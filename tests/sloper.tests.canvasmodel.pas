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

// The canvas's LCL-free parts: the view transform, and the scene (extent,
// edges as polylines, what is under the cursor).
unit Sloper.Tests.CanvasModel;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern;

type
  TTestCanvasModel = class(TOSTestCase)
  private
    FPattern: TPattern;
    procedure Build;
    procedure AssertLabels(const Msg, Expected: string; const Keys: TStringArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestYIsFlipped;
    procedure TestRoundTrip;
    procedure TestZoomKeepsAnchor;
    procedure TestZoomLimits;
    procedure TestFit;
    procedure TestTrueScale;
    procedure TestBoundsIncludeCurves;
    procedure TestNothingShownBeforeEvaluate;
    procedure TestPointAt;
    procedure TestEdgeAt;
    procedure TestPolylines;
    procedure TestPolylineMiddle;
    procedure TestObjectsBounds;
    procedure TestRevealLeavesVisibleAlone;
    procedure TestRevealCentresWithoutZooming;
    procedure TestLabelModes;
    procedure TestContextualHover;
    procedure TestContextualSelection;
    procedure TestContextualToolKeys;
    procedure TestContextualFormulaInput;
    procedure TestLabelsWaitForResults;
  end;

implementation

uses
  Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Settings, Sloper.UI.View, Sloper.UI.Scene;

function MakeRect(MinX, MinY, MaxX, MaxY: double): TRect2;
begin
  Result.MinX := MinX;
  Result.MinY := MinY;
  Result.MaxX := MaxX;
  Result.MaxY := MaxY;
end;

procedure TTestCanvasModel.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestCanvasModel.TearDown;
begin
  FreeAndNil(FPattern);
end;

// A (0, 0), B (100, 0), C (100, 50); a line A-B and a curve A-C bulging below y = 0
procedure TTestCanvasModel.Build;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100', '0');
  FPattern.AddFreePoint('C', '100', '50');
  FPattern.AddLine('1', '2');
  FPattern.AddCurve('1', '3', '270', '60', '270', '60');
end;

procedure TTestCanvasModel.TestYIsFlipped;
var
  View: TViewTransform;
begin
  View.Scale := 2;
  View.OriginX := 100;
  View.OriginY := 300;
  AssertPointsNear('origin', Vec2(100, 300), View.ToScreen(Vec2(0, 0)));
  AssertPointsNear('up in the model is up on screen', Vec2(120, 280), View.ToScreen(Vec2(10, 10)));
  AssertNear('pixels to mm', 5, View.PixelsToMM(10));
end;

procedure TTestCanvasModel.TestRoundTrip;
var
  View: TViewTransform;
begin
  View := DefaultView;
  View.ZoomAt(3.7, Vec2(123, 456));
  View.Pan(-17, 9);
  AssertPointsNear('round trip', Vec2(-31.5, 77.25), View.ToModel(View.ToScreen(Vec2(-31.5, 77.25))));
end;

procedure TTestCanvasModel.TestZoomKeepsAnchor;
var
  View: TViewTransform;
  Before: TVec2;
begin
  View := DefaultView;
  Before := View.ToModel(Vec2(250, 180));
  View.ZoomAt(ZoomStep, Vec2(250, 180));
  AssertNear('scale', DefaultView.Scale * ZoomStep, View.Scale);
  AssertPointsNear('same model point under the cursor', Before, View.ToModel(Vec2(250, 180)));
end;

procedure TTestCanvasModel.TestZoomLimits;
var
  View: TViewTransform;
begin
  View := DefaultView;
  View.ZoomAt(1e9, Vec2(0, 0));
  AssertNear('max', MaxScale, View.Scale);
  View.ZoomAt(1e-12, Vec2(0, 0));
  AssertNear('min', MinScale, View.Scale);
end;

procedure TTestCanvasModel.TestFit;
var
  View: TViewTransform;
  Bounds: TRect2;
begin
  Bounds.MinX := 0;
  Bounds.MinY := -600;
  Bounds.MaxX := 480;
  Bounds.MaxY := 12;
  View := DefaultView;
  View.Fit(Bounds, 1000, 700, 50);
  AssertNear('height limits the scale', 600 / 612, View.Scale);
  AssertPointsNear('centred', Vec2(500, 350), View.ToScreen(Vec2(240, -294)));
end;

procedure TTestCanvasModel.TestTrueScale;
begin
  AssertNear('96 dpi', 96 / 25.4, TrueScale(96));
end;

procedure TTestCanvasModel.TestBoundsIncludeCurves;
var
  Bounds: TRect2;
begin
  Build;
  FPattern.Evaluate;
  AssertTrue(PatternBounds(FPattern, Bounds));
  AssertNear('min x', 0, Bounds.MinX);
  AssertNear('max x', 100, Bounds.MaxX);
  AssertNear('max y', 50, Bounds.MaxY);
  AssertTrue('the curve dips below the points', Bounds.MinY < -10);
end;

procedure TTestCanvasModel.TestNothingShownBeforeEvaluate;
var
  Bounds: TRect2;
begin
  Build;
  AssertFalse('nothing computed', PatternBounds(FPattern, Bounds));
  AssertNull('no point', PointAt(FPattern, Vec2(0, 0), 5));
end;

procedure TTestCanvasModel.TestPointAt;
begin
  Build;
  FPattern.Evaluate;
  AssertEquals('nearest', 'B', PointAt(FPattern, Vec2(97, 2), 5).Name);
  AssertNull('out of reach', PointAt(FPattern, Vec2(50, 20), 5));
end;

procedure TTestCanvasModel.TestEdgeAt;
begin
  Build;
  FPattern.Evaluate;
  AssertEquals('the line', 'Line_A_B', EdgeAt(FPattern, Vec2(50, 1), 3).Name);
  AssertNull('nothing near', EdgeAt(FPattern, Vec2(50, 25), 3));
end;

procedure TTestCanvasModel.TestPolylines;
var
  Line, Curve: TVec2Array;
  Index: integer;
begin
  Build;
  FPattern.Evaluate;
  Line := EdgePolyline(TEdgeObject(FPattern.FindNode('4')), 0.1);
  AssertEquals('a line is its two ends', 2, Length(Line));
  Curve := EdgePolyline(TEdgeObject(FPattern.FindNode('5')), 0.1);
  AssertTrue('a curve is flattened', Length(Curve) > 4);
  AssertPointsNear('starts at A', Vec2(0, 0), Curve[0]);
  AssertPointsNear('ends at C', Vec2(100, 50), Curve[High(Curve)]);
  for Index := 1 to High(Curve) do
    AssertTrue('no repeated points', Distance(Curve[Index - 1], Curve[Index]) > 1e-9);
end;

procedure TTestCanvasModel.TestObjectsBounds;
var
  Bounds: TRect2;
begin
  Build;
  FPattern.Evaluate;
  AssertTrue('a line', ObjectsBounds(FPattern, ['4'], Bounds));
  AssertNear('line width', 100, Bounds.MaxX - Bounds.MinX);
  AssertNear('thin side grown', MinFocusSize, Bounds.MaxY - Bounds.MinY);
  AssertTrue('a point', ObjectsBounds(FPattern, ['2'], Bounds));
  AssertNear('centred on the point', 100, (Bounds.MinX + Bounds.MaxX) / 2);
  AssertNear('point area', MinFocusSize, Bounds.MaxX - Bounds.MinX);
  AssertFalse('unknown key', ObjectsBounds(FPattern, ['99'], Bounds));
  AssertFalse('nothing', ObjectsBounds(FPattern, nil, Bounds));
end;

procedure TTestCanvasModel.TestRevealLeavesVisibleAlone;
var
  View: TViewTransform;
  Bounds: TRect2;
begin
  View := DefaultView;
  View.Scale := 1;
  View.OriginX := 0;
  View.OriginY := 400;
  Bounds := MakeRect(10, 10, 50, 50);
  View.Reveal(Bounds, 800, 400, 5);
  AssertNear('x', 0, View.OriginX);
  AssertNear('y', 400, View.OriginY);
end;

procedure TTestCanvasModel.TestRevealCentresWithoutZooming;
var
  View: TViewTransform;
  Centre: TVec2;
begin
  View := DefaultView;
  View.Scale := 2;
  View.OriginX := 0;
  View.OriginY := 400;
  View.Reveal(MakeRect(1000, -500, 1100, -400), 800, 400, 5);
  AssertNear('zoom kept', 2, View.Scale);
  Centre := View.ToScreen(Vec2(1050, -450));
  AssertPointsNear('centred', Vec2(400, 200), Centre);
end;

procedure TTestCanvasModel.TestPolylineMiddle;
begin
  AssertPointsNear('a line', Vec2(50, 0), PolylineMiddle([Vec2(0, 0), Vec2(100, 0)]));
  AssertPointsNear('on a corner', Vec2(10, 0), PolylineMiddle([Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)]));
  AssertPointsNear('by length, not by vertex', Vec2(5, 0), PolylineMiddle([Vec2(0, 0), Vec2(1, 0), Vec2(2, 0), Vec2(10, 0)]));
  AssertPointsNear('one point', Vec2(3, 4), PolylineMiddle([Vec2(3, 4)]));
end;

procedure TTestCanvasModel.AssertLabels(const Msg, Expected: string; const Keys: TStringArray);
begin
  AssertEquals(Msg, Expected, string.Join(' ', Keys));
end;

procedure TTestCanvasModel.TestLabelModes;
begin
  Build;
  FPattern.Evaluate;
  AssertLabels('all', '1 2 3 4 5', LabelKeys(FPattern, lmAll, nil, '', nil));
  AssertLabels('none, even when selected', '', LabelKeys(FPattern, lmNone, ['1'], '2', ['3']));
  AssertLabels('contextual with nothing going on', '', LabelKeys(FPattern, lmContextual, nil, '', nil));
end;

procedure TTestCanvasModel.TestContextualHover;
begin
  Build;
  FPattern.Evaluate;
  AssertLabels('only the hovered object', '2', LabelKeys(FPattern, lmContextual, nil, '2', nil));
end;

procedure TTestCanvasModel.TestContextualSelection;
begin
  Build;
  FPattern.Evaluate;
  AssertLabels('a point and the edges using it', '1 4 5', LabelKeys(FPattern, lmContextual, ['1'], '', nil));
  AssertLabels('an edge and its ends', '1 2 4', LabelKeys(FPattern, lmContextual, ['4'], '', nil));
  AssertLabels('gone from the pattern', '', LabelKeys(FPattern, lmContextual, ['99'], '', nil));
end;

procedure TTestCanvasModel.TestContextualToolKeys;
begin
  Build;
  FPattern.Evaluate;
  AssertLabels('what the tool works with', '2 4', LabelKeys(FPattern, lmContextual, nil, '', ['2', '4']));
end;

// Formula references count as inputs; variables have no label on the canvas
procedure TTestCanvasModel.TestContextualFormulaInput;
var
  Point: TDraftObject;
begin
  Build;
  FPattern.AddVariable('ease', '5');
  Point := FPattern.AddFreePoint('D', 'B.x + #ease', '0');
  FPattern.Evaluate;
  AssertLabels('the point it reads', '2 ' + Point.Key, LabelKeys(FPattern, lmContextual, [Point.Key], '', nil));
end;

procedure TTestCanvasModel.TestLabelsWaitForResults;
begin
  Build;
  AssertLabels('not computed yet', '', LabelKeys(FPattern, lmAll, nil, '', nil));
end;

initialization
  RegisterTest(TTestCanvasModel);

end.
