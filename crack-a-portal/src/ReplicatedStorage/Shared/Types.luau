--!strict
-- Types: the shapes shared by the server and the client (profile, items, payloads, Config rows).
-- No code here, only types. See PLAN.md section 6.

local Types = {}

---------------------------------------------------------------------------
-- Player data and payloads (PLAN.md section 6)
---------------------------------------------------------------------------

export type Item = { id: string, kind: string, type: string, rarity: string, level: number }
export type Settings = { music: number, sfx: number, shake: boolean, reducedMotion: boolean }
export type QuestSlot = { id: string, progress: number, claimed: boolean }
export type IndexData = {
	monsters: { [string]: boolean },
	gear: { [string]: boolean },
	claimed: { [string]: boolean },
}
export type Loss = { coins: number, items: { Item }, tier: string, kind: string, at: number }

export type PublicProfile = {
	coins: number,
	portalLevel: number,
	keys: { [string]: number },
	items: { Item },
	equipped: { Weapon: string?, Armor: string? },
	unlocked: { string },
	bestKind: string,
	stats: {
		highestWave: number,
		biggestPot: number,
		monstersBeaten: number,
		openings: number,
		bossesBeaten: number,
	},
	settings: Settings,
	quests: { day: number, list: { QuestSlot }, resetAt: number },
	index: IndexData,
	dailyReadyAt: number,
	tutorialDone: boolean,
	tutorialStep: number,
	passes: { DoubleCoins: boolean, LuckierKeys: boolean },
	noPaidRandom: boolean,
	title: string?,
	invCap: number,
	serverTime: number,
	pendingLoss: Loss?,
	maxHp: number,
	damage: number,
}

export type ClosedResult = { kind: "closed", coins: number, items: { Item } }
export type FellResult = {
	kind: "fell",
	coinsKept: number,
	coinsLost: number,
	kept: { Item },
	lost: { Item },
	recover: { tier: string, product: string }?,
}

export type OpeningState = {
	state: "none" | "cracking" | "countdown" | "wave" | "chest" | "between" | "closing" | "fallen",
	seq: number,
	kind: string?,
	rarity: string?,
	wave: number,
	bossWave: boolean,
	pot: { coins: number, items: { Item } },
	left: number,
	total: number,
	chestKind: string?,
	chestItems: { Item }?, -- items only after OPEN CHEST
	countdownEnd: number?,
	hp: number,
	maxHp: number,
	tutorial: boolean,
	result: (ClosedResult | FellResult)?,
}

-- k values:
--   KeyGet{kind,rarity,pos?,source}  Coins{amount,pos?,toPot}  GearDrop{item,pos}  Dodged{}  Hurt{amount,pos,status?}
--   MonsterHit{model,amount,crit,power?}  Death{model?,pos,kind,monsterId,boss}  Toast{text,style}  Shake{amount}
--   PortalCrack{plot,kind,rarity}  ChestBurst{plot,chestKind,pos}  LevelUp{itemId,level}  Merged{item}
--   Sold{coins,count}  PortalUp{level,tier,unlocked?}  Denied{action,reason}
--   Projectile{from,to,speed,style,radius}  Hazard{pos,radius,duration,style}  Teleport{from,to,model?}
--   Beam{from,to,width,duration,style}  Status{kind,duration}  GateOpen{area}  Swing{character,step,weapon}
export type FxEvent = { k: string, [string]: any }

export type Hit = {
	model: Model,
	amount: number,
	crit: boolean,
	power: string?,
	pos: Vector3,
	killed: boolean,
	blocked: boolean?,
}
export type HitBatch = { step: number, heavy: boolean, hits: { Hit } }

export type WarnShape = {
	id: number,
	shape: "circle" | "line" | "cone" | "rain" | "arena",
	cf: CFrame,
	duration: number,
	radius: number?,
	length: number?,
	width: number?,
	angle: number?,
	circles: { Vector3 }?,
	safe: { Vector3 }?,
	safeRadius: number?,
	style: string?,
}

export type BossBar = { name: string, hp: number, maxHp: number, kind: string, rift: boolean }

export type RiftResult = { name: string, damage: number, rank: number }
export type RiftState = {
	state: "idle" | "countdown" | "wave" | "boss" | "done",
	nextAt: number,
	endsAt: number?,
	wave: number,
	waves: number,
	bossName: string?,
	inOpening: boolean?,
	results: { RiftResult }?,
}

export type BoardRow = { name: string, userId: number, value: number }
export type BoardsData = { Wave: { BoardRow }, Pot: { BoardRow } }

---------------------------------------------------------------------------
-- Logic results
---------------------------------------------------------------------------

export type WaveSpec = {
	count: number, -- monsters in the wave
	hpMult: number,
	dmgMult: number,
	coinMult: number,
}

export type OddsRow = { any } -- { id: string, weight: number }
export type Odds = { OddsRow }
export type OddsPercent = { id: string, percent: number }

export type IndexReward = {
	id: string, -- "Area:Ash", "Row:Rare", "All"
	kind: "area" | "row" | "all",
	area: string?, -- area rewards: the area id (the key is of that area's kind)
	key: string?, -- area rewards: key rarity
	rarity: string?, -- row rewards
	coins: number?, -- row rewards
	title: string?, -- the whole index
}

---------------------------------------------------------------------------
-- Config rows (PLAN.md section 3)
---------------------------------------------------------------------------

export type KeyKind = {
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
	area: string,
	shop: { [string]: number }, -- Common / Rare prices (Legendary never sold)
}

export type Rarity = {
	id: string,
	order: number,
	color: Color3,
	maxLevel: number,
	upgradeBase: number,
	sell: number,
	statMult: number,
}

export type KeyRarity = {
	id: string,
	order: number,
	color: Color3,
	hp: number,
	dmg: number,
	coins: number,
	gearOdds: string,
	chestOdds: string,
	bossEvery: number,
	bossChance: number,
	mythicBossChest: number,
}

-- One hit of a weapon's 3-hit combo. Times in seconds: the hit lands at the end of `windup`,
-- `contact` is the strike, then `recover`. Total step time = windup + contact + recover.
export type ComboStep = {
	windup: number,
	contact: number,
	recover: number,
	damage: number, -- x weapon damage
	range: number, -- studs
	arc: number, -- degrees in front
	knock: number, -- knockback speed (studs/s)
	heavy: boolean?,
	radius: number?, -- finisher: also hits everything within this radius (360 degrees)
	double: boolean?, -- finisher: hits twice
}

export type GearType = {
	id: string,
	name: string,
	slot: "Weapon" | "Armor",
	baseStat: number,
	combo: { ComboStep }?,
	comboReset: number?,
	trailWidth: number?,
	icon: number, -- image id, 0 until made
	swing: string?, -- Sfx rows
	hit: string?,
	finisher: string?,
}

export type PowerDef = {
	kind: "stagger" | "burn" | "slow" | "double",
	color: Color3,
	byRarity: { [string]: { [string]: number } },
}

export type StatusDef = { kind: "slow" | "burn", amount: number?, dps: number?, duration: number }
export type HazardDef = { radius: number, dps: number, duration: number, style: string }

export type AttackShape =
	"melee"
	| "charge"
	| "slam"
	| "cone"
	| "rain"
	| "projectile"
	| "beam"
	| "pool"
	| "teleport"
	| "swoop"
	| "summon"
	| "arena"

export type AttackDef = {
	id: string,
	shape: AttackShape,
	windup: number,
	damage: number, -- x monster damage
	range: number, -- starts when the target is within this distance
	cooldown: number,
	warn: boolean,
	heavy: boolean,
	radius: number?,
	length: number?,
	width: number?,
	angle: number?,
	count: number?,
	spread: number?,
	speed: number?,
	duration: number?,
	status: StatusDef?,
	hazard: HazardDef?,
	summon: { monster: string, count: number }?,
	safeSpots: number?,
	safeRadius: number?,
	anim: string,
	sound: string,
}

export type MonsterAnims = {
	idle: number,
	move: number,
	hit: number,
	death: number,
	emerge: number,
	roar: number,
	attacks: { [string]: number },
}

export type MonsterDef = {
	id: string,
	name: string,
	kind: string,
	boss: boolean,
	bossTitle: string?,
	hp: number,
	damage: number,
	speed: number,
	coins: number,
	weight: number,
	weightGrowth: number,
	minWave: number,
	size: Vector3,
	color: Color3,
	flying: boolean,
	hover: number,
	notice: number,
	giveUp: number,
	leash: number,
	attacks: { string },
	behaviour: "melee" | "pack" | "float" | "teleport" | "shield" | "boss",
	shieldArc: number,
	emerge: "crawl" | "leap" | "burst",
	group: number,
	model: string,
	anims: MonsterAnims,
	sounds: { growl: string, attack: string, death: string, roar: string? },
	deathColor: Color3,
}

export type Band = {
	radius: { number }, -- { inner edge, outer edge } in studs from the centre
	monsters: { [string]: number },
	keyChance: number,
	odds: string,
	hp: number,
	dmg: number,
}

export type AreaLook = {
	ground: Color3,
	groundMaterial: Enum.Material,
	accent: Color3,
	fog: Color3,
	fogDensity: number,
	haze: number,
	glare: number,
	decay: Color3,
	bloom: number,
	cc: { tint: Color3, saturation: number, contrast: number, brightness: number },
	particles: string,
	ambient: Color3,
	clock: number,
}

export type Area = {
	id: string,
	name: string,
	kind: string,
	portalLevel: number,
	inner: Band,
	outer: Band,
	gate: { style: "rubble" | "ice" | "void", count: number }?,
	look: AreaLook,
	music: string,
	props: string,
}

export type Quest = {
	id: string,
	text: string,
	event: string,
	goal: number,
	mode: "count" | "max" | "atLeast",
	arg: number?, -- which event argument (after player) is the value for "max" / "atLeast"
	scaled: boolean?, -- goal x the player's best kind coinMult
}

export type MusicTrack = { id: number, trim: number?, title: string?, artist: string?, uploader: string? }

return Types
