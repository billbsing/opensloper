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

// What the Garment View window says about a view. Kept free of the LCL so it
// can be unit-tested.
unit Sloper.UI.GarmentNotes;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Garment;

// One line each
function GarmentNotes(const Drawing: TGarmentDrawing; const SideName: string): TStringArray;

resourcestring
  rsGarmentUnjoined = '%s: no seam joins %s';
  rsGarmentOneSided = '%s: no fold or centre seam, so mirrored pieces show one side only';

implementation

function GarmentNotes(const Drawing: TGarmentDrawing; const SideName: string): TStringArray;
var
  PieceName: string;
begin
  Result := nil;
  for PieceName in Drawing.Unjoined do
    Insert(Format(rsGarmentUnjoined, [SideName, PieceName]), Result, Length(Result));
  if Drawing.OneSided then
    Insert(Format(rsGarmentOneSided, [SideName]), Result, Length(Result));
end;

end.
