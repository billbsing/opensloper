# Example patterns

Finished patterns to open in opensloper-design, try with other measurements, or read as examples of the file format. Each pattern is in centimetres and works out with no problems; a test checks that it still does.

| Pattern | What it shows |
| --- | --- |
| [`bodice-block/bodice-block.sloper`](bodice-block/bodice-block.sloper) | A simplified close-fitting bodice block, half back and half front on the fold, with a waist dart in each. Curves square to the shoulder, curve paths for the armholes, darts, notches, and seams checked for length, with 1 cm of ease on the back shoulder. |
| [`circle-skirt/circle-skirt.sloper`](circle-skirt/circle-skirt.sloper) | A knee-length full circle skirt and its buttoned waistband. Arcs drafted from the waist circumference, a piece cut on the fold, a narrower hem allowance, notches placed by distance, and a button marker. |
| [`tote-bag/tote-bag.sloper`](tote-bag/tote-bag.sloper) | A lined tote bag with boxed corners, a patch pocket and straps. It needs no measurements: resize it with its variables. Materials, the lining as a moved copy of the body, rounded corners, pocket placement lines, notches, a seam check and notes. |

The bodice and the skirt use [`measurements/size-table.slm`](measurements/size-table.slm), a size table from 8 to 16, and open in the first size. Choose another size in the design app, or try them with one person's set, [`measurements/person.slm`](measurements/person.slm):

```
opensloper-cli check bodice-block/bodice-block.sloper -s 16
opensloper-cli check circle-skirt/circle-skirt.sloper -m measurements/person.slm
opensloper-cli export-draft tote-bag/tote-bag.sloper --labels -o tote-bag.svg
```

The sizes are round figures for trying the patterns, not a published sizing standard, and the bodice is a starting point for learning rather than a tested fit.

The tutorial patterns are in [`docs/examples`](../docs/examples), beside the tutorials that build them step by step.
