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

// Copy and paste: a second line on the same points, pasting into another
// pattern with what the copy depends on, names, variables and IDs.
unit Sloper.Tests.Fragment;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern,
  Sloper.Core.Fragment;

type
  TTestFragment = class(TOSTestCase)
  private
    FPattern, FOther: TPattern;
    function Pt(Pattern: TPattern; const AName: string; X, Y: integer): string;
    function Paste(Pattern: TPattern; const Text: string): TFragmentPaste;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMapStoredFormula;
    procedure TestLineOnSamePoints;
    procedure TestCurveKeepsHandles;
    procedure TestPointsAndLineAreCopied;
    procedure TestOtherPatternTakesWhatItNeeds;
    procedure TestOtherPatternUsesSameVariable;
    procedure TestOtherPatternRenamesVariable;
    procedure TestTransformLeftOut;
    procedure TestTransformCopyAsPlainEdge;
    procedure TestOtherUnitsRefused;
    procedure TestNotAFragment;
    procedure TestPastedStitchLineJoinsPiece;
    procedure TestSurvivesSaveAndLoad;
  end;

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Units, Sloper.Core.Transform, Sloper.Core.Variables, Sloper.Core.Piece, Sloper.Core.PatternFile;

procedure TTestFragment.SetUp;
begin
  FPattern := TPattern.Create;
  FPattern.Identity := NewPatternIdentity;
  FOther := TPattern.Create;
  FOther.Identity := NewPatternIdentity;
end;

procedure TTestFragment.TearDown;
begin
  FreeAndNil(FOther);
  FreeAndNil(FPattern);
end;

function TTestFragment.Pt(Pattern: TPattern; const AName: string; X, Y: integer): string;
begin
  Result := Pattern.AddFreePoint(AName, IntToStr(X), IntToStr(Y)).Key;
end;

function TTestFragment.Paste(Pattern: TPattern; const Text: string): TFragmentPaste;
var
  Reason: string;
  Done: boolean;
begin
  Done := PasteFragment(Pattern, Text, Result, Reason);
  AssertTrue('pastes: ' + Reason, Done);
  Pattern.Evaluate;
end;

procedure TTestFragment.TestMapStoredFormula;
var
  Map: TPatternIdMap;
begin
  Map := TPatternIdMap.Create;
  try
    Map.Add('3', '30');
    Map.Add('12', '7');
    AssertEquals('{30}.x + {7} * @waist / {4}.length', MapStoredFormula('{3}.x + {12} * @waist / {4}.length', Map));
  finally
    FreeAndNil(Map);
  end;
end;

procedure TTestFragment.TestLineOnSamePoints;
var
  A, B, Line: string;
  Pasted: TFragmentPaste;
  Copy: TEdgeObject;
  Count: integer;
begin
  A := Pt(FPattern, 'A', 0, 0);
  B := Pt(FPattern, 'B', 100, 0);
  Line := FPattern.AddLine(A, B, erOutline).Key;
  FPattern.Evaluate;
  Count := FPattern.ObjectCount;
  Pasted := Paste(FPattern, CopyFragment(FPattern, [Line]).Text);
  AssertEquals('one object added', Count + 1, FPattern.ObjectCount);
  AssertEquals(1, Length(Pasted.Keys));
  AssertTrue('a new ID', Pasted.Keys[0] <> Line);
  Copy := FPattern.FindNode(Pasted.Keys[0]) as TEdgeObject;
  AssertTrue('a line', Copy is TLineObject);
  AssertEquals('starts at A', A, Copy.StartKey);
  AssertEquals('ends at B', B, Copy.EndKey);
  AssertEquals('keeps its role', Ord(erOutline), Ord(Copy.Role));
  AssertEquals('named as a second line', 'Line_A_B2', Copy.Name);
  AssertEquals('the original keeps its name', 'Line_A_B', FPattern.FindNode(Line).DisplayName);
  AssertEquals('derived names are not reported', 0, Length(Pasted.Renamed));
end;

procedure TTestFragment.TestCurveKeepsHandles;
var
  A, B, Curve: string;
  Copy: TCurveObject;
begin
  A := Pt(FPattern, 'A', 0, 0);
  B := Pt(FPattern, 'B', 100, 0);
  Curve := FPattern.AddCurve(A, B, '30', '40', '150', 'A.x + 40', erOutline).Key;
  FPattern.Evaluate;
  Copy := FPattern.FindNode(Paste(FPattern, CopyFragment(FPattern, [Curve]).Text).Keys[0]) as TCurveObject;
  AssertEquals('same points', A, Copy.StartKey);
  AssertEquals('A.x + 40', FPattern.FormulaText(Copy, 'length2'));
  AssertPointsNear('same handle', TCurveObject(FPattern.FindNode(Curve)).Curve.P2, Copy.Curve.P2);
end;

procedure TTestFragment.TestPointsAndLineAreCopied;
var
  A, B, Line: string;
  Pasted: TFragmentPaste;
  Copy: TEdgeObject;
begin
  A := Pt(FPattern, 'A', 0, 0);
  B := FPattern.AddOffsetPoint('B', A, omCartesian, '50', '0').Key;
  Line := FPattern.AddLine(A, B).Key;
  FPattern.Evaluate;
  Pasted := Paste(FPattern, CopyFragment(FPattern, [A, B, Line]).Text);
  AssertEquals(3, Length(Pasted.Keys));
  AssertEquals('A2', FPattern.FindNode(Pasted.Keys[0]).DisplayName);
  AssertEquals('B2', FPattern.FindNode(Pasted.Keys[1]).DisplayName);
  AssertEquals('B2 is placed from A2', Pasted.Keys[0], TOffsetPoint(FPattern.FindNode(Pasted.Keys[1])).Base);
  Copy := FPattern.FindNode(Pasted.Keys[2]) as TEdgeObject;
  AssertEquals('the line joins the copies', Pasted.Keys[0], Copy.StartKey);
  AssertEquals('Line_A2_B2', Copy.Name);
  AssertEquals('renames reported', 2, Length(Pasted.Renamed));
  AssertEquals('A → A2', Pasted.Renamed[0]);
end;

procedure TTestFragment.TestOtherPatternTakesWhatItNeeds;
var
  A, B, Line: string;
  Pasted: TFragmentPaste;
  Copy: TEdgeObject;
  Ease: TVariable;
begin
  FPattern.AddVariable('ease', '10');
  A := Pt(FPattern, 'A', 5, 5);
  B := FPattern.AddOffsetPoint('B', A, omCartesian, '#ease * 2', '0').Key;
  Line := FPattern.AddLine(A, B, erStitch).Key;
  FPattern.Evaluate;
  Pt(FOther, 'A', 1000, 1000);
  FOther.Evaluate;
  Pasted := Paste(FOther, CopyFragment(FPattern, [Line]).Text);
  Copy := FOther.FindNode(Pasted.Keys[0]) as TEdgeObject;
  AssertEquals('the taken name moves on', 'A2', FOther.FindNode(Copy.StartKey).DisplayName);
  AssertEquals('B', FOther.FindNode(Copy.EndKey).DisplayName);
  Ease := FOther.FindVariable('ease');
  AssertNotNull('the variable comes too', Ease);
  AssertEquals('#ease * 2', FOther.FormulaText(FOther.FindNode(Copy.EndKey), 'dx'));
  AssertPointsNear('placed as before', Vec2(25, 5), TPointObject(FOther.FindNode(Copy.EndKey)).Position);
  AssertEquals('Line_A2_B', Copy.Name);
  AssertEquals(Ord(esValid), Ord(Copy.State));
end;

procedure TTestFragment.TestOtherPatternUsesSameVariable;
var
  A, B: string;
  Count: integer;
begin
  FPattern.AddVariable('ease', '10');
  A := Pt(FPattern, 'A', 0, 0);
  B := FPattern.AddOffsetPoint('B', A, omCartesian, '#ease', '0').Key;
  FPattern.Evaluate;
  FOther.AddVariable('ease', '10');
  Count := FOther.VariableCount;
  Paste(FOther, CopyFragment(FPattern, [B]).Text);
  AssertEquals('no new variable', Count, FOther.VariableCount);
  AssertEquals('#ease', FOther.FormulaText(FOther.FindObject('B'), 'dx'));
end;

procedure TTestFragment.TestOtherPatternRenamesVariable;
var
  A, B: string;
begin
  FPattern.AddVariable('ease', '10');
  A := Pt(FPattern, 'A', 0, 0);
  B := FPattern.AddOffsetPoint('B', A, omCartesian, '#ease', '0').Key;
  FPattern.Evaluate;
  FOther.AddVariable('ease', '25');
  Paste(FOther, CopyFragment(FPattern, [B]).Text);
  AssertEquals('a different ease is kept apart', '#ease2', FOther.FormulaText(FOther.FindObject('B'), 'dx'));
  AssertNear('and keeps its value', 10, TPointObject(FOther.FindObject('B')).Position.X, 0.001);
end;

procedure TTestFragment.TestTransformLeftOut;
var
  A: string;
  Spec: TTransformSpec;
  Transform: TTransformObject;
  Copied: TFragmentCopy;
begin
  A := Pt(FPattern, 'A', 10, 0);
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Name := 'Shift';
  Spec.Sources := [A];
  Spec.DX := '5';
  Spec.DY := '0';
  Transform := FPattern.AddTransform(Spec);
  AssertNotNull(FPattern.LastError, Transform);
  FPattern.Evaluate;
  Copied := CopyFragment(FPattern, [Transform.Key]);
  AssertEquals('nothing to copy', '', Copied.Text);
  AssertEquals(1, Length(Copied.LeftOut));
  AssertEquals('Shift', Copied.LeftOut[0]);
end;

procedure TTestFragment.TestTransformCopyAsPlainEdge;
var
  A, B, Line, CopiedLine: string;
  Spec: TTransformSpec;
  Transform: TTransformObject;
  Pasted: TFragmentPaste;
  Index: integer;
  Plain: TEdgeObject;
begin
  A := Pt(FPattern, 'A', 0, 0);
  B := Pt(FPattern, 'B', 100, 0);
  Line := FPattern.AddLine(A, B, erOutline).Key;
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Line];
  Spec.DX := '0';
  Spec.DY := '50';
  Transform := FPattern.AddTransform(Spec);
  AssertNotNull(FPattern.LastError, Transform);
  FPattern.Evaluate;
  CopiedLine := '';
  for Index := 0 to FPattern.ObjectCount - 1 do
    if (FPattern.Objects[Index] is TEdgeCopy) then
      CopiedLine := FPattern.Objects[Index].Key;
  Pasted := Paste(FPattern, CopyFragment(FPattern, [CopiedLine]).Text);
  Plain := FPattern.FindNode(Pasted.Keys[0]) as TEdgeObject;
  AssertTrue('a plain line', Plain is TLineObject);
  AssertEquals('on the copied points', TEdgeObject(FPattern.FindNode(CopiedLine)).StartKey, Plain.StartKey);
  AssertNear('in the same place', 50, Plain.PointAtLength(10).Y, 0.001);

  // In another pattern its points come as free points where they were
  Pasted := Paste(FOther, CopyFragment(FPattern, [CopiedLine]).Text);
  Plain := FOther.FindNode(Pasted.Keys[0]) as TEdgeObject;
  AssertTrue('a free point', FOther.FindNode(Plain.EndKey) is TFreePoint);
  AssertPointsNear('where the copy was', Vec2(100, 50), TPointObject(FOther.FindNode(Plain.EndKey)).Position);
end;

procedure TTestFragment.TestOtherUnitsRefused;
var
  Text, Reason: string;
  Pasted: TFragmentPaste;
begin
  Text := CopyFragment(FPattern, [Pt(FPattern, 'A', 0, 0)]).Text;
  FOther.Units := muCentimetre;
  AssertFalse(PasteFragment(FOther, Text, Pasted, Reason));
  AssertEquals(Format(rsFragmentUnits, ['mm', 'cm']), Reason);
  AssertEquals('nothing added', 0, FOther.ObjectCount);
end;

procedure TTestFragment.TestNotAFragment;
var
  Reason: string;
  Pasted: TFragmentPaste;
begin
  AssertFalse(IsFragmentText('Line_A_B'));
  AssertFalse(PasteFragment(FPattern, '{"format": "pattern", "version": 1}', Pasted, Reason));
  AssertEquals(rsFragmentNotFragment, Reason);
  AssertTrue(IsFragmentText(CopyFragment(FPattern, [Pt(FPattern, 'A', 0, 0)]).Text));
end;

procedure TTestFragment.TestPastedStitchLineJoinsPiece;
var
  A, B, C, D, Stitch: string;
  Piece: TPieceObject;
  Path: TPiecePath;
  Pasted: TFragmentPaste;
  Edges: array[0..3] of string;
  Index: integer;
begin
  A := Pt(FPattern, 'A', 0, 0);
  B := Pt(FPattern, 'B', 100, 0);
  C := Pt(FPattern, 'C', 100, 100);
  D := Pt(FPattern, 'D', 0, 100);
  Edges[0] := FPattern.AddLine(A, B, erOutline).Key;
  Edges[1] := FPattern.AddLine(B, C, erOutline).Key;
  Edges[2] := FPattern.AddLine(C, D, erOutline).Key;
  Edges[3] := FPattern.AddLine(D, A, erOutline).Key;
  Path := nil;
  SetLength(Path, 4);
  for Index := 0 to 3 do
    Path[Index].EdgeKey := Edges[Index];
  Piece := FPattern.AddPiece('Front', Path, '10');
  AssertNotNull(FPattern.LastError, Piece);
  Stitch := FPattern.AddLine(Pt(FPattern, 'E', 20, 20), Pt(FPattern, 'F', 80, 20), erStitch).Key;
  FPattern.Evaluate;
  Pasted := Paste(FPattern, CopyFragment(FPattern, [Stitch]).Text);
  FPattern.Evaluate;
  AssertEquals('the copy is a marking of the piece', 1, Length(FPattern.PiecesWithMarking(Pasted.Keys[0])));
end;

procedure TTestFragment.TestSurvivesSaveAndLoad;
var
  Line, Text, Reason: string;
  Loaded: TPattern;
begin
  Line := FPattern.AddLine(Pt(FPattern, 'A', 0, 0), Pt(FPattern, 'B', 10, 0)).Key;
  FPattern.Evaluate;
  Paste(FPattern, CopyFragment(FPattern, [Line]).Text);
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(Reason, LoadPatternFromText(Loaded, Text, Reason));
    AssertEquals('the identity is kept', FPattern.Identity, Loaded.Identity);
    AssertNotNull(Loaded.FindObject('Line_A_B2'));
    AssertEquals('the counter is above every ID', FPattern.NextId, Loaded.NextId);
  finally
    FreeAndNil(Loaded);
  end;
end;

initialization
  RegisterTest(TTestFragment);
end.
