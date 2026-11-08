# Automation API

!!! note

    This page is generated from the program by `opensloper-cli doc api`; do not edit it by hand.

`opensloper-cli serve` lets a script or an assistant such as Claude drive a pattern. It reads JSON-RPC 2.0 requests on standard input, one a line, and answers each on a line of standard output. Every change goes through the pattern's undo history, as an edit in the window does.

For example:

```
--> {"jsonrpc": "2.0", "id": 1, "method": "set_formula", "params": {"name": "B", "field": "length", "formula": "@waist / 4 + #ease"}}
<-- {"jsonrpc": "2.0", "id": 1, "result": {"id": 3, "name": "B", "type": "offsetPoint", ...}}
```

## Errors

A refused call answers with a JSON-RPC error. Its `data` names the `field` at fault and the `position` of the problem in a formula, when there is one. Check the code, not the message, which may be translated.

| Code | Meaning |
| --- | --- |
| -32700 | The line is not JSON |
| -32600 | Not a JSON-RPC 2.0 request |
| -32601 | There is no such method |
| -32602 | A parameter is missing or the wrong type |
| -32603 | Something went wrong inside |
| -32000 | The call was understood and refused, such as a formula with an unknown name |

## Files and history

### `open`

Opens a pattern, optionally with another measurement file and a size.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `path` | text | yes | The pattern file (.sloper) |
| `measurements` | text |  | A measurement file to use in place of the one the pattern names |
| `size` | text |  | The size to use from a size table |

Returns: The pattern's file, measurement file, unit, object and variable counts, and whether it is modified.

### `save`

Saves the pattern.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `path` | text |  | Where to save it; by default, where it was opened from |

Returns: The pattern's file, measurement file, unit, object and variable counts, and whether it is modified.

### `convert_units`

Converts the pattern to another unit, rewriting only lengths, as one undo step. While a number's role is open nothing changes and the reply lists it; mark each and call again.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `units` | one of: `mm`, `cm`, `in` | yes | The unit to convert to |
| `marks` | list |  | The numbers the formulas leave open, each marked as a length or a number |
| `marks[].id` or `marks[].name` | number or text | yes | The object, by its ID or its name |
| `marks[].field` | text | yes | The field the number is in |
| `marks[].token` | whole number | yes | The number's token, as the reply listed it |
| `marks[].role` | one of: `length`, `number` | yes | What the number is |

Returns: `converted` true and the new `units`; or `converted` false and the `undecided` numbers, each with its object, `field`, `token`, `number`, `formula` and `position` in it.

### `undo`

Undoes the last change.

No parameters.

Returns: The pattern's file, measurement file, unit, object and variable counts, and whether it is modified.

### `redo`

Redoes the change last undone.

No parameters.

Returns: The pattern's file, measurement file, unit, object and variable counts, and whether it is modified.

## Measurements

### `get_measurements`

Lists the current measurement set: its file, sizes and values in mm.

No parameters.

Returns: `path`, `size` and `sizes` for a size table, and `measurements`, each with `key`, `value` and `description`.

### `set_measurement`

Adds or changes one value in the measurement file, and saves the file.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `key` | text | yes | The measurement's key, such as waist |
| `value` | number | yes | The value in mm |
| `size` | text |  | For a size table, the size to change |
| `description` | text |  | Its description; by default, the one it has |

Returns: `key`, `value`, whether it was `added`, and its `oldValue` when it had one.

### `missing_measurements`

Lists what the pattern needs that the measurement set lacks.

No parameters.

Returns: `missing`, each with its `key` and the `sizes` with no value.

## Objects and variables

### `list_objects`

Lists the variables and objects with their formulas, values and state.

No parameters.

Returns: `variables` and `objects`, each as `get_object` gives it.

### `get_object`

Gives one object or variable: its name, ID, type, formulas (as shown), computed values and state.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |

Returns: The object, as `get_object` gives it.

### `set_formula`

Changes one formula of an object or variable.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `field` | text | yes | The field, such as length or formula |
| `formula` | text | yes | The new formula |

Returns: The object, as `get_object` gives it.

### `rename`

Renames an object or variable; formulas that use it follow.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `newName` | text | yes | The new name |

Returns: The object, as `get_object` gives it.

### `delete`

Deletes an object or variable that nothing uses.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |

Returns: The pattern's file, measurement file, unit, object and variable counts, and whether it is modified.

### `add_variable`

Adds a variable.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `name` | text | yes | Its name, used in formulas as #name |
| `formula` | formula | yes | Its formula |
| `description` | text |  | What it is for |

Returns: The object, as `get_object` gives it.

## Drafting

### `add_point`

Adds a point of any type.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `type` | one of: `freePoint`, `offsetPoint`, `alongEdgePoint`, `betweenPoint`, `intersectPoint`, `circleEdgePoint`, `circleCirclePoint`, `projectPoint` | yes | The point's type |
| `name` | text |  | Its name; by default the next free one |
| the type's members | see the type | yes | The type's members, as on the [operations page](operations.md); points and edges are given by ID or name |

Returns: The object, as `get_object` gives it.

### `add_edge`

Adds an edge: a line, curve, curve path, circle, arc or offset edge.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `type` | one of: `line`, `curve`, `curvePath`, `circle`, `arc`, `offsetEdge` | yes | The edge's type |
| `name` | text |  | Its name; by default the next free one |
| `role` | one of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` |  | Its role; by default construction |
| the type's members | see the type | yes | The type's members, as on the [operations page](operations.md); points and edges are given by ID or name. An offset edge's `side` may also be `inside` or `outside` a `piece` |

Returns: The object, as `get_object` gives it.

### `add_repeat`

Adds a repeat: points evenly spaced between two points or along an edge.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `a` | ID or name |  | The first point |
| `b` | ID or name |  | The last point |
| `edge` | ID or name |  | Along this edge, in place of a and b |
| `count` | formula | yes | How many points |
| `ends` | one of: `include`, `exclude` |  | Whether the ends have points of their own |
| `name` | text |  | Its name; by default the next free one |

Returns: The object, as `get_object` gives it.

### `split_edge`

Splits an edge at a point on it into two parts; pieces and seams that used it take the parts.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `edge` | ID or name | yes | The edge |
| `point` | ID or name | yes | The point on it |

Returns: The two parts.

### `add_rectangle`

Adds a rectangle of four lines from a corner.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `corner` | ID or name | yes | The corner point |
| `width` | formula | yes | How far right the opposite corner is |
| `height` | formula | yes | How far down the opposite corner is |
| `role` | one of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` |  | Its role; by default construction |

Returns: The four lines.

### `round_corner`

Rounds the corner where two edges meet with an arc.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `edgeA` | ID or name | yes | The first edge |
| `edgeB` | ID or name | yes | The second edge |
| `radius` | formula | yes | The arc's radius |

Returns: The object, as `get_object` gives it.

### `convert_edge`

Changes an edge to a line or a curve in place, keeping its ID.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `to` | one of: `line`, `curve` | yes | What it becomes |

Returns: The object, as `get_object` gives it.

### `merge_points`

Merges two or more points into one, which every edge and formula then uses.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `points` | list of IDs or names | yes | The points |

Returns: The point kept.

### `break_point`

Breaks a point into one for each edge that meets there.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |

Returns: `points`, the points it became.

### `copy_objects`

Copies points and edges, with what they depend on, as Edit → Copy does.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `objects` | list of IDs or names | yes | The points and edges to copy |

Returns: `fragment`, the copy as text for `paste_objects`; `names`, the copied objects' names; `leftOut`, the names of those that cannot be copied.

### `paste_objects`

Pastes a copy as Edit → Paste does: into the pattern it came from, the objects join what they used there; into another, what they depend on comes too. They take new IDs, and a name already taken the next number.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `fragment` | text | yes | The `fragment` that `copy_objects` gave |

Returns: `objects`, the pasted copies of the copied objects; `renamed`, names that changed, as "A → A2".

### `arrange`

Aligns or distributes points. Points a formula places are left as they are and listed, unless named in replace.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `action` | one of: `alignVertical`, `alignHorizontal`, `distribute`, `distributeHorizontal`, `distributeVertical`, `distributeAlongEdge` | yes | What to do |
| `points` | list of IDs or names | yes | The points |
| `reference` | ID or name |  | For aligning: the point to line up with |
| `edge` | ID or name |  | For distributeAlongEdge: the edge |
| `replace` | list of IDs or names |  | Points placed by a formula to change all the same |

Returns: The names of the points `changed`, `asked` (left, as a formula places them) and `kept`.

### `add_transform`

Adds rotated, mirrored or moved copies of points and edges.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `type` | one of: `rotate`, `mirror`, `move` | yes | The transform |
| `sources` | list of IDs or names | yes | The points and edges to copy |
| `name` | text |  | The transform's name |
| `suffix` | text |  | Added to the names of the copies |
| `pivot` | ID or name |  | rotate: the point to turn about; move: a point to turn the copies about |
| `angle` | formula |  | rotate: how far to turn; mirror with axis.a only: the axis's direction; move: the direction |
| `axis` | group |  | mirror: the line to reflect in |
| `axis.edge` | ID or name |  | An edge |
| `axis.a` | ID or name |  | Or a point on the line |
| `axis.b` | ID or name |  | And a second point on it |
| `length` | formula |  | move: how far, at the angle |
| `dx` | formula |  | move: how far right, in place of length |
| `dy` | formula |  | move: how far down |
| `rotate` | formula |  | move with pivot: how far the copies turn |

Returns: The object, as `get_object` gives it.

### `set_role`

Changes an edge's role. A marking role puts it on the pieces it lies in.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `role` | one of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` | yes | The new role |

Returns: The edge, as `get_object` gives it, with the `pieces` it is marked on.

### `set_marker`

Gives a point or repeat a marker; it is marked on the pieces it lies in.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `marker` | one of: `plain`, `hole`, `button`, `match` | yes | The marker |
| `size` | formula |  | Its size; by default a size for the marker and the pattern's unit |

Returns: The edge, as `get_object` gives it, with the `pieces` it is marked on.

## Pieces

### `create_piece`

Makes a piece from the closed outline around a place.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `x` | number | yes | Across, in mm, inside the outline |
| `y` | number | yes | Down, in mm |
| `name` | text |  | Its name |
| `allowance` | formula |  | Its seam allowance; by default the first material's, or a round value for the pattern's unit |

Returns: The piece, as `get_object` gives it.

### `set_edge_allowance`

Gives one edge of a piece its own seam allowance, or clears it.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `edge` | ID or name | yes | The edge |
| `allowance` | formula |  | The allowance; left out, the edge goes back to the piece's |

Returns: The piece, as `get_object` gives it.

### `set_grainline`

Sets a piece's grainline: at an angle, between two points, or none.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `angle` | formula |  | At this angle |
| `start` | ID or name |  | Or from this point |
| `end` | ID or name |  | To this one |
| `none` | true or false |  | No grainline |

Returns: The piece, as `get_object` gives it.

### `add_notch`

Adds a notch on a piece's seam line, at a point or a distance along an edge.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `point` | ID or name |  | At this point |
| `edge` | ID or name |  | Or on this edge of the piece |
| `position` | formula |  | With edge: the distance from its start |

Returns: The piece, as `get_object` gives it.

### `remove_notch`

Removes a notch.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `notch` | whole number | yes | Its number, from 1 |

Returns: The piece, as `get_object` gives it.

### `add_marking`

Marks a point or a line on a piece, or adds stitch holes along an edge.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `kind` | one of: `point`, `line`, `stitch` | yes | What to add |
| `point` | ID or name |  | point: the point or repeat |
| `edge` | ID or name |  | line, stitch: the edge |
| `spacing` | formula |  | stitch: the distance between holes |
| `size` | formula |  | stitch: the hole size |

Returns: The piece, as `get_object` gives it.

### `remove_marking`

Removes a marking.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `marking` | whole number | yes | Its number, from 1 |

Returns: The piece, as `get_object` gives it.

### `set_cut`

Sets how many of a piece to cut, and whether every other one is mirrored.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `count` | whole number | yes | How many |
| `mirrored` | true or false |  | Whether every other one is mirrored |

Returns: The piece, as `get_object` gives it.

### `set_fold`

Puts a piece on the fold of one of its straight edges, or takes it off.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `edge` | ID or name |  | The edge |
| `none` | true or false |  | Off the fold |

Returns: The piece, as `get_object` gives it.

### `set_piece_material`

Sets the material a piece is cut from.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `material` | material ID or name |  | The material |
| `none` | true or false |  | No material |

Returns: The piece, as `get_object` gives it.

### `set_piece_fill`

Sets how a piece is filled on screen.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The piece, by its ID or its name |
| `color` | text |  | Its own colour, as #rrggbb, or empty for its material's |
| `style` | one of: `material`, `tint`, `hatch` |  | How it is filled |

Returns: The piece, as `get_object` gives it.

## Materials

### `list_materials`

Lists the materials and the cut list.

No parameters.

Returns: `materials`, each with `id`, `name`, `color`, `fill` and `allowance`, and the `cutList`.

### `add_material`

Adds a material.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `name` | text |  | Its name; by default the next free one |
| `color` | text |  | Its colour, as #rrggbb |
| `fill` | one of: `tint`, `hatch` |  | How pieces of it are filled |

Returns: The materials and the cut list, as `list_materials` gives them.

### `rename_material`

Renames a material.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `material` | material ID or name | yes | The material, by ID or name |
| `name` | text | yes | The new name |

Returns: The materials and the cut list, as `list_materials` gives them.

### `set_material`

Changes a material's colour, fill or seam allowance.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `material` | material ID or name | yes | The material, by ID or name |
| `color` | text |  | Its colour, as #rrggbb |
| `fill` | one of: `tint`, `hatch` |  | How pieces of it are filled |
| `allowance` | number |  | A seam allowance for pieces of it, in the pattern's unit |
| `noAllowance` | true or false |  | Takes its seam allowance away |

Returns: The materials and the cut list, as `list_materials` gives them.

### `delete_material`

Deletes a material; its pieces are left with none.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `material` | material ID or name | yes | The material, by ID or name |

Returns: The materials and the cut list, as `list_materials` gives them.

## Seams

### `add_seam`

Adds a seam: two runs of piece edges sewn together, whose lengths are checked.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `sideA` | list | yes | Side A, in order along the seam |
| `sideA[].piece` | ID or name | yes | The piece |
| `sideA[].edge` | ID or name | yes | The edge of that piece |
| `sideB` | list | yes | Side B |
| `sideB[].piece` | ID or name | yes | The piece |
| `sideB[].edge` | ID or name | yes | The edge of that piece |
| `name` | text |  | Its name |
| `ease` | formula |  | How much longer side B should be; by default 0 |
| `tolerance` | formula |  | How far the difference may be from the ease; by default a small value for the pattern's unit |

Returns: The object, as `get_object` gives it.

### `flip_seam`

Turns a seam's side B round, for edges sewn running the same way.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |

Returns: The object, as `get_object` gives it.

### `suggest_seams`

Suggests pairs of piece edges that look like they are sewn together, without adding them.

No parameters.

Returns: `suggestions`, each with `sideA`, `sideB`, whether the edge is `shared`, and the length `difference`.

## Notes

### `add_note`

Adds a note, free or hung from a point, edge or piece; with a leader it is a callout.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `text` | text | yes | The text, with draft values such as {=@waist / 4} |
| `anchor` | group |  | What it hangs from; left out for a free note |
| `anchor.point` | ID or name |  | A point |
| `anchor.edge` | ID or name |  | Or an edge |
| `anchor.piece` | ID or name |  | Or a piece |
| `anchor.position` | formula |  | With edge: how far along it, 0 to 1 |
| `x` | formula |  | A free note: its place across |
| `y` | formula |  | A free note: its place down |
| `dx` | formula |  | A hung note: how far right of what it hangs from |
| `dy` | formula |  | A hung note: how far down |
| `size` | number |  | The text size in points |
| `print` | true or false |  | Whether it prints; by default true |
| `leader` | one of: `none`, `arrow`, `dot`, `line` |  | A line to what it hangs from |
| `align` | one of: `left`, `centre`, `right` |  | How its lines line up |
| `box` | true or false |  | A white box behind it |
| `name` | text |  | Its name |

Returns: The object, as `get_object` gives it.

### `set_text`

Changes a note's text, size, printing, leader, alignment or box.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `id` or `name` | number or text | yes | The object, by its ID or its name |
| `text` | text |  | The text, with draft values such as {=@waist / 4} |
| `size` | number |  | The text size in points |
| `print` | true or false |  | Whether it prints; by default true |
| `leader` | one of: `none`, `arrow`, `dot`, `line` |  | A line to what it hangs from |
| `align` | one of: `left`, `centre`, `right` |  | How its lines line up |
| `box` | true or false |  | A white box behind it |

Returns: The object, as `get_object` gives it.

## Checking and output

### `evaluate`

Works the pattern out again and lists its problems.

No parameters.

Returns: The problems: objects that are invalid or blocked, gaps, and seams out of tolerance.

### `check`

As evaluate, with the full report of every computed value.

No parameters.

Returns: The problems, and every object's computed values.

### `render`

Draws the pattern as SVG, as the drafting window shows it.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `format` | one of: `svg` |  | Only svg so far |
| `labels` | true or false |  | Name the points and pieces |
| `hiddenRoles` | list of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` |  | Roles of edges to leave out |
| `annotations` | true or false |  | Whether to draw notes; by default true |
| `region` | group |  | Only this part, in mm |
| `region.minX` | number | yes | The left or top |
| `region.minY` | number | yes | The left or top |
| `region.maxX` | number | yes | The right or bottom |
| `region.maxY` | number | yes | The right or bottom |

Returns: `format` and the `svg` text.

### `export`

Exports a saved layout file as PDF, SVG, DXF or machine DXF.

| Parameter | Value | Required | Description |
| --- | --- | --- | --- |
| `layout` | text | yes | The layout file (.slayout) |
| `path` | text | yes | The file to write |
| `format` | one of: `pdf`, `svg`, `dxf`, `machine-dxf` |  | By default, from the file name's extension |
| `profile` | text |  | A machine profile from the settings, in place of the layout's |

Returns: The `path` written.

