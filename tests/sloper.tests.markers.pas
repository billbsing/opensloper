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

// Point markers: holes, buttons and match dots on points and repeats,
// assigned to the pieces they lie in (see Point markers in the design).
unit Sloper.Tests.Markers;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Draft,
  Sloper.Core.Piece;

type
  TTestMarkers = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X: double = 0; Y: double = 0): string;
    procedure Rectangle;
    function Reloaded: TPattern;
    function PieceAt(X, Y: double; const AName: string = 'Panel'): TPieceObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNewPointIsPlain;
    procedure TestMarkerStartsAtItsDefaultSize;
    procedure TestButtonIsMarkedNotCut;
    procedure TestMatchDotReadsAsFilled;
    procedure TestSizeIsAFormula;
    procedure TestPlainTakesItOff;
    procedure TestBadSizeLeavesMarkerAsItWas;
    procedure TestMarkerJoinsNewPiece;
    procedure TestMarkerInOverlappingPiecesJoinsBoth;
    procedure TestLooseMarkerReported;
    procedure TestRepeatMarksEveryPoint;
    procedure TestRepeatPointRefused;
    procedure TestEdgeRefused;
    procedure TestAttachNeedsMarker;
    procedure TestCopyKeepsMarker;
    procedure TestMarkerRoundTrip;
    procedure TestOldHoleBecomesMarker;
    procedure TestMarkerStrokes;
  end;

implementation

uses
  fpjson, Sloper.Core.EvalTypes, Sloper.Core.JSON, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.PatternCheck,
  Sloper.Core.Transform;

procedure TTestMarkers.SetUp;
begin
  inherited SetUp;
  FPattern := TPattern.Create;
end;

procedure TTestMarkers.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
  inherited TearDown;
end;

function TTestMarkers.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

// 200 by 100 from the origin
procedure TTestMarkers.Rectangle;
var
  Edges: TRectangleEdges;
begin
  AssertTrue(FPattern.LastError, FPattern.AddRectangle(Pt('O'), '200', '100', erOutline, Edges));
  FPattern.Evaluate;
end;

function TTestMarkers.Reloaded: TPattern;
var
  Reason: string;
begin
  FreeAndNil(FLoaded);
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Reason));
  FLoaded.Evaluate;
  Result := FLoaded;
end;

function TTestMarkers.PieceAt(X, Y: double; const AName: string): TPieceObject;
var
  Path: TPiecePath;
  Reason: string;
begin
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(X, Y), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, DefaultPieceAllowance);
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestMarkers.TestNewPointIsPlain;
var
  Point: TDraftObject;
begin
  Point := TDraftObject(FPattern.FindNode(Pt('A', 5, 5)));
  AssertTrue(Point.Marker = pmPlain);
  AssertNull('no size field', Point.Field(MarkerSizeField));
end;

procedure TTestMarkers.TestMarkerStartsAtItsDefaultSize;
var
  Key: string;
begin
  Key := Pt('A', 5, 5);
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Key, pmButton));
  FPattern.Evaluate;
  AssertEquals(15, TDraftObject(FPattern.FindNode(Key)).MarkerSize, 1e-9);
  AssertTrue(FPattern.SetMarker(Key, pmMatch));
  FPattern.Evaluate;
  AssertEquals('another marker keeps the size', 15, TDraftObject(FPattern.FindNode(Key)).MarkerSize, 1e-9);
end;

procedure TTestMarkers.TestButtonIsMarkedNotCut;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.SetMarker(Pt('Btn', 100, 50), pmButton, '12'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(1, Length(Piece.MarkingMarks));
  AssertTrue(Piece.MarkingMarks[0].Marker = pmButton);
  AssertEquals('not cut', 0, Length(Piece.MarkingMarks[0].Holes));
  AssertEquals(1, Length(Piece.MarkingMarks[0].Centres));
  AssertPointsNear('at its point', Vec2(100, 50), Piece.MarkingMarks[0].Centres[0]);
  AssertEquals(12, Piece.MarkingMarks[0].HoleSize, 1e-9);
  AssertEquals('a circle and a cross', 18, Length(Piece.MarkingStrokes));
end;

procedure TTestMarkers.TestMatchDotReadsAsFilled;
var
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  AssertTrue(FPattern.SetMarker(Pt('M', 100, 50), pmMatch));
  FPattern.Evaluate;
  AssertEquals('three rings', 48, Length(Piece.MarkingStrokes));
end;

procedure TTestMarkers.TestSizeIsAFormula;
var
  Key: string;
begin
  Key := Pt('A', 5, 5);
  AssertTrue(FPattern.SetMarker(Key, pmHole, '2 * 3'));
  FPattern.Evaluate;
  AssertEquals(6, TDraftObject(FPattern.FindNode(Key)).MarkerSize, 1e-9);
  AssertTrue(FPattern.SetFormula(FPattern.FindNode(Key), MarkerSizeField, '5'));
  FPattern.Evaluate;
  AssertEquals(5, TDraftObject(FPattern.FindNode(Key)).MarkerSize, 1e-9);
end;

procedure TTestMarkers.TestPlainTakesItOff;
var
  Piece: TPieceObject;
  Key: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmHole));
  FPattern.Evaluate;
  AssertEquals(1, Length(Piece.Markings));
  AssertTrue(FPattern.SetMarker(Key, pmPlain));
  AssertEquals(0, Length(Piece.Markings));
  AssertNull('size field gone', FPattern.FindNode(Key).Field(MarkerSizeField));
end;

procedure TTestMarkers.TestBadSizeLeavesMarkerAsItWas;
var
  Key, Other: string;
begin
  Key := Pt('A', 5, 5);
  AssertTrue(FPattern.SetMarker(Key, pmHole, '4'));
  AssertFalse(FPattern.SetMarker(Key, pmButton, '4 +'));
  AssertTrue(TDraftObject(FPattern.FindNode(Key)).Marker = pmHole);
  AssertEquals('4', FPattern.FormulaText(FPattern.FindNode(Key), MarkerSizeField));
  Other := Pt('Other', 5, 5);
  AssertFalse('from plain', FPattern.SetMarker(Other, pmHole, 'nonsense +'));
  AssertTrue(TDraftObject(FPattern.FindNode(Other)).Marker = pmPlain);
  AssertNull(FPattern.FindNode(Other).Field(MarkerSizeField));
end;

procedure TTestMarkers.TestMarkerJoinsNewPiece;
var
  Key: string;
  Piece: TPieceObject;
begin
  Rectangle;
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmHole));
  FPattern.Evaluate;
  Piece := PieceAt(50, 50);
  AssertEquals(0, Piece.PointMarkingOf(Key));
end;

procedure TTestMarkers.TestMarkerInOverlappingPiecesJoinsBoth;
var
  Inner, Outer: TPieceObject;
  Edges: TRectangleEdges;
  Path: TPiecePath;
  Index: integer;
  Key: string;
begin
  Rectangle;
  Inner := PieceAt(50, 50, 'Inner');
  AssertTrue(FPattern.AddRectangle(Pt('Corner2', -50, -50), '300', '200', erOutline, Edges));
  Path := nil;
  SetLength(Path, 4);
  for Index := 0 to 3 do
    Path[Index].EdgeKey := Edges[Index].Key;
  Outer := FPattern.AddPiece('Outer', Path, '10');
  FPattern.Evaluate;
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmMatch));
  FPattern.Evaluate;
  AssertTrue('inner', Inner.PointMarkingOf(Key) >= 0);
  AssertTrue('outer', Outer.PointMarkingOf(Key) >= 0);
  AssertEquals(2, Length(FPattern.PiecesWithMarking(Key)));
end;

procedure TTestMarkers.TestLooseMarkerReported;
var
  Key, Problem: string;
  Blocked: integer;
  Found: boolean;
begin
  Rectangle;
  PieceAt(50, 50);
  Key := Pt('H', 500, 50);
  AssertTrue(FPattern.SetMarker(Key, pmHole));
  FPattern.Evaluate;
  Found := False;
  for Problem in PatternProblems(FPattern, Blocked) do
    Found := Found or (Problem = Format(rsCheckMarkerLoose, ['H']));
  AssertTrue(Found);
end;

procedure TTestMarkers.TestRepeatMarksEveryPoint;
var
  Piece: TPieceObject;
  Buttons: TRepeatObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Buttons := FPattern.AddRepeatBetween('Btn', Pt('T', 100, 10), Pt('U', 100, 90), '5', True);
  AssertNotNull(FPattern.LastError, Buttons);
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Buttons.Key, pmButton, '11'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals(0, Piece.PointMarkingOf(Buttons.Key));
  AssertEquals(5, Length(Piece.MarkingMarks[0].Centres));
  AssertPointsNear('last', Vec2(100, 90), Piece.MarkingMarks[0].Centres[4]);
  AssertTrue(FPattern.SetFormula(Buttons, 'count', '3'));
  FPattern.Evaluate;
  AssertEquals('follows the count', 3, Length(Piece.MarkingMarks[0].Centres));
end;

procedure TTestMarkers.TestRepeatPointRefused;
var
  Buttons: TRepeatObject;
  Used: string;
begin
  Buttons := FPattern.AddRepeatBetween('Btn', Pt('T', 100, 10), Pt('U', 100, 90), '5', True);
  FPattern.Evaluate;
  Used := FPattern.UsePoint(Buttons.Item(2).Key);
  AssertFalse(FPattern.SetMarker(Used, pmButton));
  AssertEquals(Format(rsPatternMarkerOnRepeat, [FPattern.FindNode(Used).DisplayName, 'Btn']), FPattern.LastError);
end;

procedure TTestMarkers.TestEdgeRefused;
begin
  AssertFalse(FPattern.SetMarker(FPattern.AddLine(Pt('A'), Pt('B', 10, 0), erOutline).Key, pmHole));
end;

procedure TTestMarkers.TestAttachNeedsMarker;
var
  Piece: TPieceObject;
  Key: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Key := Pt('H', 100, 50);
  AssertFalse(FPattern.AddPointMarking(Piece, Key));
  AssertEquals(Format(rsPatternNoMarker, ['H']), FPattern.LastError);
end;

procedure TTestMarkers.TestCopyKeepsMarker;
var
  Spec: TTransformSpec;
  Transform: TTransformObject;
  Copy: TDraftObject;
  Key: string;
  Index: integer;
begin
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmButton, '12'));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := [Key];
  Spec.DX := '300';
  Spec.DY := '0';
  Transform := FPattern.AddTransform(Spec);
  AssertNotNull(FPattern.LastError, Transform);
  FPattern.Evaluate;
  Copy := nil;
  for Index := 0 to FPattern.ObjectCount - 1 do
    if FPattern.Objects[Index] is TPointCopy then
      Copy := FPattern.Objects[Index];
  AssertNotNull(Copy);
  AssertTrue(Copy.Marker = pmButton);
  AssertEquals(12, Copy.MarkerSize, 1e-9);
end;

procedure TTestMarkers.TestMarkerRoundTrip;
var
  Back: TPieceObject;
  Piece: TPieceObject;
  Buttons: TRepeatObject;
  Key: string;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmMatch, '3.5'));
  Buttons := FPattern.AddRepeatBetween('Btn', Pt('T', 150, 10), Pt('U', 150, 90), '4', True);
  AssertTrue(FPattern.SetMarker(Buttons.Key, pmButton));
  FPattern.Evaluate;
  Back := TPieceObject(Reloaded.FindNode(Piece.Key));
  AssertTrue(Back.Message, Back.State = esValid);
  AssertEquals(2, Length(Back.Markings));
  AssertTrue(TDraftObject(FLoaded.FindNode(Key)).Marker = pmMatch);
  AssertEquals(3.5, TDraftObject(FLoaded.FindNode(Key)).MarkerSize, 1e-9);
  AssertTrue(TDraftObject(FLoaded.FindNode(Buttons.Key)).Marker = pmButton);
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

// Written before point markers: a hole marking with its own diameter
procedure TTestMarkers.TestOldHoleBecomesMarker;
var
  Root: TJSONObject;
  Objects: TJSONArray;
  Item, Marking: TJSONObject;
  Index: integer;
  Key, Reason, OldText: string;
  Piece: TPieceObject;
begin
  Rectangle;
  Piece := PieceAt(50, 50);
  Key := Pt('H', 100, 50);
  AssertTrue(FPattern.SetMarker(Key, pmHole, '6'));
  FPattern.Evaluate;
  AssertTrue(ParseJSONObject(SavePatternToText(FPattern), Root, Reason));
  try
    Objects := TJSONArray(Root.Find('objects'));
    for Index := 0 to Objects.Count - 1 do
    begin
      Item := TJSONObject(Objects[Index]);
      if Item.Get('id', 0) = StrToInt(Key) then
      begin
        Item.Delete('marker');
        Item.Delete(MarkerSizeField);
      end;
      if Item.Get('id', 0) = StrToInt(Piece.Key) then
      begin
        Marking := TJSONObject(TJSONArray(Item.Find('markings'))[0]);
        Marking.Strings['kind'] := 'hole';
        Marking.Add('diameter', '6');
      end;
    end;
    OldText := Root.FormatJSON;
  finally
    FreeAndNil(Root);
  end;
  FLoaded := TPattern.Create;
  AssertTrue(Reason, LoadPatternFromText(FLoaded, OldText, Reason));
  FLoaded.Evaluate;
  AssertTrue(TDraftObject(FLoaded.FindNode(Key)).Marker = pmHole);
  AssertEquals(6, TDraftObject(FLoaded.FindNode(Key)).MarkerSize, 1e-9);
  AssertEquals(0, TPieceObject(FLoaded.FindNode(Piece.Key)).PointMarkingOf(Key));
  AssertEquals('written the new way', SavePatternToText(FPattern), SavePatternToText(FLoaded));
end;

procedure TTestMarkers.TestMarkerStrokes;
begin
  AssertEquals(0, Length(MarkerStrokes(pmPlain, Vec2(0, 0), 4)));
  AssertEquals(16, Length(MarkerStrokes(pmHole, Vec2(0, 0), 4)));
  AssertPointsNear('on the circle', Vec2(2, 0), MarkerStrokes(pmHole, Vec2(0, 0), 4)[0].P1);
end;

initialization
  RegisterTest(TTestMarkers);
end.
