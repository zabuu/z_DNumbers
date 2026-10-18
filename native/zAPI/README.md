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
An unsupported build or detour rejects the bridge.

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
