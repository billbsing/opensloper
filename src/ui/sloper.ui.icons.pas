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

// The command icons drawn from their SVGs at the size the screen needs, so
// they stay sharp at any scale.
unit Sloper.UI.Icons;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Controls, Graphics;

// One image per TAppIcon, in its order, Size pixels square and drawn in
// Color. An icon that cannot be read stays blank, so the indices still line
// up; IconsFound says whether the folder was there at all.
function CreateIconList(AOwner: TComponent; Size: integer; Color: TColor): TImageList;
function IconsFound: boolean;

implementation

uses
  SysUtils, BGRABitmap, BGRABitmapTypes, BGRASVG, Sloper.Core.AppPaths, Sloper.Core.JSON, Sloper.UI.IconSet;

function IconsFound: boolean;
begin
  Result := TAppPaths.IconDir <> '';
end;

function ColorText(Color: TColor): string;
var
  RGB: TColor;
begin
  RGB := ColorToRGB(Color);
  Result := Format('#%.2x%.2x%.2x', [Red(RGB), Green(RGB), Blue(RGB)]);
end;

procedure DrawIcon(Image: TBGRABitmap; const FileName, Color: string);
var
  Text, Err: string;
  Svg: TBGRASVG;
begin
  if not ReadTextFile(FileName, Text, Err) then
    Exit;
  try
    Svg := TBGRASVG.CreateFromString(TintedSVG(Text, Color));
    try
      Svg.StretchDraw(Image.Canvas2D, 0, 0, Image.Width, Image.Height);
    finally
      FreeAndNil(Svg);
    end;
  except
    // A file that is not a usable SVG leaves the icon blank
    on Exception do
      Image.FillTransparent;
  end;
end;

function CreateIconList(AOwner: TComponent; Size: integer; Color: TColor): TImageList;
var
  Dir, Hex: string;
  Icon: TAppIcon;
  Image: TBGRABitmap;
begin
  Result := TImageList.Create(AOwner);
  Result.Width := Size;
  Result.Height := Size;
  Dir := TAppPaths.IconDir;
  Hex := ColorText(Color);
  for Icon := Low(TAppIcon) to High(TAppIcon) do
  begin
    Image := TBGRABitmap.Create(Size, Size, BGRAPixelTransparent);
    try
      if Dir <> '' then
        DrawIcon(Image, IconFileName(Dir, Icon), Hex);
      Result.Add(Image.Bitmap, nil);
    finally
      FreeAndNil(Image);
    end;
  end;
end;

end.
