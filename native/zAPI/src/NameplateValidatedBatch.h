// Same projection math as v1, with live token/GUID/frame validation in the
// native work phase. All addresses are scoped to this call on the verified client.
constexpr int kValidatedPlateStride = 8;
constexpr uintptr_t kUnitNameplateOffset = 0xE60;
constexpr uintptr_t kNameplateGuidOffset = 0x4E8;
struct ValidatedPlateRow {
  float values[kValidatedPlateStride]{};
  char guid[19]{}, token[64]{};
  uintptr_t frame = 0;
};
std::vector<ValidatedPlateRow> g_validatedPlateScratch;
uint64_t g_validatedPlateCalls = 0, g_validatedPlateRows = 0;
uint64_t g_validatedPlateCurrent = 0, g_validatedPlateProjected = 0, g_validatedPlateGrowths = 0;

bool ValidateAndProjectPlate(ValidatedPlateRow &row, const Vec3 &camera,
                             const Vec3 &forward, const ProjectionViewport &viewport) {
  __try {
    uint32_t unit = 0;
    const uint64_t expected = ResolveGuid(row.guid);
    if (!expected || !row.frame || !row.token[0] || !ResolveUnit(row.token, unit) ||
        !IsReadable(unit, kUnitNameplateOffset + 4) ||
        !IsReadable(row.frame, kNameplateGuidOffset + 8) ||
        *reinterpret_cast<const uint64_t *>(unit + 0x30) != expected ||
        *reinterpret_cast<const uint32_t *>(unit + kUnitNameplateOffset) != row.frame ||
        *reinterpret_cast<const uint64_t *>(row.frame + kNameplateGuidOffset) != expected) return false;
    row.values[0] = 1; // Current association, even when the model can't project.
    Vec3 world{};
    ProjectionResult result{};
    if (!UnitNameplatePosition(unit, world) ||
        !ProjectWorldWithCamera(world, camera, forward, result, &viewport)) return true;
    row.values[1] = 1;
    row.values[2] = result.screenX; row.values[3] = result.screenY;
    row.values[4] = result.depth;
    row.values[5] = world.x; row.values[6] = world.y; row.values[7] = world.z;
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    // A fault after association validation is still an unknown association;
    // never grant projection grace to a potentially recycled/freed slot.
    for (float &value : row.values) value = 0;
    return false;
  }
}

int DoValidatedPlateProjections(void *L) {
  // (command, GUIDs, count, output, live unit tokens, native parent frames).
  // Per row: current, projected, x, y, depth, worldX, worldY, worldZ.
  if (LuaGetTop(L) < 6 || LuaType(L,2) != 5 || LuaType(L,3) != 3 || LuaType(L,4) != 5 ||
      LuaType(L,5) != 5 || LuaType(L,6) != 5) { LuaPushNil(L); return 1; }
  const double requested = LuaToNumber(L,3);
  if (!std::isfinite(requested) || requested < 0 || requested > kNameplateBatchLimit ||
      std::floor(requested) != requested) { LuaPushNil(L); return 1; }
  const int count = static_cast<int>(requested);
  const int oldLength = At<LuaLGetNFn>(kLuaLGetN)(L,4);
  if (oldLength < 0 || oldLength > kNameplateBatchLimit*kValidatedPlateStride) { LuaPushNil(L); return 1; }
  Vec3 camera{}, forward{}, right{}, up{};
  float fov = 0, aspect = 0;
  ProjectionViewport viewport{};
  if (count && (!CameraState(camera,forward,right,up,fov,aspect) || !ReadProjectionViewport(viewport))) {
    LuaPushNil(L); return 1;
  }
  std::vector<ValidatedPlateRow> rows;
  rows.swap(g_validatedPlateScratch); rows.clear();
  if (rows.capacity() < static_cast<size_t>(count)) { rows.reserve(count); ++g_validatedPlateGrowths; }
  rows.resize(count);
  for (int i=0; i<count; ++i) {
    At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L,2,i+1);
    const char *guid = LuaType(L,-1)==4 ? LuaToString(L,-1) : nullptr;
    if (IsBatchGuid(guid)) std::memcpy(rows[i].guid,guid,sizeof(rows[i].guid));
    At<LuaSetTopFn>(kLuaSetTop)(L,-2);
    At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L,5,i+1);
    const char *token = LuaType(L,-1)==4 ? LuaToString(L,-1) : nullptr;
    if (token && std::strlen(token)>0 && std::strlen(token)<sizeof(rows[i].token))
      std::memcpy(rows[i].token,token,std::strlen(token)+1);
    At<LuaSetTopFn>(kLuaSetTop)(L,-2);
    At<FrameScriptPushObjectFn>(kFrameScriptPushObject)(L,6,i+1);
    if (LuaType(L,-1)==5) rows[i].frame=reinterpret_cast<uintptr_t>(ResolveLuaObject(L,-1));
    At<LuaSetTopFn>(kLuaSetTop)(L,-2);
  }
  {
    ScopedReadableRegions readable;
    for (auto &row : rows) {
      if (row.guid[0]) ValidateAndProjectPlate(row,camera,forward,viewport);
      g_validatedPlateCurrent += row.values[0]==1;
      g_validatedPlateProjected += row.values[1]==1;
      row.frame=0; // No retained native frame pointers, including scratch capacity.
    }
  }
  ++g_validatedPlateCalls; g_validatedPlateRows+=count;
  int key=0;
  for (const auto &row : rows)
    for (float value : row.values) { LuaPushNumber(L,value); LuaRawSetI(L,4,++key); }
  for (int i=key+1; i<=oldLength; ++i) { LuaPushNil(L); LuaRawSetI(L,4,i); }
  At<LuaLSetNFn>(kLuaLSetN)(L,4,key);
  LuaPushNumber(L,count);
  rows.clear();
  if (rows.capacity()<=kNameplateBatchLimit && rows.capacity()>g_validatedPlateScratch.capacity())
    rows.swap(g_validatedPlateScratch);
  return 1;
}
