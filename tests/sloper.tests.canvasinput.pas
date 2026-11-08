{
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

// Tests for what the canvas's mouse buttons and keys may start mid-gesture
unit Sloper.Tests.CanvasInput;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.UI.CanvasInput;

type
  TTestCanvasInput = class(TOSTestCase)
  private
    function Idle: TCanvasInput;
    function Dragging: TCanvasInput;
  published
    procedure TestIdlePressGoesToTool;
    procedure TestMiddlePressPans;
    procedure TestLeftPressWithSpacePans;
    procedure TestMiddlePressDuringDragIsIgnored;
    procedure TestRightPressDuringDragIsIgnored;
    procedure TestLeftPressDuringPanIsIgnored;
    procedure TestOnlyGestureButtonHoldsIt;
    procedure TestPressOfHeldButtonMeansLostRelease;
    procedure TestIdleHoldsNoButton;
    procedure TestKeysWaitForGesture;
    procedure TestLosingFocusReleasesSpace;
    procedure TestPlainKey;
  end;

implementation

function TTestCanvasInput.Idle: TCanvasInput;
begin
  Result := Default(TCanvasInput);
end;

function TTestCanvasInput.Dragging: TCanvasInput;
begin
  Result := Idle;
  AssertTrue(Result.Press(cbLeft) = paTool);
  Result.Mode := cmDragging;
end;

procedure TTestCanvasInput.TestIdlePressGoesToTool;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  AssertTrue(Input.Press(cbLeft) = paTool);
  AssertTrue('the tool sets the mode', Input.Mode = cmIdle);
  Input := Idle;
  AssertTrue(Input.Press(cbRight) = paTool);
end;

procedure TTestCanvasInput.TestMiddlePressPans;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  AssertTrue(Input.Press(cbMiddle) = paPan);
  AssertTrue(Input.Mode = cmPanning);
end;

procedure TTestCanvasInput.TestLeftPressWithSpacePans;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  Input.SpaceDown := True;
  AssertTrue(Input.Press(cbLeft) = paPan);
  AssertTrue(Input.Mode = cmPanning);
end;

// Review finding: panning mid-drag left the drag's document change open
procedure TTestCanvasInput.TestMiddlePressDuringDragIsIgnored;
var
  Input: TCanvasInput;
begin
  Input := Dragging;
  AssertTrue(Input.Press(cbMiddle) = paIgnore);
  AssertTrue(Input.Mode = cmDragging);
  Input.SpaceDown := True;
  AssertTrue('Space+left is the drag''s own button', Input.Holds(cbLeft));
end;

procedure TTestCanvasInput.TestRightPressDuringDragIsIgnored;
var
  Input: TCanvasInput;
begin
  Input := Dragging;
  AssertTrue(Input.Press(cbRight) = paIgnore);
  AssertTrue(Input.Mode = cmDragging);
end;

procedure TTestCanvasInput.TestLeftPressDuringPanIsIgnored;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  Input.Press(cbMiddle);
  AssertTrue(Input.Press(cbLeft) = paIgnore);
  AssertTrue(Input.Mode = cmPanning);
end;

procedure TTestCanvasInput.TestOnlyGestureButtonHoldsIt;
var
  Input: TCanvasInput;
begin
  Input := Dragging;
  AssertTrue(Input.Holds(cbLeft));
  AssertFalse('a middle release does not end a left drag', Input.Holds(cbMiddle));
  AssertFalse(Input.Holds(cbRight));
end;

procedure TTestCanvasInput.TestPressOfHeldButtonMeansLostRelease;
var
  Input: TCanvasInput;
begin
  Input := Dragging;
  AssertTrue(Input.Holds(cbLeft));
  // The canvas ends the gesture, then takes the press
  Input.Mode := cmIdle;
  AssertTrue(Input.Press(cbLeft) = paTool);
end;

procedure TTestCanvasInput.TestIdleHoldsNoButton;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  AssertFalse(Input.Holds(cbLeft));
  Input.Press(cbLeft);
  AssertFalse('a click with no gesture holds nothing', Input.Holds(cbLeft));
end;

// Review findings: nudge and delete mid-drag opened a second change, and tool
// keys switched the tool mid-press or mid-box
procedure TTestCanvasInput.TestKeysWaitForGesture;
var
  Input: TCanvasInput;
  Mode: TCanvasMode;
begin
  Input := Idle;
  AssertTrue(Input.TakesKeys);
  for Mode := Succ(cmIdle) to High(TCanvasMode) do
  begin
    Input.Mode := Mode;
    AssertFalse(Input.TakesKeys);
  end;
end;

// Review finding: Space released after focus left kept the canvas panning
procedure TTestCanvasInput.TestLosingFocusReleasesSpace;
var
  Input: TCanvasInput;
begin
  Input := Idle;
  Input.SpaceDown := True;
  Input.LoseFocus;
  AssertFalse(Input.SpaceDown);
  AssertTrue(Input.Press(cbLeft) = paTool);
end;

// Review finding: Shift+Delete deleted without copying
procedure TTestCanvasInput.TestPlainKey;
begin
  AssertTrue(IsPlainKey([]));
  AssertTrue('lock keys do not count', IsPlainKey([ssNum, ssCaps]));
  AssertTrue('mouse buttons do not count', IsPlainKey([ssLeft]));
  AssertFalse(IsPlainKey([ssShift]));
  AssertFalse(IsPlainKey([ssAlt]));
  AssertFalse(IsPlainKey([ssMeta]));
  AssertFalse(IsPlainKey([ssAltGr]));
end;

initialization
  RegisterTest(TTestCanvasInput);

end.
