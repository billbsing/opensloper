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

// A small PDF writer: stroked lines and Helvetica text on pages sized in
// millimetres, nothing compressed. Written here rather than through fcl-pdf
// so that scale is exact and the same layout always gives the same bytes.
// Coordinates are millimetres from the page's top left, y down.
unit Sloper.Output.PDFWriter;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry;

type
  TPDFWriter = class
  private
    FPageWidths, FPageHeights: array of double;
    FContents: array of rawbytestring;
    function GetPageCount: integer;
    procedure Add(const Text: rawbytestring);
    function PageX(Value: double): string;
    function PageY(Value: double): string;
  public
    procedure BeginPage(AWidth, AHeight: double);
    procedure SetLineWidth(Millimetres: double);
    // Dashes and gaps this long; 0 for a solid line
    procedure SetDash(Millimetres: double);
    // Lines and text from here on, from 0 for black to 1 for white
    procedure SetGray(Level: double);
    procedure FillRectangle(const Area: TRect2);
    procedure FillPolygon(const Points: TVec2Array);
    procedure Polyline(const Points: TVec2Array; Closed: boolean);
    procedure Line(const From, Target: TVec2);
    procedure Rectangle(const Area: TRect2);
    // Baseline at (AX, AY); Size in points. Characters outside Latin-1 print as "?".
    procedure Text(AX, AY, Size: double; const AText: string);
    // Everything until PopClip is cut off at Area
    procedure PushClip(const Area: TRect2);
    procedure PopClip;
    // The finished file, as bytes
    function Finish: rawbytestring;
    property PageCount: integer read GetPageCount;
  end;

implementation

const
  PointsPerMM = 72 / 25.4;
  ValueDecimals = '0.###';

function PointsText(Value: double): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FormatFloat(ValueDecimals, Value, Settings);
  if Result = '-0' then
    Result := '0';
end;

function TPDFWriter.GetPageCount: integer;
begin
  Result := Length(FContents);
end;

procedure TPDFWriter.Add(const Text: rawbytestring);
begin
  FContents[High(FContents)] := FContents[High(FContents)] + Text + #10;
end;

function TPDFWriter.PageX(Value: double): string;
begin
  Result := PointsText(Value * PointsPerMM);
end;

// PDF's y points up, from the bottom of the page
function TPDFWriter.PageY(Value: double): string;
begin
  Result := PointsText((FPageHeights[High(FPageHeights)] - Value) * PointsPerMM);
end;

procedure TPDFWriter.BeginPage(AWidth, AHeight: double);
begin
  SetLength(FPageWidths, Length(FPageWidths) + 1);
  FPageWidths[High(FPageWidths)] := AWidth;
  SetLength(FPageHeights, Length(FPageHeights) + 1);
  FPageHeights[High(FPageHeights)] := AHeight;
  SetLength(FContents, Length(FContents) + 1);
end;

procedure TPDFWriter.SetLineWidth(Millimetres: double);
begin
  Add(PointsText(Millimetres * PointsPerMM) + ' w');
end;

procedure TPDFWriter.SetDash(Millimetres: double);
begin
  if Millimetres <= 0 then
    Add('[] 0 d')
  else
    Add('[' + PointsText(Millimetres * PointsPerMM) + '] 0 d');
end;

procedure TPDFWriter.SetGray(Level: double);
begin
  Add(PointsText(Level) + ' G ' + PointsText(Level) + ' g');
end;

procedure TPDFWriter.FillRectangle(const Area: TRect2);
begin
  Add(PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * PointsPerMM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * PointsPerMM) + ' re f');
end;

procedure TPDFWriter.FillPolygon(const Points: TVec2Array);
var
  Index: integer;
begin
  for Index := 0 to High(Points) do
    if Index = 0 then
      Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' m')
    else
      Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' l');
  Add('h f');
end;

procedure TPDFWriter.Polyline(const Points: TVec2Array; Closed: boolean);
var
  Index: integer;
begin
  if Length(Points) < 2 then
    Exit;
  Add(PageX(Points[0].X) + ' ' + PageY(Points[0].Y) + ' m');
  for Index := 1 to High(Points) do
    Add(PageX(Points[Index].X) + ' ' + PageY(Points[Index].Y) + ' l');
  if Closed then
    Add('s')
  else
    Add('S');
end;

procedure TPDFWriter.Line(const From, Target: TVec2);
begin
  Add(PageX(From.X) + ' ' + PageY(From.Y) + ' m ' + PageX(Target.X) + ' ' + PageY(Target.Y) + ' l S');
end;

procedure TPDFWriter.Rectangle(const Area: TRect2);
begin
  Add(PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * PointsPerMM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * PointsPerMM) + ' re S');
end;

// WinAnsi matches Latin-1 for what is kept here
function EscapedText(const AText: string): rawbytestring;
var
  Wide: unicodestring;
  Code: word;
  Index: integer;
begin
  Wide := UTF8Decode(AText);
  Result := '';
  for Index := 1 to Length(Wide) do
  begin
    Code := Ord(Wide[Index]);
    if Code in [Ord('('), Ord(')'), Ord('\')] then
      Result := Result + '\' + chr(Code)
    else if (Code >= 32) and (Code < 127) or (Code >= 160) and (Code <= 255) then
      Result := Result + chr(Code)
    else
      Result := Result + '?';
  end;
end;

procedure TPDFWriter.Text(AX, AY, Size: double; const AText: string);
begin
  Add('BT /F1 ' + PointsText(Size) + ' Tf ' + PageX(AX) + ' ' + PageY(AY) + ' Td (' + EscapedText(AText) + ') Tj ET');
end;

procedure TPDFWriter.PushClip(const Area: TRect2);
begin
  Add('q ' + PageX(Area.MinX) + ' ' + PageY(Area.MaxY) + ' ' + PointsText((Area.MaxX - Area.MinX) * PointsPerMM) + ' ' +
    PointsText((Area.MaxY - Area.MinY) * PointsPerMM) + ' re W n');
end;

procedure TPDFWriter.PopClip;
begin
  Add('Q');
end;

function TPDFWriter.Finish: rawbytestring;
const
  FontId = 3;
  FirstPageId = 4;
var
  Offsets: array of integer;
  Index, ObjectCount: integer;
  Kids: string;

  procedure AddObject(Id: integer; const Body: rawbytestring);
  begin
    Offsets[Id] := Length(Result);
    Result := Result + IntToStr(Id) + ' 0 obj' + #10 + Body + #10 + 'endobj' + #10;
  end;

begin
  ObjectCount := FirstPageId + 2 * Length(FContents);
  Offsets := nil;
  SetLength(Offsets, ObjectCount);
  Result := '%PDF-1.4' + #10;
  Kids := '';
  for Index := 0 to High(FContents) do
    Kids := Kids + IntToStr(FirstPageId + 2 * Index) + ' 0 R ';
  AddObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  AddObject(2, '<< /Type /Pages /Count ' + IntToStr(Length(FContents)) + ' /Kids [' + Trim(Kids) + '] >>');
  AddObject(FontId, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  for Index := 0 to High(FContents) do
  begin
    AddObject(FirstPageId + 2 * Index, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + PointsText(FPageWidths[Index] * PointsPerMM) +
      ' ' + PointsText(FPageHeights[Index] * PointsPerMM) + '] /Resources << /Font << /F1 ' + IntToStr(FontId) +
      ' 0 R >> >> /Contents ' + IntToStr(FirstPageId + 2 * Index + 1) + ' 0 R >>');
    AddObject(FirstPageId + 2 * Index + 1, '<< /Length ' + IntToStr(Length(FContents[Index])) + ' >>' + #10 + 'stream' + #10 +
      FContents[Index] + 'endstream');
  end;
  Index := Length(Result);
  Result := Result + 'xref' + #10 + '0 ' + IntToStr(ObjectCount) + #10 + '0000000000 65535 f ' + #10;
  Kids := '';
  for ObjectCount := 1 to High(Offsets) do
    Result := Result + Format('%.10d 00000 n ', [Offsets[ObjectCount]]) + #10;
  Result := Result + 'trailer' + #10 + '<< /Size ' + IntToStr(Length(Offsets)) + ' /Root 1 0 R >>' + #10 + 'startxref' + #10 +
    IntToStr(Index) + #10 + '%%EOF' + #10;
end;

end.
