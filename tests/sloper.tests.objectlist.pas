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

unit Sloper.Tests.ObjectList;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Pattern;

type
  TTestObjectList = class(TOSTestCase)
  private
    FPattern: TPattern;
    procedure Build;
    procedure AssertRows(const Msg, Expected: string; Filter: integer; const Search: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPointRow;
    procedure TestEdgeRow;
    procedure TestFormulasUseNames;
    procedure TestNotComputedHasNoValue;
    procedure TestFilters;
    procedure TestSearch;
    procedure TestSearchFormulas;
    procedure TestPlainClick;
    procedure TestToggle;
    procedure TestExtend;
    procedure TestExtendWithoutAnchor;
    procedure TestSharedCaptions;
    procedure TestVariableRow;
    procedure TestVariableSearch;
    procedure TestFailingVariableHasNoValue;
    procedure TestNewVariableName;
    procedure TestMeasurementRows;
    procedure TestMeasurementSearch;
    procedure TestMissingMeasurements;
    procedure TestNoMeasurementSet;
    procedure TestMeasurementChangeText;
  end;

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Measurements, Sloper.UI.ObjectList;

procedure TTestObjectList.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestObjectList.TearDown;
begin
  FreeAndNil(FPattern);
end;

// A (0, 0), B 100 to the right of A, and a line A-B
procedure TTestObjectList.Build;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddOffsetPoint('B', '1', omPolar, '100', '0');
  FPattern.AddLine('1', '2');
  FPattern.Evaluate;
end;

procedure TTestObjectList.AssertRows(const Msg, Expected: string; Filter: integer; const Search: string);
var
  Rows: TObjectRowArray;
  Row: TObjectRow;
  Names: string;
begin
  Rows := ObjectRows(FPattern, TObjectFilter(Filter), Search);
  Names := '';
  for Row in Rows do
    Names := Trim(Names + ' ' + Row.Name);
  AssertEquals(Msg, Expected, Names);
end;

procedure TTestObjectList.TestPointRow;
var
  Row: TObjectRow;
begin
  Build;
  Row := ObjectRow(FPattern, FPattern.FindObject('B'));
  AssertEquals('key', '2', Row.Key);
  AssertEquals('name', 'B', Row.Name);
  AssertEquals('operation', rsTypeOffset, Row.Operation);
  AssertEquals('value', '100, 0 mm', Row.Value);
  AssertEquals('formulas', 'Length = 100; Angle = 0', Row.Formulas);
  AssertEquals('state', rsStateValid, Row.StateText);
end;

procedure TTestObjectList.TestEdgeRow;
var
  Row: TObjectRow;
begin
  Build;
  Row := ObjectRow(FPattern, FPattern.FindObject('Line_A_B'));
  AssertEquals('operation', rsTypeLine, Row.Operation);
  AssertEquals('value', '100 mm', Row.Value);
  AssertEquals('no formulas', '', Row.Formulas);
end;

procedure TTestObjectList.TestFormulasUseNames;
var
  Point: TDraftObject;
begin
  Build;
  Point := FPattern.AddFreePoint('C', 'Line_A_B.length / 2', '0');
  FPattern.Evaluate;
  AssertEquals('X = Line_A_B.length / 2; Y = 0', ObjectRow(FPattern, Point).Formulas);
end;

procedure TTestObjectList.TestNotComputedHasNoValue;
begin
  FPattern.AddFreePoint('A', '0', '0');
  AssertEquals('', ObjectRow(FPattern, FPattern.FindObject('A')).Value);
end;

procedure TTestObjectList.TestFilters;
begin
  Build;
  FPattern.AddFreePoint('C', '1 / A.x', '0');
  FPattern.Evaluate;
  AssertRows('all', 'A B Line_A_B C', Ord(ofAll), '');
  AssertRows('points', 'A B C', Ord(ofPoints), '');
  AssertRows('edges', 'Line_A_B', Ord(ofEdges), '');
  AssertRows('problems', 'C', Ord(ofProblems), '');
end;

procedure TTestObjectList.TestSearch;
begin
  Build;
  AssertRows('by name, ignoring case', 'Line_A_B', Ord(ofAll), 'line_a');
  AssertRows('by operation', 'B', Ord(ofAll), 'offset');
  AssertRows('spaces around it ignored', 'B', Ord(ofAll), '  offset ');
  AssertRows('with a filter', '', Ord(ofEdges), 'offset');
  AssertRows('no match', '', Ord(ofAll), 'zzz');
end;

procedure TTestObjectList.TestSearchFormulas;
begin
  Build;
  FPattern.AddFreePoint('C', 'Line_A_B.length', '0');
  FPattern.Evaluate;
  AssertRows('finds the object reading a name', 'Line_A_B C', Ord(ofAll), 'line_a_b');
end;

procedure TTestObjectList.TestPlainClick;
begin
  AssertEquals('only the clicked one', 'b',
    string.Join(' ', SelectionAfterClick(['a', 'b', 'c'], ['a', 'c'], 'a', 'b', False, False)));
end;

procedure TTestObjectList.TestToggle;
begin
  AssertEquals('added', 'a b', string.Join(' ', SelectionAfterClick(['a', 'b', 'c'], ['a'], 'a', 'b', True, False)));
  AssertEquals('removed', 'b', string.Join(' ', SelectionAfterClick(['a', 'b', 'c'], ['a', 'b'], 'a', 'a', True, False)));
end;

procedure TTestObjectList.TestExtend;
begin
  AssertEquals('down', 'b c d', string.Join(' ', SelectionAfterClick(['a', 'b', 'c', 'd'], ['b'], 'b', 'd', False, True)));
  AssertEquals('up', 'b c d', string.Join(' ', SelectionAfterClick(['a', 'b', 'c', 'd'], ['d'], 'd', 'b', False, True)));
end;

procedure TTestObjectList.TestExtendWithoutAnchor;
begin
  AssertEquals('anchor filtered out', 'b', string.Join(' ', SelectionAfterClick(['a', 'b'], ['z'], 'z', 'b', False, True)));
end;

procedure TTestObjectList.TestSharedCaptions;
begin
  AssertEquals(rsFieldAngle1, FieldCaption('angle1'));
  AssertEquals(Format(rsFieldNodeIn, ['2']), FieldCaption('node2.lengthIn'));
  AssertEquals('unknown field', 'odd', FieldCaption('odd'));
  AssertEquals(rsStateBlocked, StateCaption(esBlocked));
end;

procedure TTestObjectList.TestVariableRow;
var
  Row: TVariableRow;
begin
  FPattern.AddVariable('ease', '20', 'Waist ease');
  FPattern.AddVariable('half', '#ease / 2');
  FPattern.Evaluate;
  Row := VariableRow(FPattern, FPattern.FindVariable('half'));
  AssertEquals('name', 'half', Row.Name);
  AssertEquals('formula with names', '#ease / 2', Row.Formula);
  AssertEquals('value', '10', Row.Value);
  AssertEquals('state', rsStateValid, Row.StateText);
  AssertEquals('description', 'Waist ease', VariableRow(FPattern, FPattern.FindVariable('ease')).Description);
end;

procedure TTestObjectList.TestVariableSearch;
var
  Rows: TVariableRowArray;
begin
  FPattern.AddVariable('ease', '20', 'Waist ease');
  FPattern.AddVariable('half', '#ease / 2');
  FPattern.AddVariable('dart', '30', 'Back only');
  FPattern.Evaluate;
  AssertEquals('all', 3, Length(VariableRows(FPattern, '')));
  Rows := VariableRows(FPattern, 'EASE');
  AssertEquals('by name and formula', 2, Length(Rows));
  Rows := VariableRows(FPattern, 'back');
  AssertEquals('by description', 1, Length(Rows));
  AssertEquals('dart', Rows[0].Name);
end;

procedure TTestObjectList.TestFailingVariableHasNoValue;
var
  Row: TVariableRow;
begin
  FPattern.AddVariable('bad', '1 / 0');
  FPattern.Evaluate;
  Row := VariableRow(FPattern, FPattern.FindVariable('bad'));
  AssertEquals('value', '', Row.Value);
  AssertEquals('state', rsStateError, Row.StateText);
end;

procedure TTestObjectList.TestNewVariableName;
begin
  AssertEquals('variable', FPattern.NewVariableName);
  FPattern.AddVariable('variable', '1');
  AssertEquals('variable2', FPattern.NewVariableName);
  FPattern.AddVariable('Variable2', '1');
  AssertEquals('ignoring case', 'variable3', FPattern.NewVariableName);
end;

procedure TTestObjectList.TestMeasurementRows;
var
  MeasurementSet: TMeasurementSet;
  Rows: TMeasurementRowArray;
begin
  MeasurementSet := TMeasurementSet.Create;
  try
    MeasurementSet.Add('waist', 720.5, 'Round the waist');
    MeasurementSet.Add('hip', 960);
    Rows := MeasurementRows(FPattern, MeasurementSet, '');
    AssertEquals(2, Length(Rows));
    AssertEquals('waist', Rows[0].Key);
    AssertEquals('720.5', Rows[0].Value);
    AssertEquals('Round the waist', Rows[0].Description);
    AssertFalse('in the set', Rows[0].Missing);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestObjectList.TestMeasurementSearch;
var
  MeasurementSet: TMeasurementSet;
  Rows: TMeasurementRowArray;
begin
  MeasurementSet := TMeasurementSet.Create;
  try
    MeasurementSet.Add('waist', 720, 'Round the middle');
    MeasurementSet.Add('hip', 960);
    Rows := MeasurementRows(FPattern, MeasurementSet, 'WAI');
    AssertEquals('by key', 1, Length(Rows));
    Rows := MeasurementRows(FPattern, MeasurementSet, 'middle');
    AssertEquals('by description', 1, Length(Rows));
    AssertEquals('waist', Rows[0].Key);
  finally
    FreeAndNil(MeasurementSet);
  end;
end;

// A key the pattern reads that this set lacks, as after switching sets
procedure TTestObjectList.TestMissingMeasurements;
var
  MeasurementSet, Other: TMeasurementSet;
  Rows: TMeasurementRowArray;
begin
  MeasurementSet := TMeasurementSet.Create;
  Other := TMeasurementSet.Create;
  try
    MeasurementSet.Add('waist', 720);
    MeasurementSet.Add('chest', 900);
    Other.Add('waist', 800);
    FPattern.Measurements := MeasurementSet;
    FPattern.AddFreePoint('A', '@waist + @chest', '0');
    FPattern.Measurements := Other;
    FPattern.Evaluate;
    Rows := MeasurementRows(FPattern, Other, '');
    AssertEquals('the set, then what is missing', 2, Length(Rows));
    AssertEquals('waist', Rows[0].Key);
    AssertEquals('chest', Rows[1].Key);
    AssertTrue('missing', Rows[1].Missing);
    AssertEquals('no value', '', Rows[1].Value);
    FPattern.Measurements := nil;
    FPattern.Evaluate;
  finally
    FreeAndNil(Other);
    FreeAndNil(MeasurementSet);
  end;
end;

procedure TTestObjectList.TestNoMeasurementSet;
begin
  AssertEquals('nothing to list', 0, Length(MeasurementRows(FPattern, nil, '')));
end;

procedure TTestObjectList.TestMeasurementChangeText;
var
  Change: TMeasurementChange;
begin
  Change := Default(TMeasurementChange);
  Change.Key := 'waist';
  Change.OldValue := 820;
  Change.Value := 830.5;
  AssertEquals('@waist 820 → 830.5 mm saved to bill.slm', MeasurementChangeText(Change, ConcatPaths(['sets', 'bill.slm'])));
  Change.Added := True;
  AssertEquals('@waist 830.5 mm added to bill.slm', MeasurementChangeText(Change, 'bill.slm'));
end;

initialization
  RegisterTest(TTestObjectList);

end.
