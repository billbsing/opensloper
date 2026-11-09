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
  Classes, SysUtils, Controls, StdCtrls, Spin, Forms, Graphics, LCLType, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.Piece, Sloper.Core.Seam,
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

  // What a row of text edits: the object's name or one of its formulas
  TFieldRowKind = (frName, frFormula);

  // A text row; its edit's Tag is its index in the panel's rows
  TFieldRow = record
    Edit: TEdit;
    // Why an entry was refused, hidden until needed
    Refusal: TLabel;
    Kind: TFieldRowKind;
    // The formula's field; empty for the name
    FieldName: string;
  end;

  // A change that adds or removes rows, so it runs once the handler of the
  // control that asked has returned
  TQueuedChange = (qcConvertType, qcAddAllowance, qcRemoveAllowance, qcGrain);

  TPropertiesPanel = class(TScrollBox)
  private
    FDocument: TPatternDocument;
    FKey: string;
    FSelectionCount: integer;
    FNameShare: double;
    // The fields the controls were built for; a rebuild is needed when they change
    FFieldNames: TStringArray;
    FDivider: TColumnDivider;
    FRows: array of TFieldRow;
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
    // Adds an edge's own seam allowance: one choice per edge without one,
    // after the prompt, with the path index of each
    FAllowanceBox: TComboBox;
    FAllowanceIndexes: array of integer;
    // The grainline's kind, in the order of TGrainKind, and its two points
    // when it runs between them: Choose..., then every point by name
    FGrainBox, FGrainStartBox, FGrainEndBox: TComboBox;
    FGrainPointKeys: TStringArray;
    // The object a queued change is for, and the change; one at a time
    FQueuedKey: string;
    FQueuedChange: TQueuedChange;
    FQueuedData: integer;
    FOnMessage: TPropertiesMessageEvent;
    // The edge of each fold choice; '' for none
    FFoldKeys: TStringArray;
    // One choice per material, then none
    FMaterialBox: TComboBox;
    FFillStyleBox: TComboBox;
    // From the material, the piece's own colour if it has one, then choosing one
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
    // Rows are being filled in, which is not the user changing them
    FFilling: boolean;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    // The object shown, or nil
    function SelectedNode: TEvalNode;
    // A change made from the panel: the document's notification while it
    // commits refreshes the values and keeps the controls
    procedure BeginEdit(const Description: string);
    // Records the change when Done, else puts the pattern back
    function EndEdit(Done: boolean; const MergeKey: string = ''): boolean;
    procedure QueueChange(Change: TQueuedChange; Data: integer);
    procedure QueuedChangeDue(Data: PtrInt);
    procedure ClearControls;
    procedure HangBelowLast(Control: TControl; SpaceAbove: integer);
    procedure Stack(Control: TControl; SpaceAbove: integer);
    function AddLabel(const ACaption: string; SpaceAbove: integer): TLabel;
    procedure AddRow(const ACaption: string; Value: TControl; SpaceAbove: integer);
    function AddTextRow(const ACaption, AText: string; SpaceAbove: integer): TGridLabel;
    function AddChoiceRow(const ACaption: string; const Items: array of string; Handler: TNotifyEvent; SpaceAbove: integer): TComboBox;
    function AddEditRow(const ACaption: string; Kind: TFieldRowKind; const FieldName: string): TEdit;
    // The formula row of this field, or -1
    function FormulaRowOf(const FieldName: string): integer;
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
    // ItemIndex is the type box's choice
    procedure ConvertType(ItemIndex: integer);
    procedure AllowanceChange(Sender: TObject);
    // Added with the piece's allowance, or removed
    procedure AddEdgeAllowance(PathIndex: integer);
    procedure RemoveEdgeAllowance(PathIndex: integer);
    function FieldRowCaption(Node: TEvalNode; const FieldName: string): string;
    procedure AddGrainRows(Piece: TPieceObject);
    procedure RefreshGrainRows(Piece: TPieceObject);
    procedure GrainChange(Sender: TObject);
    procedure ChangeGrain(Kind: TGrainKind);
    procedure MaterialChange(Sender: TObject);
    procedure FillStyleChange(Sender: TObject);
    procedure FillColorChange(Sender: TObject);
    procedure ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
    procedure RefreshMaterialRows(Piece: TPieceObject);
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
  rsPropMadeBy = 'Made by';
  rsPropNoFold = 'None';
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
  rsPropEdgeAllowance = 'Allowance, %s';
  rsPropAddEdgeAllowance = 'Add edge allowance';
  rsPropRemoveEdgeAllowance = 'Remove edge allowance';
  rsPropChangeCut = 'Change cut';
  rsPropChangeFold = 'Change fold';
  rsPropChangeType = 'Change edge type';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropChangeRole = 'Change role';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Settings,
  Sloper.UI.MaterialGrid, Sloper.UI.GridColumns, Sloper.UI.ObjectList;

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

function TPropertiesPanel.SelectedNode: TEvalNode;
begin
  Result := nil;
  if Assigned(FDocument) and (FKey <> '') then
    Result := FDocument.Pattern.FindNode(FKey);
end;

procedure TPropertiesPanel.BeginEdit(const Description: string);
begin
  FCommitting := True;
  FDocument.BeginChange(Description);
end;

function TPropertiesPanel.EndEdit(Done: boolean; const MergeKey: string): boolean;
begin
  try
    Result := FDocument.Commit(Done, MergeKey);
  finally
    FCommitting := False;
  end;
end;

// A later change replaces one still waiting, so the first call to come runs
// the latest and any other finds nothing to do
procedure TPropertiesPanel.QueueChange(Change: TQueuedChange; Data: integer);
begin
  FQueuedKey := FKey;
  FQueuedChange := Change;
  FQueuedData := Data;
  Application.QueueAsyncCall(@QueuedChangeDue, 0);
end;

// Only for the object still shown
procedure TPropertiesPanel.QueuedChangeDue(Data: PtrInt);
begin
  if not Assigned(FDocument) or (FQueuedKey = '') or (FQueuedKey <> FKey) then
    Exit;
  FQueuedKey := '';
  case FQueuedChange of
    qcConvertType: ConvertType(FQueuedData);
    qcAddAllowance: AddEdgeAllowance(FQueuedData);
    qcRemoveAllowance: RemoveEdgeAllowance(FQueuedData);
    qcGrain: ChangeGrain(TGrainKind(FQueuedData));
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
  Node := SelectedNode;
  if not Assigned(Node) then
    Exit;
  SetLength(Result, Node.FieldCount);
  for Index := 0 to Node.FieldCount - 1 do
    Result[Index] := Node.Fields[Index].Name;
end;

procedure TPropertiesPanel.ClearControls;
var
  Row: TFieldRow;
begin
  if Assigned(FCompleter) then
    FCompleter.Hide;
  // Freeing a focused edit would run its exit handler and commit mid-rebuild
  for Row in FRows do
    Row.Edit.OnExit := nil;
  while ControlCount > 0 do
    Controls[0].Free;
  FDivider := nil;
  FRows := nil;
  FRoleBox := nil;
  FMarkerBox := nil;
  FMarkedOnText := nil;
  FEndsBox := nil;
  FCutEdit := nil;
  FMirrorBox := nil;
  FFoldBox := nil;
  FAllowanceBox := nil;
  FAllowanceIndexes := nil;
  FGrainBox := nil;
  FGrainStartBox := nil;
  FGrainEndBox := nil;
  FGrainPointKeys := nil;
  FTypeBox := nil;
  FFoldKeys := nil;
  FMaterialBox := nil;
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

// Items in the order of the value they stand for; the handler is set after
// them, and the caller sets the choice
function TPropertiesPanel.AddChoiceRow(const ACaption: string; const Items: array of string; Handler: TNotifyEvent;
  SpaceAbove: integer): TComboBox;
var
  Item: string;
begin
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  for Item in Items do
    Result.Items.Add(Item);
  Result.OnChange := Handler;
  AddRow(ACaption, Result, SpaceAbove);
end;

function TPropertiesPanel.AddEditRow(const ACaption: string; Kind: TFieldRowKind; const FieldName: string): TEdit;
var
  Index: integer;
begin
  Result := TEdit.Create(Self);
  Index := Length(FRows);
  SetLength(FRows, Index + 1);
  FRows[Index].Edit := Result;
  FRows[Index].Kind := Kind;
  FRows[Index].FieldName := FieldName;
  Result.Tag := Index;
  Result.OnKeyDown := @EditKeyDown;
  Result.OnExit := @EditExit;
  Result.OnKeyUp := @EditKeyUp;
  Result.OnChange := @EditChange;
  Result.OnClick := @EditClick;
  AddRow(ACaption, Result, RowGap);
  FRows[Index].Refusal := AddLabel('', RowGap);
  FRows[Index].Refusal.Font.Color := clRed;
  FRows[Index].Refusal.Visible := False;
end;

function TPropertiesPanel.FormulaRowOf(const FieldName: string): integer;
begin
  for Result := 0 to High(FRows) do
    if (FRows[Result].Kind = frFormula) and (FRows[Result].FieldName = FieldName) then
      Exit;
  Result := -1;
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
  Result := FRows[Edit.Tag].Refusal;
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
  RoleNames: TStringArray;
begin
  DisableAlign;
  try
    ClearControls;
    FFieldNames := CurrentFieldNames;
    Node := SelectedNode;
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
    // A line, curve or arc the user drew can change type; copies and parts follow other edges
    if (Node.ClassType = TLineObject) or (Node.ClassType = TCurveObject) or (Node.ClassType = TArcObject) then
    begin
      if Node is TArcObject then
        FTypeBox := AddChoiceRow(rsPropType, [rsTypeArc, rsTypeLine], nil, Gap)
      else
        FTypeBox := AddChoiceRow(rsPropType, [rsTypeLine, rsTypeCurve], nil, Gap);
      FTypeBox.ItemIndex := FTypeBox.Items.IndexOf(TypeCaption(Node));
      FTypeBox.OnChange := @TypeChange;
    end
    else
      AddTextRow(rsPropType, TypeCaption(Node), Gap);
    if Node is TRepeatPoint then
      AddTextRow(rsPropName, TRepeatPoint(Node).Name, RowGap)
    else if Node is TDraftObject then
      AddEditRow(rsPropName, frName, '');
    if Node is TNoteObject then
      AddNoteTextRow;
    // A marker's size goes under the marker, and a piece's grainline angle
    // under the grainline
    for Index := 0 to Node.FieldCount - 1 do
      if (Node.Fields[Index].Name <> MarkerSizeField) and not ((Node is TPieceObject) and (Node.Fields[Index].Name = GrainAngleField)) and
        not ((Node is TNoteObject) and IsNoteValue(Node.Fields[Index].Name)) then
        AddEditRow(FieldRowCaption(Node, Node.Fields[Index].Name), frFormula, Node.Fields[Index].Name);
    if Node is TEdgeObject then
    begin
      RoleNames := nil;
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        Insert(RoleCaption(Role), RoleNames, Length(RoleNames));
      FRoleBox := AddChoiceRow(rsPropRole, RoleNames, @RoleChange, RowGap);
      FMarkedOnText := AddTextRow(rsPropMarkedOn, '', RowGap);
    end;
    // A repeat's points share the repeat's marker
    if ((Node is TPointObject) and not (Node is TRepeatPoint)) or (Node is TRepeatObject) then
    begin
      // In the order of TPointMarker
      FMarkerBox := AddChoiceRow(rsPropMarker, [rsPropMarkerPlain, rsPropMarkerHole, rsPropMarkerButton, rsPropMarkerMatch], @MarkerChange, RowGap);
      for Index := 0 to Node.FieldCount - 1 do
        if Node.Fields[Index].Name = MarkerSizeField then
          AddEditRow(FieldCaption(MarkerSizeField), frFormula, MarkerSizeField);
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
  Node := SelectedNode;
  if not Assigned(Node) then
    Exit;
  if FRows[Edit.Tag].Kind = frName then
    Result := Node.DisplayName
  else
    Result := FDocument.Pattern.FormulaText(Node, FRows[Edit.Tag].FieldName);
end;

procedure TPropertiesPanel.RefreshValues;
var
  Node: TEvalNode;
  Row: TFieldRow;
begin
  Node := SelectedNode;
  if not Assigned(Node) then
    Exit;
  // A field being typed in keeps its text, and the reason it was refused
  for Row in FRows do
    if not KeepsText(Row.Edit) then
    begin
      SetEditText(Row.Edit, OriginalText(Row.Edit));
      if not FCommitting then
        ClearRefusal(Row.Edit);
    end;
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
  if Assigned(FProblem) and not FCommitting then
    if Node.State = esValid then
      FProblem.Caption := ''
    else
      FProblem.Caption := Node.Message;
end;

procedure TPropertiesPanel.CommitEdit(Edit: TEdit);
var
  Node: TEvalNode;
  Row: TFieldRow;
  Reason: string;
  ErrorPos: integer;
  Done: boolean;
begin
  Node := SelectedNode;
  if not Assigned(Node) then
    Exit;
  if Edit.Text = OriginalText(Edit) then
  begin
    ClearRefusal(Edit);
    Exit;
  end;
  Row := FRows[Edit.Tag];
  // Emptying an edge's own allowance removes it, which takes its row away,
  // so it waits until this edit's handler has returned
  if (Row.Kind = frFormula) and (Node is TPieceObject) and (Trim(Edit.Text) = '') and
    (TPieceObject(Node).OverridePathIndex(Row.FieldName) >= 0) then
  begin
    QueueChange(qcRemoveAllowance, TPieceObject(Node).OverridePathIndex(Row.FieldName));
    Exit;
  end;
  if Row.Kind = frName then
  begin
    BeginEdit(rsPropRename);
    Done := FDocument.Pattern.Rename(Node, Edit.Text);
  end
  else
  begin
    BeginEdit(Format(rsPropEdit, [FieldCaption(Row.FieldName)]));
    Done := FDocument.Pattern.SetFormula(Node, Row.FieldName, Edit.Text);
  end;
  Reason := FDocument.Pattern.LastError;
  ErrorPos := FDocument.Pattern.LastErrorPos;
  EndEdit(Done);
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
var
  Row: TFieldRow;
begin
  // A hidden tab or side panel cannot take the focus, and SetFocus would raise
  for Row in FRows do
    if (Row.Kind = frName) and Row.Edit.CanFocus then
    begin
      Row.Edit.SetFocus;
      Row.Edit.SelectAll;
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

// The name field is not a formula
procedure TPropertiesPanel.UpdateCompletion(Edit: TEdit; Explicit: boolean);
begin
  if not Assigned(FDocument) or (FRows[Edit.Tag].Kind <> frFormula) then
    Exit;
  if not Assigned(FCompleter) then
    FCompleter := TFormulaCompleter.Create(Self);
  FCompleter.Update(Edit, FDocument.Pattern, SelectedNode, Explicit);
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
  // In the order of TTextAlign
  FNoteAlignBox := AddChoiceRow(rsPropNoteAlign, [rsPropNoteAlignLeft, rsPropNoteAlignCentre, rsPropNoteAlignRight], @NoteLookChange, RowGap);
  FNoteBoxCheck := TCheckBox.Create(Self);
  FNoteBoxCheck.Caption := rsPropNoteBoxCaption;
  FNoteBoxCheck.OnClick := @NoteLookChange;
  AddRow(rsPropNoteBox, FNoteBoxCheck, RowGap);
  // A free note has nothing to point at
  if Note.Anchor <> naFree then
    // In the order of TNoteLeader
    FNoteLeaderBox := AddChoiceRow(rsPropNoteLeader, [rsPropNoteLeaderNone, rsPropNoteLeaderArrow, rsPropNoteLeaderDot, rsPropNoteLeaderLine],
      @NoteLookChange, RowGap);
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
  FFilling := True;
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
    FFilling := False;
  end;
end;

// The memo's own line breaks are stored as line feeds. A draft value that
// does not parse keeps the text as typed, with the reason.
procedure TPropertiesPanel.CommitNoteText;
var
  Node: TEvalNode;
  NewText, Reason: string;
  Done: boolean;
begin
  Node := SelectedNode;
  if not Assigned(FNoteText) or not (Node is TNoteObject) then
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
  BeginEdit(rsPropChangeNoteText);
  Done := FDocument.Pattern.SetNoteText(TNoteObject(Node), NewText);
  Reason := FDocument.Pattern.LastError;
  EndEdit(Done);
  if not Done then
    FNoteRefusal.Caption := Reason;
  FNoteRefusal.Visible := not Done;
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
  Node := SelectedNode;
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
  if FFilling then
    Exit;
  Node := SelectedNode;
  if not (Node is TNoteObject) then
    Exit;
  Note := TNoteObject(Node);
  Leader := Note.Leader;
  if Assigned(FNoteLeaderBox) and (FNoteLeaderBox.ItemIndex >= 0) then
    Leader := TNoteLeader(FNoteLeaderBox.ItemIndex);
  if (Leader = Note.Leader) and (Ord(Note.Align) = FNoteAlignBox.ItemIndex) and (Note.Boxed = FNoteBoxCheck.Checked) then
    Exit;
  BeginEdit(rsPropChangeNoteLook);
  FDocument.Pattern.SetNoteAlign(Note, TTextAlign(Max(0, FNoteAlignBox.ItemIndex)));
  FDocument.Pattern.SetNoteBoxed(Note, FNoteBoxCheck.Checked);
  Reason := '';
  if not FDocument.Pattern.SetNoteLeader(Note, Leader) then
    Reason := FDocument.Pattern.LastError;
  EndEdit(Reason = '');
  if (Reason <> '') and Assigned(FOnMessage) then
    FOnMessage(Self, Reason);
end;

procedure TPropertiesPanel.NoteSizeChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFilling then
    Exit;
  Node := SelectedNode;
  if not (Node is TNoteObject) or SameValue(TNoteObject(Node).Size, FNoteSize.Value) then
    Exit;
  BeginEdit(rsPropChangeNoteSize);
  EndEdit(FDocument.Pattern.SetNoteSize(TNoteObject(Node), FNoteSize.Value), 'notesize:' + FKey);
end;

procedure TPropertiesPanel.NotePrintClick(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFilling then
    Exit;
  Node := SelectedNode;
  if not (Node is TNoteObject) or (TNoteObject(Node).Print = FNotePrint.Checked) then
    Exit;
  BeginEdit(rsPropChangeNotePrint);
  FDocument.Pattern.SetNotePrint(TNoteObject(Node), FNotePrint.Checked);
  EndEdit(True);
end;

procedure TPropertiesPanel.FreeClick(Sender: TObject);
var
  Node: TEvalNode;
  Reason: string;
begin
  Node := SelectedNode;
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
  Node := SelectedNode;
  if not (Node is TSeamObject) then
    Exit;
  BeginEdit(rsPropFlipSeam);
  TSeamObject(Node).Reversed := not TSeamObject(Node).Reversed;
  EndEdit(True);
end;

// Only straight edges can be a fold, so only those are offered
procedure TPropertiesPanel.AddPieceRows(Piece: TPieceObject);
var
  Entry: TPieceEdge;
  Edge: TEvalNode;
  Index: integer;
  FoldNames, AllowanceNames: TStringArray;
begin
  FCutEdit := TSpinEdit.Create(Self);
  FCutEdit.MinValue := 1;
  FCutEdit.MaxValue := MaxCutCount;
  FCutEdit.OnChange := @CutChange;
  AddRow(rsPropCut, FCutEdit, RowGap);
  FMirrorBox := TCheckBox.Create(Self);
  FMirrorBox.OnChange := @CutChange;
  AddRow(rsPropMirrored, FMirrorBox, RowGap);
  FoldNames := nil;
  Insert(rsPropNoFold, FoldNames, 0);
  Insert('', FFoldKeys, 0);
  for Entry in Piece.Path do
  begin
    Edge := FDocument.Pattern.FindNode(Entry.EdgeKey);
    if IsStraightEdge(TEdgeObject(Edge)) then
    begin
      Insert(Edge.DisplayName, FoldNames, Length(FoldNames));
      Insert(Entry.EdgeKey, FFoldKeys, Length(FFoldKeys));
    end;
  end;
  FFoldBox := AddChoiceRow(rsPropFold, FoldNames, @FoldChange, RowGap);
  AllowanceNames := nil;
  Insert(rsPropOwnAllowancePrompt, AllowanceNames, 0);
  for Index := 0 to High(Piece.Path) do
    if not Piece.HasOverride(Index) then
    begin
      Insert(FDocument.Pattern.FindNode(Piece.Path[Index].EdgeKey).DisplayName, AllowanceNames, Length(AllowanceNames));
      Insert(Index, FAllowanceIndexes, Length(FAllowanceIndexes));
    end;
  FAllowanceBox := AddChoiceRow(rsPropOwnAllowance, AllowanceNames, @AllowanceChange, RowGap);
  FAllowanceBox.Hint := rsPropOwnAllowanceHint;
  FAllowanceBox.ShowHint := True;
  FAllowanceBox.ItemIndex := 0;
  FAllowanceBox.Enabled := Length(FAllowanceIndexes) > 0;
  AddGrainRows(Piece);
  FMaterialBox := AddChoiceRow(rsPropMaterial, [], @MaterialChange, RowGap);
  // In the order of TPieceFillStyle
  FFillStyleBox := AddChoiceRow(rsPropFillStyle, [rsPropFromMaterial, rsPropFillTint, rsPropFillHatch], @FillStyleChange, RowGap);
  FFillColorBox := AddChoiceRow(rsPropFillColor, [], @FillColorChange, RowGap);
end;

procedure TPropertiesPanel.RefreshPieceRows(Piece: TPieceObject);
var
  Index: integer;
begin
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
procedure TPropertiesPanel.RefreshMaterialRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
begin
  Pattern := FDocument.Pattern;
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

procedure TPropertiesPanel.MaterialChange(Sender: TObject);
var
  Node: TEvalNode;
  Material: TPatternMaterial;
begin
  Node := SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FMaterialBox.ItemIndex < 0) then
    Exit;
  Material := nil;
  if FMaterialBox.ItemIndex < FDocument.Pattern.MaterialCount then
    Material := FDocument.Pattern.Materials[FMaterialBox.ItemIndex];
  BeginEdit(rsPropChangeMaterial);
  FDocument.Pattern.SetPieceMaterial(TPieceObject(Node), Material);
  EndEdit(True);
  RefreshPieceRows(TPieceObject(SelectedNode));
end;

procedure TPropertiesPanel.ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
var
  Node: TEvalNode;
begin
  Node := SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  BeginEdit(rsPropChangeFill);
  EndEdit(FDocument.Pattern.SetPieceFill(TPieceObject(Node), AColor, Style));
  RefreshPieceRows(TPieceObject(SelectedNode));
end;

procedure TPropertiesPanel.FillStyleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FFillStyleBox.ItemIndex < 0) then
    Exit;
  ChangePieceFill(TPieceObject(Node).FillColor, TPieceFillStyle(FFillStyleBox.ItemIndex));
end;

procedure TPropertiesPanel.FillColorChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  Chosen: string;
begin
  Node := SelectedNode;
  if FFilling or not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if FFillColorBox.ItemIndex = 0 then
    ChangePieceFill('', Piece.FillStyle)
  else if FFillColorBox.ItemIndex = FFillColorBox.Items.Count - 1 then
  begin
    Chosen := Piece.FillColor;
    if Chosen = '' then
      Chosen := FDocument.Pattern.Materials[0].Color;
    if ChooseMaterialColor(Self, Chosen) then
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
  if FFilling then
    Exit;
  Node := SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if (Piece.CutCount = FCutEdit.Value) and (Piece.Mirrored = FMirrorBox.Checked) then
    Exit;
  BeginEdit(rsPropChangeCut);
  EndEdit(FDocument.Pattern.SetCut(Piece, FCutEdit.Value, FMirrorBox.Checked), 'cut:' + FKey);
end;

procedure TPropertiesPanel.RefreshTransformRows(Node: TEvalNode);
begin
  if Assigned(FMadeByText) then
    FMadeByText.Caption := FDocument.Pattern.FindNode(CopyTransformKey(Node)).DisplayName;
end;

// Changing type replaces the object and rebuilds the panel, box and all
procedure TPropertiesPanel.TypeChange(Sender: TObject);
begin
  QueueChange(qcConvertType, FTypeBox.ItemIndex);
end;

procedure TPropertiesPanel.ConvertType(ItemIndex: integer);
var
  Node: TEvalNode;
  Wanted, Reason: string;
  Done: boolean;
begin
  if not Assigned(FTypeBox) then
    Exit;
  Node := SelectedNode;
  if not (Node is TEdgeObject) or (ItemIndex < 0) or (ItemIndex >= FTypeBox.Items.Count) then
    Exit;
  Wanted := FTypeBox.Items[ItemIndex];
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
  Node := SelectedNode;
  if not (Node is TPieceObject) or (TPieceObject(Node).FoldEdgeKey = FFoldKeys[FFoldBox.ItemIndex]) then
    Exit;
  BeginEdit(rsPropChangeFold);
  EndEdit(FDocument.Pattern.SetFoldEdge(TPieceObject(Node), FFoldKeys[FFoldBox.ItemIndex]));
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
  FEndsBox := AddChoiceRow(rsPropEnds, [rsPropEndsInclude, rsPropEndsExclude], @EndsChange, RowGap);
end;

procedure TPropertiesPanel.EndsChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := SelectedNode;
  if not (Node is TRepeatObject) or (Ord(not TRepeatObject(Node).IncludeEnds) = FEndsBox.ItemIndex) then
    Exit;
  BeginEdit(rsPropChangeEnds);
  TRepeatObject(Node).IncludeEnds := FEndsBox.ItemIndex = 0;
  EndEdit(True);
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
  Node := SelectedNode;
  if not (Node is TDraftObject) or (Ord(TDraftObject(Node).Marker) = FMarkerBox.ItemIndex) then
    Exit;
  BeginEdit(rsPropChangeMarker);
  FDocument.Pattern.SetMarker(Node.Key, TPointMarker(FMarkerBox.ItemIndex));
  EndEdit(True);
end;

procedure TPropertiesPanel.RoleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := SelectedNode;
  if not (Node is TEdgeObject) or (Ord(TEdgeObject(Node).Role) = FRoleBox.ItemIndex) then
    Exit;
  BeginEdit(rsPropChangeRole);
  FDocument.Pattern.SetEdgeRole(TEdgeObject(Node), TEdgeRole(FRoleBox.ItemIndex));
  EndEdit(True);
end;

// An edge's own allowance is named after its edge, which its field is not
function TPropertiesPanel.FieldRowCaption(Node: TEvalNode; const FieldName: string): string;
var
  PathIndex: integer;
begin
  PathIndex := -1;
  if Node is TPieceObject then
    PathIndex := TPieceObject(Node).OverridePathIndex(FieldName);
  if PathIndex < 0 then
    Exit(FieldCaption(FieldName));
  Result := Format(rsPropEdgeAllowance, [FDocument.Pattern.FindNode(TPieceObject(Node).Path[PathIndex].EdgeKey).DisplayName]);
end;

// Adding a field rebuilds the panel, box and all
procedure TPropertiesPanel.AllowanceChange(Sender: TObject);
begin
  if FAllowanceBox.ItemIndex <= 0 then
    Exit;
  QueueChange(qcAddAllowance, FAllowanceIndexes[FAllowanceBox.ItemIndex - 1]);
end;

// Starts at the piece's own allowance, with its row ready to type in
procedure TPropertiesPanel.AddEdgeAllowance(PathIndex: integer);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  RowIndex: integer;
begin
  Node := SelectedNode;
  if not (Node is TPieceObject) or (PathIndex > High(TPieceObject(Node).Path)) then
    Exit;
  Piece := TPieceObject(Node);
  FDocument.BeginChange(rsPropAddEdgeAllowance);
  FDocument.Commit(FDocument.Pattern.SetEdgeAllowance(Piece, PathIndex, FDocument.Pattern.FormulaText(Piece, PieceAllowanceField)));
  // The commit rebuilt the panel and may have replaced the piece
  Node := SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  RowIndex := FormulaRowOf(TPieceObject(Node).OverrideField(PathIndex));
  if RowIndex >= 0 then
  begin
    FRows[RowIndex].Edit.SetFocus;
    FRows[RowIndex].Edit.SelectAll;
  end;
end;

procedure TPropertiesPanel.RemoveEdgeAllowance(PathIndex: integer);
var
  Node: TEvalNode;
begin
  Node := SelectedNode;
  if not (Node is TPieceObject) or (PathIndex > High(TPieceObject(Node).Path)) then
    Exit;
  FDocument.BeginChange(rsPropRemoveEdgeAllowance);
  FDocument.Commit(FDocument.Pattern.SetEdgeAllowance(TPieceObject(Node), PathIndex, ''));
end;

procedure TPropertiesPanel.AddGrainRows(Piece: TPieceObject);
var
  Point: TPointObject;
  Index: integer;
  PointNames: TStringArray;
begin
  // In the order of TGrainKind
  FGrainBox := AddChoiceRow(rsPropGrainline, [rsPropGrainNone, rsPropGrainAngle, rsPropGrainPoints], @GrainChange, RowGap);
  for Index := 0 to Piece.FieldCount - 1 do
    if Piece.Fields[Index].Name = GrainAngleField then
      AddEditRow(FieldRowCaption(Piece, GrainAngleField), frFormula, GrainAngleField);
  PointNames := nil;
  Insert(rsPropGrainChoose, PointNames, 0);
  Insert('', FGrainPointKeys, 0);
  for Point in FDocument.Pattern.AllPoints do
  begin
    Insert(Point.DisplayName, PointNames, Length(PointNames));
    Insert(Point.Key, FGrainPointKeys, Length(FGrainPointKeys));
  end;
  FGrainStartBox := AddChoiceRow(rsPropGrainFrom, PointNames, @GrainChange, RowGap);
  FGrainEndBox := AddChoiceRow(rsPropGrainTo, PointNames, @GrainChange, RowGap);
end;

procedure TPropertiesPanel.RefreshGrainRows(Piece: TPieceObject);

  function PlaceOf(const Key: string): integer;
  begin
    for Result := 0 to High(FGrainPointKeys) do
      if (Key <> '') and (FGrainPointKeys[Result] = Key) then
        Exit;
    Result := 0;
  end;

begin
  if not Assigned(FGrainBox) then
    Exit;
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
procedure TPropertiesPanel.GrainChange(Sender: TObject);
var
  Points: boolean;
begin
  if FFilling or not Assigned(FGrainBox) then
    Exit;
  Points := FGrainBox.ItemIndex = Ord(gkPoints);
  FGrainStartBox.Enabled := Points;
  FGrainEndBox.Enabled := Points;
  if Points and ((FGrainStartBox.ItemIndex <= 0) or (FGrainEndBox.ItemIndex <= 0)) then
    Exit;
  QueueChange(qcGrain, FGrainBox.ItemIndex);
end;

procedure TPropertiesPanel.ChangeGrain(Kind: TGrainKind);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  Reason: string;
  Done: boolean;
begin
  if not Assigned(FGrainBox) then
    Exit;
  Node := SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  FDocument.BeginChange(rsPropChangeGrainline);
  case Kind of
    gkNone:
    begin
      FDocument.Pattern.ClearGrain(Piece);
      Done := True;
    end;
    gkAngle:
      if Piece.GrainKind = gkAngle then
        Done := True
      else
        Done := FDocument.Pattern.SetGrainAngle(Piece, DefaultGrainAngle);
    else
      Done := FDocument.Pattern.SetGrainPoints(Piece, FGrainPointKeys[FGrainStartBox.ItemIndex], FGrainPointKeys[FGrainEndBox.ItemIndex]);
  end;
  Reason := FDocument.Pattern.LastError;
  FDocument.Commit(Done);
  if not Done and Assigned(FOnMessage) then
    FOnMessage(Self, Reason);
end;

end.
