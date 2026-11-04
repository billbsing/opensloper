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

// Tooltips go above the mouse pointer rather than below it, so they do not
// cover the buttons and fields under the pointer's path. Shared by all the
// GUI programs; a hint that would go off the top of the screen stays below.
unit Sloper.UI.HintPlacement;

{$mode ObjFPC}{$H+}

interface

// Call once, after Application.Initialize
procedure PlaceHintsAboveCursor;

implementation

uses
  Classes, SysUtils, Types, Controls, Forms;

const
  // Space between the hint and the pointer's tip, at 96 dpi
  HintGap96 = 4;

type
  THintPlacer = class(TComponent)
  private
    // Never shown: only measures hints, in the same class as the real window
    FMeasure: THintWindow;
    procedure ShowHint(var HintStr: string; var CanShow: boolean; var HintInfo: THintInfo);
  end;

procedure THintPlacer.ShowHint(var HintStr: string; var CanShow: boolean; var HintInfo: THintInfo);
var
  HintRect: TRect;
  Pointer: TPoint;
  Top: integer;
  Monitor: TMonitor;
begin
  if not CanShow or (HintStr = '') then
    Exit;
  if Assigned(FMeasure) and (FMeasure.ClassType <> HintInfo.HintWindowClass) then
    FreeAndNil(FMeasure);
  if not Assigned(FMeasure) then
    FMeasure := THintWindowClass(HintInfo.HintWindowClass).Create(Self);
  HintRect := FMeasure.CalcHintRect(HintInfo.HintMaxWidth, HintStr, HintInfo.HintData);
  Pointer := Mouse.CursorPos;
  Top := Pointer.Y - HintRect.Height - Round(HintGap96 * Screen.PixelsPerInch / 96);
  Monitor := Screen.MonitorFromPoint(Pointer);
  if not Assigned(Monitor) or (Top >= Monitor.WorkareaRect.Top) then
    HintInfo.HintPos.Y := Top;
end;

procedure PlaceHintsAboveCursor;
var
  Placer: THintPlacer;
begin
  // Owned by the application, which also drops the handler when it goes
  Placer := THintPlacer.Create(Application);
  Application.AddOnShowHintHandler(@Placer.ShowHint);
end;

end.
