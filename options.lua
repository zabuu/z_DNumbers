local Z = zDNumbers

local frame = CreateFrame("Frame", "zDNumbersOptions", UIParent)
frame:SetWidth(500)
frame:SetHeight(550)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
frame:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=32, edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
frame:SetBackdropColor(.03, .03, .03, .94)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", frame, "TOP", 0, -20)
title:SetText("zDNumbers")
local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
subtitle:SetText("MSBT damage attached to visible nameplates")

local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

local controls = {}
local function Label(text, y)
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, y)
  label:SetWidth(270)
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function SetValue(key, value)
  if not Z.config then return end
  Z.config[key] = tostring(value)
  Z.Refresh()
end

local enabled = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
enabled:SetPoint("TOPLEFT", frame, "TOPLEFT", 35, -82)
enabled:SetWidth(24); enabled:SetHeight(24)
Label("Attach outgoing MSBT damage to nameplates", -82)
enabled:SetScript("OnClick", function() SetValue("enabled", this:GetChecked() and "1" or "0") end)
controls.enabled = enabled

local icons = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
icons:SetPoint("TOPLEFT", frame, "TOPLEFT", 35, -112)
icons:SetWidth(24); icons:SetHeight(24)
Label("Show subtle spell and attack source icons", -112)
icons:SetScript("OnClick", function() SetValue("icons", this:GetChecked() and "1" or "0") end)
controls.icons = icons

local opacityLabel = Label("Icon opacity: 30%", -152)
local opacity = CreateFrame("Slider", "zDNumbersIconOpacitySlider", frame, "OptionsSliderTemplate")
opacity:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -147)
opacity:SetWidth(160)
opacity:SetHeight(16)
opacity:SetMinMaxValues(0, 100)
opacity:SetValueStep(1)
if getglobal then
  local low = getglobal("zDNumbersIconOpacitySliderLow")
  local high = getglobal("zDNumbersIconOpacitySliderHigh")
  local text = getglobal("zDNumbersIconOpacitySliderText")
  if low then low:SetText("0%") end
  if high then high:SetText("100%") end
  if text then text:SetText("") end
end
opacity:SetScript("OnValueChanged", function()
  local value = math.floor((tonumber(arg1) or this:GetValue() or 30) + .5)
  opacityLabel:SetText("Icon opacity: " .. value .. "%")
  if not this.zDNumbersUpdating then SetValue("icon_opacity", value) end
end)
controls.iconOpacity = opacity
controls.iconOpacityLabel = opacityLabel

local tiltLabel = Label("Perspective depth: 12%", -190)
local tilt = CreateFrame("Slider", "zDNumbersPerspectiveTiltSlider", frame, "OptionsSliderTemplate")
tilt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -185)
tilt:SetWidth(160)
tilt:SetHeight(16)
tilt:SetMinMaxValues(0, 100)
tilt:SetValueStep(1)
if getglobal then
  local low = getglobal("zDNumbersPerspectiveTiltSliderLow")
  local high = getglobal("zDNumbersPerspectiveTiltSliderHigh")
  local text = getglobal("zDNumbersPerspectiveTiltSliderText")
  if low then low:SetText("Off") end
  if high then high:SetText("Extreme") end
  if text then text:SetText("") end
end
tilt:SetScript("OnValueChanged", function()
  local value = math.floor((tonumber(arg1) or this:GetValue() or 12) + .5)
  tiltLabel:SetText(value == 0 and "Perspective depth: Off"
    or value >= 75 and "Perspective depth: EXTREME (" .. value .. "%)"
    or "Perspective depth: " .. value .. "%")
  if not this.zDNumbersUpdating then SetValue("perspective_tilt", value) end
end)
controls.perspectiveTilt = tilt
controls.perspectiveTiltLabel = tiltLabel

local fields = {
  { "Horizontal offset", "x" },
  { "Vertical offset above health bar", "y" },
  { "Scroll-area width", "width" },
  { "Scroll height / travel distance", "height" },
  { "Seconds before text begins fading", "fade" },
}
for i = 1, table.getn(fields) do
  local y = -228 - (i - 1) * 36
  Label(fields[i][1], y)
  local key = fields[i][2]
  local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  edit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, y + 5)
  edit:SetWidth(105); edit:SetHeight(24)
  edit:SetAutoFocus(false)
  edit:SetTextColor(1, 1, 1, 1)
  edit:SetScript("OnEditFocusGained", function() this.zDNumbersEditing = true end)
  edit:SetScript("OnEnterPressed", function() SetValue(key, this:GetText()); this:ClearFocus() end)
  edit:SetScript("OnEscapePressed", function() this:SetText(Z.config[key] or ""); this:ClearFocus() end)
  edit:SetScript("OnEditFocusLost", function()
    this.zDNumbersEditing = nil
    SetValue(key, this:GetText())
  end)
  controls[key] = edit
end

Label("Text alignment", -410)
local align = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
align:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -407)
align:SetWidth(105); align:SetHeight(23)
align:SetScript("OnClick", function()
  local current = Z.config.align or "CENTER"
  local nextValue = current == "LEFT" and "CENTER" or current == "CENTER" and "RIGHT" or "LEFT"
  SetValue("align", nextValue)
end)
controls.align = align

local status = Label("", -447)
status:SetWidth(420)
controls.status = status

local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
reset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 28, 24)
reset:SetWidth(110); reset:SetHeight(25); reset:SetText("Reset defaults")
reset:SetScript("OnClick", function() Z.Reset() end)

local msbt = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
msbt:SetPoint("LEFT", reset, "RIGHT", 8, 0)
msbt:SetWidth(110); msbt:SetHeight(25); msbt:SetText("MSBT options")
msbt:SetScript("OnClick", function()
  Z.EnsureEmbeddedMSBT()
  if MikSBT and MikSBT.CommandHandler then MikSBT.CommandHandler("") end
end)

local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 24)
close:SetWidth(110); close:SetHeight(25); close:SetText("Close")
close:SetScript("OnClick", function() frame:Hide() end)

function frame:Refresh()
  if not Z.config then return end
  controls.enabled:SetChecked(Z.config.enabled == "1")
  controls.icons:SetChecked(Z.config.icons == "1")
  local opacity = math.max(0, math.min(100, tonumber(Z.config.icon_opacity) or 30))
  controls.iconOpacity.zDNumbersUpdating = true
  controls.iconOpacity:SetValue(opacity)
  controls.iconOpacity.zDNumbersUpdating = nil
  controls.iconOpacityLabel:SetText("Icon opacity: " .. math.floor(opacity + .5) .. "%")
  local tilt = math.max(0, math.min(100, tonumber(Z.config.perspective_tilt) or 12))
  controls.perspectiveTilt.zDNumbersUpdating = true
  controls.perspectiveTilt:SetValue(tilt)
  controls.perspectiveTilt.zDNumbersUpdating = nil
  controls.perspectiveTiltLabel:SetText(tilt == 0 and "Perspective depth: Off"
    or tilt >= 75 and "Perspective depth: EXTREME ("
      .. math.floor(tilt + .5) .. "%)"
    or "Perspective depth: " .. math.floor(tilt + .5) .. "%")
  for _, key in pairs({ "x", "y", "width", "height", "fade" }) do
    if not controls[key].zDNumbersEditing then controls[key]:SetText(Z.config[key] or "") end
  end
  controls.align:SetText(Z.config.align or "CENTER")
  local runtime = MikSBT and MikSBT.CurrentProfile and "|cff55ff55MSBT ready|r" or "|cffff5555MSBT unavailable|r"
  controls.status:SetText(runtime .. "  •  " .. Z.GetAttachedCount() .. " visible nameplate(s) attached")
end

frame:SetScript("OnShow", function() frame:Refresh() end)
Z.options = frame

SLASH_ZDNUMBERS1 = "/zdn"
SLASH_ZDNUMBERS2 = "/zdnumbers"
SlashCmdList["ZDNUMBERS"] = function() if frame:IsShown() then frame:Hide() else frame:Show() end end
