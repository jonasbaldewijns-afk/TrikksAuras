-- Buff Reminders (part of Trikks Auras)
-- An icon for each of your class buffs that is missing or about to run out,
-- out of combat only. Click it to cast the buff (left = on you, right = on your
-- target). Buffs are matched by spell name, so it works with whatever ranks /
-- versions of a spell the client has; a reminder only counts spells you know.
local _, TT = ...
local IsSecret = TT.IsSecret
local _, CLASS = UnitClass("player")

local R = {}                                -- R.db = TrikksAurasDB.reminders
local DEFAULTS = {
    enabled = false,                        -- opt-in
    size = 36, spacing = 4, minLeft = 2,    -- minLeft: remind when less than this many minutes are left
    group = true, hideResting = false, onlyInstance = false, hideMounted = false, sound = false,
    layouts = {}, on = {}, cast = {}, custom = {},
}
local DEFAULT_POS = { point = "CENTER", x = 0, y = 120 }
local test, inEditMode, currentLayout = false, false, nil

---------------------------------------------------------------------------
-- The buffs per class
---------------------------------------------------------------------------
-- spells = what a click casts (best first; the first one you know is used),
-- auras  = buff names that count as "has it" (defaults to the spells).
-- group  = also count party/raid members missing it, off = off by default,
-- weapon = a weapon enchant (poison, imbue) also counts,
-- always = remind even if none of the spells is known (e.g. poisons are items).
local function E(key, label, spells, auras, opts)
    local e = { key = key, label = label, spells = spells, auras = auras or spells }
    for k, v in pairs(opts or {}) do e[k] = v end
    return e
end
local BLESSINGS = {}
for _, b in ipairs({ "Kings", "Might", "Wisdom", "Salvation", "Light", "Sanctuary" }) do
    BLESSINGS[#BLESSINGS + 1] = "Blessing of " .. b
    BLESSINGS[#BLESSINGS + 1] = "Greater Blessing of " .. b
end
local POISONS = { "Instant Poison", "Deadly Poison", "Wound Poison", "Crippling Poison", "Mind-numbing Poison",
                  "Amplifying Poison", "Numbing Poison", "Atrophic Poison" }

local CLASS_BUFFS = {
    MAGE = {
        E("int", "Arcane Intellect", { "Arcane Brilliance", "Arcane Intellect" },
          { "Arcane Intellect", "Arcane Brilliance", "Dalaran Intellect", "Dalaran Brilliance" }, { group = true }),
        E("armor", "Armor", { "Molten Armor", "Mage Armor", "Ice Armor", "Frost Armor" }),
    },
    PRIEST = {
        E("fort", "Power Word: Fortitude", { "Prayer of Fortitude", "Power Word: Fortitude" }, nil, { group = true }),
        E("spirit", "Divine Spirit", { "Prayer of Spirit", "Divine Spirit" }, nil, { group = true }),
        E("shadow", "Shadow Protection", { "Prayer of Shadow Protection", "Shadow Protection" }, nil, { group = true, off = true }),
        E("innerfire", "Inner Fire", { "Inner Fire" }),
    },
    DRUID = {
        E("motw", "Mark of the Wild", { "Gift of the Wild", "Mark of the Wild" }, nil, { group = true }),
        E("thorns", "Thorns", { "Thorns" }, nil, { off = true }),
    },
    PALADIN = {
        E("blessing", "Blessing", { "Blessing of Kings", "Blessing of Might", "Blessing of Wisdom",
          "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary" }, BLESSINGS),
        E("aura", "Aura", { "Devotion Aura", "Retribution Aura", "Concentration Aura", "Crusader Aura",
          "Sanctity Aura", "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura" }),
        E("fury", "Righteous Fury", { "Righteous Fury" }, nil, { off = true }),
    },
    WARRIOR = {
        E("shout", "Battle Shout", { "Battle Shout" }, nil, { group = true }),
    },
    WARLOCK = {
        E("armor", "Demon Armor", { "Fel Armor", "Demon Armor", "Demon Skin" }),
    },
    SHAMAN = {
        E("shield", "Shield", { "Water Shield", "Lightning Shield", "Earth Shield" }),
        E("weapon", "Weapon imbue", { "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon",
          "Rockbiter Weapon", "Earthliving Weapon" }, {}, { weapon = true }),
        E("skyfury", "Skyfury", { "Skyfury" }, nil, { group = true }),
    },
    HUNTER = {
        E("trueshot", "Trueshot Aura", { "Trueshot Aura" }),
        E("aspect", "Aspect", { "Aspect of the Hawk", "Aspect of the Dragonhawk", "Aspect of the Monkey",
          "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Viper" }, nil, { off = true }),
    },
    ROGUE = {
        -- classic: poison = weapon enchant from an item; newer clients: poison = a buff from a spell
        E("poison", "Weapon poison", POISONS, POISONS, { weapon = true, always = true }),
    },
    EVOKER = {
        E("bronze", "Blessing of the Bronze", { "Blessing of the Bronze" }, nil, { group = true }),
    },
}

-- your class's list plus your own reminders
local function Entries()
    local list = {}
    for _, e in ipairs(CLASS_BUFFS[CLASS] or {}) do list[#list + 1] = e end
    for _, name in ipairs(R.db and R.db.custom or {}) do
        list[#list + 1] = E("custom:" .. name, name, { name }, { name }, { always = true, custom = true })
    end
    return list
end
local function IsOn(e)
    local v = R.db.on[e.key]
    if v == nil then return not e.off end
    return v
end

---------------------------------------------------------------------------
-- Spells you know
---------------------------------------------------------------------------
local function Known(name)
    local id
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        id = info and info.spellID
    elseif GetSpellInfo then
        id = select(7, GetSpellInfo(name))
    end
    if not id or IsSecret(id) then return nil end
    if IsPlayerSpell and IsPlayerSpell(id) then return id end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then return id end
    if IsSpellKnown and IsSpellKnown(id) then return id end
    return nil
end
local function KnownSpells(e)
    local list = {}
    for _, name in ipairs(e.spells) do
        if Known(name) then list[#list + 1] = name end
    end
    return list
end
-- the spell a click casts: your choice if you still know it, else the best one
local function CastSpell(e, known)
    local pick = R.db.cast[e.key]
    for _, n in ipairs(known) do if n == pick then return n end end
    return known[1]
end
local function SpellIcon(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        if info and info.iconID then return info.iconID end
    end
    return GetSpellTexture and GetSpellTexture(name) or nil
end

---------------------------------------------------------------------------
-- Who has what
---------------------------------------------------------------------------
-- buff name -> { seconds left, full duration } (math.huge / 0 for buffs without a duration)
local function AuraTimes(unit)
    local out = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return out end
    local now = GetTime()
    for i = 1, 255 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not a then break end
        if not IsSecret(a) and a.name and not IsSecret(a.name) then
            local left, dur, exp = math.huge, 0, a.expirationTime
            if exp and not IsSecret(exp) and exp > 0 then
                left = exp - now
                if a.duration and not IsSecret(a.duration) then dur = a.duration end
            end
            if not out[a.name] or left > out[a.name][1] then out[a.name] = { left, dur } end
        end
    end
    return out
end
local function BestLeft(times, auras)
    local best, dur
    for _, n in ipairs(auras) do
        local t = times[n]
        if t and (not best or t[1] > best) then best, dur = t[1], t[2] end
    end
    return best, dur or 0
end
-- "about to run out": less than the set minutes, but never more than a
-- quarter of the buff's own length (else a 2-minute shout would always remind)
local function Low(left, dur, limit)
    if not left then return true end
    if dur > 0 then limit = math.min(limit, dur / 4) end
    return left < limit
end

-- is there a weapon in the off hand (not a shield / held item)?
local function OffhandWeapon()
    if C_PaperDollInfo and C_PaperDollInfo.OffhandHasWeapon then return C_PaperDollInfo.OffhandHasWeapon() end
    local id = GetInventoryItemID("player", 17)
    if not id then return false end
    local classID = select(6, (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(id))
    return classID == 2
end
-- seconds left on the weakest needed weapon enchant (nil = one is missing)
local function WeaponLeft()
    local hasMain, mainMs, _, _, hasOff, offMs = GetWeaponEnchantInfo()
    if not GetInventoryItemID("player", 16) then return math.huge end   -- no weapon: nothing to remind
    if not hasMain then return nil end
    local left = (mainMs or 0) / 1000
    if OffhandWeapon() then
        if not hasOff then return nil end
        left = math.min(left, (offMs or 0) / 1000)
    end
    return left
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") then units[#units + 1] = u end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end
-- group members who could get the buff right now: alive, online, nearby
local function Reachable(u)
    if not UnitExists(u) or not UnitIsConnected(u) or UnitIsDeadOrGhost(u) or not UnitIsVisible(u) then return false end
    local inRange, checked = UnitInRange(u)
    if IsSecret(inRange) or IsSecret(checked) then return false end
    return not checked or inRange
end

-- should reminders show at all right now?
local function Allowed()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
    if UnitInVehicle and UnitInVehicle("player") then return false end
    local db = R.db
    if db.hideResting and IsResting() then return false end
    if db.hideMounted and IsMounted() then return false end
    if db.onlyInstance then
        local _, kind = IsInInstance()
        if kind ~= "party" and kind ~= "raid" then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- The row of icons (moved in Edit Mode as "Buff Reminders")
---------------------------------------------------------------------------
local container = CreateFrame("Frame", "TrikksAurasReminders", UIParent)
container:SetSize(36, 36)
container:SetClampedToScreen(true)
container:Hide()

local function Position()
    local p = currentLayout and R.db.layouts[currentLayout] or DEFAULT_POS
    container:ClearAllPoints()
    container:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

local function FormatTime(s)
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end
    return string.format("%ds", math.floor(s))
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.label or "", 1, 1, 1)
    if self.missing and self.missing > 0 then
        GameTooltip:AddLine(self.missing .. " in your group " .. (self.missing == 1 and "is" or "are") .. " missing it", 1, 0.82, 0)
    end
    if self.spell then
        GameTooltip:AddLine("Click: cast " .. self.spell .. " on yourself", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: on your target", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- secure buttons: Blizzard only lets these cast spells. Their attributes can
-- only change out of combat, which is the only time reminders show anyway.
local buttons = {}
local function GetButton(i)
    if buttons[i] then return buttons[i] end
    local b = CreateFrame("Button", "TrikksAurasReminder" .. i, container, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon); hl:SetColorTexture(1, 1, 1, 0.15)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    buttons[i] = b
    return b
end

local shownBefore = 0
local function Update()
    if not R.db or InCombatLockdown() then return end
    local db, show = R.db, {}
    local preview = test or inEditMode
    if (db.enabled and Allowed()) or preview then
        local mine = AuraTimes("player")
        local others
        local limit = db.minLeft * 60
        for _, e in ipairs(Entries()) do
            local known = KnownSpells(e)
            if IsOn(e) and (#known > 0 or e.always) then
                local left, dur = BestLeft(mine, e.auras)
                if e.weapon then
                    local w = WeaponLeft()
                    if w and (not left or w > left) then left, dur = w, 0 end
                end
                local selfLow = Low(left, dur, limit)
                local missing = 0
                if e.group and db.group then
                    if not others then
                        others = {}
                        for _, u in ipairs(GroupUnits()) do
                            if Reachable(u) then others[#others + 1] = AuraTimes(u) end
                        end
                    end
                    for _, t in ipairs(others) do
                        local l, d = BestLeft(t, e.auras)
                        if Low(l, d, limit) then missing = missing + 1 end
                    end
                end
                if selfLow or missing > 0 or preview then
                    local spell = CastSpell(e, known)
                    show[#show + 1] = {
                        e = e, spell = spell, missing = missing,
                        left = (left and left < math.huge and selfLow) and left or nil,
                        icon = (spell and SpellIcon(spell)) or (e.weapon and GetInventoryItemTexture("player", 16)) or 134400,
                    }
                end
            end
        end
    end

    -- lay out, growing from the centre
    local n, size, gap = #show, db.size, db.spacing
    local total = n * size + math.max(0, n - 1) * gap
    container:SetSize(math.max(size, total), size)
    for i, d in ipairs(show) do
        local b = GetButton(i)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("CENTER", container, "CENTER", -total / 2 + size / 2 + (i - 1) * (size + gap), 0)
        b.icon:SetTexture(d.icon)
        b.count:SetText(d.missing > 0 and d.missing or "")
        b.time:SetText(d.left and FormatTime(d.left) or "")
        b.label, b.spell, b.missing = d.e.label, d.spell, d.missing
        b:SetAttribute("type1", d.spell and "spell" or nil)
        b:SetAttribute("spell1", d.spell)
        b:SetAttribute("unit1", "player")
        b:SetAttribute("type2", d.spell and "spell" or nil)
        b:SetAttribute("spell2", d.spell)
        b:SetAttribute("unit2", "target")
        b:Show()
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end

    if db.sound and not preview and n > shownBefore then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
    if not preview then shownBefore = n end
end

---------------------------------------------------------------------------
-- On / off, Edit Mode
---------------------------------------------------------------------------
local registered = false
local function RegisterEditMode()
    local LEM = TT.LEM
    if registered or not LEM then return end
    registered = true
    LEM:AddFrame(container, function(frame, layoutName)
        -- keep it anchored by its centre, so the row grows evenly both ways
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local es, ues = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local x, y = (cx * es - ux * ues) / es, (cy * es - uy * ues) / es
        R.db.layouts[layoutName] = { point = "CENTER", x = x, y = y }
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end, DEFAULT_POS, "Buff Reminders")
    LEM:RegisterCallback("layout", function(layoutName) currentLayout = layoutName; Position() end)
    LEM:RegisterCallback("enter", function() inEditMode = true; Update() end)
    LEM:RegisterCallback("exit", function() inEditMode = false; Update() end)
    LEM:RegisterCallback("rename", function(old, new)
        R.db.layouts[new], R.db.layouts[old] = R.db.layouts[old], nil
        if currentLayout == old then currentLayout = new end
    end)
    LEM:RegisterCallback("delete", function(name) R.db.layouts[name] = nil end)
end

-- Once a second re-check (buffs running out don't always send an event).
-- Only runs while reminders are on or test mode is showing.
local ticker
local function SetTicker(on)
    if on and not ticker then ticker = C_Timer.NewTicker(1, function() Update() end)
    elseif not on and ticker then ticker:Cancel(); ticker = nil end
end

local pendingApply = false
local function Apply()
    SetTicker(R.db.enabled or test)
    if InCombatLockdown() then pendingApply = true; return end
    pendingApply = false
    if R.db.enabled then
        RegisterEditMode()
        -- hidden in combat by the game's own secure handler (allowed in combat)
        RegisterStateDriver(container, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(container, "visibility")
        container:SetShown(test)
    end
    Position()
    Update()
end

TT.onReady[#TT.onReady + 1] = function(sv)
    if type(sv.reminders) ~= "table" then sv.reminders = {} end
    TT.CopyDefaults(DEFAULTS, sv.reminders)
    R.db = sv.reminders
    Apply()
end

local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.25, function() queued = false; Update() end)
end
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED",
                     "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA", "UNIT_AURA", "UNIT_INVENTORY_CHANGED",
                     "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and pendingApply then Apply() end
    if R.db and (R.db.enabled or test) then Queue() end     -- off: ignore the (frequent) aura events
end)

---------------------------------------------------------------------------
-- Settings tab in the /ca window
---------------------------------------------------------------------------
local function BuildPage(win)
    local page = CreateFrame("Frame", nil, win)
    page:SetAllPoints()
    page:Hide()
    local db = R.db
    local refreshers = {}

    local enable = TT.Check(page, "Enabled", function(v) db.enabled = v; Apply() end)
    enable:SetPoint("TOPLEFT", 18, -40)
    refreshers[#refreshers + 1] = function() enable:SetChecked(db.enabled) end

    -- left: the buffs of your class + your own
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", 16, -70); left:SetSize(300, 400)
    local className = (UnitClass("player"))
    local lt = TT.Label(left, "Buffs for your class (" .. (className or "?") .. ")", "GameFontNormal")
    lt:SetPoint("TOPLEFT")
    local scroll = TT.Scroll(left)
    scroll:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 0, -10)
    scroll:SetSize(290, 250)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(290, 1)
    scroll:SetScrollChild(content)

    local addBox = TT.EditBox(left, 190, 22)
    addBox:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -12)
    local addHint = TT.Label(addBox, "Your own: spell / buff name", "GameFontDisableSmall")
    addHint:SetPoint("LEFT", 7, 0)
    addBox:SetScript("OnTextChanged", function(self) addHint:SetShown(self:GetText() == "") end)

    local rows = {}
    local RefreshList
    local function AddCustom()
        local name = strtrim(addBox:GetText() or "")
        addBox:SetText(""); addBox:ClearFocus()
        if name == "" then return end
        local id = tonumber(name)
        if id then                                         -- an ID: use its name
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
            name = info and info.name or name
        end
        for _, v in ipairs(db.custom) do if v == name then return end end
        db.custom[#db.custom + 1] = name
        RefreshList(); Update()
    end
    addBox:SetScript("OnEnterPressed", AddCustom)
    local addBtn = TT.Button(left, "Add", 60, AddCustom)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    local addTip = TT.Label(left, "Anything that shows as a buff on you: food,\nflasks, an item buff, a spell from another class.", "GameFontDisableSmall")
    addTip:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", 0, -8)

    RefreshList = function()
        local list = Entries()
        for i, e in ipairs(list) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(286, 26)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
                row.cb = TT.Check(row, "", function(v)
                    db.on[row.e.key] = v; Update()
                end)
                row.cb:SetPoint("LEFT", 4, 0)
                row.status = TT.Label(row, "", "GameFontDisableSmall")
                row.status:SetPoint("RIGHT", -4, 0)
                -- "pick one" buffs: which spell a click casts (click to switch)
                row.cast = TT.Button(row, "", 120, function()
                    local known = KnownSpells(row.e)
                    local cur = CastSpell(row.e, known)
                    for k, n in ipairs(known) do
                        if n == cur then db.cast[row.e.key] = known[k % #known + 1]; break end
                    end
                    RefreshList(); Update()
                end)
                row.cast:SetPoint("RIGHT", -4, 0)
                row.del = TT.Button(row, "X", 22, function()
                    for k, v in ipairs(db.custom) do
                        if "custom:" .. v == row.e.key then table.remove(db.custom, k); break end
                    end
                    db.on[row.e.key], db.cast[row.e.key] = nil, nil
                    RefreshList(); Update()
                end)
                row.del:SetPoint("RIGHT", -4, 0)
                rows[i] = row
            end
            row.e = e
            row.cb.Text:SetText(e.label)
            row.cb:SetHitRectInsets(0, -(row.cb.Text:GetStringWidth() + 12), -4, -4)
            row.cb:SetChecked(IsOn(e))
            local known = KnownSpells(e)
            row.cast:Hide(); row.del:Hide(); row.status:SetText("")
            if e.custom then
                row.del:Show()
            elseif #known == 0 and not e.always then
                row.status:SetText("not learned")
            elseif #known > 1 then
                row.cast:SetText(CastSpell(e, known)); row.cast:Show()
            end
            row:Show()
        end
        for i = #list + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #list * 28))
    end

    -- right: options
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", 332, -70); right:SetSize(270, 400)
    local rt = TT.Label(right, "Settings", "GameFontNormal")
    rt:SetPoint("TOPLEFT")
    local last = rt
    local function Place(f, gap) f:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, gap); last = f end
    local function DbCheck(text, key)
        local cb = TT.Check(right, text, function(v) db[key] = v; Update() end)
        Place(cb, last == rt and -12 or -10)
        refreshers[#refreshers + 1] = function() cb:SetChecked(db[key]) end
    end
    local function DbStepper(text, key, min, max, step)
        local s = TT.Stepper(right, text, function() return db[key] end,
            function(v) db[key] = v; Update() end, min, max, step)
        Place(s, last.isStepper and -2 or -10)
        s.isStepper = true
        refreshers[#refreshers + 1] = s.Refresh
    end
    local testCB = TT.Check(right, "Test mode (show all)", function(v) test = v; Apply() end)
    Place(testCB, -12)
    refreshers[#refreshers + 1] = function() testCB:SetChecked(test) end
    DbCheck("Count group members missing it", "group")
    DbCheck("Hide while resting (cities, inns)", "hideResting")
    DbCheck("Hide while mounted", "hideMounted")
    DbCheck("Only in dungeons and raids", "onlyInstance")
    DbCheck("Play a sound when one appears", "sound")
    DbStepper("Remind at less than (min)", "minLeft", 0, 15, 1)
    DbStepper("Icon size", "size", 20, 80, 2)
    DbStepper("Spacing", "spacing", 0, 30, 1)
    local reset = TT.Button(right, "Reset position", 120, function()
        if currentLayout then db.layouts[currentLayout] = nil end
        Position()
    end)
    Place(reset, -12)
    local tip = TT.Label(right, "Never shown in combat. Move the row in Edit\nMode (\"Buff Reminders\"). Click an icon to cast\nit on yourself, right-click on your target. The\nnumber = group members in range missing it.", "GameFontDisableSmall")
    Place(tip, -10)

    page:SetScript("OnShow", function()
        for _, f in ipairs(refreshers) do f() end
        RefreshList()
    end)
    -- leaving test mode on by accident is annoying
    page:SetScript("OnHide", function() if test then test = false; Apply() end end)
    return page
end

TT.extraTabs[#TT.extraTabs + 1] = { title = "Buff Reminders", build = BuildPage }
