# OpenSloper

Parametric sewing pattern drafting application in Lazarus / Free Pascal. GPLv3 or later.

The full design is in `documents/opensloper-design-document.md`. Read it before making architectural changes, and keep it up to date when a design decision changes.

## Layout

- `src/core/` — geometry, expressions, model, evaluator, piece builder, storage. **No LCL dependency**: never add `Forms`, `Graphics`, `Controls` or other LCL units here.
- `src/document/` — `TPatternDocument`, undo/redo commands, change notifications.
- `src/ui/` — forms, canvas, interaction tools, snapping, panels. Keep it thin: call into document and core.
- `src/output/` — PDF, SVG, DXF and Blender exporters; read computed geometry only.
- `src/api/` — the Automation API (JSON-RPC 2.0). Depends only on the document and core; every edit goes through document commands.
- `measurements/` — `opensloper-measurements`, which edits measurement files and size tables. Keep it thin, as `src/ui`.
- `data/` — files the apps read at run time: the measurement catalogue and its body figures.
- `cli/` — `opensloper-cli` (export, layout, check, measurements, serve), built on the core and ConsoleTools.
- `tests/` — FPCUnit test project and regression patterns.
- `packages/` — git submodules (Clipper2, BGRABitmap, ConsoleTools). Do not edit code in here; changes go upstream.
- `src/core/clipper2/osclipper2.lpk` — Lazarus package that builds Clipper2 from the submodule; projects depend on it rather than adding Clipper2 to their search path.
- `documents/` — internal development notes, the design document, `coding-standards.md`, `known-issues.md` and the GPL unit header (`gpl-header.txt`).
- `docs/` — user manuals and help.

## Build and test

```
git submodule update --init --recursive
./run-tests.sh     # tests, with heaptrc leak check
./build.sh         # GUI apps and CLI
./format.sh        # format sources with jcfsettings.cfg (--check to list only)
```

Toolchain overrides (`LAZBUILD`, `LAZARUS_PCP`, `LCL_WIDGETSET`) go in the gitignored `build.local.sh`; see `build.local.sh.example`.

Requires FPC 3.2.0 or later. Linux uses the Qt5/Qt6 widgetset; macOS uses Cocoa. Run `run-tests.sh` before every commit.

## Conventions

- Every source unit starts with the GPLv3 header. Code translated from Valentina or Seamly2D keeps their copyright line.
- Internal units are millimetres; angles are degrees, 0° pointing right, positive anticlockwise.
- Only definitions (operations, references, formula strings) are saved and undone; computed geometry is always derived.
- Objects are referenced by stable integer IDs (`12`, `7`), never reused; names are for display only. Formulas are stored in ID form and shown with names.
- Names: letters, digits and underscore, not starting with a digit; unique per namespace; compared case-insensitively. Copies get the next free number appended directly (`A` → `A2`).
- Every user change is a `TCommand` with `Execute` and `Undo`; one drag is one undo step.
- Evaluation failures are states (error, invalid, blocked), never exceptions that escape to the UI.
- User-visible text goes in `resourcestring` sections.
- Code style (naming, formatting, line length) follows `documents/coding-standards.md`; read it before writing code. Run `./format.sh` before committing.
- File paths go through `TAppPaths`; build paths with `ConcatPaths` / `PathDelim`, never a hard-coded `/`.
- Every program lists `Sloper.Core.CodePage` first in its uses clause and is compiled with `-FcUTF8`, so strings are UTF-8 throughout.
- Files are written through `Sloper.Core.JSON` (`JSONToText`, `JSONFloat`) for a stable layout; loading reports errors as messages, never exceptions.
- Shortcuts use `ssModifier`, not a hard-coded Ctrl.

## Testing

- Write core tests alongside or before geometry and formula code.
- Every bug gets a failing test before the fix.
- Compare coordinates with a tolerance helper, never exact float equality.
- Tests are built with heaptrc (`-gh`); fix any reported leaks.
