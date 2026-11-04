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

// Transforms: one movement (rotate, mirror or move) applied to copies of points
// and edges, so the copies follow their sources. A copy reads its transform and
// its own source, so a failing source stops only its own copy. See Transforms in
// the design document. No LCL dependency.
unit Sloper.Core.Transform;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Bezier, Sloper.Core.Draft;

const
  FieldAngle = 'angle';
  FieldLength = 'length';
  FieldDX = 'dx';
  FieldDY = 'dy';
  FieldRotate = 'rotate';

type
  TTransformKind = (tkRotate, tkMirror, tkMove);

  TTransformObject = class(TDraftObject)
  private
    FKind: TTransformKind;
    FSources: TStringArray;
    FSuffix: string;
    FPivotKey, FAxisEdgeKey, FAxisAKey, FAxisBKey: string;
    FPolar: boolean;
    FMap: TAffine2;
    function PointAtKey(Context: TEvalContext; const AKey: string; out Position: TVec2): boolean;
    function ComputeRotate(Context: TEvalContext): TEvalState;
    function ComputeMirror(Context: TEvalContext): TEvalState;
    function ComputeMove(Context: TEvalContext): TEvalState;
  public
    // Sources are the keys of what it copies; the fields follow from the kind
    // and what is set afterwards with the Use methods
    constructor Create(const AKey: string; AKind: TTransformKind; const ASources: TStringArray; const ASuffix: string);
    procedure UseRotate(const APivotKey: string);
    // One of: a straight edge; two points; a point, with an angle field
    procedure UseAxisEdge(const AEdgeKey: string);
    procedure UseAxisPoints(const AKeyA, AKeyB: string);
    procedure UseAxisAngle(const AKeyA: string);
    procedure UseMove(APolar: boolean; const APivotKey: string);
    function InputKeys: TStringArray; override;
    procedure RedirectPoint(const OldKey, NewKey: string); override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Kind: TTransformKind read FKind;
    property Sources: TStringArray read FSources;
    property Suffix: string read FSuffix;
    property PivotKey: string read FPivotKey;
    property AxisEdgeKey: string read FAxisEdgeKey;
    property AxisAKey: string read FAxisAKey;
    property AxisBKey: string read FAxisBKey;
    property Polar: boolean read FPolar;
    // The last good movement
    property Map: TAffine2 read FMap;
  end;

  TPointCopy = class(TPointObject)
  private
    FTransformKey, FSource: string;
  public
    constructor Create(const AKey, ATransformKey, ASource: string);
    function InputKeys: TStringArray; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property TransformKey: string read FTransformKey;
    property Source: string read FSource;
  end;

  TEdgeCopy = class(TEdgeObject)
  private
    FTransformKey, FSource, FPrefix: string;
    FStraight: boolean;
  public
    // AStraight and APrefix come from the source edge
    constructor Create(const AKey, ATransformKey, ASource, AStart, AEnd: string; AStraight: boolean; const APrefix: string);
    function InputKeys: TStringArray; override;
    function TypeName: string; override;
    function NamePrefix: string; override;
    function IsStraight: boolean; override;
    // Straight copies also have angle, their direction
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property TransformKey: string read FTransformKey;
    property Source: string read FSource;
  end;

// The transform a copy belongs to, or ''
function CopyTransformKey(Node: TEvalNode): string;

resourcestring
  rsTransformNotATransform = '%s is not a transform';
  rsTransformCurvedAxis = 'A mirror needs a straight edge, and %s is not';
  rsTransformNoAxis = 'The mirror''s two points are at the same place';

implementation

constructor TTransformObject.Create(const AKey: string; AKind: TTransformKind; const ASources: TStringArray; const ASuffix: string);
begin
  inherited Create(AKey);
  FKind := AKind;
  FSources := Copy(ASources);
  FSuffix := ASuffix;
  FMap := AffineIdentity;
end;

procedure TTransformObject.UseRotate(const APivotKey: string);
begin
  FPivotKey := APivotKey;
  AddField(FieldAngle);
end;

procedure TTransformObject.UseAxisEdge(const AEdgeKey: string);
begin
  FAxisEdgeKey := AEdgeKey;
end;

procedure TTransformObject.UseAxisPoints(const AKeyA, AKeyB: string);
begin
  FAxisAKey := AKeyA;
  FAxisBKey := AKeyB;
end;

procedure TTransformObject.UseAxisAngle(const AKeyA: string);
begin
  FAxisAKey := AKeyA;
  AddField(FieldAngle);
end;

procedure TTransformObject.UseMove(APolar: boolean; const APivotKey: string);
begin
  FPolar := APolar;
  FPivotKey := APivotKey;
  if APolar then
  begin
    AddField(FieldLength);
    AddField(FieldAngle);
  end
  else
  begin
    AddField(FieldDX);
    AddField(FieldDY);
  end;
  if APivotKey <> '' then
    AddField(FieldRotate);
end;

function TTransformObject.InputKeys: TStringArray;

  procedure Add(const Key: string);
  begin
    if Key <> '' then
      Insert(Key, Result, Length(Result));
  end;

begin
  Result := nil;
  Add(FPivotKey);
  Add(FAxisEdgeKey);
  Add(FAxisAKey);
  Add(FAxisBKey);
end;

// Not its sources: a copy cannot change what it is a copy of
procedure TTransformObject.RedirectPoint(const OldKey, NewKey: string);
begin
  RedirectKey(FPivotKey, OldKey, NewKey);
  RedirectKey(FAxisAKey, OldKey, NewKey);
  RedirectKey(FAxisBKey, OldKey, NewKey);
end;

function TTransformObject.TypeName: string;
const
  Names: array[TTransformKind] of string = ('rotate', 'mirror', 'move');
begin
  Result := Names[FKind];
end;

function TTransformObject.HasProperty(const Prop: string): boolean;
begin
  Result := False;
end;

function TTransformObject.PropertyValue(const Prop: string): double;
begin
  Result := 0;
end;

function TTransformObject.PointAtKey(Context: TEvalContext; const AKey: string; out Position: TVec2): boolean;
var
  Node: TEvalNode;
begin
  Position := Vec2(0, 0);
  Node := Context.FindNode(AKey);
  Result := Node is TPointObject;
  if Result then
    Position := TPointObject(Node).Position;
end;

function TTransformObject.ComputeRotate(Context: TEvalContext): TEvalState;
var
  Pivot: TVec2;
  Angle: double;
begin
  if not PointAtKey(Context, FPivotKey, Pivot) then
    Exit(Fail(esError, Format(rsDraftNotAPoint, [FPivotKey])));
  if not EvalField(Context, FieldAngle, Angle) then
    Exit(esError);
  FMap := AffineTurnAbout(Pivot, Angle);
  Result := esValid;
end;

function TTransformObject.ComputeMirror(Context: TEvalContext): TEvalState;
var
  First, Second: TVec2;
  Angle: double;
  Node: TEvalNode;
begin
  if FAxisEdgeKey <> '' then
  begin
    Node := Context.FindNode(FAxisEdgeKey);
    if not (Node is TEdgeObject) then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [FAxisEdgeKey])));
    if not TEdgeObject(Node).IsStraight then
      Exit(Fail(esInvalid, Format(rsTransformCurvedAxis, [Node.DisplayName])));
    First := TEdgeObject(Node).PointAtLength(0);
    Second := TEdgeObject(Node).PointAtLength(TEdgeObject(Node).Length);
  end
  else
  begin
    if not PointAtKey(Context, FAxisAKey, First) then
      Exit(Fail(esError, Format(rsDraftNotAPoint, [FAxisAKey])));
    if FAxisBKey <> '' then
    begin
      if not PointAtKey(Context, FAxisBKey, Second) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [FAxisBKey])));
    end
    else
    begin
      if not EvalField(Context, FieldAngle, Angle) then
        Exit(esError);
      Second := PolarPoint(First, 1, Angle);
    end;
  end;
  if PointsNear(First, Second) then
    Exit(Fail(esInvalid, rsTransformNoAxis));
  FMap := AffineReflect(First, Second);
  Result := esValid;
end;

function TTransformObject.ComputeMove(Context: TEvalContext): TEvalState;
var
  Offset, Pivot: TVec2;
  First, Second, Turn: double;
  Movement: TAffine2;
begin
  if FPolar then
  begin
    if not EvalField(Context, FieldLength, First) or not EvalField(Context, FieldAngle, Second) then
      Exit(esError);
    Offset := PolarPoint(Vec2(0, 0), First, Second);
  end
  else
  begin
    if not EvalField(Context, FieldDX, First) or not EvalField(Context, FieldDY, Second) then
      Exit(esError);
    Offset := Vec2(First, Second);
  end;
  Movement := AffineShift(Offset);
  if FPivotKey <> '' then
  begin
    if not PointAtKey(Context, FPivotKey, Pivot) then
      Exit(Fail(esError, Format(rsDraftNotAPoint, [FPivotKey])));
    if not EvalField(Context, FieldRotate, Turn) then
      Exit(esError);
    Movement := AffineThen(Movement, AffineTurnAbout(Pivot, Turn));
  end;
  FMap := Movement;
  Result := esValid;
end;

function TTransformObject.Compute(Context: TEvalContext): TEvalState;
begin
  case FKind of
    tkRotate: Result := ComputeRotate(Context);
    tkMirror: Result := ComputeMirror(Context);
    else
      Result := ComputeMove(Context);
  end;
end;

{ TPointCopy }

constructor TPointCopy.Create(const AKey, ATransformKey, ASource: string);
begin
  inherited Create(AKey);
  FTransformKey := ATransformKey;
  FSource := ASource;
end;

function TPointCopy.InputKeys: TStringArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := FTransformKey;
  Result[1] := FSource;
end;

function TPointCopy.Compute(Context: TEvalContext): TEvalState;
var
  Node, Mover: TEvalNode;
begin
  Node := Context.FindNode(FSource);
  if not (Node is TPointObject) then
    Exit(Fail(esError, Format(rsDraftNotAPoint, [FSource])));
  Mover := Context.FindNode(FTransformKey);
  if not (Mover is TTransformObject) then
    Exit(Fail(esError, Format(rsTransformNotATransform, [FTransformKey])));
  FPosition := TTransformObject(Mover).Map.Apply(TPointObject(Node).Position);
  Result := esValid;
end;

{ TEdgeCopy }

constructor TEdgeCopy.Create(const AKey, ATransformKey, ASource, AStart, AEnd: string; AStraight: boolean; const APrefix: string);
begin
  inherited Create(AKey, AStart, AEnd);
  FTransformKey := ATransformKey;
  FSource := ASource;
  FStraight := AStraight;
  FPrefix := APrefix;
end;

function TEdgeCopy.InputKeys: TStringArray;
begin
  Result := inherited InputKeys;
  Insert(FTransformKey, Result, System.Length(Result));
  Insert(FSource, Result, System.Length(Result));
end;

function TEdgeCopy.TypeName: string;
begin
  Result := 'edgeCopy';
end;

function TEdgeCopy.NamePrefix: string;
begin
  Result := FPrefix;
end;

function TEdgeCopy.IsStraight: boolean;
begin
  Result := FStraight;
end;

function TEdgeCopy.HasProperty(const Prop: string): boolean;
begin
  Result := (inherited HasProperty(Prop)) or (FStraight and (Prop = FieldAngle));
end;

function TEdgeCopy.PropertyValue(const Prop: string): double;
begin
  if Prop = FieldAngle then
    Result := StartDirection
  else
    Result := inherited PropertyValue(Prop);
end;

// Every kind of edge is line and Bézier segments, so moving their control
// points is exact and needs no case for each
function TEdgeCopy.Compute(Context: TEvalContext): TEvalState;
var
  Node, Mover: TEvalNode;
  Map: TAffine2;
  Moved: TEdgeSegmentArray;
  Index: integer;
begin
  Node := Context.FindNode(FSource);
  if not (Node is TEdgeObject) then
    Exit(Fail(esError, Format(rsDraftNotAnEdge, [FSource])));
  Mover := Context.FindNode(FTransformKey);
  if not (Mover is TTransformObject) then
    Exit(Fail(esError, Format(rsTransformNotATransform, [FTransformKey])));
  Map := TTransformObject(Mover).Map;
  Moved := Copy(TEdgeObject(Node).Segments);
  for Index := 0 to High(Moved) do
    if Moved[Index].Kind = skLine then
      Moved[Index].Line := Line2(Map.Apply(Moved[Index].Line.P1), Map.Apply(Moved[Index].Line.P2))
    else
    begin
      Moved[Index].Curve.P0 := Map.Apply(Moved[Index].Curve.P0);
      Moved[Index].Curve.P1 := Map.Apply(Moved[Index].Curve.P1);
      Moved[Index].Curve.P2 := Map.Apply(Moved[Index].Curve.P2);
      Moved[Index].Curve.P3 := Map.Apply(Moved[Index].Curve.P3);
    end;
  FSegments := Moved;
  Result := esValid;
end;

function CopyTransformKey(Node: TEvalNode): string;
begin
  if Node is TPointCopy then
    Result := TPointCopy(Node).TransformKey
  else if Node is TEdgeCopy then
    Result := TEdgeCopy(Node).TransformKey
  else
    Result := '';
end;

end.
