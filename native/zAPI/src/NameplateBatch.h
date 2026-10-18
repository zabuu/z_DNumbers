// Included after the existing projection helpers. No new client hook, object
// enumeration, cached object pointers, or alternate anchor/coordinate math.
constexpr int kNameplateBatchLimit = 512;
constexpr int kNameplateBatchStride = 7;
struct NameplateBatchRow { float values[kNameplateBatchStride]{}; };
std::vector<NameplateBatchRow> g_nameplateBatchScratch;
uint64_t g_nameplateBatchCalls = 0, g_nameplateBatchRows = 0;
uint64_t g_nameplateBatchGrowths = 0;

bool IsBatchGuid(const char *text) {
  if (!text || std::strlen(text) != 18 || text[0] != '0' ||
      (text[1] != 'x' && text[1] != 'X')) return false;
  for (int i = 2; i < 18; ++i) {
    const char c = text[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F'))) return false;
  }
  return true;
}

bool ProjectBatchNameplate(const char *guid, const Vec3 &camera,
                           const Vec3 &forward, const ProjectionViewport &viewport,
                           NameplateBatchRow &row) {
  // Unit/model pointers live only inside this call. In particular, never reuse
  // them across a frame, despawn, zone transition, or pooled nameplate slot.
  __try {
    uint32_t unit = 0;
    Vec3 world{};
    ProjectionResult result{};
    if (!ResolveUnit(guid, unit) || !UnitNameplatePosition(unit, world) ||
        !ProjectWorldWithCamera(world, camera, forward, result, &viewport)) return false;
    row.values[0] = 1;
    row.values[1] = result.screenX; row.values[2] = result.screenY;
    row.values[3] = result.depth;
    row.values[4] = world.x; row.values[5] = world.y; row.values[6] = world.z;
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

int DoProjectNameplatesInto(void *L) {
  // (command, private GUID array, explicit count, private output array).
  // Output is dense: [valid, x, y, depth, worldX, worldY, worldZ] per input.
  // An invalid/missing/off-camera model emits seven zeros, never stale data.
  if (LuaGetTop(L) < 4 || LuaType(L, 2) != 5 || LuaType(L, 3) != 3 || LuaType(L, 4) != 5) {
    LuaPushNil(L); return 1;
  }
  const double requested = LuaToNumber(L, 3);
  if (!std::isfinite(requested) || requested < 0 || requested > kNameplateBatchLimit ||
      std::floor(requested) != requested) { LuaPushNil(L); return 1; }
  const int count = static_cast<int>(requested);
  const int oldLength = At<LuaLGetNFn>(kLuaLGetN)(L, 4);
  if (oldLength < 0 || oldLength > kNameplateBatchLimit * kNameplateBatchStride) {
    LuaPushNil(L); return 1;
  }
  Vec3 camera{}, forward{}, right{}, up{};
  float fov = 0, aspect = 0;
  ProjectionViewport viewport{};
  if (count && (!CameraState(camera, forward, right, up, fov, aspect) ||
                !ReadProjectionViewport(viewport))) { LuaPushNil(L); return 1; }

  // This invocation owns its storage until all Lua output is finished. A
  // reentrant call during Lua allocation cannot overwrite the outer results.
  std::vector<NameplateBatchRow> rows;
  rows.swap(g_nameplateBatchScratch);
  rows.clear();
  if (rows.capacity() < static_cast<size_t>(count)) { rows.reserve(count); ++g_nameplateBatchGrowths; }
  rows.resize(count);
  for (int i = 0; i < count; ++i) {
    // The already-used FrameScript_PushObject entry is lua_rawgeti in this
    // verified 1.12 client (fastcall L, table index, integer key). Raw access
    // invokes no __index; strict strings avoid number-to-string allocations.
    At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L, 2, i + 1);
    const char *guid = LuaType(L, -1) == 4 ? LuaToString(L, -1) : nullptr;
    if (IsBatchGuid(guid)) ProjectBatchNameplate(guid, camera, forward, viewport, rows[i]);
    At<LuaSetTopFn>(kLuaSetTop)(L, -2);
  }
  ++g_nameplateBatchCalls;
  g_nameplateBatchRows += count;
  int key = 0;
  for (const auto &row : rows)
    for (float value : row.values) { LuaPushNumber(L, value); LuaRawSetI(L, 4, ++key); }
  for (int i = key + 1; i <= oldLength; ++i) { LuaPushNil(L); LuaRawSetI(L, 4, i); }
  // Lua 5.0 maintains a stored length, independently of the raw array writes.
  At<LuaLSetNFn>(kLuaLSetN)(L, 4, key);
  LuaPushNumber(L, count);
  rows.clear();
  if (rows.capacity() <= kNameplateBatchLimit && rows.capacity() > g_nameplateBatchScratch.capacity())
    rows.swap(g_nameplateBatchScratch);
  return 1;
}
