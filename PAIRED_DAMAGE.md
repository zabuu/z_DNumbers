# zBox pet-source integration (1.0.2)

Use zDNumbers 1.0.2+ and zBox 0.7.1+ on both characters, then reload both UIs.
No new DLL is needed. Pair through zBox normally, with or without a party.

zBox transports account 2's player-outgoing damage metadata to account 1.
zDNumbers/MSBT own all damage text and frames. The controller's pet profile,
filters, fonts, colors, crit sizing, icons, merge rules and animation apply.
Neither remote style tables nor formatted display strings are accepted.

- Pet splitting off: account 2's pet-identified numbers share the target stream.
- Split + Over the pet: numbers anchor over account 2's source GUID. A real pet
  retains its independent stream/record.
- Split + Beside target: account 2 supplies its own world/screen direction,
  independently of the real pet's direction.
- Off-screen/unavailable sources: normal MSBT Pet Outgoing fallback.

The adapter preserves target GUID, amount, crit/glancing/block/parry flags,
spell ID/icon and damage school. Pet DoTs reuse the pet spell-damage style if
the active profile has no pet DoT entry. Separate sources never merge into a
single event. The sender observes unmerged events before its local show filter,
without taking ownership of MSBT's recycled tables. Relayed pet events cannot
feed back into the observer. Healing, incoming damage, notifications and the
second character's own pet are excluded from this player-source adapter.

The public adapter is optional: `PairedDamageVersion=1`,
`SetOutgoingDamageObserver(observer, activePredicate)`,
`SetPairedDamageSource(provider)` and `ShowPairedDamage(data, sourceGUID)`.
The source provider returns only the controller's currently paired agent GUID.
zBox checks sender, realm, key, session, source GUID, bounds and replay IDs
before calling it. Unlinking stops further damage submission; existing source
animations use the normal fallback/expiry behavior.

Validation: `python tests/test_paired_damage.py` exercises actual MSBT adapter,
dispatch and merge functions plus zDNumbers' renderer. Existing pet anchor,
stream/orbit/zipper, animation-sharing and MSBT optimization fixtures also pass.
Live two-client verification remains necessary after updating both addons.
