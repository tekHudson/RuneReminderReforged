# Rune Reminder Reforged

A lightweight, from-scratch addon for World of Warcraft Classic Season of
Discovery that tracks the runes you have engraved on each equipment slot,
lets you engrave a new one with a click, and gives you a quick chat heads-up
if a gear swap changes or clears a slot's rune.

## Features

- A small draggable row (or column) of buttons, one per engravable
  equipment slot, showing the rune currently engraved there and its
  cooldown.
- Click a slot to pick a different rune from what you currently know for
  that slot.
- A chat message when equipping different gear silently changes or clears a
  tracked slot's rune, so you don't forget to re-engrave it.

That's it. No saved rune-set loadouts, no popups, no Masque skinning, no
custom fonts/colors/textures — just a small live indicator and reminder.

## Usage

- `/rrr` — opens the options panel.
- `/rrr show` / `/rrr hide` — toggle the widget.
- Drag the widget by any slot button to reposition it (unless locked in
  options).

## Install

Copy the `RuneReminderReforged` folder into:

```
World of Warcraft/_classic_era_/Interface/AddOns/
```

Then `/reload` or restart the client and enable it on the AddOns list.

## Releases

Tagged commits are packaged automatically by
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) via GitHub
Actions and attached to the GitHub Release. To cut a release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Requires the `CURSEFORGE_API_TOKEN` repo secret to also publish to
CurseForge.
