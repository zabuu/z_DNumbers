// Nameplate-only UnitXP-compatible sight geometry. Existing lineOfSight and
// pet/terrain flags are deliberately independent of this contract.
constexpr int kNameplateSightLimit = 512;
constexpr uint32_t kNameplateSightFlags = 0x100111;
struct NameplateSightUnit { Vec3 position{}; float height = 0; };
struct NameplateSightRow { char guid[19]{}; int result = -1; };
struct NameplateSightCacheEntry {
  uint64_t source = 0, target = 0;
  double sampled = 0, expires = 0;
  int result = -1;
};
NameplateSightCacheEntry g_nameplateSightCache[kNameplateSightLimit]{};
std::vector<NameplateSightRow> g_nameplateSightScratch;
uint64_t g_nameplateSightCalls = 0, g_nameplateSightRows = 0;
uint64_t g_nameplateSightTraces = 0, g_nameplateSightHits = 0, g_nameplateSightGrowths = 0;

double NameplateSightMilliseconds() {
  static LARGE_INTEGER frequency{};
  LARGE_INTEGER now{};
  if ((!frequency.QuadPart && !QueryPerformanceFrequency(&frequency)) ||
      frequency.QuadPart <= 0 || !QueryPerformanceCounter(&now)) return -1;
  return static_cast<double>(now.QuadPart) * 1000.0 / frequency.QuadPart;
}

bool ReadNameplateSightUnit(uint32_t unit, NameplateSightUnit &state) {
  __try {
    if (!UnitPosition(unit, state.position)) return false;
    // Same CMovement collision height used by UnitXP. A missing movement
    // record is unknown, rather than silently substituting a zero-height ray.
    if (!IsReadable(unit + 0x118, 4)) return false;
    const uint32_t movement = *reinterpret_cast<const uint32_t *>(unit + 0x118);
    if (!IsReadable(movement + 0xB4, 4)) return false;
    state.height = *reinterpret_cast<const float *>(movement + 0xB4);
    return std::isfinite(state.height) && state.height >= 0;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

// -1 unknown/fault, 0 clear, 1 blocked. UnitXP's 150-yard trace guard and
// inclusive [0,1] intersection bounds are retained, including endpoint hits.
int TraceNameplateSight(const Vec3 &start, const Vec3 &end) {
  const float dx = end.x - start.x, dy = end.y - start.y, dz = end.z - start.z;
  const float distance = std::sqrt(dx * dx + dy * dy + dz * dz);
  if (!std::isfinite(distance)) return -1;
  if (distance > 150.0f) return 1;
  if (distance <= 1.192092896e-7F) return 0; // numeric_limits<float>::epsilon()
  __try {
    Vec3 hit{};
    float t = 1.0f;
    ++g_nameplateSightTraces;
    const char intersects = At<IntersectFn>(kCWorldIntersect)(&start, &end, 0, &hit, &t, kNameplateSightFlags);
    if (!std::isfinite(t)) return -1;
    return intersects && t >= 0.0f && t <= 1.0f ? 1 : 0;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return -1; }
}

// Same two tests as vanilla1121_unitInLineOfSight: first trace at the shorter
// unit's height; only if blocked and heights differ, trace between both heads.
int TestNameplateSight(const NameplateSightUnit &source, const NameplateSightUnit &target) {
  const NameplateSightUnit *shorter = &source, *taller = &target;
  if (source.height > target.height) { shorter = &target; taller = &source; }
  Vec3 a = shorter->position, b = taller->position;
  a.z += shorter->height; b.z += shorter->height;
  const int first = TraceNameplateSight(a, b);
  if (first < 0) return -1;
  if (!first) return 1;
  if (shorter->height == taller->height) return 0;
  b = taller->position; b.z += taller->height;
  const int second = TraceNameplateSight(a, b);
  return second < 0 ? -1 : (second ? 0 : 1);
}

int SampleNameplateSight(const char *identifier, uint64_t sourceGuid,
                        const NameplateSightUnit &source, double now) {
  __try {
    uint32_t unit = 0;
    // Resolve on every query, even cache hits: never accept a vanished object.
    if (!ResolveUnit(identifier, unit)) return -1;
    const uint64_t targetGuid = ResolveGuid(identifier);
    if (!targetGuid) return -1;
    if (targetGuid == sourceGuid) return 1;
    const uint64_t hash = targetGuid ^ (targetGuid >> 32) ^ (targetGuid >> 17);
    auto &cached = g_nameplateSightCache[hash % kNameplateSightLimit];
    if (cached.source == sourceGuid && cached.target == targetGuid &&
        now >= cached.sampled && now < cached.expires) {
      ++g_nameplateSightHits; return cached.result;
    }
    NameplateSightUnit target{};
    if (!ReadNameplateSightUnit(unit, target)) return -1;
    const int result = TestNameplateSight(source, target);
    if (result >= 0) {
      // UnitXP uses 100 ms plus 0..60 ms random dither. Stable GUID dither
      // keeps that age range without RNG, pair-map allocation or tree walks.
      cached.source = sourceGuid; cached.target = targetGuid; cached.result = result;
      cached.sampled = now;
      cached.expires = now + 100.0 + (hash % 61);
    }
    return result;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return -1; }
}

bool NameplateSightSource(uint64_t &guid, NameplateSightUnit &source) {
  __try {
    if (!IsReadable(At<uintptr_t>(kInWorld), 1) || !*At<const uint8_t *>(kInWorld)) return false;
    uint32_t unit = 0;
    guid = ResolveGuid("player");
    return guid && ResolveUnit("player", unit) && ReadNameplateSightUnit(unit, source);
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

int DoNameplateSightInto(void *L) {
  // (command, private GUID array, explicit count, private output array).
  // One dense result per input: -1 unknown, 0 blocked, 1 clear. A whole-call
  // failure returns nil without changing output. No native unit pointers survive.
  if (LuaGetTop(L) < 4 || LuaType(L, 2) != 5 || LuaType(L, 3) != 3 || LuaType(L, 4) != 5) {
    LuaPushNil(L); return 1;
  }
  const double requested = LuaToNumber(L, 3);
  if (!std::isfinite(requested) || requested < 0 || requested > kNameplateSightLimit ||
      std::floor(requested) != requested) { LuaPushNil(L); return 1; }
  const int count = static_cast<int>(requested);
  const int oldLength = At<LuaLGetNFn>(kLuaLGetN)(L, 4);
  if (oldLength < 0 || oldLength > kNameplateSightLimit) { LuaPushNil(L); return 1; }

  std::vector<NameplateSightRow> rows;
  rows.swap(g_nameplateSightScratch); rows.clear();
  if (rows.capacity() < static_cast<size_t>(count)) { rows.reserve(count); ++g_nameplateSightGrowths; }
  rows.resize(count);
  for (int i = 0; i < count; ++i) {
    At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L, 2, i + 1);
    const char *guid = LuaType(L, -1) == 4 ? LuaToString(L, -1) : nullptr;
    if (IsBatchGuid(guid)) std::memcpy(rows[i].guid, guid, sizeof(rows[i].guid));
    At<LuaSetTopFn>(kLuaSetTop)(L, -2);
  }
  bool ready = count == 0;
  {
    // Both Lua phases are outside shared page views; source/target state is
    // read live. Scratch stays private through output, including Lua reentry.
    ScopedReadableRegions readable;
    uint64_t sourceGuid = 0;
    NameplateSightUnit source{};
    const double now = NameplateSightMilliseconds();
    if (count && now >= 0 && NameplateSightSource(sourceGuid, source)) {
      ready = true;
      for (auto &row : rows)
        if (row.guid[0]) row.result = SampleNameplateSight(row.guid, sourceGuid, source, now);
    }
  }
  if (ready) {
    ++g_nameplateSightCalls; g_nameplateSightRows += count;
    for (int i = 0; i < count; ++i) { LuaPushNumber(L, rows[i].result); LuaRawSetI(L, 4, i + 1); }
    for (int i = count + 1; i <= oldLength; ++i) { LuaPushNil(L); LuaRawSetI(L, 4, i); }
    At<LuaLSetNFn>(kLuaLSetN)(L, 4, count);
    LuaPushNumber(L, count);
  } else LuaPushNil(L);
  rows.clear();
  if (rows.capacity() <= kNameplateSightLimit && rows.capacity() > g_nameplateSightScratch.capacity())
    rows.swap(g_nameplateSightScratch);
  return 1;
}
