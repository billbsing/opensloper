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

unit Sloper.Tests.Materials;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Materials,
  Sloper.Core.Piece;

type
  TTestMaterials = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function AddSquare(const PieceName: string; Left: double): TPieceObject;
    function Reloaded: TPattern;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNewPatternHasMain;
    procedure TestSimpleFileStaysSimple;
    procedure TestIdsDoNotMoveWhileMainIsImplicit;
    procedure TestFirstChangeGivesMainAnIdAndItsPieces;
    procedure TestNewPieceTakesFirstMaterial;
    procedure TestRoundTrip;
    procedure TestMaterialsMayFollowObjectsInFile;
    procedure TestNamesFollowNameRules;
    procedure TestNamesAreUniqueIgnoringCase;
    procedure TestNewMaterialsTakeFreeNamesAndColours;
    procedure TestRefusesBadColour;
    procedure TestRefusesDeletingLastMaterial;
    procedure TestRefusesDeletingUsedMaterial;
    procedure TestDeletesUnusedMaterial;
    procedure TestNoMaterialIsUnfilledAndAProblem;
    procedure TestLookComesFromMaterial;
    procedure TestPieceOverridesLook;
    procedure TestCaptionNamesExplicitMaterialOnly;
    procedure TestCutList;
    procedure TestRefusesUnknownMaterial;
    procedure TestRefusesRepeatedMaterialId;
    procedure TestRefusesBadFileColour;
    procedure TestRefusesEmptyMaterialList;
    procedure TestHatchAnglesDiffer;
    procedure TestColorTextRoundTrip;
    procedure TestTintIsLighter;
    procedure TestHatchLinesStayInsideSquare;
    procedure TestHatchSpansConcaveShape;
    procedure TestHatchOfNothing;
    procedure TestUndoTakesBackFirstChange;
    procedure TestUndoRestoresMaterialOfPiece;
    procedure TestProblemsFilterFindsNoMaterial;
    procedure TestSVGUsesMaterialColour;
    procedure TestSVGHatchesAHatchedMaterial;
    procedure TestSVGLeavesNoMaterialUnfilled;
    procedure TestSVGLabelNamesMaterial;
    procedure TestSettingsKeepFillsToggle;
  end;

implementation

uses
  Math, Sloper.Core.Draft, Sloper.Core.PatternCheck, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.Settings,
  Sloper.Document.PatternDocument, Sloper.Output.DraftSVG, Sloper.UI.ObjectList, Sloper.Core.PatternMaterials;

const
  SquareSize = 100;

procedure TTestMaterials.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestMaterials.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestMaterials.AddSquare(const PieceName: string; Left: double): TPieceObject;
var
  Corners: array[0..3] of TFreePoint;
  Path: TPiecePath;
  Reason: string;
  Index: integer;
  NumberText: string;
begin
  for Index := 0 to 3 do
  begin
    NumberText := PieceName + 'p' + IntToStr(Index);
    Corners[Index] := FPattern.AddFreePoint(NumberText, FloatToStr(Left + SquareSize * Ord(Index in [1, 2])), FloatToStr(SquareSize * Ord(Index in [2, 3])));
  end;
  for Index := 0 to 3 do
    FPattern.AddLine(Corners[Index].Key, Corners[(Index + 1) mod 4].Key, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + SquareSize / 2, SquareSize / 2), Path, Reason));
  Result := FPattern.AddPiece(PieceName, Path, '10');
  FPattern.Evaluate;
end;

function TTestMaterials.Reloaded: TPattern;
var
  Reason: string;
begin
  FreeAndNil(FLoaded);
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
  FLoaded.Evaluate;
  Result := FLoaded;
end;

procedure TTestMaterials.TestNewPatternHasMain;
begin
  AssertEquals(1, FPattern.MaterialCount);
  AssertEquals(DefaultMaterialName, FPattern.Materials[0].Name);
  AssertEquals('no ID yet', '', FPattern.Materials[0].Key);
  AssertTrue(IsMaterialColor(FPattern.Materials[0].Color));
end;

procedure TTestMaterials.TestSimpleFileStaysSimple;
var
  Text: string;
begin
  AddSquare('Front', 0);
  Text := SavePatternToText(FPattern);
  AssertEquals('no list', 0, Pos('"materials"', Text));
  AssertEquals('no material on the piece', 0, Pos('"material"', Text));
end;

procedure TTestMaterials.TestIdsDoNotMoveWhileMainIsImplicit;
var
  Before: integer;
begin
  Before := FPattern.NextId;
  AddSquare('Front', 0);
  AssertEquals('4 points, 4 edges and a piece', Before + 9, FPattern.NextId);
end;

procedure TTestMaterials.TestFirstChangeGivesMainAnIdAndItsPieces;
var
  Piece: TPieceObject;
begin
  Piece := AddSquare('Front', 0);
  AssertTrue(FPattern.RenameMaterial(FPattern.Materials[0], 'Denim'));
  AssertTrue('has an ID', FPattern.Materials[0].Key <> '');
  AssertEquals(FPattern.Materials[0].Key, Piece.MaterialKey);
  AssertTrue('still cut from it', FPattern.MaterialOf(Piece) = FPattern.Materials[0]);
end;

procedure TTestMaterials.TestNewPieceTakesFirstMaterial;
var
  Lining: TPatternMaterial;
begin
  Lining := FPattern.AddMaterial('Lining');
  AssertTrue(Assigned(Lining));
  AssertTrue(FPattern.MaterialOf(AddSquare('Front', 0)) = FPattern.Materials[0]);
end;

procedure TTestMaterials.TestRoundTrip;
var
  Piece, Back: TPieceObject;
  Lining: TPatternMaterial;
begin
  Piece := AddSquare('Front', 0);
  Lining := FPattern.AddMaterial('Lining', '#c9a227', ffHatch);
  FPattern.SetPieceMaterial(Piece, Lining);
  AssertTrue(FPattern.SetPieceFill(Piece, '#112233', pfTint));
  Reloaded;
  AssertEquals(2, FLoaded.MaterialCount);
  AssertEquals('Lining', FLoaded.Materials[1].Name);
  AssertEquals('#C9A227', FLoaded.Materials[1].Color);
  AssertTrue(FLoaded.Materials[1].Fill = ffHatch);
  Back := TPieceObject(FLoaded.FindObject('Front'));
  AssertEquals(Lining.Key, Back.MaterialKey);
  AssertEquals('#112233', Back.FillColor);
  AssertTrue(Back.FillStyle = pfTint);
  AssertEquals('saves the same', SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestMaterials.TestMaterialsMayFollowObjectsInFile;
var
  Reason: string;
begin
  FPattern.SetPieceMaterial(AddSquare('Front', 0), FPattern.AddMaterial('Lining'));
  // The writer puts materials after objects, so this is the ordinary case
  AssertTrue(Pos('"objects"', SavePatternToText(FPattern)) < Pos('"materials"', SavePatternToText(FPattern)));
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
end;

procedure TTestMaterials.TestNamesFollowNameRules;
begin
  AssertTrue(not Assigned(FPattern.AddMaterial('2nd')));
  AssertTrue(not Assigned(FPattern.AddMaterial('Inter facing')));
  AssertFalse(FPattern.RenameMaterial(FPattern.Materials[0], 'not a name'));
  AssertEquals('refused without changing', DefaultMaterialName, FPattern.Materials[0].Name);
  AssertEquals('stays implicit', '', FPattern.Materials[0].Key);
end;

procedure TTestMaterials.TestNamesAreUniqueIgnoringCase;
begin
  AssertTrue(not Assigned(FPattern.AddMaterial('MAIN')));
  AssertTrue(FPattern.LastError <> '');
  AssertTrue('own name in another case', FPattern.RenameMaterial(FPattern.Materials[0], 'MAIN'));
end;

procedure TTestMaterials.TestNewMaterialsTakeFreeNamesAndColours;
var
  First, Second: TPatternMaterial;
begin
  First := FPattern.AddMaterial;
  Second := FPattern.AddMaterial;
  AssertEquals(NewMaterialBaseName, First.Name);
  AssertEquals(NewMaterialBaseName + '2', Second.Name);
  AssertEquals(MaterialPalette[1], First.Color);
  AssertEquals(MaterialPalette[2], Second.Color);
end;

procedure TTestMaterials.TestRefusesBadColour;
begin
  AssertFalse(FPattern.SetMaterialColor(FPattern.Materials[0], 'blue'));
  AssertFalse(FPattern.SetMaterialColor(FPattern.Materials[0], '#12345G'));
  AssertTrue(not Assigned(FPattern.AddMaterial('Lining', '#123')));
  AssertFalse(FPattern.SetPieceFill(AddSquare('Front', 0), 'red', pfMaterial));
end;

procedure TTestMaterials.TestRefusesDeletingLastMaterial;
begin
  AssertFalse(FPattern.DeleteMaterial(FPattern.Materials[0]));
  AssertEquals(rsPatternLastMaterial, FPattern.LastError);
end;

procedure TTestMaterials.TestRefusesDeletingUsedMaterial;
var
  Lining: TPatternMaterial;
begin
  Lining := FPattern.AddMaterial('Lining');
  FPattern.SetPieceMaterial(AddSquare('Front', 0), Lining);
  AssertFalse(FPattern.DeleteMaterial(Lining));
  AssertEquals(Format(rsPatternMaterialInUse, ['Lining', 'Front']), FPattern.LastError);
  AssertEquals(2, FPattern.MaterialCount);
end;

procedure TTestMaterials.TestDeletesUnusedMaterial;
begin
  AssertTrue(FPattern.DeleteMaterial(FPattern.AddMaterial('Lining')));
  AssertEquals(1, FPattern.MaterialCount);
end;

procedure TTestMaterials.TestNoMaterialIsUnfilledAndAProblem;
var
  Piece: TPieceObject;
  Blocked: integer;
  Problems: TStringArray;
begin
  Piece := AddSquare('Front', 0);
  AssertEquals('none at first', 0, Length(PatternProblems(FPattern, Blocked)));
  FPattern.SetPieceMaterial(Piece, nil);
  AssertTrue('Main is explicit', FPattern.Materials[0].Key <> '');
  AssertTrue(not Assigned(FPattern.MaterialOf(Piece)));
  AssertFalse(FPattern.PieceLook(Piece).Filled);
  Problems := PatternProblems(FPattern, Blocked);
  AssertEquals(1, Length(Problems));
  AssertEquals(Format(rsCheckNoMaterial, ['Front']), Problems[0]);
  AssertTrue('survives saving', not Assigned(Reloaded.MaterialOf(TPieceObject(FLoaded.FindObject('Front')))));
end;

procedure TTestMaterials.TestLookComesFromMaterial;
var
  Piece: TPieceObject;
  Look: TPieceLook;
begin
  Piece := AddSquare('Front', 0);
  AssertTrue(FPattern.SetMaterialColor(FPattern.Materials[0], '#102030'));
  FPattern.SetMaterialFill(FPattern.Materials[0], ffHatch);
  Look := FPattern.PieceLook(Piece);
  AssertTrue(Look.Filled);
  AssertEquals('#102030', MaterialColorText(Look.Color));
  AssertTrue(Look.Fill = ffHatch);
end;

procedure TTestMaterials.TestPieceOverridesLook;
var
  Piece: TPieceObject;
  Look: TPieceLook;
begin
  Piece := AddSquare('Front', 0);
  FPattern.SetMaterialFill(FPattern.Materials[0], ffHatch);
  AssertTrue(FPattern.SetPieceFill(Piece, '#ABCDEF', pfTint));
  Look := FPattern.PieceLook(Piece);
  AssertEquals('#ABCDEF', MaterialColorText(Look.Color));
  AssertTrue(Look.Fill = ffTint);
  AssertTrue(FPattern.SetPieceFill(Piece, '', pfMaterial));
  Look := FPattern.PieceLook(Piece);
  AssertEquals(FPattern.Materials[0].Color, MaterialColorText(Look.Color));
  AssertTrue(Look.Fill = ffHatch);
end;

procedure TTestMaterials.TestCaptionNamesExplicitMaterialOnly;
var
  Piece: TPieceObject;
begin
  Piece := AddSquare('Front', 0);
  AssertEquals('Front, cut 1', FPattern.PieceCaption(Piece));
  FPattern.SetPieceMaterial(Piece, FPattern.AddMaterial('Lining'));
  AssertEquals('Front, cut 1, Lining', FPattern.PieceCaption(Piece));
end;

procedure TTestMaterials.TestCutList;
var
  Front, Back, Yoke: TPieceObject;
begin
  Front := AddSquare('Front', 0);
  Back := AddSquare('Back', 200);
  Yoke := AddSquare('Yoke', 400);
  AssertTrue(FPattern.SetCut(Back, 2, False));
  AssertEquals('Main: Front ×1, Back ×2, Yoke ×1', FPattern.CutList);
  FPattern.SetPieceMaterial(Yoke, FPattern.AddMaterial('Lining'));
  AssertTrue(FPattern.SetFoldEdge(Front, Front.Path[0].EdgeKey));
  AssertTrue(FPattern.SetCut(Back, 2, True));
  AssertEquals('Main: Front ×1 on fold, Back ×2 mirrored · Lining: Yoke ×1', FPattern.CutList);
  FPattern.SetPieceMaterial(Yoke, nil);
  AssertEquals('Main: Front ×1 on fold, Back ×2 mirrored · ' + rsPatternNoMaterial + ': Yoke ×1', FPattern.CutList);
  AssertEquals('Main, Lining', FPattern.MaterialNames);
end;

const
  FileStart = '{"format":"pattern","version":1,"variables":[],';

procedure TTestMaterials.TestRefusesUnknownMaterial;
var
  Reason, Text: string;
begin
  FPattern.AddMaterial('Lining');
  AddSquare('Front', 0);
  Text := StringReplace(SavePatternToText(FPattern), '"material": ' + FPattern.Materials[0].Key, '"material": 999', []);
  AssertTrue('the test changed the file', Text <> SavePatternToText(FPattern));
  FLoaded := TPattern.Create;
  AssertFalse(LoadPatternFromText(FLoaded, Text, Reason));
  AssertTrue(Reason, Pos('material', Reason) > 0);
end;

procedure TTestMaterials.TestRefusesRepeatedMaterialId;
var
  Reason: string;
begin
  FLoaded := TPattern.Create;
  AssertFalse(LoadPatternFromText(FLoaded, FileStart + '"objects":[],"materials":[' +
    '{"id":1,"name":"A","color":"#112233"},{"id":1,"name":"B","color":"#112233"}]}', Reason));
  AssertEquals(Format(rsPatternFileBadId, [2, 'materials']), Reason);
end;

procedure TTestMaterials.TestRefusesBadFileColour;
var
  Reason: string;
begin
  FLoaded := TPattern.Create;
  AssertFalse(LoadPatternFromText(FLoaded, FileStart + '"objects":[],"materials":[{"id":1,"name":"A","color":"red"}]}', Reason));
  AssertTrue(Reason, Pos('red', Reason) > 0);
end;

procedure TTestMaterials.TestRefusesEmptyMaterialList;
var
  Reason: string;
begin
  FLoaded := TPattern.Create;
  AssertFalse(LoadPatternFromText(FLoaded, FileStart + '"objects":[],"materials":[]}', Reason));
  AssertEquals(Format(rsPatternFileList, ['materials']), Reason);
end;

procedure TTestMaterials.TestHatchAnglesDiffer;
begin
  AssertTrue(MaterialHatchAngle(0) <> MaterialHatchAngle(1));
  AssertTrue(MaterialHatchAngle(1) <> MaterialHatchAngle(2));
end;

procedure TTestMaterials.TestColorTextRoundTrip;
begin
  AssertEquals('#5B8DB8', MaterialColorText(ParseMaterialColor('#5b8db8')));
  AssertEquals('#000000', MaterialColorText(ParseMaterialColor('nonsense')));
end;

procedure TTestMaterials.TestTintIsLighter;
var
  Tint: TMaterialColor;
begin
  Tint := MaterialTint(ParseMaterialColor('#000000'));
  AssertEquals(178, Tint.Red);
  Tint := MaterialTint(ParseMaterialColor('#FFFFFF'));
  AssertEquals(255, Tint.Blue);
end;

procedure TTestMaterials.TestHatchLinesStayInsideSquare;
const
  Tolerance = 1e-6;
var
  Square: TVec2Array;
  Lines: TLine2Array;
  Line: TLine2;
begin
  Square := nil;
  SetLength(Square, 4);
  Square[0] := Vec2(0, 0);
  Square[1] := Vec2(100, 0);
  Square[2] := Vec2(100, 100);
  Square[3] := Vec2(0, 100);
  Lines := HatchLines(Square, 10, 45);
  AssertTrue(Length(Lines) > 10);
  for Line in Lines do
  begin
    AssertTrue(Min(Line.P1.X, Line.P2.X) >= -Tolerance);
    AssertTrue(Max(Line.P1.X, Line.P2.X) <= 100 + Tolerance);
    AssertTrue(Min(Line.P1.Y, Line.P2.Y) >= -Tolerance);
    AssertTrue(Max(Line.P1.Y, Line.P2.Y) <= 100 + Tolerance);
  end;
  // Level rows through a square that sits on the rows: every one spans it
  Lines := HatchLines(Square, 10, 0);
  AssertEquals('rows 0 to 90', 10, Length(Lines));
  for Line in Lines do
    AssertEquals(100, Abs(Line.P2.X - Line.P1.X), Tolerance);
end;

procedure TTestMaterials.TestHatchSpansConcaveShape;
var
  Notched: TVec2Array;
  Lines: TLine2Array;
begin
  // A U: a level row across the arms is two lines, not one across the gap
  Notched := nil;
  SetLength(Notched, 8);
  Notched[0] := Vec2(0, 0);
  Notched[1] := Vec2(30, 0);
  Notched[2] := Vec2(30, -25);
  Notched[3] := Vec2(20, -25);
  Notched[4] := Vec2(20, -5);
  Notched[5] := Vec2(10, -5);
  Notched[6] := Vec2(10, -25);
  Notched[7] := Vec2(0, -25);
  Lines := HatchLines(Notched, 20, 0);
  AssertEquals('one across the base at 0, two across the arms at 20', 3, Length(Lines));
  AssertEquals(10, Abs(Lines[1].P2.X - Lines[1].P1.X), 1e-6);
  AssertEquals(10, Abs(Lines[2].P2.X - Lines[2].P1.X), 1e-6);
end;

procedure TTestMaterials.TestHatchOfNothing;
begin
  AssertEquals(0, Length(HatchLines(nil, 10, 45)));
end;

procedure TTestMaterials.TestUndoTakesBackFirstChange;
var
  Document: TPatternDocument;
  Reason: string;
begin
  Document := TPatternDocument.Create;
  try
    AddSquare('Front', 0);
    AssertTrue(Reason, LoadPatternFromText(Document.Pattern, SavePatternToText(FPattern), Reason));
    Document.Pattern.Evaluate;
    Document.BeginChange('add');
    AssertTrue(Document.Commit(Assigned(Document.Pattern.AddMaterial('Lining'))));
    AssertEquals(2, Document.Pattern.MaterialCount);
    AssertTrue(Document.Undo);
    AssertEquals(1, Document.Pattern.MaterialCount);
    AssertEquals('Main is implicit again', '', Document.Pattern.Materials[0].Key);
    AssertEquals('', TPieceObject(Document.Pattern.FindObject('Front')).MaterialKey);
    AssertTrue(Document.Redo);
    AssertEquals(2, Document.Pattern.MaterialCount);
    AssertEquals('Lining', Document.Pattern.Materials[1].Name);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestMaterials.TestUndoRestoresMaterialOfPiece;
var
  Document: TPatternDocument;
  Reason, Key: string;
begin
  Document := TPatternDocument.Create;
  try
    FPattern.AddMaterial('Lining');
    AddSquare('Front', 0);
    AssertTrue(Reason, LoadPatternFromText(Document.Pattern, SavePatternToText(FPattern), Reason));
    Document.Pattern.Evaluate;
    Key := Document.Pattern.FindObject('Front').Key;
    Document.BeginChange('material');
    Document.Pattern.SetPieceMaterial(TPieceObject(Document.Pattern.FindNode(Key)), Document.Pattern.Materials[1]);
    AssertTrue(Document.EndChange);
    AssertTrue(Document.Undo);
    AssertTrue(Document.Pattern.MaterialOf(TPieceObject(Document.Pattern.FindNode(Key))) = Document.Pattern.Materials[0]);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestMaterials.TestProblemsFilterFindsNoMaterial;
var
  Piece: TPieceObject;
begin
  Piece := AddSquare('Front', 0);
  AssertEquals(0, Length(ObjectRows(FPattern, ofProblems, '')));
  FPattern.SetPieceMaterial(Piece, nil);
  AssertEquals(1, Length(ObjectRows(FPattern, ofProblems, '')));
end;

procedure TTestMaterials.TestSVGUsesMaterialColour;
var
  Tint: string;
begin
  AddSquare('Front', 0);
  AssertTrue(FPattern.SetMaterialColor(FPattern.Materials[0], '#000000'));
  Tint := LowerCase(MaterialColorText(MaterialTint(ParseMaterialColor('#000000'))));
  AssertTrue(Pos('fill="' + Tint + '"', DraftToSVG(FPattern, DefaultDraftSVGOptions)) > 0);
end;

procedure TTestMaterials.TestSVGHatchesAHatchedMaterial;
var
  Text: string;
begin
  AddSquare('Front', 0);
  FPattern.SetMaterialFill(FPattern.Materials[0], ffHatch);
  Text := DraftToSVG(FPattern, DefaultDraftSVGOptions);
  AssertTrue('hatched', Pos('data-hatch="Front"', Text) > 0);
end;

procedure TTestMaterials.TestSVGLeavesNoMaterialUnfilled;
var
  Text: string;
begin
  FPattern.SetPieceMaterial(AddSquare('Front', 0), nil);
  Text := DraftToSVG(FPattern, DefaultDraftSVGOptions);
  AssertEquals('no hatching', 0, Pos('data-hatch', Text));
  AssertEquals('no tint', 0, Pos('fill="#d', Text));
end;

procedure TTestMaterials.TestSVGLabelNamesMaterial;
var
  Options: TDraftSVGOptions;
begin
  Options := DefaultDraftSVGOptions;
  Options.Labels := True;
  FPattern.SetPieceMaterial(AddSquare('Front', 0), FPattern.AddMaterial('Lining'));
  AssertTrue(Pos('Front, cut 1, Lining', DraftToSVG(FPattern, Options)) > 0);
end;

procedure TTestMaterials.TestSettingsKeepFillsToggle;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    AssertTrue('on by default', Settings.ShowPieceFills);
    Settings.ShowPieceFills := False;
    AssertTrue(Reason, Settings.LoadFromText(Settings.SaveToText, Reason));
    AssertFalse(Settings.ShowPieceFills);
  finally
    FreeAndNil(Settings);
  end;
end;

initialization
  RegisterTest(TTestMaterials);
end.
