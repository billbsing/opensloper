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
  Sloper.Core.Settings;

const
  MinFocusSize = 60;

type
  // A mark showing which way a piece's path runs along one of its edges
  TPieceChevron = record
    Position: TVec2;
    Angle: double;
  end;

  TPieceChevronArray = array of TPieceChevron;

// Extent of the objects with these keys, at least MinFocusSize mm each way so
// that a single point has an area to zoom to; False when none is shown
function ObjectsBounds(Pattern: TPattern; const Keys: TStringArray; out Bounds: TRect2): boolean;
// The edge as a polyline, curves flattened to within Tolerance mm
function EdgePolyline(Edge: TEdgeObject; Tolerance: double): TVec2Array;
// The nearest point within Radius mm of At, or nil
function PointAt(Pattern: TPattern; const At: TVec2; Radius: double): TPointObject;
// The nearest edge within Radius mm of At, or nil
function EdgeAt(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObject;
// The smallest piece whose cutting line contains At, or nil
function PieceAt(Pattern: TPattern; const At: TVec2): TPieceObject;
// Where a piece's name goes: the middle of its extent
function PieceMiddle(Piece: TPieceObject): TVec2;
// One chevron at the middle of each edge of the piece, pointing along the path
function PieceChevrons(Pattern: TPattern; Piece: TPieceObject): TPieceChevronArray;
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

function PieceMiddle(Piece: TPieceObject): TVec2;
var
  P: TVec2;
  MinX, MinY, MaxX, MaxY: double;
begin
  MinX := Infinity;
  MinY := Infinity;
  MaxX := -Infinity;
  MaxY := -Infinity;
  for P in Piece.Outline do
  begin
    MinX := Min(MinX, P.X);
    MinY := Min(MinY, P.Y);
    MaxX := Max(MaxX, P.X);
    MaxY := Max(MaxY, P.Y);
  end;
  Result := Vec2((MinX + MaxX) / 2, (MinY + MaxY) / 2);
end;

function PieceChevrons(Pattern: TPattern; Piece: TPieceObject): TPieceChevronArray;
const
  // Measured across the middle, so a curve's direction is its tangent there
  DirectionSpan = 0.5;
var
  Index: integer;
  Edge: TEdgeObject;
  Middle, Span: double;
begin
  Result := nil;
  SetLength(Result, Length(Piece.Path));
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(Pattern.FindNode(Piece.Path[Index].EdgeKey));
    Middle := Edge.Length / 2;
    Span := Min(DirectionSpan, Middle);
    Result[Index].Position := Edge.PointAtLength(Middle);
    if Piece.Path[Index].Reversed then
      Result[Index].Angle := AngleBetween(Edge.PointAtLength(Middle + Span), Edge.PointAtLength(Middle - Span))
    else
      Result[Index].Angle := AngleBetween(Edge.PointAtLength(Middle - Span), Edge.PointAtLength(Middle + Span));
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
