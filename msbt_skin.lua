-- Presentation-only adaptation: retain MSBT's real frames, handlers and data.
local Z,UI=zDNumbers,zDNumbers.UI
local function Strip(frame)
  for _,region in ipairs({frame:GetRegions()}) do
    if region:GetObjectType()=="Texture" then region:SetTexture("") end
  end
end
local function StyleTree(frame,strata)
  if not frame then return end
  if strata then frame:SetFrameStrata(strata) end
  if frame.zSuiteSkinned then return end
  frame.zSuiteSkinned=true
  local kind,name=frame:GetObjectType(),frame:GetName() or ""
  if kind=="Button" and not string.find(name,"ColorSwatch") and not string.find(name,"Colorwatch") then
    -- Tab artwork is replaced by the explicit selected state below.
    Strip(frame); UI.Button(frame)
    if string.find(name,"CloseButton") then
      frame:SetText("x"); frame:SetWidth(24); frame:SetHeight(24)
    elseif string.find(name,"DropdownButton$") then frame:SetText("v")
    elseif string.find(name,"ScrollUpButton$") then frame:SetText("^")
    elseif string.find(name,"ScrollDownButton$") then frame:SetText("v")
    end
  elseif kind=="EditBox" then
    Strip(frame); UI.Surface(frame); frame:SetBackdropColor(.055,.07,.09,1)
    frame:SetTextColor(unpack(UI.colors.text)); frame:SetTextInsets(6,6,0,0)
  elseif kind=="Frame" or kind=="ScrollFrame" then
    -- Decorative character-sheet/skill-bar slices are container regions only.
    Strip(frame)
    if string.find(name,"Dropdown$") then
      UI.Surface(frame); frame:SetBackdropColor(.055,.07,.09,1)
    end
  end
  for _,child in ipairs({frame:GetChildren()}) do StyleTree(child,strata) end
end
local function Place(object,point,relative,relativePoint,x,y)
  if not object then return end
  object:ClearAllPoints(); object:SetPoint(point,relative,relativePoint,x,y)
end
function Z.StyleMSBTTabs(selected)
  local frame=MSBTFrameOptions
  if not frame then return end
  frame.selectedTab=selected or frame.selectedTab or 1
  for i=1,6 do
    local tab=getglobal("MSBTFrameOptionsTab"..i)
    if tab then
      if not tab.zSuiteSkinned then StyleTree(tab,"FULLSCREEN") end
      Place(tab,"TOPLEFT",frame,"TOPLEFT",14,-64-(i-1)*30)
      tab:SetWidth(136); tab:SetHeight(26)
      if tab.Enable then tab:Enable() end
      tab:SetBackdropColor(i==frame.selectedTab and .08 or .045,i==frame.selectedTab and .22 or .06,i==frame.selectedTab and .23 or .08,1)
      -- PanelTemplates left/centre/right texture regions stay hidden even
      -- after population/resizing. The original OnClick and tab ID remain.
      local caption=tab:GetFontString()
      if caption then Place(caption,"CENTER",tab,"CENTER",0,0); caption:SetTextColor(unpack(UI.colors.text)) end
    end
  end
  if frame.zSuitePageTitle then
    local data=MikSBTOpt.TABS[frame.selectedTab]
    frame.zSuitePageTitle:SetText(data and data.Label or "MSBT")
  end
end
function Z.StyleMSBTOptions()
  local frame=MSBTFrameOptions
  if not frame then return end
  StyleTree(frame,"FULLSCREEN"); UI.Surface(frame,true)
  frame:SetWidth(820); frame:SetHeight(560); frame:SetFrameStrata("FULLSCREEN")
  frame:SetHitRectInsets(0,0,0,0)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
  local title=getglobal("MSBTFrameOptionsTitleText")
  Place(title,"TOPLEFT",frame,"TOPLEFT",14,-12)
  title:SetText("MSBT  /  zDNumbers"); title:SetFontObject(GameFontNormalLarge); title:SetTextColor(unpack(UI.colors.text))
  Place(getglobal("MSBTFrameOptionsCloseButton"),"TOPRIGHT",frame,"TOPRIGHT",-10,-10)
  local drag=getglobal("MSBTFrameOptionsDrag")
  Place(drag,"TOPLEFT",frame,"TOPLEFT",8,-8); drag:SetWidth(750); drag:SetHeight(40)
  for i=1,6 do
    local page=getglobal("MSBTFrameOptionsTab"..i.."Frame")
    Place(page,"TOPLEFT",frame,"TOPLEFT",180,-108)
    page:SetWidth(610); page:SetHeight(390)
  end
  if not frame.zSuitePageTitle then
    UI.Text(frame,"z suite  /  Your existing profiles and event settings",14,-34,700):SetTextColor(unpack(UI.colors.muted))
    frame.zSuitePageTitle=UI.Text(frame,"",188,-64,580,true)
    local divider=frame:CreateTexture(nil,"BACKGROUND")
    divider:SetTexture("Interface\\BUTTONS\\WHITE8X8"); divider:SetVertexColor(.35,.4,.5,.25)
    divider:SetPoint("TOPLEFT",frame,"TOPLEFT",158,-56); divider:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",158,20); divider:SetWidth(1)
    local attached=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    attached:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-14,14); attached:SetWidth(150); attached:SetHeight(24)
    attached:SetText("zDNumbers settings"); UI.Button(attached)
    attached:SetScript("OnClick",function() if Z.options then Z.options:Show() end end)
  end
  for _,name in ipairs({"MSBTFontSettingsFrame","MSBTTriggerConfigFrame","MSBTScrollAreaMoverControlFrame"}) do
    local dialog=getglobal(name)
    if dialog then
      StyleTree(dialog,"FULLSCREEN_DIALOG"); UI.Surface(dialog,true); dialog:SetFrameStrata("FULLSCREEN_DIALOG")
      if dialog.SetClampedToScreen then dialog:SetClampedToScreen(true) end
    end
  end
  for _,name in ipairs({"Incoming","Outgoing","Notification","PetIncoming","PetOutgoing"}) do
    local mover=getglobal("MSBTScrollAreaMover"..name.."Frame")
    if mover then UI.Surface(mover,true); mover:SetBackdropColor(.035,.045,.06,.8) end
  end
  Z.StyleMSBTTabs(frame.selectedTab)
end
-- Native colour/confirmation dialogs must stay above the opaque suite panels.
local colorClick=MikSBTOpt.ColorSwatchOnClick
MikSBTOpt.ColorSwatchOnClick=function()
  colorClick(); UI.RaiseDialog(ColorPickerFrame)
end
local buttonClick=MikSBTOpt.ButtonOnClick
MikSBTOpt.ButtonOnClick=function()
  buttonClick()
  for i=1,4 do UI.RaiseDialog(getglobal("StaticPopup"..i)) end
end
