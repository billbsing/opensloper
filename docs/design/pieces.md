# Pieces

A piece is a closed outline of edges, with everything needed to cut it: seam
allowance, grainline, notches, how many to cut, and its fabric.

## Make a piece

Choose the Piece tool (++k++) and click inside a closed outline. The piece is
made from the outline edges around the click, whichever way they were drawn;
construction lines are left out. The tool stays on for the next piece until
++escape++.

A piece is made of whole edges. If its outline uses only part of an edge, such
as a hem drawn once under both front and back, the piece is refused and the
status bar names the edge: split it at the point where the pieces meet (select
the edge and the point, then Tools → Edge → Split Edge) and click again.
Splitting an edge that pieces already use moves them onto the parts.

## Seam allowance

A new piece starts with the allowance in its properties; type a formula to
change it. To give one edge its own allowance, choose the edge under
**Own allowance**: it gets a row of its own, named after the edge. Empty that
row to go back to the piece's allowance.

## Grainline

New pieces have a grainline at 90°, straight up and down the piece. Under
**Grainline** choose At an angle and type the angle, or Between two points and
choose the two points under Grainline from and Grainline to, or None.

## Notches

Choose the Notch tool (++t++) and click on a piece's edge. On a point the
notch follows the point; elsewhere it is placed a distance along the edge. A
notch on an edge two pieces share goes on both, so they match. Click a notch
to remove it.

## Cut and fold

**Cut** says how many to cut, and **Mirrored** whether every other one is
turned over, as for a left and a right. **Fold** puts a piece on the fold of
one of its straight edges: that edge has no allowance and shows a fold mark,
and the label reads *Front, cut 1 on fold*.

## Fabric

Each piece is cut from a fabric, which gives it its colour on screen and puts
it on that fabric's cut list. The Fabrics tab adds, renames and recolours
fabrics, and can give one a seam allowance: new pieces start with the first
fabric's.

## Markings

Points and lines inside a piece can be marked on it: a point with a marker
(hole, button or match dot) and a line drawn as a placement, stitch, fold, cut,
skive or edge-finish line are added to the pieces they lie in. Tools → Markings
adds them by hand, and stitch holes along an edge.
