# Items to do

Review and testing before moving on to step 10, from `ffed2e4` on `development`. Run `./build.sh` first, which builds all three programs, including `publish/opensloper-publish`.

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

Decided 2026-11-03 (see Annotations in the design document; not started):
- The user chooses the font name (installed fonts) and size (points) for each annotation.
- The PDF embeds the chosen TrueType font so prints match the screen; OpenType/CFF or a missing font falls back to Helvetica with a warning.
- First version is everything in the design: notes, callouts, live fields, bold/italic, alignment, box/background, leader ends, print-or-screen, show/hide.

#### Preferences
New prefrences dialog to record users preferences, accross measurement, design and publish, all apps use the same dialog form.
Tabs for specific opitons for the different apps. 
At the moment add the units the user wishes to use mm, cm or inch
For Design - set the background grid size in current units, save each size for the different units, instead of converting when units change.
For Publish - printer calibration (across and down), set once for the user's printer instead of in each layout; see Publish - printing question below.


Decided 2026-11-04 (see Pattern units in the design document; not started):
- Each pattern has one unit; every number in its formulas is in that unit, so `A + 400` is 400 in in an inch pattern and the `2` in `(A * 2) + 400` needs no label.
- The preference sets the unit for new patterns and the measurements app's display; it never changes an existing pattern.
- Tools → Convert Pattern Units… rewrites only numbers that are lengths, working out each number's role from where it sits, and lists undecided ones for the user.
- Numbers may carry a suffix (`400mm`, `2in`), which pins their meaning.

#### Measurement Panel Test size tool
On the measurement panel, have a 'test' slider, that the user can slide left or right. When slide left all of the measurements are decreased by 1%, up to 20%, and the opposite for right move +1% per step up to 20%. If the sizes change the design changes size if the measurements are being used, and the measurement fields are disabled. 
The fields are re-enabled only when the test slider is moved back to the center.

#### Design Canvas Ruler
Show a ruler Top and Left of the canvas in the current units, with the cursor as a line on the rulers. Similar to Inkscape. Show the units on the ruler, in a prominant color, if there is space.

Done 2026-11-05 (see Rulers in the design document): View → Rulers (Ctrl+R), unit named in the corner. Shows mm until Pattern units are done, then the pattern's unit.

#### Documents
Cleanup up the opensloper-design-document.md, after many iterations it is getting too long, summarize and reduce each section.

#### File Format Standards
For future claude creating new patterns and measurements, do we need to create storage file standards as part of the documents folder.
Each store file type has currently a version number, and the JSON specification, so that claude can read/write measurement, design and  publish files.

#### Publish - printing question
How to adjust the print size if the square block is not 10x10.

Answered 2026-11-05: the Output tab already has Calibration across and Calibration down, which scale everything drawn at true size, test square included. A square that measures 98.5 mm across needs 100 / 98.5 = 1.015.

To do, with Preferences:
- Move calibration to the Publish tab of Preferences (`settings.json`), since it belongs to the printer, not the pattern. This matches the design document's folder table, which already lists printer calibration under Config.
- Let the user type the measured size of the test square (across and down) and work out the factors, rather than entering them by hand.
- Decide what happens to the `calibrationX` / `calibrationY` already saved in layout files: read them as an override, or drop them on load.



