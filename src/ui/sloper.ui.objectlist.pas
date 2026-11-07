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

// What the objects and variables panels list: a row of text for each, narrowed
// by a filter and a search, and how clicks change the selection. Also the captions
// the panels share for object types and formula fields. Kept free of the LCL
// so it can be unit-tested.
unit Sloper.UI.ObjectList;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Measurements, Sloper.Core.PatternCheck, Sloper.Core.Variables, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Seam, Sloper.Core.SeamSuggest, Sloper.Core.Note, Sloper.Core.Units, Sloper.Core.Geometry;

type
  // ofPieces: pieces and seams; ofNotes: notes; ofProblems: anything not
  // valid, seams out of tolerance and pieces with no fabric
  TObjectFilter = (ofAll, ofPoints, ofEdges, ofPieces, ofNotes, ofProblems);

  TObjectRow = record
    Key: string;
    Name: string;
    Operation: string;
    Value: string;
    Formulas: string;
    State: TEvalState;
    StateText: string;
    // A note's whole text, which search looks through; empty for the rest
    Text: string;
  end;
  TObjectRowArray = array of TObjectRow;

  TVariableRow = record
    Key: string;
    Name: string;
    Formula: string;
    Value: string;
    Description: string;
    State: TEvalState;
    StateText: string;
  end;
  TVariableRowArray = array of TVariableRow;

  TMeasurementRow = record
    Key: string;
    Value: string;
    Description: string;
    // The pattern uses this key, but the set does not have it
    Missing: boolean;
  end;
  TMeasurementRowArray = array of TMeasurementRow;

// Caption for a formula field, such as "Start angle" for angle1
function FieldCaption(const FieldName: string): string;
// What kind of object this is, such as "Offset point"
function TypeCaption(Node: TEvalNode): string;
function StateCaption(State: TEvalState): string;
// What the object computes to: a position or a length, in AUnit. Empty before
// it is computed.
function ResultText(DraftObject: TDraftObject; AUnit: TMeasureUnit): string;
// A position as "12.5, 30 cm"
function PositionText(const Position: TVec2; AUnit: TMeasureUnit): string;
// Each entry of a seam's side, as "Front: Line_A_B"
function SeamSideText(Pattern: TPattern; const Side: TSeamSide): string;
// The difference between a seam's sides, with what is expected
function SeamDifferenceText(Seam: TSeamObject; AUnit: TMeasureUnit): string;
// One row of the Suggest Seams list
function SuggestionCaption(Pattern: TPattern; const Item: TSeamSuggestion): string;
function ObjectRow(Pattern: TPattern; DraftObject: TDraftObject): TObjectRow;
// The objects passing Filter whose name, operation or formulas contain Search,
// ignoring case, in pattern order.
function ObjectRows(Pattern: TPattern; Filter: TObjectFilter; const Search: string): TObjectRowArray;
function VariableRow(Pattern: TPattern; Variable: TVariable): TVariableRow;
// The variables whose name, formula or description contain Search, ignoring case
function VariableRows(Pattern: TPattern; const Search: string): TVariableRowArray;
// The set's measurements whose key or description contain Search, ignoring
// case, then any the pattern uses that the set lacks. Set may be nil.
function MeasurementRows(Pattern: TPattern; MeasurementSet: TMeasurementSet; const Search: string): TMeasurementRowArray;
// What a small edit did, for the status bar
function MeasurementChangeText(const Change: TMeasurementChange; const FileName: string): string;
// The selection after clicking Clicked. Toggle adds or removes it; Extend
// selects from Anchor to it in Visible, the keys in list order, or just it
// when Anchor is not listed.
function SelectionAfterClick(const Visible, Selected: TStringArray; const Anchor, Clicked: string;
  Toggle, Extend: boolean): TStringArray;

resourcestring
  rsObjectPosition = '%s, %s %s';
  rsObjectSeamLengths = 'A %s, B %s';
  rsObjectSeamDifference = '%s, expected %s';
  rsObjectSeamEntry = '%s: %s';
  rsObjectSeamEntryGap = ', ';
  rsSuggestShared = '%s and %s, shared edge';
  rsSuggestLengths = '%s and %s, %s apart';
  rsObjectFormula = '%s = %s';
  rsObjectFormulaGap = '; ';
  rsMeasurementChanged = '@%s %s → %s mm saved to %s';
  rsMeasurementAdded = '@%s %s mm added to %s';
  rsStateValid = 'Valid';
  rsStateError = 'Error';
  rsStateInvalid = 'Invalid';
  rsStateBlocked = 'Blocked';
  rsFieldX = 'X';
  rsFieldY = 'Y';
  rsFieldLength = 'Length';
  rsFieldAngle = 'Angle';
  rsFieldDX = 'Across';
  rsFieldDY = 'Down';
  rsFieldValue = 'Distance or ratio';
  rsFieldCount = 'Count';
  rsFieldRadius = 'Radius';
  rsFieldRadiusA = 'Radius from A';
  rsFieldRadiusB = 'Radius from B';
  rsFieldDistance = 'Distance';
  rsFieldMarkerSize = 'Marker size';
  rsFieldMarkingSpacing = 'Marking %s spacing';
  rsFieldMarkingSize = 'Marking %s hole size';
  rsFieldAllowance = 'Seam allowance';
  rsFieldGrainAngle = 'Grainline angle';
  rsFieldNotch = 'Notch %s position';
  rsFieldEdgeAllowance = 'Edge %s seam allowance';
  rsFieldAngle1 = 'Start angle';
  rsFieldLength1 = 'Start handle';
  rsFieldAngle2 = 'End angle';
  rsFieldLength2 = 'End handle';
  rsFieldFormula = 'Formula';
  rsFieldRotate = 'Turn';
  rsFieldEase = 'Ease';
  rsFieldTolerance = 'Tolerance';
  rsFieldNodeAngle = 'Point %s angle';
  rsFieldNodeIn = 'Point %s handle in';
  rsFieldNodeOut = 'Point %s handle out';
  rsTypeFree = 'Free point';
  rsTypeOffset = 'Offset point';
  rsTypeAlong = 'Point along an edge';
  rsTypeBetween = 'Point between points';
  rsTypeRepeat = 'Repeat';
  rsTypeRepeatPoint = 'Point in a repeat';
  rsTypeIntersect = 'Crossing of two edges';
  rsTypeCircle = 'Compass step onto an edge';
  rsTypeCircleCircle = 'Two compass steps';
  rsTypeCircleEdge = 'Circle';
  rsTypeArc = 'Arc';
  rsTypeOffsetEdge = 'Offset edge';
  rsTypeCornerArc = 'Rounded corner';
  rsTypeCornerPoint = 'End of a rounded corner';
  rsTypeProject = 'Point projected onto an edge';
  rsTypeLine = 'Line';
  rsTypeCurve = 'Curve';
  rsTypePath = 'Curve path';
  rsTypePart = 'Part of a split edge';
  rsTypePiece = 'Piece';
  rsTypeSeam = 'Seam';
  rsTypeRotate = 'Rotate';
  rsTypeMirror = 'Mirror';
  rsTypeMove = 'Move';
  rsTypePointCopy = 'Copy of a point';
  rsTypeEdgeCopy = 'Copy of an edge';
  rsTypeVariable = 'Variable';
  rsTypeNote = 'Note';
  rsTypeNotePoint = 'Note on a point';
  rsTypeNoteEdge = 'Note on an edge';
  rsTypeNotePiece = 'Note on a piece';
  rsFieldPosition = 'Along the edge (ratio)';
  rsFieldNoteValue = 'Value %s';
  rsTypeCallout = 'Callout';

implementation

uses
  Sloper.Core.Drag, Sloper.Core.JSON, Sloper.Core.Piece, Sloper.Core.Transform;

const
  VariableDecimals = 4;
  // A scaled measurement is shown to a hundredth
  ScaledFormat = '0.##';

function FieldCaption(const FieldName: string): string;
var
  Dot: integer;
  NodeNumber, Part: string;
begin
  Dot := Pos('.', FieldName);
  if (Dot > 0) and (Copy(FieldName, 1, 4) = 'edge') then
    Exit(Format(rsFieldEdgeAllowance, [Copy(FieldName, 5, Dot - 5)]));
  if (Dot > 0) and (Copy(FieldName, 1, 5) = 'notch') then
    Exit(Format(rsFieldNotch, [Copy(FieldName, 6, Dot - 6)]));
  if (Dot > 0) and (Copy(FieldName, 1, 7) = 'marking') then
  begin
    NodeNumber := Copy(FieldName, 8, Dot - 8);
    Part := Copy(FieldName, Dot + 1, MaxInt);
    if Part = MarkingSpacingField then
      Exit(Format(rsFieldMarkingSpacing, [NodeNumber]));
    Exit(Format(rsFieldMarkingSize, [NodeNumber]));
  end;
  // A note's draft values: value1, value2
  if (Length(FieldName) > Length(NoteValueField)) and (Copy(FieldName, 1, Length(NoteValueField)) = NoteValueField) and
    (StrToIntDef(Copy(FieldName, Length(NoteValueField) + 1, MaxInt), 0) > 0) then
    Exit(Format(rsFieldNoteValue, [Copy(FieldName, Length(NoteValueField) + 1, MaxInt)]));
  if (Dot > 0) and (Copy(FieldName, 1, 4) = 'node') then
  begin
    NodeNumber := Copy(FieldName, 5, Dot - 5);
    Part := Copy(FieldName, Dot + 1, MaxInt);
    if Part = 'angle' then
      Exit(Format(rsFieldNodeAngle, [NodeNumber]));
    if Part = 'lengthIn' then
      Exit(Format(rsFieldNodeIn, [NodeNumber]));
    Exit(Format(rsFieldNodeOut, [NodeNumber]));
  end;
  case FieldName of
    'ease': Result := rsFieldEase;
    'rotate': Result := rsFieldRotate;
    'tolerance': Result := rsFieldTolerance;
    'x': Result := rsFieldX;
    'y': Result := rsFieldY;
    'length': Result := rsFieldLength;
    'angle': Result := rsFieldAngle;
    'dx': Result := rsFieldDX;
    'dy': Result := rsFieldDY;
    'value': Result := rsFieldValue;
    'count': Result := rsFieldCount;
    'radius': Result := rsFieldRadius;
    'radiusA': Result := rsFieldRadiusA;
    'radiusB': Result := rsFieldRadiusB;
    'distance': Result := rsFieldDistance;
    'allowance': Result := rsFieldAllowance;
    'grainline.angle': Result := rsFieldGrainAngle;
    'angle1': Result := rsFieldAngle1;
    'length1': Result := rsFieldLength1;
    'angle2': Result := rsFieldAngle2;
    'length2': Result := rsFieldLength2;
    'formula': Result := rsFieldFormula;
    NotePositionField: Result := rsFieldPosition;
    MarkerSizeField: Result := rsFieldMarkerSize;
    else
      Result := FieldName;
  end;
end;

function TypeCaption(Node: TEvalNode): string;
begin
  if Node is TFreePoint then
    Result := rsTypeFree
  else if Node is TOffsetPoint then
    Result := rsTypeOffset
  else if Node is TAlongEdgePoint then
    Result := rsTypeAlong
  else if Node is TBetweenPoint then
    Result := rsTypeBetween
  else if Node is TRepeatPoint then
    Result := rsTypeRepeatPoint
  else if Node is TRepeatObject then
    Result := rsTypeRepeat
  else if Node is TIntersectPoint then
    Result := rsTypeIntersect
  else if Node is TCircleEdgePoint then
    Result := rsTypeCircle
  else if Node is TCircleCirclePoint then
    Result := rsTypeCircleCircle
  else if Node is TCircleObject then
    Result := rsTypeCircleEdge
  else if Node is TOffsetEdge then
    Result := rsTypeOffsetEdge
  else if Node is TCornerArc then
    Result := rsTypeCornerArc
  else if Node is TCornerPoint then
    Result := rsTypeCornerPoint
  else if Node is TArcObject then
    Result := rsTypeArc
  else if Node is TProjectPoint then
    Result := rsTypeProject
  else if Node is TLineObject then
    Result := rsTypeLine
  else if Node is TCurveObject then
    Result := rsTypeCurve
  else if Node is TCurvePathObject then
    Result := rsTypePath
  else if Node is TSplitPart then
    Result := rsTypePart
  else if Node is TPieceObject then
    Result := rsTypePiece
  else if Node is TSeamObject then
    Result := rsTypeSeam
  else if (Node is TNoteObject) and (TNoteObject(Node).Leader <> nlNone) then
    Result := rsTypeCallout
  else if Node is TNoteObject then
    case TNoteObject(Node).Anchor of
      naPoint: Result := rsTypeNotePoint;
      naEdge: Result := rsTypeNoteEdge;
      naPiece: Result := rsTypeNotePiece;
      else
        Result := rsTypeNote;
    end
  else if Node is TPointCopy then
    Result := rsTypePointCopy
  else if Node is TEdgeCopy then
    Result := rsTypeEdgeCopy
  else if Node is TTransformObject then
    case TTransformObject(Node).Kind of
      tkRotate: Result := rsTypeRotate;
      tkMirror: Result := rsTypeMirror;
      else
        Result := rsTypeMove;
    end
  else if Node is TVariable then
    Result := rsTypeVariable
  else
    Result := '';
end;

function StateCaption(State: TEvalState): string;
begin
  case State of
    esValid: Result := rsStateValid;
    esError: Result := rsStateError;
    esInvalid: Result := rsStateInvalid;
    else
      Result := rsStateBlocked;
  end;
end;

function PositionText(const Position: TVec2; AUnit: TMeasureUnit): string;
begin
  Result := Format(rsObjectPosition, [FormatLength(Position.X, AUnit), FormatLength(Position.Y, AUnit), MeasureUnitNames[AUnit]]);
end;

function ResultText(DraftObject: TDraftObject; AUnit: TMeasureUnit): string;
begin
  Result := '';
  if not DraftObject.HasResult then
    Exit;
  if DraftObject is TPointObject then
    Result := PositionText(TPointObject(DraftObject).Position, AUnit)
  else if DraftObject is TEdgeObject then
    Result := LengthWithUnit(TEdgeObject(DraftObject).Length, AUnit)
  else if DraftObject is TPieceObject then
    Result := LengthWithUnit(TPieceObject(DraftObject).Perimeter, AUnit)
  else if DraftObject is TSeamObject then
    Result := Format(rsObjectSeamLengths, [LengthWithUnit(TSeamObject(DraftObject).LengthA, AUnit),
      LengthWithUnit(TSeamObject(DraftObject).LengthB, AUnit)])
  else if DraftObject is TNoteObject then
    Result := TNoteObject(DraftObject).FirstLine;
end;

function SeamEntryText(Pattern: TPattern; const Entry: TSeamEntry): string;
begin
  Result := Format(rsObjectSeamEntry, [Pattern.FindNode(Entry.PieceKey).DisplayName, Pattern.FindNode(Entry.EdgeKey).DisplayName]);
end;

function SeamSideText(Pattern: TPattern; const Side: TSeamSide): string;
var
  Entry: TSeamEntry;
begin
  Result := '';
  for Entry in Side do
  begin
    if Result <> '' then
      Result := Result + rsObjectSeamEntryGap;
    Result := Result + SeamEntryText(Pattern, Entry);
  end;
end;

function SeamDifferenceText(Seam: TSeamObject; AUnit: TMeasureUnit): string;
begin
  Result := Format(rsObjectSeamDifference, [LengthWithUnit(Seam.Difference, AUnit), LengthWithUnit(Seam.Ease, AUnit)]);
end;

function SuggestionCaption(Pattern: TPattern; const Item: TSeamSuggestion): string;
begin
  if Item.Shared then
    Result := Format(rsSuggestShared, [SeamEntryText(Pattern, Item.First), SeamEntryText(Pattern, Item.Second)])
  else
    Result := Format(rsSuggestLengths, [SeamEntryText(Pattern, Item.First), SeamEntryText(Pattern, Item.Second), LengthWithUnit(Item.Difference, Pattern.Units)]);
end;

function FormulasText(Pattern: TPattern; DraftObject: TDraftObject): string;
var
  Index: integer;
  FieldName, Item: string;
begin
  Result := '';
  for Index := 0 to DraftObject.FieldCount - 1 do
  begin
    FieldName := DraftObject.Fields[Index].Name;
    Item := Format(rsObjectFormula, [FieldCaption(FieldName), Pattern.FormulaText(DraftObject, FieldName)]);
    if Result = '' then
      Result := Item
    else
      Result := Result + rsObjectFormulaGap + Item;
  end;
end;

function ObjectRow(Pattern: TPattern; DraftObject: TDraftObject): TObjectRow;
begin
  Result.Key := DraftObject.Key;
  Result.Name := DraftObject.DisplayName;
  Result.Operation := TypeCaption(DraftObject);
  Result.Value := ResultText(DraftObject, Pattern.Units);
  Result.Formulas := FormulasText(Pattern, DraftObject);
  Result.State := DraftObject.State;
  Result.StateText := StateCaption(DraftObject.State);
  Result.Text := '';
  if DraftObject is TNoteObject then
    Result.Text := TNoteObject(DraftObject).DisplayText(Pattern.Resolver);
end;

function PassesFilter(Pattern: TPattern; DraftObject: TDraftObject; Filter: TObjectFilter): boolean;
begin
  case Filter of
    ofPoints: Result := (DraftObject is TPointObject) or (DraftObject is TRepeatObject);
    ofEdges: Result := DraftObject is TEdgeObject;
    ofPieces: Result := (DraftObject is TPieceObject) or (DraftObject is TSeamObject);
    ofNotes: Result := DraftObject is TNoteObject;
    ofProblems: Result := (DraftObject.State <> esValid) or ((DraftObject is TSeamObject) and TSeamObject(DraftObject).OutOfTolerance) or
        ((DraftObject is TPieceObject) and not Assigned(Pattern.FabricOf(TPieceObject(DraftObject))));
    else
      Result := True;
  end;
end;

function Matches(const Row: TObjectRow; const LowerSearch: string): boolean;
begin
  Result := (LowerSearch = '') or (Pos(LowerSearch, LowerCase(Row.Name)) > 0) or (Pos(LowerSearch, LowerCase(Row.Operation)) > 0) or
    (Pos(LowerSearch, LowerCase(Row.Formulas)) > 0) or (Pos(LowerSearch, LowerCase(Row.Text)) > 0);
end;

function ObjectRows(Pattern: TPattern; Filter: TObjectFilter; const Search: string): TObjectRowArray;
var
  Index, Count, Number: integer;
  LowerSearch: string;

  procedure AddRow(DraftObject: TDraftObject);
  var
    Row: TObjectRow;
  begin
    if not Assigned(DraftObject) then
      Exit;
    Row := ObjectRow(Pattern, DraftObject);
    if not Matches(Row, LowerSearch) then
      Exit;
    if Count = Length(Result) then
      SetLength(Result, Count * 2 + 1);
    Result[Count] := Row;
    Inc(Count);
  end;

begin
  Result := nil;
  SetLength(Result, Pattern.ObjectCount);
  LowerSearch := LowerCase(Trim(Search));
  Count := 0;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if not PassesFilter(Pattern, Pattern.Objects[Index], Filter) then
      Continue
    else if (Pattern.Objects[Index] is TRepeatObject) and (TRepeatObject(Pattern.Objects[Index]).Count > 0) then
      // A repeat is listed as its points, and the first stands for it
      for Number := 1 to TRepeatObject(Pattern.Objects[Index]).Count do
        AddRow(TRepeatObject(Pattern.Objects[Index]).Item(Number))
    else
      AddRow(Pattern.Objects[Index]);
  SetLength(Result, Count);
end;

function VariableRow(Pattern: TPattern; Variable: TVariable): TVariableRow;
begin
  Result.Key := Variable.Key;
  Result.Name := Variable.Name;
  Result.Formula := Pattern.FormulaText(Variable, 'formula');
  Result.Value := '';
  if Variable.State = esValid then
    Result.Value := RoundedText(Variable.Value, VariableDecimals);
  Result.Description := Variable.Description;
  Result.State := Variable.State;
  Result.StateText := StateCaption(Variable.State);
end;

function VariableRows(Pattern: TPattern; const Search: string): TVariableRowArray;
var
  Index, Count: integer;
  LowerSearch: string;
  Row: TVariableRow;
begin
  Result := nil;
  SetLength(Result, Pattern.VariableCount);
  LowerSearch := LowerCase(Trim(Search));
  Count := 0;
  for Index := 0 to Pattern.VariableCount - 1 do
  begin
    Row := VariableRow(Pattern, Pattern.Variables[Index]);
    if (LowerSearch = '') or (Pos(LowerSearch, LowerCase(Row.Name)) > 0) or (Pos(LowerSearch, LowerCase(Row.Formula)) > 0) or
      (Pos(LowerSearch, LowerCase(Row.Description)) > 0) then
    begin
      Result[Count] := Row;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function MeasurementRows(Pattern: TPattern; MeasurementSet: TMeasurementSet; const Search: string): TMeasurementRowArray;
var
  LowerSearch: string;
  Index, Count: integer;
  Key: string;

// As the pattern reads it while it is being tried a size up or down
  function ScaledText(Value: double): string;
  var
    Formats: TFormatSettings;
  begin
    // Exactly 1 is the slider at its centre, so this is not a tolerance compare
    if Pattern.MeasurementScale = 1 then
      Exit(FormatJSONFloat(Value));
    Formats := DefaultFormatSettings;
    Formats.DecimalSeparator := '.';
    Result := FormatFloat(ScaledFormat, Value * Pattern.MeasurementScale, Formats);
  end;

  procedure Add(const AKey, Value, Description: string; Missing: boolean);
  begin
    if (LowerSearch <> '') and (Pos(LowerSearch, LowerCase(AKey)) = 0) and (Pos(LowerSearch, LowerCase(Description)) = 0) then
      Exit;
    SetLength(Result, Count + 1);
    Result[Count].Key := AKey;
    Result[Count].Value := Value;
    Result[Count].Description := Description;
    Result[Count].Missing := Missing;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  LowerSearch := LowerCase(Trim(Search));
  if Assigned(MeasurementSet) then
    for Index := 0 to MeasurementSet.Count - 1 do
      if MeasurementSet[Index].HasValue then
        Add(MeasurementSet[Index].Key, ScaledText(MeasurementSet[Index].Value), MeasurementSet[Index].Description, False)
      else
        Add(MeasurementSet[Index].Key, '', MeasurementSet[Index].Description, False);
  for Key in PatternMeasurementKeys(Pattern) do
    if not Assigned(MeasurementSet) or not Assigned(MeasurementSet.Find(Key)) then
      Add(Key, '', '', True);
end;

function MeasurementChangeText(const Change: TMeasurementChange; const FileName: string): string;
begin
  if Change.Added or not Change.HadValue then
    Result := Format(rsMeasurementAdded, [Change.Key, FormatJSONFloat(Change.Value), ExtractFileName(FileName)])
  else
    Result := Format(rsMeasurementChanged, [Change.Key, FormatJSONFloat(Change.OldValue), FormatJSONFloat(Change.Value),
      ExtractFileName(FileName)]);
end;

function KeyIndex(const Keys: TStringArray; const Key: string): integer;
begin
  for Result := 0 to High(Keys) do
    if Keys[Result] = Key then
      Exit;
  Result := -1;
end;

function SelectionAfterClick(const Visible, Selected: TStringArray; const Anchor, Clicked: string;
  Toggle, Extend: boolean): TStringArray;
var
  AnchorIndex, ClickedIndex, Found: integer;
begin
  AnchorIndex := KeyIndex(Visible, Anchor);
  ClickedIndex := KeyIndex(Visible, Clicked);
  if Extend and (AnchorIndex >= 0) and (ClickedIndex >= 0) then
  begin
    if AnchorIndex < ClickedIndex then
      Exit(Copy(Visible, AnchorIndex, ClickedIndex - AnchorIndex + 1));
    Exit(Copy(Visible, ClickedIndex, AnchorIndex - ClickedIndex + 1));
  end;
  if not Toggle then
    Exit([Clicked]);
  Result := Copy(Selected);
  Found := KeyIndex(Result, Clicked);
  if Found >= 0 then
    Delete(Result, Found, 1)
  else
    Insert(Clicked, Result, Length(Result));
end;

end.
