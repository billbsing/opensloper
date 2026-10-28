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

// opensloper-cli: export and check patterns from the command line.
program opensloper_cli;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, ConsoleTools, osVersion;

resourcestring
  rsDescription = 'Export and check OpenSloper patterns.';
  rsOptHelp = 'Show this help';
  rsOptVersion = 'Show the version';
  rsArgCommand = 'Command to run';
  rsArgPattern = 'Pattern file (.sloper)';
  rsCmdCheck = 'Evaluate a pattern and report problems';
  rsCmdExport = 'Export a pattern for one or more measurement files';
  rsNotImplemented = 'The %s command is not implemented yet.';

var
  Parser: TArgumentParser;
  Command: TArgument;
begin
  Parser := TArgumentParser.Create;
  try
    Parser.Title := 'opensloper-cli';
    Parser.Description := rsDescription;
    Parser.AddOption('help', '-h', '--help', rsOptHelp, '', avSwitch);
    Parser.AddOption('version', '-V', '--version', rsOptVersion, '', avSwitch);
    Command := Parser.AddArgument('command', rsArgCommand, 'command', asRequired, avChoice);
    Command.AddChoice('check', rsCmdCheck);
    Command.AddChoice('export', rsCmdExport);
    Parser.AddArgument('pattern', rsArgPattern, 'pattern', asOptional);

    try
      Parser.Parse;
      if Parser.IsOption('help') then
      begin
        Parser.ShowHelp;
        Exit;
      end;
      if Parser.IsOption('version') then
      begin
        WriteLn(AppName, ' ', AppVersion);
        Exit;
      end;
      Parser.Validate;
    except
      on E: EArgumentParserException do
      begin
        WriteLn(StdErr, E.Message);
        ExitCode := 1;
        Exit;
      end;
    end;

    WriteLn(StdErr, Format(rsNotImplemented, [Parser.GetArgumentValueAsString('command')]));
    ExitCode := 2;
  finally
    Parser.Free;
  end;
end.
