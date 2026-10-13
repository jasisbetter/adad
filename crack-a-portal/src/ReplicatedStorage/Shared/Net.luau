--!strict
-- Net: the one list of remotes. The server creates them at start; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Client -> server: intent only, never amounts, prices or damage.
Net.ToServer = {
	"Ready",
	"Attack",
	"Dodge",
	"UseKey",
	"OpenChest",
	"Choice",
	"Equip",
	"Upgrade",
	"Merge",
	"Sell",
	"UpgradePortal",
	"BuyKey",
	"ClaimDaily",
	"ClaimQuest",
	"ClaimIndex",
	"Setting",
	"Tutorial",
	"Recover",
}
-- Server -> client (reliable)
Net.ToClient = { "Profile", "Opening", "Fx", "Hits", "Warn", "Boss", "Rift", "Announce", "Boards" }
-- Server -> client (UnreliableRemoteEvent): cosmetic broadcasts only
Net.Unreliable = { "FxU" }

export type Limit = { rate: number, burst: number, [number]: number }

-- Readable both ways: limit.rate / limit.burst or limit[1] / limit[2].
local function limit(rate: number, burst: number): Limit
	-- selene: allow(mixed_table)
	return { rate, burst, rate = rate, burst = burst }
end

-- RateLimit.allow(player, name, rate, burst) for every client -> server remote.
Net.Limits = {
	Ready = limit(1, 2),
	Attack = limit(12, 8),
	Dodge = limit(3, 3),
	UseKey = limit(2, 3),
	OpenChest = limit(2, 3),
	Choice = limit(2, 3),
	Equip = limit(5, 6),
	Upgrade = limit(8, 10),
	Merge = limit(3, 4),
	Sell = limit(6, 8),
	UpgradePortal = limit(3, 4),
	BuyKey = limit(4, 5),
	ClaimDaily = limit(1, 2),
	ClaimQuest = limit(2, 4),
	ClaimIndex = limit(2, 4),
	Setting = limit(6, 12),
	Tutorial = limit(4, 6),
	Recover = limit(2, 3),
	Debug = limit(10, 10), -- Studio only
} :: { [string]: Limit }

local FOLDER = "Remotes"

function Net.create()
	assert(RunService:IsServer(), "Net.create is server only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, name in Net.ToServer do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Net.ToClient do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Net.Unreliable do
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	if RunService:IsStudio() then -- test commands exist only in Studio
		local remote = Instance.new("RemoteEvent")
		remote.Name = "Debug"
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Net.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.getU(name: string): UnreliableRemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER)
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.find(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	local remote = folder and folder:FindFirstChild(name)
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

return Net
