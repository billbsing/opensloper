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
  Sloper.Core.Transform, Sloper.Core.Pattern, Sloper.Core.Evaluator, Sloper.Core.Note,
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
  TPropertiesMessageEvent = procedure(Sender: TObject; const AText: string) of object;

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
    FMarkerBox: TComboBox;
    // The pieces a marking line prints on
    FMarkedOnText: TGridLabel;
    FEndsBox: TComboBox;
    FCutEdit: TSpinEdit;
    FMirrorBox: TCheckBox;
    FFoldBox: TComboBox;
    // A line, curve or arc's type, which can be changed
    FTypeBox: TComboBox;
    // The edge waiting to be changed, once the type box's handler has returned
    FConvertKey: string;
    FOnMessage: TPropertiesMessageEvent;
    // The edge of each fold choice; '' for none
    FFoldKeys: TStringArray;
    // One choice per fabric, then none
    FFabricBox: TComboBox;
    FFillStyleBox: TComboBox;
    // From the fabric, the piece's own colour if it has one, then choosing one
    FFillColorBox: TComboBox;
    FMadeByText: TGridLabel;
    FSideAText, FSideBText, FDifferenceText: TGridLabel;
    // A note's text, size, whether it prints, and what it hangs from
    FNoteText: TMemo;
    FNoteSize: TFloatSpinEdit;
    FNotePrint: TCheckBox;
    FNoteAnchorText: TGridLabel;
    FNoteRefusal: TLabel;
    FNoteLeaderBox, FNoteAlignBox: TComboBox;
    FNoteBoxCheck: TCheckBox;
    FFreeButton: TButton;
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
    procedure MarkerChange(Sender: TObject);
    function MarkedOnText(DraftObject: TDraftObject): string;
    procedure AddPieceRows(Piece: TPieceObject);
    procedure AddSeamRows;
    procedure AddNoteTextRow;
    procedure AddNoteRows(Note: TNoteObject);
    procedure RefreshNoteRows(Note: TNoteObject);
    function NoteAnchorText(Note: TNoteObject): string;
    procedure CommitNoteText;
    procedure NoteTextExit(Sender: TObject);
    procedure NoteTextKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure NoteSizeChange(Sender: TObject);
    procedure NotePrintClick(Sender: TObject);
    procedure NoteLookChange(Sender: TObject);
    procedure FreeClick(Sender: TObject);
    procedure RefreshSeamRows(Seam: TSeamObject);
    procedure FlipClick(Sender: TObject);
    procedure AddRepeatRows(ARepeat: TRepeatObject);
    procedure EndsChange(Sender: TObject);
    function EditableKey(const Key: string): string;
    procedure RefreshPieceRows(Piece: TPieceObject);
    procedure CutChange(Sender: TObject);
    procedure FoldChange(Sender: TObject);
    procedure TypeChange(Sender: TObject);
    procedure ConvertQueued(Data: PtrInt);
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
    // Puts the cursor in a note's text, with the text selected, ready to replace
    procedure FocusNoteText;
    // The part of a row's width given to names; kept between sessions by the main form
    property NameShare: double read FNameShare write SetNameShare;
    // Says why a change was refused
    property OnMessage: TPropertiesMessageEvent read FOnMessage write FOnMessage;
  end;

// What a role is called in the app
function RoleCaption(Role: TEdgeRole): string;

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
  rsPropPlacement = 'Placement';
  rsPropStitch = 'Stitch';
  rsPropFoldRole = 'Fold';
  rsPropCutRole = 'Cut';
  rsPropSkiveRole = 'Skive line';
  rsPropEdgeFinishRole = 'Edge finish';
  rsPropMarkedOn = 'Marked on';
  rsPropMarkedOnNone = 'No piece';
  rsPropNotMarking = '-';
  rsPropMarker = 'Marker';
  rsPropMarkerPlain = 'Plain';
  rsPropMarkerHole = 'Hole';
  rsPropMarkerButton = 'Button';
  rsPropMarkerMatch = 'Match dot';
  rsPropChangeMarker = 'Change marker';
  rsPropPosition = 'Position';
  rsPropNoteText = 'Text';
  rsPropNoteSize = 'Size (points)';
  rsPropNotePrint = 'Print';
  rsPropNotePrintCaption = 'Print and export it';
  rsPropNoteAnchor = 'Hangs from';
  rsPropNoteAnchorPoint = 'Point %s';
  rsPropNoteAnchorEdge = '%s';
  rsPropNoteAnchorPiece = 'Piece %s';
  rsPropNoteAnchorFree = 'Nothing (free)';
  rsPropNoteFree = 'Make free';
  rsPropNoteFreeHint = 'Unhook the note, leaving it where it is, so what it hangs from can be deleted';
  rsPropChangeNoteText = 'Change note text';
  rsPropChangeNoteSize = 'Change note size';
  rsPropChangeNotePrint = 'Change note printing';
  rsPropFreeNote = 'Make note free';
  rsPropNoteLeader = 'Leader';
  rsPropNoteLeaderNone = 'None (a plain note)';
  rsPropNoteLeaderArrow = 'Arrow';
  rsPropNoteLeaderDot = 'Dot';
  rsPropNoteLeaderLine = 'Line';
  rsPropNoteAlign = 'Lines';
  rsPropNoteAlignLeft = 'Left';
  rsPropNoteAlignCentre = 'Centred';
  rsPropNoteAlignRight = 'Right';
  rsPropNoteBox = 'Box';
  rsPropNoteBoxCaption = 'On a white box';
  rsPropChangeNoteLook = 'Change note';
  rsPropNoteTextHint = 'Draft values go in {= }, such as {=Line_A_B.length}';
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
  rsPropChangeType = 'Change edge type';
  rsPropValue = 'Value';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropDescription = 'Description';
  rsPropChangeDescription = 'Change description';
  rsPropChangeRole = 'Change role';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Variables, Sloper.Core.Drag, Sloper.Core.Settings,
  Sloper.UI.FabricsPanel, Sloper.UI.GridColumns, Sloper.UI.ObjectList;

function RoleCaption(Role: TEdgeRole): string;
begin
  case Role of
    erConstruction: Result := rsPropConstruction;
    erOutline: Result := rsPropOutline;
    erPlacement: Result := rsPropPlacement;
    erStitch: Result := rsPropStitch;
    erFold: Result := rsPropFoldRole;
    erCut: Result := rsPropCutRole;
    erSkive: Result := rsPropSkiveRole;
    else
      Result := rsPropEdgeFinishRole;
  end;
end;

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
  // A note's text field, at 96 pixels per inch
  NoteTextHeight96 = 64;
  NoteSizeStep = 1;

// A note's draft value field: value1, value2
function IsNoteValue(const FieldName: string): boolean;
begin
  Result := (Copy(FieldName, 1, Length(NoteValueField)) = NoteValueField) and
    (StrToIntDef(Copy(FieldName, Length(NoteValueField) + 1, MaxInt), 0) > 0);
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
  Application.RemoveAsyncCalls(Self);
  SetDocument(nil);
  inherited Destroy;
end;

procedure TPropertiesPanel.SetDocument(ADocument: TPatternDocument);
begin
  if FDocument = ADocument then
    Exit;
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if Assigned(FDocument) then
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
  if not Assigned(FDocument) then
    Exit;
  Node := FDocument.Pattern.FindNode(Key);
  if (Node is TRepeatPoint) and (TRepeatPoint(Node).Index = 1) then
    Result := TRepeatPoint(Node).Source.Key;
end;

procedure TPropertiesPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  // A commit from one of our own fields notifies while its handler runs;
  // the controls stay, only their values change
  if (FKey <> '') and not Assigned(FDocument.Pattern.FindNode(FKey)) then
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
  if not Assigned(FDocument) or (FKey = '') then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not Assigned(Node) then
    Exit;
  SetLength(Result, Node.FieldCount);
  for Index := 0 to Node.FieldCount - 1 do
    Result[Index] := Node.Fields[Index].Name;
end;

procedure TPropertiesPanel.ClearControls;
var
  Edit: TEdit;
begin
  if Assigned(FCompleter) then
    FCompleter.Hide;
  // Freeing a focused edit would run its exit handler and commit mid-rebuild
  if Assigned(FNameEdit) then
    FNameEdit.OnExit := nil;
  if Assigned(FDescriptionEdit) then
    FDescriptionEdit.OnExit := nil;
  for Edit in FEdits do
    if Assigned(Edit) then
      Edit.OnExit := nil;
  while ControlCount > 0 do
    Controls[0].Free;
  FDivider := nil;
  FNameEdit := nil;
  FDescriptionEdit := nil;
  FRoleBox := nil;
  FMarkerBox := nil;
  FMarkedOnText := nil;
  FCutEdit := nil;
  FMirrorBox := nil;
  FFoldBox := nil;
  FTypeBox := nil;
  FFoldKeys := nil;
  FFabricBox := nil;
  FFillStyleBox := nil;
  FFillColorBox := nil;
  FMadeByText := nil;
  FSideAText := nil;
  FSideBText := nil;
  FDifferenceText := nil;
  if Assigned(FNoteText) then
    FNoteText.OnExit := nil;
  FNoteText := nil;
  FNoteSize := nil;
  FNotePrint := nil;
  FNoteAnchorText := nil;
  FNoteRefusal := nil;
  FNoteLeaderBox := nil;
  FNoteAlignBox := nil;
  FNoteBoxCheck := nil;
  FFreeButton := nil;
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
  if not Assigned(FLastControl) then
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
  if not Assigned(FFirstRow) then
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
  if Assigned(FDivider) then
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
  Role: TEdgeRole;
begin
  DisableAlign;
  try
    ClearControls;
    FFieldNames := CurrentFieldNames;
    Node := nil;
    if Assigned(FDocument) and (FKey <> '') then
      Node := FDocument.Pattern.FindNode(FKey);
    if not Assigned(Node) then
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
    // A line, curve or arc the user drew can change type; copies and parts follow other edges
    if (Node.ClassType = TLineObject) or (Node.ClassType = TCurveObject) or (Node.ClassType = TArcObject) then
    begin
      FTypeBox := TComboBox.Create(Self);
      FTypeBox.Style := csDropDownList;
      if Node is TArcObject then
        FTypeBox.Items.Add(rsTypeArc);
      FTypeBox.Items.Add(rsTypeLine);
      if not (Node is TArcObject) then
        FTypeBox.Items.Add(rsTypeCurve);
      FTypeBox.ItemIndex := FTypeBox.Items.IndexOf(TypeCaption(Node));
      FTypeBox.OnChange := @TypeChange;
      AddRow(rsPropType, FTypeBox, Gap);
    end
    else
      AddTextRow(rsPropType, TypeCaption(Node), Gap);
    if Node is TRepeatPoint then
      AddTextRow(rsPropName, TRepeatPoint(Node).Name, RowGap)
    else if (Node is TDraftObject) or (Node is TVariable) then
      FNameEdit := AddEditRow(rsPropName, NameTag);
    if Node is TNoteObject then
      AddNoteTextRow;
    SetLength(FEdits, Node.FieldCount);
    // A marker's size goes under the marker
    for Index := 0 to Node.FieldCount - 1 do
      if (Node.Fields[Index].Name <> MarkerSizeField) and not ((Node is TNoteObject) and IsNoteValue(Node.Fields[Index].Name)) then
        FEdits[Index] := AddEditRow(FieldCaption(Node.Fields[Index].Name), Index);
    if Node is TVariable then
      FDescriptionEdit := AddEditRow(rsPropDescription, DescriptionTag);
    if Node is TEdgeObject then
    begin
      FRoleBox := TComboBox.Create(Self);
      FRoleBox.Style := csDropDownList;
      // In the order of TEdgeRole
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        FRoleBox.Items.Add(RoleCaption(Role));
      FRoleBox.OnChange := @RoleChange;
      AddRow(rsPropRole, FRoleBox, RowGap);
      FMarkedOnText := AddTextRow(rsPropMarkedOn, '', RowGap);
    end;
    // A repeat's points share the repeat's marker
    if ((Node is TPointObject) and not (Node is TRepeatPoint)) or (Node is TRepeatObject) then
    begin
      FMarkerBox := TComboBox.Create(Self);
      FMarkerBox.Style := csDropDownList;
      // In the order of TPointMarker
      FMarkerBox.Items.Add(rsPropMarkerPlain);
      FMarkerBox.Items.Add(rsPropMarkerHole);
      FMarkerBox.Items.Add(rsPropMarkerButton);
      FMarkerBox.Items.Add(rsPropMarkerMatch);
      FMarkerBox.OnChange := @MarkerChange;
      AddRow(rsPropMarker, FMarkerBox, RowGap);
      for Index := 0 to Node.FieldCount - 1 do
        if Node.Fields[Index].Name = MarkerSizeField then
          FEdits[Index] := AddEditRow(FieldCaption(MarkerSizeField), Index);
      FMarkedOnText := AddTextRow(rsPropMarkedOn, '', RowGap);
    end;
    if Node is TRepeatObject then
      AddRepeatRows(TRepeatObject(Node));
    if Node is TPieceObject then
      AddPieceRows(TPieceObject(Node));
    if Node is TSeamObject then
      AddSeamRows;
    if Node is TNoteObject then
      AddNoteRows(TNoteObject(Node));
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
      FResult := AddTextRow(rsPropValue, '', Gap)
    else if Node is TNoteObject then
      FResult := AddTextRow(rsPropPosition, '', Gap);
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
  if not Assigned(Node) then
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
  if not Assigned(FDocument) or (FKey = '') then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not Assigned(Node) then
    Exit;
  // A field being typed in keeps its text, and the reason it was refused
  if Assigned(FNameEdit) and not KeepsText(FNameEdit) then
  begin
    SetEditText(FNameEdit, OriginalText(FNameEdit));
    if not FCommitting then
      ClearRefusal(FNameEdit);
  end;
  // A note's draft values are edited in its text, so they have no field of their own
  for Edit in FEdits do
    if Assigned(Edit) and not KeepsText(Edit) then
    begin
      SetEditText(Edit, OriginalText(Edit));
      if not FCommitting then
        ClearRefusal(Edit);
    end;
  if Assigned(FDescriptionEdit) and not KeepsText(FDescriptionEdit) then
    SetEditText(FDescriptionEdit, OriginalText(FDescriptionEdit));
  if Assigned(FRoleBox) then
    FRoleBox.ItemIndex := Ord(TEdgeObject(Node).Role);
  if Assigned(FMarkerBox) then
    FMarkerBox.ItemIndex := Ord(TDraftObject(Node).Marker);
  if Assigned(FMarkedOnText) then
    FMarkedOnText.Caption := MarkedOnText(TDraftObject(Node));
  if Assigned(FEndsBox) then
    FEndsBox.ItemIndex := Ord(not TRepeatObject(Node).IncludeEnds);
  if Node is TPieceObject then
    RefreshPieceRows(TPieceObject(Node));
  if Node is TSeamObject then
    RefreshSeamRows(TSeamObject(Node));
  if Node is TNoteObject then
    RefreshNoteRows(TNoteObject(Node));
  RefreshTransformRows(Node);
  if Assigned(FResult) then
    if (Node is TNoteObject) and Node.HasResult then
      FResult.Caption := PositionText(TNoteObject(Node).Position, FDocument.Pattern.Units)
    else if Node is TDraftObject then
      FResult.Caption := ResultText(TDraftObject(Node), FDocument.Pattern.Units)
    else
      FResult.Caption := '';
  if Assigned(FResult) and (Node is TVariable) and (Node.State = esValid) then
    FResult.Caption := RoundedText(TVariable(Node).Value, 4);
  if Assigned(FProblem) and not FCommitting then
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
  if not Assigned(FDocument) or (FKey = '') then
    Exit;
  if Edit.Text = OriginalText(Edit) then
  begin
    ClearRefusal(Edit);
    Exit;
  end;
  Node := FDocument.Pattern.FindNode(FKey);
  if not Assigned(Node) then
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
  FSwallowEnterUp := (Key = VK_RETURN) and Assigned(FCompleter) and FCompleter.Visible;
  if Assigned(FCompleter) and FCompleter.HandleKey(Key) then
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
      if Assigned(FCompleter) then
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
  if Assigned(FCompleter) and FCompleter.HasMouse then
    Exit;
  if Assigned(FCompleter) then
    FCompleter.Hide;
  CommitEdit(TEdit(Sender));
end;

procedure TPropertiesPanel.FocusNoteText;
begin
  if Assigned(FNoteText) and FNoteText.CanFocus then
  begin
    FNoteText.SetFocus;
    FNoteText.SelectAll;
  end;
end;

procedure TPropertiesPanel.FocusName;
begin
  // A hidden tab or side panel cannot take the focus, and SetFocus would raise
  if Assigned(FNameEdit) and FNameEdit.CanFocus then
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
  if Assigned(FCompleter) then
    FCompleter.Hide;
end;

// The name and description fields are not formulas
procedure TPropertiesPanel.UpdateCompletion(Edit: TEdit; Explicit: boolean);
begin
  if (Edit.Tag < 0) or not Assigned(FDocument) then
    Exit;
  if not Assigned(FCompleter) then
    FCompleter := TFormulaCompleter.Create(Self);
  FCompleter.Update(Edit, FDocument.Pattern, FDocument.Pattern.FindNode(FKey), Explicit);
end;

procedure TPropertiesPanel.EditChange(Sender: TObject);
begin
  if FSettingText or not TEdit(Sender).Focused or (Assigned(FCompleter) and FCompleter.Setting) then
    Exit;
  UpdateCompletion(TEdit(Sender), False);
end;

procedure TPropertiesPanel.EditClick(Sender: TObject);
begin
  if Assigned(FCompleter) then
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

// Enter adds a line; leaving the field commits it as one undo step
procedure TPropertiesPanel.AddNoteTextRow;
begin
  FNoteText := TMemo.Create(Self);
  FNoteText.Height := Scale96ToForm(NoteTextHeight96);
  FNoteText.ScrollBars := ssAutoVertical;
  FNoteText.WantReturns := True;
  FNoteText.WordWrap := False;
  FNoteText.OnExit := @NoteTextExit;
  FNoteText.OnKeyDown := @NoteTextKeyDown;
  FNoteText.Hint := rsPropNoteTextHint;
  FNoteText.ShowHint := True;
  AddRow(rsPropNoteText, FNoteText, RowGap);
  FNoteRefusal := AddLabel('', RowGap);
  FNoteRefusal.Font.Color := clRed;
  FNoteRefusal.WordWrap := True;
  FNoteRefusal.Visible := False;
end;

procedure TPropertiesPanel.AddNoteRows(Note: TNoteObject);
begin
  FNoteSize := TFloatSpinEdit.Create(Self);
  FNoteSize.MinValue := NoteSizeStep;
  FNoteSize.MaxValue := MaxNoteSize;
  FNoteSize.Increment := NoteSizeStep;
  FNoteSize.DecimalPlaces := 1;
  FNoteSize.OnChange := @NoteSizeChange;
  AddRow(rsPropNoteSize, FNoteSize, RowGap);
  FNotePrint := TCheckBox.Create(Self);
  FNotePrint.Caption := rsPropNotePrintCaption;
  FNotePrint.OnClick := @NotePrintClick;
  AddRow(rsPropNotePrint, FNotePrint, RowGap);
  FNoteAlignBox := TComboBox.Create(Self);
  FNoteAlignBox.Style := csDropDownList;
  // In the order of TTextAlign
  FNoteAlignBox.Items.Add(rsPropNoteAlignLeft);
  FNoteAlignBox.Items.Add(rsPropNoteAlignCentre);
  FNoteAlignBox.Items.Add(rsPropNoteAlignRight);
  FNoteAlignBox.OnChange := @NoteLookChange;
  AddRow(rsPropNoteAlign, FNoteAlignBox, RowGap);
  FNoteBoxCheck := TCheckBox.Create(Self);
  FNoteBoxCheck.Caption := rsPropNoteBoxCaption;
  FNoteBoxCheck.OnClick := @NoteLookChange;
  AddRow(rsPropNoteBox, FNoteBoxCheck, RowGap);
  // A free note has nothing to point at
  if Note.Anchor <> naFree then
  begin
    FNoteLeaderBox := TComboBox.Create(Self);
    FNoteLeaderBox.Style := csDropDownList;
    // In the order of TNoteLeader
    FNoteLeaderBox.Items.Add(rsPropNoteLeaderNone);
    FNoteLeaderBox.Items.Add(rsPropNoteLeaderArrow);
    FNoteLeaderBox.Items.Add(rsPropNoteLeaderDot);
    FNoteLeaderBox.Items.Add(rsPropNoteLeaderLine);
    FNoteLeaderBox.OnChange := @NoteLookChange;
    AddRow(rsPropNoteLeader, FNoteLeaderBox, RowGap);
  end;
  FNoteAnchorText := AddTextRow(rsPropNoteAnchor, '', RowGap);
  if Note.Anchor <> naFree then
  begin
    FFreeButton := TButton.Create(Self);
    FFreeButton.Caption := rsPropNoteFree;
    FFreeButton.Hint := rsPropNoteFreeHint;
    FFreeButton.ShowHint := True;
    FFreeButton.OnClick := @FreeClick;
    AddRow('', FFreeButton, RowGap);
  end;
end;

function TPropertiesPanel.NoteAnchorText(Note: TNoteObject): string;
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(Note.AnchorKey);
  if (Note.Anchor = naFree) or not Assigned(Node) then
    Exit(rsPropNoteAnchorFree);
  case Note.Anchor of
    naPoint: Result := Format(rsPropNoteAnchorPoint, [Node.DisplayName]);
    naEdge: Result := Format(rsPropNoteAnchorEdge, [Node.DisplayName]);
    else
      Result := Format(rsPropNoteAnchorPiece, [Node.DisplayName]);
  end;
end;

// The text field keeps what is being typed in it
procedure TPropertiesPanel.RefreshNoteRows(Note: TNoteObject);
begin
  FFillingPieceRows := True;
  try
    if Assigned(FNoteText) and (not FNoteText.Focused or FRefreshFocused) then
    begin
      FNoteText.Text := Note.DisplayText(FDocument.Pattern.Resolver);
      FNoteRefusal.Visible := False;
    end;
    if Assigned(FNoteAlignBox) then
      FNoteAlignBox.ItemIndex := Ord(Note.Align);
    if Assigned(FNoteBoxCheck) then
      FNoteBoxCheck.Checked := Note.Boxed;
    if Assigned(FNoteLeaderBox) then
      FNoteLeaderBox.ItemIndex := Ord(Note.Leader);
    if Assigned(FNoteSize) and not FNoteSize.Focused then
      FNoteSize.Value := Note.Size;
    if Assigned(FNotePrint) then
      FNotePrint.Checked := Note.Print;
    if Assigned(FNoteAnchorText) then
      FNoteAnchorText.Caption := NoteAnchorText(Note);
  finally
    FFillingPieceRows := False;
  end;
end;

// The memo's own line breaks are stored as line feeds
procedure TPropertiesPanel.CommitNoteText;
var
  Node: TEvalNode;
  NewText: string;
begin
  if not Assigned(FDocument) or not Assigned(FNoteText) then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TNoteObject) then
    Exit;
  NewText := StringReplace(FNoteText.Text, #13#10, #10, [rfReplaceAll]);
  NewText := StringReplace(NewText, #13, #10, [rfReplaceAll]);
  // The memo adds a line break after the last line
  while (NewText <> '') and (NewText[Length(NewText)] = #10) do
    SetLength(NewText, Length(NewText) - 1);
  if NewText = TNoteObject(Node).DisplayText(FDocument.Pattern.Resolver) then
  begin
    FNoteRefusal.Visible := False;
    Exit;
  end;
  // A draft value that does not parse keeps the text as typed, with the reason
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeNoteText);
    if FDocument.Pattern.SetNoteText(TNoteObject(Node), NewText) then
    begin
      FDocument.EndChange;
      FNoteRefusal.Visible := False;
    end
    else
    begin
      FNoteRefusal.Caption := FDocument.Pattern.LastError;
      FDocument.CancelChange;
      FNoteRefusal.Visible := True;
    end;
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.NoteTextExit(Sender: TObject);
begin
  CommitNoteText;
end;

// Escape puts the text back
procedure TPropertiesPanel.NoteTextKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Node: TEvalNode;
begin
  if Key <> VK_ESCAPE then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if Node is TNoteObject then
    FNoteText.Text := TNoteObject(Node).DisplayText(FDocument.Pattern.Resolver);
  FNoteRefusal.Visible := False;
  Key := 0;
end;

// The leader, alignment and box, as one undo step
procedure TPropertiesPanel.NoteLookChange(Sender: TObject);
var
  Node: TEvalNode;
  Note: TNoteObject;
  Leader: TNoteLeader;
  Reason: string;
begin
  if FFillingPieceRows then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TNoteObject) then
    Exit;
  Note := TNoteObject(Node);
  Leader := Note.Leader;
  if Assigned(FNoteLeaderBox) and (FNoteLeaderBox.ItemIndex >= 0) then
    Leader := TNoteLeader(FNoteLeaderBox.ItemIndex);
  if (Leader = Note.Leader) and (Ord(Note.Align) = FNoteAlignBox.ItemIndex) and (Note.Boxed = FNoteBoxCheck.Checked) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeNoteLook);
    FDocument.Pattern.SetNoteAlign(Note, TTextAlign(Max(0, FNoteAlignBox.ItemIndex)));
    FDocument.Pattern.SetNoteBoxed(Note, FNoteBoxCheck.Checked);
    Reason := '';
    if not FDocument.Pattern.SetNoteLeader(Note, Leader) then
      Reason := FDocument.Pattern.LastError;
    FDocument.Commit(Reason = '');
  finally
    FCommitting := False;
  end;
  if (Reason <> '') and Assigned(FOnMessage) then
    FOnMessage(Self, Reason);
end;

procedure TPropertiesPanel.NoteSizeChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFillingPieceRows then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TNoteObject) or SameValue(TNoteObject(Node).Size, FNoteSize.Value) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeNoteSize);
    FDocument.Commit(FDocument.Pattern.SetNoteSize(TNoteObject(Node), FNoteSize.Value), 'notesize:' + FKey);
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.NotePrintClick(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFillingPieceRows then
    Exit;
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TNoteObject) or (TNoteObject(Node).Print = FNotePrint.Checked) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeNotePrint);
    FDocument.Pattern.SetNotePrint(TNoteObject(Node), FNotePrint.Checked);
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
end;

procedure TPropertiesPanel.FreeClick(Sender: TObject);
var
  Node: TEvalNode;
  Reason: string;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TNoteObject) then
    Exit;
  FDocument.BeginChange(rsPropFreeNote);
  Reason := '';
  if not FDocument.Pattern.MakeNoteFree(TNoteObject(Node)) then
    Reason := FDocument.Pattern.LastError;
  FDocument.Commit(Reason = '');
  if (Reason <> '') and Assigned(FOnMessage) then
    FOnMessage(Self, Reason);
end;

procedure TPropertiesPanel.RefreshSeamRows(Seam: TSeamObject);
begin
  FSideAText.Caption := SeamSideText(FDocument.Pattern, Seam.SideA);
  FSideBText.Caption := SeamSideText(FDocument.Pattern, Seam.SideB);
  if Seam.HasResult then
    FDifferenceText.Caption := SeamDifferenceText(Seam, FDocument.Pattern.Units)
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
  if Assigned(FMadeByText) then
    FMadeByText.Caption := FDocument.Pattern.FindNode(CopyTransformKey(Node)).DisplayName;
end;

// Changing type replaces the object and rebuilds the panel, box and all, so
// it waits until this handler has returned
procedure TPropertiesPanel.TypeChange(Sender: TObject);
begin
  FConvertKey := FKey;
  Application.QueueAsyncCall(@ConvertQueued, FTypeBox.ItemIndex);
end;

procedure TPropertiesPanel.ConvertQueued(Data: PtrInt);
var
  Node: TEvalNode;
  Wanted, Reason: string;
  Done: boolean;
begin
  if not Assigned(FDocument) or (FConvertKey = '') or not Assigned(FTypeBox) or (FConvertKey <> FKey) then
    Exit;
  Node := FDocument.Pattern.FindNode(FConvertKey);
  FConvertKey := '';
  if not (Node is TEdgeObject) or (Data < 0) or (Data >= FTypeBox.Items.Count) then
    Exit;
  Wanted := FTypeBox.Items[Data];
  if Wanted = TypeCaption(Node) then
    Exit;
  FDocument.BeginChange(rsPropChangeType);
  if Wanted = rsTypeLine then
    Done := Assigned(FDocument.Pattern.ConvertToLine(TEdgeObject(Node)))
  else
    Done := Assigned(FDocument.Pattern.ConvertToCurve(TEdgeObject(Node)));
  Reason := FDocument.Pattern.LastError;
  if FDocument.Commit(Done) then
    Exit;
  // The box goes back to the type the edge still has
  Rebuild;
  if Assigned(FOnMessage) then
    FOnMessage(Self, Reason);
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
    if not Assigned(Node) then
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

// The pieces it prints on, for a marking line or a marked point
function TPropertiesPanel.MarkedOnText(DraftObject: TDraftObject): string;
var
  Piece: TPieceObject;
begin
  if not FDocument.Pattern.IsMarking(DraftObject) then
    Exit(rsPropNotMarking);
  Result := '';
  for Piece in FDocument.Pattern.PiecesWithMarking(DraftObject.Key) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Piece.DisplayName;
  end;
  if Result = '' then
    Result := rsPropMarkedOnNone;
end;

procedure TPropertiesPanel.MarkerChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := FDocument.Pattern.FindNode(FKey);
  if not (Node is TDraftObject) or (Ord(TDraftObject(Node).Marker) = FMarkerBox.ItemIndex) then
    Exit;
  FCommitting := True;
  try
    FDocument.BeginChange(rsPropChangeMarker);
    FDocument.Pattern.SetMarker(Node.Key, TPointMarker(FMarkerBox.ItemIndex));
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
    FDocument.Pattern.SetEdgeRole(TEdgeObject(Node), TEdgeRole(FRoleBox.ItemIndex));
    FDocument.EndChange;
  finally
    FCommitting := False;
  end;
end;

end.
