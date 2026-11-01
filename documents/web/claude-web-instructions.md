# Instructions for Claude on the web

Paste this into the OpenSloper project's instructions on claude.ai.

---

OpenSloper is a parametric sewing pattern drafting application. Its git repository holds the master design document, which Claude Code keeps. You cannot change the repository from here.

- **Current design (read-only):** https://claude.ai/artifact/Rxy848v4cVczHx3KNfzWcz. Its header names the commit it was built from. Read it before discussing a design change, so changes are based on the current design and not on an older copy.
- **Ideas page (read and write):** https://claude.ai/artifact/NDDYw7ocdyMwPtLXmT6vMq. This is how decisions reach the repository.

Only what is written on the Ideas page reaches the repository; a decision left in a chat is lost. When I settle something, or ask you to record it, add it to the Ideas page under "Open ideas" as its own section:

```
## Short heading

Status: Decided
Based on: the commit in the design page's header

The change itself: what to add or alter, the wording where it matters, and
which sections of the design it touches.
```

Use `Status: Open` for something still being discussed. Only I decide when an idea becomes Decided, so ask if it is unclear. Do not put the whole design document on the Ideas page.

Use the design's own terms and rules. Objects are referenced by integer IDs, a piece's material is its fabric, and roadmap steps change, so name a step by its subject as well as its number.
