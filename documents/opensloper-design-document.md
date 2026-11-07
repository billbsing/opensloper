# OpenSloper — Design Document

Oct 27, 2026 · @Bill

## Overview

OpenSloper is a parametric sewing pattern drafting application written in Lazarus/Free Pascal, built first for personal use and released to the community if it proves easy to use. It owes much to Valentina and Seamly2D, the open source parametric pattern programs whose ideas it builds on.

Patterns are drafted with relative distances and formulas, so changing a measurement redraws the whole pattern. Valentina and Seamly2D (C++/Qt, which split from a common codebase in 2017) do this already, but both are large and have a steep learning curve. This project aims for the same parametric power with a simpler, more direct drawing experience.

Goals:

- Parametric drafting driven by measurement sets and variables
- An Inkscape-like canvas where snapping records relationships automatically
- Automatic piece detection instead of manually tracing outlines in order
- Seam allowance, notches, grainlines and true-scale tiled printing
- Garments and accessories in fabric and leather, with output for cutting machines
- A small, maintainable codebase with a pure-Pascal core

## Technology and licence

The project uses Lazarus/Free Pascal and is licensed GPLv3 or later.

| Component | Use | Licence |
| --- | --- | --- |
| Lazarus LCL / FCL | GUI, JSON (`fpjson`), XML (`DOM`, `XMLRead`), SQLite (SQLdb) | Modified LGPL with static-linking exception |
| Clipper2 | Polygon offsetting and booleans for seam allowance | Boost |
| BGRABitmap | Antialiased canvas drawing, SVG | Modified LGPL |
| fpvectorial (optional) | DXF/SVG/PDF export helpers | Modified LGPL |
| Tabler Icons | Toolbar and menu icons, SVG in `data/icons` | MIT |

Licence decisions:

- GPLv3 or later, matching Valentina and Seamly2D, so code can be studied, borrowed and shared in both directions.
- `LICENSE` file at the repo root with the full GPLv3 text; a standard GPL header in every unit.
- Code translated from Valentina or Seamly2D keeps their copyright line alongside the project's.
- An About box shows the licence and no-warranty notice.
- User documentation in `docs/` is licensed CC BY-SA 4.0 (see Documentation).

Practices from day one: git repository, internal units in mm, UI text in `resourcestring` sections for translation, and occasional builds on a second OS.

## Core concepts

A pattern is a graph of draft objects whose positions come from measurements, variables and other objects.

| Concept | What it is | Notes |
| --- | --- | --- |
| Measurement set | A person's body measurements, e.g. `@waist`, `@back_length` | Own file, edited in the measurements app; one set drives many patterns. A file is one person's set or a size table with one column per size, which enables grading and multi-size output later |
| Variable (increment) | Pattern-level value, e.g. `#ease_waist = 20` | Holds design decisions; formulas may use measurements and other variables (not draft objects, which would tie variables to geometry) |
| Point | A position defined by an operation, its references and formulas | Never stored as fixed coordinates, except free points |
| Operation | How a point is placed: offset, along line, intersection, perpendicular, midpoint/ratio | Inferred from snapping where possible |
| Edge | Line, Bézier curve or arc between points | Curve handles have angle and length formulas |
| Role | Each edge has a role: construction, outline, or a marking role (placement, stitch, fold, cut) | Only outline edges form piece boundaries; marking edges are attached to a piece automatically (see Markings) |
| Marker | A point's display style: plain, drill/stitch hole, button position, match dot | Markers inside a piece belong to it and print with it. Not built yet (see Markings) |
| Piece | Closed path: ordered edge references, each with a reversed flag | Seam allowance (default + per edge), grainline, notches, internal markings, labels, fabric, cut count, fold line |
| Fabric | A named fabric in the pattern (Main, Lining, Contrast, Interfacing) with a colour and fill style | Pieces are assigned a fabric; drives piece fills, the cut list, and later layout and 3D textures |
| Seam | Pairing of the edges that are sewn together, with direction and expected ease | Made by the user, with suggestions from the app; drives seam-length checks and 3D export |
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

- **UI (LCL):** canvas view (BGRABitmap, pan, zoom), interaction tools (select, add point, curve, piece), snapping engine (turns snaps into operations), panels (properties, objects, variables, measurements, fabrics)
- **Output:** tiled PDF, SVG and DXF with line types for cutting machines, Blender export (later); reads computed geometry from the core
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

**IDs.** Positive integers from one counter per pattern file, like database keys, shared by every kind of object: variables, points, edges, pieces, fabrics and annotations. The object's kind is in its `type`, so the ID carries no prefix.

- Each new object takes the counter's value and the counter goes up by one. It is saved in the file as `nextId` and only ever increases, so an ID that has been saved is never reused: not after deleting, undoing, saving or reopening. An ID handed out and undone before any save can come back after reopening; that is harmless, because no file refers to it.
- This matters beyond the file: layouts refer to pieces by pattern and piece ID, so a reused ID would silently put a different piece in an old piece's place.
- IDs are unique within one pattern file only. Pasted and imported objects get fresh IDs from the receiving file's counter, with references inside the pasted group remapped.
- UUIDs were considered and rejected: IDs only need to be unique within a file, and UUIDs would make every stored formula long and hard to read.

Measurements are the exception: patterns refer to them by a stable key such as `waist`, so any measurement file with the same keys works.

**Name rules:**

- Letters, digits and underscore, not starting with a digit; no dashes or dots, which clash with formula syntax (`A-2`, `A.x`)
- Function names and formula keywords are reserved
- Case is preserved for display but compared case-insensitively
- Unique within each namespace: draft objects (points, edges, pieces share one), `#` variables, `@` measurements, fabrics
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

**Syntax:** numbers (`12`, `0.5`, `.5`, `1e3`; `.` is always the decimal point), `+ - * /`, `^` (right-associative and tighter than unary minus, so `-2^2 = -4`), brackets, and the functions `sin cos tan asin acos atan2 sqrt abs min max round`. Angles are in degrees; `atan2(y, x)` returns degrees in (-180, 180]; `round` rounds halves away from zero; `min` and `max` take two or more values. References: `@measurement`, `#variable`, `Object.property`, and for a repeat's points `Repeat[index].property` (see Operation set).

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

## Pattern units

Decided 2026-11-04; not built yet (every file is `"units": "mm"` today).

**A pattern has one unit, mm, cm or inches, and every number in its formulas is in that unit.** In an inch pattern `@waist/4 + 1` adds one inch. The unit is the pattern file's `units` field, chosen when the pattern is made; the default for new patterns comes from Preferences. Changing the preference never changes an existing pattern.

**Formulas are worked out in the pattern unit.** Every length a formula reads arrives in that unit: measurements (files keep storing mm and are converted as they are read), `#` variables, and object properties such as `.x`, `.y` and `.length`. A plain number therefore needs no label: in `(@waist * 2) + 400` the `2` and the `400` are just numbers, and the result is right whether either was meant as a count or a length, because the whole sum is in one unit. Angles are degrees in every pattern and never converted. Where a result becomes geometry (a free point's `x`, an offset's `length`, an allowance, a radius) it is scaled to mm, so **geometry, the evaluator's computed state, the canvas and all exports stay in mm**, as before.

**What the user sees.** The properties panel, the status bar, snapping read-outs and drag rounding use the pattern unit (drags round to 0.1 mm, 0.1 cm or 0.01 in). The starting values of new objects (allowance, circle radius, rectangle size, marking sizes) are given per unit, so an inch pattern starts with round inch values rather than converted millimetres. In the Automation API, formulas and variable values are in the pattern unit, while positions and lengths in `check` reports and the `render` region stay in mm. A Seamly2D/Valentina pattern keeps its own unit when imported.

**Unit suffixes.** Built 2026-11-05, ahead of the rest of this section. A number may carry a unit, `400mm`, `1.5cm` or `2in` (written straight after it, any case), and is then converted to the pattern unit when evaluated; the suffix is optional, and a plain number is in the pattern unit. Names cannot start with a digit, so `2in` cannot be mistaken for a name, and other letters there are an error ("Unknown unit"). A suffixed number keeps its meaning in any pattern and is never rewritten by a conversion. The lexer keeps the suffix as part of the number's token (`TNumberSuffix`), so it survives the stored and display forms unchanged. The number node keeps the value as written with its suffix and converts it when evaluated, so it follows the pattern's unit. Dragging a point or handle whose length field is a suffixed literal keeps that unit, rounded to 0.1 mm, 0.1 cm or 0.01 in (`DraggedLength` in `Sloper.Core.Drag`). A suffix in an angle or ratio field is not refused yet; it is still scaled as a length.

**Converting a pattern** (Tools → Convert Pattern Units…). This is the one place where the role of each number matters, because only lengths are rewritten (`400` mm → `15.75` in) and counts, ratios and angles are not. Each plain number's role is worked out from where it sits:

- The field it is in says what the whole formula is: a length (`x`, `length`, `allowance`, `radius`), an angle, or a plain number (`count`, a ratio along an edge).
- Operands of `+`, `-`, `min` and `max` share a role, so in `@waist + 400` the `400` is a length.
- In `*`, a number multiplying a length is a plain number (`@waist * 2`); in `/`, a length divided by a number is a length and a length divided by a length is a plain number.
- Arguments of `sin`, `cos`, `tan` and results of `asin`, `acos`, `atan2` are angles; `sqrt` halves a length's power, as in `sqrt(a^2 + b^2)`.
- A `#` variable takes its role from its uses; uses that disagree make it undecided.

Numbers whose role cannot be settled (`400 * 2` in a length field, a variable used both ways) are listed for the user to mark as length or number before the conversion runs. The conversion is one undo step, rounds converted lengths to the new unit's drag precision, and leaves suffixed numbers alone. Geometry does not move, apart from that rounding.

**Code.** `Sloper.Core.Units` holds the unit type, names and scale factors, shared with the measurement code's `TMeasureUnit`. The formula context supplies lengths in the pattern unit and each length field converts its result to mm; the role analysis for conversion works on the parsed expression tree, in the core.

**Stages** (decided 2026-11-06). Both are built (2026-11-07).

- **Stage 1: the pattern's unit.** The file's `units` field (`mm`, `cm` or `in`), and new patterns taking the unit from Preferences. Formulas worked out in the pattern unit, with measurements, variables and properties arriving in it, and each length field converting its result to mm. The properties panel, status bar, rulers, grid, snapping read-outs and drag rounding in the pattern unit, and new objects starting at round values per unit. Note draft values (see Annotations) shown in the pattern unit. The Automation API, Seamly2D/Valentina import keeping its own unit, and tests. This alone makes cm and inch patterns usable; an existing pattern keeps the unit it was made in. **Built in the core** (2026-11-07): `TPattern.Units`, saved and loaded as `units`; the context's `LengthScale` (mm per pattern unit) divides measurements, `.x`, `.y`, `.length` and `.radius` (`IsLengthProperty`) and suffixed numbers as they are read; length fields are read with `EvalLength`, which multiplies by it, while angles, ratios, counts, variables and note values are left in the pattern unit; and drags write plain numbers in the pattern unit (`UnitLengthText`). **Built in the design app** (2026-11-07): File → New and the pattern the app starts with take the unit from Preferences (`NewPattern(AUnits)`); rulers, grid and cursor position follow the open pattern's unit, with the grid spacing Preferences give that unit; the object list, properties, seam and snap read-outs, formula completion and the fabric allowance prompt show it (`FormatLength`, `LengthWithUnit`); and everything that writes a computed length into a formula (snapped points, notes, circles, rectangles, drawn curve handles, notches, Convert to Curve, Arrange) writes it in the pattern unit (`RoundLengthFormulaText`). New objects start at round values per unit (`StartingLengths` in `Sloper.Core.Units`): an empty `DefaultPieceAllowance` or `DefaultSeamTolerance` asks for the unit's value, and a fabric's allowance is a number in the pattern unit. **Built in the Automation API** (2026-11-07): formulas sent as text or plain numbers are in the pattern unit and variable values come back in it, while reported positions and lengths stay mm; `open` and `save` give the pattern's `units`. There is no Seamly2D/Valentina pattern import yet, only measurement files, which are read into mm as before; a pattern importer, when built, gives the new pattern the file's own unit. The Measurements panel and its saved-to-file messages stay in mm (decided 2026-11-07): they edit the measurement file, which stores mm, not the pattern.
- **Stage 2: converting a pattern.** Tools → Convert Pattern Units…, as described above: the role of each plain number worked out from the parsed expression tree, the dialog listing the numbers whose role cannot be settled for the user to mark, and the conversion as one undo step that rounds converted lengths and leaves suffixed numbers alone. **Built** (2026-11-07) in `Sloper.Core.UnitConvert`. A role is a power of length (0 a number or angle, 1 a length, 2 an area), so `sqrt(a^2 + b^2)` and areas convert correctly. Every plain number and every `#` variable is an unknown power; the tree (`TFormula.Shape`) gives linear equations between them, and the field fixes the result (`FieldUnitKind` on each node: length, angle, number, or free for variables and note values). They are solved by Gauss–Jordan elimination in groups of linked unknowns; a number is settled when its power is fixed, and a group whose equations disagree (a variable used both as a length and a count) leaves all its numbers open. Two rules settle more, in order: a number with only one role that leaves no plain number a negative power takes it (in an angle, `2 * 10` is two numbers; in a length, `400 * 2` stays open), and an open factor of something read from the pattern is a plain number if that fits (`@waist / 4` in a note's value). Converted lengths round to the new unit's drag precision, other powers to six places, and a small value that would round to 0 keeps two significant figures. Fabric allowances convert as lengths. The dialog lists the open numbers with the number marked in its formula («400» * 2); each choice is worked through again, so what follows from it fills in, and Convert is enabled once nothing is open. Formulas with errors are left as they are, and the dialog says how many.

## Operation set

Nine point operations and six edge types cover basic bodice, skirt and trouser blocks; circles, arcs, rounded corners and offset edges are added for accessories (see Accessories); many of Valentina's \~30 tools become special cases once formulas can read properties like `{4}.angle`.

**Conventions:**

- Geometry in mm; formula numbers in the pattern's unit (see Pattern units); x right and y down, as on screen and in Valentina and Seamly2D, so 10 cm down from the neck is `dy = 100`; angles in degrees, 0° pointing right, positive anticlockwise as seen on screen, so 90° points up and 270° down. Everything that turns or tells left from right or clockwise from anticlockwise (`PolarPoint`, `AngleBetween`, `AffineTurn`, `LeftOf`, `SignedArea`) means it as seen on screen. The canvas and SVG take model coordinates as they are; PDF and DXF, which are y up, flip on export. Changed from y up on 2026-11-05; pattern files stayed at version 1, since none had been released
- Common fields on every object: `id`, `name`, `type`, `notes`
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
| Circle × circle | `centreA`, `radiusA`, `centreB`, `radiusB`, `pick` | A point at given distances from two points; `pick` 1 is to the left going from A to B, and 2 to the right |
| Project onto edge | `point`, `edge`, `direction` (perpendicular/angle), `angle`, `extend` | Foot of a perpendicular; drop vertically from a point to the hem line |
| Between points | `a`, `b`, `mode` (ratio/length), `value` | A point on the straight line from `a` to `b`, without needing an edge; used by Distribute |
| Repeat | `a` + `b`, or `edge`; `count`, `ends` (include or exclude the end points); `points[]` of `index`, `id` (generated points in use) | N evenly spaced points between two points or along an edge (equal arc length); buttons, pleats, tucks, gathers, notch rows, belt loops |

**Generated points.** A Repeat produces points that any operation can use, like transform copies, named from the repeat and their index (`Btn[1]` … `Btn[6]` for a repeat named `Btn`). Brackets are not allowed in names, so these can never clash with another object. The repeat is edited through its first item: selecting `Btn[1]` shows the repeat's own fields (name, points or edge, `count` and `ends`), and a change there updates every item, so renaming it renames every point. Every other item shows its position, read-only, and no item has a position of its own to edit. `count` is a formula (e.g. `round({12}.length / 80)`), so the number of points can change when measurements do, and evaluating never hands out IDs. Generated points therefore start as virtual points with no ID: their number and positions are computed from the repeat's definition, and only the repeat itself is stored.

A virtual point gets its ID on first use. The command that first uses `Btn[3]`, as an input or in a formula such as `Btn[3].x`, takes an ID from `nextId` and records it against index 3 in the repeat's `points[]`, in the same undo step. References are then ordinary IDs (`{41}.x`), and the ID stays with the index when the count changes. The index in a formula is a plain number, and one past the current count is rejected at entry like an unknown name. If the count drops, references to indices that no longer exist become errors ("Btn[6] no longer exists") rather than silently moving to another point; if the count rises again, the same point comes back. Creating or changing a repeat is one undoable command.

Every point is a `TRepeatPoint` kept by its `TRepeatObject`, not in the pattern's object list, as in the file. Until it is used its key is the repeat's ID and its index (`12[3]`), which `FindNode` understands, so the canvas, the objects list and the properties work with it by key like anything else; it stays out of the graph, and the repeat computes it. `TPattern.UsePoint` turns such a key into an ID, and anything that stores a point goes through it; `CheckPoint` refuses a key that is not an ID, so one can never reach a file. A used point joins the graph and reads its position from the repeat. Parsing a formula that names `Btn[3]` uses the point, which is safe because formulas are only parsed to be kept. A repeat with no points yet, such as one with a bad count, is listed as itself so that it can be put right. Deleting the first point deletes the repeat, which is refused while anything uses one of its points. An edge named after a repeat's point is called `Line_Btn_2_C`, since a name cannot hold brackets. In the app, Add repeat on the Align tab works on two selected points or one edge; while that tab is hidden, repeats are added only through the Automation API (`add_repeat`), and existing ones are still edited in the properties.

`extend` treats a line as infinite (or extends a curve along its end tangent), so long construction lines aren't needed just to find an intersection. `pick` is a stored crossing number, so the result stays stable when measurements change: crossings are numbered from 1 by distance along the first edge (`edgeA`, or the edge for circle × edge), counting from the start of its extension when extended. Project onto edge has no `pick`; it takes the result nearest the point. A perpendicular onto a curve counts only where the line meets the curve square, not where the curve simply ends.

**Edge operations:**

| Operation | Fields | Covers |
| --- | --- | --- |
| Line | `start`, `end`, `role` | Straight seams, construction lines |
| Curve (cubic Bézier) | `start`, `end`, `angle1`, `length1`, `angle2`, `length2`, `role` | Single smooth curves: hip curve, side seam shaping |
| Circle | `centre`, `radius`, `role` | Round bases, hat crowns; see Accessories |
| Arc | `centre`, `radius`, `angle1`, `angle2`, `role` | Brims, curved flaps; see Accessories |
| Curve path | `nodes[]` of `point`, `angle`, `lengthIn`, `lengthOut`; `role` | Armholes, necklines, crotch curves; one shared tangent per node keeps joins smooth. `angle` is the direction of travel at the node; formula fields are named `node2.angle`, `node2.lengthIn` and so on |
| Split edge | `edge`, `point` (on the edge, typically from Along edge or Intersect edges) | Two parametric edges; needed for dart rotation and slash-and-spread |
| Offset edge | `edges[]` (one edge or a connected run, each with a reversed flag), `distance`, `side` (left/right), `role` | Stitch lines, facings, linings, turned edges; inside or outside a piece, mitred corners, failing when the offset collapses (see Offset edge under Markings) |

Handle angles and lengths are formulas, so curves stay parametric (e.g. `length1 = @neck/6`).

**Piece and seam objects:**

| Object | Fields |
| --- | --- |
| Piece | `path[]` of `edge`, `reversed`, `allowance` (override); `allowance` (default); `grainline` (two points or angle); `notches[]` (point, or edge + position); `markings[]` (marked point, marking line, stitch holes; marked points and marking lines are assigned automatically and editable, see Markings); `labels[]`; `cut` (count, mirrored); `foldEdge` (on fold when set); `fabric` (fabric ID); `fill` (optional per-piece override) |
| Seam | `sideA[]` and `sideB[]` of `piece`, `edge`; `reversed`; `ease`; `tolerance` (see Seams) |

**Deferred to phase two:** bisector; tangent from a point to a curve. Circles, arcs and circle × circle are brought forward for accessories (see Accessories).

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
| Mirror | `sources[]`, `axis` (straight edge, two points, or point + angle), `suffix` | Curves mirror exactly, with orientation reversed |
| Move | `sources[]`, `mode` (polar/cartesian), `length` + `angle` or `dx` + `dy`, optional `rotate` + `pivot`, `suffix` | Move-and-rotate repositions a section in one step |

**Copies are real objects.** Each has its own ID and name (source name + suffix, e.g. `A_r1`) and records its source and transform. Its geometry is always computed from the source, so it can't be dragged, but it can be an input to any operation. A copied edge starts with its source's role, which can be changed, as the dart example needs.

**What can be copied.** Points and edges, including split parts and repeat points already in use. Pieces are not: clicking inside the copied outline makes a new piece.

**Edges follow their points.** Selecting an edge pulls in its endpoints automatically; copied edges connect copied points. Every edge keeps its shape as line and Bézier segments, so a copy transforms those segments, which is exact and needs no case for each kind of edge.

**In the graph:** the transform node depends on its pivot or axis and its formulas, and works out one movement. Each copy depends on the transform and on its own source, so a failing source blocks only its own copy. No special evaluator handling is needed.

**Example: shoulder dart to side seam.**

1. Draw a slash line from the bust point to the side seam; split the side seam there.
2. Select the outline between the shoulder dart and the slash.
3. Rotate about the bust point by the dart angle: the shoulder dart closes, a side dart opens.
4. Make the original edges that were rotated construction edges, so they no longer split the region the new outline encloses.
5. Click inside the new outline to form the piece from original and rotated edges.

**Example: separating front and back.** The way Seamly2D users work, except that the separated piece stays parametric:

1. Draft front and back overlapping on the block.
2. Select the back's outline edges and Move Copy them aside (for example `dx = 300`).
3. Make the back-only original edges (back neckline, back armhole) construction edges, so they stay as guides but no longer split the front's region. Shared edges such as the side seam stay outlines, because the front uses them.
4. Click inside each outline to make the front piece from the originals and the back piece from the copies.

Each piece then sits on clear canvas for notches, markings and selection. Move keeps lengths, so the front side seam and the copied back side seam match exactly and Suggest Seams proposes the pair. A measurement change moves both pieces together. A copy cannot be dragged, so the back is reshaped by editing its source in the overlapped draft, and the copy follows: the block stays the master. This is interim; a better front/back method can replace it later without changing the file format.

Slash and spread repeats this: each slash rotates everything beyond it by the spread amount. A convenience Spread tool that generates the chain can come later.

**Behaviour:**

- Creating a transform and all copies is one undoable command
- Deleting a source is refused while a copy uses it, as for any object. Deleting a transform takes its copies with it, unless something else uses them; a copy cannot be deleted alone, as with a repeat's points
- From the app: select objects and choose Rotate Copy, Mirror Copy or Move Copy (Tools → Transform), named so that each says it makes copies and leaves the sources where they are. Rotate Copy then asks for a pivot and Mirror Copy for two points or an edge. The transform starts with no movement and is selected, ready for the angle or distance to be typed as a formula. Copies are selected as a group through their transform
- A live ghost preview while dragging, and snapping to angles of existing lines, are left for later
- A copy is named once, from its source, and keeps that name if the source is renamed. It names no formula of its own, so its properties show what made it and the transform's formulas are edited on the transform

**Code.** `Sloper.Core.Transform` holds `TTransformObject`, `TPointCopy` and `TEdgeCopy`, with `TPattern.AddTransform` expanding the sources and making the copies. The movement is a `TAffine2` from `Sloper.Core.Geometry`. `add_transform` in the Automation API takes `type`, `sources`, `name`, `suffix` and, by type, `pivot`, `angle`, `axis` (`edge`, or `a` and `b`, or `a` with `angle`), `dx` and `dy` or `length`, and `rotate`.
- Rotate and move preserve lengths, giving a free check that seams are unchanged
- Cut on fold is a piece property applied at output; Mirror is for geometry needed in the draft itself

```json
{ "id": 15, "type": "rotate", "name": "Dart to side",
  "sources": [7, 3, 9], "pivot": 14,
  "angle": "{5}.angle - {6}.angle", "suffix": "_r1" }
{ "id": 16, "type": "pointCopy", "name": "A_r1", "transform": 15, "source": 7 }
{ "id": 18, "type": "edgeCopy", "transform": 15, "source": 9, "start": 16, "end": 17,
  "role": "outline" }
```

A file lists a transform before its copies.

## Drafting experience

The canvas feels like Inkscape, but every point records how it was placed relative to others.

Inkscape itself was considered and rejected as the drawing tool: it stores absolute coordinates, while patterns are designed with offset distances and formulas.

**Snap-inferred operations.** The user draws freely; the snap target decides the recorded operation:

- Snap horizontally from A at 250 mm → offset point from A, length pre-filled `250`, later editable to `@waist/4`
- Snap to where two lines cross → intersection point
- Drop in empty space → free point, which can be pinned to a relationship later

This is construction-based (an explicit dependency graph), not constraint-based like FreeCAD's Sketcher, so no numerical solver is needed.

**Borrowed from Inkscape:** node editor with draggable Bézier handles, smart snapping with visual hints, smooth pan/zoom, and a properties panel where formulas for the selection are edited.

**Align and distribute.** An Align panel modelled on Inkscape's Align and Distribute dialog. Unlike Inkscape, which moves objects to new absolute positions, each action rewrites the selected points' definitions, so the arrangement holds when measurements change.

| Action | Result |
| --- | --- |
| Align vertically to A | Each selected point's x becomes `{A}.x`; y unchanged |
| Align horizontally to A | Each selected point's y becomes `{A}.y`; x unchanged |
| Distribute evenly | The two outermost points stay; point i of n inner points becomes a Between points point at ratio `i/(n+1)` |
| Distribute horizontally / vertically | Only x (or y) is spaced evenly between the outer points; the other coordinate unchanged |
| Distribute along edge | Inner points become Along edge points at equal arc-length steps; works on curves |

- "Relative to" chooses the reference: first selected, last selected, or a chosen anchor point.
- The whole action is one undo step.
- Free points and points whose affected parameter is a plain number are converted. Points whose position comes from a formula are listed, with the choice to replace or skip each one; nothing formula-driven is overwritten silently.
- Distribute re-defines points that already exist; Repeat creates new ones. Both use the same underlying operations, Between points and Along edge.
- Snapping already records horizontal and vertical alignment while drawing; Align and distribute is for tidying up afterwards.
- It is the Align tab beside Objects, Variables and Measurements. The tab is hidden for now (2026-11-05) because the panel does not work correctly; the arrange code stays and is reached through the Automation API (`arrange`). `Sloper.Core.Arrange` plans an action first, sorting each point into change, ask or leave, so the panel can ask before anything is touched. A point the reference reads is left alone, since it would read itself.
- Formulas are written in stored form (`{1}.x`), so renaming the reference changes nothing. A cartesian offset keeps its base: its `dx` becomes `{A}.x - {base}.x`. Any other operation is only replaced on a yes; it becomes a free point, with its other coordinate fixed as a number.
- Distribute evenly's two outermost points are the two farthest apart, and the rest keep the order they lie in along the line between them. Distribute along edge shares out the whole edge between its two ends, whichever points are selected; the edge is selected along with the points.
- A point's operation changes in place (`TPattern.ConvertToFree`, `ConvertToBetween`, `ConvertToAlongEdge`), keeping its ID, name and users. Files list objects after their inputs, so the point's new inputs move up the list if they have to, and nothing else moves.

**Canvas so far** (`Sloper.UI.Canvas`, with the LCL-free `Sloper.UI.View`, `Sloper.UI.Scene` and `Sloper.Core.Drag`):

- **Drawing:** BGRABitmap on a grid in the user's unit, at the spacing set in Preferences (see Preferences). Outline edges are solid ink; construction edges are thin, grey and dashed. Errors are red and blocked objects orange. Failing objects are faded at their last good result, and objects never computed are not drawn.
- **Navigation:** the wheel scrolls and Shift+wheel scrolls sideways. Ctrl/Cmd+wheel zooms about the cursor. Middle-drag or Space+drag pans. Ctrl/Cmd+0 fits the pattern and Ctrl/Cmd+1 shows it at true size (the screen's pixels per inch).
- **Selection:** click selects a point or edge (points win when they overlap) and Shift adds. Hover highlights, and shows a failing object's message in the status bar. A drag that starts on empty canvas or a piece, not on a point or handle, draws a dotted box; on release everything wholly inside it is selected, as in Inkscape (points, edges, and pieces whose cutting line fits), and Shift adds to the selection. Escape cancels the box. `ObjectsInBox` in `Sloper.UI.Scene` does the choosing.
- **Dragging points:** only fields that are plain numbers change (free x/y, offset length/angle or dx/dy, along-edge value), rounded to 0.1 mm, 0.1° or 0.0001. A point placed by a formula or by other objects is refused, with the reason shown until the mouse button is released. One drag is one undo step; Escape cancels it.
- **Copies** (planned, 2026-11-05). A point that is a transform copy shows before it is clicked that it follows another point:
  - **Marker.** Always drawn as a small diamond instead of the usual dot. Not hollow, since a hollow handle already means one locked by a formula, and in a neutral colour, since red and orange mean problems. Copied edges keep their normal look; their endpoints carry the diamond.
  - **Link line.** Hovering or selecting a copy draws a faint dashed line back to its source point and highlights the source (see Links and problem display). With a whole moved piece selected, one line joins the middles of the two pieces' extents instead of one per point.
  - **Refused drag.** The status bar names the source and the transform: "A_r1 follows A (Move Copy 'Back'). Edit A to change it."
  - **Go to Source** (Tools menu, or double-click on a copy) selects the source point and brings it into view, since it may be off-screen on the overlapped block. The properties show "Copy of A" as a link that does the same.
- **Nudging:** arrow keys move the selected points by 1 mm (10 mm with Shift), merged into one step per run of presses.
- **Deleting:** Delete removes the selection, dependents first. It is refused with a message when anything else uses an object.
- **Changing an edge's type:** a line becomes a curve and a curve or arc a line, from the Type row in the properties or Tools → Edge → Change to Line / Change to Curve, which work on every selected edge as one undo step. The edge is replaced in place (`TPattern.ConvertToLine`, `ConvertToCurve`): it keeps its ID, role and place, so pieces, seams, notches and formulas that use it go on using it. A name the user gave it is kept; a derived one follows the new type (`Curve_A_B` becomes `Line_A_B`). A new curve starts straight, its handles a third of the way along. An arc's ends are not points, so it becomes a line between two new points, offsets from its centre by its own radius and angle formulas, which still follow measurement changes. Refused: a whole circle (no ends), an arc to a curve, transform copies, split parts and other derived edges, and a line whose `.angle` a formula reads, since only a line has it. `convert_edge` in the Automation API does the same.
- **Merging points:** Tools → Points → Merge Points joins two or more selected points into one, as Inkscape joins nodes, as one undo step, and selects the result (`TPattern.MergePoints`). Points are parametric, so nothing is averaged: one point's definition is kept, and every line, curve, path, piece notch, marking, grainline, transform pivot or axis and formula that used the others uses it instead (each object's `RedirectPoint`, and `{id}` rewritten in stored formulas). The others are then deleted, with any line or curve that ran between two of them.
  - **Name** (`MergedName` in `Sloper.Core.Names`): the first name the user gave, in selection order, or else the lowest name the app made, counted as auto-names are (`M, N, O` → `M`; `M, MyNode, O` → `MyNode`; `Z` before `AA`). A made name is upper-case letters with perhaps a copy number (`M`, `AB`, `M2`). Points carry no record of who named them, so a user's all-capitals name such as `BP` counts as made.
  - **Definition kept:** the named point's, unless it is placed from one of the others, which would make it read itself; then the first selected point that reads none of the others, renamed. A transform copy or a repeat's point follows something else and cannot be deleted, so it can only be the one kept (with its own name), and two of them are refused.
  - **Refused:** fewer than two points; anything that is not a point; a point a transform copies; a line or curve between two of the points that something else uses (a piece, a point along it); a curve path that would pass through the same point twice in a row. `merge_points` in the Automation API does the same.
- **Breaking a point:** Tools → Points → Break Point is the opposite of Merge Points: the selected point, where several lines, curves or curve paths meet, becomes one point for each of them, as one undo step, and they are selected (`TPattern.BreakPoint`). A curve path through the point counts once; arcs and circles centred on it, split parts, copies and other derived edges do not count, since they follow something else. The point keeps its ID and definition and goes with the first edge in the list, and with everything else that used it (points placed from it, formulas, notches, markings), so nothing else changes. Each other edge gets a new point placed from it by a cartesian offset of `dx` 0, `dy` 0: it follows the point as measurements change until it is dragged apart, which sets its offset, and it works the same whatever the point's operation. Pieces join their edges by position, so a piece around the point stays closed. Names are numbered as copies, with the point taking the first number: `M` becomes `M1`, `M2`, `M3`, skipping names that are taken, and a copy's number is replaced (`M2` gives `M3`, `M4`), except that a point keeps its own name when that is the first free one (`M1` gives `M1`, `M2`). Refused for a point that fewer than two edges meet at, a transform copy and a repeat's point. Merging the points again gives the one point back. `break_point` in the Automation API does the same and returns the `points`, the point itself first.
- **Scroll bars** beside and below the canvas show where the view is, over the pattern with a margin round it and wherever the view has been panned to. They stay in place, greyed, when everything is showing, so that the canvas does not change size. After using one the keys go back to the canvas.
- **Tools:** Select (S), Point (P), Line (L), Curve (C), Circle (O), Rectangle (R), Piece (K), Notch (T) and Seam (E), from the toolbar, the Tools menu or the keys. Escape stops a line, then returns to Select.
- **Toolbars and icons:** every command is a `TAction` in one `TActionList`, shared by its menu item and toolbar button, so captions, shortcuts, checked and enabled states stay in step. A command bar runs along the top (New, Open, Save; Undo, Redo, Delete; the zooms; Measurements, Publish, Export Draft SVG), and the drafting tools run down the left of the canvas in the Tools menu's order, wrapping into a second column when the window is short. The Tools menu lists the drawing tools, then groups the commands in submenus so it stays short: Arc; Edge (Split Edge, Round Corner, Change to Line, Change to Curve); Offset (Edge Left, Edge Right, Inside Piece, Outside Piece); Points (Merge, Break); Markings; Draw As; Transform (Rotate, Mirror and Move Copy); and Suggest Seams. A submenu item may have a shorter caption than its action, which keeps the full name for the toolbar tooltip. The measurements and publish apps work the same way through `TCommandSet` (`Sloper.UI.Commands`), each with a command bar along the top: measurements has New, Open, Save; Undo, Redo; Import, Export; Check Against Pattern, and publish has Open, Save; Undo, Redo; Fit Pages, Reload Patterns; Export PDF, SVG, DXF and Machine DXF. Tooltips name the command and its shortcut, and Undo and Redo name the step. In all three GUI apps tooltips appear above the pointer, so they do not cover the buttons it is moving to, and drop below it only at the top of the screen (`Sloper.UI.HintPlacement`, which the publish and measurements apps take from `src/ui`).
- **Icons** are Tabler Icons 3.50.0 outline SVGs (MIT), kept unchanged in `data/icons` with their licence and found like the catalogue. `Sloper.UI.IconSet` lists the file for each command, and `Sloper.UI.Icons` draws them with BGRABitmap at the screen's scale: 24 px for toolbars, 16 px for menus, in the theme's text colour, with a grey set for disabled buttons. A missing folder leaves the toolbars showing captions; a missing file leaves its icon blank. Drafting commands with no close stock icon use the nearest one (Piece: polygon, Arc: rainbow, Notch: inverted triangle, Seam: needle and thread, DXF export: file-vector, machine DXF export: cut, Check Against Pattern: file-search).
- **Rulers** run along the top and left of the canvas, as in Inkscape (View → Rulers, Ctrl+R, kept in `settings.json`). They line up pixel for pixel with the canvas, the left one counting down the screen as model y does, and a red line on each follows the pointer. Ticks come as close as stays readable (at least 6 px apart, numbers at least 50 px): 1, 2 and 5 steps in mm and cm, and halves down to sixteenths in inches, with a longer tick halfway between numbers (`Sloper.UI.RulerTicks`, tested without the LCL). The corner square names the unit in blue. Until patterns have units of their own (see Pattern units) the rulers, like the grid and the cursor position in the status bar, use the unit in Preferences; they then follow the pattern's unit
- **Snapping** (`Sloper.UI.Snap`): within 8 pixels of the cursor, in this order:
  1. An existing point is reused.
  2. A crossing of two nearby edges becomes an intersect point, with its `pick`. An edge and its own split parts are not treated as crossing.
  3. A place on an edge becomes an along-edge point, measured from the nearer end.
  4. A spot level with or square to a point becomes a polar offset from it. While drawing a line, its start point is tried first; between equally good line-ups, the nearer point wins.
  5. Anything else becomes a free point.

  Values are rounded to 0.1 mm. The canvas shows a marker for the kind of snap, a dotted guide to the point it lines up with, and the line being drawn, and the status bar says what a click will make ("New point 30 mm right of B").
- **Lines and curves** take two clicks. Both new end points and the edge are one undo step, and drawing carries on from the end point. New edges are outlines. A curve starts with handles along the chord, a third of its length, ready to shape in the properties.
- **Properties panel** (`Sloper.UI.Properties`, with the LCL-free `Sloper.UI.GridColumns`): the selected object's type, name, formulas (shown with names, with readable captions such as "Point 2 handle in") and role, and what it computes to, laid out as the property grid below. Enter or leaving a field commits one undo step; Escape puts the text back; undo and redo update every field, including the one being typed in. A refused formula keeps its text, shows the reason in red under its field and puts the cursor at the problem. A failing object's evaluation message shows below the rows. The role drop-down is also one undo step.
- **Labels** (`LabelKeys` in `Sloper.UI.Scene`): the View menu switches between Contextual, All and None (see Point labels), remembered in the app's settings. Point labels sit beside the point and edge labels at the middle of the edge. Contextual shows the hovered object; the selection with its direct inputs and dependents; and while drawing, the line's start and what the cursor snaps to. Holding N shows every label in any mode. None also draws smaller point markers.
- **Side panel:** tabs down the left of the window for objects, variables and measurements, shown or hidden with View → Side Panel, remembered in the app's settings. The tabs share `Sloper.UI.ListPanel`: a search box over a list, with the selection held by key.
- **Objects tab** (`Sloper.UI.ObjectsPanel`, with the LCL-free `Sloper.UI.ObjectList`): see Objects panel below.
- **Variables tab** (`Sloper.UI.VariablesPanel`): lists each `#` variable with its formula, value and description, searchable. Add makes a variable (`variable`, `variable2`…) ready to name. Selecting one clears the canvas selection and shows it in the properties panel, where its name, formula and description are edited. Adding, editing and deleting are ordinary undoable changes; deleting is refused while anything uses the variable.
- **Formula autocomplete** (`Sloper.UI.FormulaCompleter`, with the LCL-free `Sloper.UI.Completion`): a formula field offers suggestions under the caret as you type. `@` lists measurements, `#` lists variables, and after an object's dot its properties. A bare word lists objects, variables, measurements and functions, names starting with the word first; choosing an object adds its dot and goes straight on to its properties. The object being edited is left out, as are objects in a variable's formula, since neither would be accepted. Ctrl/Cmd+Space shows everything. Up and Down move, Enter or Tab take the suggestion, Escape closes the list, and the mouse works too. Enter commits the field once the list is closed.
- **Measurements tab** (`Sloper.UI.MeasurementsPanel`): the current set's keys, values and descriptions, searchable, with New and Open for the set. Keys the pattern uses and the set lacks are listed in red as Missing. Selecting a row fills the fields below the list; Enter or Save writes the change straight to the file through `TPatternDocument.ChangeMeasurement`, and the status bar says what changed. Add starts a new key. Saving with no file asks for a new one first. See Small edits from the drafting app. Not done yet: switching size, which waits for size tables in the core; watching the file for changes made elsewhere; and the button that opens the measurements app, which does not exist yet.
- **Test size** (at the bottom of the Measurements tab, under the edit fields): a slider that tries the pattern a size up or down, scaling every measurement the pattern reads by 1% a step, up to 20% either way. `TPatternDocument.SetMeasurementScale` sets `TPattern.MeasurementScale`, which `TPatternContext.MeasurementValue` applies; like the chosen size it is session state, so it is not an undo step, does not modify the pattern and is never saved, and New and Open go back to 0%. The set itself is untouched: the list shows the scaled values, and the fields below it are disabled until the slider is back at 0% (Reset puts it there), so an edit can never write a scaled value to the file. Exports from the drafting app show what is on screen, so a draft SVG exported mid-test is scaled; the publish app reads the files, so it never is
- **Curve handles** (`CurveHandles` in `Sloper.Core.Drag`): selecting a curve or curve path shows its tangent lines. Dragging a handle's end sets its angle and length, rounded like point drags, as one undo step; Escape cancels. As with points, only plain numbers change: a handle whose angle or length is a formula is drawn hollow and refuses the drag with the reason. The two handles at a path's inner node share one angle, so dragging either turns both and the join stays smooth, while each keeps its own length. A split part follows its source curve and has no handles. A handle lies over the objects under it.
- **Pieces:** with the Piece tool, one click inside a closed outline makes a piece with a 10 mm allowance, as one undo step, and selects it; a refusal shows in the status bar, and a region that already has a piece selects that piece instead of adding another. The tool stays on until Escape. The cutting line is filled with its fabric under the edges (see Fabrics). In the Select tool a click inside a piece selects it, with points and edges taking precedence, so to clear the selection click off the piece or press Escape. Hovering or selecting a piece shows chevrons at each edge's middle (see Links and problem display). Its name label sits in the middle of its extent. The properties show its allowance and any per-edge allowances; adding an edge's own allowance is only in the Automation API so far.
- **Grainlines and notches** are drawn over the edges. The grainline's angle is edited in the properties; running it between two points is only in the Automation API so far. The properties also set a piece's cut count (a run of spin clicks is one undo step), mirrored, and its fold, offering the piece's straight edges. With the Notch tool a click near a piece's edge adds a notch to every piece using that edge, so both sides of a shared seam match; on a point it follows the point, and elsewhere it stores a position rounded to 0.1 mm. A click on a notch removes every notch there. Either is one undo step.

**View options for overlapping pieces** (planned, 2026-11-05). Both are view state, like zoom and centre: saved in the pattern's `view`, kept out of undo and the modified flag, and never affecting geometry, references or output.

- **Isolate piece.** With a piece selected, View → Isolate Piece dims everything the piece does not use. Its outline edges, their points and the inputs those points are built from stay at full strength. The set comes from the dependency graph, so nothing is assigned to a piece, and a point two pieces share shows for whichever is isolated.
- **Piece stacking order.** Bring to Front and Send to Back on a piece change only which fill and outline draw over which.

These work alongside the role visibility panel (see Visibility, styles and output under Markings) and piece fills, which are semi-transparent so overlapping pieces stay readable.

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

**Implementation** (`Sloper.Core.PieceDetect`, `Sloper.Core.Piece`, `Sloper.Core.SeamAllowance`):

- `DetectPiecePath` returns a clockwise path of whole edges. A piece refers to whole edges, so a region whose boundary uses only part of an edge is refused, naming the edge to split.
- An edge that has outline split parts is left out; the parts stand in for it, since it stays in the pattern and would overlap them.
- **Overlapping panels.** Panels often overlap (a skirt's side seams cross above the hip), so crossings would cut each panel into faces that no whole edge bounds. When the faces fail, a second pass treats edges as whole and finds the smallest simple closed path around the click. Walking faces cannot do this: at a node the two panels share, the crossing turns the walk onto the wrong panel. A path where one edge's end lies part way along another is rejected, because it is really two regions joined at a point; the user splits that edge (a hem drawn once under a front and a back).
- Not done yet: Shift-click merging and the start-edge fallback.
- **Grainline.** Either the field `grainline.angle`, drawn through the middle of the outline's extent over 60% of the piece's span that way, or two points. New pieces start at 90°. A pattern file's piece may have none.
- **Notches.** A notch sits on a point on the seam line (within 0.05 mm) or at `notchN.position`, millimetres from an edge's own start, whichever way the path runs along it. It is computed as a 6 mm mark from the cutting line inwards, square to the edge at that place, using that edge's allowance. A point off the seam line or a position off the edge makes the piece invalid. Fields go by place in the list, so removing a notch renumbers the later ones.
- **Cut and fold.** A piece has a cut count (at least 1) and a mirrored flag: copies after the first are cut mirrored. Being on the fold is one setting, `foldEdge`, not a separate `onFold` flag, so the two cannot disagree. The fold edge is a straight edge of the piece, has no seam allowance whatever its own allowance says, and shows a bracket with arrows pointing at it. The shape stays half a piece in the draft; opening it out is for output (see Transforms). The label reads "Front, cut 2 mirrored" or "Front, cut 1 on fold".
- **Object order.** A file lists inputs first, and a point can be newer than the piece that comes to use it, so taking on a point moves the piece to the end of the object list. Nothing uses a piece, so this is safe; object order is otherwise creation order.
- `TPieceObject` is an evaluator node whose inputs are its edges, so edges cannot be deleted while a piece uses them. A gap of more than 0.01 mm between neighbouring edges makes it invalid, and it keeps its last good outline. Seams will be the first objects to depend on a piece (see Seams).
- **Seam allowance.** The field `allowance` is the piece's width; `SetEdgeAllowance` gives one edge its own, in a field such as `edge2.allowance` that exists only while it does. Zero suits an edge on a fold; a negative width is invalid. Clipper2's offset takes one width per path, so `OffsetOutline` builds the raw offset itself, the way Clipper2 does (mitres on convex corners, through the vertex on concave ones), with a width per segment, and Clipper2's union with a positive fill removes the loops. Corners with a mitre over four times the allowance are bevelled. A dart's allowance follows the dart as drawn; shaping it for a closed dart comes with notches.

## Markings

Decided 2026-11-05. Edge roles, automatic assignment, point markers, choosing a role before drawing, several lines in the same place the offset edge along a run, the two leather roles, role visibility and output profiles are built (2026-11-06); overriding role styles in Preferences is not yet. Roles replace the Mark Placement Line and Mark Fold Line tools, and point markers replace the hole marking that each piece kept with its own diameter. Stitch holes stay a piece marking along an edge (see Markings inside a piece under Accessories).

Internal markings (placement lines, stitching lines, fold lines, drill and stitch holes) are drawn like any other line or point and given a role. The app attaches them to the right piece itself, so there is no "select a piece, then pick an edge" step.

Seamly2D and Valentina use a two-step workflow: draw the line in draft mode, then add it to a piece's details as an internal path. Markings must belong to a piece so they move with it in layouts and printing, and because overlapping pieces (front drafted over back) make ownership ambiguous. OpenSloper keeps that requirement but resolves ownership automatically.

### Edge roles

| Role | Drawn as | Printed |
| --- | --- | --- |
| Construction | Thin dashed guide | Never on pieces |
| Outline | Piece boundary | Yes |
| Placement | Line for pockets, trims, button bands | Yes, with its piece |
| Stitch | Topstitching or internal seam line | Yes, with its piece |
| Fold | Fold or pleat line | Yes, with its piece |
| Cut | Slit or internal cut | Yes, with its piece |
| Skive line | Extent of thinning at a leather edge | Yes, with its piece |
| Edge finish | How far edge paint, burnishing or binding runs | Yes, with its piece |

**As built.** `TEdgeRole` has the six roles; `MarkingRoles` are the last four. On the canvas and in draft SVG each marking role has its own colour (placement blue, stitch green, fold purple, cut teal, since red and orange mean problems there) and dash, drawn at a fixed size on screen. On paper (PDF, the publish app's plain SVG and its preview) they are black: placement thin and solid, stitch in 1 mm dashes (shorter than the seam line's 2 mm), fold dash-dot, and cut solid at the cutting line's width (`RoleDashes` in `Sloper.Core.Draft`). For machines, fold lines are score lines, cut lines are cut with the cutting line, and placement and stitch lines are marks; DXF-AAMA writes them all on layer 8. The publish app's SVG puts each in a group of class `line-placement`, `line-stitch` and so on.

**Leather roles** (built 2026-11-06). Skive line and Edge finish join `MarkingRoles`, making six, and are assigned to pieces like the others. In files and the Automation API they are `skive` and `edgeFinish`. On the canvas, skive line is brown in long dashes and edge finish is grey and dotted, keeping clear of red and orange. On paper they are black: skive line thin in 4 mm dashes, edge finish dotted. For machines both are marks, and DXF-AAMA writes them on layer 8 with the other marking lines. The publish app's SVG groups them as `line-skive` and `line-edge-finish`.

### Point markers

| Marker | Use | Drawn as |
| --- | --- | --- |
| Plain | Ordinary draft point; not printed | |
| Hole | Drill holes at dart points and pocket corners; rivets, snaps, eyelets | A circle, cut as a hole |
| Button | Button and buttonhole positions (works with Repeat) | A circle with a cross, marked |
| Match dot | Matching points between pieces | A small dot, marked |

**As built** (decided 2026-11-06). The marker and its size belong to the point, not to the pieces it is on: a point's `marker` and its `markerSize` formula, the size across in mm, starting at 4 for a hole, 15 for a button and 3 for a match dot. Changing to another marker keeps the size; Plain drops it. A size of 0 or less makes the point invalid. A repeat takes a marker the same way and marks every one of its points, so a row of buttons follows the count; its points cannot take one of their own. A transform copy keeps its source's marker and size, as a copied edge keeps its role.

- **On pieces.** A marked point joins the pieces it lies in as `{ "kind": "point", "point": 7 }` in their `markings[]`, by the same rules as a marking line (see Automatic piece assignment): inside the cutting line, queued until evaluated, every piece when they overlap, and taken off them all when the point goes back to Plain or is deleted. A repeat lies inside when more than half its points do. A marker outside a piece it is on makes the piece invalid, and a hole on the fold line does too, as before.
- **Drawing.** The canvas and draft SVG draw a marker at its point at true size, whether or not it is on a piece yet, so a loose one shows where it is; a piece draws its markers with its other marks. A match dot is three rings, which read as a filled dot, since marks are strokes.
- **Output.** Holes are cut as true circles, as hole markings were. Buttons and match dots are Marks for machines, drawn on both halves of a piece opened out at its fold, and DXF-AAMA writes them as lines on layer 8 with the marking lines.
- **Problems.** A marked point or repeat in no piece is reported ("H has a marker but is in no piece, so it does not print").
- **Older files.** A piece's `hole` marking is read as a Hole marker on its point, with its `diameter` as the size (the first one, if two pieces gave the point different sizes), and the file is written the new way.
- **Automation API.** `set_marker` takes a point or repeat, `marker` and an optional `size`, and its reply lists the `pieces` it is on, as `set_role` does; every object's reply includes its `marker` when it has one. `add_marking` takes `kind` `point` to attach a marked point by hand, and still takes `hole` with `point` and `diameter`, which sets the marker and attaches it.

### Drawing and editing

- Draw a line between two points as usual, then set its role in the properties panel; or choose a role before drawing so new lines take it.
- Set a point's marker the same way.
- Roles and markers are ordinary undoable property changes.

**As built.** Tools → Draw As, and a drop-down on the command bar that always shows it, choose the role of the lines, curves, circles, arcs and rectangles drawn next; it starts at Outline each session. Offset edges keep their own (see Offset edge). The properties panel shows a point's or repeat's Marker, with its size under it and "Marked on" as for a line. Tools → Markings → Mark Hole makes every selected point or repeat a hole, and a repeat's point stands for its repeat.

### Automatic piece assignment

When an edge or point gets a marking role or marker, the app assigns it to a piece using the point-in-polygon test from piece detection (an edge counts as inside when its sampled points are inside the outline):

| Situation | Result |
| --- | --- |
| Inside exactly one piece | Assigned to that piece, no prompt |
| Inside several overlapping pieces | Assigned to all of them; the user takes it off the extra ones (changed from asking, 2026-11-05) |
| Inside no piece | Stays draft-only and is flagged in the problems panel |

The assignment is stored, not recalculated on every evaluation, so markings never jump between pieces silently. If a measurement change moves a marking outside its piece, the check overlay flags it ("Placement line outside Front"). The piece can be changed at any time in the properties panel, and a marking can belong to more than one piece when needed (for example a fold line shared by mirrored pieces).

Markings created before their piece exists are assigned when the piece is created, by the same rules.

**As built.** A piece keeps the lines assigned to it in its `markings[]` as `{ "kind": "line", "edge": 12 }`; the edge's role says how it prints. Where a line lies is only known once it is computed, so `TPattern` queues a line when it is given a marking role (new, copied by a transform, split, or changed with `SetEdgeRole`), and a new piece queues every line that has no piece; `TPattern.Evaluate` then assigns them and evaluates again. Inside means more than half of nine points sampled along the edge lie inside the piece's cutting line (`LiesInside`). An edge in the piece's own path is never assigned to it.

- **Changing the role.** In the properties panel, which also shows "Marked on" with the piece names, or "No piece". Another marking role keeps the assignment; construction or outline takes the line off every piece. Undo restores both.
- **By hand.** Tools → Markings → Attach Marking to Piece, with a piece and a marking line or marked point selected, attaches it wherever it lies; Tools → Markings → Remove Marking takes it off. `add_marking` with `kind` `line` or `point` does the same in the Automation API.
- **Deleting** a marking line takes it off its pieces in the same step; an edge any piece uses otherwise is still refused.
- **Problems.** `PatternProblems`, so the status bar, `check` and the Problems filter, reports a marking line in no piece ("does not print") and one outside a piece it is marked on.
- **Older files.** A `placement` or `fold` marking is read as a line, and a construction line it was on takes that role; the file is written the new way.
- **Automation API.** `set_role` takes an edge and `role`, and its reply lists the `pieces` the line is now on; `add_edge` and `add_rectangle` take the new roles, and every edge's reply includes its `role`.

### Several lines in the same place

**Different roles between the same two points.** Edges are separate objects, so any number can join the same two points, each with its own role (for example a fold line and a stitch line on one segment). The second takes the next free name (`Line_A_B2`), following the copy-numbering rule.

- Picking: a click where lines coincide selects the top one; clicking again at the same spot, or Alt-click, cycles through the others, and a small popup lists everything under the pointer.
- Display: each role has its own dash pattern and colour, and coincident edges are drawn with a small screen-only offset so it is visible that there is more than one. The offset never affects geometry or printing.
- The Objects panel lists each edge separately, so any of them can be selected there.

**As built** (`ObjectsAt`, `CoincidentEdges` and `NextKey` in `Sloper.UI.Scene`). Edges coincide when they run along the same path either way round, within 0.01 mm, whatever their type, so a straight curve lies on a line. Each group is drawn 3 px apart, square to its first edge's chord. A click picks points first, then edges nearest first with the one drawn on top (later in the pattern) first among equals, then pieces, smallest first. Clicking again within 3 px with one of the lines there selected picks the next line; Alt-click goes through everything under the pointer, points and pieces too. The status bar says which it is ("Fold1 (2 of 2 here; click again for the next)"). The popup is a right-click in the Select tool: it lists everything under the pointer with its type and ticks what is selected.

**Offset edge (parallel lines).** Topstitching and similar lines usually run a fixed distance from an edge ("stitch 6 mm in from the hem"). Drawing them point to point would need new points at every corner, so an operation creates them directly. Offset edge is built for a single edge, to the left or right (see Accessories); markings extend it:

| Operation | Fields | Covers |
| --- | --- | --- |
| Offset edge | `edges[]` (one edge or a connected run, each with a reversed flag), `distance`, `side` (left/right of the direction of travel, or inside/outside when the run belongs to a piece), `role` | Topstitching, facing lines, hem fold lines, seam lines parallel to a cut edge; follows the source edges, including curves, when measurements change |

- `distance` is a formula; the result is one edge that follows its sources, with corners joined (mitred, with a limit) where the run turns.
- Curves are offset by approximation within a small tolerance (for example 0.01 mm), using the segment geometry every edge already provides.
- If the offset collapses (a distance larger than a tight curve's radius allows), the edge becomes invalid with a message, like any failed operation.
- The new edge takes a marking role (usually Stitch) and is assigned to its piece automatically, like any marking.

**As built** (2026-11-06). The run is `edges[]` of `edge` and `reversed`, joined end to end within 0.01 mm, or the edges do not join and the offset is invalid. An outer corner is mitred, and bevelled straight across when the mitre would reach more than four distances from the corner, as seam allowance is; an inner corner is trimmed where the two offsets cross. A closed run, such as a whole outline, joins up at its start too. The offset is invalid ("The offset is more than Arc_O allows") when a curve bends towards its side more tightly than the distance, or when an inner corner would trim away a whole segment.

- **Inside and outside** are worked out when the edge is made and stored as left or right (changed from a stored side, 2026-11-06). The offset reads only its edges, never the piece, since a stitch line inside a piece is one of that piece's markings and reading the piece would make a circular reference. The run follows the piece's path, and the inside is on the right going clockwise as seen on screen. Edges picked from a piece must be one unbroken stretch of its path, which may run round past its first edge.
- **Order.** Selected edges are put in order along the run, which follows the first selected edge the way it is drawn, so left and right are that edge's sides (`ChainRun`); a branch or a gap is refused. `PieceRun` orders a piece's edges by its path.
- **From the app.** Tools → Offset → Edge Left or Edge Right take one edge or a run of them and make a construction edge, as before. Tools → Offset → Inside Piece and Outside Piece take a piece and some of its edges; inside makes a stitch line, which joins the piece, and outside a construction edge. Both start 10 mm away.
- **File and API.** One edge followed forwards is still written as `edge`, so older files are unchanged; a run is written as `edges`. `add_edge` with `type` `offsetEdge` takes `edge`, or `edges` in any order; `side` is `left`, `right`, `inside` or `outside`, and the last two need the `piece`.

**Fold on the outline.** A fold on the piece's own edge (centre front cut on the fold) is not a second line: it is the piece's existing `foldEdge` property. The edge is drawn as a fold line, and the piece is mirrored there for cutting and layout.

### Visibility, styles and output

Planned 2026-11-05 and built 2026-11-06, except overriding styles in Preferences (see As built at the end of this section). Marking roles say what a line means, like KiCad's fixed technical layers (silkscreen, edge cuts): the list is the app's, not the file's, so output settings can rely on it. New roles are added to the built-in list, never defined per pattern.

**More roles for leather.** Skive line and Edge finish (see Leather roles under Edge roles), beside the stitch holes already among the markings (see Accessories).

**Styles.** Each role keeps its built-in colour, dash and weight (see As built under Edge roles), chosen so that every role can be shown at once and read at a glance. Users can override them in Preferences, but the defaults should be distinct enough that few need to. Where lines coincide, each role has a draw priority, and the higher one is drawn on top, alongside the screen-only offset that shows there is more than one.

**Role visibility panel.** A dockable panel lists Construction and every marking role, each with a visibility checkbox and its style swatch. It also has show all, hide all, solo (show only this role) and saved presets such as "Seams only" or "Leather". Outline is not listed, because pieces are made from it and it is always shown.

- It changes the view only. Hidden lines are still stored, evaluated and printed; the drafting app never drops a line because it is hidden.
- A hidden line is not drawn, picked, snapped to or labelled, and it drops out of the click-again cycling for coincident lines. It can still be selected in the Objects panel, which shows it while it is selected. The status bar shows how many roles are hidden, so nothing seems to vanish without a reason.
- Its problems are still reported, so a hidden marking line outside its piece still shows in the Problems filter and `check`.
- **Where it is kept.** Which roles are hidden is view state, saved in the pattern's `view` as `hiddenRoles` and kept out of undo and the modified flag, like zoom and centre. The member is left out when every role is shown. Presets are the user's, not the pattern's, so they live in Preferences (`rolePresets` in `settings.json`), each a name and a list of hidden roles.
- **Draft export** follows the screen, as it does for labels and fills, so a draft SVG leaves out hidden roles. `render` in the Automation API takes an optional `hiddenRoles` list.

```json
"view": { "zoom": 1.5, "centre": [120, -200], "hiddenRoles": ["construction"] }
```

**Output chosen in the publish app.** The drafting app stores every marking, and the publish app decides which reach the output. Machine profiles already switch line types on and off for cutters (see Cutting machines under Accessories); output profiles do the same for what a piece shows, on any output.

- **Where they live.** Output profiles describe a kind of print, not a pattern, so they live in `settings.json` beside the machine profiles, and the CLI reads them too. A layout stores only the profile's name, as `outputProfile` in `output`. A layout without one prints everything, as now. A name not in the settings is a blocking problem for that layout's exports, never a quiet fallback, since a print missing its stitch lines would be cut and sewn wrongly.
- **What a profile lists.** `roles`: the marking roles to include. `pieceMarks`: the piece's other marks to include, from `seamLine`, `notches`, `grainline`, `foldBracket`, `labels`, `holes` and `stitchHoles`. `allowance`: `keep`, or `none` (see below). Optional `styles`: colour, dash and width for each role, for paper only. The cutting line is always included, since it is the piece.
- **Order.** The output profile applies first. With a machine profile, its line-type switches then decide what is left. So a profile says what the job needs, and a machine profile says what the machine can do.
- **Seam allowance.** `allowance` `none` cuts on the seam line, as leather usually is. It changes the piece's outline, not just what is drawn, so the preview, overlap checks, packing and every export use the seam line as the cutting line, and placements give its top left, as for opened-out fold pieces. The seam line itself is not drawn, since it is the cutting line. Pieces whose allowances are already zero look the same either way.
- **Built-in profiles.** The four below ship with the app and can be copied, but not changed, so a layout naming one always prints the same. Profiles are edited in the settings file until there is a window for them, as machine profiles are.

| Profile | `roles` | `pieceMarks` | `allowance` |
| --- | --- | --- | --- |
| Home printing | All | All | Keep |
| Plotter or laser cutter | Cut | Holes, stitch holes | Keep |
| Leather | Stitch, cut, skive line, edge finish | Notches, grainline, labels, holes, stitch holes | None |
| Instructions sheet | Placement, stitch, fold | Seam line, notches, labels | Keep |

```json
"outputProfiles": [
  { "name": "Leather",
    "roles": ["stitch", "cut", "skive", "edgeFinish"],
    "pieceMarks": ["notches", "grainline", "labels", "holes", "stitchHoles"],
    "allowance": "none" }
]
```

**As built** (2026-11-06).

- **Draw priority** (`RolePriorities` in `Sloper.Core.Draft`), lowest first: construction, edge finish, skive line, placement, fold, stitch, cut, outline. The canvas and draft SVG draw edges in that order (`EdgesInDrawOrder`), and among lines in the same place a click picks the highest first.
- **Role visibility panel.** The Lines tab of the side panel (`Sloper.UI.RolesPanel`), docked with the other tabs: a checkbox, a sample of the line and a Solo button for Construction and each marking role, then Show All, Hide All and the presets. Choosing a preset applies it; Save As… stores the hidden roles under a name, replacing one of the same name, and Delete removes the chosen one; both write `rolePresets` at once, the settings file being read again first as for Preferences. The preset box shows the preset that matches what is hidden, if any. A change is a view change (`TPatternDocument.ViewChanged`): no undo step, no modified flag, and it is saved with the zoom when the pattern is next saved.
- **Hidden lines** are left out of drawing (`ShownObjects`), clicks (`ObjectsAt`, `EdgeAt`), box selection, snapping, labels and the screen offset for lines in the same place; a selected one is drawn and labelled. The status bar adds "1 kind of line hidden" or "3 kinds of line hidden" to the problem count.
- **Draft export** from the app passes the view's `hiddenRoles`; `render` takes `hiddenRoles`, a list of role names, and refuses an unknown one.
- **Output profiles** (`Sloper.Core.OutputProfiles`). The built-in names are kept in English, not translated, since layouts store them. A settings profile with a built-in name is ignored, so a copy needs a new name; one with no name is skipped, and unknown roles, marks and bad styles are passed over. `holes` covers every point marker, so buttons and match dots too. A style needs a `#rrggbb` `color` and a `width` above 0, and `dash` is up to four lengths above 0. Styles change the PDF and the plain SVG; the publish preview keeps the built-in look.
- **In the layout.** `TLayout.ChosenOutputProfile` gives the profile, or everything when there is none; an unknown name is a blocking problem ("The output profile Leather 2 is not in the settings, so nothing can be exported") and the preview shows everything meanwhile. `PlaceShape` applies it, so the preview, overlap checks, packing and every export agree: it leaves out what is not listed, cuts on the seam line for `allowance` `none` (notches then start at the seam line), and marks the label hidden (`ShowLabel`) rather than dropping the piece's name. DXF-AAMA follows it too, but always writes the piece's name, size, quantity and material, which the format asks for.
- **Publish app.** An Output profile choice above Machine profile lists Everything, the built-in profiles and the user's, keeping a name the user does not have, as the machine profile choice does. The CLI and the Automation API's `export` read the user's profiles from the settings.

**Open questions:**

- Should buttonhole marks become a marking role, or wait for point markers (button position)? Grainlines and labels stay their own objects, switched by a profile's `pieceMarks`.
- Should a profile send roles to separate files or passes (one file per laser operation)?
- What values does each leather marking need (hole spacing and size, skive width and depth)? Point markers keep theirs on the point (see Point markers); stitch holes keep `spacing` and `size` on the piece's marking.

## Seams

A seam records that edges are sewn together. It is its own object, not a property of an edge: line or curve says nothing about what an edge joins to, nearly every outline edge is sewn, and a role could not name the partner. The role stays construction or outline, and no edge type changes.

The app cannot work seams out for itself. Equal lengths do not show that two edges belong together, a sleeve cap is meant to be longer than its armhole, and an edge shared by two pieces need not be sewn (a hem drawn once under a front and a back). So the user makes seams, and the app only suggests them.

**The object.** `sideA[]` and `sideB[]` each list `piece` and `edge`, in order along the seam. A side can span pieces, so a sleeve cap can sew to a front and a back armhole, and a waistband to a front and a back. It can have gaps, so a waist can run either side of a dart. Both sides may use the same piece (dart legs, a sleeve's underarm), and the same edge (a centre back on a mirrored piece, where the lengths match by definition but 3D export still needs the pairing). Several seams may use one edge, because a neckline can sew to both a collar and a facing.

- **Whole edges only**, as for pieces. A seam covering part of an edge needs the edge split first: select an edge and a point on it, then Tools → Edge → Split Edge, or `split_edge` in the Automation API. A piece keeps the edges it was made from, so splitting comes before making the piece; a piece that already exists has to be deleted and made again to use the parts.
- **Direction.** Each edge runs the way its piece's clockwise path runs, and because of that, sewn edges normally run in opposite directions. So side B is paired against side A from its far end by default, and the user never chooses a direction. `reversed` flips this, for the cases the default gets wrong, mirrored pieces most likely.
- **Length check.** Lengths are the sum of each side's edges, measured on the seam line, which is what a piece's path is. `ease` is the length side B should have over side A, a formula defaulting to 0, and `tolerance` is the allowed error, a formula defaulting to 1 mm. So a cap on side B with `ease` 25 and `tolerance` 2 passes at 23 to 27 mm longer than the armhole. Formulas let gathers follow the pattern, as in `ease = @waist * 0.5`.
- **A mismatch is a problem, not a state.** The seam stays valid and the pattern draws as normal. `opensloper-cli check`, `check` in the Automation API and the Check pattern overlay report it, with both lengths and the difference, and `opensloper-cli check` exits with 1.
- **Unsewn edges are not reported.** Without marking each edge, the check cannot tell a hem or an opening from a forgotten seam. Marking edges that way is left out for now.

**In the evaluator.** `TSeamObject` is a node whose inputs are its pieces, so it is blocked while one fails, and it follows a piece that moves to the end of the object list. Deleting a piece a seam uses is refused, as for an edge a piece uses. An edge that is not on the piece named beside it, or is that piece's fold edge, makes the seam invalid. The seam's fields are `ease` and `tolerance`. Seams are named `Seam`, `Seam2` and so on, and can be renamed. A seam has no place on the canvas of its own, so it has no label; it is selected from the objects list, where the Pieces filter shows it.

**The Seam tool** (E). A click near a piece's edge adds that edge to the current side, and another click removes it; on an edge two pieces share, the side of the edge clicked picks the piece. Tab moves to side B, so a side can take in edges from several pieces, and Shift-Tab moves back. Each side keeps its colour and shows its running length, with the difference in the status bar. Enter makes the seam as one undo step, and it keeps the tool on for the next; Escape clears the sides, then returns to Select.

Selecting a seam highlights both sides in their colours with chevrons for direction. The properties show `ease`, `tolerance`, both lengths, the difference and a Flip button, which is one undo step.

**Suggest seams** (Tools → Suggest Seams) lists likely pairs for the user to tick, with none ticked to begin with: edges shared by two pieces first, then edges on different pieces whose lengths are within 1 mm of each other. Fold edges and edges already in a seam are left out. Accepting the list is one undo step, and nothing is stored until then.

## One canvas

A pattern is one drafting area: every object is on the same canvas, drawn in pattern order with pieces under edges and edges under points. Among points, or among edges, the nearest to the cursor is picked.

**Drafts and layers were taken out** (2026-11-03), with the draft tabs, the Layers panel and the Garment view, to reduce clutter. Drafts held separate drafting areas (bodice, sleeve) as tabs in one file, and layers gave each draft a drawing order and hidden, locked and solo states. They added rules (direct inputs on the same draft, moving between layers, what shows versus what prints) for little use so far. Locking comes back per object (see Planned under Roadmap and open questions).

**One garment or product per file.** Garments that share no geometry (a skirt and a top) are separate pattern files, brought together in the publish app, which already takes several patterns into one layout. Pieces whose geometry depends on each other stay in one file: a sleeve cap drafted from the armhole length, a collar from the neckline, a facing traced off a bodice, a gusset that reads the panel edge it is sewn to. Formulas and seams only work within one file, and references between files would need a dependency graph across files and IDs unique beyond one file, so they are not planned.

**Overlapping pieces.** Front and back are drafted overlapping on the block, as on paper, and each is then separated with Move Copy (see Separating front and back under Transforms). Layers, a draft tab per piece and a z-order between tabs were considered and rejected (2026-11-05): front and back share points and lines (side seam, shoulder, hem), so a shared point would belong to one layer or tab while both pieces need it, and a tab per piece means deciding the pieces before drawing, which works against making a piece by clicking inside an outline. Isolate piece and piece stacking order cover what layers were wanted for, as view state only (see View options for overlapping pieces under Drafting experience).

**View state is kept out of undo.** Undo restores the pattern's saved text, so anything in that text is part of the history. The canvas's zoom and centre are view state: saved in the pattern file under `view` (`{"zoom": 1.5, "centre": [120, -200]}`) once the canvas has shown the pattern, so it reopens as it was left, but left out of the undo snapshots and the modified flag. Undo keeps the view text aside and puts it back after replacing the pattern. The ID counter is also kept out of the undo snapshots but is not view state: it is saved at the top level as `nextId` (see Names and IDs).

**Older files.** A file written while patterns had drafts and layers still loads: its `drafts` list and each object's `layer` are passed over, so every object lands on the one canvas, hidden layers included, and the old `view` is ignored. The drafts' and layers' IDs stay retired, as the counter is kept above them. Saving writes the file without them.

**Code.** `TPattern.View` holds the zoom and centre; `TPatternCanvas.RestoreView` and `StoreView` read and write it. `Sloper.UI.Scene` gives the drawing order and picking. The Automation API's draft and layer methods and `set_active` are gone, as are `layer` on `add_point`, `add_edge` and `add_transform`, `draft` and `shown` on `render`, and `--draft` on `export-draft`.

## Links and problem display

Direction and dependency arrows appear only on hover, selection or piece creation, never permanently, to keep the draft free of noise.

| Link | Shown when | Form |
| --- | --- | --- |
| Piece direction (clockwise path) | Creating a piece (animated along the detected path); hovering or selecting a piece; optional "Show piece direction" toggle, off by default | Small chevrons at each edge's midpoint, not arrowheads at the ends |
| Dependencies (what a point is built from) | Hovering or selecting an object; optional "Show dependencies" toggle for the whole draft | Faint arrows to its inputs, optionally to its dependents |
| Copy source (what a transform copy follows) | Hovering or selecting a copy | Faint dashed line to the source point, which is highlighted; one line between the pieces for a whole moved piece |

**Check pattern overlay.** A display option that highlights problems:

- Gaps where a piece path no longer closes (red circle at the gap)
- Dangling outline edges that can't belong to any piece
- Invalid and blocked objects (red and orange, from the evaluator)
- Seam pairs whose lengths differ by more than their tolerance
- Piece edges whose reversed flag breaks the path direction
- Marking edges or points outside the piece they are assigned to
- Marking roles with no piece (drawn outside every piece)

A problems panel lists each issue in plain words (e.g. "Front: gap between Line\_C\_D and Curve\_D\_E"); clicking one zooms to it. A warning count in the status bar flags issues without forcing the overlay on.

**Point labels.** Labels are hidden by default so the drawing stays clean; they appear only when they help the current step:

| Mode | What shows | When to use |
| --- | --- | --- |
| Contextual (default) | Labels on hover and selection; on points a tool is asking for (e.g. candidate base points while placing an offset point); on the inputs and dependents of the selected object | Normal drafting |
| All | Every point and edge label | Checking or explaining a whole draft; also while N is held on the canvas |
| None | No labels, small point markers only | Reviewing the shape of the design |

Labels never print unless explicitly turned on in the print screen.

**Objects panel.** A side panel lists every point, edge, piece and annotation with its name, operation, formulas, computed position and state (valid, error, invalid, blocked), with search and filter. Clicking a row selects the object on the canvas and brings it into view at the current zoom, so the list can be browsed without the drawing changing scale; double-clicking zooms to it. Selecting on the canvas highlights its row. Ctrl/Cmd+click and Shift+click select several, the arrow keys move the selection, and Delete deletes it as on the canvas. Search looks through names, operations, formulas and the text of notes, so searching for a name also finds what reads it; the filter narrows to points, edges, pieces, notes or problems. The panel is where names and data are read, with editing in the properties panel beside it, so the canvas doesn't need to show them; formula fields use name autocomplete, so hidden labels never make formulas harder to write.

**Property grid.** The properties panel lays out each field on one row, name on the left and value on the right, like the Castle Game Engine inspector, instead of a caption above each field. This keeps the whole selection visible in a narrow panel.

- A splitter between the two columns can be dragged to share the width between names and values, leaving each column a minimum width. Its position is a share of the row width, so it follows the panel when that is resized, and it is kept between sessions in `settings.json`.
- A name too long for its column is cut with an ellipsis and shown in full as a tooltip.
- Read-only rows (type, computed values) use the same layout with plain text in the value column.
- A refused formula's reason shows in red on a row under its field, across both columns.
- Editing behaviour is unchanged: Enter or leaving a field commits one undo step, and Escape puts the text back.

## Measurement editor

Measurements are entered against a built-in catalogue of standard body measurements, with a simple body figure that shows where each one is taken. This is the editing side of the measurements app (see Measurements app).

### Measurement catalogue

- A JSON catalogue ships with the app, `data/measurement-catalogue.json`, listing the standard measurements. It holds the base figures too, so one file describes everything the panel draws. An install puts `data` beside the programs; in the source tree it is found a folder up. It is read by `Sloper.Core.Catalogue`, and without it the table still works.
- It lists 72 measurements so far, the ones most drafting needs, from the 246 in Seamly2D; more are added as entries, with no code change.
- Keys are as short as they can be in whole words, with no abbreviations: `waist_circumference`, not `waist_circ`.
- Each entry lists the names it goes by in other programs' measurement files (check Seamly2D's and Valentina's against their source, which is GPLv3), so the catalogue is also the translation table for import and export. Our keys need not match theirs.
- Definitions follow ISO 8559-1:2017 (anthropometric definitions for body measurement) in meaning; descriptions are our own wording, since the standard's text cannot be copied.
- Custom measurements remain allowed for anything not in the catalogue, following the name rules. Nothing renames keys already in use.

| Field | Purpose |
| --- | --- |
| `key` | Stable key used in formulas (`@waist_circumference`) |
| `translations` | Its names in other formats, by format: `{ "seamly2d": ["waist_circ"] }`. A new format adds a member here, with no change to the entries' keys. The first name in a list is the one exported |
| `name` | Display name ("Waist circumference") |
| `group` | Heights, circumferences, widths, arm, leg, crotch, head, hand, foot |
| `description` | One line on what it is |
| `howTo` | How to take it (tape position, posture) |
| `view` | Figure view it appears on: front, back or side |
| `overlay` | Line or path on the figure, in figure coordinates |
| `range` | Typical minimum and maximum in mm, for typo warnings |

Values outside the typical range produce a warning, never a refusal, so unusual bodies are not blocked: the status bar says so and the cell is tinted.

### Importing and exporting other formats

Seamly2D and Valentina files come first; other programs' files use the same translation, each as one more format name in `translations`. `Sloper.Core.SeamlyFormat` reads and writes them. Seamly2D's individual `.smis` and multi-size `.smms` are Valentina's `.vit` and `.vst` with the root element renamed; the root says what a file is, from individual version 0.3.0 and multi-size version 0.4.0, and older ones are refused with the reason. Valentina's names match Seamly2D's for everything in the catalogue, so `seamly2d` covers both. Exports are checked against their schemas: version 0.3.4 and 0.4.5, and 0.3.3 and 0.4.4 for `.vit` and `.vst`.

- `knownNames` in the catalogue lists all of a format's names, including those with no entry yet. Such a name is imported as it is, and goes back out unchanged rather than as a custom measurement.
- Values in an individual file can be formulas. Arithmetic on numbers and the file's other values is worked out and the result stored, with a note, since our measurement files hold values. Anything else, such as a function, is left at 0 and listed.
- A multi-size file gives a base value with an increase for each 2 cm of size and 6 cm of height, whereas a size table has one dimension. Importing makes a column for each size within three steps of the base, at the base height, and reports that the other heights were left out. Exporting needs sizes that are even numbers from 22 to 72; it takes the middle one as the base, draws a straight line through the first and last values, and reports any value more than 0.5 mm off it. Height increases are 0, from height 176 cm.
- An individual file exported from a size table holds the size the cursor is in.

- On import, a measurement's name is looked up in `translations` for that format and renamed to our key.
- A name with no translation is kept as it is, as a custom key. A leading `@`, which marks their custom measurements, is dropped, since `@` is our own prefix in formulas.
- A name that breaks our name rules, or a key already taken in the file, is never dropped: it gets the next free number or is corrected, and is listed.
- After an import the app lists what was renamed, what was kept and what needed changing, so nothing is altered silently.
- On export, each key is translated back to the first name listed for that format. A key with no translation is written as it is, marked as a custom measurement where the format needs that (the leading `@` for Seamly2D).
- Keys already in use that are not in the catalogue, such as `waist` and `back_length`, stay custom keys.

### Body figure

- A panel beside the measurement list shows simple front, back and side outlines, drawn by us (no third-party images, so no licence questions).
- The measurements in the file are drawn faintly. Selecting or hovering over a field highlights its measurement line on the figure, as does choosing an entry in the catalogue; clicking a line on the figure selects its field. Below it is the entry's description, how to take it and its typical range.
- One base figure per view, with each measurement's line drawn from the catalogue `overlay`, so adding a measurement means adding a catalogue entry, not drawing a new picture.
- Drawn with BGRABitmap like the canvas; the catalogue and figure live in the core/data layer and the panel in the measurements app.
- Later: scale the figure to the entered values, so unusual proportions or likely typos stand out visually.

### Editing

- Add from the catalogue by group, with search; only the measurements a person needs are kept in their file, so the list leaves out those already in it. An added measurement takes the catalogue's description. In a personal set it starts at 0, which the range warning points out, and in a size table with no values.
- Values are entered in the display unit (mm, cm or inches) and stored in mm.
- When the measurements app is given a pattern, by the drafting app's Edit button, on the command line or with File → Check Against Pattern, it lists what the pattern uses that the file cannot give it: keys it lacks, and in a size table the sizes with no value. One button adds a missing key, with the catalogue's description where it has one, or goes to the empty cell. The list follows edits and is read again when the pattern is saved. It reads the saved pattern, which needs no measurement set.

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
- Formulas stored as strings, evaluated on load; a pattern's `units` (`mm`, `cm` or `in`) is the unit of its formula numbers (see Pattern units), while measurement and layout files always store mm
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

Keys from the measurement catalogue are preferred; custom keys follow the name rules.

Pattern file (`.sloper`, written by `Sloper.Core.PatternFile`). The example shows `view`, which is written once the canvas has shown the pattern. The format stays at version 1 until the first public release: while nobody else has pattern files, format changes such as integer IDs and drafts are made in place and the regression patterns are rebuilt.

```json
{
  "format": "pattern",
  "version": 1,
  "units": "mm",
  "notes": "",
  "measurementFile": "bill.slm",
  "size": "",
  "nextId": 9,
  "variables": [
    { "id": 3, "name": "ease_waist", "formula": "20", "description": "" }
  ],
  "objects": [
    { "id": 4, "type": "freePoint", "name": "A", "x": "0", "y": "0" },
    { "id": 5, "type": "offsetPoint", "name": "B",
      "base": 4, "mode": "polar", "length": "@waist/4 + {3}", "angle": "0" },
    { "id": 6, "type": "line", "start": 4, "end": 5, "role": "outline" }
  ],
  "fabrics": [
    { "id": 7, "name": "Main", "color": "#5B8DB8", "fill": "tint" },
    { "id": 8, "name": "Lining", "color": "#C9A227", "fill": "hatch" }
  ],
  "view": { "zoom": 1.5, "centre": [120, -200] }
}
```

(Shown compacted; the writer puts every member on its own line.)

- `measurementFile` is the measurement set last used with the pattern, written with `/` separators and relative to the pattern's folder unless absolute. `MeasurementFilePath` turns it into a path; the core never loads it by itself. `size` names the size used from a size table, and is empty for a personal set.
- `variables` and `objects` are in creation order. An object's direct inputs (`base`, `edge`, `start`, a path's node points and so on) must name an object earlier in the file. Creation order guarantees this, because inputs exist before the object and cannot be deleted while it uses them. Formulas may refer to any ID; a missing one shows as an error when evaluated.
- IDs and references to them (`base`, `edge`, `sources` and so on) are JSON numbers; in formula text a reference is the ID in braces (`{3}`).
- Each object has `id`, `type` and `name`, then its inputs and options, then its formulas under their field names, then `role` for edges. An edge whose name is derived from its ends (`Line_A_B`) has no `name`; the name is worked out again after loading, so it can never be stale.
- Members written with their defaults can be left out of hand-written files: `mode` (`polar`, `length`), `from` (`start`), `direction` (`perpendicular`), `extend`, `extendA`, `extendB` (`false`), `pick` (`1`), `role` (`construction`). The writer always writes them.
- A point or repeat with a marker has `marker` (`hole`, `button` or `match`) and its `markerSize` formula; a plain one has neither.
- `nextId` is the next ID to hand out and is always above every ID in the file. A hand-written file may leave it out; it is then taken as one above the highest ID. Saving writes the counter as it stands, never recomputed from the objects, so deleted IDs stay retired.
- `view` may also hold `pieceOrder`, the piece IDs in drawing order from back to front (only pieces moved from creation order need listing), and `isolate`, the ID of an isolated piece. Both are left out when unused and, like zoom and centre, kept out of undo and the modified flag. Planned, 2026-11-05.
- Loading checks IDs (positive integers, unique across variables, fabrics and objects, and below `nextId`), names, types, inputs and options, and fails with a message naming the object by ID, since edge names are only derived once everything is loaded (`Object 6 uses object 9, which is not defined before it`), leaving the pattern empty.

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
| `circle` | `centre`, `radius`, `role` |
| `arc` | `centre`, `radius`, `angle1`, `angle2`, `role` |
| `circleCirclePoint` | `centreA`, `centreB`, `pick`, `radiusA`, `radiusB` |
| `offsetEdge` | `edge`, or `edges[]` of `edge` and `reversed` for a run; `side` (`left`/`right`), `distance`, `role` |
| `cornerArc` | `vertex`, `edgeA`, `edgeB`, `radius`, `role` |
| `cornerPoint` | `arc`, `end` (1 or 2) |
| `curvePath` | `nodes[]` of `point`, `angle`, `lengthIn` (not on the first), `lengthOut` (not on the last); `role` |
| `splitPart` | `edge`, `point`, `part` (1: start to point, 2: point to end), `role` |
| `piece` | `path[]` of `edge`, `reversed`, `allowance` (only for an edge with its own); `allowance`; `grainline` (optional: `angle`, or `start` and `end`); `notches[]` (optional: `point`, or `edge` and `position`); `markings[]` (optional: `kind` of `point`, `line` or `stitch`, then `point` (a point or repeat with a marker), or `edge`, with `spacing` and `size` for `stitch`; older files' `placement` and `fold` are read as `line`, and `hole` with its `diameter` as the point's marker, see Markings); `cut` (optional: `count`, 1 by default, and `mirrored`); `foldEdge` (optional); `view` (optional: `none` by default); `fabric` (optional, see below); `fill` (optional: `color`, and `style` of `tint` or `hatch`) |
| `seam` | `sideA[]` and `sideB[]` of `piece`, `edge`; `reversed`; `ease`; `tolerance` |

Custom labels join `piece` when they are built.

`fabrics` lists `id`, `name`, `color` (`#RRGGBB`), `fill` (`tint` by default, or `hatch`) and optional `allowance`. It sits after `objects` but is read first, since pieces refer to it. A pattern whose only fabric is the untouched Main has neither `fabrics` nor a piece `fabric` (see Fabrics).

## Measurements app

Measurement files are edited in a third application, `opensloper-measurements`, as SeamlyMe does for Seamly2D. Information flows one way through the three apps, each owning one kind of file and only reading the ones before it: measurements → patterns → layouts.

**Why a separate app.** One measurement file drives many patterns, and recording someone's measurements is a different job from drafting, sometimes done by a different person: it needs a form-like editor, not a canvas. The app is also the natural home for parts of the plan that have no other place: importing Valentina/Seamly2D `.vit` and `.vst` files, size tables for grading, and later the SQLite library of clients and their measurements.

**What it does:**

- Edit keys, values and descriptions in a table, with sizes as columns; keys follow the name rules and are checked as typed
- Add, rename, reorder and delete measurements and sizes; renaming a key warns that patterns using the old key will show it as missing
- Import and export `.smis` and `.vit` (individual), and `.smms` and `.vst` (multi-size) files
- Show values in mm, cm or inches; files always store mm
- Its own undo history
- Add measurements from the catalogue, with a body figure showing where each is taken (see Measurement editor)
- Later: the client library

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

A size with no value is `null` in `values`. Each measurement holds one value per size, and a personal set is the same with a single value, so everything reads `Value`, which follows the selected size: the first until another is chosen. A table always keeps at least one size. The first size added to a personal set takes over its values; each later size starts empty.

**One unit is the central control.** All reading, writing and editing of measurement files goes through `Sloper.Core.Measurements` in the core, used by all three apps and the CLI, so key rules, units and formatting are the same everywhere. A long-running service that the apps connect to was considered and rejected: it would add process management, sockets on every platform and crash handling, for a problem that a careful write and a merge by key already solve.

**No measurement set needed to draft.** To keep the drafting app easy to start with, it works with no measurement set: a pattern can be drafted with plain numbers and `#` variables, and `measurementFile` stays empty. Only formulas that use a `@key` show the missing-key error, and adding a key from that error first offers to create a new measurement file for the pattern.

**Small edits from the drafting app.** The drafting app shows the current set in a measurements panel (keys, values, descriptions, search, switching set and size) and allows two small edits:

- Adding a missing key from its error ("@chest is not in the measurement set" → Add, with value and description), or any new key with the panel's Add button, since a formula using an unknown key is refused as it is typed
- Changing a value or description in the panel

Everything else (reordering, sizes, imports, the client library) is done in the measurements app; a button opens it at the current file. Measurement edits are not part of the pattern's undo, because the measurement set belongs to the document, not its history, so the status bar names each change ("@waist 820 → 830 mm saved to bill.slm").

**Writing safely:**

- Every small edit re-reads the file just before writing, applies that one change and writes atomically (a temporary file, then rename), so a change made elsewhere is never overwritten.
- Every app with a measurement file open watches it. With no unsaved edits it reloads. The measurements app, if it has unsaved edits, merges by key: changes to other keys merge automatically, and a change to the same key asks which value to keep.
- The drafting and publish apps re-evaluate when the file changes, the same rule as for pattern files.

**From the CLI and the Automation API:** `opensloper-cli measurements set FILE KEY VALUE [--size=SIZE] [--description=TEXT]`, `measurements list FILE [--size=SIZE] [--json]` and `measurements missing FILE PATTERN` for scripts, and matching `get_measurements`, `set_measurement` and `missing_measurements` methods in the Automation API, so Claude can add a missing measurement. `set` keeps a key's description unless it is given one, and a size table needs a size. `list` writes tab-separated columns with a heading. `missing` exits with 1 when something is missing, as `check` does for problems. All of them use `Sloper.Core.Measurements`.

**Undo and watching.** `TMeasurementDocument` (`src/document`) keeps its own history of the file's text, through the `TTextHistory` it shares with the publish app. A change read from disk clears that history, since an older step would bring back what the file has just replaced. A file seen changing has to read the same on two checks before it is taken in, and a file that does not parse is left alone. Saving over a file that has changed since it was read is refused until the change has been taken in, so a change made elsewhere is never lost. The merge compares each key with the file as last read: a key changed on one side takes that side, and one changed on both asks which to keep, as a whole, including a key deleted on one side.

**The selected size is not saved in the pattern.** The drafting app's size chooser, in the Measurements tab, is for the session; a set opens on its first size.

**Code.** A third Lazarus project, `src/measurements/opensloper_measurements.lpi`, using `src/core` and `src/document`, and BGRABitmap for the body figure once it is added.

## Publish app

Publishing is a separate application, `opensloper-publish`, as KiCad splits schematic and PCB editing: the drafting app designs and edits patterns, and the publish app brings finished pieces from one or more patterns together and prints them.

**Why a separate app.** Information flows one way: the pattern defines the pieces, and publishing only arranges and prints them, so nothing has to be synchronised back. Each app does one job and stays small; the drafting app needs no paper, printer or nesting code, and the publish app needs no snapping or formula editing. Both link the same core and evaluate patterns themselves, with no communication between processes.

**What lives where:**

| Drafting app (pattern file) | Publish app (layout file) |
| --- | --- |
| Draft geometry, formulas, variables | Which patterns and measurement sets to use |
| Pieces: outline, seam allowance, grainline, notches, piece labels, cut count | Placement of each piece copy: position, rotation, flip |
| Pattern-space annotations (notes, callouts) | Sheet-space annotations (title block, sheet notes) |
|  | Paper, margins, overlap, marks, output kind |

Printer calibration is neither: it belongs to the user's printer, so it is a preference (see Preferences).

**One or more patterns from the start.** A layout lists its sources, each a pattern file with a measurement set. Different patterns can share a layout (a skirt and a top cut from the same fabric).

**Keeping in step:**

- The publish app reads saved pattern files and watches them; when one is saved it re-evaluates and redraws, with a status message. Unsaved edits in the drafting app do not appear.
- Placements refer to pieces by source and piece ID, so they survive measurement changes and edits. A new piece appears in an "unplaced" tray; a deleted piece's placement is flagged in the problems list, never silently dropped.
- When pieces grow after a measurement change, overlaps between pieces and pieces running off the sheet are flagged, and Pack Pieces can rearrange them (see Other exports and packing).
- A missing pattern or measurement file, or a piece that fails to evaluate, is shown as a problem. Export refuses while any placed piece is invalid and lists them.

**Moving between the apps.** The drafting app has a Publish… command that opens the publish app with the current pattern, creating a layout for it if there is none, as KiCad's project manager connects its tools.

**Rotation in 90° steps.** Pieces turn by quarter turns only, so the grainline stays square to the sheet; there is no per-piece list of allowed rotations. The grainline is printed on each piece, so a turn on paper does not change how it is cut. On a projector, a material sheet or a layout with a machine profile the piece is cut as it lies, so a quarter turn there is a warning (see Accessories). A flip is there for mirrored copies. A piece cut twice gets two placements, the second mirrored when `cut.mirrored` is set.

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
              "marks": "diamond", "outputProfile": "Home printing" },
  "placements": [
    { "source": 1, "piece": 42, "copy": 1, "x": 120, "y": 40,
      "rotation": 0, "flipped": false }
  ],
  "sheetNotes": [],
  "titleBlock": { "corner": "bottomRight", "fields": ["pattern.name", "measurements.name", "date"] }
}
```

Sources have IDs from the layout's own counter, under the same never-reused rule; `piece` is the piece's ID in that source's pattern file. Placements are plain numbers, not formulas: a layout arranges finished pieces and is not parametric. One layout file holds one arrangement; a differently arranged version (A4 tiles versus one A0 sheet) is another layout file.

**Code.** The publish app is a second Lazarus project, `src/publish/opensloper_publish.lpi` (`opensloper_publish.lpr`, with its window in `src/publish/`), using `src/core` and `src/output`. Layout loading, page tiling and preview drawing live in the output layer, so `opensloper-cli export LAYOUT` produces the same PDFs without a window.

**Implemented so far** (`Sloper.Output.Layout`, `.Tiling`, `.PDFWriter`, `.LayoutPDF`):

- **Commands.** `opensloper-cli layout PATTERN` starts a layout beside the pattern with every copy placed; `opensloper-cli export LAYOUT` writes the PDF, refusing with the list of blocking problems. `-o` names the file written.
- **Layout space** is millimetres from the top left, y down. A placement gives the top left of the piece's cutting line after any rotation and flip (flip first), so it stays put when the piece grows.
- **New pieces** are placed in plain rows up to 1 m wide, 10 mm apart. This is a starting point; Pack Pieces does the packing. Even-numbered copies of a mirrored piece start flipped.
- **Problems.** A missing or unreadable file, a deleted piece, a failing piece and a layout with nothing placed block export, so a blank PDF is never written. Unplaced copies, a pattern with no pieces, overlaps, pieces off the sheet and a rotation that is not a multiple of 90° (only possible in a hand-edited file) are warnings. A source's `size` must be in its measurement file; with none given, a size table uses its first size. The title block names the size.
- **The PDF** starts with a cover page: the test square, the print-at-full-size reminder and the page map. Each tile then shows its caption, the cutting line, a dashed seam line, grainline, fold bracket, notches and the piece's label, with diamonds in the middle of each overlap. Tiles with nothing on them are left out. Calibration (from Preferences) scales everything drawn at true size, including the test square.
- **On the fold.** A piece cut on a fold prints as the half drawn, with its bracket, as on a paper pattern. Material sheets and layouts with a machine profile open it out to a whole piece instead (see Accessories).
- **PDF writer.** `TPDFWriter` is our own, about 200 lines of straight PDF rather than fcl-pdf: scale is exact, output is uncompressed and the same layout gives the same bytes, which tests can compare. It uses the built-in Helvetica, so text outside Latin-1 prints as `?`; a pattern with such names will need an embedded font. Annotations add TrueType embedding for their chosen fonts in their third stage (see Annotations).
- **The window** (`Sloper.Publish.MainForm`, `Sloper.Publish.PreviewCanvas`, with the LCL-free `Sloper.Output.Preview`) is one screen: the pages with the pieces on them, and beside them four tabs (Pieces: turn, flip, pack, the tray; Patterns: the sources; Output: paper settings and the exports; Notes: title block and sheet notes) above an always-visible problems list. It takes a `.slayout`, or a `.sloper` to start a layout for. A page's printable area is drawn white, and grey when blank. Click selects a piece and dragging moves it, on a 0.5 mm grid, as one undo step; Escape cancels. The wheel zooms about the cursor; middle-drag or Space+drag pans.
- **Undo** (`TLayoutDocument`) records the layout's text before each change, as `TPatternDocument` does, and reads the patterns again on undo. A run of paper setting changes merges into one step.
- **Keeping in step.** Once a second the window compares a checksum of each source's pattern and measurement files, since file times only go to the second. A changed file has to read the same on two checks before it is loaded, so a save still in progress is not read. The status bar then says what was read, and new pieces show as unplaced. Reload Patterns reads everything again by hand.
- **Publish…** (File menu, Ctrl/Cmd+P) in the drafting app starts `opensloper-publish`, beside it (as in `release/`), with the pattern's layout (same name, `.slayout`) if there is one and otherwise the pattern. It reads saved files, so an unnamed pattern is saved first and a modified one is offered the choice. Each use starts another window; it does not look for one already open.
- **Leaving pages out.** Right-clicking a page in the preview leaves it out of the print, or puts it back, as one undo step: a plain click selects a piece, and a page is often all piece. It shows grey and crossed, with the piece still over it, and the cover's page map strikes it through. The layout file lists the captions under `excludedPages` in `output`. A change of paper, margin, overlap or output kind clears the list, since the captions then mean other sheets.
- **Large format.** `kind` `large` prints one sheet, `rollWidth` wide (914 mm, 36 in, by default) and as long as the layout needs, with the title, reminder and test square across the top instead of a cover page. Pages and marks do not apply. A piece past the roll's printable width is a warning, and is cut off at the margin.
- **Unplaced tray.** A list in the side panel shows every copy with no placement, including ones a saved pattern has just added. Dragging one onto the pages drops it centred on the cursor and selects it; double-clicking puts it in a new row; Place new pieces takes them all. Delete or Back to tray returns a placed copy. A failing piece waits in the tray and cannot be placed until it works. In the CLI, which has no tray, unplaced copies are still warnings. A copy still placed after its piece's cut count went down prints as before, with a warning.
- **Projector.** `kind` `projector` prints one sheet sized to the layout, white on black, with thick lines and a large label, for showing on fabric. The test square stays at the top, to set the projector by. Calibration applies, and paper, roll and pages do not. Since a projected piece is cut the way it lies, a quarter-turned piece gets a warning here, though not on paper. The window shows the arrangement the usual way; only the PDF is dark.
- **Title block.** `titleBlock` holds `corner` (`bottomRight`, `bottomLeft` or `topRight`), `fields` and `everyPage`. It prints once, on the cover or beside the test square of a one-sheet output, with an optional copy in that corner of every tile, on a white box. The fields so far are `pattern.name`, `measurements.name`, `layout.name`, `date`, `cutlist` and `fabrics`; `pattern.version` and author wait for the pattern to hold them. A new layout starts with pattern, measurements and date. The layout file is left without it when it is off.
- **Sheet notes.** `sheetNotes` lists `text`, `x`, `y` and `size` (points): plain text in layout space, one or more lines, with `{pattern.name}`, `{measurements.name}`, `{layout.name}`, `{date}`, `{page}`, `{pages}`, `{cutlist}` and `{fabrics}` filled in when printed (the cover counts as page 1). A note makes the page it is on print, even with no piece there, and extends the page grid. It prints on every tile it reaches. In the window a note is selected and dragged like a piece, and lies over them; the Notes tab holds the note's text and size and the title block. A note over a piece is a warning. Text width is an estimate, since the PDF uses Helvetica unembedded, so these checks are approximate.
- **Patterns tab.** Lists the layout's sources, with Add pattern and Remove pattern, and for the selected one its measurement file (Choose measurements, or Use the pattern's own) and its size when the file is a size table. A pattern can be added twice, in two sizes. Paths are stored relative to the layout. New pieces wait in the tray. Removing a source removes its placements, and every change here is one undo step. Choosing another measurement file starts on its first size.
- **Marks.** `marks` is `diamond`, `halfCircle` or `none`, set on the Output tab. Each page prints a half circle on its own side of the overlap's middle, flat side out, so that two overlaid sheets make a circle.
- **Output profile** (planned, see Visibility, styles and output under Markings). The Output tab chooses one from the settings, or None for everything. Changing it is one undo step, and the preview follows it.
- **Custom paper.** Choosing Custom on the Output tab opens the width and height fields, and the layout saves `paperWidth` and `paperHeight`, as for any paper name it does not know. A size that cannot print is left alone while it is being typed, since 400 passes through 4, and goes back to the last good one on leaving the field.
- **Piece fill.** `fill` in `output` is `none`, which is left out of the file, `tint`, a light tint of each piece's colour under the lines of paper and large-format PDFs, or `hatch`, grey lines 6 mm apart at each fabric's angle, for black-and-white printers, set on the Output tab. Either choice applies to every piece for that print, whatever its fabric's own fill style, and a piece with no fabric stays unfilled. It does nothing on projector output, which is dark, and not in SVG or DXF. The window's preview always tints pieces, in their fabric's colour.
- **Pattern notes.** A pattern's printing notes print with the pieces they belong to, upright, on every copy (see Annotations), in the window, PDF and SVG, with the same fields as sheet notes. They cannot be selected or moved here; that is done in the drafting app.
- **Alignment and boxes.** Sheet notes can be left, centred or right aligned and put on a white box, from the Notes tab, saved as `align` and `box`; pattern notes bring their own, and callouts their leaders (see Annotations).
- Not done yet: bold, italic and fonts (annotations stage 3); see Annotations.

### Draft export

File → Export Draft SVG… in the drafting app, and `opensloper-cli export-draft PATTERN [--labels] [-m FILE] [-s SIZE] [-o FILE]`, write the draft as a true-scale SVG in millimetres: the construction itself, with its points, construction lines, curves and pieces, for teaching, documentation, review and marking up in Inkscape. It is not for cutting, which the publish app's SVG does from finished pieces and needs a layout; this needs only a draft, even an unfinished one. The drawing is `DraftToSVG`, as `render` uses.

- It matches the screen. In the window it follows View → Piece Fills, takes the pattern as it stands, saved or not, and names exactly what the canvas is naming: everything on All, nothing on None, and on Contextual the selection with its inputs and dependents (`TPatternCanvas.ShownLabelKeys` into `LabelChosen` and `LabelKeys`). Points, edges and pieces are named as on screen, an edge halfway along it. Every object is drawn either way; only the names change.
- The CLI draws with fills on and names everything, points, edges and pieces, only with `--labels`; `render`'s `labels` does the same. Problems are warnings: failing objects draw in their state colours, or are left out if they have never been computed, and the file is still written.
- The suggested file is the pattern's name with `.svg`.

### Other exports and packing

SVG and DXF-AAMA do different jobs: SVG shows pieces where they were placed, for plotters, laser cutters and Inkscape, while DXF-AAMA carries pieces into a CAD or cutting system, which arranges them itself. The machine DXF (see Accessories) follows the arrangement, as SVG does. Packing only writes placements, so the layout file does not change.

**SVG** (`Sloper.Output.LayoutSVG`, built on `TPlacedPiece`). One true-scale file in millimetres at the layout's positions, with each piece's rotation and flip. There is one group per piece copy, with separate cut, seam, marks and label groups inside it, so a cutter can leave out the seam line. Pages, overlap marks, calibration, the title block and sheet notes are left out: calibration corrects one printer, and the rest belong to paper. With no machine profile the file is all black; a profile applies its line types, colours and cut order (see Accessories).

**DXF-AAMA** (`Sloper.Output.LayoutDXF`). One block per piece, not per copy, in the piece's own coordinates, unrotated and with y flipped to point up, as DXF expects. The quantity is the piece's cut count. Only placed pieces are written, so the layout still chooses what goes out. A layout with several sizes gets separate blocks for each source, named with the size; grading rules are out of scope. The file is ASCII DXF R12 from our own small writer, like `TPDFWriter`, so the same layout gives the same bytes. Curves are polylines. A piece on a fold is exported as the half drawn, with the fold as a mirror line.

| Layer | Content |
| --- | --- |
| 1 | Cut line and piece text: name, size, quantity, and `Material:` once the pattern has named its fabrics |
| 14 | Seam line |
| 4 | Notches, as points with angle and length |
| 7 | Grainline |
| 6 | Fold (mirror line) |
| 8 | Marking lines (placement, stitch, fold and cut roles), as lines |
| 13 | Holes and stitch holes, as points at their centres; the format has no place for their size |

The layers are kept in one table so ASTM can be added later. ASTM D6673 is paywalled and listed as withdrawn, so these numbers follow Valentina's GPL exporter, with layer 6 taken from its ASTM export because its AAMA export draws mirror lines on layer 8. Layers 8 and 13 come from published layer lists of CAD systems, not from the standard, so they need the same check on a real system. The file-level text gives the style name, creation date and `Units: METRIC`. The output reads cleanly in `ezdxf`, but the exporter has not been tried on a real cutting system and is assumed to work; a test against one should check the layers and the file-level text. Names outside ASCII are written as they are, since R12 has no way to say UTF-8, and become underscores in block names.

**Pack Pieces**, on the Pieces tab, and `opensloper-cli pack LAYOUT`, which rewrites the file. It is one undo step and writes ordinary placements that can still be dragged. Every copy is packed, including those in the tray; failing pieces stay there.

- **Method.** Bounding boxes, tallest first, each placed as low and as far left as it fits, at 0° and at a quarter turn from where it stands, with flips kept and a 10 mm gap. The same input gives the same result. True-shape nesting is left for later. On a material sheet the quarter turn is only tried when `allowTurns` is set.
- **Tiled.** Each column count is tried, pages are counted with the tiling code, and the fewest pages win.
- **Large format.** Packs to the roll's printable width, for the shortest sheet. A piece too wide either way round is left where it was, with the usual warning.
- **Projector.** Not offered: the layout has no fabric width to pack against. A material sheet is the way to pack to a fabric's width.
- **Material sheet.** Packs to the sheet's width, for the shortest length, and a sheet with a set length is treated as a limit (see Accessories).
- **Only if it helps.** Packing keeps the arrangement it found when that uses fewer pages or a shorter sheet, and says so, since a hand arrangement can beat bounding boxes. New copies stay placed. An arrangement that runs off the roll never counts as better.
- Packing clears `excludedPages`, since the page captions change, and only when pieces moved. Sheet notes stay where they are.

**Commands.** Export SVG and Export DXF sit beside Export PDF on the Output tab and in the File menu, with Export Machine DXF after them. `opensloper-cli export` takes `--format=pdf|svg|dxf|machine-dxf`, or goes by the extension of `-o`, so `.dxf` means DXF-AAMA, and `--profile=NAME` overrides the layout's machine profile. `export` in the Automation API takes a layout path. The problems that block a PDF block these too.

## Fabrics

Pieces are coloured by the fabric they are cut from, so colour carries meaning (main, lining, contrast, interfacing) as well as making pieces easier to tell apart.

**Fabric list.** Each pattern has a list of fabrics, each with an ID, a name, a colour and a fill style (solid tint or hatching). A new pattern starts with one fabric, Main. Fabrics are ordinary objects: adding, renaming, recolouring and deleting are undoable commands, and names follow the name rules.

**Assignment.** Each piece is assigned a fabric and takes its fill from it, with an optional per-piece override of colour or fill style. A piece with no fabric is drawn unfilled and flagged in the problems panel. Deleting a fabric that pieces use is refused, like deleting any object with dependents.

**Display:**

- Fills are semi-transparent and drawn beneath all lines, so seams, notches, labels and overlapping pieces stay readable.
- Only pieces are filled; draft and construction lines stay neutral.
- The default palette stays distinguishable for colour-blind users, and the fabric name appears in the piece label, so colour is never the only cue.
- A display toggle turns fills off.

**Printing.** Fills are off by default, to save ink and keep tracing clean. The print screen offers a light tint or hatching per print; hatching suits black-and-white printers.

**Cut list.** Built from the fabric assignments and each piece's cut settings, grouped by fabric, for example "Main: Front ×1 on fold, Back ×2 · Lining: Front ×1 on fold, Back ×2". Available as the `{cutlist}` live field for the title block or a sheet note. A layout with several patterns joins their cut lists.

**Starting out.** Main has no ID and is not written to the file until the fabric list is first changed, so existing files load as they are and their IDs do not move. The first add, rename, recolour or change of fill gives Main an ID and puts every piece on it. So until then a piece's empty `FabricKey` means Main, and afterwards it means no fabric, which a pattern reaches by choosing None or from a hand-written file. New pieces take the first fabric. Undoing that first change takes the ID back.

**Choices made in building it:**

- A piece's caption and DXF text name its fabric only once the fabrics are explicit, so a pattern that has never touched them keeps its labels. Names follow the name rules, in their own namespace.
- The last fabric cannot be deleted.
- New fabrics are named `Fabric`, `Fabric2` and so on, and take the first palette colour no fabric has.
- A fabric's hatching angle goes by its place in the list (45°, 135°, 0°, 90°, then round again), so hatched fabrics differ on a black-and-white print.
- The display toggle is View → Piece Fills, a setting rather than part of the pattern. It affects the drafting canvas only; the publish window always shows fabric.

**Code.** `Sloper.Core.Fabrics` holds fabrics, colours and `HatchLines`, and `TPattern` answers `FabricOf`, `PieceLook` (the fabric with any override worked out), `PieceCaption`, `CutList` and `FabricNames`, so canvas, exports and garment all ask it. Hatching is plain lines, computed on screen points on the canvas so its spacing holds at any zoom. The UI is `Sloper.UI.FabricsPanel`, a Fabrics tab with the cut list under it, and rows in the piece's properties. The Automation API has `list_fabrics` (with the cut list), `add_fabric`, `rename_fabric`, `set_fabric`, `delete_fabric`, `set_piece_fabric` (a `fabric`, or `none`) and `set_piece_fill` (`color`, `style`); fabrics are named by ID or name.

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
- Optional x/y printer calibration factors for printers that are consistently slightly off, set once in Preferences for the user's printer

**Layout before printing:**

- Choose what to print: selected pieces or all pieces, from one or more patterns, for the current measurement set
- Arrange pieces to minimise pages: manual drag, or Pack Pieces (see Other exports and packing)
- Preview with the page grid over the pieces and a live page count

**Other outputs:**

- Single large-format PDF (A0 or copy-shop width)
- Projector mode: dark background, thick light lines, no tiling, for projecting onto fabric
- SVG and DXF exports (see Other exports and packing), with cut, score, mark, engrave and hole line types for cutting machines (see Accessories)
- Material layouts: a fabric width or a board, one fabric at a time, with leather hides to follow (see Accessories)
- Piece fills: off by default; optional light tint, or hatching later (for black-and-white printers), set per print

**Print screen (the main gap in existing software).** Seamly2D lacked a friendly interface for multi-page printing, so the publish app's main window is one interactive screen rather than a dialog of settings:

- Large live preview: pieces on the page grid, page labels visible, blank pages greyed out
- Pieces dragged on the preview and turned with Turn 90°; page count updates as you move them
- Settings in a side panel (paper, margins, overlap, marks), with the preview updating instantly
- Click a page to include or exclude it, e.g. to reprint one damaged sheet
- Settings saved in the layout file, so reprinting after a measurement change is one click
- One button each for tiled PDF, large-format PDF and projector PDF

Deferred: multi-size (nested) output on one sheet. Historically needed because paper patterns served every size from one print; parametric drafting generates the exact size instead. Add later if the community wants it for publishing patterns for download or print. Printing works on computed geometry, so it only means evaluating the pattern once per size in a size table and drawing the results together; a screen-only size overlay for checking grading can come with it.

## Annotations

Notes, callouts and a title block are first-class objects that print with the pattern, fixing a gap found with Seamly2D, where adding text over the final design was difficult.

| Kind | Lives in | Anchored to | Typical use |
| --- | --- | --- | --- |
| Note | Pattern space | A point, edge or piece, plus an offset; or free | "Ease sleeve cap between notches", "Stay-stitch neckline" |
| Callout | Pattern space | Text box anywhere; leader arrow tip on a point, an edge position or a piece | Pointing at a specific notch, dart or seam |
| Piece label | Pattern space | Its piece | Name, cut count, on fold, size (already part of the piece) |
| Title block | Sheet space | A page corner or the layout | Pattern name, measurement set or size, date, version, author, scale square |
| Sheet note | Sheet space | A position on the printed layout | General instructions, fabric and notions list, assembly order |

**Anchored, so annotations stay parametric.** A note or callout tip stores the anchor's ID and an offset, not absolute coordinates. When measurements change, it moves with the geometry. Deleting its anchor is refused while the note uses it, so nothing is silently lost (see Stage 1 below).

**Live text fields.** Text can include fields filled in at display and print time:

- `{pattern.name}`, `{pattern.version}`, `{measurements.name}`, `{date}`, `{page}`, `{pages}`, `{cutlist}` (cut list grouped by fabric), `{fabrics}` (fabric names)
- Values from the draft, e.g. `Seam length {=Line_A_B.length} mm`, using the formula engine and the same name-to-ID storage, so renames never break a note

**Text and style** (by stage, see Stages below):

- Each annotation has a size in points at true print size, so text prints at a known size whatever the zoom
- Multi-line text from stage 1; left/centre/right alignment and an optional white box, so text stays readable over lines, from stage 2
- Leader arrows with a small set of end styles (arrow, dot, none), with callouts in stage 2
- A font chosen by name from the fonts installed on the computer, with bold and italic, in stage 3; until then every annotation uses one sans-serif font (Helvetica in PDF)

**Visibility:**

- Each annotation is marked print and screen, or screen only (private drafting notes)
- The user can show or hide annotations as a whole
- The print screen offers a title block template (position, which fields to show), placed once per print, with an optional copy on every tiled page

**Editing:** a Text tool and a Callout tool on the canvas; click to place, type in place, drag the box and the arrow tip separately; anchoring is inferred by snapping, like points. Creating, editing and moving annotations are ordinary undoable commands. Annotations can be added at any stage of drafting, not only at the end: a note anchored to an early construction point stays with it as the draft develops, and pattern-space annotations are saved in the pattern file with everything else. Sheet-space annotations (title block, sheet notes) belong to a printed layout, so they are edited in the publish app and saved in the layout file.

**Stages** (decided 2026-11-06, replacing the all-at-once scope of 2026-11-03). Stages 1 and 2 are built; stages 3 and 4 are not.

**Stage 1: anchored notes.** Built 2026-11-06. The to-do list's asks (drawn above the pattern, show and hide, add, edit, delete and move on the canvas, size) are all here.

- **What a note is.** Plain text, one or more lines, anchored to a point, an edge and a position along it (a ratio, as for Along edge), or a piece, plus an offset `dx`, `dy` in the pattern unit; or free, at `x`, `y`. `dx`, `dy`, `x` and `y` are formulas like any other field. `size` is in points; `print` is true for print and screen, false for screen only.
- **Fields.** The document fields sheet notes already fill (`{pattern.name}`, `{measurements.name}`, `{date}`, `{cutlist}`, `{fabrics}`), using the same substitution code; `{page}` and `{pages}` print in layouts. `{=…}` draft values wait for stage 2.
- **In the evaluator.** A note is a node whose input is its anchor, so it is blocked while the anchor fails, drawn faded at its last good place. Deleting an anchor is refused while a note uses it, as for any input; the message names the note, which can be deleted or made free first. (Changed from turning the note free automatically: the refusal is already built and loses nothing.)
- **Text tool** (X). A click places a note; snapping chooses the anchor the way it chooses a point's operation (a point, a place on an edge, inside a piece, or free), and the offset is where the click was. The new note is selected, and its text is typed in the properties panel, which has a multi-line field for it; Enter adds a line and leaving the field commits one undo step. Typing on the canvas itself is left for later.
- **On the canvas.** Notes draw above pieces, edges and points, in one sans-serif font at their true size for the zoom, and are picked first. Dragging a note changes its offset (or `x`, `y` when free) when those are plain numbers, as one undo step, and is refused when they are formulas, as for points. Delete removes it. Selecting a note shows a faint line to its anchor.
- **Show and hide.** View → Annotations shows or hides every note, kept in the pattern's `view` as `hideAnnotations` (left out when shown) and out of undo, like `hiddenRoles`. Screen-only notes never print or export, whatever this setting.
- **Objects panel** lists notes with the first line of their text, under a Notes filter.
- **Output.** Draft SVG follows the screen, with `font-family="Helvetica, Arial, sans-serif"`. In the publish app a note prints with a piece when it is anchored to that piece, to one of the piece's points or edges, or lies inside its cutting line, and follows that piece's placement, rotation and flip (text stays upright when the piece is flipped). Other pattern notes are left out of layouts. PDF uses the built-in Helvetica, so text outside Latin-1 prints as `?`, as for sheet notes. DXF carries no notes.
- **Automation API.** `add_note` takes `text`, `anchor` (`point`; `edge` and `position`; `piece`; or none), `dx`, `dy` or `x`, `y`, `size` and `print`. `set_text` changes a note's text, and also takes `size` and `print`, since nothing else changes them; offsets go through `set_formula`. `render` takes `annotations` (default true). `get_object` adds `text`, `size`, `print`, `anchor` and `anchorId`, and the top left as `x`, `y`.
- **As built.** `TNoteObject` (`Sloper.Core.Note`) is a draft object, named Note, Note2 and so on, so it is renamed, deleted, undone and listed like any other. Its place is the top left of its text: a piece anchor hangs it from the piece's middle, an edge anchor from `position` (a ratio from the edge's start, 0 to 1, invalid outside), and the offset is in mm until Pattern units is built. A note prints with a piece by its top left lying inside the cutting line, as text width is only estimated. Its text box is estimated from Helvetica's average letter width (`Sloper.Core.TextFields`, which also holds the field substitution that sheet notes and pattern notes share), for picking and for placing it upright on a turned or flipped piece, where its middle follows the piece. Make free in the properties turns an anchored note free where it is, so its anchor can then be deleted. The Text tool (X) stays chosen after a click, like the Point tool, and the new note starts with the text "Text", selected in the properties' text field ready to type over. A selected or hovered note gets a light tint behind its text; a screen-only note is drawn lighter, and text under 3 pixels high is a faint bar. A note does not add pages to a print: one placed far outside its piece may land on a page left blank. In layout SVG a piece's notes go in its group as `<g class="notes">`; machine SVG and DXF carry none.
- **Problems.** A note whose anchor fails is listed. A note marked print that falls inside no piece is a warning ("does not print in layouts").

```json
{ "id": 20, "type": "note", "text": "Stay-stitch neckline",
  "anchor": { "edge": 7, "position": "0.5" },
  "dx": "10", "dy": "-15", "size": 10, "print": true }
```

**Stage 2: callouts and draft values.** Built 2026-11-06. Callouts, with the box placed by `dx`, `dy` and the leader tip on the anchor, end styles arrow, dot or none, and the box and tip dragged separately. `{=Line_A_B.length}` fields through the formula engine, stored in ID form so renames never break a note, with the value shown in the pattern unit and its references added to the note's inputs. Alignment and the white box, for notes and sheet notes alike.

- **A callout is a note with a leader.** `leader` is `arrow`, `dot` or `line` (the spec's "none" end style: a bare line), left out of the file for a plain note, so there is one object and one file type. The tip is the anchor's place, so a free note cannot have a leader: adding one is refused, and Make free drops it. The leader leaves the text's frame (its white box when it has one) at the place nearest the tip, and is not drawn when the tip is inside it. An arrow head is 3 mm long at 25° either side and a dot 0.8 mm across its radius, at true size.
- **Callout tool** (A). The first click is what the tip points at, by snapping as for the Text tool, and is refused on nothing; the second is where the text's top left goes. The new callout has an arrow and the text "Text", selected in the properties. A selected callout's tip shows as a hollow handle; dragging it hangs the callout from whatever it is dropped on (a point, a place on an edge, a piece), keeping its text where it is, as one undo step (`SetNoteAnchor`); dropping it on nothing is refused. Dragging the text moves the offset, as for any note. The properties' Leader list turns a plain note into a callout and back.
- **Draft values.** Each `{=…}` becomes a formula field of the note, `value1`, `value2` and so on, so the evaluator gives it the note as an input: a failing value blocks the note (which keeps its last good text), deleting what it reads is refused, a rename shows in its text, and measurements it reads are fetched. The file keeps them inline in the text in stored ID form (`"text": "Hem {={12}.length} mm"`), braces inside counted. The text is typed with names; a value that does not parse, or a `{=` without its `}`, is refused with the reason under the text field, which keeps what was typed. Values show to a tenth, without a unit, so the text says "mm" itself; once Pattern units is built they will show in the pattern's unit. The fields are edited in the text, so the properties show no row of their own for them.
- **Alignment and the box.** `align` (`left`, `centre`, `right`; left out at `left`) places each line within the widest, whose box stays where it was; `box` puts a white box 1 mm wider than the text all round under it. Both are the same for pattern notes and sheet notes, in the drafting app's properties, the publish app's Notes tab, the layout and pattern files, the canvas, the publish window, PDF and SVG. On projector output the box is black, the sheet's colour.
- **Which pieces a callout prints with.** A callout goes with what it points at, so the inside-the-cutting-line test uses its tip rather than its text's top left; its text keeps its place relative to the piece, wherever that falls in the layout.
- **Automation API.** `add_note` and `set_text` take `leader`, `align` and `box`, and text with `{=…}` in names; `set_text` refuses a value that does not parse, changing nothing. `get_object` gives `text` with names, `shownText` with the values, `leader`, `align` and `box`.

**Stage 3: fonts.** A font name, `bold` and `italic` beside `size`. The canvas draws with the chosen font, and SVG names it in `font-family`, so a viewer without it substitutes another. `TPDFWriter` embeds the chosen font's TrueType file, so a print matches the screen: TrueType outlines only at first, with WinAnsi (Latin-1) text; an OpenType (CFF) font, or one not installed, falls back to Helvetica with a warning in the problems list. A PDF grows by the font file's size, and the writer stays deterministic, since the whole file is embedded as it is. The font file is found from its name with FCL's `fpttf` font cache. Sheet notes and piece labels can use the same embedding, which also fixes non-Latin-1 names.

**Stage 4: SVG stamps** (see Planned under Roadmap and open questions).

## Preferences

Built 2026-11-05. Edit → Preferences… (Ctrl/Cmd+,) opens the same dialog in all three apps (`Sloper.UI.Preferences`), on the tab for the app: General in the measurements app, Design in the drafting app, Publish in the publish app. OK saves straight to `settings.json` (`TPreferences` in `Sloper.Core.Settings`); Cancel changes nothing. The other apps read the preferences when they start, so a change shows in an app already open only after it is restarted.

| Tab | Setting | Stored as |
| --- | --- | --- |
| General | Unit: mm, cm or in. The measurements app shows values in it (its Show in box changes the same preference), and the drafting app's rulers, grid and cursor position use it. New patterns will take it as their unit once Pattern units is built; it never changes an existing pattern | `measureUnit` |
| Design | Grid spacing, one per unit, each in that unit's own numbers (default 5 mm, 0.5 cm, ⅛ in), so switching units never turns ⅛ in into 3.175 mm. Major lines every ten steps, or every inch when the step divides one. Zoomed out until lines would be under 10 px apart, the grid steps up through multiples of the spacing (inch fractions double through ¼ and ½ first), so every line still lies on the set spacing (`GridSpacing` in `Sloper.UI.RulerTicks`) | `gridSteps` (`mm`, `cm`, `in`) |
| Publish | Printer calibration across and down, 0.5 to 2. **Work Out Factors** takes the test square's side as measured on a print (10 cm or 4 in, typed in the chosen unit) and sets each factor to `current × expected ÷ measured`, since the square was printed with the current factors (`CorrectedCalibration`) | `calibrationX`, `calibrationY` |

**Calibration is the printer's, not the layout's.** Layout files no longer carry `calibrationX` / `calibrationY`; older files' values are ignored when read and not written back. `TLayout.Calibration` is set from the preferences when a layout is loaded by the publish app, the CLI or the Automation API, like `MachineProfiles`, and is never saved or undone with the layout.

## File locations

OpenSloper follows each platform's conventions and never writes app files into the home folder root, unlike Seamly2D.

| Kind | Examples | Linux (XDG) | Windows | macOS |
| --- | --- | --- | --- | --- |
| Config | Preferences, printer calibration, UI layout (`settings.json`) | `~/.config/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Data | SQLite library, templates, user-added blocks, measurement catalogue, body figure | `~/.local/share/opensloper/` | `%APPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| State | Recent files, window positions, logs | `~/.local/state/opensloper/` | `%LOCALAPPDATA%\OpenSloper\` | `~/Library/Application Support/OpenSloper/` |
| Cache | Thumbnails, preview renders | `~/.cache/opensloper/` | `%LOCALAPPDATA%\OpenSloper\Cache\` | `~/Library/Caches/OpenSloper/` |

The measurement catalogue and body figure ship with the app; a user copy in the data folder would override them only if that is added later.

On Linux, `XDG_*_HOME` environment variables are respected when set.

**User documents** (`.sloper` patterns, `.slm` measurements, `.slayout` layouts) belong to the user, never in hidden folders. The first save defaults to `Documents/OpenSloper/`; after that the last-used folder is remembered.

**Implementation:**

- One `TAppPaths` unit provides `ConfigDir`, `DataDir`, `StateDir`, `CacheDir` and `DefaultDocumentsDir`; no other code builds paths
- App settings live in `settings.json` (`TAppPaths.SettingsFile`, read and written by `Sloper.Core.Settings`). The three apps share the file and run side by side, so every save reads it again first and changes only its own part: the drafting app writes its window arrangement when it closes, and Preferences and the measurements app's unit box write the preferences at once (`SaveUserPreferences`). A missing file is a first run. An unreadable one leaves the defaults; the window arrangement is then written over it without troubling the user, while saving preferences refuses and says why, rather than lose a newer version's file
- File → Open Recent lists the last 10 files each app opened or saved: patterns in the design app, measurement files in the measurements app, layouts in the publish app (a pattern that starts a new layout is not listed; the layout is, once saved). The lists live in `recent-files.json` in the state folder (`TAppPaths.RecentFilesFile`, `Sloper.Core.RecentFiles`), one per app. The apps run side by side, so each change reads the file, changes its own list and writes it straight back, instead of keeping a copy that would overwrite the others'. A missing file is taken off the list when it is chosen, with a message; `Sloper.UI.RecentMenu` builds the submenu for all three apps
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

**App icons.** The SVGs in `resources/` are the masters: Design, Measure and Publish for the three GUI apps, and the API logo for the docs, since the CLI has none. `resources/make-icons.sh` turns each app's SVG into the `.ico` beside its `.lpi` (bitmaps up to 128 px and a PNG at 256 px, because the LCL's resource loader rejects smaller PNG entries). lazbuild puts that file in the program's resources as `MAINICON`, which the LCL uses as the window icon on every platform; each `.ico` is named after its project (`opensloper_design.ico` beside `opensloper_design.lpi`), and the generated files are committed. For Linux desktops, `resources/linux/` has a `.desktop` entry per app, naming its icon (`opensloper-design`, `opensloper-measure`, `opensloper-publish`) and its window class, so a package installs the SVGs as `share/icons/hicolor/scalable/apps/<name>.svg`. A macOS `.icns` for the `.app` bundle is left for packaging.

**Deferred until a community release:** packaging the Qt bindings library, macOS code signing and notarisation, Windows builds and `sqlite3.dll`, and GitHub Actions CI. During personal use, only the portable-code practices above apply.

## Testing

Testing runs throughout development; the LCL-free core means most logic is tested without any UI.

**Tools:**

- FPCUnit with the console test runner (GUI runner optional while developing)
- Separate test project in `tests/`, built with `lazbuild` and run from a single `run-tests.sh`
- Tests built with heaptrc (`-gh`) so unfreed objects are reported

| Area | What the tests check |
| --- | --- |
| Geometry | Intersections, curve length, circle and arc length, offset curves, corner rounding, point-at-length, point-in-polygon, signed area, with a tolerance helper (`AssertPointsNear`, e.g. 0.001 mm) |
| Formula engine | Parsing, precedence, degree-based trig, reference lists, name↔ID round trip, error messages and positions |
| Evaluator | Ordering, dirty propagation, cycle rejection, invalid and blocked states |
| Names and IDs | Name uniqueness, case-insensitivity, reserved words, auto-naming past `Z` (`AA`, `BA`, `AAA`, skipping reserved names), `2` / `3` copy numbering; IDs never reused after delete, undo, save and reload |
| Operations | Each operation against hand-checked cases, plus failure cases (parallel lines, distance past end); between points, repeat (count changes, removed indices), align and distribute rewrite definitions as expected; offset edge (lines, curves, chains of edges, both sides, invalid when the offset collapses) |
| Pieces | Face detection on known drawings, clockwise orientation, seam allowance outlines via Clipper2; automatic marking assignment (single piece, overlapping pieces, none, moved outside after a measurement change), for marking lines and for points and repeats with markers; older hole markings read as markers; coincident edges and the order a click picks objects in |
| Markings | Hidden roles kept out of undo and draft export; output profiles include and leave out roles and marks; machine profile applied after the output profile; `allowance` `none` cuts on the seam line in preview, packing and every export; an unknown profile name blocks export |
| Transforms | Each transform against hand-checked positions, curves and split parts exact, lengths kept by rotate and move, a failing source blocking only its copy, deleting as a group, files |
| View and older files | The view (zoom, centre, piece order, isolated piece) is saved and stays out of undo and the modified flag; files with drafts and layers load onto one canvas with their IDs retired |
| Seams | Side lengths, default direction and flip, ease and tolerance limits, sides spanning pieces, invalid and blocked states, suggestions |
| Annotations | A note follows its anchor when measurements change; a failing anchor blocks it; deleting an anchor is refused; dragging changes plain offsets and refuses formulas; document fields filled; hidden notes kept out of undo and draft export; notes print with the right piece, placed, turned and flipped with it, and screen-only notes never print |
| Storage | Save → load → save produces identical JSON |
| Measurements | Personal sets and size tables, missing values per size, atomic save, merge by key with unsaved edits |
| Undo/redo | Execute then undo restores the exact previous state, including random command sequences |
| Printing | Tile layout maths: page count, overlaps, blank-page skipping |
| Exports and packing | SVG and DXF bytes against stored files, DXF layers and blocks, packing never overlaps, repeats exactly and does not add pages |

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
- `run-tests.sh` also builds the documentation in strict mode, so broken links fail (once the site is set up)
- `run-tests.sh` before each commit, optionally via a git pre-commit hook; the same script becomes the CI step on public release

## Documentation

User documentation is written in Markdown in `docs/` and built into a static site with Zensical, published with GitHub Pages and shipped offline with the apps.

**Tool.** Zensical, the successor to Material for MkDocs from the same team, MIT licensed. It reads `mkdocs.yml`, so the site is configured in one `docs/mkdocs.yml`. Pages stay plain Markdown with only common extensions (admonitions, tables, code blocks), so moving to another generator (MkDocs, mdBook) later means rewriting the navigation, not the pages. Zensical runs at build time only; it is not linked into or shipped with the apps, so its licence places no conditions on OpenSloper.

**Licence.** The manuals are licensed CC BY-SA 4.0, stated in `docs/LICENSE`; code remains GPLv3 or later. The theme's CSS and JavaScript in the built site keep their MIT notice.

**Structure:** one site for all the tools, since they share concepts.

| Section | Contents |
| --- | --- |
| Getting started | Installing; the apps and how files flow between them (measurements → patterns → layouts) |
| Tutorials | Worked projects from start to finish: skirt block, moving a dart, tote bag, leather card wallet |
| Measure | Measurement files, size tables, importing Valentina/Seamly2D files |
| Design | Drafting, operations, transforms, pieces, seams |
| Publish | Layouts, tiled and large-format printing, cutting machine output |
| Reference | Formula syntax and functions, every operation and its fields, file formats, keyboard shortcuts |
| API | `opensloper-cli` commands and the Automation API methods |

Pages are written by task ("Add a size", "Rotate a dart"), not by menu. Each app's section uses that app's icon.

**Kept accurate by generating what can be generated:**

- Tutorial patterns live in `docs/examples/` and their illustrations are drawn with `opensloper-cli render`, so pictures follow the app. A script (`docs/build-images.sh`) rebuilds them; the same patterns also serve as regression patterns.
- Reference pages that come from code (operations and their fields, formula functions, CLI help) are written by the CLI, for example `opensloper-cli doc operations`, so the code is the single source of truth. Generated pages are marked as such and never edited by hand.
- `run-tests.sh` builds the docs in strict mode, so broken links and missing pages fail the build.

**In the apps:**

- F1 and the Help menu open the page for the current tool or dialog, through a small table of help IDs to page paths.
- An offline copy of the built site ships with each app and opens in the browser; the website is the fallback.
- Translation (see Translation) and versioned documentation wait until the community release.

**Folders:** `docs/` is the user documentation (this section); `documents/` stays for internal development notes, including this design document. Developer documentation of the Pascal units (for example with PasDoc) is left until someone else needs to read the code.

as part of the documentation process, Cleanup up the opensloper-design-document.md, after many iterations it is getting too long, summarize and reduce each section.

## Translation

Planned for the community release; nothing is translated yet. Already in place: user-visible text lives in `resourcestring` sections (`check-standards.sh` reports message text that is not), strings are UTF-8 throughout, and names in formulas and files are stable keys and IDs, kept apart from what is shown.

Decision: the standard Free Pascal and Lazarus route, gettext `.po` files, rather than a mechanism of our own, so translators can use common tools (Poedit, Weblate, Crowdin).

**Program text.**

- Each project turns on i18n in its `.lpi`, writing to a shared `data/languages/` folder, since translations are read at run time. The compiler puts the resourcestrings in `.rsj` files and Lazarus gathers them into one template per app (`opensloper-design.pot`, `opensloper-measurements.pot`, `opensloper-publish.pot`, `opensloper-cli.pot`). Translations sit beside them as `opensloper-design.de.po` and so on.
- The GUI apps add `LCLTranslator` and call `SetDefaultLang` at start-up, which also translates the captions in `.lfm` forms. The language comes from a new General preference, `language`; with none set, from `--lang` on the command line, then the system locale (`LANG`), then English.
- `src/core` and the CLI cannot use `LCLTranslator`. They use `TranslateResourceStrings` from LazUtils' `Translations` unit, which needs no LCL, so the layering rule holds.
- `data/languages/` is found through `TAppPaths`, so installed and development builds both work.

**Measurement catalogue.** The catalogue's `name`, `description` and `howTo` are data, not resourcestrings. A script extracts them into `measurement-catalogue.pot`, with each message's context set to the measurement key, and `Sloper.Core.Catalogue` looks up the translation when it loads. Translators then have one tool and one workflow; a translated copy of the JSON per language would fall behind without anyone noticing.

**What is never translated.**

- **Formulas:** measurement keys (`@waist`), variable and object names, function names, and the `.` decimal point. A decimal comma would clash with the comma between function arguments, and a pattern must mean the same in every language. Only the display names and descriptions shown beside keys are translated. (Valentina translates its formula vocabulary, which ties its files and formulas to translation tables; we avoid that.)
- **Files:** every saved key and value stays as it is; a file written in one language opens unchanged in another.
- **Automation API:** method names, field names and error codes stay English, since scripts depend on them. Error messages may be translated; scripts should check codes, not message text.
- **CLI output meant for scripts:** column headings of `measurements list`, `check` and other machine-read output stay English. Help text and error messages are translated.

**Exported text.** Text printed on outputs, such as title block labels and piece labels, follows a language chosen in the output profile (see Visibility, styles and output under Markings), falling back to the app's language. A pattern is often printed for someone who reads another language than the person who drafted it.

**Rules for code, from now on**, so later translation needs no rewriting:

- Build messages with `Format` and placeholders (`'%s is not in the measurement set'`), never by joining pieces, since word order differs between languages.
- Give each sentence its own resourcestring, including singular and plural forms; never build plurals or sentences from fragments.
- Leave room for longer text (German runs about 30% longer than English): anchored or autosized controls, not fixed widths sized to the English.
- Keep units, numbers and dates out of the resourcestring itself; pass them in as formatted values.

**Documentation.** Translating the manuals waits with versioned documentation (see Documentation) and follows what Zensical supports.

**Tests.** A test loads a sample `.po` for a test language and checks a translated resourcestring and catalogue entry, and that formulas, saved files and API error codes are unchanged by the language.

## Repository layout

The repo mirrors the architecture layers. All Pascal source, including the three GUI apps, the CLI and third-party code isolated under `src/packages/`, lives in `src/`.

```text
opensloper/
├── LICENSE                 GPLv3 full text
├── README.md               what it is, status, build steps, submodule init
├── .gitignore              lib/, backup/, *.ppu, *.o, *.compiled, *.lps, release/
├── .gitmodules
├── run-tests.sh            submodule init, lazbuild tests, run test binary, leak check
├── build.sh                build GUI apps and CLI; local toolchain in build.local.sh
├── release/                built programs: opensloper-design, -publish, -measurements, -cli (ignored by git)
├── src/
│   ├── design/             opensloper-design: the main drafting app (.lpi / .lpr)
│   ├── measurements/       opensloper-measurements: measurement files and size tables, using core
│   ├── publish/            opensloper-publish: layouts and printing, using core + output
│   ├── cli/                opensloper-cli (export, check, serve) using core + ConsoleTools
│   ├── core/               geometry, expressions, model, evaluator, storage (no LCL)
│   │   └── clipper2/       osclipper2.lpk, builds Clipper2 from the submodule
│   ├── document/           TPatternDocument, undo/redo commands, notifications
│   ├── ui/                 forms, canvas, tools, snapping, panels
│   ├── output/             layouts, tiling, PDF, SVG, DXF, Blender exporters
│   ├── api/                Automation API: JSON-RPC 2.0 over the document layer
│   └── packages/           git submodules, pinned commits
│       ├── clipper2/
│       ├── bgrabitmap/
│       └── console-tools/
├── data/                   measurement catalogue, body figures, icons and (planned) translations, read at run time
├── resources/              branding: app icons and the API logo (SVG), for builds, docs and other resources
├── tests/                  FPCUnit test project, regression patterns and expected JSON
├── documents/              internal development: design document, known issues, Claude notes
└── docs/                   user manuals (Zensical: mkdocs.yml, examples/, LICENSE); published with GitHub Pages
```

`.gitignore` for Lazarus: `lib/`, `backup/`, `*.ppu`, `*.o`, `*.compiled`, `*.lps` (per-user session files), `*.res` if generated, and `release/`, where every project writes its program (`opensloper-design`, `opensloper-publish`, `opensloper-measurements`, `opensloper-cli`). The programs sit side by side there, so each app finds the others beside it and `data/` one folder up.

## Dependencies

Third-party and personal Pascal libraries are git submodules under `src/packages/`, pinned to known-good commits.

| Package | Path | Use | Licence |
| --- | --- | --- | --- |
| Clipper2 | `src/packages/clipper2` | Seam allowance offsetting and polygon booleans; from the fork [github.com/billbsing/Clipper2](https://github.com/billbsing/Clipper2), which carries our fixes | Boost |
| BGRABitmap | `src/packages/bgrabitmap` | Antialiased canvas drawing, SVG | Modified LGPL |
| ConsoleTools | `src/packages/console-tools` | Argument parsing and coloured, word-wrapped help for command-line tools | MIT |

**Submodule practice:**

- Each package is added to the project search path or as a `.lpk` dependency
- Updates are deliberate: a submodule bump is its own commit
- Clipper2 comes from our fork of the original AngusJohnson/Clipper2, which carries our fixes (see `documents/known-issues.md`). That repo was archived in October 2026; development moved to PolyClipping/Clipper2, which is becoming C++ only, so the fork stays on the original. When we need to change Clipper2's behaviour, it becomes our own Pascal-only Clipper2 (Boost licence, keeping Angus Johnson's notices)
- README and `run-tests.sh` include `git submodule update --init --recursive`, so builds never run with missing packages
- Every package must be GPLv3-compatible and carry an explicit licence file

**Command-line tools** (using the LCL-free core and ConsoleTools):

- `opensloper-cli export LAYOUT [--format=pdf|svg|dxf|machine-dxf] [--profile=NAME] [-o FILE]`: regenerate a layout's output after patterns or measurements change
- `opensloper-cli export-draft PATTERN [--labels] [-m FILE] [-s SIZE] [-o FILE]`: write the draft as SVG (see Draft export)
- `opensloper-cli pack LAYOUT`: pack a layout's pieces and rewrite the file; exits with 1 when it refuses or nothing improves
- `opensloper-cli check PATTERN [-m FILE] [-s SIZE] [--json]`: evaluate a pattern and report invalid objects, gaps and seam mismatches, usable in tests and CI. Implemented so far: errors, invalid objects and seam mismatches, one line each, with a count of the objects they block; `--json` prints the full report used by the regression tests. Without `-m` it uses the pattern's `measurementFile` and `size`. Exit codes: 0 no problems, 1 problems, 2 usage or file error
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

**Implemented so far** (`Sloper.API.Server`, `opensloper-cli serve`): `open`, `save`, `get_measurements`, `set_measurement`, `list_objects`, `get_object`, `set_formula`, `rename`, `delete`, `evaluate`, `check`, `undo`, `redo`, `render`, `add_point`, `add_edge`, `split_edge`, `add_rectangle`, `round_corner`, `add_variable`, `create_piece`, `set_edge_allowance`, `set_grainline`, `add_notch`, `remove_notch`, `add_marking`, `remove_marking`, `set_role`, `set_marker`, `set_cut`, `set_fold`, `convert_edge`, `merge_points`, `break_point`, the fabric methods (see Fabrics), `add_transform`, `add_seam`, `flip_seam`, `suggest_seams`, `add_note`, `set_text`, `export` and `convert_units`. Objects are named by `id` or `name`, and variables work the same way (`set_formula` with field `formula`). `add_point` and `add_edge` take a `type`, including `circleCirclePoint`, `circle` and `arc`, and fields as in a pattern file, formulas as text or plain numbers and inputs by ID or name, so a whole pattern can be built through the API; `split_edge` and `add_variable` were added to the table's methods because every operation needs a way in. `list_objects` returns variables and objects. `evaluate` recomputes and returns the problems; `check` adds the full report. `render` returns the draft as SVG text in its reply, with optional `labels` and a `region` (`minX`, `minY`, `maxX`, `maxY` in model mm); the SVG is drawn by `Sloper.Output.DraftSVG`, with true Bézier curves and failing objects in the colour of their state. PNG is not available yet, because the CLI has no LCL and so no canvas to draw it with. Batches of requests are not supported. Still to come: the GUI's `--automation` mode. `export` reads the saved layout and pattern files, as the publish app does, so a pattern has to be saved first.

- `opensloper-cli serve` runs the core and document layers with no window, speaking JSON-RPC 2.0 over stdin/stdout, one message per line.
- The GUI app accepts the same API when started with `--automation`, listening on a local socket, so a test can drive the running app and read its UI state (selection, visible labels, canvas snapshot) instead of using xdotool.

| Method | Purpose |
| --- | --- |
| `open`, `save` | Load or save a pattern, optionally with a measurement file and size; the reply gives the pattern's `units` |
| `convert_units` | Convert the pattern to `units` (`mm`, `cm` or `in`), rewriting only lengths, as one undo step. While a number's role is open nothing changes and the reply lists it (`id`, `name`, `field`, `token`, `number`, the shown `formula` and the number's `position` in it); the caller marks each in `marks` (`id` or `name`, `field`, `token`, `role`: `length` or `number`) and calls again |
| `get_measurements`, `set_measurement`, `missing_measurements` | Read the current measurement set and its sizes, add or change one value, optionally in a given `size`, or list what the pattern needs that the set lacks |
| `list_objects`, `get_object` | Names, IDs, operations, formulas (display form), computed values and state |
| `add_point`, `add_edge`, `split_edge`, `add_variable`, `add_repeat` | Create objects with an operation and formula fields; a repeat's points are named like `Btn[3]` wherever a point is wanted |
| `set_formula`, `rename`, `delete` | Edit existing objects |
| `add_transform` | Rotate, mirror or move `sources` as copies |
| `arrange` | Align or distribute points; points a formula drives are left and listed unless named in `replace` |
| `create_piece` | Detect and create a piece from a position inside a region (`x`, `y`, optional `name` and `allowance`, default 10 mm) |
| `set_edge_allowance` | Give one edge of a piece its own seam allowance, or clear it |
| `set_grainline` | Set a piece's grainline: `angle`, `start` and `end` points, or `none` |
| `set_cut`, `set_fold` | Set a piece's cut `count` and `mirrored`; set its fold `edge`, or `none` |
| `convert_edge` | Change an edge `to` a `line` or a `curve` in place, keeping its ID |
| `merge_points` | Merge two or more `points` into one (see Merging points); returns the point kept |
| `break_point` | Break a point into one for each edge meeting there (see Breaking a point); returns the `points` |
| `list_fabrics`, `add_fabric`, `rename_fabric`, `set_fabric`, `delete_fabric` | The fabric list and the cut list; add, rename, recolour, change fill or delete a fabric |
| `set_piece_fabric`, `set_piece_fill` | Assign a piece's `fabric`, or `none`; set its own `color` and `style` |
| `add_rectangle`, `round_corner` | Add a rectangle from a `corner`; round the corner between two edges |
| `add_marking`, `remove_marking` | Attach a marked point or a marking line to a piece, or add stitch holes; remove one by number from 1 |
| `set_role` | Change an edge's role; a marking role puts it on the pieces it lies in, listed in the reply |
| `set_marker` | Give a point or repeat a `marker` and optional `size`; it joins the pieces it lies in, listed in the reply |
| `add_notch`, `remove_notch` | Add a notch on a `point` or at an `edge` and `position`; remove one by number from 1 |
| `add_seam`, `flip_seam`, `suggest_seams` | Add a seam from `sideA` and `sideB`, with optional `ease` and `tolerance`; flip its direction; list likely pairs without storing them |
| `add_note`, `set_text` | Add a note or callout, anchored or free (see Annotations); change its text, size, printing, leader, alignment or box |
| `evaluate`, `check` | Recompute; return the problems list (invalid, blocked, gaps, seam mismatches) |
| `undo`, `redo` | Step through history |
| `render` | PNG or SVG of the draft or a piece, with options for labels, a region and `hiddenRoles` |
| `export` | A layout file as PDF, SVG, DXF or machine DXF to a given path; `format` and `profile` are optional |
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

## Garment view

Taken out on 2026-11-03, with drafts and layers, to reduce clutter (see One canvas). It was a read-only window (View → Garment View) showing the finished garment flat, front and back side by side: each piece had a `view` (`none`, `front`, `back` or `both`), and pieces in a view were joined along their seams, moved and rotated but never bent, then mirrored across a fold or a centre seam. It had an SVG export, `set_view` and `render` with `garment` in the Automation API. The code is in the git history before that date. A file that still gives a piece a `view` loads, and the member is dropped on saving. Seeing the finished garment is left to the Blender export.

## Accessories

OpenSloper drafts accessories in fabric and leather (bags, pouches, wallets, hats, belts) as well as garments, using the same parametric core; the additions below are useful for garments too.

**What already works:**

- **Product dimensions instead of body measurements.** A bag is driven by `#width`, `#height`, `#depth` and `#strap_length`, plain variables, so a pattern needs no measurement file. A range of sizes (small, medium, large) is a size table of dimensions, read as `@width` and so on; nothing in the measurement format assumes a body. Hats and gloves use body measurements (`@head`) as garments do.
- **Matching lengths.** A gusset's length is a formula reading the panel edge it is sewn to (`Curve_A_B.length`), and seams check that they match.
- **Repeated panels.** One panel of a six-panel cap is drafted and rotated into copies.

**Circles and arcs.** Round bases, hat crowns and brims, and rounded corners need exact circles, which give exact lengths for the gussets sewn to them. Circle and arc edges are therefore brought forward from phase two (see Operation set):

| Operation | Fields | Covers |
| --- | --- | --- |
| Circle | `centre`, `radius` | Round bag bases, hat crowns, cylinder ends; a closed edge that can be a piece on its own |
| Arc | `centre`, `radius`, `angle1`, `angle2` | Brims, curved flaps, rounded corners |

Both are stored as cubic segments like every other edge, at most 45° each, so lengths, positions along them, splitting and crossings work unchanged; `.length` is computed from the exact formula, and `.radius` can be read too. Circle × circle intersection comes with them (see Operation set).

- **Direction.** A circle starts at 0° and runs anticlockwise. An arc runs from `angle1` to `angle2`, anticlockwise when `angle2` is the greater and clockwise when it is the lesser, so 350° to 370° crosses 0°. Two equal angles, or a full turn or more, are invalid.
- **Ends.** The centre is the only point input, so a circle or arc is named after it (`Circle_O`). Its ends are not point objects: to join a line to an arc, put an Along edge point on its end, at length 0 from the start or the end, and the line follows the arc as it changes.
- **As a piece.** A piece needs at least two edges, or one that closes on itself. Clicking inside a circle nothing crosses makes a one-edge piece, unless a smaller region around the click is there. A circle crossed by another edge has to be split at the crossings, as for any edge.
- **From the app.** The Circle tool (O) takes two clicks, as a line does: the first snaps to a point or makes one for the centre, and the second, on the rim, sets the radius, rounded to 0.1 mm, with a dashed preview between them and the radius in the status bar. The centre and the circle are one undo step, and the tool stays on for the next (built 2026-11-06). For an arc, select a point, then Tools → Arc; it starts with a 50 mm radius. Both take the role chosen in Draw As and are selected, ready for their values to be typed.

**Rectangle.** Most bag and pouch pieces start as rectangles. The Rectangle tool (R) takes two clicks: the first snaps to a point or makes one for a corner, and the second sets the opposite corner, with the width and height rounded to 0.1 mm and shown in the status bar as the pointer moves (built 2026-11-06). It adds three offset points and four lines from `width` and `height` formulas, in the role chosen in Draw As, as one undo step with the first corner, and selects the four lines. The second corner may be on any side, so the width and height may be negative. A click too close to the first, under 0.1 mm across either way (or for a circle's radius), is refused. In the formulas the first corner is the start: the width is on the point across from it and the height on the point below it, and the fourth point reads the height from there, so each is in one place. It is a convenience only: the result is ordinary points and lines. `add_rectangle` in the Automation API takes `corner`, `width`, `height` and `role`.

**Rounded corners.** A Round corner operation replaces the corner where two edges meet with an arc of a formula radius, trimming both edges to its tangent points. It produces a new arc and two trimmed edges that follow the originals, as Split edge does. Select the two edges, then Tools → Edge → Round Corner, or `round_corner` with `edgeA`, `edgeB` and `radius`.

- The arc is a `cornerArc`, the tangent points are two `cornerPoint`s, and each edge is split there with ordinary split parts. The part away from the corner stays an outline; the part at the corner and the original edge become construction, so the sharp corner stays as a guide and piece detection follows the arc.
- Only corners between straight edges that share a point can be rounded. Curves need a tangent found numerically and are left for later.
- An edge that is already part of a piece is refused, as a piece keeps the edges it was made from.
- To round all the corners of a rectangle, use what is left of each edge for the next corner.

**Offset edge.** A parallel copy of an edge, or of a run of edges, at a formula distance, to the left or right of its direction, or inside or outside a piece (see Offset edge under Markings). Needed for stitch lines, facings, linings, hems, turn-backs and leather edge allowances. Unlike seam allowance, which only applies to a finished piece outline, it is an ordinary parametric edge that other operations can use. Select an edge, then Tools → Offset → Edge Left or Edge Right; it starts as construction, 10 mm away. `add_edge` takes `offsetEdge`. A line stays exact, and a curve is followed with eight cubics each, to about a hundredth of a millimetre. Its ends are not points, as for an arc, and an offset tighter than a curve's radius is invalid.

| Operation | Fields | Covers |
| --- | --- | --- |
| Offset edge | `edges[]`, `distance`, `side` (left/right), `role` | Stitch lines, facings, linings, turned edges |

**Markings inside a piece.** Notches mark only the edge. A piece also has internal markings, drawn from points and edges of the draft and printed with the piece, so they follow measurement changes:

| Marking | From | Use |
| --- | --- | --- |
| Hole | A point or repeat with the Hole marker and its size (see Point markers) | Rivets, snaps, magnetic clasps, eyelets, buttonholes' ends |
| Marking line | An edge with a marking role (placement, stitch, fold, cut), assigned automatically (see Markings) | Pocket, strap, handle and zip positions; quilting and topstitching lines; folds in leather and stiffened pieces; pleat lines; slits |
| Stitch holes | An edge (usually an Offset edge), with spacing and hole size | Hand-stitching holes for leather, spaced evenly along the edge |

Stitch hole spacing is a formula, and holes are spaced evenly between the ends with the spacing adjusted to fit, so they stay even when the size changes. The piece reports the hole count, which is also useful for working out thread length: `.holes` counts stitch holes only, and `get_object` gives it too.

- **Fields.** Stitch holes' formulas go by place in the list, like notches: `marking2.spacing` and `marking2.size`, and removing a marking renumbers the later ones. A hole's size is the point's `markerSize`.
- **Checks.** A hole must lie inside the piece's cutting line, and sizes and spacing must be above 0, or the piece is invalid. Lines are not checked, since a line may run past the edge on purpose. A marking's point or edge is an input of the piece, so it cannot be deleted while marked.
- **From the app.** Marking lines come from the edge's role and holes from the point's marker (see Markings): Tools → Markings → Mark Hole makes the selected points holes, 4 mm across, and they join the pieces they lie in. For stitch holes, select a piece and an edge, then Tools → Markings → Mark Stitch Holes; they start 4 mm apart with 1 mm holes, typed in the piece's properties. Tools → Markings → Remove Marking takes off what is on the selected point or edge. In the API, `set_marker` marks a point, `add_marking` takes `kind` (`point`, `line` or `stitch`, and `hole` as before), `point` or `edge` and the values, and `remove_marking` takes `marking`, numbered from 1.
- **Output.** Markings draw on the canvas, in draft SVG and in the publish app's PDF and SVG with the piece's other marks. DXF-AAMA writes them on layers 8 and 13 (see Other exports and packing), and with a machine profile each takes its line type (see Cutting machines below).

**Material per piece.** A piece's material is its fabric (see Fabrics): leather, foam, stiffener and interfacing go in the fabric list beside main and lining, so there is no separate material on a piece. Leather pieces are often cut with no seam allowance; per-edge allowance already allows `0`, and a fabric can set a default allowance for pieces that use it. A fabric's `allowance` is set on the Fabrics tab or with `set_fabric`. A piece takes it when it goes on that fabric, or when it is made on the first fabric, and it does not follow later changes, so a piece can still be set by hand. The publish app can lay out one fabric at a time (see below).

**Cutting machines.** Laser cutters, plotters and cutting machines (such as Cricut) read SVG and DXF and treat line types differently, so exports keep them apart:

| Line type | What | Usual colour in SVG |
| --- | --- | --- |
| Cut | Piece outline (cutting line) and cut-role lines (slits) | Red |
| Score or fold | Fold-role lines | Blue |
| Mark | Placement and stitch lines, seam lines, notches, grainlines, fold brackets | Black |
| Engrave | Labels and text | Green |
| Hole | Holes and stitch holes, cut as small circles | Red |

- **Machine profiles.** Each line type has its colour, layer name, stroke width and an on/off switch, so it can cut outlines only, or use the hairline some lasers need. Profiles describe a machine, not a pattern, so they live in the app settings, which the CLI reads too. There is a built-in `Standard` profile with the colours above.
- **In a layout.** `profile` in `output` holds only a profile's name. A layout without one writes the plain SVG it always has. A name not in the settings is a blocking problem for that export, never a quiet fallback, since the wrong colours would cut the wrong lines.
- **Cut order.** Files go score, mark, engrave, holes, then cut, because software that follows file order would otherwise free a piece before its holes are cut, and it can shift.
- **Holes.** Holes and stitch holes are true circles with a centre and diameter: `<circle>` in SVG and `CIRCLE` in DXF, not short segments.
- **Machine DXF.** Pieces where they were placed, y up, one entity set per copy, on the profile's layer names. It shares a writer with DXF-AAMA, which keeps its own fixed layers and block per piece (see Other exports and packing). It uses `Standard` if the layout has no profile.
- **Text.** Labels are `<text>` in SVG and `TEXT` in DXF, so they depend on the machine software's fonts. A single-stroke font, which lasers engrave best, waits for a test on a real machine.

**Cut as it lies.** On a material sheet, or in a layout with a machine profile, nothing is left to read the printed grainline before cutting, so two things change:

- **Quarter turns.** A quarter-turned piece gets the same warning as on a projector. A material sheet's packing does not try quarter turns unless its `allowTurns` is set, for a material with no grain such as foam or board.
- **Fold pieces.** A piece on a fold is opened out to the whole piece, mirrored across its fold line with its seam line, marks and holes, and the fold shows as a Mark. A hole marking on the fold line makes the piece invalid, as it would have no other half, and stitch holes running along the fold are written once. The preview, overlap checks, packing and every export of that layout use the whole piece, so they agree, and a placement gives the top left of the opened-out cutting line. DXF-AAMA still writes the half with its mirror line.

**Laying out on material.** Besides paper tiles, a layout in the publish app can be a material sheet, `kind` `material`: a fabric width, or a foam or card board. `materialWidth` is its width and `materialLength` its length, left out for a roll. A piece past the width or a set length is a warning. A PDF prints it as one sheet of that width, as large format does. The sheet's use is reported as the length used on a roll, and otherwise as the area of the pieces against the sheet's.

**One fabric.** `fabric` in `output` limits a layout to one fabric, of any kind, so each fabric gets its own cutting layout. It holds the fabric's name, because fabric IDs belong to each pattern and a layout can have several, and names match as usual, ignoring case. Pieces on other fabrics leave the tray, Place new pieces, packing, checks and exports. Their placements stay in the file, so clearing the filter brings them back. A name found in no source is a warning.

**Leather hides** come after these, as a step of their own: a hide's outline drawn by hand, with flaws marked as areas to avoid, and then traced over a photo in the publish window. Bounding boxes cannot honour an irregular outline, so packing onto a hide needs true shapes, and until then pieces are placed by hand and checked against the outline.

**Not included.** Fashion drawing (illustration, colours, prints) is left to tools such as Inkscape and Krita; a pattern can keep a reference image. Hardware sizes (rings, buckles, zips) are entered as variables, not a catalogue; the Notions library in Future ideas would change that.

## 3D preview (later phase)

3D draping is deferred and will use Blender's cloth simulation rather than a built-in simulator.

Writing a cloth simulator (triangulation, sewing constraints, body and self-collision, a parametric avatar) is a multi-year effort in commercial tools, so the app only exports what Blender needs:

- Triangulated piece meshes (OBJ)
- A JSON or Python file with seam pairs, piece placement around the body and fabric hints
- A Blender Python script that places pieces, creates sewing springs and runs the simulation in one step

The only requirement now is the **seam** concept in the core model, which also drives 2D seam-length checks. Any 3D module stays separate and reads computed geometry only.

## Future ideas

Ideas worth keeping that are deliberately outside the roadmap. Each is added only when the core is solid, or when the community asks for it.

| Idea | Notes |
| --- | --- |
| Notions library | A catalogue of haberdashery (zips, buttons, hooks and eyes, snaps, eyelets, elastic), placed on a pattern like KiCad footprints: markings on the seam (zip stops, button and buttonhole positions via Repeat), rules (buttonhole = button diameter + thickness; warn if a zip is longer than its opening), and an automatic notions list for the title block via live fields |
| Multi-size output | Nested sizes on one sheet for publishing patterns; see Printing |
| Size overlay | Screen-only overlay of several sizes for checking grading |
| Scaled body figure | Measurement editor figure scaled to the entered values |
| ISO 8559-1 check | Check catalogue definitions against the standard and add clause references, if the project gains traction |
| Spread tool | Generates the chain of rotations for slash and spread in one step; see Transforms |
| Fabric textures and properties | Image textures (e.g. a photo of the actual fabric) for fills and the Blender export; fabric width and nap direction for automatic layout |

## Roadmap and open questions

Save/load and undo come before the canvas, so the canvas is built on document commands from the start and saved patterns can serve as regression tests. The app becomes personally useful at step 9; community release follows if it proves easy to use.

1. Geometry core unit (points, lines, Béziers, intersections) with unit tests, no UI
2. Measurement sets, variables and the formula engine
3. Dependency graph and evaluator (dirty propagation, invalid states, cycle detection)
4. JSON save/load and undo/redo commands (done)
5. Canvas with pan/zoom and the six point operations, snap-inferred (done)
6. Align and distribute, repeat along edge (done)
7. Automation API, phase 1: `opensloper-cli serve` (JSON-RPC over stdio) with `open`, `list_objects`, `set_formula`, `evaluate`, `check` and `render` (done, render as SVG)
8. Pieces: automatic detection, seam allowance via Clipper2, grainlines, notches, fabric assignment and fills (done for now, see Fabrics; Shift-click merging, the start-edge fallback and custom piece labels remain)
9. Publish app: layout files with one or more patterns, true-scale tiled PDF printing (built, see Publish app; a real print and the Publish… save prompt are still to be tried by hand, see `items-todo.md`)
10. Measurements app (done, with 72 measurements in the catalogue so far): measurement and size table editing; measurement editor with catalogue and body figure; import and export Valentina/Seamly2D measurement files
11. Seams and seam-length checks (done, see Seams; the Check pattern overlay itself is not built yet, so a mismatch shows in the status bar, the Problems filter and `check`): seam object, Seam tool, Suggest seams, split command on the canvas
12. SVG piece export and DXF-AAMA export, automatic packing in the publish app (done, see Other exports and packing; DXF untried on a real cutting system)
13. Garment view: a flat front and back of the finished garment in the drafting app (done, then taken out; see Garment view)
14. Layers and draft tabs (done, then taken out to keep to one canvas; see One canvas)
15. Transforms: move, rotate and mirror as parametric copies (done, see Transforms; the ghost preview is left for later)
16. Accessories: circles and arcs, rectangle tool, rounded corners, offset edges, internal markings, a default allowance per fabric (done, see Accessories; rounding curved corners is left for later)
17. Cutting machine output (line types, profiles, machine DXF, opened-out fold pieces) and material sheets (fabric widths and boards, one fabric at a time) (done, see Accessories; untried on a real machine, and profiles are edited in the settings file, as there is no window for them yet)
18. Leather hides: outlines drawn or traced from a photo, flaws, placing and packing on true shapes
19. Blender export for 3D preview


### Planned

Further work agreed but not yet designed in detail or placed in the numbered steps above.

- **Locking an object.** A locked object cannot be moved, edited or deleted, but its formulas still run, so it keeps following the values they read. This brings back locking per object, after layers were taken out (see One canvas).
- **Annotations in stages.** Stage 1, anchored notes, and stage 2, callouts and draft values, are built; fonts and SVG stamps follow (see Annotations).
- **SVG stamps.** An SVG drawn in another app (a logo, a fold or assembly diagram) placed on the canvas and anchored like a note, by ID plus offset, so it moves with the geometry. Paths only: `<text>` is refused with a message asking for it to be converted to paths, which keeps fonts out of it. Drawn at true size from the SVG's own mm units (a file in px is taken at 96 px per inch, with a warning), with BGRASVG on the canvas and our own path translation in `TPDFWriter`. Prints with a piece by the same rules as notes, and is stored in the pattern file as the SVG's path data, so the pattern does not depend on the outside file.
- **Linked copies on the canvas.** The diamond marker, link line, refused-drag message and Go to Source for transform copies (see Copies under Drafting experience).
- **Isolate piece and piece stacking order.** View options for overlapping pieces (see Drafting experience).
- **Separate Piece command.** One undoable command for steps 2 to 4 of separating front and back (see Transforms): pick a region, Move Copy it aside, make the leftover back-only edges construction and make the piece. Added only if the manual steps prove tedious.
- **Claude integration.** Building on Automation API phase 2: the Claude API key is stored in Preferences so Claude can reach the app. Open question: how Claude tells the user about the changes it makes to the design, and whether the API needs to report which objects are selected so Claude can work on them.
- **Fabric needed.** Estimate from the design the fabric it needs: the area in square millimetres and the minimum width and length. Given the width of the supplier's fabric, work out the actual length to buy, and warn when the design is too big to cut from a single piece of fabric.
- **G-code export.** Export the pattern as a G-code file for CNC machines, from the publish app.
- **Translation.** gettext `.po` files for the apps, the CLI and the measurement catalogue, a language preference, and a language per output profile (see Translation).
- **Role styles in Preferences.** Overriding a role's colour, dash and weight on screen (see Styles under Visibility, styles and output). Role visibility, presets, the leather roles and output profiles were built 2026-11-06.

**Open question:** whether `pieceOrder` should list every piece or only those moved, and what happens to a piece left out when another is brought to front.
