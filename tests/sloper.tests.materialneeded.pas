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

// Material needed, with rectangles worked out by hand. Allowances are 0, so
// a panel cuts at its own size, and boxes are PACK_GAP (10) apart.
unit Sloper.Tests.MaterialNeeded;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Units,
  Sloper.Output.Layout, Sloper.Output.MaterialNeeded;

type
  TTestMaterialNeeded = class(TOSTestCase)
  private
    FFolder: string;
    FLayout: TLayout;
    FPattern: TPattern;
    FRightEdge: string;
    function AddPanel(const PieceName: string; Left, Width, Height: double): TPieceObject;
    // Saves the pattern being built as FileName and adds it to the layout
    procedure AddToLayout(const FileName: string);
    function Needs: TMaterialNeedArray;
    procedure SetMainSize(Width, Length: double; Turns: boolean = False);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFoldedRoll;
    procedure TestMirroredPairSharesAPlace;
    procedure TestWideMirroredPairCutUnfolded;
    procedure TestTooWideIsLeftOut;
    procedure TestTurnsLetItFit;
    procedure TestFoldAcrossGrainOpensOut;
    procedure TestSheetsCountUp;
    procedure TestNoSize;
    procedure TestNoMaterial;
    procedure TestMaterialOrder;
    procedure TestSizesDiffer;
    procedure TestSummaryInPatternUnit;
    procedure TestFieldInNote;
    procedure TestLayoutTakesMaterialSize;
    procedure TestLayoutKeepsSizeWithoutOne;
  end;

implementation

uses
  Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.TextFields,
  Sloper.Core.Materials;

procedure TTestMaterialNeeded.SetUp;
begin
  inherited SetUp;
  FFolder := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-need-' + IntToStr(Random(MaxInt));
  ForceDirectories(FFolder);
  FLayout := TLayout.Create;
  FLayout.FileName := ConcatPaths([FFolder, 'cut.slayout']);
  FPattern := TPattern.Create;
end;

procedure TTestMaterialNeeded.TearDown;
var
  Found: TSearchRec;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FLayout);
  if FindFirst(ConcatPaths([FFolder, '*']), faAnyFile, Found) = 0 then
    repeat
      DeleteFile(ConcatPaths([FFolder, Found.Name]));
    until FindNext(Found) <> 0;
  FindClose(Found);
  RemoveDir(FFolder);
  inherited TearDown;
end;

// Width across and Height down from (Left, 0), grainline up, no allowance
function TTestMaterialNeeded.AddPanel(const PieceName: string; Left, Width, Height: double): TPieceObject;
var
  Corners: array[0..3] of string;
  Path: TPiecePath;
  Reason: string;
  Index: integer;
begin
  for Index := 0 to 3 do
    Corners[Index] := FPattern.AddFreePoint(PieceName + IntToStr(Index), FloatToStr(Left + Width * Ord(Index in [1, 2])),
      FloatToStr(Height * Ord(Index in [2, 3]))).Key;
  for Index := 0 to 3 do
    if Index = 1 then
      FRightEdge := FPattern.AddLine(Corners[Index], Corners[(Index + 1) mod 4], erOutline).Key
    else
      FPattern.AddLine(Corners[Index], Corners[(Index + 1) mod 4], erOutline);
  FPattern.Evaluate;
  // Formulas are in the pattern's unit, positions in mm
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Width / 2, Height / 2) * MILLIMETRES_PER_UNIT[FPattern.Units], Path, Reason));
  Result := FPattern.AddPiece(PieceName, Path, '0');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestMaterialNeeded.AddToLayout(const FileName: string);
var
  Reason: string;
  Source: TLayoutSource;
  Known: boolean;
begin
  AssertTrue(Reason, SavePatternToFile(FPattern, ConcatPaths([FFolder, FileName]), Reason));
  Known := False;
  for Source in FLayout.Sources do
    Known := Known or (Source.PatternFile = FileName);
  if not Known then
    FLayout.AddSource(FileName, '', '');
  FLayout.LoadSources;
end;

function TTestMaterialNeeded.Needs: TMaterialNeedArray;
begin
  AddToLayout('front.sloper');
  Result := LayoutMaterialNeeds(FLayout);
end;

procedure TTestMaterialNeeded.SetMainSize(Width, Length: double; Turns: boolean);
begin
  AssertTrue(FPattern.LastError, FPattern.SetMaterialSize(FPattern.Materials[0], Width, Length));
  FPattern.SetMaterialAllowTurns(FPattern.Materials[0], Turns);
end;

// A 300 roll folded is 150 across. The fold piece, half 100 by 200, goes down
// the fold; the 120 by 150 piece cannot go beside it (100 + 10 + 120 > 150),
// so goes under it: 200 + 10 + 150.
procedure TTestMaterialNeeded.TestFoldedRoll;
var
  Result: TMaterialNeedArray;
begin
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(AddPanel('Back', 0, 100, 200), FRightEdge));
  AddPanel('Front', 500, 120, 150);
  SetMainSize(300, 0);
  Result := Needs;
  AssertEquals(1, Length(Result));
  AssertEquals('Main', Result[0].Name);
  AssertTrue(Result[0].Kind = mnRoll);
  AssertEquals(2, Result[0].Copies);
  AssertNear('length', 360, Result[0].Needed);
  AssertEquals('none unfolded', 0, Result[0].Unfolded, 1e-9);
  AssertNear('area, the fold piece opened out', 2 * 100 * 200 + 120 * 150, Result[0].Area);
  AssertEquals('no notes', 0, Length(Result[0].Notes));
end;

// Cut ×2 mirrored from two layers takes one place; ×2 not mirrored takes two
procedure TTestMaterialNeeded.TestMirroredPairSharesAPlace;
var
  Piece: TPieceObject;
begin
  Piece := AddPanel('Front', 0, 120, 150);
  FPattern.SetCut(Piece, 2, True);
  SetMainSize(300, 0);
  AssertNear('one place', 150, Needs[0].Needed);
  AssertEquals(2, Needs[0].Copies);
  FPattern.SetCut(Piece, 2, False);
  AssertNear('two places, one under the other', 310, Needs[0].Needed);
end;

// 200 wide is more than half a 300 roll: cut unfolded, both of the pair laid
// out, one under the other (200 + 10 + 200 > 300)
procedure TTestMaterialNeeded.TestWideMirroredPairCutUnfolded;
var
  Result: TMaterialNeedArray;
begin
  FPattern.SetCut(AddPanel('Skirt', 0, 200, 100), 2, True);
  SetMainSize(300, 0);
  Result := Needs;
  AssertNear('length', 210, Result[0].Needed);
  AssertNear('unfolded', 210, Result[0].Unfolded);
  AssertEquals(1, Length(Result[0].Notes));
  AssertEquals(Format(rsNeedUnfolded, ['Main', 'Skirt']), Result[0].Notes[0]);
end;

procedure TTestMaterialNeeded.TestTooWideIsLeftOut;
var
  Result: TMaterialNeedArray;
begin
  AddPanel('Skirt', 0, 200, 100);
  SetMainSize(150, 0);
  Result := Needs;
  AssertEquals(0, Result[0].Needed, 1e-9);
  AssertEquals(Format(rsNeedNoFit, ['Main', 'Skirt', '150 mm roll']), Result[0].Notes[0]);
end;

// Turned, 100 across fits 150 but not the 75 folded, so it is cut unfolded
procedure TTestMaterialNeeded.TestTurnsLetItFit;
begin
  AddPanel('Skirt', 0, 200, 100);
  SetMainSize(150, 0, True);
  AssertNear('turned, 200 long', 200, Needs[0].Needed);
end;

// With the grainline across, the right-edge fold runs across the grain
procedure TTestMaterialNeeded.TestFoldAcrossGrainOpensOut;
var
  Piece: TPieceObject;
  Result: TMaterialNeedArray;
begin
  Piece := AddPanel('Back', 0, 100, 50);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, FRightEdge));
  AssertTrue(FPattern.LastError, FPattern.SetGrainAngle(Piece, '0'));
  SetMainSize(300, 0);
  Result := Needs;
  AssertEquals(Format(rsNeedFoldAcross, ['Main', 'Back']), Result[0].Notes[0]);
  AssertNear('opened out, 200 along the grain', 200, Result[0].Needed);
end;

procedure TTestMaterialNeeded.TestSheetsCountUp;
var
  Result: TMaterialNeedArray;
begin
  FPattern.SetCut(AddPanel('Panel', 0, 200, 200), 3, False);
  SetMainSize(250, 250);
  Result := Needs;
  AssertTrue(Result[0].Kind = mnSheet);
  AssertEquals(3, Result[0].Sheets);
  AssertEquals('3 sheets', MaterialNeedText(Result[0]));
  AssertEquals('250 × 250 mm', MaterialNeedSize(Result[0]));
end;

procedure TTestMaterialNeeded.TestNoSize;
var
  Result: TMaterialNeedArray;
begin
  AddPanel('Front', 0, 100, 200);
  AddPanel('Strap', 500, 300, 50);
  Result := Needs;
  AssertTrue(Result[0].Kind = mnNoSize);
  AssertNear('narrowest roll', 300, Result[0].NarrowestRoll);
  AssertEquals(Format(rsNeedArea, ['35000 mm', '300 mm']), MaterialNeedText(Result[0]));
  AssertEquals('', MaterialNeedSize(Result[0]));
end;

procedure TTestMaterialNeeded.TestNoMaterial;
begin
  FPattern.SetPieceMaterial(AddPanel('Front', 0, 100, 200), nil);
  AssertEquals(rsNeedNoMaterial, Needs[0].Name);
end;

// The pattern's own order, whatever order the pieces come in; unused left out
procedure TTestMaterialNeeded.TestMaterialOrder;
var
  Lining: TPatternMaterial;
  Result: TMaterialNeedArray;
begin
  Lining := FPattern.AddMaterial('Lining');
  FPattern.AddMaterial('Interfacing');
  FPattern.SetPieceMaterial(AddPanel('Lining', 0, 100, 100), Lining);
  AddPanel('Front', 500, 100, 100);
  Result := Needs;
  AssertEquals(2, Length(Result));
  AssertEquals('Main', Result[0].Name);
  AssertEquals('Lining', Result[1].Name);
end;

procedure TTestMaterialNeeded.TestSizesDiffer;
var
  Result: TMaterialNeedArray;
begin
  AddPanel('Front', 0, 100, 100);
  SetMainSize(300, 0);
  AddToLayout('front.sloper');
  SetMainSize(400, 0);
  AddToLayout('back.sloper');
  Result := LayoutMaterialNeeds(FLayout);
  AssertEquals(1, Length(Result));
  AssertEquals('one from each', 2, Result[0].Copies);
  AssertEquals(Format(rsNeedSizesDiffer, ['Main', 'back.sloper', '300 mm roll', 'front.sloper']), Result[0].Notes[0]);
end;

// A cm pattern: the fold piece is 10 by 20 cm on a 30 cm roll
procedure TTestMaterialNeeded.TestSummaryInPatternUnit;
var
  Lining: TPatternMaterial;
begin
  FPattern.Units := muCentimetre;
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(AddPanel('Back', 0, 10, 20), FRightEdge));
  SetMainSize(30, 0);
  Lining := FPattern.AddMaterial('Lining');
  AssertTrue(FPattern.SetMaterialSize(Lining, 50, 70));
  FPattern.SetPieceMaterial(AddPanel('Pocket', 100, 10, 10), Lining);
  AssertEquals('Main: 20 cm of a 30 cm roll · Lining: 1 sheet of 50 × 70 cm', MaterialNeedSummary(Needs));
end;

procedure TTestMaterialNeeded.TestFieldInNote;
begin
  AddPanel('Front', 0, 100, 100);
  SetMainSize(300, 0);
  AddToLayout('front.sloper');
  AssertEquals('Main: 100 mm of a 300 mm roll', ExpandFields('{' + FIELD_MATERIAL_NEEDED + '}', FLayout.FieldValues('1', '1')));
end;

procedure TTestMaterialNeeded.TestLayoutTakesMaterialSize;
begin
  FPattern.Units := muCentimetre;
  AddPanel('Front', 0, 10, 10);
  SetMainSize(140, 90, True);
  AddToLayout('front.sloper');
  FLayout.Output.Kind := okMaterial;
  FLayout.Output.Material := 'main';
  AssertTrue(FLayout.TakeMaterialSize);
  AssertEquals(1400, FLayout.Output.MaterialWidth, 1e-9);
  AssertEquals(900, FLayout.Output.MaterialLength, 1e-9);
  AssertTrue(FLayout.Output.AllowTurns);
  AssertFalse('already taken', FLayout.TakeMaterialSize);
end;

procedure TTestMaterialNeeded.TestLayoutKeepsSizeWithoutOne;
var
  Width: double;
begin
  AddPanel('Front', 0, 100, 100);
  AddToLayout('front.sloper');
  FLayout.Output.Kind := okMaterial;
  FLayout.Output.Material := 'Main';
  Width := FLayout.Output.MaterialWidth;
  AssertFalse(FLayout.TakeMaterialSize);
  AssertEquals(Width, FLayout.Output.MaterialWidth, 1e-9);
  FLayout.Output.Material := '';
  AssertFalse('no material chosen', FLayout.TakeMaterialSize);
end;

initialization
  RegisterTest(TTestMaterialNeeded);
end.
