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

// The Materials dialog: the pattern's materials on the left, with New and
// Delete, and the selected one's name, colour, fill, allowance and size on
// the right. Each change is its own undo step, made at once so the canvas behind
// follows, so the dialog has only Close. A typed field commits on Enter
// or on leaving the field, and Escape puts it back; a refused one keeps its
// text, in red, with the reason under the fields. The dialog is modal, so the
// main window's Undo and Redo shortcuts cannot reach it: it handles them
// itself, leaving them to a field that holds uncommitted typing.
unit Sloper.UI.MaterialDialog;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ExtCtrls, Graphics, LCLType, Sloper.Document.PatternDocument,
  Sloper.UI.MaterialGrid, Sloper.UI.PanelEdits;

type
  TMaterialsDialog = class(TForm)
  private
    FDocument: TPatternDocument;
    FGrid: TMaterialGrid;
    FLeft: TPanel;
    FFields: TPanel;
    FNameEdit, FAllowanceEdit, FWidthEdit, FLengthEdit: TEdit;
    FSwatch: TPaintBox;
    FFillBox: TComboBox;
    FTurnsBox: TCheckBox;
    FUnitLabels: array of TLabel;
    FReason: TLabel;
    FDeleteButton, FColourButton: TButton;
    // While fields are filled from the pattern, so it reads as no edit
    FShowing: boolean;
    procedure BuildLeft;
    procedure BuildFields;
    function AddCaption(Host: TWinControl; const ACaption: string): TLabel;
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    function Current: integer;
    procedure ShowFields;
    procedure ShowField(Edit: TEdit; Field: TMaterialField);
    procedure Commit(Field: TMaterialField; const AText: string; Edit: TEdit);
    procedure ShowReason(const AText: string);
    procedure GridSelection(Sender: TObject; ACol, ARow: integer);
    procedure NewClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ColourClick(Sender: TObject);
    procedure SwatchPaint(Sender: TObject);
    procedure FillChange(Sender: TObject);
    procedure TurnsClick(Sender: TObject);
    function IsTyped(Control: TWinControl): boolean;
    procedure ClearRefused;
    procedure EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure EditExit(Sender: TObject);
    function HasUncommittedTyping: boolean;
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    function GetSplit: integer;
    procedure SetSplit(Width96: integer);
  public
    constructor CreateFor(AOwner: TComponent; ADocument: TPatternDocument; Index: integer);
    destructor Destroy; override;
    // The list's width at 96 pixels per inch, kept in the settings
    property Split: integer read GetSplit write SetSplit;
  end;

resourcestring
  rsMaterialsTitle = 'Materials';
  rsMaterialsNew = '&New';
  rsMaterialsNewHint = 'Add a material';
  rsMaterialsDelete = '&Delete';
  rsMaterialsDeleteHint = 'Delete this material, if no piece is cut from it';
  rsMaterialsName = '&Name';
  rsMaterialsColour = 'Colour';
  rsMaterialsChoose = '&Choose...';
  rsMaterialsFill = '&Fill';
  rsMaterialsAllowance = '&Allowance';
  rsMaterialsAllowanceHint = 'The seam allowance a piece takes when it goes on this material; empty for none';
  rsMaterialsWidth = '&Width';
  rsMaterialsWidthHint = 'How wide the material is; empty for no size. A piece wider than this is a problem';
  rsMaterialsLength = '&Length';
  rsMaterialsLengthHint = 'How long a sheet of it is, with a width; empty for a roll';
  rsMaterialsTurns = 'Allow &quarter turns (no grain)';
  rsMaterialsTurnsHint = 'Pieces may lie a quarter turn round on it, as on felt, foam or most leather boards';
  rsMaterialsClose = 'Close';

implementation

uses
  Math, Types, LCLIntf, Sloper.Core.Materials, Sloper.Core.Units, Sloper.UI.Spacing;

const
  DIALOG_WIDTH96 = 640;
  DIALOG_HEIGHT96 = 500;
  DEFAULT_SPLIT96 = 300;
  MIN_SPLIT96 = 160;
  FIELDS_WIDTH96 = 260;
  SWATCH_HEIGHT96 = 30;
  REFUSED_PAPER = TColor($D8D8FF);
  PROBLEM_INK = TColor($2020C0);

constructor TMaterialsDialog.CreateFor(AOwner: TComponent; ADocument: TPatternDocument; Index: integer);
var
  Bottom: TPanel;
  CloseButton: TButton;
  Splitter: TSplitter;
begin
  inherited CreateNew(AOwner);
  FDocument := ADocument;
  Caption := rsMaterialsTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsSizeable;
  Width := Scale96ToScreen(DIALOG_WIDTH96);
  Height := Scale96ToScreen(DIALOG_HEIGHT96);
  Constraints.MinWidth := Scale96ToScreen(MIN_SPLIT96 + FIELDS_WIDTH96);
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.BevelOuter := bvNone;
  Bottom.AutoSize := True;
  Bottom.BorderSpacing.Around := ControlGap;
  CloseButton := TButton.Create(Self);
  CloseButton.Parent := Bottom;
  CloseButton.Align := alRight;
  CloseButton.AutoSize := True;
  CloseButton.Caption := rsMaterialsClose;
  CloseButton.ModalResult := mrClose;
  CloseButton.Cancel := True;
  BuildLeft;
  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alLeft;
  Splitter.Left := FLeft.Left + FLeft.Width + 1;
  Splitter.MinSize := Scale96ToScreen(MIN_SPLIT96);
  BuildFields;
  FDocument.AddListener(@DocumentChanged);
  FGrid.ShowMaterials(FDocument.Pattern);
  FGrid.MaterialIndex := Max(Index, 0);
  ShowFields;
  ActiveControl := FGrid;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
end;

destructor TMaterialsDialog.Destroy;
begin
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  inherited Destroy;
end;

procedure TMaterialsDialog.BuildLeft;
var
  Buttons: TPanel;

  function AddButton(const ACaption, AHint: string; Click: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Buttons;
    Result.Align := alLeft;
    // Docked left to right in the order of their positions
    Result.Left := Buttons.ControlCount * 100;
    Result.AutoSize := True;
    Result.Caption := ACaption;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnClick := Click;
  end;

begin
  FLeft := TPanel.Create(Self);
  FLeft.Parent := Self;
  FLeft.Align := alLeft;
  FLeft.Width := Scale96ToScreen(DEFAULT_SPLIT96);
  FLeft.BevelOuter := bvNone;
  FLeft.BorderSpacing.Left := ControlGap;
  FLeft.BorderSpacing.Top := ControlGap;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := FLeft;
  Buttons.Align := alBottom;
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.BorderSpacing.Top := ControlGap;
  SpaceBetween(Buttons);
  AddButton(rsMaterialsNew, rsMaterialsNewHint, @NewClick);
  FDeleteButton := AddButton(rsMaterialsDelete, rsMaterialsDeleteHint, @DeleteClick);
  FGrid := TMaterialGrid.Create(Self);
  FGrid.Parent := FLeft;
  FGrid.Align := alClient;
  FGrid.OnSelection := @GridSelection;
end;

function TMaterialsDialog.AddCaption(Host: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Host;
  Result.Align := alTop;
  Result.Top := Host.ControlCount * 100;
  Result.BorderSpacing.Top := ControlGap;
  Result.Caption := ACaption;
end;

// One field under another, each under its caption
procedure TMaterialsDialog.BuildFields;
var
  Row: TPanel;
  UnitLabel: TLabel;

  function AddRow: TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := FFields;
    Result.Align := alTop;
    Result.Top := FFields.ControlCount * 100;
    Result.BevelOuter := bvNone;
    Result.AutoSize := True;
  end;

  function AddEdit(Host: TWinControl): TEdit;
  begin
    Result := TEdit.Create(Self);
    Result.Parent := Host;
    Result.Align := alTop;
    Result.Top := Host.ControlCount * 100;
    Result.OnKeyDown := @EditKeyDown;
    Result.OnExit := @EditExit;
  end;

  // A field with the pattern's unit after it
  function AddLength(const ACaption, AHint: string): TEdit;
  begin
    AddCaption(FFields, ACaption);
    Row := AddRow;
    UnitLabel := TLabel.Create(Self);
    UnitLabel.Parent := Row;
    UnitLabel.Align := alRight;
    UnitLabel.Layout := tlCenter;
    UnitLabel.BorderSpacing.Left := ControlGap;
    Insert(UnitLabel, FUnitLabels, Length(FUnitLabels));
    Result := AddEdit(Row);
    Result.Align := alClient;
    Result.Hint := AHint;
    Result.ShowHint := True;
  end;

begin
  FFields := TPanel.Create(Self);
  FFields.Parent := Self;
  FFields.Align := alClient;
  FFields.BevelOuter := bvNone;
  FFields.BorderSpacing.Around := ControlGap;
  SpaceBetween(FFields);
  AddCaption(FFields, rsMaterialsName).BorderSpacing.Top := 0;
  FNameEdit := AddEdit(FFields);

  AddCaption(FFields, rsMaterialsColour);
  Row := AddRow;
  // As tall as a button, not as the swatch would grow it
  Row.AutoSize := False;
  Row.Height := Scale96ToScreen(SWATCH_HEIGHT96);
  FColourButton := TButton.Create(Self);
  FColourButton.Parent := Row;
  FColourButton.Align := alRight;
  FColourButton.AutoSize := True;
  FColourButton.BorderSpacing.Left := ControlGap;
  FColourButton.Caption := rsMaterialsChoose;
  FColourButton.OnClick := @ColourClick;
  FSwatch := TPaintBox.Create(Self);
  FSwatch.Parent := Row;
  FSwatch.Align := alClient;
  FSwatch.OnPaint := @SwatchPaint;
  FSwatch.OnClick := @ColourClick;

  AddCaption(FFields, rsMaterialsFill);
  FFillBox := TComboBox.Create(Self);
  FFillBox.Parent := FFields;
  FFillBox.Align := alTop;
  FFillBox.Top := FFields.ControlCount * 100;
  FFillBox.Style := csDropDownList;
  FFillBox.Items.Add(MaterialFillCaption(ffTint));
  FFillBox.Items.Add(MaterialFillCaption(ffHatch));
  FFillBox.OnChange := @FillChange;

  FAllowanceEdit := AddLength(rsMaterialsAllowance, rsMaterialsAllowanceHint);
  FWidthEdit := AddLength(rsMaterialsWidth, rsMaterialsWidthHint);
  FLengthEdit := AddLength(rsMaterialsLength, rsMaterialsLengthHint);
  FTurnsBox := TCheckBox.Create(Self);
  FTurnsBox.Parent := FFields;
  FTurnsBox.Align := alTop;
  FTurnsBox.Top := FFields.ControlCount * 100;
  FTurnsBox.BorderSpacing.Top := ControlGap;
  FTurnsBox.Caption := rsMaterialsTurns;
  FTurnsBox.Hint := rsMaterialsTurnsHint;
  FTurnsBox.ShowHint := True;
  FTurnsBox.OnClick := @TurnsClick;

  FReason := AddCaption(FFields, '');
  FReason.WordWrap := True;
  FReason.Font.Color := PROBLEM_INK;
end;

function TMaterialsDialog.GetSplit: integer;
begin
  Result := ScaleScreenTo96(FLeft.Width);
end;

procedure TMaterialsDialog.SetSplit(Width96: integer);
begin
  if Width96 >= MIN_SPLIT96 then
    FLeft.Width := Scale96ToScreen(Width96);
end;

function TMaterialsDialog.Current: integer;
begin
  Result := FGrid.MaterialIndex;
end;

procedure TMaterialsDialog.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  FGrid.ShowMaterials(FDocument.Pattern);
  ShowFields;
end;

// A field holding a refused value keeps it until it is fixed or put back
procedure TMaterialsDialog.ShowField(Edit: TEdit; Field: TMaterialField);
begin
  if Edit.Color = REFUSED_PAPER then
    Exit;
  Edit.Text := MaterialFieldText(FDocument, Current, Field);
end;

procedure TMaterialsDialog.ShowFields;
var
  Index: integer;
  Has: boolean;
  UnitLabel: TLabel;
begin
  Index := Current;
  Has := Index >= 0;
  FShowing := True;
  try
    FFields.Enabled := Has;
    FDeleteButton.Enabled := Has and (FDocument.Pattern.MaterialCount > 1);
    for UnitLabel in FUnitLabels do
      UnitLabel.Caption := MEASURE_UNIT_NAMES[FDocument.Pattern.Units];
    ShowField(FNameEdit, mfName);
    ShowField(FAllowanceEdit, mfAllowance);
    ShowField(FWidthEdit, mfWidth);
    ShowField(FLengthEdit, mfLength);
    if Has then
    begin
      FFillBox.ItemIndex := Ord(FDocument.Pattern.Materials[Index].Fill);
      FTurnsBox.Checked := FDocument.Pattern.Materials[Index].AllowTurns;
    end
    else
    begin
      FFillBox.ItemIndex := -1;
      FTurnsBox.Checked := False;
    end;
  finally
    FShowing := False;
  end;
  FSwatch.Invalidate;
end;

procedure TMaterialsDialog.ShowReason(const AText: string);
begin
  FReason.Caption := AText;
end;

// Edit is the field the text came from, if any, to mark a refusal on
procedure TMaterialsDialog.Commit(Field: TMaterialField; const AText: string; Edit: TEdit);
var
  Reason: string;
  Done: boolean;
begin
  if FShowing or (Current < 0) then
    Exit;
  Done := CommitMaterialField(FDocument, Current, Field, AText, Reason);
  if Assigned(Edit) then
  begin
    if Done then
      Edit.Color := clDefault
    else
      Edit.Color := REFUSED_PAPER;
  end;
  if Done then
  begin
    ShowReason('');
    ShowFields;
  end
  else
    ShowReason(Reason);
end;

procedure TMaterialsDialog.GridSelection(Sender: TObject; ACol, ARow: integer);
begin
  if FGrid.Filling then
    Exit;
  // A refused value belonged to the material that was selected
  ClearRefused;
  ShowReason('');
  ShowFields;
end;

procedure TMaterialsDialog.NewClick(Sender: TObject);
var
  Index: integer;
begin
  Index := AddMaterialStep(FDocument);
  if Index < 0 then
    Exit;
  FGrid.MaterialIndex := Index;
  ShowFields;
  FNameEdit.SetFocus;
  FNameEdit.SelectAll;
end;

procedure TMaterialsDialog.DeleteClick(Sender: TObject);
var
  Reason: string;
begin
  if DeleteMaterialStep(FDocument, Current, Reason) then
    ShowReason('')
  else
    ShowReason(Reason);
end;

procedure TMaterialsDialog.ColourClick(Sender: TObject);
var
  Chosen: string;
begin
  if Current < 0 then
    Exit;
  Chosen := FDocument.Pattern.Materials[Current].Color;
  if ChooseMaterialColor(Self, Chosen) then
    Commit(mfColor, Chosen, nil);
end;

procedure TMaterialsDialog.SwatchPaint(Sender: TObject);
var
  Area: TRect;
  Index: integer;
begin
  Area := Rect(0, 0, FSwatch.Width, FSwatch.Height);
  Index := Current;
  FSwatch.Canvas.Pen.Color := clWindowFrame;
  if Index < 0 then
  begin
    FSwatch.Canvas.Brush.Color := clBtnFace;
    FSwatch.Canvas.Rectangle(Area);
    Exit;
  end;
  if FDocument.Pattern.Materials[Index].Fill = ffHatch then
  begin
    FSwatch.Canvas.Brush.Color := clWhite;
    FSwatch.Canvas.Rectangle(Area);
    InflateRect(Area, -1, -1);
    DrawSwatchHatching(FSwatch.Canvas, Area, MaterialHatchAngle(Index), SwatchColor(FDocument.Pattern.Materials[Index].Color));
  end
  else
  begin
    FSwatch.Canvas.Brush.Color := SwatchColor(FDocument.Pattern.Materials[Index].Color);
    FSwatch.Canvas.Rectangle(Area);
  end;
end;

procedure TMaterialsDialog.FillChange(Sender: TObject);
begin
  if FFillBox.ItemIndex >= 0 then
    Commit(mfFill, MATERIAL_FILL_NAMES[FFillBox.ItemIndex], nil);
end;

procedure TMaterialsDialog.TurnsClick(Sender: TObject);
begin
  Commit(mfAllowTurns, BoolToStr(FTurnsBox.Checked, 'true', 'false'), nil);
end;

function FieldOf(Dialog: TMaterialsDialog; Edit: TObject): TMaterialField;
begin
  if Edit = Dialog.FNameEdit then
    Result := mfName
  else if Edit = Dialog.FWidthEdit then
    Result := mfWidth
  else if Edit = Dialog.FLengthEdit then
    Result := mfLength
  else
    Result := mfAllowance;
end;

// One of the fields that are typed into
function TMaterialsDialog.IsTyped(Control: TWinControl): boolean;
begin
  Result := (Control = FNameEdit) or (Control = FAllowanceEdit) or (Control = FWidthEdit) or (Control = FLengthEdit);
end;

procedure TMaterialsDialog.ClearRefused;
begin
  FNameEdit.Color := clDefault;
  FAllowanceEdit.Color := clDefault;
  FWidthEdit.Color := clDefault;
  FLengthEdit.Color := clDefault;
end;

procedure TMaterialsDialog.EditKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
var
  Edit: TEdit;
  Original: string;
begin
  Edit := TEdit(Sender);
  case Key of
    VK_RETURN:
    begin
      Commit(FieldOf(Self, Edit), Edit.Text, Edit);
      Key := 0;
    end;
    VK_ESCAPE:
    begin
      // Escape closes the dialog only once the field holds no change
      Original := MaterialFieldText(FDocument, Current, FieldOf(Self, Edit));
      if (Edit.Text <> Original) or (Edit.Color = REFUSED_PAPER) then
      begin
        Edit.Color := clDefault;
        Edit.Text := Original;
        ShowReason('');
        Key := 0;
      end;
    end;
  end;
end;

procedure TMaterialsDialog.EditExit(Sender: TObject);
begin
  Commit(FieldOf(Self, Sender), TEdit(Sender).Text, TEdit(Sender));
end;

// The focused field differs from the material, or holds a refused value
function TMaterialsDialog.HasUncommittedTyping: boolean;
var
  Edit: TEdit;
begin
  Result := False;
  if not IsTyped(ActiveControl) then
    Exit;
  Edit := TEdit(ActiveControl);
  Result := (Edit.Color = REFUSED_PAPER) or (Edit.Text <> MaterialFieldText(FDocument, Current, FieldOf(Self, Edit)));
end;

// Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z undo and redo pattern changes, as in the
// main window; the fields refresh as the document changes
procedure TMaterialsDialog.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key <> VK_Z) or not (ssModifier in Shift) or (ssAlt in Shift) or HasUncommittedTyping then
    Exit;
  ClearRefused;
  ShowReason('');
  if ssShift in Shift then
    FDocument.Redo
  else
    FDocument.Undo;
  Key := 0;
end;

end.
