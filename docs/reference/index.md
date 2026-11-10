# Reference

Reference pages list exactly what the program accepts. They are generated from
the program itself, so they always match the version they were built with.

- [Formula functions and units](functions.md): the functions, operators and
  units formulas can use.
- [Operations and objects](operations.md): every kind of point, edge, transform,
  piece, seam and note, with its members as pattern files and the Automation
  API write them.
- [File formats](files.md): pattern, measurement and layout files, member by
  member, with a JSON Schema for each ([pattern](schemas/pattern.schema.json),
  [measurements](schemas/measurements.schema.json),
  [layout](schemas/layout.schema.json)) to check a file against.
- [Keyboard shortcuts](shortcuts.md): the keys and mouse actions of the three
  apps.
- [Command line](cli.md): `opensloper-cli` commands, options and exit codes.
- [Automation API](api.md): the JSON-RPC methods `opensloper-cli serve` answers,
  for scripts and assistants such as Claude, and
  [`opensloper.py`](opensloper.py), a Python client with a method for each.
