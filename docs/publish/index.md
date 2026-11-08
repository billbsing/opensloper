# The publish window

**opensloper-publish** lays out the pieces of finished patterns and prints
them at true size: on home printer pages taped together, on one large sheet,
through a projector onto the material, or as files for a cutting machine. A
layout is saved as a `.slayout` file.

## Start a layout

In the design app, File → Publish… (++ctrl+p++) opens the publish app with the
pattern's layout, the file of the same name ending `.slayout`, or starts a new
one with every piece placed. It reads the saved pattern, so an unsaved pattern
is saved first, and a changed one asks whether to save.

You can also open the publish app on its own: File → Open… takes a layout, or
a pattern to start a layout for.

## Parts of the window

- **The pages**, on the left: the pieces where they lie, over the sheets they
  print on. Each page's printable area is white, and grey when nothing prints
  on it. The status bar counts the pages.
- **Tabs**, on the right:

    | Tab | What it holds |
    | --- | --- |
    | Pieces | The selected piece (Turn 90°, Flip, Back to tray), Place new pieces, Pack pieces, and the tray of pieces not yet placed |
    | Patterns | The patterns in the layout, each with its measurements and size |
    | Output | What it prints on, the paper, marks, fill and profiles, and the exports |
    | Notes | The title block and notes on the sheet |

- **Problems**, under the tabs: anything that stops the layout printing, such
  as a missing pattern, and warnings, such as overlapping pieces.

The wheel zooms about the pointer; drag with the middle button, or hold
++space++ and drag, to pan. View → Fit Pages (++ctrl+0++) shows every page.

## Patterns and sizes

A layout can hold several patterns, and the same pattern more than once, in
different sizes. On the Patterns tab, **Add pattern…** and **Remove pattern**
change the list. For the pattern selected there, **Choose measurements…** picks
the measurement file to draw it with, **Use the pattern's own** goes back to
the file the pattern names, and **Size** chooses the size of a size table.

The layout follows its patterns. When a pattern or measurement file is saved,
the layout reads it again within a second or two, and new pieces wait in the
tray. View → Reload Patterns (++ctrl+r++) reads everything again by hand.

Every change to a layout is a step in Edit → Undo (++ctrl+z++).
