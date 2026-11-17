-- Free For All window: set the roll, watch people join, see the rolls come in,
-- and the result. Same wood-and-brass look as the game window.

local ADDON_NAME, ns = ...
local W, C = ns.W, ns.W.C
local S = ns.state
local Short, FirstName, Num = ns.Short, ns.FirstName, ns.Num

local frame
local setup = false          -- showing the "pick a roll" step (no game yet)

local PICKS = { 100, 150, 500, 1000 }

local function CurrentMax()
    local n = tonumber((frame.input:GetText() or ""):gsub("[,%s]", ""), 10)
    return n and math.floor(n) or nil
end

local function Start()
    local n = CurrentMax()
    if not n or n < ns.FFA_MIN_MAX then
        frame.hint:SetText(W.Color("warn", "Pick a roll of 2 or more."))
        return
    end
    setup = false
    frame.input:ClearFocus()
    ns.FFA_Start(n)
end

local function Create()
    local f = W.Panel("GupsDeathrollerFFAFrame", 320, 446, "Free For All")
    f:SetPoint("CENTER", 0, 100)
    tinsert(UISpecialFrames, "GupsDeathrollerFFAFrame")
    f:SetScript("OnHide", function()
        f.input:ClearFocus()
        setup = false
        ns.FFA_Clear()                                   -- a finished game goes away with the window
    end)

    f.rangeLabel = W.Text(f, 10, C.muted, { justify = "CENTER" })
    f.rangeLabel:SetPoint("TOP", 0, -42)
    f.big = W.Text(f, 34, C.gold, { justify = "CENTER", flags = "OUTLINE", title = true })
    f.big:SetPoint("TOP", 0, -56)

    f.status = W.Text(f, 12, C.text, { justify = "CENTER" })
    f.status:SetPoint("TOP", 0, -100)
    f.status:SetWidth(296)
    f.rule = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.rule:SetPoint("TOP", f.status, "BOTTOM", 0, -4)
    f.rule:SetWidth(296)

    f.timer = W.TimerBar(f, 296, ns.FFA_JOIN_TIME)
    f.timer:SetPoint("TOP", 0, -158)
    f.timer:SetScript("OnUpdate", function(self)
        local g = S.ffa
        if g and g.expires and g.phase ~= "done" then self:SetExpiry(g.expires) end
    end)

    -- setup: the roll to use
    f.input = W.Input(f, 140, 30, "e.g. 150")
    f.input:SetPoint("TOP", 0, -150)
    f.input:SetNumeric(true)
    f.input:SetMaxLetters(7)
    f.input:SetJustifyH("CENTER")
    f.input:SetScript("OnEnterPressed", function() ns.WithKeyPress(Start) end)   -- Enter: the emote goes out at once
    f.input:SetScript("OnEscapePressed", function() f:Hide() end)
    f.input:HookScript("OnTextChanged", function()
        local n = CurrentMax()
        f.big:SetText(n and n >= ns.FFA_MIN_MAX and Num(n) or "-")
        f.hint:SetText("")
    end)
    f.picks = W.Segmented(f, {
        { value = 100, label = "100", width = 52 }, { value = 150, label = "150", width = 52 },
        { value = 500, label = "500", width = 52 }, { value = 1000, label = "1,000", width = 60 },
    }, function(v) f.input:SetText(tostring(v)); f.input:SetFocus() end)
    f.picks:SetPoint("TOP", 0, -190)
    f.hint = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.hint:SetPoint("TOP", f.picks, "BOTTOM", 0, -10)
    f.hint:SetWidth(296)
    f.howto = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.howto:SetPoint("TOP", 0, -246)
    f.howto:SetWidth(280)
    f.howto:SetSpacing(3)
    f.howto:SetText("Players nearby type " .. W.Color("text", "1") .. " in chat to join, then everyone rolls. "
        .. "The lowest roll pays the highest roll the difference in gold. Ties re-roll. Nobody else needs the add-on.")

    -- players
    f.list = W.ScrollList(f, 296, 8, {
        { key = "name", title = "Player", width = 170 },
        { key = "roll", title = "Roll", width = 66, justify = "RIGHT" },
        { key = "tag", title = "", width = 56, justify = "RIGHT" },
    }, { rowHeight = 22 })
    f.list:SetPoint("TOPLEFT", 12, -176)
    local listBg = W.Card(f.list)
    listBg:SetAllPoints()
    listBg:SetFrameLevel(f.list:GetFrameLevel())

    -- footer
    f.left = W.Button(f, "Cancel", 144, 26, "neutral", function()
        if f.leftAction then f.leftAction() end
    end)
    f.left:SetPoint("BOTTOMLEFT", 12, 12)
    f.right = W.Button(f, "Start", 148, 26, "primary", function()
        if f.rightAction then f.rightAction() end
    end)
    f.right:SetPoint("BOTTOMRIGHT", -12, 12)

    W.ApplyScale(f)
    f:Hide()
    frame = f
end

local function Rows(g)
    local rows = {}
    local order = {}
    for i, p in ipairs(g.players) do order[i] = p end
    if g.phase ~= "join" then
        -- rolled first (highest at the top), then anyone still to roll
        table.sort(order, function(a, b)
            if a.roll and b.roll then return a.roll > b.roll end
            if a.roll or b.roll then return a.roll ~= nil end
            return false
        end)
    end
    local res = g.result or {}
    for _, p in ipairs(order) do
        local name = Short(p.name) .. (p.host and W.Color("muted", "  (host)") or "")
        local roll, tag
        if g.phase == "join" then
            roll = W.Color("muted", "in")
        elseif p.roll then
            roll = tostring(p.roll)
            if p.reroll then roll = roll .. W.Color("muted", " / " .. p.reroll) end
        else
            roll = W.Color("muted", g.phase == "done" and "no roll" or "...")
        end
        if res.winner and ns.SameName(p.name, res.winner) then
            name, tag = W.Color("gold", Short(p.name)), W.Color("win", "HIGH")
        elseif res.payer and ns.SameName(p.name, res.payer) then
            name, tag = W.Color("loss", Short(p.name)), W.Color("loss", "PAYS")
        elseif p.tie then
            tag = W.Color("warn", p.reroll and "TIE" or "ROLL")
        end
        rows[#rows + 1] = { cells = { name, roll, tag or "" } }
    end
    return rows
end

local function Show(list, on) for _, w in ipairs(list) do w:SetShown(on) end end

local function Update()
    if not frame then
        if not (S.ffa or setup) then return end
        Create()
    end
    local f, g = frame, S.ffa
    if not g and not setup then f:Hide(); return end
    f:Show()

    local setupParts = { f.input, f.picks, f.hint, f.howto }
    local gameParts = { f.list }

    if not g then -- setup
        Show(setupParts, true); Show(gameParts, false)
        f.timer:Hide()
        f.rangeLabel:SetText("EVERYONE ROLLS 1 TO")
        local n = CurrentMax()
        f.big:SetText(n and n >= ns.FFA_MIN_MAX and Num(n) or "-")
        f.big:SetTextColor(unpack(C.gold))
        f.status:SetText("How high does everyone roll?")
        f.rule:SetText("That's also the most anyone can owe.")
        f.left:SetLabel("Cancel"); f.leftAction = function() f:Hide() end
        f.right:SetLabel("Start Free For All"); f.right:Enable(); f.rightAction = Start
        return
    end

    Show(setupParts, false); Show(gameParts, true)
    f.rangeLabel:SetText(g.phase == "done" and "RESULT" or "EVERYONE ROLLS 1 TO")
    f.big:SetTextColor(unpack(C.gold))
    f.big:SetText(Num(g.max))
    f.timer:SetShown(g.phase ~= "done")
    f.left:Enable()

    if g.phase == "join" then
        f.status:SetText(("Type %s in chat to join  ·  %d in"):format(W.Color("gold", "1"), #g.players))
        f.rule:SetText("Lowest roll pays the highest roll the difference.")
        f.timer.label:SetText("Joining closes")
        f.timer:SetMinMaxValues(0, g.total or ns.FFA_JOIN_TIME)
        f.left:SetLabel("Cancel"); f.leftAction = ns.FFA_Cancel
        f.right:SetLabel(#g.players >= 2 and ("Start rolling (%d)"):format(#g.players) or "Waiting for players")
        f.right:SetEnabled(#g.players >= 2)
        f.rightAction = function() ns.FFA_StartRolling(false) end
    elseif g.phase == "roll" or g.phase == "tie" then
        local waiting, mine = 0, nil
        for _, p in ipairs(g.players) do
            local owes = g.phase == "roll" and not p.roll or (g.phase == "tie" and p.tie and not p.reroll)
            if owes then waiting = waiting + 1 end
            if owes and ns.SameName(p.name, S.me) then mine = true end
        end
        if g.phase == "tie" then
            f.status:SetText(W.Color("warn", "Tie!") .. (" Tied players roll again: %s"):format(W.Color("text", "/roll " .. g.max)))
        else
            f.status:SetText(("Everyone types %s"):format(W.Color("gold", "/roll " .. g.max)))
        end
        f.rule:SetText(mine and W.Color("gold", "Your turn to roll too.") or ("Waiting on %d player%s"):format(waiting, waiting == 1 and "" or "s"))
        f.timer.label:SetText("Rolls close")
        f.timer:SetMinMaxValues(0, g.total or ns.FFA_ROLL_TIME)
        f.left:SetLabel("Cancel"); f.leftAction = ns.FFA_Cancel
        f.right:SetLabel("Close rolls"); f.right:Enable(); f.rightAction = ns.FFA_CloseRolls
    else -- done
        local r = g.result or {}
        if r.winner then
            f.big:SetText(Num(r.amount) .. "g")
            f.status:SetText(("%s owes %s %s"):format(W.Color("loss", FirstName(r.payer)), W.Color("gold", FirstName(r.winner)),
                W.Color("gold", Num(r.amount) .. "g")))
            f.rule:SetText(("%d (highest) minus %d (lowest)"):format(g.highRoll, g.lowRoll))
        elseif r.allTied then
            f.big:SetText("-")
            f.status:SetText("Everyone rolled the same. Nobody owes anything.")
            f.rule:SetText("")
        else
            f.big:SetText("-")
            f.status:SetText("Not enough rolls. No result.")
            f.rule:SetText("")
        end
        local max = g.max
        f.left:SetLabel("Play again"); f.leftAction = function() S.ffa = nil; ns.FFA_Start(max) end
        f.right:SetLabel("Close"); f.right:Enable(); f.rightAction = function() f:Hide() end
    end
    f.list:SetData(Rows(g), "No players yet.")
end

local function ShowSetup()
    if ns.FFA_IsActive() then Update(); return end
    if not frame then Create() end
    if S.ffa then S.ffa = nil end                        -- a finished one makes way
    setup = true
    frame.input:SetText("")
    frame.hint:SetText("")
    Update()
    frame.input:SetFocus()
end

ns.UI.FFAUpdate = Update
ns.UI.ShowFFASetup = ShowSetup
ns.OnSetting(function(key) if key == "scale" and frame then W.ApplyScale(frame) end end)
