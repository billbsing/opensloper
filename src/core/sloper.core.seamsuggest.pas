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

// Suggest seams: pairs of piece edges that might be sewn together, for the user
// to choose from. Nothing here can know, so nothing is stored. No LCL dependency.
unit Sloper.Core.SeamSuggest;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern, Sloper.Core.Seam;

const
  // Edges on different pieces this close in length (in mm) are suggested
  SuggestLengthLimit = 1;

type
  TSeamSuggestion = record
    First, Second: TSeamEntry;
    // The same edge on two pieces, the likeliest kind of pair
    Shared: boolean;
    // How far apart the lengths are
    Difference: double;
  end;

  TSeamSuggestionArray = array of TSeamSuggestion;

// Edges shared by two pieces, then edges by how close their lengths are. Fold
// edges and edges already in a seam are left out. Call after Evaluate.
function SuggestSeams(Pattern: TPattern): TSeamSuggestionArray;

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Piece;

type
  TCandidate = record
    Entry: TSeamEntry;
    Length: double;
  end;

function InASeam(Pattern: TPattern; const PieceKey, EdgeKey: string): boolean;
var
  Index: integer;
begin
  Result := False;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TSeamObject) and TSeamObject(Pattern.Objects[Index]).UsesEdge(PieceKey, EdgeKey) then
      Exit(True);
end;

function FreeEdges(Pattern: TPattern): specialize TArray<TCandidate>;
var
  Index: integer;
  Piece: TPieceObject;
  PathEntry: TPieceEdge;
  Candidate: TCandidate;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TPieceObject) or (Pattern.Objects[Index].State <> esValid) then
      Continue;
    Piece := TPieceObject(Pattern.Objects[Index]);
    for PathEntry in Piece.Path do
    begin
      if (PathEntry.EdgeKey = Piece.FoldEdgeKey) or InASeam(Pattern, Piece.Key, PathEntry.EdgeKey) then
        Continue;
      Candidate.Entry.PieceKey := Piece.Key;
      Candidate.Entry.EdgeKey := PathEntry.EdgeKey;
      Candidate.Length := TEdgeObject(Pattern.FindNode(PathEntry.EdgeKey)).Length;
      Insert(Candidate, Result, System.Length(Result));
    end;
  end;
end;

function ComesBefore(const A, B: TSeamSuggestion): boolean;
begin
  if A.Shared <> B.Shared then
    Exit(A.Shared);
  Result := A.Difference < B.Difference;
end;

// Keeps equal suggestions in the order they were found, so the list is stable
procedure InsertInOrder(var List: TSeamSuggestionArray; const Item: TSeamSuggestion);
var
  Place: integer;
begin
  Place := System.Length(List);
  while (Place > 0) and ComesBefore(Item, List[Place - 1]) do
    Dec(Place);
  Insert(Item, List, Place);
end;

function SuggestSeams(Pattern: TPattern): TSeamSuggestionArray;
var
  Edges: specialize TArray<TCandidate>;
  Index, Other: integer;
  Item: TSeamSuggestion;
begin
  Result := nil;
  Edges := FreeEdges(Pattern);
  for Index := 0 to High(Edges) do
    for Other := Index + 1 to High(Edges) do
    begin
      if Edges[Index].Entry.PieceKey = Edges[Other].Entry.PieceKey then
        Continue;
      Item.First := Edges[Index].Entry;
      Item.Second := Edges[Other].Entry;
      Item.Shared := Item.First.EdgeKey = Item.Second.EdgeKey;
      Item.Difference := Abs(Edges[Index].Length - Edges[Other].Length);
      if Item.Shared or (Item.Difference <= SuggestLengthLimit) then
        InsertInOrder(Result, Item);
    end;
end;

end.
