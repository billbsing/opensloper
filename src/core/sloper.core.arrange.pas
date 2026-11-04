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

// Align and distribute. Each action rewrites the selected points' definitions
// rather than moving them, so the arrangement holds when measurements change.
// PlanArrange says what would happen to each point without changing anything,
// so that nothing driven by a formula is overwritten unasked; ApplyArrange then
// does it. No LCL dependency.
unit Sloper.Core.Arrange;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Pattern;

type
  TArrangeAction = (aaAlignVertical, aaAlignHorizontal, aaDistribute, aaDistributeHorizontal, aaDistributeVertical, aaDistributeAlongEdge);

  TArrangeRequest = record
    Action: TArrangeAction;
    // The selected points
    Points: TStringArray;
    // What aligning lines up with; it need not be selected
    Reference: string;
    // What aaDistributeAlongEdge runs along
    Edge: string;
  end;

  // acChange happens; acAsk needs a yes, since it would replace a formula or an
  // operation; acKeep cannot happen, or the point already is that way
  TArrangeChoice = (acChange, acAsk, acKeep);

  TArrangeItem = record
    Key, Name: string;
    Choice: TArrangeChoice;
    // Why, for acAsk and acKeep
    Reason: string;
  end;

  TArrangeItemArray = array of TArrangeItem;

// False with ErrorMessage set when the action cannot be done with these points
function PlanArrange(Pattern: TPattern; const Request: TArrangeRequest; out Items: TArrangeItemArray; out ErrorMessage: string): boolean;
// Changes the acChange points, and the acAsk points listed in Replace. On
// failure some may have changed, so call it inside a change that can be
// cancelled.
function ApplyArrange(Pattern: TPattern; const Request: TArrangeRequest; const Replace: TStringArray; out ErrorMessage: string): boolean;

resourcestring
  rsArrangeTooFewToAlign = 'Select at least one point to line up with the reference';
  rsArrangeNoReference = 'Choose a point to line up with';
  rsArrangeTooFewToDistribute = 'Select at least three points: the two outermost stay where they are';
  rsArrangeNoEdge = 'Select the line or curve as well as the points';
  rsArrangeNothingOnEdge = 'Select at least one point that is not an end of the edge';
  rsArrangeFormula = 'its position comes from a formula';
  rsArrangeOperation = 'its position comes from its operation, which this would replace';
  rsArrangeDepends = 'it is used by the points it would need, so it was left alone';
  rsArrangeAlready = 'it is already there';
  rsArrangeRepeat = 'it is part of a repeat, so it can only be moved by editing the repeat';

implementation

uses
  Math, Sloper.Core.Draft, Sloper.Core.Evaluator, Sloper.Core.Formula, Sloper.Core.Geometry, Sloper.Core.JSON;

type
  TArrangeAxis = (axX, axY);

  // What one point is to become
  TArrangeTarget = record
    Point: TPointObject;
    // The formula for its x or y, for the actions that keep the other one
    Formula: string;
    // Or the formula for a between or along edge point
    Value: string;
    // The objects those read, to check nothing goes round in a circle
    Reads: TStringArray;
  end;

  TArrangeTargetArray = array of TArrangeTarget;

const
  AxisFields: array[TArrangeAxis] of string = ('x', 'y');
  OffsetFields: array[TArrangeAxis] of string = ('dx', 'dy');

function PointNamed(Pattern: TPattern; const Key: string): TPointObject;
var
  Node: TObject;
begin
  Node := Pattern.FindNode(Key);
  if Node is TPointObject then
    Result := TPointObject(Node)
  else
    Result := nil;
end;

function ActionAxis(Action: TArrangeAction): TArrangeAxis;
begin
  if Action in [aaAlignVertical, aaDistributeHorizontal] then
    Result := axX
  else
    Result := axY;
end;

function AxisValue(Point: TPointObject; Axis: TArrangeAxis): double;
begin
  if Axis = axX then
    Result := Point.Position.X
  else
    Result := Point.Position.Y;
end;

function AxisReference(const Key: string; Axis: TArrangeAxis): string;
begin
  Result := '{' + Key + '}.' + AxisFields[Axis];
end;

function SelectedPoints(Pattern: TPattern; const Keys: TStringArray): specialize TArray<TPointObject>;
var
  Key: string;
  Point: TPointObject;
begin
  Result := nil;
  for Key in Keys do
  begin
    Point := PointNamed(Pattern, Key);
    if Assigned(Point) then
      Insert(Point, Result, Length(Result));
  end;
end;

// Sorts by Keys[], smallest first, keeping the order of equal ones
procedure SortPoints(var Points: specialize TArray<TPointObject>; var Keys: array of double);
var
  Index, Scan: integer;
  Point: TPointObject;
  Key: double;
begin
  for Index := 1 to High(Points) do
  begin
    Point := Points[Index];
    Key := Keys[Index];
    Scan := Index - 1;
    while (Scan >= 0) and (Keys[Scan] > Key) do
    begin
      Points[Scan + 1] := Points[Scan];
      Keys[Scan + 1] := Keys[Scan];
      Dec(Scan);
    end;
    Points[Scan + 1] := Point;
    Keys[Scan + 1] := Key;
  end;
end;

procedure AddTarget(var Targets: TArrangeTargetArray; Point: TPointObject; const Formula, Value: string; const Reads: array of string);
var
  Index: integer;
begin
  SetLength(Targets, Length(Targets) + 1);
  Targets[High(Targets)].Point := Point;
  Targets[High(Targets)].Formula := Formula;
  Targets[High(Targets)].Value := Value;
  SetLength(Targets[High(Targets)].Reads, Length(Reads));
  for Index := 0 to High(Reads) do
    Targets[High(Targets)].Reads[Index] := Reads[Index];
end;

function AlignTargets(Pattern: TPattern; const Request: TArrangeRequest; out Targets: TArrangeTargetArray; out ErrorMessage: string): boolean;
var
  Point: TPointObject;
  Axis: TArrangeAxis;
begin
  ErrorMessage := '';
  Targets := nil;
  if not Assigned(PointNamed(Pattern, Request.Reference)) then
  begin
    ErrorMessage := rsArrangeNoReference;
    Exit(False);
  end;
  Axis := ActionAxis(Request.Action);
  for Point in SelectedPoints(Pattern, Request.Points) do
    if Point.Key <> Request.Reference then
      AddTarget(Targets, Point, AxisReference(Request.Reference, Axis), '', [Request.Reference]);
  Result := Length(Targets) > 0;
  if not Result then
    ErrorMessage := rsArrangeTooFewToAlign;
end;

// The farthest apart stay, and the rest go between them in the order they lie
function DistributeTargets(Pattern: TPattern; const Request: TArrangeRequest; out Targets: TArrangeTargetArray; out First, Last: TPointObject;
  out ErrorMessage: string): boolean;
var
  Points: specialize TArray<TPointObject>;
  Along: array of double;
  Index, Other: integer;
  Widest: double;
  Chord: TVec2;
begin
  ErrorMessage := '';
  Targets := nil;
  First := nil;
  Last := nil;
  Points := SelectedPoints(Pattern, Request.Points);
  if Length(Points) < 3 then
  begin
    ErrorMessage := rsArrangeTooFewToDistribute;
    Exit(False);
  end;
  Widest := -1;
  for Index := 0 to High(Points) do
    for Other := Index + 1 to High(Points) do
      if Distance(Points[Index].Position, Points[Other].Position) > Widest then
      begin
        Widest := Distance(Points[Index].Position, Points[Other].Position);
        First := Points[Index];
        Last := Points[Other];
      end;
  Chord := Last.Position - First.Position;
  Along := nil;
  SetLength(Along, Length(Points));
  for Index := 0 to High(Points) do
    Along[Index] := Dot(Points[Index].Position - First.Position, Chord);
  SortPoints(Points, Along);
  for Index := 0 to High(Points) do
    if (Points[Index] <> First) and (Points[Index] <> Last) then
      AddTarget(Targets, Points[Index], '', '', [First.Key, Last.Key]);
  for Index := 0 to High(Targets) do
    Targets[Index].Value := Format('%d / %d', [Index + 1, Length(Targets) + 1]);
  Result := True;
end;

// Each coordinate is spaced on its own, between the two furthest out on it
function DistributeAxisTargets(Pattern: TPattern; const Request: TArrangeRequest; out Targets: TArrangeTargetArray; out ErrorMessage: string): boolean;
var
  Points: specialize TArray<TPointObject>;
  Along: array of double;
  Index, Steps: integer;
  Axis: TArrangeAxis;
  Low_, High_: string;
begin
  ErrorMessage := '';
  Targets := nil;
  Points := SelectedPoints(Pattern, Request.Points);
  if Length(Points) < 3 then
  begin
    ErrorMessage := rsArrangeTooFewToDistribute;
    Exit(False);
  end;
  Axis := ActionAxis(Request.Action);
  Along := nil;
  SetLength(Along, Length(Points));
  for Index := 0 to High(Points) do
    Along[Index] := AxisValue(Points[Index], Axis);
  SortPoints(Points, Along);
  Low_ := AxisReference(Points[0].Key, Axis);
  High_ := AxisReference(Points[High(Points)].Key, Axis);
  Steps := High(Points);
  for Index := 1 to High(Points) - 1 do
    AddTarget(Targets, Points[Index], Format('%s + (%s - %s) * %d / %d', [Low_, High_, Low_, Index, Steps]), '', [Points[0].Key, Points[High(Points)].Key]);
  Result := True;
end;

// The whole length of the edge is shared out, between its two ends
function EdgeTargets(Pattern: TPattern; const Request: TArrangeRequest; out Targets: TArrangeTargetArray; out ErrorMessage: string): boolean;
var
  Node: TObject;
  Edge: TEdgeObject;
  Points, Inner: specialize TArray<TPointObject>;
  Point: TPointObject;
  Along: array of double;
  Index: integer;
  Offset: double;
begin
  ErrorMessage := '';
  Targets := nil;
  Node := Pattern.FindNode(Request.Edge);
  if not (Node is TEdgeObject) then
  begin
    ErrorMessage := rsArrangeNoEdge;
    Exit(False);
  end;
  Edge := TEdgeObject(Node);
  Points := SelectedPoints(Pattern, Request.Points);
  Inner := nil;
  for Point in Points do
    if (Point.Key <> Edge.StartKey) and (Point.Key <> Edge.EndKey) then
      Insert(Point, Inner, Length(Inner));
  if not Assigned(Inner) then
  begin
    ErrorMessage := rsArrangeNothingOnEdge;
    Exit(False);
  end;
  Along := nil;
  SetLength(Along, Length(Inner));
  for Index := 0 to High(Inner) do
    Edge.Locate(Inner[Index].Position, Along[Index], Offset);
  SortPoints(Inner, Along);
  for Index := 0 to High(Inner) do
    AddTarget(Targets, Inner[Index], '', Format('%d / %d', [Index + 1, Length(Inner) + 1]), [Edge.Key]);
  Result := True;
end;

function BuildTargets(Pattern: TPattern; const Request: TArrangeRequest; out Targets: TArrangeTargetArray; out First, Last: TPointObject;
  out ErrorMessage: string): boolean;
begin
  First := nil;
  Last := nil;
  case Request.Action of
    aaAlignVertical, aaAlignHorizontal:
      Result := AlignTargets(Pattern, Request, Targets, ErrorMessage);
    aaDistribute:
      Result := DistributeTargets(Pattern, Request, Targets, First, Last, ErrorMessage);
    aaDistributeHorizontal, aaDistributeVertical:
      Result := DistributeAxisTargets(Pattern, Request, Targets, ErrorMessage);
    else
      Result := EdgeTargets(Pattern, Request, Targets, ErrorMessage);
  end;
end;

function AllLiteral(Point: TPointObject): boolean;
var
  Index: integer;
begin
  for Index := 0 to Point.FieldCount - 1 do
    if not Point.Fields[Index].Formula.IsLiteral then
      Exit(False);
  Result := True;
end;

function IsPlainPoint(Point: TPointObject): boolean;
begin
  Result := (Point is TFreePoint) or (Point is TOffsetPoint) or (Point is TBetweenPoint) or (Point is TAlongEdgePoint);
end;

// The field an axis action writes, '' when the point has none and must become
// a free point
function AxisFieldOf(Point: TPointObject; Axis: TArrangeAxis): string;
begin
  Result := '';
  if Point is TFreePoint then
    Result := AxisFields[Axis]
  else if (Point is TOffsetPoint) and (TOffsetPoint(Point).Mode = omCartesian) then
    Result := OffsetFields[Axis];
end;

// An offset's dx or dy is measured from its base
function AxisFieldText(Point: TPointObject; const Formula: string; Axis: TArrangeAxis): string;
begin
  if Point is TOffsetPoint then
    Result := Format('%s - %s', [Formula, AxisReference(TOffsetPoint(Point).Base, Axis)])
  else
    Result := Formula;
end;

function ReadsPoint(Pattern: TPattern; const Target: TArrangeTarget): boolean;
var
  Key: string;
  Node: TEvalNode;
begin
  Result := False;
  for Key in Target.Reads do
  begin
    Node := Pattern.FindNode(Key);
    if (Node = Target.Point) or (Assigned(Node) and Pattern.Reaches(Node, Target.Point)) then
      Exit(True);
  end;
end;

procedure Classify(Pattern: TPattern; Action: TArrangeAction; const Target: TArrangeTarget; var Item: TArrangeItem);
var
  FieldName: string;
  Axis: TArrangeAxis;
begin
  Item.Key := Target.Point.Key;
  Item.Name := Target.Point.DisplayName;
  Item.Choice := acChange;
  Item.Reason := '';
  if Target.Point is TRepeatPoint then
  begin
    Item.Choice := acKeep;
    Item.Reason := rsArrangeRepeat;
    Exit;
  end;
  if ReadsPoint(Pattern, Target) then
  begin
    Item.Choice := acKeep;
    Item.Reason := rsArrangeDepends;
    Exit;
  end;
  if Target.Formula <> '' then
  begin
    Axis := ActionAxis(Action);
    FieldName := AxisFieldOf(Target.Point, Axis);
    if FieldName = '' then
    begin
      Item.Choice := acAsk;
      Item.Reason := rsArrangeOperation;
    end
    else if Target.Point.Field(FieldName).StoredText = AxisFieldText(Target.Point, Target.Formula, Axis) then
    begin
      Item.Choice := acKeep;
      Item.Reason := rsArrangeAlready;
    end
    else if not Target.Point.Field(FieldName).IsLiteral then
    begin
      Item.Choice := acAsk;
      Item.Reason := rsArrangeFormula;
    end;
    Exit;
  end;
  if not IsPlainPoint(Target.Point) then
  begin
    Item.Choice := acAsk;
    Item.Reason := rsArrangeOperation;
  end
  else if not AllLiteral(Target.Point) then
  begin
    Item.Choice := acAsk;
    Item.Reason := rsArrangeFormula;
  end;
end;

function PlanArrange(Pattern: TPattern; const Request: TArrangeRequest; out Items: TArrangeItemArray; out ErrorMessage: string): boolean;
var
  Targets: TArrangeTargetArray;
  First, Last: TPointObject;
  Index: integer;
begin
  Items := nil;
  Result := BuildTargets(Pattern, Request, Targets, First, Last, ErrorMessage);
  if not Result then
    Exit;
  SetLength(Items, Length(Targets));
  for Index := 0 to High(Targets) do
    Classify(Pattern, Request.Action, Targets[Index], Items[Index]);
end;

function ApplyTarget(Pattern: TPattern; const Request: TArrangeRequest; const Target: TArrangeTarget; First, Last: TPointObject): boolean;
var
  Axis: TArrangeAxis;
  FieldName, Other: string;
begin
  case Request.Action of
    aaDistribute:
      Exit(Assigned(Pattern.ConvertToBetween(Target.Point, First.Key, Last.Key, amRatio, Target.Value)));
    aaDistributeAlongEdge:
      Exit(Assigned(Pattern.ConvertToAlongEdge(Target.Point, Request.Edge, False, amRatio, Target.Value)));
  end;
  Axis := ActionAxis(Request.Action);
  FieldName := AxisFieldOf(Target.Point, Axis);
  if FieldName <> '' then
    Exit(Pattern.SetStoredFormula(Target.Point, FieldName, AxisFieldText(Target.Point, Target.Formula, Axis)));
  // The other coordinate stays where it is, as a number
  if Axis = axX then
  begin
    Other := FormatJSONFloat(Target.Point.Position.Y);
    Result := Assigned(Pattern.ConvertToFree(Target.Point, Target.Formula, Other));
  end
  else
  begin
    Other := FormatJSONFloat(Target.Point.Position.X);
    Result := Assigned(Pattern.ConvertToFree(Target.Point, Other, Target.Formula));
  end;
end;

function ApplyArrange(Pattern: TPattern; const Request: TArrangeRequest; const Replace: TStringArray; out ErrorMessage: string): boolean;
var
  Targets: TArrangeTargetArray;
  First, Last: TPointObject;
  Index: integer;
  Item: TArrangeItem;
  Key: string;
  Wanted: boolean;
  Used: TArrangeRequest;
begin
  // Anything these read must have an ID to be read by
  Used := Request;
  Used.Points := Copy(Request.Points);
  for Index := 0 to High(Used.Points) do
    Used.Points[Index] := Pattern.UsePoint(Used.Points[Index]);
  Used.Reference := Pattern.UsePoint(Request.Reference);
  Result := BuildTargets(Pattern, Used, Targets, First, Last, ErrorMessage);
  if not Result then
    Exit;
  for Index := 0 to High(Targets) do
  begin
    Item := Default(TArrangeItem);
    Classify(Pattern, Used.Action, Targets[Index], Item);
    Wanted := Item.Choice = acChange;
    if Item.Choice = acAsk then
      for Key in Replace do
        Wanted := Wanted or (Key = Item.Key);
    if Wanted and not ApplyTarget(Pattern, Used, Targets[Index], First, Last) then
    begin
      ErrorMessage := Pattern.LastError;
      Exit(False);
    end;
  end;
end;

end.
