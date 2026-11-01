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

// Seams: side lengths, ease and tolerance, direction, files and problems.
unit Sloper.Tests.Seam;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Seam, Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.Core.SeamSuggest;

type
  TTestSeam = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    // Outline rectangle at (Left, 0), clockwise as a piece. Edges of its top
    // (Width) and right side (Height) are kept for the tests.
    function Panel(const AName: string; Left, Width, Height: double; out Top, Right: string): TPieceObject;
    function Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
    function Saved: string;
    procedure AssertNoLeftover;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSideLengths;
    procedure TestSideSpansPieces;
    procedure TestSamePieceBothSides;
    procedure TestSameEdgeInTwoSeams;
    procedure TestEaseFormulaFollowsVariable;
    procedure TestToleranceLimits;
    procedure TestNegativeToleranceIsInvalid;
    procedure TestDefaultNames;
    procedure TestRefusesEmptySide;
    procedure TestRefusesEdgeOffPiece;
    procedure TestRefusesRepeatInSide;
    procedure TestRefusesFoldEdge;
    procedure TestFoldSetLaterMakesSeamInvalid;
    procedure TestBlockedByInvalidPiece;
    procedure TestPieceInUseCannotBeDeleted;
    procedure TestDeletingSeamFreesPiece;
    procedure TestDefaultDirectionOpposesPaths;
    procedure TestFlipReversesSideB;
    procedure TestPieceMovingKeepsSeamAfterIt;
    procedure TestRoundTrip;
    procedure TestLoadRefusesEdgeOffPiece;
    procedure TestMismatchIsProblemNotState;
    procedure TestReportHasLengths;
    procedure TestSuggestSharedEdgeFirst;
    procedure TestSuggestCloseLengths;
    procedure TestSuggestLeavesOutUsedAndFold;
    procedure TestSuggestStoresNothing;
  end;

implementation

function TTestSeam.Panel(const AName: string; Left, Width, Height: double; out Top, Right: string): TPieceObject;
var
  A, B, C, D, Reason: string;
  Path: TPiecePath;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(X), FloatToStr(Y)).Key;
  end;

begin
  A := Pt(Left, 0);
  B := Pt(Left + Width, 0);
  C := Pt(Left + Width, Height);
  D := Pt(Left, Height);
  Top := FPattern.AddLine(A, B, erOutline).Key;
  Right := FPattern.AddLine(B, C, erOutline).Key;
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Width / 2, Height / 2), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestSeam.Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].PieceKey := Piece.Key;
  Result[0].EdgeKey := EdgeKey;
end;

function TTestSeam.Saved: string;
begin
  Result := SavePatternToText(FPattern);
end;

procedure TTestSeam.AssertNoLeftover;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
end;

procedure TTestSeam.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestSeam.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

procedure TTestSeam.TestSideLengths;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  Seam := FPattern.AddSeam('', Side(Front, TopF), Side(Back, TopB));
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertEquals('A', 100, Seam.LengthA, 0.001);
  AssertEquals('B', 120, Seam.LengthB, 0.001);
  AssertEquals('difference', 20, Seam.Difference, 0.001);
end;

// A waistband's edge against the waists of a front and a back
procedure TTestSeam.TestSideSpansPieces;
var
  Front, Back, Band: TPieceObject;
  TopF, RightF, TopB, RightB, TopBand, RightBand: string;
  Waist: TSeamSide;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  Band := Panel('Band', 600, 220, 30, TopBand, RightBand);
  Waist := Concat(Side(Front, TopF), Side(Back, TopB));
  Seam := FPattern.AddSeam('Waist', Waist, Side(Band, TopBand));
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  AssertEquals('both waists', 220, Seam.LengthA, 0.001);
  AssertFalse('within tolerance', Seam.OutOfTolerance);
  AssertEquals('each piece once', 3, Length(Seam.InputKeys));
end;

// A sleeve's underarm, say: both sides on one piece
procedure TTestSeam.TestSamePieceBothSides;
var
  Sleeve: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
begin
  Sleeve := Panel('Sleeve', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Sleeve, Top), Side(Sleeve, Right));
  AssertNotNull(FPattern.LastError, Seam);
  AssertEquals('one input', 1, Length(Seam.InputKeys));
  FPattern.Evaluate;
  AssertEquals('difference', 100, Seam.Difference, 0.001);
end;

// A neckline can sew to a collar and a facing; a mirrored centre back to itself
procedure TTestSeam.TestSameEdgeInTwoSeams;
var
  Back, Collar: TPieceObject;
  Top, Right, TopC, RightC: string;
begin
  Back := Panel('Back', 0, 100, 200, Top, Right);
  Collar := Panel('Collar', 300, 100, 50, TopC, RightC);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Back, Top), Side(Collar, TopC)));
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Back, Top), Side(Back, Top)));
end;

procedure TTestSeam.TestEaseFormulaFollowsVariable;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  AssertNotNull(FPattern.LastError, FPattern.AddVariable('gather', '20'));
  Seam := FPattern.AddSeam('', Side(Front, TopF), Side(Back, TopB), '#gather');
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  AssertEquals('ease', 20, Seam.Ease, 0.001);
  AssertFalse('as expected', Seam.OutOfTolerance);
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindVariable('gather'), 'formula', '5'));
  FPattern.Evaluate;
  AssertTrue('now too long', Seam.OutOfTolerance);
  AssertEquals('mismatch', 15, Seam.Mismatch, 0.001);
end;

// A cap with ease 25 and tolerance 2 passes at 23 to 27 mm over
procedure TTestSeam.TestToleranceLimits;
var
  First, Second, Third, Fourth: TPieceObject;
  Key: array[1..8] of string;

  function OutFor(Piece: TPieceObject; const EdgeKey: string): boolean;
  var
    Seam: TSeamObject;
  begin
    Seam := FPattern.AddSeam('', Side(First, Key[1]), Side(Piece, EdgeKey), '25', '2');
    AssertNotNull(FPattern.LastError, Seam);
    FPattern.Evaluate;
    Result := Seam.OutOfTolerance;
  end;

begin
  First := Panel('Armhole', 0, 100, 50, Key[1], Key[2]);
  Second := Panel('Low', 200, 123, 50, Key[3], Key[4]);
  Third := Panel('High', 400, 127, 50, Key[5], Key[6]);
  Fourth := Panel('Past', 600, 127.5, 50, Key[7], Key[8]);
  AssertFalse('lower limit', OutFor(Second, Key[3]));
  AssertFalse('upper limit', OutFor(Third, Key[5]));
  AssertTrue('past it', OutFor(Fourth, Key[7]));
end;

procedure TTestSeam.TestNegativeToleranceIsInvalid;
var
  Front: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Front, Top), Side(Front, Right), '0', '-1');
  AssertNotNull(FPattern.LastError, Seam);
  FPattern.Evaluate;
  AssertTrue('invalid', Seam.State = esInvalid);
  AssertEquals(rsSeamNegativeTolerance, Seam.Message);
end;

procedure TTestSeam.TestDefaultNames;
var
  Front: TPieceObject;
  Top, Right: string;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertEquals('Seam', FPattern.AddSeam('', Side(Front, Top), Side(Front, Right)).Name);
  AssertEquals('Seam2', FPattern.AddSeam('', Side(Front, Top), Side(Front, Right)).Name);
  AssertEquals('Shoulder', FPattern.AddSeam('Shoulder', Side(Front, Top), Side(Front, Right)).Name);
end;

procedure TTestSeam.TestRefusesEmptySide;
var
  Front: TPieceObject;
  Top, Right: string;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertNull('refused', FPattern.AddSeam('', Side(Front, Top), nil));
  AssertEquals(rsPatternSeamEmptySide, FPattern.LastError);
end;

procedure TTestSeam.TestRefusesEdgeOffPiece;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  AssertNull('refused', FPattern.AddSeam('', Side(Front, TopB), Side(Back, TopB)));
  AssertEquals(Format(rsPatternNotInPiece, [FPattern.FindNode(TopB).DisplayName, 'Front']), FPattern.LastError);
end;

procedure TTestSeam.TestRefusesRepeatInSide;
var
  Front: TPieceObject;
  Top, Right: string;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertNull('refused', FPattern.AddSeam('', Concat(Side(Front, Top), Side(Front, Top)), Side(Front, Right)));
  AssertEquals(Format(rsPatternSeamRepeats, [FPattern.FindNode(Top).DisplayName, 'Front']), FPattern.LastError);
end;

procedure TTestSeam.TestRefusesFoldEdge;
var
  Front: TPieceObject;
  Top, Right: string;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, Top));
  AssertNull('refused', FPattern.AddSeam('', Side(Front, Top), Side(Front, Right)));
  AssertEquals(Format(rsSeamOnFold, [FPattern.FindNode(Top).DisplayName, 'Front']), FPattern.LastError);
end;

procedure TTestSeam.TestFoldSetLaterMakesSeamInvalid;
var
  Front: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Front, Top), Side(Front, Right));
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, Top));
  FPattern.Evaluate;
  AssertTrue('invalid', Seam.State = esInvalid);
  AssertEquals(Format(rsSeamOnFold, [FPattern.FindNode(Top).DisplayName, 'Front']), Seam.Message);
  // A file must still load, to be put right
  AssertNoLeftover;
end;

procedure TTestSeam.TestBlockedByInvalidPiece;
var
  Front: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Front, Top), Side(Front, Right));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Front, PieceAllowanceField, '-1'));
  FPattern.Evaluate;
  AssertTrue('blocked', Seam.State = esBlocked);
end;

procedure TTestSeam.TestPieceInUseCannotBeDeleted;
var
  Front: TPieceObject;
  Top, Right: string;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, Top), Side(Front, Right)));
  AssertFalse('refused', FPattern.Delete(Front));
  AssertEquals(Format(rsPatternInUse, ['Front', 'Seam']), FPattern.LastError);
end;

procedure TTestSeam.TestDeletingSeamFreesPiece;
var
  Front: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Front, Top), Side(Front, Right));
  AssertTrue(FPattern.LastError, FPattern.Delete(Seam));
  AssertTrue(FPattern.LastError, FPattern.Delete(Front));
end;

// Two clockwise pieces sharing an edge run it in opposite directions, so a
// seam on it runs the same way along the edge on both sides
procedure TTestSeam.TestDefaultDirectionOpposesPaths;
var
  Left, Right: TPieceObject;
  Shared: string;
  A, B, C, D, E, F, Reason: string;
  Path: TPiecePath;
  Seam: TSeamObject;
begin
  A := FPattern.AddFreePoint('', '0', '0').Key;
  B := FPattern.AddFreePoint('', '100', '0').Key;
  C := FPattern.AddFreePoint('', '200', '0').Key;
  D := FPattern.AddFreePoint('', '200', '100').Key;
  E := FPattern.AddFreePoint('', '100', '100').Key;
  F := FPattern.AddFreePoint('', '0', '100').Key;
  FPattern.AddLine(A, B, erOutline);
  Shared := FPattern.AddLine(B, E, erOutline).Key;
  FPattern.AddLine(E, F, erOutline);
  FPattern.AddLine(F, A, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, E, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  Left := FPattern.AddPiece('Left', Path, '10');
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(150, 50), Path, Reason));
  Right := FPattern.AddPiece('Right', Path, '10');
  Seam := FPattern.AddSeam('', Side(Left, Shared), Side(Right, Shared));
  AssertEquals('same way along the edge', Seam.RunsForward(Left, Seam.SideA[0], False), Seam.RunsForward(Right, Seam.SideB[0], True));
end;

procedure TTestSeam.TestFlipReversesSideB;
var
  Front: TPieceObject;
  Top, Right: string;
  Seam: TSeamObject;
  Before: boolean;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  Seam := FPattern.AddSeam('', Side(Front, Top), Side(Front, Right));
  Before := Seam.RunsForward(Front, Seam.SideB[0], True);
  Seam.Reversed := True;
  AssertTrue('side B flips', Before <> Seam.RunsForward(Front, Seam.SideB[0], True));
  AssertEquals('side A stays', Seam.RunsForward(Front, Seam.SideA[0], False), not Front.Path[Front.PathIndexOf(Top)].Reversed);
end;

// A piece that takes on a newer point moves to the end of the list, and the
// file must still list it before its seam
procedure TTestSeam.TestPieceMovingKeepsSeamAfterIt;
var
  Front: TPieceObject;
  Top, Right, Err: string;
  Corner: TFreePoint;
begin
  Front := Panel('Front', 0, 100, 200, Top, Right);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, Top), Side(Front, Right)));
  Corner := FPattern.AddFreePoint('Grain', '10', '10');
  AssertTrue(FPattern.LastError, FPattern.SetGrainPoints(Front, Corner.Key, FPattern.AddFreePoint('Grain2', '10', '100').Key));
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
end;

procedure TTestSeam.TestRoundTrip;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB, Err: string;
  Seam: TSeamObject;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  Seam := FPattern.AddSeam('Waist', Concat(Side(Front, TopF), Side(Front, RightF)), Side(Back, TopB), '20', '2');
  Seam.Reversed := True;
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  AssertEquals('saves the same', Saved, SavePatternToText(FLoaded));
  Seam := TSeamObject(FLoaded.FindObject('Waist'));
  AssertEquals('entries', 2, Length(Seam.SideA));
  AssertTrue('reversed', Seam.Reversed);
end;

procedure TTestSeam.TestLoadRefusesEdgeOffPiece;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB, Text, Err: string;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  FPattern.AddSeam('', Side(Front, TopF), Side(Back, TopB));
  Text := Saved;
  // Side B's edge, the last in the file, becomes one the piece does not have
  Text := Copy(Text, 1, Pos('"sideB"', Text)) + StringReplace(Copy(Text, Pos('"sideB"', Text) + 1, MaxInt),
    '"edge": ' + TopB, '"edge": ' + TopF, []);
  AssertFalse('refused', LoadPatternFromText(FLoaded, Text, Err));
  AssertTrue(Err, Pos('is not part of', Err) > 0);
end;

procedure TTestSeam.TestMismatchIsProblemNotState;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  Seam: TSeamObject;
  Problems: TStringArray;
  BlockedCount: integer;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  Seam := FPattern.AddSeam('Side', Side(Front, TopF), Side(Back, TopB));
  FPattern.Evaluate;
  AssertTrue('stays valid', Seam.State = esValid);
  Problems := PatternProblems(FPattern, BlockedCount);
  AssertEquals('one problem', 1, Length(Problems));
  AssertEquals(Format(rsCheckSeam, ['Side', '100', '120', '20', '0']), Problems[0]);
  AssertTrue(FPattern.LastError, FPattern.SetFormula(Seam, SeamEaseField, '20'));
  FPattern.Evaluate;
  AssertEquals('none with ease', 0, Length(PatternProblems(FPattern, BlockedCount)));
end;

procedure TTestSeam.TestReportHasLengths;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  Report: TJSONObject;
  Item: TJSONObject;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 120, 200, TopB, RightB);
  FPattern.AddSeam('Side', Side(Front, TopF), Side(Back, TopB), '20', '2');
  FPattern.Evaluate;
  Report := PatternReport(FPattern, 'a', 'b');
  try
    Item := TJSONObject(Report.Arrays['objects'].Items[Report.Arrays['objects'].Count - 1]);
    AssertEquals('A', 100, Item.Floats['lengthA'], 0.001);
    AssertEquals('B', 120, Item.Floats['lengthB'], 0.001);
    AssertEquals('ease', 20, Item.Floats['ease'], 0.001);
    AssertEquals('tolerance', 2, Item.Floats['tolerance'], 0.001);
  finally
    FreeAndNil(Report);
  end;
end;

// Left and right panels around one shared edge; the outer sides are 100 too,
// so they are length suggestions behind it
procedure TTestSeam.TestSuggestSharedEdgeFirst;
var
  A, B, C, D, E, F, Shared, Reason: string;
  Path: TPiecePath;
  Suggestions: TSeamSuggestionArray;
begin
  A := FPattern.AddFreePoint('', '0', '0').Key;
  B := FPattern.AddFreePoint('', '100', '0').Key;
  C := FPattern.AddFreePoint('', '250', '0').Key;
  D := FPattern.AddFreePoint('', '250', '100').Key;
  E := FPattern.AddFreePoint('', '100', '100').Key;
  F := FPattern.AddFreePoint('', '0', '100').Key;
  FPattern.AddLine(A, B, erOutline);
  Shared := FPattern.AddLine(B, E, erOutline).Key;
  FPattern.AddLine(E, F, erOutline);
  FPattern.AddLine(F, A, erOutline);
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, E, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  FPattern.AddPiece('Left', Path, '10');
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(150, 50), Path, Reason));
  FPattern.AddPiece('Right', Path, '10');
  FPattern.Evaluate;
  Suggestions := SuggestSeams(FPattern);
  AssertTrue('some', Length(Suggestions) > 1);
  AssertTrue('shared first', Suggestions[0].Shared);
  AssertEquals('the edge', Shared, Suggestions[0].First.EdgeKey);
  AssertFalse('then lengths', Suggestions[1].Shared);
end;

procedure TTestSeam.TestSuggestCloseLengths;
var
  TopF, RightF, TopB, RightB: string;
  Suggestions: TSeamSuggestionArray;
begin
  Panel('Front', 0, 100, 200, TopF, RightF);
  Panel('Back', 300, 100.5, 250, TopB, RightB);
  FPattern.Evaluate;
  Suggestions := SuggestSeams(FPattern);
  // Top and bottom of each: four pairs within the limit, and no side pairs
  AssertEquals('pairs', 4, Length(Suggestions));
  AssertEquals('difference', 0.5, Suggestions[0].Difference, 0.001);
  AssertFalse('not shared', Suggestions[0].Shared);
end;

procedure TTestSeam.TestSuggestLeavesOutUsedAndFold;
var
  Front, Back: TPieceObject;
  TopF, RightF, TopB, RightB: string;
  Suggestions: TSeamSuggestionArray;
  Item: TSeamSuggestion;
begin
  Front := Panel('Front', 0, 100, 200, TopF, RightF);
  Back := Panel('Back', 300, 100, 200, TopB, RightB);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', Side(Front, TopF), Side(Back, TopB)));
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Back, RightB));
  FPattern.Evaluate;
  Suggestions := SuggestSeams(FPattern);
  AssertTrue('others remain', Length(Suggestions) > 0);
  for Item in Suggestions do
  begin
    AssertTrue('used edge', (Item.First.EdgeKey <> TopF) and (Item.Second.EdgeKey <> TopB));
    AssertTrue('fold edge', Item.Second.EdgeKey <> RightB);
  end;
end;

procedure TTestSeam.TestSuggestStoresNothing;
var
  TopF, RightF, TopB, RightB: string;
  Before: integer;
begin
  Panel('Front', 0, 100, 200, TopF, RightF);
  Panel('Back', 300, 100, 200, TopB, RightB);
  FPattern.Evaluate;
  Before := FPattern.ObjectCount;
  AssertTrue('suggested', Length(SuggestSeams(FPattern)) > 0);
  AssertEquals('nothing added', Before, FPattern.ObjectCount);
end;

initialization
  RegisterTest(TTestSeam);

end.
