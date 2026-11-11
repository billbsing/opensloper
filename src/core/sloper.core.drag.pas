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

// Dragging points and curve handles: which can follow the mouse, and the
// formulas a drag writes. A drag only changes fields that are plain numbers, so
// anything placed by a formula (@waist/4) keeps its parametric intent and is
// locked. No LCL dependency.
unit Sloper.Core.Drag;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Bezier, Sloper.Core.FormulaLexer, Sloper.Core.Draft, Sloper.Core.Note, Sloper.Core.Pattern,
  Sloper.Core.Units;

const
  // Dragged angles and ratios are rounded to these decimals; a length is
  // rounded in its unit (DRAG_UNIT_DECIMALS)
  DRAG_ANGLE_DECIMALS = 1;
  DRAG_RATIO_DECIMALS = 4;

type
  // A curve's handle: the end of its tangent line, set by an angle and a length.
  // The two handles at a path's inner node share one angle, so the join stays smooth.
  TCurveHandle = record
    EdgeKey: string;
    // Where the handle starts, on the curve, and where its end is
    Anchor, Position: TVec2;
    AngleField, LengthField: string;
    // Added to the field's angle to get the handle's direction: 180 for the
    // handle into a path node, which points back along the tangent
    AngleOffset: double;
  end;
  TCurveHandleArray = array of TCurveHandle;

// Value rounded to Decimals as formula text, without "-0"
function RoundedText(Value: double; Decimals: integer): string;
// Millimetres as text for a length field being dragged: in the unit the field
// is written in, with its suffix (2in stays in inches), or as a plain number
// in the pattern unit
function DraggedLength(Target: TDraftObject; const FieldName: string; Millimetres: double; Units: TMeasureUnit): string;
// True when Point can be dragged: its type moves freely, and every field the
// drag would change is a plain number. Otherwise ErrorMessage says why; for a
// transform copy it names the source and transform.
function CanDrag(Pattern: TPattern; Point: TPointObject; out ErrorMessage: string): boolean;
// Sets Point's fields so it lies at Target, or as near as its operation
// allows (a point along an edge stays on the edge). Call inside a document
// change and evaluate afterwards. False, with ErrorMessage, when the point
// cannot be dragged.
function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;
// True when the note's offset, or a free note's place, is plain numbers
function CanDragNote(Note: TNoteObject; out ErrorMessage: string): boolean;
// Sets the note's offset, or a free note's place, so its top left lies at
// Target. Call inside a document change and evaluate afterwards.
function DragNote(Pattern: TPattern; Note: TNoteObject; const Target: TVec2; out ErrorMessage: string): boolean;
// The handles of a curve or curve path, as computed; empty for other edges,
// and for one not computed. A split part follows its source and has none.
function CurveHandles(Edge: TEdgeObject): TCurveHandleArray;
// True when both of the handle's fields are plain numbers
function CanDragHandle(Edge: TEdgeObject; const Handle: TCurveHandle; out ErrorMessage: string): boolean;
// Sets the handle's angle and length so its end lies at Target. At the anchor
// the length is 0 and the angle is kept. Call inside a document change and
// evaluate afterwards.
function DragHandle(Pattern: TPattern; Edge: TEdgeObject; const Handle: TCurveHandle; const Target: TVec2;
  out ErrorMessage: string): boolean;

resourcestring
  rsDragFormula = '%s is placed by a formula; change it in its properties';
  rsDragPlaced = '%s is placed by other objects and cannot be dragged';
  // A_r1 follows A (Move Copy 'Back'). Edit A to change it.
  rsDragCopy = '%0:s follows %1:s (%2:s ''%3:s''). Edit %1:s to change it.';
  rsDragHandleFormula = 'This handle of %s is set by a formula; change it in its properties';

implementation

uses
  Math, Sloper.Core.Evaluator, Sloper.Core.JSON, Sloper.Core.Transform;

function RoundedText(Value: double; Decimals: integer): string;
var
  Scale, Rounded: double;
begin
  Scale := IntPower(10, Decimals);
  Rounded := Round(Value * Scale) / Scale;
  // No "-0"
  if Rounded = 0 then
    Rounded := 0;
  Result := FormatJSONFloat(Rounded);
end;

function DraggedLength(Target: TDraftObject; const FieldName: string; Millimetres: double; Units: TMeasureUnit): string;
var
  Suffix: TNumberSuffix;
begin
  Suffix := Target.Field(FieldName).LiteralSuffix;
  // TNumberSuffix follows TMeasureUnit after nsNone
  if Suffix <> nsNone then
    Units := TMeasureUnit(Ord(Suffix) - 1);
  Result := RoundLengthFormulaText(Millimetres, Units) + NUMBER_SUFFIX_NAMES[Suffix];
end;

// The fields a drag of Point writes; empty when its type cannot be dragged
function DragFields(Point: TPointObject): TStringArray;
begin
  Result := nil;
  if Point is TFreePoint then
    Result := ['x', 'y']
  else if Point is TOffsetPoint then
  begin
    if TOffsetPoint(Point).Mode = omPolar then
      Result := ['length', 'angle']
    else
      Result := ['dx', 'dy'];
  end
  else if Point is TAlongEdgePoint then
    Result := ['value'];
end;

// Empty when Point is not a copy, or its source or transform is gone
function CopyRefusal(Pattern: TPattern; Point: TPointObject): string;
var
  Source, Transform: TEvalNode;
begin
  Result := '';
  if not (Point is TPointCopy) then
    Exit;
  Source := Pattern.FindNode(TPointCopy(Point).Source);
  Transform := Pattern.FindNode(TPointCopy(Point).TransformKey);
  if Assigned(Source) and (Transform is TTransformObject) then
    Result := Format(rsDragCopy, [Point.DisplayName, Source.DisplayName, TransformCommandName(TTransformObject(Transform).Kind),
      Transform.DisplayName]);
end;

function CanDrag(Pattern: TPattern; Point: TPointObject; out ErrorMessage: string): boolean;
var
  FieldName: string;
  Fields: TStringArray;
begin
  ErrorMessage := CopyRefusal(Pattern, Point);
  if ErrorMessage <> '' then
    Exit(False);
  Fields := DragFields(Point);
  if Length(Fields) = 0 then
  begin
    ErrorMessage := Format(rsDragPlaced, [Point.DisplayName]);
    Exit(False);
  end;
  for FieldName in Fields do
    if not Point.Field(FieldName).IsLiteral then
    begin
      ErrorMessage := Format(rsDragFormula, [Point.DisplayName]);
      Exit(False);
    end;
  Result := True;
end;

function SetFields(Pattern: TPattern; Target: TDraftObject; const Names, Texts: array of string; out ErrorMessage: string): boolean;
var
  Index: integer;
begin
  for Index := 0 to High(Names) do
    if not Pattern.SetFormula(Target, Names[Index], Texts[Index]) then
    begin
      ErrorMessage := Pattern.LastError;
      Exit(False);
    end;
  Result := True;
end;

function CanDragNote(Note: TNoteObject; out ErrorMessage: string): boolean;
var
  FieldName: string;
begin
  ErrorMessage := '';
  for FieldName in Note.PlaceFields do
    if not Note.Field(FieldName).IsLiteral then
    begin
      ErrorMessage := Format(rsDragFormula, [Note.DisplayName]);
      Exit(False);
    end;
  Result := True;
end;

function DragNote(Pattern: TPattern; Note: TNoteObject; const Target: TVec2; out ErrorMessage: string): boolean;
var
  Fields: TStringArray;
  Offset: TVec2;
begin
  if not CanDragNote(Note, ErrorMessage) then
    Exit(False);
  Fields := Note.PlaceFields;
  Offset := Target - Note.AnchorPosition;
  if Note.Anchor = naFree then
    Offset := Target;
  Result := SetFields(Pattern, Note, Fields, [DraggedLength(Note, Fields[0], Offset.X, Pattern.Units), DraggedLength(Note, Fields[1], Offset.Y, Pattern.Units)],
    ErrorMessage);
end;

function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;
var
  BaseNode: TEvalNode;
  Base: TVec2;
  Along: TAlongEdgePoint;
  Edge: TEdgeObject;
  Position, Offset, Distance, EdgeLength: double;
begin
  if not CanDrag(Pattern, Point, ErrorMessage) then
    Exit(False);
  if Point is TFreePoint then
    Exit(SetFields(Pattern, Point, ['x', 'y'],
      [DraggedLength(Point, 'x', Target.X, Pattern.Units), DraggedLength(Point, 'y', Target.Y, Pattern.Units)], ErrorMessage));

  if Point is TOffsetPoint then
  begin
    BaseNode := Pattern.FindNode(TOffsetPoint(Point).Base);
    Base := TPointObject(BaseNode).Position;
    if TOffsetPoint(Point).Mode = omPolar then
      Exit(SetFields(Pattern, Point, ['length', 'angle'],
        [DraggedLength(Point, 'length', Sloper.Core.Geometry.Distance(Base, Target), Pattern.Units),
        RoundedText(AngleBetween(Base, Target), DRAG_ANGLE_DECIMALS)], ErrorMessage));
    Exit(SetFields(Pattern, Point, ['dx', 'dy'],
      [DraggedLength(Point, 'dx', Target.X - Base.X, Pattern.Units), DraggedLength(Point, 'dy', Target.Y - Base.Y, Pattern.Units)],
      ErrorMessage));
  end;

  // Along an edge: the nearest place on the edge
  Along := TAlongEdgePoint(Point);
  Edge := TEdgeObject(Pattern.FindNode(Along.Edge));
  Edge.Locate(Target, Position, Offset);
  EdgeLength := Edge.Length;
  if Along.FromEnd then
    Distance := EdgeLength - Position
  else
    Distance := Position;
  if Along.Mode = amLength then
    Result := SetFields(Pattern, Point, ['value'], [DraggedLength(Point, 'value', Distance, Pattern.Units)], ErrorMessage)
  else if EdgeLength > 0 then
    Result := SetFields(Pattern, Point, ['value'], [RoundedText(Distance / EdgeLength, DRAG_RATIO_DECIMALS)], ErrorMessage)
  else
    Result := True;
end;

function MakeHandle(Edge: TEdgeObject; const Anchor, Position: TVec2; const AngleField, LengthField: string;
  AngleOffset: double): TCurveHandle;
begin
  Result.EdgeKey := Edge.Key;
  Result.Anchor := Anchor;
  Result.Position := Position;
  Result.AngleField := AngleField;
  Result.LengthField := LengthField;
  Result.AngleOffset := AngleOffset;
end;

function CurveHandles(Edge: TEdgeObject): TCurveHandleArray;
var
  Index: integer;
  Curve: TCubicBezier;
  Node, NextNode: string;
begin
  Result := nil;
  if not Edge.HasResult or (Length(Edge.Segments) = 0) then
    Exit;
  if Edge is TCurveObject then
  begin
    Curve := TCurveObject(Edge).Curve;
    Result := [MakeHandle(Edge, Curve.P0, Curve.P1, 'angle1', 'length1', 0), MakeHandle(Edge, Curve.P3, Curve.P2, 'angle2', 'length2', 0)];
  end
  else if Edge is TCurvePathObject then
  begin
    SetLength(Result, 2 * Length(Edge.Segments));
    for Index := 0 to High(Edge.Segments) do
    begin
      Curve := Edge.Segments[Index].Curve;
      Node := 'node' + IntToStr(Index + 1);
      NextNode := 'node' + IntToStr(Index + 2);
      Result[2 * Index] := MakeHandle(Edge, Curve.P0, Curve.P1, Node + '.angle', Node + '.lengthOut', 0);
      Result[2 * Index + 1] := MakeHandle(Edge, Curve.P3, Curve.P2, NextNode + '.angle', NextNode + '.lengthIn', 180);
    end;
  end;
end;

function CanDragHandle(Edge: TEdgeObject; const Handle: TCurveHandle; out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Result := Edge.Field(Handle.AngleField).IsLiteral and Edge.Field(Handle.LengthField).IsLiteral;
  if not Result then
    ErrorMessage := Format(rsDragHandleFormula, [Edge.DisplayName]);
end;

function DragHandle(Pattern: TPattern; Edge: TEdgeObject; const Handle: TCurveHandle; const Target: TVec2;
  out ErrorMessage: string): boolean;
var
  LengthText: string;
begin
  if not CanDragHandle(Edge, Handle, ErrorMessage) then
    Exit(False);
  LengthText := DraggedLength(Edge, Handle.LengthField, Sloper.Core.Geometry.Distance(Handle.Anchor, Target), Pattern.Units);
  // At the anchor, whatever unit the length is written in
  if LengthText = '0' + NUMBER_SUFFIX_NAMES[Edge.Field(Handle.LengthField).LiteralSuffix] then
    Exit(SetFields(Pattern, Edge, [Handle.LengthField], [LengthText], ErrorMessage));
  Result := SetFields(Pattern, Edge, [Handle.AngleField, Handle.LengthField],
    [RoundedText(NormalizeAngle(AngleBetween(Handle.Anchor, Target) - Handle.AngleOffset), DRAG_ANGLE_DECIMALS), LengthText],
    ErrorMessage);
end;

end.
