import Foundation
import AVFoundation
import CoreMedia

// DiagStudio 0.1.0 — native macOS camera and audio diagnostics.
// No camera frames or microphone samples are saved or transmitted.
private let version = "0.2.0"

private func permissionName(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "authorized"
    case .denied: return "denied (System Settings > Privacy & Security)"
    case .restricted: return "restricted by system policy"
    case .notDetermined: return "not requested"
    @unknown default: return "unknown"
    }
}

private func cameras() -> [AVCaptureDevice] {
    let types: [AVCaptureDevice.DeviceType]

    if #available(macOS 14.0, *) {
        types = [.builtInWideAngleCamera, .external]
    } else {
        types = [.builtInWideAngleCamera, .externalUnknown]
    }

    return AVCaptureDevice.DiscoverySession(
        deviceTypes: types,
        mediaType: .video,
        position: .unspecified
    ).devices
}

private func microphones() -> [AVCaptureDevice] {
    let types: [AVCaptureDevice.DeviceType]

    if #available(macOS 14.0, *) {
        types = [.microphone, .external]
    } else {
        types = [.builtInMicrophone, .externalUnknown]
    }

    return AVCaptureDevice.DiscoverySession(
        deviceTypes: types,
        mediaType: .audio,
        position: .unspecified
    ).devices
}

private func authorization(for media: AVMediaType) -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: media) {
    case .authorized: return true
    case .denied, .restricted: return false
    case .notDetermined:
        let sem = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: media) { allowed in
            granted = allowed
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 60) == .success else {
            print("Timed out waiting for macOS permission prompt.")
            return false
        }
        return granted
    @unknown default: return false
    }
}

private final class VideoCounter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var _frames: Int = 0
    var frames: Int {
        lock.lock(); defer { lock.unlock() }
        return _frames
    }
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock(); _frames += 1; lock.unlock()
    }
}

private func cameraTest(index: Int, seconds: TimeInterval) -> Bool {
    let found = cameras()
    guard found.indices.contains(index) else {
        print("ERROR: No camera at index \(index). Run: diagstudio camera list")
        return false
    }
    guard authorization(for: .video) else {
        print("ERROR: Camera access denied. Enable camera access for the terminal app in System Settings > Privacy & Security > Camera.")
        return false
    }
    let device = found[index]
    print("Testing camera: \(device.localizedName) for \(Int(seconds)) seconds")
    let session = AVCaptureSession()
    let counter = VideoCounter()
    let queue = DispatchQueue(label: "diagstudio.video.frames")
    do {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { print("ERROR: Cannot add camera input"); return false }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(counter, queue: queue)
        guard session.canAddOutput(output) else { print("ERROR: Cannot add video output"); return false }
        session.addOutput(output)
        session.startRunning() // Synchronous; might take a moment.
        guard session.isRunning else { print("ERROR: Camera session did not start"); return false }
        Thread.sleep(forTimeInterval: seconds)
        session.stopRunning()
        let count = counter.frames
        print("Frames received: \(count)")
        if count > 0 {
            print("PASS: Camera delivered video frames (not saved).")
            return true
        }
        print("FAIL: Camera connected but delivered no video frames.")
        return false
    } catch {
        print("ERROR: Camera capture failed: \(error.localizedDescription)")
        return false
    }
}

private final class AudioMeter {
    private let lock = NSLock()
    private var buffers = 0
    private var emptyBuffers = 0
    private var unsupportedBuffers = 0
    private var peak: Float = 0
    private var sumOfSquares: Double = 0
    private var sampleCount: Int64 = 0

    var snapshot: (buffers: Int, empty: Int, unsupported: Int, peak: Float, rms: Double, samples: Int64) {
        lock.lock()
        defer { lock.unlock() }
        let rms = sampleCount > 0 ? sqrt(sumOfSquares / Double(sampleCount)) : 0
        return (buffers, emptyBuffers, unsupportedBuffers, peak, rms, sampleCount)
    }

    func measure(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frames > 0, channelCount > 0 else {
            lock.lock(); emptyBuffers += 1; lock.unlock()
            return
        }

        // AVAudioEngine typically supplies Float32 PCM. Never reinterpret integer
        // data as floats: that would produce meaningless measurements.
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData else {
            lock.lock(); unsupportedBuffers += 1; lock.unlock()
            return
        }

        var localPeak: Float = 0
        var localSum: Double = 0
        var localSamples: Int64 = 0
        for channel in 0..<channelCount {
            for frame in 0..<frames {
                let sample = channels[channel][frame]
                guard sample.isFinite else { continue }
                localPeak = max(localPeak, abs(sample))
                localSum += Double(sample) * Double(sample)
                localSamples += 1
            }
        }

        lock.lock()
        buffers += 1
        peak = max(peak, localPeak)
        sumOfSquares += localSum
        sampleCount += localSamples
        lock.unlock()
    }
}

private func audioDecibels(_ linear: Double) -> String {
    guard linear > 0 else { return "-inf dBFS" }
    return String(format: "%.1f dBFS", 20 * log10(linear))
}

private func microphoneTest(seconds: TimeInterval) -> Bool {
    guard authorization(for: .audio) else {
        print("ERROR: Microphone permission denied. Enable access in System Settings > Privacy & Security > Microphone.")
        return false
    }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
        print("ERROR: No valid microphone input format available.")
        return false
    }

    print("Input format: \(Int(format.sampleRate)) Hz, \(format.channelCount) channel(s), \(format.commonFormat.rawValue), interleaved: \(format.isInterleaved)")
    if format.commonFormat != .pcmFormatFloat32 {
        print("ERROR: This test expects Float32 PCM from AVAudioEngine. Actual format: \(format)")
        return false
    }

    let meter = AudioMeter()
    print("Testing microphone for \(Int(seconds)) seconds. Speak normally...")
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        meter.measure(buffer)
    }
    defer {
        input.removeTap(onBus: 0)
        engine.stop()
    }

    do {
        try engine.start()
        Thread.sleep(forTimeInterval: seconds)
        engine.stop()
        let data = meter.snapshot
        print("Audio buffers received: \(data.buffers)")
        print("Empty buffers: \(data.empty)")
        print("Unsupported-format buffers: \(data.unsupported)")
        print("Samples measured: \(data.samples)")
        print(String(format: "Peak input level: %.6f (%@)", data.peak, audioDecibels(Double(data.peak))))
        print(String(format: "RMS input level: %.6f (%@)", data.rms, audioDecibels(data.rms)))

        guard data.buffers > 0, data.samples > 0 else {
            print("FAIL: No usable audio samples received. Check input format, microphone selection and privacy settings.")
            return false
        }
        if data.peak < 0.001 {
            print("WARNING: Capture is active but audio is very quiet or silent.")
            print("Check System Settings > Sound > Input, input volume, microphone mute, and whether the input-level meter moves when speaking.")
            print("If macOS detects sound but DiagStudio does not, inspect the selected input route and audio engine behavior.")
            return false
        }
        print("PASS: Microphone delivered non-silent audio samples (not saved).")
        return true
    } catch {
        print("ERROR: Microphone input could not start: \(error.localizedDescription)")
        return false
    }
}

private func speakerTest() -> Bool {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let sampleRate = 44_100.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate)) else {
        print("ERROR: Could not create output audio buffer.")
        return false
    }
    buffer.frameLength = buffer.frameCapacity
    guard let samples = buffer.floatChannelData?[0] else { return false }
    for i in 0..<Int(buffer.frameLength) {
        // Modest volume with short fade-in/out to avoid clicks.
        let t = Double(i) / sampleRate
        let envelope = min(1, min(t / 0.04, (1.0 - t) / 0.04))
        samples[i] = Float(0.18 * max(0, envelope) * sin(2 * Double.pi * 440 * t))
    }
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    do {
        try engine.start()
        player.scheduleBuffer(buffer)
        print("Playing a 440 Hz test tone for one second. Check your selected system output device.")
        player.play()
        Thread.sleep(forTimeInterval: 1.25)
        player.stop()
        engine.stop()
        print("Playback request completed. Confirm that you actually heard the tone.")
        return true // Playback succeeded, but cannot prove sound was audible.
    } catch {
        print("ERROR: Could not play tone: \(error.localizedDescription)")
        return false
    }
}

private func listDevices(_ items: [AVCaptureDevice], label: String) {
    if items.isEmpty { print("No \(label) devices found."); return }
    for (index, item) in items.enumerated() {
        print("[\(index)] \(item.localizedName) | id: \(item.uniqueID)")
    }
}

private func report() {
    let process = ProcessInfo.processInfo
    print("DiagStudio \(version) — Diagnostic Report")
    print("macOS: \(process.operatingSystemVersionString)")
    print("Camera permission: \(permissionName(AVCaptureDevice.authorizationStatus(for: .video)))")
    print("Microphone permission: \(permissionName(AVCaptureDevice.authorizationStatus(for: .audio)))")
    print("Cameras: \(cameras().count)")
    listDevices(cameras(), label: "camera")
    print("Microphones: \(microphones().count)")
    listDevices(microphones(), label: "microphone")
    print("Note: Device visibility and authorization do not prove hardware health.")
    print("No captures were started, stored, or uploaded while generating this report.")
}

private func help() {
    print("""
    DiagStudio \(version) — macOS Camera & Audio Diagnostics

    Usage:
      diagstudio --version
      diagstudio --help
      diagstudio camera list
      diagstudio camera permission
      diagstudio camera test [--device N] [--seconds N]
      diagstudio audio list
      diagstudio audio permission
      diagstudio audio mic-test [--seconds N]
      diagstudio audio speaker-test
      diagstudio report

    Permission prompts appear only during capture tests.
    No video or audio is saved or sent anywhere.
    """)
}

private func secondsArgument(_ arguments: [String], fallback: Int = 5) -> Int? {
    guard let pos = arguments.firstIndex(of: "--seconds") else { return fallback }
    guard arguments.indices.contains(pos + 1), let n = Int(arguments[pos + 1]), (1...30).contains(n) else {
        print("ERROR: --seconds must be between 1 and 30")
        return nil
    }
    return n
}

private func indexArgument(_ arguments: [String]) -> Int? {
    guard let pos = arguments.firstIndex(of: "--device") else { return 0 }
    guard arguments.indices.contains(pos + 1), let n = Int(arguments[pos + 1]), n >= 0 else {
        print("ERROR: --device must be a nonnegative index")
        return nil
    }
    return n
}

let args = Array(CommandLine.arguments.dropFirst())
let result: Bool
switch args.first {
case "--version", "-v":
    print("DiagStudio \(version)")
    result = true
case "--help", "-h", nil:
    help()
    result = true
case "camera":
    switch args.dropFirst().first {
    case "list": listDevices(cameras(), label: "camera"); result = true
    case "permission": print(permissionName(AVCaptureDevice.authorizationStatus(for: .video))); result = true
    case "test":
        if let index = indexArgument(args), let seconds = secondsArgument(args) {
            result = cameraTest(index: index, seconds: Double(seconds))
        } else { result = false }
    default: help(); result = false
    }
case "audio":
    switch args.dropFirst().first {
    case "list": listDevices(microphones(), label: "microphone"); result = true
    case "permission": print(permissionName(AVCaptureDevice.authorizationStatus(for: .audio))); result = true
    case "mic-test":
        if let seconds = secondsArgument(args) { result = microphoneTest(seconds: Double(seconds)) }
        else { result = false }
    case "speaker-test": result = speakerTest()
    default: help(); result = false
    }
case "report": report(); result = true
default: help(); result = false
}
exit(result ? 0 : 1)
