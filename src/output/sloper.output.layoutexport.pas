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

// Writing a layout out in whichever format was asked for. Whatever the format,
// the problems that block a PDF block it too.
unit Sloper.Output.LayoutExport;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Output.Layout;

type
  TExportFormat = (efPDF, efSVG, efDXF);

const
  ExportExtensions: array[TExportFormat] of string = ('.pdf', '.svg', '.dxf');

// By FormatName (pdf, svg or dxf) when there is one, then by FileName's
// extension, and PDF when there is no file name. False when neither is known.
function ExportFormatFor(const FormatName, FileName: string; out AFormat: TExportFormat): boolean;
// Refuses, listing the blocking problems in ErrorMessage, or writes the file
function ExportLayout(Layout: TLayout; AFormat: TExportFormat; const FileName: string; out ErrorMessage: string): boolean;

resourcestring
  rsExportBadFormat = 'Say pdf, svg or dxf, or end the file name with .pdf, .svg or .dxf';

implementation

uses
  SysUtils, Sloper.Output.LayoutPDF, Sloper.Output.LayoutSVG, Sloper.Output.LayoutDXF;

function ExportFormatFor(const FormatName, FileName: string; out AFormat: TExportFormat): boolean;
var
  Candidate: TExportFormat;
  Wanted: string;
begin
  AFormat := efPDF;
  if FormatName <> '' then
    Wanted := '.' + LowerCase(FormatName)
  else if FileName <> '' then
    Wanted := LowerCase(ExtractFileExt(FileName))
  else
    Exit(True);
  for Candidate := Low(TExportFormat) to High(TExportFormat) do
    if ExportExtensions[Candidate] = Wanted then
    begin
      AFormat := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function ExportLayout(Layout: TLayout; AFormat: TExportFormat; const FileName: string; out ErrorMessage: string): boolean;
begin
  ErrorMessage := Layout.Refusal;
  if ErrorMessage <> '' then
    Exit(False);
  case AFormat of
    efPDF: Result := WriteBytesToFile(FileName, LayoutToPDF(Layout), ErrorMessage);
    efSVG: Result := WriteBytesToFile(FileName, LayoutToSVG(Layout), ErrorMessage);
    efDXF: Result := WriteBytesToFile(FileName, LayoutToDXF(Layout), ErrorMessage);
    else
      Result := False;
  end;
end;

end.
