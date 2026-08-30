#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <Windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include "MinHook.h"

namespace {

constexpr uintptr_t kPreferredImageBase = 0x00400000;
constexpr DWORD kExpectedTimestamp = 0x4510B6DB;
constexpr DWORD kExpectedImageSize = 0x0092B000;

constexpr uintptr_t kFrameScriptRegisterFunction = 0x00704120;
constexpr uintptr_t kLuaState = 0x00CEEF74;
constexpr uintptr_t kLuaGetTop = 0x006F3070;
constexpr uintptr_t kLuaIsNumber = 0x006F34D0;
constexpr uintptr_t kLuaToNumber = 0x006F3620;
constexpr uintptr_t kLuaToString = 0x006F3690;
constexpr uintptr_t kLuaPushNil = 0x006F37F0;
constexpr uintptr_t kLuaPushNumber = 0x006F3810;
constexpr uintptr_t kLuaPushString = 0x006F3890;
constexpr uintptr_t kLuaSetTop = 0x006F3080;
constexpr uintptr_t kFrameScriptPushObject = 0x006F3BC0;
constexpr uintptr_t kFrameScriptGetObject = 0x006F3740;

constexpr uintptr_t kUnitGuid = 0x00515970;
constexpr uintptr_t kGetObjectByGuid = 0x00464870;
constexpr uintptr_t kGetActiveCamera = 0x004818F0;
constexpr uintptr_t kWorldToScreen = 0x00483EE0;
constexpr uintptr_t kDdcToNdc = 0x0041ADE0;
constexpr uintptr_t kWorldFrame = 0x00B4B2BC;
constexpr uintptr_t kTextDrawBuilder = 0x005CDC20;

constexpr uintptr_t kFontStringTextBlock = 0xF8;
constexpr uintptr_t kTextBlockNode = 0x08;
constexpr uintptr_t kTextNodePageBuffers = 0xA0;
constexpr int kTextNodePageCount = 8;
constexpr uintptr_t kTextPageVertCount = 0x0C;
constexpr uintptr_t kTextPageVerts = 0x10;
constexpr int kTextVertStrideFloats = 5;

constexpr int kObjectTypeUnit = 3;
constexpr int kObjectTypePlayer = 4;

struct Vec3 {
  float x = 0.0f;
  float y = 0.0f;
  float z = 0.0f;
};

using LuaCFunction = int(__fastcall *)(void *L);
using FrameScriptRegisterFunctionFn = void(__fastcall *)(const char *, LuaCFunction);
using LuaGetTopFn = int(__fastcall *)(void *);
using LuaIsNumberFn = int(__fastcall *)(void *, int);
using LuaToNumberFn = double(__fastcall *)(void *, int);
using LuaToStringFn = const char *(__fastcall *)(void *, int);
using LuaPushNilFn = void(__fastcall *)(void *);
using LuaPushNumberFn = void(__fastcall *)(void *, double);
using LuaPushStringFn = void(__fastcall *)(void *, const char *);
using LuaSetTopFn = void(__fastcall *)(void *, int);
using FrameScriptPushObjectFn = void(__fastcall *)(void *, int, int);
using FrameScriptGetObjectFn = void *(__fastcall *)(void *, int);
using UnitGuidFn = uint64_t(__fastcall *)(const char *);
using GetObjectByGuidFn = uint32_t(__fastcall *)(uint64_t);
using GetActiveCameraFn = uint32_t(__fastcall *)();
using WorldToScreenFn = bool(__thiscall *)(uint32_t, float *, float *);
using DdcToNdcFn = void(__fastcall *)(float *, float *, float, float);
using UnitGetPositionFn = Vec3 *(__thiscall *)(uint32_t, Vec3 *);
using TextDrawBuilderFn = void(__fastcall *)(void *);

uintptr_t g_base = 0;
FrameScriptRegisterFunctionFn g_registerOriginal = nullptr;
TextDrawBuilderFn g_textDrawBuilderOriginal = nullptr;
volatile LONG g_initClaimed = 0;
volatile LONG g_initDone = 0;
volatile LONG g_initResult = 1;
volatile LONG g_mhInitialized = 0;
bool g_textHookInstalled = false;
std::unordered_map<void *, std::vector<float>> g_fontBaselines;
std::unordered_map<void *, std::vector<float>> g_fontWarped;
std::unordered_map<void *, float> g_fontAmounts;
std::unordered_map<void *, void *> g_fontNodes;
std::unordered_map<void *, void *> g_nodeOwners;

template <typename T>
T At(uintptr_t preferredAddress) {
  return reinterpret_cast<T>(g_base + preferredAddress - kPreferredImageBase);
}

bool IsReadable(uintptr_t address, size_t bytes) {
  if (address == 0 || bytes == 0) return false;
  MEMORY_BASIC_INFORMATION info{};
  if (VirtualQuery(reinterpret_cast<void *>(address), &info, sizeof(info)) == 0)
    return false;
  if (info.State != MEM_COMMIT || (info.Protect & (PAGE_NOACCESS | PAGE_GUARD)))
    return false;
  const uintptr_t end = address + bytes;
  const uintptr_t regionEnd = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
  return end >= address && end <= regionEnd;
}

bool CompatibleClient() {
  auto *dos = reinterpret_cast<IMAGE_DOS_HEADER *>(g_base);
  if (!IsReadable(g_base, sizeof(*dos)) || dos->e_magic != IMAGE_DOS_SIGNATURE)
    return false;
  auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(g_base + dos->e_lfanew);
  if (!IsReadable(reinterpret_cast<uintptr_t>(nt), sizeof(*nt)) ||
      nt->Signature != IMAGE_NT_SIGNATURE)
    return false;
  return nt->FileHeader.Machine == IMAGE_FILE_MACHINE_I386 &&
         nt->FileHeader.TimeDateStamp == kExpectedTimestamp &&
         nt->OptionalHeader.SizeOfImage == kExpectedImageSize;
}

void *FollowExistingJump(void *entry) {
  const uintptr_t address = reinterpret_cast<uintptr_t>(entry);
  if (!IsReadable(address, 5)) return entry;
  const auto *bytes = reinterpret_cast<const uint8_t *>(address);
  if (bytes[0] != 0xE9) return entry;
  const int32_t displacement = *reinterpret_cast<const int32_t *>(bytes + 1);
  const uintptr_t destination = address + 5 + displacement;
  return IsReadable(destination, 8) ? reinterpret_cast<void *>(destination) : entry;
}

int LuaGetTop(void *L) { return At<LuaGetTopFn>(kLuaGetTop)(L); }
bool LuaIsNumber(void *L, int index) { return At<LuaIsNumberFn>(kLuaIsNumber)(L, index) != 0; }
double LuaToNumber(void *L, int index) { return At<LuaToNumberFn>(kLuaToNumber)(L, index); }
const char *LuaToString(void *L, int index) { return At<LuaToStringFn>(kLuaToString)(L, index); }
void LuaPushNil(void *L) { At<LuaPushNilFn>(kLuaPushNil)(L); }
void LuaPushNumber(void *L, double value) { At<LuaPushNumberFn>(kLuaPushNumber)(L, value); }
void LuaPushString(void *L, const char *value) { At<LuaPushStringFn>(kLuaPushString)(L, value); }

void *ResolveLuaObject(void *L, int index) {
  At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L, index, 0);
  void *object = At<FrameScriptGetObjectFn>(kFrameScriptGetObject)(L, -1);
  At<LuaSetTopFn>(kLuaSetTop)(L, -2);
  return object;
}

template <typename Fn>
int ForEachFontVertex(void *node, Fn fn) {
  int visited = 0;
  auto *bytes = reinterpret_cast<uint8_t *>(node);
  for (int page = 0; page < kTextNodePageCount; ++page) {
    const uintptr_t slot = reinterpret_cast<uintptr_t>(bytes) +
                           kTextNodePageBuffers + page * 4;
    if (!IsReadable(slot, 4)) continue;
    auto *buffer = *reinterpret_cast<uint8_t **>(slot);
    if (!buffer || !IsReadable(reinterpret_cast<uintptr_t>(buffer) +
                               kTextPageVertCount, 8)) continue;
    const int count = *reinterpret_cast<int *>(buffer + kTextPageVertCount);
    auto *verts = *reinterpret_cast<float **>(buffer + kTextPageVerts);
    if (count <= 0 || count > 65536 || !verts ||
        !IsReadable(reinterpret_cast<uintptr_t>(verts),
                    static_cast<size_t>(count) * kTextVertStrideFloats * sizeof(float)))
      continue;
    for (int i = 0; i < count; ++i) {
      fn(verts + i * kTextVertStrideFloats);
      ++visited;
    }
  }
  return visited;
}

void *FontStringNode(void *fontString) {
  if (!fontString || !IsReadable(reinterpret_cast<uintptr_t>(fontString) +
                                 kFontStringTextBlock, 4)) return nullptr;
  auto *block = *reinterpret_cast<uint8_t **>(
      reinterpret_cast<uint8_t *>(fontString) + kFontStringTextBlock);
  if (!block || !IsReadable(reinterpret_cast<uintptr_t>(block) + kTextBlockNode, 4))
    return nullptr;
  return *reinterpret_cast<void **>(block + kTextBlockNode);
}

std::vector<float> ReadFontPositions(void *node) {
  std::vector<float> positions;
  const int count = ForEachFontVertex(node, [](float *) {});
  if (count <= 0) return positions;
  positions.reserve(static_cast<size_t>(count) * 2);
  ForEachFontVertex(node, [&](float *vertex) {
    positions.push_back(vertex[0]);
    positions.push_back(vertex[1]);
  });
  return positions;
}

void WriteFontPositions(void *node, const std::vector<float> &positions) {
  size_t index = 0;
  ForEachFontVertex(node, [&](float *vertex) {
    if (index + 1 < positions.size()) {
      vertex[0] = positions[index++];
      vertex[1] = positions[index++];
    }
  });
}

bool SamePositions(const std::vector<float> &left,
                   const std::vector<float> &right) {
  if (left.size() != right.size()) return false;
  for (size_t i = 0; i < left.size(); ++i) {
    if (std::fabs(left[i] - right[i]) > 0.0001f) return false;
  }
  return true;
}

void ForgetFontTrapezoid(void *fontString) {
  auto node = g_fontNodes.find(fontString);
  if (node != g_fontNodes.end()) {
    auto owner = g_nodeOwners.find(node->second);
    if (owner != g_nodeOwners.end() && owner->second == fontString)
      g_nodeOwners.erase(owner);
  }
  g_fontBaselines.erase(fontString);
  g_fontWarped.erase(fontString);
  g_fontAmounts.erase(fontString);
  g_fontNodes.erase(fontString);
}

bool SetFontTrapezoid(void *fontString, float amount) {
  void *node = FontStringNode(fontString);
  if (!node) return false;

  auto oldNode = g_fontNodes.find(fontString);
  if (oldNode != g_fontNodes.end() && oldNode->second != node) {
    g_nodeOwners.erase(oldNode->second);
    g_fontBaselines.erase(fontString);
    g_fontWarped.erase(fontString);
  }
  g_fontNodes[fontString] = node;
  g_nodeOwners[node] = fontString;

  std::vector<float> current = ReadFontPositions(node);
  if (current.empty()) return false;
  auto baseline = g_fontBaselines.find(fontString);
  auto warped = g_fontWarped.find(fontString);
  if (baseline != g_fontBaselines.end() && warped != g_fontWarped.end() &&
      SamePositions(current, warped->second)) {
    WriteFontPositions(node, baseline->second);
  } else {
    g_fontBaselines[fontString] = current;
  }

  if (std::fabs(amount) < 0.0001f) {
    ForgetFontTrapezoid(fontString);
    return true;
  }
  g_fontAmounts[fontString] = amount;

  float minX = 0.0f, maxX = 0.0f, minY = 0.0f, maxY = 0.0f;
  bool first = true;
  ForEachFontVertex(node, [&](float *vertex) {
    if (first) {
      minX = maxX = vertex[0]; minY = maxY = vertex[1]; first = false;
    } else {
      minX = (std::min)(minX, vertex[0]); maxX = (std::max)(maxX, vertex[0]);
      minY = (std::min)(minY, vertex[1]); maxY = (std::max)(maxY, vertex[1]);
    }
  });
  const float height = maxY - minY;
  if (height <= 0.0001f) return false;
  const float centerX = (minX + maxX) * 0.5f;
  // Diagnostic-strength ceiling: at 100% the bottom is 10% of its normal
  // width while the top is 190%, making a successful transform unmistakable.
  amount = (std::max)(-0.90f, (std::min)(0.90f, amount));
  ForEachFontVertex(node, [&](float *vertex) {
    const float vertical = (vertex[1] - minY) / height;
    const float scale = 1.0f + amount * (vertical * 2.0f - 1.0f);
    vertex[0] = centerX + (vertex[0] - centerX) * scale;
  });
  g_fontWarped[fontString] = ReadFontPositions(node);
  return true;
}

void __fastcall TextDrawBuilderHook(void *node) {
  g_textDrawBuilderOriginal(node);
  auto owner = g_nodeOwners.find(node);
  if (owner == g_nodeOwners.end()) return;
  void *fontString = owner->second;
  auto amount = g_fontAmounts.find(fontString);
  if (amount == g_fontAmounts.end() || FontStringNode(fontString) != node) {
    ForgetFontTrapezoid(fontString);
    return;
  }
  SetFontTrapezoid(fontString, amount->second);
}

uint64_t ResolveGuid(const char *identifier) {
  if (!identifier || !identifier[0]) return 0;
  if (identifier[0] == '0' && (identifier[1] == 'x' || identifier[1] == 'X'))
    return _strtoui64(identifier, nullptr, 16);
  return At<UnitGuidFn>(kUnitGuid)(identifier);
}

bool ResolveUnit(const char *identifier, uint32_t &unit) {
  const uint64_t guid = ResolveGuid(identifier);
  if (!guid) return false;
  unit = At<GetObjectByGuidFn>(kGetObjectByGuid)(guid);
  if (!IsReadable(unit, 0x11C)) return false;
  const int objectType = *reinterpret_cast<int *>(unit + 0x14);
  return objectType == kObjectTypeUnit || objectType == kObjectTypePlayer;
}

bool UnitPosition(uint32_t unit, Vec3 &position) {
  if (!IsReadable(unit, 4)) return false;
  const uint32_t vtable = *reinterpret_cast<uint32_t *>(unit);
  if (!IsReadable(vtable + 0x14, 4)) return false;
  const uint32_t getPosition = *reinterpret_cast<uint32_t *>(vtable + 0x14);
  if (!IsReadable(getPosition, 1)) return false;
  reinterpret_cast<UnitGetPositionFn>(getPosition)(unit, &position);
  return std::isfinite(position.x) && std::isfinite(position.y) && std::isfinite(position.z);
}

float UnitHeight(uint32_t unit) {
  if (!IsReadable(unit + 0x118, 4)) return 0.0f;
  const uint32_t movement = *reinterpret_cast<uint32_t *>(unit + 0x118);
  if (!IsReadable(movement + 0xB4, 4)) return 0.0f;
  float height = *reinterpret_cast<float *>(movement + 0xB4);
  if (!std::isfinite(height) || height < 0.0f) return 0.0f;
  return height > 4.0f ? 4.0f : height;
}

bool CameraState(Vec3 &position, Vec3 &forward, Vec3 &right, Vec3 &up,
                 float &fov, float &aspect) {
  const uint32_t camera = At<GetActiveCameraFn>(kGetActiveCamera)();
  if (!IsReadable(camera, 0x48)) return false;
  const float *cameraPosition = reinterpret_cast<float *>(camera + 0x08);
  const float *matrix = reinterpret_cast<float *>(camera + 0x14);
  position = {cameraPosition[0], cameraPosition[1], cameraPosition[2]};
  forward = {matrix[0], matrix[1], matrix[2]};
  right = {matrix[3], matrix[4], matrix[5]};
  up = {matrix[6], matrix[7], matrix[8]};
  fov = *reinterpret_cast<float *>(camera + 0x40);
  aspect = *reinterpret_cast<float *>(camera + 0x44);
  return std::isfinite(fov) && std::isfinite(aspect);
}

float CameraDepth(const Vec3 &world) {
  Vec3 camera{}, forward{}, right{}, up{};
  float fov = 0.0f, aspect = 0.0f;
  if (!CameraState(camera, forward, right, up, fov, aspect)) return -1.0f;
  return (world.x - camera.x) * forward.x +
         (world.y - camera.y) * forward.y +
         (world.z - camera.z) * forward.z;
}

bool ProjectWorld(const Vec3 &world, float &x, float &y, float &depth) {
  const uint32_t worldFrame = *At<uint32_t *>(kWorldFrame);
  if (!IsReadable(worldFrame + 0x3A8, 1)) return false;

  Vec3 input = world;
  Vec3 projected{};
  if (!At<WorldToScreenFn>(kWorldToScreen)(worldFrame, &input.x, &projected.x))
    return false;

  float ndcX = -1.0f;
  float ndcY = -1.0f;
  At<DdcToNdcFn>(kDdcToNdc)(&ndcX, &ndcY, projected.x, projected.y);
  x = *reinterpret_cast<float *>(worldFrame + 0x3A4) + ndcX;
  y = *reinterpret_cast<float *>(worldFrame + 0x3A0) + ndcY;
  depth = CameraDepth(world);
  return std::isfinite(x) && std::isfinite(y) && depth > 0.001f;
}

int __fastcall Script_zAPI(void *L) {
  const char *command = LuaToString(L, 1);
  if (!command) {
    LuaPushNil(L);
    return 1;
  }

  if (std::strcmp(command, "version") == 0) {
    LuaPushNumber(L, 1.3);
    return 1;
  }

  if (std::strcmp(command, "status") == 0) {
    LuaPushNumber(L, static_cast<double>(g_initResult));
    LuaPushNumber(L, g_textHookInstalled ? 1.0 : 0.0);
    return 2;
  }

  if (std::strcmp(command, "fontTrapezoid") == 0 && LuaGetTop(L) >= 3 &&
      LuaIsNumber(L, 3)) {
    void *fontString = ResolveLuaObject(L, 2);
    bool applied = false;
    if (fontString) {
      __try {
        applied = SetFontTrapezoid(
            fontString, static_cast<float>(LuaToNumber(L, 3)));
      } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_fontBaselines.erase(fontString);
        applied = false;
      }
    }
    LuaPushNumber(L, applied ? 1.0 : 0.0);
    return 1;
  }

  if (std::strcmp(command, "unitPosition") == 0 && LuaGetTop(L) >= 2) {
    uint32_t unit = 0;
    Vec3 position{};
    if (!ResolveUnit(LuaToString(L, 2), unit) || !UnitPosition(unit, position)) {
      LuaPushNil(L);
      return 1;
    }
    LuaPushNumber(L, position.x);
    LuaPushNumber(L, position.y);
    LuaPushNumber(L, position.z);
    LuaPushNumber(L, UnitHeight(unit));
    return 4;
  }

  if (std::strcmp(command, "worldToScreen") == 0 && LuaGetTop(L) >= 4 &&
      LuaIsNumber(L, 2) && LuaIsNumber(L, 3) && LuaIsNumber(L, 4)) {
    Vec3 world{static_cast<float>(LuaToNumber(L, 2)),
               static_cast<float>(LuaToNumber(L, 3)),
               static_cast<float>(LuaToNumber(L, 4))};
    float x = 0.0f, y = 0.0f, depth = 0.0f;
    if (!ProjectWorld(world, x, y, depth)) {
      LuaPushNil(L);
      return 1;
    }
    LuaPushNumber(L, x);
    LuaPushNumber(L, y);
    LuaPushNumber(L, depth);
    return 3;
  }

  if (std::strcmp(command, "projectUnit") == 0 && LuaGetTop(L) >= 3 &&
      LuaIsNumber(L, 3)) {
    uint32_t unit = 0;
    Vec3 world{};
    if (!ResolveUnit(LuaToString(L, 2), unit) || !UnitPosition(unit, world)) {
      LuaPushNil(L);
      return 1;
    }
    world.z += UnitHeight(unit) + static_cast<float>(LuaToNumber(L, 3));
    float x = 0.0f, y = 0.0f, depth = 0.0f;
    if (!ProjectWorld(world, x, y, depth)) {
      LuaPushNil(L);
      return 1;
    }
    LuaPushNumber(L, x);
    LuaPushNumber(L, y);
    LuaPushNumber(L, depth);
    LuaPushNumber(L, world.x);
    LuaPushNumber(L, world.y);
    LuaPushNumber(L, world.z);
    return 6;
  }

  if (std::strcmp(command, "camera") == 0) {
    Vec3 position{}, forward{}, right{}, up{};
    float fov = 0.0f, aspect = 0.0f;
    if (!CameraState(position, forward, right, up, fov, aspect)) {
      LuaPushNil(L);
      return 1;
    }
    const float values[] = {position.x, position.y, position.z,
                            forward.x, forward.y, forward.z,
                            right.x, right.y, right.z,
                            up.x, up.y, up.z, fov, aspect};
    for (float value : values) LuaPushNumber(L, value);
    return 14;
  }

  LuaPushNil(L);
  return 1;
}

void __fastcall RegisterFunctionHook(const char *name, LuaCFunction function) {
  g_registerOriginal(name, function);
  // UnitXP is part of the in-world API batch on every initial load and
  // /reload. Registering immediately after it avoids sharing UnitXP's hook
  // and keeps zAPI out of the glue/login Lua state.
  if (name && std::strcmp(name, "UnitXP") == 0) {
    g_fontBaselines.clear();
    g_fontWarped.clear();
    g_fontAmounts.clear();
    g_fontNodes.clear();
    g_nodeOwners.clear();
    g_registerOriginal("zAPI", &Script_zAPI);
  }
}

DWORD Install() {
  g_base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  if (!CompatibleClient()) return 2;
  if (MH_Initialize() != MH_OK) return 3;
  InterlockedExchange(&g_mhInitialized, 1);

  void *target = At<void *>(kFrameScriptRegisterFunction);
  if (MH_CreateHook(target, reinterpret_cast<void *>(&RegisterFunctionHook),
                    reinterpret_cast<void **>(&g_registerOriginal)) != MH_OK)
    return 4;
  if (MH_EnableHook(target) != MH_OK) return 5;
  // ClassicAPI loads before zAPI and already detours the draw builder. Hook
  // its current detour entry so our trampoline chains through ClassicAPI and
  // runs the trapezoid after ClassicAPI has finished its own glyph work.
  void *textTarget = FollowExistingJump(At<void *>(kTextDrawBuilder));
  if (MH_CreateHook(textTarget, reinterpret_cast<void *>(&TextDrawBuilderHook),
                    reinterpret_cast<void **>(&g_textDrawBuilderOriginal)) != MH_OK)
    return 6;
  if (MH_EnableHook(textTarget) != MH_OK) return 7;
  g_textHookInstalled = true;
  return 0;
}

DWORD EnsureInitialized() {
  if (InterlockedCompareExchange(&g_initClaimed, 1, 0) == 0) {
    g_initResult = static_cast<LONG>(Install());
    InterlockedExchange(&g_initDone, 1);
  } else {
    while (InterlockedCompareExchange(&g_initDone, 0, 0) == 0) Sleep(1);
  }
  return static_cast<DWORD>(g_initResult);
}

DWORD WINAPI InitWorker(void *) { return EnsureInitialized(); }

} // namespace

extern "C" DWORD Load() { return EnsureInitialized(); }

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(module);
    if (GetModuleHandleW(L"VfPatcher.dll") == nullptr) {
      HANDLE worker = CreateThread(nullptr, 0, InitWorker, nullptr, 0, nullptr);
      if (worker) CloseHandle(worker);
    }
  } else if (reason == DLL_PROCESS_DETACH && g_mhInitialized) {
    MH_Uninitialize();
  }
  return TRUE;
}
