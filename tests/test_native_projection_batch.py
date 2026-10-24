"""Compile the actual batch and projection helpers against a fake 1.12 client.

Runs without injecting into WoW. The full DLL build separately checks ABI/linking.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
native = ROOT / "native/zAPI/src"
source = (native / "zAPI.cpp").read_text(encoding="utf-8-sig")


def section(start, end):
    first = source.index(start)
    return source[first:source.index(end, first)]


prefix = r'''
#include <Windows.h>
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>
struct Table;
struct Value {
  int type=0; double number=0; std::string text; std::shared_ptr<Table> table;
  static Value Num(double x) { Value v; v.type=3; v.number=x; return v; }
  static Value Str(std::string x) { Value v; v.type=4; v.text=x; return v; }
  static Value Tab(std::shared_ptr<Table> t) { Value v; v.type=5; v.table=t; return v; }
};
struct Table { std::map<int,Value> array; int length=0; };
struct FakeLua {
  std::vector<Value> stack;
  std::shared_ptr<Table> input=std::make_shared<Table>(), output=std::make_shared<Table>();
  void reset(double n) { stack={Value::Str("projectNameplatesInto"),Value::Tab(input),Value::Num(n),Value::Tab(output)}; }
};
Value &slot(void *p,int index) {
  auto &s=static_cast<FakeLua *>(p)->stack;
  const int offset=index>0 ? index-1 : int(s.size())+index;
  assert(offset>=0 && offset<int(s.size())); return s[offset];
}
int LuaGetTop(void *p) { return int(static_cast<FakeLua *>(p)->stack.size()); }
int LuaType(void *p,int i) { return slot(p,i).type; }
double LuaToNumber(void *p,int i) { return slot(p,i).number; }
const char *LuaToString(void *p,int i) { return slot(p,i).text.c_str(); }
void LuaPushNil(void *p) { static_cast<FakeLua *>(p)->stack.push_back(Value{}); }
void LuaPushNumber(void *p,double n) { static_cast<FakeLua *>(p)->stack.push_back(Value::Num(n)); }
void __fastcall RawGetI(void *p,int index,int key) {
  auto &l=*static_cast<FakeLua *>(p); auto t=slot(p,index).table;
  const auto it=t->array.find(key); l.stack.push_back(it==t->array.end()?Value{}:it->second);
}
void __fastcall SetTop(void *p,int index) {
  auto &s=static_cast<FakeLua *>(p)->stack;
  s.resize(index>=0?index:int(s.size())+index+1);
}
int __fastcall GetN(void *p,int index) { return slot(p,index).table->length; }
void __fastcall SetN(void *p,int index,int n) { slot(p,index).table->length=n; }
void LuaRawSetI(void *,int,int);
'''

# Compile the real memory-validation implementation too. Only the Windows query
# is counted; fixture reads use actual committed/protected pages in this process.
prefix += r'''
bool usePageCache=true;
int pageQueries=0;
SIZE_T CountedVirtualQuery(LPCVOID p, PMEMORY_BASIC_INFORMATION info, SIZE_T n) {
  ++pageQueries; return VirtualQuery(p,info,n);
}
char *memoryFixture=nullptr;
'''
prefix += (native / "ReadableRegionCache.h").read_text(encoding="utf-8-sig")
prefix += section("bool IsReadable(", "bool CompatibleClient(").replace(
    "VirtualQuery(", "CountedVirtualQuery("
).replace("g_readableRegionCache", "(usePageCache ? g_readableRegionCache : nullptr)")

types = section("struct Vec3 {", "using LuaCFunction")
viewport = section("struct ProjectionViewport {", "bool ReadProjectionViewport(")
fake_client = r'''
using LuaLGetNFn=int(__fastcall *)(void *,int);
using LuaLSetNFn=void(__fastcall *)(void *,int,int);
using LuaSetTopFn=void(__fastcall *)(void *,int);
using FrameScriptPushObjectFn=void(__fastcall *)(void *,int,int);
using WorldToScreenFn=bool(__thiscall *)(uint32_t,float *,float *);
using DdcToNdcFn=void(__fastcall *)(float *,float *,float,float);
constexpr uintptr_t kLuaLGetN=1,kLuaLSetN=2,kLuaSetTop=3,kFrameScriptPushObject=4;
constexpr uintptr_t kWorldToScreen=5,kDdcToNdc=6;
int cameraReads=0,viewportReads=0,resolves=0,models=0,projections=0;
bool cameraReady=true,viewportReady=true,reenter=false;
float cameraX=0,angle=0;
bool __fastcall WorldToScreen(uint32_t frame,void *,float *input,float *out) {
  assert(frame==123); ++projections;
  out[0]=input[1]*.01f+angle; out[1]=input[2]*.02f; out[2]=0; return true;
}
void __fastcall DdcToNdc(float *x,float *y,float dx,float dy) { *x=dx*.5f; *y=dy*.5f; }
template<typename Fn> Fn At(uintptr_t address) {
  switch(address) {
    case 1:return reinterpret_cast<Fn>(&GetN);
    case 2:return reinterpret_cast<Fn>(&SetN);
    case 3:return reinterpret_cast<Fn>(&SetTop);
    case 4:return reinterpret_cast<Fn>(&RawGetI);
    case 5:return reinterpret_cast<Fn>(&WorldToScreen);
    case 6:return reinterpret_cast<Fn>(&DdcToNdc);
  }
  assert(false); return nullptr;
}
bool CameraState(Vec3 &pos,Vec3 &forward,Vec3 &,Vec3 &,float &fov,float &aspect) {
  ++cameraReads; pos={cameraX,0,0}; forward={1,0,0}; fov=1; aspect=1.6f; return cameraReady;
}
bool ReadProjectionViewport(ProjectionViewport &v) {
  ++viewportReads; v.frame=123; v.left=.1f; v.bottom=.2f; return viewportReady;
}
bool ResolveUnit(const char *text,uint32_t &unit) {
  assert(IsReadable(reinterpret_cast<uintptr_t>(memoryFixture),16));
  ++resolves; unit=uint32_t(std::strtoull(text+2,nullptr,16)); return unit!=0 && unit!=88;
}
bool UnitNameplatePosition(uint32_t unit,Vec3 &world) {
  for(int i=0;i<7;++i)
    assert(IsReadable(reinterpret_cast<uintptr_t>(memoryFixture)+unit*16+i,4));
  ++models;
  if(unit==99) RaiseException(EXCEPTION_ACCESS_VIOLATION,0,0,nullptr);
  if(unit==77) return false;
  world={20.0f+unit,4.0f+unit,3.0f+unit}; return true;
}
'''
projection = section("bool ProjectWorldWithCamera(", '#include "NameplateBatch.h"')
body = (native / "NameplateBatch.h").read_text(encoding="utf-8-sig")
tests = r'''
std::string guid(int n) { char s[19]; std::snprintf(s,sizeof(s),"0x%016llX",uint64_t(n)); return s; }
void fill(FakeLua &l,int n) {
  l.input->array.clear(); for(int i=1;i<=n;++i) l.input->array[i]=Value::Str(guid(i));
  l.input->length=n; l.reset(n);
}
void LuaRawSetI(void *p,int index,int key) {
  assert(g_readableRegionCache==nullptr); // No page views across Lua allocation/reentry.
  auto &l=*static_cast<FakeLua *>(p); auto t=slot(p,index).table;
  Value value=l.stack.back(); l.stack.pop_back();
  if(reenter) {
    reenter=false; FakeLua other; fill(other,2);
    assert(DoProjectNameplatesInto(&other)==1 && other.stack.back().number==2);
    assert(other.output->array.at(4).number==21-cameraX);
  }
  if(value.type==0) t->array.erase(key); else t->array[key]=value;
}
void check(FakeLua &l,int n) {
  assert(DoProjectNameplatesInto(&l)==1 && l.stack.back().type==3 && l.stack.back().number==n);
  assert(l.stack.size()==5 && l.output->length==n*7 && l.output->array.size()==size_t(n*7));
}
void rejected(FakeLua &l) {
  const auto size=l.output->array.size(); const int length=l.output->length;
  assert(DoProjectNameplatesInto(&l)==1 && l.stack.back().type==0);
  assert(l.output->array.size()==size && l.output->length==length);
}
int main() {
  memoryFixture=static_cast<char *>(VirtualAlloc(nullptr,65536,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE));
  assert(memoryFixture);
  const auto address=reinterpret_cast<uintptr_t>(memoryFixture);
  assert(!IsReadable(0,4) && !IsReadable(address,0) && !IsReadable(UINTPTR_MAX-1,8));
  {
    ScopedReadableRegions outer; auto *saved=g_readableRegionCache;
    assert(IsReadable(address,16)); const int warm=pageQueries;
    for(int i=0;i<100;++i) assert(IsReadable(address+32,4));
    assert(pageQueries==warm);
    { ScopedReadableRegions inner; assert(g_readableRegionCache!=saved); assert(IsReadable(address,4)); }
    assert(g_readableRegionCache==saved && IsReadable(address,4));
  }
  assert(g_readableRegionCache==nullptr);
  DWORD old=0; assert(VirtualProtect(memoryFixture,65536,PAGE_NOACCESS,&old));
  assert(!IsReadable(address,4)); // A new batch never inherits stale permissions.
  { ScopedReadableRegions fresh; assert(!IsReadable(address,4)); }
  assert(VirtualProtect(memoryFixture,65536,PAGE_READWRITE,&old));
  FakeLua l; fill(l,50); check(l,50);
  assert(cameraReads==1 && viewportReads==1 && resolves==50 && models==50 && projections==50);
  // Compare every native result with the actual unchanged single-unit helper.
  for(int i=1;i<=50;++i) {
    Vec3 world; UnitNameplatePosition(i,world); float x=0,y=0,d=0;
    assert(ProjectWorld(world,x,y,d)); int k=(i-1)*7;
    const float expected[]={1,x,y,d,world.x,world.y,world.z};
    for(int j=1;j<=7;++j) assert(l.output->array.at(k+j).number==expected[j-1]);
  }
  // Camera rotation/motion is fresh on every invocation; no timestamp cache.
  angle=.4f; cameraX=3; l.reset(50); check(l,50);
  assert(l.output->array.at(2).number==float(.1f+(5*.01f+.4f)*.5f));
  assert(l.output->array.at(4).number==18);
  auto cap=g_nameplateBatchScratch.capacity(); auto growth=g_nameplateBatchGrowths;
  for(int i=0;i<10000;++i) { l.reset(50); check(l,50); }
  assert(g_nameplateBatchGrowths==growth && g_nameplateBatchScratch.capacity()==cap && cap<=512);
  // Missing units/models, off-camera points, malformed rows and native faults
  // replace previous coordinates with zeros; other rows remain usable.
  l.input->array[1]=Value::Str(guid(88)); l.input->array[2]=Value::Str(guid(77));
  l.input->array[3]=Value::Str(guid(99)); l.input->array[4]=Value::Str("target");
  l.input->array[5]=Value::Num(123); l.input->array[6]=Value::Str("0x000000000000000Z");
  l.input->array.erase(7); l.reset(50); check(l,50);
  for(int key=1;key<=49;++key) assert(l.output->array.at(key).number==0);
  assert(l.output->array.at(50).number==1);
  cameraX=1000; l.reset(50); check(l,50);
  for(const auto &entry:l.output->array) assert(entry.second.number==0);
  cameraX=0; fill(l,50); check(l,50);
  const auto kept=l.output->array.at(2).number;
  // Whole-call failures do not publish partial output or alter stored length.
  cameraReady=false; l.reset(50); rejected(l); cameraReady=true;
  viewportReady=false; l.reset(50); rejected(l); viewportReady=true;
  for(double count:{-1.0,513.0,.5,HUGE_VAL,std::nan("")}) { l.reset(count); rejected(l); }
  l.reset(50); l.stack[1]=Value::Num(0); rejected(l);
  l.reset(50); l.stack[2]=Value::Str("50"); rejected(l);
  l.reset(50); l.stack[3]=Value::Num(0); assert(DoProjectNameplatesInto(&l)==1 && l.stack.back().type==0);
  l.reset(50); l.stack.pop_back(); assert(DoProjectNameplatesInto(&l)==1 && l.stack.back().type==0);
  l.output->length=3585; l.reset(50); rejected(l); l.output->length=350;
  assert(l.output->array.at(2).number==kept);
  // Reentry owns a separate result snapshot, not the outer scratch vector.
  reenter=true; l.reset(50); check(l,50); assert(l.output->array.at(4).number==21);
  fill(l,512); check(l,512); assert(g_nameplateBatchScratch.capacity()<=512);
  fill(l,1); check(l,1); assert(l.output->array.count(8)==0);
  cameraReady=false; fill(l,0); check(l,0); cameraReady=true;
  assert(l.output->array.empty() && l.output->length==0);
  // Inputs are fully consumed before output, even for aliased caller tables.
  l.input=l.output; fill(l,5); check(l,5); assert(l.output->array.at(4).number==21);
  // Isolate validation costs with real VirtualQuery, unchanged model/projection
  // fixtures and the production batch code. This is not a WoW FPS benchmark.
  l.output=std::make_shared<Table>(); fill(l,50);
  for(bool cached:{false,true}) {
    usePageCache=cached; pageQueries=0;
    auto started=std::chrono::steady_clock::now();
    for(int i=0;i<2000;++i) { l.reset(50); check(l,50); }
    const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count()/2000;
    assert(pageQueries==(cached?2000:800000));
    std::printf("BENCH 50-row native fixture cache=%d: %.6f ms/batch; %.1f VirtualQuery/batch\n",cached,ms,pageQueries/2000.0);
  }
  VirtualFree(memoryFixture,0,MEM_RELEASE);
  puts("PASS native projection parity, one camera/viewport capture, live camera, gaps/faults, bounds, strict inputs, unchanged failures, reentry and Lua 5.0 shrink/empty lengths");
  puts("PASS 10,000 warm 50-unit batches: zero additional scratch growth; retained native capacity <=512; no per-row Lua tables");
}
'''

vcvars = Path("C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Auxiliary/Build/vcvarsall.bat")
if not vcvars.is_file():
    raise SystemExit("Native batch harness requires the local MSVC x86 build tools.")
build_root = (ROOT / "native/zAPI/build").resolve()
build_root.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="projection-test-", dir=build_root) as folder:
    build = Path(folder).resolve()
    assert build.parent == build_root  # Bound generated files and cleanup to this build directory.
    cpp, exe = build / "batch.cpp", build / "batch.exe"
    cpp.write_text(prefix + types + viewport + fake_client + projection + body + tests, encoding="utf-8")
    command = f'call "{vcvars}" x86 >nul && cl /nologo /W4 /O1 /MT /EHsc /std:c++17 "{cpp}" /Fe:"{exe}"'
    result = subprocess.run('cmd.exe /d /s /c "' + command + '"', cwd=build, capture_output=True, text=True)
    if result.returncode:
        print(result.stdout, result.stderr)
        raise SystemExit(result.returncode)
    subprocess.run([str(exe)], check=True)
