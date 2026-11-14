-- Two-client simulation of Doctor Gup's Deathroller with a mocked WoW API (Lua 5.3).
-- Run from the repository root:  lua tests/harness.lua .
local ADDON_DIR = arg[1]
local FILES = { "Core.lua", "Widgets.lua", "GameUI.lua", "ChallengeUI.lua", "TradeUI.lua", "StatsUI.lua", "OptionsUI.lua", "Minimap.lua" }

local clock = 100.0
local timers = {}
local clients = {}
local failures = 0
local function check(cond, msg)
    if cond then print("  PASS  " .. msg) else print("  FAIL  " .. msg); failures = failures + 1 end
end

local function After(sec, fn) table.insert(timers, { at = clock + sec, fn = fn }) end

---------------------------------------------------------------- widget mock
local Methods = {}
local WidgetMT = { __index = function(t, k)
    local m = Methods[k]
    if m then return m end
    -- WoW widget methods are CamelCase; addon fields (f.revealing etc.) are lowercase -> nil
    if type(k) == "string" and k:match("^%u") then
        return function() return rawget(t, "_client").NewWidget("auto", t) end
    end
    return nil
end }

function Methods:SetScript(name, fn) self._scripts[name] = fn end
function Methods:GetScript(name) return self._scripts[name] end
function Methods:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Methods:Fire(name, ...) local fn = self._scripts[name]; if fn then return fn(self, ...) end end
function Methods:Show() if not self._shown then self._shown = true; self:Fire("OnShow") end end
function Methods:Hide() if self._shown then self._shown = false; self:Fire("OnHide") end end
function Methods:SetShown(b) if b then self:Show() else self:Hide() end end
function Methods:IsShown() return self._shown end
function Methods:IsVisible()
    local w = self
    while w do if not w._shown then return false end w = w._parent end
    return true
end
function Methods:SetText(t) self._text = t == nil and "" or tostring(t); if self._kind == "EditBox" then self:Fire("OnTextChanged", true) end end
function Methods:GetText() return self._text end
function Methods:Enable() self._enabled = true; self:Fire("OnEnable") end
function Methods:Disable() self._enabled = false; self:Fire("OnDisable") end
function Methods:IsEnabled() return self._enabled end
function Methods:HasFocus() return self._focus or false end
function Methods:SetFocus() self._focus = true; self:Fire("OnEditFocusGained") end
function Methods:ClearFocus() if self._focus then self._focus = false; self:Fire("OnEditFocusLost") end end
function Methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Methods:GetFrameLevel() return 1 end
function Methods:IsOwned() return false end
function Methods:RegisterEvent(e)
    local list = rawget(self, "_client").eventFrames
    for _, f in ipairs(list) do if f == self then return end end
    list[#list + 1] = self
end
function Methods:SetValue(v) self._value = v end
function Methods:GetValue() return self._value end
function Methods:AddMessage(msg) self._client.log("[chat] " .. msg) end
function Methods:Play() end
function Methods:GetWidth() return rawget(self, "_w") or 140 end
function Methods:SetWidth(w) self._w = w end
function Methods:GetCenter() return 500, 500 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetStringHeight() return 24 end
-- rough text metrics so name fitting can be tested: ~0.55 em per character
function Methods:SetFont(_, size) self._fontSize = size; return true end
function Methods:GetUnboundedStringWidth() return self:GetStringWidth() end
function Methods:GetStringWidth()
    local t = (self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #t * (self._fontSize or 12) * 0.55
end
function Methods:SetScale(v) self._scale = v end
function Methods:Stop() end

local function NewClient(fullName, shard)
    local c = { name = fullName, eventFrames = {}, widgets = {}, logs = {}, filters = {} }
    local env = {}
    c.env = env
    function c.log(s) c.logs[#c.logs + 1] = s; print(("    [%s] %s"):format(fullName:match("^%S+"), (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))) end
    function c.NewWidget(kind, parent)
        local w = setmetatable({ _kind = kind, _client = c, _scripts = {}, _text = "", _shown = true,
            _enabled = true, _parent = parent }, WidgetMT)
        c.widgets[#c.widgets + 1] = w
        return w
    end
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.unpack = table.unpack
    env.print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end c.log(table.concat(t, " ")) end
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strsplit = function(sep, s)
        local out = {}
        for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return table.unpack(out)
    end
    env.tinsert = table.insert
    env.time = os.time
    env.date = os.date
    env.GetTime = function() return clock end
    env.C_Timer = { After = After }
    env.UIParent = c.NewWidget("Frame")
    env.GameTooltip = c.NewWidget("GameTooltip")
    env.DEFAULT_CHAT_FRAME = c.NewWidget("ScrollingMessageFrame")
    env.CreateFrame = function(kind, name, parent)
        local w = c.NewWidget(kind, parent)
        if name then env[name] = w end
        return w
    end
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.SOUNDKIT = {}
    env.PlaySound = function() end
    env.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
    env.BreakUpLargeNumbers = function(n) return tostring(n) end
    env.ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 } }
    env.IsInGroup = function() return false end
    env.IsShiftKeyDown = function() return false end
    env.Minimap = c.NewWidget("Minimap")
    env.GetCursorPosition = function() return c.cursor and c.cursor[1] or 0, c.cursor and c.cursor[2] or 0 end
    env.InCombatLockdown = function() return c.inCombat == true end
    env.GetMoney = function() return math.floor((c.gold or 1234) * 10000) end
    env.ERR_TRADE_COMPLETE = "Trade complete."
    env.TradeFrame = c.NewWidget("Frame")
    env.GetPlayerTradeMoney = function() return c.tradeGive or 0 end
    env.GetTargetTradeMoney = function() return c.tradeGet or 0 end
    env.SetTradeMoney = function(copper)
        c.tradeGive = copper
        local p = c.tradePartner
        if p then p.tradeGet = copper; p.fire("TRADE_MONEY_CHANGED") end
        c.fire("TRADE_MONEY_CHANGED")
    end
    env.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "0.9.1" end end }
    env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
        RegisterAddOnCategory = function(cat) c.addonCategory = cat end,
    }
    c.emotes = {}
    env.SendChatMessage = function(msg, chatType)
        c.emotes[#c.emotes + 1] = chatType .. ": " .. msg
        c.log("[" .. chatType .. "] " .. fullName .. " " .. msg)
    end
    env.GetCurrentKeyBoardFocus = function()
        for _, w in ipairs(c.widgets) do if rawget(w, "_focus") then return w end end
    end
    env.ChatEdit_GetActiveWindow = function() return c.chatOpen and c.NewWidget("EditBox") or nil end
    env.issecretvalue = function() return false end
    env.UnitName = function(unit)
        if unit == "player" then return fullName:match("^%S+") end
        if unit == "NPC" and c.tradePartner then return c.tradePartner.name:match("^%S+") end
        if unit == "target" and c.target then return c.target:match("^%S+") end
    end
    env.GetUnitName = function(unit)
        if unit == "player" then return fullName .. "-" .. shard end
        if unit == "NPC" and c.tradePartner then return c.tradePartner.name .. "-CAMWOWUS1REALM7PvE" end
        if unit == "target" and c.target then return c.target .. "-CAMWOWUS1REALM9PvE" end
    end
    env.UnitIsPlayer = function(unit) return unit == "target" and c.target ~= nil end
    env.ChatFrame_AddMessageEventFilter = function(event, fn) c.filters[#c.filters + 1] = fn end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        SendAddonMessage = function(prefix, msg, channel, target)
            local dest
            for _, other in ipairs(clients) do if other.name:lower() == target:lower() then dest = other end end
            if not dest then
                -- the real client reports this with a system message (no quotes, with a realm tag)
                After(0.05, function() c.systemMessage("No player named " .. target .. "-CAMWOWUS1REALM3PvE is currently playing.") end)
                return 0
            end
            After(0.05, function() dest.fire("CHAT_MSG_ADDON", prefix, msg, channel, fullName .. "-" .. shard) end)
            return 0
        end,
    }
    env.RandomRoll = function(lo, hi)
        local r = table.remove(c.forced or {}, 1) or math.random(lo, hi)
        local line = ("%s rolls %d (%d-%d)"):format(fullName, r, lo, hi)
        After(0.05, function() for _, cl in ipairs(clients) do cl.systemMessage(line) end end)
    end

    function c.fire(event, ...)
        for _, f in ipairs(c.eventFrames) do f:Fire("OnEvent", event, ...) end
    end
    -- Chat frames and our event handler may run in either order; alternate to test both.
    c.order = 0
    function c.systemMessage(line)
        c.order = c.order + 1
        local function chat()
            local hidden = false
            for _, fn in ipairs(c.filters) do if fn(nil, "CHAT_MSG_SYSTEM", line) then hidden = true end end
            c.log((hidden and "[chat HIDDEN] " or "[chat] ") .. line)
        end
        if c.order % 2 == 0 then chat(); c.fire("CHAT_MSG_SYSTEM", line) else c.fire("CHAT_MSG_SYSTEM", line); chat() end
    end

    c.ns = {}
    for _, file in ipairs(FILES) do
        local chunk, err = loadfile(ADDON_DIR .. "/" .. file, "t", env)
        assert(chunk, err)
        chunk("DoctorGupsDeathroller", c.ns)
    end
    clients[#clients + 1] = c
    return c
end

local function Tick(seconds)
    local stop = clock + seconds
    while clock < stop do
        clock = clock + 0.05
        table.sort(timers, function(a, b) return a.at < b.at end)
        while timers[1] and timers[1].at <= clock do table.remove(timers, 1).fn() end
        for _, c in ipairs(clients) do
            for _, w in ipairs(c.widgets) do
                if w._scripts.OnUpdate and w:IsVisible() then w:Fire("OnUpdate", 0.05) end
            end
        end
    end
end

-- Open a trade between a and b. Returns helpers to put gold in and finish.
local function OpenTrade(a, b)
    a.tradePartner, b.tradePartner = b, a
    a.tradeGive, a.tradeGet, b.tradeGive, b.tradeGet = 0, 0, 0, 0
    a.fire("TRADE_SHOW"); b.fire("TRADE_SHOW")
end
local function PutGold(who, gold)
    who.env.SetTradeMoney(gold * 10000)
end
-- completeOn: which clients get the "Trade complete." message (others rely on the gold check)
local function FinishTrade(a, b, completeOn)
    a.fire("TRADE_ACCEPT_UPDATE", 1, 1); b.fire("TRADE_ACCEPT_UPDATE", 1, 1)
    local aNet = (a.tradeGet - a.tradeGive) / 10000
    a.gold = (a.gold or 1234) + aNet
    b.gold = (b.gold or 1234) - aNet
    for _, c in ipairs(completeOn or { a, b }) do c.fire("UI_INFO_MESSAGE", 0, "Trade complete.") end
    a.fire("TRADE_CLOSED"); b.fire("TRADE_CLOSED")
    a.tradePartner, b.tradePartner = nil, nil
    Tick(1.5)
end
local function CancelTrade(a, b)
    a.fire("TRADE_CLOSED"); b.fire("TRADE_CLOSED")
    a.tradePartner, b.tradePartner = nil, nil
    Tick(1.5)
end

local function GoChallenge(c)
    c.env.GupsDeathrollerChallengeFrame.go:Fire("OnClick")
end

local function TypeInBox(c, text)
    local box = c.env.GupsDeathrollerFrame.input
    box:SetFocus()
    box:SetText(text)
    box:Fire("OnEnterPressed")
end

local function PlayOut(a, b)
    -- whoever's turn it is types the right command until the game ends
    for _ = 1, 30 do
        local done = true
        for _, c in ipairs({ a, b }) do
            local g = c.env.GupsDeathrollerFrame and c.ns.state.game
            if g and g.state ~= "done" then done = false end
            if c.ns.IsMyTurn() and not c.env.GupsDeathrollerFrame.revealing then
                TypeInBox(c, "/roll " .. c.ns.state.game.max)
            end
        end
        Tick(1)
        if done then break end
    end
    Tick(6)
end

---------------------------------------------------------------- scenario
local ok, err = xpcall(function()
    print("== setup")
    local A = NewClient("Doctor Gup", "CAMWOWUS1REALM3PvE")
    local B = NewClient("Meudayr Darkpaw", "CAMWOWUS1REALM5PvE")
    for _, c in ipairs(clients) do c.fire("ADDON_LOADED", "DoctorGupsDeathroller"); c.fire("PLAYER_LOGIN") end
    check(A.ns.state.me == "Doctor Gup", "own name uses first + last name")
    -- existing scenarios assume the challenger rolls first; the coin flip has its own section below
    local realFlipA, realFlipB = A.ns.CoinFlip, B.ns.CoinFlip
    A.ns.CoinFlip = function() return false end
    B.ns.CoinFlip = function() return false end

    print("== challenge by target, accept")
    A.target = "Meudayr Darkpaw"
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge 5"); GoChallenge(A)
    check(A.ns.state.game and A.ns.state.game.opponent == "Meudayr Darkpaw", "target challenge uses full name")
    Tick(0.2)
    check(B.ns.state.invite ~= nil and B.env.GupsDeathrollerInviteFrame:IsShown(), "opponent sees challenge popup")
    Tick(20)
    local bar = B.env.GupsDeathrollerInviteFrame.bar
    check(bar._value and bar._value < 41 and bar._value > 39, "popup countdown bar is draining (" .. tostring(bar._value) .. "s left)")
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick")
    Tick(0.2)
    check(A.ns.state.game.state == "active", "challenger sees the accept")
    check(B.ns.state.game.state == "active", "opponent game active")

    print("== roll box only accepts /roll N")
    A.forced = { 60 }
    TypeInBox(A, "72"); Tick(0.2)
    check(#A.ns.state.game.rolls == 0, "'72' does not roll")
    TypeInBox(A, "roll 100"); Tick(0.2)
    check(#A.ns.state.game.rolls == 0, "'roll 100' does not roll")
    TypeInBox(A, "/roll 50"); Tick(0.2)
    check(#A.ns.state.game.rolls == 0, "wrong number does not roll")
    TypeInBox(B, "/roll 100"); Tick(0.2)
    check(#B.ns.state.game.rolls == 0, "not-your-turn does not roll")
    TypeInBox(A, "/ROLL 100"); Tick(0.2)
    check(#A.ns.state.game.rolls == 1 and #B.ns.state.game.rolls == 1, "'/ROLL 100' rolls, both clients see it")
    check(A.env.GupsDeathrollerFrame.revealing and B.env.GupsDeathrollerFrame.revealing, "both windows play the dice reveal")
    Tick(5)
    check(A.ns.state.game.rolls[1].revealed, "reveal finished")
    check(B.ns.IsMyTurn(), "turn passes to opponent")

    print("== play to the end (forced rolls)")
    B.forced = { 20, 1 }
    A.forced = { 5 }
    PlayOut(A, B)
    check(A.ns.state.game.state == "done" and B.ns.state.game.state == "done", "game finished on both")
    check(A.ns.state.game.won == true and B.ns.state.game.won == false, "Meudayr rolled the 1: Doctor wins")
    local hA = A.ns.GetDB().history[1]
    check(hA and hA.seq == "m60,o20,m5,o1" and hA.wager == 5, "history records roll sequence and wager (" .. tostring(hA and hA.seq) .. ")")
    check(A.ns.GetDB().stats.streak == 1 and B.ns.GetDB().stats.streak == -1, "streaks recorded")

    print("== rematch then forfeit")
    A.env.GupsDeathrollerFrame.rematch:Fire("OnClick")
    Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick")
    Tick(0.2)
    A.env.GupsDeathrollerFrame.forfeit:Fire("OnClick")
    Tick(0.3)
    check(A.ns.state.game.state == "done" and A.ns.state.game.won == false, "forfeit recorded as a loss")
    check(B.ns.state.game.won == true, "opponent gets the forfeit win")

    print("== decline and timeout")
    A.env.GupsDeathrollerFrame:Hide()                 -- closing clears the finished game
    B.env.GupsDeathrollerFrame:Hide()
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge meudayr darkpaw"); GoChallenge(A)
    Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.decline:Fire("OnClick")
    Tick(0.2)
    check(A.ns.state.game == nil, "decline clears the challenge")
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw 10"); GoChallenge(A)
    Tick(61)
    check(B.ns.state.invite == nil and not B.env.GupsDeathrollerInviteFrame:IsShown(), "invite times out and closes")
    check(A.ns.state.game == nil, "challenger's pending game times out")

    print("== stats window")
    for i = 1, 30 do   -- pad history to test scrolling and filters
        table.insert(A.ns.GetDB().history, { t = os.time() - i * 3 * 86400, opp = i % 3 == 0 and "Vember Darkpaw" or "Meudayr Darkpaw",
            won = i % 2 == 0, wager = i, start = 100, rolls = 4, seq = "m50,o10,m1" })
    end
    A.ns.GetDB().opponents["Vember Darkpaw"] = { w = 5, l = 5, net = -20, last = os.time() }
    A.env.SlashCmdList.GUPSDEATHROLLER("stats")
    local SF = A.env.GupsDeathrollerStatsFrame
    check(SF:IsShown(), "stats window opens")
    check(SF.overview.list.data[1] ~= nil, "overview lists opponents")
    check(SF.overview.record.value:GetText():find("1") ~= nil, "record card filled")
    SF.overview.list.rows[1]:Fire("OnClick")
    check(SF.history:IsShown() and SF.tabs.value == "history", "clicking an opponent opens History")
    local filtered = #SF.history.list.data
    SF.search:SetText("")
    local all = #SF.history.list.data
    check(all == #A.ns.GetDB().history, "history shows every game (" .. all .. ")")
    check(filtered < all, "search filters by opponent (" .. filtered .. " of " .. all .. ")")
    SF.history.result.buttons[2]:Fire("OnClick")
    local wins = #SF.history.list.data
    SF.history.period.buttons[3]:Fire("OnClick")
    local wins7d = #SF.history.list.data
    check(wins < all and wins7d < wins, ("result and period filters narrow the list (%d wins, %d in 7d)"):format(wins, wins7d))
    SF.history.clear:Fire("OnClick")
    check(#SF.history.list.data == all, "clear filters restores the list")
    local list = SF.history.list
    list:Fire("OnMouseWheel", -1)
    check(list.offset == 3, "mouse wheel scrolls the history")
    list.rows[1]:Fire("OnEnter")
    list.rows[1]:Fire("OnLeave")
    SF.reset:Fire("OnClick"); SF.reset:Fire("OnClick")
    check(#A.ns.GetDB().history == 0 and A.ns.GetDB().stats.wins == 0, "reset (two clicks) clears stats")
    A.env.SlashCmdList.GUPSDEATHROLLER("stats")
    check(not SF:IsShown(), "/dr stats toggles the window closed")

    print("== options window")
    A.env.SlashCmdList.GUPSDEATHROLLER("options")
    local OF = A.env.GupsDeathrollerOptionsFrame
    check(OF and OF:IsShown(), "/dr options opens the options window")
    local function Ctl(c, key) return c.ns.UI and c.env.GupsDeathrollerOptionsFrame and nil end
    -- find checkboxes by label text
    local function FindCheck(c, label)
        for _, w in ipairs(c.widgets) do
            if rawget(w, "label") and rawget(w, "mark") and rawget(w, "label")._text == label then return w end
        end
    end
    local af = FindCheck(A, "Auto-focus the roll box")
    check(af and af.checked == false, "auto-focus is off by default")

    print("== auto-focus and pre-fill")
    -- B starts a game; A will be second to roll
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    B.env.SlashCmdList.GUPSDEATHROLLER("challenge Doctor Gup"); GoChallenge(B)
    Tick(0.2)
    A.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick")
    Tick(0.2)
    B.forced = { 80, 30 }
    A.forced = { 50, 10 }
    TypeInBox(B, "/roll 100"); Tick(5)
    check(A.ns.IsMyTurn() and not A.env.GupsDeathrollerFrame.input:HasFocus(), "without the option, the box isn't focused on your turn")
    af:Fire("OnClick")
    check(A.ns.Setting("autoFocus") == true, "ticking the box turns auto-focus on")
    check(A.env.GupsDeathrollerFrame.input:HasFocus(), "turning it on mid-turn focuses the box right away")
    A.env.GupsDeathrollerFrame.input:ClearFocus()
    TypeInBox(A, "/roll 80"); Tick(0.2)
    A.env.GupsDeathrollerFrame.input:ClearFocus()
    Tick(5)
    TypeInBox(B, "/roll 50"); Tick(5)
    check(A.ns.IsMyTurn() and A.env.GupsDeathrollerFrame.input:HasFocus(), "auto-focus grabs the box when your turn starts")
    local prefill = FindCheck(A, "Pre-fill \"/roll \"")
    prefill:Fire("OnClick")
    check(A.env.GupsDeathrollerFrame.input:GetText() == "/roll ", "pre-fill puts /roll in the box")
    A.env.GupsDeathrollerFrame.input:SetText(A.env.GupsDeathrollerFrame.input:GetText() .. "30")
    A.env.GupsDeathrollerFrame.input:Fire("OnEnterPressed")
    Tick(5)
    check(#A.ns.state.game.rolls == 4, "pre-filled box + number rolls")
    -- chat open on A's next turn: auto-focus must not steal it
    A.chatOpen = true
    B.forced = { 7 }
    TypeInBox(B, "/roll 10"); Tick(5)
    check(A.ns.IsMyTurn() and not A.env.GupsDeathrollerFrame.input:HasFocus(), "auto-focus skips the turn while you're typing in chat")
    check(A.env.GupsDeathrollerFrame.input:GetText() == "/roll ", "pre-fill still happens without focus")
    A.chatOpen = false

    print("== reveal is always on")
    check(FindCheck(A, "Dice animation") == nil, "no reveal options in the options window")
    A.ns.GetDB().settings.animation = false          -- e.g. saved by v0.6.0
    A.ns.GetDB().settings.hideRollChat = false
    check(A.ns.Setting("animation") == true and A.ns.Setting("hideRollChat") == true, "old saved reveal settings are ignored")
    local before = #A.logs
    A.forced = { 1 }
    A.env.GupsDeathrollerFrame.input:SetText("/roll 7")
    A.env.GupsDeathrollerFrame.input:Fire("OnEnterPressed")
    Tick(0.5)
    check(A.env.GupsDeathrollerFrame.revealing, "the roll still gets the dice reveal")
    Tick(5)
    local hidden = false
    for i = before + 1, #A.logs do if A.logs[i]:find("HIDDEN%] Doctor Gup rolls 1") then hidden = true end end
    check(hidden and A.ns.state.game.state == "done", "roll line held back from chat, game ends after the reveal")

    print("== window size, minimap, defaults")
    local scaleSeg
    for _, w in ipairs(A.widgets) do
        if rawget(w, "buttons") and w.buttons[4] and w.buttons[4].value == 1.3 then scaleSeg = w end
    end
    scaleSeg.buttons[4]:Fire("OnClick")
    check(A.ns.Setting("scale") == 1.3 and A.env.GupsDeathrollerFrame._scale == 1.3 and OF._scale == 1.3, "window size applies to open windows")
    local mm = A.env.GupsDeathrollerMinimapButton
    check(mm and mm:IsShown(), "minimap button shown by default")
    A.cursor = { 600, 500 }
    mm:Fire("OnDragStart"); mm:Fire("OnUpdate"); mm:Fire("OnDragStop")
    check(math.abs(A.ns.Setting("minimapAngle") - 0) < 0.01, "dragging moves the minimap button (angle " .. A.ns.Setting("minimapAngle") .. ")")
    FindCheck(A, "Show minimap button"):Fire("OnClick")
    check(not mm:IsShown(), "minimap button can be hidden from options")
    A.env.SlashCmdList.GUPSDEATHROLLER("minimap")
    check(mm:IsShown(), "/dr minimap brings it back")
    mm:Fire("OnClick", "RightButton")
    check(not OF:IsShown(), "right-click toggles options")
    mm:Fire("OnClick", "RightButton")
    mm:Fire("OnEnter")
    local restore
    for _, w in ipairs(A.widgets) do if rawget(w, "text") and type(w.text) == "table" and rawget(w.text, "_text") == "Restore defaults" then restore = w end end
    restore:Fire("OnClick")
    check(A.ns.Setting("animation") == true and A.ns.Setting("autoFocus") == false and A.ns.Setting("scale") == 1, "restore defaults")
    check(af.checked == false, "checkboxes refresh after restoring defaults")
    A.env.DoctorGupsDeathroller_OnCompartmentClick(nil, "LeftButton")

    print("== announcements and milestones")
    A.env.GupsDeathrollerOptionsFrame:Hide()
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.ResetStats(); B.ns.ResetStats()
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw 25"); GoChallenge(A)
    Tick(0.2)
    check(#A.emotes == 0, "no challenge emote by default")
    B.env.GupsDeathrollerInviteFrame.decline:Fire("OnClick"); Tick(0.2)
    A.ns.SetSetting("announceChallenges", true)
    B.ns.SetSetting("announceChallenges", true)
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw 25"); GoChallenge(A)
    Tick(0.2)
    check(A.emotes[1] == "EMOTE: challenges Meudayr Darkpaw to a deathroll for 25g!", "challenge emote: " .. tostring(A.emotes[1]))
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
    check(B.emotes[1] == "EMOTE: accepts Doctor Gup's deathroll challenge for 25g!", "accept emote: " .. tostring(B.emotes[1]))
    A.forced = { 40 }; B.forced = { 1 }
    PlayOut(A, B)
    local AF = A.env.GupsDeathrollerFrame
    check(A.ns.state.game.won and AF.announce:IsShown() and AF.announce:IsEnabled(), "result screen shows an Announce button")
    check(AF.milestones:GetText():find("First deathroll win") ~= nil, "milestone shown: " .. AF.milestones:GetText())
    check(#A.emotes == 1, "nothing announced until you click")
    AF.announce:Fire("OnClick")
    check(A.emotes[2] == "EMOTE: wins a deathroll against Meudayr Darkpaw for 25g in 2 rolls!", "result emote: " .. tostring(A.emotes[2]))
    check(A.emotes[3] == "EMOTE: wins their first ever deathroll!", "milestone emote: " .. tostring(A.emotes[3]))
    check(not AF.announce:IsEnabled() and AF.announce.text._text == "Announced", "button turns into 'Announced'")
    AF.announce:Fire("OnClick")
    check(#A.emotes == 3, "can't announce twice")
    B.env.GupsDeathrollerFrame.announce:Fire("OnClick")
    check(B.emotes[2] == "EMOTE: loses a deathroll to Doctor Gup (25g) after 2 rolls.", "loser's emote: " .. tostring(B.emotes[2]))
    -- rematch inside 20s: challenge emote is throttled
    A.ns.state.game.won = true
    A.env.GupsDeathrollerFrame.rematch:Fire("OnClick"); Tick(0.2)
    check(#A.emotes == 3, "rematch challenge emote is throttled within 20s")
    B.env.GupsDeathrollerInviteFrame.decline:Fire("OnClick"); Tick(0.2)
    -- streak milestone: 3 wins
    for i = 1, 2 do
        Tick(25)
        A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
        A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw"); GoChallenge(A)
        Tick(0.2)
        B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
        A.forced = { 2 }; B.forced = { 1 }
        PlayOut(A, B)
    end
    check(A.env.GupsDeathrollerFrame.milestones:GetText():find("3%-win streak") ~= nil, "3-win streak milestone: " .. A.env.GupsDeathrollerFrame.milestones:GetText())
    A.ns.SetSetting("announceResults", false)
    check(not A.env.GupsDeathrollerFrame.announce:IsShown(), "Announce button hidden when the option is off")
    local found = false
    for _, w in ipairs(A.widgets) do if rawget(w, "label") and rawget(w, "mark") and w.label._text == "Announce challenges" then found = true end end
    check(found, "options window has the Announcements section")

    print("== /dr with a target opens the wager window")
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.target = "Meudayr Darkpaw"
    A.env.SlashCmdList.GUPSDEATHROLLER("")
    local CF = A.env.GupsDeathrollerChallengeFrame
    check(CF:IsShown() and CF.name:GetText() == "Meudayr Darkpaw", "/dr with a target opens the wager window")
    check(CF.input:HasFocus(), "wager box is focused, ready to type")
    check(A.ns.state.game == nil and B.ns.state.invite == nil, "nothing is sent until you confirm")
    CF.presets[4]:Fire("OnClick")
    check(CF.input:GetText() == "100" and CF.pot.amount:GetText() == "100g", "quick pick sets the wager and the pot")
    check(CF.go.text:GetText() == "Challenge for 100g", "button shows the stake: " .. CF.go.text:GetText())
    CF.input:SetText("5000")
    check(CF.funds:GetText():find("You only have 1234g") ~= nil, "warns when you can't cover the wager")
    CF.input:SetText("")
    check(CF.pot.amount:GetText():find("Friendly") ~= nil, "empty wager = friendly game")
    CF.input:SetText("75")
    CF.input:Fire("OnEnterPressed")
    Tick(0.2)
    check(not CF:IsShown() and A.ns.state.game and A.ns.state.game.wager == 75, "Enter sends the challenge for 75g")
    local IF = B.env.GupsDeathrollerInviteFrame
    check(IF:IsShown() and IF.pot.amount:GetText() == "75g", "challenge popup shows the pot big: " .. IF.pot.amount:GetText())
    check(A.env.GupsDeathrollerFrame.pot.amount:GetText() == "75g", "game window shows the pot")
    A.env.SlashCmdList.GUPSDEATHROLLER("")
    check(not CF:IsShown() and A.env.GupsDeathrollerFrame:IsShown(), "/dr during a game shows the game, not a new challenge")
    IF.accept:Fire("OnClick"); Tick(0.2)
    A.forced = { 1 }
    PlayOut(A, B)
    check(A.env.GupsDeathrollerFrame.potLabel:GetText():find("YOU LOSE") ~= nil, "result screen labels the pot")
    A.target = "Doctor Gup"
    A.env.GupsDeathrollerFrame:Hide()
    A.env.SlashCmdList.GUPSDEATHROLLER("")
    check(not CF:IsShown(), "targeting yourself doesn't open a challenge")
    A.target = nil
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge vember darkpaw")
    check(CF:IsShown() and CF.name:GetText() == "Vember Darkpaw", "/dr challenge First Last opens the window for that player")
    CF.cancel:Fire("OnClick")
    check(not CF:IsShown() and A.ns.state.game == nil, "cancel closes without challenging")

    print("== accept announcement follows the challenger")
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.SetSetting("announceChallenges", true)
    B.ns.SetSetting("announceChallenges", false)       -- the opponent never turned it on
    Tick(25)
    local bBefore = #B.emotes
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw 30"); GoChallenge(A)
    Tick(0.2)
    local IF2 = B.env.GupsDeathrollerInviteFrame
    check(IF2.announce.checked == true, "popup's announce box is ticked because the challenger announced")
    IF2.accept:Fire("OnClick"); Tick(0.2)
    check(#B.emotes == bBefore + 1 and B.emotes[#B.emotes] == "EMOTE: accepts Doctor Gup's deathroll challenge for 30g!",
        "opponent's accept is announced even with their own option off")
    A.ns.Forfeit(); Tick(0.3)
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    Tick(25)
    bBefore = #B.emotes
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw 30"); GoChallenge(A)
    Tick(0.2)
    IF2.announce:Fire("OnClick")                        -- they untick it
    IF2.accept:Fire("OnClick"); Tick(0.2)
    check(#B.emotes == bBefore, "unticking the box accepts quietly")
    A.ns.Forfeit(); Tick(0.3)
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.SetSetting("announceChallenges", false)
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw"); GoChallenge(A)
    Tick(0.2)
    check(IF2.announce.checked == false, "box starts unticked when nobody announces")
    IF2.decline:Fire("OnClick"); Tick(0.2)

    print("== version check before challenging")
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    check(A.ns.VERSION == "0.9.1", "version read from the TOC")
    A.target = "Meudayr Darkpaw"
    A.env.SlashCmdList.GUPSDEATHROLLER("")
    local CF3 = A.env.GupsDeathrollerChallengeFrame
    check(CF3.status:GetText():find("Checking") ~= nil and CF3.go:IsEnabled(), "shows 'Checking...' and still lets you send")
    Tick(0.3)
    check(CF3.status:GetText():find("has Deathroller 0.9.1. Ready to roll") ~= nil, "same version: " .. CF3.status:GetText())
    CF3.cancel:Fire("OnClick")

    B.ns.VERSION = "0.9.0"
    A.env.SlashCmdList.GUPSDEATHROLLER(""); Tick(0.3)
    check(CF3.status:GetText():find("0.9.0, you have 0.9.1") ~= nil and CF3.status:GetText():find("they should update") ~= nil
        and CF3.go:IsEnabled(), "older version, same protocol: warning, can still play")
    CF3.cancel:Fire("OnClick")

    B.ns.PROTO = A.ns.PROTO + 1; B.ns.VERSION = "1.0.0"
    Tick(1.1)
    A.env.SlashCmdList.GUPSDEATHROLLER(""); Tick(0.3)
    check(CF3.status:GetText():find("can't play with yours") ~= nil and CF3.status:GetText():find("You need to update") ~= nil
        and not CF3.go:IsEnabled(), "incompatible: blocked (" .. CF3.status:GetText() .. ")")
    CF3.input:Fire("OnEnterPressed")
    check(A.ns.state.game == nil, "Enter can't send a blocked challenge")
    CF3.cancel:Fire("OnClick")
    B.ns.PROTO = A.ns.PROTO; B.ns.VERSION = "0.9.1"

    B.ns.state.invite = { from = "Someone Else" }
    Tick(1.1)
    A.env.SlashCmdList.GUPSDEATHROLLER(""); Tick(0.3)
    check(CF3.status:GetText():find("in another deathroll") ~= nil and not CF3.go:IsEnabled() and CF3.retry:IsShown(), "busy: blocked with Check again")
    B.ns.state.invite = nil
    Tick(1.1)
    CF3.retry:Fire("OnClick"); Tick(0.3)
    check(CF3.status:GetText():find("Ready to roll") ~= nil and CF3.go:IsEnabled(), "Check again updates the status")
    CF3.cancel:Fire("OnClick")

    -- a player with no add-on: messages arrive but nobody answers
    clients[#clients + 1] = { name = "Ghost Player", fire = function() end, systemMessage = function() end, widgets = {} }
    A.target = "Ghost Player"
    A.env.SlashCmdList.GUPSDEATHROLLER(""); Tick(3.2)
    check(CF3.status:GetText():find("No answer from Ghost") ~= nil and CF3.go.text:GetText() == "Challenge anyway"
        and CF3.go:IsEnabled(), "no reply: offers 'Challenge anyway'")
    CF3.cancel:Fire("OnClick")

    A.target = "Nobody Online"
    A.env.SlashCmdList.GUPSDEATHROLLER(""); Tick(0.3)
    check(CF3.status:GetText():find("isn't online") ~= nil and not CF3.go:IsEnabled(), "offline: blocked (" .. CF3.status:GetText() .. ")")
    CF3.cancel:Fire("OnClick")

    print("== forfeit announcements count rolls")
    A.target = "Meudayr Darkpaw"
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.SetSetting("announceResults", true); B.ns.SetSetting("announceResults", true)
    Tick(1)
    A.env.SlashCmdList.GUPSDEATHROLLER(""); GoChallenge(A); Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
    A.forced = { 64 }
    TypeInBox(A, "/roll 100"); Tick(5)
    B.ns.Forfeit(); Tick(0.3)
    A.env.GupsDeathrollerFrame.announce:Fire("OnClick")
    B.env.GupsDeathrollerFrame.announce:Fire("OnClick")
    check(A.emotes[#A.emotes] == "EMOTE: wins a deathroll against Meudayr Darkpaw after 1 roll - Meudayr forfeited.", "forfeit win: " .. A.emotes[#A.emotes])
    check(B.emotes[#B.emotes] == "EMOTE: forfeits a deathroll to Doctor Gup after 1 roll.", "forfeit loss: " .. B.emotes[#B.emotes])

    print("== Options > AddOns > Deathroller page")
    local cat = A.addonCategory
    check(cat and cat.name == "Doctor Gup's Deathroller", "registered under Options > AddOns as 'Deathroller'")
    local panel = cat.panel
    panel:Hide(); panel:Show()                       -- the Settings panel shows it
    local function PanelCheck(label)
        for _, w in ipairs(A.widgets) do
            if rawget(w, "mark") and rawget(w, "label") and w.label._text == label then
                local p = rawget(w, "_parent")
                if p == panel then return w end
            end
        end
    end
    local pf = PanelCheck("Auto-focus the roll box")
    check(pf ~= nil, "the AddOns page has the real options, not just a button")
    check(PanelCheck("Show minimap button") and PanelCheck("Announce challenges") and PanelCheck("Debug messages"), "all sections are on the page")
    local before = A.ns.Setting("autoFocus")
    pf:Fire("OnClick")
    check(A.ns.Setting("autoFocus") == not before, "ticking a box on the page changes the setting")
    local winBox = FindCheck(A, "Auto-focus the roll box")
    check(winBox.checked == A.ns.Setting("autoFocus"), "the options window shows the same value")
    winBox:Fire("OnClick")
    check(pf.checked == A.ns.Setting("autoFocus"), "and changes in the window show on the page")
    panel.OnDefault()
    check(A.ns.Setting("autoFocus") == false and pf.checked == false, "the Settings 'Defaults' button restores defaults")

    print("== reveal length")
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    Tick(1)
    A.env.SlashCmdList.GUPSDEATHROLLER(""); GoChallenge(A); Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
    A.forced = { 50 }
    TypeInBox(A, "/roll 100"); Tick(1.7)
    check(A.env.GupsDeathrollerFrame.revealing and A.env.GupsDeathrollerFrame.dice:IsShown() and not A.ns.state.game.rolls[1].revealed, "dice still rolling at 1.7s")
    Tick(0.5)
    check(A.ns.state.game.rolls[1].revealed, "result revealed at about 2s")

    print("== debts and the trade banner")
    if A.ns.state.game and A.ns.state.game.state ~= "done" then A.ns.Forfeit(); Tick(3) end
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.GetDB().debts = {}; B.ns.GetDB().debts = {}
    A.gold, B.gold = 1000, 1000
    OpenTrade(A, B)
    check(A.env.GupsDeathrollerTradeBanner == nil or not A.env.GupsDeathrollerTradeBanner:IsShown(), "no banner when there's no debt")
    CancelTrade(A, B)

    local function PlayGame(winner, loser, wager)
        winner.env.GupsDeathrollerFrame:Hide(); loser.env.GupsDeathrollerFrame:Hide()
        Tick(1)
        winner.env.SlashCmdList.GUPSDEATHROLLER("challenge " .. loser.name); winner.env.GupsDeathrollerChallengeFrame.input:SetText(tostring(wager)); GoChallenge(winner)
        Tick(0.2)
        loser.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
        winner.forced = { 30 }; loser.forced = { 1 }
        PlayOut(winner, loser)
    end
    PlayGame(A, B, 40)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 40 and B.ns.GetDebt("Doctor Gup") == -40, "a 40g game is recorded as a debt on both sides")

    OpenTrade(B, A)
    local AB, BB = A.env.GupsDeathrollerTradeBanner, B.env.GupsDeathrollerTradeBanner
    check(AB:IsShown() and AB.headline:GetText() == "Meudayr owes you 40g", "winner's banner: " .. tostring(AB.headline:GetText()))
    check(BB:IsShown() and BB.headline:GetText() == "You owe Doctor 40g" and BB.pay:IsShown(), "loser's banner: " .. tostring(BB.headline:GetText()))
    check(BB.pay.text:GetText() == "Put in 40g", "pay button shows the amount")
    PutGold(B, 25)
    check(AB.status:GetText():find("25g, 15g short") ~= nil, "winner sees it's short: " .. AB.status:GetText())
    BB.pay:Fire("OnClick")
    check(B.tradeGive == 400000 and AB.status:GetText():find("covers it") ~= nil, "Put in 40g fills the trade; winner sees it covers it")
    FinishTrade(B, A, { A })        -- only A gets the "Trade complete." line; B relies on the gold check
    check(A.ns.GetDebt("Meudayr Darkpaw") == 0 and B.ns.GetDebt("Doctor Gup") == 0, "completed trade settles the debt on both sides")
    check(not AB:IsShown() and not BB:IsShown(), "banner closes with the trade")

    print("== partial payment, cancel, and not counting")
    PlayGame(A, B, 50)
    OpenTrade(A, B)
    PutGold(B, 20)
    FinishTrade(A, B)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 30 and B.ns.GetDebt("Doctor Gup") == -30, "a partial payment leaves 30g owed")
    OpenTrade(A, B); PutGold(B, 30); CancelTrade(A, B)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 30, "a cancelled trade doesn't count")
    OpenTrade(A, B)
    A.env.GupsDeathrollerTradeBanner.count:Fire("OnClick")
    PutGold(B, 30)
    FinishTrade(A, B)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 30 and B.ns.GetDebt("Doctor Gup") == -30 + 30, "unticking 'count gold' on one side only affects that side")
    B.ns.GetDebt("Doctor Gup")

    print("== games net out")
    A.ns.GetDB().debts = {}; B.ns.GetDB().debts = {}
    PlayGame(A, B, 50)
    PlayGame(B, A, 20)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 30 and B.ns.GetDebt("Doctor Gup") == -30, "win 50, lose 20: they owe you 30")
    local _, rec = A.ns.GetDebt("Meudayr Darkpaw")
    check(rec.games == 2, "debt remembers it came from 2 games")

    print("== Debts tab")
    A.env.GupsDeathrollerStatsFrame:Hide()
    A.env.SlashCmdList.GUPSDEATHROLLER("stats")
    local SF2 = A.env.GupsDeathrollerStatsFrame
    SF2.tabs.buttons[3]:Fire("OnClick")
    local de = SF2.debts
    check(de:IsShown() and SF2.tabs.buttons[3].text:GetText() == "Debts (1)", "Debts tab with a count")
    check(de.owed.value:GetText():find("30g") ~= nil and #de.list.data == 1, "owed-to-you total and one row")
    check(not de.paid:IsEnabled(), "Mark paid needs a selected row")
    de.list.rows[1]:Fire("OnClick")
    check(de.paid:IsEnabled(), "selecting a row enables Mark paid")
    de.list.rows[1]:Fire("OnEnter"); de.list.rows[1]:Fire("OnLeave")
    de.paid:Fire("OnClick")
    check(A.ns.GetDebt("Meudayr Darkpaw") == 0 and #de.list.data == 0 and SF2.tabs.buttons[3].text:GetText() == "Debts", "Mark paid clears it")
    PlayGame(B, A, 15)
    check(A.ns.GetDebt("Meudayr Darkpaw") == -15, "now you owe 15g")
    de.list.rows[1]:Fire("OnClick")
    de.forgive:Fire("OnClick")
    check(A.ns.GetDebt("Meudayr Darkpaw") == 0, "Forgive clears it too")
    A.ns.ResetStats()
    PlayGame(A, B, 10)
    A.ns.ResetStats()
    check(A.ns.GetDebt("Meudayr Darkpaw") == 10, "resetting stats keeps debts (they're real gold)")
    A.env.GupsDeathrollerMinimapButton:Fire("OnEnter")

    print("== survival odds")
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    check(near(A.ns.LoseChance(2), 2/3) and near(A.ns.LoseChance(3), 7/12), "odds maths: L(2) = 2/3, L(3) = 7/12")
    check(math.abs(A.ns.LoseChance(100) - 0.5) < 0.001, "from 100 it's a coin flip (" .. A.ns.LoseChance(100) .. ")")
    if A.ns.state.game and A.ns.state.game.state ~= "done" then A.ns.Forfeit(); Tick(3) end
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    A.ns.GetDB().debts = {}; B.ns.GetDB().debts = {}
    Tick(1)
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw"); A.env.GupsDeathrollerChallengeFrame.input:SetText("30"); GoChallenge(A)
    Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
    local AF, BF = A.env.GupsDeathrollerFrame, B.env.GupsDeathrollerFrame
    check(AF.odds.meText:GetText() == "50%" and AF.odds.themText:GetText() == "50%", "starts at 50% / 50%")
    check(AF.rangeLabel:GetText():find("ROLL 1 TO") and AF.rangeLabel:GetText():find("1%% chance of a 1"), "label: " .. AF.rangeLabel:GetText())
    A.forced = { 2 }
    TypeInBox(A, "/roll 100"); Tick(0.4)
    check(AF.odds.meText:GetText() == "50%", "odds don't move while the dice are still spinning")
    Tick(1.9)
    check(AF.odds.meText:GetText() == "67%" and BF.odds.meText:GetText() == "33%", "after a 2, the next roller has 33%: " .. AF.odds.meText:GetText() .. " / " .. BF.odds.meText:GetText())
    check(AF.odds.meDelta:GetText():find("+17") ~= nil and BF.odds.meDelta:GetText():find("-17") ~= nil, "the change is shown: " .. AF.odds.meDelta:GetText())
    Tick(4)
    check(AF.odds.meDelta:GetText() == "", "the change fades after a few seconds")

    print("== close calls")
    check(BF.tension == 2 and AF.tension == 2, "range 2: critical on both screens")
    check(BF.rangeLabel:GetText():find("CLOSE CALL") and BF.rangeLabel:GetText():find("ROLL 1 TO") and not BF.rangeLabel:GetText():find("CHANCE"),
        "critical label is just CLOSE CALL, ROLL 1 TO: " .. BF.rangeLabel:GetText())
    B.ns.SetSetting("closeCallFx", false)
    check(BF.tension == 0, "turning the option off clears the effects mid-game")
    B.ns.SetSetting("closeCallFx", true)
    check(BF.tension == 2, "and turning it back on restores them")
    B.forced = { 1 }
    TypeInBox(B, "/roll 2"); Tick(5)
    check(AF.tension == 0 and AF.odds.meText:GetText() == "100%" and AF.odds.caption:GetText() == "FINAL", "game over: effects cleared, odds final")

    print("== double or nothing")
    check(AF.double:IsShown() and AF.rematch._w == 144, "result screen offers double or nothing next to rematch")
    A.ns.SetSetting("announceChallenges", true); B.ns.SetSetting("announceChallenges", true)
    local aE, bE = #A.emotes, #B.emotes
    AF.double:Fire("OnEnter"); AF.double:Fire("OnLeave")
    AF.double:Fire("OnClick"); Tick(0.2)
    local g2 = A.ns.state.game
    check(g2.state == "pending" and g2.wager == 60 and g2.double, "double or nothing challenges for 60g")
    check(A.emotes[#A.emotes] == "EMOTE: goes double or nothing against Meudayr Darkpaw for 60g!", "emote: " .. tostring(A.emotes[#A.emotes]))
    local IFd = B.env.GupsDeathrollerInviteFrame
    check(IFd.pot.label:GetText():find("DOUBLE OR NOTHING") and IFd.sub:GetText():find("double or nothing") and IFd.pot.amount:GetText() == "60g", "the popup says double or nothing, for 60g")
    IFd.accept:Fire("OnClick"); Tick(0.2)
    check(B.emotes[#B.emotes] == "EMOTE: accepts Doctor Gup's double or nothing for 60g!", "accept emote: " .. tostring(B.emotes[#B.emotes]))
    check(B.ns.state.game.double and BF.potLabel:GetText():find("DOUBLE OR NOTHING"), "the game window marks it as double or nothing")
    A.forced = { 7 }
    TypeInBox(A, "/roll 100"); Tick(4)
    check(BF.tension == 1 and BF.rangeLabel:GetText():find("CLOSE CALL") and not BF.rangeLabel:GetText():find("CHANCE"), "range 7: close call (amber), no odds in the label")
    A.ns.Forfeit(); Tick(3)
    check(A.ns.GetDebt("Meudayr Darkpaw") == 30 - 60, "debt nets out: won 30, lost 60 (" .. A.ns.GetDebt("Meudayr Darkpaw") .. ")")
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    Tick(25)
    A.env.SlashCmdList.GUPSDEATHROLLER("challenge Meudayr Darkpaw"); GoChallenge(A); Tick(0.2)
    B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
    A.ns.Forfeit(); Tick(3)
    check(not AF.double:IsShown() and AF.rematch._w == 296, "friendly game: no double or nothing, rematch fills the row")
    A.ns.state.game.wager = 6000000
    check(not A.ns.CanDouble(A.ns.state.game), "can't double past the 7-digit wager limit")

    print("== newer-version notice")
    local cv = A.ns.CompareVersions
    check(cv("v1.2.0-beta1", "v1.2.0") == 0 and cv("1.1.0-forever", "v1.1.0") == 0 and cv("v1.10.0", "v1.9.9") == 1,
        "versions compare by their leading numbers")
    if A.ns.state.game and A.ns.state.game.state ~= "done" then A.ns.Forfeit(); Tick(3) end
    A.env.GupsDeathrollerFrame:Hide(); B.env.GupsDeathrollerFrame:Hide()
    local function Notices(c)
        local n = 0
        for _, line in ipairs(c.logs) do if line:find("A newer version of Doctor Gup") then n = n + 1 end end
        return n
    end
    A.ns.VERSION, B.ns.VERSION = "v1.1.1", "v1.1.0"
    local a0, b0 = Notices(A), Notices(B)
    local function Check(from, to)
        Tick(1)
        from.target = to.name
        from.env.SlashCmdList.GUPSDEATHROLLER("")
        Tick(0.3)
        from.env.GupsDeathrollerChallengeFrame.cancel:Fire("OnClick")
    end
    Check(B, A)
    check(Notices(B) == b0 + 1, "checking someone newer tells you to update")
    local last = B.logs[#B.logs]
    for _, line in ipairs(B.logs) do if line:find("A newer version") then last = line end end
    check(last:find("%(v1%.1%.1%) is out%. You have v1%.1%.0%. Update it in the CurseForge app%."), "notice: " .. last)
    check(Notices(A) == a0, "the newer player gets no notice")
    Check(B, A)
    check(Notices(B) == b0 + 1, "only once per session")
    Check(A, B)
    check(Notices(B) == b0 + 1, "being checked by the same version doesn't repeat it")
    A.ns.VERSION = "v1.2.0"
    Check(A, B)
    check(Notices(B) == b0 + 2, "being checked by someone even newer tells you again (their check carries their version)")
    B.ns.VERSION = "@project-version@"
    A.ns.VERSION = "v1.3.0"
    Check(B, A)
    check(Notices(B) == b0 + 2, "development copies (no version number) never nag")
    A.ns.VERSION, B.ns.VERSION = "0.9.1", "0.9.1"

    print("== long names fit")
    local W = A.ns.W
    local fs = A.env.GupsDeathrollerFrame.opp.name
    W.FitText(fs, "Meudayr Darkpaw", 118, 15, 11, { title = true, fallback = "Meudayr" })
    check(fs:GetText() == "Meudayr Darkpaw" and fs:GetStringWidth() <= 118, "slightly long: shrinks the font to keep the full name (size " .. fs._fontSize .. ")")
    W.FitText(fs, "Bartholomew Stormrider", 118, 15, 11, { title = true, fallback = "Bartholomew" })
    check(fs:GetText() == "Bartholomew" and fs._fontSize == 15, "too long even when shrunk: first name only, full size")
    W.FitText(fs, "Al Stormrider", 118, 15, 11, { title = true, fallback = "Al" })
    check(fs:GetText() == "Al Stormrider" and fs._fontSize == 15, "a short name stays at full size")
    local big = A.env.GupsDeathrollerChallengeFrame.name
    W.FitText(big, "Bartholomew Thunderstrike", 280, 22, 14, { flags = "OUTLINE", title = true, fallback = "Bartholomew" })
    check(big:GetText() == "Bartholomew Thunderstrike" and big:GetStringWidth() <= 280, "wager window shrinks a long full name to fit")

    print("== coin flip for who rolls first")
    local function Duel(flip)
        B.ns.CoinFlip = function() return flip end
        Tick(25)
        A.target = B.name
        A.env.SlashCmdList.GUPSDEATHROLLER("challenge 0"); GoChallenge(A); Tick(0.2)
        B.env.GupsDeathrollerInviteFrame.accept:Fire("OnClick"); Tick(0.2)
        return A.ns.state.game, B.ns.state.game
    end
    local function Finish()
        A.env.SlashCmdList.GUPSDEATHROLLER("forfeit"); Tick(0.5)
    end
    local ga, gb = Duel(true)
    check(ga.state == "active" and ga.turn == B.name and gb.turn == B.name, "accepter wins the flip: both agree they roll first")
    check(B.ns.IsMyTurn() and not A.ns.IsMyTurn(), "only the accepter may roll")
    B.forced = { 40 }; TypeInBox(B, "/roll 100"); Tick(4)
    check(#ga.rolls == 1 and ga.max == 40 and ga.turn == A.name, "accepter's first roll lands for both, then it's the challenger's turn")
    Finish()
    ga, gb = Duel(false)
    check(ga.turn == A.name and gb.turn == A.name, "challenger wins the flip: both agree the challenger starts")
    Finish()
    -- a challenger on 1.1.x sends no flip request, so the challenger always starts
    B.ns.CoinFlip = function() return true end
    local sent = {}
    local realSend = A.env.C_ChatInfo.SendAddonMessage
    A.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, ...)
        if msg:sub(1, 5) == "CHAL|" then msg = msg:gsub("|1$", "") end
        return realSend(prefix, msg, ...)
    end
    ga, gb = Duel(true)
    check(gb.turn == A.name and ga.turn == A.name, "old challenger (no flip field): challenger still rolls first")
    Finish()
    A.env.C_ChatInfo.SendAddonMessage = realSend
    -- the real flip picks both sides over many games
    local heads = 0
    for _ = 1, 200 do if realFlipB() then heads = heads + 1 end end
    check(heads > 60 and heads < 140, "real coin flip is roughly even (" .. heads .. "/200)")
end, debug.traceback)

if not ok then print("ERROR: " .. tostring(err)); failures = failures + 1 end
print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
