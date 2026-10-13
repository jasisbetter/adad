--!strict
-- Build: makes the whole map from data. Run it in Edit mode:
--   require(game.ServerStorage.Build:Clone()).run()
-- It rebuilds Workspace.Map and Workspace.Plots from scratch, sets the hub lighting and locks every part it makes.
-- Hand-made models slot in by name: Assets.Props.Prop_<Name> (pivot at the bottom centre, front -Z) and
-- Assets.Portal.Tier1 (see ASSETS.md). With nothing there, grey parts are built.
-- Layout: courtyard (Rift spot) -> 8 plots -> the Config.Areas rings going outward, each split into an inner and an
-- outer band, with a ring wall and Config gates in front of every gated area. Paths run outward through the gates.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local Assets = require(Shared.Assets)
local Templates = require(Shared.Templates)

type Area = Types.Area
type AreaLook = Types.AreaLook

local Build = {}

local STONE = Config.Colors.Stone
local STONE_DARK = Config.Colors.StoneDark
local GOLD = Config.Colors.Gold
local WOOD = Color3.fromRGB(58, 46, 38)
local FLAME = Color3.fromRGB(255, 150, 70)
local LAVA = Color3.fromRGB(255, 96, 24)
local ICE = Color3.fromRGB(175, 215, 240)
local VOID_GLOW = Config.Colors.Void

local GROUND_STEP = 0.05 -- each ground disc sits this much above the next one out (never two tops on one plane)
local PATH_W = 14 -- courtyard -> plot paths
local ROAD_W = 12 -- outward roads through the gates
local LANE_W = 5 -- the outward road narrows where it passes between two plots
local LANE_END = 150
local ROAD_ANGLE = 3 * math.pi / 8 -- first road and gate: between plots 2 and 3, clear of the boards
local WALL_H = 16 -- ring walls between areas
local WALL_T = 4
local SEG_LEN = 48
local GATE_OPEN = 16
local GATE_PILLAR = 4
local GATE_H = 19 -- top of the opening above the road
local OUTER_TINT = 0.12 -- outer band ground is this much darker

local FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

-- per-run state
local made = 0
local discs: { { radius: number, top: number } } = {} -- innermost first
local circles: { { pos: Vector3, radius: number } } = {} -- keep-out spots (spawns, lakes, lava, gates, props)
local roadAngles: { number } = {}
local roadTop = 0.45

local function part(props: { [string]: any }, parent: Instance): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate
	p.Color = STONE
	for k, v in props do
		if k ~= "ClassName" then
			(p :: any)[k] = v
		end
	end
	p.Locked = true
	p.Parent = parent
	made += 1
	return p
end

-- A flat disc whose top sits at `topY`.
local function disc(
	name: string,
	radius: number,
	thickness: number,
	topY: number,
	color: Color3,
	material: Enum.Material,
	parent: Instance,
	at: Vector3?
): BasePart
	local c = at or Vector3.zero
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(c.X, topY - thickness / 2, c.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material,
	}, parent)
end

local function folder(name: string, parent: Instance): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local function dirAt(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

local function flatRadius(pos: Vector3): number
	return math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
end

local function lockAll(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Locked = true
			made += 1
		end
	end
end

local function light(parent: BasePart, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

-- One text SurfaceGui on a face of `host`.
local function textGui(host: BasePart, name: string, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = host
	return label
end

---------------------------------------------------------------------------
-- ring maths (Gates.luau uses the same ring radius formula)
---------------------------------------------------------------------------

-- Radius of the ring wall in front of area i: the middle of the gap before it.
function Build.ringRadius(i: number): number
	local area = Config.Areas[i]
	if i == 1 then
		return area.inner.radius[1] - 10
	end
	return (Config.Areas[i - 1].outer.radius[2] + area.inner.radius[1]) / 2
end

-- Angle (radians, same convention as plotFrame) of gate n of `count`.
function Build.gateAngle(n: number, count: number): number
	return ROAD_ANGLE + (n - 1) / count * math.pi * 2
end

local function groundTop(r: number): number
	for _, d in discs do
		if r <= d.radius then
			return d.top
		end
	end
	return 0
end

local function nearRoad(pos: Vector3, clearance: number): boolean
	for _, a in roadAngles do
		local d = dirAt(a)
		local along = pos.X * d.X + pos.Z * d.Z
		if along > 0 then
			local lateral = math.abs(pos.X * d.Z - pos.Z * d.X)
			local half = (if along < LANE_END then LANE_W else ROAD_W) / 2
			if lateral < half + clearance then
				return true
			end
		end
	end
	return false
end

local function isFree(pos: Vector3, radius: number): boolean
	if nearRoad(pos, radius + 2) then
		return false
	end
	for _, c in circles do
		local dx, dz = c.pos.X - pos.X, c.pos.Z - pos.Z
		local need = c.radius + radius
		if dx * dx + dz * dz < need * need then
			return false
		end
	end
	return true
end

local function claim(pos: Vector3, radius: number)
	table.insert(circles, { pos = pos, radius = radius })
end

-- A free flat spot in the ring r0..r1, or nil after 40 tries.
local function pickSpot(rng: Random, r0: number, r1: number, radius: number): Vector3?
	local lo, hi = r0 + radius, r1 - radius
	if hi <= lo then
		return nil
	end
	for _ = 1, 40 do
		local a = rng:NextNumber() * math.pi * 2
		local pos = dirAt(a) * (lo + rng:NextNumber() * (hi - lo))
		if isFree(pos, radius) then
			claim(pos, radius)
			return pos
		end
	end
	return nil
end

-- Ground CFrame at a flat spot, random yaw, sunk `sink` studs.
local function groundCF(pos: Vector3, rng: Random, sink: number?): CFrame
	local y = groundTop(flatRadius(pos)) - (sink or 0)
	return CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
end

---------------------------------------------------------------------------
-- props (grey fallbacks; a hand-made Assets.Props.<name> model replaces each one)
---------------------------------------------------------------------------

type Grey = (model: Model, cf: CFrame, rng: Random) -> ()

local function prop(name: string, cf: CFrame, parent: Instance, rng: Random, grey: Grey): Model
	local source = Assets.findSource("Props", name)
	if source and source:IsA("Model") then
		local ok, copy = pcall(function()
			return source:Clone()
		end)
		if ok and copy then
			copy.Name = name
			copy:PivotTo(cf)
			lockAll(copy)
			copy.Parent = parent
			return copy
		end
	end
	local model = Instance.new("Model")
	model.Name = name
	grey(model, cf, rng)
	model.WorldPivot = cf
	model.Parent = parent
	return model
end

local function vary(c: Color3, rng: Random, amount: number): Color3
	local k = 1 + (rng:NextNumber() * 2 - 1) * amount
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function greyDeadTree(model: Model, cf: CFrame, rng: Random)
	local h = 8 + rng:NextNumber() * 5
	local trunkCF = cf * CFrame.Angles(rng:NextNumber() * 0.12 - 0.06, 0, rng:NextNumber() * 0.12 - 0.06)
	part({
		Name = "Trunk",
		Size = Vector3.new(1.3, h, 1.3),
		CFrame = trunkCF * CFrame.new(0, h / 2 - 0.6, 0),
		Color = vary(Color3.fromRGB(62, 56, 52), rng, 0.08),
		Material = Enum.Material.Wood,
	}, model)
	local branches = 2 + rng:NextInteger(0, 1)
	for b = 1, branches do
		local len = 3.5 + rng:NextNumber() * 2.5
		local yaw = b / branches * math.pi * 2 + rng:NextNumber()
		local tilt = 0.7 + rng:NextNumber() * 0.35
		part({
			Name = "Branch",
			Size = Vector3.new(0.6, len, 0.6),
			CFrame = trunkCF
				* CFrame.new(0, h * (0.5 + 0.35 * rng:NextNumber()), 0)
				* CFrame.Angles(0, yaw, tilt)
				* CFrame.new(0, len / 2 - 0.3, 0),
			Color = Color3.fromRGB(54, 48, 44),
			Material = Enum.Material.Wood,
		}, model)
	end
end

local function greyRuin(model: Model, cf: CFrame, rng: Random)
	local w, h = 8 + rng:NextNumber() * 4, 4 + rng:NextNumber() * 3
	part({
		Name = "Wall",
		Size = Vector3.new(w, h, 2),
		CFrame = cf * CFrame.new(0, h / 2 - 0.7, 0) * CFrame.Angles(0, 0, rng:NextNumber() * 0.1 - 0.05),
		Color = vary(STONE, rng, 0.08),
	}, model)
	local ch = 6 + rng:NextNumber() * 3
	part({
		Name = "Column",
		Size = Vector3.new(2.2, ch, 2.2),
		CFrame = cf * CFrame.new(w / 2 + 2, ch / 2 - 0.9, 0.4) * CFrame.Angles(0.06, 0.3, 0.04),
		Color = vary(STONE_DARK, rng, 0.08),
	}, model)
	part({
		Name = "Fallen",
		Size = Vector3.new(2.2, 2, 5),
		CFrame = cf * CFrame.new(-w / 2 + 1, 0.55, 3.2) * CFrame.Angles(0.12, 0.6, 0.08),
		Color = vary(STONE, rng, 0.1),
	}, model)
end

local function rockMaker(color: Color3, material: Enum.Material): Grey
	return function(model: Model, cf: CFrame, rng: Random)
		local size = Vector3.new(4 + rng:NextNumber() * 6, 3 + rng:NextNumber() * 6, 4 + rng:NextNumber() * 6)
		part({
			Name = "Rock",
			Size = size,
			CFrame = cf
				* CFrame.new(0, size.Y / 2 - 0.8, 0)
				* CFrame.Angles(rng:NextNumber() * 0.3, 0, rng:NextNumber() * 0.3),
			Color = vary(color, rng, 0.12),
			Material = material,
		}, model)
	end
end

local function greyGeyser(model: Model, cf: CFrame, _rng: Random)
	part({
		Name = "Mound",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.8, 7, 7),
		CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(30, 26, 26),
		Material = Enum.Material.Basalt,
	}, model)
	-- the vent: client effects look for parts named "Geyser"
	local vent = part({
		Name = "Geyser",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2.6, 2.6),
		CFrame = cf * CFrame.new(0, 1.2 + 0.03 - 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = LAVA,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, model)
	light(vent, LAVA, 1.2, 12)
end

local function greyIceSpike(model: Model, cf: CFrame, rng: Random)
	for s = 1, 3 do
		local h = 6 + rng:NextNumber() * 7
		local w = 1.6 + rng:NextNumber() * 0.9
		part({
			Name = "Spike",
			Size = Vector3.new(w, h, w),
			CFrame = cf
				* CFrame.Angles(0, s / 3 * math.pi * 2 + rng:NextNumber() * 0.5, 0.15 + rng:NextNumber() * 0.25)
				* CFrame.new(0, h / 2 - 1, 0)
				* CFrame.Angles(0, math.pi / 4, 0),
			Color = vary(Color3.fromRGB(165, 215, 248), rng, 0.05),
			Material = Enum.Material.Ice,
			Reflectance = 0.1,
		}, model)
	end
end

local function greyIsland(model: Model, cf: CFrame, rng: Random)
	local w, d = 12 + rng:NextNumber() * 6, 10 + rng:NextNumber() * 5
	part({
		Name = "Top",
		Size = Vector3.new(w, 2, d),
		CFrame = cf * CFrame.Angles(rng:NextNumber() * 0.1 - 0.05, 0, rng:NextNumber() * 0.1 - 0.05),
		Color = vary(Color3.fromRGB(48, 36, 66), rng, 0.1),
	}, model)
	part({
		Name = "Underside",
		Size = Vector3.new(w * 0.55, 7, d * 0.55),
		CFrame = cf * CFrame.new(0, -3.6, 0) * CFrame.Angles(0.5, 0.3, 0.45),
		Color = Color3.fromRGB(30, 22, 42),
	}, model)
	part({
		Name = "Crystal",
		Size = Vector3.new(1, 4, 1),
		CFrame = cf * CFrame.new(w * 0.2, 2.6, 0) * CFrame.Angles(0.2, 0.7, 0.15),
		Color = VOID_GLOW,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	}, model)
end

local function greyShard(model: Model, cf: CFrame, rng: Random)
	local h = 3 + rng:NextNumber() * 4
	part({
		Name = "Shard",
		Size = Vector3.new(1.4, h, 1.4),
		CFrame = cf * CFrame.Angles(0.2, 0, 0.25) * CFrame.new(0, h / 2 - 0.8, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Color = VOID_GLOW,
		Material = Enum.Material.Neon,
		CastShadow = false,
	}, model)
end

-- Torch: post, bowl and a Neon "Flame" with a PointLight. Base at `cf` (ground level).
local function torch(cf: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Torch"
	part({
		Name = "Post",
		Size = Vector3.new(0.6, 4.3, 0.6),
		CFrame = cf * CFrame.new(0, 1.85, 0),
		Color = WOOD,
		Material = Enum.Material.Wood,
	}, model)
	part(
		{ Name = "Bowl", Size = Vector3.new(1.6, 0.5, 1.6), CFrame = cf * CFrame.new(0, 4.25, 0), Color = STONE_DARK },
		model
	)
	local flame = part({
		Name = "Flame",
		Size = Vector3.new(0.8, 1.2, 0.8),
		CFrame = cf * CFrame.new(0, 4.85, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Color = FLAME,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, model)
	light(flame, FLAME, 1.4, 16)
	model.WorldPivot = cf
	model.Parent = parent
end

---------------------------------------------------------------------------
-- plots
---------------------------------------------------------------------------

function Build.plotFrame(i: number): CFrame
	local M = Config.Map
	local angle = (i - 1) / M.plotCount * math.pi * 2
	local outward = Vector3.new(math.sin(angle), 0, math.cos(angle))
	local center = outward * M.plotRadius
	return CFrame.lookAt(center, center + outward) -- local -Z points away from the courtyard
end

local function buildPlot(i: number, parent: Instance)
	local M = Config.Map
	local cf = Build.plotFrame(i)
	local half = M.plotSize / 2
	local top = 1.2
	local model = Instance.new("Model")
	model.Name = "Plot" .. i
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Index", i)
	model:SetAttribute("Owner", 0)
	model:SetAttribute("Tier", 1)
	model:SetAttribute("PortalState", "idle")

	part({
		Name = "Platform",
		Size = Vector3.new(M.plotSize.X, top, M.plotSize.Y),
		CFrame = cf * CFrame.new(0, top / 2, 0),
		Color = STONE_DARK,
	}, model)
	-- a lighter fighting floor inset, a little higher so the two tops never overlap
	part({
		Name = "Floor",
		Size = Vector3.new(M.plotSize.X - 6, 0.1, M.plotSize.Y - 6),
		CFrame = cf * CFrame.new(0, top + 0.05, 0),
		Color = STONE,
		Material = Enum.Material.Slate,
	}, model)

	-- the portal arch: a hand-made Tier1 or the grey template, its front (-Z) turned to face the courtyard
	local pz = -M.portalOffset
	local floorTop = top + 0.1
	local portal = Assets.portalTier(1) or Templates.portal(1)
	portal.Name = "Portal"
	lockAll(portal)
	local surface = portal:FindFirstChild("Surface", true)
	if surface then
		surface:SetAttribute("State", "idle")
	end
	portal:PivotTo(cf * CFrame.new(0, floorTop, pz) * CFrame.Angles(0, math.pi, 0))
	portal.Parent = model

	local function marker(name: string, at: CFrame)
		part({
			Name = name,
			Size = Vector3.new(1, 1, 1),
			CFrame = at,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, model)
	end
	marker("PlayerSpawn", cf * CFrame.new(0, floorTop + 3, 2))
	marker("ChestSpot", cf * CFrame.new(0, floorTop, -9))
	marker("MonsterSpawn", cf * CFrame.new(0, floorTop + 3, pz + 2.5))
	-- where the USE KEY prompt sits: in front of the arch, facing it
	marker("PortalFront", cf * CFrame.new(0, floorTop + 3, pz + 7))

	-- name banner at the front, facing the courtyard
	part({
		Name = "BannerPost",
		Size = Vector3.new(0.8, 9, 0.8),
		CFrame = cf * CFrame.new(-half.X + 5, floorTop + 4.5, half.Y - 2),
		Color = STONE_DARK,
	}, model)
	local board = part({
		Name = "Banner",
		Size = Vector3.new(9, 3, 0.4),
		CFrame = cf * CFrame.new(-half.X + 5, floorTop + 7.5, half.Y - 1.4) * CFrame.Angles(0, math.pi, 0),
		Color = Color3.fromRGB(46, 42, 50),
		Material = Enum.Material.SmoothPlastic,
	}, model)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Name"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = FONT
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Text = "Free plot"
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = board

	-- torches beside the arch (clear of the tier 5 spires) and cloth banners on the back corners
	for _, side in { -1, 1 } do
		torch(cf * CFrame.new(side * (half.X - 4), floorTop - 0.2, pz + 4), model)
		local postX, postZ = side * (half.X - 3), -half.Y + 3
		part({
			Name = "ClothPost",
			Size = Vector3.new(0.8, 10.2, 0.8),
			CFrame = cf * CFrame.new(postX, floorTop + 4.9, postZ),
			Color = WOOD,
			Material = Enum.Material.Wood,
		}, model)
		part({
			Name = "Cloth",
			Size = Vector3.new(3, 6, 0.2),
			CFrame = cf * CFrame.new(postX - side * 1.15, floorTop + 6.4, postZ + 0.4),
			Color = Color3.fromRGB(112, 28, 30),
			Material = Enum.Material.Fabric,
			CanCollide = false,
		}, model)
		part({
			Name = "ClothTrim",
			Size = Vector3.new(3, 0.3, 0.26),
			CFrame = cf * CFrame.new(postX - side * 1.15, floorTop + 3.5, postZ + 0.4),
			Color = GOLD,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		}, model)
	end

	-- the soft glowing wall that rises during an opening (off by default)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local h = M.wallHeight
	local wallProps: { [string]: any } = {
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 150, 70),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}
	local function wall(name: string, size: Vector3, at: CFrame)
		local props = table.clone(wallProps)
		props.Name = name
		props.Size = size
		props.CFrame = at
		part(props, walls)
	end
	wall("Front", Vector3.new(M.plotSize.X, h, 1), cf * CFrame.new(0, top + h / 2, half.Y + 0.5))
	wall("Back", Vector3.new(M.plotSize.X, h, 1), cf * CFrame.new(0, top + h / 2, -half.Y - 0.5))
	wall("Left", Vector3.new(1, h, M.plotSize.Y + 2), cf * CFrame.new(-half.X - 0.5, top + h / 2, 0))
	wall("Right", Vector3.new(1, h, M.plotSize.Y + 2), cf * CFrame.new(half.X + 0.5, top + h / 2, 0))
	walls.Parent = model

	model.WorldPivot = cf
	model.Parent = parent
end

---------------------------------------------------------------------------
-- ground, courtyard, paths
---------------------------------------------------------------------------

local function buildGround(map: Folder): number
	local M = Config.Map
	local areas = Config.Areas
	table.clear(discs)
	-- outermost first: each disc sits GROUND_STEP above the one outside it
	local k = 0
	for i = #areas, 1, -1 do
		local area = areas[i]
		local areaFolder = folder(area.id, map)
		local look = area.look
		local outerR = if i == #areas then M.worldRadius else Build.ringRadius(i + 1)
		local outerTop = k * GROUND_STEP
		disc(
			"GroundOuter",
			outerR,
			if k == 0 then 4 else 1,
			outerTop,
			look.ground:Lerp(Color3.new(0, 0, 0), OUTER_TINT),
			look.groundMaterial,
			areaFolder
		)
		table.insert(discs, 1, { radius = outerR, top = outerTop })
		k += 1
		local innerTop = k * GROUND_STEP
		disc("GroundInner", area.inner.radius[2], 1, innerTop, look.ground, look.groundMaterial, areaFolder)
		table.insert(discs, 1, { radius = area.inner.radius[2], top = innerTop })
		k += 1
	end
	local hubTop = k * GROUND_STEP
	local hub = folder("Hub", map)
	local hubR = if #areas > 0 then areas[1].inner.radius[1] else M.worldRadius
	disc("HubGround", hubR, 1, hubTop, Config.HubLook.ground, Config.HubLook.groundMaterial, hub)
	table.insert(discs, 1, { radius = hubR, top = hubTop })
	return hubTop
end

local function buildCourtyard(map: Folder, hubTop: number): number
	local M = Config.Map
	local hub = folder("Hub", map)
	local courtTop = hubTop + 0.5
	disc("Courtyard", M.courtyardRadius, 1, courtTop, STONE, Enum.Material.Slate, hub)
	local c = M.riftCenter
	disc("RiftSpot", 10, 0.3, courtTop + 0.04, STONE_DARK, Enum.Material.Slate, hub, c)

	-- the rune circle where the Server Rift opens
	local runes = folder("RuneCircle", hub)
	local function ring(radius: number, count: number, topY: number, size: Vector3)
		for n = 1, count do
			local a = (n - 0.5) / count * math.pi * 2
			local pos = c + dirAt(a) * radius
			part({
				Name = "Rune",
				Size = size,
				CFrame = CFrame.lookAt(
					Vector3.new(pos.X, topY - size.Y / 2, pos.Z),
					Vector3.new(c.X, topY - size.Y / 2, c.Z)
				),
				Color = GOLD,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			}, runes)
		end
	end
	ring(M.riftRadius, 24, courtTop + 0.04, Vector3.new(2.6, 0.1, 1.1))
	ring(7, 8, courtTop + 0.08, Vector3.new(1.6, 0.1, 0.8))

	-- torches beside each outward road where it leaves the courtyard
	local torches = folder("Torches", hub)
	for _, a in roadAngles do
		for _, side in { -1, 1 } do
			local pos = dirAt(a + side * 0.105) * (M.courtyardRadius - 1.6)
			torch(CFrame.new(pos.X, courtTop - 0.2, pos.Z), torches)
		end
	end
	return courtTop
end

local function strip(
	name: string,
	from: Vector3,
	to: Vector3,
	width: number,
	topY: number,
	thickness: number,
	props: { [string]: any },
	parent: Instance
)
	local mid = (from + to) / 2
	local len = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local at = Vector3.new(mid.X, topY - thickness / 2, mid.Z)
	local p = table.clone(props)
	p.Name = name
	p.Size = Vector3.new(width, thickness, len)
	p.CFrame = CFrame.lookAt(at, Vector3.new(to.X, at.Y, to.Z))
	return part(p, parent)
end

local function buildPaths(map: Folder)
	local M = Config.Map
	local paths = folder("Paths", map)
	local look: { [string]: any } = { Color = STONE, Material = Enum.Material.Slate }
	-- courtyard to the front of each plot
	for i = 1, M.plotCount do
		local outward = Build.plotFrame(i).LookVector
		strip(
			`Path{i}`,
			outward * (M.courtyardRadius - 2),
			outward * (M.plotRadius - M.plotSize.Y / 2 + 1),
			PATH_W,
			roadTop,
			1,
			look,
			paths
		)
	end
	-- outward roads through the gates: a narrow lane between the plots, then the full road
	local last = Config.Areas[#Config.Areas]
	local roadEnd = if last then last.outer.radius[2] else M.worldRadius - 20
	for n, a in roadAngles do
		local d = dirAt(a)
		strip(`Lane{n}`, d * (M.courtyardRadius - 2), d * (LANE_END + 1), LANE_W, roadTop, 1, look, paths)
		strip(`Road{n}`, d * LANE_END, d * roadEnd, ROAD_W, roadTop, 1, look, paths)
	end
end

local function buildBoards(map: Folder, hubTop: number)
	local M = Config.Map
	local boards = folder("Boards", map)
	local titles = { Wave = "HIGHEST WAVE", Pot = "BIGGEST POT" }
	for _, row in M.boards do
		local pos = M.riftCenter + dirAt(row.angle) * (M.courtyardRadius + 3)
		local base =
			CFrame.lookAt(Vector3.new(pos.X, hubTop, pos.Z), Vector3.new(M.riftCenter.X, hubTop, M.riftCenter.Z))
		local w, h = 14, 10
		local board = part({
			Name = `Board_{row.id}`,
			Size = Vector3.new(w, h, 0.8),
			CFrame = base * CFrame.new(0, 3 + h / 2, 0),
			Color = Config.Colors.Panel,
			Material = Enum.Material.SmoothPlastic,
		}, boards)
		for _, side in { -1, 1 } do
			part({
				Name = "Post",
				Size = Vector3.new(0.9, 3 + h + 0.6, 0.9),
				CFrame = base * CFrame.new(side * (w / 2 + 0.35), (3 + h + 0.6) / 2 - 0.5, 0),
				Color = STONE_DARK,
			}, boards)
		end
		part({
			Name = "Cap",
			Size = Vector3.new(w + 2.4, 0.6, 1.4),
			CFrame = base * CFrame.new(0, 3 + h + 0.3, 0),
			Color = GOLD,
			Material = Enum.Material.Metal,
		}, boards)

		local gui = Instance.new("SurfaceGui")
		gui.Name = "Rows"
		gui.Face = Enum.NormalId.Front -- Front (-Z) looks at the courtyard centre
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 36
		gui.MaxDistance = 200
		gui.LightInfluence = 0
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromScale(0.05, 0.02)
		title.Size = UDim2.fromScale(0.9, 0.14)
		title.FontFace = FONT
		title.TextScaled = true
		title.TextColor3 = GOLD
		title.Text = (titles :: any)[row.id] or string.upper(row.id)
		title.Parent = gui
		for r = 1, 10 do
			local line = Instance.new("TextLabel")
			line.Name = `Row{r}`
			line.BackgroundTransparency = 1
			line.Position = UDim2.fromScale(0.06, 0.18 + (r - 1) * 0.08)
			line.Size = UDim2.fromScale(0.88, 0.075)
			line.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)
			line.TextScaled = true
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.TextColor3 = Config.Colors.White
			line.Text = `{r}.  ---`
			line.Parent = gui
		end
		gui.Parent = board
	end
end

---------------------------------------------------------------------------
-- ring walls and gates
---------------------------------------------------------------------------

local function wallLook(style: string, rng: Random): (Color3, Enum.Material, number, number)
	-- color, material, transparency, height
	if style == "ice" then
		return vary(Color3.fromRGB(165, 205, 235), rng, 0.04),
			Enum.Material.Glacier,
			0,
			WALL_H + rng:NextNumber() * 2 - 1
	elseif style == "void" then
		return vary(Color3.fromRGB(44, 26, 70), rng, 0.08), Enum.Material.Glass, 0.15, WALL_H
	end
	return vary(Color3.fromRGB(88, 80, 74), rng, 0.1), Enum.Material.Slate, 0, WALL_H + rng:NextNumber() * 3.5 - 2.5
end

local function buildGate(area: Area, n: number, angle: number, radius: number, rng: Random, parent: Instance)
	local gate = area.gate :: { style: string, count: number }
	local d = dirAt(angle)
	local pos = d * radius
	local cf = CFrame.lookAt(Vector3.new(pos.X, roadTop, pos.Z), Vector3.new(pos.X, roadTop, pos.Z) + d) -- -Z outward
	local model = Instance.new("Model")
	model.Name = `Gate_{area.id}_{n}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Area", area.id)
	model:SetAttribute("PortalLevel", area.portalLevel)
	model:SetAttribute("Style", gate.style)

	local frameColor = if gate.style == "void" then Color3.fromRGB(34, 24, 48) else STONE_DARK
	local pillarH = GATE_H + 1.5
	for _, side in { -1, 1 } do
		part({
			Name = if side < 0 then "PillarL" else "PillarR",
			Size = Vector3.new(GATE_PILLAR, pillarH, WALL_T + 2),
			CFrame = cf * CFrame.new(side * (GATE_OPEN + GATE_PILLAR) / 2, pillarH / 2 - 1.5, 0),
			Color = frameColor,
		}, model)
	end
	local lintelW, lintelD = GATE_OPEN + GATE_PILLAR * 2 + 1, WALL_T + 2.4
	part({
		Name = "Lintel",
		Size = Vector3.new(lintelW, 3, lintelD),
		CFrame = cf * CFrame.new(0, GATE_H + 1.5, 0),
		Color = frameColor,
	}, model)
	-- the sign sticks out of the lintel by 0.03 on both faces
	local label = part({
		Name = "Label",
		Size = Vector3.new(14, 2.2, lintelD + 0.06),
		CFrame = cf * CFrame.new(0, GATE_H + 1.5, 0),
		Color = Config.Colors.Ink,
		Material = Enum.Material.SmoothPlastic,
	}, model)
	local text = `Portal level {area.portalLevel}`
	textGui(label, "Front", Enum.NormalId.Front, text, GOLD)
	textGui(label, "Back", Enum.NormalId.Back, text, GOLD)

	-- the thing that blocks; the Zones controller turns its collision off locally for unlocked players
	part({
		Name = "Barrier",
		Size = Vector3.new(GATE_OPEN + 0.4, GATE_H + 1.5, 1.5),
		CFrame = cf * CFrame.new(0, (GATE_H + 1.5) / 2 - 1.5, 0),
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, model)

	-- style props the client animates when the gate opens: Chunk (crumble), Pane (shatter), Veil (fade)
	local cosmetic = { CanCollide = false, CanQuery = false, CanTouch = false }
	if gate.style == "ice" then
		for k, x in { -5.4, 0, 5.4 } do
			part({
				Name = "Pane",
				Size = Vector3.new(5.8, GATE_H - 1, 0.8),
				CFrame = cf
					* CFrame.new(x, (GATE_H - 1) / 2 - 0.6, (k - 2) * 0.2)
					* CFrame.Angles(0, rng:NextNumber() * 0.1 - 0.05, 0),
				Color = vary(ICE, rng, 0.04),
				Material = Enum.Material.Ice,
				Transparency = 0.2,
				Reflectance = 0.1,
				CanCollide = cosmetic.CanCollide,
				CanQuery = cosmetic.CanQuery,
				CanTouch = cosmetic.CanTouch,
			}, model)
		end
	elseif gate.style == "void" then
		local veil = part({
			Name = "Veil",
			Size = Vector3.new(GATE_OPEN + 0.4, GATE_H - 0.4, 0.5),
			CFrame = cf * CFrame.new(0, (GATE_H - 0.4) / 2 - 1, 0),
			Color = VOID_GLOW,
			Material = Enum.Material.ForceField,
			CanCollide = cosmetic.CanCollide,
			CanQuery = cosmetic.CanQuery,
			CanTouch = cosmetic.CanTouch,
			CastShadow = false,
		}, model)
		light(veil, VOID_GLOW, 1.2, 18)
	else
		for row, y in { 2.6, 7.8, 13 } do
			for _, x in { -5.4, 0, 5.4 } do
				local s = 5.2 + rng:NextNumber() * 0.8 - row * 0.15
				part({
					Name = "Chunk",
					Size = Vector3.new(s, s, s * 0.9),
					CFrame = cf
						* CFrame.new(x + rng:NextNumber() * 0.4 - 0.2, y, rng:NextNumber() * 0.6 - 0.3)
						* CFrame.Angles(
							rng:NextNumber() * 0.4 - 0.2,
							rng:NextNumber() * 0.4 - 0.2,
							rng:NextNumber() * 0.4 - 0.2
						),
					Color = vary(Color3.fromRGB(96, 86, 78), rng, 0.12),
					CanCollide = cosmetic.CanCollide,
					CanQuery = cosmetic.CanQuery,
					CanTouch = cosmetic.CanTouch,
				}, model)
			end
		end
	end
	model.WorldPivot = cf
	model.Parent = parent
	claim(pos, 26)
	return model
end

local function buildRings(map: Folder, rng: Random): number
	local gates = folder("Gates", map)
	local wallsRoot = folder("Walls", map)
	local count = 0
	for i, area in Config.Areas do
		local gate = area.gate
		if not gate or gate.count < 1 then
			continue
		end
		local R = Build.ringRadius(i)
		local walls = folder(area.id, wallsRoot)
		local halfAng = (GATE_OPEN / 2 + GATE_PILLAR / 2) / R -- wall ends stop inside the gate pillars
		for n = 1, gate.count do
			local a = Build.gateAngle(n, gate.count)
			buildGate(area, n, a, R, rng, gates)
			count += 1
			-- the wall arc from this gate to the next one
			local a0 = a + halfAng
			local a1 = Build.gateAngle(n + 1, gate.count) - halfAng
			local segs = math.max(1, math.ceil((a1 - a0) * R / SEG_LEN))
			local step = (a1 - a0) / segs
			for s = 1, segs do
				local mid = a0 + (s - 0.5) * step
				local chord = 2 * R * math.sin(step / 2)
				local center = dirAt(mid) * (R * math.cos(step / 2))
				local color, material, transparency, h = wallLook(gate.style, rng)
				part({
					Name = "Wall",
					Size = Vector3.new(chord + 0.6, h, WALL_T), -- 0.3 overlap each end, same look
					CFrame = CFrame.lookAt(
						Vector3.new(center.X, -1 + h / 2, center.Z),
						Vector3.new(center.X, -1 + h / 2, center.Z) + dirAt(mid)
					),
					Color = color,
					Material = material,
					Transparency = transparency,
				}, walls)
			end
		end
	end
	return count
end

---------------------------------------------------------------------------
-- area dressing
---------------------------------------------------------------------------

local function bandRange(area: Area, band: string): (number, number)
	local b = if band == "inner" then area.inner else area.outer
	return b.radius[1], b.radius[2]
end

-- Lava arcs (Neon river on a CrackedLava bank) inside one band, plus a pool at each end.
local function buildLava(area: Area, band: string, parent: Instance, rng: Random)
	local r0, r1 = bandRange(area, band)
	local R = (r0 + r1) / 2
	local amp = math.min(8, (r1 - r0) / 2 - 14)
	local phase = rng:NextNumber() * math.pi * 2
	local function pointAt(a: number): Vector3
		return dirAt(a) * (R + amp * math.sin(a * 6 + phase))
	end
	local bank: { [string]: any } = { Color = Color3.fromRGB(70, 30, 20), Material = Enum.Material.CrackedLava }
	local river: { [string]: any } = { Color = LAVA, Material = Enum.Material.Neon, CastShadow = false }
	local pool: { [string]: any } = { Color = LAVA, Material = Enum.Material.Neon, CastShadow = false }
	local base = rng:NextNumber() * math.pi * 2
	for arc = 1, 2 do
		local a0 = base + (arc - 1) * math.pi + rng:NextNumber() * 0.3
		local span = 1.5 + rng:NextNumber() * 0.4
		local segs = math.ceil(span * R / 36)
		local step = span / segs
		for s = 1, segs do
			local p0, p1 = pointAt(a0 + (s - 1) * step), pointAt(a0 + s * step)
			local top = groundTop(flatRadius(p0))
			local dir = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z).Unit
			-- extend each piece 0.5 at both ends so the joints overlap (same look)
			strip("LavaBank", p0 - dir * 0.5, p1 + dir * 0.5, 10, top + 0.02, 0.4, bank, parent)
			strip("Lava", p0 - dir * 0.5, p1 + dir * 0.5, 6, top + 0.05, 0.4, river, parent)
			for _, t in { 0, 1 / 3, 2 / 3 } do
				claim(p0:Lerp(p1, t), 9)
			end
		end
		for _, a in { a0, a0 + span } do
			local p = pointAt(a)
			local top = groundTop(flatRadius(p))
			local props = table.clone(pool)
			props.Name = "LavaPool"
			props.Shape = Enum.PartType.Cylinder
			props.Size = Vector3.new(0.4, 11, 11)
			props.CFrame = CFrame.new(p.X, top + 0.05 - 0.2, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
			local poolPart = part(props, parent)
			light(poolPart, LAVA, 1, 14)
			claim(p, 10)
		end
	end
end

-- A frozen lake of overlapping ice discs (same look, so their shared tops never flicker).
local function buildLake(area: Area, band: string, size: number, parent: Instance, rng: Random)
	local r0, r1 = bandRange(area, band)
	local center = pickSpot(rng, r0, r1, size * 1.7)
	if not center then
		return
	end
	local top = groundTop(flatRadius(center)) + 0.03
	local lakeFolder = folder("FrozenLake", parent)
	disc("Ice", size, 0.4, top, ICE, Enum.Material.Ice, lakeFolder, center)
	for k = 1, 2 do
		local a = rng:NextNumber() * math.pi * 2 + k * math.pi
		local off = dirAt(a) * (size * 0.7)
		disc("Ice", size * (0.55 + rng:NextNumber() * 0.15), 0.4, top, ICE, Enum.Material.Ice, lakeFolder, center + off)
	end
end

local function scatter(
	name: string,
	count: number,
	area: Area,
	band: string,
	radius: number,
	parent: Instance,
	rng: Random,
	grey: Grey,
	sink: number?
)
	local r0, r1 = bandRange(area, band)
	for _ = 1, count do
		local pos = pickSpot(rng, r0, r1, radius)
		if pos then
			prop(name, groundCF(pos, rng, sink), parent, rng, grey)
		end
	end
end

local function buildVoidSky(area: Area, band: string, parent: Instance, rng: Random)
	local r0, r1 = bandRange(area, band)
	local floating = folder("Floating", parent) -- floats on purpose
	for _ = 1, 7 do
		local a = rng:NextNumber() * math.pi * 2
		local r = r0 + 12 + rng:NextNumber() * (r1 - r0 - 24)
		local pos = dirAt(a) * r
		local cf = CFrame.new(pos.X, groundTop(r) + 18 + rng:NextNumber() * 34, pos.Z)
			* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
		prop("Prop_Island", cf, floating, rng, greyIsland)
	end
	for _ = 1, 25 do
		local a = rng:NextNumber() * math.pi * 2
		local r = r0 + rng:NextNumber() * (r1 - r0)
		local pos = dirAt(a) * r
		local s = 0.4 + rng:NextNumber() * 0.5
		part({
			Name = "Speck",
			Size = Vector3.new(s, s, s),
			CFrame = CFrame.new(pos.X, groundTop(r) + 8 + rng:NextNumber() * 70, pos.Z)
				* CFrame.Angles(0.6, rng:NextNumber() * 6, 0.6),
			Color = if rng:NextNumber() < 0.6 then Color3.fromRGB(235, 225, 255) else VOID_GLOW,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, floating)
	end
end

-- Monster spawn points from the area data (attributes Area, Band, Monster), types mixed around the ring.
local function buildSpawns(spawns: Folder, rng: Random): number
	local M = Config.Map
	local count = 0
	for _, area in Config.Areas do
		for _, bandName in { "inner", "outer" } do
			local band = if bandName == "inner" then area.inner else area.outer
			local list = {}
			for monsterId, n in band.monsters do
				for _ = 1, n do
					table.insert(list, monsterId)
				end
			end
			table.sort(list)
			local total = #list
			local offset = if bandName == "inner" then math.pi / M.plotCount else 0
			for k, monsterId in list do
				local slot = ((k - 1) * 5) % total
				local a = offset + slot / total * math.pi * 2
				local r0, r1 = band.radius[1] + 6, band.radius[2] - 6
				local pos = dirAt(a) * (r0 + rng:NextNumber() * (r1 - r0))
				for _ = 1, 16 do
					if isFree(pos, 5) then
						break
					end
					pos = dirAt(a + rng:NextNumber() * 0.2 - 0.1) * (r0 + rng:NextNumber() * (r1 - r0))
				end
				claim(pos, 6)
				local y = groundTop(flatRadius(pos)) + 0.2
				local p = part({
					Name = "Spawn",
					Size = Vector3.new(2, 0.2, 2),
					CFrame = CFrame.new(pos.X, y, pos.Z),
					Transparency = 1,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
				}, spawns)
				p:SetAttribute("Area", area.id)
				p:SetAttribute("Band", bandName)
				p:SetAttribute("Monster", monsterId)
				count += 1
			end
		end
	end
	return count
end

-- Big keep-out features first (so spawns avoid them), then spawns, then props around both.
local function buildFeatures(map: Folder, rng: Random)
	for _, area in Config.Areas do
		local areaFolder = folder(area.id, map)
		if area.props == "lava" then
			local lava = folder("Lava", areaFolder)
			buildLava(area, "inner", lava, rng)
			buildLava(area, "outer", lava, rng)
		elseif area.props == "ice" then
			buildLake(area, "inner", 22, areaFolder, rng)
			buildLake(area, "outer", 15, areaFolder, rng)
		end
	end
end

local function buildProps(map: Folder, rng: Random)
	for _, area in Config.Areas do
		local areaFolder = folder(area.id, map)
		local props = folder("Props", areaFolder)
		for _, band in { "inner", "outer" } do
			if area.props == "ruins" then
				scatter("Prop_DeadTree", 9, area, band, 4, props, rng, greyDeadTree)
				scatter("Prop_Ruin", 5, area, band, 8, props, rng, greyRuin)
				scatter(
					"Prop_Rock",
					7,
					area,
					band,
					5,
					props,
					rng,
					rockMaker(Color3.fromRGB(88, 84, 80), Enum.Material.Slate)
				)
			elseif area.props == "lava" then
				scatter("Prop_Geyser", 5, area, band, 6, props, rng, greyGeyser)
				scatter(
					"Prop_Rock",
					6,
					area,
					band,
					5,
					props,
					rng,
					rockMaker(Color3.fromRGB(28, 24, 24), Enum.Material.Basalt)
				)
			elseif area.props == "ice" then
				scatter("Prop_IceSpike", 9, area, band, 5, props, rng, greyIceSpike)
				scatter(
					"Prop_Rock",
					4,
					area,
					band,
					5,
					props,
					rng,
					rockMaker(Color3.fromRGB(200, 214, 230), Enum.Material.Glacier)
				)
			elseif area.props == "islands" then
				buildVoidSky(area, band, areaFolder, rng)
				scatter("Prop_Shard", 6, area, band, 3, props, rng, greyShard)
			else
				scatter("Prop_Rock", 8, area, band, 5, props, rng, rockMaker(STONE, Enum.Material.Slate))
			end
		end
	end
end

local function buildEdge(map: Folder)
	local M = Config.Map
	local edge = folder("Edge", map)
	local segments = 36
	local r = M.worldRadius - 4
	local segLen = 2 * math.pi * r / segments + 1
	for s = 1, segments do
		local a = (s - 0.5) / segments * math.pi * 2
		local pos = dirAt(a) * r
		local look = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		part({
			Name = "Rim",
			Size = Vector3.new(segLen, 7, 4),
			CFrame = look * CFrame.new(0, 3.5, 0),
			Color = STONE_DARK,
		}, edge)
		part({
			Name = "MapEdge",
			Size = Vector3.new(segLen, 60, 2),
			CFrame = look * CFrame.new(0, 37, 1),
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
		}, edge)
	end
end

---------------------------------------------------------------------------
-- lighting
---------------------------------------------------------------------------

local function effect(className: string, name: string): Instance
	local found = Lighting:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	local other = Lighting:FindFirstChildOfClass(className :: any)
	if other then
		other.Name = name
		return other
	end
	local e = Instance.new(className :: any)
	e.Name = name
	e.Parent = Lighting
	return e
end

local function applyLighting(look: AreaLook)
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	pcall(function()
		(Lighting :: any).LightingStyle = (Enum :: any).LightingStyle.Realistic
	end)
	Lighting.ClockTime = look.clock
	Lighting.Brightness = 2
	Lighting.Ambient = look.ambient
	Lighting.OutdoorAmbient = look.ambient:Lerp(Color3.new(1, 1, 1), 0.25)
	Lighting.GlobalShadows = true

	local atmosphere = effect("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Color = look.fog
	atmosphere.Density = look.fogDensity
	atmosphere.Haze = look.haze
	atmosphere.Glare = look.glare
	atmosphere.Decay = look.decay
	atmosphere.Offset = 0.1

	local bloom = effect("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = look.bloom
	bloom.Size = 24
	bloom.Threshold = 1.4

	local cc = effect("ColorCorrectionEffect", "ColorCorrection") :: ColorCorrectionEffect
	cc.TintColor = look.cc.tint
	cc.Saturation = look.cc.saturation
	cc.Contrast = look.cc.contrast
	cc.Brightness = look.cc.brightness

	local sky = effect("Sky", "Sky") :: Sky
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
end

---------------------------------------------------------------------------
-- run
---------------------------------------------------------------------------

function Build.run(): string
	for _, name in { "Map", "Plots", "Baseplate" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	made = 0
	table.clear(circles)
	table.clear(roadAngles)

	local M = Config.Map
	local rng = Random.new(1234)
	local map = Instance.new("Folder")
	map.Name = "Map"

	-- roads follow the gates of the first gated ring (4 by default)
	local roadCount = 4
	for _, area in Config.Areas do
		if area.gate and area.gate.count > 0 then
			roadCount = area.gate.count
			break
		end
	end
	for n = 1, roadCount do
		table.insert(roadAngles, Build.gateAngle(n, roadCount))
	end

	local hubTop = buildGround(map)
	roadTop = hubTop + GROUND_STEP
	local courtTop = buildCourtyard(map, hubTop)
	buildPaths(map)
	buildBoards(map, hubTop)
	local gateCount = buildRings(map, rng)
	buildFeatures(map, rng)
	local spawns = folder("MonsterSpawns", map)
	local spawnCount = buildSpawns(spawns, rng)
	buildProps(map, rng)
	buildEdge(map)
	map.Parent = Workspace

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	for i = 1, M.plotCount do
		buildPlot(i, plots)
	end
	plots.Parent = Workspace

	-- the default spawn sits in the courtyard; Plots moves players to their own plot at once
	local spawnPart = Workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawnPart then
		local s = Instance.new("SpawnLocation")
		s.Name = "SpawnLocation"
		s.Anchored = true
		s.Parent = Workspace
		spawnPart = s
	end
	if spawnPart then
		spawnPart.Size = Vector3.new(6, 1, 6)
		spawnPart.CFrame = CFrame.new(M.riftCenter.X, courtTop + 0.5, M.riftCenter.Z)
		spawnPart.Anchored = true
		spawnPart.Transparency = 1
		spawnPart.CanCollide = false
		spawnPart.CanQuery = false
		spawnPart.Duration = 0
		spawnPart.Neutral = true
		spawnPart.AllowTeamChangeOnTouch = false
		local decal = spawnPart:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		spawnPart.Locked = true
	end

	applyLighting(Config.HubLook)
	pcall(function()
		Workspace.StreamingEnabled = true -- only settable in Edit mode
	end)

	local parts = 0
	for _, root in { map, plots } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
	end
	return string.format(
		"built: %d plots, %d areas, %d gates, %d spawns, %d parts (%d made)",
		M.plotCount,
		#Config.Areas,
		gateCount,
		spawnCount,
		parts,
		made
	)
end

return Build
