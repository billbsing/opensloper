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

// Sizing for the properties panel's two columns: how the row width is shared
// between names and values, and cutting text to fit a column. Kept free of
// the LCL so it can be unit-tested.
unit Sloper.UI.GridColumns;

{$mode ObjFPC}{$H+}

interface

const
  // U+2026 as UTF-8 bytes, so the constant stays a plain string
  Ellipsis = #$E2#$80#$A6;

type
  TTextWidthFunc = function(const Text: string): integer of object;

// The name column's width for Share of Available pixels, leaving each column
// at least MinColumn. When both minimums don't fit, the columns split evenly.
function NameColumnWidth(Available, MinColumn: integer; Share: double): integer;
// The share that puts the columns' boundary at Position, kept within the minimums
function NameShareAt(Position, Available, MinColumn: integer): double;
// Text as it is when it fits MaxWidth, otherwise cut short with an ellipsis
function FitText(const Text: string; MaxWidth: integer; Measure: TTextWidthFunc): string;

implementation

uses
  Math, SysUtils, Sloper.Core.Settings;

function NameColumnWidth(Available, MinColumn: integer; Share: double): integer;
begin
  if Available < 2 * MinColumn then
    Exit(Available div 2);
  Result := EnsureRange(Round(Available * Share), MinColumn, Available - MinColumn);
end;

function NameShareAt(Position, Available, MinColumn: integer): double;
begin
  if (Available <= 0) or (Available < 2 * MinColumn) then
    Exit(DefaultNameColumnShare);
  Result := EnsureRange(Position, MinColumn, Available - MinColumn) / Available;
end;

// Byte offset of the end of each UTF-8 character, so a cut never splits one
function CharacterEnds(const Text: string): specialize TArray<integer>;
var
  Index, Count: integer;
begin
  Result := nil;
  SetLength(Result, Length(Text));
  Count := 0;
  for Index := 1 to Length(Text) do
  begin
    if (Index = Length(Text)) or ((Ord(Text[Index + 1]) and $C0) <> $80) then
    begin
      Result[Count] := Index;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function FitText(const Text: string; MaxWidth: integer; Measure: TTextWidthFunc): string;
var
  Ends: specialize TArray<integer>;
  Low, High, Middle: integer;

  function Cut(Characters: integer): string;
  begin
    Result := TrimRight(Copy(Text, 1, Ends[Characters - 1])) + Ellipsis;
  end;

begin
  if Measure(Text) <= MaxWidth then
    Exit(Text);
  Ends := CharacterEnds(Text);
  // The most characters that fit along with the ellipsis
  Low := 0;
  High := Length(Ends) - 1;
  while Low < High do
  begin
    Middle := (Low + High + 1) div 2;
    if Measure(Cut(Middle)) <= MaxWidth then
      Low := Middle
    else
      High := Middle - 1;
  end;
  if Low = 0 then
    Exit(Ellipsis);
  Result := Cut(Low);
end;

end.
