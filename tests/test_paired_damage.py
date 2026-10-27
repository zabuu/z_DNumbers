"""Actual MSBT adapter/dispatch and zDNumbers rendering for a paired source."""
import ast,re
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
tree=ast.parse((ROOT/'tests/test_render_performance.py').read_text())
boot=next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n,ast.Expr)
    and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='execute')
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(boot)
lua.execute('''
peerGUID="0x0000000000000022";petGUID="0xF140000000001234";peerLoaded=true;peerVisible=true;paired=true
local exists,unitguid=UnitExists,UnitGUID
UnitExists=function(u) if u==peerGUID then return peerLoaded end;if u=="pet" or u==petGUID then return true end;return exists(u) end
UnitGUID=function(u) if u=="pet" then return petGUID end;return unitguid(u) end
local api=zAPI
peerWorldReads=0;realWorldReads=0
zAPI=function(cmd,u,a,b)
 if cmd=="projectUnitForward" and (u==peerGUID or u==petGUID) then
  return (u~=peerGUID or peerVisible) and .65 or 1.5,.4,20,115,200,2
 elseif cmd=="unitPosition" and (u==peerGUID or u=="pet") then
  if u==peerGUID then peerWorldReads=peerWorldReads+1;return 110,200,2 end
  realWorldReads=realWorldReads+1;return 90,200,2
 end
 return api(cmd,u,a,b)
end
eventsRecycler={AcquireTable=function() return {} end,ReclaimTable=function() end}
scrollAreas={Outgoing={DisplaySettings={Show=true}},PetOutgoing={DisplaySettings={Show=true}}}
animationMergeData={Outgoing={UnmergedEvents={}},PetOutgoing={UnmergedEvents={}}}
fallback={};MikSBT.AddAnimation=function(e) table.insert(fallback,e) end
''')
msbt=(ROOT/'MikScrollingBattleText/MikScrollingBattleText.lua').read_text(encoding='utf-8-sig')
def section(start,end):return msbt[msbt.index(start):msbt.index(end,msbt.index(start)+len(start))]
# Same renderer bridge and dispatcher as the shipped runtime; keep its formatter
# stub from the counted renderer fixture so no locale/asset dependencies are needed.
lua.execute(section('function MikSBT.RegisterOutgoingNameplateHandler(','function MikSBT.PrepareExternalAnimationEvent('))
lua.execute(section('function MikSBT.DispatchAnimationEvent(','function MikSBT.ResolveEffectIcon('))
lua.execute(section('function MikSBT.SubmitPairedPetDamage(','function MikSBT.DisplayMessage('))
lua.execute((ROOT/'zDNumbers.lua').read_text(encoding='utf-8-sig'))
lua.execute((ROOT/'paired_damage.lua').read_text())
lua.execute('''
fire("ADDON_LOADED","z_DNumbers")
local style={Show=true,Message="%a",FontSettings={Color={r=.2,g=.4,b=.6}}}
MikSBT.CurrentProfile.EventSettings={MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE=style,MSBT_EVENTTYPE_OUTGOING_PET_SPELL_DAMAGE=style}
zDNumbers.SetPairedDamageSource(function() return paired and peerGUID end)
function flush()
 local queue=animationMergeData.PetOutgoing.UnmergedEvents
 for i=1,table.getn(queue) do
  local e=queue[i];if not MikSBT.RouteOutgoingNameplateEvent(e) then MikSBT.AddAnimation(e) end
 end
 animationMergeData.PetOutgoing.UnmergedEvents={}
end
function relay()
 return zDNumbers.ShowPairedDamage({Kind="SPELL_DAMAGE",Amount=123,Name="Mob1",EffectName="Strike",SpellID=1752,
   TargetGUID=plates[1].guid,DamageType="Physical",IsCrit=true,IsGlancing=true},peerGUID)
end
function count(frame) local n=0;for _,item in pairs(frame.items) do if item.active then n=n+1 end end;return n end
zDNumbers.config.split_pet="0"
assert(relay());local e=animationMergeData.PetOutgoing.UnmergedEvents[1]
assert(e.EventType=="MSBT_EVENTTYPE_OUTGOING_PET_SPELL_DAMAGE" and e.EventSettings==style and e.IsCrit and e.IsGlancing)
assert(e.TargetGUID==plates[1].guid and e.PetSourceGUID==peerGUID and e.SpellID==1752 and e.DamageType=="Physical")
flush();tick(.01)
assert(not zDNumbers.pairedPetRecord) -- Shared target stream when splitting is off.
zDNumbers.config.split_pet="1";zDNumbers.config.pet_anchor="PET"
assert(relay());flush();tick(.02)
local buddy=zDNumbers.pairedPetRecord
assert(buddy.pairedOwner and buddy.sourceGUID==peerGUID and buddy.guid==peerGUID and count(buddy.frame)==1)
assert(buddy.frame.parent==UIParent and buddy.frame.items[1].isPet)
assert(zDNumbers.ShowPairedDamage({Kind="DAMAGE",Amount=50,TargetGUID=plates[1].guid},"0x0000000000000099")==false)
-- A real pet has a different source record and keeps its existing path.
MikSBT.RouteOutgoingNameplateEvent({EventType="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE",ScrollArea=scrollAreas.PetOutgoing,
 EventSettings=style,Amount=50,Name="Mob1",TargetGUID=plates[1].guid})
assert(zDNumbers.petRecord and zDNumbers.petRecord~=buddy and not zDNumbers.petRecord.pairedOwner)
peerVisible=false;tick(.03)
assert(count(buddy.frame)==0 and table.getn(fallback)==1)
tick(.04);assert(table.getn(fallback)==1) -- One-time static MSBT fallback.
peerVisible=true;assert(relay());flush();tick(.05);assert(count(buddy.frame)==1)
paired=false;tick(.06);assert(count(buddy.frame)==0 and table.getn(fallback)==2 and not relay())
paired=true
-- Target-anchored pet mode also carries a separate source geometry cache.
zDNumbers.config.pet_anchor="TARGET";assert(relay());flush();tick(.07)
assert(peerWorldReads>0)
-- The observer sees unmerged metadata before this account's local show filter.
local observed=0
zDNumbers.SetOutgoingDamageObserver(function(a) observed=observed+1;assert(a.Amount==7) end,function() return true end)
MikSBT.DispatchAnimationEvent({EventType="MSBT_EVENTTYPE_OUTGOING_DAMAGE",Amount=7,
 ScrollArea=scrollAreas.Outgoing,EventSettings={Show=false}})
assert(observed==1)
assert(relay());assert(observed==1) -- No relay loop for pet-identified data.
zDNumbers.SetOutgoingDamageObserver(function() error("observer failure") end,function() return false end)
MikSBT.DispatchAnimationEvent({EventType="MSBT_EVENTTYPE_OUTGOING_DAMAGE",Amount=7,
 ScrollArea=scrollAreas.Outgoing,EventSettings={Show=false}})
''')
# Existing merge rules retain two separate sources even on the same enemy/spell.
merge=section('function MikSBT.MergeEvents(','function MikSBT.')
merge=re.sub(r'(\bfor[ \t]+[\w_, \t]+[ \t]+in[ \t]+)([^\n]+?)([ \t]+do\b)',
    lambda m:m[0] if '(' in m[2] else m[1]+'pairs('+m[2]+')'+m[3],merge)
lua.execute(merge)
lua.execute('''
table.setn=function() end -- Lua 5.0 array-length API; Lua 5.1 infers it here.
local q={IsOutgoing=true,UnmergedEvents={},MergedEvents={}}
for i=1,2 do q.UnmergedEvents[i]={EventType="MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE",Name="Mob1",Amount=10,
 ScrollArea=scrollAreas.PetOutgoing,TargetGUID=plates[1].guid,PetSourceGUID=i==1 and peerGUID or nil} end
MikSBT.MergeEvents(q,2);assert(table.getn(q.MergedEvents)==2)
''')
print('PASS: real MSBT pet-style dispatch, GUID/crit/spell/school metadata, disabled-local-display observer, no echo loop, shared target/independent buddy+pet anchors, off-screen/unlink fallback, source-specific target geometry and non-merging sources')
