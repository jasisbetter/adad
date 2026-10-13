--!strict
-- RateLimit: a token bucket per player and key. Every remote handler calls
-- RateLimit.allow(player, name, Net.Limits[name].rate, Net.Limits[name].burst) first.

local Players = game:GetService("Players")

local RateLimit = {}

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

-- True when the player still has a token for this key (refills at perSecond, holds up to burst).
function RateLimit.allow(player: Player, key: string, perSecond: number, burst: number): boolean
	if typeof(player) ~= "Instance" or type(key) ~= "string" then
		return false
	end
	if type(perSecond) ~= "number" or perSecond ~= perSecond or perSecond <= 0 then
		return false
	end
	if type(burst) ~= "number" or burst ~= burst or burst < 1 then
		burst = 1
	end
	local now = os.clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		if player.Parent == nil then
			return false -- already left; never recreate its table
		end
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[key]
	if not bucket then
		bucket = { tokens = burst, last = now }
		perPlayer[key] = bucket
	else
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * perSecond)
		bucket.last = now
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimit.clear(player: Player)
	buckets[player] = nil
end

function RateLimit.init() end

function RateLimit.start()
	Players.PlayerRemoving:Connect(RateLimit.clear)
end

return RateLimit
