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

// The pattern's materials, in the side panel, with the cut list they make. Every
// change to them is an undoable change to the pattern.
unit Sloper.UI.MaterialPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Dialogs, Graphics, Sloper.Core.Materials, Sloper.Document.PatternDocument;

type
  TMaterialsMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TMaterialsPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FGrid: TStringGrid;
    FButtons: TPanel;
    FCutList: TMemo;
    FCutGroup: TGroupBox;
    FRefreshing: boolean;
    FOnMessage: TMaterialsMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    function CurrentMaterial: TPatternMaterial;
    procedure AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridDoubleClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ColourClick(Sender: TObject);
    procedure FillClick(Sender: TObject);
    procedure AllowanceClick(Sender: TObject);
    procedure Say(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TMaterialsMessageEvent read FOnMessage write FOnMessage;
  end;

// Asks for a colour, starting from Text; True when one was chosen
function ChooseMaterialColor(Owner: TComponent; var Text: string): boolean;

resourcestring
  rsMaterialColour = 'Colour';
  rsMaterialName = 'Material';
  rsMaterialFill = 'Fill';
  rsMaterialFillTint = 'Tint';
  rsMaterialFillHatch = 'Hatching';
  rsMaterialAllowance = 'Allowance';
  rsMaterialAllowanceButton = 'Allowance...';
  rsMaterialAllowanceHint = 'Set the seam allowance pieces take on this material';
  rsMaterialAllowanceTitle = 'Seam allowance';
  // The pattern's unit, such as cm
  rsMaterialAllowancePrompt = 'In %s, or empty for none';
  rsMaterialAllowanceChange = 'Change material allowance';
  rsMaterialAllowanceBad = 'The allowance must be a number, such as 10 or 3.5';
  rsMaterialNew = 'New';
  rsMaterialNewHint = 'Add a material';
  rsMaterialDelete = 'Delete';
  rsMaterialDeleteHint = 'Delete this material, if no piece is cut from it';
  rsMaterialColourButton = 'Colour…';
  rsMaterialColourHint = 'Choose this material''s colour';
  rsMaterialFillButton = 'Fill';
  rsMaterialFillHint = 'Switch this material between a tint and hatching';
  rsMaterialAdd = 'Add material';
  rsMaterialRemove = 'Delete material';
  rsMaterialRename = 'Rename material';
  rsMaterialRecolour = 'Change material colour';
  rsMaterialChangeFill = 'Change material fill';
  rsMaterialRenameCaption = 'Material name';
  rsMaterialRenamePrompt = 'Name';
  rsMaterialCutList = 'Cut List';

implementation

uses
  Sloper.Core.Units;

const
  ColumnColour = 0;
  ColumnName = 1;
  ColumnFill = 2;
  ColumnAllowance = 3;
  ColourWidth = 64;
  NameWidth = 130;
  FillWidth = 90;
  AllowanceWidth = 90;
  ButtonRowHeight = 36;
  ButtonWidth = 88;
  ButtonHeight = 30;
  ButtonGap = 2;
  CutListHeight = 90;

function ChooseMaterialColor(Owner: TComponent; var Text: string): boolean;
var
  Dialog: TColorDialog;
  Chosen: TMaterialColor;
begin
  Dialog := TColorDialog.Create(Owner);
  try
    Chosen := ParseMaterialColor(Text);
    Dialog.Color := RGBToColor(Chosen.Red, Chosen.Green, Chosen.Blue);
    Result := Dialog.Execute;
    if not Result then
      Exit;
    Chosen.Red := Red(ColorToRGB(Dialog.Color));
    Chosen.Green := Green(ColorToRGB(Dialog.Color));
    Chosen.Blue := Blue(ColorToRGB(Dialog.Color));
    Text := MaterialColorText(Chosen);
  finally
    FreeAndNil(Dialog);
  end;
end;

constructor TMaterialsPanel.Create(AOwner: TComponent);

  procedure AddColumn(const ACaption: string; AWidth: integer);
  var
    Column: TGridColumn;
  begin
    Column := FGrid.Columns.Add;
    Column.Title.Caption := ACaption;
    Column.Width := AWidth;
    Column.ReadOnly := True;
  end;

begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FCutGroup := TGroupBox.Create(Self);
  FCutGroup.Parent := Self;
  FCutGroup.Align := alBottom;
  FCutGroup.AutoSize := True;
  FCutGroup.Caption := rsMaterialCutList;
  FCutList := TMemo.Create(Self);
  FCutList.Parent := FCutGroup;
  FCutList.Align := alTop;
  FCutList.Height := CutListHeight;
  FCutList.ReadOnly := True;
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Height := ButtonRowHeight;
  FButtons.BevelOuter := bvNone;
  AddButton(rsMaterialNew, rsMaterialNewHint, @NewClick);
  AddButton(rsMaterialDelete, rsMaterialDeleteHint, @DeleteClick);
  AddButton(rsMaterialColourButton, rsMaterialColourHint, @ColourClick);
  AddButton(rsMaterialFillButton, rsMaterialFillHint, @FillClick);
  AddButton(rsMaterialAllowanceButton, rsMaterialAllowanceHint, @AllowanceClick);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 1;
  FGrid.Options := FGrid.Options + [goRowSelect] - [goRangeSelect];
  AddColumn(rsMaterialColour, ColourWidth);
  AddColumn(rsMaterialName, NameWidth);
  AddColumn(rsMaterialFill, FillWidth);
  AddColumn(rsMaterialAllowance, AllowanceWidth);
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
  FGrid.OnDblClick := @GridDoubleClick;
end;

destructor TMaterialsPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TMaterialsPanel.AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
var
  Button: TButton;
begin
  Button := TButton.Create(Self);
  Button.Left := FButtons.ControlCount * (ButtonWidth + ButtonGap) + ButtonGap;
  Button.Parent := FButtons;
  Button.Top := ButtonGap;
  Button.Width := ButtonWidth;
  Button.Height := ButtonHeight;
  Button.Caption := ACaption;
  Button.Hint := AHint;
  Button.ShowHint := True;
  Button.OnClick := AHandler;
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

procedure TMaterialsPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

function TMaterialsPanel.CurrentMaterial: TPatternMaterial;
begin
  Result := nil;
  if (FGrid.Row >= 1) and (FGrid.Row <= FDocument.Pattern.MaterialCount) then
    Result := FDocument.Pattern.Materials[FGrid.Row - 1];
end;

procedure TMaterialsPanel.Refresh;
const
  FillCaptions: array[TMaterialFill] of string = (rsMaterialFillTint, rsMaterialFillHatch);
var
  Index: integer;
  Material: TPatternMaterial;
begin
  if not Assigned(FDocument) or FRefreshing then
    Exit;
  FRefreshing := True;
  try
    FGrid.RowCount := FDocument.Pattern.MaterialCount + 1;
    for Index := 0 to FDocument.Pattern.MaterialCount - 1 do
    begin
      Material := FDocument.Pattern.Materials[Index];
      FGrid.Cells[ColumnColour, Index + 1] := Material.Color;
      FGrid.Cells[ColumnName, Index + 1] := Material.Name;
      FGrid.Cells[ColumnFill, Index + 1] := FillCaptions[Material.Fill];
      if Material.HasAllowance then
        FGrid.Cells[ColumnAllowance, Index + 1] := FloatToStr(Material.Allowance)
      else
        FGrid.Cells[ColumnAllowance, Index + 1] := '';
    end;
    FCutList.Text := FDocument.Pattern.CutList;
  finally
    FRefreshing := False;
  end;
  FGrid.Invalidate;
end;

// The colour column shows the colour itself; its text is the same colour, so
// it stays out of the way
procedure TMaterialsPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Material: TMaterialColor;
begin
  if (ACol <> ColumnColour) or (ARow < 1) or not Assigned(FDocument) or (ARow > FDocument.Pattern.MaterialCount) then
    Exit;
  Material := ParseMaterialColor(FDocument.Pattern.Materials[ARow - 1].Color);
  FGrid.Canvas.Brush.Color := RGBToColor(Material.Red, Material.Green, Material.Blue);
  FGrid.Canvas.Font.Color := FGrid.Canvas.Brush.Color;
end;

procedure TMaterialsPanel.GridDoubleClick(Sender: TObject);
var
  Material: TPatternMaterial;
  NewName, Reason: string;
begin
  Material := CurrentMaterial;
  if not Assigned(Material) then
    Exit;
  if FGrid.Col = ColumnColour then
  begin
    ColourClick(Sender);
    Exit;
  end;
  if FGrid.Col = ColumnFill then
  begin
    FillClick(Sender);
    Exit;
  end;
  if FGrid.Col = ColumnAllowance then
  begin
    AllowanceClick(Sender);
    Exit;
  end;
  NewName := Material.Name;
  if not InputQuery(rsMaterialRenameCaption, rsMaterialRenamePrompt, NewName) or (NewName = Material.Name) then
    Exit;
  FDocument.BeginChange(rsMaterialRename);
  Reason := '';
  if not FDocument.Pattern.RenameMaterial(Material, NewName) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TMaterialsPanel.NewClick(Sender: TObject);
var
  Added: boolean;
begin
  FDocument.BeginChange(rsMaterialAdd);
  Added := Assigned(FDocument.Pattern.AddMaterial);
  FDocument.Commit(Added);
  if Added then
    FGrid.Row := FGrid.RowCount - 1;
end;

procedure TMaterialsPanel.DeleteClick(Sender: TObject);
var
  Reason: string;
begin
  if not Assigned(CurrentMaterial) then
    Exit;
  FDocument.BeginChange(rsMaterialRemove);
  Reason := '';
  if not FDocument.Pattern.DeleteMaterial(CurrentMaterial) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TMaterialsPanel.ColourClick(Sender: TObject);
var
  Material: TPatternMaterial;
  Chosen: string;
begin
  Material := CurrentMaterial;
  if not Assigned(Material) then
    Exit;
  Chosen := Material.Color;
  if not ChooseMaterialColor(Self, Chosen) or (Chosen = Material.Color) then
    Exit;
  FDocument.BeginChange(rsMaterialRecolour);
  FDocument.Commit(FDocument.Pattern.SetMaterialColor(Material, Chosen));
end;

procedure TMaterialsPanel.FillClick(Sender: TObject);
const
  Other: array[TMaterialFill] of TMaterialFill = (ffHatch, ffTint);
var
  Material: TPatternMaterial;
begin
  Material := CurrentMaterial;
  if not Assigned(Material) then
    Exit;
  FDocument.BeginChange(rsMaterialChangeFill);
  FDocument.Pattern.SetMaterialFill(Material, Other[Material.Fill]);
  FDocument.EndChange;
end;

procedure TMaterialsPanel.AllowanceClick(Sender: TObject);
var
  Material: TPatternMaterial;
  Entry, Reason: string;
  Value: double;
begin
  Material := CurrentMaterial;
  if not Assigned(Material) then
    Exit;
  Entry := '';
  if Material.HasAllowance then
    Entry := FloatToStr(Material.Allowance);
  if not InputQuery(rsMaterialAllowanceTitle, Format(rsMaterialAllowancePrompt, [MeasureUnitNames[FDocument.Pattern.Units]]), Entry) then
    Exit;
  Entry := Trim(Entry);
  Value := 0;
  if (Entry <> '') and not TryStrToFloat(Entry, Value) then
  begin
    Say(rsMaterialAllowanceBad);
    Exit;
  end;
  FDocument.BeginChange(rsMaterialAllowanceChange);
  Reason := '';
  if not FDocument.Pattern.SetMaterialAllowance(Material, Entry <> '', Value) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

end.
