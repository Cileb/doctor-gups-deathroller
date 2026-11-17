-- Free For All: one host, any number of players, add-on or not.
--
--   1. The host starts it ("1-150"). Their character emotes it; anyone nearby
--      types 1 in chat to join (-1 to leave). The host is always in.
--   2. The host calls for rolls (or the join timer runs out). Everyone in types
--      /roll 150. Only each player's first roll in the right range counts.
--   3. When everyone has rolled (or time is up, or the host closes it), the
--      lowest roller pays the highest roller the difference between the two rolls.
--      Ties for highest or lowest: just the tied players roll again to decide who;
--      the amount still uses the original rolls.
--
-- Only the host's add-on runs the game: it reads "1" from chat and rolls from the
-- system messages, so nobody else needs the add-on. Players who do have it are
-- told (hidden add-on whispers, which players without it never see) when they're
-- in, out, and the result, so it lands in their stats too. Stats, history and
-- debts are recorded for whoever is the winner or the payer, host or not:
--   FFAJ|id|max      you're in        FFAC|id       roll now
--   FFAX|id          you're out / it's off
--   FFAR|id|max|players|winner|payer|high|low|amount   the result

local ADDON_NAME, ns = ...
local S = ns.state

ns.FFA_JOIN_TIME = 60      -- seconds to type 1
ns.FFA_ROLL_TIME = 60      -- seconds to roll (and for each tie-break)
ns.FFA_MIN_MAX   = 2

local function UI(name, ...)
    local fn = ns.UI[name]
    if fn then return fn(...) end
end

local function Print(...) return ns.Print(...) end
local function Short(n) return ns.Short(n) end
local function FirstName(n) return ns.FirstName(n) end
local function Num(n) return ns.Num(n) end

-- Quietly tell a player's add-on (if they have one) what's going on.
local function Notify(name, ...)
    if not name or ns.SameName(name, S.me) then return end
    local msg = table.concat({ ... }, "|")
    ns.Debug(("-> %s : %s"):format(name, msg))
    pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, "WHISPER", name)
end

local function NotifyAll(f, ...)
    for _, p in ipairs(f.players) do Notify(p.name, ...) end
end

function ns.FFA_IsActive()
    local f = S.ffa
    return f ~= nil and f.phase ~= "done"
end

local function Find(f, name)
    for i, p in ipairs(f.players) do
        if ns.SameName(p.name, name) then return p, i end
    end
end

-- "Doctor, Zed and Amy" (first names), or "5 players" when the list gets long.
local function NameList(list)
    if #list > 6 then return ("%d players"):format(#list) end
    local names = {}
    for i, p in ipairs(list) do names[i] = FirstName(p.name) end
    if #names == 1 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Each phase gets a number, so an old timer can tell it's been overtaken.
local function StartTimer(f, seconds, fn)
    f.round = (f.round or 0) + 1
    local round = f.round
    f.expires = GetTime() + seconds
    f.total = seconds
    C_Timer.After(seconds, function()
        if S.ffa == f and f.round == round then fn() end
    end)
end

---------------------------------------------------------------------------
-- Starting and joining
---------------------------------------------------------------------------

function ns.FFA_Start(max)
    max = math.floor(tonumber(max) or 0)
    if max < ns.FFA_MIN_MAX then Print("Pick a roll of 2 or more, like /dr ffa 150."); return end
    if max > ns.MAX_WAGER then max = ns.MAX_WAGER end
    if ns.FFA_IsActive() then Print("A Free For All is already running."); return end
    if S.game and S.game.state ~= "done" then
        Print("You're in a deathroll. Finish it or /dr forfeit first.")
        return
    end
    local ok, why = ns.Emote(("starts a Free For All deathroll, 1-%s! Lowest roll pays the highest the difference in gold. Type 1 in chat to join."):format(Num(max)))
    if not ok and why == "combat" then Print("Couldn't start it: you're in combat."); return end

    local f = { id = ns.NewId and ns.NewId() or tostring(time()), max = max, phase = "join", players = {} }
    f.players[1] = { name = S.me, host = true }
    S.ffa = f
    if ok then
        Print(("Free For All 1-%s started. Players type 1 in chat to join (-1 to leave). You have %d seconds, or click Start rolling."):format(
            Num(max), ns.FFA_JOIN_TIME))
    else
        Print(("WoW wouldn't let the add-on post it, so tell people yourself, for example in /say: \"Free For All 1-%s, type 1 to join!\""):format(Num(max)))
    end
    StartTimer(f, ns.FFA_JOIN_TIME, function() ns.FFA_StartRolling(true) end)
    UI("FFAUpdate")
end

-- Chat from other players: "1" joins, "-1" leaves (join phase only).
function ns.FFA_OnChat(msg, author)
    local f = S.ffa
    if not f or f.phase ~= "join" then return end
    if not msg or not author or ns.IsSecret(msg) or ns.IsSecret(author) then return end
    local name = ns.FullName(author)
    if not name then return end
    local text = strtrim(msg)
    if text == "1" then
        if Find(f, name) then return end
        f.players[#f.players + 1] = { name = name }
        Notify(name, "FFAJ", f.id, f.max)
        Print(("%s joined (%d players)."):format(Short(name), #f.players))
        ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        UI("FFAUpdate")
    elseif text == "-1" then
        local p, i = Find(f, name)
        if p and not p.host then
            table.remove(f.players, i)
            Notify(name, "FFAX", f.id)
            Print(("%s left (%d players)."):format(Short(name), #f.players))
            UI("FFAUpdate")
        end
    end
end

---------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------

local Finish, StartTieBreak

-- auto = the join timer ran out (no key press, so the emote waits for Enter).
function ns.FFA_StartRolling(auto)
    local f = S.ffa
    if not f or f.phase ~= "join" then return end
    if #f.players < 2 then
        Print(auto and "Nobody joined your Free For All, so it's off." or "You need at least one other player first.")
        if auto then
            NotifyAll(f, "FFAX", f.id)
            ns.Emote("calls off the Free For All: nobody joined.", nil, true)
            S.ffa = nil
            UI("FFAUpdate")
        end
        return
    end
    f.phase = "roll"
    NotifyAll(f, "FFAC", f.id)
    ns.Emote(("calls for rolls! %s: /roll %d now."):format(NameList(f.players), f.max))
    Print(("Rolling! Everyone in types /roll %d. You too."):format(f.max))
    StartTimer(f, ns.FFA_ROLL_TIME, function() Finish(true) end)
    UI("FFAUpdate")
end

-- A roll seen in chat (from Core's system-message handler).
function ns.FFA_OnRoll(who, roll, lo, hi)
    local f = S.ffa
    if not f or (f.phase ~= "roll" and f.phase ~= "tie") then return end
    if lo ~= 1 or hi ~= f.max then return end
    local p = Find(f, who)
    if not p then return end
    if f.phase == "roll" then
        if p.roll then return end                              -- first roll counts
        p.roll = roll
        UI("FFAUpdate")
        for _, q in ipairs(f.players) do if not q.roll then return end end
        Finish(false)                                         -- everyone's in
    else
        if not p.tie or p.reroll then return end
        p.reroll = roll
        UI("FFAUpdate")
        for _, q in ipairs(f.players) do if q.tie and not q.reroll then return end end
        Finish(false)
    end
end

-- Host's "Close rolls": stop waiting for anyone who hasn't rolled.
function ns.FFA_CloseRolls()
    local f = S.ffa
    if f and (f.phase == "roll" or f.phase == "tie") then Finish(true) end
end

-- Pick one player from a tied group by their re-rolls. Returns the player, or a
-- smaller tied group. Missing re-rolls on a timeout: in a top tie you drop out;
-- in a bottom tie you're taken as the lowest (the first such player pays).
local function Decide(group, wantHigh, timedOut)
    local rolled, missing = {}, {}
    for _, p in ipairs(group) do
        if p.reroll then rolled[#rolled + 1] = p else missing[#missing + 1] = p end
    end
    if not wantHigh and #missing > 0 then return missing[1] end
    if #rolled == 0 then return group[1] end                    -- nobody re-rolled at all
    local best = rolled[1].reroll
    for _, p in ipairs(rolled) do
        if (wantHigh and p.reroll > best) or (not wantHigh and p.reroll < best) then best = p.reroll end
    end
    local top = {}
    for _, p in ipairs(rolled) do if p.reroll == best then top[#top + 1] = p end end
    if #top == 1 then return top[1] end
    return nil, top
end

Finish = function(timedOut)
    local f = S.ffa
    if not f then return end

    if f.phase == "roll" then
        local rolled = {}
        for _, p in ipairs(f.players) do if p.roll then rolled[#rolled + 1] = p end end
        if #rolled < 2 then
            Print("Not enough players rolled, so there's no result.")
            ns.Emote("calls off the Free For All: not enough rolls.", nil, true)
            NotifyAll(f, "FFAX", f.id)
            f.phase, f.result = "done", { none = true }
            UI("FFAUpdate")
            return
        end
        local hi, lo = rolled[1].roll, rolled[1].roll
        for _, p in ipairs(rolled) do hi = math.max(hi, p.roll); lo = math.min(lo, p.roll) end
        f.highRoll, f.lowRoll = hi, lo
        if hi == lo then
            f.phase, f.result = "done", { none = true, allTied = true }
            NotifyAll(f, "FFAR", f.id, f.max, #f.players, "", "", hi, lo, 0)
            Print(("Everyone rolled %d. Nobody owes anything."):format(hi))
            ns.Emote(("Free For All: everyone rolled %d, so nobody owes anything!"):format(hi))
            UI("FFAUpdate")
            return
        end
        local top, bottom = {}, {}
        for _, p in ipairs(rolled) do
            if p.roll == hi then top[#top + 1] = p end
            if p.roll == lo then bottom[#bottom + 1] = p end
        end
        f.winner = (#top == 1) and top[1] or nil
        f.payer = (#bottom == 1) and bottom[1] or nil
        if f.winner and f.payer then
            ns.FFA_Resolve()
        else
            StartTieBreak(not f.winner and top or nil, not f.payer and bottom or nil)
        end
        return
    end

    -- tie-break round finished
    local topGroup, bottomGroup = {}, {}
    for _, p in ipairs(f.players) do
        if p.tie == "high" then topGroup[#topGroup + 1] = p end
        if p.tie == "low" then bottomGroup[#bottomGroup + 1] = p end
    end
    local againTop, againBottom
    if #topGroup > 0 then f.winner, againTop = Decide(topGroup, true, timedOut) end
    if #bottomGroup > 0 then f.payer, againBottom = Decide(bottomGroup, false, timedOut) end
    if f.winner and f.payer then
        ns.FFA_Resolve()
    else
        StartTieBreak(againTop, againBottom)
    end
end

StartTieBreak = function(top, bottom)
    local f = S.ffa
    for _, p in ipairs(f.players) do p.tie, p.reroll = nil, nil end
    local all = {}
    for _, p in ipairs(top or {}) do p.tie = "high"; all[#all + 1] = p end
    for _, p in ipairs(bottom or {}) do p.tie = "low"; all[#all + 1] = p end
    f.phase = "tie"
    local what = top and bottom and "highest and lowest" or (top and "highest" or "lowest")
    ns.Emote(("Tie for %s! %s: /roll %d again."):format(what, NameList(all), f.max))
    Print(("Tie for %s. %s roll again: /roll %d."):format(what, NameList(all), f.max))
    StartTimer(f, ns.FFA_ROLL_TIME, function() Finish(true) end)
    UI("FFAUpdate")
end

---------------------------------------------------------------------------
-- Result
---------------------------------------------------------------------------

-- info: { max, players (count), highRoll, lowRoll }
local function Record(info, won, other, amount)
    local DB = ns.GetDB()
    local s = DB.stats
    local o = DB.opponents[other] or { w = 0, l = 0, net = 0 }
    DB.opponents[other] = o
    if won then
        s.wins = s.wins + 1; o.w = o.w + 1
        s.goldWon = s.goldWon + amount; o.net = o.net + amount
        s.streak = math.max(s.streak, 0) + 1
        s.bestStreak = math.max(s.bestStreak, s.streak)
        s.biggestWin = math.max(s.biggestWin, amount)
    else
        s.losses = s.losses + 1; o.l = o.l + 1
        s.goldLost = s.goldLost + amount; o.net = o.net - amount
        s.streak = math.min(s.streak, 0) - 1
    end
    o.last = time()
    table.insert(DB.history, 1, {
        t = time(), opp = other, won = won, wager = amount, start = info.max,
        mode = "ffa", players = info.players, myRoll = won and info.highRoll or info.lowRoll,
        theirRoll = won and info.lowRoll or info.highRoll,
    })
    while #DB.history > ns.HISTORY_SIZE do table.remove(DB.history) end
    if amount > 0 then ns.AdjustDebt(other, won and amount or -amount, true) end
end

function ns.FFA_Resolve()
    local f = S.ffa
    local w, p = f.winner, f.payer
    local amount = f.highRoll - f.lowRoll
    f.phase = "done"
    f.result = { winner = w.name, payer = p.name, amount = amount }
    for _, q in ipairs(f.players) do q.tie = nil end

    NotifyAll(f, "FFAR", f.id, f.max, #f.players, w.name, p.name, f.highRoll, f.lowRoll, amount)
    local info = { max = f.max, players = #f.players, highRoll = f.highRoll, lowRoll = f.lowRoll }
    ns.Emote(("Free For All result: %s rolled %d (highest), %s rolled %d (lowest). %s owes %s %sg!"):format(
        Short(w.name), f.highRoll, Short(p.name), f.lowRoll, FirstName(p.name), FirstName(w.name), Num(amount)))
    if ns.SameName(w.name, S.me) then
        Record(info, true, p.name, amount)
        Print(("You win! %s owes you %sg."):format(Short(p.name), Num(amount)))
        ns.Sound("LOOT_WINDOW_COIN_SOUND")
    elseif ns.SameName(p.name, S.me) then
        Record(info, false, w.name, amount)
        Print(("You rolled lowest: you owe %s %sg."):format(Short(w.name), Num(amount)))
    else
        Print(("%s owes %s %sg."):format(Short(p.name), Short(w.name), Num(amount)))
    end
    UI("FFAUpdate")
    UI("RefreshStats")
end

function ns.FFA_Cancel()
    local f = S.ffa
    if not f then return end
    if f.phase ~= "done" then
        NotifyAll(f, "FFAX", f.id)
        ns.Emote("calls off the Free For All.", nil, true)
        Print("Free For All cancelled.")
    end
    S.ffa = nil
    UI("FFAUpdate")
end

-- Close the window after a finished game (or abandon one).
function ns.FFA_Clear()
    if S.ffa and S.ffa.phase == "done" then S.ffa = nil end
end

---------------------------------------------------------------------------
-- Playing in someone else's Free For All (when you have the add-on too)
---------------------------------------------------------------------------

-- id -> { host, max, t, myRoll }; kept a few minutes at most
local joined = {}
ns.ffaJoined = joined
local JOINED_LIFETIME = 600

local function Prune()
    for id, j in pairs(joined) do
        if time() - j.t > JOINED_LIFETIME then joined[id] = nil end
    end
end

function ns.FFA_IsPlaying()
    Prune()
    return next(joined) ~= nil
end

-- Your own rolls, so a reported result can be checked against what you rolled.
function ns.FFA_OnMyRoll(roll, lo, hi)
    for _, j in pairs(joined) do
        if lo == 1 and hi == j.max and not j.myRoll and j.calling then j.myRoll = roll end
    end
end

function ns.FFA_OnAddon(text, sender)
    local parts = { strsplit("|", text) }
    local cmd, id = parts[1], parts[2]
    if not id then return end
    local host = ns.FullName(sender)
    if cmd == "FFAJ" then
        local max = tonumber(parts[3])
        if not max then return end
        joined[id] = { host = host, max = max, t = time() }
        Print(("You're in %s's Free For All (1-%s). When they call for rolls, type /roll %d."):format(
            Short(host), Num(max), max))
        ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    elseif cmd == "FFAC" then
        local j = joined[id]
        if j and ns.SameName(j.host, host) then
            j.calling = true                                   -- your next roll in range is the one that counts
            Print(("%s called for rolls: type /roll %d now!"):format(Short(host), j.max))
            ns.Sound("READY_CHECK")
        end
    elseif cmd == "FFAX" then
        local j = joined[id]
        if j and ns.SameName(j.host, host) then
            joined[id] = nil
            Print(("You're out of %s's Free For All."):format(Short(host)))
        end
    elseif cmd == "FFAR" then
        local j = joined[id]
        if not (j and ns.SameName(j.host, host)) then return end
        joined[id] = nil
        local max, count = tonumber(parts[3]), tonumber(parts[4])
        local winner, payer = parts[5], parts[6]
        local high, low, amount = tonumber(parts[7]), tonumber(parts[8]), tonumber(parts[9])
        if not (max and high and low and amount) then return end
        if amount <= 0 or winner == "" then
            Print(("%s's Free For All: everyone rolled the same, so nobody owes anything."):format(Short(host)))
            return
        end
        local info = { max = max, players = count or 0, highRoll = high, lowRoll = low }
        local iWon, iPay = ns.SameName(winner, S.me), ns.SameName(payer, S.me)
        -- if we saw our own roll, it has to match what the host says
        if (iWon and j.myRoll and j.myRoll ~= high) or (iPay and j.myRoll and j.myRoll ~= low) then
            Print(("%s's Free For All result doesn't match your roll (%d), so it wasn't recorded."):format(Short(host), j.myRoll))
            return
        end
        if iWon then
            Record(info, true, payer, amount)
            Print(("You won %s's Free For All! %s owes you %sg."):format(Short(host), Short(payer), Num(amount)))
            ns.Sound("LOOT_WINDOW_COIN_SOUND")
        elseif iPay then
            Record(info, false, winner, amount)
            Print(("You rolled lowest in %s's Free For All: you owe %s %sg."):format(Short(host), Short(winner), Num(amount)))
        else
            Print(("%s's Free For All: %s owes %s %sg. You're in the clear."):format(
                Short(host), Short(payer), Short(winner), Num(amount)))
        end
        UI("RefreshStats")
    end
end
