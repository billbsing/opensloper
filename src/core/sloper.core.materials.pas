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

// The materials of a pattern, how a piece's material looks, and hatching. Colours
// are "#RRGGBB" text, as in pattern files. A pattern starts with one material,
// Main, that has no ID and is not written to the file, until the user changes
// the list. No LCL dependency.
unit Sloper.Core.Materials;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Geometry;

const
  DEFAULT_MATERIAL_NAME = 'Main';
  // Not translated: a name has to keep to the name rules
  NEW_MATERIAL_BASE_NAME = 'Material';
  // As written in pattern files and the Automation API
  MATERIAL_FILL_NAMES: array[0..1] of string = ('tint', 'hatch');
  PIECE_FILL_NAMES: array[0..2] of string = ('material', 'tint', 'hatch');
  // Told apart by hue and by lightness, so also with colour-blindness
  MATERIAL_PALETTE: array[0..5] of string = ('#5B8DB8', '#C9A227', '#2E9E7B', '#CC79A7', '#D55E00', '#7A5AA6');

type
  TMaterialFill = (ffTint, ffHatch);
  // A piece's own fill style: pfMaterial takes the material's
  TPieceFillStyle = (pfMaterial, pfTint, pfHatch);

  TMaterialColor = record
    Red, Green, Blue: byte;
  end;

  TPatternMaterial = class
  public
    Key, Name, Color: string;
    Fill: TMaterialFill;
    // The seam allowance a piece takes when it goes on this material
    HasAllowance: boolean;
    Allowance: double;
  end;

  TPatternMaterialList = specialize TObjectList<TPatternMaterial>;

  // How a piece is filled, with its material and any override worked out.
  // Not Filled for a piece with no material.
  TPieceLook = record
    Filled: boolean;
    Color: TMaterialColor;
    Fill: TMaterialFill;
    HatchAngle: double;
  end;

function IsMaterialColor(const Text: string): boolean;
// Black for text that is not a colour
function ParseMaterialColor(const Text: string): TMaterialColor;
function MaterialColorText(const Color: TMaterialColor): string;
// The colour mixed with white, for a fill that has to be opaque
function MaterialTint(const Color: TMaterialColor): TMaterialColor;
// A material's place in the list decides its hatching, so hatched materials can
// be told apart on a black-and-white print
function MaterialHatchAngle(Index: integer): double;
// Parallel lines across a closed polygon, Spacing apart at Angle degrees, on
// fixed rows so they stay put as the polygon changes
function HatchLines(const Polygon: TVec2Array; Spacing, Angle: double): TLine2Array;

implementation

uses
  Math;

const
  // The share of the material's colour in a printed or opaque tint; the rest is white
  MATERIAL_TINT_SHARE = 0.3;
  HATCH_ANGLES: array[0..3] of double = (45, 135, 0, 90);

function IsMaterialColor(const Text: string): boolean;
var
  Index: integer;
begin
  Result := (Length(Text) = 7) and (Text[1] = '#');
  if Result then
    for Index := 2 to 7 do
      if not (Text[Index] in ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

function ParseMaterialColor(const Text: string): TMaterialColor;
begin
  Result := Default(TMaterialColor);
  if not IsMaterialColor(Text) then
    Exit;
  Result.Red := StrToInt('$' + Copy(Text, 2, 2));
  Result.Green := StrToInt('$' + Copy(Text, 4, 2));
  Result.Blue := StrToInt('$' + Copy(Text, 6, 2));
end;

function MaterialColorText(const Color: TMaterialColor): string;
begin
  Result := '#' + IntToHex(Color.Red, 2) + IntToHex(Color.Green, 2) + IntToHex(Color.Blue, 2);
end;

function MaterialTint(const Color: TMaterialColor): TMaterialColor;

  function Mixed(Channel: byte): byte;
  begin
    Result := Round(Channel * MATERIAL_TINT_SHARE + 255 * (1 - MATERIAL_TINT_SHARE));
  end;

begin
  Result.Red := Mixed(Color.Red);
  Result.Green := Mixed(Color.Green);
  Result.Blue := Mixed(Color.Blue);
end;

function MaterialHatchAngle(Index: integer): double;
begin
  Result := HATCH_ANGLES[Abs(Index) mod Length(HATCH_ANGLES)];
end;

function HatchLines(const Polygon: TVec2Array; Spacing, Angle: double): TLine2Array;
var
  Along, Across: TVec2;
  Crossings: array of double;

  procedure AddCrossing(Value: double);
  var
    Place: integer;
  begin
    Place := Length(Crossings);
    SetLength(Crossings, Place + 1);
    while (Place > 0) and (Crossings[Place - 1] > Value) do
    begin
      Crossings[Place] := Crossings[Place - 1];
      Dec(Place);
    end;
    Crossings[Place] := Value;
  end;

  procedure CollectCrossings(Row: double);
  var
    Index: integer;
    First, Last: TVec2;
    FirstAcross, LastAcross, Share: double;
  begin
    Crossings := nil;
    for Index := 0 to High(Polygon) do
    begin
      First := Polygon[Index];
      Last := Polygon[(Index + 1) mod Length(Polygon)];
      FirstAcross := Dot(First, Across);
      LastAcross := Dot(Last, Across);
      // One end counts as below and the other above, so a row through a corner
      // crosses once or not at all
      if (FirstAcross <= Row) = (LastAcross <= Row) then
        Continue;
      Share := (Row - FirstAcross) / (LastAcross - FirstAcross);
      AddCrossing(Dot(First, Along) + (Dot(Last, Along) - Dot(First, Along)) * Share);
    end;
  end;

var
  Point: TVec2;
  Row, Lowest, Highest: double;
  Number, Pair: integer;
begin
  Result := nil;
  if (Length(Polygon) < 3) or (Spacing <= 0) then
    Exit;
  Along := PolarPoint(Vec2(0, 0), 1, Angle);
  Across := LeftOf(Along);
  Lowest := Infinity;
  Highest := -Infinity;
  for Point in Polygon do
  begin
    Lowest := Min(Lowest, Dot(Point, Across));
    Highest := Max(Highest, Dot(Point, Across));
  end;
  for Number := Ceil(Lowest / Spacing) to Floor(Highest / Spacing) do
  begin
    Row := Number * Spacing;
    CollectCrossings(Row);
    Pair := 0;
    while Pair + 1 <= High(Crossings) do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Line2(Along * Crossings[Pair] + Across * Row, Along * Crossings[Pair + 1] + Across * Row);
      Inc(Pair, 2);
    end;
  end;
end;

end.
