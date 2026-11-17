# Doctor Gup's Deathroller

Two-player deathrolls for World of Warcraft: Forever: verified rolls, a dice reveal with real suspense, a big gold pot, and debts that settle at the trade window.

Download it from [CurseForge](https://www.curseforge.com/wow/addons) (project 1803451).

## Releasing a new version

1. Put the new version's notes in `CHANGELOG.md` (only the newest version's notes; this file becomes the CurseForge changelog) and push to `main`.
2. On GitHub, open **Actions > Release > Run workflow**, type the version (for example `v1.1.1`) and click **Run workflow**.

The workflow runs the tests, tags the newest commit on `main` with that version, builds `DoctorGupsDeathroller-v1.1.1.zip`, uploads it to CurseForge and attaches it to a GitHub release. The version becomes the one shown in game.

Versions with `-alpha` or `-beta` in them (for example `v1.2.0-beta1`) are uploaded as alpha or beta files.

You can also push a tag yourself instead: `git tag v1.1.1 && git push origin v1.1.1`.

## Tests

`lua tests/harness.lua .` runs two simulated players through challenges, games, trades, stats and options against a mocked WoW API (Lua 5.3). It runs automatically on every push.

## Files

| File | What it does |
| --- | --- |
| `Core.lua` | Rules, add-on messages, roll reading, stats, debts, slash commands |
| `FFA.lua` | Free For All: joining by typing 1, rolls, ties, results |
| `Spectate.lua` | Watching games: serving spectators, watching, the Live list |
| `Widgets.lua` | The shared look: panels, buttons, lists, inputs |
| `GameUI.lua` | Game window, challenge popup, dice reveal |
| `FFAUI.lua` | Free For All window |
| `ChallengeUI.lua` | Wager window and version check |
| `TradeUI.lua` | Debt banner on the trade window |
| `StatsUI.lua` | Stats window: Overview, History, Debts |
| `OptionsUI.lua` | Options window and the Options > AddOns page |
| `Minimap.lua` | Minimap button |
