# Example patterns

Finished patterns to open, try with other measurements, and take apart to see
how they are drafted. They are in the `examples` folder of the source, beside
the measurement files they use, and on GitHub:
[examples](https://github.com/billbsing/opensloper/tree/development/examples).
Each is in centimetres and works out with no problems.

| Pattern | What it shows |
| --- | --- |
| [Bodice block](https://github.com/billbsing/opensloper/blob/development/examples/bodice-block/bodice-block.sloper) | A simplified close-fitting bodice, half back and half front on the fold, with a waist dart in each. Curves square to the shoulder, curve paths for the armholes, darts, notches, and [seams](../design/pieces.md#seams) checked for length, with 1 cm of ease on the back shoulder |
| [Circle skirt](https://github.com/billbsing/opensloper/blob/development/examples/circle-skirt/circle-skirt.sloper) | A knee-length full circle skirt and its buttoned waistband. Arcs drafted from the waist, a piece cut on the fold, a narrower hem allowance, notches placed by distance, and a button marker |
| [Tote bag](https://github.com/billbsing/opensloper/blob/development/examples/tote-bag/tote-bag.sloper) | A lined tote with boxed corners, a patch pocket and straps, sized by its variables rather than measurements. Materials, the lining as a moved copy of the body, rounded corners, placement lines, notches, a seam and [notes](../design/notes.md) |

The bodice and the skirt use
[size-table.slm](https://github.com/billbsing/opensloper/blob/development/examples/measurements/size-table.slm),
sizes 8 to 16, and open in the first size: choose another in the Measurements
tab. To try them on one person, open
[person.slm](https://github.com/billbsing/opensloper/blob/development/examples/measurements/person.slm)
in its place. The sizes are round figures for trying the patterns, not a
published sizing standard, and the bodice is a starting point for learning
rather than a tested fit.

Keep a downloaded pattern and the `measurements` folder side by side, as they
are in the source, so the pattern finds its measurement file. From the command
line, in the `examples` folder:

```
opensloper-cli check bodice-block/bodice-block.sloper -s 16
opensloper-cli check circle-skirt/circle-skirt.sloper -m measurements/person.slm
opensloper-cli export-draft tote-bag/tote-bag.sloper --labels -o tote-bag.svg
```

The [tutorials](../tutorials/index.md) have patterns of their own, built step
by step.
