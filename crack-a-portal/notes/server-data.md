# server-data helper notes

## Files
- `src/ServerScriptService/Server/init.server.luau` (rebuilt): Net.create(), collision groups Players/Monsters/Fx, require Systems in PLAN ORDER (pcall, warn + skip), init() all (pcall; a system whose init fails is not started), start() all (task.spawn + pcall).
- `src/ServerScriptService/Server/Systems/Save.luau` (new): DataStore `CrackAPortal_Players_v1`, key `p_<UserId>`, record `{ data, lock = { job, at }, savedAt }`; session lock via UpdateAsync (stale 150 s), retries 1/2/4/8 s, lock retries 5 x 3 s, modes datastore/memory/temp, future-version guard.
- `src/ServerScriptService/Server/Systems/PlayerData.luau` (rebuilt + extended): session, load/kick, Config clean-up, custom HP, coins/keys/items/equip API, settings remote, coalesced Profile snapshot, autosave, onLeaving + final save, BindToClose, Ready remote + onReady hooks.
- `src/ServerScriptService/Server/Systems/Notify.luau` (new): toast, announce, fx, fxAll, fxNear.
- `src/ServerScriptService/Server/Systems/Appearance.luau` (new): weapon/armour welded on the character, swing trail, character attributes, title BillboardGui.
- `src/ServerStorage/Tests/PlayerData.spec.luau` (new): 2 tests for `PlayerData.cleanProfile`.

## API
Save:
- `mode(): "datastore" | "memory" | "temp"`
- `load(player): (boolean, Profile?, string?)` reasons `"locked" | "future" | "left" | "error"`
- `save(player, profile, release): (boolean, string?)` reasons `"lost"` (another server holds the lock), `"future"`, `"error"`, `"notLoaded"`, `"unknown"`
- `saveNow(player): boolean` (false if not loaded or the write failed; true for temp/Studio profiles)
- extras: `markLoaded(player)`, `markTemp(player, profile)`, `isTemp(player): boolean`, `forget(player)` (PlayerData uses them; nobody else needs to)

PlayerData (all PLAN functions):
- `get(player): Session?` (only loaded sessions), `waitLoaded(player, timeout?): Session?`
- `onLoaded(fn)`, `onLeaving(fn)`, `onReady(fn)`, `markDirty(player)`, `snapshot(player)`, `recalc(player)`
- `addCoins(player, n, source?)`, `spendCoins(player, n): boolean`, `coinMult(player): number`
- `addKey(player, kind, rarity, n?, source?)` (fires `KeyGained`), `takeKey(player, kind, rarity): boolean`, `keyCount(player, kind, rarity): number`
- `addItem(player, item): Item?` (fires `ItemGained`), `removeItem(player, id): Item?`, `findItem(player, id): Item?`
- `equip(player, id): boolean`, `equipIfEmpty(player)`
- `setHp(player, hp)`, `heal(player, n)`, `fullHeal(player)`, `bestKind(player): string`, `unlocked(player): { string }`
- `setSetting(player, name, value)` (also the "Setting" remote handler)
- extras: `PlayerData.equipChanged: Signal<Player>`, `PlayerData.cleanProfile(profile): Profile` (pure)
- `export type Session` = PLAN section 7 fields exactly.

Notify: `fx(player, ev)`, `fxAll(ev)`, `fxNear(pos, radius, ev)` (FxU), `toast(player, text, style?)`, `announce(text, style?)`.

Appearance: `refresh(player)`, `setTitle(player, title?)`.

## Deviations from PLAN.md
- `Save.save` returns a second value (reason); `Save` has 4 extra helpers (above).
- `PlayerData.get` returns nil until the profile is loaded (so nothing can act on an unloaded profile).
- `addItem` past the cap: the item still gets an id, is sold for `Logic.sellValue`, a toast is sent, `ItemGained` still fires (it was found: Index and quests count it) and `nil` is returned.
- `addKey` / `addItem` send no Fx (KeyGet/GearDrop pop-ups are the caller's job, e.g. MapMonsters/Openings).
- Setting remote: validated first, then rate-limited; a rate-limited value is kept (newest per name) and applied 0.5 s later, so the end of a slider drag is never lost. No snapshot is sent for settings (attributes carry them).
- A future-version profile is never claimed: load returns `"future"` (live: kick with "rejoin for the newest server"; Studio: temp profile). Save's transform also refuses to write over a stored version > VERSION and refuses when another JobId holds the lock.
- Studio: a failed load (any reason) continues on a temporary profile that never saves (with a warning); live servers kick.
- An autosave that finds another server's lock (`"lost"`) kicks the player on a live server.
- StudioTempData is honoured only in Studio (a live server can never be switched to non-saving profiles).

## Needs from others
- Appearance <-> PlayerData: PlayerData fires `PlayerData.equipChanged` (equip, equipIfEmpty, removeItem of an equipped item); Appearance listens. Nobody needs to call `Appearance.refresh` after equipping (calling it is harmless).
- Index: call `Appearance.setTitle(player, Config.Index.title)`; it also writes `profile.title` and marks dirty.
- Purchases: set `session.passes.DoubleCoins/LuckierKeys` and `session.noPaidRandom` (defaults false/false/**true**: Luckier Keys stays hidden until the PolicyService check says otherwise), then `PlayerData.markDirty(player)`. ProcessReceipt: `Receipts.apply(...)` then `Save.saveNow(player)`.
- Daily: fill `profile.quests` for today in an `onLoaded` hook (PlayerData only computes `quests.resetAt` = next UTC day for the snapshot).
- Combat: owns falls and regen; reads/writes HP only via `setHp/heal/fullHeal`. PlayerData does `fullHeal` on CharacterAdded unless the player attribute `InOpening` or `InRift` is true.
- Monsters: put rig parts in collision group "Monsters" (groups are registered by init.server; PlayerData puts character parts in "Players").
- Client Combat: weapon model `character.GearWeapon` (TwinBlades: `GearWeapon.Right` / `.Left`), trails named `SwingTrail` (Enabled = false; enable during swings). Armour model `character.GearArmor`. Both carry attribute `ItemKey`.
- Toast styles used: "info", "warn" ("good", "rare", "legendary" suggested for others). Effects should accept any string.

## Decisions
- Autosave every 60 s; first autosave 60 + (UserId % 30) s after loading (so the lock is refreshed well within 150 s).
- Snapshot gap 0.2 s (task.defer when free, task.delay otherwise).
- BindToClose waits up to 25 s, except in Studio memory/temp mode (no wait). Studio datastore mode waits.
- Lock job id = `game.JobId`, or "studio" when empty.
- Kick texts: failed load, locked ("still saving on another server"), future version, lost lock (plain words, ask to rejoin).
- Coins cap 1e15, keys 9999 per stack (same as SaveSchema). Volumes rounded to 0.01.
- HP attributes are written rounded up (`math.ceil`). Better armour adds the extra max health at once.
- Humanoid: `BreakJointsOnDeath = false`, health topped up on every HealthChanged (> 0); game HP lives only in the session.
- Trail: colour = kind glow -> towards white by 8% per rarity step; LightEmission 0.25 + 0.15 x order; head transparency 0.6 - 0.08 x order; lifetime 0.16 + 0.02 x order.
- Weapons weld with a `Weld` (C0 = hand grip attachment, C1 = Grip); loose parts of hand-made models are welded to the grip part. Missing grip attachment on a custom rig: one is made at the bottom of the hand.
- Armour: every attachment in the model whose name matches an attachment on a body part (direct child, never an accessory) welds its part on its own.
- Title tag: BillboardGui on the Head, 6 x 0.7 studs, 2.4 studs up, MaxDistance 60, Oswald Bold, GoldBright with Ink stroke.
- Collision groups (init.server): Players-Monsters, Players-Fx, Monsters-Fx, Fx-Fx do not collide.

## Studio checks
- Saving with API access on: join, change coins, leave, rejoin -> kept. Two Studio test servers can't hold the same key (both use job "studio": locks only protect real servers).
- API access off: one `[Save]` warning, game runs on memory saves.
- `workspace:SetAttribute("StudioTempData", true)` before Play: fresh profile, nothing saved.
- Weapon grip orientation in the hand for Sword, Axe, Twin Blades (R15 and R6), trail endpoints, armour pieces on torso and shoulders.
- Title tag size and height over the head, fades at 60 studs.
- Reset character outside an opening -> full HP; inside an opening HP is kept.
- Humanoid never dies from monster hits (only the custom HP bar moves).

## Assets/anim/sound hooks
- Gear models (via `Assets.gear`): weapons need an Attachment `Grip` (+ `TrailTop`, `TrailBottom` for the trail); Twin Blades sub-models `Right` and `Left`; armour pieces carry attachments named after R15 body attachments (`BodyFrontAttachment`, `LeftShoulderAttachment`, `RightShoulderAttachment`, ...). Scripts inside gear models are removed.
- No sounds or animations in these modules.
