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

// Pattern variables (increments): named values such as #ease_waist that hold
// design decisions. Each has a stable ID (v1, v2, ...) used in stored
// formulas, so renaming never breaks a formula. TPattern manages them.
// No LCL dependency.
unit osVariables;

{$mode ObjFPC}{$H+}

interface

uses
  osEvalTypes, osEvaluator, osFormula;

type
  TVariable = class(TEvalNode)
  private
    FName: string;
    FValue: Double;
  public
    Description: string;
    constructor Create(const AKey: string);
    function DisplayName: string; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    function Formula: TFormula;
    property Name: string read FName write FName;
    // Last good value; kept while the variable is failing
    property Value: Double read FValue;
  end;

  // A measurement read by the pattern, such as @waist. Created by TPattern
  // for each key its formulas use.
  TMeasurementNode = class(TEvalNode)
  private
    FValue: Double;
  public
    function DisplayName: string; override;
    function Compute(Context: TEvalContext): TEvalState; override;
    property Value: Double read FValue;
  end;

resourcestring
  rsMeasurementNotInSet = '@%s is not in the measurement set';

implementation

uses
  SysUtils;

{ TVariable }

constructor TVariable.Create(const AKey: string);
begin
  inherited Create(AKey);
  AddField('formula');
end;

function TVariable.DisplayName: string;
begin
  Result := '#' + FName;
end;

function TVariable.Formula: TFormula;
begin
  Result := Field('formula');
end;

function TVariable.Compute(Context: TEvalContext): TEvalState;
var
  NewValue: Double;
begin
  if not EvalField(Context, 'formula', NewValue) then
    Exit(esError);
  FValue := NewValue;
  Result := esValid;
end;

{ TMeasurementNode }

function TMeasurementNode.DisplayName: string;
begin
  Result := Key;
end;

function TMeasurementNode.Compute(Context: TEvalContext): TEvalState;
var
  NewValue: Double;
begin
  // Key is '@waist'; the context looks up 'waist' in the measurement set
  if not Context.MeasurementValue(Copy(Key, 2, MaxInt), NewValue) then
    Exit(Fail(esError, Format(rsMeasurementNotInSet, [Copy(Key, 2, MaxInt)])));
  FValue := NewValue;
  Result := esValid;
end;

end.
