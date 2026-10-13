--!strict
-- Save: the only module that touches the players' DataStore (PLAN.md section 10).
-- DataStore "CrackAPortal_Players_v1", key "p_<UserId>", record { data, lock = { job, at }, savedAt }.
-- load() claims a session lock with UpdateAsync and migrates; save() writes and refreshes or
-- releases the lock, only while this server holds it. Nothing is written for a player until
-- PlayerData calls markLoaded(); before that a release only clears our lock (data untouched).
-- Modes: "datastore" (live, and Studio with API access), "memory" (Studio without API access,
-- one warning), "temp" (Studio with workspace attribute StudioTempData: fresh, never saved).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local SaveSchema = require(script.Parent.Parent.Lib.SaveSchema)

type Profile = SaveSchema.Profile
export type Mode = "datastore" | "memory" | "temp"

local Save = {}

local STORE_NAME = "CrackAPortal_Players_v1"
local LOCK_STALE = 150 -- seconds; autosave every 60 s keeps a live lock fresh
local BACKOFF = { 1, 2, 4, 8 } -- waits between the 5 tries of every DataStore call
local LOCK_RETRIES = 5 -- another server holds a fresh lock: try again this many times
local LOCK_WAIT = 3

local IS_STUDIO = RunService:IsStudio()
local JOB = "studio" -- set to game.JobId in init (empty in Studio)

type Entry = {
	profile: Profile?,
	loaded: boolean, -- PlayerData finished loading: saves may write data
	claimed: boolean, -- we wrote our lock into the record
	noSave: boolean, -- temp profile (temp mode, UserId <= 0, Studio fallback)
	busy: boolean, -- a write is running (writes for one player never overlap)
}

local state = {
	mode = (if IS_STUDIO then "memory" else "datastore") :: Mode,
	ready = false,
	store = nil :: DataStore?,
	entries = {} :: { [Player]: Entry },
	memory = {} :: { [number]: string }, -- memory mode: JSON per UserId (kept for this session only)
}

local function keyOf(userId: number): string
	return `p_{userId}`
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Runs fn with pcall, 5 tries with 1/2/4/8 s backoff. Stops early when `alive` says no.
local function withRetry(label: string, fn: () -> (), alive: (() -> boolean)?): (boolean, string?)
	local lastErr: string? = nil
	for attempt = 1, #BACKOFF + 1 do
		local ok, err = pcall(fn)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		warn(`[Save] {label} try {attempt}/{#BACKOFF + 1} failed: {lastErr}`)
		if attempt <= #BACKOFF then
			task.wait(BACKOFF[attempt])
			if alive and not alive() then
				return false, "left"
			end
		end
	end
	return false, lastErr
end

local function getStore(): DataStore?
	if state.store then
		return state.store
	end
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok and store then
		state.store = store
		return store
	end
	return nil
end

local function waitReady()
	local started = os.clock()
	while not state.ready and os.clock() - started < 30 do
		task.wait(0.1)
	end
end

local function entryOf(player: Player): Entry
	local entry = state.entries[player]
	if not entry then
		entry = { profile = nil, loaded = false, claimed = false, noSave = false, busy = false }
		state.entries[player] = entry
	end
	return entry
end

local function lockFresh(lock: any, now: number): boolean
	return type(lock) == "table" and type(lock.job) == "string" and isFinite(lock.at) and now - lock.at < LOCK_STALE
end

local function storedVersion(data: any): number
	if type(data) == "table" and isFinite(data.version) then
		return data.version
	end
	return 0
end

local function waitIdle(entry: Entry)
	local started = os.clock()
	while entry.busy and os.clock() - started < 60 do
		task.wait(0.1)
	end
end

---------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------

function Save.mode(): Mode
	return state.mode
end

-- (true, profile) on success; (false, nil, reason) with reason "locked" | "future" | "left" | "error".
function Save.load(player: Player): (boolean, Profile?, string?)
	waitReady()
	local entry = entryOf(player)
	local userId = player.UserId
	local mode = state.mode

	if mode == "temp" or userId <= 0 then
		entry.noSave = true
		local profile = SaveSchema.default()
		entry.profile = profile
		return true, profile, nil
	end

	if mode == "memory" then
		local raw = state.memory[userId]
		local data: any = nil
		if raw then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
			data = if ok then decoded else nil
		end
		local profile, future = SaveSchema.migrate(data)
		if future then
			return false, nil, "future"
		end
		entry.profile = profile
		return true, profile, nil
	end

	local function alive(): boolean
		return player.Parent ~= nil
	end

	for lockTry = 1, LOCK_RETRIES do
		local store = getStore()
		local result: string = "error"
		local captured: any = nil
		local ok = false
		if store then
			ok = withRetry(`load {userId}`, function()
				store:UpdateAsync(keyOf(userId), function(old: any): any
					local now = os.time()
					local record: { [string]: any } = if type(old) == "table" then old else {}
					local lock = record.lock
					if lockFresh(lock, now) and lock.job ~= JOB then
						result = "locked"
						return nil
					end
					if storedVersion(record.data) > SaveSchema.VERSION then
						result = "future"
						return nil
					end
					captured = record.data
					record.lock = { job = JOB, at = now }
					result = "claimed"
					return record
				end)
			end, alive)
		end
		if not alive() then
			-- if the lock got claimed, release it with the stored data untouched
			if ok and result == "claimed" then
				entry.claimed = true
				Save.save(player, SaveSchema.default(), true)
			end
			state.entries[player] = nil
			return false, nil, "left"
		end
		if ok and result == "claimed" then
			local profile, future = SaveSchema.migrate(captured)
			entry.claimed = true
			if future then
				-- cannot happen (checked in the transform), but never play on a future profile
				Save.save(player, profile, true)
				return false, nil, "future"
			end
			entry.profile = profile
			return true, profile, nil
		end
		if ok and result == "future" then
			return false, nil, "future"
		end
		if not ok or result ~= "locked" then
			return false, nil, "error"
		end
		if lockTry < LOCK_RETRIES then
			task.wait(LOCK_WAIT)
			if not alive() then
				state.entries[player] = nil
				return false, nil, "left"
			end
		end
	end
	return false, nil, "locked"
end

-- Loading is finished (PlayerData set session.loaded): from now on saves write data.
function Save.markLoaded(player: Player)
	local entry = state.entries[player]
	if entry then
		entry.loaded = true
	end
end

-- Profiles that never save (temp mode, UserId <= 0, Studio load fallback).
function Save.markTemp(player: Player, profile: Profile)
	local entry = entryOf(player)
	entry.noSave = true
	entry.profile = profile
end

function Save.isTemp(player: Player): boolean
	local entry = state.entries[player]
	return entry == nil or entry.noSave
end

-- Writes the profile and refreshes the lock, or clears it when `release` (the entry is then
-- forgotten). Before markLoaded only a release runs, and it never touches the stored data.
-- Returns (success, reason?) with reason "lost" when another server holds the lock.
function Save.save(player: Player, profile: Profile, release: boolean): (boolean, string?)
	local entry = state.entries[player]
	if not entry then
		return false, "unknown"
	end
	if entry.noSave or player.UserId <= 0 or state.mode == "temp" then
		if release then
			state.entries[player] = nil
		end
		return true, nil
	end
	if not entry.loaded and not release then
		return false, "notLoaded"
	end
	local writeData = entry.loaded
	if writeData then
		entry.profile = profile
	end

	waitIdle(entry)
	entry.busy = true
	local userId = player.UserId
	local success, reason = false, nil :: string?

	if state.mode == "memory" then
		if writeData then
			local ok, encoded = pcall(HttpService.JSONEncode, HttpService, profile)
			if ok then
				state.memory[userId] = encoded
				success = true
			else
				reason = "encode"
				warn(`[Save] memory save {userId} failed: {encoded}`)
			end
		else
			success = true
		end
	elseif not entry.claimed then
		success = not writeData -- nothing claimed: nothing to release; a data write is refused
		reason = if writeData then "notClaimed" else nil
	else
		local store = getStore()
		local outcome = "error"
		if store then
			local ok = withRetry(`save {userId}`, function()
				store:UpdateAsync(keyOf(userId), function(old: any): any
					local now = os.time()
					local record: { [string]: any } = if type(old) == "table" then old else {}
					local lock = record.lock
					if type(lock) == "table" and lock.job ~= JOB then
						-- another server holds the lock (ours went stale and it claimed it): never overwrite
						outcome = "lost"
						return nil
					end
					if writeData then
						if storedVersion(record.data) > SaveSchema.VERSION then
							outcome = "future"
							return nil
						end
						record.data = profile
						record.savedAt = now
					end
					record.lock = if release then nil else { job = JOB, at = now }
					outcome = "saved"
					return record
				end)
			end)
			if not ok then
				outcome = "error"
			end
		end
		success = outcome == "saved"
		reason = if success then nil else outcome
		if not success then
			warn(`[Save] save {userId} did not write ({outcome})`)
		end
	end

	entry.busy = false
	if release then
		state.entries[player] = nil
	end
	return success, reason
end

-- Immediate save for purchases (Receipts): true only when the data was written.
function Save.saveNow(player: Player): boolean
	local entry = state.entries[player]
	if not entry or not entry.loaded or not entry.profile then
		return false
	end
	if entry.noSave or state.mode == "temp" then
		return true -- Studio test profile: nothing to keep
	end
	local ok = Save.save(player, entry.profile, false)
	return ok
end

-- Drops what Save knows about a player (after the final save, or a failed load).
function Save.forget(player: Player)
	state.entries[player] = nil
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------

function Save.init()
	if game.JobId ~= "" then
		JOB = game.JobId
	end
	if IS_STUDIO and workspace:GetAttribute(Config.Studio.tempDataAttribute) == true then
		state.mode = "temp"
		state.ready = true
		warn("[Save] StudioTempData is on: every player gets a fresh temporary profile that never saves.")
	elseif not IS_STUDIO then
		-- a live server always uses the DataStore; a failed load kicks, never falls back to memory
		state.mode = "datastore"
		state.ready = true
		getStore()
	end
end

function Save.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		-- safety net: PlayerData releases first; anything left after a minute is dropped
		task.delay(60, function()
			local entry = state.entries[player]
			if entry and not entry.busy then
				state.entries[player] = nil
			end
		end)
	end)
	if state.ready then
		return
	end
	-- Studio: probe once; without API access run on memory saves (one warning)
	local ok, err = pcall(function()
		local store = DataStoreService:GetDataStore(STORE_NAME)
		store:GetAsync("probe")
		state.store = store
	end)
	if ok then
		state.mode = "datastore"
	else
		state.mode = "memory"
		warn(
			"[Save] DataStores are not available in Studio ("
				.. tostring(err)
				.. "). Running on MEMORY saves: nothing is kept after this test. "
				.. "Turn on Game Settings > Security > Enable Studio Access to API Services to test real saving."
		)
	end
	state.ready = true
end

return Save
