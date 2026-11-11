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

// Every kind of object a pattern holds, with its members as a pattern file
// and the Automation API write them, for the reference documentation. Tests
// hold it to the code: every member a saved object has must be listed, and
// each formula's kind must match the node's FieldUnitKind. No LCL dependency.
unit Sloper.Core.OperationInfo;

{$mode ObjFPC}{$H+}

interface

type
  TOperationGroup = (ogPoint, ogEdge, ogTransform, ogPiece, ogAnnotation);

  TMemberKind = (
    mkLength,          // a formula giving a length, in the pattern's unit
    mkAngle,           // a formula giving an angle in degrees
    mkNumber,          // a formula giving a plain number: a count or a ratio
    mkLengthOrRatio,   // a formula, a length or a ratio by the object's mode
    mkPoint,           // a point's ID
    mkEdge,            // an edge's ID
    mkPiece,           // a piece's ID
    mkObject,          // the ID of any object
    mkMaterial,        // a material's ID
    mkChoice,          // one of the words in Choices
    mkFlag,            // true or false
    mkWhole,           // a whole number
    mkText,            // text
    mkSize,            // a plain number, not a formula
    mkSizeOrNull,      // a plain number, or null for none
    mkFormula,         // a formula giving any value
    mkPatternObject,   // one of the objects this table lists
    mkList,            // a list of objects, whose members are listed after it as list[].member
    mkGroup);          // an object, whose members are listed after it as group.member

  // A name ending in [] is a list of values of its kind, such as sources[]
  TOperationMember = record
    // As in the file: x, nodes[].angle, grainline.start
    Name: string;
    Kind: TMemberKind;
    // For mkChoice, the words it takes, separated by ", "
    Choices: string;
    Description: string;
    // A file without it does not load
    Required: boolean;
  end;
  TOperationMemberArray = array of TOperationMember;

  TOperationInfo = record
    // The "type" in a pattern file and the Automation API
    TypeName: string;
    Title: string;
    Group: TOperationGroup;
    // Made by another operation rather than added by itself
    Derived: boolean;
    Summary: string;
    // What formulas can read, separated by ", "; a condition after one in brackets
    Properties: string;
    Members: TOperationMemberArray;
  end;
  TOperationInfoArray = array of TOperationInfo;

// Every type, grouped and in the order the documentation lists them
function OperationInfos: TOperationInfoArray;
// Members every object of the group has, besides its own
function CommonMembers(Group: TOperationGroup): TOperationMemberArray;
function FindOperationInfo(const TypeName: string; out Info: TOperationInfo): boolean;
// The member with this name, such as nodes[].angle, or a list of values
// named with [] after it; False when not listed
function FindMember(const Info: TOperationInfo; const AName: string; out Member: TOperationMember): boolean;

resourcestring
  rsMemberId = 'The object''s ID, a whole number that never changes; other objects refer to it';
  rsMemberType = 'The kind of object, as in the headings on this page';
  rsMemberName = 'The name shown and used in formulas; an edge named after its ends leaves it out';
  rsMemberRole = 'What the edge is: an outline makes pieces, the others are drawn and printed in their own style';
  rsMemberMarker = 'A marker drawn at the point: a hole, a button or a match dot';
  rsMemberMarkerSize = 'The marker''s size, when it has one';

  rsOpFreePoint = 'Free point';
  rsOpFreePointSummary = 'A point at a place of its own: the origin, or a point not yet tied to others.';
  rsMemberX = 'Distance to the right of the origin';
  rsMemberY = 'Distance down from the origin';
  rsOpOffsetPoint = 'Offset point';
  rsOpOffsetPointSummary = 'A point a distance at an angle from another point, or across and down from it. ' +
    'Square to a line is an angle such as `Line_A_B.angle + 90`.';
  rsMemberBase = 'The point it is measured from';
  rsMemberOffsetMode = 'polar: a length at an angle; cartesian: across and down';
  rsMemberOffsetLength = 'polar: how far from the base';
  rsMemberOffsetAngle = 'polar: which way, 0° right and 90° up';
  rsMemberDx = 'cartesian: how far to the right';
  rsMemberDy = 'cartesian: how far down';
  rsOpAlongEdge = 'Point along an edge';
  rsOpAlongEdgeSummary = 'A point on a line, curve or arc, a length or a share of the way along it: a midpoint, thirds, ' +
    'dart positions.';
  rsMemberAlongEdge = 'The edge it lies on';
  rsMemberFrom = 'The end it is measured from';
  rsMemberAlongMode = 'length: a distance along the edge; ratio: a share of its length, 0 to 1';
  rsMemberAlongValue = 'The distance or the ratio';
  rsOpBetween = 'Point between points';
  rsOpBetweenSummary = 'A point on the straight line from one point to another, without needing an edge.';
  rsMemberA = 'The first point';
  rsMemberB = 'The second point';
  rsMemberBetweenMode = 'ratio: a share of the way, 0 to 1; length: a distance from a';
  rsMemberBetweenValue = 'The ratio or the distance';
  rsOpIntersect = 'Intersection of edges';
  rsOpIntersectSummary = 'Where two edges cross: lines, curves or arcs.';
  rsMemberEdgeA = 'The first edge';
  rsMemberEdgeB = 'The second edge';
  rsMemberExtendA = 'Let the first edge run on past its ends, along its end directions';
  rsMemberExtendB = 'Let the second edge run on past its ends';
  rsMemberPick = 'Which crossing, counting from 1 along the first edge, so it stays the same one when sizes change';
  rsOpCircleEdge = 'Circle and edge';
  rsOpCircleEdgeSummary = 'Where a circle around a point crosses an edge: a compass step, such as the shoulder length ' +
    'from the neck point onto the shoulder line.';
  rsMemberCentre = 'The point at the centre';
  rsMemberRadius = 'The distance from the centre';
  rsMemberCrossedEdge = 'The edge the circle crosses';
  rsMemberExtend = 'Let the edge run on past its ends';
  rsMemberCirclePick = 'Which crossing, counting from 1 along the edge';
  rsOpCircleCircle = 'Circle and circle';
  rsOpCircleCircleSummary = 'A point at given distances from two points.';
  rsMemberCentreA = 'The first centre';
  rsMemberRadiusA = 'The distance from the first centre';
  rsMemberCentreB = 'The second centre';
  rsMemberRadiusB = 'The distance from the second centre';
  rsMemberSidePick = '1: on the left going from the first centre to the second; 2: on the right';
  rsOpProject = 'Point projected onto an edge';
  rsOpProjectSummary = 'From a point onto an edge, square to it or at an angle: the foot of a perpendicular, or straight ' +
    'down to the hem line.';
  rsMemberSource = 'The point it comes from';
  rsMemberOntoEdge = 'The edge it lands on';
  rsMemberDirection = 'perpendicular: square to the edge; angle: along the angle given';
  rsMemberProjectAngle = 'angle: the direction to travel in';
  rsOpRepeat = 'Repeat';
  rsOpRepeatSummary = 'A number of points evenly spaced between two points or along an edge: buttons, pleats, notch rows. ' +
    'They are named after the repeat and their number, such as `Btn[3]`.';
  rsMemberRepeatEdge = 'Along this edge, by equal length, in place of a and b';
  rsMemberCount = 'How many points';
  rsMemberEnds = 'Whether the ends have points of their own';
  rsMemberRepeatPoints = 'The points in use by other objects, each with its number and ID';
  rsMemberRepeatIndex = 'The point''s number, from 1';
  rsMemberRepeatId = 'The ID it was given when first used';
  rsOpCornerPoint = 'Corner point';
  rsOpCornerPointSummary = 'An end of a rounded corner''s arc, where it meets the trimmed edge; made by Round Corner.';
  rsMemberCornerArc = 'The rounded corner';
  rsMemberCornerEnd = 'Which end: 1 or 2';
  rsOpPointCopy = 'Point copy';
  rsOpPointCopySummary = 'A copy of a point made by a transform; it follows its source.';
  rsMemberTransform = 'The transform that made it';
  rsMemberCopySource = 'What it is a copy of';

  rsOpLine = 'Line';
  rsOpLineSummary = 'A straight edge between two points.';
  rsMemberStart = 'The point it starts at';
  rsMemberEnd = 'The point it ends at';
  rsOpCurve = 'Curve';
  rsOpCurveSummary = 'A smooth curve between two points, shaped by a handle at each end: a hip curve, side seam shaping.';
  rsMemberAngle1 = 'The direction it leaves the start in';
  rsMemberLength1 = 'How far the start''s handle reaches';
  rsMemberAngle2 = 'The direction of the end''s handle, pointing back along the curve';
  rsMemberLength2 = 'How far the end''s handle reaches';
  rsOpCurvePath = 'Curve path';
  rsOpCurvePathSummary = 'A smooth curve through several points: armholes, necklines, crotch curves. Each point has one ' +
    'direction, so the joins stay smooth. In formulas a node''s fields are named node2.angle, node2.lengthIn and so on.';
  rsMemberNodes = 'The points it passes through, in order';
  rsMemberNodePoint = 'The point';
  rsMemberNodeAngle = 'The direction of travel at the point';
  rsMemberNodeIn = 'How far the handle reaches back; not on the first point';
  rsMemberNodeOut = 'How far the handle reaches on; not on the last point';
  rsOpCircle = 'Circle';
  rsOpCircleSummary = 'A circle around a point: round bases, hat crowns.';
  rsOpArc = 'Arc';
  rsOpArcSummary = 'Part of a circle, from one angle to another, anticlockwise: brims, curved flaps.';
  rsMemberArcAngle1 = 'Where it starts, 0° right and 90° up';
  rsMemberArcAngle2 = 'Where it ends';
  rsOpOffsetEdge = 'Offset edge';
  rsOpOffsetEdgeSummary = 'An edge, or a run of joined edges, followed at a distance: stitch lines, facings, linings. ' +
    'Corners are mitred and trimmed.';
  rsMemberOffsetSource = 'One edge to follow, forwards; a run is written as edges instead';
  rsMemberOffsetRun = 'The joined edges to follow, in order';
  rsMemberRunEdge = 'An edge of the run';
  rsMemberRunReversed = 'Whether the run follows it from its end to its start';
  rsMemberSide = 'Which side, going along the run';
  rsMemberDistance = 'How far from the run';
  rsOpSplitPart = 'Part of a split edge';
  rsOpSplitPartSummary = 'One of the two parts an edge is split into at a point on it; made by Split Edge, for darts and ' +
    'slash and spread.';
  rsMemberSplitEdge = 'The edge that was split';
  rsMemberSplitPoint = 'The point it was split at';
  rsMemberPart = '1: from the start to the point; 2: from the point to the end';
  rsOpCornerArc = 'Rounded corner';
  rsOpCornerArcSummary = 'An arc that rounds the corner where two edges meet, made by Round Corner with its two corner ' +
    'points.';
  rsMemberVertex = 'The corner''s point';
  rsMemberCornerEdgeA = 'The first edge at the corner';
  rsMemberCornerEdgeB = 'The second edge at the corner';
  rsMemberCornerRadius = 'The arc''s radius';
  rsOpEdgeCopy = 'Edge copy';
  rsOpEdgeCopySummary = 'A copy of an edge made by a transform; it follows its source.';
  rsMemberCopyStart = 'The copy''s start point';
  rsMemberCopyEnd = 'The copy''s end point';

  rsOpRotate = 'Rotate';
  rsOpRotateSummary = 'Copies of points and edges turned about a point: dart rotation, slash and spread.';
  rsMemberSources = 'The points and edges to copy; an edge brings its ends';
  rsMemberSuffix = 'Added to each copy''s name';
  rsMemberPivot = 'The point it turns about';
  rsMemberTurn = 'How far it turns, anticlockwise';
  rsOpMirror = 'Mirror';
  rsOpMirrorSummary = 'Copies of points and edges reflected in a line: half a piece made whole.';
  rsMemberAxis = 'The line to reflect in: an edge, two points, or a point and an angle';
  rsMemberAxisEdge = 'An edge to reflect in';
  rsMemberAxisA = 'A point on the line';
  rsMemberAxisB = 'A second point on the line';
  rsMemberAxisAngle = 'With axis.a only: the line''s direction';
  rsOpMove = 'Move';
  rsOpMoveSummary = 'Copies of points and edges moved aside, and turned if wanted: developing facings, yokes, pockets.';
  rsMemberMoveMode = 'polar: a length at an angle; cartesian: across and down';
  rsMemberMoveLength = 'polar: how far';
  rsMemberMoveAngle = 'polar: which way';
  rsMemberMoveDx = 'cartesian: how far to the right';
  rsMemberMoveDy = 'cartesian: how far down';
  rsMemberMovePivot = 'With rotate: the point the copies turn about';
  rsMemberMoveRotate = 'With pivot: how far the copies turn';

  rsOpPiece = 'Piece';
  rsOpPieceSummary = 'A closed outline of edges, with its seam allowance, grainline, notches, markings, cut and material.';
  rsMemberPath = 'The edges around the piece, clockwise';
  rsMemberPathEdge = 'An edge of the outline';
  rsMemberPathReversed = 'Whether the path follows it from its end to its start';
  rsMemberPathAllowance = 'The edge''s own seam allowance, when it has one';
  rsMemberAllowance = 'The seam allowance';
  rsMemberGrainline = 'Left out for none';
  rsMemberGrainAngle = 'At an angle through the middle of the piece';
  rsMemberGrainStart = 'Or between two points: the first';
  rsMemberGrainEnd = 'The second point';
  rsMemberNotches = 'Notches on the seam line';
  rsMemberNotchPoint = 'At a point on the seam line';
  rsMemberNotchEdge = 'Or on an edge of the piece';
  rsMemberNotchPosition = 'With edge: the distance from the edge''s start';
  rsMemberMarkings = 'Points and lines marked on the piece';
  rsMemberMarkingKind = 'point: a marked point; line: a marking line; stitch: stitch holes along an edge';
  rsMemberMarkingPoint = 'point: the point or repeat';
  rsMemberMarkingEdge = 'line, stitch: the edge';
  rsMemberMarkingSpacing = 'stitch: the distance between holes, adjusted to fit';
  rsMemberMarkingSize = 'stitch: the hole size';
  rsMemberCut = 'How many to cut';
  rsMemberCutCount = 'How many';
  rsMemberCutMirrored = 'Whether every other one is mirrored';
  rsMemberFoldEdge = 'The edge the piece is cut on the fold of, when it is';
  rsMemberMaterial = 'The material it is cut from';
  rsMemberFill = 'How it is filled on screen, when not as its material';
  rsMemberFillColor = 'Its own colour, as #rrggbb';
  rsMemberFillStyle = 'How it is filled: as its material, a tint or a hatch';
  rsOpSeam = 'Seam';
  rsOpSeamSummary = 'Two runs of piece edges that are sewn together, so their lengths can be checked.';
  rsMemberSideA = 'The edges of side A, in order along the seam';
  rsMemberSideB = 'The edges of side B';
  rsMemberSidePiece = 'The piece';
  rsMemberSideEdge = 'The edge of that piece';
  rsMemberSeamReversed = 'Whether side B runs the same way as its pieces'' paths';
  rsMemberEase = 'How much longer side B should be than side A';
  rsMemberTolerance = 'How far the difference may be from the ease';

  rsOpNote = 'Note';
  rsOpNoteSummary = 'Text on the pattern, free or hung from a point, edge or piece, with draft values such as ' +
    '`{=@waist / 4}` worked out in it.';
  rsMemberAnchor = 'What it hangs from; left out for a free note';
  rsMemberAnchorPoint = 'A point';
  rsMemberAnchorEdge = 'Or an edge';
  rsMemberAnchorPiece = 'Or a piece';
  rsMemberAnchorPosition = 'With edge: how far along it, 0 to 1';
  rsMemberNoteX = 'A free note: its place across';
  rsMemberNoteY = 'A free note: its place down';
  rsMemberNoteDx = 'A hung note: how far right of what it hangs from';
  rsMemberNoteDy = 'A hung note: how far down';
  rsMemberText = 'The text, with draft values in {= }';
  rsMemberSize = 'The text size in points';
  rsMemberPrint = 'Whether it prints with its piece';
  rsMemberLeader = 'A line to what it hangs from, making it a callout';
  rsMemberAlign = 'How its lines line up';
  rsMemberBox = 'Whether it has a white box behind it';

implementation

uses
  SysUtils, Sloper.Core.Draft, Sloper.Core.Note, Sloper.Core.Materials, Sloper.Core.Piece;

var
  Table: TOperationInfoArray;
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

procedure Op(const ATypeName, ATitle: string; AGroup: TOperationGroup; const ASummary, AProperties: string;
  ADerived: boolean = False);
begin
  Building := Length(Table);
  SetLength(Table, Building + 1);
  Table[Building].TypeName := ATypeName;
  Table[Building].Title := ATitle;
  Table[Building].Group := AGroup;
  Table[Building].Summary := ASummary;
  Table[Building].Properties := AProperties;
  Table[Building].Derived := ADerived;
end;

function NewMember(const AName: string; AKind: TMemberKind; const ADescription: string; const AChoices: string = '';
  ARequired: boolean = False): TOperationMember;
begin
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Description := ADescription;
  Result.Choices := AChoices;
  Result.Required := ARequired;
end;

procedure M(const AName: string; AKind: TMemberKind; const ADescription: string; const AChoices: string = '');
begin
  Insert(NewMember(AName, AKind, ADescription, AChoices), Table[Building].Members, Length(Table[Building].Members));
end;

procedure BuildTable;
begin
  Table := nil;
  // Points
  Op('freePoint', rsOpFreePoint, ogPoint, rsOpFreePointSummary, 'x, y');
  M('x', mkLength, rsMemberX);
  M('y', mkLength, rsMemberY);
  Op('offsetPoint', rsOpOffsetPoint, ogPoint, rsOpOffsetPointSummary, 'x, y');
  M('base', mkPoint, rsMemberBase);
  M('mode', mkChoice, rsMemberOffsetMode, 'polar, cartesian');
  M('length', mkLength, rsMemberOffsetLength);
  M('angle', mkAngle, rsMemberOffsetAngle);
  M('dx', mkLength, rsMemberDx);
  M('dy', mkLength, rsMemberDy);
  Op('alongEdgePoint', rsOpAlongEdge, ogPoint, rsOpAlongEdgeSummary, 'x, y');
  M('edge', mkEdge, rsMemberAlongEdge);
  M('from', mkChoice, rsMemberFrom, 'start, end');
  M('mode', mkChoice, rsMemberAlongMode, 'length, ratio');
  M('value', mkLengthOrRatio, rsMemberAlongValue);
  Op('betweenPoint', rsOpBetween, ogPoint, rsOpBetweenSummary, 'x, y');
  M('a', mkPoint, rsMemberA);
  M('b', mkPoint, rsMemberB);
  M('mode', mkChoice, rsMemberBetweenMode, 'length, ratio');
  M('value', mkLengthOrRatio, rsMemberBetweenValue);
  Op('intersectPoint', rsOpIntersect, ogPoint, rsOpIntersectSummary, 'x, y');
  M('edgeA', mkEdge, rsMemberEdgeA);
  M('edgeB', mkEdge, rsMemberEdgeB);
  M('extendA', mkFlag, rsMemberExtendA);
  M('extendB', mkFlag, rsMemberExtendB);
  M('pick', mkWhole, rsMemberPick);
  Op('circleEdgePoint', rsOpCircleEdge, ogPoint, rsOpCircleEdgeSummary, 'x, y');
  M('centre', mkPoint, rsMemberCentre);
  M('radius', mkLength, rsMemberRadius);
  M('edge', mkEdge, rsMemberCrossedEdge);
  M('extend', mkFlag, rsMemberExtend);
  M('pick', mkWhole, rsMemberCirclePick);
  Op('circleCirclePoint', rsOpCircleCircle, ogPoint, rsOpCircleCircleSummary, 'x, y');
  M('centreA', mkPoint, rsMemberCentreA);
  M('radiusA', mkLength, rsMemberRadiusA);
  M('centreB', mkPoint, rsMemberCentreB);
  M('radiusB', mkLength, rsMemberRadiusB);
  M('pick', mkWhole, rsMemberSidePick);
  Op('projectPoint', rsOpProject, ogPoint, rsOpProjectSummary, 'x, y');
  M('point', mkPoint, rsMemberSource);
  M('edge', mkEdge, rsMemberOntoEdge);
  M('direction', mkChoice, rsMemberDirection, 'perpendicular, angle');
  M('angle', mkAngle, rsMemberProjectAngle);
  M('extend', mkFlag, rsMemberExtend);
  Op('repeat', rsOpRepeat, ogPoint, rsOpRepeatSummary, 'count');
  M('a', mkPoint, rsMemberA);
  M('b', mkPoint, rsMemberB);
  M('edge', mkEdge, rsMemberRepeatEdge);
  M('count', mkNumber, rsMemberCount);
  M('ends', mkChoice, rsMemberEnds, 'include, exclude');
  M('points', mkList, rsMemberRepeatPoints);
  M('points[].index', mkWhole, rsMemberRepeatIndex);
  M('points[].id', mkWhole, rsMemberRepeatId);
  Op('cornerPoint', rsOpCornerPoint, ogPoint, rsOpCornerPointSummary, 'x, y', True);
  M('arc', mkEdge, rsMemberCornerArc);
  M('end', mkWhole, rsMemberCornerEnd);
  Op('pointCopy', rsOpPointCopy, ogPoint, rsOpPointCopySummary, 'x, y', True);
  M('transform', mkObject, rsMemberTransform);
  M('source', mkPoint, rsMemberCopySource);
  // Edges
  Op('line', rsOpLine, ogEdge, rsOpLineSummary, 'length, angle, angle1, angle2');
  M('start', mkPoint, rsMemberStart);
  M('end', mkPoint, rsMemberEnd);
  Op('curve', rsOpCurve, ogEdge, rsOpCurveSummary, 'length, angle1, angle2');
  M('start', mkPoint, rsMemberStart);
  M('end', mkPoint, rsMemberEnd);
  M('angle1', mkAngle, rsMemberAngle1);
  M('length1', mkLength, rsMemberLength1);
  M('angle2', mkAngle, rsMemberAngle2);
  M('length2', mkLength, rsMemberLength2);
  Op('curvePath', rsOpCurvePath, ogEdge, rsOpCurvePathSummary, 'length, angle1, angle2');
  M('nodes', mkList, rsMemberNodes);
  M('nodes[].point', mkPoint, rsMemberNodePoint);
  M('nodes[].angle', mkAngle, rsMemberNodeAngle);
  M('nodes[].lengthIn', mkLength, rsMemberNodeIn);
  M('nodes[].lengthOut', mkLength, rsMemberNodeOut);
  Op('circle', rsOpCircle, ogEdge, rsOpCircleSummary, 'length, radius, angle1, angle2');
  M('centre', mkPoint, rsMemberCentre);
  M('radius', mkLength, rsMemberRadius);
  Op('arc', rsOpArc, ogEdge, rsOpArcSummary, 'length, radius, angle1, angle2');
  M('centre', mkPoint, rsMemberCentre);
  M('radius', mkLength, rsMemberRadius);
  M('angle1', mkAngle, rsMemberArcAngle1);
  M('angle2', mkAngle, rsMemberArcAngle2);
  Op('offsetEdge', rsOpOffsetEdge, ogEdge, rsOpOffsetEdgeSummary, 'length, angle1, angle2');
  M('edge', mkEdge, rsMemberOffsetSource);
  M('edges', mkList, rsMemberOffsetRun);
  M('edges[].edge', mkEdge, rsMemberRunEdge);
  M('edges[].reversed', mkFlag, rsMemberRunReversed);
  M('side', mkChoice, rsMemberSide, 'left, right');
  M('distance', mkLength, rsMemberDistance);
  Op('splitPart', rsOpSplitPart, ogEdge, rsOpSplitPartSummary, 'length, angle1, angle2, angle (when straight)');
  M('edge', mkEdge, rsMemberSplitEdge);
  M('point', mkPoint, rsMemberSplitPoint);
  M('part', mkWhole, rsMemberPart);
  Op('cornerArc', rsOpCornerArc, ogEdge, rsOpCornerArcSummary, 'length, radius, angle1, angle2');
  M('vertex', mkPoint, rsMemberVertex);
  M('edgeA', mkEdge, rsMemberCornerEdgeA);
  M('edgeB', mkEdge, rsMemberCornerEdgeB);
  M('radius', mkLength, rsMemberCornerRadius);
  Op('edgeCopy', rsOpEdgeCopy, ogEdge, rsOpEdgeCopySummary, 'length, angle1, angle2, angle (when straight)', True);
  M('transform', mkObject, rsMemberTransform);
  M('source', mkEdge, rsMemberCopySource);
  M('start', mkPoint, rsMemberCopyStart);
  M('end', mkPoint, rsMemberCopyEnd);
  // Transforms
  Op('rotate', rsOpRotate, ogTransform, rsOpRotateSummary, '');
  M('sources[]', mkObject, rsMemberSources);
  M('suffix', mkText, rsMemberSuffix);
  M('pivot', mkPoint, rsMemberPivot);
  M('angle', mkAngle, rsMemberTurn);
  Op('mirror', rsOpMirror, ogTransform, rsOpMirrorSummary, '');
  M('sources[]', mkObject, rsMemberSources);
  M('suffix', mkText, rsMemberSuffix);
  M('axis', mkGroup, rsMemberAxis);
  M('axis.edge', mkEdge, rsMemberAxisEdge);
  M('axis.a', mkPoint, rsMemberAxisA);
  M('axis.b', mkPoint, rsMemberAxisB);
  M('angle', mkAngle, rsMemberAxisAngle);
  Op('move', rsOpMove, ogTransform, rsOpMoveSummary, '');
  M('sources[]', mkObject, rsMemberSources);
  M('suffix', mkText, rsMemberSuffix);
  M('mode', mkChoice, rsMemberMoveMode, 'polar, cartesian');
  M('length', mkLength, rsMemberMoveLength);
  M('angle', mkAngle, rsMemberMoveAngle);
  M('dx', mkLength, rsMemberMoveDx);
  M('dy', mkLength, rsMemberMoveDy);
  M('pivot', mkPoint, rsMemberMovePivot);
  M('rotate', mkAngle, rsMemberMoveRotate);
  // Pieces and seams
  Op('piece', rsOpPiece, ogPiece, rsOpPieceSummary, 'holes');
  M('path', mkList, rsMemberPath);
  M('path[].edge', mkEdge, rsMemberPathEdge);
  M('path[].reversed', mkFlag, rsMemberPathReversed);
  M('path[].allowance', mkLength, rsMemberPathAllowance);
  M('allowance', mkLength, rsMemberAllowance);
  M('grainline', mkGroup, rsMemberGrainline);
  M('grainline.angle', mkAngle, rsMemberGrainAngle);
  M('grainline.start', mkPoint, rsMemberGrainStart);
  M('grainline.end', mkPoint, rsMemberGrainEnd);
  M('notches', mkList, rsMemberNotches);
  M('notches[].point', mkPoint, rsMemberNotchPoint);
  M('notches[].edge', mkEdge, rsMemberNotchEdge);
  M('notches[].position', mkLength, rsMemberNotchPosition);
  M('markings', mkList, rsMemberMarkings);
  M('markings[].kind', mkChoice, rsMemberMarkingKind, Joined(MARKING_KIND_NAMES));
  M('markings[].point', mkPoint, rsMemberMarkingPoint);
  M('markings[].edge', mkEdge, rsMemberMarkingEdge);
  M('markings[].spacing', mkLength, rsMemberMarkingSpacing);
  M('markings[].size', mkLength, rsMemberMarkingSize);
  M('cut', mkGroup, rsMemberCut);
  M('cut.count', mkWhole, rsMemberCutCount);
  M('cut.mirrored', mkFlag, rsMemberCutMirrored);
  M('foldEdge', mkEdge, rsMemberFoldEdge);
  M('material', mkMaterial, rsMemberMaterial);
  M('fill', mkGroup, rsMemberFill);
  M('fill.color', mkText, rsMemberFillColor);
  M('fill.style', mkChoice, rsMemberFillStyle, Joined(PIECE_FILL_NAMES));
  Op('seam', rsOpSeam, ogPiece, rsOpSeamSummary, '');
  M('sideA', mkList, rsMemberSideA);
  M('sideA[].piece', mkPiece, rsMemberSidePiece);
  M('sideA[].edge', mkEdge, rsMemberSideEdge);
  M('sideB', mkList, rsMemberSideB);
  M('sideB[].piece', mkPiece, rsMemberSidePiece);
  M('sideB[].edge', mkEdge, rsMemberSideEdge);
  M('reversed', mkFlag, rsMemberSeamReversed);
  M('ease', mkLength, rsMemberEase);
  M('tolerance', mkLength, rsMemberTolerance);
  // Annotations
  Op('note', rsOpNote, ogAnnotation, rsOpNoteSummary, '');
  M('anchor', mkGroup, rsMemberAnchor);
  M('anchor.point', mkPoint, rsMemberAnchorPoint);
  M('anchor.edge', mkEdge, rsMemberAnchorEdge);
  M('anchor.piece', mkPiece, rsMemberAnchorPiece);
  M('anchor.position', mkNumber, rsMemberAnchorPosition);
  M('x', mkLength, rsMemberNoteX);
  M('y', mkLength, rsMemberNoteY);
  M('dx', mkLength, rsMemberNoteDx);
  M('dy', mkLength, rsMemberNoteDy);
  M('text', mkText, rsMemberText);
  M('size', mkSize, rsMemberSize);
  M('print', mkFlag, rsMemberPrint);
  M('leader', mkChoice, rsMemberLeader, Joined(NOTE_LEADER_NAMES));
  M('align', mkChoice, rsMemberAlign, Joined(TEXT_ALIGN_NAMES));
  M('box', mkFlag, rsMemberBox);
end;

function OperationInfos: TOperationInfoArray;
begin
  if Length(Table) = 0 then
    BuildTable;
  Result := Table;
end;

function CommonMembers(Group: TOperationGroup): TOperationMemberArray;
begin
  Result := [NewMember('id', mkWhole, rsMemberId, '', True), NewMember('type', mkText, rsMemberType, '', True),
    NewMember('name', mkText, rsMemberName)];
  if Group = ogEdge then
    Insert(NewMember('role', mkChoice, rsMemberRole, RoleChoices), Result, Length(Result));
  if Group = ogPoint then
  begin
    Insert(NewMember('marker', mkChoice, rsMemberMarker, Joined(POINT_MARKER_NAMES)), Result, Length(Result));
    Insert(NewMember(MARKER_SIZE_FIELD, mkLength, rsMemberMarkerSize), Result, Length(Result));
  end;
end;

function FindOperationInfo(const TypeName: string; out Info: TOperationInfo): boolean;
var
  Candidate: TOperationInfo;
begin
  Info := Default(TOperationInfo);
  for Candidate in OperationInfos do
    if Candidate.TypeName = TypeName then
    begin
      Info := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function FindMember(const Info: TOperationInfo; const AName: string; out Member: TOperationMember): boolean;
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
  for Candidate in CommonMembers(Info.Group) do
    if (Candidate.Name = AName) or (Candidate.Name = AName + '[]') then
    begin
      Member := Candidate;
      Exit(True);
    end;
  Result := False;
end;

end.
