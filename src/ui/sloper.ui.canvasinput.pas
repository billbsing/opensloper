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

// What the canvas's mouse buttons and keys may start, given the gesture under
// way. One gesture at a time: a drag holds an open document change, so a
// second press or an editing key must wait for it to end. Kept free of the
// LCL so it can be unit-tested.
unit Sloper.UI.CanvasInput;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes;

type
  // cmRefused: a drag was refused; the reason stays up until the button is released
  // cmBoxing: dragging a selection box from empty canvas or a piece
  TCanvasMode = (cmIdle, cmPressed, cmPanning, cmDragging, cmRefused, cmBoxing);
  TCanvasButton = (cbLeft, cbMiddle, cbRight, cbOther);
  // paTool: the press goes to the tool, which may start a gesture by setting Mode
  TPressAction = (paIgnore, paPan, paTool);

  TCanvasInput = record
  private
    FButton: TCanvasButton;
  public
    // Set by the canvas as a gesture moves on (pressed, dragging); cmIdle ends it
    Mode: TCanvasMode;
    SpaceDown: boolean;
    function Busy: boolean;
    // True when a gesture is under way and Button began it. Only its release
    // ends the gesture; a press of it means that release never arrived (let go
    // outside the window, say), so the gesture is ended before the press is taken
    function Holds(Button: TCanvasButton): boolean;
    // What a press does; a press while a gesture is under way is ignored
    function Press(Button: TCanvasButton): TPressAction;
    // Tool keys, nudges, deleting and seam keys act only between gestures
    function TakesKeys: boolean;
    // The key-ups go elsewhere once focus has moved
    procedure LoseFocus;
  end;

// No Shift, Ctrl, Alt or other modifier held; lock keys and mouse buttons do not count
function IsPlainKey(Shift: TShiftState): boolean;

implementation

const
  NOT_MODIFIERS = [ssLeft, ssRight, ssMiddle, ssDouble, ssTriple, ssQuad, ssExtra1, ssExtra2, ssCaps, ssNum, ssScroll];

function TCanvasInput.Busy: boolean;
begin
  Result := Mode <> cmIdle;
end;

function TCanvasInput.Holds(Button: TCanvasButton): boolean;
begin
  Result := Busy and (Button = FButton);
end;

function TCanvasInput.Press(Button: TCanvasButton): TPressAction;
begin
  if Busy then
    Exit(paIgnore);
  FButton := Button;
  if (Button = cbMiddle) or ((Button = cbLeft) and SpaceDown) then
  begin
    Mode := cmPanning;
    Exit(paPan);
  end;
  Result := paTool;
end;

function TCanvasInput.TakesKeys: boolean;
begin
  Result := not Busy;
end;

procedure TCanvasInput.LoseFocus;
begin
  SpaceDown := False;
end;

function IsPlainKey(Shift: TShiftState): boolean;
begin
  Result := Shift - NOT_MODIFIERS = [];
end;

end.
