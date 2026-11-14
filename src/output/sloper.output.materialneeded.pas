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

// Material needed: how much of each material a layout's patterns take to
// cut, from every valid piece and its cut count, whatever the layout's own
// arrangement. Each piece lies with its grainline along the material. A roll
// is cut folded in half lengthwise: fold pieces go on the fold, a mirrored
// pair shares a place, and a piece too wide for half the roll is cut
// unfolded after the folded part. A sheet is cut single layer, as many
// sheets as it takes. Pieces are packed by their bounding boxes, as Pack
// Pieces does, so the answer is an estimate on the generous side.
// See the design document. No LCL dependency.
unit Sloper.Output.MaterialNeeded;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Units, Sloper.Output.Layout;

type
  TMaterialNeedKind = (mnNoSize, mnRoll, mnSheet);

  TMaterialNeed = record
    Name: string;
    // The unit of the pattern it was first found in, for showing lengths
    Units: TMeasureUnit;
    Kind: TMaterialNeedKind;
    // In mm; 0 for none
    Width, Length: double;
    AllowTurns: boolean;
    // Pieces to cut, counting each copy
    Copies: integer;
    // The pieces' area in mm², every copy opened out
    Area: double;
    // A roll's length to buy, in mm, of which Unfolded is cut unfolded
    Needed, Unfolded: double;
    Sheets: integer;
    // With no size: the narrowest roll every piece fits, in mm
    NarrowestRoll: double;
    // Pieces cut unfolded or left out, sizes that differ, and folds across
    // the grain, in plain words
    Notes: TStringArray;
  end;

  TMaterialNeedArray = array of TMaterialNeed;

// Each material by name, in the order the layout's patterns first use them
function LayoutMaterialNeeds(Layout: TLayout): TMaterialNeedArray;
// "150 cm roll", "50 × 70 cm", or '' with no size
function MaterialNeedSize(const Need: TMaterialNeed): string;
// "135 cm", "2 sheets", or the area and narrowest roll with no size
function MaterialNeedText(const Need: TMaterialNeed): string;
// "Main: 135 cm of a 150 cm roll · Interfacing: 2 sheets of 50 × 70 cm"
function MaterialNeedSummary(const Needs: TMaterialNeedArray): string;

resourcestring
  rsNeedNoMaterial = 'No material';
  // Width, unit
  rsNeedRoll = '%s roll';
  // Width, length
  rsNeedSheet = '%s × %s';
  rsNeedOneSheet = '1 sheet';
  rsNeedSheets = '%d sheets';
  // Area, narrowest roll
  rsNeedArea = '%s² of pieces, on a roll at least %s wide';
  // Name, what is needed
  rsNeedSummaryEntry = '%s: %s';
  // Name, what is needed, roll width
  rsNeedSummaryRoll = '%s: %s of a %s roll';
  // Name, what is needed, sheet size
  rsNeedSummarySheet = '%s: %s of %s';
  // Material, piece
  rsNeedUnfolded = '%s: %s is cut unfolded, being wider than half the roll';
  // Material, piece, size
  rsNeedNoFit = '%s: %s does not fit a %s, so it is left out';
  // Material, piece
  rsNeedFoldAcross = '%s: the fold of %s runs across the grain, so it is cut opened out';
  // Material, file, size used, file
  rsNeedSizesDiffer = '%s: %s gives it another size; this uses %s from %s';

implementation

uses
  Math, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Materials, Sloper.Core.EvalTypes,
  Sloper.Output.Packing;

const
  SUMMARY_GAP: string = ' · ';

type
  // One place on the material: a box, and the piece it is for
  TCutBox = record
    Size: TVec2;
    Caption: string;
    // The pieces it cuts: 2 for a mirrored pair cut from two layers
    Copies: integer;
  end;

  TCutBoxArray = array of TCutBox;

  // The pieces of one material, gathered across the layout's patterns
  TGathered = record
    Need: TMaterialNeed;
    // Boxes on the fold of a folded roll, and the rest
    FoldBoxes, Boxes: TCutBoxArray;
    // Every copy opened out, for a sheet or no size
    WholeBoxes: TCutBoxArray;
    // The file the size came from
    SizeFile: string;
  end;

  TGatheredArray = array of TGathered;

procedure AddBox(var Boxes: TCutBoxArray; const Size: TVec2; const Caption: string; Count: integer; Copies: integer = 1);
var
  Box: TCutBox;
  Index: integer;
begin
  Box.Size := Size;
  Box.Caption := Caption;
  Box.Copies := Copies;
  for Index := 1 to Count do
    Insert(Box, Boxes, System.Length(Boxes));
end;

// Each note once, as a piece cut several times has several boxes
procedure AddNote(var Need: TMaterialNeed; const Note: string);
var
  Existing: string;
begin
  for Existing in Need.Notes do
    if Existing = Note then
      Exit;
  Insert(Note, Need.Notes, System.Length(Need.Notes));
end;

function Shown(const Need: TMaterialNeed; Millimetres: double): string;
begin
  Result := LengthWithUnit(Millimetres, Need.Units);
end;

function FindGathered(var Groups: TGatheredArray; const AName: string): integer;
begin
  for Result := 0 to High(Groups) do
    if SameText(Groups[Result].Need.Name, AName) then
      Exit;
  Result := -1;
end;

// Takes the material's size the first time one is given, and notes another
procedure TakeSize(var Group: TGathered; Material: TPatternMaterial; Units: TMeasureUnit; const FileName: string);
var
  Width, Length: double;
begin
  if not Assigned(Material) or (Material.Width <= 0) then
    Exit;
  Width := Material.Width * MILLIMETRES_PER_UNIT[Units];
  Length := Material.Length * MILLIMETRES_PER_UNIT[Units];
  if Group.Need.Width <= 0 then
  begin
    Group.Need.Width := Width;
    Group.Need.Length := Length;
    Group.Need.AllowTurns := Material.AllowTurns;
    Group.SizeFile := FileName;
    if Length > 0 then
      Group.Need.Kind := mnSheet
    else
      Group.Need.Kind := mnRoll;
  end
  else if not SameValue(Width, Group.Need.Width, DEFAULT_TOLERANCE) or not SameValue(Length, Group.Need.Length, DEFAULT_TOLERANCE) or
    (Material.AllowTurns <> Group.Need.AllowTurns) then
    AddNote(Group.Need, Format(rsNeedSizesDiffer, [Group.Need.Name, FileName, MaterialNeedSize(Group.Need), Group.SizeFile]));
end;

procedure GatherPiece(var Group: TGathered; Piece: TPieceObject);
var
  Shape: TGrainShape;
  Whole, Half: TVec2;
  Count: integer;
begin
  Shape := Piece.GrainShape;
  Whole := PointsExtent(Shape.Whole);
  Half := PointsExtent(Shape.Half);
  Count := Max(Piece.CutCount, 1);
  Inc(Group.Need.Copies, Count);
  if Piece.OnFold then
    Group.Need.Area := Group.Need.Area + 2 * Count * Abs(SignedArea(Piece.CutLine))
  else
    Group.Need.Area := Group.Need.Area + Count * Abs(SignedArea(Piece.CutLine));
  AddBox(Group.WholeBoxes, Whole, Piece.DisplayName, Count);
  if Piece.OnFold and Shape.FoldAlongGrain then
    AddBox(Group.FoldBoxes, Half, Piece.DisplayName, Count)
  else
  begin
    if Piece.OnFold then
      AddNote(Group.Need, Format(rsNeedFoldAcross, [Group.Need.Name, Piece.DisplayName]));
    // Two layers cut a mirrored pair at once; other copies each get a place
    if Piece.Mirrored and not Piece.OnFold then
    begin
      AddBox(Group.Boxes, Whole, Piece.DisplayName, Count div 2, 2);
      AddBox(Group.Boxes, Whole, Piece.DisplayName, Count mod 2);
    end
    else
      AddBox(Group.Boxes, Whole, Piece.DisplayName, Count);
  end;
end;

function Sizes(const Boxes: TCutBoxArray): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, System.Length(Boxes));
  for Index := 0 to High(Boxes) do
    Result[Index] := Boxes[Index].Size;
end;

// How far down the spots that fit reach
function Bottom(const Boxes: TCutBoxArray; const Spots: TBoxSpotArray): double;
var
  Index: integer;
begin
  Result := 0;
  for Index := 0 to High(Spots) do
    if Spots[Index].Fits then
    begin
      if Spots[Index].Turned then
        Result := Max(Result, Spots[Index].Y + Boxes[Index].Size.X)
      else
        Result := Max(Result, Spots[Index].Y + Boxes[Index].Size.Y);
    end;
end;

function FitsAcross(const Size: TVec2; Width: double; Turns: boolean): boolean;
begin
  Result := FitsMaterial(Size.X, Size.Y, Width, 0, Turns);
end;

procedure WorkOutRoll(var Group: TGathered);
var
  Need: TMaterialNeed;
  Folded, Open: TCutBoxArray;
  Column: array of TRect2;
  Box: TCutBox;
  Spots: TBoxSpotArray;
  Down: double;
begin
  Need := Group.Need;
  Column := nil;
  Down := 0;
  // Fold pieces go down the fold, one under another
  for Box in Group.FoldBoxes do
    if Box.Size.X > Need.Width / 2 + DEFAULT_TOLERANCE then
      AddNote(Need, Format(rsNeedNoFit, [Need.Name, Box.Caption, MaterialNeedSize(Need)]))
    else
    begin
      SetLength(Column, System.Length(Column) + 1);
      Column[High(Column)].MinX := 0;
      Column[High(Column)].MinY := Down;
      Column[High(Column)].MaxX := Box.Size.X;
      Column[High(Column)].MaxY := Down + Box.Size.Y;
      Down := Column[High(Column)].MaxY + PACK_GAP;
    end;
  Folded := nil;
  Open := nil;
  for Box in Group.Boxes do
    if FitsAcross(Box.Size, Need.Width / 2, Need.AllowTurns) then
      Insert(Box, Folded, System.Length(Folded))
    else if FitsAcross(Box.Size, Need.Width, Need.AllowTurns) then
    begin
      // Unfolded, each piece the box cut from two layers needs its own place
      AddBox(Open, Box.Size, Box.Caption, Box.Copies);
      AddNote(Need, Format(rsNeedUnfolded, [Need.Name, Box.Caption]));
    end
    else
      AddNote(Need, Format(rsNeedNoFit, [Need.Name, Box.Caption, MaterialNeedSize(Need)]));
  Spots := PackBoxes(Sizes(Folded), Need.Width / 2, Infinity, Need.AllowTurns, Column);
  Need.Needed := Bottom(Folded, Spots);
  if System.Length(Column) > 0 then
    Need.Needed := Max(Need.Needed, Column[High(Column)].MaxY);
  if System.Length(Open) > 0 then
  begin
    Spots := PackBoxes(Sizes(Open), Need.Width, Infinity, Need.AllowTurns, []);
    Need.Unfolded := Bottom(Open, Spots);
    Need.Needed := Need.Needed + Need.Unfolded;
  end;
  Group.Need := Need;
end;

procedure WorkOutSheets(var Group: TGathered);
var
  Need: TMaterialNeed;
  Left, Next: TCutBoxArray;
  Box: TCutBox;
  Spots: TBoxSpotArray;
  Index: integer;
begin
  Need := Group.Need;
  Left := nil;
  for Box in Group.WholeBoxes do
    if FitsMaterial(Box.Size.X, Box.Size.Y, Need.Width, Need.Length, Need.AllowTurns) then
      Insert(Box, Left, System.Length(Left))
    else
      AddNote(Need, Format(rsNeedNoFit, [Need.Name, Box.Caption, MaterialNeedSize(Need)]));
  while System.Length(Left) > 0 do
  begin
    Spots := PackBoxes(Sizes(Left), Need.Width, Need.Length, Need.AllowTurns, []);
    Next := nil;
    for Index := 0 to High(Left) do
      if not Spots[Index].Fits then
        Insert(Left[Index], Next, System.Length(Next));
    // Within the tolerance of fitting, a box may still find no room
    if System.Length(Next) = System.Length(Left) then
    begin
      for Box in Next do
        AddNote(Need, Format(rsNeedNoFit, [Need.Name, Box.Caption, MaterialNeedSize(Need)]));
      Break;
    end;
    Inc(Need.Sheets);
    Left := Next;
  end;
  Group.Need := Need;
end;

procedure WorkOutNoSize(var Group: TGathered);
var
  Box: TCutBox;
begin
  for Box in Group.WholeBoxes do
    Group.Need.NarrowestRoll := Max(Group.Need.NarrowestRoll, Box.Size.X);
end;

function LayoutMaterialNeeds(Layout: TLayout): TMaterialNeedArray;
var
  Groups: TGatheredArray;
  Source: TLayoutSource;
  Index, Place: integer;
  Piece: TPieceObject;
  Material: TPatternMaterial;
  MaterialName, FileName: string;
begin
  Groups := nil;
  for Source in Layout.Sources do
  begin
    if not Assigned(Source.Pattern) or (Source.LoadError <> '') then
      Continue;
    FileName := ExtractFileName(Source.PatternFile);
    // In the pattern's own order; those no piece uses are dropped below
    for Index := 0 to Source.Pattern.MaterialCount - 1 do
      if FindGathered(Groups, Source.Pattern.Materials[Index].Name) < 0 then
      begin
        Place := System.Length(Groups);
        SetLength(Groups, Place + 1);
        Groups[Place] := Default(TGathered);
        Groups[Place].Need.Name := Source.Pattern.Materials[Index].Name;
        Groups[Place].Need.Units := Source.Pattern.Units;
      end;
    for Index := 0 to Source.Pattern.ObjectCount - 1 do
    begin
      if not (Source.Pattern.Objects[Index] is TPieceObject) or (Source.Pattern.Objects[Index].State <> esValid) then
        Continue;
      Piece := TPieceObject(Source.Pattern.Objects[Index]);
      Material := Source.Pattern.MaterialOf(Piece);
      MaterialName := rsNeedNoMaterial;
      if Assigned(Material) then
        MaterialName := Material.Name;
      Place := FindGathered(Groups, MaterialName);
      if Place < 0 then
      begin
        Place := System.Length(Groups);
        SetLength(Groups, Place + 1);
        Groups[Place] := Default(TGathered);
        Groups[Place].Need.Name := MaterialName;
        Groups[Place].Need.Units := Source.Pattern.Units;
      end;
      TakeSize(Groups[Place], Material, Source.Pattern.Units, FileName);
      GatherPiece(Groups[Place], Piece);
    end;
  end;
  Result := nil;
  for Index := 0 to High(Groups) do
  begin
    if Groups[Index].Need.Copies = 0 then
      Continue;
    case Groups[Index].Need.Kind of
      mnRoll: WorkOutRoll(Groups[Index]);
      mnSheet: WorkOutSheets(Groups[Index]);
      mnNoSize: WorkOutNoSize(Groups[Index]);
    end;
    Insert(Groups[Index].Need, Result, System.Length(Result));
  end;
end;

function MaterialNeedSize(const Need: TMaterialNeed): string;
begin
  case Need.Kind of
    mnRoll: Result := Format(rsNeedRoll, [Shown(Need, Need.Width)]);
    mnSheet: Result := Format(rsNeedSheet, [FormatLength(Need.Width, Need.Units), Shown(Need, Need.Length)]);
    else
      Result := '';
  end;
end;

function AreaText(const Need: TMaterialNeed): string;
begin
  Result := FormatLength(Need.Area / MILLIMETRES_PER_UNIT[Need.Units], Need.Units) + ' ' + MEASURE_UNIT_NAMES[Need.Units];
end;

function MaterialNeedText(const Need: TMaterialNeed): string;
begin
  case Need.Kind of
    mnRoll: Result := Shown(Need, Need.Needed);
    mnSheet:
      if Need.Sheets = 1 then
        Result := rsNeedOneSheet
      else
        Result := Format(rsNeedSheets, [Need.Sheets]);
    else
      Result := Format(rsNeedArea, [AreaText(Need), Shown(Need, Need.NarrowestRoll)]);
  end;
end;

function MaterialNeedSummary(const Needs: TMaterialNeedArray): string;
var
  Need: TMaterialNeed;
  Entry: string;
begin
  Result := '';
  for Need in Needs do
  begin
    case Need.Kind of
      mnRoll: Entry := Format(rsNeedSummaryRoll, [Need.Name, MaterialNeedText(Need), Shown(Need, Need.Width)]);
      mnSheet: Entry := Format(rsNeedSummarySheet, [Need.Name, MaterialNeedText(Need), MaterialNeedSize(Need)]);
      else
        Entry := Format(rsNeedSummaryEntry, [Need.Name, MaterialNeedText(Need)]);
    end;
    if Result <> '' then
      Result := Result + SUMMARY_GAP;
    Result := Result + Entry;
  end;
end;

end.
