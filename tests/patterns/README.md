# Regression patterns

Sample patterns with measurement sets, and the expected computed values for each combination. `Sloper.Tests.Regression` evaluates every case again and compares it with the expected file, so any change that silently alters a draft fails.

| File | What it is |
| --- | --- |
| `<pattern>.sloper` | A pattern |
| `<set>.slm` | A measurement set |
| `<pattern>.<set>.expected.json` | The report for that pattern with that set: each variable's value and each object's state with its position or length, rounded to 1e-6 mm |

Current cases:

- `skirt-block.sloper`: a straight skirt block, half back and front, using every point and edge operation, including split parts of split parts. Sets: `skirt-small.slm`, `skirt-large.slm`.

## Adding or updating a case

Expected files are written by the CLI. Check the values by hand before committing them: spot-check points you can work out on paper.

```
./build.sh
cd tests/patterns
../../cli/opensloper-cli check skirt-block.sloper -m skirt-small.slm             # must report no problems
../../cli/opensloper-cli check skirt-block.sloper -m skirt-small.slm --json > skirt-block.skirt-small.expected.json
```

Only regenerate an expected file when the change in values is intended, and say why in the commit message.
