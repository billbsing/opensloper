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

// Locked objects: locking is one undo step and is saved; a locked object
// cannot be moved, edited or deleted, by the pattern's own checks or by the
// document refusing a change that alters it, but its formulas still run.
unit Sloper.Tests.Locking;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece,
  Sloper.Core.Pattern, Sloper.Document.PatternDocument, Sloper.UI.SelectionEdits;

type
  TTestLocking = class(TOSTestCase)
  private
    FDocument: TPatternDocument;
    // A 100 mm square piece Front, corners A (0, 0), B, C and D, outline
    // edges AB, BC, CD and DA; E a free point inside it at (#w, 50)
    FA, FE, FAB, FPiece, FW: string;
    function Pattern: TPattern;
    function PointE: TPointObject;
    function Piece: TPieceObject;
    procedure Lock(const Key: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNothingLockedAtFirst;
    procedure TestLockIsOneUndoStep;
    procedure TestUnlock;
    procedure TestLockingSkipsWhatIsLocked;
    procedure TestLockedFormulasStillRun;
    procedure TestLockedRefusesEdits;
    procedure TestLockedCannotBeDragged;
    procedure TestDocumentRefusesChangeToLocked;
    procedure TestDocumentRefusesDeletingThroughOthers;
    procedure TestUnlockingIsItsOwnStep;
    procedure TestWholePatternChangeMayRewriteLocked;
    procedure TestVariableCannotBeLocked;
    procedure TestRepeatPointsFollowTheirRepeat;
    procedure TestLockedPieceTakesNoMarkings;
    procedure TestSavedAndLoaded;
    procedure TestPastedCopyIsUnlocked;
  end;

implementation

uses
  Sloper.Core.Evaluator, Sloper.Core.Drag, Sloper.Core.Fragment, Sloper.Core.PatternFile, Sloper.Core.PieceDetect;

procedure TTestLocking.SetUp;
var
  Path: TPiecePath;
  ErrorMessage, B, C, D: string;
begin
  FDocument := TPatternDocument.Create;
  FW := Pattern.AddVariable('w', '50').Key;
  FA := Pattern.AddFreePoint('A', '0', '0').Key;
  B := Pattern.AddFreePoint('B', '100', '0').Key;
  C := Pattern.AddFreePoint('C', '100', '100').Key;
  D := Pattern.AddFreePoint('D', '0', '100').Key;
  FE := Pattern.AddFreePoint('E', '#w', '50').Key;
  FAB := Pattern.AddLine(FA, B, erOutline).Key;
  Pattern.AddLine(B, C, erOutline);
  Pattern.AddLine(C, D, erOutline);
  Pattern.AddLine(D, FA, erOutline);
  Pattern.Evaluate;
  AssertTrue(ErrorMessage, DetectPiecePath(Pattern, Vec2(50, 50), Path, ErrorMessage));
  FPiece := Pattern.AddPiece('Front', Path, '10').Key;
  Pattern.Evaluate;
end;

procedure TTestLocking.TearDown;
begin
  FreeAndNil(FDocument);
end;

function TTestLocking.Pattern: TPattern;
begin
  Result := FDocument.Pattern;
end;

function TTestLocking.PointE: TPointObject;
begin
  Result := Pattern.FindNode(FE) as TPointObject;
end;

function TTestLocking.Piece: TPieceObject;
begin
  Result := Pattern.FindNode(FPiece) as TPieceObject;
end;

procedure TTestLocking.Lock(const Key: string);
var
  Edit: TSelectionEdit;
begin
  Edit := LockSelection(FDocument, [Key], True);
  AssertTrue('locked, else ' + Edit.Message, Edit.Done);
end;

procedure TTestLocking.TestNothingLockedAtFirst;
var
  Reason: string;
begin
  AssertFalse(Pattern.IsLocked(PointE));
  AssertFalse(Pattern.IsLocked(Piece));
  AssertTrue('A can be dragged', CanDrag(Pattern, Pattern.FindNode(FA) as TPointObject, Reason));
end;

procedure TTestLocking.TestLockIsOneUndoStep;
var
  Edit: TSelectionEdit;
begin
  Edit := LockSelection(FDocument, [FE, FPiece], True);
  AssertTrue(Edit.Done);
  AssertEquals('says what', Format(rsSelectionLocked, ['E, Front']), Edit.Message);
  AssertEquals('undo step', rsSelectionLock, FDocument.UndoDescription);
  AssertTrue(Pattern.IsLocked(PointE));
  AssertTrue(Pattern.IsLocked(Piece));
  AssertTrue(FDocument.Undo);
  AssertFalse('undone', Pattern.IsLocked(PointE));
  AssertFalse('one step', FDocument.CanUndo);
  AssertTrue(FDocument.Redo);
  AssertTrue('redone', Pattern.IsLocked(PointE));
end;

procedure TTestLocking.TestUnlock;
var
  Edit: TSelectionEdit;
begin
  Lock(FE);
  Edit := LockSelection(FDocument, [FE], False);
  AssertTrue(Edit.Done);
  AssertEquals(Format(rsSelectionUnlocked, ['E']), Edit.Message);
  AssertEquals(rsSelectionUnlock, FDocument.UndoDescription);
  AssertFalse(Pattern.IsLocked(PointE));
  AssertTrue('editable again', Pattern.SetFormula(PointE, 'y', '60'));
end;

procedure TTestLocking.TestLockingSkipsWhatIsLocked;
var
  Edit: TSelectionEdit;
begin
  Lock(FE);
  Edit := LockSelection(FDocument, [FE], True);
  AssertFalse('nothing to lock', Edit.Done);
  Edit := LockSelection(FDocument, [], True);
  AssertEquals(rsSelectionPickToLock, Edit.Message);
end;

procedure TTestLocking.TestLockedFormulasStillRun;
begin
  Lock(FE);
  FDocument.BeginChange('Change w');
  AssertTrue(Pattern.SetFormula(Pattern.FindNode(FW), 'formula', '70'));
  AssertTrue('a change to what it reads is not refused', FDocument.EndChange);
  AssertFalse(FDocument.ChangeRefused);
  AssertNear('E follows #w', 70, PointE.Position.X);
end;

procedure TTestLocking.TestLockedRefusesEdits;
var
  Locked: string;
begin
  Lock(FE);
  Locked := Format(rsPatternLocked, ['E']);
  AssertFalse('formula', Pattern.SetFormula(PointE, 'y', '60'));
  AssertEquals(Locked, Pattern.LastError);
  AssertFalse('rename', Pattern.Rename(PointE, 'F'));
  AssertEquals(Locked, Pattern.LastError);
  AssertFalse('delete', Pattern.Delete(PointE));
  AssertEquals(Locked, Pattern.LastError);
  AssertEquals('delete from the canvas', Locked, DeleteSelection(FDocument, [FE], rsSelectionDelete).Message);
  AssertNotNull('still there', Pattern.FindNode(FE));
end;

procedure TTestLocking.TestLockedCannotBeDragged;
var
  Reason: string;
  Edit: TSelectionEdit;
begin
  Pattern.SetFormula(PointE, 'x', '50');
  Lock(FE);
  AssertFalse(CanDrag(Pattern, PointE, Reason));
  AssertEquals(Format(rsDragLocked, ['E']), Reason);
  Edit := NudgeSelection(FDocument, [FE], Vec2(1, 0));
  AssertFalse(Edit.Done);
  AssertEquals(Format(rsDragLocked, ['E']), Edit.Message);
  AssertNear('not moved', 50, PointE.Position.X);
  AssertFalse('no change left open', FDocument.ChangeOpen);
end;

// SetCut has no lock check of its own: the document catches it
procedure TTestLocking.TestDocumentRefusesChangeToLocked;
begin
  Lock(FPiece);
  FDocument.BeginChange('Cut');
  AssertTrue(Pattern.SetCut(Piece, 2, True));
  AssertFalse('refused', FDocument.EndChange);
  AssertTrue(FDocument.ChangeRefused);
  AssertEquals(Format(rsPatternLocked, ['Front']), Pattern.LastError);
  AssertEquals('put back', 1, Piece.CutCount);
  AssertEquals('no step', rsSelectionLock, FDocument.UndoDescription);
  AssertFalse('no change left open', FDocument.ChangeOpen);
end;

procedure TTestLocking.TestDocumentRefusesDeletingThroughOthers;
var
  Edit: TSelectionEdit;
  Line: string;
begin
  // Deleting a line the piece only prints would take the piece's marking with it
  Line := Pattern.AddLine(FA, FE, erStitch).Key;
  Pattern.Evaluate;
  AssertEquals('marked on the piece', 1, Length(Piece.Markings));
  Lock(FPiece);
  Edit := DeleteSelection(FDocument, [Line], rsSelectionDelete);
  AssertFalse(Edit.Done);
  AssertEquals(Format(rsPatternLocked, ['Front']), Edit.Message);
  AssertEquals('marking kept', 1, Length(Piece.Markings));
end;

procedure TTestLocking.TestUnlockingIsItsOwnStep;
begin
  Lock(FE);
  FDocument.BeginChange('Unlock and move');
  AssertTrue(Pattern.SetLocked(PointE, False));
  AssertTrue(Pattern.SetFormula(PointE, 'y', '60'));
  AssertFalse('refused', FDocument.EndChange);
  AssertTrue(Pattern.IsLocked(PointE));
  AssertNear('not moved', 50, PointE.Position.Y);
end;

procedure TTestLocking.TestWholePatternChangeMayRewriteLocked;
begin
  Lock(FE);
  FDocument.BeginChange('Convert', False);
  AssertTrue(Pattern.SetStoredFormula(PointE, 'y', '5'));
  AssertTrue(FDocument.EndChange);
  AssertNear('converted', 5, PointE.Position.Y);
end;

procedure TTestLocking.TestVariableCannotBeLocked;
begin
  AssertFalse(Pattern.SetLocked(Pattern.FindNode(FW), True));
  AssertEquals(Format(rsPatternCannotLock, ['#w']), Pattern.LastError);
  AssertFalse(Pattern.IsLocked(Pattern.FindNode(FW)));
end;

procedure TTestLocking.TestRepeatPointsFollowTheirRepeat;
var
  Repeat_: TRepeatObject;
  Item: TEvalNode;
begin
  Repeat_ := Pattern.AddRepeatBetween('R', FA, FE, '3', True);
  Pattern.Evaluate;
  Item := Repeat_.Item(1);
  AssertTrue('a point locks its repeat', Pattern.SetLocked(Item, True));
  AssertTrue(Repeat_.Locked);
  AssertTrue('its points are locked', Pattern.IsLocked(Item));
  AssertFalse(Pattern.Delete(Item));
  // Using one of its points changes no definition of the repeat
  FDocument.BeginChange('Line');
  AssertNotNull(Pattern.AddLine(Pattern.UsePoint(Repeat_.Item(2).Key), FE));
  AssertTrue('not refused', FDocument.EndChange);
end;

procedure TTestLocking.TestLockedPieceTakesNoMarkings;
begin
  Lock(FPiece);
  FDocument.BeginChange('Add stitch line');
  AssertNotNull(Pattern.AddLine(FA, FE, erStitch));
  AssertTrue('not refused', FDocument.EndChange);
  AssertEquals('not marked on the locked piece', 0, Length(Piece.Markings));
end;

procedure TTestLocking.TestSavedAndLoaded;
var
  Text, Err: string;
  Loaded: TPattern;
begin
  Text := SavePatternToText(Pattern);
  AssertEquals('nothing written while unlocked', 0, Pos('"locked"', Text));
  Lock(FE);
  Text := SavePatternToText(Pattern);
  AssertTrue(Pos('"locked": true', Text) > 0);
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, Text, Err));
    AssertTrue(Loaded.FindObject('E').Locked);
    AssertFalse(Loaded.FindObject('A').Locked);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestLocking.TestPastedCopyIsUnlocked;
var
  Copied: TFragmentCopy;
  Edit: TSelectionEdit;
begin
  Lock(FE);
  Edit := CopySelection(FDocument, [FE], Copied);
  AssertTrue(Edit.Done);
  Edit := PasteFragmentText(FDocument, Copied.Text);
  AssertTrue(Edit.Message, Edit.Done);
  AssertFalse('the copy is unlocked', Pattern.IsLocked(Pattern.FindNode(Edit.Selection[0])));
  AssertTrue('the original stays locked', Pattern.IsLocked(PointE));
end;

initialization
  RegisterTest(TTestLocking);
end.
