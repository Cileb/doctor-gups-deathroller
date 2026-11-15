## 1.3.2

- **The "Press Enter to post" bar is now part of the game window.** It slides out under the window like a drawer, and moves, scales and closes with it. If you close the window while an announcement is waiting, the bar stays where the window was. Enter posts, Esc skips (a second Esc closes the window), and the x dismisses it with the mouse.
- **Removed the "Put in" button from the trade banner.** WoW doesn't let add-ons fill in the trade's gold, so the button didn't do anything. The banner now tells you how much to put in the trade's gold box, and still tracks the gold live and settles the debt when the trade completes.

## 1.3.1

- **Fix: announcements work again on WoW Forever.** Since Forever 1.60.1, add-ons can only post emotes after a key press, and a click on an add-on window doesn't count. Announcements now go out at once when you type a `/dr` command or press Enter in the wager window. After a click, a small bar shows what will be posted: press **Enter** to post it or **Esc** to skip it. Every other key keeps working as normal. Unposted announcements are dropped after 30 seconds, so nothing posts late.

## 1.3.0

- **Open challenges: play anyone, add-on or not.** Type `/dr open [gold]` (or click **Open challenge** in the stats window). Your character emotes the challenge, and the first player nearby to type `/roll 100` within 60 seconds is your opponent. That roll is their first roll. The add-on referees the whole game from chat, with the same window, dice reveal, odds and close calls.
- **Challenge in chat.** If the player you target doesn't answer the version check, the button now says **Challenge in chat**: they accept by typing `/roll 100`. Rematches and double or nothing against them work the same way.
- **Chat games, the details:** there's no coin flip (they can't take part in one), and the wager is on trust. Stats, history (marked "no add-on") and debts are kept on your side. Forfeits are announced so they know. If they stop rolling for 2 minutes, you can end the game with no result.
- **Fix: no more ADDON_ACTION_BLOCKED errors from announcements.** Some clients and areas don't let add-ons post emotes. The add-on now checks first and skips them there. If WoW blocks one anyway, it tells you once and stops trying until /reload, instead of raising an error every time. Games are never affected.
- **Odds bar fix:** the bar now uses whoever actually rolled first (it assumed the challenger).

## 1.2.0

- **Coin flip for who rolls first.** The challenger no longer always starts: a coin flip picks who rolls first, and both players are told the result. If the challenger is still on 1.1.x, the challenger rolls first as before.
- **Long names fit.** Names in the player cards, the wager window and the challenge popup shrink to fit their space. If a name is still too long at the smallest size, only the first name is shown.
- **Simpler close-call label.** At 10 or less the label now just reads "CLOSE CALL · ROLL 1 TO"; the chance-of-a-1 hint only shows above 10, where it adds something.
