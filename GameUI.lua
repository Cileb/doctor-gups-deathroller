-- Deathroller: game window, challenge popup and the dice reveal.

local _, ns = ...
local W, C = ns.W, ns.W.C
local S = ns.state
local SameName, Short, FirstName, Num = ns.SameName, ns.Short, ns.FirstName, ns.Num

-- Seconds of dice animation before a result is shown, per "revealSpeed" option.
local REVEAL_TIMES = { fast = 1.4, normal = 2.0, slow = 4.0 }
local function RevealTime()
    if not ns.Setting("animation") then return 0 end
    return REVEAL_TIMES[ns.Setting("revealSpeed")] or REVEAL_TIMES.normal
end
local function RevealHold()            -- seconds the result stays up before the window moves on
    return ns.Setting("animation") and 1.2 or 0.4
end
local DICE_TEXTURE = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"

local frame                 -- game window
local inviteFrame           -- challenge popup

---------------------------------------------------------------------------
-- Player cards ("You" vs opponent)
---------------------------------------------------------------------------

local function PlayerCard(parent, label, nameColor)
    local card = W.Card(parent)
    card:SetSize(136, 50)
    card.label = W.Text(card, 10, C.muted)
    card.label:SetPoint("TOPLEFT", 10, -9)
    card.label:SetText(label)
    card.name = W.Text(card, 15, nameColor, { title = true })
    card.name:SetPoint("TOPLEFT", 10, -24)       -- width set by W.FitText
    card.tag = W.Text(card, 10, C.accent, { justify = "RIGHT" })
    card.tag:SetPoint("TOPRIGHT", -8, -9)

    function card:SetActive(on, tag)
        if on then
            self.border:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
        else
            self.border:SetColor(unpack(C.line))
            self.bg:SetVertexColor(unpack(C.card))
        end
        self.tag:SetText(on and tag or "")
    end
    return card
end

---------------------------------------------------------------------------
-- Game window
---------------------------------------------------------------------------

local function CreateGameFrame()
    local DB = ns.GetDB()
    local f = W.Panel("GupsDeathrollerFrame", 320, 430, "Deathroll")
    if DB.pos then
        f:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
    else
        f:SetPoint("CENTER", 0, 120)
    end
    function f:OnMoved()
        local p, _, rp, x, y = self:GetPoint()
        ns.GetDB().pos = { p, rp, x, y }
    end
    tinsert(UISpecialFrames, "GupsDeathrollerFrame")      -- Escape closes it
    f:SetScript("OnHide", function()
        if f.input then f.input:ClearFocus() end      -- give the keyboard back
        ns.ClearFinished()
    end)


    -- matchup
    f.me = PlayerCard(f, "YOU", C.gold)
    f.me:SetPoint("TOPLEFT", 12, -40)
    f.opp = PlayerCard(f, "OPPONENT", C.opp)
    f.opp:SetPoint("TOPRIGHT", -12, -40)
    local vs = W.Text(f, 11, C.muted, { justify = "CENTER" })
    vs:SetPoint("TOP", 0, -59)
    vs:SetText("vs")

    -- chance to win: you (gold, left) vs them (teal, right), under the player cards
    local odds = CreateFrame("Frame", nil, f)
    odds:SetSize(296, 5)
    odds:SetPoint("TOP", 0, -114)
    odds.bg = W.Tex(odds, { 0, 0, 0, 0.45 })
    odds.bg:SetAllPoints()
    odds.mine = W.Tex(odds, { C.gold[1], C.gold[2], C.gold[3], 0.9 }, "ARTWORK")
    odds.mine:SetPoint("TOPLEFT"); odds.mine:SetPoint("BOTTOMLEFT")
    odds.theirs = W.Tex(odds, { C.opp[1], C.opp[2], C.opp[3], 0.75 }, "ARTWORK")
    odds.theirs:SetPoint("TOPRIGHT"); odds.theirs:SetPoint("BOTTOMRIGHT")
    odds.mid = W.Tex(odds, { C.text[1], C.text[2], C.text[3], 0.5 }, "OVERLAY")   -- the 50% mark
    odds.mid:SetSize(1, 9)
    odds.mid:SetPoint("CENTER")
    odds.caption = W.Text(f, 9, C.muted, { justify = "CENTER" })
    odds.caption:SetPoint("BOTTOM", odds, "TOP", 0, 4)
    odds.caption:SetText("CHANCE TO WIN")
    odds.meText = W.Text(f, 13, C.gold, { title = true })
    odds.meText:SetPoint("BOTTOMLEFT", odds, "TOPLEFT", 0, 3)
    odds.meDelta = W.Text(f, 10, C.muted)
    odds.meDelta:SetPoint("LEFT", odds.meText, "RIGHT", 5, 0)
    odds.themText = W.Text(f, 13, C.opp, { title = true, justify = "RIGHT" })
    odds.themText:SetPoint("BOTTOMRIGHT", odds, "TOPRIGHT", 0, 3)
    odds.themDelta = W.Text(f, 10, C.muted, { justify = "RIGHT" })
    odds.themDelta:SetPoint("RIGHT", odds.themText, "LEFT", -5, 0)
    odds.shown, odds.target = 0.5, 0.5
    function odds:Draw(p)
        local w = self:GetWidth()
        self.mine:SetWidth(math.max(0.01, w * p))
        self.theirs:SetWidth(math.max(0.01, w * (1 - p)))
    end
    odds:SetScript("OnUpdate", function(self, dt)            -- glide to the new value
        if math.abs(self.target - self.shown) < 0.001 then return end
        self.shown = self.shown + (self.target - self.shown) * math.min(1, dt * 6)
        self:Draw(self.shown)
    end)
    f.odds = odds

    -- the pot, front and centre under the players
    f.potBg = W.Tex(f, { C.gold[1], C.gold[2], C.gold[3], 0.07 }, "BACKGROUND", 1)
    f.potBg:SetPoint("TOPLEFT", 12, -126)
    f.potBg:SetPoint("TOPRIGHT", -12, -126)
    f.potBg:SetHeight(34)
    f.potLabel = W.Text(f, 10, C.gold, { justify = "LEFT" })
    f.potLabel:SetPoint("LEFT", f.potBg, "LEFT", 10, 0)
    f.potLabel:SetText("POT")
    f.pot = W.Pot(f, 22)
    f.pot:SetPoint("TOP", 0, -132)

    -- centre: label, big number, status
    f.rangeLabel = W.Text(f, 10, C.muted, { justify = "CENTER" })
    f.rangeLabel:SetWidth(296)
    f.rangeLabel:SetPoint("TOP", 0, -170)

    f.glow = W.Tex(f, { 1, 1, 1, 1 }, "ARTWORK")
    f.glow:SetSize(220, 56)
    f.glow:SetPoint("TOP", 0, -182)
    f.glow:SetAlpha(0)
    local flash = f.glow:CreateAnimationGroup()
    local fa = flash:CreateAnimation("Alpha")
    fa:SetFromAlpha(0.35); fa:SetToAlpha(0); fa:SetDuration(0.7)
    f.flash = flash

    -- close-call pulses (looping; speed set per level)
    f.glowPulse = f.glow:CreateAnimationGroup()
    f.glowPulse:SetLooping("BOUNCE")
    f.glowPulseA = f.glowPulse:CreateAnimation("Alpha")
    f.glowPulseA:SetFromAlpha(0.04); f.glowPulseA:SetToAlpha(0.22)

    f.big = W.Text(f, 44, C.text, { justify = "CENTER", flags = "OUTLINE", title = true })
    f.big:SetPoint("TOP", 0, -184)
    f.bigPulse = f.big:CreateAnimationGroup()
    f.bigPulse:SetLooping("BOUNCE")
    f.bigPulseA = f.bigPulse:CreateAnimation("Alpha")
    f.bigPulseA:SetFromAlpha(1); f.bigPulseA:SetToAlpha(0.55)

    f.dice = f:CreateTexture(nil, "OVERLAY")
    f.dice:SetTexture(DICE_TEXTURE)
    f.dice:SetSize(30, 30)
    f.dice:SetPoint("RIGHT", f.big, "LEFT", -10, 0)
    f.dice:Hide()

    f.status = W.Text(f, 12, C.muted, { justify = "CENTER" })
    f.status:SetPoint("TOP", 0, -236)
    f.status:SetWidth(296)

    -- pending: countdown
    f.timer = W.TimerBar(f, 296, ns.INVITE_TIMEOUT)
    f.timer:SetPoint("TOP", 0, -278)
    f.timer.label:SetText("Challenge expires")
    f.timer:SetScript("OnUpdate", function(self)
        local g = S.game
        if g and (g.state == "pending" or g.state == "open") and g.expires then self:SetExpiry(g.expires) end
    end)

    -- active: roll input
    f.input = W.Input(f, 296, 30, "")
    f.input:SetPoint("TOP", 0, -262)
    f.input:SetJustifyH("CENTER")
    f.input.placeholder:SetJustifyH("CENTER")
    f.input:SetMaxLetters(20)
    f.input:SetScript("OnEnterPressed", function(self)
        local ok, why = ns.TryRollCommand(self:GetText())
        if ok then
            self:SetText("")
            self:ClearFocus()
        elseif why == "wrong" then
            f.status:SetText(W.Color("loss", "Not quite.") .. "  Type exactly " .. W.Color("text", "/roll " .. S.game.max))
            ns.Sound("IG_QUEST_LOG_ABANDON_QUEST")
            self:HighlightText()
        else
            self:SetText("")
            self:ClearFocus()
        end
    end)

    -- done: series line and milestones
    f.series = W.Text(f, 12, C.muted, { justify = "CENTER" })
    f.series:SetPoint("TOP", 0, -262)
    f.milestones = W.Text(f, 11, C.gold, { justify = "CENTER" })
    f.milestones:SetPoint("TOP", 0, -280)
    f.milestones:SetWidth(296)

    -- roll ladder
    f.ladderLabel = W.Text(f, 10, C.muted)
    f.ladderLabel:SetPoint("TOPLEFT", 14, -306)
    f.ladder = W.Text(f, 13, C.text, { wrap = true })
    f.ladder:SetPoint("TOPLEFT", 14, -322)
    f.ladder:SetWidth(292)
    f.ladder:SetSpacing(4)

    -- footer buttons (shown per state)
    f.forfeit = W.Button(f, "Forfeit", 90, 26, "ghost", function() ns.Forfeit() end)
    f.forfeit:SetPoint("BOTTOMLEFT", 12, 12)
    f.forfeit:HookScript("OnEnter", function(self)
        if not ns.IsStalled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("End game")
        GameTooltip:AddLine("Ends it with no result. Nobody wins, nobody owes.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.forfeit:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.statsBtn = W.Button(f, "Stats", 90, 26, "ghost", function() ns.UI.ToggleStats() end)
    f.statsBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.cancel = W.Button(f, "Cancel challenge", 296, 26, "neutral", function() ns.Forfeit() end)
    f.cancel:SetPoint("BOTTOM", 0, 12)
    -- result screen: [Rematch][Double or nothing] over [Announce][Close]
    f.rematch = W.Button(f, "Rematch", 144, 26, "neutral", function() ns.Rematch() end)
    f.rematch:SetPoint("BOTTOMLEFT", 12, 44)
    f.rematch:HookScript("OnEnter", function(self)
        local g = S.game
        if not g then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Rematch")
        GameTooltip:AddLine(g.wager > 0 and ("Same stakes: %sg"):format(Num(g.wager)) or "Another friendly game", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f.rematch:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.double = W.Button(f, "Double or nothing", 148, 26, "primary", function() ns.DoubleOrNothing() end)
    f.double:SetPoint("BOTTOMRIGHT", -12, 44)
    f.double:HookScript("OnEnter", function(self)
        local g = S.game
        if not g then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Double or nothing")
        GameTooltip:AddLine(("Challenge %s again for %sg, twice this pot."):format(FirstName(g.opponent), Num(g.wager * 2)), 0.7, 0.7, 0.7, true)
        local gold = ns.MyGold()
        if gold < g.wager * 2 then
            GameTooltip:AddLine(("You only have %sg."):format(Num(gold)), C.loss[1], C.loss[2], C.loss[3])
        end
        GameTooltip:Show()
    end)
    f.double:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.closeBtn = W.Button(f, "Close", 148, 26, "neutral", function() f:Hide() end)
    f.closeBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.announce = W.Button(f, "Announce", 144, 26, "neutral", function() ns.AnnounceResult() end)
    f.announce:SetPoint("BOTTOMLEFT", 12, 12)
    f.announce:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.bg:SetVertexColor(unpack(self.style.hi)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Announce the result")
        GameTooltip:AddLine("Your character emotes the result to everyone nearby" ..
            (ns.Setting("announceMilestones") and ", plus any milestones." or "."), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.announce:HookScript("OnLeave", function() GameTooltip:Hide() end)

    W.ApplyScale(f)
    f:Hide()
    frame = f
end

-- Auto-focus only when it can't get in the way: not in combat, and not while
-- you're typing in chat or any other box.
local function CanAutoFocus()
    if InCombatLockdown and InCombatLockdown() then return false end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus ~= frame.input then return false end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return false end
    return true
end

-- Once per turn: pre-fill "/roll " and/or put the cursor in the box (both optional).
local function PrepareMyTurn(g)
    if g.preparedTurn == #g.rolls then return end
    g.preparedTurn = #g.rolls
    local box = frame.input
    if ns.Setting("prefillRoll") and box:GetText() == "" then box:SetText("/roll ") end
    if ns.Setting("autoFocus") and CanAutoFocus() then
        box:SetFocus()
        box:SetCursorPosition(#box:GetText())
    end
end

-- Odds from what both players have SEEN: only revealed rolls count, so the bar
-- never gives away a result that's still spinning. Returns your chance (0..1).
local function MyWinChance(g)
    if g.state == "done" then return g.won and 1 or 0 end
    -- whoever rolls first: the first roll's owner, or (before any roll) whose turn it is
    local n, roller = g.startMax, (g.rolls[1] and g.rolls[1].who) or g.turn or g.challenger
    for i = #g.rolls, 1, -1 do
        local r = g.rolls[i]
        if r.revealed then
            if r.roll == 1 then return SameName(r.who, S.me) and 0 or 1 end
            n = r.roll
            roller = SameName(r.who, S.me) and g.opponent or S.me
            break
        end
    end
    local rollerWins = 1 - ns.LoseChance(n)
    return SameName(roller, S.me) and rollerWins or (1 - rollerWins)
end

local function Pct(p) return ("%d%%"):format(math.floor(p * 100 + 0.5)) end

local function UpdateOdds(g)
    local o = frame.odds
    local p = MyWinChance(g)
    local key = g.id .. ":" .. g.state
    if o.gameKey ~= g.id then                      -- new game: jump, no deltas
        o.gameKey, o.shown = g.id, p
        o:Draw(p)
        o.meDelta:SetText(""); o.themDelta:SetText("")
    elseif o.target and math.abs(p - o.target) >= 0.005 and g.state ~= "done" then
        local d = math.floor((p - o.target) * 100 + 0.5)
        if d ~= 0 then
            o.meDelta:SetText(W.Color(d > 0 and "win" or "loss", (d > 0 and "+" or "") .. d))
            o.themDelta:SetText(W.Color(d < 0 and "win" or "loss", (d < 0 and "+" or "") .. (-d)))
            local token = {}
            o.deltaToken = token
            C_Timer.After(2.5, function()
                if o.deltaToken == token then o.meDelta:SetText(""); o.themDelta:SetText("") end
            end)
        end
    end
    o.target = p
    o.meText:SetText(Pct(p))
    o.themText:SetText(Pct(1 - p))
    o.caption:SetText(g.state == "done" and "FINAL" or "CHANCE TO WIN")
end

-- "1% chance of a 1" from 100 (only shown above 10; close calls speak for themselves).
local function OneChance(n)
    return ("%d%% CHANCE OF A 1"):format(math.max(1, math.floor(100 / n + 0.5)))
end

-- Close calls: 10 or less is tense (amber), 3 or less is critical (red).
local TENSION_SOUNDS = { "UI_BATTLEGROUND_COUNTDOWN_TIMER", "ALARM_CLOCK_WARNING_3", "RAID_WARNING" }
local function TensionLevel(g)
    if not g or g.state ~= "active" then return 0 end
    if g.max <= 3 then return 2 end
    if g.max <= 10 then return 1 end
    return 0
end

local function ClearTension()
    local f = frame
    f.bigPulse:Stop(); f.glowPulse:Stop()
    f.big:SetAlpha(1); f.glow:SetAlpha(0)
    f.trim:SetColor(C.accent[1], C.accent[2], C.accent[3], 0.45)
    f.tension = 0
end

local function ApplyTension(g)
    local f = frame
    local level = ns.Setting("closeCallFx") and TensionLevel(g) or 0
    if level == 0 then
        if f.tension ~= 0 then ClearTension() end
        return
    end
    local color = level == 2 and C.loss or C.warn
    f.big:SetTextColor(unpack(color))
    f.trim:SetColor(color[1], color[2], color[3], level == 2 and 1 or 0.8)
    f.glow:SetVertexColor(unpack(color))
    if f.tension ~= level then
        local speed = level == 2 and 0.35 or 0.7
        f.bigPulseA:SetDuration(speed); f.glowPulseA:SetDuration(speed)
        f.bigPulse:Stop(); f.glowPulse:Stop()
        f.bigPulse:Play(); f.glowPulse:Play()
        -- one warning sound each time it gets worse
        if level > (g.tensionHeard or 0) then
            g.tensionHeard = level
            for _, key in ipairs(TENSION_SOUNDS) do
                if SOUNDKIT and SOUNDKIT[key] then ns.Sound(key); break end
            end
        end
        f.tension = level
    end
end

local function UpdateLadder()
    local f, g = frame, S.game
    local oppFirst = g.opponent and FirstName(g.opponent) or "them"
    f.ladderLabel:SetText("ROLLS   " .. W.Color("gold", "you") .. "  " .. W.Color("opp", oppFirst:lower()))

    local parts = { W.Color("muted", Num(g.startMax)) }
    for _, r in ipairs(g.rolls) do
        if r.revealed then
            local v
            if r.roll == 1 then v = W.Color("loss", "1")
            else v = W.Color(SameName(r.who, S.me) and "gold" or "opp", Num(r.roll)) end
            if not r.verified then v = v .. W.Color("muted", "*") end
            parts[#parts + 1] = v
        end
    end
    -- keep the most recent ones if it gets long
    while #parts > 10 do table.remove(parts, 2); parts[2] = W.Color("muted", "...") end
    f.ladder:SetText(table.concat(parts, W.Color("muted", "  >  ")))
end

local function ShowOnly(f, shown)
    for _, key in ipairs({ "timer", "input", "series", "milestones", "forfeit", "statsBtn", "cancel", "rematch", "double", "closeBtn", "announce" }) do
        f[key]:SetShown(shown[key] == true)
    end
end

local function Update()
    local f, g = frame, S.game
    if not f then return end
    if not g then f:Hide(); return end
    if f.revealing then f:Show(); return end          -- the dice animation owns the window

    local opp = g.opponent and Short(g.opponent) or "Anyone nearby"
    f.opp.label:SetText(g.noAddon and "NO ADD-ON" or "OPPONENT")
    -- cards are narrow: shrink long names, then fall back to the first name
    W.FitText(f.me.name, Short(S.me), 118, 15, 11, { title = true, fallback = FirstName(S.me) })
    W.FitText(f.opp.name, opp, 118, 15, 11, { title = true, fallback = FirstName(opp) })
    f.pot:SetAmount(g.wager)
    f.potLabel:SetShown(g.wager > 0)
    f.potBg:SetShown(g.wager > 0)
    UpdateLadder()
    UpdateOdds(g)
    W.SetFont(f.big, 44, "OUTLINE", true)
    f.dice:Hide()

    f.potLabel:SetText(g.double and W.Color("loss", "DOUBLE OR NOTHING") or "POT")
    if g.state == "pending" or g.state == "open" then
        ShowOnly(f, { timer = true, cancel = true })
        f.me:SetActive(false); f.opp:SetActive(false)
        f.rangeLabel:SetText("STARTING ROLL")
        f.big:SetText(Num(g.max))
        f.big:SetTextColor(unpack(C.muted))
        if g.state == "open" then
            -- chat challenge: the accept is a roll, and that roll comes first
            f.status:SetText(("Waiting for %s to type %s"):format(
                g.only and W.Color("opp", FirstName(opp)) or "anyone nearby", W.Color("text", "/roll " .. g.max)))
            f.timer.label:SetText("First to roll takes it on")
        else
            f.status:SetText(("Waiting for %s to accept..."):format(W.Color("opp", FirstName(opp))))
            f.timer.label:SetText("Challenge expires")
        end
        f.timer:SetExpiry(g.expires or GetTime())

    elseif g.state == "active" or g.state == "ending" then
        ShowOnly(f, { input = true, forfeit = true, statsBtn = true })
        f.forfeit:SetLabel(ns.IsStalled(g) and "End game" or "Forfeit")
        local mine = ns.IsMyTurn()
        f.me:SetActive(mine, "YOUR TURN")
        f.opp:SetActive(not mine and g.state == "active", "ROLLING")
        f.big:SetText(Num(g.max))
        f.big:SetTextColor(unpack(mine and C.gold or C.text))
        local level = TensionLevel(g)
        if level > 0 then
            -- at this range the risk speaks for itself; no odds needed
            f.rangeLabel:SetText(W.Color(level == 2 and "loss" or "warn", "CLOSE CALL") .. "   ROLL 1 TO")
        else
            f.rangeLabel:SetText("ROLL 1 TO   " .. W.Color("muted", "(" .. OneChance(g.max):lower() .. ")"))
        end
        if mine then
            f.status:SetText(W.Color("win", "Your turn!") .. "  Type the command below.")
            f.input:Enable()
            f.input:SetPlaceholder(("/roll %d   then press Enter"):format(g.max))
        else
            if ns.IsStalled(g) then
                f.status:SetText(("%s hasn't rolled for 2 minutes."):format(W.Color("opp", FirstName(opp))))
            else
                f.status:SetText(("Waiting for %s to /roll %d..."):format(W.Color("opp", FirstName(opp)), g.max))
            end
            f.input:SetText("")
            f.input:ClearFocus()
            f.input:Disable()
            f.input:SetPlaceholder("Not your turn")
        end
        f.input.keepHighlight = mine
        f.input:SetHighlighted(mine or f.input:HasFocus())
        f.input:SetAlpha(mine and 1 or 0.5)
        f.input:RefreshPlaceholder()

    else -- done
        local canAnnounce = ns.Setting("announceResults")
        local canDouble = ns.CanDouble(g)
        ShowOnly(f, { series = true, milestones = true, rematch = true, double = canDouble, closeBtn = true, announce = canAnnounce })
        -- rows stay full width when a button is missing
        f.rematch:SetWidth(canDouble and 144 or 296)
        f.closeBtn:SetWidth(canAnnounce and 148 or 296)
        if g.announced then
            f.announce:SetLabel("Announced")
            f.announce:Disable()
        else
            f.announce:SetLabel("Announce")
            f.announce:Enable()
        end
        local labels = {}
        for i, m in ipairs(g.milestones or {}) do labels[i] = m.label end
        f.milestones:SetText(#labels > 0 and ("* " .. table.concat(labels, "   * ")) or "")
        f.me:SetActive(false); f.opp:SetActive(false)
        f.rangeLabel:SetText("RESULT")
        W.SetFont(f.big, 34, "OUTLINE", true)
        f.big:SetText(g.won and "VICTORY" or "DEFEAT")
        f.big:SetTextColor(unpack(g.won and C.win or C.loss))
        local how = g.reason == "forfeit" and "forfeited" or "rolled a 1"
        local who = g.won and FirstName(opp) or "You"
        local owe = ""
        if g.wager > 0 then
            owe = g.won and ("  -  %s owes you %s"):format(FirstName(opp), W.Gold(g.wager))
                or ("  -  you owe %s"):format(W.Gold(g.wager))
        end
        f.status:SetText(who .. " " .. how .. owe)
        if g.wager > 0 then
            f.potLabel:SetText(g.won and W.Color("win", "YOU WIN") or W.Color("loss", "YOU LOSE"))
        end
        local w, l = ns.HeadToHead(g.opponent)
        local lead = w > l and "You lead" or (w < l and (FirstName(opp) .. " leads") or "Series tied")
        f.series:SetText(("%s  %s-%s"):format(lead, W.Color("win", w), W.Color("loss", l)))
    end
    ApplyTension(g)
    f:Show()
    if ns.IsMyTurn() then PrepareMyTurn(g) end
end

---------------------------------------------------------------------------
-- Dice reveal: the real roll has already happened on the server; its chat line is
-- hidden (see the chat filter below) and shown here after a short animation.
---------------------------------------------------------------------------

local queue = {}
local driver = CreateFrame("Frame")      -- not a child of the window, so it runs even if that's hidden

local function SystemColor()
    local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
    if info then return info.r, info.g, info.b end
    return 1, 1, 0
end

local function RunNextReveal()
    local job = queue[1]
    if not job then return end
    local f = frame
    if not f then table.remove(queue, 1); job.done(); return RunNextReveal() end

    local e = job.entry
    local isMe = SameName(e.who, S.me)
    local color = isMe and C.gold or C.opp
    f.revealing = true
    f:Show()
    f.me:SetActive(isMe, "ROLLING")
    f.opp:SetActive(not isMe, "ROLLING")
    f.rangeLabel:SetText(isMe and "YOU ROLL" or (FirstName(e.who):upper() .. " ROLLS"))
    f.status:SetText(("1 to %s ..."):format(Num(e.max)))
    f.input:ClearFocus()
    f.input:Disable()
    f.input:SetPlaceholder("Rolling...")
    f.input:RefreshPlaceholder()
    f.bigPulse:Stop(); f.big:SetAlpha(1)            -- the pulse would fight the flicker
    f.tension = -1                                  -- re-applied once the result is in
    W.SetFont(f.big, 44, "OUTLINE", true)
    local duration = RevealTime()
    f.dice:SetShown(duration > 0)
    if duration > 0 then ns.Sound("IG_BACKPACK_OPEN") end

    local elapsed, nextTick = 0, 0
    driver:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        f.dice:SetRotation(elapsed * 10)

        if elapsed < duration then
            if elapsed >= nextTick then
                -- flicker random numbers, slowing down as it nears the end
                local p = elapsed / duration
                nextTick = elapsed + 0.04 + p * p * 0.4
                f.big:SetText(Num(math.random(1, e.max)))
                f.big:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            end
            return
        end

        -- Land on the real result.
        self:SetScript("OnUpdate", nil)
        e.revealed = true
        if S.game then UpdateOdds(S.game) end        -- the bar moves the moment the number lands
        f.dice:Hide()
        f.dice:SetRotation(0)
        f.big:SetText(Num(e.roll))
        if e.roll == 1 then
            f.big:SetTextColor(unpack(C.loss))
            f.glow:SetVertexColor(unpack(C.loss))
            f.status:SetText(W.Color("loss", (isMe and "You" or FirstName(e.who)) .. " rolled a 1!"))
            ns.Sound("RAID_WARNING")
        else
            f.big:SetTextColor(unpack(color))
            f.glow:SetVertexColor(unpack(color))
            f.status:SetText((isMe and "You" or FirstName(e.who)) .. " rolled " .. W.Color(isMe and "gold" or "opp", Num(e.roll)))
            ns.Sound("LOOT_WINDOW_COIN_SOUND")
        end
        f.flash:Stop(); f.flash:Play()
        UpdateLadder()
        if ns.IsGameRollLineHidden() then
            DEFAULT_CHAT_FRAME:AddMessage(job.line .. (e.verified and "" or "  |cff888888(unverified)|r"), SystemColor())
        end

        C_Timer.After(RevealHold(), function()
            table.remove(queue, 1)
            f.revealing = false
            job.done()
            RunNextReveal()
        end)
    end)
end

local function Reveal(entry, line, done)
    table.insert(queue, { entry = entry, line = line, done = done })
    if #queue == 1 then RunNextReveal() end
end

local function ChatFilter(_, _, msg, ...)
    if ns.IsGameRollLine(msg) then return true end
    return false, msg, ...
end

---------------------------------------------------------------------------
-- Challenge popup
---------------------------------------------------------------------------

local function CreateInviteFrame()
    local f = W.Panel("GupsDeathrollerInviteFrame", 320, 290, "Deathroll challenge")
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    function f:OnCloseClicked() ns.DeclineInvite() end

    f.name = W.Text(f, 22, C.gold, { justify = "CENTER", flags = "OUTLINE", title = true })
    f.name:SetPoint("TOP", 0, -44)
    f.sub = W.Text(f, 12, C.muted, { justify = "CENTER" })
    f.sub:SetPoint("TOP", 0, -68)
    f.sub:SetText("challenges you to a deathroll")

    f.potBg = W.Tex(f, { C.gold[1], C.gold[2], C.gold[3], 0.07 }, "BACKGROUND", 1)
    f.potBg:SetPoint("TOPLEFT", 14, -90)
    f.potBg:SetPoint("TOPRIGHT", -14, -90)
    f.potBg:SetHeight(58)
    f.pot = W.Pot(f, 30, "FOR")
    f.pot:SetPoint("TOP", 0, -96)

    f.start = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.start:SetPoint("TOP", 0, -156)
    f.h2h = W.Text(f, 11, C.muted, { justify = "CENTER" })
    f.h2h:SetPoint("TOP", 0, -174)

    -- Ticked if the challenger announced their challenge (or you announce challenges).
    f.announce = W.Check(f, 200, "Announce to people nearby")
    f.announce:SetPoint("TOP", 6, -196)
    f.announce:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Your character emotes that you accepted the challenge.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.announce:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.bar = W.TimerBar(f, 292, ns.INVITE_TIMEOUT)
    f.bar:SetPoint("BOTTOM", 0, 52)
    f.bar.label:SetText("Expires in")

    f.decline = W.Button(f, "Decline", 142, 28, "neutral", function() ns.DeclineInvite() end)
    f.decline:SetPoint("BOTTOMLEFT", 14, 14)
    f.accept = W.Button(f, "Accept", 142, 28, "success", function() ns.AcceptInvite(f.announce.checked) end)
    f.accept:SetPoint("BOTTOMRIGHT", -14, 14)

    f:SetScript("OnUpdate", function(self)
        local inv = S.invite
        if not inv then self:Hide(); return end
        if self.bar:SetExpiry(inv.expires) <= 0 then ns.DeclineInvite(true) end
    end)
    W.ApplyScale(f)
    f:Hide()
    inviteFrame = f
end

local function ShowInvite(inv)
    if not inviteFrame then CreateInviteFrame() end
    local f = inviteFrame
    W.FitText(f.name, Short(inv.from), 280, 22, 14, { flags = "OUTLINE", title = true, fallback = FirstName(inv.from) })
    f.pot:SetAmount(inv.wager)
    f.potBg:SetShown(inv.wager > 0)
    if inv.double then
        f.sub:SetText(W.Color("loss", "wants double or nothing!"))
        f.pot.label:SetText(W.Color("loss", "DOUBLE OR NOTHING"))
    else
        f.sub:SetText("challenges you to a deathroll")
        f.pot.label:SetText("FOR")
    end
    f.announce:SetChecked(inv.announced or ns.Setting("announceChallenges"))
    f.start:SetText("Starting roll 1 - " .. Num(inv.max))
    local w, l, net = ns.HeadToHead(inv.from)
    if w + l == 0 then
        f.h2h:SetText(("You haven't played %s before"):format(FirstName(inv.from)))
    else
        f.h2h:SetText(("Your record vs %s:  %s-%s   %s"):format(FirstName(inv.from),
            W.Color("win", w), W.Color("loss", l), W.Gold(net, true)))
    end
    f.bar:SetExpiry(inv.expires)
    f:Show()
end

local function HideInvite()
    if inviteFrame then inviteFrame:Hide() end
end

---------------------------------------------------------------------------
-- Hook up to the core
---------------------------------------------------------------------------

function ns.UI.Init()
    CreateGameFrame()
    local addFilter = ChatFrame_AddMessageEventFilter
        or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if addFilter then
        addFilter("CHAT_MSG_SYSTEM", ChatFilter)
        ns.chatFilterActive = true
    else
        ns.Debug("no chat filter API; roll lines will show in chat straight away")
    end
end

ns.OnSetting(function(key)
    if key == "scale" then
        W.ApplyScale(frame)
        W.ApplyScale(inviteFrame)
    elseif key == "closeCallFx" then
        if frame and frame:IsShown() and S.game and not frame.revealing then Update() end
    elseif key == "announceResults" then
        if frame and frame:IsShown() then Update() end
    elseif key == "autoFocus" or key == "prefillRoll" then
        if S.game then S.game.preparedTurn = nil end
        if frame and frame:IsShown() then Update() end
    end
end)

------------------------------------------------------------------------
-- "Press Enter to post" bar. On Forever an add-on can only emote after a key
-- press (a click doesn't count), so after a click the announcement waits here.
-- Only Enter and Esc are taken; every other key keeps working as normal.
------------------------------------------------------------------------
local prompt

local function KeyCap(parent, label)
    local cap = CreateFrame("Frame", nil, parent)
    cap:SetHeight(18)
    local bg = W.Tex(cap, C.header, "BACKGROUND")
    bg:SetAllPoints()
    W.Border(cap, { C.accent[1], C.accent[2], C.accent[3], 0.8 })
    cap.text = W.Text(cap, 10, C.gold, { flags = "OUTLINE" })
    cap.text:SetPoint("CENTER", 0, 0)
    cap.text:SetText(label)
    cap:SetWidth(cap.text:GetStringWidth() + 14)
    return cap
end

local function CreatePrompt()
    local f = CreateFrame("Frame", "GupsDeathrollerEmotePrompt", UIParent)
    f:SetSize(320, 84)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.bg = W.Tex(f, C.bg)
    f.bg:SetAllPoints()
    W.Border(f)
    local inner = CreateFrame("Frame", nil, f)
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)
    W.Border(inner, { C.accent[1], C.accent[2], C.accent[3], 0.45 })

    f.caption = W.Text(f, 10, C.muted)
    f.caption:SetPoint("TOPLEFT", 12, -9)
    f.caption:SetText("ANNOUNCE TO PEOPLE NEARBY")
    f.count = W.Text(f, 10, C.muted, { justify = "RIGHT" })
    f.count:SetPoint("TOPRIGHT", -28, -9)

    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(16, 16)
    f.close:SetPoint("TOPRIGHT", -6, -6)
    f.close.text = W.Text(f.close, 12, C.muted)
    f.close.text:SetPoint("CENTER")
    f.close.text:SetText("x")
    f.close:SetScript("OnClick", function() ns.SkipEmotes() end)   -- skipping needs no key press
    f.close:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.text)) end)
    f.close:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.muted)) end)

    f.preview = W.Text(f, 12, C.text, { justify = "LEFT" })
    f.preview:SetPoint("TOPLEFT", 12, -24)
    f.preview:SetWidth(296)
    f.preview:SetMaxLines(2)

    f.enter = KeyCap(f, "ENTER")
    f.enter:SetPoint("BOTTOMLEFT", 12, 10)
    f.enterText = W.Text(f, 11, C.text)
    f.enterText:SetPoint("LEFT", f.enter, "RIGHT", 6, 0)
    f.enterText:SetText("Post")
    f.esc = KeyCap(f, "ESC")
    f.esc:SetPoint("LEFT", f.enterText, "RIGHT", 16, 0)
    f.escText = W.Text(f, 11, C.muted)
    f.escText:SetPoint("LEFT", f.esc, "RIGHT", 6, 0)
    f.escText:SetText("Skip")

    -- time left before it's dropped: a thin brass line along the bottom
    f.timeBar = W.Tex(f, { C.accent[1], C.accent[2], C.accent[3], 0.8 }, "ARTWORK")
    f.timeBar:SetHeight(2)
    f.timeBar:SetPoint("BOTTOMLEFT", 1, 1)
    f:SetScript("OnUpdate", function(self)
        if not self.expires then return end
        local left = self.expires - GetTime()
        if left <= 0 then ns.UI.UpdateEmotePrompt(); return end
        self.timeBar:SetWidth(math.max(1, 318 * left / ns.EMOTE_WAIT))
    end)

    -- keys: take Enter and Esc, pass everything else on
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown and InCombatLockdown() then return end   -- can't change key handling in combat
        local used = ns.EmotePromptKey(key)
        self:SetPropagateKeyboardInput(not used)
    end)
    f:Hide()
    return f
end

local function UpdateEmotePrompt()
    local text, count, expires = ns.PendingEmote()
    if not text then
        if prompt then prompt:Hide() end
        return
    end
    prompt = prompt or CreatePrompt()
    prompt.preview:SetText(W.Color("muted", Short(S.me or "You")) .. " " .. text)
    prompt.count:SetText(count > 1 and ("1 of %d"):format(count) or "")
    prompt.expires = expires
    prompt:ClearAllPoints()
    if frame and frame:IsShown() then
        prompt:SetPoint("TOP", frame, "BOTTOM", 0, -6)
    else
        prompt:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    prompt:SetScale(ns.Setting("scale") or 1)
    if not prompt:IsShown() then
        prompt:Show()
        ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    end
end

ns.UI.UpdateEmotePrompt = UpdateEmotePrompt
ns.UI.Update     = Update
ns.UI.Reveal     = Reveal
ns.UI.ShowInvite = ShowInvite
ns.UI.HideInvite = HideInvite
