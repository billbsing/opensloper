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
  TExportFormat = (efPDF, efSVG, efDXF, efMachineDXF);

const
  ExportNames: array[TExportFormat] of string = ('pdf', 'svg', 'dxf', 'machine-dxf');
  ExportExtensions: array[TExportFormat] of string = ('.pdf', '.svg', '.dxf', '.dxf');

// By FormatName (one of ExportNames) when there is one, then by FileName's
// extension, where .dxf means DXF-AAMA, and PDF when there is no file name.
// False when neither is known.
function ExportFormatFor(const FormatName, FileName: string; out AFormat: TExportFormat): boolean;
// Refuses, listing the blocking problems in ErrorMessage, or writes the file
function ExportLayout(Layout: TLayout; AFormat: TExportFormat; const FileName: string; out ErrorMessage: string): boolean;

resourcestring
  rsExportBadFormat = 'Say pdf, svg, dxf or machine-dxf, or end the file name with .pdf, .svg or .dxf';

implementation

uses
  SysUtils, Sloper.Core.MachineProfiles, Sloper.Output.LayoutPDF, Sloper.Output.LayoutSVG, Sloper.Output.LayoutDXF;

function ExportFormatFor(const FormatName, FileName: string; out AFormat: TExportFormat): boolean;
var
  Candidate: TExportFormat;
  Wanted: string;
begin
  AFormat := efPDF;
  if (FormatName = '') and (FileName = '') then
    Exit(True);
  Wanted := LowerCase(ExtractFileExt(FileName));
  for Candidate := Low(TExportFormat) to High(TExportFormat) do
    if ((FormatName <> '') and SameText(ExportNames[Candidate], FormatName)) or ((FormatName = '') and (ExportExtensions[Candidate] = Wanted)) then
    begin
      AFormat := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function ExportLayout(Layout: TLayout; AFormat: TExportFormat; const FileName: string; out ErrorMessage: string): boolean;
var
  Profile: TMachineProfile;
begin
  ErrorMessage := Layout.Refusal;
  if ErrorMessage <> '' then
    Exit(False);
  // The wrong colours would cut the wrong lines, so this never falls back
  if ((AFormat = efMachineDXF) or ((AFormat = efSVG) and (Layout.Output.Profile <> ''))) and not Layout.ChosenProfile(Profile) then
  begin
    ErrorMessage := Format(rsLayoutUnknownProfile, [Layout.Output.Profile]);
    Exit(False);
  end;
  case AFormat of
    efPDF: Result := WriteBytesToFile(FileName, LayoutToPDF(Layout), ErrorMessage);
    efSVG: Result := WriteBytesToFile(FileName, LayoutToSVG(Layout), ErrorMessage);
    efDXF: Result := WriteBytesToFile(FileName, LayoutToDXF(Layout), ErrorMessage);
    efMachineDXF: Result := WriteBytesToFile(FileName, LayoutToMachineDXF(Layout, Profile), ErrorMessage);
    else
      Result := False;
  end;
end;

end.
