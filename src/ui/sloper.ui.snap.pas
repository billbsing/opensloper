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

// Snapping turns where the user clicks into the operation recorded for a
// new point: an existing point is reused, a crossing of two edges becomes an
// intersect point, a place on an edge a point along it, a spot level with or
// square to a point an offset from it, and anything else a free point.
// Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.Snap;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.Core.Note;

type
  // snHorizontal and snVertical: level with or square to a point
  TSnapKind = (snFree, snPoint, snCrossing, snEdge, snHorizontal, snVertical);

  TSnap = record
    Kind: TSnapKind;
    // Where the point goes, in mm
    Position: TVec2;
    // snPoint: the point; snHorizontal, snVertical: the point it lines up with
    PointKey: string;
    // snEdge: the edge; snCrossing: the two edges, in pattern order
    EdgeKey, OtherEdgeKey: string;
    // snCrossing: the crossing's number along EdgeKey, from 1
    Pick: integer;
    // snEdge: measured from the edge's end rather than its start
    FromEnd: boolean;
    // snEdge: distance along the edge; snHorizontal, snVertical: from the point
    Distance: double;
    // snHorizontal, snVertical: direction from the point, 0, 90, 180 or 270
    Angle: double;
  end;

// The snap for a click at At, looking Radius mm around it. AnchorKey, when
// given, is the point a line starts from: lining up with it comes first.
function FindSnap(Pattern: TPattern; const At: TVec2; Radius: double; const AnchorKey: string = ''): TSnap;
// What a click would make, in words
function SnapDescription(Pattern: TPattern; const Snap: TSnap): string;
// Adds the point the snap describes, with an automatic name, and returns its
// key; for snPoint returns the existing point. '' when refused, with the
// reason in Pattern.LastError.
function PointFromSnap(Pattern: TPattern; const Snap: TSnap): string;
// The existing objects the snap works from, whose labels help while drawing
function SnapObjectKeys(const Snap: TSnap): TStringArray;
// A circle around the snapped centre, through Rim, its radius rounded to
// 0.1 mm; the centre point is made if needed. nil when refused, with the
// reason in Pattern.LastError.
function CircleFromSnap(Pattern: TPattern; const Centre: TSnap; const Rim: TVec2; Role: TEdgeRole): TCircleObject;
// A rectangle from the snapped corner to Opposite, its width and height
// rounded to 0.1 mm and either way from the corner; the corner point is made
// if needed. False when refused, with the reason in Pattern.LastError.
function RectangleFromSnap(Pattern: TPattern; const Corner: TSnap; const Opposite: TVec2; Role: TEdgeRole;
  out Edges: TRectangleEdges): boolean;

// Where the Text tool hangs a note clicked at Click: the snapped point, or
// the place on the snapped edge (a crossing goes on its first edge); otherwise
// the piece Click is inside, or nothing. The offset is from there to Click.
procedure NoteAnchorFromSnap(Pattern: TPattern; const Snap: TSnap; const Click: TVec2; out Anchor: TNoteAnchor; out AnchorKey: string;
  out Ratio: double);
// A note with AText hung as NoteAnchorFromSnap says, its offset to the click
// rounded to 0.1 mm. nil when refused, with the reason in Pattern.LastError.
function NoteFromSnap(Pattern: TPattern; const Snap: TSnap; const Click: TVec2; const AText: string): TNoteObject;
// What a click of the Text tool would hang the note from, in words
function NoteSnapDescription(Pattern: TPattern; const Snap: TSnap; const Click: TVec2): string;

resourcestring
  rsSnapNotePoint = 'New note on point %s';
  rsSnapNoteEdge = 'New note on %s';
  rsSnapNotePiece = 'New note on piece %s';
  rsSnapNoteFree = 'New note at %s, %s';
  rsSnapTooSmall = 'Too small: move further from the first click';
  rsSnapFree = 'New point at %s, %s';
  rsSnapPoint = 'Point %s';
  rsSnapCrossing = 'New point where %s crosses %s';
  rsSnapEdge = 'New point on %s, %s mm from %s';
  rsSnapRight = 'New point %s mm right of %s';
  rsSnapLeft = 'New point %s mm left of %s';
  rsSnapUp = 'New point %s mm above %s';
  rsSnapDown = 'New point %s mm below %s';

implementation

uses
  Math, Sloper.Core.Evaluator, Sloper.Core.EvalTypes, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.UI.Scene;

const
  LengthDecimals = 1;

type
  TEdgeObjectArray = array of TEdgeObject;

// The edge a split part was cut from, followed back to the original
function RootEdge(Edge: TEdgeObject; Pattern: TPattern): TEdgeObject;
var
  Node: TEvalNode;
begin
  Result := Edge;
  while Result is TSplitPart do
  begin
    Node := Pattern.FindNode(TSplitPart(Result).Source);
    if not (Node is TEdgeObject) then
      Break;
    Result := TEdgeObject(Node);
  end;
end;

function IsUsable(Pattern: TPattern; DraftObject: TDraftObject): boolean;
begin
  Result := (DraftObject.State = esValid) and DraftObject.HasResult;
end;

// Valid edges within Radius of At, in pattern order
function NearbyEdges(Pattern: TPattern; const At: TVec2; Radius: double): TEdgeObjectArray;
var
  Index: integer;
  DraftObject: TDraftObject;
  Position, Offset: double;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if not (DraftObject is TEdgeObject) or not IsUsable(Pattern, DraftObject) or Pattern.IsHidden(DraftObject) then
      Continue;
    TEdgeObject(DraftObject).Locate(At, Position, Offset);
    if Offset <= Radius then
      Insert(TEdgeObject(DraftObject), Result, Length(Result));
  end;
end;

function FindCrossing(Pattern: TPattern; const Edges: TEdgeObjectArray; const At: TVec2; Radius: double;
  var Snap: TSnap): boolean;
var
  First, Second, Index: integer;
  Crossings: TEdgeCrossingArray;
  Best, Gap: double;
begin
  Result := False;
  Best := Radius;
  for First := 0 to High(Edges) - 1 do
    for Second := First + 1 to High(Edges) do
    begin
      // A split part lies on the edge it came from: they touch everywhere
      if RootEdge(Edges[First], Pattern) = RootEdge(Edges[Second], Pattern) then
        Continue;
      Crossings := CrossEdges(Edges[First], False, Edges[Second], False);
      for Index := 0 to High(Crossings) do
      begin
        Gap := Distance(Crossings[Index].Point, At);
        if Gap <= Best then
        begin
          Best := Gap;
          Snap.Kind := snCrossing;
          Snap.Position := Crossings[Index].Point;
          Snap.EdgeKey := Edges[First].Key;
          Snap.OtherEdgeKey := Edges[Second].Key;
          Snap.Pick := Index + 1;
          Result := True;
        end;
      end;
    end;
end;

procedure SnapToEdge(const Edges: TEdgeObjectArray; const At: TVec2; var Snap: TSnap);
var
  Edge, Best: TEdgeObject;
  Position, Offset, BestOffset, BestPosition: double;
  OnEdge, BestPoint: TVec2;
begin
  Best := nil;
  BestOffset := MaxDouble;
  BestPosition := 0;
  BestPoint := At;
  for Edge in Edges do
  begin
    OnEdge := Edge.Locate(At, Position, Offset);
    if Offset < BestOffset then
    begin
      Best := Edge;
      BestOffset := Offset;
      BestPosition := Position;
      BestPoint := OnEdge;
    end;
  end;
  Snap.Kind := snEdge;
  Snap.Position := BestPoint;
  Snap.EdgeKey := Best.Key;
  // Measured from the nearer end, so the number stays small and meaningful
  Snap.FromEnd := BestPosition > Best.Length / 2;
  if Snap.FromEnd then
    Snap.Distance := Best.Length - BestPosition
  else
    Snap.Distance := BestPosition;
end;

// Level with Base (horizontal) or square to it (vertical), when within
// Radius. The closest line-up wins; between equals, the nearer point.
function LineUp(Base: TPointObject; const At: TVec2; Radius: double; var Snap: TSnap; var BestGap: double): boolean;
const
  NearerWins = 1e-6;
var
  DX, DY: double;
begin
  Result := False;
  DX := At.X - Base.Position.X;
  DY := At.Y - Base.Position.Y;
  if (Abs(DY) <= Radius) and (Abs(DY) + Abs(DX) * NearerWins < BestGap) and (Abs(DX) > Radius) then
  begin
    BestGap := Abs(DY) + Abs(DX) * NearerWins;
    Snap.Kind := snHorizontal;
    Snap.Position := Vec2(At.X, Base.Position.Y);
    Snap.PointKey := Base.Key;
    Snap.Distance := Abs(DX);
    if DX >= 0 then
      Snap.Angle := 0
    else
      Snap.Angle := 180;
    Result := True;
  end;
  if (Abs(DX) <= Radius) and (Abs(DX) + Abs(DY) * NearerWins < BestGap) and (Abs(DY) > Radius) then
  begin
    BestGap := Abs(DX) + Abs(DY) * NearerWins;
    Snap.Kind := snVertical;
    Snap.Position := Vec2(Base.Position.X, At.Y);
    Snap.PointKey := Base.Key;
    Snap.Distance := Abs(DY);
    // y down: a smaller y is higher up, at 90 degrees
    if DY <= 0 then
      Snap.Angle := 90
    else
      Snap.Angle := 270;
    Result := True;
  end;
end;

function FindSnap(Pattern: TPattern; const At: TVec2; Radius: double; const AnchorKey: string): TSnap;
var
  Point: TPointObject;
  Edges: TEdgeObjectArray;
  Index: integer;
  DraftObject: TDraftObject;
  Anchor: TEvalNode;
  BestGap: double;
begin
  Result := Default(TSnap);
  Result.Kind := snFree;
  Result.Position := At;

  Point := PointAt(Pattern, At, Radius);
  if Assigned(Point) then
  begin
    Result.Kind := snPoint;
    Result.Position := Point.Position;
    Result.PointKey := Point.Key;
    Exit;
  end;

  Edges := NearbyEdges(Pattern, At, Radius);
  if FindCrossing(Pattern, Edges, At, Radius, Result) then
    Exit;
  if Length(Edges) > 0 then
  begin
    SnapToEdge(Edges, At, Result);
    Exit;
  end;

  BestGap := MaxDouble;
  Anchor := Pattern.FindNode(AnchorKey);
  if (Anchor is TPointObject) and IsUsable(Pattern, TPointObject(Anchor)) and LineUp(TPointObject(Anchor), At, Radius, Result, BestGap) then
    Exit;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject is TPointObject) and IsUsable(Pattern, DraftObject) then
      LineUp(TPointObject(DraftObject), At, Radius, Result, BestGap);
  end;
end;

function NameOf(Pattern: TPattern; const Key: string): string;
var
  Node: TEvalNode;
begin
  Node := Pattern.FindNode(Key);
  if not Assigned(Node) then
    Result := Key
  else
    Result := Node.DisplayName;
end;

function SnapDescription(Pattern: TPattern; const Snap: TSnap): string;
var
  Edge: TEdgeObject;
  EndName: string;
begin
  case Snap.Kind of
    snPoint:
      Result := Format(rsSnapPoint, [NameOf(Pattern, Snap.PointKey)]);
    snCrossing:
      Result := Format(rsSnapCrossing, [NameOf(Pattern, Snap.EdgeKey), NameOf(Pattern, Snap.OtherEdgeKey)]);
    snEdge:
    begin
      Edge := TEdgeObject(Pattern.FindNode(Snap.EdgeKey));
      if Snap.FromEnd then
        EndName := NameOf(Pattern, Edge.EndKey)
      else
        EndName := NameOf(Pattern, Edge.StartKey);
      Result := Format(rsSnapEdge, [Edge.DisplayName, RoundedText(Snap.Distance, LengthDecimals), EndName]);
    end;
    snHorizontal:
      if Snap.Angle = 0 then
        Result := Format(rsSnapRight, [RoundedText(Snap.Distance, LengthDecimals), NameOf(Pattern, Snap.PointKey)])
      else
        Result := Format(rsSnapLeft, [RoundedText(Snap.Distance, LengthDecimals), NameOf(Pattern, Snap.PointKey)]);
    snVertical:
      if Snap.Angle = 90 then
        Result := Format(rsSnapUp, [RoundedText(Snap.Distance, LengthDecimals), NameOf(Pattern, Snap.PointKey)])
      else
        Result := Format(rsSnapDown, [RoundedText(Snap.Distance, LengthDecimals), NameOf(Pattern, Snap.PointKey)]);
    else
      Result := Format(rsSnapFree, [RoundedText(Snap.Position.X, LengthDecimals), RoundedText(Snap.Position.Y, LengthDecimals)]);
  end;
end;

function PointFromSnap(Pattern: TPattern; const Snap: TSnap): string;
var
  Added: TPointObject;
begin
  case Snap.Kind of
    snPoint:
      Exit(Pattern.UsePoint(Snap.PointKey));
    snCrossing:
      Added := Pattern.AddIntersectPoint('', Snap.EdgeKey, Snap.OtherEdgeKey, False, False, Snap.Pick);
    snEdge:
      Added := Pattern.AddAlongEdgePoint('', Snap.EdgeKey, Snap.FromEnd, amLength, RoundedText(Snap.Distance, LengthDecimals));
    snHorizontal, snVertical:
      Added := Pattern.AddOffsetPoint('', Pattern.UsePoint(Snap.PointKey), omPolar, RoundedText(Snap.Distance, LengthDecimals),
        RoundedText(Snap.Angle, 0));
    else
      Added := Pattern.AddFreePoint('', RoundedText(Snap.Position.X, LengthDecimals), RoundedText(Snap.Position.Y, LengthDecimals));
  end;
  if not Assigned(Added) then
    Result := ''
  else
    Result := Added.Key;
end;

procedure NoteAnchorFromSnap(Pattern: TPattern; const Snap: TSnap; const Click: TVec2; out Anchor: TNoteAnchor; out AnchorKey: string;
  out Ratio: double);
var
  Edge: TEdgeObject;
  Piece: TPieceObject;
  Along, Offset: double;
begin
  Anchor := naFree;
  AnchorKey := '';
  Ratio := 0;
  case Snap.Kind of
    snPoint:
    begin
      Anchor := naPoint;
      AnchorKey := Snap.PointKey;
      Exit;
    end;
    snEdge, snCrossing:
    begin
      Edge := TEdgeObject(Pattern.FindNode(Snap.EdgeKey));
      if Assigned(Edge) and (Edge.Length > 0) then
      begin
        Edge.Locate(Snap.Position, Along, Offset);
        Anchor := naEdge;
        AnchorKey := Edge.Key;
        Ratio := EnsureRange(Along / Edge.Length, 0, 1);
        Exit;
      end;
    end;
  end;
  Piece := PieceAt(Pattern, Click);
  if Assigned(Piece) then
  begin
    Anchor := naPiece;
    AnchorKey := Piece.Key;
  end;
end;

function NoteFromSnap(Pattern: TPattern; const Snap: TSnap; const Click: TVec2; const AText: string): TNoteObject;
var
  Anchor: TNoteAnchor;
  AnchorKey, RatioText: string;
  Ratio: double;
  Base: TVec2;
  Node: TEvalNode;
begin
  NoteAnchorFromSnap(Pattern, Snap, Click, Anchor, AnchorKey, Ratio);
  RatioText := RoundedText(Ratio, DragRatioDecimals);
  if Anchor = naFree then
    Exit(Pattern.AddNote('', AText, naFree, '', '', RoundedText(Click.X, LengthDecimals), RoundedText(Click.Y, LengthDecimals)));
  Node := Pattern.FindNode(AnchorKey);
  case Anchor of
    naPoint: Base := TPointObject(Node).Position;
    naEdge: Base := TEdgeObject(Node).PointAtLength(RoundTo(Ratio, -DragRatioDecimals) * TEdgeObject(Node).Length);
    else
      Base := TPieceObject(Node).Middle;
  end;
  Result := Pattern.AddNote('', AText, Anchor, AnchorKey, RatioText, RoundedText(Click.X - Base.X, LengthDecimals),
    RoundedText(Click.Y - Base.Y, LengthDecimals));
end;

function NoteSnapDescription(Pattern: TPattern; const Snap: TSnap; const Click: TVec2): string;
var
  Anchor: TNoteAnchor;
  AnchorKey: string;
  Ratio: double;
begin
  NoteAnchorFromSnap(Pattern, Snap, Click, Anchor, AnchorKey, Ratio);
  case Anchor of
    naPoint: Result := Format(rsSnapNotePoint, [Pattern.FindNode(AnchorKey).DisplayName]);
    naEdge: Result := Format(rsSnapNoteEdge, [Pattern.FindNode(AnchorKey).DisplayName]);
    naPiece: Result := Format(rsSnapNotePiece, [Pattern.FindNode(AnchorKey).DisplayName]);
    else
      Result := Format(rsSnapNoteFree, [RoundedText(Click.X, LengthDecimals), RoundedText(Click.Y, LengthDecimals)]);
  end;
end;

function SnapObjectKeys(const Snap: TSnap): TStringArray;
var
  Key: string;
begin
  Result := nil;
  for Key in [Snap.PointKey, Snap.EdgeKey, Snap.OtherEdgeKey] do
    if Key <> '' then
      Insert(Key, Result, Length(Result));
end;

// Rounded as RoundedText rounds, so the check matches the formula written
function Rounds(Value: double): double;
begin
  Result := Round(Value * 10) / 10;
end;

function CircleFromSnap(Pattern: TPattern; const Centre: TSnap; const Rim: TVec2; Role: TEdgeRole): TCircleObject;
var
  CentreKey: string;
begin
  Result := nil;
  if Rounds(Distance(Centre.Position, Rim)) <= 0 then
  begin
    Pattern.Refuse(rsSnapTooSmall);
    Exit;
  end;
  CentreKey := PointFromSnap(Pattern, Centre);
  if CentreKey <> '' then
    Result := Pattern.AddCircle(CentreKey, RoundedText(Distance(Centre.Position, Rim), LengthDecimals), Role);
end;

function RectangleFromSnap(Pattern: TPattern; const Corner: TSnap; const Opposite: TVec2; Role: TEdgeRole;
  out Edges: TRectangleEdges): boolean;
var
  CornerKey: string;
begin
  Edges := Default(TRectangleEdges);
  if (Rounds(Opposite.X - Corner.Position.X) = 0) or (Rounds(Opposite.Y - Corner.Position.Y) = 0) then
    Exit(Pattern.Refuse(rsSnapTooSmall));
  CornerKey := PointFromSnap(Pattern, Corner);
  Result := (CornerKey <> '') and Pattern.AddRectangle(CornerKey, RoundedText(Opposite.X - Corner.Position.X, LengthDecimals),
    RoundedText(Opposite.Y - Corner.Position.Y, LengthDecimals), Role, Edges);
end;

end.
