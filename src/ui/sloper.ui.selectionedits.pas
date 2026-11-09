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

// Edits made to what is selected on the canvas, from the Edit and Tools
// menus and the arrow and Delete keys. Each checks that the selection fits,
// makes its change as one undo step through the document, and says what to
// select and show afterwards; the canvas only applies that. Kept free of the
// LCL so it can be unit-tested.
unit Sloper.UI.SelectionEdits;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern, Sloper.Core.Fragment,
  Sloper.Document.PatternDocument;

type
  TSelectionEdit = record
    // The change was made
    Done: boolean;
    // Select Selection afterwards; otherwise the selection stays as it is
    Reselect: boolean;
    Selection: TStringArray;
    // For the status bar: what was done, or why not; empty leaves it as it is
    Message: string;
  end;

// Moves the selected points and notes by Offset (mm); a run of nudges to
// the same objects is one undo step
function NudgeSelection(Document: TPatternDocument; const Selection: TStringArray; const Offset: TVec2): TSelectionEdit;
// Description names the undo step: Delete, or Cut
function DeleteSelection(Document: TPatternDocument; const Selection: TStringArray; const Description: string): TSelectionEdit;
// Copied.Text is empty when nothing selected can be copied
function CopySelection(Document: TPatternDocument; const Selection: TStringArray; out Copied: TFragmentCopy): TSelectionEdit;
// Everything selected must be copied, or deleting would lose what is left out
function CutSelection(Document: TPatternDocument; const Selection: TStringArray; out Copied: TFragmentCopy): TSelectionEdit;
function PasteFragmentText(Document: TPatternDocument; const FragmentText: string): TSelectionEdit;
// An edge and a point on it
function SplitSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
// An arc about the one selected point; circles have their own tool
function AddArcAtSelection(Document: TPatternDocument; const Selection: TStringArray; Role: TEdgeRole): TSelectionEdit;
// One edge, or a run of them in any order, which follows the first selected
function OffsetSelection(Document: TPatternDocument; const Selection: TStringArray; Side: TOffsetSide): TSelectionEdit;
// Edges of a piece, selected with it, offset inside it (as a stitch line)
// or outside it (as a construction line)
function OffsetSelectionInPiece(Document: TPatternDocument; const Selection: TStringArray; Inside: boolean): TSelectionEdit;
// Every selected edge to a curve, or to a line
function ConvertSelection(Document: TPatternDocument; const Selection: TStringArray; ToCurve: boolean): TSelectionEdit;
function MergeSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
function BreakSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
// The two straight edges that meet at the corner
function RoundSelectedCorner(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
// A repeat between the two selected points or along the one selected edge;
// other selected objects are left out. Its first point is selected, as that
// is where the repeat's count is edited
function AddRepeatAtSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
// A marking of the selected piece on the selected edge or point; for mkPoint,
// every selected point or repeat becomes a hole instead
function MarkSelection(Document: TPatternDocument; const Selection: TStringArray; Kind: TMarkingKind): TSelectionEdit;
// The selected piece's markings on the selected point or edge
function UnmarkSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
// Adds the transform, its sources and pivot or axis already chosen
function AddTransform(Document: TPatternDocument; const Spec: TTransformSpec): TSelectionEdit;
// For the status bar: "A, B, Line_A_B"
function ObjectNames(Pattern: TPattern; const Keys: TStringArray): string;

resourcestring
  rsSelectionNudge = 'Nudge';
  rsSelectionDelete = 'Delete';
  rsSelectionCut = 'Cut';
  rsSelectionCutDone = 'Cut %s';
  rsSelectionCannotCut = 'Nothing was cut: %s cannot be copied; only points and edges can';
  rsSelectionPickToCopy = 'Select the points and edges to copy first';
  rsSelectionCannotCopy = '%s cannot be copied; only points and edges can';
  rsSelectionCopied = 'Copied %s';
  rsSelectionCopiedLeftOut = 'Copied %s; left out %s, which cannot be copied';
  rsSelectionPaste = 'Paste';
  rsSelectionPasted = 'Pasted %s';
  rsSelectionPastedRenamed = 'Pasted %s; renamed %s';
  rsSelectionSplit = 'Split edge';
  rsSelectionAddArc = 'Add circle or arc';
  rsSelectionPickCentre = 'Select the point for its centre first';
  rsSelectionAddOffset = 'Add offset edge';
  rsSelectionPickEdgeToOffset = 'Select the edges to offset first';
  rsSelectionPickPieceEdges = 'Select the piece and the edges of it to offset';
  rsSelectionConvertToLine = 'Change to line';
  rsSelectionConvertToCurve = 'Change to curve';
  rsSelectionPickEdgesToConvert = 'Select the edges to change first';
  rsSelectionMergePoints = 'Merge points';
  rsSelectionMerged = 'Merged %d points into %s';
  rsSelectionBreakPoint = 'Break point';
  rsSelectionPickPointToBreak = 'Select the point to break first';
  rsSelectionBroken = 'Broke %s into %d points';
  rsSelectionRoundCorner = 'Round corner';
  rsSelectionPickCornerEdges = 'Select the two straight edges that meet at the corner';
  rsSelectionAddRepeat = 'Add repeat';
  rsSelectionPickRepeat = 'Select two points, or one line or curve, to repeat along';
  rsSelectionRepeatAdded = 'Added %s; set its count in the properties';
  rsSelectionAddMarking = 'Add marking';
  rsSelectionPickHole = 'Select the points to mark as holes';
  rsSelectionPickMarkingEdge = 'Select the piece and the edge for the marking';
  rsSelectionPickLine = 'Select the piece and the marking line or marked point to attach to it';
  rsSelectionRemoveMarking = 'Remove marking';
  rsSelectionPickMarkingToRemove = 'Select the piece and the point or edge of the marking to remove';
  rsSelectionTransform = 'Add %s';

implementation

uses
  StrUtils, Sloper.Core.Evaluator, Sloper.Core.Units, Sloper.Core.Drag, Sloper.Core.Note, Sloper.Core.Transform, Sloper.UI.Scene;

const
  // A new arc's sweep, as a starting point for typing the real values; its
  // radius and other starting lengths are per unit (StartingLengths)
  NewArcSweep = '90';
  // A new repeat's count, to be changed in the properties
  NewRepeatCount = '3';

function Refused(const Reason: string): TSelectionEdit;
begin
  Result := Default(TSelectionEdit);
  Result.Message := Reason;
end;

// Ends the change begun for an edit; when it fails, Message is the pattern's
// reason, read before cancelling puts the pattern back
function Commit(Document: TPatternDocument; Done: boolean): TSelectionEdit;
var
  Reason: string;
begin
  Reason := Document.Pattern.LastError;
  Result := Default(TSelectionEdit);
  Result.Done := Document.Commit(Done);
  if not Result.Done then
    Result.Message := Reason;
end;

// As Commit, then selects Keys and shows Success
function CommitSelecting(Document: TPatternDocument; Done: boolean; const Keys: TStringArray; const Success: string = ''): TSelectionEdit;
begin
  Result := Commit(Document, Done);
  if not Result.Done then
    Exit;
  Result.Reselect := True;
  Result.Selection := Keys;
  Result.Message := Success;
end;

// The key of an object just added, read before the change ends
function KeyOf(Node: TEvalNode): TStringArray;
begin
  Result := nil;
  if Assigned(Node) then
    Result := [Node.Key];
end;

function ObjectNames(Pattern: TPattern; const Keys: TStringArray): string;
var
  Key: string;
  Node: TEvalNode;
begin
  Result := '';
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if not Assigned(Node) then
      Continue;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Node.DisplayName;
  end;
end;

// A repeat's point stands for its repeat, which holds the marker
function MarkerKey(Pattern: TPattern; const Key: string): string;
var
  Node: TEvalNode;
begin
  Result := Key;
  Node := Pattern.FindNode(Key);
  if Node is TRepeatPoint then
    Result := TRepeatPoint(Node).Source.Key;
end;

function SelectedPiece(Pattern: TPattern; const Selection: TStringArray): TPieceObject;
var
  Key: string;
  Node: TEvalNode;
begin
  Result := nil;
  for Key in Selection do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TPieceObject then
      Result := TPieceObject(Node);
  end;
end;

function NudgeSelection(Document: TPatternDocument; const Selection: TStringArray; const Offset: TVec2): TSelectionEdit;
var
  Selected, Reason, MergeKey: string;
  Node: TEvalNode;
  Moved, Done: boolean;
begin
  Result := Default(TSelectionEdit);
  if Length(Selection) = 0 then
    Exit;
  Document.BeginChange(rsSelectionNudge);
  Moved := False;
  MergeKey := 'nudge';
  for Selected in Selection do
  begin
    Node := Document.Pattern.FindNode(Selected);
    if not (Node is TPointObject) and not (Node is TNoteObject) then
      Continue;
    MergeKey := MergeKey + ':' + Selected;
    if Node is TNoteObject then
      Done := DragNote(Document.Pattern, TNoteObject(Node), TNoteObject(Node).Position + Offset, Reason)
    else
      Done := DragPoint(Document.Pattern, TPointObject(Node), TPointObject(Node).Position + Offset, Reason);
    if not Done then
    begin
      Document.CancelChange;
      Exit(Refused(Reason));
    end;
    Moved := True;
  end;
  Result.Done := Document.Commit(Moved, MergeKey);
end;

function DeleteSelection(Document: TPatternDocument; const Selection: TStringArray; const Description: string): TSelectionEdit;
var
  Index: integer;
  Node: TEvalNode;
begin
  Result := Default(TSelectionEdit);
  if Length(Selection) = 0 then
    Exit;
  Document.BeginChange(Description);
  // Later objects can use earlier ones, so delete from the end of the pattern
  for Index := Document.Pattern.ObjectCount - 1 downto 0 do
  begin
    Node := Document.Pattern.Objects[Index];
    if (IndexStr(Node.Key, Selection) >= 0) and not Document.Pattern.Delete(Node) then
    begin
      Result.Message := Document.Pattern.LastError;
      Document.CancelChange;
      Exit;
    end;
  end;
  Document.EndChange;
  Result.Done := True;
  Result.Reselect := True;
end;

function CopySelection(Document: TPatternDocument; const Selection: TStringArray; out Copied: TFragmentCopy): TSelectionEdit;
var
  LeftOut: string;
begin
  Copied := Default(TFragmentCopy);
  if Length(Selection) = 0 then
    Exit(Refused(rsSelectionPickToCopy));
  Result := Default(TSelectionEdit);
  Copied := CopyFragment(Document.Pattern, Selection);
  Result.Done := Copied.Text <> '';
  LeftOut := string.Join(', ', Copied.LeftOut);
  if not Result.Done then
    Result.Message := Format(rsSelectionCannotCopy, [LeftOut])
  else if LeftOut <> '' then
    Result.Message := Format(rsSelectionCopiedLeftOut, [ObjectNames(Document.Pattern, Copied.Keys), LeftOut])
  else
    Result.Message := Format(rsSelectionCopied, [ObjectNames(Document.Pattern, Copied.Keys)]);
end;

function CutSelection(Document: TPatternDocument; const Selection: TStringArray; out Copied: TFragmentCopy): TSelectionEdit;
var
  Names: string;
begin
  Copied := Default(TFragmentCopy);
  if Length(Selection) = 0 then
    Exit(Refused(rsSelectionPickToCopy));
  Copied := CopyFragment(Document.Pattern, Selection);
  if Length(Copied.LeftOut) > 0 then
  begin
    Result := Refused(Format(rsSelectionCannotCut, [string.Join(', ', Copied.LeftOut)]));
    Copied := Default(TFragmentCopy);
    Exit;
  end;
  Names := ObjectNames(Document.Pattern, Copied.Keys);
  Result := DeleteSelection(Document, Selection, rsSelectionCut);
  if Result.Done then
    Result.Message := Format(rsSelectionCutDone, [Names])
  else
    Copied := Default(TFragmentCopy);
end;

function PasteFragmentText(Document: TPatternDocument; const FragmentText: string): TSelectionEdit;
var
  Pasted: TFragmentPaste;
  Reason: string;
begin
  Document.BeginChange(rsSelectionPaste);
  if not Document.Commit(PasteFragment(Document.Pattern, FragmentText, Pasted, Reason)) then
    Exit(Refused(Reason));
  Result := Default(TSelectionEdit);
  Result.Done := True;
  Result.Reselect := True;
  Result.Selection := Pasted.Keys;
  if Length(Pasted.Renamed) > 0 then
    Result.Message := Format(rsSelectionPastedRenamed, [ObjectNames(Document.Pattern, Pasted.Keys), string.Join(', ', Pasted.Renamed)])
  else
    Result.Message := Format(rsSelectionPasted, [ObjectNames(Document.Pattern, Pasted.Keys)]);
end;

function SplitSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  EdgeKey, PointKey, Reason: string;
  First, Second: TSplitPart;
  Parts: TStringArray;
  Done: boolean;
begin
  if not SplitFromSelection(Document.Pattern, Selection, EdgeKey, PointKey, Reason) then
    Exit(Refused(Reason));
  Document.BeginChange(rsSelectionSplit);
  Done := Document.Pattern.SplitEdge(EdgeKey, Document.Pattern.UsePoint(PointKey), First, Second);
  Parts := nil;
  if Done then
    Parts := [First.Key, Second.Key];
  Result := CommitSelecting(Document, Done, Parts);
end;

function AddArcAtSelection(Document: TPatternDocument; const Selection: TStringArray; Role: TEdgeRole): TSelectionEdit;
var
  Node: TEvalNode;
  Added: TEdgeObject;
begin
  Node := nil;
  if Length(Selection) = 1 then
    Node := Document.Pattern.FindNode(Selection[0]);
  if not (Node is TPointObject) then
    Exit(Refused(rsSelectionPickCentre));
  Document.BeginChange(rsSelectionAddArc);
  Added := Document.Pattern.AddArc(Document.Pattern.UsePoint(Node.Key), StartingLengths[slArcRadius, Document.Pattern.Units], '0', NewArcSweep, Role);
  Result := CommitSelecting(Document, Assigned(Added), KeyOf(Added));
end;

function OffsetSelection(Document: TPatternDocument; const Selection: TStringArray; Side: TOffsetSide): TSelectionEdit;
var
  Edges: TStringArray;
  Run: TRunEdgeArray;
  Added: TOffsetEdge;
  Distance: string;
begin
  Edges := EdgeKeys(Document.Pattern, Selection);
  if (Length(Edges) = 0) or (Length(Edges) <> Length(Selection)) then
    Exit(Refused(rsSelectionPickEdgeToOffset));
  Distance := StartingLengths[slOffsetDistance, Document.Pattern.Units];
  Document.BeginChange(rsSelectionAddOffset);
  Added := nil;
  if Length(Edges) = 1 then
    Added := Document.Pattern.AddOffsetEdge(Edges[0], Distance, Side, erConstruction)
  else if Document.Pattern.ChainRun(Edges, Run) then
    Added := Document.Pattern.AddOffsetRun(Run, Distance, Side, erConstruction);
  Result := CommitSelecting(Document, Assigned(Added), KeyOf(Added));
end;

function OffsetSelectionInPiece(Document: TPatternDocument; const Selection: TStringArray; Inside: boolean): TSelectionEdit;
var
  Piece: TPieceObject;
  Edges: TStringArray;
  Run: TRunEdgeArray;
  Side: TOffsetSide;
  Role: TEdgeRole;
  Added: TOffsetEdge;
begin
  Piece := SelectedPiece(Document.Pattern, Selection);
  Edges := EdgeKeys(Document.Pattern, Selection);
  if not Assigned(Piece) or (Length(Edges) = 0) or (Length(Edges) + 1 <> Length(Selection)) then
    Exit(Refused(rsSelectionPickPieceEdges));
  Role := erConstruction;
  if Inside then
    Role := erStitch;
  Document.BeginChange(rsSelectionAddOffset);
  Added := nil;
  if Document.Pattern.PieceRun(Piece, Edges, Inside, Run, Side) then
    Added := Document.Pattern.AddOffsetRun(Run, StartingLengths[slOffsetDistance, Document.Pattern.Units], Side, Role);
  Result := CommitSelecting(Document, Assigned(Added), KeyOf(Added));
end;

function ConvertSelection(Document: TPatternDocument; const Selection: TStringArray; ToCurve: boolean): TSelectionEdit;
var
  Key: string;
  Edge: TEdgeObject;
  Edges: TStringArray;
  Done: boolean;
begin
  Edges := EdgeKeys(Document.Pattern, Selection);
  if Length(Edges) = 0 then
    Exit(Refused(rsSelectionPickEdgesToConvert));
  if ToCurve then
    Document.BeginChange(rsSelectionConvertToCurve)
  else
    Document.BeginChange(rsSelectionConvertToLine);
  Done := True;
  // Each edge keeps its ID, so it is found again after the one before it changed
  for Key in Edges do
  begin
    Edge := TEdgeObject(Document.Pattern.FindNode(Key));
    if ToCurve then
      Done := Assigned(Document.Pattern.ConvertToCurve(Edge))
    else
      Done := Assigned(Document.Pattern.ConvertToLine(Edge));
    if not Done then
      Break;
  end;
  Result := Commit(Document, Done);
end;

function MergeSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Kept: TPointObject;
  Key, KeptName: string;
  Points: TStringArray;
begin
  Points := nil;
  for Key in Selection do
    if Document.Pattern.FindNode(Key) is TPointObject then
      Insert(Key, Points, Length(Points));
  Document.BeginChange(rsSelectionMergePoints);
  Kept := Document.Pattern.MergePoints(Points);
  KeptName := '';
  if Assigned(Kept) then
    KeptName := Kept.Name;
  Result := CommitSelecting(Document, Assigned(Kept), KeyOf(Kept), Format(rsSelectionMerged, [Length(Points), KeptName]));
end;

function BreakSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Node: TEvalNode;
  Broken: TPointObjectArray;
  Keys: TStringArray;
  Item: TPointObject;
  OldName: string;
begin
  Node := nil;
  if Length(Selection) = 1 then
    Node := Document.Pattern.FindNode(Selection[0]);
  if not (Node is TPointObject) then
    Exit(Refused(rsSelectionPickPointToBreak));
  OldName := Node.DisplayName;
  Document.BeginChange(rsSelectionBreakPoint);
  Broken := Document.Pattern.BreakPoint(TPointObject(Node));
  Keys := nil;
  for Item in Broken do
    Insert(Item.Key, Keys, Length(Keys));
  Result := CommitSelecting(Document, Length(Broken) > 0, Keys, Format(rsSelectionBroken, [OldName, Length(Keys)]));
end;

function RoundSelectedCorner(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Added: TCornerArc;
begin
  if (Length(Selection) <> 2) or not (Document.Pattern.FindNode(Selection[0]) is TEdgeObject) or not
    (Document.Pattern.FindNode(Selection[1]) is TEdgeObject) then
    Exit(Refused(rsSelectionPickCornerEdges));
  Document.BeginChange(rsSelectionRoundCorner);
  Added := Document.Pattern.AddRoundCorner(Selection[0], Selection[1], StartingLengths[slCornerRadius, Document.Pattern.Units]);
  Result := CommitSelecting(Document, Assigned(Added), KeyOf(Added));
end;

function AddRepeatAtSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Key, AddedKey: string;
  Node: TEvalNode;
  Points, Edges: TStringArray;
  Pattern: TPattern;
  Added: TRepeatObject;
begin
  Pattern := Document.Pattern;
  Points := nil;
  for Key in Selection do
    if Pattern.FindNode(Key) is TPointObject then
      Insert(Key, Points, Length(Points));
  Edges := EdgeKeys(Pattern, Selection);
  if not ((Length(Points) = 2) and (Length(Edges) = 0) or (Length(Points) = 0) and (Length(Edges) = 1)) then
    Exit(Refused(rsSelectionPickRepeat));
  Document.BeginChange(rsSelectionAddRepeat);
  // A repeat's own point between them is given an ID, as anything using it is
  if Length(Edges) = 1 then
    Added := Pattern.AddRepeatOnEdge('', Edges[0], NewRepeatCount, True)
  else
    Added := Pattern.AddRepeatBetween('', Pattern.UsePoint(Points[0]), Pattern.UsePoint(Points[1]), NewRepeatCount, True);
  AddedKey := '';
  if Assigned(Added) then
    AddedKey := Added.Key;
  Result := Commit(Document, Assigned(Added));
  if not Result.Done then
    Exit;
  Node := Pattern.FindNode(AddedKey);
  Result.Message := Format(rsSelectionRepeatAdded, [Node.DisplayName]);
  if (Node is TRepeatObject) and Assigned(TRepeatObject(Node).Item(1)) then
  begin
    Result.Reselect := True;
    Result.Selection := [TRepeatObject(Node).Item(1).Key];
  end;
end;

// Every selected point or repeat becomes a hole, joining the pieces it lies in
function MarkHoles(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Key, Target: string;
  Node: TEvalNode;
  Targets: TStringArray;
  Done: boolean;
begin
  Targets := nil;
  for Key in Selection do
  begin
    Node := Document.Pattern.FindNode(Key);
    Target := MarkerKey(Document.Pattern, Key);
    if ((Node is TPointObject) or (Node is TRepeatObject)) and (TDraftObject(Document.Pattern.FindNode(Target)).Marker <> pmHole) and
      (IndexStr(Target, Targets) < 0) then
      Insert(Target, Targets, Length(Targets));
  end;
  if Length(Targets) = 0 then
    Exit(Refused(rsSelectionPickHole));
  Document.BeginChange(rsSelectionAddMarking);
  Done := True;
  for Target in Targets do
    Done := Done and Document.Pattern.SetMarker(Target, pmHole);
  Result := Commit(Document, Done);
end;

function MarkSelection(Document: TPatternDocument; const Selection: TStringArray; Kind: TMarkingKind): TSelectionEdit;
var
  Key, Target: string;
  Node: TEvalNode;
  Piece: TPieceObject;
  Done: boolean;
begin
  if Kind = mkPoint then
    Exit(MarkHoles(Document, Selection));
  Piece := nil;
  Target := '';
  for Key in Selection do
  begin
    Node := Document.Pattern.FindNode(Key);
    if Node is TPieceObject then
      Piece := TPieceObject(Node)
    else if (Node is TEdgeObject) or ((Kind = mkLine) and ((Node is TPointObject) or (Node is TRepeatObject))) then
      Target := MarkerKey(Document.Pattern, Key);
  end;
  if not Assigned(Piece) or (Target = '') or (Length(Selection) <> 2) then
  begin
    if Kind = mkLine then
      Exit(Refused(rsSelectionPickLine));
    Exit(Refused(rsSelectionPickMarkingEdge));
  end;
  Document.BeginChange(rsSelectionAddMarking);
  if Kind = mkStitchHoles then
    Done := Document.Pattern.AddStitchMarking(Piece, Target, StartingLengths[slStitchSpacing, Document.Pattern.Units],
      StartingLengths[slStitchSize, Document.Pattern.Units])
  else if Document.Pattern.FindNode(Target) is TEdgeObject then
    Done := Document.Pattern.AddLineMarking(Piece, Target)
  else
    Done := Document.Pattern.AddPointMarking(Piece, Target);
  Result := Commit(Document, Done);
end;

function UnmarkSelection(Document: TPatternDocument; const Selection: TStringArray): TSelectionEdit;
var
  Key, Target: string;
  Piece: TPieceObject;
  Index: integer;
  Done: boolean;
begin
  Piece := SelectedPiece(Document.Pattern, Selection);
  Target := '';
  for Key in Selection do
    if not (Document.Pattern.FindNode(Key) is TPieceObject) then
      Target := MarkerKey(Document.Pattern, Key);
  if not Assigned(Piece) or (Target = '') then
    Exit(Refused(rsSelectionPickMarkingToRemove));
  Document.BeginChange(rsSelectionRemoveMarking);
  Done := False;
  for Index := High(Piece.Markings) downto 0 do
    if (Piece.Markings[Index].PointKey = Target) or (Piece.Markings[Index].EdgeKey = Target) then
      Done := Document.Pattern.RemoveMarking(Piece, Index) or Done;
  Result := Default(TSelectionEdit);
  Result.Done := Document.Commit(Done);
  if not Result.Done then
    Result.Message := rsSelectionPickMarkingToRemove;
end;

function AddTransform(Document: TPatternDocument; const Spec: TTransformSpec): TSelectionEdit;
var
  Transform: TTransformObject;
begin
  Document.BeginChange(Format(rsSelectionTransform, [Spec.Name]));
  Transform := Document.Pattern.AddTransform(Spec);
  Result := CommitSelecting(Document, Assigned(Transform), KeyOf(Transform));
end;

end.
