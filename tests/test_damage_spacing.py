"""Close-packed damage spacing eases pushes without altering natural travel."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root=Path(__file__).resolve().parents[1]
source=(root/"zDNumbers.lua").read_text(encoding="utf-8-sig")
lua=LuaRuntime(unpack_returned_tuples=True)
lua.compile(source,name="zDNumbers.lua")
helper=source[source.index("local function ResolveAnimationSpacing("):source.index("local function UpdateAnimations(")]
lua.execute('''
TEXT_SLOTS=10
Z={config={split_pet="0"}}
RetireAnimationItem=function(item) item.active=nil end
function item(y,h,order)
  return {active=true,position=y,fontSize=h,stackOffset=0,displayPosition=y,spawnSequence=order,
    text={GetStringHeight=function() return h end}}
end
function frame(items)
  for i=#items+1,10 do items[i]={} end
  return {items=items}
end
''')
lua.execute(helper+'''
-- New item does not add a full font-size-plus-eight shove to the old entry.
old=item(3,12,1); newest=item(0,12,2); f=frame({old,newest})
ResolveAnimationSpacing(f,200,1/60)
assert(old.position==3 and newest.position==0)
assert(old.stackTarget==14) -- Actual lower glyph height plus only 2 pixels.
assert(old.displayPosition>3 and old.displayPosition<6)
for i=1,60 do ResolveAnimationSpacing(f,200,1/60) end
assert(math.abs(old.displayPosition-14)<.001)

-- Mixed crit/normal sizes use the lower entry's height, not their average.
crit=item(0,24,3); normal=item(1,10,2); above=item(2,12,1)
f=frame({above,normal,crit}); ResolveAnimationSpacing(f,200,1/60)
assert(normal.stackTarget==26 and above.stackTarget==38)

-- Simultaneous events have deterministic newest-at-bottom ordering.
a=item(0,10,1); b=item(0,10,2); c=item(0,10,3)
f=frame({a,b,c}); ResolveAnimationSpacing(f,200,1/60)
assert(c.stackTarget==0 and b.stackTarget==12 and a.stackTarget==24)

-- Icon-only blocks/parries reserve their icon footprint.
c.text.GetStringHeight=function() return 0 end
c.result={icon={IsShown=function() return true end,GetHeight=function() return 8 end}}
ResolveAnimationSpacing(f,200,1/60); assert(b.stackTarget==10)

-- A gap disappearing does not send text backwards.
local previous=a.displayPosition
b.active=nil; c.active=nil
a.position=1; ResolveAnimationSpacing(f,200,1/60)
assert(a.displayPosition>=previous)

-- Crowded entries retire only after easing to the boundary, not on a large
-- desired position that has not actually reached the edge yet.
a=item(2,12,1); b=item(0,12,2); f=frame({a,b})
ResolveAnimationSpacing(f,10,1/60)
assert(a.active and a.displayPosition<10 and a.stackTarget==14)
for i=1,30 do ResolveAnimationSpacing(f,10,1/60) end
assert(not a.active)

-- Equal wall-clock durations behave the same at different frame rates.
function sample(dt,count)
  local low=item(0,12,2); local high=item(3,12,1)
  local f=frame({high,low})
  for i=1,count do ResolveAnimationSpacing(f,200,dt) end
  return high.displayPosition
end
assert(math.abs(sample(1/30,6)-sample(1/120,24))<.00001)
''')
assert "local spacing = size + 8" not in source
assert "item.displayPosition or item.position" in source
print("Damage-spacing smoothing, tight gaps, mixed sizes, ordering, and frame-rate tests passed.")
