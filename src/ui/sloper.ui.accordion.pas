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

// The side panel's sections, one open at a time: each has a header across
// the full width, and the open one shows its panel under its header, with
// the headers after it collapsed at the bottom (see Side panel in the design).
unit Sloper.UI.Accordion;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Controls, ExtCtrls, Graphics, LCLType;

type
  TAccordion = class;

  // A section's header: click it, or press Enter or Space on it, to open
  // its section; Up and Down move to the next header
  TAccordionHeader = class(TCustomControl)
  private
    FAccordion: TAccordion;
    FOpen: boolean;
    FHot: boolean;
    procedure SetOpen(AOpen: boolean);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AAccordion: TAccordion); reintroduce;
    property Open: boolean read FOpen write SetOpen;
  end;

  TAccordionSection = class
  public
    // Names the section in settings, whatever its caption
    Key: string;
    Header: TAccordionHeader;
    // What the section shows, the parent for its panel
    Content: TPanel;
    Shown: boolean;
  end;

  TAccordionSectionList = specialize TObjectList<TAccordionSection>;

  TAccordion = class(TCustomControl)
  private
    FSections: TAccordionSectionList;
    FActive: TAccordionSection;
    function HeaderHeight: integer;
    function SectionOf(Content: TWinControl): TAccordionSection;
    function SectionOfHeader(Header: TAccordionHeader): TAccordionSection;
    procedure ArrangeSections;
    procedure Activate(Section: TAccordionSection);
    procedure HeaderClicked(Header: TAccordionHeader);
    procedure FocusNextHeader(Header: TAccordionHeader; Step: integer);
    function GetActiveContent: TWinControl;
    procedure SetActiveContent(Content: TWinControl);
    function GetActiveKey: string;
    procedure SetActiveKey(const AKey: string);
  protected
    procedure Resize; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // A new section at the end, closed unless it is the first; the result is
    // the parent for its panel
    function AddSection(const AKey, ACaption: string): TWinControl;
    // Leaves a section out, header and all, or brings it back; the open
    // section, once left out, gives way to the first shown one
    procedure SetSectionShown(Content: TWinControl; Shown: boolean);
    // The open section, by what AddSection gave
    property ActiveContent: TWinControl read GetActiveContent write SetActiveContent;
    // The open section by its key; a key no shown section has changes nothing
    property ActiveKey: string read GetActiveKey write SetActiveKey;
  end;

implementation

uses
  Math, Sloper.UI.AccordionLayout;

const
  // At 96 pixels per inch
  HEADER_HEIGHT96 = 26;
  HEADER_PADDING96 = 10;
  TEXT_INDENT96 = 24;
  ARROW_LEFT96 = 8;
  ARROW_SIZE96 = 8;
  // How much of the highlight colour tints an open or pointed-at header
  OPEN_TINT = 0.18;
  HOT_TINT = 0.10;

// From First towards Second by Amount, 0 to 1
function Blend(First, Second: TColor; Amount: double): TColor;
var
  From, Towards: longint;
begin
  From := ColorToRGB(First);
  Towards := ColorToRGB(Second);
  Result := RGBToColor(Round(Red(From) + (Red(Towards) - Red(From)) * Amount), Round(Green(From) + (Green(Towards) - Green(From)) * Amount),
    Round(Blue(From) + (Blue(Towards) - Blue(From)) * Amount));
end;

{ TAccordionHeader }

constructor TAccordionHeader.Create(AAccordion: TAccordion);
begin
  inherited Create(AAccordion);
  FAccordion := AAccordion;
  TabStop := True;
  ControlStyle := ControlStyle + [csOpaque];
end;

procedure TAccordionHeader.SetOpen(AOpen: boolean);
begin
  if FOpen = AOpen then
    Exit;
  FOpen := AOpen;
  Invalidate;
end;

// A tinted bar with a line under it, an arrow pointing down when open and
// right when closed, and the caption, bold when open
procedure TAccordionHeader.Paint;
var
  Area: TRect;
  ArrowLeft, ArrowSize, Middle: integer;
begin
  Area := ClientRect;
  if FOpen then
    Canvas.Brush.Color := Blend(clBtnFace, clHighlight, OPEN_TINT)
  else if FHot then
    Canvas.Brush.Color := Blend(clBtnFace, clHighlight, HOT_TINT)
  else
    Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(Area);
  Canvas.Pen.Color := clBtnShadow;
  Canvas.Line(Area.Left, Area.Bottom - 1, Area.Right, Area.Bottom - 1);
  ArrowLeft := Scale96ToForm(ARROW_LEFT96);
  ArrowSize := Scale96ToForm(ARROW_SIZE96);
  Middle := (Area.Top + Area.Bottom) div 2;
  Canvas.Pen.Color := clBtnText;
  Canvas.Brush.Color := clBtnText;
  if FOpen then
    Canvas.Polygon([Point(ArrowLeft, Middle - ArrowSize div 4), Point(ArrowLeft + ArrowSize, Middle - ArrowSize div 4),
      Point(ArrowLeft + ArrowSize div 2, Middle + ArrowSize div 4 + 1)])
  else
    Canvas.Polygon([Point(ArrowLeft + ArrowSize div 4, Middle - ArrowSize div 2), Point(ArrowLeft + ArrowSize div 4, Middle + ArrowSize div 2),
      Point(ArrowLeft + ArrowSize * 3 div 4 + 1, Middle)]);
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Color := clBtnText;
  if FOpen then
    Canvas.Font.Style := [fsBold];
  Canvas.TextOut(Scale96ToForm(TEXT_INDENT96), Middle - Canvas.TextHeight(Caption) div 2, Caption);
  Canvas.Brush.Style := bsSolid;
  if Focused then
    Canvas.DrawFocusRect(Rect(Area.Left + 2, Area.Top + 2, Area.Right - 2, Area.Bottom - 3));
end;

// A click opens the section without taking the keyboard from the canvas
procedure TAccordionHeader.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    FAccordion.HeaderClicked(Self);
end;

procedure TAccordionHeader.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TAccordionHeader.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TAccordionHeader.KeyDown(var Key: word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_RETURN, VK_SPACE:
    begin
      FAccordion.HeaderClicked(Self);
      Key := 0;
    end;
    VK_UP:
    begin
      FAccordion.FocusNextHeader(Self, -1);
      Key := 0;
    end;
    VK_DOWN:
    begin
      FAccordion.FocusNextHeader(Self, 1);
      Key := 0;
    end;
  end;
end;

procedure TAccordionHeader.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TAccordionHeader.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

{ TAccordion }

constructor TAccordion.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSections := TAccordionSectionList.Create(True);
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TAccordion.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FSections);
end;

// Tall enough for the caption in the widgetset's font
function TAccordion.HeaderHeight: integer;
begin
  Result := Scale96ToForm(HEADER_HEIGHT96);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    Result := Max(Result, Canvas.TextHeight('Ag') + Scale96ToForm(HEADER_PADDING96));
  end;
end;

function TAccordion.AddSection(const AKey, ACaption: string): TWinControl;
var
  Section: TAccordionSection;
begin
  Section := TAccordionSection.Create;
  FSections.Add(Section);
  Section.Key := AKey;
  Section.Shown := True;
  Section.Header := TAccordionHeader.Create(Self);
  Section.Header.Caption := ACaption;
  Section.Header.Parent := Self;
  Section.Content := TPanel.Create(Self);
  Section.Content.BevelOuter := bvNone;
  Section.Content.Caption := '';
  // Lighter than the headers, as a tab page is
  Section.Content.Color := clWindow;
  Section.Content.Visible := False;
  Section.Content.Parent := Self;
  if not Assigned(FActive) then
    Activate(Section)
  else
    ArrangeSections;
  Result := Section.Content;
end;

function TAccordion.SectionOf(Content: TWinControl): TAccordionSection;
begin
  for Result in FSections do
    if Result.Content = Content then
      Exit;
  Result := nil;
end;

function TAccordion.SectionOfHeader(Header: TAccordionHeader): TAccordionSection;
begin
  for Result in FSections do
    if Result.Header = Header then
      Exit;
  Result := nil;
end;

procedure TAccordion.SetSectionShown(Content: TWinControl; Shown: boolean);
var
  Section, First: TAccordionSection;
begin
  Section := SectionOf(Content);
  if not Assigned(Section) or (Section.Shown = Shown) then
    Exit;
  Section.Shown := Shown;
  Section.Header.Visible := Shown;
  if Section = FActive then
  begin
    FActive := nil;
    for First in FSections do
      if First.Shown then
      begin
        Activate(First);
        Exit;
      end;
    Section.Content.Visible := False;
  end;
  ArrangeSections;
end;

function TAccordion.GetActiveContent: TWinControl;
begin
  Result := nil;
  if Assigned(FActive) then
    Result := FActive.Content;
end;

procedure TAccordion.SetActiveContent(Content: TWinControl);
var
  Section: TAccordionSection;
begin
  Section := SectionOf(Content);
  if Assigned(Section) and Section.Shown then
    Activate(Section);
end;

function TAccordion.GetActiveKey: string;
begin
  Result := '';
  if Assigned(FActive) then
    Result := FActive.Key;
end;

procedure TAccordion.SetActiveKey(const AKey: string);
var
  Section: TAccordionSection;
begin
  for Section in FSections do
    if (Section.Key = AKey) and Section.Shown then
    begin
      Activate(Section);
      Exit;
    end;
end;

// The new section is shown before the old one is hidden, so the panel never
// stands empty, and a field being typed in the old one commits as it goes
procedure TAccordion.Activate(Section: TAccordionSection);
var
  Other: TAccordionSection;
begin
  FActive := Section;
  DisableAlign;
  try
    for Other in FSections do
      Other.Header.Open := Other = Section;
    ArrangeSections;
    Section.Content.Visible := True;
    for Other in FSections do
      if Other <> Section then
        Other.Content.Visible := False;
  finally
    EnableAlign;
  end;
end;

procedure TAccordion.HeaderClicked(Header: TAccordionHeader);
var
  Section: TAccordionSection;
begin
  Section := SectionOfHeader(Header);
  if Assigned(Section) and (Section <> FActive) then
    Activate(Section);
end;

procedure TAccordion.FocusNextHeader(Header: TAccordionHeader; Step: integer);
var
  Index: integer;
begin
  Index := FSections.IndexOf(SectionOfHeader(Header));
  if Index < 0 then
    Exit;
  repeat
    Index := Index + Step;
  until (Index < 0) or (Index >= FSections.Count) or FSections[Index].Shown;
  if (Index >= 0) and (Index < FSections.Count) and FSections[Index].Header.CanFocus then
    FSections[Index].Header.SetFocus;
end;

procedure TAccordion.ArrangeSections;
var
  Shown: array of TAccordionSection;
  Section: TAccordionSection;
  Places: TAccordionPlaces;
  RowHeight, Index, ActiveIndex: integer;
begin
  Shown := nil;
  ActiveIndex := 0;
  for Section in FSections do
    if Section.Shown then
    begin
      if Section = FActive then
        ActiveIndex := Length(Shown);
      Insert(Section, Shown, Length(Shown));
    end;
  if Length(Shown) = 0 then
    Exit;
  RowHeight := HeaderHeight;
  Places := PlaceSections(Length(Shown), ActiveIndex, RowHeight, ClientHeight);
  for Index := 0 to High(Shown) do
    Shown[Index].Header.SetBounds(0, Places.HeaderTops[Index], ClientWidth, RowHeight);
  if Assigned(FActive) then
    FActive.Content.SetBounds(0, Places.ContentTop, ClientWidth, Places.ContentHeight);
end;

procedure TAccordion.Resize;
begin
  inherited Resize;
  ArrangeSections;
end;

procedure TAccordion.Paint;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);
end;

end.
