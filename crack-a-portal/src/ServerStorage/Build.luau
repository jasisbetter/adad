--!strict
-- Build: makes the grey-test map from data. Run it in Edit mode:
--   require(game.ServerStorage.Build:Clone()).run()
-- It rebuilds Workspace.Map and Workspace.Plots from scratch and locks every part it makes.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Build = {}

local STONE = Color3.fromRGB(92, 90, 96)
local STONE_DARK = Color3.fromRGB(64, 62, 68)
local ASH = Color3.fromRGB(118, 114, 110)

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
	return p
end

-- A flat disc whose top sits at `topY`.
local function disc(name: string, radius: number, thickness: number, topY: number, color: Color3, material: Enum.Material, parent: Instance)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(0, topY - thickness / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material,
	}, parent)
end

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

	part({ Name = "Platform", Size = Vector3.new(M.plotSize.X, top, M.plotSize.Y), CFrame = cf * CFrame.new(0, top / 2, 0), Color = STONE_DARK }, model)
	-- a lighter fighting floor inset, a little higher so the two tops never overlap
	part({ Name = "Floor", Size = Vector3.new(M.plotSize.X - 6, 0.1, M.plotSize.Y - 6), CFrame = cf * CFrame.new(0, top + 0.05, 0), Color = STONE, Material = Enum.Material.Slate }, model)

	local portal = Instance.new("Model")
	portal.Name = "Portal"
	local pz = -M.portalOffset
	local floorTop = top + 0.1
	part({ Name = "Step", Size = Vector3.new(22, 0.6, 7), CFrame = cf * CFrame.new(0, floorTop + 0.3, pz), Color = STONE_DARK }, portal)
	part({ Name = "PillarL", Size = Vector3.new(3, 18, 3), CFrame = cf * CFrame.new(-8.5, floorTop + 0.6 + 9, pz), Color = STONE }, portal)
	part({ Name = "PillarR", Size = Vector3.new(3, 18, 3), CFrame = cf * CFrame.new(8.5, floorTop + 0.6 + 9, pz), Color = STONE }, portal)
	part({ Name = "Lintel", Size = Vector3.new(21, 3, 3.4), CFrame = cf * CFrame.new(0, floorTop + 0.6 + 18 + 1.5, pz), Color = STONE }, portal)
	local surface = part({
		Name = "Surface",
		Size = Vector3.new(14, 18, 0.4),
		CFrame = cf * CFrame.new(0, floorTop + 0.6 + 9, pz),
		Color = Color3.fromRGB(34, 32, 40),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, portal)
	surface:SetAttribute("State", "idle")
	portal.PrimaryPart = surface
	portal.Parent = model

	local function marker(name: string, at: CFrame)
		part({ Name = name, Size = Vector3.new(1, 1, 1), CFrame = at, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, model)
	end
	marker("PlayerSpawn", cf * CFrame.new(0, floorTop + 3, 2))
	marker("ChestSpot", cf * CFrame.new(0, floorTop, -9))
	marker("MonsterSpawn", cf * CFrame.new(0, floorTop + 3, pz + 2.5))

	-- name banner at the front, facing the courtyard
	local post = part({ Name = "BannerPost", Size = Vector3.new(0.8, 9, 0.8), CFrame = cf * CFrame.new(-half.X + 5, floorTop + 4.5, half.Y - 2), Color = STONE_DARK }, model)
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
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Config.Colors.Gold
	label.Text = "Free plot"
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = board
	local _ = post

	-- the soft glowing wall that rises during an opening (off by default)
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local h = M.wallHeight
	local wallProps = {
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

	model.Parent = parent
end

function Build.run(): string
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local oldPlots = Workspace:FindFirstChild("Plots")
	if oldPlots then
		oldPlots:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local M = Config.Map
	local map = Instance.new("Folder")
	map.Name = "Map"

	disc("Ground", M.worldRadius, 4, 0, ASH, Enum.Material.Ground, map)
	disc("InnerGround", 168, 0.3, 0.15, STONE_DARK, Enum.Material.Slate, map)
	disc("Courtyard", M.courtyardRadius, 0.6, 0.6, STONE, Enum.Material.Slate, map)
	disc("CourtyardRing", 10, 0.2, 0.7, STONE_DARK, Enum.Material.Slate, map)

	-- paths from the courtyard to the front of each plot
	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	for i = 1, M.plotCount do
		local cf = Build.plotFrame(i)
		local outward = cf.LookVector
		local from = M.courtyardRadius - 2
		local to = M.plotRadius - M.plotSize.Y / 2 + 1
		local mid = outward * ((from + to) / 2)
		part({
			Name = "Path" .. i,
			Size = Vector3.new(14, 0.3, to - from),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.3, 0), mid + Vector3.new(0, 0.3, 0) + outward),
			Color = STONE,
			Material = Enum.Material.Slate,
		}, paths)
	end
	paths.Parent = map

	-- edge of the world: a low rock rim plus a tall invisible wall
	local edge = Instance.new("Folder")
	edge.Name = "Edge"
	local segments = 36
	local r = M.worldRadius - 4
	local segLen = 2 * math.pi * r / segments + 1
	for s = 1, segments do
		local a = (s - 0.5) / segments * math.pi * 2
		local pos = Vector3.new(math.sin(a), 0, math.cos(a)) * r
		local look = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		part({ Name = "Rim", Size = Vector3.new(segLen, 7, 4), CFrame = look * CFrame.new(0, 3.5, 0), Color = STONE_DARK }, edge)
		part({ Name = "Invisible", Size = Vector3.new(segLen, 60, 2), CFrame = look * CFrame.new(0, 37, 1), Transparency = 1, CanQuery = false, CastShadow = false }, edge)
	end
	edge.Parent = map

	-- monster spawn points, from the area data
	local spawns = Instance.new("Folder")
	spawns.Name = "MonsterSpawns"
	local rng = Random.new(1234)
	local placed: { Vector3 } = {}
	for _, area in Config.Areas do
		for _, bandName in { "inner", "outer" } do
			local band = (area :: any)[bandName]
			local list = {}
			for monsterId, count in band.monsters do
				for _ = 1, count do
					table.insert(list, monsterId)
				end
			end
			table.sort(list)
			local n = #list
			local offset = if bandName == "inner" then math.pi / M.plotCount else 0
			for k, monsterId in list do
				-- mix the types around the ring instead of grouping them
				local slot = ((k - 1) * 5) % n
				local a = offset + slot / n * math.pi * 2
				local rad = band.radius[1] + rng:NextNumber() * (band.radius[2] - band.radius[1])
				local pos = Vector3.new(math.sin(a), 0, math.cos(a)) * rad
				table.insert(placed, pos)
				local p = part({ Name = "Spawn", Size = Vector3.new(2, 0.2, 2), CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, spawns)
				p:SetAttribute("Area", area.id)
				p:SetAttribute("Band", bandName)
				p:SetAttribute("Monster", monsterId)
			end
		end
	end
	spawns.Parent = map

	-- grey rocks scattered in the wastes so the ground isn't empty
	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	local made = 0
	local tries = 0
	while made < 34 and tries < 500 do
		tries += 1
		local a = rng:NextNumber() * math.pi * 2
		local rad = 178 + rng:NextNumber() * 150
		local pos = Vector3.new(math.sin(a), 0, math.cos(a)) * rad
		local ok = true
		for _, other in placed do
			if (other - pos).Magnitude < 16 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, pos)
			made += 1
			local size = Vector3.new(4 + rng:NextNumber() * 7, 3 + rng:NextNumber() * 8, 4 + rng:NextNumber() * 7)
			part({
				Name = "Rock",
				Size = size,
				CFrame = CFrame.new(pos + Vector3.new(0, size.Y / 2 - 0.6, 0)) * CFrame.Angles(rng:NextNumber() * 0.3, rng:NextNumber() * 6.28, rng:NextNumber() * 0.3),
				Color = Color3.fromRGB(80 + rng:NextInteger(0, 25), 78 + rng:NextInteger(0, 20), 76 + rng:NextInteger(0, 20)),
				Material = Enum.Material.Slate,
			}, rocks)
		end
	end
	rocks.Parent = map
	map.Parent = Workspace

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	for i = 1, M.plotCount do
		buildPlot(i, plots)
	end
	plots.Parent = Workspace

	-- the default spawn sits in the courtyard; players are moved to their plot at once
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Position = Vector3.new(0, 1.2, 0)
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Duration = 0
		spawn.Neutral = true
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		spawn.Locked = true
	end

	-- grey test lighting: readable, a little moody
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 116, 122)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.32
		atmosphere.Color = Color3.fromRGB(196, 180, 168)
		atmosphere.Decay = Color3.fromRGB(110, 92, 86)
		atmosphere.Haze = 1.2
		atmosphere.Glare = 0
	end

	Workspace.StreamingEnabled = true
	return string.format("built: %d plots, %d spawns, %d rocks", M.plotCount, #spawns:GetChildren(), made)
end

return Build
