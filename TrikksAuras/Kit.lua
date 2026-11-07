-- Trikks Auras: small UI kit
-- A trimmed copy of Trikks Tweaks' flat look, so this addon works on its own
-- and still looks the same next to it. Lives in this addon's private table
-- (the second value of "..."), so it can never clash with Trikks Tweaks.
local _, TT = ...

function TT.IsSecret(v) return issecretvalue and issecretvalue(v) end
function TT.Print(msg) print("|cff33ff99Trikks Auras:|r " .. msg) end

-- name, icon, spellID from a spell ID or known spell name
function TT.SpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then return info.name, info.iconID, info.spellID end
    elseif GetSpellInfo then
        local name, _, icon, _, _, _, id = GetSpellInfo(spell)
        return name, icon, id
    end
end

local C = {
    bg     = { 0.06, 0.06, 0.07, 0.96 },   -- window background
    panel  = { 0.10, 0.10, 0.11, 1 },      -- buttons, boxes, title bar
    hover  = { 0.16, 0.16, 0.18, 1 },
    border = { 0.20, 0.20, 0.22, 1 },
    accent = { 0.20, 1.00, 0.60, 1 },      -- Trikks green (same as chat prefix)
    text   = { 0.92, 0.92, 0.92, 1 },
    dim    = { 0.50, 0.50, 0.53, 1 },
}
TT.C = C
local WHITE = "Interface\\Buttons\\WHITE8x8"

function TT.Flat(f, bg, border)
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
        f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
    end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg or C.panel))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

function TT.Label(parent, text, font)
    local l = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    l:SetText(text or "")
    l:SetJustifyH("LEFT")
    return l
end

function TT.Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    TT.Flat(b)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text or "")
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropColor(unpack(C.hover)); self:SetBackdropBorderColor(unpack(C.accent)) end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(C.panel)); self:SetBackdropBorderColor(unpack(C.border))
    end)
    b:SetScript("OnDisable", function(self) self:SetBackdropColor(0.07, 0.07, 0.08, 1) end)
    b:SetScript("OnEnable", function(self) self:SetBackdropColor(unpack(C.panel)) end)
    b:SetScript("OnClick", onClick)
    return b
end

function TT.Check(parent, text, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(14, 14)
    TT.Flat(cb, { 0.04, 0.04, 0.05, 1 })
    local fill = cb:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))
    cb:SetCheckedTexture(fill)
    cb.Text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.Text:SetText(text or "")
    -- make the label clickable too
    cb:SetHitRectInsets(0, -(cb.Text:GetStringWidth() + 12), -4, -4)
    cb:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    cb:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    -- old layouts assumed a 26px tall Blizzard checkbox; keep spacing similar
    return cb
end

function TT.EditBox(parent, w, h)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w or 150, h or 22)
    TT.Flat(e, { 0.04, 0.04, 0.05, 1 })
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

function TT.Scroll(parent)
    local s = CreateFrame("ScrollFrame", nil, parent)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    thumb:SetWidth(2)
    local function UpdateThumb()
        local range, h = s:GetVerticalScrollRange(), s:GetHeight()
        if range <= 0 or h <= 0 then thumb:Hide(); return end
        local th = math.max(16, h * h / (h + range))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 6, -(h - th) * (s:GetVerticalScroll() / range))
        thumb:Show()
    end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 26))
        self:SetVerticalScroll(v)
    end)
    s:SetScript("OnVerticalScroll", UpdateThumb)
    s:SetScript("OnScrollRangeChanged", UpdateThumb)
    s:SetScript("OnSizeChanged", UpdateThumb)
    return s
end

function TT.Stepper(parent, text, get, set, min, max, step)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(250, 24)
    local l = TT.Label(row, "")
    l:SetPoint("LEFT")
    function row.Refresh() l:SetText(text .. ":  |cffffffff" .. get() .. "|r") end
    local function Change(d)
        set(math.max(min, math.min(max, get() + d)))
        row.Refresh()
    end
    local plus = TT.Button(row, "+", 22, function() Change(IsShiftKeyDown() and step * 5 or step) end)
    plus:SetPoint("RIGHT", -10, 0)
    local minus = TT.Button(row, "-", 22, function() Change(IsShiftKeyDown() and -step * 5 or -step) end)
    minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    return row
end

function TT.Window(name, w, h, title, parent)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    TT.Flat(f, C.bg)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end          -- Esc closes it

    local line = f:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(2)
    line:SetColorTexture(unpack(C.accent))

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -9)
    t:SetTextColor(unpack(C.text))
    t:SetText(title and title:upper() or "")
    f.TitleText = t

    local sep = f:CreateTexture(nil, "OVERLAY")
    sep:SetPoint("TOPLEFT", 1, -26); sep:SetPoint("TOPRIGHT", -1, -26)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(C.border))

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, -2)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    x:SetTextColor(unpack(C.dim))
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.35, 0.35) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(C.dim)) end)
    close:SetScript("OnClick", function() f:Hide() end)
    return f
end
