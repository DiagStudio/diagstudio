#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
case "$(uname -s)" in
  Darwin)
    swiftc -O -framework AVFoundation -framework CoreMedia \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist \
      Sources/DiagStudio/macOS.swift -o .build/diagstudio
    ;;
  Linux)
    swiftc -O Sources/DiagStudio/Linux.swift -o .build/diagstudio
    ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
.build/diagstudio --version
