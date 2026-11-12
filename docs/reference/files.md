# File formats

!!! note

    This page is generated from the program by `opensloper-cli doc files`; do not edit it by hand.

The apps keep their files as JSON text, so other programs, scripts and assistants such as Claude can read and write them. Each kind of file is described here, and by a JSON Schema that a validator can check a file against.

## Rules for every file

- The file is UTF-8 JSON with one object at the top. Its `format` says what kind of file it is and its `version` which version of that format; a program refuses a file newer than it knows.
- Lengths in measurement and layout files are millimetres. A pattern's formulas are in the pattern's own `units`; a number may also carry its unit, as `2in`.
- Objects have IDs, whole numbers above 0 that never change and are never reused. Other objects and formulas refer to them by ID: a member such as `base` holds the number, and formula text writes it in braces, `{12}`. Names are for people: letters, digits and underscore, not starting with a digit.
- File names inside a file are relative to that file's folder unless absolute, and written with `/`.
- The apps write every member in a fixed order, two spaces to a level, with numbers in the shortest form that reads back exactly and `.` as the decimal point, so files compare well in version control.
- Members marked required must be there for the file to load. Others may be left out of a file written by hand, and take their defaults. A file that does not load says why, and nothing of it is used.
- The schemas list exactly the members the apps write. The apps also read a few members older files have, which the schemas leave out.

## Pattern (`.sloper`)

Made by opensloper-design. It holds the definitions only: the formula for each point and line, and which edges make each piece. Positions are worked out again every time it opens.

Version 1. JSON Schema: [pattern.schema.json](schemas/pattern.schema.json).

| Member | Value | Required | Description |
| --- | --- | --- | --- |
| `format` | one of: `pattern` | yes | What the file is; a file with another value does not load |
| `version` | whole number | yes | The version of the format; a program refuses a file newer than it knows |
| `units` | one of: `mm`, `cm`, `in` |  | The unit of the numbers in formulas |
| `notes` | text |  | Notes about the pattern |
| `measurementFile` | text |  | The measurement file last used with it, relative to the pattern's folder unless absolute, with / between folders; empty when there is none |
| `identity` | text |  | Tells the pattern from others when objects are pasted; made when the pattern is |
| `nextId` | whole number |  | The next ID to hand out, above every ID in the file, so deleted IDs are never reused; when left out, one above the highest ID |
| `variables` | list |  | The # variables, in the order they were made |
| `variables[].id` | whole number | yes | The variable's ID; IDs are unique across variables, materials and objects |
| `variables[].name` | text | yes | The name formulas use after # |
| `variables[].formula` | formula | yes | Its value, in ID form: another object is written {12} |
| `variables[].description` | text |  | What it is for |
| `objects[]` | list, each object |  | The points, edges, transforms, pieces, seams and notes, in the order they were made, each after every object it uses; their members are on the Operations and objects page |
| `materials` | list |  | The materials pieces are cut from; left out while the only one is the untouched Main |
| `materials[].id` | whole number | yes | The material's ID |
| `materials[].name` | text | yes | Its name, unique in the pattern |
| `materials[].color` | text | yes | Its colour, as #RRGGBB |
| `materials[].fill` | one of: `tint`, `hatch` |  | How its pieces are filled on screen and in print |
| `materials[].allowance` | number |  | The seam allowance of its pieces, in the pattern's unit, when it has its own |
| `view` | group |  | How the design app last showed the pattern; not part of undo |
| `view.zoom` | number |  | The zoom |
| `view.centre[]` | list, each number |  | The point in the middle of the window, as x and y in mm |
| `view.hiddenRoles[]` | list, each one of: `construction`, `outline`, `placement`, `stitch`, `fold`, `cut`, `skive`, `edgeFinish` |  | The kinds of line hidden on the canvas |
| `view.hideAnnotations` | true or false |  | Whether notes are hidden |

Each entry in `objects` is an object whose members depend on its `type`; they are listed on [Operations and objects](operations.md).

### Example

```json
{
  "format": "pattern",
  "version": 1,
  "units": "cm",
  "notes": "",
  "measurementFile": "bill.slm",
  "nextId": 6,
  "variables": [
    {
      "id": 1,
      "name": "ease",
      "formula": "2",
      "description": "Ease at the waist"
    }
  ],
  "objects": [
    {
      "id": 2,
      "type": "freePoint",
      "name": "A",
      "x": "0",
      "y": "0"
    },
    {
      "id": 3,
      "type": "offsetPoint",
      "name": "B",
      "base": 2,
      "mode": "polar",
      "length": "@waist / 4 + {1}",
      "angle": "0"
    },
    {
      "id": 4,
      "type": "line",
      "start": 2,
      "end": 3,
      "role": "outline"
    }
  ],
  "materials": [
    {
      "id": 5,
      "name": "Main",
      "color": "#5B8DB8",
      "fill": "tint",
      "allowance": 1.5
    }
  ]
}
```

## Measurements (`.slm`)

Made by opensloper-measurements: one person's measurements, with a value each, or a size table, with a value for each size. Patterns refer to a measurement by its key, as @waist.

Version 1. JSON Schema: [measurements.schema.json](schemas/measurements.schema.json).

| Member | Value | Required | Description |
| --- | --- | --- | --- |
| `format` | one of: `measurements` | yes | What the file is; a file with another value does not load |
| `version` | whole number | yes | The version of the format; a program refuses a file newer than it knows |
| `units` | one of: `mm` |  | Always mm: values in this file are millimetres |
| `name` | text |  | Whose measurements, or the name of the size table |
| `notes` | text |  | Notes, such as how they were taken |
| `sizes[]` | list, each text |  | A size table's sizes, as named; left out for one person's set |
| `measurements` | list | yes | The measurements, in the order shown |
| `measurements[].key` | text | yes | The name patterns use after @; letters, digits and underscore |
| `measurements[].value` | number |  | The value, in a set with no sizes |
| `measurements[].values[]` | list, each number or null |  | In a size table, one value for each size in order; null for a size with no value |
| `measurements[].description` | text |  | What is measured |

### Example

```json
{
  "format": "measurements",
  "version": 1,
  "units": "mm",
  "name": "Block sizes",
  "notes": "",
  "sizes": [
    "36",
    "38"
  ],
  "measurements": [
    {
      "key": "waist",
      "values": [
        700,
        740
      ],
      "description": "Waist circumference"
    },
    {
      "key": "back_length",
      "values": [
        405,
        null
      ],
      "description": "Nape to waist"
    }
  ]
}
```

## Layout (`.slayout`)

Made by opensloper-publish: where the pieces of one or more patterns go on the pages, roll or material, and how they print. Positions are plain numbers in mm, from the top left, y down.

Version 1. JSON Schema: [layout.schema.json](schemas/layout.schema.json).

| Member | Value | Required | Description |
| --- | --- | --- | --- |
| `format` | one of: `layout` | yes | What the file is; a file with another value does not load |
| `version` | whole number | yes | The version of the format; a program refuses a file newer than it knows |
| `units` | one of: `mm` |  | Always mm: values in this file are millimetres |
| `name` | text |  | The layout's name, for the title block |
| `nextId` | whole number |  | The next source ID to hand out |
| `sources` | list | yes | The patterns laid out, each with the measurements to draw it with |
| `sources[].id` | whole number | yes | The source's ID, which placements refer to |
| `sources[].pattern` | text | yes | The pattern file, relative to the layout's folder |
| `sources[].measurementFile` | text |  | The measurement file, relative to the layout's folder; the pattern's own when left out |
| `sources[].size` | text |  | The size, for a size table; its first size when left out |
| `output` | group |  | What the layout prints on and how |
| `output.kind` | one of: `tiled`, `large`, `projector`, `material` |  | tiled: pages taped together; large: a roll; projector: shown on the material; material: a sheet of material for a cutting machine |
| `output.rollWidth` | number |  | The roll's width, for large |
| `output.paper` | text |  | The paper size, A4, A3 or Letter, or a name of your own with its width and height |
| `output.paperWidth` | number |  | The paper's width, for a size of your own |
| `output.paperHeight` | number |  | The paper's height, for a size of your own |
| `output.margin` | number |  | The edge of the paper left blank |
| `output.overlap` | number |  | How far tiles overlap |
| `output.marks` | one of: `diamond`, `none`, `halfCircle` |  | The marks for lining up tiles |
| `output.fill` | one of: `none`, `tint`, `hatch` |  | How pieces are filled; none when left out |
| `output.profile` | text |  | The cutting machine profile, from the settings |
| `output.outputProfile` | text |  | The output profile, from the settings, which chooses what prints |
| `output.materialWidth` | number |  | The material's width, for material |
| `output.materialLength` | number |  | The material's length, for material; 0 or left out for as long as needed |
| `output.allowTurns` | true or false |  | Whether a piece may lie across the grain, for material |
| `output.material` | text |  | Only pieces cut from this material, by name |
| `output.excludedPages[]` | list, each text |  | Pages left out of the print, by their captions |
| `placements` | list |  | Where each copy of each piece lies |
| `placements[].source` | whole number | yes | The source the piece is from |
| `placements[].piece` | whole number | yes | The piece's ID in that source's pattern |
| `placements[].copy` | whole number |  | Which copy, from 1, for a piece cut more than once |
| `placements[].x` | number | yes | The left of the piece's cutting line, after turning and flipping |
| `placements[].y` | number | yes | The top of the piece's cutting line, after turning and flipping |
| `placements[].rotation` | whole number |  | The turn in degrees, a multiple of 90, anticlockwise |
| `placements[].flipped` | true or false |  | Whether the piece is flipped over, before it is turned |
| `sheetNotes` | list |  | Text placed on the sheet, not on a piece |
| `sheetNotes[].text` | text | yes | The text; it may hold fields such as {date} |
| `sheetNotes[].x` | number | yes | Its left |
| `sheetNotes[].y` | number | yes | Its top |
| `sheetNotes[].size` | number |  | Its size in points |
| `sheetNotes[].align` | one of: `left`, `centre`, `right` |  | How its lines line up |
| `sheetNotes[].box` | true or false |  | Whether it has a white box behind it |
| `sheetNotes[].font` | text |  | The font family it prints in; left out for the default sans-serif |
| `sheetNotes[].bold` | true or false |  | Whether it is bold |
| `sheetNotes[].italic` | true or false |  | Whether it is italic |
| `titleBlock` | group |  | The title block; no title block when left out |
| `titleBlock.corner` | one of: `bottomRight`, `bottomLeft`, `topRight` |  | The corner of the page it sits in |
| `titleBlock.fields[]` | list, each one of: `pattern.name`, `measurements.name`, `layout.name`, `date`, `cutlist`, `materials` |  | What it shows, in order |
| `titleBlock.everyPage` | true or false |  | Whether it is on every page, not only the first |

### Example

```json
{
  "format": "layout",
  "version": 1,
  "units": "mm",
  "name": "Skirt, A4",
  "nextId": 2,
  "sources": [
    {
      "id": 1,
      "pattern": "skirt.sloper",
      "measurementFile": "sizes.slm",
      "size": "38"
    }
  ],
  "output": {
    "kind": "tiled",
    "rollWidth": 914,
    "paper": "A4",
    "margin": 6,
    "overlap": 10,
    "marks": "diamond"
  },
  "placements": [
    {
      "source": 1,
      "piece": 42,
      "copy": 1,
      "x": 20,
      "y": 20,
      "rotation": 0,
      "flipped": false
    }
  ],
  "titleBlock": {
    "corner": "bottomRight",
    "fields": [
      "pattern.name",
      "measurements.name",
      "date"
    ],
    "everyPage": false
  }
}
```

