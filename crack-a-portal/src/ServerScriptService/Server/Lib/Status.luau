--!strict
-- Status: timed effects on monsters (keyed by their Mon table) and players (keyed by Player).
--   stagger: stops movement and interrupts a wind-up (owners read isStaggered / the handler)
--   burn:    damage over time, ticked at 4 Hz through the handler set with setBurnHandler
--   slow:    speed multiplier (1 - amount)
-- Times are server time (workspace:GetServerTimeNow()), so clients can compare the Burn /
-- Slow / Stagger attributes (expiry times) with their own GetServerTimeNow().
-- Owners call Status.tick() at 4-10 Hz. No allocation per tick.

local Workspace = game:GetService("Workspace")

local Status = {}

local BURN_INTERVAL = 0.25 -- 4 Hz
local MIN_SPEED = 0.1

export type Kind = "stagger" | "burn" | "slow"
export type Params = {
	duration: number,
	amount: number?, -- slow: 0..1 speed cut
	dps: number?, -- burn: damage per second (already scaled by the caller)
	source: any?, -- burn: who gets credit (a Player), passed to the burn handler
}

type Entry = {
	host: Instance?, -- the model (monsters) or the Player that carries the attributes
	staggerUntil: number,
	slowUntil: number,
	slowAmount: number,
	burnUntil: number,
	burnDps: number,
	nextBurn: number,
	burnSource: any?,
}

local entries: { [any]: Entry } = {}
local burnHandler: ((target: any, amount: number, source: any?) -> ())? = nil
local staggerHandler: ((target: any, duration: number) -> ())? = nil

function Status.now(): number
	return Workspace:GetServerTimeNow()
end

-- fn(target, damage, source) deals burn damage (Monsters.damage or Combat.damagePlayer).
function Status.setBurnHandler(fn: (target: any, amount: number, source: any?) -> ())
	burnHandler = fn
end

-- fn(target, duration) runs when a stagger lands (Monsters uses it to cancel a wind-up at once).
function Status.setStaggerHandler(fn: (target: any, duration: number) -> ())
	staggerHandler = fn
end

local function hostOf(target: any): Instance?
	if typeof(target) == "Instance" then
		return target
	end
	if type(target) == "table" then
		local model = target.model
		if typeof(model) == "Instance" then
			return model
		end
	end
	return nil
end

local function setAttr(entry: Entry, name: string, value: number?)
	local host = entry.host
	if host and host.Parent ~= nil then
		if host:GetAttribute(name) ~= value then
			host:SetAttribute(name, value)
		end
	end
end

local function entryFor(target: any): Entry
	local entry = entries[target]
	if not entry then
		entry = {
			host = hostOf(target),
			staggerUntil = 0,
			slowUntil = 0,
			slowAmount = 0,
			burnUntil = 0,
			burnDps = 0,
			nextBurn = 0,
			burnSource = nil,
		}
		entries[target] = entry
	end
	return entry
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Status.apply(target: any, kind: Kind, params: Params)
	if target == nil or type(params) ~= "table" or not finite(params.duration) or params.duration <= 0 then
		return
	end
	local now = Status.now()
	local entry = entryFor(target)
	local untilTime = now + params.duration
	if kind == "stagger" then
		if untilTime > entry.staggerUntil then
			entry.staggerUntil = untilTime
			setAttr(entry, "Stagger", untilTime)
		end
		if staggerHandler then
			local ok, err = pcall(staggerHandler, target, params.duration)
			if not ok then
				warn(`[Status] stagger handler error: {err}`)
			end
		end
	elseif kind == "slow" then
		local amount = if finite(params.amount) then math.clamp(params.amount :: number, 0, 1 - MIN_SPEED) else 0.3
		if entry.slowUntil <= now then
			entry.slowAmount = amount
		else
			entry.slowAmount = math.max(entry.slowAmount, amount)
		end
		if untilTime > entry.slowUntil then
			entry.slowUntil = untilTime
			setAttr(entry, "Slow", untilTime)
		end
	elseif kind == "burn" then
		local dps = if finite(params.dps) then math.max(0, params.dps :: number) else 0
		if dps <= 0 then
			return
		end
		if entry.burnUntil <= now then
			entry.burnDps = dps
			entry.nextBurn = now + BURN_INTERVAL
		else
			entry.burnDps = math.max(entry.burnDps, dps)
		end
		entry.burnSource = params.source
		if untilTime > entry.burnUntil then
			entry.burnUntil = untilTime
			setAttr(entry, "Burn", untilTime)
		end
	end
end

function Status.isStaggered(target: any): boolean
	local entry = entries[target]
	return entry ~= nil and entry.staggerUntil > Status.now()
end

-- 0 while staggered, 1 - slow amount while slowed, else 1.
function Status.speedMult(target: any): number
	local entry = entries[target]
	if not entry then
		return 1
	end
	local now = Status.now()
	if entry.staggerUntil > now then
		return 0
	end
	if entry.slowUntil > now then
		return math.max(MIN_SPEED, 1 - entry.slowAmount)
	end
	return 1
end

-- True when the target has any effect still running.
function Status.has(target: any, kind: Kind): boolean
	local entry = entries[target]
	if not entry then
		return false
	end
	local now = Status.now()
	if kind == "stagger" then
		return entry.staggerUntil > now
	elseif kind == "slow" then
		return entry.slowUntil > now
	end
	return entry.burnUntil > now
end

function Status.clear(target: any)
	local entry = entries[target]
	if not entry then
		return
	end
	entries[target] = nil
	setAttr(entry, "Stagger", nil)
	setAttr(entry, "Slow", nil)
	setAttr(entry, "Burn", nil)
end

local function gone(target: any, entry: Entry): boolean
	if type(target) == "table" and target.alive == false then
		return true
	end
	local host = entry.host
	return host ~= nil and host.Parent == nil
end

-- Hoisted so tick() makes no closures.
local function runBurn(target: any, amount: number, source: any?)
	local handler = burnHandler
	if not handler then
		return
	end
	local ok, err = pcall(handler, target, amount, source)
	if not ok then
		warn(`[Status] burn handler error: {err}`)
	end
end

-- Expires effects and deals burn ticks. `now` defaults to Status.now().
function Status.tick(now: number?)
	local t = now or Status.now()
	for target, entry in entries do
		if gone(target, entry) then
			entries[target] = nil
			continue
		end
		if entry.staggerUntil > 0 and entry.staggerUntil <= t then
			entry.staggerUntil = 0
			setAttr(entry, "Stagger", nil)
		end
		if entry.slowUntil > 0 and entry.slowUntil <= t then
			entry.slowUntil = 0
			entry.slowAmount = 0
			setAttr(entry, "Slow", nil)
		end
		if entry.burnUntil > 0 then
			-- catch up missed ticks (at most a few) so burn damage does not depend on the tick rate
			local ticks = 0
			while entry.nextBurn <= t and entry.nextBurn <= entry.burnUntil + 1e-3 and ticks < 8 do
				ticks += 1
				entry.nextBurn += BURN_INTERVAL
			end
			if ticks > 0 and burnHandler then
				-- deferred: the handler may add or clear entries, which must not happen mid-loop
				task.defer(runBurn, target, entry.burnDps * BURN_INTERVAL * ticks, entry.burnSource)
			end
			if entry.burnUntil <= t then
				entry.burnUntil = 0
				entry.burnDps = 0
				entry.burnSource = nil
				setAttr(entry, "Burn", nil)
			end
		end
		if entry.staggerUntil == 0 and entry.slowUntil == 0 and entry.burnUntil == 0 then
			entries[target] = nil -- nothing left; drop the entry
		end
	end
end

return Status
