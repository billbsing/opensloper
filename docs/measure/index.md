# The measurements app

**opensloper-measurements** keeps measurement files (`.slm`). A file is either
one person's measurements, with one value each, or a size table, with a value
for each size. Patterns read a measurement by its key, as `@waist`, so one
pattern draws for any file that has the keys it uses.

## Parts of the window

- **Name and notes**, along the top: whose measurements these are, or the name
  of the size table, and anything worth knowing about how they were taken.
- **The table**, on the left: one row for each measurement, with its key, its
  value (one column for each size in a size table) and a description. Add,
  Delete, Up and Down are under it.
- **The body figure**, on the right: front, back and side outlines. The
  measurement you are on is drawn on the figure, with what it is and how to
  take it underneath; clicking a line on the figure goes to its row.
- **Add From the Catalogue**, under the figure: the standard measurements, by
  group and with a search box, to add to the file.

**Show in**, at the top right, chooses whether values are shown in
millimetres, centimetres or inches. Files always store millimetres, so the
choice changes nothing in the file. The unit starts as the one in
Edit → Preferences….

## Edit a value

Click a value and type, or press ++f2++ or ++enter++. ++enter++ or leaving the
cell keeps the change; ++escape++ puts back what was there. A value must be a
number, such as `82.5`, in the unit shown.

A value well outside the usual range for that measurement tints its cell and
says so in the status bar. It is kept, in case it is right: the range is there
to catch typing slips, not to turn anyone away.

Every change is a step in Edit → Undo (++ctrl+z++) and Edit → Redo
(++ctrl+shift+z++).

## Keys

A key is the name patterns use after `@`: letters, digits and underscore, not
starting with a digit, such as `waist_circumference`. Keys from the catalogue
are the usual choice, since patterns from other people are likely to use them.

You can change a key by typing in its cell. Patterns that used the old key
then show it as missing, and the status bar reminds you. Deleting a
measurement asks first, for the same reason.

## When the file changes elsewhere

The design app can save small changes to the same file (see
[Measurements in the design app](in-design.md)). The measurements app watches
the file: with no unsaved changes of its own it simply reads it again. With
unsaved changes, it merges the two by key, and asks which value to keep only
when the same measurement was changed in both places. Saving never overwrites
a change it has not taken in.

## Check a file against a pattern

File → Check Against Pattern… reads a pattern and lists what it needs that
this file cannot give it: keys the file lacks and, in a size table, sizes with
no value. One button adds a missing key, with the catalogue's description, or
goes to the empty cell. The list follows your edits, and is read again when
the pattern is saved. File → Stop Checking closes it.

The design app opens the measurements app this way from File → Measurements →
Edit in Measurements App….
