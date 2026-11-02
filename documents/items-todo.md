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

## Changes List

Fix UI splitter to go between the canvas and side panel.
Allow mouse click on an empty document and drag a dotted box over items, to select a group of items. This can be used below for merging points
Allow to delete items without maintaining connections, so leave points and other items dangling.
Allow user to 'merge' points to to a single point. This solves when we create a new line, that does not connect to another point.
Allow user to break a line and add points on the break.
When drawing line, curve, press the shift button to keep the line straight ( as in inkscape).
Allow user when drag on a selected line, converts to curve (as in inkscape).
Allow user to convert a curve -> line , and line->curve, using tool buttons.
Lock an edge, and point to stop changes being made, such as the type see above line <--> curve, cursor moving, deletion.
Layers and Drafts seem to be mixed up with similar functioanlity.
Remove layers, as this does not seem to work, but keep drafts.
Maybe change side bar display for Drafts instead of layers.
Allow user to delete draft tab.
Allow user to rename a draft tab.
Do we need to assign front/back before using the garment viewer.
Place the garment viewer into the side tab, not a sepearte window.
Add, Edit, Delete, Move anotations in the design page.
Set font, and font size for anotations.
When doing SVG export on the design page - change to show the labels that are shown on the screen by the user, if contextual - then use only contextual labels, if all then show all else None. 
Add icons for all menu operations.
Move menu commands to TActionList.
Create icon toolbars for tools and actions
Circle and Rectangle, drawing tools, do not need to select a point first. After creating a circle the point is automatically placed in the midle. The rectangle places 4 points automaticcaly.
Add the Circle, Rectangle, to the Select, Point, Line, Curve







