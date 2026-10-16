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
- In `/zdn`, enable **Split pet damage into a separate stream**. It is off
  by default, preserving the combined stream. The default **Over the pet** anchor
  places the stream over the pet's nose, using its own facing rather than the
  enemy's nameplate. **Forward distance past the pet** adjusts this world offset.
  Pet damage does not need a visible enemy or pet nameplate. Off-screen/missing
  pets return new hits to the ordinary MSBT Pet Outgoing area. Already-visible
  pet numbers transfer there once, then continue with MSBT's normal lifetime.
  zAPI 2.2 supplies the exact forward anchor; older DLLs use the pet's head.
  MSBT retains the fonts, colours, filters, formatting and crit settings.
  The optional **Beside target (legacy)** mode retains the previous layout:
  pet numbers
  orbit the main stream's starting point on a horizontal world plane, turning
  through 360 degrees toward your pet's X/Y position. Both streams start at the
  same world elevation; uphill/downhill pets do not tilt the ring. The camera
  projects this level ring into perspective, and numbers continue rising from
  their respective starting points with readable, camera-facing text.
  Each nameplate gets separate ten-number player/pet pools. Position is resolved
  per number against nearby text, crits and icons. A wide crit only displaces the
  pet hits beside that row, rather than pushing the entire pet stack away.
  When the pet-facing direction lines up vertically with the regular stream
  (behind/in front of the target), player and pet slots weave in an alternating
  zipper, retaining order within each source. Side-facing streams retain their
  independent vertical spacing. Pet hits fit into individual gaps, with a
  two-pixel clearance plus outline allowance; unused scroll-area width is ignored.
  World yaw and each number's gap closure are smoothed, with a small center dead zone to avoid
  jitter. One pet X/Y lookup per frame is shared across all streams; one level
  projection per active nameplate supplies the ring's perspective for every
  pet number. The existing zAPI is used; no DLL update is needed. Without world
  coordinates, a visible pet plate supplies a level left/right fallback.
  If neither is available, retain the last direction
  (right for a new stream or pet-less dummy preview). MSBT's pet fonts, colors,
  filters and event formatting still apply. zNameplates' **Dummy Damage!** also
  pulses the legacy target-side pet lane while splitting is enabled, even
  without a real pet. Real pet combat uses the selected anchor.
- Disable separate `MikScrollingBattleText` and `MikScrollingBattleTextOptions`
  addons while using zDNumbers; they are already included.

## Settings windows

`/zdn` uses the same compact, opaque dark surfaces and navigation rail as
zNameplates. Placement, Appearance, Pet damage and MSBT pages retain all previous
controls. Numeric settings have sliders plus precise entry, alignment has a
dropdown, and resetting placement requires confirmation. Existing saved values
and MSBT profiles are not migrated or overwritten by the UI refresh.

The embedded `/msbt` editor retains its six original pages, event/message editors,
font previews, profile operations, colour pickers, triggers, suppressions and
five-area positioning/preview tool. Its original callbacks and data paths remain;
only presentation, navigation and modal layering change. Missing local trigger
selections recover from the saved trigger instead of throwing or losing events.

The shared spacing, surfaces and selected states follow
[Material layout guidance](https://m3.material.io/components/lists/overview).
No external MSBT addon or zNameplates dependency is introduced.

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

The embedded MSBT parser reuses its capture-order layouts and avoids iterator
allocation for ordinary first-match searches. Burst queues compact once after
merging, preserving late arrivals and the existing target, pet, crit and result
rules. Empty merge ticks skip processing. Hidden/suppressed event records return
to the recycler, whose weak overflow handles gaps left by collection.
Overflow uses weak table identities rather than a lifetime sequence of numeric
slots. Clearing event records no longer polls global Lua memory twice per
event. `/msbt stats` retains pool counters and labels table reuse as an estimate;
`/msbt stats memory` toggles detailed memory-delta sampling when explicitly
needed. That diagnostic sampling starts off after reload.

Formatted screen text reuses its name-resolution result for class coloring,
halving roster searches for those messages. Preformatted notifications still
resolve their names, and results are never cached across separate events.

Scroll areas share one clock sample per animation frame. Sticky holds and
unchanged font/icon geometry, opacity and anchor positions skip redundant UI
writes; motion, fade curves, crit jitter, display timing and the vanilla font
size workaround are preserved. Item-icon searches probe actual bag capacity,
with the original fallback when slot counts are unavailable. Identical health
or mana alert sounds play once per resource update while retaining all text
notifications.

Screen-text parents are warmed during initialization and stay shown with
transparent text/icons while idle. The existing MSBT event frame drives only
active scroll areas; idle areas have no separate animation callback. This
avoids hiding and reactivating a native display for each isolated message, the
path measured at 459 ms in the October 14 Falling capture. Explicitly hidden
parents recover on new text, and hiding UIParent still hides the combat text.

`tests/test_msbt_optimization.py` compares parsing, merging and 18 animation
scenarios against a bundled pre-optimization baseline. Its work-count and
allocation comparisons are controlled Lua checks, not in-game FPS estimates.
OctoPerf also has optional internal MSBT timings to
separate warning audio, fonts/icons, merging and outgoing routing when a hitch
is recorded. Those spans remain passive while recording is off.

Text/icon slots are allocated only when a number needs them and reused later;
idle nameplates do not run animation tracking. Numbers on the same unit share
one base projection per rendered frame, while each elevated point still gets
its own live camera projection. Frozen/dead anchors use remembered world points
without repeatedly resolving an expired unit.
Split pet streams reuse those projections: a single horizontal probe supplies
the perspective translation. Each pet number finds its nearest free gap along
that direction using reusable, bounded collision intervals for individual
numbers. There are no scene scans, per-number pet lookups or repeated native
projections to fit the ring. Zipper ordering also uses reused slot arrays.
Those orbit/zipper calculations are used only by the optional legacy anchor;
the default over-pet stream shares one base projection across its active numbers.

Rounded-icon geometry, font height, perspective setup, alignment and opacity
are changed only when needed. Motion and fades still update every rendered
frame. Modern nameplate enumeration avoids duplicate attachments; legacy/mixed
hosts retain periodic recovery and immediate recovery on an unmatched damage
batch. MSBT formatting, merging, depth and profiles remain unchanged. The default
combined stream retains ten slots; split mode allows ten per source, allocated
only when used. Player/pet GUID hints are source-matched so equal simultaneous
hits cannot steal each other's target.

The factory-profile regression test checks the immutable captured preset rather
than comparing against a player's subsequently edited live saves. To explicitly
audit those saves against the original capture, run the test with
`ZDN_VERIFY_LIVE_PRESET=1`; a mismatch does not mean saves were overwritten.
