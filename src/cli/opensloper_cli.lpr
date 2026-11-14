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

// opensloper-cli: export and check patterns from the command line. The
// commands are in Sloper.CLI.Commands.
// Exit codes: 0 success, 1 the pattern has problems, 2 a usage or file error.
program opensloper_cli;

{$mode ObjFPC}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Sloper.Core.CodePage,
  Sloper.CLI.Commands;

var
  Args: array of string;
  Index: integer;
begin
  Args := nil;
  SetLength(Args, ParamCount);
  for Index := 1 to ParamCount do
    Args[Index - 1] := ParamStr(Index);
  ExitCode := RunCli(Args, Output, StdErr);
end.
