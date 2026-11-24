# Better Cooldown Manager

**The Cooldown Manager you already use, with the options it's missing.** Better Cooldown Manager adds a few choices to the right-click menu in Cooldown Settings, so your tracked buffs can remind you to rebuff and your cooldowns only show when they're ready.

Built for **WoW Forever**.

---

## Features

### Buff reminders
Right-click a buff in **Tracked Buffs** or **Tracked Bars** and choose **Reminder**:

- **Only when it has expired**: the icon stays hidden while the buff is up, and appears the moment it falls off
- **...and also show it early**: pick 5 sec, 10 sec, 15 sec, 30 sec, 1, 2, 5 or 10 min, or type a custom time (like `25m` or `1:30`)
- Optional **glow** while the reminder is showing

Expired reminders appear **greyed out in their normal slot** in Blizzard's own row. There are no extra frames to place.

### About to Expire alerts
Blizzard's alerts can fire when a buff is applied or removed. Better Cooldown Manager adds **About to Expire** to the **When** dropdown in the New Alert dialog. Pick 5 sec up to 10 min (or a custom time) and your sound, visual or text-to-speech alert plays when the buff gets that low. They appear in the right-click menu alongside Blizzard's alerts, with the same play, edit and delete buttons.

### Group buff reminders
Right-click a buff in the **Group Buffs** tab (buffs other players give you, like Fortitude or Arcane Intellect) and choose **Reminder**. When it's missing or running out, an icon matching the Tracked Buffs style appears at the end of that row, so you know to ask for a rebuff. Tick **Only when I'm in a group** so it doesn't nag you while solo.

### Show cooldowns only when ready
Right-click an **Essential** or **Utility** cooldown and choose **Show Only When Ready**. The icon stays hidden while it's on cooldown, and appears when it's ready, or a few seconds before.

### Matching timers
Blizzard's Cooldown Manager rounds buff timers down while the tooltip rounds up, so the same buff could say "14m" in one place and "15 minutes" in another. Tracked Buffs timers now round up to match.

## Lightweight and compatible

Better Cooldown Manager doesn't replace or restyle the Cooldown Manager. It only adds menu options and changes when Blizzard's own icons are shown, so your layout, Edit Mode settings and alerts all keep working.

---

## How to use

1. Type `/bcm` to open **Cooldown Settings**.
2. **Right-click** a buff (or cooldown).
3. Hover **Reminder** (or **Show Only When Ready**) and pick when it should show.

The Cooldown Manager row needs to be visible for its icons to show. If you've set a row to only appear in combat, its reminders only appear in combat too.

## Slash commands

| Command | What it does |
|---|---|
| `/bcm` | Open Cooldown Settings |
| `/bcm list` | List your reminders |
| `/bcm clear` | Remove all reminders and About to Expire alerts |
| `/bcm debug` | Print what the addon sees (handy for bug reports) |

---

## Bugs and suggestions

Please report issues on [GitHub](https://github.com/Pa-ntsaloons/BetterCooldownManager/issues). Include the output of `/bcm debug` and any Lua error text.
