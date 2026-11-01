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

// The tabs under the canvas, one per draft and a + to add one. A double click
// renames, a right click offers Rename and Delete, and dragging reorders.
unit Sloper.UI.DraftBar;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, ComCtrls, Menus, Dialogs, Sloper.Core.Drafts, Sloper.Document.PatternDocument;

type
  TDraftBarMessageEvent = procedure(Sender: TObject; const AText: string) of object;
  TDraftChoiceEvent = procedure(Sender: TObject; Draft: TPatternDraft) of object;

  TDraftBar = class(TTabControl)
  private
    FDocument: TPatternDocument;
    FRefreshing: boolean;
    FPopup: TPopupMenu;
    FMenuDraft: TPatternDraft;
    FPressTab: integer;
    FOnMessage: TDraftBarMessageEvent;
    FOnChoose: TDraftChoiceEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    procedure TabChanged(Sender: TObject);
    procedure TabDoubleClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure AddDraft;
    procedure RenameDraft(Draft: TPatternDraft);
    procedure Say(const AText: string);
    function DraftAt(X, Y: integer): TPatternDraft;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TDraftBarMessageEvent read FOnMessage write FOnMessage;
    // A tab was chosen; the canvas does the switching
    property OnChoose: TDraftChoiceEvent read FOnChoose write FOnChoose;
  end;

resourcestring
  rsDraftAddTab = '+';
  rsDraftAdd = 'Add draft';
  rsDraftRename = 'Rename draft';
  rsDraftDelete = 'Delete draft';
  rsDraftMove = 'Move draft';
  rsDraftRenameMenu = 'Rename...';
  rsDraftDeleteMenu = 'Delete';
  rsDraftRenameCaption = 'Draft name';
  rsDraftRenamePrompt = 'Name';

implementation

const
  BarHeight = 30;

constructor TDraftBar.Create(AOwner: TComponent);
var
  Item: TMenuItem;
begin
  inherited Create(AOwner);
  TabPosition := tpBottom;
  Height := BarHeight;
  FPressTab := -1;
  OnChange := @TabChanged;
  OnDblClick := @TabDoubleClick;
  FPopup := TPopupMenu.Create(Self);
  Item := TMenuItem.Create(FPopup);
  Item.Caption := rsDraftRenameMenu;
  Item.OnClick := @RenameClick;
  FPopup.Items.Add(Item);
  Item := TMenuItem.Create(FPopup);
  Item.Caption := rsDraftDeleteMenu;
  Item.OnClick := @DeleteClick;
  FPopup.Items.Add(Item);
end;

destructor TDraftBar.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TDraftBar.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument <> nil then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if FDocument <> nil then
  begin
    FDocument.AddListener(@DocumentChanged);
    Refresh;
  end;
end;

procedure TDraftBar.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TDraftBar.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

procedure TDraftBar.Refresh;
var
  Index: integer;
begin
  if (FDocument = nil) or FRefreshing then
    Exit;
  FRefreshing := True;
  try
    Tabs.BeginUpdate;
    try
      Tabs.Clear;
      for Index := 0 to FDocument.Pattern.DraftCount - 1 do
        Tabs.Add(FDocument.Pattern.Drafts[Index].Name);
      Tabs.Add(rsDraftAddTab);
    finally
      Tabs.EndUpdate;
    end;
    for Index := 0 to FDocument.Pattern.DraftCount - 1 do
      if FDocument.Pattern.Drafts[Index] = FDocument.Pattern.ActiveDraft then
        TabIndex := Index;
  finally
    FRefreshing := False;
  end;
end;

procedure TDraftBar.TabChanged(Sender: TObject);
begin
  if FRefreshing or (FDocument = nil) then
    Exit;
  if TabIndex = Tabs.Count - 1 then
    AddDraft
  else if Assigned(FOnChoose) then
    FOnChoose(Self, FDocument.Pattern.Drafts[TabIndex]);
end;

procedure TDraftBar.AddDraft;
var
  Draft: TPatternDraft;
  Key: string;
begin
  FDocument.BeginChange(rsDraftAdd);
  Draft := FDocument.Pattern.AddDraft;
  Key := Draft.Key;
  FDocument.EndChange;
  if Assigned(FOnChoose) then
    FOnChoose(Self, FDocument.Pattern.FindDraft(Key));
  Refresh;
end;

function TDraftBar.DraftAt(X, Y: integer): TPatternDraft;
var
  Index: integer;
begin
  Result := nil;
  if FDocument = nil then
    Exit;
  Index := IndexOfTabAt(X, Y);
  if (Index >= 0) and (Index < FDocument.Pattern.DraftCount) then
    Result := FDocument.Pattern.Drafts[Index];
end;

procedure TDraftBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Spot: TPoint;
begin
  inherited MouseDown(Button, Shift, X, Y);
  FPressTab := -1;
  if Button = mbLeft then
    FPressTab := IndexOfTabAt(X, Y)
  else if Button = mbRight then
  begin
    FMenuDraft := DraftAt(X, Y);
    if FMenuDraft <> nil then
    begin
      Spot := ClientToScreen(Point(X, Y));
      FPopup.PopUp(Spot.X, Spot.Y);
    end;
  end;
end;

// Letting go over another tab puts the pressed draft there
procedure TDraftBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Target: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or (FPressTab < 0) or (FDocument = nil) then
    Exit;
  Target := IndexOfTabAt(X, Y);
  if (Target >= 0) and (Target <> FPressTab) and (FPressTab < FDocument.Pattern.DraftCount) and (Target < FDocument.Pattern.DraftCount) then
  begin
    FDocument.BeginChange(rsDraftMove);
    FDocument.Commit(FDocument.Pattern.MoveDraft(FDocument.Pattern.Drafts[FPressTab], Target));
  end;
  FPressTab := -1;
end;

procedure TDraftBar.RenameDraft(Draft: TPatternDraft);
var
  NewName, Reason, Key: string;
begin
  NewName := Draft.Name;
  Key := Draft.Key;
  if not InputQuery(rsDraftRenameCaption, rsDraftRenamePrompt, NewName) or (NewName = Draft.Name) then
    Exit;
  FDocument.BeginChange(rsDraftRename);
  Reason := '';
  if not FDocument.Pattern.RenameDraft(FDocument.Pattern.FindDraft(Key), NewName) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TDraftBar.TabDoubleClick(Sender: TObject);
begin
  if (FDocument <> nil) and (TabIndex >= 0) and (TabIndex < FDocument.Pattern.DraftCount) then
    RenameDraft(FDocument.Pattern.Drafts[TabIndex]);
end;

procedure TDraftBar.RenameClick(Sender: TObject);
begin
  if FMenuDraft <> nil then
    RenameDraft(FMenuDraft);
end;

procedure TDraftBar.DeleteClick(Sender: TObject);
var
  Reason: string;
begin
  if FMenuDraft = nil then
    Exit;
  FDocument.BeginChange(rsDraftDelete);
  Reason := '';
  if not FDocument.Pattern.DeleteDraft(FMenuDraft) then
    Reason := FDocument.Pattern.LastError;
  FMenuDraft := nil;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

end.
