#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x .build/diagstudio ]] || ./scripts/build.sh
.build/diagstudio --version | grep -F 'DiagStudio 0.1.0'
.build/diagstudio --help | grep -F 'audio mic-test'
.build/diagstudio --help | grep -F 'camera test'
echo 'CLI smoke tests passed.'
