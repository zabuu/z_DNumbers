zDNumbers = zDNumbers or {}

local Z = zDNumbers
local defaults = {
  enabled = "1",
  icons = "1",
  icon_opacity = "55",
  perspective_tilt = "30",
  x = "0",
  y = "8",
  width = "120",
  height = "142",
  fade = ".65",
  align = "CENTER",
  split_pet = "0",
  pet_anchor = "PET",
  pet_forward = ".65",
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

local STREAM_SLOTS = 10
local TEXT_SLOTS = STREAM_SLOTS * 2
local PET_STREAM_GAP = 2
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
local animatingRecords = {}
local fadingRecords = {}
local fadingRecordsByGuid = {}
local recycledRecords = {}
local outgoingGuidHints = {}
local duplicateNameCursor = {}
local guidEventsEnabled
local cachedWorldChildren = {}
local cachedWorldChildCount = -1
local nextPlateScan = 0
local nextLegacyPlateScan = 0
local lastOutgoingPlateScan
local petScreenSample = {}
local petWorldSample = {}
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
  amount = tonumber(amount) or 0
  if item.appliedPerspective == amount and item.perspectiveAPI == zAPI then return end
  local ok, applied = pcall(zAPI, "fontTrapezoid", item.text, amount)
  if ok and applied and applied ~= 0 then
    item.appliedPerspective, item.perspectiveAPI = amount, zAPI
  end
end

local function SafeFrameStrata(frame)
  return "TOOLTIP"
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

local function IsPetAnimation(animationEvent)
  -- MSBT's parser marks the source before formatting/recycling the event.
  return type(animationEvent.EventType) == "string"
    and string.find(animationEvent.EventType, "^MSBT_EVENTTYPE_OUTGOING_PET_") ~= nil
end

local function NativeProject(record, verticalOffset, now)
  if type(zAPI) ~= "function" or not record then return end
  local identifier = record.guid or record.unit
  if not identifier then return end
  verticalOffset = verticalOffset or 0
  now = now or GetTime()
  local sample = record.nativeProjectionSample
  if not sample then sample = {}; record.nativeProjectionSample = sample end
  if verticalOffset == 0 and sample.time == now and sample.api == zAPI and sample.identifier == identifier then
    return sample.x, sample.y, sample.depth, sample.wx, sample.wy, sample.wz
  end
  local ok, x, y, depth, worldX, worldY, worldZ
  if record.petOwner then
    ok, x, y, depth, worldX, worldY, worldZ = pcall(zAPI, "projectUnitForward", identifier,
      verticalOffset + .25, tonumber(Z.config.pet_forward) or .65)
    -- Older DLLs retain a safe head anchor until the native update is installed.
    if not ok or type(x) ~= "number" then
      ok, x, y, depth, worldX, worldY, worldZ = pcall(zAPI, "projectUnit", identifier, verticalOffset + .25)
    end
  else
    ok, x, y, depth, worldX, worldY, worldZ = pcall(zAPI, "projectUnit", identifier, verticalOffset)
  end
  if verticalOffset == 0 then
    sample.time, sample.api, sample.identifier = now, zAPI, identifier
    sample.x, sample.y, sample.depth, sample.wx, sample.wy, sample.wz = nil, nil, nil, nil, nil, nil
  end
  if not ok or type(x) ~= "number" or type(y) ~= "number"
      or type(depth) ~= "number" or depth <= 0 then return end
  if verticalOffset == 0 then sample.x, sample.y, sample.depth, sample.wx, sample.wy, sample.wz = x, y, depth, worldX, worldY, worldZ end
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

local function PetScreenPosition(now)
  -- One camera projection per rendered frame, shared by every active stream.
  if petScreenSample.time == now and petScreenSample.api == zAPI then
    return petScreenSample.x, petScreenSample.y
  end
  petScreenSample.time, petScreenSample.api = now, zAPI
  petScreenSample.x, petScreenSample.y = nil, nil
  if UnitExists and not UnitExists("pet") then return end
  if type(zAPI) == "function" then
    local ok, x, y, depth = pcall(zAPI, "projectUnit", "pet", 0)
    if ok and type(x) == "number" and type(y) == "number" and x == x and y == y
        and type(depth) == "number" and depth > 0 then
      petScreenSample.x, petScreenSample.y = x * UIParent:GetWidth(), y * UIParent:GetHeight()
      return petScreenSample.x, petScreenSample.y
    end
    -- A pet behind the camera/projection gap has no trustworthy direction.
    -- Do not switch to a clamped native plate and accidentally reverse it.
    return
  end
  -- Without the DLL, a visible pet nameplate can still supply a screen point.
  local guid = UnitGUID and UnitGUID("pet")
  local petRecord = recordsByUnit.pet or (guid and recordsByGuid[guid])
  local petFrame
  if petRecord and not petRecord.frozen and petRecord.base
      and (not petRecord.base.IsVisible or petRecord.base:IsVisible()) then
    -- Its healthbar may be hidden by the host addon; it still has a valid center.
    petFrame = petRecord.anchor or petRecord.base
  end
  if not petFrame and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    petFrame = C_NamePlate.GetNamePlateForUnit("pet")
  end
  if petFrame and petFrame.GetCenter and (petRecord or not petFrame.IsVisible or petFrame:IsVisible()) then
    local x, y = petFrame:GetCenter()
    if x and y then
      local scale = (petFrame.GetEffectiveScale and petFrame:GetEffectiveScale() or 1)
        / math.max(.001, UIParent:GetEffectiveScale())
      petScreenSample.x, petScreenSample.y = x * scale, y * scale
    end
  end
  return petScreenSample.x, petScreenSample.y
end

local function PetWorldPosition(now)
  -- Read only XY: terrain/pet height must never pitch the orbit. Share this
  -- snapshot across all active nameplates, including a pet off screen.
  if petWorldSample.time == now and petWorldSample.api == zAPI then
    return petWorldSample.x, petWorldSample.y
  end
  petWorldSample.time, petWorldSample.api = now, zAPI
  petWorldSample.x, petWorldSample.y = nil, nil
  if type(zAPI) ~= "function" or UnitExists and not UnitExists("pet") then return end
  local ok, x, y = pcall(zAPI, "unitPosition", "pet")
  if ok and type(x) == "number" and type(y) == "number" and x == x and y == y
      and math.abs(x) < math.huge and math.abs(y) < math.huge then
    petWorldSample.x, petWorldSample.y = x, y
  end
  return petWorldSample.x, petWorldSample.y
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
  if item.sourceIconShown == shown and item.sourceIconRounded == item.roundedIcon then return end
  item.sourceIconShown, item.sourceIconRounded = shown, item.roundedIcon
  if shown then item.icon:Show() else item.icon:Hide() end
  if not item.iconPieces then return end
  for i = 1, table.getn(item.iconPieces) do
    if shown and item.roundedIcon then item.iconPieces[i]:Show()
    else item.iconPieces[i]:Hide() end
  end
end

local function SetSourceIconAlpha(item, alpha)
  if item.sourceIconAlpha == alpha then return end
  item.sourceIconAlpha = alpha
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
    for i = 1, 4 do item.iconPieces[i] = item.frame:CreateTexture(nil, "ARTWORK") end
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
  if item.configuredIconSize ~= size or item.configuredIconTexture ~= item.iconTexture then
    item.icon:ClearAllPoints()
    item.icon:SetPoint("RIGHT", item.text, "LEFT", -ICON_TEXT_GAP, 0)
    item.icon:SetTexture(item.iconTexture)
    ConfigureRoundedSourceIcon(item, size)
    item.sourceIconAlpha = nil
    item.configuredIconSize, item.configuredIconTexture = size, item.iconTexture
  end
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
  if result.configuredIconSize ~= size or result.configuredIconTexture ~= result.iconTexture then
    result.icon:ClearAllPoints()
    result.icon:SetPoint("LEFT", item.text, "RIGHT", ICON_TEXT_GAP, 0)
    result.icon:SetTexture(result.iconTexture)
    ConfigureRoundedSourceIcon(result, size)
    result.sourceIconAlpha = nil
    result.configuredIconSize, result.configuredIconTexture = size, result.iconTexture
  end
  SetSourceIconAlpha(result, item.text.GetAlpha and item.text:GetAlpha() or 1)
  SetSourceIconShown(result, true)
end

local function ClearAnimations(record)
  if not record or not record.frame then return end
  animatingRecords[record] = nil
  record.frame.spacingLastTime = nil
  record.frame.petStreamOffset = nil
  record.frame.petStreamOffsetY, record.frame.petStreamAngle = nil, nil
  record.frame.petStreamYaw, record.frame.petStreamRadius = nil, nil
  record.frame.petZipper = nil
  record.frame.petStreamWorldX, record.frame.petStreamWorldY, record.frame.petStreamWorldZ = nil, nil, nil
  for i = 1, TEXT_SLOTS do
    local item = record.frame.items[i]
    if item then
      item.active = nil
      item.fallbackEvent = nil
      item.petOrbitRadius, item.petPlacedTime = nil, nil
      SetTextPerspective(item, 0)
      item.text:Hide()
      SetSourceIconShown(item, false)
      SetSourceIconShown(item.result, false)
    end
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
    if record.frame.items[i] and record.frame.items[i].active then hasAnimations = true; break end
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
  frame:SetFrameStrata("TOOLTIP")
  frame:SetFrameLevel(100)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", record.screenX, record.screenY)
  frame:Show()
  return true
end

local function ConfigureRecord(record)
  if not record or not record.frame then return end
  if record.petOwner then
    local width=math.max(20,tonumber(Z.config.width) or 120)
    local height=math.max(10,tonumber(Z.config.height) or 142)
    if record.configWidth~=width or record.configHeight~=height then
      record.frame:SetSize(width,height); record.frame.configHeight=height
      record.configWidth,record.configHeight=width,height
    end
    return
  end
  local anchor = FindHealthAnchor(record.base)
  local parent = anchor.GetParent and anchor:GetParent() or record.base
  local width = tonumber(Z.config.width) or 120
  local height = tonumber(Z.config.height) or 80
  local x = tonumber(Z.config.x) or 0
  local y = tonumber(Z.config.y) or 8
  if width < 20 then width = 20 end
  if height < 10 then height = 10 end
  if record.anchor == anchor and record.configParent == parent and record.configWidth == width
      and record.configHeight == height and record.configX == x and record.configY == y
      and (not record.frame.GetParent or record.frame:GetParent() == parent) then return end

  -- GudaPlates and similar replacements hide every unrecognized direct child
  -- of the Blizzard plate. Live under their visible overlay instead.
  if parent and record.frame.GetParent and record.frame:GetParent() ~= parent then
    record.frame:SetParent(parent)
  end
  if record.frame.SetAlpha then record.frame:SetAlpha(1) end
  if record.frame.SetFrameStrata then
    record.frame:SetFrameStrata("TOOLTIP")
  end
  record.anchor = anchor
  record.frame:ClearAllPoints()
  record.frame:SetPoint("BOTTOM", anchor, "TOP", x, y)
  record.frame:SetSize(width, height)
  record.frame:SetFrameLevel(100)
  record.frame.configHeight = height
  record.configParent, record.configWidth, record.configHeight, record.configX, record.configY = parent, width, height, x, y
end

local function CreateAnimationItem(frame)
  local resultIcon = frame:CreateTexture(nil, "ARTWORK")
  local item = {
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
    icon = frame:CreateTexture(nil, "ARTWORK"),
    result = { icon = resultIcon, frame = frame }, frame = frame,
  }
  item.text:Hide(); item.icon:Hide(); resultIcon:Hide()
  return item
end

local function CreateRecord(base)
  local recycled = table.remove(recycledRecords)
  if recycled then
    recycled.base = base
    recycled.anchor = nil
    recycled.frame:SetParent(base)
    recycled.frame:SetScale(1)
    recycled.frame:SetFrameStrata("TOOLTIP")
    recycled.frame:SetFrameLevel(100)
    recordsByPlate[base] = recycled
    ConfigureRecord(recycled)
    return recycled
  end

  local record = { base = base }
  local frame = CreateFrame("Frame", nil, base)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetFrameLevel(100)
  frame.items = {}
  -- Allocate slots only when numbers actually use them, not on crowd arrival.
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
    or (not (record.guid and guid) and record.unit and unit and record.unit ~= unit)
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

local function ScanVisibleNameplates(forceLegacy)
  if not Z.config then return end
  local modernScan, scanned = false, {}

  for record in pairs(visibleRecords) do
    if record.base and record.base.IsShown and not record.base:IsShown() then
      DetachNameplate(record)
    end
  end

  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
      modernScan = true
      for _, plate in pairs(plates) do
        if plate and (not plate.IsShown or plate:IsShown()) then AttachNameplate(plate); scanned[plate] = true end
      end
    end
  end

  if C_NamePlate and C_NamePlate.GetNamePlateForUnit and UnitExists then
    for i = 1, 40 do
      local unit = "nameplate" .. i
      if UnitExists(unit) then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate and (not scanned[plate] or not recordsByPlate[plate] or recordsByPlate[plate].unit ~= unit) then AttachNameplate(plate, unit); scanned[plate] = true end
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
  if (not modernScan or forceLegacy or GetTime() >= nextLegacyPlateScan) and WorldFrame and WorldFrame.GetChildren then
    nextLegacyPlateScan = GetTime()+1
    local childCount = WorldFrame.GetNumChildren and WorldFrame:GetNumChildren()
    if not childCount or childCount ~= cachedWorldChildCount then
      cachedWorldChildren = { WorldFrame:GetChildren() }
      cachedWorldChildCount = childCount or table.getn(cachedWorldChildren)
    end
    for i = 1, table.getn(cachedWorldChildren) do
      local plate = cachedWorldChildren[i]
      if plate and not scanned[plate] and (not plate.IsShown or plate:IsShown()) and IsWorldNameplate(plate) then
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

local function QueueGuidHint(targetGuid, amount, spellId, isPet)
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
    isPet = isPet and true or false,
    time = now,
  })
end

local function ConsumeGuidHint(animationEvent)
  local now = GetTime()
  local amount = animationEvent.Amount and tonumber(animationEvent.Amount) or nil
  local isSpell = animationEvent.EffectName ~= nil
  local isPet = IsPetAnimation(animationEvent)
  for i = 1, table.getn(outgoingGuidHints) do
    local hint = outgoingGuidHints[i]
    if now - hint.time <= 1.5 and hint.isPet == isPet and hint.amount == amount and hint.isSpell == isSpell and
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
  if not frame:IsShown() then frame.spacingLastTime = now end
  local isPet = IsPetAnimation(animationEvent)
  local split = Z.config.split_pet == "1"
  local slot, oldest, freeIndex
  local streamCount = 0
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if not item or not item.active then
      if not freeIndex then freeIndex = i end
    elseif not split or item.isPet == isPet then
      streamCount = streamCount + 1
      if not oldest or item.startTime < oldest.startTime then oldest = item end
    end
  end
  if streamCount >= STREAM_SLOTS then
    slot = oldest
  elseif freeIndex then
    slot = frame.items[freeIndex] or CreateAnimationItem(frame)
    frame.items[freeIndex] = slot
  end
  if not slot then return end

  local settings = animationEvent.EventSettings
  local size = MikSBT.GetFontSize(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local font = MikSBT.GetFontPath(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local outline = MikSBT.GetFontOutline(animationEvent.ScrollArea, settings, animationEvent.IsCrit)
  local colorR = settings.FontSettings.Color.r
  local colorG = settings.FontSettings.Color.g
  local colorB = settings.FontSettings.Color.b
  local anchor, justify = Alignment()
  slot.active = true
  slot.isPet = isPet
  slot.petSourceGUID = animationEvent.PetSourceGUID
  slot.fallbackEvent = nil
  if record.petOwner then
    -- MSBT recycles the source event immediately after this callback. Retain
    -- our own shallow record only while the pet number is alive, for fallback.
    slot.fallbackEvent = {}
    for key,value in pairs(animationEvent) do slot.fallbackEvent[key]=value end
  end
  slot.pendingRender = true
  slot.text:Hide()
  slot.startTime = now
  slot.lastUpdate = now
  slot.position = 0
  slot.stackOffset, slot.displayPosition, slot.stackTarget = 0, 0, 0
  frame.spawnSequence = (frame.spawnSequence or 0) + 1
  slot.spawnSequence = frame.spawnSequence
  slot.fontSize = size
  slot.visualSize = size
  slot.native3D = nil
  slot.nativeTravel = nil
  slot.nativeBaseX, slot.nativeBaseY, slot.nativeBaseZ = nil, nil, nil
  slot.nativeCorrectionX, slot.nativeCorrectionY = nil, nil
  slot.nativeScreenDepth = nil
  slot.petOrbitRadius, slot.petPlacedTime = nil, nil
  slot.perspectiveWarp = 0
  SetTextPerspective(slot, 0)
  slot.appliedPerspective, slot.perspectiveAPI = nil, nil

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
  slot.renderReference, slot.renderAnchor = frame, anchor
  slot.text:SetJustifyH(justify)
  slot.appliedJustify = justify
  local fontSurfaceSize = slot.native3D
    and math.floor(size * NATIVE_MAX_SCALE + .5) or size - 1
  slot.text:SetFont(font, math.max(1, fontSurfaceSize), outline)
  slot.text:SetTextHeight(math.max(1, size))
  slot.appliedTextHeight = math.max(1, size)
  slot.text:SetTextColor(colorR, colorG, colorB)
  -- Full blocks and parries have no damage amount, so their result icon
  -- replaces the localized message. Partial blocks retain the damage number.
  local iconOnlyResult = (animationEvent.IsBlocked or animationEvent.IsParried)
    and (not animationEvent.Amount or tonumber(animationEvent.Amount) == 0)
  slot.text:SetText(iconOnlyResult and "" or animationEvent.Text)
  slot.collisionTextHeight = nil
  slot.collisionTextWidth = nil
  slot.text:SetAlpha(1)
  slot.appliedAlpha = 1
  ConfigureSourceIcon(slot)
  ConfigureResultIcon(slot)
  -- Wait for the next layout pass to reveal a new slot: a pet event must not
  -- flash in the main column for one rendered frame before its lane is known.
  SetSourceIconShown(slot, false)
  SetSourceIconShown(slot.result, false)
  frame:Show()
  animatingRecords[record] = true
end

local function RetireAnimationItem(item)
  item.active = nil
  item.pendingRender = nil
  item.fallbackEvent = nil
  item.stackOffset, item.displayPosition, item.stackTarget = nil, nil, nil
  item.native3D = nil
  item.visualSize = nil
  item.perspectiveWarp = nil
  SetTextPerspective(item, 0)
  item.text:Hide()
  SetSourceIconShown(item, false)
  SetSourceIconShown(item.result, false)
end

local function NativeAnimationPlacement(record, item, anchor, height, render)
  item.nativeScreenDepth = nil
  if not item.native3D or not UIParent or not UIParent.GetWidth
      or not UIParent.GetHeight then return end
  local progress = math.max(0, math.min(1, (item.displayPosition or item.position) / height))
  local worldOffset = progress * (item.nativeTravel or NATIVE_DEFAULT_TRAVEL)

  if render.api~=zAPI or render.ui~=UIParent or render.identity~=(record.guid or record.unit)
      or render.frozen~=record.frozen then
    render.baseReady,render.geometryReady=nil,nil
    render.api,render.ui,render.identity,render.frozen=zAPI,UIParent,record.guid or record.unit,record.frozen
  end
  if not render.baseReady then
    render.baseX,render.baseY,render.baseDepth,render.wx,render.wy,render.wz=nil,nil,nil,nil,nil,nil
    if not record.frozen then
      render.baseX,render.baseY,render.baseDepth,render.wx,render.wy,render.wz=NativeProject(record,0,render.now)
    end
    render.baseReady=true
  end
  local baseX, baseY, baseDepth, baseWorldX, baseWorldY, baseWorldZ=
    render.baseX,render.baseY,render.baseDepth,render.wx,render.wy,render.wz
  local pointX, pointY, pointDepth, pointWorldX, pointWorldY, pointWorldZ
  if baseX and baseWorldX and baseWorldY and baseWorldZ then
    pointWorldX, pointWorldY, pointWorldZ = baseWorldX, baseWorldY, baseWorldZ + worldOffset
    pointX, pointY, pointDepth = NativeWorldToScreen(pointWorldX, pointWorldY, pointWorldZ)
  elseif baseX then
    pointX, pointY, pointDepth, pointWorldX, pointWorldY, pointWorldZ = NativeProject(record, worldOffset, render.now)
  end

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

  if not render.geometryReady then
    render.width,render.height=UIParent:GetWidth(),UIParent:GetHeight()
    render.originX,render.originY=nil,nil
    if not record.frozen then render.originX,render.originY=FrameBottomAnchor(record.frame,anchor) end
    render.geometryReady=true
  end
  local uiWidth,uiHeight=render.width,render.height
  if not record.frozen then
    local originX, originY = render.originX,render.originY
    if originX and originY then
      item.nativeCorrectionX = originX - baseX * uiWidth
      item.nativeCorrectionY = originY - baseY * uiHeight
    end
  end
  if not item.nativeCorrectionX or not item.nativeCorrectionY then return end

  item.nativeScreenX, item.nativeScreenY, item.nativeScreenDepth = pointX, pointY, pointDepth
  item.nativeBaseScreenX, item.nativeBaseScreenY, item.nativeBaseScreenDepth = baseX, baseY, baseDepth

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

local function ResolveAnimationSpacing(frame, height, elapsed, zipper)
  local layout = frame.collisionLayout
  if not layout then
    layout = {}
    frame.collisionLayout = layout
  end
  local oldCount = frame.collisionLayoutCount or 0
  local count = 0
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item and item.active then
      count = count + 1
      layout[count] = item
    end
  end
  for i = count + 1, oldCount do layout[i] = nil end
  frame.collisionLayoutCount = count

  -- Avoid table.getn/table.insert/table.sort here. Vanilla-compatible clients
  -- can preserve a stale implicit array size on reused tables, producing nil
  -- holes. The small bounded pools are cheap and safe to sort explicitly.
  for i = 2, count do
    local item = layout[i]
    local index = i - 1
    while index >= 1 and (layout[index].position > item.position or
        (layout[index].position == item.position and
          (layout[index].spawnSequence or 0) < (item.spawnSequence or 0))) do
      layout[index + 1] = layout[index]
      index = index - 1
    end
    layout[index + 1] = item
  end

  if zipper then
    -- Front/back streams share a column. Weave their individual slots instead
    -- of reserving the entire main stack as one solid obstacle. Keep the order
    -- within each source; unequal bursts use the remaining slots normally.
    local main = frame.zipperMain or {}
    local pet = frame.zipperPet or {}
    frame.zipperMain, frame.zipperPet = main, pet
    local mainCount, petCount = 0, 0
    for i = 1, count do
      local item = layout[i]
      if item.isPet then petCount = petCount + 1; pet[petCount] = item
      else mainCount = mainCount + 1; main[mainCount] = item end
    end
    for i = mainCount + 1, frame.zipperMainCount or 0 do main[i] = nil end
    for i = petCount + 1, frame.zipperPetCount or 0 do pet[i] = nil end
    frame.zipperMainCount, frame.zipperPetCount = mainCount, petCount
    local nextPet = count > 0 and layout[1].isPet
    local mainIndex, petIndex = 1, 1
    for i = 1, count do
      if petIndex <= petCount and (nextPet or mainIndex > mainCount) then
        layout[i] = pet[petIndex]; petIndex = petIndex + 1; nextPet = false
      else
        layout[i] = main[mainIndex]; mainIndex = mainIndex + 1; nextPet = true
      end
    end
  end

  local previousMain, previousPet
  local split = Z.config.split_pet == "1"
  -- Natural travel stays untouched. Ease only the extra collision displacement
  -- so a newly arriving event never teleports every existing number upward.
  local blend = 1 - math.exp(-math.max(0, math.min(.1, elapsed or 1/60)) / .075)
  for i = 1, count do
    local item = layout[i]
    local petStream = split and item.isPet and not zipper
    local previous = previousMain
    if petStream then previous = previousPet end
    local target = item.position
    if previous then
      -- Bottom-anchored text needs the lower entry's actual height, not an
      -- average of both font sizes or the old extra eight-pixel spawn shove.
      local textHeight = previous.collisionTextHeight
      if (textHeight == nil or not previous.appliedTextHeight) and previous.text.GetStringHeight then
        textHeight = previous.text:GetStringHeight()
        if previous.appliedTextHeight then previous.collisionTextHeight = textHeight end
      end
      local footprint = math.max(1, textHeight or previous.fontSize or 12)
      if previous.icon and (previous.icon:IsShown() or
          previous.pendingRender and previous.iconTexture and Z.config.icons == "1") then
        footprint = math.max(footprint, previous.configuredIconSize or previous.icon:GetHeight())
      end
      if previous.result and (previous.result.icon:IsShown() or
          previous.pendingRender and previous.result.iconTexture) then
        footprint = math.max(footprint, previous.result.configuredIconSize or previous.result.icon:GetHeight())
      end
      -- Shared rows need outline clearance and the small pet-facing offset;
      -- otherwise even a two-pixel orbit can skip past the next main row.
      local minimumGap = footprint + (zipper and 6 or 2)
      target = math.max(target, previous.stackTarget + minimumGap)
    end
    item.stackTarget = target
    local offset = item.stackOffset or 0
    offset = offset + (math.max(0, target - item.position) - offset) * blend
    -- A released gap settles gently too, without reversing the number's motion.
    if item.displayPosition then offset = math.max(offset, item.displayPosition - item.position) end
    item.stackOffset = offset
    item.displayPosition = item.position + offset
    if item.displayPosition >= height then
      -- A crowded area cannot display unlimited events without overlap. End
      -- the oldest/topmost entries early instead of drawing them together.
      RetireAnimationItem(item)
    else
      if petStream then previousPet = item else previousMain = item end
    end
  end
end

local function AnimationBounds(item, anchor, x, y, scale)
  local width = item.collisionTextWidth
  if width == nil then
    width = item.text.GetStringWidth and item.text:GetStringWidth() or item.fontSize or 12
    item.collisionTextWidth = width
  end
  width = math.max(0, width) * scale
  -- Include the exaggerated glyph trapezoid, outline, and both icon gutters.
  local warpPadding = width * math.max(0, item.perspectiveWarp or 0) * .5
  local left = anchor == "BOTTOMLEFT" and x or anchor == "BOTTOMRIGHT" and x - width or x - width * .5
  local right = left + width
  local height = item.collisionTextHeight
  if height == nil then
    height = item.text.GetStringHeight and item.text:GetStringHeight() or item.fontSize or 12
    item.collisionTextHeight = height
  end
  height = math.max(0, height) * scale
  local bottom, top = y, y + height
  local iconHeight = 0
  if item.icon:IsShown() then left = left - ((item.configuredIconSize or item.icon:GetWidth()) + ICON_TEXT_GAP) * scale end
  if item.result.icon:IsShown() then right = right + ((item.result.configuredIconSize or item.result.icon:GetWidth()) + ICON_TEXT_GAP) * scale end
  if item.icon:IsShown() then iconHeight = item.configuredIconSize or item.icon:GetHeight() end
  if item.result.icon:IsShown() then iconHeight = math.max(iconHeight, item.result.configuredIconSize or item.result.icon:GetHeight()) end
  iconHeight = iconHeight * scale
  bottom, top = math.min(bottom, y + (height - iconHeight) * .5), math.max(top, y + (height + iconHeight) * .5)
  return left - warpPadding - scale, right + warpPadding + scale, bottom - scale, top + scale
end

local function NativePetOrbit(record, frame, now, elapsed, sourceGUID)
  local reference
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item and item.active and item.isPet and item.petSourceGUID==sourceGUID then
      if not item.native3D
          or not item.nativeBaseX or not item.nativeBaseY or not item.nativeBaseZ then return end
      reference = reference or item
    end
  end
  if not reference then return end
  local baseX, baseY, baseDepth, worldX, worldY, worldZ
  if record.frozen then
    worldX, worldY, worldZ = reference.nativeBaseX, reference.nativeBaseY, reference.nativeBaseZ
    baseX, baseY, baseDepth = NativeWorldToScreen(worldX, worldY, worldZ)
  else
    baseX, baseY, baseDepth, worldX, worldY, worldZ = NativeProject(record, 0, now)
  end
  if not baseX or not worldX or not worldY or not worldZ then return end
  local yaw = frame.petStreamYaw
  local petX, petY
  if not record.frozen then
    if sourceGUID and type(zAPI)=="function" then
      local ok,x,y=pcall(zAPI,"unitPosition",sourceGUID)
      if ok and type(x)=="number" and type(y)=="number" then petX,petY=x,y end
    elseif not sourceGUID then petX, petY = PetWorldPosition(now) end
  end
  if petX and petY then
    local dx, dy = petX - worldX, petY - worldY
    if dx * dx + dy * dy > .1 * .1 then
      local desired = math.atan2(dy, dx)
      if yaw then
        local difference = desired - yaw
        if difference > math.pi then difference = difference - 2 * math.pi end
        if difference < -math.pi then difference = difference + 2 * math.pi end
        yaw = yaw + difference * (1 - math.exp(-math.max(0, math.min(.1, elapsed)) / .10))
      else yaw = desired end
    end
  end
  if not yaw then return end
  if yaw > math.pi then yaw = yaw - 2 * math.pi end
  if yaw < -math.pi then yaw = yaw + 2 * math.pi end
  frame.petStreamYaw = yaw
  local dx, dy = math.cos(yaw), math.sin(yaw)
  -- The ring starts at the SAME world Z as regular numbers, even on slopes.
  local probeX, probeY, probeDepth = NativeWorldToScreen(worldX + dx, worldY + dy, worldZ)
  if not probeX then return end
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  local rayX, rayY = (probeX - baseX) * width, (probeY - baseY) * height
  local rayLength = math.sqrt(rayX * rayX + rayY * rayY)
  if rayLength < .01 then return end
  frame.petStreamAngle = math.atan2(rayY, rayX)
  -- Hysteresis avoids changing slot order for tiny camera/pet movements.
  local verticality = math.abs(rayY) / rayLength
  if verticality >= .80 then frame.petZipper = true
  elseif verticality < .65 then frame.petZipper = nil end
  local orbit = frame.petOrbit or {}
  frame.petOrbit = orbit
  -- One probe still supplies exact perspective for every individual number.
  orbit.native, orbit.depthDelta, orbit.baseDepth = true, probeDepth - baseDepth, baseDepth
  orbit.numeratorX, orbit.numeratorY = probeX * probeDepth - baseX * baseDepth,
    probeY * probeDepth - baseY * baseDepth
  orbit.pixelX, orbit.pixelY, orbit.minimum = rayX / rayLength, rayY / rayLength, PET_STREAM_GAP / rayLength
  orbit.worldX, orbit.worldY, orbit.worldZ, orbit.dx, orbit.dy = worldX, worldY, worldZ, dx, dy
  return orbit
end

local function PetStreamPlacement(frame, now, frozen, originX, sourceGUID)
  -- A screen-only fallback cannot recover world yaw. Keep its baseline level
  -- and use left/right instead of mistaking pet elevation for an orbit angle.
  local direction = math.cos(frame.petStreamAngle or 0) < 0 and -1 or 1
  local petX
  if not frozen then
    if sourceGUID and type(zAPI)=="function" then
      local ok,x,y,depth=pcall(zAPI,"projectUnit",sourceGUID,0)
      if ok and type(x)=="number" and type(depth)=="number" and depth>0 and x>=0 and x<=1 then petX=x*UIParent:GetWidth() end
    elseif not sourceGUID then petX=PetScreenPosition(now) end
  end
  local dx = petX and petX - originX
  if dx and math.abs(dx) > 16 then direction = dx < 0 and -1 or 1 end
  frame.petStreamAngle = direction < 0 and math.pi or 0
  frame.petZipper = nil
  local orbit = frame.petFallbackOrbit or {}
  frame.petFallbackOrbit = orbit
  orbit.native, orbit.pixelX, orbit.pixelY, orbit.minimum = false, direction, 0, PET_STREAM_GAP
  return orbit
end

local function AxisOverlapInterval(minimum, maximum, movement, depth, depthDelta, limit)
  -- Solve overlap before perspective division: each axis contributes one
  -- forbidden radius interval. A pair of text/icon boxes is not a whole stack.
  local low, high = 0, limit
  local coefficient, bound = movement - minimum * depthDelta, minimum * depth
  if coefficient > .0000001 then low = math.max(low, bound / coefficient)
  elseif coefficient < -.0000001 then high = math.min(high, bound / coefficient)
  elseif bound > 0 then return end
  coefficient, bound = movement - maximum * depthDelta, maximum * depth
  if coefficient > .0000001 then high = math.min(high, bound / coefficient)
  elseif coefficient < -.0000001 then low = math.max(low, bound / coefficient)
  elseif bound < 0 then return end
  if low < high then return low, high end
end

local function PetNumberRadius(frame, item, movementX, movementY, depth, depthDelta,
    limit, minimum, native, now, elapsed, hasMain, originX, originY, scale)
  local lows, highs = frame.petIntervalLow or {}, frame.petIntervalHigh or {}
  frame.petIntervalLow, frame.petIntervalHigh = lows, highs
  local count = 0
  for i = 0, TEXT_SLOTS do
    local obstacle = frame.items[i]
    local left, right, bottom, top
    if i == 0 and not hasMain then
      left, right, bottom, top = originX - 6 * scale, originX + 6 * scale, originY, originY + 12 * scale
    elseif obstacle and obstacle ~= item and obstacle.active then
      if not obstacle.isPet then
        left, right, bottom, top = obstacle.layoutLeft, obstacle.layoutRight, obstacle.layoutBottom, obstacle.layoutTop
      elseif obstacle.petPlacedTime == now then
        left, right, bottom, top = obstacle.petLeft, obstacle.petRight, obstacle.petBottom, obstacle.petTop
      end
    end
    if left then
      local lowX, highX = AxisOverlapInterval(left - PET_STREAM_GAP - item.layoutRight,
        right + PET_STREAM_GAP - item.layoutLeft, movementX, depth, depthDelta, limit)
      if lowX then
        local lowY, highY = AxisOverlapInterval(bottom - PET_STREAM_GAP - item.layoutTop,
          top + PET_STREAM_GAP - item.layoutBottom, movementY, depth, depthDelta, limit)
        if lowY then
          local low, high = math.max(lowX, lowY), math.min(highX, highY)
          if low < high then
            count = count + 1
            local index = count
            while index > 1 and lows[index - 1] > low do
              lows[index], highs[index] = lows[index - 1], highs[index - 1]; index = index - 1
            end
            lows[index], highs[index] = low, high
          end
        end
      end
    end
  end
  -- Pick the first free gap along this number's pet-facing ray. No repeated
  -- native projections or scene scans; the bounded interval arrays are reused.
  local radius = minimum
  for i = 1, count do
    if radius < lows[i] then break end
    if radius <= highs[i] then radius = highs[i] + .000001 end
  end
  if radius >= limit or radius == math.huge or radius ~= radius then return end
  if item.petOrbitRadius and item.petOrbitNative == native then
    local blend = 1 - math.exp(-math.max(0, math.min(.1, elapsed)) / .10)
    local eased = math.max(radius, item.petOrbitRadius + (radius - item.petOrbitRadius) * blend)
    local safe = eased < limit
    for i = 1, count do
      if eased >= lows[i] and eased <= highs[i] then safe = false; break end
    end
    if safe then radius = eased end
  end
  return radius
end

local function PlacePetNumber(frame, item, orbit, now, elapsed, hasMain, originX, originY, scale)
  local native = orbit.native and item.nativeScreenDepth ~= nil
  local depth, delta = 1, 0
  local movementX, movementY, limit = orbit.pixelX, orbit.pixelY, math.huge
  local minimum = PET_STREAM_GAP
  if native then
    depth, delta = item.nativeScreenDepth, orbit.depthDelta
    movementX = (orbit.numeratorX - item.nativeScreenX * delta) * UIParent:GetWidth()
    movementY = (orbit.numeratorY - item.nativeScreenY * delta) * UIParent:GetHeight()
    if delta < 0 then limit = (math.min(depth, orbit.baseDepth) - .1) / -delta end
    minimum = orbit.minimum
  end
  local radius = PetNumberRadius(frame, item, movementX, movementY, depth, delta,
    limit, minimum, native, now, elapsed, hasMain, originX, originY, scale)
  if not radius then
    -- A near-plane/degenerate point still gets readable individual placement.
    native, depth, delta = false, 1, 0
    movementX, movementY = orbit.pixelX, orbit.pixelY
    radius = PetNumberRadius(frame, item, movementX, movementY, depth, delta,
      math.huge, PET_STREAM_GAP, native, now, elapsed, hasMain, originX, originY, scale) or 0
  end
  item.petOrbitRadius, item.petOrbitNative = radius, native
  item.petOffsetX, item.petOffsetY = radius * movementX / (depth + radius * delta),
    radius * movementY / (depth + radius * delta)
  item.petLeft, item.petRight = item.layoutLeft + item.petOffsetX, item.layoutRight + item.petOffsetX
  item.petBottom, item.petTop = item.layoutBottom + item.petOffsetY, item.layoutTop + item.petOffsetY
  item.petPlacedTime = now
  item.petOrbitWorldX, item.petOrbitWorldY, item.petOrbitWorldZ = nil, nil, nil
  if native then
    item.petOrbitWorldX, item.petOrbitWorldY, item.petOrbitWorldZ =
      orbit.worldX + radius * orbit.dx, orbit.worldY + radius * orbit.dy, orbit.worldZ
  end
end

local function PetAnchorVisible(record, now)
  local unit=record.pairedOwner and record.sourceGUID or "pet"
  if record.pairedOwner then
    local ok,current=pcall(Z.pairedDamageSource or function() end,unit)
    if not ok or current~=unit then return end
  end
  if not UnitExists then return end
  local exists,loaded=pcall(UnitExists,unit)
  if not exists or not loaded then return end
  local guid=record.pairedOwner and unit or (UnitGUID and UnitGUID("pet"))
  if record.guid and guid and record.guid~=guid then return end
  record.unit,record.guid=unit,guid
  local x,y,depth=NativeProject(record,0,now)
  if not x or x<0 or x>1 or y<0 or y>1 or depth<=0 then return end
  record.frame:SetPoint("BOTTOM",UIParent,"BOTTOMLEFT",
    x*UIParent:GetWidth()+(tonumber(Z.config.x) or 0),
    y*UIParent:GetHeight()+(tonumber(Z.config.y) or 8))
  return true
end

local function FallBackPetAnimations(record)
  for i=1,TEXT_SLOTS do
    local item=record.frame.items[i]
    if item and item.active and item.fallbackEvent and MikSBT.AddAnimation then
      local saved=item.fallbackEvent; item.fallbackEvent=nil
      MikSBT.AddAnimation(saved)
    end
  end
  ClearAnimations(record)
end

local function UpdateAnimations(record, now)
  local frame = record and record.frame
  if not frame or not frame:IsShown() then return end
  if not Enabled() then
    if record.frozen then ReleaseFadingRecord(record) else ClearAnimations(record) end
    return
  end
  if record.petOwner then
    if Z.config.split_pet~="1" or Z.config.pet_anchor=="TARGET" then ClearAnimations(record); return end
    if not PetAnchorVisible(record,now) then FallBackPetAnimations(record); return end
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
  local hasPet
  local pairedSources=frame.pairedSources or {};frame.pairedSources=pairedSources
  for source in pairs(pairedSources) do pairedSources[source]=nil end
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item and item.active then
      item.position = item.position + speed * (now - item.lastUpdate)
      item.lastUpdate = now
      if item.position >= height then
        RetireAnimationItem(item)
      end
      if item.active and item.isPet then
        if item.petSourceGUID then pairedSources[item.petSourceGUID]=true else hasPet=true end
      end
    end
  end

  local spacingElapsed = now - (frame.spacingLastTime or now - 1/60)
  frame.spacingLastTime = now
  local split = Z.config.split_pet == "1" and not record.petOwner
  local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  local scale = frameScale / math.max(.001, uiScale)
  local originX, originY
  if split then originX, originY = FrameBottomAnchor(frame, anchor) end
  originX, originY = (originX or 0) * scale, (originY or 0) * scale
  local petOrbit
  if split and hasPet then
    petOrbit = NativePetOrbit(record, frame, now, spacingElapsed)
      or PetStreamPlacement(frame, now, record.frozen, originX)
  else frame.petZipper = nil end
  local pairedOrbit
  frame.pairedPetGeometries=frame.pairedPetGeometries or {}
  frame.pairedPetOrbits=frame.pairedPetOrbits or {}
  for source in pairs(frame.pairedPetOrbits) do frame.pairedPetOrbits[source]=nil end
  if split then for source in pairs(pairedSources) do
    local geometry=frame.pairedPetGeometries[source]
    if not geometry then geometry={sourceGUID=source};frame.pairedPetGeometries[source]=geometry end
    frame.pairedPetGeometry=geometry -- compatibility for single-source integrations
    geometry.items=frame.items
    local orbit=NativePetOrbit(record,geometry,now,spacingElapsed,source) or
      PetStreamPlacement(geometry,now,record.frozen,originX,source)
    frame.pairedPetOrbits[source]=orbit
    pairedOrbit=pairedOrbit or orbit
    if not hasPet then frame.petZipper=geometry.petZipper end
  end end
  ResolveAnimationSpacing(frame, height, spacingElapsed, frame.petZipper)

  local render=record.animationRender
  if not render then render={}; record.animationRender=render end
  render.now,render.baseReady,render.geometryReady=now,nil,nil
  local anyActive, hasMain
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item and item.active then
      anyActive = true
      local elapsed = now - item.startTime
      local alpha = 1
      if elapsed > fadeDelay and fadeTime > 0 then
        alpha = 1 - ((elapsed - fadeDelay) / fadeTime)
        if alpha < 0 then alpha = 0 end
      end
      -- Restore the unwarped glyph vertices before a possible text-height
      -- rebuild, then apply the current frame's perspective after layout.
      local nativeX, nativeY = NativeAnimationPlacement(record, item, anchor, height, render)
      local textHeight = math.max(1, nativeX and (item.visualSize or item.fontSize or 12) or (item.fontSize or 12))
      if not item.appliedTextHeight or math.abs(textHeight-item.appliedTextHeight) > .001 then
        SetTextPerspective(item, 0)
        item.text:SetTextHeight(textHeight)
        item.appliedTextHeight = textHeight
        item.collisionTextHeight = nil
        item.collisionTextWidth = nil
        item.appliedPerspective = nil
      end
      if not nativeX or not nativeY then
        item.visualSize = item.fontSize
        item.perspectiveWarp = 0
      end
      if item.appliedJustify ~= justify then item.text:SetJustifyH(justify); item.appliedJustify = justify end
      if item.appliedAlpha ~= alpha then item.text:SetAlpha(alpha); item.appliedAlpha = alpha end
      if item.native3D or item.pendingRender then
        ConfigureSourceIcon(item)
        ConfigureResultIcon(item)
      end
      if item.icon:IsShown() then SetSourceIconAlpha(item, alpha * iconAlpha) end
      if item.result.icon:IsShown() then SetSourceIconAlpha(item.result, alpha) end
      item.layoutX, item.layoutY = nativeX, nativeY
      if split then
        local left, right, bottom, top = AnimationBounds(item, anchor, nativeX or originX,
          nativeY or originY + (item.displayPosition or item.position) * scale, scale)
        item.layoutLeft, item.layoutRight, item.layoutBottom, item.layoutTop = left, right, bottom, top
        if not item.isPet then hasMain = true end
      end
    end
  end
  frame.petStreamOffset, frame.petStreamOffsetY, frame.petStreamRadius = nil, nil, nil
  frame.petStreamWorldX, frame.petStreamWorldY, frame.petStreamWorldZ = nil, nil, nil
  if petOrbit or pairedOrbit then
    for i = 1, frame.collisionLayoutCount or 0 do
      local item = frame.collisionLayout[i]
      if item.active and item.isPet then
        PlacePetNumber(frame, item, item.petSourceGUID and frame.pairedPetOrbits[item.petSourceGUID] or petOrbit, now, spacingElapsed, hasMain, originX, originY, scale)
        if not frame.petStreamOffset then
          frame.petStreamOffset, frame.petStreamOffsetY, frame.petStreamRadius =
            item.petOffsetX, item.petOffsetY, item.petOrbitRadius
          frame.petStreamWorldX, frame.petStreamWorldY, frame.petStreamWorldZ =
            item.petOrbitWorldX, item.petOrbitWorldY, item.petOrbitWorldZ
        end
      end
    end
  end
  for i = 1, TEXT_SLOTS do
    local item = frame.items[i]
    if item and item.active then
      local offset = split and item.isPet and item.petOffsetX or 0
      local offsetY = split and item.isPet and item.petOffsetY or 0
      local reference = item.layoutX and UIParent or frame
      if item.renderReference ~= reference or item.renderAnchor ~= anchor then item.text:ClearAllPoints() end
      if item.layoutX then
        local x, y = item.layoutX + offset, item.layoutY + offsetY
        item.text:SetPoint(anchor, UIParent, "BOTTOMLEFT", x, y)
      else
        item.text:SetPoint(anchor, frame, anchor, offset / scale, (item.displayPosition or item.position) + offsetY / scale)
      end
      item.renderReference, item.renderAnchor = reference, anchor
      SetTextPerspective(item, item.perspectiveWarp or 0)
      if item.pendingRender then item.text:Show(); item.pendingRender = nil end
    end
  end
  if not anyActive then
    animatingRecords[record] = nil
    frame:Hide()
    if record.frozen then ReleaseFadingRecord(record) end
  end
end

local function HandleOutgoing(animationEvent)
  local targetGuid = animationEvent.TargetGUID or ConsumeGuidHint(animationEvent)
  if IsPetAnimation(animationEvent) and Z.config.split_pet=="1" and Z.config.pet_anchor~="TARGET" then
    local source=animationEvent.PetSourceGUID
    Z.pairedPetRecords=Z.pairedPetRecords or {}
    local record
    if source then record=Z.pairedPetRecords[source] else record=Z.petRecord end
    if not record then
      local frame=CreateFrame("Frame",nil,UIParent)
      frame:SetFrameStrata("TOOLTIP"); frame:SetFrameLevel(100); frame.items={}; frame:Hide()
      record={petOwner=true,pairedOwner=source~=nil,sourceGUID=source,frame=frame}
      if source then Z.pairedPetRecords[source]=record;Z.pairedPetRecord=record else Z.petRecord=record end
    end
    if record.guid and record.guid~=(source or (UnitGUID and UnitGUID("pet"))) then
      FallBackPetAnimations(record); record.guid=nil; record.nativeProjectionSample=nil
    end
    record.sourceGUID=source
    ConfigureRecord(record)
    if not PetAnchorVisible(record,GetTime()) then return false end
    if MikSBT.PrepareExternalAnimationEvent(animationEvent) then AddAnimation(record,animationEvent) end
    return true
  end
  if not MikSBT.PrepareExternalAnimationEvent(animationEvent) then return end
  local record = FindRecord(animationEvent.Name, targetGuid)
  if not record then
    local now = GetTime()
    -- AoE merge batches share one recovery scan instead of walking the entire
    -- scene once for each unmatched hit. Legacy plates still recover promptly.
    if lastOutgoingPlateScan ~= now then
      lastOutgoingPlateScan = now; nextPlateScan = now + .25; ScanVisibleNameplates(true)
    end
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

-- Public preview hook used by zNameplates' optional dummy cluster. It feeds
-- directly through the normal renderer so MSBT fonts, colours, crit sizing,
-- icons, spacing, speed, and fade settings are all exercised by the test.
local dummyPulse = 0
function Z.PulseDummyDamage(bases)
  if not Enabled() then return nil, "Enable nameplate damage in zDNumbers first." end
  if type(bases) ~= "table" or table.getn(bases) == 0 then
    return nil, "No dummy nameplates are available."
  end

  local profile = MikSBT.CurrentProfile
  local display = profile.DisplaySettings and profile.DisplaySettings.Outgoing
  local settings = profile.EventSettings and profile.EventSettings.MSBT_EVENTTYPE_OUTGOING_DAMAGE
  if not display or not settings then return nil, "The active MSBT profile is not ready." end

  dummyPulse = dummyPulse + 1
  local textures = {
    "Interface\\Icons\\Ability_MeleeDamage",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Ability_BackStab",
    "Interface\\Icons\\Ability_Hunter_CriticalShot",
    "Interface\\Icons\\Spell_Shadow_ShadowBolt",
  }
  local scrollArea = { DisplaySettings = display }
  for i = 1, table.getn(bases) do
    local base = bases[i]
    local record = base and AttachNameplate(base)
    if record then
      local amount = tostring(120 + i * 137 + math.mod(dummyPulse * 43, 211))
      local animationEvent = {
        ScrollArea = scrollArea,
        EventType = "MSBT_EVENTTYPE_OUTGOING_DAMAGE",
        EventSettings = settings,
        UnformattedText = settings.Message,
        Amount = amount,
        Name = record.name or "Dummy",
        IsCrit = i == 1,
        Texture = textures[i] or textures[1],
      }
      if i == 3 then animationEvent.IsGlancing = true
      elseif i == 4 then animationEvent.IsBlocked = true
      elseif i == 5 then animationEvent.IsParried = true end
      if MikSBT.PrepareExternalAnimationEvent(animationEvent) then
        AddAnimation(record, animationEvent)
      end
      if Z.config.split_pet == "1" then
        local petSettings = profile.EventSettings.MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE or settings
        local petEvent = {
          ScrollArea = { DisplaySettings = profile.DisplaySettings.PetOutgoing or display },
          EventType = "MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE",
          EventSettings = petSettings,
          UnformattedText = petSettings.Message,
          Amount = tostring(40 + i * 17 + math.mod(dummyPulse * 11, 51)),
          Name = record.name or "Dummy",
          Texture = "Interface\\Icons\\Ability_Druid_FerociousBite",
        }
        if MikSBT.PrepareExternalAnimationEvent(petEvent) then AddAnimation(record, petEvent) end
      end
    end
  end
  return true
end

function Z.HideDummyDamage(bases)
  if type(bases) ~= "table" then return end
  for i = 1, table.getn(bases) do
    local record = recordsByPlate[bases[i]]
    if record and visibleRecords[record] then
      ClearAnimations(record)
      DetachNameplate(record)
    end
  end
end

function Z.Refresh()
  if Z.petRecord then
    Z.petRecord.nativeProjectionSample=nil
    ConfigureRecord(Z.petRecord)
    if not Enabled() or Z.config.split_pet~="1" or Z.config.pet_anchor=="TARGET" then ClearAnimations(Z.petRecord) end
  end
  for _,record in pairs(Z.pairedPetRecords or {}) do
    record.nativeProjectionSample=nil
    ConfigureRecord(record)
    if not Enabled() or Z.config.split_pet~="1" or Z.config.pet_anchor=="TARGET" then ClearAnimations(record) end
  end
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
    if Z.petRecord then ClearAnimations(Z.petRecord); Z.petRecord.guid=nil; Z.petRecord.nativeProjectionSample=nil end
    for _,record in pairs(Z.pairedPetRecords or {}) do ClearAnimations(record);record.guid=nil;record.nativeProjectionSample=nil end
    Z.EnsureEmbeddedMSBT()
    RegisterMSBTIntegration()
    cachedWorldChildCount = -1
    nextLegacyPlateScan = 0
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
    petScreenSample.time = nil
    sourceSpellIcons = {}
    sourceSpellbookScanned = nil
    return
  elseif event == "AUTO_ATTACK_SELF" then
    QueueGuidHint(arg2, arg3 and arg3 > 0 and arg3 or nil, nil)
  elseif event == "AUTO_ATTACK_OTHER" then
    if arg1 == UnitGUID("pet") then QueueGuidHint(arg2, arg3 and arg3 > 0 and arg3 or nil, nil, true) end
  elseif event == "SPELL_DAMAGE_EVENT_SELF" then
    QueueGuidHint(arg1, arg4, arg3)
  elseif event == "SPELL_DAMAGE_EVENT_OTHER" then
    if arg2 == UnitGUID("pet") then QueueGuidHint(arg1, arg4, arg3, true) end
  elseif event == "SPELL_MISS_SELF" then
    QueueGuidHint(arg2, nil, arg3)
  elseif event == "SPELL_MISS_OTHER" then
    if arg1 == UnitGUID("pet") then QueueGuidHint(arg2, nil, arg3, true) end
  end
end)

eventFrame:SetScript("OnUpdate", function()
  if not Z.config then return end
  local now = GetTime()
  if now >= nextPlateScan then
    nextPlateScan = now + .25
    ScanVisibleNameplates()
  end
  for record in pairs(animatingRecords) do
    if not record.frozen then RememberRecordPosition(record) end
    UpdateAnimations(record, now)
  end
end)
