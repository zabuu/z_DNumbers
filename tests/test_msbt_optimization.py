"""Compare imported MSBT with its preserved baseline using Lua 5.0 semantics."""
from pathlib import Path
import re
import gzip
import hashlib
import json
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
BASELINE = json.loads(gzip.decompress((ROOT / "tests/fixtures/msbt-before-optimization-20261014.json.gz").read_bytes()))
for name, source in BASELINE["files"].items():
    assert hashlib.sha256(source.encode("utf-8")).hexdigest() == BASELINE["source_sha256"][name]
NEW = ROOT / "MikScrollingBattleText"


def vanilla_loops(source):
    # Vanilla's generic-for accepts a table. Lua 5.1 needs pairs explicitly.
    return re.sub(
        r"(\bfor[ \t]+[\w_, \t]+[ \t]+in[ \t]+)([^\n]+?)([ \t]+do\b)",
        lambda m: m[0] if "(" in m[2] else m[1] + "pairs(" + m[2] + ")" + m[3],
        source,
    )


HARNESS = '''
now=0; writes=0; clocks=0; moves=0; iterators=0; memoryReads=0; messages={}; SlashCmdList={}
ceil=math.ceil; floor=math.floor; strlower=string.lower; gsub=string.gsub
math.mod=math.fmod
GetTime=function() clocks=clocks+1; return now end
gcinfo=function() memoryReads=memoryReads+1; return 100000,150000 end
UnitMana=function() return 1000 end
UnitName=function(unit) return unit=='player' and 'Tester' or nil end
UnitClass=function() return 'Mage','MAGE' end
GetLocale=function() return 'enUS' end
getglobal=function(name) return _G[name] end
AceLibrary=function() return {} end
DEFAULT_CHAT_FRAME={AddMessage=function(self,text) table.insert(messages,text) end}
-- Emulate Lua 5.0's explicit array lengths, not just Lua 5.1's # operator.
local sizes=setmetatable({},{__mode='k'})
local rawgetn=table.getn
table.getn=function(t) return sizes[t] or rawgetn(t) end
table.setn=function(t,n) sizes[t]=n end
table.insert=function(t,a,b)
 local n=table.getn(t); local index,value
 if b==nil then index,value=n+1,a else index,value=a,b end
 for i=n,index,-1 do t[i+1]=t[i] end
 t[index]=value; sizes[t]=n+1
end
table.remove=function(t,index)
 local n=table.getn(t); index=index or n
 if n==0 then return end
 local value=t[index]
 for i=index,n-1 do t[i]=t[i+1]; moves=moves+1 end
 t[n]=nil; sizes[t]=n-1; return value
end
local rawgfind=string.gfind
string.gfind=function(...) iterators=iterators+1; return rawgfind(...) end
function widget(name)
 local w={name=name,alpha=0,height=26,width=26,shown=true,scripts={}}
 function w:GetName() return self.name end
 function w:SetPoint(anchor,x,y) writes=writes+1; self.anchor,self.x,self.y=anchor,x,y end
 function w:SetAlpha(v) writes=writes+1; self.alpha=v end
 function w:SetTextHeight(v) writes=writes+1; self.height=v end
 function w:SetWidth(v) writes=writes+1; self.width=v end
 function w:SetHeight(v) writes=writes+1; self.height=v end
 function w:SetFrameStrata() end
 function w:SetScript(k,fn) self.scripts[k]=fn end
 function w:Hide() self.shown=false end
 function w:Show() self.shown=true end
 function w:IsVisible() return self.shown end
 function w:CreateFontString(name) local f=widget(name); _G[name]=f; return f end
 return w
end
function CreateFrame(kind,name,parent) local f=widget(name); if name then _G[name]=f end; return f end
UIParent=widget('UIParent')
for _,name in ipairs({'MSBTFrameIncoming','MSBTFrameOutgoing','MSBTFrameNotification'}) do
 _G[name]=widget(name)
 for i=1,20 do _G[name..'Text'..i]=widget(name..'Text'..i) end
end
function upvalue(fn,name)
 for i=1,100 do local k,v=debug.getupvalue(fn,i); if k==name then return v end; if not k then break end end
 error('missing upvalue '..name)
end
function copy(t)
 if type(t)~='table' then return t end
 local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
end
MikSBT={}
'''


def runtime(folder):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    for filename in ("MikTableRecyclerObject.lua", "MikCombatEventHelper.lua", "MikScrollingBattleText.lua"):
        source = BASELINE["files"][filename] if folder is None else (folder / filename).read_text(encoding="utf-8-sig")
        lua.compile(source)
        lua.execute(vanilla_loops(source))
    lua.execute('''
    MikSBT.CurrentProfile={TextSpeed=50,FadeDelay=1,UseStickyCrits=true,DisplaySettings={},Suppressions={}}
    MikSBT.DEFAULT_CONFIG={TextSpeed=50}
    for _,name in ipairs({'Incoming','Outgoing','PetIncoming','PetOutgoing','Notification'}) do
     MikSBT.CurrentProfile.DisplaySettings[name]={Show=true,ScrollHeight=200,ScrollDirection=1,AnimationStyle=1}
    end
    MikSBT.SetupAnimationScrollAreas()
    areas=upvalue(MikSBT.DispatchAnimationEvent,'scrollAreas')
    pool=upvalue(MikSBT.MergeEvents,'eventsRecycler')
    MikCEH.Init()
    ''')
    return lua


def plain(value):
    if hasattr(value, "items"):
        return {k: plain(v) for k, v in value.items()}
    return value


old, new = runtime(None), runtime(NEW)

# Parsing: locale argument order, punctuation, numbers, no-capture trailers,
# position captures, multiple captures and misses must produce identical data.
cases = [
    ("%s hits for %d.", "Wolf hits for 142.", ["%n", "%a"]),
    ("%2$s trifft %1$s fuer %3$d.", "Wolf trifft Tester fuer 85.", ["%n", "%s", "%a"]),
    ("(%s) gains %d%%.", "(Tester) gains 10%.", ["%n", "%a"]),
    ("(Glancing)", "Damage (Glancing)", []),
    ("%s fades from you.", "Deterrence fades from you.", ["%b"]),
    ("%s hits for %d.", "does not match", ["%n", "%a"]),
    ("%s %s %s %s %s %s %s %s %s", "a b c d e f g h i", ["%a"]),
]
for i, (fmt, text, order) in enumerate(cases):
    output = []
    for lua in (old, new):
        name = f"FORMAT_{i}"
        lua.globals()[name] = fmt
        result = lua.globals().MikCEH.GetCapturedData(text, name, lua.table_from(order))
        output.append(None if result is None else plain(result))
    assert output[0] == output[1], (fmt, output)
for pattern, text in [("plain", "a plain match"), ("(%a+) (%d+)", "Wolf 42"), ("()hit()", "hit"), ("", "abc"), ("no", "miss"), ("^literal", "a ^literal example"), ("^anchor", "anchor")]:
    old.execute("patternResult=copy(MikCEH.GetUnorderedCaptureDataTable(string.gfind(... )()))", text, pattern)
    new.globals().patternResult = new.globals().copy(new.globals().MikCEH.CapturePattern(text, pattern))
    assert plain(old.globals().patternResult) == plain(new.globals().patternResult), pattern

# Replay an actual parser with partial-action probes; snapshot event tables
# because the parser intentionally reuses them on the next event.
parser_results = []
allocations = []
for lua in (old, new):
    lua.execute('''
    COMBATHITOTHERSELF='%s hits you for %d.'
    BLOCK_TRAILER=' (%d blocked)'; ABSORB_TRAILER=' (%d absorbed)'
    RESIST_TRAILER=' (%d resisted)'; VULNERABLE_TRAILER=' (%d vulnerable)'
    CRUSHING_TRAILER=' (Crushing)'; GLANCING_TRAILER=' (Glancing)'
    captured={}; layouts={}
    local original=MikCEH.GetCapturedData
    MikCEH.GetCapturedData=function(message,name,order) layouts[order]=true; return original(message,name,order) end
    MikSBT.CombatEventsHandler=function(event) captured[#captured+1]=copy(event) end
    for i=1,30 do MikCEH.ParseForIncomingHits('Wolf hits you for 142. (31 blocked)') end
    layoutCount=0; for _ in pairs(layouts) do layoutCount=layoutCount+1 end
    ''')
    parser_results.append(plain(lua.globals().captured))
    allocations.append(lua.globals().layoutCount)
assert parser_results[0] == parser_results[1]
assert allocations[0] > 30 and allocations[1] <= 3, allocations
print(f"PASS: parser output/locales/trailers unchanged; capture-order table identities {allocations[0]} -> {allocations[1]}")

growth = []
for folder in (None, NEW):
    lua = runtime(folder)
    lua.execute('''
    COMBATHITOTHERSELF='%s hits you for %d.'
    BLOCK_TRAILER=' (%d blocked)'; ABSORB_TRAILER=' (%d absorbed)'
    RESIST_TRAILER=' (%d resisted)'; VULNERABLE_TRAILER=' (%d vulnerable)'
    CRUSHING_TRAILER=' (Crushing)'; GLANCING_TRAILER=' (Glancing)'
    MikSBT.CombatEventsHandler=function() end
    for i=1,100 do MikCEH.ParseForIncomingHits('Wolf hits you for 142. (31 blocked)') end
    -- Controlled Lua 5.1 allocation comparison only; production never stops GC.
    collectgarbage('collect'); collectgarbage('stop')
    local before=collectgarbage('count')
    for i=1,5000 do MikCEH.ParseForIncomingHits('Wolf hits you for 142. (31 blocked)') end
    parserGrowth=collectgarbage('count')-before
    collectgarbage('restart')
    ''')
    growth.append(lua.globals().parserGrowth)
assert growth[0] > 500 and growth[1] < growth[0] / 10, growth
print(f"PASS: 5000 incoming-hit allocation replay {growth[0]:.0f} -> {growth[1]:.0f} KB (GC stopped only in mock)")

# Burst merging: include per-target GUIDs, crits, overheals and attack-result
# flags, plus events appended by a resolver during the current merge.
merge_results, shifts, checks = [], [], []
for lua in (old, new):
    lua.execute('''
    local merge={IsOutgoing=true,UnmergedEvents={},MergedEvents={}}
    enabledChecks=0; resolved=0
    MikSBT.RegisterOutgoingNameplateHandler(function() end,function() enabledChecks=enabledChecks+1; return true end,
     function(event)
      resolved=resolved+1
      if resolved==1 then
       table.insert(merge.UnmergedEvents,{EventType='damage',EffectName='late',Name='late',TargetGUID='later',Amount=9})
      end
      return event.resolveGUID
     end)
    for i=1,240 do
     table.insert(merge.UnmergedEvents,{EventType='damage',EffectName=(i%5==0 and 'Multi-Shot' or 'Auto Shot'),
      Name='Mob'..math.mod(i,7),resolveGUID='guid'..math.mod(i,7),ScrollArea=areas.Outgoing,
      Amount=i,IsCrit=(i%3==0),IsGlancing=(i%11==0),IsBlocked=(i%13==0),IsParried=(i%17==0),OverhealAmount=2})
    end
    MikSBT.MSG_MULTIPLE_TARGETS='Multiple'; MikSBT.MSG_HITS='Hits'; MikSBT.MSG_CRITS='Crits'; MikSBT.MSG_CRIT='Crit'
    moves=0; MikSBT.MergeEvents(merge,240)
    mergeOutput={}
    for i,event in ipairs(merge.MergedEvents) do
     mergeOutput[i]={EventType=event.EventType,EffectName=event.EffectName,Name=event.Name,Amount=event.Amount,
      TargetGUID=event.TargetGUID,IsCrit=event.IsCrit,IsGlancing=event.IsGlancing,IsBlocked=event.IsBlocked,
      IsParried=event.IsParried,NumMerged=event.NumMerged,NumCrits=event.NumCrits,OverhealAmount=event.OverhealAmount,
      MergeTrailerText=event.MergeTrailerText}
    end
    mergeOutput.pending=copy(merge.UnmergedEvents)
    assert(table.getn(merge.UnmergedEvents)==1 and merge.UnmergedEvents[1].EffectName=='late')
    ''')
    merge_results.append(plain(lua.globals().mergeOutput))
    shifts.append(lua.globals().moves)
    checks.append(lua.globals().enabledChecks)
assert merge_results[0] == merge_results[1]
assert shifts[0] > 20000 and shifts[1] == 0, shifts
assert checks[1] < checks[0] / 5, checks
print(f"PASS: burst merges/GUIDs/crit/result flags/late events unchanged; queue shifts {shifts[0]} -> {shifts[1]}; integration checks {checks[0]} -> {checks[1]}")

for mode in ("Incoming", "Outgoing", "PetOutgoing"):
    results = []
    for lua in (old, new):
        lua.globals().mode = mode
        lua.execute('''
        MikSBT.RegisterOutgoingNameplateHandler(function() end,function() return true end,function() end)
        local merge={IsOutgoing=(mode~='Incoming'),UnmergedEvents={},MergedEvents={}}
        for i=1,60 do
         local event={ScrollArea=areas[mode],Amount=tostring(i),IsCrit=(i%3==0),PartialEffectText='partial'}
         event.EventType=(i%2==0 and 'MSBT_EVENTTYPE_OUTGOING_HEAL' or 'damage')
         if i%4~=0 then event.EffectName='Spell'..math.mod(i,3) end
         if i%7~=0 then event.Name='Mob'..math.mod(i,4) end
         if i%5~=0 then event.TargetGUID='guid'..math.mod(i,4) end
         if i%6==0 then event.IsBlocked=false end
         table.insert(merge.UnmergedEvents,event)
        end
        MikSBT.MergeEvents(merge,60)
        mixed={}
        for i,event in ipairs(merge.MergedEvents) do
         mixed[i]={EventType=event.EventType,Name=event.Name,EffectName=event.EffectName,
          Amount=event.Amount,TargetGUID=event.TargetGUID,IsCrit=event.IsCrit,IsBlocked=event.IsBlocked,
          NumMerged=event.NumMerged,NumCrits=event.NumCrits,MergeTrailerText=event.MergeTrailerText,
          PartialEffectText=event.PartialEffectText}
        end
        ''')
        results.append(plain(lua.globals().mixed))
    assert results[0] == results[1], mode
print("PASS: incoming/healing/pet merging, unknown GUIDs, missing names/effects, string amounts and nil/false flags preserved")

# Compare every displayed state across fade-in, hold, jitter, fade-out,
# scroll directions/styles, texture replacement and live speed changes.
def animation_trace(lua, sticky, crit, style, direction):
    lua.globals().sticky, lua.globals().crit = sticky, crit
    lua.globals().style, lua.globals().direction = style, direction
    lua.execute('''
    math.randomseed(42); writes=0; clocks=0
    local settings={ScrollHeight=200,AnimationStyle=style,ScrollDirection=direction}
    local area={DisplaySettings=settings}
    local event={ScrollArea=area,IsSticky=sticky,IsCrit=crit}
    local x,y=MikSBT.GetAnimationStartingPosition(event)
    local info={IsActive=true,IsSticky=sticky,IsCrit=crit,FontObject=widget(),Texture=widget(),
      FontSize=26,PositionX=x,PositionY=y,LastUpdated=0,StartTime=0,AnchorPoint='LEFT',Alpha=0,
      ScrollFunction=MikSBT.GetScrollFunction(event)}
    trace={}
    for tick=1,500 do
     now=tick*.01
     if tick==170 then MikSBT.CurrentProfile.TextSpeed=70 end
     if tick==220 then info.Texture=widget() end
     if tick==230 then info.PositionY=info.PositionY+4 end
     if info.IsActive then MikSBT.DoAnimation(info,area) end
     trace[tick]={x=info.PositionX,y=info.PositionY,active=info.IsActive,alpha=info.FontObject.alpha,
       fontX=info.FontObject.x,fontY=info.FontObject.y,anchor=info.FontObject.anchor,
       height=info.FontObject.height,iconAlpha=info.Texture.alpha,iconWidth=info.Texture.width,iconHeight=info.Texture.height}
    end
    MikSBT.CurrentProfile.TextSpeed=50
    ''')
    return plain(lua.globals().trace), lua.globals().writes


steady_writes = None
for sticky, crit in [(True, False), (False, True), (False, False)]:
    for style in (1, 2, 3):
        for direction in (1, 2):
            a, before = animation_trace(old, sticky, crit, style, direction)
            b, after = animation_trace(new, sticky, crit, style, direction)
            assert a == b, (sticky, crit, style, direction)
            if sticky and not crit and style == direction == 1:
                steady_writes = (before, after)
assert steady_writes[1] < steady_writes[0] / 2, steady_writes
print(f"PASS: 18 animation scenarios match every displayed sample; sticky UI writes {steady_writes[0]} -> {steady_writes[1]}")

clock_counts, empty_counts, item_counts = [], [], []
for lua in (old, new):
    lua.execute('''
    local area=areas.Incoming
    for _,info in pairs(area.AnimationDisplayArray) do
     info.IsActive=true; info.IsSticky=false; info.IsCrit=false; info.FontSize=26
     info.PositionX,info.PositionY=0,0; info.LastUpdated=0; info.StartTime=0
     info.AnchorPoint='LEFT'; info.ScrollFunction=MikSBT.ScrollStraightUp
    end
    clocks=0; now=.03; MikSBT.OnUpdateAnimationFrame(MSBTFrameIncoming)
    frameClocks=clocks
    local original=MikSBT.MergeEvents
    emptyMerges=0
    MikSBT.MergeEvents=function(data,count) emptyMerges=emptyMerges+1; return original(data,count) end
    arg1=.31; MikSBT.OnUpdate(); MikSBT.MergeEvents=original
    NUM_BAG_FRAMES=4; MAX_CONTAINER_ITEMS=24; itemReads=0
    GetInventoryItemLink=function() return nil end
    GetContainerNumSlots=function(bag) return bag==0 and 2 or (bag==1 and 1 or 0) end
    GetContainerItemLink=function(bag,slot)
     itemReads=itemReads+1
     if (bag==0 and slot==2) or (bag==1 and slot==1) then return '[Potion]' end
    end
    GetContainerItemInfo=function(bag,slot) return bag==0 and 'first-icon' or 'last-icon',1 end
    assert(MikSBT.FindItemIcon('Potion')=='last-icon')
    ''')
    clock_counts.append(lua.globals().frameClocks)
    empty_counts.append(lua.globals().emptyMerges)
    item_counts.append(lua.globals().itemReads)
    lua.execute('''
    GetContainerNumSlots=nil; itemReads=0
    assert(MikSBT.FindItemIcon('Potion')=='last-icon' and itemReads==120)
    GetInventoryItemLink=function(unit,slot) return slot==16 and '[Sword]' or nil end
    GetInventoryItemTexture=function() return 'equipped-icon' end
    GetInventoryItemCount=function() return 3 end
    local slot,unused,icon,count=MikSBT.FindItemIcon('Sword')
    assert(slot==16 and unused==nil and icon=='equipped-icon' and count==3)
    ''')
assert clock_counts == [40, 1], clock_counts
assert empty_counts == [4, 0], empty_counts
assert item_counts == [120, 3], item_counts
print("PASS: 20-animation frame clocks 40 -> 1; empty merge calls 4 -> 0; bag probes 120 -> 3; legacy/equipped item return shapes preserved")

# Hidden notifications recycle instead of allocating a fresh table each time.
for lua in (old, new):
    lua.execute('''
    pool.PrimaryCache={}; pool.OverflowCache=setmetatable({},{__mode='v'}); pool.OverflowNext=0
    pool.NumNew=0; pool.NumRecycled=0
    for i=1,2000 do
     local event=pool:AcquireTable(); event.ScrollArea=areas.Notification; event.EventSettings={Show=false}
     MikSBT.DispatchAnimationEvent(event)
    end
    ''')
assert old.globals().pool.NumNew == 2000 and new.globals().pool.NumNew == 1
new.execute('''
-- Existing suppression and duplicate mana-gain filters also return ownership
-- exactly once; profile/scroll-area settings themselves must remain intact.
local before=pool.NumReclaimed
local event=pool:AcquireTable()
event.Text='gain'; event.EventType='MSBT_EVENTTYPE_NOTIFICATION_POWER_GAIN'; event.EffectName='Mana'
MikSBT.CurrentProfile.ShowAllManaGains=true
MikSBT.AddAnimation(event)
assert(pool.NumReclaimed==before+1 and next(event)==nil)
MikSBT.CurrentProfile.Suppressions={{Enabled=true,SearchPattern='^hidden$'}}
event=pool:AcquireTable(); event.Text='hidden'
MikSBT.AddAnimation(event)
assert(pool.NumReclaimed==before+2 and next(event)==nil)
assert(MikSBT.CurrentProfile.Suppressions[1].Enabled)
-- Weak overflow holes must neither hide nor overwrite live reusable records.
local recycler=MikTRO:NewRecyclerObject(0)
local a,b,c={tag='a'},{tag='b'},{tag='c'}
recycler:ReclaimTable(a); recycler:ReclaimTable(b); recycler:ReclaimTable(c)
recycler.OverflowCache[1]=nil
local one,two=recycler:AcquireTable(),recycler:AcquireTable()
assert(one~=two and (one==b or one==c) and (two==b or two==c))
assert(not recycler:TablesInOverflow())
assert(recycler.NumRecycled==2)
''')
print("PASS: hidden-event allocations 2000 -> 1; sparse weak recycler preserves distinct reusable tables")
print("All imported MSBT optimization checks passed against the preserved baseline (mocked Lua 5.1 / vanilla array lengths).")
