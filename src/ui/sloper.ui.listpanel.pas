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

// A tab can make some of its columns editable. Its rows are then edited in the
// grid: typing, F2 or Enter opens the cell, Enter or leaving the cell commits
// it through CommitCell, and Escape puts the text back. A refused value keeps
// its text, with the cell in red and the reason sent to OnMessage, until it is
// committed or Escape is pressed on it. Editable panels select cells rather
// than rows and select one row at a time.
unit Sloper.UI.ListPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Graphics, LCLType, Types, Sloper.Core.EvalTypes,
  Sloper.Document.PatternDocument, Sloper.UI.FormulaCompleter;

type
  TListPanelRow = record
    Key: string;
    Cells: TStringArray;
    State: TEvalState;
    // Drawn in bold, as a row with unsaved edits is
    Marked: boolean;
  end;
  TListPanelRowArray = array of TListPanelRow;

  // A value a tab refused, kept in its cell until it is fixed or dropped
  TListPanelRefusal = record
    Key: string;
    Column: integer;
    Text: string;
  end;
  TListPanelRefusalArray = array of TListPanelRefusal;

  TListPanelMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TListPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FSearch: TEdit;
    FGrid: TStringGrid;
    FCellEditor: TStringCellEditor;
    FRows: TListPanelRowArray;
    FSelected: TStringArray;
    FAnchor: string;
    FMultiSelect: boolean;
    FEditableColumns: array of boolean;
    FFormulaColumns: array of boolean;
    FRefusals: TListPanelRefusalArray;
    FCompleter: TFormulaCompleter;
    // The cell the open editor belongs to, by key, as rows may move
    FEditKey: string;
    FEditColumn: integer;
    FEditOriginal: string;
    // A commit's own change waits to refresh until the grid has closed the cell
    FCommitting: boolean;
    FRefreshQueued: boolean;
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
    function GetEditable: boolean;
    function IsSelected(const Key: string): boolean;
    function VisibleKeys: TStringArray;
    function RowOfKey(const Key: string): integer;
    function RefusalIndex(const Key: string; Column: integer): integer;
    procedure DropRefusal(const Key: string; Column: integer);
    procedure ShowRefusals;
    procedure RefreshQueued(Data: PtrInt);
    procedure ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
    function ColumnIsEditable(Column: integer): boolean;
    function ColumnIsFormula(Column: integer): boolean;
    procedure UpdateCompletion(Explicit: boolean);
    procedure HideCompletion;
    function CompleterKey(var Key: word; Shift: TShiftState): boolean;
    function CompleterHasMouse: boolean;
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridDoubleClick(Sender: TObject);
    procedure GridSelection(Sender: TObject; ACol, ARow: integer);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure GridSelectEditor(Sender: TObject; ACol, ARow: integer; var Editor: TWinControl);
    procedure GridGetEditText(Sender: TObject; ACol, ARow: integer; var Value: string);
    procedure GridValidate(Sender: TObject; ACol, ARow: integer; const OldValue: string; var NewValue: string);
  protected
    FHeader: TPanel;
    // Column widths are at 96 pixels per inch
    procedure SetColumns(const Captions: array of string; const Widths96: array of integer);
    // Turns on editing in the grid. Formula columns offer name completion.
    procedure SetEditableColumns(const Editable, Formula: array of boolean);
    function BuildRows: TListPanelRowArray; virtual; abstract;
    // Whether this row's cell can be edited; the default is its column's setting
    function CellEditable(const Key: string; Column: integer): boolean; virtual;
    // The text the editor starts with; the default is the cell as shown
    function CellEditText(const Key: string; Column: integer; const Shown: string): string; virtual;
    // Makes the edit; False refuses it, with the reason shown to the user
    function CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean; virtual;
    procedure SearchChange(Sender: TObject);
    procedure Refresh;
    // Refreshes once the current event is over, as after a commit that the
    // document is not told about
    procedure QueueRefresh;
    // Drops every refused value, putting the cells back
    procedure ClearRefusals;
    // The user pressed Delete in the list
    procedure DeleteRequested; virtual;
    // The user chose rows; the default raises OnSelect
    procedure SelectionChosen; virtual;
    procedure ShowMessageText(const AText: string);
    // Selects the row and moves to its cell, opening the editor when Edit is set
    procedure FocusCell(const Key: string; Column: integer; Edit: boolean);
    // Closes an open cell editor, committing what it holds
    procedure FinishEditing;
    property SearchText: string read GetSearchText;
    property MultiSelect: boolean read FMultiSelect write FMultiSelect;
    property Editable: boolean read GetEditable;
    property Grid: TStringGrid read FGrid;
    property Refusals: TListPanelRefusalArray read FRefusals;
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
  Forms, Sloper.UI.ObjectList, Sloper.UI.Spacing;

const
  PROBLEM_INK = TColor($2020C0);
  BLOCKED_INK = TColor($0080E0);
  REFUSED_PAPER = TColor($D8D8FF);

type
  // Keeps the cell open while the suggestions under it are clicked
  TListGrid = class(TStringGrid)
  private
    FPanel: TListPanel;
  protected
    procedure DoExit; override;
  end;

  // The cell editor, which gives the suggestions the keys they use first
  TListCellEditor = class(TStringCellEditor)
  private
    FPanel: TListPanel;
    // Enter accepted a suggestion; its key press must not close the cell
    FSwallowReturn: boolean;
    // and its key coming up must not select the whole text
    FSwallowReturnUp: boolean;
  protected
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
    procedure KeyPress(var Key: char); override;
    procedure KeyUp(var Key: word; Shift: TShiftState); override;
    procedure Change; override;
    procedure Click; override;
  end;

procedure TListGrid.DoExit;
begin
  if FPanel.CompleterHasMouse then
    Exit;
  FPanel.HideCompletion;
  inherited DoExit;
end;

procedure TListCellEditor.KeyDown(var Key: word; Shift: TShiftState);
begin
  FSwallowReturn := False;
  FSwallowReturnUp := False;
  if FPanel.CompleterKey(Key, Shift) then
  begin
    FSwallowReturn := True;
    FSwallowReturnUp := True;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TListCellEditor.KeyUp(var Key: word; Shift: TShiftState);
begin
  if FSwallowReturnUp and (Key in [VK_RETURN, VK_TAB]) then
  begin
    FSwallowReturnUp := False;
    Key := 0;
    Exit;
  end;
  inherited KeyUp(Key, Shift);
end;

procedure TListCellEditor.KeyPress(var Key: char);
begin
  if FSwallowReturn and (Key in [#13, #9]) then
  begin
    FSwallowReturn := False;
    Key := #0;
    Exit;
  end;
  inherited KeyPress(Key);
end;

procedure TListCellEditor.Change;
begin
  inherited Change;
  if Visible and Focused then
    FPanel.UpdateCompletion(False);
end;

procedure TListCellEditor.Click;
begin
  inherited Click;
  FPanel.HideCompletion;
end;

constructor TListPanel.Create(AOwner: TComponent);
var
  ListGrid: TListGrid;
  CellEditor: TListCellEditor;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  SpaceChildren(Self);
  FMultiSelect := True;
  FHeader := TPanel.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHeader.BevelOuter := bvNone;
  FHeader.AutoSize := True;
  SpaceBetween(FHeader);
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FHeader;
  FSearch.Align := alTop;
  FSearch.TextHint := rsListSearch;
  FSearch.OnChange := @SearchChange;
  ListGrid := TListGrid.Create(Self);
  ListGrid.FPanel := Self;
  FGrid := ListGrid;
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
  CellEditor := TListCellEditor.Create(Self);
  CellEditor.FPanel := Self;
  CellEditor.Visible := False;
  FCellEditor := CellEditor;
end;

destructor TListPanel.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
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

procedure TListPanel.SetEditableColumns(const Editable, Formula: array of boolean);
var
  Column: integer;
begin
  SetLength(FEditableColumns, Length(Editable));
  for Column := 0 to High(Editable) do
    FEditableColumns[Column] := Editable[Column];
  SetLength(FFormulaColumns, Length(Formula));
  for Column := 0 to High(Formula) do
    FFormulaColumns[Column] := Formula[Column];
  FMultiSelect := False;
  // Row selection and editing do not mix, so the panel paints the row itself
  FGrid.Options := [goFixedVertLine, goFixedHorzLine, goColSizing, goEditing, goThumbTracking];
  FGrid.AutoAdvance := aaNone;
  FGrid.FocusRectVisible := True;
  FGrid.OnSelectEditor := @GridSelectEditor;
  FGrid.OnGetEditText := @GridGetEditText;
  FGrid.OnValidateEntry := @GridValidate;
end;

function TListPanel.GetEditable: boolean;
begin
  Result := Length(FEditableColumns) > 0;
end;

function TListPanel.ColumnIsEditable(Column: integer): boolean;
begin
  Result := (Column >= 0) and (Column < Length(FEditableColumns)) and FEditableColumns[Column];
end;

function TListPanel.ColumnIsFormula(Column: integer): boolean;
begin
  Result := (Column >= 0) and (Column < Length(FFormulaColumns)) and FFormulaColumns[Column];
end;

function TListPanel.CellEditable(const Key: string; Column: integer): boolean;
begin
  Result := ColumnIsEditable(Column);
end;

function TListPanel.CellEditText(const Key: string; Column: integer; const Shown: string): string;
begin
  Result := Shown;
end;

function TListPanel.CommitCell(const Key: string; Column: integer; const AText: string; out Reason: string): boolean;
begin
  Reason := '';
  Result := False;
end;

function TListPanel.GetSearchText: string;
begin
  Result := FSearch.Text;
end;

procedure TListPanel.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  FRefusals := nil;
  if Assigned(FDocument) then
    FDocument.AddListener(@DocumentChanged);
  if not (csDestroying in ComponentState) then
    Refresh;
end;

procedure TListPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  if dcObjectsReplaced in Changes then
    FRefusals := nil;
  if Changes * [dcPattern, dcObjectsReplaced, dcMeasurements] = [] then
    Exit;
  if FCommitting then
    QueueRefresh
  else
    Refresh;
end;

procedure TListPanel.QueueRefresh;
begin
  if FRefreshQueued then
    Exit;
  FRefreshQueued := True;
  Application.QueueAsyncCall(@RefreshQueued, 0);
end;

procedure TListPanel.RefreshQueued(Data: PtrInt);
begin
  FRefreshQueued := False;
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
  if not Assigned(FDocument) then
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
      ShowRefusals;
    finally
      FGrid.EndUpdate;
    end;
  finally
    FUpdating := False;
  end;
end;

// Refused text goes back over the value it would have replaced; a refusal
// whose row has gone is dropped
procedure TListPanel.ShowRefusals;
var
  Index, RowIndex: integer;
begin
  for Index := High(FRefusals) downto 0 do
  begin
    RowIndex := RowOfKey(FRefusals[Index].Key);
    if RowIndex < 0 then
      Delete(FRefusals, Index, 1)
    else
      FGrid.Cells[FRefusals[Index].Column, RowIndex + 1] := FRefusals[Index].Text;
  end;
end;

function TListPanel.RowOfKey(const Key: string): integer;
var
  Index: integer;
begin
  for Index := 0 to High(FRows) do
    if FRows[Index].Key = Key then
      Exit(Index);
  Result := -1;
end;

function TListPanel.RefusalIndex(const Key: string; Column: integer): integer;
var
  Index: integer;
begin
  for Index := 0 to High(FRefusals) do
    if (FRefusals[Index].Key = Key) and (FRefusals[Index].Column = Column) then
      Exit(Index);
  Result := -1;
end;

procedure TListPanel.ClearRefusals;
begin
  FRefusals := nil;
  Refresh;
end;

procedure TListPanel.DropRefusal(const Key: string; Column: integer);
var
  Index: integer;
begin
  Index := RefusalIndex(Key, Column);
  if Index >= 0 then
    Delete(FRefusals, Index, 1);
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
    if Length(Keys) > 0 then
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

procedure TListPanel.FocusCell(const Key: string; Column: integer; Edit: boolean);
var
  RowIndex: integer;
begin
  RowIndex := RowOfKey(Key);
  if RowIndex < 0 then
    Exit;
  ChooseKeys([Key]);
  FUpdating := True;
  try
    FGrid.Col := Column;
    FGrid.Row := RowIndex + 1;
  finally
    FUpdating := False;
  end;
  if FGrid.CanFocus then
    FGrid.SetFocus;
  if Edit and CellEditable(Key, Column) then
    FGrid.EditorMode := True;
end;

procedure TListPanel.FinishEditing;
begin
  if FGrid.EditorMode then
    FGrid.EditorMode := False;
end;

// RowIndex is a grid row: 0 is the heading
procedure TListPanel.ChooseRow(RowIndex: integer; Toggle, Extend: boolean);
var
  Key: string;
begin
  if (RowIndex < 1) or (RowIndex > Length(FRows)) then
    Exit;
  Key := FRows[RowIndex - 1].Key;
  // Moving along a row of an editable list is not a new choice
  if Editable and (Length(FSelected) = 1) and (FSelected[0] = Key) then
    Exit;
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

// An editable cell opens; elsewhere it shows the row's object
procedure TListPanel.GridDoubleClick(Sender: TObject);
begin
  if Editable and (FGrid.Row >= 1) and (FGrid.Row <= Length(FRows)) and CellEditable(FRows[FGrid.Row - 1].Key, FGrid.Col) then
  begin
    FGrid.EditorMode := True;
    Exit;
  end;
  if (Length(FSelected) > 0) and Assigned(FOnZoom) then
    FOnZoom(Self);
end;

// The arrow keys; clicks are handled on the way down
procedure TListPanel.GridSelection(Sender: TObject; ACol, ARow: integer);
begin
  if not FUpdating and not FClicking then
    ChooseRow(ARow, False, False);
end;

// Keys from an open cell editor come here too, and are its own
procedure TListPanel.GridKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Cell: TPoint;
begin
  if FGrid.EditorMode then
    Exit;
  case Key of
    VK_DELETE, VK_BACK:
    begin
      DeleteRequested;
      Key := 0;
    end;
    VK_ESCAPE:
      if Editable and (FGrid.Row >= 1) and (FGrid.Row <= Length(FRows)) then
      begin
        Cell := Point(FGrid.Col, FGrid.Row);
        if RefusalIndex(FRows[Cell.Y - 1].Key, Cell.X) >= 0 then
        begin
          DropRefusal(FRows[Cell.Y - 1].Key, Cell.X);
          FGrid.Cells[Cell.X, Cell.Y] := FRows[Cell.Y - 1].Cells[Cell.X];
          ShowMessageText('');
          Key := 0;
        end;
      end;
    VK_SPACE:
      // Ctrl+Space would otherwise start editing with a space
      if ssModifier in Shift then
        Key := 0;
  end;
end;

procedure TListPanel.GridSelectEditor(Sender: TObject; ACol, ARow: integer; var Editor: TWinControl);
begin
  if (ARow < 1) or (ARow > Length(FRows)) or not CellEditable(FRows[ARow - 1].Key, ACol) then
  begin
    Editor := nil;
    Exit;
  end;
  Editor := FCellEditor;
end;

// Called as the editor opens, so it records which cell is being edited
procedure TListPanel.GridGetEditText(Sender: TObject; ACol, ARow: integer; var Value: string);
var
  Index: integer;
begin
  if (ARow < 1) or (ARow > Length(FRows)) then
    Exit;
  FEditKey := FRows[ARow - 1].Key;
  FEditColumn := ACol;
  FEditOriginal := CellEditText(FEditKey, ACol, FRows[ARow - 1].Cells[ACol]);
  Index := RefusalIndex(FEditKey, ACol);
  if Index >= 0 then
    Value := FRefusals[Index].Text
  else
    Value := FEditOriginal;
end;

// Leaving the cell or pressing Enter. The grid writes NewValue to the cell
// afterwards, so the refresh this commit causes waits until it has.
procedure TListPanel.GridValidate(Sender: TObject; ACol, ARow: integer; const OldValue: string; var NewValue: string);
var
  Key, Reason: string;
  Column, Index: integer;
  Done: boolean;
begin
  HideCompletion;
  if FUpdating or (FEditKey = '') then
    Exit;
  Key := FEditKey;
  Column := FEditColumn;
  FEditKey := '';
  if NewValue = FEditOriginal then
  begin
    if RefusalIndex(Key, Column) >= 0 then
      ShowMessageText('');
    DropRefusal(Key, Column);
    NewValue := OldValue;
    if RowOfKey(Key) >= 0 then
      NewValue := FRows[RowOfKey(Key)].Cells[Column];
    Exit;
  end;
  FCommitting := True;
  try
    Done := CommitCell(Key, Column, NewValue, Reason);
  finally
    FCommitting := False;
  end;
  if Done then
  begin
    if RefusalIndex(Key, Column) >= 0 then
      ShowMessageText('');
    DropRefusal(Key, Column);
  end
  else
  begin
    Index := RefusalIndex(Key, Column);
    if Index < 0 then
    begin
      Index := Length(FRefusals);
      SetLength(FRefusals, Index + 1);
      FRefusals[Index].Key := Key;
      FRefusals[Index].Column := Column;
    end;
    FRefusals[Index].Text := NewValue;
    ShowMessageText(Reason);
  end;
  QueueRefresh;
end;

procedure TListPanel.UpdateCompletion(Explicit: boolean);
begin
  if not Assigned(FDocument) or (FEditKey = '') or not ColumnIsFormula(FEditColumn) then
    Exit;
  if not Assigned(FCompleter) then
    FCompleter := TFormulaCompleter.Create(Self);
  FCompleter.Update(FCellEditor, FDocument.Pattern, FDocument.Pattern.FindNode(FEditKey), Explicit);
end;

procedure TListPanel.HideCompletion;
begin
  if Assigned(FCompleter) then
    FCompleter.Hide;
end;

function TListPanel.CompleterHasMouse: boolean;
begin
  Result := Assigned(FCompleter) and FCompleter.HasMouse;
end;

// Keys in the cell editor go to the suggestions first; Ctrl+Space asks for them
function TListPanel.CompleterKey(var Key: word; Shift: TShiftState): boolean;
begin
  if (Key = VK_SPACE) and (ssModifier in Shift) and ColumnIsFormula(FEditColumn) then
  begin
    UpdateCompletion(True);
    Key := 0;
    Exit(False);
  end;
  Result := Assigned(FCompleter) and FCompleter.HandleKey(Key);
  if not Result and (Key in [VK_LEFT, VK_RIGHT, VK_HOME, VK_END]) then
    HideCompletion;
end;

procedure TListPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Row: TListPanelRow;
begin
  if (ARow < 1) or (ARow > Length(FRows)) then
    Exit;
  Row := FRows[ARow - 1];
  if Row.Marked then
    FGrid.Canvas.Font.Style := [fsBold]
  else
    FGrid.Canvas.Font.Style := [];
  if Editable and (RefusalIndex(Row.Key, ACol) >= 0) then
  begin
    FGrid.Canvas.Brush.Color := REFUSED_PAPER;
    FGrid.Canvas.Font.Color := PROBLEM_INK;
    Exit;
  end;
  // The current cell of an editable row stands out from the rest of it
  if IsSelected(Row.Key) and not (Editable and (ACol <> FGrid.Col)) then
  begin
    FGrid.Canvas.Brush.Color := clHighlight;
    FGrid.Canvas.Font.Color := clHighlightText;
    Exit;
  end;
  if IsSelected(Row.Key) then
    FGrid.Canvas.Brush.Color := clBtnFace
  else
    FGrid.Canvas.Brush.Color := FGrid.Color;
  if Row.State in [esError, esInvalid] then
    FGrid.Canvas.Font.Color := PROBLEM_INK
  else if Row.State = esBlocked then
    FGrid.Canvas.Font.Color := BLOCKED_INK
  else
    FGrid.Canvas.Font.Color := clWindowText;
end;

end.
