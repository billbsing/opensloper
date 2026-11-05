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
Done 2026-11-05 (see Preferences in the design document): one dialog in all three apps, Edit → Preferences…, with General (unit), Design (grid spacing per unit) and Publish (printer calibration, worked out from a measured test square). Calibration moved out of layout files; older layouts' values are ignored.

Still to do:
- New patterns take the preferred unit, once Pattern units is built (decided 2026-11-04, not started): each pattern has one unit, the preference sets it for new patterns and never changes an existing one, Tools → Convert Pattern Units… rewrites only lengths, and numbers may carry a suffix (`400mm`, `2in`; the suffix is built, converting to mm for now).
- An app already open picks up a preference changed in another app only when restarted.

#### Marking line roles
Done 2026-11-05 (see Markings in the design document): edges can be placement, stitch, fold or cut lines, which join the pieces they lie in and print in their own style. Still to do: point markers (drill hole, button, match dot), choosing a role before drawing, several lines in the same place (picking and the screen offset), and the longer offset edge (runs of edges, inside/outside, mitred corners).

#### Documents
Cleanup up the opensloper-design-document.md, after many iterations it is getting too long, summarize and reduce each section.

#### File Format Standards
For future claude creating new patterns and measurements, do we need to create storage file standards as part of the documents folder.
Each store file type has currently a version number, and the JSON specification, so that claude can read/write measurement, design and  publish files.

#### Publish - printing question
How to adjust the print size if the square block is not 10x10.

Answered 2026-11-05: set the calibration in Preferences → Publish. Type the measured size of the test square and Work Out Factors sets them; a square that measures 98.5 mm across, printed with no correction, needs 100 / 98.5 = 1.015.
