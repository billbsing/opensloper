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

// The map from a piece as drafted to the piece as sewn: each dart is closed by
// turning the piece about its apex, so the two legs land on one line and the
// rest of the piece opens slightly to take it up, most near the dart and not
// at all opposite it; then a move and turn place the result. The outline,
// stitch lines, markings and grainline all go through it, so everything on a
// piece follows its darts. See Garment view in the design. No LCL dependency.
unit Sloper.Core.Warp;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry;

type
  // A dart as drafted: its apex and the far ends of its two straight legs
  TDartClosing = record
    Apex: TVec2;
    // Into the opening, halfway between the legs
    Bisector: double;
    // The opening, in degrees, above 0 and below 180
    Opening: double;
    // Leg lengths: First is the leg clockwise of the bisector, as seen on screen
    FirstLength, SecondLength: double;
  end;

  TDartClosingArray = array of TDartClosing;

  TPieceWarp = class
  private
    FDarts: TDartClosingArray;
    FPlacement: TAffine2;
    function CloseOne(const Dart: TDartClosing; const Position: TVec2): TVec2;
  public
    constructor Create;
    // Closed in the order added, each after those before it; Dart is as
    // drafted and is carried through the darts already added
    procedure AddDart(const Dart: TDartClosing);
    // The darts closed, without the placement
    function Close(const Position: TVec2): TVec2;
    // Where Position ends up on the finished piece
    function Apply(const Position: TVec2): TVec2;
    function ApplyAll(const Points: TVec2Array): TVec2Array;
    // Applied after the darts are closed
    property Placement: TAffine2 read FPlacement write FPlacement;
    property Darts: TDartClosingArray read FDarts;
  end;

// A dart from its apex and the far ends of its legs, on a piece with this
// outline. False when the opening between the legs is not outside the piece.
function MakeDartClosing(const Apex, FirstEnd, SecondEnd: TVec2; const Outline: TVec2Array; out Dart: TDartClosing): boolean;
// Where the closed dart's legs end: on the bisector, halfway between the two
// lengths
function ClosedDartEnd(const Dart: TDartClosing): TVec2;

implementation

uses
  Math;

const
  // Share of the shorter leg that the inside test steps off the apex
  INSIDE_STEP = 0.01;

function MakeDartClosing(const Apex, FirstEnd, SecondEnd: TVec2; const Outline: TVec2Array; out Dart: TDartClosing): boolean;
var
  AngleA, AngleB, Between, Step: double;
  Probe: TVec2;
begin
  Dart := Default(TDartClosing);
  Result := False;
  if PointsNear(Apex, FirstEnd) or PointsNear(Apex, SecondEnd) then
    Exit;
  AngleA := AngleBetween(Apex, FirstEnd);
  AngleB := AngleBetween(Apex, SecondEnd);
  // From the first leg anticlockwise to the second
  Between := NormalizeAngle(AngleB - AngleA);
  if (Between < EPSILON) or (Abs(Between - 180) < EPSILON) then
    Exit;
  Dart.Apex := Apex;
  if Between < 180 then
  begin
    // The second leg is anticlockwise of the first, so the first is the clockwise leg
    Dart.Opening := Between;
    Dart.Bisector := NormalizeAngle(AngleA + Between / 2);
    Dart.FirstLength := Distance(Apex, FirstEnd);
    Dart.SecondLength := Distance(Apex, SecondEnd);
  end
  else
  begin
    Dart.Opening := 360 - Between;
    Dart.Bisector := NormalizeAngle(AngleB + Dart.Opening / 2);
    Dart.FirstLength := Distance(Apex, SecondEnd);
    Dart.SecondLength := Distance(Apex, FirstEnd);
  end;
  Step := Min(Dart.FirstLength, Dart.SecondLength) * INSIDE_STEP;
  Probe := PolarPoint(Apex, Step, Dart.Bisector);
  Result := not PointInPolygon(Probe, Outline);
end;

function ClosedDartEnd(const Dart: TDartClosing): TVec2;
begin
  Result := PolarPoint(Dart.Apex, (Dart.FirstLength + Dart.SecondLength) / 2, Dart.Bisector);
end;

constructor TPieceWarp.Create;
begin
  inherited Create;
  FPlacement := AffineIdentity;
end;

procedure TPieceWarp.AddDart(const Dart: TDartClosing);
var
  Carried: TDartClosing;
  FirstEnd, SecondEnd: TVec2;
  Opening: double;
begin
  Carried := Dart;
  if Length(FDarts) > 0 then
  begin
    // The dart as the darts before have left it
    FirstEnd := Close(PolarPoint(Dart.Apex, Dart.FirstLength, Dart.Bisector - Dart.Opening / 2));
    SecondEnd := Close(PolarPoint(Dart.Apex, Dart.SecondLength, Dart.Bisector + Dart.Opening / 2));
    Carried.Apex := Close(Dart.Apex);
    Carried.FirstLength := Distance(Carried.Apex, FirstEnd);
    Carried.SecondLength := Distance(Carried.Apex, SecondEnd);
    Opening := NormalizeAngle(AngleBetween(Carried.Apex, SecondEnd) - AngleBetween(Carried.Apex, FirstEnd));
    // Still a dart: it can only have opened or closed a little
    if (Opening > EPSILON) and (Opening < 180) and (Carried.FirstLength > EPSILON) and (Carried.SecondLength > EPSILON) then
    begin
      Carried.Opening := Opening;
      Carried.Bisector := NormalizeAngle(AngleBetween(Carried.Apex, FirstEnd) + Opening / 2);
    end;
  end;
  Insert(Carried, FDarts, Length(FDarts));
end;

// Turns Position about the apex by a share of the opening that grows with its angle
// round the piece from the clockwise leg, so that leg turns forward by half
// the opening and the other back by half, and the side opposite stays. The
// legs' ends are moved along to meet halfway between their lengths, by a
// stretch that fades out towards the opposite side.
function TPieceWarp.CloseOne(const Dart: TDartClosing; const Position: TVec2): TVec2;
var
  Radius, Around, Half, Turned, Stretch, Middle: double;
begin
  Radius := Distance(Dart.Apex, Position);
  if Radius < EPSILON then
    Exit(Position);
  Half := Dart.Opening / 2;
  // 0 along the bisector, into the opening, growing anticlockwise
  Around := NormalizeAngle(AngleBetween(Dart.Apex, Position) - Dart.Bisector);
  // In the opening itself: on the leg nearest
  if Around < Half then
    Around := Half
  else if Around > 360 - Half then
    Around := 360 - Half;
  Turned := 180 + (Around - 180) * 360 / (360 - Dart.Opening);
  Middle := (Dart.FirstLength + Dart.SecondLength) / 2;
  if Around <= 180 then
    // From the second (anticlockwise) leg at Half to nothing at 180
    Stretch := 1 + (Middle / Dart.SecondLength - 1) * (180 - Around) / (180 - Half)
  else
    Stretch := 1 + (Middle / Dart.FirstLength - 1) * (Around - 180) / (180 - Half);
  Result := PolarPoint(Dart.Apex, Radius * Stretch, Dart.Bisector + Turned);
end;

function TPieceWarp.Close(const Position: TVec2): TVec2;
var
  Dart: TDartClosing;
begin
  Result := Position;
  for Dart in FDarts do
    Result := CloseOne(Dart, Result);
end;

function TPieceWarp.Apply(const Position: TVec2): TVec2;
begin
  Result := FPlacement.Apply(Close(Position));
end;

function TPieceWarp.ApplyAll(const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Apply(Points[Index]);
end;

end.
