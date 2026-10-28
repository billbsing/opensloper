# Known issues

## Clipper2 offset depends on the caller's compiler options

Found 2026-10-28 while setting up the test project.

`InflatePaths` on a 100 × 100 mm square with delta 10 and `jtMiter` should return one 120 × 120 mm square. Depending on unrelated compiler options (range checks or `-gt` in the calling code, `-O1` in Clipper2) it returns four 10 × 10 mm corner pieces instead. Seen with Clipper2 1.5.4 and 2.0.1, FPC 3.2.2 and 3.3.1.

**Cause.** `GetLowestPolygonInfo` in `Clipper.Offset.pas` uses `MaxDouble` as a "not computed yet" marker:

```pascal
a := MaxDouble;
...
if a = MaxDouble then   // never true on x86_64 Linux
begin
  a := Area(paths[i]);
  IsNegArea := a < 0;
end;
```

On FPC for x86_64 Linux, `Extended` is 80-bit, so the untyped constant `MaxDouble` is compared at extended precision and never equals a `Double` holding it. The block never runs and the `out` parameter `IsNegArea` keeps whatever was in that memory. When that junk reads as true, the group is treated as reversed, the polygon is offset inwards and the cleanup union leaves the corner pieces. On Windows x64 `Extended` is `Double`, so Delphi does not show it. `GetBounds(TPathsD)` in `Clipper.Core.pas` uses the same `= MaxDouble` test to detect empty input.

**Fix.** Use a Boolean flag instead of the sentinel and initialise `IsNegArea`; in `GetBounds` test `Result.Left > Result.Right`. The same commit also fixes `group.paths[i]` → `group.paths[j]` in the zero-delta branch of `TClipperOffset.ExecuteInternal`.

The fix is on branch `fix-maxdouble-sentinel` of the fork `github.com/billbsing/Clipper2`, and `packages/clipper2` points at that fork until upstream takes the fix. `tests/testclipper.pas` (`TestMitredSquareOffset`) covers it. Once upstream merges it, point the submodule back at `github.com/AngusJohnson/Clipper2`.

## fpcupdeluxe Lazarus 4.99 in ~/Packages/fpc_build: lazbuild fails

`~/Packages/fpc_build/lazarus/lazbuild` stops before reaching any project with `The package "IdeSynedit" is installed but no valid package file (.lpk) was found`, even with a fresh `--pcp` folder. This is the trunk install, not this project: `ide/packages/idesynedit/idesynedit.lpk` was added upstream on 2026-07-19 and the `lazbuild` binary probably predates it. Rebuilding Lazarus in fpcupdeluxe should fix it. Until then the system Lazarus 4.8 / FPC 3.2.2 is used; `build.local.sh.example` shows how to point the scripts at another toolchain.
