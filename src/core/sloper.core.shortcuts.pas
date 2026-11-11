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

// The keys and mouse actions of the three apps, for the apps themselves and
// the Keyboard shortcuts page. The apps take the keys of their menu commands
// and drafting tools from here; the other keys are handled in the canvases
// and listed here to be documented. No LCL dependency.
unit Sloper.Core.Shortcuts;

{$mode ObjFPC}{$H+}

interface

type
  TShortcutApp = (saDesign, saMeasurements, saPublish);
  TShortcutApps = set of TShortcutApp;

  TShortcutGroup = (sgFile, sgEdit, sgView, sgTools, sgCanvas, sgPanels, sgMouse);

  TShortcutKind = (
    skCommand,  // the app sets the key from this table
    skFixed,    // the app handles the keys in code; listed to be documented
    skMouse);   // a mouse action, perhaps with keys held

  TKeyCommand = (
    kcNew, kcOpen, kcSave, kcSaveAs, kcImport, kcExportMeasurements, kcExportPDF, kcOpenMeasurements, kcPublish, kcQuit,
    kcUndo, kcRedo, kcCut, kcCopy, kcPaste, kcPreferences,
    kcZoomIn, kcZoomOut, kcFit, kcTrueSize, kcRulers, kcReload,
    kcToolSelect, kcToolPoint, kcToolLine, kcToolCurve, kcToolCircle, kcToolRectangle, kcToolPiece, kcToolNotch,
    kcToolSeam, kcToolText, kcToolCallout,
    kcCancel, kcDelete, kcNudge, kcNudgeFar, kcShowLabels, kcSeamNextSide, kcSeamPreviousSide, kcMakeSeam,
    kcRemovePiece, kcClearSelection,
    kcEditCell, kcCommitCell, kcRevertCell,
    kcScroll, kcScrollSideways, kcWheelZoom, kcPublishWheelZoom, kcPanMiddle, kcPanSpace, kcCycle, kcExtendCurve, kcPickList,
    kcExcludePage);

  TShortcutModifier = (smMod, smShift, smAlt);
  TShortcutModifiers = set of TShortcutModifier;

  TShortcutInfo = record
    // Keys joined by +, such as Mod+Shift+S, where Mod is Ctrl, or Cmd on
    // macOS; a key is a letter, a digit or a name such as Comma or Delete
    Keys: string;
    Kind: TShortcutKind;
    Group: TShortcutGroup;
    Apps: TShortcutApps;
    Description: string;
  end;

const
  // The keys known by name; any other key is one letter or digit
  SHORTCUT_KEY_NAMES: array[0..12] of string = ('Comma', 'Plus', 'Minus', 'Delete', 'Escape', 'Enter', 'Tab', 'Space', 'Left',
    'Right', 'Up', 'Down', 'F2');

// Every key and mouse action, in the order the page lists them
function ShortcutInfo(Command: TKeyCommand): TShortcutInfo;
// Keys as one key press: the key, a letter, digit or one of SHORTCUT_KEY_NAMES,
// and the modifiers held; False when they are not, such as Arrows
function ParseShortcut(const Keys: string; out Key: string; out Modifiers: TShortcutModifiers): boolean;

resourcestring
  rsKeyNew = 'New file';
  rsKeyOpen = 'Open a file';
  rsKeySave = 'Save';
  rsKeySaveAs = 'Save under another name';
  rsKeyImport = 'Import a Valentina or Seamly2D file';
  rsKeyExportMeasurements = 'Export a Valentina or Seamly2D file';
  rsKeyExportPDF = 'Export the layout as a PDF';
  rsKeyOpenMeasurements = 'Open a measurement set for the pattern';
  rsKeyPublish = 'Lay out and print the pattern in the publish app';
  rsKeyQuit = 'Quit';
  rsKeyUndo = 'Undo';
  rsKeyRedo = 'Redo';
  rsKeyCut = 'Cut the selection, or text in a field';
  rsKeyCopy = 'Copy the selection, or text in a field';
  rsKeyPaste = 'Paste';
  rsKeyPreferences = 'Preferences';
  rsKeyZoomIn = 'Zoom in';
  rsKeyZoomOut = 'Zoom out';
  rsKeyFit = 'Fit everything in the window';
  rsKeyTrueSize = 'Show the pattern at its true size';
  rsKeyRulers = 'Show or hide the rulers';
  rsKeyReload = 'Read the patterns again';
  rsKeyToolSelect = 'Select tool';
  rsKeyToolPoint = 'Point tool';
  rsKeyToolLine = 'Line tool';
  rsKeyToolCurve = 'Curve tool';
  rsKeyToolCircle = 'Circle tool';
  rsKeyToolRectangle = 'Rectangle tool';
  rsKeyToolPiece = 'Piece tool';
  rsKeyToolNotch = 'Notch tool';
  rsKeyToolSeam = 'Seam tool';
  rsKeyToolText = 'Text tool';
  rsKeyToolCallout = 'Callout tool';
  rsKeyCancel = 'Cancel a drag or what the tool is doing; then go back to the Select tool; then clear the selection';
  rsKeyDelete = 'Delete the selection; Backspace does the same';
  rsKeyNudge = 'Move the selected points 1 mm';
  rsKeyNudgeFar = 'Move the selected points 10 mm';
  rsKeyShowLabels = 'Show every label while held';
  rsKeySeamNextSide = 'Seam tool: go on to the other side of the seam';
  rsKeySeamPreviousSide = 'Seam tool: go back to the first side';
  rsKeyMakeSeam = 'Seam tool: make the seam';
  rsKeyRemovePiece = 'Take the selected piece off the pages; Backspace does the same';
  rsKeyClearSelection = 'Cancel a drag, or clear the selection';
  rsKeyEditCell = 'Edit the cell, or start typing';
  rsKeyCommitCell = 'Keep the change to the cell';
  rsKeyRevertCell = 'Put the cell back as it was';
  rsKeyScroll = 'Scroll up and down';
  rsKeyScrollSideways = 'Scroll sideways';
  rsKeyWheelZoom = 'Zoom about the pointer';
  rsKeyPublishWheelZoom = 'Zoom about the pointer';
  rsKeyPanMiddle = 'Pan';
  rsKeyPanSpace = 'Pan';
  rsKeyCycle = 'Select the next of several lines in the same place; clicking again at the same spot does the same';
  rsKeyExtendCurve = 'With the Curve tool, carry the last curve on through the point, as one curve path';
  rsKeyPickList = 'With the Select tool, list everything under the pointer, to pick one; with a drawing tool, stop the ' +
    'line or curve';
  rsKeyExcludePage = 'Leave a page out of the print, or put it back';

implementation

uses
  SysUtils, StrUtils;

const
  ALL_APPS = [saDesign, saMeasurements, saPublish];

function Info(const AKeys: string; AKind: TShortcutKind; AGroup: TShortcutGroup; AApps: TShortcutApps;
  const ADescription: string): TShortcutInfo;
begin
  Result.Keys := AKeys;
  Result.Kind := AKind;
  Result.Group := AGroup;
  Result.Apps := AApps;
  Result.Description := ADescription;
end;

function ShortcutInfo(Command: TKeyCommand): TShortcutInfo;
begin
  case Command of
    kcNew: Result := Info('Mod+N', skCommand, sgFile, [saDesign, saMeasurements], rsKeyNew);
    kcOpen: Result := Info('Mod+O', skCommand, sgFile, ALL_APPS, rsKeyOpen);
    kcSave: Result := Info('Mod+S', skCommand, sgFile, ALL_APPS, rsKeySave);
    kcSaveAs: Result := Info('Mod+Shift+S', skCommand, sgFile, ALL_APPS, rsKeySaveAs);
    kcImport: Result := Info('Mod+I', skCommand, sgFile, [saMeasurements], rsKeyImport);
    kcExportMeasurements: Result := Info('Mod+E', skCommand, sgFile, [saMeasurements], rsKeyExportMeasurements);
    kcExportPDF: Result := Info('Mod+E', skCommand, sgFile, [saPublish], rsKeyExportPDF);
    kcOpenMeasurements: Result := Info('Mod+M', skCommand, sgFile, [saDesign], rsKeyOpenMeasurements);
    kcPublish: Result := Info('Mod+P', skCommand, sgFile, [saDesign], rsKeyPublish);
    kcQuit: Result := Info('Mod+Q', skCommand, sgFile, ALL_APPS, rsKeyQuit);
    kcUndo: Result := Info('Mod+Z', skCommand, sgEdit, ALL_APPS, rsKeyUndo);
    kcRedo: Result := Info('Mod+Shift+Z', skCommand, sgEdit, ALL_APPS, rsKeyRedo);
    kcCut: Result := Info('Mod+X', skCommand, sgEdit, [saDesign], rsKeyCut);
    kcCopy: Result := Info('Mod+C', skCommand, sgEdit, [saDesign], rsKeyCopy);
    kcPaste: Result := Info('Mod+V', skCommand, sgEdit, [saDesign], rsKeyPaste);
    kcPreferences: Result := Info('Mod+Comma', skCommand, sgEdit, ALL_APPS, rsKeyPreferences);
    kcZoomIn: Result := Info('Mod+Plus', skCommand, sgView, [saDesign], rsKeyZoomIn);
    kcZoomOut: Result := Info('Mod+Minus', skCommand, sgView, [saDesign], rsKeyZoomOut);
    kcFit: Result := Info('Mod+0', skCommand, sgView, [saDesign, saPublish], rsKeyFit);
    kcTrueSize: Result := Info('Mod+1', skCommand, sgView, [saDesign], rsKeyTrueSize);
    kcRulers: Result := Info('Mod+R', skCommand, sgView, [saDesign], rsKeyRulers);
    kcReload: Result := Info('Mod+R', skCommand, sgView, [saPublish], rsKeyReload);
    kcToolSelect: Result := Info('S', skCommand, sgTools, [saDesign], rsKeyToolSelect);
    kcToolPoint: Result := Info('P', skCommand, sgTools, [saDesign], rsKeyToolPoint);
    kcToolLine: Result := Info('L', skCommand, sgTools, [saDesign], rsKeyToolLine);
    kcToolCurve: Result := Info('C', skCommand, sgTools, [saDesign], rsKeyToolCurve);
    kcToolCircle: Result := Info('O', skCommand, sgTools, [saDesign], rsKeyToolCircle);
    kcToolRectangle: Result := Info('R', skCommand, sgTools, [saDesign], rsKeyToolRectangle);
    kcToolPiece: Result := Info('K', skCommand, sgTools, [saDesign], rsKeyToolPiece);
    kcToolNotch: Result := Info('T', skCommand, sgTools, [saDesign], rsKeyToolNotch);
    kcToolSeam: Result := Info('E', skCommand, sgTools, [saDesign], rsKeyToolSeam);
    kcToolText: Result := Info('X', skCommand, sgTools, [saDesign], rsKeyToolText);
    kcToolCallout: Result := Info('A', skCommand, sgTools, [saDesign], rsKeyToolCallout);
    kcCancel: Result := Info('Escape', skFixed, sgCanvas, [saDesign], rsKeyCancel);
    kcDelete: Result := Info('Delete', skFixed, sgCanvas, [saDesign], rsKeyDelete);
    kcNudge: Result := Info('Arrows', skFixed, sgCanvas, [saDesign], rsKeyNudge);
    kcNudgeFar: Result := Info('Shift+Arrows', skFixed, sgCanvas, [saDesign], rsKeyNudgeFar);
    kcShowLabels: Result := Info('N', skFixed, sgCanvas, [saDesign], rsKeyShowLabels);
    kcSeamNextSide: Result := Info('Tab', skFixed, sgCanvas, [saDesign], rsKeySeamNextSide);
    kcSeamPreviousSide: Result := Info('Shift+Tab', skFixed, sgCanvas, [saDesign], rsKeySeamPreviousSide);
    kcMakeSeam: Result := Info('Enter', skFixed, sgCanvas, [saDesign], rsKeyMakeSeam);
    kcRemovePiece: Result := Info('Delete', skFixed, sgCanvas, [saPublish], rsKeyRemovePiece);
    kcClearSelection: Result := Info('Escape', skFixed, sgCanvas, [saPublish], rsKeyClearSelection);
    kcEditCell: Result := Info('F2', skFixed, sgPanels, [saDesign, saMeasurements], rsKeyEditCell);
    kcCommitCell: Result := Info('Enter', skFixed, sgPanels, [saDesign, saMeasurements], rsKeyCommitCell);
    kcRevertCell: Result := Info('Escape', skFixed, sgPanels, [saDesign, saMeasurements], rsKeyRevertCell);
    kcScroll: Result := Info('Wheel', skMouse, sgMouse, [saDesign], rsKeyScroll);
    kcScrollSideways: Result := Info('Shift+Wheel', skMouse, sgMouse, [saDesign], rsKeyScrollSideways);
    kcWheelZoom: Result := Info('Mod+Wheel', skMouse, sgMouse, [saDesign], rsKeyWheelZoom);
    kcPublishWheelZoom: Result := Info('Wheel', skMouse, sgMouse, [saPublish], rsKeyPublishWheelZoom);
    kcPanMiddle: Result := Info('Middle-drag', skMouse, sgMouse, [saDesign, saPublish], rsKeyPanMiddle);
    kcPanSpace: Result := Info('Space+Drag', skMouse, sgMouse, [saDesign, saPublish], rsKeyPanSpace);
    kcCycle: Result := Info('Alt+Click', skMouse, sgMouse, [saDesign], rsKeyCycle);
    kcExtendCurve: Result := Info('Shift+Click', skMouse, sgMouse, [saDesign], rsKeyExtendCurve);
    kcPickList: Result := Info('Right-click', skMouse, sgMouse, [saDesign], rsKeyPickList);
    kcExcludePage: Result := Info('Right-click', skMouse, sgMouse, [saPublish], rsKeyExcludePage);
  end;
end;

function ParseShortcut(const Keys: string; out Key: string; out Modifiers: TShortcutModifiers): boolean;
var
  Part: string;
begin
  Key := '';
  Modifiers := [];
  for Part in Keys.Split(['+']) do
    if (Part = 'Mod') and not (smMod in Modifiers) then
      Include(Modifiers, smMod)
    else if (Part = 'Shift') and not (smShift in Modifiers) then
      Include(Modifiers, smShift)
    else if (Part = 'Alt') and not (smAlt in Modifiers) then
      Include(Modifiers, smAlt)
    else if (Key = '') and (((Length(Part) = 1) and (Part[1] in ['A'..'Z', '0'..'9'])) or (IndexStr(Part, SHORTCUT_KEY_NAMES) >= 0)) then
      Key := Part
    else
      Exit(False);
  Result := Key <> '';
end;

end.
