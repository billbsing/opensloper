# Size tables

A size table is a measurement file with several sizes, such as `36`, `38` and
`40`, and a value for each measurement in each size. Patterns read it exactly
as they read one person's file: `@waist` is the value in the size chosen.

## Make a size table

In any measurement file, click **Add size…** and name the size. The first size
added to one person's set takes over its values; each later size starts empty.
Sizes are shown as columns of the table, in order.

| Button | What it does |
| --- | --- |
| Add size… | Add a size, named as you like |
| Rename size… | Rename the size whose column you are in |
| Delete size | Delete that size and its values, after asking |
| Size left, Size right | Move that size's column |

A table always keeps at least one size. A cell can be left empty, for a size
that has no value yet.

## Choose a size

Wherever a size table is used, a size is chosen with it:

- **The design app**: the **Size** box in the Measurements tab. It is for the
  session; a pattern opens on the table's first size.
- **The publish app**: the **Size** box in the Patterns tab, for each pattern
  in the layout. The same pattern can be added twice, in two sizes.
- **The command line**: `--size`, as in
  `opensloper-cli check skirt.sloper -m sizes.slm --size=38` (see
  [Command line](../reference/cli.md)).

A pattern that needs a value the chosen size does not have shows the error
"@waist has no value for size 42", and everything that uses it waits until
the value is filled in.

Ease belongs in the pattern, as a `#` variable, not in the size table: the
table holds body or product measurements only.
