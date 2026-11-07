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

// Reference pages of the user documentation, written as Markdown from the
// tables the code itself uses, so they cannot drift from it: the formula
// functions and units, and the command line. opensloper-cli doc TOPIC writes
// one; build-docs.sh writes them all into docs/reference/. No LCL dependency.
unit Sloper.Docs.Reference;

{$mode ObjFPC}{$H+}

interface

const
  // Each is written to docs/reference/TOPIC.md
  DocTopics: array[0..1] of string = ('functions', 'cli');

// The page for Topic; False when there is no such topic
function ReferencePage(const Topic: string; out Markdown: string): boolean;

resourcestring
  rsDocGenerated = 'This page is generated from the program by `opensloper-cli doc %s`; do not edit it by hand.';
  rsDocFunctionsTitle = 'Formula functions and units';
  rsDocFunctionsIntro = 'Formulas can use these functions. Angles are in degrees, 0° pointing right and 90° up. ' +
    'Function names are written in lower case and are the same in every language.';
  rsDocFunction = 'Function';
  rsDocArguments = 'Values';
  rsDocWhatItGives = 'What it gives';
  rsDocOrMore = '%d or more';
  rsDocOperatorsTitle = 'Operators';
  rsDocOperatorsIntro = 'In order of precedence, highest first. `^` groups from the right and binds tighter than a leading ' +
    'minus, so `-2^2` is -4.';
  rsDocOperator = 'Operator';
  rsDocMeaning = 'Meaning';
  rsDocOpGroup = 'Grouping';
  rsDocOpPower = 'Power';
  rsDocOpNegate = 'Minus a value';
  rsDocOpMultiply = 'Multiply and divide';
  rsDocOpAdd = 'Add and subtract';
  rsDocUnitsTitle = 'Units';
  rsDocUnitsIntro = 'A plain number is in the pattern''s unit. A number may carry a unit written straight after it, in any ' +
    'case, and is then converted to the pattern''s unit: `400mm`, `1.5cm`, `2in`. A number written with a unit keeps ' +
    'its meaning in every pattern, and Convert Pattern Units leaves it alone.';
  rsDocUnit = 'Unit';
  rsDocMillimetres = 'In millimetres';
  rsDocCliTitle = 'Command line';
  rsDocCliIntro = '`opensloper-cli` exports and checks patterns without a window, for scripts and builds.';
  rsDocCommands = 'Commands';
  rsDocOptions = 'Options';
  rsDocOption = 'Option';
  rsDocValue = 'Value';
  rsDocDescription = 'Description';
  rsDocArgumentsTitle = 'Arguments';
  rsDocArgumentsIntro = 'After the command, in this order; each command takes the ones it needs.';
  rsDocArgument = 'Argument';
  rsDocExitCodes = 'Exit codes';
  rsDocCode = 'Code';

implementation

uses
  SysUtils, Sloper.Core.Formula, Sloper.Core.FormulaLexer, Sloper.Core.Units, Sloper.CLI.Arguments;

// Characters that would end a table cell or start markup
function Cell(const Text: string): string;
begin
  Result := StringReplace(Text, '|', '\|', [rfReplaceAll]);
  Result := StringReplace(Result, LineEnding, '<br>', [rfReplaceAll]);
end;

function Row(const Cells: array of string): string;
var
  Index: integer;
begin
  Result := '|';
  for Index := 0 to High(Cells) do
    Result := Result + ' ' + Cells[Index] + ' |';
  Result := Result + LineEnding;
end;

function HeaderRow(const Cells: array of string): string;
var
  Index: integer;
begin
  Result := Row(Cells) + '|';
  for Index := 0 to High(Cells) do
    Result := Result + ' --- |';
  Result := Result + LineEnding;
end;

function Heading(Level: integer; const Text: string): string;
begin
  Result := StringOfChar('#', Level) + ' ' + Text + LineEnding + LineEnding;
end;

function Paragraph(const Text: string): string;
begin
  Result := Text + LineEnding + LineEnding;
end;

function Code(const Text: string): string;
begin
  Result := '`' + Text + '`';
end;

function Generated(const Topic: string): string;
begin
  Result := Paragraph('!!! note' + LineEnding + LineEnding + '    ' + Format(rsDocGenerated, [Topic]));
end;

function FunctionsPage: string;
var
  Info: TFormulaFunctionInfo;
  Values: string;
  Suffix: TNumberSuffix;
begin
  Result := Heading(1, rsDocFunctionsTitle) + Generated('functions') + Paragraph(rsDocFunctionsIntro);
  Result := Result + HeaderRow([rsDocFunction, rsDocArguments, rsDocWhatItGives]);
  for Info in FormulaFunctions do
  begin
    if Info.MaxArgs < 0 then
      Values := Format(rsDocOrMore, [Info.MinArgs])
    else
      Values := IntToStr(Info.MinArgs);
    Result := Result + Row([Code(Info.Name + '(' + Info.Arguments + ')'), Values, Cell(Info.Description)]);
  end;
  Result := Result + LineEnding + Heading(2, rsDocOperatorsTitle) + Paragraph(rsDocOperatorsIntro);
  Result := Result + HeaderRow([rsDocOperator, rsDocMeaning]);
  Result := Result + Row([Code('( )'), rsDocOpGroup]) + Row([Code('^'), rsDocOpPower]) + Row([Code('-'), rsDocOpNegate]) +
    Row([Code('*') + ' ' + Code('/'), rsDocOpMultiply]) + Row([Code('+') + ' ' + Code('-'), rsDocOpAdd]);
  Result := Result + LineEnding + Heading(2, rsDocUnitsTitle) + Paragraph(rsDocUnitsIntro);
  Result := Result + HeaderRow([rsDocUnit, rsDocMillimetres]);
  for Suffix := Succ(nsNone) to High(TNumberSuffix) do
    Result := Result + Row([Code(NumberSuffixNames[Suffix]), FormatFloat('0.##', NumberSuffixMillimetres[Suffix])]);
end;

function CliPage: string;
var
  Command: TCliCommand;
  Option: TCliOption;
  Argument: TCliArgument;
  Names: string;
  Status: integer;
begin
  Result := Heading(1, rsDocCliTitle) + Generated('cli') + Paragraph(rsDocCliIntro);
  Result := Result + Paragraph('```' + LineEnding + CliTitle + ' [options] <command> [arguments]' + LineEnding + '```');
  Result := Result + Heading(2, rsDocCommands);
  for Command in CliCommands do
  begin
    Result := Result + Heading(3, Command.Name) + Paragraph(Command.Description);
    // Each way of calling it on a line of its own
    Result := Result + Paragraph('```' + LineEnding + CliTitle + ' ' + StringReplace(Command.Usage, LineEnding,
      LineEnding + CliTitle + ' ', [rfReplaceAll]) + LineEnding + '```');
  end;
  Result := Result + Heading(2, rsDocOptions) + HeaderRow([rsDocOption, rsDocValue, rsDocDescription]);
  for Option in CliOptions do
  begin
    Names := Code(Option.Long);
    if Option.Short <> '' then
      Names := Code(Option.Short) + ', ' + Names;
    Result := Result + Row([Names, Option.Parameter, Cell(Option.Description)]);
  end;
  Result := Result + LineEnding + Heading(2, rsDocArgumentsTitle) + Paragraph(rsDocArgumentsIntro) +
    HeaderRow([rsDocArgument, rsDocDescription]);
  for Argument in CliArguments do
    Result := Result + Row([Code(Argument.Name), Cell(Argument.Description)]);
  Result := Result + LineEnding + Heading(2, rsDocExitCodes) + HeaderRow([rsDocCode, rsDocMeaning]);
  for Status := Low(CliExitCodes) to High(CliExitCodes) do
    Result := Result + Row([IntToStr(Status), CliExitCodes[Status]]);
end;

function ReferencePage(const Topic: string; out Markdown: string): boolean;
begin
  Result := True;
  if Topic = 'functions' then
    Markdown := FunctionsPage
  else if Topic = 'cli' then
    Markdown := CliPage
  else
  begin
    Markdown := '';
    Result := False;
  end;
  // Pages are written with LF line ends on every system
  Markdown := StringReplace(Markdown, LineEnding, #10, [rfReplaceAll]);
end;

end.
