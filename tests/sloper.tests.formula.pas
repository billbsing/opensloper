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

unit Sloper.Tests.Formula;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.FormulaLexer, Sloper.Core.Formula;

type
  // A small pattern: points A (p1) and B (p2), line Line_A_B (l1),
  // variables ease_waist (v1) and dart (v2), measurements waist, hip and
  // back_length. Names are values in the lists, IDs are the keys.
  TTestResolver = class(TNameResolver)
  public
    Objects, Variables, Measurements: TStringList;
    constructor Create;
    destructor Destroy; override;
    function ResolveMeasurement(const Name: string; out Key: string): boolean; override;
    function ResolveVariable(const Name: string; out Id: string): boolean; override;
    function ResolveObject(const Name: string; out Id: string): boolean; override;
    function ResolveProperty(const ObjectId, Prop: string; out CanonicalProp: string): boolean; override;
    function VariableName(const Id: string; out Name: string): boolean; override;
    function ObjectName(const Id: string; out Name: string): boolean; override;
  end;

  TTestContext = class(TFormulaContext)
  public
    function MeasurementValue(const Key: string; out Value: double): boolean; override;
    function VariableValue(const Id: string; out Value: double): boolean; override;
    function PropertyValue(const ObjectId, Prop: string; out Value: double): boolean; override;
  end;

  TTestFormulaLexer = class(TOSTestCase)
  published
    procedure TestDisplayTokens;
    procedure TestStoredTokens;
    procedure TestNumberForms;
    procedure TestBadNumber;
    // Past a double's range: an error at the number, not an exception
    procedure TestHugeNumber;
    procedure TestNumberSuffixes;
    procedure TestUnexpectedCharacter;
    procedure TestUnexpectedCharacterIsWholeUtf8Char;
    procedure TestMissingNames;
    procedure TestFormsDiffer;
  end;

  TTestFormula = class(TOSTestCase)
  private
    FResolver: TTestResolver;
    FContext: TTestContext;
    FFormula: TFormula;
    function Eval(const Text: string): double;
    procedure AssertValue(const Text: string; Expected: double);
    procedure AssertParseError(const Text, Msg: string; Pos: integer);
    procedure AssertEvalError(const Text, Msg: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNumbers;
    procedure TestPrecedence;
    procedure TestPowerAndUnaryMinus;
    procedure TestTrigUsesDegrees;
    procedure TestOtherFunctions;
    procedure TestRoundHalfAwayFromZero;
    procedure TestFunctionNamesIgnoreCase;
    procedure TestMeasurementsAndVariables;
    procedure TestObjectProperties;
    procedure TestNamesIgnoreCase;
    procedure TestSpacingIsKept;
    procedure TestReferencesAreUnique;
    procedure TestRenameKeepsFormula;
    procedure TestStoredRoundTrip;
    procedure TestDanglingId;
    procedure TestIsLiteral;
    procedure TestUnitSuffixes;
    procedure TestSuffixRoundTrip;
    procedure TestUnknownSuffix;
    procedure TestDecimalPointIgnoresLocale;
    procedure TestEmpty;
    procedure TestSyntaxErrors;
    procedure TestUnknownNames;
    procedure TestPropertyErrors;
    procedure TestFunctionErrors;
    procedure TestTooDeep;
    procedure TestStoredFormRejectsNames;
    procedure TestFailedParseKeepsText;
    procedure TestEvaluationErrors;
    procedure TestDisplayErrorPos;
  end;

implementation

uses
  SysUtils, StrUtils;

  { TTestResolver }

constructor TTestResolver.Create;
begin
  Objects := TStringList.Create;
  Objects.Values['1'] := 'A';
  Objects.Values['2'] := 'B';
  Objects.Values['3'] := 'Line_A_B';
  Variables := TStringList.Create;
  Variables.Values['4'] := 'ease_waist';
  Variables.Values['5'] := 'dart';
  Measurements := TStringList.Create;
  Measurements.Add('waist');
  Measurements.Add('hip');
  Measurements.Add('back_length');
end;

destructor TTestResolver.Destroy;
begin
  FreeAndNil(Objects);
  FreeAndNil(Variables);
  FreeAndNil(Measurements);
  inherited Destroy;
end;

function FindByName(List: TStringList; const Name: string; out Id: string): boolean;
var
  I: integer;
begin
  for I := 0 to List.Count - 1 do
    if SameText(List.ValueFromIndex[I], Name) then
    begin
      Id := List.Names[I];
      Exit(True);
    end;
  Result := False;
end;

function TTestResolver.ResolveMeasurement(const Name: string; out Key: string): boolean;
var
  I: integer;
begin
  I := Measurements.IndexOf(Name);
  Result := I >= 0;
  if Result then
    Key := Measurements[I];
end;

function TTestResolver.ResolveVariable(const Name: string; out Id: string): boolean;
begin
  Result := FindByName(Variables, Name, Id);
end;

function TTestResolver.ResolveObject(const Name: string; out Id: string): boolean;
begin
  Result := FindByName(Objects, Name, Id);
end;

function TTestResolver.ResolveProperty(const ObjectId, Prop: string;
  out CanonicalProp: string): boolean;
begin
  CanonicalProp := LowerCase(Prop);
  // 3 is the line; the other objects are points
  if ObjectId = '3' then
    Result := (CanonicalProp = 'length') or (CanonicalProp = 'angle')
  else
    Result := (CanonicalProp = 'x') or (CanonicalProp = 'y');
end;

function TTestResolver.VariableName(const Id: string; out Name: string): boolean;
begin
  Name := Variables.Values[Id];
  Result := Name <> '';
end;

function TTestResolver.ObjectName(const Id: string; out Name: string): boolean;
begin
  Name := Objects.Values[Id];
  Result := Name <> '';
end;

{ TTestContext }

function TTestContext.MeasurementValue(const Key: string; out Value: double): boolean;
begin
  Result := True;
  if SameText(Key, 'waist') then
    Value := 720
  else if SameText(Key, 'hip') then
    Value := 960
  else
    Result := False;
end;

function TTestContext.VariableValue(const Id: string; out Value: double): boolean;
begin
  Result := True;
  if Id = '4' then
    Value := 20
  else if Id = '5' then
    Value := 15
  else
    Result := False;
end;

function TTestContext.PropertyValue(const ObjectId, Prop: string; out Value: double): boolean;
begin
  Result := True;
  if (ObjectId = '1') and (Prop = 'x') then
    Value := 0
  else if (ObjectId = '1') and (Prop = 'y') then
    Value := 0
  else if (ObjectId = '2') and (Prop = 'x') then
    Value := 100
  else if (ObjectId = '2') and (Prop = 'y') then
    Value := 50
  else if (ObjectId = '3') and (Prop = 'length') then
    Value := 125
  else
    Result := False;
end;

{ TTestFormulaLexer }

function Tokens(const Text: string; Form: TFormulaTextForm): TFormulaTokenArray;
var
  Msg: string;
  Pos: integer;
begin
  if not TokenizeFormula(Text, Form, Result, Msg, Pos) then
    raise Exception.CreateFmt('Tokenize failed at %d: %s', [Pos, Msg]);
end;

procedure TTestFormulaLexer.TestDisplayTokens;
var
  T: TFormulaTokenArray;
begin
  T := Tokens('Line_A_B.length + @waist/4 - #ease', ffDisplay);
  AssertEquals('count', 7, Length(T));
  AssertTrue('object ref', T[0].Kind = ftObjectRef);
  AssertEquals('object name', 'Line_A_B', T[0].Name);
  AssertEquals('property', 'length', T[0].Prop);
  AssertEquals('object pos', 1, T[0].Pos);
  AssertEquals('object len', 15, T[0].Len);
  AssertTrue('plus', (T[1].Kind = ftOperator) and (T[1].Op = '+'));
  AssertTrue('measurement', T[2].Kind = ftMeasurement);
  AssertEquals('measurement key', 'waist', T[2].Name);
  AssertEquals('measurement pos', 19, T[2].Pos);
  AssertTrue('number', T[4].Kind = ftNumber);
  AssertNear('number value', 4, T[4].Value);
  AssertTrue('variable', T[6].Kind = ftVariable);
  AssertEquals('variable name', 'ease', T[6].Name);
end;

procedure TTestFormulaLexer.TestStoredTokens;
var
  T: TFormulaTokenArray;
begin
  T := Tokens('{3}.length + {4}', ffStored);
  AssertEquals('count', 3, Length(T));
  AssertTrue('object id', T[0].Kind = ftIdRef);
  AssertEquals('id', '3', T[0].Name);
  AssertEquals('property', 'length', T[0].Prop);
  AssertTrue('variable id', T[2].Kind = ftIdRef);
  AssertEquals('no property', '', T[2].Prop);
end;

procedure TTestFormulaLexer.TestNumberForms;
var
  T: TFormulaTokenArray;
begin
  T := Tokens('12 0.5 .5 1e3 2.5E-1', ffDisplay);
  AssertEquals('count', 5, Length(T));
  AssertNear('integer', 12, T[0].Value);
  AssertNear('decimal', 0.5, T[1].Value);
  AssertNear('leading point', 0.5, T[2].Value);
  AssertNear('exponent', 1000, T[3].Value);
  AssertNear('negative exponent', 0.25, T[4].Value);
end;

procedure TTestFormulaLexer.TestBadNumber;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertFalse('trailing point', TokenizeFormula('1. + 2', ffDisplay, T, Msg, Pos));
  AssertEquals(rsFormulaExpectedDigit, Msg);
  AssertEquals('position', 3, Pos);
  AssertFalse('empty exponent', TokenizeFormula('2e+', ffDisplay, T, Msg, Pos));
  AssertEquals('exponent position', 4, Pos);
end;

procedure TTestFormulaLexer.TestUnexpectedCharacter;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertFalse(TokenizeFormula('3 $ 4', ffDisplay, T, Msg, Pos));
  AssertEquals(Format(rsFormulaUnexpectedChar, ['$']), Msg);
  AssertEquals(3, Pos);
end;

procedure TTestFormulaLexer.TestUnexpectedCharacterIsWholeUtf8Char;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertFalse(TokenizeFormula('3 × 4', ffDisplay, T, Msg, Pos));
  AssertEquals(Format(rsFormulaUnexpectedChar, ['×']), Msg);
end;

procedure TTestFormulaLexer.TestMissingNames;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertFalse('bare @', TokenizeFormula('@ + 1', ffDisplay, T, Msg, Pos));
  AssertEquals(rsFormulaExpectedMeasurement, Msg);
  AssertFalse('bare #', TokenizeFormula('#', ffDisplay, T, Msg, Pos));
  AssertEquals(rsFormulaExpectedVariable, Msg);
  AssertFalse('dot without property', TokenizeFormula('A. + 1', ffDisplay, T, Msg, Pos));
  AssertEquals(rsFormulaExpectedProperty, Msg);
  AssertEquals('dot position', 3, Pos);
  AssertFalse('unclosed id', TokenizeFormula('{1.x', ffStored, T, Msg, Pos));
  AssertEquals(rsFormulaBadId, Msg);
  // IDs are positive integers in plain decimal
  AssertFalse('letter id', TokenizeFormula('{p1}.x', ffStored, T, Msg, Pos));
  AssertEquals(rsFormulaBadId, Msg);
  AssertFalse('leading zero', TokenizeFormula('{012}.x', ffStored, T, Msg, Pos));
  AssertFalse('zero', TokenizeFormula('{0}', ffStored, T, Msg, Pos));
end;

procedure TTestFormulaLexer.TestFormsDiffer;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertFalse('no braces when typing', TokenizeFormula('{1}.x', ffDisplay, T, Msg, Pos));
  AssertFalse('no # when stored', TokenizeFormula('#ease', ffStored, T, Msg, Pos));
end;

{ TTestFormula }

procedure TTestFormula.SetUp;
begin
  FResolver := TTestResolver.Create;
  FContext := TTestContext.Create;
  FFormula := TFormula.Create;
end;

procedure TTestFormula.TearDown;
begin
  FreeAndNil(FFormula);
  FreeAndNil(FContext);
  FreeAndNil(FResolver);
end;

function TTestFormula.Eval(const Text: string): double;
begin
  if not FFormula.Parse(Text, FResolver) then
    Fail(Format('"%s" did not parse: %s at %d', [Text, FFormula.ErrorMessage, FFormula.ErrorPos]));
  if not FFormula.Evaluate(FContext, Result) then
    Fail(Format('"%s" did not evaluate: %s', [Text, FFormula.ErrorMessage]));
end;

procedure TTestFormula.AssertValue(const Text: string; Expected: double);
begin
  AssertNear(Text, Expected, Eval(Text), 1e-9);
end;

procedure TTestFormula.AssertParseError(const Text, Msg: string; Pos: integer);
begin
  AssertFalse(Text + ' parses', FFormula.Parse(Text, FResolver));
  AssertFalse(Text + ' valid', FFormula.Valid);
  AssertEquals(Text + ' message', Msg, FFormula.ErrorMessage);
  AssertEquals(Text + ' position', Pos, FFormula.ErrorPos);
end;

procedure TTestFormula.AssertEvalError(const Text, Msg: string);
var
  V: double;
begin
  AssertTrue(Text + ' parses', FFormula.Parse(Text, FResolver));
  AssertFalse(Text + ' evaluates', FFormula.Evaluate(FContext, V));
  AssertEquals(Text + ' message', Msg, FFormula.ErrorMessage);
end;

procedure TTestFormula.TestNumbers;
begin
  AssertValue('42', 42);
  AssertValue('0.25', 0.25);
  AssertValue('7/2', 3.5);
end;

procedure TTestFormula.TestPrecedence;
begin
  AssertValue('2 + 3 * 4', 14);
  AssertValue('(2 + 3) * 4', 20);
  AssertValue('10 - 2 - 3', 5);
  AssertValue('8 / 2 / 2', 2);
  AssertValue('2 * 3 + 4 * 5', 26);
end;

procedure TTestFormula.TestPowerAndUnaryMinus;
begin
  AssertValue('2^3^2', 512);
  AssertValue('-2^2', -4);
  AssertValue('(-2)^2', 4);
  AssertValue('2^-1', 0.5);
  AssertValue('2 * -3', -6);
  AssertValue('4 - -2', 6);
  AssertValue('+5', 5);
end;

procedure TTestFormula.TestTrigUsesDegrees;
begin
  AssertValue('sin(30)', 0.5);
  AssertValue('cos(60)', 0.5);
  AssertValue('tan(45)', 1);
  AssertValue('asin(0.5)', 30);
  AssertValue('acos(0)', 90);
  AssertValue('atan2(1, 1)', 45);
  AssertValue('atan2(1, -1)', 135);
end;

procedure TTestFormula.TestOtherFunctions;
begin
  AssertValue('sqrt(16)', 4);
  AssertValue('abs(-3)', 3);
  AssertValue('min(3, 1, 2)', 1);
  AssertValue('max(3, 7)', 7);
  AssertValue('max(1, 2, 9, 4)', 9);
end;

procedure TTestFormula.TestRoundHalfAwayFromZero;
begin
  AssertValue('round(2.5)', 3);
  AssertValue('round(3.5)', 4);
  AssertValue('round(-2.5)', -3);
  AssertValue('round(2.4)', 2);
end;

procedure TTestFormula.TestFunctionNamesIgnoreCase;
begin
  AssertValue('SIN(30) + Max(1, 2)', 2.5);
end;

procedure TTestFormula.TestMeasurementsAndVariables;
var
  Refs: TFormulaReferenceArray;
begin
  AssertValue('@waist/4 + #ease_waist', 200);
  AssertEquals('stored', '@waist/4 + {4}', FFormula.StoredText);
  Refs := FFormula.References;
  AssertEquals('reference count', 2, Length(Refs));
  AssertTrue('measurement', Refs[0].Kind = rkMeasurement);
  AssertEquals('key', 'waist', Refs[0].Id);
  AssertTrue('variable', Refs[1].Kind = rkVariable);
  AssertEquals('variable id', '4', Refs[1].Id);
end;

procedure TTestFormula.TestObjectProperties;
var
  Refs: TFormulaReferenceArray;
begin
  AssertValue('Line_A_B.length + B.x / 2', 175);
  AssertEquals('stored', '{3}.length + {2}.x / 2', FFormula.StoredText);
  Refs := FFormula.References;
  AssertEquals('reference count', 2, Length(Refs));
  AssertTrue('object', Refs[0].Kind = rkObject);
  AssertEquals('id', '3', Refs[0].Id);
  AssertEquals('property', 'length', Refs[0].Prop);
end;

procedure TTestFormula.TestNamesIgnoreCase;
begin
  AssertValue('line_a_b.LENGTH + @WAIST + #Ease_Waist', 865);
  AssertEquals('stored', '{3}.length + @waist + {4}', FFormula.StoredText);
  AssertEquals('display uses current spelling', 'Line_A_B.length + @waist + #ease_waist',
    FFormula.DisplayText(FResolver));
end;

procedure TTestFormula.TestSpacingIsKept;
begin
  AssertTrue(FFormula.Parse('  @waist /4+ 1.50', FResolver));
  AssertEquals('stored', '  @waist /4+ 1.50', FFormula.StoredText);
  AssertEquals('display', '  @waist /4+ 1.50', FFormula.DisplayText(FResolver));
end;

procedure TTestFormula.TestReferencesAreUnique;
begin
  AssertTrue(FFormula.Parse('#ease_waist + #EASE_WAIST * A.x + A.x + A.y', FResolver));
  AssertEquals(3, Length(FFormula.References));
end;

procedure TTestFormula.TestRenameKeepsFormula;
begin
  AssertTrue(FFormula.Parse('A.x + #dart', FResolver));
  FResolver.Objects.Values['1'] := 'Waist_Front';
  FResolver.Variables.Values['5'] := 'dart_width';
  AssertEquals('{1}.x + {5}', FFormula.StoredText);
  AssertEquals('Waist_Front.x + #dart_width', FFormula.DisplayText(FResolver));
end;

procedure TTestFormula.TestStoredRoundTrip;
var
  Stored: string;
  V: double;
begin
  AssertTrue(FFormula.Parse('Line_A_B.length * 2 - @hip / 4 + #dart', FResolver));
  Stored := FFormula.StoredText;
  AssertTrue('loads', FFormula.ParseStored(Stored));
  AssertEquals('same stored text', Stored, FFormula.StoredText);
  AssertTrue(FFormula.Evaluate(FContext, V));
  AssertNear('value', 25, V);
  AssertEquals('display', 'Line_A_B.length * 2 - @hip / 4 + #dart', FFormula.DisplayText(FResolver));
end;

procedure TTestFormula.TestDanglingId;
var
  V: double;
begin
  AssertTrue(FFormula.ParseStored('{99}.x + 1'));
  AssertEquals('display keeps the ID', '{99}.x + 1', FFormula.DisplayText(FResolver));
  AssertFalse(FFormula.Evaluate(FContext, V));
  AssertEquals(Format(rsFormulaNoValue, ['{99}.x']), FFormula.ErrorMessage);
  AssertEquals(1, FFormula.ErrorPos);
end;

procedure TTestFormula.TestIsLiteral;
begin
  AssertTrue('number', FFormula.Parse('12.5', FResolver) and FFormula.IsLiteral);
  AssertTrue('negative number', FFormula.Parse('-3', FResolver) and FFormula.IsLiteral);
  AssertFalse('sum', FFormula.Parse('2 + 1', FResolver) and FFormula.IsLiteral);
  AssertFalse('measurement', FFormula.Parse('@waist', FResolver) and FFormula.IsLiteral);
  FFormula.Parse('3 +', FResolver);
  AssertFalse('invalid', FFormula.IsLiteral);
end;

procedure TTestFormula.TestDecimalPointIgnoresLocale;
var
  Saved: char;
begin
  Saved := DefaultFormatSettings.DecimalSeparator;
  DefaultFormatSettings.DecimalSeparator := ',';
  try
    AssertValue('0.5 + 1.25', 1.75);
  finally
    DefaultFormatSettings.DecimalSeparator := Saved;
  end;
end;

procedure TTestFormula.TestEmpty;
begin
  AssertParseError('', rsFormulaEmpty, 1);
  AssertParseError('   ', rsFormulaEmpty, 1);
end;

procedure TTestFormula.TestSyntaxErrors;
begin
  AssertParseError('3 +', rsFormulaEndsTooSoon, 4);
  AssertParseError('(1 + 2', rsFormulaExpectedClose, 7);
  AssertParseError('1 + 2)', Format(rsFormulaUnexpected, [')']), 6);
  AssertParseError('3 * * 4', rsFormulaExpectedValue, 5);
  AssertParseError('2 3', Format(rsFormulaUnexpected, ['3']), 3);
  AssertParseError('()', rsFormulaExpectedValue, 2);
end;

procedure TTestFormula.TestUnknownNames;
begin
  AssertParseError('foo + 1', Format(rsFormulaUnknownName, ['foo']), 1);
  AssertParseError('1 + @chest', Format(rsFormulaUnknownMeasurement, ['chest']), 5);
  AssertParseError('#nope', Format(rsFormulaUnknownVariable, ['nope']), 1);
  AssertParseError('Front.x', Format(rsFormulaUnknownName, ['Front']), 1);
  AssertParseError('ease_waist * 2', Format(rsFormulaMissingHash, ['ease_waist', 'ease_waist']), 1);
end;

procedure TTestFormula.TestPropertyErrors;
begin
  AssertParseError('A + 1', Format(rsFormulaNeedsProperty, ['A', 'A', 'A']), 1);
  AssertParseError('2 * A.length', Format(rsFormulaUnknownProperty, ['A', 'length']), 7);
end;

procedure TTestFormula.TestFunctionErrors;
begin
  AssertParseError('sin 30', Format(rsFormulaExpectedBracket, ['sin']), 5);
  AssertParseError('1 + sin(1, 2)', Format(rsFormulaArgCount, ['sin', 1]), 5);
  AssertParseError('min(1)', Format(rsFormulaArgCountAtLeast, ['min', 2]), 1);
  AssertParseError('max(1, 2', rsFormulaExpectedClose, 9);
end;

// A formula from a shared file or the Automation API must not overflow the
// stack: brackets, signs and long chains all build deep trees
procedure TTestFormula.TestTooDeep;
var
  Deep: string;
  V: double;
begin
  Deep := StringOfChar('(', MAX_FORMULA_DEPTH) + '1' + StringOfChar(')', MAX_FORMULA_DEPTH);
  AssertTrue('at the limit', FFormula.Parse(Deep, FResolver));
  AssertTrue(FFormula.Evaluate(FContext, V));
  AssertFalse('brackets', FFormula.Parse(StringOfChar('(', 100000) + '1' + StringOfChar(')', 100000), FResolver));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
  AssertFalse('signs', FFormula.Parse(StringOfChar('-', 100000) + '1', FResolver));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
  AssertFalse('functions', FFormula.Parse(DupeString('abs(', 100000) + '1' + StringOfChar(')', 100000), FResolver));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
  AssertFalse('powers', FFormula.Parse(DupeString('2^', 100000) + '1', FResolver));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
  AssertFalse('a chain', FFormula.Parse('1' + DupeString('+1', 100000), FResolver));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
  AssertFalse('stored form', FFormula.ParseStored(StringOfChar('(', 100000) + '1' + StringOfChar(')', 100000)));
  AssertEquals(Format(rsFormulaTooDeep, [MAX_FORMULA_DEPTH]), FFormula.ErrorMessage);
end;

procedure TTestFormula.TestStoredFormRejectsNames;
begin
  AssertFalse(FFormula.ParseStored('A.x + 1'));
  AssertEquals(rsFormulaNamesNotIds, FFormula.ErrorMessage);
  AssertFalse(FFormula.ParseStored('foo'));
  AssertEquals(rsFormulaNamesNotIds, FFormula.ErrorMessage);
end;

procedure TTestFormula.TestFailedParseKeepsText;
var
  V: double;
begin
  AssertTrue(FFormula.Parse('@waist', FResolver));
  AssertFalse(FFormula.Parse('@waist +', FResolver));
  AssertEquals('text kept for saving', '@waist +', FFormula.StoredText);
  AssertEquals('shown as typed', '@waist +', FFormula.DisplayText(FResolver));
  AssertEquals('no references', 0, Length(FFormula.References));
  AssertFalse('cannot evaluate', FFormula.Evaluate(FContext, V));
  AssertEquals('keeps the parse error', rsFormulaEndsTooSoon, FFormula.ErrorMessage);
end;

procedure TTestFormula.TestEvaluationErrors;
begin
  AssertEvalError('1 / (2 - 2)', rsFormulaDivideByZero);
  AssertEquals('at the division', 3, FFormula.ErrorPos);
  AssertEvalError('sqrt(-1)', rsFormulaSqrtNegative);
  AssertEvalError('asin(2)', Format(rsFormulaOutOfDomain, ['asin']));
  AssertEvalError('10^400', rsFormulaNotANumber);
  AssertEquals('whole formula', 0, FFormula.ErrorPos);
  AssertEvalError('(-8)^(1/3)', rsFormulaNotANumber);
  AssertEvalError('@back_length', Format(rsFormulaNoValue, ['@back_length']));
end;

procedure TTestFormula.TestDisplayErrorPos;
var
  V: double;
begin
  // Stored: {3}.length / ({1}.x - {1}.x); the '/' moves when shown with names
  AssertTrue(FFormula.Parse('Line_A_B.length / (A.x - A.x)', FResolver));
  AssertFalse(FFormula.Evaluate(FContext, V));
  AssertEquals('stored position', 12, FFormula.ErrorPos);
  AssertEquals('display position', 17, FFormula.DisplayErrorPos(FResolver));
end;

procedure TTestFormulaLexer.TestHugeNumber;
var
  Tokens: TFormulaTokenArray;
  Err: string;
  ErrPos: integer;
  Product: double;
begin
  AssertFalse(TokenizeFormula('2 + 1e400', ffStored, Tokens, Err, ErrPos));
  AssertEquals(rsFormulaNumberRange, Err);
  AssertEquals('at the number', 5, ErrPos);
  Product := 1.5;
  Product := Product * 2;
  AssertEquals('no exception left behind', 3.0, Product);
end;

procedure TTestFormulaLexer.TestNumberSuffixes;
var
  T: TFormulaTokenArray;
  Msg: string;
  Pos: integer;
begin
  AssertTrue(Msg, TokenizeFormula('400mm + 1.5cm*2in - 3', ffDisplay, T, Msg, Pos));
  AssertEquals('tokens', 7, Length(T));
  AssertTrue('mm', T[0].Suffix = nsMillimetre);
  AssertNear('written value', 400, T[0].Value);
  AssertEquals('suffix is part of the number', 5, T[0].Len);
  AssertTrue('cm', T[2].Suffix = nsCentimetre);
  AssertTrue('in', T[4].Suffix = nsInch);
  AssertTrue('plain', T[6].Suffix = nsNone);
  AssertTrue('any case', TokenizeFormula('2IN', ffDisplay, T, Msg, Pos) and (T[0].Suffix = nsInch));
  AssertTrue('stored form too', TokenizeFormula('{3}.x + 2in', ffStored, T, Msg, Pos) and (T[2].Suffix = nsInch));
  AssertFalse('unknown unit', TokenizeFormula('3 + 2ft', ffDisplay, T, Msg, Pos));
  AssertEquals(Format(rsFormulaUnknownSuffix, ['ft']), Msg);
  AssertEquals('at the unit', 6, Pos);
end;

procedure TTestFormula.TestUnitSuffixes;
begin
  AssertValue('400mm', 400);
  AssertValue('1.5cm', 15);
  AssertValue('2in', 50.8);
  AssertValue('-1in', -25.4);
  AssertValue('1e1mm', 10);
  AssertValue('(@waist * 2) + 1in', 2 * Eval('@waist') + 25.4);
  // The suffix is optional: a plain number is in the pattern's unit
  AssertValue('400 + 400mm', 800);
end;

procedure TTestFormula.TestSuffixRoundTrip;
var
  Stored: string;
begin
  AssertTrue(FFormula.Parse('Line_A_B.length + 2in', FResolver));
  Stored := FFormula.StoredText;
  AssertTrue('stored keeps the unit', Pos('2in', Stored) > 0);
  AssertTrue(FFormula.ParseStored(Stored));
  AssertEquals('display', 'Line_A_B.length + 2in', FFormula.DisplayText(FResolver));
  AssertTrue(FFormula.Parse('-2.5cm', FResolver));
  AssertTrue('literal', FFormula.IsLiteral);
  AssertTrue('its unit', FFormula.LiteralSuffix = nsCentimetre);
  AssertTrue(FFormula.Parse('12', FResolver));
  AssertTrue('plain', FFormula.LiteralSuffix = nsNone);
  AssertTrue(FFormula.Parse('2in + 1', FResolver));
  AssertTrue('not a literal', FFormula.LiteralSuffix = nsNone);
end;

procedure TTestFormula.TestUnknownSuffix;
begin
  AssertParseError('10 + 3pt', Format(rsFormulaUnknownSuffix, ['pt']), 7);
end;

initialization
  RegisterTest(TTestFormulaLexer);
  RegisterTest(TTestFormula);

end.
