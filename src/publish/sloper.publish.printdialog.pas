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

// The Print dialog: the printer, the copies and, for tiled pages, whether to
// print the cover alone first to measure the test square. It prints the same
// PDF as Export PDF, at 100%, through Sloper.Output.Printing.
unit Sloper.Publish.PrintDialog;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Output.Layout, Sloper.Output.Printing;

// Fills Request with what was chosen; False when cancelled
function ChoosePrintOptions(AOwner: TComponent; Layout: TLayout; out Request: TPrintRequest): boolean;

resourcestring
  rsPrintTitle = 'Print';
  rsPrintButton = 'Print';
  rsPrintPrinter = 'Printer';
  rsPrintSystemDefault = 'The system''s default printer';
  rsPrintCopies = 'Copies';
  rsPrintPagesGroup = 'Pages';
  rsPrintAllPages = 'All %d pages';
  rsPrintOnePage = 'The one sheet';
  rsPrintCoverOnly = 'The cover only, to measure the test square first';
  rsPrintTilesOnly = 'Pages 2 to %d, once the test square is right';
  rsPrintTrueSize = 'It prints at 100%, never scaled to fit. Measure the test square before you cut anything; ' +
    'if it is off, set the printer calibration in Preferences.';
  rsPrintWindowsNote = 'The PDF goes to the default PDF viewer, which prints it on the default printer. ' +
    'If the viewer asks, choose 100% or actual size, never fit to page.';

implementation

uses
  SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Spin, ButtonPanel, Sloper.UI.Spacing;

const
  DIALOG_WIDTH = 460;
  // Before the dialog is fitted to its contents when shown
  DIALOG_HEIGHT = 320;
  MAX_COPIES = 99;
  // At least the cover and one page, for the cover to be printed apart
  MIN_PAGES_TO_SPLIT = 2;
  // Between the Tops of controls stacked in order, in pixels
  STACK_STEP = 1000;

var
  // The printer chosen last, kept while the app runs
  LastPrinter: string = '';

type
  TLayoutPrintDialog = class(TForm)
  private
    FPrinters: TStringArray;
    FPrinterBox: TComboBox;
    FCopiesEdit: TSpinEdit;
    FPagesGroup: TRadioGroup;
    FButtons: TButtonPanel;
    FNextTop: integer;
    // The control stacked last, whose bottom the dialog is sized to show
    FLast: TControl;
    function AddLabel(const ACaption: string): TLabel;
    procedure Stack(Control: TControl);
    // Sizes the dialog to its contents
    procedure FitContents;
  protected
    procedure DoShow; override;
  public
    constructor Create(AOwner: TComponent; Layout: TLayout); reintroduce;
    function Request: TPrintRequest;
  end;

procedure TLayoutPrintDialog.Stack(Control: TControl);
begin
  Control.Parent := Self;
  // Top-aligned controls go in the order of Top, so each goes below the last
  Inc(FNextTop, STACK_STEP);
  Control.Top := FNextTop;
  Control.Align := alTop;
  Control.BorderSpacing.Left := ControlGap;
  Control.BorderSpacing.Right := ControlGap;
  Control.BorderSpacing.Top := ControlGap;
  FLast := Control;
end;

function TLayoutPrintDialog.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Stack(Result);
  Result.WordWrap := True;
  Result.Caption := ACaption;
end;

constructor TLayoutPrintDialog.Create(AOwner: TComponent; Layout: TLayout);
var
  DefaultPrinter, PrinterName: string;
  PageCount: integer;
begin
  inherited CreateNew(AOwner);
  Caption := rsPrintTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  Width := Scale96ToForm(DIALOG_WIDTH);
  Height := Scale96ToForm(DIALOG_HEIGHT);
  FButtons := TButtonPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.ShowButtons := [pbOK, pbCancel];
  SpaceButtons(FButtons);
  FButtons.OKButton.Caption := rsPrintButton;
  if CanChoosePrintOptions then
  begin
    AddLabel(rsPrintPrinter);
    FPrinterBox := TComboBox.Create(Self);
    Stack(FPrinterBox);
    FPrinterBox.Style := csDropDownList;
    ListPrinters(FPrinters, DefaultPrinter);
    if Length(FPrinters) = 0 then
      FPrinterBox.Items.Add(rsPrintSystemDefault);
    for PrinterName in FPrinters do
      FPrinterBox.Items.Add(PrinterName);
    FPrinterBox.ItemIndex := 0;
    if LastPrinter <> '' then
      DefaultPrinter := LastPrinter;
    if FPrinterBox.Items.IndexOf(DefaultPrinter) >= 0 then
      FPrinterBox.ItemIndex := FPrinterBox.Items.IndexOf(DefaultPrinter);
    AddLabel(rsPrintCopies);
    FCopiesEdit := TSpinEdit.Create(Self);
    Stack(FCopiesEdit);
    FCopiesEdit.MinValue := 1;
    FCopiesEdit.MaxValue := MAX_COPIES;
    FCopiesEdit.Value := 1;
    FPagesGroup := TRadioGroup.Create(Self);
    Stack(FPagesGroup);
    FPagesGroup.AutoSize := True;
    FPagesGroup.Caption := rsPrintPagesGroup;
    PageCount := PrintedPageCount(Layout);
    // In the order of TPrintPages
    if Layout.Output.Kind = okTiled then
      FPagesGroup.Items.Add(Format(rsPrintAllPages, [PageCount]))
    else
      FPagesGroup.Items.Add(rsPrintOnePage);
    if (Layout.Output.Kind = okTiled) and (PageCount >= MIN_PAGES_TO_SPLIT) then
    begin
      FPagesGroup.Items.Add(rsPrintCoverOnly);
      FPagesGroup.Items.Add(Format(rsPrintTilesOnly, [PageCount]));
    end;
    FPagesGroup.ItemIndex := Ord(ppAll);
    AddLabel(rsPrintTrueSize).BorderSpacing.Bottom := ControlGap;
  end
  else
    AddLabel(rsPrintWindowsNote).BorderSpacing.Bottom := ControlGap;
end;

// The sizes are only known once the controls are laid out with the real font,
// which can be larger than the screen resolution alone gives, so the form is
// not autosized: it measured the wrapped notes before they were wrapped. The
// width comes first, since wrapped notes are taller in a narrower dialog.
procedure TLayoutPrintDialog.FitContents;
var
  PreferredWidth, PreferredHeight, Room: integer;
begin
  if Assigned(FPagesGroup) then
  begin
    PreferredWidth := 0;
    PreferredHeight := 0;
    FPagesGroup.GetPreferredSize(PreferredWidth, PreferredHeight, True);
    Width := Width + Max(0, PreferredWidth - FPagesGroup.Width);
    // Laid out again at the new width before the notes are measured
    DisableAutoSizing;
    EnableAutoSizing;
  end;
  Room := FButtons.Top - FButtons.BorderSpacing.Around - FButtons.BorderSpacing.Top;
  ClientHeight := ClientHeight + FLast.Top + FLast.Height + FLast.BorderSpacing.Around + FLast.BorderSpacing.Bottom - Room;
end;

// Only a shown dialog is laid out, so it is fitted here and centred again
procedure TLayoutPrintDialog.DoShow;
begin
  inherited DoShow;
  FitContents;
  MoveToDefaultPosition;
end;

function TLayoutPrintDialog.Request: TPrintRequest;
begin
  Result := Default(TPrintRequest);
  Result.Copies := 1;
  Result.Pages := ppAll;
  if not Assigned(FPrinterBox) then
    Exit;
  if Length(FPrinters) > 0 then
    Result.Printer := FPrinters[FPrinterBox.ItemIndex];
  Result.Copies := FCopiesEdit.Value;
  Result.Pages := TPrintPages(FPagesGroup.ItemIndex);
end;

function ChoosePrintOptions(AOwner: TComponent; Layout: TLayout; out Request: TPrintRequest): boolean;
var
  Dialog: TLayoutPrintDialog;
begin
  Dialog := TLayoutPrintDialog.Create(AOwner, Layout);
  try
    Result := Dialog.ShowModal = mrOk;
    Request := Dialog.Request;
    Request.Title := ChangeFileExt(ExtractFileName(Layout.FileName), '');
    if Result and (Request.Printer <> '') then
      LastPrinter := Request.Printer;
  finally
    FreeAndNil(Dialog);
  end;
end;

end.
