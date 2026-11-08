# Operations and objects

!!! note

    This page is generated from the program by `opensloper-cli doc operations`; do not edit it by hand.

Every kind of object a pattern holds, with its members as they are written in a pattern file and given to the Automation API (`add_point`, `add_edge` and the other methods take the same names). Formulas are text, in the pattern's unit; a plain number may be given in their place. Objects refer to one another by ID.

## Members every object has

| Member | Value | Description |
| --- | --- | --- |
| `id` | whole number | The object's ID, a whole number that never changes; other objects refer to it |
| `type` | text | The kind of object, as in the headings on this page |
| `name` | text | The name shown and used in formulas; an edge named after its ends leaves it out |

Edges also have:

| Member | Value | Description |
| --- | --- | --- |
| `role` | one of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` | What the edge is: an outline makes pieces, the others are drawn and printed in their own style |

Points and repeats also have:

| Member | Value | Description |
| --- | --- | --- |
| `marker` | one of: `plain`, `hole`, `button`, `match` | A marker drawn at the point: a hole, a button or a match dot |
| `markerSize` | length formula | The marker's size, when it has one |

## Points

### Free point (`freePoint`)

A point at a place of its own: the origin, or a point not yet tied to others.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `x` | length formula | Distance to the right of the origin |
| `y` | length formula | Distance down from the origin |

### Offset point (`offsetPoint`)

A point a distance at an angle from another point, or across and down from it. Square to a line is an angle such as `Line_A_B.angle + 90`.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `base` | point ID | The point it is measured from |
| `mode` | one of: `polar`, `cartesian` | polar: a length at an angle; cartesian: across and down |
| `length` | length formula | polar: how far from the base |
| `angle` | angle formula | polar: which way, 0° right and 90° up |
| `dx` | length formula | cartesian: how far to the right |
| `dy` | length formula | cartesian: how far down |

### Point along an edge (`alongEdgePoint`)

A point on a line, curve or arc, a length or a share of the way along it: a midpoint, thirds, dart positions.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `edge` | edge ID | The edge it lies on |
| `from` | one of: `start`, `end` | The end it is measured from |
| `mode` | one of: `length`, `ratio` | length: a distance along the edge; ratio: a share of its length, 0 to 1 |
| `value` | length or ratio formula | The distance or the ratio |

### Point between points (`betweenPoint`)

A point on the straight line from one point to another, without needing an edge.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `a` | point ID | The first point |
| `b` | point ID | The second point |
| `mode` | one of: `length`, `ratio` | ratio: a share of the way, 0 to 1; length: a distance from a |
| `value` | length or ratio formula | The ratio or the distance |

### Intersection of edges (`intersectPoint`)

Where two edges cross: lines, curves or arcs.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `edgeA` | edge ID | The first edge |
| `edgeB` | edge ID | The second edge |
| `extendA` | true or false | Let the first edge run on past its ends, along its end directions |
| `extendB` | true or false | Let the second edge run on past its ends |
| `pick` | whole number | Which crossing, counting from 1 along the first edge, so it stays the same one when sizes change |

### Circle and edge (`circleEdgePoint`)

Where a circle around a point crosses an edge: a compass step, such as the shoulder length from the neck point onto the shoulder line.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `centre` | point ID | The point at the centre |
| `radius` | length formula | The distance from the centre |
| `edge` | edge ID | The edge the circle crosses |
| `extend` | true or false | Let the edge run on past its ends |
| `pick` | whole number | Which crossing, counting from 1 along the edge |

### Circle and circle (`circleCirclePoint`)

A point at given distances from two points.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `centreA` | point ID | The first centre |
| `radiusA` | length formula | The distance from the first centre |
| `centreB` | point ID | The second centre |
| `radiusB` | length formula | The distance from the second centre |
| `pick` | whole number | 1: on the left going from the first centre to the second; 2: on the right |

### Point projected onto an edge (`projectPoint`)

From a point onto an edge, square to it or at an angle: the foot of a perpendicular, or straight down to the hem line.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `point` | point ID | The point it comes from |
| `edge` | edge ID | The edge it lands on |
| `direction` | one of: `perpendicular`, `angle` | perpendicular: square to the edge; angle: along the angle given |
| `angle` | angle formula | angle: the direction to travel in |
| `extend` | true or false | Let the edge run on past its ends |

### Repeat (`repeat`)

A number of points evenly spaced between two points or along an edge: buttons, pleats, notch rows. They are named after the repeat and their number, such as `Btn[3]`.

Formulas can read: `.count`.

| Member | Value | Description |
| --- | --- | --- |
| `a` | point ID | The first point |
| `b` | point ID | The second point |
| `edge` | edge ID | Along this edge, by equal length, in place of a and b |
| `count` | number formula | How many points |
| `ends` | one of: `include`, `exclude` | Whether the ends have points of their own |
| `points` | list | The points in use by other objects, each with its number and ID |
| `points[].index` | whole number | The point's number, from 1 |
| `points[].id` | whole number | The ID it was given when first used |

### Corner point (`cornerPoint`)

An end of a rounded corner's arc, where it meets the trimmed edge; made by Round Corner.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `arc` | edge ID | The rounded corner |
| `end` | whole number | Which end: 1 or 2 |

### Point copy (`pointCopy`)

A copy of a point made by a transform; it follows its source.

Formulas can read: `.x`, `.y`.

| Member | Value | Description |
| --- | --- | --- |
| `transform` | object ID | The transform that made it |
| `source` | point ID | What it is a copy of |

## Edges

### Line (`line`)

A straight edge between two points.

Formulas can read: `.length`, `.angle`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `start` | point ID | The point it starts at |
| `end` | point ID | The point it ends at |

### Curve (`curve`)

A smooth curve between two points, shaped by a handle at each end: a hip curve, side seam shaping.

Formulas can read: `.length`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `start` | point ID | The point it starts at |
| `end` | point ID | The point it ends at |
| `angle1` | angle formula | The direction it leaves the start in |
| `length1` | length formula | How far the start's handle reaches |
| `angle2` | angle formula | The direction of the end's handle, pointing back along the curve |
| `length2` | length formula | How far the end's handle reaches |

### Curve path (`curvePath`)

A smooth curve through several points: armholes, necklines, crotch curves. Each point has one direction, so the joins stay smooth. In formulas a node's fields are named node2.angle, node2.lengthIn and so on.

Formulas can read: `.length`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `nodes` | list | The points it passes through, in order |
| `nodes[].point` | point ID | The point |
| `nodes[].angle` | angle formula | The direction of travel at the point |
| `nodes[].lengthIn` | length formula | How far the handle reaches back; not on the first point |
| `nodes[].lengthOut` | length formula | How far the handle reaches on; not on the last point |

### Circle (`circle`)

A circle around a point: round bases, hat crowns.

Formulas can read: `.length`, `.radius`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `centre` | point ID | The point at the centre |
| `radius` | length formula | The distance from the centre |

### Arc (`arc`)

Part of a circle, from one angle to another, anticlockwise: brims, curved flaps.

Formulas can read: `.length`, `.radius`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `centre` | point ID | The point at the centre |
| `radius` | length formula | The distance from the centre |
| `angle1` | angle formula | Where it starts, 0° right and 90° up |
| `angle2` | angle formula | Where it ends |

### Offset edge (`offsetEdge`)

An edge, or a run of joined edges, followed at a distance: stitch lines, facings, linings. Corners are mitred and trimmed.

Formulas can read: `.length`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `edge` | edge ID | One edge to follow, forwards; a run is written as edges instead |
| `edges` | list | The joined edges to follow, in order |
| `edges[].edge` | edge ID | An edge of the run |
| `edges[].reversed` | true or false | Whether the run follows it from its end to its start |
| `side` | one of: `left`, `right` | Which side, going along the run |
| `distance` | length formula | How far from the run |

### Part of a split edge (`splitPart`)

One of the two parts an edge is split into at a point on it; made by Split Edge, for darts and slash and spread.

Formulas can read: `.length`, `.angle1`, `.angle2`, `.angle` (when straight).

| Member | Value | Description |
| --- | --- | --- |
| `edge` | edge ID | The edge that was split |
| `point` | point ID | The point it was split at |
| `part` | whole number | 1: from the start to the point; 2: from the point to the end |

### Rounded corner (`cornerArc`)

An arc that rounds the corner where two edges meet, made by Round Corner with its two corner points.

Formulas can read: `.length`, `.radius`, `.angle1`, `.angle2`.

| Member | Value | Description |
| --- | --- | --- |
| `vertex` | point ID | The corner's point |
| `edgeA` | edge ID | The first edge at the corner |
| `edgeB` | edge ID | The second edge at the corner |
| `radius` | length formula | The arc's radius |

### Edge copy (`edgeCopy`)

A copy of an edge made by a transform; it follows its source.

Formulas can read: `.length`, `.angle1`, `.angle2`, `.angle` (when straight).

| Member | Value | Description |
| --- | --- | --- |
| `transform` | object ID | The transform that made it |
| `source` | edge ID | What it is a copy of |
| `start` | point ID | The copy's start point |
| `end` | point ID | The copy's end point |

## Transforms

### Rotate (`rotate`)

Copies of points and edges turned about a point: dart rotation, slash and spread.

| Member | Value | Description |
| --- | --- | --- |
| `sources` | list | The points and edges to copy; an edge brings its ends |
| `suffix` | text | Added to each copy's name |
| `pivot` | point ID | The point it turns about |
| `angle` | angle formula | How far it turns, anticlockwise |

### Mirror (`mirror`)

Copies of points and edges reflected in a line: half a piece made whole.

| Member | Value | Description |
| --- | --- | --- |
| `sources` | list | The points and edges to copy; an edge brings its ends |
| `suffix` | text | Added to each copy's name |
| `axis` | group | The line to reflect in: an edge, two points, or a point and an angle |
| `axis.edge` | edge ID | An edge to reflect in |
| `axis.a` | point ID | A point on the line |
| `axis.b` | point ID | A second point on the line |
| `angle` | angle formula | With axis.a only: the line's direction |

### Move (`move`)

Copies of points and edges moved aside, and turned if wanted: developing facings, yokes, pockets.

| Member | Value | Description |
| --- | --- | --- |
| `sources` | list | The points and edges to copy; an edge brings its ends |
| `suffix` | text | Added to each copy's name |
| `mode` | one of: `polar`, `cartesian` | polar: a length at an angle; cartesian: across and down |
| `length` | length formula | polar: how far |
| `angle` | angle formula | polar: which way |
| `dx` | length formula | cartesian: how far to the right |
| `dy` | length formula | cartesian: how far down |
| `pivot` | point ID | With rotate: the point the copies turn about |
| `rotate` | angle formula | With pivot: how far the copies turn |

## Pieces and seams

### Piece (`piece`)

A closed outline of edges, with its seam allowance, grainline, notches, markings, cut and material.

Formulas can read: `.holes`.

| Member | Value | Description |
| --- | --- | --- |
| `path` | list | The edges around the piece, clockwise |
| `path[].edge` | edge ID | An edge of the outline |
| `path[].reversed` | true or false | Whether the path follows it from its end to its start |
| `path[].allowance` | length formula | The edge's own seam allowance, when it has one |
| `allowance` | length formula | The seam allowance |
| `grainline` | group | Left out for none |
| `grainline.angle` | angle formula | At an angle through the middle of the piece |
| `grainline.start` | point ID | Or between two points: the first |
| `grainline.end` | point ID | The second point |
| `notches` | list | Notches on the seam line |
| `notches[].point` | point ID | At a point on the seam line |
| `notches[].edge` | edge ID | Or on an edge of the piece |
| `notches[].position` | length formula | With edge: the distance from the edge's start |
| `markings` | list | Points and lines marked on the piece |
| `markings[].kind` | one of: `point`, `line`, `stitch` | point: a marked point; line: a marking line; stitch: stitch holes along an edge |
| `markings[].point` | point ID | point: the point or repeat |
| `markings[].edge` | edge ID | line, stitch: the edge |
| `markings[].spacing` | length formula | stitch: the distance between holes, adjusted to fit |
| `markings[].size` | length formula | stitch: the hole size |
| `cut` | group | How many to cut |
| `cut.count` | whole number | How many |
| `cut.mirrored` | true or false | Whether every other one is mirrored |
| `foldEdge` | edge ID | The edge the piece is cut on the fold of, when it is |
| `material` | material ID | The material it is cut from |
| `fill` | group | How it is filled on screen, when not as its material |
| `fill.color` | text | Its own colour, as #rrggbb |
| `fill.style` | one of: `material`, `tint`, `hatch` | How it is filled: as its material, a tint or a hatch |

### Seam (`seam`)

Two runs of piece edges that are sewn together, so their lengths can be checked.

| Member | Value | Description |
| --- | --- | --- |
| `sideA` | list | The edges of side A, in order along the seam |
| `sideA[].piece` | piece ID | The piece |
| `sideA[].edge` | edge ID | The edge of that piece |
| `sideB` | list | The edges of side B |
| `sideB[].piece` | piece ID | The piece |
| `sideB[].edge` | edge ID | The edge of that piece |
| `reversed` | true or false | Whether side B runs the same way as its pieces' paths |
| `ease` | length formula | How much longer side B should be than side A |
| `tolerance` | length formula | How far the difference may be from the ease |

## Notes

### Note (`note`)

Text on the pattern, free or hung from a point, edge or piece, with draft values such as `{=@waist / 4}` worked out in it.

| Member | Value | Description |
| --- | --- | --- |
| `anchor` | group | What it hangs from; left out for a free note |
| `anchor.point` | point ID | A point |
| `anchor.edge` | edge ID | Or an edge |
| `anchor.piece` | piece ID | Or a piece |
| `anchor.position` | number formula | With edge: how far along it, 0 to 1 |
| `x` | length formula | A free note: its place across |
| `y` | length formula | A free note: its place down |
| `dx` | length formula | A hung note: how far right of what it hangs from |
| `dy` | length formula | A hung note: how far down |
| `text` | text | The text, with draft values in {= } |
| `size` | number | The text size in points |
| `print` | true or false | Whether it prints with its piece |
| `leader` | one of: `none`, `arrow`, `dot`, `line` | A line to what it hangs from, making it a callout |
| `align` | one of: `left`, `centre`, `right` | How its lines line up |
| `box` | true or false | Whether it has a white box behind it |

