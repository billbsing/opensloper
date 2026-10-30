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
| Measurement set | A person's body measurements, e.g. `@waist`, `@back_length` | Own file, edited in the measurements app; one set drives many patterns. A file is one person's set or a size table with one column per size, which enables grading |
| Variable (increment) | Pattern-level value, e.g. `#ease_waist = 20` | Holds design decisions; formulas may use measurements and other variables (not draft objects, which would tie variables to geometry) |
| Point | A position defined by an operation, its references and formulas | Never stored as fixed coordinates, except free points |
| Operation | How a point is placed: offset, along line, intersection, perpendicular, midpoint/ratio | Inferred from snapping where possible |
| Edge | Line, Bézier curve or arc between points | Curve handles have angle and length formulas |
| Role | Each edge is *construction* (guide, dashed) or *outline* | Only outline edges form piece boundaries |
| Piece | Closed path: ordered edge references, each with a reversed flag | Seam allowance (default + per edge), grainline, notches, labels, cut count, fold line |
| Seam | Pairing of edges on two pieces that are sewn together, with direction | Drives seam-length checks and 3D export |
| Draft | A drafting area within a pattern file, shown as a tab | E.g. bodice, sleeve, collar; drafts share measurements, variables and names |
| Layer | Ordered group within a draft, for drawing order and visibility | E.g. original draft vs rotated dart; can be hidden or locked |
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
- **Core (pure Pascal, no LCL):** geometry, expressions, model, evaluator, piece builder (Clipper2 seam allowance), storage (JSON pattern and measurement files)

Three GUI apps sit on these layers: the measurements app, the drafting app and the publish app (see Measurements app and Publish app). Each owns one kind of file and only reads the ones before it (measurements → patterns → layouts). They share the core, and the publish app the output layer, but not each other's UI.

The UI changes the model only through document commands, and exporters read computed geometry directly from the core, so a new output format never touches drafting code.

## Key design decisions

The central rule: only definitions are saved and undone; computed geometry is always derived.

1. **Definition vs result.** Each object holds its definition (operation, references, formula strings) and a cached computed result (coordinates). Saving, loading and undo touch definitions only.
2. **Dependencies come from formulas.** Each formula is parsed once into an expression tree; everything it references (measurements, variables, objects such as `Line_A_B.length`) plus the operation's direct references forms the dependency graph. The user never manages it.
3. **Ordered, incremental evaluation.** The graph is topologically sorted. A change marks the object and everything downstream dirty, and eventually only those are re-evaluated; the first version recomputes everything (see Evaluator). Formula edits that create a cycle are rejected with a clear message.
4. **Failures are states, not crashes.** If an operation cannot be evaluated (e.g. two lines no longer intersect), the object and its dependents become invalid and are highlighted in red. The pattern stays editable.
5. **IDs separate from names.** Internal IDs are integers that never change and are never reused; user-facing names can be renamed freely.
6. **Operation registry.** Each operation type is a class that declares its inputs and parameters and evaluates itself. Adding a tool means writing one class, adding its `Add…` call to `TPattern`, and giving it a file type in `Sloper.Core.PatternFile`.
7. **Commands for undo/redo.** Every user change is a `TCommand` with `Execute` and `Undo`; the UI listens for change notifications. One drag is one undo step: the start value is recorded on mouse-down, the model updates live during the drag without creating commands, and a single command is committed on mouse-up; Escape cancels and restores the start value. Repeated arrow-key nudges of the same object within about a second merge into one step, as do consecutive spin box or slider changes to the same field. Formula fields commit one step on Enter or loss of focus, not per keystroke.

   Implementation (`Sloper.Document.PatternDocument`):
   - **Changes.** A command is a `TPatternChange` holding the pattern's saved text from before and after. The UI opens a change with `BeginChange`, edits `Pattern` through its normal API (calling `LiveUpdate` while dragging), then calls `EndChange`, or `CancelChange` for Escape. `Commit(Success)` wraps a single edit.
   - **Why text.** Undo restores exactly the earlier definitions, with the same IDs, for every editing call, without writing an inverse for each.
   - **Holding objects.** Undo, redo, cancel and load replace the pattern's objects with new instances (`dcObjectsReplaced`), so the UI holds objects by ID, never by reference, across changes.
   - **Merging.** `EndChange(MergeKey)` joins the last step when it has the same key and came within `MergeSeconds` (1 s) of it, e.g. `nudge:3`. A merged step that cancels out is dropped. A step the file was saved after is never merged into, so the saved state stays reachable.
   - **Limits and the modified flag.** At most `UndoLimit` steps are kept (500). The document is modified when the undo position differs from the one at the last save, or when the measurement set changed.
   - **The measurement set** (file and size) belongs to the document, not the history: undo never swaps it back, and edits to the measurement file itself are not pattern undo steps (see Measurements app). On save it is stored relative to the pattern's folder; while the pattern is unsaved it is stored as an absolute path.
   - **The ID counter** only ever goes up. Undo and redo restore the pattern's text but keep the counter where it is, so undoing a creation and creating something else never hands out the same ID.
   - **Notifications.** Listeners receive a set of `dcPattern`, `dcObjectsReplaced`, `dcMeasurements`, `dcHistory` and `dcFile`.
8. **Storage kept apart from the model.** `TPattern` knows nothing about JSON; `Sloper.Core.PatternFile` reads and writes it through `TPattern`'s loader hooks (`InsertVariable`, `InsertObject`, `UpdateDerivedNames`). With only one format there is no storage interface; one can be extracted if a second format is added.

```pascal
TPointOperation = class
  function Inputs: TObjectRefArray; virtual; abstract;
  function Params: TFormulaArray; virtual; abstract;
  function Evaluate(Ctx: TEvalContext; out Pt: TVec2): Boolean; virtual; abstract;
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

**Implementation** (`Sloper.Core.Evaluator`, `Sloper.Core.Pattern`):

- Node keys are object and variable IDs as text (`12`); measurements are `@key`. `TPattern` creates a measurement node for each key its formulas use, so a key missing from the current set is one error ("@chest is not in the measurement set") and everything reading it is blocked.
- A node's dependencies are its inputs (`InputKeys`, e.g. an offset's base point) plus every reference in its formula fields. A reference to an ID that no longer exists makes the node an error ("Uses object 9, which no longer exists").
- `TPattern.SetFormula` refuses an edit that would close a cycle, naming both nodes. Loaded files can still contain one: nodes on the cycle become errors and their readers are blocked.
- `Evaluate` rebuilds the graph and recomputes everything; dirty tracking can come later if dragging needs it.
- `TPattern` is the editing API (`Add…`, `SetFormula`, `Rename`, `Delete`), reporting refusals in `LastError`, `LastErrorField` and `LastErrorPos`. Undo commands (roadmap step 4) wrap these calls. `Delete` is refused while other nodes use the object.
- Implemented so far: all six point operations (free, offset, along edge, intersect edges, circle × edge, project onto edge) and all edge operations (line, curve, curve path, split edge), with derived names (`Line_A_B`, `Path_A_C`) that follow renamed endpoints until the user names the edge. Pattern files are saved and loaded (`Sloper.Core.PatternFile`, see File format and storage); undo and redo work through `TPatternDocument` (see Key design decisions item 7). The canvas is under way (roadmap step 5; see Drafting experience).
- Every edge keeps its computed geometry as segments (straight or cubic), so length, positions along it, splitting and crossings work the same for every kind of edge. For crossings an edge supplies pieces (`TEdgeObject.Pieces`), one per segment, plus a ray off each end along its tangent when extended; an extended line is therefore its infinite line.
- Split edge creates two new edges (`Line_A_P`, `Line_P_B`) that follow the source edge and the point; the source stays. A part is invalid while the point is off the edge or at one of its ends. Parts of a line stay straight and keep `.angle`.

```pascal
type
  TEvalState = (esValid, esDirty, esError, esInvalid, esBlocked);

  TEvalNode = class
  public
    function InputKeys: TStringArray; virtual;        // direct inputs
    function DependencyKeys: TStringArray;            // inputs + formula references
    function DisplayName: string; virtual; abstract;
    // Called only when every dependency is valid; on failure returns
    // esError or esInvalid with Message set and keeps the last good result
    function Compute(Context: TEvalContext): TEvalState; virtual; abstract;
    function Field(const Name: string): TFormula;     // named formula fields
    property Key: string;
    property State: TEvalState;
    property Message: string;
    property Deps, Dependents: TEvalNodeArray;
  end;

  TEvaluator = class
  public
    procedure Rebuild(const Nodes: TEvalNodeArray; Context: TEvalContext);  // deps + Kahn sort
    procedure Run(Context: TEvalContext);    // blocked if an input failed, else Compute
    class function Reaches(From, Target: TEvalNode; Context: TEvalContext): Boolean;
    property Order: TEvalNodeArray;
  end;
```

## Names and IDs

References are stored as IDs and shown as names, so renaming an object changes one field and never breaks a formula.

**Formulas.** The user types names (`Line_A_B.length + @waist/4 + #ease`) with autocomplete. On commit the parser resolves each name and stores the ID form (`{12}.length + @waist/4 + {3}`): objects as `{id}.property`, variables as `{id}`, measurements by their stable key. Unknown names are rejected at entry. Formula fields, tooltips and error messages convert IDs back to current names for display.

**IDs.** Positive integers from one counter per pattern file, like database keys, shared by every kind of object: variables, points, edges, pieces, drafts, layers and annotations. The object's kind is in its `type`, so the ID carries no prefix.

- Each new object takes the counter's value and the counter goes up by one. It is saved in the file as `nextId` and only ever increases, so an ID that has been saved is never reused: not after deleting, undoing, saving or reopening. An ID handed out and undone before any save can come back after reopening; that is harmless, because no file refers to it.
- This matters beyond the file: layouts refer to pieces by pattern and piece ID, so a reused ID would silently put a different piece in an old piece's place.
- IDs are unique within one pattern file only. Pasted and imported objects get fresh IDs from the receiving file's counter, with references inside the pasted group remapped.
- UUIDs were considered and rejected: IDs only need to be unique within a file, and UUIDs would make every stored formula long and hard to read.

Measurements are the exception: patterns refer to them by a stable key such as `waist`, so any measurement file with the same keys works.

**Name rules:**

- Letters, digits and underscore, not starting with a digit; no dashes or dots, which clash with formula syntax (`A-2`, `A.x`)
- Function names and formula keywords are reserved
- Case is preserved for display but compared case-insensitively
- Unique within each namespace: draft objects (points, edges, pieces share one), `#` variables, `@` measurements
- Auto-naming counts like spreadsheet columns: `A` to `Z`, then `AA`, `AB` … `AZ`, `BA` … `ZZ`, then `AAA`. It always takes the next free name across the whole pattern, skipping names that are taken or reserved (such as `ABS`, `COS`, `MAX`). Auto-names never contain digits, so a trailing number always means a copy
- Line names are derived from endpoints (`Line_A_B`) unless the user sets a custom one

**Renaming.** The rename field validates as the user types and cannot be confirmed with a duplicate or invalid name. Rename is an undoable command.

**Undo and redo never fail or prompt.** Linear undo restores exact earlier states, which were already valid, so no clash can occur. A debug-build assertion checks name uniqueness after every undo and redo.

**Clashes from paste, import, merge or restore** are resolved automatically and reported in a notice:

- Number appended directly, no separator (`A` → `A2`, `A3`…), using the next free number
- An existing numeric suffix is stripped first, so a copy of `A2` becomes `A3`, not `A22`; any trailing digits count as the copy number, so a copy of `Hip2` simply takes the next free number
- Pasted objects get fresh IDs, with references inside the pasted group remapped

## Formula engine

Decision: a small recursive-descent parser of our own (`Sloper.Core.Formula`), on a custom tokenizer (`Sloper.Core.FormulaLexer`). TFPExpressionParser was planned first, but a probe on FPC 3.2.2 showed its error positions refer to translated text, it lets comparisons, `if()`, `mod`, `and`/`or` and strings through, and it reports errors as exceptions; our syntax is small enough that our own parser is less code than wrapping it.

**Syntax:** numbers (`12`, `0.5`, `.5`, `1e3`; `.` is always the decimal point), `+ - * /`, `^` (right-associative and tighter than unary minus, so `-2^2 = -4`), brackets, and the functions `sin cos tan asin acos atan2 sqrt abs min max round`. Angles are in degrees; `atan2(y, x)` returns degrees in (-180, 180]; `round` rounds halves away from zero; `min` and `max` take two or more values. References: `@measurement`, `#variable`, `Object.property`.

**Pipeline:**

1. The tokenizer reads the display form the user types, or the stored ID form from a file, and reports spelling errors with their position.
2. `TFormula` resolves names through a `TNameResolver`, collects the references for the dependency graph and rejects unknown names, objects without a property and unknown properties.
3. The parser builds an expression tree once; evaluation walks it with values from a `TFormulaContext`.
4. The stored form keeps the user's spacing and number spelling; only references change.

**Failures are states.** Parse errors give a message and a 1-based position in the text as typed. Evaluation errors (division by zero, square root of a negative, `asin` out of range, missing value, overflow) set `ErrorMessage` and `ErrorPos`; `DisplayErrorPos` maps the position into the display text. FPU exceptions are masked during evaluation, because x87 exceptions from `Power` can surface outside the method; infinite or NaN results become errors. A formula that fails to parse keeps its text, so a file round-trips unchanged.

```pascal
TFormula = class
  function Parse(const Text: string; Resolver: TNameResolver): Boolean;  // display form
  function ParseStored(const Text: string): Boolean;                     // ID form, from a file
  function Evaluate(Context: TFormulaContext; out Value: Double): Boolean;
  function DisplayText(Resolver: TNameResolver): string;                 // IDs -> names
  function IsLiteral: Boolean;                                           // plain number, draggable
  property StoredText: string;
  property References: TFormulaReferenceArray;                           // for the dependency graph
  property ErrorMessage: string;
  property ErrorPos: Integer;
end;
```

## Operation set

Six point operations and three edge types cover basic bodice, skirt and trouser blocks; many of Valentina's \~30 tools become special cases once formulas can read properties like `{4}.angle`.

**Conventions:**

- Units in mm; angles in degrees, 0° pointing right, positive anticlockwise (as Valentina); the canvas flips y for screen drawing
- Common fields on every object: `id`, `name`, `type`, `layer`, `visible`, `notes`; `visible` applies only while the object's layer is visible (see Draft tabs and layers)
- Readable properties: point `.x`, `.y`; every edge `.length`, `.angle1` (direction of the start handle) and `.angle2` (direction of the end handle, pointing back along the edge); straight edges also `.angle`
- Functions: `sin cos tan asin acos atan2 sqrt abs min max round`

**Point operations:**

| Operation | Fields | Covers |
| --- | --- | --- |
| Free | `x`, `y` | Origin, sketch points not yet pinned |
| Offset | `base`, `mode` (polar/cartesian), `length` + `angle` or `dx` + `dy` | Distance at angle, straight down or across, perpendicular from a line (`angle = {4}.angle + 90`) |
| Along edge | `edge`, `from` (start/end), `mode` (length/ratio), `value` | Point along a line, curve or arc; midpoint (ratio 0.5); thirds; dart positions |
| Intersect edges | `edgeA`, `edgeB`, `extendA`, `extendB`, `pick` | Line×line, line×curve, curve×curve |
| Circle × edge | `centre`, `radius`, `edge`, `extend`, `pick` | Compass step, e.g. shoulder length from neck point onto the shoulder slope line |
| Project onto edge | `point`, `edge`, `direction` (perpendicular/angle), `angle`, `extend` | Foot of a perpendicular; drop vertically from a point to the hem line |

`extend` treats a line as infinite (or extends a curve along its end tangent), so long construction lines aren't needed just to find an intersection. `pick` is a stored crossing number, so the result stays stable when measurements change: crossings are numbered from 1 by distance along the first edge (`edgeA`, or the edge for circle × edge), counting from the start of its extension when extended. Project onto edge has no `pick`; it takes the result nearest the point. A perpendicular onto a curve counts only where the line meets the curve square, not where the curve simply ends.

**Edge operations:**

| Operation | Fields | Covers |
| --- | --- | --- |
| Line | `start`, `end`, `role` | Straight seams, construction lines |
| Curve (cubic Bézier) | `start`, `end`, `angle1`, `length1`, `angle2`, `length2`, `role` | Single smooth curves: hip curve, side seam shaping |
| Curve path | `nodes[]` of `point`, `angle`, `lengthIn`, `lengthOut`; `role` | Armholes, necklines, crotch curves; one shared tangent per node keeps joins smooth. `angle` is the direction of travel at the node; formula fields are named `node2.angle`, `node2.lengthIn` and so on |
| Split edge | `edge`, `point` (on the edge, typically from Along edge or Intersect edges) | Two parametric edges; needed for dart rotation and slash-and-spread |

Handle angles and lengths are formulas, so curves stay parametric (e.g. `length1 = @neck/6`).

**Piece and seam objects:**

| Object | Fields |
| --- | --- |
| Piece | `path[]` of `edge`, `reversed`, `allowance` (override); `allowance` (default); `grainline` (two points or angle); `notches[]` (point, or edge + position); `labels[]`; `cut` (count, onFold, mirrored); `foldEdge` |
| Seam | `pieceA`, `edgesA[]`, `pieceB`, `edgesB[]`, `reversed`, `tolerance` |

**Deferred to phase two:** bisector; circle × circle; arcs (approximated by curve paths at first); tangent from a point to a curve.

```json
{ "id": 5, "type": "circleEdgePoint", "name": "SP",
  "centre": 3, "radius": "@shoulder_length",
  "edge": 4, "extend": true, "pick": 1 }

{ "id": 13, "type": "curvePath", "role": "outline",
  "nodes": [
    { "point": 5, "angle": "{4}.angle - 90", "lengthOut": "40" },
    { "point": 9, "angle": "270", "lengthIn": "35", "lengthOut": "30" },
    { "point": 12, "angle": "0", "lengthIn": "25" }
  ] }
```

## Transforms

A transform is one operation that produces parametric copies of a set of objects, so rotated, mirrored or moved copies update when measurements change.

Uses: dart rotation, slash and spread, mirroring a half piece, and moving a traced section aside to develop it (facings, yokes, pockets).

| Transform | Fields | Notes |
| --- | --- | --- |
| Rotate | `sources[]`, `pivot`, `angle`, `suffix` | Angle is a formula, e.g. dart angle `{5}.angle - {6}.angle` |
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
- Copies can go to a chosen or new layer, keeping the original draft usable; a Move can also put its copies on another draft (see Draft tabs and layers)
- Interactive: pick the pivot, drag with a live ghost preview, snap to angles of existing lines
- Rotate and move preserve lengths, giving a free check that seams are unchanged
- Cut on fold is a piece property applied at output; Mirror is for geometry needed in the draft itself

```json
{ "id": 15, "type": "rotate", "name": "Dart to side",
  "sources": [7, 3, 9], "pivot": 14,
  "angle": "{5}.angle - {6}.angle", "suffix": "_r1", "layer": 2 }
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

**Canvas so far** (`Sloper.UI.Canvas`, with the LCL-free `Sloper.UI.View`, `Sloper.UI.Scene` and `Sloper.Core.Drag`):

- **Drawing:** BGRABitmap on an adaptive mm grid. Outline edges are solid ink; construction edges are thin, grey and dashed. Errors are red and blocked objects orange. Failing objects are faded at their last good result, and objects never computed are not drawn.
- **Navigation:** the wheel scrolls and Shift+wheel scrolls sideways. Ctrl/Cmd+wheel zooms about the cursor. Middle-drag or Space+drag pans. Ctrl/Cmd+0 fits the pattern and Ctrl/Cmd+1 shows it at true size (the screen's pixels per inch).
- **Selection:** click selects a point or edge (points win when they overlap) and Shift adds. Hover highlights, and shows a failing object's message in the status bar.
- **Dragging points:** only fields that are plain numbers change (free x/y, offset length/angle or dx/dy, along-edge value), rounded to 0.1 mm, 0.1° or 0.0001. A point placed by a formula or by other objects is refused, with the reason shown. One drag is one undo step; Escape cancels it.
- **Nudging:** arrow keys move the selected points by 1 mm (10 mm with Shift), merged into one step per run of presses.
- **Deleting:** Delete removes the selection, dependents first. It is refused with a message when anything else uses an object.
- **Tools:** Select (S), Point (P), Line (L) and Curve (C), from the toolbar, the Tools menu or the keys. Escape stops a line, then returns to Select.
- **Snapping** (`Sloper.UI.Snap`): within 8 pixels of the cursor, in this order:
  1. An existing point is reused.
  2. A crossing of two nearby edges becomes an intersect point, with its `pick`. An edge and its own split parts are not treated as crossing.
  3. A place on an edge becomes an along-edge point, measured from the nearer end.
  4. A spot level with or square to a point becomes a polar offset from it. While drawing a line, its start point is tried first; between equally good line-ups, the nearer point wins.
  5. Anything else becomes a free point.

  Values are rounded to 0.1 mm. The canvas shows a marker for the kind of snap, a dotted guide to the point it lines up with, and the line being drawn, and the status bar says what a click will make ("New point 30 mm right of B").
- **Lines and curves** take two clicks. Both new end points and the edge are one undo step, and drawing carries on from the end point. New edges are outlines. A curve starts with handles along the chord, a third of its length, ready to shape in the properties.
- **Properties panel** (`Sloper.UI.Properties`): the selected object's type, name, formulas (shown with names, with readable captions such as "Point 2 handle in") and role, and what it computes to. Enter or leaving a field commits one undo step; Escape puts the text back. A refused formula keeps its text, shows the reason in red and puts the cursor at the problem. The role drop-down is also one undo step.
- **Next:** the property grid layout below, point label modes (the canvas still labels every point), the objects panel with name autocomplete in formula fields, variables and measurements panels, and a node editor for curve handles.

**Automatic piece detection.** Instead of clicking around an outline clockwise, the user clicks inside a region:

1. Build a planar graph from outline edges only; split edges where they cross.
2. Sort edges around each node by outgoing angle (curve tangents, not chords).
3. Prune dangling nodes, then walk faces by always taking the next edge clockwise.
4. Discard the outer face; pick the face containing the click (point-in-polygon).
5. Normalise the found path to clockwise internally using signed area, setting each edge's reversed flag automatically. The user never draws, clicks or orders anything in a particular direction; lines and curves can be drawn either way round.

Handling the edge cases:

- Construction lines are excluded by their role, so they don't fragment regions
- Overlapping pieces: the smallest face is chosen; Shift-click merges adjacent faces
- Nodes within a small tolerance are merged so formula rounding doesn't break cycles
- The piece is stored as edge references, so it follows measurement changes; detection re-runs only on request or to warn when a path no longer closes
- Fallback: click a start edge, the app walks the path and highlights it for confirmation

## Draft tabs and layers

A pattern file holds one or more drafts, shown as tabs along the bottom of the canvas like sheets in a spreadsheet workbook, and each draft holds layers for drawing order and visibility.

**Draft tabs.** Each draft is a separate drafting area in the same pattern file, such as Bodice, Sleeve and Collar, with its own canvas, origin and zoom. All drafts share the measurement set, the `#` variables and the undo history.

- Tabs are added, renamed, reordered by dragging and deleted from the tab bar. Deleting a draft is refused while objects on other drafts use its objects.
- Undo and redo of a change on another draft switch to that draft, so the change is visible.
- Sub-windows (one form per draft) were considered and rejected: they make the user manage windows and are the least portable part of the LCL. Seeing two drafts side by side can come later as a split view, a second canvas pane in the main window showing another tab.

**Names are global.** Names are unique across all drafts, as now, so formulas need no qualifier and nothing changes in the formula engine. Auto-naming continues from the next free name across the whole pattern. Autocomplete and the objects panel show each object's draft beside its name, and the objects panel can filter by draft.

**References between drafts:**

- Formulas may refer to objects on any draft, so a sleeve cap can use the bodice armhole's `.length`.
- Direct inputs (a base point, an edge to intersect or split, a curve's end points) must be on the same draft, so every line on a canvas starts from something visible on it.
- To bring geometry to another draft, such as tracing a facing or yoke off the bodice, a Move transform takes a destination draft and makes parametric copies there.
- Piece detection works within one draft.

**Layers.** Each draft has an ordered list of layers; the order is the drawing order (z-order), as in Inkscape.

- Every object belongs to exactly one layer. New objects go into the active layer, and Move to layer is an undoable command.
- Each layer has a visible and a locked checkbox.
- **Hidden** means not drawn: objects on a hidden layer are still evaluated, because visible objects may depend on them, but they cannot be selected or snapped to.
- The layer comes first: on a hidden layer every object is hidden; on a visible layer each object's own `visible` field decides. A hidden object is treated like one on a hidden layer.
- **Locked** means visible but fixed: its points can be snapped to, but its objects cannot be selected, dragged or deleted. Useful for a finished block being built on.
- Clicking follows the order: points win over edges, as now, and among points or among edges the topmost layer wins.
- Piece detection uses visible outline edges only, so hiding the layer with the original dart lets the user click inside the rotated outline without the old edges splitting the region.
- Deleting a layer is refused while its objects are used elsewhere; a layer can be emptied with Move to layer first.
- A new draft starts with one layer, `Draft`.

**View state is kept out of undo.** Undo restores the pattern's saved text, so anything in that text is part of the history. Layer visibility and lock, the active layer, the current tab and each draft's zoom and position are view state: saved in the pattern file under its own `view` member so the pattern reopens as it was left, but left out of the undo snapshots and the modified flag. The ID counter is also kept out of the undo snapshots but is not view state: it is saved at the top level as `nextId` (see Names and IDs). Draft and layer names, order and membership are part of the pattern and undoable.

**In the file** (shape to be settled with the implementation):

```json
{
  "format": "pattern",
  "version": 1,
  "nextId": 7,
  "drafts": [
    { "id": 1, "name": "Bodice",
      "layers": [ { "id": 3, "name": "Draft" }, { "id": 4, "name": "Side dart" } ] },
    { "id": 2, "name": "Sleeve",
      "layers": [ { "id": 5, "name": "Draft" } ] }
  ],
  "objects": [
    { "id": 6, "type": "freePoint", "name": "A", "layer": 3, "x": "0", "y": "0" }
  ],
  "view": {
    "draft": 1,
    "drafts": {
      "1": { "activeLayer": 4, "zoom": 1.5, "centre": [120, -200],
             "hidden": [], "locked": [3] }
    }
  }
}
```

An object's draft is its layer's draft. The format version stays at 1; files written before drafts and integer IDs are not read, and the regression patterns are rebuilt (see File format and storage).

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

**Point labels.** Labels are hidden by default so the drawing stays clean; they appear only when they help the current step:

| Mode | What shows | When to use |
| --- | --- | --- |
| Contextual (default) | Labels on hover and selection; on points a tool is asking for (e.g. candidate base points while placing an offset point); on the inputs and dependents of the selected object | Normal drafting |
| All | Every point and edge label | Checking or explaining a whole draft; also while a shortcut key is held |
| None | No labels, small point markers only | Reviewing the shape of the design |

Labels never print unless explicitly turned on in the print screen.

**Objects panel.** A side panel lists every point, edge, piece and annotation with its name, operation, formulas, computed position and state (valid, error, invalid, blocked), with search and filter. Selecting in the panel selects and zooms on the canvas, and the reverse. The panel is where names and data are read and edited, so the canvas doesn't need to show them; formula fields use name autocomplete, so hidden labels never make formulas harder to write.

**Property grid.** The properties panel lays out each field on one row, name on the left and value on the right, like the Castle Game Engine inspector, instead of a caption above each field. This keeps the whole selection visible in a narrow panel.

- A splitter between the two columns can be dragged to share the width between names and values. Its position is kept between sessions.
- A name too long for its column is cut with an ellipsis and shown in full as a tooltip.
- Read-only rows (type, computed values) use the same layout with plain text in the value column.
- A refused formula's reason shows in red on a row under its field, across both columns.
- Editing behaviour is unchanged: Enter or leaving a field commits one undo step, and Escape puts the text back.

## File format and storage

Pattern files are JSON; SQLite is reserved for an app-level library.

| Format | Role | Reason |
| --- | --- | --- |
| JSON | Native pattern and measurement files | Built into FCL, readable, diffs in git, easy to share |
| SQLite | Optional library: clients/measurements, pattern catalogue, settings | Searchable, grows over time; not suited to small, shared documents |
| XML (read only) | Import Valentina/Seamly2D measurement files (`.vit`, `.vst`) in the measurements app | Compatibility with existing users' data |
| SVG | Export pieces; import as a non-parametric trace layer | Exchange with Inkscape and laser cutters |
| YAML | Not used; possible later export | No standard Pascal library; whitespace pitfalls |

JSON rules:

- Top-level `format` and `version` fields from the first file
- Stable IDs for every object; references by ID
- Formulas stored as strings, evaluated on load
- Consistent key order and pretty-printing on save: two-space indent, `"key": value`, LF line ends, numbers in the shortest form that reads back exactly (`720`, `432.5`), `.` as decimal point
- Text is UTF-8; every program lists `Sloper.Core.CodePage` first so non-ASCII names and notes survive
- Measurements in separate files from patterns
- A file that fails to load reports why and leaves nothing half-loaded; a formula that does not parse is kept as text and shows as an error

Measurement file (`.slm`); values are in mm, keys follow the name rules and are what patterns refer to (`@waist`):

```json
{
  "format": "measurements",
  "version": 1,
  "units": "mm",
  "name": "Bill",
  "notes": "Measured over a T-shirt",
  "measurements": [
    {
      "key": "waist",
      "value": 820,
      "description": "Waist circumference"
    }
  ]
}
```

Pattern file (`.sloper`, written by `Sloper.Core.PatternFile`). The format stays at version 1 until the first public release: while nobody else has pattern files, format changes such as integer IDs and drafts are made in place and the regression patterns are rebuilt.

```json
{
  "format": "pattern",
  "version": 1,
  "units": "mm",
  "notes": "",
  "measurementFile": "bill.slm",
  "size": "",
  "nextId": 7,
  "drafts": [
    { "id": 1, "name": "Skirt", "layers": [ { "id": 2, "name": "Draft" } ] }
  ],
  "variables": [
    { "id": 3, "name": "ease_waist", "formula": "20", "description": "" }
  ],
  "objects": [
    { "id": 4, "type": "freePoint", "name": "A", "layer": 2, "x": "0", "y": "0" },
    { "id": 5, "type": "offsetPoint", "name": "B", "layer": 2,
      "base": 4, "mode": "polar", "length": "@waist/4 + {3}", "angle": "0" },
    { "id": 6, "type": "line", "layer": 2, "start": 4, "end": 5, "role": "outline" }
  ],
  "view": { "draft": 1 }
}
```

(Shown compacted; the writer puts every member on its own line.)

- `measurementFile` is the measurement set last used with the pattern, written with `/` separators and relative to the pattern's folder unless absolute. `MeasurementFilePath` turns it into a path; the core never loads it by itself. `size` names the size used from a size table, and is empty for a personal set.
- `variables` and `objects` are in creation order. An object's direct inputs (`base`, `edge`, `start`, a path's node points and so on) must name an object earlier in the file. Creation order guarantees this, because inputs exist before the object and cannot be deleted while it uses them. Formulas may refer to any ID; a missing one shows as an error when evaluated.
- IDs and references to them (`base`, `edge`, `layer`, `sources` and so on) are JSON numbers; in formula text a reference is the ID in braces (`{3}`).
- Each object has `id`, `type`, `name` and `layer`, then its inputs and options, then its formulas under their field names, then `role` for edges. An edge whose name is derived from its ends (`Line_A_B`) has no `name`; the name is worked out again after loading, so it can never be stale.
- Members written with their defaults can be left out of hand-written files: `mode` (`polar`, `length`), `from` (`start`), `direction` (`perpendicular`), `extend`, `extendA`, `extendB` (`false`), `pick` (`1`), `role` (`construction`). The writer always writes them.
- `nextId` is the next ID to hand out and is always above every ID in the file. A hand-written file may leave it out; it is then taken as one above the highest ID. Saving writes the counter as it stands, never recomputed from the objects, so deleted IDs stay retired.
- Loading checks IDs (positive integers, unique across drafts, layers, variables and objects, and below `nextId`), names, types, inputs and options, and fails with a message naming the object by ID, since edge names are only derived once everything is loaded (`Object 6 uses object 9, which is not defined before it`), leaving the pattern empty.

| `type` | Members besides `id`, `type`, `name` |
| --- | --- |
| `freePoint` | `x`, `y` |
| `offsetPoint` | `base`, `mode` (`polar`/`cartesian`), `length` + `angle` or `dx` + `dy` |
| `alongEdgePoint` | `edge`, `from` (`start`/`end`), `mode` (`length`/`ratio`), `value` |
| `intersectPoint` | `edgeA`, `edgeB`, `extendA`, `extendB`, `pick` |
| `circleEdgePoint` | `centre`, `edge`, `extend`, `pick`, `radius` |
| `projectPoint` | `point`, `edge`, `direction` (`perpendicular`/`angle`), `extend`, `angle` (only for `angle`) |
| `line` | `start`, `end`, `role` |
| `curve` | `start`, `end`, `angle1`, `length1`, `angle2`, `length2`, `role` |
| `curvePath` | `nodes[]` of `point`, `angle`, `lengthIn` (not on the first), `lengthOut` (not on the last); `role` |
| `splitPart` | `edge`, `point`, `part` (1: start to point, 2: point to end), `role` |

Pieces and seams are added to the file when they exist in the model.

## Measurements app

Measurement files are edited in a third application, `opensloper-measurements`, as SeamlyMe does for Seamly2D. Information flows one way through the three apps, each owning one kind of file and only reading the ones before it: measurements → patterns → layouts.

**Why a separate app.** One measurement file drives many patterns, and recording someone's measurements is a different job from drafting, sometimes done by a different person: it needs a form-like editor, not a canvas. The app is also the natural home for parts of the plan that have no other place: importing Valentina/Seamly2D `.vit` and `.vst` files, size tables for grading, and later the SQLite library of clients and their measurements.

**What it does:**

- Edit keys, values and descriptions in a table, with sizes as columns; keys follow the name rules and are checked as typed
- Add, rename, reorder and delete measurements and sizes; renaming a key warns that patterns using the old key will show it as missing
- Import `.vit` (individual) and `.vst` (multi-size) files
- Show values in mm, cm or inches; files always store mm
- Its own undo history
- Later: the client library, and diagrams showing where to take each measurement

**One file format, one or several sizes.** A measurement file is either one person's set, with a `value` per measurement, or a size table, with a `sizes` list and a `values` list per measurement, one per size. Patterns do not change: they refer to `@waist` either way. Wherever a measurement file is chosen, a size is chosen with it (the drafting app's current set, each source in a layout); a personal set has no size. A size with no value for a key the pattern uses is one error ("@waist has no value for size 42"), and everything reading it is blocked. Pattern-specific ease stays in the pattern's `#` variables, never in the measurement file.

```json
{
  "format": "measurements",
  "version": 1,
  "units": "mm",
  "name": "Women's block sizes",
  "notes": "",
  "sizes": ["36", "38", "40"],
  "measurements": [
    { "key": "waist", "values": [700, 740, 780], "description": "Waist circumference" },
    { "key": "back_length", "values": [405, 410, 415], "description": "Nape to waist" }
  ]
}
```

**One unit is the central control.** All reading, writing and editing of measurement files goes through `Sloper.Core.Measurements` in the core, used by all three apps and the CLI, so key rules, units and formatting are the same everywhere. A long-running service that the apps connect to was considered and rejected: it would add process management, sockets on every platform and crash handling, for a problem that a careful write and a merge by key already solve.

**No measurement set needed to draft.** To keep the drafting app easy to start with, it works with no measurement set: a pattern can be drafted with plain numbers and `#` variables, and `measurementFile` stays empty. Only formulas that use a `@key` show the missing-key error, and adding a key from that error first offers to create a new measurement file for the pattern.

**Small edits from the drafting app.** The drafting app shows the current set in a measurements panel (keys, values, descriptions, search, switching set and size) and allows two small edits:

- Adding a missing key from its error ("@chest is not in the measurement set" → Add, with value and description)
- Changing a value in the panel

Everything else (reordering, sizes, imports, the client library) is done in the measurements app; a button opens it at the current file. Measurement edits are not part of the pattern's undo, because the measurement set belongs to the document, not its history, so the status bar names each change ("@waist 820 → 830 mm saved to bill.slm").

**Writing safely:**

- Every small edit re-reads the file just before writing, applies that one change and writes atomically (a temporary file, then rename), so a change made elsewhere is never overwritten.
- Every app with a measurement file open watches it. With no unsaved edits it reloads. The measurements app, if it has unsaved edits, merges by key: changes to other keys merge automatically, and a change to the same key asks which value to keep.
- The drafting and publish apps re-evaluate when the file changes, the same rule as for pattern files.

**From the CLI and the Automation API:** `opensloper-cli measurements set FILE KEY VALUE [--size SIZE] [--description TEXT]` and `opensloper-cli measurements list FILE` for scripts, and matching `get_measurements` and `set_measurement` methods in the Automation API, so Claude can add a missing measurement. Both use `Sloper.Core.Measurements`.

**Code.** A third Lazarus project, `measurements/opensloper-measurements.lpi`, using `src/core` only.

## Publish app

Publishing is a separate application, `opensloper-publish`, as KiCad splits schematic and PCB editing: the drafting app designs and edits patterns, and the publish app brings finished pieces from one or more patterns together and prints them.

**Why a separate app.** Information flows one way: the pattern defines the pieces, and publishing only arranges and prints them, so nothing has to be synchronised back. Each app does one job and stays small; the drafting app needs no paper, printer or nesting code, and the publish app needs no snapping or formula editing. Both link the same core and evaluate patterns themselves, with no communication between processes.

**What lives where:**

| Drafting app (pattern file) | Publish app (layout file) |
| --- | --- |
| Draft geometry, formulas, variables | Which patterns and measurement sets to use |
| Pieces: outline, seam allowance, grainline, notches, piece labels, cut count, allowed rotations | Placement of each piece copy: position, rotation, flip |
| Pattern-space annotations (notes, callouts) | Sheet-space annotations (title block, sheet notes) |
|  | Paper, margins, overlap, marks, calibration, output kind |

**One or more patterns from the start.** A layout lists its sources, each a pattern file with a measurement set. The same pattern can appear several times with different measurement sets (several sizes on one layout, a step towards grading), and different patterns can share a layout (a skirt and a top cut from the same fabric).

**Keeping in step:**

- The publish app reads saved pattern files and watches them; when one is saved it re-evaluates and redraws, with a status message. Unsaved edits in the drafting app do not appear.
- Placements refer to pieces by source and piece ID, so they survive measurement changes and edits. A new piece appears in an "unplaced" tray; a deleted piece's placement is flagged in the problems list, never silently dropped.
- When pieces grow after a measurement change, overlaps between pieces and pieces running off the sheet are flagged; automatic packing can come later.
- A missing pattern or measurement file, or a piece that fails to evaluate, is shown as a problem. Export refuses while any placed piece is invalid and lists them.

**Moving between the apps.** The drafting app has a Publish… command that opens the publish app with the current pattern, creating a layout for it if there is none, as KiCad's project manager connects its tools.

**Rotation follows the grain.** Each piece says in the drafting app which rotations keep its grainline (0°/180° by default, 90° steps where the fabric allows). The publish app offers only those, plus a flip for mirrored copies. A piece cut twice gets two placements, the second mirrored when `cut.mirrored` is set.

**Layout file** (`.slayout`, JSON under the same rules as pattern files; paths relative to the layout file):

```json
{
  "format": "layout",
  "version": 1,
  "units": "mm",
  "name": "Summer dress, A4",
  "nextId": 4,
  "sources": [
    { "id": 1, "pattern": "skirt.sloper", "measurementFile": "bill.slm" },
    { "id": 2, "pattern": "skirt.sloper", "measurementFile": "sizes.slm", "size": "38" },
    { "id": 3, "pattern": "top.sloper", "measurementFile": "sizes.slm", "size": "38" }
  ],
  "output": { "kind": "tiled", "paper": "A4", "margin": 6, "overlap": 10,
              "marks": "diamond", "calibrationX": 1, "calibrationY": 1 },
  "placements": [
    { "source": 1, "piece": 42, "copy": 1, "x": 120, "y": 40,
      "rotation": 0, "flipped": false }
  ],
  "sheetNotes": [],
  "titleBlock": { "corner": "bottomRight", "fields": ["pattern.name", "measurements.name", "date"] }
}
```

Sources have IDs from the layout's own counter, under the same never-reused rule; `piece` is the piece's ID in that source's pattern file. Placements are plain numbers, not formulas: a layout arranges finished pieces and is not parametric. One layout file holds one arrangement; a differently arranged version (A4 tiles versus one A0 sheet) is another layout file.

**Code.** The publish app is a second Lazarus project, `publish/opensloper-publish.lpi`, using `src/core` and `src/output`. Layout loading, page tiling and preview drawing live in the output layer, so `opensloper-cli export LAYOUT` produces the same PDFs without a window.

## Printing

The publish app (see Publish app) prints patterns directly at true scale, with notes and text printed alongside them (see Annotations), so no third-party tiling or editing software is needed, a gap found in practice with Seamly2D.

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

- Choose what to print: pieces from one or more patterns, in one or several sizes
- Arrange pieces to minimise pages: manual drag first, simple automatic packing later
- Preview with the page grid over the pieces and a live page count

**Other outputs:**

- Single large-format PDF (A0 or copy-shop width)
- Projector mode: dark background, thick light lines, no tiling, for projecting onto fabric
- SVG and DXF exports, as in the Output layer

**Print screen (the main gap in existing software).** Seamly2D lacked a friendly interface for multi-page printing, so the publish app's main window is one interactive screen rather than a dialog of settings:

- Large live preview: pieces on the page grid, page labels visible, blank pages greyed out
- Pieces dragged and rotated directly on the preview; page count updates as you move them
- Settings in a side panel (paper, margins, overlap, marks, calibration), with the preview updating instantly
- Click a page to include or exclude it, e.g. to reprint one damaged sheet
- Settings saved in the layout file, so reprinting after a measurement change is one click
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

**Editing:** a Text tool and a Callout tool on the canvas; click to place, type in place, drag the box and the arrow tip separately; anchoring is inferred by snapping, like points. Creating, editing and moving annotations are ordinary undoable commands. Annotations can be added at any stage of drafting, not only at the end: a note anchored to an early construction point stays with it as the draft develops, and pattern-space annotations are saved in the pattern file with everything else. Sheet-space annotations (title block, sheet notes) belong to a printed layout, so they are edited in the publish app and saved in the layout file.

```json
{ "id": 20, "type": "callout", "layer": 8,
  "text": "Ease cap between notches ({=Curve_SC.length} mm)",
  "anchor": { "edge": 7, "position": "0.5" },
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

**User documents** (`.sloper` patterns, `.slm` measurements, `.slayout` layouts) belong to the user, never in hidden folders. The first save defaults to `Documents/OpenSloper/`; after that the last-used folder is remembered.

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
| Names and IDs | Name uniqueness, case-insensitivity, reserved words, auto-naming past `Z` (`AA`, `BA`, `AAA`, skipping reserved names), `2` / `3` copy numbering; IDs never reused after delete, undo, save and reload |
| Operations | Each operation against hand-checked cases, plus failure cases (parallel lines, distance past end) |
| Pieces | Face detection on known drawings, clockwise orientation, seam allowance outlines via Clipper2 |
| Storage | Save → load → save produces identical JSON |
| Measurements | Personal sets and size tables, missing values per size, atomic save, merge by key with unsaved edits |
| Undo/redo | Execute then undo restores the exact previous state, including random command sequences |
| Printing | Tile layout maths: page count, overlaps, blank-page skipping |

**Regression patterns.** A few sample patterns (skirt block, bodice block) with two or three measurement sets each, and their expected computed coordinates stored as JSON. Each test evaluates a pattern and compares results, so any change that silently alters a draft fails.

- In `tests/patterns/`: `<pattern>.sloper`, `<set>.slm`, and one `<pattern>.<set>.expected.json` per case. The test runs every expected file it finds.
- An expected file is the report from `opensloper-cli check --json` (`Sloper.Core.PatternCheck`): each variable's value and each object's state with its position or length, rounded to 1e-6 mm. Values are compared within 1e-5 mm, the other members exactly.
- A new or deliberately changed pattern gets its expected file from the CLI, after its values are checked by hand. `tests/patterns/README.md` has the commands.
- So far: a straight skirt block that uses every operation, with a small and a large measurement set. A bodice block comes once pieces exist.

**Habits:**

- Core tests written alongside, or before, geometry and formula code
- Every bug gets a failing test before the fix
- UI kept thin: forms call into the document and core layers
- End-to-end checks drive `opensloper-cli serve` through the Automation API and inspect render output, instead of GUI automation tools such as xdotool
- `run-tests.sh` before each commit, optionally via a git pre-commit hook; the same script becomes the CI step on public release

## Repository layout

The repo mirrors the architecture layers, with third-party code isolated under `packages/`.

```text
opensloper/
├── LICENSE                 GPLv3 full text
├── README.md               what it is, status, build steps, submodule init
├── .gitignore              lib/, backup/, *.ppu, *.o, *.compiled, *.lps, binaries
├── .gitmodules
├── run-tests.sh            submodule init, lazbuild tests, run test binary, leak check
├── build.sh                build GUI app and CLI; local toolchain in build.local.sh
├── opensloper.lpi / .lpr   main GUI application
├── src/
│   ├── core/               geometry, expressions, model, evaluator, storage (no LCL)
│   │   └── clipper2/       osclipper2.lpk, builds Clipper2 from the submodule
│   ├── document/           TPatternDocument, undo/redo commands, notifications
│   ├── ui/                 forms, canvas, tools, snapping, panels
│   └── output/             layouts, tiling, PDF, SVG, DXF, Blender exporters
├── measurements/           opensloper-measurements: measurement files and size tables, using core
├── publish/                opensloper-publish: layouts and printing, using core + output
├── cli/                    opensloper-cli (export, check, serve) using core + ConsoleTools
├── tests/                  FPCUnit test project, regression patterns and expected JSON
├── packages/               git submodules, pinned commits
│   ├── clipper2/
│   ├── bgrabitmap/
│   └── console-tools/
├── documents/              internal development: design document, known issues, Claude notes
└── docs/                   user manuals and help; can be published with GitHub Pages
```

`.gitignore` for Lazarus: `lib/`, `backup/`, `*.ppu`, `*.o`, `*.compiled`, `*.lps` (per-user session files), `*.res` if generated, and built executables.

## Dependencies

Third-party and personal Pascal libraries are git submodules under `packages/`, pinned to known-good commits.

| Package | Path | Use | Licence |
| --- | --- | --- | --- |
| Clipper2 | `packages/clipper2` | Seam allowance offsetting and polygon booleans; from the fork [github.com/billbsing/Clipper2](https://github.com/billbsing/Clipper2), which carries our fixes | Boost |
| BGRABitmap | `packages/bgrabitmap` | Antialiased canvas drawing, SVG | Modified LGPL |
| ConsoleTools | `packages/console-tools` | Argument parsing and coloured, word-wrapped help for command-line tools | MIT |

**Submodule practice:**

- Each package is added to the project search path or as a `.lpk` dependency
- Updates are deliberate: a submodule bump is its own commit
- Clipper2 comes from our fork of the original AngusJohnson/Clipper2, which carries our fixes (see `documents/known-issues.md`). That repo was archived in October 2026; development moved to PolyClipping/Clipper2, which is becoming C++ only, so the fork stays on the original. When we need to change Clipper2's behaviour, it becomes our own Pascal-only Clipper2 (Boost licence, keeping Angus Johnson's notices)
- README and `run-tests.sh` include `git submodule update --init --recursive`, so builds never run with missing packages
- Every package must be GPLv3-compatible and carry an explicit licence file

**Command-line tools** (using the LCL-free core and ConsoleTools):

- `opensloper-cli export LAYOUT`: regenerate the PDFs for a layout file after patterns or measurements change
- `opensloper-cli check PATTERN [-m FILE] [-s SIZE] [--json]`: evaluate a pattern and report invalid objects, gaps and seam mismatches, usable in tests and CI. Implemented so far: errors and invalid objects, one line each, with a count of the objects they block; `--json` prints the full report used by the regression tests. Without `-m` it uses the pattern's `measurementFile` and `size`. Exit codes: 0 no problems, 1 problems, 2 usage or file error
- `opensloper-cli measurements list FILE` and `measurements set FILE KEY VALUE [--size SIZE] [--description TEXT]`: read and edit measurement files from scripts, through `Sloper.Core.Measurements` (see Measurements app)

**ConsoleTools improvements noted:**

- [x] Fix `BuildSortedOptions`: long-only options format `Option.Short` instead of `Option.Long`, so their help order is arbitrary
- [x] Disable colour when `NO_COLOR` is set or stdout is not a terminal (per-parser `IsColor`, `ColorCode`)
- [x] Add `Parse(const Args: array of string)` so FPCUnit tests can supply argument lists
- [x] Add a licence file (MIT)
- [x] Replace `TStrings.Contains` / `ContainsName` with `IndexOf` / `IndexOfName`, so it builds with FPC 3.2.x as shipped by stable Lazarus (now requires FPC 3.2.0+, tested on 3.2.2)

ConsoleTools is public at [github.com/billbsing/console-tools](https://github.com/billbsing/console-tools), MIT licensed, with FPCUnit tests (parse, validation, sort order, colour).

## Automation API

OpenSloper exposes its document operations as an API, first so Claude Code can test the app without GUI automation, later so Claude can help design and change patterns.

**One rule: the API only issues document commands.** Every API call goes through the same document-layer commands as the UI, so name rules, formula checks, cycle checks and undo apply exactly as they do for a user. The API cannot put a pattern into a state the UI could not. Measurement edits go through `Sloper.Core.Measurements` with the same safe write as the drafting app.

### Phase 1: scripting and testing

- `opensloper-cli serve` runs the core and document layers with no window, speaking JSON-RPC 2.0 over stdin/stdout, one message per line.
- The GUI app accepts the same API when started with `--automation`, listening on a local socket, so a test can drive the running app and read its UI state (selection, visible labels, canvas snapshot) instead of using xdotool.

| Method | Purpose |
| --- | --- |
| `open`, `save` | Load or save a pattern, optionally with a measurement file and size |
| `get_measurements`, `set_measurement` | Read the current measurement set, or add or change one value |
| `list_objects`, `get_object` | Names, IDs, operations, formulas (display form), computed values and state |
| `add_point`, `add_edge` | Create objects with an operation and formula fields |
| `set_formula`, `rename`, `delete` | Edit existing objects |
| `create_piece` | Detect and create a piece from a position inside a region |
| `evaluate`, `check` | Recompute; return the problems list (invalid, blocked, gaps, seam mismatches) |
| `undo`, `redo` | Step through history |
| `render` | PNG or SVG of the draft or a piece, with options for labels and a region |
| `export` | PDF, SVG or DXF to a given path |
| `ui_state` (GUI only) | Selection, label mode, viewport, canvas snapshot |

`render` lets Claude look at the result, not only check numbers, so a wrong curve or misplaced dart is caught visually.

**Errors are data.** A refused call returns a JSON-RPC error with the message, the field and the character position, matching `TPattern.LastError`, `LastErrorField` and `LastErrorPos`. Evaluation failures are reported as object states, never as crashes.

### Phase 2: Claude as a design assistant

- MCP (Model Context Protocol) is JSON-RPC 2.0 over stdio, so `opensloper-cli serve` grows into an MCP server by adding the MCP handshake and tool listing; the methods above become MCP tools. Claude Desktop and Claude Code can then connect directly.
- With the GUI in `--automation` mode, the user sees Claude's changes live. Each Claude request is grouped into one undo step labelled `Claude: <summary>`, so it can be reviewed and undone at once.
- Example requests: "move the shoulder dart to the side seam", "add 2 cm ease at the hip", "why is point C invalid?", "add notches where the sleeve cap meets the armhole".

### Safety and scope

- Automation is off by default in the GUI, listens only locally (a Unix domain socket, or 127.0.0.1 on platforms without one) and requires a token printed at startup.
- The API works on the open document. File access is limited to `open`, `save` and `export` with paths the caller supplies.
- The API layer lives beside the CLI and the UI and depends only on the document and core layers, keeping both usable without it.

## 3D preview (later phase)

3D draping is deferred and will use Blender's cloth simulation rather than a built-in simulator.

Writing a cloth simulator (triangulation, sewing constraints, body and self-collision, a parametric avatar) is a multi-year effort in commercial tools, so the app only exports what Blender needs:

- Triangulated piece meshes (OBJ)
- A JSON or Python file with seam pairs, piece placement around the body and fabric hints
- A Blender Python script that places pieces, creates sewing springs and runs the simulation in one step

The only requirement now is the **seam** concept in the core model, which also drives 2D seam-length checks. Any 3D module stays separate and reads computed geometry only.

## Roadmap and open questions

Save/load and undo come before the canvas, so the canvas is built on document commands from the start and saved patterns can serve as regression tests. The app becomes personally useful at step 8; community release follows if it proves easy to use.

1. Geometry core unit (points, lines, Béziers, intersections) with unit tests, no UI
2. Measurement sets, variables and the formula engine
3. Dependency graph and evaluator (dirty propagation, invalid states, cycle detection)
4. JSON save/load and undo/redo commands (done)
5. Canvas with pan/zoom and the six point operations, snap-inferred
6. Automation API, phase 1: `opensloper-cli serve` (JSON-RPC over stdio) with `open`, `list_objects`, `set_formula`, `evaluate`, `check` and `render`
7. Pieces: automatic detection, seam allowance via Clipper2, grainlines, notches
8. Publish app: layout files with one or more patterns, true-scale tiled PDF printing
9. Measurements app: measurement and size table editing, Valentina/Seamly2D import; SVG export
10. Seams and seam-length checks
11. DXF-AAMA export, automatic packing in the publish app
12. Blender export for 3D preview

Open questions:

- [x] Evaluator details: settled, see Evaluator
- [x] Operation set: settled, see Operation set, including transforms
- [x] Expression engine: settled, our own recursive-descent parser behind TFormula (TFPExpressionParser was dropped after a probe); see Formula engine
- [x] Project name: settled, OpenSloper (opensloper.com available; reserve domain and GitHub name; file extensions .sloper for patterns, .slm for measurements)
- [x] Undo granularity: settled, see Key design decisions item 7
- [x] Publishing: settled, a separate publish app with layout files that take one or more patterns; see Publish app
- [x] Measurements: settled, a separate measurements app; one file format for personal sets and size tables; small edits from the drafting app through the shared core unit; see Measurements app
- [x] Draft tabs and layers: settled, drafts as tabs within one pattern file, global names, ordered layers per draft; see Draft tabs and layers
