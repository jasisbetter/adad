# shared-lib notes

## Files
- `src/ReplicatedStorage/Shared/Geometry.luau`: new. Pure flat shape tests (circle, line, cone, arena with safe spots, segments), safe-spot picker, ring points, random point in a circle.
- `src/ReplicatedStorage/Shared/Signal.luau`: new. Tiny typed signal (Connect/Once/Fire/Wait/DisconnectAll); handlers run in order, each in `task.spawn` + `pcall`.
- `src/ReplicatedStorage/Shared/Assets.luau`: new. Finds hand-made models in `ReplicatedStorage.Assets` (and `ServerStorage.Assets` on the server), returns a clone or nil, never yields or errors; validates monsters and portal tiers.
- `src/ReplicatedStorage/Shared/Templates.luau`: new. Grey fallback models by code: a part-based rig for each of the 16 monsters, gear (Sword, Axe, TwinBlades, Armor by rarity), portal tiers 1-5, chests (normal/big/boss), keys.
- `src/ReplicatedStorage/Shared/AnimHooks.luau`: new. Loads/plays Config animation ids through an Animator (id 0 -> nil), caches Animation objects and tracks, waits for Length > 0 and reloads broken tracks.
- `src/ServerScriptService/Server/Lib/Bus.luau`: new. Cross-system events with the PLAN section 8 name list; handlers in `task.spawn` + `pcall`.
- `src/ServerScriptService/Server/Lib/SaveSchema.luau`: new. Profile v1 default, migrate (garbage -> default, future versions flagged, v0 grey-test migration), sanitize (fills, clamps, drops bad data).
- `src/ServerScriptService/Server/Lib/Receipts.luau`: new. Receipt ids in the profile (newest 100), idempotent `apply` for ProcessReceipt.
- `src/ServerScriptService/Server/Lib/Status.luau`: new. Timed stagger/burn/slow on monsters and players, attributes Burn/Slow/Stagger, 4 Hz burn ticks.
- `src/ServerScriptService/Server/Systems/RateLimit.luau`: rebuilt from NOTES.md. Token bucket per player and key.
- `src/ServerStorage/Tests/Geometry.spec.luau`, `SaveSchema.spec.luau`, `Receipts.spec.luau`, `Signal.spec.luau`: new specs (28 tests, all passing offline).

## API
Geometry (all pure, Y ignored):
- `flat(v: Vector3): Vector3`, `flatDistance(a, b): number`, `flatUnit(v): Vector3?`
- `inCircle(center, radius, p): boolean`
- `inLine(origin, dir, length, width, p): boolean` (dir flattened; rectangle ahead of origin)
- `inCone(origin, dir, range, angleDegrees, p): boolean` (angleDegrees = FULL opening; >= 360 = all around)
- `inArena(center, radius, p, safeSpots: { Vector3 }, safeRadius): boolean` (true = gets hit)
- `segmentT(a, b, p): number`, `pointOnSegment(a, b, p): Vector3`, `distanceToSegment(a, b, p): number`
- `safeSpots(center, radius, count, safeRadius, rng: Random): { Vector3 }` (whole safe circle inside the arena, spread by angle)
- `ringPoints(center, radius, n, offset: number?): { Vector3 }`, `randomInCircle(center, radius, rng): Vector3`

Signal:
- `Signal.new<T...>(): Signal<T...>`; `:Connect(fn): Connection`, `:Once(fn): Connection`, `:Fire(...)`, `:Wait(): T...`, `:DisconnectAll()`
- `Connection = { Connected: boolean, Disconnect: (self) -> () }`; types `Signal.Signal<T...>`, `Signal.Connection`

Assets (clones; nil when missing or invalid, one warning per bad asset):
- `find(category, name, sub: string?): Instance?`, `findSource(category, name, sub?): Instance?` (original, not cloned)
- `monster(id): Model?` (needs PrimaryPart named "Root" and an Animator), `gear(kind, gearType, rarity: string?): Model?` (tries `<GearType>_<Rarity>` first), `portalTier(n): Model?` (needs a "Surface" part), `chest(chestKind): Model?` ("normal"/"Normal" etc.), `key(kind): Model?`

Templates:
- `monster(def): Model` (def: any Config.Monsters row; reads id, kind, size, color, flying, behaviour, boss, model)
- `joints(model): { [string]: Motor6D }` (use this, not `FindFirstChild(name, true)`, which can return the part of the same name)
- `gear(kind, gearType, rarity: string?): Model`, `portal(tier): Model`, `chest(chestKind): Model`, `key(kind, rarity: string?): Model`, `hasRig(id): boolean`

AnimHooks:
- `load(animator, id, opts: { priority: Enum.AnimationPriority?, looped: boolean? }?): AnimationTrack?`
- `ready(track?): boolean` (Length > 0), `play(track, fade?, weight?, speed?)`, `onMarker(track, name, fn): RBXScriptConnection`
- `stopAll(animator, fade?)`, `clear(animator)` (also runs automatically on Animator.Destroying), `animatorOf(model): Animator?`

Bus (server): `Bus.Events` (name set), `Bus.on(name, fn): () -> ()`, `Bus.fire(name, ...)`

SaveSchema (server, pure):
- `VERSION = 1`, `default(): Profile`, `migrate(data: any): (Profile, boolean)` (second value `future`), `sanitize(data: any): Profile`, `MIGRATIONS: { [number]: (table) -> table }`
- exported types `Profile`, `Item`, `Settings`, `QuestSlot`, `Loss`

Receipts (server, pure): `MAX = 100`, `has(profile, id): boolean`, `record(profile, id, now)`, `trim(receipts, max?)`, `apply(profile, id, now, grant: () -> boolean): "granted" | "already" | "failed"`

Status (server):
- `apply(target, kind: "stagger" | "burn" | "slow", params: { duration: number, amount: number?, dps: number?, source: any? })`
- `speedMult(target): number` (0 while staggered), `isStaggered(target): boolean`, `has(target, kind): boolean`
- `tick(now: number?)`, `clear(target)`, `now(): number` (workspace:GetServerTimeNow())
- `setBurnHandler(fn(target, amount, source))`, `setStaggerHandler(fn(target, duration))`

RateLimit: `allow(player, key, perSecond, burst): boolean`, `clear(player)`, `init()`, `start()` (PlayerRemoving -> clear)

## Deviations from PLAN.md
- `SaveSchema.migrate` returns a second value `future: boolean`. A profile saved by a newer game version (version > 1) comes back untouched with `future = true`; **Save must refuse to overwrite it** (kick or play without saving).
- `Status.tick(now?)` takes the current server time (computed task) instead of `dt` (PLAN). With no argument it reads `Status.now()`. Burn catches up missed 0.25 s ticks (max 8 at once), so damage does not depend on the owner's tick rate.
- `Receipts.apply` added (pure ProcessReceipt helper), plus `Receipts.trim`.
- Extras not in PLAN: `Geometry.flatDistance/flatUnit/segmentT/distanceToSegment/randomInCircle`, `Assets.findSource`, `Templates.joints/hasRig`, `AnimHooks.ready/animatorOf`, `Status.has/now/setStaggerHandler`.
- Motor6D hierarchy: Body -> Root, other parts -> Body or their own limb (Fist -> Arm, Weapon -> ArmR, Horn -> Head), not every part straight to Root. Animations pose by part name, so this is the hierarchy real models should copy.

## Needs from others
- Save: honour `SaveSchema.migrate`'s second return (`future`) and never save over it.
- PlayerData: SaveSchema only checks item shape (it has no Config). On load, drop items whose kind/type/rarity are not in Config, clamp item levels to `Logic.maxLevel(rarity)` and clamp `portalLevel` to `Config.Portal.maxLevel` (SaveSchema uses generous caps: level/portal 1..999).
- Monsters: call `Status.setBurnHandler(fn)` and `Status.setStaggerHandler(fn)` once (Combat may share the burn handler for players: dispatch on `typeof(target) == "Instance"`), call `Status.tick()` from the 10 Hz AI loop, `Status.clear(mon)` on despawn and `Status.clear(player)` on leave. Mon tables are recognised by `.model` and `.alive`.
- Monsters: set Root `CanQuery`/collision group/network owner and the AlignPosition/AlignOrientation on `RootAttachment` (Templates leave Root non-queryable, unanchored).
- MonsterFx / Combat: find joints with `Templates.joints(model)`; real Humanoid characters still need `Motor6D or AnimationConstraint`.
- Purchases: `Receipts.apply(profile, receiptId, os.time(), grant)`, then save; only return PurchaseGranted after "granted"/"already" and a successful save.
- Plots: `Templates.portal(tier)` has pivot at the bottom centre (front -Z), PrimaryPart = `Surface` (attribute `State` = "idle", like Build's); place it with `PivotTo`. Runes are Neon parts named `Rune`/`Keystone`/`Crown` (tint them by kind if wanted).
- Appearance: weld weapons by `Grip`; TwinBlades = sub-models `Right` and `Left` (each with Grip/TrailTop/TrailBottom); Armor = separate parts `Chest`, `ShoulderL`, `ShoulderR`, each with an attachment named like the R15 body attachment it goes on (`BodyFrontAttachment`, `LeftShoulderAttachment`, `RightShoulderAttachment`); each piece must be welded on its own (trims are already welded to their piece).

## Decisions
- Cone angle = full opening in degrees.
- Safe spots: even angles with a random turn and +-25% of a step of jitter, distance between max(1.2 x safeRadius, 0.35 x radius) and radius - safeRadius - 1.
- Status: burn ticks every 0.25 s; stacking keeps the higher dps and the later expiry; slow keeps the bigger cut; minimum speed multiplier 0.1 while slowed, 0 while staggered. Times are `workspace:GetServerTimeNow()`. The burn handler runs via `task.defer` (after the tick loop) inside `pcall`.
- Save caps: coins 1e15, counts 1e12, keys 9999 per stack, levels 1..999, quests list 10, items kept 150 (warning on drop), receipts newest 100 (ties by id), strings 1..64 chars (receipt ids up to 128).
- v0 (grey-test) migration keeps coins/keys/items/equipped/nextId and marks the tutorial done (they have played already); a v0 table without items gets the starter kit and the tutorial.
- Equipped ids that point at missing items are dropped; `nextId` is raised past the highest `iN` id.
- Signal/Bus: handler errors are warned (`[Signal]`, `[Bus] <event>`), never thrown. Bus warns once per unknown event name and ignores it.
- AnimHooks: waits 3 s for Length > 0, reloads up to 2 times, then marks the id broken for the session (placeholder stays). Default fade 0.1.
- Templates: monster pivot = bottom centre via `Root.PivotOffset`; Root = invisible box of `def.size`; all visible parts SmoothPlastic (Slate for Stone Brute / Ashen Golem) with Neon accents in the kind's glow; bosses add a PointLight. Part counts: 10-17 for monsters, 20-23 for bosses.
- Gear template sizes: Sword blade 3 studs, Twin Blades 2 studs each, Axe 3.2-stud handle; Legendary x1.08 and Mythic x1.15 bigger; Rare+ Neon trim, Epic+ rarity-coloured gem, Legendary+ PointLight, Mythic ParticleEmitter "Sparkles".
- Portal tier scale 1 + 0.15 per tier; 2 runes per pillar per tier; tier 2 keystone, tier 3 peaked arch, tier 4 side spires, tier 5 crown; PointLight brightness 0.4 + 0.3 x tier, range 8 + 4 x tier.
- Chests: normal 3x2x2 wood/iron, big 4x2.6x2.6 gold bands + Neon seam, boss 5x3.2x3.2 dark with gold spikes, light and sparkles.

## Studio checks
- Spawn each monster template (`Templates.monster(Config.Monsters.X)`) and look from every side: silhouettes recognisable, eyes facing -Z, nothing floating.
- Ball parts in Roblox are forced uniform: check the Void Shade wisps, bat body and crawler abdomen still read well.
- Armor attachments on an R15 character: chest plate and pauldrons sit on the torso and shoulders (offsets are estimates).
- Weapon grip orientation in the hand (Grip: +Y along the blade, -Z = edge forward); trails between TrailTop/TrailBottom.
- Chest lid hinge (Motor6D "Lid" Transform about X) opens backwards.
- Portal tiers 1-5 next to each other: growth reads clearly; tier 1 matches Build's arch size.
- AnimHooks with a real id: track loads, `Hit` marker fires, a bad id falls back to the placeholder after ~9 s with one warning.

## Assets/anim/sound hooks
- Monster models: `ServerStorage.Assets.Monsters.<MonsterId>` (or ReplicatedStorage.Assets). Must have PrimaryPart `Root` (bottom-centre pivot, front -Z) and an `AnimationController > Animator` (or Humanoid > Animator), else the grey template is used. Same part and Motor6D names as the template (Body, Head, ArmL/ArmR, LegL/LegR or LegFL/LegFR/LegBL/LegBR, WingL/WingR, Tail, Weapon, Shield...), attachments `RootAttachment`, `Eye`, `Glow`, `Top`, `Weapon` (if armed), `Shield` (Void Knight).
- Gear: `ReplicatedStorage.Assets.Gear.<Kind>.<GearType>` or `<GearType>_<Rarity>` for rarity variants. Weapons: `Grip`, `TrailTop`, `TrailBottom`; TwinBlades: `Left` and `Right` sub-models; Armor: `Chest`, `ShoulderL`, `ShoulderR` with the R15 attachment names above.
- Portal: `ReplicatedStorage.Assets.Portal.Tier1..Tier5`, must contain a part named exactly `Surface`.
- Chests: `ReplicatedStorage.Assets.Chests.Normal|Big|Boss` (template: Base anchored, Motor6D `Lid`, attachment `Burst`).
- Keys: `ReplicatedStorage.Assets.Keys.<Kind>` (template: Shaft anchored, `Gem`, attachment `Glow`).
- Animations: any Config id through `AnimHooks.load(animator, id, opts)`; id 0 = placeholder. Marker names are read by callers (`Hit`).
- No sounds in these modules.
