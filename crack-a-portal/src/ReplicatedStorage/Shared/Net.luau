--!strict
-- Net: the one list of remotes. The server creates them at start; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- Client -> server: intent only, never amounts or damage.
Net.ToServer = { "Attack", "Dodge", "UseKey", "OpenChest", "Choice", "Equip", "Ready" }
-- Server -> client
Net.ToClient = { "Profile", "Opening", "Fx", "Hits", "Warn" }

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

function Net.find(name: string): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	local remote = folder and folder:FindFirstChild(name)
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

return Net
