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

unit Sloper.Tests.DraftSVG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern;

type
  TTestDraftSVG = class(TOSTestCase)
  private
    FPattern: TPattern;
    procedure Build;
    function Render(Labels: boolean = False): string;
    procedure AssertHas(const Msg, Part, Text: string);
    procedure AssertLacks(const Msg, Part, Text: string);
    procedure BuildPiece;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPointsAreFlipped;
    procedure TestLineIsAPath;
    procedure TestCurveIsABezier;
    procedure TestPathHasEverySegment;
    procedure TestConstructionIsDashed;
    procedure TestLabels;
    procedure TestViewBoxHasAMargin;
    procedure TestRegion;
    procedure TestFailingObjectIsRed;
    procedure TestNeverComputedFailureIsLeftOut;
    procedure TestNotComputedIsLeftOut;
    procedure TestEmptyPattern;
    procedure TestSizesFollowTheDrawing;
    procedure TestPieceIsDrawnUnderItsEdges;
    procedure TestNoFillsLeavesPieceUnfilled;
    procedure TestNoFillsLeavesOutHatching;
  end;

implementation

uses
  Sloper.Core.Draft, Sloper.Core.Fabrics, Sloper.Core.Geometry, Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Output.DraftSVG;

procedure TTestDraftSVG.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestDraftSVG.TearDown;
begin
  FreeAndNil(FPattern);
end;

// A (0, 0), B (100, 0), C (100, 50); an outline A-B and a curve A-C
procedure TTestDraftSVG.Build;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100', '0');
  FPattern.AddFreePoint('C', '100', '50');
  FPattern.AddLine('1', '2', erOutline);
  FPattern.AddCurve('1', '3', '270', '60', '270', '60');
  FPattern.Evaluate;
end;

function TTestDraftSVG.Render(Labels: boolean): string;
var
  Options: TDraftSVGOptions;
begin
  Options := DefaultDraftSVGOptions;
  Options.Labels := Labels;
  Result := DraftToSVG(FPattern, Options);
end;

procedure TTestDraftSVG.AssertHas(const Msg, Part, Text: string);
begin
  AssertTrue(Msg + ': expected ' + Part + ' in ' + Text, Pos(Part, Text) > 0);
end;

procedure TTestDraftSVG.AssertLacks(const Msg, Part, Text: string);
begin
  AssertTrue(Msg + ': did not expect ' + Part, Pos(Part, Text) = 0);
end;

procedure TTestDraftSVG.TestPointsAreFlipped;
begin
  Build;
  AssertHas('y up becomes y down', 'data-name="C" cx="100" cy="-50"', Render);
end;

procedure TTestDraftSVG.TestLineIsAPath;
begin
  Build;
  AssertHas('line', 'data-id="4" data-name="Line_A_B" d="M 0 0 L 100 0"', Render);
end;

procedure TTestDraftSVG.TestCurveIsABezier;
begin
  Build;
  // Handles straight down from A and C, 60 long: (0, -60) and (100, -10)
  AssertHas('exact, not flattened', 'd="M 0 0 C 0 60 100 10 100 -50"', Render);
end;

procedure TTestDraftSVG.TestPathHasEverySegment;
var
  Text: string;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100', '100');
  FPattern.AddFreePoint('C', '200', '0');
  FPattern.AddCurvePath(['1', '2', '3'], ['90', '0', '270'], ['', '50', '20'], ['30', '40', '']);
  FPattern.Evaluate;
  Text := Render;
  AssertHas('joined up', 'd="M 0 0 C 0 -30 50 -100 100 -100 C 140 -100 200 -20 200 0"', Text);
end;

procedure TTestDraftSVG.TestConstructionIsDashed;
var
  Text: string;
begin
  Build;
  Text := Render;
  AssertHas('construction', 'stroke-dasharray', Text);
  AssertLacks('outline solid', 'L 100 0" fill="none" stroke="#202020" stroke-width="0.15" stroke-dasharray', Text);
end;

procedure TTestDraftSVG.TestLabels;
begin
  Build;
  AssertLacks('off by default', '<text', Render);
  AssertHas('on', '>C</text>', Render(True));
end;

procedure TTestDraftSVG.TestViewBoxHasAMargin;
begin
  Build;
  // The curve dips to about y = -35, so check the sides and the top
  AssertHas('5% of 100 mm each side', 'viewBox="-5 -55 110 ', Render);
end;

procedure TTestDraftSVG.TestRegion;
var
  Options: TDraftSVGOptions;
begin
  Build;
  Options := DefaultDraftSVGOptions;
  Options.HasRegion := True;
  Options.Region.MinX := 10;
  Options.Region.MinY := 20;
  Options.Region.MaxX := 40;
  Options.Region.MaxY := 60;
  AssertHas('no margin, top is max y', 'viewBox="10 -60 30 40"', DraftToSVG(FPattern, Options));
end;

// A failing object is drawn at its last good result, in the colour of its state
procedure TTestDraftSVG.TestFailingObjectIsRed;
var
  Text: string;
begin
  FPattern.AddVariable('wide', '10');
  FPattern.AddFreePoint('A', '#wide', '0');
  FPattern.AddFreePoint('B', '100 / #wide', '0');
  FPattern.Evaluate;
  FPattern.SetFormula(FPattern.FindObject('B'), 'x', '100 / (#wide - 10)');
  FPattern.Evaluate;
  Text := Render;
  AssertHas('at its last good place, in red', 'data-name="B" cx="10" cy="0" r="0.03" fill="#c02020"', Text);
  AssertHas('the other is fine', 'data-name="A" cx="10" cy="0" r="0.03" fill="#202020"', Text);
end;

procedure TTestDraftSVG.TestNeverComputedFailureIsLeftOut;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100 / A.x', '0');
  FPattern.Evaluate;
  AssertLacks('no result to show', 'data-name="B"', Render);
  AssertHas('A is fine', 'data-name="A"', Render);
end;

procedure TTestDraftSVG.TestNotComputedIsLeftOut;
begin
  FPattern.AddFreePoint('A', '0', '0');
  AssertLacks('not evaluated yet', 'data-name="A"', Render);
end;

procedure TTestDraftSVG.TestEmptyPattern;
var
  Text: string;
begin
  Text := Render;
  AssertHas('still an SVG', '<svg', Text);
  AssertHas('closed', '</svg>', Text);
end;

procedure TTestDraftSVG.TestSizesFollowTheDrawing;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '1000', '0');
  FPattern.Evaluate;
  // A point is 0.3% of the longer side
  AssertHas('radius', 'r="3"', Render);
end;

procedure TTestDraftSVG.TestPieceIsDrawnUnderItsEdges;
var
  A, B, C: string;
  Path: TPiecePath;
  Text, ErrorMessage: string;
begin
  A := FPattern.AddFreePoint('P', '0', '0').Key;
  B := FPattern.AddFreePoint('Q', '100', '0').Key;
  C := FPattern.AddFreePoint('R', '0', '100').Key;
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(ErrorMessage, DetectPiecePath(FPattern, Vec2(10, 10), Path, ErrorMessage));
  FPattern.AddPiece('Front', Path, '10');
  FPattern.Evaluate;
  Text := Render;
  AssertHas('the piece', 'data-name="Front"', Text);
  AssertTrue('under the edges', Pos('data-name="Front"', Text) < Pos('data-name="Line_P_Q"', Text));
  AssertTrue('grainline over the edges', Pos('data-name="Line_P_Q"', Text) < Pos('data-marks="Front"', Text));
  AssertHas('its label', 'Front, cut 1', Render(True));
end;

procedure TTestDraftSVG.BuildPiece;
var
  A, B, C: string;
  Path: TPiecePath;
  ErrorMessage: string;
begin
  A := FPattern.AddFreePoint('P', '0', '0').Key;
  B := FPattern.AddFreePoint('Q', '100', '0').Key;
  C := FPattern.AddFreePoint('R', '0', '100').Key;
  FPattern.AddLine(A, B, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(ErrorMessage, DetectPiecePath(FPattern, Vec2(10, 10), Path, ErrorMessage));
  FPattern.AddPiece('Front', Path, '10');
  FPattern.Evaluate;
end;

procedure TTestDraftSVG.TestNoFillsLeavesPieceUnfilled;
var
  Options: TDraftSVGOptions;
begin
  BuildPiece;
  Options := DefaultDraftSVGOptions;
  AssertLacks('tinted to begin with', 'data-name="Front" d="M 0 0 Z" fill="none"', DraftToSVG(FPattern, Options));
  Options.NoFills := True;
  AssertTrue('no fill', Pos('Z" fill="none"', DraftToSVG(FPattern, Options)) > 0);
end;

procedure TTestDraftSVG.TestNoFillsLeavesOutHatching;
var
  Options: TDraftSVGOptions;
begin
  BuildPiece;
  FPattern.SetFabricFill(FPattern.Fabrics[0], ffHatch);
  Options := DefaultDraftSVGOptions;
  AssertHas('hatched', 'data-hatch', DraftToSVG(FPattern, Options));
  Options.NoFills := True;
  AssertLacks('not when fills are off', 'data-hatch', DraftToSVG(FPattern, Options));
end;

initialization
  RegisterTest(TTestDraftSVG);

end.
