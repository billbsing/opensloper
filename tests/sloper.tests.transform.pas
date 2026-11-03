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

// Transforms: rotate, mirror and move, copies of points and edges, deleting as a
// group, and files.
unit Sloper.Tests.Transform;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern,
  Sloper.Core.Draft, Sloper.Core.Transform, Sloper.Core.EvalTypes;

type
  TTestTransform = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X, Y: double): TFreePoint;
    function Rotate(const Sources: TStringArray; const Pivot, Angle: string): TTransformObject;
    function Copied(const AName: string): TVec2;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAffineReflectAcrossDiagonal;
    procedure TestAffineThenRunsBeforeFirst;
    procedure TestRotatePoint;
    procedure TestRotateFollowsFormula;
    procedure TestRotateFollowsSource;
    procedure TestMirrorTwoPoints;
    procedure TestMirrorStraightEdge;
    procedure TestMirrorPointAndAngle;
    procedure TestMirrorRefusesCurve;
    procedure TestMirrorSamePlaceInvalid;
    procedure TestMoveCartesian;
    procedure TestMovePolar;
    procedure TestMoveAndTurn;
    procedure TestEdgeBringsItsEnds;
    procedure TestCopiedEdgeJoinsCopiedPoints;
    procedure TestCurveCopiedExactly;
    procedure TestSplitPartCopied;
    procedure TestRepeatPointCopied;
    procedure TestRotateKeepsLengths;
    procedure TestCopyHasAngleWhenStraight;
    procedure TestCopyKeepsRole;
    procedure TestCopyCanBeInput;
    procedure TestNames;
    procedure TestSuffixesCountUp;
    procedure TestRefusesNothing;
    procedure TestRefusesPiece;
    procedure TestFailingSourceBlocksOnlyItsCopy;
    procedure TestSourceInUseCannotBeDeleted;
    procedure TestCopyCannotBeDeletedAlone;
    procedure TestDeletingTransformTakesCopies;
    procedure TestDeletingTransformInUseRefused;
    procedure TestCopyCannotBeDragged;
    procedure TestCopyCannotBeConverted;
    procedure TestRoundTrip;
    procedure TestRoundTripKeepsPosition;
    procedure TestRoundTripMirrorAndMove;
    procedure TestPieceFromOriginalAndCopy;
  end;

implementation

uses
  Math, Sloper.Core.PatternFile, Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Drag, Sloper.Core.Variables;

procedure TTestTransform.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestTransform.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

function TTestTransform.Pt(const AName: string; X, Y: double): TFreePoint;
var
  Fixed: TFormatSettings;
begin
  Fixed := DefaultFormatSettings;
  Fixed.DecimalSeparator := '.';
  Result := FPattern.AddFreePoint(AName, FloatToStr(X, Fixed), FloatToStr(Y, Fixed));
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestTransform.Rotate(const Sources: TStringArray; const Pivot, Angle: string): TTransformObject;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkRotate;
  Spec.Sources := Sources;
  Spec.Pivot := Pivot;
  Spec.Angle := Angle;
  Result := FPattern.AddTransform(Spec);
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestTransform.Copied(const AName: string): TVec2;
var
  Node: TDraftObject;
begin
  Node := FPattern.FindObject(AName);
  AssertNotNull('no ' + AName, Node);
  Result := TPointObject(Node).Position;
end;

procedure TTestTransform.TestAffineReflectAcrossDiagonal;
begin
  AssertPointsNear('swapped', Vec2(3, 2), AffineReflect(Vec2(0, 0), Vec2(1, 1)).Apply(Vec2(2, 3)));
end;

procedure TTestTransform.TestAffineThenRunsBeforeFirst;
begin
  AssertPointsNear('turn, then shift', Vec2(10, 1), AffineThen(AffineShift(Vec2(10, 0)), AffineTurn(90)).Apply(Vec2(1, 0)));
end;

procedure TTestTransform.TestRotatePoint;
var
  A, Pivot: TFreePoint;
begin
  A := Pt('A', 10, 0);
  Pivot := Pt('P', 0, 0);
  Rotate([A.Key], Pivot.Key, '90');
  FPattern.Evaluate;
  AssertPointsNear('a quarter anticlockwise', Vec2(0, 10), Copied('A_r1'));
end;

procedure TTestTransform.TestRotateFollowsFormula;
var
  A, Pivot: TFreePoint;
  Transform: TTransformObject;
begin
  A := Pt('A', 10, 0);
  Pivot := Pt('P', 0, 0);
  Transform := Rotate([A.Key], Pivot.Key, '0');
  FPattern.Evaluate;
  AssertPointsNear('on top to begin with', Vec2(10, 0), Copied('A_r1'));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Transform, FieldAngle, '180'));
  FPattern.Evaluate;
  AssertPointsNear('follows', Vec2(-10, 0), Copied('A_r1'));
end;

procedure TTestTransform.TestRotateFollowsSource;
var
  A, Pivot: TFreePoint;
begin
  A := Pt('A', 10, 0);
  Pivot := Pt('P', 0, 0);
  Rotate([A.Key], Pivot.Key, '90');
  AssertTrue(FPattern.LastError, FPattern.SetFormula(A, 'x', '20'));
  FPattern.Evaluate;
  AssertPointsNear('moved with it', Vec2(0, 20), Copied('A_r1'));
end;

procedure TTestTransform.TestMirrorTwoPoints;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [Pt('A', 10, 5).Key];
  Spec.AxisA := Pt('P', 0, 0).Key;
  Spec.AxisB := Pt('Q', 0, 100).Key;
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('across', Vec2(-10, 5), Copied('A_m1'));
end;

procedure TTestTransform.TestMirrorStraightEdge;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [Pt('A', 10, 5).Key];
  Spec.AxisEdge := FPattern.AddLine(Pt('P', -50, 0).Key, Pt('Q', 50, 0).Key).Key;
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('across', Vec2(10, -5), Copied('A_m1'));
end;

procedure TTestTransform.TestMirrorPointAndAngle;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [Pt('A', 2, 3).Key];
  Spec.AxisA := Pt('P', 0, 0).Key;
  Spec.Angle := '45';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('across the diagonal', Vec2(3, 2), Copied('A_m1'));
end;

procedure TTestTransform.TestMirrorRefusesCurve;
var
  Spec: TTransformSpec;
  Curve: TCurveObject;
begin
  Curve := FPattern.AddCurve(Pt('P', 0, 0).Key, Pt('Q', 100, 0).Key, '45', '30', '135', '30');
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [Pt('A', 2, 3).Key];
  Spec.AxisEdge := Curve.Key;
  AssertNull('refused', FPattern.AddTransform(Spec));
  AssertEquals(Format(rsTransformCurvedAxis, [Curve.DisplayName]), FPattern.LastError);
end;

procedure TTestTransform.TestMirrorSamePlaceInvalid;
var
  Spec: TTransformSpec;
  Transform: TTransformObject;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [Pt('A', 2, 3).Key];
  Spec.AxisA := Pt('P', 0, 0).Key;
  Spec.AxisB := Pt('Q', 0, 0).Key;
  Transform := FPattern.AddTransform(Spec);
  FPattern.Evaluate;
  AssertTrue('invalid', Transform.State = esInvalid);
  AssertEquals(rsTransformNoAxis, Transform.Message);
  AssertTrue('its copy waits', FPattern.FindObject('A_m1').State = esBlocked);
end;

procedure TTestTransform.TestMoveCartesian;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Pt('A', 2, 3).Key];
  Spec.DX := '100';
  Spec.DY := '-50';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('moved', Vec2(102, -47), Copied('A_t1'));
end;

procedure TTestTransform.TestMovePolar;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Polar := True;
  Spec.Sources := [Pt('A', 0, 0).Key];
  Spec.Length := '10';
  Spec.Angle := '90';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('moved', Vec2(0, 10), Copied('A_t1'));
end;

// Turned about the pivot, then moved
procedure TTestTransform.TestMoveAndTurn;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Pt('A', 10, 0).Key];
  Spec.DX := '100';
  Spec.DY := '0';
  Spec.Pivot := Pt('P', 0, 0).Key;
  Spec.Rotate := '90';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  FPattern.Evaluate;
  AssertPointsNear('turned and moved', Vec2(100, 10), Copied('A_t1'));
end;

procedure TTestTransform.TestEdgeBringsItsEnds;
var
  Line: TLineObject;
  Pivot: TFreePoint;
begin
  Line := FPattern.AddLine(Pt('A', 10, 0).Key, Pt('B', 20, 0).Key);
  Pivot := Pt('P', 0, 0);
  Rotate([Line.Key], Pivot.Key, '90');
  FPattern.Evaluate;
  AssertPointsNear('start', Vec2(0, 10), Copied('A_r1'));
  AssertPointsNear('end', Vec2(0, 20), Copied('B_r1'));
end;

procedure TTestTransform.TestCopiedEdgeJoinsCopiedPoints;
var
  Line: TLineObject;
  Copy: TEdgeObject;
begin
  Line := FPattern.AddLine(Pt('A', 10, 0).Key, Pt('B', 20, 0).Key);
  Rotate([Line.Key], Pt('P', 0, 0).Key, '90');
  Copy := TEdgeObject(FPattern.FindObject(Line.Name + '_r1'));
  AssertEquals('start', FPattern.FindObject('A_r1').Key, Copy.StartKey);
  AssertEquals('end', FPattern.FindObject('B_r1').Key, Copy.EndKey);
end;

// The copy's middle and handles land exactly, not on a flattened line
procedure TTestTransform.TestCurveCopiedExactly;
var
  Curve: TCurveObject;
  Copy: TEdgeObject;
begin
  Curve := FPattern.AddCurve(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key, '45', '40', '135', '40');
  Rotate([Curve.Key], Pt('P', 0, 0).Key, '90');
  FPattern.Evaluate;
  Copy := TEdgeObject(FPattern.FindObject(Curve.Name + '_r1'));
  AssertEquals('still a curve', Ord(skCurve), Ord(Copy.Segments[0].Kind));
  AssertPointsNear('middle', RotatePoint(Curve.PointAtLength(Curve.Length / 2), Vec2(0, 0), 90), Copy.PointAtLength(Copy.Length / 2));
  AssertPointsNear('handle', RotatePoint(Curve.Segments[0].Curve.P1, Vec2(0, 0), 90), Copy.Segments[0].Curve.P1);
end;

procedure TTestTransform.TestSplitPartCopied;
var
  Line: TLineObject;
  First, Second: TSplitPart;
  M: TAlongEdgePoint;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  M := FPattern.AddAlongEdgePoint('M', Line.Key, False, amLength, '30');
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Line.Key, M.Key, First, Second));
  Rotate([First.Key], Pt('P', 0, 0).Key, '90');
  FPattern.Evaluate;
  AssertNear('the part''s length', 30, TEdgeObject(FPattern.FindObject(First.Name + '_r1')).Length);
end;

procedure TTestTransform.TestRepeatPointCopied;
var
  ARepeat: TRepeatObject;
begin
  ARepeat := FPattern.AddRepeatBetween('Btn', Pt('A', 0, 0).Key, Pt('B', 100, 0).Key, '3', True);
  FPattern.Evaluate;
  Rotate([ARepeat.Item(2).Key], Pt('P', 0, 0).Key, '90');
  FPattern.Evaluate;
  AssertPointsNear('the middle one', Vec2(0, 50), Copied('Btn_2_r1'));
end;

procedure TTestTransform.TestRotateKeepsLengths;
var
  Curve: TCurveObject;
begin
  Curve := FPattern.AddCurve(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key, '45', '40', '135', '40');
  Rotate([Curve.Key], Pt('P', 33, 12).Key, '37');
  FPattern.Evaluate;
  AssertNear('length', Curve.Length, TEdgeObject(FPattern.FindObject(Curve.Name + '_r1')).Length);
end;

procedure TTestTransform.TestCopyHasAngleWhenStraight;
var
  Line: TLineObject;
  Copy: TEdgeObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Rotate([Line.Key], Pt('P', 0, 0).Key, '30');
  FPattern.Evaluate;
  Copy := TEdgeObject(FPattern.FindObject(Line.Name + '_r1'));
  AssertTrue('straight', IsStraightEdge(Copy));
  AssertTrue('has it', Copy.HasProperty('angle'));
  AssertNear('angle', 30, Copy.PropertyValue('angle'));
end;

procedure TTestTransform.TestCopyKeepsRole;
var
  Line: TLineObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key, erOutline);
  Rotate([Line.Key], Pt('P', 0, 0).Key, '30');
  AssertTrue('outline', TEdgeObject(FPattern.FindObject(Line.Name + '_r1')).Role = erOutline);
end;

procedure TTestTransform.TestCopyCanBeInput;
var
  A: TFreePoint;
  Next: TOffsetPoint;
begin
  A := Pt('A', 10, 0);
  Rotate([A.Key], Pt('P', 0, 0).Key, '90');
  Next := FPattern.AddOffsetPoint('N', FPattern.FindObject('A_r1').Key, omCartesian, '5', '0');
  AssertNotNull(FPattern.LastError, Next);
  FPattern.Evaluate;
  AssertPointsNear('from the copy', Vec2(5, 10), Next.Position);
end;

procedure TTestTransform.TestNames;
var
  Transform: TTransformObject;
begin
  Transform := Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertEquals('Rotate', Transform.Name);
  AssertEquals('_r1', Transform.Suffix);
  AssertNotNull('copy', FPattern.FindObject('A_r1'));
end;

procedure TTestTransform.TestSuffixesCountUp;
var
  A, Pivot: TFreePoint;
begin
  A := Pt('A', 10, 0);
  Pivot := Pt('P', 0, 0);
  Rotate([A.Key], Pivot.Key, '90');
  AssertEquals('_r2', Rotate([A.Key], Pivot.Key, '45').Suffix);
  AssertNotNull('copy', FPattern.FindObject('A_r2'));
end;

procedure TTestTransform.TestRefusesNothing;
var
  Spec: TTransformSpec;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  AssertNull('refused', FPattern.AddTransform(Spec));
  AssertEquals(rsPatternTransformNothing, FPattern.LastError);
end;

procedure TTestTransform.TestRefusesPiece;
var
  Spec: TTransformSpec;
  A, B, C, D, Reason: string;
  Path: TPiecePath;
  Piece: TPieceObject;
begin
  A := Pt('', 0, 0).Key;
  B := Pt('', 100, 0).Key;
  C := Pt('', 100, 100).Key;
  D := Pt('', 0, 100).Key;
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  Piece := FPattern.AddPiece('Front', Path, '10');
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Piece.Key];
  AssertNull('refused', FPattern.AddTransform(Spec));
  AssertEquals(Format(rsPatternTransformNotCopyable, ['Front']), FPattern.LastError);
end;

procedure TTestTransform.TestFailingSourceBlocksOnlyItsCopy;
var
  A, B: TFreePoint;
  Transform: TTransformObject;
begin
  A := Pt('A', 10, 0);
  B := Pt('B', 20, 0);
  Transform := Rotate([A.Key, B.Key], Pt('P', 0, 0).Key, '90');
  AssertTrue(FPattern.LastError, FPattern.SetFormula(A, 'x', '1 / 0'));
  FPattern.Evaluate;
  AssertTrue('its copy', FPattern.FindObject('A_r1').State = esBlocked);
  AssertTrue('the other', FPattern.FindObject('B_r1').State = esValid);
  AssertTrue('the transform', Transform.State = esValid);
end;

procedure TTestTransform.TestSourceInUseCannotBeDeleted;
var
  A: TFreePoint;
begin
  A := Pt('A', 10, 0);
  Rotate([A.Key], Pt('P', 0, 0).Key, '90');
  AssertFalse('refused', FPattern.Delete(A));
end;

procedure TTestTransform.TestCopyCannotBeDeletedAlone;
var
  Transform: TTransformObject;
begin
  Transform := Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertFalse('refused', FPattern.Delete(FPattern.FindObject('A_r1')));
  AssertEquals(Format(rsPatternCopyOfTransform, ['A_r1', Transform.Name]), FPattern.LastError);
end;

procedure TTestTransform.TestDeletingTransformTakesCopies;
var
  Line: TLineObject;
  Transform: TTransformObject;
  Before: integer;
  A: TDraftObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Before := FPattern.ObjectCount;
  Transform := Rotate([Line.Key], Line.StartKey, '90');
  AssertTrue(FPattern.LastError, FPattern.Delete(Transform));
  AssertEquals('all gone', Before, FPattern.ObjectCount);
  A := FPattern.FindObject('A');
  AssertTrue('the source is free again', FPattern.Delete(Line) and FPattern.Delete(A));
end;

procedure TTestTransform.TestDeletingTransformInUseRefused;
var
  Transform: TTransformObject;
begin
  Transform := Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertNotNull(FPattern.LastError, FPattern.AddOffsetPoint('N', FPattern.FindObject('A_r1').Key, omCartesian, '5', '0'));
  AssertFalse('N uses the copy', FPattern.Delete(Transform));
  AssertNotNull('copy stays', FPattern.FindObject('A_r1'));
end;

procedure TTestTransform.TestCopyCannotBeDragged;
var
  Reason: string;
begin
  Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertFalse('refused', CanDrag(TPointObject(FPattern.FindObject('A_r1')), Reason));
end;

procedure TTestTransform.TestCopyCannotBeConverted;
begin
  Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertNull('refused', FPattern.ConvertToFree(TPointObject(FPattern.FindObject('A_r1')), '0', '0'));
end;

procedure TTestTransform.TestRoundTrip;
var
  Err, Saved: string;
  Line: TLineObject;
begin
  Line := FPattern.AddLine(Pt('A', 10, 0).Key, Pt('B', 20, 0).Key, erOutline);
  Rotate([Line.Key], Pt('P', 0, 0).Key, '90');
  Saved := SavePatternToText(FPattern);
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  AssertEquals(Saved, SavePatternToText(FLoaded));
end;

procedure TTestTransform.TestRoundTripKeepsPosition;
var
  Err: string;
begin
  Rotate([Pt('A', 10, 0).Key], Pt('P', 0, 0).Key, '90');
  AssertTrue(Err, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Err));
  FLoaded.Evaluate;
  AssertPointsNear('computed again', Vec2(0, 10), TPointObject(FLoaded.FindObject('A_r1')).Position);
end;

procedure TTestTransform.TestRoundTripMirrorAndMove;
var
  Err, Saved: string;
  Spec: TTransformSpec;
  A: TFreePoint;
begin
  A := Pt('A', 2, 3);
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [A.Key];
  Spec.AxisA := Pt('P', 0, 0).Key;
  Spec.Angle := '45';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMirror;
  Spec.Sources := [A.Key];
  Spec.AxisEdge := FPattern.AddLine(Pt('Q', 0, 0).Key, Pt('R', 9, 0).Key).Key;
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Polar := True;
  Spec.Sources := [A.Key];
  Spec.Length := '5';
  Spec.Angle := '10';
  Spec.Pivot := FPattern.FindObject('P').Key;
  Spec.Rotate := '30';
  AssertNotNull(FPattern.LastError, FPattern.AddTransform(Spec));
  Saved := SavePatternToText(FPattern);
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  AssertEquals(Saved, SavePatternToText(FLoaded));
end;

// The dart example: a piece from an original edge and a copied one
procedure TTestTransform.TestPieceFromOriginalAndCopy;
var
  A, B, C: string;
  Bottom, Side: TLineObject;
  Transform: TTransformObject;
  Top: TEdgeObject;
  Path: TPiecePath;
  Reason: string;
begin
  A := Pt('A', 0, 0).Key;
  B := Pt('B', 100, 0).Key;
  C := Pt('C', 100, 100).Key;
  Bottom := FPattern.AddLine(A, B, erOutline);
  Side := FPattern.AddLine(B, C, erOutline);
  Transform := Rotate([Bottom.Key], A, '90');
  FPattern.Evaluate;
  Top := FPattern.AddLine(C, FPattern.FindObject('B_r1').Key, erOutline);
  AssertNotNull(FPattern.LastError, Top);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  AssertEquals('all four edges', 4, Length(Path));
  AssertNotNull('used by a piece', Transform);
  AssertTrue('the side stays', Side.State = esValid);
end;

initialization
  RegisterTest(TTestTransform);

end.
