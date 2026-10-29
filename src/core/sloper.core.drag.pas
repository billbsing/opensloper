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

// Dragging points: which points can follow the mouse, and the formulas a
// drag writes. A drag only changes fields that are plain numbers, so a point
// placed by a formula (@waist/4) keeps its parametric intent and is locked.
// No LCL dependency.
unit Sloper.Core.Drag;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

const
  // Dragged values are rounded to these decimals: mm, degrees, ratio
  DragLengthDecimals = 1;
  DragAngleDecimals = 1;
  DragRatioDecimals = 4;

// Value rounded to Decimals as formula text, without "-0"
function RoundedText(Value: double; Decimals: integer): string;
// True when Point can be dragged: its type moves freely, and every field the
// drag would change is a plain number. Otherwise ErrorMessage says why.
function CanDrag(Point: TPointObject; out ErrorMessage: string): boolean;
// Sets Point's fields so it lies at Target, or as near as its operation
// allows (a point along an edge stays on the edge). Call inside a document
// change and evaluate afterwards. False, with ErrorMessage, when the point
// cannot be dragged.
function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;

resourcestring
  rsDragFormula = '%s is placed by a formula; change it in its properties';
  rsDragPlaced = '%s is placed by other objects and cannot be dragged';

implementation

uses
  SysUtils, Math, Sloper.Core.Evaluator, Sloper.Core.JSON;

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

function CanDrag(Point: TPointObject; out ErrorMessage: string): boolean;
var
  FieldName: string;
  Fields: TStringArray;
begin
  ErrorMessage := '';
  Fields := DragFields(Point);
  if Fields = nil then
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

function SetFields(Pattern: TPattern; Point: TPointObject; const Names, Texts: array of string; out ErrorMessage: string): boolean;
var
  Index: integer;
begin
  for Index := 0 to High(Names) do
    if not Pattern.SetFormula(Point, Names[Index], Texts[Index]) then
    begin
      ErrorMessage := Pattern.LastError;
      Exit(False);
    end;
  Result := True;
end;

function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;
var
  BaseNode: TEvalNode;
  Base: TVec2;
  Along: TAlongEdgePoint;
  Edge: TEdgeObject;
  Position, Offset, Distance, EdgeLength: double;
begin
  if not CanDrag(Point, ErrorMessage) then
    Exit(False);
  if Point is TFreePoint then
    Exit(SetFields(Pattern, Point, ['x', 'y'],
      [RoundedText(Target.X, DragLengthDecimals), RoundedText(Target.Y, DragLengthDecimals)], ErrorMessage));

  if Point is TOffsetPoint then
  begin
    BaseNode := Pattern.FindNode(TOffsetPoint(Point).Base);
    Base := TPointObject(BaseNode).Position;
    if TOffsetPoint(Point).Mode = omPolar then
      Exit(SetFields(Pattern, Point, ['length', 'angle'],
        [RoundedText(Sloper.Core.Geometry.Distance(Base, Target), DragLengthDecimals),
        RoundedText(AngleBetween(Base, Target), DragAngleDecimals)], ErrorMessage));
    Exit(SetFields(Pattern, Point, ['dx', 'dy'],
      [RoundedText(Target.X - Base.X, DragLengthDecimals), RoundedText(Target.Y - Base.Y, DragLengthDecimals)],
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
    Result := SetFields(Pattern, Point, ['value'], [RoundedText(Distance, DragLengthDecimals)], ErrorMessage)
  else if EdgeLength > 0 then
    Result := SetFields(Pattern, Point, ['value'], [RoundedText(Distance / EdgeLength, DragRatioDecimals)], ErrorMessage)
  else
    Result := True;
end;

end.
