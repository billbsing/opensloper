# src/document

`TPatternDocument` (`sloper.document.patterndocument.pas`): owns the pattern and its measurement set, opens and saves files, keeps the undo and redo history, and notifies listeners of changes. Depends on `src/core` only. See Key design decisions item 7 in the design document for how changes and undo work.

`TMeasurementDocument` (`sloper.document.measurementdocument.pas`): the measurement file open in the measurements app, with its own undo history, atomic saving, and watching and merging by key. See Measurements app in the design document.
