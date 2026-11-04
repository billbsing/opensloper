# OpenSloper

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use. It owes much to Valentina and Seamly2D, the open source parametric pattern programs whose ideas it builds on.

## Status

Early development: project skeleton, geometry basics and the test suite are in place. See `documents/opensloper-design-document.md` for the design and roadmap, and `documents/known-issues.md` for open problems.

## Development

To clone this project, you must use `--recursive`, since this project contains submodules that are used in the build process.

To build we suggest you first install Lazarus/Free Pascal using [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe).

```
git clone --recursive https://github.com/billbsing/opensloper.git
cd opensloper
./build.sh
```

## Building

Requires Lazarus with FPC 3.2.0 or later. Linux uses the Qt6 widgetset (`libQt6Pas`); macOS uses Cocoa.

```
git submodule update --init --recursive
./run-tests.sh     # build and run the tests (with leak checking)
./build.sh         # build opensloper, publish/opensloper-publish, measurements/opensloper-measurements and cli/opensloper-cli
```

To use a Lazarus/FPC that is not on `PATH` (for example an fpcupdeluxe install), copy `build.local.sh.example` to `build.local.sh` and edit the paths.

## Licence

GPLv3 or later; see `LICENSE`.
