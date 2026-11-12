# Contributing to OpenSloper

Thank you for helping. This page covers what a pull request needs before it can be merged. Read `CLAUDE.md` for the project's layout and rules, and `documents/coding-standards.md` for how the code is written.

Everyone taking part in the project is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately, as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Toolchain

Use the release toolchain that CI uses: **Lazarus 4.8 with FPC 3.2.2**. The formatter is built from your Lazarus's own source, so a different Lazarus version may format code differently and fail the CI formatting check. On Linux, the GUI apps also need the Qt5 or Qt6 Pascal bindings (`libQt5Pas` or `libQt6Pas`).

```
git clone --recursive https://github.com/billbsing/opensloper.git
cd opensloper
./run-tests.sh
./build.sh
```

## Before you open a pull request

Run all four of these and fix anything they report:

```
./format.sh             # format the sources (./format.sh --check lists files only)
./check-standards.sh    # rules the formatter cannot check
./run-tests.sh          # tests, with the heaptrc leak check
./build.sh              # the GUI apps and the CLI
```

CI runs the same checks on every pull request, and they must pass before a merge. `check-standards.sh` also prints warnings, such as single-letter names. Warnings don't fail the check, but please fix them in code you add.

## What a good pull request looks like

- **One change per pull request.** Keep refactoring separate from features and fixes.
- **Tests.** New geometry and formula code comes with core tests. A bug fix starts with a test that fails without the fix. Compare coordinates with a tolerance, never with exact equality.
- **No leaks.** heaptrc must report 0 unfreed blocks.
- **Layers.** `src/core/` has no LCL dependency. The API works through document commands. The UI stays thin. Every user change is an undoable `TCommand`.
- **Text.** User-visible text goes in `resourcestring` sections.
- **Design.** If the change alters a design decision, update `documents/opensloper-design-document.md` in the same pull request. Open an issue to discuss larger changes before writing the code.
- **Third-party code.** Don't edit `src/packages/`. Send changes to Clipper2, BGRABitmap or ConsoleTools to their own projects.
- **Changelog.** Add a line for anything a user would notice to `CHANGELOG.md`, under the version being worked on (the `APP_VERSION` in `src/core/sloper.core.version.pas`), with the issue number if there is one.
- **Commits.** Write commit messages that say what the change does and why.

## Licence

OpenSloper is licensed under the GNU GPL, version 3 or later. By submitting a pull request, you agree that your contribution is licensed under the same terms. Every new source file starts with the header in `documents/gpl-header.txt`. Code translated from Valentina or Seamly2D keeps their copyright line.
