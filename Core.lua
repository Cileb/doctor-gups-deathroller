-- Deathroller: two-player deathroll add-on for World of Warcraft: Forever
--
-- Core: game rules, addon-message protocol, saved stats, events and slash commands.
-- The windows live in GameUI.lua and StatsUI.lua; they read state from ns.state
-- and are told to refresh through ns.UI (see the bottom of this section).
--
-- How it works
--   * Players coordinate over hidden addon messages (challenge / accept / forfeit).
--   * The rolls themselves are real /rolls. Each client reads the server's
--     "X rolls N (1-M)" system message, so neither side can fake a result.
--   * If a roll is only seen through the opponent's addon message (you were out of
--     range of each other and not grouped), it is still applied but marked "unverified".

local ADDON_NAME, ns = ...

ns.PREFIX         = "GUPSDEATHROLL"   -- addon message prefix (max 16 chars), unique to this add-on
ns.PROTO          = 3             -- bump when the message format changes
ns.VERSION        = "?"           -- from the TOC, set on ADDON_LOADED
ns.START_ROLL     = 100           -- every deathroll starts at 1-100
ns.INVITE_TIMEOUT = 60            -- seconds to answer a challenge
ns.HISTORY_SIZE   = 1000          -- games kept for the stats window

-- Shared state the UI files read. Never replace this table, only its fields.
local S = { game = nil, invite = nil, me = nil }
ns.state = S

-- UI hooks, filled in by GameUI.lua / StatsUI.lua. Safe to call before they exist.
ns.UI = ns.UI or {}
local function UI(name, ...)
    local fn = ns.UI[name]
    if fn then return fn(...) end
end

local DB                           -- SavedVariables, set on ADDON_LOADED

-- Options (DB.settings). Change with ns.SetSetting so the UI can react.
ns.DEFAULTS = {
    autoFocus     = false,     -- put the cursor in the roll box when your turn starts
    prefillRoll   = false,     -- start the roll box with "/roll "
    animation     = true,      -- dice animation before each result
    revealSpeed   = "normal",  -- fast / normal / slow
    hideRollChat  = true,      -- hide game roll lines in chat until revealed
    sound         = true,
    announceChallenges = false, -- emote when you challenge someone or accept a challenge
    announceResults    = true,  -- show an "Announce" button on the result screen
    announceMilestones = true,  -- include milestones (streaks, biggest pot, ...) in that announcement
    tips          = true,      -- helpful tips in chat
    minimap       = true,      -- show the minimap button
    minimapAngle  = 215,       -- degrees around the minimap
    scale         = 1,         -- window size
}

-- The reveal is part of the game, not a preference: always animated, normal speed,
-- with roll lines held back from chat (ignores anything saved by v0.6.0).
local FIXED = { animation = true, revealSpeed = true, hideRollChat = true }

function ns.Setting(key)
    if FIXED[key] then return ns.DEFAULTS[key] end
    local v = DB and DB.settings and DB.settings[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

function ns.SetSetting(key, value)
    DB.settings[key] = value
    if ns.UI.OnSettingChanged then ns.UI.OnSettingChanged(key, value) end
end
local ROLL_PATTERN                 -- Lua pattern built from RANDOM_ROLL_RESULT

---------------------------------------------------------------------------
-- Helpers (exported on ns for the UI files)
---------------------------------------------------------------------------

local function Print(msg)
    print("|cffe03c3cGup's Deathroller|r: " .. tostring(msg))
end

local function Debug(msg)
    if DB and DB.debug then print("|cff888888[Deathroller debug]|r " .. (tostring(msg):gsub("|", "||"))) end
end

local function Sound(key)
    if ns.Setting("sound") and SOUNDKIT and SOUNDKIT[key] then PlaySound(SOUNDKIT[key]) end
end

local function IsSecret(v)
    -- Midnight-era "secret values" also exist in Forever; never inspect one.
    return issecretvalue and issecretvalue(v) or false
end

-- WoW Forever is realmless: "First Last" is unique across the whole region, and
-- the "-REALM" tag some APIs add (e.g. "-CAMWOWUS1REALM3PvE") is an internal shard
-- that differs between players and isn't a valid whisper address. Drop any tag.
local function FullName(name)
    if not name or IsSecret(name) then return nil end
    name = strtrim((name:match("^[^%-]+") or ""))
    if name == "" then return nil end
    return name
end

local function SameName(a, b)
    a, b = FullName(a), FullName(b)
    return a ~= nil and b ~= nil and a:lower() == b:lower()
end

local function Short(name)
    return FullName(name) or "?"
end

local function FirstName(name)
    name = Short(name)
    return name:match("^(%S+)") or name
end

local function Num(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- Typed names may be lowercase: capitalise the start of each word ("meudayr darkpaw").
local function NormalizeTypedName(name)
    name = name:gsub("(%S)(%S*)", function(first, rest) return first:upper() .. rest end)
    return FullName(name)
end

-- In Forever, UnitName() returns only the first name. GetUnitName(unit, true)
-- returns "First Last" (plus a realm tag, which FullName strips).
local function UnitFullCharName(unit)
    local name = GetUnitName and GetUnitName(unit, true)
    if not name or IsSecret(name) then name = UnitName(unit) end
    return FullName(name)
end

ns.UnitFullCharName = function(unit) return UnitFullCharName(unit) end

local function TargetName()
    if not UnitIsPlayer("target") then return nil end
    return UnitFullCharName("target")
end

local function NewId()
    return ("%d%04d"):format(time(), math.random(0, 9999))
end

ns.Print, ns.Debug, ns.Sound, ns.IsSecret = Print, Debug, Sound, IsSecret
ns.FullName, ns.SameName, ns.Short, ns.FirstName, ns.Num = FullName, SameName, Short, FirstName, Num

function ns.GetDB() return DB end

function ns.IsMyTurn()
    local g = S.game
    return g ~= nil and g.state == "active" and SameName(g.turn, S.me)
end

-- Head-to-head record against a player: wins, losses, net gold (all 0 if never played).
function ns.HeadToHead(name)
    local o = DB and DB.opponents[FullName(name) or ""]
    if not o then
        -- older saves may have stored a differently-cased key
        for key, rec in pairs(DB and DB.opponents or {}) do
            if SameName(key, name) then o = rec; break end
        end
    end
    if not o then return 0, 0, 0 end
    return o.w, o.l, o.net
end

---------------------------------------------------------------------------
-- Addon messages
---------------------------------------------------------------------------

local function Send(target, ...)
    local msg = table.concat({ ... }, "|")
    local result = C_ChatInfo.SendAddonMessage(ns.PREFIX, msg, "WHISPER", target)
    Debug(("-> %s : %s  (result %s)"):format(target, msg, tostring(result)))
    -- Older APIs return a boolean, newer ones an Enum.SendAddonMessageResult (0 = success).
    if result == false or (type(result) == "number" and result ~= 0) then
        Print(("Couldn't send to %s. Are they online? (Trial accounts can't send addon messages.)")
            :format(Short(target)))
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Roll parsing
---------------------------------------------------------------------------

-- Turn the localised "%s rolls %d (%d-%d)" into a Lua pattern.
local function BuildRollPattern()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("%%%d+%$", "%%")                          -- drop positional "%1$"
    fmt = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")    -- escape magic chars
    fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return fmt                                               -- unanchored: tolerate extra text
end

-- Strip colour codes, hyperlinks and brackets so "[Doctor Gup]" etc. still parse.
local function CleanChat(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    msg = msg:gsub("|H.-|h(.-)|h", "%1")
    msg = msg:gsub("[%[%]]", "")
    return strtrim(msg)
end

local FALLBACK_PATTERN = "(.+) rolls (%d+) %((%d+)%D+(%d+)%)"

local function ParseRoll(msg)
    if not ROLL_PATTERN then return nil end
    local clean = CleanChat(msg)
    local who, roll, lo, hi = clean:match(ROLL_PATTERN)
    if not who then who, roll, lo, hi = clean:match(FALLBACK_PATTERN) end
    if not who then return nil end
    return FullName(who), tonumber(roll), tonumber(lo), tonumber(hi)
end

-- Are game roll lines being hidden from chat (so the reveal should print them)?
function ns.IsGameRollLineHidden()
    return ns.Setting("hideRollChat") and ns.Setting("animation") and ns.chatFilterActive == true
end

-- Used by the chat filter: is this "X rolls N (1-M)" line part of the current game?
function ns.IsGameRollLine(msg)
    local g = S.game
    if not g or IsSecret(msg) then return false end
    if not (ns.Setting("hideRollChat") and ns.Setting("animation")) then return false end
    local who, roll, lo, hi = ParseRoll(msg)
    if not who then return false end
    -- before our own handler has processed it
    if g.state == "active" and lo == 1 and hi == g.max and SameName(who, g.turn) then
        return true
    end
    -- after our handler processed it (chat frames may run either side of us)
    for i = #g.rolls, math.max(1, #g.rolls - 1), -1 do
        local r = g.rolls[i]
        if SameName(r.who, who) and r.roll == roll and r.max == hi and GetTime() - r.t < 10 then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Game logic
---------------------------------------------------------------------------

-- Compact roll sequence for history tooltips: "m72,o40,m1" (m = me, o = opponent).
local function EncodeRolls(rolls)
    local parts = {}
    for i, r in ipairs(rolls) do
        parts[i] = (SameName(r.who, S.me) and "m" or "o") .. r.roll
    end
    return table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- Debts: DB.debts[name] = { amount = gold (positive: they owe you, negative: you
-- owe them), games = wagered games since it was last settled, since = time() }
-- Repeat games against the same player net out.
---------------------------------------------------------------------------

local function DebtKey(name)
    for key in pairs(DB.debts) do
        if SameName(key, name) then return key end
    end
    return FullName(name)
end

-- Amount owed (+ they owe you, - you owe them) and the record, for a player.
function ns.GetDebt(name)
    if not DB or not name then return 0 end
    local d = DB.debts[DebtKey(name)]
    if not d then return 0 end
    return d.amount, d
end

local function AdjustDebt(name, delta, fromGame)
    local key = DebtKey(name)
    local d = DB.debts[key] or { amount = 0, games = 0, since = time() }
    local wasZero = d.amount == 0
    d.amount = d.amount + delta
    if fromGame then d.games = d.games + 1 end
    if wasZero then d.since = time() end
    d.last = time()
    -- anything under 1g left over counts as settled
    if math.abs(d.amount) < 1 then DB.debts[key] = nil else DB.debts[key] = d end
    UI("RefreshStats")
    UI("RefreshTrade")
end

function ns.ClearDebt(name, how)
    local key = DebtKey(name)
    local d = DB.debts[key]
    if not d then return end
    DB.debts[key] = nil
    local amt = Num(math.floor(math.abs(d.amount) + 0.5)) .. "g"
    if how == "forgive" then
        Print(d.amount > 0 and ("Forgave %s's %s debt."):format(Short(key), amt)
            or ("Cleared the %s you owed %s."):format(amt, Short(key)))
    else
        Print(("Marked the %s debt with %s as paid."):format(amt, Short(key)))
    end
    UI("RefreshStats")
    UI("RefreshTrade")
end

-- Totals for the stats window and minimap tooltip.
function ns.DebtTotals()
    local owedToMe, iOwe, nOwedToMe, nIOwe = 0, 0, 0, 0
    for _, d in pairs(DB and DB.debts or {}) do
        if d.amount > 0 then owedToMe = owedToMe + d.amount; nOwedToMe = nOwedToMe + 1
        else iOwe = iOwe - d.amount; nIOwe = nIOwe + 1 end
    end
    return owedToMe, iOwe, nOwedToMe, nIOwe
end

local function RecordResult(g)
    local s = DB.stats
    local opp = g.opponent
    local o = DB.opponents[opp] or { w = 0, l = 0, net = 0 }
    DB.opponents[opp] = o
    local previousBiggest = s.biggestWin

    if g.won then
        s.wins = s.wins + 1; o.w = o.w + 1
        s.goldWon = s.goldWon + g.wager; o.net = o.net + g.wager
        s.streak = math.max(s.streak, 0) + 1
        s.bestStreak = math.max(s.bestStreak, s.streak)
        s.biggestWin = math.max(s.biggestWin, g.wager)
    else
        s.losses = s.losses + 1; o.l = o.l + 1
        s.goldLost = s.goldLost + g.wager; o.net = o.net - g.wager
        s.streak = math.min(s.streak, 0) - 1
    end
    o.last = time()

    table.insert(DB.history, 1, {
        t = time(), opp = opp, won = g.won, wager = g.wager,
        start = g.startMax, rolls = #g.rolls, reason = g.reason,
        seq = EncodeRolls(g.rolls),
    })
    while #DB.history > ns.HISTORY_SIZE do table.remove(DB.history) end

    -- Milestones (wins only): shown on the result screen, and announced if you choose.
    -- label = short text for the window, emote = what your character says.
    local m, oppName = {}, Short(opp)
    if g.won then
        local st = s.streak
        if st == 3 or (st >= 5 and st % 5 == 0) then
            m[#m + 1] = { label = st .. "-win streak", emote = ("is on a %d-win deathroll streak!"):format(st) }
        end
        if s.wins == 1 or s.wins == 10 or s.wins == 25 or (s.wins >= 50 and s.wins % 50 == 0) then
            m[#m + 1] = { label = s.wins == 1 and "First deathroll win" or (s.wins .. " wins"),
                          emote = s.wins == 1 and "wins their first ever deathroll!" or ("has now won %d deathrolls!"):format(s.wins) }
        end
        if g.wager > 0 and g.wager > previousBiggest and previousBiggest > 0 then
            m[#m + 1] = { label = "Biggest pot yet", emote = ("just won their biggest pot yet: %sg!"):format(Num(g.wager)) }
        end
        if o.w == 1 and o.l >= 3 then
            m[#m + 1] = { label = "First win vs " .. FirstName(oppName),
                          emote = ("finally beats %s after %d losses!"):format(oppName, o.l) }
        end
    end
    g.milestones = m

    if g.wager > 0 then AdjustDebt(opp, g.won and g.wager or -g.wager, true) end
end

local function EndGame(loser, reason)
    local g = S.game
    if not g or g.state == "done" then return end
    g.state  = "done"
    g.won    = not SameName(loser, S.me)
    g.reason = reason
    RecordResult(g)

    local opp = Short(g.opponent)
    if g.won then
        Print(("|cff4cd964You win!|r %s %s.%s"):format(opp,
            reason == "forfeit" and "forfeited" or "rolled a 1",
            g.wager > 0 and (" %s owes you %sg."):format(opp, Num(g.wager)) or ""))
    else
        Print(("|cffff4d4dYou lose.|r %s%s"):format(
            reason == "forfeit" and "You forfeited." or "You rolled a 1.",
            g.wager > 0 and (" You owe %s %sg."):format(opp, Num(g.wager)) or ""))
    end
    for _, m in ipairs(g.milestones or {}) do Print("|cffffcc40Milestone:|r " .. m.label) end
    Sound(g.won and "READY_CHECK" or "RAID_WARNING")
    UI("Update")
    UI("RefreshStats")
end

-- Apply one roll. `verified` = seen in the server's system message.
local function HandleRoll(who, roll, lo, hi, verified, rawText)
    local g = S.game
    if not g then return end

    -- An addon-message roll already applied, now confirmed by the system message.
    local last = g.rolls[#g.rolls]
    if verified and last and not last.verified and SameName(last.who, who)
        and last.roll == roll and last.max == hi then
        last.verified = true
        UI("Update")
        return
    end

    if g.state ~= "active" then Debug("roll ignored: game is " .. g.state); return end
    local isMe = SameName(who, S.me)
    if not isMe and not SameName(who, g.opponent) then
        Debug(("roll ignored: '%s' is neither me ('%s') nor opponent ('%s')"):format(who, tostring(S.me), g.opponent))
        return
    end
    if not SameName(who, g.turn) then
        Debug(("roll ignored: it's %s's turn, not %s's"):format(g.turn, who))
        return
    end
    if lo ~= 1 or hi ~= g.max then
        if verified then
            Print(("%s rolled %d-%d, but this turn is 1-%s. Ignored."):format(Short(who), lo, hi, Num(g.max)))
        end
        return
    end

    local entry = { who = who, roll = roll, max = hi, verified = verified, t = GetTime() }
    table.insert(g.rolls, entry)
    if isMe and verified then
        Send(g.opponent, "ROLL", g.id, roll, hi)        -- backup in case they can't see chat
    end

    -- Game state moves on now (so nothing else can be rolled for this turn);
    -- the window and chat only find out after the dice animation.
    if roll == 1 then
        g.state = "ending"
    else
        g.max  = roll
        g.turn = isMe and g.opponent or S.me
    end
    local line = rawText or (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"):format(Short(who), roll, 1, hi)
    local function Done()
        if roll == 1 then
            EndGame(who, "roll")
        else
            if not isMe then Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end   -- your turn
            UI("Update")
        end
    end
    if ns.UI.Reveal then ns.UI.Reveal(entry, line, Done) else Done() end
end

---------------------------------------------------------------------------
-- Public announcements (emotes). WoW only lets an add-on emote straight after a
-- click or key press, so these are only called from /dr commands and buttons.
---------------------------------------------------------------------------

local lastEmote = 0
local function Emote(text)
    if InCombatLockdown and InCombatLockdown() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    local ok = pcall(send, text, "EMOTE")
    if not ok then Debug("emote blocked: " .. text) end
    lastEmote = GetTime()
    return ok
end

local function WagerText(wager, fmt)
    return wager > 0 and fmt:format(Num(wager)) or ""
end

local function AnnounceChallenge(g)
    if not ns.Setting("announceChallenges") then return end
    if GetTime() - lastEmote < 20 then return end           -- don't spam rematches
    Emote(("challenges %s to a deathroll%s!"):format(Short(g.opponent), WagerText(g.wager, " for %sg")))
end

-- The "Announce" button on the result screen.
function ns.AnnounceResult()
    local g = S.game
    if not g or g.state ~= "done" or g.announced then return end
    local opp, first = Short(g.opponent), FirstName(g.opponent)
    local n = #g.rolls
    local rolls = (n == 1) and "1 roll" or (n .. " rolls")
    local line
    if g.won and g.reason == "forfeit" then
        line = n == 0
            and ("wins a deathroll against %s%s - %s forfeited before the first roll."):format(opp, WagerText(g.wager, " for %sg"), first)
            or ("wins a deathroll against %s%s after %s - %s forfeited."):format(opp, WagerText(g.wager, " for %sg"), rolls, first)
    elseif g.won then
        line = ("wins a deathroll against %s%s in %s!"):format(opp, WagerText(g.wager, " for %sg"), rolls)
    elseif g.reason == "forfeit" then
        line = n == 0
            and ("forfeits a deathroll to %s%s before the first roll."):format(opp, WagerText(g.wager, " (%sg)"))
            or ("forfeits a deathroll to %s%s after %s."):format(opp, WagerText(g.wager, " (%sg)"), rolls)
    else
        line = ("loses a deathroll to %s%s after %s."):format(opp, WagerText(g.wager, " (%sg)"), rolls)
    end
    if not Emote(line) then Print("Couldn't announce right now (in combat?)."); return end
    if ns.Setting("announceMilestones") then
        for i, m in ipairs(g.milestones or {}) do
            if i > 2 then break end
            Emote(m.emote)
        end
    end
    g.announced = true
    UI("Update")
end

function ns.StartChallenge(target, wager)
    local max = ns.START_ROLL
    if S.game and S.game.state ~= "done" then
        Print("You're already in a deathroll. Finish it or /dr forfeit first.")
        return
    end
    if SameName(target, S.me) then Print("You can't deathroll yourself."); return end
    wager = math.max(0, math.floor(tonumber(wager) or 0))

    local g = {
        id = NewId(), opponent = target, challenger = S.me,
        max = max, startMax = max, wager = wager,
        turn = S.me, rolls = {}, state = "pending",
        expires = GetTime() + ns.INVITE_TIMEOUT,
    }
    S.game = g
    -- last field: is the challenger announcing? (older versions ignore it)
    local announcing = ns.Setting("announceChallenges") and 1 or 0
    if not Send(target, "CHAL", ns.PROTO, g.id, max, wager, announcing) then S.game = nil; UI("Update"); return end

    Print(("Challenged %s: 1-%s%s. Waiting for an answer..."):format(Short(target), Num(max),
        wager > 0 and (" for %sg"):format(Num(wager)) or ""))
    AnnounceChallenge(g)
    UI("Update")

    C_Timer.After(ns.INVITE_TIMEOUT, function()
        if S.game == g and g.state == "pending" then
            Print(("No answer from %s. Do they have Deathroller installed?"):format(Short(target)))
            S.game = nil
            UI("Update")
        end
    end)
end

-- Open the wager window for a player (from /dr with a target, or /dr challenge Name).
function ns.OpenChallenge(target, wager)
    if S.game and S.game.state ~= "done" then
        Print("You're already in a deathroll. Finish it or /dr forfeit first.")
        UI("Update")
        return
    end
    if SameName(target, S.me) then Print("You can't deathroll yourself."); return end
    UI("ShowChallengeSetup", target, math.max(0, math.floor(tonumber(wager) or 0)))
end

-- Your gold, in whole gold pieces.
function ns.MyGold()
    return math.floor((GetMoney and GetMoney() or 0) / 10000)
end

function ns.Rematch()
    local g = S.game
    if g and g.state == "done" then ns.StartChallenge(g.opponent, g.wager) end
end

local function CancelChallenge()
    local g = S.game
    if g and g.state == "pending" then
        Send(g.opponent, "CANC", g.id)
        Print("Challenge cancelled.")
        S.game = nil
        UI("Update")
    end
end

function ns.Forfeit()
    local g = S.game
    if not g then return end
    if g.state == "pending" then CancelChallenge(); return end
    if g.state ~= "active" then return end
    Send(g.opponent, "FORF", g.id)
    EndGame(S.me, "forfeit")
end

-- Clear a finished game (the window was closed).
function ns.ClearFinished()
    if S.game and S.game.state == "done" then S.game = nil end
end

local function ProximityTip()
    if ns.Setting("tips") and not IsInGroup() then
        Print("Tip: stand near each other or group up, so both of you can see every roll in chat.")
    end
end

-- announce: whether to emote the accept (the popup's checkbox). nil = use your setting.
function ns.AcceptInvite(announce)
    local inv = S.invite
    if not inv then return end
    S.invite = nil
    UI("HideInvite")
    if S.game and S.game.state ~= "done" then Send(inv.from, "BUSY", inv.id); return end

    S.game = {
        id = inv.id, opponent = inv.from, challenger = inv.from,
        max = inv.max, startMax = inv.max, wager = inv.wager,
        turn = inv.from, rolls = {}, state = "active",
    }
    Send(inv.from, "ACC", inv.id)
    Print(("Deathroll on! %s rolls first."):format(Short(inv.from)))
    if announce == nil then announce = ns.Setting("announceChallenges") end
    if announce then
        Emote(("accepts %s's deathroll challenge%s!"):format(Short(inv.from), WagerText(inv.wager, " for %sg")))
    end
    ProximityTip()
    UI("Update")
end

function ns.DeclineInvite(timedOut)
    local inv = S.invite
    if not inv then return end
    Send(inv.from, "DEC", inv.id)
    S.invite = nil
    UI("HideInvite")
    if timedOut then Print(("You didn't answer %s's challenge in time."):format(Short(inv.from))) end
end

---------------------------------------------------------------------------
-- Version check: before you challenge someone, ask their add-on what version it is.
-- PING|id  ->  PONG|id|proto|version|busy
-- probe.status: checking, ok, different (same protocol, other version), incompatible,
--               busy, noreply, offline
---------------------------------------------------------------------------

local probe
local lastPong = {}
ns.PROBE_TIMEOUT = 3

-- Compare "0.9.1"-style versions: -1, 0 or 1.
local function CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end
ns.CompareVersions = CompareVersions

function ns.CheckPlayer(target)
    local p = { target = target, id = NewId(), status = "checking" }
    probe = p
    if not Send(target, "PING", p.id) then p.status = "offline" end
    UI("ProbeUpdated", p)
    C_Timer.After(ns.PROBE_TIMEOUT, function()
        if probe == p and p.status == "checking" then
            p.status = "noreply"
            UI("ProbeUpdated", p)
        end
    end)
    return p
end

-- "No player named X is currently playing." for the player we're checking?
local notFoundPattern
local function IsNotFound(msg, name)
    if not notFoundPattern then
        local fmt = (ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."):gsub("['\"]", "")
        fmt = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%s", "(.+)")
        notFoundPattern = "^" .. fmt .. "$"
    end
    local who = msg:gsub("['\"]", ""):match(notFoundPattern)
    return who ~= nil and SameName(who, name)
end

local function OnAddonMessage(text, sender)
    sender = FullName(sender)
    if not sender or SameName(sender, S.me) then return end
    local cmd, a, b, c, d, e = strsplit("|", text)

    if cmd == "PING" then
        if GetTime() - (lastPong[sender] or 0) < 0.25 then return end  -- don't let anyone spam replies
        lastPong[sender] = GetTime()
        local busy = (S.game and S.game.state ~= "done") or S.invite
        Send(sender, "PONG", a or "", ns.PROTO, ns.VERSION, busy and 1 or 0)
        return
    end

    if cmd == "PONG" then
        local p = probe
        if not p or p.id ~= a or not SameName(p.target, sender) then return end
        p.theirProto, p.theirVersion = tonumber(b), c or "?"
        if p.theirProto ~= ns.PROTO then p.status = "incompatible"
        elseif d == "1" then p.status = "busy"
        elseif CompareVersions(p.theirVersion, ns.VERSION) ~= 0 then p.status = "different"
        else p.status = "ok" end
        UI("ProbeUpdated", p)
        return
    end

    if cmd == "CHAL" then
        local proto, id, max, wager = tonumber(a), b, tonumber(c), tonumber(d) or 0
        if proto ~= ns.PROTO then
            Print(("%s uses a different Deathroller version. Ask them to update (or update yourself)."):format(Short(sender)))
            return
        end
        if not id or max ~= ns.START_ROLL then return end
        if (S.game and S.game.state ~= "done") or S.invite then Send(sender, "BUSY", id); return end

        S.invite = { from = sender, id = id, max = max, wager = math.max(0, math.floor(wager)),
                     expires = GetTime() + ns.INVITE_TIMEOUT, announced = (e == "1") }
        UI("ShowInvite", S.invite)
        Sound("READY_CHECK")
        return
    end

    if cmd == "CANC" then
        if S.invite and S.invite.id == a and SameName(S.invite.from, sender) then
            S.invite = nil
            UI("HideInvite")
            Print(("%s cancelled the challenge."):format(Short(sender)))
        end
        return
    end

    -- Everything below belongs to the current game with this opponent.
    local g = S.game
    if not g or g.id ~= a or not SameName(g.opponent, sender) then
        Debug(("ignored %s from %s (game %s, opponent %s)"):format(cmd, sender,
            g and g.id or "none", g and g.opponent or "none"))
        return
    end

    if cmd == "ACC" and g.state == "pending" then
        g.state = "active"
        Print(("%s accepted. You roll first: type /roll %d."):format(Short(sender), g.max))
        ProximityTip()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        UI("Update")
    elseif (cmd == "DEC" or cmd == "BUSY") and g.state == "pending" then
        Print(cmd == "DEC" and ("%s declined."):format(Short(sender))
            or ("%s is busy with another deathroll."):format(Short(sender)))
        S.game = nil
        UI("Update")
    elseif cmd == "ROLL" then
        local roll, max = tonumber(b), tonumber(c)
        if roll and max then HandleRoll(sender, roll, 1, max, false) end
    elseif cmd == "FORF" then
        EndGame(sender, "forfeit")
    end
end

-- The roll box in the game window: only the real command counts, "/roll 72" or "/roll 1-72".
-- Returns true if a roll was made, or false plus a reason.
function ns.TryRollCommand(text)
    text = strtrim(text or ""):lower()
    local n = tonumber(text:match("^/roll%s+(%d+)$") or text:match("^/roll%s+1%s*%-%s*(%d+)$"))
    Debug(("roll box: '%s' -> %s"):format(text, tostring(n)))
    if not ns.IsMyTurn() then return false, "turn" end
    if n ~= S.game.max then return false, "wrong" end
    RandomRoll(1, n)          -- Enter is a key press, so this counts as a player action
    return true
end

function ns.ResetStats()
    DB.stats = { wins = 0, losses = 0, goldWon = 0, goldLost = 0, streak = 0, bestStreak = 0, biggestWin = 0 }
    DB.opponents = {}
    DB.history = {}
    Print("Stats reset.")
    UI("RefreshStats")
end

---------------------------------------------------------------------------
-- Trades: when you trade someone you have a deathroll debt with, show the banner
-- (TradeUI.lua) and, when the trade completes, count the gold toward the debt.
-- S.trade = { partner, count (checkbox), give, get (copper), money, applied }
---------------------------------------------------------------------------

local function TradeGold()
    local give = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
    local get = GetTargetTradeMoney and GetTargetTradeMoney() or 0
    return give, get
end

local function ApplyTrade(t)
    if t.applied then return end
    t.applied = true
    if not t.count then return end
    local debt = ns.GetDebt(t.partner)
    local who = Short(t.partner)
    if debt > 0 and t.get > 0 then
        local credit = math.min(debt, t.get / 10000)
        AdjustDebt(t.partner, -credit)
        local left = ns.GetDebt(t.partner)
        Print(left > 0 and ("%s paid %sg. They still owe you %sg."):format(who, Num(math.floor(credit + 0.5)), Num(math.floor(left + 0.5)))
            or ("%s paid up. Debt settled!"):format(who))
    elseif debt < 0 and t.give > 0 then
        local credit = math.min(-debt, t.give / 10000)
        AdjustDebt(t.partner, credit)
        local left = ns.GetDebt(t.partner)
        Print(left < 0 and ("You paid %s %sg. You still owe %sg."):format(who, Num(math.floor(credit + 0.5)), Num(math.floor(-left + 0.5)))
            or ("You paid %s. Debt settled!"):format(who))
    end
end

local function OnTradeEvent(event, ...)
    if event == "TRADE_SHOW" then
        local partner = ns.UnitFullCharName("NPC")
        if partner and ns.GetDebt(partner) ~= 0 then
            S.trade = { partner = partner, count = true, give = 0, get = 0, money = GetMoney() }
            UI("ShowTrade", S.trade)
        else
            S.trade = nil
        end
        return
    end
    local t = S.trade
    if not t then return end

    if event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        t.give, t.get = TradeGold()
        t.money = GetMoney()
        UI("RefreshTrade")
    elseif event == "UI_INFO_MESSAGE" then
        local _, msg = ...
        if msg and not IsSecret(msg) and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then ApplyTrade(t) end
    elseif event == "TRADE_CLOSED" then
        UI("HideTrade")
        -- Backup check: if our gold changed by exactly the traded amounts, it went through.
        C_Timer.After(1, function()
            if not t.applied and (t.give > 0 or t.get > 0)
                and GetMoney() == t.money - t.give + t.get then
                ApplyTrade(t)
            end
            if S.trade == t then S.trade = nil end
        end)
    end
end

-- "Put in Ng" on the trade banner (a click, so the game allows it).
function ns.PayDebtInTrade()
    local t = S.trade
    if not t then return false end
    local debt = ns.GetDebt(t.partner)
    if debt >= 0 then return false end
    local copper = math.ceil(-debt) * 10000
    if GetMoney() < copper then
        Print(("You only have %sg; you owe %sg."):format(Num(ns.MyGold()), Num(math.ceil(-debt))))
        return false
    end
    local ok = SetTradeMoney and pcall(SetTradeMoney, copper)
    t.give = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or t.give
    UI("RefreshTrade")
    return ok and t.give == copper
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Help()
    Print("commands")
    print("   /dr (or /gup)  - with a player targeted: challenge them (choose your wager)")
    print("   /dr challenge First Last  - challenge someone who isn't targeted")
    print("   On your turn, type /roll N in the window's box (or in chat) and press Enter.")
    print("   /dr forfeit   - give up / cancel your challenge")
    print("   /dr show      - reopen the game window")
    print("   /dr stats     - open/close the stats window")
    print("   /dr options   - settings (auto-focus, animation, minimap button, ...)")
    print("   /dr minimap   - show/hide the minimap button")
    print("   /dr version   - show your Deathroller version")
    print("   /dr debug     - show what the add-on sends, receives and reads (for troubleshooting)")
end

SLASH_GUPSDEATHROLLER1 = "/deathroll"
SLASH_GUPSDEATHROLLER2 = "/dr"
SLASH_GUPSDEATHROLLER3 = "/deathroller"
SLASH_GUPSDEATHROLLER4 = "/gup"          -- always free, in case another deathroll add-on also uses /dr
SlashCmdList.GUPSDEATHROLLER = function(input)
    local args = {}
    for word in (input or ""):gmatch("%S+") do args[#args + 1] = word end
    local cmd = (args[1] or ""):lower()

    if cmd == "challenge" or cmd == "c" or cmd == "duel" then
        -- "/dr c Meudayr Darkpaw 20", "/dr c Meudayr Darkpaw", or "/dr c 20" with a target.
        -- Names have a space in Forever, so the gold (if any) is the last word.
        local words = { select(2, unpack(args)) }
        local wager = 0
        local last = words[#words] and tonumber((words[#words]:gsub("[gG]$", "")))
        if last then wager = last; words[#words] = nil end

        local target
        if #words > 0 then
            target = NormalizeTypedName(table.concat(words, " "))
        else
            target = TargetName()
        end
        if not target then Print("Target a player and type /dr, or use /dr challenge First Last."); return end
        ns.OpenChallenge(target, wager)
    elseif cmd == "forfeit" or cmd == "ff" or cmd == "cancel" then
        ns.Forfeit()
    elseif cmd == "show" then
        if S.game then UI("Update") else Print("No deathroll in progress.") end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        UI("ToggleOptions")
    elseif cmd == "minimap" then
        ns.SetSetting("minimap", not ns.Setting("minimap"))
        Print("Minimap button " .. (ns.Setting("minimap") and "shown." or "hidden. /dr minimap brings it back."))
    elseif cmd == "version" or cmd == "v" then
        Print("version " .. ns.VERSION)
    elseif cmd == "debug" then
        DB.debug = not DB.debug
        Print("Debug messages " .. (DB.debug and "on." or "off."))
        Debug(("me = '%s', roll pattern = %s"):format(tostring(S.me), tostring(ROLL_PATTERN)))
        UI("OnSettingChanged", "debug", DB.debug)
    elseif cmd == "stats" then
        UI("ToggleStats")
    elseif cmd == "" then
        -- Main entry point: a game in progress comes first, then a targeted player
        -- (opens the wager window), otherwise the last game or your stats.
        local target = TargetName()
        if S.game and S.game.state ~= "done" then UI("Update")
        elseif target and not SameName(target, S.me) then ns.OpenChallenge(target)
        elseif S.game then UI("Update")
        else UI("ToggleStats") end
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_ADDON")
for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE" }) do
    events:RegisterEvent(e)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        DoctorGupsDeathrollerDB = DoctorGupsDeathrollerDB or {}
        DB = DoctorGupsDeathrollerDB
        DB.stats = DB.stats or { wins = 0, losses = 0, goldWon = 0, goldLost = 0 }
        DB.stats.streak = DB.stats.streak or 0
        DB.stats.bestStreak = DB.stats.bestStreak or 0
        DB.stats.biggestWin = DB.stats.biggestWin or 0
        DB.opponents = DB.opponents or {}
        DB.history = DB.history or {}
        DB.settings = DB.settings or {}
        DB.debts = DB.debts or {}
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        ns.VERSION = meta and meta(ADDON_NAME, "Version") or "?"

    elseif event == "PLAYER_LOGIN" then
        S.me = UnitFullCharName("player")
        ROLL_PATTERN = BuildRollPattern()
        C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
        UI("Init")
        UI("InitMinimap")
        UI("InitOptions")

    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...
        if probe and probe.status == "checking" and not IsSecret(msg) and IsNotFound(msg, probe.target) then
            probe.status = "offline"
            UI("ProbeUpdated", probe)
        end
        if not S.game or not ROLL_PATTERN then return end
        if IsSecret(msg) then Debug("system message is a secret value; can't read it"); return end
        local who, roll, lo, hi = ParseRoll(msg)
        Debug(("system: %s  ->  %s"):format(msg, who and ("%s %d (%d-%d)"):format(who, roll, lo, hi) or "not a roll"))
        if who then HandleRoll(who, roll, lo, hi, true, msg) end

    elseif event:find("^TRADE_") or event == "UI_INFO_MESSAGE" then
        OnTradeEvent(event, ...)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if IsSecret(prefix) or prefix ~= ns.PREFIX or IsSecret(text) or IsSecret(sender) then return end
        Debug(("<- %s [%s] : %s"):format(tostring(sender), tostring(channel), tostring(text)))
        OnAddonMessage(text, sender)
    end
end)

-- Addon compartment (the add-ons button by the minimap): left-click stats, right-click options.
function DoctorGupsDeathroller_OnCompartmentClick(_, button)
    if button == "RightButton" then UI("ToggleOptions")
    elseif S.game then UI("Update")
    else UI("ToggleStats") end
end
