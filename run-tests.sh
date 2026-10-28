#!/usr/bin/env bash
# Build and run the OpenSloper test suite. Run before every commit.
# Toolchain overrides (LAZBUILD, LAZARUS_PCP) can go in build.local.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ -f build.local.sh ] && . ./build.local.sh
LAZBUILD="${LAZBUILD:-lazbuild}"
PCP_ARGS=()
[ -n "${LAZARUS_PCP:-}" ] && PCP_ARGS=(--pcp="$LAZARUS_PCP")

git submodule update --init --recursive

# -B: lazbuild compares file times to the second, so an edit made in the
# same second as the last build could otherwise be skipped
"$LAZBUILD" "${PCP_ARGS[@]}" -q -B tests/opensloper_tests.lpi

HEAPLOG="$(mktemp)"
RESULTS="$(mktemp)"
trap 'rm -f "$HEAPLOG" "$RESULTS"' EXIT
rm -f "$HEAPLOG"
set +e
HEAPTRC="log=$HEAPLOG" ./tests/opensloper_tests --all --format=plain "$@" 2>&1 | tee "$RESULTS"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  echo "Tests failed (exit $status)" >&2
  exit "$status"
fi
# The runner can stop early (an exception outside a test) and still exit 0,
# so require its summary too
if ! grep -q '^Number of errors: *0$' "$RESULTS" || ! grep -q '^Number of failures: *0$' "$RESULTS"; then
  echo "Tests did not finish or did not pass" >&2
  exit 1
fi
if ! grep -q '^0 unfreed memory blocks' "$HEAPLOG" 2>/dev/null; then
  cat "$HEAPLOG" >&2 2>/dev/null || echo "No heaptrc report was written" >&2
  echo "heaptrc reported memory leaks" >&2
  exit 1
fi
echo "All tests passed, no leaks."
