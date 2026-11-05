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

implementation

uses
  SysUtils, Graphics, LCLProc, Sloper.UI.Icons;

const
  ToolIconSize = 24;
  MenuIconSize = 16;
  ButtonPadding = 8;

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
var
  Button: TToolButton;
begin
  Button := TToolButton.Create(FBar);
  Button.Parent := FBar;
  Button.Style := tbsDivider;
end;

end.
