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

// The one spacing the three apps lay controls out with: 8 pixels at 96 per
// inch between neighbouring controls and between a control and the edge of
// its panel or dialog (see Spacing in the design). The Lines tab keeps its
// own, tighter list.
unit Sloper.UI.Spacing;

{$mode ObjFPC}{$H+}

interface

uses
  Controls, ButtonPanel;

// The gap at the screen's resolution
function ControlGap: integer;
// Puts the gap between a container's children and round its edges. The
// parent's spacing is the least a child gets, so a child's own BorderSpacing
// can only add to it, and two neighbours do not add up to twice the gap.
procedure SpaceChildren(Container: TWinControl);
// Only between the children, for a container already inside the gap of the
// one around it
procedure SpaceBetween(Container: TWinControl);
// A dialog's row of OK and Cancel, which keeps its own spacing otherwise
procedure SpaceButtons(Buttons: TButtonPanel);

implementation

uses
  Forms;

const
  CONTROL_GAP96 = 8;

function ControlGap: integer;
begin
  Result := Round(CONTROL_GAP96 * Screen.PixelsPerInch / 96);
end;

procedure SpaceChildren(Container: TWinControl);
begin
  SpaceBetween(Container);
  Container.ChildSizing.LeftRightSpacing := ControlGap;
  Container.ChildSizing.TopBottomSpacing := ControlGap;
end;

procedure SpaceBetween(Container: TWinControl);
begin
  Container.ChildSizing.HorizontalSpacing := ControlGap;
  Container.ChildSizing.VerticalSpacing := ControlGap;
end;

procedure SpaceButtons(Buttons: TButtonPanel);
begin
  Buttons.Spacing := ControlGap;
  Buttons.BorderSpacing.Around := ControlGap;
end;

end.
