# OpenSloper

Parametric sewing pattern drafting application in Lazarus / Free Pascal. GPLv3 or later.

The full design is in `documents/opensloper-design-document.md`. Read it before making architectural changes, and keep it up to date when a design decision changes.

## Layout

- `src/core/` — geometry, expressions, model, evaluator, piece builder, storage. **No LCL dependency**: never add `Forms`, `Graphics`, `Controls` or other LCL units here.
- `src/document/` — `TPatternDocument`, undo/redo commands, change notifications.
- `src/ui/` — forms, canvas, interaction tools, snapping, panels. Keep it thin: call into document and core.
- `src/output/` — PDF, SVG, DXF and Blender exporters; read computed geometry only. `src/output/thirdparty/` holds our own units that draw with BGRABitmap built without the LCL (the draft as PNG); every standard applies there, and only those BGRA units are allowed besides.
- `src/api/` — the Automation API (JSON-RPC 2.0), its MCP server, and the design window's automation socket (endpoint, listener, and the connection `serve --connect` uses). Depends only on the document, core and output; every edit goes through document commands.
- `src/design/` — `opensloper-design`, the main design app.
- `src/measurements/` — `opensloper-measurements`, which edits measurement files and size tables. Keep it thin, as `src/ui`.
- `src/publish/` — `opensloper-publish`, layouts and printing.
- `src/cli/` — `opensloper-cli` (export, export-draft, layout, check, measurements, serve, doc), built on the core and ConsoleTools. Its commands and options are tables in `Sloper.CLI.Arguments`, which build the parser and the CLI reference page.
- `src/docs/` — code that writes the generated reference pages, the file format schemas and the Python API client (`opensloper.py`) of the user documentation (`opensloper-cli doc TOPIC`). Doc generation code goes here.
- `src/packages/` — git submodules (Clipper2, BGRABitmap, ConsoleTools). Do not edit code in here; changes go upstream.
- `resources/` — branding: app icons and the API logo (SVG), for builds, docs and other resources; `make-icons.sh` regenerates the apps' `.ico` files after an SVG changes, and `linux/` holds the `.desktop` entries.
- `data/` — files the apps read at run time: the measurement catalogue and its body figures, the Tabler toolbar icons (`data/icons`, MIT), and the fonts images are drawn with (`data/fonts`: Noto Sans, OFL, and DejaVu Sans, Bitstream Vera licence).
- `tests/` — FPCUnit test project and regression patterns.
- `src/core/clipper2/osclipper2.lpk` — Lazarus package that builds Clipper2 from the submodule; projects depend on it rather than adding Clipper2 to their search path.
- `documents/` — internal development notes, the design document, `coding-standards.md`, `known-issues.md` and the GPL unit header (`gpl-header.txt`).
- `docs/` — user documentation (Markdown, built with Zensical from `zensical.toml`, licensed CC BY-SA 4.0). `docs/examples/` holds the tutorial and example patterns with their measurements, which readers download from the site and a test opens. `docs/reference/` holds generated pages and the generated Python client `opensloper.py`, and `docs/reference/schemas/` the generated JSON Schemas of the user files: never edit them by hand; run `./build.sh` then `./build-docs.sh`, and a test fails while a committed page is out of date.

## Build and test

```
git submodule update --init --recursive
./run-tests.sh     # tests, with heaptrc leak check
./build.sh         # GUI apps and CLI, into release/ (not in git)
./format.sh        # format sources with jcfsettings.cfg (--check to list only)
./check-standards.sh  # rules the formatter cannot check (errors fail, warnings advise)
./build-docs.sh    # regenerate docs/reference/ and build the site into release/site_docs (--serve to preview)
./venv/bin/python check-schemas.py  # check example and regression files against the file schemas (build-docs.sh runs it)
```

Toolchain overrides (`LAZBUILD`, `LAZARUS_PCP`, `LCL_WIDGETSET`) go in the gitignored `build.local.sh`; see `build.local.sh.example`.

Requires FPC 3.2.0 or later; CI (`.github/workflows/ci.yml`) uses the release Lazarus 4.8 with FPC 3.2.2, and its formatter is the reference. Linux uses the Qt5/Qt6 widgetset; macOS uses Cocoa. Run `run-tests.sh` and `check-standards.sh` before every commit. Pull request rules are in `CONTRIBUTING.md`.

## Conventions

- Every source unit starts with the GPLv3 header. Code translated from Valentina or Seamly2D keeps their copyright line.
- Internal units are millimetres: geometry, computed state and exports. Formula numbers are in the pattern's unit (mm, cm or in), converted where they become geometry (see Pattern units in the design). Coordinates are x right, y down, as on screen and in Seamly2D. Angles are degrees, 0° pointing right, positive anticlockwise as seen on screen, so 90° points up.
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
