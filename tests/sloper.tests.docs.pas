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
    procedure TestExamplePatternsHaveNoProblems;
    procedure TestTutorialImagesDrawWhatExists;
  end;

implementation

uses
  SysUtils, Classes, ConsoleTools, Sloper.Core.JSON, Sloper.Core.Formula, Sloper.Core.Measurements, Sloper.Core.Pattern,
  Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.CLI.Arguments, Sloper.Docs.Reference;

function DocsFolder: string;
begin
  Result := ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs']);
end;

function ReferenceFolder: string;
begin
  Result := ConcatPaths([DocsFolder, 'reference']);
end;

// Loads an example pattern with the measurement file it names, if any, and evaluates it
procedure LoadExample(const FileName: string; Pattern: TPattern; Measurements: TMeasurementSet);
var
  Err: string;
begin
  if not LoadPatternFromFile(Pattern, FileName, Err) then
    raise EAssertionFailedError.Create(FileName + ': ' + Err);
  if Pattern.MeasurementFile <> '' then
  begin
    if not Measurements.LoadFromFile(MeasurementFilePath(Pattern, FileName), Err) then
      raise EAssertionFailedError.Create(FileName + ': ' + Err);
    Pattern.Measurements := Measurements;
  end;
  Pattern.Evaluate;
end;

// Run ./build-docs.sh after ./build.sh to write them again
procedure TTestDocs.TestCommittedPagesAreCurrent;
var
  Topic, Expected, Committed, Err: string;
begin
  for Topic in DocTopics do
  begin
    AssertTrue(Topic, ReferencePage(Topic, Expected));
    AssertTrue(Err, ReadTextFile(ConcatPaths([ReferenceFolder, StringReplace(DocTopicPath(Topic), '/', PathDelim, [rfReplaceAll])]),
      Committed, Err));
    AssertEquals('docs/reference/' + DocTopicPath(Topic) + ' is out of date: run ./build.sh then ./build-docs.sh', Expected,
      Committed);
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

// Every file under Folder, in its subfolders too, with this extension
procedure FindFiles(const Folder, Extension: string; Found: TStrings);
var
  Search: TSearchRec;
begin
  if FindFirst(ConcatPaths([Folder, AllFilesMask]), faAnyFile, Search) = 0 then
  try
    repeat
      if (Search.Name = '.') or (Search.Name = '..') then
        Continue;
      if (Search.Attr and faDirectory) <> 0 then
        FindFiles(ConcatPaths([Folder, Search.Name]), Extension, Found)
      else if SameText(ExtractFileExt(Search.Name), Extension) then
        Found.Add(ConcatPaths([Folder, Search.Name]));
    until FindNext(Search) <> 0;
  finally
    FindClose(Search);
  end;
end;

// Every tutorial and example pattern in docs/examples opens with its measurements, if it has any, and
// works out cleanly
procedure TTestDocs.TestExamplePatternsHaveNoProblems;
var
  Files: TStringList;
  FileName, Problem: string;
  Pattern: TPattern;
  Measurements: TMeasurementSet;
  Blocked: integer;
begin
  Files := TStringList.Create;
  try
    FindFiles(ConcatPaths([DocsFolder, 'examples']), '.sloper', Files);
    AssertTrue('there are examples', Files.Count > 0);
    for FileName in Files do
    begin
      Measurements := TMeasurementSet.Create;
      Pattern := TPattern.Create;
      try
        LoadExample(FileName, Pattern, Measurements);
        for Problem in PatternProblems(Pattern, Blocked) do
          Fail(ExtractFileName(FileName) + ': ' + Problem);
      finally
        FreeAndNil(Pattern);
        FreeAndNil(Measurements);
      end;
    end;
  finally
    FreeAndNil(Files);
  end;
end;

// docs/tutorials/images.list names objects to draw up to; each must still exist
procedure TTestDocs.TestTutorialImagesDrawWhatExists;
var
  Lines: TStringList;
  Line, Err, Text: string;
  Parts: TStringArray;
  Pattern: TPattern;
  Measurements: TMeasurementSet;
begin
  AssertTrue(Err, ReadTextFile(ConcatPaths([DocsFolder, 'tutorials', 'images.list']), Text, Err));
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for Line in Lines do
    begin
      if (Trim(Line) = '') or Line.StartsWith('#') then
        Continue;
      Parts := Line.Split([' '], TStringSplitOptions.ExcludeEmpty);
      AssertEquals(Line, 3, Length(Parts));
      AssertTrue(Parts[0] + ' is drawn', FileExists(ConcatPaths([DocsFolder, 'tutorials', 'images', Parts[0]])));
      if Parts[2] = '-' then
        Continue;
      Measurements := TMeasurementSet.Create;
      Pattern := TPattern.Create;
      try
        LoadExample(ConcatPaths([DocsFolder, Parts[1]]), Pattern, Measurements);
        AssertNotNull(Parts[0] + ': ' + Parts[2] + ' is not in ' + Parts[1], Pattern.FindObject(Parts[2]));
      finally
        FreeAndNil(Pattern);
        FreeAndNil(Measurements);
      end;
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

initialization
  RegisterTest(TTestDocs);
end.
