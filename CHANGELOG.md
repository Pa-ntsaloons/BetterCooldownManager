# Changelog

## 1.0.0

First release.

- New **Reminder** option when you right-click a buff in Cooldown Settings: show it only once it has expired, or also when it has 5 sec to 10 min (or a custom time) left
- Expired reminders show in their normal slot in Blizzard's Tracked Buffs row, greyed out, with an optional glow
- **Reminder** option on the **Group Buffs** tab too: a Tracked Buffs-style icon appears at the end of the row when a buff from another player is missing or running out (optionally only in a group)
- **About to Expire** choice in the New Alert dialog's **When** dropdown for buffs: play a sound, visual or text-to-speech alert when a buff has a set time left
- New **Show Only When Ready** option for cooldowns: show it only when it's ready, or about to be
- Tracked Buffs timers round up to match the buff tooltip (25 minutes left shows "25m", not "24m")
- `/bcm` opens Cooldown Settings; also `/bcm list`, `/bcm clear`, `/bcm debug`
