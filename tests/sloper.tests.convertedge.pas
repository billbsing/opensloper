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

// Changing an edge between a line and a curve in place, and an arc to a line:
// whatever used the edge goes on using it.
unit Sloper.Tests.ConvertEdge;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestConvertEdge = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCurveToLineKeepsIdAndUsers;
    procedure TestDerivedNameFollowsType;
    procedure TestUserNameIsKept;
    procedure TestRoleIsKept;
    procedure TestLineToCurveStartsStraight;
    procedure TestLineToCurveRefusedWhileAngleIsRead;
    procedure TestPieceKeepsItsEdge;
    procedure TestArcToLineEndsFollowTheArc;
    procedure TestCircleRefused;
    procedure TestArcToCurveRefused;
    procedure TestAlreadyThatTypeRefused;
    procedure TestTransformCopyRefused;
  end;

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Transform, Sloper.Core.Variables;

procedure TTestConvertEdge.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestConvertEdge.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestConvertEdge.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

procedure TTestConvertEdge.TestCurveToLineKeepsIdAndUsers;
var
  Curve: TCurveObject;
  Line: TLineObject;
  Reader: TOffsetPoint;
  Key: string;
begin
  Curve := FPattern.AddCurve(Pt('A', 0, 0), Pt('B', 100, 0), '90', '40', '90', '40');
  Key := Curve.Key;
  Reader := FPattern.AddOffsetPoint('R', Pt('O', 0, -50), omCartesian, Curve.Name + '.length', '0');
  AssertNotNull(FPattern.LastError, Reader);
  Line := FPattern.ConvertToLine(Curve);
  AssertNotNull(FPattern.LastError, Line);
  AssertEquals('same ID', Key, Line.Key);
  AssertTrue('the line is found by the old ID', FPattern.FindNode(Line.Key) = Line);
  FPattern.Evaluate;
  AssertTrue('the reader is fine', Reader.State = esValid);
  AssertNear('and reads the line', 100, Reader.Position.X);
end;

procedure TTestConvertEdge.TestDerivedNameFollowsType;
var
  Key: string;
begin
  Key := FPattern.AddCurve(Pt('A', 0, 0), Pt('B', 100, 0), '90', '40', '90', '40').Key;
  AssertEquals('Line_A_B', FPattern.ConvertToLine(TEdgeObject(FPattern.FindNode(Key))).Name);
  AssertEquals('kept its ID', Key, FPattern.FindObject('Line_A_B').Key);
  AssertEquals('and back', 'Curve_A_B', FPattern.ConvertToCurve(TEdgeObject(FPattern.FindNode(Key))).Name);
end;

procedure TTestConvertEdge.TestUserNameIsKept;
var
  Curve: TCurveObject;
begin
  Curve := FPattern.AddCurve(Pt('A', 0, 0), Pt('B', 100, 0), '90', '40', '90', '40');
  AssertTrue(FPattern.LastError, FPattern.Rename(Curve, 'Hem'));
  AssertEquals('Hem', FPattern.ConvertToLine(Curve).Name);
end;

procedure TTestConvertEdge.TestRoleIsKept;
begin
  AssertTrue('outline', FPattern.ConvertToCurve(FPattern.AddLine(Pt('A', 0, 0), Pt('B', 100, 0), erOutline)).Role = erOutline);
end;

procedure TTestConvertEdge.TestLineToCurveStartsStraight;
var
  Curve: TCurveObject;
begin
  Curve := FPattern.ConvertToCurve(FPattern.AddLine(Pt('A', 0, 0), Pt('B', 90, 0)));
  AssertNotNull(FPattern.LastError, Curve);
  FPattern.Evaluate;
  AssertTrue('valid', Curve.State = esValid);
  AssertNear('as long as the line', 90, Curve.Length);
  AssertPointsNear('straight', Vec2(45, 0), Curve.PointAtLength(45));
  AssertEquals('handles a third along', '30', FPattern.FormulaText(Curve, 'length1'));
end;

// Only a line has .angle, so a formula reading it would break
procedure TTestConvertEdge.TestLineToCurveRefusedWhileAngleIsRead;
var
  Line: TLineObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0), Pt('B', 100, 0));
  AssertNotNull(FPattern.LastError, FPattern.AddOffsetPoint('R', Pt('O', 0, -50), omPolar, '10', Line.Name + '.angle + 90'));
  AssertNull('refused', FPattern.ConvertToCurve(Line));
  AssertTrue(FPattern.LastError, Pos('R', FPattern.LastError) > 0);
  AssertTrue('still a line', FPattern.FindNode(Line.Key) is TLineObject);
end;

procedure TTestConvertEdge.TestPieceKeepsItsEdge;
var
  A, B, C, D, Err: string;
  Path: TPiecePath;
  Piece: TPieceObject;
  TopKey: string;
begin
  A := Pt('A', 0, 0);
  B := Pt('B', 100, 0);
  C := Pt('C', 100, 100);
  D := Pt('D', 0, 100);
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  TopKey := FPattern.AddLine(C, D, erOutline).Key;
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Err, DetectPiecePath(FPattern, Vec2(50, 50), Path, Err));
  Piece := FPattern.AddPiece('Front', Path, '10');
  // The line object is replaced, so it is found again by its ID
  AssertNotNull(FPattern.LastError, FPattern.ConvertToCurve(TEdgeObject(FPattern.FindNode(TopKey))));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindNode(TopKey), 'angle1', '120'));
  FPattern.Evaluate;
  AssertTrue('the piece still closes', Piece.State = esValid);
  AssertTrue('round the curve now', Piece.Perimeter > 400);
end;

procedure TTestConvertEdge.TestArcToLineEndsFollowTheArc;
var
  Arc: TArcObject;
  Line: TLineObject;
  Radius: TVariable;
  ArcKey: string;
begin
  Radius := FPattern.AddVariable('r', '50');
  Arc := FPattern.AddArc(Pt('O', 0, 0), '#r', '0', '90');
  AssertNotNull(FPattern.LastError, Arc);
  ArcKey := Arc.Key;
  Line := FPattern.ConvertToLine(Arc);
  AssertNotNull(FPattern.LastError, Line);
  AssertEquals('the arc''s ID', ArcKey, Line.Key);
  FPattern.Evaluate;
  AssertPointsNear('from the arc''s start', Vec2(50, 0), TPointObject(FPattern.FindNode(Line.StartKey)).Position);
  AssertPointsNear('to its end, up at 90 degrees', Vec2(0, -50), TPointObject(FPattern.FindNode(Line.EndKey)).Position);
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Radius, 'formula', '60'));
  FPattern.Evaluate;
  AssertPointsNear('the ends follow the radius', Vec2(60, 0), TPointObject(FPattern.FindNode(Line.StartKey)).Position);
end;

procedure TTestConvertEdge.TestCircleRefused;
begin
  AssertNull('no ends to join', FPattern.ConvertToLine(FPattern.AddCircle(Pt('O', 0, 0), '50')));
end;

procedure TTestConvertEdge.TestArcToCurveRefused;
begin
  AssertNull('only a line becomes a curve', FPattern.ConvertToCurve(FPattern.AddArc(Pt('O', 0, 0), '50', '0', '90')));
end;

procedure TTestConvertEdge.TestAlreadyThatTypeRefused;
begin
  AssertNull('a line', FPattern.ConvertToLine(FPattern.AddLine(Pt('A', 0, 0), Pt('B', 100, 0))));
  AssertNull('a curve', FPattern.ConvertToCurve(FPattern.AddCurve(Pt('C', 0, 10), Pt('D', 100, 10), '90', '40', '90', '40')));
end;

procedure TTestConvertEdge.TestTransformCopyRefused;
var
  Spec: TTransformSpec;
  Line: TLineObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0), Pt('B', 100, 0));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Line.Key];
  Spec.DX := '10';
  Spec.DY := '0';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  AssertNull('it follows its transform', FPattern.ConvertToCurve(TEdgeObject(FPattern.FindObject(Line.Name + '_t1'))));
end;

initialization
  RegisterTest(TTestConvertEdge);

end.
