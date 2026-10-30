# OpenSloper

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use.

## Status

Early development: project skeleton, geometry basics and the test suite are in place. See `documents/opensloper-design-document.md` for the design and roadmap, and `documents/known-issues.md` for open problems.

## Building

Requires Lazarus with FPC 3.2.0 or later. Linux uses the Qt5 widgetset (`libQt5Pas`); macOS uses Cocoa.

```
git submodule update --init --recursive
./run-tests.sh     # build and run the tests (with leak checking)
./build.sh         # build opensloper and cli/opensloper-cli
```

To use a Lazarus/FPC that is not on `PATH` (for example an fpcupdeluxe install), copy `build.local.sh.example` to `build.local.sh` and edit the paths.

## Licence

GPLv3 or later; see `LICENSE`.
