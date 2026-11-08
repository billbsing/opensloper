# Measurements and formulas

Every distance and angle in a pattern is a formula. A formula can be a plain
number, `250`, or read measurements, variables and other objects:
`@hip / 4 + #ease`.

## Measurements

A pattern reads its measurements from a measurement file (`.slm`), chosen with
File → Measurements → Open Set… (++ctrl+m++), or a new one made with New
Set…. In a formula a measurement is written with `@`: `@waist`,
`@waist_to_hip`. The Measurements tab lists the file's values; a key the
pattern uses that the file lacks is shown in red as Missing.

A value or description can be changed in the Measurements tab's list, and a
missing key given a value there; Add makes a new key. These edits belong to
the measurement file, not the pattern, so they are not undo steps: they show
in bold until Save writes them to the file, and Revert drops them. The pattern
uses them once they are saved. If you would lose them, by opening another file
or closing the app, you are asked whether to save them. Anything else, such as
sizes or deleting keys, is done in the measurements app: File → Measurements →
Edit in Measurements App….

Swap in another person's file, or another size, and the whole pattern redraws.
To see how the pattern behaves a size up or down without changing any file,
move the slider at the bottom of the Measurements tab; Reset puts it back. The
list cannot be edited while the slider is away from 0%, and the slider waits
while there are unsaved edits.

## Variables

A variable holds a value used in more than one place, such as the ease, and is
written with `#`: `#hip_ease`. In the Variables tab click Add, type its name
and press ++enter++, then type its formula in the Formula cell. Name, formula
and description are all edited in the list, and each change is one undo
step. A variable can read measurements and
other variables, but not points or edges.

## Reading objects

A formula can read a point's place or an edge's length and angle, by the
object's name and a property: `B.x`, `Waist_line.length`, `Line_A_B.angle`.
Square to a line is its angle plus 90: `Line_A_B.angle + 90`. Each object's
properties are listed in [Operations and objects](../reference/operations.md).

## Typing formulas

As you type, the field suggests names: after `@` the measurements, after `#`
the variables, after an object's name and a dot its properties.
++ctrl+space++ shows everything. ++enter++ or ++tab++ takes a suggestion.

A formula that cannot be worked out, such as one naming something that does
not exist, is refused: its text is kept, the reason shows in red under the
field, and the cursor is put at the problem.

Names are case-insensitive and stay correct when you rename something:
formulas store the object, not its name. The functions, operators and units
formulas can use are listed in
[Formula functions and units](../reference/functions.md).

## Units

Each pattern has a unit, mm, cm or inches, and every plain number in its
formulas is in that unit: in an inch pattern, `@waist / 4 + 1` adds one inch.
A new pattern takes the unit set in Edit → Preferences. A number can carry its
own unit, `400mm`, `1.5cm` or `2in`, and then means the same in any pattern.

Tools → Convert Pattern Units… changes a pattern's unit. It rewrites only the
numbers that are lengths, not counts, ratios or angles, and asks about any
number it cannot tell, such as `400 * 2`.

## When something goes wrong

An object that cannot be worked out is drawn red, at its last good place, and
those that depend on it orange. Hover over it, or select it, to see why. The
Objects tab's Problems filter lists them all.
