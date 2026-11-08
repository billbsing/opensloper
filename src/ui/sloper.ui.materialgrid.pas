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

// The read-only list of a pattern's materials that the Materials tab and the
// Materials dialog share: a swatch drawn in the material's colour and fill,
// then name, fill and allowance. Rows are the pattern's materials in order,
// so a row is found again by its index after undo replaces them.
unit Sloper.UI.MaterialGrid;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Grids, Graphics, Dialogs, Types, Sloper.Core.Pattern, Sloper.Core.Materials;

type
  TMaterialGrid = class(TStringGrid)
  private
    FPattern: TPattern;
    // While the rows are filled, so moving the current row reads as no choice
    FFilling: boolean;
    function GetMaterialIndex: integer;
    procedure SetMaterialIndex(Index: integer);
  protected
    procedure PrepareCanvas(ACol, ARow: integer; AState: TGridDrawState); override;
    procedure DrawCell(ACol, ARow: integer; ARect: TRect; AState: TGridDrawState); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Fills the rows from the pattern, keeping the current row where it can
    procedure ShowMaterials(APattern: TPattern);
    // The current row's material, or -1
    property MaterialIndex: integer read GetMaterialIndex write SetMaterialIndex;
    property Filling: boolean read FFilling;
  end;

// Asks for a colour, starting from Text; True when one was chosen
function ChooseMaterialColor(Owner: TComponent; var Text: string): boolean;
function MaterialFillCaption(Fill: TMaterialFill): string;
// Hatching over Rect at the material's angle, in Ink
procedure DrawSwatchHatching(Canvas: TCanvas; const Rect: TRect; Angle: double; Ink: TColor);
function SwatchColor(const ColorText: string): TColor;

resourcestring
  rsMaterialColour = 'Colour';
  rsMaterialName = 'Material';
  rsMaterialFill = 'Fill';
  rsMaterialFillTint = 'Tint';
  rsMaterialFillHatch = 'Hatching';
  rsMaterialAllowance = 'Allowance';

implementation

uses
  Math, Forms, Sloper.Core.JSON;

const
  ColumnColour = 0;
  ColumnName = 1;
  ColumnFill = 2;
  ColumnAllowance = 3;
  ColourWidth96 = 64;
  NameWidth96 = 130;
  FillWidth96 = 90;
  AllowanceWidth96 = 90;
  // Between hatching lines in a swatch, at 96 pixels per inch
  SwatchHatchGap96 = 6;

function ChooseMaterialColor(Owner: TComponent; var Text: string): boolean;
var
  Dialog: TColorDialog;
  Chosen: TMaterialColor;
begin
  Dialog := TColorDialog.Create(Owner);
  try
    Chosen := ParseMaterialColor(Text);
    Dialog.Color := RGBToColor(Chosen.Red, Chosen.Green, Chosen.Blue);
    Result := Dialog.Execute;
    if not Result then
      Exit;
    Chosen.Red := Red(ColorToRGB(Dialog.Color));
    Chosen.Green := Green(ColorToRGB(Dialog.Color));
    Chosen.Blue := Blue(ColorToRGB(Dialog.Color));
    Text := MaterialColorText(Chosen);
  finally
    FreeAndNil(Dialog);
  end;
end;

function MaterialFillCaption(Fill: TMaterialFill): string;
begin
  if Fill = ffHatch then
    Result := rsMaterialFillHatch
  else
    Result := rsMaterialFillTint;
end;

function SwatchColor(const ColorText: string): TColor;
var
  Parsed: TMaterialColor;
begin
  Parsed := ParseMaterialColor(ColorText);
  Result := RGBToColor(Parsed.Red, Parsed.Green, Parsed.Blue);
end;

// Parallel lines through the rectangle, spaced along their normal
procedure DrawSwatchHatching(Canvas: TCanvas; const Rect: TRect; Angle: double; Ink: TColor);
var
  DirX, DirY, NormX, NormY, CentreX, CentreY, Reach, Offset, Gap: double;
begin
  // Screen y runs down, and angles turn anticlockwise as seen
  DirX := Cos(DegToRad(Angle));
  DirY := -Sin(DegToRad(Angle));
  NormX := -DirY;
  NormY := DirX;
  CentreX := (Rect.Left + Rect.Right) / 2;
  CentreY := (Rect.Top + Rect.Bottom) / 2;
  Reach := Hypot(Rect.Right - Rect.Left, Rect.Bottom - Rect.Top);
  Gap := Max(3, SwatchHatchGap96 * Screen.PixelsPerInch / 96);
  Canvas.Pen.Color := Ink;
  Canvas.Pen.Width := 1;
  Canvas.ClipRect := Rect;
  Canvas.Clipping := True;
  try
    Offset := -Reach;
    while Offset <= Reach do
    begin
      Canvas.Line(Round(CentreX + NormX * Offset - DirX * Reach), Round(CentreY + NormY * Offset - DirY * Reach),
        Round(CentreX + NormX * Offset + DirX * Reach), Round(CentreY + NormY * Offset + DirY * Reach));
      Offset := Offset + Gap;
    end;
  finally
    Canvas.Clipping := False;
  end;
end;

constructor TMaterialGrid.Create(AOwner: TComponent);

  procedure AddColumn(const ACaption: string; Width96: integer);
  var
    Column: TGridColumn;
  begin
    Column := Columns.Add;
    Column.Title.Caption := ACaption;
    Column.Width := Scale96ToScreen(Width96);
    Column.ReadOnly := True;
  end;

begin
  inherited Create(AOwner);
  FixedCols := 0;
  FixedRows := 1;
  RowCount := 1;
  Options := Options + [goRowSelect] - [goRangeSelect, goEditing];
  AddColumn(rsMaterialColour, ColourWidth96);
  AddColumn(rsMaterialName, NameWidth96);
  AddColumn(rsMaterialFill, FillWidth96);
  AddColumn(rsMaterialAllowance, AllowanceWidth96);
end;

procedure TMaterialGrid.ShowMaterials(APattern: TPattern);
var
  Index, Current: integer;
  Material: TPatternMaterial;
begin
  FPattern := APattern;
  Current := MaterialIndex;
  FFilling := True;
  try
    BeginUpdate;
    try
      if not Assigned(FPattern) then
        RowCount := 1
      else
      begin
        RowCount := FPattern.MaterialCount + 1;
        for Index := 0 to FPattern.MaterialCount - 1 do
        begin
          Material := FPattern.Materials[Index];
          Cells[ColumnColour, Index + 1] := '';
          Cells[ColumnName, Index + 1] := Material.Name;
          Cells[ColumnFill, Index + 1] := MaterialFillCaption(Material.Fill);
          if Material.HasAllowance then
            Cells[ColumnAllowance, Index + 1] := FormatJSONFloat(Material.Allowance)
          else
            Cells[ColumnAllowance, Index + 1] := '';
        end;
      end;
    finally
      EndUpdate;
    end;
    if Current >= 0 then
      SetMaterialIndex(Min(Current, RowCount - 2));
  finally
    FFilling := False;
  end;
  Invalidate;
end;

function TMaterialGrid.GetMaterialIndex: integer;
begin
  Result := -1;
  if Assigned(FPattern) and (Row >= 1) and (Row <= FPattern.MaterialCount) then
    Result := Row - 1;
end;

procedure TMaterialGrid.SetMaterialIndex(Index: integer);
begin
  if (Index >= 0) and (Index < RowCount - 1) then
    Row := Index + 1;
end;

procedure TMaterialGrid.PrepareCanvas(ACol, ARow: integer; AState: TGridDrawState);
begin
  inherited PrepareCanvas(ACol, ARow, AState);
  if (ACol = ColumnColour) and (ARow >= 1) and Assigned(FPattern) and (ARow <= FPattern.MaterialCount) then
    Canvas.Brush.Color := SwatchColor(FPattern.Materials[ARow - 1].Color);
end;

// A hatched material's swatch shows its hatching, at its angle
procedure TMaterialGrid.DrawCell(ACol, ARow: integer; ARect: TRect; AState: TGridDrawState);
var
  Swatch: TRect;
begin
  inherited DrawCell(ACol, ARow, ARect, AState);
  if (ACol <> ColumnColour) or (ARow < 1) or not Assigned(FPattern) or (ARow > FPattern.MaterialCount) or
    (FPattern.Materials[ARow - 1].Fill <> ffHatch) then
    Exit;
  Swatch := ARect;
  InflateRect(Swatch, -1, -1);
  Canvas.Brush.Color := clWhite;
  Canvas.FillRect(Swatch);
  DrawSwatchHatching(Canvas, Swatch, MaterialHatchAngle(ARow - 1), SwatchColor(FPattern.Materials[ARow - 1].Color));
end;

end.
