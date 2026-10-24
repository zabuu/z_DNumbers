"""Compile production LOS batching and compare rays with retained UnitXP source."""
import ast
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/zAPI/src"
source = (NATIVE / "zAPI.cpp").read_text(encoding="utf-8-sig")
reference = ROOT / "native_reference/UnitXP_SP3"


def function(text, marker):
    start = text.index(marker)
    brace = text.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end] + "\n"


# Reuse only the fake Lua table/stack ABI declarations, not that test's runner.
tree = ast.parse((ROOT / "tests/test_native_projection_batch.py").read_text())
prefix = next(ast.literal_eval(n.value) for n in tree.body
              if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "prefix" for t in n.targets))
prefix += '#include <type_traits>\n#include <limits>\n'
prefix += (NATIVE / "ReadableRegionCache.h").read_text()
prefix += function(source, "bool IsReadable(")
prefix += source[source.index("struct Vec3 {"):source.index("using LuaCFunction")]
prefix += r'''
using C3Vector=Vec3;
using LuaLGetNFn=int(__fastcall *)(void *,int);
using LuaLSetNFn=void(__fastcall *)(void *,int,int);
using LuaSetTopFn=void(__fastcall *)(void *,int);
using FrameScriptPushObjectFn=void(__fastcall *)(void *,int,int);
using IntersectFn=char(__fastcall *)(const Vec3 *,const Vec3 *,int,Vec3 *,float *,uint32_t);
constexpr uintptr_t kLuaLGetN=1,kLuaLSetN=2,kLuaSetTop=3,kFrameScriptPushObject=4,kCWorldIntersect=5,kInWorld=6;
uint8_t worldReady=1; double fakeNow=0; uint64_t playerGuid=777;
int sourceReads=0,targetReads=0,sourceResolves=0; bool reenter=false,fault=false;
struct Ray { Vec3 a,b; uint32_t flags; };
std::vector<Ray> rays;
bool hits=false; float hitAt=.5f; bool secondClear=false;
char __fastcall Intersect(const Vec3 *a,const Vec3 *b,int,Vec3 *,float *t,uint32_t flags) {
  assert(flags==0x100111); rays.push_back({*a,*b,flags});
  if(fault) RaiseException(EXCEPTION_ACCESS_VIOLATION,0,0,nullptr);
  *t=hitAt; return hits && !(secondClear && a->z!=b->z);
}
template<typename T> T At(uintptr_t key) {
  uintptr_t p=0;
  switch(key) {
    case 1:p=reinterpret_cast<uintptr_t>(&GetN);break;
    case 2:p=reinterpret_cast<uintptr_t>(&SetN);break;
    case 3:p=reinterpret_cast<uintptr_t>(&SetTop);break;
    case 4:p=reinterpret_cast<uintptr_t>(&RawGetI);break;
    case 5:p=reinterpret_cast<uintptr_t>(&Intersect);break;
    case 6:p=reinterpret_cast<uintptr_t>(&worldReady);break;
    default:assert(false);
  }
  if constexpr(std::is_pointer<T>::value) return reinterpret_cast<T>(p);
  else return static_cast<T>(p);
}
struct Fixture {
  uint8_t unit[0x11C]{},movement[0xB8]{}; Vec3 pos{20,0,0}; bool present=true;
  Fixture(float height=2) {
    *reinterpret_cast<uint32_t *>(unit+0x118)=reinterpret_cast<uint32_t>(movement);
    *reinterpret_cast<float *>(movement+0xB4)=height;
  }
  uint32_t address() { return reinterpret_cast<uint32_t>(unit); }
};
std::map<uint64_t,Fixture *> fixtures;
uint64_t ResolveGuid(const char *s) { return std::strcmp(s,"player")==0?playerGuid:std::strtoull(s+2,nullptr,16); }
bool ResolveUnit(const char *s,uint32_t &unit) {
  const auto id=ResolveGuid(s); if(std::strcmp(s,"player")==0) ++sourceResolves;
  auto it=fixtures.find(id); if(it==fixtures.end() || !it->second->present) return false;
  unit=it->second->address(); return true;
}
bool UnitPosition(uint32_t u,Vec3 &p) {
  for(const auto &it:fixtures) if(it.second->address()==u) {
    if(it.first==playerGuid) ++sourceReads; else ++targetReads;
    p=it.second->pos; return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);
  }
  return false;
}
float vanilla1121_unitCollisionBoxHeight(uint32_t u) {
  auto m=*reinterpret_cast<uint32_t *>(u+0x118); return *reinterpret_cast<float *>(m+0xB4);
}
C3Vector vanilla1121_unitPosition(uint32_t u) { C3Vector p{}; assert(UnitPosition(u,p)); return p; }
float UnitXP_distanceBetween(const C3Vector &a,const C3Vector &b) {
  return std::sqrt((a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)+(a.z-b.z)*(a.z-b.z));
}
void perfSetSlotName(int,const std::string &) {} void perfMarkStart(int) {} void perfMarkEnd(int) {}
auto p_CWorld_Intersect=&Intersect;
'''
prefix += function((reference / "Vanilla1121_functions.cpp").read_text(encoding="utf-8-sig"), "bool CWorld_Intersect(").replace(
    "uint32_t intersectFlag)", "uint32_t intersectFlag = 0x100111)")
prefix += function((reference / "Vanilla1121_functions.cpp").read_text(encoding="utf-8-sig"), "bool vanilla1121_unitInLineOfSight(")
prefix += function((NATIVE / "NameplateBatch.h").read_text(), "bool IsBatchGuid(")
body = (NATIVE / "NameplateSight.h").read_text()
body = body.replace(function(body, "double NameplateSightMilliseconds("),
                    "double NameplateSightMilliseconds() { return fakeNow; }\n")
tests = r'''
std::string guid(int n) { char b[19]; std::snprintf(b,sizeof(b),"0x%016llX",uint64_t(n)); return b; }
void fill(FakeLua &l,int n) {
  l.input->array.clear(); for(int i=1;i<=n;++i) l.input->array[i]=Value::Str(guid(i));
  l.input->length=n; l.reset(n);
}
void LuaRawSetI(void *p,int index,int key) {
  assert(!g_readableRegionCache);
  auto &l=*static_cast<FakeLua *>(p); auto t=slot(p,index).table;
  Value value=l.stack.back(); l.stack.pop_back();
  if(reenter) {
    reenter=false; FakeLua nested; fill(nested,2); assert(DoNameplateSightInto(&nested)==1);
    assert(nested.stack.back().number==2);
  }
  if(value.type==0) t->array.erase(key); else t->array[key]=value;
}
void check(FakeLua &l,int n) {
  assert(DoNameplateSightInto(&l)==1 && l.stack.back().type==3 && l.stack.back().number==n);
  assert(l.output->length==n && l.output->array.size()==size_t(n));
}
void rejected(FakeLua &l) {
  auto size=l.output->array.size(); auto length=l.output->length;
  assert(DoNameplateSightInto(&l)==1 && l.stack.back().type==0);
  assert(l.output->array.size()==size && l.output->length==length);
}
int main() {
  Fixture player; fixtures[playerGuid]=&player; player.pos={0,0,0};
  std::vector<std::unique_ptr<Fixture>> owned;
  for(int i=1;i<=512;++i) { owned.emplace_back(new Fixture(float(1+i%4))); fixtures[i]=owned.back().get(); }
  // Compare actual legacy and production geometry, including both ray paths,
  // swapped heights, endpoint/out-of-segment hits, near-identical points and
  // the >150 yard guard. Also compare every ray endpoint and query mask.
  int cases=0;
  for(float h1:{0.f,1.f,2.f,4.f}) for(float h2:{0.f,1.f,2.f,4.f})
   for(float distance:{0.f,.00000001f,20.f,150.f,151.f})
    for(float t:{-.1f,0.f,.5f,1.f,1.1f}) for(bool hit:{false,true}) for(bool upper:{false,true}) {
      *reinterpret_cast<float *>(player.movement+0xB4)=h1;
      auto &target=*fixtures[1]; *reinterpret_cast<float *>(target.movement+0xB4)=h2; target.pos={distance,0,0};
      hits=hit; hitAt=t; secondClear=upper; rays.clear();
      const bool expected=vanilla1121_unitInLineOfSight(player.address(),target.address());
      auto expectedRays=rays; rays.clear(); NameplateSightUnit a{},b{};
      assert(ReadNameplateSightUnit(player.address(),a)&&ReadNameplateSightUnit(target.address(),b));
      assert(TestNameplateSight(a,b)==int(expected)); assert(rays.size()==expectedRays.size());
      for(size_t i=0;i<rays.size();++i) {
        assert(std::memcmp(&rays[i].a,&expectedRays[i].a,sizeof(Vec3))==0);
        assert(std::memcmp(&rays[i].b,&expectedRays[i].b,sizeof(Vec3))==0);
        assert(rays[i].flags==expectedRays[i].flags);
      }
      ++cases;
    }
  *reinterpret_cast<float *>(player.movement+0xB4)=2;
  fixtures[1]->pos={20,0,0}; hits=false; secondClear=false; hitAt=.5f;
  FakeLua l; fill(l,50); sourceReads=targetReads=sourceResolves=0; rays.clear(); check(l,50);
  assert(sourceReads==1 && sourceResolves==1 && targetReads==50 && rays.size()==50);
  for(const auto &v:l.output->array) assert(v.second.number==1);
  auto growth=g_nameplateSightGrowths; auto cap=g_nameplateSightScratch.capacity();
  fakeNow=99; l.reset(50); sourceReads=targetReads=0; rays.clear(); check(l,50);
  assert(sourceReads==1 && targetReads==0 && rays.empty() && g_nameplateSightHits>=50);
  // Expiry (100..160ms) refreshes blocked/clear transitions; source identity
  // changes invalidate even an unexpired result. Missing targets never hit.
  fakeNow=161; hits=true; l.reset(50); rays.clear(); check(l,50); assert(!rays.empty());
  assert(l.output->array.at(1).number==0);
  fixtures[1]->present=false; l.reset(50); check(l,50); assert(l.output->array.at(1).number==-1);
  fixtures[1]->present=true;
  fixtures.erase(playerGuid); playerGuid=778; fixtures[playerGuid]=&player;
  hits=false; l.reset(50); sourceReads=targetReads=0; check(l,50); assert(targetReads==50);
  assert(l.output->array.at(1).number==1);
  // Faults/invalid movement are unknown, never a fabricated clear/blocked ray.
  fakeNow=1000; fault=true; l.reset(50); check(l,50); assert(l.output->array.at(1).number==-1); fault=false;
  auto movement=*reinterpret_cast<uint32_t *>(fixtures[1]->unit+0x118);
  *reinterpret_cast<uint32_t *>(fixtures[1]->unit+0x118)=0;
  l.reset(50); check(l,50); assert(l.output->array.at(1).number==-1);
  *reinterpret_cast<uint32_t *>(fixtures[1]->unit+0x118)=movement;
  l.input->array[1]=Value::Str("target"); l.input->array[2]=Value::Num(1); l.input->array.erase(3);
  l.reset(50); check(l,50); for(int i=1;i<=3;++i) assert(l.output->array.at(i).number==-1);
  worldReady=0; l.reset(50); rejected(l); worldReady=1;
  for(double n:{-1.0,513.0,.5,HUGE_VAL,std::nan("")}) { l.reset(n); rejected(l); }
  l.reset(50); l.stack[1]=Value::Num(0); rejected(l);
  l.reset(50); l.stack[2]=Value::Str("50"); rejected(l);
  l.output->length=513; l.reset(50); rejected(l); l.output->length=50;
  // Clear/resize/aliased tables and output reentry retain private snapshots.
  fill(l,50); reenter=true; check(l,50);
  fill(l,512); check(l,512); assert(g_nameplateSightScratch.capacity()<=512);
  fill(l,1); check(l,1); worldReady=0; fill(l,0); check(l,0); worldReady=1;
  l.input=l.output; fill(l,5); check(l,5); l.output=std::make_shared<Table>();
  fill(l,50); check(l,50); growth=g_nameplateSightGrowths; cap=g_nameplateSightScratch.capacity();
  for(int i=0;i<10000;++i) { fakeNow=2000+i*20; l.reset(50); check(l,50); }
  assert(g_nameplateSightGrowths==growth && g_nameplateSightScratch.capacity()==cap && cap<=512);
  std::printf("PASS %d cases against actual UnitXP geometry: identical rays, masks, heights, distance guard and results\n",cases);
  puts("PASS 50 due queries: player resolution/position reads 50 -> 1; warm cached target reads 50 -> 0; 10,000 batches with no scratch growth");
  puts("PASS source change, disappeared units, expiry, native faults, malformed inputs, unchanged failures, bounds, Lua 5.0 lengths, aliased output and reentry");
}
'''
vcvars = Path("C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Auxiliary/Build/vcvarsall.bat")
build_root = (ROOT / "native/zAPI/build").resolve()
with tempfile.TemporaryDirectory(prefix="sight-test-", dir=build_root) as folder:
    build = Path(folder).resolve()
    assert build.parent == build_root
    cpp, exe = build / "sight.cpp", build / "sight.exe"
    cpp.write_text(prefix + body + tests, encoding="utf-8")
    cmd = f'call "{vcvars}" x86 >nul && cl /nologo /W4 /O2 /MT /EHsc /std:c++17 "{cpp}" /Fe:"{exe}"'
    result = subprocess.run('cmd.exe /d /s /c "' + cmd + '"', cwd=build, capture_output=True, text=True)
    if result.returncode:
        print(result.stdout, result.stderr)
        raise SystemExit(result.returncode)
    subprocess.run([str(exe)], check=True)
