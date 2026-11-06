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

// Checking an evaluated pattern: the problems to show the user, and a report
// of every computed value as JSON, used by "opensloper-cli check --json" and
// by the regression tests. No LCL dependency.
unit Sloper.Core.PatternCheck;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.Core.EvalTypes, Sloper.Core.Pattern;

const
  // Reported values are rounded to this many decimals of a millimetre: far
  // finer than drafting needs, and it keeps reports readable and stable
  ReportDecimals = 6;

// The measurement keys the pattern's formulas use, in order
function PatternMeasurementKeys(Pattern: TPattern): TStringArray;
// The same, from a pattern file; needs no measurement set
function ReadPatternMeasurementKeys(const FileName: string; out Keys: TStringArray; out ErrorMessage: string): boolean;

// Value rounded to ReportDecimals
function ReportFloat(Value: double): TJSONData;
// The state as written in reports; not translated
function StateName(State: TEvalState): string;
// One line per measurement, variable or object in error or invalid, as
// "Name (error): message", then one per seam out of tolerance and one per piece
// with no fabric, one per marking line in no piece or outside its piece, and
// one per printing note in no piece.
// Blocked ones fail because of these, so they are only counted.
function PatternProblems(Pattern: TPattern; out BlockedCount: integer): TStringArray;
// Every variable's value and every object's position (points), length (edges)
// areas and perimeter (pieces), or side lengths (seams), with its state; failing ones have a message instead of values.
// PatternName and MeasurementName are written as given. The caller frees it.
function PatternReport(Pattern: TPattern; const PatternName, MeasurementName: string): TJSONObject;

resourcestring
  rsCheckProblem = '%s (%s): %s';
  rsCheckError = 'error';
  rsCheckInvalid = 'invalid';
  rsCheckNoFabric = '%s has no fabric';
  rsCheckLineOutside = '%s lies outside %s, which it is marked on';
  rsCheckLineLoose = '%s is a marking line in no piece, so it does not print';
  rsCheckMarkerLoose = '%s has a marker but is in no piece, so it does not print';
  rsCheckSeam = '%s: side A is %s mm and side B %s mm, %s mm from the expected %s mm';
  rsCheckNoteLoose = '%s is marked to print but lies in no piece, so it does not print in layouts';

implementation

uses
  Classes, Math, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.PatternFile, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Geometry,
  Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Note;

function StateName(State: TEvalState): string;
begin
  case State of
    esValid: Result := 'valid';
    esDirty: Result := 'dirty';
    esError: Result := 'error';
    esInvalid: Result := 'invalid';
    esBlocked: Result := 'blocked';
  end;
end;

function PatternMeasurementKeys(Pattern: TPattern): TStringArray;
var
  Node: TEvalNode;
  Keys: TStringList;
begin
  Keys := TStringList.Create;
  try
    for Node in Pattern.AllNodes do
      if Node is TMeasurementNode then
        Keys.Add(Copy(Node.Key, 2, MaxInt));
    Keys.Sort;
    Result := Keys.ToStringArray;
  finally
    FreeAndNil(Keys);
  end;
end;

function ReadPatternMeasurementKeys(const FileName: string; out Keys: TStringArray; out ErrorMessage: string): boolean;
var
  Pattern: TPattern;
begin
  Keys := nil;
  Pattern := TPattern.Create;
  try
    Result := LoadPatternFromFile(Pattern, FileName, ErrorMessage);
    if not Result then
      Exit;
    // Evaluating is what makes a node for each key
    Pattern.Evaluate;
    Keys := PatternMeasurementKeys(Pattern);
  finally
    FreeAndNil(Pattern);
  end;
end;

// Only for markings and pieces that computed, as failing ones are reported
// anyway. A marked point outside its piece makes the piece invalid, so only
// lines are checked for that here.
procedure AddMarkingLineProblems(Pattern: TPattern; var Problems: TStringArray);
var
  Index: integer;
  DraftObject: TDraftObject;
  Piece: TPieceObject;
  Pieces: TPieceObjectArray;
  IsLine: boolean;
begin
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    IsLine := (DraftObject is TEdgeObject) and (TEdgeObject(DraftObject).Role in MarkingRoles);
    if not IsLine and not (((DraftObject is TPointObject) or (DraftObject is TRepeatObject)) and (DraftObject.Marker <> pmPlain)) then
      Continue;
    if DraftObject.State <> esValid then
      Continue;
    Pieces := Pattern.PiecesWithMarking(DraftObject.Key);
    if (Length(Pieces) = 0) and IsLine then
      Insert(Format(rsCheckLineLoose, [DraftObject.DisplayName]), Problems, Length(Problems))
    else if Length(Pieces) = 0 then
      Insert(Format(rsCheckMarkerLoose, [DraftObject.DisplayName]), Problems, Length(Problems));
    if IsLine then
      for Piece in Pieces do
        if (Piece.State = esValid) and not Pattern.LiesInside(DraftObject, Piece) then
          Insert(Format(rsCheckLineOutside, [DraftObject.DisplayName, Piece.DisplayName]), Problems, Length(Problems));
  end;
end;

function PatternProblems(Pattern: TPattern; out BlockedCount: integer): TStringArray;
const
  SeamFormat = '0.#';
var
  Node: TEvalNode;
  StateText: string;
  Index: integer;
  Seam: TSeamObject;
begin
  Result := nil;
  BlockedCount := 0;
  for Node in Pattern.AllNodes do
  begin
    case Node.State of
      esError: StateText := rsCheckError;
      esInvalid: StateText := rsCheckInvalid;
      esBlocked:
      begin
        Inc(BlockedCount);
        Continue;
      end;
      else
        Continue;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Format(rsCheckProblem, [Node.DisplayName, StateText, Node.Message]);
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TSeamObject) and (Pattern.Objects[Index].State = esValid) then
    begin
      Seam := TSeamObject(Pattern.Objects[Index]);
      if not Seam.OutOfTolerance then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Format(rsCheckSeam, [Seam.DisplayName, FormatFloat(SeamFormat, Seam.LengthA), FormatFloat(SeamFormat, Seam.LengthB),
        FormatFloat(SeamFormat, Seam.Mismatch), FormatFloat(SeamFormat, Seam.Ease)]);
    end;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and not Assigned(Pattern.FabricOf(TPieceObject(Pattern.Objects[Index]))) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Format(rsCheckNoFabric, [Pattern.Objects[Index].DisplayName]);
    end;
  AddMarkingLineProblems(Pattern, Result);
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TNoteObject) and TNoteObject(Pattern.Objects[Index]).Print and (Pattern.Objects[Index].State = esValid) and
      (Length(Pattern.NotePieces(TNoteObject(Pattern.Objects[Index]))) = 0) then
      Insert(Format(rsCheckNoteLoose, [Pattern.Objects[Index].DisplayName]), Result, Length(Result));
end;

function ReportFloat(Value: double): TJSONData;
var
  Scale, Rounded: double;
begin
  Scale := IntPower(10, ReportDecimals);
  Rounded := Round(Value * Scale) / Scale;
  // No "-0" in reports
  if Rounded = 0 then
    Rounded := 0;
  Result := JSONFloat(Rounded);
end;

function ReportNode(Node: TEvalNode; const AName: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('id', StrToInt(Node.Key));
    Result.Add('name', AName);
    Result.Add('state', StateName(Node.State));
    if Node.State <> esValid then
      Result.Add('message', Node.Message);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function PatternReport(Pattern: TPattern; const PatternName, MeasurementName: string): TJSONObject;
var
  List: TJSONArray;
  Item: TJSONObject;
  Index: integer;
  Variable: TVariable;
  DraftObject: TDraftObject;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('pattern', PatternName);
    Result.Add('measurements', MeasurementName);
    List := TJSONArray.Create;
    Result.Add('variables', List);
    for Index := 0 to Pattern.VariableCount - 1 do
    begin
      Variable := Pattern.Variables[Index];
      Item := ReportNode(Variable, Variable.Name);
      List.Add(Item);
      if Variable.State = esValid then
        Item.Add('value', ReportFloat(Variable.Value));
    end;
    List := TJSONArray.Create;
    Result.Add('objects', List);
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      DraftObject := Pattern.Objects[Index];
      Item := ReportNode(DraftObject, DraftObject.Name);
      List.Add(Item);
      if DraftObject.State = esValid then
        if DraftObject is TPointObject then
        begin
          Item.Add('x', ReportFloat(TPointObject(DraftObject).Position.X));
          Item.Add('y', ReportFloat(TPointObject(DraftObject).Position.Y));
        end
        else if DraftObject is TEdgeObject then
          Item.Add('length', ReportFloat(TEdgeObject(DraftObject).Length))
        else if DraftObject is TPieceObject then
        begin
          Item.Add('area', ReportFloat(TPieceObject(DraftObject).Area));
          Item.Add('perimeter', ReportFloat(TPieceObject(DraftObject).Perimeter));
          Item.Add('cutArea', ReportFloat(Abs(SignedArea(TPieceObject(DraftObject).CutLine))));
        end
        else if DraftObject is TNoteObject then
        begin
          Item.Add('x', ReportFloat(TNoteObject(DraftObject).Position.X));
          Item.Add('y', ReportFloat(TNoteObject(DraftObject).Position.Y));
        end
        else if DraftObject is TSeamObject then
        begin
          Item.Add('lengthA', ReportFloat(TSeamObject(DraftObject).LengthA));
          Item.Add('lengthB', ReportFloat(TSeamObject(DraftObject).LengthB));
          Item.Add('ease', ReportFloat(TSeamObject(DraftObject).Ease));
          Item.Add('tolerance', ReportFloat(TSeamObject(DraftObject).Tolerance));
        end;
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

end.
