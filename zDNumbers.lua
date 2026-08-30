zDNumbers = zDNumbers or {}

local Z = zDNumbers
local defaults = {
  enabled = "1",
  icons = "1",
  icon_opacity = "30",
  perspective_tilt = "12",
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
local SOURCE_ICON_SCALE = .70
local RESULT_ICON_SCALE = .70
local ICON_TEXT_GAP = 3
local NATIVE_MIN_SCALE = .65
local NATIVE_MAX_SCALE = 1.50
local NATIVE_DEFAULT_TRAVEL = 3
local NATIVE_MAX_TRAVEL = 6
local MAX_PERSPECTIVE_WARP = 100
local GLANCING_RESULT_ICON = "Interface\\Icons\\Ability_Whirlwind"
local PARRIED_RESULT_ICON = "Interface\\Icons\\Ability_Parry"
local BLOCKED_RESULT_ICON = "Interface\\Icons\\Ability_Defend"

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
local sourceSpellIcons = {}
local sourceSpellbookScanned
local sourceSpellLibrary
local sourceSpellLibraryChecked
local validFrameStrata = {
  BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true,
  DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}

local function SetTextPerspective(item, amount)
  if not item or not item.text or type(zAPI) ~= "function" then return end
  pcall(zAPI, "fontTrapezoid", item.text, tonumber(amount) or 0)
end

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

local function NativeProject(record, verticalOffset)
  if type(zAPI) ~= "function" or not record then return end
  local identifier = record.guid or record.unit
  if not identifier then return end
  local ok, x, y, depth, worldX, worldY, worldZ =
    pcall(zAPI, "projectUnit", identifier, verticalOffset or 0)
  if not ok or type(x) ~= "number" or type(y) ~= "number"
      or type(depth) ~= "number" or depth <= 0 then return end
  return x, y, depth, worldX, worldY, worldZ
end

local function NativeWorldToScreen(x, y, z)
  if type(zAPI) ~= "function" or type(x) ~= "number"
      or type(y) ~= "number" or type(z) ~= "number" then return end
  local ok, screenX, screenY, depth = pcall(zAPI, "worldToScreen", x, y, z)
  if not ok or type(screenX) ~= "number" or type(screenY) ~= "number"
      or type(depth) ~= "number" or depth <= 0 then return end
  return screenX, screenY, depth
end

local function FrameBottomAnchor(frame, anchor)
  if not frame then return end
  local left = frame.GetLeft and frame:GetLeft()
  local right = frame.GetRight and frame:GetRight()
  local bottom = frame.GetBottom and frame:GetBottom()
  if not left or not right or not bottom then return end
  if anchor == "BOTTOMLEFT" then return left, bottom end
  if anchor == "BOTTOMRIGHT" then return right, bottom end
  return (left + right) * .5, bottom
end

local function SourceIconAlpha()
  local opacity = tonumber(Z.config and Z.config.icon_opacity) or 30
  return math.max(0, math.min(100, opacity)) / 100
end

local function CacheSourceSpellbook(bookType)
  if not GetSpellName or not GetSpellTexture then return end
  for index = 1, 512 do
    local foundName, name = pcall(GetSpellName, index, bookType)
    if not foundName or not name or name == "" then break end
    local foundIcon, texture = pcall(GetSpellTexture, index, bookType)
    if foundIcon and texture then sourceSpellIcons[string.lower(name)] = texture end
  end
end

local function ResolveSourceIcon(animationEvent)
  if animationEvent.Texture then return animationEvent.Texture end

  local spellId = animationEvent.SpellID or animationEvent.SpellId or animationEvent.spellId
  if spellId and C_Spell and C_Spell.GetSpellTexture then
    local found, texture = pcall(C_Spell.GetSpellTexture, spellId)
    if found and texture then return texture end
  end
  if spellId and GetSpellRecField and GetSpellIconTexture then
    local foundId, iconId = pcall(GetSpellRecField, spellId, "spellIconID")
    if foundId and iconId then
      local foundIcon, texture = pcall(GetSpellIconTexture, iconId)
      if foundIcon and texture then return texture end
    end
  end

  local effectName = animationEvent.EffectName
  if type(effectName) == "string" and effectName ~= "" then
    local name = string.gsub(effectName, " %(%d+%)", "")
    local key = string.lower(name)
    if ICON_CACHE and ICON_CACHE[key] then return ICON_CACHE[key] end

    if not sourceSpellbookScanned then
      sourceSpellbookScanned = true
      CacheSourceSpellbook(BOOKTYPE_SPELL or "spell")
      CacheSourceSpellbook(BOOKTYPE_PET or "pet")
    end
    if sourceSpellIcons[key] then return sourceSpellIcons[key] end

    if not sourceSpellLibraryChecked and AceLibrary then
      sourceSpellLibraryChecked = true
      local found, library = pcall(AceLibrary, "Babble-Spell-2.2")
      if found then sourceSpellLibrary = library end
    end
    if sourceSpellLibrary and sourceSpellLibrary.GetSpellIcon then
      local found, texture = pcall(sourceSpellLibrary.GetSpellIcon, sourceSpellLibrary, name)
      if found and texture then
        sourceSpellIcons[key] = texture
        if ICON_CACHE then ICON_CACHE[key] = texture end
        return texture
      end
    end

    if MikSBT and MikSBT.FindItemIcon then
      local found, first, _, third = pcall(MikSBT.FindItemIcon, name)
      local texture = type(first) == "string" and first or third
      if found and texture then
        sourceSpellIcons[key] = texture
        if ICON_CACHE then ICON_CACHE[key] = texture end
        return texture
      end
    end

    sourceSpellIcons[key] = "Interface\\Icons\\INV_Misc_QuestionMark"
    return sourceSpellIcons[key]
  end

  local eventType = animationEvent.EventType
  if type(eventType) == "string" and string.find(eventType, "PET", 1, true) then
    return "Interface\\Icons\\Ability_Druid_Maul"
  end
  if GetInventoryItemTexture then
    local found, texture = pcall(GetInventoryItemTexture, "player", 16)
    if found and texture then return texture end
  end
  return "Interface\\Icons\\Ability_MeleeDamage"
end

local function SetSourceIconShown(item, shown)
  if shown then item.icon:Show() else item.icon:Hide() end
  if not item.iconPieces then return end
  for i = 1, table.getn(item.iconPieces) do
    if shown and item.roundedIcon then item.iconPieces[i]:Show()
    else item.iconPieces[i]:Hide() end
  end
end

local function SetSourceIconAlpha(item, alpha)
  item.icon:SetAlpha(alpha)
  if not item.iconPieces then return end
  for i = 1, table.getn(item.iconPieces) do item.iconPieces[i]:SetAlpha(alpha) end
end

local function ConfigureRoundedSourceIcon(item, size)
  if size < 6 then
    item.roundedIcon = nil
    item.icon:SetWidth(size)
    item.icon:SetHeight(size)
    if item.icon.SetTexCoord then item.icon:SetTexCoord(.08, .92, .08, .92) end
    return
  end

  -- Vanilla textures cannot be alpha-masked. Stacking cropped strips produces
  -- genuinely transparent, rounded corners while preserving the source art.
  if not item.iconPieces then
    item.iconPieces = {}
    for i = 1, 4 do item.iconPieces[i] = item.frame:CreateTexture(nil, "BORDER") end
  end

  local corner = math.min(math.floor((size - 1) / 2),
    math.max(2, math.floor(size * .20 + .5)))
  local cap = math.max(1, math.floor(corner / 2))
  local shoulder = corner - cap
  local capInset = math.max(1, corner - 1)
  local shoulderInset = math.max(1, math.floor(corner * .45 + .5))
  local middle = size - corner * 2
  local crop, span = .08, .84

  item.roundedIcon = true
  item.icon:SetWidth(size)
  item.icon:SetHeight(middle)
  if item.icon.SetTexCoord then
    item.icon:SetTexCoord(crop, 1 - crop,
      crop + span * corner / size, 1 - crop - span * corner / size)
  end

  local function ConfigurePiece(piece, point, relative, relativePoint, height, inset, top)
    piece:ClearAllPoints()
    piece:SetPoint(point, relative, relativePoint, 0, 0)
    piece:SetWidth(size - inset * 2)
    piece:SetHeight(height)
    piece:SetTexture(item.iconTexture)
    if piece.SetTexCoord then
      piece:SetTexCoord(crop + span * inset / size, 1 - crop - span * inset / size,
        crop + span * top / size, crop + span * (top + height) / size)
    end
  end

  local topShoulder, topCap = item.iconPieces[1], item.iconPieces[2]
  local bottomShoulder, bottomCap = item.iconPieces[3], item.iconPieces[4]
  ConfigurePiece(topShoulder, "BOTTOM", item.icon, "TOP", shoulder, shoulderInset, cap)
  ConfigurePiece(topCap, "BOTTOM", topShoulder, "TOP", cap, capInset, 0)
  ConfigurePiece(bottomShoulder, "TOP", item.icon, "BOTTOM", shoulder,
    shoulderInset, size - corner)
  ConfigurePiece(bottomCap, "TOP", bottomShoulder, "BOTTOM", cap,
    capInset, size - cap)
end

local function ConfigureSourceIcon(item)
  if not item or not item.icon then return end
  if not item.active or not item.iconTexture or not Z.config or Z.config.icons ~= "1" then
    SetSourceIconShown(item, false)
    return
  end

  local size = math.max(1, math.floor((item.visualSize or item.fontSize or 12)
    * SOURCE_ICON_SCALE + .5))
  item.icon:ClearAllPoints()
  item.icon:SetPoint("RIGHT", item.text, "LEFT", -ICON_TEXT_GAP, 0)
  item.icon:SetTexture(item.iconTexture)
  ConfigureRoundedSourceIcon(item, size)
  local alpha = item.text.GetAlpha and item.text:GetAlpha() or 1
  SetSourceIconAlpha(item, alpha * SourceIconAlpha())
  SetSourceIconShown(item, true)
end

local function ConfigureResultIcon(item)
  local result = item and item.result
  if not result then return end
  result.active = item.active
  result.fontSize = item.visualSize or item.fontSize
  result.iconTexture = item.resultIconTexture
  if not item.active or not result.iconTexture then
    SetSourceIconShown(result, false)
    return
  end

  local size = math.max(1, math.floor((item.visualSize or item.fontSize or 12)
    * RESULT_ICON_SCALE + .5))
  result.icon:ClearAllPoints()
  result.icon:SetPoint("LEFT", item.text, "RIGHT", ICON_TEXT_GAP, 0)
  result.icon:SetTexture(result.iconTexture)
  ConfigureRoundedSourceIcon(result, size)
  SetSourceIconAlpha(result, item.text.GetAlpha and item.text:GetAlpha() or 1)
  SetSourceIconShown(result, true)
end

local function ClearAnimations(record)
  if not record or not record.frame then return end
  for i = 1, TEXT_SLOTS do
    local item = record.frame.items[i]
    item.active = nil
    item.text:Hide()
    SetSourceIconShown(item, false)
    SetSourceIconShown(item.result, false)
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
    local resultIcon = frame:CreateTexture(nil, "BORDER")
    local item = {
      text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
      icon = frame:CreateTexture(nil, "BORDER"),
      result = { icon = resultIcon, frame = frame },
      frame = frame,
    }
    item.text:Hide()
    item.icon:Hide()
    resultIcon:Hide()
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
    spellId = spellId,
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
      if hint.spellId and not animationEvent.SpellID then animationEvent.SpellID = hint.spellId end
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
  local colorR = settings.FontSettings.Color.r
  local colorG = settings.FontSettings.Color.g
  local colorB = settings.FontSettings.Color.b
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
  slot.fontSize = size
  slot.visualSize = size
  slot.native3D = nil
  slot.nativeTravel = nil
  slot.nativeBaseX, slot.nativeBaseY, slot.nativeBaseZ = nil, nil, nil
  slot.nativeCorrectionX, slot.nativeCorrectionY = nil, nil
  slot.perspectiveWarp = 0
  SetTextPerspective(slot, 0)

  local baseX, baseY, baseDepth, baseWorldX, baseWorldY, baseWorldZ =
    NativeProject(record, 0)
  local raisedX, raisedY = NativeProject(record, 1)
  if baseX and raisedX and UIParent and UIParent.GetWidth and UIParent.GetHeight then
    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    local deltaX = (raisedX - baseX) * uiWidth
    local deltaY = (raisedY - baseY) * uiHeight
    local pixelsPerWorldUnit = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local configuredHeight = frame.configHeight or tonumber(Z.config.height) or 80
    local travel = NATIVE_DEFAULT_TRAVEL
    if pixelsPerWorldUnit > 1 then travel = configuredHeight / pixelsPerWorldUnit end
    travel = math.max(.5, math.min(NATIVE_MAX_TRAVEL, travel))
    slot.native3D = true
    slot.nativeTravel = travel
    slot.nativeBaseDepth = baseDepth
    slot.nativeBaseX, slot.nativeBaseY, slot.nativeBaseZ =
      baseWorldX, baseWorldY, baseWorldZ
  end
  slot.iconTexture = ResolveSourceIcon(animationEvent)
  slot.resultIconTexture = animationEvent.IsBlocked and BLOCKED_RESULT_ICON
    or animationEvent.IsParried and PARRIED_RESULT_ICON
    or animationEvent.IsGlancing and GLANCING_RESULT_ICON or nil
  slot.text:ClearAllPoints()
  slot.text:SetPoint(anchor, frame, anchor, 0, 0)
  slot.text:SetJustifyH(justify)
  local fontSurfaceSize = slot.native3D
    and math.floor(size * NATIVE_MAX_SCALE + .5) or size - 1
  slot.text:SetFont(font, math.max(1, fontSurfaceSize), outline)
  slot.text:SetTextHeight(math.max(1, size))
  slot.text:SetTextColor(colorR, colorG, colorB)
  -- Full blocks and parries have no damage amount, so their result icon
  -- replaces the localized message. Partial blocks retain the damage number.
  local iconOnlyResult = (animationEvent.IsBlocked or animationEvent.IsParried)
    and (not animationEvent.Amount or tonumber(animationEvent.Amount) == 0)
  slot.text:SetText(iconOnlyResult and "" or animationEvent.Text)
  slot.text:SetAlpha(1)
  slot.text:Show()
  ConfigureSourceIcon(slot)
  ConfigureResultIcon(slot)
  frame:Show()
end

local function RetireAnimationItem(item)
  item.active = nil
  item.native3D = nil
  item.visualSize = nil
  item.perspectiveWarp = nil
  SetTextPerspective(item, 0)
  item.text:Hide()
  SetSourceIconShown(item, false)
  SetSourceIconShown(item.result, false)
end

local function NativeAnimationPlacement(record, item, anchor, height)
  if not item.native3D or not UIParent or not UIParent.GetWidth
      or not UIParent.GetHeight then return end
  local progress = math.max(0, math.min(1, item.position / height))
  local worldOffset = progress * (item.nativeTravel or NATIVE_DEFAULT_TRAVEL)

  local baseX, baseY, baseDepth, baseWorldX, baseWorldY, baseWorldZ =
    NativeProject(record, 0)
  local pointX, pointY, pointDepth, pointWorldX, pointWorldY, pointWorldZ =
    NativeProject(record, worldOffset)

  if baseX and pointX then
    item.nativeBaseX, item.nativeBaseY, item.nativeBaseZ =
      baseWorldX, baseWorldY, baseWorldZ
    item.nativePointX, item.nativePointY, item.nativePointZ =
      pointWorldX, pointWorldY, pointWorldZ
  elseif item.nativeBaseX and item.nativeBaseY and item.nativeBaseZ then
    baseX, baseY, baseDepth = NativeWorldToScreen(
      item.nativeBaseX, item.nativeBaseY, item.nativeBaseZ)
    pointWorldX, pointWorldY = item.nativeBaseX, item.nativeBaseY
    pointWorldZ = item.nativeBaseZ + worldOffset
    pointX, pointY, pointDepth = NativeWorldToScreen(
      pointWorldX, pointWorldY, pointWorldZ)
    item.nativePointX, item.nativePointY, item.nativePointZ =
      pointWorldX, pointWorldY, pointWorldZ
  end
  if not baseX or not pointX then return end

  local uiWidth = UIParent:GetWidth()
  local uiHeight = UIParent:GetHeight()
  if not record.frozen then
    local originX, originY = FrameBottomAnchor(record.frame, anchor)
    if originX and originY then
      item.nativeCorrectionX = originX - baseX * uiWidth
      item.nativeCorrectionY = originY - baseY * uiHeight
    end
  end
  if not item.nativeCorrectionX or not item.nativeCorrectionY then return end

  local scale = baseDepth / pointDepth
  scale = math.max(NATIVE_MIN_SCALE, math.min(NATIVE_MAX_SCALE, scale))
  item.visualSize = (item.fontSize or 12) * scale

  -- Keep the baseline camera-horizontal. zAPI reshapes each glyph quad into a
  -- subtle trapezoid: narrower at the bottom and wider at the top.
  local warp = tonumber(Z.config and Z.config.perspective_tilt) or 12
  warp = math.max(0, math.min(MAX_PERSPECTIVE_WARP, warp))
  item.perspectiveWarp = warp / 100
  return pointX * uiWidth + item.nativeCorrectionX,
    pointY * uiHeight + item.nativeCorrectionY
end

local function ResolveAnimationSpacing(frame, height)
  local layout = frame.collisionLayout
  if not layout then
    layout = {}
    frame.collisionLayout = layout
  end
  local oldCount = frame.collisionLayoutCount or 0
  local count = 0
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item.active then
      count = count + 1
      layout[count] = item
    end
  end
  for i = count + 1, oldCount do layout[i] = nil end
  frame.collisionLayoutCount = count

  -- Avoid table.getn/table.insert/table.sort here. Vanilla-compatible clients
  -- can preserve a stale implicit array size on reused tables, producing nil
  -- holes. Ten slots are cheaper and safer to sort explicitly.
  for i = 2, count do
    local item = layout[i]
    local index = i - 1
    while index >= 1 and layout[index].position > item.position do
      layout[index + 1] = layout[index]
      index = index - 1
    end
    layout[index + 1] = item
  end

  local previous
  for i = 1, count do
    local item = layout[i]
    if previous then
      local minimumGap = ((previous.fontSize or 12)
        + (item.fontSize or 12)) * .5 + 4
      item.position = math.max(item.position, previous.position + minimumGap)
    end
    if item.position >= height then
      -- A crowded area cannot display unlimited events without overlap. End
      -- the oldest/topmost entries early instead of drawing them together.
      RetireAnimationItem(item)
    else
      previous = item
    end
  end
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
  local iconAlpha = SourceIconAlpha()
  -- Move first, resolve collisions second, and render last. Keeping those
  -- phases separate prevents mixed crit/normal sizes from crossing visually.
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item.active then
      item.position = item.position + speed * (now - item.lastUpdate)
      item.lastUpdate = now
      if item.position >= height then
        RetireAnimationItem(item)
      end
    end
  end

  ResolveAnimationSpacing(frame, height)

  local anyActive
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item.active then
      anyActive = true
      local elapsed = now - item.startTime
      local alpha = 1
      if elapsed > fadeDelay and fadeTime > 0 then
        alpha = 1 - ((elapsed - fadeDelay) / fadeTime)
        if alpha < 0 then alpha = 0 end
      end
      item.text:ClearAllPoints()
      -- Restore the unwarped glyph vertices before a possible text-height
      -- rebuild, then apply the current frame's perspective after layout.
      SetTextPerspective(item, 0)
      local nativeX, nativeY = NativeAnimationPlacement(record, item, anchor, height)
      if nativeX and nativeY then
        item.text:SetPoint(anchor, UIParent, "BOTTOMLEFT", nativeX, nativeY)
        item.text:SetTextHeight(math.max(1, item.visualSize or item.fontSize or 12))
      else
        item.visualSize = item.fontSize
        item.perspectiveWarp = 0
        item.text:SetPoint(anchor, frame, anchor, 0, item.position)
        item.text:SetTextHeight(math.max(1, item.fontSize or 12))
      end
      SetTextPerspective(item, item.perspectiveWarp or 0)
      item.text:SetJustifyH(justify)
      item.text:SetAlpha(alpha)
      if item.native3D then
        ConfigureSourceIcon(item)
        ConfigureResultIcon(item)
      end
      if item.icon:IsShown() then SetSourceIconAlpha(item, alpha * iconAlpha) end
      if item.result.icon:IsShown() then SetSourceIconAlpha(item.result, alpha) end
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
    for i = 1, TEXT_SLOTS do
      ConfigureSourceIcon(record.frame.items[i])
      ConfigureResultIcon(record.frame.items[i])
    end
  end
  for record in pairs(fadingRecords) do
    for i = 1, TEXT_SLOTS do
      ConfigureSourceIcon(record.frame.items[i])
      ConfigureResultIcon(record.frame.items[i])
    end
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
  "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PET_BAR_UPDATE", "UNIT_PET",
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
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB"
      or event == "PET_BAR_UPDATE" or event == "UNIT_PET" then
    sourceSpellIcons = {}
    sourceSpellbookScanned = nil
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
