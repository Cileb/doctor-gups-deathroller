## 1.2.1

- **Fix: no more ADDON_ACTION_BLOCKED errors from announcements.** Some clients and areas don't let add-ons post emotes. The add-on now checks first and skips them there. If WoW blocks one anyway, it tells you once and stops trying until /reload, instead of raising an error every time. Games are never affected.

## 1.2.0

- **Coin flip for who rolls first.** The challenger no longer always starts: a coin flip picks who rolls first, and both players are told the result. If the challenger is still on 1.1.x, the challenger rolls first as before.
- **Long names fit.** Names in the player cards, the wager window and the challenge popup shrink to fit their space. If a name is still too long at the smallest size, only the first name is shown.
- **Simpler close-call label.** At 10 or less the label now just reads "CLOSE CALL · ROLL 1 TO"; the chance-of-a-1 hint only shows above 10, where it adds something.
