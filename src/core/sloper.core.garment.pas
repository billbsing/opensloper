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

// The Garment view: the finished garment laid flat, front and back. Pieces are
// joined along their seams, moving and rotating but never bending, then
// mirrored across the centre line. Computed from the pattern; nothing here is
// stored. See Garment view in the design document. No LCL dependency.
unit Sloper.Core.Garment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Piece;

type
  TGarmentSide = (gsFront, gsBack);
  TPolylineArray = array of TVec2Array;

  TGarmentShape = record
    PieceName: string;
    // The closed seam line, to fill
    Outline: TVec2Array;
    // Each edge to draw; a fold is not an edge of the finished piece
    Lines: TPolylineArray;
  end;

  TGarmentShapeArray = array of TGarmentShape;

  TGarmentDrawing = record
    Shapes: TGarmentShapeArray;
    // Empty extent when there are no shapes
    Bounds: TRect2;
    // Pieces that no seam joins to the rest, drawn beside it
    Unjoined: TStringArray;
    // There is no centre line, so a piece cut twice shows one side only
    OneSided: boolean;
  end;

// Call after Evaluate. Failing pieces and seams are left out.
function BuildGarment(Pattern: TPattern; Side: TGarmentSide): TGarmentDrawing;
// How many pieces are in neither view
function PiecesWithoutView(Pattern: TPattern): integer;

implementation

uses
  Math, Sloper.Core.Bezier, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Seam;

const
  // Between what is joined and a piece that is not
  ClusterGap = 40;

type
  // X' = XX x + XY y + TX, Y' = YX x + YY y + TY
  TGarmentMap = record
    XX, XY, YX, YY, TX, TY: double;
  end;

  TGarmentItem = record
    Piece: TPieceObject;
    Map: TGarmentMap;
    Placed: boolean;
    // Which group of joined pieces it went into
    Cluster: integer;
  end;

  TGarmentItemArray = array of TGarmentItem;
  TSeamList = array of TSeamObject;

function IdentityMap: TGarmentMap;
begin
  Result := Default(TGarmentMap);
  Result.XX := 1;
  Result.YY := 1;
end;

function Moved(const Map: TGarmentMap; const P: TVec2): TVec2;
begin
  Result := Vec2(Map.XX * P.X + Map.XY * P.Y + Map.TX, Map.YX * P.X + Map.YY * P.Y + Map.TY);
end;

// Before first, then After
function Combined(const After, Before: TGarmentMap): TGarmentMap;
begin
  Result.XX := After.XX * Before.XX + After.XY * Before.YX;
  Result.XY := After.XX * Before.XY + After.XY * Before.YY;
  Result.YX := After.YX * Before.XX + After.YY * Before.YX;
  Result.YY := After.YX * Before.XY + After.YY * Before.YY;
  Result.TX := After.XX * Before.TX + After.XY * Before.TY + After.TX;
  Result.TY := After.YX * Before.TX + After.YY * Before.TY + After.TY;
end;

function Shifted(const Offset: TVec2): TGarmentMap;
begin
  Result := IdentityMap;
  Result.TX := Offset.X;
  Result.TY := Offset.Y;
end;

function Turned(AngleDeg: double): TGarmentMap;
begin
  Result := IdentityMap;
  Result.XX := Cos(DegToRad(AngleDeg));
  Result.XY := -Sin(DegToRad(AngleDeg));
  Result.YX := Sin(DegToRad(AngleDeg));
  Result.YY := Cos(DegToRad(AngleDeg));
end;

// Across the line through A and B
function Reflected(const A, B: TVec2): TGarmentMap;
var
  Along: TVec2;
  Span: double;
begin
  Result := IdentityMap;
  Span := Distance(A, B);
  if Span = 0 then
    Exit;
  Along := (B - A) * (1 / Span);
  Result.XX := Along.X * Along.X - Along.Y * Along.Y;
  Result.XY := 2 * Along.X * Along.Y;
  Result.YX := Result.XY;
  Result.YY := -Result.XX;
  Result.TX := A.X - (Result.XX * A.X + Result.XY * A.Y);
  Result.TY := A.Y - (Result.YX * A.X + Result.YY * A.Y);
end;

function ViewShows(Piece: TPieceObject; Side: TGarmentSide): boolean;
begin
  Result := (Piece.View = pvBoth) or ((Side = gsFront) and (Piece.View = pvFront)) or ((Side = gsBack) and (Piece.View = pvBack));
end;

function ItemsInView(Pattern: TPattern; Side: TGarmentSide): TGarmentItemArray;
var
  Index: integer;
  Item: TGarmentItem;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and (Pattern.Objects[Index].State = esValid) and
      ViewShows(TPieceObject(Pattern.Objects[Index]), Side) then
    begin
      Item := Default(TGarmentItem);
      Item.Piece := TPieceObject(Pattern.Objects[Index]);
      Item.Map := IdentityMap;
      Item.Cluster := -1;
      Insert(Item, Result, Length(Result));
    end;
end;

function IndexOfPiece(const Items: TGarmentItemArray; const PieceKey: string): integer;
begin
  for Result := 0 to High(Items) do
    if Items[Result].Piece.Key = PieceKey then
      Exit;
  Result := -1;
end;

function SideInView(const Items: TGarmentItemArray; const Side: TSeamSide): boolean;
var
  Entry: TSeamEntry;
begin
  Result := True;
  for Entry in Side do
    if IndexOfPiece(Items, Entry.PieceKey) < 0 then
      Exit(False);
end;

function IsLonger(A, B: TSeamObject): boolean;
begin
  Result := Max(A.LengthA, A.LengthB) > Max(B.LengthA, B.LengthB);
end;

// Longest first, and otherwise in file order
function SeamsInView(Pattern: TPattern; const Items: TGarmentItemArray): TSeamList;
var
  Index, Place: integer;
  Seam: TSeamObject;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TSeamObject) and (Pattern.Objects[Index].State = esValid) then
    begin
      Seam := TSeamObject(Pattern.Objects[Index]);
      if not SideInView(Items, Seam.SideA) or not SideInView(Items, Seam.SideB) then
        Continue;
      Place := Length(Result);
      while (Place > 0) and IsLonger(Seam, Result[Place - 1]) do
        Dec(Place);
      Insert(Seam, Result, Place);
    end;
end;

// Where a side of the seam starts and ends, walking the way it runs. Side B is
// listed from the other end of the seam, unless the seam is reversed.
procedure SideEnds(Pattern: TPattern; Seam: TSeamObject; OnSideB: boolean; const Items: TGarmentItemArray; out First, Last: TVec2);

  procedure EntryEnds(const Entry: TSeamEntry; out RunStart, RunEnd: TVec2);
  var
    Piece: TPieceObject;
    Edge: TEdgeObject;
    Map: TGarmentMap;
    Swap: TVec2;
  begin
    Piece := TPieceObject(Pattern.FindNode(Entry.PieceKey));
    Edge := TEdgeObject(Pattern.FindNode(Entry.EdgeKey));
    Map := Items[IndexOfPiece(Items, Entry.PieceKey)].Map;
    RunStart := Moved(Map, Edge.PointAtLength(0));
    RunEnd := Moved(Map, Edge.PointAtLength(Edge.Length));
    if not Seam.RunsForward(Piece, Entry, OnSideB) then
    begin
      Swap := RunStart;
      RunStart := RunEnd;
      RunEnd := Swap;
    end;
  end;

var
  Side: TSeamSide;
  Ignored: TVec2;
begin
  if OnSideB then
    Side := Seam.SideB
  else
    Side := Seam.SideA;
  if OnSideB and not Seam.Reversed then
  begin
    EntryEnds(Side[High(Side)], First, Ignored);
    EntryEnds(Side[0], Ignored, Last);
  end
  else
  begin
    EntryEnds(Side[0], First, Ignored);
    EntryEnds(Side[High(Side)], Ignored, Last);
  end;
end;

// Moves and turns so that the ends of one line meet those of another, as
// nearly as their lengths allow: any difference is shared between the ends
function JoiningMap(const FromStart, FromEnd, ToStart, ToEnd: TVec2): TGarmentMap;
var
  Turn: double;
  FromMiddle, ToMiddle: TVec2;
begin
  Turn := 0;
  if (Distance(FromStart, FromEnd) > DefaultTolerance) and (Distance(ToStart, ToEnd) > DefaultTolerance) then
    Turn := Line2(ToStart, ToEnd).Angle - Line2(FromStart, FromEnd).Angle;
  FromMiddle := Lerp(FromStart, FromEnd, 0.5);
  ToMiddle := Lerp(ToStart, ToEnd, 0.5);
  Result := Combined(Shifted(ToMiddle), Combined(Turned(Turn), Shifted(-FromMiddle)));
end;

function AllPlaced(const Items: TGarmentItemArray; const Side: TSeamSide; Cluster: integer): boolean;
var
  Entry: TSeamEntry;
  Item: TGarmentItem;
begin
  Result := True;
  for Entry in Side do
  begin
    Item := Items[IndexOfPiece(Items, Entry.PieceKey)];
    if not Item.Placed or (Item.Cluster <> Cluster) then
      Exit(False);
  end;
end;

// The one piece on this side, when it has one and it is still to be placed;
// otherwise -1
function SingleNewPiece(const Items: TGarmentItemArray; const Side: TSeamSide): integer;
var
  Entry: TSeamEntry;
begin
  Result := IndexOfPiece(Items, Side[0].PieceKey);
  if Items[Result].Placed then
    Exit(-1);
  for Entry in Side do
    if Entry.PieceKey <> Side[0].PieceKey then
      Exit(-1);
end;

// Puts the new side's piece against the placed side. False when this way
// round does not apply.
function JoinAcross(Pattern: TPattern; Seam: TSeamObject; NewIsSideB: boolean; var Items: TGarmentItemArray; Cluster: integer): boolean;
var
  PlacedSide, NewSide: TSeamSide;
  NewItem, Host: integer;
  ToStart, ToEnd, FromStart, FromEnd, NewMiddle, HostMiddle: TVec2;
  Map: TGarmentMap;
begin
  Result := False;
  if NewIsSideB then
  begin
    PlacedSide := Seam.SideA;
    NewSide := Seam.SideB;
  end
  else
  begin
    PlacedSide := Seam.SideB;
    NewSide := Seam.SideA;
  end;
  if not AllPlaced(Items, PlacedSide, Cluster) then
    Exit;
  NewItem := SingleNewPiece(Items, NewSide);
  if NewItem < 0 then
    Exit;
  SideEnds(Pattern, Seam, not NewIsSideB, Items, ToStart, ToEnd);
  SideEnds(Pattern, Seam, NewIsSideB, Items, FromStart, FromEnd);
  Map := JoiningMap(FromStart, FromEnd, ToStart, ToEnd);
  Host := IndexOfPiece(Items, PlacedSide[0].PieceKey);
  NewMiddle := Moved(Map, Items[NewItem].Piece.Middle);
  HostMiddle := Moved(Items[Host].Map, Items[Host].Piece.Middle);
  // On the same side of the seam, it would lie over the piece it joins
  if Cross(ToEnd - ToStart, NewMiddle - ToStart) * Cross(ToEnd - ToStart, HostMiddle - ToStart) > 0 then
    Map := Combined(Reflected(ToStart, ToEnd), Map);
  Items[NewItem].Map := Map;
  Items[NewItem].Placed := True;
  Items[NewItem].Cluster := Cluster;
  Result := True;
end;

procedure JoinAll(Pattern: TPattern; const Seams: TSeamList; var Items: TGarmentItemArray; Cluster: integer);
var
  Seam: TSeamObject;
  Joined: boolean;
begin
  repeat
    Joined := False;
    for Seam in Seams do
      if JoinAcross(Pattern, Seam, True, Items, Cluster) or JoinAcross(Pattern, Seam, False, Items, Cluster) then
      begin
        Joined := True;
        Break;
      end;
  until not Joined;
end;

function LargestUnplaced(const Items: TGarmentItemArray): integer;
var
  Index: integer;
begin
  Result := -1;
  for Index := 0 to High(Items) do
    if not Items[Index].Placed and ((Result < 0) or (Items[Index].Piece.Area > Items[Result].Piece.Area)) then
      Result := Index;
end;

function IsSelfSeam(Seam: TSeamObject): boolean;
begin
  Result := (Length(Seam.SideA) = 1) and (Length(Seam.SideB) = 1) and (Seam.SideA[0].PieceKey = Seam.SideB[0].PieceKey) and
    (Seam.SideA[0].EdgeKey = Seam.SideB[0].EdgeKey);
end;

// A piece's fold, or an edge seamed to itself
function FindCentreLine(Pattern: TPattern; const Seams: TSeamList; const Items: TGarmentItemArray; Cluster: integer; out Centre: TLine2): boolean;
var
  Item: TGarmentItem;
  Seam: TSeamObject;
  Edge: TEdgeObject;
  Map: TGarmentMap;
begin
  Centre := Default(TLine2);
  Result := True;
  for Item in Items do
    if Item.Placed and (Item.Cluster = Cluster) and Item.Piece.OnFold then
    begin
      Centre := Line2(Moved(Item.Map, Item.Piece.FoldLine.P1), Moved(Item.Map, Item.Piece.FoldLine.P2));
      Exit;
    end;
  for Seam in Seams do
    if IsSelfSeam(Seam) then
    begin
      Item := Items[IndexOfPiece(Items, Seam.SideA[0].PieceKey)];
      if not Item.Placed or (Item.Cluster <> Cluster) then
        Continue;
      Edge := TEdgeObject(Pattern.FindNode(Seam.SideA[0].EdgeKey));
      Map := Item.Map;
      Centre := Line2(Moved(Map, Edge.PointAtLength(0)), Moved(Map, Edge.PointAtLength(Edge.Length)));
      Exit;
    end;
  Result := False;
end;

function MovedAll(const Map: TGarmentMap; const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Moved(Map, Points[Index]);
end;

function ShapeOf(Pattern: TPattern; const Item: TGarmentItem; const Map: TGarmentMap): TGarmentShape;
var
  Entry: TPieceEdge;
begin
  Result := Default(TGarmentShape);
  Result.PieceName := Item.Piece.DisplayName;
  Result.Outline := MovedAll(Map, Item.Piece.Outline);
  for Entry in Item.Piece.Path do
    if Entry.EdgeKey <> Item.Piece.FoldEdgeKey then
      Insert(MovedAll(Map, TEdgeObject(Pattern.FindNode(Entry.EdgeKey)).Flatten(CoarseFlatness)), Result.Lines, Length(Result.Lines));
end;

// So the centre line stands upright, turning as little as it can, which keeps
// the side that was up
function UprightMap(const Centre: TLine2): TGarmentMap;
var
  Turn: double;
begin
  Turn := 90 - Centre.Angle;
  while Turn > 90 do
    Turn := Turn - 180;
  while Turn <= -90 do
    Turn := Turn + 180;
  Result := Turned(Turn);
end;

procedure Grow(var Bounds: TRect2; var Started: boolean; const Points: TVec2Array);
var
  P: TVec2;
begin
  for P in Points do
    if not Started then
    begin
      Bounds.MinX := P.X;
      Bounds.MaxX := P.X;
      Bounds.MinY := P.Y;
      Bounds.MaxY := P.Y;
      Started := True;
    end
    else
    begin
      Bounds.MinX := Min(Bounds.MinX, P.X);
      Bounds.MaxX := Max(Bounds.MaxX, P.X);
      Bounds.MinY := Min(Bounds.MinY, P.Y);
      Bounds.MaxY := Max(Bounds.MaxY, P.Y);
    end;
end;

// The shapes of one group of joined pieces, opened out and upright
function ClusterShapes(Pattern: TPattern; const Seams: TSeamList; const Items: TGarmentItemArray; Cluster: integer;
  var OneSided: boolean): TGarmentShapeArray;
var
  Item: TGarmentItem;
  Centre: TLine2;
  HasCentre: boolean;
  Upright, Mirror: TGarmentMap;
begin
  Result := nil;
  HasCentre := FindCentreLine(Pattern, Seams, Items, Cluster, Centre);
  Upright := IdentityMap;
  Mirror := IdentityMap;
  if HasCentre then
  begin
    Upright := UprightMap(Centre);
    Mirror := Reflected(Centre.P1, Centre.P2);
  end;
  for Item in Items do
  begin
    if Item.Cluster <> Cluster then
      Continue;
    Insert(ShapeOf(Pattern, Item, Combined(Upright, Item.Map)), Result, Length(Result));
    if HasCentre and (Item.Piece.OnFold or (Item.Piece.CutCount > 1)) then
      Insert(ShapeOf(Pattern, Item, Combined(Upright, Combined(Mirror, Item.Map))), Result, Length(Result))
    else if not HasCentre and (Item.Piece.CutCount > 1) then
      OneSided := True;
  end;
end;

// Moves each shape by Offset
function ShapesShifted(const Shapes: TGarmentShapeArray; const Offset: TVec2): TGarmentShapeArray;
var
  Index, Line: integer;
  Map: TGarmentMap;
begin
  Map := Shifted(Offset);
  Result := Copy(Shapes);
  for Index := 0 to High(Result) do
  begin
    Result[Index].Outline := MovedAll(Map, Shapes[Index].Outline);
    Result[Index].Lines := Copy(Shapes[Index].Lines);
    for Line := 0 to High(Result[Index].Lines) do
      Result[Index].Lines[Line] := MovedAll(Map, Shapes[Index].Lines[Line]);
  end;
end;

function ShapesBounds(const Shapes: TGarmentShapeArray): TRect2;
var
  Shape: TGarmentShape;
  Started: boolean;
begin
  Result := Default(TRect2);
  Started := False;
  for Shape in Shapes do
    Grow(Result, Started, Shape.Outline);
end;

function BuildGarment(Pattern: TPattern; Side: TGarmentSide): TGarmentDrawing;
var
  Items: TGarmentItemArray;
  Seams: TSeamList;
  Shapes: TGarmentShapeArray;
  Cluster, Root: integer;
  Own: TRect2;
begin
  Result := Default(TGarmentDrawing);
  Items := ItemsInView(Pattern, Side);
  Seams := SeamsInView(Pattern, Items);
  Cluster := 0;
  repeat
    Root := LargestUnplaced(Items);
    if Root < 0 then
      Break;
    Items[Root].Placed := True;
    Items[Root].Cluster := Cluster;
    if Cluster > 0 then
      Insert(Items[Root].Piece.DisplayName, Result.Unjoined, Length(Result.Unjoined));
    JoinAll(Pattern, Seams, Items, Cluster);
    Shapes := ClusterShapes(Pattern, Seams, Items, Cluster, Result.OneSided);
    // Each group after the first goes beside what is there
    if Cluster > 0 then
    begin
      Own := ShapesBounds(Shapes);
      Shapes := ShapesShifted(Shapes, Vec2(Result.Bounds.MaxX + ClusterGap - Own.MinX, Result.Bounds.MaxY - Own.MaxY));
    end;
    Result.Shapes := Concat(Result.Shapes, Shapes);
    Result.Bounds := ShapesBounds(Result.Shapes);
    Inc(Cluster);
  until False;
end;

function PiecesWithoutView(Pattern: TPattern): integer;
var
  Index: integer;
begin
  Result := 0;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and (TPieceObject(Pattern.Objects[Index]).View = pvNone) then
      Inc(Result);
end;

end.
