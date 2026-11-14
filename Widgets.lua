-- Deathroller: shared look and widgets (panels, buttons, bars, inputs, scroll lists).
-- Theme: a pirate gambling den. Dark ship's-wood panels with planks, brass trim,
-- a skull on every title bar, gold for booty, red for the flag.
-- Drawn mostly with flat textures so it doesn't depend on Blizzard templates.

local _, ns = ...
local W = {}
ns.W = W

local FLAT = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"     -- the game's old-parchment quest-title font
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
W.FLAT, W.FONT, W.TITLE_FONT, W.SKULL = FLAT, FONT, TITLE_FONT, SKULL

-- Palette ------------------------------------------------------------------
local C = {
    bg       = { 0.14, 0.095, 0.06, 0.97 },  -- ship's wood
    plank    = { 0, 0, 0, 0.22 },            -- seams between planks
    header   = { 0.09, 0.06, 0.035, 1 },
    card     = { 0.96, 0.86, 0.62, 0.06 },   -- a hint of parchment
    cardHi   = { 0.96, 0.86, 0.62, 0.12 },
    border   = { 0.05, 0.03, 0.015, 1 },
    line     = { 0.85, 0.65, 0.30, 0.22 },   -- brass hairline
    accent   = { 0.86, 0.66, 0.30 },         -- brass
    red      = { 0.66, 0.15, 0.10 },         -- the flag
    gold     = { 1.00, 0.82, 0.30 },         -- booty
    text     = { 0.96, 0.91, 0.80 },         -- cream
    muted    = { 0.68, 0.59, 0.46 },
    win      = { 0.50, 0.86, 0.40 },
    loss     = { 0.96, 0.40, 0.30 },
    opp      = { 0.45, 0.82, 0.86 },         -- sea-glass teal: the other player
    warn     = { 0.98, 0.72, 0.28 },         -- amber
}
W.C = C

local function Hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
W.Hex = Hex
function W.Color(key, text) return Hex(C[key]) .. tostring(text) .. "|r" end

function W.Gold(n, signed)
    n = n or 0
    if n == 0 then return W.Color("muted", "-") end
    if not signed then return W.Color("gold", ns.Num(n) .. "g") end
    if n > 0 then return W.Color("win", "+" .. ns.Num(n) .. "g") end
    return W.Color("loss", "-" .. ns.Num(-n) .. "g")
end

-- Basic regions ---------------------------------------------------------------
function W.Tex(parent, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetTexture(FLAT)
    t:SetVertexColor(unpack(color))
    return t
end

-- Title font (Morpheus) for headings and big numbers, falling back to the normal font.
function W.SetFont(fs, size, flags, title)
    if not (title and fs:SetFont(TITLE_FONT, size, flags or "")) then
        fs:SetFont(FONT, size, flags or "")
    end
end

function W.Text(parent, size, color, opts)
    opts = opts or {}
    local fs = parent:CreateFontString(nil, opts.layer or "OVERLAY")
    W.SetFont(fs, size, opts.flags, opts.title)
    fs:SetTextColor(unpack(color or C.text))
    if opts.shadow ~= false then
        fs:SetShadowColor(0, 0, 0, 0.8)
        fs:SetShadowOffset(1, -1)
    end
    fs:SetJustifyH(opts.justify or "LEFT")
    fs:SetWordWrap(opts.wrap or false)
    return fs
end

-- 1px border around a frame, drawn with four textures.
function W.Border(f, color)
    color = color or C.border
    local b = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = W.Tex(f, color, "BORDER", 7)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
            t:SetPoint(side .. "LEFT", 0, 0); t:SetPoint(side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint("TOP" .. side, 0, 0); t:SetPoint("BOTTOM" .. side, 0, 0)
        end
        b[i] = t
    end
    function b:SetColor(r, g, bl, a) for _, t in ipairs(self) do t:SetVertexColor(r, g, bl, a or 1) end end
    f.border = b
    return b
end

-- A rounded-feeling "card": light fill plus a hairline border.
function W.Card(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = W.Tex(f, C.card)
    f.bg:SetAllPoints()
    W.Border(f, C.line)
    return f
end

-- Movable window with a header strip, accent line and close button.
function W.Panel(name, width, height, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)

    f.bg = W.Tex(f, C.bg)
    f.bg:SetAllPoints()
    -- plank seams across the window
    for y = 58, height - 10, 34 do
        local seam = W.Tex(f, C.plank, "BACKGROUND", 1)
        seam:SetHeight(1)
        seam:SetPoint("TOPLEFT", 1, -y); seam:SetPoint("TOPRIGHT", -1, -y)
    end
    W.Border(f)
    local inner = CreateFrame("Frame", nil, f)       -- brass inner trim
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("BOTTOMRIGHT", -1, 1)
    f.trim = W.Border(inner, { C.accent[1], C.accent[2], C.accent[3], 0.45 })

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(28)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.OnMoved then f:OnMoved() end
    end)
    local hbg = W.Tex(header, C.header, "ARTWORK")
    hbg:SetAllPoints()
    -- brass rail under the header: bright line over a dark one
    local rail = W.Tex(header, { C.accent[1], C.accent[2], C.accent[3], 1 }, "ARTWORK", 2)
    rail:SetHeight(2)
    rail:SetPoint("BOTTOMLEFT"); rail:SetPoint("BOTTOMRIGHT")
    local railShadow = W.Tex(f, { 0, 0, 0, 0.5 }, "ARTWORK")
    railShadow:SetHeight(2)
    railShadow:SetPoint("TOPLEFT", header, "BOTTOMLEFT"); railShadow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
    f.header = header

    local skull = header:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(SKULL)
    skull:SetSize(16, 16)
    skull:SetPoint("LEFT", 9, 1)

    f.title = W.Text(header, 16, C.gold, { title = true })
    f.title:SetPoint("LEFT", skull, "RIGHT", 6, 0)
    f.title:SetText(title or "")

    local close = CreateFrame("Button", nil, header)
    close:SetSize(28, 26)
    close:SetPoint("RIGHT", 0, 1)
    close.text = W.Text(close, 14, C.muted, { justify = "CENTER" })
    close.text:SetPoint("CENTER", 0, 0)
    close.text:SetText("x")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(C.loss)) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.muted)) end)
    close:SetScript("OnClick", function() if f.OnCloseClicked then f:OnCloseClicked() else f:Hide() end end)
    f.close = close

    -- Fade in when shown.
    local fade = f:CreateAnimationGroup()
    local a = fade:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15)
    f:HookScript("OnShow", function() fade:Play() end)

    return f
end

-- Buttons ------------------------------------------------------------------
local BUTTON_STYLES = {
    primary = { bg = { 0.60, 0.14, 0.09, 1 }, hi = { 0.74, 0.19, 0.12, 1 }, text = { 1, 0.93, 0.80 }, brass = true },
    success = { bg = { 0.20, 0.42, 0.20, 1 }, hi = { 0.26, 0.53, 0.25, 1 }, text = { 1, 0.95, 0.82 }, brass = true },
    neutral = { bg = { 0.26, 0.17, 0.10, 1 }, hi = { 0.34, 0.23, 0.13, 1 }, text = C.text,            brass = true },
    ghost   = { bg = { 1, 1, 1, 0 },          hi = { 0.96, 0.86, 0.62, 0.08 }, text = C.muted },
}

function W.Button(parent, text, width, height, style, onClick)
    local st = BUTTON_STYLES[style or "neutral"]
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 26)
    b.bg = W.Tex(b, st.bg, "BACKGROUND")
    b.bg:SetAllPoints()
    W.Border(b, st.brass and { C.accent[1], C.accent[2], C.accent[3], 0.7 } or { 0, 0, 0, 0 })
    b.text = W.Text(b, 12, st.text, { justify = "CENTER" })
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(text)
    b.style = st

    b:SetScript("OnEnter", function(self) if self:IsEnabled() then self.bg:SetVertexColor(unpack(self.style.hi)) end end)
    b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(unpack(self.style.bg)) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.4); self.bg:SetVertexColor(unpack(self.style.bg)) end)
    if onClick then b:SetScript("OnClick", onClick) end

    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

-- A row of toggle buttons where exactly one is selected.
-- options = { { value = "all", label = "All" }, ... }
function W.Segmented(parent, options, onChange, buttonWidth)
    local seg = CreateFrame("Frame", nil, parent)
    seg.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local w = opt.width or buttonWidth or 56
        local b = CreateFrame("Button", nil, seg)
        b:SetSize(w, 22)
        b:SetPoint("LEFT", x, 0)
        b.bg = W.Tex(b, C.card)
        b.bg:SetAllPoints()
        b.under = W.Tex(b, { C.accent[1], C.accent[2], C.accent[3], 1 }, "ARTWORK")
        b.under:SetHeight(2)
        b.under:SetPoint("BOTTOMLEFT"); b.under:SetPoint("BOTTOMRIGHT")
        b.text = W.Text(b, 11, C.muted, { justify = "CENTER" })
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(opt.label)
        b.value = opt.value
        b:SetScript("OnClick", function() seg:SetValue(opt.value, true) end)
        b:SetScript("OnEnter", function(self) if seg.value ~= self.value then self.bg:SetVertexColor(unpack(C.cardHi)) end end)
        b:SetScript("OnLeave", function(self) if seg.value ~= self.value then self.bg:SetVertexColor(unpack(C.card)) end end)
        seg.buttons[i] = b
        x = x + w + 2
    end
    seg:SetSize(x - 2, 22)

    function seg:SetValue(value, fromClick)
        self.value = value
        for _, b in ipairs(self.buttons) do
            local on = b.value == value
            b.under:SetShown(on)
            b.text:SetTextColor(unpack(on and C.text or C.muted))
            b.bg:SetVertexColor(unpack(on and C.cardHi or C.card))
        end
        if fromClick and onChange then onChange(value) end
    end
    seg:SetValue(options[1].value)
    return seg
end

-- Text input with placeholder text and an accent border while focused.
function W.Input(parent, width, height, placeholder)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, height or 28)
    box:SetAutoFocus(false)
    box:SetFont(FONT, 13, "")
    box:SetTextColor(unpack(C.text))
    box:SetTextInsets(10, 10, 0, 0)
    box.bg = W.Tex(box, { 0, 0, 0, 0.45 })
    box.bg:SetAllPoints()
    local border = W.Border(box, C.line)

    box.placeholder = W.Text(box, 12, C.muted)
    box.placeholder:SetPoint("LEFT", 10, 0)
    box.placeholder:SetPoint("RIGHT", -10, 0)
    box.placeholder:SetText(placeholder or "")

    function box:SetPlaceholder(t) self.placeholder:SetText(t) end
    function box:RefreshPlaceholder()
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    function box:SetHighlighted(on)
        if on then border:SetColor(C.accent[1], C.accent[2], C.accent[3], 1)
        else border:SetColor(unpack(C.line)) end
    end
    box:SetScript("OnEditFocusGained", function(self) self:RefreshPlaceholder(); self:SetHighlighted(true) end)
    box:SetScript("OnEditFocusLost", function(self) self:RefreshPlaceholder(); self:SetHighlighted(self.keepHighlight) end)
    box:SetScript("OnTextChanged", function(self) self:RefreshPlaceholder(); if self.OnChanged then self:OnChanged() end end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Thin countdown bar that drains and shifts green -> amber -> red.
function W.TimerBar(parent, width, total)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, 6)
    bar:SetStatusBarTexture(FLAT)
    bar:SetMinMaxValues(0, total)
    local bg = W.Tex(bar, { 1, 1, 1, 0.08 })
    bg:SetAllPoints()

    bar.label = W.Text(bar, 11, C.muted)
    bar.label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
    bar.secs = W.Text(bar, 11, C.text, { justify = "RIGHT" })
    bar.secs:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)

    -- Pass the GetTime() at which it runs out; returns seconds left.
    function bar:SetExpiry(expires)
        local left = math.max(0, expires - GetTime())
        self:SetValue(left)
        local p = left / total
        if p > 0.5 then self:SetStatusBarColor(unpack(C.win))
        elseif p > 0.2 then self:SetStatusBarColor(0.95, 0.70, 0.20)
        else self:SetStatusBarColor(unpack(C.loss)) end
        self.secs:SetText(("%ds"):format(math.ceil(left)))
        return left
    end
    return bar
end

-- Virtualised scrolling list: a fixed set of row frames that are re-filled as you scroll.
-- columns = { { key = "date", title = "When", width = 80, justify = "LEFT" }, ... }
-- The caller sets list:SetData(rows) where each row is { cells = { ... }, ...anything }.
function W.ScrollList(parent, width, rowCount, columns, opts)
    opts = opts or {}
    local ROW_H = opts.rowHeight or 22
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, 22 + rowCount * ROW_H)
    list.data, list.offset = {}, 0

    -- header
    local x = 10
    for _, col in ipairs(columns) do
        local h = W.Text(list, 10, C.muted, { justify = col.justify })
        h:SetPoint("TOPLEFT", x, -6)
        h:SetWidth(col.width)
        h:SetText((col.title or ""):upper())
        x = x + col.width
    end
    local hl = W.Tex(list, C.line, "ARTWORK")
    hl:SetHeight(1)
    hl:SetPoint("TOPLEFT", 0, -21); hl:SetPoint("TOPRIGHT", 0, -21)

    list.rows = {}
    for r = 1, rowCount do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -22 - (r - 1) * ROW_H)
        row:SetPoint("RIGHT", list, "RIGHT", -10, 0)
        row.stripe = W.Tex(row, { 1, 1, 1, (r % 2 == 0) and 0.025 or 0 })
        row.stripe:SetAllPoints()
        row.hover = W.Tex(row, { 1, 1, 1, 0.06 }, "ARTWORK")
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.sel = W.Tex(row, { C.accent[1], C.accent[2], C.accent[3], 0.18 }, "ARTWORK", 1)
        row.sel:SetAllPoints()
        row.sel:Hide()
        row.cells = {}
        local cx = 10
        for i, col in ipairs(columns) do
            local fs = W.Text(row, 12, C.text, { justify = col.justify })
            fs:SetPoint("LEFT", cx, 0)
            fs:SetWidth(col.width - 4)
            row.cells[i] = fs
            cx = cx + col.width
        end
        row:SetScript("OnEnter", function(self)
            if not self.item then return end
            self.hover:Show()
            if opts.onEnter then opts.onEnter(self, self.item) end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if not self.item then return end
            if opts.selectable then
                list.selectedKey = (list.selectedKey ~= self.item.key) and self.item.key or nil
                list:Refresh()
            end
            if opts.onClick then opts.onClick(self.item) end
        end)
        list.rows[r] = row
    end

    list.empty = W.Text(list, 12, C.muted, { justify = "CENTER", wrap = true })
    list.empty:SetPoint("TOP", 0, -22 - ROW_H * 1.5)
    list.empty:SetWidth(width - 40)

    -- thin scrollbar on the right
    local track = W.Tex(list, { 1, 1, 1, 0.05 }, "ARTWORK")
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", -2, -24)
    track:SetPoint("BOTTOMRIGHT", -2, 2)
    local thumb = W.Tex(list, { C.accent[1], C.accent[2], C.accent[3], 0.8 }, "OVERLAY")
    thumb:SetWidth(3)
    list.track, list.thumb = track, thumb

    function list:MaxOffset() return math.max(0, #self.data - rowCount) end

    function list:Refresh()
        for r, row in ipairs(self.rows) do
            local item = self.data[self.offset + r]
            row.item = item
            for i, fs in ipairs(row.cells) do fs:SetText(item and item.cells[i] or "") end
            row:EnableMouse(item ~= nil)
            row.sel:SetShown(item ~= nil and item.key ~= nil and item.key == self.selectedKey)
        end
        local max = self:MaxOffset()
        track:SetShown(max > 0)
        thumb:SetShown(max > 0)
        if max > 0 then
            local trackH = rowCount * ROW_H - 4
            local thumbH = math.max(16, trackH * rowCount / #self.data)
            thumb:SetHeight(thumbH)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", -2, -24 - (trackH - thumbH) * (self.offset / max))
        end
    end

    function list:SetData(data, emptyText)
        self.data = data or {}
        -- drop the selection if that row is gone
        local found = false
        for _, item in ipairs(self.data) do if item.key ~= nil and item.key == self.selectedKey then found = true end end
        if not found then self.selectedKey = nil end
        self.offset = math.min(self.offset, self:MaxOffset())
        self.empty:SetText(#self.data == 0 and (emptyText or "") or "")
        self:Refresh()
    end

    function list:GetSelected()
        for _, item in ipairs(self.data) do if item.key ~= nil and item.key == self.selectedKey then return item end end
    end

    function list:ScrollTo(offset)
        self.offset = math.max(0, math.min(self:MaxOffset(), offset))
        self:Refresh()
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(self.offset - delta * (IsShiftKeyDown() and rowCount or 3))
    end)
    return list
end

-- Checkbox with a label and an optional muted description underneath.
function W.Check(parent, width, label, desc, onChange)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(width, desc and 40 or 22)

    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(16, 16)
    c.box:SetPoint("TOPLEFT", 0, -2)
    c.box.bg = W.Tex(c.box, { 0, 0, 0, 0.5 })
    c.box.bg:SetAllPoints()
    local border = W.Border(c.box, C.line)
    c.mark = W.Tex(c.box, { C.accent[1], C.accent[2], C.accent[3], 1 }, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)

    c.label = W.Text(c, 12, C.text)
    c.label:SetPoint("TOPLEFT", 26, -3)
    c.label:SetPoint("RIGHT", 0, 0)
    c.label:SetText(label)
    if desc then
        c.desc = W.Text(c, 10, C.muted, { wrap = true })
        c.desc:SetPoint("TOPLEFT", 26, -19)
        c.desc:SetWidth(width - 26)
        c.desc:SetText(desc)
        c:SetHeight(22 + (tonumber(c.desc:GetStringHeight()) or 12))
    end

    function c:SetChecked(on)
        self.checked = on and true or false
        self.mark:SetShown(self.checked)
    end
    c:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        ns.Sound(self.checked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if onChange then onChange(self.checked) end
    end)
    c:SetScript("OnEnter", function() border:SetColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    c:SetScript("OnLeave", function() border:SetColor(unpack(C.line)) end)
    c:SetChecked(false)
    return c
end

-- Small uppercase section heading with a hairline under it.
function W.Section(parent, text, width)
    local fs = W.Text(parent, 14, C.gold, { title = true })
    fs:SetText(text)
    local line = W.Tex(parent, C.line, "ARTWORK")
    line:SetHeight(1)
    line:SetWidth(width)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    return fs
end

-- Setting changes fan out to every window that cares (see ns.SetSetting in Core).
local listeners = {}
function ns.OnSetting(fn) listeners[#listeners + 1] = fn end
ns.UI.OnSettingChanged = function(key, value)
    for _, fn in ipairs(listeners) do fn(key, value) end
end

-- Apply the window-size setting to one of our windows.
function W.ApplyScale(f)
    if f then f:SetScale(ns.Setting("scale") or 1) end
end

-- The pot: gold coin + big amount, centred. SetAmount(0) shows "Friendly game".
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
function W.Pot(parent, size, label)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(260, size + (label and 16 or 0))
    if label then
        p.label = W.Text(p, 10, C.muted, { justify = "CENTER" })
        p.label:SetPoint("TOP", 0, 0)
        p.label:SetText(label)
    end
    p.amount = W.Text(p, size, C.gold, { justify = "CENTER", flags = "OUTLINE", title = true })
    p.amount:SetPoint("TOP", 8, label and -14 or 0)
    p.coin = p:CreateTexture(nil, "ARTWORK")
    p.coin:SetTexture(COIN)
    p.coin:SetSize(size * 0.8, size * 0.8)
    p.coin:SetPoint("RIGHT", p.amount, "LEFT", -5, 0)

    function p:SetAmount(n)
        if n and n > 0 then
            W.SetFont(self.amount, size, "OUTLINE", true)
            self.amount:SetTextColor(unpack(C.gold))
            self.amount:SetText(ns.Num(n) .. "g")
            self.amount:SetPoint("TOP", math.floor(size * 0.4), label and -14 or 0)
            self.coin:Show()
        else
            W.SetFont(self.amount, math.floor(size * 0.55), "", false)
            self.amount:SetTextColor(unpack(C.muted))
            self.amount:SetText("Friendly game - no gold")
            self.amount:SetPoint("TOP", 0, label and -16 or -2)
            self.coin:Hide()
        end
    end
    return p
end
