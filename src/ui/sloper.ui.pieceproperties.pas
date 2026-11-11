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

// A piece's rows in the properties panel: how many to cut and whether
// mirrored, the fold, edges with their own seam allowance, the grainline,
// and the material and fill.
unit Sloper.UI.PieceProperties;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StdCtrls, Spin, Sloper.Core.Evaluator, Sloper.Core.Materials, Sloper.Core.Piece, Sloper.UI.Properties;

type
  TPieceSection = class(TPropertySection)
  private
    FCutEdit: TSpinEdit;
    FMirrorBox: TCheckBox;
    FFoldBox: TComboBox;
    // The edge of each fold choice; '' for none
    FFoldKeys: TStringArray;
    // Adds an edge's own seam allowance: one choice per edge without one,
    // after the prompt, with the path index of each
    FAllowanceBox: TComboBox;
    FAllowanceIndexes: array of integer;
    // The grainline's kind, in the order of TGrainKind, and its two points
    // when it runs between them: Choose..., then every point by name
    FGrainBox, FGrainStartBox, FGrainEndBox: TComboBox;
    FGrainPointKeys: TStringArray;
    // One choice per material, then none
    FMaterialBox: TComboBox;
    FFillStyleBox: TComboBox;
    // From the material, the piece's own colour if it has one, then choosing one
    FFillColorBox: TComboBox;
    procedure AddRows(Piece: TPieceObject);
    procedure AddGrainRows(Piece: TPieceObject);
    procedure RefreshGrainRows(Piece: TPieceObject);
    procedure RefreshMaterialRows(Piece: TPieceObject);
    procedure CutChange(Sender: TObject);
    procedure FoldChange(Sender: TObject);
    procedure AllowanceChange(Sender: TObject);
    // Added with the piece's allowance, or removed
    procedure AddEdgeAllowance(PathIndex: integer);
    procedure RemoveEdgeAllowance(PathIndex: integer);
    procedure GrainChange(Sender: TObject);
    procedure ChangeGrain(Kind: TGrainKind);
    procedure MaterialChange(Sender: TObject);
    procedure FillStyleChange(Sender: TObject);
    procedure FillColorChange(Sender: TObject);
    procedure ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
    function OwnsField(Node: TEvalNode; const FieldName: string): boolean; override;
    function FieldRowCaption(Node: TEvalNode; const FieldName: string): string; override;
    function TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean; override;
    procedure QueuedChangeDue(Change, Data: integer); override;
  end;

resourcestring
  rsPropCut = 'Cut';
  rsPropMirrored = 'Mirrored';
  rsPropFold = 'Fold';
  rsPropNoFold = 'None';
  rsPropMaterial = 'Material';
  rsPropNoMaterial = 'None';
  rsPropChangeMaterial = 'Change material';
  rsPropFillStyle = 'Fill';
  rsPropFillColor = 'Colour';
  rsPropFromMaterial = 'From material';
  rsPropFillTint = 'Tint';
  rsPropFillHatch = 'Hatching';
  rsPropChooseColor = 'Choose…';
  rsPropChangeFill = 'Change fill';
  rsPropGrainline = 'Grainline';
  rsPropGrainNone = 'None';
  rsPropGrainAngle = 'At an angle';
  rsPropGrainPoints = 'Between two points';
  rsPropGrainFrom = 'Grainline from';
  rsPropGrainTo = 'Grainline to';
  rsPropGrainChoose = 'Choose...';
  rsPropChangeGrainline = 'Change grainline';
  rsPropOwnAllowance = 'Own allowance';
  rsPropOwnAllowancePrompt = 'Add for an edge...';
  rsPropOwnAllowanceHint = 'Give one edge its own seam allowance; empty its row to go back to the piece''s';
  rsPropAddEdgeAllowance = 'Add edge allowance';
  rsPropRemoveEdgeAllowance = 'Remove edge allowance';
  rsPropChangeCut = 'Change cut';
  rsPropChangeFold = 'Change fold';

implementation

uses
  Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.UI.MaterialGrid, Sloper.UI.ObjectList, Sloper.UI.PropertyText;

const
  MAX_CUT_COUNT = 99;
  // The changes that add or remove rows, so they are queued
  QUEUED_ADD_ALLOWANCE = 0;
  QUEUED_REMOVE_ALLOWANCE = 1;
  QUEUED_GRAIN = 2;

procedure TPieceSection.Build(Node: TEvalNode; Place: TSectionPlace);
begin
  if Place = spRows then
    AddRows(TPieceObject(Node));
end;

// Only straight edges can be a fold, so only those are offered
procedure TPieceSection.AddRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Entry: TPieceEdge;
  Edge: TEvalNode;
  Index: integer;
  FoldNames, AllowanceNames: TStringArray;
begin
  Pattern := Panel.Document.Pattern;
  FCutEdit := TSpinEdit.Create(Panel);
  FCutEdit.MinValue := 1;
  FCutEdit.MaxValue := MAX_CUT_COUNT;
  FCutEdit.OnChange := @CutChange;
  Panel.AddRow(rsPropCut, FCutEdit);
  FMirrorBox := TCheckBox.Create(Panel);
  FMirrorBox.OnChange := @CutChange;
  Panel.AddRow(rsPropMirrored, FMirrorBox);
  FoldNames := nil;
  Insert(rsPropNoFold, FoldNames, 0);
  Insert('', FFoldKeys, 0);
  for Entry in Piece.Path do
  begin
    Edge := Pattern.FindNode(Entry.EdgeKey);
    if IsStraightEdge(TEdgeObject(Edge)) then
    begin
      Insert(Edge.DisplayName, FoldNames, Length(FoldNames));
      Insert(Entry.EdgeKey, FFoldKeys, Length(FFoldKeys));
    end;
  end;
  FFoldBox := Panel.AddChoiceRow(rsPropFold, FoldNames, @FoldChange);
  AllowanceNames := nil;
  Insert(rsPropOwnAllowancePrompt, AllowanceNames, 0);
  for Index := 0 to High(Piece.Path) do
    if not Piece.HasOverride(Index) then
    begin
      Insert(Pattern.FindNode(Piece.Path[Index].EdgeKey).DisplayName, AllowanceNames, Length(AllowanceNames));
      Insert(Index, FAllowanceIndexes, Length(FAllowanceIndexes));
    end;
  FAllowanceBox := Panel.AddChoiceRow(rsPropOwnAllowance, AllowanceNames, @AllowanceChange);
  FAllowanceBox.Hint := rsPropOwnAllowanceHint;
  FAllowanceBox.ShowHint := True;
  FAllowanceBox.ItemIndex := 0;
  FAllowanceBox.Enabled := Length(FAllowanceIndexes) > 0;
  AddGrainRows(Piece);
  FMaterialBox := Panel.AddChoiceRow(rsPropMaterial, [], @MaterialChange);
  // In the order of TPieceFillStyle
  FFillStyleBox := Panel.AddChoiceRow(rsPropFillStyle, [rsPropFromMaterial, rsPropFillTint, rsPropFillHatch], @FillStyleChange);
  FFillColorBox := Panel.AddChoiceRow(rsPropFillColor, [], @FillColorChange);
end;

// The grainline's angle goes under the grainline, not with the other fields
function TPieceSection.OwnsField(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := FieldName = GRAIN_ANGLE_FIELD;
end;

// An edge's own allowance is named after its edge, which its field is not
function TPieceSection.FieldRowCaption(Node: TEvalNode; const FieldName: string): string;
begin
  Result := EdgeAllowanceCaption(Panel.Document.Pattern, TPieceObject(Node), FieldName);
end;

// Emptying an edge's own allowance removes it, which takes its row away, so
// it waits until the edit's handler has returned
function TPieceSection.TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean;
var
  PathIndex: integer;
begin
  PathIndex := TPieceObject(Node).OverridePathIndex(FieldName);
  Result := (Trim(AText) = '') and (PathIndex >= 0);
  if Result then
    Panel.QueueChange(Self, QUEUED_REMOVE_ALLOWANCE, PathIndex);
end;

procedure TPieceSection.QueuedChangeDue(Change, Data: integer);
begin
  case Change of
    QUEUED_ADD_ALLOWANCE: AddEdgeAllowance(Data);
    QUEUED_REMOVE_ALLOWANCE: RemoveEdgeAllowance(Data);
    QUEUED_GRAIN: ChangeGrain(TGrainKind(Data));
  end;
end;

procedure TPieceSection.Refresh(Node: TEvalNode);
var
  Piece: TPieceObject;
  Index: integer;
begin
  Piece := TPieceObject(Node);
  // Each row fires its change event, when the others are not yet filled in
  FFilling := True;
  try
    FCutEdit.Value := Piece.CutCount;
    FMirrorBox.Checked := Piece.Mirrored;
    RefreshMaterialRows(Piece);
    RefreshGrainRows(Piece);
  finally
    FFilling := False;
  end;
  for Index := 0 to High(FFoldKeys) do
    if FFoldKeys[Index] = Piece.FoldEdgeKey then
      FFoldBox.ItemIndex := Index;
end;

// The materials can change while the piece stays selected
procedure TPieceSection.RefreshMaterialRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
begin
  Pattern := Panel.Document.Pattern;
  FMaterialBox.Items.Clear;
  for Index := 0 to Pattern.MaterialCount - 1 do
    FMaterialBox.Items.Add(Pattern.Materials[Index].Name);
  FMaterialBox.Items.Add(rsPropNoMaterial);
  FMaterialBox.ItemIndex := Pattern.MaterialCount;
  for Index := 0 to Pattern.MaterialCount - 1 do
    if Pattern.MaterialOf(Piece) = Pattern.Materials[Index] then
      FMaterialBox.ItemIndex := Index;
  FFillStyleBox.ItemIndex := Ord(Piece.FillStyle);
  FFillColorBox.Items.Clear;
  FFillColorBox.Items.Add(rsPropFromMaterial);
  if Piece.FillColor <> '' then
    FFillColorBox.Items.Add(Piece.FillColor);
  FFillColorBox.Items.Add(rsPropChooseColor);
  FFillColorBox.ItemIndex := Ord(Piece.FillColor <> '');
end;

procedure TPieceSection.MaterialChange(Sender: TObject);
var
  Node: TEvalNode;
  Pattern: TPattern;
  Material: TPatternMaterial;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FMaterialBox.ItemIndex < 0) then
    Exit;
  Pattern := Panel.Document.Pattern;
  Material := nil;
  if FMaterialBox.ItemIndex < Pattern.MaterialCount then
    Material := Pattern.Materials[FMaterialBox.ItemIndex];
  Panel.BeginEdit(rsPropChangeMaterial);
  Pattern.SetPieceMaterial(TPieceObject(Node), Material);
  Panel.EndEdit(True);
  Refresh(Panel.SelectedNode);
end;

procedure TPieceSection.ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Panel.BeginEdit(rsPropChangeFill);
  Panel.EndEdit(Panel.Document.Pattern.SetPieceFill(TPieceObject(Node), AColor, Style));
  Refresh(Panel.SelectedNode);
end;

procedure TPieceSection.FillStyleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FFillStyleBox.ItemIndex < 0) then
    Exit;
  ChangePieceFill(TPieceObject(Node).FillColor, TPieceFillStyle(FFillStyleBox.ItemIndex));
end;

procedure TPieceSection.FillColorChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  Chosen: string;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if FFillColorBox.ItemIndex = 0 then
    ChangePieceFill('', Piece.FillStyle)
  else if FFillColorBox.ItemIndex = FFillColorBox.Items.Count - 1 then
  begin
    Chosen := Piece.FillColor;
    if Chosen = '' then
      Chosen := Panel.Document.Pattern.Materials[0].Color;
    if ChooseMaterialColor(Panel, Chosen) then
      ChangePieceFill(Chosen, Piece.FillStyle)
    else
      Refresh(Piece);
  end;
end;

// Runs of spin clicks merge into one undo step
procedure TPieceSection.CutChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
begin
  if FFilling then
    Exit;
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if (Piece.CutCount = FCutEdit.Value) and (Piece.Mirrored = FMirrorBox.Checked) then
    Exit;
  Panel.BeginEdit(rsPropChangeCut);
  Panel.EndEdit(Panel.Document.Pattern.SetCut(Piece, FCutEdit.Value, FMirrorBox.Checked), 'cut:' + Panel.SelectedKey);
end;

procedure TPieceSection.FoldChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) or (TPieceObject(Node).FoldEdgeKey = FFoldKeys[FFoldBox.ItemIndex]) then
    Exit;
  Panel.BeginEdit(rsPropChangeFold);
  Panel.EndEdit(Panel.Document.Pattern.SetFoldEdge(TPieceObject(Node), FFoldKeys[FFoldBox.ItemIndex]));
end;

// Adding a field rebuilds the panel, box and all
procedure TPieceSection.AllowanceChange(Sender: TObject);
begin
  if FAllowanceBox.ItemIndex <= 0 then
    Exit;
  Panel.QueueChange(Self, QUEUED_ADD_ALLOWANCE, FAllowanceIndexes[FAllowanceBox.ItemIndex - 1]);
end;

// Starts at the piece's own allowance, with its row ready to type in. The
// commit rebuilds the panel, which frees this section, so only the panel is
// used after it.
procedure TPieceSection.AddEdgeAllowance(PathIndex: integer);
var
  APanel: TPropertiesPanel;
  Node: TEvalNode;
  Piece: TPieceObject;
begin
  APanel := Panel;
  Node := APanel.SelectedNode;
  if not (Node is TPieceObject) or (PathIndex > High(TPieceObject(Node).Path)) then
    Exit;
  Piece := TPieceObject(Node);
  APanel.Document.BeginChange(rsPropAddEdgeAllowance);
  APanel.Document.Commit(APanel.Document.Pattern.SetEdgeAllowance(Piece, PathIndex, APanel.Document.Pattern.FormulaText(Piece,
    PIECE_ALLOWANCE_FIELD)));
  // The commit may have replaced the piece
  Node := APanel.SelectedNode;
  if Node is TPieceObject then
    APanel.FocusFormulaRow(TPieceObject(Node).OverrideField(PathIndex));
end;

procedure TPieceSection.RemoveEdgeAllowance(PathIndex: integer);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) or (PathIndex > High(TPieceObject(Node).Path)) then
    Exit;
  Panel.Document.BeginChange(rsPropRemoveEdgeAllowance);
  Panel.Document.Commit(Panel.Document.Pattern.SetEdgeAllowance(TPieceObject(Node), PathIndex, ''));
end;

procedure TPieceSection.AddGrainRows(Piece: TPieceObject);
var
  Point: TPointObject;
  Index: integer;
  PointNames: TStringArray;
begin
  // In the order of TGrainKind
  FGrainBox := Panel.AddChoiceRow(rsPropGrainline, [rsPropGrainNone, rsPropGrainAngle, rsPropGrainPoints], @GrainChange);
  for Index := 0 to Piece.FieldCount - 1 do
    if Piece.Fields[Index].Name = GRAIN_ANGLE_FIELD then
      Panel.AddEditRow(FieldCaption(GRAIN_ANGLE_FIELD), frFormula, GRAIN_ANGLE_FIELD);
  PointNames := nil;
  Insert(rsPropGrainChoose, PointNames, 0);
  Insert('', FGrainPointKeys, 0);
  for Point in Panel.Document.Pattern.AllPoints do
  begin
    Insert(Point.DisplayName, PointNames, Length(PointNames));
    Insert(Point.Key, FGrainPointKeys, Length(FGrainPointKeys));
  end;
  FGrainStartBox := Panel.AddChoiceRow(rsPropGrainFrom, PointNames, @GrainChange);
  FGrainEndBox := Panel.AddChoiceRow(rsPropGrainTo, PointNames, @GrainChange);
end;

procedure TPieceSection.RefreshGrainRows(Piece: TPieceObject);

  function PlaceOf(const Key: string): integer;
  begin
    for Result := 0 to High(FGrainPointKeys) do
      if (Key <> '') and (FGrainPointKeys[Result] = Key) then
        Exit;
    Result := 0;
  end;

begin
  FGrainBox.ItemIndex := Ord(Piece.GrainKind);
  if Piece.GrainKind = gkPoints then
  begin
    FGrainStartBox.ItemIndex := PlaceOf(Piece.GrainStartKey);
    FGrainEndBox.ItemIndex := PlaceOf(Piece.GrainEndKey);
  end
  else
  begin
    FGrainStartBox.ItemIndex := 0;
    FGrainEndBox.ItemIndex := 0;
  end;
  FGrainStartBox.Enabled := Piece.GrainKind = gkPoints;
  FGrainEndBox.Enabled := Piece.GrainKind = gkPoints;
end;

// Between two points takes effect once both are chosen. Changing the kind
// adds or removes the angle's row, so the change is queued.
procedure TPieceSection.GrainChange(Sender: TObject);
var
  Points: boolean;
begin
  if FFilling then
    Exit;
  Points := FGrainBox.ItemIndex = Ord(gkPoints);
  FGrainStartBox.Enabled := Points;
  FGrainEndBox.Enabled := Points;
  if Points and ((FGrainStartBox.ItemIndex <= 0) or (FGrainEndBox.ItemIndex <= 0)) then
    Exit;
  Panel.QueueChange(Self, QUEUED_GRAIN, FGrainBox.ItemIndex);
end;

// The commit may rebuild the panel, which frees this section, so only the
// panel is used after it
procedure TPieceSection.ChangeGrain(Kind: TGrainKind);
var
  APanel: TPropertiesPanel;
  Pattern: TPattern;
  Node: TEvalNode;
  Piece: TPieceObject;
  Reason: string;
  Done: boolean;
begin
  APanel := Panel;
  Node := APanel.SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  Pattern := APanel.Document.Pattern;
  APanel.Document.BeginChange(rsPropChangeGrainline);
  case Kind of
    gkNone:
    begin
      Pattern.ClearGrain(Piece);
      Done := True;
    end;
    gkAngle:
      if Piece.GrainKind = gkAngle then
        Done := True
      else
        Done := Pattern.SetGrainAngle(Piece, DEFAULT_GRAIN_ANGLE);
    else
      Done := Pattern.SetGrainPoints(Piece, FGrainPointKeys[FGrainStartBox.ItemIndex], FGrainPointKeys[FGrainEndBox.ItemIndex]);
  end;
  Reason := Pattern.LastError;
  APanel.Document.Commit(Done);
  if not Done then
    APanel.Report(Reason);
end;

end.
