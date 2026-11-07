-- Module: Centered Auras
-- Whitelisted auras on YOU shown as a row of icons that stays centred on its
-- anchor (1 icon = middle, 2 = either side of the middle, ...).
-- Standalone addon (Trikks Auras): needs nothing else. The UI kit is in Kit.lua.
local ADDON, TT = ...
-- M.db = saved settings (TrikksAurasDB), M.enabled = on/off; filled in on ADDON_LOADED
local M = { enabled = false }
-- shared with the other files of this addon (Reminders.lua)
TT.onReady = {}         -- functions(db) run once the saved settings are loaded
TT.extraTabs = {}       -- extra pages in the window: { title, build = function(win) return page end }
local DEFAULTS = {
    enabled = true,                      -- installing the addon is the opt-in
    spells = {}, size = 40, spacing = 4, x = 0, y = -150, layouts = {},
    vertical = false, showSwipe = true, showNumbers = true, showStacks = true,
    alpha = 100, scale = 100,
}
local testMode = false
local SpellInfo, IsSecret = TT.SpellInfo, TT.IsSecret
local function Num(v) if v == nil or IsSecret(v) then return 0 end return tonumber(v) or 0 end

local function GetAura(id)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if ok and a and not IsSecret(a) then return a end
end

-- In combat this client hides most aura data from addons ("secret values"):
-- asking "do I have spell X?" gets no answer then. What stays readable is
-- each aura's instance ID, a number it keeps for as long as it is on you. So
-- whenever the data IS readable we remember "instance 1234 = spell X", and in
-- combat keep showing those instances while they are still there. Timer and
-- stacks come from Blizzard's display-only objects (a duration object for the
-- swipe, a ready-made stack text), which are allowed to carry secret data.
-- Limit: a buff gained during combat whose spell ID is secret can't be recognised.
local instances = {}          -- auraInstanceID -> spellID, tracked spells only
local refreshed = {}          -- instances Blizzard updated (refreshed timer / stacks)

local function Tracked(id)
    for _, v in ipairs(M.db.spells) do if v == id then return true end end
    return false
end
local function Remember(a)
    if a and not IsSecret(a) and a.auraInstanceID and not IsSecret(a.auraInstanceID)
       and a.spellId and not IsSecret(a.spellId) and M.db and Tracked(a.spellId) then
        instances[a.auraInstanceID] = a.spellId
    end
end
-- the instance IDs of everything on you right now (this list is never secret);
-- nil when the client has no such function
local function PresentIDs()
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs) then return nil end
    local set = {}
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, "player", filter)
        if ok and type(ids) == "table" then
            for _, iid in ipairs(ids) do
                if not IsSecret(iid) then set[iid] = true end
            end
        end
    end
    return set
end
local function InstanceOf(id, present)
    if not present then return nil end
    for iid, sid in pairs(instances) do
        if sid == id and present[iid] then return iid end
    end
    return nil
end
-- does Blizzard hide this buff from addons in combat?
local function SecretInCombat(id)
    if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return false end
    local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
    return ok and secret == true
end

---------------------------------------------------------------------------
-- Anchor (centre point of the row), moved through Blizzard's Edit Mode
---------------------------------------------------------------------------
-- LibEditMode (by p3lim, bundled in TrikksAuras\Libs\) adds our frame to Edit Mode with
-- the same blue selection box and drag behaviour as Blizzard's own frames,
-- and tells us which Edit Mode layout is active so every layout can have its
-- own position.
local LEM = LibStub and LibStub("LibEditMode", true)
TT.LEM = LEM
local DEFAULT_POS = { point = "CENTER", x = 0, y = -150 }
local inEditMode, currentLayout = false, nil

local anchor = CreateFrame("Frame", "TrikksAurasAnchor", UIParent)
anchor:SetSize(40, 40)
anchor:SetClampedToScreen(true)
anchor.editModeName = "Centered Auras"

local function Position()
    local db = M.db
    anchor:ClearAllPoints()
    local p = currentLayout and db.layouts[currentLayout]
    if p then
        anchor:SetPoint(p.point, UIParent, p.point, p.x, p.y)
    else
        -- no position for this layout yet: use the old single position (or the default)
        local s = anchor:GetScale()
        anchor:SetPoint("CENTER", UIParent, "CENTER", db.x / s, db.y / s)
    end
end

local function ApplyAnchor()
    local db = M.db
    anchor:SetScale(db.scale / 100)
    anchor:SetAlpha(db.alpha / 100)
    anchor:SetShown(M.enabled)       -- hidden = also gone from Edit Mode
    Position()
end

---------------------------------------------------------------------------
-- Icons + layout
---------------------------------------------------------------------------
local icons = {}
local function GetIcon(i)
    if icons[i] then return icons[i] end
    local f = CreateFrame("Frame", nil, anchor)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -1, 1); f.border:SetPoint("BOTTOMRIGHT", 1, -1)
    f.border:SetColorTexture(0, 0, 0, 1)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetDrawEdge(false)
    f.cd:SetReverse(true)
    f.count = f.cd:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    icons[i] = f
    return f
end

local function HideAll(from)
    for i = from or 1, #icons do icons[i]:Hide(); icons[i].exp = nil; icons[i].isTest = false; icons[i].inst = nil end
end

local function Update()
    if not M.db then return end
    if not M.enabled then HideAll(); return end
    local db, shown, present = M.db, {}, false
    for _, id in ipairs(db.spells) do
        local a = GetAura(id)
        local iid
        if not a then
            if present == false then present = PresentIDs() end
            iid = InstanceOf(id, present)
        end
        if a then
            Remember(a)
            shown[#shown + 1] = { icon = a.icon, dur = Num(a.duration), exp = Num(a.expirationTime),
                                  stacks = Num(a.applications) }
        elseif iid then
            local _, icon = SpellInfo(id)
            shown[#shown + 1] = { icon = icon or 134400, inst = iid }
        elseif testMode or inEditMode then
            local _, icon = SpellInfo(id)
            shown[#shown + 1] = { icon = icon or 134400, dur = 30, exp = 0, stacks = 0, test = true }
        end
    end

    -- Centring: length of the whole row, then start half of it before the centre.
    local n, size, gap = #shown, db.size, db.spacing
    local total = n * size + (n - 1) * gap
    -- the anchor covers the whole row, so Edit Mode's selection box fits it
    local long = math.max(size, total)
    if db.vertical then anchor:SetSize(size, long) else anchor:SetSize(long, size) end
    for i, data in ipairs(shown) do
        local f = GetIcon(i)
        local offset = -total / 2 + size / 2 + (i - 1) * (size + gap)
        f:SetSize(size, size)
        f:ClearAllPoints()
        if db.vertical then f:SetPoint("CENTER", anchor, "CENTER", 0, -offset)
        else f:SetPoint("CENTER", anchor, "CENTER", offset, 0) end
        f.tex:SetTexture(data.icon)
        f.cd:SetDrawSwipe(db.showSwipe)
        f.cd:SetHideCountdownNumbers(not db.showNumbers)
        if data.inst then
            -- secret data: Blizzard's own stack text and duration object
            local okC, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, "player", data.inst, 2)
            f.count:SetText((db.showStacks and okC and txt) or "")
            if f.inst ~= data.inst or refreshed[data.inst] then
                local okD, dur = pcall(C_UnitAuras.GetAuraDuration, "player", data.inst)
                if not (okD and dur and pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur)) then f.cd:Clear() end
                f.inst, f.exp, f.isTest = data.inst, nil, false
            end
        else
            f.inst = nil
            f.count:SetText((db.showStacks and data.stacks > 1) and data.stacks or "")
        end
        if data.inst then
            f.exp = nil
        elseif data.test then
            if not f.isTest then f.cd:SetCooldown(GetTime(), 30); f.isTest = true; f.exp = nil end
        elseif data.dur > 0 and data.exp > 0 then
            if f.exp ~= data.exp then
                f.cd:SetCooldown(data.exp - data.dur, data.dur)
                f.exp, f.isTest = data.exp, false
            end
        else
            f.cd:Clear(); f.exp, f.isTest = nil, false
        end
        f:Show()
    end
    HideAll(n + 1)
    wipe(refreshed)
end

---------------------------------------------------------------------------
-- Whitelist helpers
---------------------------------------------------------------------------
local RefreshList, RefreshPicker

local function IsTracked(id)
    for _, v in ipairs(M.db.spells) do if v == id then return true end end
end

local function AddSpell(input)
    input = input and strtrim(tostring(input)) or ""
    if input == "" then return end
    local id = tonumber(input)
    if not id then
        local _, _, sid = SpellInfo(input)
        id = sid
        if not id then TT.Print("couldn't find a spell called '" .. input .. "'. Try its spell ID."); return end
    end
    if IsTracked(id) then TT.Print("already tracking that."); return end
    M.db.spells[#M.db.spells + 1] = id
    TT.Print("tracking " .. (SpellInfo(id) or "?") .. " (" .. id .. ")")
    if RefreshList then RefreshList() end
    if RefreshPicker then RefreshPicker() end
    Update()
end

local function RemoveSpell(id)
    id = tonumber(id)
    for i, v in ipairs(M.db.spells) do if v == id then table.remove(M.db.spells, i) break end end
    if RefreshList then RefreshList() end
    if RefreshPicker then RefreshPicker() end
    Update()
end

local function MoveSpell(i, dir)
    local s, j = M.db.spells, i + dir
    if j < 1 or j > #s then return end
    s[i], s[j] = s[j], s[i]
    RefreshList(); Update()
end

---------------------------------------------------------------------------
-- Settings window (/ca)
---------------------------------------------------------------------------
local win = TT.Window("TrikksAurasFrame", 620, 486, "Trikks Auras")

function M:BuildSettings(body, page)
    local db = M.db
    -- left: whitelist
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT"); left:SetSize(300, 400)
    local lt = TT.Label(left, "Tracked auras (whitelist)", "GameFontNormal")
    lt:SetPoint("TOPLEFT")

    local addBox = TT.EditBox(left, 176, 22)
    addBox:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -10)
    local addHint = TT.Label(left, "Spell ID or name", "GameFontDisableSmall")
    addHint:SetPoint("LEFT", addBox, "LEFT", 7, 0)
    addBox:SetScript("OnTextChanged", function(self) addHint:SetShown(self:GetText() == "") end)
    local function DoAdd() AddSpell(addBox:GetText()); addBox:SetText(""); addBox:ClearFocus() end
    addBox:SetScript("OnEnterPressed", DoAdd)
    local addBtn = TT.Button(left, "Add", 50, DoAdd)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    local pickBtn = TT.Button(left, "From my buffs...", 140, nil)
    pickBtn:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -8)

    local scroll = TT.Scroll(left)
    scroll:SetPoint("TOPLEFT", pickBtn, "BOTTOMLEFT", 4, -14)
    scroll:SetSize(270, 290)
    local listBg = CreateFrame("Frame", nil, left, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", scroll, -4, 4); listBg:SetPoint("BOTTOMRIGHT", scroll, 12, -4)
    listBg:SetFrameLevel(scroll:GetFrameLevel() - 1)
    TT.Flat(listBg, { 0.03, 0.03, 0.04, 1 })
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(270, 1)
    scroll:SetScrollChild(content)
    local emptyText = TT.Label(content, "Nothing tracked yet.\nAdd a spell ID / name, or pick\nfrom your current buffs.", "GameFontDisable")
    emptyText:SetPoint("TOP", 0, -20)
    emptyText:SetJustifyH("CENTER")

    local rows = {}
    RefreshList = function()
        local s = M.db.spells
        for i, id in ipairs(s) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(266, 24)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 2, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetWidth(150); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
                row.del = TT.Button(row, "X", 22, nil); row.del:SetPoint("RIGHT")
                row.down = TT.Button(row, "v", 22, nil); row.down:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
                row.up = TT.Button(row, "^", 22, nil); row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(self.id)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", GameTooltip_Hide)
                rows[i] = row
            end
            local name, icon = SpellInfo(id)
            row.id = id
            row.icon:SetTexture(icon or 134400)
            row.text:SetText((name or "Unknown") .. " |cff888888" .. id .. "|r" .. (SecretInCombat(id) and " |cffffaa00*|r" or ""))
            row.del:SetScript("OnClick", function() RemoveSpell(id) end)
            row.up:SetScript("OnClick", function() MoveSpell(i, -1) end)
            row.down:SetScript("OnClick", function() MoveSpell(i, 1) end)
            row.up:SetEnabled(i > 1); row.down:SetEnabled(i < #s)
            row:Show()
        end
        for i = #s + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #s * 26))
        emptyText:SetShown(#s == 0)
    end

    -- right: display settings
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPLEFT", 316, 0); right:SetSize(270, 400)
    local rt = TT.Label(right, "Settings", "GameFontNormal")
    rt:SetPoint("TOPLEFT")
    local refreshers, last = {}, rt

    local function Place(f, gap)
        f:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, gap)
        last = f
    end
    local function BoolCheck(text, get, set)
        local cb = TT.Check(right, text, function(v) set(v); Update() end)
        Place(cb, last == rt and -12 or -10)
        refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    end
    local function DbCheck(text, key)
        BoolCheck(text, function() return db[key] end, function(v) db[key] = v end)
    end
    local function DbStepper(text, key, min, max, step, after)
        local s = TT.Stepper(right, text, function() return db[key] end,
            function(v) db[key] = v; if after then after() end; Update() end, min, max, step)
        Place(s, last.isStepper and -2 or -10)
        s.isStepper = true
        refreshers[#refreshers + 1] = s.Refresh
    end

    BoolCheck("Test mode (show all icons)", function() return testMode end, function(v) testMode = v end)
    DbCheck("Vertical (top to bottom)", "vertical")
    DbCheck("Show cooldown swipe", "showSwipe")
    DbCheck("Show timer numbers", "showNumbers")
    DbCheck("Show stack count", "showStacks")
    DbStepper("Icon size", "size", 16, 120, 2)
    DbStepper("Spacing", "spacing", 0, 40, 1)
    DbStepper("Scale %", "scale", 50, 200, 5, ApplyAnchor)
    DbStepper("Opacity %", "alpha", 10, 100, 5, ApplyAnchor)

    local resetPos = TT.Button(right, "Reset position", 120, function()
        if currentLayout then db.layouts[currentLayout] = nil end
        db.x, db.y = 0, -150
        ApplyAnchor()
    end)
    Place(resetPos, -12)
    local tip = TT.Label(right, "Move the row in Edit Mode (Esc > Edit Mode):\nit's listed as \"Centered Auras\", with its own\nposition per layout.\n\nTip: IDs & Links - hold Ctrl over a buff\nto see its spell ID.\n\n|cffffaa00*|r Blizzard hides this buff from addons in\ncombat: it keeps showing if it was up before\nthe fight, but can't appear if you get it\nduring combat.", "GameFontDisableSmall")
    Place(tip, -10)

    -- picker: auras you have right now, click to add
    local picker = TT.Window(nil, 240, 340, "Your current auras", win)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", win, "TOPRIGHT", 4, 0)
    local pscroll = TT.Scroll(picker)
    pscroll:SetPoint("TOPLEFT", 12, -36); pscroll:SetPoint("BOTTOMRIGHT", -16, 34)
    local pcontent = CreateFrame("Frame", nil, pscroll)
    pcontent:SetSize(200, 1)
    pscroll:SetScrollChild(pcontent)
    local pnote = TT.Label(picker, "", "GameFontDisableSmall")
    pnote:SetPoint("BOTTOM", 0, 12)
    local pButtons = {}
    RefreshPicker = function()
        if not picker:IsShown() then return end
        local list = {}
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                for i = 1, 40 do
                    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                    if not ok or not a then break end
                    if not IsSecret(a) and a.spellId and not IsSecret(a.spellId) then
                        list[#list + 1] = { id = a.spellId, name = a.name, icon = a.icon, harmful = filter == "HARMFUL" }
                    end
                end
            end
        end
        for i, data in ipairs(list) do
            local b = pButtons[i]
            if not b then
                b = CreateFrame("Button", nil, pcontent)
                b:SetSize(196, 24)
                b:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
                b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
                b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(22, 22); b.icon:SetPoint("LEFT")
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetWidth(166)
                b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
                pButtons[i] = b
            end
            local tracked = IsTracked(data.id)
            b.icon:SetTexture(data.icon)
            b.icon:SetDesaturated(tracked)
            local color = tracked and "|cff666666" or (data.harmful and "|cffff6666" or "|cffffffff")
            b.text:SetText(color .. (data.name or "?") .. (tracked and " (tracked)" or "") .. "|r")
            b:SetScript("OnClick", function() if not IsTracked(data.id) then AddSpell(data.id) end end)
            b:Show()
        end
        for i = #list + 1, #pButtons do pButtons[i]:Hide() end
        pcontent:SetHeight(math.max(1, #list * 26))
        pnote:SetText(#list == 0 and "No readable auras right now." or "Click an aura to track it")
    end
    picker:SetScript("OnShow", RefreshPicker)
    pickBtn:SetScript("OnClick", function() picker:SetShown(not picker:IsShown()) end)

    page.OnPageShow = function()
        for _, f in ipairs(refreshers) do f() end
        RefreshList()
    end
    page:HookScript("OnHide", function() picker:Hide() end)
end

-- leaving test mode on by accident is annoying: turn it off when the window closes
win:HookScript("OnHide", function() if testMode then testMode = false; Update() end end)

---------------------------------------------------------------------------
-- Enable / disable + events
---------------------------------------------------------------------------
local registered = false
local function RegisterEditMode()
    if registered or not LEM then return end
    registered = true
    LEM:AddFrame(anchor, function(frame, layoutName)
        -- Edit Mode saves a position from the nearest corner, but our anchor
        -- changes size as auras come and go: anchored by a corner it would grow
        -- away from that corner. Re-anchor by its CENTRE instead.
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local es, ues = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local x = (cx * es - ux * ues) / es                    -- offset in the frame's own units
        local y = (cy * es - uy * ues) / es
        M.db.layouts[layoutName] = { point = "CENTER", x = x, y = y }
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end, DEFAULT_POS, "Centered Auras")
    -- quick settings in the Edit Mode panel for our frame
    local S = LEM.SettingType
    LEM:AddFrameSettings(anchor, {
        { kind = S.Slider, name = "Icon size", default = 40, minValue = 16, maxValue = 120, valueStep = 1,
          get = function() return M.db.size end, set = function(_, v) M.db.size = v; Update() end },
        { kind = S.Slider, name = "Spacing", default = 4, minValue = 0, maxValue = 40, valueStep = 1,
          get = function() return M.db.spacing end, set = function(_, v) M.db.spacing = v; Update() end },
        { kind = S.Slider, name = "Opacity", default = 100, minValue = 10, maxValue = 100, valueStep = 5,
          get = function() return M.db.alpha end, set = function(_, v) M.db.alpha = v; ApplyAnchor() end },
        { kind = S.Checkbox, name = "Vertical", default = false,
          get = function() return M.db.vertical end, set = function(_, v) M.db.vertical = v; Update() end },
    })
    LEM:RegisterCallback("layout", function(layoutName) currentLayout = layoutName; Position() end)
    LEM:RegisterCallback("enter", function() inEditMode = true; Update() end)
    LEM:RegisterCallback("exit", function() inEditMode = false; Update() end)
    LEM:RegisterCallback("rename", function(old, new)
        M.db.layouts[new], M.db.layouts[old] = M.db.layouts[old], nil
        if currentLayout == old then currentLayout = new end
    end)
    LEM:RegisterCallback("delete", function(name) M.db.layouts[name] = nil end)
end

function M:OnEnable() RegisterEditMode(); ApplyAnchor(); Update() end
function M:OnDisable() ApplyAnchor(); Update() end

-- the window: on/off switch on top, the settings page below (built on first open)
-- the Centered Auras page; other pages (tabs) are added by the other files
local auraPage = CreateFrame("Frame", nil, win)
auraPage:SetAllPoints()
local enableCheck = TT.Check(auraPage, "Enabled", function(v)
    M.enabled, M.db.enabled = v, v
    if v then M:OnEnable() else M:OnDisable() end
end)
enableCheck:SetPoint("TOPLEFT", 18, -40)
local body = CreateFrame("Frame", nil, auraPage)
body:SetPoint("TOPLEFT", 16, -70); body:SetPoint("BOTTOMRIGHT", -16, 16)
-- tab buttons top right; the selected one gets an accent border
local tabs = {}
local function SelectTab(i)
    for j, t in ipairs(tabs) do
        t.page:SetShown(i == j)
        t.button.selected = (i == j)
        t.button:SetBackdropBorderColor(unpack(i == j and TT.C.accent or TT.C.border))
    end
end
function TT.SelectTab(title)
    for i, t in ipairs(tabs) do if t.title == title then SelectTab(i) end end
end
local function BuildTabs()
    local list = { { title = "Centered Auras", page = auraPage } }
    for _, t in ipairs(TT.extraTabs) do list[#list + 1] = t end
    if #list < 2 then return end
    local x = -40
    for i = #list, 1, -1 do
        local t = list[i]
        if not t.page then t.page = t.build(win) end
        local b = TT.Button(win, t.title, 120, function() SelectTab(i) end)
        b:SetPoint("TOPRIGHT", x, -34)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(TT.C.panel))
            self:SetBackdropBorderColor(unpack(self.selected and TT.C.accent or TT.C.border))
        end)
        t.button = b
        x = x - 124
    end
    tabs = list
    SelectTab(1)
end

win:SetScript("OnShow", function()
    if not body.built then body.built = true; M:BuildSettings(body, body); BuildTabs() end
    enableCheck:SetChecked(M.enabled)
    if body.OnPageShow then body.OnPageShow() end
end)

-- copy defaults into saved settings without overwriting what's there
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

TT.CopyDefaults = CopyDefaults

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    local db = TrikksAurasDB
    if type(db) ~= "table" or not db.spells then
        -- first start: bring settings over from where Centered Auras used to
        -- live (the Trikks Tweaks module, or an early version of this addon).
        -- "OptionalDeps: TrikksTweaks" in the .toc makes sure TrikksTweaksDB
        -- is already loaded at this point when Trikks Tweaks is installed.
        local old = (type(db) == "table" and db.modules and db.modules.CenteredAuras)
            or (TrikksTweaksDB and TrikksTweaksDB.modules and TrikksTweaksDB.modules.CenteredAuras)
        db = type(old) == "table" and old or {}
        if TrikksTweaksDB and TrikksTweaksDB.modules then TrikksTweaksDB.modules.CenteredAuras = nil end
        if old then TT.Print("settings imported from Trikks Tweaks' Centered Auras.") end
    end
    db.modules = nil
    CopyDefaults(DEFAULTS, db)
    TrikksAurasDB = db
    M.db, M.enabled = db, db.enabled
    ApplyAnchor()
    if M.enabled then RegisterEditMode() end
    for _, f in ipairs(TT.onReady) do
        local ok, err = pcall(f, db)
        if not ok then geterrorhandler()("Trikks Auras: " .. tostring(err)) end
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterUnitEvent("UNIT_AURA", "player")
-- keep the instance list up to date (see the note at the top)
local function TrackChanges(info)
    if info.isFullUpdate then
        local present = PresentIDs()
        if present then for iid in pairs(instances) do if not present[iid] then instances[iid] = nil end end end
    end
    for _, a in ipairs(info.addedAuras or {}) do Remember(a) end
    for _, iid in ipairs(info.updatedAuraInstanceIDs or {}) do
        if not IsSecret(iid) and instances[iid] then refreshed[iid] = true end
    end
    for _, iid in ipairs(info.removedAuraInstanceIDs or {}) do
        if not IsSecret(iid) then instances[iid] = nil end
    end
end
ev:SetScript("OnEvent", function(_, event, _, info)
    if event == "PLAYER_ENTERING_WORLD" then wipe(instances) end
    if event == "UNIT_AURA" and type(info) == "table" and M.db then pcall(TrackChanges, info) end
    Update()
    if event == "UNIT_AURA" and RefreshPicker then RefreshPicker() end
end)
C_Timer.NewTicker(0.5, Update)            -- safety net for missed aura events

SLASH_TTCENTEREDAURAS1 = "/ca"
SLASH_TTCENTEREDAURAS2 = "/trikksauras"
SlashCmdList.TTCENTEREDAURAS = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = cmd and cmd:lower() or ""
    if cmd == "add" then AddSpell(arg)
    elseif cmd == "remove" then RemoveSpell(arg)
    elseif cmd == "unlock" or cmd == "lock" then TT.Print("move the row in Edit Mode (Esc > Edit Mode).")
    elseif cmd == "test" then testMode = not testMode; Update()
    elseif cmd == "buffs" or cmd == "reminders" then win:Show(); TT.SelectTab("Buff Reminders")
    else win:SetShown(not win:IsShown()) end
end
