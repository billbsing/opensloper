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

// opensloper-cli's commands, options and arguments, as tables. The parser is
// built from them, and so is the command-line reference page, so the two
// cannot drift apart. ConsoleTools cannot list what it was given, hence the
// tables. No LCL dependency.
unit Sloper.CLI.Arguments;

{$mode ObjFPC}{$H+}

interface

uses
  ConsoleTools;

const
  EXIT_SUCCESS = 0;
  EXIT_PROBLEMS = 1;
  EXIT_FAILURE = 2;

type
  TCliCommand = record
    Name: string;
    // How it is called, as typed: words in capitals are filled in
    Usage: string;
    Description: string;
  end;

  TCliOption = record
    Name, Short, Long: string;
    // The value it takes, as shown in help; '' for a switch
    Parameter: string;
    Description: string;
  end;

  TCliArgument = record
    Name, Description: string;
  end;

resourcestring
  rsCliDescription = 'Export and check OpenSloper patterns.';
  rsOptHelp = 'Show this help';
  rsOptVersion = 'Show the version';
  rsOptMeasurements = 'Measurement file (.slm); default: the one the pattern names';
  rsOptSize = 'check, layout: the size to use from a size table, default the first; measurements: the size to list or set';
  rsOptDescription = 'measurements set: the description; default: keep the one it has';
  rsOptJSON = 'check: print every computed value as JSON; measurements list: print the file';
  rsOptOutput = 'layout, export, export-draft, doc: the file to write';
  rsOptLabels = 'export-draft: name the points and pieces';
  rsOptUpTo = 'export-draft: draw only this object and those before it, as the pattern was when it was added';
  rsOptFormat = 'export: pdf, svg, dxf or machine-dxf; default: the extension of --output, or pdf';
  rsOptProfile = 'export: a machine profile from the settings, in place of the layout''s';
  rsArgCommand = 'Command to run';
  rsArgPattern = 'Pattern file (.sloper), layout file (.slayout) to export, for measurements: list, set or missing, ' +
    'or for doc: the topic';
  rsArgFile = 'measurements: the measurement file (.slm)';
  rsArgKey = 'measurements set: the key; measurements missing: the pattern file';
  rsArgValue = 'measurements set: the value in mm';
  rsCmdCheck = 'Evaluate a pattern and report problems';
  rsCmdExport = 'Export a layout file as PDF, SVG or DXF';
  rsCmdExportDraft = 'Export a pattern''s draft as SVG, as the drafting window shows it';
  rsCmdLayout = 'Start a layout file for a pattern, with every piece placed';
  rsCmdMeasurements = 'List a measurement file, set a value, or see what a pattern needs that it lacks';
  rsCmdPack = 'Pack a layout''s pieces and rewrite the layout file';
  rsCmdServe = 'Answer JSON-RPC 2.0 on stdin and stdout, one message per line, as the Automation API and as an MCP server';
  rsCmdDoc = 'Write a page of the reference documentation as Markdown, or a file format''s JSON Schema; with no ' +
    'topic, list the topics';
  rsExitSuccess = 'Success';
  rsExitProblems = 'check: the pattern has problems';
  rsExitFailure = 'A usage error, or a file that could not be read or written';

const
  CLI_TITLE = 'opensloper-cli';
  CLI_COMMANDS: array[0..7] of TCliCommand = (
    (Name: 'check'; Usage: 'check PATTERN [-m FILE] [-s SIZE] [--json]'; Description: rsCmdCheck),
    (Name: 'export'; Usage: 'export LAYOUT [-o FILE] [--format=FORMAT] [--profile=NAME]'; Description: rsCmdExport),
    (Name: 'export-draft'; Usage: 'export-draft PATTERN [-o FILE] [-m FILE] [-s SIZE] [--labels] [--upto=NAME]';
    Description: rsCmdExportDraft),
    (Name: 'layout'; Usage: 'layout PATTERN [-o FILE] [-m FILE] [-s SIZE]'; Description: rsCmdLayout),
    (Name: 'measurements'; Usage: 'measurements list FILE [-s SIZE] [--json]' + LineEnding +
    'measurements set FILE KEY VALUE [-s SIZE] [-d TEXT]' + LineEnding + 'measurements missing FILE PATTERN'; Description: rsCmdMeasurements),
    (Name: 'pack'; Usage: 'pack LAYOUT'; Description: rsCmdPack),
    (Name: 'serve'; Usage: 'serve'; Description: rsCmdServe),
    (Name: 'doc'; Usage: 'doc TOPIC [-o FILE]' + LineEnding + 'doc'; Description: rsCmdDoc));
  CLI_OPTIONS: array[0..10] of TCliOption = (
    (Name: 'help'; Short: '-h'; Long: '--help'; Parameter: ''; Description: rsOptHelp),
    (Name: 'version'; Short: '-V'; Long: '--version'; Parameter: ''; Description: rsOptVersion),
    (Name: 'measurements'; Short: '-m'; Long: '--measurements'; Parameter: 'file'; Description: rsOptMeasurements),
    (Name: 'size'; Short: '-s'; Long: '--size'; Parameter: 'size'; Description: rsOptSize),
    (Name: 'description'; Short: '-d'; Long: '--description'; Parameter: 'text'; Description: rsOptDescription),
    (Name: 'json'; Short: ''; Long: '--json'; Parameter: ''; Description: rsOptJSON),
    (Name: 'output'; Short: '-o'; Long: '--output'; Parameter: 'file'; Description: rsOptOutput),
    (Name: 'format'; Short: ''; Long: '--format'; Parameter: 'format'; Description: rsOptFormat),
    (Name: 'profile'; Short: ''; Long: '--profile'; Parameter: 'name'; Description: rsOptProfile),
    (Name: 'labels'; Short: ''; Long: '--labels'; Parameter: ''; Description: rsOptLabels),
    (Name: 'upto'; Short: ''; Long: '--upto'; Parameter: 'name'; Description: rsOptUpTo));
  // After the command, in order; all optional, as each command takes its own
  CLI_ARGUMENTS: array[0..3] of TCliArgument = (
    (Name: 'pattern'; Description: rsArgPattern),
    (Name: 'file'; Description: rsArgFile),
    (Name: 'key'; Description: rsArgKey),
    (Name: 'value'; Description: rsArgValue));
  CLI_EXIT_CODES: array[EXIT_SUCCESS..EXIT_FAILURE] of string = (rsExitSuccess, rsExitProblems, rsExitFailure);

// A parser for the tables above; the caller frees it
function BuildCliParser: TArgumentParser;

implementation

function BuildCliParser: TArgumentParser;
var
  Option: TCliOption;
  Command: TCliCommand;
  CommandArgument: TArgument;
  Argument: TCliArgument;
begin
  Result := TArgumentParser.Create;
  Result.Title := CLI_TITLE;
  Result.Description := rsCliDescription;
  for Option in CLI_OPTIONS do
    if Option.Parameter = '' then
      Result.AddOption(Option.Name, Option.Short, Option.Long, Option.Description, '', avSwitch)
    else
      Result.AddOption(Option.Name, Option.Short, Option.Long, Option.Description, Option.Parameter);
  CommandArgument := Result.AddArgument('command', rsArgCommand, 'command', asRequired, avChoice);
  for Command in CLI_COMMANDS do
    CommandArgument.AddChoice(Command.Name, Command.Description);
  for Argument in CLI_ARGUMENTS do
    Result.AddArgument(Argument.Name, Argument.Description, Argument.Name, asOptional);
end;

end.
