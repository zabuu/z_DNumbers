zDNumbers = zDNumbers or {}

local Z = zDNumbers
local defaults = {
  enabled = "1",
  x = "0",
  y = "8",
  width = "120",
  height = "80",
  fade = ".5",
  align = "CENTER",
}

local function MergeDefaults(target)
  for key, value in pairs(defaults) do
    if target[key] == nil then target[key] = value end
  end
end

local function ResetConfig()
  local imported = Z.config.zNameplatesImport
  for key in pairs(Z.config) do Z.config[key] = nil end
  MergeDefaults(Z.config)
  Z.config.zNameplatesImport = imported
  if Z.Refresh then Z.Refresh() end
end

local function ImportLegacyConfig(target)
  if target.zNameplatesImport == "1" then return end
  local legacy = zNameplatesDB and zNameplatesDB.config and zNameplatesDB.config.nameplates
  if type(legacy) ~= "table" then return end
  local map = {
    enabled = "msbt_enable", x = "msbt_x", y = "msbt_y",
    height = "msbt_height", fade = "msbt_fade", align = "msbt_align",
    width = "width",
  }
  for key, legacyKey in pairs(map) do
    if target[key] == nil and legacy[legacyKey] ~= nil then target[key] = legacy[legacyKey] end
    if legacyKey ~= "width" then legacy[legacyKey] = nil end
  end
  target.zNameplatesImport = "1"
end

Z.defaults = defaults
Z.Reset = ResetConfig

local TEXT_SLOTS = 10
local recordsByPlate = {}
local recordsByUnit = {}
local recordsByGuid = {}
local visibleRecords = {}
local fadingRecords = {}
local fadingRecordsByGuid = {}
local recycledRecords = {}
local outgoingGuidHints = {}
local duplicateNameCursor = {}
local guidEventsEnabled
local cachedWorldChildren = {}
local cachedWorldChildCount = -1
local nextPlateScan = 0
local validFrameStrata = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
  DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}

local function SafeFrameStrata(frame)
  local strata = frame and frame.GetFrameStrata and frame:GetFrameStrata()
  return validFrameStrata[strata] and strata or "LOW"
end

local function IsStatusBar(object)
  return object and ((object.GetObjectType and object:GetObjectType() == "StatusBar")
    or (object.GetValue and object.GetMinMaxValues and object.GetStatusBarColor
      and object.SetStatusBarTexture))
end

-- Prefer a host addon's exposed health bar, but make no assumptions about the
-- addon's identity. The fallback scan also supports unmodified Blizzard plates
-- and nameplate addons which only expose normal StatusBar children.
local function FindHealthAnchor(base)
  if not base then return UIParent end

  -- Do not put these in a sparse array: Lua 5.0/5.1 can stop at the first
  -- missing entry, which skips ordinary Blizzard and third-party plate layouts.
  if base.nameplate then
    if base.nameplate.health then return base.nameplate.health end
    if base.nameplate.healthBar then return base.nameplate.healthBar end
    if base.nameplate.healthbar then return base.nameplate.healthbar end
  end
  if base.UnitFrame then
    if base.UnitFrame.healthBar then return base.UnitFrame.healthBar end
    if base.UnitFrame.healthbar then return base.UnitFrame.healthbar end
    if base.UnitFrame.health then return base.UnitFrame.health end
  end
  if base.unitFrame then
    if base.unitFrame.healthBar then return base.unitFrame.healthBar end
    if base.unitFrame.healthbar then return base.unitFrame.healthbar end
    if base.unitFrame.health then return base.unitFrame.health end
  end
  if base.healthBar then return base.healthBar end
  if base.healthbar then return base.healthbar end
  if base.health then return base.health end

  if IsStatusBar(base) then return base end
  if not base.GetChildren then return base end
  local children = { base:GetChildren() }
  for i = 1, table.getn(children) do
    if IsStatusBar(children[i]) then return children[i] end
  end
  for i = 1, table.getn(children) do
    local child = children[i]
    if child and child.GetChildren then
      local grandchildren = { child:GetChildren() }
      for j = 1, table.getn(grandchildren) do
        if IsStatusBar(grandchildren[j]) then return grandchildren[j] end
      end
    end
  end

  return base
end

local function PlateName(base, unit)
  local visual = base and (base.nameplate or base.UnitFrame or base.unitFrame)
  local nameText = visual and (visual.name or visual.Name
    or (visual.original and visual.original.name))
  if nameText and nameText.GetText then
    local name = nameText:GetText()
    if name and name ~= "" then return name end
  end

  if base and base.GetRegions then
    local regions = { base:GetRegions() }
    for i = 1, table.getn(regions) do
      local region = regions[i]
      if region and region.GetObjectType and region:GetObjectType() == "FontString"
          and region.GetText then
        local name = region:GetText()
        if name and name ~= "" and not tonumber(name) then return name end
      end
    end
  end

  if unit and UnitName then
    local ok, name = pcall(UnitName, unit)
    if ok and name and name ~= "" then return name end
  end
end

local function PlateGuid(base)
  if not base or not base.GetName then return nil end

  -- SuperWoW exposes a nameplate's actual unit GUID through GetName(1), even
  -- when no addon has created a nameplateN unit token for the original plate.
  local ok, guid = pcall(base.GetName, base, 1)
  if ok and type(guid) == "string" and string.find(guid, "^0[xX]%x+$") then
    return guid
  end
end

local function Alignment()
  local align = Z.config.align or "CENTER"
  if align == "LEFT" then return "BOTTOMLEFT", "LEFT" end
  if align == "RIGHT" then return "BOTTOMRIGHT", "RIGHT" end
  return "BOTTOM", "CENTER"
end

local function ClearAnimations(record)
  if not record or not record.frame then return end
  for i = 1, TEXT_SLOTS do
    local item = record.frame.items[i]
    item.active = nil
    item.text:Hide()
  end
  record.frame:Hide()
end

local function RememberRecordPosition(record)
  if not record or record.frozen or not record.frame then return end
  local x, y = record.frame:GetCenter()
  if not x or not y then return end

  local frameScale = record.frame.GetEffectiveScale and record.frame:GetEffectiveScale() or 1
  local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  if parentScale <= 0 then parentScale = 1 end

  record.screenX = x * frameScale / parentScale
  record.screenY = y * frameScale / parentScale
  record.screenScale = frameScale / parentScale
  record.screenStrata = SafeFrameStrata(record.frame)
end

local function ReleaseFadingRecord(record)
  if not record or not fadingRecords[record] then return end
  fadingRecords[record] = nil
  if record.guid and fadingRecordsByGuid[record.guid] == record then
    fadingRecordsByGuid[record.guid] = nil
  end
  ClearAnimations(record)
  record.base, record.anchor, record.unit, record.guid, record.name = nil, nil, nil, nil, nil
  record.frozen, record.screenX, record.screenY = nil, nil, nil
  record.screenScale, record.screenStrata = nil, nil
  table.insert(recycledRecords, record)
end

local function FreezeRecord(record)
  if not record or not record.frame then return end

  local hasAnimations
  for i = 1, TEXT_SLOTS do
    if record.frame.items[i].active then hasAnimations = true; break end
  end
  if not hasAnimations then ClearAnimations(record); return end

  RememberRecordPosition(record)
  if not record.screenX or not record.screenY then ClearAnimations(record); return end

  if recordsByPlate[record.base] == record then recordsByPlate[record.base] = nil end
  record.frozen = true
  fadingRecords[record] = true
  if record.guid then fadingRecordsByGuid[record.guid] = record end

  -- Nameplate frames are pooled and immediately move to another unit. Keep the
  -- old text alive under UIParent at its final on-screen position instead.
  local frame = record.frame
  frame:SetParent(UIParent)
  frame:SetScale(record.screenScale or 1)
  frame:SetFrameStrata(record.screenStrata or "LOW")
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", record.screenX, record.screenY)
  frame:Show()
  return true
end

local function ConfigureRecord(record)
  if not record or not record.frame then return end
  local anchor = FindHealthAnchor(record.base)
  local parent = anchor.GetParent and anchor:GetParent() or record.base
  local width = tonumber(Z.config.width) or 120
  local height = tonumber(Z.config.height) or 80
  local x = tonumber(Z.config.x) or 0
  local y = tonumber(Z.config.y) or 8
  if width < 20 then width = 20 end
  if height < 10 then height = 10 end

  -- GudaPlates and similar replacements hide every unrecognized direct child
  -- of the Blizzard plate. Live under their visible overlay instead.
  if parent and record.frame.GetParent and record.frame:GetParent() ~= parent then
    record.frame:SetParent(parent)
  end
  if record.frame.SetAlpha then record.frame:SetAlpha(1) end
  if record.frame.SetFrameStrata then
    record.frame:SetFrameStrata(SafeFrameStrata(parent or anchor))
  end
  record.anchor = anchor
  record.frame:ClearAllPoints()
  record.frame:SetPoint("BOTTOM", anchor, "TOP", x, y)
  record.frame:SetSize(width, height)
  local anchorLevel = anchor.GetFrameLevel and anchor:GetFrameLevel() or 1
  record.frame:SetFrameLevel(math.max(0, anchorLevel - 1))
  record.frame.configHeight = height
end

local function CreateRecord(base)
  local recycled = table.remove(recycledRecords)
  if recycled then
    recycled.base = base
    recycled.frame:SetParent(base)
    recycled.frame:SetScale(1)
    recycled.frame:SetFrameStrata(SafeFrameStrata(base))
    recordsByPlate[base] = recycled
    ConfigureRecord(recycled)
    return recycled
  end

  local record = { base = base }
  local frame = CreateFrame("Frame", nil, base)
  frame.items = {}
  for i = 1, TEXT_SLOTS do
    local item = { text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal") }
    item.text:Hide()
    frame.items[i] = item
  end
  frame:Hide()
  record.frame = frame
  recordsByPlate[base] = record
  ConfigureRecord(record)
  return record
end

local function ResolvePlateUnit(base, unit, existing)
  if unit then return unit end
  if existing and existing.unit then return existing.unit end

  local visual = base.nameplate or base.UnitFrame or base.unitFrame
  return base.namePlateUnitToken or base.displayedUnit or base.unit
    or (visual and (visual.namePlateUnitToken or visual.displayedUnit
      or visual.unit or visual.cachedUnitStr))
    or PlateGuid(base)
end

local function AttachNameplate(base, unit)
  if not Z.config or not base then return end

  local record = recordsByPlate[base]
  unit = ResolvePlateUnit(base, unit, record)
  local guid = PlateGuid(base)
  if not guid and unit and UnitGUID then
    local ok, resolvedGuid = pcall(UnitGUID, unit)
    if ok then guid = resolvedGuid end
  end
  local name = PlateName(base, unit)
  if not unit and not guid and not name then return end

  local changed = record and ((record.guid and guid and record.guid ~= guid)
    or (record.unit and unit and record.unit ~= unit)
    or (not record.guid and not guid and record.name and name and record.name ~= name))
  if changed then
    visibleRecords[record] = nil
    if record.unit and recordsByUnit[record.unit] == record then recordsByUnit[record.unit] = nil end
    if record.guid and recordsByGuid[record.guid] == record then recordsByGuid[record.guid] = nil end
    if FreezeRecord(record) then record.unit = nil; record = nil end
  end

  local wasVisible = record and visibleRecords[record]
  record = record or CreateRecord(base)
  if record.unit and record.unit ~= unit and recordsByUnit[record.unit] == record then
    recordsByUnit[record.unit] = nil
  end
  if record.guid and record.guid ~= guid and recordsByGuid[record.guid] == record then
    recordsByGuid[record.guid] = nil
  end
  record.unit, record.guid = unit, guid
  record.name = name or record.name
  if unit then recordsByUnit[unit] = record end
  if guid then recordsByGuid[guid] = record end
  visibleRecords[record] = true

  if not wasVisible then ClearAnimations(record) end
  if not wasVisible or record.anchor ~= FindHealthAnchor(base) then ConfigureRecord(record) end
  return record
end

local function DetachNameplate(record)
  if not record then return end
  visibleRecords[record] = nil
  if record.unit and recordsByUnit[record.unit] == record then recordsByUnit[record.unit] = nil end
  if record.guid and recordsByGuid[record.guid] == record then recordsByGuid[record.guid] = nil end
  record.unit = nil
  if not FreezeRecord(record) then record.guid, record.name = nil, nil end
end

local function IsWorldNameplate(frame)
  if not frame then return false end
  if recordsByPlate[frame] then return true end
  if frame.nameplate and (frame.nameplate.health or frame.nameplate.healthBar
      or frame.nameplate.healthbar) then return true end
  if not frame.GetRegions then return false end

  local regions = { frame:GetRegions() }
  for i = 1, table.getn(regions) do
    local region = regions[i]
    if region and region.GetObjectType and region:GetObjectType() == "Texture"
        and region.GetTexture then
      local texture = region:GetTexture()
      if type(texture) == "string"
          and string.find(string.lower(texture), "nameplate%-border") then
        return true
      end
    end
  end
  return false
end

local function ScanVisibleNameplates()
  if not Z.config then return end

  for record in pairs(visibleRecords) do
    if record.base and record.base.IsShown and not record.base:IsShown() then
      DetachNameplate(record)
    end
  end

  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      for _, plate in pairs(plates) do
        if plate and (not plate.IsShown or plate:IsShown()) then AttachNameplate(plate) end
      end
    end
  end

  if C_NamePlate and C_NamePlate.GetNamePlateForUnit and UnitExists then
    for i = 1, 40 do
      local unit = "nameplate" .. i
      if UnitExists(unit) then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate then AttachNameplate(plate, unit) end
      end
    end

    for _, unit in pairs({ "target", "mouseover" }) do
      if UnitExists(unit) then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate and not recordsByPlate[plate] then AttachNameplate(plate, unit) end
      end
    end
  elseif UnitNameplate and UnitExists then
    for _, unit in pairs({ "target", "mouseover" }) do
      if UnitExists(unit) then
        local ok, plate = pcall(UnitNameplate, unit)
        if ok and plate then AttachNameplate(plate, unit) end
      end
    end
  end

  -- Vanilla Blizzard plates, GudaPlates, and other legacy addons may never
  -- publish NAME_PLATE_UNIT_ADDED. Their real frames still live on WorldFrame.
  if WorldFrame and WorldFrame.GetChildren then
    local childCount = WorldFrame.GetNumChildren and WorldFrame:GetNumChildren()
    if not childCount or childCount ~= cachedWorldChildCount then
      cachedWorldChildren = { WorldFrame:GetChildren() }
      cachedWorldChildCount = childCount or table.getn(cachedWorldChildren)
    end
    for i = 1, table.getn(cachedWorldChildren) do
      local plate = cachedWorldChildren[i]
      if plate and (not plate.IsShown or plate:IsShown()) and IsWorldNameplate(plate) then
        AttachNameplate(plate)
      end
    end
  end
end

local function EnableGuidEvents()
  if guidEventsEnabled or not GetNampowerVersion then return end
  pcall(SetCVar, "NP_EnableAutoAttackEvents", "1")
  pcall(SetCVar, "NP_EnableSpellDamageEvents", "1")
  pcall(SetCVar, "NP_EnableSpellMissEvents", "1")
  guidEventsEnabled = true
end

local function Enabled()
  local enabled = Z.config and Z.config.enabled == "1" and MikSBT
    and MikSBT.CurrentProfile and MikSBT.PrepareExternalAnimationEvent
    and MikSBT.GetFontSize and MikSBT.GetFontPath and MikSBT.GetFontOutline and true or false
  if enabled then EnableGuidEvents() end
  return enabled
end

local function QueueGuidHint(targetGuid, amount, spellId)
  if not targetGuid or targetGuid == "0x0000000000000000" then return end
  local now = GetTime()
  for i = table.getn(outgoingGuidHints), 1, -1 do
    if now - outgoingGuidHints[i].time > 1.5 then table.remove(outgoingGuidHints, i) end
  end
  local effectName
  if spellId and GetSpellRecField then effectName = GetSpellRecField(spellId, "name") end
  table.insert(outgoingGuidHints, {
    guid = targetGuid,
    amount = amount and tonumber(amount) or nil,
    effectName = effectName,
    isSpell = spellId ~= nil,
    time = now,
  })
end

local function ConsumeGuidHint(animationEvent)
  local now = GetTime()
  local amount = animationEvent.Amount and tonumber(animationEvent.Amount) or nil
  local isSpell = animationEvent.EffectName ~= nil
  for i = 1, table.getn(outgoingGuidHints) do
    local hint = outgoingGuidHints[i]
    if now - hint.time <= 1.5 and hint.amount == amount and hint.isSpell == isSpell and
        (not hint.effectName or not animationEvent.EffectName or hint.effectName == animationEvent.EffectName) then
      table.remove(outgoingGuidHints, i)
      return hint.guid
    end
  end
end

local function FindRecord(unitName, targetGuid)
  if targetGuid then
    -- A known target must never be reassigned solely because another plate has
    -- the same name. Recently removed targets retain their frozen text frame.
    local record = recordsByGuid[targetGuid] or fadingRecordsByGuid[targetGuid]
    if record then return record end
  end
  if not unitName or unitName == "" then return nil end

  local matches = {}
  for record in pairs(visibleRecords) do
    local name = record.name
    if record.unit and UnitName then
      local ok, unitNameNow = pcall(UnitName, record.unit)
      if ok and unitNameNow and unitNameNow ~= "" then name = unitNameNow end
    end
    if name == unitName and (not targetGuid or not record.guid) then
      table.insert(matches, record)
    end
  end
  local count = table.getn(matches)
  if count == 0 then return nil end
  -- GUID-bearing combat events may use a name-only legacy plate when that
  -- plate is unambiguous, but never guess between same-named targets.
  if targetGuid and count ~= 1 then return nil end
  if count == 1 then return matches[1] end

  -- Name-only combat messages cannot distinguish identical AoE targets. Rotate
  -- them across every matching visible plate; Nampower GUID hints take priority.
  local cursor = (duplicateNameCursor[unitName] or 0) + 1
  if cursor > count then cursor = 1 end
  duplicateNameCursor[unitName] = cursor
  return matches[cursor]
end

local function AddAnimation(record, animationEvent)
  if not record or not record.frame then return end
  if not record.frozen then ConfigureRecord(record) end
  local frame = record.frame
  local now = GetTime()
  local slot, oldest
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if not item.active then
      slot = item
      break
    elseif not oldest or item.startTime < oldest.startTime then
      oldest = item
    end
  end
  slot = slot or oldest
  if not slot then return end

  local settings = animationEvent.EventSettings
  local size = MikSBT.GetFontSize(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local font = MikSBT.GetFontPath(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local outline = MikSBT.GetFontOutline(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local anchor, justify = Alignment()
  local spacing = size + 8

  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item.active and item ~= slot and item.position < spacing then
      item.position = math.min(frame.configHeight, item.position + spacing)
    end
  end

  slot.active = true
  slot.startTime = now
  slot.lastUpdate = now
  slot.position = 0
  slot.text:ClearAllPoints()
  slot.text:SetPoint(anchor, frame, anchor, 0, 0)
  slot.text:SetJustifyH(justify)
  slot.text:SetFont(font, math.max(1, size - 1), outline)
  slot.text:SetTextHeight(math.max(1, size))
  slot.text:SetTextColor(settings.FontSettings.Color.r, settings.FontSettings.Color.g, settings.FontSettings.Color.b)
  slot.text:SetText(animationEvent.Text)
  slot.text:SetAlpha(1)
  slot.text:Show()
  frame:Show()
end

local function UpdateAnimations(record, now)
  local frame = record and record.frame
  if not frame or not frame:IsShown() then return end
  if not Enabled() then
    if record.frozen then ReleaseFadingRecord(record) else ClearAnimations(record) end
    return
  end

  local height = frame.configHeight or tonumber(Z.config.height) or 80
  local speed = tonumber(MikSBT.CurrentProfile.TextSpeed) or 75
  local fadeDelay = tonumber(Z.config.fade) or .5
  if speed <= 0 then speed = 75 end
  if fadeDelay < 0 then fadeDelay = 0 end
  local travelTime = height / speed
  local fadeTime = travelTime - fadeDelay
  local anchor, justify = Alignment()
  local anyActive

  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item.active then
      item.position = item.position + speed * (now - item.lastUpdate)
      item.lastUpdate = now
      local elapsed = now - item.startTime
      if item.position >= height then
        item.active = nil
        item.text:Hide()
      else
        anyActive = true
        local alpha = 1
        if elapsed > fadeDelay and fadeTime > 0 then
          alpha = 1 - ((elapsed - fadeDelay) / fadeTime)
          if alpha < 0 then alpha = 0 end
        end
        item.text:ClearAllPoints()
        item.text:SetPoint(anchor, frame, anchor, 0, item.position)
        item.text:SetJustifyH(justify)
        item.text:SetAlpha(alpha)
      end
    end
  end
  if not anyActive then
    frame:Hide()
    if record.frozen then ReleaseFadingRecord(record) end
  end
end

local function HandleOutgoing(animationEvent)
  local targetGuid = animationEvent.TargetGUID or ConsumeGuidHint(animationEvent)
  if not MikSBT.PrepareExternalAnimationEvent(animationEvent) then return end
  local record = FindRecord(animationEvent.Name, targetGuid)
  if not record then
    ScanVisibleNameplates()
    record = FindRecord(animationEvent.Name, targetGuid)
  end
  if record then AddAnimation(record, animationEvent) end
end

local function RegisterMSBTIntegration()
  if MikSBT and MikSBT.RegisterOutgoingNameplateHandler then
    MikSBT.RegisterOutgoingNameplateHandler(HandleOutgoing, Enabled, ConsumeGuidHint)
    Enabled()
  end
end

function Z.Refresh()
  ScanVisibleNameplates()
  for record in pairs(visibleRecords) do
    ConfigureRecord(record)
    if not Enabled() then ClearAnimations(record) end
  end
  if Z.options and Z.options.Refresh then Z.options:Refresh() end
end

function Z.GetAttachedCount()
  local count = 0
  for record in pairs(visibleRecords) do count = count + 1 end
  return count
end

local eventFrame = CreateFrame("Frame", "zDNumbersEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(eventFrame.RegisterEvent, eventFrame, "NAME_PLATE_UNIT_ADDED")
pcall(eventFrame.RegisterEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED")

for _, eventName in pairs({
  "AUTO_ATTACK_SELF", "AUTO_ATTACK_OTHER",
  "SPELL_DAMAGE_EVENT_SELF", "SPELL_DAMAGE_EVENT_OTHER",
  "SPELL_MISS_SELF", "SPELL_MISS_OTHER",
}) do pcall(eventFrame.RegisterEvent, eventFrame, eventName) end

eventFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "z_DNumbers" then
    zDNumbersDB = type(zDNumbersDB) == "table" and zDNumbersDB or {}
    ImportLegacyConfig(zDNumbersDB)
    MergeDefaults(zDNumbersDB)
    Z.config = zDNumbersDB
    Z.EnsureEmbeddedMSBT()
    RegisterMSBTIntegration()
    ScanVisibleNameplates()
    if Z.options and Z.options.Refresh then Z.options:Refresh() end
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    Z.EnsureEmbeddedMSBT()
    RegisterMSBTIntegration()
    cachedWorldChildCount = -1
    ScanVisibleNameplates()
    return
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(arg1)
    if base then AttachNameplate(base, arg1) end
    return
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    DetachNameplate(recordsByUnit[arg1])
    return
  elseif event == "AUTO_ATTACK_SELF" then
    QueueGuidHint(arg2, arg3 and arg3 > 0 and arg3 or nil, nil)
  elseif event == "AUTO_ATTACK_OTHER" then
    if arg1 == UnitGUID("pet") then QueueGuidHint(arg2, arg3 and arg3 > 0 and arg3 or nil, nil) end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" then
    QueueGuidHint(arg1, arg4, arg3)
  elseif event == "SPELL_DAMAGE_EVENT_OTHER" then
    if arg2 == UnitGUID("pet") then QueueGuidHint(arg1, arg4, arg3) end
  elseif event == "SPELL_MISS_SELF" then
    QueueGuidHint(arg2, nil, arg3)
  elseif event == "SPELL_MISS_OTHER" then
    if arg1 == UnitGUID("pet") then QueueGuidHint(arg2, nil, arg3) end
  end
end)

eventFrame:SetScript("OnUpdate", function()
  if not Z.config then return end
  local now = GetTime()
  if now >= nextPlateScan then
    nextPlateScan = now + .25
    ScanVisibleNameplates()
  end
  for record in pairs(visibleRecords) do
    RememberRecordPosition(record)
    UpdateAnimations(record, now)
  end
  for record in pairs(fadingRecords) do UpdateAnimations(record, now) end
end)
