#!/usr/bin/env bash
# Bootstrap the Dial dev environment.
# - Verifies Xcode + xcodegen are installed
# - Generates Dial.xcodeproj from project.yml
# - Reminds about local secrets (.env.local)

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null; then
  echo "✗ Xcode is not installed (or xcode-select points at Command Line Tools)."
  echo "  Install Xcode from the App Store, then run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "    sudo xcodebuild -license accept"
  exit 1
fi

if ! command -v xcodegen >/dev/null; then
  echo "✗ xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi

echo "→ Generating Dial.xcodeproj from project.yml…"
xcodegen generate

if [[ ! -f .env.local ]]; then
  cat <<'EOM'

⚠  No .env.local found. The Spotify Client ID is currently embedded in project.yml
   for personal-use convenience. For shared/CI environments, move it to .env.local
   and inject via xcconfig at build time.

EOM
fi

echo "✓ Done. Open Dial.xcodeproj or run: xcodebuild -scheme Dial -destination 'platform=macOS' build"
