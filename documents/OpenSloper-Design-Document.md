# OpenSloper — Design Document

Oct 27, 2026 · @Bill

## Overview

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use.

Patterns are drafted with relative distances and formulas, so changing a measurement redraws the whole pattern. Valentina and Seamly2D (C++/Qt, which split from a common codebase in 2017) do this already, but both are large and have a steep learning curve. This project aims for the same parametric power with a simpler, more direct drawing experience.

Goals:

- Parametric drafting driven by measurement sets and variables
- An Inkscape-like canvas where snapping records relationships automatically
- Automatic piece detection instead of manually tracing outlines in order
- Seam allowance, notches, grainlines and true-scale tiled printing
- A small, maintainable codebase with a pure-Pascal core

## Technology and licence

The project uses Lazarus/Free Pascal and is licensed GPLv3 or later.

| Component | Use | Licence |
| --- | --- | --- |
| Lazarus LCL / FCL | GUI, JSON (`fpjson`), XML (`DOM`, `XMLRead`), SQLite (SQLdb) | Modified LGPL with static-linking exception |
| Clipper2 | Polygon offsetting and booleans for seam allowance | Boost |
| BGRABitmap | Antialiased canvas drawing, SVG | Modified LGPL |
| TFPExpressionParser or custom parser | Formula evaluation | FCL |
| fpvectorial (optional) | DXF/SVG/PDF export helpers | Modified LGPL |

Licence decisions:

- GPLv3 or later, matching Valentina and Seamly2D, so code can be studied, borrowed and shared in both directions.
- `LICENSE` file at the repo root with the full GPLv3 text; a standard GPL header in every unit.
- Code translated from Valentina or Seamly2D keeps their copyright line alongside the project's.
- An About box shows the licence and no-warranty notice.

Practices from day one: git repository, internal units in mm, UI text in `resourcestring` sections for translation, and occasional builds on a second OS.

## Core concepts

A pattern is a graph of draft objects whose positions come from measurements, variables and other objects.

| Concept | What it is | Notes |
| --- | --- | --- |
| Measurement set | A person's body measurements, e.g. `@waist`, `@back_length` | Own file; one set drives many patterns. A size table (several sets) enables grading later |
| Variable (increment) | Pattern-level value, e.g. `#ease_waist = 20` | Holds design decisions; may use formulas |
| Point | A position defined by an operation, its references and formulas | Never stored as fixed coordinates, except free points |
| Operation | How a point is placed: offset, along line, intersection, perpendicular, midpoint/ratio | Inferred from snapping where possible |
| Edge | Line, Bézier curve or arc between points | Curve handles have angle and length formulas |
| Role | Each edge is *construction* (guide, dashed) or *outline* | Only outline edges form piece boundaries |
| Piece | Closed path: ordered edge references, each with a reversed flag | Seam allowance (default + per edge), grainline, notches, labels, cut count, fold line |
| Seam | Pairing of edges on two pieces that are sewn together, with direction | Drives seam-length checks and 3D export |
| Layer | Grouping for visibility | E.g. front, back, sleeve, draft vs pieces |
| Layout | Pieces arranged on sheets for printing or plotting | Works on computed geometry only |
| Annotation | Note, callout, title block or sheet note | Anchored to objects by ID so it follows measurement changes; may contain live fields |

The core drafting operations:

- **Offset from a point:** distance plus angle, or dx/dy
- **Along a line or curve:** a distance from one end
- **Intersection:** of two lines or curves
- **Perpendicular or bisector:** squaring off from a line, splitting an angle
- **Midpoint or ratio:** between two points

## Architecture

Four layers, each depending only on the ones below; the core has no LCL dependency, so it can be unit-tested and reused by a command-line tool.

Layers (dependencies point down):

- **UI (LCL):** canvas view (BGRABitmap, pan, zoom), interaction tools (select, add point, curve, piece), snapping engine (turns snaps into operations), panels (formulas, measurements, layers)
- **Output:** tiled PDF, SVG and DXF, Blender export (later); reads computed geometry from the core
- **Document:** TPatternDocument (owns the model), undo/redo commands, change notifications
- **Core (pure Pascal, no LCL):** geometry, expressions, model, evaluator, piece builder (Clipper2 seam allowance), storage (IPatternStorage, JSON)

The UI changes the model only through document commands, and exporters read computed geometry directly from the core, so a new output format never touches drafting code.

## Key design decisions

The central rule: only definitions are saved and undone; computed geometry is always derived.

1. **Definition vs result.** Each object holds its definition (operation, references, formula strings) and a cached computed result (coordinates). Saving, loading and undo touch definitions only.
2. **Dependencies come from formulas.** Each formula is parsed once into an expression tree; everything it references (measurements, variables, objects such as `Line_A_B.length`) plus the operation's direct references forms the dependency graph. The user never manages it.
3. **Ordered, incremental evaluation.** The graph is topologically sorted. A change marks the object and everything downstream dirty; only those are re-evaluated. Formula edits that create a cycle are rejected with a clear message.
4. **Failures are states, not crashes.** If an operation cannot be evaluated (e.g. two lines no longer intersect), the object and its dependents become invalid and are highlighted in red. The pattern stays editable.
5. **IDs separate from names.** Internal IDs never change; user-facing names can be renamed freely.
6. **Operation registry.** Each operation type is a class that declares its inputs and parameters, evaluates itself, and saves/loads itself. Adding a tool means writing and registering one class.
7. **Commands for undo/redo.** Every user change is a `TCommand` with `Execute` and `Undo`; the UI listens for change notifications. One drag is one undo step: the start value is recorded on mouse-down, the model updates live during the drag without creating commands, and a single command is committed on mouse-up; Escape cancels and restores the start value. Repeated arrow-key nudges of the same object within about a second merge into one step, as do consecutive spin box or slider changes to the same field. Formula fields commit one step on Enter or loss of focus, not per keystroke.
8. **Storage behind an interface.** `IPatternStorage` with `Load`/`Save`, so the core never depends on a file format.

```pascal
TPointOperation = class
  function Inputs: TObjectRefArray; virtual; abstract;
  function Params: TFormulaArray; virtual; abstract;
  function Evaluate(Ctx: TEvalContext; out Pt: TVec2): Boolean; virtual; abstract;
  procedure SaveTo(Node: TJSONObject); virtual; abstract;
  procedure LoadFrom(Node: TJSONObject); virtual; abstract;
end;

TOffsetPoint = class(TPointOperation)   // distance + angle from a base point
  BasePoint: TObjectRef;
  Length, Angle: TFormula;
end;
```

## Evaluator

The evaluator turns definitions into coordinates in dependency order, and records why anything fails instead of crashing.

**Graph nodes.** Measurements, variables, points, edges and pieces are all nodes. Each holds its dependencies, its dependents (reverse list), a state with message, and its computed result. Dependencies come from the operation's direct inputs plus every reference collected when its formulas are parsed.

**Evaluation order:**

1. Topological sort (Kahn's algorithm), redone only when structure changes: objects added or deleted, or a formula referencing something new.
2. A change marks the node and everything downstream dirty.
3. Walk the sorted list and evaluate dirty nodes; inputs are always current when reached.

Patterns are small, so the first version re-evaluates everything in order on every change; dirty tracking is added only if dragging feels slow.

**Cycle detection.** Before an edit makes X depend on Y, search from Y through its dependencies; if X is reachable, reject the edit with a message naming both objects. The graph is therefore always acyclic.

| State | Meaning | Example | Display |
| --- | --- | --- | --- |
| Valid | Computed fine |  | Normal |
| Error | Formula problem | Unknown name, divide by zero, syntax error | Red, message on hover |
| Invalid | Geometry impossible | Parallel lines, distance past end of curve | Red, message on hover |
| Blocked | An input failed | Depends on an invalid point | Faded orange, "blocked by point C" |

Each node keeps its last good value, drawn ghosted while it is failing, so the drawing has no sudden holes.

**Dragging.** Parameters that are plain numbers update when dragged. Formula-driven parameters are locked by default, with an optional override offset (`@waist/4 + #ease + 13.5`) to keep the parametric intent. The evaluator reports which parameters are literal and which are formulas.

```pascal
type
  TEvalState = (esValid, esDirty, esError, esInvalid, esBlocked);

  TEvalNode = class
  public
    Id: TNodeId;
    State: TEvalState;
    Message: string;
    Deps: TNodeList;         // what I read from
    Dependents: TNodeList;   // what reads from me
    procedure CollectDeps(Resolver: TNameResolver); virtual; abstract;
    function Evaluate(Ctx: TEvalContext): TEvalState; virtual; abstract;
  end;

  TEvaluator = class
  private
    FOrder: TNodeList;       // topologically sorted
  public
    procedure Rebuild;       // collect deps, rebuild dependents, sort
    procedure MarkDirty(Node: TEvalNode);
    function WouldCreateCycle(Node, NewDep: TEvalNode): Boolean;
    procedure Run;
  end;

procedure TEvaluator.Run;
var
  N, D, BlockedBy: TEvalNode;
begin
  for N in FOrder do
    if N.State = esDirty then
    begin
      BlockedBy := nil;
      for D in N.Deps do
        if D.State <> esValid then begin BlockedBy := D; Break; end;
      if BlockedBy <> nil then
      begin
        N.State := esBlocked;
        N.Message := 'Blocked by ' + BlockedBy.DisplayName;
      end
      else
        N.State := N.Evaluate(Ctx);
    end;
end;
```

## Names and IDs

References are stored as IDs and shown as names, so renaming an object changes one field and never breaks a formula.

**Formulas.** The user types names (`Line_A_B.length + @waist/4`) with autocomplete. On commit the parser resolves each name and stores the ID form (`{l1}.length + @waist/4`); unknown names are rejected at entry. Formula fields, tooltips and error messages convert IDs back to current names for display.

**IDs.** Short and readable (`p12`, `l7`), unique within the pattern, never reused after deletion. Measurements are the exception: patterns refer to them by a stable key such as `waist`, so any measurement file with the same keys works.

**Name rules:**

- Letters, digits and underscore, not starting with a digit; no dashes or dots, which clash with formula syntax (`A-2`, `A.x`)
- Function names and formula keywords are reserved
- Case is preserved for display but compared case-insensitively
- Unique within each namespace: draft objects (points, edges, pieces share one), `#` variables, `@` measurements
- Auto-naming (`A` to `Z`, then `A1`…) always takes the next free name
- Line names are derived from endpoints (`Line_A_B`) unless the user sets a custom one

**Renaming.** The rename field validates as the user types and cannot be confirmed with a duplicate or invalid name. Rename is an undoable command.

**Undo and redo never fail or prompt.** Linear undo restores exact earlier states, which were already valid, so no clash can occur. A debug-build assertion checks name uniqueness after every undo and redo.

**Clashes from paste, import, merge or restore** are resolved automatically and reported in a notice:

- Number appended directly, no separator (`A` → `A2`, `A3`…), using the next free number
- An existing numeric suffix is stripped first, so a copy of `A2` becomes `A3`, not `A22`; any trailing digits count as the copy number, so a copy of `Hip2` or of an auto-named `A1` simply takes the next free number
- Pasted objects get fresh IDs, with references inside the pasted group remapped

## Formula engine

Decision: start with TFPExpressionParser behind a `TFormula` interface, with a custom tokenizer in front; a custom parser can replace it later without changes elsewhere.

**Why a translation layer is needed.** TFPExpressionParser expects plain identifiers registered before parsing, does not readily report which names a formula uses, has radian-based trig, and gives limited error positions. Our syntax uses `@waist`, `#ease` and `{l1}.length`, degrees, and needs a dependency list.

**Pipeline:**

1. Custom tokenizer reads the formula: resolves names to IDs, collects references for the dependency graph, reports unknown names with their position.
2. Tokens are mapped to plain identifiers (`@waist` → `m_waist`, `#ease` → `v_ease`, `{l1}.length` → `o_l1_length`), registered as variables.
3. TFPExpressionParser parses once and evaluates on each run.
4. Degree-based `sin`, `cos`, `tan`, `asin`, `acos`, `atan2` are registered as custom functions.

The tokenizer is needed regardless (it drives name/ID conversion), so it carries over if the engine is replaced by a custom recursive-descent parser.

```pascal
TFormula = class
  function Parse(const Text: string; Resolver: TNameResolver): Boolean;
  function References: TNodeIdArray;       // for the dependency graph
  function Evaluate(Ctx: TEvalContext): Double;
  function DisplayText(Resolver: TNameResolver): string;  // IDs -> names
  property ErrorMessage: string;
  property ErrorPos: Integer;
end;
```

To confirm against the FPC version in use: identifier rules, integer/float handling, and access to the parse tree.

## Operation set

Six point operations and three edge types cover basic bodice, skirt and trouser blocks; many of Valentina's \~30 tools become special cases once formulas can read properties like `{l1}.angle`.

**Conventions:**

- Units in mm; angles in degrees, 0° pointing right, positive anticlockwise (as Valentina); the canvas flips y for screen drawing
- Common fields on every object: `id`, `name`, `type`, `layer`, `visible`, `notes`
- Readable properties: point `.x`, `.y`; edge `.length`, `.angle` (lines), `.angle1` / `.angle2` (curve ends)
- Functions: `sin cos tan asin acos atan2 sqrt abs min max round`

**Point operations:**

| Operation | Fields | Covers |
| --- | --- | --- |
| Free | `x`, `y` | Origin, sketch points not yet pinned |
| Offset | `base`, `mode` (polar/cartesian), `length` + `angle` or `dx` + `dy` | Distance at angle, straight down or across, perpendicular from a line (`angle = {l1}.angle + 90`) |
| Along edge | `edge`, `from` (start/end), `mode` (length/ratio), `value` | Point along a line, curve or arc; midpoint (ratio 0.5); thirds; dart positions |
| Intersect edges | `edgeA`, `edgeB`, `extendA`, `extendB`, `pick` | Line×line, line×curve, curve×curve |
| Circle × edge | `centre`, `radius`, `edge`, `extend`, `pick` | Compass step, e.g. shoulder length from neck point onto the shoulder slope line |
| Project onto edge | `point`, `edge`, `direction` (perpendicular/angle), `angle`, `extend` | Foot of a perpendicular; drop vertically from a point to the hem line |

`extend` treats a line as infinite (or extends a curve along its end tangent), so long construction lines aren't needed just to find an intersection. `pick` is a stored crossing number, so the result stays stable when measurements change.

**Edge operations:**

| Operation | Fields | Covers |
| --- | --- | --- |
| Line | `start`, `end`, `role` | Straight seams, construction lines |
| Curve (cubic Bézier) | `start`, `end`, `angle1`, `length1`, `angle2`, `length2`, `role` | Single smooth curves: hip curve, side seam shaping |
| Curve path | `nodes[]` of `point`, `angle`, `lengthIn`, `lengthOut`; `role` | Armholes, necklines, crotch curves; one shared tangent per node keeps joins smooth |
| Split edge | `edge`, `point` (on the edge, typically from Along edge or Intersect edges) | Two parametric edges; needed for dart rotation and slash-and-spread |

Handle angles and lengths are formulas, so curves stay parametric (e.g. `length1 = @neck/6`).

**Piece and seam objects:**

| Object | Fields |
| --- | --- |
| Piece | `path[]` of `edge`, `reversed`, `allowance` (override); `allowance` (default); `grainline` (two points or angle); `notches[]` (point, or edge + position); `labels[]`; `cut` (count, onFold, mirrored); `foldEdge` |
| Seam | `pieceA`, `edgesA[]`, `pieceB`, `edgesB[]`, `reversed`, `tolerance` |

**Deferred to phase two:** bisector; circle × circle; arcs (approximated by curve paths at first); tangent from a point to a curve.

```json
{ "id": "p5", "type": "circleEdge", "name": "SP",
  "centre": "p3", "radius": "@shoulder_length",
  "edge": "l4", "extend": true, "pick": 1 }

{ "id": "c2", "type": "curvePath", "role": "outline",
  "nodes": [
    { "point": "p5", "angle": "{l4}.angle - 90", "lengthOut": "40" },
    { "point": "p9", "angle": "270", "lengthIn": "35", "lengthOut": "30" },
    { "point": "p12", "angle": "0", "lengthIn": "25" }
  ] }
```

## Transforms

A transform is one operation that produces parametric copies of a set of objects, so rotated, mirrored or moved copies update when measurements change.

Uses: dart rotation, slash and spread, mirroring a half piece, and moving a traced section aside to develop it (facings, yokes, pockets).

| Transform | Fields | Notes |
| --- | --- | --- |
| Rotate | `sources[]`, `pivot`, `angle`, `suffix` | Angle is a formula, e.g. dart angle `{l5}.angle - {l6}.angle` |
| Mirror | `sources[]`, `axis` (edge, two points, or point + angle), `suffix` | Curves mirror exactly, with orientation reversed |
| Move | `sources[]`, `mode` (polar/cartesian), `length` + `angle` or `dx` + `dy`, optional `rotate` + `pivot`, `suffix` | Move-and-rotate repositions a section in one step |

**Copies are real objects.** Each has its own ID and name (source name + suffix, e.g. `A_r1`) and records its source and transform. Its geometry is always computed from the source, so it can't be dragged, but it can be an input to any operation.

**Edges follow their points.** Selecting an edge pulls in its endpoints automatically; copied edges connect copied points. Béziers transform exactly via their control points.

**In the graph:** the transform node depends on its pivot or axis and all sources; every copy depends on the transform node. No special evaluator handling is needed.

**Example: shoulder dart to side seam.**

1. Draw a slash line from the bust point to the side seam; split the side seam there.
2. Select the outline between the shoulder dart and the slash.
3. Rotate about the bust point by the dart angle: the shoulder dart closes, a side dart opens.
4. Click inside the new outline to form the piece from original and rotated edges.

Slash and spread repeats this: each slash rotates everything beyond it by the spread amount. A convenience Spread tool that generates the chain can come later.

**Behaviour:**

- Creating a transform and all copies is one undoable command
- Deleting a source prompts to delete its dependents, as for any object
- Copies can go to a chosen or new layer, keeping the original draft usable
- Interactive: pick the pivot, drag with a live ghost preview, snap to angles of existing lines
- Rotate and move preserve lengths, giving a free check that seams are unchanged
- Cut on fold is a piece property applied at output; Mirror is for geometry needed in the draft itself

```json
{ "id": "t1", "type": "rotate", "name": "Dart to side",
  "sources": ["l7", "c3", "l9"], "pivot": "p14",
  "angle": "{l5}.angle - {l6}.angle", "suffix": "_r1", "layer": "side-dart" }
```

## Drafting experience

The canvas feels like Inkscape, but every point records how it was placed relative to others.

Inkscape itself was considered and rejected as the drawing tool: it stores absolute coordinates, while patterns are designed with offset distances and formulas.

**Snap-inferred operations.** The user draws freely; the snap target decides the recorded operation:

- Snap horizontally from A at 250 mm → offset point from A, length pre-filled `250`, later editable to `@waist/4`
- Snap to where two lines cross → intersection point
- Drop in empty space → free point, which can be pinned to a relationship later

This is construction-based (an explicit dependency graph), not constraint-based like FreeCAD's Sketcher, so no numerical solver is needed.

**Borrowed from Inkscape:** node editor with draggable Bézier handles, smart snapping with visual hints, layers, smooth pan/zoom, and a properties panel where formulas for the selection are edited.

**Automatic piece detection.** Instead of clicking around an outline clockwise, the user clicks inside a region:

1. Build a planar graph from outline edges only; split edges where they cross.
2. Sort edges around each node by outgoing angle (curve tangents, not chords).
3. Prune dangling nodes, then walk faces by always taking the next edge clockwise.
4. Discard the outer face; pick the face containing the click (point-in-polygon).
5. Use signed area to force clockwise order.

Handling the edge cases:

- Construction lines are excluded by their role, so they don't fragment regions
- Overlapping pieces: the smallest face is chosen; Shift-click merges adjacent faces
- Nodes within a small tolerance are merged so formula rounding doesn't break cycles
- The piece is stored as edge references, so it follows measurement changes; detection re-runs only on request or to warn when a path no longer closes
- Fallback: click a start edge, the app walks the path and highlights it for confirmation

## Links and problem display

Direction and dependency arrows appear only on hover, selection or piece creation, never permanently, to keep the draft free of noise.

| Link | Shown when | Form |
| --- | --- | --- |
| Piece direction (clockwise path) | Creating a piece (animated along the detected path); hovering or selecting a piece; optional "Show piece direction" toggle, off by default | Small chevrons at each edge's midpoint, not arrowheads at the ends |
| Dependencies (what a point is built from) | Hovering or selecting an object; optional "Show dependencies" toggle for the whole draft | Faint arrows to its inputs, optionally to its dependents |

**Check pattern overlay.** A display option that highlights problems:

- Gaps where a piece path no longer closes (red circle at the gap)
- Dangling outline edges that can't belong to any piece
- Invalid and blocked objects (red and orange, from the evaluator)
- Seam pairs whose lengths differ by more than their tolerance
- Piece edges whose reversed flag breaks the path direction

A problems panel lists each issue in plain words (e.g. "Front: gap between Line\_C\_D and Curve\_D\_E"); clicking one zooms to it. A warning count in the status bar flags issues without forcing the overlay on.

## File format and storage

Pattern files are JSON; SQLite is reserved for an app-level library.

| Format | Role | Reason |
| --- | --- | --- |
| JSON | Native pattern and measurement files | Built into FCL, readable, diffs in git, easy to share |
| SQLite | Optional library: clients/measurements, pattern catalogue, settings | Searchable, grows over time; not suited to small, shared documents |
| XML (read only) | Import Valentina/Seamly2D measurement files (`.vit`, `.vst`) | Compatibility with existing users' data |
| SVG | Export pieces; import as a non-parametric trace layer | Exchange with Inkscape and laser cutters |
| YAML | Not used; possible later export | No standard Pascal library; whitespace pitfalls |

JSON rules:

- Top-level `format` and `version` fields from the first file
- Stable IDs for every object; references by ID
- Formulas stored as strings, evaluated on load
- Consistent key order and pretty-printing on save
- Measurements in separate files from patterns

```json
{
  "format": "pattern",
  "version": 1,
  "units": "mm",
  "measurements": "bill.measurements.json",
  "increments": [
    { "name": "#ease_waist", "formula": "20" }
  ],
  "objects": [
    { "id": "p1", "type": "point", "name": "A", "x": "0", "y": "0" },
    { "id": "p2", "type": "pointAtDistanceAngle", "name": "B",
      "base": "p1", "length": "@waist/4 + #ease_waist", "angle": "0" },
    { "id": "l1", "type": "line", "start": "p1", "end": "p2" }
  ],
  "pieces": []
}
```

## Printing

OpenSloper prints patterns directly at true scale, so no third-party tiling software is needed, a gap found in practice with Seamly2D.

**Tiling:**

- Paper sizes: A4, US Letter and custom, with per-printer margins
- Overlap or glue margin on page edges
- Alignment marks (diamonds or half-circles) that match between neighbouring pages
- Row and column labels (A1, A2, B1…) on every page, plus a page map on the first page
- Blank pages skipped automatically

**Scale accuracy:**

- Test square on the first page (10 cm, or 4 in for Letter) to check with a ruler
- Clear "print at 100% / actual size" reminder in the PDF
- Optional x/y printer calibration factors for printers that are consistently slightly off

**Layout before printing:**

- Choose what to print: selected pieces, all pieces, one or several sizes
- Arrange pieces to minimise pages: manual drag first, simple automatic packing later
- Preview with the page grid over the pieces and a live page count

**Other outputs:**

- Single large-format PDF (A0 or copy-shop width)
- Projector mode: dark background, thick light lines, no tiling, for projecting onto fabric
- SVG and DXF exports, as in the Output layer

**Print screen (the main gap in existing software).** Seamly2D lacked a friendly interface for multi-page printing, so the print workflow is one interactive screen rather than a dialog of settings:

- Large live preview: pieces on the page grid, page labels visible, blank pages greyed out
- Pieces dragged and rotated directly on the preview; page count updates as you move them
- Settings in a side panel (paper, margins, overlap, marks, calibration), with the preview updating instantly
- Click a page to include or exclude it, e.g. to reprint one damaged sheet
- Settings remembered per pattern, so reprinting after a measurement change is one click
- One button each for tiled PDF, large-format PDF and projector PDF

## Annotations

Notes, callouts and a title block are first-class objects that print with the pattern, fixing a gap found with Seamly2D, where adding text over the final design was difficult.

| Kind | Lives in | Anchored to | Typical use |
| --- | --- | --- | --- |
| Note | Pattern space | A point, edge or piece, plus an offset; or free | "Ease sleeve cap between notches", "Stay-stitch neckline" |
| Callout | Pattern space | Text box anywhere; leader arrow tip on a point, an edge position or a piece | Pointing at a specific notch, dart or seam |
| Piece label | Pattern space | Its piece | Name, cut count, on fold, size (already part of the piece) |
| Title block | Sheet space | A page corner or the layout | Pattern name, measurement set or size, date, version, author, scale square |
| Sheet note | Sheet space | A position on the printed layout | General instructions, fabric and notions list, assembly order |

**Anchored, so annotations stay parametric.** A note or callout tip stores the anchor's ID and an offset, not absolute coordinates. When measurements change, it moves with the geometry; if its anchor is deleted, it becomes a free note and is flagged in the problems panel rather than silently lost.

**Live text fields.** Text can include fields filled in at display and print time:

- `{pattern.name}`, `{pattern.version}`, `{measurements.name}`, `{date}`, `{page}`, `{pages}`
- Values from the draft, e.g. `Seam length {=Line_A_B.length} mm`, using the formula engine and the same name-to-ID storage, so renames never break a note

**Text and style:**

- Size set in mm or pt at true print size, so text prints at a known size whatever the zoom
- Multi-line text, bold and italic, left/centre/right alignment, optional box or white background so text stays readable over lines
- Leader arrows with a small set of end styles (arrow, dot, none)

**Visibility:**

- Each annotation is marked print and screen, or screen only (private drafting notes)
- Annotations sit on layers like everything else, so a whole set can be hidden
- The print screen offers a title block template (position, which fields to show), placed once per print, with an optional copy on every tiled page

**Editing:** a Text tool and a Callout tool on the canvas; click to place, type in place, drag the box and the arrow tip separately; anchoring is inferred by snapping, like points. Creating, editing and moving annotations are ordinary undoable commands. Annotations can be added at any stage of drafting, not only at the end: a note anchored to an early construction point stays with it as the draft develops, and annotations are saved in the pattern file with everything else.

```json
{ "id": "n3", "type": "callout", "layer": "notes",
  "text": "Ease cap between notches ({=Curve_SC.length} mm)",
  "anchor": { "edge": "c7", "position": "0.5" },
  "box": { "dx": "40", "dy": "-25" },
  "size": "4mm", "print": true }
```

## File locations

OpenSloper follows each platform's conventions and never writes app files into the home folder root, unlike Seamly2D.

| Kind | Examples | Linux (XDG) | Windows | macOS |
| --- | --- | --- | --- | --- |
| Config | Preferences, printer calibration, UI layout | `~/.config/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Data | SQLite library, templates, user-added blocks | `~/.local/share/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| State | Recent files, window positions, logs | `~/.local/state/opensloper/` | `%LOCALAPPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Cache | Thumbnails, preview renders | `~/.cache/opensloper/` | `%LOCALAPPDATA%\OpenSloper\Cache\` | `~/Library/Caches/OpenSloper/` |

On Linux, `XDG_*_HOME` environment variables are respected when set.

**User documents** (`.sloper` patterns, `.slm` measurements) belong to the user, never in hidden folders. The first save defaults to `Documents/OpenSloper/`; after that the last-used folder is remembered.

**Implementation:**

- One `TAppPaths` unit provides `ConfigDir`, `DataDir`, `StateDir`, `CacheDir` and `DefaultDocumentsDir`; no other code builds paths
- `GetAppConfigDir` covers config on Linux and Windows; macOS and the XDG data and cache folders may need small custom code
- `Application.Title` and the app name are set early so library calls use `opensloper`
- Folders are created on first use, not at install time
- Optional portable mode: a `portable.ini` beside the executable stores everything next to it

## Platforms

Development is on Linux with the Qt widgetset, testing on macOS, and Windows deferred until a general release.

| Platform | Role | Widgetset | Notes |
| --- | --- | --- | --- |
| Linux | Main development | Qt5 or Qt6 | Modern look and HiDPI; ships with the `libQt5Pas` / `libQt6Pas` bindings library as a runtime dependency |
| macOS | Testing | Cocoa | Native Apple Silicon build; Retina-scale canvas; `.app` bundle; signing and notarisation needed for public release |
| Windows | Later | Win32 | Ship `sqlite3.dll`; otherwise kept working through portable code |

**Keeping all platforms viable:**

- Shortcuts use the LCL's platform-neutral modifier (`ssModifier`): Cmd on macOS, Ctrl elsewhere
- Paths built with `ConcatPaths` / `PathDelim`, always through `TAppPaths`
- No Unix-only units in the core
- Canvas and mouse handling tested on Qt and Cocoa early, including Retina scaling
- Optional GitHub Actions builds on Linux, macOS and Windows on every push, so Windows keeps compiling untested

**Deferred until a community release:** packaging the Qt bindings library, macOS code signing and notarisation, Windows builds and `sqlite3.dll`, and GitHub Actions CI. During personal use, only the portable-code practices above apply.

## Testing

Testing runs throughout development; the LCL-free core means most logic is tested without any UI.

**Tools:**

- FPCUnit with the console test runner (GUI runner optional while developing)
- Separate test project in `tests/`, built with `lazbuild` and run from a single `run-tests.sh`
- Tests built with heaptrc (`-gh`) so unfreed objects are reported

| Area | What the tests check |
| --- | --- |
| Geometry | Intersections, curve length, point-at-length, point-in-polygon, signed area, with a tolerance helper (`AssertPointsNear`, e.g. 0.001 mm) |
| Formula engine | Parsing, precedence, degree-based trig, reference lists, name↔ID round trip, error messages and positions |
| Evaluator | Ordering, dirty propagation, cycle rejection, invalid and blocked states |
| Names | Uniqueness, case-insensitivity, reserved words, `2` / `3` copy numbering |
| Operations | Each operation against hand-checked cases, plus failure cases (parallel lines, distance past end) |
| Pieces | Face detection on known drawings, clockwise orientation, seam allowance outlines via Clipper2 |
| Storage | Save → load → save produces identical JSON |
| Undo/redo | Execute then undo restores the exact previous state, including random command sequences |
| Printing | Tile layout maths: page count, overlaps, blank-page skipping |

**Regression patterns.** A few sample patterns (skirt block, bodice block) with two or three measurement sets each, and their expected computed coordinates stored as JSON. Each test evaluates a pattern and compares results, so any change that silently alters a draft fails.

**Habits:**

- Core tests written alongside, or before, geometry and formula code
- Every bug gets a failing test before the fix
- UI kept thin: forms call into the document and core layers
- `run-tests.sh` before each commit, optionally via a git pre-commit hook; the same script becomes the CI step on public release

## Repository layout

The repo mirrors the architecture layers, with third-party code isolated under `packages/`.

```text
opensloper/
├── LICENSE                 GPLv3 full text
├── README.md               what it is, status, build steps, submodule init
├── .gitignore              lib/, backup/, *.ppu, *.o, *.compiled, *.lps, binaries
├── .gitmodules
├── run-tests.sh            submodule init, lazbuild tests, run test binary
├── opensloper.lpi / .lpr   main GUI application
├── src/
│   ├── core/               geometry, expressions, model, evaluator, storage (no LCL)
│   ├── document/           TPatternDocument, undo/redo commands, notifications
│   ├── ui/                 forms, canvas, tools, snapping, panels
│   └── output/             PDF, SVG, DXF, Blender exporters
├── cli/                    opensloper-cli (export, check) using core + ConsoleTools
├── tests/                  FPCUnit test project, regression patterns and expected JSON
├── packages/               git submodules, pinned commits
│   ├── clipper2/
│   ├── bgrabitmap/
│   └── console-tools/
├── documents/              internal development: design document, Claude notes
└── docs/                   user manuals and help; can be published with GitHub Pages
```

`.gitignore` for Lazarus: `lib/`, `backup/`, `*.ppu`, `*.o`, `*.compiled`, `*.lps` (per-user session files), `*.res` if generated, and built executables.

## Dependencies

Third-party and personal Pascal libraries are git submodules under `packages/`, pinned to known-good commits.

| Package | Path | Use | Licence |
| --- | --- | --- | --- |
| Clipper2 | `packages/clipper2` | Seam allowance offsetting and polygon booleans | Boost |
| BGRABitmap | `packages/bgrabitmap` | Antialiased canvas drawing, SVG | Modified LGPL |
| ConsoleTools | `packages/console-tools` | Argument parsing and coloured, word-wrapped help for command-line tools | MIT |

**Submodule practice:**

- Each package is added to the project search path or as a `.lpk` dependency
- Updates are deliberate: a submodule bump is its own commit
- README and `run-tests.sh` include `git submodule update --init --recursive`, so builds never run with missing packages
- Every package must be GPLv3-compatible and carry an explicit licence file

**Command-line tools** (using the LCL-free core and ConsoleTools):

- `opensloper-cli export`: regenerate PDFs for a pattern and one or more measurement files
- `opensloper-cli check`: evaluate a pattern and report invalid objects, gaps and seam mismatches, usable in tests and CI

**ConsoleTools improvements noted:**

- [x] Fix `BuildSortedOptions`: long-only options format `Option.Short` instead of `Option.Long`, so their help order is arbitrary
- [x] Disable colour when `NO_COLOR` is set or stdout is not a terminal (per-parser `IsColor`, `ColorCode`)
- [x] Add `Parse(const Args: array of string)` so FPCUnit tests can supply argument lists
- [x] Add a licence file (MIT)
- [x] Replace `TStrings.Contains` / `ContainsName` with `IndexOf` / `IndexOfName`, so it builds with FPC 3.2.x as shipped by stable Lazarus (now requires FPC 3.2.0+, tested on 3.2.2)

ConsoleTools is public at [github.com/billbsing/console-tools](https://github.com/billbsing/console-tools), MIT licensed, with FPCUnit tests (parse, validation, sort order, colour).

## 3D preview (later phase)

3D draping is deferred and will use Blender's cloth simulation rather than a built-in simulator.

Writing a cloth simulator (triangulation, sewing constraints, body and self-collision, a parametric avatar) is a multi-year effort in commercial tools, so the app only exports what Blender needs:

- Triangulated piece meshes (OBJ)
- A JSON or Python file with seam pairs, piece placement around the body and fabric hints
- A Blender Python script that places pieces, creates sewing springs and runs the simulation in one step

The only requirement now is the **seam** concept in the core model, which also drives 2D seam-length checks. Any 3D module stays separate and reads computed geometry only.

## Roadmap and open questions

The app becomes personally useful at step 7; community release follows if it proves easy to use.

1. Geometry core unit (points, lines, Béziers, intersections) with unit tests, no UI
2. Measurement sets, variables and the formula engine
3. Dependency graph and evaluator (dirty propagation, invalid states, cycle detection)
4. Canvas with pan/zoom and the five core operations, snap-inferred
5. JSON save/load and undo/redo commands
6. Pieces: automatic detection, seam allowance via Clipper2, grainlines, notches
7. True-scale tiled PDF printing
8. Import Valentina/Seamly2D measurement files; SVG export
9. Seams and seam-length checks
10. DXF-AAMA export, simple layout
11. Blender export for 3D preview

Open questions:

- [x] Evaluator details: settled, see Evaluator
- [x] Operation set: settled, see Operation set, including transforms
- [x] Expression engine: settled, TFPExpressionParser behind TFormula; see Formula engine
- [x] Project name: settled, OpenSloper (opensloper.com available; reserve domain and GitHub name; file extensions .sloper for patterns, .slm for measurements)
- [x] Undo granularity: settled, see Key design decisions item 7
