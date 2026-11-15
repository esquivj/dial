#!/usr/bin/env bash
# scripts/backup-and-install.sh
# Back up this Mac's Dial database and app, check the backup, then install
# the checked-out commit with `scripts/dev.sh install`.
#
# Backups go to ~/Library/Application Support/Dial-backups/<date>-before-<commit>.
# An existing folder is never reused: a second run gets a -2, -3... suffix.
#
# Every step either succeeds or stops the script with
#     INSTALL_FAILED: <step>
# Success ends with the installed commit, Dial's pid, and
#     INSTALL_DONE
# so a remote caller (a Rex pane on the mini) can wait for either marker.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$HOME/Library/Application Support/Dial"
BACKUPS="$HOME/Library/Application Support/Dial-backups"
APP="/Applications/Dial.app"

step="start"
trap 'echo "INSTALL_FAILED: $step"' ERR

cd "$REPO_ROOT"
commit="$(git rev-parse --short=7 HEAD)"

step="choose backup folder"
base="$BACKUPS/$(date +%Y-%m-%d)-before-$commit"
dest="$base"
n=2
while [ -e "$dest" ]; do
  dest="$base-$n"
  n=$((n + 1))
done
mkdir -p "$dest"
echo "→ Backing up to $dest"

step="back up database"
if [ -f "$DATA_DIR/dial.sqlite" ]; then
  # .backup takes a consistent copy even while Dial is writing.
  sqlite3 "$DATA_DIR/dial.sqlite" ".backup \"$dest/dial.sqlite\""

  step="check backup integrity"
  # Not -readonly: on the mini, a read-only open of the fresh copy failed
  # with "unable to open database file (14)"; a plain open works on both.
  # -list keeps the answer a bare "ok" whatever the local output mode.
  result="$(sqlite3 -batch -noheader -list "$dest/dial.sqlite" 'PRAGMA integrity_check;')"
  if [ "$result" != "ok" ]; then
    echo "$result" | head -5
    false
  fi
  echo "  integrity: ok"
else
  echo "  no database yet; skipping"
fi

step="back up app"
if [ -d "$APP" ]; then
  ditto "$APP" "$dest/Dial.app"
  echo "  app: copied"
fi

step="install"
scripts/dev.sh install

step="confirm install"
installed="$(plutil -extract DialGitCommit raw "$APP/Contents/Info.plist")"
if [ "$installed" != "$commit" ]; then
  echo "  installed $installed, expected $commit"
  false
fi
pid="$(pgrep -x Dial || true)"
if [ -z "$pid" ]; then
  echo "  Dial isn't running"
  false
fi
echo "Installed $installed, Dial pid $pid"
echo "INSTALL_DONE"
