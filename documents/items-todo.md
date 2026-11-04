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

#### Tool Merge Points
This is simalar to inkscape join nodes, the user selects 2 or more points, then clicks on the tool.
The new point name will take the lowest default name , or the first name that has been changed by the user.
So point names 'M, N, O' -> 'M'.
Point names 'M, MyNode, O' -> MyNode

Done 2026-11-04 (see Merging points in the design document; to test in the app):
- Tools → Merge Points and the toolbar button; `merge_points` in the Automation API.
- The kept point keeps one definition; users of the others move to it, and a line between two of them is deleted.

#### Tool Break Points
This is the opposite of tool merge, a single point is broken up into multiple points, depending on the number of connecting objects.
The new point names, are the same as a copy so point 'M' -> 'M1, M2'.

Done 2026-11-04 (see Breaking a point in the design document; to test in the app):
- Tools → Break Point and the toolbar button; `break_point` in the Automation API.
- The point keeps its ID and goes with the first edge; each other edge gets a new point at dx 0, dy 0 from it, to drag apart.

#### Anotations
Have the anotations appear at the highest Z-order , over the design. The user can view/hide anotations.
Add, Edit, Delete, Move anotations in the design page.
Set font, and font size for anotations.

Decided 2026-11-03 (see Annotations in the design document; not started):
- The user chooses the font name (installed fonts) and size (points) for each annotation.
- The PDF embeds the chosen TrueType font so prints match the screen; OpenType/CFF or a missing font falls back to Helvetica with a warning.
- First version is everything in the design: notes, callouts, live fields, bold/italic, alignment, box/background, leader ends, print-or-screen, show/hide.

#### New Circle and Rectangle creation
Now we can merge and break points...
Circle and Rectangle, drawing tools, do not need to select a point first. After creating a circle the point is automatically placed in the midle. The rectangle places 4 points automaticcaly.

#### Preferences
New prefrences dialog to record users preferences, accross measurement, design and publish, all apps use the same dialog form.
Tabs for specific opitons for the different apps. 
At the moment add the units the user wishes to use mm, cm or inch
For Design - set the background grid size in current units, save each size for the different units, instead of converting when units change.


Decided 2026-11-04 (see Pattern units in the design document; not started):
- Each pattern has one unit; every number in its formulas is in that unit, so `A + 400` is 400 in in an inch pattern and the `2` in `(A * 2) + 400` needs no label.
- The preference sets the unit for new patterns and the measurements app's display; it never changes an existing pattern.
- Tools → Convert Pattern Units… rewrites only numbers that are lengths, working out each number's role from where it sits, and lists undecided ones for the user.
- Numbers may carry a suffix (`400mm`, `2in`), which pins their meaning.

#### Claude MCP integration
Need to store the claude api code in the preferences form for claude to access the app.
Also need to work out how claude is going to communicate to the user for changes to the design, does claude need to find what design objects are selected from the API?

#### Measurement Panel Test size tool
On the measurement panel, have a 'test' slider, that the user can slide left or right. When slide left all of the measurements are decreased by 1%, up to 20%, and the opposite for right move +1% per step up to 20%. If the sizes change the design changes size if the measurements are being used, and the measurement fields are disabled. 
The fields are re-enabled only when the test slider is moved back to the center.

#### Design Canvas Ruler
Show a ruler Top and Left of the canvas in the current units, with the cursor as a line on the rulers. Similar to Inkscape. Show the units on the ruler, in a prominant color, if there is space.

#### Measurement App
Need to change to toolbar and icons.

#### Publish App
Need to add basic toolbar and icons.

#### Documents
Cleanup up the opensloper-design-document.md, after many iterations it is getting too long, summarize and reduce each section.

#### File Format Standards
For future claude creating new patterns and measurements, do we need to create storage file standards as part of the documents folder.
Each store file type has currently a version number, and the JSON specification, so that claude can read/write measurement, design and  publish files.

#### Build script
Can we determin if Qt6 is available, if so build with qt6, else build with Qt5.

#### Apps, Maintenance, Design & Publish
Add Menu item Open Recent -> list of last open files

## Future Road Map Changes

#### Locking an object
An object can be locked and the user can not do any operation with this except the formular can still be run, and the object can still set it's value based on the formular values.






