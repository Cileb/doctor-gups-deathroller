-- Deathroller: minimap button (drag around the edge; hide it in /dr options or with /dr minimap).

local _, ns = ...
local W, C = ns.W, ns.W.C

local button
local ICON = "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
local atan2 = math.atan2 or math.atan

local function Place()
    local angle = math.rad(ns.Setting("minimapAngle") or 215)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ShowTooltip(self)
    local DB = ns.GetDB()
    local s = DB.stats
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Doctor Gup's Deathroller", C.accent[1] + 0.1, C.accent[2] + 0.2, C.accent[3] + 0.2)
    GameTooltip:AddLine(("Record %d-%d   Net %s"):format(s.wins, s.losses, W.Gold(s.goldWon - s.goldLost, true)), 1, 1, 1)
    local owedToMe, iOwe = ns.DebtTotals()
    if owedToMe > 0 or iOwe > 0 then
        GameTooltip:AddLine(("Owed to you: %s    You owe: %s"):format(
            owedToMe > 0 and W.Color("win", ns.Num(math.floor(owedToMe + 0.5)) .. "g") or "-",
            iOwe > 0 and W.Color("loss", ns.Num(math.floor(iOwe + 0.5)) .. "g") or "-"), 1, 1, 1)
    end
    local g = ns.state.game
    if g and g.state ~= "done" then
        GameTooltip:AddLine(("In a deathroll vs %s"):format(ns.Short(g.opponent)), C.gold[1], C.gold[2], C.gold[3])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(g and "Left-click: show the game" or "Left-click: stats", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function Create()
    if button or not Minimap then return end
    local b = CreateFrame("Button", "GupsDeathrollerMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    -- standard round minimap-button look
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ns.UI.ToggleOptions()
        elseif ns.state.game then ns.UI.Update()
        else ns.UI.ToggleStats() end
    end)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)

    -- drag around the minimap edge
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(atan2(py / scale - my, px / scale - mx))
            ns.GetDB().settings.minimapAngle = angle % 360
            Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    button = b
    Place()
end

local function Refresh()
    if ns.Setting("minimap") then
        Create()
        if button then Place(); button:Show() end
    elseif button then
        button:Hide()
    end
end

ns.OnSetting(function(key)
    if key == "minimap" or key == "minimapAngle" then Refresh() end
end)

ns.UI.InitMinimap = Refresh
