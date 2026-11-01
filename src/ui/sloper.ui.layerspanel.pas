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

// The layers of the active draft, top first. Showing, locking and soloing a
// layer are view state; the rest are undoable changes to the pattern.
unit Sloper.UI.LayersPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Dialogs, Sloper.Core.Drafts, Sloper.Document.PatternDocument;

type
  TLayersMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TLayersPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FGrid: TStringGrid;
    FButtons: TPanel;
    FRefreshing: boolean;
    FOnMessage: TLayersMessageEvent;
    FOnMoveHere: TNotifyEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    function RowLayer(ARow: integer): TPatternLayer;
    function CurrentLayer: TPatternLayer;
    procedure AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
    procedure GridSelect(Sender: TObject; ACol, ARow: integer);
    procedure GridToggle(Sender: TObject; ACol, ARow: integer; State: TCheckBoxState);
    procedure GridDoubleClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure MoveHereClick(Sender: TObject);
    procedure Say(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TLayersMessageEvent read FOnMessage write FOnMessage;
    // Asks for the selection to go to the active layer
    property OnMoveHere: TNotifyEvent read FOnMoveHere write FOnMoveHere;
  end;

resourcestring
  rsLayerShow = 'Show';
  rsLayerLock = 'Lock';
  rsLayerSolo = 'Solo';
  rsLayerName = 'Layer';
  rsLayerNew = 'New';
  rsLayerNewHint = 'Add a layer above the others';
  rsLayerDelete = 'Delete';
  rsLayerDeleteHint = 'Delete this layer and what is on it';
  rsLayerUp = 'Up';
  rsLayerUpHint = 'Move this layer up the stack';
  rsLayerDown = 'Down';
  rsLayerDownHint = 'Move this layer down the stack';
  rsLayerMoveHere = 'Move selection here';
  rsLayerMoveHereHint = 'Move what is selected to this layer';
  rsLayerAdd = 'Add layer';
  rsLayerRemove = 'Delete layer';
  rsLayerRaise = 'Move layer';
  rsLayerRename = 'Rename layer';
  rsLayerRenameCaption = 'Layer name';
  rsLayerRenamePrompt = 'Name';

implementation

const
  ColumnShow = 0;
  ColumnLock = 1;
  ColumnSolo = 2;
  ColumnName = 3;
  CheckWidth = 52;
  NameWidth = 200;
  ButtonRowHeight = 72;
  ButtonWidth = 66;
  ButtonHeight = 30;
  ButtonGap = 2;
  MoveButtonWidth = 200;
  CheckedText = '1';
  UncheckedText = '0';

constructor TLayersPanel.Create(AOwner: TComponent);

  procedure AddColumn(const ACaption: string; AWidth: integer; IsCheck: boolean);
  var
    Column: TGridColumn;
  begin
    Column := FGrid.Columns.Add;
    Column.Title.Caption := ACaption;
    Column.Width := AWidth;
    if IsCheck then
    begin
      Column.ButtonStyle := cbsCheckboxColumn;
      Column.ValueChecked := CheckedText;
      Column.ValueUnchecked := UncheckedText;
    end
    else
      Column.ReadOnly := True;
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Height := ButtonRowHeight;
  FButtons.BevelOuter := bvNone;
  AddButton(rsLayerNew, rsLayerNewHint, @NewClick);
  AddButton(rsLayerDelete, rsLayerDeleteHint, @DeleteClick);
  AddButton(rsLayerUp, rsLayerUpHint, @UpClick);
  AddButton(rsLayerDown, rsLayerDownHint, @DownClick);
  AddButton(rsLayerMoveHere, rsLayerMoveHereHint, @MoveHereClick);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 1;
  FGrid.Options := FGrid.Options + [goEditing] - [goRangeSelect];
  AddColumn(rsLayerShow, CheckWidth, True);
  AddColumn(rsLayerLock, CheckWidth, True);
  AddColumn(rsLayerSolo, CheckWidth, True);
  AddColumn(rsLayerName, NameWidth, False);
  FGrid.OnSelection := @GridSelect;
  FGrid.OnCheckboxToggled := @GridToggle;
  FGrid.OnDblClick := @GridDoubleClick;
end;

destructor TLayersPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TLayersPanel.AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
var
  Button: TButton;
  Place: integer;
begin
  Place := FButtons.ControlCount;
  Button := TButton.Create(Self);
  Button.Parent := FButtons;
  Button.Caption := ACaption;
  Button.Hint := AHint;
  Button.ShowHint := True;
  Button.OnClick := AHandler;
  Button.Height := ButtonHeight;
  if Place < 4 then
  begin
    Button.Left := Place * (ButtonWidth + ButtonGap) + ButtonGap;
    Button.Top := ButtonGap;
    Button.Width := ButtonWidth;
  end
  else
  begin
    Button.Left := ButtonGap;
    Button.Top := ButtonHeight + 2 * ButtonGap;
    Button.Width := MoveButtonWidth;
  end;
end;

procedure TLayersPanel.SetDocument(ADocument: TPatternDocument);
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

procedure TLayersPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TLayersPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

// Row 1 is the top of the stack
function TLayersPanel.RowLayer(ARow: integer): TPatternLayer;
var
  Layers: TPatternLayerList;
  Index: integer;
begin
  Result := nil;
  Layers := FDocument.Pattern.ActiveDraft.Layers;
  Index := Layers.Count - ARow;
  if (ARow >= 1) and (Index >= 0) then
    Result := Layers[Index];
end;

function TLayersPanel.CurrentLayer: TPatternLayer;
begin
  Result := FDocument.Pattern.ActiveLayer;
end;

procedure TLayersPanel.Refresh;
const
  Marks: array[boolean] of string = (UncheckedText, CheckedText);
var
  Draft: TPatternDraft;
  Row: integer;
  Layer: TPatternLayer;
begin
  if (FDocument = nil) or FRefreshing then
    Exit;
  FRefreshing := True;
  try
    Draft := FDocument.Pattern.ActiveDraft;
    FGrid.RowCount := Draft.Layers.Count + 1;
    for Row := 1 to Draft.Layers.Count do
    begin
      Layer := RowLayer(Row);
      FGrid.Cells[ColumnShow, Row] := Marks[not Layer.Hidden];
      FGrid.Cells[ColumnLock, Row] := Marks[Layer.Locked];
      FGrid.Cells[ColumnSolo, Row] := Marks[FDocument.Pattern.SoloLayer = Layer];
      FGrid.Cells[ColumnName, Row] := Layer.Name;
      if Layer = Draft.ActiveLayer then
        FGrid.Row := Row;
    end;
  finally
    FRefreshing := False;
  end;
end;

procedure TLayersPanel.GridSelect(Sender: TObject; ACol, ARow: integer);
var
  Layer: TPatternLayer;
begin
  if FRefreshing or (FDocument = nil) then
    Exit;
  Layer := RowLayer(ARow);
  if (Layer = nil) or (Layer = CurrentLayer) then
    Exit;
  FDocument.Pattern.SelectLayer(Layer);
  FDocument.ViewChanged;
end;

procedure TLayersPanel.GridToggle(Sender: TObject; ACol, ARow: integer; State: TCheckBoxState);
var
  Layer: TPatternLayer;
begin
  if FRefreshing or (FDocument = nil) then
    Exit;
  Layer := RowLayer(ARow);
  if Layer = nil then
    Exit;
  case ACol of
    ColumnShow: Layer.Hidden := State <> cbChecked;
    ColumnLock: Layer.Locked := State = cbChecked;
    ColumnSolo:
      if State = cbChecked then
        FDocument.Pattern.SoloLayer := Layer
      else
        FDocument.Pattern.SoloLayer := nil;
  end;
  FDocument.ViewChanged;
end;

procedure TLayersPanel.GridDoubleClick(Sender: TObject);
var
  Layer: TPatternLayer;
  NewName, Reason: string;
begin
  if FGrid.Col <> ColumnName then
    Exit;
  Layer := RowLayer(FGrid.Row);
  if Layer = nil then
    Exit;
  NewName := Layer.Name;
  if not InputQuery(rsLayerRenameCaption, rsLayerRenamePrompt, NewName) or (NewName = Layer.Name) then
    Exit;
  FDocument.BeginChange(rsLayerRename);
  Reason := '';
  if not FDocument.Pattern.RenameLayer(FDocument.Pattern.ActiveDraft, Layer, NewName) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TLayersPanel.NewClick(Sender: TObject);
var
  Layer: TPatternLayer;
begin
  FDocument.BeginChange(rsLayerAdd);
  Layer := FDocument.Pattern.AddLayer(FDocument.Pattern.ActiveDraft);
  if Layer <> nil then
    FDocument.Pattern.SelectLayer(Layer);
  FDocument.Commit(Layer <> nil);
end;

procedure TLayersPanel.DeleteClick(Sender: TObject);
var
  Reason: string;
begin
  FDocument.BeginChange(rsLayerRemove);
  Reason := '';
  if not FDocument.Pattern.DeleteLayer(FDocument.Pattern.ActiveDraft, CurrentLayer) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TLayersPanel.UpClick(Sender: TObject);
begin
  FDocument.BeginChange(rsLayerRaise);
  FDocument.Commit(FDocument.Pattern.MoveLayer(FDocument.Pattern.ActiveDraft, CurrentLayer, 1));
end;

procedure TLayersPanel.DownClick(Sender: TObject);
begin
  FDocument.BeginChange(rsLayerRaise);
  FDocument.Commit(FDocument.Pattern.MoveLayer(FDocument.Pattern.ActiveDraft, CurrentLayer, -1));
end;

procedure TLayersPanel.MoveHereClick(Sender: TObject);
begin
  if Assigned(FOnMoveHere) then
    FOnMoveHere(Self);
end;

end.
