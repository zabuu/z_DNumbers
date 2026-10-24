#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <Windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <vector>

#include "MinHook.h"
#include "ScopedPetCommand.h"
#include "ScopedPetPosition.h"
#include "VerifiedNativeEntry.h"
#include "GcControl.h"

namespace {

constexpr uintptr_t kPreferredImageBase = 0x00400000;
constexpr DWORD kExpectedTimestamp = 0x4510B6DB;
constexpr DWORD kExpectedImageSize = 0x0092B000;

constexpr uintptr_t kFrameScriptRegisterFunction = 0x00704120;
constexpr uintptr_t kLuaState = 0x00CEEF74;
constexpr uintptr_t kLuaGetTop = 0x006F3070;
constexpr uintptr_t kLuaType = 0x006F3400;
constexpr uintptr_t kLuaLGetN = 0x006F5050;
constexpr uintptr_t kLuaLSetN = 0x006F4EA0;
constexpr uintptr_t kLuaGetGCThreshold = 0x006F43E0;
constexpr uintptr_t kLuaGetGCCount = 0x006F43F0;
constexpr uintptr_t kLuaSetGCThreshold = 0x006F4400;
constexpr uintptr_t kLuaIsNumber = 0x006F34D0;
constexpr uintptr_t kLuaToNumber = 0x006F3620;
constexpr uintptr_t kLuaToString = 0x006F3690;
constexpr uintptr_t kLuaPushNil = 0x006F37F0;
constexpr uintptr_t kLuaPushNumber = 0x006F3810;
constexpr uintptr_t kLuaPushString = 0x006F3890;
constexpr uintptr_t kLuaNewTable = 0x006F3C90;
constexpr uintptr_t kLuaRawSetI = 0x006F3F60;
constexpr uintptr_t kLuaSetTop = 0x006F3080;
constexpr uintptr_t kFrameScriptPushObject = 0x006F3BC0;
constexpr uintptr_t kFrameScriptGetObject = 0x006F3740;

constexpr uintptr_t kUnitGuid = 0x00515970;
constexpr uintptr_t kGetObjectByGuid = 0x00464870;
constexpr uintptr_t kSetTargetByGuid = 0x00493540;
constexpr uintptr_t kPetCommandDispatch = 0x004BD1D0;
constexpr uintptr_t kPositionSpellDispatch = 0x004B3300;
constexpr uintptr_t kPositionCommit = 0x006E60F0;
constexpr uintptr_t kPositionCancel = 0x006E4900;
constexpr uintptr_t kPositionPlacement = 0x00CECAC0;
constexpr uintptr_t kFrameScriptContext = 0x00CEEAC0;
constexpr uintptr_t kFrameScriptDepth = 0x00CEEAC4;
constexpr uintptr_t kInWorld = 0x00B4B424;
constexpr uintptr_t kEnumVisibleObjects = 0x00468380;
constexpr uintptr_t kGetActiveCamera = 0x004818F0;
constexpr uintptr_t kUnitGetNamePosition = 0x00608640;
constexpr uintptr_t kNameplateWorldClearance = 0x0080ABFC;
constexpr uintptr_t kWorldToScreen = 0x00483EE0;
constexpr uintptr_t kDdcToNdc = 0x0041ADE0;
constexpr uintptr_t kWorldFrame = 0x00B4B2BC;
constexpr uintptr_t kTextDrawBuilder = 0x005CDC20;
constexpr uintptr_t kRefreshCursorRaycast = 0x00481F00;
constexpr uintptr_t kGetTickCount = 0x0042C010;
constexpr uintptr_t kCWorldIntersect = 0x00672170;
constexpr uint32_t kLoSFlags = 0x01200116;
constexpr uintptr_t kSpellDbcRecords = 0x00C0D788;
constexpr uintptr_t kSpellDbcMaxId = 0x00C0D78C;
constexpr uintptr_t kLocale = 0x00C0E080;
constexpr uintptr_t kPlayerSpellbook = 0x00B700F0;
constexpr uintptr_t kPetSpellbook = 0x00B6F098;
constexpr uintptr_t kCooldownMgrPlayer = 0x00CECAEC;
constexpr uintptr_t kCooldownMgrPet = 0x00CECB04;
constexpr uintptr_t kLightDirection = 0x00C0F520;
constexpr uintptr_t kLightDiffuse = 0x00C0F4E4;
constexpr uintptr_t kLightAmbient = 0x00C0F504;
constexpr uintptr_t kDeviceSetTexture = 0x005A0D70;
constexpr uintptr_t kPrepareTexture = 0x005A0A80;

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

struct ProjectionResult {
  float ddcX = 0.0f;
  float ddcY = 0.0f;
  float ndcX = 0.0f;
  float ndcY = 0.0f;
  float screenX = 0.0f;
  float screenY = 0.0f;
  float depth = 0.0f;
};

using LuaCFunction = int(__fastcall *)(void *L);
using FrameScriptRegisterFunctionFn = void(__fastcall *)(const char *, LuaCFunction);
using LuaGetTopFn = int(__fastcall *)(void *);
using LuaTypeFn = int(__fastcall *)(void *, int);
using LuaLGetNFn = int(__fastcall *)(void *, int);
using LuaLSetNFn = void(__fastcall *)(void *, int, int);
using LuaGetGCFn = uint32_t(__fastcall *)(void *);
using LuaSetGCFn = void(__fastcall *)(void *, uint32_t);
using LuaIsNumberFn = int(__fastcall *)(void *, int);
using LuaToNumberFn = double(__fastcall *)(void *, int);
using LuaToStringFn = const char *(__fastcall *)(void *, int);
using LuaPushNilFn = void(__fastcall *)(void *);
using LuaPushNumberFn = void(__fastcall *)(void *, double);
using LuaPushStringFn = void(__fastcall *)(void *, const char *);
using LuaNewTableFn = void(__fastcall *)(void *);
using LuaRawSetIFn = void(__fastcall *)(void *, int, int);
using LuaSetTopFn = void(__fastcall *)(void *, int);
using FrameScriptPushObjectFn = void(__fastcall *)(void *, int, int);
using FrameScriptGetObjectFn = void *(__fastcall *)(void *, int);
using UnitGuidFn = uint64_t(__fastcall *)(const char *);
using GetObjectByGuidFn = uint32_t(__fastcall *)(uint64_t);
using SetTargetByGuidFn = void(__fastcall *)(const uint64_t *);
using EnumVisibleCallbackFn = int(__fastcall *)(void *, void *, uint64_t);
using EnumVisibleObjectsFn = int(__fastcall *)(EnumVisibleCallbackFn, void *);
using GetActiveCameraFn = uint32_t(__fastcall *)();
using WorldToScreenFn = bool(__thiscall *)(uint32_t, float *, float *);
using DdcToNdcFn = void(__fastcall *)(float *, float *, float, float);
using UnitGetPositionFn = Vec3 *(__thiscall *)(uint32_t, Vec3 *);
using TextDrawBuilderFn = void(__fastcall *)(void *);
using RefreshCursorRaycastFn = void(__fastcall *)(void *);
using GetTickCountFn = uint32_t(__cdecl *)();
using IntersectFn = char(__fastcall *)(const Vec3 *start, const Vec3 *end,
                                       int unused, Vec3 *hitOut, float *tOut,
                                       uint32_t flags);
using DeviceSetTextureFn = void(__thiscall *)(void *, void *);
using PrepareTextureFn = void(__thiscall *)(void *, void *);

uintptr_t g_base = 0;
FrameScriptRegisterFunctionFn g_registerOriginal = nullptr;
TextDrawBuilderFn g_textDrawBuilderOriginal = nullptr;
DeviceSetTextureFn g_deviceSetTextureOriginal = nullptr;
PrepareTextureFn g_prepareTextureOriginal = nullptr;
volatile LONG g_initClaimed = 0;
volatile LONG g_initDone = 0;
volatile LONG g_initResult = 1;
volatile LONG g_mhInitialized = 0;
volatile LONG g_petCommandBusy = 0;
bool g_textHookInstalled = false;
struct FontTransformState {
  void *node = nullptr;
  float amount = 0.0f;
  std::vector<float> baseline;
  std::vector<float> warped;
};
std::unordered_map<void *, FontTransformState> g_fontStates;
std::unordered_map<void *, void *> g_nodeOwners;

template <typename T>
T At(uintptr_t preferredAddress) {
  if constexpr (std::is_pointer_v<T>) {
    return reinterpret_cast<T>(g_base + preferredAddress - kPreferredImageBase);
  } else {
    return static_cast<T>(g_base + preferredAddress - kPreferredImageBase);
  }
}

#include "ReadableRegionCache.h"

bool IsReadable(uintptr_t address, size_t bytes) {
  if (address == 0 || bytes == 0) return false;
  if (g_readableRegionCache && g_readableRegionCache->Contains(address, bytes)) return true;
  MEMORY_BASIC_INFORMATION info{};
  if (VirtualQuery(reinterpret_cast<void *>(address), &info, sizeof(info)) == 0)
    return false;
  if (info.State != MEM_COMMIT || (info.Protect & (PAGE_NOACCESS | PAGE_GUARD)))
    return false;
  const uintptr_t end = address + bytes;
  const uintptr_t regionEnd = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
  const bool readable = end >= address && end <= regionEnd;
  if (readable && g_readableRegionCache) g_readableRegionCache->Remember(info);
  return readable;
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
int LuaType(void *L, int index) { return At<LuaTypeFn>(kLuaType)(L, index); }
bool LuaIsNumber(void *L, int index) { return At<LuaIsNumberFn>(kLuaIsNumber)(L, index) != 0; }
double LuaToNumber(void *L, int index) { return At<LuaToNumberFn>(kLuaToNumber)(L, index); }
const char *LuaToString(void *L, int index) { return At<LuaToStringFn>(kLuaToString)(L, index); }
void LuaPushNil(void *L) { At<LuaPushNilFn>(kLuaPushNil)(L); }
void LuaPushNumber(void *L, double value) { At<LuaPushNumberFn>(kLuaPushNumber)(L, value); }
void LuaPushString(void *L, const char *value) { At<LuaPushStringFn>(kLuaPushString)(L, value); }
void LuaNewTable(void *L) { At<LuaNewTableFn>(kLuaNewTable)(L); }
void LuaRawSetI(void *L, int tableIndex, int key) { At<LuaRawSetIFn>(kLuaRawSetI)(L, tableIndex, key); }

void *ResolveLuaObject(void *L, int index) {
  At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L, index, 0);
  void *object = At<FrameScriptGetObjectFn>(kFrameScriptGetObject)(L, -1);
  At<LuaSetTopFn>(kLuaSetTop)(L, -2);
  return object;
}

struct FontVertexPages {
  struct Page { float *vertices; int count; } pages[kTextNodePageCount]{};
  int used = 0;
  size_t vertices = 0;
};

FontVertexPages ReadFontVertexPages(void *node) {
  FontVertexPages result{};
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
    result.pages[result.used++] = {verts, count};
    result.vertices += static_cast<size_t>(count);
  }
  return result;
}

template <typename Fn>
void ForEachFontVertex(const FontVertexPages &pages, Fn fn) {
  for (int page = 0; page < pages.used; ++page)
    for (int i = 0; i < pages.pages[page].count; ++i)
      fn(pages.pages[page].vertices + i * kTextVertStrideFloats);
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

void ResizeFontPositions(std::vector<float> &positions, size_t count) {
  // Reuse ordinary damage-text buffers, but release unusually large capacity
  // when a pooled font returns to short text (128 KiB per retained buffer).
  constexpr size_t retainedFloats = 32768;
  if (positions.capacity() > retainedFloats && count <= retainedFloats) {
    std::vector<float> compact(count);
    positions.swap(compact);
  } else {
    positions.resize(count);
  }
}

void ReadFontPositions(const FontVertexPages &pages, std::vector<float> &positions) {
  ResizeFontPositions(positions, pages.vertices * 2);
  size_t index = 0;
  ForEachFontVertex(pages, [&](float *vertex) {
    positions[index++] = vertex[0];
    positions[index++] = vertex[1];
  });
}

void WriteFontPositions(const FontVertexPages &pages, const std::vector<float> &positions) {
  size_t index = 0;
  ForEachFontVertex(pages, [&](float *vertex) {
    if (index + 1 < positions.size()) {
      vertex[0] = positions[index++];
      vertex[1] = positions[index++];
    }
  });
}

bool SameFontPositions(const FontVertexPages &pages, const std::vector<float> &positions) {
  if (pages.vertices * 2 != positions.size()) return false;
  size_t index = 0;
  bool same = true;
  ForEachFontVertex(pages, [&](float *vertex) {
    if (std::fabs(vertex[0] - positions[index++]) > 0.0001f) same = false;
    if (std::fabs(vertex[1] - positions[index++]) > 0.0001f) same = false;
  });
  return same;
}

void ForgetFontTrapezoid(void *fontString) {
  auto state = g_fontStates.find(fontString);
  if (state != g_fontStates.end()) {
    auto owner = g_nodeOwners.find(state->second.node);
    if (owner != g_nodeOwners.end() && owner->second == fontString)
      g_nodeOwners.erase(owner);
  }
  g_fontStates.erase(fontString);
}

bool SetFontTrapezoid(void *fontString, float amount) {
  void *node = FontStringNode(fontString);
  if (!node) return false;

  // Validate page descriptors once per operation. No client code runs between
  // the following passes, so they can reuse these stack-owned page views.
  const FontVertexPages pages = ReadFontVertexPages(node);
  if (!pages.vertices) return false;
  auto &state = g_fontStates[fontString];
  if (state.node != node) {
    auto owner = g_nodeOwners.find(state.node);
    if (owner != g_nodeOwners.end() && owner->second == fontString)
      g_nodeOwners.erase(owner);
    state.baseline.clear();
    state.warped.clear();
    state.node = node;
  }
  g_nodeOwners[node] = fontString;
  if (!state.baseline.empty() && SameFontPositions(pages, state.warped)) {
    if (state.amount == amount && std::fabs(amount) >= 0.0001f) return true;
    WriteFontPositions(pages, state.baseline);
  } else {
    ReadFontPositions(pages, state.baseline);
  }

  if (std::fabs(amount) < 0.0001f) {
    ForgetFontTrapezoid(fontString);
    return true;
  }
  state.amount = amount;

  float minX = 0.0f, maxX = 0.0f, minY = 0.0f, maxY = 0.0f;
  bool first = true;
  ForEachFontVertex(pages, [&](float *vertex) {
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
  ResizeFontPositions(state.warped, pages.vertices * 2);
  size_t index = 0;
  ForEachFontVertex(pages, [&](float *vertex) {
    const float vertical = (vertex[1] - minY) / height;
    const float scale = 1.0f + amount * (vertical * 2.0f - 1.0f);
    vertex[0] = centerX + (vertex[0] - centerX) * scale;
    state.warped[index++] = vertex[0];
    state.warped[index++] = vertex[1];
  });
  return true;
}

void __fastcall TextDrawBuilderHook(void *node) {
  g_textDrawBuilderOriginal(node);
  if (g_nodeOwners.empty()) return;
  auto owner = g_nodeOwners.find(node);
  if (owner == g_nodeOwners.end()) return;
  void *fontString = owner->second;
  auto state = g_fontStates.find(fontString);
  if (state == g_fontStates.end() || FontStringNode(fontString) != node) {
    ForgetFontTrapezoid(fontString);
    return;
  }
  SetFontTrapezoid(fontString, state->second.amount);
}

void __fastcall DeviceSetTextureHook(void *device, void * /*edx*/, void *tex) {
  if (!tex) return;
  __try {
    const uintptr_t texAddr = reinterpret_cast<uintptr_t>(tex);
    if (!IsReadable(texAddr, 0x50)) return;

    const uintptr_t callback = *reinterpret_cast<const uintptr_t *>(texAddr + 0x44);
    if (callback != 0 && callback < 0x00400000) {
      return;
    }

    const uint32_t width = *reinterpret_cast<const uint32_t *>(texAddr + 0x24);
    const uint32_t height = *reinterpret_cast<const uint32_t *>(texAddr + 0x28);
    if (width > 8192 || height > 8192) {
      return;
    }

    g_deviceSetTextureOriginal(device, tex);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return;
  }
}

void __fastcall PrepareTextureHook(void *device, void * /*edx*/, void *tex) {
  if (!tex) return;
  __try {
    const uintptr_t texAddr = reinterpret_cast<uintptr_t>(tex);
    if (!IsReadable(texAddr, 0x50)) return;

    const uintptr_t callback = *reinterpret_cast<const uintptr_t *>(texAddr + 0x44);
    if (callback != 0 && callback < 0x00400000) {
      return;
    }

    const uint32_t width = *reinterpret_cast<const uint32_t *>(texAddr + 0x24);
    const uint32_t height = *reinterpret_cast<const uint32_t *>(texAddr + 0x28);
    if (width > 8192 || height > 8192) {
      return;
    }

    g_prepareTextureOriginal(device, tex);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return;
  }
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

bool GcControlAvailable() {
  // Verify the installed client's public API, including the conditional tail
  // call to full GC. A patched/detoured entry disables this optional feature.
  static const uint8_t countBytes[] = {0x8B,0x41,0x10,0x8B,0x40,0x28,0xC1,0xE8,0x0A,0xC3};
  static const uint8_t thresholdBytes[] = {0x8B,0x41,0x10,0x8B,0x40,0x24,0xC1,0xE8,0x0A,0xC3};
  static const uint8_t setterBytes[] = {
    0x81,0xFA,0xFF,0xFF,0x3F,0x00,0x8B,0x41,0x10,0x76,0x09,0xC7,0x40,0x24,
    0xFF,0xFF,0xFF,0xFF,0xEB,0x06,0xC1,0xE2,0x0A,0x89,0x50,0x24,0x8B,0x41,
    0x10,0x8B,0x50,0x28,0x3B,0x50,0x24,0x72,0x05,0xE9,0x16,0x2F,0x00,0x00,0xC3};
  return IsReadable(At<uintptr_t>(kLuaGetGCCount), sizeof(countBytes)) &&
    IsReadable(At<uintptr_t>(kLuaGetGCThreshold), sizeof(thresholdBytes)) &&
    IsReadable(At<uintptr_t>(kLuaSetGCThreshold), sizeof(setterBytes)) &&
    std::memcmp(At<void *>(kLuaGetGCCount), countBytes, sizeof(countBytes)) == 0 &&
    std::memcmp(At<void *>(kLuaGetGCThreshold), thresholdBytes, sizeof(thresholdBytes)) == 0 &&
    std::memcmp(At<void *>(kLuaSetGCThreshold), setterBytes, sizeof(setterBytes)) == 0;
}

bool GcCombatClear() {
  if (!IsReadable(At<uintptr_t>(kInWorld), 1) || *At<const uint8_t *>(kInWorld) == 0)
    return false;
  const char *tokens[] = {"player", "pet"};
  for (size_t i = 0; i < 2; ++i) {
    const char *token = tokens[i];
    const uint64_t guid = ResolveGuid(token);
    if (!guid) { if (i == 0) return false; else continue; }
    uint32_t unit = 0;
    if (!ResolveUnit(token, unit) || !IsReadable(unit + 0x110, 4) ||
        (i == 0 && *reinterpret_cast<const int *>(unit + 0x14) != kObjectTypePlayer)) return false;
    const uint32_t fields = *reinterpret_cast<const uint32_t *>(unit + 0x110);
    if (!IsReadable(fields + 0xA0, 4) ||
        (*reinterpret_cast<const uint32_t *>(fields + 0xA0) & 0x00080000) != 0)
      return false;
  }
  return true;
}

int GcReject(void *L, const char *reason) {
  LuaPushNumber(L, 0); LuaPushString(L, reason); return 2;
}

int ScriptGcControl(void *L, const char *command) {
  if (std::strcmp(command, "gcControlVersion") == 0) {
    LuaPushNumber(L, GcControlAvailable() ? 1 : 0); return 1;
  }
  if (!GcControlAvailable()) return GcReject(L, "GC API signature mismatch");
  const uint32_t used = At<LuaGetGCFn>(kLuaGetGCCount)(L);
  const uint32_t threshold = At<LuaGetGCFn>(kLuaGetGCThreshold)(L);
  MEMORYSTATUSEX memory{}; memory.dwLength = sizeof(memory);
  if (!GlobalMemoryStatusEx(&memory)) return GcReject(L, "memory status unavailable");
  if (std::strcmp(command, "gcStatus") == 0) {
    LuaPushNumber(L, used); LuaPushNumber(L, threshold);
    LuaPushNumber(L, static_cast<double>(memory.ullAvailVirtual / 1024));
    LuaPushNumber(L, static_cast<double>(memory.ullTotalVirtual / 1024));
    LuaPushNumber(L, static_cast<double>(memory.ullAvailPageFile / 1024));
    return 5;
  }
  if (std::strcmp(command, "gcSetThreshold") == 0) {
    if (LuaGetTop(L) < 2 || !LuaIsNumber(L, 2)) return GcReject(L, "numeric KB threshold required");
    const double requested = LuaToNumber(L, 2);
    const char *reason = GcThresholdRejection(used, threshold, requested,
      static_cast<double>(memory.ullAvailVirtual / 1024),
      static_cast<double>(memory.ullAvailPageFile / 1024));
    if (reason) return GcReject(L, reason);
    At<LuaSetGCFn>(kLuaSetGCThreshold)(L, static_cast<uint32_t>(requested));
    LuaPushNumber(L, 1); return 1;
  }
  if (std::strcmp(command, "gcCollect") != 0) return GcReject(L, "unknown GC command");
  if (!GcCombatClear()) return GcReject(L, "player/pet combat or world state prevents collection");
  static bool collecting = false;
  if (collecting) return GcReject(L, "collection already active");
  collecting = true;
  LARGE_INTEGER frequency{}, started{}, finished{};
  QueryPerformanceFrequency(&frequency); QueryPerformanceCounter(&started);
  __try {
    At<LuaSetGCFn>(kLuaSetGCThreshold)(L, 0);
  } __finally { collecting = false; }
  QueryPerformanceCounter(&finished);
  const uint32_t after = At<LuaGetGCFn>(kLuaGetGCCount)(L);
  LuaPushNumber(L, 1);
  LuaPushNumber(L, frequency.QuadPart > 0 ?
    (finished.QuadPart - started.QuadPart) * 1000.0 / frequency.QuadPart : 0);
  LuaPushNumber(L, used > after ? used - after : 0);
  LuaPushNumber(L, after);
  LuaPushNumber(L, At<LuaGetGCFn>(kLuaGetGCThreshold)(L));
  return 5;
}

bool ReadNativeEntry(uintptr_t address, void *out, size_t size) {
  __try {
    if (!IsReadable(address, size)) return false;
    std::memcpy(out, reinterpret_cast<const void *>(address), size); return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
bool NativeEntryExecutable(uintptr_t address, size_t size) {
  MEMORY_BASIC_INFORMATION info{};
  return IsReadable(address, size) && VirtualQuery(reinterpret_cast<void *>(address), &info, sizeof(info)) &&
    (info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY));
}
NativeEntryModule KnownNampowerModule() {
  const uintptr_t base = reinterpret_cast<uintptr_t>(GetModuleHandleW(L"nampower.dll"));
  IMAGE_DOS_HEADER dos{}; IMAGE_NT_HEADERS32 nt{};
  // Installed Nampower 4.6.2: pin the inspected image, not any DLL with this name.
  if (!ReadNativeEntry(base, &dos, sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE ||
      dos.e_lfanew < 0 || dos.e_lfanew > 0x100000 ||
      !ReadNativeEntry(base + dos.e_lfanew, &nt, sizeof(nt)) || nt.Signature != IMAGE_NT_SIGNATURE ||
      nt.FileHeader.Machine != IMAGE_FILE_MACHINE_I386 || nt.FileHeader.TimeDateStamp != 0x6A99D431 ||
      nt.OptionalHeader.SizeOfImage != 0xDB000) return {};
  return {base, nt.OptionalHeader.SizeOfImage};
}
NativeEntryResult InspectNativeEntry(uintptr_t preferred, const uint8_t *prefix, size_t size) {
  return VerifyNativeEntry(At<uintptr_t>(preferred), prefix, size, KnownNampowerModule(),
      {&ReadNativeEntry, &NativeEntryExecutable});
}

bool CheckPetCommandBridge(const char *&detail) {
  // Fail closed for unknown changes; preserve the verified Nampower hook chain.
  // Byte-verified against the installed 1.12.1.5875 PetAttack dispatcher.
  static const uint8_t prefix[] = {
      0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x40, 0x53, 0x56, 0x57, 0x8B, 0xF9,
      0xB9, 0x02, 0x00, 0x00, 0x00, 0x8B, 0xF2, 0x89, 0x7D, 0xFC};
  if (!CompatibleClient()) { detail = "unsupported client image"; return false; }
  const auto result = InspectNativeEntry(kPetCommandDispatch, prefix, sizeof(prefix));
  detail = NativeEntryDescription(result);
  if (!NativeEntryAccepted(result)) return false;
  if (!IsReadable(At<uintptr_t>(kFrameScriptContext), sizeof(uint32_t)) ||
      !IsReadable(At<uintptr_t>(kFrameScriptDepth), sizeof(uint32_t)) ||
      !IsReadable(At<uintptr_t>(kInWorld), sizeof(uint8_t))) {
    detail = "client context unavailable"; return false;
  }
  return true;
}
bool PetCommandBridgeAvailable() {
  const char *detail = nullptr; return CheckPetCommandBridge(detail);
}

bool LivingUnit(uint32_t unit) {
  if (!IsReadable(unit + 0x110, sizeof(uint32_t))) return false;
  const uint32_t descriptor = *reinterpret_cast<const uint32_t *>(unit + 0x110);
  return descriptor != 0 && IsReadable(descriptor + 0x40, sizeof(uint32_t)) &&
         *reinterpret_cast<const uint32_t *>(descriptor + 0x40) != 0;
}

bool SafePetCommand(const char *command, const char *identifier,
                    const char *&reason) {
  // A small allowlist, never a caller-supplied opcode or arbitrary script.
  uint32_t opcode = 0;
  if (!command) { reason = "missing pet command"; return false; }
  if (std::strcmp(command, "attack") == 0) opcode = 0x07000002;
  else if (std::strcmp(command, "follow") == 0) opcode = 0x07000001;
  else if (std::strcmp(command, "stay") == 0) opcode = 0x07000000;
  else if (std::strcmp(command, "passive") == 0) opcode = 0x06000000;
  else { reason = "unsupported pet command"; return false; }
  __try {
    if (!PetCommandBridgeAvailable()) {
      reason = "unsupported pet command dispatcher"; return false;
    }
    if (*At<const uint8_t *>(kInWorld) == 0) {
      reason = "not in world"; return false;
    }
    uint32_t pet = 0;
    if (!ResolveUnit("pet", pet) || !LivingUnit(pet)) {
      reason = "no living active pet"; return false;
    }
    uint64_t victim = 0;
    if (opcode == 0x07000002) {
      uint32_t target = 0;
      victim = ResolveGuid(identifier);
      if (!victim || !ResolveUnit(identifier, target) || !LivingUnit(target) ||
          target == pet || victim == ResolveGuid("player")) {
        reason = "invalid pet attack target"; return false;
      }
    }
    const bool submitted = DispatchScopedPetCommand(
        At<PetCommandDispatchFn>(kPetCommandDispatch),
        At<uint32_t *>(kFrameScriptContext), At<uint32_t *>(kFrameScriptDepth),
        &g_petCommandBusy, opcode, victim);
    if (!submitted) reason = "pet dispatcher busy or native exception";
    return submitted;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    reason = "native pet command validation exception";
    return false;
  }
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
  return height;
}

bool UnitNameplatePosition(uint32_t unit, Vec3 &position) {
  // CGUnit's name attachment, not its collision-box eye point. The client's
  // nameplate projection (0x60F7F0) calls 0x608640 and adds this clearance
  // before WorldToScreen. Read it before any CGNamePlateFrame collision work.
  if (!IsReadable(unit, 0x114)) return false;
  const uint32_t fields = *reinterpret_cast<uint32_t *>(unit + 0x110);
  const uint32_t model = *reinterpret_cast<uint32_t *>(unit + 0xD8);
  if (!fields || !model || !IsReadable(fields + 0x1FC, 4) ||
      !IsReadable(model, 4) ||
      !IsReadable(At<uintptr_t>(kUnitGetNamePosition), 1) ||
      !IsReadable(At<uintptr_t>(kNameplateWorldClearance), 4)) return false;
  __try {
    At<UnitGetPositionFn>(kUnitGetNamePosition)(unit, &position);
    position.z += *At<const float *>(kNameplateWorldClearance);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
  return std::isfinite(position.x) && std::isfinite(position.y) &&
         std::isfinite(position.z);
}

struct NearbyCreature {
  uint64_t guid = 0;
  float dist = 0.0f;
};

struct NearbyCtx {
  Vec3 refPos{};
  float maxDistSq = 0.0f;
  std::vector<NearbyCreature> &results;
};

// A query swaps cached capacity into its private vector through Lua output.
// GC/finalizer reentry can then borrow other storage without changing it.
thread_local std::vector<NearbyCreature> g_nearbyScratch;
thread_local bool g_nearbyBusy = false;
constexpr size_t kNearbyRetainedLimit = 4096;
uint64_t g_nearbyLegacyCalls = 0, g_nearbyBufferCalls = 0;
uint64_t g_nearbyGrowths = 0;

int __fastcall EnumCreaturesCallback(NearbyCtx *ctx, void * /*unusedEdx*/, uint64_t guid) {
  if (!ctx) return 0;
  // Creature GUID high 16 bits = 0xF130
  if (((guid >> 48) & 0xFFFF) != 0xF130) return 1;
  uint32_t unit = At<GetObjectByGuidFn>(kGetObjectByGuid)(guid);
  if (!unit) return 1;
  Vec3 pos{};
  if (!UnitPosition(unit, pos)) return 1;
  const float dx = pos.x - ctx->refPos.x;
  const float dy = pos.y - ctx->refPos.y;
  const float dz = pos.z - ctx->refPos.z;
  const float distSq = dx * dx + dy * dy + dz * dz;
  if (distSq <= ctx->maxDistSq) {
    ctx->results.push_back({guid, std::sqrt(distSq)});
  }
  return 1;
}

bool SafeEnumVisible(EnumVisibleCallbackFn cb, void *ctx) {
  __try {
    At<EnumVisibleObjectsFn>(kEnumVisibleObjects)(cb, ctx);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

#include "GatherObjects.h"

// Read-only 1.12.1 UpdateFields. CGObject +0x08 is the base descriptor,
// including OBJECT_FIELD_GUID; never confuse it with CGUnit's +0x110 block.
struct GroundObject {
  uint64_t guid = 0;
  Vec3 position{};
  uint32_t type = 0, id = 0, state = 0;
};

bool ReadOwnGroundObject(uint64_t guid, uint64_t owner, GroundObject &result) {
  __try {
    const uint32_t object = At<GetObjectByGuidFn>(kGetObjectByGuid)(guid);
    if (!owner || !IsReadable(object, 0x18)) return false;
    const uint32_t type = *reinterpret_cast<const uint32_t *>(object + 0x14);
    if (type != 5 && type != 6) return false;
    const uint32_t fields = *reinterpret_cast<const uint32_t *>(object + 0x08);
    const size_t size = type == 5 ? 0x68 : 0x40;
    if (!fields || !IsReadable(fields, size) ||
        *reinterpret_cast<const uint64_t *>(fields) != guid ||
        *reinterpret_cast<const uint64_t *>(fields + 0x18) != owner) return false;
    // GO type 6 is a trap. Dynamic objects carry the generating spell ID.
    if (type == 5 && *reinterpret_cast<const uint32_t *>(fields + 0x54) != 6) return false;
    result.guid = guid; result.type = type;
    result.id = *reinterpret_cast<const uint32_t *>(fields + (type == 5 ? 0x0C : 0x24));
    result.state = type == 5 ? *reinterpret_cast<const uint32_t *>(fields + 0x38) : 0;
    const uintptr_t position = fields + (type == 5 ? 0x3C : 0x2C);
    result.position = *reinterpret_cast<const Vec3 *>(position);
    return std::isfinite(result.position.x) && std::isfinite(result.position.y) &&
           std::isfinite(result.position.z) && result.id != 0;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

struct GroundQuery {
  uint64_t owner = 0, exclude = 0;
  uint32_t type = 0, id = 0;
  GroundObject result{};
};
int __fastcall EnumGroundObject(GroundQuery *query, void *, uint64_t guid) {
  if (!query || guid == query->exclude) return 1;
  GroundObject object{};
  if (!ReadOwnGroundObject(guid, query->owner, object) || object.type != query->type || object.id != query->id) return 1;
  query->result = object;
  return 0;
}

bool UnitFacing(uint32_t unit, float &facing) {
  __try {
    if (!IsReadable(unit + 0x9C4, sizeof(float))) return false;
    facing = *reinterpret_cast<const float *>(unit + 0x9C4);
    return std::isfinite(facing) && facing >= -0.01f && facing <= 6.30f;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

bool SafeSetTarget(const uint64_t *guid) {
  __try {
    At<SetTargetByGuidFn>(kSetTargetByGuid)(guid);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}

char SafeIntersect(const Vec3 *start, const Vec3 *end, Vec3 *hit, float *t, uint32_t flags) {
  __try {
    return At<IntersectFn>(kCWorldIntersect)(start, end, 0, hit, t, flags);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

#include "PetRearPosition.h"

int DoNearbyCreatures(void *L, float maxRange, const char *centerToken, bool reuse = false) {
  // Reusable output is an ordinary dense Lua array, never a retained native
  // reference into the Lua heap. Validate before raw array writes.
  if ((reuse && (LuaGetTop(L) < 4 || LuaType(L, 4) != 5)) || g_nearbyBusy ||
      !std::isfinite(maxRange) || maxRange < 0.0f) {
    LuaPushNil(L);
    return 1;
  }
  uint32_t centerUnit = 0;
  Vec3 centerPos{};
  if (!ResolveUnit(centerToken, centerUnit) || !UnitPosition(centerUnit, centerPos)) {
    LuaPushNil(L);
    return 1;
  }

  const int previousCount = reuse ? At<LuaLGetNFn>(kLuaLGetN)(L, 4) : 0;
  // Avoid unbounded work on a malformed/sparse caller-owned buffer.
  if (previousCount < 0 || previousCount > 1000000) {
    LuaPushNil(L);
    return 1;
  }
  // Keep a private result vector until Lua output is finished. A second query
  // can be entered by a Lua finalizer while a GUID string is being pushed.
  std::vector<NearbyCreature> results;
  results.swap(g_nearbyScratch);
  results.clear();
  const size_t oldCapacity = results.capacity();
  NearbyCtx ctx{centerPos, maxRange * maxRange, results};
  g_nearbyBusy = true;
  if (!SafeEnumVisible(reinterpret_cast<EnumVisibleCallbackFn>(&EnumCreaturesCallback), &ctx)) {
    g_nearbyBusy = false;
    if (results.capacity() <= kNearbyRetainedLimit) results.swap(g_nearbyScratch);
    LuaPushNil(L);
    return 1;
  }

  std::sort(ctx.results.begin(), ctx.results.end(),
            [](const NearbyCreature &a, const NearbyCreature &b) {
              return a.dist < b.dist;
            });
  g_nearbyBusy = false;
  if (results.capacity() > oldCapacity) ++g_nearbyGrowths;
  if (reuse) ++g_nearbyBufferCalls;
  else { ++g_nearbyLegacyCalls; LuaNewTable(L); }
  const int outputIndex = reuse ? 4 : LuaGetTop(L);
  char guidStr[24];
  for (size_t i = 0; i < ctx.results.size(); ++i) {
    std::snprintf(guidStr, sizeof(guidStr), "0x%016llX", ctx.results[i].guid);
    LuaPushString(L, guidStr);
    LuaRawSetI(L, outputIndex, static_cast<int>(i + 1));
  }
  if (reuse) {
    for (int i = static_cast<int>(results.size()) + 1; i <= previousCount; ++i) {
      LuaPushNil(L);
      LuaRawSetI(L, outputIndex, i);
    }
    // Lua 5.0 table.getn can use an out-of-band size; raw writes alone do not
    // update it. This is the verified client luaL_setn ABI, not Lua 5.1 objlen.
    At<LuaLSetNFn>(kLuaLSetN)(L, outputIndex, static_cast<int>(results.size()));
    LuaPushNumber(L, static_cast<double>(results.size()));
  }
  if (results.capacity() <= kNearbyRetainedLimit && g_nearbyScratch.empty())
    results.swap(g_nearbyScratch);
  return 1;
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

struct ProjectionViewport {
  uint32_t frame = 0;
  float left = 0.0f;
  float bottom = 0.0f;
};

bool ReadProjectionViewport(ProjectionViewport &viewport) {
  viewport.frame = *At<uint32_t *>(kWorldFrame);
  if (!viewport.frame || !IsReadable(viewport.frame + 0x3A0, 9)) return false;
  viewport.left = *reinterpret_cast<const float *>(viewport.frame + 0x3A4);
  viewport.bottom = *reinterpret_cast<const float *>(viewport.frame + 0x3A0);
  return true;
}

bool ProjectWorldWithCamera(const Vec3 &world, const Vec3 &camera,
                            const Vec3 &forward, ProjectionResult &result,
                            const ProjectionViewport *capturedViewport = nullptr) {
  ProjectionViewport localViewport{};
  if (!capturedViewport) {
    if (!ReadProjectionViewport(localViewport)) return false;
    capturedViewport = &localViewport;
  }
  const uint32_t worldFrame = capturedViewport->frame;

  Vec3 input = world;
  Vec3 projected{};
  if (!At<WorldToScreenFn>(kWorldToScreen)(worldFrame, &input.x, &projected.x))
    return false;

  result.ddcX = projected.x;
  result.ddcY = projected.y;
  result.ndcX = -1.0f;
  result.ndcY = -1.0f;
  At<DdcToNdcFn>(kDdcToNdc)(&result.ndcX, &result.ndcY,
                             result.ddcX, result.ddcY);
  result.screenX = capturedViewport->left + result.ndcX;
  result.screenY = capturedViewport->bottom + result.ndcY;
  result.depth = (world.x - camera.x) * forward.x +
                 (world.y - camera.y) * forward.y +
                 (world.z - camera.z) * forward.z;
  return std::isfinite(result.ddcX) && std::isfinite(result.ddcY) &&
         std::isfinite(result.ndcX) && std::isfinite(result.ndcY) &&
         std::isfinite(result.screenX) && std::isfinite(result.screenY) &&
         std::isfinite(result.depth) && result.depth > 0.001f;
}

bool ProjectWorld(const Vec3 &world, float &x, float &y, float &depth) {
  Vec3 camera{}, forward{}, right{}, up{};
  float fov = 0.0f, aspect = 0.0f;
  if (!CameraState(camera, forward, right, up, fov, aspect)) return false;
  ProjectionResult result{};
  if (!ProjectWorldWithCamera(world, camera, forward, result)) return false;
  x = result.screenX;
  y = result.screenY;
  depth = result.depth;
  return true;
}

#include "NameplateBatch.h"
#include "NameplateValidatedBatch.h"
#include "NameplateSight.h"

bool SunLight(Vec3 &lightDir, float &diffuseR, float &diffuseG, float &diffuseB,
              float &ambientR, float &ambientG, float &ambientB) {
  if (!IsReadable(kLightDiffuse, 0x50)) return false;

  const float *dir = reinterpret_cast<const float *>(kLightDirection);
  const float *diff = reinterpret_cast<const float *>(kLightDiffuse);
  const float *amb = reinterpret_cast<const float *>(kLightAmbient);

  float dx = dir[0];
  float dy = dir[1];
  float dz = dir[2];

  float lenSq = (std::isfinite(dx) && std::isfinite(dy) && std::isfinite(dz))
                    ? (dx * dx + dy * dy + dz * dz)
                    : 0.0f;
  if (lenSq < 0.0001f || lenSq > 10.0f) {
    // Standard outdoor sun fallback (high sky, slightly south-east)
    dx = -0.3f;
    dy = 0.5f;
    dz = -0.8f;
    lenSq = dx * dx + dy * dy + dz * dz;
  }

  const float invLen = 1.0f / std::sqrt(lenSq);
  // Direct3D Direction is the vector light travels TOWARDS the scene.
  // The vector pointing FROM the scene TOWARDS the sun/moon is -Direction.
  lightDir.x = -dx * invLen;
  lightDir.y = -dy * invLen;
  lightDir.z = -dz * invLen;

  diffuseR = (std::isfinite(diff[0]) && diff[0] >= 0.0f) ? diff[0] : 1.0f;
  diffuseG = (std::isfinite(diff[1]) && diff[1] >= 0.0f) ? diff[1] : 1.0f;
  diffuseB = (std::isfinite(diff[2]) && diff[2] >= 0.0f) ? diff[2] : 1.0f;

  ambientR = (std::isfinite(amb[0]) && amb[0] >= 0.0f) ? amb[0] : 0.4f;
  ambientG = (std::isfinite(amb[1]) && amb[1] >= 0.0f) ? amb[1] : 0.4f;
  ambientB = (std::isfinite(amb[2]) && amb[2] >= 0.0f) ? amb[2] : 0.4f;

  return true;
}

struct CooldownNode {
  void *prev;                 // +0x00
  CooldownNode *next;         // +0x04
  uint32_t spellId;           // +0x08
  uint32_t itemId;            // +0x0C
  uint32_t startTime;         // +0x10 (ms)
  uint32_t spellDuration;     // +0x14 (ms)
  uint32_t category;          // +0x18
  uint32_t categoryStart;     // +0x1C (ms)
  uint32_t categoryDuration;  // +0x20 (ms)
  uint8_t  isGCD;             // +0x24
  uint8_t  pad[3];            // +0x25
  uint32_t gcdCategory;       // +0x28
  uint32_t gcdDuration;       // +0x2C (ms)
};

struct CooldownQuery {
  float remaining = 0.0f;
  float duration = 0.0f;
  float startTime = 0.0f;
  float gcdRemaining = 0.0f;
  int isCategory = 0;
};

uint32_t FindSpellIdByName(const char *name) {
  if (!name || name[0] == '\0') return 0;

  std::string cleanName = name;
  size_t paren = cleanName.find('(');
  if (paren != std::string::npos) {
    cleanName = cleanName.substr(0, paren);
    while (!cleanName.empty() && (cleanName.back() == ' ' || cleanName.back() == '\t')) {
      cleanName.pop_back();
    }
  }
  if (cleanName.empty()) return 0;

  const uintptr_t maxIdAddr = At<uintptr_t>(kSpellDbcMaxId);
  if (!IsReadable(maxIdAddr, sizeof(uint32_t))) return 0;
  const uint32_t maxId = *reinterpret_cast<const uint32_t *>(maxIdAddr);

  const uintptr_t spellTableAddr = At<uintptr_t>(kSpellDbcRecords);
  if (!IsReadable(spellTableAddr, sizeof(uintptr_t))) return 0;
  uint32_t **spellTable = *reinterpret_cast<uint32_t ***>(spellTableAddr);
  if (!spellTable) return 0;

  const uintptr_t localeAddr = At<uintptr_t>(kLocale);
  const uint32_t locale = IsReadable(localeAddr, sizeof(uint32_t))
                              ? *reinterpret_cast<const uint32_t *>(localeAddr)
                              : 0;

  auto matchesName = [&](uint32_t id) -> bool {
    if (id == 0 || id > maxId) return false;
    if (!IsReadable(reinterpret_cast<uintptr_t>(&spellTable[id]), sizeof(uint32_t *))) return false;
    if (!spellTable[id]) return false;
    uint8_t *rec = reinterpret_cast<uint8_t *>(spellTable[id]);
    if (!IsReadable(reinterpret_cast<uintptr_t>(rec), 0x220)) return false;
    const char *sName = *reinterpret_cast<const char **>(rec + 0x1e0 + locale * 4);
    if (!sName || !IsReadable(reinterpret_cast<uintptr_t>(sName), 1)) return false;
    return _stricmp(sName, cleanName.c_str()) == 0;
  };

  const uintptr_t playerBook = At<uintptr_t>(kPlayerSpellbook);
  if (IsReadable(playerBook, 1024 * sizeof(uint32_t))) {
    const uint32_t *book = reinterpret_cast<const uint32_t *>(playerBook);
    uint32_t bestId = 0;
    for (int i = 1; i < 1024; ++i) {
      if (matchesName(book[i])) {
        bestId = book[i];
      }
    }
    if (bestId > 0) return bestId;
  }

  const uintptr_t petBook = At<uintptr_t>(kPetSpellbook);
  if (IsReadable(petBook, 1024 * sizeof(uint32_t))) {
    const uint32_t *book = reinterpret_cast<const uint32_t *>(petBook);
    uint32_t bestId = 0;
    for (int i = 1; i < 1024; ++i) {
      if (matchesName(book[i])) {
        bestId = book[i];
      }
    }
    if (bestId > 0) return bestId;
  }

  uint32_t fallbackId = 0;
  for (uint32_t id = 1; id <= maxId; ++id) {
    if (matchesName(id)) {
      fallbackId = id;
    }
  }
  return fallbackId;
}

float QueryActiveGcd() {
  const auto getTick = At<GetTickCountFn>(kGetTickCount);
  const uint32_t currentTick = getTick ? getTick() : 0;
  const uintptr_t mgr = At<uintptr_t>(kCooldownMgrPlayer);
  if (!mgr || !IsReadable(mgr, 16)) return 0.0f;

  CooldownNode *head = *reinterpret_cast<CooldownNode **>(mgr + 8);
  int32_t bestGcd = 0;
  for (CooldownNode *node = head;
       node != nullptr && ((reinterpret_cast<uintptr_t>(node) & 1) == 0);
       node = node->next) {
    if (!IsReadable(reinterpret_cast<uintptr_t>(node), sizeof(CooldownNode))) break;
    if (node->gcdDuration > 0) {
      int32_t gRem = static_cast<int32_t>((node->startTime + node->gcdDuration) - currentTick);
      if (gRem > bestGcd) bestGcd = gRem;
    }
  }
  return bestGcd > 0 ? (static_cast<float>(bestGcd) / 1000.0f) : 0.0f;
}

bool QuerySpellCooldown(uint32_t spellId, CooldownQuery &out) {
  if (spellId == 0) return false;

  const uintptr_t maxIdAddr = At<uintptr_t>(kSpellDbcMaxId);
  if (!IsReadable(maxIdAddr, sizeof(uint32_t))) return false;
  const uint32_t maxId = *reinterpret_cast<const uint32_t *>(maxIdAddr);

  const uintptr_t spellTableAddr = At<uintptr_t>(kSpellDbcRecords);
  if (!IsReadable(spellTableAddr, sizeof(uintptr_t))) return false;
  uint32_t **spellTable = *reinterpret_cast<uint32_t ***>(spellTableAddr);
  if (!spellTable || spellId > maxId) return false;
  if (!IsReadable(reinterpret_cast<uintptr_t>(&spellTable[spellId]), sizeof(uint32_t *)))
    return false;
  if (!spellTable[spellId]) return false;

  uint8_t *rec = reinterpret_cast<uint8_t *>(spellTable[spellId]);
  if (!IsReadable(reinterpret_cast<uintptr_t>(rec), 0x280)) return false;

  const uint32_t category = *reinterpret_cast<const uint32_t *>(rec + 8);

  const auto getTick = At<GetTickCountFn>(kGetTickCount);
  const uint32_t currentTick = getTick ? getTick() : 0;

  const uintptr_t managers[] = {
      At<uintptr_t>(kCooldownMgrPlayer),
      At<uintptr_t>(kCooldownMgrPet)
  };

  int32_t bestRem = 0;
  uint32_t bestDur = 0;
  uint32_t bestStart = 0;
  int isCat = 0;
  int32_t bestGcdRem = 0;

  for (uintptr_t mgr : managers) {
    if (!mgr || !IsReadable(mgr, 16)) continue;
    CooldownNode *head = *reinterpret_cast<CooldownNode **>(mgr + 8);
    for (CooldownNode *node = head;
         node != nullptr && ((reinterpret_cast<uintptr_t>(node) & 1) == 0);
         node = node->next) {
      if (!IsReadable(reinterpret_cast<uintptr_t>(node), sizeof(CooldownNode)))
        break;

      if (node->gcdDuration > 0) {
        int32_t gRem = static_cast<int32_t>((node->startTime + node->gcdDuration) - currentTick);
        if (gRem > bestGcdRem) bestGcdRem = gRem;
      }

      if (node->spellId == spellId && node->itemId == 0) {
        if (node->spellDuration > 0) {
          int32_t rem = static_cast<int32_t>((node->startTime + node->spellDuration) - currentTick);
          if (rem > bestRem) {
            bestRem = rem;
            bestDur = node->spellDuration;
            bestStart = node->startTime;
            isCat = 0;
          }
        }
      }

      if (category > 0 && node->category == category) {
        if (node->categoryDuration > 0) {
          int32_t catRem = static_cast<int32_t>((node->categoryStart + node->categoryDuration) - currentTick);
          if (catRem > bestRem) {
            bestRem = catRem;
            bestDur = node->categoryDuration;
            bestStart = node->categoryStart;
            isCat = 1;
          }
        }
      }
    }
  }

  if (bestRem > 0) {
    out.remaining = static_cast<float>(bestRem) / 1000.0f;
    out.duration = static_cast<float>(bestDur) / 1000.0f;
    out.startTime = static_cast<float>(bestStart) / 1000.0f;
    out.isCategory = isCat;
  } else {
    out.remaining = 0.0f;
    out.duration = 0.0f;
    out.startTime = 0.0f;
    out.isCategory = 0;
  }

  out.gcdRemaining = bestGcdRem > 0 ? (static_cast<float>(bestGcdRem) / 1000.0f) : 0.0f;
  return true;
}

bool QueryItemCooldown(uint32_t itemId, CooldownQuery &out) {
  if (itemId == 0) return false;

  const auto getTick = At<GetTickCountFn>(kGetTickCount);
  const uint32_t currentTick = getTick ? getTick() : 0;

  const uintptr_t mgr = At<uintptr_t>(kCooldownMgrPlayer);
  if (!mgr || !IsReadable(mgr, 16)) return false;

  CooldownNode *head = *reinterpret_cast<CooldownNode **>(mgr + 8);
  int32_t bestRem = 0;
  uint32_t bestDur = 0;
  uint32_t bestStart = 0;
  int isCat = 0;
  int32_t bestGcdRem = 0;

  for (CooldownNode *node = head;
       node != nullptr && ((reinterpret_cast<uintptr_t>(node) & 1) == 0);
       node = node->next) {
    if (!IsReadable(reinterpret_cast<uintptr_t>(node), sizeof(CooldownNode)))
      break;

    if (node->gcdDuration > 0) {
      int32_t gRem = static_cast<int32_t>((node->startTime + node->gcdDuration) - currentTick);
      if (gRem > bestGcdRem) bestGcdRem = gRem;
    }

    if (node->itemId == itemId) {
      if (node->spellDuration > 0) {
        int32_t rem = static_cast<int32_t>((node->startTime + node->spellDuration) - currentTick);
        if (rem > bestRem) {
          bestRem = rem;
          bestDur = node->spellDuration;
          bestStart = node->startTime;
          isCat = 0;
        }
      }
      if (node->categoryDuration > 0) {
        int32_t catRem = static_cast<int32_t>((node->categoryStart + node->categoryDuration) - currentTick);
        if (catRem > bestRem) {
          bestRem = catRem;
          bestDur = node->categoryDuration;
          bestStart = node->categoryStart;
          isCat = 1;
        }
      }
    }
  }

  if (bestRem > 0) {
    out.remaining = static_cast<float>(bestRem) / 1000.0f;
    out.duration = static_cast<float>(bestDur) / 1000.0f;
    out.startTime = static_cast<float>(bestStart) / 1000.0f;
    out.isCategory = isCat;
  } else {
    out.remaining = 0.0f;
    out.duration = 0.0f;
    out.startTime = 0.0f;
    out.isCategory = 0;
  }

  out.gcdRemaining = bestGcdRem > 0 ? (static_cast<float>(bestGcdRem) / 1000.0f) : 0.0f;
  return true;
}

int __fastcall Script_zAPI(void *L) {
  const char *command = LuaToString(L, 1);
  if (!command) {
    LuaPushNil(L);
    return 1;
  }

  if (std::strcmp(command, "version") == 0) {
    LuaPushNumber(L, 3.1);
    return 1;
  }

  if (std::strcmp(command, "nameplateBatchVersion") == 0) { LuaPushNumber(L, 1); return 1; }
  if (std::strcmp(command, "nameplateValidationVersion") == 0) { LuaPushNumber(L, 1); return 1; }
  if (std::strcmp(command, "projectNameplatesValidatedInto") == 0) return DoValidatedPlateProjections(L);
  if (std::strcmp(command, "nameplateValidationStats") == 0) {
    LuaPushNumber(L, static_cast<double>(g_validatedPlateCalls));
    LuaPushNumber(L, static_cast<double>(g_validatedPlateRows));
    LuaPushNumber(L, static_cast<double>(g_validatedPlateCurrent));
    LuaPushNumber(L, static_cast<double>(g_validatedPlateProjected));
    LuaPushNumber(L, static_cast<double>(g_validatedPlateGrowths));
    LuaPushNumber(L, static_cast<double>(g_validatedPlateScratch.capacity()));
    return 6;
  }
  if (std::strcmp(command, "nameplateSightVersion") == 0) { LuaPushNumber(L, 1); return 1; }
  if (std::strcmp(command, "nameplateSightInto") == 0) return DoNameplateSightInto(L);
  if (std::strcmp(command, "nameplateSightStats") == 0) {
    LuaPushNumber(L, static_cast<double>(g_nameplateSightCalls));
    LuaPushNumber(L, static_cast<double>(g_nameplateSightRows));
    LuaPushNumber(L, static_cast<double>(g_nameplateSightTraces));
    LuaPushNumber(L, static_cast<double>(g_nameplateSightHits));
    LuaPushNumber(L, static_cast<double>(g_nameplateSightGrowths));
    LuaPushNumber(L, static_cast<double>(g_nameplateSightScratch.capacity()));
    return 6;
  }
  if (std::strcmp(command, "projectNameplatesInto") == 0) return DoProjectNameplatesInto(L);
  if (std::strcmp(command, "nameplateBatchStats") == 0) {
    LuaPushNumber(L, static_cast<double>(g_nameplateBatchCalls));
    LuaPushNumber(L, static_cast<double>(g_nameplateBatchRows));
    LuaPushNumber(L, static_cast<double>(g_nameplateBatchGrowths));
    LuaPushNumber(L, static_cast<double>(g_nameplateBatchScratch.capacity()));
    return 4;
  }

  if (std::strcmp(command, "gcControlVersion") == 0 ||
      std::strcmp(command, "gcStatus") == 0 ||
      std::strcmp(command, "gcSetThreshold") == 0 ||
      std::strcmp(command, "gcCollect") == 0)
    return ScriptGcControl(L, command);

  if (std::strcmp(command, "nearbyBufferVersion") == 0) {
    LuaPushNumber(L, 1.0);
    return 1;
  }

  if (std::strcmp(command, "gatherBufferVersion") == 0) { LuaPushNumber(L, 1.0);return 1; }
  if (std::strcmp(command, "gatherObjectsInto") == 0) return DoGatherObjects(L);
  if (std::strcmp(command, "gatherScanStats") == 0) {
    LuaPushNumber(L, static_cast<double>(g_gatherQueries));
    LuaPushNumber(L, static_cast<double>(g_gatherScratch.capacity()));return 2;
  }

  if (std::strcmp(command, "nearbyScanStats") == 0) {
    LuaPushNumber(L, static_cast<double>(g_nearbyLegacyCalls));
    LuaPushNumber(L, static_cast<double>(g_nearbyBufferCalls));
    LuaPushNumber(L, static_cast<double>(g_nearbyGrowths));
    LuaPushNumber(L, static_cast<double>(g_nearbyScratch.capacity()));
    return 4;
  }

  if (std::strcmp(command, "petCommandVersion") == 0) {
    LuaPushNumber(L, PetCommandBridgeAvailable() ? 1.0 : 0.0);
    return 1;
  }

  if (std::strcmp(command, "petPositionVersion") == 0) {
    LuaPushNumber(L, PetPositionAvailable() ? 1 : 0); return 1;
  }
  if (std::strcmp(command, "petBridgeStatus") == 0) {
    const char *petDetail = nullptr, *positionDetail = nullptr;
    CheckPetCommandBridge(petDetail); CheckPetPositionBridge(positionDetail);
    LuaPushString(L, petDetail); LuaPushString(L, positionDetail); return 2;
  }
  if (std::strcmp(command, "petRearState") == 0 && LuaGetTop(L) >= 2) {
    PetRearState state;
    if (!ReadPetRearState(LuaToString(L, 2), state)) { LuaPushNil(L); return 1; }
    LuaPushNumber(L, state.target.x); LuaPushNumber(L, state.target.y); LuaPushNumber(L, state.target.z);
    LuaPushNumber(L, state.facing);
    LuaPushNumber(L, state.pet.x); LuaPushNumber(L, state.pet.y); LuaPushNumber(L, state.pet.z);
    LuaPushNumber(L, state.radius); LuaPushNumber(L, state.pvp ? 1 : 0); LuaPushNumber(L, state.tanking ? 1 : 0);
    return 10;
  }
  if (std::strcmp(command, "petTakePosition") == 0 && LuaGetTop(L) >= 2) {
    Vec3 point{}; const char *reason = "invalid owner position";
    const bool submitted = TakePetRearPosition(LuaToString(L, 2), point, reason);
    LuaPushNumber(L, submitted ? 1 : 0);
    if (!submitted) { LuaPushString(L, reason); return 2; }
    LuaPushNumber(L, point.x); LuaPushNumber(L, point.y); LuaPushNumber(L, point.z); return 4;
  }

  if (std::strcmp(command, "petCommand") == 0) {
    const char *reason = nullptr;
    const char *action = LuaGetTop(L) >= 2 ? LuaToString(L, 2) : nullptr;
    const char *unit = LuaGetTop(L) >= 3 ? LuaToString(L, 3) : nullptr;
    const bool submitted = SafePetCommand(action, unit, reason);
    LuaPushNumber(L, submitted ? 1.0 : 0.0);
    if (!submitted) { LuaPushString(L, reason ? reason : "pet command rejected"); return 2; }
    return 1;
  }

  if (std::strcmp(command, "status") == 0) {
    LuaPushNumber(L, static_cast<double>(g_initResult));
    LuaPushNumber(L, g_textHookInstalled ? 1.0 : 0.0);
    return 2;
  }

  if (std::strcmp(command, "spellId") == 0 && LuaGetTop(L) >= 2) {
    const char *name = LuaToString(L, 2);
    uint32_t id = FindSpellIdByName(name);
    if (id > 0) {
      LuaPushNumber(L, static_cast<double>(id));
      return 1;
    }
    LuaPushNil(L);
    return 1;
  }

  if (std::strcmp(command, "gcd") == 0) {
    LuaPushNumber(L, QueryActiveGcd());
    return 1;
  }

  if (std::strcmp(command, "cooldown") == 0 && LuaGetTop(L) >= 2) {
    CooldownQuery q{};
    bool resolved = false;

    if (LuaIsNumber(L, 2)) {
      uint32_t id = static_cast<uint32_t>(LuaToNumber(L, 2));
      if (QuerySpellCooldown(id, q)) {
        resolved = true;
      }
      if (!resolved || q.remaining == 0.0f) {
        CooldownQuery itemQ{};
        if (QueryItemCooldown(id, itemQ) && itemQ.remaining > 0.0f) {
          q = itemQ;
          resolved = true;
        }
      }
    } else {
      const char *str = LuaToString(L, 2);
      if (str && str[0] != '\0') {
        const char *itemMatch = std::strstr(str, "item:");
        if (itemMatch) {
          uint32_t itemId = static_cast<uint32_t>(std::strtoul(itemMatch + 5, nullptr, 10));
          if (itemId > 0 && QueryItemCooldown(itemId, q)) {
            resolved = true;
          }
        }
        if (!resolved) {
          uint32_t spellId = FindSpellIdByName(str);
          if (spellId > 0 && QuerySpellCooldown(spellId, q)) {
            resolved = true;
          }
        }
      }
    }

    if (!resolved) {
      float gcd = QueryActiveGcd();
      LuaPushNumber(L, 0.0);
      LuaPushNumber(L, 0.0);
      LuaPushNumber(L, 0.0);
      LuaPushNumber(L, gcd);
      LuaPushNumber(L, 0.0);
      return 5;
    }

    LuaPushNumber(L, q.remaining);
    LuaPushNumber(L, q.duration);
    LuaPushNumber(L, q.startTime);
    LuaPushNumber(L, q.gcdRemaining);
    LuaPushNumber(L, q.isCategory ? 1.0 : 0.0);
    return 5;
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
        ForgetFontTrapezoid(fontString);
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

  if (std::strcmp(command, "groundObjectVersion") == 0) {
    LuaPushNumber(L, 1.0); return 1;
  }
  if (std::strcmp(command, "groundObjectState") == 0 || std::strcmp(command, "groundObject") == 0) {
    GroundObject result{};
    const uint64_t owner = ResolveGuid("player");
    if (std::strcmp(command, "groundObjectState") == 0 && LuaGetTop(L) >= 2) {
      if (!ReadOwnGroundObject(ResolveGuid(LuaToString(L, 2)), owner, result)) result = GroundObject{};
    } else if (LuaGetTop(L) >= 3 && LuaIsNumber(L, 2) && LuaIsNumber(L, 3)) {
      GroundQuery query{}; query.owner = owner;
      query.type = static_cast<uint32_t>(LuaToNumber(L, 2));
      query.id = static_cast<uint32_t>(LuaToNumber(L, 3));
      query.exclude = LuaGetTop(L) >= 4 ? ResolveGuid(LuaToString(L, 4)) : 0;
      if ((query.type == 5 || query.type == 6) && query.id &&
          SafeEnumVisible(reinterpret_cast<EnumVisibleCallbackFn>(EnumGroundObject), &query)) result = query.result;
    }
    if (!result.guid) { LuaPushNil(L); return 1; }
    char guid[19]; std::snprintf(guid, sizeof(guid), "0x%016llX", result.guid);
    LuaPushString(L, guid);
    LuaPushNumber(L, result.position.x); LuaPushNumber(L, result.position.y); LuaPushNumber(L, result.position.z);
    LuaPushNumber(L, result.type); LuaPushNumber(L, result.id); LuaPushNumber(L, result.state);
    return 7;
  }

  if (std::strcmp(command, "losPosition") == 0 && LuaGetTop(L) >= 2) {
    uint32_t unit = 0;
    Vec3 position{};
    if (!ResolveUnit(LuaToString(L, 2), unit) || !UnitPosition(unit, position)) {
      LuaPushNil(L);
      return 1;
    }
    const float height = UnitHeight(unit);
    position.z += height;
    LuaPushNumber(L, position.x);
    LuaPushNumber(L, position.y);
    LuaPushNumber(L, position.z);
    LuaPushNumber(L, height);
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

  const bool nameplateProjection = std::strcmp(command, "projectNameplate") == 0;
  const bool forwardProjection = std::strcmp(command, "projectUnitForward") == 0;
  if ((nameplateProjection || forwardProjection || std::strcmp(command, "projectUnit") == 0) && LuaGetTop(L) >= 3 &&
      LuaIsNumber(L, 3)) {
    uint32_t unit = 0;
    Vec3 world{};
    if (!ResolveUnit(LuaToString(L, 2), unit) ||
        !(nameplateProjection ? UnitNameplatePosition(unit, world) : UnitPosition(unit, world))) {
      LuaPushNil(L);
      return 1;
    }
    if (!nameplateProjection) world.z += UnitHeight(unit);
    if (forwardProjection) {
      float facing = 0.0f;
      if (LuaGetTop(L) < 4 || !LuaIsNumber(L, 4) || !UnitFacing(unit, facing)) { LuaPushNil(L); return 1; }
      const float distance = static_cast<float>(LuaToNumber(L, 4));
      if (!std::isfinite(distance) || distance < 0 || distance > 8) { LuaPushNil(L); return 1; }
      world.x += std::cos(facing) * distance;
      world.y += std::sin(facing) * distance;
    }
    world.z += static_cast<float>(LuaToNumber(L, 3));
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

  if (std::strcmp(command, "projectLine") == 0 && LuaGetTop(L) >= 5 &&
      LuaIsNumber(L, 4) && LuaIsNumber(L, 5)) {
    uint32_t sourceUnit = 0, targetUnit = 0;
    Vec3 sourceWorld{}, targetWorld{};
    const char *sourceToken = LuaToString(L, 2);
    const char *targetToken = LuaToString(L, 3);
    if (!ResolveUnit(sourceToken, sourceUnit)) { LuaPushNil(L); return 1; }
    if (sourceToken && targetToken && std::strcmp(sourceToken, targetToken) == 0)
      targetUnit = sourceUnit;
    else if (!ResolveUnit(targetToken, targetUnit)) { LuaPushNil(L); return 1; }
    if (!UnitPosition(sourceUnit, sourceWorld)) {
      LuaPushNil(L);
      return 1;
    }
    if (sourceUnit == targetUnit) targetWorld = sourceWorld;
    else if (!UnitPosition(targetUnit, targetWorld)) { LuaPushNil(L); return 1; }
    sourceWorld.z += static_cast<float>(LuaToNumber(L, 4));
    targetWorld.z += static_cast<float>(LuaToNumber(L, 5));

    Vec3 camera{}, forward{}, right{}, up{};
    float fov = 0.0f, aspect = 0.0f;
    ProjectionResult sourceProjection{}, targetProjection{};
    ProjectionViewport viewport{};
    if (!CameraState(camera, forward, right, up, fov, aspect) ||
        !ReadProjectionViewport(viewport) ||
        !ProjectWorldWithCamera(sourceWorld, camera, forward, sourceProjection, &viewport)) {
      LuaPushNil(L);
      return 1;
    }

    // WorldToScreen deliberately rejects points behind the near plane. Keep
    // the line snapshot useful there by returning a synthetic point along the
    // target's camera-space bearing. Lua only uses this point as a ray toward
    // the screen edge; its distance is intentionally arbitrary. Dividing the
    // horizontal component by camera aspect makes the direction isotropic
    // after normalized coordinates are expanded to UI pixels.
    const bool samePoint = sourceWorld.x == targetWorld.x &&
      sourceWorld.y == targetWorld.y && sourceWorld.z == targetWorld.z;
    if (samePoint) targetProjection = sourceProjection;
    else if (!ProjectWorldWithCamera(targetWorld, camera, forward, targetProjection, &viewport)) {
      const Vec3 delta{targetWorld.x - sourceWorld.x,
                       targetWorld.y - sourceWorld.y,
                       targetWorld.z - sourceWorld.z};
      float rayX = -(delta.x * right.x + delta.y * right.y + delta.z * right.z);
      float rayY = delta.x * up.x + delta.y * up.y + delta.z * up.z;
      const float targetDepth = (targetWorld.x - camera.x) * forward.x +
                                (targetWorld.y - camera.y) * forward.y +
                                (targetWorld.z - camera.z) * forward.z;
      float length = std::sqrt(rayX * rayX + rayY * rayY);
      if (length <= 0.0001f && targetDepth < 0.0f) {
        rayX = 0.0f;
        rayY = -1.0f;
        length = 1.0f;
      }
      if (length <= 0.0001f) {
        LuaPushNil(L);
        return 1;
      }
      const float safeAspect = (std::isfinite(aspect) && aspect > 0.01f)
                                   ? aspect : 1.0f;
      targetProjection.screenX = sourceProjection.screenX +
                                 (rayX / length) * 2.0f / safeAspect;
      targetProjection.screenY = sourceProjection.screenY +
                                 (rayY / length) * 2.0f;
      targetProjection.depth = targetDepth;
    }

    LuaPushNumber(L, static_cast<double>(GetTickCount()));
    const float values[] = {
        sourceProjection.screenX, sourceProjection.screenY, sourceProjection.depth,
        sourceWorld.x, sourceWorld.y, sourceWorld.z,
        targetProjection.screenX, targetProjection.screenY, targetProjection.depth,
        targetWorld.x, targetWorld.y, targetWorld.z};
    for (float value : values) LuaPushNumber(L, value);
    return 13;
  }

  if (std::strcmp(command, "projectionProbe") == 0) {
    const uint32_t worldFrame = *At<uint32_t *>(kWorldFrame);
    if (!IsReadable(worldFrame + 0x3A8, 1)) {
      LuaPushNil(L);
      return 1;
    }
    const float viewport[] = {
        *reinterpret_cast<float *>(worldFrame + 0x390),
        *reinterpret_cast<float *>(worldFrame + 0x394),
        *reinterpret_cast<float *>(worldFrame + 0x398),
        *reinterpret_cast<float *>(worldFrame + 0x39C),
        *reinterpret_cast<float *>(worldFrame + 0x3A0),
        *reinterpret_cast<float *>(worldFrame + 0x3A4)};
    for (float value : viewport) {
      if (!std::isfinite(value)) {
        LuaPushNil(L);
        return 1;
      }
    }
    LuaPushNumber(L, static_cast<double>(GetTickCount()));
    for (float value : viewport) LuaPushNumber(L, value);
    return 7;
  }

  if (std::strcmp(command, "cursorProjection") == 0) {
    const uint32_t clickInfo = *At<uint32_t *>(kWorldFrame);
    if (!IsReadable(clickInfo + 0x368, 4)) {
      LuaPushNil(L);
      return 1;
    }
    __try {
      At<RefreshCursorRaycastFn>(kRefreshCursorRaycast)(
          reinterpret_cast<void *>(clickInfo));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
      LuaPushNil(L);
      return 1;
    }
    if (*reinterpret_cast<uint32_t *>(clickInfo + 0x350) != 1) {
      LuaPushNil(L);
      return 1;
    }
    Vec3 world = *reinterpret_cast<Vec3 *>(clickInfo + 0x360);
    float projectedX = 0.0f, projectedY = 0.0f, depth = 0.0f;
    if (!ProjectWorld(world, projectedX, projectedY, depth)) {
      LuaPushNil(L);
      return 1;
    }

    HWND window = GetForegroundWindow();
    POINT cursor{};
    RECT client{};
    if (!window || !GetCursorPos(&cursor) || !ScreenToClient(window, &cursor) ||
        !GetClientRect(window, &client)) {
      LuaPushNil(L);
      return 1;
    }
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    if (width <= 0 || height <= 0 || cursor.x < 0 || cursor.y < 0 ||
        cursor.x > width || cursor.y > height) {
      LuaPushNil(L);
      return 1;
    }
    const float cursorX = static_cast<float>(cursor.x) / width;
    const float cursorY = static_cast<float>(height - cursor.y) / height;
    const float values[] = {projectedX, projectedY, cursorX, cursorY,
                            world.x, world.y, world.z, depth};
    LuaPushNumber(L, static_cast<double>(GetTickCount()));
    for (float value : values) LuaPushNumber(L, value);
    return 9;
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

  if (std::strcmp(command, "groundZ") == 0 && LuaGetTop(L) >= 3 &&
      LuaIsNumber(L, 2) && LuaIsNumber(L, 3)) {
    const float x = static_cast<float>(LuaToNumber(L, 2));
    const float y = static_cast<float>(LuaToNumber(L, 3));
    const float approxZ = (LuaGetTop(L) >= 4 && LuaIsNumber(L, 4))
                              ? static_cast<float>(LuaToNumber(L, 4))
                              : 0.0f;
    Vec3 start{x, y, approxZ + 35.0f};
    Vec3 end{x, y, approxZ - 35.0f};
    Vec3 hit{};
    float t = 1.0f;
    auto intersect = At<IntersectFn>(kCWorldIntersect);
    char hitGeo = 0;
    __try {
      hitGeo = intersect(&start, &end, 0, &hit, &t, kLoSFlags);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
      hitGeo = 0;
    }
    if (hitGeo != 0 && t >= 0.0f && t <= 1.0f) {
      LuaPushNumber(L, hit.z);
      return 1;
    }
    LuaPushNil(L);
    return 1;
  }

  if (std::strcmp(command, "raycast") == 0 && LuaGetTop(L) >= 7 &&
      LuaIsNumber(L, 2) && LuaIsNumber(L, 3) && LuaIsNumber(L, 4) &&
      LuaIsNumber(L, 5) && LuaIsNumber(L, 6) && LuaIsNumber(L, 7)) {
    Vec3 start{static_cast<float>(LuaToNumber(L, 2)),
               static_cast<float>(LuaToNumber(L, 3)),
               static_cast<float>(LuaToNumber(L, 4))};
    Vec3 end{static_cast<float>(LuaToNumber(L, 5)),
             static_cast<float>(LuaToNumber(L, 6)),
             static_cast<float>(LuaToNumber(L, 7))};
    const float dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z;
    const float dist = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (dist > 250.0f) {
      LuaPushNumber(L, 0.0);
      return 1;
    }
    Vec3 hit{};
    float t = 1.0f;
    auto intersect = At<IntersectFn>(kCWorldIntersect);
    char hitGeo = 0;
    __try {
      hitGeo = intersect(&start, &end, 0, &hit, &t, kLoSFlags);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
      hitGeo = 0;
    }
    if (hitGeo != 0 && t >= 0.0f && t <= 1.0f) {
      LuaPushNumber(L, 1.0);
      LuaPushNumber(L, hit.x);
      LuaPushNumber(L, hit.y);
      LuaPushNumber(L, hit.z);
      LuaPushNumber(L, t);
      return 5;
    }
    LuaPushNumber(L, 0.0);
    return 1;
  }

  if (std::strcmp(command, "isOccluded") == 0 && LuaGetTop(L) >= 4 &&
      LuaIsNumber(L, 2) && LuaIsNumber(L, 3) && LuaIsNumber(L, 4)) {
    Vec3 camera{}, forward{}, right{}, up{};
    float fov = 0.0f, aspect = 0.0f;
    if (!CameraState(camera, forward, right, up, fov, aspect)) {
      LuaPushNil(L);
      return 1;
    }
    const Vec3 camStart{camera.x + forward.x * 0.5f,
                        camera.y + forward.y * 0.5f,
                        camera.z + forward.z * 0.5f};
    const Vec3 target{static_cast<float>(LuaToNumber(L, 2)),
                      static_cast<float>(LuaToNumber(L, 3)),
                      static_cast<float>(LuaToNumber(L, 4)) + 0.15f};
    const float dx = target.x - camStart.x, dy = target.y - camStart.y, dz = target.z - camStart.z;
    const float dist = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (dist > 250.0f || dist <= 0.05f) {
      LuaPushNumber(L, 0.0);
      return 1;
    }
    Vec3 hit{};
    float t = 1.0f;
    auto intersect = At<IntersectFn>(kCWorldIntersect);
    char hitGeo = 0;
    __try {
      hitGeo = intersect(&camStart, &target, 0, &hit, &t, kLoSFlags);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
      hitGeo = 0;
    }
    const bool occluded = (hitGeo != 0 && t > 0.03f && t < 0.97f);
    LuaPushNumber(L, occluded ? 1.0 : 0.0);
    return 1;
  }

  if (std::strcmp(command, "sunLight") == 0) {
    Vec3 camPos{}, forward{}, right{}, up{};
    float fov = 0.0f, aspect = 0.0f;
    if (!CameraState(camPos, forward, right, up, fov, aspect)) {
      LuaPushNil(L);
      return 1;
    }
    Vec3 lightDir{};
    float diffR = 1.0f, diffG = 1.0f, diffB = 1.0f;
    float ambR = 0.4f, ambG = 0.4f, ambB = 0.4f;
    if (!SunLight(lightDir, diffR, diffG, diffB, ambR, ambG, ambB)) {
      LuaPushNil(L);
      return 1;
    }
    // Note: In WoW's internal camera matrix, right basis is mirrored relative to UI screen X.
    const float sunCamX = -(lightDir.x * right.x + lightDir.y * right.y + lightDir.z * right.z);
    const float sunCamY =  (lightDir.x * up.x    + lightDir.y * up.y    + lightDir.z * up.z);
    const float sunCamZ =  (lightDir.x * forward.x + lightDir.y * forward.y + lightDir.z * forward.z);
    const float screenAngle = std::atan2(sunCamY, sunCamX);

    LuaPushNumber(L, screenAngle);
    LuaPushNumber(L, sunCamX);
    LuaPushNumber(L, sunCamY);
    LuaPushNumber(L, sunCamZ);
    LuaPushNumber(L, lightDir.x);
    LuaPushNumber(L, lightDir.y);
    LuaPushNumber(L, lightDir.z);
    LuaPushNumber(L, diffR);
    LuaPushNumber(L, diffG);
    LuaPushNumber(L, diffB);
    LuaPushNumber(L, ambR);
    LuaPushNumber(L, ambG);
    LuaPushNumber(L, ambB);
    return 13;
  }

  if (std::strcmp(command, "unitDistance") == 0 && LuaGetTop(L) >= 3) {
    uint32_t u1 = 0, u2 = 0;
    Vec3 p1{}, p2{};
    if (!ResolveUnit(LuaToString(L, 2), u1) ||
        !ResolveUnit(LuaToString(L, 3), u2) ||
        !UnitPosition(u1, p1) ||
        !UnitPosition(u2, p2)) {
      LuaPushNil(L);
      return 1;
    }
    const float dx = p1.x - p2.x;
    const float dy = p1.y - p2.y;
    const float dz = p1.z - p2.z;
    LuaPushNumber(L, std::sqrt(dx * dx + dy * dy + dz * dz));
    return 1;
  }

  if (std::strcmp(command, "lineOfSight") == 0 && LuaGetTop(L) >= 3) {
    uint32_t u1 = 0, u2 = 0;
    Vec3 p1{}, p2{};
    if (!ResolveUnit(LuaToString(L, 2), u1) ||
        !ResolveUnit(LuaToString(L, 3), u2) ||
        !UnitPosition(u1, p1) ||
        !UnitPosition(u2, p2)) {
      LuaPushNil(L);
      return 1;
    }
    p1.z += UnitHeight(u1);
    p2.z += UnitHeight(u2);
    Vec3 hit{};
    float t = 1.0f;
    const char hitGeo = SafeIntersect(&p1, &p2, &hit, &t, kLoSFlags);
    const bool clearLoS = (hitGeo == 0 || t >= 0.98f);
    LuaPushNumber(L, clearLoS ? 1.0 : 0.0);
    return 1;
  }

  if (std::strcmp(command, "setTarget") == 0 && LuaGetTop(L) >= 2) {
    const uint64_t guid = ResolveGuid(LuaToString(L, 2));
    if (!guid || !SafeSetTarget(&guid)) {
      LuaPushNil(L);
      return 1;
    }
    LuaPushNumber(L, 1.0);
    return 1;
  }

  if (std::strcmp(command, "nearbyCreatures") == 0 ||
      std::strcmp(command, "nearbyCreaturesInto") == 0) {
    float maxRange = 30.0f;
    if (LuaGetTop(L) >= 2 && LuaIsNumber(L, 2)) {
      maxRange = static_cast<float>(LuaToNumber(L, 2));
    }
    const char *centerToken = (LuaGetTop(L) >= 3) ? LuaToString(L, 3) : "player";
    return DoNearbyCreatures(L, maxRange, centerToken,
                            std::strcmp(command, "nearbyCreaturesInto") == 0);
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
    g_fontStates.clear();
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

  // Guard against degenerate / corrupt texture Use-After-Free crashes in graphics pipeline
  void *devSetTexTarget = FollowExistingJump(At<void *>(kDeviceSetTexture));
  if (MH_CreateHook(devSetTexTarget, reinterpret_cast<void *>(&DeviceSetTextureHook),
                    reinterpret_cast<void **>(&g_deviceSetTextureOriginal)) == MH_OK) {
    MH_EnableHook(devSetTexTarget);
  }

  void *prepTexTarget = FollowExistingJump(At<void *>(kPrepareTexture));
  if (MH_CreateHook(prepTexTarget, reinterpret_cast<void *>(&PrepareTextureHook),
                    reinterpret_cast<void **>(&g_prepareTextureOriginal)) == MH_OK) {
    MH_EnableHook(prepTexTarget);
  }

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
