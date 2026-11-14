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

// The members of each kind of user file outside a pattern's objects, which
// Sloper.Core.OperationInfo lists, for the file format documentation and
// JSON Schemas. Tests hold it to the code: every member a saved file has must
// be listed, every listed member must be written by some file, and each
// example must load. No LCL dependency.
unit Sloper.Core.FileInfo;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.OperationInfo;

type
  TFileFormatInfo = record
    // The "format" member of the file
    FormatName: string;
    Extension: string;
    Version: integer;
    Title: string;
    Summary: string;
    Members: TOperationMemberArray;
    // A short file of this kind, as the program writes it
    Example: string;
  end;
  TFileFormatInfoArray = array of TFileFormatInfo;

// The pattern, measurement and layout files, in that order
function FileFormatInfos: TFileFormatInfoArray;
function FindFileFormatInfo(const FormatName: string; out Info: TFileFormatInfo): boolean;
// The member with this name, such as sources[].id, or a list of values named
// with [] after it; False when not listed
function FindFileMember(const Info: TFileFormatInfo; const AName: string; out Member: TOperationMember): boolean;

resourcestring
  rsFileFormat = 'What the file is; a file with another value does not load';
  rsFileVersion = 'The version of the format; a program refuses a file newer than it knows';
  rsFileUnitsMM = 'Always mm: values in this file are millimetres';

  rsFilePatternTitle = 'Pattern';
  rsFilePatternSummary = 'Made by opensloper-design. It holds the definitions only: the formula for each point and ' +
    'line, and which edges make each piece. Positions are worked out again every time it opens.';
  rsFilePatternUnits = 'The unit of the numbers in formulas';
  rsFilePatternNotes = 'Notes about the pattern';
  rsFilePatternMeasurementFile = 'The measurement file last used with it, relative to the pattern''s folder unless ' +
    'absolute, with / between folders; empty when there is none';
  rsFilePatternIdentity = 'Tells the pattern from others when objects are pasted; made when the pattern is';
  rsFilePatternNextId = 'The next ID to hand out, above every ID in the file, so deleted IDs are never reused; ' +
    'when left out, one above the highest ID';
  rsFilePatternVariables = 'The # variables, in the order they were made';
  rsFileVariableId = 'The variable''s ID; IDs are unique across variables, materials and objects';
  rsFileVariableName = 'The name formulas use after #';
  rsFileVariableFormula = 'Its value, in ID form: another object is written {12}';
  rsFileVariableDescription = 'What it is for';
  rsFilePatternObjects = 'The points, edges, transforms, pieces, seams and notes, in the order they were made, each ' +
    'after every object it uses; their members are on the Operations and objects page';
  rsFilePatternMaterials = 'The materials pieces are cut from; left out while the only one is the untouched Main';
  rsFileMaterialId = 'The material''s ID';
  rsFileMaterialName = 'Its name, unique in the pattern';
  rsFileMaterialColor = 'Its colour, as #RRGGBB';
  rsFileMaterialFill = 'How its pieces are filled on screen and in print';
  rsFileMaterialAllowance = 'The seam allowance of its pieces, in the pattern''s unit, when it has its own';
  rsFileMaterialWidth = 'How wide it is, in the pattern''s unit; a width alone is a roll. Pieces wider are problems';
  rsFileMaterialLength = 'How long a sheet of it is, in the pattern''s unit, with a width; left out for a roll';
  rsFileMaterialAllowTurns = 'Whether pieces may lie a quarter turn round on it, for material with no grain';
  rsFilePatternView = 'How the design app last showed the pattern; not part of undo';
  rsFileViewZoom = 'The zoom';
  rsFileViewCentre = 'The point in the middle of the window, as x and y in mm';
  rsFileViewHiddenRoles = 'The kinds of line hidden on the canvas';
  rsFileViewHideAnnotations = 'Whether notes are hidden';
  rsFileViewHiddenPieces = 'Pieces hidden on the canvas, by ID, with what only they use; they still print';
  rsFileViewIsolate = 'The piece worked on alone on the canvas, by ID; everything it does not use is dimmed';
  rsFileViewPieceOrder = 'Pieces in drawing order on the canvas, lowest first, by ID; a piece not listed goes on top';

  rsFileMeasurementsTitle = 'Measurements';
  rsFileMeasurementsSummary = 'Made by opensloper-measurements: one person''s measurements, with a value each, or a ' +
    'size table, with a value for each size. Patterns refer to a measurement by its key, as @waist.';
  rsFileMeasurementsName = 'Whose measurements, or the name of the size table';
  rsFileMeasurementsNotes = 'Notes, such as how they were taken';
  rsFileMeasurementsSizes = 'A size table''s sizes, as named; left out for one person''s set';
  rsFileMeasurementsList = 'The measurements, in the order shown';
  rsFileMeasurementKey = 'The name patterns use after @; letters, digits and underscore';
  rsFileMeasurementValue = 'The value, in a set with no sizes';
  rsFileMeasurementValues = 'In a size table, one value for each size in order; null for a size with no value';
  rsFileMeasurementDescription = 'What is measured';

  rsFileLayoutTitle = 'Layout';
  rsFileLayoutSummary = 'Made by opensloper-publish: where the pieces of one or more patterns go on the pages, roll or ' +
    'material, and how they print. Positions are plain numbers in mm, from the top left, y down.';
  rsFileLayoutName = 'The layout''s name, for the title block';
  rsFileLayoutNextId = 'The next source ID to hand out';
  rsFileLayoutSources = 'The patterns laid out, each with the measurements to draw it with';
  rsFileSourceId = 'The source''s ID, which placements refer to';
  rsFileSourcePattern = 'The pattern file, relative to the layout''s folder';
  rsFileSourceMeasurementFile = 'The measurement file, relative to the layout''s folder; the pattern''s own when ' +
    'left out';
  rsFileSourceSize = 'The size, for a size table; its first size when left out';
  rsFileLayoutOutput = 'What the layout prints on and how';
  rsFileOutputKind = 'tiled: pages taped together; large: a roll; projector: shown on the material; material: a ' +
    'sheet of material for a cutting machine';
  rsFileOutputRollWidth = 'The roll''s width, for large';
  rsFileOutputPaper = 'The paper size, A4, A3 or Letter, or a name of your own with its width and height';
  rsFileOutputPaperWidth = 'The paper''s width, for a size of your own';
  rsFileOutputPaperHeight = 'The paper''s height, for a size of your own';
  rsFileOutputMargin = 'The edge of the paper left blank';
  rsFileOutputOverlap = 'How far tiles overlap';
  rsFileOutputMarks = 'The marks for lining up tiles';
  rsFileOutputFill = 'How pieces are filled; none when left out';
  rsFileOutputProfile = 'The cutting machine profile, from the settings';
  rsFileOutputOutputProfile = 'The output profile, from the settings, which chooses what prints';
  rsFileOutputMaterialWidth = 'The material''s width, for material';
  rsFileOutputMaterialLength = 'The material''s length, for material; 0 or left out for as long as needed';
  rsFileOutputAllowTurns = 'Whether a piece may lie across the grain, for material';
  rsFileOutputMaterial = 'Only pieces cut from this material, by name';
  rsFileOutputExcludedPages = 'Pages left out of the print, by their captions';
  rsFileLayoutPlacements = 'Where each copy of each piece lies';
  rsFilePlacementSource = 'The source the piece is from';
  rsFilePlacementPiece = 'The piece''s ID in that source''s pattern';
  rsFilePlacementCopy = 'Which copy, from 1, for a piece cut more than once';
  rsFilePlacementX = 'The left of the piece''s cutting line, after turning and flipping';
  rsFilePlacementY = 'The top of the piece''s cutting line, after turning and flipping';
  rsFilePlacementRotation = 'The turn in degrees, a multiple of 90, anticlockwise';
  rsFilePlacementFlipped = 'Whether the piece is flipped over, before it is turned';
  rsFileLayoutSheetNotes = 'Text placed on the sheet, not on a piece';
  rsFileSheetNoteText = 'The text; it may hold fields such as {date}';
  rsFileSheetNoteX = 'Its left';
  rsFileSheetNoteY = 'Its top';
  rsFileSheetNoteSize = 'Its size in points';
  rsFileSheetNoteAlign = 'How its lines line up';
  rsFileSheetNoteBox = 'Whether it has a white box behind it';
  rsFileSheetNoteFont = 'The font family it prints in; left out for the default sans-serif';
  rsFileSheetNoteBold = 'Whether it is bold';
  rsFileSheetNoteItalic = 'Whether it is italic';
  rsFileLayoutTitleBlock = 'The title block; no title block when left out';
  rsFileTitleCorner = 'The corner of the page it sits in';
  rsFileTitleFields = 'What it shows, in order';
  rsFileTitleEveryPage = 'Whether it is on every page, not only the first';

implementation

uses
  SysUtils, Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.Note, Sloper.Core.Units, Sloper.Core.TextFields,
  Sloper.Core.PatternFile, Sloper.Core.Measurements;

const
  // As the apps name them; Sloper.Output.Layout is outside the core, so a test
  // holds the layout's to it
  LAYOUT_FORMAT_NAME = 'layout';
  LAYOUT_FORMAT_VERSION = 1;
  LAYOUT_EXTENSION_NAME = '.slayout';
  PATTERN_EXTENSION_NAME = '.sloper';
  MEASUREMENT_EXTENSION_NAME = '.slm';

  PATTERN_EXAMPLE =
    '{' + LineEnding +
    '  "format": "pattern",' + LineEnding +
    '  "version": 1,' + LineEnding +
    '  "units": "cm",' + LineEnding +
    '  "notes": "",' + LineEnding +
    '  "measurementFile": "bill.slm",' + LineEnding +
    '  "nextId": 6,' + LineEnding +
    '  "variables": [' + LineEnding +
    '    {' + LineEnding +
    '      "id": 1,' + LineEnding +
    '      "name": "ease",' + LineEnding +
    '      "formula": "2",' + LineEnding +
    '      "description": "Ease at the waist"' + LineEnding +
    '    }' + LineEnding +
    '  ],' + LineEnding +
    '  "objects": [' + LineEnding +
    '    {' + LineEnding +
    '      "id": 2,' + LineEnding +
    '      "type": "freePoint",' + LineEnding +
    '      "name": "A",' + LineEnding +
    '      "x": "0",' + LineEnding +
    '      "y": "0"' + LineEnding +
    '    },' + LineEnding +
    '    {' + LineEnding +
    '      "id": 3,' + LineEnding +
    '      "type": "offsetPoint",' + LineEnding +
    '      "name": "B",' + LineEnding +
    '      "base": 2,' + LineEnding +
    '      "mode": "polar",' + LineEnding +
    '      "length": "@waist / 4 + {1}",' + LineEnding +
    '      "angle": "0"' + LineEnding +
    '    },' + LineEnding +
    '    {' + LineEnding +
    '      "id": 4,' + LineEnding +
    '      "type": "line",' + LineEnding +
    '      "start": 2,' + LineEnding +
    '      "end": 3,' + LineEnding +
    '      "role": "outline"' + LineEnding +
    '    }' + LineEnding +
    '  ],' + LineEnding +
    '  "materials": [' + LineEnding +
    '    {' + LineEnding +
    '      "id": 5,' + LineEnding +
    '      "name": "Main",' + LineEnding +
    '      "color": "#5B8DB8",' + LineEnding +
    '      "fill": "tint",' + LineEnding +
    '      "allowance": 1.5' + LineEnding +
    '    }' + LineEnding +
    '  ]' + LineEnding +
    '}';

  MEASUREMENTS_EXAMPLE =
    '{' + LineEnding +
    '  "format": "measurements",' + LineEnding +
    '  "version": 1,' + LineEnding +
    '  "units": "mm",' + LineEnding +
    '  "name": "Block sizes",' + LineEnding +
    '  "notes": "",' + LineEnding +
    '  "sizes": [' + LineEnding +
    '    "36",' + LineEnding +
    '    "38"' + LineEnding +
    '  ],' + LineEnding +
    '  "measurements": [' + LineEnding +
    '    {' + LineEnding +
    '      "key": "waist",' + LineEnding +
    '      "values": [' + LineEnding +
    '        700,' + LineEnding +
    '        740' + LineEnding +
    '      ],' + LineEnding +
    '      "description": "Waist circumference"' + LineEnding +
    '    },' + LineEnding +
    '    {' + LineEnding +
    '      "key": "back_length",' + LineEnding +
    '      "values": [' + LineEnding +
    '        405,' + LineEnding +
    '        null' + LineEnding +
    '      ],' + LineEnding +
    '      "description": "Nape to waist"' + LineEnding +
    '    }' + LineEnding +
    '  ]' + LineEnding +
    '}';

  LAYOUT_EXAMPLE =
    '{' + LineEnding +
    '  "format": "layout",' + LineEnding +
    '  "version": 1,' + LineEnding +
    '  "units": "mm",' + LineEnding +
    '  "name": "Skirt, A4",' + LineEnding +
    '  "nextId": 2,' + LineEnding +
    '  "sources": [' + LineEnding +
    '    {' + LineEnding +
    '      "id": 1,' + LineEnding +
    '      "pattern": "skirt.sloper",' + LineEnding +
    '      "measurementFile": "sizes.slm",' + LineEnding +
    '      "size": "38"' + LineEnding +
    '    }' + LineEnding +
    '  ],' + LineEnding +
    '  "output": {' + LineEnding +
    '    "kind": "tiled",' + LineEnding +
    '    "rollWidth": 914,' + LineEnding +
    '    "paper": "A4",' + LineEnding +
    '    "margin": 6,' + LineEnding +
    '    "overlap": 10,' + LineEnding +
    '    "marks": "diamond"' + LineEnding +
    '  },' + LineEnding +
    '  "placements": [' + LineEnding +
    '    {' + LineEnding +
    '      "source": 1,' + LineEnding +
    '      "piece": 42,' + LineEnding +
    '      "copy": 1,' + LineEnding +
    '      "x": 20,' + LineEnding +
    '      "y": 20,' + LineEnding +
    '      "rotation": 0,' + LineEnding +
    '      "flipped": false' + LineEnding +
    '    }' + LineEnding +
    '  ],' + LineEnding +
    '  "titleBlock": {' + LineEnding +
    '    "corner": "bottomRight",' + LineEnding +
    '    "fields": [' + LineEnding +
    '      "pattern.name",' + LineEnding +
    '      "measurements.name",' + LineEnding +
    '      "date"' + LineEnding +
    '    ],' + LineEnding +
    '    "everyPage": false' + LineEnding +
    '  }' + LineEnding +
    '}';

var
  Table: TFileFormatInfoArray;
  Building: integer;

function Joined(const Names: array of string): string;
begin
  Result := string.Join(', ', Names);
end;

function RoleChoices: string;
var
  Role: TEdgeRole;
begin
  Result := '';
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + EDGE_ROLE_NAMES[Role];
  end;
end;

function UnitChoices: string;
var
  MeasureUnit: TMeasureUnit;
begin
  Result := '';
  for MeasureUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + MEASURE_UNIT_NAMES[MeasureUnit];
  end;
end;

procedure FileFormat(const AFormatName, AExtension: string; AVersion: integer; const ATitle, ASummary, AExample: string);
begin
  Building := Length(Table);
  SetLength(Table, Building + 1);
  Table[Building].FormatName := AFormatName;
  Table[Building].Extension := AExtension;
  Table[Building].Version := AVersion;
  Table[Building].Title := ATitle;
  Table[Building].Summary := ASummary;
  Table[Building].Example := AExample;
end;

procedure M(const AName: string; AKind: TMemberKind; const ADescription: string; const AChoices: string = '';
  ARequired: boolean = False);
var
  Member: TOperationMember;
begin
  Member.Name := AName;
  Member.Kind := AKind;
  Member.Description := ADescription;
  Member.Choices := AChoices;
  Member.Required := ARequired;
  Insert(Member, Table[Building].Members, Length(Table[Building].Members));
end;

// A required member
procedure R(const AName: string; AKind: TMemberKind; const ADescription: string; const AChoices: string = '');
begin
  M(AName, AKind, ADescription, AChoices, True);
end;

procedure BuildTable;
begin
  Table := nil;
  FileFormat(PATTERN_FORMAT, PATTERN_EXTENSION_NAME, PATTERN_VERSION, rsFilePatternTitle, rsFilePatternSummary, PATTERN_EXAMPLE);
  R('format', mkChoice, rsFileFormat, PATTERN_FORMAT);
  R('version', mkWhole, rsFileVersion);
  M('units', mkChoice, rsFilePatternUnits, UnitChoices);
  M('notes', mkText, rsFilePatternNotes);
  M('measurementFile', mkText, rsFilePatternMeasurementFile);
  M('identity', mkText, rsFilePatternIdentity);
  M('nextId', mkWhole, rsFilePatternNextId);
  M('variables', mkList, rsFilePatternVariables);
  R('variables[].id', mkWhole, rsFileVariableId);
  R('variables[].name', mkText, rsFileVariableName);
  R('variables[].formula', mkFormula, rsFileVariableFormula);
  M('variables[].description', mkText, rsFileVariableDescription);
  M('objects[]', mkPatternObject, rsFilePatternObjects);
  M('materials', mkList, rsFilePatternMaterials);
  R('materials[].id', mkWhole, rsFileMaterialId);
  R('materials[].name', mkText, rsFileMaterialName);
  R('materials[].color', mkText, rsFileMaterialColor);
  M('materials[].fill', mkChoice, rsFileMaterialFill, Joined(MATERIAL_FILL_NAMES));
  M('materials[].allowance', mkSize, rsFileMaterialAllowance);
  M('materials[].width', mkSize, rsFileMaterialWidth);
  M('materials[].length', mkSize, rsFileMaterialLength);
  M('materials[].allowTurns', mkFlag, rsFileMaterialAllowTurns);
  M('view', mkGroup, rsFilePatternView);
  M('view.zoom', mkSize, rsFileViewZoom);
  M('view.centre[]', mkSize, rsFileViewCentre);
  M('view.hiddenRoles[]', mkChoice, rsFileViewHiddenRoles, RoleChoices);
  M('view.hideAnnotations', mkFlag, rsFileViewHideAnnotations);
  M('view.hiddenPieces[]', mkWhole, rsFileViewHiddenPieces);
  M('view.isolate', mkWhole, rsFileViewIsolate);
  M('view.pieceOrder[]', mkWhole, rsFileViewPieceOrder);

  FileFormat(MEASUREMENT_FORMAT, MEASUREMENT_EXTENSION_NAME, MEASUREMENT_VERSION, rsFileMeasurementsTitle, rsFileMeasurementsSummary,
    MEASUREMENTS_EXAMPLE);
  R('format', mkChoice, rsFileFormat, MEASUREMENT_FORMAT);
  R('version', mkWhole, rsFileVersion);
  M('units', mkChoice, rsFileUnitsMM, 'mm');
  M('name', mkText, rsFileMeasurementsName);
  M('notes', mkText, rsFileMeasurementsNotes);
  M('sizes[]', mkText, rsFileMeasurementsSizes);
  R('measurements', mkList, rsFileMeasurementsList);
  R('measurements[].key', mkText, rsFileMeasurementKey);
  M('measurements[].value', mkSize, rsFileMeasurementValue);
  M('measurements[].values[]', mkSizeOrNull, rsFileMeasurementValues);
  M('measurements[].description', mkText, rsFileMeasurementDescription);

  FileFormat(LAYOUT_FORMAT_NAME, LAYOUT_EXTENSION_NAME, LAYOUT_FORMAT_VERSION, rsFileLayoutTitle, rsFileLayoutSummary, LAYOUT_EXAMPLE);
  R('format', mkChoice, rsFileFormat, LAYOUT_FORMAT_NAME);
  R('version', mkWhole, rsFileVersion);
  M('units', mkChoice, rsFileUnitsMM, 'mm');
  M('name', mkText, rsFileLayoutName);
  M('nextId', mkWhole, rsFileLayoutNextId);
  R('sources', mkList, rsFileLayoutSources);
  R('sources[].id', mkWhole, rsFileSourceId);
  R('sources[].pattern', mkText, rsFileSourcePattern);
  M('sources[].measurementFile', mkText, rsFileSourceMeasurementFile);
  M('sources[].size', mkText, rsFileSourceSize);
  M('output', mkGroup, rsFileLayoutOutput);
  M('output.kind', mkChoice, rsFileOutputKind, 'tiled, large, projector, material');
  M('output.rollWidth', mkSize, rsFileOutputRollWidth);
  M('output.paper', mkText, rsFileOutputPaper);
  M('output.paperWidth', mkSize, rsFileOutputPaperWidth);
  M('output.paperHeight', mkSize, rsFileOutputPaperHeight);
  M('output.margin', mkSize, rsFileOutputMargin);
  M('output.overlap', mkSize, rsFileOutputOverlap);
  M('output.marks', mkChoice, rsFileOutputMarks, 'diamond, none, halfCircle');
  M('output.fill', mkChoice, rsFileOutputFill, 'none, tint, hatch');
  M('output.profile', mkText, rsFileOutputProfile);
  M('output.outputProfile', mkText, rsFileOutputOutputProfile);
  M('output.materialWidth', mkSize, rsFileOutputMaterialWidth);
  M('output.materialLength', mkSize, rsFileOutputMaterialLength);
  M('output.allowTurns', mkFlag, rsFileOutputAllowTurns);
  M('output.material', mkText, rsFileOutputMaterial);
  M('output.excludedPages[]', mkText, rsFileOutputExcludedPages);
  M('placements', mkList, rsFileLayoutPlacements);
  R('placements[].source', mkWhole, rsFilePlacementSource);
  R('placements[].piece', mkWhole, rsFilePlacementPiece);
  M('placements[].copy', mkWhole, rsFilePlacementCopy);
  R('placements[].x', mkSize, rsFilePlacementX);
  R('placements[].y', mkSize, rsFilePlacementY);
  M('placements[].rotation', mkWhole, rsFilePlacementRotation);
  M('placements[].flipped', mkFlag, rsFilePlacementFlipped);
  M('sheetNotes', mkList, rsFileLayoutSheetNotes);
  R('sheetNotes[].text', mkText, rsFileSheetNoteText);
  R('sheetNotes[].x', mkSize, rsFileSheetNoteX);
  R('sheetNotes[].y', mkSize, rsFileSheetNoteY);
  M('sheetNotes[].size', mkSize, rsFileSheetNoteSize);
  M('sheetNotes[].align', mkChoice, rsFileSheetNoteAlign, Joined(TEXT_ALIGN_NAMES));
  M('sheetNotes[].box', mkFlag, rsFileSheetNoteBox);
  M('sheetNotes[].font', mkText, rsFileSheetNoteFont);
  M('sheetNotes[].bold', mkFlag, rsFileSheetNoteBold);
  M('sheetNotes[].italic', mkFlag, rsFileSheetNoteItalic);
  M('titleBlock', mkGroup, rsFileLayoutTitleBlock);
  M('titleBlock.corner', mkChoice, rsFileTitleCorner, 'bottomRight, bottomLeft, topRight');
  M('titleBlock.fields[]', mkChoice, rsFileTitleFields, Joined([FIELD_PATTERN_NAME, FIELD_MEASUREMENTS_NAME, FIELD_LAYOUT_NAME,
    FIELD_DATE, FIELD_CUT_LIST, FIELD_MATERIALS, FIELD_MATERIAL_NEEDED]));
  M('titleBlock.everyPage', mkFlag, rsFileTitleEveryPage);
end;

function FileFormatInfos: TFileFormatInfoArray;
begin
  if Length(Table) = 0 then
    BuildTable;
  Result := Table;
end;

function FindFileFormatInfo(const FormatName: string; out Info: TFileFormatInfo): boolean;
var
  Candidate: TFileFormatInfo;
begin
  Info := Default(TFileFormatInfo);
  for Candidate in FileFormatInfos do
    if Candidate.FormatName = FormatName then
    begin
      Info := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function FindFileMember(const Info: TFileFormatInfo; const AName: string; out Member: TOperationMember): boolean;
var
  Candidate: TOperationMember;
begin
  Member := Default(TOperationMember);
  for Candidate in Info.Members do
    if (Candidate.Name = AName) or (Candidate.Name = AName + '[]') then
    begin
      Member := Candidate;
      Exit(True);
    end;
  Result := False;
end;

end.
