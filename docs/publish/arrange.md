# Arrange pieces

Each piece is placed as many times as its pattern says to cut it. A piece cut
twice and mirrored gets its second copy flipped.

## Move, turn and flip

Click a piece to select it and drag it where you want it; it moves in 0.5 mm
steps. ++escape++ during a drag puts it back.

On the Pieces tab:

- **Turn 90°** turns the selected piece a quarter turn. Pieces only turn in
  quarter turns, so the grainline stays square to the sheet; the printed
  grainline shows how to lay it on the material.
- **Flip** turns it over, for a mirrored copy.
- **Back to tray** takes it off the pages. ++delete++ does the same.

## The tray

The tray lists copies with no place yet: new pieces, and copies taken back.
Drag one onto the pages to place it under the pointer, or double-click it to
put it in a new row. **Place new pieces** places them all in rows.

A piece with a problem in its pattern waits in the tray until the pattern is
fixed.

## Pack pieces

**Pack pieces** arranges every copy, including those in the tray, to use as
few pages, or as short a sheet, as it can. It tries each piece as it stands and
a quarter turn from it, keeps pieces 10 mm apart, and keeps flips. When your own
arrangement already does better, it is kept, and the status bar says so.

Packing is one step to undo, and the pieces can still be dragged afterwards.

## Warnings

The problems count in the status bar (click it for the list) warns about pieces that overlap, pieces off the sheet,
copies still in the tray and, where a piece is cut as it lies, a piece turned
across the grain. Warnings do not stop printing; problems such as a missing
pattern do, so a blank page is never printed.
