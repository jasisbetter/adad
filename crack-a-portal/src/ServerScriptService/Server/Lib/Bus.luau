--!strict
-- Bus: cross-system server events (PLAN.md section 8). Each handler runs in its own thread
-- with pcall, so one broken handler never stops the others or the system that fired.

local Bus = {}

-- The only valid event names (PLAN.md section 8), with their arguments.
Bus.Events = {
	MonsterBeaten = true, -- (player, monsterId, mode)
	BossBeaten = true, -- (player, monsterId, mode)
	OpeningStarted = true, -- (player, kind, rarity)
	WaveStarted = true, -- (player, wave, kind, rarity)
	WaveCleared = true, -- (player, wave)
	PotClosed = true, -- (player, coins, itemCount, recovered)
	Fell = true, -- (player, wave)
	ItemGained = true, -- (player, item)
	ItemMerged = true, -- (player, item)
	KeyGained = true, -- (player, kind, rarity, source)
	PortalLevel = true, -- (player, level)
	RiftHelped = true, -- (player)
} :: { [string]: boolean }

type Handler = (...any) -> ()

local handlers: { [string]: { Handler } } = {}
local warnedUnknown: { [string]: boolean } = {}

local function checkName(name: string): boolean
	if Bus.Events[name] then
		return true
	end
	if not warnedUnknown[name] then
		warnedUnknown[name] = true
		warn(`[Bus] unknown event "{name}" (see PLAN.md section 8)`)
	end
	return false
end

-- Hoisted so fire() makes no closures.
local function run(name: string, fn: Handler, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[Bus] {name} handler error: {err}`)
	end
end

-- Subscribes; returns a function that unsubscribes.
function Bus.on(name: string, fn: Handler): () -> ()
	checkName(name)
	local list = handlers[name]
	if not list then
		list = {}
		handlers[name] = list
	end
	table.insert(list, fn)
	local connected = true
	return function()
		if not connected then
			return
		end
		connected = false
		local current = handlers[name]
		local index = current and table.find(current, fn)
		if current and index then
			-- copy on write, so a fire() walking the old list is not shifted
			local copy = table.clone(current)
			table.remove(copy, index)
			handlers[name] = copy
		end
	end
end

function Bus.fire(name: string, ...: any)
	if not checkName(name) then
		return
	end
	local list = handlers[name]
	if not list or #list == 0 then
		return
	end
	-- unsubscribing replaces the list, so this walk is never shifted; new handlers wait for the next fire
	local count = #list
	for i = 1, count do
		task.spawn(run, name, list[i], ...)
	end
end

return Bus
