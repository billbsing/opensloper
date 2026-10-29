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
// what it computes to. Formulas are shown with names; Enter or leaving a
// field commits it as one undo step, Escape puts it back. The object is held
// by its ID, since undo and redo replace the pattern's objects.
unit Sloper.UI.Properties;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, Graphics, LCLType, Sloper.Document.PatternDocument;

type
  TPropertiesPanel = class(TScrollBox)
  private
    FDocument: TPatternDocument;
    FKey: string;
    FSelectionCount: integer;
    // The fields the controls were built for; a rebuild is needed when they change
    FFieldNames: TStringArray;
    FTitle: TLabel;
    FNameEdit: TEdit;
    FRoleBox: TComboBox;
    FEdits: array of TEdit;
    FResult: TLabel;
    FProblem: TLabel;
    FLastControl: TControl;
    FCommitting: boolean;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure ClearControls;
    procedure Stack(Control: TControl; SpaceAbove: integer);
    function AddLabel(const ACaption: string; SpaceAbove: integer): TLabel;
    function AddEdit(ATag: integer): TEdit;
    procedure Rebuild;
    procedure RefreshValues;
    function CurrentFieldNames: TStringArray;
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure RoleChange(Sender: TObject);
    procedure CommitEdit(Edit: TEdit);
    function OriginalText(Edit: TEdit): string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Shows the object with this key alone, or a count when several or none are selected
    procedure ShowSelection(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
  end;

// Caption for a formula field, such as "Start angle" for angle1
function FieldCaption(const FieldName: string): string;

resourcestring
  rsPropNothing = 'Nothing selected';
  rsPropMany = '%d objects selected';
  rsPropName = 'Name';
  rsPropRole = 'Role';
  rsPropConstruction = 'Construction';
  rsPropOutline = 'Outline';
  rsPropAt = 'At %s, %s mm';
  rsPropLength = 'Length %s mm';
  rsPropValue = 'Value %s';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropChangeRole = 'Change role';
  rsFieldX = 'X';
  rsFieldY = 'Y';
  rsFieldLength = 'Length';
  rsFieldAngle = 'Angle';
  rsFieldDX = 'Across';
  rsFieldDY = 'Up';
  rsFieldValue = 'Distance or ratio';
  rsFieldRadius = 'Radius';
  rsFieldAngle1 = 'Start angle';
  rsFieldLength1 = 'Start handle';
  rsFieldAngle2 = 'End angle';
  rsFieldLength2 = 'End handle';
  rsFieldFormula = 'Formula';
  rsFieldNodeAngle = 'Point %s angle';
  rsFieldNodeIn = 'Point %s handle in';
  rsFieldNodeOut = 'Point %s handle out';
  rsTypeFree = 'Free point';
  rsTypeOffset = 'Offset point';
  rsTypeAlong = 'Point along an edge';
  rsTypeIntersect = 'Crossing of two edges';
  rsTypeCircle = 'Compass step onto an edge';
  rsTypeProject = 'Point projected onto an edge';
  rsTypeLine = 'Line';
  rsTypeCurve = 'Curve';
  rsTypePath = 'Curve path';
  rsTypePart = 'Part of a split edge';
  rsTypeVariable = 'Variable';

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Variables, Sloper.Core.Draft, Sloper.Core.Drag;

const
  Gap = 6;
  Indent = 8;

function FieldCaption(const FieldName: string): string;
var
  Dot: integer;
  NodeNumber, Part: string;
begin
  Dot := Pos('.', FieldName);
  if (Dot > 0) and (Copy(FieldName, 1, 4) = 'node') then
  begin
    NodeNumber := Copy(FieldName, 5, Dot - 5);
    Part := Copy(FieldName, Dot + 1, MaxInt);
    if Part = 'angle' then
      Exit(Format(rsFieldNodeAngle, [NodeNumber]));
    if Part = 'lengthIn' then
      Exit(Format(rsFieldNodeIn, [NodeNumber]));
    Exit(Format(rsFieldNodeOut, [NodeNumber]));
  end;
  case FieldName of
    'x': Result := rsFieldX;
    'y': Result := rsFieldY;
    'length': Result := rsFieldLength;
    'angle': Result := rsFieldAngle;
    'dx': Result := rsFieldDX;
    'dy': Result := rsFieldDY;
    'value': Result := rsFieldValue;
    'radius': Result := rsFieldRadius;
    'angle1': Result := rsFieldAngle1;
    'length1': Result := rsFieldLength1;
    'angle2': Result := rsFieldAngle2;
    'length2': Result := rsFieldLength2;
    'formula': Result := rsFieldFormula;
    else
      Result := FieldName;
  end;
end;

function TypeCaption(Node: TEvalNode): string;
begin
  if Node is TFreePoint then
    Result := rsTypeFree
  else if Node is TOffsetPoint then
    Result := rsTypeOffset
  else if Node is TAlongEdgePoint then
    Result := rsTypeAlong
  else if Node is TIntersectPoint then
    Result := rsTypeIntersect
  else if Node is TCircleEdgePoint then
    Result := rsTypeCircle
  else if Node is TProjectPoint then
    Result := rsTypeProject
  else if Node is TLineObject then
    Result := rsTypeLine
  else if Node is TCurveObject then
    Result := rsTypeCurve
  else if Node is TCurvePathObject then
    Result := rsTypePath
  else if Node is TSplitPart then
    Result := rsTypePart
  else if Node is TVariable then
    Result := rsTypeVariable
  else
    Result := '';
end;

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

{ TPropertiesPanel }

constructor TPropertiesPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
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
    FKey := Keys[0]
  else
    FKey := '';
  Rebuild;
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
  if FCommitting or (FKey <> '') and SameNames(CurrentFieldNames, FFieldNames) then
    RefreshValues
  else
    Rebuild;
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
  // Freeing a focused edit would run its exit handler and commit mid-rebuild
  if FNameEdit <> nil then
    FNameEdit.OnExit := nil;
  for Edit in FEdits do
    Edit.OnExit := nil;
  while ControlCount > 0 do
    Controls[0].Free;
  FTitle := nil;
  FNameEdit := nil;
  FRoleBox := nil;
  FEdits := nil;
  FResult := nil;
  FProblem := nil;
  FLastControl := nil;
end;

// Each control hangs below the one before, anchored to the panel's sides, so
// sizes follow the widgetset's fonts and scaling and the order is explicit
procedure TPropertiesPanel.Stack(Control: TControl; SpaceAbove: integer);
begin
  Control.Parent := Self;
  Control.Anchors := [akLeft, akTop, akRight];
  Control.AnchorSideLeft.Control := Self;
  Control.AnchorSideLeft.Side := asrTop;
  Control.AnchorSideRight.Control := Self;
  Control.AnchorSideRight.Side := asrBottom;
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
  Control.BorderSpacing.Left := Indent;
  Control.BorderSpacing.Right := Indent;
  Control.BorderSpacing.Top := SpaceAbove;
  FLastControl := Control;
end;

function TPropertiesPanel.AddLabel(const ACaption: string; SpaceAbove: integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Stack(Result, SpaceAbove);
end;

function TPropertiesPanel.AddEdit(ATag: integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Tag := ATag;
  Result.OnKeyDown := @EditKeyDown;
  Result.OnExit := @EditExit;
  Stack(Result, 2);
end;

// Tag -1 is the name; 0 and up are formula fields
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
    FTitle := AddLabel(TypeCaption(Node), Gap);
    FTitle.Font.Style := [fsBold];
    if (Node is TDraftObject) or (Node is TVariable) then
    begin
      AddLabel(rsPropName, Gap);
      FNameEdit := AddEdit(-1);
    end;
    SetLength(FEdits, Node.FieldCount);
    for Index := 0 to Node.FieldCount - 1 do
    begin
      AddLabel(FieldCaption(Node.Fields[Index].Name), Gap);
      FEdits[Index] := AddEdit(Index);
    end;
    if Node is TEdgeObject then
    begin
      AddLabel(rsPropRole, Gap);
      FRoleBox := TComboBox.Create(Self);
      FRoleBox.Style := csDropDownList;
      FRoleBox.Items.Add(rsPropConstruction);
      FRoleBox.Items.Add(rsPropOutline);
      FRoleBox.OnChange := @RoleChange;
      Stack(FRoleBox, 2);
    end;
    FResult := AddLabel('', 2 * Gap);
    FProblem := AddLabel('', Gap);
    FProblem.Font.Color := clRed;
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
  if Edit.Tag < 0 then
    Result := Node.DisplayName
  else
    Result := FDocument.Pattern.FormulaText(Node, Node.Fields[Edit.Tag].Name);
  // Variables show as #name; the name field holds the bare name
  if (Edit.Tag < 0) and (Node is TVariable) then
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
  // A field being typed in keeps its text
  if (FNameEdit <> nil) and not FNameEdit.Focused then
    FNameEdit.Text := OriginalText(FNameEdit);
  for Edit in FEdits do
    if not Edit.Focused then
      Edit.Text := OriginalText(Edit);
  if FRoleBox <> nil then
    FRoleBox.ItemIndex := Ord(TEdgeObject(Node).Role);
  if FResult <> nil then
    if not (Node is TDraftObject) or not TDraftObject(Node).HasResult then
      FResult.Caption := ''
    else if Node is TPointObject then
      FResult.Caption := Format(rsPropAt, [RoundedText(TPointObject(Node).Position.X, 1),
        RoundedText(TPointObject(Node).Position.Y, 1)])
    else if Node is TEdgeObject then
      FResult.Caption := Format(rsPropLength, [RoundedText(TEdgeObject(Node).Length, 1)]);
  if (FResult <> nil) and (Node is TVariable) and (Node.State = esValid) then
    FResult.Caption := Format(rsPropValue, [RoundedText(TVariable(Node).Value, 4)]);
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
  if (FDocument = nil) or (FKey = '') or (Edit.Text = OriginalText(Edit)) then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if Node = nil then
    Exit;
  if Edit.Tag < 0 then
    Description := rsPropRename
  else
  begin
    FieldName := Node.Fields[Edit.Tag].Name;
    Description := Format(rsPropEdit, [FieldCaption(FieldName)]);
  end;
  FCommitting := True;
  try
    FDocument.BeginChange(Description);
    if Edit.Tag < 0 then
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
    Edit.Text := OriginalText(Edit);
    RefreshValues;
  end
  else
  begin
    // Keep the text so it can be fixed, with the cursor at the problem
    FProblem.Caption := Reason;
    if ErrorPos > 0 then
      Edit.SelStart := ErrorPos - 1;
  end;
end;

procedure TPropertiesPanel.EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Edit: TEdit;
begin
  Edit := TEdit(Sender);
  case Key of
    VK_RETURN:
    begin
      CommitEdit(Edit);
      Key := 0;
    end;
    VK_ESCAPE:
    begin
      Edit.Text := OriginalText(Edit);
      FProblem.Caption := '';
      Key := 0;
    end;
  end;
end;

procedure TPropertiesPanel.EditExit(Sender: TObject);
begin
  CommitEdit(TEdit(Sender));
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
