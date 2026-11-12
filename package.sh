#!/usr/bin/env bash
# Package the apps that build.sh put in release/ for this platform, as
#   release/dist/opensloper-VERSION-linux-x86_64.tar.gz    (Linux)
#   release/dist/opensloper-VERSION-macos-arm64.zip        (macOS: OpenSloper.app)
#   release/dist/opensloper-VERSION-windows-x86_64.zip     (Windows, from Git Bash)
# VERSION is APP_VERSION in Sloper.Core.Version. Run ./build.sh first.
# STRIP names the strip program when it is not on PATH (as on Windows).
# On Linux, BUNDLE_LIBS lists libraries to ship in lib/ beside the programs
# (the release workflow ships the Qt6 Pascal bindings, libQt6Pas.so.6, which
# few distributions package); the GUI programs then look there first.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(sed -n "s/^ *APP_VERSION = '\(.*\)';.*/\1/p" src/core/sloper.core.version.pas)
[ -n "$VERSION" ] || { echo "APP_VERSION not found in src/core/sloper.core.version.pas" >&2; exit 1; }
APPS=(opensloper-design opensloper-publish opensloper-measurements opensloper-cli)
DIST=release/dist
STAGE=release/stage
rm -rf "$STAGE"
mkdir -p "$DIST" "$STAGE"

case "$(uname -m)" in
  x86_64 | amd64) ARCH=x86_64 ;;
  arm64 | aarch64) ARCH=arm64 ;;
  *) ARCH=$(uname -m) ;;
esac

# The programs lose their debug information; the build keeps it for debugging
strip_programs() {
  local strip="${STRIP:-strip}"
  if ! command -v "$strip" >/dev/null 2>&1; then
    echo "No $strip found, so the programs keep their debug information" >&2
    return
  fi
  for program in "$@"; do
    "$strip" "$program"
  done
}

# What the download says about running it, beside the programs
write_readme() {
  local file=$1 platform=$2
  {
    echo "OpenSloper $VERSION for $platform"
    echo
    echo "Parametric sewing pattern drafting. https://github.com/billbsing/opensloper"
    echo "Free software under the GNU General Public License version 3 or later (LICENSE)."
    echo
    case "$platform" in
      Linux)
        echo "Run opensloper-design (the pattern editor), opensloper-measurements or"
        echo "opensloper-publish from this folder; keep the data folder beside them."
        echo "opensloper-cli is the command-line tool."
        echo
        if [ -n "${BUNDLE_LIBS:-}" ]; then
          echo "The apps use Qt 6.4 or later, which most desktops have; its Pascal"
          echo "bindings are in the lib folder. Should Qt 6 be missing:"
          echo "  Debian, Ubuntu: sudo apt install libqt6printsupport6 qt6-qpa-plugins"
          echo "  Fedora: sudo dnf install qt6-qtbase-gui"
          echo "  Arch: sudo pacman -S qt6-base"
        else
          echo "The apps use Qt and need its Pascal bindings, libQt5Pas or libQt6Pas,"
          echo "from your distribution (libqt5pas1 or libqt6pas6 on Debian and Ubuntu)."
        fi
        echo
        echo "share/applications holds menu entries and share/icons the icons; copy them"
        echo "to ~/.local/share/applications and ~/.local/share/icons/hicolor/scalable/apps"
        echo "with the programs on your PATH to start OpenSloper from the desktop menu."
        ;;
      macOS)
        echo "Move OpenSloper.app to Applications and open it: it is the pattern editor,"
        echo "and its File menu opens the measurements editor and the publish window."
        echo "It is not signed by Apple. If macOS says it cannot be opened or is damaged,"
        echo "run this once in Terminal:"
        echo "  xattr -cr /Applications/OpenSloper.app"
        echo "The command-line tool is OpenSloper.app/Contents/MacOS/opensloper-cli."
        echo "Built for Apple silicon (arm64)."
        ;;
      Windows)
        echo "Run opensloper-design.exe (the pattern editor), opensloper-measurements.exe"
        echo "or opensloper-publish.exe from this folder; keep the data folder beside"
        echo "them. opensloper-cli.exe is the command-line tool."
        echo
        echo "The programs are not signed, so Windows SmartScreen may ask before the"
        echo "first run: choose More info, then Run anyway."
        ;;
    esac
  } > "$file"
}

case "$(uname -s)" in
  Linux)
    NAME="opensloper-$VERSION-linux-$ARCH"
    ROOT="$STAGE/$NAME"
    mkdir -p "$ROOT/share/applications" "$ROOT/share/icons"
    for app in "${APPS[@]}"; do
      cp "release/$app" "$ROOT/"
    done
    strip_programs "${APPS[@]/#/$ROOT/}"
    if [ -n "${BUNDLE_LIBS:-}" ]; then
      mkdir -p "$ROOT/lib"
      for lib in $BUNDLE_LIBS; do
        cp -L "$lib" "$ROOT/lib/"
      done
      for app in opensloper-design opensloper-publish opensloper-measurements; do
        patchelf --set-rpath '$ORIGIN/lib' "$ROOT/$app"
      done
    fi
    cp -R data "$ROOT/data"
    cp resources/linux/*.desktop "$ROOT/share/applications/"
    # Named as the desktop entries' Icon lines name them
    cp resources/opensloper-design.svg resources/opensloper-publish.svg resources/opensloper-measure.svg "$ROOT/share/icons/"
    cp LICENSE "$ROOT/"
    write_readme "$ROOT/README.txt" Linux
    tar -C "$STAGE" -czf "$DIST/$NAME.tar.gz" "$NAME"
    echo "$DIST/$NAME.tar.gz"
    ;;
  Darwin)
    # One bundle: the design app opens the other two as programs beside it
    NAME="opensloper-$VERSION-macos-$ARCH"
    BUNDLE="$STAGE/$NAME/OpenSloper.app"
    mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
    for app in "${APPS[@]}"; do
      cp "release/$app" "$BUNDLE/Contents/MacOS/"
    done
    # Code signing takes only programs in MacOS, so the data is a resource
    cp -R data "$BUNDLE/Contents/Resources/data"
    if command -v rsvg-convert >/dev/null && command -v iconutil >/dev/null; then
      ICONSET="$STAGE/OpenSloper.iconset"
      mkdir -p "$ICONSET"
      for size in 16 32 128 256 512; do
        rsvg-convert -w $size -h $size resources/opensloper-design.svg -o "$ICONSET/icon_${size}x${size}.png"
        rsvg-convert -w $((size * 2)) -h $((size * 2)) resources/opensloper-design.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
      done
      iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/OpenSloper.icns"
    else
      echo "No rsvg-convert or iconutil, so the bundle has no icon" >&2
    fi
    # No NSPrincipalClass: the LCL then makes its own TCocoaApplication, and
    # naming NSApplication there gives it one without the LCL's methods
    cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OpenSloper</string>
  <key>CFBundleDisplayName</key><string>OpenSloper</string>
  <key>CFBundleIdentifier</key><string>io.github.billbsing.opensloper</string>
  <key>CFBundleExecutable</key><string>opensloper-design</string>
  <key>CFBundleIconFile</key><string>OpenSloper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
    # Apple silicon runs only signed programs; an ad hoc signature is enough
    # to run once the download's quarantine is cleared
    codesign --force --deep --sign - "$BUNDLE"
    cp LICENSE "$STAGE/$NAME/"
    write_readme "$STAGE/$NAME/README.txt" macOS
    (cd "$STAGE" && ditto -c -k --keepParent "$NAME" "../../$DIST/$NAME.zip")
    echo "$DIST/$NAME.zip"
    ;;
  MINGW* | MSYS* | CYGWIN*)
    NAME="opensloper-$VERSION-windows-$ARCH"
    ROOT="$STAGE/$NAME"
    mkdir -p "$ROOT"
    PROGRAMS=()
    for app in "${APPS[@]}"; do
      cp "release/$app.exe" "$ROOT/"
      PROGRAMS+=("$ROOT/$app.exe")
    done
    strip_programs "${PROGRAMS[@]}"
    cp -R data "$ROOT/data"
    cp LICENSE "$ROOT/LICENSE.txt"
    write_readme "$ROOT/README.txt" Windows
    (cd "$STAGE" && 7z a -tzip -bso0 "../../$DIST/$NAME.zip" "$NAME")
    echo "$DIST/$NAME.zip"
    ;;
  *)
    echo "No packaging for $(uname -s)" >&2
    exit 1
    ;;
esac
