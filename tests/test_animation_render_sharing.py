"""Compare live movement/geometry/fades against the preserved renderer."""
import ast
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "zDNumbers.lua").read_text(encoding="utf-8-sig")
baseline = ROOT.parent / "_zSuiteMaintenance/combat-render-2026-10-24/before/z_DNumbers/zDNumbers.lua"
tree = ast.parse((ROOT / "tests/test_render_performance.py").read_text())
boot = next(ast.literal_eval(n.value.args[0]) for n in tree.body if isinstance(n, ast.Expr)
            and isinstance(n.value, ast.Call) and isinstance(n.value.func, ast.Attribute)
            and n.value.func.attr == "execute")
boot = boot.replace('clock=0;', 'clock=0;clockReads=0;uiReads=0;boundReads=0;camera=0;movement=0;anchorX=190;anchorY=160;frames={};')
boot = boot.replace('GetTime=function() return clock end', 'GetTime=function() clockReads=clockReads+1;return clock end')
boot = boot.replace('function methods:GetWidth() return self.width end', 'function methods:GetWidth() if self==UIParent then uiReads=uiReads+1 end;return self.width end')
boot = boot.replace('function methods:GetHeight() return self.height end', 'function methods:GetHeight() if self==UIParent then uiReads=uiReads+1 end;return self.height end')
boot = boot.replace('function methods:GetLeft() return 190 end', 'function methods:GetLeft() boundReads=boundReads+1;return anchorX end')
boot = boot.replace('function methods:GetRight() return 310 end', 'function methods:GetRight() boundReads=boundReads+1;return anchorX+120 end')
boot = boot.replace('function methods:GetBottom() return 160 end', 'function methods:GetBottom() boundReads=boundReads+1;return anchorY end')
boot = boot.replace('CreateFrame=function(kind,name,parent) return widget(kind,parent,name) end',
                    'CreateFrame=function(kind,name,parent) local f=widget(kind,parent,name);table.insert(frames,f);return f end')


def runtime(text):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute(boot)
    vm.execute(r'''
local previous=zAPI
function project(x,y,z) return .5+(x-100)*.001+camera,.4+(y-200)*.001+(z-2)*.01,20+(x-100)*.01-z*.1 end
zAPI=function(command,a,b,c)
 if command=="projectUnit" then
  unitProjects=unitProjects+1;if not objects[a] or modelGap then return nil end
  local x,y,z=100+movement,200,2+(b or 0);local sx,sy,d=project(x,y,z)
  if oldDLL then return sx,sy,d end
  return sx,sy,d,x,y,z
 elseif command=="worldToScreen" then worldProjects=worldProjects+1;return project(a,b,c) end
 return previous(command,a,b,c)
end
''')
    vm.execute(text)
    vm.execute(r'''
fire("ADDON_LOADED","z_DNumbers")
for i=1,10 do damage(plates[1].guid,true);damage(plates[2].guid,false) end
active={};for _,f in ipairs(frames) do if f.items and f.items[1] then table.insert(active,f) end end
assert(table.getn(active)==2);tick(.01)
function snapshot()
 local result={}
 for _,f in ipairs(active) do for _,item in ipairs(f.items) do if item.active then
  local point=item.text.SetPointArgs
  table.insert(result,point[4]);table.insert(result,point[5]);table.insert(result,item.text.alpha)
  table.insert(result,item.text.textHeight);table.insert(result,item.perspectiveWarp or 0)
  table.insert(result,item.nativeScreenDepth or 0)
 end end end
 return result
end
''')
    return vm


new = runtime(source)
old = runtime(baseline.read_text(encoding="utf-8-sig")) if baseline.is_file() else None
vms = [old, new] if old else [new]
for vm in vms:
    vm.execute('clockReads,uiReads,boundReads,unitProjects,worldProjects=0,0,0,0,0;tick(.02)')
assert new.globals().clockReads == 1
assert new.globals().uiReads == 4 and new.globals().boundReads == 6
assert new.globals().unitProjects == 2 and new.globals().worldProjects == 20
if old:
    assert old.globals().clockReads == 21
    assert old.globals().uiReads == 40 and old.globals().boundReads == 60
    assert old.globals().unitProjects == 2 and old.globals().worldProjects == 20
    print("PASS 20 numbers / 2 records: clock + dimension + anchor reads 121 -> 11; all 2 base and 20 elevated projections retained")
for i in range(1, 181):
    # Live camera, owner movement, UI resize, alignment and projection gaps.
    script = f'clock={.02+i*.01};camera={i*.0001};movement={i*.02};anchorX={190+i*.1};anchorY={160+i*.02};'
    if i == 40:
        script += 'UIParent.width=1250;UIParent.height=900;zDNumbers.config.align="LEFT";'
    if i == 60:
        script += 'modelGap=true;'
    if i == 65:
        script += 'modelGap=false;'
    if i == 80:
        script += 'oldDLL=true;'
    if i == 85:
        script += 'oldDLL=false;'
    if i == 100:
        script += 'fire("NAME_PLATE_UNIT_REMOVED","nameplate1");objects[plates[1].guid]=nil;'
    if i == 120:
        script += 'zDNumbers.config.align="RIGHT";'
    if i == 140:
        script += 'local previous=zAPI;zAPI=function(a,b,c,d) return previous(a,b,c,d) end;'
    script += 'this=named.zDNumbersEventFrame;this.scripts.OnUpdate()'
    for vm in vms:
        vm.execute(script)
    if old:
        a, b = list(old.globals().snapshot().values()), list(new.globals().snapshot().values())
        assert len(a) == len(b)
        assert all(abs(x-y) < 1e-9 for x, y in zip(a, b)), (i, a, b)
for vm in vms:
    vm.execute('tick(12);clockReads,uiReads,boundReads=0,0,0;tick(12.01);assert(uiReads==0 and boundReads==0)')
print("PASS 180 moving/camera frames match preserved positions, depth, text size, perspective and alpha; resize, alignment, model gaps, older DLL, frozen records, API swap and idle expiry")
