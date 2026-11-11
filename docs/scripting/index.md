# Scripting

`opensloper-cli serve` lets a program draft and change patterns: a script that
makes a family of patterns, a test, or an assistant such as Claude. It does
everything through the same steps as the design window, so names, formulas and
undo follow the same rules, and a script cannot make a pattern the window could
not open.

Every method, with its parameters and what it returns, is on the
[Automation API](../reference/api.md) reference page. This page shows how to use
them.

## How it talks

`serve` reads [JSON-RPC 2.0](https://www.jsonrpc.org/specification) requests on
standard input, one to a line, and writes each answer on a line of standard
output. It has no window and keeps one pattern open at a time. Try it by hand:

```
$ opensloper-cli serve
{"jsonrpc": "2.0", "id": 1, "method": "add_point", "params": {"type": "freePoint", "name": "A", "x": "0", "y": "0"}}
{ "jsonrpc" : "2.0", "id" : 1, "result" : { "id" : 1, "name" : "A", "type" : "freePoint", "state" : "valid", "x" : 0, "y" : 0, "formulas" : { "x" : "0", "y" : "0" } } }
```

It stops at the end of its input (++ctrl+d++ when typing). A request with no
`id` is a notification: it is carried out and gets no answer.

## The Python client

[`opensloper.py`](../reference/opensloper.py) is a small Python module that
starts `serve` and gives each method as a Python method, with its parameters
and their descriptions, so an editor can complete them. It is written from the
program's own list of methods, so it always matches the version it came with.
Download it into the folder of your script; it needs Python 3.8 or later and
nothing else.

- `OpenSloper()` starts `opensloper-cli` from your `PATH`, or the program the
  `OPENSLOPER_CLI` environment variable names. Use it in a `with` block, which
  stops the server at the end.
- Parameters a method needs come first, in order or by name; the others are
  given by name. The object a method acts on is given by its ID (a number) or
  its name.
- `add_point` and `add_edge` take the type's members as named parameters, as on
  the [operations page](../reference/operations.md).
- A refused call raises `OpenSloperError`, with the error's `code`, `message`,
  `field` and `position`.
- `call("method", {...})` sends any method by name, with its parameters as a
  dictionary.

Other languages talk to `serve` directly, a line of JSON each way, as
[How it talks](#how-it-talks) shows.

## A first script

This Python script drafts half a gathered skirt from the example
[size table](../getting-started/examples.md), checks it, draws it and saves it.
Run it in a folder holding `opensloper.py` and a copy of the example
`measurements` folder, with `opensloper-cli` on your `PATH`.

```python
import json

from opensloper import OpenSloper

# A new pattern in cm that uses the example size table
with open("gathered-skirt.sloper", "w", encoding="utf-8") as f:
    json.dump({"format": "pattern", "version": 1, "units": "cm",
               "measurementFile": "measurements/size-table.slm"}, f)

with OpenSloper() as sloper:
    sloper.open("gathered-skirt.sloper", size="12")

    sloper.add_variable("fullness", "1.5", description="Skirt width at the waist, times the hip")
    sloper.add_variable("hem", "4", description="Hem depth, turned up")

    # Half the skirt: a rectangle from the waist at centre front to the hem at the side
    sloper.add_point("freePoint", name="A", x="0", y="0")
    sides = sloper.add_rectangle("A", "@hip_circumference / 2 * #fullness", "@waist_to_knee + #hem", role="outline")
    waist, side, hem, centre = [edge["name"] for edge in sides]
    sloper.rename(waist, "Waist")
    sloper.rename(centre, "Centre_front")
    sloper.rename(hem, "Hem")

    # Pieces are found from a place inside the outline, given in mm
    sloper.create_piece(50, 50, name="Skirt", allowance="1.5")
    sloper.set_fold("Skirt", edge="Centre_front")
    sloper.set_cut("Skirt", 2)
    sloper.set_edge_allowance("Skirt", "Hem", allowance="1")

    # Check it, look at it and keep it
    problems = sloper.evaluate()["problems"]
    print("Problems:", problems or "none")
    print("Waist to gather:", round(sloper.get_object("Waist")["length"]), "mm")
    with open("gathered-skirt.svg", "w", encoding="utf-8") as f:
        f.write(sloper.render(labels=True)["svg"])
    sloper.save()
```

It prints:

```
Problems: none
Waist to gather: 735 mm
```

and leaves `gathered-skirt.sloper`, which opens in the design window like any
other pattern, and `gathered-skirt.svg`, a picture of the draft. Change
`fullness` in the Variables tab, or the size, and the skirt follows: the script
wrote formulas, not numbers.

## Things to know

**Starting a pattern.** `serve` starts with an empty pattern in mm, which can
be built and then saved with `save` and a `path`. No method gives a pattern its
measurement file, so to use measurements, write a small starting file as the
script does, with the `units` and `measurementFile` you want, and `open` it.
`convert_units` changes the unit of the pattern that is open.

**Naming objects.** Objects are given by `id` or by `name`, in parameters such
as `base` and in formulas, as in the window. A point or edge left unnamed gets
the next free name, so name what you will use later, or take the name from the
answer: every method that makes something answers with it.

**Units.** Formulas and variable values are in the pattern's unit, as in the
window. Positions and lengths in answers, and the place given to
`create_piece`, are always mm.

**Methods that make several objects.** `add_rectangle` answers with its four
lines, clockwise from the top: top, right, bottom and left. `split_edge`
answers with the two parts. `round_corner` splits both edges and answers with
the arc only; the parts it keeps, which are what a piece or a second corner
then uses, are the newest objects in `list_objects`. An edge that has been
split stays, as construction, and the parts take its place in pieces and seams.

**Errors.** A refused call answers with an `error` instead of a `result`, and
nothing is changed:

```
{ "jsonrpc" : "2.0", "id" : 5, "error" : { "code" : -32000, "message" : "The formula ends too soon", "data" : { "field" : "length", "position" : 5 } } }
```

`data` names the field and the place in the formula, counted from 1; the Python
client raises it as `OpenSloperError`. Check the
`code`, not the message, which may be translated: -32000 is a call that was
understood and refused, such as an unknown name or a formula that does not
read; the others are listed on the reference page. An object whose formulas
read but cannot be worked out, such as a line between two points in the same
place, is made, and the answer gives its `state`, such as `invalid`, with a `message`
saying why. `evaluate` lists every
such problem, gaps in pieces and seams out of tolerance.

**Undo.** Every change is one step on the pattern's undo history, and `undo`
and `redo` work as in the window.

**Looking at the result.** `render` answers with the draft as SVG, as the
window draws it, or with `"format": "png"` as a PNG image (base64, `width`
pixels across), so a script or an assistant can see a curve or a dart and not
only its numbers. `check` gives every computed value.

**What it will write.** `save` writes only `.sloper` files and never replaces a
file that is not a pattern; `export` writes only a file with its format's
extension; `set_measurement` writes only the pattern's own measurement file.

## Without a script

For one-off jobs the command line may be enough:
[`opensloper-cli check`](../reference/cli.md) reports a pattern's problems and
exits with 1 when it has any, so it suits a build or a test, and `export-draft`
draws a pattern as SVG, or as PNG with `--format=png`.

## With Claude

`serve` is also a [Model Context Protocol](https://modelcontextprotocol.io)
server, so Claude can use the methods above as tools: draft, check and fix a
pattern, and look at `render` with `"format": "png"`, which Claude receives as
an image, to see what it made. To add it to Claude Code:

```
$ claude mcp add opensloper -- /path/to/opensloper-cli serve
```

For Claude Desktop, add it to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "opensloper": {
      "command": "/path/to/opensloper-cli",
      "args": ["serve"]
    }
  }
}
```

Each method is a tool of the same name, with the parameters on the
[reference page](../reference/api.md). A refused call comes back to Claude as
the error above, so it can read why and try again. Claude works on its own copy
of the pattern, as a script does, and changes your file only when it calls
`save`; open the file in the design window afterwards to see the result.

The [File formats](../reference/files.md) page and its schemas describe the
files, so Claude can also read and write them directly. Connecting Claude to
the design window, so that you watch its changes and undo them, is planned.
