# OpenSloper coding standards

How OpenSloper's Pascal code is named, laid out and formatted. Architecture rules (layers, IDs, commands, evaluation states) are in `CLAUDE.md` and the design document.

## Formatting

Code is formatted with JEDI Code Format (JCF), the formatter built into the Lazarus IDE, using the project settings in `jcfsettings.cfg`.

- **From the command line:** `./format.sh` formats every source file; `./format.sh --check` lists files that need formatting without changing them; `./format.sh FILE...` formats only those files. Run it before committing.
- **In the IDE:** use the same settings, so the IDE and `format.sh` agree. Copy `jcfsettings.cfg` over the IDE's copy in the Lazarus configuration folder (for the fpcupdeluxe install, `~/Packages/fpc_build/config_lazarus/jcfsettings.cfg`), then use Source → JEDI Code Format → Format Current Editor Window.
- **Formatter version:** `format.sh` builds the command-line formatter into `lib/jcf` on first use, from the Lazarus source in `JCF_SOURCE` (set in `build.local.sh`). Use the Lazarus version the IDE runs, so both produce the same layout. Delete `lib/jcf` to rebuild it.
- **Not formatted:** `packages/` (third-party code) and `src/core/clipper2/osclipper2.pas`, which Lazarus regenerates.

What the settings produce:

| Rule | Setting |
| --- | --- |
| Indentation | 2 spaces, no tabs; procedure bodies not indented further |
| `begin` / `end` | On their own line, at the indentation of the statement they belong to; in a `case`, a branch's `begin` lines up with its label |
| Line length | At most 164 characters; longer lines are broken at a parameter or operator, with the continuation indented 2 more |
| Line breaks you add | Kept: the formatter does not join lines in expressions, parameter lists or `var` sections, so long string expressions and argument lists can be laid out one part per line |
| Operators | `and`, `or`, `+` and other binary operators end a broken line rather than start the next one |
| Spacing | One space around operators and `:=`, after commas and semicolons; none before `(` in calls and declarations, none inside brackets |
| Blank lines | One before each routine; at most two in a row; none at the start of `var` sections or procedure headers |
| Alignment | No column alignment of assignments, declarations or comments |
| Reserved words and directives | Lower case: `begin`, `function`, `override` |
| Built-in types | Lower case: `double`, `integer`, `boolean`, `char`, `byte`, `string` |
| Constants | `True`, `False` and `nil` keep their case |
| Program `uses` | One unit per line |

The project settings are the IDE's own settings with four changes: `RemoveExpressionReturns`, `RemoveProcedureDefReturns` and `RemoveVarReturns` are off, so deliberate line breaks survive, and `WhenRebreakLines` is 1, so lines over 164 characters are broken.

## Naming

- **Descriptive names.** No single-letter variables or parameters: `Index`, not `I`; `Node`, not `N`; `Failure`, not `E`. A name says what the value is (`StartPos`, `LengthOrDx`, `TokenIndex`), not just its type.
  - Exceptions: the core math units (`Sloper.Core.Geometry`, `Sloper.Core.Bezier`, `Sloper.Core.Numeric`), where single letters (`P`, `T`, `A`, `B`) match the formulas and read better; and `tests/`.
- **Parameters that would clash take an `A` prefix.** When a parameter's plain name matches a field, property or method of the class (`AName`, `AEdge`, `AKey`, `AValue`), prefix it with `A`. Free Pascal refuses a local or parameter with the same name as a member. Locals use plain descriptive names instead (`EdgeObject`, `PointPos`).
- **Fields** start with `F` and are private; expose them through properties.
- **Types** start with `T`, exception classes with `E`; enumeration values carry a short lower-case prefix (`esValid`, `omPolar`, `pdAngle`).
- **Units** are named `Sloper.<Area>.<Name>`, where the area is the folder: `Sloper.Core.Formula` (`src/core`), `Sloper.Document.…` (`src/document`), `Sloper.UI.MainForm` (`src/ui`), `Sloper.Output.…` (`src/output`) and `Sloper.Tests.Pattern` (`tests`). File names are the unit name in lower case (`sloper.core.formula.pas`).
- **Resource strings** start with `rs` and the unit's area (`rsFormulaEmpty`, `rsDraftPastEnd`).
- **IDs and names** follow the project's name rules (see `CLAUDE.md`): letters, digits and underscore, compared without regard to case.

## Other conventions

- Every unit starts with the GPLv3 header from `documents/gpl-header.txt`, then a short comment saying what the unit is for.
- Units start with `{$mode ObjFPC}{$H+}`.
- Comments explain why, or what is not obvious; they don't restate the code.
- Free objects with `FreeAndNil(Obj)`, never `Obj.Free` or `Obj.Destroy`, so a reference is either `nil` or a live instance (see [Modern Object Pascal](https://castle-engine.io/modern_pascal)). It does not clear other copies of the reference. The one exception is a typecast list item (`TObject(List[Index]).Free`), which cannot be passed to `FreeAndNil`; clear the list straight after.
- Recursion inside a function needs brackets: in ObjFPC mode a bare `ParseUnary` inside `ParseUnary` means the result variable, so write `ParseUnary()`.
- Don't index an array with a call that can grow it (`Tokens[Add(...)] := ...`): Free Pascal may take the array's address before the call reallocates it. Store the index first.
- Compare floats with a tolerance, and never compare a `double` with an untyped float constant such as `MaxDouble`: on x86_64 Linux the constant is evaluated as 80-bit `Extended` and never equals the `double` (see `documents/known-issues.md`).
