# Large format, projector and cutting machines

The Output tab chooses what the layout prints on.

| Output | Prints |
| --- | --- |
| Tiled pages | Pages for a home printer, taped together (see [Print on paper](printing.md)) |
| Large format | One sheet the width of a plotter or copy-shop roll |
| Projector | One dark sheet to show on the material |
| Material sheet | One sheet the size of the material, for cutting it as laid out |

## Large format

Set **Roll width (mm)**, 914 mm (36 in) by default. The sheet is as long as
the layout needs, with the title, the reminder to print at full size and the
test square across the top. Pack pieces packs to the roll's width.

## Projector

The PDF is white lines on black, thick and with large labels, to project onto
the material on a cutting mat. The test square is at the top, to set the
projector's size by. Calibration applies; paper and pages do not.

A projected piece is cut the way it lies, so a piece turned a quarter turn
across the grain gets a warning.

## Material sheet

For laying out on a fabric width or a board: set **Material width (mm)**, and
**Material length (mm)**, or 0 for a roll. **Material** limits the layout to
the pieces cut from one material, so each material gets its own layout. Pack
pieces packs to the width, for the shortest length, and only tries quarter
turns when **Allow quarter turns (no grain)** is on, for foam, card or other
material with no grain.

A piece cut on a fold is opened out to the whole piece here, since nobody
folds the material before a machine cuts it.

## Output profiles

**Output profile** chooses which marks print: Everything, Home printing,
Plotter or laser cutter, Leather, or Instructions sheet. A profile can leave out
seam lines, notches, grainlines and kinds of marking line, or the seam
allowance itself, as leather pieces often need. The preview follows the
profile.

## Files for other programs

Besides Export PDF…, the Output tab and the File menu have:

| Export | For |
| --- | --- |
| Export SVG… | Inkscape, plotters and laser cutters: true size, pieces where they lie, with cut, seam, marks and labels in separate groups |
| Export DXF… | CAD and cutting systems (DXF-AAMA): one block per piece, with its quantity, for the system to arrange itself |
| Export Machine DXF… | Cutting machines that cut where the pieces lie, with lines on the machine profile's layers |

**Machine profile** chooses how lines go to a cutting machine: each kind of line
(cut, score, mark, engrave, hole) with its colour, layer and width, and whether
it is sent at all. Files list the cuts last, so a piece is not freed before its
holes are cut. Without a profile, SVG is all black.

The same exports run from the command line, as
`opensloper-cli export LAYOUT --format=svg` (see
[Command line](../reference/cli.md)).
