// Read-only loaded-container/fishing-hole snapshot. Included inside zAPI's
// anonymous namespace after the existing guarded enumeration primitive.
struct GatherObject {
  uint64_t guid = 0;
  Vec3 position{};
  uint32_t entry = 0, display = 0, type = 0, state = 0, flags = 0, dynamic = 0;
};

bool ReadGatherObject(uint64_t guid, GatherObject &out) {
  __try {
    if (((guid >> 48) & 0xFFFF) != 0xF110) return false;
    const uint32_t object = At<GetObjectByGuidFn>(kGetObjectByGuid)(guid);
    if (!IsReadable(object, 0x18) || *reinterpret_cast<const uint32_t *>(object + 0x14) != 5) return false;
    const uint32_t fields = *reinterpret_cast<const uint32_t *>(object + 0x08);
    if (!IsReadable(fields, 0x68) || *reinterpret_cast<const uint64_t *>(fields) != guid) return false;
    const uint32_t type = *reinterpret_cast<const uint32_t *>(fields + 0x54);
    if (type != 3 && type != 25) return false; // Containers include herbs/ore; not traps or bobbers.
    const uint32_t state = *reinterpret_cast<const uint32_t *>(fields + 0x38);
    const uint32_t flags = *reinterpret_cast<const uint32_t *>(fields + 0x24);
    const uint32_t dynamic = *reinterpret_cast<const uint32_t *>(fields + 0x4C);
    if ((flags & 0x10) || (dynamic & 0x04) || (type == 3 && state != 1) || state > 2) return false;
    out.guid = guid; out.type = type; out.state = state; out.flags = flags; out.dynamic = dynamic;
    out.entry = *reinterpret_cast<const uint32_t *>(fields + 0x0C);
    out.display = *reinterpret_cast<const uint32_t *>(fields + 0x20);
    out.position = *reinterpret_cast<const Vec3 *>(fields + 0x3C);
    return out.entry && std::isfinite(out.position.x) && std::isfinite(out.position.y) &&
           std::isfinite(out.position.z) && std::fabs(out.position.x) < 100000.0f &&
           std::fabs(out.position.y) < 100000.0f && std::fabs(out.position.z) < 100000.0f;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

bool GatherPlayerPosition(Vec3 &position) {
  __try {
    if (!IsReadable(At<uintptr_t>(kInWorld), 1) || !*At<const uint8_t *>(kInWorld)) return false;
    uint32_t player = 0;
    return ResolveUnit("player", player) && UnitPosition(player, position);
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

thread_local std::vector<GatherObject> g_gatherScratch;
thread_local bool g_gatherBusy = false;
uint64_t g_gatherQueries = 0;
int __fastcall EnumGatherObjects(std::vector<GatherObject> *results, void *, uint64_t guid) {
  GatherObject object{};
  if (results && ReadGatherObject(guid, object)) results->push_back(object);
  return 1;
}

int DoGatherObjects(void *L) {
  constexpr int stride = 10;
  if (LuaGetTop(L) < 2 || LuaType(L, 2) != 5 || g_gatherBusy) { LuaPushNil(L); return 1; }
  const int previous = At<LuaLGetNFn>(kLuaLGetN)(L, 2);
  Vec3 player{};
  if (previous < 0 || previous > 1000000 || !GatherPlayerPosition(player)) { LuaPushNil(L); return 1; }
  std::vector<GatherObject> results;
  results.swap(g_gatherScratch);results.clear();
  g_gatherBusy = true;
  const bool ready = SafeEnumVisible(reinterpret_cast<EnumVisibleCallbackFn>(&EnumGatherObjects), &results);
  g_gatherBusy = false;
  if (!ready || results.size() > 100000) {
    results.clear();
    if (results.capacity() <= 4096) results.swap(g_gatherScratch);
    LuaPushNil(L);return 1; // Failed snapshots never mutate caller output.
  }
  // Stable GUID ordering avoids marker churn when native enumeration reorders.
  std::sort(results.begin(), results.end(), [](const GatherObject &a, const GatherObject &b) { return a.guid < b.guid; });
  ++g_gatherQueries;
  int index = 0;char guid[19];
  for (const auto &object : results) {
    std::snprintf(guid, sizeof(guid), "0x%016llX", object.guid);
    LuaPushString(L, guid);LuaRawSetI(L, 2, ++index);
    const double values[] = {double(object.entry),object.position.x,object.position.y,object.position.z,
                            double(object.display),double(object.type),double(object.state),double(object.flags),double(object.dynamic)};
    for (double value : values) { LuaPushNumber(L, value);LuaRawSetI(L, 2, ++index); }
  }
  for (int i = index + 1; i <= previous; ++i) { LuaPushNil(L);LuaRawSetI(L, 2, i); }
  At<LuaLSetNFn>(kLuaLSetN)(L, 2, index);
  LuaPushNumber(L, static_cast<double>(index / stride));
  LuaPushNumber(L, player.x);LuaPushNumber(L, player.y);LuaPushNumber(L, player.z);
  results.clear();
  if (results.capacity() <= 4096 && g_gatherScratch.empty()) results.swap(g_gatherScratch);
  return 4;
}
