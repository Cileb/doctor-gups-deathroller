-- Spectating: watch someone else's 1v1 or Free For All, from anywhere.
--
-- Serving (you're playing): a spectator's add-on asks yours to be let in. Yours
-- then sends them hidden add-on whispers as the game moves: each roll, state
-- changes and the result. It does this by comparing the game to what it last sent,
-- several times a second, so it doesn't need hooks all over the game code. Up to
-- ns.SPEC_MAX spectators; turn "Let others watch your games" off to refuse.
-- It also tells your guild and group about live games (the "Live" tab).
--
-- Watching: the game window (1v1) or the Free For All window opens read-only,
-- with the same dice reveal. Nothing is recorded for spectators, and nothing is
-- said in chat.
--
-- Messages (prefix GUPSDEATHROLL):
--   WREQ|req              please let me watch        WNO|req|why   no (off / none / full)
--   WSTOP|gid             I've stopped watching
--   1v1:  WOD|req|gid|opp|challenger|state|turn|startMax|max|wager|double|won|reason|rolls|total
--         WS|gid|state|turn|max|opp   WR|gid|S/O|roll|max   WE|gid|won|reason   WX|gid
--         (S = the player you asked, O = their opponent; won is from S's side)
--   FFA:  WOF|req|gid|max|phase|expiresIn   WFS|gid|phase|expiresIn|max
--         WFP|gid|name|roll|reroll|tie|host   WFL|gid|name
--         WFE|gid|winner|payer|high|low|amount|flag   WFX|gid
--   Live: LIVE|d|gid|p1|p2|wager|max   LIVE|f|gid|host|max|count|phase   LIVEX|gid

local ADDON_NAME, ns = ...
local S = ns.state

ns.SPEC_MAX      = 10
ns.LIVE_EVERY    = 45      -- re-announce live games this often
ns.LIVE_LIFETIME = 120     -- forget a live game we haven't heard about for this long
ns.WATCH_WAIT    = 4       -- seconds to wait for an answer to "let me watch"

local function UI(name, ...)
    local fn = ns.UI[name]
    if fn then return fn(...) end
end
local function Print(...) return ns.Print(...) end
local function Short(n) return ns.Short(n) end
local function FirstName(n) return ns.FirstName(n) end

local function Join(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = t[i] == nil and "" or tostring(t[i]) end
    return table.concat(t, "|")
end

local function Whisper(name, ...)
    if not name then return end
    local msg = Join(...)
    ns.Debug(("-> %s : %s"):format(name, msg))
    pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, "WHISPER", name)
end

-- Tell your guild and your group (live games list).
local function Broadcast(...)
    local msg = Join(...)
    if IsInGuild and IsInGuild() then pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, "GUILD") end
    if IsInGroup and IsInGroup() then
        pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    end
end

local function Allowed() return ns.Setting("allowSpectators") end

---------------------------------------------------------------------------
-- Serving your game
---------------------------------------------------------------------------

local duel = { watchers = {} }     -- what we've sent about S.game
local ffa = { watchers = {} }      -- ... and about S.ffa

local function SendAll(side, ...)
    for _, name in ipairs(side.watchers) do Whisper(name, ...) end
end

local function IndexOf(list, name)
    for i, n in ipairs(list) do if ns.SameName(n, name) then return i end end
end

-- Who's watching you right now (for the "2 watching" line).
function ns.WatcherNames()
    if S.ffa then return ffa.watchers end
    return duel.watchers
end

local function Side(g, who) return ns.SameName(who, S.me) and "S" or "O" end

local function EncodeRolls(g)
    local parts, from = {}, math.max(1, #g.rolls - 11)
    for i = from, #g.rolls do
        local r = g.rolls[i]
        parts[#parts + 1] = Side(g, r.who) .. r.roll
    end
    return table.concat(parts, ".")
end

local function DuelSnapshot(req, g)
    local won = g.state == "done" and (g.won and 1 or 0) or ""
    return "WOD", req, g.id, g.opponent or "", g.challenger or "", g.state, g.turn or "", g.startMax, g.max,
        g.wager, g.double and 1 or 0, won, g.reason or "", EncodeRolls(g), #g.rolls
end

local function FFAPlayerMsg(f, p)
    return "WFP", f.id, p.name, p.roll or "", p.reroll or "", p.tie or "", p.host and 1 or 0
end

local function FFAResultMsg(f)
    local r = f.result or {}
    if r.winner then
        return "WFE", f.id, r.winner, r.payer, f.highRoll, f.lowRoll, r.amount, ""
    end
    return "WFE", f.id, "", "", f.highRoll or "", f.lowRoll or "", 0, r.allTied and "tied" or "none"
end

local function ExpiresIn(f)
    return f.expires and math.max(0, math.floor(f.expires - GetTime() + 0.5)) or 0
end

local function OnWatchStop(sender)
    for _, side in ipairs({ duel, ffa }) do
        local i = IndexOf(side.watchers, sender)
        if i then table.remove(side.watchers, i) end
    end
    UI("Update"); UI("FFAUpdate")
end

local function DuelLive(g)
    if not Allowed() then return end
    Broadcast("LIVE", "d", g.id, S.me, g.opponent or "", g.wager, g.max)
end

-- Compare S.game with what we last sent and send the difference.
local function TickDuel()
    local g = S.game
    if duel.g ~= g then
        if duel.g then
            if not duel.ended then SendAll(duel, "WX", duel.g.id) end
            if duel.live then Broadcast("LIVEX", duel.g.id) end
        end
        duel.g, duel.state, duel.sent, duel.ended, duel.live, duel.liveAt = g, nil, 0, false, false, 0
        duel.watchers = {}
    end
    if not g then return end
    if g.state ~= duel.state then
        duel.state = g.state
        SendAll(duel, "WS", g.id, g.state, g.turn or "", g.max, g.opponent or "")
    end
    while duel.sent < #g.rolls do
        duel.sent = duel.sent + 1
        local r = g.rolls[duel.sent]
        SendAll(duel, "WR", g.id, Side(g, r.who), r.roll, r.max)
    end
    if g.state == "done" and not duel.ended then
        duel.ended = true
        SendAll(duel, "WE", g.id, g.won and 1 or 0, g.reason or "")
        if duel.live then Broadcast("LIVEX", g.id); duel.live = false end
    end
    local live = (g.state == "active" or g.state == "ending") and g.opponent
    if live and Allowed() and (not duel.live or GetTime() - duel.liveAt >= ns.LIVE_EVERY) then
        duel.live, duel.liveAt = true, GetTime()
        DuelLive(g)
    end
end

local function TickFFA()
    local f = S.ffa
    if ffa.f ~= f then
        if ffa.f then
            if not ffa.ended then SendAll(ffa, "WFX", ffa.f.id) end
            if ffa.live then Broadcast("LIVEX", ffa.f.id) end
        end
        ffa.f, ffa.phase, ffa.round, ffa.snap, ffa.ended, ffa.live, ffa.liveAt = f, nil, nil, {}, false, false, 0
        ffa.watchers = {}
    end
    if not f then return end
    local changedPhase = f.phase ~= ffa.phase or f.round ~= ffa.round
    if changedPhase then
        ffa.phase, ffa.round = f.phase, f.round
        SendAll(ffa, "WFS", f.id, f.phase, ExpiresIn(f), f.max)
    end
    local seen = {}
    for _, p in ipairs(f.players) do
        local key = Join(p.roll, p.reroll, p.tie, p.host)
        seen[p.name] = true
        if ffa.snap[p.name] ~= key then
            ffa.snap[p.name] = key
            SendAll(ffa, FFAPlayerMsg(f, p))
        end
    end
    for name in pairs(ffa.snap) do
        if not seen[name] then ffa.snap[name] = nil; SendAll(ffa, "WFL", f.id, name) end
    end
    if f.phase == "done" and not ffa.ended then
        ffa.ended = true
        SendAll(ffa, FFAResultMsg(f))
        if ffa.live then Broadcast("LIVEX", f.id); ffa.live = false end
    end
    if f.phase ~= "done" and Allowed() and (changedPhase or not ffa.live or GetTime() - ffa.liveAt >= ns.LIVE_EVERY) then
        ffa.live, ffa.liveAt = true, GetTime()
        Broadcast("LIVE", "f", f.id, S.me, f.max, #f.players, f.phase)
    end
end

local function OnWatchRequest(sender, req)
    if not Allowed() then Whisper(sender, "WNO", req, "off"); return end
    TickDuel(); TickFFA()                                  -- in sync before adding them
    local side
    if S.ffa then side = ffa
    elseif S.game then side = duel
    else Whisper(sender, "WNO", req, "none"); return end
    if not IndexOf(side.watchers, sender) then
        if #side.watchers >= ns.SPEC_MAX then Whisper(sender, "WNO", req, "full"); return end
        side.watchers[#side.watchers + 1] = sender
    end
    if side == ffa then
        local f = S.ffa
        Whisper(sender, "WOF", req, f.id, f.max, f.phase, ExpiresIn(f))
        for _, p in ipairs(f.players) do Whisper(sender, FFAPlayerMsg(f, p)) end
        if f.phase == "done" then Whisper(sender, FFAResultMsg(f)) end
    else
        Whisper(sender, DuelSnapshot(req, S.game))
    end
    UI("Update"); UI("FFAUpdate")                          -- "1 watching"
end

-- Spectating turned off mid-game: let everyone go.
ns.OnSetting(function(key, value)
    if key ~= "allowSpectators" or value then return end
    for _, side in ipairs({ duel, ffa }) do
        local gid = side.g and side.g.id or (side.f and side.f.id)
        if gid then
            SendAll(side, side == ffa and "WFX" or "WX", gid)
            if side.live then Broadcast("LIVEX", gid); side.live = false end
        end
        side.watchers = {}
    end
end)

local function Tick()
    if S.me then
        TickDuel()
        TickFFA()
    end
    C_Timer.After(0.2, Tick)
end
C_Timer.After(1, Tick)

---------------------------------------------------------------------------
-- Watching someone else
---------------------------------------------------------------------------

local pending          -- { server, req, t }

local function Playing()
    return (S.game and S.game.state ~= "done") or (ns.FFA_IsActive and ns.FFA_IsActive())
end

function ns.IsWatching() return S.watch ~= nil end

-- name: "First Last", or nil for your target.
function ns.Watch(name)
    if Playing() then Print("You can't watch while you're in a game yourself."); return end
    if not name or name == "" then
        name = ns.UnitFullCharName and UnitIsPlayer and UnitIsPlayer("target") and ns.UnitFullCharName("target")
        if not name then Print("Target the player you want to watch, or type /dr watch First Last."); return end
    end
    name = ns.FullName(name)
    if not name then return end
    if ns.SameName(name, S.me) then Print("That's you."); return end
    if S.watch then ns.StopWatching(true) end
    local req = tostring(math.random(100000, 999999))
    pending = { server = name, req = req, t = GetTime() }
    Whisper(name, "WREQ", req)
    C_Timer.After(ns.WATCH_WAIT, function()
        if pending and pending.req == req then
            pending = nil
            Print(("No answer from %s. They may not be online, or may need the latest Doctor Gup's Deathroller."):format(Short(name)))
        end
    end)
end

function ns.StopWatching(quiet)
    local w = S.watch
    if not w then return end
    Whisper(w.server, "WSTOP", w.gid)
    S.watch = nil
    if not quiet then Print("Stopped watching.") end
    UI("Update"); UI("FFAUpdate")
end

local function Other(g, side) return side == "S" and g.left or g.opponent end

local function ApplyEnd(g, won, reason)
    g.state, g.won, g.reason, g.pendingEnd = "done", won, reason, nil
    local winner = won and g.left or g.opponent
    Print(("%s wins the deathroll against %s."):format(Short(winner), Short(won and g.opponent or g.left)))
    UI("Update")
end

local function OnDuelSnapshot(sender, parts)
    local _, _, gid, opp, challenger, state, turn, startMax, max, wager, double, won, reason, rolls, total =
        unpack(parts)
    local g = {
        spectate = true, id = gid, left = sender, opponent = opp ~= "" and opp or nil,
        challenger = challenger ~= "" and challenger or sender, state = state,
        turn = turn ~= "" and turn or nil, startMax = tonumber(startMax) or 100, max = tonumber(max) or 100,
        wager = tonumber(wager) or 0, double = double == "1", rolls = {},
    }
    -- rolls so far: already seen, no reveal
    local who = { S = sender, O = g.opponent }
    for token in (rolls or ""):gmatch("[^%.]+") do
        local side, roll = token:sub(1, 1), tonumber(token:sub(2))
        if roll then
            g.rolls[#g.rolls + 1] = { who = who[side], roll = roll, max = 0, verified = true, revealed = true, t = 0 }
        end
    end
    g.skipped = math.max(0, (tonumber(total) or #g.rolls) - #g.rolls)
    if state == "done" then g.won, g.reason = won == "1", reason ~= "" and reason or "roll" end
    S.watch = { server = sender, kind = "duel", gid = gid, game = g }
    Print(("Watching %s vs %s. Close the window to stop."):format(Short(sender), g.opponent and Short(g.opponent) or "an open challenge"))
    UI("Update")
end

local function OnDuelUpdate(cmd, parts)
    local g = S.watch.game
    if cmd == "WS" then
        local state, turn, max, opp = parts[3], parts[4], tonumber(parts[5]), parts[6]
        if opp ~= "" then g.opponent = opp end
        if (g.state == "pending" or g.state == "open") and state == "active" then
            g.state, g.turn, g.max = "active", turn ~= "" and turn or g.turn, max or g.max
            UI("Update")
        elseif state == "pending" or state == "open" then
            g.state = state
            UI("Update")
        end
    elseif cmd == "WR" then
        local side, roll, max = parts[3], tonumber(parts[4]), tonumber(parts[5])
        if not (roll and max) then return end
        local who = Other(g, side)
        if g.state == "pending" or g.state == "open" then g.state = "active" end
        local entry = { who = who, roll = roll, max = max, verified = true, t = GetTime() }
        table.insert(g.rolls, entry)
        if roll == 1 then
            g.state = "ending"
        else
            g.max = roll
            g.turn = ns.SameName(who, g.left) and g.opponent or g.left
        end
        local line = (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"):format(Short(who), roll, 1, max)
        local function Done()
            if g.pendingEnd then ApplyEnd(g, g.pendingEnd.won, g.pendingEnd.reason) else UI("Update") end
        end
        if ns.UI.Reveal then ns.UI.Reveal(entry, line, Done) else entry.revealed = true; Done() end
    elseif cmd == "WE" then
        local won, reason = parts[3] == "1", parts[4] ~= "" and parts[4] or "roll"
        local last = g.rolls[#g.rolls]
        if reason == "roll" and last and not last.revealed then
            g.pendingEnd = { won = won, reason = reason }      -- after the dice land
        else
            ApplyEnd(g, won, reason)
        end
    elseif cmd == "WX" then
        if g.state ~= "done" then
            g.state, g.noResult = "done", true
            Print(("%s's game ended without a result."):format(Short(S.watch.server)))
            UI("Update")
        end
    end
end

local function FFAPlayer(f, name)
    for i, p in ipairs(f.players) do if ns.SameName(p.name, name) then return p, i end end
end

local function OnFFAMessage(cmd, parts, sender)
    if cmd == "WOF" then
        local _, _, gid, max, phase, expiresIn = unpack(parts)
        local f = {
            spectate = true, id = gid, host = sender, max = tonumber(max) or 0, phase = phase,
            players = {}, expires = GetTime() + (tonumber(expiresIn) or 0),
            total = phase == "join" and ns.FFA_JOIN_TIME or ns.FFA_ROLL_TIME,
        }
        S.watch = { server = sender, kind = "ffa", gid = gid, ffa = f }
        Print(("Watching %s's Free For All (1-%s). Close the window to stop."):format(Short(sender), ns.Num(f.max)))
        UI("FFAUpdate")
        return
    end
    local f = S.watch and S.watch.ffa
    if not f or parts[2] ~= f.id then return end
    if cmd == "WFS" then
        f.phase = parts[3]
        f.expires = GetTime() + (tonumber(parts[4]) or 0)
        f.total = f.phase == "join" and ns.FFA_JOIN_TIME or ns.FFA_ROLL_TIME
        f.max = tonumber(parts[5]) or f.max
    elseif cmd == "WFP" then
        local name = parts[3]
        local p = FFAPlayer(f, name)
        if not p then p = { name = name }; f.players[#f.players + 1] = p end
        p.roll, p.reroll = tonumber(parts[4]), tonumber(parts[5])
        p.tie = parts[6] ~= "" and parts[6] or nil
        p.host = parts[7] == "1"
    elseif cmd == "WFL" then
        local _, i = FFAPlayer(f, parts[3])
        if i then table.remove(f.players, i) end
    elseif cmd == "WFE" then
        f.phase = "done"
        f.highRoll, f.lowRoll = tonumber(parts[5]), tonumber(parts[6])
        if parts[3] ~= "" then
            f.result = { winner = parts[3], payer = parts[4], amount = tonumber(parts[7]) or 0 }
            Print(("%s's Free For All: %s owes %s %sg."):format(Short(sender), Short(parts[4]), Short(parts[3]), ns.Num(f.result.amount)))
        else
            f.result = { none = true, allTied = parts[8] == "tied" }
        end
    elseif cmd == "WFX" then
        if f.phase ~= "done" then
            f.phase, f.result = "done", { none = true, calledOff = true }
            Print(("%s's Free For All was called off."):format(Short(sender)))
        end
    end
    UI("FFAUpdate")
end

---------------------------------------------------------------------------
-- Live games from your guild and group
---------------------------------------------------------------------------

local live = {}            -- gid -> { kind, server, p1, p2, host, wager, max, count, phase, t }
ns.liveGames = live

function ns.LiveGames()
    local list = {}
    for gid, e in pairs(live) do
        if GetTime() - e.t > ns.LIVE_LIFETIME then live[gid] = nil else list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

local function OnLive(parts, sender)
    if parts[1] == "LIVEX" then
        if live[parts[2]] then live[parts[2]] = nil; UI("RefreshStats") end
        return
    end
    local kind, gid = parts[2], parts[3]
    if not gid then return end
    local e = live[gid] or {}
    e.gid, e.server, e.t = gid, sender, GetTime()
    if kind == "d" then
        e.kind, e.p1, e.p2, e.wager, e.max = "duel", parts[4], parts[5], tonumber(parts[6]) or 0, tonumber(parts[7]) or 0
    elseif kind == "f" then
        e.kind, e.host, e.max, e.count, e.phase = "ffa", parts[4], tonumber(parts[5]) or 0, tonumber(parts[6]) or 0, parts[7]
    else
        return
    end
    live[gid] = e
    UI("RefreshStats")
end

---------------------------------------------------------------------------
-- Messages in
---------------------------------------------------------------------------

function ns.Spec_OnAddon(text, sender)
    local parts = { strsplit("|", text) }
    local cmd = parts[1]
    if cmd == "LIVE" or cmd == "LIVEX" then OnLive(parts, sender); return end
    if cmd == "WREQ" then OnWatchRequest(sender, parts[2]); return end
    if cmd == "WSTOP" then OnWatchStop(sender); return end

    -- answers to our request
    if cmd == "WNO" or cmd == "WOD" or cmd == "WOF" then
        if not (pending and pending.req == parts[2] and ns.SameName(pending.server, sender)) then return end
        pending = nil
        if cmd == "WNO" then
            local why = parts[3]
            Print(why == "off" and ("%s doesn't allow spectators."):format(Short(sender))
                or why == "full" and ("%s's game already has %d spectators."):format(Short(sender), ns.SPEC_MAX)
                or ("%s isn't in a game right now."):format(Short(sender)))
        elseif cmd == "WOD" then
            OnDuelSnapshot(sender, parts)
        else
            OnFFAMessage(cmd, parts, sender)
        end
        return
    end

    -- updates for what we're watching
    local w = S.watch
    if not (w and ns.SameName(w.server, sender)) then return end
    if w.kind == "duel" and parts[2] == w.gid then OnDuelUpdate(cmd, parts)
    elseif w.kind == "ffa" then OnFFAMessage(cmd, parts, sender) end
end

-- Chat filter: hold back roll lines of the game you're watching until the dice land.
function ns.IsWatchedRollLine(msg)
    local w = S.watch
    local g = w and w.game
    if not g or (g.state ~= "active" and g.state ~= "ending") then return false end
    local who, roll, lo, hi = ns.ParseRoll(msg)
    if not who or lo ~= 1 then return false end
    if not (ns.SameName(who, g.left) or ns.SameName(who, g.opponent)) then return false end
    if hi == g.max and ns.SameName(who, g.turn) then return true end
    for i = #g.rolls, math.max(1, #g.rolls - 1), -1 do
        local r = g.rolls[i]
        if ns.SameName(r.who, who) and r.roll == roll and r.max == hi and GetTime() - r.t < 10 then return true end
    end
    return false
end
