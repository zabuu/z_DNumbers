// Stack-owned successful VirtualQuery results for a native-only work phase.
// Never keep this cache across Lua calls, callbacks, output, or rendered frames.
#pragma once

class ReadableRegionCache {
  struct Region { uintptr_t begin = 0, end = 0; };
  Region regions_[32]{};
  size_t count_ = 0, next_ = 0;
public:
  bool Contains(uintptr_t address, size_t bytes) const {
    const uintptr_t end = address + bytes;
    if (!address || !bytes || end < address) return false;
    for (size_t i = 0; i < count_; ++i)
      if (address >= regions_[i].begin && end <= regions_[i].end) return true;
    return false;
  }
  void Remember(const MEMORY_BASIC_INFORMATION &info) {
    const uintptr_t begin = reinterpret_cast<uintptr_t>(info.BaseAddress);
    const uintptr_t end = begin + info.RegionSize;
    if (end <= begin) return;
    regions_[next_] = {begin, end};
    next_ = (next_ + 1) % 32;
    if (count_ < 32) ++count_;
  }
};

thread_local ReadableRegionCache *g_readableRegionCache = nullptr;

class ScopedReadableRegions {
  ReadableRegionCache regions_;
  ReadableRegionCache *previous_;
public:
  ScopedReadableRegions() : previous_(g_readableRegionCache) { g_readableRegionCache = &regions_; }
  ~ScopedReadableRegions() { g_readableRegionCache = previous_; }
  ScopedReadableRegions(const ScopedReadableRegions &) = delete;
  ScopedReadableRegions &operator=(const ScopedReadableRegions &) = delete;
};
