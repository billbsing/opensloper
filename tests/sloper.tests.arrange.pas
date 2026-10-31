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

// Points between points, changing a point's operation, and align and distribute.
unit Sloper.Tests.Arrange;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Arrange, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestArrange = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Free(const AName: string; X, Y: double): TFreePoint;
    function Named(const AName: string): TPointObject;
    function Request(Action: TArrangeAction; const Points: array of TPointObject; const Reference: string = ''; const Edge: string = ''): TArrangeRequest;
    procedure Apply(const ARequest: TArrangeRequest; const Replace: TStringArray = nil);
    function Plan(const ARequest: TArrangeRequest): TArrangeItemArray;
    procedure AssertAt(const AName: string; X, Y: double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBetweenByRatio;
    procedure TestBetweenByLength;
    procedure TestBetweenFollowsItsPoints;
    procedure TestBetweenRatioRange;
    procedure TestBetweenPastTheEnd;
    procedure TestBetweenSamePlace;
    procedure TestBetweenNeedsPoints;
    procedure TestConvertKeepsIdAndName;
    procedure TestConvertKeepsUsers;
    procedure TestConvertRefusesACircle;
    procedure TestConvertRefusesAFormulaCircle;
    procedure TestConvertFailureLeavesPoint;
    procedure TestAlignVertical;
    procedure TestAlignHorizontal;
    procedure TestAlignHolds;
    procedure TestAlignCartesianOffset;
    procedure TestAlignNeedsAReference;
    procedure TestAlignNeedsAPoint;
    procedure TestAlignAsksBeforeFormula;
    procedure TestAlignAsksBeforeOperation;
    procedure TestAlignReplacesWhenTold;
    procedure TestAlignReplacingKeepsOtherCoordinate;
    procedure TestAlignSkipsWhatItIsUsedBy;
    procedure TestAlignAlreadyThere;
    procedure TestDistribute;
    procedure TestDistributeFindsOutermost;
    procedure TestDistributeHolds;
    procedure TestDistributeOnlyMovesInner;
    procedure TestDistributeNeedsThree;
    procedure TestDistributeAsksBeforeOperation;
    procedure TestDistributeAsksBeforeFormula;
    procedure TestDistributeHorizontal;
    procedure TestDistributeVertical;
    procedure TestDistributeAlongLine;
    procedure TestDistributeAlongCurve;
    procedure TestDistributeAlongEdgeLeavesEnds;
    procedure TestDistributeAlongNeedsAnEdge;
    procedure TestPlanChangesNothing;
    procedure TestBetweenRoundTrip;
    procedure TestConvertedPointUsingLaterPointsLoads;
    procedure TestAlignToALaterPointLoads;
    procedure TestOrderKeepsTheRest;
    procedure TestUndoAfterAConvertedPointMoved;
    procedure TestRenameAfterAlign;
    procedure TestDocumentUndoesItAsOneStep;
    procedure TestDocumentCancelsAFailure;
  end;

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Geometry, Sloper.Core.Evaluator, Sloper.Core.PatternFile, Sloper.Document.PatternDocument;

procedure TTestArrange.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestArrange.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestArrange.Free(const AName: string; X, Y: double): TFreePoint;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y));
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestArrange.Named(const AName: string): TPointObject;
begin
  Result := TPointObject(FPattern.FindObject(AName));
end;

function TTestArrange.Request(Action: TArrangeAction; const Points: array of TPointObject; const Reference, Edge: string): TArrangeRequest;
var
  Point: TPointObject;
begin
  Result := Default(TArrangeRequest);
  Result.Action := Action;
  Result.Reference := Reference;
  Result.Edge := Edge;
  for Point in Points do
    Insert(Point.Key, Result.Points, Length(Result.Points));
end;

procedure TTestArrange.Apply(const ARequest: TArrangeRequest; const Replace: TStringArray);
var
  Err: string;
begin
  FPattern.Evaluate;
  AssertTrue(Err, ApplyArrange(FPattern, ARequest, Replace, Err));
  FPattern.Evaluate;
end;

function TTestArrange.Plan(const ARequest: TArrangeRequest): TArrangeItemArray;
var
  Err: string;
begin
  FPattern.Evaluate;
  AssertTrue(Err, PlanArrange(FPattern, ARequest, Result, Err));
end;

procedure TTestArrange.AssertAt(const AName: string; X, Y: double);
begin
  AssertEquals(AName + ' is valid: ' + Named(AName).Message, True, Named(AName).State = esValid);
  AssertNear(AName + ' x', X, Named(AName).Position.X);
  AssertNear(AName + ' y', Y, Named(AName).Position.Y);
end;

procedure TTestArrange.TestBetweenByRatio;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 50);
  AssertNotNull(FPattern.AddBetweenPoint('C', A.Key, B.Key, amRatio, '0.25'));
  FPattern.Evaluate;
  AssertAt('C', 25, 12.5);
end;

procedure TTestArrange.TestBetweenByLength;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 30, 40);
  AssertNotNull(FPattern.AddBetweenPoint('C', A.Key, B.Key, amLength, '10'));
  FPattern.Evaluate;
  AssertAt('C', 6, 8);
end;

procedure TTestArrange.TestBetweenFollowsItsPoints;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  FPattern.AddBetweenPoint('C', A.Key, B.Key, amRatio, '0.5');
  AssertTrue(FPattern.SetFormula(B, 'x', '200'));
  FPattern.Evaluate;
  AssertAt('C', 100, 0);
end;

procedure TTestArrange.TestBetweenRatioRange;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  FPattern.AddBetweenPoint('C', A.Key, B.Key, amRatio, '1.5');
  FPattern.Evaluate;
  AssertTrue(Named('C').State = esInvalid);
end;

procedure TTestArrange.TestBetweenPastTheEnd;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  FPattern.AddBetweenPoint('C', A.Key, B.Key, amLength, '101');
  FPattern.Evaluate;
  AssertTrue(Named('C').State = esInvalid);
end;

procedure TTestArrange.TestBetweenSamePlace;
var
  A, B: TFreePoint;
begin
  A := Free('A', 5, 5);
  B := Free('B', 5, 5);
  FPattern.AddBetweenPoint('C', A.Key, B.Key, amLength, '1');
  FPattern.AddBetweenPoint('D', A.Key, B.Key, amRatio, '0.5');
  FPattern.Evaluate;
  AssertTrue('no direction to go in', Named('C').State = esInvalid);
  AssertAt('D', 5, 5);
end;

procedure TTestArrange.TestBetweenNeedsPoints;
var
  A, B: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  AssertNull(FPattern.AddBetweenPoint('C', A.Key, FPattern.AddLine(A.Key, B.Key).Key, amRatio, '0.5'));
end;

procedure TTestArrange.TestConvertKeepsIdAndName;
var
  A, B, C: TFreePoint;
  Key: string;
  Index: integer;
  Done: TBetweenPoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := Free('C', 10, 10);
  Key := C.Key;
  Index := FPattern.ObjectCount;
  Done := FPattern.ConvertToBetween(C, A.Key, B.Key, amRatio, '0.5');
  AssertNotNull(FPattern.LastError, Done);
  AssertEquals(Key, Done.Key);
  AssertEquals('C', Done.Name);
  AssertEquals(Index, FPattern.ObjectCount);
  AssertTrue('findable', FPattern.FindNode(Key) = Done);
  FPattern.Evaluate;
  AssertAt('C', 50, 0);
end;

procedure TTestArrange.TestConvertKeepsUsers;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := Free('C', 10, 10);
  FPattern.AddOffsetPoint('D', C.Key, omCartesian, '0', '5');
  FPattern.Evaluate;
  AssertNotNull(FPattern.ConvertToBetween(C, A.Key, B.Key, amRatio, '0.5'));
  FPattern.Evaluate;
  AssertAt('D', 50, 5);
end;

procedure TTestArrange.TestConvertRefusesACircle;
var
  A, B: TFreePoint;
  C: TOffsetPoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := FPattern.AddOffsetPoint('C', A.Key, omCartesian, '0', '5');
  AssertNull('C reads A', FPattern.ConvertToBetween(A, C.Key, B.Key, amRatio, '0.5'));
  AssertTrue(FPattern.LastError <> '');
  AssertNull('nor can it use itself', FPattern.ConvertToBetween(A, A.Key, B.Key, amRatio, '0.5'));
end;

procedure TTestArrange.TestConvertRefusesAFormulaCircle;
var
  A: TFreePoint;
  C: TOffsetPoint;
begin
  A := Free('A', 0, 0);
  C := FPattern.AddOffsetPoint('C', A.Key, omCartesian, '0', '5');
  AssertNull(FPattern.ConvertToFree(A, '{' + C.Key + '}.x', '0'));
end;

procedure TTestArrange.TestConvertFailureLeavesPoint;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := Free('C', 10, 10);
  AssertNull(FPattern.ConvertToBetween(C, A.Key, B.Key, amRatio, '1 +'));
  AssertTrue('still there', FPattern.FindNode(C.Key) = C);
  FPattern.Evaluate;
  AssertAt('C', 10, 10);
end;

procedure TTestArrange.TestAlignVertical;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  AssertAt('B', 50, 20);
end;

procedure TTestArrange.TestAlignHorizontal;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 7);
  B := Free('B', 10, 20);
  Apply(Request(aaAlignHorizontal, [A, B], A.Key));
  AssertAt('B', 10, 7);
end;

procedure TTestArrange.TestAlignHolds;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  AssertTrue(FPattern.SetFormula(A, 'x', '80'));
  FPattern.Evaluate;
  AssertAt('B', 80, 20);
end;

procedure TTestArrange.TestAlignCartesianOffset;
var
  A, B: TFreePoint;
  C: TOffsetPoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  C := FPattern.AddOffsetPoint('C', B.Key, omCartesian, '5', '5');
  Apply(Request(aaAlignVertical, [A, C], A.Key));
  AssertAt('C', 50, 25);
  AssertTrue('still an offset', FPattern.FindNode(C.Key) is TOffsetPoint);
  AssertTrue(FPattern.SetFormula(B, 'x', '0'));
  FPattern.Evaluate;
  AssertAt('C', 50, 25);
end;

procedure TTestArrange.TestAlignNeedsAReference;
var
  Items: TArrangeItemArray;
  Err: string;
begin
  AssertFalse(PlanArrange(FPattern, Request(aaAlignVertical, [Free('A', 0, 0)], ''), Items, Err));
  AssertEquals(rsArrangeNoReference, Err);
end;

procedure TTestArrange.TestAlignNeedsAPoint;
var
  A: TFreePoint;
  Items: TArrangeItemArray;
  Err: string;
begin
  A := Free('A', 0, 0);
  AssertFalse('only the reference is selected', PlanArrange(FPattern, Request(aaAlignVertical, [A], A.Key), Items, Err));
  AssertEquals(rsArrangeTooFewToAlign, Err);
end;

procedure TTestArrange.TestAlignAsksBeforeFormula;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := FPattern.AddFreePoint('B', '10 + 5', '20');
  AssertTrue(Plan(Request(aaAlignVertical, [A, B], A.Key))[0].Choice = acAsk);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  AssertAt('B', 15, 20);
end;

procedure TTestArrange.TestAlignAsksBeforeOperation;
var
  A, B: TFreePoint;
  C: TOffsetPoint;
  Items: TArrangeItemArray;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  C := FPattern.AddOffsetPoint('C', B.Key, omPolar, '10', '0');
  Items := Plan(Request(aaAlignVertical, [A, C], A.Key));
  AssertTrue(Items[0].Choice = acAsk);
  AssertEquals(rsArrangeOperation, Items[0].Reason);
  Apply(Request(aaAlignVertical, [A, C], A.Key));
  AssertTrue('left alone unless told', FPattern.FindNode(C.Key) = TObject(C));
end;

procedure TTestArrange.TestAlignReplacesWhenTold;
var
  A, B: TFreePoint;
  Replace: TStringArray;
begin
  A := Free('A', 50, 0);
  B := FPattern.AddFreePoint('B', '10 + 5', '20');
  Replace := nil;
  Insert(B.Key, Replace, 0);
  Apply(Request(aaAlignVertical, [A, B], A.Key), Replace);
  AssertAt('B', 50, 20);
end;

procedure TTestArrange.TestAlignReplacingKeepsOtherCoordinate;
var
  A, B: TFreePoint;
  C: TOffsetPoint;
  Replace: TStringArray;
  Key: string;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  C := FPattern.AddOffsetPoint('C', B.Key, omPolar, '10', '0');
  Key := C.Key;
  Replace := nil;
  Insert(Key, Replace, 0);
  Apply(Request(aaAlignVertical, [A, C], A.Key), Replace);
  AssertTrue(FPattern.FindNode(Key) is TFreePoint);
  AssertAt('C', 50, 20);
end;

procedure TTestArrange.TestAlignSkipsWhatItIsUsedBy;
var
  A, B: TFreePoint;
  C: TOffsetPoint;
  Items: TArrangeItemArray;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  C := FPattern.AddOffsetPoint('C', B.Key, omCartesian, '5', '5');
  Items := Plan(Request(aaAlignVertical, [C, B], C.Key));
  AssertTrue('C reads B, so B cannot read C', Items[0].Choice = acKeep);
  AssertEquals(rsArrangeDepends, Items[0].Reason);
  Apply(Request(aaAlignVertical, [C, B], C.Key));
  AssertAt('B', 10, 20);
  AssertAt('A', 50, 0);
end;

procedure TTestArrange.TestAlignAlreadyThere;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  AssertTrue(Plan(Request(aaAlignVertical, [A, B], A.Key))[0].Choice = acKeep);
end;

procedure TTestArrange.TestDistribute;
var
  A, B, C, D: TFreePoint;
  Key: string;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := Free('C', 10, 50);
  D := Free('D', 250, -30);
  Key := C.Key;
  Apply(Request(aaDistribute, [A, C, D, B]));
  AssertAt('C', 100, 0);
  AssertAt('D', 200, 0);
  AssertTrue(FPattern.FindNode(Key) is TBetweenPoint);
end;

// Whatever order they were picked in
procedure TTestArrange.TestDistributeFindsOutermost;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 40, 0);
  B := Free('B', 0, 0);
  C := Free('C', 100, 0);
  Apply(Request(aaDistribute, [A, B, C]));
  AssertAt('A', 50, 0);
  AssertAt('B', 0, 0);
  AssertAt('C', 100, 0);
end;

procedure TTestArrange.TestDistributeHolds;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := Free('C', 10, 0);
  Apply(Request(aaDistribute, [A, B, C]));
  AssertTrue(FPattern.SetFormula(B, 'x', '200'));
  FPattern.Evaluate;
  AssertAt('C', 100, 0);
end;

procedure TTestArrange.TestDistributeOnlyMovesInner;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  C := Free('C', 10, 0);
  AssertEquals(1, Length(Plan(Request(aaDistribute, [A, B, C]))));
  AssertEquals(C.Key, Plan(Request(aaDistribute, [A, B, C]))[0].Key);
end;

procedure TTestArrange.TestDistributeNeedsThree;
var
  Items: TArrangeItemArray;
  Err: string;
begin
  AssertFalse(PlanArrange(FPattern, Request(aaDistribute, [Free('A', 0, 0), Free('B', 1, 0)]), Items, Err));
  AssertEquals(rsArrangeTooFewToDistribute, Err);
end;

// A crossing has no formulas at all, so nothing else would stop it being replaced
procedure TTestArrange.TestDistributeAsksBeforeOperation;
var
  A, B, C, D: TFreePoint;
  Crossing: TIntersectPoint;
  Items: TArrangeItemArray;
  Key: string;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := Free('C', 100, -50);
  D := Free('D', 100, 50);
  Crossing := FPattern.AddIntersectPoint('X', FPattern.AddLine(A.Key, B.Key).Key, FPattern.AddLine(C.Key, D.Key).Key, False, False, 1);
  AssertNotNull(FPattern.LastError, Crossing);
  Key := Crossing.Key;
  Items := Plan(Request(aaDistribute, [A, B, Crossing]));
  AssertEquals(1, Length(Items));
  AssertTrue(Items[0].Choice = acAsk);
  AssertEquals(rsArrangeOperation, Items[0].Reason);
  Apply(Request(aaDistribute, [A, B, Crossing]));
  AssertTrue('left alone unless told', FPattern.FindNode(Key) is TIntersectPoint);
end;

procedure TTestArrange.TestDistributeAsksBeforeFormula;
var
  A, B, C: TFreePoint;
  Items: TArrangeItemArray;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := FPattern.AddFreePoint('C', '10 + 5', '20');
  Items := Plan(Request(aaDistribute, [A, B, C]));
  AssertTrue(Items[0].Choice = acAsk);
  AssertEquals(rsArrangeFormula, Items[0].Reason);
end;

procedure TTestArrange.TestDistributeHorizontal;
var
  A, B, C, D: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 10);
  C := Free('C', 10, 50);
  D := Free('D', 250, 70);
  Apply(Request(aaDistributeHorizontal, [A, B, C, D]));
  AssertAt('C', 100, 50);
  AssertAt('D', 200, 70);
  AssertTrue(FPattern.SetFormula(B, 'x', '600'));
  FPattern.Evaluate;
  AssertAt('C', 200, 50);
end;

procedure TTestArrange.TestDistributeVertical;
var
  A, B, C: TFreePoint;
begin
  A := Free('A', 0, 0);
  B := Free('B', 5, 100);
  C := Free('C', 9, 10);
  Apply(Request(aaDistributeVertical, [A, B, C]));
  AssertAt('C', 9, 50);
end;

procedure TTestArrange.TestDistributeAlongLine;
var
  A, B, C, D: TFreePoint;
  Edge: TLineObject;
  Key: string;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := Free('C', 20, 5);
  D := Free('D', 250, 5);
  Edge := FPattern.AddLine(A.Key, B.Key);
  Key := C.Key;
  Apply(Request(aaDistributeAlongEdge, [C, D], '', Edge.Key));
  AssertAt('C', 100, 0);
  AssertAt('D', 200, 0);
  AssertTrue(FPattern.FindNode(Key) is TAlongEdgePoint);
end;

procedure TTestArrange.TestDistributeAlongCurve;
var
  A, B, C: TFreePoint;
  Edge: TCurveObject;
  Middle: TVec2;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := Free('C', 100, 50);
  Edge := FPattern.AddCurve(A.Key, B.Key, '90', '100', '90', '100');
  AssertNotNull(FPattern.LastError, Edge);
  Apply(Request(aaDistributeAlongEdge, [C], '', Edge.Key));
  Middle := Edge.PointAtLength(Edge.Length / 2);
  AssertAt('C', Middle.X, Middle.Y);
end;

procedure TTestArrange.TestDistributeAlongEdgeLeavesEnds;
var
  A, B, C: TFreePoint;
  Edge: TLineObject;
begin
  A := Free('A', 0, 0);
  B := Free('B', 300, 0);
  C := Free('C', 20, 5);
  Edge := FPattern.AddLine(A.Key, B.Key);
  Apply(Request(aaDistributeAlongEdge, [A, C, B], '', Edge.Key));
  AssertAt('A', 0, 0);
  AssertAt('B', 300, 0);
  AssertAt('C', 150, 0);
end;

procedure TTestArrange.TestDistributeAlongNeedsAnEdge;
var
  Items: TArrangeItemArray;
  Err: string;
begin
  AssertFalse(PlanArrange(FPattern, Request(aaDistributeAlongEdge, [Free('A', 0, 0)]), Items, Err));
  AssertEquals(rsArrangeNoEdge, Err);
end;

procedure TTestArrange.TestPlanChangesNothing;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  Plan(Request(aaAlignVertical, [A, B], A.Key));
  FPattern.Evaluate;
  AssertAt('B', 10, 20);
end;

procedure TTestArrange.TestBetweenRoundTrip;
var
  A, B: TFreePoint;
  Loaded: TPattern;
  Err: string;
begin
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  FPattern.AddBetweenPoint('C', A.Key, B.Key, amLength, '30');
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, SavePatternToText(FPattern), Err));
    Loaded.Evaluate;
    AssertTrue(Loaded.FindObject('C') is TBetweenPoint);
    AssertTrue(TBetweenPoint(Loaded.FindObject('C')).Mode = amLength);
    AssertNear('x', 30, TPointObject(Loaded.FindObject('C')).Position.X);
  finally
    FreeAndNil(Loaded);
  end;
end;

// The point was made first, so now it reads points that come after it in the file
procedure TTestArrange.TestConvertedPointUsingLaterPointsLoads;
var
  Inner, A, B: TFreePoint;
  Loaded: TPattern;
  Err: string;
begin
  Inner := Free('C', 10, 10);
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  Apply(Request(aaDistribute, [Inner, A, B]));
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, SavePatternToText(FPattern), Err));
    Loaded.Evaluate;
    AssertNear('x', 50, TPointObject(Loaded.FindObject('C')).Position.X);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestArrange.TestAlignToALaterPointLoads;
var
  B, A: TFreePoint;
  Loaded: TPattern;
  Err: string;
begin
  B := Free('B', 10, 20);
  A := Free('A', 50, 0);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, SavePatternToText(FPattern), Err));
    Loaded.Evaluate;
    AssertNear('x', 50, TPointObject(Loaded.FindObject('B')).Position.X);
  finally
    FreeAndNil(Loaded);
  end;
end;

// Only what has to move does
procedure TTestArrange.TestOrderKeepsTheRest;
var
  Inner, A, B: TFreePoint;
begin
  Free('First', 1, 1);
  Inner := Free('C', 10, 10);
  Free('Middle', 2, 2);
  A := Free('A', 0, 0);
  B := Free('B', 100, 0);
  Free('Last', 3, 3);
  FPattern.Evaluate;
  AssertNotNull(FPattern.ConvertToBetween(Inner, A.Key, B.Key, amRatio, '0.5'));
  AssertEquals('First', FPattern.Objects[0].Name);
  AssertEquals('A', FPattern.Objects[1].Name);
  AssertEquals('B', FPattern.Objects[2].Name);
  AssertEquals('C', FPattern.Objects[3].Name);
  AssertEquals('Middle', FPattern.Objects[4].Name);
  AssertEquals('Last', FPattern.Objects[5].Name);
end;

// Undo loads the saved text, so it relies on the order too
procedure TTestArrange.TestUndoAfterAConvertedPointMoved;
var
  Document: TPatternDocument;
  C, A, B: TFreePoint;
  Err: string;
  Wanted: TArrangeRequest;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Points');
    C := Document.Pattern.AddFreePoint('C', '10', '10');
    A := Document.Pattern.AddFreePoint('A', '0', '0');
    B := Document.Pattern.AddFreePoint('B', '100', '0');
    Document.Commit(True);
    Wanted := Default(TArrangeRequest);
    Wanted.Action := aaDistribute;
    Wanted.Points := [C.Key, A.Key, B.Key];
    Document.BeginChange('Distribute');
    AssertTrue(Err, ApplyArrange(Document.Pattern, Wanted, nil, Err));
    Document.Commit(True);
    AssertTrue(Document.Undo);
    AssertEquals('order back too', 'C', Document.Pattern.Objects[0].Name);
    AssertTrue(Document.Redo);
    AssertNear('and forward again', 50, TPointObject(Document.Pattern.FindObject('C')).Position.X);
  finally
    FreeAndNil(Document);
  end;
end;

// Formulas go by ID, so renaming the reference changes nothing
procedure TTestArrange.TestRenameAfterAlign;
var
  A, B: TFreePoint;
begin
  A := Free('A', 50, 0);
  B := Free('B', 10, 20);
  Apply(Request(aaAlignVertical, [A, B], A.Key));
  AssertTrue(FPattern.Rename(A, 'Reference'));
  AssertEquals('Reference.x', FPattern.FormulaText(B, 'x'));
  FPattern.Evaluate;
  AssertNear('x', 50, B.Position.X);
end;

procedure TTestArrange.TestDocumentUndoesItAsOneStep;
var
  Document: TPatternDocument;
  A, B, C, D: TFreePoint;
  Err: string;
  Wanted: TArrangeRequest;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Points');
    A := Document.Pattern.AddFreePoint('A', '0', '0');
    B := Document.Pattern.AddFreePoint('B', '300', '0');
    C := Document.Pattern.AddFreePoint('C', '10', '5');
    D := Document.Pattern.AddFreePoint('D', '250', '5');
    Document.Commit(True);
    Wanted := Default(TArrangeRequest);
    Wanted.Action := aaDistribute;
    Wanted.Points := [A.Key, B.Key, C.Key, D.Key];
    Document.BeginChange('Distribute');
    AssertTrue(Err, ApplyArrange(Document.Pattern, Wanted, nil, Err));
    Document.Commit(True);
    AssertNear('moved', 100, TPointObject(Document.Pattern.FindObject('C')).Position.X);
    AssertTrue(Document.Undo);
    AssertTrue(Document.Pattern.FindObject('C') is TFreePoint);
    AssertTrue(Document.Pattern.FindObject('D') is TFreePoint);
    AssertNear('back', 10, TPointObject(Document.Pattern.FindObject('C')).Position.X);
    AssertTrue(Document.Redo);
    AssertTrue(Document.Pattern.FindObject('D') is TBetweenPoint);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestArrange.TestDocumentCancelsAFailure;
var
  Document: TPatternDocument;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Points');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.Commit(True);
    Document.BeginChange('Change');
    AssertNull(Document.Pattern.ConvertToFree(TPointObject(Document.Pattern.FindObject('A')), '1 +', '0'));
    Document.CancelChange;
    AssertTrue(Document.Pattern.FindObject('A') is TFreePoint);
  finally
    FreeAndNil(Document);
  end;
end;

initialization
  RegisterTest(TTestArrange);

end.
