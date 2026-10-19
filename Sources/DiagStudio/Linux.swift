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

private func run(_ executable: String, _ arguments: [String]) -> ResultOutput? {
    guard let path = tool(executable) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
        // Tests capture only bounded durations/amounts; avoid stdout pipe deadlock.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ResultOutput(status: process.terminationStatus, out: data,
                            err: String(data: error, encoding: .utf8) ?? "")
    } catch {
        print("ERROR: \(executable): \(error.localizedDescription)")
        return nil
    }
}

private func cameraDevices() -> [String] {
    guard let devices = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }
    return devices.filter { $0.range(of: #"^video[0-9]+$"#, options: .regularExpression) != nil }
        .map { "/dev/\($0)" }.sorted()
}

private func cameraList() {
    let devices = cameraDevices()
    if devices.isEmpty { print("No /dev/video* devices detected."); return }
    for (i, d) in devices.enumerated() {
        let info = run("v4l2-ctl", ["-d", d, "--info"])
        let card = info?.text.split(separator: "\n").first(where: { $0.contains("Card type") })?.trimmingCharacters(in: .whitespaces) ?? ""
        print("[\(i)] \(d) \(card)")
    }
}

private func cameraTest(_ index: Int, seconds: Int) -> Bool {
    let devices = cameraDevices()
    guard devices.indices.contains(index) else { print("ERROR: Invalid camera index; run camera list"); return false }
    guard tool("v4l2-ctl") != nil else { print("ERROR: Install v4l-utils (v4l2-ctl)"); return false }
    let device = devices[index]
    // Streaming without writing frames to a file.
    let count = max(1, min(300, seconds * 15))
    guard let result = run("v4l2-ctl", ["-d", device, "--stream-mmap", "--stream-count=\(count)"]) else { return false }
    print("Testing camera \(device) for up to \(count) frames")
    if result.status == 0 { print("PASS: V4L2 streaming completed. No frames saved."); return true }
    print("FAIL: V4L2 capture failed: \(result.err.trimmingCharacters(in: .whitespacesAndNewlines))")
    return false
}

private func microphones() -> Bool {
    guard let r = run("arecord", ["-l"]) else { print("ERROR: arecord missing. Install alsa-utils."); return false }
    print(r.text.isEmpty ? r.err : r.text)
    return r.status == 0
}

private func inputsPermission() {
    print("Linux device access uses /dev permissions, groups, udev and/or PipeWire/PulseAudio policy.")
    print("Run 'diagstudio audio list' and perform a capture test to validate access.")
}

private func micTest(seconds: Int) -> Bool {
    guard tool("arecord") != nil else { print("ERROR: Install alsa-utils (arecord)"); return false }
    print("Testing default ALSA microphone for \(seconds) seconds. Speak normally...")
    // Capture bounded 16-bit little-endian mono PCM to a pipe, not a recorded file.
    guard let result = run("arecord", ["-q", "-D", "default", "-t", "raw", "-f", "S16_LE", "-c", "1", "-r", "16000", "-d", "\(seconds)"]) else { return false }
    guard result.status == 0 else {
        print("FAIL: arecord: \(result.err.trimmingCharacters(in: .whitespacesAndNewlines))"); return false
    }
    let samples = result.out.count / 2
    guard samples > 0 else { print("FAIL: No microphone samples received"); return false }
    var peak = 0.0
    var sumSq = 0.0
    result.out.withUnsafeBytes { bytes in
        let raw = bytes.bindMemory(to: UInt8.self)
        for i in 0..<samples {
            let unsigned = UInt16(raw[2 * i]) | (UInt16(raw[2 * i + 1]) << 8)
            let value = Double(Int16(bitPattern: unsigned)) / 32768.0
            peak = max(peak, abs(value))
            sumSq += value * value
        }
    }
    let rms = sqrt(sumSq / Double(samples))
    print("Samples: \(samples)")
    print(String(format: "Peak input level: %.6f", peak))
    print(String(format: "RMS input level: %.6f", rms))
    if peak < 0.001 { print("WARNING: Signal is nearly silent; verify input routing and levels."); return false }
    print("PASS: Microphone delivered a nonzero signal (not saved).")
    return true
}

private func speakerTest() -> Bool {
    guard tool("aplay") != nil else { print("ERROR: Install alsa-utils (aplay)"); return false }
    let rate = 44100
    var wav = Data()
    func u16(_ x: UInt16) { wav.append(UInt8(x & 255)); wav.append(UInt8(x >> 8)) }
    func u32(_ x: UInt32) { u16(UInt16(x & 65535)); u16(UInt16(x >> 16)) }
    func chunk(_ x: String) { wav.append(contentsOf: x.utf8) }
    chunk("RIFF"); u32(UInt32(36 + rate * 2)); chunk("WAVEfmt "); u32(16)
    u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    chunk("data"); u32(UInt32(rate * 2))
    for i in 0..<rate {
        let t = Double(i) / Double(rate)
        let fade = min(1, min(t / 0.04, (1 - t) / 0.04))
        let value = Int16(0.18 * max(0, fade) * sin(2 * Double.pi * 440 * t) * 32767)
        u16(UInt16(bitPattern: value))
    }
    let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diagstudio-\(UUID().uuidString).wav")
    do { try wav.write(to: path); defer { try? FileManager.default.removeItem(at: path) }
        print("Playing 440 Hz test tone. Confirm audibility yourself.")
        guard let r = run("aplay", ["-q", path.path]) else { return false }
        if r.status != 0 { print("FAIL: \(r.err)"); return false }
        print("Playback completed; hardware audibility not automatically verified.")
        return true
    } catch { print("FAIL: \(error)"); return false }
}

private func report() {
    print("DiagStudio \(version) — Linux Diagnostic Report")
    print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Architecture: \(run("uname", ["-m"])?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown")")
    print("Camera nodes: \(cameraDevices().count)")
    cameraList()
    print("Microphones (ALSA):")
    _ = microphones()
    print("Permissions and device discovery alone do not establish physical hardware health.")
}

private func help() {
    print("""
    DiagStudio \(version) — camera & audio diagnostics (Linux)
    Usage:
      diagstudio --version | --help
      diagstudio camera list | permission | test [--device N] [--seconds N]
      diagstudio audio list | permission | mic-test [--seconds N] | speaker-test
      diagstudio report
    Device streams are not retained or uploaded. Speaker test uses a temporary tone WAV removed after playback.
    """)
}

private func option(_ flag: String, args: [String], default fallback: Int, bounds: ClosedRange<Int>) -> Int? {
    guard let pos = args.firstIndex(of: flag) else { return fallback }
    guard pos + 1 < args.count, let n = Int(args[pos+1]), bounds.contains(n) else {
        print("ERROR: \(flag) must be between \(bounds.lowerBound) and \(bounds.upperBound)"); return nil
    }
    return n
}

let args = Array(CommandLine.arguments.dropFirst())
let action = args.first ?? "--help"
var success = true
switch action {
case "--version", "-v": print("DiagStudio \(version)")
case "--help", "-h": help()
case "camera":
    switch args.dropFirst().first {
    case "list": cameraList()
    case "permission": print("Linux camera access is governed by /dev/video* permissions; run camera test to verify access.")
    case "test":
        if let idx = option("--device", args: args, default: 0, bounds: 0...1000),
           let secs = option("--seconds", args: args, default: 5, bounds: 1...30) {
            success = cameraTest(idx, seconds: secs)
        } else { success = false }
    default: help(); success = false
    }
case "audio":
    switch args.dropFirst().first {
    case "list": success = microphones()
    case "permission": inputsPermission()
    case "mic-test":
        if let secs = option("--seconds", args: args, default: 5, bounds: 1...30) { success = micTest(seconds: secs) }
        else { success = false }
    case "speaker-test": success = speakerTest()
    default: help(); success = false
    }
case "report": report()
default: help(); success = false
}
exit(success ? 0 : 1)
#endif
