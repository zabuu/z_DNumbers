#pragma once

#include <Windows.h>
#include <cstdint>

// Same fastcall ABI used by the inspected client's PetAttack/PetFollow wrappers.
using PetCommandDispatchFn = void(__fastcall *)(const uint32_t *, const uint64_t *);

// Only the fixed native pet command runs in the neutral execution context.
// Restore it on normal return and Windows exceptions; never run caller Lua here.
inline bool DispatchScopedPetCommand(PetCommandDispatchFn dispatch,
                                     uint32_t *context, uint32_t *depth,
                                     volatile LONG *busy, uint32_t command,
                                     uint64_t victim) {
  if (!dispatch || !context || !depth || !busy ||
      InterlockedCompareExchange(busy, 1, 0) != 0) return false;
  bool submitted = false;
  __try {
    const uint32_t savedContext = *context;
    const uint32_t savedDepth = *depth;
    __try {
      *context = 0;
      dispatch(&command, &victim);
      submitted = true;
    } __finally {
      *context = savedContext;
      *depth = savedDepth;
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    submitted = false;
  }
  InterlockedExchange(busy, 0);
  return submitted;
}
