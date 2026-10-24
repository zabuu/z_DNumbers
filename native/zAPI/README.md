# zAPI

Native utility API for the 32-bit WoW 1.12.1.5875 client used by
OctoWoW. It is loaded through VanillaFixes `dlls.txt` and registers one Lua
global without detouring UnitXP:

```lua
zAPI("version")
bufferVersion = zAPI("nearbyBufferVersion") -- 1 for the reusable output contract
-- Keep a private dense output array; subsequent calls replace its contents.
nearby = {}
count = zAPI("nearbyCreaturesInto", 30, "pet", nearby)
legacyCalls, bufferCalls, nativeGrowths, retainedCapacity = zAPI("nearbyScanStats")
petCommandVersion = zAPI("petCommandVersion") -- 1 when the bridge is compatible
submitted, reason = zAPI("petCommand", "attack", unitTokenOrGUID)
submitted, reason = zAPI("petCommand", "follow") -- also "stay" and "passive"
x, y, z, height = zAPI("unitPosition", unitTokenOrGUID)
x, y, z, height = zAPI("losPosition", unitTokenOrGUID)
x, y, depth = zAPI("worldToScreen", worldX, worldY, worldZ)
x, y, depth, worldX, worldY, worldZ = zAPI("projectUnit", unitTokenOrGUID, verticalOffset)
x, y, depth, worldX, worldY, worldZ = zAPI("projectNameplate", unitTokenOrGUID, verticalOffset)
batchVersion = zAPI("nameplateBatchVersion") -- 1 in zAPI 2.8
guids, projected = {}, {} -- private, reusable arrays; fill guids with GUID strings
count = zAPI("projectNameplatesInto", guids, inputCount, projected)
batchCalls, batchRows, batchGrowths, retainedRows = zAPI("nameplateBatchStats")
x, y, depth, worldX, worldY, worldZ = zAPI("projectUnitForward", unitTokenOrGUID, verticalOffset, forwardYards)
groundVersion = zAPI("groundObjectVersion") -- 1 in zAPI 2.2
guid, x, y, z, objectType, entryOrSpellID, state = zAPI("groundObject", objectType, entryOrSpellID, excludedGUID)
guid, x, y, z, objectType, entryOrSpellID, state = zAPI("groundObjectState", guid)
tick, sourceX, sourceY, sourceDepth, sourceWorldX, sourceWorldY, sourceWorldZ,
  targetX, targetY, targetDepth, targetWorldX, targetWorldY, targetWorldZ =
  zAPI("projectLine", sourceUnit, targetUnit, sourceZOffset, targetZOffset)
tick, viewportLeft, viewportRight, viewportBottom, viewportTop,
  marginBottom, marginLeft = zAPI("projectionProbe")
tick, projectedX, projectedY, cursorX, cursorY, worldX, worldY, worldZ, depth =
  zAPI("cursorProjection")
cameraX, cameraY, cameraZ, forwardX, forwardY, forwardZ,
  rightX, rightY, rightZ, upX, upY, upZ, fov, aspect = zAPI("camera")
```

Projected `x` and `y` are normalized with a bottom-left origin, ready to map
through `UIParent:GetWidth()` and `UIParent:GetHeight()`. `depth` is distance
along the live camera forward vector and can be used for perspective scaling.
`losPosition` returns the unit base position raised by its collision-box height,
matching the eye point used by UnitXP/ClassicAPI line-of-sight traces.

`projectNameplate` (zAPI 1.9) uses the client's model name attachment and its
native world-space clearance, exactly as the original nameplate projection
does before screen-space collision placement. Unlike `projectUnit`, it is not
based on collision-box height. It never reads or repositions a nameplate frame;
an unavailable model/attachment returns nil rather than a different anchor.
`projectUnit` and damage-number callers retain their existing behavior.

Version 2.8 adds batched name-attachment projection for zNameplates 2.1.2.
`projectNameplatesInto` accepts up to 512 GUID strings and an explicit integer
count, and replaces the caller's private output array. Each input occupies seven
dense numeric slots: `valid, x, y, depth, worldX, worldY, worldZ`. A missing,
invalid, off-camera or unavailable model emits seven zeros (`valid = 0`); a
successful projection has `valid = 1`. The command returns the input count on
success, including zero. Nil means the whole call failed and output is unchanged.
Shrinking/empty successful calls clear the old tail and update Lua 5.0's stored
array length. Count/type/length checks bound both work and retained buffers.

The batch captures the camera and WorldFrame viewport once per call, then uses
the exact existing model-name-attachment and native WorldToScreen/DDC conversion
for every GUID. It does not scan the object list, borrow collision-shifted native
frames, approximate unit height, change clipping, or cache object/model/camera
pointers across calls. Output coordinates and depth have the same meaning as
`projectNameplate(guid, 0)`. World attachment coordinates are not unit origins:
existing world-distance samples remain separate at their unchanged cadence.

Each invocation owns its native scratch vector through output, including during
reentrant Lua allocation; at most 512 rows are retained for reuse. No per-row Lua
tables or strings are created by the command. `nameplateBatchStats` reports
cumulative successful batches, input rows, scratch-capacity growths, and currently
retained rows. These are diagnostic counts, not measured FPS or allocation times.
Old commands and the 2.7 pet bridges remain unchanged. Native tests compare batch
output with the actual single-unit projection helper and cover failures, reentry,
stored lengths and 10,000 warm batches. A full client restart loads the new DLL.

Version 2.9 retains this version-1 batch contract. It copies validated GUIDs into
the bounded scratch rows before projection, then shares successful `VirtualQuery`
region checks during the native computation phase only (32 region slots). No
unit, model, position, camera or page view survives the batch. Live reads and
per-row SEH remain; input/output run outside the page-cache scope, including
allocation/reentry. Other commands retain uncached memory validation. A 50-row
native fixture with real Windows page queries reduces 400 queries to 1 and took
0.190 ms versus 0.032 ms per batch on the development machine. Those timings
isolate validation overhead with simulated client geometry; they are not WoW FPS
measurements. Tests also cover scope nesting, overflow, protected pages between
calls, projection parity, failures, reentry and bounded warm storage.

Version 3.1 adds live association validation to a separate projection contract:

```lua
supported = zAPI("nameplateValidationVersion") -- 1
count = zAPI("projectNameplatesValidatedInto", privateGuids, inputCount,
             privateOutput, privateUnitTokens, privateNativeParentFrames)
calls, rows, current, projected, growths, capacity = zAPI("nameplateValidationStats")
```

Each of up to 512 rows emits eight numbers: current, projected, x, y, depth,
worldX, worldY, worldZ. Flags are 0/1. The live token must resolve to the expected
GUID; the unit's nameplate pointer and frame's GUID must both match the supplied
parent wrapper. These fields (`CGUnit+0x30`, `+0xE60`, frame `+0x4E8`) and the
extended token resolver are verified against this client's ClassicAPI sources.
One live unit lookup supplies validation and the existing projection math.
Current=1/projected=0 describes a current unit whose model cannot project;
stale associations or faults produce all zeroes. No native pointers survive the
computation phase. Input is copied before native reads; successful page checks
are shared only within that phase. Whole-call failure leaves output unchanged;
empty/shrinking output, Lua 5.0 stored lengths, aliasing and reentry follow the
existing batch contract. The version-1 projection API is unchanged.

Production native tests cover scalar parity, live camera changes, all association
checks, missing models, native faults, reentry, bounds and 10,000 warm batches.
Lua fixtures exercise both render branches and older-DLL/failure fallbacks.
A full client restart loads the new DLL; work counts do not establish live FPS.

Version 3.0 adds a nameplate-specific sight batch:

```lua
supported = zAPI("nameplateSightVersion") -- 1
count = zAPI("nameplateSightInto", privateGuidArray, inputCount, privateOutput)
calls, rows, traces, hits, growths, capacity = zAPI("nameplateSightStats")
```

Up to 512 strict GUID strings produce one dense output each: `1` clear, `0`
blocked, `-1` unknown. A whole-call failure returns nil and leaves output
unchanged. Empty/shrinking successful calls clear the tail and update Lua 5.0's
stored length. Arrays may alias; each invocation owns its scratch through Lua
output/reentry. Private scratch capacity is retained up to 512 rows.

The player is resolved/read once per batch. Every target is resolved live, even
on result-cache hits. Sight geometry matches the retained UnitXP implementation:
first trace at the shorter unit's CMovement collision height, then (only when
blocked and heights differ) a head-to-head trace. The query mask is `0x100111`,
intersection bounds include 0 and 1, and UnitXP's 150-yard/epsilon guards apply.
The existing `lineOfSight`, pet and terrain commands retain their contracts.

A fixed 512-slot direct-mapped cache stores only source/target GUIDs, result and
timestamps. Collisions evict entries. Results expire after 100–160 ms with
deterministic GUID dither (UnitXP uses random dither in the same range). One
high-resolution clock read is shared by the batch. Missing units and faults are
unknown; only valid results are cached. SEH and successful page checks are scoped
to the native phase; no object, movement or model pointer survives a call.
No new hook, object-list scan, forced collection or GC setting is introduced.

Production native tests compare 1,600 geometry cases with the retained UnitXP
source, including every ray endpoint/mask. They also cover expiry, source
identity, disappearing units, faults, strict inputs, reentry, output ownership,
Lua 5.0 lengths and 10,000 warm batches. Lua integration fixtures preserve due
sample counts/fades/scales/anchors while replacing 5,050 individual calls with
601 batches (50 plates, ten seconds, normal cadence), or 2,550 calls with 401
batches for background-friendly plates. These are offline work counts; live
timings require another capture after a full client restart.

`projectLine` is the zAPI 1.5 atomic projection path. It resolves both unit
positions and projects them against one camera capture. If the target is behind
the near plane, its screen coordinate becomes a synthetic point along the same
snapshot's camera-space bearing so callers can place a correct edge arrow.
`projectionProbe` exposes the WorldFrame viewport fields needed to diagnose
client-specific normalized-coordinate offsets without modifying them.
`cursorProjection` is the zAPI 1.6 calibration primitive. It raycasts the
terrain under the OS cursor, projects the resulting world point, and returns
both normalized positions from the same native call for an unambiguous
native-to-UI viewport mapping.

The DLL validates the expected x86 client timestamp and image size before
installing its single hook. Unsupported clients fail closed instead of using
unchecked addresses.

The zAPI 2.0 pet bridge uses the same fastcall dispatcher and command values
as this client's PetAttack/PetFollow/PetWait/PetPassiveMode. It passes the
victim GUID directly, so it never changes the player's target or target history.
Only those four commands are exposed. The caller must still check hostility,
crowd control, recall, feeding, mode and distance; zPet performs those checks.
The native side checks the live-world byte flag, resolves a living active pet,
validates a living attack target, and verifies the dispatcher's byte signature.
Unsupported builds or unrecognized detours reject the bridge. Version 2.7
also recognizes the inspected Nampower 4.6.2 hook chain described below.

The call temporarily sets the frame-script context to zero only around the
fixed pet dispatcher. It restores the saved context and depth with Windows
structured exception handling, rejects reentry, and does not accept arbitrary
Lua or numeric opcodes. `submitted == 1` means the dispatcher returned;
zPet separately waits for pet-target/action acknowledgement. Zero plus a reason
means rejection. No extra client hook or continuous native scan is installed.

Version 2.1 adds reusable nearby-creature output. `nearbyCreaturesInto` returns
the number written (including zero); nil means failure and leaves the output
unchanged. The caller must supply a private dense array as argument four.
Successful queries clear the old tail and update Lua 5.0's stored array length,
so `table.getn` remains correct after shrinking/empty results. It preserves the
same complete nearest-first creature results as `nearbyCreatures`; the legacy
command continues returning a new independently owned table. GUIDs stay strings
to retain all 64 bits. No Lua table pointers are retained natively.

Both scan paths reuse native vector capacity, retaining at most 4,096 entries
of scratch capacity per thread. Larger results remain complete; their excess
capacity is released after output. Each active query owns its vector until all
Lua output is complete, so a query reentered during Lua allocation/finalization
cannot overwrite another query's results. `nearbyScanStats` returns cumulative
successful legacy calls, buffer calls, queries that grew vector capacity and the current
thread's retained capacity as scalar numbers. These diagnose this scan path;
they are not allocator or garbage-collector duration statistics.

zPet 1.4.3 probes `nearbyBufferVersion` once, uses a private reused array with
compatible DLLs and keeps the old command for older DLLs. Its existing 0.5-second
query cache and object-discovery opt-in remain. Distance-cache records are reused
with a bounded 256-record free pool; distance freshness, invalidation, unknown
results and pet behavior remain. Neither addon changes GC settings or forces
collections. This reduces one source of temporary allocations; live captures
are still needed to measure any effect on hitches.

Build with `./build.ps1`. Deployment is explicit (`./build.ps1 -Deploy`) and
requires replacing the game-root DLL; a locked file fails without renaming a
loaded DLL. Back up that DLL before deploying. A full game restart is required,
because `/reload` cannot replace the DLL already loaded into the client.

Version 2.2 adds read-only forward projection and owned-ground-object queries.
`projectUnitForward` offsets XY along the unit's live facing, not the camera's,
and retains the usual collision-height + vertical-offset projection. Forward
distance must be finite and between 0 and 8 yards. zDNumbers uses it for a
pet-nose damage anchor.

`groundObject` scans for one matching player-owned trap (object type 5, trap GO
type 6, ID = object entry) or dynamic object (type 6, ID = generating spell).
It can exclude the preceding GUID during a replacement cast.
`groundObjectState` resolves a known owned GUID directly without a scan. Both
validate object type, descriptor range, descriptor GUID, owner GUID and finite
coordinates, returning nil on failure. They do not expose other players' hidden
traps, accept memory addresses, change targets, install new hooks, or draw
native cards. Position/type/owner fields follow the
[1.12.1 UpdateFields contract](https://github.com/vmangos/core/blob/development/src/game/Objects/UpdateFields_1_12_1.h).
The addon, not this native API, tracks observed creation/trigger time and expiry.

Version 2.4 adds a read-only gathering snapshot for zMap:

```lua
compatible = zAPI("gatherBufferVersion") -- 1
local buffer = {} -- private, reused caller-owned dense array
count, playerX, playerY, playerZ = zAPI("gatherObjectsInto", buffer)
queries, retainedNativeCapacity = zAPI("gatherScanStats")
```

Each object occupies ten consecutive entries: GUID string, object entry,
world X/Y/Z, display ID, GO type, state, flags and dynamic flags. `count` is
the number of objects, while `table.getn(buffer)` is `count * 10`. Results
sort by full GUID. Zero means a successful empty snapshot; nil means failure
and leaves the buffer unchanged. The player position belongs to the same
synchronous query. Lua 5.0's stored array length and old tail are updated.

The query enumerates only client-loaded public gameobjects, accepts container
type 3 and fishing-hole type 25, and rejects traps, fishing bobbers, used
containers and noninteractive objects. Descriptor GUID/type/range, finite
positions and live player/world state are checked. Resource identification
belongs to zMap's identity catalogue; these results contain no remote spawn
database or respawn prediction. No target, interaction, tracking buff, network
request, memory-writing command or additional engine hook is added.

Native scratch capacity and Lua output are reused. Reentry cannot overwrite
an outer query's vector. At most 4,096 native records are retained between
queries; larger successful snapshots remain complete and release excess
capacity. A malformed million-entry caller buffer or snapshot larger than
100,000 objects fails instead of returning partial live state. zMap scans
twice per second only while its window and live gathering are enabled.

Version 2.3 adds signature-verified GC controls for OctoGC:

```lua
compatible = zAPI("gcControlVersion") -- 1 or 0
luaKB, thresholdKB, virtualFreeKB, totalVirtualKB, commitFreeKB = zAPI("gcStatus")
accepted, reason = zAPI("gcSetThreshold", thresholdKB)
accepted, milliseconds, freedKB, afterKB, nextThresholdKB = zAPI("gcCollect")
```

`gcSetThreshold` accepts integral KB, at least live usage plus 1 MiB and at
most 1 GiB. Raising it additionally requires enough virtual address space for
the remaining Lua headroom plus 256 MiB, and commit headroom plus 128 MiB.
Lowering to a still-safe value is allowed under pressure. It cannot request a
collection. Callers must also respect their script-memory budget; OctoGC does.

`gcCollect` is the separate full-cycle command. It rejects player or pet combat,
unknown world/unit state, bad descriptor pointers and recursive collection.
It uses the verified public Lua 5.0 threshold API with zero, timing the actual
call with QPC. Other commands never fall through to collection. Failure returns
`0, reason`. No hook/VM patch or global collectgarbage replacement is added.
Exact count/threshold/setter entry bytes must match the inspected client.

These controls make bounded combat deferral possible; they do not promise that
all collection can be postponed safely or that full cleanup becomes incremental.
The Lua scheduler, tests and limits are documented in `OctoGC/README.md` under
the AddOns root. Existing 2.2 forward/ground queries and earlier APIs remain.

Version 2.5 reduces rendering overhead while preserving these command contracts.
Font trapezoid transforms retain two buffers per active font in one state record,
validate glyph pages once per synchronous operation, and skip rewriting an
already identical transform. Normal warmed transforms allocate no temporary
vertex vectors; unusually large capacities are released when text shrinks below
the 32,768-float retention limit. Disabling a transform still restores the original
vertices and releases its state. The draw hook immediately passes through when
no fonts use the effect.

`projectLine` captures the viewport once for both endpoints and reuses resolution,
position and projection work when both endpoints refer to the same unit/point.
All camera/unit data is still read during each call; no cross-frame position,
camera or raycast-result cache is introduced. The DLL is built with `/O2` speed
optimization. Texture safety guards, pet command validation, nearby/gathering
buffers and GC controls retain their behavior.

Version 2.6 adds a narrow OctoWoW Take Position bridge for zPet:

```lua
compatible = zAPI("petPositionVersion") -- 1 when placement signatures match
tx, ty, tz, facing, px, py, pz, radius, pvp, tanking = zAPI("petRearState", targetGUID)
submitted, x, y, z = zAPI("petTakePosition", targetGUID)
-- Failure: 0, reason. State-query failure: nil.
```

State reads living owner/pet/target geometry atomically; facing uses radians.
PvP includes player-controlled enemies. Tanking means target's victim GUID is
the pet, independently of Growl; zPet checks actual Growl autocast state.
Take Position computes the rear point itself and validates range, nearby ground
elevation and obstruction. It accepts no caller-provided spell, opcode or XYZ.
Only learned player spellbook IDs 6/8 with the exact custom DBC name are allowed.
Existing ground placement is never consumed. The byte-verified x86 spell and
placement functions run in a scoped native context with reentry rejection and
SEH restoration, using the same coordinate-placement primitive as ClassicAPI.
There is no additional hook or direct coordinate write. Submission is not
movement acknowledgement; zPet observes arrival, sends Attack after Stay,
and handles safety, ownership, timeout, replan cadence and backoff in Lua.

Version 2.7 fixes compatibility with the installed Nampower 4.6.2. Its pet,
spellbook and terrain-click detours replace the entry bytes that 2.6 required
to remain untouched. `VerifiedNativeEntry.h` now accepts original entries or
the verified Hadesmem x86 gate. It checks every fixed instruction byte, the
untouched client signature after the five-byte jump, readable hook context,
executable gate/callbacks, and callback/vtable/implementation ownership in the
inspected Nampower module (PE timestamp `0x6A99D431`, image size `0xDB000`).
It never calls the gate's helper or a virtual method during validation.
Unknown versions, modified bodies and foreign/unrecognized gates fail closed.
Calls continue through the installed entry and hook chain; no bypass, new hook,
patch or trampoline invocation is introduced. All earlier API contracts remain.

```lua
petEntryDetail, placementEntryDetail = zAPI("petBridgeStatus")
```

These read-only diagnostics explain rejected compatibility and identify accepted
Nampower hooks. zPet 1.5.1 caches them during initialization for `/zpet status`.
The former generic restart message no longer hides an actual rejection.
Reference sources: Nampower commit `2c7f51cd436e9b0ce88271e84ce5a77c19f2c23b`,
Hadesmem commit `741a29dc817ce4aff5c3c3cd29e0832597108b1d`, retained read-only
under `_zPetMaintenance/native-reference/`. Tests cover valid original/hooked
entries, all 40 fixed gate-byte mutations, invalid callbacks/context/body/memory
permissions and 10,000 validations, plus the existing scoped command/placement
ABI and exception recovery suites. Live game behavior needs separate validation.
