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

// The cutting line of a piece: its seam line moved outwards by a seam
// allowance that can differ along the way. Clipper2's own offset takes one
// width for a whole path, so the raw offset is built here the way Clipper2
// builds its own, one width per segment, and Clipper2's union then removes
// the loops it leaves in tight concave places. No LCL dependency.
unit Sloper.Core.SeamAllowance;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry;

type
  TDoubleArray = array of double;

// Outline is a closed polygon without a repeated last point, either way
// round; Allowances[Index] is the width of the segment leaving
// Outline[Index]. CutLine runs clockwise. False when no line results.
function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; out CutLine: TVec2Array): boolean;

implementation

uses
  Math, Clipper, Clipper.Core;

const
  // Clipper2 rounds to this many decimals of a millimetre
  CutLineDecimals = 3;
  // A corner sharper than this, as a multiple of the wider allowance, is cut
  // off rather than running out to a long spike
  MitreLimit = 4;
  // Sine of the turn below which two segments count as one straight line
  StraightTurn = 1e-9;

function UnitVector(const From, Target: TVec2): TVec2;
begin
  Result := Target - From;
  Result := Result * (1 / Result.Length);
end;

// Right of the direction of travel: outwards on an anticlockwise path
function Outwards(const Direction: TVec2): TVec2;
begin
  Result := Vec2(Direction.Y, -Direction.X);
end;

// Adds the offset of one corner to Raw
procedure OffsetVertex(const Vertex, Incoming, Outgoing: TVec2; WidthIn, WidthOut: double; var Raw: TPathD);
var
  Before, After, Mitre: TVec2;
  Turn: double;
  Count: integer;

  procedure Add(const P: TVec2);
  begin
    Raw[Count].X := P.X;
    Raw[Count].Y := P.Y;
    Inc(Count);
  end;

begin
  Count := Length(Raw);
  SetLength(Raw, Count + 3);
  Before := Vertex + Outwards(Incoming) * WidthIn;
  After := Vertex + Outwards(Outgoing) * WidthOut;
  Turn := Cross(Incoming, Outgoing);
  if Turn > StraightTurn then
  begin
    // A convex corner: the two offset lines meet at a point
    Mitre := Before + Incoming * (Cross(After - Before, Outgoing) / Turn);
    if Distance(Mitre, Vertex) <= MitreLimit * Max(WidthIn, WidthOut) then
      Add(Mitre)
    else
    begin
      Add(Before);
      Add(After);
    end;
  end
  else if Turn < -StraightTurn then
  begin
    // A concave corner: going through the vertex keeps the winding right, so
    // the union drops the overlap
    Add(Before);
    Add(Vertex);
    Add(After);
  end
  else
  begin
    Add(Before);
    Add(After);
  end;
  SetLength(Raw, Count);
end;

function LargestPath(const Paths: TPathsD): TPathD;
var
  Path: TPathD;
  Size, Best: double;
begin
  Result := nil;
  Best := 0;
  for Path in Paths do
  begin
    Size := Abs(Area(Path));
    if Size > Best then
    begin
      Best := Size;
      Result := Path;
    end;
  end;
end;

function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; out CutLine: TVec2Array): boolean;
var
  Count, Index, Before, After: integer;
  Points: TVec2Array;
  Widths: TDoubleArray;
  Raw: TPathsD;
  Cleaned: TPathD;
  Swap: TVec2;
begin
  CutLine := nil;
  Count := Length(Outline);
  if Count < 3 then
    Exit(False);
  Points := nil;
  Widths := nil;
  SetLength(Points, Count);
  SetLength(Widths, Count);
  // Anticlockwise, so the segment from a point to the next keeps its width
  // when it runs the other way: reversed, it leaves the point before it
  if SignedArea(Outline) > 0 then
    for Index := 0 to Count - 1 do
    begin
      Points[Index] := Outline[Index];
      Widths[Index] := Allowances[Index];
    end
  else
    for Index := 0 to Count - 1 do
    begin
      Points[Index] := Outline[Count - 1 - Index];
      Widths[Index] := Allowances[(2 * Count - 2 - Index) mod Count];
    end;

  Raw := nil;
  SetLength(Raw, 1);
  for Index := 0 to Count - 1 do
  begin
    Before := (Index + Count - 1) mod Count;
    After := (Index + 1) mod Count;
    OffsetVertex(Points[Index], UnitVector(Points[Before], Points[Index]), UnitVector(Points[Index], Points[After]),
      Widths[Before], Widths[Index], Raw[0]);
  end;

  Cleaned := LargestPath(Union(Raw, frPositive, CutLineDecimals));
  Result := Length(Cleaned) >= 3;
  if not Result then
    Exit;
  SetLength(CutLine, Length(Cleaned));
  for Index := 0 to High(Cleaned) do
    CutLine[Index] := Vec2(Cleaned[Index].X, Cleaned[Index].Y);
  if not IsClockwise(CutLine) then
    for Index := 0 to High(CutLine) div 2 do
    begin
      Swap := CutLine[Index];
      CutLine[Index] := CutLine[High(CutLine) - Index];
      CutLine[High(CutLine) - Index] := Swap;
    end;
end;

end.
