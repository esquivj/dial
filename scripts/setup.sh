#!/usr/bin/env bash
# Bootstrap the Dial dev environment.
# - Verifies Xcode + xcodegen are installed
# - Generates Dial.xcodeproj from project.yml
# - Reminds you to set your Spotify Client ID (Config/Dial.local.xcconfig)

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

if [[ ! -f Config/Dial.local.xcconfig ]]; then
  cat <<'EOM'

⚠  No Config/Dial.local.xcconfig yet. Copy Config/Dial.local.xcconfig.example
   to it and set SPOTIFY_CLIENT_ID to your Spotify app's Client ID. Builds and
   tests work without it, but scripts/install.sh won't install a build that
   can't sign in to Spotify.

EOM
fi

echo "✓ Done. Open Dial.xcodeproj or run: xcodebuild -scheme Dial -destination 'platform=macOS' build"
