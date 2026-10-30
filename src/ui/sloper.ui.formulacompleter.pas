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

// The list of suggestions under a formula field. It is a plain control on the
// form rather than a window of its own, so keyboard focus stays in the field,
// and it floats over the panels without being cut off by them. The field keeps
// the keys: it passes them to HandleKey while the list shows.
unit Sloper.UI.FormulaCompleter;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, LCLType, Math, Sloper.Core.Evaluator, Sloper.Core.Pattern, Sloper.UI.Completion;

type
  TFormulaCompleter = class(TComponent)
  private
    FList: TListBox;
    FEdit: TEdit;
    FCompletion: TCompletion;
    FPattern: TPattern;
    FNode: TEvalNode;
    FSetting: boolean;
    procedure CreateList;
    procedure Place;
    procedure Accept;
    procedure ListClick(Sender: TObject);
    function GetVisible: boolean;
  public
    // Looks again at the text around Edit's caret; hides when there is nothing to offer
    procedure Update(AEdit: TEdit; APattern: TPattern; ANode: TEvalNode; Explicit: boolean);
    procedure Hide;
    // True when the list used the key
    function HandleKey(var Key: word): boolean;
    // True while the mouse is on the list, when a field losing focus should stay open
    function HasMouse: boolean;
    property Visible: boolean read GetVisible;
    // The list is changing the field's text
    property Setting: boolean read FSetting;
  end;

implementation

const
  MaxRows = 8;
  MinWidth96 = 220;

procedure TFormulaCompleter.CreateList;
begin
  if FList <> nil then
    Exit;
  FList := TListBox.Create(Self);
  FList.Visible := False;
  FList.TabStop := False;
  FList.Parent := GetParentForm(FEdit);
  FList.OnClick := @ListClick;
end;

// Under the field, or over it when the form has no room below, and inside the form
procedure TFormulaCompleter.Place;
var
  Form: TCustomForm;
  Corner: TPoint;
  ListWidth, ListHeight: integer;
begin
  Form := GetParentForm(FEdit);
  ListWidth := Max(FEdit.Width, FEdit.ScaleDesignToForm(MinWidth96));
  ListHeight := Min(FList.Count, MaxRows) * FList.ItemHeight + 6;
  Corner := Form.ScreenToClient(FEdit.ClientToScreen(Point(0, FEdit.Height)));
  if Corner.Y + ListHeight > Form.ClientHeight then
    Corner.Y := Max(0, Corner.Y - FEdit.Height - ListHeight);
  FList.SetBounds(Max(0, Min(Corner.X, Form.ClientWidth - ListWidth)), Corner.Y, ListWidth, ListHeight);
end;

procedure TFormulaCompleter.Update(AEdit: TEdit; APattern: TPattern; ANode: TEvalNode; Explicit: boolean);
var
  Item: TCompletionItem;
begin
  FEdit := AEdit;
  FPattern := APattern;
  FNode := ANode;
  FCompletion := FormulaCompletion(APattern, ANode, AEdit.Text, AEdit.SelStart, Explicit);
  if FCompletion.Items = nil then
  begin
    Hide;
    Exit;
  end;
  CreateList;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Item in FCompletion.Items do
      if Item.Detail = '' then
        FList.Items.Add(Item.Name)
      else
        FList.Items.Add(Item.Name + '   ' + Item.Detail);
  finally
    FList.Items.EndUpdate;
  end;
  FList.ItemIndex := 0;
  Place;
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TFormulaCompleter.Hide;
begin
  if FList <> nil then
    FList.Visible := False;
end;

function TFormulaCompleter.GetVisible: boolean;
begin
  Result := (FList <> nil) and FList.Visible;
end;

function TFormulaCompleter.HasMouse: boolean;
begin
  Result := Visible and FList.MouseInClient;
end;

procedure TFormulaCompleter.Accept;
var
  NewCaret: integer;
  NewText: string;
begin
  if FList.ItemIndex < 0 then
    Exit;
  NewText := ApplyCompletion(FEdit.Text, FCompletion, FList.ItemIndex, NewCaret);
  // Before the caret is placed: focus coming back to a field selects all of it
  Hide;
  FSetting := True;
  try
    FEdit.Text := NewText;
    FEdit.SelLength := 0;
    FEdit.SelStart := NewCaret;
  finally
    FSetting := False;
  end;
  // After an object's dot its properties are next
  if NewText[NewCaret] = '.' then
    Update(FEdit, FPattern, FNode, False);
end;

procedure TFormulaCompleter.ListClick(Sender: TObject);
begin
  // The click took focus; it comes back first, and that selects all of the field
  FEdit.SetFocus;
  Accept;
end;

function TFormulaCompleter.HandleKey(var Key: word): boolean;
begin
  Result := Visible;
  if not Result then
    Exit;
  case Key of
    VK_UP:
      FList.ItemIndex := Max(FList.ItemIndex - 1, 0);
    VK_DOWN:
      FList.ItemIndex := Min(FList.ItemIndex + 1, FList.Count - 1);
    VK_RETURN, VK_TAB:
      Accept;
    VK_ESCAPE:
      Hide;
    else
      Exit(False);
  end;
  Key := 0;
end;

end.
