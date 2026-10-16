"""Missing selected-trigger state must recover without losing saved events."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
tree=ast.parse((root.parent/"z_Nameplates/tests/test_settings_ui.py").read_text(encoding="utf-8-sig"))
bootstrap=next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n,ast.Expr)
               and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=="execute")
lua=LuaRuntime(unpack_returned_tuples=True); lua.execute(bootstrap)
lua.execute('''
MikSBTOpt={}; local methods=getmetatable(UIParent).__index
function methods:GetName() return self.name end
local objects={}
getglobal=function(name)
 if not objects[name] then objects[name]=CreateFrame("Frame",name); objects[name]:SetChecked(true) end
 return objects[name]
end
MikCEH={TRIGGERTYPE_SEARCH_PATTERN=1,EraseTable=function(t) for k in pairs(t) do t[k]=nil end end}
local settings={TriggerType=1,TriggerEvents={"SPELL_A","SPELL_B"},SearchPatterns={"old"}}
MikSBT={CurrentProfile={Triggers={saved={TriggerSettings=settings}}},RegisterTriggers=function() registered=true end}
UIDropDownMenu_GetSelectedValue=function(frame) return string.find(frame.name,"Stance") and 7 or 1 end
''')
lua.execute((root/"MikScrollingBattleTextOptions/MSBTOptions.lua").read_text(encoding="utf-8-sig"))
lua.execute('''
MikSBTOpt.PopulateAvailableTriggerEvents=function() end
MikSBTOpt.PopulateDropdown=function() end
MikSBTOpt.PopulateEditbox=function(name,value) getglobal(name):SetText(value) end
local frame=getglobal("MSBTTriggerConfigFrame"); frame.TriggerKey="saved"
local settings=MikSBT.CurrentProfile.Triggers.saved.TriggerSettings
-- Save with no editor-local SelectedTriggerEvents: preserve the saved list.
frame.SelectedTriggerEvents=nil
getglobal("MSBTTriggerConfigFrameSearchPattern1Editbox"):SetText("new search")
MikSBTOpt.SaveTriggerConfig()
assert(registered and #settings.TriggerEvents==2)
assert(frame.SelectedTriggerEvents.SPELL_A and frame.SelectedTriggerEvents.SPELL_B)
-- Toggling a trigger-event checkbox is safe before the local table exists.
frame.SelectedTriggerEvents=nil
this=getglobal("MSBTTriggerConfigFrameTriggerEvent1Checkbox")
this.TriggerEvent="SPELL_C"; this:SetChecked(true); MikSBTOpt.CheckboxOnClick()
assert(frame.SelectedTriggerEvents.SPELL_C and frame.SelectedTriggerEvents.SPELL_A)
MikSBTOpt.SaveTriggerConfig(); assert(#settings.TriggerEvents==3)
this:SetChecked(false); MikSBTOpt.CheckboxOnClick(); MikSBTOpt.SaveTriggerConfig()
assert(#settings.TriggerEvents==2 and not frame.SelectedTriggerEvents.SPELL_C)
-- A threshold trigger switched to search has no list yet; that's valid.
settings.TriggerEvents=nil; frame.SelectedTriggerEvents=nil
MikSBTOpt.SetupVariableTriggerControls("saved",true)
MikSBTOpt.SaveTriggerConfig()
assert(type(frame.SelectedTriggerEvents)=="table" and #settings.TriggerEvents==0)
''')
print("MSBT trigger editor: missing state, retained selections, checkbox changes and threshold-to-search transitions passed.")
