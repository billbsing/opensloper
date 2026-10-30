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

// The open pattern: the model, its measurement set and file, undo and redo,
// and change notifications. Every user change goes through a change:

//   Document.BeginChange(rsAddPoint);
//   Document.Commit(Document.Pattern.AddFreePoint('', X, Y) <> nil);

// A change records the pattern's saved text before and after, so undo and
// redo restore exactly the earlier definitions. Undo, redo and cancel load
// that text again, which replaces the pattern's objects with new ones (the
// IDs stay the same): hold objects by ID, not by reference, across changes.
// No LCL dependency.
unit Sloper.Document.PatternDocument;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Measurements, Sloper.Core.Pattern;

const
  DefaultUndoLimit = 500;
  // Changes with the same merge key this close together become one step
  DefaultMergeSeconds = 1.0;

type
  EDocumentError = class(Exception);

  TPatternDocument = class;

  // dcPattern: definitions or results changed. dcObjectsReplaced: the
  // pattern's objects are new instances (undo, redo, cancel, load).
  // dcMeasurements: another measurement set. dcHistory: what can be undone
  // or redone. dcFile: file name or modified flag.
  TDocumentChange = (dcPattern, dcObjectsReplaced, dcMeasurements, dcHistory, dcFile);
  TDocumentChanges = set of TDocumentChange;
  TDocumentListener = procedure(Document: TPatternDocument; Changes: TDocumentChanges) of object;
  TDocumentClock = function: TDateTime of object;

  TCommand = class
  private
    FDescription: string;
  public
    constructor Create(const ADescription: string);
    // Does the change again (redo)
    procedure Execute; virtual; abstract;
    procedure Undo; virtual; abstract;
    // Shown as "Undo <Description>"
    property Description: string read FDescription;
  end;

  // A change to the pattern's definitions, kept as its saved text before and after
  TPatternChange = class(TCommand)
  private
    FDocument: TPatternDocument;
    FBefore, FAfter: string;
    FMergeKey: string;
    FTime: TDateTime;
  public
    constructor Create(ADocument: TPatternDocument; const ADescription, ABefore, AAfter, AMergeKey: string;
      ATime: TDateTime);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TCommandList = specialize TObjectList<TCommand>;

  TPatternDocument = class
  private
    FPattern: TPattern;
    FMeasurements: TMeasurementSet;
    FMeasurementPath: string;
    FMeasurementError: string;
    FMeasurementsChanged: boolean;
    FFileName: string;
    FUndo, FRedo: TCommandList;
    FSavedCount: integer;
    FChangeOpen: boolean;
    FChangeDescription: string;
    FChangeBefore: string;
    FListeners: array of TDocumentListener;
    FClock: TDocumentClock;
    FUndoLimit: integer;
    FMergeSeconds: double;
    function GetModified: boolean;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
    function GetRedoDescription: string;
    function CurrentTime: TDateTime;
    procedure Notify(Changes: TDocumentChanges);
    procedure ClearHistory;
    procedure ClearRedo;
    procedure TrimUndo;
    procedure RequireNoChange;
    function MeasurementFileFor(const PatternFileName: string): string;
    procedure ApplySnapshot(const Text: string);
    procedure SetMeasurementSet(ASet: TMeasurementSet; const APath: string);
  public
    constructor Create;
    destructor Destroy; override;

    // An empty pattern with no history and no file name. The measurement
    // set is kept.
    procedure NewPattern;
    // On failure the open pattern is unchanged. The pattern's measurement
    // file is loaded too; if that fails the pattern still opens, without a
    // measurement set, and MeasurementError says why.
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    // Makes the set in FileName current, or none for ''. Not an undo step,
    // but the pattern records it, so the document becomes modified. On
    // failure the current set is kept.
    function UseMeasurements(const FileName: string; out ErrorMessage: string): boolean;
    // A small edit to the current measurement file: it is re-read, this key
    // changed or added, and written, then the set is loaded again and the
    // pattern re-evaluated. Not an undo step and does not modify the pattern,
    // since the set is not part of it. On failure nothing changes.
    function ChangeMeasurement(const Key: string; Value: double; const Description: string;
      out Change: TMeasurementChange; out ErrorMessage: string): boolean;

    // A change: BeginChange, any number of edits to Pattern (with LiveUpdate
    // to show them, e.g. while dragging), then EndChange to record them as
    // one undo step, or CancelChange to put the pattern back. Changes do not
    // nest; beginning one while another is open raises EDocumentError.
    procedure BeginChange(const Description: string);
    // Records the change. A change with the same non-empty MergeKey as the
    // last step, within MergeSeconds, joins that step (arrow-key nudges,
    // spin box steps); if they cancel out, the step goes. False when nothing
    // changed.
    function EndChange(const MergeKey: string = ''): boolean;
    procedure CancelChange;
    // EndChange when Success, else CancelChange; for wrapping one edit:
    // Commit(Pattern.Rename(...))
    function Commit(Success: boolean; const MergeKey: string = ''): boolean;
    // Re-evaluates and notifies, without recording anything
    procedure LiveUpdate;

    // False while a change is open or there is nothing to undo or redo
    function Undo: boolean;
    function Redo: boolean;

    procedure AddListener(Listener: TDocumentListener);
    procedure RemoveListener(Listener: TDocumentListener);

    property Pattern: TPattern read FPattern;
    // nil when there is none
    property Measurements: TMeasurementSet read FMeasurements;
    // Full path of the measurement file; kept when loading it failed
    property MeasurementPath: string read FMeasurementPath;
    // Why the pattern's measurement file could not be loaded, or ''
    property MeasurementError: string read FMeasurementError;
    // Full path, or '' for a pattern not saved yet
    property FileName: string read FFileName;
    property Modified: boolean read GetModified;
    property ChangeOpen: boolean read FChangeOpen;
    property CanUndo: boolean read GetCanUndo;
    property CanRedo: boolean read GetCanRedo;
    property UndoDescription: string read GetUndoDescription;
    property RedoDescription: string read GetRedoDescription;
    // Oldest steps are dropped beyond this many
    property UndoLimit: integer read FUndoLimit write FUndoLimit;
    property MergeSeconds: double read FMergeSeconds write FMergeSeconds;
    // For tests; nil means Now
    property Clock: TDocumentClock read FClock write FClock;
  end;

resourcestring
  rsDocumentChangeOpen = 'A change is already open';
  rsDocumentNoChange = 'No change is open';
  rsDocumentBadSnapshot = 'Could not restore the pattern: %s';
  rsDocumentNoMeasurements = 'There is no measurement file';

implementation

uses
  Sloper.Core.JSON, Sloper.Core.PatternFile;

  { TCommand }

constructor TCommand.Create(const ADescription: string);
begin
  FDescription := ADescription;
end;

{ TPatternChange }

constructor TPatternChange.Create(ADocument: TPatternDocument; const ADescription, ABefore, AAfter, AMergeKey: string;
  ATime: TDateTime);
begin
  inherited Create(ADescription);
  FDocument := ADocument;
  FBefore := ABefore;
  FAfter := AAfter;
  FMergeKey := AMergeKey;
  FTime := ATime;
end;

procedure TPatternChange.Execute;
begin
  FDocument.ApplySnapshot(FAfter);
end;

procedure TPatternChange.Undo;
begin
  FDocument.ApplySnapshot(FBefore);
end;

{ TPatternDocument }

constructor TPatternDocument.Create;
begin
  FPattern := TPattern.Create;
  FUndo := TCommandList.Create;
  FRedo := TCommandList.Create;
  FUndoLimit := DefaultUndoLimit;
  FMergeSeconds := DefaultMergeSeconds;
end;

destructor TPatternDocument.Destroy;
begin
  ClearHistory;
  FreeAndNil(FUndo);
  FreeAndNil(FRedo);
  // The pattern reads the measurement set, so it goes first
  FreeAndNil(FPattern);
  FreeAndNil(FMeasurements);
  inherited Destroy;
end;

function TPatternDocument.CurrentTime: TDateTime;
begin
  if Assigned(FClock) then
    Result := FClock()
  else
    Result := Now;
end;

procedure TPatternDocument.Notify(Changes: TDocumentChanges);
var
  Listeners: array of TDocumentListener;
  Listener: TDocumentListener;
begin
  // A copy, so a listener can remove itself
  Listeners := Copy(FListeners, 0, Length(FListeners));
  for Listener in Listeners do
    Listener(Self, Changes);
end;

procedure TPatternDocument.AddListener(Listener: TDocumentListener);
begin
  SetLength(FListeners, Length(FListeners) + 1);
  FListeners[High(FListeners)] := Listener;
end;

procedure TPatternDocument.RemoveListener(Listener: TDocumentListener);
var
  Index: integer;
begin
  for Index := 0 to High(FListeners) do
    if (TMethod(FListeners[Index]).Code = TMethod(Listener).Code) and
      (TMethod(FListeners[Index]).Data = TMethod(Listener).Data) then
    begin
      Delete(FListeners, Index, 1);
      Exit;
    end;
end;

function TPatternDocument.GetModified: boolean;
begin
  Result := (FUndo.Count <> FSavedCount) or FMeasurementsChanged;
end;

function TPatternDocument.GetCanUndo: boolean;
begin
  Result := not FChangeOpen and (FUndo.Count > 0);
end;

function TPatternDocument.GetCanRedo: boolean;
begin
  Result := not FChangeOpen and (FRedo.Count > 0);
end;

function TPatternDocument.GetUndoDescription: string;
begin
  if FUndo.Count = 0 then
    Result := ''
  else
    Result := FUndo.Last.Description;
end;

function TPatternDocument.GetRedoDescription: string;
begin
  if FRedo.Count = 0 then
    Result := ''
  else
    Result := FRedo.Last.Description;
end;

procedure TPatternDocument.ClearHistory;
begin
  FUndo.Clear;
  FRedo.Clear;
  FSavedCount := 0;
end;

procedure TPatternDocument.ClearRedo;
begin
  FRedo.Clear;
  // The saved state was on the discarded redo branch
  if FSavedCount > FUndo.Count then
    FSavedCount := -1;
end;

procedure TPatternDocument.TrimUndo;
begin
  while (FUndoLimit > 0) and (FUndo.Count > FUndoLimit) do
  begin
    FUndo.Delete(0);
    // FSavedCount counts steps; a save before the dropped step can no longer be reached
    if FSavedCount > 0 then
      Dec(FSavedCount)
    else
      FSavedCount := -1;
  end;
end;

procedure TPatternDocument.RequireNoChange;
begin
  if FChangeOpen then
    raise EDocumentError.Create(rsDocumentChangeOpen);
end;

// The measurement path as the pattern stores it: relative to the pattern's
// folder with "/" separators, or absolute while the pattern has no file
function TPatternDocument.MeasurementFileFor(const PatternFileName: string): string;
begin
  if FMeasurementPath = '' then
    Exit('');
  if PatternFileName = '' then
    Result := FMeasurementPath
  else
    Result := ExtractRelativePath(IncludeTrailingPathDelimiter(ExtractFileDir(PatternFileName)), FMeasurementPath);
  if PathDelim <> '/' then
    Result := StringReplace(Result, PathDelim, '/', [rfReplaceAll]);
end;

// Loads a recorded state. The measurement set is the document's choice, not
// part of the history, so the restored pattern keeps the current one. The ID
// counter stays where it is, so an undone object's ID is never handed out again.
procedure TPatternDocument.ApplySnapshot(const Text: string);
var
  Err: string;
  NextId: integer;
begin
  NextId := FPattern.NextId;
  if not LoadPatternFromText(FPattern, Text, Err) then
    raise EDocumentError.CreateFmt(rsDocumentBadSnapshot, [Err]);
  if NextId > FPattern.NextId then
    FPattern.NextId := NextId;
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  FPattern.Evaluate;
end;

procedure TPatternDocument.SetMeasurementSet(ASet: TMeasurementSet; const APath: string);
begin
  FPattern.Measurements := ASet;
  FreeAndNil(FMeasurements);
  FMeasurements := ASet;
  FMeasurementPath := APath;
end;

procedure TPatternDocument.NewPattern;
begin
  RequireNoChange;
  FPattern.Clear;
  ClearHistory;
  FFileName := '';
  FMeasurementsChanged := False;
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  FPattern.Evaluate;
  Notify([dcPattern, dcObjectsReplaced, dcHistory, dcFile]);
end;

function TPatternDocument.LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Loaded: TPattern;
  FullName, SetPath, SetError: string;
  NewSet: TMeasurementSet;
begin
  RequireNoChange;
  NewSet := nil;
  Loaded := TPattern.Create;
  try
    if not LoadPatternFromFile(Loaded, FileName, ErrorMessage) then
      Exit(False);
    FullName := ExpandFileName(FileName);
    SetPath := MeasurementFilePath(Loaded, FullName);
    SetError := '';
    if SetPath <> '' then
    begin
      SetPath := ExpandFileName(SetPath);
      NewSet := TMeasurementSet.Create;
      if not NewSet.LoadFromFile(SetPath, SetError) then
        FreeAndNil(NewSet);
    end;

    FreeAndNil(FPattern);
    FPattern := Loaded;
    Loaded := nil;
    SetMeasurementSet(NewSet, SetPath);
    NewSet := nil;
  finally
    FreeAndNil(NewSet);
    FreeAndNil(Loaded);
  end;
  FMeasurementError := SetError;
  ClearHistory;
  FFileName := FullName;
  FMeasurementsChanged := False;
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  FPattern.Evaluate;
  Notify([dcPattern, dcObjectsReplaced, dcMeasurements, dcHistory, dcFile]);
  Result := True;
end;

function TPatternDocument.SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
var
  FullName: string;
begin
  RequireNoChange;
  FullName := ExpandFileName(FileName);
  // The measurement file is stored relative to where the pattern now goes
  FPattern.MeasurementFile := MeasurementFileFor(FullName);
  if not WriteTextFile(FullName, SavePatternToText(FPattern), ErrorMessage) then
  begin
    FPattern.MeasurementFile := MeasurementFileFor(FFileName);
    Exit(False);
  end;
  FFileName := FullName;
  FSavedCount := FUndo.Count;
  FMeasurementsChanged := False;
  Notify([dcFile]);
  Result := True;
end;

function TPatternDocument.ChangeMeasurement(const Key: string; Value: double; const Description: string;
  out Change: TMeasurementChange; out ErrorMessage: string): boolean;
var
  NewSet: TMeasurementSet;
begin
  RequireNoChange;
  Change := Default(TMeasurementChange);
  ErrorMessage := '';
  if FMeasurementPath = '' then
  begin
    ErrorMessage := rsDocumentNoMeasurements;
    Exit(False);
  end;
  if not ChangeMeasurementInFile(FMeasurementPath, Key, Value, Description, Change, ErrorMessage) then
    Exit(False);
  NewSet := TMeasurementSet.Create;
  try
    if not NewSet.LoadFromFile(FMeasurementPath, ErrorMessage) then
      Exit(False);
    SetMeasurementSet(NewSet, FMeasurementPath);
    NewSet := nil;
  finally
    FreeAndNil(NewSet);
  end;
  FMeasurementError := '';
  FPattern.Evaluate;
  Notify([dcPattern, dcMeasurements]);
  Result := True;
end;

function TPatternDocument.UseMeasurements(const FileName: string; out ErrorMessage: string): boolean;
var
  NewSet: TMeasurementSet;
  NewPath, OldStored: string;
  WasModified: boolean;
  Changes: TDocumentChanges;
begin
  RequireNoChange;
  ErrorMessage := '';
  NewSet := nil;
  NewPath := '';
  WasModified := Modified;
  OldStored := FPattern.MeasurementFile;
  try
    if FileName <> '' then
    begin
      NewPath := ExpandFileName(FileName);
      NewSet := TMeasurementSet.Create;
      if not NewSet.LoadFromFile(NewPath, ErrorMessage) then
        Exit(False);
    end;
    SetMeasurementSet(NewSet, NewPath);
    NewSet := nil;
  finally
    FreeAndNil(NewSet);
  end;
  FMeasurementError := '';
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  if FPattern.MeasurementFile <> OldStored then
    FMeasurementsChanged := True;
  FPattern.Evaluate;
  Changes := [dcPattern, dcMeasurements];
  if Modified <> WasModified then
    Include(Changes, dcFile);
  Notify(Changes);
  Result := True;
end;

procedure TPatternDocument.BeginChange(const Description: string);
begin
  RequireNoChange;
  FChangeBefore := SavePatternToText(FPattern, False);
  FChangeDescription := Description;
  FChangeOpen := True;
end;

function TPatternDocument.EndChange(const MergeKey: string): boolean;
var
  After: string;
  Last: TPatternChange;
  Time: TDateTime;
  WasModified: boolean;
  Changes: TDocumentChanges;
begin
  if not FChangeOpen then
    raise EDocumentError.Create(rsDocumentNoChange);
  FChangeOpen := False;
  FPattern.Evaluate;
  After := SavePatternToText(FPattern, False);
  if After = FChangeBefore then
  begin
    Notify([dcPattern]);
    Exit(False);
  end;

  WasModified := Modified;
  ClearRedo;
  Time := CurrentTime;
  Last := nil;
  if FUndo.Count > 0 then
    Last := TPatternChange(FUndo.Last);
  // Never merge into the step the file was saved after: that state must stay reachable
  if (MergeKey <> '') and (Last <> nil) and (Last.FMergeKey = MergeKey) and (FSavedCount <> FUndo.Count) and
    ((Time - Last.FTime) * SecsPerDay <= FMergeSeconds) then
  begin
    Last.FAfter := After;
    Last.FTime := Time;
    if Last.FAfter = Last.FBefore then
      FUndo.Delete(FUndo.Count - 1);
  end
  else
  begin
    FUndo.Add(TPatternChange.Create(Self, FChangeDescription, FChangeBefore, After, MergeKey, Time));
    TrimUndo;
  end;

  Changes := [dcPattern, dcHistory];
  if Modified <> WasModified then
    Include(Changes, dcFile);
  Notify(Changes);
  Result := True;
end;

procedure TPatternDocument.CancelChange;
begin
  if not FChangeOpen then
    raise EDocumentError.Create(rsDocumentNoChange);
  FChangeOpen := False;
  if SavePatternToText(FPattern, False) <> FChangeBefore then
  begin
    ApplySnapshot(FChangeBefore);
    Notify([dcPattern, dcObjectsReplaced]);
  end;
end;

function TPatternDocument.Commit(Success: boolean; const MergeKey: string): boolean;
begin
  if Success then
    Result := EndChange(MergeKey)
  else
  begin
    CancelChange;
    Result := False;
  end;
end;

procedure TPatternDocument.LiveUpdate;
begin
  FPattern.Evaluate;
  Notify([dcPattern]);
end;

function TPatternDocument.Undo: boolean;
var
  Command: TCommand;
  WasModified: boolean;
  Changes: TDocumentChanges;
begin
  if not CanUndo then
    Exit(False);
  WasModified := Modified;
  Command := FUndo.ExtractIndex(FUndo.Count - 1);
  Command.Undo;
  FRedo.Add(Command);
  Changes := [dcPattern, dcObjectsReplaced, dcHistory];
  if Modified <> WasModified then
    Include(Changes, dcFile);
  Notify(Changes);
  Result := True;
end;

function TPatternDocument.Redo: boolean;
var
  Command: TCommand;
  WasModified: boolean;
  Changes: TDocumentChanges;
begin
  if not CanRedo then
    Exit(False);
  WasModified := Modified;
  Command := FRedo.ExtractIndex(FRedo.Count - 1);
  Command.Execute;
  FUndo.Add(Command);
  Changes := [dcPattern, dcObjectsReplaced, dcHistory];
  if Modified <> WasModified then
    Include(Changes, dcFile);
  Notify(Changes);
  Result := True;
end;

end.
