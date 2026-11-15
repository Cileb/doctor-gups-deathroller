-- Deathroller: banner on the trade window, shown only when you have a deathroll
-- debt with the person you're trading. Tracks the gold in the trade as it changes.

local _, ns = ...
local W, C = ns.W, ns.W.C
local Short, FirstName, Num = ns.Short, ns.FirstName, ns.Num

local banner

local function Ago(t)
    local s = time() - (t or time())
    if s < 3600 then return ("%d min ago"):format(math.max(1, math.floor(s / 60))) end
    if s < 86400 then return ("%d h ago"):format(math.floor(s / 3600)) end
    return ("%d days ago"):format(math.floor(s / 86400))
end

local function G(n) return Num(math.floor(n + 0.5)) .. "g" end

local function Create()
    local b = CreateFrame("Frame", "GupsDeathrollerTradeBanner", UIParent)
    b:SetSize(340, 104)
    b:SetFrameStrata("HIGH")
    b.bg = W.Tex(b, C.bg)
    b.bg:SetAllPoints()
    W.Border(b)
    local inner = CreateFrame("Frame", nil, b)
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)
    W.Border(inner, { C.accent[1], C.accent[2], C.accent[3], 0.6 })
    local rail = W.Tex(b, { C.accent[1], C.accent[2], C.accent[3], 1 }, "ARTWORK")
    rail:SetHeight(2)
    rail:SetPoint("TOPLEFT", 1, -1); rail:SetPoint("TOPRIGHT", -1, -1)

    b.skull = b:CreateTexture(nil, "ARTWORK")
    b.skull:SetTexture(W.SKULL)
    b.skull:SetSize(18, 18)
    b.skull:SetPoint("TOPLEFT", 10, -10)
    b.headline = W.Text(b, 17, C.gold, { title = true })
    b.headline:SetPoint("LEFT", b.skull, "RIGHT", 6, 0)
    b.headline:SetPoint("RIGHT", -10, 0)
    b.sub = W.Text(b, 10, C.muted)
    b.sub:SetPoint("TOPLEFT", 12, -32)

    b.status = W.Text(b, 12, C.text)
    b.status:SetPoint("TOPLEFT", 12, -50)
    b.status:SetPoint("RIGHT", -12, 0)

    b.count = W.Check(b, 200, "Count gold toward the debt", nil, function(on)
        if ns.state.trade then ns.state.trade.count = on end
    end)
    b.count:SetPoint("BOTTOMLEFT", 10, 8)

    b:Hide()
    banner = b
end

local function Place()
    banner:ClearAllPoints()
    if TradeFrame and TradeFrame:IsShown() then
        banner:SetWidth(math.max(300, TradeFrame:GetWidth() or 340))
        banner:SetPoint("BOTTOM", TradeFrame, "TOP", 0, 6)
    else
        banner:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
end

local function Refresh()
    local t = ns.state.trade
    if not banner or not banner:IsShown() or not t then return end
    local debt, rec = ns.GetDebt(t.partner)
    local who = Short(t.partner)

    if debt == 0 then                                     -- settled while the window is open
        banner.headline:SetText(W.Color("win", "All square with " .. FirstName(who)))
        banner.sub:SetText("No deathroll debt left.")
        banner.status:SetText("")
        banner.count:Hide()
        return
    end

    local games = rec and rec.games or 0
    banner.sub:SetText(("From %d deathroll%s, %s"):format(games, games == 1 and "" or "s", Ago(rec and rec.last)))
    banner.count:Show()
    banner.count:SetChecked(t.count)

    if debt > 0 then
        banner.headline:SetText(("%s owes you %s"):format(FirstName(who), G(debt)))
        local get = t.get / 10000
        if get <= 0 then
            banner.status:SetText(W.Color("muted", ("Waiting for %s to put gold in the trade..."):format(FirstName(who))))
        elseif get + 0.0001 >= debt then
            banner.status:SetText(W.Color("win", ("They're putting in %s. That covers it."):format(G(get))))
        else
            banner.status:SetText(W.Color("warn", ("They're putting in %s, %s short."):format(G(get), G(debt - get))))
        end
    else
        local owe = -debt
        banner.headline:SetText(("You owe %s %s"):format(FirstName(who), G(owe)))
        local give = t.give / 10000
        if give <= 0 then
            banner.status:SetText(W.Color("muted", ("Put %s in the trade's gold box."):format(G(math.ceil(owe)))))
        elseif give + 0.0001 >= owe then
            banner.status:SetText(W.Color("win", ("You're putting in %s. That covers it."):format(G(give))))
        else
            banner.status:SetText(W.Color("warn", ("You're putting in %s, %s short."):format(G(give), G(owe - give))))
        end
    end
end

local function ShowTrade(t)
    if not banner then Create() end
    Place()
    banner:Show()
    Refresh()
end

local function HideTrade()
    if banner then banner:Hide() end
end

ns.OnSetting(function(key) if key == "scale" and banner then W.ApplyScale(banner) end end)
ns.UI.ShowTrade    = ShowTrade
ns.UI.HideTrade    = HideTrade
ns.UI.RefreshTrade = Refresh
