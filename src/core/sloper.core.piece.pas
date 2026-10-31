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

  // The default seam allowance is the field "allowance"; an edge with its own
  // has a field such as "edge2.allowance", which exists only while it does
  TPieceObject = class(TDraftObject)
  private
    FPath: TPiecePath;
    FOutline: TVec2Array;
    FCutLine: TVec2Array;
    function BuildOutline(Context: TEvalContext; DefaultWidth: double; out Outline: TVec2Array; out Widths: TDoubleArray): TEvalState;
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
    function Area: double;
    function Perimeter: double;
    property Path: TPiecePath read FPath;
    // Last good seam line, closed without repeating its first point
    property Outline: TVec2Array read FOutline;
    // Last good cutting line, clockwise, closed without repeating its first point
    property CutLine: TVec2Array read FCutLine;
  end;

resourcestring
  rsPieceGap = 'There is a gap between %s and %s';
  rsPieceNoArea = 'The outline encloses no area';
  rsPieceNegativeAllowance = 'A seam allowance cannot be negative';
  rsPieceNoCutLine = 'No cutting line could be worked out';

implementation

uses
  Sloper.Core.Bezier;

constructor TPieceObject.Create(const AKey: string; const APath: TPiecePath);
begin
  inherited Create(AKey);
  FPath := Copy(APath);
  AddField(PieceAllowanceField);
end;

function TPieceObject.InputKeys: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FPath));
  for Index := 0 to High(FPath) do
    Result[Index] := FPath[Index].EdgeKey;
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
  out Widths: TDoubleArray): TEvalState;
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

function TPieceObject.Compute(Context: TEvalContext): TEvalState;
var
  Width: double;
  Points, Cut: TVec2Array;
  Widths: TDoubleArray;
begin
  if not EvalField(Context, PieceAllowanceField, Width) then
    Exit(esError);
  if Width < 0 then
    Exit(Fail(esInvalid, rsPieceNegativeAllowance));
  Result := BuildOutline(Context, Width, Points, Widths);
  if Result <> esValid then
    Exit;
  if Abs(SignedArea(Points)) < PieceJoinTolerance then
    Exit(Fail(esInvalid, rsPieceNoArea));
  if not OffsetOutline(Points, Widths, Cut) then
    Exit(Fail(esInvalid, rsPieceNoCutLine));
  FOutline := Points;
  FCutLine := Cut;
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

end.
