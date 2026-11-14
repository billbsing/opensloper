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

unit Sloper.Tests.JSON;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, fpjson, Sloper.Core.JSON;

type
  TTestJSON = class(TOSTestCase)
  published
    procedure TestWholeNumbers;
    procedure TestShortestDecimals;
    procedure TestDecimalsRoundTrip;
    procedure TestLayout;
    procedure TestEmptyContainers;
    procedure TestEscapes;
    procedure TestParseErrors;
    // Nesting deeper than any file needs is refused before parsing, which
    // recurses once a level and would overflow the stack
    procedure TestDeepNestingRefused;
    procedure TestTypedAccess;
  end;

implementation

uses
  SysUtils;

const
  ROUND_TRIP_VALUES: array[0..4] of double = (1 / 3, 0.1 + 0.2, 123.456789, 1e-7, 2.5e20);

procedure TTestJSON.TestWholeNumbers;
begin
  AssertEquals('720', FormatJSONFloat(720));
  AssertEquals('-15', FormatJSONFloat(-15));
  AssertEquals('0', FormatJSONFloat(0));
end;

procedure TTestJSON.TestShortestDecimals;
var
  Saved: char;
begin
  AssertEquals('720.5', FormatJSONFloat(720.5));
  AssertEquals('0.1', FormatJSONFloat(0.1));
  AssertEquals('-12.75', FormatJSONFloat(-12.75));
  Saved := DefaultFormatSettings.DecimalSeparator;
  DefaultFormatSettings.DecimalSeparator := ',';
  try
    AssertEquals('locale ignored', '2.5', FormatJSONFloat(2.5));
  finally
    DefaultFormatSettings.DecimalSeparator := Saved;
  end;
end;

procedure TTestJSON.TestDecimalsRoundTrip;
var
  V, Back: double;
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  for V in ROUND_TRIP_VALUES do
  begin
    Back := StrToFloat(FormatJSONFloat(V), Settings);
    AssertTrue(FormatJSONFloat(V) + ' reads back exactly', Back = V);
  end;
end;

procedure TTestJSON.TestLayout;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('format', 'test');
    Obj.Add('value', JSONFloat(720.5));
    Obj.Add('count', 3);
    Obj.Add('flag', True);
    Obj.Add('list', TJSONArray.Create([1, 'a']));
    Obj.Add('inner', TJSONObject.Create(['key', 'x']));
    AssertEquals(
      '{'#10 +
      '  "format": "test",'#10 +
      '  "value": 720.5,'#10 +
      '  "count": 3,'#10 +
      '  "flag": true,'#10 +
      '  "list": ['#10 +
      '    1,'#10 +
      '    "a"'#10 +
      '  ],'#10 +
      '  "inner": {'#10 +
      '    "key": "x"'#10 +
      '  }'#10 +
      '}'#10, JSONToText(Obj));
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TTestJSON.TestEmptyContainers;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create(['list', TJSONArray.Create, 'obj', TJSONObject.Create]);
  try
    AssertEquals('{'#10'  "list": [],'#10'  "obj": {}'#10'}'#10, JSONToText(Obj));
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TTestJSON.TestEscapes;
var
  Obj: TJSONObject;
  Back: TJSONObject;
  Msg, S: string;
begin
  Obj := TJSONObject.Create(['text', 'Say "hi"'#10'Ärmel']);
  try
    AssertTrue(ParseJSONObject(JSONToText(Obj), Back, Msg));
    try
      AssertTrue(GetJSONString(Back, 'text', S));
      AssertEquals('Say "hi"'#10'Ärmel', S);
    finally
      FreeAndNil(Back);
    end;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TTestJSON.TestDeepNestingRefused;
const
  // Far past the stack's depth for fpjson's recursion
  CRASH_DEPTH = 1000000;
  NEEDED_DEPTH = 40;
var
  Obj: TJSONObject;
  Err: string;
begin
  AssertFalse(ParseJSONObject('{"a":' + StringOfChar('[', CRASH_DEPTH) + StringOfChar(']', CRASH_DEPTH) + '}', Obj, Err));
  AssertEquals(Format(rsJSONTooDeep, [JSON_MAX_DEPTH]), Err);
  AssertNull(Obj);
  // Deeper than a file needs, but well within the limit
  AssertTrue(Err, ParseJSONObject('{"a":' + StringOfChar('[', NEEDED_DEPTH) + StringOfChar(']', NEEDED_DEPTH) + '}', Obj, Err));
  FreeAndNil(Obj);
  // Brackets in strings, escaped quotes too, are text, not nesting
  AssertTrue(Err, ParseJSONObject('{"a":"\"' + StringOfChar('[', CRASH_DEPTH) + '"}', Obj, Err));
  AssertEquals('"' + StringOfChar('[', CRASH_DEPTH), Obj.Get('a', ''));
  FreeAndNil(Obj);
end;

procedure TTestJSON.TestParseErrors;
var
  Obj: TJSONObject;
  Msg: string;
begin
  AssertFalse('syntax', ParseJSONObject('{"a": 1,', Obj, Msg));
  AssertTrue('syntax message', Pos('not valid JSON', Msg) > 0);
  AssertNull(Obj);
  AssertFalse('array', ParseJSONObject('[1, 2]', Obj, Msg));
  AssertEquals(rsJSONNotObject, Msg);
  AssertFalse('empty', ParseJSONObject('', Obj, Msg));
end;

procedure TTestJSON.TestTypedAccess;
var
  Obj: TJSONObject;
  Msg, S: string;
  D: double;
  I: integer;
begin
  AssertTrue(ParseJSONObject('{"s": "x", "n": 2.5, "i": 3, "b": true}', Obj, Msg));
  try
    AssertTrue(GetJSONString(Obj, 's', S));
    AssertFalse('number is not a string', GetJSONString(Obj, 'n', S));
    AssertTrue(GetJSONNumber(Obj, 'n', D));
    AssertNear('float', 2.5, D);
    AssertTrue('integer is a number', GetJSONNumber(Obj, 'i', D));
    AssertTrue(GetJSONInteger(Obj, 'i', I));
    AssertEquals(3, I);
    AssertFalse('float is not an integer', GetJSONInteger(Obj, 'n', I));
    AssertFalse('missing', GetJSONNumber(Obj, 'zz', D));
    AssertFalse('boolean is not a number', GetJSONNumber(Obj, 'b', D));
  finally
    FreeAndNil(Obj);
  end;
end;

initialization
  RegisterTest(TTestJSON);

end.
