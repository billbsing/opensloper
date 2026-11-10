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

// Where the side panel's headers and its one open section go: the open
// section's header and those before it at the top, the open section under
// them, and the headers after it at the bottom. Kept free of the LCL so it
// can be unit-tested.
unit Sloper.UI.AccordionLayout;

{$mode ObjFPC}{$H+}

interface

type
  TAccordionPlaces = record
    // The top of each shown section's header, in order
    HeaderTops: array of integer;
    // The open section's place, under its header; its height is never below 0
    ContentTop, ContentHeight: integer;
  end;

// Places for HeaderCount headers of HeaderHeight in a control Height high,
// with section ActiveIndex open. When the headers do not all fit, the open
// section gets no height and the headers after it run on past the bottom.
function PlaceSections(HeaderCount, ActiveIndex, HeaderHeight, Height: integer): TAccordionPlaces;

implementation

uses
  Math;

function PlaceSections(HeaderCount, ActiveIndex, HeaderHeight, Height: integer): TAccordionPlaces;
var
  Index, BottomStart: integer;
begin
  Result.HeaderTops := nil;
  SetLength(Result.HeaderTops, HeaderCount);
  Result.ContentTop := 0;
  Result.ContentHeight := 0;
  if HeaderCount = 0 then
    Exit;
  ActiveIndex := EnsureRange(ActiveIndex, 0, HeaderCount - 1);
  for Index := 0 to ActiveIndex do
    Result.HeaderTops[Index] := Index * HeaderHeight;
  Result.ContentTop := (ActiveIndex + 1) * HeaderHeight;
  BottomStart := Max(Result.ContentTop, Height - (HeaderCount - 1 - ActiveIndex) * HeaderHeight);
  Result.ContentHeight := BottomStart - Result.ContentTop;
  for Index := ActiveIndex + 1 to HeaderCount - 1 do
    Result.HeaderTops[Index] := BottomStart + (Index - ActiveIndex - 1) * HeaderHeight;
end;

end.
