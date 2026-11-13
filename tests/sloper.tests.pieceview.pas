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

// The view options for overlapping pieces: hiding a piece with what only it
// uses, isolating one, and the drawing order, and how they are saved.
unit Sloper.Tests.PieceView;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern;

type
  TTestPieceView = class(TOSTestCase)
  private
    FPattern: TPattern;
    FFront, FBack: TPieceObject;
    // Point keys by name
    function Key(const AName: string): string;
    function Obj(const AName: string): TDraftObject;
    function EdgeBetween(const First, Second: string): TDraftObject;
    function Piece(const AName: string; const Corners: array of string): TPieceObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNothingHiddenAtFirst;
    procedure TestHidingTakesWhatOnlyItUses;
    procedure TestSharedEdgeStays;
    procedure TestLooseLineKeepsItsPoint;
    procedure TestRepeatPointsFollowTheirRepeat;
    procedure TestNoteGoesWithItsPiece;
    procedure TestShowAllPieces;
    procedure TestIsolateDimsTheRest;
    procedure TestIsolatedPiecesNoteStays;
    procedure TestHidingIsolatedPieceEndsIsolation;
    procedure TestDrawOrder;
    procedure TestNewPieceGoesOnTop;
    procedure TestViewSaved;
    procedure TestViewIdsNotPiecesPassedOver;
    procedure TestDeletedPieceNotSaved;
    procedure TestViewChangesAreCountedFresh;
    procedure TestHiddenAndDimmedOutOfReach;
    procedure TestGarmentFollowsView;
    procedure TestDraftExportLeavesOutHidden;
  end;

implementation

uses
  Sloper.Core.Geometry, Sloper.Core.Note, Sloper.Core.PatternFile, Sloper.Core.Garment, Sloper.Output.DraftSVG, Sloper.UI.Scene;

procedure TTestPieceView.SetUp;
begin
  FPattern := TPattern.Create;
  // Front and back share the edge B-C
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '100', '0');
  FPattern.AddFreePoint('C', '100', '100');
  FPattern.AddFreePoint('D', '0', '100');
  FPattern.AddFreePoint('E', '200', '0');
  FPattern.AddFreePoint('F', '200', '100');
  FPattern.AddFreePoint('G', '300', '50');
  FFront := Piece('Front', ['A', 'B', 'C', 'D']);
  FBack := Piece('Back', ['B', 'E', 'F', 'C']);
end;

procedure TTestPieceView.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestPieceView.Key(const AName: string): string;
begin
  Result := Obj(AName).Key;
end;

function TTestPieceView.Obj(const AName: string): TDraftObject;
begin
  Result := FPattern.FindObject(AName);
  AssertNotNull(AName, Result);
end;

function TTestPieceView.EdgeBetween(const First, Second: string): TDraftObject;
var
  Index: integer;
  Edge: TEdgeObject;
begin
  for Index := 0 to FPattern.ObjectCount - 1 do
    if FPattern.Objects[Index] is TEdgeObject then
    begin
      Edge := TEdgeObject(FPattern.Objects[Index]);
      if ((Edge.StartKey = Key(First)) and (Edge.EndKey = Key(Second))) or ((Edge.StartKey = Key(Second)) and (Edge.EndKey = Key(First))) then
        Exit(Edge);
    end;
  Fail('No edge ' + First + '-' + Second);
  Result := nil;
end;

// Reuses an edge between two corners if there is one, reversed if it runs
// the other way
function TTestPieceView.Piece(const AName: string; const Corners: array of string): TPieceObject;
var
  Index: integer;
  Path: TPiecePath;
  Start, Finish: string;
  Index2: integer;
  Edge: TEdgeObject;
  Found: boolean;
begin
  Path := nil;
  SetLength(Path, Length(Corners));
  for Index := 0 to High(Corners) do
  begin
    Start := Key(Corners[Index]);
    Finish := Key(Corners[(Index + 1) mod Length(Corners)]);
    Found := False;
    for Index2 := 0 to FPattern.ObjectCount - 1 do
      if FPattern.Objects[Index2] is TEdgeObject then
      begin
        Edge := TEdgeObject(FPattern.Objects[Index2]);
        if (Edge.StartKey = Start) and (Edge.EndKey = Finish) or (Edge.StartKey = Finish) and (Edge.EndKey = Start) then
        begin
          Path[Index].EdgeKey := Edge.Key;
          Path[Index].Reversed := Edge.StartKey = Finish;
          Found := True;
        end;
      end;
    if not Found then
    begin
      Path[Index].EdgeKey := FPattern.AddLine(Start, Finish, erOutline).Key;
      Path[Index].Reversed := False;
    end;
  end;
  FPattern.Evaluate;
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestPieceView.TestNothingHiddenAtFirst;
var
  Index: integer;
begin
  for Index := 0 to FPattern.ObjectCount - 1 do
    AssertTrue(FPattern.Objects[Index].DisplayName, FPattern.IsActive(FPattern.Objects[Index]));
  AssertEquals(0, FPattern.HiddenPieceCount);
end;

procedure TTestPieceView.TestHidingTakesWhatOnlyItUses;
begin
  FPattern.SetPieceHidden(FBack, True);
  AssertTrue('piece', FPattern.IsHidden(FBack));
  AssertTrue('its own corner', FPattern.IsHidden(Obj('E')));
  AssertTrue('its own edge', FPattern.IsHidden(EdgeBetween('E', 'F')));
  AssertFalse('the other piece', FPattern.IsHidden(FFront));
  AssertFalse('a corner only the front has', FPattern.IsHidden(Obj('A')));
  AssertFalse('used by nothing', FPattern.IsHidden(Obj('G')));
  AssertEquals(1, FPattern.HiddenPieceCount);
end;

procedure TTestPieceView.TestSharedEdgeStays;
begin
  FPattern.SetPieceHidden(FBack, True);
  AssertFalse('shared edge', FPattern.IsHidden(EdgeBetween('B', 'C')));
  AssertFalse('shared corner', FPattern.IsHidden(Obj('B')));
end;

procedure TTestPieceView.TestLooseLineKeepsItsPoint;
var
  Loose: TDraftObject;
begin
  Loose := FPattern.AddLine(Key('E'), Key('G'));
  FPattern.Evaluate;
  FPattern.SetPieceHidden(FBack, True);
  AssertFalse('a line in no piece', FPattern.IsHidden(Loose));
  AssertFalse('its end in the hidden piece', FPattern.IsHidden(Obj('E')));
  AssertTrue('the rest of the piece', FPattern.IsHidden(Obj('F')));
end;

procedure TTestPieceView.TestRepeatPointsFollowTheirRepeat;
var
  Point: TPointObject;
begin
  // A repeat along an edge only the back uses is in no piece, so it stays
  AssertNotNull(FPattern.LastError, FPattern.AddRepeatOnEdge('R', EdgeBetween('E', 'F').Key, '3', False));
  FPattern.Evaluate;
  FPattern.SetPieceHidden(FBack, True);
  for Point in FPattern.AllPoints do
    if Point is TRepeatPoint then
      AssertFalse('a repeat point', FPattern.IsHidden(Point));
  AssertFalse('its edge, which it uses', FPattern.IsHidden(EdgeBetween('E', 'F')));
end;

procedure TTestPieceView.TestNoteGoesWithItsPiece;
var
  OnBack, OnFront: TNoteObject;
begin
  OnBack := FPattern.AddNote('', 'Back', naPiece, FBack.Key, '', '0', '0');
  OnFront := FPattern.AddNote('', 'Front', naPiece, FFront.Key, '', '0', '0');
  FPattern.Evaluate;
  FPattern.SetPieceHidden(FBack, True);
  AssertTrue('on the hidden piece', FPattern.IsHidden(OnBack));
  AssertFalse('on the other', FPattern.IsHidden(OnFront));
end;

procedure TTestPieceView.TestShowAllPieces;
begin
  FPattern.SetPieceHidden(FBack, True);
  FPattern.SetPieceHidden(FFront, True);
  AssertEquals(2, FPattern.HiddenPieceCount);
  AssertTrue('the shared edge too, with both hidden', FPattern.IsHidden(EdgeBetween('B', 'C')));
  FPattern.ShowAllPieces;
  AssertEquals(0, FPattern.HiddenPieceCount);
  AssertFalse(FPattern.IsHidden(FBack));
  AssertFalse(FPattern.IsHidden(Obj('E')));
end;

procedure TTestPieceView.TestIsolateDimsTheRest;
begin
  FPattern.View.Isolated := FFront.Key;
  AssertTrue('isolated', FPattern.IsolatedPiece = FFront);
  AssertTrue('the piece', FPattern.IsActive(FFront));
  AssertTrue('its edge', FPattern.IsActive(EdgeBetween('A', 'B')));
  AssertTrue('the shared edge', FPattern.IsActive(EdgeBetween('B', 'C')));
  AssertTrue('the other piece', FPattern.IsDimmed(FBack));
  AssertTrue('its corner', FPattern.IsDimmed(Obj('E')));
  AssertTrue('a loose point', FPattern.IsDimmed(Obj('G')));
  AssertFalse('dimmed is not hidden', FPattern.IsHidden(FBack));
  FPattern.View.Isolated := '';
  AssertTrue('back to normal', FPattern.IsActive(FBack));
end;

procedure TTestPieceView.TestIsolatedPiecesNoteStays;
var
  Note: TNoteObject;
begin
  Note := FPattern.AddNote('', 'Front', naPiece, FFront.Key, '', '0', '0');
  FPattern.Evaluate;
  FPattern.View.Isolated := FFront.Key;
  AssertTrue(FPattern.IsActive(Note));
end;

procedure TTestPieceView.TestHidingIsolatedPieceEndsIsolation;
begin
  FPattern.View.Isolated := FFront.Key;
  FPattern.SetPieceHidden(FFront, True);
  AssertEquals('', FPattern.View.Isolated);
  AssertFalse(Assigned(FPattern.IsolatedPiece));
end;

procedure TTestPieceView.TestDrawOrder;
var
  Order: TPieceObjectArray;
begin
  Order := FPattern.PiecesInDrawOrder;
  AssertTrue('pattern order first', (Order[0] = FFront) and (Order[1] = FBack));
  FPattern.BringToFront(FFront);
  Order := FPattern.PiecesInDrawOrder;
  AssertTrue('front on top', (Order[0] = FBack) and (Order[1] = FFront));
  FPattern.SendToBack(FFront);
  Order := FPattern.PiecesInDrawOrder;
  AssertTrue('front at the back', (Order[0] = FFront) and (Order[1] = FBack));
end;

procedure TTestPieceView.TestNewPieceGoesOnTop;
var
  Order: TPieceObjectArray;
  Third: TPieceObject;
begin
  FPattern.SendToBack(FBack);
  FPattern.AddFreePoint('H', '200', '200');
  FPattern.AddFreePoint('I', '100', '200');
  Third := Piece('Sleeve', ['C', 'F', 'H', 'I']);
  Order := FPattern.PiecesInDrawOrder;
  AssertEquals(3, Length(Order));
  AssertTrue('listed first', (Order[0] = FBack) and (Order[1] = FFront));
  AssertTrue('new on top', Order[2] = Third);
end;

procedure TTestPieceView.TestViewSaved;
var
  Loaded: TPattern;
  Err: string;
begin
  FPattern.SetPieceHidden(FBack, True);
  FPattern.View.Isolated := FFront.Key;
  FPattern.BringToFront(FFront);
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, SavePatternToText(FPattern), Err));
    AssertEquals('hidden', 1, Length(Loaded.View.HiddenPieces));
    AssertEquals(FBack.Key, Loaded.View.HiddenPieces[0]);
    AssertEquals('isolated', FFront.Key, Loaded.View.Isolated);
    AssertEquals('order', 2, Length(Loaded.View.PieceOrder));
    AssertEquals(FFront.Key, Loaded.View.PieceOrder[1]);
  finally
    FreeAndNil(Loaded);
  end;
  // Left out when there is nothing to say
  FPattern.ShowAllPieces;
  FPattern.View.Isolated := '';
  FPattern.View.PieceOrder := nil;
  AssertEquals('nothing saved', 0, Pos('Pieces', SavePatternToText(FPattern)) + Pos('isolate', SavePatternToText(FPattern)));
end;

procedure TTestPieceView.TestViewIdsNotPiecesPassedOver;
var
  Text, Err: string;
  Loaded: TPattern;
begin
  Text := SavePatternToText(FPattern);
  Text := StringReplace(Text, '"view": {', '"view": {"hiddenPieces": [' + Key('A') + ', "x", 9999, ' + FBack.Key +
    '], "isolate": -3, ', []);
  if Pos('"view"', Text) = 0 then
    Text := StringReplace(Text, '"nextId"', '"view": {"hiddenPieces": [' + Key('A') + ', "x", 9999, ' + FBack.Key + ']}, "nextId"', []);
  Loaded := TPattern.Create;
  try
    AssertTrue(Err, LoadPatternFromText(Loaded, Text, Err));
    Loaded.Evaluate;
    AssertEquals('only the piece counts', 1, Loaded.HiddenPieceCount);
    AssertEquals('no isolation', '', Loaded.View.Isolated);
    AssertTrue(Loaded.IsHidden(TDraftObject(Loaded.FindNode(FBack.Key))));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestPieceView.TestDeletedPieceNotSaved;
begin
  FPattern.SetPieceHidden(FBack, True);
  AssertTrue(FPattern.LastError, FPattern.Delete(FBack));
  FPattern.Evaluate;
  AssertEquals(0, FPattern.HiddenPieceCount);
  AssertEquals(0, Pos('hiddenPieces', SavePatternToText(FPattern)));
end;

procedure TTestPieceView.TestViewChangesAreCountedFresh;
begin
  // The worked-out visibility follows each change, without evaluating again
  FPattern.SetPieceHidden(FBack, True);
  AssertTrue(FPattern.IsHidden(Obj('E')));
  FPattern.SetPieceHidden(FBack, False);
  AssertFalse(FPattern.IsHidden(Obj('E')));
  FPattern.View.Isolated := FBack.Key;
  AssertTrue(FPattern.IsDimmed(Obj('A')));
end;

procedure TTestPieceView.TestHiddenAndDimmedOutOfReach;
var
  Box: TRect2;
  Keys: TStringArray;
  Found: string;
begin
  AssertTrue('reachable at first', PointAt(FPattern, Vec2(200, 0), 2) = Obj('E'));
  FPattern.SetPieceHidden(FBack, True);
  AssertFalse('hidden', Assigned(PointAt(FPattern, Vec2(200, 0), 2)));
  FPattern.ShowAllPieces;
  FPattern.View.Isolated := FFront.Key;
  AssertFalse('dimmed', Assigned(PointAt(FPattern, Vec2(200, 0), 2)));
  AssertTrue('the isolated piece''s corner', PointAt(FPattern, Vec2(0, 0), 2) = Obj('A'));
  AssertFalse('a dimmed piece', Assigned(PieceAt(FPattern, Vec2(150, 50))));
  AssertTrue('the isolated piece', PieceAt(FPattern, Vec2(50, 50)) = FFront);
  Box.MinX := -10;
  Box.MinY := -10;
  Box.MaxX := 400;
  Box.MaxY := 400;
  Keys := ObjectsInBox(FPattern, Box);
  for Found in Keys do
    AssertFalse('box takes nothing dimmed', FPattern.IsDimmed(TDraftObject(FPattern.FindNode(Found))));
  AssertTrue('box takes the piece', Pos(FFront.Key, string.Join(',', Keys)) > 0);
end;

procedure TTestPieceView.TestGarmentFollowsView;
var
  Scene: TGarmentScene;
  Builder: TGarmentBuilder;
begin
  Builder := TGarmentBuilder.Create;
  try
    FPattern.SetPieceHidden(FBack, True);
    Scene := Builder.Build(FPattern, True);
    AssertEquals('hidden left out', 1, Length(Scene.Pieces));
    AssertEquals('Front', Scene.Pieces[0].Name);
    AssertEquals('output keeps it', 2, Length(Builder.Build(FPattern).Pieces));
    FPattern.ShowAllPieces;
    FPattern.View.Isolated := FBack.Key;
    Scene := Builder.Build(FPattern, True);
    AssertEquals('only the isolated', 1, Length(Scene.Pieces));
    AssertEquals('Back', Scene.Pieces[0].Name);
    FPattern.View.Isolated := '';
    FPattern.SendToBack(FBack);
    Scene := Builder.Build(FPattern, True);
    AssertEquals('drawing order', 'Back', Scene.Pieces[0].Name);
    AssertEquals('pattern order for output', 'Front', Builder.Build(FPattern).Pieces[0].Name);
  finally
    FreeAndNil(Builder);
  end;
end;

procedure TTestPieceView.TestDraftExportLeavesOutHidden;
var
  Options: TDraftSVGOptions;
begin
  FPattern.SetPieceHidden(FBack, True);
  Options := DefaultDraftSVGOptions;
  AssertTrue('all by default', Pos('data-name="Back"', DraftToSVG(FPattern, Options)) > 0);
  Options.FollowPieceView := True;
  AssertEquals('as on screen', 0, Pos('data-name="Back"', DraftToSVG(FPattern, Options)));
  AssertTrue('the other stays', Pos('data-name="Front"', DraftToSVG(FPattern, Options)) > 0);
end;

initialization
  RegisterTest(TTestPieceView);
end.
