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

// The Garment View window: a read-only flat front and back, drawn at one scale
// and kept up to date with the pattern. The drawing comes from
// Sloper.Core.Garment; this only shows it.
unit Sloper.UI.GarmentWindow;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, BGRABitmap, BGRABitmapTypes, Sloper.Core.Garment, Sloper.Document.PatternDocument;

type
  TGarmentPane = class(TCustomControl)
  private
    FDocument: TPatternDocument;
    FBitmap: TBGRABitmap;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write FDocument;
  end;

  TGarmentWindow = class(TForm)
  private
    FDocument: TPatternDocument;
    FPane: TGarmentPane;
    FNotes: TLabel;
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure SetDocument(ADocument: TPatternDocument);
    procedure RefreshNotes;
  public
    constructor CreateFor(AOwner: TComponent);
    destructor Destroy; override;
    procedure ShowView;
    property Document: TPatternDocument read FDocument write SetDocument;
  end;

resourcestring
  rsGarmentTitle = 'Garment View';
  rsGarmentFront = 'Front';
  rsGarmentBack = 'Back';
  rsGarmentEmpty = 'Nothing in this view';
  rsGarmentNoView = 'Pieces in neither view: %d. Set View in a piece''s properties.';

implementation

uses
  Math, Graphics, Sloper.Core.Fabrics, Sloper.Core.Geometry, Sloper.UI.GarmentNotes;

const
  HatchPixels = 8;
  WindowWidth = 800;
  WindowHeight = 620;
  PaneMargin = 24;
  TitleHeight = 28;
  NotePadding = 6;

function Paper: TBGRAPixel;
begin
  Result := BGRA(252, 251, 248);
end;

function Ink: TBGRAPixel;
begin
  Result := BGRA(34, 36, 40);
end;

function Tint(const Color: TFabricColor): TBGRAPixel;
var
  Light: TFabricColor;
begin
  Light := FabricTint(Color);
  Result := BGRA(Light.R, Light.G, Light.B);
end;

constructor TGarmentPane.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBitmap := TBGRABitmap.Create(1, 1);
end;

destructor TGarmentPane.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TGarmentPane.Paint;
var
  Stroke: TLine2;
  Drawings: array[TGarmentSide] of TGarmentDrawing;
  Names: array[TGarmentSide] of string;
  Side: TGarmentSide;
  Shape: TGarmentShape;
  Line: TVec2Array;
  Scale, SlotWidth, SlotHeight, SlotLeft, OffsetX, OffsetY: double;

  function ScreenPoints(const Points: TVec2Array): ArrayOfTPointF;
  var
    Index: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Points));
    for Index := 0 to High(Points) do
      Result[Index] := PointF(OffsetX + Points[Index].X * Scale, OffsetY - Points[Index].Y * Scale);
  end;

  function ScreenVectors(const Points: TVec2Array): TVec2Array;
  var
    Index: integer;
  begin
    Result := nil;
    SetLength(Result, Length(Points));
    for Index := 0 to High(Points) do
      Result[Index] := Vec2(OffsetX + Points[Index].X * Scale, OffsetY - Points[Index].Y * Scale);
  end;

  function FitScale(const Drawing: TGarmentDrawing): double;
  begin
    Result := Min(SlotWidth / Max(Drawing.Bounds.MaxX - Drawing.Bounds.MinX, 1), SlotHeight / Max(Drawing.Bounds.MaxY - Drawing.Bounds.MinY, 1));
  end;

begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FBitmap.Fill(Paper);
  if FDocument = nil then
  begin
    FBitmap.Draw(Canvas, 0, 0, True);
    Exit;
  end;
  Names[gsFront] := rsGarmentFront;
  Names[gsBack] := rsGarmentBack;
  SlotWidth := Max(ClientWidth / 2 - 2 * PaneMargin, 1);
  SlotHeight := Max(ClientHeight - TitleHeight - 2 * PaneMargin, 1);
  // One scale, so front and back compare
  Scale := Infinity;
  for Side := Low(TGarmentSide) to High(TGarmentSide) do
  begin
    Drawings[Side] := BuildGarment(FDocument.Pattern, Side);
    if Drawings[Side].Shapes <> nil then
      Scale := Min(Scale, FitScale(Drawings[Side]));
  end;
  FBitmap.FontHeight := 14;
  for Side := Low(TGarmentSide) to High(TGarmentSide) do
  begin
    SlotLeft := PaneMargin + Ord(Side) * (ClientWidth / 2);
    FBitmap.TextOut(SlotLeft, PaneMargin / 2, Names[Side], Ink);
    if Drawings[Side].Shapes = nil then
    begin
      FBitmap.FontHeight := 12;
      FBitmap.TextOut(SlotLeft, PaneMargin + TitleHeight, rsGarmentEmpty, Ink);
      FBitmap.FontHeight := 14;
      Continue;
    end;
    OffsetX := SlotLeft + SlotWidth / 2 - (Drawings[Side].Bounds.MinX + Drawings[Side].Bounds.MaxX) / 2 * Scale;
    OffsetY := TitleHeight + PaneMargin + SlotHeight / 2 + (Drawings[Side].Bounds.MinY + Drawings[Side].Bounds.MaxY) / 2 * Scale;
    // A thin line in the tint closes the hairline where two halves meet
    for Shape in Drawings[Side].Shapes do
    begin
      if not Shape.Look.Filled then
        Continue;
      if Shape.Look.Fill = ffHatch then
      begin
        for Stroke in HatchLines(ScreenVectors(Shape.Outline), HatchPixels, Shape.Look.HatchAngle) do
          FBitmap.DrawLineAntialias(Stroke.P1.X, Stroke.P1.Y, Stroke.P2.X, Stroke.P2.Y, BGRA(Shape.Look.Color.R, Shape.Look.Color.G, Shape.Look.Color.B), 1);
        Continue;
      end;
      FBitmap.FillPolyAntialias(ScreenPoints(Shape.Outline), Tint(Shape.Look.Color));
      FBitmap.DrawPolygonAntialias(ScreenPoints(Shape.Outline), Tint(Shape.Look.Color), 1);
    end;
    for Shape in Drawings[Side].Shapes do
      for Line in Shape.Lines do
        FBitmap.DrawPolyLineAntialias(ScreenPoints(Line), Ink, 1.5);
  end;
  FBitmap.Draw(Canvas, 0, 0, True);
end;

constructor TGarmentWindow.CreateFor(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := rsGarmentTitle;
  Width := WindowWidth;
  Height := WindowHeight;
  Position := poOwnerFormCenter;
  // Stays over the main window, so a change there can be watched here
  PopupMode := pmExplicit;
  PopupParent := TCustomForm(AOwner);
  FNotes := TLabel.Create(Self);
  FNotes.Parent := Self;
  FNotes.Align := alBottom;
  FNotes.WordWrap := True;
  FNotes.BorderSpacing.Around := NotePadding;
  FPane := TGarmentPane.Create(Self);
  FPane.Parent := Self;
  FPane.Align := alClient;
end;

destructor TGarmentWindow.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TGarmentWindow.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument <> nil then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  FPane.Document := ADocument;
  if FDocument <> nil then
    FDocument.AddListener(@DocumentChanged);
end;

procedure TGarmentWindow.RefreshNotes;
var
  Lines: TStringArray;
  Line: string;
  Missing: integer;
begin
  Lines := Concat(GarmentNotes(BuildGarment(FDocument.Pattern, gsFront), rsGarmentFront),
    GarmentNotes(BuildGarment(FDocument.Pattern, gsBack), rsGarmentBack));
  Missing := PiecesWithoutView(FDocument.Pattern);
  if Missing > 0 then
    Insert(Format(rsGarmentNoView, [Missing]), Lines, Length(Lines));
  FNotes.Caption := '';
  for Line in Lines do
    if FNotes.Caption = '' then
      FNotes.Caption := Line
    else
      FNotes.Caption := FNotes.Caption + LineEnding + Line;
end;

procedure TGarmentWindow.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if not Visible then
    Exit;
  RefreshNotes;
  FPane.Invalidate;
end;

procedure TGarmentWindow.ShowView;
begin
  RefreshNotes;
  Show;
  BringToFront;
  FPane.Invalidate;
end;

end.
