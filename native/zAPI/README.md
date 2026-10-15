# zAPI

Native utility API for the 32-bit WoW 1.12.1.5875 client used by
OctoWoW. It is loaded through VanillaFixes `dlls.txt` and registers one Lua
global without detouring UnitXP:

```lua
zAPI("version")
petCommandVersion = zAPI("petCommandVersion") -- 1 when the bridge is compatible
submitted, reason = zAPI("petCommand", "attack", unitTokenOrGUID)
submitted, reason = zAPI("petCommand", "follow") -- also "stay" and "passive"
x, y, z, height = zAPI("unitPosition", unitTokenOrGUID)
x, y, z, height = zAPI("losPosition", unitTokenOrGUID)
x, y, depth = zAPI("worldToScreen", worldX, worldY, worldZ)
x, y, depth, worldX, worldY, worldZ = zAPI("projectUnit", unitTokenOrGUID, verticalOffset)
x, y, depth, worldX, worldY, worldZ = zAPI("projectNameplate", unitTokenOrGUID, verticalOffset)
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

Build with `./build.ps1`. Deployment is explicit (`./build.ps1 -Deploy`) and
requires replacing the game-root DLL; a locked file fails without renaming a
loaded DLL. Back up that DLL before deploying. A full game restart is required,
because `/reload` cannot replace the DLL already loaded into the client.
