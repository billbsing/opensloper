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

// A note: text drawn on the pattern and printed with its piece. It is anchored
// to a point, a place along an edge or a piece, plus an offset, so it follows
// the draft as measurements change; or free, at fixed coordinates. Its text,
// size and whether it prints are plain values; where it goes is formulas.
// See Annotations in the design document. No LCL dependency.
unit Sloper.Core.Note;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece;

const
  // The formula fields: the offset from the anchor, or the place of a free
  // note, both in mm; and how far along an edge, as a ratio from its start
  NoteDxField = 'dx';
  NoteDyField = 'dy';
  NoteXField = 'x';
  NoteYField = 'y';
  NotePositionField = 'position';
  // Points, at true print size
  DefaultNoteSize = 10;
  MaxNoteSize = 500;

type
  TNoteAnchor = (naFree, naPoint, naEdge, naPiece);

const
  // As written in pattern files and the Automation API
  NoteAnchorNames: array[TNoteAnchor] of string = ('free', 'point', 'edge', 'piece');

type
  TNoteObject = class(TDraftObject)
  private
    FAnchor: TNoteAnchor;
    FAnchorKey: string;
    FText: string;
    FSize: double;
    FPrint: boolean;
    FPosition, FAnchorPosition: TVec2;
    function AnchorAt(Context: TEvalContext; out At: TVec2): TEvalState;
  public
    // AAnchorKey is the point, edge or piece; empty for a free note
    constructor Create(const AKey: string; AAnchor: TNoteAnchor; const AAnchorKey: string);
    function InputKeys: TStringArray; override;
    procedure RedirectPoint(const OldKey, NewKey: string); override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    // Turns an anchored note free, taking fields x and y in place of its
    // offset; the caller sets their formulas
    procedure MakeFree;
    // The fields a drag of the note writes: x and y, or dx and dy
    function PlaceFields: TStringArray;
    // The first line of its text, to list it by
    function FirstLine: string;
    property Anchor: TNoteAnchor read FAnchor;
    property AnchorKey: string read FAnchorKey;
    // One or more lines, broken by line feeds
    property Text: string read FText write FText;
    // In points
    property Size: double read FSize write FSize;
    // False for a note only shown on screen, never printed or exported
    property Print: boolean read FPrint write FPrint;
    // Last good top left of its text
    property Position: TVec2 read FPosition;
    // Last good place it hangs from: the point, the place on the edge, the
    // piece's middle, or its own place when free
    property AnchorPosition: TVec2 read FAnchorPosition;
  end;

  TNoteObjectArray = array of TNoteObject;

resourcestring
  rsNoteNotAPiece = '%s is not a piece';
  rsNoteMissing = 'Uses object %s, which no longer exists';

implementation

constructor TNoteObject.Create(const AKey: string; AAnchor: TNoteAnchor; const AAnchorKey: string);
begin
  inherited Create(AKey);
  FAnchor := AAnchor;
  FAnchorKey := AAnchorKey;
  if FAnchor = naFree then
    FAnchorKey := '';
  FSize := DefaultNoteSize;
  FPrint := True;
  if FAnchor = naFree then
  begin
    AddField(NoteXField);
    AddField(NoteYField);
  end
  else
  begin
    if FAnchor = naEdge then
      AddField(NotePositionField);
    AddField(NoteDxField);
    AddField(NoteDyField);
  end;
end;

function TNoteObject.InputKeys: TStringArray;
begin
  Result := nil;
  if FAnchorKey <> '' then
    Result := [FAnchorKey];
end;

procedure TNoteObject.RedirectPoint(const OldKey, NewKey: string);
begin
  if FAnchor = naPoint then
    RedirectKey(FAnchorKey, OldKey, NewKey);
end;

function TNoteObject.TypeName: string;
begin
  Result := 'note';
end;

function TNoteObject.HasProperty(const Prop: string): boolean;
begin
  Result := False;
end;

function TNoteObject.PropertyValue(const Prop: string): double;
begin
  Result := 0;
end;

function TNoteObject.AnchorAt(Context: TEvalContext; out At: TVec2): TEvalState;
var
  Node: TEvalNode;
  Edge: TEdgeObject;
  Ratio: double;
begin
  At := Vec2(0, 0);
  Node := nil;
  if FAnchor <> naFree then
  begin
    Node := Context.FindNode(FAnchorKey);
    if not Assigned(Node) then
      Exit(Fail(esError, Format(rsNoteMissing, [FAnchorKey])));
  end;
  case FAnchor of
    naPoint:
    begin
      if not (Node is TPointObject) then
        Exit(Fail(esError, Format(rsDraftNotAPoint, [Node.DisplayName])));
      At := TPointObject(Node).Position;
    end;
    naEdge:
    begin
      if not (Node is TEdgeObject) then
        Exit(Fail(esError, Format(rsDraftNotAnEdge, [Node.DisplayName])));
      Edge := TEdgeObject(Node);
      if not EvalField(Context, NotePositionField, Ratio) then
        Exit(esError);
      if (Ratio < 0) or (Ratio > 1) then
        Exit(Fail(esInvalid, Format(rsDraftRatioRange, [FormatFloat('0.###', Ratio)])));
      At := Edge.PointAtLength(Ratio * Edge.Length);
    end;
    naPiece:
    begin
      if not (Node is TPieceObject) then
        Exit(Fail(esError, Format(rsNoteNotAPiece, [Node.DisplayName])));
      At := TPieceObject(Node).Middle;
    end;
  end;
  Result := esValid;
end;

function TNoteObject.Compute(Context: TEvalContext): TEvalState;
var
  Base: TVec2;
  First, Second: double;
begin
  if FAnchor = naFree then
  begin
    if not EvalField(Context, NoteXField, First) or not EvalField(Context, NoteYField, Second) then
      Exit(esError);
    FAnchorPosition := Vec2(First, Second);
    FPosition := FAnchorPosition;
    Exit(esValid);
  end;
  Result := AnchorAt(Context, Base);
  if Result <> esValid then
    Exit;
  if not EvalField(Context, NoteDxField, First) or not EvalField(Context, NoteDyField, Second) then
    Exit(esError);
  FAnchorPosition := Base;
  FPosition := Base + Vec2(First, Second);
end;

procedure TNoteObject.MakeFree;
begin
  if FAnchor = naFree then
    Exit;
  if FAnchor = naEdge then
    RemoveField(NotePositionField);
  RemoveField(NoteDxField);
  RemoveField(NoteDyField);
  AddField(NoteXField);
  AddField(NoteYField);
  FAnchor := naFree;
  FAnchorKey := '';
end;

function TNoteObject.PlaceFields: TStringArray;
begin
  if FAnchor = naFree then
    Result := [NoteXField, NoteYField]
  else
    Result := [NoteDxField, NoteDyField];
end;

function TNoteObject.FirstLine: string;
var
  Stop: integer;
begin
  Result := StringReplace(FText, #13, #10, [rfReplaceAll]);
  Stop := Pos(#10, Result);
  if Stop > 0 then
    Result := Copy(Result, 1, Stop - 1);
end;

end.
