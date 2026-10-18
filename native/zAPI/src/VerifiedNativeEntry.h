#pragma once
#include <cstddef>
#include <cstdint>
#include <cstring>

struct NativeEntryMemory {
  bool (*read)(uintptr_t, void *, size_t);
  bool (*executable)(uintptr_t, size_t);
};
struct NativeEntryModule {
  uintptr_t base = 0;
  size_t size = 0;
  bool Contains(uintptr_t p) const { return base && p >= base && p - base < size; }
};
enum class NativeEntryResult {
  Original, Nampower, Unreadable, UnknownPrefix, ModifiedTail, UnknownModule,
  InvalidGate, ForeignCallback, InvalidContext, ForeignImplementation
};
inline const char *NativeEntryDescription(NativeEntryResult result) {
  switch (result) {
    case NativeEntryResult::Original: return "original client entry";
    case NativeEntryResult::Nampower: return "verified Nampower 4.6.2 hook";
    case NativeEntryResult::Unreadable: return "native entry unavailable";
    case NativeEntryResult::UnknownPrefix: return "unrecognized native entry";
    case NativeEntryResult::ModifiedTail: return "native body signature changed";
    case NativeEntryResult::UnknownModule: return "hook requires verified Nampower build";
    case NativeEntryResult::InvalidGate: return "unrecognized hook gate";
    case NativeEntryResult::ForeignCallback: return "hook callback outside verified Nampower";
    case NativeEntryResult::InvalidContext: return "invalid hook context";
    default: return "hook implementation outside verified Nampower";
  }
}
inline bool NativeEntryAccepted(NativeEntryResult result) {
  return result == NativeEntryResult::Original || result == NativeEntryResult::Nampower;
}

// Inspect only. The caller still invokes the original entry and its installed
// hook chain; this never calls a gate helper, virtual method or trampoline.
inline NativeEntryResult VerifyNativeEntry(uintptr_t entry, const uint8_t *expected,
    size_t size, NativeEntryModule module, NativeEntryMemory memory) {
  uint8_t code[64]{};
  if (!expected || size < 6 || size > sizeof(code) || !memory.read || !memory.executable ||
      !memory.read(entry, code, size) || !memory.executable(entry, size)) return NativeEntryResult::Unreadable;
  if (std::memcmp(code, expected, size) == 0) return NativeEntryResult::Original;
  if (code[0] != 0xE9) return NativeEntryResult::UnknownPrefix;
  // Hadesmem writes exactly a five-byte jump, leaving the remaining bytes.
  if (std::memcmp(code + 5, expected + 5, size - 5) != 0) return NativeEntryResult::ModifiedTail;
  if (!module.base || !module.size) return NativeEntryResult::UnknownModule;
  int32_t rel = 0; std::memcpy(&rel, code + 1, 4);
  const uintptr_t gate = entry + 5 + rel;
  uint8_t stub[56]{};
  if (!memory.read(gate, stub, sizeof(stub)) || !memory.executable(gate, sizeof(stub))) return NativeEntryResult::InvalidGate;
  // The public Hadesmem x86 gate. Only its three absolute operands and final
  // relative jump vary. Every instruction byte and operand role is verified.
  static const uint8_t pattern[56] = {
    0x90,0x90,0x90,0x90,0x90,0x60,0x8B,0x4C,0x24,0x20,0xB8,0,0,0,0,
    0x51,0xFF,0xD0,0x59,0x89,0x08,0x64,0x8B,0x0D,0x14,0,0,0,0xB8,0,0,0,0,
    0x64,0xA3,0x14,0,0,0,0xB8,0,0,0,0,0x51,0xFF,0xD0,0x59,0x89,0x08,0x61,
    0xE9,0,0,0,0};
  for (size_t i = 0; i < sizeof(stub); ++i) {
    if ((i >= 11 && i < 15) || (i >= 29 && i < 33) ||
        (i >= 40 && i < 44) || i >= 52) continue;
    if (stub[i] != pattern[i]) return NativeEntryResult::InvalidGate;
  }
  uint32_t retHelper=0, context=0, userHelper=0;
  std::memcpy(&retHelper, stub + 11, 4); std::memcpy(&context, stub + 29, 4);
  std::memcpy(&userHelper, stub + 40, 4);
  if (!module.Contains(retHelper) || !module.Contains(userHelper) ||
      !memory.executable(retHelper, 1) || !memory.executable(userHelper, 1)) return NativeEntryResult::ForeignCallback;
  uint32_t patch=0, vtable=0, apply=0;
  if (!memory.read(context, &patch, 4) || !memory.read(patch, &vtable, 4) ||
      !module.Contains(vtable) || !memory.read(vtable, &apply, 4) ||
      !module.Contains(apply) || !memory.executable(apply, 1)) return NativeEntryResult::InvalidContext;
  std::memcpy(&rel, stub + 52, 4);
  const uintptr_t implementation = gate + sizeof(stub) + rel;
  if (!module.Contains(implementation) || !memory.executable(implementation, 1)) return NativeEntryResult::ForeignImplementation;
  return NativeEntryResult::Nampower;
}
