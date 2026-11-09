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

// Seams: edges that are sewn together, and whether their lengths agree. A seam
// is made by the user; see Seams in the design document. No LCL dependency.
unit Sloper.Core.Seam;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Draft, Sloper.Core.Piece;

const
  SeamEaseField = 'ease';
  SeamToleranceField = 'tolerance';
  DefaultSeamEase = '0';
  // Asks AddSeam for the pattern unit's starting tolerance (StartingLengths)
  DefaultSeamTolerance = '';

type
  TSeamEntry = record
    PieceKey, EdgeKey: string;
  end;

  // In order along the seam
  TSeamSide = array of TSeamEntry;

  // Ease is the length side B should have over side A. Side A runs the way
  // its pieces' paths run. Sewn edges normally run in opposite directions
  // around clockwise paths, so side B runs against its paths unless Reversed.
  TSeamObject = class(TDraftObject)
  private
    FSideA, FSideB: TSeamSide;
    FReversed: boolean;
    FLengthA, FLengthB, FEase, FTolerance: double;
    function SideLength(Context: TEvalContext; const Side: TSeamSide; out Total: double): TEvalState;
  public
    constructor Create(const AKey: string; const ASideA, ASideB: TSeamSide);
    function InputKeys: TStringArray; override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function FieldUnitKind(const AName: string): TFieldUnitKind; override;
    function UsesPiece(const PieceKey: string): boolean;
    function UsesEdge(const PieceKey, EdgeKey: string): boolean;
    // The piece's edge, split, becomes its parts, given in the order the
    // piece's path runs; each side takes them in its own direction
    procedure SplitEntry(const PieceKey, EdgeKey: string; const PathOrder: array of string);
    // The piece's two edges become one edge, where the first of them was
    procedure JoinEntries(const PieceKey, KeyA, KeyB, NewKey: string);
    // Length of side B over side A, from the last good evaluation
    function Difference: double;
    // How far Difference is from the ease; positive when side B is too long
    function Mismatch: double;
    // Whether the lengths are further apart than the tolerance allows
    function OutOfTolerance: boolean;
    // Whether the seam runs along this entry's edge from its start to its end
    function RunsForward(Piece: TPieceObject; const Entry: TSeamEntry; OnSideB: boolean): boolean;
    property SideA: TSeamSide read FSideA;
    property SideB: TSeamSide read FSideB;
    property Reversed: boolean read FReversed write FReversed;
    // From the last good evaluation
    property LengthA: double read FLengthA;
    property LengthB: double read FLengthB;
    property Ease: double read FEase;
    property Tolerance: double read FTolerance;
  end;

resourcestring
  rsSeamNotAPiece = '%s is not a piece';
  rsSeamNotInPiece = '%s is not part of %s';
  rsSeamOnFold = '%s is the fold of %s, so it cannot be in a seam';
  rsSeamNegativeTolerance = 'A seam''s tolerance cannot be negative';

implementation

uses
  Sloper.Core.Geometry;

constructor TSeamObject.Create(const AKey: string; const ASideA, ASideB: TSeamSide);
begin
  inherited Create(AKey);
  FSideA := Copy(ASideA);
  FSideB := Copy(ASideB);
  AddField(SeamEaseField);
  AddField(SeamToleranceField);
end;

function TSeamObject.InputKeys: TStringArray;

  procedure AddSide(const Side: TSeamSide);
  var
    Entry: TSeamEntry;
    InputKey: string;
    Known: boolean;
  begin
    for Entry in Side do
    begin
      Known := False;
      for InputKey in Result do
        Known := Known or (InputKey = Entry.PieceKey);
      if not Known then
        System.Insert(Entry.PieceKey, Result, Length(Result));
    end;
  end;

begin
  Result := nil;
  AddSide(FSideA);
  AddSide(FSideB);
end;

function TSeamObject.TypeName: string;
begin
  Result := 'seam';
end;

function TSeamObject.HasProperty(const Prop: string): boolean;
begin
  Result := False;
end;

function TSeamObject.PropertyValue(const Prop: string): double;
begin
  Result := 0;
end;

function TSeamObject.SideLength(Context: TEvalContext; const Side: TSeamSide; out Total: double): TEvalState;
var
  Entry: TSeamEntry;
  Node: TEvalNode;
  Piece: TPieceObject;
begin
  Total := 0;
  for Entry in Side do
  begin
    Node := Context.FindNode(Entry.PieceKey);
    if not (Node is TPieceObject) then
      Exit(Fail(esError, Format(rsSeamNotAPiece, [Entry.PieceKey])));
    Piece := TPieceObject(Node);
    Node := Context.FindNode(Entry.EdgeKey);
    if not (Node is TEdgeObject) then
      Exit(Fail(esError, Format(rsDraftNotAnEdge, [Entry.EdgeKey])));
    if Piece.PathIndexOf(Entry.EdgeKey) < 0 then
      Exit(Fail(esInvalid, Format(rsSeamNotInPiece, [Node.DisplayName, Piece.DisplayName])));
    if Piece.FoldEdgeKey = Entry.EdgeKey then
      Exit(Fail(esInvalid, Format(rsSeamOnFold, [Node.DisplayName, Piece.DisplayName])));
    Total := Total + TEdgeObject(Node).Length;
  end;
  Result := esValid;
end;

function TSeamObject.Compute(Context: TEvalContext): TEvalState;
var
  FirstLength, SecondLength, EaseValue, ToleranceValue: double;
begin
  Result := SideLength(Context, FSideA, FirstLength);
  if Result <> esValid then
    Exit;
  Result := SideLength(Context, FSideB, SecondLength);
  if Result <> esValid then
    Exit;
  if not EvalLength(Context, SeamEaseField, EaseValue) or not EvalLength(Context, SeamToleranceField, ToleranceValue) then
    Exit(esError);
  if ToleranceValue < 0 then
    Exit(Fail(esInvalid, rsSeamNegativeTolerance));
  FLengthA := FirstLength;
  FLengthB := SecondLength;
  FEase := EaseValue;
  FTolerance := ToleranceValue;
end;

function TSeamObject.UsesEdge(const PieceKey, EdgeKey: string): boolean;

  function InSide(const Side: TSeamSide): boolean;
  var
    Entry: TSeamEntry;
  begin
    Result := False;
    for Entry in Side do
      if (Entry.PieceKey = PieceKey) and (Entry.EdgeKey = EdgeKey) then
        Exit(True);
  end;

begin
  Result := InSide(FSideA) or InSide(FSideB);
end;

function TSeamObject.UsesPiece(const PieceKey: string): boolean;
var
  InputKey: string;
begin
  Result := False;
  for InputKey in InputKeys do
    if InputKey = PieceKey then
      Exit(True);
end;

function TSeamObject.Difference: double;
begin
  Result := FLengthB - FLengthA;
end;

function TSeamObject.Mismatch: double;
begin
  Result := Difference - FEase;
end;

function TSeamObject.OutOfTolerance: boolean;
begin
  Result := Abs(Mismatch) > FTolerance + DefaultTolerance;
end;

function TSeamObject.RunsForward(Piece: TPieceObject; const Entry: TSeamEntry; OnSideB: boolean): boolean;
var
  AlongPath: boolean;
begin
  AlongPath := not Piece.Path[Piece.PathIndexOf(Entry.EdgeKey)].Reversed;
  if OnSideB and not FReversed then
    Result := not AlongPath
  else
    Result := AlongPath;
end;

function TSeamObject.FieldUnitKind(const AName: string): TFieldUnitKind;
begin
  if (AName = SeamEaseField) or (AName = SeamToleranceField) then
    Result := fkLength
  else
    Result := inherited FieldUnitKind(AName);
end;

procedure TSeamObject.SplitEntry(const PieceKey, EdgeKey: string; const PathOrder: array of string);

  procedure SplitIn(var Side: TSeamSide; WithPath: boolean);
  var
    Index, Part: integer;
    Entry: TSeamEntry;
  begin
    for Index := High(Side) downto 0 do
      if (Side[Index].PieceKey = PieceKey) and (Side[Index].EdgeKey = EdgeKey) then
      begin
        Delete(Side, Index, 1);
        Entry.PieceKey := PieceKey;
        for Part := 0 to High(PathOrder) do
        begin
          if WithPath then
            Entry.EdgeKey := PathOrder[Part]
          else
            Entry.EdgeKey := PathOrder[High(PathOrder) - Part];
          Insert(Entry, Side, Index + Part);
        end;
      end;
  end;

begin
  SplitIn(FSideA, True);
  SplitIn(FSideB, FReversed);
end;

procedure TSeamObject.JoinEntries(const PieceKey, KeyA, KeyB, NewKey: string);

  procedure JoinIn(var Side: TSeamSide);
  var
    Index: integer;
    Found: boolean;
  begin
    Found := False;
    Index := 0;
    while Index <= High(Side) do
      if (Side[Index].PieceKey = PieceKey) and ((Side[Index].EdgeKey = KeyA) or (Side[Index].EdgeKey = KeyB)) then
      begin
        if Found then
          Delete(Side, Index, 1)
        else
        begin
          Side[Index].EdgeKey := NewKey;
          Found := True;
          Inc(Index);
        end;
      end
      else
        Inc(Index);
  end;

begin
  JoinIn(FSideA);
  JoinIn(FSideB);
end;

end.
