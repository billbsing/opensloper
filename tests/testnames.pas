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

unit TestNames;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, fpcunit, testregistry, osTestCase, osNames;

type
  TTestNames = class(TOSTestCase)
  private
    FTaken: TStringList;
    function Taken(const Name: string): boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestValidNames;
    procedure TestInvalidNames;
    procedure TestFunctionNamesAreReserved;
    procedure TestSameNameIgnoresCase;
    procedure TestNextFreeNameKeepsFreeName;
    procedure TestNextFreeNameAppendsNumber;
    procedure TestNextFreeNameStripsNumber;
    procedure TestNextFreeNameIgnoresCase;
    procedure TestNextAutoName;
  end;

implementation

uses
  SysUtils;

procedure TTestNames.SetUp;
begin
  FTaken := TStringList.Create;
  FTaken.CaseSensitive := False;
end;

procedure TTestNames.TearDown;
begin
  FreeAndNil(FTaken);
end;

function TTestNames.Taken(const Name: string): boolean;
begin
  Result := FTaken.IndexOf(Name) >= 0;
end;

procedure TTestNames.TestValidNames;
begin
  AssertTrue('letter', IsValidName('A'));
  AssertTrue('line name', IsValidName('Line_A_B'));
  AssertTrue('digits after', IsValidName('A12'));
  AssertTrue('leading underscore', IsValidName('_tmp'));
end;

procedure TTestNames.TestInvalidNames;
begin
  AssertFalse('empty', IsValidName(''));
  AssertFalse('leading digit', IsValidName('1A'));
  AssertFalse('dash', IsValidName('A-2'));
  AssertFalse('dot', IsValidName('A.x'));
  AssertFalse('space', IsValidName('A B'));
  AssertFalse('non-ASCII', IsValidName('Ärmel'));
end;

procedure TTestNames.TestFunctionNamesAreReserved;
begin
  AssertFalse('sin', IsValidName('sin'));
  AssertFalse('any case', IsValidName('MAX'));
  AssertTrue('reserved', IsReservedName('atan2'));
  AssertTrue('longer name is fine', IsValidName('sine'));
end;

procedure TTestNames.TestSameNameIgnoresCase;
begin
  AssertTrue(SameName('Line_A_B', 'line_a_b'));
  AssertFalse(SameName('A', 'A2'));
end;

procedure TTestNames.TestNextFreeNameKeepsFreeName;
begin
  AssertEquals('A', NextFreeName('A', @Taken));
end;

procedure TTestNames.TestNextFreeNameAppendsNumber;
begin
  FTaken.Add('A');
  AssertEquals('A2', NextFreeName('A', @Taken));
  FTaken.Add('A2');
  AssertEquals('A3', NextFreeName('A', @Taken));
end;

procedure TTestNames.TestNextFreeNameStripsNumber;
begin
  FTaken.Add('A');
  FTaken.Add('A2');
  AssertEquals('copy of A2', 'A3', NextFreeName('A2', @Taken));
  FTaken.Add('Hip2');
  AssertEquals('copy of Hip2', 'Hip3', NextFreeName('Hip2', @Taken));
  FTaken.Add('B1');
  AssertEquals('copy of auto-named B1', 'B2', NextFreeName('B1', @Taken));
end;

procedure TTestNames.TestNextFreeNameIgnoresCase;
begin
  FTaken.Add('a');
  AssertEquals('A2', NextFreeName('A', @Taken));
end;

procedure TTestNames.TestNextAutoName;
var
  C: char;
begin
  AssertEquals('first', 'A', NextAutoName(@Taken));
  FTaken.Add('A');
  FTaken.Add('B');
  AssertEquals('next', 'C', NextAutoName(@Taken));
  for C := 'C' to 'Z' do
    FTaken.Add(C);
  AssertEquals('after Z', 'A1', NextAutoName(@Taken));
  FTaken.Add('A1');
  AssertEquals('then', 'B1', NextAutoName(@Taken));
  FTaken.Delete(FTaken.IndexOf('M'));
  AssertEquals('gap is reused', 'M', NextAutoName(@Taken));
end;

initialization
  RegisterTest(TTestNames);

end.
