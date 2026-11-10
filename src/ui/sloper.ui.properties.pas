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

// The panel keeps the row layout, the column divider and formula editing;
// the rows for each kind of object come from section objects, made for the
// selected object and freed on each rebuild.
unit Sloper.UI.Properties;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Generics.Collections, Controls, StdCtrls, Forms, Graphics, LCLType, Sloper.Core.Draft,
  Sloper.Core.Evaluator, Sloper.Document.PatternDocument, Sloper.UI.FormulaCompleter;

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

  // Where a section's rows go, top to bottom: every section adds its rows
  // for one place before any section adds rows for the next
  TSectionPlace = (spType, spName, spFields, spRows, spResult, spEnd);

  TPropertiesPanel = class;

  // The rows for one kind of object, with their controls, handlers and lists.
  // The panel makes the sections the selected object needs and frees them on
  // each rebuild, after freeing the controls, which belong to the panel. A
  // commit that does not go through BeginEdit, or a queued change, can rebuild
  // the panel and free the section whose code is running: such code keeps the
  // panel in a local first and uses only that afterwards.
  TPropertySection = class
  private
    FPanel: TPropertiesPanel;
  protected
    // Rows are being filled in, which is not the user changing them
    FFilling: boolean;
    property Panel: TPropertiesPanel read FPanel;
  public
    constructor Create(APanel: TPropertiesPanel); virtual;
    procedure Build(Node: TEvalNode; Place: TSectionPlace); virtual; abstract;
    // Shows the object's values in the rows already built
    procedure Refresh(Node: TEvalNode); virtual;
    // A field the section shows in its own rows, which the field rows leave out
    function OwnsField(Node: TEvalNode; const FieldName: string): boolean; virtual;
    // The caption of a field's row, or '' for the usual one
    function FieldRowCaption(Node: TEvalNode; const FieldName: string): string; virtual;
    // True when the section deals with committing this text to a field itself
    function TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean; virtual;
    // A change the section queued with the panel, now due
    procedure QueuedChangeDue(Change, Data: integer); virtual;
  end;

  TPropertySectionClass = class of TPropertySection;
  TPropertySectionList = specialize TObjectList<TPropertySection>;

  TPropertiesPanel = class(TScrollBox)
  private
    FDocument: TPatternDocument;
    FKey: string;
    FSelectionCount: integer;
    FNameShare: double;
    // The fields the controls were built for; a rebuild is needed when they change
    FFieldNames: TStringArray;
    FSections: TPropertySectionList;
    FDivider: TColumnDivider;
    FRows: array of TFieldRow;
    // The object a queued change is for, the section that asked, and the
    // change; one at a time
    FQueuedKey: string;
    FQueuedSection: TPropertySectionClass;
    FQueuedChange: integer;
    FQueuedData: integer;
    FOnMessage: TPropertiesMessageEvent;
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
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure QueuedChangeDue(Data: PtrInt);
    procedure AddSections(Node: TEvalNode);
    function FindSection(SectionClass: TPropertySectionClass): TPropertySection;
    procedure FreeRows;
    procedure HangBelowLast(Control: TControl);
    procedure Stack(Control: TControl);
    // The formula row of this field, or -1
    function FormulaRowOf(const FieldName: string): integer;
    function SectionOwnsField(Node: TEvalNode; const FieldName: string): boolean;
    function ColumnSpace: integer;
    function MinColumn: integer;
    procedure PositionDivider;
    procedure DividerDrag(Sender: TObject; NewLeft: integer);
    procedure SetNameShare(AShare: double);
    function RefusalRow(Edit: TEdit): TLabel;
    procedure ShowRefusal(Edit: TEdit; const Reason: string);
    procedure ClearRefusal(Edit: TEdit);
    procedure RefreshValues;
    function CurrentFieldNames: TStringArray;
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    procedure EditKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditChange(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure UpdateCompletion(Edit: TEdit; Explicit: boolean);
    procedure SetEditText(Edit: TEdit; const AText: string);
    function EditableKey(const Key: string): string;
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

    { For the sections }

    // The key of the object shown, or ''
    property SelectedKey: string read FKey;
    // The object shown, or nil
    function SelectedNode: TEvalNode;
    // Builds every row again for the object shown
    procedure Rebuild;
    // A change made from the panel: the document's notification while it
    // commits refreshes the values and keeps the controls
    procedure BeginEdit(const Description: string);
    // Records the change when Done, else puts the pattern back
    function EndEdit(Done: boolean; const MergeKey: string = ''): boolean;
    // A change that adds or removes rows, so it runs once the handler of the
    // control that asked has returned, through the section's QueuedChangeDue.
    // A later change replaces one still waiting.
    procedure QueueChange(Section: TPropertySection; Change, Data: integer);
    // Says why a change was refused, through OnMessage
    procedure Report(const AText: string);
    // A field being typed in keeps its text, unless undo or redo changed the pattern
    function KeepsText(Control: TWinControl): boolean;
    // A change from the panel is being committed
    property Committing: boolean read FCommitting;
    function AddLabel(const ACaption: string): TLabel;
    procedure AddRow(const ACaption: string; Value: TControl);
    function AddTextRow(const ACaption, AText: string): TGridLabel;
    // Items in the order of the value they stand for; the handler is set after
    // them, and the caller sets the choice
    function AddChoiceRow(const ACaption: string; const Items: array of string; Handler: TNotifyEvent): TComboBox;
    function AddEditRow(const ACaption: string; Kind: TFieldRowKind; const FieldName: string): TEdit;
    // Puts the cursor in this field's row, with its text selected
    procedure FocusFormulaRow(const FieldName: string);
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
  rsPropMadeBy = 'Made by';
  rsPropChangeType = 'Change edge type';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropChangeRole = 'Change role';

implementation

uses
  Math, Spin, Sloper.Core.EvalTypes, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Transform,
  Sloper.Core.Note, Sloper.Core.Settings, Sloper.UI.GridColumns, Sloper.UI.ObjectList, Sloper.UI.PieceProperties, Sloper.UI.PropertyText, Sloper.UI.Spacing;

type
  // Rows every object has: type, name and formula fields first; what made a
  // copy, the result and the problem last
  TCommonSection = class(TPropertySection)
  private
    FMadeByText: TGridLabel;
    FResult: TGridLabel;
    FProblem: TLabel;
    procedure AddFieldRows(Node: TEvalNode);
    procedure AddResultRows(Node: TEvalNode);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
  end;

  // A line, curve or arc: its type when it can change, its role and the
  // pieces it is marked on
  TEdgeSection = class(TPropertySection)
  private
    FTypeBox: TComboBox;
    FRoleBox: TComboBox;
    FMarkedOnText: TGridLabel;
    procedure TypeChange(Sender: TObject);
    // ItemIndex is the type box's choice
    procedure ConvertType(ItemIndex: integer);
    procedure RoleChange(Sender: TObject);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
    procedure QueuedChangeDue(Change, Data: integer); override;
  end;

  // A point's or repeat's marker, its size, and the pieces it is marked on
  TMarkerSection = class(TPropertySection)
  private
    FMarkerBox: TComboBox;
    FMarkedOnText: TGridLabel;
    procedure MarkerChange(Sender: TObject);
    procedure ChangeMarker(Marker: TPointMarker);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
    function OwnsField(Node: TEvalNode; const FieldName: string): boolean; override;
    procedure QueuedChangeDue(Change, Data: integer); override;
  end;

  // What a repeat runs between or along, and whether it includes the ends
  TRepeatSection = class(TPropertySection)
  private
    FEndsBox: TComboBox;
    procedure EndsChange(Sender: TObject);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
  end;

  // A seam's sides, its direction, and the difference in their lengths
  TSeamSection = class(TPropertySection)
  private
    FSideAText, FSideBText, FDifferenceText: TGridLabel;
    procedure FlipClick(Sender: TObject);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
  end;

  // A note's text, size, whether it prints, its look, and what it hangs from
  TNoteSection = class(TPropertySection)
  private
    FNoteText: TMemo;
    FNoteRefusal: TLabel;
    FNoteSize: TFloatSpinEdit;
    FNotePrint: TCheckBox;
    FNoteAnchorText: TGridLabel;
    FNoteLeaderBox, FNoteAlignBox: TComboBox;
    FNoteBoxCheck: TCheckBox;
    procedure AddTextRow;
    procedure AddRows(Note: TNoteObject);
    procedure CommitText;
    procedure TextExit(Sender: TObject);
    procedure TextKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure SizeChange(Sender: TObject);
    procedure PrintClick(Sender: TObject);
    procedure LookChange(Sender: TObject);
    procedure FreeClick(Sender: TObject);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
    function OwnsField(Node: TEvalNode; const FieldName: string): boolean; override;
    procedure FocusText;
  end;

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
  // At 96 pixels per inch
  DividerWidth96 = 8;
  MinColumn96 = 48;
  // A note's text field, at 96 pixels per inch
  NoteTextHeight96 = 64;
  NoteSizeStep = 1;
  // The edge and marker sections' queued changes
  QueuedConvertType = 0;
  QueuedMarker = 1;

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

// A line, curve or arc the user drew can change type; copies and parts follow other edges
function CanChangeType(Node: TEvalNode): boolean;
begin
  Result := (Node.ClassType = TLineObject) or (Node.ClassType = TCurveObject) or (Node.ClassType = TArcObject);
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

{ TPropertySection }

constructor TPropertySection.Create(APanel: TPropertiesPanel);
begin
  inherited Create;
  FPanel := APanel;
end;

procedure TPropertySection.Refresh(Node: TEvalNode);
begin
end;

function TPropertySection.OwnsField(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := False;
end;

function TPropertySection.FieldRowCaption(Node: TEvalNode; const FieldName: string): string;
begin
  Result := '';
end;

function TPropertySection.TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean;
begin
  Result := False;
end;

procedure TPropertySection.QueuedChangeDue(Change, Data: integer);
begin
end;

{ TPropertiesPanel }

constructor TPropertiesPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  FNameShare := DefaultNameColumnShare;
  HorzScrollBar.Visible := False;
  FSections := TPropertySectionList.Create(True);
  Rebuild;
end;

// The sections go after the controls, whose events may still reach them
destructor TPropertiesPanel.Destroy;
begin
  Application.RemoveAsyncCalls(Self);
  SetDocument(nil);
  inherited Destroy;
  FreeAndNil(FSections);
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

procedure TPropertiesPanel.Report(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

// The section is found again by its class when the change is due, since a
// rebuild in between frees the one that asked
procedure TPropertiesPanel.QueueChange(Section: TPropertySection; Change, Data: integer);
begin
  FQueuedKey := FKey;
  FQueuedSection := TPropertySectionClass(Section.ClassType);
  FQueuedChange := Change;
  FQueuedData := Data;
  Application.QueueAsyncCall(@QueuedChangeDue, 0);
end;

// Only for the object still shown; the first call to come runs the latest
// change and any other finds nothing to do
procedure TPropertiesPanel.QueuedChangeDue(Data: PtrInt);
var
  Section: TPropertySection;
begin
  if not Assigned(FDocument) or (FQueuedKey = '') or (FQueuedKey <> FKey) then
    Exit;
  FQueuedKey := '';
  Section := FindSection(FQueuedSection);
  if Assigned(Section) then
    Section.QueuedChangeDue(FQueuedChange, FQueuedData);
end;

function TPropertiesPanel.FindSection(SectionClass: TPropertySectionClass): TPropertySection;
begin
  for Result in FSections do
    if Result.ClassType = SectionClass then
      Exit;
  Result := nil;
end;

function TPropertiesPanel.KeepsText(Control: TWinControl): boolean;
begin
  Result := Control.Focused and not FRefreshFocused;
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

// The sections for this object, in the order their rows go in each place
procedure TPropertiesPanel.AddSections(Node: TEvalNode);
begin
  FSections.Add(TCommonSection.Create(Self));
  if Node is TEdgeObject then
    FSections.Add(TEdgeSection.Create(Self));
  // A repeat's points share the repeat's marker
  if ((Node is TPointObject) and not (Node is TRepeatPoint)) or (Node is TRepeatObject) then
    FSections.Add(TMarkerSection.Create(Self));
  if Node is TRepeatObject then
    FSections.Add(TRepeatSection.Create(Self));
  if Node is TPieceObject then
    FSections.Add(TPieceSection.Create(Self));
  if Node is TSeamObject then
    FSections.Add(TSeamSection.Create(Self));
  if Node is TNoteObject then
    FSections.Add(TNoteSection.Create(Self));
end;

// The controls go before the sections whose handlers they call. A focused
// field being freed would run its exit handler and commit mid-rebuild.
procedure TPropertiesPanel.FreeRows;
var
  Index: integer;
begin
  if Assigned(FCompleter) then
    FCompleter.Hide;
  for Index := 0 to ControlCount - 1 do
    if Controls[Index] is TEdit then
      TEdit(Controls[Index]).OnExit := nil
    else if Controls[Index] is TMemo then
      TMemo(Controls[Index]).OnExit := nil;
  while ControlCount > 0 do
    Controls[0].Free;
  FSections.Clear;
  FDivider := nil;
  FRows := nil;
  FFirstRow := nil;
  FLastRow := nil;
  FLastControl := nil;
end;

// Each control hangs below the one before, so sizes follow the widgetset's
// fonts and scaling and the order is explicit. A hidden control takes no
// room: the next one anchors through it.
procedure TPropertiesPanel.HangBelowLast(Control: TControl);
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
  Control.BorderSpacing.Top := ControlGap;
  FLastControl := Control;
end;

// A control across both columns
procedure TPropertiesPanel.Stack(Control: TControl);
begin
  Control.Parent := Self;
  Control.Anchors := [akLeft, akTop, akRight];
  Control.AnchorSideLeft.Control := Self;
  Control.AnchorSideLeft.Side := asrTop;
  Control.AnchorSideRight.Control := Self;
  Control.AnchorSideRight.Side := asrBottom;
  Control.BorderSpacing.Left := ControlGap;
  Control.BorderSpacing.Right := ControlGap;
  HangBelowLast(Control);
end;

function TPropertiesPanel.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Stack(Result);
end;

// A name in the left column beside Value in the right; the value sets the
// row's height and the divider sets where the columns meet
procedure TPropertiesPanel.AddRow(const ACaption: string; Value: TControl);
var
  NameLabel: TGridLabel;
begin
  Value.Parent := Self;
  Value.Anchors := [akLeft, akTop, akRight];
  Value.AnchorSideLeft.Control := FDivider;
  Value.AnchorSideLeft.Side := asrBottom;
  Value.AnchorSideRight.Control := Self;
  Value.AnchorSideRight.Side := asrBottom;
  Value.BorderSpacing.Right := ControlGap;
  HangBelowLast(Value);
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
  NameLabel.BorderSpacing.Left := ControlGap;
  if not Assigned(FFirstRow) then
    FFirstRow := Value;
  FLastRow := Value;
end;

function TPropertiesPanel.AddTextRow(const ACaption, AText: string): TGridLabel;
begin
  Result := TGridLabel.Create(Self);
  Result.Caption := AText;
  AddRow(ACaption, Result);
end;

function TPropertiesPanel.AddChoiceRow(const ACaption: string; const Items: array of string; Handler: TNotifyEvent): TComboBox;
var
  Item: string;
begin
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  for Item in Items do
    Result.Items.Add(Item);
  Result.OnChange := Handler;
  AddRow(ACaption, Result);
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
  AddRow(ACaption, Result);
  FRows[Index].Refusal := AddLabel('');
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

procedure TPropertiesPanel.FocusFormulaRow(const FieldName: string);
var
  RowIndex: integer;
begin
  RowIndex := FormulaRowOf(FieldName);
  if RowIndex < 0 then
    Exit;
  FRows[RowIndex].Edit.SetFocus;
  FRows[RowIndex].Edit.SelectAll;
end;

function TPropertiesPanel.SectionOwnsField(Node: TEvalNode; const FieldName: string): boolean;
var
  Section: TPropertySection;
begin
  for Section in FSections do
    if Section.OwnsField(Node, FieldName) then
      Exit(True);
  Result := False;
end;

// The width the two columns share
function TPropertiesPanel.ColumnSpace: integer;
begin
  Result := ClientWidth - 2 * ControlGap - FDivider.Width;
end;

function TPropertiesPanel.MinColumn: integer;
begin
  Result := Scale96ToForm(MinColumn96);
end;

procedure TPropertiesPanel.PositionDivider;
begin
  if Assigned(FDivider) then
    FDivider.Left := ControlGap + NameColumnWidth(ColumnSpace, MinColumn, FNameShare);
end;

procedure TPropertiesPanel.DividerDrag(Sender: TObject; NewLeft: integer);
begin
  FNameShare := NameShareAt(NewLeft - ControlGap, ColumnSpace, MinColumn);
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
  Place: TSectionPlace;
  Section: TPropertySection;
begin
  DisableAlign;
  try
    FreeRows;
    FFieldNames := CurrentFieldNames;
    Node := SelectedNode;
    if not Assigned(Node) then
    begin
      if FSelectionCount > 1 then
        AddLabel(Format(rsPropMany, [FSelectionCount]))
      else
        AddLabel(rsPropNothing);
      Exit;
    end;
    FDivider := TColumnDivider.Create(Self);
    FDivider.Width := Scale96ToForm(DividerWidth96);
    FDivider.Parent := Self;
    FDivider.OnDrag := @DividerDrag;
    AddSections(Node);
    for Place := Low(TSectionPlace) to High(TSectionPlace) do
      for Section in FSections do
        Section.Build(Node, Place);
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
  Section: TPropertySection;
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
  for Section in FSections do
    Section.Refresh(Node);
end;

procedure TPropertiesPanel.CommitEdit(Edit: TEdit);
var
  Node: TEvalNode;
  Row: TFieldRow;
  Section: TPropertySection;
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
  if Row.Kind = frFormula then
    for Section in FSections do
      if Section.TakesCommit(Node, Row.FieldName, Edit.Text) then
        Exit;
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
var
  Section: TPropertySection;
begin
  Section := FindSection(TNoteSection);
  if Assigned(Section) then
    TNoteSection(Section).FocusText;
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

{ TCommonSection }

procedure TCommonSection.Build(Node: TEvalNode; Place: TSectionPlace);
begin
  case Place of
    spType:
      if not CanChangeType(Node) then
        Panel.AddTextRow(rsPropType, TypeCaption(Node));
    spName:
      if Node is TRepeatPoint then
        Panel.AddTextRow(rsPropName, TRepeatPoint(Node).Name)
      else if Node is TDraftObject then
        Panel.AddEditRow(rsPropName, frName, '');
    spFields:
      AddFieldRows(Node);
    spResult:
      AddResultRows(Node);
    spEnd:
    begin
      FProblem := Panel.AddLabel('');
      FProblem.Font.Color := clRed;
    end;
  end;
end;

// A marker's size goes under the marker, on the objects that show one, and
// other sections show some fields in their own rows
procedure TCommonSection.AddFieldRows(Node: TEvalNode);
var
  Section: TPropertySection;
  FieldName, Caption: string;
  Index: integer;
begin
  for Index := 0 to Node.FieldCount - 1 do
  begin
    FieldName := Node.Fields[Index].Name;
    if (FieldName = MarkerSizeField) or Panel.SectionOwnsField(Node, FieldName) then
      Continue;
    Caption := '';
    for Section in Panel.FSections do
      if Caption = '' then
        Caption := Section.FieldRowCaption(Node, FieldName);
    if Caption = '' then
      Caption := FieldCaption(FieldName);
    Panel.AddEditRow(Caption, frFormula, FieldName);
  end;
end;

procedure TCommonSection.AddResultRows(Node: TEvalNode);
begin
  if CopyTransformKey(Node) <> '' then
    FMadeByText := Panel.AddTextRow(rsPropMadeBy, '');
  if Node is TPointObject then
    FResult := Panel.AddTextRow(rsPropPosition, '')
  else if Node is TEdgeObject then
    FResult := Panel.AddTextRow(rsPropLength, '')
  else if Node is TPieceObject then
    FResult := Panel.AddTextRow(rsPropPerimeter, '')
  else if Node is TSeamObject then
    FResult := Panel.AddTextRow(rsPropSeamLengths, '')
  else if Node is TNoteObject then
    FResult := Panel.AddTextRow(rsPropPosition, '');
end;

procedure TCommonSection.Refresh(Node: TEvalNode);
var
  Pattern: TPattern;
begin
  Pattern := Panel.Document.Pattern;
  if Assigned(FMadeByText) then
    FMadeByText.Caption := Pattern.FindNode(CopyTransformKey(Node)).DisplayName;
  if Assigned(FResult) then
    if (Node is TNoteObject) and Node.HasResult then
      FResult.Caption := PositionText(TNoteObject(Node).Position, Pattern.Units)
    else if Node is TDraftObject then
      FResult.Caption := ResultText(TDraftObject(Node), Pattern.Units)
    else
      FResult.Caption := '';
  if Assigned(FProblem) and not Panel.Committing then
    if Node.State = esValid then
      FProblem.Caption := ''
    else
      FProblem.Caption := Node.Message;
end;

{ TEdgeSection }

procedure TEdgeSection.Build(Node: TEvalNode; Place: TSectionPlace);
var
  Role: TEdgeRole;
  RoleNames: TStringArray;
begin
  case Place of
    spType:
      if CanChangeType(Node) then
      begin
        if Node is TArcObject then
          FTypeBox := Panel.AddChoiceRow(rsPropType, [rsTypeArc, rsTypeLine], nil)
        else
          FTypeBox := Panel.AddChoiceRow(rsPropType, [rsTypeLine, rsTypeCurve], nil);
        FTypeBox.ItemIndex := FTypeBox.Items.IndexOf(TypeCaption(Node));
        FTypeBox.OnChange := @TypeChange;
      end;
    spRows:
    begin
      RoleNames := nil;
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        Insert(RoleCaption(Role), RoleNames, Length(RoleNames));
      FRoleBox := Panel.AddChoiceRow(rsPropRole, RoleNames, @RoleChange);
      FMarkedOnText := Panel.AddTextRow(rsPropMarkedOn, '');
    end;
  end;
end;

procedure TEdgeSection.Refresh(Node: TEvalNode);
begin
  FRoleBox.ItemIndex := Ord(TEdgeObject(Node).Role);
  FMarkedOnText.Caption := MarkedOnText(Panel.Document.Pattern, TDraftObject(Node));
end;

// Changing type replaces the object and rebuilds the panel, box and all
procedure TEdgeSection.TypeChange(Sender: TObject);
begin
  Panel.QueueChange(Self, QueuedConvertType, FTypeBox.ItemIndex);
end;

procedure TEdgeSection.QueuedChangeDue(Change, Data: integer);
begin
  if Change = QueuedConvertType then
    ConvertType(Data);
end;

// The commit rebuilds the panel, which frees this section, so only the panel
// is used after it
procedure TEdgeSection.ConvertType(ItemIndex: integer);
var
  APanel: TPropertiesPanel;
  Pattern: TPattern;
  Node: TEvalNode;
  Wanted, Reason: string;
  Done: boolean;
begin
  if not Assigned(FTypeBox) then
    Exit;
  APanel := Panel;
  Node := APanel.SelectedNode;
  if not (Node is TEdgeObject) or (ItemIndex < 0) or (ItemIndex >= FTypeBox.Items.Count) then
    Exit;
  Wanted := FTypeBox.Items[ItemIndex];
  if Wanted = TypeCaption(Node) then
    Exit;
  Pattern := APanel.Document.Pattern;
  APanel.Document.BeginChange(rsPropChangeType);
  if Wanted = rsTypeLine then
    Done := Assigned(Pattern.ConvertToLine(TEdgeObject(Node)))
  else
    Done := Assigned(Pattern.ConvertToCurve(TEdgeObject(Node)));
  Reason := Pattern.LastError;
  if APanel.Document.Commit(Done) then
    Exit;
  // The box goes back to the type the edge still has
  APanel.Rebuild;
  APanel.Report(Reason);
end;

procedure TEdgeSection.RoleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TEdgeObject) or (Ord(TEdgeObject(Node).Role) = FRoleBox.ItemIndex) then
    Exit;
  Panel.BeginEdit(rsPropChangeRole);
  Panel.Document.Pattern.SetEdgeRole(TEdgeObject(Node), TEdgeRole(FRoleBox.ItemIndex));
  Panel.EndEdit(True);
end;

{ TMarkerSection }

procedure TMarkerSection.Build(Node: TEvalNode; Place: TSectionPlace);
var
  Index: integer;
begin
  if Place <> spRows then
    Exit;
  // In the order of TPointMarker
  FMarkerBox := Panel.AddChoiceRow(rsPropMarker, [rsPropMarkerPlain, rsPropMarkerHole, rsPropMarkerButton, rsPropMarkerMatch], @MarkerChange);
  for Index := 0 to Node.FieldCount - 1 do
    if Node.Fields[Index].Name = MarkerSizeField then
      Panel.AddEditRow(FieldCaption(MarkerSizeField), frFormula, MarkerSizeField);
  FMarkedOnText := Panel.AddTextRow(rsPropMarkedOn, '');
end;

function TMarkerSection.OwnsField(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := FieldName = MarkerSizeField;
end;

procedure TMarkerSection.Refresh(Node: TEvalNode);
begin
  FMarkerBox.ItemIndex := Ord(TDraftObject(Node).Marker);
  FMarkedOnText.Caption := MarkedOnText(Panel.Document.Pattern, TDraftObject(Node));
end;

// A plain point has no size, so changing to or from plain adds or removes
// the size's row and the change is queued
procedure TMarkerSection.MarkerChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TDraftObject) or (FMarkerBox.ItemIndex < 0) or (Ord(TDraftObject(Node).Marker) = FMarkerBox.ItemIndex) then
    Exit;
  Panel.QueueChange(Self, QueuedMarker, FMarkerBox.ItemIndex);
end;

procedure TMarkerSection.QueuedChangeDue(Change, Data: integer);
begin
  if Change = QueuedMarker then
    ChangeMarker(TPointMarker(Data));
end;

// Committed outside BeginEdit, so the panel rebuilds when the fields change,
// which frees this section: only the panel is used after it
procedure TMarkerSection.ChangeMarker(Marker: TPointMarker);
var
  APanel: TPropertiesPanel;
  Node: TEvalNode;
  Reason: string;
  Done: boolean;
begin
  APanel := Panel;
  Node := APanel.SelectedNode;
  if not (Node is TDraftObject) or (TDraftObject(Node).Marker = Marker) then
    Exit;
  APanel.Document.BeginChange(rsPropChangeMarker);
  Done := APanel.Document.Pattern.SetMarker(Node.Key, Marker);
  Reason := APanel.Document.Pattern.LastError;
  if APanel.Document.Commit(Done) then
    Exit;
  // The box goes back to the marker the object still has
  APanel.Rebuild;
  APanel.Report(Reason);
end;

{ TRepeatSection }

procedure TRepeatSection.Build(Node: TEvalNode; Place: TSectionPlace);

  function NameOf(const Key: string): string;
  var
    Found: TEvalNode;
  begin
    Found := Panel.Document.Pattern.FindNode(Key);
    if not Assigned(Found) then
      Result := Key
    else
      Result := Found.DisplayName;
  end;

var
  ARepeat: TRepeatObject;
begin
  if Place <> spRows then
    Exit;
  ARepeat := TRepeatObject(Node);
  if ARepeat.Edge <> '' then
    Panel.AddTextRow(rsPropRepeatEdge, NameOf(ARepeat.Edge))
  else
  begin
    Panel.AddTextRow(rsPropRepeatFrom, NameOf(ARepeat.FirstPoint));
    Panel.AddTextRow(rsPropRepeatTo, NameOf(ARepeat.LastPoint));
  end;
  FEndsBox := Panel.AddChoiceRow(rsPropEnds, [rsPropEndsInclude, rsPropEndsExclude], @EndsChange);
end;

procedure TRepeatSection.Refresh(Node: TEvalNode);
begin
  FEndsBox.ItemIndex := Ord(not TRepeatObject(Node).IncludeEnds);
end;

procedure TRepeatSection.EndsChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TRepeatObject) or (Ord(not TRepeatObject(Node).IncludeEnds) = FEndsBox.ItemIndex) then
    Exit;
  Panel.BeginEdit(rsPropChangeEnds);
  TRepeatObject(Node).IncludeEnds := FEndsBox.ItemIndex = 0;
  Panel.EndEdit(True);
end;

{ TSeamSection }

procedure TSeamSection.Build(Node: TEvalNode; Place: TSectionPlace);
var
  Flip: TButton;
begin
  case Place of
    spRows:
    begin
      FSideAText := Panel.AddTextRow(rsPropSideA, '');
      FSideBText := Panel.AddTextRow(rsPropSideB, '');
      Flip := TButton.Create(Panel);
      Flip.Caption := rsPropFlip;
      Flip.OnClick := @FlipClick;
      Panel.AddRow(rsPropDirection, Flip);
    end;
    // Under the lengths it compares
    spResult:
      FDifferenceText := Panel.AddTextRow(rsPropSeamDifference, '');
  end;
end;

procedure TSeamSection.Refresh(Node: TEvalNode);
var
  Seam: TSeamObject;
  Pattern: TPattern;
begin
  Seam := TSeamObject(Node);
  Pattern := Panel.Document.Pattern;
  FSideAText.Caption := SeamSideText(Pattern, Seam.SideA);
  FSideBText.Caption := SeamSideText(Pattern, Seam.SideB);
  if Seam.HasResult then
    FDifferenceText.Caption := SeamDifferenceText(Seam, Pattern.Units)
  else
    FDifferenceText.Caption := '';
end;

procedure TSeamSection.FlipClick(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if not (Node is TSeamObject) then
    Exit;
  Panel.BeginEdit(rsPropFlipSeam);
  TSeamObject(Node).Reversed := not TSeamObject(Node).Reversed;
  Panel.EndEdit(True);
end;

{ TNoteSection }

procedure TNoteSection.Build(Node: TEvalNode; Place: TSectionPlace);
begin
  case Place of
    spName: AddTextRow;
    spRows: AddRows(TNoteObject(Node));
  end;
end;

// Its draft values are part of its text
function TNoteSection.OwnsField(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := IsNoteValue(FieldName);
end;

// Enter adds a line; leaving the field commits it as one undo step
procedure TNoteSection.AddTextRow;
begin
  FNoteText := TMemo.Create(Panel);
  FNoteText.Height := Panel.Scale96ToForm(NoteTextHeight96);
  FNoteText.ScrollBars := ssAutoVertical;
  FNoteText.WantReturns := True;
  FNoteText.WordWrap := False;
  FNoteText.OnExit := @TextExit;
  FNoteText.OnKeyDown := @TextKeyDown;
  FNoteText.Hint := rsPropNoteTextHint;
  FNoteText.ShowHint := True;
  Panel.AddRow(rsPropNoteText, FNoteText);
  FNoteRefusal := Panel.AddLabel('');
  FNoteRefusal.Font.Color := clRed;
  FNoteRefusal.WordWrap := True;
  FNoteRefusal.Visible := False;
end;

procedure TNoteSection.AddRows(Note: TNoteObject);
var
  FreeButton: TButton;
begin
  FNoteSize := TFloatSpinEdit.Create(Panel);
  FNoteSize.MinValue := NoteSizeStep;
  FNoteSize.MaxValue := MaxNoteSize;
  FNoteSize.Increment := NoteSizeStep;
  FNoteSize.DecimalPlaces := 1;
  FNoteSize.OnChange := @SizeChange;
  Panel.AddRow(rsPropNoteSize, FNoteSize);
  FNotePrint := TCheckBox.Create(Panel);
  FNotePrint.Caption := rsPropNotePrintCaption;
  FNotePrint.OnClick := @PrintClick;
  Panel.AddRow(rsPropNotePrint, FNotePrint);
  // In the order of TTextAlign
  FNoteAlignBox := Panel.AddChoiceRow(rsPropNoteAlign, [rsPropNoteAlignLeft, rsPropNoteAlignCentre, rsPropNoteAlignRight], @LookChange);
  FNoteBoxCheck := TCheckBox.Create(Panel);
  FNoteBoxCheck.Caption := rsPropNoteBoxCaption;
  FNoteBoxCheck.OnClick := @LookChange;
  Panel.AddRow(rsPropNoteBox, FNoteBoxCheck);
  // A free note has nothing to point at
  if Note.Anchor <> naFree then
    // In the order of TNoteLeader
    FNoteLeaderBox := Panel.AddChoiceRow(rsPropNoteLeader, [rsPropNoteLeaderNone, rsPropNoteLeaderArrow, rsPropNoteLeaderDot,
      rsPropNoteLeaderLine], @LookChange);
  FNoteAnchorText := Panel.AddTextRow(rsPropNoteAnchor, '');
  if Note.Anchor <> naFree then
  begin
    FreeButton := TButton.Create(Panel);
    FreeButton.Caption := rsPropNoteFree;
    FreeButton.Hint := rsPropNoteFreeHint;
    FreeButton.ShowHint := True;
    FreeButton.OnClick := @FreeClick;
    Panel.AddRow('', FreeButton);
  end;
end;

// The text field keeps what is being typed in it
procedure TNoteSection.Refresh(Node: TEvalNode);
var
  Note: TNoteObject;
begin
  Note := TNoteObject(Node);
  FFilling := True;
  try
    if not Panel.KeepsText(FNoteText) then
    begin
      FNoteText.Text := Note.DisplayText(Panel.Document.Pattern.Resolver);
      FNoteRefusal.Visible := False;
    end;
    FNoteAlignBox.ItemIndex := Ord(Note.Align);
    FNoteBoxCheck.Checked := Note.Boxed;
    if Assigned(FNoteLeaderBox) then
      FNoteLeaderBox.ItemIndex := Ord(Note.Leader);
    if not FNoteSize.Focused then
      FNoteSize.Value := Note.Size;
    FNotePrint.Checked := Note.Print;
    FNoteAnchorText.Caption := NoteAnchorText(Panel.Document.Pattern, Note);
  finally
    FFilling := False;
  end;
end;

procedure TNoteSection.FocusText;
begin
  if FNoteText.CanFocus then
  begin
    FNoteText.SetFocus;
    FNoteText.SelectAll;
  end;
end;

// A draft value that does not parse keeps the text as typed, with the reason
procedure TNoteSection.CommitText;
var
  Node: TEvalNode;
  NewText, Reason: string;
  Done: boolean;
begin
  Node := Panel.SelectedNode;
  if not (Node is TNoteObject) then
    Exit;
  NewText := NoteTextFromField(FNoteText.Text);
  if NewText = TNoteObject(Node).DisplayText(Panel.Document.Pattern.Resolver) then
  begin
    FNoteRefusal.Visible := False;
    Exit;
  end;
  Panel.BeginEdit(rsPropChangeNoteText);
  Done := Panel.Document.Pattern.SetNoteText(TNoteObject(Node), NewText);
  Reason := Panel.Document.Pattern.LastError;
  Panel.EndEdit(Done);
  if not Done then
    FNoteRefusal.Caption := Reason;
  FNoteRefusal.Visible := not Done;
end;

procedure TNoteSection.TextExit(Sender: TObject);
begin
  CommitText;
end;

// Escape puts the text back
procedure TNoteSection.TextKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Node: TEvalNode;
begin
  if Key <> VK_ESCAPE then
    Exit;
  Node := Panel.SelectedNode;
  if Node is TNoteObject then
    FNoteText.Text := TNoteObject(Node).DisplayText(Panel.Document.Pattern.Resolver);
  FNoteRefusal.Visible := False;
  Key := 0;
end;

// The leader, alignment and box, as one undo step
procedure TNoteSection.LookChange(Sender: TObject);
var
  Node: TEvalNode;
  Note: TNoteObject;
  Pattern: TPattern;
  Leader: TNoteLeader;
  Reason: string;
begin
  if FFilling then
    Exit;
  Node := Panel.SelectedNode;
  if not (Node is TNoteObject) then
    Exit;
  Note := TNoteObject(Node);
  Pattern := Panel.Document.Pattern;
  Leader := Note.Leader;
  if Assigned(FNoteLeaderBox) and (FNoteLeaderBox.ItemIndex >= 0) then
    Leader := TNoteLeader(FNoteLeaderBox.ItemIndex);
  if (Leader = Note.Leader) and (Ord(Note.Align) = FNoteAlignBox.ItemIndex) and (Note.Boxed = FNoteBoxCheck.Checked) then
    Exit;
  Panel.BeginEdit(rsPropChangeNoteLook);
  Pattern.SetNoteAlign(Note, TTextAlign(Max(0, FNoteAlignBox.ItemIndex)));
  Pattern.SetNoteBoxed(Note, FNoteBoxCheck.Checked);
  Reason := '';
  if not Pattern.SetNoteLeader(Note, Leader) then
    Reason := Pattern.LastError;
  Panel.EndEdit(Reason = '');
  if Reason <> '' then
    Panel.Report(Reason);
end;

procedure TNoteSection.SizeChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFilling then
    Exit;
  Node := Panel.SelectedNode;
  if not (Node is TNoteObject) or SameValue(TNoteObject(Node).Size, FNoteSize.Value) then
    Exit;
  Panel.BeginEdit(rsPropChangeNoteSize);
  Panel.EndEdit(Panel.Document.Pattern.SetNoteSize(TNoteObject(Node), FNoteSize.Value), 'notesize:' + Panel.SelectedKey);
end;

procedure TNoteSection.PrintClick(Sender: TObject);
var
  Node: TEvalNode;
begin
  if FFilling then
    Exit;
  Node := Panel.SelectedNode;
  if not (Node is TNoteObject) or (TNoteObject(Node).Print = FNotePrint.Checked) then
    Exit;
  Panel.BeginEdit(rsPropChangeNotePrint);
  Panel.Document.Pattern.SetNotePrint(TNoteObject(Node), FNotePrint.Checked);
  Panel.EndEdit(True);
end;

// The commit rebuilds the panel, which frees this section, so only the panel
// is used after it
procedure TNoteSection.FreeClick(Sender: TObject);
var
  APanel: TPropertiesPanel;
  Node: TEvalNode;
  Reason: string;
begin
  APanel := Panel;
  Node := APanel.SelectedNode;
  if not (Node is TNoteObject) then
    Exit;
  APanel.Document.BeginChange(rsPropFreeNote);
  Reason := '';
  if not APanel.Document.Pattern.MakeNoteFree(TNoteObject(Node)) then
    Reason := APanel.Document.Pattern.LastError;
  APanel.Document.Commit(Reason = '');
  if Reason <> '' then
    APanel.Report(Reason);
end;

end.
