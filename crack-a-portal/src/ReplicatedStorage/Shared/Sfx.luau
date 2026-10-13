--!strict
-- ModuleScript "Sfx", client only (from the roblox-ai-sound-effects skill kit).
-- Every sound effect in the game plays through here.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

export type Def = {
	id: number?, -- one sound...
	ids: { number }?, -- ...or several takes of the same sound: a different one each play
	volume: number?, -- 0 to 1 (default 0.4)
	speed: number?, -- PlaybackSpeed: 2 = an octave up, 0.5 = an octave down
	vary: number?, -- random pitch spread: 0.06 = 3% either way (the default); 0 for tuned notes
	region: { number }?, -- { from, to } seconds: play only that part (cuts silence and long tails)
	voices: number?, -- how many copies can ring at once (default 1)
	gap: number?, -- shortest time between two plays, seconds (stops pile-ups); a minGap in the call wins
	range: number?, -- playAt only: studs at which it can no longer be heard (default 80)
}
type Voice = { sound: Sound, id: number, born: number, anchor: Attachment? }
type Pool = { takes: { number }, voices: { { Voice } }, at: { number }, last: number }

local DEFAULT_SLIDER = 0.8
local RETRY_AFTER = 30 -- seconds before a sound that failed to load is asked for again

local Sfx = {}

-- name = what the game calls it. A sound with no id (or id 0) is skipped, so the game runs without it.
-- Ids are filled from the Creator Store library after measuring them (see the game notes).
Sfx.Sounds = {
	Click = { ids = { 9120917438, 9120917609, 9120917794, 9120917861 }, volume = 0.3 }, -- PSE "Wood Impacts Soft Impacts On Temple Blocks"
	Swing = { ids = { 9120742710, 9120742903 }, region = { 0, 0.35 }, volume = 0.3, voices = 2, vary = 0.1 }, -- PSE "Whoosh Thick Quick Multiple Variations" 2, 3
	SwingHeavy = { id = 9120742729, region = { 0, 0.55 }, volume = 0.35, voices = 2, vary = 0.08 }, -- PSE "Whoosh Thick Quick" take
	Hit = { ids = { 9114742182, 9113565905 }, region = { 0, 0.5 }, volume = 0.4, voices = 4, vary = 0.12, gap = 0.03 }, -- PSE "Gym Bag Thudding" 5, "Boxing Hits" 14
	Crit = { id = 9125513939, region = { 0, 0.8 }, volume = 0.45, voices = 2, vary = 0.06 }, -- PSE "Drum Tom Tom Single Hits"
	Death = { ids = { 9116406375, 9125639499 }, region = { 0.01, 0.55 }, volume = 0.35, voices = 3, vary = 0.1, gap = 0.05 }, -- PSE "Magic Poofs" (Thumpy Wheezy Exhale 1, Short Breathy Bursts)
	Coin = { id = 9117577025, volume = 0.3, voices = 3, gap = 0.04, vary = 0.03 }, -- PSE "Plastic Impacts Dish Shaped Planter" 4
	Gear = { id = 9116423786, region = { 0.01, 0.6 }, volume = 0.45, vary = 0.02 }, -- PSE "Magic Transformation" 33
	Key = { id = 9112752910, region = { 0.05, 0.3 }, volume = 0.45, vary = 0 }, -- PSE "Bubble Wobble Comic Bloops"
	Crack = { id = 9118664167, region = { 0.35, 1.9 }, volume = 0.55, vary = 0.02 }, -- PSE "Rocks" 3
	PortalOpen = { id = 9116421639, region = { 0.01, 0.6 }, volume = 0.5, vary = 0.02 }, -- PSE "Magic Transformation" take
	WaveStart = { id = 9125514525, region = { 0, 1.1 }, volume = 0.45, vary = 0 }, -- PSE "Drum Tom Tom Single Hits"
	ChestLand = { id = 9120917438, speed = 0.6, volume = 0.45, vary = 0.04 }, -- PSE temple block, slowed
	ChestOpen = { id = 9126264414, region = { 0.02, 0.45 }, volume = 0.5, vary = 0.02 }, -- PSE "Wood Groan Creak Opening Wood Chest Coffin" 2
	Reveal = { id = 9116423273, region = { 0.01, 0.6 }, volume = 0.45, vary = 0 }, -- PSE "Magic Transformation" take
	Close = { id = 9116421238, region = { 0.01, 0.6 }, volume = 0.5, vary = 0 }, -- PSE "Magic Transformation" take
	Fall = { id = 9116423786, speed = 0.85, region = { 0.01, 0.6 }, volume = 0.5, vary = 0 }, -- PSE "Magic Transformation" 33, slowed
	Kept = { id = 9112751536, speed = 0.7, region = { 0.02, 0.3 }, volume = 0.4, vary = 0, voices = 3 }, -- PSE "Bubble Bloop High Pitched Cute", slowed
	Shatter = { id = 9118689425, speed = 0.8, region = { 0.58, 0.9 }, volume = 0.35, vary = 0.06, voices = 3 }, -- PSE "Rocks Knock Against Each Other" 3
	Hurt = { id = 9114742182, speed = 0.75, volume = 0.4, vary = 0.08, gap = 0.08 }, -- PSE "Gym Bag Thudding" 5, slowed
	Dodge = { id = 9125495641, region = { 0.04, 0.21 }, volume = 0.3, vary = 0.08 }, -- PSE "Dowel Swish Bamboo Thick Midrange"
	Slam = { id = 9125514679, volume = 0.45, voices = 2, vary = 0.06, range = 90 }, -- PSE "Drum Tom Tom Single Hits"
	Warn = { id = 9120742729, region = { 0, 0.5 }, volume = 0.25, voices = 3, vary = 0.04, gap = 0.1 }, -- PSE "Whoosh Thick Quick" take, slowed
} :: { [string]: Def }

local player = Players.LocalPlayer :: Player
-- Studio-only mute switch from roblox-playtest-review, so test runs are silent from the first frame.
local MUTED = RunService:IsStudio() and os.time() < (tonumber(workspace:GetAttribute("StudioMuteUntil")) or 0)
Sfx.muted = MUTED

local found = SoundService:FindFirstChild("SFX")
local group: SoundGroup
if found and found:IsA("SoundGroup") then
	group = found
else
	group = Instance.new("SoundGroup")
	group.Name = "SFX"
	group.Parent = SoundService
end
Sfx.Group = group

local slider = DEFAULT_SLIDER
local lastSlider = -math.huge
local rng = Random.new()
local pools: { [string]: Pool } = {}
local lastPlayed: { [string]: number } = {}

local function apply(alpha: number)
	slider = math.clamp(alpha, 0, 1)
	group:SetAttribute("SliderValue", slider) -- what the player chose, readable even while muted
	group.Volume = if MUTED then 0 else slider -- a new SoundGroup starts at 0.5, so it is always set
end

-- The Sounds slider in Settings calls this on every movement (0 to 1).
function Sfx.setVolume(alpha: number)
	lastSlider = os.clock()
	apply(alpha)
end

function Sfx.getVolume(): number
	return slider
end

-- The server keeps the saved value on the player as the "SfxVolume" attribute.
local function applySaved()
	if os.clock() - lastSlider < 1 then
		return -- the server echoing the slider's own value: don't fight the finger
	end
	local saved = player:GetAttribute("SfxVolume")
	if typeof(saved) == "number" then
		apply(saved)
	end
end
player:GetAttributeChangedSignal("SfxVolume"):Connect(applySaved)
apply(slider)
applySaved()

-- Roblox's own sounds (steps, jump, landing) sit in no group. In the SFX group the slider and
-- the Studio mute switch cover them too.
local function adopt(inst: Instance)
	if inst:IsA("Sound") and inst.SoundGroup == nil then
		inst.SoundGroup = group
	end
end
for _, inst in workspace:GetDescendants() do
	adopt(inst)
end
workspace.DescendantAdded:Connect(adopt)

local function takes(def: Def): { number }
	local all: { number } = def.ids or { def.id or 0 }
	local list = {}
	for _, id in all do
		if id ~= 0 then
			table.insert(list, id)
		end
	end
	return list
end

local function makeVoice(name: string, def: Def, id: number, in3D: boolean): Voice
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. id
	sound.SoundGroup = group -- being inside a folder is not enough
	if def.region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(def.region[1], def.region[2])
	end
	local anchor: Attachment? = nil
	if in3D then -- a Sound under an Attachment in Workspace is 3D: it gets quieter with distance
		local range = def.range or 80
		local point = Instance.new("Attachment")
		point.Name = "Sfx_" .. name
		point.Parent = workspace.Terrain
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = range * 0.15
		sound.RollOffMaxDistance = range -- the default is 10,000 studs: heard across the whole map
		sound.Parent = point
		anchor = point
	else
		sound.Parent = SoundService -- not under a part: the same everywhere
	end
	return { sound = sound, id = id, born = os.clock(), anchor = anchor }
end

-- One pool per sound: `voices` copies of every take, used in turn, so a quick second play
-- never cuts the first one off, and the number that can ring at once is fixed.
local function getPool(key: string, name: string, def: Def, in3D: boolean): Pool?
	local existing = pools[key]
	if existing then
		return existing
	end
	local list = takes(def)
	if #list == 0 then
		return nil
	end
	local pool: Pool = { takes = list, voices = {}, at = {}, last = 0 }
	for take, id in list do
		pool.voices[take] = {}
		pool.at[take] = 0
		for copy = 1, math.max(1, def.voices or 1) do
			pool.voices[take][copy] = makeVoice(name, def, id, in3D)
		end
	end
	pools[key] = pool
	return pool
end

local function start(name: string, position: Vector3?, pitch: number?, minGap: number?, gain: number?)
	local def = Sfx.Sounds[name]
	if not def then
		warn("[Sfx] no sound called " .. name)
		return
	end
	local now = os.clock()
	local gap = minGap or def.gap
	if gap and now - (lastPlayed[name] or 0) < gap then
		return
	end
	if position then
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - position).Magnitude > (def.range or 80) then
			return -- too far to hear: don't spend a voice on it
		end
	end
	local key = if position then name .. "@3D" else name
	local pool = getPool(key, name, def, position ~= nil)
	if not pool then
		return
	end
	lastPlayed[name] = now
	local take = 1
	if #pool.takes > 1 then -- a random take, never the same one twice in a row
		take = rng:NextInteger(1, #pool.takes - (if pool.last > 0 then 1 else 0))
		if pool.last > 0 and take >= pool.last then
			take += 1
		end
	end
	pool.last = take
	local copies = pool.voices[take]
	pool.at[take] = pool.at[take] % #copies + 1
	local voice = copies[pool.at[take]]
	local sound = voice.sound
	if not sound.IsLoaded and now - voice.born > RETRY_AFTER then
		voice.born = now -- a sound that failed to load is not retried by Roblox: ask again
		sound.SoundId = ""
		sound.SoundId = "rbxassetid://" .. voice.id
	end
	if voice.anchor and position then
		voice.anchor.WorldPosition = position
	end
	local vary = def.vary or 0.06
	sound.Volume = math.min((def.volume or 0.4) * math.clamp(gain or 1, 0, 1.5), 1)
	sound.PlaybackSpeed = (def.speed or 1) * (pitch or 1) * (1 + (rng:NextNumber() - 0.5) * vary)
	sound.TimePosition = if def.region then def.region[1] else 0
	sound:Play() -- on a Sound this starts again from TimePosition
end

-- Sfx.play("Click")   Sfx.play("Coin", Sfx.step(streak))   Sfx.play("Hit", 1, 0.1, 0.5)
function Sfx.play(name: string, pitch: number?, minGap: number?, gain: number?)
	start(name, nil, pitch, minGap, gain)
end

-- The same sound at a place in the world: it fades with distance and is skipped when out of range.
function Sfx.playAt(name: string, position: Vector3, pitch: number?, minGap: number?, gain: number?)
	start(name, position, pitch, minGap, gain)
end

-- Pitch for step n of a streak or a rarity ladder: one semitone a step, capped so it never goes shrill.
function Sfx.step(n: number): number
	return 2 ^ (math.clamp(n, 0, 7) / 12)
end

-- Builds the copies now so the first play is not late. Sfx.preload() = all; or pass the names needed first.
function Sfx.preload(names: { string }?)
	task.spawn(function()
		for name, def in Sfx.Sounds do
			if not names or table.find(names, name) then
				getPool(name, name, def, false)
			end
		end
	end)
end

return Sfx
