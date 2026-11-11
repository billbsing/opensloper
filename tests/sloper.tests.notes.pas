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

// Notes (annotations stage 1): anchoring, following the draft, blocking,
// refusing to delete an anchor, dragging, files, the view's hide flag, which
// pieces a note prints with, and problems.
unit Sloper.Tests.Notes;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Note;

type
  TTestNotes = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X, Y: double): TPointObject;
    // An outline square from (Left, 0), Size across, as a piece
    function Square(const AName: string; Left, Size: double; out TopEdge: string): TPieceObject;
    function Saved: string;
    function Reloaded: TPattern;
    function Problems: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPointAnchorFollows;
    procedure TestEdgeAnchorRatio;
    procedure TestEdgeRatioOutOfRangeIsInvalid;
    procedure TestPieceAnchorIsMiddle;
    procedure TestFreeNote;
    procedure TestFailingAnchorBlocks;
    procedure TestDeletingAnchorRefused;
    procedure TestMakeFreeKeepsPlace;
    procedure TestDefaultNames;
    procedure TestRefusesWrongAnchorKind;
    procedure TestSizeLimits;
    procedure TestMergeMovesAnchor;
    procedure TestDragPlainOffset;
    procedure TestDragRefusesFormula;
    procedure TestDragFreeNote;
    procedure TestRoundTrip;
    procedure TestLoadRefusesBadAnchor;
    procedure TestHideAnnotationsSaved;
    procedure TestHideAnnotationsKeptOutOfUndo;
    procedure TestNotePieces;
    procedure TestCalloutGoesWithItsTip;
    procedure TestPieceNotesOnlyPrinting;
    procedure TestPieceMovingKeepsNoteAfterIt;
    procedure TestProblems;
    procedure TestFieldValues;
    procedure TestBoundsIncludeNotes;
    procedure TestTextToolAnchors;
    procedure TestNotesAtTopmostAndHidden;
    procedure TestObjectRows;
    procedure TestDraftSVG;
    // Stage 2
    procedure TestSplitDraftValues;
    procedure TestDraftValueFollowsDraft;
    procedure TestDraftValueTextIsShort;
    procedure TestDraftValueStoredById;
    procedure TestDraftValueIsAnInput;
    procedure TestDraftValueRefused;
    procedure TestDraftValueFailingBlocks;
    procedure TestDraftValueVariable;
    procedure TestDraftValueRoundTrip;
    procedure TestCalloutNeedsAnchor;
    procedure TestLookRoundTrip;
    procedure TestSetNoteAnchorKeepsText;
    procedure TestLeaderGeometry;
    procedure TestAlignedLeft;
    procedure TestCalloutFromSnap;
    procedure TestReanchorFromSnap;
    procedure TestCalloutTipAt;
    procedure TestCalloutCaptions;
    procedure TestDraftSVGCallout;
  end;

implementation

uses
  Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.Core.PieceDetect, Sloper.Core.Drag, Sloper.Core.Bounds, Sloper.Core.TextFields,
  Sloper.Core.Measurements, Sloper.Core.Settings, Sloper.Document.PatternDocument, Sloper.UI.Snap, Sloper.UI.Scene, Sloper.UI.ObjectList, Sloper.Output.DraftSVG;

const
  ANCHOR_PATTERN_HEAD = '{"format": "pattern", "version": 1, "objects": [{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}, ';

procedure TTestNotes.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestNotes.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

function TTestNotes.Pt(const AName: string; X, Y: double): TPointObject;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y));
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestNotes.Square(const AName: string; Left, Size: double; out TopEdge: string): TPieceObject;
var
  A, B, C, D: TPointObject;
  Path: TPiecePath;
  Reason: string;
begin
  A := Pt('', Left, 0);
  B := Pt('', Left + Size, 0);
  C := Pt('', Left + Size, Size);
  D := Pt('', Left, Size);
  TopEdge := FPattern.AddLine(A.Key, B.Key, erOutline).Key;
  FPattern.AddLine(B.Key, C.Key, erOutline);
  FPattern.AddLine(C.Key, D.Key, erOutline);
  FPattern.AddLine(D.Key, A.Key, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Size / 2, Size / 2), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestNotes.Saved: string;
begin
  Result := SavePatternToText(FPattern);
end;

function TTestNotes.Reloaded: TPattern;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
  FLoaded.Evaluate;
  Result := FLoaded;
end;

function TTestNotes.Problems: string;
var
  Blocked: integer;
begin
  Result := string.Join(LineEnding, PatternProblems(FPattern, Blocked));
end;

procedure TTestNotes.TestPointAnchorFollows;
var
  A: TPointObject;
  Note: TNoteObject;
begin
  A := Pt('A', 10, 20);
  Note := FPattern.AddNote('', 'Stay-stitch', naPoint, A.Key, '', '5', '-3');
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertTrue(Note.State = esValid);
  AssertPointsNear('offset from A', Vec2(15, 17), Note.Position);
  AssertPointsNear('hangs from A', Vec2(10, 20), Note.AnchorPosition);
  AssertTrue(FPattern.SetFormula(A, 'x', '40'));
  FPattern.Evaluate;
  AssertPointsNear('follows A', Vec2(45, 17), Note.Position);
end;

procedure TTestNotes.TestEdgeAnchorRatio;
var
  Edge: TLineObject;
  Note: TNoteObject;
begin
  Edge := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Note := FPattern.AddNote('', 'Ease', naEdge, Edge.Key, '0.25', '0', '10');
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertPointsNear('a quarter along, then down', Vec2(25, 10), Note.Position);
  AssertTrue(FPattern.SetFormula(FPattern.FindObject('B'), 'x', '200'));
  FPattern.Evaluate;
  AssertPointsNear('still a quarter along', Vec2(50, 10), Note.Position);
end;

procedure TTestNotes.TestEdgeRatioOutOfRangeIsInvalid;
var
  Edge: TLineObject;
  Note: TNoteObject;
begin
  Edge := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Note := FPattern.AddNote('', 'Ease', naEdge, Edge.Key, '1.5', '0', '0');
  FPattern.Evaluate;
  AssertTrue(Note.State = esInvalid);
end;

procedure TTestNotes.TestPieceAnchorIsMiddle;
var
  Piece: TPieceObject;
  Top: string;
  Note: TNoteObject;
begin
  Piece := Square('Front', 0, 100, Top);
  Note := FPattern.AddNote('', 'Front', naPiece, Piece.Key, '', '-10', '0');
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertPointsNear('the middle, moved left', Piece.Middle + Vec2(-10, 0), Note.Position);
end;

procedure TTestNotes.TestFreeNote;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Loose', naFree, '', '', '30', '40');
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertPointsNear('at x, y', Vec2(30, 40), Note.Position);
  AssertEquals('no inputs', 0, Length(Note.InputKeys));
end;

procedure TTestNotes.TestFailingAnchorBlocks;
var
  A: TPointObject;
  Note: TNoteObject;
begin
  A := Pt('A', 10, 20);
  Note := FPattern.AddNote('', 'Text', naPoint, A.Key, '', '0', '0');
  FPattern.Evaluate;
  // Divides by zero, an error
  AssertTrue(FPattern.LastError, FPattern.SetFormula(A, 'x', '1 / 0'));
  FPattern.Evaluate;
  AssertTrue('the point fails', A.State <> esValid);
  FPattern.Evaluate;
  AssertTrue('blocked', Note.State = esBlocked);
  AssertPointsNear('kept its last good place', Vec2(10, 20), Note.Position);
end;

procedure TTestNotes.TestDeletingAnchorRefused;
var
  A: TPointObject;
begin
  A := Pt('A', 10, 20);
  FPattern.AddNote('Stay', 'Text', naPoint, A.Key, '', '0', '0');
  AssertFalse('refused', FPattern.Delete(A));
  AssertTrue('names the note', Pos('Stay', FPattern.LastError) > 0);
end;

procedure TTestNotes.TestMakeFreeKeepsPlace;
var
  A: TPointObject;
  Note: TNoteObject;
  Key: string;
begin
  A := Pt('A', 10, 20);
  Note := FPattern.AddNote('', 'Text', naPoint, A.Key, '', '2.5', '3');
  Key := Note.Key;
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.MakeNoteFree(Note));
  AssertTrue(Note.Anchor = naFree);
  AssertTrue('the point can go', FPattern.Delete(A));
  FPattern.Evaluate;
  Note := TNoteObject(FPattern.FindNode(Key));
  AssertPointsNear('same place', Vec2(12.5, 23), Note.Position);
  AssertEquals('x', '12.5', FPattern.FormulaText(Note, NOTE_X_FIELD));
  AssertFalse('already free', FPattern.MakeNoteFree(Note));
end;

procedure TTestNotes.TestDefaultNames;
begin
  AssertEquals('Note', FPattern.AddNote('', 'a', naFree, '', '', '0', '0').Name);
  AssertEquals('Note2', FPattern.AddNote('', 'b', naFree, '', '', '0', '0').Name);
  AssertNull('name taken', FPattern.AddNote('Note', 'c', naFree, '', '', '0', '0'));
end;

procedure TTestNotes.TestRefusesWrongAnchorKind;
var
  A: TPointObject;
  Edge: TLineObject;
begin
  A := Pt('A', 0, 0);
  Edge := FPattern.AddLine(A.Key, Pt('B', 10, 0).Key);
  AssertNull('edge as point', FPattern.AddNote('', 'x', naPoint, Edge.Key, '', '0', '0'));
  AssertNull('point as edge', FPattern.AddNote('', 'x', naEdge, A.Key, '0.5', '0', '0'));
  AssertNull('point as piece', FPattern.AddNote('', 'x', naPiece, A.Key, '', '0', '0'));
  AssertNull('missing', FPattern.AddNote('', 'x', naPoint, '999', '', '0', '0'));
  AssertNull('bad formula', FPattern.AddNote('', 'x', naPoint, A.Key, '', '1 +', '0'));
  AssertEquals('nothing added', 3, FPattern.ObjectCount);
end;

procedure TTestNotes.TestSizeLimits;
var
  Note: TNoteObject;
begin
  AssertNull('zero', FPattern.AddNote('', 'x', naFree, '', '', '0', '0', 0));
  Note := FPattern.AddNote('', 'x', naFree, '', '', '0', '0', 14);
  AssertNear('given size', 14, Note.Size);
  AssertFalse(FPattern.SetNoteSize(Note, -1));
  AssertFalse(FPattern.SetNoteSize(Note, MAX_NOTE_SIZE + 1));
  AssertTrue(FPattern.SetNoteSize(Note, 8));
  AssertNear('changed', 8, Note.Size);
end;

procedure TTestNotes.TestMergeMovesAnchor;
var
  A, B: TPointObject;
  Note: TNoteObject;
  Kept: TPointObject;
begin
  A := Pt('A', 0, 0);
  B := Pt('B', 0, 0);
  Note := FPattern.AddNote('', 'x', naPoint, B.Key, '', '0', '0');
  Kept := FPattern.MergePoints([A.Key, B.Key]);
  AssertNotNull(FPattern.LastError, Kept);
  AssertEquals('follows the kept point', Kept.Key, Note.AnchorKey);
end;

procedure TTestNotes.TestDragPlainOffset;
var
  A: TPointObject;
  Note: TNoteObject;
  Reason: string;
begin
  A := Pt('A', 10, 20);
  Note := FPattern.AddNote('', 'x', naPoint, A.Key, '', '0', '0');
  FPattern.Evaluate;
  AssertTrue(Reason, DragNote(FPattern, Note, Vec2(25.04, 12), Reason));
  FPattern.Evaluate;
  AssertEquals('dx', '15', FPattern.FormulaText(Note, NOTE_DX_FIELD));
  AssertEquals('dy', '-8', FPattern.FormulaText(Note, NOTE_DY_FIELD));
  AssertPointsNear('moved', Vec2(25, 12), Note.Position);
end;

procedure TTestNotes.TestDragRefusesFormula;
var
  A: TPointObject;
  Note: TNoteObject;
  Reason: string;
begin
  A := Pt('A', 10, 20);
  Note := FPattern.AddNote('', 'x', naPoint, A.Key, '', 'A.x / 2', '0');
  FPattern.Evaluate;
  AssertFalse(DragNote(FPattern, Note, Vec2(0, 0), Reason));
  AssertTrue(Reason <> '');
  AssertEquals('kept', 'A.x / 2', FPattern.FormulaText(Note, NOTE_DX_FIELD));
end;

procedure TTestNotes.TestDragFreeNote;
var
  Note: TNoteObject;
  Reason: string;
begin
  Note := FPattern.AddNote('', 'x', naFree, '', '', '0', '0');
  FPattern.Evaluate;
  AssertTrue(Reason, DragNote(FPattern, Note, Vec2(7, -3), Reason));
  FPattern.Evaluate;
  AssertPointsNear('placed', Vec2(7, -3), Note.Position);
end;

procedure TTestNotes.TestRoundTrip;
var
  Piece: TPieceObject;
  Top, Text: string;
  Note: TNoteObject;
begin
  Piece := Square('Front', 0, 100, Top);
  FPattern.AddNote('', 'On a point' + #10 + 'second line', naPoint, TEdgeObject(FPattern.FindNode(Top)).StartKey, '', '1', '2');
  FPattern.AddNote('', 'On an edge', naEdge, Top, '0.5', '0', '-10', 12, False);
  FPattern.AddNote('', 'On the piece', naPiece, Piece.Key, '', '0', '0');
  FPattern.AddNote('', 'Free', naFree, '', '', '5', '6');
  FPattern.Evaluate;
  Text := Saved;
  AssertTrue('a note', Pos('"type": "note"', Text) > 0);
  AssertTrue('edge anchor', Pos('"edge": ' + Top, Text) > 0);
  AssertEquals('same again', Text, SavePatternToText(Reloaded));
  Note := TNoteObject(FLoaded.FindObject('Note2'));
  AssertEquals('text', 'On an edge', Note.StoredText);
  AssertNear('size', 12, Note.Size);
  AssertFalse('screen only', Note.Print);
  AssertTrue(Note.Anchor = naEdge);
  AssertEquals('position', '0.5', FLoaded.FormulaText(Note, NOTE_POSITION_FIELD));
  AssertEquals('two lines', 'On a point' + #10 + 'second line', TNoteObject(FLoaded.FindObject('Note')).StoredText);
end;

procedure TTestNotes.TestLoadRefusesBadAnchor;
var
  Err: string;
begin
  AssertFalse('point as edge', LoadPatternFromText(FLoaded, ANCHOR_PATTERN_HEAD +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"edge": 1, "position": "0"}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('later object', LoadPatternFromText(FLoaded, ANCHOR_PATTERN_HEAD +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 5}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('two anchors', LoadPatternFromText(FLoaded, ANCHOR_PATTERN_HEAD +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1, "piece": 1}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('no text', LoadPatternFromText(FLoaded, ANCHOR_PATTERN_HEAD +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1}, "dx": "0", "dy": "0"}]}', Err));
  AssertTrue(Err, LoadPatternFromText(FLoaded, ANCHOR_PATTERN_HEAD +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertNear('default size', DEFAULT_NOTE_SIZE, TNoteObject(FLoaded.FindObject('N')).Size);
  AssertTrue('prints by default', TNoteObject(FLoaded.FindObject('N')).Print);
end;

procedure TTestNotes.TestHideAnnotationsSaved;
begin
  AssertEquals('left out when shown', 0, Pos('hideAnnotations', Saved));
  FPattern.View.HideAnnotations := True;
  AssertTrue('written', Pos('hideAnnotations', Saved) > 0);
  AssertTrue('read', Reloaded.View.HideAnnotations);
end;

procedure TTestNotes.TestHideAnnotationsKeptOutOfUndo;
var
  Document: TPatternDocument;
  Before: string;
begin
  Before := SavePatternToText(FPattern, False);
  FPattern.View.HideAnnotations := True;
  AssertEquals('no change to undo', Before, SavePatternToText(FPattern, False));
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add note');
    Document.Pattern.AddNote('', 'x', naFree, '', '', '0', '0');
    Document.EndChange;
    Document.Pattern.View.HideAnnotations := True;
    Document.ViewChanged;
    Document.Undo;
    AssertTrue('kept through undo', Document.Pattern.View.HideAnnotations);
    AssertFalse('not a modification', Document.Modified);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestNotes.TestNotePieces;
var
  Front, Back: TPieceObject;
  TopF, TopB: string;
  OnEdge, OnCorner, Inside, Outside, OnPiece: TNoteObject;
  Pieces: TPieceObjectArray;
begin
  Front := Square('Front', 0, 100, TopF);
  Back := Square('Back', 200, 100, TopB);
  OnEdge := FPattern.AddNote('', 'a', naEdge, TopF, '0.5', '0', '-50');
  OnCorner := FPattern.AddNote('', 'b', naPoint, TEdgeObject(FPattern.FindNode(TopB)).StartKey, '', '-500', '0');
  Inside := FPattern.AddNote('', 'c', naFree, '', '', '50', '50');
  Outside := FPattern.AddNote('', 'd', naFree, '', '', '150', '50');
  OnPiece := FPattern.AddNote('', 'e', naPiece, Back.Key, '', '0', '0');
  FPattern.Evaluate;
  Pieces := FPattern.NotePieces(OnEdge);
  AssertEquals('edge of front, though outside it', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Front);
  Pieces := FPattern.NotePieces(OnCorner);
  AssertEquals('corner of back', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Back);
  Pieces := FPattern.NotePieces(Inside);
  AssertEquals('inside front', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Front);
  AssertEquals('between the pieces', 0, Length(FPattern.NotePieces(Outside)));
  Pieces := FPattern.NotePieces(OnPiece);
  AssertEquals('anchored to back', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Back);
end;

// A callout's text may lie over another piece; it prints with what it points at
procedure TTestNotes.TestCalloutGoesWithItsTip;
var
  Front, Back: TPieceObject;
  TopF, TopB: string;
  Callout, Pointing: TNoteObject;
  Pieces: TPieceObjectArray;
begin
  Front := Square('Front', 0, 100, TopF);
  Back := Square('Back', 200, 100, TopB);
  // On Back's corner, its text over Front
  Callout := FPattern.AddNote('', 'a', naPoint, TEdgeObject(FPattern.FindNode(TopB)).StartKey, '', '-150', '50', DEFAULT_NOTE_SIZE, True, nlArrow);
  FPattern.Evaluate;
  Pieces := FPattern.NotePieces(Callout);
  AssertEquals('only Back', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Back);
  // Pointing inside Front at a point no piece uses
  Pointing := FPattern.AddNote('', 'b', naPoint, Pt('Inside', 50, 50).Key, '', '300', '0', DEFAULT_NOTE_SIZE, True, nlDot);
  FPattern.Evaluate;
  Pieces := FPattern.NotePieces(Pointing);
  AssertEquals('where its tip is', 1, Length(Pieces));
  AssertTrue(Pieces[0] = Front);
end;

procedure TTestNotes.TestPieceNotesOnlyPrinting;
var
  Front: TPieceObject;
  Top: string;
  Notes: TNoteObjectArray;
begin
  Front := Square('Front', 0, 100, Top);
  FPattern.AddNote('Shown', 'a', naPiece, Front.Key, '', '0', '0', DEFAULT_NOTE_SIZE, False);
  FPattern.AddNote('Printed', 'b', naPiece, Front.Key, '', '0', '0');
  FPattern.Evaluate;
  Notes := FPattern.PieceNotes(Front);
  AssertEquals(1, Length(Notes));
  AssertEquals('Printed', Notes[0].Name);
end;

procedure TTestNotes.TestPieceMovingKeepsNoteAfterIt;
var
  Front: TPieceObject;
  Top, Err: string;
  Late: TPointObject;
begin
  Front := Square('Front', 0, 100, Top);
  FPattern.AddNote('', 'a', naPiece, Front.Key, '', '0', '0');
  Late := Pt('Late', 50, 0);
  // A notch on a newer point moves the piece down the file
  AssertTrue(FPattern.LastError, FPattern.AddPointNotch(Front, Late.Key));
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
end;

procedure TTestNotes.TestProblems;
var
  Front: TPieceObject;
  Top: string;
begin
  Front := Square('Front', 0, 100, Top);
  FPattern.AddNote('Loose', 'a', naFree, '', '', '500', '500');
  FPattern.AddNote('Private', 'b', naFree, '', '', '500', '500', DEFAULT_NOTE_SIZE, False);
  FPattern.AddNote('Fine', 'c', naPiece, Front.Key, '', '0', '0');
  FPattern.Evaluate;
  AssertTrue('loose printing note', Pos('Loose', Problems) > 0);
  AssertEquals('screen-only note is fine', 0, Pos('Private', Problems));
  AssertEquals('note on a piece is fine', 0, Pos('Fine', Problems));
end;

procedure TTestNotes.TestFieldValues;
var
  Values: TFieldValues;
  Measurements: TMeasurementSet;
begin
  Measurements := TMeasurementSet.Create;
  try
    Measurements.Name := 'Anna';
    FPattern.Measurements := Measurements;
    Values := PatternFieldValues(FPattern, ConcatPaths(['patterns', 'skirt.sloper']));
    AssertEquals('Skirt for Anna', ExpandFields('Skirt for {measurements.name}', Values));
    AssertEquals('skirt', ExpandFields('{pattern.name}', Values));
    AssertEquals('no file keeps the field', '{pattern.name}', ExpandFields('{pattern.name}', PatternFieldValues(FPattern, '')));
    AssertEquals('page stays as typed', '{page}', ExpandFields('{page}', Values));
  finally
    FPattern.Measurements := nil;
    FreeAndNil(Measurements);
  end;
end;

procedure TTestNotes.TestBoundsIncludeNotes;
var
  Bounds: TRect2;
begin
  Pt('A', 0, 0);
  FPattern.AddNote('', 'Far away', naFree, '', '', '300', '200');
  FPattern.Evaluate;
  AssertTrue(PatternBounds(FPattern, Bounds));
  AssertTrue('reaches the note', Bounds.MaxX > 300);
  AssertTrue(PatternBounds(FPattern, Bounds, False));
  AssertNear('without notes', 0, Bounds.MaxX);
end;

procedure TTestNotes.TestTextToolAnchors;
var
  Front: TPieceObject;
  Top: string;
  A: TPointObject;
  Snap: TSnap;
  Note: TNoteObject;
begin
  Front := Square('Front', 0, 100, Top);
  FPattern.Evaluate;
  A := TPointObject(FPattern.FindNode(TEdgeObject(FPattern.FindNode(Top)).StartKey));
  // On a point, offset to where the click was
  Snap := FindSnap(FPattern, Vec2(1, 1), 3);
  AssertTrue('snaps to the corner', Snap.Kind = snPoint);
  Note := NoteFromSnap(FPattern, Snap, Vec2(1, 1), 'a');
  AssertNotNull(FPattern.LastError, Note);
  AssertTrue('point anchor', Note.Anchor = naPoint);
  AssertEquals('the corner', A.Key, Note.AnchorKey);
  AssertEquals('dx', '1', FPattern.FormulaText(Note, NOTE_DX_FIELD));
  // On an edge, as a ratio along it
  Snap := FindSnap(FPattern, Vec2(25, 1), 3);
  AssertTrue('snaps to the top', Snap.Kind = snEdge);
  Note := NoteFromSnap(FPattern, Snap, Vec2(25, 1), 'b');
  AssertTrue('edge anchor', Note.Anchor = naEdge);
  AssertEquals('the top', Top, Note.AnchorKey);
  AssertEquals('a quarter along', '0.25', FPattern.FormulaText(Note, NOTE_POSITION_FIELD));
  AssertEquals('dy', '1', FPattern.FormulaText(Note, NOTE_DY_FIELD));
  // Inside the piece, away from its edges
  Snap := FindSnap(FPattern, Vec2(30, 60), 3);
  Note := NoteFromSnap(FPattern, Snap, Vec2(30, 60), 'c');
  AssertTrue('piece anchor ' + NOTE_ANCHOR_NAMES[Note.Anchor], Note.Anchor = naPiece);
  AssertEquals('the piece', Front.Key, Note.AnchorKey);
  FPattern.Evaluate;
  AssertPointsNear('where it was clicked', Vec2(30, 60), Note.Position, 0.06);
  // Outside everything
  Snap := FindSnap(FPattern, Vec2(300, 300), 3);
  Note := NoteFromSnap(FPattern, Snap, Vec2(300, 300), 'd');
  AssertTrue('free', Note.Anchor = naFree);
  AssertEquals('x', '300', FPattern.FormulaText(Note, NOTE_X_FIELD));
end;

procedure TTestNotes.TestNotesAtTopmostAndHidden;
var
  First, Second: TNoteObject;
  Keys: TStringArray;
  Box: TRect2;
begin
  First := FPattern.AddNote('', 'Underneath', naFree, '', '', '0', '0');
  Second := FPattern.AddNote('', 'On top', naFree, '', '', '1', '1');
  FPattern.Evaluate;
  Keys := NotesAt(FPattern, Vec2(2, 2), Default(TFieldValues), 0.5);
  AssertEquals('both', 2, Length(Keys));
  AssertEquals('later first', Second.Key, Keys[0]);
  AssertEquals(First.Key, Keys[1]);
  AssertEquals('missed', 0, Length(NotesAt(FPattern, Vec2(200, 200), Default(TFieldValues), 0.5)));
  FPattern.View.HideAnnotations := True;
  AssertEquals('hidden', 0, Length(NotesAt(FPattern, Vec2(2, 2), Default(TFieldValues), 0.5)));
  Box.MinX := -10;
  Box.MinY := -10;
  Box.MaxX := 100;
  Box.MaxY := 100;
  AssertEquals('not boxed while hidden', 0, Length(ObjectsInBox(FPattern, Box)));
  FPattern.View.HideAnnotations := False;
  AssertEquals('boxed when shown', 2, Length(ObjectsInBox(FPattern, Box)));
end;

procedure TTestNotes.TestObjectRows;
var
  Rows: TObjectRowArray;
  A: TPointObject;
begin
  A := Pt('A', 0, 0);
  FPattern.AddNote('', 'Stay-stitch' + #10 + 'the neckline', naFree, '', '', '0', '0');
  FPattern.Evaluate;
  Rows := ObjectRows(FPattern, ofNotes, '');
  AssertEquals('only notes', 1, Length(Rows));
  AssertEquals('first line', 'Stay-stitch', Rows[0].Value);
  AssertEquals('a note', 'Note', Rows[0].Operation);
  AssertEquals('found by its text', 1, Length(ObjectRows(FPattern, ofAll, 'neckline')));
  // Its text is its label, so it gets no name drawn beside it
  AssertEquals('not labelled', A.Key, string.Join(',', LabelKeys(FPattern, lmAll, [Rows[0].Key], '', nil)));
end;

procedure TTestNotes.TestDraftSVG;
var
  Options: TDraftSVGOptions;
  Text: string;
begin
  Pt('A', 0, 0);
  FPattern.AddNote('', 'For {pattern.name}' + #10 + 'Line <two>', naFree, '', '', '10', '10');
  FPattern.AddNote('', 'Mine', naFree, '', '', '10', '30', DEFAULT_NOTE_SIZE, False);
  FPattern.Evaluate;
  Options := DefaultDraftSVGOptions;
  Options.PatternFileName := 'skirt.sloper';
  Text := DraftToSVG(FPattern, Options);
  AssertTrue('field filled', Pos('>For skirt<', Text) > 0);
  AssertTrue('escaped second line', Pos('>Line &lt;two&gt;<', Text) > 0);
  AssertTrue('font', Pos('font-family="Helvetica, Arial, sans-serif"', Text) > 0);
  AssertEquals('screen only left out', 0, Pos('Mine', Text));
  Options.HideAnnotations := True;
  AssertEquals('hidden', 0, Pos('skirt', DraftToSVG(FPattern, Options)));
end;

procedure TTestNotes.TestSplitDraftValues;
var
  Template: string;
  Expressions: TStringArray;
  ErrorPos: integer;
begin
  AssertTrue(SplitDraftValues('a {={12}.x + 1} b {= 2 }', Template, Expressions, ErrorPos));
  AssertEquals('a ' + VALUE_MARK + ' b ' + VALUE_MARK, Template);
  AssertEquals(2, Length(Expressions));
  AssertEquals('braces inside counted', '{12}.x + 1', Expressions[0]);
  AssertEquals('trimmed', '2', Expressions[1]);
  AssertTrue('plain braces stay', SplitDraftValues('{pattern.name}', Template, Expressions, ErrorPos));
  AssertEquals('{pattern.name}', Template);
  AssertFalse('unclosed', SplitDraftValues('x {=1 + 2', Template, Expressions, ErrorPos));
  AssertEquals('at the {=', 3, ErrorPos);
end;

procedure TTestNotes.TestDraftValueFollowsDraft;
var
  Line: TLineObject;
  Note: TNoteObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Note := FPattern.AddNote('', 'Seam {=Line_A_B.length} mm', naEdge, Line.Key, '0.5', '0', '5');
  AssertNotNull(FPattern.LastError, Note);
  AssertEquals('one value', 1, Note.ValueCount);
  FPattern.Evaluate;
  AssertEquals('Seam 100 mm', Note.ShownText);
  AssertTrue(FPattern.SetFormula(FPattern.FindObject('B'), 'x', '150.04'));
  FPattern.Evaluate;
  AssertEquals('to a tenth', 'Seam 150 mm', Note.ShownText);
  AssertEquals('first line', 'Seam 150 mm', Note.FirstLine);
end;

// RoundTo leaves binary noise that full-precision printing shows
procedure TTestNotes.TestDraftValueTextIsShort;
begin
  AssertEquals('135.1', DraftValueText(135.1));
  AssertEquals('as seen on screen', '135.2', DraftValueText(135.175108));
  AssertEquals('135.1', DraftValueText(135.0999999));
  AssertEquals('253.9', DraftValueText(253.94));
  AssertEquals('no minus zero', '0', DraftValueText(-0.04));
  AssertEquals('-12.3', DraftValueText(-12.34));
end;

procedure TTestNotes.TestDraftValueStoredById;
var
  Line: TLineObject;
  Note: TNoteObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  Note := FPattern.AddNote('', 'Seam {=Line_A_B.length}', naFree, '', '', '0', '0');
  AssertEquals('stored by ID', 'Seam {=' + Note.Field('value1').StoredText + '}', Note.StoredText);
  AssertEquals('no name stored', 0, Pos('Line_A_B', Note.StoredText));
  AssertTrue(Pos(Line.Key, Note.StoredText) > 0);
  AssertTrue(FPattern.Rename(Line, 'Hem'));
  AssertEquals('shown with the new name', 'Seam {=Hem.length}', Note.DisplayText(FPattern.Resolver));
end;

procedure TTestNotes.TestDraftValueIsAnInput;
var
  Line: TLineObject;
begin
  Line := FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  FPattern.AddNote('Length', '{=Line_A_B.length}', naFree, '', '', '0', '0');
  FPattern.Evaluate;
  AssertFalse('refused', FPattern.Delete(Line));
  AssertTrue('names the note', Pos('Length', FPattern.LastError) > 0);
end;

procedure TTestNotes.TestDraftValueRefused;
var
  Note: TNoteObject;
begin
  Pt('A', 0, 0);
  Note := FPattern.AddNote('', 'Before', naFree, '', '', '0', '0');
  AssertFalse('unknown name', FPattern.SetNoteText(Note, 'x {=Nope.length}'));
  AssertEquals('names the field', NOTE_TEXT_FIELD, FPattern.LastErrorField);
  AssertEquals('kept', 'Before', Note.StoredText);
  AssertFalse('unclosed', FPattern.SetNoteText(Note, 'x {=A.x'));
  AssertFalse('itself', FPattern.SetNoteText(Note, '{=Note.x}'));
  AssertNull('refused when added', FPattern.AddNote('', '{=1 +}', naFree, '', '', '0', '0'));
  AssertTrue(FPattern.SetNoteText(Note, 'At {=A.x}'));
  AssertTrue('back to plain', FPattern.SetNoteText(Note, 'Plain'));
  AssertEquals('no values left', 0, Note.ValueCount);
  AssertEquals('no value fields left', 2, Note.FieldCount);
end;

procedure TTestNotes.TestDraftValueFailingBlocks;
var
  A: TPointObject;
  Note: TNoteObject;
begin
  A := Pt('A', 10, 0);
  Note := FPattern.AddNote('', 'x is {=A.x}', naFree, '', '', '0', '0');
  FPattern.Evaluate;
  AssertEquals('x is 10', Note.ShownText);
  AssertTrue(FPattern.SetFormula(A, 'x', '1 / 0'));
  FPattern.Evaluate;
  AssertTrue('blocked', Note.State = esBlocked);
  AssertEquals('keeps its last good value', 'x is 10', Note.ShownText);
end;

procedure TTestNotes.TestDraftValueVariable;
var
  Note: TNoteObject;
begin
  AssertNotNull(FPattern.LastError, FPattern.AddVariable('ease', '5'));
  Note := FPattern.AddNote('', 'Ease {=#ease * 2} mm', naFree, '', '', '0', '0');
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertEquals('Ease 10 mm', Note.ShownText);
end;

procedure TTestNotes.TestDraftValueRoundTrip;
var
  Note: TNoteObject;
begin
  FPattern.AddLine(Pt('A', 0, 0).Key, Pt('B', 100, 0).Key);
  FPattern.AddNote('Hem', 'Hem {=Line_A_B.length} mm' + #10 + 'and {=A.x + 1}', naFree, '', '', '0', '0');
  FPattern.Evaluate;
  Note := TNoteObject(Reloaded.FindObject('Hem'));
  AssertEquals('two values', 2, Note.ValueCount);
  AssertEquals('Hem 100 mm' + #10 + 'and 1', Note.ShownText);
  AssertEquals('same file', Saved, SavePatternToText(FLoaded));
end;

procedure TTestNotes.TestCalloutNeedsAnchor;
var
  A: TPointObject;
  Note: TNoteObject;
begin
  A := Pt('A', 0, 0);
  AssertNull('free callout', FPattern.AddNote('', 'x', naFree, '', '', '0', '0', DEFAULT_NOTE_SIZE, True, nlArrow));
  Note := FPattern.AddNote('', 'x', naFree, '', '', '0', '0');
  AssertFalse('free note cannot get a leader', FPattern.SetNoteLeader(Note, nlDot));
  Note := FPattern.AddNote('', 'x', naPoint, A.Key, '', '10', '0', DEFAULT_NOTE_SIZE, True, nlArrow);
  AssertNotNull(FPattern.LastError, Note);
  FPattern.Evaluate;
  AssertTrue(FPattern.MakeNoteFree(Note));
  AssertTrue('made free, it loses its leader', Note.Leader = nlNone);
end;

procedure TTestNotes.TestLookRoundTrip;
var
  A: TPointObject;
  Note: TNoteObject;
  Text: string;
begin
  A := Pt('A', 0, 0);
  Note := FPattern.AddNote('Call', 'x', naPoint, A.Key, '', '10', '0', DEFAULT_NOTE_SIZE, True, nlDot);
  FPattern.SetNoteAlign(Note, taCentre);
  FPattern.SetNoteBoxed(Note, True);
  FPattern.AddNote('Plain', 'y', naFree, '', '', '0', '0');
  Text := Saved;
  AssertTrue('leader', Pos('"leader": "dot"', Text) > 0);
  AssertTrue('align', Pos('"align": "centre"', Text) > 0);
  AssertTrue('box', Pos('"box": true', Text) > 0);
  // Only the callout writes them
  AssertEquals('plain notes stay plain', 0, Pos('"leader"', Copy(Text, Pos('"leader"', Text) + 1, MaxInt)));
  Note := TNoteObject(Reloaded.FindObject('Call'));
  AssertTrue(Note.Leader = nlDot);
  AssertTrue(Note.Align = taCentre);
  AssertTrue(Note.Boxed);
  Note := TNoteObject(FLoaded.FindObject('Plain'));
  AssertTrue(Note.Leader = nlNone);
  AssertTrue(Note.Align = taLeft);
  AssertFalse(Note.Boxed);
end;

procedure TTestNotes.TestSetNoteAnchorKeepsText;
var
  A: TPointObject;
  Line: TLineObject;
  Note: TNoteObject;
  Err: string;
begin
  A := Pt('A', 0, 0);
  Line := FPattern.AddLine(A.Key, Pt('B', 100, 0).Key);
  Note := FPattern.AddNote('', 'x', naPoint, A.Key, '', '10', '5', DEFAULT_NOTE_SIZE, True, nlArrow);
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.SetNoteAnchor(Note, naEdge, Line.Key, 0.5));
  AssertTrue(Note.Anchor = naEdge);
  AssertEquals('dx', '-40', FPattern.FormulaText(Note, NOTE_DX_FIELD));
  AssertEquals('position', '0.5', FPattern.FormulaText(Note, NOTE_POSITION_FIELD));
  FPattern.Evaluate;
  AssertPointsNear('text stays', Vec2(10, 5), Note.Position);
  AssertPointsNear('tip moved', Vec2(50, 0), Note.AnchorPosition);
  AssertEquals('position, dx and dy only', 3, Note.FieldCount);
  // From a point to a point, with a draft value, as dragging a tip does
  AssertTrue(FPattern.SetNoteText(Note, 'At {=A.x}'));
  AssertTrue(FPattern.LastError, FPattern.SetNoteAnchor(Note, naPoint, A.Key));
  AssertEquals('value, dx and dy only', 3, Note.FieldCount);
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, FPattern.SetNoteAnchor(Note, naEdge, Line.Key, 0.5));
  FPattern.Evaluate;
  AssertFalse('a callout cannot be free', FPattern.SetNoteAnchor(Note, naFree, ''));
  AssertFalse('ratio past the end', FPattern.SetNoteAnchor(Note, naEdge, Line.Key, 2));
  AssertTrue(Err, LoadPatternFromText(FLoaded, Saved, Err));
end;

procedure TTestNotes.TestLeaderGeometry;
var
  Box: TRect2;
  Start: TVec2;
  Strokes: TLine2Array;
begin
  Box.MinX := 0;
  Box.MinY := 0;
  Box.MaxX := 10;
  Box.MaxY := 5;
  AssertTrue(LeaderStart(Box, Vec2(20, 2), Start));
  AssertPointsNear('from the near side', Vec2(10, 2), Start);
  AssertTrue(LeaderStart(Box, Vec2(-5, -5), Start));
  AssertPointsNear('from the corner', Vec2(0, 0), Start);
  AssertFalse('tip inside', LeaderStart(Box, Vec2(5, 2), Start));
  AssertEquals('no leader', 0, Length(LeaderStrokes(Vec2(10, 2), Vec2(20, 2), nlNone)));
  AssertEquals('a line', 1, Length(LeaderStrokes(Vec2(10, 2), Vec2(20, 2), nlLine)));
  AssertEquals('a dot is drawn apart', 1, Length(LeaderStrokes(Vec2(10, 2), Vec2(20, 2), nlDot)));
  Strokes := LeaderStrokes(Vec2(10, 2), Vec2(20, 2), nlArrow);
  AssertEquals('line and head', 3, Length(Strokes));
  AssertNear('head length', LEADER_ARROW_LENGTH, Distance(Strokes[1].P1, Strokes[1].P2));
  AssertTrue('head points back', Strokes[1].P2.X < 20);
  AssertTrue('one each side', (Strokes[1].P2.Y - 2) * (Strokes[2].P2.Y - 2) < 0);
  AssertEquals('dot outline', 12, Length(LeaderDot(Vec2(0, 0))));
end;

procedure TTestNotes.TestAlignedLeft;
begin
  AssertNear('left', 10, AlignedLeft(10, 100, 40, taLeft));
  AssertNear('centre', 40, AlignedLeft(10, 100, 40, taCentre));
  AssertNear('right', 70, AlignedLeft(10, 100, 40, taRight));
end;

procedure TTestNotes.TestCalloutFromSnap;
var
  A: TPointObject;
  Snap: TSnap;
  Note: TNoteObject;
begin
  A := Pt('A', 0, 0);
  Pt('B', 100, 0);
  FPattern.Evaluate;
  Snap := FindSnap(FPattern, Vec2(1, 1), 3);
  Note := CalloutFromSnap(FPattern, Snap, Vec2(1, 1), Vec2(20, 30), 'Here', nlArrow);
  AssertNotNull(FPattern.LastError, Note);
  AssertTrue(Note.Anchor = naPoint);
  AssertEquals(A.Key, Note.AnchorKey);
  AssertTrue(Note.Leader = nlArrow);
  FPattern.Evaluate;
  AssertPointsNear('text where the second click was', Vec2(20, 30), Note.Position);
  AssertPointsNear('tip on A', Vec2(0, 0), Note.AnchorPosition);
  Snap := FindSnap(FPattern, Vec2(300, 300), 3);
  AssertNull('nothing to point at', CalloutFromSnap(FPattern, Snap, Vec2(300, 300), Vec2(310, 310), 'x', nlArrow));
end;

procedure TTestNotes.TestReanchorFromSnap;
var
  B: TPointObject;
  Snap: TSnap;
  Note: TNoteObject;
begin
  Pt('A', 0, 0);
  B := Pt('B', 100, 0);
  FPattern.Evaluate;
  Note := CalloutFromSnap(FPattern, FindSnap(FPattern, Vec2(0, 0), 3), Vec2(0, 0), Vec2(20, 30), 'x', nlArrow);
  FPattern.Evaluate;
  Snap := FindSnap(FPattern, Vec2(99, 1), 3);
  AssertTrue(FPattern.LastError, ReanchorFromSnap(FPattern, Note, Snap, Vec2(99, 1)));
  AssertEquals('now on B', B.Key, Note.AnchorKey);
  FPattern.Evaluate;
  AssertPointsNear('text stays', Vec2(20, 30), Note.Position);
  AssertFalse('dropped on nothing', ReanchorFromSnap(FPattern, Note, FindSnap(FPattern, Vec2(300, 300), 3), Vec2(300, 300)));
end;

procedure TTestNotes.TestCalloutTipAt;
var
  A: TPointObject;
  Note, Plain: TNoteObject;
begin
  A := Pt('A', 0, 0);
  Note := FPattern.AddNote('', 'x', naPoint, A.Key, '', '20', '20', DEFAULT_NOTE_SIZE, True, nlArrow);
  Plain := FPattern.AddNote('', 'y', naPoint, A.Key, '', '40', '20');
  FPattern.Evaluate;
  AssertEquals('selected callout', Note.Key, CalloutTipAt(FPattern, [Plain.Key, Note.Key], Vec2(0.5, 0), 1));
  AssertEquals('not selected', '', CalloutTipAt(FPattern, [Plain.Key], Vec2(0.5, 0), 1));
  AssertEquals('too far', '', CalloutTipAt(FPattern, [Note.Key], Vec2(5, 0), 1));
end;

procedure TTestNotes.TestCalloutCaptions;
var
  A: TPointObject;
  Note: TNoteObject;
begin
  A := Pt('A', 0, 0);
  Note := FPattern.AddNote('', 'At {=A.x}', naPoint, A.Key, '', '20', '20', DEFAULT_NOTE_SIZE, True, nlArrow);
  AssertEquals('Callout', TypeCaption(Note));
  AssertEquals('Value 1', FieldCaption(Note.ValueField(0)));
end;

procedure TTestNotes.TestDraftSVGCallout;
var
  A: TPointObject;
  Note: TNoteObject;
  Text: string;
begin
  A := Pt('A', 0, 0);
  Note := FPattern.AddNote('', 'Centred', naPoint, A.Key, '', '20', '20', DEFAULT_NOTE_SIZE, True, nlDot);
  FPattern.SetNoteBoxed(Note, True);
  FPattern.SetNoteAlign(Note, taCentre);
  FPattern.Evaluate;
  Text := DraftToSVG(FPattern, DefaultDraftSVGOptions);
  AssertTrue('white box', Pos('fill="#ffffff"/>', Text) > 0);
  AssertTrue('dot at the tip', Pos('<circle data-id="' + Note.Key + '" cx="0" cy="0"', Text) > 0);
  AssertTrue('leader', Pos('<path data-id="' + Note.Key + '"', Text) > 0);
end;

initialization
  RegisterTest(TTestNotes);

end.
