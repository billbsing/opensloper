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

// Pieces: a closed path of edge references with a seam allowance. Only the
// references and formulas are stored, so a piece follows every change to its
// edges; its outline and cutting line are computed. No LCL dependency.
unit Sloper.Core.Piece;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.SeamAllowance;

const
  // The formula field of the seam allowance, and its member in pattern files
  PieceAllowanceField = 'allowance';
  DefaultPieceAllowance = '10';
  GrainAngleField = 'grainline.angle';
  DefaultGrainAngle = '90';
  // A point this close (in mm) to a piece's seam line can carry a notch
  NotchPointTolerance = 0.05;
  // Ends of neighbouring edges this close (in mm) count as joined, so formula
  // rounding cannot open a piece
  PieceJoinTolerance = 0.01;

type
  TPieceEdge = record
    EdgeKey: string;
    // True when the path runs along the edge from its end to its start
    Reversed: boolean;
  end;

  TPiecePath = array of TPieceEdge;

  // gkAngle lays the grainline through the piece's middle at a formula angle;
  // gkPoints runs it between two points
  TGrainKind = (gkNone, gkAngle, gkPoints);

  // On a point, or at the formula "notchN.position": mm from the edge's start
  TPieceNotch = record
    PointKey, EdgeKey: string;
  end;

  TPieceNotchArray = array of TPieceNotch;

  // A notch as cut: from the cutting line in towards the seam line
  TNotchMark = record
    Seam, Cut, Tip: TVec2;
  end;

  TNotchMarkArray = array of TNotchMark;
  TLine2Array = array of TLine2;

  // The default seam allowance is the field "allowance"; an edge with its own
  // has a field such as "edge2.allowance", which exists only while it does
  TPieceObject = class(TDraftObject)
  private
    FPath: TPiecePath;
    FOutline: TVec2Array;
    FCutLine: TVec2Array;
    FGrainKind: TGrainKind;
    FGrainStartKey, FGrainEndKey: string;
    FGrainline: TLine2;
    FNotches: TPieceNotchArray;
    FNotchMarks: TNotchMarkArray;
    FCutCount: integer;
    FMirrored: boolean;
    FFoldEdgeKey: string;
    FFoldLine: TLine2;
    FFoldInwards: double;
    function BuildOutline(Context: TEvalContext; DefaultWidth: double; out Outline: TVec2Array; out Widths, EdgeWidths: TDoubleArray): TEvalState;
    function ComputeGrainline(Context: TEvalContext; const Points: TVec2Array; out Line: TLine2): TEvalState;
    function ComputeNotch(Context: TEvalContext; Index: integer; const EdgeWidths: TDoubleArray; Anticlockwise: boolean;
      out Mark: TNotchMark): TEvalState;
    procedure ComputeFold(Context: TEvalContext; Anticlockwise: boolean; out Line: TLine2; out Inwards: double);
    function OutwardAngle(Edge: TEdgeObject; PathIndex: integer; Position: double; Anticlockwise: boolean): double;
    function LocateNotch(Context: TEvalContext; Index: integer; out PathIndex: integer; out Position: double): TEvalState;
  public
    constructor Create(const AKey: string; const APath: TPiecePath);
    function InputKeys: TStringArray; override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    // Index in the path of the edge with this key, or -1
    function PathIndexOf(const EdgeKey: string): integer;
    function OverrideField(PathIndex: integer): string;
    function HasOverride(PathIndex: integer): boolean;
    procedure AddOverride(PathIndex: integer);
    procedure RemoveOverride(PathIndex: integer);
    // Clears the old grainline's field, if any. gkAngle adds its field;
    // gkPoints takes the two point keys.
    procedure SetGrainKind(AKind: TGrainKind; const AStartKey: string = ''; const AEndKey: string = '');
    // A new notch's index. An edge notch has the field NotchField(Index).
    function AddNotch(const APointKey, AEdgeKey: string): integer;
    procedure RemoveNotch(Index: integer);
    function NotchField(Index: integer): string;
    function Area: double;
    function Perimeter: double;
    // The middle of the outline's extent
    function Middle: TVec2;
    // The grainline's shaft and the strokes of an arrowhead at each end
    function GrainArrow: TLine2Array;
    // The fold line's bracket: a line in from the fold with an arrow down to
    // it at each end. Empty when the piece is not cut on a fold.
    function FoldArrow: TLine2Array;
    // The name with how to cut it: "Front, cut 2 mirrored"
    function CutCaption: string;
    property Path: TPiecePath read FPath;
    // Last good seam line, closed without repeating its first point
    property Outline: TVec2Array read FOutline;
    // Last good cutting line, clockwise, closed without repeating its first point
    property CutLine: TVec2Array read FCutLine;
    property GrainKind: TGrainKind read FGrainKind;
    property GrainStartKey: string read FGrainStartKey;
    property GrainEndKey: string read FGrainEndKey;
    // Last good grainline
    property Grainline: TLine2 read FGrainline;
    property Notches: TPieceNotchArray read FNotches;
    // Last good marks, one per notch
    property NotchMarks: TNotchMarkArray read FNotchMarks;
    // How many to cut, at least 1
    property CutCount: integer read FCutCount write FCutCount;
    // Copies after the first are cut mirrored, as a left and a right
    property Mirrored: boolean read FMirrored write FMirrored;
    // The edge the piece is cut on the fold along, or '' when none. It has no
    // seam allowance, whatever its allowance says.
    property FoldEdgeKey: string read FFoldEdgeKey write FFoldEdgeKey;
    function OnFold: boolean;
  end;

resourcestring
  rsPieceGap = 'There is a gap between %s and %s';
  rsPieceNoArea = 'The outline encloses no area';
  rsPieceNegativeAllowance = 'A seam allowance cannot be negative';
  rsPieceNoCutLine = 'No cutting line could be worked out';
  rsPieceGrainSamePlace = 'The grainline starts and ends at the same place';
  rsPieceNotchOffPiece = 'The notch at %s is not on the seam line';
  rsPieceNotchPastEnd = 'The notch at %s mm is off %s (%s mm long)';
  rsPieceCaption = '%s, cut %d';
  rsPieceCaptionMirrored = '%s, cut %d mirrored';
  rsPieceCaptionFold = '%s, cut %d on fold';

implementation

uses
  Math, Sloper.Core.Bezier;

const
  // Share of the piece's span along its grain that the arrow covers
  GrainShare = 0.6;
  GrainHeadLength = 10;
  GrainHeadSpread = 155;
  NotchLength = 6;
  FoldDepth = 20;
  FoldInset = 0.15;
  FoldHeadLength = 8;
  FoldHeadWidth = 25;

constructor TPieceObject.Create(const AKey: string; const APath: TPiecePath);
begin
  inherited Create(AKey);
  FPath := Copy(APath);
  AddField(PieceAllowanceField);
  FCutCount := 1;
end;

function TPieceObject.InputKeys: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FPath));
  for Index := 0 to High(FPath) do
    Result[Index] := FPath[Index].EdgeKey;
  if FGrainKind = gkPoints then
  begin
    System.Insert(FGrainStartKey, Result, Length(Result));
    System.Insert(FGrainEndKey, Result, Length(Result));
  end;
  for Index := 0 to High(FNotches) do
    if FNotches[Index].PointKey <> '' then
      System.Insert(FNotches[Index].PointKey, Result, Length(Result));
end;

function TPieceObject.TypeName: string;
begin
  Result := 'piece';
end;

function TPieceObject.HasProperty(const Prop: string): boolean;
begin
  Result := False;
end;

function TPieceObject.PropertyValue(const Prop: string): double;
begin
  Result := 0;
end;

function TPieceObject.PathIndexOf(const EdgeKey: string): integer;
begin
  for Result := 0 to High(FPath) do
    if FPath[Result].EdgeKey = EdgeKey then
      Exit;
  Result := -1;
end;

function TPieceObject.OverrideField(PathIndex: integer): string;
begin
  Result := 'edge' + IntToStr(PathIndex + 1) + '.' + PieceAllowanceField;
end;

function TPieceObject.HasOverride(PathIndex: integer): boolean;
begin
  Result := Field(OverrideField(PathIndex)) <> nil;
end;

procedure TPieceObject.AddOverride(PathIndex: integer);
begin
  if not HasOverride(PathIndex) then
    AddField(OverrideField(PathIndex));
end;

procedure TPieceObject.RemoveOverride(PathIndex: integer);
begin
  RemoveField(OverrideField(PathIndex));
end;

procedure TPieceObject.SetGrainKind(AKind: TGrainKind; const AStartKey, AEndKey: string);
begin
  if FGrainKind = gkAngle then
    RemoveField(GrainAngleField);
  FGrainKind := AKind;
  FGrainStartKey := AStartKey;
  FGrainEndKey := AEndKey;
  if AKind = gkAngle then
    AddField(GrainAngleField);
end;

function TPieceObject.NotchField(Index: integer): string;
begin
  Result := 'notch' + IntToStr(Index + 1) + '.position';
end;

function TPieceObject.AddNotch(const APointKey, AEdgeKey: string): integer;
begin
  Result := Length(FNotches);
  SetLength(FNotches, Result + 1);
  FNotches[Result].PointKey := APointKey;
  FNotches[Result].EdgeKey := AEdgeKey;
  if AEdgeKey <> '' then
    AddField(NotchField(Result));
end;

procedure TPieceObject.RemoveNotch(Index: integer);
var
  Later: integer;
begin
  if FNotches[Index].EdgeKey <> '' then
    RemoveField(NotchField(Index));
  // Fields are named by place in the list, so later ones move down
  for Later := Index + 1 to High(FNotches) do
    if FNotches[Later].EdgeKey <> '' then
      RenameField(NotchField(Later), NotchField(Later - 1));
  System.Delete(FNotches, Index, 1);
  if Index <= High(FNotchMarks) then
    System.Delete(FNotchMarks, Index, 1);
end;

function ReversedPoints(const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Points[High(Points) - Index];
end;

function TPieceObject.BuildOutline(Context: TEvalContext; DefaultWidth: double; out Outline: TVec2Array;
  out Widths, EdgeWidths: TDoubleArray): TEvalState;
var
  Index, Added, PointIndex: integer;
  Node: TEvalNode;
  First, Previous: TEdgeObject;
  Points: TVec2Array;
  LastEnd: TVec2;
  Width: double;
begin
  Outline := nil;
  Widths := nil;
  EdgeWidths := nil;
  SetLength(EdgeWidths, Length(FPath));
  First := nil;
  Previous := nil;
  LastEnd := Vec2(0, 0);
  for Index := 0 to High(FPath) do
  begin
    Node := Context.FindNode(FPath[Index].EdgeKey);
    if not (Node is TEdgeObject) then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [FPath[Index].EdgeKey])));
    Width := DefaultWidth;
    if HasOverride(Index) and not EvalField(Context, OverrideField(Index), Width) then
      Exit(esError);
    if Width < 0 then
      Exit(Fail(esInvalid, rsPieceNegativeAllowance));
    if FPath[Index].EdgeKey = FFoldEdgeKey then
      Width := 0;
    EdgeWidths[Index] := Width;
    Points := TEdgeObject(Node).Flatten(CoarseFlatness);
    if FPath[Index].Reversed then
      Points := ReversedPoints(Points);
    if (Previous <> nil) and not PointsNear(LastEnd, Points[0], PieceJoinTolerance) then
      Exit(Fail(esInvalid, Format(rsPieceGap, [Previous.DisplayName, Node.DisplayName])));
    // Each point of the edge but its last starts a segment of this width
    Added := Length(Outline);
    SetLength(Outline, Added + High(Points));
    SetLength(Widths, Added + High(Points));
    for PointIndex := 0 to High(Points) - 1 do
    begin
      Outline[Added + PointIndex] := Points[PointIndex];
      Widths[Added + PointIndex] := Width;
    end;
    LastEnd := Points[High(Points)];
    Previous := TEdgeObject(Node);
    if First = nil then
      First := Previous;
  end;
  if not PointsNear(LastEnd, Outline[0], PieceJoinTolerance) then
    Exit(Fail(esInvalid, Format(rsPieceGap, [Previous.DisplayName, First.DisplayName])));
  Result := esValid;
end;

function ExtentMiddle(const Points: TVec2Array): TVec2;
var
  P: TVec2;
  MinX, MinY, MaxX, MaxY: double;
begin
  MinX := Infinity;
  MinY := Infinity;
  MaxX := -Infinity;
  MaxY := -Infinity;
  for P in Points do
  begin
    MinX := Min(MinX, P.X);
    MinY := Min(MinY, P.Y);
    MaxX := Max(MaxX, P.X);
    MaxY := Max(MaxY, P.Y);
  end;
  Result := Vec2((MinX + MaxX) / 2, (MinY + MaxY) / 2);
end;

function TPieceObject.ComputeGrainline(Context: TEvalContext; const Points: TVec2Array; out Line: TLine2): TEvalState;
var
  Angle, Along, Lowest, Highest: double;
  Centre, Direction, P: TVec2;
  StartNode, EndNode: TEvalNode;
begin
  Line := FGrainline;
  case FGrainKind of
    gkAngle:
    begin
      if not EvalField(Context, GrainAngleField, Angle) then
        Exit(esError);
      Centre := ExtentMiddle(Points);
      Direction := PolarPoint(Vec2(0, 0), 1, Angle);
      Lowest := Infinity;
      Highest := -Infinity;
      for P in Points do
      begin
        Along := Dot(P - Centre, Direction);
        Lowest := Min(Lowest, Along);
        Highest := Max(Highest, Along);
      end;
      Centre := Centre + Direction * ((Lowest + Highest) / 2);
      Along := (Highest - Lowest) * GrainShare / 2;
      Line := Line2(Centre - Direction * Along, Centre + Direction * Along);
    end;
    gkPoints:
    begin
      StartNode := Context.FindNode(FGrainStartKey);
      EndNode := Context.FindNode(FGrainEndKey);
      if not (StartNode is TPointObject) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [FGrainStartKey])));
      if not (EndNode is TPointObject) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [FGrainEndKey])));
      Line := Line2(TPointObject(StartNode).Position, TPointObject(EndNode).Position);
      if PointsNear(Line.P1, Line.P2) then
        Exit(Fail(esInvalid, rsPieceGrainSamePlace));
    end;
  end;
  Result := esValid;
end;

// Where a notch falls: which edge of the path, and how far along it
function TPieceObject.LocateNotch(Context: TEvalContext; Index: integer; out PathIndex: integer; out Position: double): TEvalState;
var
  Notch: TPieceNotch;
  Node: TEvalNode;
  Edge: TEdgeObject;
  Entry: integer;
  Spot: TVec2;
  Along, Gap, Best: double;
begin
  Notch := FNotches[Index];
  PathIndex := -1;
  Position := 0;
  if Notch.EdgeKey <> '' then
  begin
    PathIndex := PathIndexOf(Notch.EdgeKey);
    if PathIndex < 0 then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [Notch.EdgeKey])));
    Edge := TEdgeObject(Context.FindNode(Notch.EdgeKey));
    if not EvalField(Context, NotchField(Index), Position) then
      Exit(esError);
    if (Position < -DefaultTolerance) or (Position > Edge.Length + DefaultTolerance) then
      Exit(Fail(esInvalid, Format(rsPieceNotchPastEnd, [FormatFloat('0.#', Position), Edge.DisplayName, FormatFloat('0.#', Edge.Length)])));
    Exit(esValid);
  end;
  Node := Context.FindNode(Notch.PointKey);
  if not (Node is TPointObject) then
    Exit(Fail(esError, Format(rsDraftNotAPoint, [Notch.PointKey])));
  Spot := TPointObject(Node).Position;
  Best := NotchPointTolerance;
  for Entry := 0 to High(FPath) do
  begin
    TEdgeObject(Context.FindNode(FPath[Entry].EdgeKey)).Locate(Spot, Along, Gap);
    if Gap <= Best then
    begin
      Best := Gap;
      PathIndex := Entry;
      Position := Along;
    end;
  end;
  if PathIndex < 0 then
    Exit(Fail(esInvalid, Format(rsPieceNotchOffPiece, [Node.DisplayName])));
  Result := esValid;
end;

// Outside is left of the way a clockwise path runs
function TPieceObject.OutwardAngle(Edge: TEdgeObject; PathIndex: integer; Position: double; Anticlockwise: boolean): double;
begin
  Result := Edge.DirectionAt(Position);
  if FPath[PathIndex].Reversed then
    Result := Result + 180;
  if Anticlockwise then
    Result := Result - 90
  else
    Result := Result + 90;
end;

procedure TPieceObject.ComputeFold(Context: TEvalContext; Anticlockwise: boolean; out Line: TLine2; out Inwards: double);
var
  Edge: TEdgeObject;
begin
  Line := FFoldLine;
  Inwards := FFoldInwards;
  if FFoldEdgeKey = '' then
    Exit;
  Edge := TEdgeObject(Context.FindNode(FFoldEdgeKey));
  Line := Line2(Edge.PointAtLength(0), Edge.PointAtLength(Edge.Length));
  Inwards := OutwardAngle(Edge, PathIndexOf(FFoldEdgeKey), Edge.Length / 2, Anticlockwise) + 180;
end;

function TPieceObject.ComputeNotch(Context: TEvalContext; Index: integer; const EdgeWidths: TDoubleArray;
  Anticlockwise: boolean; out Mark: TNotchMark): TEvalState;
var
  PathIndex: integer;
  Position, Outwards: double;
  Edge: TEdgeObject;
begin
  Mark := Default(TNotchMark);
  Result := LocateNotch(Context, Index, PathIndex, Position);
  if Result <> esValid then
    Exit;
  Edge := TEdgeObject(Context.FindNode(FPath[PathIndex].EdgeKey));
  Outwards := OutwardAngle(Edge, PathIndex, Position, Anticlockwise);
  Mark.Seam := Edge.PointAtLength(Position);
  Mark.Cut := PolarPoint(Mark.Seam, EdgeWidths[PathIndex], Outwards);
  Mark.Tip := PolarPoint(Mark.Cut, NotchLength, Outwards + 180);
end;

function TPieceObject.Compute(Context: TEvalContext): TEvalState;
var
  Width: double;
  Points, Cut: TVec2Array;
  Widths, EdgeWidths: TDoubleArray;
  Line: TLine2;
  Marks: TNotchMarkArray;
  Index: integer;
  FoldLine: TLine2;
  FoldInwards: double;
begin
  if not EvalField(Context, PieceAllowanceField, Width) then
    Exit(esError);
  if Width < 0 then
    Exit(Fail(esInvalid, rsPieceNegativeAllowance));
  Result := BuildOutline(Context, Width, Points, Widths, EdgeWidths);
  if Result <> esValid then
    Exit;
  if Abs(SignedArea(Points)) < PieceJoinTolerance then
    Exit(Fail(esInvalid, rsPieceNoArea));
  if not OffsetOutline(Points, Widths, Cut) then
    Exit(Fail(esInvalid, rsPieceNoCutLine));
  Result := ComputeGrainline(Context, Points, Line);
  if Result <> esValid then
    Exit;
  Marks := nil;
  SetLength(Marks, Length(FNotches));
  for Index := 0 to High(FNotches) do
  begin
    Result := ComputeNotch(Context, Index, EdgeWidths, SignedArea(Points) > 0, Marks[Index]);
    if Result <> esValid then
      Exit;
  end;
  ComputeFold(Context, SignedArea(Points) > 0, FoldLine, FoldInwards);
  FOutline := Points;
  FCutLine := Cut;
  FGrainline := Line;
  FNotchMarks := Marks;
  FFoldLine := FoldLine;
  FFoldInwards := FoldInwards;
end;

function TPieceObject.Area: double;
begin
  Result := Abs(SignedArea(FOutline));
end;

function TPieceObject.Perimeter: double;
begin
  Result := 0;
  if FOutline <> nil then
    Result := PolylineLength(FOutline) + Distance(FOutline[High(FOutline)], FOutline[0]);
end;

function TPieceObject.Middle: TVec2;
begin
  Result := ExtentMiddle(FOutline);
end;

function TPieceObject.OnFold: boolean;
begin
  Result := FFoldEdgeKey <> '';
end;

function TPieceObject.CutCaption: string;
begin
  if OnFold then
    Result := Format(rsPieceCaptionFold, [DisplayName, FCutCount])
  else if FMirrored and (FCutCount > 1) then
    Result := Format(rsPieceCaptionMirrored, [DisplayName, FCutCount])
  else
    Result := Format(rsPieceCaption, [DisplayName, FCutCount]);
end;

function TPieceObject.FoldArrow: TLine2Array;
var
  Near1, Near2, Far1, Far2: TVec2;

  procedure AddStroke(const From, Target: TVec2);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Line2(From, Target);
  end;

  procedure AddHead(const Tip: TVec2);
  begin
    AddStroke(Tip, PolarPoint(Tip, FoldHeadLength, FFoldInwards + FoldHeadWidth));
    AddStroke(Tip, PolarPoint(Tip, FoldHeadLength, FFoldInwards - FoldHeadWidth));
  end;

begin
  Result := nil;
  if not OnFold then
    Exit;
  Near1 := FFoldLine.PointAt(FoldInset);
  Near2 := FFoldLine.PointAt(1 - FoldInset);
  Far1 := PolarPoint(Near1, FoldDepth, FFoldInwards);
  Far2 := PolarPoint(Near2, FoldDepth, FFoldInwards);
  AddStroke(Far1, Far2);
  AddStroke(Far1, Near1);
  AddStroke(Far2, Near2);
  AddHead(Near1);
  AddHead(Near2);
end;

function TPieceObject.GrainArrow: TLine2Array;
var
  Angle: double;

  procedure AddStroke(const From, Target: TVec2);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Line2(From, Target);
  end;

begin
  Result := nil;
  if FGrainKind = gkNone then
    Exit;
  Angle := FGrainline.Angle;
  AddStroke(FGrainline.P1, FGrainline.P2);
  AddStroke(FGrainline.P2, PolarPoint(FGrainline.P2, GrainHeadLength, Angle + GrainHeadSpread));
  AddStroke(FGrainline.P2, PolarPoint(FGrainline.P2, GrainHeadLength, Angle - GrainHeadSpread));
  AddStroke(FGrainline.P1, PolarPoint(FGrainline.P1, GrainHeadLength, Angle + GrainHeadSpread + 180));
  AddStroke(FGrainline.P1, PolarPoint(FGrainline.P1, GrainHeadLength, Angle - GrainHeadSpread + 180));
end;

end.
