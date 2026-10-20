// Included after the shared unit/geometry helpers in zAPI.cpp.
struct PetRearState {
  Vec3 target{}, pet{}, point{};
  float facing = 0, radius = 0;
  bool pvp = false, tanking = false;
};

bool CheckPetPositionBridge(const char *&detail) {
  static const uint8_t dispatch[] = {0x55,0x8B,0xEC,0x83,0xEC,0x20,0x53,0x56,0x8B,0xF2,0x57};
  static const uint8_t commit[] = {0x66,0xA1,0xC0,0xCA,0xCE,0x00,0x66,0x85,0xC0,0x75,0x03,0x32,0xC0,0xC3};
  static const uint8_t cancel[] = {0xE8,0x9B,0xFF,0xFF,0xFF,0x84,0xC0,0x74,0x0B};
  if (!CheckPetCommandBridge(detail)) return false;
  const auto castEntry = InspectNativeEntry(kPositionSpellDispatch, dispatch, sizeof(dispatch));
  if (!NativeEntryAccepted(castEntry)) { detail = NativeEntryDescription(castEntry); return false; }
  const auto groundEntry = InspectNativeEntry(kPositionCommit, commit, sizeof(commit));
  if (!NativeEntryAccepted(groundEntry)) { detail = NativeEntryDescription(groundEntry); return false; }
  const auto cancelEntry = InspectNativeEntry(kPositionCancel, cancel, sizeof(cancel));
  if (!NativeEntryAccepted(cancelEntry)) { detail = NativeEntryDescription(cancelEntry); return false; }
  if (!IsReadable(At<uintptr_t>(kPositionPlacement), 4)) { detail = "placement state unavailable"; return false; }
  detail = castEntry == NativeEntryResult::Nampower || groundEntry == NativeEntryResult::Nampower ?
    "verified Nampower 4.6.2 placement hooks" : "original placement entries";
  return true;
}
bool PetPositionAvailable() {
  const char *detail = nullptr; return CheckPetPositionBridge(detail);
}

bool ReadPetRearState(const char *guid, PetRearState &state) {
  __try {
    if (!CompatibleClient() || !guid || std::strncmp(guid, "0x", 2) != 0 ||
        !IsReadable(At<uintptr_t>(kInWorld), 1) || !*At<const uint8_t *>(kInWorld)) return false;
    uint32_t target = 0, pet = 0, player = 0;
    if (!ResolveUnit("player", player) || !LivingUnit(player) ||
        !ResolveUnit(guid, target) || !LivingUnit(target) ||
        !ResolveUnit("pet", pet) || !LivingUnit(pet) || target == player || target == pet ||
        !UnitPosition(target, state.target) || !UnitPosition(pet, state.pet) ||
        !UnitFacing(target, state.facing)) return false;
    const uint32_t fields = *reinterpret_cast<const uint32_t *>(target + 0x110);
    const uint32_t petFields = *reinterpret_cast<const uint32_t *>(pet + 0x110);
    if (!IsReadable(fields, 0x1F4) || !IsReadable(petFields + 0x1F0, 4)) return false;
    // UNIT_FIELD_COMBATREACH follows BOUNDINGRADIUS. Use a point within the
    // combined reach, leaving space for server chase rather than model overlap.
    // Global update-field index 130 minus the six OBJECT_FIELD words:
    // (130 - 6) * 4 = 0x1F0 within CGUnit +0x110's unit-field block.
    // +0x1F4 is DISPLAYID, not a float reach.
    const float targetReach = *reinterpret_cast<const float *>(fields + 0x1F0);
    const float petReach = *reinterpret_cast<const float *>(petFields + 0x1F0);
    if (!std::isfinite(targetReach) || !std::isfinite(petReach) || targetReach <= 0 ||
        targetReach > 30 || petReach <= 0 || petReach > 10) return false;
    state.radius = std::clamp(targetReach + petReach - 0.75f, 1.5f, 15.0f);
    state.point = {state.target.x - std::cos(state.facing) * state.radius,
                   state.target.y - std::sin(state.facing) * state.radius, state.target.z};
    state.pvp = *reinterpret_cast<const int *>(target + 0x14) == kObjectTypePlayer ||
      (*reinterpret_cast<const uint32_t *>(fields + 0xA0) & 0x08) != 0;
    state.tanking = *reinterpret_cast<const uint64_t *>(fields + 0x28) == ResolveGuid("pet");
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

bool FindTakePositionSlot(unsigned &slot) {
  __try {
    const auto *book = At<const uint32_t *>(kPlayerSpellbook);
    if (!IsReadable(reinterpret_cast<uintptr_t>(book), 1024 * 4) ||
        !IsReadable(At<uintptr_t>(kSpellDbcRecords), 4)) return false;
    const auto records = *At<const uintptr_t *const *>(kSpellDbcRecords);
    if (!records) return false;
    for (unsigned i = 0; i < 1024; ++i) {
      // Both IDs are Take Position in OctoWoW's installed patch-O/patch-5 DBC.
      // Check the English DBC name too: vanilla ID 6 is a different spell.
      if (book[i] != 6 && book[i] != 8) continue;
      if (!IsReadable(reinterpret_cast<uintptr_t>(records + book[i]), 4)) continue;
      const uintptr_t record = records[book[i]];
      if (!IsReadable(record + 0x1E0, 4)) continue;
      const char *name = *reinterpret_cast<const char *const *>(record + 0x1E0);
      if (!IsReadable(reinterpret_cast<uintptr_t>(name), sizeof("Pet Command: Take Position")) ||
          std::memcmp(name, "Pet Command: Take Position", sizeof("Pet Command: Take Position")) != 0) continue;
      slot = i; return true;
    }
    return false;
  } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

bool TakePetRearPosition(const char *guid, Vec3 &destination, const char *&reason) {
  __try {
    if (!PetPositionAvailable()) { reason = "unsupported placement functions"; return false; }
    if (*At<const uint32_t *>(kPositionPlacement) != 0) { reason = "cursor spell already active"; return false; }
    PetRearState state;
    if (!ReadPetRearState(guid, state)) { reason = "rear geometry unavailable"; return false; }
    unsigned slot = 0;
    if (!FindTakePositionSlot(slot)) { reason = "Take Position not learned"; return false; }
    uint32_t player = 0; Vec3 owner{};
    if (!ResolveUnit("player", player) || !UnitPosition(player, owner)) return false;
    auto distanceSq = [](const Vec3 &a, const Vec3 &b) {
      const float x=a.x-b.x, y=a.y-b.y, z=a.z-b.z; return x*x+y*y+z*z;
    };
    if (distanceSq(owner, state.point) > 40*40 || distanceSq(state.pet, state.point) > 25*25) {
      reason = "rear point outside safe movement range"; return false;
    }
    // Require a floor close to the target's elevation. No blind Z reuse over
    // cliffs, water, another floor, or an untraceable destination.
    Vec3 high = state.point, low = state.point, ground{}; float t = 1;
    high.z += 2; low.z -= 3;
    if (!SafeIntersect(&high, &low, &ground, &t, kLoSFlags) ||
        !std::isfinite(ground.x) || !std::isfinite(ground.y) || !std::isfinite(ground.z) ||
        std::abs(ground.z - state.target.z) > 2.5f) {
      reason = "no nearby floor behind target"; return false;
    }
    Vec3 start = state.target, end = ground, hit{};
    start.z += 0.8f; end.z += 0.8f;
    if (SafeIntersect(&start, &end, &hit, &t, kLoSFlags)) {
      reason = "rear point obstructed"; return false;
    }
    static uint32_t lastMoveTick = 0;
    const uint32_t now = At<GetTickCountFn>(kGetTickCount)();
    if (lastMoveTick && now - lastMoveTick < 750) { reason = "movement command cooldown"; return false; }
    lastMoveTick = now;
    const float xyz[] = {ground.x, ground.y, ground.z};
    if (!DispatchScopedPetPosition(At<PositionSpellDispatchFn>(kPositionSpellDispatch),
        At<PositionCommitFn>(kPositionCommit), At<PositionCancelFn>(kPositionCancel),
        At<uint32_t *>(kPositionPlacement), At<uint32_t *>(kFrameScriptContext),
        At<uint32_t *>(kFrameScriptDepth), &g_petCommandBusy, slot, xyz)) {
      reason = "Take Position placement rejected"; return false;
    }
    destination = ground; return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) { reason = "native placement validation exception"; return false; }
}
