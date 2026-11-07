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

// The generated reference pages: committed copies that still match the
// program, and the command-line table the parser is built from.
unit Sloper.Tests.Docs;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase;

type
  TTestDocs = class(TOSTestCase)
  published
    procedure TestCommittedPagesAreCurrent;
    procedure TestUnknownTopic;
    procedure TestEveryFunctionListed;
    procedure TestParserHasEveryOption;
    procedure TestEveryCommandListed;
  end;

implementation

uses
  SysUtils, ConsoleTools, Sloper.Core.JSON, Sloper.Core.Formula, Sloper.CLI.Arguments, Sloper.Docs.Reference;

function ReferenceFolder: string;
begin
  Result := ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'reference']);
end;

// Run ./build-docs.sh after ./build.sh to write them again
procedure TTestDocs.TestCommittedPagesAreCurrent;
var
  Topic, Expected, Committed, Err: string;
begin
  for Topic in DocTopics do
  begin
    AssertTrue(Topic, ReferencePage(Topic, Expected));
    AssertTrue(Err, ReadTextFile(ConcatPaths([ReferenceFolder, Topic + '.md']), Committed, Err));
    AssertEquals('docs/reference/' + Topic + '.md is out of date: run ./build.sh then ./build-docs.sh', Expected, Committed);
  end;
end;

procedure TTestDocs.TestUnknownTopic;
var
  Markdown: string;
begin
  AssertFalse(ReferencePage('nothing', Markdown));
  AssertEquals('', Markdown);
end;

procedure TTestDocs.TestEveryFunctionListed;
var
  Markdown: string;
  Info: TFormulaFunctionInfo;
begin
  AssertTrue(ReferencePage('functions', Markdown));
  for Info in FormulaFunctions do
    AssertTrue(Info.Name, Pos('`' + Info.Name + '(', Markdown) > 0);
end;

procedure TTestDocs.TestParserHasEveryOption;
var
  Parser: TArgumentParser;
  Option: TCliOption;
begin
  Parser := BuildCliParser;
  try
    for Option in CliOptions do
      AssertNotNull(Option.Name, Parser.Options[Option.Name]);
  finally
    FreeAndNil(Parser);
  end;
end;

procedure TTestDocs.TestEveryCommandListed;
var
  Markdown: string;
  Command: TCliCommand;
begin
  AssertTrue(ReferencePage('cli', Markdown));
  for Command in CliCommands do
    AssertTrue(Command.Name, Pos('### ' + Command.Name + #10, Markdown) > 0);
end;

initialization
  RegisterTest(TTestDocs);
end.
