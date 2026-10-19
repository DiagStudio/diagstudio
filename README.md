# DiagStudio — Camera & Audio Diagnostics for macOS

A native Swift CLI to inspect detected webcams and microphones, check macOS authorization, test camera video frame delivery, measure microphone input (without recording), and play a one-second speaker test tone.

**Status: v0.1.0 starter, not yet validated on macOS hardware.** This tool tests basic software-level functionality; it cannot conclusively diagnose physical camera/microphone component failures. It does not automatically fix faults.

## Requirements

- macOS 13+ recommended
- Xcode / Xcode Command Line Tools and Swift
- A real Mac with webcam and/or microphone for hardware tests

## Build and run

```bash
xcode-select --install    # only if development tools are missing
./scripts/build.sh
./scripts/smoke-test.sh
.build/diagstudio --help
```

## Commands

```bash
.build/diagstudio --version
.build/diagstudio camera list
.build/diagstudio camera permission
.build/diagstudio camera test
.build/diagstudio camera test --device 0 --seconds 5
.build/diagstudio audio list
.build/diagstudio audio permission
.build/diagstudio audio mic-test --seconds 5
.build/diagstudio audio speaker-test
.build/diagstudio report
```

Device indices start at zero. For the first version, microphone testing uses the **macOS default input**, and speaker testing uses the **macOS default output**. Select them using System Settings > Sound. Camera testing lets you choose one of the discovered devices.

## Privacy and permissions

Camera and microphone access are requested only when you run the corresponding capture test. `Info.plist` is embedded into the CLI executable by the build script. Depending on how Terminal is launched and macOS TCC behavior, privacy prompts/settings may identify the hosting terminal. If permission was denied, go to **System Settings > Privacy & Security > Camera** or **Microphone**. A packaged and signed application may offer more consistent permission identity for distribution.

The tool never writes audio recordings, camera images, or videos to disk, and contains no networking code. It prints device identifiers in the local terminal; avoid publicly posting diagnostic output if device metadata is sensitive.

**Audio speaker test:** A successful play request does not prove that you heard sound. The tool asks you to confirm audibility yourself.

## Source layout

```
Sources/DiagStudio/main.swift  # CLI, capture sessions, audio tests
Info.plist                     # macOS privacy descriptions
scripts/build.sh               # native macOS binary build
scripts/smoke-test.sh          # CLI smoke tests
.github/workflows/ci.yml       # GitHub-hosted macOS compile/test
homebrew-formula-example/      # draft formula; do not publish until release
```

## GitHub + Homebrew

1. Push this source project to `DiagStudio/diagstudio` (retain your repository's LICENSE; use MIT only if that is your license).
2. Run `./scripts/build.sh` and live hardware tests on macOS.
3. Publish Git tag `v0.1.0` after successful verification.
4. Download `https://github.com/DiagStudio/diagstudio/archive/refs/tags/v0.1.0.tar.gz` and run `shasum -a 256 <archive>`.
5. Update `homebrew-formula-example/diagstudio.rb` with the real hash, verify licensing and build dependencies, then copy to `DiagStudio/homebrew-tools/Formula/diagstudio.rb`.
6. Test `brew install diagstudio/tools/diagstudio` on a Mac and run `brew test diagstudio/tools/diagstudio`.

**Note:** The sample formula uses `:xcode` because it compiles Swift source. It may require adjustments for the exact installed SDK/Swift toolchain and Homebrew audit rules; it has not been verified in this environment. The `brew install diagstudio` short name works after the user taps `diagstudio/tools` and any applicable Homebrew trust policy is satisfied.

## Limitations and next steps

- Mic test uses default input, not a selected mic ID.
- Speaker test is subjective; it cannot read back whether the tone was audible.
- No frame quality, focus, exposure, latency, frequency-response, or USB hardware health assessment yet.
- Audio engine input tap requires a functioning audio device/driver and may be denied by privacy settings.
- Requires testing on actual Macs and different OS/hardware versions before production use.
