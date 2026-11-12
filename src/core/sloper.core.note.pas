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
// the draft as measurements change; or free, at fixed coordinates. A note with
// a leader is a callout: a line from its text to the place it hangs from. Its
// text may hold draft values, {=Line_A_B.length}, each a formula field
// (value1, value2 and so on), so they follow the draft and renames. Its size,
// alignment, box and whether it prints are plain values; where it goes is
// formulas. Its font is a family name with bold and italic, the default
// sans-serif when the name is empty. See Annotations in the design document.
// No LCL dependency.
unit Sloper.Core.Note;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Formula, Sloper.Core.Geometry, Sloper.Core.Draft,
  Sloper.Core.Piece;

const
  // The formula fields: the offset from the anchor, or the place of a free
  // note, both in mm; and how far along an edge, as a ratio from its start
  NOTE_DX_FIELD = 'dx';
  NOTE_DY_FIELD = 'dy';
  NOTE_X_FIELD = 'x';
  NOTE_Y_FIELD = 'y';
  NOTE_POSITION_FIELD = 'position';
  // A draft value's field is this with its number from 1: value1, value2
  NOTE_VALUE_FIELD = 'value';
  // Not a formula field: names the text when a draft value in it is refused
  NOTE_TEXT_FIELD = 'text';
  // Points, at true print size
  DEFAULT_NOTE_SIZE = 10;
  MAX_NOTE_SIZE = 500;
  // In mm, at true size: an arrow head's length, and a dot's radius
  LEADER_ARROW_LENGTH = 3;
  LEADER_DOT_RADIUS = 0.8;
  // Stands for a draft value in a note's template; never typed
  VALUE_MARK = #1;
  // The longest font family name kept
  MAX_FONT_NAME_LENGTH = 64;

type
  TNoteAnchor = (naFree, naPoint, naEdge, naPiece);
  // nlNone is a plain note; the others make it a callout, with a leader
  // ending in an arrow, a dot or nothing at the tip
  TNoteLeader = (nlNone, nlArrow, nlDot, nlLine);
  // How the lines of a note sit within its widest line
  TTextAlign = (taLeft, taCentre, taRight);

  // The font text is drawn in: a family name, empty for the default
  // sans-serif (Helvetica in PDF), and its style
  TTextStyle = record
    Font: string;
    Bold, Italic: boolean;
  end;

const
  // As written in pattern and layout files and the Automation API
  NOTE_ANCHOR_NAMES: array[TNoteAnchor] of string = ('free', 'point', 'edge', 'piece');
  NOTE_LEADER_NAMES: array[TNoteLeader] of string = ('none', 'arrow', 'dot', 'line');
  TEXT_ALIGN_NAMES: array[TTextAlign] of string = ('left', 'centre', 'right');

type
  TNoteObject = class(TDraftObject)
  private
    FAnchor: TNoteAnchor;
    FAnchorKey: string;
    // The text with VALUE_MARK where each draft value goes
    FTemplate: string;
    FValues: array of double;
    FSize: double;
    FPrint: boolean;
    FLeader: TNoteLeader;
    FAlign: TTextAlign;
    FBoxed: boolean;
    FStyle: TTextStyle;
    FPosition, FAnchorPosition: TVec2;
    function AnchorAt(Context: TEvalContext; out At: TVec2): TEvalState;
    function GetValueCount: integer;
    procedure AddPlaceFields;
    procedure RemovePlaceFields;
    // The template with each value's text in turn
    function Filled(const Parts: array of string): string;
  public
    // AAnchorKey is the point, edge or piece; empty for a free note
    constructor Create(const AKey: string; AAnchor: TNoteAnchor; const AAnchorKey: string);
    function InputKeys: TStringArray; override;
    procedure RedirectPoint(const OldKey, NewKey: string); override;
    function TypeName: string; override;
    function HasProperty(const Prop: string): boolean; override;
    function PropertyValue(const Prop: string): double; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function FieldUnitKind(const AName: string): TFieldUnitKind; override;
    // Turns an anchored note free, taking fields x and y in place of its
    // offset, and drops its leader; the caller sets their formulas
    procedure MakeFree;
    // Hangs it from another anchor, with new place fields (position for an
    // edge, dx and dy) for the caller to set; its draft values stay
    procedure Reanchor(AAnchor: TNoteAnchor; const AAnchorKey: string);
    // The fields a drag of the note writes: x and y, or dx and dy
    function PlaceFields: TStringArray;
    function ValueField(Index: integer): string;
    // Text with no draft values: {= is kept as typed
    procedure SetPlainText(const AText: string);
    // Takes a template and one parsed formula per VALUE_MARK in it, owning them
    procedure SetValues(const ATemplate: string; const Formulas: array of TFormula);
    // As read from a file: {=...} in stored ID form. One that does not parse
    // is kept as text, and the note shows an error.
    procedure SetStoredText(const AText: string);
    // The text as saved, each draft value as {=formula} in ID form
    function StoredText: string;
    // The text as the user edits it, each draft value as {=formula} with names
    function DisplayText(Resolver: TNameResolver): string;
    // The text as drawn and printed, each draft value its last good value
    function ShownText: string;
    // The first line of the shown text, to list it by
    function FirstLine: string;
    property Anchor: TNoteAnchor read FAnchor;
    property AnchorKey: string read FAnchorKey;
    property ValueCount: integer read GetValueCount;
    // In points
    property Size: double read FSize write FSize;
    // False for a note only shown on screen, never printed or exported
    property Print: boolean read FPrint write FPrint;
    // A callout's leader; nlNone for a plain note. A free note has none.
    property Leader: TNoteLeader read FLeader write FLeader;
    property Align: TTextAlign read FAlign write FAlign;
    // Drawn on a white box, so it reads over lines
    property Boxed: boolean read FBoxed write FBoxed;
    // Its font; the caller checks the name with CheckFontName
    property Style: TTextStyle read FStyle write FStyle;
    // Last good top left of its text
    property Position: TVec2 read FPosition;
    // Last good place it hangs from, where a callout's tip is: the point, the
    // place on the edge, the piece's middle, or its own place when free
    property AnchorPosition: TVec2 read FAnchorPosition;
  end;

  TNoteObjectArray = array of TNoteObject;

// Splits Text at each {=...}, braces inside counted, into a template with
// VALUE_MARK for each and the formulas' text. False when a {= is not closed,
// with ErrorPos at it.
function SplitDraftValues(const Text: string; out Template: string; out Expressions: TStringArray; out ErrorPos: integer): boolean;
// The draft value as shown in text: to a tenth, without "-0"
function DraftValueText(Value: double): string;
// Value to Decimals places as a short number, without "-0"
function RoundedNumberText(Value: double; Decimals: integer): string;
// Where a leader leaves the box Frame towards Tip: the nearest place on its
// edge. False when Tip lies inside it, so there is no leader to draw.
function LeaderStart(const Frame: TRect2; const Tip: TVec2; out Start: TVec2): boolean;
// The leader from Start to Tip as strokes: the line, and for an arrow its head
function LeaderStrokes(const Start, Tip: TVec2; Leader: TNoteLeader): TLine2Array;
// A dot's outline as a polygon, for writers without circles
function LeaderDot(const Tip: TVec2): TVec2Array;
// Where a line LineWidth wide starts in a box Left .. Left + BoxWidth
function AlignedLeft(Left, BoxWidth, LineWidth: double; Align: TTextAlign): double;
// The box grown by the white box's margin
function PaddedBox(const Box: TRect2): TRect2;
function SameTextStyle(const First, Second: TTextStyle): boolean;
// A font name as kept, trimmed; False with Reason when it is too long or holds
// a character that would break a file or an SVG attribute
function CheckFontName(const AName: string; out Kept, Reason: string): boolean;

resourcestring
  rsNoteNotAPiece = '%s is not a piece';
  rsNoteMissing = 'Uses object %s, which no longer exists';
  rsNoteUnclosed = 'A {= has no closing }';
  rsNoteFontLong = 'A font name can have at most %d characters';
  rsNoteFontCharacter = 'A font name cannot hold %s';
  rsNoteFontControl = 'A font name cannot hold a line break or tab';

implementation

uses
  Math, Sloper.Core.JSON;

const
  DOT_SIDES = 12;
  UNKNOWN = '?';
  // The white box's margin around the text, in mm at true size
  NOTE_BOX_PADDING = 1;
  // Either side of the leader, in degrees
  LEADER_ARROW_SPREAD = 25;
  // Draft values are shown to a tenth
  NOTE_VALUE_DECIMALS = 1;
  // Starts a draft value in a note's stored and shown text
  DRAFT_VALUE_OPEN = '{=';
  PLACE_FIELD_NAMES: array[0..4] of string = (NOTE_X_FIELD, NOTE_Y_FIELD, NOTE_POSITION_FIELD, NOTE_DX_FIELD, NOTE_DY_FIELD);
  // Separate families in SVG and CSS, or quote or escape in SVG and PDF
  FONT_NAME_FORBIDDEN = [',', ';', '"', '''', '<', '>', '&', '\', '(', ')', '{', '}'];

function SplitDraftValues(const Text: string; out Template: string; out Expressions: TStringArray; out ErrorPos: integer): boolean;
var
  Index, Depth, Start: integer;
begin
  Template := '';
  Expressions := nil;
  ErrorPos := 0;
  Index := 1;
  while Index <= Length(Text) do
  begin
    if (Text[Index] = '{') and (Index < Length(Text)) and (Text[Index + 1] = '=') then
    begin
      Start := Index;
      Depth := 1;
      Inc(Index, 2);
      while (Index <= Length(Text)) and (Depth > 0) do
      begin
        if Text[Index] = '{' then
          Inc(Depth)
        else if Text[Index] = '}' then
          Dec(Depth);
        Inc(Index);
      end;
      if Depth > 0 then
      begin
        ErrorPos := Start;
        Exit(False);
      end;
      Insert(Trim(Copy(Text, Start + 2, Index - Start - 3)), Expressions, Length(Expressions));
      Template := Template + VALUE_MARK;
    end
    else
    begin
      if Text[Index] <> VALUE_MARK then
        Template := Template + Text[Index];
      Inc(Index);
    end;
  end;
  Result := True;
end;

// RoundTo leaves binary noise (135.20000000000002), which the shortest
// round-trip form would print; dividing a whole number does not
function RoundedNumberText(Value: double; Decimals: integer): string;
var
  Scale, Rounded: double;
begin
  Scale := IntPower(10, Decimals);
  Rounded := Round(Value * Scale) / Scale;
  if Rounded = 0 then
    Rounded := 0;
  Result := FormatJSONFloat(Rounded);
end;

function DraftValueText(Value: double): string;
begin
  Result := RoundedNumberText(Value, NOTE_VALUE_DECIMALS);
end;

function LeaderStart(const Frame: TRect2; const Tip: TVec2; out Start: TVec2): boolean;
begin
  Start := Vec2(EnsureRange(Tip.X, Frame.MinX, Frame.MaxX), EnsureRange(Tip.Y, Frame.MinY, Frame.MaxY));
  Result := Distance(Start, Tip) > DEFAULT_TOLERANCE;
end;

function LeaderStrokes(const Start, Tip: TVec2; Leader: TNoteLeader): TLine2Array;
var
  Back: double;
begin
  Result := nil;
  if Leader = nlNone then
    Exit;
  Result := [Line2(Start, Tip)];
  if Leader <> nlArrow then
    Exit;
  // Screen angles turn anticlockwise with y down, so the direction back
  // from the tip is measured from the tip towards the start
  Back := RadToDeg(ArcTan2(-(Start.Y - Tip.Y), Start.X - Tip.X));
  Insert(Line2(Tip, PolarPoint(Tip, LEADER_ARROW_LENGTH, Back + LEADER_ARROW_SPREAD)), Result, Length(Result));
  Insert(Line2(Tip, PolarPoint(Tip, LEADER_ARROW_LENGTH, Back - LEADER_ARROW_SPREAD)), Result, Length(Result));
end;

function LeaderDot(const Tip: TVec2): TVec2Array;
var
  Side: integer;
begin
  Result := nil;
  SetLength(Result, DOT_SIDES);
  for Side := 0 to DOT_SIDES - 1 do
    Result[Side] := PolarPoint(Tip, LEADER_DOT_RADIUS, Side * 360 / DOT_SIDES);
end;

function AlignedLeft(Left, BoxWidth, LineWidth: double; Align: TTextAlign): double;
begin
  case Align of
    taCentre: Result := Left + (BoxWidth - LineWidth) / 2;
    taRight: Result := Left + BoxWidth - LineWidth;
    else
      Result := Left;
  end;
end;

function PaddedBox(const Box: TRect2): TRect2;
begin
  Result.MinX := Box.MinX - NOTE_BOX_PADDING;
  Result.MinY := Box.MinY - NOTE_BOX_PADDING;
  Result.MaxX := Box.MaxX + NOTE_BOX_PADDING;
  Result.MaxY := Box.MaxY + NOTE_BOX_PADDING;
end;

function SameTextStyle(const First, Second: TTextStyle): boolean;
begin
  Result := SameText(First.Font, Second.Font) and (First.Bold = Second.Bold) and (First.Italic = Second.Italic);
end;

function CheckFontName(const AName: string; out Kept, Reason: string): boolean;
var
  Letter: char;
begin
  Kept := Trim(AName);
  Reason := '';
  if Length(UTF8Decode(Kept)) > MAX_FONT_NAME_LENGTH then
  begin
    Reason := Format(rsNoteFontLong, [MAX_FONT_NAME_LENGTH]);
    Exit(False);
  end;
  for Letter in Kept do
    if (Letter < ' ') or (Letter in FONT_NAME_FORBIDDEN) then
    begin
      if Letter < ' ' then
        Reason := rsNoteFontControl
      else
        Reason := Format(rsNoteFontCharacter, [Letter]);
      Exit(False);
    end;
  Result := True;
end;

{ TNoteObject }

constructor TNoteObject.Create(const AKey: string; AAnchor: TNoteAnchor; const AAnchorKey: string);
begin
  inherited Create(AKey);
  FAnchor := AAnchor;
  FAnchorKey := AAnchorKey;
  if FAnchor = naFree then
    FAnchorKey := '';
  FSize := DEFAULT_NOTE_SIZE;
  FPrint := True;
  AddPlaceFields;
end;

procedure TNoteObject.AddPlaceFields;
begin
  if FAnchor = naFree then
  begin
    AddField(NOTE_X_FIELD);
    AddField(NOTE_Y_FIELD);
  end
  else
  begin
    if FAnchor = naEdge then
      AddField(NOTE_POSITION_FIELD);
    AddField(NOTE_DX_FIELD);
    AddField(NOTE_DY_FIELD);
  end;
end;

procedure TNoteObject.RemovePlaceFields;
var
  FieldName: string;
begin
  for FieldName in PLACE_FIELD_NAMES do
    if Assigned(Field(FieldName)) then
      RemoveField(FieldName);
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

function TNoteObject.GetValueCount: integer;
begin
  Result := Length(FValues);
end;

function TNoteObject.ValueField(Index: integer): string;
begin
  Result := NOTE_VALUE_FIELD + IntToStr(Index + 1);
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
      if not EvalField(Context, NOTE_POSITION_FIELD, Ratio) then
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

// The values are worked out first, so a failing one keeps the note where it was
function TNoteObject.Compute(Context: TEvalContext): TEvalState;
var
  Base, Offset: TVec2;
  First, Second: double;
  Values: array of double;
  Index: integer;
begin
  Values := nil;
  SetLength(Values, Length(FValues));
  for Index := 0 to High(Values) do
    if not EvalField(Context, ValueField(Index), Values[Index]) then
      Exit(esError);
  if FAnchor = naFree then
  begin
    if not EvalLength(Context, NOTE_X_FIELD, First) or not EvalLength(Context, NOTE_Y_FIELD, Second) then
      Exit(esError);
    Base := Vec2(First, Second);
    Offset := Vec2(0, 0);
  end
  else
  begin
    Result := AnchorAt(Context, Base);
    if Result <> esValid then
      Exit;
    if not EvalLength(Context, NOTE_DX_FIELD, First) or not EvalLength(Context, NOTE_DY_FIELD, Second) then
      Exit(esError);
    Offset := Vec2(First, Second);
  end;
  FValues := Values;
  FAnchorPosition := Base;
  FPosition := Base + Offset;
  Result := esValid;
end;

procedure TNoteObject.MakeFree;
begin
  FLeader := nlNone;
  if FAnchor = naFree then
    Exit;
  RemovePlaceFields;
  FAnchor := naFree;
  FAnchorKey := '';
  AddPlaceFields;
end;

procedure TNoteObject.Reanchor(AAnchor: TNoteAnchor; const AAnchorKey: string);
begin
  RemovePlaceFields;
  FAnchor := AAnchor;
  FAnchorKey := AAnchorKey;
  if FAnchor = naFree then
  begin
    FAnchorKey := '';
    FLeader := nlNone;
  end;
  AddPlaceFields;
end;

function TNoteObject.PlaceFields: TStringArray;
begin
  if FAnchor = naFree then
    Result := [NOTE_X_FIELD, NOTE_Y_FIELD]
  else
    Result := [NOTE_DX_FIELD, NOTE_DY_FIELD];
end;

procedure TNoteObject.SetPlainText(const AText: string);
begin
  SetValues(StringReplace(AText, VALUE_MARK, '', [rfReplaceAll]), []);
end;

procedure TNoteObject.SetValues(const ATemplate: string; const Formulas: array of TFormula);
var
  Index: integer;
begin
  for Index := 0 to High(FValues) do
    RemoveField(ValueField(Index));
  FValues := nil;
  SetLength(FValues, Length(Formulas));
  for Index := 0 to High(Formulas) do
  begin
    AddField(ValueField(Index));
    ReplaceField(ValueField(Index), Formulas[Index]);
    FValues[Index] := NaN;
  end;
  FTemplate := ATemplate;
end;

procedure TNoteObject.SetStoredText(const AText: string);
var
  Template: string;
  Expressions: TStringArray;
  Formulas: array of TFormula;
  ErrorPos, Index: integer;
begin
  if not SplitDraftValues(AText, Template, Expressions, ErrorPos) then
  begin
    SetPlainText(AText);
    Exit;
  end;
  Formulas := nil;
  SetLength(Formulas, Length(Expressions));
  for Index := 0 to High(Expressions) do
  begin
    Formulas[Index] := TFormula.Create;
    Formulas[Index].ParseStored(Expressions[Index]);
  end;
  SetValues(Template, Formulas);
end;

function TNoteObject.Filled(const Parts: array of string): string;
var
  Index, Part: integer;
begin
  Result := '';
  Part := 0;
  for Index := 1 to Length(FTemplate) do
    if (FTemplate[Index] = VALUE_MARK) and (Part <= High(Parts)) then
    begin
      Result := Result + Parts[Part];
      Inc(Part);
    end
    else
      Result := Result + FTemplate[Index];
end;

function TNoteObject.StoredText: string;
var
  Parts: TStringArray;
  Index: integer;
begin
  Parts := nil;
  SetLength(Parts, Length(FValues));
  for Index := 0 to High(Parts) do
    Parts[Index] := DRAFT_VALUE_OPEN + Field(ValueField(Index)).StoredText + '}';
  Result := Filled(Parts);
end;

function TNoteObject.DisplayText(Resolver: TNameResolver): string;
var
  Parts: TStringArray;
  Index: integer;
begin
  Parts := nil;
  SetLength(Parts, Length(FValues));
  for Index := 0 to High(Parts) do
    Parts[Index] := DRAFT_VALUE_OPEN + Field(ValueField(Index)).DisplayText(Resolver) + '}';
  Result := Filled(Parts);
end;

function TNoteObject.ShownText: string;
var
  Parts: TStringArray;
  Index: integer;
begin
  Parts := nil;
  SetLength(Parts, Length(FValues));
  for Index := 0 to High(Parts) do
    if IsNan(FValues[Index]) then
      Parts[Index] := UNKNOWN
    else
      Parts[Index] := DraftValueText(FValues[Index]);
  Result := Filled(Parts);
end;

function TNoteObject.FirstLine: string;
var
  Stop: integer;
begin
  Result := StringReplace(ShownText, #13, #10, [rfReplaceAll]);
  Stop := Pos(#10, Result);
  if Stop > 0 then
    Result := Copy(Result, 1, Stop - 1);
end;

// The place is in lengths, the position along an edge a ratio, and a draft
// value is whatever its formula makes it
function TNoteObject.FieldUnitKind(const AName: string): TFieldUnitKind;
begin
  if AName = NOTE_POSITION_FIELD then
    Result := fkNumber
  else if AName.StartsWith(NOTE_VALUE_FIELD) then
    Result := fkFree
  else
    Result := inherited FieldUnitKind(AName);
end;

end.
