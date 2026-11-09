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

// Edits to the canvas selection: which selections each accepts, that each is
// one undo step, and what it selects and says afterwards
unit Sloper.Tests.SelectionEdits;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece,
  Sloper.Core.Pattern, Sloper.Core.Fragment, Sloper.Document.PatternDocument, Sloper.UI.SelectionEdits;

type
  TTestSelectionEdits = class(TOSTestCase)
  private
    FDocument: TPatternDocument;
    // A 100 mm square piece, corners A (0, 0), B, C and D, outline edges
    // AB, BC, CD and DA; E a free point inside it
    FA, FB, FC, FD, FE, FAB, FBC, FCD, FDA, FPiece: string;
    function Pattern: TPattern;
    function PointX(const Key: string): double;
    function Edge(const Key: string): TEdgeObject;
    function Piece: TPieceObject;
    // The edit was refused with Message, changing nothing and leaving no change open
    procedure AssertRefused(const Msg: string; const Edit: TSelectionEdit; const Message: string);
    // The edit was made as one undo step named Description
    procedure AssertOneStep(const Msg: string; const Edit: TSelectionEdit; const Description: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNudgeMovesPointsAndKeepsSelection;
    procedure TestNudgesMerge;
    procedure TestNudgeIgnoresEdges;
    procedure TestNudgeRefusedPointSaysWhy;
    procedure TestDeleteClearsSelection;
    procedure TestDeleteRefusedWhenUsed;
    procedure TestDeleteNothingSelected;
    procedure TestCopyLeavesOutPiece;
    procedure TestCopyNothingCopyable;
    procedure TestCopyNothingSelected;
    procedure TestCutRefusedWhenSomethingLeftOut;
    procedure TestCutCopiesAndDeletes;
    procedure TestPasteSelectsCopies;
    procedure TestSplitSelectsParts;
    procedure TestSplitNeedsEdgeAndPoint;
    procedure TestArcAboutPoint;
    procedure TestArcNeedsOnePoint;
    procedure TestOffsetEdge;
    procedure TestOffsetNeedsOnlyEdges;
    procedure TestOffsetInsidePieceIsStitch;
    procedure TestOffsetInPieceNeedsPiece;
    procedure TestConvertKeepsSelection;
    procedure TestConvertNeedsEdges;
    procedure TestMergeSelectsKept;
    procedure TestBreakNeedsOnePoint;
    procedure TestRoundCorner;
    procedure TestRoundCornerRefusedSaysWhy;
    procedure TestRoundCornerOfPieceIsOneStep;
    procedure TestRoundCornerNeedsTwoEdges;
    procedure TestMarkPoint;
    procedure TestMarkNeedsPieceAndTarget;
    procedure TestMarkHoles;
    procedure TestMarkHolesNeedsPoints;
    procedure TestUnmark;
    procedure TestUnmarkNothingMarked;
    procedure TestTransformSelectsIt;
    procedure TestObjectNames;
  end;

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.PieceDetect, Sloper.Core.Transform;

procedure TTestSelectionEdits.SetUp;
var
  Path: TPiecePath;
  ErrorMessage: string;
begin
  FDocument := TPatternDocument.Create;
  FA := Pattern.AddFreePoint('A', '0', '0').Key;
  FB := Pattern.AddFreePoint('B', '100', '0').Key;
  FC := Pattern.AddFreePoint('C', '100', '100').Key;
  FD := Pattern.AddFreePoint('D', '0', '100').Key;
  FE := Pattern.AddFreePoint('E', '50', '50').Key;
  FAB := Pattern.AddLine(FA, FB, erOutline).Key;
  FBC := Pattern.AddLine(FB, FC, erOutline).Key;
  FCD := Pattern.AddLine(FC, FD, erOutline).Key;
  FDA := Pattern.AddLine(FD, FA, erOutline).Key;
  Pattern.Evaluate;
  AssertTrue(ErrorMessage, DetectPiecePath(Pattern, Vec2(50, 50), Path, ErrorMessage));
  FPiece := Pattern.AddPiece('Front', Path, '10').Key;
  Pattern.Evaluate;
end;

procedure TTestSelectionEdits.TearDown;
begin
  FreeAndNil(FDocument);
end;

function TTestSelectionEdits.Pattern: TPattern;
begin
  Result := FDocument.Pattern;
end;

function TTestSelectionEdits.PointX(const Key: string): double;
begin
  Result := TPointObject(Pattern.FindNode(Key)).Position.X;
end;

function TTestSelectionEdits.Edge(const Key: string): TEdgeObject;
begin
  Result := Pattern.FindNode(Key) as TEdgeObject;
end;

function TTestSelectionEdits.Piece: TPieceObject;
begin
  Result := Pattern.FindNode(FPiece) as TPieceObject;
end;

procedure TTestSelectionEdits.AssertRefused(const Msg: string; const Edit: TSelectionEdit; const Message: string);
begin
  AssertFalse(Msg + ': not done', Edit.Done);
  AssertFalse(Msg + ': selection stays', Edit.Reselect);
  AssertEquals(Msg + ': message', Message, Edit.Message);
  AssertFalse(Msg + ': no change left open', FDocument.ChangeOpen);
  AssertFalse(Msg + ': nothing to undo', FDocument.CanUndo);
end;

procedure TTestSelectionEdits.AssertOneStep(const Msg: string; const Edit: TSelectionEdit; const Description: string);
begin
  AssertTrue(Msg + ': done, else ' + Edit.Message, Edit.Done);
  AssertFalse(Msg + ': no change left open', FDocument.ChangeOpen);
  AssertEquals(Msg + ': undo step', Description, FDocument.UndoDescription);
  AssertTrue(Msg + ': undo', FDocument.Undo);
  AssertFalse(Msg + ': one step', FDocument.CanUndo);
  AssertTrue(Msg + ': redo', FDocument.Redo);
end;

procedure TTestSelectionEdits.TestNudgeMovesPointsAndKeepsSelection;
var
  Edit: TSelectionEdit;
begin
  Edit := NudgeSelection(FDocument, [FA, FB], Vec2(1, 0));
  AssertNear('A moved', 1, PointX(FA));
  AssertNear('B moved', 101, PointX(FB));
  AssertFalse('selection stays', Edit.Reselect);
  AssertEquals('', Edit.Message);
  AssertOneStep('nudge', Edit, rsSelectionNudge);
end;

procedure TTestSelectionEdits.TestNudgesMerge;
begin
  NudgeSelection(FDocument, [FA], Vec2(1, 0));
  NudgeSelection(FDocument, [FA], Vec2(1, 0));
  AssertNear('moved twice', 2, PointX(FA));
  AssertTrue(FDocument.Undo);
  AssertFalse('a run of nudges is one step', FDocument.CanUndo);
  AssertNear('back at the start', 0, PointX(FA));
end;

procedure TTestSelectionEdits.TestNudgeIgnoresEdges;
begin
  AssertRefused('only an edge', NudgeSelection(FDocument, [FAB], Vec2(1, 0)), '');
  AssertRefused('nothing', NudgeSelection(FDocument, [], Vec2(1, 0)), '');
end;

procedure TTestSelectionEdits.TestNudgeRefusedPointSaysWhy;
var
  Mid: string;
  Edit: TSelectionEdit;
begin
  // Placed by a formula, so it cannot be dragged
  Mid := Pattern.AddAlongEdgePoint('M', FAB, False, amRatio, '0.25 + 0.25').Key;
  Pattern.Evaluate;
  Edit := NudgeSelection(FDocument, [FA, Mid], Vec2(1, 0));
  AssertFalse(Edit.Done);
  AssertTrue('says why', Edit.Message <> '');
  AssertNear('A put back', 0, PointX(FA));
  AssertFalse(FDocument.ChangeOpen);
  AssertFalse(FDocument.CanUndo);
end;

procedure TTestSelectionEdits.TestDeleteClearsSelection;
var
  Edit: TSelectionEdit;
begin
  Edit := DeleteSelection(FDocument, [FE], rsSelectionDelete);
  AssertNull('deleted', Pattern.FindNode(FE));
  AssertTrue(Edit.Reselect);
  AssertEquals('nothing selected', 0, Length(Edit.Selection));
  AssertOneStep('delete', Edit, rsSelectionDelete);
end;

procedure TTestSelectionEdits.TestDeleteRefusedWhenUsed;
var
  Edit: TSelectionEdit;
begin
  Edit := DeleteSelection(FDocument, [FE, FA], rsSelectionDelete);
  AssertFalse(Edit.Done);
  AssertTrue('says why', Edit.Message <> '');
  AssertNotNull('E put back', Pattern.FindNode(FE));
  AssertFalse(FDocument.ChangeOpen);
  AssertFalse(FDocument.CanUndo);
end;

procedure TTestSelectionEdits.TestDeleteNothingSelected;
begin
  AssertRefused('nothing', DeleteSelection(FDocument, [], rsSelectionDelete), '');
end;

procedure TTestSelectionEdits.TestCopyLeavesOutPiece;
var
  Copied: TFragmentCopy;
  Edit: TSelectionEdit;
begin
  Edit := CopySelection(FDocument, [FE, FPiece], Copied);
  AssertTrue(Edit.Done);
  AssertTrue(Copied.Text <> '');
  AssertEquals(Format(rsSelectionCopiedLeftOut, ['E', 'Front']), Edit.Message);
  AssertFalse('a copy changes nothing', FDocument.CanUndo);
end;

procedure TTestSelectionEdits.TestCopyNothingCopyable;
var
  Copied: TFragmentCopy;
begin
  AssertRefused('piece only', CopySelection(FDocument, [FPiece], Copied), Format(rsSelectionCannotCopy, ['Front']));
  AssertEquals('', Copied.Text);
end;

procedure TTestSelectionEdits.TestCopyNothingSelected;
var
  Copied: TFragmentCopy;
begin
  AssertRefused('nothing', CopySelection(FDocument, [], Copied), rsSelectionPickToCopy);
end;

procedure TTestSelectionEdits.TestCutRefusedWhenSomethingLeftOut;
var
  Copied: TFragmentCopy;
begin
  AssertRefused('with piece', CutSelection(FDocument, [FE, FPiece], Copied), Format(rsSelectionCannotCut, ['Front']));
  AssertEquals('nothing to paste', '', Copied.Text);
  AssertNotNull('E kept', Pattern.FindNode(FE));
end;

procedure TTestSelectionEdits.TestCutCopiesAndDeletes;
var
  Copied: TFragmentCopy;
  Edit: TSelectionEdit;
begin
  Edit := CutSelection(FDocument, [FE], Copied);
  AssertTrue(Copied.Text <> '');
  AssertNull('deleted', Pattern.FindNode(FE));
  AssertEquals(Format(rsSelectionCutDone, ['E']), Edit.Message);
  AssertOneStep('cut', Edit, rsSelectionCut);
end;

procedure TTestSelectionEdits.TestPasteSelectsCopies;
var
  Copied: TFragmentCopy;
  Edit: TSelectionEdit;
begin
  CopySelection(FDocument, [FE], Copied);
  Edit := PasteFragmentText(FDocument, Copied.Text);
  AssertTrue(Edit.Reselect);
  AssertEquals(1, Length(Edit.Selection));
  AssertTrue('a new copy', Edit.Selection[0] <> FE);
  AssertEquals(Format(rsSelectionPastedRenamed, ['E2', 'E → E2']), Edit.Message);
  AssertOneStep('paste', Edit, rsSelectionPaste);
end;

procedure TTestSelectionEdits.TestSplitSelectsParts;
var
  Mid: string;
  Edit: TSelectionEdit;
begin
  Mid := Pattern.AddAlongEdgePoint('M', FAB, False, amRatio, '0.5').Key;
  Pattern.Evaluate;
  Edit := SplitSelection(FDocument, [FAB, Mid]);
  AssertTrue(Edit.Message, Edit.Done);
  AssertEquals('both parts selected', 2, Length(Edit.Selection));
  AssertTrue(Pattern.FindNode(Edit.Selection[0]) is TSplitPart);
  AssertOneStep('split', Edit, rsSelectionSplit);
end;

procedure TTestSelectionEdits.TestSplitNeedsEdgeAndPoint;
var
  Edit: TSelectionEdit;
begin
  Edit := SplitSelection(FDocument, [FE]);
  AssertFalse(Edit.Done);
  AssertTrue('says why', Edit.Message <> '');
  AssertFalse(FDocument.CanUndo);
end;

procedure TTestSelectionEdits.TestArcAboutPoint;
var
  Edit: TSelectionEdit;
begin
  Edit := AddArcAtSelection(FDocument, [FE], erStitch);
  AssertTrue(Edit.Message, Edit.Done);
  AssertTrue(Pattern.FindNode(Edit.Selection[0]) is TArcObject);
  AssertTrue('takes the drawing role', Edge(Edit.Selection[0]).Role = erStitch);
  AssertOneStep('arc', Edit, rsSelectionAddArc);
end;

procedure TTestSelectionEdits.TestArcNeedsOnePoint;
begin
  AssertRefused('two points', AddArcAtSelection(FDocument, [FA, FB], erConstruction), rsSelectionPickCentre);
  AssertRefused('an edge', AddArcAtSelection(FDocument, [FAB], erConstruction), rsSelectionPickCentre);
end;

procedure TTestSelectionEdits.TestOffsetEdge;
var
  Edit: TSelectionEdit;
begin
  Edit := OffsetSelection(FDocument, [FAB], osLeft);
  AssertTrue(Edit.Message, Edit.Done);
  AssertTrue(Pattern.FindNode(Edit.Selection[0]) is TOffsetEdge);
  AssertTrue(Edge(Edit.Selection[0]).Role = erConstruction);
  AssertOneStep('offset', Edit, rsSelectionAddOffset);
end;

procedure TTestSelectionEdits.TestOffsetNeedsOnlyEdges;
begin
  AssertRefused('edge and point', OffsetSelection(FDocument, [FAB, FE], osLeft), rsSelectionPickEdgeToOffset);
  AssertRefused('nothing', OffsetSelection(FDocument, [], osLeft), rsSelectionPickEdgeToOffset);
end;

procedure TTestSelectionEdits.TestOffsetInsidePieceIsStitch;
var
  Edit: TSelectionEdit;
begin
  Edit := OffsetSelectionInPiece(FDocument, [FPiece, FAB], True);
  AssertTrue(Edit.Message, Edit.Done);
  AssertTrue(Edge(Edit.Selection[0]).Role = erStitch);
  AssertOneStep('offset inside', Edit, rsSelectionAddOffset);
end;

procedure TTestSelectionEdits.TestOffsetInPieceNeedsPiece;
begin
  AssertRefused('no piece', OffsetSelectionInPiece(FDocument, [FAB], True), rsSelectionPickPieceEdges);
  AssertRefused('a point too', OffsetSelectionInPiece(FDocument, [FPiece, FAB, FE], True), rsSelectionPickPieceEdges);
end;

procedure TTestSelectionEdits.TestConvertKeepsSelection;
var
  Edit: TSelectionEdit;
begin
  Edit := ConvertSelection(FDocument, [FAB, FE], True);
  AssertTrue(Edit.Message, Edit.Done);
  AssertFalse('selection stays', Edit.Reselect);
  AssertTrue('same ID, now a curve', Pattern.FindNode(FAB) is TCurveObject);
  AssertOneStep('convert', Edit, rsSelectionConvertToCurve);
end;

procedure TTestSelectionEdits.TestConvertNeedsEdges;
begin
  AssertRefused('a point', ConvertSelection(FDocument, [FE], False), rsSelectionPickEdgesToConvert);
end;

procedure TTestSelectionEdits.TestMergeSelectsKept;
var
  Other: string;
  Edit: TSelectionEdit;
begin
  Other := Pattern.AddFreePoint('F', '60', '50').Key;
  Pattern.Evaluate;
  Edit := MergeSelection(FDocument, [FE, Other, FAB]);
  AssertTrue(Edit.Message, Edit.Done);
  AssertEquals(1, Length(Edit.Selection));
  AssertEquals('edges are not merged', Format(rsSelectionMerged, [2, 'E']), Edit.Message);
  AssertOneStep('merge', Edit, rsSelectionMergePoints);
end;

procedure TTestSelectionEdits.TestBreakNeedsOnePoint;
begin
  AssertRefused('two points', BreakSelection(FDocument, [FA, FB]), rsSelectionPickPointToBreak);
  AssertRefused('an edge', BreakSelection(FDocument, [FAB]), rsSelectionPickPointToBreak);
end;

procedure TTestSelectionEdits.TestRoundCorner;
var
  Corner, First, Second: string;
  Edit: TSelectionEdit;
begin
  Corner := Pattern.AddFreePoint('H', '300', '0').Key;
  First := Pattern.AddLine(Pattern.AddFreePoint('G', '200', '0').Key, Corner).Key;
  Second := Pattern.AddLine(Corner, Pattern.AddFreePoint('I', '300', '100').Key).Key;
  Pattern.Evaluate;
  Edit := RoundSelectedCorner(FDocument, [First, Second]);
  AssertTrue(Edit.Message, Edit.Done);
  AssertTrue(Pattern.FindNode(Edit.Selection[0]) is TCornerArc);
  AssertOneStep('round', Edit, rsSelectionRoundCorner);
end;

// The pattern's own refusal comes back as the message
// A piece's fold has to stay one straight edge
procedure TTestSelectionEdits.TestRoundCornerRefusedSaysWhy;
var
  Edit: TSelectionEdit;
begin
  AssertTrue(Pattern.LastError, Pattern.SetFoldEdge(Piece, FBC));
  Edit := RoundSelectedCorner(FDocument, [FAB, FBC]);
  AssertFalse(Edit.Done);
  AssertTrue('names the piece', Pos('Front', Edit.Message) > 0);
  AssertFalse(FDocument.ChangeOpen);
  AssertFalse(FDocument.CanUndo);
end;

// Rounding a piece's corner rounds the piece, in one step that undoes whole
procedure TTestSelectionEdits.TestRoundCornerOfPieceIsOneStep;
var
  Edit: TSelectionEdit;
begin
  Edit := RoundSelectedCorner(FDocument, [FAB, FBC]);
  AssertTrue(Edit.Message, Edit.Done);
  Pattern.Evaluate;
  AssertEquals('four lines and the arc', 5, Length(Piece.Path));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertTrue(FDocument.CanUndo);
  FDocument.Undo;
  Pattern.Evaluate;
  AssertEquals('back to the sharp corner', 4, Length(Piece.Path));
  AssertEquals(10000, Piece.Area, 1e-6);
end;

procedure TTestSelectionEdits.TestRoundCornerNeedsTwoEdges;
begin
  AssertRefused('one edge', RoundSelectedCorner(FDocument, [FAB]), rsSelectionPickCornerEdges);
  AssertRefused('edge and point', RoundSelectedCorner(FDocument, [FAB, FB]), rsSelectionPickCornerEdges);
end;

procedure TTestSelectionEdits.TestMarkPoint;
var
  Edit: TSelectionEdit;
begin
  // A marked point needs a marker
  AssertTrue(Pattern.SetMarker(FE, pmButton));
  Edit := MarkSelection(FDocument, [FPiece, FE], mkLine);
  AssertTrue(Edit.Message, Edit.Done);
  AssertFalse('selection stays', Edit.Reselect);
  AssertEquals(1, Length(Piece.Markings));
  AssertEquals(FE, Piece.Markings[0].PointKey);
  AssertOneStep('mark', Edit, rsSelectionAddMarking);
end;

procedure TTestSelectionEdits.TestMarkNeedsPieceAndTarget;
begin
  AssertRefused('no piece', MarkSelection(FDocument, [FE], mkLine), rsSelectionPickLine);
  AssertRefused('a point is no edge', MarkSelection(FDocument, [FPiece, FE], mkStitchHoles), rsSelectionPickMarkingEdge);
  AssertRefused('three objects', MarkSelection(FDocument, [FPiece, FAB, FE], mkStitchHoles), rsSelectionPickMarkingEdge);
end;

procedure TTestSelectionEdits.TestMarkHoles;
var
  Edit: TSelectionEdit;
begin
  Edit := MarkSelection(FDocument, [FE, FAB], mkPoint);
  AssertTrue(Edit.Message, Edit.Done);
  AssertTrue(TPointObject(Pattern.FindNode(FE)).Marker = pmHole);
  AssertOneStep('holes', Edit, rsSelectionAddMarking);
end;

procedure TTestSelectionEdits.TestMarkHolesNeedsPoints;
begin
  AssertRefused('an edge', MarkSelection(FDocument, [FAB], mkPoint), rsSelectionPickHole);
  MarkSelection(FDocument, [FE], mkPoint);
  AssertEquals('already a hole', rsSelectionPickHole, MarkSelection(FDocument, [FE], mkPoint).Message);
end;

procedure TTestSelectionEdits.TestUnmark;
var
  Edit: TSelectionEdit;
begin
  AssertTrue(Pattern.SetMarker(FE, pmButton));
  AssertTrue(MarkSelection(FDocument, [FPiece, FE], mkLine).Done);
  Edit := UnmarkSelection(FDocument, [FE, FPiece]);
  AssertTrue(Edit.Done);
  AssertEquals(0, Length(Piece.Markings));
  AssertEquals(rsSelectionRemoveMarking, FDocument.UndoDescription);
end;

procedure TTestSelectionEdits.TestUnmarkNothingMarked;
begin
  AssertRefused('not marked', UnmarkSelection(FDocument, [FPiece, FE]), rsSelectionPickMarkingToRemove);
  AssertRefused('no piece', UnmarkSelection(FDocument, [FE]), rsSelectionPickMarkingToRemove);
end;

procedure TTestSelectionEdits.TestTransformSelectsIt;
var
  Spec: TTransformSpec;
  Edit: TSelectionEdit;
begin
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Name := 'Back';
  Spec.Sources := [FE];
  Spec.DX := '10';
  Spec.DY := '0';
  Edit := AddTransform(FDocument, Spec);
  AssertTrue(Edit.Message, Edit.Done);
  AssertEquals(1, Length(Edit.Selection));
  AssertOneStep('transform', Edit, Format(rsSelectionTransform, ['Back']));
end;

procedure TTestSelectionEdits.TestObjectNames;
begin
  AssertEquals('A, B, Front', ObjectNames(Pattern, [FA, FB, 'missing', FPiece]));
end;

initialization
  RegisterTest(TTestSelectionEdits);

end.
