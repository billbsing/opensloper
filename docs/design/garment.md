# The Garment tab

The **Garment** tab in the side panel shows your pieces as they will look
sewn: darts closed, pieces cut on the fold opened out, and each piece shaded as
if wrapped round a body. It is there to glance at while you draft, to see
proportions and shaping. It does not show how pieces join, fit or drape.

The tab only shows; nothing in it changes the pattern, and nothing about it is
saved with the pattern.

## What it shows

- **Each piece on its own, where it is on the canvas.** Pieces that overlap on
  the canvas, such as a front drafted over a back, overlap here too, in the
  canvas's drawing order. Move them apart on the canvas to see them apart here.
  Hidden pieces are left out, and while a piece is isolated only it is shown
  (see [Overlapping pieces](pieces.md#overlapping-pieces)).
- **Upright by its grainline.** A piece with a grainline is turned so the
  grainline points up, as the piece hangs on the body. A waistband drafted
  upright with a sideways grainline is shown lying across.
- **Darts closed.** A dart is closed when it is a [seam](pieces.md#seams)
  between its two legs: make a seam with one leg as side A and the other as
  side B. The two legs come together on one stitch line and the piece opens
  slightly round the dart to take it up, most near the dart and not at all on
  the far side. A dart with a curved leg, or one opening wider than 90°, is
  left open, and a note under the drawing says so.
- **Folds opened.** A piece cut on the fold is shown whole, both halves, with
  no line down the fold.
- **Seams sewn.** An edge that is in a seam has a fine stitch line just inside
  it. Buttons, holes, stitch lines and topstitching are drawn; notches,
  labels, seam allowances and construction lines are not.
- **Colour.** Each piece is filled with its material's colour at full
  strength, or its hatching.

A piece that has a problem is left out, with a note under the drawing.

## Using it

| To | Do |
| --- | --- |
| Show another material | Choose it in the list at the top, or All materials. The tab starts on the first material, so lining does not cover the main pieces |
| Zoom | The mouse wheel, about the pointer |
| Pan | Drag |
| Fit everything again | Double-click |
| Zoom and pan with the canvas | Tick **Follow canvas** |
| See a piece's name | Point at it; it is highlighted on the canvas too |
| Select a piece | Click it; it is selected on the canvas |

A piece selected on the canvas is outlined in the tab. A seam selected in the
Objects tab is marked in orange on both its sides, wherever they are, which
helps find matching edges once pieces are apart.

The tab follows every change you make. While it is closed it does no work.

## Shading

Edit → Preferences…, Design tab, Garment View:

| Setting | Meaning |
| --- | --- |
| Shade pieces as if round a body | Untick for flat colour |
| Light from (degrees) | Where the light comes from: 0° from the right, 90° from above; 135°, the upper left, by default |
| Shading strength (%) | How strong the shading is, 50% by default |

## Exporting

**Export…** at the top of the tab saves the pieces it shows as an SVG
drawing, at true size in millimetres, or as a PNG image of the width you
choose, drawn as on screen. In SVG the shading is drawn as gradients, so it is
close to the screen but not exact.

Scripts get the same drawing from the Automation API's `render` with
`"garment": true`; see the [Automation API](../reference/api.md).
