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
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Drag, Sloper.Core.Pattern, Sloper.Core.Settings;

const
  MinFocusSize = 60;

// Extent of everything shown; False when nothing is
function PatternBounds(Pattern: TPattern; out Bounds: TRect2): boolean;
// Extent of the objects with these keys, at least MinFocusSize mm each way so
// that a single point has an area to zoom to; False when none is shown
function ObjectsBounds(Pattern: TPattern; const Keys: TStringArray; out Bounds: TRect2): boolean;
// The edge as a polyline, curves flattened to within Tolerance mm
function EdgePolyline(Edge: TEdgeObject; Tolerance: double): TVec2Array;
// The nearest point within Radius mm of At, or nil
function PointAt(Pattern: TPattern; const At: TVec2; Radius: double): TPointObject;
// The nearest edge within Radius mm of At, or nil
function EdgeAt(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObject;
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

implementation

uses
  Math, Generics.Collections, Sloper.Core.Bezier, Sloper.Core.Evaluator;

type
  TKeySet = specialize THashSet<string>;

procedure Include(var Bounds: TRect2; var Empty: boolean; const P: TVec2);
begin
  if Empty then
  begin
    Bounds.MinX := P.X;
    Bounds.MaxX := P.X;
    Bounds.MinY := P.Y;
    Bounds.MaxY := P.Y;
    Empty := False;
    Exit;
  end;
  Bounds.MinX := Min(Bounds.MinX, P.X);
  Bounds.MaxX := Max(Bounds.MaxX, P.X);
  Bounds.MinY := Min(Bounds.MinY, P.Y);
  Bounds.MaxY := Max(Bounds.MaxY, P.Y);
end;

procedure IncludeObject(var Bounds: TRect2; var Empty: boolean; DraftObject: TDraftObject);
var
  Segment: TEdgeSegment;
  CurveBounds: TRect2;
begin
  if not DraftObject.HasResult then
    Exit;
  if DraftObject is TPointObject then
    Include(Bounds, Empty, TPointObject(DraftObject).Position)
  else if DraftObject is TEdgeObject then
    for Segment in TEdgeObject(DraftObject).Segments do
      if Segment.Kind = skLine then
      begin
        Include(Bounds, Empty, Segment.Line.P1);
        Include(Bounds, Empty, Segment.Line.P2);
      end
      else
      begin
        CurveBounds := Segment.Curve.Bounds;
        Include(Bounds, Empty, Vec2(CurveBounds.MinX, CurveBounds.MinY));
        Include(Bounds, Empty, Vec2(CurveBounds.MaxX, CurveBounds.MaxY));
      end;
end;

function PatternBounds(Pattern: TPattern; out Bounds: TRect2): boolean;
var
  Index: integer;
  Empty: boolean;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Index := 0 to Pattern.ObjectCount - 1 do
    IncludeObject(Bounds, Empty, Pattern.Objects[Index]);
  Result := not Empty;
end;

function ObjectsBounds(Pattern: TPattern; const Keys: TStringArray; out Bounds: TRect2): boolean;
var
  Key: string;
  Node: TEvalNode;
  Empty: boolean;
  Grow: double;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TDraftObject then
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
  Index: integer;
  DraftObject: TDraftObject;
  Best, Gap: double;
begin
  Result := nil;
  Best := Radius;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TPointObject) or not DraftObject.HasResult then
      Continue;
    Gap := Distance(TPointObject(DraftObject).Position, At);
    if Gap <= Best then
    begin
      Best := Gap;
      Result := TPointObject(DraftObject);
    end;
  end;
end;

function EdgeAt(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObject;
var
  Index: integer;
  DraftObject: TDraftObject;
  Best, Position, Offset: double;
begin
  Result := nil;
  Best := Radius;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TEdgeObject) or not DraftObject.HasResult or (TEdgeObject(DraftObject).Segments = nil) then
      Continue;
    TEdgeObject(DraftObject).Locate(At, Position, Offset);
    if Offset <= Best then
    begin
      Best := Offset;
      Result := TEdgeObject(DraftObject);
    end;
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
      if Node = nil then
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
      if DraftObject.HasResult and ((Mode = lmAll) or Wanted.Contains(DraftObject.Key)) then
      begin
        Result[Count] := DraftObject.Key;
        Inc(Count);
      end;
    end;
    SetLength(Result, Count);
  finally
    FreeAndNil(Wanted);
  end;
end;

end.
