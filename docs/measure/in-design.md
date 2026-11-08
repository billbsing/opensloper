# Measurements in the design app

A pattern names the measurement file it was last drafted with. The design app
shows that file in the **Measurements** tab of the side panel, and lets you
make small changes to it without leaving the pattern.

## Choose a file

File → Measurements has:

| Command | What it does |
| --- | --- |
| New Set… | Make a new, empty measurement file for the pattern |
| Open Set… (++ctrl+m++) | Draft the pattern with another file |
| Edit in Measurements App… | Open the file in the measurements app, checked against the pattern |

A pattern does not need a measurement file at all. Plain numbers and `#`
variables are enough to draft with, and only formulas that use an `@` key show
an error until there is a file with that key.

## The Measurements tab

The tab shows the file's name, the **Size** box for a size table, and a row for
each measurement. Values and descriptions can be edited in place, as in the
other lists: ++enter++ keeps a change and ++escape++ puts the old text back.

- **Missing**: keys the pattern uses that the file does not have are listed
  with Missing as their value. Type a value in the row to add the key.
- **Add**: adds a new key, ready to name.
- **Save** writes your edits to the file, all at once. Rows you have changed
  are bold and marked `*` until then, and the pattern keeps drawing with the
  values in the file.
- **Revert** drops your edits.

Opening another file or pattern, or closing the app, with edits not yet saved
asks whether to save them. These changes are not part of the pattern's undo,
since the file belongs to every pattern that uses it.

Everything else, such as sizes, reordering, imports and the catalogue, is done
in the measurements app.

## Try other sizes

**Test size** makes every measurement a little larger or smaller, 1% a step,
so you can see how the pattern grows and shrinks before you trust it with
other people's measurements. Nothing is saved, and **Reset** goes back to the
file's values. It is paused while edits are waiting to be saved.
