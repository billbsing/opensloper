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

// The pattern's fabrics, in the side panel, with the cut list they make. Every
// change to them is an undoable change to the pattern.
unit Sloper.UI.FabricsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Dialogs, Graphics, Sloper.Core.Fabrics, Sloper.Document.PatternDocument;

type
  TFabricsMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TFabricsPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FGrid: TStringGrid;
    FButtons: TPanel;
    FCutList: TMemo;
    FRefreshing: boolean;
    FOnMessage: TFabricsMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    function CurrentFabric: TPatternFabric;
    procedure AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridDoubleClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ColourClick(Sender: TObject);
    procedure FillClick(Sender: TObject);
    procedure Say(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TFabricsMessageEvent read FOnMessage write FOnMessage;
  end;

// Asks for a colour, starting from Text; True when one was chosen
function ChooseFabricColor(Owner: TComponent; var Text: string): boolean;

resourcestring
  rsFabricColour = 'Colour';
  rsFabricName = 'Fabric';
  rsFabricFill = 'Fill';
  rsFabricFillTint = 'Tint';
  rsFabricFillHatch = 'Hatching';
  rsFabricNew = 'New';
  rsFabricNewHint = 'Add a fabric';
  rsFabricDelete = 'Delete';
  rsFabricDeleteHint = 'Delete this fabric, if no piece is cut from it';
  rsFabricColourButton = 'Colour…';
  rsFabricColourHint = 'Choose this fabric''s colour';
  rsFabricFillButton = 'Fill';
  rsFabricFillHint = 'Switch this fabric between a tint and hatching';
  rsFabricAdd = 'Add fabric';
  rsFabricRemove = 'Delete fabric';
  rsFabricRename = 'Rename fabric';
  rsFabricRecolour = 'Change fabric colour';
  rsFabricChangeFill = 'Change fabric fill';
  rsFabricRenameCaption = 'Fabric name';
  rsFabricRenamePrompt = 'Name';

implementation

const
  ColumnColour = 0;
  ColumnName = 1;
  ColumnFill = 2;
  ColourWidth = 64;
  NameWidth = 180;
  FillWidth = 90;
  ButtonRowHeight = 36;
  ButtonWidth = 80;
  ButtonHeight = 30;
  ButtonGap = 2;
  CutListHeight = 90;

function ChooseFabricColor(Owner: TComponent; var Text: string): boolean;
var
  Dialog: TColorDialog;
  Chosen: TFabricColor;
begin
  Dialog := TColorDialog.Create(Owner);
  try
    Chosen := ParseFabricColor(Text);
    Dialog.Color := RGBToColor(Chosen.R, Chosen.G, Chosen.B);
    Result := Dialog.Execute;
    if not Result then
      Exit;
    Chosen.R := Red(ColorToRGB(Dialog.Color));
    Chosen.G := Green(ColorToRGB(Dialog.Color));
    Chosen.B := Blue(ColorToRGB(Dialog.Color));
    Text := FabricColorText(Chosen);
  finally
    FreeAndNil(Dialog);
  end;
end;

constructor TFabricsPanel.Create(AOwner: TComponent);

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
  FCutList := TMemo.Create(Self);
  FCutList.Parent := Self;
  FCutList.Align := alBottom;
  FCutList.Height := CutListHeight;
  FCutList.ReadOnly := True;
  FButtons := TPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alBottom;
  FButtons.Height := ButtonRowHeight;
  FButtons.BevelOuter := bvNone;
  AddButton(rsFabricNew, rsFabricNewHint, @NewClick);
  AddButton(rsFabricDelete, rsFabricDeleteHint, @DeleteClick);
  AddButton(rsFabricColourButton, rsFabricColourHint, @ColourClick);
  AddButton(rsFabricFillButton, rsFabricFillHint, @FillClick);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 1;
  FGrid.Options := FGrid.Options + [goRowSelect] - [goRangeSelect];
  AddColumn(rsFabricColour, ColourWidth);
  AddColumn(rsFabricName, NameWidth);
  AddColumn(rsFabricFill, FillWidth);
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
  FGrid.OnDblClick := @GridDoubleClick;
end;

destructor TFabricsPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TFabricsPanel.AddButton(const ACaption, AHint: string; AHandler: TNotifyEvent);
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

procedure TFabricsPanel.SetDocument(ADocument: TPatternDocument);
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

procedure TFabricsPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TFabricsPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

function TFabricsPanel.CurrentFabric: TPatternFabric;
begin
  Result := nil;
  if (FGrid.Row >= 1) and (FGrid.Row <= FDocument.Pattern.FabricCount) then
    Result := FDocument.Pattern.Fabrics[FGrid.Row - 1];
end;

procedure TFabricsPanel.Refresh;
const
  FillCaptions: array[TFabricFill] of string = (rsFabricFillTint, rsFabricFillHatch);
var
  Index: integer;
  Fabric: TPatternFabric;
begin
  if (FDocument = nil) or FRefreshing then
    Exit;
  FRefreshing := True;
  try
    FGrid.RowCount := FDocument.Pattern.FabricCount + 1;
    for Index := 0 to FDocument.Pattern.FabricCount - 1 do
    begin
      Fabric := FDocument.Pattern.Fabrics[Index];
      FGrid.Cells[ColumnColour, Index + 1] := Fabric.Color;
      FGrid.Cells[ColumnName, Index + 1] := Fabric.Name;
      FGrid.Cells[ColumnFill, Index + 1] := FillCaptions[Fabric.Fill];
    end;
    FCutList.Text := FDocument.Pattern.CutList;
  finally
    FRefreshing := False;
  end;
  FGrid.Invalidate;
end;

// The colour column shows the colour itself; its text is the same colour, so
// it stays out of the way
procedure TFabricsPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Fabric: TFabricColor;
begin
  if (ACol <> ColumnColour) or (ARow < 1) or (FDocument = nil) or (ARow > FDocument.Pattern.FabricCount) then
    Exit;
  Fabric := ParseFabricColor(FDocument.Pattern.Fabrics[ARow - 1].Color);
  FGrid.Canvas.Brush.Color := RGBToColor(Fabric.R, Fabric.G, Fabric.B);
  FGrid.Canvas.Font.Color := FGrid.Canvas.Brush.Color;
end;

procedure TFabricsPanel.GridDoubleClick(Sender: TObject);
var
  Fabric: TPatternFabric;
  NewName, Reason: string;
begin
  Fabric := CurrentFabric;
  if Fabric = nil then
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
  NewName := Fabric.Name;
  if not InputQuery(rsFabricRenameCaption, rsFabricRenamePrompt, NewName) or (NewName = Fabric.Name) then
    Exit;
  FDocument.BeginChange(rsFabricRename);
  Reason := '';
  if not FDocument.Pattern.RenameFabric(Fabric, NewName) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TFabricsPanel.NewClick(Sender: TObject);
var
  Added: boolean;
begin
  FDocument.BeginChange(rsFabricAdd);
  Added := FDocument.Pattern.AddFabric <> nil;
  FDocument.Commit(Added);
  if Added then
    FGrid.Row := FGrid.RowCount - 1;
end;

procedure TFabricsPanel.DeleteClick(Sender: TObject);
var
  Reason: string;
begin
  if CurrentFabric = nil then
    Exit;
  FDocument.BeginChange(rsFabricRemove);
  Reason := '';
  if not FDocument.Pattern.DeleteFabric(CurrentFabric) then
    Reason := FDocument.Pattern.LastError;
  if not FDocument.Commit(Reason = '') then
    Say(Reason);
end;

procedure TFabricsPanel.ColourClick(Sender: TObject);
var
  Fabric: TPatternFabric;
  Chosen: string;
begin
  Fabric := CurrentFabric;
  if Fabric = nil then
    Exit;
  Chosen := Fabric.Color;
  if not ChooseFabricColor(Self, Chosen) or (Chosen = Fabric.Color) then
    Exit;
  FDocument.BeginChange(rsFabricRecolour);
  FDocument.Commit(FDocument.Pattern.SetFabricColor(Fabric, Chosen));
end;

procedure TFabricsPanel.FillClick(Sender: TObject);
const
  Other: array[TFabricFill] of TFabricFill = (ffHatch, ffTint);
var
  Fabric: TPatternFabric;
begin
  Fabric := CurrentFabric;
  if Fabric = nil then
    Exit;
  FDocument.BeginChange(rsFabricChangeFill);
  FDocument.Pattern.SetFabricFill(Fabric, Other[Fabric.Fill]);
  FDocument.EndChange;
end;

end.
