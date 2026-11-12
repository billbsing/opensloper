#!/usr/bin/env bash
# Print the release notes of a version, by default the APP_VERSION in
# Sloper.Core.Version: its CHANGELOG.md section, without its heading, or when
# that is missing or empty, the subjects of the commits since the previous
# release's tag (vX.Y.Z), each with the issues it closes ("Closes #3").
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

if grep -q '[^[:space:]]' <<< "$SECTION"; then
  printf '%s\n' "$SECTION"
  exit 0
fi

# The newest release tag before this version's own, which moves with it
PREVIOUS=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude "v$VERSION" HEAD 2>/dev/null || true)
if [ -z "$PREVIOUS" ]; then
  echo "The first release of OpenSloper."
  exit 0
fi

echo "Changes since ${PREVIOUS#v}:"
echo
COUNT=0
while IFS= read -r commit; do
  subject=$(git log -1 --format=%s "$commit")
  issues=$(git log -1 --format=%B "$commit" |
    grep -oiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' | grep -oE '#[0-9]+' | sort -u -t'#' -k2n | paste -sd' ' - || true)
  if [ -n "$issues" ]; then
    echo "- $subject (${issues// /, })"
  else
    echo "- $subject"
  fi
  COUNT=$((COUNT + 1))
done < <(git rev-list --no-merges --reverse "$PREVIOUS..HEAD")
[ "$COUNT" -gt 0 ] || echo "- No changes"
