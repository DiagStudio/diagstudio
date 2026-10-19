#if os(Linux)
import Foundation
import Glibc

private let version = "0.2.0"

private struct ResultOutput {
    let status: Int32
    let out: Data
    let err: String
    var text: String { String(data: out, encoding: .utf8) ?? "" }
}

private func tool(_ name: String) -> String? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    return path.split(separator: ":").map { "\($0)/\(name)" }
        .first(where: { access($0, X_OK) == 0 })
}

// Read both pipes concurrently and enforce a real wall-clock timeout.
// In particular, ALSA's default input can block indefinitely on some systems.
private final class CapturedBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func set(_ data: Data) {
        lock.lock(); storage = data; lock.unlock()
    }
    var data: Data {
        lock.lock(); defer { lock.unlock() }; return storage
    }
}

private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> ResultOutput? {
    guard let path = tool(executable) else {
        print("ERROR: Missing command: \(executable)")
        return nil
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    let stdout = CapturedBytes()
    let stderr = CapturedBytes()
    let readers = DispatchGroup()
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }

    do {
        try process.run()
    } catch {
        print("ERROR: \(executable): \(error.localizedDescription)")
        return nil
    }
    // Close the parent's write ends so readers see EOF when the child exits.
    outPipe.fileHandleForWriting.closeFile()
    errPipe.fileHandleForWriting.closeFile()
    readers.enter()
    DispatchQueue.global(qos: .utility).async {
        stdout.set(outPipe.fileHandleForReading.readDataToEndOfFile())
        readers.leave()
    }
    readers.enter()
    DispatchQueue.global(qos: .utility).async {
        stderr.set(errPipe.fileHandleForReading.readDataToEndOfFile())
        readers.leave()
    }

    let expired = finished.wait(timeout: .now() + timeout) == .timedOut
    if expired {
        process.terminate()
        if finished.wait(timeout: .now() + 2) == .timedOut {
            _ = Glibc.kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
        }
    }
    // Child should have exited. Avoid indefinite reader waits if inherited
    // pipe descriptors are unexpectedly left open by another process.
    let drained = readers.wait(timeout: .now() + 2) == .success
    if !drained {
        outPipe.fileHandleForReading.closeFile()
        errPipe.fileHandleForReading.closeFile()
    }
    let errorText = String(data: stderr.data, encoding: .utf8) ?? ""
    if expired {
        return ResultOutput(status: 124, out: stdout.data,
                            err: "Timed out after \(Int(timeout)) seconds. " + errorText)
    }
    return ResultOutput(status: process.terminationStatus, out: stdout.data, err: errorText)
}

private func cameraDevices() -> [String] {
    guard let devices = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }