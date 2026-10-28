#!/usr/bin/env bash
# Format the Pascal sources with JEDI Code Format and the project settings in
# jcfsettings.cfg (see documents/coding-standards.md). packages/ and the
# Lazarus-generated package unit osclipper2.pas are left alone.
#
#   ./format.sh           format every source file in place
#   ./format.sh --check   list files that need formatting, change nothing
#   ./format.sh FILE...   format only the given files
#
# The command-line formatter is built into lib/jcf on first use, from the
# Lazarus source in JCF_SOURCE (default: the system Lazarus). Use the same
# Lazarus version as your IDE so both format alike; set JCF_SOURCE in
# build.local.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ -f build.local.sh ] && . ./build.local.sh
LAZBUILD="${LAZBUILD:-lazbuild}"
JCF="${JCF:-lib/jcf/jcf}"
JCF_SOURCE="${JCF_SOURCE:-/usr/lib/lazarus/components/jcf2}"
CONFIG="$PWD/jcfsettings.cfg"

build_jcf() {
  local lazarus_dir src
  echo "Building the formatter from $JCF_SOURCE" >&2
  lazarus_dir="$(dirname "$(realpath "$(command -v "$LAZBUILD")")")"
  src=lib/jcf-src
  rm -rf "$src" lib/jcf-pcp
  mkdir -p lib/jcf
  cp -r "$JCF_SOURCE" "$src"
  rm -rf "$src/lib"
  # Build against this copy's own jcfbase package, not the one installed in
  # the Lazarus that does the building
  sed -i 's|<PackageName Value="jcfbase"/>|&\n        <DefaultFilename Value="../../jcfbase.lpk" Prefer="True"/>|' \
    "$src/CommandLine/Lazarus/jcf.lpi"
  "$LAZBUILD" --pcp="$PWD/lib/jcf-pcp" --lazarusdir="$lazarus_dir" -q \
    "$src/CommandLine/Lazarus/jcf.lpi" > lib/jcf/build.log 2>&1 ||
    { cat lib/jcf/build.log >&2; exit 1; }
  cp "$src"/lib/CommandLine-*/jcf "$JCF"
}

format_file() {
  local log
  log="$(mktemp)"
  if ! "$JCF" -clarify -inplace -y -config="$CONFIG" -F "$1" > "$log" 2>&1 ||
    grep -qiE 'exception|parse error' "$log"; then
    echo "Could not format $1:" >&2
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

[ -x "$JCF" ] || build_jcf

CHECK=0
if [ "${1:-}" = "--check" ]; then
  CHECK=1
  shift
fi
if [ $# -gt 0 ]; then
  FILES=("$@")
else
  mapfile -t FILES < <(git ls-files --cached --others --exclude-standard '*.pas' '*.lpr' '*.pp' |
    grep -v '^packages/' | grep -v '^src/core/clipper2/osclipper2.pas$')
fi

if [ "$CHECK" -eq 1 ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  NEEDED=0
  for f in "${FILES[@]}"; do
    cp "$f" "$TMP/check.pas"
    format_file "$TMP/check.pas"
    if ! cmp -s "$f" "$TMP/check.pas"; then
      echo "$f"
      NEEDED=1
    fi
  done
  exit "$NEEDED"
fi

for f in "${FILES[@]}"; do
  format_file "$f"
done
echo "Formatted ${#FILES[@]} files."
