"""Exercise over-pet routing and MSBT fallback using the real renderer."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
tree=ast.parse((root/"tests/test_render_performance.py").read_text(encoding="utf-8-sig"))
bootstrap=next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n,ast.Expr)
               and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=="execute")
lua=LuaRuntime(unpack_returned_tuples=True); lua.execute(bootstrap)
lua.execute('''
local oldGuid,oldExists=UnitGUID,UnitExists
petGuid="0xF140000000001234"; petExists=true; petVisible=true; petX=10; petY=20; noseProjects=0
UnitGUID=function(unit) if unit=="pet" then return petExists and petGuid end return oldGuid(unit) end
UnitExists=function(unit) if unit=="pet" or unit==petGuid then return petExists end return oldExists(unit) end
local previous=zAPI
local function project(x,y,z) return .5+x*.002,.4+y*.002+z*.01,20-z*.1 end
zAPI=function(command,unit,offset,forward)
 if command=="projectUnitForward" and unit==petGuid then
  noseProjects=noseProjects+1
  local wx,wy,wz=petX+(forward or .65),petY,2+(offset or 0)
  local x,y,d=project(wx,wy,wz)
  return petVisible and x or 1.2,y,d,wx,wy,wz
 elseif command=="worldToScreen" then return project(unit,offset,forward) end
 return previous(command,unit,offset,forward)
end
fallback={}; MikSBT.AddAnimation=function(event) table.insert(fallback,event) end
MikSBT.RegisterOutgoingNameplateHandler=function(f) outgoing=f end
function hit(pet)
 return outgoing({TargetGUID=plates[1].guid,Name="Mob1",Amount=100,Text="100",Texture="source.blp",
  EventType=pet and "MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE" or "MSBT_EVENTTYPE_OUTGOING_DAMAGE",
  ScrollArea={},EventSettings={FontSettings={Color={r=.2,g=.4,b=.6}}}})
end
function count(frame)
 local n=0; for _,item in pairs(frame.items) do if item.active then n=n+1 end end; return n
end
''')
lua.execute((root/"zDNumbers.lua").read_text(encoding="utf-8-sig"))
lua.execute('''
fire("ADDON_LOADED","z_DNumbers")
assert(zDNumbers.config.pet_anchor=="PET" and zDNumbers.config.split_pet=="0")
zDNumbers.config.split_pet="1"
assert(hit(true)==true)
local record=zDNumbers.petRecord; local frame=record.frame
assert(record.petOwner and frame.parent==UIParent and count(frame)==1)
-- Model the engine's real anchored-frame geometry for this independent owner.
function frame:GetBottom() return self.SetPointArgs[5] end
function frame:GetLeft() return self.SetPointArgs[4]-self.width*.5 end
function frame:GetRight() return self.SetPointArgs[4]+self.width*.5 end
tick(.01)
local item=frame.items[1]; local point=item.text.SetPointArgs
assert(point[2]==UIParent and item.text:IsShown())
assert(math.abs(point[4]-(.5+(petX+.65)*.002)*1000)<.001)
assert(item.text.SetTextColorArgs[1]==.2 and item.text.SetTextColorArgs[3]==.6)
-- More events share a pet stream, even across different target GUIDs.
hit(true); hit(true); assert(count(frame)==3)
local before=noseProjects; petX=30; tick(.02)
assert(noseProjects-before==1) -- One shared base sample, no repeated pet lookups.
assert(frame.SetPointArgs[4]>(.5+30*.002)*1000)
hit(false); assert(count(frame)==3) -- Player damage remains over its target.
-- Leaving the viewport transfers all live pet slots exactly once to MSBT.
petVisible=false; tick(.03)
assert(count(frame)==0 and not frame:IsShown() and table.getn(fallback)==3)
assert(fallback[1].EventType=="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE")
tick(.04); assert(table.getn(fallback)==3)
assert(hit(true)==false) -- The bridge leaves the original event for MSBT.
assert(table.getn(fallback)==3)
petVisible=true; tick(.05); assert(hit(true)==true and count(frame)==1)
petExists=false; tick(.06)
assert(count(frame)==0 and table.getn(fallback)==4 and hit(true)==false)
petExists=true; petGuid="0xF140000000005678"; tick(.07)
assert(hit(true)==true and record.guid==petGuid)
fire("PLAYER_ENTERING_WORLD"); assert(count(frame)==0)
''')
# An explicit false means the recycler is still owned by normal MSBT, whereas
# legacy nil-returning callbacks retain the original successful-transfer API.
msbt=(root/"MikScrollingBattleText/MikScrollingBattleText.lua").read_text(encoding="utf-8-sig")
bridge=msbt[msbt.index("function MikSBT.RegisterOutgoingNameplateHandler("):msbt.index("function MikSBT.PrepareExternalAnimationEvent(")]
lua.execute('scrollAreas={Outgoing={},PetOutgoing={}}; reclaimed=0; eventsRecycler={ReclaimTable=function() reclaimed=reclaimed+1 end}')
lua.execute(bridge)
lua.execute('''
local e={ScrollArea=scrollAreas.PetOutgoing,EventType="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE"}
MikSBT.RegisterOutgoingNameplateHandler(function() return false end,function() return true end)
assert(not MikSBT.RouteOutgoingNameplateEvent(e) and reclaimed==0)
MikSBT.RegisterOutgoingNameplateHandler(function() end,function() return true end)
assert(MikSBT.RouteOutgoingNameplateEvent(e) and reclaimed==1)
''')
print("Pet anchor: nose projection, shared stream, original styles, visible/off-screen routing, live migration and recycler ownership passed.")
