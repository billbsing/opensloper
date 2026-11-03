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

// The properties panel: the selected object's name, formulas and role, and
// what it computes to, one field to a row with the name on the left and the
// value on the right. Formulas are shown with names; Enter or leaving a field
// commits it as one undo step, Escape puts it back. The object is held by its
// ID, since undo and redo replace the pattern's objects.
unit Sloper.UI.Properties;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Spin, Forms, Graphics, LCLType, Sloper.Core.Draft, Sloper.Core.Fabrics, Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Transform, Sloper.Core.Pattern, Sloper.Core.Evaluator,
  Sloper.Document.PatternDocument, Sloper.UI.FormulaCompleter;

type
  // One line of text that cuts itself to the label's width with an ellipsis
  // and shows the full text as a tooltip when it does
  TGridLabel = class(TLabel)
  private
    FFittedText: string;
  protected
    function GetLabelText: string; override;
    procedure Paint; override;
  public
    constructor Create(TheOwner: TComponent); override;
  end;

  TColumnDragEvent = procedure(Sender: TObject; NewLeft: integer) of object;

  // The draggable strip between the name and value columns
  TColumnDivider = class(TGraphicControl)
  private
    FGrabX: integer;
    FDragging: boolean;
    FOnDrag: TColumnDragEvent;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
  public
    constructor Create(TheOwner: TComponent); override;
    property OnDrag: TColumnDragEvent read FOnDrag write FOnDrag;
  end;

  TPropertiesPanel = class(TScrollBox)
  private
    FDocument: TPatternDocument;
    FKey: string;
    FSelectionCount: integer;
    FNameShare: double;
    // The fields the controls were built for; a rebuild is needed when they change
    FFieldNames: TStringArray;
    FDivider: TColumnDivider;
    FNameEdit: TEdit;
    FDescriptionEdit: TEdit;
    FRoleBox: TComboBox;
    FEndsBox: TComboBox;
    FCutEdit: TSpinEdit;
    FMirrorBox: TCheckBox;
    FFoldBox: TComboBox;
    // The edge of each fold choice; '' for none
    FFoldKeys: TStringArray;
    // One choice per fabric, then none
    FFabricBox: TComboBox;
    FFillStyleBox: TComboBox;
    // From the fabric, the piece's own colour if it has one, then choosing one
    FFillColorBox: TComboBox;
    FMadeByText: TGridLabel;
    FSideAText, FSideBText, FDifferenceText: TGridLabel;
    FEdits: array of TEdit;
    // Each field's row for a refused entry, hidden until needed; see RefusalRow
    FRefusals: array of TLabel;
    FResult: TGridLabel;
    FProblem: TLabel;
    FFirstRow: TControl;
    FLastRow: TControl;
    FLastControl: TControl;
    FCommitting: boolean;
    FCompleter: TFormulaCompleter;
    // The panel itself is setting a field's text, so suggestions stay away
    FSettingText: boolean;
    // Enter took a suggestion; its release must not select the whole field
    FSwallowEnterUp: boolean;
    // Undo or redo changed the pattern, so even the field being typed in follows it
    FRefreshFocused: boolean;
    // The piece's rows are being filled in, which is not the user changing them
    FFillingPieceRows: boolean;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure ClearControls;
    procedure HangBelowLast(Control: TControl; SpaceAbove: integer);
    procedure Stack(Control: TControl; SpaceAbove: integer);
    function AddLabel(const ACaption: string; SpaceAbove: integer): TLabel;
    procedure AddRow(const ACaption: string; Value: TControl; SpaceAbove: integer);
    function AddTextRow(const ACaption, AText: string; SpaceAbove: integer): TGridLabel;
    function AddEditRow(const ACaption: string; ATag: integer): TEdit;
    function ColumnSpace: integer;
    function MinColumn: integer;
    procedure PositionDivider;
    procedure DividerDrag(Sender: TObject; NewLeft: integer);
    procedure SetNameShare(AShare: double);
    function RefusalRow(Edit: TEdit): TLabel;
    procedure ShowRefusal(Edit: TEdit; const Reason: string);
    procedure ClearRefusal(Edit: TEdit);
    procedure Rebuild;
    procedure RefreshValues;
    function CurrentFieldNames: TStringArray;
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure EditKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditChange(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure UpdateCompletion(Edit: TEdit; Explicit: boolean);
    procedure SetEditText(Edit: TEdit; const AText: string);
    function KeepsText(Edit: TEdit): boolean;
    procedure RoleChange(Sender: TObject);
    procedure AddPieceRows(Piece: TPieceObject);
    procedure AddSeamRows;
    procedure RefreshSeamRows(Seam: TSeamObject);
    procedure FlipClick(Sender: TObject);
    procedure AddRepeatRows(ARepeat: TRepeatObject);
    procedure EndsChange(Sender: TObject);
    function EditableKey(const Key: string): string;
    procedure RefreshPieceRows(Piece: TPieceObject);
    procedure CutChange(Sender: TObject);
    procedure FoldChange(Sender: TObject);
    procedure FabricChange(Sender: TObject);
    procedure FillStyleChange(Sender: TObject);
    procedure FillColorChange(Sender: TObject);
    procedure ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
    procedure RefreshFabricRows(Piece: TPieceObject);
    procedure RefreshTransformRows(Node: TEvalNode);
    procedure CommitEdit(Edit: TEdit);
    function OriginalText(Edit: TEdit): string;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Shows the object with this key alone, or a count when several or none are selected
    procedure ShowSelection(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    // Puts the cursor in the name field, with the name selected, ready to replace
    procedure FocusName;
    // The part of a row's width given to names; kept between sessions by the main form
    property NameShare: double read FNameShare write SetNameShare;
  end;

resourcestring
  rsPropNothing = 'Nothing selected';
  rsPropMany = '%d objects selected';
  rsPropType = 'Type';
  rsPropName = 'Name';
  rsPropRole = 'Role';
  rsPropRepeatFrom = 'From';
  rsPropRepeatTo = 'To';
  rsPropRepeatEdge = 'Along';
  rsPropEnds = 'Ends';
  rsPropEndsInclude = 'Include the ends';
  rsPropEndsExclude = 'Leave out the ends';
  rsPropChangeEnds = 'Change repeat ends';
  rsPropConstruction = 'Construction';
  rsPropOutline = 'Outline';
  rsPropPosition = 'Position';
  rsPropLength = 'Length';
  rsPropPerimeter = 'Perimeter';
  rsPropSideA = 'Side A';
  rsPropSideB = 'Side B';
  rsPropSeamLengths = 'Lengths';
  rsPropSeamDifference = 'Difference';
  rsPropDirection = 'Direction';
  rsPropFlip = 'Flip';
  rsPropFlipSeam = 'Flip seam';
  rsPropCut = 'Cut';
  rsPropMirrored = 'Mirrored';
  rsPropFold = 'Fold';
  rsPropFabric = 'Fabric';
  rsPropNoFabric = 'None';
  rsPropChangeFabric = 'Change fabric';
  rsPropFillStyle = 'Fill';
  rsPropFillColor = 'Colour';
  rsPropFromFabric = 'From fabric';
  rsPropFillTint = 'Tint';
  rsPropFillHatch = 'Hatching';
  rsPropChooseColor = 'Choose…';
  rsPropChangeFill = 'Change fill';
  rsPropMadeBy = 'Made by';
  rsPropNoFold = 'None';
  rsPropChangeCut = 'Change cut';
  rsPropChangeFold = 'Change fold';
  rsPropValue = 'Value';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropDescription = 'Description';
  rsPropChangeDescription = 'Change description';
  rsPropChangeRole = 'Change role';

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Variables, Sloper.Core.Drag, Sloper.Core.Settings,
  Sloper.UI.FabricsPanel, Sloper.UI.GridColumns, Sloper.UI.ObjectList;

const
  Gap = 6;
  RowGap = 3;
  Indent = 8;
  // At 96 pixels per inch
  DividerWidth96 = 8;
  MinColumn96 = 48;
  // Edit tags below the field numbers
  NameTag = -1;
  DescriptionTag = -2;
  RefusalBase = 2;
  MaxCutCount = 99;

function SameNames(const First, Second: TStringArray): boolean;
var
  Index: integer;
begin
  if Length(First) <> Length(Second) then
    Exit(False);
  for Index := 0 to High(First) do
    if First[Index] <> Second[Index] then
      Exit(False);
  Result := True;
end;

{ TGridLabel }

constructor TGridLabel.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  ShowAccelChar := False;
  Layout := tlCenter;
  ShowHint := True;
end;

function TGridLabel.GetLabelText: string;
begin
  if FFittedText <> '' then
    Result := FFittedText
  else
    Result := inherited GetLabelText;
end;

// Fitted here, where the width and font are final; the fitted text is only
// for drawing, so the label's preferred size still comes from the full text
procedure TGridLabel.Paint;
begin
  Canvas.Font := Font;
  FFittedText := FitText(Caption, Width, @Canvas.TextWidth);
  if FFittedText = Caption then
    Hint := ''
  else
    Hint := Caption;
  inherited Paint;
  FFittedText := '';
end;

{ TColumnDivider }

constructor TColumnDivider.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  ControlStyle := ControlStyle + [csCaptureMouse];
  Cursor := crHSplit;
end;

procedure TColumnDivider.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    FGrabX := X;
  end;
end;

procedure TColumnDivider.MouseMove(Shift: TShiftState; X, Y: integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging and Assigned(FOnDrag) then
    FOnDrag(Self, Left + X - FGrabX);
end;

procedure TColumnDivider.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FDragging := False;
end;

{ TPropertiesPanel }

constructor TPropertiesPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  FNameShare := DefaultNameColumnShare;
  HorzScrollBar.Visible := False;
  Rebuild;
end;

destructor TPropertiesPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

procedure TPropertiesPanel.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if FDocument <> nil then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if FDocument <> nil then
    FDocument.AddListener(@DocumentChanged);
  FKey := '';
  FSelectionCount := 0;
  if not (csDestroying in ComponentState) then
    Rebuild;
end;

procedure TPropertiesPanel.ShowSelection(const Keys: TStringArray);
begin
  FSelectionCount := Length(Keys);
  if FSelectionCount = 1 then
    FKey := EditableKey(Keys[0])
  else
    FKey := '';
  Rebuild;
end;

// A repeat is edited through its first point
function TPropertiesPanel.EditableKey(const Key: string): string;
var
  Node: TEvalNode;
begin
  Result := Key;
  if FDocument = nil then
    Exit;
  Node := FDocument.Pattern.FindNode(Key);
  if (Node is TRepeatPoint) and (TRepeatPoint(Node).Index = 1) then
    Result := TRepeatPoint(Node).Source.Key;
end;

procedure TPropertiesPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  // A commit from one of our own fields notifies while its handler runs;
  // the controls stay, only their values change
  if (FKey <> '') and (FDocument.Pattern.FindNode(FKey) = nil) then
  begin
    FKey := '';
    FSelectionCount := 0;
  end;
  FRefreshFocused := dcObjectsReplaced in Changes;
  try
    if FCommitting or (FKey <> '') and SameNames(CurrentFieldNames, FFieldNames) then
      RefreshValues
    else
      Rebuild;
  finally
    FRefreshFocused := False;
  end;
end;

function TPropertiesPanel.KeepsText(Edit: TEdit): boolean;
begin
  Result := Edit.Focused and not FRefreshFocused;
end;

function TPropertiesPanel.CurrentFieldNames: TStringArray;
var
  Node: TEvalNode;
  Index: integer;
begin
  Result := nil;
  if (FDocument = nil) or (FKey = '') then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if Node = nil then
    Exit;
  SetLength(Result, Node.FieldCount);
  for Index := 0 to Node.FieldCount - 1 do
    Result[Index] := Node.Fields[Index].Name;
end;

procedure TPropertiesPanel.ClearControls;
var
  Edit: TEdit;
begin
  if FCompleter <> nil then
    FCompleter.Hide;
  // Freeing a focused edit would run its exit handler and commit mid-rebuild
  if FNameEdit <> nil then
    FNameEdit.OnExit := nil;
  if FDescriptionEdit <> nil then
    FDescriptionEdit.OnExit := nil;
  for Edit in FEdits do
    Edit.OnExit := nil;
  while ControlCount > 0 do
    Controls[0].Free;
  FDivider := nil;
  FNameEdit := nil;
  FDescriptionEdit := nil;
  FRoleBox := nil;
  FCutEdit := nil;
  FMirrorBox := nil;
  FFoldBox := nil;
  FFoldKeys := nil;
  FFabricBox := nil;
  FFillStyleBox := nil;
  FFillColorBox := nil;
  FMadeByText := nil;
  FSideAText := nil;
  FSideBText := nil;
  FDifferenceText := nil;
  FEdits := nil;
  FRefusals := nil;
  FResult := nil;
  FProblem := nil;
  FFirstRow := nil;
  FLastRow := nil;
  FLastControl := nil;
end;

// Each control hangs below the one before, so sizes follow the widgetset's
// fonts and scaling and the order is explicit. A hidden control takes no
// room: the next one anchors through it.
procedure TPropertiesPanel.HangBelowLast(Control: TControl; SpaceAbove: integer);
begin
  if FLastControl = nil then
  begin
    Control.AnchorSideTop.Control := Self;
    Control.AnchorSideTop.Side := asrTop;
  end
  else
  begin
    Control.AnchorSideTop.Control := FLastControl;
    Control.AnchorSideTop.Side := asrBottom;
  end;
  Control.BorderSpacing.Top := SpaceAbove;
  FLastControl := Control;
end;

// A control across both columns
procedure TPropertiesPanel.Stack(Control: TControl; SpaceAbove: integer);
begin
  Control.Parent := Self;
  Control.Anchors := [akLeft, akTop, akRight];
  Control.AnchorSideLeft.Control := Self;
  Control.AnchorSideLeft.Side := asrTop;
  Control.AnchorSideRight.Control := Self;
  Control.AnchorSideRight.Side := asrBottom;
  Control.BorderSpacing.Left := Indent;
  Control.BorderSpacing.Right := Indent;
  HangBelowLast(Control, SpaceAbove);
end;

function TPropertiesPanel.AddLabel(const ACaption: string; SpaceAbove: integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Stack(Result, SpaceAbove);
end;

// A name in the left column beside Value in the right; the value sets the
// row's height and the divider sets where the columns meet
procedure TPropertiesPanel.AddRow(const ACaption: string; Value: TControl; SpaceAbove: integer);
var
  NameLabel: TGridLabel;
begin
  Value.Parent := Self;
  Value.Anchors := [akLeft, akTop, akRight];
  Value.AnchorSideLeft.Control := FDivider;
  Value.AnchorSideLeft.Side := asrBottom;
  Value.AnchorSideRight.Control := Self;
  Value.AnchorSideRight.Side := asrBottom;
  Value.BorderSpacing.Right := Indent;
  HangBelowLast(Value, SpaceAbove);
  NameLabel := TGridLabel.Create(Self);
  NameLabel.Caption := ACaption;
  NameLabel.Parent := Self;
  NameLabel.Anchors := [akLeft, akTop, akRight, akBottom];
  NameLabel.AnchorSideLeft.Control := Self;
  NameLabel.AnchorSideLeft.Side := asrTop;
  NameLabel.AnchorSideRight.Control := FDivider;
  NameLabel.AnchorSideRight.Side := asrTop;
  NameLabel.AnchorSideTop.Control := Value;
  NameLabel.AnchorSideTop.Side := asrTop;
  NameLabel.AnchorSideBottom.Control := Value;
  NameLabel.AnchorSideBottom.Side := asrBottom;
  NameLabel.BorderSpacing.Left := Indent;
  if FFirstRow = nil then
    FFirstRow := Value;
  FLastRow := Value;
end;

function TPropertiesPanel.AddTextRow(const ACaption, AText: string; SpaceAbove: integer): TGridLabel;
begin
  Result := TGridLabel.Create(Self);
  Result.Caption := AText;
  AddRow(ACaption, Result, SpaceAbove);
end;

// Tag -1 is the name; 0 and up are formula fields
function TPropertiesPanel.AddEditRow(const ACaption: string; ATag: integer): TEdit;
var
  Refusal: TLabel;
begin
  Result := TEdit.Create(Self);
  Result.Tag := ATag;
  Result.OnKeyDown := @EditKeyDown;
  Result.OnExit := @EditExit;
  Result.OnKeyUp := @EditKeyUp;
  Result.OnChange := @EditChange;
  Result.OnClick := @EditClick;
  AddRow(ACaption, Result, RowGap);
  Refusal := AddLabel('', RowGap);
  Refusal.Font.Color := clRed;
  Refusal.Visible := False;
  FRefusals[ATag + RefusalBase] := Refusal;
end;

// The width the two columns share
function TPropertiesPanel.ColumnSpace: integer;
begin
  Result := ClientWidth - 2 * Indent - FDivider.Width;
end;

function TPropertiesPanel.MinColumn: integer;
begin
  Result := Scale96ToForm(MinColumn96);
end;

procedure TPropertiesPanel.PositionDivider;
begin
  if FDivider <> nil then
    FDivider.Left := Indent + NameColumnWidth(ColumnSpace, MinColumn, FNameShare);
end;

procedure TPropertiesPanel.DividerDrag(Sender: TObject; NewLeft: integer);
begin
  FNameShare := NameShareAt(NewLeft - Indent, ColumnSpace, MinColumn);
  PositionDivider;
end;

procedure TPropertiesPanel.SetNameShare(AShare: double);
begin
  FNameShare := AShare;
  PositionDivider;
end;

procedure TPropertiesPanel.Resize;
begin
  inherited Resize;
  PositionDivider;
end;

function TPropertiesPanel.RefusalRow(Edit: TEdit): TLabel;
begin
  Result := FRefusals[Edit.Tag + RefusalBase];
end;

procedure TPropertiesPanel.ShowRefusal(Edit: TEdit; const Reason: string);
begin
  RefusalRow(Edit).Caption := Reason;
  RefusalRow(Edit).Visible := True;
end;

procedure TPropertiesPanel.ClearRefusal(Edit: TEdit);
begin
  RefusalRow(Edit).Visible := False;
end;

procedure TPropertiesPanel.Rebuild;
var
  Node: TEvalNode;
  Index: integer;
begin
  DisableAlign;
  try
    ClearControls;
    FFieldNames := CurrentFieldNames;
    Node := nil;
    if (FDocument <> nil) and (FKey <> '') then
      Node := FDocument.Pattern.FindNode(FKey);
    if Node = nil then
    begin
      if FSelectionCount > 1 then
        AddLabel(Format(rsPropMany, [FSelectionCount]), Gap)
      else
        AddLabel(rsPropNothing, Gap);
      Exit;
    end;
    FDivider := TColumnDivider.Create(Self);
    FDivider.Width := Scale96ToForm(DividerWidth96);
    FDivider.Parent := Self;
    FDivider.OnDrag := @DividerDrag;
    SetLength(FRefusals, Node.FieldCount + RefusalBase);
    AddTextRow(rsPropType, TypeCaption(Node), Gap);
    if Node is TRepeatPoint then
      AddTextRow(rsPropName, TRepeatPoint(Node).Name, RowGap)
    else if (Node is TDraftObject) or (Node is TVariable) then
      FNameEdit := AddEditRow(rsPropName, NameTag);
    SetLength(FEdits, Node.FieldCount);
    for Index := 0 to Node.FieldCount - 1 do
      FEdits[Index] := AddEditRow(FieldCaption(Node.Fields[Index].Name), Index);
    if Node is TVariable then
      FDescriptionEdit := AddEditRow(rsPropDescription, DescriptionTag);
    if Node is TEdgeObject then
    begin
      FRoleBox := TComboBox.Create(Self);
      FRoleBox.Style := csDropDownList;
      FRoleBox.Items.Add(rsPropConstruction);
      FRoleBox.Items.Add(rsPropOutline);
      FRoleBox.OnChange := @RoleChange;
      AddRow(rsPropRole, FRoleBox, RowGap);
    end;
    if Node is TRepeatObject then
      AddRepeatRows(TRepeatObject(Node));
    if Node is TPieceObject then
      AddPieceRows(TPieceObject(Node));
    if Node is TSeamObject then
      AddSeamRows;
    if CopyTransformKey(Node) <> '' then
      FMadeByText := AddTextRow(rsPropMadeBy, '', RowGap);
    if Node is TPointObject then
      FResult := AddTextRow(rsPropPosition, '', Gap)
    else if Node is TEdgeObject then
      FResult := AddTextRow(rsPropLength, '', Gap)
    else if Node is TPieceObject then
      FResult := AddTextRow(rsPropPerimeter, '', Gap)
    else if Node is TSeamObject then
      FResult := AddTextRow(rsPropSeamLengths, '', Gap)
    else if Node is TVariable then
      FResult := AddTextRow(rsPropValue, '', Gap);
    if Node is TSeamObject then
      FDifferenceText := AddTextRow(rsPropSeamDifference, '', RowGap);
    FProblem := AddLabel('', Gap);
    FProblem.Font.Color := clRed;
    FDivider.Anchors := [akLeft, akTop, akBottom];
    FDivider.AnchorSideTop.Control := FFirstRow;
    FDivider.AnchorSideTop.Side := asrTop;
    FDivider.AnchorSideBottom.Control := FLastRow;
    FDivider.AnchorSideBottom.Side := asrBottom;
    PositionDivider;
  finally
    EnableAlign;
  end;
  RefreshValues;
end;

// The text a field should show now
function TPropertiesPanel.OriginalText(Edit: TEdit): string;
var
  Node: TEvalNode;
begin
  Result := '';
  Node := FDocument.Pattern.FindNode(FKey);
  if Node = nil then
    Exit;
  if Edit.Tag = DescriptionTag then
    Result := TVariable(Node).Description
  else if Edit.Tag = NameTag then
    Result := Node.DisplayName
  else
    Result := FDocument.Pattern.FormulaText(Node, Node.Fields[Edit.Tag].Name);
  // Variables show as #name; the name field holds the bare name
  if (Edit.Tag = NameTag) and (Node is TVariable) then
    Result := TVariable(Node).Name;
end;

procedure TPropertiesPanel.RefreshValues;
var
  Node: TEvalNode;
  Edit: TEdit;
begin
  if (FDocument = nil) or (FKey = '') then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if Node = nil then
    Exit;
  // A field being typed in keeps its text, and the reason it was refused
  if (FNameEdit <> nil) and not KeepsText(FNameEdit) then
  begin
    SetEditText(FNameEdit, OriginalText(FNameEdit));
    if not FCommitting then
      ClearRefusal(FNameEdit);
  end;
  for Edit in FEdits do
    if not KeepsText(Edit) then
    begin
      SetEditText(Edit, OriginalText(Edit));
      if not FCommitting then
        ClearRefusal(Edit);
    end;
  if (FDescriptionEdit <> nil) and not KeepsText(FDescriptionEdit) then
    SetEditText(FDescriptionEdit, OriginalText(FDescriptionEdit));
  if FRoleBox <> nil then
    FRoleBox.ItemIndex := Ord(TEdgeObject(Node).Role);
  if FEndsBox <> nil then
    FEndsBox.ItemIndex := Ord(not TRepeatObject(Node).IncludeEnds);
  if Node is TPieceObject then
    RefreshPieceRows(TPieceObject(Node));
  if Node is TSeamObject then
    RefreshSeamRows(TSeamObject(Node));
  RefreshTransformRows(Node);
  if FResult <> nil then
    if Node is TDraftObject then
      FResult.Caption := ResultText(TDraftObject(Node))
    else
      FResult.Caption := '';
  if (FResult <> nil) and (Node is TVariable) and (Node.State = esValid) then
    FResult.Caption := RoundedText(TVariable(Node).Value, 4);
  if (FProblem <> nil) and not FCommitting then
    if Node.State = esValid then
      FProblem.Caption := ''
    else
      FProblem.Caption := Node.Message;
end;

procedure TPropertiesPanel.CommitEdit(Edit: TEdit);
var
  Node: TEvalNode;
  FieldName, Description, Reason: string;
  ErrorPos: integer;
  Done: boolean;
begin
  if (FDocument = nil) or (FKey = '') then
    Exit;
  if Edit.Text = OriginalText(Edit) then
  begin
    ClearRefusal(Edit);
    Exit;
  end;
  Node := FDocument.Pattern.FindNode(FKey);
  if Node = nil then
    Exit;
  if Edit.Tag = DescriptionTag then
    Description := rsPropChangeDescription
  else if Edit.Tag = NameTag then
    Description := rsPropRename
  else
  begin
    FieldName := Node.Fields[Edit.Tag].Name;
    Description := Format(rsPropEdit, [FieldCaption(FieldName)]);
  end;
  FCommitting := True;
  try
    FDocument.BeginChange(Description);
    if Edit.Tag = DescriptionTag then
    begin
      TVariable(Node).Description := Edit.Text;
      Done := True;
    end
    else if Edit.Tag = NameTag then
      Done := FDocument.Pattern.Rename(Node, Edit.Text)
    else
      Done := FDocument.Pattern.SetFormula(Node, FieldName, Edit.Text);
    Reason := FDocument.Pattern.LastError;
    ErrorPos := FDocument.Pattern.LastErrorPos;
    FDocument.Commit(Done);
  finally
    FCommitting := False;
  end;
  if Done then
  begin
    SetEditText(Edit, OriginalText(Edit));
    ClearRefusal(Edit);
    RefreshValues;
  end
  else
  begin
    // Keep the text so it can be fixed, with the cursor at the problem
    ShowRefusal(Edit, Reason);
    if ErrorPos > 0 then
      Edit.SelStart := ErrorPos - 1;
  end;
end;

procedure TPropertiesPanel.EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Edit: TEdit;
begin
  Edit := TEdit(Sender);
  FSwallowEnterUp := (Key = VK_RETURN) and (FCompleter <> nil) and FCompleter.Visible;
  if (FCompleter <> nil) and FCompleter.HandleKey(Key) then
    Exit;
  case Key of
    VK_RETURN:
    begin
      CommitEdit(Edit);
      Key := 0;
    end;
    VK_ESCAPE:
    begin
      SetEditText(Edit, OriginalText(Edit));
      ClearRefusal(Edit);
      Key := 0;
    end;
    VK_SPACE:
      if ssModifier in Shift then
      begin
        UpdateCompletion(Edit, True);
        Key := 0;
      end;
    VK_LEFT, VK_RIGHT, VK_HOME, VK_END:
      if FCompleter <> nil then
        FCompleter.Hide;
  end;
end;

// The edit selects all of its text when Enter comes up
procedure TPropertiesPanel.EditKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and FSwallowEnterUp then
  begin
    FSwallowEnterUp := False;
    Key := 0;
  end;
end;

procedure TPropertiesPanel.EditExit(Sender: TObject);
begin
  // A click on the suggestions comes back to the field
  if (FCompleter <> nil) and FCompleter.HasMouse then
    Exit;
  if FCompleter <> nil then
    FCompleter.Hide;
  CommitEdit(TEdit(Sender));
end;

procedure TPropertiesPanel.FocusName;
begin
  if FNameEdit <> nil then
  begin
    FNameEdit.SetFocus;
    FNameEdit.SelectAll;
  end;
end;

procedure TPropertiesPanel.SetEditText(Edit: TEdit; const AText: string);
begin
  FSettingText := True;
  try
    Edit.Text := AText;
  finally
    FSettingText := False;
  end;
  if FCompleter <> nil then
    FCompleter.Hide;
end;

// The name and description fields are not formulas
procedure TPropertiesPanel.UpdateCompletion(Edit: TEdit; Explicit: boolean);
begin
  if (Edit.Tag < 0) or (FDocument = nil) then
    Exit;
  if FCompleter = nil then
    FCompleter := TFormulaCompleter.Create(Self);
  FCompleter.Update(Edit, FDocument.Pattern, FDocument.Pattern.FindNode(FKey), Explicit);
end;

procedure TPropertiesPanel.EditChange(Sender: TObject);
begin
  if FSettingText or not TEdit(Sender).Focused or ((FCompleter <> nil) and FCompleter.Setting) then
    Exit;
  UpdateCompletion(TEdit(Sender), False);
end;

procedure TPropertiesPanel.EditClick(Sender: TObject);
begin
  if FCompleter <> nil then
    FCompleter.Hide;
end;

procedure TPropertiesPanel.AddSeamRows;
var
  Flip: TButton;
begin
  FSideAText := AddTextRow(rsPropSideA, '', RowGap);
  FSideBText := AddTextRow(rsPropSideB, '', RowGap);
  Flip := TButton.Create(Self);
  Flip.Caption := rsPropFlip;
  Flip.OnClick := @FlipClick;
  AddRow(rsPropDirection, Flip, RowGap);
end;

procedure TPropertiesPanel.RefreshSeamRows(Seam: TSeamObject);
begin
  FSideAText.Caption := SeamSideText(FDocument.Pattern, Seam.SideA);
  FSideBText.Caption := SeamSideText(FDocument.Pattern, Seam.SideB);
  if Seam.HasResult then
    FDifferenceText.Caption := SeamDifferenceText(Seam)
  else
    FDifferenceText.Caption := '';
end;

procedure TPropertiesPanel.FlipClick(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TSeamObject) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropFlipSeam);
    TSeamObject(Node).Reversed := not TSeamObject(Node).Reversed;
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
end;

// Only straight edges can be a fold, so only those are offered
procedure TPropertiesPanel.AddPieceRows(Piece: TPieceObject);
var
  Entry: TPieceEdge;
  Edge: TEvalNode;
begin
  FCutEdit := TSpinEdit.Create(Self);
  FCutEdit.MinValue := 1;
  FCutEdit.MaxValue := MaxCutCount;
  FCutEdit.OnChange := @CutChange;
  AddRow(rsPropCut, FCutEdit, RowGap);
  FMirrorBox := TCheckBox.Create(Self);
  FMirrorBox.OnChange := @CutChange;
  AddRow(rsPropMirrored, FMirrorBox, RowGap);
  FFoldBox := TComboBox.Create(Self);
  FFoldBox.Style := csDropDownList;
  FFoldBox.Items.Add(rsPropNoFold);
  Insert('', FFoldKeys, 0);
  for Entry in Piece.Path do
  begin
    Edge := FDocument.Pattern.FindNode(Entry.EdgeKey);
    if IsStraightEdge(TEdgeObject(Edge)) then
    begin
      FFoldBox.Items.Add(Edge.DisplayName);
      Insert(Entry.EdgeKey, FFoldKeys, Length(FFoldKeys));
    end;
  end;
  FFoldBox.OnChange := @FoldChange;
  AddRow(rsPropFold, FFoldBox, RowGap);
  FFabricBox := TComboBox.Create(Self);
  FFabricBox.Style := csDropDownList;
  FFabricBox.OnChange := @FabricChange;
  AddRow(rsPropFabric, FFabricBox, RowGap);
  FFillStyleBox := TComboBox.Create(Self);
  FFillStyleBox.Style := csDropDownList;
  // In the order of TPieceFillStyle
  FFillStyleBox.Items.Add(rsPropFromFabric);
  FFillStyleBox.Items.Add(rsPropFillTint);
  FFillStyleBox.Items.Add(rsPropFillHatch);
  FFillStyleBox.OnChange := @FillStyleChange;
  AddRow(rsPropFillStyle, FFillStyleBox, RowGap);
  FFillColorBox := TComboBox.Create(Self);
  FFillColorBox.Style := csDropDownList;
  FFillColorBox.OnChange := @FillColorChange;
  AddRow(rsPropFillColor, FFillColorBox, RowGap);
end;

procedure TPropertiesPanel.RefreshPieceRows(Piece: TPieceObject);
var
  Index: integer;
begin
  // Each row fires its change event, when the others are not yet filled in
  FFillingPieceRows := True;
  try
    FCutEdit.Value := Piece.CutCount;
    FMirrorBox.Checked := Piece.Mirrored;
    RefreshFabricRows(Piece);
  finally
    FFillingPieceRows := False;
  end;
  for Index := 0 to High(FFoldKeys) do
    if FFoldKeys[Index] = Piece.FoldEdgeKey then
      FFoldBox.ItemIndex := Index;
end;

// The fabrics can change while the piece stays selected
procedure TPropertiesPanel.RefreshFabricRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
begin
  Pattern := FDocument.Pattern;
  FFabricBox.Items.Clear;
  for Index := 0 to Pattern.FabricCount - 1 do
    FFabricBox.Items.Add(Pattern.Fabrics[Index].Name);
  FFabricBox.Items.Add(rsPropNoFabric);
  FFabricBox.ItemIndex := Pattern.FabricCount;
  for Index := 0 to Pattern.FabricCount - 1 do
    if Pattern.FabricOf(Piece) = Pattern.Fabrics[Index] then
      FFabricBox.ItemIndex := Index;
  FFillStyleBox.ItemIndex := Ord(Piece.FillStyle);
  FFillColorBox.Items.Clear;
  FFillColorBox.Items.Add(rsPropFromFabric);
  if Piece.FillColor <> '' then
    FFillColorBox.Items.Add(Piece.FillColor);
  FFillColorBox.Items.Add(rsPropChooseColor);
  FFillColorBox.ItemIndex := Ord(Piece.FillColor <> '');
end;

procedure TPropertiesPanel.FabricChange(Sender: TObject);
var
  Node: TEvalNode;
  Fabric: TPatternFabric;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if FFillingPieceRows or not (Node is TPieceObject) or (FFabricBox.ItemIndex < 0) then
    Exit;
  Fabric := nil;
  if FFabricBox.ItemIndex < FDocument.Pattern.FabricCount then
    Fabric := FDocument.Pattern.Fabrics[FFabricBox.ItemIndex];
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeFabric);
    FDocument.Pattern.SetPieceFabric(TPieceObject(Node), Fabric);
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
  RefreshPieceRows(TPieceObject(FDocument.Pattern.FindNode(FKey)));
end;

procedure TPropertiesPanel.ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TPieceObject) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeFill);
    FDocument.Commit(FDocument.Pattern.SetPieceFill(TPieceObject(Node), AColor, Style));
  finally
    FCommitting := False;
  end;
  RefreshPieceRows(TPieceObject(FDocument.Pattern.FindNode(FKey)));
end;

procedure TPropertiesPanel.FillStyleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if FFillingPieceRows or not (Node is TPieceObject) or (FFillStyleBox.ItemIndex < 0) then
    Exit;
  ChangePieceFill(TPieceObject(Node).FillColor, TPieceFillStyle(FFillStyleBox.ItemIndex));
end;

procedure TPropertiesPanel.FillColorChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  Chosen: string;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if FFillingPieceRows or not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if FFillColorBox.ItemIndex = 0 then
    ChangePieceFill('', Piece.FillStyle)
  else if FFillColorBox.ItemIndex = FFillColorBox.Items.Count - 1 then
  begin
    Chosen := Piece.FillColor;
    if Chosen = '' then
      Chosen := FDocument.Pattern.Fabrics[0].Color;
    if ChooseFabricColor(Self, Chosen) then
      ChangePieceFill(Chosen, Piece.FillStyle)
    else
      RefreshPieceRows(Piece);
  end;
end;

// Runs of spin clicks merge into one undo step
procedure TPropertiesPanel.CutChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
begin
  if FFillingPieceRows then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if (Piece.CutCount = FCutEdit.Value) and (Piece.Mirrored = FMirrorBox.Checked) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeCut);
    FDocument.Commit(FDocument.Pattern.SetCut(Piece, FCutEdit.Value, FMirrorBox.Checked), 'cut:' + FKey);
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.RefreshTransformRows(Node: TEvalNode);
begin
  if FMadeByText <> nil then
    FMadeByText.Caption := FDocument.Pattern.FindNode(CopyTransformKey(Node)).DisplayName;
end;

procedure TPropertiesPanel.FoldChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TPieceObject) or (TPieceObject(Node).FoldEdgeKey = FFoldKeys[FFoldBox.ItemIndex]) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeFold);
    FDocument.Commit(FDocument.Pattern.SetFoldEdge(TPieceObject(Node), FFoldKeys[FFoldBox.ItemIndex]));
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.AddRepeatRows(ARepeat: TRepeatObject);

  function NameOf(const Key: string): string;
  var
    Node: TEvalNode;
  begin
    Node := FDocument.Pattern.FindNode(Key);
    if Node = nil then
      Result := Key
    else
      Result := Node.DisplayName;
  end;

begin
  if ARepeat.Edge <> '' then
    AddTextRow(rsPropRepeatEdge, NameOf(ARepeat.Edge), RowGap)
  else
  begin
    AddTextRow(rsPropRepeatFrom, NameOf(ARepeat.FirstPoint), RowGap);
    AddTextRow(rsPropRepeatTo, NameOf(ARepeat.LastPoint), RowGap);
  end;
  FEndsBox := TComboBox.Create(Self);
  FEndsBox.Style := csDropDownList;
  FEndsBox.Items.Add(rsPropEndsInclude);
  FEndsBox.Items.Add(rsPropEndsExclude);
  FEndsBox.OnChange := @EndsChange;
  AddRow(rsPropEnds, FEndsBox, RowGap);
end;

procedure TPropertiesPanel.EndsChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TRepeatObject) or (Ord(not TRepeatObject(Node).IncludeEnds) = FEndsBox.ItemIndex) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeEnds);
    TRepeatObject(Node).IncludeEnds := FEndsBox.ItemIndex = 0;
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.RoleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TEdgeObject) or (Ord(TEdgeObject(Node).Role) = FRoleBox.ItemIndex) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeRole);
    TEdgeObject(Node).Role := TEdgeRole(FRoleBox.ItemIndex);
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
end;

end.
