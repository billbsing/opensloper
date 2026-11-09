# Notes and callouts

Notes put text on the pattern: sewing instructions such as *Stay-stitch the
neckline*, the size a piece was drafted for, or a value worked out from the
measurements. A callout is a note with a line to what it is about, pointing at
a notch, a dart or a seam.

## Add a note

Choose the Text tool (++x++) and click. The note hangs from what the click
snaps to, a point, a place on an edge, or a piece, and moves with it when the
pattern changes. Clicked on nothing, it is a free note that stays where it is
put. Its text is selected in the properties, ready to type over.

Choose the Callout tool (++a++), click what it points at, then click where its
text goes. The text hangs from the place it points at. ++escape++ stops either
tool.

A note's place is kept as a distance across and down from what it hangs from,
in the **Across** and **Down** rows. Drag the note to change them while they are
plain numbers; once either is a formula, change it in the properties. Dragging a callout's tip onto something else hangs it
from that instead.

## Properties

| Row | Meaning |
| --- | --- |
| Text | The text, on several lines if you like |
| Size (points) | The text size when printed at true size; 10 unless you change it |
| Print | Whether it prints and exports with its piece. Turn it off for notes to yourself |
| Hangs from | The point, edge or piece it moves with, or Nothing (free) |
| Make free | Unhooks the note and leaves it where it is |
| Leader | None for a plain note; Arrow, Dot or Line for a callout |
| Lines | Left, Centred or Right |
| Box | On a white box, so it reads over lines and fills |

A point, edge or piece cannot be deleted while a note hangs from it: make the
note free first, or delete it.

## Values from the draft

Text in `{= }` is a formula, worked out again whenever the pattern changes, in
the pattern's unit:

```
Waist {=Waist.length * 4} cm
Dart {=#dart} cm, ease {=@hip / 20}
```

Each value has its own row, **Value 1**, **Value 2** and so on, showing what it
works out to. A formula that fails blocks the note until it is fixed, and
renaming what it reads changes the text to match.

A few names in braces are filled in when the pattern is printed:
`{pattern.name}`, `{measurements.name}`, `{date}`, `{cutlist}` and
`{materials}`.

## Showing and printing

View → Annotations shows or hides every note on the canvas; the pattern
remembers the choice, and it is not an undo step.

A note prints with a piece when it hangs from the piece, or from one of its
points or edges, or when its text starts inside the piece's cutting line. It
follows the piece in the layout and stays upright when the piece is flipped.
Other notes are left out of layouts, and a printing note on no piece is listed
as a warning. Notes are not written to DXF files.
