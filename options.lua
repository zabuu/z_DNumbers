local Z, UI = zDNumbers, zDNumbers.UI
local frame=UI.Window("zDNumbersOptions","zDNumbers","z suite  /  Settings apply immediately")
local pages={
  {name="Placement",description="Camera-aware outgoing damage attached to the world.",items={
    {"check","Attach outgoing damage to nameplates","enabled"},
    {"section","Position & travel"},
    {"slider","Horizontal offset","x",-300,300,1," px"},
    {"slider","Height above the health bar","y",-100,300,1," px"},
    {"slider","Scroll-area width","width",20,500,1," px"},
    {"slider","Scroll height / travel distance","height",10,600,1," px"},
    {"slider","Delay before fading","fade",0,10,.05," sec",2},
  }},
  {name="Appearance",description="Icons, alignment and perspective. MSBT controls fonts and event colours.",items={
    {"check","Show spell and attack source icons","icons"},
    {"slider","Source-icon opacity","icon_opacity",0,100,1,"%"},
    {"slider","Perspective depth","perspective_tilt",0,100,1,"%"},
    {"select","Text alignment","align",{{"Left","LEFT"},{"Centre","CENTER"},{"Right","RIGHT"}}},
    {"note","Source icons retain their rounded edges and padding. Block, parry and glancing-result icons remain enabled."},
    {"note","Perspective changes world-space travel and glyph shaping; text remains camera-horizontal."},
  }},
  {name="Pet damage",description="Keep pet damage near its source instead of crowding the target.",items={
    {"check","Split pet damage into a separate stream","split_pet"},
    {"select","Pet damage anchor","pet_anchor",{{"Over the pet","PET"},{"Beside target (legacy)","TARGET"}}},
    {"slider","Forward distance past the pet","pet_forward",0,3,.05," yd",2},
    {"note","Pet damage rises above the pet's nose, independently of enemy nameplates. Off-screen pets use the normal MSBT Pet Outgoing screen area."},
    {"note","Pet fonts, colours, crit sizing, filters and merge rules still come from MSBT. Turning this off restores the combined target stream."},
  }},
  {name="MSBT",description="The complete embedded MSBT editor, styled to match the z suite.",items={
    {"note","All original MSBT controls are retained: profiles, fonts, incoming and outgoing events, notifications, triggers, suppressions and scroll-area positioning."},
    {"action","Open MSBT settings",function() Z.EnsureEmbeddedMSBT(); if MSBTFrameOptions then MSBTFrameOptions:Show() end end},
    {"note","Use the MSBT scroll-area mover to position the static fallback for off-screen pet damage. Your existing MSBT profile is preserved."},
  }},
}
local controls,tabs,active={},{},1
Z.settingsPages=pages
local title=UI.Text(frame,"",178,-60,600,true)
local description=UI.Text(frame,"",178,-82,600); description:SetTextColor(unpack(UI.colors.muted))
local scroll=CreateFrame("ScrollFrame","zDNumbersSettingsScroll",frame,"UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT",frame,"TOPLEFT",170,-110); scroll:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-30,58)
local content=CreateFrame("Frame",nil,scroll); content:SetWidth(620); content:SetHeight(1); scroll:SetScrollChild(content)
local divider=frame:CreateTexture(nil,"ARTWORK")
divider:SetTexture("Interface\\BUTTONS\\WHITE8X8"); divider:SetVertexColor(.35,.4,.5,.25)
divider:SetPoint("TOPLEFT",frame,"TOPLEFT",158,-56); divider:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",158,52); divider:SetWidth(1)
local function SetValue(key,value)
  if not Z.config or tostring(Z.config[key])==tostring(value) then return end
  Z.config[key]=tostring(value); Z.Refresh()
end
local function OpenPage(index)
  active=index; local page=pages[index]; title:SetText(page.name); description:SetText(page.description)
  local y=0
  for _,widget in ipairs(controls) do
    if widget.page==index then
      widget.row:ClearAllPoints(); widget.row:SetPoint("TOPLEFT",content,"TOPLEFT",0,-y); widget.row:Show(); y=y+widget.height
    else widget.row:Hide() end
  end
  content:SetHeight(math.max(1,y)); scroll:SetVerticalScroll(0)
  for i,tab in ipairs(tabs) do tab:SetBackdropColor(i==index and .08 or .045,i==index and .22 or .06,i==index and .23 or .08,1) end
end
for pageIndex,page in ipairs(pages) do
  local index=pageIndex
  local tab=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
  tab:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-64-(index-1)*30); tab:SetWidth(136); tab:SetHeight(26)
  tab:SetText(page.name); UI.Button(tab); tabs[index]=tab
  tab:SetScript("OnClick",function() OpenPage(index); frame:Refresh() end)
  for _,definition in ipairs(page.items) do
    local item=definition -- Private binding for legacy Lua closures.
    local kind,text,key=item[1],item[2],item[3]
    local row=CreateFrame("Frame",nil,content)
    local height=kind=="slider" and 40 or kind=="note" and 64 or 32
    row:SetWidth(620); row:SetHeight(height)
    local widget={page=index,row=row,height=height,key=key,kind=kind}; table.insert(controls,widget)
    if kind=="check" then
      local control=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
      control:SetWidth(22); control:SetHeight(22); control:SetPoint("TOPLEFT",row,"TOPLEFT",8,-3)
      UI.Text(row,text,35,-8,575)
      control:SetScript("OnClick",function() SetValue(key,this:GetChecked() and "1" or "0") end); widget.control=control
    elseif kind=="slider" then
      UI.Text(row,text,8,-7,295)
      local name="zDNumbersSettingSlider"..table.getn(controls)
      local control=CreateFrame("Slider",name,row,"OptionsSliderTemplate")
      control:SetPoint("TOPLEFT",row,"TOPLEFT",320,-6); control:SetWidth(175); control:SetHeight(16)
      control:SetMinMaxValues(item[4],item[5]); control:SetValueStep(item[6])
      for _,suffix in ipairs({"Low","High","Text"}) do
        local region=getglobal(name..suffix)
        if region then region:SetText(suffix=="Low" and item[4]..item[7] or suffix=="High" and item[5]..item[7] or "") end
      end
      local input=UI.Input(row); input:SetWidth(85); input:SetHeight(24); input:SetPoint("TOPRIGHT",row,"TOPRIGHT",-8,-2)
      input:SetScript("OnEditFocusGained",function() this.editing=true end)
      local function SaveNumber(value)
        local number=tonumber(value)
        if not number then frame:Refresh(); return end
        number=math.max(item[4],math.min(item[5],number)); number=math.floor(number/item[6]+.5)*item[6]
        SetValue(key,string.format("%."..(item[8] or 0).."f",number))
      end
      control:SetScript("OnValueChanged",function() if not frame.updating then SaveNumber(arg1 or this:GetValue()) end end)
      input:SetScript("OnEnterPressed",function() SaveNumber(this:GetText()); this:ClearFocus() end)
      input:SetScript("OnEscapePressed",function() this:SetText(Z.config[key]); this:ClearFocus(); frame:Refresh() end)
      input:SetScript("OnEditFocusLost",function() this.editing=nil; if not frame.updating then SaveNumber(this:GetText()) end end)
      widget.control,widget.input=control,input; widget.format="%."..(item[8] or 0).."f"
    elseif kind=="select" then
      UI.Text(row,text,8,-7,295)
      widget.control=UI.Select(row,item[4],function() return Z.config and Z.config[key] end,function(value) SetValue(key,value) end)
      widget.control:SetPoint("TOPRIGHT",row,"TOPRIGHT",-8,-2)
    elseif kind=="action" then
      local control=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
      control:SetPoint("TOPLEFT",row,"TOPLEFT",8,-2); control:SetWidth(260); control:SetHeight(24)
      control:SetText(text); UI.Button(control); control:SetScript("OnClick",key)
    else
      local label=UI.Text(row,text,8,-8,598,kind=="section")
      if kind=="note" then label:SetTextColor(unpack(UI.colors.muted)) end
    end
  end
end
local status=UI.Text(frame,"",178,-510,580); status:SetTextColor(unpack(UI.colors.muted))
local reset=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
reset:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",14,14); reset:SetWidth(136); reset:SetHeight(24)
reset:SetText("Reset defaults..."); UI.Button(reset)
reset:SetScript("OnClick",function()
  StaticPopupDialogs.ZDN_RESET={text="Reset zDNumbers placement and appearance? MSBT profiles are not changed.",
    button1="Reset",button2="Cancel",OnAccept=function() Z.Reset() end,timeout=0,whileDead=1,hideOnEscape=1}
  UI.RaiseDialog(StaticPopup_Show("ZDN_RESET"))
end)
local msbt=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
msbt:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-14,14); msbt:SetWidth(140); msbt:SetHeight(24)
msbt:SetText("MSBT settings"); UI.Button(msbt)
msbt:SetScript("OnClick",function() Z.EnsureEmbeddedMSBT(); if MSBTFrameOptions then MSBTFrameOptions:Show() end end)
function frame:Refresh()
  if not Z.config then return end
  self.updating=true
  for _,widget in ipairs(controls) do
    if widget.kind=="check" then widget.control:SetChecked(Z.config[widget.key]=="1")
    elseif widget.kind=="slider" then
      local value=tonumber(Z.config[widget.key]) or tonumber(Z.defaults[widget.key]) or 0
      widget.control:SetValue(value)
      if not widget.input.editing then widget.input:SetText(string.format(widget.format,value)) end
    elseif widget.kind=="select" then widget.control:Refresh() end
  end
  self.updating=nil
  status:SetText((MikSBT and MikSBT.CurrentProfile and "MSBT ready" or "MSBT unavailable").."  /  "..Z.GetAttachedCount().." visible plates")
end
frame:SetScript("OnShow",function() OpenPage(active); frame:Refresh() end)
Z.options,Z.settingsControls=frame,controls
SLASH_ZDNUMBERS1="/zdn"; SLASH_ZDNUMBERS2="/zdnumbers"
SlashCmdList.ZDNUMBERS=function() if frame:IsShown() then frame:Hide() else frame:Show() end end
