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

// The objects tab of the side panel: every point and edge, searchable and
// filtered by kind, following the canvas selection and setting it.
unit Sloper.UI.ObjectsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Sloper.UI.ListPanel;

type
  TObjectsPanel = class(TListPanel)
  private
    FFilter: TComboBox;
  protected
    function BuildRows: TListPanelRowArray; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

resourcestring
  rsObjectsAll = 'All objects';
  rsObjectsPoints = 'Points';
  rsObjectsEdges = 'Edges';
  rsObjectsPieces = 'Pieces';
  rsObjectsProblems = 'Problems';
  rsColumnName = 'Name';
  rsColumnOperation = 'Operation';
  rsColumnValue = 'Value';
  rsColumnState = 'State';
  rsColumnFormulas = 'Formulas';

implementation

uses
  Sloper.UI.ObjectList;

constructor TObjectsPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFilter := TComboBox.Create(Self);
  FFilter.Parent := FHeader;
  FFilter.Align := alTop;
  FFilter.Top := FHeader.Height;
  FFilter.Style := csDropDownList;
  // In the order of TObjectFilter
  FFilter.Items.Add(rsObjectsAll);
  FFilter.Items.Add(rsObjectsPoints);
  FFilter.Items.Add(rsObjectsEdges);
  FFilter.Items.Add(rsObjectsPieces);
  FFilter.Items.Add(rsObjectsProblems);
  FFilter.ItemIndex := Ord(ofAll);
  FFilter.OnChange := @SearchChange;
  SetColumns([rsColumnName, rsColumnOperation, rsColumnValue, rsColumnState, rsColumnFormulas], [110, 150, 110, 60, 240]);
end;

function TObjectsPanel.BuildRows: TListPanelRowArray;
var
  Rows: TObjectRowArray;
  Index: integer;
begin
  Result := nil;
  Rows := ObjectRows(Document.Pattern, TObjectFilter(FFilter.ItemIndex), SearchText);
  SetLength(Result, Length(Rows));
  for Index := 0 to High(Rows) do
  begin
    Result[Index].Key := Rows[Index].Key;
    Result[Index].State := Rows[Index].State;
    Result[Index].Cells := [Rows[Index].Name, Rows[Index].Operation, Rows[Index].Value, Rows[Index].StateText, Rows[Index].Formulas];
  end;
end;

end.
