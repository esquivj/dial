#!/bin/sh
# Records which commit a build came from, so `plutil` or Settings can tell
# any installed Dial apart. Runs as an Xcode post-build phase (project.yml),
# after Info.plist is processed and before the app is signed.
#
# Keys written to the built app's Info.plist:
#   DialGitCommit  short SHA of HEAD, or "unknown" outside a git checkout
#   DialGitDirty   true when the tree had uncommitted changes (ignored files aside)
#   DialBuildDate  build time, ISO 8601 UTC
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
buddy=/usr/libexec/PlistBuddy

commit=unknown
dirty=false
if command -v git >/dev/null 2>&1 && git -C "${SRCROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  commit=$(git -C "${SRCROOT}" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
  if [ -n "$(git -C "${SRCROOT}" status --porcelain 2>/dev/null)" ]; then
    dirty=true
  fi
fi
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)

set_key() {
  "$buddy" -c "Delete :$1" "$plist" >/dev/null 2>&1 || true
  "$buddy" -c "Add :$1 $2 $3" "$plist"
}
set_key DialGitCommit string "$commit"
set_key DialGitDirty bool "$dirty"
set_key DialBuildDate string "$built"

echo "Stamped ${commit}$([ "$dirty" = true ] && echo ' (dirty)') built ${built}"
