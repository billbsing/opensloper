# Print on paper

For a home printer, choose **Tiled pages** on the Output tab. The layout is cut
into pages that overlap, to be trimmed and taped together.

## Paper and pages

| Setting | What it does |
| --- | --- |
| Paper | A4, A3 or Letter, or Custom with its width and height |
| Margin (mm) | The edge of the paper the printer cannot reach |
| Overlap (mm) | How far neighbouring pages overlap |
| Alignment marks | Diamonds, half circles or none, to line pages up |
| Piece fill | None, a light tint of each piece's colour, or hatching for black-and-white printers |

Pages are named by row and column, A1, A2, B1 and so on, and pages with
nothing on them are left out. To reprint some pages, or leave some out,
right-click a page: it turns grey and crossed, and the page map strikes it
through. Right-click it again to put it back.

**Print…** (++ctrl+p++), on the File menu, the toolbar and the Output tab,
prints the layout directly. The dialog chooses the printer and the number of
copies, and for tiled pages whether to print everything, **the cover only**,
to measure the test square first, or **the pages after the cover**, once the
square is right. It prints the same PDF as Export PDF, at 100%, never scaled
to fit. On Windows it goes to your PDF viewer, which prints on the default
printer: if the viewer asks, choose 100% or actual size.

**Export PDF…** (++ctrl+e++) writes the PDF, to print later or from another
computer. A projector layout is shown, not printed, so Print is off for it.

## Print at true size

Print the PDF at **100%** or **actual size**, never "fit to page". The first
page is a cover with the page map, a reminder of this, and a test square: 10
cm, or 4 in on Letter paper.

Measure the test square with a ruler before you cut anything. If it is right,
print the rest and tape the pages together, matching the marks in the overlaps.

## Calibrate a printer

Some printers are always a little off. Edit → Preferences… → Publish holds two
calibration factors, across and down, and everything printed at true size is
scaled by them, including the test square.

1. Print a layout with the factors as they are.
2. Measure the test square across and down.
3. Under **Work Out From a Test Print**, choose the test square's size, type
   what you measured, and click **Work Out Factors**.

A square that measures 98.5 mm across, printed with no correction, needs
100 / 98.5 = 1.015 across. The factors belong to your printer, so every layout
uses them.

## Title block and notes

The Notes tab sets what prints besides the pieces.

- **Title block**: the pattern, measurements, layout name, date, cut list and
  materials, as you choose, in a corner of the cover, and on every page if you
  like.
- **Sheet notes**: text placed on the pages, selected and dragged like a
  piece. Notes can fill in fields as they print: `{pattern.name}`,
  `{measurements.name}`, `{date}`, `{page}`, `{pages}`, `{cutlist}` and
  `{materials}`. Each has its own size, line alignment, white box, font, and
  bold or italic, as notes on the pattern do (see
  [Notes and callouts](../design/notes.md#fonts)).

Notes written on the pieces in the design app print with their pieces.
