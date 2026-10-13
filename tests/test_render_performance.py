"""Run the actual addon with counted native/UI calls and pooled-frame recycling."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / "zDNumbers.lua").read_text(encoding="utf-8-sig")
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
clock=0; regions=0; writes=0; unitProjects=0; worldProjects=0; warps=0; centers=0; sceneScans=0; worldScans=0
named={}; plates={}; units={}; objects={}
GetTime=function() return clock end
local methods={}
function widget(kind,parent,name)
 local w=setmetatable({kind=kind,parent=parent,name=name,shown=true,alpha=1,width=120,height=80,scale=1,level=0,strata="LOW",scripts={}}, {__index=function(t,k)
  if methods[k] then return methods[k] end
  if string.sub(k,1,3)=="Set" or k=="ClearAllPoints" then
   return function(self,...) writes=writes+1; self[k.."Args"]={...} end
  end
 end})
 if name then named[name]=w end
 return w
end
function methods:RegisterEvent() end
function methods:SetScript(k,f) self.scripts[k]=f end
function methods:GetParent() return self.parent end
function methods:SetParent(p) writes=writes+1; self.parent=p end
function methods:GetName(flag) if flag==1 then return self.guid end return self.name end
function methods:Show() writes=writes+1; self.shown=true end
function methods:Hide() writes=writes+1; self.shown=false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetWidth(v) writes=writes+1; self.width=v end
function methods:SetHeight(v) writes=writes+1; self.height=v end
function methods:SetSize(w,h) writes=writes+1; self.width=w; self.height=h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.scale end
function methods:SetScale(v) writes=writes+1; self.scale=v end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(v) writes=writes+1; self.strata=v end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(v) writes=writes+1; self.level=v end
function methods:GetCenter() centers=centers+1; return 250,200 end
function methods:GetLeft() return 190 end
function methods:GetRight() return 310 end
function methods:GetBottom() return 160 end
function methods:SetAlpha(v) writes=writes+1; self.alpha=v end
function methods:GetAlpha() return self.alpha end
function methods:SetFont(f,s,o) writes=writes+1; self.font=f; self.fontSize=s; self.outline=o end
function methods:GetFont() return self.font,self.fontSize,self.outline end
function methods:SetTextHeight(h) writes=writes+1; self.textHeight=h end
function methods:SetText(t) writes=writes+1; self.text=t end
function methods:GetText() return self.text end
function methods:GetStringHeight() return self.text=="" and 0 or self.textHeight or self.fontSize or 12 end
function methods:GetObjectType() return self.kind end
function methods:CreateTexture() regions=regions+1; return widget("Texture",self) end
function methods:CreateFontString() regions=regions+1; return widget("FontString",self) end
CreateFrame=function(kind,name,parent) return widget(kind,parent,name) end
UIParent=widget("Frame"); UIParent.width=1000; UIParent.height=800
WorldFrame=widget("Frame")
function WorldFrame:GetNumChildren() return #plates end
function WorldFrame:GetChildren() worldScans=worldScans+1; return unpack(plates) end
function add(i,guid)
 local b=widget("Button"); b.guid=guid or string.format("0x%08X",i); b.unit="nameplate"..i
 local n=widget("FontString",b); n.text="Mob"..i
 local h=widget("StatusBar",b); h.height=8
 b.nameplate={health=h,name=n,unit=b.unit}; plates[i]=b
 units[b.unit]=b; objects[b.guid]=b
 return b
end
UnitExists=function(u) return units[u]~=nil or objects[u]~=nil end
UnitGUID=function(u) local b=units[u] or objects[u]; return b and b.guid end
UnitName=function(u) local b=units[u] or objects[u]; return b and b.nameplate.name.text end
C_NamePlate={GetNamePlates=function() sceneScans=sceneScans+1; return plates end,GetNamePlateForUnit=function(u) return units[u] or objects[u] end}
zAPI=function(command,guid,offset,z)
 if command=="fontTrapezoid" then warps=warps+1; return 1 end
 if command=="projectUnit" then
  unitProjects=unitProjects+1
  if not objects[guid] then return nil end
  return .5,.4+(offset or 0)*.01,20,100,200,2+(offset or 0)
 end
 assert(command=="worldToScreen"); worldProjects=worldProjects+1
 return .5,.4+(z-2)*.01,20
end
MikSBT={CurrentProfile={TextSpeed=50},PrepareExternalAnimationEvent=function() return true end,
 GetFontSize=function(a,s,crit) return crit and 24 or 12 end,GetFontPath=function() return "font.ttf" end,GetFontOutline=function() return "OUTLINE" end,
 RegisterOutgoingNameplateHandler=function(f) outgoing=f end}
zDNumbers={EnsureEmbeddedMSBT=function() end}
zDNumbersDB={height="250"}
for i=1,50 do add(i) end
function fire(e,a) event=e; arg1=a; this=named.zDNumbersEventFrame; this.scripts.OnEvent() end
function tick(t) clock=t; this=named.zDNumbersEventFrame; this.scripts.OnUpdate() end
function damage(guid,result)
 outgoing({TargetGUID=guid,Name=UnitName(guid),Amount=100,Text="100",Texture="source.blp",IsBlocked=result,
  ScrollArea={},EventSettings={FontSettings={Color={r=1,g=1,b=1}}}})
end
''')
lua.execute(source)
lua.execute('''
fire("ADDON_LOADED","z_DNumbers")
assert(zDNumbers.GetAttachedCount()==50)
assert(regions==0) -- Empty/idle mobs do not allocate a ten-slot pool.
centers=0; tick(.1); assert(centers==0) -- Nor do they run animation position tracking.
damage(plates[1].guid,true)
assert(regions==11) -- One text + two icons + four rounded strips per icon.
tick(.11)
for i=2,10 do damage(plates[1].guid,true) end
local beforeUnit,beforeWorld,beforeWarp=unitProjects,worldProjects,warps
tick(.12)
-- All ten numbers share one unit resolution; each elevated world point still
-- gets a live projection against the player's camera.
assert(unitProjects-beforeUnit<=2)
assert(worldProjects-beforeWorld==10)
local steadyWrites,steadyWarps=writes,warps
beforeUnit,beforeWorld=unitProjects,worldProjects
for i=1,10 do tick(.12+i*.01) end
assert(unitProjects-beforeUnit==10 and worldProjects-beforeWorld==100)
assert(warps-steadyWarps==0) -- No repeated restore/re-warp with unchanged size.
assert(writes-steadyWrites<=110) -- Ten moving points, not ten rounded-icon rebuilds.
-- Live icon settings, alignment, and opacity still change existing numbers.
zDNumbers.config.icon_opacity="70"; zDNumbers.config.align="LEFT"; tick(.23)
local before=regions; zDNumbers.config.icons="0"; tick(.24)
zDNumbers.config.icons="1"; tick(.25); assert(regions==before)
-- Death freezes the outgoing record. Reusing its native frame for another
-- GUID must not reassign old numbers, including when GUIDs stay resolvable.
local oldGuid=plates[1].guid
fire("NAME_PLATE_UNIT_REMOVED","nameplate1")
objects[oldGuid]=nil; plates[1].guid="0xDEADBEEF"; objects[plates[1].guid]=plates[1]
fire("NAME_PLATE_UNIT_ADDED","nameplate1")
beforeUnit,beforeWorld=unitProjects,worldProjects; tick(.26)
assert(unitProjects==beforeUnit and worldProjects>beforeWorld)
damage(plates[1].guid,true); tick(.27)
assert(unitProjects>beforeUnit)
for i=1,90 do tick(.27+i*.1) end
centers=0; tick(10); assert(centers==0 and zDNumbers.GetAttachedCount()==50)
-- A world-only legacy plate remains supported even alongside the modern API.
legacy=add(51,"0xCAFEBABE"); units.nameplate51=nil
local all=plates
C_NamePlate.GetNamePlates=function() local list={} for i=1,50 do list[i]=all[i] end return list end
damage(legacy.guid,false); tick(10.01)
assert(zDNumbers.GetAttachedCount()==51)
-- With no modern provider, the ordinary WorldFrame scan still finds plates.
C_NamePlate=nil; legacy2=add(52,"0xBEEFBEEF"); units.nameplate52=nil
clock=10.02; damage(legacy2.guid,false)
assert(zDNumbers.GetAttachedCount()==52)
-- A disabled renderer clears active work, and native projection is optional.
zDNumbers.config.enabled="0"; tick(10.03)
centers=0; tick(10.04); assert(centers==0)
zDNumbers.config.enabled="1"; zAPI=nil
clock=10.05; damage(legacy2.guid,false); tick(10.06)
tick(16); centers=0; tick(16.01); assert(centers==0)
''')
print("zDNumbers: idle pools/updates eliminated; 10 numbers use 1 unit + 10 world projections/frame; rounded icons/warp stay cached; death/recycling and mixed legacy hosts pass.")
