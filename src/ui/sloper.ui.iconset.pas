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

// The icon each command shows, as a Tabler outline SVG in data/icons. Kept
// free of the LCL so the list can be checked by the tests.
unit Sloper.UI.IconSet;

{$mode ObjFPC}{$H+}

interface

type
  TAppIcon = (aiNew, aiOpen, aiSave, aiSaveAs, aiMeasurements, aiPublish, aiExportDraft, aiQuit,
    aiUndo, aiRedo, aiCut, aiCopy, aiPaste, aiDelete,
    aiZoomIn, aiZoomOut, aiFit, aiTrueSize, aiZoomArea, aiSidePanel, aiLabels, aiPieceFills, aiAbout,
    aiSelect, aiPoint, aiLine, aiCurve, aiPiece, aiNotch, aiSeam,
    aiSplit, aiCircle, aiArc, aiRectangle, aiRoundCorner, aiOffsetLeft, aiOffsetRight, aiToLine, aiToCurve,
    aiMergePoints, aiBreakPoint, aiRepeat,
    aiHole, aiPlacement, aiStitchHoles, aiRemoveMarking,
    aiRotate, aiMirror, aiMove, aiSuggestSeams,
    // The measurements and publish apps
    aiImport, aiExport, aiCheckPattern, aiStopCheck,
    aiExportPDF, aiExportSVG, aiExportDXF, aiExportMachineDXF, aiReload,
    aiRulers, aiPreferences,
    // Notes
    aiText, aiAnnotations, aiCallout,
    // Overlapping pieces
    aiHidePiece, aiShowPieces, aiIsolate, aiBringToFront, aiSendToBack,
    // Locked objects
    aiLock, aiUnlock);

const
  APP_ICON_NAMES: array[TAppIcon] of string = ('file-plus', 'folder-open', 'device-floppy', 'file-pencil',
    'ruler-measure', 'printer', 'file-type-svg', 'logout',
    'arrow-back-up', 'arrow-forward-up', 'cut', 'copy', 'clipboard', 'trash',
    'zoom-in', 'zoom-out', 'zoom-scan', 'zoom-reset', 'zoom-in-area', 'layout-sidebar-right', 'tag', 'bucket', 'info-circle',
    'pointer', 'point', 'line', 'vector-bezier', 'polygon', 'triangle-inverted', 'needle-thread',
    'scissors', 'circle', 'rainbow', 'rectangle', 'border-corner-rounded', 'arrow-bar-left', 'arrow-bar-right', 'line', 'vector-bezier',
    'arrows-join', 'arrows-split', 'dots',
    'circle-dot', 'line-dashed', 'line-dotted', 'eraser',
    'rotate', 'flip-vertical', 'arrows-move', 'sparkles',
    'file-import', 'file-export', 'file-search', 'player-stop',
    'file-type-pdf', 'file-type-svg', 'file-vector', 'cut', 'refresh',
    'ruler-2', 'settings',
    'typography', 'notes', 'message',
    'eye-off', 'eye', 'focus-2', 'stack-front', 'stack-back', 'lock', 'lock-open');

function IconFileName(const Dir: string; Icon: TAppIcon): string;
// Tabler draws in currentColor; this gives it Color, such as #202020
function TintedSVG(const Text, Color: string): string;

implementation

uses
  SysUtils;

function IconFileName(const Dir: string; Icon: TAppIcon): string;
begin
  Result := ConcatPaths([Dir, APP_ICON_NAMES[Icon] + '.svg']);
end;

function TintedSVG(const Text, Color: string): string;
begin
  Result := StringReplace(Text, 'currentColor', Color, [rfReplaceAll]);
end;

end.
