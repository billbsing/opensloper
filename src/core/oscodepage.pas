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

// Makes strings UTF-8 throughout the program. List this unit first in every
// program's uses clause: console programs otherwise start with no code page,
// and non-ASCII text (names, notes) is garbled when it passes through JSON
// or file names. No LCL dependency.
unit osCodePage;

{$mode ObjFPC}{$H+}

interface

implementation

uses
  {$IFDEF UNIX}
  cwstring,
  {$ENDIF}
  SysUtils;

initialization
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
end.
