# Known issues

## Clipper2 offset depends on the caller's compiler options

Found 2026-10-28 while setting up the test project.

`InflatePaths` on a 100 × 100 mm square with delta 10 and `jtMiter` should return one 120 × 120 mm square. When the *calling* unit is compiled with range checks (`-Cr`), it returns four 10 × 10 mm squares at the corners instead. The Clipper2 units can be precompiled without any checks and it still happens.

- Same result with Clipper2 1.5.4 and 2.0.1 (`packages/clipper2`), FPC 3.2.2 and FPC 3.3.1.
- Clipper2 built with `-gt` (trash local variables) also fails; `-Co`, `-Ci`, `-Ct`, `-Sa` and heaptrc do not.
- Clipper2 built with `-O2` or `-O3` hides it; `-O-` and `-O1` do not.
- Adding one `WriteLn` inside `InflatePaths` hides it. valgrind reports no errors.

This points at Clipper2 reading memory whose contents depend on stack layout (an uninitialised value, or a managed function result that is not cleared before use) rather than at our code. The FPC build of Clipper2 issues many "function result variable of a managed type does not seem to be initialized" warnings in `Clipper.Core.pas`, which are the first place to look.

Also seen while reading `Clipper.Offset.pas` (`TClipperOffset.ExecuteInternal`): the zero-delta branch copies `group.paths[i]` inside a `j` loop; it should be `group.paths[j]`.

`tests/testclipper.pas` keeps the reproducing test, marked `Ignore` so it shows in every run without blocking commits. Fix upstream, bump the submodule, then remove the `Ignore` line.

Minimal reproduction (compile with `fpc -Cr -Fu<Clipper2Lib>`):

```pascal
program t;
{$mode objfpc}{$H+}
uses Clipper, Clipper.Core;
var Sq, R: TPathsD;
begin
  SetLength(Sq, 1);
  Sq[0] := MakePathD([0, 0, 100, 0, 100, 100, 0, 100]);
  R := InflatePaths(Sq, 10, jtMiter, etPolygon);
  WriteLn(Length(R));  // 1 expected; prints 4 with -Cr
end.
```

## fpcupdeluxe Lazarus 4.99 in ~/Packages/fpc_build: lazbuild fails

`~/Packages/fpc_build/lazarus/lazbuild` stops before reaching any project with `The package "IdeSynedit" is installed but no valid package file (.lpk) was found`, even with a fresh `--pcp` folder. This is the trunk install, not this project: `ide/packages/idesynedit/idesynedit.lpk` was added upstream on 2026-07-19 and the `lazbuild` binary probably predates it. Rebuilding Lazarus in fpcupdeluxe should fix it. Until then the system Lazarus 4.8 / FPC 3.2.2 is used; `build.local.sh.example` shows how to point the scripts at another toolchain.
