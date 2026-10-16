#!/usr/bin/env bash
# scripts/dev.sh
# One entry point for building, testing and checking Dial from the command
# line. Everything builds into ONE DerivedData folder (.build/DerivedData) so
# repeated runs stay incremental and don't litter the repo with copies.
#
# Usage:
#   scripts/dev.sh build                 # regenerate project + Debug build
#   scripts/dev.sh test [Class[/test]]   # full suite, or only the named tests
#   scripts/dev.sh snapshot              # visual regression tests only
#   scripts/dev.sh record                # re-record visual baselines (review the PNGs!)
#   scripts/dev.sh grid                  # render every HUD/menu bar state + contact sheet
#   scripts/dev.sh install [--no-open]   # build, copy to /Applications, relaunch
#
# Output is a short summary. Full logs: .build/logs/<command>.log
# Test results bundle: .build/results/test.xcresult
# Failed visual snapshots: .build/snapshot-failures/<name>.{actual,baseline}.png
# Every render from `snapshot` (pass or fail): .build/snapshots/<name>.png
# State grid from `grid`: .build/state-grid/<state>.png + contact-sheet.png

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DERIVED_DATA="$REPO_ROOT/.build/DerivedData"
LOG_DIR="$REPO_ROOT/.build/logs"
RESULT_BUNDLE="$REPO_ROOT/.build/results/test.xcresult"
SNAPSHOT_FAILURES="$REPO_ROOT/.build/snapshot-failures"
SNAPSHOT_RENDERS="$REPO_ROOT/.build/snapshots"
STATE_GRID="$REPO_ROOT/.build/state-grid"
RECORD_FLAG="$REPO_ROOT/DialTests/Snapshots/VisualRegression/.record"
CERT_NAME="Dial Local Dev"

mkdir -p "$LOG_DIR" "$(dirname "$RESULT_BUNDLE")"

die() { echo "✗ $*" >&2; exit 1; }

preflight() {
  command -v xcodegen >/dev/null || die "xcodegen not found. Install with: brew install xcodegen"
  if ! security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    die "Signing cert '$CERT_NAME' is missing. Run once: scripts/create-cert.sh"
  fi
  xcodegen generate --quiet >/dev/null
}

xcb() {
  xcodebuild -project Dial.xcodeproj -scheme Dial -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" "$@"
}

# Unique compiler warnings/errors as "path:line: message", repo-relative.
print_diagnostics() {
  local log="$1" kind="$2"
  grep -E "^/.*: $kind: " "$log" | sed "s|^$REPO_ROOT/||" | sort -u || true
}

cmd_build() {
  preflight
  local log="$LOG_DIR/build.log" start=$SECONDS
  echo "→ Building (Debug)"
  if ! xcb build >"$log" 2>&1; then
    print_diagnostics "$log" error
    die "Build failed after $((SECONDS - start))s. Full log: .build/logs/build.log"
  fi
  local warnings
  warnings="$(print_diagnostics "$log" warning)"
  [[ -n "$warnings" ]] && echo "$warnings"
  echo "✓ Build succeeded in $((SECONDS - start))s ($(printf '%s' "$warnings" | grep -c . || true) warnings)"
}

run_tests() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log" start=$SECONDS
  local only=()
  for t in "$@"; do only+=("-only-testing:DialTests/$t"); done

  rm -rf "$RESULT_BUNDLE" "$SNAPSHOT_FAILURES"
  echo "→ Testing${*:+ $*}"
  local status=0
  xcb test -resultBundlePath "$RESULT_BUNDLE" ${only[@]+"${only[@]}"} >"$log" 2>&1 || status=$?

  if [[ ! -d "$RESULT_BUNDLE" ]]; then
    print_diagnostics "$log" error
    die "Tests did not run (build failed?) after $((SECONDS - start))s. Full log: .build/logs/$name.log"
  fi

  xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact 2>/dev/null \
    | /usr/bin/python3 -c '
import json, sys
s = json.load(sys.stdin)
print("  %d passed, %d failed, %d skipped" % (
    s.get("passedTests", 0), s.get("failedTests", 0), s.get("skippedTests", 0)))
for f in s.get("testFailures", []):
    name = f.get("testIdentifierString") or f.get("testName")
    print("  ✗ %s: %s" % (name, f.get("failureText", "").strip()))
' || echo "  (could not read result summary; see .build/logs/$name.log)"

  local warnings
  warnings="$(print_diagnostics "$log" warning)"
  [[ -n "$warnings" ]] && echo "$warnings"

  if [[ -d "$SNAPSHOT_FAILURES" ]] && ls "$SNAPSHOT_FAILURES"/*.png >/dev/null 2>&1; then
    echo "  Visual diffs written to .build/snapshot-failures/ (open the .actual.png next to its .baseline.png)"
  fi

  if [[ $status -ne 0 ]]; then
    die "Tests failed after $((SECONDS - start))s. Full log: .build/logs/$name.log"
  fi
  echo "✓ Tests passed in $((SECONDS - start))s"
}

cmd_test() { preflight; run_tests test "$@"; }
# Export every PNG the tests attached, named by snapshot (e.g. dial-hud-aqua.png),
# so a passing render can be looked at too.
export_renders() {
  rm -rf "$SNAPSHOT_RENDERS" "$SNAPSHOT_RENDERS.raw"
  xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" \
    --output-path "$SNAPSHOT_RENDERS.raw" >/dev/null 2>&1 || return 0
  mkdir -p "$SNAPSHOT_RENDERS"
  /usr/bin/python3 - "$SNAPSHOT_RENDERS.raw" "$SNAPSHOT_RENDERS" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    for a in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]{36}(?=\.png$)", "", a["suggestedHumanReadableName"])
        shutil.copy(os.path.join(raw, a["exportedFileName"]), os.path.join(out, name))
PY
  rm -rf "$SNAPSHOT_RENDERS.raw"
  echo "  Renders: .build/snapshots/ ($(ls "$SNAPSHOT_RENDERS" | wc -l | tr -d ' ') PNGs)"
}

cmd_snapshot() {
  preflight
  local status=0
  ( run_tests snapshot VisualRegressionTests ) || status=$?
  export_renders
  return $status
}

cmd_record() {
  preflight
  touch "$RECORD_FLAG"
  trap 'rm -f "$RECORD_FLAG"' EXIT
  run_tests record VisualRegressionTests
  rm -f "$RECORD_FLAG"
  echo
  echo "Re-recorded baselines (changed files below). LOOK at each PNG before committing:"
  git status --short -- DialTests/Snapshots/VisualRegression
}

# Not a regression check: renders every state in DialTests/StateGridFixtures.swift
# so a person (or agent) can look at them side by side.
cmd_grid() {
  preflight
  rm -rf "$STATE_GRID"
  mkdir -p "$STATE_GRID"
  touch "$STATE_GRID/.render"
  trap 'rm -f "$STATE_GRID/.render"' EXIT
  run_tests grid VisualRegressionTests/test_renderStateGrid
  rm -f "$STATE_GRID/.render"
  echo "  State grid: .build/state-grid/ ($(ls "$STATE_GRID"/*.png | wc -l | tr -d ' ') PNGs). Open contact-sheet.png."
}

cmd_install() { exec "$REPO_ROOT/scripts/install.sh" "$@"; }

case "${1:-}" in
  build)    shift; cmd_build "$@" ;;
  test)     shift; cmd_test "$@" ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  record)   shift; cmd_record "$@" ;;
  grid)     shift; cmd_grid "$@" ;;
  install)  shift; cmd_install "$@" ;;
  *) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
