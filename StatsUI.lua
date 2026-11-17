-- Deathroller: stats window (Overview + full, filterable, scrollable History).

local _, ns = ...
local W, C = ns.W, ns.W.C
local Short, FirstName, Num = ns.Short, ns.FirstName, ns.Num

local frame
local filter = { search = "", result = "all", period = "all" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Pct(w, total)
    if total == 0 then return "-" end
    return ("%d%%"):format(math.floor(w / total * 100 + 0.5))
end

local function Record(w, l)
    return W.Color("win", w) .. W.Color("muted", "-") .. W.Color("loss", l)
end

local function MidnightToday()
    local t = date("*t")
    return time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

local function PeriodStart(period)
    if period == "today" then return MidnightToday() end
    if period == "7d" then return time() - 7 * 86400 end
    if period == "30d" then return time() - 30 * 86400 end
    return 0
end

-- "m72,o40,m1" -> coloured "100 > 72 > 40 > 1"
local function FormatSequence(h)
    local parts = { W.Color("muted", Num(h.start or ns.START_ROLL)) }
    for token in (h.seq or ""):gmatch("[^,]+") do
        local who, n = token:sub(1, 1), tonumber(token:sub(2))
        if n then
            parts[#parts + 1] = n == 1 and W.Color("loss", "1") or W.Color(who == "m" and "gold" or "opp", Num(n))
        end
    end
    return table.concat(parts, W.Color("muted", " > "))
end

-- KPI card: label / big value / small note
local function StatCard(parent, label)
    local card = W.Card(parent)
    card:SetSize(127, 66)
    card.label = W.Text(card, 10, C.muted)
    card.label:SetPoint("TOPLEFT", 10, -9)
    card.label:SetText(label)
    card.value = W.Text(card, 22, C.text, { title = true })
    card.value:SetPoint("TOPLEFT", 10, -24)
    card.note = W.Text(card, 10, C.muted)
    card.note:SetPoint("BOTTOMLEFT", 10, 8)
    card.note:SetPoint("RIGHT", -8, 0)
    return card
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local SetTab, RefreshHistory, RefreshDebts, RefreshLive

local function CreateStatsFrame()
    local DB = ns.GetDB()
    local f = W.Panel("GupsDeathrollerStatsFrame", 560, 520, "Deathroller stats")
    if DB.statsPos then
        f:SetPoint(DB.statsPos[1], UIParent, DB.statsPos[2], DB.statsPos[3], DB.statsPos[4])
    else
        f:SetPoint("CENTER", 0, 40)
    end
    function f:OnMoved()
        local p, _, rp, x, y = self:GetPoint()
        ns.GetDB().statsPos = { p, rp, x, y }
    end
    tinsert(UISpecialFrames, "GupsDeathrollerStatsFrame")

    f.tabs = W.Segmented(f, {
        { value = "overview", label = "Overview", width = 84 },
        { value = "history",  label = "History",  width = 84 },
        { value = "debts",    label = "Debts",    width = 84 },
        { value = "live",     label = "Live",     width = 72 },
    }, function(v) SetTab(v) end)
    f.tabs:SetPoint("TOPLEFT", 12, -40)

    f.total = W.Text(f, 11, C.muted, { justify = "RIGHT" })
    f.total:SetPoint("TOPRIGHT", -14, -46)

    -- Overview page ---------------------------------------------------------
    local ov = CreateFrame("Frame", nil, f)
    ov:SetPoint("TOPLEFT", 0, -72)
    ov:SetPoint("BOTTOMRIGHT", 0, 46)
    f.overview = ov

    ov.record = StatCard(ov, "RECORD")
    ov.record:SetPoint("TOPLEFT", 12, 0)
    ov.net = StatCard(ov, "NET GOLD")
    ov.net:SetPoint("LEFT", ov.record, "RIGHT", 8, 0)
    ov.streak = StatCard(ov, "STREAK")
    ov.streak:SetPoint("LEFT", ov.net, "RIGHT", 8, 0)
    ov.biggest = StatCard(ov, "BIGGEST WIN")
    ov.biggest:SetPoint("LEFT", ov.streak, "RIGHT", 8, 0)

    local oppTitle = W.Text(ov, 12, C.text)
    oppTitle:SetPoint("TOPLEFT", 14, -84)
    oppTitle:SetText("Opponents")
    local oppHint = W.Text(ov, 10, C.muted, { justify = "RIGHT" })
    oppHint:SetPoint("TOPRIGHT", -14, -86)
    oppHint:SetText("click a player to see your games against them")

    ov.list = W.ScrollList(ov, 536, 12, {
        { title = "Player", width = 200 },
        { title = "Games",  width = 70, justify = "CENTER" },
        { title = "Record", width = 90, justify = "CENTER" },
        { title = "Win %",  width = 70, justify = "CENTER" },
        { title = "Net",    width = 96, justify = "RIGHT" },
    }, {
        onClick = function(item)
            filter.search = item.name:lower()
            f.search:SetText(item.name)
            SetTab("history")
        end,
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.name, C.opp[1], C.opp[2], C.opp[3])
            if item.last then GameTooltip:AddLine("Last played " .. date("%b %d, %H:%M", item.last), 0.7, 0.7, 0.7) end
            GameTooltip:AddLine("Click to see your games against them", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end,
    })
    ov.list:SetPoint("TOPLEFT", 12, -102)
    local ovbg = W.Card(ov.list)
    ovbg:SetAllPoints()
    ovbg:SetFrameLevel(ov.list:GetFrameLevel())

    -- History page ----------------------------------------------------------
    local hi = CreateFrame("Frame", nil, f)
    hi:SetPoint("TOPLEFT", 0, -72)
    hi:SetPoint("BOTTOMRIGHT", 0, 46)
    f.history = hi

    f.search = W.Input(hi, 160, 24, "Search opponent...")
    f.search:SetPoint("TOPLEFT", 12, 0)
    function f.search:OnChanged()
        filter.search = strtrim(self:GetText() or ""):lower()
        RefreshHistory()
    end
    f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    hi.result = W.Segmented(hi, {
        { value = "all",    label = "All",    width = 40 },
        { value = "win",    label = "Wins",   width = 48 },
        { value = "loss",   label = "Losses", width = 56 },
    }, function(v) filter.result = v; RefreshHistory() end)
    hi.result:SetPoint("LEFT", f.search, "RIGHT", 10, 0)

    hi.period = W.Segmented(hi, {
        { value = "all",   label = "All time", width = 58 },
        { value = "30d",   label = "30d",      width = 40 },
        { value = "7d",    label = "7d",       width = 36 },
        { value = "today", label = "Today",    width = 50 },
    }, function(v) filter.period = v; RefreshHistory() end)
    hi.period:SetPoint("LEFT", hi.result, "RIGHT", 10, 0)

    hi.summary = W.Text(hi, 12, C.text)
    hi.summary:SetPoint("TOPLEFT", 14, -36)
    hi.clear = W.Button(hi, "Clear filters", 90, 20, "ghost", function()
        filter.search, filter.result, filter.period = "", "all", "all"
        f.search:SetText("")
        hi.result:SetValue("all")
        hi.period:SetValue("all")
        RefreshHistory()
    end)
    hi.clear:SetPoint("TOPRIGHT", -12, -32)

    hi.list = W.ScrollList(hi, 536, 14, {
        { title = "When",     width = 110 },
        { title = "Result",   width = 64, justify = "CENTER" },
        { title = "Opponent", width = 190 },
        { title = "Rolls",    width = 60, justify = "CENTER" },
        { title = "Gold",     width = 96, justify = "RIGHT" },
    }, {
        onEnter = function(row, item)
            local h = item.h
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddDoubleLine(Short(h.opp), h.won and "Win" or "Loss",
                C.opp[1], C.opp[2], C.opp[3],
                (h.won and C.win or C.loss)[1], (h.won and C.win or C.loss)[2], (h.won and C.win or C.loss)[3])
            GameTooltip:AddLine(date("%A, %B %d %Y at %H:%M", h.t), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            if h.mode == "ffa" then
                GameTooltip:AddLine(("Free For All 1-%s, %d players"):format(Num(h.start or 0), h.players or 0), 1, 1, 1)
                if h.myRoll and h.theirRoll then
                    GameTooltip:AddLine(("You rolled %d, they rolled %d"):format(h.myRoll, h.theirRoll), 0.8, 0.8, 0.8)
                end
            elseif h.seq and h.seq ~= "" then
                GameTooltip:AddLine(FormatSequence(h), 1, 1, 1, true)
            else
                GameTooltip:AddLine(("%d rolls (sequence not recorded)"):format(h.rolls or 0), 0.6, 0.6, 0.6)
            end
            if h.reason == "forfeit" then
                GameTooltip:AddLine((h.won and "They" or "You") .. " forfeited", 0.6, 0.6, 0.6)
            end
            if (h.wager or 0) > 0 then
                GameTooltip:AddLine((h.won and "Won " or "Lost ") .. Num(h.wager) .. "g", C.gold[1], C.gold[2], C.gold[3])
            end
            GameTooltip:Show()
        end,
        onClick = function(item)
            f.search:SetText(Short(item.h.opp))   -- filters to that opponent
        end,
    })
    hi.list:SetPoint("TOPLEFT", 12, -58)
    local hibg = W.Card(hi.list)
    hibg:SetAllPoints()
    hibg:SetFrameLevel(hi.list:GetFrameLevel())

    -- Debts page --------------------------------------------------------------
    local de = CreateFrame("Frame", nil, f)
    de:SetPoint("TOPLEFT", 0, -72)
    de:SetPoint("BOTTOMRIGHT", 0, 46)
    f.debts = de

    de.owed = StatCard(de, "OWED TO YOU")
    de.owed:SetPoint("TOPLEFT", 12, 0)
    de.owed:SetWidth(263)
    de.owe = StatCard(de, "YOU OWE")
    de.owe:SetPoint("LEFT", de.owed, "RIGHT", 10, 0)
    de.owe:SetWidth(263)

    local dTitle = W.Text(de, 12, C.text)
    dTitle:SetPoint("TOPLEFT", 14, -84)
    dTitle:SetText("Unpaid deathrolls")
    local dHint = W.Text(de, 10, C.muted, { justify = "RIGHT" })
    dHint:SetPoint("TOPRIGHT", -14, -86)
    dHint:SetText("trading these players settles them automatically")

    de.list = W.ScrollList(de, 536, 10, {
        { title = "Player",  width = 200 },
        { title = "",        width = 130 },
        { title = "Amount",  width = 96, justify = "RIGHT" },
        { title = "Since",   width = 100, justify = "RIGHT" },
    }, {
        selectable = true,
        onClick = function() RefreshDebts() end,
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.key, C.opp[1], C.opp[2], C.opp[3])
            GameTooltip:AddLine(item.amount > 0 and ("Owes you %sg"):format(Num(math.floor(item.amount + 0.5)))
                or ("You owe them %sg"):format(Num(math.floor(-item.amount + 0.5))), 1, 1, 1)
            GameTooltip:AddLine(("From %d wagered deathroll%s"):format(item.games, item.games == 1 and "" or "s"), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Paid by mail or some other way? Select it and click Mark paid.", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
        end,
    })
    de.list:SetPoint("TOPLEFT", 12, -102)
    local debg = W.Card(de.list)
    debg:SetAllPoints()
    debg:SetFrameLevel(de.list:GetFrameLevel())

    de.paid = W.Button(de, "Mark paid", 110, 24, "neutral", function()
        local item = de.list:GetSelected()
        if item then ns.ClearDebt(item.key, "paid") end
    end)
    de.paid:SetPoint("TOPLEFT", 12, -356)
    de.forgive = W.Button(de, "Forgive", 90, 24, "ghost", function()
        local item = de.list:GetSelected()
        if item then ns.ClearDebt(item.key, "forgive") end
    end)
    de.forgive:SetPoint("LEFT", de.paid, "RIGHT", 8, 0)
    de.selHint = W.Text(de, 10, C.muted)
    de.selHint:SetPoint("LEFT", de.forgive, "RIGHT", 12, 0)

    -- Live page: games in your guild and group you can watch ---------------
    local lv = CreateFrame("Frame", nil, f)
    lv:SetPoint("TOPLEFT", 0, -72)
    lv:SetPoint("BOTTOMRIGHT", 0, 46)
    f.live = lv
    local lTitle = W.Text(lv, 12, C.text)
    lTitle:SetPoint("TOPLEFT", 14, 0)
    lTitle:SetText("Live games")
    local lHint = W.Text(lv, 10, C.muted, { justify = "RIGHT" })
    lHint:SetPoint("TOPRIGHT", -14, -2)
    lHint:SetText("click a game to watch it")
    lv.list = W.ScrollList(lv, 536, 12, {
        { title = "Game",   width = 270 },
        { title = "Stakes", width = 100, justify = "RIGHT" },
        { title = "Roll",   width = 80, justify = "RIGHT" },
        { title = "",       width = 76, justify = "RIGHT" },
    }, {
        onClick = function(item) ns.Watch(item.server) end,
        onEnter = function(row, item)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(item.title, 1, 1, 1)
            GameTooltip:AddLine("Click to watch. Close the game window to stop.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end,
    })
    lv.list:SetPoint("TOPLEFT", 12, -20)
    local lvbg = W.Card(lv.list)
    lvbg:SetAllPoints()
    lvbg:SetFrameLevel(lv.list:GetFrameLevel())
    lv.how = W.Text(lv, 11, C.muted, { justify = "LEFT" })
    lv.how:SetPoint("TOPLEFT", lv.list, "BOTTOMLEFT", 2, -10)
    lv.how:SetWidth(530)
    lv.how:SetText("Games from your guild and group show up here. To watch anyone else, target them and type "
        .. W.Color("text", "/dr watch") .. ". You can watch from anywhere; nothing you watch is recorded.")
    -- keep it fresh while it's open
    lv.elapsed = 0
    lv:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 2 then self.elapsed = 0; RefreshLive() end
    end)

    -- Footer ------------------------------------------------------------------
    f.reset = W.Button(f, "Reset stats", 110, 24, "ghost")
    f.reset:SetPoint("BOTTOMLEFT", 12, 12)
    f.reset:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetLabel("Reset stats")
            ns.ResetStats()
        else
            self.armed = true
            self:SetLabel(W.Color("loss", "Click to confirm"))
            C_Timer.After(4, function()
                if self.armed then self.armed = nil; self:SetLabel("Reset stats") end
            end)
        end
    end)
    f.open = W.Button(f, "Open challenge", 120, 24, "primary", function() ns.OpenChallenge(nil) end)
    f.open:SetPoint("LEFT", f.reset, "RIGHT", 8, 0)
    f.open:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Open challenge")
        GameTooltip:AddLine("Anyone nearby can take it by typing /roll 100. They don't need the add-on.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.open:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.ffa = W.Button(f, "Free For All", 110, 24, "neutral", function() ns.UI.ShowFFASetup() end)
    f.ffa:SetPoint("LEFT", f.open, "RIGHT", 8, 0)
    f.ffa:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Free For All")
        GameTooltip:AddLine("Anyone nearby types 1 to join, everyone rolls, and the lowest roll pays the highest the difference. Nobody else needs the add-on.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.ffa:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.note = W.Text(f, 10, C.muted, { justify = "RIGHT" })
    f.note:SetPoint("BOTTOMRIGHT", -14, 18)
    f.note:SetText(("Keeps your last %s games"):format(Num(ns.HISTORY_SIZE)))

    W.ApplyScale(f)
    f:Hide()
    frame = f
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------

local function RefreshOverview()
    local DB, ov = ns.GetDB(), frame.overview
    local s = DB.stats
    local total = s.wins + s.losses

    ov.record.value:SetText(Record(s.wins, s.losses))
    ov.record.note:SetText(total > 0 and ("%s won  -  %d games"):format(Pct(s.wins, total), total) or "No games yet")

    ov.net.value:SetText(W.Gold(s.goldWon - s.goldLost, true))
    ov.net.note:SetText(("won %s  -  lost %s"):format(Num(s.goldWon) .. "g", Num(s.goldLost) .. "g"))

    if s.streak > 0 then
        ov.streak.value:SetText(W.Color("win", s.streak .. (s.streak == 1 and " win" or " wins")))
    elseif s.streak < 0 then
        ov.streak.value:SetText(W.Color("loss", -s.streak .. (s.streak == -1 and " loss" or " losses")))
    else
        ov.streak.value:SetText(W.Color("muted", "-"))
    end
    ov.streak.note:SetText(s.bestStreak > 0 and ("best: %d wins in a row"):format(s.bestStreak) or "no wins yet")

    ov.biggest.value:SetText(s.biggestWin > 0 and W.Gold(s.biggestWin) or W.Color("muted", "-"))
    ov.biggest.note:SetText("largest pot you've won")

    local items = {}
    for name, o in pairs(DB.opponents) do
        local games = o.w + o.l
        items[#items + 1] = {
            name = Short(name), last = o.last, games = games,
            cells = { W.Color("opp", Short(name)), tostring(games), Record(o.w, o.l), Pct(o.w, games), W.Gold(o.net, true) },
        }
    end
    table.sort(items, function(a, b)
        if a.games ~= b.games then return a.games > b.games end
        return (a.last or 0) > (b.last or 0)
    end)
    ov.list:SetData(items, "Nobody yet. Challenge someone with /dr challenge First Last.")
end

RefreshHistory = function()
    if not frame then return end
    local DB, hi = ns.GetDB(), frame.history
    local since = PeriodStart(filter.period)
    local items, w, l, net = {}, 0, 0, 0
    for _, h in ipairs(DB.history) do
        local ok = h.t >= since
            and (filter.result == "all" or (filter.result == "win") == (h.won == true))
            and (filter.search == "" or Short(h.opp):lower():find(filter.search, 1, true) ~= nil)
        if ok then
            local wager = h.wager or 0
            if h.won then w = w + 1; net = net + wager else l = l + 1; net = net - wager end
            items[#items + 1] = {
                h = h,
                cells = {
                    date("%m/%d  %H:%M", h.t),
                    h.won and W.Color("win", "WIN") or W.Color("loss", "LOSS"),
                    W.Color("opp", Short(h.opp)) .. (h.reason == "forfeit" and W.Color("muted", "  forfeit") or "")
                        .. (h.noAddon and W.Color("muted", "  no add-on") or "")
                        .. (h.mode == "ffa" and W.Color("muted", "  free for all") or ""),
                    tostring(h.rolls or "-"),
                    wager > 0 and W.Gold(h.won and wager or -wager, true) or W.Color("muted", "-"),
                },
            }
        end
    end

    local n = #items
    if n == 0 then
        hi.summary:SetText(W.Color("muted", "No games match"))
    else
        hi.summary:SetText(("%d game%s   %s  (%s)   net %s"):format(n, n == 1 and "" or "s",
            Record(w, l), Pct(w, n), W.Gold(net, true)))
    end
    local filtered = filter.search ~= "" or filter.result ~= "all" or filter.period ~= "all"
    hi.clear:SetShown(filtered)
    hi.list:SetData(items, #DB.history == 0 and "No games yet." or "No games match these filters.")
end

RefreshDebts = function()
    if not frame then return end
    local DB, de = ns.GetDB(), frame.debts
    local owedToMe, iOwe, nOwed, nOwe = ns.DebtTotals()
    de.owed.value:SetText(owedToMe > 0 and W.Color("win", Num(math.floor(owedToMe + 0.5)) .. "g") or W.Color("muted", "-"))
    de.owed.note:SetText(nOwed > 0 and ("from %d player%s"):format(nOwed, nOwed == 1 and "" or "s") or "nobody owes you")
    de.owe.value:SetText(iOwe > 0 and W.Color("loss", Num(math.floor(iOwe + 0.5)) .. "g") or W.Color("muted", "-"))
    de.owe.note:SetText(nOwe > 0 and ("to %d player%s"):format(nOwe, nOwe == 1 and "" or "s") or "you're all paid up")

    local items = {}
    for name, d in pairs(DB.debts) do
        items[#items + 1] = {
            key = name, amount = d.amount, games = d.games or 0, since = d.since,
            cells = {
                W.Color("opp", Short(name)),
                d.amount > 0 and W.Color("win", "owes you") or W.Color("loss", "you owe"),
                W.Gold(math.floor(math.abs(d.amount) + 0.5)),
                date("%m/%d", d.since or time()),
            },
        }
    end
    table.sort(items, function(a, b) return math.abs(a.amount) > math.abs(b.amount) end)
    de.list:SetData(items, "No unpaid deathrolls. Everyone's square.")

    local sel = de.list:GetSelected()
    if sel then de.paid:Enable(); de.forgive:Enable() else de.paid:Disable(); de.forgive:Disable() end
    de.selHint:SetText(sel and "" or "select a row first")

    local n = #items
    frame.tabs.buttons[3].text:SetText(n > 0 and ("Debts (%d)"):format(n) or "Debts")
end

RefreshLive = function()
    if not frame then return end
    local items = {}
    for _, e in ipairs(ns.LiveGames and ns.LiveGames() or {}) do
        local title, stakes, cells
        if e.kind == "duel" then
            title = ("%s vs %s"):format(Short(e.p1), Short(e.p2))
            stakes = (e.wager or 0) > 0 and W.Gold(e.wager) or W.Color("muted", "friendly")
            cells = { W.Color("gold", Short(e.p1)) .. W.Color("muted", "  vs  ") .. W.Color("opp", Short(e.p2)),
                stakes, "1-" .. Num(e.max), W.Color("gold", "Watch") }
        else
            title = ("%s's Free For All"):format(Short(e.host))
            cells = { W.Color("gold", Short(e.host)) .. W.Color("muted", "'s Free For All  ·  " .. (e.count or 0) .. " in"),
                W.Color("muted", e.phase == "join" and "joining" or "rolling"), "1-" .. Num(e.max), W.Color("gold", "Watch") }
        end
        items[#items + 1] = { server = e.server, title = title, cells = cells }
    end
    frame.live.list:SetData(items, "No live games in your guild or group right now.")
    frame.tabs.buttons[4].text:SetText(#items > 0 and ("Live (%d)"):format(#items) or "Live")
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    local DB = ns.GetDB()
    local s = DB.stats
    frame.total:SetText(("%d games played  -  %d in history"):format(s.wins + s.losses, #DB.history))
    RefreshOverview()
    RefreshHistory()
    RefreshDebts()
    RefreshLive()
end

SetTab = function(tab)
    frame.tabs:SetValue(tab)
    frame.overview:SetShown(tab == "overview")
    frame.history:SetShown(tab == "history")
    frame.debts:SetShown(tab == "debts")
    frame.live:SetShown(tab == "live")
    Refresh()
end

local function ToggleStats()
    if not frame then CreateStatsFrame() end
    if frame:IsShown() then frame:Hide(); return end
    frame:Show()
    SetTab(frame.tabs.value or "overview")
end

ns.OnSetting(function(key) if key == "scale" then W.ApplyScale(frame) end end)

ns.UI.ToggleStats  = ToggleStats
ns.UI.RefreshStats = Refresh
