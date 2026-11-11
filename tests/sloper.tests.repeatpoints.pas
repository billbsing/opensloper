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

// Repeats: evenly spaced points that have no ID until something uses them.
unit Sloper.Tests.RepeatPoints;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Draft, Sloper.Core.Note, Sloper.Core.Pattern;

type
  TTestRepeat = class(TOSTestCase)
  private
    FPattern: TPattern;
    FA, FB: TFreePoint;
    function Between(ACount: integer; IncludeEnds: boolean = True): TRepeatObject;
    procedure AssertItem(Item: TRepeatPoint; X, Y: double);
    function Reloaded: TPattern;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestIncludingTheEnds;
    procedure TestLeavingOutTheEnds;
    procedure TestOnePointGoesInTheMiddle;
    procedure TestAlongACurveByArcLength;
    procedure TestCountIsAFormula;
    procedure TestCountChangesWithItsFormula;
    procedure TestBadCounts;
    procedure TestSamePointRefused;
    procedure TestFollowsItsPoints;
    procedure TestNamesFromTheRepeat;
    procedure TestRenameRenamesEveryPoint;
    procedure TestBracketsNotAllowedInNames;
    procedure TestEvaluatingHandsOutNoIds;
    procedure TestFirstUseTakesAnId;
    procedure TestIdStaysWithItsIndex;
    procedure TestUsingAPointTwiceIsOneId;
    procedure TestVirtualKeyFindsAUsedPoint;
    procedure TestVirtualKeyCannotBeStored;
    procedure TestFormulaUsesAPoint;
    procedure TestFormulaGivesAnId;
    procedure TestNoteTextGivesAnotherId;
    procedure TestRefusedAddTakesNoId;
    procedure TestRefusedAddKeepsTheUsedPoint;
    procedure TestFormulaPastTheCountRefused;
    procedure TestFormulaIndexZeroRefused;
    procedure TestPointNeedsAProperty;
    procedure TestRepeatCountReadable;
    procedure TestCountDropsToAnError;
    procedure TestCountDropBlocksUsers;
    procedure TestCountRisesAndThePointIsBack;
    procedure TestItsPointsCannotBeRenamed;
    procedure TestItsPointsCannotBeConverted;
    procedure TestOnlyTheFirstPointDeletes;
    procedure TestDeleteTakesItsPoints;
    procedure TestDeleteRefusedWhileAPointIsUsed;
    procedure TestAllPointsIncludesThem;
    procedure TestRoundTrip;
    procedure TestRoundTripOnAnEdge;
    procedure TestUsedPointsSurviveReload;
    procedure TestUsedPastTheCountSurvivesReload;
    procedure TestUnusedPointsAreNotSaved;
    procedure TestBadRepeatPointsRefused;
    procedure TestUndoTakesBackTheId;
    procedure TestLineFromARepeatPointStaysPut;
    procedure TestEdgeNameFromARepeatPointIsAName;
    procedure TestEdgeNameFollowsARename;
    procedure TestAlignToARepeatPoint;
    procedure TestDistributeBetweenRepeatPoints;
    procedure TestRepeatPointsAreNotRearranged;
    procedure TestListedAsItsPoints;
    procedure TestListedUnderPoints;
    procedure TestListedWhenItHasNoPoints;
    procedure TestPickedOnTheCanvas;
  end;

implementation

uses
  Sloper.Core.Arrange, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Names, Sloper.Core.PatternFile,
  Sloper.Document.PatternDocument,
  Sloper.UI.ObjectList, Sloper.UI.Scene;

const
  REPEAT_PATTERN_HEAD = '{"format": "pattern", "version": 1, "units": "mm", "objects": [' +
    '{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"}, {"id": 2, "type": "freePoint", "name": "B", "x": "9", "y": "0"}, ' +
    '{"id": 3, "type": "repeat", "name": "R", "a": 1, "b": 2, "ends": "include", "count": "3", "points": [';

procedure TTestRepeat.SetUp;
begin
  FPattern := TPattern.Create;
  FA := FPattern.AddFreePoint('A', '0', '0');
  FB := FPattern.AddFreePoint('B', '300', '0');
end;

procedure TTestRepeat.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestRepeat.Between(ACount: integer; IncludeEnds: boolean): TRepeatObject;
begin
  Result := FPattern.AddRepeatBetween('Btn', FA.Key, FB.Key, IntToStr(ACount), IncludeEnds);
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

procedure TTestRepeat.AssertItem(Item: TRepeatPoint; X, Y: double);
begin
  AssertNotNull(Item);
  AssertNear('x', X, Item.Position.X);
  AssertNear('y', Y, Item.Position.Y);
end;

function TTestRepeat.Reloaded: TPattern;
var
  Err: string;
begin
  Result := TPattern.Create;
  AssertTrue(Err, LoadPatternFromText(Result, SavePatternToText(FPattern), Err));
  Result.Evaluate;
end;

procedure TTestRepeat.TestIncludingTheEnds;
var
  Done: TRepeatObject;
begin
  Done := Between(4);
  AssertEquals(4, Done.Count);
  AssertItem(Done.Item(1), 0, 0);
  AssertItem(Done.Item(2), 100, 0);
  AssertItem(Done.Item(4), 300, 0);
end;

procedure TTestRepeat.TestLeavingOutTheEnds;
var
  Done: TRepeatObject;
begin
  Done := Between(2, False);
  AssertItem(Done.Item(1), 100, 0);
  AssertItem(Done.Item(2), 200, 0);
end;

procedure TTestRepeat.TestOnePointGoesInTheMiddle;
begin
  AssertItem(Between(1).Item(1), 150, 0);
end;

procedure TTestRepeat.TestAlongACurveByArcLength;
var
  Edge: TCurveObject;
  Done: TRepeatObject;
  Middle: TVec2;
begin
  Edge := FPattern.AddCurve(FA.Key, FB.Key, '90', '100', '90', '100');
  Done := FPattern.AddRepeatOnEdge('Btn', Edge.Key, '3', True);
  AssertNotNull(FPattern.LastError, Done);
  FPattern.Evaluate;
  Middle := Edge.PointAtLength(Edge.Length / 2);
  AssertItem(Done.Item(2), Middle.X, Middle.Y);
end;

procedure TTestRepeat.TestCountIsAFormula;
var
  Done: TRepeatObject;
begin
  Done := FPattern.AddRepeatBetween('Btn', FA.Key, FB.Key, 'round(300 / 80)', True);
  FPattern.Evaluate;
  AssertEquals(4, Done.Count);
end;

procedure TTestRepeat.TestCountChangesWithItsFormula;
var
  Done: TRepeatObject;
begin
  Done := FPattern.AddRepeatBetween('Btn', FA.Key, FB.Key, 'round(A.x + 3)', True);
  FPattern.Evaluate;
  AssertEquals(3, Done.Count);
  AssertTrue(FPattern.SetFormula(FA, 'x', '2'));
  FPattern.Evaluate;
  AssertEquals(5, Done.Count);
end;

procedure TTestRepeat.TestBadCounts;
var
  Done: TRepeatObject;
begin
  Done := FPattern.AddRepeatBetween('Btn', FA.Key, FB.Key, '0', True);
  FPattern.Evaluate;
  AssertTrue('none', Done.State = esInvalid);
  AssertTrue(FPattern.SetFormula(Done, 'count', '-3'));
  FPattern.Evaluate;
  AssertTrue('negative', Done.State = esInvalid);
  AssertTrue(FPattern.SetFormula(Done, 'count', '100000'));
  FPattern.Evaluate;
  AssertTrue('too many', Done.State = esInvalid);
end;

procedure TTestRepeat.TestSamePointRefused;
begin
  AssertNull(FPattern.AddRepeatBetween('Btn', FA.Key, FA.Key, '3', True));
  AssertEquals(rsPatternRepeatSamePoint, FPattern.LastError);
end;

procedure TTestRepeat.TestFollowsItsPoints;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertTrue(FPattern.SetFormula(FB, 'x', '600'));
  FPattern.Evaluate;
  AssertItem(Done.Item(2), 300, 0);
end;

procedure TTestRepeat.TestNamesFromTheRepeat;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertEquals('Btn[1]', Done.Item(1).Name);
  AssertEquals('Btn[3]', Done.Item(3).Name);
  AssertTrue('found by name', FPattern.FindObject('Btn[2]') = TObject(Done.Item(2)));
end;

procedure TTestRepeat.TestRenameRenamesEveryPoint;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  FPattern.UsePoint(Done.Item(2).Key);
  AssertTrue(FPattern.Rename(Done, 'Loop'));
  AssertEquals('Loop[1]', Done.Item(1).Name);
  AssertEquals('used too', 'Loop[2]', Done.Item(2).Name);
end;

procedure TTestRepeat.TestBracketsNotAllowedInNames;
begin
  AssertFalse(FPattern.Rename(Between(3), 'Btn[1]'));
end;

procedure TTestRepeat.TestEvaluatingHandsOutNoIds;
var
  Done: TRepeatObject;
  Before: integer;
begin
  Done := Between(6);
  Before := FPattern.NextId;
  FPattern.Evaluate;
  AssertEquals('no IDs spent', Before, FPattern.NextId);
  AssertTrue('nothing has one', Length(Done.UsedItems) = 0);
  AssertTrue(Done.Item(3).IsVirtual);
end;

procedure TTestRepeat.TestFirstUseTakesAnId;
var
  Done: TRepeatObject;
  Id: string;
  Before: integer;
begin
  Done := Between(6);
  Before := FPattern.NextId;
  Id := FPattern.UsePoint(Done.Item(3).Key);
  AssertEquals(IntToStr(Before), Id);
  AssertFalse(Done.Item(3).IsVirtual);
  AssertEquals(1, Length(Done.UsedItems));
  AssertTrue('in the graph', FPattern.FindNode(Id) = TObject(Done.Item(3)));
end;

procedure TTestRepeat.TestIdStaysWithItsIndex;
var
  Done: TRepeatObject;
  Id: string;
begin
  Done := Between(6);
  Id := FPattern.UsePoint(Done.Item(3).Key);
  AssertTrue(FPattern.SetFormula(Done, 'count', '10'));
  FPattern.Evaluate;
  AssertEquals(Id, Done.Item(3).Key);
  AssertEquals(3, TRepeatPoint(FPattern.FindNode(Id)).Index);
  AssertItem(Done.Item(3), 200 / 3, 0);
end;

procedure TTestRepeat.TestUsingAPointTwiceIsOneId;
var
  Done: TRepeatObject;
  Key, First: string;
begin
  Done := Between(3);
  Key := Done.Item(2).Key;
  First := FPattern.UsePoint(Key);
  AssertEquals(First, FPattern.UsePoint(Key));
  AssertEquals(First, FPattern.UsePoint(First));
end;

procedure TTestRepeat.TestVirtualKeyFindsAUsedPoint;
var
  Done: TRepeatObject;
  Key: string;
begin
  Done := Between(3);
  Key := Done.Item(2).Key;
  FPattern.UsePoint(Key);
  AssertTrue('a selection holding the old key stays good', FPattern.FindNode(Key) = TObject(Done.Item(2)));
end;

procedure TTestRepeat.TestVirtualKeyCannotBeStored;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertNull('it has no ID yet', FPattern.AddLine(FA.Key, Done.Item(2).Key));
  AssertNotNull(FPattern.AddLine(FA.Key, FPattern.UsePoint(Done.Item(2).Key)));
end;

procedure TTestRepeat.TestFormulaUsesAPoint;
var
  Point: TFreePoint;
begin
  Between(4);
  Point := FPattern.AddFreePoint('P', 'Btn[3].x', '0');
  AssertNotNull(FPattern.LastError, Point);
  FPattern.Evaluate;
  AssertNear('x', 200, Point.Position.X);
end;

procedure TTestRepeat.TestFormulaGivesAnId;
var
  Done: TRepeatObject;
  Point: TFreePoint;
begin
  Done := Between(4);
  Point := FPattern.AddFreePoint('P', 'Btn[3].x', '0');
  AssertEquals('stored by ID', '{' + Done.Item(3).Key + '}.x', Point.Field('x').StoredText);
  AssertEquals('shown by name', 'Btn[3].x', FPattern.FormulaText(Point, 'x'));
end;

// The note takes its own ID, not the one its text gives the point
procedure TTestRepeat.TestNoteTextGivesAnotherId;
var
  Done: TRepeatObject;
  Note: TNoteObject;
begin
  Done := Between(4);
  Note := FPattern.AddNote('', 'At {=Btn[3].x}', naFree, '', '', '10', '10');
  AssertNotNull(FPattern.LastError, Note);
  AssertNotNull('the point is used', Done.Item(3));
  AssertFalse('two IDs', Note.Key = Done.Item(3).Key);
  AssertSame('the note by its ID', Note, FPattern.FindNode(Note.Key));
  AssertTrue('the point by its ID', FPattern.FindNode(Done.Item(3).Key) is TRepeatPoint);
end;

procedure TTestRepeat.TestRefusedAddTakesNoId;
var
  Next: integer;
begin
  Between(4);
  Next := FPattern.NextId;
  AssertNull('refused', FPattern.AddFreePoint('P', '1 +', '0'));
  AssertEquals('no ID used', Next, FPattern.NextId);
  AssertEquals('the next one takes it', IntToStr(Next), FPattern.AddFreePoint('Q', '0', '0').Key);
end;

// A formula that named the point gave it an ID, which it keeps
procedure TTestRepeat.TestRefusedAddKeepsTheUsedPoint;
var
  Done: TRepeatObject;
  Added: TFreePoint;
begin
  Done := Between(4);
  AssertNull('refused', FPattern.AddFreePoint('P', 'Btn[3].x', '1 +'));
  Added := FPattern.AddFreePoint('Q', 'Btn[3].x', '0');
  AssertNotNull(FPattern.LastError, Added);
  AssertFalse('two IDs', Added.Key = Done.Item(3).Key);
  AssertEquals('stored by the point''s ID', '{' + Done.Item(3).Key + '}.x', Added.Field('x').StoredText);
end;

procedure TTestRepeat.TestFormulaPastTheCountRefused;
begin
  Between(4);
  AssertNull(FPattern.AddFreePoint('P', 'Btn[5].x', '0'));
end;

procedure TTestRepeat.TestFormulaIndexZeroRefused;
begin
  Between(4);
  AssertNull(FPattern.AddFreePoint('P', 'Btn[0].x', '0'));
end;

procedure TTestRepeat.TestPointNeedsAProperty;
begin
  Between(4);
  AssertNull(FPattern.AddFreePoint('P', 'Btn[2]', '0'));
end;

procedure TTestRepeat.TestRepeatCountReadable;
var
  Point: TFreePoint;
begin
  Between(4);
  Point := FPattern.AddFreePoint('P', 'Btn.count * 10', '0');
  AssertNotNull(FPattern.LastError, Point);
  FPattern.Evaluate;
  AssertNear('x', 40, Point.Position.X);
end;

procedure TTestRepeat.TestCountDropsToAnError;
var
  Done: TRepeatObject;
  Used: TEvalNode;
begin
  Done := Between(6);
  Used := FPattern.FindNode(FPattern.UsePoint(Done.Item(6).Key));
  AssertTrue(FPattern.SetFormula(Done, 'count', '4'));
  FPattern.Evaluate;
  AssertTrue(Used.State = esError);
  AssertEquals(Format(rsDraftRepeatGone, ['Btn[6]']), Used.Message);
end;

procedure TTestRepeat.TestCountDropBlocksUsers;
var
  Done: TRepeatObject;
  Point: TFreePoint;
begin
  Done := Between(6);
  Point := FPattern.AddFreePoint('P', 'Btn[6].x', '0');
  FPattern.Evaluate;
  AssertNear('fine at first', 300, Point.Position.X);
  AssertTrue(FPattern.SetFormula(Done, 'count', '4'));
  FPattern.Evaluate;
  AssertTrue('not moved to another point', Point.State = esBlocked);
end;

procedure TTestRepeat.TestCountRisesAndThePointIsBack;
var
  Done: TRepeatObject;
  Point: TFreePoint;
  Id: string;
begin
  Done := Between(6);
  Point := FPattern.AddFreePoint('P', 'Btn[6].x', '0');
  Id := Done.Item(6).Key;
  AssertTrue(FPattern.SetFormula(Done, 'count', '4'));
  FPattern.Evaluate;
  AssertTrue(FPattern.SetFormula(Done, 'count', '7'));
  FPattern.Evaluate;
  AssertEquals('the same point', Id, Done.Item(6).Key);
  AssertTrue(Point.State = esValid);
  AssertNear('where it now is', 250, Point.Position.X);
end;

procedure TTestRepeat.TestItsPointsCannotBeRenamed;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertFalse(FPattern.Rename(Done.Item(2), 'Other'));
  AssertEquals(Format(rsPatternRepeatItem, ['Btn[2]']), FPattern.LastError);
end;

procedure TTestRepeat.TestItsPointsCannotBeConverted;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertNull(FPattern.ConvertToFree(Done.Item(2), '0', '0'));
  AssertEquals(Format(rsPatternRepeatItem, ['Btn[2]']), FPattern.LastError);
end;

procedure TTestRepeat.TestOnlyTheFirstPointDeletes;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  AssertFalse(FPattern.Delete(Done.Item(2)));
  AssertTrue('it stands for the repeat', FPattern.Delete(Done.Item(1)));
  AssertNull(FPattern.FindObject('Btn'));
end;

procedure TTestRepeat.TestDeleteTakesItsPoints;
var
  Done: TRepeatObject;
  Id: string;
begin
  Done := Between(3);
  Id := FPattern.UsePoint(Done.Item(2).Key);
  AssertTrue(FPattern.LastError, FPattern.Delete(Done));
  AssertNull(FPattern.FindNode(Id));
  FPattern.Evaluate;
end;

procedure TTestRepeat.TestDeleteRefusedWhileAPointIsUsed;
var
  Done: TRepeatObject;
begin
  Done := Between(3);
  FPattern.AddFreePoint('P', 'Btn[2].x', '0');
  AssertFalse(FPattern.Delete(Done));
  AssertTrue(FPattern.LastError, Pos('P', FPattern.LastError) > 0);
end;

procedure TTestRepeat.TestAllPointsIncludesThem;
begin
  Between(3);
  AssertEquals('A, B and three', 5, Length(FPattern.AllPoints));
end;

procedure TTestRepeat.TestRoundTrip;
var
  Loaded: TPattern;
  Done: TRepeatObject;
begin
  Between(4, False);
  Loaded := Reloaded;
  try
    Done := TRepeatObject(Loaded.FindObject('Btn'));
    AssertNotNull(Done);
    AssertFalse(Done.IncludeEnds);
    AssertEquals(4, Done.Count);
    AssertNear('x', 60, Done.Item(1).Position.X);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestRepeat.TestRoundTripOnAnEdge;
var
  Loaded: TPattern;
  Edge: TLineObject;
begin
  Edge := FPattern.AddLine(FA.Key, FB.Key);
  FPattern.AddRepeatOnEdge('Btn', Edge.Key, '3', True);
  Loaded := Reloaded;
  try
    AssertEquals(Edge.Key, TRepeatObject(Loaded.FindObject('Btn')).Edge);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestRepeat.TestUsedPointsSurviveReload;
var
  Loaded: TPattern;
  Done: TRepeatObject;
  Id: string;
begin
  Done := Between(4);
  FPattern.AddFreePoint('P', 'Btn[3].x', '0');
  Id := Done.Item(3).Key;
  Loaded := Reloaded;
  try
    AssertEquals(Id, TRepeatObject(Loaded.FindObject('Btn')).Item(3).Key);
    AssertNear('reads it', 200, TPointObject(Loaded.FindObject('P')).Position.X);
    AssertEquals('Btn[3].x', Loaded.FormulaText(Loaded.FindObject('P'), 'x'));
    AssertEquals('no ID reused', FPattern.NextId, Loaded.NextId);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestRepeat.TestUsedPastTheCountSurvivesReload;
var
  Loaded: TPattern;
  Done: TRepeatObject;
  Id: string;
begin
  Done := Between(6);
  Id := FPattern.UsePoint(Done.Item(6).Key);
  AssertTrue(FPattern.SetFormula(Done, 'count', '4'));
  FPattern.Evaluate;
  Loaded := Reloaded;
  try
    AssertTrue(Loaded.FindNode(Id).State = esError);
    AssertEquals(Format(rsDraftRepeatGone, ['Btn[6]']), Loaded.FindNode(Id).Message);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestRepeat.TestUnusedPointsAreNotSaved;
begin
  Between(6);
  AssertEquals(0, Pos('"points"', SavePatternToText(FPattern)));
end;

procedure TTestRepeat.TestBadRepeatPointsRefused;
var
  Loaded: TPattern;
  Err: string;
begin
  Loaded := TPattern.Create;
  try
    AssertFalse('an ID taken', LoadPatternFromText(Loaded, REPEAT_PATTERN_HEAD + '{"index": 1, "id": 1}]}]}', Err));
    AssertFalse('an index twice', LoadPatternFromText(Loaded, REPEAT_PATTERN_HEAD + '{"index": 1, "id": 4}, {"index": 1, "id": 5}]}]}', Err));
    AssertFalse('an index of 0', LoadPatternFromText(Loaded, REPEAT_PATTERN_HEAD + '{"index": 0, "id": 4}]}]}', Err));
    AssertTrue(Err, LoadPatternFromText(Loaded, REPEAT_PATTERN_HEAD + '{"index": 2, "id": 4}]}]}', Err));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestRepeat.TestUndoTakesBackTheId;
var
  Document: TPatternDocument;
  Done: TRepeatObject;
begin
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Points');
    Document.Pattern.AddFreePoint('A', '0', '0');
    Document.Pattern.AddFreePoint('B', '300', '0');
    Document.Pattern.AddRepeatBetween('Btn', Document.Pattern.FindObject('A').Key, Document.Pattern.FindObject('B').Key, '4', True);
    Document.Commit(True);
    Document.BeginChange('Use it');
    AssertNotNull(Document.Pattern.LastError, Document.Pattern.AddFreePoint('P', 'Btn[3].x', '0'));
    Document.Commit(True);
    Done := TRepeatObject(Document.Pattern.FindObject('Btn'));
    AssertEquals(1, Length(Done.UsedItems));
    AssertTrue(Document.Undo);
    Done := TRepeatObject(Document.Pattern.FindObject('Btn'));
    AssertEquals('in the same undo step', 0, Length(Done.UsedItems));
    AssertTrue(Document.Redo);
    Done := TRepeatObject(Document.Pattern.FindObject('Btn'));
    AssertEquals(1, Length(Done.UsedItems));
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestRepeat.TestLineFromARepeatPointStaysPut;
var
  Done: TRepeatObject;
  Line: TLineObject;
begin
  Done := Between(4);
  Line := FPattern.AddLine(FPattern.UsePoint(Done.Item(2).Key), FB.Key);
  FPattern.Evaluate;
  AssertNear('length', 200, Line.Length);
  AssertTrue(FPattern.SetFormula(Done, 'count', '7'));
  FPattern.Evaluate;
  AssertNear('it follows its index', 250, Line.Length);
end;

// A derived name has to work in a formula like any other
procedure TTestRepeat.TestEdgeNameFromARepeatPointIsAName;
var
  Done: TRepeatObject;
  Line: TLineObject;
  Err: string;
  Point: TFreePoint;
begin
  Done := Between(4);
  Line := FPattern.AddLine(FPattern.UsePoint(Done.Item(2).Key), FB.Key);
  FPattern.UpdateDerivedNames;
  AssertTrue(Line.Name, CheckName(Line.Name, Err));
  Point := FPattern.AddFreePoint('P', Line.Name + '.length', '0');
  AssertNotNull(FPattern.LastError, Point);
  FPattern.Evaluate;
  AssertNear('length', 200, Point.Position.X);
end;

procedure TTestRepeat.TestEdgeNameFollowsARename;
var
  Done: TRepeatObject;
  Line: TLineObject;
begin
  Done := Between(4);
  Line := FPattern.AddLine(FPattern.UsePoint(Done.Item(2).Key), FB.Key);
  AssertTrue(FPattern.Rename(Done, 'Loop'));
  AssertTrue(Line.Name, Pos('Loop', Line.Name) > 0);
end;

procedure TTestRepeat.TestAlignToARepeatPoint;
var
  Done: TRepeatObject;
  Point: TFreePoint;
  Request: TArrangeRequest;
  Err: string;
begin
  Done := Between(4);
  Point := FPattern.AddFreePoint('P', '5', '50');
  Request := Default(TArrangeRequest);
  Request.Action := aaAlignVertical;
  Request.Points := [Point.Key];
  Request.Reference := Done.Item(3).Key;
  AssertTrue(Err, ApplyArrange(FPattern, Request, nil, Err));
  FPattern.Evaluate;
  AssertNear('lined up', 200, Point.Position.X);
  AssertFalse('so it has an ID', Done.Item(3).IsVirtual);
end;

procedure TTestRepeat.TestDistributeBetweenRepeatPoints;
var
  Done: TRepeatObject;
  Point: TFreePoint;
  Request: TArrangeRequest;
  Err: string;
begin
  Done := Between(4);
  Point := FPattern.AddFreePoint('P', '5', '50');
  Request := Default(TArrangeRequest);
  Request.Action := aaDistribute;
  Request.Points := [Done.Item(1).Key, Done.Item(4).Key, Point.Key];
  AssertTrue(Err, ApplyArrange(FPattern, Request, nil, Err));
  AssertEquals('nothing kept a virtual key', 0, Pos(Done.Key + '[', SavePatternToText(FPattern)));
  AssertEquals(2, Length(Done.UsedItems));
  FPattern.Evaluate;
  AssertNear('between them', 150, TPointObject(FPattern.FindObject('P')).Position.X);
end;

procedure TTestRepeat.TestRepeatPointsAreNotRearranged;
var
  Done: TRepeatObject;
  Request: TArrangeRequest;
  Items: TArrangeItemArray;
  Err: string;
begin
  Done := Between(4);
  Request := Default(TArrangeRequest);
  Request.Action := aaAlignHorizontal;
  Request.Points := [FA.Key, Done.Item(2).Key];
  Request.Reference := FA.Key;
  AssertTrue(Err, PlanArrange(FPattern, Request, Items, Err));
  AssertTrue(Items[0].Choice = acKeep);
  AssertEquals(rsArrangeRepeat, Items[0].Reason);
end;

procedure TTestRepeat.TestListedAsItsPoints;
var
  Rows: TObjectRowArray;
begin
  Between(3);
  Rows := ObjectRows(FPattern, ofAll, '');
  AssertEquals('A, B and three', 5, Length(Rows));
  AssertEquals('Btn[1]', Rows[2].Name);
  AssertEquals('Btn[3]', Rows[4].Name);
  AssertEquals('search', 1, Length(ObjectRows(FPattern, ofAll, 'btn[2')));
end;

procedure TTestRepeat.TestListedUnderPoints;
begin
  Between(3);
  AssertEquals(5, Length(ObjectRows(FPattern, ofPoints, '')));
  AssertEquals(0, Length(ObjectRows(FPattern, ofEdges, '')));
end;

// A bad count leaves no points, and it must still be there to put right
procedure TTestRepeat.TestListedWhenItHasNoPoints;
var
  Rows: TObjectRowArray;
begin
  FPattern.AddRepeatBetween('Btn', FA.Key, FB.Key, '0', True);
  FPattern.Evaluate;
  Rows := ObjectRows(FPattern, ofAll, '');
  AssertEquals(3, Length(Rows));
  AssertEquals('Btn', Rows[2].Name);
end;

procedure TTestRepeat.TestPickedOnTheCanvas;
var
  Done: TRepeatObject;
begin
  Done := Between(4);
  AssertTrue(PointAt(FPattern, Vec2(101, 1), 5) = TObject(Done.Item(2)));
end;

initialization
  RegisterTest(TTestRepeat);

end.
