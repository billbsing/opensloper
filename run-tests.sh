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

"$LAZBUILD" "${PCP_ARGS[@]}" -q tests/opensloper_tests.lpi

HEAPLOG="$(mktemp)"
trap 'rm -f "$HEAPLOG"' EXIT
rm -f "$HEAPLOG"
status=0
HEAPTRC="log=$HEAPLOG" ./tests/opensloper_tests --all --format=plain "$@" || status=$?

if [ "$status" -ne 0 ]; then
  echo "Tests failed (exit $status)" >&2
  exit "$status"
fi
if ! grep -q '^0 unfreed memory blocks' "$HEAPLOG" 2>/dev/null; then
  cat "$HEAPLOG" >&2 2>/dev/null || echo "No heaptrc report was written" >&2
  echo "heaptrc reported memory leaks" >&2
  exit 1
fi
echo "All tests passed, no leaks."
