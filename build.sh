#!/usr/bin/env bash
# Build the GUI apps and the command-line tool.
# Usage: ./build.sh [lazbuild options], e.g. ./build.sh --build-mode=Release
# Toolchain overrides (LAZBUILD, LAZARUS_PCP, LCL_WIDGETSET) can go in build.local.sh.
# On Linux the widgetset is qt6 when libQt6Pas is installed, else qt5; it is
# cocoa on macOS and win32 on Windows (run from Git Bash).
set -euo pipefail
cd "$(dirname "$0")"

[ -f build.local.sh ] && . ./build.local.sh
LAZBUILD="${LAZBUILD:-lazbuild}"
PCP_ARGS=()
[ -n "${LAZARUS_PCP:-}" ] && PCP_ARGS=(--pcp="$LAZARUS_PCP")

# Qt6 needs its Pascal bindings (libQt6Pas), not just Qt6 itself
has_qt6pas() {
  if command -v ldconfig >/dev/null 2>&1 || [ -x /sbin/ldconfig ]; then
    "$(command -v ldconfig || echo /sbin/ldconfig)" -p 2>/dev/null | grep -q 'libQt6Pas\.so' && return 0
  fi
  compgen -G '/usr/lib*/libQt6Pas.so*' >/dev/null || compgen -G '/usr/lib/*/libQt6Pas.so*' >/dev/null ||
    compgen -G '/usr/local/lib*/libQt6Pas.so*' >/dev/null
}

case "$(uname -s)" in
  Darwin) WS="${LCL_WIDGETSET:-cocoa}" ;;
  MINGW* | MSYS* | CYGWIN*) WS="${LCL_WIDGETSET:-win32}" ;;
  *)
    if [ -n "${LCL_WIDGETSET:-}" ]; then
      WS="$LCL_WIDGETSET"
    elif has_qt6pas; then
      WS=qt6
    else
      WS=qt5
    fi
    ;;
esac
echo "Building GUI apps with the $WS widgetset"

git submodule update --init --recursive

"$LAZBUILD" "${PCP_ARGS[@]}" -q src/cli/opensloper_cli.lpi "$@"
"$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$WS" src/design/opensloper_design.lpi "$@"
"$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$WS" src/publish/opensloper_publish.lpi "$@"
"$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$WS" src/measurements/opensloper_measurements.lpi "$@"
