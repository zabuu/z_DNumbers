# zDNumbers

`zDNumbers` is an OctoWoW addon that embeds Mik's Scrolling Battle Text and
places outgoing player and pet damage above the nameplate belonging to the
affected unit.

It does not require zNameplates or pfUI. It listens to OctoWoW's
`NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED` API and discovers a usable
health bar structurally, so it can attach to Blizzard nameplates or another
nameplate replacement without addon-specific integration.

## Usage

- `/zdn` or `/zdnumbers` opens attachment, placement, alignment, and fade settings.
- `/msbt` opens the embedded MSBT font, color, event, text, speed, and profile settings.
- Disable separate `MikScrollingBattleText` and `MikScrollingBattleTextOptions`
  addons while using zDNumbers; they are already included.

When upgrading from the combined zNameplates build, leave zNameplates enabled
for the first login. zDNumbers lists it as an optional load-order dependency so
the previous `MikSBT_Save` profile and per-character placement values can be
picked up and saved under zDNumbers.

Fresh installs use the saved Zabbu preset for attachment settings and the
embedded MSBT factory profile: 55% source-icon opacity, 142 px travel height,
0.65 sec attachment fade delay, 30% perspective depth, Expressway typography,
and the captured MSBT colors, text speed, scroll areas and notifications.
Existing character settings and saved MSBT profiles are not overwritten.
Explicit resets/new MSBT profiles use the new factory preset. Other locales
fall back to a valid bundled/client font when Expressway is unavailable.

## Nameplate compatibility

The attachment layer first checks common exposed health-bar fields, then scans
the plate's normal frame children for a StatusBar. GUID-aware Nampower events
are preferred for precise AoE routing; legacy name-only messages are distributed
across matching visible plates.

MSBT remains the source of combat parsing, event formatting, fonts, colors,
profiles, suppressions, merge behavior, text speed, and fade timing.

New events no longer shove nearby numbers upward by a full font size plus
eight pixels. Collision layout uses the lower number's rendered height (or
result/source-icon footprint) with a two-pixel gap, and eases only the added
displacement over roughly 75 ms. Normal travel speed remains unchanged. The
same eased position drives both regular screen text and native depth motion;
crowded entries retire after reaching the boundary, not when a pending push
would put them there.

## Performance

Text/icon slots are allocated only when a number needs them and reused later;
idle nameplates do not run animation tracking. Numbers on the same unit share
one base projection per rendered frame, while each elevated point still gets
its own live camera projection. Frozen/dead anchors use remembered world points
without repeatedly resolving an expired unit.

Rounded-icon geometry, font height, perspective setup, alignment and opacity
are changed only when needed. Motion and fades still update every rendered
frame. Modern nameplate enumeration avoids duplicate attachments; legacy/mixed
hosts retain periodic recovery and immediate recovery on an unmatched damage
batch. MSBT formatting, merging, ten-slot capacity, depth and profiles remain
unchanged.
