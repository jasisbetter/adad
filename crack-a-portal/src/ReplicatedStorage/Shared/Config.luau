--!strict
-- Config: every number, monster, attack, key, gear type, area and odds table in the game.
-- Starting numbers; Sim/Pacing.luau tunes them and PACING.md records every change.
-- Adding a monster, an attack or a fifth area is a new row here, not new code.

local Types = require(script.Parent.Types)

type Odds = Types.Odds

local Config = {}

Config.Version = 1 -- the save schema version lives in SaveSchema, not here
Config.GreyTest = false -- grey-test shortcut OFF: map keys roll real rarities

local rgb = Color3.fromRGB

Config.Colors = {
	Gold = rgb(232, 188, 92),
	GoldBright = rgb(255, 214, 120),
	Ink = rgb(14, 12, 18),
	Panel = rgb(26, 23, 31),
	Stone = rgb(92, 90, 96),
	StoneDark = rgb(64, 62, 68),
	White = rgb(240, 236, 228),
	Muted = rgb(160, 154, 150),
	Ash = rgb(255, 138, 60),
	Ember = rgb(255, 92, 28),
	Frost = rgb(120, 200, 255),
	Void = rgb(170, 90, 255),
	Danger = rgb(230, 52, 52),
	Warn = rgb(255, 70, 50),
	Good = rgb(92, 214, 120),
	Crit = rgb(255, 205, 60),
	Burn = rgb(255, 130, 40),
	Slow = rgb(110, 180, 255),
	Double = rgb(190, 110, 255),
	Stagger = rgb(230, 220, 200),
}

---------------------------------------------------------------------------
-- Map (Build.luau reads these)
---------------------------------------------------------------------------

Config.Map = {
	plotCount = 8,
	plotRadius = 110,
	plotSize = Vector2.new(56, 64),
	portalOffset = 22,
	wallHeight = 14,
	courtyardRadius = 44,
	worldRadius = 880,
	riftCenter = Vector3.new(0, 0, 0),
	riftRadius = 34, -- courtyard fight circle
	-- world leaderboards at the courtyard edge, between plots 1-2 and 5-6 (radians)
	boards = {
		{ id = "Wave", angle = math.pi / 8 },
		{ id = "Pot", angle = math.pi + math.pi / 8 },
	},
}

---------------------------------------------------------------------------
-- Key kinds and rarities
---------------------------------------------------------------------------

Config.KindOrder = { "Ash", "Ember", "Frost", "Void" }

local SHOP_BASE = { Common = 150, Rare = 1500 } -- Ash prices, x kind.coinMult per area

local function kindRow(row: {
	id: string,
	name: string,
	order: number,
	color: Color3,
	glow: Color3,
	statMult: number,
	coinMult: number,
	unlockLevel: number,
	monsters: { string },
	boss: string,
}): Types.KeyKind
	local shop = {}
	for rarity, price in SHOP_BASE do
		shop[rarity] = price * row.coinMult
	end
	return {
		id = row.id,
		name = row.name,
		order = row.order,
		color = row.color,
		glow = row.glow,
		statMult = row.statMult,
		coinMult = row.coinMult,
		unlockLevel = row.unlockLevel,
		monsters = row.monsters,
		boss = row.boss,
		area = row.id,
		shop = shop,
	}
end

Config.KeyKinds = {
	Ash = kindRow({
		id = "Ash",
		name = "Ash",
		order = 1,
		color = rgb(150, 140, 132),
		glow = rgb(255, 138, 60),
		statMult = 1,
		coinMult = 1,
		unlockLevel = 1,
		monsters = { "AshImp", "CinderHound", "StoneBrute" },
		boss = "AshenGolem",
	}),
	Ember = kindRow({
		id = "Ember",
		name = "Ember",
		order = 2,
		color = rgb(60, 40, 36),
		glow = rgb(255, 92, 28),
		statMult = 3,
		coinMult = 6,
		unlockLevel = 5,
		monsters = { "FlameSkeleton", "LavaCrawler", "EmberBat" },
		boss = "MoltenKnight",
	}),
	Frost = kindRow({
		id = "Frost",
		name = "Frost",
		order = 3,
		color = rgb(200, 228, 250),
		glow = rgb(120, 200, 255),
		statMult = 9,
		coinMult = 36,
		unlockLevel = 10,
		monsters = { "FrostWolf", "IceWraith", "GlacierTroll" },
		boss = "Frostmaw",
	}),
	Void = kindRow({
		id = "Void",
		name = "Void",
		order = 4,
		color = rgb(40, 24, 60),
		glow = rgb(170, 90, 255),
		statMult = 27,
		coinMult = 216,
		unlockLevel = 15,
		monsters = { "VoidShade", "RiftEye", "VoidKnight" },
		boss = "HollowKing",
	}),
} :: { [string]: Types.KeyKind }

Config.KeyRarityOrder = { "Common", "Rare", "Legendary" }
Config.KeyRarities = {
	Common = {
		id = "Common",
		order = 1,
		color = rgb(170, 170, 176),
		hp = 1,
		dmg = 1,
		coins = 1,
		gearOdds = "CommonKey",
		chestOdds = "RareKey",
		bossEvery = 0,
		bossChance = 0,
		mythicBossChest = 0,
	},
	Rare = {
		id = "Rare",
		order = 2,
		color = rgb(70, 150, 255),
		hp = 2,
		dmg = 2,
		coins = 2,
		gearOdds = "RareKey",
		chestOdds = "LegendaryKey",
		bossEvery = 5,
		bossChance = 0.3,
		mythicBossChest = 0,
	},
	Legendary = {
		id = "Legendary",
		order = 3,
		color = rgb(255, 196, 50),
		hp = 4,
		dmg = 4,
		coins = 5,
		gearOdds = "LegendaryKey",
		chestOdds = "LegendaryChest",
		bossEvery = 5,
		bossChance = 1,
		mythicBossChest = 0.15,
	},
} :: { [string]: Types.KeyRarity }

---------------------------------------------------------------------------
-- Gear rarities, levels and odds
---------------------------------------------------------------------------

Config.LevelGrowth = 1.06 -- +6% main stat per level (compounding)
Config.UpgradeGrowth = 1.2 -- cost = upgradeBase * 1.2^level * kind.coinMult

Config.Rarities = {
	{ id = "Common", order = 1, color = rgb(158, 158, 164), maxLevel = 10, upgradeBase = 20, sell = 10, statMult = 1 },
	{ id = "Rare", order = 2, color = rgb(64, 146, 255), maxLevel = 20, upgradeBase = 60, sell = 50, statMult = 1 },
	{ id = "Epic", order = 3, color = rgb(172, 86, 244), maxLevel = 30, upgradeBase = 200, sell = 250, statMult = 1 },
	{
		id = "Legendary",
		order = 4,
		color = rgb(255, 192, 48),
		maxLevel = 40,
		upgradeBase = 700,
		sell = 1250,
		statMult = 1,
	},
	{
		id = "Mythic",
		order = 5,
		color = rgb(240, 56, 64),
		maxLevel = 50,
		upgradeBase = 2500,
		sell = 6250,
		statMult = 1,
	},
} :: { Types.Rarity }

-- statMult rule: a level 1 item of the next rarity = the rarity below at half its max level.
for i = 2, #Config.Rarities do
	local prev = Config.Rarities[i - 1]
	Config.Rarities[i].statMult = prev.statMult * Config.LevelGrowth ^ (math.floor(prev.maxLevel / 2) - 1)
end

Config.RarityById = {} :: { [string]: Types.Rarity }
for _, r in Config.Rarities do
	Config.RarityById[r.id] = r
end

-- Gear rarity odds, ascending rarity, weights sum to 100.
Config.GearOdds = {
	CommonKey = { { "Common", 70 }, { "Rare", 25 }, { "Epic", 5 } },
	RareKey = { { "Common", 40 }, { "Rare", 40 }, { "Epic", 17 }, { "Legendary", 3 } },
	LegendaryKey = { { "Rare", 40 }, { "Epic", 35 }, { "Legendary", 20 }, { "Mythic", 5 } },
	LegendaryChest = { { "Rare", 25 }, { "Epic", 40 }, { "Legendary", 28 }, { "Mythic", 7 } },
} :: { [string]: Odds }

Config.Gear = {
	monsterDropChance = 0.03,
	chestOddsStepEvery = 5,
	chestOddsStep = 0.12,
	bigChestEvery = 5,
	bigChestCount = 3,
	bigChestMin = "Epic",
	bossChestCount = 3,
	bossChestMin = "Legendary",
	firstChest = { type = "Sword", rarity = "Rare" }, -- tutorial's first chest
}

-- Weapons: each combo step lands at the end of `windup`. Twin Blades are fast and light with a
-- double-hit finisher; the Axe is slow and heavy with more knockback and a bigger finisher.
-- Damage per second over a full combo: Sword ~2.28x, Axe ~2.35x, Twin Blades ~2.31x weapon damage.
Config.GearTypes = {
	Sword = {
		id = "Sword",
		name = "Sword",
		slot = "Weapon",
		baseStat = 10,
		combo = {
			{ windup = 0.12, contact = 0.08, recover = 0.25, damage = 1.0, range = 8, arc = 110, knock = 6 },
			{ windup = 0.12, contact = 0.08, recover = 0.25, damage = 1.0, range = 8, arc = 110, knock = 6 },
			{
				windup = 0.18,
				contact = 0.1,
				recover = 0.4,
				damage = 1.6,
				range = 8.5,
				arc = 140,
				knock = 14,
				heavy = true,
				radius = 9,
			},
		},
		comboReset = 0.9,
		trailWidth = 1.2,
		icon = 0,
		swing = "SwordSwing",
		hit = "SwordHit",
		finisher = "SwordFinisher",
	},
	Axe = {
		id = "Axe",
		name = "Axe",
		slot = "Weapon",
		baseStat = 10,
		combo = {
			{
				windup = 0.3,
				contact = 0.12,
				recover = 0.45,
				damage = 1.8,
				range = 9,
				arc = 140,
				knock = 12,
				heavy = true,
			},
			{
				windup = 0.3,
				contact = 0.12,
				recover = 0.45,
				damage = 1.8,
				range = 9,
				arc = 140,
				knock = 12,
				heavy = true,
			},
			{
				windup = 0.42,
				contact = 0.13,
				recover = 0.6,
				damage = 3.2,
				range = 10,
				arc = 180,
				knock = 26,
				heavy = true,
				radius = 11.5,
			},
		},
		comboReset = 1.1,
		trailWidth = 1.6,
		icon = 0,
		swing = "AxeSwing",
		hit = "AxeHit",
		finisher = "AxeFinisher",
	},
	TwinBlades = {
		id = "TwinBlades",
		name = "Twin Blades",
		slot = "Weapon",
		baseStat = 10,
		combo = {
			{ windup = 0.07, contact = 0.06, recover = 0.17, damage = 0.65, range = 7, arc = 90, knock = 3 },
			{ windup = 0.07, contact = 0.06, recover = 0.17, damage = 0.65, range = 7, arc = 90, knock = 3 },
			{
				windup = 0.1,
				contact = 0.08,
				recover = 0.3,
				damage = 0.6, -- per hit, hits twice
				range = 7.5,
				arc = 120,
				knock = 8,
				double = true,
			},
		},
		comboReset = 0.7,
		trailWidth = 0.8,
		icon = 0,
		swing = "TwinSwing",
		hit = "TwinHit",
		finisher = "TwinFinisher",
	},
	Armor = {
		id = "Armor",
		name = "Armor",
		slot = "Armor",
		baseStat = 40, -- extra max health
		icon = 0,
	},
} :: { [string]: Types.GearType }

Config.KindGear = {
	Ash = { "Sword", "Axe", "TwinBlades", "Armor" },
	Ember = { "Sword", "Axe", "TwinBlades", "Armor" },
	Frost = { "Sword", "Axe", "TwinBlades", "Armor" },
	Void = { "Sword", "Axe", "TwinBlades", "Armor" },
}

-- Weapon powers (Rare and up). stagger { chance, duration }  burn { dps = fraction of hit damage
-- per second, duration }  slow { amount = speed cut 0..1, duration }  double { chance }
Config.Powers = {
	Ash = {
		kind = "stagger",
		color = Config.Colors.Stagger,
		byRarity = {
			Rare = { chance = 0.10, duration = 0.4 },
			Epic = { chance = 0.14, duration = 0.5 },
			Legendary = { chance = 0.19, duration = 0.65 },
			Mythic = { chance = 0.25, duration = 0.8 },
		},
	},
	Ember = {
		kind = "burn",
		color = Config.Colors.Burn,
		byRarity = {
			Rare = { dps = 0.15, duration = 3 },
			Epic = { dps = 0.2, duration = 3 },
			Legendary = { dps = 0.26, duration = 3.5 },
			Mythic = { dps = 0.34, duration = 4 },
		},
	},
	Frost = {
		kind = "slow",
		color = Config.Colors.Slow,
		byRarity = {
			Rare = { amount = 0.25, duration = 1.5 },
			Epic = { amount = 0.3, duration = 2 },
			Legendary = { amount = 0.36, duration = 2.5 },
			Mythic = { amount = 0.45, duration = 3 },
		},
	},
	Void = {
		kind = "double",
		color = Config.Colors.Double,
		byRarity = {
			Rare = { chance = 0.10 },
			Epic = { chance = 0.15 },
			Legendary = { chance = 0.21 },
			Mythic = { chance = 0.28 },
		},
	},
} :: { [string]: Types.PowerDef }

---------------------------------------------------------------------------
-- Combat and waves
---------------------------------------------------------------------------

Config.Combat = {
	playerBaseHp = 100,
	fistDamage = 5, -- no weapon equipped
	critChance = 0.10,
	critMult = 2,
	dodge = { duration = 0.35, cooldown = 1.5, speed = 46 },
	hitStop = { light = 0.06, heavy = 0.12, max = 0.15 },
	regenPerSecond = 4,
	regenDelay = 4,
	autoFaceRange = 14,
	maxHitsPerSwing = 8,
	comboGrace = 0.12, -- extra seconds the server allows between combo steps (latency)
	staggerImmune = 1.5, -- seconds a monster can't be staggered again
}

Config.Waves = {
	baseCount = 4,
	maxAlive = 15,
	hpGrowth = 1.15,
	dmgGrowth = 1.10,
	coinGrowth = 1.08,
	countdown = 3,
	groupGap = { 2, 4 },
	healBetween = 0.30,
	idleClose = 60,
	bossAdds = 2,
}

---------------------------------------------------------------------------
-- Attacks (damage is x the monster's damage; times in seconds; sizes in studs, angles in degrees)
---------------------------------------------------------------------------

local function attack(row: { [string]: any }): Types.AttackDef
	row.warn = if row.warn == nil then true else row.warn
	row.heavy = row.heavy == true
	return row :: any
end

Config.Attacks = {
	-- Ash
	AshImpScratch = attack({
		shape = "melee",
		windup = 0.45,
		damage = 1,
		range = 4.5,
		angle = 100,
		cooldown = 1.8,
		warn = false,
		anim = "Scratch",
		sound = "AshImpAttack",
	}),
	CinderHoundBite = attack({
		shape = "melee",
		windup = 0.45,
		damage = 0.8,
		range = 5,
		angle = 90,
		cooldown = 2,
		warn = false,
		anim = "Bite",
		sound = "CinderHoundAttack",
	}),
	CinderHoundCharge = attack({
		shape = "charge",
		windup = 0.6,
		damage = 1.3,
		range = 22,
		length = 26,
		width = 4,
		speed = 52,
		cooldown = 4.5,
		anim = "Charge",
		sound = "BossCharge",
	}),
	StoneBruteSlam = attack({
		shape = "slam",
		windup = 0.9,
		damage = 1.5,
		range = 8,
		radius = 9,
		cooldown = 3.5,
		heavy = true,
		anim = "Slam",
		sound = "Slam",
	}),
	GolemSlam = attack({
		shape = "slam",
		windup = 1.1,
		damage = 1.6,
		range = 12,
		radius = 14,
		cooldown = 4.5,
		heavy = true,
		anim = "Slam",
		sound = "Slam",
	}),
	GolemBoulder = attack({
		shape = "projectile",
		windup = 0.9,
		damage = 1.3,
		range = 60,
		radius = 7, -- landing circle
		count = 1,
		speed = 60,
		cooldown = 6,
		heavy = true,
		anim = "Throw",
		sound = "BoulderThrow",
	}),
	GolemRoar = attack({
		shape = "summon",
		windup = 1.2,
		damage = 0,
		range = 80,
		cooldown = 15,
		warn = false,
		summon = { monster = "AshImp", count = 3 },
		anim = "Roar",
		sound = "ImpSummon",
	}),

	-- Ember
	FlameSkeletonSwing = attack({
		shape = "melee",
		windup = 0.5,
		damage = 1,
		range = 6,
		angle = 120,
		cooldown = 2.2,
		warn = false,
		hazard = { radius = 4, dps = 0.25, duration = 3, style = "Embers" },
		anim = "Swing",
		sound = "FlameSkeletonAttack",
	}),
	LavaCrawlerBite = attack({
		shape = "melee",
		windup = 0.45,
		damage = 1,
		range = 5,
		angle = 90,
		cooldown = 1.8,
		warn = false,
		anim = "Bite",
		sound = "LavaCrawlerAttack",
	}),
	LavaCrawlerPool = attack({
		shape = "pool",
		windup = 0.5,
		damage = 0,
		range = 30,
		radius = 5,
		cooldown = 4,
		hazard = { radius = 5, dps = 0.4, duration = 5, style = "Fire" },
		anim = "Spit",
		sound = "FirePool",
	}),
	EmberBatSwoop = attack({
		shape = "swoop",
		windup = 0.6,
		damage = 1.1,
		range = 24,
		length = 22,
		width = 4,
		speed = 55,
		cooldown = 3.5,
		anim = "Swoop",
		sound = "EmberSwoop",
	}),
	MoltenSweep = attack({
		shape = "cone",
		windup = 0.9,
		damage = 1.5,
		range = 13,
		length = 14,
		angle = 100,
		cooldown = 4.5,
		heavy = true,
		anim = "Sweep",
		sound = "FireSweep",
	}),
	MoltenEruption = attack({
		shape = "rain",
		windup = 1.2,
		damage = 1.3,
		range = 40,
		radius = 5,
		count = 6,
		spread = 18,
		cooldown = 8,
		heavy = true,
		hazard = { radius = 4, dps = 0.3, duration = 2.5, style = "Fire" },
		anim = "Eruption",
		sound = "LavaErupt",
	}),
	MoltenCharge = attack({
		shape = "charge",
		windup = 0.8,
		damage = 1.4,
		range = 40,
		length = 34,
		width = 6,
		speed = 60,
		cooldown = 7,
		heavy = true,
		anim = "Charge",
		sound = "BossCharge",
	}),

	-- Frost
	FrostWolfBite = attack({
		shape = "melee",
		windup = 0.45,
		damage = 1,
		range = 5,
		angle = 90,
		cooldown = 1.6,
		warn = false,
		anim = "Bite",
		sound = "FrostWolfAttack",
	}),
	IceWraithShards = attack({
		shape = "projectile",
		windup = 0.7,
		damage = 1,
		range = 30,
		length = 32, -- each shard flies in a line (red line warnings)
		width = 3,
		count = 3,
		spread = 15, -- degrees between lines
		speed = 45,
		cooldown = 3.5,
		anim = "Cast",
		sound = "IceShard",
	}),
	GlacierStomp = attack({
		shape = "slam",
		windup = 1.0,
		damage = 1.4,
		range = 9,
		radius = 10,
		cooldown = 4,
		heavy = true,
		status = { kind = "slow", amount = 0.4, duration = 2.5 },
		anim = "Stomp",
		sound = "Slam",
	}),
	FrostmawBreath = attack({
		shape = "cone",
		windup = 1.0,
		damage = 1.5,
		range = 16,
		length = 18,
		angle = 70,
		duration = 1.2,
		cooldown = 6,
		status = { kind = "slow", amount = 0.35, duration = 2 },
		anim = "Breath",
		sound = "FrostBreath",
	}),
	FrostmawIcicles = attack({
		shape = "rain",
		windup = 1.3,
		damage = 1.1,
		range = 45,
		radius = 3.5,
		count = 12,
		spread = 22,
		cooldown = 9,
		anim = "Icicles",
		sound = "IcicleFall",
	}),
	FrostmawTail = attack({
		shape = "cone",
		windup = 0.8,
		damage = 1.3,
		range = 11,
		length = 13,
		angle = 220,
		cooldown = 5,
		heavy = true,
		anim = "TailSweep",
		sound = "TailSweep",
	}),

	-- Void
	VoidShadeClaw = attack({
		shape = "melee",
		windup = 0.45,
		damage = 1,
		range = 5,
		angle = 100,
		cooldown = 1.8,
		warn = false,
		anim = "Claw",
		sound = "VoidShadeAttack",
	}),
	VoidShadeTeleport = attack({
		shape = "teleport",
		windup = 0.6, -- purple flash where it will appear first
		damage = 1.2,
		range = 30,
		radius = 5, -- strike circle after it appears
		cooldown = 5,
		anim = "Teleport",
		sound = "Teleport",
	}),
	RiftEyeBeam = attack({
		shape = "beam",
		windup = 1.0, -- thin red line, then the beam
		damage = 1.5,
		range = 40,
		length = 42,
		width = 3,
		duration = 0.6,
		cooldown = 5,
		heavy = true,
		anim = "Beam",
		sound = "BeamFire",
	}),
	VoidKnightSlash = attack({
		shape = "melee",
		windup = 0.55,
		damage = 1.2,
		range = 6,
		angle = 120,
		cooldown = 2.4,
		warn = false,
		anim = "Slash",
		sound = "VoidKnightAttack",
	}),
	VoidKnightCleave = attack({
		shape = "cone",
		windup = 0.8,
		damage = 1.6,
		range = 8,
		length = 9,
		angle = 110,
		cooldown = 5,
		heavy = true,
		anim = "Cleave",
		sound = "VoidKnightAttack",
	}),
	HollowStrike = attack({
		shape = "cone",
		windup = 0.7,
		damage = 1.3,
		range = 10,
		length = 11,
		angle = 120,
		cooldown = 3,
		anim = "Strike",
		sound = "HollowKingAttack",
	}),
	HollowSummon = attack({
		shape = "summon",
		windup = 1.2,
		damage = 0,
		range = 80,
		cooldown = 16,
		warn = false,
		summon = { monster = "VoidShade", count = 2 },
		anim = "Summon",
		sound = "ShadeSummon",
	}),
	HollowOrbs = attack({
		shape = "projectile",
		windup = 0.9,
		damage = 1,
		range = 50,
		length = 50,
		radius = 3, -- orb size
		count = 5,
		spread = 25,
		speed = 35,
		cooldown = 6,
		anim = "Orbs",
		sound = "VoidOrb",
	}),
	HollowArena = attack({
		shape = "arena",
		windup = 2.2,
		damage = 2.2,
		range = 60,
		radius = 40, -- the whole fight area
		safeSpots = 3,
		safeRadius = 7,
		cooldown = 18,
		heavy = true,
		anim = "ArenaSlam",
		sound = "ArenaSlam",
	}),
} :: { [string]: Types.AttackDef }

for id, a in Config.Attacks do
	(a :: any).id = id
end

---------------------------------------------------------------------------
-- Monsters (Ash-scale numbers; the kind's statMult scales them)
---------------------------------------------------------------------------

local function monster(row: { [string]: any }): Types.MonsterDef
	local id = row.id :: string
	local attackAnims = {}
	for _, attackId in row.attacks :: { string } do
		attackAnims[attackId] = 0
	end
	row.boss = row.boss == true
	row.flying = row.flying == true
	row.hover = row.hover or 0
	row.shieldArc = row.shieldArc or 0
	row.group = row.group or 1
	row.notice = row.notice or 45
	row.giveUp = row.giveUp or 90
	row.leash = row.leash or 60
	row.model = id
	row.anims = { idle = 0, move = 0, hit = 0, death = 0, emerge = 0, roar = 0, attacks = attackAnims }
	row.sounds = {
		growl = `{id}Growl`,
		attack = `{id}Attack`,
		death = `{id}Death`,
		roar = if row.boss then `{id}Roar` else nil,
	}
	return row :: any
end

Config.Monsters = {
	-- Ash Wastes
	AshImp = monster({
		id = "AshImp",
		name = "Ash Imp",
		kind = "Ash",
		hp = 30,
		damage = 3,
		speed = 18,
		coins = 5,
		weight = 10,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(2, 2.6, 2),
		color = rgb(120, 112, 106),
		attacks = { "AshImpScratch" },
		behaviour = "melee",
		emerge = "leap",
		group = 3,
		deathColor = rgb(255, 140, 60),
	}),
	CinderHound = monster({
		id = "CinderHound",
		name = "Cinder Hound",
		kind = "Ash",
		hp = 55,
		damage = 6,
		speed = 16,
		coins = 8,
		weight = 5,
		weightGrowth = 0.6,
		minWave = 2,
		size = Vector3.new(2.6, 3, 5),
		color = rgb(88, 78, 72),
		attacks = { "CinderHoundBite", "CinderHoundCharge" },
		behaviour = "melee",
		emerge = "leap",
		group = 2,
		deathColor = rgb(255, 120, 50),
	}),
	StoneBrute = monster({
		id = "StoneBrute",
		name = "Stone Brute",
		kind = "Ash",
		hp = 140,
		damage = 10,
		speed = 9,
		coins = 15,
		weight = 2,
		weightGrowth = 0.45,
		minWave = 3,
		size = Vector3.new(5, 7, 4),
		color = rgb(104, 100, 98),
		attacks = { "StoneBruteSlam" },
		behaviour = "melee",
		emerge = "crawl",
		deathColor = rgb(200, 120, 70),
	}),
	AshenGolem = monster({
		id = "AshenGolem",
		name = "Ashen Golem",
		bossTitle = "The Ashen Golem",
		kind = "Ash",
		boss = true,
		hp = 900,
		damage = 12,
		speed = 8,
		coins = 120,
		weight = 0,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(9, 12, 7),
		color = rgb(96, 90, 86),
		notice = 70,
		giveUp = 140,
		leash = 90,
		attacks = { "GolemSlam", "GolemBoulder", "GolemRoar" },
		behaviour = "boss",
		emerge = "burst",
		deathColor = rgb(255, 140, 60),
	}),

	-- Ember Fields
	FlameSkeleton = monster({
		id = "FlameSkeleton",
		name = "Flame Skeleton",
		kind = "Ember",
		hp = 45,
		damage = 4,
		speed = 15,
		coins = 6,
		weight = 10,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(2.4, 5, 1.6),
		color = rgb(210, 196, 170),
		attacks = { "FlameSkeletonSwing" },
		behaviour = "melee",
		emerge = "crawl",
		group = 2,
		deathColor = rgb(255, 110, 30),
	}),
	LavaCrawler = monster({
		id = "LavaCrawler",
		name = "Lava Crawler",
		kind = "Ember",
		hp = 60,
		damage = 5,
		speed = 14,
		coins = 8,
		weight = 5,
		weightGrowth = 0.6,
		minWave = 2,
		size = Vector3.new(5, 2, 5),
		color = rgb(50, 34, 30),
		attacks = { "LavaCrawlerBite", "LavaCrawlerPool" },
		behaviour = "melee",
		emerge = "crawl",
		deathColor = rgb(255, 90, 20),
	}),
	EmberBat = monster({
		id = "EmberBat",
		name = "Ember Bat",
		kind = "Ember",
		hp = 40,
		damage = 6,
		speed = 20,
		coins = 9,
		weight = 3,
		weightGrowth = 0.5,
		minWave = 3,
		size = Vector3.new(4, 1.6, 2),
		color = rgb(70, 40, 36),
		flying = true,
		hover = 8,
		attacks = { "EmberBatSwoop" },
		behaviour = "float",
		emerge = "burst",
		group = 2,
		deathColor = rgb(255, 130, 40),
	}),
	MoltenKnight = monster({
		id = "MoltenKnight",
		name = "Molten Knight",
		bossTitle = "The Molten Knight",
		kind = "Ember",
		boss = true,
		hp = 1000,
		damage = 13,
		speed = 10,
		coins = 130,
		weight = 0,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(6, 11, 4),
		color = rgb(46, 32, 30),
		notice = 70,
		giveUp = 140,
		leash = 90,
		attacks = { "MoltenSweep", "MoltenEruption", "MoltenCharge" },
		behaviour = "boss",
		emerge = "burst",
		deathColor = rgb(255, 100, 20),
	}),

	-- Frost Hollow
	FrostWolf = monster({
		id = "FrostWolf",
		name = "Frost Wolf",
		kind = "Frost",
		hp = 40,
		damage = 4,
		speed = 19,
		coins = 6,
		weight = 10,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(2.4, 2.8, 4.6),
		color = rgb(206, 222, 236),
		attacks = { "FrostWolfBite" },
		behaviour = "pack",
		emerge = "leap",
		group = 3,
		deathColor = rgb(170, 220, 255),
	}),
	IceWraith = monster({
		id = "IceWraith",
		name = "Ice Wraith",
		kind = "Frost",
		hp = 50,
		damage = 6,
		speed = 12,
		coins = 9,
		weight = 5,
		weightGrowth = 0.6,
		minWave = 2,
		size = Vector3.new(3, 5, 2),
		color = rgb(160, 210, 245),
		flying = true,
		hover = 4,
		attacks = { "IceWraithShards" },
		behaviour = "float",
		emerge = "burst",
		deathColor = rgb(140, 210, 255),
	}),
	GlacierTroll = monster({
		id = "GlacierTroll",
		name = "Glacier Troll",
		kind = "Frost",
		hp = 150,
		damage = 10,
		speed = 8,
		coins = 15,
		weight = 2,
		weightGrowth = 0.45,
		minWave = 3,
		size = Vector3.new(6, 8, 4.5),
		color = rgb(120, 160, 196),
		attacks = { "GlacierStomp" },
		behaviour = "melee",
		emerge = "crawl",
		deathColor = rgb(190, 230, 255),
	}),
	Frostmaw = monster({
		id = "Frostmaw",
		name = "Frostmaw",
		bossTitle = "Frostmaw",
		kind = "Frost",
		boss = true,
		hp = 1100,
		damage = 13,
		speed = 9,
		coins = 140,
		weight = 0,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(10, 9, 16),
		color = rgb(180, 210, 236),
		notice = 70,
		giveUp = 140,
		leash = 90,
		attacks = { "FrostmawBreath", "FrostmawIcicles", "FrostmawTail" },
		behaviour = "boss",
		emerge = "burst",
		deathColor = rgb(170, 220, 255),
	}),

	-- Void Rift
	VoidShade = monster({
		id = "VoidShade",
		name = "Void Shade",
		kind = "Void",
		hp = 40,
		damage = 5,
		speed = 17,
		coins = 7,
		weight = 10,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(2.4, 4.6, 1.6),
		color = rgb(46, 30, 70),
		attacks = { "VoidShadeClaw", "VoidShadeTeleport" },
		behaviour = "teleport",
		emerge = "burst",
		group = 2,
		deathColor = rgb(170, 90, 255),
	}),
	RiftEye = monster({
		id = "RiftEye",
		name = "Rift Eye",
		kind = "Void",
		hp = 55,
		damage = 6,
		speed = 10,
		coins = 9,
		weight = 5,
		weightGrowth = 0.6,
		minWave = 2,
		size = Vector3.new(3.4, 3.4, 3.4),
		color = rgb(80, 40, 110),
		flying = true,
		hover = 6,
		attacks = { "RiftEyeBeam" },
		behaviour = "float",
		emerge = "burst",
		deathColor = rgb(200, 120, 255),
	}),
	VoidKnight = monster({
		id = "VoidKnight",
		name = "Void Knight",
		kind = "Void",
		hp = 130,
		damage = 9,
		speed = 11,
		coins = 15,
		weight = 2,
		weightGrowth = 0.45,
		minWave = 3,
		size = Vector3.new(3.6, 6.4, 2.4),
		color = rgb(36, 26, 52),
		attacks = { "VoidKnightSlash", "VoidKnightCleave" },
		behaviour = "shield",
		shieldArc = 120,
		emerge = "crawl",
		deathColor = rgb(160, 80, 240),
	}),
	HollowKing = monster({
		id = "HollowKing",
		name = "Hollow King",
		bossTitle = "The Hollow King",
		kind = "Void",
		boss = true,
		hp = 1200,
		damage = 14,
		speed = 9,
		coins = 150,
		weight = 0,
		weightGrowth = 0,
		minWave = 1,
		size = Vector3.new(6, 12, 4),
		color = rgb(30, 20, 46),
		notice = 70,
		giveUp = 140,
		leash = 90,
		attacks = { "HollowStrike", "HollowOrbs", "HollowSummon", "HollowArena" },
		behaviour = "boss",
		emerge = "burst",
		deathColor = rgb(180, 90, 255),
	}),
} :: { [string]: Types.MonsterDef }

---------------------------------------------------------------------------
-- Areas: rings going outward around the plots, in ring order. A fifth area = one more row.
---------------------------------------------------------------------------

Config.Areas = {
	{
		id = "Ash",
		name = "Ash Wastes",
		kind = "Ash",
		portalLevel = 1,
		inner = {
			radius = { 178, 255 },
			monsters = { AshImp = 4, CinderHound = 3, StoneBrute = 2 },
			keyChance = 0.08,
			odds = "MapInner",
			hp = 1,
			dmg = 1,
		},
		outer = {
			radius = { 255, 330 },
			monsters = { AshImp = 3, CinderHound = 3, StoneBrute = 3 },
			keyChance = 0.12,
			odds = "MapOuter",
			hp = 1.4,
			dmg = 1.25,
		},
		gate = nil,
		look = {
			ground = rgb(118, 114, 110),
			groundMaterial = Enum.Material.Ground,
			accent = rgb(255, 140, 60),
			fog = rgb(120, 112, 108),
			fogDensity = 0.35,
			haze = 1.6,
			glare = 0,
			decay = rgb(96, 74, 62),
			bloom = 0.8,
			cc = { tint = rgb(255, 240, 228), saturation = -0.25, contrast = 0.08, brightness = 0 },
			particles = "Embers",
			ambient = rgb(70, 64, 62),
			clock = 17.2,
		},
		music = "AreaAsh",
		props = "ruins",
	},
	{
		id = "Ember",
		name = "Ember Fields",
		kind = "Ember",
		portalLevel = 5,
		inner = {
			radius = { 350, 425 },
			monsters = { FlameSkeleton = 4, LavaCrawler = 3, EmberBat = 2 },
			keyChance = 0.08,
			odds = "MapInner",
			hp = 1,
			dmg = 1,
		},
		outer = {
			radius = { 425, 500 },
			monsters = { FlameSkeleton = 3, LavaCrawler = 3, EmberBat = 3 },
			keyChance = 0.12,
			odds = "MapOuter",
			hp = 1.4,
			dmg = 1.25,
		},
		gate = { style = "rubble", count = 4 },
		look = {
			ground = rgb(38, 32, 30),
			groundMaterial = Enum.Material.Basalt,
			accent = rgb(255, 100, 20),
			fog = rgb(96, 42, 24),
			fogDensity = 0.4,
			haze = 2.2,
			glare = 0.4,
			decay = rgb(255, 110, 40),
			bloom = 1.2,
			cc = { tint = rgb(255, 215, 190), saturation = 0.05, contrast = 0.12, brightness = 0.02 },
			particles = "Heat",
			ambient = rgb(90, 50, 35),
			clock = 18.4,
		},
		music = "AreaEmber",
		props = "lava",
	},
	{
		id = "Frost",
		name = "Frost Hollow",
		kind = "Frost",
		portalLevel = 10,
		inner = {
			radius = { 520, 595 },
			monsters = { FrostWolf = 4, IceWraith = 3, GlacierTroll = 2 },
			keyChance = 0.08,
			odds = "MapInner",
			hp = 1,
			dmg = 1,
		},
		outer = {
			radius = { 595, 670 },
			monsters = { FrostWolf = 3, IceWraith = 3, GlacierTroll = 3 },
			keyChance = 0.12,
			odds = "MapOuter",
			hp = 1.4,
			dmg = 1.25,
		},
		gate = { style = "ice", count = 4 },
		look = {
			ground = rgb(214, 226, 240),
			groundMaterial = Enum.Material.Snow,
			accent = rgb(120, 200, 255),
			fog = rgb(170, 200, 230),
			fogDensity = 0.45,
			haze = 1.2,
			glare = 0.2,
			decay = rgb(120, 160, 210),
			bloom = 0.9,
			cc = { tint = rgb(220, 235, 255), saturation = -0.1, contrast = 0.06, brightness = 0.03 },
			particles = "Snow",
			ambient = rgb(90, 110, 140),
			clock = 15,
		},
		music = "AreaFrost",
		props = "ice",
	},
	{
		id = "Void",
		name = "Void Rift",
		kind = "Void",
		portalLevel = 15,
		inner = {
			radius = { 690, 765 },
			monsters = { VoidShade = 4, RiftEye = 3, VoidKnight = 2 },
			keyChance = 0.08,
			odds = "MapInner",
			hp = 1,
			dmg = 1,
		},
		outer = {
			radius = { 765, 840 },
			monsters = { VoidShade = 3, RiftEye = 3, VoidKnight = 3 },
			keyChance = 0.12,
			odds = "MapOuter",
			hp = 1.4,
			dmg = 1.25,
		},
		gate = { style = "void", count = 4 },
		look = {
			ground = rgb(42, 32, 58),
			groundMaterial = Enum.Material.Slate,
			accent = rgb(180, 90, 255),
			fog = rgb(40, 20, 62),
			fogDensity = 0.42,
			haze = 0.8,
			glare = 0.6,
			decay = rgb(120, 60, 200),
			bloom = 1.3,
			cc = { tint = rgb(230, 210, 255), saturation = 0.1, contrast = 0.15, brightness = -0.02 },
			particles = "Void",
			ambient = rgb(60, 40, 90),
			clock = 0, -- night sky for the stars
		},
		music = "AreaVoid",
		props = "islands",
	},
} :: { Types.Area }

-- Plots and courtyard (inside the first ring): dark stone, torches.
Config.HubLook = {
	ground = rgb(64, 62, 68),
	groundMaterial = Enum.Material.Slate,
	accent = rgb(232, 188, 92),
	fog = rgb(70, 64, 72),
	fogDensity = 0.3,
	haze = 1.2,
	glare = 0,
	decay = rgb(90, 74, 70),
	bloom = 0.9,
	cc = { tint = rgb(255, 244, 232), saturation = -0.15, contrast = 0.08, brightness = 0 },
	particles = "Embers",
	ambient = rgb(72, 66, 70),
	clock = 17.6,
} :: Types.AreaLook

Config.AreaById = {} :: { [string]: Types.Area }
for _, area in Config.Areas do
	Config.AreaById[area.id] = area
end

-- Key rarity when a map monster drops a key (Lucky = Luckier Keys gamepass).
Config.MapKeyOdds = {
	MapInner = { { "Common", 85 }, { "Rare", 14 }, { "Legendary", 1 } },
	MapOuter = { { "Common", 75 }, { "Rare", 22 }, { "Legendary", 3 } },
	MapInnerLucky = { { "Common", 75 }, { "Rare", 22 }, { "Legendary", 3 } },
	MapOuterLucky = { { "Common", 65 }, { "Rare", 30 }, { "Legendary", 5 } },
} :: { [string]: Odds }

Config.MapMonsters = { respawn = 12, activeRadius = 160, tickHz = 10 }

---------------------------------------------------------------------------
-- Progression and long-term
---------------------------------------------------------------------------

Config.Portal = {
	maxLevel = 20,
	baseCost = 300,
	costGrowth = 1.6,
	bonusPerLevel = 0.05,
	tiers = { 1, 5, 10, 15, 20 }, -- tier n starts at that level: bigger arch, more runes, more glow
}

Config.Inventory = { cap = 100, warnAt = 90 }
Config.Daily = { keyEvery = 86400 }

-- Daily quests. mode "count": +1 per event. "max": keeps the highest event value.
-- "atLeast": done when one event value reaches the goal. `arg` = which event argument after the
-- player is the value (Bus events, PLAN.md section 8). `scaled` = goal x best kind coinMult.
Config.Quests = {
	perDay = 3,
	list = {
		{ id = "Wave10", text = "Reach wave 10", event = "WaveStarted", goal = 10, mode = "max", arg = 1 },
		{
			id = "Pot5000",
			text = "Close a pot worth 5,000 coins",
			event = "PotClosed",
			goal = 5000,
			mode = "atLeast",
			arg = 1,
			scaled = true,
		},
		{ id = "Beat100", text = "Beat 100 monsters", event = "MonsterBeaten", goal = 100, mode = "count" },
		{ id = "Open3", text = "Open 3 portals", event = "OpeningStarted", goal = 3, mode = "count" },
		{ id = "Boss1", text = "Beat a boss", event = "BossBeaten", goal = 1, mode = "count" },
		{ id = "Merge1", text = "Merge an item", event = "ItemMerged", goal = 1, mode = "count" },
		{ id = "Rift1", text = "Help in a Server Rift", event = "RiftHelped", goal = 1, mode = "count" },
		{ id = "Clear15", text = "Clear 15 waves", event = "WaveCleared", goal = 15, mode = "count" },
		{ id = "Keys3", text = "Find 3 keys", event = "KeyGained", goal = 3, mode = "count" },
		{ id = "Gear5", text = "Collect 5 pieces of gear", event = "ItemGained", goal = 5, mode = "count" },
	} :: { Types.Quest },
	-- slot 1 and 2: coins (x best kind coinMult) and a Common key; slot 3: a Rare key
	rewards = { { coins = 300, key = "Common" }, { coins = 600, key = "Common" }, { coins = 0, key = "Rare" } },
}

Config.Index = {
	areaKey = "Rare",
	rowCoins = { Common = 200, Rare = 600, Epic = 2000, Legendary = 7000, Mythic = 25000 },
	title = "Portal Warden",
}

Config.Leaderboards = {
	stores = { Wave = "HighestWave_v1", Pot = "BiggestPot_v1" },
	top = 10,
	refresh = 60,
	minWrite = 60,
}

Config.Rift = {
	every = 900,
	firstAfter = 300,
	countdown = 30,
	waves = 3,
	waveSize = 8,
	hpPerExtra = 0.6,
	bossOrder = { "AshenGolem", "MoltenKnight", "Frostmaw", "HollowKing" },
	bossScale = 1.6,
	bossHp = 2.5,
	rewardCoins = 500,
	topCount = 3,
	legendaryChance = 0.10,
	joinRadius = 60,
	timeLimit = 240,
}

-- Ids are 0 until Jas creates them on the website (TODO_STUDIO.md). Prices come from product info.
Config.Passes = {
	DoubleCoins = { id = 0, name = "2x Coins" },
	LuckierKeys = { id = 0, name = "Luckier Keys", paidRandom = true },
}
Config.Products = {
	RecoverSmall = { id = 0, tier = "small" },
	RecoverMedium = { id = 0, tier = "medium" },
	RecoverBig = { id = 0, tier = "big" },
}
-- Recover Loot tier: lost value (coins + sell values) / kind coinMult.
Config.Recover = { thresholds = { medium = 1000, big = 10000 }, offerSeconds = 600 }

Config.Tutorial = {
	firstWave = { monster = "AshImp", count = 3, hp = 0.6 },
	closeAfterWave = 2,
	steps = { "Portal", "Key", "Attack", "Dodge", "Chest", "Choice", "Gear", "Explore" },
}

---------------------------------------------------------------------------
-- Animation, music and Studio hooks (ids 0 until made in Studio)
---------------------------------------------------------------------------

Config.Anims = {
	player = { dodge = 0, hit = 0, fall = 0, victory = 0, keyUse = 0 },
	weapons = { Sword = { 0, 0, 0 }, Axe = { 0, 0, 0 }, TwinBlades = { 0, 0, 0 } },
}

-- Every id stays 0 until Jas picks tracks in Studio. An id-0 track is skipped (silence or the layer below).
Config.Music = {
	Hub = { { id = 0 } } :: { Types.MusicTrack }, -- plots + courtyard calm bed (also the tutorial-safe default)
	Tutorial = { id = 0 } :: Types.MusicTrack, -- optional; falls back to Hub
	Areas = { -- calm dark fantasy track per area, keyed by area.music
		AreaAsh = { id = 0 },
		AreaEmber = { id = 0 },
		AreaFrost = { id = 0 },
		AreaVoid = { id = 0 },
	} :: { [string]: Types.MusicTrack },
	Combat = { -- openings: tier = Logic.musicTier(wave), one step every `tierEvery` waves
		{ id = 0 }, -- waves 1-4
		{ id = 0 }, -- waves 5-9
		{ id = 0 }, -- waves 10-14
		{ id = 0 }, -- waves 15+
	} :: { Types.MusicTrack },
	tierEvery = 5,
	Boss = {
		Ash = { id = 0 },
		Ember = { id = 0 },
		Frost = { id = 0 },
		Void = { id = 0 },
	} :: { [string]: Types.MusicTrack },
	Rift = { id = 0 } :: Types.MusicTrack, -- countdown + Rift waves
	RiftBoss = { id = 0 } :: Types.MusicTrack, -- falls back to Boss[kind], then Rift
	Priority = { zone = 1, combat = 2, rift = 3, boss = 5 },
	Fade = { zone = 1.5, combat = 1.5, tier = 2.0, rift = 1.0, boss = 0.4, out = 1.5 },
}

Config.Studio = { muteAttribute = "StudioMuteUntil", tempDataAttribute = "StudioTempData" }

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

Config.MonsterIds = {} :: { string }
Config.BossByKind = {} :: { [string]: string }
for id in Config.Monsters do
	table.insert(Config.MonsterIds, id)
end
table.sort(Config.MonsterIds)
for kindId, kind in Config.KeyKinds do
	Config.BossByKind[kindId] = kind.boss
end

---------------------------------------------------------------------------
-- Checks at load (cheap): a typo here fails loudly instead of in the middle of a fight.
---------------------------------------------------------------------------

local function checkOdds(name: string, odds: Odds)
	local total = 0
	for _, row in odds do
		total += row[2] :: number
	end
	assert(math.abs(total - 100) < 1e-9, `Config odds {name} sum to {total}, not 100`)
end
for name, odds in Config.GearOdds do
	checkOdds(name, odds)
	for _, row in odds do
		assert(Config.RarityById[row[1]], `GearOdds {name}: unknown rarity {row[1]}`)
	end
end
for name, odds in Config.MapKeyOdds do
	checkOdds(name, odds)
	for _, row in odds do
		assert(Config.KeyRarities[row[1]], `MapKeyOdds {name}: unknown key rarity {row[1]}`)
	end
end
for id, kr in Config.KeyRarities do
	assert(Config.GearOdds[kr.gearOdds], `KeyRarity {id}: unknown gearOdds`)
	assert(Config.GearOdds[kr.chestOdds], `KeyRarity {id}: unknown chestOdds`)
end
for id, def in Config.Monsters do
	assert(Config.KeyKinds[def.kind], `Monster {id}: unknown kind {def.kind}`)
	for _, attackId in def.attacks do
		assert(Config.Attacks[attackId], `Monster {id}: unknown attack {attackId}`)
	end
end
for id, a in Config.Attacks do
	assert(a.windup >= 0.4, `Attack {id}: wind-up under 0.4 s`)
	if a.summon then
		assert(Config.Monsters[a.summon.monster], `Attack {id}: unknown summon {a.summon.monster}`)
	end
end
for kindId, kind in Config.KeyKinds do
	assert(#kind.monsters == 3, `Kind {kindId}: needs 3 monsters`)
	for _, monsterId in kind.monsters do
		assert(Config.Monsters[monsterId], `Kind {kindId}: unknown monster {monsterId}`)
	end
	assert(Config.Monsters[kind.boss] and Config.Monsters[kind.boss].boss, `Kind {kindId}: bad boss {kind.boss}`)
	assert(Config.KindGear[kindId], `Kind {kindId}: no KindGear row`)
	assert(Config.Powers[kindId], `Kind {kindId}: no Powers row`)
	assert(Config.AreaById[kind.area], `Kind {kindId}: unknown area {kind.area}`)
end
for _, kindId in Config.KindOrder do
	assert(Config.KeyKinds[kindId], `KindOrder: unknown kind {kindId}`)
end
for _, area in Config.Areas do
	assert(Config.KeyKinds[area.kind], `Area {area.id}: unknown kind`)
	assert(Config.Music.Areas[area.music], `Area {area.id}: unknown music {area.music}`)
	for _, band in { area.inner, area.outer } do
		assert(Config.MapKeyOdds[band.odds] and Config.MapKeyOdds[band.odds .. "Lucky"], `Area {area.id}: bad odds`)
		assert(band.radius[1] < band.radius[2] and band.radius[2] <= Config.Map.worldRadius, `Area {area.id}: radius`)
		for monsterId in band.monsters do
			assert(Config.Monsters[monsterId], `Area {area.id}: unknown monster {monsterId}`)
		end
	end
end
for _, list in Config.KindGear do
	for _, typeId in list do
		assert(Config.GearTypes[typeId], `KindGear: unknown gear type {typeId}`)
	end
end
assert(Config.GearTypes[Config.Gear.firstChest.type], "Gear.firstChest: unknown type")
assert(Config.RarityById[Config.Gear.firstChest.rarity], "Gear.firstChest: unknown rarity")
assert(Config.Monsters[Config.Tutorial.firstWave.monster], "Tutorial.firstWave: unknown monster")
for _, bossId in Config.Rift.bossOrder do
	assert(Config.Monsters[bossId], `Rift.bossOrder: unknown boss {bossId}`)
end
do
	local events = {
		MonsterBeaten = true,
		BossBeaten = true,
		OpeningStarted = true,
		WaveStarted = true,
		WaveCleared = true,
		PotClosed = true,
		Fell = true,
		ItemGained = true,
		ItemMerged = true,
		KeyGained = true,
		PortalLevel = true,
		RiftHelped = true,
	}
	for _, q in Config.Quests.list do
		assert(events[q.event], `Quest {q.id}: unknown event {q.event}`)
	end
	assert(#Config.Quests.list >= Config.Quests.perDay, "Quests: fewer quests than perDay")
end

return Config
