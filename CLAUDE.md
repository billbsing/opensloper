# OpenSloper

Parametric sewing pattern drafting application in Lazarus / Free Pascal. GPLv3 or later.

The full design is in `documents/OpenSloper-Design-Document.md`. Read it before making architectural changes, and keep it up to date when a design decision changes.

## Layout

- `src/core/` — geometry, expressions, model, evaluator, piece builder, storage. **No LCL dependency**: never add `Forms`, `Graphics`, `Controls` or other LCL units here.
- `src/document/` — `TPatternDocument`, undo/redo commands, change notifications.
- `src/ui/` — forms, canvas, interaction tools, snapping, panels. Keep it thin: call into document and core.
- `src/output/` — PDF, SVG, DXF and Blender exporters; read computed geometry only.
- `cli/` — `opensloper-cli` (export, check), built on the core and ConsoleTools.
- `tests/` — FPCUnit test project and regression patterns.
- `packages/` — git submodules (Clipper2, BGRABitmap, ConsoleTools). Do not edit code in here; changes go upstream.
- `src/core/clipper2/osclipper2.lpk` — Lazarus package that builds Clipper2 from the submodule; projects depend on it rather than adding Clipper2 to their search path.
- `documents/` — internal development notes, the design document, `known-issues.md` and the GPL unit header (`gpl-header.txt`).
- `docs/` — user manuals and help.

## Build and test

```
git submodule update --init --recursive
./run-tests.sh     # tests, with heaptrc leak check
./build.sh         # GUI app and CLI
```

Toolchain overrides (`LAZBUILD`, `LAZARUS_PCP`, `LCL_WIDGETSET`) go in the gitignored `build.local.sh`; see `build.local.sh.example`.

Requires FPC 3.2.0 or later. Linux uses the Qt5/Qt6 widgetset; macOS uses Cocoa. Run `run-tests.sh` before every commit.

## Conventions

- Every source unit starts with the GPLv3 header. Code translated from Valentina or Seamly2D keeps their copyright line.
- Internal units are millimetres; angles are degrees, 0° pointing right, positive anticlockwise.
- Only definitions (operations, references, formula strings) are saved and undone; computed geometry is always derived.
- Objects are referenced by stable IDs (`p12`, `l7`); names are for display only. Formulas are stored in ID form and shown with names.
- Names: letters, digits and underscore, not starting with a digit; unique per namespace; compared case-insensitively. Copies get the next free number appended directly (`A` → `A2`).
- Every user change is a `TCommand` with `Execute` and `Undo`; one drag is one undo step.
- Evaluation failures are states (error, invalid, blocked), never exceptions that escape to the UI.
- User-visible text goes in `resourcestring` sections.
- File paths go through `TAppPaths`; build paths with `ConcatPaths` / `PathDelim`, never a hard-coded `/`.
- Shortcuts use `ssModifier`, not a hard-coded Ctrl.

## Testing

- Write core tests alongside or before geometry and formula code.
- Every bug gets a failing test before the fix.
- Compare coordinates with a tolerance helper, never exact float equality.
- Tests are built with heaptrc (`-gh`); fix any reported leaks.
