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

// The extent of what a pattern draws, in model millimetres. Objects that are
// failing count at their last good result; objects never computed do not
// count. No LCL dependency.
unit Sloper.Core.Bounds;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

// Extent of everything shown, notes too unless WithNotes is False; False when
// nothing is
function PatternBounds(Pattern: TPattern; out Bounds: TRect2; WithNotes: boolean = True): boolean;
// Widens Bounds to take in DraftObject. Start with Empty True.
procedure IncludeObject(var Bounds: TRect2; var Empty: boolean; DraftObject: TDraftObject);

implementation

uses
  Math, Sloper.Core.Bezier, Sloper.Core.Piece, Sloper.Core.Note, Sloper.Core.TextFields;

procedure Include(var Bounds: TRect2; var Empty: boolean; const P: TVec2);
begin
  if Empty then
  begin
    Bounds.MinX := P.X;
    Bounds.MaxX := P.X;
    Bounds.MinY := P.Y;
    Bounds.MaxY := P.Y;
    Empty := False;
    Exit;
  end;
  Bounds.MinX := Min(Bounds.MinX, P.X);
  Bounds.MaxX := Max(Bounds.MaxX, P.X);
  Bounds.MinY := Min(Bounds.MinY, P.Y);
  Bounds.MaxY := Max(Bounds.MaxY, P.Y);
end;

procedure IncludeObject(var Bounds: TRect2; var Empty: boolean; DraftObject: TDraftObject);
var
  Segment: TEdgeSegment;
  CurveBounds, Box: TRect2;
  Corner: TVec2;
begin
  if not DraftObject.HasResult then
    Exit;
  // Its text as typed, since the fields are not known here
  if DraftObject is TNoteObject then
  begin
    Box := NoteBox(TNoteObject(DraftObject), Default(TFieldValues));
    Include(Bounds, Empty, Vec2(Box.MinX, Box.MinY));
    Include(Bounds, Empty, Vec2(Box.MaxX, Box.MaxY));
  end
  else if DraftObject is TPointObject then
    Include(Bounds, Empty, TPointObject(DraftObject).Position)
  else if DraftObject is TPieceObject then
    for Corner in TPieceObject(DraftObject).CutLine do
      Include(Bounds, Empty, Corner)
  else if DraftObject is TEdgeObject then
    for Segment in TEdgeObject(DraftObject).Segments do
      if Segment.Kind = skLine then
      begin
        Include(Bounds, Empty, Segment.Line.P1);
        Include(Bounds, Empty, Segment.Line.P2);
      end
      else
      begin
        CurveBounds := Segment.Curve.Bounds;
        Include(Bounds, Empty, Vec2(CurveBounds.MinX, CurveBounds.MinY));
        Include(Bounds, Empty, Vec2(CurveBounds.MaxX, CurveBounds.MaxY));
      end;
end;

function PatternBounds(Pattern: TPattern; out Bounds: TRect2; WithNotes: boolean): boolean;
var
  Index: integer;
  Empty: boolean;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if WithNotes or not (Pattern.Objects[Index] is TNoteObject) then
      IncludeObject(Bounds, Empty, Pattern.Objects[Index]);
  Result := not Empty;
end;

end.
