# Example patterns

Finished patterns to download, open, try with other measurements, and take
apart to see how they are drafted. Each works out with no problems.

| Pattern | What it shows |
| --- | --- |
| [Bodice block with curve paths](../examples/bodice-curve-paths/bodice-curve-paths.sloper) | The [bodice block tutorial](../tutorials/bodice-block.md)'s block, with each armhole drafted as one curve path through the across-back or across-chest point instead of two curves. Curves square to the shoulder, darts, notches, and [seams](../design/pieces.md#seams) checked for length, with 1 cm of ease on the back shoulder |
| [Circle skirt](../examples/circle-skirt/circle-skirt.sloper) | A knee-length full circle skirt and its buttoned waistband. Arcs drafted from the waist, a piece cut on the fold, a narrower hem allowance, notches placed by distance, and a button marker |
| [Tote bag](../examples/tote-bag/tote-bag.sloper) | A lined tote with boxed corners, a patch pocket and straps, sized by its variables rather than measurements. Materials, the lining as a moved copy of the body, rounded corners, placement lines, notches, a seam and [notes](../design/notes.md) |

The bodice and the skirt use
[size-table.slm](../examples/measurements/size-table.slm), sizes 8 to 16, and
open in the first size: choose another in the Measurements tab. To try them on
one person, open [person.slm](../examples/measurements/person.slm) in its place.
The sizes are round figures for trying the patterns, not a published sizing
standard, and the bodice is a starting point for learning rather than a tested
fit.

Save each pattern in a folder of its own, beside a folder named `measurements`
holding the two measurement files, so the pattern finds its measurement file:

```
examples/
  bodice-curve-paths/bodice-curve-paths.sloper
  circle-skirt/circle-skirt.sloper
  tote-bag/tote-bag.sloper
  measurements/size-table.slm
  measurements/person.slm
```

In the source they are already laid out this way, in `docs/examples`. From the
command line, in that folder:

```
opensloper-cli check bodice-curve-paths/bodice-curve-paths.sloper -s 16
opensloper-cli check circle-skirt/circle-skirt.sloper -m measurements/person.slm
opensloper-cli export-draft tote-bag/tote-bag.sloper --labels -o tote-bag.svg
```

The [tutorials](../tutorials/index.md) have patterns of their own, built step
by step, in the same folder.
