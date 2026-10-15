"""Exercise real pet routing, independent pools/spacing, lane geometry and UI."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / "zDNumbers.lua").read_text(encoding="utf-8-sig")
# Reuse the counted fake-client bootstrap without running that suite's scenarios.
tree = ast.parse((root / "tests/test_render_performance.py").read_text(encoding="utf-8-sig"))
bootstrap = next(ast.literal_eval(n.value.args[0]) for n in tree.body
                 if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
                 and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == "execute")
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(bootstrap)
lua.execute('''
widgets={}; local originalWidget=widget
widget=function(...)
 local w=originalWidget(...); widgets[#widgets+1]=w
 function w:GetEffectiveScale() return self.scale*(self.parent and self.parent:GetEffectiveScale() or 1) end
 function w:GetStringWidth() return string.len(self.text or "")*(self.textHeight or 12)*.6 end
 function w:Enable() self.enabled=true end
 function w:Disable() self.enabled=false end
 function w:SetChecked(v) self.checked=v end
 function w:GetChecked() return self.checked end
 function w:EnableMouse() end
 function w:RegisterForDrag() end
 return w
end
petX=.8; petY=.212; petAvailable=true; petProjects=0
local originalExists=UnitExists
UnitExists=function(u) if u=="pet" then return petAvailable end return originalExists(u) end
local clientAPI=zAPI
zAPI=function(command,a,b,c)
 if command=="projectUnit" and a=="pet" then
  petProjects=petProjects+1; return petX,petY,20
 end
 return clientAPI(command,a,b,c)
end
petNativeAPI=zAPI
MikSBT.RegisterOutgoingNameplateHandler=function(f,enabled,resolver) outgoing=f; hintResolver=resolver end
function emit(guid,pet,crit,text,result)
 outgoing({TargetGUID=guid,Name=UnitName(guid),Amount=100,Text=text or "100",Texture="source.blp",IsBlocked=result,IsCrit=crit,
  EventType=pet and "MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE" or "MSBT_EVENTTYPE_OUTGOING_DAMAGE",
  ScrollArea={},EventSettings={FontSettings={Color={r=1,g=1,b=1}}}})
end
function record(i)
 for _,w in ipairs(widgets) do if w.kind=="Frame" and w.items and w.parent==plates[i] then return w end end
 error("Record not found")
end
function active(f,pet)
 local n=0; for _,v in pairs(f.items) do if v.active and (pet==nil or v.isPet==pet) then n=n+1 end end; return n
end
function first(f,pet)
 for _,v in pairs(f.items) do if v.active and v.isPet==pet then return v end end
end
function clear() zDNumbers.config.enabled="0"; clock=clock+.01; tick(clock); zDNumbers.config.enabled="1" end
function step() clock=clock+.01; tick(clock) end
-- Screen-space bounds from the rendered text anchors, independent of layout helpers.
function bounds(item)
 local p=item.text.SetPointArgs; local s=item.text:GetEffectiveScale()/UIParent:GetEffectiveScale()
 local x=p[4]; if p[2]~=UIParent then x=(250+x)*s end
 local w=item.text:GetStringWidth()*s; local l=x-w*.5
 if p[1]=="BOTTOMLEFT" then l=x elseif p[1]=="BOTTOMRIGHT" then l=x-w end
 local r=l+w
 if item.icon:IsShown() then l=l-(item.configuredIconSize+3)*s end
 if item.result.icon:IsShown() then r=r+(item.result.configuredIconSize+3)*s end
 return l,r
end
function rect(item)
 local l,r=bounds(item)
 local p=item.text.SetPointArgs; local s=item.text:GetEffectiveScale()/UIParent:GetEffectiveScale()
 local y=p[5]; if p[2]~=UIParent then y=(160+y)*s end
 local h=item.text:GetStringHeight()*s; local icon=0
 if item.icon:IsShown() then icon=item.configuredIconSize*s end
 if item.result.icon:IsShown() then icon=math.max(icon,item.result.configuredIconSize*s) end
 return l,r,math.min(y,y+(h-icon)*.5),math.max(y+h,y+(h+icon)*.5)
end
function assertSeparate(f)
 for _,main in pairs(f.items) do if main.active and not main.isPet then
  for _,pet in pairs(f.items) do if pet.active and pet.isPet then
   local ml,mr,mb,mt=rect(main); local pl,pr,pb,pt=rect(pet)
   assert(pr+1.9<=ml or pl>=mr+1.9 or pt+1.9<=mb or pb>=mt+1.9)
  end end
 end end
end
function assertLanes(f,side)
 local main,pet
 for _,v in pairs(f.items) do if v.active then
  assert(v.text:IsShown() and not v.pendingRender)
  if v.isPet then pet=true; assert(side=="LEFT" and v.petOffsetX<0 or side=="RIGHT" and v.petOffsetX>0)
  else main=true end
 end end
 assert(main and pet); assertSeparate(f)
end
function settle(side)
 petX=side=="LEFT" and -.4 or 1.2
 for i=1,50 do step() end
end
''')
lua.execute(source)
lua.execute('''
fire("ADDON_LOADED","z_DNumbers")
assert(zDNumbers.config.split_pet=="0" and not zDNumbers.config.pet_side)
-- Opt-out keeps the original combined ten-number capacity.
emit(plates[1].guid,false); emit(plates[1].guid,true); step()
local f=record(1); assert(active(f)==2)
assert(first(f,false).stackTarget>0) -- Pet and player share spacing while off.
assert(first(f,false).text.SetPointArgs[4]==first(f,true).text.SetPointArgs[4])
for i=1,15 do emit(plates[1].guid,i%2==0) end
assert(active(f)==10)
clear(); zDNumbers.config.split_pet="1"
-- Ordinary three-digit hits sit snugly together. A huge scroll-area setting
-- must not reserve invisible horizontal padding between the streams.
zDNumbers.config.width="500"; zDNumbers.Refresh()
emit(plates[1].guid,false); emit(plates[1].guid,true); step()
assertLanes(f,"RIGHT"); assert(f.petStreamOffset>0 and f.petStreamOffset<50)
local compactOffset=f.petStreamOffset
zDNumbers.config.width="120"; zDNumbers.Refresh(); step()
assert(math.abs(f.petStreamOffset-compactOffset)<.001)
clear()
emit(plates[1].guid,false,false,"100",true)
emit(plates[1].guid,true,true,"99999",true)
-- New numbers/icons cannot flash in the wrong column before the layout pass.
assert(not first(f,true).text:IsShown() and not first(f,true).icon:IsShown())
step(); assertLanes(f,"RIGHT")
assert(first(f,false).stackTarget==first(f,true).stackTarget) -- Independent vertical streams.
local old=first(f,false); local pet=first(f,true)
emit(plates[1].guid,true,false,"222"); step()
assert(old.stackTarget==old.position and pet.stackTarget>pet.position)
assertLanes(f,"RIGHT")
settle("LEFT"); assertLanes(f,"LEFT")
-- All alignments, icon-only results, large crits and inherited UI scales.
for _,alignment in ipairs({"LEFT","CENTER","RIGHT"}) do
 zDNumbers.config.align=alignment; step(); assertLanes(f,"LEFT")
 settle("RIGHT"); assertLanes(f,"RIGHT")
 settle("LEFT")
end
f:SetScale(.7); UIParent.scale=.8; step(); assertLanes(f,"LEFT")
f:SetScale(1); UIParent.scale=1; zDNumbers.config.align="CENTER"
-- A pitched/rotated camera can move higher numbers sideways and change depth.
local originalAPI=zAPI
zAPI=function(command,a,b,c)
 if command=="worldToScreen" then
  worldProjects=worldProjects+1; return .5+(c-2)*.06,.4+(c-2)*.01,20-(c-2)*2
 end
 return originalAPI(command,a,b,c)
end
for i=1,8 do step(); assertLanes(f,"LEFT") end
petX=1.2
settle("RIGHT")
for i=1,8 do step(); assertLanes(f,"RIGHT") end
zAPI=originalAPI; settle("LEFT")
-- Pet bursts may not evict or push a player's pending entries.
clear(); emit(plates[1].guid,false)
local main=first(f,false)
for i=1,25 do emit(plates[1].guid,true) end
assert(active(f,false)==1 and active(f,true)==10 and main.active)
for i=1,20 do emit(plates[1].guid,false) end
assert(active(f,false)==10 and active(f,true)==10)
step(); assertLanes(f,"LEFT")
-- Returning to combined mode and switching sides work without reload.
zDNumbers.config.split_pet="0"; step()
for _,v in pairs(f.items) do if v.active then assert(v.text.SetPointArgs[4]==main.text.SetPointArgs[4]) end end
clear(); zDNumbers.config.split_pet="1"
-- Equal simultaneous hits on different units consume source-matched GUID hints.
GetNampowerVersion=function() return 1 end; SetCVar=function() end
UnitGUID=function(u) if u=="pet" then return "petguid" end local b=units[u] or objects[u]; return b and b.guid end
event="AUTO_ATTACK_OTHER"; arg1="petguid"; arg2=plates[2].guid; arg3=100
named.zDNumbersEventFrame.scripts.OnEvent()
event="AUTO_ATTACK_SELF"; arg1=nil; arg2=plates[1].guid; arg3=100
named.zDNumbersEventFrame.scripts.OnEvent()
assert(hintResolver({Amount=100,EventType="MSBT_EVENTTYPE_OUTGOING_DAMAGE"})==plates[1].guid)
assert(hintResolver({Amount=100,EventType="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE"})==plates[2].guid)
-- Pet spells/DoTs and misses retain the same source classification and styling.
outgoing({TargetGUID=plates[1].guid,Name=UnitName(plates[1].guid),Amount=7,Text="7",
 EventType="MSBT_EVENTTYPE_OUTGOING_PET_SPELL_DOT",Texture="spell.blp",ScrollArea={},
 EventSettings={FontSettings={Color={r=.2,g=.7,b=.4}}}})
step(); assert(active(f,true)==1 and active(f,false)==0)
local color=first(f,true).text.SetTextColorArgs
assert(color[1]==.2 and color[2]==.7 and color[3]==.4)
clear()
-- The dummy pulse previews both streams without a real pet or DLL requirement.
MikSBT.CurrentProfile.DisplaySettings={Outgoing={},PetOutgoing={}}
local settings={Message="%a",FontSettings={Color={r=1,g=1,b=1}}}
MikSBT.CurrentProfile.EventSettings={MSBT_EVENTTYPE_OUTGOING_DAMAGE=settings,MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE=settings}
MikSBT.PrepareExternalAnimationEvent=function(e) e.Text=e.Text or e.Amount; return true end
assert(zDNumbers.PulseDummyDamage({plates[1]})); step()
assert(active(f,false)==1 and active(f,true)==1); assertLanes(f,"LEFT")
-- A dead/recycled native plate retains BOTH lanes on the old world anchor.
local guid=plates[1].guid; fire("NAME_PLATE_UNIT_REMOVED","nameplate1")
objects[guid]=nil; plates[1].guid="0xNEW"; objects["0xNEW"]=plates[1]
fire("NAME_PLATE_UNIT_ADDED","nameplate1"); step()
assert(f.parent==UIParent); assertLanes(f,"LEFT")
for i=1,60 do clock=clock+.1; tick(clock) end
assert(active(f)==0 and not f:IsShown())
-- Fallback rendering still gets isolated lanes and source icons with no DLL.
zAPI=nil; petAvailable=false
emit(plates[2].guid,false,true,"123456789",true)
emit(plates[2].guid,true,false,"22222",true); step()
local fallback=record(2); assertLanes(fallback,"RIGHT")
assert(first(fallback,true).icon:IsShown())
-- Once the widest number disappears, reclaim its gap smoothly, not forever.
local offset=fallback.petStreamOffset
first(fallback,false).active=nil; step()
assert(fallback.petStreamOffset<offset and fallback.petStreamOffset>offset*.5)
for i=1,25 do step() end
assert(fallback.petStreamOffset<offset*.5)
zDNumbers.config.split_pet="0"; clear()
''')

lua.execute('''
-- Screen-only direction cannot infer world yaw: pet height never lifts the lane.
zAPI=petNativeAPI; petAvailable=true; zDNumbers.config.split_pet="1"
for _,point in ipairs({{-.4,-.5},{1.2,-.5},{-.4,1.2},{1.2,1.2},{.2445,-.5},{.2445,1.2}}) do
 clear(); petX,petY=point[1],point[2]
 emit(plates[2].guid,false); emit(plates[2].guid,true); step()
 local f=record(2); assertSeparate(f)
 assert(f.petStreamOffsetY==0)
 if point[1]<0 then assert(f.petStreamOffset<0) elseif point[1]>1 then assert(f.petStreamOffset>0) end
 if point[1]==.2445 then assert(math.abs(f.petStreamOffset)<50) end
end
-- Legacy side changes remain level and clear.
petX=1.2; petY=.212
for i=1,35 do step(); assertSeparate(record(2)) end
local f=record(2); local angle=f.petStreamAngle
petX=-.4
step(); assert(f.petStreamOffset<0 and f.petStreamOffsetY==0)
for i=1,60 do step(); assertSeparate(f) end
assert(f.petStreamOffset<0)
-- Near-center jitter and unavailable/behind-camera pets hold the last direction.
local ml,mr,mb,mt=rect(first(f,false)); angle=f.petStreamAngle
petX=(ml+mr)*.5/1000; petY=(mb+mt)*.5/800
step(); assert(f.petStreamAngle==angle)
petAvailable=false; step(); assert(f.petStreamAngle==angle)
petAvailable=true; local native=zAPI
zAPI=function(command,a,b,c)
 if command=="projectUnit" and a=="pet" then return .8,.2,-1 end
 return native(command,a,b,c)
end
step(); assert(f.petStreamAngle==angle)
-- Five active nameplates share ONE pet projection, not one per number/plate.
clear(); zAPI=petNativeAPI; petX=1.2; petY=.212
for i=2,6 do emit(plates[i].guid,false); emit(plates[i].guid,true) end
local before=petProjects; step(); assert(petProjects-before==1)
-- A visible pet plate is a direction fallback even if its healthbar is hidden.
clear(); zAPI=nil
local previousGuid=UnitGUID
UnitGUID=function(u) if u=="pet" then return plates[3].guid end return previousGuid(u) end
local health=plates[3].nameplate.health
health.GetCenter=function() return 50,190 end; health:Hide()
emit(plates[2].guid,false); emit(plates[2].guid,true); step()
assert(record(2).petStreamOffset<0); assertSeparate(record(2))
health:Show(); UnitGUID=previousGuid
clear(); zDNumbers.config.split_pet="0"
''')

# Test the actual MSBT transfer/recycler contract (not duplicate display output).
msbt = (root / "MikScrollingBattleText/MikScrollingBattleText.lua").read_text(encoding="utf-8-sig")
bridge = msbt[msbt.index("function MikSBT.RegisterOutgoingNameplateHandler("):
              msbt.index("function MikSBT.PrepareExternalAnimationEvent(")]
lua.execute('scrollAreas={Outgoing={},PetOutgoing={}}; reclaimed=0; delivered=0; eventsRecycler={ReclaimTable=function() reclaimed=reclaimed+1 end}')
lua.execute(bridge)
lua.execute('''
MikSBT.RegisterOutgoingNameplateHandler(function() delivered=delivered+1 end,function() return true end)
for _,area in ipairs({scrollAreas.Outgoing,scrollAreas.PetOutgoing}) do
 assert(MikSBT.RouteOutgoingNameplateEvent({ScrollArea=area,EventType="damage"}))
end
assert(delivered==2 and reclaimed==2)
assert(not MikSBT.RouteOutgoingNameplateEvent({ScrollArea=scrollAreas.Outgoing,EventType="MSBT_EVENTTYPE_OUTGOING_HEAL"}))
''')

# Exercise the actual checkbox and automatic-position hint in the client UI.
lua.execute('''
SlashCmdList={}; getglobal=function(n) return named[n] end
zDNumbers.Refresh=function() if zDNumbers.options then zDNumbers.options:Refresh() end end
zDNumbers.GetAttachedCount=function() return 0 end
''')
lua.execute((root / "options.lua").read_text(encoding="utf-8-sig"))
lua.execute('''
zDNumbers.options:Refresh()
local checkbox,hint
for _,w in ipairs(widgets) do
 if w.kind=="CheckButton" and w.SetPointArgs[5]==-112 then checkbox=w end
 if w.kind=="FontString" and w.text=="Position: level orbit toward your pet (automatic)" then hint=w end
 assert(not (w.kind=="Button" and w.SetPointArgs and w.SetPointArgs[5]==-144))
end
assert(checkbox and hint and hint.alpha==.45)
this=checkbox; this.checked=true; this.scripts.OnClick()
assert(zDNumbers.config.split_pet=="1" and hint.alpha==1)
this=checkbox; this.checked=false; this.scripts.OnClick()
assert(zDNumbers.config.split_pet=="0" and hint.alpha==.45)
''')
print("Pet streams: level legacy fallback, compact separation/dead zone, shared pet projection, independent pools/spacing, source routing, previews, UI and death/recycling passed.")
