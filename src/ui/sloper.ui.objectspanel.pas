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

// The objects panel: a searchable, filterable list of the pattern's objects
// beside the canvas. It follows the canvas selection and sets it. Rows are
// held by key, since undo and redo replace the pattern's objects. The grid
// always has a current row, even with nothing selected, so the panel keeps
// the selection itself and paints it.
unit Sloper.UI.ObjectsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Graphics, LCLType, Types, Sloper.Document.PatternDocument, Sloper.UI.ObjectList;

type
  TObjectsPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FSearch: TEdit;
    FFilter: TComboBox;
    FGrid: TStringGrid;
    FRows: TObjectRowArray;
    FSelected: TStringArray;
    FAnchor: string;
    // Moving the grid's current row in code must not read as a user's choice
    FUpdating: boolean;
    FClicking: boolean;
    FOnSelect: TNotifyEvent;
    FOnZoom: TNotifyEvent;
    FOnDelete: TNotifyEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure FilterChange(Sender: TObject);
    procedure Refresh;
    function IsSelected(const Key: string): boolean;
    function VisibleKeys: TStringArray;
    procedure ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridDoubleClick(Sender: TObject);
    procedure GridSelection(Sender: TObject; ACol, ARow: integer);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Follows the canvas; does not raise OnSelect
    procedure ShowSelection(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    // Keys of the selected objects
    property Selection: TStringArray read FSelected;
    // The user chose objects in the list
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    // The user double-clicked an object
    property OnZoom: TNotifyEvent read FOnZoom write FOnZoom;
    // The user pressed Delete in the list
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
  end;

resourcestring
  rsObjectsSearch = 'Search names and formulas';
  rsObjectsAll = 'All objects';
  rsObjectsPoints = 'Points';
  rsObjectsEdges = 'Edges';
  rsObjectsProblems = 'Problems';
  rsColumnName = 'Name';
  rsColumnOperation = 'Operation';
  rsColumnValue = 'Value';
  rsColumnState = 'State';
  rsColumnFormulas = 'Formulas';

implementation

uses
  Sloper.Core.EvalTypes;

const
  ColumnName = 0;
  ColumnOperation = 1;
  ColumnValue = 2;
  ColumnState = 3;
  ColumnFormulas = 4;
  ProblemInk = TColor($2020C0);
  BlockedInk = TColor($0080E0);

constructor TObjectsPanel.Create(AOwner: TComponent);
var
  Header: TPanel;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.BevelOuter := bvNone;
  Header.AutoSize := True;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := Header;
  FSearch.Align := alTop;
  FSearch.TextHint := rsObjectsSearch;
  FSearch.OnChange := @FilterChange;
  FFilter := TComboBox.Create(Self);
  FFilter.Parent := Header;
  FFilter.Align := alTop;
  FFilter.Top := FSearch.Height;
  FFilter.Style := csDropDownList;
  // In the order of TObjectFilter
  FFilter.Items.Add(rsObjectsAll);
  FFilter.Items.Add(rsObjectsPoints);
  FFilter.Items.Add(rsObjectsEdges);
  FFilter.Items.Add(rsObjectsProblems);
  FFilter.ItemIndex := Ord(ofAll);
  FFilter.OnChange := @FilterChange;
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.RowCount := 1;
  FGrid.FixedRows := 1;
  FGrid.ColCount := ColumnFormulas + 1;
  FGrid.Options := [goFixedVertLine, goFixedHorzLine, goColSizing, goRowSelect, goThumbTracking];
  FGrid.FocusRectVisible := False;
  FGrid.Cells[ColumnName, 0] := rsColumnName;
  FGrid.Cells[ColumnOperation, 0] := rsColumnOperation;
  FGrid.Cells[ColumnValue, 0] := rsColumnValue;
  FGrid.Cells[ColumnState, 0] := rsColumnState;
  FGrid.Cells[ColumnFormulas, 0] := rsColumnFormulas;
  FGrid.ColWidths[ColumnName] := ScaleX(110, 96);
  FGrid.ColWidths[ColumnOperation] := ScaleX(150, 96);
  FGrid.ColWidths[ColumnValue] := ScaleX(110, 96);
  FGrid.ColWidths[ColumnState] := ScaleX(60, 96);
  FGrid.ColWidths[ColumnFormulas] := ScaleX(240, 96);
  FGrid.OnMouseDown := @GridMouseDown;
  FGrid.OnMouseUp := @GridMouseUp;
  FGrid.OnDblClick := @GridDoubleClick;
  FGrid.OnSelection := @GridSelection;
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
  FGrid.OnKeyDown := @GridKeyDown;
end;

destructor TObjectsPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TObjectsPanel.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if FDocument <> nil then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if FDocument <> nil then
    FDocument.AddListener(@DocumentChanged);
  if not (csDestroying in ComponentState) then
    Refresh;
end;

procedure TObjectsPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if Changes * [dcPattern, dcObjectsReplaced, dcMeasurements] <> [] then
    Refresh;
end;

procedure TObjectsPanel.FilterChange(Sender: TObject);
begin
  Refresh;
end;

procedure TObjectsPanel.Refresh;
var
  Index: integer;
begin
  if FDocument = nil then
    FRows := nil
  else
    FRows := ObjectRows(FDocument.Pattern, TObjectFilter(FFilter.ItemIndex), FSearch.Text);
  FUpdating := True;
  try
    FGrid.BeginUpdate;
    try
      FGrid.RowCount := Length(FRows) + 1;
      for Index := 0 to High(FRows) do
      begin
        FGrid.Cells[ColumnName, Index + 1] := FRows[Index].Name;
        FGrid.Cells[ColumnOperation, Index + 1] := FRows[Index].Operation;
        FGrid.Cells[ColumnValue, Index + 1] := FRows[Index].Value;
        FGrid.Cells[ColumnState, Index + 1] := FRows[Index].StateText;
        FGrid.Cells[ColumnFormulas, Index + 1] := FRows[Index].Formulas;
      end;
    finally
      FGrid.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
end;

function TObjectsPanel.IsSelected(const Key: string): boolean;
var
  Selected: string;
begin
  for Selected in FSelected do
    if Selected = Key then
      Exit(True);
  Result := False;
end;

function TObjectsPanel.VisibleKeys: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FRows));
  for Index := 0 to High(FRows) do
    Result[Index] := FRows[Index].Key;
end;

procedure TObjectsPanel.ShowSelection(const Keys: TStringArray);
var
  Index: integer;
begin
  FSelected := Keys;
  if Length(Keys) = 1 then
    FAnchor := Keys[0];
  FUpdating := True;
  try
    if Keys <> nil then
      for Index := 0 to High(FRows) do
        if FRows[Index].Key = Keys[High(Keys)] then
        begin
          FGrid.Row := Index + 1;
          Break;
        end;
  finally
    FUpdating := False;
  end;
  FGrid.Invalidate;
end;

// RowIndex is a grid row: 0 is the heading
procedure TObjectsPanel.ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
var
  Key: string;
begin
  if (RowIndex < 1) or (RowIndex > Length(FRows)) then
    Exit;
  Key := FRows[RowIndex - 1].Key;
  FSelected := SelectionAfterClick(VisibleKeys, FSelected, FAnchor, Key, Toggle, Extend);
  if not Extend then
    FAnchor := Key;
  FGrid.Invalidate;
  if Assigned(FOnSelect) then
    FOnSelect(Self);
end;

procedure TObjectsPanel.GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Cell: TPoint;
begin
  if Button <> mbLeft then
    Exit;
  FClicking := True;
  // The second press of a double-click must leave the selection for OnDblClick
  if ssDouble in Shift then
    Exit;
  Cell := FGrid.MouseToCell(Point(X, Y));
  ChooseRow(Cell.Y, ssModifier in Shift, ssShift in Shift);
end;

procedure TObjectsPanel.GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  FClicking := False;
end;

procedure TObjectsPanel.GridDoubleClick(Sender: TObject);
begin
  if (FSelected <> nil) and Assigned(FOnZoom) then
    FOnZoom(Self);
end;

// The arrow keys; clicks are handled on the way down
procedure TObjectsPanel.GridSelection(Sender: TObject; ACol, ARow: integer);
begin
  if not FUpdating and not FClicking then
    ChooseRow(ARow, False, False);
end;

procedure TObjectsPanel.GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key in [VK_DELETE, VK_BACK]) and Assigned(FOnDelete) then
  begin
    FOnDelete(Self);
    Key := 0;
  end;
end;

procedure TObjectsPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Row: TObjectRow;
begin
  if (ARow < 1) or (ARow > Length(FRows)) then
    Exit;
  Row := FRows[ARow - 1];
  if IsSelected(Row.Key) then
  begin
    FGrid.Canvas.Brush.Color := clHighlight;
    FGrid.Canvas.Font.Color := clHighlightText;
    Exit;
  end;
  FGrid.Canvas.Brush.Color := FGrid.Color;
  if Row.State in [esError, esInvalid] then
    FGrid.Canvas.Font.Color := ProblemInk
  else if Row.State = esBlocked then
    FGrid.Canvas.Font.Color := BlockedInk
  else
    FGrid.Canvas.Font.Color := clWindowText;
end;

end.
