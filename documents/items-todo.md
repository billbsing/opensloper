# Items to do

Review and testing before moving on to step 10, from `ffed2e4` on `development`. Run `./build.sh` first, which builds all three programs, including `release/opensloper-publish`.

## To test

These could not be tested properly during development.

- [x] **Export PDF in the window:** never clicked through a file dialog; all test exports went through the CLI.
- [ ] **A real print:** measure the 10 cm test square with a ruler, then tape two tiles together using the diamonds.
- [x] **A real projector:** the line thicknesses are a best guess.
- [ ] **Publish… save prompt:** in the drafting app, try this with a modified pattern, and from a real save.
- [x] **Publish window:** Flip, Reload Patterns, panning, the Delete key and the every-page title block.

## Known limits

- A piece keeps the edges it was made from, so splitting an edge after making its piece does nothing for it: the piece has to be deleted and made again before a seam can use the parts.
- An edge's own seam allowance, and a grainline between two points, can only be set through the Automation API.
- Each Publish… opens another window, rather than finding one already open.

## List of Changes

#### Anotations
Have the anotations appear at the highest Z-order , over the design. The user can view/hide anotations.
Add, Edit, Delete, Move anotations in the design page.
Set font, and font size for anotations, change direction, anchored from a point.

Rescoped 2026-11-06 into four stages (see Stages under Annotations in the design document):
- Stage 1, anchored notes: done 2026-11-06. Plain text anchored to a point, edge or piece, Text tool (X), drag, show and hide (View → Annotations), document fields, printing with their piece; one sans-serif font.
- Stage 2: done 2026-11-06. Callouts (Callout tool, A; a note with a leader, its tip dragged to re-anchor it), `{=…}` draft values, alignment and the white box for notes and sheet notes.
- Stage 3: font name, bold and italic, with the chosen TrueType font embedded in PDF.
- Stage 4: SVG stamps, anchored path-only drawings.

#### Preferences
Done 2026-11-05 (see Preferences in the design document): one dialog in all three apps, Edit → Preferences…, with General (unit), Design (grid spacing per unit) and Publish (printer calibration, worked out from a measured test square). Calibration moved out of layout files; older layouts' values are ignored.

Still to do:
- New patterns take the preferred unit, once Pattern units is built (decided 2026-11-04, not started): each pattern has one unit, the preference sets it for new patterns and never changes an existing one, Tools → Convert Pattern Units… rewrites only lengths, and numbers may carry a suffix (`400mm`, `2in`; the suffix is built, converting to mm for now). Split 2026-11-06 into two stages (see Stages under Pattern units in the design document): stage 1, the pattern's unit (built 2026-11-07); stage 2, converting a pattern (not started).
- An app already open picks up a preference changed in another app only when restarted.

#### Marking line roles
Done 2026-11-05 (see Markings in the design document): edges can be placement, stitch, fold or cut lines, which join the pieces they lie in and print in their own style. Finished 2026-11-06: point markers (hole, button, match dot) on points and repeats, Draw As for the role of new lines, several lines in the same place (click again or Alt-click to cycle, right-click list, screen offset), and the offset edge along a run (inside/outside a piece, mitred and trimmed corners, invalid when it collapses). Still to try by hand: Alt-click on a real desktop, as some window managers take it for moving windows. Also done 2026-11-06: the skive line and edge finish roles, the Lines tab for hiding roles with presets, and output profiles in the publish app; still to do: overriding role styles in Preferences, and a print with the Leather profile tried by hand.

#### File Format Standards
For future claude creating new patterns and measurements, do we need to create storage file standards as part of the documents folder.
Each store file type has currently a version number, and the JSON specification, so that claude can read/write measurement, design and  publish files.

#### Publish - printing question
How to adjust the print size if the square block is not 10x10.

Answered 2026-11-05: set the calibration in Preferences → Publish. Type the measured size of the test square and Work Out Factors sets them; a square that measures 98.5 mm across, printed with no correction, needs 100 / 98.5 = 1.015.
