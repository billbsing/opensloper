#!/usr/bin/env bash
# Print the CHANGELOG.md section of a version, without its heading: by default
# the APP_VERSION in Sloper.Core.Version. Fails when the section is missing or
# has nothing in it, so the release workflow publishes no version without notes.
# Usage: ./release-notes.sh [VERSION]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(sed -n "s/^ *APP_VERSION = '\(.*\)';.*/\1/p" src/core/sloper.core.version.pas)}"
[ -n "$VERSION" ] || { echo "APP_VERSION not found in src/core/sloper.core.version.pas" >&2; exit 1; }

# From "## VERSION" (perhaps followed by " - date") to the next "## " heading,
# with the blank lines at either end left out
SECTION=$(awk -v version="$VERSION" '
  /^## / {
    if (found) exit
    if ($2 == version) { found = 1; next }
  }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if ! grep -q '[^[:space:]]' <<< "$SECTION"; then
  echo "CHANGELOG.md has no notes for $VERSION: add them under \"## $VERSION\"" >&2
  exit 1
fi
printf '%s\n' "$SECTION"
