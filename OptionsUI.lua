-- Deathroller: options. The same controls are built in two places:
--   * our own window (/dr options, right-click the minimap button)
--   * the game's Options > AddOns > Deathroller page
-- Both read and write the same settings, so a change in one shows in the other.

local _, ns = ...
local W, C = ns.W, ns.W.C

local frame                 -- our options window
local blizzPanel            -- the Options > AddOns page
local controls = {}         -- { key = "autoFocus", ctl = <checkbox or segmented> }, ...

local COL_W = 280

local function Track(key, ctl) controls[#controls + 1] = { key = key, ctl = ctl } end

local function Check(parent, key, label, desc)
    local c = W.Check(parent, COL_W, label, desc, function(on) ns.SetSetting(key, on) end)
    Track(key, c)
    return c
end

local function Choice(parent, key, label, options, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COL_W, 24)
    row.label = W.Text(row, 12, C.text)
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetText(label)
    row.seg = W.Segmented(row, options, function(v) ns.SetSetting(key, v) end, width)
    row.seg:SetPoint("RIGHT", 0, 0)
    Track(key, row.seg)
    return row
end

-- Lay out a column: each item is placed under the previous one.
local function Stack(parent, x, y, items)
    local prev
    for _, item in ipairs(items) do
        local widget, gap = item[1], item[2] or 8
        widget:ClearAllPoints()
        if prev then
            widget:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
        else
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        end
        prev = widget
    end
end

local function RefreshOptions()
    for _, entry in ipairs(controls) do
        local key, ctl = entry.key, entry.ctl
        if key == "debug" then
            ctl:SetChecked(ns.GetDB().debug)
        elseif ctl.SetChecked then
            ctl:SetChecked(ns.Setting(key))
        else
            ctl:SetValue(ns.Setting(key))
        end
    end
end

local function RestoreDefaults()
    for key, value in pairs(ns.DEFAULTS) do
        if key ~= "minimapAngle" then ns.SetSetting(key, value) end
    end
    RefreshOptions()
end

local function ResetPositions()
    local DB = ns.GetDB()
    DB.pos, DB.statsPos = nil, nil
    for _, name in ipairs({ "GupsDeathrollerFrame", "GupsDeathrollerStatsFrame", "GupsDeathrollerOptionsFrame" }) do
        local win = _G[name]
        if win then win:ClearAllPoints(); win:SetPoint("CENTER", 0, 60) end
    end
    ns.SetSetting("minimapAngle", ns.DEFAULTS.minimapAngle)
    ns.Print("Window positions reset.")
end

-- Build the two columns of options into `parent`, starting `top` pixels down.
local function BuildContent(parent, left, top)
    -- Left column
    local turn = W.Section(parent, "Your turn", COL_W)
    local autoFocus = Check(parent, "autoFocus", "Auto-focus the roll box",
        "Puts your cursor in the roll box when your turn starts. Skipped in combat or while you're typing elsewhere. Esc gives your keys back.")
    local prefill = Check(parent, "prefillRoll", "Pre-fill \"/roll \"",
        "Starts the box with /roll so you only type the number.")

    local ann = W.Section(parent, "Announcements", COL_W)
    local annChal = Check(parent, "announceChallenges", "Announce challenges",
        "Your character emotes when you challenge someone or accept a challenge, so people nearby can watch.")
    local annRes = Check(parent, "announceResults", "Announce button on results",
        "Adds an Announce button to the result screen, to share who won. Its arrow picks Emote, Party or Guild for that game.")
    local annWhere = Choice(parent, "announceChannel", "Results go to", {
        { value = "EMOTE", label = "Emote", width = 52 },
        { value = "PARTY", label = "Party", width = 48 },
        { value = "GUILD", label = "Guild", width = 48 },
    })
    local annMile = Check(parent, "announceMilestones", "Include milestones",
        "Adds streaks, your biggest pot and other milestones to that announcement.")

    local spectate = Check(parent, "allowSpectators", "Let others watch your games",
        "Players with the add-on can watch your games live, and your games show in your guild's and group's Live tab. Turn off to keep them private.")

    Stack(parent, left, top, {
        { turn }, { autoFocus, 12 }, { prefill, 6 },
        { ann, 18 }, { annChal, 12 }, { annRes, 6 }, { annWhere, 8 }, { annMile, 8 }, { spectate, 6 },
    })

    -- Right column
    local ui = W.Section(parent, "Interface", COL_W)
    local minimap = Check(parent, "minimap", "Show minimap button",
        "Left-click: game or stats. Right-click: options. Drag to move it.")
    local sound = Check(parent, "sound", "Sounds", "Challenge, your turn, dice and result sounds.")
    local closeCall = Check(parent, "closeCallFx", "Close-call effects",
        "When the roll gets down to 10 or less: the number pulses, the frame turns amber then red, and a warning sound plays.")
    local tips = Check(parent, "tips", "Tips in chat", "Reminders like standing close together so both of you see every roll.")
    local scale = Choice(parent, "scale", "Window size", {
        { value = 0.9,  label = "90%",  width = 44 },
        { value = 1,    label = "100%", width = 48 },
        { value = 1.15, label = "115%", width = 48 },
        { value = 1.3,  label = "130%", width = 48 },
    })

    local adv = W.Section(parent, "Troubleshooting", COL_W)
    local debug = W.Check(parent, COL_W, "Debug messages",
        "Prints what the add-on sends, receives and reads. Same as /dr debug.", function(on)
            ns.GetDB().debug = on
        end)
    Track("debug", debug)

    Stack(parent, left + COL_W + 20, top, {
        { ui }, { minimap, 12 }, { sound, 6 }, { closeCall, 6 }, { tips, 6 }, { scale, 8 },
        { adv, 18 }, { debug, 12 },
    })
end

---------------------------------------------------------------------------
-- Our own window
---------------------------------------------------------------------------

local function CreateOptionsFrame()
    local f = W.Panel("GupsDeathrollerOptionsFrame", 2 * COL_W + 60, 486, "Gup's Deathroller options")
    f:SetPoint("CENTER", 0, 60)
    tinsert(UISpecialFrames, "GupsDeathrollerOptionsFrame")

    BuildContent(f, 20, -46)

    local resetPos = W.Button(f, "Reset window positions", 170, 24, "ghost", ResetPositions)
    resetPos:SetPoint("BOTTOMLEFT", 14, 14)
    local defaults = W.Button(f, "Restore defaults", 130, 24, "ghost", RestoreDefaults)
    defaults:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
    local done = W.Button(f, "Done", 100, 24, "primary", function() f:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -14, 14)

    W.ApplyScale(f)
    f:Hide()
    frame = f
end

local function ToggleOptions()
    if not frame then CreateOptionsFrame() end
    if frame:IsShown() then frame:Hide(); return end
    RefreshOptions()
    frame:Show()
end

ns.OnSetting(function(key)
    if key == "scale" and frame then W.ApplyScale(frame) end
    RefreshOptions()
end)

---------------------------------------------------------------------------
-- Options > AddOns > Deathroller
---------------------------------------------------------------------------

local function RegisterBlizzardCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()

    local skull = panel:CreateTexture(nil, "ARTWORK")
    skull:SetTexture(W.SKULL)
    skull:SetSize(20, 20)
    skull:SetPoint("TOPLEFT", 16, -16)
    local title = W.Text(panel, 22, C.gold, { title = true })
    title:SetPoint("LEFT", skull, "RIGHT", 8, 0)
    title:SetText("Doctor Gup's Deathroller")
    local version = W.Text(panel, 11, C.muted)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
    panel:SetScript("OnShow", function()
        version:SetText("version " .. tostring(ns.VERSION))
        RefreshOptions()
    end)

    BuildContent(panel, 18, -56)

    local resetPos = W.Button(panel, "Reset window positions", 170, 24, "neutral", ResetPositions)
    resetPos:SetPoint("TOPLEFT", 18, -486)
    local defaults = W.Button(panel, "Restore defaults", 130, 24, "neutral", RestoreDefaults)
    defaults:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)

    -- The Settings panel's own "Defaults" button and refreshes call these on canvas pages.
    panel.OnDefault = RestoreDefaults
    panel.OnRefresh = RefreshOptions
    panel.OnCommit = function() end

    local ok = pcall(function()
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Doctor Gup's Deathroller")
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    end)
    if ok then blizzPanel = panel else ns.Debug("couldn't add Deathroller to the game's AddOns options") end
end

ns.UI.ToggleOptions  = ToggleOptions
ns.UI.RefreshOptions = RefreshOptions
ns.UI.InitOptions    = RegisterBlizzardCategory
