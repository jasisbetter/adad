--!strict
-- Templates: grey fallback models built by code, used whenever Assets returns nil.
-- Real models must follow the same names (contract in ASSETS.md), so no gameplay code
-- cares which one it got.
--
-- Monster rig contract:
--   Model (Atomic streaming), PrimaryPart "Root": invisible box of the monster's size,
--   CanCollide/CanQuery/CanTouch false, Massless false, pivot at the bottom centre, front = -Z.
--   Visible parts: unanchored, non-colliding, CanQuery/CanTouch false, Massless, each joined
--   to its parent part by a Motor6D named after the part (Body -> Root, the rest -> Body or
--   their limb), parented to Part0. Templates.joints(model) maps names to the Motor6Ds.
--   Attachments: RootAttachment (Root, centre), Eye (front of the head), Glow (body centre),
--   Top (above the head, health bars), Weapon (on the weapon), Shield (Void Knight's shield).
--   AnimationController > Animator. Neon accents in the kind's glow colour.

local Config = require(script.Parent.Config)

local Templates = {}

-- Only the MonsterDef fields this module reads (PLAN.md section 3).
export type MonsterDefLite = {
	id: string,
	kind: string,
	size: Vector3,
	color: Color3,
	flying: boolean?,
	hover: number?,
	behaviour: string?,
	boss: boolean?,
	model: string?,
}

-- One body part, in fractions of the monster's size: c = centre (x: width, y: height from
-- the ground, z: length with -0.5 at the front), s = size, r = degrees.
type PartSpec = {
	name: string,
	parent: string?,
	c: { number },
	s: { number },
	r: { number }?,
	shape: string?,
	tone: string?,
	mirror: boolean?,
	alpha: number?,
}

type RigSpec = {
	material: Enum.Material?,
	eye: string?, -- part that holds the Eye attachment (front face)
	weapon: string?,
	shield: string?,
	parts: { PartSpec },
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local METAL = Color3.fromRGB(74, 72, 82)
local BONE = Color3.fromRGB(226, 214, 188)
local DARK = Color3.fromRGB(16, 12, 22)
local GOLD = Color3.fromRGB(222, 178, 70)
local ICE = Color3.fromRGB(176, 224, 255)
local WOOD = Color3.fromRGB(92, 62, 40)

local RARITY_ORDER_FALLBACK: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------

local function kindColors(kind: string): (Color3, Color3)
	local row = (Config.KeyKinds :: any)[kind]
	if row then
		return row.color, row.glow
	end
	return Color3.fromRGB(150, 150, 150), WHITE
end

local function rarityOrder(rarity: string?): number
	if not rarity then
		return 1
	end
	local row = (Config.RarityById :: any)[rarity]
	return if row then row.order else (RARITY_ORDER_FALLBACK[rarity] or 1)
end

local function rarityColor(rarity: string?): Color3
	local row = rarity and (Config.RarityById :: any)[rarity]
	return if row then row.color else WHITE
end

local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Anchored = false
	p.Massless = true
	p.CastShadow = size.Magnitude > 1.5
	return p
end

local function attach(name: string, parent: BasePart, offset: CFrame): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = offset
	a.Parent = parent
	return a
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Name = b.Name
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function light(parent: BasePart, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

local function sparkles(parent: BasePart, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkles"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(0.4, 1.4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
end

local function setLocked(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Locked = true
		end
	end
end

---------------------------------------------------------------------------
-- monster rigs (part specs)
---------------------------------------------------------------------------

-- P(name, parent, cx, cy, cz, sx, sy, sz, extra?)
local function P(
	name: string,
	parent: string?,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	extra: { [string]: any }?
): PartSpec
	local spec: PartSpec = { name = name, parent = parent, c = { cx, cy, cz }, s = { sx, sy, sz } }
	if extra then
		spec.r = extra.r
		spec.shape = extra.shape
		spec.tone = extra.tone
		spec.mirror = extra.mirror
		spec.alpha = extra.alpha
	end
	return spec
end

local M = { mirror = true }
local GLOW = { tone = "glow" }
local GLOW_M = { tone = "glow", mirror = true }

local RIGS: { [string]: RigSpec } = {
	-- small, hunched, horns
	AshImp = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.45, 0.05, 0.7, 0.42, 0.6, { r = { 22, 0, 0 } }),
			P("Head", "Body", 0, 0.74, -0.22, 0.56, 0.34, 0.5),
			P("Horn", "Head", 0.2, 0.96, -0.16, 0.1, 0.26, 0.1, { mirror = true, r = { -10, 0, -22 }, tone = "dark" }),
			P("Eye", "Head", 0.12, 0.77, -0.47, 0.1, 0.07, 0.04, GLOW_M),
			P("Arm", "Body", 0.42, 0.4, -0.15, 0.15, 0.42, 0.15, { mirror = true, r = { 25, 0, 0 } }),
			P("Leg", "Body", 0.18, 0.13, 0.1, 0.18, 0.26, 0.2, M),
			P("Tail", "Body", 0, 0.3, 0.45, 0.08, 0.08, 0.4, { r = { -30, 0, 0 }, tone = "dark" }),
		},
	},
	-- long, four legs
	CinderHound = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.56, 0.02, 0.62, 0.32, 0.62),
			P("Head", "Body", 0, 0.72, -0.36, 0.5, 0.28, 0.24),
			P("Snout", "Head", 0, 0.64, -0.5, 0.32, 0.16, 0.16, { tone = "dark" }),
			P("Ear", "Head", 0.16, 0.9, -0.34, 0.1, 0.14, 0.06, { mirror = true, shape = "Wedge" }),
			P("Eye", "Head", 0.13, 0.76, -0.485, 0.08, 0.05, 0.03, GLOW_M),
			P("LegF", "Body", 0.22, 0.2, -0.22, 0.16, 0.4, 0.1, M),
			P("LegB", "Body", 0.22, 0.2, 0.24, 0.16, 0.4, 0.1, M),
			P("Tail", "Body", 0, 0.66, 0.42, 0.1, 0.08, 0.26, { r = { 25, 0, 0 } }),
			P("Embers", "Body", 0, 0.73, 0.02, 0.12, 0.04, 0.5, GLOW),
		},
	},
	-- big and broad
	StoneBrute = {
		material = Enum.Material.Slate,
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.56, 0, 0.72, 0.4, 0.6),
			P("Head", "Body", 0, 0.82, -0.12, 0.3, 0.17, 0.3),
			P("Eye", "Head", 0.07, 0.84, -0.275, 0.07, 0.03, 0.03, GLOW_M),
			P("Arm", "Body", 0.43, 0.5, -0.05, 0.2, 0.48, 0.26, M),
			P("Fist", "Arm", 0.44, 0.2, -0.08, 0.26, 0.17, 0.32, { mirror = true, tone = "dark" }),
			P("Leg", "Body", 0.2, 0.17, 0, 0.24, 0.34, 0.3, M),
			P("Brow", "Head", 0, 0.9, -0.2, 0.32, 0.05, 0.16, { tone = "dark" }),
		},
	},
	-- huge, rocky, glowing cracks (boss)
	AshenGolem = {
		material = Enum.Material.Slate,
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.56, 0, 0.66, 0.38, 0.52),
			P("Head", "Body", 0, 0.84, -0.12, 0.26, 0.16, 0.26),
			P("Eye", "Head", 0.06, 0.85, -0.255, 0.06, 0.03, 0.02, GLOW_M),
			P("Core", "Body", 0, 0.6, -0.265, 0.18, 0.18, 0.03, GLOW),
			P("Shoulder", "Body", 0.36, 0.75, 0, 0.3, 0.24, 0.32, { mirror = true, shape = "Ball", tone = "dark" }),
			P("Arm", "Body", 0.42, 0.47, -0.02, 0.2, 0.44, 0.24, M),
			P("Fist", "Arm", 0.44, 0.18, -0.06, 0.3, 0.22, 0.32, { mirror = true, tone = "dark" }),
			P("Crack", "Arm", 0.42, 0.5, -0.145, 0.04, 0.3, 0.02, GLOW_M),
			P("Leg", "Body", 0.19, 0.16, 0, 0.26, 0.32, 0.3, M),
			P("RockA", "Body", -0.2, 0.74, 0.22, 0.2, 0.14, 0.16, { r = { 20, 30, 10 }, tone = "dark" }),
			P("RockB", "Body", 0.18, 0.7, 0.24, 0.16, 0.12, 0.14, { r = { -15, 10, 25 }, tone = "dark" }),
			P("RockC", "Body", 0, 0.78, 0.2, 0.18, 0.12, 0.16, { r = { 10, 45, 0 }, tone = "dark" }),
			P("Brow", "Head", 0, 0.9, -0.22, 0.3, 0.05, 0.12, { tone = "dark" }),
		},
	},
	-- humanoid skeleton with a sword
	FlameSkeleton = {
		eye = "Head",
		weapon = "Weapon",
		parts = {
			P("Body", nil, 0, 0.62, 0, 0.42, 0.22, 0.24, { tone = "bone" }),
			P("Spine", "Body", 0, 0.45, 0, 0.1, 0.14, 0.1, { tone = "bone" }),
			P("Hips", "Spine", 0, 0.38, 0, 0.32, 0.05, 0.18, { tone = "bone" }),
			P("Head", "Body", 0, 0.85, 0, 0.26, 0.16, 0.3, { tone = "bone" }),
			P("Jaw", "Head", 0, 0.76, -0.04, 0.18, 0.04, 0.2, { tone = "bone" }),
			P("Eye", "Head", 0.06, 0.86, -0.15, 0.06, 0.03, 0.02, GLOW_M),
			P("Flame", "Head", 0, 0.97, 0.02, 0.14, 0.08, 0.14, { tone = "glow", shape = "Ball" }),
			P("Arm", "Body", 0.27, 0.58, 0, 0.08, 0.36, 0.1, { mirror = true, tone = "bone" }),
			P("Leg", "Hips", 0.1, 0.19, 0, 0.08, 0.36, 0.1, { mirror = true, tone = "bone" }),
			P("Weapon", "ArmR", 0.28, 0.42, -0.62, 0.04, 0.05, 0.9, { tone = "metal" }),
			P("WeaponGlow", "Weapon", 0.28, 0.42, -0.7, 0.045, 0.02, 0.7, GLOW),
		},
	},
	-- spider with 8 legs and lava spots
	LavaCrawler = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.42, 0.18, 0.46, 0.42, 0.46, { shape = "Ball" }),
			P("Head", "Body", 0, 0.36, -0.16, 0.3, 0.24, 0.26),
			P("Eye", "Head", 0.06, 0.42, -0.295, 0.05, 0.05, 0.02, GLOW_M),
			P("Eye2", "Head", 0.11, 0.38, -0.285, 0.04, 0.04, 0.02, GLOW_M),
			P("Spots", "Body", 0, 0.62, 0.18, 0.26, 0.06, 0.26, GLOW),
			P("Leg1", "Body", 0.32, 0.26, -0.22, 0.4, 0.07, 0.07, { mirror = true, r = { 0, 25, -28 }, tone = "dark" }),
			P("Leg2", "Body", 0.34, 0.26, -0.07, 0.42, 0.07, 0.07, { mirror = true, r = { 0, 8, -28 }, tone = "dark" }),
			P("Leg3", "Body", 0.34, 0.26, 0.09, 0.42, 0.07, 0.07, { mirror = true, r = { 0, -8, -28 }, tone = "dark" }),
			P("Leg4", "Body", 0.32, 0.26, 0.25, 0.4, 0.07, 0.07, { mirror = true, r = { 0, -25, -28 }, tone = "dark" }),
		},
	},
	-- bat with wings
	EmberBat = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.5, 0, 0.18, 0.4, 0.4, { shape = "Ball" }),
			P("Head", "Body", 0, 0.72, -0.18, 0.15, 0.26, 0.26),
			P("Ear", "Head", 0.04, 0.9, -0.18, 0.04, 0.14, 0.08, { mirror = true, shape = "Wedge" }),
			P("Eye", "Head", 0.035, 0.74, -0.315, 0.03, 0.05, 0.02, GLOW_M),
			P("Wing", "Body", 0.27, 0.56, 0.02, 0.36, 0.04, 0.42, { mirror = true, r = { 0, 0, 10 } }),
			P("WingTip", "Wing", 0.43, 0.6, 0.08, 0.14, 0.03, 0.3, { mirror = true, r = { 0, 0, 25 }, tone = "glow" }),
			P("Foot", "Body", 0.04, 0.24, 0.05, 0.03, 0.12, 0.05, { mirror = true, tone = "dark" }),
		},
	},
	-- armoured knight with a big burning sword (boss)
	MoltenKnight = {
		eye = "Head",
		weapon = "Weapon",
		parts = {
			P("Body", nil, 0, 0.6, 0, 0.44, 0.28, 0.3, { tone = "metal" }),
			P("Core", "Body", 0, 0.62, -0.155, 0.14, 0.12, 0.02, GLOW),
			P("Skirt", "Body", 0, 0.42, 0, 0.4, 0.1, 0.3, { tone = "dark" }),
			P("Shoulder", "Body", 0.27, 0.73, 0, 0.22, 0.1, 0.32, { mirror = true, tone = "metal" }),
			P("Head", "Body", 0, 0.85, 0, 0.18, 0.12, 0.24, { tone = "metal" }),
			P("Visor", "Head", 0, 0.855, -0.125, 0.14, 0.02, 0.02, GLOW),
			P("Crest", "Head", 0, 0.94, 0.02, 0.04, 0.06, 0.22, { tone = "glow" }),
			P("Arm", "Body", 0.3, 0.56, 0, 0.11, 0.26, 0.14, M),
			P("Gauntlet", "Arm", 0.3, 0.41, -0.02, 0.13, 0.07, 0.17, { mirror = true, tone = "metal" }),
			P("Leg", "Body", 0.11, 0.2, 0, 0.14, 0.38, 0.18, M),
			P("Boot", "Leg", 0.11, 0.03, -0.03, 0.16, 0.06, 0.24, { mirror = true, tone = "metal" }),
			P("Crack", "Leg", 0.11, 0.24, -0.095, 0.03, 0.2, 0.02, GLOW_M),
			P("Weapon", "ArmR", 0.32, 0.62, -0.42, 0.05, 0.6, 0.14, { tone = "metal" }),
			P("Guard", "Weapon", 0.32, 0.33, -0.42, 0.06, 0.04, 0.3, { tone = "dark" }),
			P("WeaponGlow", "Weapon", 0.32, 0.64, -0.495, 0.055, 0.54, 0.02, GLOW),
		},
	},
	-- wolf with a mane, comes in packs
	FrostWolf = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.56, 0.06, 0.6, 0.3, 0.56),
			P("Mane", "Body", 0, 0.64, -0.18, 0.7, 0.4, 0.22, { tone = "light" }),
			P("Head", "Body", 0, 0.72, -0.36, 0.46, 0.26, 0.22),
			P("Snout", "Head", 0, 0.64, -0.49, 0.28, 0.14, 0.14, { tone = "light" }),
			P("Ear", "Head", 0.15, 0.9, -0.34, 0.1, 0.16, 0.06, { mirror = true, shape = "Wedge" }),
			P("Eye", "Head", 0.12, 0.76, -0.475, 0.08, 0.04, 0.03, GLOW_M),
			P("LegF", "Body", 0.2, 0.2, -0.2, 0.15, 0.4, 0.1, M),
			P("LegB", "Body", 0.2, 0.2, 0.26, 0.15, 0.4, 0.1, M),
			P("Tail", "Body", 0, 0.72, 0.42, 0.14, 0.14, 0.3, { r = { 40, 0, 0 }, tone = "light" }),
		},
	},
	-- floating cloak with a hood
	IceWraith = {
		eye = "Hood",
		parts = {
			P("Body", nil, 0, 0.56, 0, 0.44, 0.38, 0.4, { alpha = 0.1 }),
			P("Hem", "Body", 0, 0.28, 0.02, 0.58, 0.26, 0.5, { alpha = 0.25 }),
			P(
				"Tatter",
				"Hem",
				0.2,
				0.12,
				0.05,
				0.12,
				0.2,
				0.3,
				{ mirror = true, shape = "Wedge", r = { 180, 0, 0 }, alpha = 0.35 }
			),
			P("Hood", "Body", 0, 0.83, 0, 0.34, 0.24, 0.4),
			P("Face", "Hood", 0, 0.81, -0.19, 0.24, 0.16, 0.03, { tone = "black" }),
			P("Eye", "Hood", 0.06, 0.83, -0.21, 0.06, 0.03, 0.02, GLOW_M),
			P("Arm", "Body", 0.3, 0.58, -0.1, 0.12, 0.36, 0.14, { mirror = true, r = { 35, 0, -10 } }),
			P("Shard", "ArmR", 0.32, 0.5, -0.42, 0.08, 0.2, 0.08, { tone = "ice", r = { 0, 45, 0 } }),
		},
	},
	-- big troll with tusks and ice spikes
	GlacierTroll = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.56, 0.05, 0.68, 0.4, 0.55),
			P("Belly", "Body", 0, 0.46, -0.22, 0.48, 0.28, 0.1, { tone = "light" }),
			P("Head", "Body", 0, 0.8, -0.18, 0.3, 0.2, 0.3),
			P("Tusk", "Head", 0.08, 0.74, -0.34, 0.04, 0.1, 0.04, { mirror = true, r = { -20, 0, 0 }, tone = "bone" }),
			P("Eye", "Head", 0.07, 0.84, -0.335, 0.05, 0.03, 0.02, GLOW_M),
			P("Arm", "Body", 0.42, 0.45, -0.05, 0.2, 0.52, 0.22, M),
			P("Fist", "Arm", 0.43, 0.15, -0.06, 0.26, 0.15, 0.28, { mirror = true, tone = "light" }),
			P("Leg", "Body", 0.19, 0.15, 0.02, 0.22, 0.3, 0.26, M),
			P("Spike1", "Body", 0, 0.82, 0.18, 0.08, 0.16, 0.08, { tone = "ice", r = { 20, 0, 0 } }),
			P("Spike2", "Body", 0.18, 0.78, 0.22, 0.07, 0.14, 0.07, { tone = "ice", r = { 20, 0, -20 } }),
			P("Spike3", "Body", -0.18, 0.78, 0.22, 0.07, 0.14, 0.07, { tone = "ice", r = { 20, 0, 20 } }),
		},
	},
	-- giant ice beast with a tail (boss)
	Frostmaw = {
		eye = "Head",
		parts = {
			P("Body", nil, 0, 0.52, 0.08, 0.58, 0.38, 0.5),
			P("Chest", "Body", 0, 0.56, -0.2, 0.62, 0.46, 0.22, { tone = "light" }),
			P("Head", "Chest", 0, 0.66, -0.4, 0.34, 0.24, 0.2),
			P("Jaw", "Head", 0, 0.53, -0.42, 0.28, 0.07, 0.18, { tone = "light" }),
			P("Mouth", "Head", 0, 0.6, -0.505, 0.18, 0.04, 0.02, GLOW),
			P(
				"Horn",
				"Head",
				0.14,
				0.82,
				-0.36,
				0.05,
				0.18,
				0.05,
				{ mirror = true, r = { -30, 0, -15 }, tone = "ice" }
			),
			P("Eye", "Head", 0.1, 0.7, -0.505, 0.05, 0.03, 0.02, GLOW_M),
			P("LegF", "Chest", 0.24, 0.18, -0.2, 0.17, 0.36, 0.14, M),
			P("LegB", "Body", 0.22, 0.18, 0.24, 0.17, 0.36, 0.14, M),
			P("Tail", "Body", 0, 0.46, 0.46, 0.13, 0.12, 0.3, { r = { -12, 0, 0 } }),
			P("TailTip", "Tail", 0, 0.42, 0.66, 0.1, 0.09, 0.2, { tone = "ice" }),
			P("Spike1", "Body", 0, 0.76, -0.08, 0.06, 0.12, 0.06, { tone = "ice" }),
			P("Spike2", "Body", 0, 0.74, 0.08, 0.06, 0.12, 0.06, { tone = "ice" }),
			P("Spike3", "Body", 0, 0.72, 0.22, 0.06, 0.11, 0.06, { tone = "ice" }),
			P("Spike4", "Tail", 0, 0.56, 0.42, 0.05, 0.09, 0.05, { tone = "ice" }),
		},
	},
	-- wisp: dark ball with a glowing core and trailing puffs
	VoidShade = {
		eye = "Body",
		parts = {
			P("Body", nil, 0, 0.66, 0, 0.6, 0.36, 0.6, { shape = "Ball", alpha = 0.3 }),
			P("Core", "Body", 0, 0.66, 0, 0.3, 0.18, 0.3, { shape = "Ball", tone = "glow" }),
			P("Eye", "Body", 0.12, 0.7, -0.29, 0.08, 0.04, 0.03, GLOW_M),
			P("Arm", "Body", 0.34, 0.56, -0.05, 0.12, 0.26, 0.12, { mirror = true, r = { 20, 0, -25 }, alpha = 0.3 }),
			P("Wisp1", "Body", 0, 0.44, 0.06, 0.4, 0.14, 0.4, { shape = "Ball", alpha = 0.4 }),
			P("Wisp2", "Wisp1", 0, 0.28, 0.12, 0.26, 0.1, 0.26, { shape = "Ball", alpha = 0.5 }),
			P("Wisp3", "Wisp2", 0, 0.15, 0.16, 0.14, 0.07, 0.14, { shape = "Ball", alpha = 0.6 }),
		},
	},
	-- floating eye with an iris and tendrils
	RiftEye = {
		eye = "Body",
		parts = {
			P("Body", nil, 0, 0.56, 0, 0.76, 0.76, 0.76, { shape = "Ball" }),
			P(
				"Iris",
				"Body",
				0,
				0.56,
				-0.37,
				0.04,
				0.36,
				0.36,
				{ shape = "Cylinder", r = { 0, 90, 0 }, tone = "glow" }
			),
			P(
				"Pupil",
				"Iris",
				0,
				0.56,
				-0.395,
				0.02,
				0.16,
				0.16,
				{ shape = "Cylinder", r = { 0, 90, 0 }, tone = "black" }
			),
			P("Lid", "Body", 0, 0.86, -0.12, 0.6, 0.12, 0.5, { tone = "dark" }),
			P(
				"Ring",
				"Body",
				0,
				0.56,
				0.08,
				0.04,
				0.9,
				0.9,
				{ shape = "Cylinder", r = { 0, 0, 90 }, tone = "glow", alpha = 0.3 }
			),
			P("Tendril1", "Body", 0.15, 0.16, 0.15, 0.06, 0.3, 0.06, { r = { 15, 0, -10 }, tone = "dark" }),
			P("Tendril2", "Body", -0.15, 0.16, 0.15, 0.06, 0.3, 0.06, { r = { 15, 0, 10 }, tone = "dark" }),
			P("Tendril3", "Body", 0.1, 0.14, -0.1, 0.05, 0.26, 0.05, { r = { -10, 0, -8 }, tone = "dark" }),
			P("Tendril4", "Body", -0.1, 0.14, -0.1, 0.05, 0.26, 0.05, { r = { -10, 0, 8 }, tone = "dark" }),
		},
	},
	-- knight with a big shield on the front
	VoidKnight = {
		eye = "Head",
		weapon = "Weapon",
		shield = "Shield",
		parts = {
			P("Body", nil, 0, 0.6, 0, 0.42, 0.26, 0.3, { tone = "metal" }),
			P("Skirt", "Body", 0, 0.43, 0, 0.38, 0.09, 0.3, { tone = "dark" }),
			P("Shoulder", "Body", 0.26, 0.72, 0, 0.2, 0.08, 0.3, { mirror = true, tone = "metal" }),
			P("Head", "Body", 0, 0.84, 0, 0.18, 0.12, 0.24),
			P("Visor", "Head", 0, 0.85, -0.125, 0.12, 0.02, 0.02, GLOW),
			P("Horn", "Head", 0.08, 0.94, 0, 0.03, 0.08, 0.03, { mirror = true, r = { 0, 0, -20 }, tone = "dark" }),
			P("Arm", "Body", 0.28, 0.56, 0, 0.1, 0.26, 0.14, M),
			P("Leg", "Body", 0.1, 0.2, 0, 0.13, 0.38, 0.18, M),
			P("Shield", "ArmL", -0.14, 0.52, -0.42, 0.62, 0.5, 0.06, { tone = "metal" }),
			P("ShieldRune", "Shield", -0.14, 0.52, -0.455, 0.14, 0.24, 0.02, GLOW),
			P("Weapon", "ArmR", 0.3, 0.5, -0.4, 0.04, 0.05, 0.6, { tone = "metal" }),
			P("WeaponGlow", "Weapon", 0.3, 0.5, -0.45, 0.045, 0.02, 0.48, GLOW),
		},
	},
	-- tall robed king with a crown and a staff (boss)
	HollowKing = {
		eye = "Head",
		weapon = "Weapon",
		parts = {
			P("Body", nil, 0, 0.62, 0, 0.34, 0.24, 0.24),
			P("Robe", "Body", 0, 0.26, 0, 0.46, 0.46, 0.36, { tone = "dark" }),
			P("Cape", "Body", 0, 0.5, 0.14, 0.42, 0.6, 0.03, { tone = "dark" }),
			P("Head", "Body", 0, 0.82, 0, 0.16, 0.11, 0.2, { tone = "black" }),
			P("Eye", "Head", 0.035, 0.83, -0.1, 0.035, 0.015, 0.02, GLOW_M),
			P("Crown", "Head", 0, 0.9, 0, 0.18, 0.03, 0.22, { tone = "gold" }),
			P("CrownSpike1", "Crown", 0, 0.94, -0.1, 0.03, 0.06, 0.03, { tone = "glow" }),
			P("CrownSpike2", "Crown", 0.07, 0.935, -0.07, 0.025, 0.05, 0.025, { tone = "gold" }),
			P("CrownSpike3", "Crown", -0.07, 0.935, -0.07, 0.025, 0.05, 0.025, { tone = "gold" }),
			P("CrownSpike4", "Crown", 0.08, 0.93, 0.05, 0.025, 0.04, 0.025, { tone = "gold" }),
			P("CrownSpike5", "Crown", -0.08, 0.93, 0.05, 0.025, 0.04, 0.025, { tone = "gold" }),
			P("Shoulder", "Body", 0.2, 0.73, 0, 0.14, 0.06, 0.24, { mirror = true, tone = "gold" }),
			P("Arm", "Body", 0.24, 0.55, 0, 0.07, 0.34, 0.08, M),
			P("Hand", "Arm", 0.25, 0.37, -0.02, 0.08, 0.05, 0.1, { mirror = true, tone = "black" }),
			P("Orb", "HandL", -0.28, 0.4, -0.18, 0.12, 0.08, 0.12, { shape = "Ball", tone = "glow" }),
			P("Weapon", "ArmR", 0.28, 0.5, -0.06, 0.03, 0.8, 0.04, { tone = "black" }),
			P("StaffGem", "Weapon", 0.28, 0.92, -0.06, 0.08, 0.05, 0.08, { tone = "glow" }),
			P("Core", "Body", 0, 0.63, -0.125, 0.1, 0.07, 0.02, GLOW),
		},
	},
}

-- Fallback silhouettes for monsters added later without a rig of their own.
local FALLBACK_BY_BEHAVIOUR: { [string]: string } = {
	melee = "StoneBrute",
	pack = "FrostWolf",
	float = "IceWraith",
	teleport = "VoidShade",
	shield = "VoidKnight",
	boss = "AshenGolem",
}

local function rigFor(def: MonsterDefLite): RigSpec
	local spec = RIGS[def.id] or (def.model and RIGS[def.model])
	if spec then
		return spec
	end
	if def.flying then
		return RIGS.EmberBat
	end
	return RIGS[FALLBACK_BY_BEHAVIOUR[def.behaviour or "melee"] or "StoneBrute"] or RIGS.StoneBrute
end

local function toneColor(tone: string?, main: Color3, glow: Color3): (Color3, Enum.Material?)
	if tone == "glow" then
		return glow, Enum.Material.Neon
	elseif tone == "dark" then
		return main:Lerp(BLACK, 0.35), nil
	elseif tone == "light" then
		return main:Lerp(WHITE, 0.3), nil
	elseif tone == "metal" then
		return METAL:Lerp(main, 0.25), Enum.Material.Metal
	elseif tone == "bone" then
		return BONE, nil
	elseif tone == "black" then
		return DARK, Enum.Material.SmoothPlastic
	elseif tone == "gold" then
		return GOLD, Enum.Material.Metal
	elseif tone == "ice" then
		return ICE, Enum.Material.Ice
	end
	return main, nil
end

local function shapeOf(name: string?): Enum.PartType?
	if name == "Ball" then
		return Enum.PartType.Ball
	elseif name == "Cylinder" then
		return Enum.PartType.Cylinder
	end
	return nil
end

local function motor(part0: BasePart, part1: BasePart)
	local m = Instance.new("Motor6D")
	m.Name = part1.Name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	m.C1 = CFrame.identity
	m.Parent = part0
end

-- Builds one spec side (side: "" for single parts, "L"/"R" for mirrored ones).
local function buildPart(
	spec: PartSpec,
	side: string,
	size: Vector3,
	main: Color3,
	glow: Color3,
	material: Enum.Material
): Part
	local sx = if side == "L" then -1 else 1
	local c, s = spec.c, spec.s
	local pos = Vector3.new(c[1] * size.X * sx, c[2] * size.Y, c[3] * size.Z)
	local partSize = Vector3.new(
		math.max(0.05, s[1] * size.X),
		math.max(0.05, s[2] * size.Y),
		math.max(0.05, s[3] * size.Z)
	)
	local cf = CFrame.new(pos)
	local r = spec.r
	if r then
		cf *= CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2] * sx), math.rad(r[3] * sx))
	end
	local wedge = spec.shape == "Wedge"
	local color, toneMaterial = toneColor(spec.tone, main, glow)
	local p: Part
	if wedge then
		local w = Instance.new("WedgePart")
		w.Name = spec.name .. side
		w.Size = partSize
		w.CFrame = cf
		w.Color = color
		w.Material = toneMaterial or material
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.Massless = true
		w.CastShadow = false
		p = w :: any
	else
		p = newPart(spec.name .. side, partSize, cf, color, toneMaterial or material)
		local shape = shapeOf(spec.shape)
		if shape then
			p.Shape = shape
		end
	end
	if spec.alpha then
		p.Transparency = spec.alpha
	end
	if spec.tone == "glow" then
		p.CastShadow = false
	end
	return p
end

-- A part-based rig for a Config.Monsters row (see the contract at the top).
function Templates.monster(def: MonsterDefLite): Model
	local size = Vector3.new(math.max(0.5, def.size.X), math.max(0.5, def.size.Y), math.max(0.5, def.size.Z))
	local main = def.color
	local _, glow = kindColors(def.kind)
	local spec = rigFor(def)
	local material = spec.material or Enum.Material.SmoothPlastic

	local model = Instance.new("Model")
	model.Name = def.model or def.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = size
	root.CFrame = CFrame.new(0, size.Y / 2, 0)
	root.PivotOffset = CFrame.new(0, -size.Y / 2, 0) -- model pivot = bottom centre
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = false
	root.Anchored = false
	root.CastShadow = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	attach("RootAttachment", root, CFrame.identity)
	attach("Top", root, CFrame.new(0, size.Y / 2 + 1, 0))
	root.Parent = model
	model.PrimaryPart = root

	local built: { [string]: Part } = {}
	local mirrored: { [string]: boolean } = {}
	for _, ps in spec.parts do
		if ps.mirror then
			mirrored[ps.name] = true
		end
	end

	local function parentFor(ps: PartSpec, side: string): BasePart
		local parentName = ps.parent
		if parentName == nil then
			return root
		end
		local direct = built[parentName]
		if direct then
			return direct
		end
		-- a mirrored child follows its own side's limb (Fist on ArmL hangs from ArmL)
		local sided = if mirrored[parentName] then built[parentName .. (if side == "" then "R" else side)] else nil
		return sided or built.Body or root
	end

	for _, ps in spec.parts do
		local sides = if ps.mirror then { "L", "R" } else { "" }
		for _, side in sides do
			local p = buildPart(ps, side, size, main, glow, material)
			local parent = parentFor(ps, side)
			motor(parent, p)
			built[p.Name] = p
			p.Parent = model
		end
	end

	local body = built.Body or root
	attach("Glow", body, CFrame.identity)
	local eyePart = spec.eye and built[spec.eye]
	if eyePart then
		attach("Eye", eyePart, CFrame.new(0, eyePart.Size.Y * 0.1, -eyePart.Size.Z / 2))
	else
		attach("Eye", body, CFrame.new(0, body.Size.Y * 0.3, -body.Size.Z / 2))
	end
	local weaponPart = spec.weapon and built[spec.weapon]
	if weaponPart then
		attach("Weapon", weaponPart, CFrame.identity)
	end
	local shieldPart = spec.shield and built[spec.shield]
	if shieldPart then
		attach("Shield", shieldPart, CFrame.new(0, 0, -shieldPart.Size.Z / 2))
	end

	if def.boss then
		light(body, glow, 1.5, math.clamp(size.Magnitude, 10, 30))
	end

	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	local animator = Instance.new("Animator")
	animator.Parent = controller
	controller.Parent = model

	return model
end

-- Every Motor6D in a rig by name (Body, Head, ArmL...). Part names and joint names match,
-- so use this instead of FindFirstChild(name, true), which may return the part.
function Templates.joints(model: Model): { [string]: Motor6D }
	local out: { [string]: Motor6D } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			out[d.Name] = d
		end
	end
	return out
end

---------------------------------------------------------------------------
-- gear
---------------------------------------------------------------------------

-- Rarer = more glow: Rare+ Neon trim, Epic+ gem, Legendary+ light, Mythic particles.
local function rarityDressing(
	main: BasePart,
	model: Model,
	trimSize: Vector3,
	trimOffset: CFrame,
	glow: Color3,
	rarity: string?
)
	local order = rarityOrder(rarity)
	if order >= 2 then
		local trim = newPart("Trim", trimSize, main.CFrame * trimOffset, glow, Enum.Material.Neon)
		trim.CastShadow = false
		weld(main, trim)
		trim.Parent = model
	end
	if order >= 3 then
		local gem = newPart("Gem", Vector3.new(0.22, 0.22, 0.22), main.CFrame, rarityColor(rarity), Enum.Material.Neon)
		gem.Shape = Enum.PartType.Ball
		gem.CastShadow = false
		weld(main, gem)
		gem.Parent = model
	end
	if order >= 4 then
		light(main, glow, 1 + (order - 4), 6 + (order - 4) * 3)
	end
	if order >= 5 then
		sparkles(main, glow, 8, 0.18)
	end
end

local function sizeScale(rarity: string?): number
	local order = rarityOrder(rarity)
	return if order >= 5 then 1.15 elseif order >= 4 then 1.08 else 1
end

-- One blade (Sword or a Twin Blades half). Grip at the model origin, +Y along the blade,
-- -Z = the edge forward.
local function blade(name: string, length: number, main: Color3, glow: Color3, rarity: string?, origin: CFrame?): Model
	local k = sizeScale(rarity)
	local o = origin or CFrame.identity
	local model = Instance.new("Model")
	model.Name = name
	local handle = newPart("Handle", Vector3.new(0.28, 0.9 * k, 0.28), o, WOOD, Enum.Material.Wood)
	attach("Grip", handle, CFrame.identity)
	local guardY = 0.45 * k + 0.1
	local guard = newPart(
		"Guard",
		Vector3.new(0.3, 0.2, 1.1 * k),
		o * CFrame.new(0, guardY, 0),
		main:Lerp(BLACK, 0.3),
		Enum.Material.Metal
	)
	local bladeLen = length * k
	local bladePart = newPart(
		"Blade",
		Vector3.new(0.12, bladeLen, 0.42 * k),
		o * CFrame.new(0, guardY + 0.1 + bladeLen / 2, 0),
		main:Lerp(WHITE, 0.25),
		Enum.Material.Metal
	)
	attach("TrailTop", bladePart, CFrame.new(0, bladeLen / 2 - 0.1, 0))
	attach("TrailBottom", bladePart, CFrame.new(0, -bladeLen / 2 + 0.2, 0))
	local pommel = newPart(
		"Pommel",
		Vector3.new(0.34, 0.34, 0.34),
		o * CFrame.new(0, -0.45 * k - 0.12, 0),
		main,
		Enum.Material.Metal
	)
	pommel.Shape = Enum.PartType.Ball
	weld(handle, guard)
	weld(handle, bladePart)
	weld(handle, pommel)
	handle.Parent = model
	guard.Parent = model
	bladePart.Parent = model
	pommel.Parent = model
	model.PrimaryPart = handle
	rarityDressing(bladePart, model, Vector3.new(0.14, bladeLen * 0.85, 0.06), CFrame.new(0, 0, -0.2 * k), glow, rarity)
	return model
end

local function axe(main: Color3, glow: Color3, rarity: string?): Model
	local k = sizeScale(rarity)
	local model = Instance.new("Model")
	model.Name = "Axe"
	local handle = newPart(
		"Handle",
		Vector3.new(0.28, 3.2 * k, 0.28),
		CFrame.new(0, 1.0 * k, 0),
		WOOD,
		Enum.Material.Wood
	)
	attach("Grip", handle, CFrame.new(0, -1.0 * k, 0))
	local headY = 2.25 * k
	local head = newPart(
		"Head",
		Vector3.new(0.2, 1.1 * k, 1.0 * k),
		CFrame.new(0, headY, -0.55 * k),
		main:Lerp(WHITE, 0.2),
		Enum.Material.Metal
	)
	attach("TrailTop", head, CFrame.new(0, 0.5 * k, -0.45 * k))
	attach("TrailBottom", head, CFrame.new(0, -0.5 * k, -0.45 * k))
	local back = newPart(
		"Spike",
		Vector3.new(0.2, 0.4 * k, 0.45 * k),
		CFrame.new(0, headY, 0.32 * k),
		main:Lerp(BLACK, 0.3),
		Enum.Material.Metal
	)
	local cap = newPart(
		"Cap",
		Vector3.new(0.38, 0.28, 0.38),
		CFrame.new(0, 2.66 * k, 0),
		main:Lerp(BLACK, 0.3),
		Enum.Material.Metal
	)
	weld(handle, head)
	weld(handle, back)
	weld(handle, cap)
	handle.Parent = model
	head.Parent = model
	back.Parent = model
	cap.Parent = model
	model.PrimaryPart = handle
	rarityDressing(head, model, Vector3.new(0.22, 1.0 * k, 0.1), CFrame.new(0, 0, -0.5 * k), glow, rarity)
	return model
end

local function armor(main: Color3, glow: Color3, rarity: string?): Model
	local model = Instance.new("Model")
	model.Name = "Armor"
	-- sized for an R15 UpperTorso; each piece is welded on its own by Appearance
	local chest = newPart("Chest", Vector3.new(2.15, 1.5, 1.2), CFrame.new(0, 0, 0), main, Enum.Material.Metal)
	attach("BodyFrontAttachment", chest, CFrame.new(0, 0, -0.5))
	chest.Parent = model
	rarityDressing(chest, model, Vector3.new(2.2, 0.16, 1.25), CFrame.new(0, -0.45, 0), glow, rarity)
	for _, side in { "L", "R" } do
		local sx = if side == "L" then -1 else 1
		local shoulder = newPart(
			`Shoulder{side}`,
			Vector3.new(1.0, 0.45, 1.25),
			CFrame.new(1.05 * sx, 0.95, 0) * CFrame.Angles(0, 0, math.rad(-12 * sx)),
			main:Lerp(BLACK, 0.2),
			Enum.Material.Metal
		)
		attach(
			if side == "L" then "LeftShoulderAttachment" else "RightShoulderAttachment",
			shoulder,
			CFrame.new(-0.05 * sx, -0.18, 0)
		)
		if rarityOrder(rarity) >= 2 then
			local rim = newPart(
				`Rim{side}`,
				Vector3.new(1.02, 0.08, 1.27),
				shoulder.CFrame * CFrame.new(0, -0.2, 0),
				glow,
				Enum.Material.Neon
			)
			rim.CastShadow = false
			weld(shoulder, rim)
			rim.Parent = model
		end
		shoulder.Parent = model
	end
	model.PrimaryPart = chest
	return model
end

-- Weapon or armour visuals for Appearance (weapons: Grip, TrailTop, TrailBottom attachments;
-- TwinBlades: sub-models "Left" and "Right"; Armor: parts Chest, ShoulderL, ShoulderR).
function Templates.gear(kind: string, gearType: string, rarity: string?): Model
	local main, glow = kindColors(kind)
	local model: Model
	if gearType == "Axe" then
		model = axe(main, glow, rarity)
	elseif gearType == "TwinBlades" then
		model = Instance.new("Model")
		model.Name = "TwinBlades"
		local right = blade("Right", 2.0, main, glow, rarity, CFrame.new(1, 0, 0))
		local left = blade("Left", 2.0, main, glow, rarity, CFrame.new(-1, 0, 0))
		right.Parent = model
		left.Parent = model
		model.PrimaryPart = right.PrimaryPart
	elseif gearType == "Armor" then
		model = armor(main, glow, rarity)
	else
		model = blade("Sword", 3.0, main, glow, rarity)
	end
	model:SetAttribute("Kind", kind)
	model:SetAttribute("GearType", gearType)
	model:SetAttribute("Rarity", rarity or "Common")
	return model
end

---------------------------------------------------------------------------
-- map props: portal tiers, chests, keys (anchored where they stand, Locked)
---------------------------------------------------------------------------

local function anchoredPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = newPart(name, size, cf, color, material)
	p.Anchored = true
	p.Massless = false
	p.CanCollide = true
	return p
end

-- The portal arch for tier 1-5 (bigger arch, more runes, more glow). Pivot at the bottom
-- centre, the Surface faces -Z. Runes are Neon parts named "Rune" (Plots may tint them).
function Templates.portal(tier: number): Model
	local t = math.clamp(math.floor(tier), 1, 5)
	local s = 1 + 0.15 * (t - 1)
	local gold = (Config.Colors :: any).Gold or GOLD
	local stone = (Config.Colors :: any).Stone or Color3.fromRGB(92, 90, 96)
	local stoneDark = (Config.Colors :: any).StoneDark or Color3.fromRGB(64, 62, 68)
	local model = Instance.new("Model")
	model.Name = `Tier{t}`
	model:SetAttribute("Tier", t)

	local stepH = 0.6
	local pillarH = 18 * s
	local halfGap = 8.5 * s
	local surfaceY = stepH + pillarH / 2
	local function add(p: BasePart)
		p.Parent = model
	end

	add(anchoredPart(
		"Step",
		Vector3.new(22 * s, stepH, 7 * s),
		CFrame.new(0, stepH / 2, 0),
		stoneDark,
		Enum.Material.Slate
	))
	for _, side in { -1, 1 } do
		local name = if side < 0 then "PillarL" else "PillarR"
		local x = halfGap * side
		add(anchoredPart(
			name,
			Vector3.new(3 * s, pillarH, 3 * s),
			CFrame.new(x, stepH + pillarH / 2, 0),
			stone,
			Enum.Material.Slate
		))
		-- runes up the front of each pillar: 2 per tier
		local count = t * 2
		for i = 1, count do
			local y = stepH + pillarH * (i / (count + 1))
			local rune = anchoredPart(
				"Rune",
				Vector3.new(0.9 * s, 0.5 * s, 0.12),
				CFrame.new(x, y, -1.5 * s - 0.06),
				gold,
				Enum.Material.Neon
			)
			rune.CanCollide = false
			rune.CastShadow = false
			add(rune)
		end
		if t >= 4 then
			local spireH = 6 * s
			local spireX = (halfGap + 4 * s) * side
			add(anchoredPart(
				if side < 0 then "SpireL" else "SpireR",
				Vector3.new(1.6 * s, spireH, 1.6 * s),
				CFrame.new(spireX, stepH + spireH / 2, 0),
				stoneDark,
				Enum.Material.Slate
			))
			local tip = anchoredPart(
				"Rune",
				Vector3.new(0.9 * s, 0.9 * s, 0.9 * s),
				CFrame.new(spireX, stepH + spireH + 0.6 * s, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)),
				gold,
				Enum.Material.Neon
			)
			tip.CanCollide = false
			add(tip)
		end
	end
	local lintelY = stepH + pillarH + 1.5 * s
	add(anchoredPart(
		"Lintel",
		Vector3.new(21 * s, 3 * s, 3.4 * s),
		CFrame.new(0, lintelY, 0),
		stone,
		Enum.Material.Slate
	))
	if t >= 2 then
		local key = anchoredPart(
			"Rune",
			Vector3.new(1.4 * s, 1.4 * s, 0.2),
			CFrame.new(0, lintelY, -1.7 * s - 0.1) * CFrame.Angles(0, 0, math.rad(45)),
			gold,
			Enum.Material.Neon
		)
		key.Name = "Keystone"
		key.CanCollide = false
		add(key)
	end
	if t >= 3 then
		for _, side in { -1, 1 } do
			local arch = anchoredPart(
				if side < 0 then "ArchL" else "ArchR",
				Vector3.new(11 * s, 1.6 * s, 3 * s),
				CFrame.new(5 * s * side, lintelY + 2.4 * s, 0) * CFrame.Angles(0, 0, math.rad(-14 * side)),
				stoneDark,
				Enum.Material.Slate
			)
			add(arch)
		end
	end
	if t >= 5 then
		for i = -2, 2 do
			local spike = anchoredPart(
				"Rune",
				Vector3.new(0.6 * s, (2.4 - math.abs(i) * 0.5) * s, 0.6 * s),
				CFrame.new(i * 2.2 * s, lintelY + 4.6 * s - math.abs(i) * 0.6 * s, 0),
				gold,
				Enum.Material.Neon
			)
			spike.Name = "Crown"
			spike.CanCollide = false
			add(spike)
		end
	end

	local surface = anchoredPart(
		"Surface",
		Vector3.new(14 * s, pillarH, 0.4),
		CFrame.new(0, surfaceY, 0),
		Color3.fromRGB(34, 32, 40),
		Enum.Material.SmoothPlastic
	)
	surface.CanCollide = false
	surface.CanQuery = false
	surface.CanTouch = false
	surface.CastShadow = false
	surface:SetAttribute("State", "idle")
	surface.PivotOffset = CFrame.new(0, -surfaceY, 0) -- model pivot = bottom centre
	light(surface, gold, 0.4 + 0.3 * t, 8 + 4 * t)
	attach("Glow", surface, CFrame.identity)
	add(surface)
	model.PrimaryPart = surface
	setLocked(model)
	return model
end

local CHEST_SIZES: { [string]: Vector3 } = {
	normal = Vector3.new(3, 2, 2),
	big = Vector3.new(4, 2.6, 2.6),
	boss = Vector3.new(5, 3.2, 3.2),
}

-- A chest ("normal" | "big" | "boss", any case). Base anchored; Lid on a Motor6D "Lid"
-- hinged at the back (rotate its Transform about X to open). Attachment "Burst" on top.
function Templates.chest(chestKind: string): Model
	local kindKey = string.lower(chestKind)
	local size = CHEST_SIZES[kindKey] or CHEST_SIZES.normal
	local big = kindKey == "big"
	local boss = kindKey == "boss"
	local woodColor = if boss then Color3.fromRGB(40, 30, 44) else WOOD
	local bandColor = if big or boss then GOLD else METAL
	local glowColor = if boss then Color3.fromRGB(255, 200, 80) else GOLD

	local model = Instance.new("Model")
	model.Name = if boss then "Boss" elseif big then "Big" else "Normal"
	local baseH = size.Y * 0.62
	local lidH = size.Y - baseH
	local base = anchoredPart(
		"Base",
		Vector3.new(size.X, baseH, size.Z),
		CFrame.new(0, baseH / 2, 0),
		woodColor,
		Enum.Material.Wood
	)
	base.CanCollide = false
	base.PivotOffset = CFrame.new(0, -baseH / 2, 0)
	local lid = newPart(
		"Lid",
		Vector3.new(size.X, lidH, size.Z),
		CFrame.new(0, baseH + lidH / 2, 0),
		woodColor,
		Enum.Material.Wood
	)
	local hinge = Instance.new("Motor6D")
	hinge.Name = "Lid"
	hinge.Part0 = base
	hinge.Part1 = lid
	hinge.C0 = CFrame.new(0, baseH / 2, size.Z / 2)
	hinge.C1 = CFrame.new(0, -lidH / 2, size.Z / 2)
	hinge.Parent = base
	attach("Burst", lid, CFrame.new(0, lidH / 2 + 0.5, 0))

	local function strap(name: string, x: number, onLid: boolean)
		local host = if onLid then lid else base
		local h = if onLid then lidH else baseH
		local p = newPart(
			name,
			Vector3.new(0.3, h + 0.04, size.Z + 0.06),
			host.CFrame * CFrame.new(x, 0, 0),
			bandColor,
			Enum.Material.Metal
		)
		weld(host, p)
		p.Parent = model
	end
	strap("BandL", -size.X * 0.3, false)
	strap("BandR", size.X * 0.3, false)
	strap("LidBandL", -size.X * 0.3, true)
	strap("LidBandR", size.X * 0.3, true)

	local lock = newPart(
		"Lock",
		Vector3.new(0.5, 0.6, 0.15),
		CFrame.new(0, baseH - 0.3, -size.Z / 2 - 0.07),
		if big or boss then glowColor else GOLD,
		if big or boss then Enum.Material.Neon else Enum.Material.Metal
	)
	weld(base, lock)
	lock.Parent = model
	if big or boss then
		local seam = newPart(
			"Seam",
			Vector3.new(size.X + 0.02, 0.08, size.Z + 0.02),
			CFrame.new(0, baseH, 0),
			glowColor,
			Enum.Material.Neon
		)
		seam.CastShadow = false
		weld(base, seam)
		seam.Parent = model
		light(lock, glowColor, if boss then 2 else 1.2, if boss then 14 else 9)
	end
	if boss then
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local spike = newPart(
				"Spike",
				Vector3.new(0.35, 0.8, 0.35),
				CFrame.new(
					corner[1] * size.X / 2,
					size.Y + 0.2,
					corner[2] * size.Z / 2
				) * CFrame.Angles(0, math.rad(45), 0),
				GOLD,
				Enum.Material.Metal
			)
			weld(lid, spike)
			spike.Parent = model
		end
		sparkles(lock, glowColor, 6, 0.25)
	end
	base.Parent = model
	lid.Parent = model
	model.PrimaryPart = base
	setLocked(model)
	return model
end

-- A key of a kind and key rarity (Common / Rare / Legendary). Shaft anchored (the pivot,
-- centred), bow ring with a gem facing -Z; rarer = more glow.
function Templates.key(kind: string, rarity: string?): Model
	local main, glow = kindColors(kind)
	local keyRow = rarity and (Config.KeyRarities :: any)[rarity]
	local rarityTint = if keyRow then keyRow.color else glow
	local order = if rarity == "Legendary" then 3 elseif rarity == "Rare" then 2 else 1

	local model = Instance.new("Model")
	model.Name = `{kind}Key`
	local shaft = anchoredPart("Shaft", Vector3.new(0.3, 2.2, 0.3), CFrame.identity, main, Enum.Material.Metal)
	shaft.CanCollide = false
	local bow = newPart(
		"Bow",
		Vector3.new(0.3, 1.4, 1.4),
		CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(90), 0),
		main,
		Enum.Material.Metal
	)
	bow.Shape = Enum.PartType.Cylinder
	local gem = newPart("Gem", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 1.6, -0.1), glow, Enum.Material.Neon)
	gem.Shape = Enum.PartType.Ball
	local tooth1 = newPart(
		"Tooth1",
		Vector3.new(0.18, 0.3, 0.55),
		CFrame.new(0, -0.85, -0.35),
		main,
		Enum.Material.Metal
	)
	local tooth2 = newPart(
		"Tooth2",
		Vector3.new(0.18, 0.25, 0.4),
		CFrame.new(0, -0.45, -0.28),
		main,
		Enum.Material.Metal
	)
	for _, p in { bow, gem, tooth1, tooth2 } do
		weld(shaft, p)
		p.Parent = model
	end
	if order >= 2 then
		local ring = newPart(
			"Trim",
			Vector3.new(0.12, 1.6, 1.6),
			CFrame.new(0, 1.6, 0.12) * CFrame.Angles(0, math.rad(90), 0),
			rarityTint,
			Enum.Material.Neon
		)
		ring.Shape = Enum.PartType.Cylinder
		ring.CastShadow = false
		weld(shaft, ring)
		ring.Parent = model
		light(gem, rarityTint, if order >= 3 then 2 else 0.8, if order >= 3 then 10 else 6)
	end
	if order >= 3 then
		sparkles(gem, rarityTint, 10, 0.2)
	end
	attach("Glow", gem, CFrame.identity)
	shaft.Parent = model
	model.PrimaryPart = shaft
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Rarity", rarity or "Common")
	setLocked(model)
	return model
end

-- Ids that have a hand-made silhouette here (the rest use a fallback by behaviour).
function Templates.hasRig(id: string): boolean
	return RIGS[id] ~= nil
end

return Templates
