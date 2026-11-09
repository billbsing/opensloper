# Draw points and lines

You draw freely, and OpenSloper records *how* each point was placed: what it
was measured from and how far. When the measurements change, the point moves
with them.

## Snapping decides the operation

With the Point, Line or Curve tool, the pointer snaps to what is near it, and
that decides what kind of point a click makes. In order:

| Near | A click makes | Operation |
| --- | --- | --- |
| An existing point | Uses that point | — |
| Where two edges cross | A point at the crossing | Intersection of edges |
| An edge | A point on it, measured from its nearer end | Point along an edge |
| Level with a point, or straight above or below it | A point that distance from it | Offset point |
| Nothing | A point where you click | Free point |

A marker shows the kind of snap, a dotted guide shows the point it lines up
with, and the status bar says what the click will make, such as *New point
30 mm right of B*. While drawing a line, its start point is lined up with first.

Distances are rounded to a tenth of a millimetre (or 0.1 cm, 0.01 in in those
units), ready to be replaced by a formula in the Properties tab.

## Lines and curves

Lines and curves take two clicks, and drawing carries on from the end. With
the Curve tool, hold ++shift++ as you click to carry the last curve on through
the point instead, as one smooth [curve path](shaping.md#curve-paths). New
edges are outlines; choose another kind first in Tools → Draw As, or change an
edge's role in its properties. Outlines are what pieces are made of;
construction lines are thin, grey and dashed, and are only guides.

A new curve starts straight. Select it to see its handles, and drag a handle's
end to shape it, or type its angles and lengths in the properties. Tools →
Edge → Change to Curve and Change to Line turn one into the other in place.
A line that is a piece's fold, or whose part is, stays a line: a fold has to
be straight.

## Moving points

Drag a point with the Select tool, or nudge the selected points with the arrow
keys: 1 mm a press, 10 mm with ++shift++. Only plain numbers change: a point
placed by a formula, or by other objects, stays put and the status bar says
why. Change its formulas in the Properties tab instead.

## Other operations

| Command | Makes |
| --- | --- |
| Tools → Arc | An arc around a selected point |
| Tools → Edge → Split Edge | Two parts of an edge, split at a point on it; pieces and seams that used the edge take the parts |
| Tools → Edge → Round Corner | An arc rounding the corner where two selected edges meet |
| Tools → Offset | A line following an edge, or a run of edges, at a distance: stitch lines, facings |
| Tools → Points → Merge Points | One point from several, which everything that used them then uses |
| Tools → Points → Break Point | One point for each edge that meets at a point |
| Tools → Points → Repeat Points | A row of evenly spaced points between two selected points or along a selected edge |
| Tools → Transform | Rotated, mirrored or moved copies, which follow their sources |

[Curves, copies and repeats](shaping.md) explains curve paths, offsets,
rounded corners, transforms and repeats. Every operation and its settings are
listed in
[Operations and objects](../reference/operations.md).
