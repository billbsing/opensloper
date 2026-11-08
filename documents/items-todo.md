# Items to do

Review and testing before moving on to step 10, from `ffed2e4` on `development`. Run `./build.sh` first, which builds all three programs, including `release/opensloper-publish`.

## To test

These could not be tested properly during development.

- [x] **Export PDF in the window:** never clicked through a file dialog; all test exports went through the CLI.
- [ ] **A real print:** measure the 10 cm test square with a ruler, then tape two tiles together using the diamonds.
- [x] **A real projector:** the line thicknesses are a best guess.
- [ ] **Publish… save prompt:** in the drafting app, try this with a modified pattern, and from a real save.
- [x] **Publish window:** Flip, Reload Patterns, panning, the Delete key and the every-page title block.

## Known limits

- ~~A piece keeps the edges it was made from, so splitting an edge after making its piece does nothing for it.~~ Fixed 2026-11-07: pieces, their notches and allowances, and seams take the parts.
- ~~An edge's own seam allowance, and a grainline between two points, can only be set through the Automation API.~~ Fixed 2026-11-07: Own allowance and Grainline in the piece's properties.
- Each Publish… opens another window, rather than finding one already open.

## List of Changes

#### Anotations
Have the anotations appear at the highest Z-order , over the design. The user can view/hide anotations.
Add, Edit, Delete, Move anotations in the design page.
Set font, and font size for anotations, change direction, anchored from a point.

Rescoped 2026-11-06 into four stages (see Stages under Annotations in the design document):
- Stage 1, anchored notes: done 2026-11-06. Plain text anchored to a point, edge or piece, Text tool (X), drag, show and hide (View → Annotations), document fields, printing with their piece; one sans-serif font.
- Stage 2: done 2026-11-06. Callouts (Callout tool, A; a note with a leader, its tip dragged to re-anchor it), `{=…}` draft values, alignment and the white box for notes and sheet notes.
- Stage 3: font name, bold and italic, with the chosen TrueType font embedded in PDF.
- Stage 4: SVG stamps, anchored path-only drawings.

#### Preferences
Done 2026-11-05 (see Preferences in the design document): one dialog in all three apps, Edit → Preferences…, with General (unit), Design (grid spacing per unit) and Publish (printer calibration, worked out from a measured test square). Calibration moved out of layout files; older layouts' values are ignored.

Still to do:
- New patterns take the preferred unit, once Pattern units is built (decided 2026-11-04, not started): each pattern has one unit, the preference sets it for new patterns and never changes an existing one, Tools → Convert Pattern Units… rewrites only lengths, and numbers may carry a suffix (`400mm`, `2in`; the suffix is built, converting to mm for now). Split 2026-11-06 into two stages (see Pattern units in the design document): stage 1, the pattern's unit, and stage 2, converting a pattern (both built 2026-11-07).
- An app already open picks up a preference changed in another app only when restarted.

#### Marking line roles
Done 2026-11-05 (see Markings in the design document): edges can be placement, stitch, fold or cut lines, which join the pieces they lie in and print in their own style. Finished 2026-11-06: point markers (hole, button, match dot) on points and repeats, Draw As for the role of new lines, several lines in the same place (click again or Alt-click to cycle, right-click list, screen offset), and the offset edge along a run (inside/outside a piece, mitred and trimmed corners, invalid when it collapses). Still to try by hand: Alt-click on a real desktop, as some window managers take it for moving windows. Also done 2026-11-06: the skive line and edge finish roles, the Lines tab for hiding roles with presets, and output profiles in the publish app; still to do: overriding role styles in Preferences, and a print with the Leather profile tried by hand.

#### File Format Standards
For future claude creating new patterns and measurements, do we need to create storage file standards as part of the documents folder.
Each store file type has currently a version number, and the JSON specification, so that claude can read/write measurement, design and  publish files.

Decided 2026-11-08: user documentation pages and JSON Schema, both generated from the code, as the reference pages are. Done together with more documentation, in stages:

- [x] **Stage 1, file formats.** A table of each user file's members outside the objects (pattern, measurements, layout), as `Sloper.Core.OperationInfo` is for objects, with a test that every member a saved file writes is listed. `opensloper-cli doc files` writes a File formats page: the shared rules, then each file's members and an example. `opensloper-cli doc` also writes `docs/reference/schemas/pattern.schema.json`, `measurements.schema.json` and `layout.schema.json` (JSON Schema 2020-12), the pattern's objects from the operations table. The committed-pages test covers the schemas, and `build-docs.sh` checks the examples and regression files against them with Python's `jsonschema`. The design document's File format section keeps the decisions and points to the page.
- [x] **Stage 2, keyboard shortcuts.** A shortcuts table outside the LCL that the three apps take their shortcuts from, and a generated Keyboard shortcuts page.
- [x] **Stage 3, Measure section.** Pages for the measurements app: a set, size tables, the catalogue and body figure, importing and exporting Valentina and Seamly2D files, and the measurements panel in the design app.
- [x] **Stage 4, Publish section.** Pages for the publish app: making a layout, arranging and packing pieces, printing tiles and checking the scale, calibration, large-format and projector output, and exports.
- [x] **Stage 5, shorter design document.** Summarise each section of `opensloper-design-document.md`, keeping decisions and their reasons, and moving what the user pages and reference pages now say to them.

#### Publish - printing question
How to adjust the print size if the square block is not 10x10.

Answered 2026-11-05: set the calibration in Preferences → Publish. Type the measured size of the test square and Work Out Factors sets them; a square that measures 98.5 mm across, printed with no correction, needs 100 / 98.5 = 1.015.

#### Editable panels in the design app
Planned 2026-11-07, built 2026-11-08. Variables, Measurements and Materials should follow one pattern: read in the grid and edit in the grid (Enter or leaving a cell commits, Escape puts the text back), a refused value keeps its text with the cell in red and the reason in the status bar, buttons in one row at the bottom with Add first, and file commands in the main menu rather than in panels. Materials is the exception: its panel is read-only and editing is in a dialog, since colour and fill do not fit in a cell. Decided: each change in the material dialog is its own undo step, applied at once, with a Close button; the Variables tab no longer shows its selection in the properties panel; the Measurements tab gets a Revert button. Materials… goes in the Edit menu unless decided otherwise.

- [x] **Stage 1, editable list panel.** An editable mode for `TListPanel`: an `Editable` flag per column and a virtual `CommitCell(Key, Column, Text)` that can refuse with a reason. Editable panels select cells, not rows (`goRowSelect` and `goEditing` do not mix), still painting the current row, with multi-select off. Delete and Backspace edit the text while a cell editor is open and only reach `DeleteRequested` when none is. Formula cells keep name completion: check first whether `Sloper.UI.FormulaCompleter` attaches to the grid's editor, else write a custom editor for formula columns. The measurements app's grid (`goEditing`, `OnValidateEntry`, `OnSetEditText`) is the model.
- [x] **Stage 2, Variables.** Name, Formula and Description edited in the grid, Value read-only; each cell commit is one undo step, through the same pattern changes the properties panel uses. Add appends `variable2` (the next free name) and puts the cursor in its Name cell, staying on the tab. Drop the sync to the properties panel (`VariablesSelect`, `VariablesAdded` in the main form). Delete as now.
- [x] **Stage 3, Measurements.** File → Measurements becomes a submenu: New Set…, Open Set… (keeps Ctrl+M), Edit in Measurements App…; the panel loses its New, Open and Edit buttons but keeps the file name and Size box. Value and Description edited in the grid; Key only on a row made by Add; typing a value in a Missing row adds that key. Edited rows are marked (bold, `*`) and held as pending changes; Save is disabled until there is one, and Revert drops them all. Save re-reads the file, applies every pending change and writes once, through a new `ChangeMeasurements` (several changes, one atomic write) in the document and core, with tests; with no set open it asks for a new file first, as now. Pending values do not change the pattern until saved. While changes are pending, Test size is disabled; opening another set or pattern, closing the app, or a reload from the file watch asks Save / Discard.
- [x] **Stage 4, Materials.** The panel becomes a read-only grid (swatch, name, fill, allowance) with the cut list and an Edit… button; Edit → Materials… opens the same dialog. New `Sloper.UI.MaterialDialog`: on the left the material grid with New and Delete under it, a splitter, on the right Name, Colour (swatch and Choose…), Fill (Tint or Hatching) and Allowance in the pattern's unit, for the row selected on the left. The splitter position is kept in `settings.json`. Each field commit is one undo step, applied at once so the canvas follows; the dialog has Close. The grid and swatch drawing move to a shared unit used by panel and dialog. The `InputQuery` prompts for rename and allowance and the Fill toggle button go.
- [x] **Stage 5, documents.** Design document: Side panel, Variables tab, Measurements tab, Small edits from the drafting app (one write per Save instead of per change) and the Materials Code paragraph, plus a short Editable panels paragraph with the shared rule. Update the user documentation pages for these panels. Each stage has tests for what needs no GUI (pending changes, the batch write, cell commits through the document) and a click-through on Xvfb.
