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

// Draft objects: points placed by operations, and the edges between them.
// Each is an evaluator node; only its definition (operation, inputs,
// formulas) is stored, and its geometry is computed. No LCL dependency.
unit Sloper.Core.Draft;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Bezier;

type
  TEdgeRole = (erConstruction, erOutline);
  TOffsetMode = (omPolar, omCartesian);
  TAlongMode = (amLength, amRatio);
  TProjectDirection = (pdPerpendicular, pdAngle);

  TSegmentKind = (skLine, skCurve);

  // One straight or curved stretch of an edge's computed geometry
  TEdgeSegment = record
    Kind: TSegmentKind;
    Line: TLine2;
    Curve: TCubicBezier;
  end;

  TEdgeSegmentArray = array of TEdgeSegment;

  TEdgePieceKind = (epLine, epCurve);

  // Part of an edge, for finding crossings. A line piece covers
  // Line.PointAt(T) for TMin <= T <= TMax (infinite for an extended line);
  // its position along the edge is PosBase + PosScale * T. A curve piece is
  // a whole curve segment; its position is PosBase plus the arc length along it.
  TEdgePiece = record
    Kind: TEdgePieceKind;
    Line: TLine2;
    TMin, TMax: double;
    PosBase, PosScale: double;
    Curve: TCubicBezier;
  end;

  TEdgePieceArray = array of TEdgePiece;

  // A crossing on an edge; Position is its distance along the edge in mm,
  // negative before the start of an extended edge
  TEdgeCrossing = record
    Point: TVec2;
    Position: double;
  end;

  TEdgeCrossingArray = array of TEdgeCrossing;

  TDraftObject = class(TEvalNode)
  private
    FName: string;
  public
    function DisplayName: string; override;
    function TypeName: string; virtual; abstract;
    // Readable properties in formulas, such as x or length (lower case)
    function HasProperty(const Prop: string): boolean; virtual; abstract;
    // Value of a property from the last good result
    function PropertyValue(const Prop: string): double; virtual; abstract;
    property Name: string read FName write FName;
  end;

  TPointObject = class(TDraftObject)
  protected
    FPosition: TVec2;
    // Position of the point with the given key; False with Message set if
    // it is not a point
    function InputPoint(Context: TEvalContext; const AKey: string; out APosition: TVec2): boolean;
  public
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    // Last good position
    property Position: TVec2 read FPosition;
  end;

  // A point at fixed coordinates, given by formulas x and y
  TFreePoint = class(TPointObject)
  public
    constructor Create(const AKey: string);
    function Compute(Context: TEvalContext): TEvalState; override;
  end;

  // A point offset from Base by length and angle (polar), or dx and dy
  TOffsetPoint = class(TPointObject)
  private
    FBase: string;
    FMode: TOffsetMode;
  public
    constructor Create(const AKey, ABase: string; AMode: TOffsetMode);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Base: string read FBase;
    property Mode: TOffsetMode read FMode;
  end;

  // A point along a line or curve: a distance or ratio from its start or end
  TAlongEdgePoint = class(TPointObject)
  private
    FEdge: string;
    FFromEnd: boolean;
    FMode: TAlongMode;
  public
    constructor Create(const AKey, AEdge: string; AFromEnd: boolean; AMode: TAlongMode);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Edge: string read FEdge;
    property FromEnd: boolean read FFromEnd;
    property Mode: TAlongMode read FMode;
  end;

  // Lines, curves, curve paths and split parts. Each keeps its computed
  // geometry as segments, so length, positions along it and crossings work
  // the same for every kind of edge.
  TEdgeObject = class(TDraftObject)
  private
    FStartKey, FEndKey: string;
  protected
    // Last good geometry
    FSegments: TEdgeSegmentArray;
  public
    Role: TEdgeRole;
    // The name follows the endpoints (Line_A_B) until the user renames it
    NameIsDerived: boolean;
    constructor Create(const AKey, AStart, AEnd: string);
    function InputKeys: TStringArray; override;
    // Every edge has length, angle1 (direction of its start handle) and
    // angle2 (direction of its end handle, pointing back along the edge)
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Length: double;
    function PointAtLength(ADistance: double): TVec2;
    // Direction of travel where the edge starts and where it ends
    function StartDirection: double;
    function EndDirection: double;
    // The edge as pieces; an extended edge continues along its end tangents
    function Pieces(Extend: boolean): TEdgePieceArray;
    // Nearest point on the edge to APoint: its distance from APoint and its
    // position along the edge
    function Locate(const APoint: TVec2; out Position, Offset: double): TVec2;
    // The geometry before and after Position (mm along the edge)
    procedure SplitAt(Position: double; out First, Second: TEdgeSegmentArray);
    // Prefix for derived names: Line, Curve or Path
    function NamePrefix: string; virtual; abstract;
    property StartKey: string read FStartKey;
    property EndKey: string read FEndKey;
    property Segments: TEdgeSegmentArray read FSegments;
  end;

  TLineObject = class(TEdgeObject)
  private
    function GetLine: TLine2;
  public
    function TypeName: string; override;
    function NamePrefix: string; override;
    // Lines also have angle, their direction
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Line: TLine2 read GetLine;
  end;

  // Cubic Bézier between two points; handles given by angle1/length1 at the
  // start and angle2/length2 at the end
  TCurveObject = class(TEdgeObject)
  private
    function GetCurve: TCubicBezier;
  public
    constructor Create(const AKey, AStart, AEnd: string);
    function TypeName: string; override;
    function NamePrefix: string; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Curve: TCubicBezier read GetCurve;
  end;

  // A smooth curve through several points (armholes, necklines). Each node
  // has a tangent angle, the direction of travel there, shared by the
  // segments either side so the joins are smooth; and handle lengths before
  // (lengthIn) and after (lengthOut) it. Fields are node1.angle,
  // node1.lengthOut, node2.lengthIn, node2.angle and so on; the first node
  // has no lengthIn and the last no lengthOut.
  TCurvePathObject = class(TEdgeObject)
  private
    FNodeKeys: TStringArray;
  public
    constructor Create(const AKey: string; const ANodeKeys: array of string);
    function InputKeys: TStringArray; override;
    function TypeName: string; override;
    function NamePrefix: string; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property NodeKeys: TStringArray read FNodeKeys;
  end;

  // One side of an edge split at a point: Part 1 runs from the edge's start
  // to the point, Part 2 from the point to the edge's end. Follows the edge
  // and the point as they change.
  TSplitPart = class(TEdgeObject)
  private
    FSource, FPoint: string;
    FPart: integer;
    FStraight: boolean;
    FPrefix: string;
  public
    // AStraight and APrefix come from the source edge: a part of a line is
    // straight and has the angle property
    constructor Create(const AKey, ASource, APoint: string; APart: integer;
      const ASourceStart, ASourceEnd: string; AStraight: boolean; const APrefix: string);
    function InputKeys: TStringArray; override;
    function TypeName: string; override;
    function NamePrefix: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Source: string read FSource;
    property Point: string read FPoint;
    property Part: integer read FPart;
    property Straight: boolean read FStraight;
  end;

  // Where two edges cross. Pick numbers the crossings from 1 along EdgeA.
  TIntersectPoint = class(TPointObject)
  private
    FEdgeA, FEdgeB: string;
    FExtendA, FExtendB: boolean;
    FPick: integer;
  public
    constructor Create(const AKey, AEdgeA, AEdgeB: string; AExtendA, AExtendB: boolean;
      APick: integer);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property EdgeA: string read FEdgeA;
    property EdgeB: string read FEdgeB;
    property ExtendA: boolean read FExtendA;
    property ExtendB: boolean read FExtendB;
    property Pick: integer read FPick;
  end;

  // Where a circle around Centre, with the radius formula, crosses an edge;
  // a compass step. Pick numbers the crossings from 1 along the edge.
  TCircleEdgePoint = class(TPointObject)
  private
    FCentre, FEdge: string;
    FExtend: boolean;
    FPick: integer;
  public
    constructor Create(const AKey, ACentre, AEdge: string; AExtend: boolean; APick: integer);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Centre: string read FCentre;
    property Edge: string read FEdge;
    property Extend: boolean read FExtend;
    property Pick: integer read FPick;
  end;

  // From a point onto an edge: the foot of the perpendicular, or along a
  // line at the angle formula. The nearest result to the point is used.
  TProjectPoint = class(TPointObject)
  private
    FSource, FEdge: string;
    FDirection: TProjectDirection;
    FExtend: boolean;
  public
    constructor Create(const AKey, ASource, AEdge: string; ADirection: TProjectDirection;
      AExtend: boolean);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Source: string read FSource;
    property Edge: string read FEdge;
    property Direction: TProjectDirection read FDirection;
    property Extend: boolean read FExtend;
  end;

// True for a line, or a part of one: straight, with the angle property
function IsStraightEdge(Edge: TEdgeObject): boolean;
// Part 1 or 2 of Source split at the point with key APoint
function NewSplitPart(const AKey: string; Source: TEdgeObject; const APoint: string; APart: integer): TSplitPart;

// Crossings of two lists of pieces, in order along the first, with repeats merged
function CrossPieces(const PiecesA, PiecesB: TEdgePieceArray): TEdgeCrossingArray;
// Crossings of two edges, in order along A, with repeats merged
function CrossEdges(EdgeA: TEdgeObject; ExtendA: boolean; EdgeB: TEdgeObject;
  ExtendB: boolean): TEdgeCrossingArray;
// Crossings of a circle with an edge, in order along the edge
function CrossCircleEdge(const Centre: TVec2; Radius: double; Edge: TEdgeObject;
  Extend: boolean): TEdgeCrossingArray;

resourcestring
  rsDraftNotAPoint = '%s is not a point';
  rsDraftNotAnEdge = '%s is not a line or curve';
  rsDraftSamePlace = 'The start and end are at the same place';
  rsDraftPastEnd = 'The distance %s mm is past the end of %s (%s mm long)';
  rsDraftRatioRange = 'The ratio %s is outside 0 to 1';
  rsDraftNegativeHandle = 'A handle length cannot be negative';
  rsDraftNoCrossing = '%s and %s do not cross';
  rsDraftPickMissing = 'There are only %d crossings, so crossing %d does not exist';
  rsDraftCircleMisses = 'The circle does not reach %s';
  rsDraftNegativeRadius = 'The radius cannot be negative';
  rsDraftNoFoot = 'No perpendicular from %s meets %s';
  rsDraftNoProjection = 'A line from %s at %s° does not meet %s';
  rsDraftNotOnEdge = '%s is not on %s';
  rsDraftSplitAtEnd = '%s is at an end of %s, so there is nothing to split';

implementation

uses
  Math;

function FormatMM(Millimetres: double): string;
begin
  Result := FormatFloat('0.#', Millimetres);
end;

{ TDraftObject }

function TDraftObject.DisplayName: string;
begin
  Result := FName;
end;

{ TPointObject }

function TPointObject.InputPoint(Context: TEvalContext; const AKey: string;
  out APosition: TVec2): boolean;
var
  Node: TEvalNode;
begin
  APosition := Vec2(0, 0);
  Node := Context.FindNode(AKey);
  Result := Node is TPointObject;
  if Result then
    APosition := TPointObject(Node).Position
  else if Node <> nil then
    Fail(esError, Format(rsDraftNotAPoint, [Node.DisplayName]))
  else
    Fail(esError, Format(rsDraftNotAPoint, [AKey]));
end;

function TPointObject.TypeName: string;
begin
  Result := 'point';
end;

function TPointObject.HasProperty(const Prop: string): boolean;
begin
  Result := (Prop = 'x') or (Prop = 'y');
end;

function TPointObject.PropertyValue(const Prop: string): double;
begin
  if Prop = 'x' then
    Result := FPosition.X
  else
    Result := FPosition.Y;
end;

{ TFreePoint }

constructor TFreePoint.Create(const AKey: string);
begin
  inherited Create(AKey);
  AddField('x');
  AddField('y');
end;

function TFreePoint.Compute(Context: TEvalContext): TEvalState;
var
  XValue, YValue: double;
begin
  if not EvalField(Context, 'x', XValue) or not EvalField(Context, 'y', YValue) then
    Exit(esError);
  FPosition := Vec2(XValue, YValue);
  Result := esValid;
end;

{ TOffsetPoint }

constructor TOffsetPoint.Create(const AKey, ABase: string; AMode: TOffsetMode);
begin
  inherited Create(AKey);
  FBase := ABase;
  FMode := AMode;
  if AMode = omPolar then
  begin
    AddField('length');
    AddField('angle');
  end
  else
  begin
    AddField('dx');
    AddField('dy');
  end;
end;

function TOffsetPoint.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := FBase;
end;

function TOffsetPoint.Compute(Context: TEvalContext): TEvalState;
var
  BasePos: TVec2;
  LengthOrDx, AngleOrDy: double;
begin
  if not InputPoint(Context, FBase, BasePos) then
    Exit(esError);
  if FMode = omPolar then
  begin
    if not EvalField(Context, 'length', LengthOrDx) or not EvalField(Context, 'angle', AngleOrDy) then
      Exit(esError);
    FPosition := PolarPoint(BasePos, LengthOrDx, AngleOrDy);
  end
  else
  begin
    if not EvalField(Context, 'dx', LengthOrDx) or not EvalField(Context, 'dy', AngleOrDy) then
      Exit(esError);
    FPosition := BasePos + Vec2(LengthOrDx, AngleOrDy);
  end;
  Result := esValid;
end;

{ TAlongEdgePoint }

constructor TAlongEdgePoint.Create(const AKey, AEdge: string; AFromEnd: boolean;
  AMode: TAlongMode);
begin
  inherited Create(AKey);
  FEdge := AEdge;
  FFromEnd := AFromEnd;
  FMode := AMode;
  AddField('value');
end;

function TAlongEdgePoint.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0] := FEdge;
end;

function TAlongEdgePoint.Compute(Context: TEvalContext): TEvalState;
var
  Node: TEvalNode;
  EdgeObject: TEdgeObject;
  Amount, Len, DistanceAlong: double;
begin
  Node := Context.FindNode(FEdge);
  if not (Node is TEdgeObject) then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FEdge])));
  EdgeObject := TEdgeObject(Node);
  if not EvalField(Context, 'value', Amount) then
    Exit(esError);
  Len := EdgeObject.Length;
  if FMode = amRatio then
  begin
    if (Amount < 0) or (Amount > 1) then
      Exit(Fail(esInvalid, Format(rsDraftRatioRange, [FormatFloat('0.###', Amount)])));
    DistanceAlong := Amount * Len;
  end
  else
  begin
    if (Amount < -DefaultTolerance) or (Amount > Len + DefaultTolerance) then
      Exit(Fail(esInvalid, Format(rsDraftPastEnd, [FormatMM(Amount), EdgeObject.DisplayName, FormatMM(Len)])));
    DistanceAlong := Amount;
  end;
  if FFromEnd then
    DistanceAlong := Len - DistanceAlong;
  FPosition := EdgeObject.PointAtLength(DistanceAlong);
  Result := esValid;
end;

{ Segments }

function LineSegment(const ALine: TLine2): TEdgeSegment;
begin
  Result := Default(TEdgeSegment);
  Result.Kind := skLine;
  Result.Line := ALine;
end;

function CurveSegment(const ACurve: TCubicBezier): TEdgeSegment;
begin
  Result := Default(TEdgeSegment);
  Result.Kind := skCurve;
  Result.Curve := ACurve;
end;

procedure AddSegment(var Segments: TEdgeSegmentArray; const Segment: TEdgeSegment);
begin
  SetLength(Segments, Length(Segments) + 1);
  Segments[High(Segments)] := Segment;
end;

function SegmentLength(const Segment: TEdgeSegment): double;
begin
  if Segment.Kind = skLine then
    Result := Segment.Line.Length
  else
    Result := Segment.Curve.Length;
end;

function SegmentPointAtLength(const Segment: TEdgeSegment; ADistance: double): TVec2;
begin
  if Segment.Kind = skLine then
    Result := Segment.Line.PointAtLength(ADistance)
  else
    Result := Segment.Curve.PointAtLength(ADistance);
end;

{ TEdgeObject }

constructor TEdgeObject.Create(const AKey, AStart, AEnd: string);
begin
  inherited Create(AKey);
  FStartKey := AStart;
  FEndKey := AEnd;
  NameIsDerived := True;
end;

function TEdgeObject.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FStartKey;
  Result[1] := FEndKey;
end;

function TEdgeObject.HasProperty(const Prop: string): boolean;
begin
  Result := (Prop = 'length') or (Prop = 'angle1') or (Prop = 'angle2');
end;

function TEdgeObject.PropertyValue(const Prop: string): double;
begin
  if Prop = 'length' then
    Result := Length
  else if Prop = 'angle1' then
    Result := StartDirection
  else
    Result := NormalizeAngle(EndDirection + 180);
end;

function TEdgeObject.Length: double;
var
  Segment: TEdgeSegment;
begin
  Result := 0;
  for Segment in FSegments do
    Result := Result + SegmentLength(Segment);
end;

function TEdgeObject.PointAtLength(ADistance: double): TVec2;
var
  Index: integer;
  Remaining, SegLength: double;
begin
  if System.Length(FSegments) = 0 then
    Exit(Vec2(0, 0));
  Remaining := ADistance;
  for Index := 0 to High(FSegments) - 1 do
  begin
    SegLength := SegmentLength(FSegments[Index]);
    if Remaining <= SegLength then
      Exit(SegmentPointAtLength(FSegments[Index], Remaining));
    Remaining := Remaining - SegLength;
  end;
  Result := SegmentPointAtLength(FSegments[High(FSegments)], Remaining);
end;

function TEdgeObject.StartDirection: double;
begin
  if System.Length(FSegments) = 0 then
    Exit(0);
  if FSegments[0].Kind = skLine then
    Result := FSegments[0].Line.Angle
  else
    Result := FSegments[0].Curve.StartAngle;
end;

function TEdgeObject.EndDirection: double;
var
  Last: TEdgeSegment;
begin
  if System.Length(FSegments) = 0 then
    Exit(0);
  Last := FSegments[High(FSegments)];
  if Last.Kind = skLine then
    Result := Last.Line.Angle
  else
    // The end handle points back along the curve
    Result := NormalizeAngle(Last.Curve.EndAngle + 180);
end;

function LinePiece(const ALine: TLine2; TMin, TMax, PosBase, PosScale: double): TEdgePiece;
begin
  Result := Default(TEdgePiece);
  Result.Kind := epLine;
  Result.Line := ALine;
  Result.TMin := TMin;
  Result.TMax := TMax;
  Result.PosBase := PosBase;
  Result.PosScale := PosScale;
end;

procedure AddPiece(var Pieces: TEdgePieceArray; const Piece: TEdgePiece);
begin
  SetLength(Pieces, Length(Pieces) + 1);
  Pieces[High(Pieces)] := Piece;
end;

function TEdgeObject.Pieces(Extend: boolean): TEdgePieceArray;
var
  Segment: TEdgeSegment;
  Piece: TEdgePiece;
  Position, SegLength: double;
  StartPos, EndPos: TVec2;
begin
  Result := nil;
  Position := 0;
  for Segment in FSegments do
  begin
    SegLength := SegmentLength(Segment);
    if Segment.Kind = skLine then
      AddPiece(Result, LinePiece(Segment.Line, 0, 1, Position, SegLength))
    else
    begin
      Piece := Default(TEdgePiece);
      Piece.Kind := epCurve;
      Piece.Curve := Segment.Curve;
      Piece.PosBase := Position;
      AddPiece(Result, Piece);
    end;
    Position := Position + SegLength;
  end;
  if Extend and (System.Length(FSegments) > 0) then
  begin
    // Rays of unit-length lines, so T is the distance along them in mm: one
    // back from the start, one on from the end
    if FSegments[0].Kind = skLine then
      StartPos := FSegments[0].Line.P1
    else
      StartPos := FSegments[0].Curve.P0;
    if FSegments[High(FSegments)].Kind = skLine then
      EndPos := FSegments[High(FSegments)].Line.P2
    else
      EndPos := FSegments[High(FSegments)].Curve.P3;
    AddPiece(Result, LinePiece(Line2(StartPos, PolarPoint(StartPos, 1, StartDirection + 180)),
      0, Infinity, 0, -1));
    AddPiece(Result, LinePiece(Line2(EndPos, PolarPoint(EndPos, 1, EndDirection)),
      0, Infinity, Position, 1));
  end;
end;

function TEdgeObject.Locate(const APoint: TVec2; out Position, Offset: double): TVec2;
var
  Index: integer;
  Before, T, SegOffset, SegPosition: double;
  Nearest: TVec2;
  Segment: TEdgeSegment;
begin
  Result := Vec2(0, 0);
  Position := 0;
  Offset := Infinity;
  Before := 0;
  for Index := 0 to High(FSegments) do
  begin
    Segment := FSegments[Index];
    if Segment.Kind = skLine then
    begin
      T := EnsureRange(Segment.Line.ParamOf(APoint), 0, 1);
      Nearest := Segment.Line.PointAt(T);
      SegPosition := T * Segment.Line.Length;
    end
    else
    begin
      T := Segment.Curve.ClosestParam(APoint);
      Nearest := Segment.Curve.PointAt(T);
      SegPosition := Segment.Curve.LengthBetween(0, T);
    end;
    SegOffset := Distance(APoint, Nearest);
    if SegOffset < Offset then
    begin
      Offset := SegOffset;
      Position := Before + SegPosition;
      Result := Nearest;
    end;
    Before := Before + SegmentLength(Segment);
  end;
end;

procedure TEdgeObject.SplitAt(Position: double; out First, Second: TEdgeSegmentArray);
var
  Index: integer;
  Before, SegLength, Local, T: double;
  Segment: TEdgeSegment;
  SplitPos: TVec2;
  CurveA, CurveB: TCubicBezier;
  Done: boolean;
begin
  First := nil;
  Second := nil;
  Before := 0;
  Done := False;
  for Index := 0 to High(FSegments) do
  begin
    Segment := FSegments[Index];
    SegLength := SegmentLength(Segment);
    if Done then
      AddSegment(Second, Segment)
    else if (Before + SegLength < Position) and (Index < High(FSegments)) then
      AddSegment(First, Segment)
    else
    begin
      // The split falls in this segment
      Local := Position - Before;
      if Segment.Kind = skLine then
      begin
        SplitPos := Segment.Line.PointAtLength(Local);
        if Local > DefaultTolerance then
          AddSegment(First, LineSegment(Line2(Segment.Line.P1, SplitPos)));
        if SegLength - Local > DefaultTolerance then
          AddSegment(Second, LineSegment(Line2(SplitPos, Segment.Line.P2)));
      end
      else
      begin
        T := Segment.Curve.ParamAtLength(Local);
        Segment.Curve.Split(T, CurveA, CurveB);
        if Local > DefaultTolerance then
          AddSegment(First, CurveSegment(CurveA));
        if SegLength - Local > DefaultTolerance then
          AddSegment(Second, CurveSegment(CurveB));
      end;
      Done := True;
    end;
    Before := Before + SegLength;
  end;
end;

// Position of the point with Key, or False if it is not a point
function PointPosition(Context: TEvalContext; const Key: string; out APosition: TVec2): boolean;
var
  Node: TEvalNode;
begin
  APosition := Vec2(0, 0);
  Node := Context.FindNode(Key);
  Result := Node is TPointObject;
  if Result then
    APosition := TPointObject(Node).Position;
end;

function EdgeEnds(Edge: TEdgeObject; Context: TEvalContext; out StartPos, EndPos: TVec2): TEvalState;
begin
  EndPos := Vec2(0, 0);
  if not PointPosition(Context, Edge.StartKey, StartPos) or not PointPosition(Context, Edge.EndKey, EndPos) then
    Exit(esError);
  if PointsNear(StartPos, EndPos) then
    Exit(esInvalid);
  Result := esValid;
end;

{ TLineObject }

function TLineObject.GetLine: TLine2;
begin
  if System.Length(FSegments) = 0 then
    Result := Line2(Vec2(0, 0), Vec2(0, 0))
  else
    Result := FSegments[0].Line;
end;

function TLineObject.TypeName: string;
begin
  Result := 'line';
end;

function TLineObject.NamePrefix: string;
begin
  Result := 'Line';
end;

function TLineObject.HasProperty(const Prop: string): boolean;
begin
  Result := (Prop = 'angle') or inherited HasProperty(Prop);
end;

function TLineObject.PropertyValue(const Prop: string): double;
begin
  if Prop = 'angle' then
    Result := Line.Angle
  else
    Result := inherited PropertyValue(Prop);
end;

function TLineObject.Compute(Context: TEvalContext): TEvalState;
var
  StartPos, EndPos: TVec2;
begin
  Result := EdgeEnds(Self, Context, StartPos, EndPos);
  case Result of
    esError: Exit(Fail(esError, Format(rsDraftNotAPoint, [StartKey + '/' + EndKey])));
    esInvalid: Exit(Fail(esInvalid, rsDraftSamePlace));
  end;
  FSegments := nil;
  AddSegment(FSegments, LineSegment(Line2(StartPos, EndPos)));
end;

{ TCurveObject }

constructor TCurveObject.Create(const AKey, AStart, AEnd: string);
begin
  inherited Create(AKey, AStart, AEnd);
  AddField('angle1');
  AddField('length1');
  AddField('angle2');
  AddField('length2');
end;

function TCurveObject.GetCurve: TCubicBezier;
begin
  if System.Length(FSegments) = 0 then
    Result := Default(TCubicBezier)
  else
    Result := FSegments[0].Curve;
end;

function TCurveObject.TypeName: string;
begin
  Result := 'curve';
end;

function TCurveObject.NamePrefix: string;
begin
  Result := 'Curve';
end;

function TCurveObject.Compute(Context: TEvalContext): TEvalState;
var
  StartPos, EndPos: TVec2;
  A1, L1, A2, L2: double;
begin
  Result := EdgeEnds(Self, Context, StartPos, EndPos);
  case Result of
    esError: Exit(Fail(esError, Format(rsDraftNotAPoint, [StartKey + '/' + EndKey])));
    esInvalid: Exit(Fail(esInvalid, rsDraftSamePlace));
  end;
  if not EvalField(Context, 'angle1', A1) or not EvalField(Context, 'length1', L1) or not EvalField(Context, 'angle2', A2) or
    not EvalField(Context, 'length2', L2) then
    Exit(esError);
  if (L1 < 0) or (L2 < 0) then
    Exit(Fail(esInvalid, rsDraftNegativeHandle));
  FSegments := nil;
  AddSegment(FSegments, CurveSegment(BezierFromHandles(StartPos, A1, L1, EndPos, A2, L2)));
  Result := esValid;
end;

{ TCurvePathObject }

constructor TCurvePathObject.Create(const AKey: string; const ANodeKeys: array of string);
var
  Index: integer;
  NodeName: string;
begin
  inherited Create(AKey, ANodeKeys[0], ANodeKeys[High(ANodeKeys)]);
  SetLength(FNodeKeys, System.Length(ANodeKeys));
  for Index := 0 to High(ANodeKeys) do
  begin
    FNodeKeys[Index] := ANodeKeys[Index];
    NodeName := 'node' + IntToStr(Index + 1);
    if Index > 0 then
      AddField(NodeName + '.lengthIn');
    AddField(NodeName + '.angle');
    if Index < High(ANodeKeys) then
      AddField(NodeName + '.lengthOut');
  end;
end;

function TCurvePathObject.InputKeys: TStringArray;
begin
  Result := Copy(FNodeKeys);
end;

function TCurvePathObject.TypeName: string;
begin
  Result := 'path';
end;

function TCurvePathObject.NamePrefix: string;
begin
  Result := 'Path';
end;

function TCurvePathObject.Compute(Context: TEvalContext): TEvalState;
var
  Index: integer;
  Positions: TVec2Array;
  Angles, LengthsIn, LengthsOut: array of double;
  NodeName: string;
begin
  Positions := nil;
  SetLength(Positions, System.Length(FNodeKeys));
  Angles := nil;
  SetLength(Angles, System.Length(FNodeKeys));
  LengthsIn := nil;
  SetLength(LengthsIn, System.Length(FNodeKeys));
  LengthsOut := nil;
  SetLength(LengthsOut, System.Length(FNodeKeys));
  for Index := 0 to High(FNodeKeys) do
  begin
    if not PointPosition(Context, FNodeKeys[Index], Positions[Index]) then
      Exit(Fail(esError, Format(rsDraftNotAPoint, [FNodeKeys[Index]])));
    if (Index > 0) and PointsNear(Positions[Index - 1], Positions[Index]) then
      Exit(Fail(esInvalid, rsDraftSamePlace));
    NodeName := 'node' + IntToStr(Index + 1);
    if not EvalField(Context, NodeName + '.angle', Angles[Index]) then
      Exit(esError);
    if (Index > 0) and not EvalField(Context, NodeName + '.lengthIn', LengthsIn[Index]) then
      Exit(esError);
    if (Index < High(FNodeKeys)) and not EvalField(Context, NodeName + '.lengthOut', LengthsOut[Index]) then
      Exit(esError);
    if (LengthsIn[Index] < 0) or (LengthsOut[Index] < 0) then
      Exit(Fail(esInvalid, rsDraftNegativeHandle));
  end;
  FSegments := nil;
  // The handle into node i+1 points back along its tangent
  for Index := 0 to High(FNodeKeys) - 1 do
    AddSegment(FSegments, CurveSegment(BezierFromHandles(Positions[Index], Angles[Index], LengthsOut[Index],
      Positions[Index + 1], Angles[Index + 1] + 180, LengthsIn[Index + 1])));
  Result := esValid;
end;

function IsStraightEdge(Edge: TEdgeObject): boolean;
begin
  Result := (Edge is TLineObject) or ((Edge is TSplitPart) and TSplitPart(Edge).Straight);
end;

function NewSplitPart(const AKey: string; Source: TEdgeObject; const APoint: string; APart: integer): TSplitPart;
begin
  Result := TSplitPart.Create(AKey, Source.Key, APoint, APart, Source.StartKey, Source.EndKey,
    IsStraightEdge(Source), Source.NamePrefix);
end;

{ TSplitPart }

constructor TSplitPart.Create(const AKey, ASource, APoint: string; APart: integer;
  const ASourceStart, ASourceEnd: string; AStraight: boolean; const APrefix: string);
begin
  if APart = 1 then
    inherited Create(AKey, ASourceStart, APoint)
  else
    inherited Create(AKey, APoint, ASourceEnd);
  FSource := ASource;
  FPoint := APoint;
  FPart := APart;
  FStraight := AStraight;
  FPrefix := APrefix;
end;

function TSplitPart.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FSource;
  Result[1] := FPoint;
end;

function TSplitPart.TypeName: string;
begin
  Result := 'part';
end;

function TSplitPart.NamePrefix: string;
begin
  Result := FPrefix;
end;

function TSplitPart.HasProperty(const Prop: string): boolean;
begin
  Result := (FStraight and (Prop = 'angle')) or inherited HasProperty(Prop);
end;

function TSplitPart.PropertyValue(const Prop: string): double;
begin
  if Prop = 'angle' then
    Result := StartDirection
  else
    Result := inherited PropertyValue(Prop);
end;

function TSplitPart.Compute(Context: TEvalContext): TEvalState;
var
  Node: TEvalNode;
  SourceEdge: TEdgeObject;
  SplitPos: TVec2;
  Position, Offset: double;
  First, Second: TEdgeSegmentArray;
begin
  Node := Context.FindNode(FSource);
  if not (Node is TEdgeObject) then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FSource])));
  SourceEdge := TEdgeObject(Node);
  if not PointPosition(Context, FPoint, SplitPos) then
    Exit(Fail(esError, Format(rsDraftNotAPoint, [FPoint])));
  SourceEdge.Locate(SplitPos, Position, Offset);
  if Offset > DefaultTolerance then
    Exit(Fail(esInvalid, Format(rsDraftNotOnEdge, [Context.FindNode(FPoint).DisplayName, SourceEdge.DisplayName])));
  if (Position <= DefaultTolerance) or (Position >= SourceEdge.Length - DefaultTolerance) then
    Exit(Fail(esInvalid, Format(rsDraftSplitAtEnd, [Context.FindNode(FPoint).DisplayName, SourceEdge.DisplayName])));
  SourceEdge.SplitAt(Position, First, Second);
  if FPart = 1 then
    FSegments := First
  else
    FSegments := Second;
  Result := esValid;
end;

// True when T is within a line piece, allowing DefaultTolerance in mm
function InPiece(const Piece: TEdgePiece; T: double): boolean;
var
  Tolerance: double;
begin
  Tolerance := DefaultTolerance / Max(Piece.Line.Length, Epsilon);
  Result := (T >= Piece.TMin - Tolerance) and (T <= Piece.TMax + Tolerance);
end;

procedure AddCrossing(var Crossings: TEdgeCrossingArray; const APoint: TVec2; APosition: double);
begin
  SetLength(Crossings, Length(Crossings) + 1);
  Crossings[High(Crossings)].Point := APoint;
  Crossings[High(Crossings)].Position := APosition;
end;

// Sorts by position and merges crossings at the same point, such as where an
// extension ray starts at the curve's end
procedure SortAndMerge(var Crossings: TEdgeCrossingArray);
var
  Index, Inner, Count: integer;
  Item: TEdgeCrossing;
begin
  for Index := 1 to High(Crossings) do
  begin
    Item := Crossings[Index];
    Inner := Index - 1;
    while (Inner >= 0) and (Crossings[Inner].Position > Item.Position) do
    begin
      Crossings[Inner + 1] := Crossings[Inner];
      Dec(Inner);
    end;
    Crossings[Inner + 1] := Item;
  end;
  Count := 0;
  for Index := 0 to High(Crossings) do
    if (Count = 0) or not PointsNear(Crossings[Index].Point, Crossings[Count - 1].Point) then
    begin
      Crossings[Count] := Crossings[Index];
      Inc(Count);
    end;
  SetLength(Crossings, Count);
end;

function CrossPieces(const PiecesA, PiecesB: TEdgePieceArray): TEdgeCrossingArray;
var
  PieceA, PieceB: TEdgePiece;
  Hit: TIntersection;
  Hits: TIntersectionArray;
  CurveHit: TIntersection;
begin
  Result := nil;
  for PieceA in PiecesA do
    for PieceB in PiecesB do
      if (PieceA.Kind = epLine) and (PieceB.Kind = epLine) then
      begin
        if IntersectLines(PieceA.Line, PieceB.Line, True, True, Hit) and InPiece(PieceA, Hit.T1) and InPiece(PieceB, Hit.T2) then
          AddCrossing(Result, Hit.Point, PieceA.PosBase + PieceA.PosScale * Hit.T1);
      end
      else if PieceA.Kind = epLine then
      begin
        Hits := IntersectBezierLine(PieceB.Curve, PieceA.Line, True);
        for CurveHit in Hits do
          if InPiece(PieceA, CurveHit.T2) then
            AddCrossing(Result, CurveHit.Point, PieceA.PosBase + PieceA.PosScale * CurveHit.T2);
      end
      else if PieceB.Kind = epLine then
      begin
        Hits := IntersectBezierLine(PieceA.Curve, PieceB.Line, True);
        for CurveHit in Hits do
          if InPiece(PieceB, CurveHit.T2) then
            AddCrossing(Result, CurveHit.Point, PieceA.PosBase + PieceA.Curve.LengthBetween(0, CurveHit.T1));
      end
      else
      begin
        Hits := IntersectBeziers(PieceA.Curve, PieceB.Curve);
        for CurveHit in Hits do
          AddCrossing(Result, CurveHit.Point, PieceA.PosBase + PieceA.Curve.LengthBetween(0, CurveHit.T1));
      end;
  SortAndMerge(Result);
end;

function CrossEdges(EdgeA: TEdgeObject; ExtendA: boolean; EdgeB: TEdgeObject;
  ExtendB: boolean): TEdgeCrossingArray;
begin
  Result := CrossPieces(EdgeA.Pieces(ExtendA), EdgeB.Pieces(ExtendB));
end;

function CrossCircleEdge(const Centre: TVec2; Radius: double; Edge: TEdgeObject;
  Extend: boolean): TEdgeCrossingArray;
var
  Piece: TEdgePiece;
  Hit: TIntersection;
begin
  Result := nil;
  for Piece in Edge.Pieces(Extend) do
    if Piece.Kind = epLine then
    begin
      for Hit in IntersectLineCircle(Piece.Line, True, Centre, Radius) do
        if InPiece(Piece, Hit.T1) then
          AddCrossing(Result, Hit.Point, Piece.PosBase + Piece.PosScale * Hit.T1);
    end
    else
      for Hit in IntersectBezierCircle(Piece.Curve, Centre, Radius) do
        AddCrossing(Result, Hit.Point, Piece.PosBase + Piece.Curve.LengthBetween(0, Hit.T1));
  SortAndMerge(Result);
end;

// The edge for Key, or nil if it is not an edge
function InputEdge(Context: TEvalContext; const Key: string): TEdgeObject;
var
  Found: TEvalNode;
begin
  Found := Context.FindNode(Key);
  if Found is TEdgeObject then
    Result := TEdgeObject(Found)
  else
    Result := nil;
end;

{ TIntersectPoint }

constructor TIntersectPoint.Create(const AKey, AEdgeA, AEdgeB: string;
  AExtendA, AExtendB: boolean; APick: integer);
begin
  inherited Create(AKey);
  FEdgeA := AEdgeA;
  FEdgeB := AEdgeB;
  FExtendA := AExtendA;
  FExtendB := AExtendB;
  FPick := APick;
end;

function TIntersectPoint.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FEdgeA;
  Result[1] := FEdgeB;
end;

function TIntersectPoint.Compute(Context: TEvalContext): TEvalState;
var
  First, Second: TEdgeObject;
  Crossings: TEdgeCrossingArray;
begin
  First := InputEdge(Context, FEdgeA);
  Second := InputEdge(Context, FEdgeB);
  if First = nil then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FEdgeA])));
  if Second = nil then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FEdgeB])));
  Crossings := CrossEdges(First, FExtendA, Second, FExtendB);
  if Length(Crossings) = 0 then
    Exit(Fail(esInvalid, Format(rsDraftNoCrossing, [First.DisplayName, Second.DisplayName])));
  if FPick > Length(Crossings) then
    Exit(Fail(esInvalid, Format(rsDraftPickMissing, [Length(Crossings), FPick])));
  FPosition := Crossings[FPick - 1].Point;
  Result := esValid;
end;

{ TCircleEdgePoint }

constructor TCircleEdgePoint.Create(const AKey, ACentre, AEdge: string; AExtend: boolean;
  APick: integer);
begin
  inherited Create(AKey);
  FCentre := ACentre;
  FEdge := AEdge;
  FExtend := AExtend;
  FPick := APick;
  AddField('radius');
end;

function TCircleEdgePoint.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FCentre;
  Result[1] := FEdge;
end;

function TCircleEdgePoint.Compute(Context: TEvalContext): TEvalState;
var
  CentrePos: TVec2;
  EdgeObject: TEdgeObject;
  Radius: double;
  Crossings: TEdgeCrossingArray;
begin
  if not InputPoint(Context, FCentre, CentrePos) then
    Exit(esError);
  EdgeObject := InputEdge(Context, FEdge);
  if EdgeObject = nil then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FEdge])));
  if not EvalField(Context, 'radius', Radius) then
    Exit(esError);
  if Radius < 0 then
    Exit(Fail(esInvalid, rsDraftNegativeRadius));
  Crossings := CrossCircleEdge(CentrePos, Radius, EdgeObject, FExtend);
  if Length(Crossings) = 0 then
    Exit(Fail(esInvalid, Format(rsDraftCircleMisses, [EdgeObject.DisplayName])));
  if FPick > Length(Crossings) then
    Exit(Fail(esInvalid, Format(rsDraftPickMissing, [Length(Crossings), FPick])));
  FPosition := Crossings[FPick - 1].Point;
  Result := esValid;
end;

{ TProjectPoint }

constructor TProjectPoint.Create(const AKey, ASource, AEdge: string;
  ADirection: TProjectDirection; AExtend: boolean);
begin
  inherited Create(AKey);
  FSource := ASource;
  FEdge := AEdge;
  FDirection := ADirection;
  FExtend := AExtend;
  if ADirection = pdAngle then
    AddField('angle');
end;

function TProjectPoint.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FSource;
  Result[1] := FEdge;
end;

// Feet of perpendiculars from SourcePos onto the pieces
function PerpendicularFeet(const SourcePos: TVec2; const Pieces: TEdgePieceArray): TVec2Array;
var
  Piece: TEdgePiece;
  T: double;
  Foot, Tangent: TVec2;

  procedure AddFoot(const APoint: TVec2);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := APoint;
  end;

begin
  Result := nil;
  for Piece in Pieces do
    if Piece.Kind = epLine then
    begin
      T := Piece.Line.ParamOf(SourcePos);
      if InPiece(Piece, T) then
        AddFoot(Piece.Line.PointAt(T));
    end
    else
    begin
      // The nearest point counts only where the line to it is square to
      // the curve, not where the curve simply ends
      T := Piece.Curve.ClosestParam(SourcePos);
      Foot := Piece.Curve.PointAt(T);
      Tangent := Piece.Curve.DerivativeAt(T);
      if (Tangent.Length > Epsilon) and
        (Abs(Dot(SourcePos - Foot, Tangent * (1 / Tangent.Length))) <= DefaultTolerance) then
        AddFoot(Foot);
    end;
end;

function TProjectPoint.Compute(Context: TEvalContext): TEvalState;
var
  SourcePos, BestPos, Candidate: TVec2;
  EdgeObject: TEdgeObject;
  AngleValue: double;
  Candidates: TVec2Array;
  Crossing: TEdgeCrossing;
  SourceName: string;
  ThroughSource: TEdgePieceArray;
  Index: integer;
begin
  if not InputPoint(Context, FSource, SourcePos) then
    Exit(esError);
  EdgeObject := InputEdge(Context, FEdge);
  if EdgeObject = nil then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FEdge])));
  SourceName := Context.FindNode(FSource).DisplayName;

  Candidates := nil;
  if FDirection = pdPerpendicular then
  begin
    Candidates := PerpendicularFeet(SourcePos, EdgeObject.Pieces(FExtend));
    if Length(Candidates) = 0 then
      Exit(Fail(esInvalid, Format(rsDraftNoFoot, [SourceName, EdgeObject.DisplayName])));
  end
  else
  begin
    if not EvalField(Context, 'angle', AngleValue) then
      Exit(esError);
    // A line through the source point at the angle, extended both ways
    ThroughSource := nil;
    AddPiece(ThroughSource, LinePiece(Line2(SourcePos, PolarPoint(SourcePos, 1, AngleValue)),
      NegInfinity, Infinity, 0, 1));
    for Crossing in CrossPieces(ThroughSource, EdgeObject.Pieces(FExtend)) do
    begin
      SetLength(Candidates, Length(Candidates) + 1);
      Candidates[High(Candidates)] := Crossing.Point;
    end;
    if Length(Candidates) = 0 then
      Exit(Fail(esInvalid, Format(rsDraftNoProjection,
        [SourceName, FormatFloat('0.#', AngleValue), EdgeObject.DisplayName])));
  end;

  BestPos := Candidates[0];
  for Index := 1 to High(Candidates) do
  begin
    Candidate := Candidates[Index];
    if Distance(SourcePos, Candidate) < Distance(SourcePos, BestPos) then
      BestPos := Candidate;
  end;
  FPosition := BestPos;
  Result := esValid;
end;

end.
