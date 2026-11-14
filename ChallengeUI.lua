-- Deathroller: "new challenge" window. Target a player, type /dr, pick the wager, Challenge.

local _, ns = ...
local W, C = ns.W, ns.W.C
local Short, FirstName, Num = ns.Short, ns.FirstName, ns.Num

local frame
local PRESETS = { 0, 10, 50, 100, 500, 1000 }

local function CurrentWager()
    return math.max(0, math.floor(tonumber(frame.input:GetText()) or 0))
end

-- Version check result -> status line, and whether you can send the challenge.
local function ProbeText(p)
    local them = FirstName(p.target)
    local v = p.theirVersion or "?"
    if p.status == "checking" then
        return "muted", ("Checking if %s has Deathroller..."):format(them), true
    elseif p.status == "ok" then
        return "win", ("%s has Deathroller %s. Ready to roll."):format(them, v), true
    elseif p.status == "different" then
        local older = ns.CompareVersions(v, ns.VERSION) < 0
        return "warn", ("%s has Deathroller %s, you have %s. Games still work, but %s should update.")
            :format(them, v, ns.VERSION, older and "they" or "you"), true
    elseif p.status == "incompatible" then
        return "loss", ("%s's Deathroller (%s) can't play with yours (%s). %s need to update.")
            :format(them, v, ns.VERSION, ns.CompareVersions(v, ns.VERSION) < 0 and "They" or "You"), false
    elseif p.status == "busy" then
        return "warn", ("%s is in another deathroll right now."):format(them), false
    elseif p.status == "offline" then
        return "loss", ("%s isn't online."):format(them), false
    else -- noreply
        return "loss", ("No answer from %s. They may not have Doctor Gup's Deathroller, or have an old version.")
            :format(them), "anyway"
    end
end

local function Refresh()
    local wager, gold = CurrentWager(), ns.MyGold()
    frame.pot:SetAmount(wager)
    for _, b in ipairs(frame.presets) do
        local on = b.value == wager
        b.bg:SetVertexColor(unpack(on and { C.gold[1], C.gold[2], C.gold[3], 0.25 } or b.style.bg))
        b.text:SetTextColor(unpack(on and C.gold or C.text))
    end
    if wager > gold then
        frame.funds:SetText(W.Color("loss", ("You only have %sg"):format(Num(gold))))
    else
        frame.funds:SetText(("You have %s"):format(W.Color("gold", Num(gold) .. "g")))
    end
    local label = wager > 0 and ("Challenge for %sg"):format(Num(wager)) or "Challenge"

    local p = frame.probe
    local color, text, canSend = "muted", "", true
    if p then color, text, canSend = ProbeText(p) end
    frame.status:SetText(text)
    frame.status:SetTextColor(unpack(C[color]))
    frame.dot:SetVertexColor(unpack(C[color]))
    frame.dot:SetShown(text ~= "")
    frame.retry:SetShown(p ~= nil and (p.status == "noreply" or p.status == "offline" or p.status == "busy"))
    if canSend == "anyway" then label = "Challenge anyway" end
    if canSend then frame.go:Enable() else frame.go:Disable() end
    frame.go:SetLabel(label)
end

local function Submit()
    if not frame.go:IsEnabled() then return end
    local target, wager = frame.target, CurrentWager()
    frame:Hide()
    ns.StartChallenge(target, wager)      -- from a click or Enter: emotes are allowed
end

local function Create()
    local f = W.Panel("GupsDeathrollerChallengeFrame", 320, 372, "New deathroll")
    f:SetPoint("CENTER", 0, 80)
    tinsert(UISpecialFrames, "GupsDeathrollerChallengeFrame")

    f.who = W.Text(f, 10, C.muted, { justify = "CENTER" })
    f.who:SetPoint("TOP", 0, -42)
    f.who:SetText("CHALLENGE")
    f.name = W.Text(f, 22, C.opp, { justify = "CENTER", flags = "OUTLINE", title = true })
    f.name:SetPoint("TOP", 0, -56)
    f.h2h = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.h2h:SetPoint("TOP", 0, -82)

    -- the pot, big
    f.pot = W.Pot(f, 30, "FOR")
    f.pot:SetPoint("TOP", 0, -106)

    -- wager entry
    local wl = W.Text(f, 10, C.muted)
    wl:SetPoint("TOPLEFT", 14, -164)
    wl:SetText("WAGER (GOLD)")
    f.input = W.Input(f, 292, 30, "0 for a friendly game")
    f.input:SetPoint("TOP", 0, -178)
    f.input:SetNumeric(true)
    f.input:SetMaxLetters(7)
    f.input:SetJustifyH("CENTER")
    f.input.placeholder:SetJustifyH("CENTER")
    f.input.OnChanged = function() Refresh() end
    f.input:SetScript("OnEnterPressed", Submit)
    f.input:SetScript("OnEscapePressed", function() f:Hide() end)

    -- quick picks
    f.presets = {}
    local x = 14
    for i, v in ipairs(PRESETS) do
        local b = W.Button(f, v == 0 and "None" or Num(v), 44, 22, "neutral", function()
            f.input:SetText(v == 0 and "" or tostring(v))
            f.input:SetFocus()
            f.input:SetCursorPosition(#f.input:GetText())
        end)
        b:SetPoint("TOPLEFT", x, -216)
        b.value = v
        f.presets[i] = b
        x = x + 44 + 5.6
    end

    f.funds = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.funds:SetPoint("TOP", 0, -250)

    -- version check status
    local line = W.Tex(f, C.line, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 14, -272); line:SetPoint("TOPRIGHT", -14, -272)
    f.dot = W.Tex(f, { 1, 1, 1, 1 }, "ARTWORK")
    f.dot:SetSize(6, 6)
    f.dot:SetPoint("TOPLEFT", 16, -287)
    f.status = W.Text(f, 11, C.muted, { wrap = true })
    f.status:SetPoint("TOPLEFT", 28, -283)
    f.status:SetWidth(200)
    f.retry = W.Button(f, "Check again", 76, 20, "ghost", function()
        f.probe = ns.CheckPlayer(f.target)
        Refresh()
    end)
    f.retry:SetPoint("TOPRIGHT", -12, -280)

    f.cancel = W.Button(f, "Cancel", 100, 30, "neutral", function() f:Hide() end)
    f.cancel:SetPoint("BOTTOMLEFT", 14, 14)
    f.go = W.Button(f, "Challenge", 184, 30, "primary", Submit)
    f.go:SetPoint("BOTTOMRIGHT", -14, 14)

    f:SetScript("OnHide", function() f.input:ClearFocus() end)   -- give the keyboard back

    W.ApplyScale(f)
    f:Hide()
    frame = f
end

local function Show(target, wager)
    if not frame then Create() end
    frame.target = target
    W.FitText(frame.name, Short(target), 280, 22, 14, { flags = "OUTLINE", title = true, fallback = FirstName(target) })
    local w, l, net = ns.HeadToHead(target)
    if w + l == 0 then
        frame.h2h:SetText(("You haven't played %s before"):format(FirstName(target)))
    else
        frame.h2h:SetText(("Your record vs %s:  %s-%s   %s"):format(FirstName(target),
            W.Color("win", w), W.Color("loss", l), W.Gold(net, true)))
    end
    frame.input:SetText(wager and wager > 0 and tostring(wager) or "")
    frame.probe = ns.CheckPlayer(target)
    frame:Show()
    Refresh()
    frame.input:SetFocus()
    frame.input:HighlightText()
end

ns.OnSetting(function(key) if key == "scale" then W.ApplyScale(frame) end end)
ns.UI.ShowChallengeSetup = Show
ns.UI.ProbeUpdated = function(p)
    if frame and frame:IsShown() and frame.probe == p then Refresh() end
end
