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
    procedure TestPieceNotesOnlyPrinting;
    procedure TestPieceMovingKeepsNoteAfterIt;
    procedure TestProblems;
    procedure TestFieldValues;
    procedure TestBoundsIncludeNotes;
    procedure TestTextToolAnchors;
    procedure TestNotesAtTopmostAndHidden;
    procedure TestObjectRows;
    procedure TestDraftSVG;
  end;

implementation

uses
  Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.Core.PieceDetect, Sloper.Core.Drag, Sloper.Core.Bounds, Sloper.Core.TextFields,
  Sloper.Core.Measurements, Sloper.Core.Settings, Sloper.Document.PatternDocument, Sloper.UI.Snap, Sloper.UI.Scene, Sloper.UI.ObjectList, Sloper.Output.DraftSVG;

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
  AssertEquals('x', '12.5', FPattern.FormulaText(Note, NoteXField));
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
  AssertFalse(FPattern.SetNoteSize(Note, MaxNoteSize + 1));
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
  AssertEquals('dx', '15', FPattern.FormulaText(Note, NoteDxField));
  AssertEquals('dy', '-8', FPattern.FormulaText(Note, NoteDyField));
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
  AssertEquals('kept', 'A.x / 2', FPattern.FormulaText(Note, NoteDxField));
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
  AssertEquals('text', 'On an edge', Note.Text);
  AssertNear('size', 12, Note.Size);
  AssertFalse('screen only', Note.Print);
  AssertTrue(Note.Anchor = naEdge);
  AssertEquals('position', '0.5', FLoaded.FormulaText(Note, NotePositionField));
  AssertEquals('two lines', 'On a point' + #10 + 'second line', TNoteObject(FLoaded.FindObject('Note')).Text);
end;

procedure TTestNotes.TestLoadRefusesBadAnchor;
const
  Head = '{"format": "pattern", "version": 1, "objects": [{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}, ';
var
  Err: string;
begin
  AssertFalse('point as edge', LoadPatternFromText(FLoaded, Head +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"edge": 1, "position": "0"}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('later object', LoadPatternFromText(FLoaded, Head +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 5}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('two anchors', LoadPatternFromText(FLoaded, Head +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1, "piece": 1}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertFalse('no text', LoadPatternFromText(FLoaded, Head +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1}, "dx": "0", "dy": "0"}]}', Err));
  AssertTrue(Err, LoadPatternFromText(FLoaded, Head +
    '{"id": 2, "type": "note", "name": "N", "anchor": {"point": 1}, "dx": "0", "dy": "0", "text": "x"}]}', Err));
  AssertNear('default size', DefaultNoteSize, TNoteObject(FLoaded.FindObject('N')).Size);
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

procedure TTestNotes.TestPieceNotesOnlyPrinting;
var
  Front: TPieceObject;
  Top: string;
  Notes: TNoteObjectArray;
begin
  Front := Square('Front', 0, 100, Top);
  FPattern.AddNote('Shown', 'a', naPiece, Front.Key, '', '0', '0', DefaultNoteSize, False);
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
  FPattern.AddNote('Private', 'b', naFree, '', '', '500', '500', DefaultNoteSize, False);
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
  AssertEquals('dx', '1', FPattern.FormulaText(Note, NoteDxField));
  // On an edge, as a ratio along it
  Snap := FindSnap(FPattern, Vec2(25, 1), 3);
  AssertTrue('snaps to the top', Snap.Kind = snEdge);
  Note := NoteFromSnap(FPattern, Snap, Vec2(25, 1), 'b');
  AssertTrue('edge anchor', Note.Anchor = naEdge);
  AssertEquals('the top', Top, Note.AnchorKey);
  AssertEquals('a quarter along', '0.25', FPattern.FormulaText(Note, NotePositionField));
  AssertEquals('dy', '1', FPattern.FormulaText(Note, NoteDyField));
  // Inside the piece, away from its edges
  Snap := FindSnap(FPattern, Vec2(30, 60), 3);
  Note := NoteFromSnap(FPattern, Snap, Vec2(30, 60), 'c');
  AssertTrue('piece anchor ' + NoteAnchorNames[Note.Anchor], Note.Anchor = naPiece);
  AssertEquals('the piece', Front.Key, Note.AnchorKey);
  FPattern.Evaluate;
  AssertPointsNear('where it was clicked', Vec2(30, 60), Note.Position, 0.06);
  // Outside everything
  Snap := FindSnap(FPattern, Vec2(300, 300), 3);
  Note := NoteFromSnap(FPattern, Snap, Vec2(300, 300), 'd');
  AssertTrue('free', Note.Anchor = naFree);
  AssertEquals('x', '300', FPattern.FormulaText(Note, NoteXField));
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
  FPattern.AddNote('', 'Mine', naFree, '', '', '10', '30', DefaultNoteSize, False);
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

initialization
  RegisterTest(TTestNotes);

end.
