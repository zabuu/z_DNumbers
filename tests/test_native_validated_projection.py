"""Production combined validation/projection against live native memory fixtures."""
import ast
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/zAPI/src"
source = (NATIVE / "zAPI.cpp").read_text(encoding="utf-8-sig")
tree = ast.parse((ROOT / "tests/test_native_projection_batch.py").read_text())


def assigned(name):
    return next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))


def section(first, last):
    start = source.index(first)
    return source[start:source.index(last, start)]


prefix = assigned("prefix")
prefix += (NATIVE / "ReadableRegionCache.h").read_text()
prefix += section("bool IsReadable(", "bool CompatibleClient(")
prefix += section("struct Vec3 {", "using LuaCFunction")
prefix += section("struct ProjectionViewport {", "bool ReadProjectionViewport(")
client = assigned("fake_client")
client = client[:client.index("bool ResolveUnit(")]
client = client.replace("template<typename Fn> Fn At(", '''
using FrameScriptGetObjectFn=void *(__fastcall *)(void *,int);
constexpr uintptr_t kFrameScriptGetObject=7;
void *__fastcall FixtureLuaObject(void *p,int index) {
 auto &v=slot(p,index); return v.type==2?reinterpret_cast<void *>(uintptr_t(v.number)):nullptr;
}
template<typename Fn> Fn At(''')
client = client.replace("case 6:return", "case 7:return reinterpret_cast<Fn>(&FixtureLuaObject);\n    case 6:return")
client += section("void *ResolveLuaObject(", "struct FontVertexPages {")
client += r'''
struct Fixture {
 uint8_t unit[0xE64]{},frame[0x4F0]{}; bool present=true,model=true,fault=false; int index;
 Fixture(int i):index(i) {
  *reinterpret_cast<uint64_t *>(unit+0x30)=i;
  *reinterpret_cast<uint32_t *>(unit+0xE60)=reinterpret_cast<uint32_t>(frame);
  *reinterpret_cast<uint64_t *>(frame+0x4E8)=i;
 }
};
std::map<int,std::unique_ptr<Fixture>> fixtures;
uint64_t ResolveGuid(const char *s) { return std::strtoull(s+2,nullptr,16); }
bool ResolveUnit(const char *s,uint32_t &unit) {
 ++resolves;
 const int i=std::strncmp(s,"nameplate",9)==0?std::atoi(s+9):int(ResolveGuid(s));
 auto it=fixtures.find(i); if(it==fixtures.end() || !it->second->present) return false;
 unit=reinterpret_cast<uint32_t>(it->second->unit); return true;
}
bool UnitNameplatePosition(uint32_t unit,Vec3 &world) {
 ++models;
 for(const auto &item:fixtures) if(reinterpret_cast<uint32_t>(item.second->unit)==unit) {
  if(item.second->fault) RaiseException(EXCEPTION_ACCESS_VIOLATION,0,0,nullptr);
  if(!item.second->model) return false;
  const float i=float(item.second->index); world={20+i,4+i,3+i}; return true;
 }
 return false;
}
'''
projection = section("bool ProjectWorldWithCamera(", '#include "NameplateBatch.h"')
body = (NATIVE / "NameplateBatch.h").read_text() + (NATIVE / "NameplateValidatedBatch.h").read_text()
tests = r'''
bool reentry=false;
std::shared_ptr<Table> tokens=std::make_shared<Table>(),parents=std::make_shared<Table>();
std::string guid(int n) { char b[19]; std::snprintf(b,sizeof(b),"0x%016llX",uint64_t(n)); return b; }
void reset(FakeLua &l,double n) { l.reset(n); l.stack.push_back(Value::Tab(tokens)); l.stack.push_back(Value::Tab(parents)); }
void fill(FakeLua &l,int count) {
 l.input->array.clear(); tokens->array.clear(); parents->array.clear();
 for(int i=1;i<=count;++i) {
  l.input->array[i]=Value::Str(guid(i)); tokens->array[i]=Value::Str("nameplate"+std::to_string(i));
  auto wrapper=std::make_shared<Table>(); Value ptr;ptr.type=2;ptr.number=reinterpret_cast<uintptr_t>(fixtures[i]->frame);
  wrapper->array[0]=ptr; parents->array[i]=Value::Tab(wrapper);
 }
 reset(l,count);
}
void LuaRawSetI(void *p,int index,int key) {
 assert(!g_readableRegionCache);
 auto &l=*static_cast<FakeLua *>(p);auto t=slot(p,index).table;Value v=l.stack.back();l.stack.pop_back();
 if(reentry) {
  reentry=false;FakeLua inner;inner.input=l.input;reset(inner,2);
  assert(DoValidatedPlateProjections(&inner)==1 && inner.stack.back().number==2);
 }
 if(v.type==0)t->array.erase(key);else t->array[key]=v;
}
void check(FakeLua &l,int count) {
 assert(DoValidatedPlateProjections(&l)==1 && l.stack.back().type==3 && l.stack.back().number==count);
 assert(l.stack.size()==7 && l.output->length==count*8 && l.output->array.size()==size_t(count*8));
}
void rejected(FakeLua &l) {
 auto size=l.output->array.size(); auto length=l.output->length;
 assert(DoValidatedPlateProjections(&l)==1 && l.stack.back().type==0);
 assert(l.output->array.size()==size && l.output->length==length);
}
int main() {
 for(int i=1;i<=512;++i) fixtures[i]=std::make_unique<Fixture>(i);
 FakeLua l;fill(l,50);resolves=models=0;check(l,50);
 assert(resolves==50 && models==50); // one live unit resolution per plate.
 for(int i=1;i<=50;++i) {
  NameplateBatchRow old; Vec3 camera{cameraX,0,0},forward{1,0,0};ProjectionViewport viewport{};ReadProjectionViewport(viewport);
  assert(ProjectBatchNameplate(guid(i).c_str(),camera,forward,viewport,old));int k=(i-1)*8;
  assert(l.output->array.at(k+1).number==1);
  for(int j=0;j<7;++j)assert(l.output->array.at(k+j+2).number==old.values[j]);
 }
 cameraX=3;angle=.4f;reset(l,50);check(l,50);assert(l.output->array.at(5).number==18);
 // Token, object GUID and both directions of the native frame association
 // must agree. Stale slots cannot inherit projection grace.
 tokens->array[1]=Value::Str("nameplate2");
 *reinterpret_cast<uint64_t *>(fixtures[2]->unit+0x30)=99;
 *reinterpret_cast<uint64_t *>(fixtures[3]->frame+0x4E8)=99;
 *reinterpret_cast<uint32_t *>(fixtures[4]->unit+0xE60)=reinterpret_cast<uint32_t>(fixtures[5]->frame);
 fixtures[5]->present=false; parents->array[6]=Value::Num(0);
 fixtures[7]->model=false; fixtures[8]->fault=true;
 reset(l,50);check(l,50);
 for(int i=1;i<=6;++i) for(int j=1;j<=8;++j)assert(l.output->array.at((i-1)*8+j).number==0);
 assert(l.output->array.at(49).number==1 && l.output->array.at(50).number==0); // model gap, current association.
 assert(l.output->array.at(57).number==0); // native fault: unknown association.
 *reinterpret_cast<uint64_t *>(fixtures[2]->unit+0x30)=2;
 *reinterpret_cast<uint64_t *>(fixtures[3]->frame+0x4E8)=3;
 *reinterpret_cast<uint32_t *>(fixtures[4]->unit+0xE60)=reinterpret_cast<uint32_t>(fixtures[4]->frame);
 fixtures[5]->present=true;fixtures[7]->model=true;fixtures[8]->fault=false;
 fill(l,50);check(l,50);
 cameraReady=false;reset(l,50);rejected(l);cameraReady=true;
 viewportReady=false;reset(l,50);rejected(l);viewportReady=true;
 for(double n:{-1.0,513.0,.5,HUGE_VAL,std::nan("")}) {reset(l,n);rejected(l);}
 reset(l,50);l.stack[4]=Value::Num(0);rejected(l);
 reset(l,50);l.stack[5]=Value::Num(0);rejected(l);
 l.output->length=4097;reset(l,50);rejected(l);l.output->length=400;
 reentry=true;reset(l,50);check(l,50);assert(l.output->array.at(5).number==18);
 fill(l,512);check(l,512);fill(l,1);check(l,1);cameraReady=false;fill(l,0);check(l,0);cameraReady=true;
 l.input=l.output;fill(l,5);check(l,5);l.output=std::make_shared<Table>();fill(l,50);check(l,50);
 auto capacity=g_validatedPlateScratch.capacity();auto growth=g_validatedPlateGrowths;
 for(int i=0;i<10000;++i) {reset(l,50);check(l,50);}
 assert(g_validatedPlateScratch.capacity()==capacity && capacity<=512 && g_validatedPlateGrowths==growth);
 puts("PASS exact scalar projection parity, live camera, one unit resolution/plate, token/GUID/bidirectional frame identity, model gaps vs stale slots, native faults, bounds, unchanged failures, reentry, Lua 5.0 lengths and aliased output");
 puts("PASS 10,000 warm 50-plate validated batches: no further scratch growth; retained rows <=512");
}
'''
vcvars = Path("C:/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/VC/Auxiliary/Build/vcvarsall.bat")
build_root = (ROOT / "native/zAPI/build").resolve()
with tempfile.TemporaryDirectory(prefix="validated-test-", dir=build_root) as folder:
    build = Path(folder).resolve()
    assert build.parent == build_root
    cpp, exe = build / "test.cpp", build / "test.exe"
    cpp.write_text(prefix + client + projection + body + tests, encoding="utf-8")
    cmd = f'call "{vcvars}" x86 >nul && cl /nologo /W4 /O2 /MT /EHsc /std:c++17 "{cpp}" /Fe:"{exe}"'
    result = subprocess.run('cmd.exe /d /s /c "' + cmd + '"', cwd=build, capture_output=True, text=True)
    if result.returncode:
        print(result.stdout, result.stderr)
        raise SystemExit(result.returncode)
    subprocess.run([str(exe)], check=True)

