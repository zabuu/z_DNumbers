"""Exercise compact z-suite navigation/controls and presentation-only MSBT skin."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
tree=ast.parse((root.parent/"z_Nameplates/tests/test_settings_ui.py").read_text(encoding="utf-8-sig"))
bootstrap=next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n,ast.Expr)
               and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=="execute")
lua=LuaRuntime(unpack_returned_tuples=True); lua.execute(bootstrap)
lua.execute('''
local methods=getmetatable(UIParent).__index
function methods:GetName() return self.name end
function methods:GetObjectType() return self.kind end
function methods:GetChildren()
 local found={}; for _,f in ipairs(frames) do if f.owner==self and f.kind~="Texture" and f.kind~="FontString" then found[#found+1]=f end end
 return unpack(found)
end
function methods:GetRegions()
 local found={}; for _,f in ipairs(frames) do if f.owner==self and (f.kind=="Texture" or f.kind=="FontString") then found[#found+1]=f end end
 return unpack(found)
end
function methods:SetFontString(f) self.caption=f end
GameFontNormalLarge={}; UISpecialFrames={}
zDNumbers={config={enabled="1",icons="1",icon_opacity="55",perspective_tilt="30",x="0",y="8",width="120",height="142",fade=".65",align="CENTER",split_pet="0",pet_anchor="PET",pet_forward=".65"},defaults={}}
Z=zDNumbers; local C=Z.config
function Z.Refresh() if Z.options then Z.options:Refresh() end end
function Z.GetAttachedCount() return 3 end
function Z.EnsureEmbeddedMSBT() end
MikSBT={CurrentProfile={marker="preserve"}}
''')
for name in ("suite_ui.lua","options.lua"):
    lua.execute((root/name).read_text(encoding="utf-8-sig"))
lua.execute('''
Z.options:Show()
assert(Z.options:GetFrameStrata()=="FULLSCREEN" and Z.options.backdropColor[4]==1)
assert(Z.options.width==820 and Z.options.height==560 and #Z.settingsPages==4)
local function button(text)
 for _,f in ipairs(frames) do if f.kind=="Button" and f:GetText()==text then return f end end
 error("No button "..text)
end
for _,p in ipairs(Z.settingsPages) do invoke(button(p.name),"OnClick") end
local found={}; for _,w in ipairs(Z.settingsControls) do if w.key then found[w.key]=w end end
for _,key in ipairs({"enabled","icons","icon_opacity","perspective_tilt","x","y","width","height","fade","align","split_pet","pet_anchor","pet_forward"}) do assert(found[key],key) end
assert(Z.config.fade==".65" and Z.config.icon_opacity=="55" and Z.config.pet_forward==".65")
local w=found.x; w.input:SetText("999"); invoke(w.input,"OnEnterPressed")
assert(Z.config.x=="300")
w=found.pet_forward; w.input:SetText("1.25"); invoke(w.input,"OnEnterPressed")
assert(Z.config.pet_forward=="1.25")
w.input:SetText("2.75"); invoke(w.input,"OnEscapePressed"); assert(Z.config.pet_forward=="1.25")
invoke(found.split_pet.control,"OnClick"); assert(Z.config.split_pet=="0")
found.split_pet.control:SetChecked(true); invoke(found.split_pet.control,"OnClick"); assert(Z.config.split_pet=="1")
invoke(found.align.control,"OnClick"); assert(found.align.control.menu:IsShown())
local choose
for _,f in ipairs(frames) do if f.kind=="Button" and f:GetText()=="Right" and f.owner==found.align.control.menu then choose=f end end
invoke(choose,"OnClick"); assert(Z.config.align=="RIGHT" and not found.align.control.menu:IsShown())
invoke(button("Reset defaults..."),"OnClick"); assert(popup=="ZDN_RESET" and Z.config.x=="300")
-- Build the real named MSBT surface; skinning must not replace callbacks.
MSBTFrameOptions=CreateFrame("Frame","MSBTFrameOptions",UIParent)
MSBTFrameOptionsTitleText=MSBTFrameOptions:CreateFontString()
MSBTFrameOptionsCloseButton=CreateFrame("Button","MSBTFrameOptionsCloseButton",MSBTFrameOptions)
MSBTFrameOptionsDrag=CreateFrame("Frame","MSBTFrameOptionsDrag",MSBTFrameOptions)
MSBTFrameOptions.selectedTab=2
MikSBTOpt={TABS={}}
originalClick=function() preserved=true end
for i=1,6 do
 MikSBTOpt.TABS[i]={Label="Page"..i}
 local tab=CreateFrame("Button","MSBTFrameOptionsTab"..i,MSBTFrameOptions); tab:SetScript("OnClick",originalClick)
 CreateFrame("Frame","MSBTFrameOptionsTab"..i.."Frame",MSBTFrameOptions)
end
for _,name in ipairs({"MSBTFontSettingsFrame","MSBTTriggerConfigFrame","MSBTScrollAreaMoverControlFrame"}) do CreateFrame("Frame",name,UIParent) end
MSBTOriginalEdit=CreateFrame("EditBox","MSBTOriginalEdit",MSBTFrameOptionsTab1Frame)
MSBTOriginalEdit:SetFrameStrata("HIGH") -- The embedded XML explicitly uses HIGH.
MSBTOriginalEdit:SetScript("OnTextChanged",originalClick)
MikSBTOpt.ColorSwatchOnClick=function() colorClicked=true end
MikSBTOpt.ButtonOnClick=function() buttonClicked=true end
''')
lua.execute((root/"msbt_skin.lua").read_text(encoding="utf-8-sig"))
lua.execute('''
Z.StyleMSBTOptions()
assert(MSBTFrameOptions.width==820 and MSBTFrameOptions.height==560)
assert(MSBTFrameOptions.backdropColor[4]==1 and MSBTFrameOptions:GetFrameStrata()=="FULLSCREEN")
assert(MSBTOriginalEdit:GetScript("OnTextChanged")==originalClick)
assert(MSBTOriginalEdit:GetFrameStrata()=="FULLSCREEN")
for i=1,6 do
 local tab=getglobal("MSBTFrameOptionsTab"..i)
 assert(tab:GetScript("OnClick")==originalClick and tab.width==136 and tab.height==26)
 local p=getglobal("MSBTFrameOptionsTab"..i.."Frame").points[1]
 assert(p[4]==180 and p[5]==-108)
end
assert(MSBTFontSettingsFrame:GetFrameStrata()=="FULLSCREEN_DIALOG")
Z.StyleMSBTTabs(5); assert(MSBTFrameOptions.selectedTab==5 and MSBTFrameOptions.zSuitePageTitle:GetText()=="Page5")
ColorPickerFrame=CreateFrame("Frame"); MikSBTOpt.ColorSwatchOnClick()
assert(colorClicked and ColorPickerFrame:GetFrameStrata()=="FULLSCREEN_DIALOG")
ColorPickerFrame:Hide(); assert(ColorPickerFrame:GetFrameStrata()=="DIALOG")
assert(MikSBT.CurrentProfile.marker=="preserve")
''')
print("Suite UI: all placement controls, compact pages, numeric edits, dropdowns, confirmations, MSBT callback/profile preservation and modal layering passed.")
