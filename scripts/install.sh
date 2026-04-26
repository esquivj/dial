#!/usr/bin/env bash
# scripts/install.sh
# One-command "build, install to /Applications, relaunch" for Dial.
#
# Why this exists: macOS TCC tracks Screen Recording permission by code
# signature, and Xcode's per-build ad-hoc signatures change every time —
# so reinstalling under /Applications/Dial.app (a stable path) is the
# closest thing we get to "permission persists." Combined with a real
# DEVELOPMENT_TEAM in project.yml (Apple Development cert), TCC actually
# recognizes the rebuild as the same app and keeps the grant.
#
# Usage:
#     ./scripts/install.sh           # build + install + open
#     ./scripts/install.sh --no-open # build + install (don't relaunch)
#
# Errors out cleanly on each failure so you don't end up with a half-
# installed app silently.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Dial"
DEST="/Applications/${APP_NAME}.app"

cd "$REPO_ROOT"

# 1. Regenerate Xcode project from project.yml — picks up any source files
#    added since the last generate. Cheap, idempotent.
echo "→ Regenerating Xcode project"
xcodegen generate >/dev/null

# 2. Build. xcodebuild output is verbose; only show the lines that matter.
echo "→ Building Debug configuration"
BUILD_LOG=$(mktemp)
trap "rm -f $BUILD_LOG" EXIT
if ! xcodebuild -project "${APP_NAME}.xcodeproj" \
                -scheme "${APP_NAME}" \
                -configuration Debug \
                -allowProvisioningUpdates \
                build > "$BUILD_LOG" 2>&1; then
  echo "✗ Build failed. Tail of log:"
  tail -30 "$BUILD_LOG"
  exit 1
fi

# Surface any warnings without dumping the whole build transcript.
WARNINGS=$(grep -c "warning:" "$BUILD_LOG" || true)
if [ "$WARNINGS" -gt 0 ]; then
  echo "  (built with $WARNINGS warning(s))"
fi

# 3. Locate the freshly built .app under DerivedData.
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/Debug \
  -name "${APP_NAME}.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
  echo "✗ Could not find ${APP_NAME}.app under DerivedData after a successful build"
  exit 1
fi

echo "  Built: $APP_PATH"

# 4. Kill any running instance — both the /Applications copy and any
#    that's been launched directly out of DerivedData.
echo "→ Stopping running ${APP_NAME} (if any)"
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5  # give the process a moment to actually terminate

# 5. Replace /Applications/Dial.app atomically-ish.
echo "→ Installing to ${DEST}"
rm -rf "$DEST"
cp -R "$APP_PATH" "$DEST"

# 6. Relaunch unless --no-open passed.
if [ "${1:-}" != "--no-open" ]; then
  echo "→ Relaunching"
  open "$DEST"
fi

echo "✓ Done."
