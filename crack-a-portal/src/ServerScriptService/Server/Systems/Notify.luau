--!strict
-- Notify: server -> client messages. Toasts and effects for one player (Fx, reliable),
-- server messages for everyone (Announce, skips players in the tutorial) and cosmetic
-- broadcasts to players nearby (FxU, unreliable).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

type FxEvent = Types.FxEvent

local Notify = {}

local remotes = {
	fx = nil :: RemoteEvent?,
	fxU = nil :: UnreliableRemoteEvent?,
	announce = nil :: RemoteEvent?,
}

local function fxRemote(): RemoteEvent?
	if not remotes.fx then
		remotes.fx = Net.find("Fx")
	end
	return remotes.fx
end

local function announceRemote(): RemoteEvent?
	if not remotes.announce then
		remotes.announce = Net.find("Announce")
	end
	return remotes.announce
end

local function fxURemote(): UnreliableRemoteEvent?
	if not remotes.fxU then
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local remote = folder and folder:FindFirstChild("FxU")
		if remote and remote:IsA("UnreliableRemoteEvent") then
			remotes.fxU = remote
		end
	end
	return remotes.fxU
end

local function inGame(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

-- One reliable effect event for this player.
function Notify.fx(player: Player, ev: FxEvent)
	local remote = fxRemote()
	if remote and inGame(player) then
		remote:FireClient(player, ev)
	end
end

-- Reliable effect event for everyone.
function Notify.fxAll(ev: FxEvent)
	local remote = fxRemote()
	if remote then
		remote:FireAllClients(ev)
	end
end

-- Cosmetic broadcast (unreliable) to players whose character is within `radius` of `pos`.
function Notify.fxNear(pos: Vector3, radius: number, ev: FxEvent)
	local remote = fxURemote()
	if not remote then
		return
	end
	local r2 = radius * radius
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character.PrimaryPart
		if root then
			local d = root.Position - pos
			if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
				remote:FireClient(player, ev)
			end
		end
	end
end

-- A short message card on this player's screen. Styles: "info", "good", "warn", "rare", "legendary".
function Notify.toast(player: Player, text: string, style: string?)
	Notify.fx(player, { k = "Toast", text = text, style = style or "info" })
end

-- A server message for every player, except players still in the tutorial.
function Notify.announce(text: string, style: string?)
	local remote = announceRemote()
	if not remote then
		return
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("TutorialActive") ~= true then
			remote:FireClient(player, text, style or "info")
		end
	end
end

function Notify.init()
	fxRemote()
	announceRemote()
	fxURemote()
end

function Notify.start() end

return Notify
