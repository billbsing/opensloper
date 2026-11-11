# Curves, copies and repeats

Beyond points, lines and simple curves, a few operations shape a pattern
further: curves through several points, edges that follow other edges at a
distance, rounded corners, copies that are turned, mirrored or moved, and rows
of evenly spaced points. Each stays parametric, so it follows the measurements
like everything else.

## Curve paths

A curve path is one smooth curve through several points, for armholes,
necklines and crotch curves. At each point it has one direction of travel, so
the curve has no kink where it passes through. Each point also has a handle
reaching back (**handle in**) and one reaching on (**handle out**); the first
point has only a handle out and the last only a handle in.

Select a curve path to see its handles. Drag a handle's end to change the
point's direction and that handle's length, or type them in its properties:
**Point 2 angle**, **Point 2 handle in**, **Point 2 handle out** and so on,
numbered from the start. Like any field they take formulas, such as
`Back_shoulder.angle - 90` to leave the shoulder square, and once one is a
formula its handle is changed only in the properties. In formulas elsewhere the
same values are `node2.angle`, `node2.lengthIn` and `node2.lengthOut`.

To draw one, use the Curve tool (++c++): click the start and the second point
as for a curve, then hold ++shift++ and click each further point. Each
Shift+click carries the curve on through the point, so the curve becomes one
curve path; a plain click starts a separate curve from the end instead, and
++escape++ stops. The point the path ended at turns to run smoothly on to the
new one, and the handles you had already set stay. Each Shift+click is its own
undo step. A curve that something already uses, such as a piece, cannot be
carried on, because its end would move.

The [Automation API](../scripting/index.md) makes curve paths too, and copy
and paste copies them; the
[bodice block with curve paths](../getting-started/examples.md) example has
two.

## Offset edges

An offset edge follows an edge, or a run of edges joined end to end, at a
distance: topstitching, facings, linings and turn-backs. Select the edge or
edges and choose Tools → Offset:

| Command | Makes an edge |
| --- | --- |
| Offset Edge Left, Offset Edge Right | On that side, going along the selected run |
| Offset Inside Piece, Offset Outside Piece | Inside or outside the selected piece, along its selected edges |

The new edge starts 10 mm away (1 cm, ½ in), as construction: set its
distance in the properties and give it a role, such as a stitch line, so it is
marked on the piece. It follows its edges when they move. Outer corners are
mitred and inner ones trimmed where the offsets cross, and it is invalid when
a curve bends more tightly than the distance.

## Rounded corners

Select two straight edges that meet at a point and choose Tools → Edge → Round
Corner. An arc replaces the corner, 10 mm in radius (1 cm, ½ in) to start, and
both edges are cut back where it meets them. The radius is a formula in the
arc's properties. The sharp corner stays behind as construction, as a guide.

A piece already made from the edges is rounded too, in the same step: it takes
the arc and what is left of the edges, and keeps its notches, seams, cut,
grainline and material. A notch on the part cut away moves to the end of the
arc beside it. A corner on the edge a piece is folded on cannot be rounded,
since a fold has to stay one straight edge.

Only corners between straight edges can be rounded so far. To round a second
corner on the same edge, select the part of the edge that is left.

## Copies that follow: transforms

Tools → Transform makes copies of the selected points and edges that are
turned, mirrored or moved, and that follow their sources when the pattern
changes. Each leaves the sources where they are:

| Command | After choosing it | Used for |
| --- | --- | --- |
| Rotate Copy… | Click the point to turn about | Moving a dart, slash and spread |
| Mirror Copy… | Click a straight edge, or two points on the line to reflect in | Making a half whole |
| Move Copy… | Nothing: the copies start where the sources are | Moving a section aside to develop it: facings, yokes, pockets, the back drafted over the front |

The transform is selected when it is made, with no turn or movement yet: type
its **Angle**, or **Across** and **Down**, in the properties, as formulas. A
dart's angle, for example, is the difference between its legs' angles,
`Dart_leg_2.angle - Dart_leg_1.angle`.

The copies are named after their sources with a suffix, such as `A_r1`.
Copied points are drawn as diamonds rather than dots. Hover over or select a
copy to see a faint dashed line to its source, which lights up; selecting the
transform shows this for all its points. Double-click a copy, or choose Tools →
Transform → Go to Source, to select its source and bring it into view; with
the transform selected, Go to Source selects everything it copies. Copies
cannot be dragged, since the transform places them, but they can be used by
any other operation, and a copied edge can be given another role. To make a
piece from copied edges, click inside them with the Piece tool. Deleting the
transform deletes its copies; a copy cannot be deleted on its own.

For example, to move a shoulder dart to the side seam: draw a line from the
bust point to the side seam and split the side seam there; select the outline
between the dart and that line, and Rotate Copy it about the bust point by the
dart's angle, so the shoulder dart closes and a side dart opens; make the
originals construction; click inside the new outline.

## Repeats

A repeat is a row of evenly spaced points between two points or along an
edge, for buttons, buttonholes, pleats, tucks and belt loops. Its **Count** is
a formula, so the row can grow with the pattern, such as
`round(Centre_front.length / 8)`, and **Ends** says whether the first and last
points sit on the ends or the row is spaced between them.

The points are named after the repeat and their number, `Btn[1]`, `Btn[2]` and
so on, and can be used like other points, in formulas as `Btn[2].x`. When the
count drops, anything that used a point that has gone shows an error instead of
moving to another point; when the count rises again, the point comes back.

Select the first point of a repeat to edit the repeat. Give it a marker, such
as Button, and every point in the row gets it and is marked on the piece.

To make one, select two points, or one line or curve, and choose Tools →
Points → Repeat Points. The new repeat has three points, the first and last on
the ends, and its first point is selected so you can set **Count** and **Ends**
in the Properties tab. The [Automation API](../scripting/index.md) makes them
with `add_repeat`, and copy and paste copies them.
