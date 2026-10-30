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

// The list behind the side panel's tabs: a search box over a grid of rows,
// held by key, since undo and redo replace the pattern's objects. The grid
// always has a current row, even with nothing selected, so the panel keeps
// the selection itself and paints it. Each tab says what its rows are.
unit Sloper.UI.ListPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Graphics, LCLType, Types, Sloper.Core.EvalTypes,
  Sloper.Document.PatternDocument;

type
  TListPanelRow = record
    Key: string;
    Cells: TStringArray;
    State: TEvalState;
  end;
  TListPanelRowArray = array of TListPanelRow;

  TListPanelMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TListPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FSearch: TEdit;
    FGrid: TStringGrid;
    FRows: TListPanelRowArray;
    FSelected: TStringArray;
    FAnchor: string;
    FMultiSelect: boolean;
    // Moving the grid's current row in code must not read as a user's choice
    FUpdating: boolean;
    FClicking: boolean;
    FOnSelect: TNotifyEvent;
    FOnZoom: TNotifyEvent;
    FOnDelete: TNotifyEvent;
    FOnMessage: TListPanelMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    function GetSearchText: string;
    function IsSelected(const Key: string): boolean;
    function VisibleKeys: TStringArray;
    procedure ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridDoubleClick(Sender: TObject);
    procedure GridSelection(Sender: TObject; ACol, ARow: integer);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
  protected
    FHeader: TPanel;
    // Column widths are at 96 pixels per inch
    procedure SetColumns(const Captions: array of string; const Widths96: array of integer);
    function BuildRows: TListPanelRowArray; virtual; abstract;
    procedure SearchChange(Sender: TObject);
    procedure Refresh;
    // The user pressed Delete in the list
    procedure DeleteRequested; virtual;
    // The user chose rows; the default raises OnSelect
    procedure SelectionChosen; virtual;
    procedure ShowMessageText(const AText: string);
    property SearchText: string read GetSearchText;
    property MultiSelect: boolean read FMultiSelect write FMultiSelect;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Follows a selection made elsewhere; does not raise OnSelect
    procedure ShowSelection(const Keys: TStringArray);
    // Selects as the user would, raising OnSelect
    procedure ChooseKeys(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    // Keys of the selected rows
    property Selection: TStringArray read FSelected;
    // The user chose rows in the list
    property OnSelect: TNotifyEvent read FOnSelect write FOnSelect;
    // The user double-clicked a row
    property OnZoom: TNotifyEvent read FOnZoom write FOnZoom;
    property OnDelete: TNotifyEvent read FOnDelete write FOnDelete;
    // A hint or the reason something could not be done
    property OnMessage: TListPanelMessageEvent read FOnMessage write FOnMessage;
  end;

resourcestring
  rsListSearch = 'Search';

implementation

uses
  Sloper.UI.ObjectList;

const
  ProblemInk = TColor($2020C0);
  BlockedInk = TColor($0080E0);

constructor TListPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FMultiSelect := True;
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.BevelOuter := bvNone;
  FHeader.AutoSize := True;
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FHeader;
  FSearch.Align := alTop;
  FSearch.TextHint := rsListSearch;
  FSearch.OnChange := @SearchChange;
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.RowCount := 1;
  FGrid.FixedRows := 1;
  FGrid.Options := [goFixedVertLine, goFixedHorzLine, goColSizing, goRowSelect, goThumbTracking];
  FGrid.FocusRectVisible := False;
  FGrid.OnMouseDown := @GridMouseDown;
  FGrid.OnMouseUp := @GridMouseUp;
  FGrid.OnDblClick := @GridDoubleClick;
  FGrid.OnSelection := @GridSelection;
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
  FGrid.OnKeyDown := @GridKeyDown;
end;

destructor TListPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TListPanel.SetColumns(const Captions: array of string; const Widths96: array of integer);
var
  Column: integer;
begin
  FGrid.ColCount := Length(Captions);
  for Column := 0 to High(Captions) do
  begin
    FGrid.Cells[Column, 0] := Captions[Column];
    FGrid.ColWidths[Column] := ScaleX(Widths96[Column], 96);
  end;
end;

function TListPanel.GetSearchText: string;
begin
  Result := FSearch.Text;
end;

procedure TListPanel.SetDocument(ADocument: TPatternDocument);
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

procedure TListPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if Changes * [dcPattern, dcObjectsReplaced, dcMeasurements] <> [] then
    Refresh;
end;

procedure TListPanel.SearchChange(Sender: TObject);
begin
  Refresh;
end;

procedure TListPanel.Refresh;
var
  RowIndex, Column: integer;
begin
  if FDocument = nil then
    FRows := nil
  else
    FRows := BuildRows;
  FUpdating := True;
  try
    FGrid.BeginUpdate;
    try
      FGrid.RowCount := Length(FRows) + 1;
      for RowIndex := 0 to High(FRows) do
        for Column := 0 to High(FRows[RowIndex].Cells) do
          FGrid.Cells[Column, RowIndex + 1] := FRows[RowIndex].Cells[Column];
    finally
      FGrid.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TListPanel.DeleteRequested;
begin
  if Assigned(FOnDelete) then
    FOnDelete(Self);
end;

procedure TListPanel.ShowMessageText(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

function TListPanel.IsSelected(const Key: string): boolean;
var
  Selected: string;
begin
  for Selected in FSelected do
    if Selected = Key then
      Exit(True);
  Result := False;
end;

function TListPanel.VisibleKeys: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FRows));
  for Index := 0 to High(FRows) do
    Result[Index] := FRows[Index].Key;
end;

procedure TListPanel.ShowSelection(const Keys: TStringArray);
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

procedure TListPanel.ChooseKeys(const Keys: TStringArray);
begin
  ShowSelection(Keys);
  SelectionChosen;
end;

procedure TListPanel.SelectionChosen;
begin
  if Assigned(FOnSelect) then
    FOnSelect(Self);
end;

// RowIndex is a grid row: 0 is the heading
procedure TListPanel.ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
var
  Key: string;
begin
  if (RowIndex < 1) or (RowIndex > Length(FRows)) then
    Exit;
  Key := FRows[RowIndex - 1].Key;
  FSelected := SelectionAfterClick(VisibleKeys, FSelected, FAnchor, Key, Toggle and FMultiSelect, Extend and FMultiSelect);
  if not Extend then
    FAnchor := Key;
  FGrid.Invalidate;
  SelectionChosen;
end;

procedure TListPanel.GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
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

procedure TListPanel.GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  FClicking := False;
end;

procedure TListPanel.GridDoubleClick(Sender: TObject);
begin
  if (FSelected <> nil) and Assigned(FOnZoom) then
    FOnZoom(Self);
end;

// The arrow keys; clicks are handled on the way down
procedure TListPanel.GridSelection(Sender: TObject; ACol, ARow: integer);
begin
  if not FUpdating and not FClicking then
    ChooseRow(ARow, False, False);
end;

procedure TListPanel.GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if Key in [VK_DELETE, VK_BACK] then
  begin
    DeleteRequested;
    Key := 0;
  end;
end;

procedure TListPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Row: TListPanelRow;
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
