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

## A first script

This Python script drafts half a gathered skirt from the example
[size table](../getting-started/examples.md), checks it, draws it and saves it.
Run it in a copy of the `examples` folder, with `opensloper-cli` on your `PATH`.

```python
import json
import subprocess
import sys

# Start opensloper-cli serve; each request and each answer is one line of JSON
server = subprocess.Popen(["opensloper-cli", "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
next_id = 0


def call(method, **params):
    global next_id
    next_id += 1
    request = {"jsonrpc": "2.0", "id": next_id, "method": method, "params": params}
    server.stdin.write(json.dumps(request) + "\n")
    server.stdin.flush()
    answer = json.loads(server.stdout.readline())
    if "error" in answer:
        sys.exit(f"{method} was refused: {answer['error']['message']} {answer['error'].get('data', '')}")
    return answer["result"]


# A new pattern in cm that uses the example size table
with open("gathered-skirt.sloper", "w", encoding="utf-8") as f:
    json.dump({"format": "pattern", "version": 1, "units": "cm",
               "measurementFile": "measurements/size-table.slm"}, f)
call("open", path="gathered-skirt.sloper", size="12")

call("add_variable", name="fullness", formula="1.5", description="Skirt width at the waist, times the hip")
call("add_variable", name="hem", formula="4", description="Hem depth, turned up")

# Half the skirt: a rectangle from the waist at centre front to the hem at the side
call("add_point", type="freePoint", name="A", x="0", y="0")
sides = call("add_rectangle", corner="A", width="@hip_circumference / 2 * #fullness",
             height="@waist_to_knee + #hem", role="outline")
waist, side, hem, centre = [edge["name"] for edge in sides]
call("rename", name=waist, newName="Waist")
call("rename", name=centre, newName="Centre_front")
call("rename", name=hem, newName="Hem")

# Pieces are found from a place inside the outline, given in mm
call("create_piece", x=50, y=50, name="Skirt", allowance="1.5")
call("set_fold", name="Skirt", edge="Centre_front")
call("set_cut", name="Skirt", count=2)
call("set_edge_allowance", name="Skirt", edge="Hem", allowance="1")

# Check it, look at it and keep it
problems = call("evaluate")["problems"]
print("Problems:", problems or "none")
print("Waist to gather:", round(call("get_object", name="Waist")["length"]), "mm")
with open("gathered-skirt.svg", "w", encoding="utf-8") as f:
    f.write(call("render", labels=True)["svg"])
call("save")
server.stdin.close()
server.wait()
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

`data` names the field and the place in the formula, counted from 1. Check the
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
window draws it, so a script or an assistant can see a curve or a dart and not
only its numbers. `check` gives every computed value.

**What it will write.** `save` writes only `.sloper` files and never replaces a
file that is not a pattern; `export` writes only a file with its format's
extension; `set_measurement` writes only the pattern's own measurement file.

## Without a script

For one-off jobs the command line may be enough:
[`opensloper-cli check`](../reference/cli.md) reports a pattern's problems and
exits with 1 when it has any, so it suits a build or a test, and `export-draft`
draws a pattern as SVG.

## With Claude

Claude Code can run `opensloper-cli serve` itself and use the methods above to
draft, check and fix a pattern, looking at `render` to see what it made. The
[File formats](../reference/files.md) page and its schemas describe the files,
so it can also read and write them directly. Connecting Claude to the design
window, so that you watch its changes and undo them, is planned.
