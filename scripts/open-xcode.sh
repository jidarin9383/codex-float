#!/bin/zsh
# Open Codex Float as a Swift package in full Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Xcode not found at $DEVELOPER_DIR" >&2
  exit 1
fi

# Prefer permanent switch when already configured; otherwise this shell still works.
if [[ "$(xcode-select -p 2>/dev/null)" != "$DEVELOPER_DIR" ]]; then
  echo "Note: active developer dir is not Xcode."
  echo "One-time fix (needs password):"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "Using DEVELOPER_DIR=$DEVELOPER_DIR for this open."
fi

open -a Xcode "$ROOT/Package.swift"
echo "Opened Package.swift in Xcode."
echo "Scheme: CodexFloat  →  Run (⌘R). Destination: My Mac."
