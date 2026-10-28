#!/usr/bin/env bash
# Build the GUI app and the command-line tool.
# Usage: ./build.sh [lazbuild options], e.g. ./build.sh --build-mode=Release
# Toolchain overrides (LAZBUILD, LAZARUS_PCP, LCL_WIDGETSET) can go in build.local.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ -f build.local.sh ] && . ./build.local.sh
LAZBUILD="${LAZBUILD:-lazbuild}"
PCP_ARGS=()
[ -n "${LAZARUS_PCP:-}" ] && PCP_ARGS=(--pcp="$LAZARUS_PCP")

case "$(uname -s)" in
  Darwin) WS="${LCL_WIDGETSET:-cocoa}" ;;
  *)      WS="${LCL_WIDGETSET:-qt5}" ;;
esac

git submodule update --init --recursive

"$LAZBUILD" "${PCP_ARGS[@]}" -q cli/opensloper_cli.lpi "$@"
"$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$WS" opensloper.lpi "$@"
