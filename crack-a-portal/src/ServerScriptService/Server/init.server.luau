--!strict
-- Server boot: create the remotes, register collision groups, then require every system in
-- ORDER, call init() on all of them, then start() on all of them. Each step is wrapped in
-- pcall, so one broken system is skipped with a warning and the rest still run.

local PhysicsService = game:GetService("PhysicsService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Systems = script:WaitForChild("Systems")

local ORDER = {
	"RateLimit",
	"Save",
	"PlayerData",
	"Notify",
	"Plots",
	"Gates",
	"Appearance",
	"Monsters",
	"Combat",
	"Openings",
	"MapMonsters",
	"Economy",
	"Daily",
	"Index",
	"Leaderboards",
	"Rift",
	"Purchases",
	"Tutorial",
	"DebugTools",
}

type System = { init: (() -> ())?, start: (() -> ())? }

-- Remotes first: every system's init may look them up.
local netOk, netErr = pcall(Net.create)
if not netOk then
	warn(`[Server] Net.create failed: {netErr}`)
end

-- Collision groups: players and monsters never collide; Fx parts collide with neither.
-- PlayerData puts character parts in "Players"; Monsters puts its rigs in "Monsters".
local function registerGroups()
	for _, name in { "Players", "Monsters", "Fx" } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Players", "Monsters", false)
	PhysicsService:CollisionGroupSetCollidable("Players", "Fx", false)
	PhysicsService:CollisionGroupSetCollidable("Monsters", "Fx", false)
	PhysicsService:CollisionGroupSetCollidable("Fx", "Fx", false)
end
local groupsOk, groupsErr = pcall(registerGroups)
if not groupsOk then
	warn(`[Server] collision groups: {groupsErr}`)
end

local loaded: { { name: string, mod: System } } = {}

for _, name in ORDER do
	local moduleScript = Systems:FindFirstChild(name)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`[Server] system {name} is missing; skipped`)
		continue
	end
	local ok, result = pcall(require, moduleScript)
	if ok and type(result) == "table" then
		table.insert(loaded, { name = name, mod = result :: any })
	else
		warn(`[Server] system {name} failed to load; skipped: {result}`)
	end
end

local ready: { { name: string, mod: System } } = {}
for _, entry in loaded do
	local init = entry.mod.init
	if init then
		local ok, err = pcall(init)
		if not ok then
			warn(`[Server] {entry.name}.init failed; not started: {err}`)
			continue
		end
	end
	table.insert(ready, entry)
end

for _, entry in ready do
	local start = entry.mod.start
	if start then
		task.spawn(function()
			local ok, err = pcall(start)
			if not ok then
				warn(`[Server] {entry.name}.start failed: {err}`)
			end
		end)
	end
end
