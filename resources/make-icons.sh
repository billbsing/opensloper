#!/usr/bin/env bash
# Make the GUI apps' icons from the SVGs in resources/. Run it after changing
# an SVG and commit the results: lazbuild reads each project's .ico (named
# after its .lpi, next to it) into the program's resources as MAINICON, which
# the LCL loads as the application icon on every platform. The API logo is for
# the docs only, as the CLI has no icon.
#
# Sizes up to 128 px are bitmaps and 256 px is PNG, as Windows lays them out.
# The LCL's resource loader fails with a range check error on smaller PNG
# entries, and bitmaps at 256 px would make each file 380 KB.
#
# Needs rsvg-convert (librsvg), ImageMagick 7 (magick) and python3.
set -euo pipefail
cd "$(dirname "$0")/.."

BITMAP_SIZES=(16 20 24 32 40 48 64 128)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

make_icon() {
  local svg=$1 ico=$2
  local pngs=()
  for size in "${BITMAP_SIZES[@]}" 256; do
    rsvg-convert -w "$size" -h "$size" "resources/$svg.svg" -o "$WORK/$size.png"
  done
  for size in "${BITMAP_SIZES[@]}"; do
    pngs+=("$WORK/$size.png")
  done
  magick "${pngs[@]}" "$WORK/bitmaps.ico"
  # Add the 256 px PNG to the bitmaps' icon directory
  python3 -I - "$WORK/bitmaps.ico" "$WORK/256.png" "$ico" <<'PY'
import struct, sys
bitmaps, png, out = sys.argv[1:]
data = open(bitmaps, 'rb').read()
count = struct.unpack('<HHH', data[:6])[2]
entries = [struct.unpack('<BBBBHHII', data[6 + 16 * i:22 + 16 * i]) for i in range(count)]
images = [data[e[7]:e[7] + e[6]] for e in entries]
# 256 is written as 0
entries.append((0, 0, 0, 0, 1, 32, 0, 0))
images.append(open(png, 'rb').read())
offset = 6 + 16 * len(entries)
directory = struct.pack('<HHH', 0, 1, len(entries))
for entry, image in zip(entries, images):
    directory += struct.pack('<BBBBHHII', *entry[:6], len(image), offset)
    offset += len(image)
with open(out, 'wb') as f:
    f.write(directory + b''.join(images))
PY
  echo "$ico"
}

make_icon opensloper-design src/design/opensloper_design.ico
make_icon opensloper-measure src/measurements/opensloper_measurements.ico
make_icon opensloper-publish src/publish/opensloper_publish.ico
