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

// Merging points into one: the name it takes, which definition stays, and
// whatever used the others using it instead.
unit Sloper.Tests.MergePoints;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestMergePoints = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMergedName;
    procedure TestUsersMoveToKeptPoint;
    procedure TestUserNameIsKept;
    procedure TestKeptIsNotPlacedFromTheOthers;
    procedure TestLineBetweenIsDeleted;
    procedure TestUsedLineBetweenRefused;
    procedure TestPathThroughBothRefused;
    procedure TestPieceNotchFollows;
    procedure TestTooFewRefused;
    procedure TestEdgeRefused;
    procedure TestCopiedPointRefused;
    procedure TestCopyIsKept;
    procedure TestSavesAndLoads;
  end;

implementation

uses
  SysUtils, Sloper.Core.Names, Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Transform,
  Sloper.Core.PatternFile;

procedure TTestMergePoints.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestMergePoints.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestMergePoints.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

procedure TTestMergePoints.TestMergedName;
begin
  AssertEquals('lowest made name', 'M', MergedName(['M', 'N', 'O']));
  AssertEquals('the user''s name', 'MyNode', MergedName(['M', 'MyNode', 'O']));
  AssertEquals('the first of the user''s', 'Hip', MergedName(['Hip', 'Waist']));
  AssertEquals('Z comes before AA', 'Z', MergedName(['AA', 'Z']));
  AssertEquals('C comes before BB', 'C', MergedName(['BB', 'C']));
  AssertEquals('a copy after its source', 'M', MergedName(['M2', 'M']));
  AssertTrue('a copy is made', IsMadeName('M2'));
  AssertTrue('so is a broken point', IsMadeName('M1'));
  AssertFalse('lower case is the user''s', IsMadeName('m'));
  AssertFalse('so is an underscore', IsMadeName('BP_1'));
  AssertFalse('a number from 0 is not a copy', IsMadeName('M0'));
end;

procedure TTestMergePoints.TestUsersMoveToKeptPoint;
var
  M, N, Reader, Line: string;
  Kept: TPointObject;
begin
  M := Pt('M', 10, 10);
  N := Pt('N', 12, 10);
  Line := FPattern.AddLine(N, Pt('B', 100, 0)).Key;
  Reader := FPattern.AddOffsetPoint('R', N, omCartesian, 'N.x + 5', '0').Key;
  Kept := FPattern.MergePoints([M, N]);
  AssertNotNull(FPattern.LastError, Kept);
  AssertEquals('keeps M', M, Kept.Key);
  AssertEquals('M', Kept.Name);
  AssertNull('N is gone', FPattern.FindNode(N));
  AssertEquals('the line starts at M', M, TEdgeObject(FPattern.FindNode(Line)).StartKey);
  AssertEquals('its name follows', 'Line_M_B', FPattern.FindNode(Line).DisplayName);
  AssertEquals('the offset is from M', M, TOffsetPoint(FPattern.FindNode(Reader)).Base);
  AssertEquals('its formula reads M', 'M.x + 5', FPattern.FormulaText(FPattern.FindNode(Reader), 'dx'));
  FPattern.Evaluate;
  AssertPointsNear('placed from M', Vec2(25, 10), TPointObject(FPattern.FindNode(Reader)).Position);
end;

procedure TTestMergePoints.TestUserNameIsKept;
var
  M, MyNode, O: string;
  Kept: TPointObject;
begin
  M := Pt('M', 0, 0);
  MyNode := Pt('MyNode', 5, 5);
  O := Pt('O', 9, 9);
  Kept := FPattern.MergePoints([M, MyNode, O]);
  AssertNotNull(FPattern.LastError, Kept);
  AssertEquals('MyNode', Kept.Name);
  AssertEquals('its own definition', MyNode, Kept.Key);
  AssertNull(FPattern.FindNode(M));
  AssertNull(FPattern.FindNode(O));
  FPattern.Evaluate;
  AssertPointsNear('where it was', Vec2(5, 5), Kept.Position);
end;

// MyNode is placed from M, so keeping MyNode would make it read itself
procedure TTestMergePoints.TestKeptIsNotPlacedFromTheOthers;
var
  M, MyNode: string;
  Kept: TPointObject;
begin
  M := Pt('M', 3, 4);
  MyNode := FPattern.AddOffsetPoint('MyNode', M, omCartesian, '10', '0').Key;
  Kept := FPattern.MergePoints([M, MyNode]);
  AssertNotNull(FPattern.LastError, Kept);
  AssertEquals('M''s definition', M, Kept.Key);
  AssertEquals('the user''s name', 'MyNode', Kept.Name);
  AssertNull(FPattern.FindNode(MyNode));
  FPattern.Evaluate;
  AssertPointsNear('where M was', Vec2(3, 4), Kept.Position);
end;

procedure TTestMergePoints.TestLineBetweenIsDeleted;
var
  M, N, Between, Other: string;
begin
  M := Pt('M', 0, 0);
  N := Pt('N', 1, 0);
  Between := FPattern.AddLine(M, N).Key;
  Other := FPattern.AddLine(N, Pt('B', 50, 50)).Key;
  AssertNotNull(FPattern.LastError, FPattern.MergePoints([M, N]));
  AssertNull('the line between them is gone', FPattern.FindNode(Between));
  AssertNotNull('the other stays', FPattern.FindNode(Other));
end;

procedure TTestMergePoints.TestUsedLineBetweenRefused;
var
  M, N, Between: string;
begin
  M := Pt('M', 0, 0);
  N := Pt('N', 10, 0);
  Between := FPattern.AddLine(M, N).Key;
  AssertNotNull(FPattern.LastError, FPattern.AddAlongEdgePoint('Q', Between, False, amRatio, '0.5'));
  AssertNull('refused', FPattern.MergePoints([M, N]));
  AssertTrue(FPattern.LastError, Pos('Q', FPattern.LastError) > 0);
  AssertNotNull('nothing changed', FPattern.FindNode(N));
  AssertEquals(N, TEdgeObject(FPattern.FindNode(Between)).EndKey);
end;

procedure TTestMergePoints.TestPathThroughBothRefused;
var
  M, N: string;
begin
  M := Pt('M', 10, 0);
  N := Pt('N', 20, 0);
  AssertNotNull(FPattern.LastError, FPattern.AddCurvePath([Pt('A', 0, 0), M, N, Pt('B', 30, 0)], ['0', '0', '0', '0'],
    ['', '3', '3', '3'], ['3', '3', '3', '']));
  AssertNull('refused', FPattern.MergePoints([M, N]));
  AssertNotNull('nothing changed', FPattern.FindNode(N));
end;

procedure TTestMergePoints.TestPieceNotchFollows;
var
  A, B, C, D, N, Err: string;
  Path: TPiecePath;
  Piece: TPieceObject;
begin
  A := Pt('A', 0, 0);
  B := Pt('B', 100, 0);
  C := Pt('C', 100, 100);
  D := Pt('D', 0, 100);
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Err, DetectPiecePath(FPattern, Vec2(50, 50), Path, Err));
  Piece := FPattern.AddPiece('Front', Path, '10');
  N := Pt('N', 50, 0);
  AssertTrue(FPattern.LastError, FPattern.AddPointNotch(Piece, N));
  AssertNotNull(FPattern.LastError, FPattern.MergePoints([B, N]));
  AssertEquals('the notch is at B', B, TPieceObject(FPattern.FindObject('Front')).Notches[0].PointKey);
end;

procedure TTestMergePoints.TestTooFewRefused;
var
  M: string;
begin
  M := Pt('M', 0, 0);
  AssertNull('one point', FPattern.MergePoints([M]));
  AssertNull('the same point twice', FPattern.MergePoints([M, M]));
end;

procedure TTestMergePoints.TestEdgeRefused;
var
  M, N: string;
begin
  M := Pt('M', 0, 0);
  N := Pt('N', 10, 0);
  AssertNull('an edge', FPattern.MergePoints([M, FPattern.AddLine(N, Pt('B', 9, 9)).Key]));
  AssertNotNull(FPattern.FindNode(M));
end;

procedure TTestMergePoints.TestCopiedPointRefused;
var
  Spec: TTransformSpec;
  M, N: string;
begin
  M := Pt('M', 0, 0);
  N := Pt('N', 10, 0);
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [N];
  Spec.DX := '10';
  Spec.DY := '0';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  AssertNull('N has a copy', FPattern.MergePoints([M, N]));
  AssertNotNull(FPattern.FindNode(N));
end;

procedure TTestMergePoints.TestCopyIsKept;
var
  Spec: TTransformSpec;
  M, N: string;
  Copy: TDraftObject;
  Kept: TPointObject;
begin
  M := Pt('M', 0, 0);
  N := Pt('N', 10, 0);
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [N];
  Spec.DX := '10';
  Spec.DY := '0';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  Copy := FPattern.FindObject('N_t1');
  Kept := FPattern.MergePoints([M, Copy.Key]);
  AssertNotNull(FPattern.LastError, Kept);
  AssertEquals('the copy stays', Copy.Key, Kept.Key);
  AssertEquals('with its own name', 'N_t1', Kept.Name);
  AssertNull(FPattern.FindNode(M));
end;

// The kept point may come after its new users in the list; files list inputs first
procedure TTestMergePoints.TestSavesAndLoads;
var
  M, N, Err: string;
  Loaded: TPattern;
begin
  N := Pt('N', 10, 0);
  FPattern.AddLine(N, Pt('B', 50, 0));
  M := Pt('MyNode', 0, 0);
  AssertNotNull(FPattern.LastError, FPattern.MergePoints([M, N]));
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, SavePatternToText(FPattern), Err));
    AssertNotNull(Loaded.FindObject('Line_MyNode_B'));
  finally
    FreeAndNil(Loaded);
  end;
end;

initialization
  RegisterTest(TTestMergePoints);

end.
