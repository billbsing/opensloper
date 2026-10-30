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

unit Sloper.Tests.Completion;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Evaluator, Sloper.Core.Measurements, Sloper.Core.Pattern,
  Sloper.UI.Completion;

type
  TTestCompletion = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    function Names(const Text: string; Node: TEvalNode = nil; Explicit: boolean = False): string;
    function Offered(const Text: string; Node: TEvalNode = nil): TCompletion;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMeasurements;
    procedure TestVariables;
    procedure TestProperties;
    procedure TestLineHasAngle;
    procedure TestBareWordOffersEverything;
    procedure TestPrefixComesFirst;
    procedure TestEmptyWordOffersNothing;
    procedure TestExplicitOffersAll;
    procedure TestNumbersOfferNothing;
    procedure TestAfterOperator;
    procedure TestOwnObjectLeftOut;
    procedure TestVariableFormulaHasNoObjects;
    procedure TestNoMeasurementSet;
    procedure TestFinishedWordOffersNothing;
    procedure TestApplyReplacesWord;
    procedure TestApplyInsideWord;
    procedure TestDetails;
    procedure TestCaretOutOfRange;
  end;

implementation

uses
  Sloper.Core.Draft;

procedure TTestCompletion.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FSet.Add('hip', 960);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
  FPattern.AddVariable('ease', '20');
  FPattern.AddVariable('waist_ease', '10');
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('Apex', '100', '0');
  FPattern.AddFreePoint('Waist', '100', '50');
  FPattern.AddLine('3', '4', erOutline, 'Hem');
  FPattern.AddCurve('3', '5', '0', '10', '0', '10', erOutline, 'Side');
  FPattern.Evaluate;
end;

procedure TTestCompletion.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestCompletion.Offered(const Text: string; Node: TEvalNode): TCompletion;
begin
  Result := FormulaCompletion(FPattern, Node, Text, Length(Text), False);
end;

function TTestCompletion.Names(const Text: string; Node: TEvalNode; Explicit: boolean): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in FormulaCompletion(FPattern, Node, Text, Length(Text), Explicit).Items do
    Result := Trim(Result + ' ' + Item.Insert);
end;

procedure TTestCompletion.TestMeasurements;
begin
  AssertEquals('all', 'hip waist', Names('@'));
  AssertEquals('narrowed, ignoring case', 'waist', Names('10 + @WA'));
end;

procedure TTestCompletion.TestVariables;
begin
  AssertEquals('all', 'ease waist_ease', Names('#'));
  AssertEquals('within the name too', 'ease waist_ease', Names('#ea'));
end;

procedure TTestCompletion.TestProperties;
begin
  AssertEquals('a point', 'x y', Names('A.'));
  AssertEquals('an edge, ignoring case', 'angle1 angle2 length', Names('side.'));
  AssertEquals('narrowed, starting with it first', 'length angle1 angle2', Names('Side.le'));
  AssertEquals('no such object', '', Names('Nothing.'));
end;

procedure TTestCompletion.TestLineHasAngle;
begin
  AssertEquals('angle angle1 angle2 length', Names('Hem.'));
end;

procedure TTestCompletion.TestBareWordOffersEverything;
begin
  AssertEquals('objects, variables and measurements', 'Waist. @waist #waist_ease', Names('wa'));
  AssertEquals('functions', 'sqrt(', Names('sq'));
  AssertEquals('the start of a name, then inside one', 'Side. sin( asin(', Names('si'));
end;

procedure TTestCompletion.TestPrefixComesFirst;
begin
  AssertEquals('names that start with it, in order', 'A. abs( acos( Apex. asin( atan2(', Copy(Names('a'), 1, 32));
  AssertEquals('then names that contain it', '#ease #waist_ease', Names('ease'));
end;

procedure TTestCompletion.TestEmptyWordOffersNothing;
begin
  AssertEquals('empty field', '', Names(''));
  AssertEquals('after an operator', '', Names('10 + '));
end;

procedure TTestCompletion.TestExplicitOffersAll;
begin
  AssertTrue('objects', Pos('Hem.', Names('', nil, True)) > 0);
  AssertTrue('functions', Pos('sqrt(', Names('10 + ', nil, True)) > 0);
end;

procedure TTestCompletion.TestNumbersOfferNothing;
begin
  AssertEquals('whole', '', Names('12'));
  AssertEquals('decimal', '', Names('1.5'));
  AssertEquals('digit in a name is fine', 'atan2(', Names('atan'));
end;

procedure TTestCompletion.TestAfterOperator;
var
  Completion: TCompletion;
begin
  Completion := Offered('10 * (A.x + Si');
  AssertEquals('replaces only the word', 12, Completion.From);
  AssertEquals(14, Completion.Upto);
end;

procedure TTestCompletion.TestOwnObjectLeftOut;
var
  Hem: TEvalNode;
begin
  Hem := FPattern.FindObject('Hem');
  AssertEquals('another object', 'Hem.', Names('He'));
  AssertEquals('a formula cannot use itself', '', Names('He', Hem));
  AssertEquals('nor its properties', '', Names('Hem.', Hem));
end;

procedure TTestCompletion.TestVariableFormulaHasNoObjects;
var
  Ease: TEvalNode;
begin
  Ease := FPattern.FindVariable('ease');
  AssertEquals('no objects, no itself', '@waist #waist_ease', Names('wa', Ease));
  AssertEquals('no properties', '', Names('A.', Ease));
  AssertEquals('itself', 'waist_ease', Names('#', Ease));
end;

procedure TTestCompletion.TestNoMeasurementSet;
begin
  FPattern.Measurements := nil;
  AssertEquals('', Names('@'));
  AssertEquals('Waist. #waist_ease', Names('wa'));
end;

procedure TTestCompletion.TestFinishedWordOffersNothing;
begin
  AssertEquals('measurement', '', Names('@waist'));
  AssertEquals('property', '', Names('Side.length'));
  AssertEquals('a longer name still shows', 'angle angle1 angle2', Names('Hem.angle'));
end;

procedure TTestCompletion.TestApplyReplacesWord;
var
  Completion: TCompletion;
  Caret: integer;
begin
  Completion := Offered('10 + Si');
  AssertEquals('Side', Completion.Items[0].Name);
  AssertEquals('10 + Side.', ApplyCompletion('10 + Si', Completion, 0, Caret));
  AssertEquals('caret after it', 10, Caret);
end;

procedure TTestCompletion.TestApplyInsideWord;
var
  Completion: TCompletion;
  Caret: integer;
begin
  Completion := FormulaCompletion(FPattern, nil, '@wa + 1', 2, False);
  AssertEquals('waist', Completion.Items[0].Name);
  AssertEquals('@waist + 1', ApplyCompletion('@wa + 1', Completion, 0, Caret));
  AssertEquals(6, Caret);
end;

procedure TTestCompletion.TestDetails;
begin
  AssertEquals('measurement', '720 mm', Offered('@wa').Items[0].Detail);
  AssertEquals('variable', '10', Offered('#waist').Items[0].Detail);
  AssertEquals('property', '100', Offered('Hem.le').Items[0].Detail);
  AssertEquals('function', rsCompletionFunction, Offered('sq').Items[0].Detail);
end;

procedure TTestCompletion.TestCaretOutOfRange;
begin
  AssertEquals(0, Length(FormulaCompletion(FPattern, nil, 'A.', 9, False).Items));
  AssertEquals(0, Length(FormulaCompletion(FPattern, nil, 'A.', -1, False).Items));
end;

initialization
  RegisterTest(TTestCompletion);

end.
