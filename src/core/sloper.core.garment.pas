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

// The Garment view's scene: each piece as sewn, darts closed and folds opened,
// placed where it is on the canvas with its grainline upright, and how it is
// shaded. Computed from the evaluated pattern; nothing here is stored. The
// painter and the SVG export draw what this hands them. See Garment view in
// the design document. No LCL dependency.
unit Sloper.Core.Garment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Numeric, Sloper.Core.Settings, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.Piece,
  Sloper.Core.Pattern;

type
  TPolylineArray = array of TVec2Array;

  // A line drawn on a finished piece: an edge of its outline, a closed dart or
  // a stitch marking. EdgeKey is the edge it was drawn from; SeamKey names the
  // dart a closed dart's stitch line belongs to.
  TGarmentLine = record
    Points: TVec2Array;
    EdgeKey, SeamKey: string;
    // An outline edge in a seam, drawn as a stitch
    Sewn: boolean;
  end;

  TGarmentLineArray = array of TGarmentLine;

  // A button, hole or match dot, Size across, or a stitch hole
  TGarmentMarker = record
    Centre: TVec2;
    Size: double;
    Marker: TPointMarker;
  end;

  TGarmentMarkerArray = array of TGarmentMarker;

  TGarmentPiece = record
    PieceKey, Name: string;
    Look: TPieceLook;
    // Index of its material in the pattern, or -1 for none
    MaterialIndex: integer;
    // The closed seam line, to fill
    Outline: TVec2Array;
    // Outline edges; a fold has none
    Edges: TGarmentLineArray;
    // Closed darts, stitch lines and topstitching
    Stitches: TGarmentLineArray;
    Markers: TGarmentMarkerArray;
    Bounds: TRect2;
    // Shaded across each column rather than each row: a long narrow piece
    // lying across
    ShadeColumns: boolean;
  end;

  TGarmentPieceArray = array of TGarmentPiece;

  TGarmentScene = record
    // In the canvas's stacking order, lowest first
    Pieces: TGarmentPieceArray;
    // What was left out, for under the drawing
    Notes: TStringArray;
    // Empty extent when there are no pieces
    Bounds: TRect2;
  end;

  // How the pieces are lit (see Preferences)
  TGarmentLight = record
    Enabled: boolean;
    // Where the light comes from, degrees as on the canvas: 135 is upper left
    Angle: double;
    // 0 flat to 1 full
    Strength: double;
  end;

  TGarmentEntry = record
    Fingerprint: string;
    Piece: TGarmentPiece;
    Notes: TStringArray;
  end;

  TGarmentEntryMap = specialize TDictionary<string, TGarmentEntry>;

  // Builds scenes, rebuilding only the pieces whose geometry changed since the
  // last build
  TGarmentBuilder = class
  private
    FEntries: TGarmentEntryMap;
    FRebuilt: integer;
  public
    constructor Create;
    destructor Destroy; override;
    // Call after Evaluate. Failing pieces are left out with a note.
    function Build(Pattern: TPattern): TGarmentScene;
    procedure Clear;
    // How many pieces the last Build worked out afresh
    property Rebuilt: integer read FRebuilt;
  end;

const
  // A piece this many times as long as it is wide is shaded as a tube
  GARMENT_NARROW_RATIO = 3;
  GARMENT_MAX_DART = 90;

function DefaultGarmentLight: TGarmentLight;
// As set in Preferences
function GarmentLightOf(const Preferences: TPreferences): TGarmentLight;
// One piece as sewn, with notes on what could not be done
function BuildGarmentPiece(Pattern: TPattern; Piece: TPieceObject; out Notes: TStringArray): TGarmentPiece;
function BuildGarment(Pattern: TPattern): TGarmentScene;
// The pieces of one material, by index, or all for -1; Bounds follows them
function GarmentOfMaterial(const Scene: TGarmentScene; MaterialIndex: integer): TGarmentScene;
// How bright a point is, as a factor on its colour (1 unchanged): Across is
// where it is between the two sides of the piece at its row, 0 at the left
// (top for columns) and 1 at the right, lit as a half cylinder
function GarmentShade(Across: double; Columns: boolean; const Light: TGarmentLight): double;
// The outermost crossings of the outline with the row at Y (the column at X
// for Columns); False when it misses
function GarmentSpan(const Outline: TVec2Array; Columns: boolean; Coord: double; out Low, High: double): boolean;
// The spans of Count rows (columns) from Start, Step apart, each averaged with
// those just above and below it, so the shading follows the outline without
// jumping where it turns sharply; a row the piece misses has Low above High
procedure GarmentSpans(const Piece: TGarmentPiece; Start, Step: double; Count: integer; out Lows, Highs: TDoubleArray);
// How much an edge running from SegmentStart to SegmentEnd faces the light, -1 away to 1 towards,
// from its outward side
function GarmentEdgeFacing(const Outline: TVec2Array; const SegmentStart, SegmentEnd: TVec2; const Light: TGarmentLight): double;
// The unit normal into the piece across the segment from SegmentStart to SegmentEnd
function GarmentInward(const Outline: TVec2Array; const SegmentStart, SegmentEnd: TVec2): TVec2;
// The topmost piece under Position, or -1
function GarmentPieceAt(const Scene: TGarmentScene; const Position: TVec2): integer;
// The line moved Inset into the piece, each point along the mean of the
// inward normals either side of it: a seam's stitches, just inside its edge
function GarmentInset(const Outline, Points: TVec2Array; Inset: double): TVec2Array;
// The edge's mean facing (GarmentEdgeFacing), weighted by length
function GarmentLineFacing(const Outline, Points: TVec2Array; const Light: TGarmentLight): double;
// What a piece is filled with under its shading: its material's colour at
// full strength; the light tint under hatching; grey with no material
function GarmentBaseColor(const Look: TPieceLook): TMaterialColor;
// The colour times Shade, kept within 0 to 255
function ShadedColor(const Color: TMaterialColor; Shade: double): TMaterialColor;

resourcestring
  rsGarmentDartCurved = 'The dart %s on %s is left open: a leg is curved';
  rsGarmentDartWide = 'The dart %s on %s is left open: it is wider than %d°';
  rsGarmentDartInward = 'The dart %s on %s is left open: its legs do not open away from the piece';
  rsGarmentPieceFails = '%s is left out: it has a problem';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Bezier, Sloper.Core.Seam, Sloper.Core.Warp;

const
  // A leg further than this (mm) from its chord is curved
  STRAIGHT_TOLERANCE = 0.05;
  // How high the light is above the panel, in degrees
  LIGHT_ELEVATION = 65;
  // What the light leaves at the sides, so they never go black
  AMBIENT = 0.45;
  // A row's span is the widest of those this share of the piece's height
  // either side, so rows cut short by a sloping hem or shoulder take the
  // width just past it; then spans are averaged over the second share, so the
  // shading does not jump where the outline turns sharply (an underarm)
  SPAN_ENVELOPE = 0.05;
  SPAN_SMOOTHING = 0.04;
  // A step off a segment for the inside test, in mm
  SIDE_STEP = 0.05;
  UNFILLED_COLOR: TMaterialColor = (Red: 214; Green: 214; Blue: 210);

type
  TDartInfo = record
    SeamKey: string;
    FirstIndex, SecondIndex: integer;
    // As drafted
    Apex, FirstEnd, SecondEnd: TVec2;
    Closing: TDartClosing;
  end;

  TDartInfoArray = array of TDartInfo;

function DefaultGarmentLight: TGarmentLight;
begin
  Result.Enabled := True;
  Result.Angle := DEFAULT_GARMENT_LIGHT_ANGLE;
  Result.Strength := DEFAULT_GARMENT_SHADE_STRENGTH;
end;

function GarmentLightOf(const Preferences: TPreferences): TGarmentLight;
begin
  Result.Enabled := Preferences.GarmentShading;
  Result.Angle := Preferences.GarmentLightAngle;
  Result.Strength := Preferences.GarmentShadeStrength;
end;

function EmptyRect: TRect2;
begin
  Result.MinX := Infinity;
  Result.MinY := Infinity;
  Result.MaxX := -Infinity;
  Result.MaxY := -Infinity;
end;

procedure GrowRect(var Bounds: TRect2; const Points: TVec2Array);
var
  Point: TVec2;
begin
  for Point in Points do
  begin
    Bounds.MinX := Min(Bounds.MinX, Point.X);
    Bounds.MinY := Min(Bounds.MinY, Point.Y);
    Bounds.MaxX := Max(Bounds.MaxX, Point.X);
    Bounds.MaxY := Max(Bounds.MaxY, Point.Y);
  end;
end;

procedure GrowRectBy(var Bounds: TRect2; const Other: TRect2);
begin
  Bounds.MinX := Min(Bounds.MinX, Other.MinX);
  Bounds.MinY := Min(Bounds.MinY, Other.MinY);
  Bounds.MaxX := Max(Bounds.MaxX, Other.MaxX);
  Bounds.MaxY := Max(Bounds.MaxY, Other.MaxY);
end;

function MapAll(const Map: TAffine2; const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Map.Apply(Points[Index]);
end;

function ReversedAll(const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Points[High(Points) - Index];
end;

// The edge's points the way the path runs
function PathPoints(Pattern: TPattern; Piece: TPieceObject; PathIndex: integer): TVec2Array;
begin
  Result := TEdgeObject(Pattern.FindNode(Piece.Path[PathIndex].EdgeKey)).Flatten(COARSE_FLATNESS);
  if Piece.Path[PathIndex].Reversed then
    Result := ReversedAll(Result);
end;

function IsStraightRun(const Points: TVec2Array): boolean;
var
  Chord: TLine2;
  Point: TVec2;
begin
  Result := True;
  if Length(Points) < 3 then
    Exit;
  Chord := Line2(Points[0], Points[High(Points)]);
  for Point in Points do
    if Distance(Point, Chord.ClosestPoint(Point, True)) > STRAIGHT_TOLERANCE then
      Exit(False);
end;

// Seams of the piece whose two sides are one edge each of this piece, meeting
// at a point of its path: its darts, in pattern order
function FindDarts(Pattern: TPattern; Piece: TPieceObject; var Notes: TStringArray): TDartInfoArray;
var
  Index, First, Second, Count: integer;
  Seam: TSeamObject;
  Info: TDartInfo;
  FirstPoints, SecondPoints: TVec2Array;
  Swap: integer;
begin
  Result := nil;
  Count := Length(Piece.Path);
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TSeamObject) or (Pattern.Objects[Index].State <> esValid) then
      Continue;
    Seam := TSeamObject(Pattern.Objects[Index]);
    if (Length(Seam.SideA) <> 1) or (Length(Seam.SideB) <> 1) or (Seam.SideA[0].PieceKey <> Piece.Key) or
      (Seam.SideB[0].PieceKey <> Piece.Key) or (Seam.SideA[0].EdgeKey = Seam.SideB[0].EdgeKey) then
      Continue;
    First := Piece.PathIndexOf(Seam.SideA[0].EdgeKey);
    Second := Piece.PathIndexOf(Seam.SideB[0].EdgeKey);
    if (First < 0) or (Second < 0) then
      Continue;
    // The path runs along the first leg into the apex and out along the second
    if (First + 1) mod Count <> Second then
    begin
      if (Second + 1) mod Count <> First then
        Continue;
      Swap := First;
      First := Second;
      Second := Swap;
    end;
    Info := Default(TDartInfo);
    Info.SeamKey := Seam.Key;
    Info.FirstIndex := First;
    Info.SecondIndex := Second;
    FirstPoints := PathPoints(Pattern, Piece, First);
    SecondPoints := PathPoints(Pattern, Piece, Second);
    if not IsStraightRun(FirstPoints) or not IsStraightRun(SecondPoints) then
    begin
      Insert(Format(rsGarmentDartCurved, [Seam.DisplayName, Piece.DisplayName]), Notes, Length(Notes));
      Continue;
    end;
    Info.Apex := FirstPoints[High(FirstPoints)];
    Info.FirstEnd := FirstPoints[0];
    Info.SecondEnd := SecondPoints[High(SecondPoints)];
    if not MakeDartClosing(Info.Apex, Info.FirstEnd, Info.SecondEnd, Piece.Outline, Info.Closing) then
    begin
      Insert(Format(rsGarmentDartInward, [Seam.DisplayName, Piece.DisplayName]), Notes, Length(Notes));
      Continue;
    end;
    if Info.Closing.Opening > GARMENT_MAX_DART then
    begin
      Insert(Format(rsGarmentDartWide, [Seam.DisplayName, Piece.DisplayName, GARMENT_MAX_DART]), Notes, Length(Notes));
      Continue;
    end;
    Insert(Info, Result, Length(Result));
  end;
end;

function IsDartLeg(const Darts: TDartInfoArray; PathIndex: integer): boolean;
var
  Dart: TDartInfo;
begin
  Result := False;
  for Dart in Darts do
    if (Dart.FirstIndex = PathIndex) or (Dart.SecondIndex = PathIndex) then
      Exit(True);
end;

// Whether a seam other than a dart sews this edge of the piece
function IsSewn(Pattern: TPattern; Piece: TPieceObject; const EdgeKey: string; const Darts: TDartInfoArray): boolean;
var
  Index: integer;
  Seam: TSeamObject;
  Dart: TDartInfo;
  IsDart: boolean;
begin
  Result := False;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TSeamObject) or (Pattern.Objects[Index].State <> esValid) then
      Continue;
    Seam := TSeamObject(Pattern.Objects[Index]);
    IsDart := False;
    for Dart in Darts do
      IsDart := IsDart or (Dart.SeamKey = Seam.Key);
    if not IsDart and Seam.UsesEdge(Piece.Key, EdgeKey) then
      Exit(True);
  end;
end;

// The outline point furthest from every apex, which closing the darts must
// not move
function Anchor(const Outline: TVec2Array; const Darts: TDartInfoArray): TVec2;
var
  Point: TVec2;
  Dart: TDartInfo;
  Nearest, Best: double;
begin
  Result := Outline[0];
  Best := -1;
  for Point in Outline do
  begin
    Nearest := Infinity;
    for Dart in Darts do
      Nearest := Min(Nearest, Distance(Point, Dart.Closing.Apex));
    if Nearest > Best then
    begin
      Best := Nearest;
      Result := Point;
    end;
  end;
end;

// The least turn that stands the line upright
function UprightTurn(const Line: TLine2): double;
begin
  Result := 90 - Line.Angle;
  while Result > 90 do
    Result := Result - 180;
  while Result <= -90 do
    Result := Result + 180;
end;

function MaterialIndexOf(Pattern: TPattern; Piece: TPieceObject): integer;
var
  Material: TPatternMaterial;
begin
  Material := Pattern.MaterialOf(Piece);
  for Result := 0 to Pattern.MaterialCount - 1 do
    if Pattern.Materials[Result] = Material then
      Exit;
  Result := -1;
end;

function MakeLine(const Points: TVec2Array; const EdgeKey, SeamKey: string; Sewn: boolean): TGarmentLine;
begin
  Result := Default(TGarmentLine);
  Result.Points := Points;
  Result.EdgeKey := EdgeKey;
  Result.SeamKey := SeamKey;
  Result.Sewn := Sewn;
end;

function BuildGarmentPiece(Pattern: TPattern; Piece: TPieceObject; out Notes: TStringArray): TGarmentPiece;
var
  Warp: TPieceWarp;
  Darts: TDartInfoArray;
  Dart: TDartInfo;
  Start, Step, PathIndex, FoldIndex, Count, Index: integer;
  Half, Points, Ends: TVec2Array;
  Final, Mirror, Base: TAffine2;
  Fixed, FoldA, FoldB: TVec2;
  Mark: TMarkingMark;
  Folded: boolean;
  Turn: double;
  EdgeKey: string;

// Through the darts, the placement and, for the opened half, the fold
  function Finished(const Position: TVec2; Mirrored: boolean): TVec2;
  begin
    if Mirrored then
      Result := Mirror.Apply(Warp.Apply(Position))
    else
      Result := Final.Apply(Warp.Apply(Position));
  end;

  function FinishedAll(const Source: TVec2Array; Mirrored: boolean): TVec2Array;
  var
    PointIndex: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Source));
    for PointIndex := 0 to High(Source) do
      Result[PointIndex] := Finished(Source[PointIndex], Mirrored);
  end;

  procedure AddBoth(var Lines: TGarmentLineArray; const Source: TVec2Array; const AEdgeKey, ASeamKey: string; Sewn: boolean);
  begin
    Insert(MakeLine(FinishedAll(Source, False), AEdgeKey, ASeamKey, Sewn), Lines, Length(Lines));
    if Folded then
      Insert(MakeLine(FinishedAll(Source, True), AEdgeKey, ASeamKey, Sewn), Lines, Length(Lines));
  end;

  procedure AddMarkers(const Centres: TVec2Array; Size: double; AMarker: TPointMarker);
  var
    Marker: TGarmentMarker;
    Centre: TVec2;
    Mirrored: boolean;
  begin
    for Mirrored := False to Folded do
      for Centre in Centres do
      begin
        Marker.Centre := Finished(Centre, Mirrored);
        Marker.Size := Size;
        Marker.Marker := AMarker;
        Insert(Marker, Result.Markers, Length(Result.Markers));
      end;
  end;

begin
  Notes := nil;
  Result := Default(TGarmentPiece);
  Result.PieceKey := Piece.Key;
  Result.Name := Piece.DisplayName;
  Result.Look := Pattern.PieceLook(Piece);
  Result.MaterialIndex := MaterialIndexOf(Pattern, Piece);
  Count := Length(Piece.Path);
  Warp := TPieceWarp.Create;
  try
    Darts := FindDarts(Pattern, Piece, Notes);
    for Dart in Darts do
      Warp.AddDart(Dart.Closing);
    FoldIndex := -1;
    if Piece.OnFold then
      FoldIndex := Piece.PathIndexOf(Piece.FoldEdgeKey);
    Folded := FoldIndex >= 0;
    // Closing the darts leaves the part furthest from them where it was, or
    // on a fold the fold, so the two halves stay square to it
    Base := AffineIdentity;
    if (Length(Darts) > 0) and Folded then
    begin
      FoldA := Warp.Close(Piece.FoldLine.P1);
      FoldB := Warp.Close(Piece.FoldLine.P2);
      Fixed := Lerp(Piece.FoldLine.P1, Piece.FoldLine.P2, 0.5);
      Turn := NormalizeAngle(Piece.FoldLine.Angle - Line2(FoldA, FoldB).Angle);
      if Turn > 180 then
        Turn := Turn - 360;
      Base := AffineThen(AffineTurnAbout(Fixed, Turn), AffineShift(Fixed - Lerp(FoldA, FoldB, 0.5)));
    end
    else if Length(Darts) > 0 then
    begin
      Fixed := Anchor(Piece.Outline, Darts);
      Base := AffineShift(Fixed - Warp.Close(Fixed));
    end;
    Warp.Placement := Base;
    // As drafted: the part furthest from the darts, which closing them leaves
    // unturned, keeps the grain's direction, and a fold stays straight
    Turn := 0;
    if Piece.GrainKind <> gkNone then
      Turn := UprightTurn(Piece.Grainline);
    Final := AffineTurnAbout(Piece.Middle, Turn);
    Mirror := Final;
    if Folded then
    begin
      FoldA := Warp.Apply(Piece.FoldLine.P1);
      FoldB := Warp.Apply(Piece.FoldLine.P2);
      Mirror := AffineThen(Final, AffineReflect(FoldA, FoldB));
    end;

    // Round the path from just after the fold, so an opened piece is one
    // run from the fold back to it, then the same mirrored and reversed
    Start := 0;
    if Folded then
      Start := (FoldIndex + 1) mod Count;
    Half := nil;
    for Step := 0 to Count - 1 do
    begin
      PathIndex := (Start + Step) mod Count;
      if (PathIndex = FoldIndex) or IsDartLeg(Darts, PathIndex) then
        Continue;
      Points := PathPoints(Pattern, Piece, PathIndex);
      EdgeKey := Piece.Path[PathIndex].EdgeKey;
      AddBoth(Result.Edges, Points, EdgeKey, '', IsSewn(Pattern, Piece, EdgeKey, Darts));
      // Closed, not yet placed
      Points := Warp.ApplyAll(Points);
      // Each edge but the first starts where the one before ended
      if Length(Half) > 0 then
        Delete(Points, 0, 1);
      Half := Concat(Half, Points);
    end;
    if Folded then
    begin
      // From the fold's end round to its start, then back on the other side
      Points := MapAll(Mirror, ReversedAll(Half));
      Result.Outline := Concat(MapAll(Final, Half), Copy(Points, 1, Length(Points) - 2));
    end
    else
    begin
      Result.Outline := MapAll(Final, Half);
      // Closed without repeating the first point
      if (Length(Half) > 1) and PointsNear(Half[0], Half[High(Half)], PIECE_JOIN_TOLERANCE) then
        SetLength(Result.Outline, Length(Half) - 1);
    end;

    // A closed dart is one stitch line from its apex to where its legs met
    for Dart in Darts do
    begin
      Ends := nil;
      SetLength(Ends, 2);
      Ends[0] := Warp.Apply(Dart.Apex);
      Ends[1] := Lerp(Warp.Apply(Dart.FirstEnd), Warp.Apply(Dart.SecondEnd), 0.5);
      Insert(MakeLine(MapAll(Final, Ends), '', Dart.SeamKey, False), Result.Stitches, Length(Result.Stitches));
      if Folded then
        Insert(MakeLine(MapAll(Mirror, Ends), '', Dart.SeamKey, False), Result.Stitches, Length(Result.Stitches));
    end;

    for Index := 0 to High(Piece.MarkingMarks) do
    begin
      Mark := Piece.MarkingMarks[Index];
      case Mark.Kind of
        mkLine:
          if Mark.Role = erStitch then
            AddBoth(Result.Stitches, Mark.Line, Piece.Markings[Index].EdgeKey, '', False);
        mkStitchHoles: AddMarkers(Mark.Holes, Mark.HoleSize, pmHole);
        mkPoint: AddMarkers(Mark.Centres, Mark.HoleSize, Mark.Marker);
      end;
    end;
  finally
    FreeAndNil(Warp);
  end;
  Result.Bounds := EmptyRect;
  GrowRect(Result.Bounds, Result.Outline);
  Result.ShadeColumns := (Result.Bounds.MaxX - Result.Bounds.MinX) >= GARMENT_NARROW_RATIO * (Result.Bounds.MaxY - Result.Bounds.MinY);
end;

// Everything the piece's finished shape follows from, so an unchanged piece
// is not built again
function Fingerprint(Pattern: TPattern; Piece: TPieceObject): string;
var
  Builder: TStringBuilder;
  Point: TVec2;
  Index: integer;
  Seam: TSeamObject;
  Look: TPieceLook;
  Mark: TMarkingMark;

  procedure AddNumber(Value: double);
  begin
    Builder.Append(FloatToStrF(Value, ffGeneral, 10, 0));
    Builder.Append(' ');
  end;

  procedure AddPoints(const Points: TVec2Array);
  var
    Each: TVec2;
  begin
    for Each in Points do
    begin
      AddNumber(Each.X);
      AddNumber(Each.Y);
    end;
    Builder.Append('|');
  end;

begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append(Piece.DisplayName + '|');
    for Index := 0 to High(Piece.Path) do
    begin
      Builder.Append(Piece.Path[Index].EdgeKey + ' ');
      AddPoints(TEdgeObject(Pattern.FindNode(Piece.Path[Index].EdgeKey)).Flatten(COARSE_FLATNESS));
    end;
    for Point in Piece.Outline do
    begin
      AddNumber(Point.X);
      AddNumber(Point.Y);
    end;
    Builder.Append(IntToStr(Ord(Piece.GrainKind)) + '|');
    AddNumber(Piece.Grainline.P1.X);
    AddNumber(Piece.Grainline.P1.Y);
    AddNumber(Piece.Grainline.P2.X);
    AddNumber(Piece.Grainline.P2.Y);
    Builder.Append(Piece.FoldEdgeKey + '|');
    Look := Pattern.PieceLook(Piece);
    Builder.Append(BoolToStr(Look.Filled, True) + MaterialColorText(Look.Color) + IntToStr(Ord(Look.Fill)) + ' ');
    AddNumber(Look.HatchAngle);
    Builder.Append(IntToStr(MaterialIndexOf(Pattern, Piece)) + '|');
    for Index := 0 to High(Piece.MarkingMarks) do
    begin
      Mark := Piece.MarkingMarks[Index];
      Builder.Append(IntToStr(Ord(Mark.Kind)) + IntToStr(Ord(Mark.Role)) + IntToStr(Ord(Mark.Marker)) + ' ');
      Builder.Append(Piece.Markings[Index].EdgeKey + ' ');
      AddPoints(Mark.Line);
      AddPoints(Mark.Holes);
      AddPoints(Mark.Centres);
      AddNumber(Mark.HoleSize);
    end;
    for Index := 0 to Pattern.ObjectCount - 1 do
      if (Pattern.Objects[Index] is TSeamObject) and TSeamObject(Pattern.Objects[Index]).UsesPiece(Piece.Key) then
      begin
        Seam := TSeamObject(Pattern.Objects[Index]);
        Builder.Append('seam ' + Seam.Key + Seam.DisplayName + IntToStr(Ord(Seam.State)) + ' ');
        if Length(Seam.SideA) > 0 then
          Builder.Append(Seam.SideA[0].PieceKey + ':' + Seam.SideA[0].EdgeKey + ' ' + IntToStr(Length(Seam.SideA)) + ' ');
        if Length(Seam.SideB) > 0 then
          Builder.Append(Seam.SideB[0].PieceKey + ':' + Seam.SideB[0].EdgeKey + ' ' + IntToStr(Length(Seam.SideB)) + ' ');
      end;
    Result := Builder.ToString;
  finally
    FreeAndNil(Builder);
  end;
end;

constructor TGarmentBuilder.Create;
begin
  inherited Create;
  FEntries := TGarmentEntryMap.Create;
end;

destructor TGarmentBuilder.Destroy;
begin
  FreeAndNil(FEntries);
  inherited Destroy;
end;

procedure TGarmentBuilder.Clear;
begin
  FEntries.Clear;
end;

function TGarmentBuilder.Build(Pattern: TPattern): TGarmentScene;
var
  Index: integer;
  Piece: TPieceObject;
  Entry: TGarmentEntry;
  Print, Note: string;
  Kept: TGarmentEntryMap;
begin
  Result := Default(TGarmentScene);
  Result.Bounds := EmptyRect;
  FRebuilt := 0;
  Kept := TGarmentEntryMap.Create;
  try
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      if not (Pattern.Objects[Index] is TPieceObject) then
        Continue;
      Piece := TPieceObject(Pattern.Objects[Index]);
      if (Piece.State <> esValid) or (Length(Piece.Outline) < 3) then
      begin
        Insert(Format(rsGarmentPieceFails, [Piece.DisplayName]), Result.Notes, Length(Result.Notes));
        Continue;
      end;
      Print := Fingerprint(Pattern, Piece);
      if not FEntries.TryGetValue(Piece.Key, Entry) or (Entry.Fingerprint <> Print) then
      begin
        Entry.Fingerprint := Print;
        Entry.Piece := BuildGarmentPiece(Pattern, Piece, Entry.Notes);
        Inc(FRebuilt);
      end;
      Kept.AddOrSetValue(Piece.Key, Entry);
      Insert(Entry.Piece, Result.Pieces, Length(Result.Pieces));
      GrowRectBy(Result.Bounds, Entry.Piece.Bounds);
      for Note in Entry.Notes do
        Insert(Note, Result.Notes, Length(Result.Notes));
    end;
    // Pieces gone from the pattern go from the cache
    FEntries.Clear;
    for Print in Kept.Keys do
      FEntries.Add(Print, Kept[Print]);
  finally
    FreeAndNil(Kept);
  end;
end;

function BuildGarment(Pattern: TPattern): TGarmentScene;
var
  Builder: TGarmentBuilder;
begin
  Builder := TGarmentBuilder.Create;
  try
    Result := Builder.Build(Pattern);
  finally
    FreeAndNil(Builder);
  end;
end;

function GarmentOfMaterial(const Scene: TGarmentScene; MaterialIndex: integer): TGarmentScene;
var
  Piece: TGarmentPiece;
begin
  Result := Default(TGarmentScene);
  Result.Notes := Scene.Notes;
  Result.Bounds := EmptyRect;
  for Piece in Scene.Pieces do
    if (MaterialIndex < 0) or (Piece.MaterialIndex = MaterialIndex) then
    begin
      Insert(Piece, Result.Pieces, Length(Result.Pieces));
      GrowRectBy(Result.Bounds, Piece.Bounds);
    end;
end;

function GarmentShade(Across: double; Columns: boolean; const Light: TGarmentLight): double;
var
  Side, Depth, Lit, Flat, Elevation, Toward: double;
begin
  if not Light.Enabled then
    Exit(1);
  // The half cylinder's surface leans from -1 at one side to 1 at the other
  Side := EnsureRange(2 * Across - 1, -1, 1);
  Depth := Sqrt(1 - Side * Side);
  Elevation := DegToRad(LIGHT_ELEVATION);
  // The light's part along the shading direction: right for rows, down for
  // columns (y is down on screen, angles count up)
  if Columns then
    Toward := -Sin(DegToRad(Light.Angle)) * Cos(Elevation)
  else
    Toward := Cos(DegToRad(Light.Angle)) * Cos(Elevation);
  Lit := Max(0, Side * Toward + Depth * Sin(Elevation));
  Flat := Sin(Elevation);
  Result := (AMBIENT + (1 - AMBIENT) * Lit) / (AMBIENT + (1 - AMBIENT) * Flat);
  Result := 1 + EnsureRange(Light.Strength, 0, 1) * (Result - 1);
end;

function GarmentSpan(const Outline: TVec2Array; Columns: boolean; Coord: double; out Low, High: double): boolean;
var
  Index, Next: integer;
  SegmentStart, SegmentEnd: TVec2;
  AlongA, AlongB, AcrossA, AcrossB, Hit: double;
begin
  Low := Infinity;
  High := -Infinity;
  for Index := 0 to System.High(Outline) do
  begin
    Next := (Index + 1) mod Length(Outline);
    SegmentStart := Outline[Index];
    SegmentEnd := Outline[Next];
    if Columns then
    begin
      AlongA := SegmentStart.X;
      AlongB := SegmentEnd.X;
      AcrossA := SegmentStart.Y;
      AcrossB := SegmentEnd.Y;
    end
    else
    begin
      AlongA := SegmentStart.Y;
      AlongB := SegmentEnd.Y;
      AcrossA := SegmentStart.X;
      AcrossB := SegmentEnd.X;
    end;
    if (Coord < Min(AlongA, AlongB)) or (Coord > Max(AlongA, AlongB)) or (AlongA = AlongB) then
      Continue;
    Hit := AcrossA + (AcrossB - AcrossA) * (Coord - AlongA) / (AlongB - AlongA);
    Low := Min(Low, Hit);
    High := Max(High, Hit);
  end;
  Result := High > Low;
end;

procedure GarmentSpans(const Piece: TGarmentPiece; Start, Step: double; Count: integer; out Lows, Highs: TDoubleArray);
var
  RawLows, RawHighs, WideLows, WideHighs: TDoubleArray;
  Found: array of boolean;
  Index, Near, Reach, Taken: integer;
  Extent, SumLow, SumHigh: double;

  function ReachOf(Share: double): integer;
  begin
    Result := 0;
    if Abs(Step) > EPSILON then
      Result := Min(Round(Extent * Share / Abs(Step)), Count);
  end;

begin
  Lows := nil;
  Highs := nil;
  RawLows := nil;
  RawHighs := nil;
  WideLows := nil;
  WideHighs := nil;
  Found := nil;
  SetLength(Lows, Count);
  SetLength(Highs, Count);
  SetLength(RawLows, Count);
  SetLength(RawHighs, Count);
  SetLength(WideLows, Count);
  SetLength(WideHighs, Count);
  SetLength(Found, Count);
  for Index := 0 to Count - 1 do
    Found[Index] := GarmentSpan(Piece.Outline, Piece.ShadeColumns, Start + Index * Step, RawLows[Index], RawHighs[Index]);
  if Piece.ShadeColumns then
    Extent := Piece.Bounds.MaxX - Piece.Bounds.MinX
  else
    Extent := Piece.Bounds.MaxY - Piece.Bounds.MinY;
  Reach := ReachOf(SPAN_ENVELOPE);
  for Index := 0 to Count - 1 do
  begin
    WideLows[Index] := RawLows[Index];
    WideHighs[Index] := RawHighs[Index];
    if not Found[Index] then
      Continue;
    for Near := Max(0, Index - Reach) to Min(Count - 1, Index + Reach) do
      if Found[Near] then
      begin
        WideLows[Index] := Min(WideLows[Index], RawLows[Near]);
        WideHighs[Index] := Max(WideHighs[Index], RawHighs[Near]);
      end;
  end;
  Reach := ReachOf(SPAN_SMOOTHING);
  for Index := 0 to Count - 1 do
  begin
    Lows[Index] := 1;
    Highs[Index] := 0;
    if not Found[Index] then
      Continue;
    SumLow := 0;
    SumHigh := 0;
    Taken := 0;
    for Near := Max(0, Index - Reach) to Min(Count - 1, Index + Reach) do
      if Found[Near] then
      begin
        SumLow := SumLow + WideLows[Near];
        SumHigh := SumHigh + WideHighs[Near];
        Inc(Taken);
      end;
    Lows[Index] := SumLow / Taken;
    Highs[Index] := SumHigh / Taken;
  end;
end;

function GarmentInward(const Outline: TVec2Array; const SegmentStart, SegmentEnd: TVec2): TVec2;
var
  Direction, Left: TVec2;
begin
  Direction := SegmentEnd - SegmentStart;
  if Direction.Length < EPSILON then
    Exit(Vec2(0, 0));
  Direction := Direction * (1 / Direction.Length);
  Left := LeftOf(Direction);
  if PointInPolygon(Lerp(SegmentStart, SegmentEnd, 0.5) + Left * SIDE_STEP, Outline) then
    Result := Left
  else
    Result := -Left;
end;

function GarmentEdgeFacing(const Outline: TVec2Array; const SegmentStart, SegmentEnd: TVec2; const Light: TGarmentLight): double;
var
  Outward, Toward: TVec2;
begin
  Outward := -GarmentInward(Outline, SegmentStart, SegmentEnd);
  // Towards the light, on screen: y down
  Toward := Vec2(Cos(DegToRad(Light.Angle)), -Sin(DegToRad(Light.Angle)));
  Result := Dot(Outward, Toward);
end;

function GarmentInset(const Outline, Points: TVec2Array; Inset: double): TVec2Array;
var
  Index: integer;
  Normal: TVec2;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
  begin
    Normal := Vec2(0, 0);
    if Index > 0 then
      Normal := Normal + GarmentInward(Outline, Points[Index - 1], Points[Index]);
    if Index < High(Points) then
      Normal := Normal + GarmentInward(Outline, Points[Index], Points[Index + 1]);
    if Normal.Length > EPSILON then
      Normal := Normal * (1 / Normal.Length);
    Result[Index] := Points[Index] + Normal * Inset;
  end;
end;

function GarmentLineFacing(const Outline, Points: TVec2Array; const Light: TGarmentLight): double;
var
  Index: integer;
  Total, Run: double;
begin
  Result := 0;
  Total := 0;
  for Index := 1 to High(Points) do
  begin
    Run := Distance(Points[Index - 1], Points[Index]);
    Result := Result + Run * GarmentEdgeFacing(Outline, Points[Index - 1], Points[Index], Light);
    Total := Total + Run;
  end;
  if Total > EPSILON then
    Result := Result / Total;
end;

function GarmentBaseColor(const Look: TPieceLook): TMaterialColor;
begin
  if not Look.Filled then
    Result := UNFILLED_COLOR
  else if Look.Fill = ffHatch then
    Result := MaterialTint(Look.Color)
  else
    Result := Look.Color;
end;

function ShadedColor(const Color: TMaterialColor; Shade: double): TMaterialColor;
begin
  Result.Red := EnsureRange(Round(Color.Red * Shade), 0, 255);
  Result.Green := EnsureRange(Round(Color.Green * Shade), 0, 255);
  Result.Blue := EnsureRange(Round(Color.Blue * Shade), 0, 255);
end;

function GarmentPieceAt(const Scene: TGarmentScene; const Position: TVec2): integer;
begin
  for Result := High(Scene.Pieces) downto 0 do
    if PointInPolygon(Position, Scene.Pieces[Result].Outline) then
      Exit;
  Result := -1;
end;

end.
