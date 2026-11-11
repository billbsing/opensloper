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

// The draft as a PNG image: the draft's SVG drawn by BGRABitmap, so the image
// always matches the SVG. Text is drawn with the fonts bundled in data/fonts
// through Lazarus's own FreeType, which needs no system library and gives the
// same image on every platform. Uses BGRABitmap built without the LCL, so the
// CLI can draw images; it lives in thirdparty for that reason only.
unit Sloper.Output.DraftPNG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern, Sloper.Output.DraftSVG;

const
  // In pixels
  PNG_MIN_WIDTH = 16;
  PNG_MAX_WIDTH = 4096;
  PNG_DEFAULT_WIDTH = 1600;

// The draft as PNG file bytes, Width pixels across and as high as the drawing
// needs; False with a message when it cannot be drawn
function DraftToPNG(Pattern: TPattern; const Options: TDraftSVGOptions; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
// The font families text is drawn with, best first; empty when no font loads
function DrawingFontFamilies: string;

resourcestring
  rsPngWidth = 'The width must be from %d to %d pixels';
  rsPngNoFonts = 'No fonts to draw text with were found in data/fonts';

implementation

uses
  SysUtils, Classes, Math, BGRABitmap, BGRABitmapTypes, BGRASVG, BGRAFreeType, EasyLazFreeType,
  // Makes FreeType's default font collection, which the LCL build of BGRABitmap leaves out
  LazFreeTypeFontCollection, Sloper.Core.AppPaths;

const
  // The bundled fonts, tried in this order; a missing one is skipped
  FONT_FILES: array[0..1] of string = ('NotoSans-Regular.ttf', 'DejaVuSans.ttf');
  SVG_FONT_ATTRIBUTE = 'font-family="';

var
  FontsLoaded: boolean;
  Families: string;

// Adds the bundled fonts to FreeType's font collection, once
procedure LoadFonts;
var
  Folder, FileName: string;
  Item: TCustomFontCollectionItem;
begin
  if FontsLoaded then
    Exit;
  FontsLoaded := True;
  Families := '';
  Folder := TAppPaths.FontDir;
  if Folder = '' then
    Exit;
  for FileName in FONT_FILES do
  try
    if not FileExists(ConcatPaths([Folder, FileName])) then
      Continue;
    Item := FontCollection.AddFile(ConcatPaths([Folder, FileName]));
    if Assigned(Item) and Assigned(Item.Family) then
      Families := Families + Item.Family.FamilyName + ', ';
  except
    // A font FreeType cannot read is left out; the next may do
    on Exception do ;
  end;
end;

function DrawingFontFamilies: string;
begin
  LoadFonts;
  Result := Families;
  if Result.EndsWith(', ') then
    SetLength(Result, Length(Result) - 2);
end;

// The draft's SVG, naming the bundled fonts first: BGRABitmap draws with the
// first family it has, and cannot draw the generic sans-serif without one
function DrawingSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
begin
  LoadFonts;
  Result := StringReplace(DraftToSVG(Pattern, Options), SVG_FONT_ATTRIBUTE, SVG_FONT_ATTRIBUTE + Families, [rfReplaceAll]);
end;

function DraftToPNG(Pattern: TPattern; const Options: TDraftSVGOptions; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
var
  Svg: TBGRASVG;
  Image: TBGRABitmap;
  Source: TStringStream;
  Output: TMemoryStream;
  Height: integer;
begin
  Png := '';
  ErrorMessage := '';
  if (Width < PNG_MIN_WIDTH) or (Width > PNG_MAX_WIDTH) then
  begin
    ErrorMessage := Format(rsPngWidth, [PNG_MIN_WIDTH, PNG_MAX_WIDTH]);
    Exit(False);
  end;
  if DrawingFontFamilies = '' then
  begin
    ErrorMessage := rsPngNoFonts;
    Exit(False);
  end;
  Svg := nil;
  Image := nil;
  Source := nil;
  Output := nil;
  try
    try
      Source := TStringStream.Create(DrawingSVG(Pattern, Options));
      Svg := TBGRASVG.Create(Source);
      Height := Max(1, Round(Width * Svg.ViewBox.size.y / Svg.ViewBox.size.x));
      Image := TBGRABitmap.Create(Width, Height, BGRAWhite);
      // The bundled fonts in the design window too, where the LCL would draw
      // with the system's
      Image.FontRenderer := TBGRAFreeTypeFontRenderer.Create;
      Svg.StretchDraw(Image.Canvas2D, 0, 0, Width, Height);
      Output := TMemoryStream.Create;
      Image.SaveToStreamAsPng(Output);
      SetLength(Png, Output.Size);
      if Output.Size > 0 then
        Move(Output.Memory^, Png[1], Output.Size);
      Result := True;
    except
      on Failure: Exception do
      begin
        ErrorMessage := Failure.Message;
        Result := False;
      end;
    end;
  finally
    FreeAndNil(Output);
    FreeAndNil(Source);
    FreeAndNil(Image);
    FreeAndNil(Svg);
  end;
end;

end.
