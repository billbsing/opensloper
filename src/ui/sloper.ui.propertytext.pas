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

// Text the properties panel works out from the pattern: the pieces a marking
// is on, what a note hangs from, an edge allowance's caption, and a note's
// text as typed. Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.PropertyText;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Note, Sloper.Core.Pattern;

// The pieces a marking line or a marked point prints on, by name
function MarkedOnText(Pattern: TPattern; DraftObject: TDraftObject): string;
// What a note hangs from: a point, an edge, a piece, or nothing
function NoteAnchorText(Pattern: TPattern; Note: TNoteObject): string;
// The caption of an edge's own allowance, named after its edge, or '' when
// the field is not one
function EdgeAllowanceCaption(Pattern: TPattern; Piece: TPieceObject; const FieldName: string): string;
// A note's text as typed in a multi-line field: its line breaks become line
// feeds, and those at the end go, since the field adds one after the last line
function NoteTextFromField(const AText: string): string;

resourcestring
  rsPropMarkedOnNone = 'No piece';
  rsPropNotMarking = '-';
  rsPropNoteAnchorPoint = 'Point %s';
  rsPropNoteAnchorEdge = '%s';
  rsPropNoteAnchorPiece = 'Piece %s';
  rsPropNoteAnchorFree = 'Nothing (free)';
  rsPropEdgeAllowance = 'Allowance, %s';

implementation

uses
  SysUtils, Sloper.Core.Evaluator;

function MarkedOnText(Pattern: TPattern; DraftObject: TDraftObject): string;
var
  Piece: TPieceObject;
begin
  if not Pattern.IsMarking(DraftObject) then
    Exit(rsPropNotMarking);
  Result := '';
  for Piece in Pattern.PiecesWithMarking(DraftObject.Key) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Piece.DisplayName;
  end;
  if Result = '' then
    Result := rsPropMarkedOnNone;
end;

function NoteAnchorText(Pattern: TPattern; Note: TNoteObject): string;
var
  Node: TEvalNode;
begin
  Node := Pattern.FindNode(Note.AnchorKey);
  if (Note.Anchor = naFree) or not Assigned(Node) then
    Exit(rsPropNoteAnchorFree);
  case Note.Anchor of
    naPoint: Result := Format(rsPropNoteAnchorPoint, [Node.DisplayName]);
    naEdge: Result := Format(rsPropNoteAnchorEdge, [Node.DisplayName]);
    else
      Result := Format(rsPropNoteAnchorPiece, [Node.DisplayName]);
  end;
end;

function EdgeAllowanceCaption(Pattern: TPattern; Piece: TPieceObject; const FieldName: string): string;
var
  PathIndex: integer;
begin
  PathIndex := Piece.OverridePathIndex(FieldName);
  if PathIndex < 0 then
    Exit('');
  Result := Format(rsPropEdgeAllowance, [Pattern.FindNode(Piece.Path[PathIndex].EdgeKey).DisplayName]);
end;

function NoteTextFromField(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  while (Result <> '') and (Result[Length(Result)] = #10) do
    SetLength(Result, Length(Result) - 1);
end;

end.
