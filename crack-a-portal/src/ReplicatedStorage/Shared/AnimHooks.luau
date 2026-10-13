--!strict
-- AnimHooks: plays animation ids from Config through an Animator. Id 0 = not made yet:
-- load() returns nil and the caller runs its code-driven placeholder. Each id gets one
-- Animation object, and each Animator loads each id once (tracks are cached and reused).
-- A fresh track reads Length 0 until the clip arrives; a background check waits for it and
-- reloads a few times before giving up on a broken id (callers keep their placeholder).

export type LoadOpts = {
	priority: Enum.AnimationPriority?,
	looped: boolean?,
}

local AnimHooks = {}

local CHECK_INTERVAL = 0.25
local CHECK_TIME = 3 -- seconds to wait for Length > 0 before a reload
local MAX_RELOADS = 2

local animations: { [number]: Animation } = {}
-- per Animator: id -> track (weak keys so a destroyed Animator can be collected)
local tracks: { [Animator]: { [number]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
local broken: { [number]: boolean } = {}
local destroyConns: { [Animator]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any

local function animationFor(id: number): Animation
	local a = animations[id]
	if not a then
		a = Instance.new("Animation")
		a.Name = `Anim{id}`
		a.AnimationId = `rbxassetid://{id}`
		animations[id] = a
	end
	return a
end

local function applyOpts(track: AnimationTrack, opts: LoadOpts?)
	if opts then
		if opts.priority then
			track.Priority = opts.priority
		end
		if opts.looped ~= nil then
			track.Looped = opts.looped
		end
	end
end

local function rawLoad(animator: Animator, id: number, opts: LoadOpts?): AnimationTrack?
	local ok, result = pcall(animator.LoadAnimation, animator, animationFor(id))
	if not ok or result == nil then
		warn(`[AnimHooks] could not load animation {id}: {result}`)
		return nil
	end
	local track = result :: AnimationTrack
	applyOpts(track, opts)
	return track
end

-- Waits for Length > 0; reloads the track a few times if it never arrives.
local function watchLength(animator: Animator, id: number, opts: LoadOpts?)
	task.spawn(function()
		for attempt = 0, MAX_RELOADS do
			local per = tracks[animator]
			local track = per and per[id]
			if not track then
				return
			end
			local waited = 0
			while track.Length == 0 and waited < CHECK_TIME do
				task.wait(CHECK_INTERVAL)
				waited += CHECK_INTERVAL
				if tracks[animator] ~= per or per[id] ~= track then
					return -- cleared or replaced meanwhile
				end
			end
			if track.Length > 0 then
				return
			end
			if animator.Parent == nil then
				AnimHooks.clear(animator) -- the rig went away; not the id's fault
				return
			end
			if attempt == MAX_RELOADS then
				break
			end
			track:Stop(0)
			track:Destroy()
			per[id] = nil
			local fresh = rawLoad(animator, id, opts)
			if not fresh then
				break
			end
			per[id] = fresh
		end
		warn(`[AnimHooks] animation {id} never loaded (Length 0); placeholder stays`)
		broken[id] = true
		local per = tracks[animator]
		local track = per and per[id]
		if per and track then
			track:Destroy()
			per[id] = nil
		end
	end)
end

-- The cached track for this id on this Animator, or nil (id 0, broken id, load failure).
function AnimHooks.load(animator: Animator, id: number, opts: LoadOpts?): AnimationTrack?
	if id == 0 or id ~= id or broken[id] then
		return nil
	end
	local per = tracks[animator]
	if not per then
		per = {}
		tracks[animator] = per
		destroyConns[animator] = animator.Destroying:Connect(function()
			AnimHooks.clear(animator)
		end)
	end
	local track = per[id]
	if track then
		applyOpts(track, opts)
		return track
	end
	local fresh = rawLoad(animator, id, opts)
	if not fresh then
		return nil
	end
	per[id] = fresh
	if fresh.Length == 0 then
		watchLength(animator, id, opts)
	end
	return fresh
end

-- True when the track's clip has arrived (Length > 0).
function AnimHooks.ready(track: AnimationTrack?): boolean
	return track ~= nil and track.Length > 0
end

function AnimHooks.play(track: AnimationTrack, fade: number?, weight: number?, speed: number?)
	track:Play(fade or 0.1, weight or 1, speed or 1)
end

-- Fires fn when the track reaches the named marker (connect once per track, not per play).
function AnimHooks.onMarker(track: AnimationTrack, name: string, fn: (param: string) -> ()): RBXScriptConnection
	return track:GetMarkerReachedSignal(name):Connect(fn)
end

function AnimHooks.stopAll(animator: Animator, fade: number?)
	local per = tracks[animator]
	if not per then
		return
	end
	for _, track in per do
		track:Stop(fade or 0.1)
	end
end

-- Drops every cached track of this Animator (call when the model is destroyed or pooled away).
function AnimHooks.clear(animator: Animator)
	local per = tracks[animator]
	tracks[animator] = nil
	if per then
		for _, track in per do
			track:Stop(0)
			track:Destroy()
		end
	end
	local conn = destroyConns[animator]
	if conn then
		destroyConns[animator] = nil
		conn:Disconnect()
	end
end

-- The Animator inside a model's AnimationController or Humanoid, or nil.
function AnimHooks.animatorOf(model: Instance): Animator?
	local host = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
	return if host then host:FindFirstChildOfClass("Animator") else nil
end

return AnimHooks
