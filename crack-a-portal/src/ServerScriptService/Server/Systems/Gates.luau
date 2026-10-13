--!strict
-- Gates: which area a position is in, who may enter which area (portal level >= area.portalLevel),
-- and the server check behind the gates. Four times a second every player gets the attribute
-- Area (area id, or "Hub" for the courtyard and plots), and anyone past the ring wall of their
-- first locked area is moved back just inside it, in front of the nearest gate, with a toast.
-- The client Zones controller turns gate Barrier collision off locally for unlocked areas; this
-- check is the authority.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic)
local Types = require(Shared.Types)

local Bus = require(script.Parent.Parent.Lib.Bus)
local PlayerData = require(script.Parent.PlayerData)
local Notify = require(script.Parent.Notify)

type Area = Types.Area

local Gates = {}

local TICK = 0.25 -- 4 Hz
local PAST = 3 -- studs past the ring wall that count as "through" (the barrier itself is ~1 stud thick)
local PUSH_IN = 8 -- studs inside the ring wall where a player is put back
local LIFT = 3.5 -- root height above the gate's ground point
local TOAST_GAP = 4 -- seconds between "Reach portal level" toasts per player

type GateSpot = { pos: Vector3, dir: Vector3 }
type PlayerState = { area: string?, lastToast: number, level: number? }

local ringRadius: { [number]: number } = {} -- area index -> radius of the wall in front of it
local gateSpots: { [string]: { GateSpot } } = {} -- area id -> gates
local states: { [Player]: PlayerState } = {}
local running = false

-- Same formula as Build.ringRadius: the middle of the gap in front of area i.
local function computeRing(i: number): number
	local area = Config.Areas[i]
	if i == 1 then
		return area.inner.radius[1] - 10
	end
	return (Config.Areas[i - 1].outer.radius[2] + area.inner.radius[1]) / 2
end

local function flatOf(pos: Vector3): Vector3
	local c = Config.Map.riftCenter
	return Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
end

local function scanGates()
	table.clear(gateSpots)
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Gates")
	if not folder then
		warn("[Gates] no Workspace.Map.Gates: players are pushed back without a gate to aim at")
		return
	end
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local areaId = string.match(model.Name, "^Gate_(.+)_%d+$")
		if not areaId or not Config.AreaById[areaId] then
			continue
		end
		local pos = model:GetPivot().Position
		local flat = flatOf(pos)
		if flat.Magnitude < 1 then
			continue
		end
		local list = gateSpots[areaId]
		if not list then
			list = {}
			gateSpots[areaId] = list
		end
		table.insert(list, { pos = pos, dir = flat.Unit })
	end
end

local function portalLevel(player: Player): number
	local session = PlayerData.get(player)
	if session then
		return math.max(1, tonumber(session.profile.portalLevel) or 1)
	end
	return math.max(1, tonumber(player:GetAttribute("PortalLevel")) or 1)
end

-- How many areas, counted from the centre, this level may enter (stops at the first locked one).
local function allowedCount(level: number): number
	local n = 0
	for i, area in Config.Areas do
		if area.portalLevel <= level then
			n = i
		else
			break
		end
	end
	return n
end

-- "Hub" inside the first ring; in the gap between two areas, the inner one.
local function zoneId(r: number): string
	local id = "Hub"
	for _, area in Config.Areas do
		if r >= area.inner.radius[1] then
			id = area.id
		else
			break
		end
	end
	return id
end

---------------------------------------------------------------------------
-- public API
---------------------------------------------------------------------------

function Gates.areaAt(pos: Vector3): (Area?, string?)
	return Logic.areaAt(pos)
end

function Gates.canEnter(player: Player, areaId: string): boolean
	local area = Config.AreaById[areaId]
	if not area then
		return false
	end
	return portalLevel(player) >= area.portalLevel
end

-- The outermost area the player may enter (the first area at least).
function Gates.unlockedArea(player: Player): Area
	local n = math.max(1, allowedCount(portalLevel(player)))
	return Config.Areas[n]
end

---------------------------------------------------------------------------
-- enforcement
---------------------------------------------------------------------------

local function pushBack(player: Player, character: Model, root: BasePart, lockedIndex: number, state: PlayerState)
	local locked = Config.Areas[lockedIndex]
	local R = ringRadius[lockedIndex]
	local c = Config.Map.riftCenter
	local flat = flatOf(root.Position)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
	local target: Vector3
	local best: GateSpot? = nil
	local bestDot = -2
	for _, spot in gateSpots[locked.id] or {} do
		local d = spot.dir:Dot(dir)
		if d > bestDot then
			bestDot = d
			best = spot
		end
	end
	if best then
		local p = c + best.dir * (R - PUSH_IN)
		target = Vector3.new(p.X, best.pos.Y + LIFT, p.Z)
	else
		local p = c + dir * (R - PUSH_IN)
		target = Vector3.new(p.X, math.max(root.Position.Y, LIFT + 1), p.Z)
	end
	-- keep facing
	local rotation = root.CFrame - root.CFrame.Position
	character:PivotTo(CFrame.new(target) * rotation)
	root.AssemblyLinearVelocity = Vector3.zero

	local now = os.clock()
	if now - state.lastToast >= TOAST_GAP then
		state.lastToast = now
		Notify.toast(player, `Reach portal level {locked.portalLevel} to enter {locked.name}`, "warn")
	end
end

local function checkPlayer(player: Player)
	local state = states[player]
	if not state then
		state = { area = nil, lastToast = -math.huge, level = nil }
		states[player] = state
	end
	local character = player.Character
	local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	local r = flatOf(root.Position).Magnitude
	local id = zoneId(r)
	if state.area ~= id then
		state.area = id
		player:SetAttribute("Area", id)
	end
	local lockedIndex = allowedCount(portalLevel(player)) + 1
	local R = ringRadius[lockedIndex]
	if R and r > R + PAST then
		pushBack(player, character, root, lockedIndex, state)
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(checkPlayer, player)
		if not ok then
			warn(`[Gates] {err}`)
		end
	end
end

-- A portal level-up that unlocks areas plays their gate opening effect on that player's screen.
local function onPortalLevel(player: Player, level: number)
	if type(level) ~= "number" then
		return
	end
	local state = states[player]
	local before = if state and state.level then state.level else level - 1
	for _, area in Config.Areas do
		if area.portalLevel > before and area.portalLevel <= level and area.gate then
			Notify.fx(player, { k = "GateOpen", area = area.id })
		end
	end
	if state then
		state.level = level
	end
end

function Gates.init()
	table.clear(ringRadius)
	for i in Config.Areas do
		ringRadius[i] = computeRing(i)
	end
	-- the first area has no wall in front of it when it is open from level 1
	if Config.Areas[1] and Config.Areas[1].portalLevel <= 1 then
		ringRadius[1] = nil
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	PlayerData.onLoaded(function(player: Player)
		local state = states[player]
		if not state then
			state = { area = nil, lastToast = -math.huge, level = nil }
			states[player] = state
		end
		state.level = portalLevel(player)
	end)
	Bus.on("PortalLevel", onPortalLevel)
end

function Gates.start()
	if running then
		return
	end
	running = true
	scanGates()
	while running do
		task.wait(TICK)
		tick()
	end
end

return Gates
