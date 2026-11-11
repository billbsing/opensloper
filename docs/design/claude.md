# Asking Claude

The **Claude** tab in the side panel lets you ask Claude, Anthropic's AI model,
to work on the pattern you have open, in your own words:

- "Add 2 cm ease at the hip."
- "Why is point C invalid?"
- "Move the shoulder dart to the side seam."
- "Make the selected curve meet the waist at a right angle."

Claude reads the pattern, makes the changes with the same operations you use,
and says what it changed. Each change appears on the canvas at once and is one
step on the undo history, labelled *Claude*, such as **Edit → Undo Claude: Add
variable**, so you can look at what it did and undo any of it.

## Setting it up

Claude needs an Anthropic API key, which you get from the
[Claude Console](https://platform.claude.com). Requests are billed to that key's
account.

1. Choose **Edit → Preferences**, open the **Design** tab and paste the key
   into **Anthropic API key**. It is kept in a file of its own that only you
   can read, not in the settings file. If the `ANTHROPIC_API_KEY` environment
   variable is set, that key is used instead.
2. Open the **Claude** tab, type your question and press ++enter++
   (++shift+enter++ starts a new line), or click **Ask**.

## Working with it

- Claude can see what you have selected and which part of the draft is in
  view, so "this point" and "the curve I selected" work. It can also look at
  the draft as a picture to check the shape of what it made.
- **Stop** ends the answer in progress; changes already made stay, each one
  undoable.
- **New Conversation** starts afresh. Claude remembers the conversation until
  then, so you can say "now do the same on the back".
- Claude does not open other patterns, and saves only when you ask. It asks
  before writing a file outside the pattern's folder. While you are dragging,
  it waits.

## What is sent

Your questions, and the parts of the pattern Claude reads to answer them
(names, formulas, values, notes and, when it looks, a picture of the draft),
are sent to Anthropic. Text in a pattern someone else made is treated as data,
not as instructions to Claude.

To have Claude work on the pattern from Claude Code or Claude Desktop instead,
see [Claude in the design window](../scripting/index.md#claude-in-the-design-window).
