# Doctor Gup's Deathroller

Two-player deathrolls for World of Warcraft: Forever: verified rolls, a dice reveal with real suspense, a big gold pot, and debts that settle at the trade window.

Download it from [CurseForge](https://www.curseforge.com/wow/addons) (project 1803451).

## Releasing a new version

1. Add the new version's notes to the top of `CHANGELOG.md`. Only the newest section is shown on CurseForge, so replace the old one.
2. Commit and push.
3. Tag the commit and push the tag:

   ```
   git tag v1.0.1
   git push origin v1.0.1
   ```

The **Release** workflow runs the tests, then builds `DoctorGupsDeathroller-v1.0.1.zip`, uploads it to CurseForge and attaches it to a GitHub release. The tag becomes the version shown in game.

Tags with `alpha` or `beta` in them (for example `v1.1.0-beta1`) are uploaded as alpha or beta files.

## Tests

`lua tests/harness.lua .` runs two simulated players through challenges, games, trades, stats and options against a mocked WoW API (Lua 5.3). It runs automatically on every push.

## Files

| File | What it does |
| --- | --- |
| `Core.lua` | Rules, add-on messages, roll reading, stats, debts, slash commands |
| `Widgets.lua` | The shared look: panels, buttons, lists, inputs |
| `GameUI.lua` | Game window, challenge popup, dice reveal |
| `ChallengeUI.lua` | Wager window and version check |
| `TradeUI.lua` | Debt banner on the trade window |
| `StatsUI.lua` | Stats window: Overview, History, Debts |
| `OptionsUI.lua` | Options window and the Options > AddOns page |
| `Minimap.lua` | Minimap button |
