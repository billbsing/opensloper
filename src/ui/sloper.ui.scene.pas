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

// What the canvas shows, in model millimetres: the pattern's extent, edges
// as polylines for drawing, and the point or edge under the cursor. Objects
// that are failing are shown at their last good result; objects never
// computed are not shown. Also which labels to draw. Kept free of the LCL so
// it can be unit-tested.
unit Sloper.UI.Scene;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Bounds, Sloper.Core.Draft, Sloper.Core.Drag, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Core.Seam, Sloper.Core.Transform, Sloper.Core.Settings;

const
  MinFocusSize = 60;

type
  // A mark showing which way a piece's path runs along one of its edges
  TPieceChevron = record
    Position: TVec2;
    Angle: double;
  end;

  TPieceChevronArray = array of TPieceChevron;

  // An edge drawn in the same place as others, moved aside on screen only by
  // Slot gaps along Normal, so it shows that there is more than one
  TEdgeSlot = record
    Key: string;
    Slot: double;
    Normal: TVec2;
  end;

  TEdgeSlotArray = array of TEdgeSlot;

  // Where a notch would go: on a point, or Position mm along the edge
  TNotchTarget = record
    EdgeKey, PointKey: string;
    Position: double;
  end;

// Extent of the objects with these keys, at least MinFocusSize mm each way so
// that a single point has an area to zoom to; False when none is shown
function ObjectsBounds(Pattern: TPattern; const Keys: TStringArray; out Bounds: TRect2): boolean;
// The edge as a polyline, curves flattened to within Tolerance mm
function EdgePolyline(Edge: TEdgeObject; Tolerance: double): TVec2Array;
// What shows on the canvas, in drawing order
function ShownObjects(Pattern: TPattern): TDraftObjectArray;
function ShownPoints(Pattern: TPattern): TPointObjectArray;
// The nearest point within Radius mm of At, or nil
function PointAt(Pattern: TPattern; const At: TVec2; Radius: double): TPointObject;
// Points, edges and pieces lying wholly inside Box, in model mm, in pattern
// order; a repeat counts as its points
function ObjectsInBox(Pattern: TPattern; const Box: TRect2): TStringArray;
// The same for edges
function EdgeAt(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObject;
// The smallest piece whose cutting line contains At, or nil
function PieceAt(Pattern: TPattern; const At: TVec2): TPieceObject;
// Everything under At, in the order a click picks it: points within
// PointRadius mm, nearest first; edges within EdgeRadius mm, nearest first and
// the one drawn on top first among equals; then pieces, smallest first
function ObjectsAt(Pattern: TPattern; const At: TVec2; PointRadius, EdgeRadius: double): TStringArray;
// The edges among Keys
function EdgeKeys(Pattern: TPattern; const Keys: TStringArray): TStringArray;
// The key after Current in Keys, going round to the first; the first when
// Current is not there
function NextKey(const Keys: TStringArray; const Current: string): string;
// Two edges that run along the same path, either way round, within Tolerance mm
function EdgesCoincide(EdgeA, EdgeB: TEdgeObject; Tolerance: double): boolean;
// Every edge that lies on another, with its place in its group; groups come
// in the order of their first edge, and edges within a group in pattern order
function CoincidentEdges(Pattern: TPattern): TEdgeSlotArray;
// Where a piece's name goes: the middle of its extent
function PieceMiddle(Piece: TPieceObject): TVec2;
// One chevron at the middle of each edge of the piece, pointing along the path
function PieceChevrons(Pattern: TPattern; Piece: TPieceObject): TPieceChevronArray;
// The chevrons of one side of a seam, pointing the way it runs
function SeamChevrons(Pattern: TPattern; Seam: TSeamObject; OnSideB: boolean): TPieceChevronArray;
// The piece's edge within Radius mm of At, nearest first. An edge on two pieces
// goes with the piece At is inside.
function SeamEntryAt(Pattern: TPattern; const At: TVec2; Radius: double; out Entry: TSeamEntry): boolean;
// Adds the entry to the side, or takes it off when it is already there
procedure ToggleSeamEntry(var Side: TSeamSide; const Entry: TSeamEntry);
function SeamSideLength(Pattern: TPattern; const Side: TSeamSide): double;
// The side without entries whose piece or edge no longer exists
function ExistingSeamEntries(Pattern: TPattern; const Side: TSeamSide): TSeamSide;
// The edge and point of a selection of one edge and one point on it, not at an
// end. False with the reason otherwise.
function SplitFromSelection(Pattern: TPattern; const Selection: TStringArray; out EdgeKey, PointKey, Reason: string): boolean;
// The nearest place on a piece's seam line within Radius mm of At
function NotchTargetAt(Pattern: TPattern; const At: TVec2; Radius: double; out Target: TNotchTarget): boolean;
// The handles of the selected curves
function SelectionHandles(Pattern: TPattern; const Selection: TStringArray): TCurveHandleArray;
// The nearest handle of the selected curves within Radius mm of At
function HandleAt(Pattern: TPattern; const Selection: TStringArray; const At: TVec2; Radius: double; out Handle: TCurveHandle): boolean;
// The point halfway along a polyline of at least one point, where an edge's label goes
function PolylineMiddle(const Line: TVec2Array): TVec2;
// Keys of the objects to label, in pattern order. Contextual labels the
// hovered object, the selection with its direct inputs and dependents, and
// ToolKeys, the objects a tool is working with.
function LabelKeys(Pattern: TPattern; Mode: TLabelMode; const Selection: TStringArray; const HoverKey: string;
  const ToolKeys: TStringArray): TStringArray;

resourcestring
  rsSceneSplitSelect = 'Select an edge and a point on it to split the edge';
  rsSceneSplitOff = '%s is not on %s';
  rsSceneSplitAtEnd = '%s is at an end of %s, so there is nothing to split off';

implementation

uses
  Math, StrUtils, Generics.Collections, Sloper.Core.Bezier, Sloper.Core.Evaluator;

type
  TKeySet = specialize THashSet<string>;

function ObjectsBounds(Pattern: TPattern; const Keys: TStringArray; out Bounds: TRect2): boolean;
var
  Key: string;
  Node: TEvalNode;
  Entry: TSeamEntry;
  Empty: boolean;
  Grow: double;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TSeamObject then
      for Entry in Concat(TSeamObject(Node).SideA, TSeamObject(Node).SideB) do
        IncludeObject(Bounds, Empty, TDraftObject(Pattern.FindNode(Entry.EdgeKey)))
    else if Node is TDraftObject then
      IncludeObject(Bounds, Empty, TDraftObject(Node));
  end;
  Result := not Empty;
  if not Result then
    Exit;
  Grow := Max(0, (MinFocusSize - (Bounds.MaxX - Bounds.MinX)) / 2);
  Bounds.MinX := Bounds.MinX - Grow;
  Bounds.MaxX := Bounds.MaxX + Grow;
  Grow := Max(0, (MinFocusSize - (Bounds.MaxY - Bounds.MinY)) / 2);
  Bounds.MinY := Bounds.MinY - Grow;
  Bounds.MaxY := Bounds.MaxY + Grow;
end;

function EdgePolyline(Edge: TEdgeObject; Tolerance: double): TVec2Array;
var
  Segment: TEdgeSegment;
  Samples: TCurveSampleArray;
  Index, Count: integer;

  procedure Add(const P: TVec2);
  begin
    if Count = Length(Result) then
      SetLength(Result, Max(16, Count * 2));
    Result[Count] := P;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  for Segment in Edge.Segments do
  begin
    if Segment.Kind = skLine then
    begin
      if Count = 0 then
        Add(Segment.Line.P1);
      Add(Segment.Line.P2);
    end
    else
    begin
      Samples := Segment.Curve.Flatten(Tolerance);
      // Each segment starts where the last one ended
      for Index := 0 to High(Samples) do
        if (Index > 0) or (Count = 0) then
          Add(Samples[Index].Point);
    end;
  end;
  SetLength(Result, Count);
end;

function PointAt(Pattern: TPattern; const At: TVec2; Radius: double): TPointObject;
var
  Point: TPointObject;
  Best, Gap: double;
begin
  Result := nil;
  Best := Radius;
  for Point in Pattern.AllPoints do
  begin
    if not Point.HasResult then
      Continue;
    Gap := Distance(Point.Position, At);
    if Gap <= Best then
    begin
      Best := Gap;
      Result := Point;
    end;
  end;
end;

function EdgeAt(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObject;
  // The first edge a click there picks
var
  Keys: TStringArray;
begin
  Result := nil;
  Keys := ObjectsAt(Pattern, At, -1, Radius);
  if Length(Keys) > 0 then
    Result := TEdgeObject(Pattern.FindNode(Keys[0]));
end;

function ObjectsInBox(Pattern: TPattern; const Box: TRect2): TStringArray;

  procedure Consider(DraftObject: TDraftObject);
  var
    Bounds: TRect2;
    Empty: boolean;
  begin
    if not ((DraftObject is TPointObject) or (DraftObject is TEdgeObject) or (DraftObject is TPieceObject)) or Pattern.IsHidden(DraftObject) then
      Exit;
    Empty := True;
    IncludeObject(Bounds, Empty, DraftObject);
    if not Empty and (Bounds.MinX >= Box.MinX) and (Bounds.MaxX <= Box.MaxX) and (Bounds.MinY >= Box.MinY) and
      (Bounds.MaxY <= Box.MaxY) then
      Insert(DraftObject.Key, Result, Length(Result));
  end;

var
  Index, Number: integer;
  DraftObject: TDraftObject;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TRepeatObject) and (TRepeatObject(DraftObject).Count > 0) then
      for Number := 1 to TRepeatObject(DraftObject).Count do
        Consider(TRepeatObject(DraftObject).Item(Number))
    else
      Consider(DraftObject);
  end;
end;

function ShownObjects(Pattern: TPattern): TDraftObjectArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if not Pattern.IsHidden(Pattern.Objects[Index]) then
      Insert(Pattern.Objects[Index], Result, Length(Result));
end;

function ShownPoints(Pattern: TPattern): TPointObjectArray;
begin
  Result := Pattern.AllPoints;
end;

function PieceAt(Pattern: TPattern; const At: TVec2): TPieceObject;
var
  Index: integer;
  Piece: TPieceObject;
  Best, Size: double;
begin
  Result := nil;
  Best := Infinity;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and Pattern.Objects[Index].HasResult then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      Size := Abs(SignedArea(Piece.CutLine));
      if (Size < Best) and PointInPolygon(At, Piece.CutLine) then
      begin
        Best := Size;
        Result := Piece;
      end;
    end;
end;

function ObjectsAt(Pattern: TPattern; const At: TVec2; PointRadius, EdgeRadius: double): TStringArray;
const
  // Lines in the same place are this close in mm
  RankTolerance = 1e-6;
type
  TFound = record
    Key: string;
    Rank: double;
    // Among equal ranks, the higher comes first
    Priority: integer;
  end;
var
  Found: array of TFound;

  procedure Add(const AKey: string; ARank: double; APriority: integer = 0);
  begin
    SetLength(Found, Length(Found) + 1);
    Found[High(Found)].Key := AKey;
    Found[High(Found)].Rank := ARank;
    Found[High(Found)].Priority := APriority;
  end;

  function Before(const Item, Other: TFound): boolean;
  begin
    if Abs(Item.Rank - Other.Rank) > RankTolerance then
      Result := Item.Rank < Other.Rank
    else
      Result := Item.Priority > Other.Priority;
  end;

  // Stable, so equals keep the order they were added in
  procedure SortFrom(First: integer);
  var
    Item, Place: integer;
    Swap: TFound;
  begin
    for Item := First + 1 to High(Found) do
    begin
      Place := Item;
      while (Place > First) and Before(Found[Place], Found[Place - 1]) do
      begin
        Swap := Found[Place];
        Found[Place] := Found[Place - 1];
        Found[Place - 1] := Swap;
        Dec(Place);
      end;
    end;
  end;

var
  Index, First: integer;
  DraftObject: TDraftObject;
  Point: TPointObject;
  Position, Offset: double;
begin
  Found := nil;
  for Point in Pattern.AllPoints do
    if Point.HasResult and (Distance(Point.Position, At) <= PointRadius) then
      Add(Point.Key, Distance(Point.Position, At));
  SortFrom(0);
  First := Length(Found);
  // Later objects are drawn on top, so they come first among equals
  for Index := Pattern.ObjectCount - 1 downto 0 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TEdgeObject) or not DraftObject.HasResult or (Length(TEdgeObject(DraftObject).Segments) = 0) or
      Pattern.IsHidden(DraftObject) then
      Continue;
    TEdgeObject(DraftObject).Locate(At, Position, Offset);
    if Offset <= EdgeRadius then
      Add(DraftObject.Key, Offset, RolePriorities[TEdgeObject(DraftObject).Role]);
  end;
  SortFrom(First);
  First := Length(Found);
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPieceObject) and DraftObject.HasResult and PointInPolygon(At, TPieceObject(DraftObject).CutLine) then
      Add(DraftObject.Key, Abs(SignedArea(TPieceObject(DraftObject).CutLine)));
  end;
  SortFrom(First);
  Result := nil;
  SetLength(Result, Length(Found));
  for Index := 0 to High(Found) do
    Result[Index] := Found[Index].Key;
end;

function EdgeKeys(Pattern: TPattern; const Keys: TStringArray): TStringArray;
var
  Key: string;
begin
  Result := nil;
  for Key in Keys do
    if Pattern.FindNode(Key) is TEdgeObject then
      Insert(Key, Result, Length(Result));
end;

function NextKey(const Keys: TStringArray; const Current: string): string;
var
  Index: integer;
begin
  Result := '';
  if Length(Keys) = 0 then
    Exit;
  Result := Keys[0];
  for Index := 0 to High(Keys) do
    if Keys[Index] = Current then
      Exit(Keys[(Index + 1) mod Length(Keys)]);
end;

function EdgesCoincide(EdgeA, EdgeB: TEdgeObject; Tolerance: double): boolean;
const
  Samples = 8;

// Every sample along From lies on Onto
  function LiesOn(From, Onto: TEdgeObject): boolean;
  var
    Index: integer;
    Position, Offset: double;
  begin
    for Index := 0 to Samples do
    begin
      Onto.Locate(From.PointAtLength(From.Length * Index / Samples), Position, Offset);
      if Offset > Tolerance then
        Exit(False);
    end;
    Result := True;
  end;

var
  StartA, EndA, StartB, EndB: TVec2;
begin
  if not EdgeA.HasResult or not EdgeB.HasResult or (Length(EdgeA.Segments) = 0) or (Length(EdgeB.Segments) = 0) then
    Exit(False);
  if Abs(EdgeA.Length - EdgeB.Length) > Tolerance then
    Exit(False);
  StartA := EdgeA.PointAtLength(0);
  EndA := EdgeA.PointAtLength(EdgeA.Length);
  StartB := EdgeB.PointAtLength(0);
  EndB := EdgeB.PointAtLength(EdgeB.Length);
  if not ((PointsNear(StartA, StartB, Tolerance) and PointsNear(EndA, EndB, Tolerance)) or
    (PointsNear(StartA, EndB, Tolerance) and PointsNear(EndA, StartB, Tolerance))) then
    Exit(False);
  Result := LiesOn(EdgeA, EdgeB) and LiesOn(EdgeB, EdgeA);
end;

function CoincidentEdges(Pattern: TPattern): TEdgeSlotArray;
const
  Tolerance = 0.01;
var
  Edges: array of TEdgeObject;
  Group: array of TEdgeObject;
  Taken: array of boolean;
  Index, Other, Member: integer;
  Chord, Normal: TVec2;
  Slot: TEdgeSlot;
begin
  Result := nil;
  Edges := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TEdgeObject) and Pattern.Objects[Index].HasResult and not Pattern.IsHidden(Pattern.Objects[Index]) and
      (Length(TEdgeObject(Pattern.Objects[Index]).Segments) > 0) then
      Insert(TEdgeObject(Pattern.Objects[Index]), Edges, Length(Edges));
  Taken := nil;
  SetLength(Taken, Length(Edges));
  for Index := 0 to High(Edges) do
  begin
    if Taken[Index] then
      Continue;
    Group := [Edges[Index]];
    for Other := Index + 1 to High(Edges) do
      if not Taken[Other] and EdgesCoincide(Edges[Index], Edges[Other], Tolerance) then
      begin
        Taken[Other] := True;
        Insert(Edges[Other], Group, Length(Group));
      end;
    if Length(Group) < 2 then
      Continue;
    // One side of the first edge's chord; a closed edge has none, so it goes
    // down and to the right
    Chord := Group[0].PointAtLength(Group[0].Length) - Group[0].PointAtLength(0);
    if Chord.Length < Tolerance then
      Normal := Vec2(Sqrt(0.5), Sqrt(0.5))
    else
      Normal := Vec2(-Chord.Y / Chord.Length, Chord.X / Chord.Length);
    for Member := 0 to High(Group) do
    begin
      Slot.Key := Group[Member].Key;
      Slot.Slot := Member - (Length(Group) - 1) / 2;
      Slot.Normal := Normal;
      Insert(Slot, Result, Length(Result));
    end;
  end;
end;

function PieceMiddle(Piece: TPieceObject): TVec2;
begin
  Result := Piece.Middle;
end;

function PieceChevrons(Pattern: TPattern; Piece: TPieceObject): TPieceChevronArray;
var
  Index: integer;
  Edge: TEdgeObject;
begin
  Result := nil;
  SetLength(Result, Length(Piece.Path));
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(Pattern.FindNode(Piece.Path[Index].EdgeKey));
    Result[Index].Position := Edge.PointAtLength(Edge.Length / 2);
    Result[Index].Angle := Edge.DirectionAt(Edge.Length / 2);
    if Piece.Path[Index].Reversed then
      Result[Index].Angle := NormalizeAngle(Result[Index].Angle + 180);
  end;
end;

function SeamChevrons(Pattern: TPattern; Seam: TSeamObject; OnSideB: boolean): TPieceChevronArray;
var
  Side: TSeamSide;
  Entry: TSeamEntry;
  Piece: TPieceObject;
  Edge: TEdgeObject;
  Item: TPieceChevron;
begin
  Result := nil;
  if OnSideB then
    Side := Seam.SideB
  else
    Side := Seam.SideA;
  for Entry in Side do
  begin
    Piece := TPieceObject(Pattern.FindNode(Entry.PieceKey));
    if (Piece.PathIndexOf(Entry.EdgeKey) < 0) then
      Continue;
    Edge := TEdgeObject(Pattern.FindNode(Entry.EdgeKey));
    Item.Position := Edge.PointAtLength(Edge.Length / 2);
    Item.Angle := Edge.DirectionAt(Edge.Length / 2);
    if not Seam.RunsForward(Piece, Entry, OnSideB) then
      Item.Angle := NormalizeAngle(Item.Angle + 180);
    Insert(Item, Result, Length(Result));
  end;
end;

function SeamEntryAt(Pattern: TPattern; const At: TVec2; Radius: double; out Entry: TSeamEntry): boolean;
var
  Index: integer;
  Piece: TPieceObject;
  PathEntry: TPieceEdge;
  Position, Gap, Best: double;
  Inside: boolean;
begin
  Entry := Default(TSeamEntry);
  Result := False;
  Best := Radius;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TPieceObject) or not Pattern.Objects[Index].HasResult then
      Continue;
    Piece := TPieceObject(Pattern.Objects[Index]);
    for PathEntry in Piece.Path do
    begin
      TEdgeObject(Pattern.FindNode(PathEntry.EdgeKey)).Locate(At, Position, Gap);
      if (Gap < Best) or (not Result and (Gap <= Best)) then
      begin
        Best := Gap;
        Entry.EdgeKey := PathEntry.EdgeKey;
        Entry.PieceKey := Piece.Key;
        Result := True;
      end;
    end;
  end;
  if not Result then
    Exit;
  Inside := PointInPolygon(At, TPieceObject(Pattern.FindNode(Entry.PieceKey)).Outline);
  for Index := 0 to Pattern.ObjectCount - 1 do
    if not Inside and (Pattern.Objects[Index] is TPieceObject) and Pattern.Objects[Index].HasResult then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      if (Piece.PathIndexOf(Entry.EdgeKey) >= 0) and PointInPolygon(At, Piece.Outline) then
      begin
        Entry.PieceKey := Piece.Key;
        Inside := True;
      end;
    end;
end;

procedure ToggleSeamEntry(var Side: TSeamSide; const Entry: TSeamEntry);
var
  Index: integer;
begin
  for Index := 0 to High(Side) do
    if (Side[Index].PieceKey = Entry.PieceKey) and (Side[Index].EdgeKey = Entry.EdgeKey) then
    begin
      Delete(Side, Index, 1);
      Exit;
    end;
  Insert(Entry, Side, Length(Side));
end;

function SeamSideLength(Pattern: TPattern; const Side: TSeamSide): double;
var
  Entry: TSeamEntry;
begin
  Result := 0;
  for Entry in Side do
    Result := Result + TEdgeObject(Pattern.FindNode(Entry.EdgeKey)).Length;
end;

function ExistingSeamEntries(Pattern: TPattern; const Side: TSeamSide): TSeamSide;
var
  Entry: TSeamEntry;
begin
  Result := nil;
  for Entry in Side do
    if (Pattern.FindNode(Entry.PieceKey) is TPieceObject) and (Pattern.FindNode(Entry.EdgeKey) is TEdgeObject) then
      Insert(Entry, Result, Length(Result));
end;

function SplitFromSelection(Pattern: TPattern; const Selection: TStringArray; out EdgeKey, PointKey, Reason: string): boolean;
var
  Key: string;
  Node: TEvalNode;
  Edge: TEdgeObject;
  Point: TPointObject;
  Position, Gap: double;
begin
  Result := False;
  EdgeKey := '';
  PointKey := '';
  Reason := rsSceneSplitSelect;
  Edge := nil;
  Point := nil;
  if Length(Selection) <> 2 then
    Exit;
  for Key in Selection do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TEdgeObject then
      Edge := TEdgeObject(Node)
    else if Node is TPointObject then
      Point := TPointObject(Node);
  end;
  if not Assigned(Edge) or not Assigned(Point) or not Edge.HasResult or not Point.HasResult then
    Exit;
  Edge.Locate(Point.Position, Position, Gap);
  if Gap > NotchPointTolerance then
  begin
    Reason := Format(rsSceneSplitOff, [Point.DisplayName, Edge.DisplayName]);
    Exit;
  end;
  if (Position <= NotchPointTolerance) or (Position >= Edge.Length - NotchPointTolerance) then
  begin
    Reason := Format(rsSceneSplitAtEnd, [Point.DisplayName, Edge.DisplayName]);
    Exit;
  end;
  EdgeKey := Edge.Key;
  PointKey := Point.Key;
  Reason := '';
  Result := True;
end;

function NotchTargetAt(Pattern: TPattern; const At: TVec2; Radius: double; out Target: TNotchTarget): boolean;
var
  Index, Entry: integer;
  Piece: TPieceObject;
  Edge: TEdgeObject;
  Point: TPointObject;
  Position, Gap, Best: double;
begin
  Target := Default(TNotchTarget);
  Result := False;
  Best := Radius;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      for Entry := 0 to High(Piece.Path) do
      begin
        Edge := TEdgeObject(Pattern.FindNode(Piece.Path[Entry].EdgeKey));
        Edge.Locate(At, Position, Gap);
        if Gap <= Best then
        begin
          Best := Gap;
          Target.EdgeKey := Edge.Key;
          Target.Position := Position;
          Result := True;
        end;
      end;
    end;
  if not Result then
    Exit;
  // A point on the edge keeps the notch with it as the edge changes
  Point := PointAt(Pattern, At, Radius);
  if Assigned(Point) then
  begin
    TEdgeObject(Pattern.FindNode(Target.EdgeKey)).Locate(Point.Position, Position, Gap);
    if Gap <= NotchPointTolerance then
      Target.PointKey := Point.Key;
  end;
end;

function SelectionHandles(Pattern: TPattern; const Selection: TStringArray): TCurveHandleArray;
var
  Key: string;
  Node: TEvalNode;
begin
  Result := nil;
  for Key in Selection do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TEdgeObject then
      Result := Concat(Result, CurveHandles(TEdgeObject(Node)));
  end;
end;

function HandleAt(Pattern: TPattern; const Selection: TStringArray; const At: TVec2; Radius: double; out Handle: TCurveHandle): boolean;
var
  Candidate: TCurveHandle;
  Best, Gap: double;
begin
  Result := False;
  Handle := Default(TCurveHandle);
  Best := Radius;
  for Candidate in SelectionHandles(Pattern, Selection) do
  begin
    Gap := Distance(Candidate.Position, At);
    if Gap <= Best then
    begin
      Best := Gap;
      Handle := Candidate;
      Result := True;
    end;
  end;
end;

function PolylineMiddle(const Line: TVec2Array): TVec2;
var
  Index: integer;
  Total, Remaining, Step: double;
begin
  Total := 0;
  for Index := 1 to High(Line) do
    Total := Total + Distance(Line[Index - 1], Line[Index]);
  Remaining := Total / 2;
  for Index := 1 to High(Line) do
  begin
    Step := Distance(Line[Index - 1], Line[Index]);
    if (Step > 0) and (Remaining <= Step) then
      Exit(Lerp(Line[Index - 1], Line[Index], Remaining / Step));
    Remaining := Remaining - Step;
  end;
  Result := Line[0];
end;

function LabelKeys(Pattern: TPattern; Mode: TLabelMode; const Selection: TStringArray; const HoverKey: string;
  const ToolKeys: TStringArray): TStringArray;
var
  Point: TPointObject;
  Wanted: TKeySet;
  Key: string;
  Node, Neighbour: TEvalNode;
  Index, Count: integer;
  DraftObject: TDraftObject;
begin
  Result := nil;
  if Mode = lmNone then
    Exit;
  Wanted := TKeySet.Create;
  try
    Wanted.Add(HoverKey);
    for Key in ToolKeys do
      Wanted.Add(Key);
    for Key in Selection do
    begin
      Wanted.Add(Key);
      Node := Pattern.FindNode(Key);
      if not Assigned(Node) then
        Continue;
      for Neighbour in Node.Deps do
        Wanted.Add(Neighbour.Key);
      for Neighbour in Node.Dependents do
        Wanted.Add(Neighbour.Key);
    end;
    SetLength(Result, Pattern.ObjectCount);
    Count := 0;
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      DraftObject := Pattern.Objects[Index];
      // A seam has no place of its own to put a label, and a hidden line
      // shows only while it is selected
      if DraftObject.HasResult and not (DraftObject is TSeamObject) and not (DraftObject is TTransformObject) and
        ((Mode = lmAll) or Wanted.Contains(DraftObject.Key)) and
        (not Pattern.IsHidden(DraftObject) or (IndexStr(DraftObject.Key, Selection) >= 0)) then
      begin
        Result[Count] := DraftObject.Key;
        Inc(Count);
      end;
    end;
    SetLength(Result, Count);
    for Point in Pattern.AllPoints do
      if (Point is TRepeatPoint) and Point.HasResult and ((Mode = lmAll) or Wanted.Contains(Point.Key)) then
        Insert(Point.Key, Result, Length(Result));
  finally
    FreeAndNil(Wanted);
  end;
end;

end.
