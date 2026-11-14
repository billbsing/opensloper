# OpenSloper — Design Document

Oct 27, 2026, restructured Nov 14, 2026 (#2) · @Bill

How this document is laid out: **General** covers what every app shares (concepts, architecture, files, platforms, standards); then a part for each app, **Measurements app**, **Design app** and **Publish app**, and one for the **Automation API and command line**, each holding the design of what is managed there. **Open items** at the end gathers everything not built yet, as a list to open GitHub issues from; the sections above it describe what is built and the decisions behind it.

## General

### Overview

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use. It owes much to Valentina and Seamly2D, the open source parametric pattern programs whose ideas it builds on.

Patterns are drafted with relative distances and formulas, so changing a measurement redraws the whole pattern. Valentina and Seamly2D (C++/Qt, which split from a common codebase in 2017) do this already, but both are large and have a steep learning curve. This project aims for the same parametric power with a simpler, more direct drawing experience.

Goals:

- Parametric drafting driven by measurement sets and variables
- An Inkscape-like canvas where snapping records relationships automatically
- Automatic piece detection instead of manually tracing outlines in order
- Seam allowance, notches, grainlines and true-scale tiled printing
- Garments and accessories in fabric and leather, with output for cutting machines
- A small, maintainable codebase with a pure-Pascal core

### Technology and licence

The project uses Lazarus/Free Pascal and is licensed GPLv3 or later.

| Component | Use | Licence |
| --- | --- | --- |
| Lazarus LCL / FCL | GUI, JSON (`fpjson`), XML (`DOM`, `XMLRead`), SQLite (SQLdb) | Modified LGPL with static-linking exception |
| Clipper2 | Polygon offsetting and booleans for seam allowance | Boost |
| BGRABitmap | Antialiased canvas drawing, SVG; PNG images in the CLI and API, without the LCL | Modified LGPL |
| fpvectorial (optional) | DXF/SVG/PDF export helpers | Modified LGPL |
| Tabler Icons | Toolbar and menu icons, SVG in `data/icons` | MIT |

Licence decisions:

- GPLv3 or later, matching Valentina and Seamly2D, so code can be studied, borrowed and shared in both directions.
- `LICENSE` file at the repo root with the full GPLv3 text; a standard GPL header in every unit.
- Code translated from Valentina or Seamly2D keeps their copyright line alongside the project's.
- An About box shows the licence and no-warranty notice.
- User documentation in `docs/` is licensed CC BY-SA 4.0 (see Documentation).

Practices from day one: git repository, internal units in mm, UI text in `resourcestring` sections for translation, and occasional builds on a second OS.

### Core concepts

A pattern is a graph of draft objects whose positions come from measurements, variables and other objects.

| Concept | What it is | Notes |
| --- | --- | --- |
| Measurement set | A person's or a product's measurements, e.g. `@waist` | Own file, edited in the measurements app; one set drives many patterns. One person's set or a size table with one column per size |
| Variable | Pattern-level value, e.g. `#ease_waist = 20` | Holds design decisions; formulas may use measurements and other variables, not draft objects, which would tie variables to geometry |
| Point | A position defined by an operation, its references and formulas | Never stored as fixed coordinates, except free points |
| Operation | How an object is placed: offset, along an edge, intersection, projection, transform… | Inferred from snapping where possible; the full list is the generated Operations page |
| Edge | Line, curve, path, circle, arc or offset between points | Curve handles have angle and length formulas |
| Role | Construction, outline, or a marking role (placement, stitch, fold, cut, skive, edge finish) | Only outline edges form piece boundaries; marking edges join the pieces they lie in (see Markings) |
| Marker | A point's mark: plain, hole, button or match dot | A marked point inside a piece prints with it (see Markings) |
| Piece | Closed path of edge references, each with a reversed flag | Seam allowance, grainline, notches, markings, material, cut count, fold line |
| Material | A named material (Main, Lining, Interfacing, Leather) with a colour and fill | Drives piece fills, the cut list and material layouts |
| Seam | The edges that are sewn together, with direction and expected ease | Drives seam-length checks |
| Layout | Pieces arranged on sheets for printing, plotting or cutting | Works on computed geometry only |
| Annotation | Note, callout, title block or sheet note | Anchored to objects by ID, so it follows measurement changes; may contain live fields |

### Architecture

Four layers, each depending only on the ones below; the core has no LCL dependency, so it can be unit-tested and reused by a command-line tool.

Layers (dependencies point down):

- **UI (LCL):** canvas view (BGRABitmap, pan, zoom), interaction tools (select, add point, curve, piece), snapping engine (turns snaps into operations), panels (properties, objects, variables, measurements, materials)
- **Output:** tiled PDF, SVG and DXF with line types for cutting machines, Blender export (later); reads computed geometry from the core
- **Document:** TPatternDocument (owns the model), undo/redo commands, change notifications
- **Core (pure Pascal, no LCL):** geometry, expressions, model, evaluator, piece builder (Clipper2 seam allowance), storage (JSON pattern and measurement files)

Three GUI apps sit on these layers: the measurements app, the drafting app and the publish app (see Measurements app and Publish app). Each owns one kind of file and only reads the ones before it (measurements → patterns → layouts). They share the core, and the publish app the output layer, but not each other's UI.

The UI changes the model only through document commands, and exporters read computed geometry directly from the core, so a new output format never touches drafting code.

### Key design decisions

The central rule: only definitions are saved and undone; computed geometry is always derived.

1. **Definition vs result.** Each object holds its definition (operation, references, formula strings) and a cached computed result. Saving, loading and undo touch definitions only.
2. **Dependencies come from formulas.** Each formula is parsed once into an expression tree; what it references, plus the operation's direct inputs, forms the dependency graph. The user never manages it.
3. **Ordered evaluation.** The graph is topologically sorted; a change re-evaluates what depends on it (see Evaluator). An edit that would make a cycle is refused with a clear message.
4. **Failures are states, not crashes.** An object that cannot be evaluated (two lines no longer cross) and its dependents become invalid and show in red. The pattern stays editable.
5. **IDs separate from names.** IDs are integers that never change and are never reused; names can be changed freely (see Names and IDs).
6. **One class per operation.** Each operation type declares its inputs and formulas and evaluates itself. Adding one means writing the class, its `Add…` call on `TPattern`, its file type in `Sloper.Core.PatternFile` and its row in `Sloper.Core.OperationInfo`.
7. **Commands for undo and redo.** Every user change is one step. One drag is one step: the model updates live during the drag and the step is committed on mouse-up; Escape cancels. Nudges of the same object within a second merge into one step, as do runs of changes to one field. Formula fields commit on Enter or leaving the field, not per keystroke.

   `Sloper.Document.PatternDocument` keeps each step as the pattern's saved text before and after (`BeginChange`, `EndChange`, `CancelChange`), so undo restores exactly the earlier definitions, with the same IDs, without an inverse for every editing call. Because undo replaces the objects with new instances, the UI holds objects by ID, never by reference. A step the file was saved after is never merged into, so the saved state stays reachable. At most 500 steps are kept. The ID counter only goes up, even on undo, so an ID is never handed out twice. The measurement set (file and size) belongs to the document, not the history: undo never swaps it back.
8. **Storage kept apart from the model.** `TPattern` knows nothing about JSON; `Sloper.Core.PatternFile` reads and writes it through the pattern's loader calls. With one format there is no storage interface; one can be extracted if a second format is added.

### File format and storage

Pattern, measurement and layout files are JSON; SQLite is reserved for a later library of clients and patterns.

| Format | Role | Reason |
| --- | --- | --- |
| JSON | Pattern, measurement and layout files | Built into FCL, readable, diffs in git, easy to share |
| SQLite | Later: a library of clients, measurements and patterns | Searchable, grows over time; not suited to small shared documents |
| XML | Seamly2D and Valentina measurement files | Compatibility with existing users' data |
| SVG, DXF, PDF | Exports | See Publish app |
| YAML | Not used | No standard Pascal library; whitespace pitfalls |

**Rules** (`Sloper.Core.JSON`):

- `format` and `version` at the top of every file; a program refuses a version newer than it knows.
- Stable IDs for every object, and references by ID. Formulas are stored as strings in ID form and parsed on load; a pattern's `units` is the unit of its formula numbers, while measurement and layout files store mm.
- A fixed member order and layout on save: two-space indent, LF line ends, numbers in the shortest form that reads back exactly, `.` as the decimal point, so files diff well. Text is UTF-8.
- A file that fails to load says why and leaves nothing half-loaded; a formula that does not parse is kept as text and shows as an error.
- Pattern files stay at version 1 until the first public release: while nobody else has pattern files, format changes are made in place and the regression patterns rebuilt.

**The formats are specified in the user documentation**, decided 2026-11-08 so that Claude and other tools can rely on them. `opensloper-cli doc files` writes the File formats page and `opensloper-cli doc pattern.schema.json` (and `measurements`, `layout`) a JSON Schema, draft 2020-12, for each, into `docs/reference/`. Both come from code tables: the members outside the objects from `Sloper.Core.FileInfo`, and the objects from `Sloper.Core.OperationInfo`. A schema lists exactly the members the apps write, marks those a file needs to load as required, and allows no others, so a misspelt member is caught; the loaders also accept a few members of older files that the schemas leave out. Tests hold the tables to the writers both ways (every member written is listed, every listed member is written) and check that each example on the page is a file exactly as the program writes it. `check-schemas.py`, run by `opensloper-make.sh docs` and the documentation workflow, checks the schemas with Python's `jsonschema` and every example and regression file against them.

**Pattern file rules** the schema cannot say:

- `variables` and `objects` are in creation order, and an object's direct inputs must come earlier in the file, which creation order guarantees, since inputs cannot be deleted while used. Formulas may refer to any ID; a missing one is an error when evaluated. A piece that takes on a newer point moves to the end.
- An edge named after its ends has no `name`; it is worked out after loading, so it can never be stale.
- `nextId` is above every ID in the file, and saving writes the counter as it stands, never recomputed, so deleted IDs stay retired. A hand-written file may leave it out.
- Members written with their defaults (`mode`, `from`, `direction`, `extend`, `pick`, `role`) may be left out of hand-written files; the writer always writes them.
- `materials` comes after `objects` but is read first, since pieces refer to it, and a pattern whose only material is the untouched Main writes neither `materials` nor a piece `material`.
- `measurementFile` is relative to the pattern's folder unless absolute, with `/` separators; the core never loads it by itself. The size used from a size table is not saved.
- Loading checks IDs (positive, unique across variables, materials and objects, below `nextId`), names, types and inputs, and fails naming the object by ID (`Object 6 uses object 9, which is not defined before it`), leaving the pattern empty.
- `view.hiddenPieces`, `view.isolate` and `view.pieceOrder` (2026-11-13) hold the overlapping-piece view options by ID, each left out when empty. `pieceOrder` lists every piece once one has been moved; a piece not in it, new or from an older file, goes on top in pattern order. IDs that are not pieces are passed over, and saving writes only pieces that still exist.

### Preferences

Built 2026-11-05. Edit → Preferences… opens the same dialog in all three apps (`Sloper.UI.Preferences`), on the app's own tab. OK saves straight to `settings.json` (`TPreferences` in `Sloper.Core.Settings`). An app already open picks up a change made in another only when restarted.

| Tab | Setting | Stored as |
| --- | --- | --- |
| General | Unit: mm, cm or in. The unit new patterns take, and the measurements app's display unit (its Show in box changes the same preference). It never changes an existing pattern | `measureUnit` |
| Design | Grid spacing, one per unit, in that unit's own numbers (5 mm, 0.5 cm, ⅛ in), so switching units never turns ⅛ in into 3.175 mm. Zoomed out, the grid steps up through multiples of the spacing, so every line still lies on it | `gridSteps` |
| Design | Garment view: whether the Garment tab shades its pieces, where the light comes from (degrees, 135 is upper left) and how strongly (0 to 100%) | `garmentShading`, `garmentLightAngle`, `garmentShadeStrength` |
| Publish | Printer calibration across and down, 0.5 to 2. **Work Out Factors** sets each to `current × expected ÷ measured` from a test square measured on a print made with the current factors | `calibrationX`, `calibrationY` |

**Calibration is the printer's, not the layout's.** Layout files no longer carry it (older files' values are ignored); the publish app, the CLI and the Automation API set it from the preferences when they load a layout.

### File locations

OpenSloper follows each platform's conventions and never writes app files into the home folder root, unlike Seamly2D and Valentina (They may have changed this recently).

| Kind | Examples | Linux (XDG) | Windows | macOS |
| --- | --- | --- | --- | --- |
| Config | `settings.json`: preferences, profiles, window layout | `~/.config/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Data | Later: library, templates, user blocks | `~/.local/share/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| State | `recent-files.json`, logs | `~/.local/state/opensloper/` | `%LOCALAPPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Cache | Thumbnails, previews | `~/.cache/opensloper/` | `%LOCALAPPDATA%\OpenSloper\Cache\` | `~/Library/Caches/OpenSloper/` |

`XDG_*_HOME` is respected on Linux. The catalogue, body figures and icons ship in `data/` beside the programs (a folder up in the source tree, and in `Contents/Resources` of the macOS app bundle, since code signing takes only programs in `Contents/MacOS`). Folders are created on first use.

**User documents** (`.sloper`, `.slm`, `.slayout`) belong to the user, never in hidden folders: the first save defaults to `Documents/OpenSloper/`, then the last-used folder.

**Implementation.** `TAppPaths` gives `ConfigDir`, `DataDir`, `StateDir`, `CacheDir` and `DefaultDocumentsDir`; no other code builds these paths. The three apps share `settings.json` and `recent-files.json` and run side by side, so every save reads the file again first and changes only its own part. A missing settings file is a first run; an unreadable one leaves the defaults, and saving preferences over it is refused with the reason, rather than lose a newer version's file. File → Open Recent lists each app's last 10 files (`Sloper.Core.RecentFiles`, `Sloper.UI.RecentMenu`); a missing file is taken off when chosen.

### Platforms

Development is on Linux with the Qt widgetset, testing on macOS, and Windows deferred until a general release.

| Platform | Role | Widgetset | Notes |
| --- | --- | --- | --- |
| Linux | Main development | Qt5 or Qt6 | HiDPI; needs the `libQt5Pas` or `libQt6Pas` bindings at run time |
| macOS | Testing | Cocoa | Apple Silicon, Retina canvas, `.app` bundle; signing and notarisation for a public release |
| Windows | Release builds | Win32 | Built by the release workflow; kept compiling through portable code |

**Keeping all platforms viable:** shortcuts use `ssModifier` (Cmd on macOS, Ctrl elsewhere); paths go through `TAppPaths` with `ConcatPaths` and `PathDelim`; no Unix-only units in the core; widgetset-specific code (such as the Qt menu divider style) is kept behind `{$IFDEF}` with a do-nothing fallback.

**App icons.** The SVGs in `resources/` are the masters. `resources/make-icons.sh` turns each app's SVG into the `.ico` beside its `.lpi` (bitmaps up to 128 px and a 256 px PNG, since the LCL's loader rejects smaller PNG entries), which lazbuild puts in the program as `MAINICON`; the generated files are committed. `resources/linux/` has a `.desktop` entry per app.

**Release builds** (2026-11-12). Every push to the `release` branch runs `.github/workflows/release.yml`: Linux x86_64 (Qt6, Ubuntu 24.04), macOS arm64 (Cocoa, FPC 3.2.4rc1 as released with Lazarus 4.8 for macOS) and Windows x86_64 (Win32) are built with `opensloper-make.sh build`, packed by `opensloper-make.sh package` and started once from the unpacked download; the Linux job runs the tests first. The downloads become the GitHub release of `APP_VERSION` (tag `vVERSION`, a pre-release while 0.x), replaced on each push until the version changes. The release's notes are that version's section of `CHANGELOG.md`, written as the changes are made, or when it has none, the subjects of the commits since the previous release's tag with the issues they close (`opensloper-make.sh release`). Linux is a `.tar.gz` with menu entries and icons, and the Qt6 Pascal bindings (`libQt6Pas.so.6`) in `lib/`, built from Lazarus's own sources since Ubuntu packages them only from 26.04, which the GUI programs find through an `$ORIGIN/lib` rpath; macOS one `OpenSloper.app` holding all four programs, opening on the design app, which opens the others from its menus, signed ad hoc; Windows a `.zip`. The programs are stripped of debug information.

Known gaps: Linux needs Qt 6.4 or later and the glibc of Ubuntu 24.04 or later. The assistant's HTTPS goes through OpenSSL, which FPC 3.2.2 loads on Windows only as the OpenSSL 1.1 DLLs, past their end of life, so they are not shipped and the assistant cannot connect there. The assistant is untried on macOS, where the system's unversioned `libcrypto` must not be loaded; OpenSSL is loaded only on its first request, so the apps start either way.

### Repository layout

The repository mirrors the layers, with all Pascal source under `src/` and third-party code in submodules under `src/packages/`. `CLAUDE.md` lists every folder and script.

```text
opensloper/
├── src/
│   ├── core/          geometry, formulas, model, evaluator, storage (no LCL)
│   ├── document/      documents, undo, notifications
│   ├── ui/            forms, canvas, tools, snapping, panels
│   ├── output/        layouts, tiling, PDF, SVG, DXF
│   ├── api/           Automation API (JSON-RPC 2.0), the apps' link
│   ├── docs/          generated reference pages and schemas
│   ├── design/  measurements/  publish/  cli/   the four programs
│   └── packages/      submodules: Clipper2, BGRABitmap, ConsoleTools
├── data/              catalogue, body figures, icons, read at run time
├── resources/         app icons and logo (SVG masters)
├── tests/             FPCUnit project and regression patterns
├── documents/         internal notes and this document
├── docs/              user documentation (Zensical)
└── release/           built programs, not in git
```

The programs are built side by side into `release/`, so each app finds the others beside it and `data/` one folder up.

### Dependencies

Third-party and personal Pascal libraries are git submodules under `src/packages/`, pinned to known-good commits. A submodule bump is its own commit, the build scripts run `git submodule update --init --recursive`, and every package must be GPLv3-compatible with an explicit licence file.

| Package | Use | Licence |
| --- | --- | --- |
| Clipper2 | Seam allowance offsetting and polygon booleans | Boost |
| BGRABitmap | Antialiased canvas drawing, SVG; PNG images in the CLI and API, without the LCL | Modified LGPL |
| ConsoleTools | Argument parsing and help for the CLI | MIT |

**Clipper2** comes from our fork of AngusJohnson/Clipper2 ([github.com/billbsing/Clipper2](https://github.com/billbsing/Clipper2)), which carries our fixes (see `documents/known-issues.md`). That repository was archived in October 2026, and development moved to PolyClipping/Clipper2, which is becoming C++ only, so the fork stays on the original. When we need to change Clipper2's behaviour it becomes our own Pascal-only Clipper2, keeping Angus Johnson's notices. Projects depend on `src/core/clipper2/osclipper2.lpk` rather than adding it to their search path.

**ConsoleTools** ([github.com/billbsing/console-tools](https://github.com/billbsing/console-tools)) is our own, with fixes made for this project upstream: long-only option order, `NO_COLOR`, parsing argument lists for tests, FPC 3.2 support.

### Testing

Testing runs throughout development; the LCL-free core means most logic is tested without any UI.

**Tools.** FPCUnit with the console runner, in a separate project in `tests/`, built and run by `opensloper-make.sh test` with heaptrc (`-gh`), so leaks fail too. CI (`.github/workflows/ci.yml`) runs it with the formatter and the standards check.

**What is covered.** Geometry (with a tolerance helper, never exact float equality), the formula engine, the evaluator's order and states, names and IDs (never reused after delete, undo, save and reload), every operation against hand-checked cases and their failures, piece detection and seam allowance, marking assignment, transforms, seams, annotations, materials, pattern units and conversion, copy and paste, measurement files and merges, undo (execute then undo restores the exact earlier state), save → load → save giving identical JSON, tiling, packing, and the PDF, SVG and DXF bytes against stored files. Tables that document the program are held to it: the operations, file members, API methods, CLI options and shortcuts, and the committed reference pages and schemas must match what the program writes.

**Regression patterns** in `tests/patterns/`: patterns with two measurement sets each and their expected results, the report from `opensloper-cli check --json` (each variable's value and each object's state and position, to 1e-6 mm). Every expected file found is checked, so a change that silently alters a draft fails. `tests/patterns/README.md` has the commands to make one, after checking its values by hand.

**Habits:**

- Core tests written alongside, or before, geometry and formula code
- Every bug gets a failing test before the fix
- UI kept thin, so what matters can be tested without it
- End-to-end checks drive `opensloper-cli serve` through the Automation API and its renders; the GUI is checked by hand on a private Xvfb display
- `opensloper-make.sh test` and `opensloper-make.sh check` before every commit

### Documentation

User documentation is Markdown in `docs/`, built into a static site with Zensical, published with GitHub Pages and to be shipped offline with the apps.

**Tool.** Zensical, the successor to Material for MkDocs from the same team (MIT), configured in `zensical.toml` and built by `opensloper-make.sh docs` into `release/site_docs` in strict mode, so broken links fail; it is installed in a local `venv` from `requirements.txt`. Pages use only common extensions (admonitions, tables, code, keys), so moving to another generator means rewriting the navigation, not the pages. It runs at build time only and is not shipped with the apps. The manuals are CC BY-SA 4.0 (`docs/LICENSE`); code stays GPLv3 or later.

**Structure.** One site for all the tools, since they share concepts: Getting started, Tutorials, Measure, Design, Publish and Reference. Pages are written by task ("Add a size"), not by menu.

**Generated where it can be,** so the code is the single source of truth:

- `opensloper-cli doc TOPIC` (`Sloper.Docs.Reference`, `Sloper.Docs.Schema` in `src/docs/`) writes the reference pages from the tables the code itself uses: `functions` (formula functions, operators and unit suffixes), `operations` (`Sloper.Core.OperationInfo`), `files` and the three JSON Schemas (`Sloper.Core.FileInfo`, see File format and storage), `shortcuts` (`Sloper.Core.Shortcuts`, which the apps take their keys from), `cli` (`Sloper.CLI.Arguments`, which also builds the parser) and `api` (`Sloper.API.Methods`, which also gives the MCP tool list). A topic ending in `.schema.json` is written to `docs/reference/schemas/`; `doc` with no topic lists them.
- Tests hold each table to the code: every member a saved object or file has is listed and every listed one written, formula kinds match `FieldUnitKind`, every API method listed is answered and every parameter read, every CLI option is in the parser, and no app gives one key press to two commands.
- Generated pages and schemas are committed, so the site builds without a Pascal toolchain, and a test fails while one differs from what the program writes. They carry a note saying so and are never edited by hand.
- Tutorial patterns live in `docs/examples/` with their measurements, so readers can download them; their pictures are drawn by `export-draft --labels --upto=NAME` from the list in `docs/tutorials/images.list`, so one finished pattern gives a picture for every step. Finished example patterns that are not tutorials live there too, with their shared measurements in `docs/examples/measurements/`, and the Example patterns page links to them. Tests check that every pattern there opens with no problems and every object the list stops at exists.
- `.github/workflows/docs.yml` checks the files against the schemas and publishes the site on pushes to `development` that touch the docs.

**Folders:** `docs/` is the user documentation; `documents/` is internal development notes, including this document.

### Translation

Planned for the community release; nothing is translated yet. Already in place: user-visible text is in `resourcestring` sections (`opensloper-make.sh check` reports message text that is not), strings are UTF-8 throughout, and names in formulas and files are stable keys and IDs, kept apart from what is shown.

Decision: the standard Free Pascal and Lazarus route, gettext `.po` files, so translators can use common tools (Poedit, Weblate, Crowdin).

- **Program text.** Each project writes its template to a shared `data/languages/` (`opensloper-design.pot` and so on), with translations beside it. The GUI apps use `LCLTranslator` and `SetDefaultLang`, which also translates `.lfm` captions; the language comes from a `language` preference, then `--lang`, then the system locale. The core and CLI use LazUtils' `TranslateResourceStrings`, which needs no LCL, so the layering rule holds.
- **The measurement catalogue's** names, descriptions and how-tos are extracted into their own `.pot`, with the key as context, so translators have one workflow; a translated copy of the JSON per language would fall behind unnoticed.
- **Never translated:** formulas (keys, names, functions and the `.` decimal point, since a decimal comma would clash with argument commas and a pattern must mean the same everywhere; Valentina translates its formula vocabulary, which ties its files to translation tables); saved files; Automation API method and field names and error codes (messages may be translated, so scripts check codes); CLI output meant for scripts.
- **Exported text** such as title block and piece labels follows a language chosen in the output profile, falling back to the app's, since a pattern is often printed for someone who reads another language.

**Rules for code now**, so translation later needs no rewriting: build messages with `Format` and placeholders, never by joining pieces; one resourcestring per sentence, plurals included; leave room for longer text (German runs about 30% longer) with anchored or autosized controls; keep units, numbers and dates out of the resourcestring.

## Measurements app

Measurement files are edited in their own application, `opensloper-measurements`, as SeamlyMe does for Seamly2D. Information flows one way through the three apps, each owning one kind of file and only reading the ones before it: measurements → patterns → layouts.

**Why a separate app.** One measurement file drives many patterns, and recording someone's measurements is a different job from drafting, sometimes by a different person: it needs a form, not a canvas. It is also the home for importing Valentina and Seamly2D files, size tables, and later the client library.

**One format, one or several sizes.** A file is one person's set, with a `value` per measurement, or a size table, with `sizes` and a `values` list per measurement (`null` for a size with no value). Patterns do not change: they read `@waist` either way, and everything reads the value of the selected size, the first until another is chosen. Wherever a file is chosen a size is chosen with it; a size with no value for a key the pattern uses is one error ("@waist has no value for size 42"). A table always keeps at least one size; the first size added to a personal set takes over its values. Pattern-specific ease stays in the pattern's `#` variables, never in the measurement file.

**One unit is the central control.** All reading, writing and editing of measurement files goes through `Sloper.Core.Measurements`, used by all three apps and the CLI, so key rules, units and formatting are the same everywhere. A long-running service the apps connect to was considered and rejected: it would add process management, sockets and crash handling for a problem that a careful write and a merge by key already solve.

**No measurement set needed to draft.** A pattern can be drafted with plain numbers and `#` variables; only formulas that use an `@` key show the missing-key error, and adding a key from that error first offers to make a measurement file.

**Small edits from the drafting app.** The Measurements tab allows adding a missing or new key and changing a value or description. The edits are held until Save, which writes them in one write. Everything else (sizes, order, imports) is done in the measurements app, which File → Measurements → Edit in Measurements App… opens at the file. These edits are not part of the pattern's undo, since the file belongs to every pattern that uses it, so the status bar names what was saved.

**Writing safely.**

- Every save of small edits re-reads the file just before writing, applies its changes and writes atomically (a temporary file, then rename), so a change made elsewhere is never overwritten; `ChangeMeasurementsInFile` makes every change or none.
- Every app with a measurement file open watches it. A file seen changing must read the same on two checks before it is taken in, and one that does not parse is left alone. With no unsaved edits the app reloads. The measurements app, with unsaved edits, merges by key against the file as last read: a key changed on one side takes that side, and one changed on both asks which to keep. Saving over a file that changed since it was read is refused until the change has been taken in.
- `TMeasurementDocument` keeps its own undo history of the file's text (`TTextHistory`, shared with the publish app); a change read from disk clears it, since an older step would bring back what the file has just replaced.

**From the CLI and the Automation API:** `measurements set`, `list` and `missing`, and the `get_measurements`, `set_measurement` and `missing_measurements` methods, so a script or Claude can add a missing measurement. `set` keeps a key's description unless given one, and a size table needs a size; `missing` exits with 1 when something is missing, as `check` does.

### Measurement editor

Measurements are entered against a built-in catalogue of standard body measurements, with a body figure that shows where each is taken. This is the editing side of the measurements app; the user pages (Measure) describe it as used.

#### Measurement catalogue

`data/measurement-catalogue.json`, read by `Sloper.Core.Catalogue`; without it the table still works. It lists 72 measurements so far, the ones most drafting needs, from Seamly2D's 246; more are added as entries, with no code change. It also holds the figure outlines, so one file describes everything the panel draws.

- Keys are whole words with no abbreviations: `waist_circumference`, not `waist_circ`. Custom keys remain allowed for anything not listed, and nothing renames keys already in use (`waist` and `back_length` stay custom).
- Definitions follow ISO 8559-1:2017 in meaning; the descriptions are our own wording, since the standard's text cannot be copied.
- Each entry has `key`, `name`, `group`, `description`, `howTo`, `view` (front, back or side), `overlay` (its line on the figure) and a typical `range` in mm. A value outside the range is a warning, never a refusal, so unusual bodies are not blocked.
- `translations` lists the entry's names in other programs' files by format (`{ "seamly2d": ["waist_circ"] }`), the first being the one exported, so the catalogue is also the translation table for import and export. `knownNames` lists a format's names with no entry yet, so they go back out unchanged rather than as custom measurements.

#### Importing and exporting other formats

`Sloper.Core.SeamlyFormat` reads and writes Seamly2D's `.smis` and `.smms` and Valentina's `.vit` and `.vst` (the same files with the root renamed; Valentina's names match Seamly2D's for everything in the catalogue). Older versions than individual 0.3.0 and multi-size 0.4.0 are refused with the reason, and exports are checked against their schemas. Other programs' files would use the same translation, each as one more format in `translations`.

- **Nothing is altered silently.** A name is translated to our key, or kept as a custom key (dropping Seamly2D's leading `@`, our own prefix), or corrected or numbered when it breaks our rules or is taken; the app then lists what was renamed, kept and changed.
- Values written as formulas are worked out and stored, with a note, since our files hold values; anything else, such as a function, is left at 0 and listed.
- A multi-size file gives a base value with an increase per 2 cm of size and 6 cm of height, while a size table has one dimension: importing makes a column for each size within three steps of the base, at the base height, and reports the heights left out. Exporting needs even sizes from 22 to 72, takes the middle as the base, fits a straight line through the first and last values and reports any value more than 0.5 mm off it.

#### Body figure

Front, back and side outlines drawn by us (no third-party images, so no licence questions), with BGRABitmap. The file's measurements are drawn faintly and the current one highlighted; clicking a line selects its row. One base figure per view, with each measurement's line from the catalogue `overlay`, so a new measurement is a catalogue entry, not a new picture.

#### Editing

Measurements are added from the catalogue by group, with search, leaving out those already in the file, so a file holds only what its person needs; an added one takes the catalogue's description and starts at 0 (which the range warning points out) or, in a size table, empty. Values are entered in the display unit and stored in mm. Given a pattern, the app lists what the pattern uses that the file cannot give it (missing keys, and sizes with no value), with one button to add or go to each; the list follows edits and the saved pattern.

## Design app

### Evaluator

The evaluator (`Sloper.Core.Evaluator`) turns definitions into coordinates in dependency order, and records why anything fails instead of crashing.

**Graph.** Measurements, variables and every draft object are nodes, keyed by ID as text (`12`) and measurements by `@key`. A node depends on its direct inputs (an offset's base point) and on every reference in its formulas. The nodes are sorted topologically (Kahn's algorithm) and evaluated in order, so inputs are always current when reached. Patterns are small, so `Evaluate` rebuilds the graph and recomputes everything on every change; dirty tracking waits until dragging needs it.

**Cycles.** `TPattern.SetFormula` refuses an edit that would make a node depend on itself, naming both nodes, so the graph stays acyclic. A loaded file can still hold a cycle: the nodes on it become errors and their readers are blocked.

| State | Meaning | Example | Display |
| --- | --- | --- | --- |
| Valid | Computed fine |  | Normal |
| Error | Formula problem | Unknown name, divide by zero, a measurement the set lacks | Red, message on hover |
| Invalid | Geometry impossible | Parallel lines, distance past the end of a curve | Red, message on hover |
| Blocked | An input failed | Depends on an invalid point | Faded orange, "blocked by point C" |

Each node keeps its last good value, drawn ghosted while it fails, so the drawing has no sudden holes. A key missing from the measurement set is one error on its `@` node, and everything reading it is blocked. A reference to an ID that no longer exists is an error on the reader.

**Editing API.** `TPattern` (`Add…`, `SetFormula`, `Rename`, `Delete`) reports refusals in `LastError`, `LastErrorField` and `LastErrorPos`; `Delete` is refused while other nodes use the object. Undo wraps these calls (see Key design decisions). `TPattern` stays the one entry point, but operations that only rework objects already there live in their own units behind its methods: changing type in `Sloper.Core.TypeChange` and merging and breaking points in `Sloper.Core.PointMerge`, which work through a small public editing kernel at the end of the class (`SetError`, `ForgetGraph`, `DeleteNode`, `OrderObjectsByInputs`, `ReplacePoint`, `ReplaceEdge`, `CheckPoint`, `CheckEdgeTarget`); the materials are a `TPatternMaterials` the pattern owns (`Sloper.Core.PatternMaterials`). Operations that make new objects (transforms, offset runs, round corners, notes) stay in `TPattern`, since moving them would open its object-creation internals. Callers go through `TPattern`'s methods, not the units, so they need only `Sloper.Core.Pattern` (decided 2026-11-09).

**Edges as segments.** Every edge keeps its computed geometry as straight or cubic segments, so length, positions along it, splitting and crossings work the same for every kind of edge. For crossings an extended edge adds a ray off each end along its tangent, so an extended line is its infinite line.

**Dragging.** A field that is a plain number changes when dragged; a formula field is locked (see Drafting experience).

### Names and IDs

References are stored as IDs and shown as names, so renaming an object changes one field and never breaks a formula.

**Formulas.** The user types names (`Line_A_B.length + @waist/4 + #ease`) with completion. On commit each name is resolved and the ID form is stored (`{12}.length + @waist/4 + {3}`): objects as `{id}.property`, variables as `{id}`, measurements by their key. Unknown names are refused as typed. Fields, tooltips and messages show the current names.

**IDs.** Positive integers from one counter per pattern file, shared by every kind of object: variables, points, edges, pieces, materials and annotations. The kind is in the object's `type`, so the ID has no prefix.

- The counter is saved as `nextId` and only goes up, so an ID that has been saved is never reused: not after deleting, undoing, saving or reopening. This matters beyond the file: layouts refer to pieces by ID, and a reused ID would quietly put a different piece in an old one's place.
- IDs are unique within one file. Pasted and imported objects get fresh IDs, with references inside the pasted group remapped.
- UUIDs were rejected: they are only needed across files, and would make every stored formula long and hard to read.

Measurements are the exception: patterns refer to them by key, so any measurement file with the same keys works.

**Name rules:**

- Letters, digits and underscore, not starting with a digit; dashes and dots clash with formula syntax (`A-2`, `A.x`)
- Function names and keywords are reserved
- Case is kept for display but compared case-insensitively
- Unique within each namespace: draft objects (points, edges, pieces and notes share one), `#` variables, `@` measurements, materials
- Automatic names count like spreadsheet columns: `A` to `Z`, `AA` … `ZZ`, `AAA`, taking the next free name and skipping reserved words (`ABS`, `COS`). They never contain digits, so a trailing number always means a copy
- An edge is named after its ends (`Line_A_B`) unless the user names it

**Renaming** is checked as typed, cannot be confirmed with a taken or invalid name, and is one undo step. Undo and redo never fail or prompt, since they restore states that were already valid.

**Clashes from paste or import** are resolved automatically and reported: the next free number is appended with no separator (`A` → `A2`), and a trailing number is taken as the copy number, so a copy of `A2` becomes `A3`, not `A22`.

### Formula engine

Decision: a small recursive-descent parser of our own (`Sloper.Core.Formula`, on the tokenizer `Sloper.Core.FormulaLexer`). TFPExpressionParser was tried first, but on FPC 3.2.2 its error positions refer to translated text, it lets comparisons, `if()`, `mod` and strings through, and it reports errors as exceptions; our syntax is small enough that our own parser is less code than wrapping it.

**Syntax.** Numbers with `.` as the decimal point and an optional unit (`2in`), `+ - * /`, `^` (right-associative and tighter than unary minus, so `-2^2 = -4`), brackets, the functions listed on the generated Formula functions page, and references: `@measurement`, `#variable`, `Object.property` and `Repeat[index].property`. Angles are in degrees.

**Pipeline.** The tokenizer reads either the display form the user types or the stored ID form, and reports errors with their position. `TFormula` resolves names, collects references for the dependency graph and refuses unknown names and properties. The expression tree is built once and walked on each evaluation. The stored form keeps the user's spacing and number spelling; only references change.

**Failures are states.** A parse error gives a message and a position in the text as typed. Evaluation errors (division by zero, square root of a negative, `asin` out of range, a missing value) set `ErrorMessage` and `ErrorPos`. FPU exceptions are masked during evaluation, and infinite or NaN results become errors. A formula that fails to parse keeps its text, so a file round-trips unchanged.

**Depth is limited.** A formula nests at most 256 levels (`MAX_FORMULA_DEPTH`): brackets, signs, function calls and each operator in a chain such as `1+1+…` count. The parser, evaluation and freeing all recurse, so without the limit a crafted file or API call overflowed the stack and crashed the program (found in the security review of 2026-11-08). For the same reason, graph walks over dependencies (`TEvaluator.Reaches`) use a list of pending nodes rather than recursion, since a file can make a chain as long as it likes. Nodes left over after sorting are told apart in one pass (`TEvaluator.MarkCycles`, Tarjan's algorithm with its own stacks): those in a cycle are errors, those that only read one are blocked. Walking the cycle once per node took minutes for a crafted file with a cycle of 20,000 objects.

### Pattern units

Decided 2026-11-04, built 2026-11-07.

**A pattern has one unit, mm, cm or inches, and every number in its formulas is in that unit.** In an inch pattern `@waist/4 + 1` adds one inch. The unit is the file's `units`, chosen when the pattern is made from the unit in Preferences; changing the preference never changes an existing pattern.

**Formulas are worked out in the pattern unit.** Every length a formula reads arrives in it: measurements (files store mm and are converted as read), variables, and properties such as `.x` and `.length`. A plain number therefore needs no label: in `(@waist * 2) + 400` the whole sum is in one unit, whether a number was meant as a count or a length. Angles are degrees everywhere and never converted. Where a result becomes geometry (a free point's `x`, an allowance, a radius) it is scaled to mm, so **geometry, computed state, the canvas and every export stay in mm**. In code, the context's `LengthScale` divides lengths as they are read, and length fields are read with `EvalLength`, which multiplies by it.

**What the user sees.** The properties, status bar, rulers, grid, snapping read-outs and drag rounding (0.1 mm, 0.1 cm or 0.01 in) use the pattern unit, and new objects start at round values per unit (`STARTING_LENGTHS`). Everything that writes a computed length into a formula writes it in the pattern unit. In the Automation API, formulas and variable values are in the pattern unit, while reported positions and lengths stay mm. The Measurements tab stays in mm, since it edits the measurement file, not the pattern.

**Unit suffixes.** A number may carry a unit, `400mm`, `1.5cm` or `2in`, and is converted to the pattern unit when evaluated. Names cannot start with a digit, so `2in` cannot be read as a name. A suffixed number keeps its meaning in any pattern and is never rewritten by a conversion; a drag of a suffixed length keeps its unit.

**Converting a pattern** (Tools → Convert Pattern Units…, `Sloper.Core.UnitConvert`). Only lengths are rewritten (`400` mm → `15.75` in); counts, ratios and angles are not, so each plain number's role must be known. A role is a power of length (0 a number or angle, 1 a length, 2 an area). The field fixes the result's power (`FieldUnitKind`), and the expression tree gives linear equations between the unknown powers of numbers and variables, solved by Gauss–Jordan elimination: operands of `+` and `-` share a power, `*` and `/` add and subtract them, `sqrt` halves one. A variable used both as a length and a count leaves its numbers open. Numbers still open (`400 * 2` in a length field) are listed, marked in their formula, for the user to choose before Convert is enabled; each choice is worked through again. The conversion is one undo step, rounds lengths to the new unit's drag precision, converts material allowances, and leaves formulas with errors alone. Geometry does not move, apart from that rounding.

### Operation set

Nine point operations and the edge types cover bodice, skirt and trouser blocks; circles, arcs, rounded corners and offset edges were added for accessories (see Accessories). Many of Valentina's ~30 tools become special cases once formulas can read properties such as `{4}.angle`. Every operation with its members and readable properties is on the generated Operations and objects page, from `Sloper.Core.OperationInfo`, which tests hold to the code.

**Conventions:**

- Geometry in mm, formula numbers in the pattern's unit (see Pattern units).
- x right and y down, as on screen and in Valentina and Seamly2D, so 10 cm down is `dy = 100`. Angles in degrees, 0° pointing right, positive anticlockwise as seen on screen, so 90° points up. Everything that turns or tells left from right means it as seen on screen. The canvas and SVG take model coordinates as they are; PDF and DXF, which are y up, flip on export. Changed from y up on 2026-11-05, before any file was released.
- Points read `.x`, `.y`; every edge `.length`, `.angle1` (start handle) and `.angle2` (end handle, pointing back along the edge); straight edges also `.angle`.
- Curve handles are formulas, so curves stay parametric (`length1 = @neck/6`). A curve path shares one tangent per node, which keeps its joins smooth.
- **Drawing a curve path.** The Curve tool chains separate curves, as the tutorials use; Shift+click instead carries the curve it just drew on through the point (`TPattern.ExtendCurve`, in `Sloper.Core.TypeChange`), one undo step per click. The edge keeps its ID, name and role and becomes a curve path; its handles stay, the old end's angle turns to point from the node before it towards the new point (a Catmull-Rom tangent), and the new stretch's handles are a third of its chord. Refused while anything uses the edge, as its end moves. Chosen 2026-11-09 over a separate tool or a Join command, so the Curve tool's plain clicks stay as they were.

**Crossings.** `extend` lets an edge run on past its ends along its end tangent, so long construction lines are not needed just to find a crossing. `pick` is a stored crossing number, counted from 1 along the first edge, so the result stays the same crossing when measurements change. Project onto edge takes the result nearest the point, and a perpendicular onto a curve counts only where it meets the curve square.

**Split edge** makes two parametric parts that follow the source edge and the point, for dart rotation and slash-and-spread. The source stays as construction, and pieces and seams that used it take the parts.

**Repeat.** N evenly spaced points between two points or along an edge (equal arc length), for buttons, pleats, tucks, notch rows and belt loops. `count` is a formula (`round({12}.length / 80)`), so the number of points can change with measurements, and evaluating must never hand out IDs. So the points are virtual: only the repeat is stored, and its points are named `Btn[1]` … `Btn[6]` (brackets cannot appear in other names, so these never clash). A point gets an ID the first time something uses it, recorded against its index in the repeat's `points[]` in the same undo step; references are then ordinary IDs, and the ID stays with the index when the count changes. When the count drops, references to missing indices become errors rather than moving to another point; when it rises again, the same point comes back. Until used, a point's key is the repeat's ID and index (`12[3]`); `TPattern.UsePoint` turns it into an ID, and `CheckPoint` keeps such keys out of files. The repeat is edited through its first point; deleting it deletes the repeat, refused while anything uses one of its points. Tools → Points → Repeat Points (`AddRepeatAtSelection`) makes one between two selected points or along one selected edge, with a count of 3 and ends included, and selects its first point.

### Transforms

A transform is one operation that makes parametric copies of a set of points and edges, so rotated, mirrored or moved copies follow measurement changes. Uses: dart rotation, slash and spread, mirroring a half, and moving a section aside to develop it (facings, yokes, pockets). Rotate turns about a pivot by a formula angle (a dart angle is `{5}.angle - {6}.angle`); Mirror reflects in a straight edge, two points, or a point and an angle; Move shifts, and can turn about a pivot in the same step.

**Copies are real objects.** Each has its own ID and a name made once from its source's and the suffix (`A_r1`), and records its source and transform. Its geometry is always computed, so it cannot be dragged, but it can be an input to any operation. A copied edge starts with its source's role, which can be changed. Selecting an edge pulls in its ends, and copied edges join copied points. Since every edge is segments, a copy transforms the segments, exactly, with no case per kind of edge. Pieces are not copied: clicking inside a copied outline makes a new piece.

**In the graph** the transform works out one movement (a `TAffine2`) from its pivot or axis and formulas, and each copy depends on the transform and its own source, so a failing source blocks only its copy.

**Behaviour.** Making a transform and its copies is one undo step. Deleting a source is refused while a copy uses it; deleting a transform takes its copies, unless something else uses them, and a copy cannot be deleted alone. In the app, Tools → Transform has Rotate Copy, Mirror Copy and Move Copy, named so each says it leaves the sources where they are; the transform starts with no movement, selected, ready for its formula. Rotate and move keep lengths, a free check that seams are unchanged. Cut on fold is a piece property applied at output; Mirror is for geometry the draft itself needs.

**Example: shoulder dart to side seam.** Draw a slash from the bust point to the side seam and split the side seam there; rotate the outline between the dart and the slash about the bust point by the dart angle, so the shoulder dart closes and a side dart opens; make the rotated originals construction; click inside the new outline.

**Example: separating front and back**, as Seamly2D users work but staying parametric. Draft front and back overlapping; Move Copy the back's outline aside; make the back-only originals construction, keeping shared edges such as the side seam as outlines; click inside each outline. The front comes from the originals and the back from the copies, so a measurement change moves both, the side seams match exactly, and the back is reshaped by editing the overlapped draft, which stays the master. This is interim; a better front/back method can replace it without changing the file format.

**Code.** `Sloper.Core.Transform` (`TTransformObject`, `TPointCopy`, `TEdgeCopy`); `TPattern.AddTransform` expands the sources and makes the copies. A file lists a transform before its copies.

### One canvas

A pattern is one drafting area: every object is on the same canvas, drawn in pattern order with pieces under edges and edges under points.

**Drafts and layers were taken out** (2026-11-03), with the draft tabs, the Layers panel and the Garment view, to reduce clutter; the Garment view came back on 2026-11-13 as a side panel tab (see Garment view). They added rules (inputs on the same draft, moving between layers, what shows versus what prints) for little use. Locking came back per object (see Locked objects under Drafting experience).

**One garment or product per file.** Garments that share no geometry (a skirt and a top) are separate files, brought together in the publish app. Pieces whose geometry depends on each other (a sleeve cap from the armhole, a collar from the neckline, a gusset from the panel edge it is sewn to) stay in one file. References between files would need a dependency graph across files and IDs unique beyond one file, so they are not planned.

**Overlapping pieces.** Front and back are drafted overlapping, as on paper, and separated with Move Copy (see Transforms). Layers or a tab per piece were rejected (2026-11-05): front and back share points and lines, which would have to belong to one layer, and a tab per piece means deciding the pieces before drawing, against making a piece by clicking inside an outline. Isolating, hiding and stacking pieces cover what layers were wanted for, as view state (see View options for overlapping pieces under Drafting experience).

**View state is kept out of undo.** Zoom, centre, hidden roles and hidden annotations are saved in the pattern's `view`, so it reopens as it was left, but are left out of the undo snapshots and the modified flag. The ID counter is also kept out of the snapshots, though it is not view state.

**Older files** with drafts and layers still load: `drafts` and each object's `layer` are passed over, the old `view` is ignored, and the drafts' IDs stay retired.

### Drafting experience

The canvas feels like Inkscape, but every point records how it was placed relative to others. Inkscape itself was rejected as the drawing tool: it stores absolute coordinates, while patterns are designed with distances and formulas. The user pages (The design window, Drawing, Pieces) and the generated Keyboard shortcuts page describe the window as used; this section keeps the decisions.

**Snap-inferred operations.** The user draws freely and the snap target decides the recorded operation: a point level with A at 250 mm becomes an offset from A with `250` ready to change to `@waist/4`; a crossing becomes an intersection; empty space gives a free point. This is construction-based (an explicit dependency graph), not constraint-based like FreeCAD's Sketcher, so no solver is needed. Snapping (`Sloper.UI.Snap`) looks within 8 pixels, in order: an existing point; a crossing of two edges (an edge and its own split parts do not count); a place on an edge, measured from the nearer end; a spot level with or square to a point, the start of the line being drawn first; else a free point. Values round to 0.1 mm, and the status bar says what a click will make.

**Canvas** (`Sloper.UI.Canvas`, with the LCL-free `Sloper.UI.View`, `Sloper.UI.Scene`, `Sloper.UI.CanvasInput` and `Sloper.Core.Drag`):
- **Edits to the selection** (`Sloper.UI.SelectionEdits`): nudge, delete, copy, cut and paste, and the Tools menu's split, offset, change type, merge, break, round corner, markings and transforms. Each checks that the selection fits, makes one undo step through the document and returns what to select and show (`TSelectionEdit`); the canvas only applies the result, so the rules are tested without the LCL.
- **Drawing** (`Sloper.UI.PatternPainter`, which draws what the canvas hands it and decides nothing about tools or input). BGRABitmap, on a grid in the pattern's unit at the spacing in Preferences. Outlines are solid ink and construction thin, grey and dashed; errors red, blocked orange, failing objects faded at their last good result.
- **Selection.** Click selects (points win over edges, and both over pieces), Shift adds. A drag from empty canvas or a piece draws a box and selects everything wholly inside it (`ObjectsInBox`).
- **Dragging** changes only fields that are plain numbers, rounded to 0.1 mm, 0.1° or 0.0001; a point placed by a formula refuses, with the reason shown until release. Curve handles work the same way: a handle with a formula is drawn hollow and refuses, and the two handles at a path's inner node share one angle, so the join stays smooth. Arrow keys nudge 1 mm (10 with Shift), merged into one step per run.
- **Deleting** removes the selection, refused with a message while something else uses an object. Only a plain Delete or Backspace deletes: Shift+Delete means Cut elsewhere, so it does nothing here rather than lose what was meant to be kept.
- **One gesture at a time** (`Sloper.UI.CanvasInput`). A drag holds an open document change until its button is released, so while a press, drag, box or pan is under way the canvas ignores other buttons and the keys that change the tool or the pattern (tool letters, arrows, Delete, the seam keys); Escape still cancels. Only the button that began a gesture ends it, and a second press of that button means its release was lost, so the gesture is cancelled first. Space for panning is let go when focus leaves the canvas, since its key-up goes elsewhere.
- **Changing an edge's type** (Tools → Edge → Change to Line / Change to Curve) replaces it in place (`ConvertToLine`, `ConvertToCurve`), keeping its ID, role and users. A new curve starts straight with handles a third of the way along. An arc becomes a line between two new points offset from its centre by its own formulas. Refused: a circle, transform copies, split parts and other derived edges, a line whose `.angle` a formula reads, and a line that is a piece's fold or whose part, copy or offset is (`CheckNoFoldFollows`), since a fold has to be straight. Split parts and edge copies take their straightness from their source each time they are evaluated, so they follow a change of type.
- **Merging points** (Tools → Points → Merge Points, `TPattern.MergePoints`) joins two or more points, as Inkscape joins nodes. Points are parametric, so nothing is averaged: one definition is kept and everything that used the others uses it. The name is the first one the user gave, else the lowest made name (`MergedName`). The definition is the named point's unless it reads one of the others. Refused: a line between two of the points that something else uses, a path that would pass through one point twice in a row, two transform copies.
- **Breaking a point** (`TPattern.BreakPoint`) is the opposite: each edge meeting there gets its own point, placed from the original by an offset of 0, 0, so it follows the point until dragged apart. Pieces join edges by position, so a piece around the point stays closed. Names are numbered as copies (`M` → `M1`, `M2`). Merging again gives the one point back.
- **Labels** (`LabelKeys`) are hidden by default so the drawing stays clean, and appear when they help. View → Labels chooses Contextual (the default: the hovered object, the selection with its inputs and dependents, and what a tool snaps to or asks for), All (everything named) or None, which also draws smaller points; holding N shows all. Labels never print unless turned on.
- **Zoom tool** (Z), as Inkscape's: dragging a box zooms to it, a click zooms in a step about the pointer and Shift+click out. The box is the canvas's own gesture, the select tool's box without selecting, so the tool object holds only its hint. The publish preview has the same as View → Zoom Area (Z while the preview has the keyboard, a toggle on the toolbar), since it has no tools; while it is on, presses zoom rather than drag pieces, and Escape turns it off. Added 2026-11-12 (issue #3). The publish preview also has the design canvas's scroll bars, over the pages and the Fit Pages margin (`PagesBounds`), moved by hand only (issue #6).
- **Rulers** line up pixel for pixel with the canvas, with ticks as close as stays readable (`Sloper.UI.RulerTicks`, tested without the LCL).
- **Tools** (`Sloper.UI.CanvasTools`). Each drawing tool is an object (`TCanvasToolHandler`) with its own press, move, Escape and key handlers, what it snaps to and labels, what it draws over the pattern through `TPatternPainter` and the state it keeps between clicks (a line's first click, a seam's two sides). It reaches the canvas only through `TCanvasToolHost` (document, view, draw role, select, message, repaint). The canvas keeps pan, zoom, `TCanvasInput`, transform picking and the select tool's gestures (dragging points, handles and callout tips, the selection box, the pick menu), and hands the rest to the tool in use, so a new tool is a new class and a row in `CanvasToolInfo`, the one table of each tool's key, icon and caption that the canvas and the Tools menu share. The canvas works out the tool keys once. Moved from the canvas on 2026-11-09 and checked as the painter was (commit `c2256df`): both builds driven through every tool on a private Xvfb display, 42 screenshots matching pixel for pixel.
- **Locked objects** (issue #16, done 2026-11-13). Edit → Lock and Unlock, or the Locked box in the properties panel, lock the selected objects as one undo step; the flag is a definition, saved as `locked` on the object and left out when false. A locked object is drawn greyed (its ink without colour, half way to the paper; its piece fill likewise), can still be selected, copied and used as an input, and its formulas still run, so it follows what it reads. It cannot be moved, edited or deleted: drags and nudges refuse (`CanDrag`, `CanDragNote`, `CanDragHandle`); the properties panel makes its rows read-only apart from the Locked box; `TPattern.SetFormula`, `Rename` and `Delete` refuse it with "E is locked; unlock it to change it". Every other path (a piece's cut, notches, markings, splitting one of its edges, merging points it reads, the API) is caught by the document: `BeginChange` records each locked object's definition (`LockedObjectText`: as saved, without `locked` and a repeat's used `points`, which change when others use them) and `EndChange` undoes a change that alters or removes one, setting `ChangeRefused` and the reason. A locked object must therefore be unlocked in its own step before it is changed. Converting the pattern's unit rewrites every formula, so it begins its change with `CheckLocks` off. A repeat's points follow the repeat. A locked piece takes no new markings. A pasted copy starts unlocked. The API has `set_locked`, and `get_object` gives `locked`. The Objects tab shows "OK, locked" in the state column.
- **Copies.** A copied point is drawn as a small neutral diamond, not a hollow marker (which means locked by a formula) nor red or orange (problems); its edges are known by their diamond ends. Hovering or selecting a copy draws a faint dashed line to its source, from point to point or middle to middle, and lights the source as if hovered; selecting the transform does so for each copied point (`CopyLinks` in `Sloper.UI.Scene`). A refused drag or nudge names the source and transform ("A_r1 follows A (Move Copy 'Back'). Edit A to change it.", `CanDrag`). Tools → Transform → Go to Source, or double-clicking a copy, selects the sources of the selected copies, or what a selected transform copies, and brings them into view (`GoToSource` in `Sloper.UI.SelectionEdits`). Done 2026-11-11.

**Toolbars and icons.** Every command is a `TAction` shared by its menu item and toolbar button, so captions, shortcuts and states stay in step; the measurements and publish apps do the same through `TCommandSet` (`Sloper.UI.Commands`). Menu keys and tool letters come from `Sloper.Core.Shortcuts`, which also writes the shortcuts page. Zoom In is Ctrl++: Qt names the main keyboard's `=`/`+` key `=` in a menu, so Plus is set as the keypad's key, which it shows as `+`, and `SetActionShortCut` adds Ctrl+= and Ctrl+Shift+= (Minus adds the keypad's) as secondary keys, so Ctrl+= still works. A form looks for secondary keys only in action lists it owns, so `TCommandSet`'s list belongs to the form (2026-11-12, issue #3). A command bar runs along the top and the drafting tools down the left, wrapping into a second column when the window is short. The Tools menu lists the drawing tools, then groups the rest in short submenus (Edge, Offset, Points, Markings, Draw As, Transform); a submenu item may have a shorter caption than its action, which keeps the full name for the tooltip. Tooltips appear above the pointer so they do not cover the buttons it moves to (`Sloper.UI.HintPlacement`). Icons are Tabler Icons outline SVGs (MIT) in `data/icons`, drawn by `Sloper.UI.Icons` at the screen's scale in the theme's text colour; without the folder the toolbars show captions. Qt styles draw toolbar and menu dividers too faint on a dark theme, so the toolbar dividers are drawn by the app and menu dividers set by a style sheet rule (`AddToolDivider`, `ShowMenuDividers`).

**Properties panel** (`Sloper.UI.Properties`): the selection's type, name, formulas (shown with names, with readable captions such as "Point 2 handle in"), role and computed values. Enter or leaving a field commits one undo step and Escape puts the text back. A refused formula keeps its text, shows the reason under the field and puts the cursor at the problem. The panel keeps the row layout, the column divider and formula editing; the rows for each kind of object come from **section objects** (common, edge, marker, repeat, piece in `Sloper.UI.PieceProperties`, seam and note), made for the selected object and freed on each rebuild, so no control field can outlive its rows. Each section adds its rows at fixed places (type, name, fields, its own rows, result, end), can claim fields to show in its own rows, and queues a change that adds or removes rows (type, marker, edge allowance, grainline) to run once the control's handler has returned. Text the panel works out from the pattern is in `Sloper.UI.PropertyText`, free of the LCL and tested.

**Formula completion** (`Sloper.UI.FormulaCompleter`, with the LCL-free `Sloper.UI.Completion`): `@` lists measurements, `#` variables, a dot an object's properties, and a bare word everything, matches first; choosing an object goes straight on to its properties. The object being edited, and objects in a variable's formula, are left out, since neither would be accepted.

**Spacing** (decided 2026-11-10, `Sloper.UI.Spacing`). The three apps lay controls out on one gap, 8 pixels at 96 per inch and scaled to the screen: between neighbouring controls, including a caption and the field under it, and between a control and the edge of its panel or dialog. A container sets it on its children through `ChildSizing` (`SpaceChildren`, or `SpaceBetween` for one already inside another's gap), so two neighbours are never twice the gap apart, and dialogs' OK and Cancel rows take it through `SpaceButtons`. The Lines tab keeps its own, tighter list of checkboxes; toolbars, the canvas, the status bar and the side panel's headers are not laid out on it.

**Side panel sections** (built 2026-11-10, `Sloper.UI.Accordion`). The side panel is an accordion rather than tabs down its side: each tab has a header across the full width, and exactly one is open, its header and those before it at the top, its panel under them, and the headers after it collapsed at the bottom. Clicking a header, or Enter or Space on it, opens it and closes the one that was open; Up and Down move between headers. A click does not take the keyboard from the canvas, as a tab did not. Vertical tab captions were hard to read, and the headers leave the panel's whole width to the open tab; the layout arithmetic is in the LCL-free `Sloper.UI.AccordionLayout`, where tests check it. The publish app's tabs (Pieces, Patterns, Output, Notes) use the same control, with Problems under it. Each app keeps its open tab in the settings file by key (`sideTab`, `publishTab`, such as `objects`), not by place, so reordering or adding tabs does not open the wrong one; a key the app does not know opens the first tab. The publish app writes only its own key, reading the file again first, as preferences are saved.

**Side panel and editable panels.** Tabs for properties, objects, variables, measurements, lines and materials share `Sloper.UI.ListPanel`: a search box over a list, with the selection held by key. Decided 2026-11-07, built 2026-11-08: a list is read in the grid and, where a value fits a cell, edited there (F2, Enter or typing opens it; Enter or leaving commits; Escape reverts); a refused value keeps its text, the cell red and the reason in the status bar; buttons sit in one row at the bottom with Add first; file commands go in the main menu, not in panels. Materials is the exception, read-only with editing in a dialog, since colour and fill do not fit a cell. An editable list selects cells, not rows, and Delete reaches the tab only when no cell is open. A commit is made by the row's key, after the grid has closed the cell, so a row that moves cannot take the edit; the commits are in the LCL-free `Sloper.UI.PanelEdits`, where tests make them.

- **Variables** are edited in the grid, one undo step per cell; a selected variable is not shown in the properties.
- **Measurements** edits are held as pending changes, shown bold with `*`, and do not change the pattern until Save, which re-reads the file and writes every change at once (see Measurements app). Choosing another size, opening another set or pattern, closing, or the file changing on disk asks Save or Discard.
- **Test size** scales every measurement the pattern reads by 1% a step, up to 20% either way (`TPattern.MeasurementScale`). It is session state: not an undo step, never saved, and the set cannot be edited until it is back at 0%, so a scaled value can never reach the file.

**Pieces.** The Piece tool makes a piece with one click inside a closed outline, with the starting allowance, and stays on until Escape; a region that already has a piece selects it. A notch click adds a notch to every piece using that edge, so both sides of a seam match.

**Automatic piece detection** (`Sloper.Core.PieceDetect`). Instead of clicking round an outline in order, the user clicks inside a region:

1. Build a planar graph from outline edges only, split where they cross.
2. Sort edges round each node by tangent, prune dangling nodes, and walk faces taking the next edge clockwise.
3. Pick the face containing the click, and set each edge's reversed flag so the path runs clockwise. Nothing is ever drawn or clicked in a particular direction.

Construction lines are left out by their role, and an edge with outline split parts is left out in favour of them. A piece refers to whole edges, so a region bounded by part of an edge is refused, naming the edge to split. Panels often overlap (a skirt's side seams cross above the hip), cutting each panel into faces no whole edge bounds; then a second pass treats edges as whole and finds the smallest simple closed path round the click. A path where one edge ends part way along another is refused, since it is two regions joined at a point.

**Piece details** (`Sloper.Core.Piece`, `Sloper.Core.SeamAllowance`):

- **Grainline**: an angle, drawn through the middle of the extent over 60% of the span, or two points; new pieces start at 90°.
- **Notches** sit on a point on the seam line or at a position along an edge from its own start, drawn as a 6 mm mark in from the cutting line, square to the edge. A point off the seam line makes the piece invalid.
- **Cut and fold.** A cut count and a mirrored flag. Being on the fold is one setting, `foldEdge`, so it cannot disagree with another flag; the fold edge is straight, has no allowance and shows a bracket. The draft stays half a piece; opening it out is for output.
- **Seam allowance.** The piece's width, and an edge's own in a field such as `edge2.allowance` that exists only while it does. Clipper2's offset takes one width per path, so `OffsetOutline` builds the raw offset with a width per segment (mitred convex corners, bevelled past four times the allowance) and Clipper2's union removes the loops.
- A piece is a node whose inputs are its edges, so they cannot be deleted while it uses them; a gap over 0.01 mm makes it invalid. A piece that takes on a newer point moves to the end of the object list, since files list inputs first.

**View options for overlapping pieces** (planned 2026-11-05, hiding added and built 2026-11-13, #10). View state like zoom, kept out of undo, in the View menu, working on the selected pieces:

- **Hide Piece** takes the piece off the canvas with everything only hidden pieces use (decided 2026-11-13): what the piece is made from, through inputs and formulas (`DependencyKeys`), less what a shown piece, or an object in no piece (a construction line, a note), still uses. A line shared by front and back stays; a construction line drawn from a hidden piece's point keeps that point. Seams keep nothing showing, as they are not drawn, and a note goes with its pieces when all of them are hidden. **Show All Pieces** brings them back, and the status bar says how many are hidden. Hidden pieces still print (decided 2026-11-13): layouts, the publish app, the CLI and the API's `render` include every piece; File → Export Draft follows the screen, as it does for hidden roles.
- **Isolate Piece** works on one piece alone: everything it does not use, but its notes, is drawn faintly under a wash of paper and cannot be clicked, snapped to, box-selected or labelled (decided 2026-11-13). Choosing it again, or Escape on the Select tool with nothing selected, shows everything. Isolating a hidden piece shows it; hiding the isolated piece ends isolation. Export ignores isolation.
- **Bring to Front** and **Send to Back** change only the order pieces are drawn in. Clicking inside overlapping pieces still picks the smallest, as before.

The core works these out (`TPattern.IsHidden`, `IsDimmed`, `IsActive`, `PiecesInDrawOrder`) and keeps them until the view, an evaluation or the object count changes; the canvas, snapping and the painter only ask. The Garment tab follows all three (see Garment view).

**Align and distribute** (`Sloper.Core.Arrange`). Modelled on Inkscape's Align and Distribute, but each action rewrites the selected points' definitions so the arrangement holds when measurements change: align sets `x` to `{A}.x`; distribute makes inner points Between points at `i/(n+1)` or Along edge points at equal arc length. A point placed by a formula is only replaced on a yes, and nothing formula-driven is overwritten silently. A point's operation changes in place (`ConvertToFree`, `ConvertToBetween`, `ConvertToAlongEdge`), keeping its ID, name and users. The Align tab is hidden (2026-11-05) because the panel does not work correctly; the code is reached through the Automation API's `arrange`.

#### Copy and paste

Decided and built 2026-11-07. Edit → Copy, Cut and Paste copy definitions, not positions, so a pasted object stays parametric. Seamly2D has no object copy and paste, so this follows our own rules.

**The main use is a second line on the same points.** A pasted edge joins the same points and is selected, ready to become a stitch or fold line (see Several lines in the same place). It is then independent; a line that must stay on its source is an offset edge instead.

- **In the same pattern** only the selected objects are added; references outside the selection stay on the originals. **In another pattern** the selection comes with the whole chain it depends on, so the fragment stands alone: this is how a collar is taken from one pattern into another. The pattern's `identity`, a random value made with the pattern and kept by Save As, tells the two cases apart; since IDs are never reused, an outside reference whose ID still exists in the same pattern is the same object.
- Variables come with formulas that use them; in another pattern a variable with the same name and formula is reused, and a different one is kept as a copy (`ease2`). Measurements are matched by key.
- Pasted objects take fresh IDs and free names by the clash rules, and the status bar lists renames. The paste is one undo step, and the copies are selected.
- Only points, repeats and edges are copied; the status bar says what was left out. A transform copy is copied as the plain object it gives. What the chain needs but cannot copy is listed under `needs`, and pasting it into another pattern is refused, naming it.
- Formulas are in the pattern's unit, so pasting between patterns in different units is refused.
- When a text field has focus, Cut, Copy and Paste act on its text. Cut is Copy then Delete as one step, refused when Delete would be or when something selected cannot be copied.

The fragment (`opensloperFragment`, version 1) holds `identity`, `units`, `selection`, `variables` (each with its display formula, for matching), `objects` and `needs`; the clipboard also gets the names as plain text, for formula fields. It is read with the pattern file loader through an ID map (`AddPatternItems`). `Sloper.Core.Fragment` builds and pastes without the LCL; `copy_objects` and `paste_objects` do the same in the Automation API.

### Links and problem display

Direction and dependency marks appear only on hover, selection or piece creation, never permanently, to keep the draft free of noise.

| Link | Shown when | Form |
| --- | --- | --- |
| Piece direction | Hovering or selecting a piece | Small chevrons at each edge's middle, not arrowheads at the ends |
| Copy source | Hovering or selecting a transform copy, or selecting its transform | Faint dashed line to the source, which is highlighted |

**Problems** (`Sloper.Core.PatternCheck`) are listed in plain words and counted in the status bar: failing objects, gaps where a piece no longer closes, seams out of tolerance, markings outside their piece or in none, marked points in no piece. The same list is the Objects tab's Problems filter, `check` in the CLI and the Automation API.

**Objects tab.** Every point, edge, piece and note with its name, operation, formulas, computed value and state, with search (names, operations, formulas and note text, so searching a name finds what reads it) and a filter (points, edges, pieces, notes, problems). Clicking a row selects the object and brings it into view at the current zoom; double-clicking zooms to it. Since names and data are read there and formulas complete names, hidden labels never make formulas harder to write.

**Property grid.** The properties lay out each field on one row, name left and value right, like the Castle Game Engine inspector, so the whole selection fits a narrow panel. The splitter between the columns is kept as a share of the width in `settings.json`; a long name is cut with an ellipsis and shown in full as a tooltip; a refused formula's reason shows on a row under its field.

### Markings

Decided 2026-11-05, built 2026-11-06. Internal markings (placement, stitch and fold lines, holes, buttons) are drawn like any other line or point and given a role or a marker, and the app attaches them to the right piece itself. Seamly2D and Valentina draw the line in the draft, then add it to a piece's details as an internal path. Markings must belong to a piece so they move with it in layouts and printing, and overlapping pieces (front drafted over back) make that ambiguous; OpenSloper keeps the requirement but resolves it automatically. Stitch holes stay a piece marking along an edge (see Accessories).

#### Edge roles

| Role | What | On paper |
| --- | --- | --- |
| Construction | Thin dashed guide | Never |
| Outline | Piece boundary | The cutting line |
| Placement | Pockets, trims, button bands | Thin, solid |
| Stitch | Topstitching or an internal seam | 1 mm dashes (shorter than the seam line's 2 mm) |
| Fold | Fold or pleat line | Dash-dot |
| Cut | Slit or internal cut | Solid, at the cutting line's width |
| Skive | How far a leather edge is thinned | 4 mm dashes |
| Edge finish | How far edge paint, burnishing or binding runs | Dotted |

Roles are a fixed list in the app, like KiCad's technical layers, never defined per pattern, so output settings can rely on them. On the canvas and in draft SVG each marking role has its own colour (placement blue, stitch green, fold purple, cut teal, skive brown, edge finish grey, keeping clear of red and orange, which mean problems) and dash; on paper they are black (`ROLE_DASHES`). For machines fold is a score line, cut is cut with the outline, and the rest are marks; DXF-AAMA writes them on layer 8. Where lines coincide, a draw priority puts the higher role on top (`ROLE_PRIORITIES`: construction, edge finish, skive, placement, fold, stitch, cut, outline).

Tools → Draw As, and a box on the command bar that always shows it, choose the role of lines drawn next; it starts at Outline each session. Roles and markers are ordinary undoable property changes.

#### Point markers

| Marker | Use | Drawn as | Starting size |
| --- | --- | --- | --- |
| Plain | Ordinary point; not printed | | |
| Hole | Dart points, pocket corners, rivets, snaps, eyelets | A circle, cut as a hole | 4 mm |
| Button | Button and buttonhole positions | A circle with a cross | 15 mm |
| Match dot | Matching points between pieces | A small dot | 3 mm |

The marker and its size (`markerSize`, a formula, across in mm) belong to the point, not to its pieces, which replaced the hole marking each piece kept with its own diameter. A repeat takes a marker for all its points, so a row of buttons follows the count. A transform copy keeps its source's marker, as a copied edge keeps its role. A marker outside a piece it is on, or a hole on the fold line, makes the piece invalid. Holes are cut as true circles; buttons and match dots are marks. Older files' `hole` markings are read as Hole markers.

#### Automatic piece assignment

When an edge takes a marking role or a point a marker, it joins every piece it lies inside (an edge counts as inside when more than half of nine points sampled along it are, `LiesInside`; a repeat when more than half its points are). Inside several overlapping pieces it joins them all and the user takes it off the extra ones (changed from asking, 2026-11-05). Inside none, it stays draft-only and is reported ("does not print").

The assignment is stored in the piece's `markings[]`, not recalculated, so markings never jump between pieces silently; one that a measurement change moves outside its piece is reported. Where a line lies is only known once computed, so `TPattern` queues it and `Evaluate` assigns it. A new piece takes every queued line and marked point inside it. Another marking role keeps the assignment; construction, outline or Plain takes it off every piece, and deleting the line or point takes it off in the same step. Tools → Markings → Attach Marking to Piece and Remove Marking change it by hand. Older files' `placement` and `fold` markings are read as lines with that role.

#### Several lines in the same place

Edges are separate objects, so any number can join the same two points, each with its own role (a fold line and a stitch line on one segment); the second is named `Line_A_B2`. They coincide when they run along the same path either way round within 0.01 mm, and each group is drawn 3 px apart on screen only, so it shows there is more than one; geometry and printing are untouched. A click picks points first, then edges nearest first, the highest role on top, then pieces, smallest first. Clicking again at the same spot, or Alt-click, cycles through them, the status bar saying which ("Fold1 (2 of 2 here; click again for the next)"), and a right-click in the Select tool lists everything under the pointer (`ObjectsAt`, `CoincidentEdges`, `NextKey` in `Sloper.UI.Scene`).

**Offset edge.** Topstitching usually runs a fixed distance from an edge, and drawing it point to point would need new points at every corner, so an offset edge makes it directly, following its sources when measurements change. It takes one edge or a run joined end to end within 0.01 mm. Outer corners are mitred, bevelled past four distances as seam allowance is; inner corners are trimmed where the offsets cross; a closed run joins up at its start. Curves are followed within about 0.01 mm. The edge is invalid when a curve bends tighter than the distance or an inner corner would trim away a segment.

- **Inside and outside a piece** are worked out when the edge is made and stored as left or right (inside is on the right going clockwise). The offset reads only its edges, never the piece: a stitch line inside a piece is one of the piece's markings, and reading the piece would be circular.
- Selected edges are put in order along the run, following the first selected edge's direction (`ChainRun`); a branch or gap is refused. A piece's edges must be one unbroken stretch of its path (`PieceRun`).
- Tools → Offset → Inside Piece makes a stitch line that joins the piece; Outside Piece, Edge Left and Edge Right make construction edges. All start 10 mm away.

**Fold on the outline.** A fold on the piece's own edge (centre front on the fold) is not a second line but the piece's `foldEdge`.

#### Role visibility

The Lines tab (`Sloper.UI.RolesPanel`) lists Construction and each marking role with a checkbox, a sample and Solo, then Show All, Hide All and presets ("Seams only", "Leather"). Outline is not listed, since pieces are made from it. It changes the view only: hidden lines are still stored, evaluated and printed, and their problems still reported, but they are not drawn, clicked, snapped to or labelled, unless selected (in the Objects tab). The status bar says how many kinds are hidden, so nothing seems to vanish without reason. Which roles are hidden is view state, saved as `hiddenRoles` in the pattern's `view` and kept out of undo; presets are the user's, in `settings.json` as `rolePresets`. Draft export follows the screen. Which markings reach paper is the publish app's choice (see Output profiles).

### Seams

A seam records that edges are sewn together. It is its own object, not a property of an edge: nearly every outline edge is sewn, and a role could not name the partner. The app cannot work seams out for itself (equal lengths do not show that two edges belong together, a sleeve cap is meant to be longer than its armhole, and an edge shared by two pieces need not be sewn), so the user makes seams and the app suggests them.

**The object.** `sideA[]` and `sideB[]` each list `piece` and `edge`, in order along the seam. A side can span pieces (a sleeve cap to a front and a back armhole) and have gaps (a waist either side of a dart). Both sides may use the same piece (dart legs) or the same edge (a centre back on a mirrored piece). Several seams may use one edge: a neckline sews to a collar and a facing.

- **Whole edges only**, as for pieces. Splitting an edge that pieces and seams already use moves them onto the parts in the same undo step (`TPattern.FollowSplit`, 2026-11-07): paths take both parts in order, an edge's own allowance goes to both, a notch past the split moves to the second part without moving on the piece, and a seam takes both parts, so its lengths are unchanged. A piece folded on the edge keeps it.
- **Direction.** Each edge runs the way its piece's clockwise path runs, so sewn edges normally run opposite ways, and side B is paired from its far end by default; the user never chooses a direction. `reversed` flips this for the cases the default gets wrong, mirrored pieces most likely.
- **Length check.** Each side's length is the sum of its edges on the seam line. `ease` (default 0) is the length side B should have over side A and `tolerance` (default 1 mm) the allowed error, both formulas, so gathers can follow the pattern (`ease = @waist * 0.5`). A mismatch is a problem, not a state: the seam stays valid, and `check`, the CLI's exit code and the Problems filter report both lengths and the difference.
- **Unsewn edges are not reported**, since the check cannot tell a hem or opening from a forgotten seam without marking every edge.

A seam is a node whose inputs are its pieces, so it is blocked while one fails, and a piece a seam uses cannot be deleted. Seams are named `Seam`, `Seam2`; they have no place on the canvas, so they are selected from the Objects tab.

**In the app.** The Seam tool (E): a click on a piece's edge adds it to the current side (on a shared edge, the side of the edge clicked picks the piece), Tab moves to side B, Enter makes the seam as one undo step. Each side shows its colour and running length, with the difference in the status bar. A selected seam shows both sides with chevrons for direction, and Flip in the properties. **Suggest Seams** lists likely pairs, none ticked: edges shared by two pieces first, then edges on different pieces within 1 mm of each other's length. Accepting is one undo step.

### Materials

Pieces are coloured by the material they are cut from, so colour carries meaning (main, lining, contrast, interfacing, leather) as well as telling pieces apart. They are called materials, not fabrics, because leather, foam and stiffener go in the same list.

**The list.** Each pattern has materials with an ID, a name (its own namespace), a colour, a fill style (tint or hatching) and an optional default allowance. They are ordinary objects: adding, renaming, recolouring and deleting are undo steps. New ones are named `Material`, `Material2` and take the first unused palette colour. The last material cannot be deleted, nor one that pieces use.

**Size** (decided 2026-11-14, issue #19). A material can have a width and a length, in the pattern's unit like its allowance and converted with it: a width alone is a roll (fabric off the bolt), both a sheet (a board, a remnant), neither (the default) no size and no check. A length without a width is refused, and taking the width away takes the length too. `allowTurns` is for material with no grain (felt, foam, most leather boards), as on a publish material sheet.

- **Fit check.** Each valid piece on a sized material is measured as it lies on the material: the cutting line turned so its grainline runs along the length (as drawn when it has none), and opened out when it is on a fold, as cutting on fabric folded double needs the same width (changed 2026-11-14 from the draft's own axes: a paper pattern is laid on the fabric by its grainline, however it was printed). A piece wider than a roll, or past either side of a sheet, is a problem ("Front is 152 cm across, wider than Main at 140 cm"); with `allowTurns` only if it fits neither way. As for seam lengths, the piece's state does not change: the problem is listed, counted, and reported by `check`, the CLI and the API (`AddMaterialFitProblems` in `Sloper.Core.PatternCheck`, `TPieceObject.GrainShape` and `GrainExtent`, `FitsMaterial`).
- **One piece at a time.** Whether all the pieces fit together is the publish app's Material needed; the design app checks only what can never be cut.
- **File and API.** `width`, `length` (left out when 0) and `allowTurns` (left out when false) on each material; `set_material` takes them (a width of 0 takes the length away too) and `list_materials` reports them.
- **Editing.** The Materials dialog has Width and Length fields under the allowance, with the pattern's unit and empty for none, and an Allow quarter turns box, each one undo step; the list shows the size ("150 × 200 cm", "150 cm roll").

**Assignment.** Each piece is on a material and takes its fill from it, with an optional per-piece colour or fill override. A piece with no material is drawn unfilled and reported. A piece takes the material's allowance when it goes on that material, and does not follow later changes, so it can still be set by hand.

**Starting out.** A new pattern has one material, Main, which has no ID and is not written to the file until the list is first changed, so simple files stay simple and existing IDs do not move. The first change gives Main an ID and puts every piece on it; until then a piece's empty material means Main, and afterwards it means none. Captions and DXF text name the material only once the materials are explicit.

**Display.** Fills are semi-transparent and under every line, so seams, notches, labels and overlapping pieces stay readable; only pieces are filled. The palette stays distinguishable for colour-blind users, and the material name is in the piece label, so colour is never the only cue. View → Piece Fills turns fills off on the canvas (a setting, not part of the pattern); the publish window always shows them. Hatching angles go by place in the list (45°, 135°, 0°, 90°…), so hatched materials differ on a black-and-white print, and are computed in screen points, so the spacing holds at any zoom. Printing fills is off by default, to save ink; the publish app offers a tint or hatching per print.

**Cut list.** Grouped by material from each piece's cut settings ("Main: Front ×1 on fold, Back ×2 · Lining: …"), as the `{cutlist}` field for title blocks and notes. A layout with several patterns joins their lists.

**Code.** `Sloper.Core.Materials`, and the pattern's list in `Sloper.Core.PatternMaterials`, with `TPattern` answering `MaterialOf`, `PieceLook`, `PieceCaption` and `CutList`, so the canvas and every export ask the same place. The Materials tab is a read-only list with the cut list (`Sloper.UI.MaterialPanel`); editing is in `Sloper.UI.MaterialDialog`, each field commit one undo step applied at once so the canvas follows, with only Close. The dialog is modal, so it handles undo and redo keys itself, except while a field holds uncommitted typing. The list and swatches are `Sloper.UI.MaterialGrid`, shared by panel and dialog.

### Annotations

Notes, callouts and a title block print with the pattern, fixing a gap found with Seamly2D, where adding text over the final design was difficult.

| Kind | Lives in | Anchored to | Typical use |
| --- | --- | --- | --- |
| Note | Pattern | A point, edge position or piece, plus an offset; or free | "Stay-stitch neckline" |
| Callout | Pattern | Text anywhere, leader tip on a point, edge position or piece | Pointing at a notch, dart or seam |
| Piece label | Pattern | Its piece | Name, cut count, on fold (part of the piece) |
| Information block | Layout | A page corner | Pattern, measurements, size, date |
| Sheet note | Layout | A place on the printed layout | Instructions, notions, assembly order |

**Anchored, so annotations stay parametric.** A note stores its anchor's ID and an offset (`dx`, `dy`, formulas in the pattern unit), not coordinates, so it moves with the geometry; a free note has `x`, `y`. It is a node whose input is its anchor: blocked, and drawn faded at its last good place, while the anchor fails, and deleting an anchor is refused while a note uses it (changed from making the note free automatically: the refusal was already built and loses nothing). Make free turns a note free where it is. Pattern notes can be added at any stage of drafting and are saved in the pattern; information blocks and sheet notes belong to a layout and are edited in the publish app (see Publish app).

**Fields.** Text can hold document fields (`{pattern.name}`, `{measurements.name}`, `{date}`, `{page}`, `{pages}`, `{cutlist}`, `{materials}`), filled in by the substitution code sheet and pattern notes share (`Sloper.Core.TextFields`), and draft values such as `{=Line_A_B.length}`. Each draft value is a formula field of the note (`value1`, `value2`), so a failing value blocks the note, deleting what it reads is refused, and renames show; the file keeps them inline in stored ID form (`"Hem {={12}.length} mm"`).

**Stages** (decided 2026-11-06). Stages 1 to 3 are built; stage 4, SVG stamps, is under Open items.

- **Stage 1, anchored notes.** Plain multi-line text with a size in points at true print size, `print` (false for screen-only drafting notes), the Text tool (X) with the anchor chosen by snapping as for points, dragging the offset when it is a plain number, View → Annotations to show or hide them all (`hideAnnotations` in `view`, out of undo), and one sans-serif font (Helvetica in PDF). Notes draw above everything and are picked first. Text is typed in the properties.
- **Stage 2, callouts and draft values.** A callout is a note with `leader` (`arrow`, `dot` or `line`), so there is one object and one file type; a free note cannot have one, since the tip is the anchor. The Callout tool (A) takes the tip, then the text's place; dragging the tip re-anchors the callout to whatever it is dropped on (`SetNoteAnchor`). `align` and a white `box` (black on projector output) work the same for pattern notes and sheet notes.
- **Stage 3, fonts** (built 2026-11-12). A family name (`font`, left out for the default sans-serif), `bold` and `italic`, on pattern notes and sheet notes alike (`TTextStyle`). A name is trimmed, at most 64 characters, and refused when it holds a comma, quote, bracket, `;`, `<`, `>`, `&`, `\` or a control character, which would split a font list or break a file or an SVG attribute. The properties and the publish app's Notes tab pick from the system's fonts or take a typed name. The canvas draws the font; SVG names it before the default families, with `font-weight` and `font-style`.
  - **Finding a font** (`Sloper.Output.Fonts`): the bundled fonts (`data/fonts`) first, then the system's font folders (`TAppPaths.SystemFontDirs`), listed with FCL's `fpttf` cache and read with its TrueType parser, each folder in name order so the same machine always picks the same file. Files named like the family are read first; the rest only when those lack the exact style, so a missing font reads every file once (about 0.3 s for 2,600 fonts on a Linux desktop). The nearest face wins, bold counting before italic; answers are cached for the process, behind a lock, since the API runs on its own thread.
  - **Measuring.** The unit installs a measurer in `Sloper.Core.TextFields`, so a named font's box, alignment and print tests use its real advance widths everywhere (canvas, SVG, PDF, layout). The default font is still estimated from Helvetica's average width (bold a little wider), so existing layouts do not move.
  - **PDF.** A named font, or the bundled Noto Sans for default-font text Helvetica cannot print, is embedded as a CIDFontType2 with Identity-H, a ToUnicode map (so text copies and searches) and a FlateDecode file. The file is cut down to the glyphs used by our own subsetter (`Sloper.Output.FontSubset`), which keeps every glyph's number and empties the rest, so pages name glyphs by their numbers in the full font while being written (`/CIDToGIDMap /Identity`) and the subset is made at the end; its six-letter tag comes from a checksum of the glyphs, so the same text gives the same bytes. A style the family lacks is drawn: bold by stroking as well as filling (`2 Tr`), italic by a 12° slant. A font not installed, one with PostScript (CFF) outlines, or one whose licence forbids embedding prints in the default font instead, measured as it, and the layout lists one warning per font (`FontProblem`). Glyphs past U+FFFF, and letters the font lacks, print as its missing glyph.
  - **PNG** images still draw with the bundled fonts only (see Drawing images without the LCL), so a note in a named font shows in a bundled font there.

### Accessories

OpenSloper drafts accessories in fabric and leather (bags, pouches, wallets, hats, belts) as well as garments, with the same parametric core; the additions are useful for garments too.

**What the core already gave.** A bag is driven by product dimensions (`#width`, `#height`) or, for a range of sizes, a size table of them read as `@width`: nothing in a measurement file assumes a body. A gusset's length reads the panel edge it is sewn to (`Curve_A_B.length`), and seams check that they match. A panel of a six-panel cap is drafted once and rotated into copies.

**Circles and arcs**, brought forward from phase two for round bases, crowns, brims and rounded corners, which need exact lengths for the gussets sewn to them. They are stored as cubic segments of at most 45° like every other edge, so lengths, positions, splitting and crossings work unchanged, while `.length` and `.radius` come from the exact formulas. A circle starts at 0° and runs anticlockwise; an arc runs from `angle1` to `angle2`, the shorter way by sign, so 350° to 370° crosses 0°. Their ends are not points: to join a line to an arc, put an along-edge point at its end. A circle nothing crosses can be a one-edge piece.

**Rectangle tool** (R): two clicks make three offset points and four lines from `width` and `height` formulas, in one undo step, since most bag pieces start as rectangles.

**Rounded corners** (Tools → Edge → Round Corner) replace the corner between two straight edges that share a point with an arc of a formula radius (`cornerArc`), trimming both edges at its tangent points (`cornerPoint`) with ordinary split parts. The part at the corner and the original edge become construction, so the sharp corner stays as a guide. A piece on the edges is rounded too (changed 2026-11-09 from refusing until the piece was deleted, which predated `FollowSplit`): it takes the parts as for any split, then the arc in place of the two parts at the corner (`TPattern.FollowCorner`), reversed when its path runs from the second edge to the first; notches on those parts go to the arc's end beside them, and seams take the arc. A piece folded on either edge is refused, since a fold stays one straight edge.

**Offset edges** (see Markings): stitch lines, facings, linings and turn-backs as ordinary parametric edges, unlike seam allowance, which only applies to a finished outline.

**Markings inside a piece**, printed with it and following measurement changes: holes from point markers, marking lines from edge roles (see Markings), and stitch holes along an edge. Stitch holes take a spacing formula and a size, and are spaced evenly between the ends with the spacing adjusted to fit, so they stay even when the size changes; `.holes` counts them, which helps work out thread. A hole must lie inside the cutting line, and sizes and spacing must be above 0.

**Material per piece.** Leather, foam, stiffener and interfacing are materials beside main and lining (see Materials). Leather is often cut with no seam allowance: an edge's own allowance can be 0, a material can carry a default allowance, and an output profile can cut on the seam line.

**Output for machines** (line types, machine profiles, cutting a piece as it lies, material sheets) is in the publish app (see Cutting machines and material sheets).

**Not included.** Fashion drawing is left to Inkscape and Krita. Hardware sizes (rings, buckles, zips) are entered as variables; the Notions library under Open items would change that.

### Garment view

Built 2026-11-13 (#4) as the **Garment** tab of the side panel, after Properties and Objects. It shows each piece as sewn, darts closed and folds opened, shaded so it looks slightly rounded, to glance at while drafting. It shows proportions and shaping, not how pieces go together, fit or drape, which stay with the Blender export (see Blender export under Publish app). It is read-only and nothing in it is saved.

**History.** A Garment window (step 13) showed the finished garment flat, front and back, with pieces joined along their seams. It was taken out on 2026-11-03 with drafts and layers (see One canvas; commit `b920e6c`). It looked unfinished: darts stayed open, curved seams that differ left gaps, a sleeve sewn to a front and a back armhole did not join, and the flat outlines gave no sense of a body inside.

**Pieces side by side, not front and back** (decided 2026-11-09). The first design joined pieces along their seams into a front and a back view, which needed a front, back or both setting on every piece, since the app cannot tell a front from a back, plus seam welding and registering the two views. Each piece is now shown on its own, arranged as on the canvas, so nothing has to be set or stored and the tab works on any pattern with pieces. It gives up the assembled look, which the old window never got right and Blender does properly. A file from before 2026-11-03 that gives a piece `view` loads with it ignored.

#### The tab

- **Arranged as on the canvas.** Each piece keeps its drafted place. A piece with a grainline is turned about the middle of its outline so the grainline as drafted is upright, as it hangs on the body; one without keeps its canvas direction. Pieces that overlap, on the canvas (front drafted over back) or once darts close and folds open, are drawn overlapping in the canvas's drawing order and not pushed apart (decided 2026-11-09): the tab mirrors the canvas, and separating pieces is the drafter's job there (see Overlapping pieces). A piece cut more than once is shown once. It follows the canvas view (built 2026-11-13, #10): hidden pieces are left out, an isolated piece is shown alone, and pieces are drawn in the view's drawing order (`TGarmentBuilder.Build` with `FollowView`); the API's `render` with `garment` shows every piece, in pattern order, as output does.
- **Material filter.** A list at the top shows one material's pieces, or all; it starts on the pattern's first material, so lining and interfacing do not cover the main pieces, and goes back to it when another pattern opens. View state, not saved.
- **Navigation.** The drawing fits the panel; the wheel zooms about the pointer, a drag pans and a double-click fits again. **Follow canvas**, off by default, uses the canvas's zoom and puts the middle of what the canvas shows in the middle of the tab instead. View state, not saved.
- **Live.** The scene is rebuilt after each change while the tab is showing, and not at all while it is hidden (it builds when it next paints). `TGarmentBuilder` keeps each piece with a fingerprint of everything its finished shape follows from (edges, outline, grainline, fold, markings, look, material and the seams that use it) and rebuilds only pieces whose fingerprint changed. If a build takes longer than a frame (16 ms), a drag updates the tab on release only.
- **Linked to the canvas.** Hovering a piece names it beside the pointer, lightens it, and shows it hovered on the canvas (`TPatternCanvas.OutsideHoverKey`); a click selects it there. A piece selected on the canvas is outlined in the tab, and a selected seam is marked on both its sides on whichever pieces they lie, as the warp leaves them, and on a closed dart's stitch line. Marks are drawn over every piece, so an overlapping piece cannot hide them. Nothing in the tab edits the pattern.
- **Notes** under the drawing say what was left out: a dart left open and why, a failing piece, or that there are no pieces (of the chosen material).
- **Export…** saves the pieces shown as SVG, or as PNG at a width asked for (16 to 4096 pixels, 1200 by default), drawn as on screen. The Automation API's `render` takes `garment` (and `material`, by name) for the same SVG or PNG, lit as by default; the CLI and API draw PNG with BGRABitmap's no-LCL build, as for the draft (see Drawing images without the LCL).

#### Building a piece

Everything is computed in the core from the evaluated pattern (`Sloper.Core.Garment`, no LCL), reading computed geometry.

1. **Close the darts.** A dart is a seam whose two sides are one edge each of the same piece, next to each other in its path, so they meet at a point, the apex (see Seams); other seams within a piece are ordinary seams. Each dart is closed by turning the piece about its apex (`Sloper.Core.Warp`): with θ the opening and α a point's angle round the apex from the opening's bisector, the point moves to 180° + (α − 180°) × 360° / (360° − θ), so each leg turns half the opening onto the bisector and the side opposite the dart does not move, while the rest of the piece opens slightly to take it up. Where the legs differ in length their ends meet halfway, by a stretch along the radius that fades to nothing opposite. The closed dart is drawn as one stitch line from the apex to where the legs met. Several darts are closed one after another, each as the ones before left it. A dart is left open, with a note, when a leg is curved, when its opening is over 90°, or when the space between its legs is inside the piece. A stitch-role marking line inside a piece is drawn as a stitch line, as it is.
2. **Place.** A piece with darts is moved back so the outline point furthest from every apex stays where it is on the canvas, so closing a dart moves only the outline near it. A piece cut on a fold is instead moved and turned so its fold stays where it was, along its drafted line, so both halves stay square to it. A piece with no darts does not move.
3. **Open the fold.** A piece cut on a fold is mirrored across its fold as placed, so it shows whole, as cut; the fold has no line.
4. **Turn upright** by its grainline (see The tab).

The warp is a map from piece coordinates to finished ones that the outline, stitch lines, markings and grainline all go through, so everything on a piece follows its darts.

#### Drawing

The painter decides nothing: the core hands it a scene (`TGarmentScene`: outlines, edge lines with whether each is sewn, stitch lines, markers, bounds), and one renderer, `Sloper.Output.GarmentPNG` in `src/output/thirdparty`, draws it for the tab, the PNG export and the API, so they match. `Sloper.Output.GarmentSVG` draws the same scene as SVG.

- **Outlines** are the seam lines, not the cutting lines. An edge in a seam other than a dart is drawn as sewn: a fine dashed line just inside its solid line (`GarmentInset`); other edges are plain. Notches, labels, the seam allowance, grainlines and construction are left out (the name shows on hover); buttons, holes, match dots, stitch holes, stitch lines and topstitching are drawn.
- **Fill** is the material's colour at full strength rather than the canvas's light tint; a hatched material is its light tint with the hatching over it; a piece with no material is grey.
- **Shading (semi-3D).** Each piece is lit as if wrapped round a body: across each row, the shade follows a half cylinder between the piece's left and right sides at that height (`GarmentShade`, a pure function of where the point is across the row, tested without the LCL), brighter in the middle and darker towards the sides, lit a little from the upper left. A row's sides are the widest found within 5% of the piece's height either side, then averaged over 4% (`GarmentSpans`), so rows cut short by a sloping hem or shoulder take the width just past it and the shading does not jump at an underarm. A long narrow piece lying across, at least three times as wide as it is tall once upright (a waistband), is shaded down each column instead, as a tube along its length; a sleeve or strap, upright by its grainline, is already shaded across its width. A soft shadow lies just inside each sewn edge on the side away from the light and a faint highlight on the side towards it, so seams look slightly raised. The light comes from 65° above the panel with 45% ambient light, so the sides never go black. Its direction (135°, upper left, by default), its strength (50%) and an off switch are in Preferences (Design), not the pattern.
- **Shadow.** A soft drop shadow under each piece separates it from the panel's background, stronger on a dark background so it shows in both themes.

The SVG draws the shading as one horizontal gradient per band of rows (about 4 mm each, 8 to 150 of them), clipped to the piece, and the shadows with blur filters: close to the screen, not exact.

#### Limits

Pieces never bend beyond the dart warp, so a flared skirt shows flat, gathers and pleats do not show, darts drawn only as marking lines stay as lines, and how pieces join, fit and drape are not shown. Accessories (bags, hats) are drawn the same way.

## Publish app

Publishing is a separate application, `opensloper-publish`, as KiCad splits schematic and PCB editing: the drafting app designs patterns, and the publish app brings finished pieces from one or more patterns together and prints them. The user pages (Publish) describe it as used.

**Why a separate app.** Information flows one way: the pattern defines the pieces, and publishing only arranges and prints them, so nothing is synchronised back. The drafting app needs no paper, printer or nesting code, and the publish app no snapping or formula editing. Both link the same core and evaluate patterns themselves. No pattern data passes between the processes; the only message is the apps' link below, which finds a window that is already open.

| Drafting app (pattern file) | Publish app (layout file) |
| --- | --- |
| Geometry, formulas, variables | Which patterns and measurement sets to use |
| Pieces: outline, allowance, grainline, notches, labels, cut count | Placement of each copy: position, quarter turns, flip |
| Pattern-space notes and callouts | Sheet-space title block and notes |
|  | Paper, margins, overlap, marks, output kind, profiles |

Printer calibration is neither: it belongs to the user's printer, so it is a preference.

**Layouts.** A layout lists its sources, each a pattern with a measurement set and size, with IDs from the layout's own never-reused counter; the same pattern may appear twice in two sizes. Placements refer to a piece by source and piece ID, so they survive measurement changes and edits, and are plain numbers, not formulas: a layout arranges finished pieces and is not parametric. A placement gives the top left of the piece's cutting line after any flip and turn, so it stays put when the piece grows. One file holds one arrangement; A4 tiles and one A0 sheet are two layouts.

**Keeping in step.** The publish app reads saved files, never the drafting app's unsaved edits. Once a second it compares a checksum of each source's files (file times only go to the second), and a changed file must read the same on two checks before it is loaded. New pieces wait in the tray; a deleted piece is a problem, never dropped silently. Publish… in the drafting app opens the pattern's layout (same name, `.slayout`) or starts one, in the publish window already showing it when there is one.

**Finding an open window** (decided 2026-11-14, issue #18). Each publish window listens on the apps' link (`Sloper.API.AppLink`), and Publish… asks every one listening, newest first, to show the pattern's layout, by its full path. The one whose layout is that file comes to the front and says so; when none does, Publish… starts another publish app as before. A window showing a different layout is never reused, since that would replace the user's work, perhaps unsaved: one window per layout. A new layout counts, since it is named after its pattern before it is saved.
- **The link is the automation socket's plumbing** under another kind of endpoint: `publish-<pid>.json` and `.sock` in the same private run folder, the same token, the same listener thread running each message on the main thread. A message is one JSON-RPC request (`show`, with `layout`), answered with `{"done": true}` or `false`; there are no other methods yet. A window that cannot listen still works, and Publish… then opens another window.
- **A file left by a crash** (or a killed process, which never runs its destructor) is removed when nothing answers behind it; a window writes its file only once it listens, so it is never one still starting. Each window allows 3 s to answer, since it answers between its own events.
- **Coming to the front** is the platforms' part. On Windows only the process the user works in may raise another, so the drafting app calls `AllowSetForegroundWindow` with the publish window's process before it asks. On X11 most window managers raise the window, though some only mark it as wanting attention. On Wayland a window may not take focus by itself: that needs an `xdg-activation` token passed from the asking app, which Qt 5 cannot use, so for now the window may only be marked. On macOS the same socket works; `open -a` would also hand a running bundle the file, but the apps are not yet bundled.
- **Not the service rejected under Measurements app.** That was a long-running process every app connects to, with its own lifetime and crash handling; this is a listener inside each window that ends with it, using code that already exists.
- **Rejected:** scanning for windows by title or class (different on each platform, impossible on Wayland), keeping the started process (a process number says nothing of the layout shown, and misses windows the user opened), and FPC's `SimpleIPC` or the UniqueInstance package (one named server per app, for a single instance, while there may be several publish windows; on Unix it also needs polling).

**Rotation in 90° steps**, so the grainline stays square to the sheet; there is no per-piece list of allowed turns. On paper the printed grainline shows how to cut, so a turn does not matter; where the piece is cut as it lies, a quarter turn is a warning (see Cutting machines and material sheets). A piece cut twice gets two placements, the second flipped when `cut.mirrored` is set.

**Problems.** A missing file, a deleted or failing piece, and a layout with nothing placed block export, so a blank PDF is never written. Unplaced copies, overlaps, pieces off the sheet, notes over pieces and odd rotations are warnings. They are counted at the left of the status bar, as in the design app, with how many stop printing (decided 2026-11-13, issue #21, replacing the list under the side tabs); pointing at the count shows them and clicking it lists them. Unplaced copies are left to the tray.

**Output kinds** (`kind` in `output`):

- **Tiled.** Pages with row and column captions (A1, B2), overlaps with diamond or half-circle marks that make a whole shape across two sheets, empty pages left out, and a cover with the test square, the print-at-100% reminder and the page map. Right-clicking a page leaves it out (`excludedPages`), shown grey and crossed, and struck through on the map; a change of paper, margin, overlap or kind clears the list, since the captions then mean other sheets. Paper is A4, A3, Letter or custom.
- **Large format.** One sheet `rollWidth` wide (914 mm by default), as long as needed, with the title, reminder and test square across the top.
- **Projector.** One dark sheet, thick light lines and large labels, for projecting onto fabric, with the test square to set the projector by.
- **Material sheet.** A fabric width or a board, `materialWidth` by `materialLength` (0 for a roll), one material at a time (see Cutting machines and material sheets).

Calibration scales everything printed at true size, including the test square. A piece on a fold prints as the half drawn with its bracket, except where it is cut as it lies, where it is opened out. `fill` tints or hatches pieces for that print, whatever their material's own fill.

**Information block and sheet notes.** The information block, `title` in the file (`corner`, `fields`, `everyPage`), prints on the cover or beside the test square, and optionally on every tile: plain lines chosen from a list, with nothing to type or place. Sheet notes are text in layout space, dragged like pieces, with fields (`{pattern.name}`, `{date}`, `{page}`, `{pages}`, `{cutlist}`, `{materials}`, `{materialneeded}`) filled in when printed; a note makes the page it is on print. Pattern notes print with their pieces and cannot be moved here.

The side panel has a section for each (#14, changed from one Notes tab holding both). The preview shows the block where it prints: in each printed tile's corner, above a single sheet beside the test square, and on the cover, which tiled output shows as a sheet left of the first column; `Sloper.Output.TitleBlock` places it for the PDF and the preview alike. Sheet notes are framed on screen, dotted or, when selected, solid, so they can be found and picked; picking one opens the Notes section on its details. The preview draws note text at its size in points, its lines a line height apart, as the PDF and the design canvas do, and as a tint when too small to read.

**The PDF writer** (`TPDFWriter`) is our own plain PDF rather than fcl-pdf: the scale is exact, the pages uncompressed, and the same layout gives the same bytes, which tests compare. Default-font text is the built-in Helvetica (or its bold and oblique forms); named fonts, and default-font text outside Latin-1, are embedded TrueType (see Annotations, stage 3). A file with only Helvetica text is byte for byte what it was before fonts.

**Code.** `src/publish` holds the window; layout loading, tiling, previews and exports are in `src/output` (`Sloper.Output.Layout`, `.Tiling`, `.LayoutPDF`, `.Preview`, `.TitleBlock`), so `opensloper-cli export LAYOUT` writes the same files without a window. `TLayoutDocument` keeps undo as the layout's text before each change and reads the patterns again on undo; a run of paper setting changes is one step.

### Printing

The publish app prints patterns directly at true scale, with notes alongside, so no third-party tiling or editing software is needed, a gap found in practice with Seamly2D, which also lacked a friendly screen for multi-page printing. So the publish window is one interactive screen rather than a dialog of settings: a large live preview of pieces on the page grid with captions, pieces dragged and turned with the page count following, settings beside it with the preview updating at once, pages clicked out of the print, and everything saved in the layout so reprinting after a measurement change is one click (see Publish app).

**Scale accuracy.** A test square on the first page (10 cm, or 4 in on Letter), a clear "print at 100%" reminder, and x and y calibration factors for printers that are consistently a little off, set once in Preferences.

**Print… prints the PDF** (decided 2026-11-13, issue #13). File → Print… (Mod+P), the toolbar and the Print and Export group send the same PDF as Export PDF to the system's print service with scaling off, so what prints is exactly what exports, already tested for scale. On Linux and macOS that is CUPS: `lpstat` lists the printers, and `lp` takes the file with `print-scaling=none` and `fit-to-page=false`, the paper as its media (A4, A3, Letter, else `Custom.WxHmm`, the one sheet's size for the other kinds) and, for tiled pages, `page-ranges`, so the dialog can print the cover alone to measure the test square, then the rest. The dialog offers the printer (the system default first, then the last one chosen while the app runs), copies and those pages. On Windows the PDF goes to the default PDF viewer's print command on the default printer, with no choices and no scaling guarantee, and the dialog says to choose 100% if the viewer asks. The file is written to the user's runtime folder (`lp` copies it into the queue, then it is deleted). The problems that block Export PDF block Print, and a projector layout, dark all over, is not printed. The code is `Sloper.Output.Printing` (no LCL) and `Sloper.Publish.PrintDialog`.

Drawing to a printer canvas (LCL `Printers`, with the native print dialog) was the alternative: the same on all three systems, but a second renderer beside the PDF writer (fonts, hatching, clipping) whose scale depends on each driver's resolution and printable-area offset. **If printing through the PDF gives trouble** (print services that scale or crop it, page ranges or media ignored, Windows viewers without a print command), the fallback is to turn `TPDFWriter`'s drawing calls into an abstract surface that both the PDF writer and a printer canvas implement, so the layout is drawn by one `TLayoutPrinter` either way.

### Output profiles

**Output profiles** (`Sloper.Core.OutputProfiles`). The drafting app stores every marking; the publish app decides which reach the output. A profile describes a kind of print, not a pattern, so profiles live in `settings.json` beside the machine profiles, and a layout stores only the name, as `outputProfile`. A profile lists the `roles` and `pieceMarks` (seam line, notches, grainline, fold bracket, labels, holes, stitch holes) to include, `allowance` (`keep`, or `none` to cut on the seam line, as leather usually is) and optional paper `styles` per role. The cutting line always prints. A name not in the settings blocks that layout's exports, never a quiet fallback, since a print missing its stitch lines would be sewn wrongly. The output profile applies first; a machine profile then decides what its machine takes.

`allowance` `none` changes the outline, not just what is drawn, so the preview, overlap checks, packing and every export use the seam line as the cutting line (`PlaceShape` applies the profile for all of them). Four profiles are built in and cannot be changed, so a layout naming one always prints the same; their names stay English, since layouts store them, and a user profile with a built-in name is ignored.

| Profile | Roles | Piece marks | Allowance |
| --- | --- | --- | --- |
| Home printing | All | All | Keep |
| Plotter or laser cutter | Cut | Holes, stitch holes | Keep |
| Leather | Stitch, cut, skive, edge finish | Notches, grainline, labels, holes, stitch holes | None |
| Instructions sheet | Placement, stitch, fold | Seam line, notches, labels | Keep |

Profiles are edited in the settings file until there is a window for them.

### Notes on paper

A note prints with a piece when it is anchored to the piece or one of its points or edges, or its top left (a callout's tip) lies inside the cutting line, and follows that piece's placement, upright even when the piece is flipped; other notes are left out of layouts, and a print note in no piece is a warning. Text in the default font is measured from Helvetica's average letter width, so these tests are approximate for it; a named font is measured from its own widths. A note does not add pages. Screen-only notes never print or export. DXF carries no notes.

### Draft export

File → Export Draft SVG… and `opensloper-cli export-draft` write the draft itself as a true-scale SVG in mm (points, construction, curves, pieces), for teaching, documentation and review in Inkscape. It needs only a draft, even an unfinished one, and is not for cutting, which the publish app does from finished pieces. In the app it matches the screen (fills, labels as shown, hidden roles left out, the pattern as it stands); the CLI names everything only with `--labels`. Problems are warnings: failing objects draw in their state colours. `--upto` draws the pattern as it was when an object was added, for tutorial pictures.

### Other exports and packing

SVG shows pieces where they were placed, for plotters, laser cutters and Inkscape; DXF-AAMA carries pieces into a CAD or cutting system, which arranges them itself; machine DXF follows the arrangement like SVG (see Cutting machines and material sheets). The problems that block a PDF block these too.

**SVG** (`Sloper.Output.LayoutSVG`): one true-scale file at the layout's positions, one group per copy with cut, seam, marks and label groups inside, so a cutter can leave out the seam line. Pages, marks, calibration, title block and sheet notes belong to paper and are left out. Without a machine profile it is all black.

**DXF-AAMA** (`Sloper.Output.LayoutDXF`): ASCII DXF R12 from our own small writer, so the same layout gives the same bytes. One block per piece, not per copy, in the piece's own coordinates with y up, with its cut count as the quantity; placed pieces only, so the layout still chooses what goes out; sizes as separate blocks, since grading rules are out of scope. Curves are polylines, and a fold piece is the half with a mirror line.

| Layer | Content |
| --- | --- |
| 1 | Cut line and piece text: name, size, quantity, material |
| 14 | Seam line |
| 4 | Notches |
| 7 | Grainline |
| 6 | Fold (mirror line) |
| 8 | Marking lines and point markers |
| 13 | Holes and stitch holes, as points |

ASTM D6673 is paywalled and listed as withdrawn, so the layers follow Valentina's GPL exporter, with 6 from its ASTM export; 8 and 13 come from CAD systems' published layer lists. The output reads cleanly in `ezdxf` but has not been tried on a real cutting system; that test should check the layers and file-level text.

**Pack Pieces** (and `opensloper-cli pack`) packs every copy, tray included, as one undo step of ordinary placements. Bounding boxes, tallest first, each as low and left as it fits, as it stands or a quarter turn from it (on a material sheet only with `allowTurns`), flips kept, 10 mm apart; the same input gives the same result. Tiled tries each column count for the fewest pages; large format and material sheets pack to the width for the shortest length. It keeps the existing arrangement when that is already better, and says so.

### Cutting machines and material sheets

Laser cutters, plotters and cutters such as Cricut treat line types differently, so exports keep them apart:

| Line type | What | Usual SVG colour |
| --- | --- | --- |
| Cut | Cutting line and cut-role lines | Red |
| Score | Fold-role lines | Blue |
| Mark | Placement and stitch lines, seam line, notches, grainline, fold bracket, buttons, match dots | Black |
| Engrave | Labels and text | Green |
| Hole | Holes and stitch holes, as true circles (`<circle>`, `CIRCLE`) | Red |

- **Machine profiles** give each line type a colour, layer, width and an on/off switch, so a job can cut outlines only or use a laser's hairline. They describe a machine, not a pattern, so they live in the settings, with a built-in `Standard`. A layout stores only the profile's name; one not in the settings blocks that export, since the wrong colours would cut the wrong lines.
- **Cut order.** Files go score, mark, engrave, holes, then cut, since software that follows file order would otherwise free a piece before its holes are cut.
- **Machine DXF** writes pieces where they were placed, y up, on the profile's layer names, sharing a writer with DXF-AAMA. Labels are text, so they depend on the machine's fonts; a single-stroke font waits for a test on a real machine.

**Cut as it lies.** On a material sheet, a projector or with a machine profile, nobody reads the printed grainline before cutting, so a quarter turn is a warning, and packing a material sheet only tries quarter turns with `allowTurns`, for material with no grain. A piece on a fold is opened out to the whole piece, mirrored with its marks, and the fold shows as a Mark; a hole on the fold line makes the piece invalid, as it has no other half. The preview, checks, packing and every export of that layout use the whole piece, so they agree; DXF-AAMA still writes the half with its mirror line.

**Material sheets** (`kind` `material`): a fabric width or a foam or card board, `materialWidth` by `materialLength` (0 or left out for a roll), printed as one sheet. Use is reported as the length used on a roll, else as the pieces' area against the sheet's. `material` limits a layout to one material by name (material IDs belong to each pattern, and a layout can have several), so each material gets its own cutting layout; other pieces leave the tray, packing, checks and exports, but keep their placements. Choosing a material, or the material kind with one chosen, takes that material's size from the first pattern that gives it one, in the same undo step (`TLayout.TakeMaterialSize`); it is copied once, not linked, so the layout's fields can still be changed.

### Material needed

Decided and built 2026-11-14 (issue #19, phase 2). How much of each material the layout's patterns take, for buying fabric: the Materials tab of the publish app, the `{materialneeded}` field (and the information block's Material needed line), and `opensloper-cli materials LAYOUT|PATTERN [--json]`. The code is `Sloper.Output.MaterialNeeded`, without the LCL.

- **The whole design, not the sheet.** Every valid piece of every source counts, with its cut count, whether placed or not and whatever the layout's material filter. Paper layouts may turn pieces any way, since a paper piece is laid on the fabric by its grainline, so the estimate makes its own cutting plan rather than reading placements.
- **By the grainline.** Each piece lies with its grainline along the material (`TPieceObject.GrainShape`), as the design app's fit check measures it; `allowTurns` lets packing try a quarter turn.
- **A roll is cut folded** in half lengthwise, as home sewers cut: packing is half the width over two layers. Pieces on a fold go down the fold, one under another, as the half drafted; a fold that runs across the grain (more than 1°) cannot, so that piece is cut opened out, with a note. A mirrored pair is cut from both layers at once and takes one place; other copies take one each, to be safe. A piece wider than half the roll but not the whole is cut unfolded, every copy, after the folded part, with a note; one wider than the roll is left out, with a note. The length is the folded part plus the unfolded part.
- **A sheet is cut single layer**, every copy opened out, as many sheets as it takes. **No size**: the pieces' area, and the narrowest roll every piece fits.
- **Packing** is Pack Pieces' bounding-box packing (`PackBoxes` in `Sloper.Output.Packing`, which can start around boxes already placed), 10 mm apart, so the answer errs on the generous side; true-shape nesting would tighten it.
- **Across patterns** a material is matched by name, in each pattern's own order, leaving out materials no piece uses. Its size comes from the first pattern that gives it one, and lengths show in that pattern's unit; another size for it is noted.
- **The tab** lists Material, Size, Pieces and Needed, with the notes and how the estimate is made under them, worked out again on each change. Title blocks ask for the field on every page, so `TLayout.MaterialNeeded` keeps the summary until the files loaded change.

### Blender export (3D preview)

Not built yet (see Open items). 3D draping will use Blender's cloth simulation rather than a built-in simulator.

Writing a cloth simulator (triangulation, sewing constraints, body and self-collision, a parametric avatar) is a multi-year effort in commercial tools, so the app only exports what Blender needs:

- Triangulated piece meshes (OBJ)
- A JSON or Python file with seam pairs, piece placement around the body and fabric hints
- A Blender Python script that places pieces, creates sewing springs and runs the simulation in one step

The Garment tab is the quick, flat look at the finished pieces; Blender is for fit and drape. The only requirement now is the **seam** concept in the core model, which also drives 2D seam-length checks. Any 3D module stays separate and reads computed geometry only.

## Automation API and command line

### Command line

`opensloper-cli` is built on the LCL-free core and ConsoleTools; its commands are on the generated Command line page. `check` exits with 0 for no problems, 1 for problems and 2 for a usage or file error, so it works in tests and CI. The commands are in `Sloper.CLI.Commands`, whose `RunCli` takes the arguments as a list and writes to the text files it is given; the program only passes its parameters, `Output` and `StdErr`. Tests run commands through it with both caught in streams (`Sloper.Tests.CLI`), on copies of the example patterns, checking exit codes, what is printed and the files written, with no built program needed (decided 2026-11-14). `serve` keeps to standard input and output, and `--help` prints through ConsoleTools to standard output, so neither is tested that way.

### Automation API

OpenSloper exposes its document operations as an API, first so Claude Code can test the app without GUI automation, later so Claude can help design and change patterns. The methods are on the generated Automation API page, from `Sloper.API.Methods`.

**One rule: the API only issues document commands.** Every call goes through the same document changes as the UI, so name rules, formula checks, cycle checks and undo apply exactly as for a user, and the API cannot put a pattern into a state the UI could not. Measurement edits go through `Sloper.Core.Measurements` with the same safe write as the drafting app.

#### Phase 1: scripting and testing

Built (`Sloper.API.Server`, `opensloper-cli serve`): JSON-RPC 2.0 over stdin and stdout, one message a line, with no window. Objects are named by `id` or `name`; `add_point` and `add_edge` take a `type` and fields as in a pattern file, so a whole pattern can be built through the API, and formulas are in the pattern's unit while reported positions stay mm. `render` returns the draft as SVG (`Sloper.Output.DraftSVG`), so Claude can look at the result, not only check numbers, and a wrong curve or misplaced dart is caught. `export` reads the saved files, as the publish app does. `render` with `format` png returns the draft as a PNG image, base64 (see Drawing images without the LCL); batches are not supported. A notification (a request without an `id`) gets no reply, not even when it fails, as JSON-RPC requires, nor when it has no `method` or its `params` is not an object: `serve --connect` reads no reply to a line without an `id`, and would take one as the answer to its next request. Only a line that is not JSON at all is answered, with a null `id`.

**A generated Python client, not an embedded language** (decided 2026-11-10). `opensloper-cli doc opensloper.py` (`Sloper.Docs.Python`) writes `docs/reference/opensloper.py` from the methods table: one Python method per API method, with typed parameters (choices as `Literal`) and the table's descriptions as docstrings, the target as `id` or `name` by its type, `add_point` and `add_edge` members as keyword arguments, and a refused call raised as `OpenSloperError` with its code, field and position. It is committed with the other generated pages, so a test fails when it falls behind the table, and readers download it from the site; it is MIT licensed so it does not bind the licence of the scripts that import it, and it is not published to PyPI until users ask for that. Pascal scripting inside the apps was rejected: it would duplicate the API with a second binding layer, few pattern makers know Pascal, and scripts carried in shared patterns would run code from untrusted files. Driving the running app is left to the GUI's `--automation` socket, which the same client can then use.

**Errors are data.** A refused call returns a JSON-RPC error with the message, the field and the position in the formula (`TPattern.LastError`, `LastErrorField`, `LastErrorPos`); scripts check the code, not the message. Evaluation failures are object states, never crashes.

**The design window's automation mode** (built 2026-11-11): see Phase 2. A test can drive the running app through `serve --connect` and read its state with `ui_state` (file, selection, label mode, the region in view) instead of xdotool, and look at the canvas with `render` and that region.

#### Phase 2: Claude as a design assistant

- **MCP server** (built 2026-11-11, `Sloper.API.MCP`). MCP is JSON-RPC 2.0 over stdio, so `opensloper-cli serve` answers the MCP handshake (`initialize`, `ping`, `tools/list`, `tools/call`, notifications) and passes every other method to the API server: one command serves scripts and MCP clients, and Claude Code and Claude Desktop connect directly. The tool list is made from the methods table, one tool per method with the same name: a JSON Schema from each parameter's kind (a target becomes `id` or `name`, neither required), the summary and reply as the description, and `readOnlyHint` from the table's `ReadOnly`. `add_point` and `add_edge` take their members by type, so their descriptions list each type's members from `Sloper.Core.OperationInfo` rather than a schema per type. A refused call is a tool result with `isError` and the API's error (code, message, field, position) as its text, so the model reads why and retries; an unknown tool is a protocol error. `render` answers with the SVG as text, and with `format` png as an image, so the model sees the draft: MCP clients take PNG but not SVG images. Resources and prompts wait until there is a use for them.
- **Live editing in the design window** (built 2026-11-11). The user turns automation on with Tools → Allow Claude to Connect, or starts the app with `--automation`; `opensloper-cli serve --connect` is then an MCP server on the pattern open in that window, so the user sees Claude's changes as they happen. Each change is one undo step labelled `Claude: <description>` (Edit → Undo Claude: Add variable), so it can be reviewed and undone at once. Built from four parts:
  - `Sloper.API.Endpoint` (no LCL): the run folder (`TAppPaths.RuntimeDir`, made `0700` and checked to be the user's), the token, and an endpoint file per window, `automation-<pid>.json` beside `automation-<pid>.sock` (Windows: a loopback port in the file). The file name starts with the endpoint's kind, so the apps' link (`publish-<pid>`) shares the folder and is never found by an automation client. The JSON-RPC codes and replies they all use are in `Sloper.API.Rpc`. A client reads the newest; several windows can listen, and a stale file left by a crash is skipped when nothing answers. A socket path over 103 characters is refused with a message, since ssockets crashes on a longer one.
  - `Sloper.API.Listener` (no LCL): a thread that accepts one client at a time. The first line must be `authenticate` with the token, within 5 s and 4 KB, or the connection is refused and closed. Each request line then runs on the main thread (`Synchronize`), between the user's own edits; writes never raise SIGPIPE (`MSG_NOSIGNAL`, `SO_NOSIGPIPE`).
  - `Sloper.API.Connection` (no LCL), behind `serve --connect`: `TMcpServer` calls it as it calls the local server (`TApiBackend`), and answers the MCP handshake itself, so the window is not involved until Claude acts. It connects on the first tool call, so the order of starting things does not matter, and again on the call after the window drops it; the call that finds the connection gone fails and says so.
  - `Sloper.UI.Automation`: the controller in the window. `TApiServer.CreateFor` works on the window's document without owning it; `ChangePrefix` labels the undo steps; `OpensFiles` false refuses `open`, since the user opens patterns and replacing theirs would lose work; `OnConfirmWrite` asks before `save` or `export` writes outside the pattern's folder; `OnWindowState` answers `ui_state`. While the user has a change open (a drag), every method that is not read-only is refused with "try again", so Claude never lands in the middle of the user's edit.
- **In-app assistant** (built 2026-11-11, `src/assistant/`, `Sloper.UI.AssistantPanel`). A Claude section in the side panel: the user asks in their own words and Claude works on the open pattern with the Automation API's methods as tools, through the same `TApiServer.CreateFor` as live editing (undo steps labelled `Claude: …`, `open` refused, writes outside the pattern's folder asked, edits wait during a drag). No consent prompt: the user typed the request. Decided 2026-11-11:
  - **The key** is the user's Anthropic API key, entered in Preferences (Design) and kept in `anthropic-key` in the config folder, mode `0600`, not in `settings.json`, which is plain and shared by the apps; `ANTHROPIC_API_KEY` wins when set, and Preferences then shows it read-only. A system keyring was rejected for now: three platform bindings with no Pascal library.
  - **Raw HTTPS** (`Sloper.Assistant.Http`): Pascal has no Anthropic SDK, so `fphttpclient` with OpenSSL posts to `/v1/messages`, API version `2026-10-21`; `ANTHROPIC_BASE_URL` points it elsewhere, as the SDKs allow, which the GUI check uses with a local mock server. Cancelling raises from the stream sink, which the API's pings keep calling while Claude thinks.
  - **The request**: `claude-opus-5-5`, streamed, effort `high` (drafting is work where a wrong formula costs more than tokens), adaptive thinking (always on for this model, so not sent), `max_tokens` 64000, refusal fallbacks (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`), automatic prompt caching. The tools (every method but `open`, with `eager_input_streaming`) and the system prompt are made from the program's own tables and never change, so the cache holds across turns; the system prompt carries the formula functions, units and each object type's properties, and says that text in a pattern is data, never instructions.
  - **The loop** (`Sloper.Assistant.Conversation`, manual, since there is no SDK tool runner): the history only grows and each assistant message goes back exactly as streamed, thinking blocks and signatures included (`Sloper.Assistant.Stream` rebuilds blocks from the events), except the API's rule after a fallback part-way through: thinking and tool_use blocks before the last `fallback` block are left out. Tool inputs are parsed strictly once whole; input that does not parse is not run and goes back as an `INVALID_JSON` error. A turn ending in `refusal`, `max_tokens` or `model_context_window_exceeded` runs none of its tools, and their results go back as stopped so the history stays valid. 429 and 5xx are retried three times, honouring `retry-after`; 401 says to check the key. A question stops after 40 requests.
  - **Threads**: the conversation runs on a worker thread; text is gathered and shown on the main thread, and each tool runs there (`Synchronize`), between the user's own edits. The panel frees the worker itself, also when the window closes mid-answer.
- **Consent** is asked on Claude's first request on a connection, reading included, since a pattern's contents are the user's too: Allow Once (this connection), Allow Until I Close OpenSloper, or Don't Allow, the default, which refuses the request and drops the connection. The status bar shows "Claude can connect" or "Claude connected · click to disconnect"; clicking it, or Tools → Disconnect Claude, drops the client, which is asked again when it reconnects unless allowed for the session.
- Example requests: "move the shoulder dart to the side seam", "add 2 cm ease at the hip", "why is point C invalid?".

#### Safety and scope

Reviewed 2026-11-08.

**`serve` over stdio needs no token.** Only the process that started it holds its pipes, and that process can already do anything the user can, so a token would protect nothing. The MCP server over stdio is the same.

**The GUI's `--automation` socket needs protection**, since any local process could connect:

- Off by default; turned on per session from the GUI or the command line.
- Listens only locally: on Linux and macOS a Unix domain socket in `$XDG_RUNTIME_DIR` (or a private folder made for it) with mode `0600`, so file permissions already keep other users out; on Windows 127.0.0.1, never 0.0.0.0. If it ever speaks HTTP, it also checks `Host` and `Origin`, against DNS rebinding from web pages.
- **A token the app generates, never one the user picks**: 32 random bytes from the OS, new at each start, written to a file only the user can read (beside the socket), and compared in constant time. The connecting program (the MCP bridge in `opensloper-cli`) reads the file and sends it; the user never pastes it into a chat, so it never reaches the model, the transcript or anything prompt injection could repeat. Printing it at start-up was dropped: a GUI started from the desktop has no terminal, and printed text ends up in logs.
- **Consent is the user's, in the app**, asked on Claude's first request on a connection, with the status bar showing while a client is connected (see Consent under Phase 2).

**Prompt injection is the larger risk.** Claude reads names, notes and descriptions from patterns other people share, and that text can carry instructions. A token does not help, since the attack comes through the client the user trusts, so the API limits what a steered client can do:

- `save` writes only `.sloper` files and replaces only a file that already holds a pattern (its `format` is `pattern`); `export` writes only a file with its format's extension. Built 2026-11-08.
- `set_measurement` writes only the pattern's measurement file, and only after it loads as one.
- In the design window, writes outside the open pattern's folder ask the user first, `open` is refused, and every change is one undo step labelled `Claude: <description>`. Built 2026-11-11.

**Other rules:**

- The API works on the open document; file access is limited to `open`, `save` and `export` with paths the caller gives.
- The API layer depends only on the document and core layers, keeping both usable without it.
- Nothing runs a shell: the apps start each other with `TProcess` and an argument list, so file names cannot inject commands. Text written into SVG is escaped (`EscapeXML`).

### Drawing images without the LCL

Built 2026-11-11 (`Sloper.Output.DraftPNG`). The CLI and the API draw the draft as PNG by drawing the draft's SVG with BGRABitmap's no-LCL build (`bgrabitmappack4nolcl_freetype`), so the image always matches the SVG and there is no second drawing routine. Text goes through Lazarus's own FreeType (`freetypelaz`, Pascal, no system library) with fonts bundled in `data/fonts`: Noto Sans, then DejaVu Sans if Noto is missing (BGRABitmap uses the first family it has; it does not fall back glyph by glyph). Bundling rather than reading system fonts gives the same image on every platform and in tests, and LazFreeType cannot read every system font. The SVG names the bundled families first in each `font-family`, since BGRABitmap cannot draw the generic `sans-serif` alone. Widths are 16 to 4096 pixels, 1600 by default, and the height follows the drawing.

Our units that use a third-party drawing library live in `src/output/thirdparty`: every standard applies there, and `opensloper-make.sh check` allows only BGRABitmap's no-LCL units besides, so the rest of `src/output` stays vector-only and nothing below `src/ui` uses the LCL. The CLI and tests require the no-LCL package; the GUI apps keep the LCL build, which compiles the same units.

## Open items

Everything not built yet, gathered from the sections above so each can become a GitHub issue; the sections keep only what is built and the decisions behind it. When an item becomes an issue, put its number here; when it is built, take it out and describe it in its section.

### Roadmap

Save, load and undo came before the canvas, so the canvas was built on document commands from the start and saved patterns served as regression tests. The app becomes personally useful at step 9; a community release follows if it proves easy to use.

1. Blender export for 3D preview

### To do

Agreed, but not built. Each line is meant to become one issue.

**General**

- **Preferences across open apps.** An app already open picks up a preference changed in another only when restarted. The apps' link could carry it (see Finding an open window under Publish app), with every app listening and a message sent to all of them.
- **Portable install.** A `portable.ini` beside the executable keeps settings, state and cache next to it (see File locations).
- **Translation**, for the community release (see Translation).
- **Release packaging**, for the community release: packaging the Qt bindings, macOS notarisation, Intel macOS builds, signed Windows programs, and a macOS `.icns` icon.
- **The assistant on Windows and macOS.** On Windows FPC 3.2.2 loads OpenSSL only as the 1.1 DLLs, which are not shipped, so the assistant cannot connect; on macOS it is untried (see Platforms).
- **Bodice block regression pattern** in `tests/patterns/`.
- **More tutorials**: moving a dart, a tote bag, a leather card wallet; and a documentation page per app's icon.
- **Help in the apps.** F1 and the Help menu open the page for the current tool or dialog through a table of help IDs; an offline copy of the site ships with each app, with the website as fallback. Translated and versioned documentation wait for the community release.
- **Developer documentation** of the units (PasDoc), once someone else needs to read the code.

**Design app**

- **Unit suffixes in angle and ratio fields** are not refused yet (see Pattern units).
- **More operations**: a bisector, and a tangent from a point to a curve.
- **Transforms**: a live ghost while dragging, and snapping to existing angles.
- **Separate Piece command**: one command for separating front and back (see Transforms), only if the manual steps prove tedious.
- **Piece detection**: Shift-click to merge faces, and a start-edge fallback.
- **Custom piece labels.**
- **Align tab**: fix the panel and show it again; until then align and distribute are reached through the Automation API's `arrange` (see Align and distribute).
- **Check pattern overlay**: draw the problems on the canvas, and report dangling outline edges.
- **Dependency arrows**: hovering or selecting an object draws faint arrows to its inputs, optionally to its dependents (see Links and problem display).
- **Typing note text on the canvas**, rather than in the properties.
- **SVG stamps** (annotations stage 4). A drawing from another app (a logo, a fold or assembly diagram) placed and anchored like a note, so it moves with the geometry. Paths only: `<text>` is refused with a message asking for it to be converted to paths, which keeps fonts out. Drawn at true size from the SVG's own units (px taken at 96 per inch, with a warning), and stored in the pattern as path data, so the pattern does not depend on the outside file.
- **Rounding curved corners**, which needs a tangent found numerically (see Accessories).
- **Pleats in the Garment tab**, drawn as lines.
- **Role styles in Preferences**: overriding a role's colour, dash and weight.

**Publish app**

- **A window for output and machine profiles**, which are edited in the settings file for now.
- **True-shape nesting** for Pack Pieces, in place of bounding boxes.
- **G-code export**, for CNC machines.
- **Raising the publish window on Wayland**, which needs an `xdg-activation` token Qt 5 cannot use (see Finding an open window).
- **Blender export** for fit and drape (see Blender export (3D preview)).

**To try on real hardware**

- A print with the Leather output profile.
- Alt-click to cycle coincident lines on a real desktop, as some window managers take it.
- DXF-AAMA on a real cutting system, checking the layers and file-level text.
- Machine SVG and DXF on a real cutter, and whether labels need a single-stroke font.

### Open questions

- Should buttonholes become a marking role?
- Should an output profile send roles to separate files or passes, one per laser operation?
- What values does each leather marking need (skive width and depth)?
- Leather hides (under Future ideas): is there evidence the community needs them?

### Future ideas

Ideas worth keeping that are deliberately outside the roadmap. Each is added only when the core is solid, or when the community asks for it.

| Idea | Notes |
| --- | --- |
| Notions library | A catalogue of haberdashery (zips, buttons, hooks and eyes, snaps, eyelets, elastic), placed on a pattern like KiCad footprints: markings on the seam (zip stops, button and buttonhole positions via Repeat), rules (buttonhole = button diameter + thickness; warn if a zip is longer than its opening), and an automatic notions list for the title block via live fields |
| Multi-size output | Nested sizes on one sheet, for published patterns. Paper patterns needed it to serve every size from one print; parametric drafting makes the exact size instead. It would mean evaluating the pattern once per size and drawing the results together, with a screen-only size overlay for checking grading |
| Scaled body figure | The measurements app's figure scaled to the entered values, so unusual proportions and likely typos stand out |
| ISO 8559-1 check | Check catalogue definitions against the standard and add clause references, if the project gains traction |
| Spread tool | Generates the chain of rotations for slash and spread in one step; see Transforms |
| Fabric textures and properties | Image textures (e.g. a photo of the actual fabric) for fills and the Blender export; nap direction for automatic layout (width is a material's size) |
| Leather hides | A hide's outline drawn or traced from a photo, with flaws marked as areas to avoid. Bounding boxes cannot honour an irregular outline, so packing on a hide needs true shapes; until then pieces are placed by hand and checked against the outline. See Open questions |
| Client library | A searchable SQLite library of clients, measurements and patterns (see File format and storage) |
| Materials app | An app like the measurements app that keeps a list of materials and their specifications, for the design and publish apps to use |
