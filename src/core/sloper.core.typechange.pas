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
// Changing a point's operation, or an edge between a line and a curve, in
// place: the object keeps its ID, name and users, so whatever reads it carries
// on. TPattern's ConvertTo methods call these. No LCL dependency.
unit Sloper.Core.TypeChange;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Draft, Sloper.Core.Pattern;

// Point is freed. Formulas are in stored form. Nil with the reason in the
// pattern's LastError on failure, when Point is left as it was.
function ConvertToFree(Pattern: TPattern; Point: TPointObject; const XText, YText: string): TFreePoint;
function ConvertToBetween(Pattern: TPattern; Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode;
  const Value: string): TBetweenPoint;
function ConvertToAlongEdge(Pattern: TPattern; Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode;
  const Value: string): TAlongEdgePoint;
// Its role and place stay, and a name the user gave it is kept. An arc
// becomes a line between two new points at its ends, offsets from its centre
// by its own formulas. A new curve starts straight, its handles a third of
// the way along. Refused for a circle, a copy, a derived edge, a line whose
// angle a formula reads, and a line a fold follows.
function ConvertToLine(Pattern: TPattern; Edge: TEdgeObject): TLineObject;
function ConvertToCurve(Pattern: TPattern; Edge: TEdgeObject): TCurveObject;
// Carries a curve or curve path on through PointId, as one curve path that
// keeps the edge's ID, name and role. The handles it had stay, but the point
// it ended at turns to run smoothly on to PointId, and the new stretch's
// handles are a third of its length. Refused for any other kind of edge, a
// copy, an edge something uses (its end moves), and the point it ends at.
function ExtendCurve(Pattern: TPattern; Edge: TEdgeObject; const PointId: string): TCurvePathObject;

resourcestring
  rsPatternNotConvertible = '%s cannot be changed: only lines, curves and arcs can become a line or a curve';
  rsPatternAlreadyLine = '%s is already a line';
  rsPatternAlreadyCurve = '%s is already a curve';
  rsPatternCircleNoEnds = '%s is a whole circle, so it has no ends to join with a line';
  rsPatternOnlyLineToCurve = 'Only a line can become a curve, and %s is an arc';
  rsPatternAngleInUse = '%s reads %s.angle, which only a line has, so it cannot become a curve';
  rsPatternFoldFollows = '%s is the fold of %s, so %s cannot become a curve';
  rsPatternNotExtendable = '%s cannot be carried on: only a curve or a curve path can';
  rsPatternExtendInUse = '%s is used by %s, so it cannot be carried on';
  rsPatternExtendSamePoint = '%s already ends at %s';

implementation

uses
  SysUtils, StrUtils, Math, Sloper.Core.Geometry, Sloper.Core.Formula, Sloper.Core.Evaluator, Sloper.Core.Piece,
  Sloper.Core.Transform, Sloper.Core.Units;

// Lines, curves and arcs the user drew; copies and parts follow other edges
function CheckConvertible(Pattern: TPattern; Edge: TEdgeObject): boolean;
begin
  if Edge is TEdgeCopy then
    Exit(Pattern.SetError(Format(rsPatternCopyOfTransform, [Edge.DisplayName, Pattern.FindNode(TEdgeCopy(Edge).TransformKey).DisplayName])));
  if Edge.ClassType = TCircleObject then
    Exit(Pattern.SetError(Format(rsPatternCircleNoEnds, [Edge.DisplayName])));
  if (Edge.ClassType <> TLineObject) and (Edge.ClassType <> TCurveObject) and (Edge.ClassType <> TArcObject) then
    Exit(Pattern.SetError(Format(rsPatternNotConvertible, [Edge.DisplayName])));
  Result := True;
end;

// False, with the reason, when a piece's fold is Edge or an edge that is
// straight only while Edge is: its parts, copies and offsets
function CheckNoFoldFollows(Pattern: TPattern; Edge: TEdgeObject): boolean;
var
  Following: TStringArray;
  DraftObject: TDraftObject;
  Source: string;
  Piece: TPieceObject;
  Index: integer;
begin
  Following := [Edge.Key];
  // The objects are in input order, so a part of a part is found after its source
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    Source := '';
    if DraftObject is TSplitPart then
      Source := TSplitPart(DraftObject).Source
    else if DraftObject is TEdgeCopy then
      Source := TEdgeCopy(DraftObject).Source
    else if (DraftObject is TOffsetEdge) and (Length(TOffsetEdge(DraftObject).Run) = 1) then
      Source := TOffsetEdge(DraftObject).Run[0].EdgeKey;
    if (Source <> '') and (IndexStr(Source, Following) >= 0) then
      Insert(DraftObject.Key, Following, Length(Following));
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      if (Piece.FoldEdgeKey <> '') and (IndexStr(Piece.FoldEdgeKey, Following) >= 0) then
        Exit(Pattern.SetError(Format(rsPatternFoldFollows, [Pattern.FindNode(Piece.FoldEdgeKey).DisplayName, Piece.DisplayName, Edge.DisplayName])));
    end;
  Result := True;
end;

function ConvertToLine(Pattern: TPattern; Edge: TEdgeObject): TLineObject;
var
  StartPoint, EndPoint: TOffsetPoint;
  Radius: string;
begin
  Result := nil;
  if not CheckConvertible(Pattern, Edge) then
    Exit;
  if Edge is TLineObject then
  begin
    Pattern.SetError(Format(rsPatternAlreadyLine, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    Radius := Pattern.FormulaText(Edge, 'radius');
    StartPoint := Pattern.AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, Pattern.FormulaText(Edge, 'angle1'));
    if not Assigned(StartPoint) then
      Exit;
    EndPoint := Pattern.AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, Pattern.FormulaText(Edge, 'angle2'));
    if not Assigned(EndPoint) then
      Exit;
    Result := TLineObject.Create(Edge.Key, StartPoint.Key, EndPoint.Key);
  end
  else
    Result := TLineObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not Pattern.ReplaceEdge(Edge, Result, [], []) then
    Result := nil;
end;

function ConvertToCurve(Pattern: TPattern; Edge: TEdgeObject): TCurveObject;
var
  User: TEvalNode;
  FieldIndex: integer;
  Ref: TFormulaReference;
  Direction, BackAngle, Handle: double;
  Formats: TFormatSettings;

  function Text(Value: double): string;
  begin
    Result := FloatToStr(RoundTo(Value, -1), Formats);
  end;

begin
  Result := nil;
  if not CheckConvertible(Pattern, Edge) then
    Exit;
  if Edge is TCurveObject then
  begin
    Pattern.SetError(Format(rsPatternAlreadyCurve, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    Pattern.SetError(Format(rsPatternOnlyLineToCurve, [Edge.DisplayName]));
    Exit;
  end;
  for User in Pattern.UsersOf(Edge) do
    for FieldIndex := 0 to User.FieldCount - 1 do
      for Ref in User.Fields[FieldIndex].Formula.References do
        if (ReferenceKey(Ref) = Edge.Key) and SameText(Ref.Prop, 'angle') then
        begin
          Pattern.SetError(Format(rsPatternAngleInUse, [User.DisplayName, Edge.DisplayName]));
          Exit;
        end;
  if not CheckNoFoldFollows(Pattern, Edge) then
    Exit;
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  // The handles are placed from where the line is now
  if not Edge.HasResult then
    Pattern.Evaluate;
  Direction := 0;
  Handle := 0;
  if Edge.HasResult then
  begin
    Direction := Edge.StartDirection;
    Handle := Edge.Length / 3;
  end;
  // The end handle points back along the edge
  BackAngle := FMod(Direction + 180, 360);
  Result := TCurveObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not Pattern.ReplaceEdge(Edge, Result, ['angle1', 'length1', 'angle2', 'length2'],
    [Text(Direction), RoundLengthFormulaText(Handle, Pattern.Units), Text(BackAngle), RoundLengthFormulaText(Handle, Pattern.Units)]) then
    Result := nil;
end;

function ConvertToFree(Pattern: TPattern; Point: TPointObject; const XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create(Point.Key);
  if not Pattern.ReplacePoint(Point, Result, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function ConvertToBetween(Pattern: TPattern; Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := nil;
  if not Pattern.CheckPoint(FirstId) or not Pattern.CheckPoint(LastId) then
    Exit;
  Result := TBetweenPoint.Create(Point.Key, FirstId, LastId, Mode);
  if not Pattern.ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
end;

function ConvertToAlongEdge(Pattern: TPattern; Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode;
  const Value: string): TAlongEdgePoint;
begin
  Result := nil;
  if not Pattern.CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TAlongEdgePoint.Create(Point.Key, EdgeId, FromEnd, Mode);
  if not Pattern.ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
end;

function ExtendCurve(Pattern: TPattern; Edge: TEdgeObject; const PointId: string): TCurvePathObject;
var
  Users: TEvalNodeArray;
  Nodes, Names, Texts: TStringArray;
  Count, Index: integer;
  Before, Last, Next: TVec2;
  Handle: double;
  Formats: TFormatSettings;

  function Text(Value: double): string;
  begin
    Result := FloatToStr(RoundTo(Value, -1), Formats);
  end;

  procedure Keep(const NewName, OldName: string);
  begin
    Insert(NewName, Names, Length(Names));
    Insert(Edge.Field(OldName).StoredText, Texts, Length(Texts));
  end;

  procedure Put(const NewName, AText: string);
  begin
    Insert(NewName, Names, Length(Names));
    Insert(AText, Texts, Length(Texts));
  end;

  function PositionOf(const Key: string): TVec2;
  begin
    Result := TPointObject(Pattern.FindNode(Key)).Position;
  end;

begin
  Result := nil;
  if Edge is TEdgeCopy then
  begin
    Pattern.SetError(Format(rsPatternCopyOfTransform, [Edge.DisplayName, Pattern.FindNode(TEdgeCopy(Edge).TransformKey).DisplayName]));
    Exit;
  end;
  if (Edge.ClassType <> TCurveObject) and (Edge.ClassType <> TCurvePathObject) then
  begin
    Pattern.SetError(Format(rsPatternNotExtendable, [Edge.DisplayName]));
    Exit;
  end;
  Users := Pattern.UsersOf(Edge);
  if Length(Users) > 0 then
  begin
    Pattern.SetError(Format(rsPatternExtendInUse, [Edge.DisplayName, Users[0].DisplayName]));
    Exit;
  end;
  if not Pattern.CheckPoint(PointId) then
    Exit;
  if PointId = Edge.EndKey then
  begin
    Pattern.SetError(Format(rsPatternExtendSamePoint, [Edge.DisplayName, Pattern.FindNode(PointId).DisplayName]));
    Exit;
  end;
  if Edge is TCurvePathObject then
    Nodes := Copy(TCurvePathObject(Edge).NodeKeys)
  else
    Nodes := [Edge.StartKey, Edge.EndKey];
  Count := Length(Nodes);
  // The new handles are placed from where the points are now
  if not Edge.HasResult or not Pattern.FindNode(PointId).HasResult then
    Pattern.Evaluate;
  Before := PositionOf(Nodes[Count - 2]);
  Last := PositionOf(Nodes[Count - 1]);
  Next := PositionOf(PointId);
  Handle := Distance(Last, Next) / 3;
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  Names := nil;
  Texts := nil;
  if Edge is TCurveObject then
  begin
    Keep('node1.angle', 'angle1');
    Keep('node1.lengthOut', 'length1');
    Keep('node2.lengthIn', 'length2');
  end
  else
    for Index := 1 to Count do
    begin
      if Index > 1 then
        Keep(Format('node%d.lengthIn', [Index]), Format('node%d.lengthIn', [Index]));
      if Index < Count then
      begin
        Keep(Format('node%d.angle', [Index]), Format('node%d.angle', [Index]));
        Keep(Format('node%d.lengthOut', [Index]), Format('node%d.lengthOut', [Index]));
      end;
    end;
  // The old end runs on from the point before it towards the new one
  Put(Format('node%d.angle', [Count]), Text(AngleBetween(Before, Next)));
  Put(Format('node%d.lengthOut', [Count]), RoundLengthFormulaText(Handle, Pattern.Units));
  Put(Format('node%d.lengthIn', [Count + 1]), RoundLengthFormulaText(Handle, Pattern.Units));
  Put(Format('node%d.angle', [Count + 1]), Text(AngleBetween(Last, Next)));
  Insert(PointId, Nodes, Length(Nodes));
  Result := TCurvePathObject.Create(Edge.Key, Nodes);
  if not Pattern.ReplaceEdge(Edge, Result, Names, Texts) then
    Result := nil;
end;

end.
