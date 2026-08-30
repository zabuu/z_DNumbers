# zAPI

Small native projection API for the 32-bit WoW 1.12.1.5875 client used by
OctoWoW. It is loaded through VanillaFixes `dlls.txt` and registers one Lua
global without detouring UnitXP:

```lua
zAPI("version")
x, y, z, height = zAPI("unitPosition", unitTokenOrGUID)
x, y, depth = zAPI("worldToScreen", worldX, worldY, worldZ)
x, y, depth, worldX, worldY, worldZ = zAPI("projectUnit", unitTokenOrGUID, verticalOffset)
cameraX, cameraY, cameraZ, forwardX, forwardY, forwardZ,
  rightX, rightY, rightZ, upX, upY, upZ, fov, aspect = zAPI("camera")
```

Projected `x` and `y` are normalized with a bottom-left origin, ready to map
through `UIParent:GetWidth()` and `UIParent:GetHeight()`. `depth` is distance
along the live camera forward vector and can be used for perspective scaling.

The DLL validates the expected x86 client timestamp and image size before
installing its single hook. Unsupported clients fail closed instead of using
unchecked addresses.
