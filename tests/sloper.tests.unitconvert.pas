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

// Converting a pattern's unit: the role of each plain number, and geometry
// that does not move.
unit Sloper.Tests.UnitConvert;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Draft, Sloper.Core.Pattern,
  Sloper.Core.UnitConvert;

type
  TTestUnitConvert = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Check(Obj: TObject): TObject;
    function Pt(const AName, X, Y: string): TPointObject;
    // The numbers of one field, in order, as "value:power" or "value:?"
    function Roles(Node: TObject; const FieldName: string; const Marks: TUnitMarkArray): string;
    function Roles(Node: TObject; const FieldName: string): string;
    procedure BuildEveryKind;
    function Geometry: string;
    procedure Convert(ToUnits: integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFieldSettlesALiteral;
    procedure TestFactorsOfALength;
    procedure TestAnglesAndCounts;
    procedure TestPowersAndRoots;
    procedure TestTwoBareNumbersUndecided;
    procedure TestMarkSettlesTheOther;
    procedure TestVariableTakesItsUses;
    procedure TestVariableUsedBothWays;
    procedure TestNoteValueFactor;
    procedure TestAlongEdgeByMode;
    procedure TestSuffixIsNotANumber;
    procedure TestConvertedNumber;
    procedure TestConvertRewritesLengthsOnly;
    procedure TestConvertRefusesUndecided;
    procedure TestConvertRefusesSameUnit;
    procedure TestMaterialAllowanceConverted;
    procedure TestGeometryDoesNotMove;
    procedure TestRoundTrip;
    procedure TestRegressionPatterns;
  end;

implementation

uses
  SysUtils, Math, Sloper.Core.Units, Sloper.Core.Geometry, Sloper.Core.Evaluator, Sloper.Core.EvalTypes, Sloper.Core.Variables,
  Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Seam, Sloper.Core.Note, Sloper.Core.Transform, Sloper.Core.PatternFile;

const
  REGRESSION_PATTERN_NAMES: array[0..1] of string = ('skirt-block.sloper', 'skirt-pieces.sloper');

procedure TTestUnitConvert.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestUnitConvert.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestUnitConvert.Check(Obj: TObject): TObject;
begin
  if not Assigned(Obj) then
    Fail('Refused: ' + FPattern.LastError);
  Result := Obj;
end;

function TTestUnitConvert.Pt(const AName, X, Y: string): TPointObject;
begin
  Result := TPointObject(Check(FPattern.AddFreePoint(AName, X, Y)));
end;

function TTestUnitConvert.Roles(Node: TObject; const FieldName: string; const Marks: TUnitMarkArray): string;
var
  Number: TUnitNumber;
  Item: string;
begin
  Result := '';
  for Number in AnalyseUnits(FPattern, Marks).Numbers do
    if (Number.NodeKey = TEvalNode(Node).Key) and (Number.FieldName = FieldName) then
    begin
      if Number.Decided then
        Item := FloatToStr(Number.Value) + ':' + FloatToStr(Number.Power)
      else
        Item := FloatToStr(Number.Value) + ':?';
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Item;
    end;
end;

function TTestUnitConvert.Roles(Node: TObject; const FieldName: string): string;
begin
  Result := Roles(Node, FieldName, nil);
end;

procedure TTestUnitConvert.TestFieldSettlesALiteral;
var
  A: TPointObject;
begin
  A := Pt('A', '400', '-25');
  AssertEquals('x', '400:1', Roles(A, 'x'));
  AssertEquals('y', '25:1', Roles(A, 'y'));
end;

procedure TTestUnitConvert.TestFactorsOfALength;
var
  A: TPointObject;
begin
  A := Pt('A', '@waist * 2', '@waist / 4 + 10');
  AssertEquals('times a length', '2:0', Roles(A, 'x'));
  AssertEquals('divides a length; added to a length', '4:0 10:1', Roles(A, 'y'));
end;

procedure TTestUnitConvert.TestAnglesAndCounts;
var
  A, B: TPointObject;
  Edge: TLineObject;
  Repeated: TRepeatObject;
begin
  A := Pt('A', '0', '0');
  B := TPointObject(Check(FPattern.AddOffsetPoint('B', A.Key, omPolar, '50', '45 + 2 * 10')));
  Edge := TLineObject(Check(FPattern.AddLine(A.Key, B.Key)));
  Repeated := TRepeatObject(Check(FPattern.AddRepeatOnEdge('R', Edge.Key, '3', False)));
  AssertEquals('angle', '45:0 2:0 10:0', Roles(B, 'angle'));
  AssertEquals('count', '3:0', Roles(Repeated, 'count'));
end;

procedure TTestUnitConvert.TestPowersAndRoots;
var
  A: TPointObject;
begin
  A := Pt('A', 'sqrt(400^2 + 300^2)', '100 * sin(30)');
  AssertEquals('Pythagoras', '400:1 2:0 300:1 2:0', Roles(A, 'x'));
  AssertEquals('a length times a sine', '100:1 30:0', Roles(A, 'y'));
end;

procedure TTestUnitConvert.TestTwoBareNumbersUndecided;
var
  A: TPointObject;
begin
  A := Pt('A', '400 * 2', '0');
  AssertEquals('either could be the length', '400:? 2:?', Roles(A, 'x'));
end;

procedure TTestUnitConvert.TestMarkSettlesTheOther;
var
  A: TPointObject;
  Analysis: TUnitAnalysis;
  Marks: TUnitMarkArray;
begin
  A := Pt('A', '400 * 2', '0');
  Analysis := AnalyseUnits(FPattern, nil);
  AssertEquals('both open', 2, UndecidedCount(Analysis.Numbers));
  Marks := [MarkFor(Analysis.Numbers[1], False)];
  AssertEquals('400 follows', '400:1 2:0', Roles(A, 'x', Marks));
end;

procedure TTestUnitConvert.TestVariableTakesItsUses;
var
  Ease: TVariable;
begin
  Ease := TVariable(Check(FPattern.AddVariable('ease', '10 + @waist / 100')));
  Pt('A', '#ease', '0');
  AssertEquals('a length, from its use', '10:1 100:0', Roles(Ease, 'formula'));
end;

procedure TTestUnitConvert.TestVariableUsedBothWays;
var
  Many: TVariable;
  A: TPointObject;
begin
  Many := TVariable(Check(FPattern.AddVariable('many', '5')));
  A := Pt('A', '#many', '0');
  Check(FPattern.AddRepeatBetween('R', A.Key, Pt('B', '100', '0').Key, '#many', False));
  AssertEquals('a length and a count', '5:?', Roles(Many, 'formula'));
end;

procedure TTestUnitConvert.TestNoteValueFactor;
var
  Note: TNoteObject;
begin
  Note := TNoteObject(Check(FPattern.AddNote('', 'Quarter {=@waist / 4} and {=@waist + 20}', naFree, '', '', '0', '0')));
  AssertEquals('divides a length', '4:0', Roles(Note, Note.ValueField(0)));
  AssertEquals('added to a length', '20:1', Roles(Note, Note.ValueField(1)));
end;

procedure TTestUnitConvert.TestAlongEdgeByMode;
var
  Edge: TLineObject;
  ByLength, ByRatio: TPointObject;
begin
  Edge := TLineObject(Check(FPattern.AddLine(Pt('A', '0', '0').Key, Pt('B', '100', '0').Key)));
  ByLength := TPointObject(Check(FPattern.AddAlongEdgePoint('C', Edge.Key, False, amLength, '30')));
  ByRatio := TPointObject(Check(FPattern.AddAlongEdgePoint('D', Edge.Key, False, amRatio, '0.5')));
  AssertEquals('length', '30:1', Roles(ByLength, 'value'));
  AssertEquals('ratio', '0.5:0', Roles(ByRatio, 'value'));
end;

procedure TTestUnitConvert.TestSuffixIsNotANumber;
var
  A: TPointObject;
begin
  A := Pt('A', '2in * 3', '1cm + 4');
  AssertEquals('times a length', '3:0', Roles(A, 'x'));
  AssertEquals('added to a length', '4:1', Roles(A, 'y'));
end;

procedure TTestUnitConvert.TestConvertedNumber;
begin
  AssertNear('400 mm to 0.01 in', 15.75, ConvertedNumber(400, 1, muMillimetre, muInch));
  AssertNear('to 0.1 cm', 40, ConvertedNumber(400, 1, muMillimetre, muCentimetre));
  AssertNear('to 0.1 mm', 9.5, ConvertedNumber(0.375, 1, muInch, muMillimetre));
  AssertNear('a number stays', 4, ConvertedNumber(4, 0, muMillimetre, muInch));
  AssertNear('an area', 4, ConvertedNumber(400, 2, muMillimetre, muCentimetre));
  AssertNear('small, kept to two figures', 0.0039, ConvertedNumber(0.1, 1, muMillimetre, muInch));
end;

procedure TTestUnitConvert.Convert(ToUnits: integer);
var
  Err: string;
begin
  AssertTrue(Err, ConvertPatternUnits(FPattern, TMeasureUnit(ToUnits), AnalyseUnits(FPattern, nil).Numbers, Err));
  FPattern.Evaluate;
end;

procedure TTestUnitConvert.TestConvertRewritesLengthsOnly;
var
  A: TPointObject;
begin
  A := Pt('A', '@waist / 4 + 20', '-(30 + 2in) * 2');
  Convert(Ord(muCentimetre));
  AssertTrue('the pattern is in cm', FPattern.Units = muCentimetre);
  AssertEquals('x', '@waist / 4 + 2', FPattern.FormulaText(A, 'x'));
  AssertEquals('suffix kept', '-(3 + 2in) * 2', FPattern.FormulaText(A, 'y'));
  AssertPointsNear('same place', Vec2(200, -161.6), A.Position);
end;

procedure TTestUnitConvert.TestConvertRefusesUndecided;
var
  Err: string;
begin
  Pt('A', '400 * 2', '0');
  AssertFalse(ConvertPatternUnits(FPattern, muInch, AnalyseUnits(FPattern, nil).Numbers, Err));
  AssertEquals(Format(rsConvertUndecided, [2]), Err);
  AssertTrue('unchanged', FPattern.Units = muMillimetre);
end;

procedure TTestUnitConvert.TestConvertRefusesSameUnit;
var
  Err: string;
begin
  AssertFalse(ConvertPatternUnits(FPattern, muMillimetre, nil, Err));
  AssertEquals(Format(rsConvertSameUnit, ['mm']), Err);
end;

procedure TTestUnitConvert.TestMaterialAllowanceConverted;
begin
  FPattern.Materials[0].HasAllowance := True;
  FPattern.Materials[0].Allowance := 15;
  Convert(Ord(muCentimetre));
  AssertNear('1.5 cm', 1.5, FPattern.Materials[0].Allowance);
end;

// Something of every kind, in whole millimetres, so a conversion to cm
// rounds nothing away
procedure TTestUnitConvert.BuildEveryKind;
var
  A, B, C, D, Path: TPointObject;
  AB, BC, CD, DA, Curve: TEdgeObject;
  Piece: TPieceObject;
  PiecePath: TPiecePath;
  Side: TSeamSide;
  Spec: TTransformSpec;
  Reason: string;
begin
  Check(FPattern.AddVariable('ease', '10 + @waist / 72'));
  A := Pt('A', '0', '0');
  B := Pt('B', '@waist / 4 + #ease', '0');
  C := TPointObject(Check(FPattern.AddOffsetPoint('C', B.Key, omCartesian, '0', '200')));
  D := TPointObject(Check(FPattern.AddOffsetPoint('D', A.Key, omPolar, '200', '270')));
  AB := TEdgeObject(Check(FPattern.AddLine(A.Key, B.Key, erOutline)));
  BC := TEdgeObject(Check(FPattern.AddLine(B.Key, C.Key, erOutline)));
  CD := TEdgeObject(Check(FPattern.AddLine(C.Key, D.Key, erOutline)));
  DA := TEdgeObject(Check(FPattern.AddLine(D.Key, A.Key, erOutline)));
  Check(FPattern.AddAlongEdgePoint('E', AB.Key, False, amLength, '30'));
  Check(FPattern.AddAlongEdgePoint('F', AB.Key, True, amRatio, '0.25'));
  Check(FPattern.AddBetweenPoint('G', A.Key, C.Key, amLength, '40'));
  Check(FPattern.AddCircleCirclePoint('H', A.Key, '150', B.Key, '150', 1));
  Check(FPattern.AddCircleEdgePoint('I', A.Key, '250', BC.Key, True, 1));
  Check(FPattern.AddProjectPoint('J', FPattern.FindObject('E').Key, CD.Key, pdAngle, '-80', True));
  Check(FPattern.AddRepeatOnEdge('K', CD.Key, '3', False));
  Curve := TEdgeObject(Check(FPattern.AddCurve(A.Key, C.Key, '-30', '60', '120', '50')));
  Check(FPattern.AddArc(A.Key, '20', '0', '90'));
  Check(FPattern.AddCircle(C.Key, '10'));
  Check(FPattern.AddOffsetEdge(Curve.Key, '10', osLeft, erConstruction));
  Path := Pt('L', '50', '100');
  Check(FPattern.AddCurvePath([A.Key, Path.Key, C.Key], ['-45', '0', '45'], ['', '20', '30'], ['20', '30', '']));
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Path.Key, pmButton, '15'));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [A.Key, B.Key, AB.Key];
  Spec.Polar := False;
  Spec.DX := '300';
  Spec.DY := '20';
  Spec.Pivot := A.Key;
  Spec.Rotate := '10';
  Check(FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), PiecePath, Reason));
  Piece := TPieceObject(Check(FPattern.AddPiece('Front', PiecePath, '10')));
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Piece, 0, '20'));
  AssertTrue(FPattern.LastError, FPattern.AddEdgeNotch(Piece, BC.Key, '50'));
  AssertTrue(FPattern.LastError, FPattern.AddStitchMarking(Piece, DA.Key, '4', '1'));
  Side := nil;
  SetLength(Side, 1);
  Side[0].PieceKey := Piece.Key;
  Side[0].EdgeKey := AB.Key;
  Check(FPattern.AddSeam('', Side, Side, '5', '2'));
  Check(FPattern.AddNote('', 'Waist {=@waist / 4 + #ease}', naPoint, B.Key, '', '10', '20'));
  FPattern.Evaluate;
end;

// Every computed position and length, to 0.01 mm
function TTestUnitConvert.Geometry: string;
var
  Index: integer;
  Node: TDraftObject;
  Item: string;
  At: TVec2;
begin
  Result := '';
  for Index := 0 to FPattern.ObjectCount - 1 do
  begin
    Node := FPattern.Objects[Index];
    AssertTrue(Node.DisplayName + ': ' + Node.Message, Node.State = esValid);
    Item := Node.DisplayName;
    if Node is TPointObject then
      Item := Item + Format(' %.2f,%.2f', [TPointObject(Node).Position.X, TPointObject(Node).Position.Y]);
    if Node is TEdgeObject then
      Item := Item + Format(' %.2f', [TEdgeObject(Node).Length]);
    if Node is TPieceObject then
      for At in TPieceObject(Node).CutLine do
        Item := Item + Format(' %.2f,%.2f', [At.X, At.Y]);
    if Node is TSeamObject then
      Item := Item + Format(' %.2f %.2f', [TSeamObject(Node).Ease, TSeamObject(Node).Difference]);
    if Node is TNoteObject then
      Item := Item + Format(' %.2f,%.2f', [TNoteObject(Node).Position.X, TNoteObject(Node).Position.Y]);
    Item := Item + Format(' %.2f', [Node.MarkerSize]);
    Result := Result + Item + LineEnding;
  end;
end;

procedure TTestUnitConvert.TestGeometryDoesNotMove;
var
  Before: string;
begin
  BuildEveryKind;
  Before := Geometry;
  AssertEquals('nothing to ask', 0, UndecidedCount(AnalyseUnits(FPattern, nil).Numbers));
  Convert(Ord(muCentimetre));
  AssertEquals('cm', Before, Geometry);
  Convert(Ord(muMillimetre));
  AssertEquals('and back', Before, Geometry);
end;

procedure TTestUnitConvert.TestRoundTrip;
var
  Before: string;
begin
  BuildEveryKind;
  Before := SavePatternToText(FPattern);
  Convert(Ord(muCentimetre));
  Convert(Ord(muMillimetre));
  AssertEquals('the same file', Before, SavePatternToText(FPattern));
end;

// The skirt patterns in tests/patterns, with their measurements: nothing for
// the user to mark, and nothing moves on the way to cm and back
procedure TTestUnitConvert.TestRegressionPatterns;
var
  Folder, PatternName, Err, Before: string;
begin
  Folder := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'patterns']);
  AssertTrue(Err, FSet.LoadFromFile(ConcatPaths([Folder, 'skirt-small.slm']), Err));
  for PatternName in REGRESSION_PATTERN_NAMES do
  begin
    AssertTrue(Err, LoadPatternFromFile(FPattern, ConcatPaths([Folder, PatternName]), Err));
    FPattern.Evaluate;
    Before := Geometry;
    AssertEquals(PatternName + ': nothing to ask', 0, UndecidedCount(AnalyseUnits(FPattern, nil).Numbers));
    Convert(Ord(muCentimetre));
    AssertEquals(PatternName + ' in cm', Before, Geometry);
    Convert(Ord(muMillimetre));
    AssertEquals(PatternName + ' and back', Before, Geometry);
  end;
end;

initialization
  RegisterTest(TTestUnitConvert);
end.
