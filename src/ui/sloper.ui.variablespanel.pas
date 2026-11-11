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

// The variables tab of the side panel: the pattern's # variables, edited in
// the grid, with Add and Delete. Name, formula and description are editable,
// and each committed cell, add or delete is one undoable change to the pattern.
unit Sloper.UI.VariablesPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Sloper.UI.ListPanel;

type
  TVariablesPanel = class(TListPanel)
  private
    FButtons: TPanel;
    procedure AddClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  protected
    function BuildRows: TListPanelRowArray; override;
    function CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean; override;
    procedure DeleteRequested; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

resourcestring
  rsVariablesAdd = '&Add';
  rsVariablesDelete = '&Delete';
  rsVariablesAddChange = 'Add variable';
  rsVariablesDeleteChange = 'Delete variable';
  rsColumnVariableName = 'Name';
  rsColumnFormula = 'Formula';
  rsColumnVariableValue = 'Value';
  rsColumnDescription = 'Description';

implementation

uses
  Sloper.Core.Evaluator, Sloper.Core.Variables, Sloper.UI.ObjectList, Sloper.UI.PanelEdits, Sloper.UI.Spacing;

const
  NEW_VARIABLE_FORMULA = '0';

constructor TVariablesPanel.Create(AOwner: TComponent);

  procedure AddButton(const ACaption: string; Click: TNotifyEvent);
  var
    Button: TButton;
  begin
    Button := TButton.Create(Self);
    Button.Parent := FButtons;
    Button.Caption := ACaption;
    Button.AutoSize := True;
    Button.Align := alLeft;
    // Docked left to right in the order of their positions
    Button.Left := FButtons.ControlCount * 100;
    Button.OnClick := Click;
  end;

begin
  inherited Create(AOwner);
  MultiSelect := False;
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.BevelOuter := bvNone;
  FButtons.AutoSize := True;
  SpaceBetween(FButtons);
  AddButton(rsVariablesAdd, @AddClick);
  AddButton(rsVariablesDelete, @DeleteClick);
  SetColumns([rsColumnVariableName, rsColumnFormula, rsColumnVariableValue, rsColumnDescription], [110, 150, 70, 200]);
  SetEditableColumns([True, True, False, True], [False, True, False, False]);
end;

function TVariablesPanel.CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean;
var
  ErrorPos: integer;
begin
  Reason := '';
  if not Assigned(Document) or (Column < Ord(Low(TVariableColumn))) or (Column > Ord(High(TVariableColumn))) then
    Exit(False);
  Result := CommitVariableCell(Document, Key, TVariableColumn(Column), AText, Reason, ErrorPos);
end;

function TVariablesPanel.BuildRows: TListPanelRowArray;
var
  Rows: TVariableRowArray;
  Index: integer;
begin
  Result := nil;
  Rows := VariableRows(Document.Pattern, SearchText);
  SetLength(Result, Length(Rows));
  for Index := 0 to High(Rows) do
  begin
    Result[Index].Key := Rows[Index].Key;
    Result[Index].State := Rows[Index].State;
    Result[Index].Cells := [Rows[Index].Name, Rows[Index].Formula, Rows[Index].Value, Rows[Index].Description];
  end;
end;

procedure TVariablesPanel.AddClick(Sender: TObject);
var
  Variable: TVariable;
  Key, Reason: string;
begin
  if not Assigned(Document) then
    Exit;
  FinishEditing;
  Document.BeginChange(rsVariablesAddChange);
  Variable := Document.Pattern.AddVariable(Document.Pattern.NewVariableName, NEW_VARIABLE_FORMULA);
  Reason := Document.Pattern.LastError;
  Key := '';
  if Assigned(Variable) then
    Key := Variable.Key;
  Document.Commit(Assigned(Variable));
  if Key = '' then
  begin
    ShowMessageText(Reason);
    Exit;
  end;
  // The new row is there now, as the panel refreshes on every change
  FocusCell(Key, Ord(vcName), True);
end;

procedure TVariablesPanel.DeleteClick(Sender: TObject);
begin
  DeleteRequested;
end;

procedure TVariablesPanel.DeleteRequested;
var
  Node: TEvalNode;
  Reason: string;
  Done: boolean;
begin
  if not Assigned(Document) or (Length(Selection) = 0) then
    Exit;
  Node := Document.Pattern.FindNode(Selection[0]);
  if not Assigned(Node) then
    Exit;
  Document.BeginChange(rsVariablesDeleteChange);
  Done := Document.Pattern.Delete(Node);
  Reason := Document.Pattern.LastError;
  Document.Commit(Done);
  if Done then
    ChooseKeys(nil)
  else
    ShowMessageText(Reason);
end;

end.
