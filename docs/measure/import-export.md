# Valentina and Seamly2D files

The measurements app reads and writes the measurement files of Seamly2D and
Valentina, so you can bring measurements you already have.

| File | Program | Holds |
| --- | --- | --- |
| `.smis` | Seamly2D | One person |
| `.smms` | Seamly2D | Several sizes |
| `.vit` | Valentina | One person |
| `.vst` | Valentina | Several sizes |

## Import

File → Import… (++ctrl+i++) reads one of these files into a new measurement
file. Afterwards a report lists everything that was not a straight copy:

- **Renamed to our keys**: measurements the catalogue knows under another
  name, such as Seamly2D's `waist_circ`, which becomes `waist_circumference`.
- **Kept as custom keys**: names the catalogue does not know, kept as they
  are. Their leading `@` is dropped, since OpenSloper uses `@` in formulas.
- **Had to change**: names that broke the key rules or were taken twice,
  corrected or numbered.
- **Notes**: values written as formulas, which are worked out and stored as
  numbers; anything that could not be worked out is left at 0 and listed.

A multi-size file gives a base size with a step for each size up or down.
Importing it makes a column for each size within three steps of the base, and
the report says which heights were left out, since a size table here has one
row of sizes.

Nothing is changed silently: check the report, then save the file as `.slm`.

## Export

File → Export… (++ctrl+e++) writes the file in one of these formats.
Measurements are given the names the other program expects; a key with no
translation is written as a custom measurement.

From a size table you can write a multi-size file, or an individual file for
the size you are in. A multi-size file needs sizes that are even numbers from
22 to 72, and it stores a base value with an even step between sizes, so the
report lists any value more than 0.5 mm off that line.
