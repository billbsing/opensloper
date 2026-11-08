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

// A window's commands as actions, shared by its menu items and the buttons of
// a toolbar along the top, with the icons drawn for both. Used by the
// measurements and publish apps. Without the icon folder the buttons show
// their captions instead.
unit Sloper.UI.Commands;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Forms, Controls, Menus, ActnList, ComCtrls, Sloper.UI.IconSet;

type
  TCommandSet = class(TComponent)
  private
    FActions: TActionList;
    FBar: TToolBar;
    FToolIcons, FDisabledIcons, FMenuIcons: TImageList;
  public
    // Puts the toolbar at the top of Form and gives Menu its icons
    constructor Create(Form: TCustomForm; Menu: TMainMenu); reintroduce;
    function NewAction(const ACaption: string; AIcon: TAppIcon; AHandler: TNotifyEvent; AShortCut: TShortCut = 0; ATag: PtrInt = 0): TAction;
    function AddMenuItem(Parent: TMenuItem; AAction: TAction): TMenuItem;
    procedure AddButton(AAction: TAction);
    procedure AddDivider;
    property Actions: TActionList read FActions;
    property Bar: TToolBar read FBar;
  end;

// The tooltip: the caption without its accelerator or dots. The LCL adds the
// shortcut itself.
procedure SetActionHint(AAction: TAction);

// A line between groups of buttons. Drawn here, as the Qt styles draw the
// divider too faint to see.
procedure AddToolDivider(Bar: TToolBar);

// Draws the lines between groups of menu items in the colour of the toolbar
// dividers, in every menu of the app, as the Qt styles draw them too faint to
// see on a dark menu. Safe to call more than once.
procedure ShowMenuDividers;

implementation

uses
  {$IFDEF LCLQt5}qt5,{$ENDIF}
  {$IFDEF LCLQt6}qt6,{$ENDIF}
  SysUtils, Graphics, LCLProc, Sloper.UI.Icons;

const
  ToolIconSize = 24;
  MenuIconSize = 16;
  ButtonPadding = 8;
  DividerSpace = 11;
  DividerInset = 4;
  MenuDividerGap = 4;
  MenuDividerInset = 6;

type
  TDividerButton = class(TToolButton)
  protected
    procedure Paint; override;
  end;

function IsVerticalBar(Button: TToolButton): boolean;
begin
  Result := Assigned(Button.Parent) and (Button.Parent.Align in [alLeft, alRight]);
end;

procedure TDividerButton.Paint;
var
  Inset, Middle: integer;
begin
  Inset := Scale96ToForm(DividerInset);
  Canvas.Pen.Color := clGrayText;
  Canvas.Pen.Width := 1;
  if IsVerticalBar(Self) then
  begin
    Middle := ClientHeight div 2;
    Canvas.Line(Inset, Middle, ClientWidth - Inset, Middle);
  end
  else
  begin
    Middle := ClientWidth div 2;
    Canvas.Line(Middle, Inset, Middle, ClientHeight - Inset);
  end;
end;

procedure AddToolDivider(Bar: TToolBar);
var
  Button: TToolButton;
begin
  // The bar sizes a divider by its Width or Height along the bar, and a new
  // button gets the full button size when it joins the bar
  Button := TDividerButton.Create(Bar);
  Button.Parent := Bar;
  Button.Style := tbsDivider;
  if IsVerticalBar(Button) then
    Button.Height := Bar.Scale96ToForm(DividerSpace)
  else
    Button.Width := Bar.Scale96ToForm(DividerSpace);
end;

{$IF DEFINED(LCLQt5) or DEFINED(LCLQt6)}
var
  MenuDividersShown: boolean = False;

function Scale96(Size: integer): integer;
begin
  Result := Round(Size * Screen.PixelsPerInch / 96);
end;

// Added to the app's style sheet, keeping any the Qt theme has set
procedure ShowMenuDividers;
var
  App: QApplicationH;
  Sheet: WideString;
  Color: TColor;
begin
  if MenuDividersShown then
    Exit;
  MenuDividersShown := True;
  App := QApplicationH(QCoreApplication_instance());
  QApplication_styleSheet(App, @Sheet);
  Color := ColorToRGB(clGrayText);
  Sheet := Sheet + UTF8Decode(Format(LineEnding + 'QMenu::separator { height: 1px; margin: %dpx %dpx; background: #%.2x%.2x%.2x; }',
    [Scale96(MenuDividerGap), Scale96(MenuDividerInset), Red(Color), Green(Color), Blue(Color)]));
  QApplication_setStyleSheet(App, @Sheet);
end;
{$ELSE}

procedure ShowMenuDividers;
begin
end;
{$ENDIF}

procedure SetActionHint(AAction: TAction);
begin
  AAction.Hint := StringReplace(StripHotkey(AAction.Caption), '...', '', []);
end;

constructor TCommandSet.Create(Form: TCustomForm; Menu: TMainMenu);
begin
  inherited Create(Form);
  FToolIcons := CreateIconList(Self, Form.Scale96ToForm(ToolIconSize), clWindowText);
  FDisabledIcons := CreateIconList(Self, Form.Scale96ToForm(ToolIconSize), clGrayText);
  FMenuIcons := CreateIconList(Self, Form.Scale96ToForm(MenuIconSize), clMenuText);
  FActions := TActionList.Create(Self);
  FActions.Images := FMenuIcons;
  Menu.Images := FMenuIcons;
  ShowMenuDividers;
  FBar := TToolBar.Create(Self);
  FBar.Parent := Form;
  FBar.Align := alTop;
  FBar.Images := FToolIcons;
  FBar.DisabledImages := FDisabledIcons;
  FBar.ShowCaptions := not IconsFound;
  FBar.ShowHint := True;
  FBar.AutoSize := True;
  FBar.Wrapable := True;
  if IconsFound then
  begin
    FBar.ButtonWidth := FToolIcons.Width + Form.Scale96ToForm(ButtonPadding);
    FBar.ButtonHeight := FToolIcons.Height + Form.Scale96ToForm(ButtonPadding);
  end;
end;

function TCommandSet.NewAction(const ACaption: string; AIcon: TAppIcon; AHandler: TNotifyEvent; AShortCut: TShortCut; ATag: PtrInt): TAction;
begin
  Result := TAction.Create(FActions);
  Result.ActionList := FActions;
  Result.Caption := ACaption;
  Result.ImageIndex := Ord(AIcon);
  Result.ShortCut := AShortCut;
  Result.Tag := ATag;
  Result.OnExecute := AHandler;
  SetActionHint(Result);
end;

function TCommandSet.AddMenuItem(Parent: TMenuItem; AAction: TAction): TMenuItem;
begin
  Result := TMenuItem.Create(Parent);
  Result.Action := AAction;
  Parent.Add(Result);
end;

procedure TCommandSet.AddButton(AAction: TAction);
var
  Button: TToolButton;
begin
  Button := TToolButton.Create(FBar);
  Button.Parent := FBar;
  Button.Action := AAction;
end;

procedure TCommandSet.AddDivider;
begin
  AddToolDivider(FBar);
end;

end.
