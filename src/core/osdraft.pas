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
unit osDraft;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, osEvalTypes, osEvaluator, osGeometry, osBezier;

type
  TEdgeRole = (erConstruction, erOutline);
  TOffsetMode = (omPolar, omCartesian);
  TAlongMode = (amLength, amRatio);

  TDraftObject = class(TEvalNode)
  private
    FName: string;
  public
    function DisplayName: string; override;
    function TypeName: string; virtual; abstract;
    // Readable properties in formulas, such as x or length (lower case)
    function HasProperty(const Prop: string): Boolean; virtual; abstract;
    // Value of a property from the last good result
    function PropertyValue(const Prop: string): Double; virtual; abstract;
    property Name: string read FName write FName;
  end;

  TPointObject = class(TDraftObject)
  protected
    FPosition: TVec2;
    // Position of the point with the given key; False with Message set if
    // it is not a point
    function InputPoint(Context: TEvalContext; const AKey: string; out APosition: TVec2): Boolean;
  public
    function TypeName: string; override;
    function HasProperty(const Prop: string): Boolean; override;
    function PropertyValue(const Prop: string): Double; override;
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
    FFromEnd: Boolean;
    FMode: TAlongMode;
  public
    constructor Create(const AKey, AEdge: string; AFromEnd: Boolean; AMode: TAlongMode);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Edge: string read FEdge;
    property FromEnd: Boolean read FFromEnd;
    property Mode: TAlongMode read FMode;
  end;

  TEdgeObject = class(TDraftObject)
  private
    FStartKey, FEndKey: string;
  public
    Role: TEdgeRole;
    // The name follows the endpoints (Line_A_B) until the user renames it
    NameIsDerived: Boolean;
    constructor Create(const AKey, AStart, AEnd: string);
    function InputKeys: TStringArray; override;
    // Geometry of the last good result
    function Length: Double; virtual; abstract;
    function PointAtLength(ADistance: Double): TVec2; virtual; abstract;
    // Prefix for derived names: Line or Curve
    function NamePrefix: string; virtual; abstract;
    property StartKey: string read FStartKey;
    property EndKey: string read FEndKey;
  end;

  TLineObject = class(TEdgeObject)
  private
    FLine: TLine2;
  public
    function TypeName: string; override;
    function NamePrefix: string; override;
    function HasProperty(const Prop: string): Boolean; override;
    function PropertyValue(const Prop: string): Double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function Length: Double; override;
    function PointAtLength(ADistance: Double): TVec2; override;
    property Line: TLine2 read FLine;
  end;

  // Cubic Bézier between two points; handles given by angle1/length1 at the
  // start and angle2/length2 at the end
  TCurveObject = class(TEdgeObject)
  private
    FCurve: TCubicBezier;
  public
    constructor Create(const AKey, AStart, AEnd: string);
    function TypeName: string; override;
    function NamePrefix: string; override;
    function HasProperty(const Prop: string): Boolean; override;
    function PropertyValue(const Prop: string): Double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function Length: Double; override;
    function PointAtLength(ADistance: Double): TVec2; override;
    property Curve: TCubicBezier read FCurve;
  end;

resourcestring
  rsDraftNotAPoint = '%s is not a point';
  rsDraftNotAnEdge = '%s is not a line or curve';
  rsDraftSamePlace = 'The start and end are at the same place';
  rsDraftPastEnd = 'The distance %s mm is past the end of %s (%s mm long)';
  rsDraftRatioRange = 'The ratio %s is outside 0 to 1';
  rsDraftNegativeHandle = 'A handle length cannot be negative';

implementation

function FormatMM(Millimetres: Double): string;
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
  out APosition: TVec2): Boolean;
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

function TPointObject.HasProperty(const Prop: string): Boolean;
begin
  Result := (Prop = 'x') or (Prop = 'y');
end;

function TPointObject.PropertyValue(const Prop: string): Double;
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
  XValue, YValue: Double;
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
  LengthOrDx, AngleOrDy: Double;
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

constructor TAlongEdgePoint.Create(const AKey, AEdge: string; AFromEnd: Boolean;
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
  Amount, Len, DistanceAlong: Double;
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

function EdgeEnds(Edge: TEdgeObject; Context: TEvalContext; out StartPos, EndPos: TVec2): TEvalState;
var
  NA, NB: TEvalNode;
begin
  StartPos := Vec2(0, 0);
  EndPos := Vec2(0, 0);
  NA := Context.FindNode(Edge.StartKey);
  NB := Context.FindNode(Edge.EndKey);
  if not (NA is TPointObject) or not (NB is TPointObject) then
    Exit(esError);
  StartPos := TPointObject(NA).Position;
  EndPos := TPointObject(NB).Position;
  if PointsNear(StartPos, EndPos) then
    Exit(esInvalid);
  Result := esValid;
end;

{ TLineObject }

function TLineObject.TypeName: string;
begin
  Result := 'line';
end;

function TLineObject.NamePrefix: string;
begin
  Result := 'Line';
end;

function TLineObject.HasProperty(const Prop: string): Boolean;
begin
  Result := (Prop = 'length') or (Prop = 'angle');
end;

function TLineObject.PropertyValue(const Prop: string): Double;
begin
  if Prop = 'length' then
    Result := FLine.Length
  else
    Result := FLine.Angle;
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
  FLine := Line2(StartPos, EndPos);
end;

function TLineObject.Length: Double;
begin
  Result := FLine.Length;
end;

function TLineObject.PointAtLength(ADistance: Double): TVec2;
begin
  Result := FLine.PointAtLength(ADistance);
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

function TCurveObject.TypeName: string;
begin
  Result := 'curve';
end;

function TCurveObject.NamePrefix: string;
begin
  Result := 'Curve';
end;

function TCurveObject.HasProperty(const Prop: string): Boolean;
begin
  Result := (Prop = 'length') or (Prop = 'angle1') or (Prop = 'angle2');
end;

function TCurveObject.PropertyValue(const Prop: string): Double;
begin
  if Prop = 'length' then
    Result := FCurve.Length
  else if Prop = 'angle1' then
    Result := FCurve.StartAngle
  else
    Result := FCurve.EndAngle;
end;

function TCurveObject.Compute(Context: TEvalContext): TEvalState;
var
  StartPos, EndPos: TVec2;
  A1, L1, A2, L2: Double;
begin
  Result := EdgeEnds(Self, Context, StartPos, EndPos);
  case Result of
    esError: Exit(Fail(esError, Format(rsDraftNotAPoint, [StartKey + '/' + EndKey])));
    esInvalid: Exit(Fail(esInvalid, rsDraftSamePlace));
  end;
  if not EvalField(Context, 'angle1', A1) or not EvalField(Context, 'length1', L1)
    or not EvalField(Context, 'angle2', A2) or not EvalField(Context, 'length2', L2) then
    Exit(esError);
  if (L1 < 0) or (L2 < 0) then
    Exit(Fail(esInvalid, rsDraftNegativeHandle));
  FCurve := BezierFromHandles(StartPos, A1, L1, EndPos, A2, L2);
  Result := esValid;
end;

function TCurveObject.Length: Double;
begin
  Result := FCurve.Length;
end;

function TCurveObject.PointAtLength(ADistance: Double): TVec2;
begin
  Result := FCurve.PointAtLength(ADistance);
end;

end.
