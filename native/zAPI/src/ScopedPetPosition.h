#pragma once
#include <Windows.h>
#include <cstdint>

using PositionSpellDispatchFn = void(__fastcall *)(unsigned, int, unsigned, unsigned);
using PositionCommitFn = unsigned char(__fastcall *)(const float *);
using PositionCancelFn = void(__fastcall *)();

// Only a caller-validated Take Position spellbook slot may reach this helper.
// Never consume somebody else's reticle. Restore the script context even when
// dispatch, placement or cancellation raises a structured exception.
inline bool DispatchScopedPetPosition(PositionSpellDispatchFn dispatch,
    PositionCommitFn commit, PositionCancelFn cancel, uint32_t *placement,
    uint32_t *context, uint32_t *depth, volatile LONG *busy,
    unsigned slot, const float *xyz) {
  if (!dispatch || !commit || !cancel || !placement || !context || !depth ||
      !busy || !xyz || InterlockedCompareExchange(busy, 1, 0) != 0) return false;
  bool submitted = false;
  __try {
    const uint32_t savedContext = *context, savedDepth = *depth;
    bool owned = false;
    __try {
      if (*placement == 0) {
        owned = true;
        *context = 0;
        dispatch(slot, 0, 0, 0);
        if ((*placement & 0x60) != 0) {
          commit(xyz);
          submitted = *placement == 0;
        }
      }
    } __finally {
      __try { if (owned && *placement != 0) { *context = 0; cancel(); } }
      __finally { *context = savedContext; *depth = savedDepth; }
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) { submitted = false; }
  InterlockedExchange(busy, 0);
  return submitted;
}
