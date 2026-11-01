#!/bin/bash
# Builds the read-only web copy of the design document, from the file itself so
# the text cannot drift. Writes lib/design-page/opensloper-design.html; publish
# that to https://claude.ai/artifact/Rxy848v4cVczHx3KNfzWcz (see the sync-design
# skill). Needs pandoc and python3.
set -euo pipefail
cd "$(dirname "$0")/../.."

Source=documents/opensloper-design-document.md
Output=lib/design-page/opensloper-design.html
Commit=$(git rev-parse --short HEAD)
Dirty=""
git diff --quiet HEAD -- "$Source" || Dirty=" with uncommitted changes"

mkdir -p "$(dirname "$Output")"
pandoc -f gfm -t html5 --template=documents/web/design-page-template.html --toc --toc-depth=3 --wrap=none -o "$Output" "$Source"
python3 -I - "$Output" "$Commit" "$Dirty" "$(date +%F)" <<'PY'
import re
import sys

path, commit, dirty, date = sys.argv[1:5]
with open(path, encoding='utf-8') as page:
    text = page.read()
text = text.replace('__COMMIT__', commit).replace('__DIRTY__', dirty).replace('__DATE__', date)
# Wide tables scroll in their own box, so the page itself never does
text = text.replace('<table>', '<div class="table"><table>').replace('</table>', '</table></div>')
with open(path, 'w', encoding='utf-8') as page:
    page.write(text)
PY
echo "Built $Output from $Commit$Dirty"
