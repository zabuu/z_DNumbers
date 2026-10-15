"""Verify rendered per-number interleaving, local collisions and pool reuse."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]

def execute_strings(filename):
    tree = ast.parse((root / "tests" / filename).read_text(encoding="utf-8-sig"))
    return [ast.literal_eval(n.value.args[0]) for n in tree.body
            if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
            and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == "execute"
            and isinstance(n.value.args[0], ast.Constant)]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(execute_strings("test_render_performance.py")[0])
lua.execute(execute_strings("test_pet_stream.py")[0])
lua.execute(execute_strings("test_pet_yaw.py")[0])
lua.execute((root / "zDNumbers.lua").read_text(encoding="utf-8-sig"))
lua.execute('''
fire("ADDON_LOADED","z_DNumbers")
zDNumbers.config.split_pet="1"; zDNumbers.config.height="142"; zDNumbers.Refresh()
function assertPetPairs(f)
 for _,a in pairs(f.items) do if a.active and a.isPet then
  for _,b in pairs(f.items) do if b.active and b.isPet and a~=b then
   local al,ar,ab,at=rect(a); local bl,br,bb,bt=rect(b)
   assert(ar+1.9<=bl or al>=br+1.9 or at+1.9<=bb or ab>=bt+1.9)
  end end
 end end
end
-- Paired hits must occupy alternating rendered rows, including real gaps
-- inside the main stack: clearing its outer bounding box cannot pass this.
petWX,petWY=100,210
for i=1,3 do emit(plates[1].guid,false); emit(plates[1].guid,true) end
for i=1,35 do step() end
local f=record(1); assert(f.petZipper and active(f,false)==3 and active(f,true)==3)
checkOrbit(f); assertPetPairs(f)
local ordered={}
for _,item in pairs(f.items) do if item.active then table.insert(ordered,item) end end
table.sort(ordered,function(a,b) return a.text.SetPointArgs[5]<b.text.SetPointArgs[5] end)
for i=2,#ordered do assert(ordered[i].isPet~=ordered[i-1].isPet,"Rendered rows did not alternate") end
local inside=0
for _,item in pairs(f.items) do if item.active and item.isPet then
 local y=item.text.SetPointArgs[5]; local below,above
 for _,main in pairs(f.items) do if main.active and not main.isPet then
  local my=main.text.SetPointArgs[5]; if my<y then below=true elseif my>y then above=true end
 end end
 if below and above then inside=inside+1 end
 assert(math.abs(item.petOffsetY)<20,"A pet number was pushed past the whole main stack")
end end
assert(inside>=2,"Pet numbers did not weave inside the regular stack")
-- Adding another hit keeps per-source order/spacing and readable footprints.
emit(plates[1].guid,false,true,"9999",true); emit(plates[1].guid,true)
for i=1,12 do step(); checkOrbit(f); assertPetPairs(f) end
-- A side-facing pet keeps independent vertical lanes. A very wide crit in a
-- different row cannot inflate the offset of a new ordinary pet hit.
clear(); petWX,petWY=110,200
emit(plates[1].guid,false,true,"123456789",true); emit(plates[1].guid,true)
local highPet=first(f,true)
for i=1,40 do step() end
emit(plates[1].guid,false); emit(plates[1].guid,true)
step(); assert(not f.petZipper); checkOrbit(f); assertPetPairs(f)
local lowPet
for _,item in pairs(f.items) do if item.active and item.isPet and item~=highPet then lowPet=item end end
assert(lowPet and lowPet.petOffsetX<50)
assert(highPet.petOffsetX>lowPet.petOffsetX+40,"Crit width shifted both pet rows together")
assert(highPet.petOrbitRadius~=lowPet.petOrbitRadius)
-- Turning back to the shared column still clears individual mixed-size rows.
petWX,petWY=100,210
for i=1,30 do step(); checkOrbit(f); assertPetPairs(f) end
assert(f.petZipper)
-- Source bursts preserve independent capacities; crowded zipper slots retire
-- normally at the configured height instead of drawing text on top of text.
clear(); emit(plates[1].guid,false)
for i=1,25 do emit(plates[1].guid,true,i%2==0,tostring(10000+i),true) end
assert(active(f,false)==1 and active(f,true)==10)
for i=1,10 do step(); checkOrbit(f); assertPetPairs(f) end
-- New/recycled entries cannot inherit an old radius or flash before placement.
clear(); petWX,petWY=110,200
emit(plates[1].guid,true)
local reused=first(f,true); assert(reused.petOrbitRadius==nil and not reused.text:IsShown())
step(); assert(reused.text:IsShown() and reused.petPlacedTime==clock)
checkOrbit(f)
-- Opt-out restores the combined stream and stops all pet world-position work.
zDNumbers.config.split_pet="0"
local beforePet=petPositions; step(); assert(not f.petZipper and petPositions==beforePet)
''')
print("Pet zipper: alternating rendered rows inside the main stack, per-hit crit displacement, clear pet/player/icon footprints, smooth turns, independent burst pools, radius reset and opt-out passed.")
