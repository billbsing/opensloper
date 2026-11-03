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

#### Tool Break Points
This is the opposite of tool merge, a single point is broken up into multiple points, depending on the number of connecting objects.
The new point names, are the same as a copy so point 'M' -> 'M1, M2'.

#### Locking an object
An object can be locked and the user can do any operation with this except the formular can still be run, and the object can still move based on the formular values.

#### Anotations
Have the anotations appear at the highest Z-order , over the design. The user can view/hide anotations.
Add, Edit, Delete, Move anotations in the design page.
Set font, and font size for anotations.

#### New Circle and Rectangle creation
Now we can merge and break points...
Circle and Rectangle, drawing tools, do not need to select a point first. After creating a circle the point is automatically placed in the midle. The rectangle places 4 points automaticcaly.








