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

Fixed on `main` of our fork `github.com/billbsing/Clipper2`, which `src/packages/clipper2` uses. Upstream has a large backlog, so we stay on the fork rather than wait for a merge; the fix can still be offered upstream as a pull request. `tests/sloper.tests.clipper.pas` (`TestMitredSquareOffset`) covers it.

## fpcupdeluxe Lazarus 4.99 in ~/Packages/fpc_build: lazbuild fails

`~/Packages/fpc_build/lazarus/lazbuild` stops before reaching any project with `The package "IdeSynedit" is installed but no valid package file (.lpk) was found`, even with a fresh `--pcp` folder. This is the trunk install, not this project: `ide/packages/idesynedit/idesynedit.lpk` was added upstream on 2026-07-19 and the `lazbuild` binary probably predates it. Rebuilding Lazarus in fpcupdeluxe should fix it. Until then the system Lazarus 4.8 / FPC 3.2.2 is used; `build.local.sh.example` shows how to point the scripts at another toolchain.

## `for … in [ … ]` over string constants loops over characters

Found 2026-11-06 while building annotations stage 2. With FPC 3.2.2 in `{$mode ObjFPC}{$H+}`, a list of string constants in a `for … in` is taken as a set of characters, so each item is cut to its first letter:

```pascal
for Name in ['x', 'position', 'dx'] do   // gives 'x', 'p', 'd'
```

There is no warning. Single-letter names work by chance, which hides it. `TNoteObject.RemovePlaceFields` removed `x` and `y` but never `dx` or `dy`, so re-anchoring a note left its old offset fields behind. A list built from variables, as in `SnapObjectKeys`, is a real string array and works.

**Fix.** Loop over a typed constant array instead (`const Names: array[0..2] of string = (...)`). `TestSetNoteAnchorKeepsText` in `tests/sloper.tests.notes.pas` covers the case.

## Qt: shortcuts do nothing after a menu is closed with Escape

Found 2026-11-07, with Lazarus 4.8, FPC 3.2.2 and Qt 5.15 on Linux (Qt5 widgetset). Not seen on other widgetsets, which were not tried.

**What the user sees.** Open a menu with the mouse (say Edit) and close it with Escape. Ctrl+Q, Ctrl+Z and the tool keys (P, L, …) then do nothing until Escape is pressed a second time or the canvas is clicked. Nothing on screen shows why: the menu bar is not highlighted.

**To reproduce.** Open any pattern, click Edit, press Escape, press Ctrl+Q: the app stays open. Press Escape again, then Ctrl+Q: it quits. Builds from before copy and paste (`74e7db9`) behave the same, so it is not from our recent changes.

**Cause, in two parts.**

1. *Qt.* Escape closes the menu but leaves the menu bar in keyboard navigation mode with the keyboard focus (`QMenuBarPrivate::setKeyboardMode` in `qmenubar.cpp`; Down opens the menu again). A second Escape ends the mode. This is ordinary Qt behaviour. A key the menu bar does not use, such as Ctrl+Q, it ignores (`QMenuBar::keyPressEvent` ends with `e->ignore()`), and `QApplication::notify` passes it on to the parent widget, our main window.
2. *LCL.* The key reaches the main window as a **non-spontaneous** event (seen with an application-wide Qt event filter: the menu bar gets it spontaneous, the `QMainWindow` gets it non-spontaneous). `TQtMainWindow.EventFilter` hands key events to `TQtWidget.EventFilter`, which drops every non-spontaneous key event outside edit controls (`qtwidgets.pas`, around line 2754: "non-spontaneous key events are garbage in Qt >= 4.4 for non edits"). So the shortcut never reaches the LCL, and no `OnKeyDown`, `KeyPreview` or action list sees it.

**What we fixed in OpenSloper** (`fc7c9d4`). Clicking the canvas did not end the mode either, because `TCustomForm.SetActiveControl` returns early when the canvas is already the active control (`customform.inc`), so the canvas's `SetFocus` never reached Qt. The drafting canvas (`TPatternCanvas.TakeFocus`) and the publish preview canvas now ask the widgetset for the focus directly (`LCLIntf.SetFocus`) when they do not really have it. A click on the canvas now gives shortcuts back.

**Not fixed: Escape followed straight away by a shortcut.** It needs a change in the LCL, which we do not patch locally (CI and users build with release Lazarus). A tested patch, for a Lazarus bug report or merge request: in `lcl/interfaces/qt5/qtwidgets.pas`, `TQtMainWindow.EventFilter`, add a case before `QEventWindowUnblocked`:

```pascal
      QEventKeyPress,
      QEventKeyRelease:
      begin
        {A key that the menu bar did not use, such as a shortcut pressed while
         the menu bar has the keyboard after Escape closed one of its menus.
         Qt passes it on to the window as a non-spontaneous event, which
         TQtWidget.EventFilter drops, so the shortcut would be lost.}
        if not QEvent_spontaneous(Event) and Assigned(FMenuBar) and
          (QApplication_focusWidget() = FMenuBar.Widget) then
          Result := SlotKey(Sender, Event) or (LCLObject is TCustomControl)
        else
          Result := inherited EventFilter(Sender, Event);
      end;
```

It was built into a private copy of Lazarus 4.8 and tried on Xvfb: after Escape, Ctrl+Q, Ctrl+Z and tool keys worked from the File and Edit menus, keys still reached the canvas as before, and Down still opened the menu from keyboard mode. The `qt6` widgetset's `qtwidgets.pas` drops non-spontaneous key events the same way (also around line 2754), so it probably needs the same change; that was not tried. Until Lazarus has a fix, the workaround is a second Escape or a click on the canvas.
