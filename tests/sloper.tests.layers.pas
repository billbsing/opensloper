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

// Drafts and layers: the model, files, what shows, and undo.
unit Sloper.Tests.Layers;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Drafts,
  Sloper.Core.Draft, Sloper.Core.Piece;

type
  TTestLayers = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Pt(const AName: string; X: double = 0): TFreePoint;
    function Reloaded: TPattern;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNewPatternHasOneDraftOneLayer;
    procedure TestSimpleFileStaysSimple;
    procedure TestFileWithoutDraftsLoads;
    procedure TestIdsStayWhereTheyWere;
    procedure TestAddingDraftWritesDrafts;
    procedure TestExplicitIdsFollowObjects;
    procedure TestRoundTrip;
    procedure TestSavedTwiceIsTheSame;
    procedure TestRefusesRepeatedDraftId;
    procedure TestRefusesUnknownLayer;
    procedure TestRefusesEmptyDrafts;
    procedure TestNewObjectGoesOnActiveLayer;
    procedure TestNamesDefaultToNextFree;
    procedure TestLayerNameMayRepeatAcrossDrafts;
    procedure TestRefusesTakenDraftName;
    procedure TestRefusesTakenLayerName;
    procedure TestRefusesEmptyName;
    procedure TestMoveLayerUpAndDown;
    procedure TestMoveDraft;
    procedure TestMoveToLayer;
    procedure TestMoveToLayerStaysOnDraft;
    procedure TestDeleteLastLayerRefused;
    procedure TestDeleteLastDraftRefused;
    procedure TestDeleteLayerTakesItsObjects;
    procedure TestDeleteLayerInUseRefused;
    procedure TestDeleteDraftInUseRefused;
    procedure TestDeleteDraftChoosesAnother;
    procedure TestDirectInputOnOtherDraftRefused;
    procedure TestFormulaMayReadOtherDraft;
    procedure TestSeamMayCrossDrafts;
    procedure TestHiddenIsNotShown;
    procedure TestSoloShowsOneLayer;
    procedure TestLockedIsShownNotPickable;
    procedure TestOtherDraftIsNotShown;
    procedure TestRepeatPointFollowsItsRepeat;
    procedure TestViewSavedInFile;
    procedure TestViewNotInUndoSnapshot;
    procedure TestViewSkipsWhatHasGone;
    procedure TestPieceDetectionSkipsHiddenLayer;
    procedure TestPieceDetectionStaysOnItsDraft;
    procedure TestBoundsOfActiveDraftOnly;
    procedure TestShownObjectsGoInLayerOrder;
    procedure TestShownObjectsLeaveOutHidden;
    procedure TestTopLayerPointWins;
    procedure TestPointPickSkipsLockedAndHidden;
    procedure TestEdgePickSkipsLocked;
    procedure TestSnapSkipsHiddenButNotLocked;
    procedure TestHidingLeavesOutputAlone;
    procedure TestUndoShowsChangedDraft;
    procedure TestUndoKeepsView;
    procedure TestHidingIsNotAChange;
  end;

implementation

uses
  Sloper.Core.Bounds, Sloper.Core.Garment, Sloper.Core.PatternFile, Sloper.Core.PieceDetect, Sloper.Core.Seam, Sloper.Core.Variables,
  Sloper.Document.PatternDocument,
  Sloper.UI.Scene, Sloper.UI.Snap;

procedure TTestLayers.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestLayers.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

function TTestLayers.Pt(const AName: string; X: double): TFreePoint;
begin
  Result := FPattern.AddFreePoint(AName, IntToStr(Round(X)), '0');
  AssertNotNull(FPattern.LastError, Result);
end;

function TTestLayers.Reloaded: TPattern;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, SavePatternToText(FPattern), Err));
  Result := FLoaded;
end;

procedure TTestLayers.TestNewPatternHasOneDraftOneLayer;
begin
  AssertEquals('one draft', 1, FPattern.DraftCount);
  AssertEquals('one layer', 1, FPattern.Drafts[0].Layers.Count);
  AssertEquals(DefaultDraftName, FPattern.Drafts[0].Name);
  AssertEquals(DefaultLayerName, FPattern.ActiveLayer.Name);
end;

procedure TTestLayers.TestSimpleFileStaysSimple;
var
  Text: string;
begin
  Pt('A');
  Text := SavePatternToText(FPattern);
  AssertEquals('no drafts', 0, Pos('"drafts"', Text));
  AssertEquals('no layer', 0, Pos('"layer"', Text));
  AssertEquals('no view', 0, Pos('"view"', Text));
end;

procedure TTestLayers.TestFileWithoutDraftsLoads;
var
  Err: string;
begin
  AssertTrue(Err, LoadPatternFromText(FLoaded, '{"format": "pattern", "version": 1, "objects": [{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}]}',
    Err));
  AssertEquals('one draft', 1, FLoaded.DraftCount);
  AssertTrue('on the layer', FLoaded.LayerOf(FLoaded.FindObject('A')) = FLoaded.ActiveLayer);
end;

procedure TTestLayers.TestIdsStayWhereTheyWere;
begin
  AssertEquals('the first object is still 1', '1', Pt('A').Key);
end;

procedure TTestLayers.TestAddingDraftWritesDrafts;
var
  Text: string;
begin
  Pt('A');
  FPattern.AddDraft('Sleeve');
  Text := SavePatternToText(FPattern);
  AssertTrue('drafts', Pos('"drafts"', Text) > 0);
  AssertTrue('layer', Pos('"layer"', Text) > 0);
  AssertTrue('view', Pos('"view"', Text) > 0);
end;

procedure TTestLayers.TestExplicitIdsFollowObjects;
var
  A: TFreePoint;
begin
  A := Pt('A');
  FPattern.AddDraft('Sleeve');
  AssertEquals('object keeps its ID', '1', A.Key);
  AssertEquals('first draft next', '2', FPattern.Drafts[0].Key);
  AssertEquals('first layer next', '3', FPattern.Drafts[0].Layers[0].Key);
  AssertEquals('moved onto it', '3', A.LayerKey);
  AssertEquals('then the new draft', '4', FPattern.Drafts[1].Key);
  AssertEquals('and its layer', '5', FPattern.Drafts[1].Layers[0].Key);
  AssertEquals('next object above them', '6', Pt('B').Key);
end;

procedure TTestLayers.TestRoundTrip;
var
  Loaded: TPattern;
  Sleeve: TPatternDraft;
begin
  Pt('A');
  Sleeve := FPattern.AddDraft('Sleeve');
  FPattern.AddLayer(Sleeve, 'Side dart');
  FPattern.ActiveDraft := Sleeve;
  Pt('B');
  Loaded := Reloaded;
  AssertEquals('drafts', 2, Loaded.DraftCount);
  AssertEquals('Sleeve', Loaded.Drafts[1].Name);
  AssertEquals('Side dart', Loaded.Drafts[1].Layers[1].Name);
  AssertEquals('B stays there', 'Sleeve', Loaded.DraftOf(Loaded.FindObject('B')).Name);
  AssertEquals('A stays', 'Draft', Loaded.DraftOf(Loaded.FindObject('A')).Name);
end;

procedure TTestLayers.TestSavedTwiceIsTheSame;
var
  Sleeve: TPatternDraft;
begin
  Pt('A');
  Sleeve := FPattern.AddDraft('Sleeve');
  FPattern.AddLayer(Sleeve);
  AssertEquals(SavePatternToText(FPattern), SavePatternToText(Reloaded));
end;

procedure TTestLayers.TestRefusesRepeatedDraftId;
var
  Err: string;
begin
  AssertFalse('repeated', LoadPatternFromText(FLoaded,
    '{"format": "pattern", "version": 1, "drafts": [{"id": 1, "name": "A", "layers": [{"id": 1, "name": "L"}]}]}', Err));
  AssertFalse('object on it', LoadPatternFromText(FLoaded,
    '{"format": "pattern", "version": 1, "drafts": [{"id": 1, "name": "A", "layers": [{"id": 2, "name": "L"}]}],' +
    ' "objects": [{"id": 2, "type": "freePoint", "name": "A", "x": "0", "y": "0"}]}', Err));
end;

procedure TTestLayers.TestRefusesUnknownLayer;
var
  Err: string;
begin
  AssertFalse('no such layer', LoadPatternFromText(FLoaded,
    '{"format": "pattern", "version": 1, "drafts": [{"id": 1, "name": "A", "layers": [{"id": 2, "name": "L"}]}],' +
    ' "objects": [{"id": 3, "type": "freePoint", "name": "A", "layer": 9, "x": "0", "y": "0"}]}', Err));
end;

procedure TTestLayers.TestRefusesEmptyDrafts;
var
  Err: string;
begin
  AssertFalse('no drafts', LoadPatternFromText(FLoaded, '{"format": "pattern", "version": 1, "drafts": []}', Err));
  AssertFalse('no layers', LoadPatternFromText(FLoaded, '{"format": "pattern", "version": 1, "drafts": [{"id": 1, "name": "A", "layers": []}]}', Err));
end;

procedure TTestLayers.TestNewObjectGoesOnActiveLayer;
var
  Layer: TPatternLayer;
begin
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  FPattern.SelectLayer(Layer);
  AssertTrue('on it', FPattern.LayerOf(Pt('A')) = Layer);
end;

procedure TTestLayers.TestNamesDefaultToNextFree;
begin
  AssertEquals('Draft2', FPattern.AddDraft.Name);
  AssertEquals('Draft3', FPattern.AddDraft.Name);
  AssertEquals('Draft2', FPattern.AddLayer(FPattern.ActiveDraft).Name);
end;

procedure TTestLayers.TestLayerNameMayRepeatAcrossDrafts;
var
  Sleeve: TPatternDraft;
begin
  Sleeve := FPattern.AddDraft('Sleeve');
  AssertEquals('Draft', Sleeve.Layers[0].Name);
  AssertNotNull(FPattern.LastError, FPattern.AddLayer(Sleeve, 'Side dart'));
  AssertNotNull(FPattern.LastError, FPattern.AddLayer(FPattern.Drafts[0], 'Side dart'));
end;

procedure TTestLayers.TestRefusesTakenDraftName;
var
  Sleeve: TPatternDraft;
begin
  Sleeve := FPattern.AddDraft('Sleeve');
  AssertNull('added', FPattern.AddDraft('SLEEVE'));
  AssertEquals(Format(rsPatternDraftTaken, ['SLEEVE']), FPattern.LastError);
  AssertFalse('renamed', FPattern.RenameDraft(FPattern.Drafts[0], 'sleeve'));
  AssertTrue('its own, in new case', FPattern.RenameDraft(Sleeve, 'SLEEVE'));
end;

procedure TTestLayers.TestRefusesTakenLayerName;
var
  Layer: TPatternLayer;
begin
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  AssertNull('added', FPattern.AddLayer(FPattern.ActiveDraft, 'DART'));
  AssertFalse('renamed', FPattern.RenameLayer(FPattern.ActiveDraft, FPattern.ActiveDraft.Layers[0], 'dart'));
  AssertTrue('its own', FPattern.RenameLayer(FPattern.ActiveDraft, Layer, 'Darts'));
end;

procedure TTestLayers.TestRefusesEmptyName;
begin
  AssertFalse('draft', FPattern.RenameDraft(FPattern.ActiveDraft, '  '));
  AssertFalse('layer', FPattern.RenameLayer(FPattern.ActiveDraft, FPattern.ActiveLayer, ''));
end;

procedure TTestLayers.TestMoveLayerUpAndDown;
var
  Draft: TPatternDraft;
  Top: TPatternLayer;
begin
  Draft := FPattern.ActiveDraft;
  Top := FPattern.AddLayer(Draft, 'Top');
  AssertFalse('already top', FPattern.MoveLayer(Draft, Top, 1));
  AssertTrue('down', FPattern.MoveLayer(Draft, Top, -1));
  AssertEquals('at the bottom', 0, Draft.IndexOfLayer(Top));
  AssertFalse('already bottom', FPattern.MoveLayer(Draft, Top, -1));
end;

procedure TTestLayers.TestMoveDraft;
var
  Sleeve: TPatternDraft;
begin
  Sleeve := FPattern.AddDraft('Sleeve');
  AssertTrue('first', FPattern.MoveDraft(Sleeve, 0));
  AssertEquals('Sleeve', FPattern.Drafts[0].Name);
  AssertFalse('off the end', FPattern.MoveDraft(Sleeve, 5));
end;

procedure TTestLayers.TestMoveToLayer;
var
  A: TFreePoint;
  Layer: TPatternLayer;
begin
  A := Pt('A');
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  AssertTrue(FPattern.LastError, FPattern.MoveToLayer(A, Layer));
  AssertTrue('moved', FPattern.LayerOf(A) = Layer);
end;

procedure TTestLayers.TestMoveToLayerStaysOnDraft;
var
  A: TFreePoint;
  Sleeve: TPatternDraft;
begin
  A := Pt('A');
  Sleeve := FPattern.AddDraft('Sleeve');
  AssertFalse('refused', FPattern.MoveToLayer(A, Sleeve.Layers[0]));
end;

procedure TTestLayers.TestDeleteLastLayerRefused;
begin
  AssertFalse('refused', FPattern.DeleteLayer(FPattern.ActiveDraft, FPattern.ActiveLayer));
  AssertEquals(rsPatternLastLayer, FPattern.LastError);
end;

procedure TTestLayers.TestDeleteLastDraftRefused;
begin
  AssertFalse('refused', FPattern.DeleteDraft(FPattern.ActiveDraft));
  AssertEquals(rsPatternLastDraft, FPattern.LastError);
end;

procedure TTestLayers.TestDeleteLayerTakesItsObjects;
var
  Layer: TPatternLayer;
  A, B: TFreePoint;
begin
  A := Pt('A');
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  FPattern.SelectLayer(Layer);
  B := Pt('B', 10);
  FPattern.AddLine(B.Key, Pt('C', 20).Key);
  AssertTrue(FPattern.LastError, FPattern.DeleteLayer(FPattern.ActiveDraft, Layer));
  AssertEquals('only A left', 1, FPattern.ObjectCount);
  AssertTrue('A', FPattern.Objects[0] = A);
  AssertEquals('one layer', 1, FPattern.ActiveDraft.Layers.Count);
  AssertNotNull('still somewhere to draw', FPattern.ActiveLayer);
end;

procedure TTestLayers.TestDeleteLayerInUseRefused;
var
  Layer: TPatternLayer;
  B: TFreePoint;
begin
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  FPattern.SelectLayer(Layer);
  B := Pt('B', 10);
  FPattern.SelectLayer(FPattern.ActiveDraft.Layers[0]);
  FPattern.AddLine(Pt('A').Key, B.Key);
  AssertFalse('used from the other layer', FPattern.DeleteLayer(FPattern.ActiveDraft, Layer));
  AssertEquals('nothing went', 3, FPattern.ObjectCount);
end;

procedure TTestLayers.TestDeleteDraftInUseRefused;
var
  First, Sleeve: TPatternDraft;
  B: TFreePoint;
begin
  First := FPattern.ActiveDraft;
  Sleeve := FPattern.AddDraft('Sleeve');
  FPattern.ActiveDraft := Sleeve;
  B := Pt('B');
  FPattern.ActiveDraft := First;
  AssertNotNull(FPattern.LastError, FPattern.AddFreePoint('C', 'B.x', '0'));
  AssertFalse('a formula reads it', FPattern.DeleteDraft(Sleeve));
  AssertEquals('nothing went', 2, FPattern.ObjectCount);
  AssertNotNull('B stays', FPattern.FindNode(B.Key));
end;

procedure TTestLayers.TestDeleteDraftChoosesAnother;
var
  Sleeve: TPatternDraft;
begin
  Sleeve := FPattern.AddDraft('Sleeve');
  FPattern.ActiveDraft := Sleeve;
  Pt('B');
  AssertTrue(FPattern.LastError, FPattern.DeleteDraft(Sleeve));
  AssertEquals('drafts', 1, FPattern.DraftCount);
  AssertTrue('active', FPattern.ActiveDraft = FPattern.Drafts[0]);
  AssertEquals('its objects went', 0, FPattern.ObjectCount);
end;

procedure TTestLayers.TestDirectInputOnOtherDraftRefused;
var
  A: TFreePoint;
begin
  A := Pt('A');
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  AssertNull('a line to it', FPattern.AddLine(A.Key, Pt('B').Key));
  AssertEquals(Format(rsPatternOtherDraft, ['A']), FPattern.LastError);
end;

procedure TTestLayers.TestFormulaMayReadOtherDraft;
begin
  Pt('A', 25);
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  AssertNotNull(FPattern.LastError, FPattern.AddFreePoint('B', 'A.x * 2', '0'));
  FPattern.Evaluate;
  AssertNear('read', 50, TFreePoint(FPattern.FindObject('B')).Position.X);
end;

procedure TTestLayers.TestSeamMayCrossDrafts;

  function Square(Left: integer): TPieceObject;
  var
    A, B, C, D, Reason: string;
    Path: TPiecePath;
  begin
    A := FPattern.AddFreePoint('', IntToStr(Left), '0').Key;
    B := FPattern.AddFreePoint('', IntToStr(Left + 100), '0').Key;
    C := FPattern.AddFreePoint('', IntToStr(Left + 100), '100').Key;
    D := FPattern.AddFreePoint('', IntToStr(Left), '100').Key;
    FPattern.AddLine(A, B, erOutline);
    FPattern.AddLine(B, C, erOutline);
    FPattern.AddLine(C, D, erOutline);
    FPattern.AddLine(D, A, erOutline);
    FPattern.Evaluate;
    AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + 50, 50), Path, Reason));
    Result := FPattern.AddPiece('', Path, '10');
  end;

var
  Front, Back: TPieceObject;
  SideA, SideB: TSeamSide;
begin
  Front := Square(0);
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  Back := Square(0);
  SideA := nil;
  SideB := nil;
  SetLength(SideA, 1);
  SetLength(SideB, 1);
  SideA[0].PieceKey := Front.Key;
  SideA[0].EdgeKey := Front.Path[0].EdgeKey;
  SideB[0].PieceKey := Back.Key;
  SideB[0].EdgeKey := Back.Path[0].EdgeKey;
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('', SideA, SideB));
end;

procedure TTestLayers.TestHiddenIsNotShown;
var
  A: TFreePoint;
begin
  A := Pt('A');
  AssertTrue('shown', FPattern.IsShown(A));
  FPattern.ActiveLayer.Hidden := True;
  AssertFalse('hidden', FPattern.IsShown(A));
  AssertFalse('so not pickable', FPattern.IsPickable(A));
end;

procedure TTestLayers.TestSoloShowsOneLayer;
var
  A, B: TFreePoint;
  Layer: TPatternLayer;
begin
  A := Pt('A');
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  FPattern.SelectLayer(Layer);
  B := Pt('B');
  FPattern.SoloLayer := Layer;
  AssertFalse('the other', FPattern.IsShown(A));
  AssertTrue('this one', FPattern.IsShown(B));
  FPattern.SoloLayer := nil;
  AssertTrue('back', FPattern.IsShown(A));
end;

procedure TTestLayers.TestLockedIsShownNotPickable;
var
  A: TFreePoint;
begin
  A := Pt('A');
  FPattern.ActiveLayer.Locked := True;
  AssertTrue('shown', FPattern.IsShown(A));
  AssertFalse('not pickable', FPattern.IsPickable(A));
end;

procedure TTestLayers.TestOtherDraftIsNotShown;
var
  A: TFreePoint;
begin
  A := Pt('A');
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  AssertFalse('other draft', FPattern.IsShown(A));
end;

procedure TTestLayers.TestRepeatPointFollowsItsRepeat;
var
  ARepeat: TRepeatObject;
  Layer: TPatternLayer;
begin
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Dart');
  FPattern.SelectLayer(Layer);
  ARepeat := FPattern.AddRepeatBetween('Btn', Pt('A').Key, Pt('B', 100).Key, '3', True);
  AssertNotNull(FPattern.LastError, ARepeat);
  FPattern.Evaluate;
  AssertTrue('on its layer', FPattern.LayerOf(ARepeat.Item(2)) = Layer);
end;

procedure TTestLayers.TestViewSavedInFile;
var
  Loaded: TPattern;
  Sleeve: TPatternDraft;
  Layer: TPatternLayer;
begin
  Sleeve := FPattern.AddDraft('Sleeve');
  Layer := FPattern.AddLayer(Sleeve, 'Dart');
  Sleeve.ActiveLayer := Layer;
  Sleeve.Layers[0].Hidden := True;
  Layer.Locked := True;
  Sleeve.HasView := True;
  Sleeve.Zoom := 1.5;
  Sleeve.CentreX := 120;
  Sleeve.CentreY := -200;
  FPattern.ActiveDraft := Sleeve;
  Loaded := Reloaded;
  AssertEquals('active draft', 'Sleeve', Loaded.ActiveDraft.Name);
  AssertEquals('active layer', 'Dart', Loaded.ActiveLayer.Name);
  AssertTrue('hidden', Loaded.ActiveDraft.Layers[0].Hidden);
  AssertTrue('locked', Loaded.ActiveDraft.Layers[1].Locked);
  AssertNear('zoom', 1.5, Loaded.ActiveDraft.Zoom);
  AssertNear('centre', -200, Loaded.ActiveDraft.CentreY);
end;

procedure TTestLayers.TestViewNotInUndoSnapshot;
var
  Before: string;
begin
  FPattern.AddDraft('Sleeve');
  Before := SavePatternToText(FPattern, False);
  FPattern.Drafts[1].Layers[0].Hidden := True;
  FPattern.ActiveDraft := FPattern.Drafts[1];
  AssertEquals('no change to undo', Before, SavePatternToText(FPattern, False));
end;

procedure TTestLayers.TestViewSkipsWhatHasGone;
begin
  FPattern.AddDraft('Sleeve');
  RestorePatternView(FPattern, '{"draft": 99, "solo": 98, "drafts": {"99": {"hidden": [97]}}}');
  AssertTrue('stays', FPattern.ActiveDraft = FPattern.Drafts[0]);
  AssertNull('no solo', FPattern.SoloLayer);
end;

// A square on the active layer, returning nothing: tests look for it
procedure Outline(Pattern: TPattern; Left: integer);
var
  A, B, C, D: string;
begin
  A := Pattern.AddFreePoint('', IntToStr(Left), '0').Key;
  B := Pattern.AddFreePoint('', IntToStr(Left + 100), '0').Key;
  C := Pattern.AddFreePoint('', IntToStr(Left + 100), '100').Key;
  D := Pattern.AddFreePoint('', IntToStr(Left), '100').Key;
  Pattern.AddLine(A, B, erOutline);
  Pattern.AddLine(B, C, erOutline);
  Pattern.AddLine(C, D, erOutline);
  Pattern.AddLine(D, A, erOutline);
end;

// The rotated dart case: an edge across the square splits it until its layer
// is hidden
procedure TTestLayers.TestPieceDetectionSkipsHiddenLayer;
var
  Layer: TPatternLayer;
  Path: TPiecePath;
  Reason: string;
begin
  Outline(FPattern, 0);
  Layer := FPattern.AddLayer(FPattern.ActiveDraft, 'Old');
  FPattern.SelectLayer(Layer);
  FPattern.AddLine(Pt('', 0).Key, FPattern.AddFreePoint('', '100', '100').Key, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(70, 30), Path, Reason));
  AssertEquals('cut in two: a triangle', 3, Length(Path));
  Layer.Hidden := True;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(70, 30), Path, Reason));
  AssertEquals('the whole square', 4, Length(Path));
end;

procedure TTestLayers.TestPieceDetectionStaysOnItsDraft;
var
  Path: TPiecePath;
  Reason: string;
begin
  Outline(FPattern, 0);
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  FPattern.Evaluate;
  AssertFalse('nothing on this draft', DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
end;

procedure TTestLayers.TestBoundsOfActiveDraftOnly;
var
  Bounds: TRect2;
begin
  Pt('A', 1000);
  FPattern.ActiveDraft := FPattern.AddDraft('Sleeve');
  Pt('B', 50);
  FPattern.Evaluate;
  AssertTrue('has bounds', PatternBounds(FPattern, Bounds));
  AssertNear('only B', 50, Bounds.MaxX);
end;

procedure TTestLayers.TestShownObjectsGoInLayerOrder;
var
  A, B: TFreePoint;
  Draft: TPatternDraft;
  Layer: TPatternLayer;
  Shown: TDraftObjectArray;
begin
  Draft := FPattern.ActiveDraft;
  A := Pt('A');
  Layer := FPattern.AddLayer(Draft, 'Top');
  FPattern.SelectLayer(Layer);
  B := Pt('B');
  FPattern.Evaluate;
  Shown := ShownObjects(FPattern);
  AssertTrue('bottom first', Shown[0] = A);
  AssertTrue(FPattern.MoveLayer(Draft, Layer, -1));
  Shown := ShownObjects(FPattern);
  AssertTrue('follows the stack', Shown[0] = B);
end;

procedure TTestLayers.TestShownObjectsLeaveOutHidden;
begin
  Pt('A');
  FPattern.ActiveLayer.Hidden := True;
  AssertEquals('objects', 0, Length(ShownObjects(FPattern)));
  AssertEquals('points', 0, Length(ShownPoints(FPattern)));
end;

// B is further away, but on top
procedure TTestLayers.TestTopLayerPointWins;
var
  A, B: TFreePoint;
begin
  A := Pt('A', 0);
  FPattern.SelectLayer(FPattern.AddLayer(FPattern.ActiveDraft, 'Top'));
  B := Pt('B', 3);
  FPattern.Evaluate;
  AssertTrue('the top one', PointAt(FPattern, Vec2(0, 0), 5) = B);
  FPattern.ActiveDraft.Layers.Move(0, 1);
  AssertTrue('the stack decides', PointAt(FPattern, Vec2(2, 0), 5) = A);
end;

procedure TTestLayers.TestPointPickSkipsLockedAndHidden;
begin
  Pt('A');
  FPattern.Evaluate;
  FPattern.ActiveLayer.Locked := True;
  AssertNull('locked', PointAt(FPattern, Vec2(0, 0), 5));
  FPattern.ActiveLayer.Locked := False;
  FPattern.ActiveLayer.Hidden := True;
  AssertNull('hidden', PointAt(FPattern, Vec2(0, 0), 5));
end;

procedure TTestLayers.TestEdgePickSkipsLocked;
begin
  FPattern.AddLine(Pt('A').Key, Pt('B', 100).Key);
  FPattern.Evaluate;
  AssertNotNull('free', EdgeAt(FPattern, Vec2(50, 0), 5));
  FPattern.ActiveLayer.Locked := True;
  AssertNull('locked', EdgeAt(FPattern, Vec2(50, 0), 5));
end;

procedure TTestLayers.TestSnapSkipsHiddenButNotLocked;
var
  Line: TLineObject;
  Snap: TSnap;
begin
  Line := FPattern.AddLine(Pt('A').Key, Pt('B', 100).Key);
  FPattern.Evaluate;
  FPattern.ActiveLayer.Locked := True;
  Snap := FindSnap(FPattern, Vec2(50, 1), 5);
  AssertEquals('locked can be snapped to', Line.Key, Snap.EdgeKey);
  FPattern.ActiveLayer.Locked := False;
  FPattern.ActiveLayer.Hidden := True;
  Snap := FindSnap(FPattern, Vec2(50, 1), 5);
  AssertTrue('hidden cannot', Snap.EdgeKey <> Line.Key);
end;

// Output goes by the pieces, whatever is hidden
procedure TTestLayers.TestHidingLeavesOutputAlone;
var
  Path: TPiecePath;
  Reason: string;
  Piece: TPieceObject;
begin
  Outline(FPattern, 0);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(50, 50), Path, Reason));
  Piece := FPattern.AddPiece('Front', Path, '10');
  Piece.View := pvFront;
  FPattern.Evaluate;
  FPattern.ActiveLayer.Hidden := True;
  AssertEquals('still in the garment', 1, Length(BuildGarment(FPattern, gsFront).Shapes));
end;

procedure TTestLayers.TestUndoShowsChangedDraft;
var
  Document: TPatternDocument;
  Sleeve: TPatternDraft;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add draft');
    Sleeve := Document.Pattern.AddDraft('Sleeve');
    Document.EndChange;
    Document.Pattern.ActiveDraft := Sleeve;
    Document.BeginChange('Add point');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.EndChange;
    Document.Pattern.ActiveDraft := Document.Pattern.Drafts[0];
    Document.Undo;
    AssertEquals('undo took it away', 0, Document.Pattern.ObjectCount);
    AssertEquals('and shows where', 'Sleeve', Document.Pattern.ActiveDraft.Name);
    Document.Pattern.ActiveDraft := Document.Pattern.Drafts[0];
    Document.Redo;
    AssertEquals('redo too', 'Sleeve', Document.Pattern.ActiveDraft.Name);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayers.TestUndoKeepsView;
var
  Document: TPatternDocument;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add draft');
    Document.Pattern.AddDraft('Sleeve');
    Document.EndChange;
    Document.BeginChange('Add point');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.EndChange;
    Document.Pattern.Drafts[1].Layers[0].Hidden := True;
    Document.Undo;
    AssertTrue('still hidden', Document.Pattern.Drafts[1].Layers[0].Hidden);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestLayers.TestHidingIsNotAChange;
var
  Document: TPatternDocument;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Add draft');
    Document.Pattern.AddDraft('Sleeve');
    Document.EndChange;
    AssertTrue('modified by that', Document.Modified);
    Document.BeginChange('Hide');
    Document.Pattern.ActiveLayer.Hidden := True;
    AssertFalse('nothing to undo', Document.EndChange);
  finally
    FreeAndNil(Document);
  end;
end;

initialization
  RegisterTest(TTestLayers);

end.
