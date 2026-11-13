# Pieces

A piece is a closed outline of edges, with everything needed to cut it: seam
allowance, grainline, notches, how many to cut, and its material.

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

## Material

Each piece is cut from a material, which gives it its colour on screen and puts
it on that material's cut list. The Materials tab lists them with the cut
list; Edit… opens the Materials window, which adds, renames, recolours and
deletes materials, switches one between a tint and hatching, and can give one
a seam allowance: new pieces start with the first material's. Each change is
one undo step and shows at once on the canvas.

## Markings

Points and lines inside a piece can be marked on it: a point with a marker
(hole, button or match dot) and a line drawn as a placement, stitch, fold, cut,
skive or edge-finish line are added to the pieces they lie in. Tools → Markings
adds them by hand, and stitch holes along an edge.

## Seams

A seam says which edges are sewn together, so their lengths can be checked: a
side seam front to back, a shoulder with the back eased in, a sleeve cap to its
armhole. The app cannot tell which edges are sewn from the shapes alone, so
you make seams yourself, or accept the ones it suggests.

Choose the Seam tool (++e++) and click the edges of side A, in order along the
seam; then press ++tab++ and click the edges of side B. A side may run over
several pieces, such as a sleeve cap sewn to a front and a back armhole, and
may skip a dart. On an edge two pieces share, the side of the edge you click
picks the piece, and clicking an edge again takes it off. The status bar shows each side's length and the difference as
you go; ++enter++ makes the seam, and ++escape++ drops it. An edge that is a
piece's fold cannot be in a seam.

**Tools → Suggest Seams…** lists likely pairs, none ticked: edges two pieces
share first, then edges of different pieces within 1 mm of the same length.
Tick the ones that are sewn; accepting them is one undo step.

Seams are not drawn on the canvas: select one in the Objects tab, under Pieces.
Its properties show:

| Row | Meaning |
| --- | --- |
| Side A, Side B | The edges of each side, with the pieces they are on |
| Ease | How much longer side B should be than side A, as a formula: `10mm` for an eased back shoulder, `@waist * 0.5` for gathers. 0 for edges that match |
| Tolerance | How far the difference may be from the ease before it is a problem; 1 mm unless you change it |
| Lengths, Difference | Each side's length on the seam line, and how far apart they are |
| Flip | Turns side B round |

Sewn edges usually run opposite ways round their pieces, so side B is paired
from its far end. When that pairs the wrong ends, which is most likely with a
mirrored piece, press Flip.

A seam between a dart's two legs, one leg as side A and the other as side B,
checks that the legs match, and lets [the Garment tab](garment.md) close the
dart.

A seam whose difference is outside its tolerance is a problem: the status bar
counts it, the Objects tab's Problems filter lists it, and `opensloper-cli
check` reports both lengths. The seam itself stays valid, so nothing else
stops working. Edges in no seam are never reported, since a hem or an opening
looks just like a forgotten seam.

Splitting an edge a seam uses gives the seam both parts, so its lengths do not
change. A piece cannot be deleted while a seam uses it.
