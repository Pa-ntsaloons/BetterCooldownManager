-- Better Cooldown Manager
-- Extends Blizzard's Cooldown Manager. Right-click a buff in Cooldown Settings to
-- turn it into a Reminder: Blizzard's own icon is shown only when the buff has
-- expired, or has X time left. Right-click a cooldown to show it only when ready.
--
-- Everything is shown in Blizzard's own Tracked Buffs / Bars / cooldown rows.
-- We never write to Blizzard's Lua tables (that would spread taint); we only read
-- their state, show/hide/fade their frames, and add small overlays.
local _, ns = ...

local GetTime, floor, max = GetTime, math.floor, math.max
local pairs, ipairs, pcall, select, type, tonumber, wipe = pairs, ipairs, pcall, select, type, tonumber, wipe

local db
local PRESETS = { 5, 10, 15, 30, 60, 120, 300, 600 }
local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer" }

local function Print(...) print("|cff33ccffBetter Cooldown Manager:|r", ...) end

---------------------------------------------------------------------------
-- Secret-value helpers (Midnight/Forever combat restrictions)
---------------------------------------------------------------------------
local issecretvalue = issecretvalue
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function Readable(...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then return false end
    end
    return true
end

-- Call a method and return its first two results only if they're normal values.
local function SafeCall(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then return nil end
    local ok, a, b = pcall(obj[method], obj, ...)
    if ok and Readable(a, b) then return a, b end
end

---------------------------------------------------------------------------
-- Categories that have a Blizzard frame we can use
---------------------------------------------------------------------------
local function CategoryKind(cat)
    local C = Enum and Enum.CooldownViewerCategory
    if not C or cat == nil then return nil end
    if cat == C.TrackedBuff or cat == C.TrackedBar
        or cat == C.EquipSlotTracked or cat == C.SpecAgnosticTracked then
        return "buff"
    end
    if cat == C.Essential or cat == C.Utility
        or cat == C.EquipSlotEssential or cat == C.SpecAgnosticEssential then
        return "cooldown"
    end
end

---------------------------------------------------------------------------
-- Time formatting / parsing
---------------------------------------------------------------------------
local function FormatSecs(s)
    if s >= 60 then
        if s % 60 == 0 then return ("%d min"):format(s / 60) end
        return ("%d:%02d"):format(floor(s / 60), s % 60)
    end
    return ("%g sec"):format(s)
end

local function ParseTime(text)
    local t = strtrim(text or ""):lower()
    if t == "" then return end
    local m, s = t:match("^(%d+):(%d%d?)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    local n = tonumber(t)
    if n then return n > 0 and n or nil end
    local mins = tonumber(t:match("(%d+%.?%d*)%s*m"))
    local secs = tonumber(t:match("(%d+%.?%d*)%s*s"))
    if mins or secs then
        local total = (mins or 0) * 60 + (secs or 0)
        return total > 0 and total or nil
    end
end

---------------------------------------------------------------------------
-- Blizzard frames
---------------------------------------------------------------------------
local frameByID = {}
local function CollectFrames()
    wipe(frameByID)
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer and viewer.itemFramePool then
            for f in viewer.itemFramePool:EnumerateActive() do
                local id = SafeCall(f, "GetCooldownID")
                if id then frameByID[id] = f end
            end
        end
    end
end

local function SettingsOpen()
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return true end
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok and active == true then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- State evaluation
---------------------------------------------------------------------------
local RT = {} -- runtime state per cooldownID: lastExp, lastShow

-- Buff: returns show, missing
local function EvalBuff(r, f, now, rt)
    local ok, active = pcall(f.IsActive, f)
    if not ok or IsSecret(active) then return rt.lastShow, false end
    if not active then -- false, or nil when Blizzard has never activated it
        rt.lastExp = nil
        return true, true
    end
    if (r.threshold or 0) <= 0 then return false, false end

    local exp = SafeCall(f, "GetCooldownValues") -- expirationTime, duration
    if exp == nil then
        -- Timer hidden from addons right now: count down from the last reading.
        exp = rt.lastExp
    else
        rt.lastExp = exp
    end
    if not exp or exp == 0 then return false, false end -- unknown or permanent
    return exp - now <= r.threshold, false
end

-- Cooldown: returns show
local function EvalCooldown(r, f, now, rt)
    local ch = f.cachedSpellChargeInfo
    if type(ch) == "table" and Readable(ch.currentCharges, ch.maxCharges)
        and ch.maxCharges and ch.maxCharges > 1 and ch.currentCharges and ch.currentCharges > 0 then
        return true
    end
    local ok, onCD = pcall(f.IsOnCooldown, f)
    if not ok or onCD == nil or IsSecret(onCD) then return rt.lastShow end
    if not onCD then return true end
    if (r.threshold or 0) <= 0 then return false end
    local s, d = f.cooldownStartTime, f.cooldownDuration
    if s and d and Readable(s, d) then
        return s + d - now <= r.threshold
    end
    return false
end

---------------------------------------------------------------------------
-- Overlays on Blizzard frames (our own child frames)
---------------------------------------------------------------------------
local overlays = {}

local function GetOverlay(f)
    local o = overlays[f]
    if o then return o end
    o = CreateFrame("Frame", nil, f)
    o:SetAllPoints()
    o:SetFrameLevel(f:GetFrameLevel() + 10)

    -- Glow
    local g = o:CreateTexture(nil, "OVERLAY", nil, 7)
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.85, 0.2)
    g:SetPoint("CENTER")
    o.glow = g
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(1)
    a:SetDuration(0.5)
    o.anim = ag

    overlays[f] = o
    return o
end

local desaturated = {} -- buff frames whose icon we greyed out

local function SetOverlay(f, glow, missing)
    -- Expired buff: grey the icon out, like Blizzard does for inactive things.
    local icon = SafeCall(f, "GetIconTexture")
    if icon and icon.SetDesaturated then
        if missing then
            icon:SetDesaturated(true)
            desaturated[f] = icon
        elseif desaturated[f] then
            icon:SetDesaturated(false)
            desaturated[f] = nil
        end
    end

    local o = overlays[f]
    if not glow then
        if o and o:IsShown() then o.anim:Stop(); o:Hide() end
        return
    end
    o = GetOverlay(f)
    local w, h = f:GetSize()
    local s = max(w, h) * 1.8
    o.glow:SetSize(s, s)
    if not o:IsShown() then o:Show() end
    if not o.anim:IsPlaying() then o.anim:Play() end
end

---------------------------------------------------------------------------
-- Timer text on Tracked Buff icons, rounded up like the buff tooltip/buff bar
-- (Blizzard's built-in countdown rounds down: 14:50 left shows "14m").
---------------------------------------------------------------------------
local timerTexts = {}    -- item frame -> our font string
local hidCountdown = {}  -- item frame -> cooldown frame whose numbers we hid

local function FormatLeft(s)
    if s >= 3600 then return ("%dh"):format(math.ceil(s / 3600)) end
    if s >= 60 then return ("%dm"):format(math.ceil(s / 60)) end
    return ("%d"):format(math.ceil(s))
end

local function RestoreTimer(f)
    local cd = hidCountdown[f]
    if cd then
        local viewer = SafeCall(f, "GetViewerFrame")
        local wantsTimer = not viewer or viewer.timerShown ~= false
        cd:SetHideCountdownNumbers(not wantsTimer)
        hidCountdown[f] = nil
    end
    local fs = timerTexts[f]
    if fs and fs:IsShown() then fs:Hide() end
end

local function GetTimerText(f, cd)
    local fs = timerTexts[f]
    if fs then return fs end
    local holder = CreateFrame("Frame", nil, f)
    holder:SetAllPoints(cd)
    holder:SetFrameLevel(cd:GetFrameLevel() + 2)
    fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local blizz = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if blizz then
        local okF, font, size, flags = pcall(blizz.GetFont, blizz)
        if okF and type(font) == "string" and type(size) == "number" then
            pcall(fs.SetFont, fs, font, size, flags or "")
        end
        -- Copy Blizzard's anchor when it's a normal one; otherwise just centre it.
        local okP, p, _, rp, x, y = pcall(blizz.GetPoint, blizz, 1)
        local placed = false
        if okP and type(p) == "string" and type(rp) == "string"
            and type(x) == "number" and type(y) == "number" and Readable(p, rp, x, y) then
            placed = pcall(fs.SetPoint, fs, p, holder, rp, x, y)
        end
        if not placed then
            fs:ClearAllPoints()
            fs:SetPoint("CENTER")
        end
        local okC, r, g, b, a = pcall(blizz.GetTextColor, blizz)
        if okC and type(r) == "number" and Readable(r, g, b, a) then fs:SetTextColor(r, g, b, a) end
    else
        fs:SetPoint("CENTER")
    end
    timerTexts[f] = fs
    return fs
end

local function UpdateTimerTexts(now, seen)
    local viewer = BuffIconCooldownViewer
    if not viewer or not viewer.itemFramePool or viewer.timerShown == false then return end
    for f in viewer.itemFramePool:EnumerateActive() do
        seen[f] = true
        local cd = SafeCall(f, "GetCooldownFrame")
        local active = SafeCall(f, "IsActive")
        local exp = active and SafeCall(f, "GetCooldownValues") or nil
        if cd and exp and exp > now then
            cd:SetHideCountdownNumbers(true)
            hidCountdown[f] = cd
            local fs = GetTimerText(f, cd)
            fs:SetText(FormatLeft(exp - now))
            fs:Show()
        else
            RestoreTimer(f)
        end
    end
end

---------------------------------------------------------------------------
-- Main update
---------------------------------------------------------------------------
local faded = {}       -- frames we set to alpha 0
local forced = {}      -- inactive buff frames we force-showed
local touched = {}

local function LetBlizzardDecide(f)
    -- Hand visibility back to Blizzard's own logic.
    pcall(f.UpdateShownState, f)
end

local function RestoreFrame(f)
    if faded[f] then f:SetAlpha(1); faded[f] = nil end
    if forced[f] then forced[f] = nil; LetBlizzardDecide(f) end
    SetOverlay(f, false, false)
end

local function RestoreAll()
    for f in pairs(faded) do RestoreFrame(f) end
    for f in pairs(forced) do RestoreFrame(f) end
    for f in pairs(overlays) do SetOverlay(f, false, false) end
    for f in pairs(desaturated) do SetOverlay(f, false, false) end
    for f in pairs(hidCountdown) do RestoreTimer(f) end
end

---------------------------------------------------------------------------
-- Group buff reminders (Group Buffs tab: buffs other players give you).
-- Blizzard has no Cooldown Manager icon for these, so we draw icons that copy
-- the Tracked Buffs look and attach them to the end of that row.
---------------------------------------------------------------------------
local GRT = {}         -- runtime state per group buff spellID
local groupIcons = {}
local groupAuras = { byID = {}, byName = {}, secret = false }
local groupList = {}

function ns.ResetGroupReminder(id) GRT[id] = nil end

local function ScanPlayerBuffs()
    local byID, byName = groupAuras.byID, groupAuras.byName
    wipe(byID); wipe(byName)
    groupAuras.secret = false
    for i = 1, 255 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        local name, id = a.name, a.spellId
        if not Readable(name, id) then
            groupAuras.secret = true
        elseif name then
            local rec = {}
            if Readable(a.expirationTime, a.duration) and a.expirationTime ~= nil then
                rec.exp, rec.dur = a.expirationTime, a.duration
            end
            if id then byID[id] = rec end
            byName[name:lower()] = rec
        end
    end
end

local function LowerName(id)
    if not id then return end
    local n = C_Spell.GetSpellName(id)
    if n and Readable(n) then return n:lower() end
end

-- Matches by spell ID, then by name (so every rank of the buff counts).
local function FindGroupAura(id, r)
    local byID, byName = groupAuras.byID, groupAuras.byName
    local rec = byID[id] or (r.displaySpellID and byID[r.displaySpellID])
    if rec then return rec end
    local n1, n2 = LowerName(id), LowerName(r.displaySpellID)
    return (n1 and byName[n1]) or (n2 and byName[n2]) or (r.name and byName[r.name:lower()])
end

-- Returns show, missing, expirationTime, duration
local function EvalGroup(id, r, now, rt)
    if r.groupOnly and not IsInGroup() then return false, false end
    local rec = FindGroupAura(id, r)
    if rec then
        if rec.exp then rt.lastExp, rt.lastDur = rec.exp, rec.dur end
        local exp = rec.exp or rt.lastExp
        if (r.threshold or 0) <= 0 or not exp or exp == 0 then return false, false end
        return exp - now <= r.threshold, false, exp, rec.dur or rt.lastDur
    end
    if groupAuras.secret then
        -- Some buffs are hidden from addons right now (combat): use the last reading.
        if rt.lastExp == 0 or rt.lastExp == nil and not rt.lastMissing then return rt.lastShow, rt.lastMissing end
        if rt.lastExp and rt.lastExp > now then
            return (r.threshold or 0) > 0 and rt.lastExp - now <= r.threshold, false, rt.lastExp, rt.lastDur
        end
    end
    rt.lastExp = nil
    return true, true
end

local function CreateGroupIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 40)
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    local mask = f:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
    mask:SetAllPoints(f.Icon)
    f.Icon:AddMaskTexture(mask)
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    border:SetPoint("TOPLEFT", -8, 7)
    border:SetPoint("BOTTOMRIGHT", 8, -7)

    f.Cooldown = CreateFrame("Cooldown", nil, f)
    f.Cooldown:SetAllPoints()
    f.Cooldown:SetReverse(true)
    f.Cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
    f.Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    f.Cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
    f.Cooldown:SetHideCountdownNumbers(true)

    local holder = CreateFrame("Frame", nil, f)
    holder:SetAllPoints()
    holder:SetFrameLevel(f.Cooldown:GetFrameLevel() + 2)
    f.Text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.Text:SetPoint("CENTER")
    -- Copy the font Blizzard uses for its timer numbers.
    local viewer = BuffIconCooldownViewer
    if viewer and viewer.itemFramePool then
        for fr in viewer.itemFramePool:EnumerateActive() do
            local cd = SafeCall(fr, "GetCooldownFrame")
            local blizz = cd and cd.GetCountdownFontString and cd:GetCountdownFontString()
            if blizz then
                local okF, font, size, flags = pcall(blizz.GetFont, blizz)
                if okF and type(font) == "string" and type(size) == "number" then
                    pcall(f.Text.SetFont, f.Text, font, size, flags or "")
                end
                break
            end
        end
    end

    f.GetIconTexture = function(self) return self.Icon end -- used by SetOverlay
    f:SetMouseClickEnabled(false)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:Hide()
    return f
end

local function HideGroupIcons(from)
    for i = from or 1, #groupIcons do
        local f = groupIcons[i]
        if f:IsShown() then f:Hide() end
    end
end

local function UpdateGroupReminders(now)
    wipe(groupList)
    if not next(db.groupReminders) then HideGroupIcons(1); return end
    local viewer = BuffIconCooldownViewer
    if not viewer or not viewer.itemFramePool then HideGroupIcons(1); return end

    ScanPlayerBuffs()
    for id, r in pairs(db.groupReminders) do
        local rt = GRT[id]
        if not rt then rt = {}; GRT[id] = rt end
        local ok, show, missing, exp, dur = pcall(EvalGroup, id, r, now, rt)
        if not ok then show, missing = rt.lastShow, rt.lastMissing end
        rt.lastShow, rt.lastMissing = show and true or false, missing and true or false
        if show then
            groupList[#groupList + 1] = { id = id, r = r, missing = missing, exp = exp, dur = dur }
        end
    end
    table.sort(groupList, function(a, b) return (a.r.name or "") < (b.r.name or "") end)

    -- Attach after the last slot of Blizzard's Tracked Buffs row, going the same way it grows.
    local last, lastIndex
    for fr in viewer.itemFramePool:EnumerateActive() do
        local li = fr.layoutIndex
        if type(li) == "number" and (not lastIndex or li > lastIndex) then last, lastIndex = fr, li end
    end
    local pad = tonumber(viewer.childXPadding) or 1
    local horizontal = viewer.isHorizontal ~= false
    local right = viewer.layoutFramesGoingRight ~= false
    local up = viewer.layoutFramesGoingUp == true
    local scale = tonumber(viewer.iconScale) or 1
    local tooltips = viewer.tooltipsShown ~= false

    local prev = last
    for i, item in ipairs(groupList) do
        local f = groupIcons[i]
        if not f then f = CreateGroupIcon(viewer); groupIcons[i] = f end
        f:SetScale(scale)
        f:ClearAllPoints()
        if not prev then
            f:SetPoint("CENTER", viewer, "CENTER")
        elseif horizontal then
            if right then f:SetPoint("LEFT", prev, "RIGHT", pad, 0) else f:SetPoint("RIGHT", prev, "LEFT", -pad, 0) end
        else
            if up then f:SetPoint("BOTTOM", prev, "TOP", 0, pad) else f:SetPoint("TOP", prev, "BOTTOM", 0, -pad) end
        end
        prev = f

        local r = item.r
        f.spellID = r.displaySpellID or item.id
        f.Icon:SetTexture(r.icon or C_Spell.GetSpellTexture(item.id))
        f:SetMouseMotionEnabled(tooltips)
        if item.exp and item.dur and item.dur > 0 and item.exp > now then
            if f._exp ~= item.exp then
                f.Cooldown:SetCooldown(item.exp - item.dur, item.dur)
                f._exp = item.exp
            end
            f.Text:SetText(viewer.timerShown ~= false and FormatLeft(item.exp - now) or "")
        else
            if f._exp then f.Cooldown:Clear(); f._exp = nil end
            f.Text:SetText("")
        end
        f:Show()
        touched[f] = true
        SetOverlay(f, r.glow, item.missing and true or false)
    end
    HideGroupIcons(#groupList + 1)
end

local timerSeen = {}

local function UpdateInner()
    if not db then return end

    if SettingsOpen() then
        -- Blizzard shows everything while the layout is being edited.
        RestoreAll()
        HideGroupIcons(1)
        return
    end

    local now = GetTime()
    CollectFrames()
    wipe(touched)

    wipe(timerSeen)
    local okT, errT = pcall(UpdateTimerTexts, now, timerSeen)
    if not okT then ns.ReportError(errT) end
    for f in pairs(hidCountdown) do if not timerSeen[f] then RestoreTimer(f) end end

    for id, r in pairs(db.reminders) do
        local f = frameByID[id]
        if f then
            touched[f] = true
            local rt = RT[id]
            if not rt then rt = {}; RT[id] = rt end

            local ok, show, missing
            if r.kind == "cooldown" then
                ok, show = pcall(EvalCooldown, r, f, now, rt)
                missing = false
            else
                ok, show, missing = pcall(EvalBuff, r, f, now, rt)
            end
            if not ok then show, missing = rt.lastShow, false end
            show = show and true or false
            rt.lastShow = show

            if show then
                if faded[f] then f:SetAlpha(1); faded[f] = nil end
                if not f:IsShown() then
                    -- Blizzard hides expired buffs; put the icon back in its own slot.
                    f:Show()
                    forced[f] = true
                end
                SetOverlay(f, r.glow, missing and true or false)
            else
                if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
                faded[f] = true
                if forced[f] then forced[f] = nil; LetBlizzardDecide(f) end
                SetOverlay(f, false, false)
            end
        end
    end

    local okG, errG = pcall(UpdateGroupReminders, now)
    if not okG then ns.ReportError(errG) end

    local okA, errA = pcall(ns.UpdateExpireAlerts, now)
    if not okA then ns.ReportError(errA) end

    -- Frames that stopped being reminders, or that Blizzard reused for another spell.
    for f in pairs(faded) do if not touched[f] then RestoreFrame(f) end end
    for f in pairs(forced) do if not touched[f] then RestoreFrame(f) end end
    for f in pairs(overlays) do if not touched[f] then SetOverlay(f, false, false) end end
    for f in pairs(desaturated) do if not touched[f] then SetOverlay(f, false, false) end end
end

-- Runs 10 times a second, so an error must never escape (it would spam the
-- error window). Report each distinct error once in chat instead.
local reported = {}
function ns.ReportError(err)
    err = tostring(err)
    if not reported[err] then
        reported[err] = true
        Print("|cffff5555error:|r " .. err .. " (please report this, with /bcm debug output)")
    end
end

function ns.Update()
    local ok, err = pcall(UpdateInner)
    if not ok then ns.ReportError(err) end
    if ns.RefreshAlertDialog then
        ok, err = pcall(ns.RefreshAlertDialog)
        if not ok then ns.ReportError(err) end
    end
end

---------------------------------------------------------------------------
-- Right-click menu in Cooldown Settings
---------------------------------------------------------------------------
StaticPopupDialogs["BETTERCOOLDOWNMANAGER_CUSTOM_TIME"] = {
    text = "Show it when this much time is left:\n|cffaaaaaa(examples: 45, 90s, 2m, 1:30)|r",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 10,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local eb = self.GetEditBox and self:GetEditBox() or self.editBox or self.EditBox
        eb:SetText(data and data.current and tostring(data.current) or "")
        eb:SetFocus()
    end,
    OnAccept = function(self, data)
        local eb = self.GetEditBox and self:GetEditBox() or self.editBox or self.EditBox
        local secs = ParseTime(eb:GetText())
        if secs then data.apply(secs) else Print("couldn't read that time.") end
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        local dialog = editBox:GetParent()
        StaticPopupDialogs.BETTERCOOLDOWNMANAGER_CUSTOM_TIME.OnAccept(dialog, data)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

local function IsPreset(s)
    for _, p in ipairs(PRESETS) do if p == s then return true end end
    return false
end

local function StatusText(r, kind)
    if not r then return "Off" end
    local base = kind == "buff" and "When Expired" or "When Ready"
    if (r.threshold or 0) <= 0 then return base end
    return base .. " or < " .. FormatSecs(r.threshold)
end

-- Shared Reminder submenu.
--   store/key: where the reminder is saved
--   kind:      "buff" or "cooldown"
--   fill(r):   called when saving, to store name etc.
--   reset():   clear runtime state for this reminder
--   extra(sub, current): add more options at the bottom
--   alwaysText: label for "off"
local function BuildReminderMenu(root, o)
    local store, key, kind = o.store, o.key, o.kind

    local function Apply(threshold)
        if threshold == nil then
            store[key] = nil
        else
            local r = store[key] or { glow = true }
            r.kind = kind
            r.threshold = threshold
            if o.fill then o.fill(r) end
            store[key] = r
        end
        if o.reset then o.reset() end
        ns.Update()
    end

    local function IsSelected(value)
        local r = store[key]
        if value == "off" then return r == nil end
        if value == "on" then return r ~= nil end
        if value == "custom" then return r ~= nil and (r.threshold or 0) > 0 and not IsPreset(r.threshold) end
        return r ~= nil and (r.threshold or 0) == value
    end
    local function SetSelected(value)
        if value == "off" then
            Apply(nil)
        elseif value == "on" then
            -- Clicking the parent keeps any early-warning time already chosen.
            if not store[key] then Apply(0) end
        elseif value == "custom" then
            local r = store[key]
            StaticPopup_Show("BETTERCOOLDOWNMANAGER_CUSTOM_TIME", nil, nil, { apply = Apply, current = r and r.threshold })
        else
            Apply(value)
        end
        return MenuResponse and MenuResponse.Close
    end

    root:CreateDivider()
    local current = store[key]
    local label = kind == "buff" and "Reminder" or "Show Only When Ready"
    local sub = root:CreateButton(("%s: |cffffd100%s|r"):format(label, StatusText(current, kind)))

    local buff = kind == "buff"
    sub:CreateTitle(buff and "Show this buff..." or "Show this cooldown...")
    sub:CreateRadio(o.alwaysText or (buff and "Always (normal tracked buff)" or "Always (normal)"), IsSelected, SetSelected, "off")

    -- "When expired" is the parent; the early-warning times sit inside it, since
    -- every one of them also shows the icon once it has expired.
    local on = sub:CreateRadio(buff and "Only when it has expired" or "Only when it is ready", IsSelected, SetSelected, "on")
    on:CreateTitle(buff and "...and also show it early, when:" or "...and also show it early, when:")
    on:CreateRadio(buff and "No, only once it has expired" or "No, only once it's ready", IsSelected, SetSelected, 0)
    for _, s in ipairs(PRESETS) do
        local text = buff and ("%s or less is left") or ("it's ready in %s or less")
        on:CreateRadio(text:format(FormatSecs(s)), IsSelected, SetSelected, s)
    end
    local customText = "Custom time..."
    if current and (current.threshold or 0) > 0 and not IsPreset(current.threshold) then
        customText = ("Custom (%s)..."):format(FormatSecs(current.threshold))
    end
    on:CreateRadio(customText, IsSelected, SetSelected, "custom")

    sub:CreateDivider()
    local glow = sub:CreateCheckbox("Glow while showing",
        function() local r = store[key]; return r ~= nil and r.glow end,
        function() local r = store[key]; if r then r.glow = not r.glow; ns.Update() end end)
    if glow.SetEnabled then glow:SetEnabled(current ~= nil) end
    if o.extra then o.extra(sub, current) end
end

-- Tracked Buffs / Bars / Essential / Utility items
local function AddReminderMenu(owner, root)
    if not db or not owner or type(owner.GetCooldownID) ~= "function" then return end
    if SafeCall(owner, "IsEmptyCategory") then return end
    local id = SafeCall(owner, "GetCooldownID")
    if not id then return end
    local kind = CategoryKind(SafeCall(owner, "GetCategory"))
    if not kind then return end

    if kind == "buff" and ns.AddExpireAlertEntries then ns.AddExpireAlertEntries(owner, root, id) end

    BuildReminderMenu(root, {
        store = db.reminders, key = id, kind = kind,
        fill = function(r) r.name = SafeCall(owner, "GetNameText") or r.name end,
        reset = function() RT[id] = nil end,
    })
end

-- Group Buffs tab items (buffs other players give you)
local function AddGroupBuffMenu(owner, root)
    if not db or not owner or type(owner.GetGroupBuffItem) ~= "function" then return end
    local item = SafeCall(owner, "GetGroupBuffItem")
    if type(item) ~= "table" or not item.spellID then return end
    local id = item.spellID

    BuildReminderMenu(root, {
        store = db.groupReminders, key = id, kind = "buff",
        alwaysText = "Off",
        fill = function(r)
            r.name = item.name or r.name
            r.icon = item.iconID or r.icon
            r.displaySpellID = item.displaySpellID
            if r.groupOnly == nil then r.groupOnly = not item.isKnown end
        end,
        reset = function() ns.ResetGroupReminder(id) end,
        extra = function(sub, current)
            local cb = sub:CreateCheckbox("Only when I'm in a group",
                function() local r = db.groupReminders[id]; return r ~= nil and r.groupOnly end,
                function() local r = db.groupReminders[id]; if r then r.groupOnly = not r.groupOnly; ns.Update() end end)
            if cb.SetEnabled then cb:SetEnabled(current ~= nil) end
        end,
    })
end

---------------------------------------------------------------------------
-- "About to Expire" alerts.
-- Adds an About to Expire choice to the When dropdown of Blizzard's New Alert
-- dialog. Blizzard's alert list only accepts its own event types, so these
-- alerts are saved by us (db.expireAlerts[cooldownID] = { {type, payload, seconds}, ... })
-- and played through Blizzard's own alert player, so they look/sound the same.
---------------------------------------------------------------------------
local pendingExpire     -- seconds chosen in the open dialog, or nil
local editingAlert      -- { id = cooldownID, index = n } when editing one of ours
local suppressClear = false
local saveButton
local alertFired = {}   -- [cooldownID][index] = expirationTime it last fired for
local alertLastExp = {} -- [cooldownID] = last readable expirationTime

local function AuraEventType()
    local E = Enum and Enum.CooldownViewerAlertEventType
    return E and E.OnAuraApplied
end

local function ExpireText(seconds)
    return ("About to Expire (%s)"):format(FormatSecs(seconds))
end

local function EditDialog() return CooldownViewerSettingsEditAlert end

local function DialogSupportsExpire(dialog)
    local E = Enum and Enum.CooldownViewerAlertEventType
    local valid = dialog and dialog.validCooldownAlertTypes
    return E and type(valid) == "table" and (valid[E.OnAuraRemoved] ~= nil or valid[E.OnAuraApplied] ~= nil)
end

local function ClearPending()
    pendingExpire, editingAlert = nil, nil
    if saveButton then saveButton:Hide() end
end

local function RefreshDialogState()
    local dialog = EditDialog()
    if not dialog or not saveButton then return end
    if pendingExpire and dialog:IsShown() then
        saveButton:SetText(editingAlert and "Save Alert" or "Add Alert")
        saveButton:Show()
        local dd = dialog.EventDropdown
        local text = dd and dd.Text
        if text and text.SetText then text:SetText(ExpireText(pendingExpire)) end
    else
        saveButton:Hide()
    end
end
ns.RefreshAlertDialog = RefreshDialogState

local function SavePendingAlert()
    local dialog = EditDialog()
    if not dialog or not pendingExpire then return end
    local id = dialog.cooldownID
    local working = dialog.workingCopyOfAlert
    if not id or type(working) ~= "table" then return end
    local entry = {
        type = CooldownViewerAlert_GetType(working),
        payload = CooldownViewerAlert_GetPayload(working),
        seconds = pendingExpire,
    }
    db.expireAlerts[id] = db.expireAlerts[id] or {}
    local list = db.expireAlerts[id]
    if editingAlert and editingAlert.id == id and list[editingAlert.index] then
        list[editingAlert.index] = entry
    else
        list[#list + 1] = entry
    end
    alertFired[id] = nil
    ClearPending()
    dialog:Hide()
end

local function SetupSaveButton(dialog)
    if saveButton or not dialog or not dialog.AddButton then return end
    -- Sits exactly on top of Blizzard's Add Alert button, only while About to Expire is chosen.
    saveButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveButton:SetAllPoints(dialog.AddButton)
    saveButton:SetFrameLevel(dialog.AddButton:GetFrameLevel() + 5)
    saveButton:SetScript("OnClick", SavePendingAlert)
    saveButton:Hide()
    dialog:HookScript("OnHide", ClearPending)
    hooksecurefunc(dialog, "DisplayForAlert", function()
        if not suppressClear then ClearPending() end
    end)
end

-- Picking one of Blizzard's own When choices cancels ours.
local function OnBlizzardSetEvent(alert)
    local dialog = EditDialog()
    if pendingExpire and dialog and alert == dialog.workingCopyOfAlert then
        ClearPending()
    end
end

local function AddExpireChoices(owner, root)
    local dialog = EditDialog()
    if not db or not DialogSupportsExpire(dialog) then return end
    SetupSaveButton(dialog)

    local function IsSelected(value)
        if value == "parent" then return pendingExpire ~= nil end
        if value == "custom" then return pendingExpire ~= nil and not IsPreset(pendingExpire) end
        return pendingExpire == value
    end
    local function Choose(seconds)
        pendingExpire = seconds
        RefreshDialogState()
    end
    local function SetSelected(value)
        if value == "custom" then
            StaticPopup_Show("BETTERCOOLDOWNMANAGER_CUSTOM_TIME", nil, nil, { apply = Choose, current = pendingExpire })
        elseif value == "parent" then
            if not pendingExpire then Choose(10) end
        else
            Choose(value)
        end
        return MenuResponse and MenuResponse.Close
    end

    root:CreateDivider()
    local parent = root:CreateRadio(pendingExpire and ExpireText(pendingExpire) or "About to Expire", IsSelected, SetSelected, "parent")
    parent:CreateTitle("Alert when this much time is left:")
    for _, s in ipairs(PRESETS) do
        parent:CreateRadio(FormatSecs(s), IsSelected, SetSelected, s)
    end
    local customText = "Custom time..."
    if pendingExpire and not IsPreset(pendingExpire) then customText = ("Custom (%s)..."):format(FormatSecs(pendingExpire)) end
    parent:CreateRadio(customText, IsSelected, SetSelected, "custom")
end

-- Our alerts, listed in the right-click menu just like Blizzard's.
function ns.AddExpireAlertEntries(owner, root, id)
    local list = db.expireAlerts[id]
    if not list or #list == 0 or not CooldownViewerContextMenu_AddAlertEntryButton then return end
    root:CreateDivider()
    root:CreateTitle("About to Expire alerts")
    for index, a in ipairs(list) do
        local blizzAlert = CooldownViewerAlert_Create(a.type, AuraEventType(), a.payload)
        CooldownViewerContextMenu_AddAlertEntryButton(root, a.type,
            CooldownViewerAlert_GetPayloadText(blizzAlert), ExpireText(a.seconds),
            function() -- edit
                local dialog = EditDialog()
                if not dialog then return end
                SetupSaveButton(dialog)
                suppressClear = true
                pcall(dialog.DisplayForAlert, dialog, owner, blizzAlert, false)
                suppressClear = false
                pendingExpire = a.seconds
                editingAlert = { id = id, index = index }
                RefreshDialogState()
            end,
            function() -- delete
                table.remove(list, index)
                if #list == 0 then db.expireAlerts[id] = nil end
                alertFired[id] = nil
            end,
            function() -- play sample
                pcall(CooldownViewerAlert_PlayAlert, owner, SafeCall(owner, "GetNameText"), blizzAlert, "Gameplay SFX")
            end)
    end
end

-- Fire alerts when a tracked buff crosses its time.
function ns.UpdateExpireAlerts(now)
    if not next(db.expireAlerts) then return end
    for id, list in pairs(db.expireAlerts) do
        local f = frameByID[id]
        if f then
            local active = SafeCall(f, "IsActive")
            local exp
            if active then
                exp = SafeCall(f, "GetCooldownValues")
                if exp then alertLastExp[id] = exp else exp = alertLastExp[id] end
            else
                alertLastExp[id] = nil
            end
            alertFired[id] = alertFired[id] or {}
            local fired = alertFired[id]
            if exp and exp > now then
                local left = exp - now
                for index, a in ipairs(list) do
                    if left <= (a.seconds or 0) and fired[index] ~= exp then
                        fired[index] = exp
                        local alert = CooldownViewerAlert_Create(a.type, AuraEventType(), a.payload)
                        pcall(CooldownViewerAlert_PlayAlert, f, SafeCall(f, "GetNameText"), alert, "Gameplay SFX")
                    end
                end
            elseif not active then
                wipe(fired) -- buff gone; it can alert again next time
            end
        end
    end
end

local alertHooksInstalled = false
function ns.InstallAlertHooks()
    if alertHooksInstalled or not CooldownViewerAlert_SetEvent or not EditDialog() then return end
    alertHooksInstalled = true
    hooksecurefunc("CooldownViewerAlert_SetEvent", OnBlizzardSetEvent)
    SetupSaveButton(EditDialog())
    Menu.ModifyMenu("COOLDOWN_VIEWER_ALERT_EVENT", function(owner, rootDescription)
        local ok, err = pcall(AddExpireChoices, owner, rootDescription)
        if not ok then Print("menu error: " .. tostring(err)) end
    end)
end

---------------------------------------------------------------------------
-- Slash command: /bcm (open Cooldown Settings), /bcm list, /bcm clear, /bcm debug
---------------------------------------------------------------------------
SLASH_BETTERCOOLDOWNMANAGER1 = "/bcm"
SLASH_BETTERCOOLDOWNMANAGER2 = "/bettercdm"
SlashCmdList.BETTERCOOLDOWNMANAGER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "debug" then
        CollectFrames()
        local now = GetTime()
        Print("debug:")
        for _, name in ipairs(VIEWERS) do
            local v = _G[name]
            print(("  %s: %s"):format(name, not v and "missing" or
                (v:IsShown() and "shown" or "HIDDEN") .. (v:IsVisible() and "" or " (not visible)")))
        end
        local any = false
        for id, r in pairs(db.reminders) do
            any = true
            local f = frameByID[id]
            local line = ("  %s [id %s] %s"):format(r.name or "?", tostring(id), StatusText(r, r.kind))
            if not f then
                print(line .. " | NO BLIZZARD FRAME (not in Tracked Buffs/Bars/Essential/Utility?)")
            else
                local okA, active = pcall(f.IsActive, f)
                local exp = SafeCall(f, "GetCooldownValues")
                local left = exp and exp > 0 and ("%.0fs left"):format(exp - now) or (exp == 0 and "no timer" or "time unknown")
                local viewer = SafeCall(f, "GetViewerFrame") or f:GetParent()
                print(("%s | active=%s %s | frameShown=%s alpha=%.1f viewerVisible=%s | decision=%s"):format(
                    line, okA and tostring(active) or "error", left,
                    tostring(f:IsShown()), f:GetAlpha(), tostring(viewer and viewer:IsVisible()),
                    tostring(RT[id] and RT[id].lastShow)))
            end
        end
        if not any then print("  (no reminders set)") end
        ScanPlayerBuffs()
        for id, r in pairs(db.groupReminders) do
            local rec = FindGroupAura(id, r)
            local left = rec and (rec.exp and (rec.exp == 0 and "no timer" or ("%.0fs left"):format(rec.exp - now)) or "time unknown") or "MISSING"
            print(("  group buff %s [spell %s] %s | %s | inGroup=%s groupOnly=%s | decision=%s"):format(
                r.name or "?", tostring(id), StatusText(r, "buff"), left, tostring(IsInGroup()),
                tostring(r.groupOnly), tostring(GRT[id] and GRT[id].lastShow)))
        end
        if groupAuras.secret then print("  (some of your buffs are hidden from addons right now)") end
        print("  settings/edit mode open: " .. tostring(SettingsOpen()))
        -- Every Blizzard icon frame, to spot duplicates or reused frames.
        for _, name in ipairs(VIEWERS) do
            local v = _G[name]
            if v and v.itemFramePool then
                for fr in v.itemFramePool:EnumerateActive() do
                    local fid = SafeCall(fr, "GetCooldownID")
                    if fid and db.reminders[fid] or overlays[fr] or desaturated[fr] or forced[fr] or faded[fr] then
                        local okA, active = pcall(fr.IsActive, fr)
                        print(("  frame %s in %s: id=%s active=%s shown=%s alpha=%.1f forced=%s faded=%s grey=%s glow=%s"):format(
                            tostring(fr):sub(-6), name, tostring(fid), okA and tostring(active) or "error",
                            tostring(fr:IsShown()), fr:GetAlpha(), tostring(forced[fr] or false), tostring(faded[fr] or false),
                            tostring(desaturated[fr] ~= nil), tostring(overlays[fr] ~= nil and overlays[fr]:IsShown())))
                    end
                end
            end
        end
        return
    end
    if cmd == "clear" then
        wipe(db.reminders)
        wipe(db.groupReminders)
        wipe(db.expireAlerts)
        wipe(RT)
        wipe(GRT)
        wipe(alertFired)
        ns.Update()
        Print("all reminders and About to Expire alerts removed.")
        return
    end
    if cmd == "" then
        -- Open Blizzard's Cooldown Settings, like its own slash command does.
        if not CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
        end
        if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
            local ok, err = pcall(CooldownViewerSettings.TogglePanel, CooldownViewerSettings)
            if not ok then Print("couldn't open Cooldown Settings: " .. tostring(err)) end
        else
            Print("Cooldown Settings isn't available on this character.")
        end
        return
    end
    if cmd ~= "list" then
        Print("commands:")
        print("  /bcm - open Cooldown Settings (right-click a buff or cooldown there)")
        print("  /bcm list - list your reminders")
        print("  /bcm clear - remove all reminders")
        print("  /bcm debug - show what the addon sees (for bug reports)")
        return
    end
    Print("your reminders (right-click a buff or cooldown in Cooldown Settings to change them):")
    local any = false
    for id, r in pairs(db.reminders) do
        any = true
        print(("  %s - %s"):format(r.name or ("#" .. id), StatusText(r, r.kind)))
    end
    for id, r in pairs(db.groupReminders) do
        any = true
        print(("  %s (group buff) - %s%s"):format(r.name or ("#" .. id), StatusText(r, "buff"),
            r.groupOnly and ", only in a group" or ""))
    end
    for id, list in pairs(db.expireAlerts) do
        local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
        local name = info and info.spellID and C_Spell.GetSpellName(info.spellID) or ("#" .. id)
        for _, a in ipairs(list) do
            any = true
            local alert = CooldownViewerAlert_Create(a.type, AuraEventType(), a.payload)
            print(("  %s - alert: %s, %s"):format(name, CooldownViewerAlert_GetPayloadText(alert), ExpireText(a.seconds)))
        end
    end
    if not any then print("  (no reminders set)") end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- The Cooldown Manager's settings may load after us.
        if addonName == "Blizzard_CooldownViewer" then
            local ok, err = pcall(ns.InstallAlertHooks)
            if not ok then ns.ReportError(err) end
        end
        return
    end

    BetterCooldownManagerCharDB = BetterCooldownManagerCharDB or {}
    db = BetterCooldownManagerCharDB
    db.reminders = db.reminders or {}
    db.groupReminders = db.groupReminders or {}
    db.expireAlerts = db.expireAlerts or {}

    local okH, errH = pcall(ns.InstallAlertHooks)
    if not okH then ns.ReportError(errH) end
    self:RegisterEvent("ADDON_LOADED")

    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription)
            local ok, err = pcall(AddReminderMenu, owner, rootDescription)
            if not ok then Print("menu error: " .. tostring(err)) end
        end)
        Menu.ModifyMenu("MENU_GROUP_BUFF_FILTER_ITEM", function(owner, rootDescription)
            local ok, err = pcall(AddGroupBuffMenu, owner, rootDescription)
            if not ok then Print("menu error: " .. tostring(err)) end
        end)
    else
        Print("couldn't hook the Cooldown Settings menu (Menu API missing).")
    end

    C_Timer.NewTicker(0.1, ns.Update)
end)
