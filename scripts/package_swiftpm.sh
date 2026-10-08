#!/usr/bin/env bash
# iPad に持っていくための SiliconFlowLab.swiftpm.zip を dist/ に作ります。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/SiliconFlowLab.swiftpm.zip"
cd "$ROOT"
zip -r -q "dist/SiliconFlowLab.swiftpm.zip" "SiliconFlowLab.swiftpm" \
  -x "SiliconFlowLab.swiftpm/.build/*" \
  -x "SiliconFlowLab.swiftpm/.swiftpm/*" \
  -x "*.DS_Store"
unzip -l "dist/SiliconFlowLab.swiftpm.zip" | tail -1
ls -la "dist/SiliconFlowLab.swiftpm.zip"
