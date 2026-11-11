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

// The role visibility panel: which line roles the drafting canvas shows, with
// show all, hide all, solo and the user's presets. It changes the view only,
// never the pattern (see Visibility, styles and output in the design).
unit Sloper.UI.RolesPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs, Sloper.Core.Draft, Sloper.Core.Settings,
  Sloper.Document.PatternDocument;

type
  TRolesMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TRolesPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FChecks: array[TEdgeRole] of TCheckBox;
    FPresetBox: TComboBox;
    FPresetGroup: TGroupBox;
    FPresets: TRolePresetArray;
    FRefreshing: boolean;
    FViewGroup: TGroupBox;
    FOnMessage: TRolesMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Refresh;
    procedure RefreshPresets;
    procedure SetHidden(Roles: TEdgeRoles);
    procedure CheckClick(Sender: TObject);
    procedure SoloClick(Sender: TObject);
    procedure ShowAllClick(Sender: TObject);
    procedure HideAllClick(Sender: TObject);
    procedure PresetChange(Sender: TObject);
    procedure SavePresetClick(Sender: TObject);
    procedure DeletePresetClick(Sender: TObject);
    procedure SwatchPaint(Sender: TObject);
    procedure StorePresets;
    function AddButton(AParent: TWinControl; const ACaption, AHint: string; AHandler: TNotifyEvent): TButton;
    procedure Say(const AText: string);
    procedure Build;
  protected
    procedure SetParent(NewParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // The user's presets, from the settings; saving one writes them back
    procedure SetPresets(const Presets: TRolePresetArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TRolesMessageEvent read FOnMessage write FOnMessage;
  end;

resourcestring
  rsRolesShowAll = 'Show All';
  rsRolesShowAllHint = 'Show every kind of line';
  rsRolesHideAll = 'Hide All';
  rsRolesHideAllHint = 'Hide every kind of line but outlines';
  rsRolesSolo = 'Solo';
  rsRolesSoloHint = 'Show only this kind of line, besides outlines';
  rsRolesPresets = 'Presets';
  rsRolesNoPreset = '(choose a preset)';
  rsRolesSavePreset = 'Save As…';
  rsRolesSavePresetHint = 'Save which lines are hidden as a preset';
  rsRolesDeletePreset = 'Delete';
  rsRolesDeletePresetHint = 'Delete the chosen preset';
  rsRolesPresetTitle = 'Save preset';
  rsRolesPresetPrompt = 'Preset name';
  rsRolesPresetSaved = 'Saved the preset %s';
  rsRolesPresetNotSaved = 'The preset could not be saved: %s';
  rsRolesOutlineNote = 'Outlines always show, as pieces are made from them. Hidden lines still print.';
  rsRoleViewGroup = 'Line Filter Views';

implementation

uses
  Math, Sloper.UI.Properties;

const
  GAP = 6;
  SWATCH_WIDTH = 68;
  ROW_HEIGHT96 = 30;

constructor TRolesPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  BorderSpacing.Around := GAP;
end;

// Once on a form, as sizes scale with the screen
procedure TRolesPanel.SetParent(NewParent: TWinControl);
begin
  inherited SetParent(NewParent);
  if Assigned(NewParent) and not Assigned(FPresetBox) then
    Build;
end;

procedure TRolesPanel.Build;
var
  Role: TEdgeRole;
  Row, Buttons: TPanel;
  Swatch: TPaintBox;
  Solo: TButton;
  Note: TLabel;
begin
  FViewGroup := TGroupBox.Create(Self);
  FViewGroup.Parent := Self;
  FViewGroup.Align := alTop;
  FViewGroup.Caption := rsRoleViewGroup;
  FViewGroup.AutoSize := True;
  FViewGroup.ChildSizing.TopBottomSpacing := 8;

  for Role := High(TEdgeRole) downto Low(TEdgeRole) do
  begin
    if not (Role in HIDEABLE_ROLES) then
      Continue;
    Row := TPanel.Create(Self);
    Row.Parent := FViewGroup;
    Row.Align := alTop;
    Row.BevelOuter := bvNone;
    Row.Height := Scale96ToForm(ROW_HEIGHT96);
    Solo := AddButton(Row, rsRolesSolo, rsRolesSoloHint, @SoloClick);
    Solo.Align := alRight;
    Solo.Tag := Ord(Role);
    Swatch := TPaintBox.Create(Self);
    Swatch.Parent := Row;
    Swatch.Align := alLeft;
    Swatch.Width := Scale96ToForm(SWATCH_WIDTH);
    Swatch.Tag := Ord(Role);
    Swatch.OnPaint := @SwatchPaint;
    FChecks[Role] := TCheckBox.Create(Self);
    FChecks[Role].Parent := Row;
    FChecks[Role].Align := alClient;
    FChecks[Role].BorderSpacing.Left := GAP;
    FChecks[Role].Caption := RoleCaption(Role);
    FChecks[Role].Tag := Ord(Role);
    FChecks[Role].OnClick := @CheckClick;
  end;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FViewGroup;
  Buttons.Align := alTop;
  Buttons.BorderSpacing.Top := 8;
  Buttons.Top := 10000;
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  AddButton(Buttons, rsRolesHideAll, rsRolesHideAllHint, @HideAllClick).Align := alLeft;
  AddButton(Buttons, rsRolesShowAll, rsRolesShowAllHint, @ShowAllClick).Align := alLeft;
  Note := TLabel.Create(FViewGroup);
  Note.Parent := FViewGroup;
  Note.Align := alTop;
  Note.Top := 10001;
  Note.BorderSpacing.Top := 8;
  Note.WordWrap := True;
  Note.Caption := rsRolesOutlineNote;
  FPresetGroup := TGroupBox.Create(Self);
  FPresetGroup.Parent := Self;
  FPresetGroup.Align := alTop;
  FPresetGroup.BorderSpacing.Top := 8;
  FPresetGroup.Top := 10002;
  FPresetGroup.Caption := rsRolesPresets;
  FPresetGroup.ChildSizing.TopBottomSpacing := 8;

  FPresetBox := TComboBox.Create(Self);
  FPresetBox.Parent := FPresetGroup;
  FPresetBox.Align := alTop;
  FPresetBox.Top := 10003;
  FPresetBox.Style := csDropDownList;
  FPresetBox.OnChange := @PresetChange;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FPresetGroup;
  Buttons.Align := alTop;
  Buttons.Top := 10004;
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  AddButton(Buttons, rsRolesDeletePreset, rsRolesDeletePresetHint, @DeletePresetClick).Align := alLeft;
  AddButton(Buttons, rsRolesSavePreset, rsRolesSavePresetHint, @SavePresetClick).Align := alLeft;
  RefreshPresets;
  Refresh;
end;

destructor TRolesPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

function TRolesPanel.AddButton(AParent: TWinControl; const ACaption, AHint: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.AutoSize := True;
  Result.BorderSpacing.Right := GAP;
  Result.OnClick := AHandler;
end;

procedure TRolesPanel.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if Assigned(FDocument) then
    FDocument.AddListener(@DocumentChanged);
  Refresh;
end;

procedure TRolesPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TRolesPanel.Refresh;
var
  Role: TEdgeRole;
  Index: integer;
begin
  FRefreshing := True;
  try
    for Role := Low(TEdgeRole) to High(TEdgeRole) do
      if Assigned(FChecks[Role]) then
      begin
        FChecks[Role].Enabled := Assigned(FDocument);
        FChecks[Role].Checked := not Assigned(FDocument) or not (Role in FDocument.Pattern.View.HiddenRoles);
      end;
    // The preset that matches what is hidden, so choosing one again works
    // after a change
    if Assigned(FPresetBox) and Assigned(FDocument) then
    begin
      FPresetBox.ItemIndex := 0;
      for Index := 0 to High(FPresets) do
        if FPresets[Index].Hidden = FDocument.Pattern.View.HiddenRoles then
        begin
          FPresetBox.ItemIndex := Index + 1;
          Break;
        end;
    end;
  finally
    FRefreshing := False;
  end;
end;

procedure TRolesPanel.RefreshPresets;
var
  Preset: TRolePreset;
begin
  if not Assigned(FPresetBox) then
    Exit;
  FPresetBox.Items.Clear;
  FPresetBox.Items.Add(rsRolesNoPreset);
  for Preset in FPresets do
    FPresetBox.Items.Add(Preset.Name);
  FPresetBox.ItemIndex := 0;
end;

procedure TRolesPanel.SetPresets(const Presets: TRolePresetArray);
begin
  FPresets := Presets;
  RefreshPresets;
end;

// View state only: not an undo step, and the pattern is not modified
procedure TRolesPanel.SetHidden(Roles: TEdgeRoles);
begin
  if not Assigned(FDocument) then
    Exit;
  FDocument.Pattern.View.HiddenRoles := Roles * HIDEABLE_ROLES;
  FDocument.ViewChanged;
end;

procedure TRolesPanel.CheckClick(Sender: TObject);
var
  Role: TEdgeRole;
  Hidden: TEdgeRoles;
begin
  if FRefreshing or not Assigned(FDocument) then
    Exit;
  Role := TEdgeRole(TCheckBox(Sender).Tag);
  Hidden := FDocument.Pattern.View.HiddenRoles;
  if TCheckBox(Sender).Checked then
    Exclude(Hidden, Role)
  else
    Include(Hidden, Role);
  SetHidden(Hidden);
end;

procedure TRolesPanel.SoloClick(Sender: TObject);
begin
  SetHidden(HIDEABLE_ROLES - [TEdgeRole(TComponent(Sender).Tag)]);
end;

procedure TRolesPanel.ShowAllClick(Sender: TObject);
begin
  SetHidden([]);
end;

procedure TRolesPanel.HideAllClick(Sender: TObject);
begin
  SetHidden(HIDEABLE_ROLES);
end;

procedure TRolesPanel.PresetChange(Sender: TObject);
begin
  if FPresetBox.ItemIndex > 0 then
    SetHidden(FPresets[FPresetBox.ItemIndex - 1].Hidden);
end;

procedure TRolesPanel.SavePresetClick(Sender: TObject);
var
  Preset: TRolePreset;
begin
  if not Assigned(FDocument) then
    Exit;
  Preset.Name := '';
  if FPresetBox.ItemIndex > 0 then
    Preset.Name := FPresetBox.Items[FPresetBox.ItemIndex];
  if not InputQuery(rsRolesPresetTitle, rsRolesPresetPrompt, Preset.Name) or (Trim(Preset.Name) = '') then
    Exit;
  Preset.Name := Trim(Preset.Name);
  Preset.Hidden := FDocument.Pattern.View.HiddenRoles;
  PutRolePreset(FPresets, Preset);
  StorePresets;
  RefreshPresets;
  FPresetBox.ItemIndex := FPresetBox.Items.IndexOf(Preset.Name);
  Say(Format(rsRolesPresetSaved, [Preset.Name]));
end;

procedure TRolesPanel.DeletePresetClick(Sender: TObject);
begin
  if FPresetBox.ItemIndex <= 0 then
    Exit;
  RemoveRolePreset(FPresets, FPresetBox.Items[FPresetBox.ItemIndex]);
  StorePresets;
  RefreshPresets;
end;

procedure TRolesPanel.StorePresets;
var
  Reason: string;
begin
  if not SaveUserRolePresets(FPresets, Reason) then
    Say(Format(rsRolesPresetNotSaved, [Reason]));
end;

// The role's colour and dashes, as the canvas draws it
procedure TRolesPanel.SwatchPaint(Sender: TObject);
var
  Box: TPaintBox;
  Role: TEdgeRole;
  Middle: integer;
begin
  Box := TPaintBox(Sender);
  Box.Canvas.Brush.Color := clWhite; // Or any TColor like clSilver, clBtnFace, etc.

  // Fill the entire paintbox area
  Box.Canvas.FillRect(Box.ClientRect);
  Role := TEdgeRole(Box.Tag);
  Middle := Box.Height div 2;
  if ROLE_COLORS[Role] = '' then
    Box.Canvas.Pen.Color := clGray
  else
    Box.Canvas.Pen.Color := RGBToColor(StrToInt('$' + Copy(ROLE_COLORS[Role], 2, 2)), StrToInt('$' + Copy(ROLE_COLORS[Role], 4, 2)),
      StrToInt('$' + Copy(ROLE_COLORS[Role], 6, 2)));
  Box.Canvas.Pen.Width := Max(1, Scale96ToForm(2) * 2);
  if (Role = erConstruction) or (ROLE_DASHES[Role][0] > 0) then
  begin
    Box.Canvas.Pen.Width := 4;
    Box.Canvas.Pen.Style := psDash;
  end
  else
    Box.Canvas.Pen.Style := psSolid;
  Box.Canvas.Line(4, Middle, Box.Width - 4, Middle);
end;

procedure TRolesPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

end.
