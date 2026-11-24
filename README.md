# Better Cooldown Manager

A lightweight World of Warcraft addon that improves Blizzard's built-in **Cooldown Manager**. It adds options to the right-click menu in Cooldown Settings, so a tracked buff can become a **reminder** that only shows when it has expired or is about to, and a cooldown can show **only when it's ready**.

Built for **WoW Forever**.

## Features

- **Buff reminders**: right-click a buff in Tracked Buffs or Tracked Bars and choose **Reminder**. Show it only once it has expired, or also early when 5 sec, 10 sec, 15 sec, 30 sec, 1, 2, 5 or 10 min (or a custom time) is left
- **Shows in Blizzard's own row**: an expired reminder appears greyed out in its usual slot, with an optional glow. Nothing new to place on screen
- **Group buff reminders**: right-click a buff in the **Group Buffs** tab (buffs other players give you, like Fortitude) and choose **Reminder**. When it's missing or running out, an icon in the Tracked Buffs style appears at the end of that row. Optionally only while you're in a group
- **About to Expire alerts**: in Blizzard's **New Alert** dialog, the **When** dropdown gets an **About to Expire** choice for buffs. Pick a time (or a custom one) and your sound, visual or text-to-speech alert plays when the buff gets that low. These alerts show in the right-click menu like Blizzard's, with play, edit and delete buttons
- **Show only when ready**: right-click an Essential or Utility cooldown to hide it until it's ready, or until it's nearly ready
- **Matching timers**: Tracked Buffs timers round up like the buff tooltip, so 14:50 left shows "15m" everywhere
- Settings are saved per character

Better Cooldown Manager doesn't replace the Cooldown Manager. It only adds menu options and changes when Blizzard's own icons are shown.

## Installation

1. Download the latest release.
2. Extract the `BetterCooldownManager` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Make sure the folder is named `BetterCooldownManager`, then restart the game or type `/reload`.

## Usage

1. Type `/bcm` to open **Cooldown Settings** (the Cooldown Manager's settings window).
2. Right-click a buff and hover **Reminder**, or right-click a cooldown and hover **Show Only When Ready**.
3. Pick **Only when it has expired** (or **Only when it is ready**). Hover it to also show the icon early, at a set time.

The Cooldown Manager row must be visible for icons to show. If a row is set to only appear in combat in Edit Mode, its reminders only appear in combat too.

### Slash commands

| Command | What it does |
|---|---|
| `/bcm` | Open Cooldown Settings |
| `/bcm list` | List your reminders |
| `/bcm clear` | Remove all reminders and About to Expire alerts |
| `/bcm debug` | Print what the addon sees (for bug reports) |

## Building a release

Update `## Version:` in `BetterCooldownManager.toc`, add a matching `## <version>` section at the top of `CHANGELOG.md`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

This creates `releases\BetterCooldownManager-<version>.zip`, ready to upload to CurseForge, and copies that version's changelog to the clipboard for the upload form.

## Reporting bugs

Please open an issue that includes the output of `/bcm debug` and any Lua error text.

## License

[MIT](LICENSE)
