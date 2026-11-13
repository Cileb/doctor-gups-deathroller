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
    card.name:SetPoint("TOPLEFT", 10, -24)
    card.name:SetPoint("RIGHT", -8, 0)
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
    local f = W.Panel("GupsDeathrollerFrame", 320, 386, "Deathroll")
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

    -- the pot, front and centre under the players
    f.potBg = W.Tex(f, { C.gold[1], C.gold[2], C.gold[3], 0.07 }, "BACKGROUND", 1)
    f.potBg:SetPoint("TOPLEFT", 12, -98)
    f.potBg:SetPoint("TOPRIGHT", -12, -98)
    f.potBg:SetHeight(34)
    f.potLabel = W.Text(f, 10, C.gold, { justify = "LEFT" })
    f.potLabel:SetPoint("LEFT", f.potBg, "LEFT", 10, 0)
    f.potLabel:SetText("POT")
    f.pot = W.Pot(f, 22)
    f.pot:SetPoint("TOP", 0, -104)

    -- centre: label, big number, status
    f.rangeLabel = W.Text(f, 10, C.muted, { justify = "CENTER" })
    f.rangeLabel:SetPoint("TOP", 0, -142)

    f.glow = W.Tex(f, { 1, 1, 1, 1 }, "ARTWORK")
    f.glow:SetSize(220, 56)
    f.glow:SetPoint("TOP", 0, -154)
    f.glow:SetAlpha(0)
    local flash = f.glow:CreateAnimationGroup()
    local fa = flash:CreateAnimation("Alpha")
    fa:SetFromAlpha(0.35); fa:SetToAlpha(0); fa:SetDuration(0.7)
    f.flash = flash

    f.big = W.Text(f, 44, C.text, { justify = "CENTER", flags = "OUTLINE", title = true })
    f.big:SetPoint("TOP", 0, -156)

    f.dice = f:CreateTexture(nil, "OVERLAY")
    f.dice:SetTexture(DICE_TEXTURE)
    f.dice:SetSize(30, 30)
    f.dice:SetPoint("RIGHT", f.big, "LEFT", -10, 0)
    f.dice:Hide()

    f.status = W.Text(f, 12, C.muted, { justify = "CENTER" })
    f.status:SetPoint("TOP", 0, -208)
    f.status:SetWidth(296)

    -- pending: countdown
    f.timer = W.TimerBar(f, 296, ns.INVITE_TIMEOUT)
    f.timer:SetPoint("TOP", 0, -250)
    f.timer.label:SetText("Challenge expires")
    f.timer:SetScript("OnUpdate", function(self)
        local g = S.game
        if g and g.state == "pending" and g.expires then self:SetExpiry(g.expires) end
    end)

    -- active: roll input
    f.input = W.Input(f, 296, 30, "")
    f.input:SetPoint("TOP", 0, -234)
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
    f.series:SetPoint("TOP", 0, -236)
    f.milestones = W.Text(f, 11, C.gold, { justify = "CENTER" })
    f.milestones:SetPoint("TOP", 0, -256)
    f.milestones:SetWidth(296)

    -- roll ladder
    f.ladderLabel = W.Text(f, 10, C.muted)
    f.ladderLabel:SetPoint("TOPLEFT", 14, -278)
    f.ladder = W.Text(f, 13, C.text, { wrap = true })
    f.ladder:SetPoint("TOPLEFT", 14, -294)
    f.ladder:SetWidth(292)
    f.ladder:SetSpacing(4)

    -- footer buttons (shown per state)
    f.forfeit = W.Button(f, "Forfeit", 90, 26, "ghost", function() ns.Forfeit() end)
    f.forfeit:SetPoint("BOTTOMLEFT", 12, 12)
    f.statsBtn = W.Button(f, "Stats", 90, 26, "ghost", function() ns.UI.ToggleStats() end)
    f.statsBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.cancel = W.Button(f, "Cancel challenge", 296, 26, "neutral", function() ns.Forfeit() end)
    f.cancel:SetPoint("BOTTOM", 0, 12)
    f.rematch = W.Button(f, "Rematch", 140, 26, "primary", function() ns.Rematch() end)
    f.rematch:SetPoint("BOTTOMLEFT", 12, 12)
    f.closeBtn = W.Button(f, "Close", 140, 26, "neutral", function() f:Hide() end)
    f.closeBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.announce = W.Button(f, "Announce", 96, 26, "neutral", function() ns.AnnounceResult() end)
    f.announce:SetPoint("BOTTOM", 0, 12)
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

local function UpdateLadder()
    local f, g = frame, S.game
    local oppFirst = FirstName(g.opponent)
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
    while #parts > 12 do table.remove(parts, 2); parts[2] = W.Color("muted", "...") end
    f.ladder:SetText(table.concat(parts, W.Color("muted", "  >  ")))
end

local function ShowOnly(f, shown)
    for _, key in ipairs({ "timer", "input", "series", "milestones", "forfeit", "statsBtn", "cancel", "rematch", "closeBtn", "announce" }) do
        f[key]:SetShown(shown[key] == true)
    end
end

local function Update()
    local f, g = frame, S.game
    if not f then return end
    if not g then f:Hide(); return end
    if f.revealing then f:Show(); return end          -- the dice animation owns the window

    local opp = Short(g.opponent)
    f.me.name:SetText(Short(S.me))
    f.opp.name:SetText(opp)
    f.pot:SetAmount(g.wager)
    f.potLabel:SetShown(g.wager > 0)
    f.potBg:SetShown(g.wager > 0)
    UpdateLadder()
    W.SetFont(f.big, 44, "OUTLINE", true)
    f.dice:Hide()

    f.potLabel:SetText("POT")
    if g.state == "pending" then
        ShowOnly(f, { timer = true, cancel = true })
        f.me:SetActive(false); f.opp:SetActive(false)
        f.rangeLabel:SetText("STARTING ROLL")
        f.big:SetText(Num(g.max))
        f.big:SetTextColor(unpack(C.muted))
        f.status:SetText(("Waiting for %s to accept..."):format(W.Color("opp", FirstName(opp))))
        f.timer:SetExpiry(g.expires or GetTime())

    elseif g.state == "active" or g.state == "ending" then
        ShowOnly(f, { input = true, forfeit = true, statsBtn = true })
        local mine = ns.IsMyTurn()
        f.me:SetActive(mine, "YOUR TURN")
        f.opp:SetActive(not mine and g.state == "active", "ROLLING")
        f.rangeLabel:SetText("ROLL 1 TO")
        f.big:SetText(Num(g.max))
        f.big:SetTextColor(unpack(mine and C.gold or C.text))
        if mine then
            f.status:SetText(W.Color("win", "Your turn!") .. "  Type the command below.")
            f.input:Enable()
            f.input:SetPlaceholder(("/roll %d   then press Enter"):format(g.max))
        else
            f.status:SetText(("Waiting for %s to /roll %d..."):format(W.Color("opp", FirstName(opp)), g.max))
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
        ShowOnly(f, { series = true, milestones = true, rematch = true, closeBtn = true, announce = canAnnounce })
        f.rematch:SetWidth(canAnnounce and 96 or 140)
        f.closeBtn:SetWidth(canAnnounce and 96 or 140)
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
    f.name:SetText(Short(inv.from))
    f.pot:SetAmount(inv.wager)
    f.potBg:SetShown(inv.wager > 0)
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
    elseif key == "announceResults" then
        if frame and frame:IsShown() then Update() end
    elseif key == "autoFocus" or key == "prefillRoll" then
        if S.game then S.game.preparedTurn = nil end
        if frame and frame:IsShown() then Update() end
    end
end)

ns.UI.Update     = Update
ns.UI.Reveal     = Reveal
ns.UI.ShowInvite = ShowInvite
ns.UI.HideInvite = HideInvite
