--!strict
-- Plots: reads Workspace.Plots.PlotN (made by ServerStorage.Build), hands each player a free plot on join
-- and frees it on leave, writes the owner's name on the banner and keeps the plot attributes
-- (Index, Owner = UserId, Tier, PortalState, PortalKind). Also: inside checks, the opening walls,
-- the portal tier model and sending players home.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic)
local Assets = require(Shared.Assets)
local Templates = require(Shared.Templates)

local Bus = require(script.Parent.Parent.Lib.Bus)
local PlayerData = require(script.Parent.PlayerData)

local Plots = {}

local PLAYER_GROUP = "Players"
local WALL_ON = 0.3 -- ForceField transparency while a wall is up
local WALL_FADE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLAMP_MARGIN = 2.5
local FREE_TEXT = "Free plot"
local STATES = { idle = true, cracking = true, open = true, closing = true, slam = true }

type PlotInfo = {
	model: Model,
	index: number,
	platform: BasePart,
	owner: Player?,
	walls: { BasePart },
	wallOn: boolean,
	tweens: { Tween },
}

local plots: { PlotInfo } = {}
local byModel: { [Model]: PlotInfo } = {}
local byPlayer: { [Player]: PlotInfo } = {}
local charConns: { [Player]: { RBXScriptConnection } } = {}
local playerConns: { [Player]: RBXScriptConnection } = {}
local started = false

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function moveCharacter(player: Player, cf: CFrame)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	character:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function bannerLabel(plot: Model): TextLabel?
	local banner = plot:FindFirstChild("Banner")
	-- FindFirstChild: banner.Name would read the Name property, not the SurfaceGui
	local gui = banner and banner:FindFirstChild("Name")
	local label = gui and gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function setBanner(plot: Model, text: string)
	local label = bannerLabel(plot)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function portalLevelOf(player: Player): number
	local session = PlayerData.get(player)
	if session then
		return math.max(1, tonumber(session.profile.portalLevel) or 1)
	end
	return math.max(1, tonumber(player:GetAttribute("PortalLevel")) or 1)
end

local function prepModel(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Locked = true
		end
	end
end

local function surfaceOf(portal: Instance?): BasePart?
	local surface = portal and portal:FindFirstChild("Surface", true)
	if surface and surface:IsA("BasePart") then
		return surface
	end
	return nil
end

---------------------------------------------------------------------------
-- loading the plots
---------------------------------------------------------------------------

local function ensureMap()
	if Workspace:FindFirstChild("Plots") then
		return
	end
	-- Build.run() was not run in Edit mode: build the map now so the game still works
	warn("[Plots] Workspace.Plots is missing; running ServerStorage.Build now (run Build.run() in Edit mode)")
	local module = ServerStorage:FindFirstChild("Build")
	if module and module:IsA("ModuleScript") then
		local ok, err = pcall(function()
			local Build: any = require(module :: any)
			print(`[Plots] {Build.run()}`)
		end)
		if not ok then
			warn(`[Plots] Build.run failed: {err}`)
		end
	end
end

local function scan()
	local folder = Workspace:FindFirstChild("Plots")
	if not folder then
		warn("[Plots] no Workspace.Plots: players get no plot")
		return
	end
	for i = 1, Config.Map.plotCount do
		local model = folder:FindFirstChild(`Plot{i}`)
		local platform = model and model:FindFirstChild("Platform")
		if not model or not model:IsA("Model") or not platform or not platform:IsA("BasePart") then
			warn(`[Plots] Plot{i} is missing or has no Platform; skipped`)
			continue
		end
		local walls: { BasePart } = {}
		local wallFolder = model:FindFirstChild("Walls")
		if wallFolder then
			for _, w in wallFolder:GetChildren() do
				if w:IsA("BasePart") then
					w.Transparency = 1
					w.CanCollide = false
					table.insert(walls, w)
				end
			end
		end
		local info: PlotInfo = {
			model = model,
			index = i,
			platform = platform,
			owner = nil,
			walls = walls,
			wallOn = false,
			tweens = {},
		}
		model:SetAttribute("Index", i)
		model:SetAttribute("Owner", 0)
		model:SetAttribute("PortalState", "idle")
		model:SetAttribute("PortalKind", nil)
		if model:GetAttribute("Tier") == nil then
			model:SetAttribute("Tier", 1)
		end
		setBanner(model, FREE_TEXT)
		table.insert(plots, info)
		byModel[model] = info
	end
end

---------------------------------------------------------------------------
-- public API
---------------------------------------------------------------------------

function Plots.plotOf(player: Player): Model?
	local info = byPlayer[player]
	return info and info.model
end

function Plots.indexOf(plot: Model): number
	local info = byModel[plot]
	return if info then info.index else (tonumber(plot:GetAttribute("Index")) or 0)
end

function Plots.ownerOf(plot: Model): Player?
	local info = byModel[plot]
	return info and info.owner
end

-- True when pos is over the plot's platform (flat rectangle in the plot's own space, Y ignored).
-- margin > 0 shrinks the rectangle, < 0 grows it (default 0: the platform edge).
function Plots.isInside(plot: Model, pos: Vector3, margin: number?): boolean
	local info = byModel[plot]
	if not info then
		return false
	end
	local m = margin or 0
	local p = info.platform.CFrame:PointToObjectSpace(pos)
	local half = info.platform.Size / 2
	return math.abs(p.X) <= half.X - m and math.abs(p.Z) <= half.Z - m
end

-- pos moved onto the plot (CLAMP_MARGIN studs inside the edge), height kept.
function Plots.clampInside(plot: Model, pos: Vector3): Vector3
	local info = byModel[plot]
	if not info then
		return pos
	end
	local cf = info.platform.CFrame
	local p = cf:PointToObjectSpace(pos)
	local half = info.platform.Size / 2
	local hx, hz = math.max(0, half.X - CLAMP_MARGIN), math.max(0, half.Z - CLAMP_MARGIN)
	return cf:PointToWorldSpace(Vector3.new(math.clamp(p.X, -hx, hx), p.Y, math.clamp(p.Z, -hz, hz)))
end

-- CFrame of a marker on the plot: "PlayerSpawn", "ChestSpot", "MonsterSpawn", "PortalFront".
function Plots.spot(plot: Model, name: string): CFrame
	local marker = plot:FindFirstChild(name)
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	return plot:GetPivot()
end

-- Sends the player to their plot's spawn, facing the portal (the courtyard spawn without a plot).
function Plots.sendHome(player: Player)
	local info = byPlayer[player]
	if info then
		moveCharacter(player, Plots.spot(info.model, "PlayerSpawn"))
		return
	end
	local spawnPart = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnPart then
		moveCharacter(player, spawnPart.CFrame + Vector3.new(0, 3, 0))
	end
end

-- Just outside the plot's front edge, facing the plot.
local function outsideFront(info: PlotInfo): CFrame
	local cf = info.platform.CFrame
	local pos = cf:PointToWorldSpace(Vector3.new(0, 3, info.platform.Size.Z / 2 + 6))
	local look = Vector3.new(cf.Position.X, pos.Y, cf.Position.Z)
	return CFrame.lookAt(pos, look)
end

-- The soft glowing walls around the plot. On during an opening: they block everyone, so the owner
-- can't leave and other players can't come in. Players who aren't the owner are moved out first.
function Plots.setWall(plot: Model, on: boolean)
	local info = byModel[plot]
	if not info or info.wallOn == on then
		return
	end
	info.wallOn = on
	for _, t in info.tweens do
		t:Cancel()
	end
	table.clear(info.tweens)
	if on then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if not root then
				continue
			end
			local inside = Plots.isInside(plot, root.Position)
			if player ~= info.owner and inside then
				moveCharacter(player, outsideFront(info))
			elseif player == info.owner and not inside then
				Plots.sendHome(player)
			end
		end
	end
	for _, wall in info.walls do
		wall.CanCollide = on
		local tween = TweenService:Create(wall, WALL_FADE, { Transparency = if on then WALL_ON else 1 })
		table.insert(info.tweens, tween)
		tween:Play()
	end
end

-- Swaps the portal arch for the tier of this portal level (Assets.Portal.Tier<n> or the grey
-- template), at the same pivot. The new arch keeps a part named "Surface" (re-find it after a swap).
function Plots.setTier(plot: Model, level: number)
	local info = byModel[plot]
	if not info then
		return
	end
	local tier = Logic.portalTier(math.max(1, math.floor(tonumber(level) or 1)))
	local old = plot:FindFirstChild("Portal")
	if old and plot:GetAttribute("Tier") == tier then
		return
	end
	local base: CFrame
	if old and old:IsA("Model") then
		base = old:GetPivot()
	else
		-- same place Build puts it: on the floor, PortalOffset back, front facing the courtyard
		local p = info.platform
		base = p.CFrame * CFrame.new(0, p.Size.Y / 2 + 0.1, -Config.Map.portalOffset) * CFrame.Angles(0, math.pi, 0)
	end
	local fresh = Assets.portalTier(tier) or Templates.portal(tier)
	fresh.Name = "Portal"
	prepModel(fresh)
	local state = plot:GetAttribute("PortalState")
	local surface = surfaceOf(fresh)
	if surface then
		surface:SetAttribute("State", if type(state) == "string" then state else "idle")
	end
	fresh:PivotTo(base)
	if old then
		old:Destroy()
	end
	fresh.Parent = plot
	plot:SetAttribute("Tier", tier)
end

-- Portal state attributes ("idle", "cracking", "open", "closing", "slam"); the client animates them.
function Plots.setPortalState(plot: Model, state: string, kind: string?)
	if not byModel[plot] or not STATES[state] then
		return
	end
	plot:SetAttribute("PortalState", state)
	if kind ~= nil then
		plot:SetAttribute("PortalKind", kind)
	elseif state == "idle" then
		plot:SetAttribute("PortalKind", nil)
	end
	local surface = surfaceOf(plot:FindFirstChild("Portal"))
	if surface then
		surface:SetAttribute("State", state)
	end
end

-- Gives the player a free plot (lowest index first). Returns the plot, or nil when all are taken.
function Plots.assign(player: Player): Model?
	local existing = byPlayer[player]
	if existing then
		return existing.model
	end
	for _, info in plots do
		if info.owner == nil then
			info.owner = player
			byPlayer[player] = info
			info.model:SetAttribute("Owner", player.UserId)
			info.model:SetAttribute("PortalState", "idle")
			info.model:SetAttribute("PortalKind", nil)
			setBanner(info.model, player.DisplayName)
			Plots.setTier(info.model, portalLevelOf(player))
			return info.model
		end
	end
	warn(`[Plots] no free plot for {player.Name}`)
	return nil
end

local function release(player: Player)
	local info = byPlayer[player]
	byPlayer[player] = nil
	if not info or info.owner ~= player then
		return
	end
	info.owner = nil
	Plots.setWall(info.model, false)
	Plots.setPortalState(info.model, "idle")
	info.model:SetAttribute("Owner", 0)
	setBanner(info.model, FREE_TEXT)
	Plots.setTier(info.model, 1)
end

---------------------------------------------------------------------------
-- players and characters
---------------------------------------------------------------------------

local function ensureGroup()
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(PLAYER_GROUP) then
			PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
		end
	end)
end

local function setGroup(d: Instance)
	if d:IsA("BasePart") then
		d.CollisionGroup = PLAYER_GROUP
	end
end

local function clearCharacter(player: Player)
	local list = charConns[player]
	if list then
		for _, c in list do
			c:Disconnect()
		end
		charConns[player] = nil
	end
end

local function onCharacter(player: Player, character: Model)
	clearCharacter(player)
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	charConns[player] = { character.DescendantAdded:Connect(setGroup) }
	task.spawn(function()
		-- wait until the character is in the world (Roblox places it at the SpawnLocation first)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		local limit = os.clock() + 10
		while not character:IsDescendantOf(Workspace) and os.clock() < limit do
			task.wait()
		end
		task.wait()
		if player.Character == character and character:IsDescendantOf(Workspace) then
			Plots.sendHome(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	if playerConns[player] then
		return
	end
	Plots.assign(player)
	playerConns[player] = player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local conn = playerConns[player]
	if conn then
		conn:Disconnect()
		playerConns[player] = nil
	end
	clearCharacter(player)
	release(player)
end

function Plots.init()
	ensureGroup()
	ensureMap()
	scan()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- the saved portal level arrives after join; portal upgrades come through the Bus
	PlayerData.onLoaded(function(player: Player)
		local info = byPlayer[player]
		if info then
			Plots.setTier(info.model, portalLevelOf(player))
		end
	end)
	Bus.on("PortalLevel", function(player: Player, level: number)
		local info = byPlayer[player]
		if info and type(level) == "number" then
			Plots.setTier(info.model, level)
		end
	end)
end

function Plots.start()
	if started then
		return
	end
	started = true
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Plots
