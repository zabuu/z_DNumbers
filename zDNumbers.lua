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
local outgoingGuidHints = {}
local duplicateNameCursor = {}
local guidEventsEnabled

local function IsStatusBar(object)
  return object and object.GetValue and object.GetMinMaxValues
    and object.GetStatusBarColor and object.SetStatusBarTexture
end

-- Prefer a host addon's exposed health bar, but make no assumptions about the
-- addon's identity. The fallback scan also supports unmodified Blizzard plates
-- and nameplate addons which only expose normal StatusBar children.
local function FindHealthAnchor(base)
  if not base then return UIParent end

  local candidates = {
    base.nameplate and base.nameplate.health,
    base.UnitFrame and base.UnitFrame.healthBar,
    base.UnitFrame and base.UnitFrame.healthbar,
    base.unitFrame and base.unitFrame.healthBar,
    base.unitFrame and base.unitFrame.healthbar,
    base.healthBar,
    base.healthbar,
  }
  for i = 1, table.getn(candidates) do
    if candidates[i] then return candidates[i] end
  end

  if IsStatusBar(base) then return base end
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

local function ConfigureRecord(record)
  if not record or not record.frame then return end
  local anchor = FindHealthAnchor(record.base)
  local width = tonumber(Z.config.width) or 120
  local height = tonumber(Z.config.height) or 80
  local x = tonumber(Z.config.x) or 0
  local y = tonumber(Z.config.y) or 8
  if width < 20 then width = 20 end
  if height < 10 then height = 10 end

  record.anchor = anchor
  record.frame:ClearAllPoints()
  record.frame:SetPoint("BOTTOM", anchor, "TOP", x, y)
  record.frame:SetSize(width, height)
  local anchorLevel = anchor.GetFrameLevel and anchor:GetFrameLevel() or 1
  record.frame:SetFrameLevel(math.max(0, anchorLevel - 1))
  record.frame.configHeight = height
end

local function CreateRecord(base)
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
  if targetGuid and recordsByGuid[targetGuid] then return recordsByGuid[targetGuid] end
  if not unitName or unitName == "" then return nil end

  local matches = {}
  for record in pairs(visibleRecords) do
    if record.unit and UnitName(record.unit) == unitName then table.insert(matches, record) end
  end
  local count = table.getn(matches)
  if count == 0 then return nil end
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
  ConfigureRecord(record)
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
  if not Enabled() then ClearAnimations(record); return end

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
  if not anyActive then frame:Hide() end
end

local function HandleOutgoing(animationEvent)
  local targetGuid = animationEvent.TargetGUID or ConsumeGuidHint(animationEvent)
  if not MikSBT.PrepareExternalAnimationEvent(animationEvent) then return end
  local record = FindRecord(animationEvent.Name, targetGuid)
  if record then AddAnimation(record, animationEvent) end
end

local function RegisterMSBTIntegration()
  if MikSBT and MikSBT.RegisterOutgoingNameplateHandler then
    MikSBT.RegisterOutgoingNameplateHandler(HandleOutgoing, Enabled, ConsumeGuidHint)
    Enabled()
  end
end

function Z.Refresh()
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
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

for _, eventName in pairs({
  "AUTO_ATTACK_SELF", "AUTO_ATTACK_OTHER",
  "SPELL_DAMAGE_EVENT_SELF", "SPELL_DAMAGE_EVENT_OTHER",
  "SPELL_MISS_SELF", "SPELL_MISS_OTHER",
}) do pcall(eventFrame.RegisterEvent, eventFrame, eventName) end

eventFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "zDNumbers" then
    zDNumbersDB = type(zDNumbersDB) == "table" and zDNumbersDB or {}
    ImportLegacyConfig(zDNumbersDB)
    MergeDefaults(zDNumbersDB)
    Z.config = zDNumbersDB
    Z.EnsureEmbeddedMSBT()
    RegisterMSBTIntegration()
    if Z.options and Z.options.Refresh then Z.options:Refresh() end
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    Z.EnsureEmbeddedMSBT()
    RegisterMSBTIntegration()
    return
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(arg1)
    if not base then return end
    local record = recordsByPlate[base] or CreateRecord(base)
    if record.unit and recordsByUnit[record.unit] == record then recordsByUnit[record.unit] = nil end
    if record.guid and recordsByGuid[record.guid] == record then recordsByGuid[record.guid] = nil end
    record.unit = arg1
    record.guid = UnitGUID(arg1)
    recordsByUnit[arg1] = record
    if record.guid then recordsByGuid[record.guid] = record end
    visibleRecords[record] = true
    ClearAnimations(record)
    ConfigureRecord(record)
    return
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local record = recordsByUnit[arg1]
    recordsByUnit[arg1] = nil
    if not record then return end
    visibleRecords[record] = nil
    if record.guid and recordsByGuid[record.guid] == record then recordsByGuid[record.guid] = nil end
    record.unit, record.guid = nil, nil
    ClearAnimations(record)
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
  for record in pairs(visibleRecords) do UpdateAnimations(record, now) end
end)
