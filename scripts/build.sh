#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: This project must be built on macOS." >&2
  exit 1
fi
mkdir -p .build
swiftc -O -framework AVFoundation -framework CoreMedia \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker Info.plist \
  Sources/DiagStudio/main.swift -o .build/diagstudio
printf 'Built %s\n' "$(pwd)/.build/diagstudio"
.build/diagstudio --version
