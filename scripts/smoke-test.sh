#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
.build/diagstudio --version | grep -q 'DiagStudio '
.build/diagstudio --help | grep -q 'camera'
.build/diagstudio --help | grep -q 'audio'
echo 'CLI smoke tests passed.'
