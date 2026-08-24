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

## Nameplate compatibility

The attachment layer first checks common exposed health-bar fields, then scans
the plate's normal frame children for a StatusBar. GUID-aware Nampower events
are preferred for precise AoE routing; legacy name-only messages are distributed
across matching visible plates.

MSBT remains the source of combat parsing, event formatting, fonts, colors,
profiles, suppressions, merge behavior, text speed, and fade timing.
