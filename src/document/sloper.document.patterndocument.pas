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
//   Document.Commit(Assigned(Document.Pattern.AddFreePoint('', X, Y)));

// A change records the pattern's saved text before and after, so undo and
// redo restore exactly the earlier definitions. Undo, redo and cancel load
// that text again, which replaces the pattern's objects with new ones (the
// IDs stay the same): hold objects by ID, not by reference, across changes.
// No LCL dependency.
unit Sloper.Document.PatternDocument;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.Units;

type
  EDocumentError = class(Exception);

  TPatternDocument = class;

  // dcPattern: definitions or results changed. dcObjectsReplaced: the
  // pattern's objects are new instances (undo, redo, cancel, load).
  // dcMeasurements: another measurement set. dcHistory: what can be undone
  // or redone. dcFile: file name or modified flag. dcView: view state, such as
  // the zoom, outside undo.
  TDocumentChange = (dcPattern, dcObjectsReplaced, dcMeasurements, dcHistory, dcFile, dcView);
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

  // A locked object's definition when a change began
  TLockedDefinition = record
    Key: string;
    // As shown, for naming it after it is gone
    Name: string;
    Text: string;
  end;

  TPatternDocument = class
  private
    FPattern: TPattern;
    FMeasurements: TMeasurementSet;
    FMeasurementPath: string;
    FMeasurementError: string;
    // The set's file as it was read, and its text seen changing since
    FMeasurementText, FPendingMeasurementText: string;
    FMeasurementsChanged: boolean;
    FFileName: string;
    FUndo, FRedo: TCommandList;
    FSavedCount: integer;
    FChangeOpen: boolean;
    FChangeDescription: string;
    FChangeBefore: string;
    FCheckLocks: boolean;
    FLockedBefore: array of TLockedDefinition;
    FChangeRefused: boolean;
    FGeneration: integer;
    FListeners: array of TDocumentListener;
    FClock: TDocumentClock;
    FUndoLimit: integer;
    FMergeSeconds: double;
    function GetModified: boolean;
    function GetMeasurementScale: double;
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
    procedure RecordLocked;
    function ChangedLocked: string;
  public
    constructor Create;
    destructor Destroy; override;

    // An empty pattern in AUnits, with no history and no file name. The
    // measurement set is kept.
    procedure NewPattern(AUnits: TMeasureUnit = muMillimetre);
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
    // Several such edits, with one write of the file; on failure none is made
    function ChangeMeasurements(const Edits: TMeasurementEditArray; out Changes: TMeasurementChangeArray;
      out ErrorMessage: string): boolean;
    // Whether the measurement file now differs from the set as it was read
    function MeasurementFileChanged: boolean;
    // Uses this size of a size table and re-evaluates; False when it is not in
    // the set. Not an undo step, and not saved: a set starts on its first size.
    function SelectMeasurementSize(const Size: string): boolean;
    // Multiplies every measurement the pattern reads by Factor, to try it a
    // size up or down, and re-evaluates. Not an undo step, not a modification
    // and not saved; New and Open go back to 1. False for a Factor not above 0.
    function SetMeasurementScale(Factor: double): boolean;
    // Call regularly: reads the set again and re-evaluates once a change made
    // elsewhere has stopped changing, keeping the size. True when it did.
    function CheckMeasurementFile: boolean;

    // A change: BeginChange, any number of edits to Pattern (with LiveUpdate
    // to show them, e.g. while dragging), then EndChange to record them as
    // one undo step, or CancelChange to put the pattern back. Changes do not
    // nest; beginning one while another is open raises EDocumentError.
    // An object locked when the change begins must come out of it as it
    // was, apart from being unlocked; CheckLocks False lets a change to the
    // whole pattern, such as converting its unit, rewrite locked objects too.
    procedure BeginChange(const Description: string; CheckLocks: boolean = True);
    // Records the change. One that changed a locked object is undone
    // instead, with Pattern.LastError naming the object and ChangeRefused
    // set. A change with the same non-empty MergeKey as the
    // last step, within MergeSeconds, joins that step (arrow-key nudges,
    // spin box steps); if they cancel out, the step goes. False when nothing
    // changed.
    function EndChange(const MergeKey: string = ''): boolean;
    procedure CancelChange;
    // Gives the open change another description, for a change begun before
    // its caller knew what it would be
    procedure RenameChange(const Description: string);
    // EndChange when Success, else CancelChange; for wrapping one edit:
    // Commit(Pattern.Rename(...))
    function Commit(Success: boolean; const MergeKey: string = ''): boolean;
    // Re-evaluates and notifies, without recording anything
    procedure LiveUpdate;
    // View state changed: part of no undo step and not a modification
    procedure ViewChanged;

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
    property MeasurementScale: double read GetMeasurementScale;
    // Full path, or '' for a pattern not saved yet
    property FileName: string read FFileName;
    property Modified: boolean read GetModified;
    property ChangeOpen: boolean read FChangeOpen;
    // Counts the patterns the document has held: New and Open add one, so a
    // client that learned IDs and names can tell they belong to another
    property Generation: integer read FGeneration;
    // The last change ended was undone because it changed a locked object
    property ChangeRefused: boolean read FChangeRefused;
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
  Sloper.Core.JSON, Sloper.Core.PatternFile, Sloper.Core.Draft, Sloper.Core.Evaluator;

const
  DEFAULT_UNDO_LIMIT = 500;
  // Changes with the same merge key this close together become one step
  DEFAULT_MERGE_SECONDS = 1.0;

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
  FPattern.Identity := NewPatternIdentity;
  FUndo := TCommandList.Create;
  FRedo := TCommandList.Create;
  FUndoLimit := DEFAULT_UNDO_LIMIT;
  FMergeSeconds := DEFAULT_MERGE_SECONDS;
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
  Err, ViewText: string;
  NextId: integer;
begin
  NextId := FPattern.NextId;
  ViewText := PatternViewToText(FPattern);
  if not LoadPatternFromText(FPattern, Text, Err) then
    raise EDocumentError.CreateFmt(rsDocumentBadSnapshot, [Err]);
  if NextId > FPattern.NextId then
    FPattern.NextId := NextId;
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  // The view is not part of the history, so it stays as it was
  RestorePatternView(FPattern, ViewText);
  FPattern.Evaluate;
end;

procedure TPatternDocument.SetMeasurementSet(ASet: TMeasurementSet; const APath: string);
var
  Reason: string;
begin
  FPattern.Measurements := ASet;
  FreeAndNil(FMeasurements);
  FMeasurements := ASet;
  FMeasurementPath := APath;
  FPendingMeasurementText := '';
  if (APath = '') or not ReadTextFile(APath, FMeasurementText, Reason) then
    FMeasurementText := '';
end;

procedure TPatternDocument.NewPattern(AUnits: TMeasureUnit);
begin
  RequireNoChange;
  FPattern.Clear;
  FPattern.Identity := NewPatternIdentity;
  FPattern.Units := AUnits;
  FPattern.MeasurementScale := 1;
  ClearHistory;
  FFileName := '';
  FMeasurementsChanged := False;
  FPattern.MeasurementFile := MeasurementFileFor(FFileName);
  FPattern.Evaluate;
  Inc(FGeneration);
  Notify([dcPattern, dcObjectsReplaced, dcMeasurements, dcHistory, dcFile]);
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
    // Files from before identities get one, saved with the next save
    if Loaded.Identity = '' then
      Loaded.Identity := NewPatternIdentity;
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
  Inc(FGeneration);
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
  Edits: TMeasurementEditArray;
  Changes: TMeasurementChangeArray;
begin
  Change := Default(TMeasurementChange);
  Edits := nil;
  SetLength(Edits, 1);
  Edits[0].Key := Key;
  Edits[0].Value := Value;
  Edits[0].Description := Description;
  Result := ChangeMeasurements(Edits, Changes, ErrorMessage);
  if Result then
    Change := Changes[0];
end;

function TPatternDocument.ChangeMeasurements(const Edits: TMeasurementEditArray; out Changes: TMeasurementChangeArray;
  out ErrorMessage: string): boolean;
var
  NewSet: TMeasurementSet;
  Size: string;
begin
  RequireNoChange;
  Changes := nil;
  ErrorMessage := '';
  if FMeasurementPath = '' then
  begin
    ErrorMessage := rsDocumentNoMeasurements;
    Exit(False);
  end;
  Size := '';
  if Assigned(FMeasurements) then
    Size := FMeasurements.SizeName;
  if not ChangeMeasurementsInFile(FMeasurementPath, Edits, Changes, ErrorMessage, Size) then
    Exit(False);
  NewSet := TMeasurementSet.Create;
  try
    if not NewSet.LoadFromFile(FMeasurementPath, ErrorMessage) then
      Exit(False);
    NewSet.SelectSize(Size);
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

function TPatternDocument.MeasurementFileChanged: boolean;
var
  Text, Reason: string;
begin
  Result := (FMeasurementPath <> '') and ReadTextFile(FMeasurementPath, Text, Reason) and (Text <> FMeasurementText);
end;

function TPatternDocument.GetMeasurementScale: double;
begin
  Result := FPattern.MeasurementScale;
end;

function TPatternDocument.SetMeasurementScale(Factor: double): boolean;
begin
  RequireNoChange;
  if Factor <= 0 then
    Exit(False);
  Result := True;
  // Only an actual change re-evaluates, so this is not a tolerance compare
  if Factor = FPattern.MeasurementScale then
    Exit;
  FPattern.MeasurementScale := Factor;
  FPattern.Evaluate;
  Notify([dcPattern, dcMeasurements]);
end;

function TPatternDocument.SelectMeasurementSize(const Size: string): boolean;
begin
  RequireNoChange;
  Result := Assigned(FMeasurements) and FMeasurements.SelectSize(Size);
  if not Result then
    Exit;
  FPattern.Evaluate;
  Notify([dcPattern, dcMeasurements]);
end;

function TPatternDocument.CheckMeasurementFile: boolean;
var
  Text, Reason, Size: string;
  NewSet: TMeasurementSet;
begin
  Result := False;
  if FChangeOpen or (FMeasurementPath = '') or not ReadTextFile(FMeasurementPath, Text, Reason) or (Text = FMeasurementText) then
  begin
    FPendingMeasurementText := '';
    Exit;
  end;
  if Text <> FPendingMeasurementText then
  begin
    FPendingMeasurementText := Text;
    Exit;
  end;
  FPendingMeasurementText := '';
  NewSet := TMeasurementSet.Create;
  try
    // A broken file is left for whoever is writing it to put right
    if not NewSet.LoadFromText(Text, Reason) then
      Exit;
    Size := '';
    if Assigned(FMeasurements) then
      Size := FMeasurements.SizeName;
    NewSet.SelectSize(Size);
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

procedure TPatternDocument.BeginChange(const Description: string; CheckLocks: boolean);
begin
  RequireNoChange;
  FChangeBefore := SavePatternToText(FPattern, False);
  FChangeDescription := Description;
  FCheckLocks := CheckLocks;
  FChangeRefused := False;
  RecordLocked;
  FChangeOpen := True;
end;

procedure TPatternDocument.RecordLocked;
var
  Index, Count: integer;
begin
  FLockedBefore := nil;
  if not FCheckLocks then
    Exit;
  Count := 0;
  for Index := 0 to FPattern.ObjectCount - 1 do
    if FPattern.Objects[Index].Locked then
    begin
      SetLength(FLockedBefore, Count + 1);
      FLockedBefore[Count].Key := FPattern.Objects[Index].Key;
      FLockedBefore[Count].Name := FPattern.Objects[Index].DisplayName;
      FLockedBefore[Count].Text := LockedObjectText(FPattern.Objects[Index]);
      Inc(Count);
    end;
end;

// The name of an object locked when the change began that is now changed or
// gone, or '' when there is none
function TPatternDocument.ChangedLocked: string;
var
  Before: TLockedDefinition;
  Node: TEvalNode;
begin
  for Before in FLockedBefore do
  begin
    Node := FPattern.FindNode(Before.Key);
    if not (Node is TDraftObject) or (LockedObjectText(TDraftObject(Node)) <> Before.Text) then
      Exit(Before.Name);
  end;
  Result := '';
end;

function TPatternDocument.EndChange(const MergeKey: string): boolean;
var
  After, LockedName: string;
  Last: TPatternChange;
  Time: TDateTime;
  WasModified: boolean;
  Changes: TDocumentChanges;
begin
  if not FChangeOpen then
    raise EDocumentError.Create(rsDocumentNoChange);
  FChangeOpen := False;
  FChangeRefused := False;
  FPattern.Evaluate;
  LockedName := ChangedLocked;
  FLockedBefore := nil;
  if LockedName <> '' then
  begin
    ApplySnapshot(FChangeBefore);
    FChangeRefused := True;
    FPattern.Refuse(Format(rsPatternLocked, [LockedName]));
    Notify([dcPattern, dcObjectsReplaced]);
    Exit(False);
  end;
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
  if (MergeKey <> '') and Assigned(Last) and (Last.FMergeKey = MergeKey) and (FSavedCount <> FUndo.Count) and
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
  FLockedBefore := nil;
  if SavePatternToText(FPattern, False) <> FChangeBefore then
  begin
    ApplySnapshot(FChangeBefore);
    Notify([dcPattern, dcObjectsReplaced]);
  end;
end;

procedure TPatternDocument.RenameChange(const Description: string);
begin
  if not FChangeOpen then
    raise EDocumentError.Create(rsDocumentNoChange);
  FChangeDescription := Description;
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

procedure TPatternDocument.ViewChanged;
begin
  Notify([dcView]);
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
