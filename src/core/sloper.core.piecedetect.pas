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

// Automatic piece detection: the outline edges are treated as a planar graph,
// and the faces of the graph are walked to find the closed path around a
// place the user clicked. The steps are in the design document under
// "Automatic piece detection". No LCL dependency.
unit Sloper.Core.PieceDetect;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Piece, Sloper.Core.Pattern;

// The clockwise path around At, from the outline edges. False with the reason
// in ErrorMessage when At is in no closed region, or the region's edges would
// have to be split first.
function DetectPiecePath(Pattern: TPattern; const At: TVec2; out Path: TPiecePath; out ErrorMessage: string): boolean;

resourcestring
  rsDetectNoRegion = 'There is no closed outline around this place';
  rsDetectNeedsSplit = '%s crosses another edge here; split it at the crossing first';
  rsDetectBridge = '%s runs through this region without dividing it';

implementation

uses
  SysUtils, Math, Generics.Collections, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.SeamAllowance;

const
  // How far along an edge (in mm) its direction leaving a node is measured,
  // so curves that leave tangent to each other still sort the right way round
  DirectionReach = 0.5;
  // Sampling of a curve for the region's polygon
  CurveStep = 5;
  MinCurveSteps = 16;
  // Limit on the search for closed paths, far above what a draft needs
  MaxCycleSteps = 200000;

type
  TEdgeList = specialize TList<TEdgeObject>;
  TIntegerArray = array of integer;

  // One way along a stretch of an edge. Arcs come in pairs: the arc with an
  // even index runs with the edge, and Index xor 1 is the same stretch back.
  TArc = record
    Edge: TEdgeObject;
    FromPos, ToPos: double;
    FromNode, ToNode: integer;
    Angle: double;
    Removed, Walked: boolean;
  end;

  TArcArray = array of TArc;

  TFaceFinder = class
  private
    FArcs: TArcArray;
    FNodes: TVec2Array;
    FOutgoing: array of TIntegerArray;
    function NodeAt(const P: TVec2): integer;
    procedure AddStretch(Edge: TEdgeObject; FromPos, ToPos: double);
    procedure RemoveDangling;
    procedure SortOutgoing;
    function NextArc(Arc: integer): integer;
    function FacePolygon(const Face: TIntegerArray): TVec2Array;
    function WalkFace(Start: integer): TIntegerArray;
    function TouchesItself(const Cycle: TIntegerArray): boolean;
  public
    // With CutAtCrossings False edges run whole, end to end, so a panel that
    // overlaps its neighbour keeps its own outline
    procedure Build(Edges: TEdgeList; CutAtCrossings: boolean);
    // The arcs around the smallest region containing At; nil when there is none
    function FaceAt(const At: TVec2): TIntegerArray;
    // The arcs, anticlockwise, of the smallest simple closed path around At.
    // For a graph of whole edges, where walking faces would turn the wrong
    // way at a node two crossing panels share. nil when there is none.
    function CycleAt(const At: TVec2): TIntegerArray;
    function ArcIsWholeEdge(Arc: integer): boolean;
    property Arcs: TArcArray read FArcs;
  end;

// Outline edges with results. An edge that has been split stays in the
// pattern; its outline parts stand in for it, or it would overlap them.
function OutlineEdges(Pattern: TPattern): TEdgeList;
var
  Index: integer;
  Replaced: specialize THashSet<string>;
  Edge: TEdgeObject;
begin
  Result := TEdgeList.Create;
  Replaced := specialize THashSet<string>.Create;
  try
    for Index := 0 to Pattern.ObjectCount - 1 do
      if (Pattern.Objects[Index] is TSplitPart) and (TSplitPart(Pattern.Objects[Index]).Role = erOutline) then
        Replaced.Add(TSplitPart(Pattern.Objects[Index]).Source);
    for Index := 0 to Pattern.ObjectCount - 1 do
      if Pattern.Objects[Index] is TEdgeObject then
      begin
        Edge := TEdgeObject(Pattern.Objects[Index]);
        if (Edge.Role = erOutline) and (Edge.State = esValid) and not Replaced.Contains(Edge.Key) then
          Result.Add(Edge);
      end;
  except
    FreeAndNil(Replaced);
    FreeAndNil(Result);
    raise;
  end;
  FreeAndNil(Replaced);
end;

// Where Edge has to be cut: its ends, and every crossing with another edge
function CutPositions(Edge: TEdgeObject; Edges: TEdgeList): TDoubleArray;
var
  Other: TEdgeObject;
  Crossing: TEdgeCrossing;
  Count, Slot: integer;
  Position: double;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := 0;
  Result[1] := Edge.Length;
  Count := 2;
  for Other in Edges do
    if Other <> Edge then
      for Crossing in CrossEdges(Edge, False, Other, False) do
      begin
        Position := Crossing.Position;
        // Keep the list sorted; a repeat or a crossing at an end is no new cut
        Slot := 1;
        while (Slot < Count - 1) and (Result[Slot] < Position) do
          Inc(Slot);
        if (Position - Result[Slot - 1] <= PieceJoinTolerance) or (Result[Slot] - Position <= PieceJoinTolerance) then
          Continue;
        System.Insert(Position, Result, Slot);
        Inc(Count);
      end;
end;

function TFaceFinder.NodeAt(const P: TVec2): integer;
begin
  for Result := 0 to High(FNodes) do
    if PointsNear(FNodes[Result], P, PieceJoinTolerance) then
      Exit;
  SetLength(FNodes, Length(FNodes) + 1);
  Result := High(FNodes);
  FNodes[Result] := P;
end;

procedure TFaceFinder.AddStretch(Edge: TEdgeObject; FromPos, ToPos: double);
var
  Reach: double;
  StartNode, EndNode, Count: integer;
  StartPos, EndPos: TVec2;

  procedure SetArc(Index: integer; AFromPos, AToPos: double; AFromNode, AToNode: integer; const Origin, Target: TVec2);
  begin
    FArcs[Index] := Default(TArc);
    FArcs[Index].Edge := Edge;
    FArcs[Index].FromPos := AFromPos;
    FArcs[Index].ToPos := AToPos;
    FArcs[Index].FromNode := AFromNode;
    FArcs[Index].ToNode := AToNode;
    FArcs[Index].Angle := AngleBetween(Origin, Target);
  end;

begin
  StartPos := Edge.PointAtLength(FromPos);
  EndPos := Edge.PointAtLength(ToPos);
  StartNode := NodeAt(StartPos);
  EndNode := NodeAt(EndPos);
  if StartNode = EndNode then
    Exit;
  Reach := Min(DirectionReach, (ToPos - FromPos) / 4);
  Count := Length(FArcs);
  SetLength(FArcs, Count + 2);
  SetArc(Count, FromPos, ToPos, StartNode, EndNode, StartPos, Edge.PointAtLength(FromPos + Reach));
  SetArc(Count + 1, ToPos, FromPos, EndNode, StartNode, EndPos, Edge.PointAtLength(ToPos - Reach));
end;

// Dangling stretches cannot be part of a closed path
procedure TFaceFinder.RemoveDangling;
var
  Degree: TIntegerArray;
  Index: integer;
  Changed: boolean;
begin
  Degree := nil;
  repeat
    Changed := False;
    Degree := nil;
    SetLength(Degree, Length(FNodes));
    for Index := 0 to High(FArcs) do
      if not FArcs[Index].Removed then
        Inc(Degree[FArcs[Index].FromNode]);
    for Index := 0 to High(FArcs) do
      if not FArcs[Index].Removed and ((Degree[FArcs[Index].FromNode] = 1) or (Degree[FArcs[Index].ToNode] = 1)) then
      begin
        FArcs[Index].Removed := True;
        FArcs[Index xor 1].Removed := True;
        Changed := True;
      end;
  until not Changed;
end;

// Each node's arcs in order of angle, anticlockwise
procedure TFaceFinder.SortOutgoing;
var
  Index, Slot, Node: integer;
  List: TIntegerArray;
begin
  FOutgoing := nil;
  SetLength(FOutgoing, Length(FNodes));
  for Index := 0 to High(FArcs) do
    if not FArcs[Index].Removed then
    begin
      Node := FArcs[Index].FromNode;
      List := FOutgoing[Node];
      Slot := Length(List);
      while (Slot > 0) and (FArcs[List[Slot - 1]].Angle > FArcs[Index].Angle) do
        Dec(Slot);
      System.Insert(Index, FOutgoing[Node], Slot);
    end;
end;

procedure TFaceFinder.Build(Edges: TEdgeList; CutAtCrossings: boolean);
var
  Edge: TEdgeObject;
  Cuts: TDoubleArray;
  Index: integer;
begin
  for Edge in Edges do
    if CutAtCrossings then
    begin
      Cuts := CutPositions(Edge, Edges);
      for Index := 0 to High(Cuts) - 1 do
        AddStretch(Edge, Cuts[Index], Cuts[Index + 1]);
    end
    else
      AddStretch(Edge, 0, Edge.Length);
  RemoveDangling;
  SortOutgoing;
end;

// The first arc clockwise from the way back keeps the region on the left, so
// inner regions are walked anticlockwise and the outer one clockwise
function TFaceFinder.NextArc(Arc: integer): integer;
var
  List: TIntegerArray;
  Slot, Back: integer;
begin
  List := FOutgoing[FArcs[Arc].ToNode];
  Back := Arc xor 1;
  for Slot := 0 to High(List) do
    if List[Slot] = Back then
      Exit(List[(Slot + High(List)) mod Length(List)]);
  Result := Back;
end;

function TFaceFinder.WalkFace(Start: integer): TIntegerArray;
var
  Current: integer;
begin
  Result := nil;
  Current := Start;
  repeat
    FArcs[Current].Walked := True;
    System.Insert(Current, Result, Length(Result));
    Current := NextArc(Current);
  until Current = Start;
end;

function TFaceFinder.FacePolygon(const Face: TIntegerArray): TVec2Array;
var
  ArcIndex, Steps, Step, Count: integer;
  Arc: TArc;
begin
  Result := nil;
  Count := 0;
  for ArcIndex in Face do
  begin
    Arc := FArcs[ArcIndex];
    Steps := 1;
    if not IsStraightEdge(Arc.Edge) then
      Steps := Max(MinCurveSteps, Ceil(Abs(Arc.ToPos - Arc.FromPos) / CurveStep));
    SetLength(Result, Count + Steps);
    for Step := 0 to Steps - 1 do
      Result[Count + Step] := Arc.Edge.PointAtLength(Arc.FromPos + (Arc.ToPos - Arc.FromPos) * Step / Steps);
    Inc(Count, Steps);
  end;
end;

function TFaceFinder.FaceAt(const At: TVec2): TIntegerArray;
var
  Index: integer;
  Face: TIntegerArray;
  Polygon: TVec2Array;
  Size, Best: double;
begin
  Result := nil;
  Best := Infinity;
  for Index := 0 to High(FArcs) do
  begin
    if FArcs[Index].Removed or FArcs[Index].Walked then
      Continue;
    Face := WalkFace(Index);
    Polygon := FacePolygon(Face);
    Size := SignedArea(Polygon);
    if (Size > 0) and (Size < Best) and PointInPolygon(At, Polygon) then
    begin
      Best := Size;
      Result := Face;
    end;
  end;
end;

// True when an end of one edge lies part way along another: the path is then
// really two regions joined at a point, and that edge has to be split
function TFaceFinder.TouchesItself(const Cycle: TIntegerArray): boolean;
var
  ArcIndex, Other: integer;
  Position, Gap: double;
begin
  Result := False;
  for ArcIndex in Cycle do
    for Other in Cycle do
      if (FArcs[Other].FromNode <> FArcs[ArcIndex].ToNode) and (FArcs[Other].ToNode <> FArcs[ArcIndex].ToNode) then
      begin
        FArcs[Other].Edge.Locate(FNodes[FArcs[ArcIndex].ToNode], Position, Gap);
        if Gap <= PieceJoinTolerance then
          Exit(True);
      end;
end;

function TFaceFinder.CycleAt(const At: TVec2): TIntegerArray;
var
  Visited: array of boolean;
  Trail: TIntegerArray;
  Best: double;
  Steps, StartNode: integer;

  procedure Consider;
  var
    Polygon: TVec2Array;
    Size: double;
    Index: integer;
  begin
    Polygon := FacePolygon(Trail);
    Size := Abs(SignedArea(Polygon));
    if (Size <= 0) or (Size >= Best) or not PointInPolygon(At, Polygon) or TouchesItself(Trail) then
      Exit;
    Best := Size;
    Result := Copy(Trail);
    if SignedArea(Polygon) < 0 then
      for Index := 0 to High(Trail) do
        Result[Index] := Trail[High(Trail) - Index] xor 1;
  end;

  procedure Extend(Arc: integer);
  var
    Next, Target: integer;
  begin
    Inc(Steps);
    if Steps > MaxCycleSteps then
      Exit;
    Target := FArcs[Arc].ToNode;
    System.Insert(Arc, Trail, Length(Trail));
    if Target = StartNode then
      Consider
    else if (Target > StartNode) and not Visited[Target] then
    begin
      Visited[Target] := True;
      for Next in FOutgoing[Target] do
        if Next <> Arc xor 1 then
          Extend(Next);
      Visited[Target] := False;
    end;
    SetLength(Trail, Length(Trail) - 1);
  end;

var
  First: integer;
begin
  Result := nil;
  Best := Infinity;
  Steps := 0;
  Trail := nil;
  Visited := nil;
  SetLength(Visited, Length(FNodes));
  // Each path is found from its lowest node, so once each way round
  for StartNode := 0 to High(FNodes) do
    for First in FOutgoing[StartNode] do
      Extend(First);
end;

function TFaceFinder.ArcIsWholeEdge(Arc: integer): boolean;
begin
  Result := (Min(FArcs[Arc].FromPos, FArcs[Arc].ToPos) <= PieceJoinTolerance) and
    (Max(FArcs[Arc].FromPos, FArcs[Arc].ToPos) >= FArcs[Arc].Edge.Length - PieceJoinTolerance);
end;

// The path around Face, clockwise; False with the reason in ErrorMessage
function FacePath(Finder: TFaceFinder; const Face: TIntegerArray; out Path: TPiecePath; out ErrorMessage: string): boolean;
var
  Index, Other: integer;
  Arc: TArc;
begin
  Path := nil;
  SetLength(Path, Length(Face));
  // The walk is anticlockwise; pieces are stored clockwise
  for Index := 0 to High(Face) do
  begin
    Arc := Finder.Arcs[Face[Index]];
    if not Finder.ArcIsWholeEdge(Face[Index]) then
    begin
      ErrorMessage := Format(rsDetectNeedsSplit, [Arc.Edge.DisplayName]);
      Exit(False);
    end;
    for Other := 0 to Index - 1 do
      if Finder.Arcs[Face[Other]].Edge = Arc.Edge then
      begin
        ErrorMessage := Format(rsDetectBridge, [Arc.Edge.DisplayName]);
        Exit(False);
      end;
    Path[High(Face) - Index].EdgeKey := Arc.Edge.Key;
    Path[High(Face) - Index].Reversed := Arc.FromPos < Arc.ToPos;
  end;
  Result := True;
end;

function DetectPiecePath(Pattern: TPattern; const At: TVec2; out Path: TPiecePath; out ErrorMessage: string): boolean;
var
  Edges: TEdgeList;
  Finder: TFaceFinder;
  Face: TIntegerArray;
  WholeEdgeError: string;
begin
  Path := nil;
  ErrorMessage := rsDetectNoRegion;
  Result := False;
  Finder := nil;
  Edges := OutlineEdges(Pattern);
  try
    Finder := TFaceFinder.Create;
    Finder.Build(Edges, True);
    Face := Finder.FaceAt(At);
    if Face = nil then
      Exit;
    Result := FacePath(Finder, Face, Path, ErrorMessage);
    if Result then
      Exit;
    // Overlapping panels cross each other, but each still closes on its own
    FreeAndNil(Finder);
    Finder := TFaceFinder.Create;
    Finder.Build(Edges, False);
    Face := Finder.CycleAt(At);
    if Face <> nil then
      Result := FacePath(Finder, Face, Path, WholeEdgeError);
  finally
    FreeAndNil(Finder);
    FreeAndNil(Edges);
  end;
end;

end.
