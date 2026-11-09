# OpenSloper

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use. It owes much to Valentina and Seamly2D, the open source parametric pattern programs whose ideas it builds on.

## Status

Early development: project skeleton, geometry basics and the test suite are in place. See `documents/opensloper-design-document.md` for the design and roadmap, and `documents/known-issues.md` for open problems.

## Development

To clone this project, you must use `--recursive`, since this project contains submodules that are used in the build process.

Build with the release toolchain that CI uses: Lazarus 4.8 with FPC 3.2.2 (from your distribution, or the packages at [lazarus-ide.org](https://www.lazarus-ide.org)).

```
git clone --recursive https://github.com/billbsing/opensloper.git
cd opensloper
./build.sh
```

## Building

Requires Lazarus with FPC 3.2.0 or later. Linux uses the Qt5/Qt6 widgetset (`libQt5Pas`, `libQt6Pas`); `build.sh` picks Qt6 when `libQt6Pas` is installed, else Qt5 (set `LCL_WIDGETSET` to choose). macOS uses Cocoa.

```
git submodule update --init --recursive
./run-tests.sh     # build and run the tests (with leak checking)
./build.sh         # build the three GUI apps and the CLI into release/
```

To contribute, see `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`. To report a security problem, see `SECURITY.md`.

To use a Lazarus/FPC that is not on `PATH` (for example an fpcupdeluxe install), copy `build.local.sh.example` to `build.local.sh` and edit the paths.

## Licence

GPLv3 or later; see `LICENSE`.


