# DiagStudio v0.2.0 — macOS + Linux Camera and Audio Diagnostics

**Cross-platform source preview; hardware not yet validated on all four targets.**

## Support targets

- macOS x86_64 / arm64: AVFoundation camera and AVAudioEngine microphone/speaker.
- Linux x86_64 / aarch64: V4L2 camera (`v4l2-ctl`), ALSA tools (`arecord`, `aplay`) for sound.

Linux needs installed `v4l-utils` and `alsa-utils` at runtime, and Swift development tools to build from source.

**Linux limitation:** PipeWire-only and sandboxed audio setups may not expose the ALSA `default` device. The initial Linux backend uses ALSA compatibility and does not yet implement native PipeWire APIs. `/dev/video*` can include metadata and non-capture endpoints; the initial camera list may show such nodes. Tests should be performed with compatible physical devices. `v4l2-ctl --stream-mmap` doesn't work with every V4L2 driver or format.

## Build

```bash
bash scripts/build.sh
bash scripts/smoke-test.sh
```

For Ubuntu Linux install tools with:

```bash
sudo apt-get update
sudo apt-get install -y v4l-utils alsa-utils
```

Install Swift from official toolchain instructions for your distro/architecture; `swiftc --version` must work before build.

## Commands

```bash
.build/diagstudio --version
.build/diagstudio --help
.build/diagstudio camera list
.build/diagstudio camera permission
.build/diagstudio camera test --device 0 --seconds 5
.build/diagstudio audio list
.build/diagstudio audio permission
.build/diagstudio audio mic-test --seconds 10
.build/diagstudio audio speaker-test
.build/diagstudio report
```

On Linux camera capture streams to v4l2-ctl but does not save frames. Microphone PCM is piped into the app's memory to calculate peak/RMS and is not saved. The speaker tone is a temporary WAV removed after playback. No samples are uploaded.

Camera, mic, and speaker tests require user-approved device access; a success report proves software interaction, **not full physical device health**.

## Homebrew

`homebrew-formula-example/diagstudio.rb` is a non-publishable template until version `v0.2.0` exists and its checksum, license, and dependencies are validated. Homebrew package names for Linux CLI dependencies may vary; validate names for the tap and supported host platform. Do not copy blindly.

After validating on all four targets, publish the version tag, compute SHA256, finalize the formula in `DiagStudio/homebrew-tools/Formula/diagstudio.rb`, audit and test on target systems.

**Note on deployment:** macOS compilation embeds `Info.plist` for camera/mic permission prompts. A CLI launched from Terminal may be governed by the terminal application's own privacy permissions.

## Migration from existing repository

Replace old `Sources/DiagStudio/main.swift` with the provided platform-specific files; do not leave the old `main.swift` in the same compile target. Back up existing changes first and run tests before publishing. Keep your repository's existing license (if present).
