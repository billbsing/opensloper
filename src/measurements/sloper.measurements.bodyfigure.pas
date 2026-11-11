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

// The body figure: front, back and side outlines, with the measurements in the
// file drawn on them. One is highlighted, and clicking one picks it.
unit Sloper.Measurements.BodyFigure;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, BGRABitmap, BGRABitmapTypes, Sloper.Core.Catalogue, Sloper.Core.Geometry;

type
  TKeyEvent = procedure(Sender: TObject; const Key: string) of object;

  TBodyFigure = class(TCustomControl)
  private
    FBitmap: TBGRABitmap;
    FCatalogue: TCatalogue;
    FKeys: TStringArray;
    FHighlight, FHover: string;
    FOnPick, FOnHover: TKeyEvent;
    function KeyAt(X, Y: integer): string;
    function ScreenPoints(View: TCatalogueView; const Path: TFigurePath): ArrayOfTPointF;
    procedure DrawOverlay(Entry: TCatalogueEntry; Ink: TBGRAPixel; AWidth: single);
    procedure DrawView(View: TCatalogueView);
    procedure SetHighlight(const AKey: string);
    procedure SetKeys(const AKeys: TStringArray);
    procedure SetCatalogue(ACatalogue: TCatalogue);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Paint; override;
    property Catalogue: TCatalogue read FCatalogue write SetCatalogue;
    // The measurements in the file, drawn faintly
    property Keys: TStringArray read FKeys write SetKeys;
    property Highlight: string read FHighlight write SetHighlight;
    property OnPick: TKeyEvent read FOnPick write FOnPick;
    // The key under the mouse, '' when it leaves
    property OnHover: TKeyEvent read FOnHover write FOnHover;
  end;

resourcestring
  rsViewFront = 'Front';
  rsViewBack = 'Back';
  rsViewSide = 'Side';

implementation

uses
  Math;

const
  HIT_PIXELS = 5;
  OVERLAY_WIDTH = 1.5;
  HIGHLIGHT_WIDTH = 3;
  OUTLINE_WIDTH = 1.2;
  CAPTION_HEIGHT = 13;
  CAPTION_GAP = 2;
  // Kept clear below the figures, with room for the text's descent
  CAPTION_ROOM = CAPTION_HEIGHT + 3 * CAPTION_GAP;
  VIEW_CAPTIONS: array[TCatalogueView] of string = (rsViewFront, rsViewBack, rsViewSide);

var
  Desk, BodyFill, BodyEdge, OverlayInk, HighlightInk: TBGRAPixel;

constructor TBodyFigure.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBitmap := TBGRABitmap.Create(1, 1);
end;

destructor TBodyFigure.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TBodyFigure.SetCatalogue(ACatalogue: TCatalogue);
begin
  FCatalogue := ACatalogue;
  Invalidate;
end;

procedure TBodyFigure.SetKeys(const AKeys: TStringArray);
begin
  FKeys := AKeys;
  Invalidate;
end;

procedure TBodyFigure.SetHighlight(const AKey: string);
begin
  if AKey = FHighlight then
    Exit;
  FHighlight := AKey;
  Invalidate;
end;

function TBodyFigure.ScreenPoints(View: TCatalogueView; const Path: TFigurePath): ArrayOfTPointF;
var
  Layout: TFigureLayout;
  Index: integer;
  Spot: TVec2;
begin
  Layout := LayoutFigures(ClientWidth, ClientHeight - CAPTION_ROOM);
  Result := nil;
  SetLength(Result, Length(Path));
  for Index := 0 to High(Path) do
  begin
    Spot := FigureToScreen(Layout, View, Path[Index]);
    Result[Index] := PointF(Spot.X, Spot.Y);
  end;
end;

procedure TBodyFigure.DrawOverlay(Entry: TCatalogueEntry; Ink: TBGRAPixel; AWidth: single);
begin
  FBitmap.DrawPolyLineAntialias(ScreenPoints(Entry.View, Entry.Overlay), Ink, AWidth);
end;

procedure TBodyFigure.DrawView(View: TCatalogueView);
var
  Path: TFigurePath;
  Layout: TFigureLayout;
  Middle: TVec2;
begin
  for Path in FCatalogue.Figures[View] do
    FBitmap.DrawPolygonAntialias(FBitmap.ComputeClosedSpline(ScreenPoints(View, Path), ssCrossing), BodyEdge, OUTLINE_WIDTH, BodyFill);
  Layout := LayoutFigures(ClientWidth, ClientHeight - CAPTION_ROOM);
  Middle := FigureToScreen(Layout, View, Vec2(FIGURE_WIDTH / 2, FIGURE_HEIGHT));
  FBitmap.FontHeight := CAPTION_HEIGHT;
  FBitmap.TextOut(Middle.X, Middle.Y + CAPTION_GAP, VIEW_CAPTIONS[View], BodyEdge, taCenter);
end;

procedure TBodyFigure.Paint;
var
  View: TCatalogueView;
  Key: string;
  Entry: TCatalogueEntry;
begin
  if (FBitmap.Width <> ClientWidth) or (FBitmap.Height <> ClientHeight) then
    FBitmap.SetSize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FBitmap.Fill(Desk);
  FBitmap.FontQuality := fqFineAntialiasing;
  if Assigned(FCatalogue) then
  begin
    for View := Low(TCatalogueView) to High(TCatalogueView) do
      if Assigned(FCatalogue.Figures[View]) then
        DrawView(View);
    for Key in FKeys do
    begin
      Entry := FCatalogue.Find(Key);
      if Assigned(Entry) then
        DrawOverlay(Entry, OverlayInk, OVERLAY_WIDTH);
    end;
    Entry := FCatalogue.Find(FHighlight);
    if Assigned(Entry) then
      DrawOverlay(Entry, HighlightInk, HIGHLIGHT_WIDTH);
  end;
  FBitmap.Draw(Canvas, 0, 0, True);
end;

function TBodyFigure.KeyAt(X, Y: integer): string;
var
  Layout: TFigureLayout;
  View: TCatalogueView;
  OnFigure: TVec2;
  Entry: TCatalogueEntry;
begin
  Result := '';
  if not Assigned(FCatalogue) then
    Exit;
  Layout := LayoutFigures(ClientWidth, ClientHeight - CAPTION_ROOM);
  if not ScreenToFigure(Layout, Vec2(X, Y), View, OnFigure) then
    Exit;
  Entry := FCatalogue.OverlayAt(View, OnFigure, HIT_PIXELS / Layout.Scale, FKeys);
  if Assigned(Entry) then
    Result := Entry.Key;
end;

procedure TBodyFigure.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Key: string;
begin
  inherited MouseDown(Button, Shift, X, Y);
  Key := KeyAt(X, Y);
  if (Button = mbLeft) and (Key <> '') and Assigned(FOnPick) then
    FOnPick(Self, Key);
end;

procedure TBodyFigure.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Key: string;
begin
  inherited MouseMove(Shift, X, Y);
  Key := KeyAt(X, Y);
  if Key = FHover then
    Exit;
  FHover := Key;
  if Key = '' then
    Cursor := crDefault
  else
    Cursor := crHandPoint;
  if Assigned(FOnHover) then
    FOnHover(Self, Key);
end;

procedure TBodyFigure.MouseLeave;
begin
  inherited MouseLeave;
  if FHover = '' then
    Exit;
  FHover := '';
  if Assigned(FOnHover) then
    FOnHover(Self, '');
end;

initialization
  Desk := BGRA(255, 255, 255);
  BodyFill := BGRA(240, 238, 234);
  BodyEdge := BGRA(90, 90, 96);
  OverlayInk := BGRA(120, 150, 190);
  HighlightInk := BGRA(200, 50, 40);

end.
