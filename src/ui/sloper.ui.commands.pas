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
  Classes, Forms, Controls, Menus, ActnList, ComCtrls, Sloper.UI.IconSet, Sloper.Core.Shortcuts;

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

// The key of a command, as Sloper.Core.Shortcuts gives it; 0 when its keys
// are not one key press, such as Arrows
function CommandShortCut(Command: TKeyCommand): TShortCut;
// Keys written as the shortcuts table writes them, such as Mod+Shift+S
function KeysToShortCut(const Keys: string): TShortCut;

implementation

uses
  {$IFDEF LCLQt5}qt5,{$ENDIF}
  {$IFDEF LCLQt6}qt6,{$ENDIF}
  SysUtils, StrUtils, Graphics, LCLProc, LCLType, Sloper.UI.Icons;

const
  TOOL_ICON_SIZE = 24;
  MENU_ICON_SIZE = 16;
  BUTTON_PADDING = 8;
  DIVIDER_SPACE = 11;
  DIVIDER_INSET = 4;
  MENU_DIVIDER_GAP = 4;
  MENU_DIVIDER_INSET = 6;
  // In the order of SHORTCUT_KEY_NAMES
  NAMED_KEYS: array[0..High(SHORTCUT_KEY_NAMES)] of word = (VK_OEM_COMMA, VK_OEM_PLUS, VK_OEM_MINUS, VK_DELETE, VK_ESCAPE,
    VK_RETURN, VK_TAB, VK_SPACE, VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_F2);

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
  Inset := Scale96ToForm(DIVIDER_INSET);
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
    Button.Height := Bar.Scale96ToForm(DIVIDER_SPACE)
  else
    Button.Width := Bar.Scale96ToForm(DIVIDER_SPACE);
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
    [Scale96(MENU_DIVIDER_GAP), Scale96(MENU_DIVIDER_INSET), Red(Color), Green(Color), Blue(Color)]));
  QApplication_setStyleSheet(App, @Sheet);
end;
{$ELSE}

procedure ShowMenuDividers;
begin
end;
{$ENDIF}

function KeysToShortCut(const Keys: string): TShortCut;
var
  KeyName: string;
  Modifiers: TShortcutModifiers;
  Shift: TShiftState;
  Key: word;
begin
  if not ParseShortcut(Keys, KeyName, Modifiers) then
    Exit(0);
  if Length(KeyName) = 1 then
    Key := Ord(KeyName[1])
  else
    Key := NAMED_KEYS[IndexStr(KeyName, SHORTCUT_KEY_NAMES)];
  Shift := [];
  if smMod in Modifiers then
    Include(Shift, ssModifier);
  if smShift in Modifiers then
    Include(Shift, ssShift);
  if smAlt in Modifiers then
    Include(Shift, ssAlt);
  Result := ShortCut(Key, Shift);
end;

function CommandShortCut(Command: TKeyCommand): TShortCut;
begin
  Result := KeysToShortCut(ShortcutInfo(Command).Keys);
end;

procedure SetActionHint(AAction: TAction);
begin
  AAction.Hint := StringReplace(StripHotkey(AAction.Caption), '...', '', []);
end;

constructor TCommandSet.Create(Form: TCustomForm; Menu: TMainMenu);
begin
  inherited Create(Form);
  FToolIcons := CreateIconList(Self, Form.Scale96ToForm(TOOL_ICON_SIZE), clWindowText);
  FDisabledIcons := CreateIconList(Self, Form.Scale96ToForm(TOOL_ICON_SIZE), clGrayText);
  FMenuIcons := CreateIconList(Self, Form.Scale96ToForm(MENU_ICON_SIZE), clMenuText);
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
    FBar.ButtonWidth := FToolIcons.Width + Form.Scale96ToForm(BUTTON_PADDING);
    FBar.ButtonHeight := FToolIcons.Height + Form.Scale96ToForm(BUTTON_PADDING);
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
