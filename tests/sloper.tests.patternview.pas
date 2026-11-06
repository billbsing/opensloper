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

// The canvas view saved with a pattern, and files from before drafts and
// layers were taken out.
unit Sloper.Tests.PatternView;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern;

type
  TTestPatternView = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Reloaded: TPattern;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSimpleFileStaysSimple;
    procedure TestViewSavedInFile;
    procedure TestViewNotInUndoSnapshot;
    procedure TestOddViewPassedOver;
    procedure TestUndoKeepsView;
    procedure TestViewIsNotAChange;
    procedure TestOldDraftsLoadOnOneCanvas;
    procedure TestOldDraftIdsStayRetired;
    procedure TestOldFileSavesWithoutDrafts;
    procedure TestHiddenRolesSaved;
    procedure TestHiddenRolesKeptOutOfUndo;
    procedure TestOutlineNeverHidden;
  end;

implementation

uses
  Sloper.Core.Draft, Sloper.Core.PatternFile, Sloper.Document.PatternDocument;

const
  // Two drafts, the second with two layers, and a point on each
  OldFile = '{"format": "pattern", "version": 1, ' +
    '"drafts": [{"id": 1, "name": "Draft", "layers": [{"id": 2, "name": "Draft"}]}, ' +
    '{"id": 3, "name": "Sleeve", "layers": [{"id": 4, "name": "Draft"}, {"id": 40, "name": "Dart"}]}], ' +
    '"objects": [{"id": 5, "type": "freePoint", "name": "A", "x": "0", "y": "0", "layer": 2}, ' +
    '{"id": 6, "type": "freePoint", "name": "B", "x": "10", "y": "0", "layer": 40}], ' +
    '"view": {"draft": 3, "drafts": {"3": {"activeLayer": 40, "hidden": [4]}}}}';

procedure TTestPatternView.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestPatternView.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

function TTestPatternView.Reloaded: TPattern;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Err));
  Result := FLoaded;
end;

procedure TTestPatternView.TestSimpleFileStaysSimple;
var
  Text: string;
begin
  FPattern.AddFreePoint('A', '0', '0');
  Text := SavePatternToText(FPattern);
  AssertEquals('no drafts', 0, Pos('"drafts"', Text));
  AssertEquals('no layer', 0, Pos('"layer"', Text));
  AssertEquals('no view until the canvas has shown it', 0, Pos('"view"', Text));
end;

procedure TTestPatternView.TestViewSavedInFile;
var
  Loaded: TPattern;
begin
  FPattern.View.HasView := True;
  FPattern.View.Zoom := 1.5;
  FPattern.View.CentreX := 120;
  FPattern.View.CentreY := -200;
  Loaded := Reloaded;
  AssertTrue('has a view', Loaded.View.HasView);
  AssertNear('zoom', 1.5, Loaded.View.Zoom);
  AssertNear('centre x', 120, Loaded.View.CentreX);
  AssertNear('centre y', -200, Loaded.View.CentreY);
end;

procedure TTestPatternView.TestViewNotInUndoSnapshot;
var
  Before: string;
begin
  Before := SavePatternToText(FPattern, False);
  FPattern.View.HasView := True;
  FPattern.View.Zoom := 2;
  AssertEquals('no change to undo', Before, SavePatternToText(FPattern, False));
end;

procedure TTestPatternView.TestOddViewPassedOver;
begin
  RestorePatternView(FPattern, '{"zoom": "big", "centre": [1]}');
  AssertFalse('no view', FPattern.View.HasView);
  RestorePatternView(FPattern, '{"zoom": -1, "centre": [1, 2]}');
  AssertFalse('no negative zoom', FPattern.View.HasView);
end;

procedure TTestPatternView.TestUndoKeepsView;
var
  Document: TPatternDocument;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add point');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.EndChange;
    Document.Pattern.View.HasView := True;
    Document.Pattern.View.Zoom := 3;
    Document.Undo;
    AssertNear('zoom kept', 3, Document.Pattern.View.Zoom);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestPatternView.TestViewIsNotAChange;
var
  Document: TPatternDocument;
begin
  Document := TPatternDocument.Create;
  try
    Document.Pattern.View.HasView := True;
    Document.Pattern.View.Zoom := 3;
    Document.ViewChanged;
    AssertFalse('not modified', Document.Modified);
    AssertFalse('nothing to undo', Document.CanUndo);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestPatternView.TestOldDraftsLoadOnOneCanvas;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, OldFile, Err));
  AssertEquals('both points', 2, FLoaded.ObjectCount);
  AssertNotNull('A', FLoaded.FindObject('A'));
  AssertNotNull('B, from a hidden layer on another draft', FLoaded.FindObject('B'));
  AssertFalse('the old view is passed over', FLoaded.View.HasView);
end;

procedure TTestPatternView.TestOldDraftIdsStayRetired;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, OldFile, Err));
  AssertEquals('above the highest layer ID', '41', FLoaded.AddFreePoint('C', '0', '0').Key);
end;

procedure TTestPatternView.TestOldFileSavesWithoutDrafts;
var
  Err, Text: string;
begin
  AssertTrue(Err, LoadPatternFromText(FPattern, OldFile, Err));
  Text := SavePatternToText(FPattern);
  AssertEquals('no drafts', 0, Pos('"drafts"', Text));
  AssertEquals('no layer', 0, Pos('"layer"', Text));
  AssertTrue('the counter stays above the old IDs', Pos('"nextId": 41', Text) > 0);
end;

procedure TTestPatternView.TestHiddenRolesSaved;
begin
  FPattern.View.HiddenRoles := [erConstruction, erEdgeFinish];
  AssertTrue('written', Pos('"hiddenRoles"', SavePatternToText(FPattern)) > 0);
  AssertTrue(Reloaded.View.HiddenRoles = [erConstruction, erEdgeFinish]);
  AssertFalse('no zoom yet', FLoaded.View.HasView);
  FPattern.View.HiddenRoles := [];
  AssertEquals('left out when all show', 0, Pos('hiddenRoles', SavePatternToText(FPattern)));
end;

procedure TTestPatternView.TestHiddenRolesKeptOutOfUndo;
var
  Document: TPatternDocument;
  Before: string;
begin
  Before := SavePatternToText(FPattern, False);
  FPattern.View.HiddenRoles := [erStitch];
  AssertEquals('no change to undo', Before, SavePatternToText(FPattern, False));
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add point');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.EndChange;
    Document.Pattern.View.HiddenRoles := [erFold];
    Document.ViewChanged;
    Document.Undo;
    AssertTrue('kept through undo', Document.Pattern.View.HiddenRoles = [erFold]);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestPatternView.TestOutlineNeverHidden;
begin
  RestorePatternView(FPattern, '{"hiddenRoles": ["outline", "stitch", "nonsense", 3]}');
  AssertTrue(FPattern.View.HiddenRoles = [erStitch]);
end;

initialization
  RegisterTest(TTestPatternView);

end.
