# Crack a Portal: build plan and code contract

This file is the contract every module is written against. If code and this file disagree, fix one of them and say which in `CHANGES.md`. Read `BRIEF.md` (the spec), `PROMPT.md` (the coding job) and `NOTES.md` (grey test) first.

## 0. Starting point

Only 5 grey-test files reached this session: `Shared/Anim.luau`, `Shared/Sfx.luau`, `Shared/Logic.luau`, `Shared/Net.luau` and `ServerStorage/Build.luau`. The other 19 (Config, the server systems, the client controllers, the two `init` scripts, `default.project.json`) never arrived, so they are **rebuilt from the descriptions in NOTES.md**: same names, same APIs and the same behaviour, then extended. The 5 real files are kept and extended. When Jas's Claude installs `src/`, the whole tree replaces the old one.

Ground rules for every file (from PROMPT.md section 1): `--!strict`, typed, modern APIs only (`task.*`, constraints, `GetAttribute`, `Players:GetPlayers()`), no deprecated calls, no TODO or `...` placeholders, the server decides everything, every remote validated and rate-limited, everything as data in `Config`, pure maths in `Logic`, everything built by code, sound only through `Sfx`/`Music` with ids `0` until Jas picks them, no publishing.

## 1. File map (Rojo, see `default.project.json`)

```
src/ReplicatedStorage/Shared/          -> ReplicatedStorage.Shared (both sides)
  Config.luau      all game data and numbers (section 3)
  Logic.luau       pure maths, no instances (section 4)          [grey test, extended]
  Types.luau       exported types for profile, items, payloads (section 6)
  Net.luau         remote list, limits, create/get (section 5)   [grey test, extended]
  Geometry.luau    pure shape tests: circle, line, cone, arena safe spots
  Signal.luau      tiny typed signal (connect/fire/once/disconnect)
  Assets.luau      find a model by name, or nil (callers fall back to Templates)
  Templates.luau   grey fallback models built by code (monsters, gear, portal tiers, chests, keys)
  AnimHooks.luau   load/play animation ids through an Animator; id 0 -> nil (placeholder runs)
  Anim.luau        UI motion (grey test, roblox-game-ui module)    [grey test]
  Sfx.luau         sound effects, client only (grey test kit)      [grey test, rows added]

src/ServerScriptService/Server/        -> ServerScriptService.Server (Script)
  init.server.luau  boot: require Systems in ORDER, init() all, start() all, each in pcall
  Systems/          one ModuleScript per system (section 7), each { init: () -> (), start: () -> () }
  Lib/              helpers that are not booted: Bus, SaveSchema, Receipts, Attacks, Status

src/ServerStorage/                     -> ServerStorage
  Build.luau        makes the whole map: run once in Edit mode   [grey test, extended]
  Tests/Run.luau    tiny test runner (Studio + offline)
  Tests/*.spec.luau unit tests for pure modules
  Sim/Pacing.luau   pacing simulation built on Logic (used by a spec and tools/pacing.luau)

src/StarterPlayerScripts/Client/       -> StarterPlayer.StarterPlayerScripts.Client (LocalScript)
  init.client.luau  boot: require Controllers in ORDER, init() all, start() all, each in pcall
  Controllers/      one ModuleScript per concern (section 9)
  Controllers/Screens/  one ModuleScript per window, registered by Windows
```

Asset folders (made by hand later in Studio, optional; code falls back to Templates when missing): `ServerStorage.Assets.Monsters.<MonsterId>`, `ReplicatedStorage.Assets.Gear.<Kind>.<GearType>`, `ReplicatedStorage.Assets.Portal.Tier<1-5>`, `ReplicatedStorage.Assets.Chests.<Normal|Big|Boss>`, `ReplicatedStorage.Assets.Keys.<Kind>`. Contract in `ASSETS.md`.

## 2. Boot order

Server `ORDER` (init.server.luau):
```
RateLimit, Save, PlayerData, Notify, Plots, Gates, Appearance, Monsters, Combat,
Openings, MapMonsters, Economy, Daily, Index, Leaderboards, Rift, Purchases, Tutorial, DebugTools
```
`Net.create()` runs first inside init.server before any system's `init`. Each `init` only wires things (no yields); `start` may loop (it is called with `task.spawn` inside `pcall`). A system that fails to load is skipped with one `warn`, the rest run.

Client `ORDER` (init.client.luau):
```
Ui, Store, Effects, Music, Zones, MonsterFx, Combat, Hud, Windows, OpeningUi, Reveal, RiftUi, Tutorial
```
Client sends `Ready` after every controller has started; the server answers with a full `Profile` and `Opening` snapshot.

## 3. Config schema (`Shared/Config.luau`)

All tables keyed by string id also carry `id`. Lists that must be ordered are arrays. Values are starting numbers; `Sim/Pacing.luau` tunes them and `PACING.md` records every change.

```lua
Config.Version = 1                  -- save schema version lives in SaveSchema, not here
Config.GreyTest = false             -- grey-test shortcut OFF (map keys roll real rarities)
Config.Colors = { Gold, Ink, Ash, Ember, Frost, Void, Danger, Good, ... }   -- Build uses Colors.Gold

Config.Map = {
  plotCount = 8, plotRadius = 110, plotSize = Vector2.new(56, 64), portalOffset = 22, wallHeight = 14,
  courtyardRadius = 44, worldRadius = 880,
  riftCenter = Vector3.new(0, 0, 0), riftRadius = 34,           -- courtyard fight circle
  boards = { { id = "Wave", angle = ... }, { id = "Pot", angle = ... } },   -- world leaderboards at the courtyard edge
}

Config.KindOrder = { "Ash", "Ember", "Frost", "Void" }
Config.KeyKinds[kind] = {
  id, name, order = 1..4, color: Color3, glow: Color3,
  statMult = 1 | 3 | 9 | 27,        -- monsters and gear (~3x per area)
  coinMult = 1 | 6 | 36 | 216,      -- coins, prices, sell, upgrade costs (~6x per area)
  unlockLevel = 1 | 5 | 10 | 15,
  monsters = { "AshImp", "CinderHound", "StoneBrute" }, boss = "AshenGolem",
  area = "Ash", shop = { Common = 150, Rare = 1500 },   -- x6 per area (Ember 900/9000 ...)
}

Config.Rarities = { { id = "Common", order = 1, color, maxLevel = 10, upgradeBase = 20, sell = 10, statMult = <computed> }, Rare 20/60/50, Epic 30/200/250, Legendary 40/700/1250, Mythic 50/2500/6250 }
Config.RarityById[id] = <row>
-- statMult computed in Config: Common 1; next = prev * LevelGrowth^(floor(prev.maxLevel/2) - 1)
Config.LevelGrowth = 1.06           -- +6% main stat per level (compounding, as the grey test did)
Config.UpgradeGrowth = 1.2          -- cost = upgradeBase * 1.2^level * kind.coinMult

Config.KeyRarityOrder = { "Common", "Rare", "Legendary" }
Config.KeyRarities[r] = {
  id, order, color, hp = 1|2|4, dmg = 1|2|4, coins = 1|2|5,
  gearOdds = "CommonKey"|"RareKey"|"LegendaryKey",      -- wave monster drops
  chestOdds = "RareKey"|"LegendaryKey"|"LegendaryChest", -- "next key rarity's odds"
  bossEvery = 0|5|5, bossChance = 0|0.3|1, mythicBossChest = 0|0|0.15,
}
Config.GearOdds[name] = { { "Common", 70 }, { "Rare", 25 }, { "Epic", 5 } }  -- ascending rarity, weights sum 100
  -- CommonKey 70/25/5, RareKey C40/R40/E17/L3, LegendaryKey R40/E35/L20/M5, LegendaryChest R25/E40/L28/M7

Config.Gear = {
  monsterDropChance = 0.03, chestOddsStepEvery = 5, chestOddsStep = 0.12,
  bigChestEvery = 5, bigChestCount = 3, bigChestMin = "Epic",
  bossChestCount = 3, bossChestMin = "Legendary",
  firstChest = { type = "Sword", rarity = "Rare" },     -- tutorial's first chest
}
Config.GearTypes[type] = {
  id, name ("Twin Blades"), slot = "Weapon"|"Armor", baseStat,
  -- weapons only:
  combo = { { windup, contact, recover, damage, range, arc, knock, heavy: boolean?, radius: number? (360 finisher), double: boolean? } x3 },
  comboReset = seconds, trailWidth, icon,
}
Config.KindGear[kind] = { "Sword", "Axe", "TwinBlades", "Armor" }
Config.Powers[kind] = { kind = "stagger"|"burn"|"slow"|"double", color, byRarity = { Rare = {...}, Epic = {...}, Legendary = {...}, Mythic = {...} } }
  -- stagger { chance, duration }   burn { dps (fraction of hit damage per second), duration }
  -- slow { amount (0..1 speed cut), duration }   double { chance }

Config.Combat = {
  playerBaseHp = 100, critChance = 0.10, critMult = 2,
  dodge = { duration = 0.35, cooldown = 1.5, speed = 46 },
  hitStop = { light = 0.06, heavy = 0.12, max = 0.15 }, regenPerSecond = 4, regenDelay = 4,
  autoFaceRange = 14, maxHitsPerSwing = 8,
}

Config.Waves = { baseCount = 4, maxAlive = 15, hpGrowth = 1.15, dmgGrowth = 1.10, coinGrowth = 1.08,
  countdown = 3, groupGap = { 2, 4 }, healBetween = 0.30, idleClose = 60, bossAdds = 2 }

Config.Monsters[id] = {
  id, name, kind, boss = false, bossTitle = "The Ashen Golem"?,
  hp, damage, speed, coins, weight, weightGrowth, minWave,
  size = Vector3, color = Color3, flying = false, hover = 0,      -- grey template + flyers
  notice = 45, giveUp = 90, leash = 60,                             -- map AI (studs)
  attacks = { "AshImpScratch", ... }, behaviour = "melee"|"pack"|"float"|"teleport"|"shield"|"boss",
  shieldArc = 0 (degrees of frontal block, Void Knight 120),
  emerge = "crawl"|"leap"|"burst", group = 1 (comes in groups of n),
  model = "AshImp",                 -- asset name in ServerStorage.Assets.Monsters
  anims = { idle = 0, move = 0, hit = 0, death = 0, emerge = 0, roar = 0, attacks = { [attackId] = 0 } },
  sounds = { growl = "AshImpGrowl", attack = "AshImpAttack", death = "AshImpDeath" },   -- Sfx row names
  deathColor = Color3,
}
-- 12 monsters + 4 bosses: AshImp, CinderHound, StoneBrute, AshenGolem; FlameSkeleton, LavaCrawler, EmberBat,
-- MoltenKnight; FrostWolf, IceWraith, GlacierTroll, Frostmaw; VoidShade, RiftEye, VoidKnight, HollowKing

Config.Attacks[id] = {
  id, shape = "melee"|"charge"|"slam"|"cone"|"rain"|"projectile"|"beam"|"pool"|"teleport"|"swoop"|"summon"|"arena",
  windup (>= 0.4 for anything with a warning), damage (x monster damage), range (start when target within),
  cooldown, warn = true|false, heavy = false,
  radius?, length?, width?, angle?, count?, spread?, speed?, duration?,   -- shape params
  status = { kind = "slow"|"burn", amount?, dps?, duration }?,
  hazard = { radius, dps (x monster damage per s), duration, style }?,  -- fire pools, embers
  summon = { monster, count }?, safeSpots = 3?, safeRadius = 7?,
  anim = "Scratch", sound = "Slam",
}

Config.Areas = {   -- array, in ring order outward; adding a fifth area = one more row
  { id = "Ash", name = "Ash Wastes", kind = "Ash", portalLevel = 1,
    inner = { radius = { 178, 255 }, monsters = { AshImp = 4, CinderHound = 3, StoneBrute = 2 }, keyChance = 0.08, odds = "MapInner", hp = 1, dmg = 1 },
    outer = { radius = { 255, 330 }, monsters = { ... }, keyChance = 0.12, odds = "MapOuter", hp = 1.4, dmg = 1.25 },
    gate = nil | { style = "rubble"|"ice"|"void", count = 4 },  -- Ember: rubble, Frost: ice, Void: void
    look = { ground = Color3, groundMaterial, accent, fog = Color3, fogDensity, haze, decay, bloom, cc = { tint, saturation, contrast, brightness }, particles = "Embers"|"Heat"|"Snow"|"Void", ambient, clock },
    music = "AreaAsh", props = "ruins"|"lava"|"ice"|"islands" },
  ...
}
Config.AreaById[id] = <row>
Config.MapKeyOdds = { MapInner = { {"Common",85},{"Rare",14},{"Legendary",1} }, MapOuter = { 75/22/3 },
                      MapInnerLucky = { 75/22/3 }, MapOuterLucky = { 65/30/5 } }
Config.MapMonsters = { respawn = 12, activeRadius = 160, tickHz = 10 }

Config.Portal = { maxLevel = 20, baseCost = 300, costGrowth = 1.6, bonusPerLevel = 0.05,
  tiers = { 1, 5, 10, 15, 20 } }    -- tier n starts at that level: bigger arch, more runes, more glow

Config.Inventory = { cap = 100, warnAt = 90 }
Config.Daily = { keyEvery = 86400 }
Config.Quests = { perDay = 3, list = { { id = "Wave10", text = "Reach wave 10", event = "WaveStarted", goal = 10, mode = "max" }, ... },
  rewards = { { coins = 300, key = "Common" }, { coins = 600, key = "Common" }, { key = "Rare" } } }  -- coins x best kind coinMult
Config.Index = { areaKey = "Rare", rowCoins = { Common = 200, Rare = 600, Epic = 2000, Legendary = 7000, Mythic = 25000 }, title = "Portal Warden" }
Config.Leaderboards = { stores = { Wave = "HighestWave_v1", Pot = "BiggestPot_v1" }, top = 10, refresh = 60, minWrite = 60 }
Config.Rift = { every = 900, firstAfter = 300, countdown = 30, waves = 3, waveSize = 8, hpPerExtra = 0.6,
  bossOrder = { "AshenGolem", "MoltenKnight", "Frostmaw", "HollowKing" }, bossScale = 1.6, bossHp = 2.5,
  rewardCoins = 500, topCount = 3, legendaryChance = 0.10, joinRadius = 60, timeLimit = 240 }
Config.Passes = { DoubleCoins = { id = 0, name = "2x Coins" }, LuckierKeys = { id = 0, name = "Luckier Keys", paidRandom = true } }
Config.Products = { RecoverSmall = { id = 0, tier = "small" }, RecoverMedium = { id = 0, tier = "medium" }, RecoverBig = { id = 0, tier = "big" } }
Config.Recover = { thresholds = { medium = 1000, big = 10000 }, offerSeconds = 600 }  -- lost value / kind.coinMult
Config.Tutorial = { firstWave = { monster = "AshImp", count = 3, hp = 0.6 }, closeAfterWave = 2, steps = { ...ids } }
Config.Anims = { player = { dodge = 0, hit = 0, fall = 0, victory = 0, keyUse = 0 },
  weapons = { Sword = { 0, 0, 0 }, Axe = { 0, 0, 0 }, TwinBlades = { 0, 0, 0 } } }
Config.Music = { ... }  -- track rows with id = 0 (section 9, Music)
Config.Studio = { muteAttribute = "StudioMuteUntil", tempDataAttribute = "StudioTempData" }
```

## 4. Logic API (`Shared/Logic.luau`, pure: numbers in, numbers out, `rng: Random` passed in)

Kept from the grey test (same signatures): `weightedPick`, `boostedOdds`, `rarityOrder`, `rollRarity`, `itemStat`, `itemName`, `itemSlot`, `formatStat`, `short`, `waveSpec`, `monsterMix`, `keptCoins`, `randomHalf`, `rollChest` (extended with `opts`), `rollGearType`, `rollMonsterGear`, `newItem`, `sortBest`.

New:
```lua
Logic.statAt(item: Item, level: number): number
Logic.maxLevel(rarity: string): number
Logic.upgradeCost(item: Item): number?             -- nil at max level
Logic.sellValue(item: Item): number                -- sell[rarity] * kind.coinMult
Logic.nextRarity(rarity: string): string?          -- nil for Mythic
Logic.itemKey(item): string                        -- "Ash|Sword|Rare" (merge identity, index key)
Logic.mergeGroup(items: { Item }, pick: Item, equipped: { [string]: string }): { string }?  -- 3 ids incl pick, lowest level first, pick always in; nil if not enough or Mythic
Logic.portalCost(level: number): number?           -- cost to go level -> level + 1; nil at max
Logic.portalBonus(level: number): number           -- 1 + 0.05 * (level - 1)
Logic.portalTier(level: number): number            -- 1..#Config.Portal.tiers
Logic.unlockedKinds(level: number): { string }     -- kinds whose unlockLevel <= level, in KindOrder
Logic.bestKind(level: number): string
Logic.keyPrice(kind: string, rarity: string): number?   -- nil for Legendary (never sold)
Logic.mapKeyOdds(band: "inner"|"outer", area: Area, lucky: boolean): { { any } }
Logic.rollMapKey(band, area, lucky: boolean, rng): string?    -- nil = no key; else rarity
Logic.oddsPercent(odds: { { any } }): { { id: string, percent: number } }  -- exact, sums to 100, 2 decimals max
Logic.isBossWave(wave: number, keyRarity: string, rng): boolean
Logic.rollChest(wave, keyRarity, kindId, rng, opts: { boss: boolean?, first: boolean? }?): { Item }  -- big / boss / first-chest rules
Logic.chestKind(wave: number, boss: boolean): "normal"|"big"|"boss"
Logic.killCoins(def: MonsterDef, spec: WaveSpec, portalLevel: number, coinMult: number): number  -- whole coins, >= 1
Logic.lossValue(coins: number, items: { Item }, kindId: string): number   -- (coins + sell values) / kind.coinMult
Logic.recoverTier(value: number): "small"|"medium"|"big"
Logic.power(item: Item): { kind: string, [string]: number }?   -- nil for Common or armor
Logic.dayNumber(t: number): number                 -- floor(t / 86400) (UTC days)
Logic.questsForDay(day: number, userId: number): { string }   -- 3 distinct quest ids, deterministic
Logic.questReward(slot: number, bestKind: string): { coins: number, key: string? }
Logic.indexRewards(index: IndexData): { { id: string, kind: "area"|"row"|"all", ... } }   -- earned and not yet claimed
Logic.riftHpMult(players: number): number          -- 1 + 0.6 * (players - 1)
Logic.maxHp(armor: Item?): number                  -- playerBaseHp + armor stat
Logic.weaponDamage(weapon: Item?): number          -- fists if nil
```

## 5. Remotes (`Shared/Net.luau`)

The client sends intent only, never amounts, prices or damage. Every handler starts with `RateLimit.allow(player, name, rate, burst)` using `Net.Limits[name]`, then validates types (NaN, inf, ranges, string length <= 64, known ids), ownership and state. Bad requests are dropped silently.

| Remote (client -> server) | Arguments | Rate/s, burst | Handler |
| --- | --- | --- | --- |
| Ready | none | 1, 2 | PlayerData (sends snapshots) |
| Attack | none | 12, 8 | Combat.onAttack |
| Dodge | none | 3, 3 | Combat.onDodge |
| UseKey | kind: string, rarity: string | 2, 3 | Openings.useKey |
| OpenChest | none | 2, 3 | Openings.openChest |
| Choice | choice: "close" or "more" | 2, 3 | Openings.choice |
| Equip | itemId: string | 5, 6 | Economy.equip |
| Upgrade | itemId: string | 8, 10 | Economy.upgrade |
| Merge | itemId: string | 3, 4 | Economy.merge |
| Sell | itemId: string, confirmed: boolean? | 6, 8 | Economy.sell |
| UpgradePortal | none | 3, 4 | Economy.upgradePortal |
| BuyKey | kind: string, rarity: string | 4, 5 | Economy.buyKey |
| ClaimDaily | none | 1, 2 | Daily.claimKey |
| ClaimQuest | slot: number (1-3) | 2, 4 | Daily.claimQuest |
| ClaimIndex | rewardId: string | 2, 4 | Index.claim |
| Setting | name: "music"/"sfx"/"shake"/"reducedMotion", value: number or boolean | 6, 12 | PlayerData.setSetting |
| Tutorial | action: "step"/"done"/"skip", step: number? | 4, 6 | Tutorial.onRemote |
| Recover | action: "skip" | 2, 3 | Purchases.skipRecover |
| Debug | cmd: string, arg: any (Studio only, created only in Studio) | 10, 10 | DebugTools |

| Remote (server -> client) | Payload | Notes |
| --- | --- | --- |
| Profile | PublicProfile | full snapshot, coalesced with `task.defer`, at most ~5/s |
| Opening | OpeningState | on every state change |
| Fx | FxEvent | reliable effects for this player |
| FxU | FxEvent | UnreliableRemoteEvent: cosmetic broadcasts (others' hits, deaths) |
| Hits | HitBatch | the attacker's own hit results (drives hit-stop, numbers, sound) |
| Warn | WarnShape | red warning zones, to the players who can be hit |
| Boss | BossBar or false | boss health bar, at most 5/s |
| Rift | RiftState | to everyone |
| Announce | text: string, style: string | server messages (Legendary key found, Rift) |
| Boards | BoardsData | leaderboard rows, every refresh and on Ready |

`Net` keeps the grey-test API (`Net.ToServer`, `Net.ToClient`, `Net.create()`, `Net.get(name)`, `Net.find(name)`) and adds `Net.Unreliable = { "FxU" }`, `Net.Limits = { [name] = { rate, burst } }` and `Net.getU(name): UnreliableRemoteEvent`.

## 6. Types and payloads (`Shared/Types.luau`)

```lua
export type Item = { id: string, kind: string, type: string, rarity: string, level: number }
export type Settings = { music: number, sfx: number, shake: boolean, reducedMotion: boolean }
export type QuestSlot = { id: string, progress: number, claimed: boolean }
export type IndexData = { monsters: { [string]: boolean }, gear: { [string]: boolean }, claimed: { [string]: boolean } }
export type Loss = { coins: number, items: { Item }, tier: string, kind: string, at: number }

export type PublicProfile = {
  coins: number, portalLevel: number, keys: { [string]: number }, items: { Item },
  equipped: { Weapon: string?, Armor: string? }, unlocked: { string }, bestKind: string,
  stats: { highestWave: number, biggestPot: number, monstersBeaten: number, openings: number, bossesBeaten: number },
  settings: Settings, quests: { day: number, list: { QuestSlot }, resetAt: number },
  index: IndexData, dailyReadyAt: number, tutorialDone: boolean, tutorialStep: number,
  passes: { DoubleCoins: boolean, LuckierKeys: boolean }, noPaidRandom: boolean,
  title: string?, invCap: number, serverTime: number, pendingLoss: Loss?,
  maxHp: number, damage: number,
}

export type OpeningState = {
  state: "none" | "cracking" | "countdown" | "wave" | "chest" | "between" | "closing" | "fallen",
  seq: number, kind: string?, rarity: string?, wave: number, bossWave: boolean,
  pot: { coins: number, items: { Item } }, left: number, total: number,
  chestKind: string?, chestItems: { Item }?,    -- items only after OPEN CHEST
  countdownEnd: number?, hp: number, maxHp: number, tutorial: boolean,
  result: { kind: "closed", coins: number, items: { Item } }
        | { kind: "fell", coinsKept: number, coinsLost: number, kept: { Item }, lost: { Item }, recover: { tier: string, product: string }? }?,
}

export type FxEvent = { k: string, [string]: any }
-- k values: KeyGet{kind,rarity,pos?,source}  Coins{amount,pos?,toPot}  GearDrop{item,pos}  Dodged{}  Hurt{amount,pos,status?}
-- MonsterHit{model,amount,crit,power?}  Death{model?,pos,kind,monsterId,boss}  Toast{text,style}  Shake{amount}
-- PortalCrack{plot,kind,rarity}  ChestBurst{plot,chestKind,pos}  LevelUp{itemId,level}  Merged{item}  Sold{coins,count}
-- PortalUp{level,tier,unlocked?}  Denied{action,reason}  Projectile{from,to,speed,style,radius}  Hazard{pos,radius,duration,style}
-- Teleport{from,to,model?}  Beam{from,to,width,duration,style}  Status{kind,duration}  GateOpen{area}  Swing{character,step,weapon}

export type HitBatch = { step: number, heavy: boolean, hits: { { model: Model, amount: number, crit: boolean, power: string?, pos: Vector3, killed: boolean, blocked: boolean? } } }
export type WarnShape = { id: number, shape: "circle" | "line" | "cone" | "rain" | "arena", cf: CFrame, duration: number,
  radius: number?, length: number?, width: number?, angle: number?, circles: { Vector3 }?, safe: { Vector3 }?, safeRadius: number?, style: string? }
export type BossBar = { name: string, hp: number, maxHp: number, kind: string, rift: boolean }
export type RiftState = { state: "idle" | "countdown" | "wave" | "boss" | "done", nextAt: number, endsAt: number?, wave: number, waves: number,
  bossName: string?, inOpening: boolean?, results: { { name: string, damage: number, rank: number } }? }
export type BoardsData = { Wave: { { name: string, userId: number, value: number } }, Pot: { { name: string, userId: number, value: number } } }
```

## 7. Server systems (`Server/Systems`, public API)

Shared server helpers (`Server/Lib`, not booted):
- `Bus.on(name, fn): () -> ()` (returns disconnect), `Bus.fire(name, ...)` - cross-system events (section 8). Handlers run in `task.spawn` with `pcall`.
- `SaveSchema.VERSION`, `SaveSchema.default(): Profile`, `SaveSchema.migrate(data: any): Profile` (also fills missing fields from the default and clamps types), `SaveSchema.MIGRATIONS`.
- `Receipts.has(profile, receiptId): boolean`, `Receipts.record(profile, receiptId, now)` (keeps the newest 100).
- `Attacks.run(mon, attackId, target: Player): ()` - runs one attack: warning, wind-up (>= 0.4 s), strike, resolution with `Geometry`, status, hazards, summons. Used by Monsters.
- `Status` - timed effects on monsters and players: `Status.apply(target, kind, params)`, `Status.speedMult(target)`, `Status.tick(dt)` (burn damage at 4 Hz).

| System | Public API (besides `init`/`start`) |
| --- | --- |
| RateLimit | `allow(player, key, rate, burst): boolean`, `clear(player)` |
| Save | `mode(): "datastore" | "memory" | "temp"`, `load(player): (boolean, Profile?, string?)` (claims the session lock, migrates; on failure returns false + reason), `save(player, profile, release: boolean): boolean`, `saveNow(player): boolean` (used by receipts) |
| PlayerData | `get(player): Session?`, `waitLoaded(player, timeout): Session?`, `onLoaded(fn)`, `onLeaving(fn)` (runs before the final save, e.g. Openings applies a fall), `snapshot(player)`, `recalc(player)`, `addCoins(player, n, source)`, `spendCoins(player, n): boolean`, `coinMult(player): number` (2 with the pass), `addKey(player, kind, rarity, n, source)`, `takeKey(player, kind, rarity): boolean`, `keyCount(player, kind, rarity)`, `addItem(player, item): Item?` (assigns `id`, overflow past cap auto-sells with a toast), `removeItem(player, id): Item?`, `findItem(player, id): Item?`, `equip(player, id): boolean`, `equipIfEmpty(player)`, `setHp(player, hp)`, `heal(player, n)`, `fullHeal(player)`, `bestKind(player)`, `unlocked(player): { string }`, `setSetting(player, name, value)` |
| Notify | `toast(player, text, style)`, `announce(text, style)` (all players, skips players in the tutorial), `fx(player, ev)`, `fxAll(ev)`, `fxNear(pos, radius, ev)` (FxU) |
| Plots | `assign(player): Model?`, `plotOf(player): Model?`, `indexOf(plot): number`, `ownerOf(plot): Player?`, `isInside(plot, pos): boolean`, `clampInside(plot, pos): Vector3`, `setWall(plot, on)`, `sendHome(player)`, `spot(plot, name): CFrame` (PlayerSpawn, ChestSpot, MonsterSpawn, PortalFront), `setTier(plot, level)`, `setPortalState(plot, state, kind?)` |
| Gates | `areaAt(pos): (Area?, "inner" | "outer" | nil)`, `canEnter(player, areaId): boolean`, `unlockedArea(player): Area` (outermost allowed), enforcement loop at 4 Hz that returns anyone past their allowed ring to just inside it, plus attribute `Area` on the player |
| Appearance | `refresh(player)` (welds the equipped weapon and armour models on the character, sets trail colours), `setTitle(player, title?)` |
| Monsters | `spawn(defId, cf, opts: SpawnOpts): Mon`, `damage(mon, amount, by: Player?, dir: Vector3?, opts: { heavy: boolean?, knock: number?, crit: boolean?, power: string? }?): boolean` (true if killed), `kill(mon, by)`, `despawn(mon)`, `fromModel(model): Mon?`, `all(): { Mon }`, `hittableBy(player): { Mon }`, `ownedBy(player): { Mon }`, `countOwned(player): number`, `setTarget(mon, player?)`, `onDeath(fn)` |
| Combat | `onAttack(player)`, `onDodge(player)`, `damagePlayer(player, amount, src: { mon: Mon?, status: { kind: string, amount: number?, dps: number?, duration: number }?, heavy: boolean? })`, `isInvuln(player): boolean`, `onDown(fn: (player) -> boolean)` (first handler returning true owns the fall; default sends home), `speedMult(player): number` |
| Openings | `useKey(player, kind, rarity)`, `openChest(player)`, `choice(player, choice)`, `isBusy(player): boolean`, `state(player): OpeningState?`, `debug(player, cmd, arg)` (killwave, boss, chest, fall, potgear) |
| MapMonsters | `debugKill(player)`, `count(): number` |
| Economy | handlers for Equip, Upgrade, Merge, Sell, UpgradePortal, BuyKey (all validated, state-checked: nothing changes during an opening except via the pot) |
| Daily | `claimKey(player)`, `claimQuest(player, slot)`, quest progress from Bus events |
| Index | `claim(player, rewardId)`, records monsters beaten and gear found from Bus events, sets the title |
| Leaderboards | records Highest Wave / Biggest Pot in OrderedDataStores (debounced, only improvements, never test players, never pots saved by Recover Loot), refreshes the world boards and sends `Boards` |
| Rift | `state(): RiftState`, `startNow()` (debug), `isActive(): boolean`, damage tracking per player, `onDown` handler for players inside the Rift |
| Purchases | `owns(player, passId): boolean`, `skipRecover(player)`, `ProcessReceipt` (idempotent, receipts saved before `PurchaseGranted`), pass checks on join and on purchase, PolicyService check (`NoPaidRandom`) |
| Tutorial | `isActive(player): boolean`, `onRemote(player, action, step)`, `grantUpgradeCoins(player)` (exactly one upgrade), first-wave and first-chest rules read by Openings |
| DebugTools | Studio only (`RunService:IsStudio()`), BindableFunction `ServerStorage.DebugCall` and the `Debug` remote: coins, portal, unlock, gear, key, boss, rift, reset, tutorial, heal, killwave, chest, fall, state, home, monsters |

`SpawnOpts = { mode: "opening" | "map" | "rift", owner: Player?, plot: Model?, hpMult: number, dmgMult: number, coinMult: number?, home: CFrame?, emerge: boolean?, scale: number?, glow: boolean?, boss: boolean?, band: string?, area: string? }`

`Mon = { id: number, def: MonsterDef, model: Model, root: BasePart, hp: number, maxHp: number, dmg: number, mode: string, owner: Player?, plot: Model?, alive: boolean, state: string, target: Player?, home: CFrame?, nextAttack: number, attackIndex: number, busyUntil: number, data: { [string]: any } }`

**Monster rigs (decision, see DECISIONS.md):** monsters are **AnimationController rigs moved by the server**, not Humanoids. Each model: an invisible `Root` part (CanCollide false, Massless false, server network owner) with `AlignPosition` (OneAttachment, `MaxVelocity` = speed) and `AlignOrientation` (OneAttachment), body parts joined to `Root` by `Motor6D`s, an `AnimationController` with an `Animator`. The AI ticks at 10 Hz, picks a target, raycasts the ground once per tick and moves the align targets. Physics does the smoothing in between, and replication interpolates. Flyers add `hover`. The `Monsters` API is the same as the grey test's.

**Session (in memory, never saved) = `{ player, profile, loaded: boolean, hp, maxHp, damage, invulnUntil, lastHurt, lastAttack, comboStep, dodgeReadyAt, passes = { DoubleCoins, LuckierKeys }, noPaidRandom, tutorial: { step, coinsGiven } }`.**

## 8. Bus events (exact names and arguments)

```
MonsterBeaten(player, monsterId, mode)          -- killer credit; mode "opening" | "map" | "rift"
BossBeaten(player, monsterId, mode)
OpeningStarted(player, kind, rarity)
WaveStarted(player, wave, kind, rarity)         -- Highest Wave leaderboard + "reach wave 10"
WaveCleared(player, wave)
PotClosed(player, coins, itemCount, recovered)  -- recovered = true for Recover Loot (never counts on boards)
Fell(player, wave)
ItemGained(player, item)                        -- whenever gear lands in the inventory
ItemMerged(player, item)
KeyGained(player, kind, rarity, source)
PortalLevel(player, level)
RiftHelped(player)
```

## 9. Client controllers (`Client/Controllers`, public API)

| Controller | Job and API |
| --- | --- |
| Ui | Style tokens (written first, also listed in DECISIONS.md) and builders: `Ui.T` (tokens), `Ui.scale()`, `Ui.screen(name, order, insets?) -> (ScreenGui, Frame)`, `Ui.designSize(gui): Vector2`, `Ui.panel`, `Ui.label`, `Ui.button(opts) -> Button`, `Ui.iconButton`, `Ui.rarityColor(r)`, `Ui.rarityTag`, `Ui.shine(obj) -> stop` (Legendary/Mythic border shine, paused while hidden), `Ui.slider(opts)`, `Ui.toggle(opts)`, `Ui.itemCard(item, opts)`, `Ui.denied(button, priceLabel?)` (shake + red flash, no popup), `Ui.isTouch()`, `Ui.fmt(n)`. Exact signatures are in `Ui.luau`'s header. |
| Store | Client state: `Store.profile`, `Store.opening`, `Store.rift`, `Store.boards`, `Store.boss`, signals `Store.changed: Signal<string>` ("profile", "opening", "rift", "boards", "boss"), `Store.serverTime()`, helpers `Store.item(id)`, `Store.keyCount(kind, rarity)`, `Store.isBusy()` |
| Effects | Camera shake by trauma + `rumble`, damage-number pool (36+), sparks, slashes, flash, death bursts by kind colour, warning zones that fill up (circle, line, cone, rain, arena with safe spots), projectiles, hazards, beams, teleport flashes, flying coins and icons on curves, toasts, hurt vignette. Honours the CameraShake setting and Reduced Motion. |
| Music | Area tracks by zone, combat music during openings (layer up every 5 waves), boss music, Rift music, crossfades, own SoundGroup, slider (`MusicVolume` attribute), Studio mute. All ids 0. |
| Zones | Per-area lighting by the player's position (Atmosphere, Bloom, ColorCorrection, ambient, particles), blended across ring borders; gate visuals and opening effects for unlocked areas; local gate collision off for unlocked gates. |
| MonsterFx | Monster health bars, wind-up glow, hit flash, placeholder motion for grey rigs (id 0), status tints, boss bar feed, emerge effects. |
| Combat | Input (hold ATTACK, click, Q / ButtonB dodge, ButtonX / R2 attack), auto-face, placeholder swings per weapon type written into joint Transform (own and other players' characters, from the `Swing` attribute), trails by kind and rarity, hit-stop, dodge roll with LinearVelocity, animation hooks for real ids with the `Hit` marker. |
| Hud | Coins top left, side buttons (Inventory, Portal, Keys, Quests, Index), STORE and SETTINGS top right, ATTACK + DODGE + health bar bottom right, context button (USE KEY / OPEN CHEST), Studio TEST panel. |
| Windows | One window at a time, grows from the button that opened it, content wave, main button last, faster close, dim layer, `Windows.open(name, fromButton?)`, `Windows.close()`, `Windows.current()`, `Windows.register(name, screenModule)`. Screens: Inventory, GearCard, Portal, Keys, StoreScreen, Quests, Index, Leaderboards, Settings, Confirm. |
| OpeningUi | Pot (top middle), between panel, wave banner, presentations queue with tokens: crack sequence, chest burst and hop, close celebration, fall card flips, Recover Loot offer, boss bar under the pot. |
| Reveal | Rarity-scaled reveals for chests, keys and gear (< 2 s Common, 5-6 s with rays, confetti and shine for Legendary/Mythic), tap skips. |
| RiftUi | Rift countdown at the top of every screen, wave/boss status, results card, "finish your portal to join" note. |
| Tutorial | 8-step spotlight (dim, bright circle centred on its target on every device, big arrow, short text, taps elsewhere blocked, Skip), ground arrow at the end. |

## 10. Save schema (version 1, `Server/Lib/SaveSchema.luau`)

DataStore `CrackAPortal_Players_v1`, key `p_<UserId>`, value `{ data = Profile, lock = { job = JobId, at = os.time() }?, savedAt = os.time() }`.

```lua
Profile = {
  version = 1,
  coins = 0,
  items = { { id = "i1", kind = "Ash", type = "Sword", rarity = "Common", level = 1 } },  -- starter sword
  equipped = { Weapon = "i1" },          -- Armor absent until found
  nextId = 2,
  keys = { ["Ash|Common"] = 1 },          -- the tutorial's free key
  portalLevel = 1,
  index = { monsters = {}, gear = {}, claimed = {} },
  quests = { day = 0, list = {} },        -- filled on load for today
  dailyKeyAt = 0,                         -- last claim time; free when now >= dailyKeyAt + 86400
  stats = { highestWave = 0, biggestPot = 0, monstersBeaten = 0, openings = 0, bossesBeaten = 0 },
  boardsSent = { Wave = 0, Pot = 0 },     -- last values written to the OrderedDataStores
  settings = { music = 0.6, sfx = 0.8, shake = true, reducedMotion = false },
  tutorialDone = false, tutorialStep = 0, tutorialCoins = false,
  receipts = {},                          -- [receiptId] = time, newest 100 kept
  pendingLoss = nil,                      -- Recover Loot offer: { coins, items, tier, kind, at }
  title = nil,
}
```
Rules: session lock via `UpdateAsync` (stale after 150 s; autosave every 60 s, staggered by UserId), retries with backoff (1, 2, 4, 8 s), `BindToClose` saves everyone in parallel (wait up to 25 s; no wait in Studio memory mode), a `loaded` flag (nothing saves before the profile is in), never save default data over a failed load (live server: kick with a friendly message), memory mode only in Studio (one clear warning), `StudioTempData` workspace attribute gives fresh temporary profiles, UserId <= 0 never saved. **The pot and opening state are never saved.** Leaving mid-wave = fall (applied in `onLeaving` before the final save); leaving between waves = the whole pot is kept.

## 11. Attributes

| On | Attributes |
| --- | --- |
| Player | `HP`, `MaxHP`, `Area`, `PortalLevel`, `MusicVolume`, `SfxVolume`, `CameraShake`, `ReducedMotion`, `NoPaidRandom`, `Title`, `InOpening`, `InRift`, `TutorialActive` |
| Character | `Swing` (combo step, increments per swing), `SwingType` (weapon type), `WeaponKind`, `WeaponRarity`, `Dodging` |
| Monster model | `MonsterId` (number), `Def`, `HP`, `MaxHP`, `Owner` (UserId, 0 for map/rift), `Mode`, `State`, `Attack`, `Boss`, `Kind`, `Burn`, `Slow`, `Stagger` (expiry times), `Dead`, `Emerge`; tag `Monster` |
| Plot model | `Index`, `Owner` (UserId), `Tier`, `PortalState` ("idle", "cracking", "open", "closing", "slam"), `PortalKind` |
| Workspace | `StudioMuteUntil` (number), `StudioTempData` (bool), `RiftState` |

## 12. Build order and who writes what

Work is split by file ownership so helpers never edit the same file:
1. Shared foundation: Config, Types, Logic, Net, Geometry, Signal, Assets, Templates, AnimHooks; server Lib (Bus, SaveSchema, Receipts, Status); RateLimit; specs for the pure modules.
2. In parallel: server systems (by group) and the client foundation (Ui tokens + builders, Store, Windows, init.client).
3. Client screens and controllers (after the client foundation), server systems finishing.
4. Integration: compile everything, run the specs, check every cross-module call against the real exports, selene, then the `roblox-reviewer` audit and fixes.
5. Docs: CHANGES.md (grouped by BUILD ORDER step), DECISIONS.md, PACING.md, ASSETS.md, NOTES.md, TODO_STUDIO.md; zip.

## 13. Testing

- `lune run tools/check.luau` - compiles every file with the real Luau compiler.
- `lune run tools/test.luau` - runs `ServerStorage/Tests/*.spec.luau` offline; in Studio `require(game.ServerStorage.Tests.Run)()` runs the same specs.
- `lune run tools/pacing.luau` - prints the pacing table used in PACING.md.
- `selene src` with `roblox_offline.yml` (Roblox globals) and `stylua --check src`.
- Strict type checking with Roblox definitions needs Studio (or luau-lsp with network access); listed in TODO_STUDIO.md.
