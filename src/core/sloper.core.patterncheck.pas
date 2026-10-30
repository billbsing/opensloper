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

// Value rounded to ReportDecimals
function ReportFloat(Value: double): TJSONData;
// The state as written in reports; not translated
function StateName(State: TEvalState): string;
// One line per measurement, variable or object in error or invalid, as
// "Name (error): message". Blocked ones fail because of these, so they are
// only counted.
function PatternProblems(Pattern: TPattern; out BlockedCount: integer): TStringArray;
// Every variable's value and every object's position (points) or length
// (edges), with its state; failing ones have a message instead of values.
// PatternName and MeasurementName are written as given. The caller frees it.
function PatternReport(Pattern: TPattern; const PatternName, MeasurementName: string): TJSONObject;

resourcestring
  rsCheckProblem = '%s (%s): %s';
  rsCheckError = 'error';
  rsCheckInvalid = 'invalid';

implementation

uses
  Math, Sloper.Core.JSON, Sloper.Core.Evaluator, Sloper.Core.Variables, Sloper.Core.Draft;

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

function PatternProblems(Pattern: TPattern; out BlockedCount: integer): TStringArray;
var
  Node: TEvalNode;
  StateText: string;
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
  Result.Add('id', StrToInt(Node.Key));
  Result.Add('name', AName);
  Result.Add('state', StateName(Node.State));
  if Node.State <> esValid then
    Result.Add('message', Node.Message);
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
  Result.Add('pattern', PatternName);
  Result.Add('measurements', MeasurementName);
  List := TJSONArray.Create;
  Result.Add('variables', List);
  for Index := 0 to Pattern.VariableCount - 1 do
  begin
    Variable := Pattern.Variables[Index];
    Item := ReportNode(Variable, Variable.Name);
    if Variable.State = esValid then
      Item.Add('value', ReportFloat(Variable.Value));
    List.Add(Item);
  end;
  List := TJSONArray.Create;
  Result.Add('objects', List);
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    Item := ReportNode(DraftObject, DraftObject.Name);
    if DraftObject.State = esValid then
      if DraftObject is TPointObject then
      begin
        Item.Add('x', ReportFloat(TPointObject(DraftObject).Position.X));
        Item.Add('y', ReportFloat(TPointObject(DraftObject).Position.Y));
      end
      else if DraftObject is TEdgeObject then
        Item.Add('length', ReportFloat(TEdgeObject(DraftObject).Length));
    List.Add(Item);
  end;
end;

end.
