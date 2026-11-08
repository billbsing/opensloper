# The design window

**opensloper-design** is where patterns are drafted. A pattern is built from
points and edges placed by formulas, then closed outlines become pieces.

## Parts of the window

- **Canvas**, in the middle: the pattern, on a grid in the pattern's unit, with
  rulers along the top and left (View → Rulers, Ctrl+R).
- **Tools**, down the left of the canvas: Select, Point, Line, Curve, Circle,
  Rectangle, Piece, Notch, Seam, Text and Callout, then commands such as Arc,
  Split Edge and Round Corner. The Tools menu lists them all.
- **Side panel**, on the right (View → Side Panel), with tabs:

    | Tab | What it shows |
    | --- | --- |
    | Properties | The selected object: its name, formulas and settings |
    | Objects | Every object, with its operation, value and state, searchable |
    | Variables | The pattern's `#` variables |
    | Measurements | The measurement file's values, with a slider to try a size up or down |
    | Lines | Which kinds of line are shown |
    | Materials | The materials pieces are cut from |

- **Status bar**, along the bottom: where the pointer is, what a click will
  make, and whether the pattern has problems.

## Tools and keys

| Tool | Key | Click to |
| --- | --- | --- |
| Select | ++s++ | Select points, edges and pieces; drag to move points |
| Point | ++p++ | Add a point |
| Line | ++l++ | Draw a straight edge between two points |
| Curve | ++c++ | Draw a curved edge between two points |
| Circle | ++o++ | Draw a circle from its centre and a point on it |
| Rectangle | ++r++ | Draw a rectangle from one corner to the opposite one |
| Piece | ++k++ | Make a piece from the closed outline around the click |
| Notch | ++t++ | Add a notch on a piece's edge, or remove one |
| Seam | ++e++ | Pick the edges of two pieces that are sewn together |
| Text | ++x++ | Add a note |
| Callout | ++a++ | Add a note with a line to what it is about |

++escape++ stops what a tool is doing, and pressed again returns to Select.

## Moving around

| To | Do |
| --- | --- |
| Zoom | ++ctrl+plus++ and ++ctrl+minus++, or ++ctrl++ and the mouse wheel |
| Pan | Drag with the middle button, or hold ++space++ and drag |
| Scroll | The mouse wheel; ++shift++ and the wheel scrolls sideways |
| See the whole pattern | ++ctrl+0++ (View → Fit Pattern) |
| See it at true size | ++ctrl+1++ (View → True Size) |

On a Mac, ++cmd++ takes the place of ++ctrl++.

## Selecting and editing

Click a point, edge or piece to select it; ++shift++ and click adds to the
selection. Drag on empty canvas to select everything inside a box. The
Properties tab shows the selected object, and a change there is made when you
press ++enter++ or leave the field.

## Editing in the lists

The Variables and Measurements tabs are edited in their lists. Click a cell and
type, or press ++f2++ or ++enter++, to change it; ++enter++ or leaving the cell
makes the change, and ++escape++ puts the old text back. A value that cannot be
used keeps its text, with the cell in red and the reason in the status bar,
until you fix it or press ++escape++ on it. Formula cells offer names as you
type, as in the Properties tab. ++delete++ removes the row only when no cell is
open.

The Materials tab is a list to read: its Edit… button, a double-click on a
row, or Edit → Materials… opens the Materials window, where materials are
added, renamed, recoloured and deleted.

Every change is one step in Edit → Undo (++ctrl+z++) and Edit → Redo
(++ctrl+shift+z++). ++delete++ removes the selection; it is refused while
something else uses an object, and the status bar says what.

Labels follow View → Labels: Contextual shows the names of what you are working
with, All shows every name, and None hides them. Hold ++n++ to see every name
for a moment.
