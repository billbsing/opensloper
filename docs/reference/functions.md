# Formula functions and units

!!! note

    This page is generated from the program by `opensloper-cli doc functions`; do not edit it by hand.

Formulas can use these functions. Angles are in degrees, 0° pointing right and 90° up. Function names are written in lower case and are the same in every language.

| Function | Values | What it gives |
| --- | --- | --- |
| `sin(angle)` | 1 | Sine of an angle in degrees |
| `cos(angle)` | 1 | Cosine of an angle in degrees |
| `tan(angle)` | 1 | Tangent of an angle in degrees |
| `asin(value)` | 1 | The angle, in degrees, whose sine is the value (-1 to 1) |
| `acos(value)` | 1 | The angle, in degrees, whose cosine is the value (-1 to 1) |
| `atan2(dy, dx)` | 2 | The angle, in degrees, of the direction given by dy and dx |
| `sqrt(value)` | 1 | Square root; the value cannot be negative |
| `abs(value)` | 1 | The value without its sign |
| `min(a, b, ...)` | 2 or more | The smallest of two or more values |
| `max(a, b, ...)` | 2 or more | The largest of two or more values |
| `round(value)` | 1 | Rounded to the nearest whole number |

## Operators

In order of precedence, highest first. `^` groups from the right and binds tighter than a leading minus, so `-2^2` is -4.

| Operator | Meaning |
| --- | --- |
| `( )` | Grouping |
| `^` | Power |
| `-` | Minus a value |
| `*` `/` | Multiply and divide |
| `+` `-` | Add and subtract |

## Units

A plain number is in the pattern's unit. A number may carry a unit written straight after it, in any case, and is then converted to the pattern's unit: `400mm`, `1.5cm`, `2in`. A number written with a unit keeps its meaning in every pattern, and Convert Pattern Units leaves it alone.

| Unit | In millimetres |
| --- | --- |
| `mm` | 1 |
| `cm` | 10 |
| `in` | 25.4 |
