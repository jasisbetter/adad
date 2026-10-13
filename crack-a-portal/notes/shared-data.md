# shared-data helper notes

## Files
- `src/ReplicatedStorage/Shared/Config.luau` (new): all game data per PLAN.md section 3: colours, map, 4 key kinds, 3 key rarities, 5 gear rarities (statMult computed), gear odds, gear rules, Sword/Axe/TwinBlades/Armor with 3-step combos, weapon powers, combat, waves, 30 attacks, 16 monsters, 4 ring areas with looks, map key odds (with Luckier Keys tables), portal, inventory, daily, 10 quests, index, leaderboards, Rift, passes/products (ids 0), Recover, tutorial, anims (ids 0), music rows (ids 0), Studio attribute names, lookup tables and load-time asserts.
- `src/ReplicatedStorage/Shared/Types.luau` (new): PLAN.md section 6 types plus Config row types (KeyKind, Rarity, KeyRarity, ComboStep, GearType, PowerDef, AttackDef, MonsterDef, Band, AreaLook, Area, Quest, MusicTrack) and Logic results (WaveSpec, OddsPercent, IndexReward).
- `src/ReplicatedStorage/Shared/Logic.luau` (grey test, extended): every grey-test function kept; `rollChest` gains `opts` (first / boss / big chest rules); all PLAN.md section 4 functions added, plus `musicTier`, `areaAtRadius`, `areaAt`.
- `src/ReplicatedStorage/Shared/Net.luau` (grey test, extended): all PLAN.md section 5 remotes, `Net.Unreliable = { "FxU" }` (created as UnreliableRemoteEvent), `Net.Limits`, `Net.getU`.
- `src/ServerStorage/Tests/Config.spec.luau`, `Logic.spec.luau`, `Net.spec.luau` (new): 30 tests (odds, random half, kept coins, merge, sell, upgrade, portal, kinds, statMult rule, waves, bosses, chests, map keys, quests, index, areas, limits).

## API
- Config: every field in PLAN.md section 3, plus `Config.HubLook: AreaLook` (plots/courtyard lighting), `Config.Combat.fistDamage = 5`, `Config.Combat.comboGrace = 0.12`, `Config.Combat.staggerImmune = 1.5`, `Config.Music.tierEvery = 5`, `Config.Music.Tutorial`, `Config.Colors.*` (Gold, GoldBright, Ink, Panel, Stone, StoneDark, White, Muted, Ash, Ember, Frost, Void, Danger, Warn, Good, Crit, Burn, Slow, Double, Stagger).
- Lookups: `Config.RarityById[id]`, `Config.AreaById[id]`, `Config.MonsterIds` (sorted), `Config.BossByKind[kind]`.
- Logic (kept): `weightedPick(list, rng)`, `boostedOdds(base, steps, stepSize)`, `rarityOrder(id)`, `rollRarity(odds, rng, min?)`, `itemStat(item)`, `itemName(item)`, `itemSlot(item)`, `formatStat(n)`, `short(n)`, `waveSpec(wave, keyRarity, kind)`, `monsterMix(wave, kind)`, `keptCoins(coins)`, `randomHalf(count, rng): {[number]: boolean}`, `rollGearType(kind, rng)`, `rollMonsterGear(keyRarity, kind, rng, bonus?)`, `newItem(kind, type, rarity)`, `sortBest(items)`.
- Logic (new): `chestKind(wave, boss)`, `rollChest(wave, keyRarity, kind, rng, opts?: { boss: boolean?, first: boolean? })`, `statAt(item, level)`, `maxLevel(rarity)`, `upgradeCost(item): number?`, `sellValue(item)`, `nextRarity(rarity): string?`, `itemKey(item)`, `mergeGroup(items, pick, equipped): {string}?` (returns `{ pick.id, lowest, next lowest }`), `power(item): {[string]: any}?` (`kind` + the byRarity fields), `maxHp(armor?)`, `weaponDamage(weapon?)`, `portalCost(level): number?`, `portalBonus(level)`, `portalTier(level)`, `unlockedKinds(level)`, `bestKind(level)`, `keyPrice(kind, rarity): number?`, `mapKeyOdds(band, area, lucky)`, `rollMapKey(band, area, lucky, rng): string?`, `oddsPercent(odds): { {id, percent} }`, `isBossWave(wave, keyRarity, rng)`, `killCoins(def, spec, portalLevel, coinMult)`, `lossValue(coins, items, kind)`, `recoverTier(value)`, `riftHpMult(players)`, `musicTier(wave)`, `areaAtRadius(r): (Area?, "inner"|"outer"?)`, `areaAt(pos: Vector3): (Area?, band?)`, `dayNumber(t)`, `questsForDay(day, userId)`, `questReward(slot, bestKind): { coins, key? }`, `indexRewards(index): { IndexReward }`.
- Types exported by Logic: `Logic.Item`, `Logic.WaveSpec` (aliases of Types).
- Net: `Net.ToServer`, `Net.ToClient`, `Net.Unreliable`, `Net.Limits[name]` (`.rate`/`.burst`, also `[1]`/`[2]`), `Net.create()`, `Net.get(name): RemoteEvent`, `Net.getU(name): UnreliableRemoteEvent`, `Net.find(name): RemoteEvent?`.

## Deviations from PLAN.md
- `Net.Limits[name]` rows carry both `rate`/`burst` fields and `[1]`/`[2]`, so either reading of PLAN's `{ rate, burst }` works. `Debug` has a row too.
- `area.music` = `"AreaAsh"` etc. keys into `Config.Music.Areas` (PLAN's value names; the audio digest's keying by area id is not used).
- `Config.Monsters[id].sounds` also has `roar` (bosses only, `"<Id>Roar"`).
- `Config.Attacks` rows default `warn = true` unless set false (small melee attacks: Imp scratch, bites, claws, sword swings) and `heavy = false`.
- Melee attacks use `angle` (degrees) for their arc and `range` for reach. Cones use `length` (reach) and `angle`.
- Combo step timing: the hit lands at the end of `windup`; `contact` is the strike, then `recover`. Step time = windup + contact + recover.
- `Config.Quests.list` rows have `arg` (which Bus event argument after the player is the value for "max"/"atLeast") and `scaled` (goal x best kind coinMult; used by Pot5000).
- `mergeGroup` never uses an equipped item as one of the two extra items (the pick itself may be equipped).
- `stylua` here is built without Luau support (it only parses Lua 5.1), so it can't format these files. Lines are kept under 120 columns by hand; run `stylua src` once with a Luau-enabled build.

## Needs from others
- None. Every caller should use the APIs above.
- Systems that pick a power colour should use `Config.Powers[kind].color` / `Config.Colors.Burn|Slow|Double|Crit`.

## Decisions
- Rarity statMult (computed): Common 1, Rare 1.2625, Epic 2.133, Legendary 4.822, Mythic 14.59.
- Gear base stats: all weapons 10 damage, Armor 40 max health; fists 5.
- Combos (windup/contact/recover, damage x): Sword 0.12/0.08/0.25 x1.0, x1.0, then 0.18/0.10/0.40 x1.6 finisher with a 9-stud 360-degree radius (~2.28x DPS). Axe 0.30/0.12/0.45 x1.8 heavy twice, then 0.42/0.13/0.60 x3.2 with an 11.5-stud radius, knockback 12/12/26 (~2.35x DPS). Twin Blades 0.07/0.06/0.17 x0.65 twice, then 0.10/0.08/0.30 x0.6 hitting twice (~2.31x DPS). Combo reset 0.9 / 1.1 / 0.7 s.
- Powers: stagger chance 10/14/19/25% (0.4-0.8 s); burn 15/20/26/34% of hit per s for 3-4 s; slow 25/30/36/45% for 1.5-3 s; double 10/15/21/28%.
- Monsters (Ash-scale hp/dmg/speed/coins): Imp 30/3/18/5, Hound 55/6/16/8, Brute 140/10/9/15, Golem 900/12/8/120; Skeleton 45/4/15/6, Crawler 60/5/14/8, Bat 40/6/20/9, Molten Knight 1000/13/10/130; Wolf 40/4/19/6, Wraith 50/6/12/9, Troll 150/10/8/15, Frostmaw 1100/13/9/140; Shade 40/5/17/7, Rift Eye 55/6/10/9, Void Knight 130/9/11/15, Hollow King 1200/14/9/150. Types 2 and 3 of each kind appear from waves 2 and 3.
- Attacks: 30 rows. Small melee: no warning, wind-up 0.45-0.55 s. Warned attacks 0.5-1.0 s; boss specials 0.9-2.2 s (Hollow King arena slam 2.2 s, 3 safe spots of radius 7 in a 40-stud arena).
- Areas: Ash 178-255-330, Ember 350-425-500, Frost 520-595-670, Void 690-765-840 (inner-split-outer), 18 map monsters each (9 inner, 9 outer), gates of 4 per ring, 20-stud gaps between rings for gates.
- Quests (10): Wave10, Pot5000 (scaled), Beat100, Open3, Boss1, Merge1, Rift1, Clear15, Keys3, Gear5.
- Tutorial step ids: Portal, Key, Attack, Dodge, Chest, Choice, Gear, Explore.
- `questsForDay` uses its own integer generator (MINSTD), not `Random`, so it is the same on every machine.
- Index: area reward needs the 3 monsters and the boss; a rarity row needs every kind x gear type of that rarity (16 items); "All" needs every area and every row.

## Studio checks
- Run the specs in Studio (`require(game.ServerStorage.Tests.Run)()`): Config asserts run at load, so a bad row shows up at once.
- Strict type check of Config/Logic/Types with Roblox definitions (luau-lsp or Studio script analysis).
- Feel-check the three weapon combos and the attack wind-ups once the placeholder swings and monsters are in.

## Assets/anim/sound hooks
- Monster models: `ServerStorage.Assets.Monsters.<MonsterId>` (`Config.Monsters[id].model` = id). Grey template size and colour: `size`, `color`, `deathColor`.
- Monster anims: `Config.Monsters[id].anims` = `{ idle, move, hit, death, emerge, roar, attacks = { [attackId] = 0 } }`, all 0. Attack rows carry an `anim` name (Scratch, Bite, Charge, Slam, Throw, Roar, Swing, Spit, Swoop, Sweep, Eruption, Cast, Stomp, Breath, Icicles, TailSweep, Claw, Teleport, Beam, Slash, Cleave, Strike, Summon, Orbs, ArenaSlam).
- Player anims: `Config.Anims.player` (dodge, hit, fall, victory, keyUse) and `Config.Anims.weapons[type] = { 0, 0, 0 }`.
- Sfx row names the Config expects: `<MonsterId>Growl|Attack|Death` for all 16, `<BossId>Roar` for the 4 bosses; weapon rows `SwordSwing/SwordHit/SwordFinisher`, `AxeSwing/AxeHit/AxeFinisher`, `TwinSwing/TwinHit/TwinFinisher`; attack sounds `BossCharge`, `Slam`, `BoulderThrow`, `ImpSummon`, `FirePool`, `EmberSwoop`, `FireSweep`, `LavaErupt`, `IceShard`, `FrostBreath`, `IcicleFall`, `TailSweep`, `Teleport`, `BeamFire`, `ShadeSummon`, `VoidOrb`, `ArenaSlam`, plus `<MonsterId>Attack` / `HollowKingAttack` / `VoidKnightAttack`.
- Music: `Config.Music.Hub`, `.Tutorial`, `.Areas.AreaAsh|AreaEmber|AreaFrost|AreaVoid`, `.Combat[1..4]`, `.Boss[kind]`, `.Rift`, `.RiftBoss`, all id 0.
- Gear icons: `Config.GearTypes[type].icon = 0`.
