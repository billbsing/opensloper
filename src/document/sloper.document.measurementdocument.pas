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

// The measurement file being edited in the measurements app, with its own undo
// history. Like TLayoutDocument, a change records the saved text before it.
// It also watches the file: another app can change it at any time, so unsaved
// edits are merged with that change by key. Depends on src/core only.
unit Sloper.Document.MeasurementDocument;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Core.Measurements, Sloper.Core.TextHistory;

type
  // fcReloaded: the file changed and nothing was unsaved. fcMerged: unsaved
  // edits were merged with it. fcConflict: both changed a key, see Conflicts.
  TMeasurementFileCheck = (fcSame, fcReloaded, fcMerged, fcConflict);

  TMeasurementDocument = class
  private
    FSet: TMeasurementSet;
    FFileName: string;
    FHistory: TTextHistory;
    // What Modified compares with
    FSavedText: string;
    // The file as last read or written, the common base of a merge
    FBaseText: string;
    // The file's text seen changing, and the text a conflict is waiting on
    FPendingText, FConflictText: string;
    FConflicts: TStringArray;
    FChangeOpen: boolean;
    FBefore, FDescription: string;
    FOnChange: TNotifyEvent;
    function GetModified: boolean;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
    procedure Changed;
    procedure Restore(const Text: string);
    // Takes the file's text as the new base, keeping the set's edits
    procedure AdoptFile(const Text: string);
    function Merge(const FileText: string; const TakeTheirs: TStringArray; out MergedText: string; out Conflicts: TStringArray): boolean;
    function FreeKey: string;
    function AddKey(const Key, Description: string): TMeasurement;
  public
    constructor Create;
    destructor Destroy; override;
    procedure New;
    // Starts a new, unnamed file with what an import made, not yet saved
    procedure TakeImported(Imported: TMeasurementSet);
    function Open(const AFileName: string; out ErrorMessage: string): boolean;
    // Written atomically. Refused when the open file has changed on disk
    // since it was read, until CheckFile has taken that change in.
    function Save(const AFileName: string; out ErrorMessage: string): boolean;
    // Call regularly. A file seen changing may still be being written, so it
    // has to read the same on two checks running before it is taken in.
    function CheckFile: TMeasurementFileCheck;
    // After fcConflict: the keys in TakeTheirs get the file's version, the
    // others keep the edits here
    procedure ResolveConflicts(const TakeTheirs: TStringArray);

    procedure BeginChange(const Description: string);
    // A step that matches the last one's non-empty key, within a second, joins it
    procedure EndChange(const MergeKey: string = '');
    procedure CancelChange;
    procedure Undo;
    procedure Redo;

    // One undo step each. Those that can be refused say why and change nothing.
    procedure SetName(const AName: string);
    procedure SetNotes(const ANotes: string);
    function AddMeasurement: TMeasurement;
    // A named one, as from the catalogue
    function AddKnown(const Key, Description: string; out ErrorMessage: string): boolean;
    procedure DeleteMeasurement(Index: integer);
    procedure MoveMeasurement(Index, NewIndex: integer);
    function RenameKey(Index: integer; const NewKey: string; out ErrorMessage: string): boolean;
    procedure SetDescription(Index: integer; const Description: string);
    procedure SetValue(Index, SizeIndex: integer; Value: double);
    // Only a size table can have no value
    function ClearValue(Index, SizeIndex: integer; out ErrorMessage: string): boolean;
    function AddSize(const Size: string; out ErrorMessage: string): boolean;
    function RenameSize(Index: integer; const NewSize: string; out ErrorMessage: string): boolean;
    function DeleteSize(Index: integer; out ErrorMessage: string): boolean;
    procedure MoveSize(Index, NewIndex: integer);

    property Measurements: TMeasurementSet read FSet;
    property FileName: string read FFileName;
    property Conflicts: TStringArray read FConflicts;
    property Modified: boolean read GetModified;
    property CanUndo: boolean read GetCanUndo;
    property CanRedo: boolean read GetCanRedo;
    property UndoDescription: string read GetUndoDescription;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

resourcestring
  rsFileChangedOnDisk = 'The file has changed on disk. Its changes are being taken in; save again in a moment';
  rsNeedsAValue = 'A set with no sizes needs a value for every measurement';
  rsChangeName = 'Change name';
  rsChangeNotes = 'Change notes';
  rsChangeAdd = 'Add measurement';
  rsChangeDelete = 'Delete measurement';
  rsChangeMove = 'Move measurement';
  rsChangeRename = 'Rename measurement';
  rsChangeDescription = 'Change description';
  rsChangeValue = 'Change value';
  rsChangeAddSize = 'Add size';
  rsChangeRenameSize = 'Rename size';
  rsChangeDeleteSize = 'Delete size';
  rsChangeMoveSize = 'Move size';

implementation

uses
  Sloper.Core.JSON;

const
  NewKeyStem = 'measurement';

constructor TMeasurementDocument.Create;
begin
  FSet := TMeasurementSet.Create;
  FHistory := TTextHistory.Create;
  FSavedText := FSet.SaveToText;
end;

destructor TMeasurementDocument.Destroy;
begin
  FreeAndNil(FHistory);
  FreeAndNil(FSet);
  inherited Destroy;
end;

procedure TMeasurementDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TMeasurementDocument.GetModified: boolean;
begin
  Result := FSet.SaveToText <> FSavedText;
end;

function TMeasurementDocument.GetCanUndo: boolean;
begin
  Result := FHistory.CanUndo;
end;

function TMeasurementDocument.GetCanRedo: boolean;
begin
  Result := FHistory.CanRedo;
end;

function TMeasurementDocument.GetUndoDescription: string;
begin
  Result := FHistory.UndoDescription;
end;

procedure TMeasurementDocument.New;
begin
  FSet.Clear;
  FFileName := '';
  FBaseText := '';
  FPendingText := '';
  FHistory.Clear;
  FSavedText := FSet.SaveToText;
  Changed;
end;

procedure TMeasurementDocument.TakeImported(Imported: TMeasurementSet);
var
  Err: string;
begin
  FSet.LoadFromText(Imported.SaveToText, Err);
  FFileName := '';
  FBaseText := '';
  FPendingText := '';
  FHistory.Clear;
  // Not saved yet, so closing it asks
  FSavedText := '';
  Changed;
end;

function TMeasurementDocument.Open(const AFileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
  Loaded: TMeasurementSet;
begin
  Result := False;
  if not ReadTextFile(AFileName, Text, ErrorMessage) then
    Exit;
  Loaded := TMeasurementSet.Create;
  try
    if not Loaded.LoadFromText(Text, ErrorMessage) then
      Exit;
    FreeAndNil(FSet);
    FSet := Loaded;
    Loaded := nil;
  finally
    FreeAndNil(Loaded);
  end;
  FFileName := AFileName;
  FBaseText := Text;
  FPendingText := '';
  FHistory.Clear;
  FSavedText := FSet.SaveToText;
  Changed;
  Result := True;
end;

function TMeasurementDocument.Save(const AFileName: string; out ErrorMessage: string): boolean;
var
  OnDisk, Text: string;
begin
  ErrorMessage := '';
  if (FFileName <> '') and SameFileName(ExpandFileName(AFileName), ExpandFileName(FFileName)) and
    ReadTextFile(FFileName, OnDisk, ErrorMessage) and (OnDisk <> FBaseText) then
  begin
    ErrorMessage := rsFileChangedOnDisk;
    Exit(False);
  end;
  Text := FSet.SaveToText;
  Result := WriteTextFileAtomic(AFileName, Text, ErrorMessage);
  if not Result then
    Exit;
  FFileName := AFileName;
  FBaseText := Text;
  FSavedText := Text;
  FPendingText := '';
  FHistory.EndMerging;
  Changed;
end;

function TMeasurementDocument.Merge(const FileText: string; const TakeTheirs: TStringArray; out MergedText: string; out Conflicts: TStringArray): boolean;
var
  Base, Theirs, Merged: TMeasurementSet;
  Err: string;
begin
  Conflicts := nil;
  MergedText := '';
  Base := nil;
  Theirs := nil;
  Merged := nil;
  try
    Base := TMeasurementSet.Create;
    Theirs := TMeasurementSet.Create;
    Merged := TMeasurementSet.Create;
    Result := Base.LoadFromText(FBaseText, Err) and Theirs.LoadFromText(FileText, Err);
    if not Result then
      Exit;
    MergeMeasurementSets(Base, FSet, Theirs, TakeTheirs, Merged, Conflicts);
    MergedText := Merged.SaveToText;
  finally
    FreeAndNil(Merged);
    FreeAndNil(Theirs);
    FreeAndNil(Base);
  end;
end;

procedure TMeasurementDocument.AdoptFile(const Text: string);
var
  Err: string;
  Theirs: TMeasurementSet;
begin
  FBaseText := Text;
  Theirs := TMeasurementSet.Create;
  try
    if Theirs.LoadFromText(Text, Err) then
      FSavedText := Theirs.SaveToText;
  finally
    FreeAndNil(Theirs);
  end;
  // An older step would bring back what the file has just replaced
  FHistory.Clear;
end;

function TMeasurementDocument.CheckFile: TMeasurementFileCheck;
var
  Text, MergedText, Err: string;
  Readable: TMeasurementSet;
  Found: TStringArray;
begin
  Result := fcSame;
  if (FFileName = '') or FChangeOpen or (FConflicts <> nil) or not ReadTextFile(FFileName, Text, Err) or (Text = FBaseText) then
  begin
    FPendingText := '';
    Exit;
  end;
  if Text <> FPendingText then
  begin
    FPendingText := Text;
    Exit;
  end;
  FPendingText := '';
  Readable := TMeasurementSet.Create;
  try
    // A broken file is left for whoever is writing it to put right
    if not Readable.LoadFromText(Text, Err) then
      Exit;
  finally
    FreeAndNil(Readable);
  end;
  if not Modified then
  begin
    AdoptFile(Text);
    FSet.LoadFromText(Text, Err);
    Changed;
    Exit(fcReloaded);
  end;
  if not Merge(Text, nil, MergedText, Found) then
    Exit;
  if Found <> nil then
  begin
    FConflicts := Found;
    FConflictText := Text;
    Exit(fcConflict);
  end;
  AdoptFile(Text);
  FSet.LoadFromText(MergedText, Err);
  Changed;
  Result := fcMerged;
end;

procedure TMeasurementDocument.ResolveConflicts(const TakeTheirs: TStringArray);
var
  MergedText, Err: string;
  Remaining: TStringArray;
begin
  if FConflicts = nil then
    Exit;
  FConflicts := nil;
  if not Merge(FConflictText, TakeTheirs, MergedText, Remaining) then
    Exit;
  AdoptFile(FConflictText);
  // Conflicts not in TakeTheirs keep the edits here, as Merge leaves them
  FSet.LoadFromText(MergedText, Err);
  Changed;
end;

procedure TMeasurementDocument.BeginChange(const Description: string);
begin
  FBefore := FSet.SaveToText;
  FDescription := Description;
  FChangeOpen := True;
end;

procedure TMeasurementDocument.EndChange(const MergeKey: string);
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  if FSet.SaveToText = FBefore then
    Exit;
  FHistory.Add(FBefore, FDescription, MergeKey);
  Changed;
end;

procedure TMeasurementDocument.CancelChange;
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  Restore(FBefore);
end;

// Keeps the selected size, which the text does not hold
procedure TMeasurementDocument.Restore(const Text: string);
var
  Size, Err: string;
begin
  Size := FSet.SizeName;
  FSet.LoadFromText(Text, Err);
  FSet.SelectSize(Size);
  Changed;
end;

procedure TMeasurementDocument.Undo;
begin
  if CanUndo then
    Restore(FHistory.Undo(FSet.SaveToText));
end;

procedure TMeasurementDocument.Redo;
begin
  if CanRedo then
    Restore(FHistory.Redo(FSet.SaveToText));
end;

procedure TMeasurementDocument.SetName(const AName: string);
begin
  BeginChange(rsChangeName);
  FSet.Name := AName;
  EndChange;
end;

procedure TMeasurementDocument.SetNotes(const ANotes: string);
begin
  BeginChange(rsChangeNotes);
  FSet.Notes := ANotes;
  EndChange;
end;

// The next free number is appended directly, as copies are named
function TMeasurementDocument.FreeKey: string;
var
  Number: integer;
begin
  Result := NewKeyStem;
  Number := 1;
  while FSet.Find(Result) <> nil do
  begin
    Inc(Number);
    Result := NewKeyStem + IntToStr(Number);
  end;
end;

// A size table starts with no values; a personal set has to have one
function TMeasurementDocument.AddKey(const Key, Description: string): TMeasurement;
var
  Index: integer;
begin
  BeginChange(rsChangeAdd);
  Result := FSet.Add(Key, 0, Description);
  for Index := 0 to FSet.SizeCount - 1 do
    Result.ClearValueFor(Index);
  EndChange;
end;

function TMeasurementDocument.AddMeasurement: TMeasurement;
begin
  Result := AddKey(FreeKey, '');
end;

function TMeasurementDocument.AddKnown(const Key, Description: string; out ErrorMessage: string): boolean;
begin
  Result := FSet.CheckKey(Key, nil, ErrorMessage);
  if Result then
    AddKey(Key, Description);
end;

procedure TMeasurementDocument.DeleteMeasurement(Index: integer);
begin
  BeginChange(rsChangeDelete);
  FSet.Delete(FSet[Index]);
  EndChange;
end;

procedure TMeasurementDocument.MoveMeasurement(Index, NewIndex: integer);
begin
  BeginChange(rsChangeMove);
  FSet.Move(FSet[Index], NewIndex);
  EndChange;
end;

function TMeasurementDocument.RenameKey(Index: integer; const NewKey: string; out ErrorMessage: string): boolean;
begin
  Result := FSet.CheckKey(NewKey, FSet[Index], ErrorMessage);
  if not Result then
    Exit;
  BeginChange(rsChangeRename);
  FSet.Rename(FSet[Index], NewKey);
  EndChange;
end;

procedure TMeasurementDocument.SetDescription(Index: integer; const Description: string);
begin
  BeginChange(rsChangeDescription);
  FSet[Index].Description := Description;
  EndChange;
end;

procedure TMeasurementDocument.SetValue(Index, SizeIndex: integer; Value: double);
begin
  BeginChange(rsChangeValue);
  FSet[Index].SetValueFor(SizeIndex, Value);
  EndChange;
end;

function TMeasurementDocument.ClearValue(Index, SizeIndex: integer; out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Result := FSet.SizeCount > 0;
  if not Result then
  begin
    ErrorMessage := rsNeedsAValue;
    Exit;
  end;
  BeginChange(rsChangeValue);
  FSet[Index].ClearValueFor(SizeIndex);
  EndChange;
end;

function TMeasurementDocument.AddSize(const Size: string; out ErrorMessage: string): boolean;
begin
  Result := FSet.CheckSize(Size, -1, ErrorMessage);
  if not Result then
    Exit;
  BeginChange(rsChangeAddSize);
  FSet.AddSize(Size);
  EndChange;
end;

function TMeasurementDocument.RenameSize(Index: integer; const NewSize: string; out ErrorMessage: string): boolean;
begin
  Result := FSet.CheckSize(NewSize, Index, ErrorMessage);
  if not Result then
    Exit;
  BeginChange(rsChangeRenameSize);
  FSet.RenameSize(Index, NewSize);
  EndChange;
end;

function TMeasurementDocument.DeleteSize(Index: integer; out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Result := FSet.SizeCount > 1;
  if not Result then
  begin
    ErrorMessage := rsMeasurementLastSize;
    Exit;
  end;
  BeginChange(rsChangeDeleteSize);
  FSet.DeleteSize(Index);
  EndChange;
end;

procedure TMeasurementDocument.MoveSize(Index, NewIndex: integer);
begin
  BeginChange(rsChangeMoveSize);
  FSet.MoveSize(Index, NewIndex);
  EndChange;
end;

end.
