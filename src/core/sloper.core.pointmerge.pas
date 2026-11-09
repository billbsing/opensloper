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
// Merging points into one and breaking a point into one for each edge that
// meets there. TPattern's MergePoints and BreakPoint call these. No LCL
// dependency.
unit Sloper.Core.PointMerge;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Draft, Sloper.Core.Pattern;

// Joins two or more points into one, as Inkscape joins nodes: one point's
// definition is kept, and whatever used the others uses it instead, then
// they are deleted, with any line or curve that ran between two of them.
// It takes MergedName of their names. Kept is the named point unless it is
// placed from one of the others; then the first that is not. A copy or a
// repeat's point can only be kept. Nil with the reason in the pattern's
// LastError when refused.
function MergePoints(Pattern: TPattern; const Keys: array of string): TPointObject;
// The opposite of MergePoints: a point where several lines, curves or curve
// paths meet becomes one point for each of them. The point itself, renamed
// M1, stays with the first and with everything else that uses it; each other
// edge gets a new point M2, M3 … placed from it by dx 0, dy 0, so it follows
// the point until it is moved apart. The point first, nil with the reason in
// the pattern's LastError when refused.
function BreakPoint(Pattern: TPattern; Point: TPointObject): TPointObjectArray;

resourcestring
  rsPatternMergeTooFew = 'Select two or more points to merge';
  rsPatternMergeNotPoint = '%s is not a point, so it cannot be merged';
  rsPatternMergeTwoFixed = '%s and %s are copies or a repeat''s points, and only one point can be kept';
  rsPatternMergeKeptReads = '%s is placed from %s, so %s cannot be merged into it';
  rsPatternMergeCopied = '%s is copied by %s, so it cannot be merged away';
  rsPatternMergeEdgeInUse = '%s runs between points being merged and is used by %s';
  rsPatternBreakTooFew = '%s joins fewer than two lines or curves, so there is nothing to break';

implementation

uses
  SysUtils, Sloper.Core.Formula, Sloper.Core.Evaluator, Sloper.Core.Names, Sloper.Core.Transform;

function IndexOfObject(const Objects: TDraftObjectArray; DraftObject: TEvalNode): integer;
var
  Index: integer;
begin
  for Index := 0 to High(Objects) do
    if Objects[Index] = DraftObject then
      Exit(Index);
  Result := -1;
end;

// A copy or a repeat's point follows something else, so it cannot be deleted
function IsFixedPoint(Point: TPointObject): boolean;
begin
  Result := (Point is TPointCopy) or (Point is TRepeatPoint);
end;

// The point named AName when it reads none of the others, or else the first
// that reads none of them; a fixed point has to be the one kept
function ChooseKeptPoint(Pattern: TPattern; const Points: TPointObjectArray; const AName: string): TPointObject;
var
  Point, Other, Fixed: TPointObject;

  function ReadsAnother(Candidate: TPointObject): TPointObject;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if (Member <> Candidate) and Pattern.Reaches(Candidate, Member) then
        Exit(Member);
    Result := nil;
  end;

begin
  Result := nil;
  Fixed := nil;
  for Point in Points do
    if IsFixedPoint(Point) then
    begin
      if Assigned(Fixed) then
      begin
        Pattern.SetError(Format(rsPatternMergeTwoFixed, [Fixed.DisplayName, Point.DisplayName]));
        Exit;
      end;
      Fixed := Point;
    end;
  if Assigned(Fixed) then
  begin
    Other := ReadsAnother(Fixed);
    if Assigned(Other) then
      Pattern.SetError(Format(rsPatternMergeKeptReads, [Fixed.DisplayName, Other.DisplayName, Other.DisplayName]))
    else
      Result := Fixed;
    Exit;
  end;
  for Point in Points do
    if SameName(Point.Name, AName) and not Assigned(ReadsAnother(Point)) then
      Exit(Point);
  for Point in Points do
    if not Assigned(ReadsAnother(Point)) then
      Exit(Point);
end;

// Doomed: the points to merge away, and lines and curves between two of the
// points, which nothing else may use
function CheckMergeAway(Pattern: TPattern; const Points: TPointObjectArray; Kept: TPointObject; out Doomed: TDraftObjectArray): boolean;
var
  Point: TPointObject;
  User: TEvalNode;
  Index, NodeIndex: integer;
  Edge: TEdgeObject;
  Path: TCurvePathObject;

  function InGroup(const Key: string): boolean;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if Member.Key = Key then
        Exit(True);
    Result := False;
  end;

begin
  Result := False;
  Doomed := nil;
  for Point in Points do
    if Point <> Kept then
    begin
      for User in Pattern.UsersOf(Point) do
        if User is TPointCopy then
          Exit(Pattern.SetError(Format(rsPatternMergeCopied, [Point.DisplayName, Pattern.FindNode(TPointCopy(User).TransformKey).DisplayName])));
      Insert(Point, Doomed, Length(Doomed));
    end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if Pattern.Objects[Index] is TCurvePathObject then
    begin
      Path := TCurvePathObject(Pattern.Objects[Index]);
      for NodeIndex := 1 to High(Path.NodeKeys) do
        if InGroup(Path.NodeKeys[NodeIndex - 1]) and InGroup(Path.NodeKeys[NodeIndex]) then
          Exit(Pattern.SetError(rsPatternPathRepeats));
    end;
    if not ((Pattern.Objects[Index].ClassType = TLineObject) or (Pattern.Objects[Index].ClassType = TCurveObject)) then
      Continue;
    Edge := TEdgeObject(Pattern.Objects[Index]);
    if InGroup(Edge.StartKey) and InGroup(Edge.EndKey) then
      Insert(Edge, Doomed, Length(Doomed));
  end;
  for Index := 0 to High(Doomed) do
    if Doomed[Index] is TEdgeObject then
      for User in Pattern.UsersOf(Doomed[Index]) do
        if IndexOfObject(Doomed, User) < 0 then
          Exit(Pattern.SetError(Format(rsPatternMergeEdgeInUse, [Doomed[Index].DisplayName, User.DisplayName])));
  Result := True;
end;

// Every object but the doomed reads KeptKey instead of Point, in its inputs
// and its formulas
procedure RedirectUsers(Pattern: TPattern; Point: TPointObject; const KeptKey: string; const Doomed: TDraftObjectArray);
var
  Node: TEvalNode;
  Ref: TFormulaReference;
  Index: integer;
  Formula: TFormula;
begin
  for Node in Pattern.AllNodes do
  begin
    if not (Node is TDraftObject) or (IndexOfObject(Doomed, Node) >= 0) then
      Continue;
    TDraftObject(Node).RedirectPoint(Point.Key, KeptKey);
    for Index := 0 to Node.FieldCount - 1 do
    begin
      Formula := Node.Fields[Index].Formula;
      for Ref in Formula.References do
        if Ref.Id = Point.Key then
        begin
          // In stored form braces hold only IDs
          Formula.ParseStored(StringReplace(Formula.StoredText, '{' + Point.Key + '}', '{' + KeptKey + '}', [rfReplaceAll]));
          Break;
        end;
    end;
  end;
end;

function MergePoints(Pattern: TPattern; const Keys: array of string): TPointObject;
var
  Points: TPointObjectArray;
  Names: TStringArray;
  Doomed: TDraftObjectArray;
  Key, KeptKey, NewName: string;
  Node: TEvalNode;
  Item: TDraftObject;
  Deleted: boolean;
  Index: integer;

  function HasPoint(Candidate: TEvalNode): boolean;
  var
    Member: TPointObject;
  begin
    for Member in Points do
      if Member = Candidate then
        Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  Points := nil;
  Names := nil;
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if not Assigned(Node) then
    begin
      Pattern.SetError(Format(rsPatternUnknownObject, [Key]));
      Exit;
    end;
    if not (Node is TPointObject) then
    begin
      Pattern.SetError(Format(rsPatternMergeNotPoint, [Node.DisplayName]));
      Exit;
    end;
    if not HasPoint(Node) then
    begin
      Insert(TPointObject(Node), Points, Length(Points));
      Insert(TPointObject(Node).Name, Names, Length(Names));
    end;
  end;
  if Length(Points) < 2 then
  begin
    Pattern.SetError(rsPatternMergeTooFew);
    Exit;
  end;
  NewName := MergedName(Names);
  Result := ChooseKeptPoint(Pattern, Points, NewName);
  if not Assigned(Result) or not CheckMergeAway(Pattern, Points, Result, Doomed) then
    Exit(nil);
  // A repeat's point that nothing uses yet needs an ID before anything can
  KeptKey := Pattern.UsePoint(Result.Key);
  // The evaluator may hold the nodes; forget the old graph
  Pattern.ForgetGraph;
  for Item in Doomed do
    if Item is TPointObject then
      RedirectUsers(Pattern, TPointObject(Item), KeptKey, Doomed);
  // Doomed objects may read each other, so each goes once nothing does
  repeat
    Deleted := False;
    for Index := High(Doomed) downto 0 do
      if Length(Pattern.UsersOf(Doomed[Index])) = 0 then
      begin
        Pattern.DeleteNode(Doomed[Index]);
        System.Delete(Doomed, Index, 1);
        Deleted := True;
      end;
  until not Deleted;
  Result := TPointObject(Pattern.FindNode(KeptKey));
  if not IsFixedPoint(Result) then
    Result.Name := NewName;
  Pattern.UpdateDerivedNames;
  Pattern.OrderObjectsByInputs;
end;

// Lines, curves and curve paths that pass through or end at Point, in list
// order; derived edges follow their sources and are left out
function ConnectingEdges(Pattern: TPattern; Point: TPointObject): TDraftObjectArray;
var
  Index: integer;
  Candidate: TDraftObject;
  Key: string;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    Candidate := Pattern.Objects[Index];
    if (Candidate.ClassType <> TLineObject) and (Candidate.ClassType <> TCurveObject) and (Candidate.ClassType <> TCurvePathObject) then
      Continue;
    for Key in Candidate.InputKeys do
      if Key = Point.Key then
      begin
        Insert(Candidate, Result, Length(Result));
        Break;
      end;
  end;
end;

// Base followed by the next number from Number that no other object has
function NextBrokenName(Pattern: TPattern; const Base: string; var Number: integer; Own: TDraftObject): string;
var
  Taken: TDraftObject;
begin
  repeat
    Result := Base + IntToStr(Number);
    Inc(Number);
    Taken := Pattern.FindObject(Result);
  until not Assigned(Taken) or (Taken = Own);
end;

function BreakPoint(Pattern: TPattern; Point: TPointObject): TPointObjectArray;
var
  Edges: TDraftObjectArray;
  Base: string;
  Number, Index: integer;
  Added: TOffsetPoint;
begin
  Result := nil;
  if Point is TRepeatPoint then
  begin
    Pattern.SetError(Format(rsPatternRepeatItem, [Point.DisplayName]));
    Exit;
  end;
  if Point is TPointCopy then
  begin
    Pattern.SetError(Format(rsPatternCopyOfTransform, [Point.DisplayName, Pattern.FindNode(TPointCopy(Point).TransformKey).DisplayName]));
    Exit;
  end;
  Edges := ConnectingEdges(Pattern, Point);
  if Length(Edges) < 2 then
  begin
    Pattern.SetError(Format(rsPatternBreakTooFew, [Point.DisplayName]));
    Exit;
  end;
  // A copy's number is replaced, as when copying: M2 breaks into M3, M4
  Base := Point.Name;
  while (Length(Base) > 1) and (Base[Length(Base)] in ['0'..'9']) do
    System.Delete(Base, Length(Base), 1);
  Number := 1;
  Point.Name := NextBrokenName(Pattern, Base, Number, Point);
  Insert(Point, Result, 0);
  for Index := 1 to High(Edges) do
  begin
    Added := Pattern.AddOffsetPoint(NextBrokenName(Pattern, Base, Number, nil), Point.Key, omCartesian, '0', '0');
    if not Assigned(Added) then
      Exit(nil);
    Edges[Index].RedirectPoint(Point.Key, Added.Key);
    Insert(TPointObject(Added), Result, Length(Result));
  end;
  // The evaluator may hold the old graph
  Pattern.ForgetGraph;
  Pattern.UpdateDerivedNames;
  Pattern.OrderObjectsByInputs;
end;

end.
