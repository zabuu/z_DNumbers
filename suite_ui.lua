-- Shared z-suite settings primitives, independent of zNameplates and pfUI.
zDNumbers = zDNumbers or {}
local UI = {}; zDNumbers.UI = UI
local WHITE = "Interface\\BUTTONS\\WHITE8X8"
UI.colors = {background={.035,.045,.06,1},surface={.09,.12,.16,1},border={.22,.28,.35,1},
  text={.9,.94,.98,1},muted={.65,.72,.8,1},accent={.2,.85,.72,1}}
function UI.Surface(frame,panel)
  frame:SetBackdrop({bgFile=WHITE,edgeFile=panel and "Interface\\Tooltips\\UI-Tooltip-Border" or WHITE,
    edgeSize=panel and 12 or 1,insets=panel and {left=4,right=4,top=4,bottom=4} or nil})
  frame:SetBackdropColor(unpack(panel and UI.colors.background or UI.colors.surface))
  frame:SetBackdropBorderColor(unpack(UI.colors.border))
end
function UI.Button(button)
  button:SetNormalTexture(""); button:SetPushedTexture(""); button:SetDisabledTexture("")
  UI.Surface(button); button:SetHighlightTexture(WHITE)
  local highlight=button:GetHighlightTexture()
  if highlight then highlight:SetVertexColor(.25,.7,.65,.14) end
  local text=button:GetFontString()
  if not text then
    text=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    text:SetPoint("CENTER",button,"CENTER",0,0); button:SetFontString(text)
  end
  text:SetTextColor(unpack(UI.colors.text))
end
function UI.Text(parent,text,x,y,width,large)
  local label=parent:CreateFontString(nil,"OVERLAY",large and "GameFontNormalLarge" or "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y); label:SetWidth(width or 580); label:SetJustifyH("LEFT")
  label:SetTextColor(unpack(UI.colors.text)); label:SetText(text); return label
end
function UI.Input(parent)
  local edit=CreateFrame("EditBox",nil,parent)
  edit:SetFontObject(GameFontHighlightSmall); edit:SetTextInsets(7,7,0,0); edit:SetAutoFocus(false)
  UI.Surface(edit); edit:SetBackdropColor(.055,.07,.09,1); edit:SetTextColor(unpack(UI.colors.text)); return edit
end
function UI.RaiseDialog(dialog)
  if not dialog or not dialog:IsShown() then return end
  if not dialog.zSuiteLayerHook then
    local previous=dialog:GetScript("OnHide")
    dialog:SetScript("OnHide",function()
      if previous then previous(dialog) end
      if dialog.zSuiteOldStrata then dialog:SetFrameStrata(dialog.zSuiteOldStrata); dialog.zSuiteOldStrata=nil end
    end)
    dialog.zSuiteLayerHook=true
  end
  dialog.zSuiteOldStrata=dialog.zSuiteOldStrata or dialog:GetFrameStrata()
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
end
function UI.Window(name,title,subtitle)
  local frame=CreateFrame("Frame",name,UIParent)
  frame:SetWidth(820); frame:SetHeight(560); frame:SetPoint("CENTER",UIParent,"CENTER",0,20)
  frame:SetFrameStrata("FULLSCREEN"); frame:EnableMouse(true); frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart",function() this:StartMoving() end)
  frame:SetScript("OnDragStop",function() this:StopMovingOrSizing() end)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  UI.Surface(frame,true); frame.title=UI.Text(frame,title,14,-12,620,true)
  frame.subtitle=UI.Text(frame,subtitle,14,-34,700); frame.subtitle:SetTextColor(unpack(UI.colors.muted))
  local close=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
  close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-10); close:SetWidth(24); close:SetHeight(24)
  close:SetText("x"); UI.Button(close); close:SetScript("OnClick",function() frame:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames,name) end
  frame:Hide(); return frame
end
function UI.Select(parent,values,getValue,setValue)
  local button=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
  button:SetWidth(230); button:SetHeight(24); UI.Button(button)
  local menu=CreateFrame("Frame",nil,button)
  menu:SetWidth(230); menu:SetHeight(table.getn(values)*24+8); menu:SetFrameStrata("TOOLTIP")
  menu:EnableMouse(true); UI.Surface(menu,true); menu:SetPoint("TOPRIGHT",button,"BOTTOMRIGHT",0,-2); menu:Hide()
  button.menu=menu
  function button:Refresh()
    local current=getValue()
    for _,value in ipairs(values) do if value[2]==current then self:SetText(value[1].."  v"); return end end
    self:SetText(tostring(current).."  v")
  end
  for i,value in ipairs(values) do
    local row=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate")
    row:SetPoint("TOPLEFT",menu,"TOPLEFT",4,-4-(i-1)*24); row:SetWidth(222); row:SetHeight(24)
    row:SetText(value[1]); UI.Button(row); local choice=value[2]
    row:SetScript("OnClick",function() setValue(choice); menu:Hide(); button:Refresh() end)
  end
  button:SetScript("OnClick",function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
  button:SetScript("OnHide",function() menu:Hide() end)
  return button
end
