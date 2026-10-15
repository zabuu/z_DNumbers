"""Run the actual renderer against a perspective camera and level pet orbit."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
source = (root / "zDNumbers.lua").read_text(encoding="utf-8-sig")
performance_tree = ast.parse((root / "tests/test_render_performance.py").read_text(encoding="utf-8-sig"))
bootstrap = next(ast.literal_eval(n.value.args[0]) for n in performance_tree.body
                 if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
                 and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == "execute")
pet_tree = ast.parse((root / "tests/test_pet_stream.py").read_text(encoding="utf-8-sig"))
helpers = next(ast.literal_eval(n.value.args[0]) for n in pet_tree.body
               if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
               and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == "execute"
               and isinstance(n.value.args[0], ast.Constant))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(bootstrap)
lua.execute(helpers)
lua.execute('''
petWX=110; petWY=200; petWZ=2; petPositions=0; petScreenProjects=0
cameraYaw=0; cameraPitch=math.atan(.5); cameraDistance=22
cameraSide=0; cameraUp=0
local previousAPI=zAPI
function project(x,y,z)
 x,y,z=x-100,y-200,z-2
 local cy,sy=math.cos(cameraYaw),math.sin(cameraYaw)
 local cp,sp=math.cos(cameraPitch),math.sin(cameraPitch)
 local depth=cameraDistance-x*sy*cp+y*cy*cp-z*sp
 if depth<=.001 then return end
 return .5+(x*cy+y*sy+cameraSide)/depth,.4+(-x*sy*sp+y*cy*sp+z*cp+cameraUp)/depth,depth
end
zAPI=function(command,a,b,c)
 if command=="unitPosition" and a=="pet" then
  petPositions=petPositions+1; return petWX,petWY,petWZ,1
 elseif command=="projectUnit" then
  unitProjects=unitProjects+1
  if a=="pet" then petScreenProjects=petScreenProjects+1; return project(petWX,petWY,petWZ) end
  if not objects[a] then return end
  local x,y,d=project(100,200,2+(b or 0)); return x,y,d,100,200,2+(b or 0)
 elseif command=="worldToScreen" then
  worldProjects=worldProjects+1; return project(a,b,c)
 end
 return previousAPI(command,a,b,c)
end
function approx(a,b) assert(a and b and math.abs(a-b)<.000001,tostring(a).." != "..tostring(b)) end
function checkOrbit(f)
 local pet=first(f,true); assert(pet)
 -- Compare every rendered pet point to an independent world projection:
 -- horizontal displacement, unchanged world elevation/rise, readable text.
 for _,item in pairs(f.items) do if item.active and item.isPet then
  local p=item.text.SetPointArgs
  if item.petOrbitNative then
   approx(item.petOrbitWorldZ,item.nativeBaseZ)
   local x,y,d=project(item.petOrbitWorldX,item.petOrbitWorldY,
    item.petOrbitWorldZ+item.nativePointZ-item.nativeBaseZ)
   approx(p[4],x*1000+item.nativeCorrectionX)
   approx(p[5],y*800+item.nativeCorrectionY)
  else
   assert(item.petOffsetX==item.petOffsetX and item.petOffsetY==item.petOffsetY)
  end
 end end
 assertSeparate(f)
end
function spawn(yaw,height)
 clear(); petWX,petWY=100+10*math.cos(yaw),200+10*math.sin(yaw); petWZ=height or 2
 emit(plates[1].guid,false); emit(plates[1].guid,true); step()
 local f=record(1); checkOrbit(f)
 approx(math.cos(f.petStreamYaw),math.cos(yaw)); approx(math.sin(f.petStreamYaw),math.sin(yaw))
 return f
end
''')
lua.execute(source)
lua.execute('''
fire("ADDON_LOADED","z_DNumbers"); zDNumbers.config.split_pet="1"
-- Complete horizontal rotation at several camera yaw/pitch angles. Height
-- changes are deliberately extreme to catch any accidental pet-Z dependency.
for _,pitch in ipairs({.12,math.atan(.5),1.1}) do
 cameraPitch=pitch
 for _,camera in ipairs({0,.7,2.4}) do
  cameraYaw=camera
  for i=0,15 do
   local yaw=i*math.pi/8
   local f=spawn(yaw,-100); local x,y=f.petStreamOffset,f.petStreamOffsetY
   f=spawn(yaw,200); approx(f.petStreamOffset,x); approx(f.petStreamOffsetY,y)
  end
 end
end
cameraYaw=0; cameraPitch=math.atan(.5)
local f=spawn(0)
-- Changing the age/width/size of regular hits cannot spin the starting center.
emit(plates[1].guid,false,true,"123456789",true); step(); checkOrbit(f); approx(f.petStreamYaw,0)
-- Dense pet bursts, all alignments, result/source icons and inherited scales.
for _,alignment in ipairs({"LEFT","CENTER","RIGHT"}) do
 clear(); zDNumbers.config.align=alignment
 emit(plates[1].guid,false,true,"123456789",true)
 for i=1,8 do emit(plates[1].guid,true,i%2==0,tostring(10000+i),true) end
 for i=1,12 do step(); checkOrbit(f) end
end
f:SetScale(.7); UIParent.scale=.8; step(); checkOrbit(f)
f:SetScale(1); UIParent.scale=1; zDNumbers.config.align="CENTER"
-- Off-center targets lean as text rises: all projected pet points must still
-- clear main glyphs when that leaning changes a point's displacement direction.
for _,pitch in ipairs({.05,math.atan(.5),1.1}) do
 cameraPitch=pitch
 for _,side in ipairs({-10,10}) do
  cameraSide=side; cameraUp=4
  for i=0,15 do
   f=spawn(i*math.pi/8)
   for j=1,7 do
    emit(plates[1].guid,false,j%2==0,tostring(10000+j),true)
    emit(plates[1].guid,true,j%2==0,tostring(10000+j),true)
   end
   for j=1,20 do step(); checkOrbit(f) end
  end
 end
end
cameraSide=0; cameraUp=0; cameraPitch=math.atan(.5)
-- The world yaw eases through a turn; camera rotation reprojects that same
-- plane immediately rather than interpolating a stale screen-space bearing.
f=spawn(0); petWX,petWY=90,200
step(); assert(f.petStreamYaw>0 and f.petStreamYaw<1); checkOrbit(f)
for i=1,30 do step(); checkOrbit(f) end
local yaw=f.petStreamYaw; cameraYaw=cameraYaw+.8; step(); checkOrbit(f)
assert(math.abs(f.petStreamYaw-yaw)<.02)
-- Tiny XY jitter and missing pets retain the remembered world direction.
petWX,petWY=100.01,200.01; yaw=f.petStreamYaw; petWZ=500
step(); approx(f.petStreamYaw,yaw); checkOrbit(f)
petAvailable=false; step(); approx(f.petStreamYaw,yaw); checkOrbit(f)
petAvailable=true
-- A pet behind the camera still has usable world XY; no pet screen lookup.
cameraYaw=0; f=spawn(-math.pi/2); petWX,petWY,petWZ=100,-1000,500
step(); checkOrbit(f); approx(f.petStreamYaw,-math.pi/2); assert(petScreenProjects==0)
-- Shortest yaw wrap around +/-pi, with no full-circle jump.
f=spawn(math.pi-.01); petWX,petWY=100+10*math.cos(-math.pi+.01),200+10*math.sin(-math.pi+.01)
step(); assert(f.petStreamYaw>math.pi-.02); checkOrbit(f)
-- Five plates share one pet XY read; each adds just one world probe to the
-- ordinary one-projection-per-number rendering cost. Steady layout is pooled.
clear(); cameraPitch=0; petWX,petWY=110,200
for i=2,6 do emit(plates[i].guid,false); emit(plates[i].guid,true) end
local beforePet,beforeUnit,beforeWorld,beforeRegions=petPositions,unitProjects,worldProjects,regions
step(); assert(petPositions-beforePet==1 and unitProjects-beforeUnit==5 and worldProjects-beforeWorld==15)
for i=2,6 do checkOrbit(record(i)) end
local beforeWrites,beforeWarps=writes,warps
step(); assert(regions==beforeRegions and warps==beforeWarps and writes-beforeWrites==10)
-- Frozen/recycled anchors keep yaw and shared elevation; no old unit/pet lookup.
clear(); cameraPitch=math.atan(.5); f=spawn(.6); local yaw=f.petStreamYaw; local guid=plates[1].guid
fire("NAME_PLATE_UNIT_REMOVED","nameplate1"); objects[guid]=nil
petWX,petWY=90,200; beforePet,beforeUnit=petPositions,unitProjects
step(); checkOrbit(f); approx(f.petStreamYaw,yaw)
assert(petPositions==beforePet and unitProjects==beforeUnit)
-- A collapsed edge-on view safely uses a level lane, never invalid points.
clear(); cameraPitch=0; cameraYaw=0
emit(plates[2].guid,false); emit(plates[2].guid,true); step()
assertSeparate(record(2))
''')
print("Pet orbit: shared starting elevation, 360-degree world yaw, height independence, live camera perspective, exact projected rising points, clear text/icons, smooth turns/wrap, off-screen pet, one XY read/frame + one probe/plate, pooled rendering and frozen anchors passed.")
