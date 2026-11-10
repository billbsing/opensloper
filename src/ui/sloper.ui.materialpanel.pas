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

// The pattern's materials, in the side panel, with the cut list they make.
// The list is read-only: colour and fill do not fit in a cell, so materials
// are edited in the Materials dialog, which Edit opens, as does a double-click
// on a row or Edit → Materials.
unit Sloper.UI.MaterialPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Sloper.Document.PatternDocument, Sloper.UI.MaterialGrid;

type
  TMaterialsMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TMaterialsPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FGrid: TMaterialGrid;
    FButtons: TPanel;
    FCutList: TMemo;
    FCutGroup: TGroupBox;
    FOnMessage: TMaterialsMessageEvent;
    FOnEdit: TNotifyEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    function GetMaterialIndex: integer;
    procedure EditClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write SetDocument;
    // The row the dialog should start on, or -1
    property MaterialIndex: integer read GetMaterialIndex;
    property OnMessage: TMaterialsMessageEvent read FOnMessage write FOnMessage;
    // The user wants the Materials dialog
    property OnEdit: TNotifyEvent read FOnEdit write FOnEdit;
  end;

resourcestring
  rsMaterialEdit = '&Edit...';
  rsMaterialEditHint = 'Add, rename, recolour or delete materials';
  rsMaterialCutList = 'Cut List';

implementation

uses
  Sloper.UI.Spacing;

const
  CutListHeight96 = 90;

constructor TMaterialsPanel.Create(AOwner: TComponent);
var
  Button: TButton;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  SpaceChildren(Self);
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  // The bottom row, under the cut list
  FButtons.Top := 2000;
  FButtons.BevelOuter := bvNone;
  FButtons.AutoSize := True;
  SpaceBetween(FButtons);
  Button := TButton.Create(Self);
  Button.Parent := FButtons;
  Button.Align := alLeft;
  Button.AutoSize := True;
  Button.Caption := rsMaterialEdit;
  Button.Hint := rsMaterialEditHint;
  Button.ShowHint := True;
  Button.OnClick := @EditClick;
  FCutGroup := TGroupBox.Create(Self);
  FCutGroup.Parent := Self;
  FCutGroup.Align := alBottom;
  FCutGroup.Top := 1000;
  FCutGroup.AutoSize := True;
  SpaceChildren(FCutGroup);
  FCutGroup.Caption := rsMaterialCutList;
  FCutList := TMemo.Create(Self);
  FCutList.Parent := FCutGroup;
  FCutList.Align := alTop;
  FCutList.Height := Scale96ToScreen(CutListHeight96);
  FCutList.ReadOnly := True;
  FGrid := TMaterialGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.OnDblClick := @EditClick;
end;

destructor TMaterialsPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TMaterialsPanel.SetDocument(ADocument: TPatternDocument);
begin
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if Assigned(FDocument) then
  begin
    FDocument.AddListener(@DocumentChanged);
    Refresh;
  end;
end;

procedure TMaterialsPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TMaterialsPanel.Refresh;
begin
  if not Assigned(FDocument) then
    Exit;
  FGrid.ShowMaterials(FDocument.Pattern);
  FCutList.Text := FDocument.Pattern.CutList;
end;

function TMaterialsPanel.GetMaterialIndex: integer;
begin
  Result := FGrid.MaterialIndex;
end;

procedure TMaterialsPanel.EditClick(Sender: TObject);
begin
  if Assigned(FOnEdit) then
    FOnEdit(Self);
end;

end.
