--!strict
-- SaveSchema: the saved profile (PLAN.md section 10). default() gives a fresh profile,
-- migrate() turns anything loaded from the DataStore into a valid current profile.
-- Pure: no services. The pot and opening state are never part of the profile.

local Receipts = require(script.Parent.Receipts)

local SaveSchema = {}

SaveSchema.VERSION = 1

-- Sane ranges (generous so a later Config change never clamps real progress away).
local MAX_COINS = 1e15
local MAX_COUNT = 1e12
local MAX_KEYS = 9999
local MAX_LEVEL = 999
local MAX_ITEMS_KEPT = 150
local MAX_STRING = 64
local MAX_QUESTS = 10
local MAX_LOSS_ITEMS = 150

export type Item = { id: string, kind: string, type: string, rarity: string, level: number }
export type Settings = { music: number, sfx: number, shake: boolean, reducedMotion: boolean }
export type QuestSlot = { id: string, progress: number, claimed: boolean }
export type Loss = { coins: number, items: { Item }, tier: string, kind: string, at: number }

export type Profile = {
	version: number,
	coins: number,
	items: { Item },
	equipped: { Weapon: string?, Armor: string? },
	nextId: number,
	keys: { [string]: number },
	portalLevel: number,
	index: { monsters: { [string]: boolean }, gear: { [string]: boolean }, claimed: { [string]: boolean } },
	quests: { day: number, list: { QuestSlot } },
	dailyKeyAt: number,
	stats: { highestWave: number, biggestPot: number, monstersBeaten: number, openings: number, bossesBeaten: number },
	boardsSent: { Wave: number, Pot: number },
	settings: Settings,
	tutorialDone: boolean,
	tutorialStep: number,
	tutorialCoins: boolean,
	receipts: { [string]: number },
	pendingLoss: Loss?,
	title: string?,
}

local STAT_NAMES = { "highestWave", "biggestPot", "monstersBeaten", "openings", "bossesBeaten" }

function SaveSchema.default(): Profile
	return {
		version = SaveSchema.VERSION,
		coins = 0,
		items = { { id = "i1", kind = "Ash", type = "Sword", rarity = "Common", level = 1 } },
		equipped = { Weapon = "i1" },
		nextId = 2,
		keys = { ["Ash|Common"] = 1 },
		portalLevel = 1,
		index = { monsters = {}, gear = {}, claimed = {} },
		quests = { day = 0, list = {} },
		dailyKeyAt = 0,
		stats = { highestWave = 0, biggestPot = 0, monstersBeaten = 0, openings = 0, bossesBeaten = 0 },
		boardsSent = { Wave = 0, Pot = 0 },
		settings = { music = 0.6, sfx = 0.8, shake = true, reducedMotion = false },
		tutorialDone = false,
		tutorialStep = 0,
		tutorialCoins = false,
		receipts = {},
		pendingLoss = nil,
		title = nil,
	}
end

---------------------------------------------------------------------------
-- value checks
---------------------------------------------------------------------------

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Whole number in [lo, hi], or the fallback when v is not a finite number.
local function int(v: any, lo: number, hi: number, fallback: number): number
	if not isNumber(v) then
		return fallback
	end
	return math.clamp(math.floor(v), lo, hi)
end

local function num(v: any, lo: number, hi: number, fallback: number): number
	if not isNumber(v) then
		return fallback
	end
	return math.clamp(v, lo, hi)
end

local function bool(v: any, fallback: boolean): boolean
	if type(v) == "boolean" then
		return v
	end
	return fallback
end

local function str(v: any): string?
	if type(v) == "string" and #v > 0 and #v <= MAX_STRING then
		return v
	end
	return nil
end

local function tbl(v: any): { [any]: any }?
	return if type(v) == "table" then v else nil
end

local function cleanItem(v: any): Item?
	local t = tbl(v)
	if not t then
		return nil
	end
	local id, kind, gearType, rarity = str(t.id), str(t.kind), str(t.type), str(t.rarity)
	if not id or not kind or not gearType or not rarity then
		return nil
	end
	return { id = id, kind = kind, type = gearType, rarity = rarity, level = int(t.level, 1, MAX_LEVEL, 1) }
end

local function cleanItems(v: any, limit: number, label: string): { Item }
	local out: { Item } = {}
	local list = tbl(v)
	if not list then
		return out
	end
	local seen: { [string]: boolean } = {}
	local dropped = 0
	for _, raw in ipairs(list) do
		local item = cleanItem(raw)
		if item and not seen[item.id] then
			if #out < limit then
				seen[item.id] = true
				table.insert(out, item)
			else
				dropped += 1
			end
		end
	end
	if dropped > 0 then
		warn(`[SaveSchema] {label}: kept the first {limit} items, dropped {dropped}`)
	end
	return out
end

local function cleanFlags(v: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local t = tbl(v)
	if t then
		for k, flag in t do
			if str(k) and flag == true then
				out[k] = true
			end
		end
	end
	return out
end

-- "Kind|Rarity" -> count; also accepts the nested { Kind = { Rarity = n } } shape.
local function cleanKeys(v: any): { [string]: number }
	local out: { [string]: number } = {}
	local t = tbl(v)
	if not t then
		return out
	end
	local function add(key: string, count: any)
		local n = int(count, 0, MAX_KEYS, 0)
		if n > 0 and string.match(key, "^%w+|%w+$") then
			out[key] = math.min(MAX_KEYS, (out[key] or 0) + n)
		end
	end
	for k, count in t do
		if type(k) == "string" then
			local nested = tbl(count)
			if nested then
				for rarity, n in nested do
					if type(rarity) == "string" then
						add(`{k}|{rarity}`, n)
					end
				end
			else
				add(k, count)
			end
		end
	end
	return out
end

local function cleanReceipts(v: any): { [string]: number }
	local out: { [string]: number } = {}
	local t = tbl(v)
	if t then
		for id, at in t do
			if type(id) == "string" and #id > 0 and #id <= 128 then
				out[id] = num(at, 0, MAX_COUNT * 1000, 0)
			end
		end
	end
	Receipts.trim(out)
	return out
end

local function cleanLoss(v: any): Loss?
	local t = tbl(v)
	if not t then
		return nil
	end
	local tier, kind = str(t.tier), str(t.kind)
	if not tier or not kind then
		return nil
	end
	return {
		coins = int(t.coins, 0, MAX_COINS, 0),
		items = cleanItems(t.items, MAX_LOSS_ITEMS, "pendingLoss"),
		tier = tier,
		kind = kind,
		at = num(t.at, 0, MAX_COUNT * 1000, 0),
	}
end

local function idNumber(id: string): number
	local n = tonumber(string.match(id, "^i(%d+)$"))
	return n or 0
end

---------------------------------------------------------------------------
-- sanitize: a fresh current profile built from whatever was loaded
---------------------------------------------------------------------------

function SaveSchema.sanitize(data: any): Profile
	local src = tbl(data) or {}
	local p = SaveSchema.default()

	p.coins = int(src.coins, 0, MAX_COINS, 0)

	if src.items ~= nil then
		p.items = cleanItems(src.items, MAX_ITEMS_KEPT, "items")
	end
	local ids: { [string]: Item } = {}
	local highest = 0
	for _, item in p.items do
		ids[item.id] = item
		highest = math.max(highest, idNumber(item.id))
	end
	p.nextId = math.max(int(src.nextId, 1, MAX_COUNT, 1), highest + 1)

	local eq = tbl(src.equipped)
	if eq or src.items ~= nil then
		local weapon = eq and str(eq.Weapon)
		local armor = eq and str(eq.Armor)
		p.equipped = {
			Weapon = if weapon and ids[weapon] then weapon else nil,
			Armor = if armor and ids[armor] and armor ~= weapon then armor else nil,
		}
	end

	if src.keys ~= nil then
		p.keys = cleanKeys(src.keys)
	end
	p.portalLevel = int(src.portalLevel, 1, MAX_LEVEL, 1)

	local index = tbl(src.index)
	if index then
		p.index = {
			monsters = cleanFlags(index.monsters),
			gear = cleanFlags(index.gear),
			claimed = cleanFlags(index.claimed),
		}
	end

	local quests = tbl(src.quests)
	if quests then
		local list: { QuestSlot } = {}
		local raw = tbl(quests.list)
		if raw then
			for _, q in ipairs(raw) do
				local slot = tbl(q)
				local id = slot and str(slot.id)
				if slot and id and #list < MAX_QUESTS then
					table.insert(list, {
						id = id,
						progress = num(slot.progress, 0, MAX_COUNT, 0),
						claimed = bool(slot.claimed, false),
					})
				end
			end
		end
		p.quests = { day = int(quests.day, 0, MAX_COUNT, 0), list = list }
	end

	p.dailyKeyAt = num(src.dailyKeyAt, 0, MAX_COUNT * 1000, 0)

	local stats = tbl(src.stats)
	if stats then
		for _, name in STAT_NAMES do
			(p.stats :: any)[name] = int(stats[name], 0, MAX_COUNT, 0)
		end
	end

	local boards = tbl(src.boardsSent)
	if boards then
		p.boardsSent = { Wave = int(boards.Wave, 0, MAX_COUNT, 0), Pot = int(boards.Pot, 0, MAX_COINS, 0) }
	end

	local settings = tbl(src.settings)
	if settings then
		local d = p.settings
		p.settings = {
			music = num(settings.music, 0, 1, d.music),
			sfx = num(settings.sfx, 0, 1, d.sfx),
			shake = bool(settings.shake, d.shake),
			reducedMotion = bool(settings.reducedMotion, d.reducedMotion),
		}
	end

	p.tutorialDone = bool(src.tutorialDone, false)
	p.tutorialStep = int(src.tutorialStep, 0, 99, 0)
	p.tutorialCoins = bool(src.tutorialCoins, false)
	p.receipts = cleanReceipts(src.receipts)
	p.pendingLoss = cleanLoss(src.pendingLoss)
	p.title = str(src.title)
	p.version = SaveSchema.VERSION
	return p
end

---------------------------------------------------------------------------
-- migrations: MIGRATIONS[v] turns a version-v table into version v + 1
---------------------------------------------------------------------------

SaveSchema.MIGRATIONS = {
	-- v0: the grey test's session table (coins, keys, items, equipped, nextId; nothing else).
	[0] = function(old: { [any]: any }): { [any]: any }
		local out: { [any]: any } = {
			version = 1,
			coins = old.coins,
			keys = old.keys,
			items = old.items,
			equipped = old.equipped,
			nextId = old.nextId,
		}
		-- grey-test players have played: skip the tutorial and its free key
		if old.items ~= nil then
			out.tutorialDone = true
		end
		return out
	end,
} :: { [number]: (data: { [any]: any }) -> { [any]: any } }

-- Returns a valid current profile and `future`: true when the data was saved by a newer
-- version of the game. A future profile is returned untouched and must never be saved over.
function SaveSchema.migrate(data: any): (Profile, boolean)
	local t = tbl(data)
	if not t then
		return SaveSchema.default(), false
	end
	local version = if isNumber(t.version) then math.floor(t.version) else 0
	if version > SaveSchema.VERSION then
		return t :: any, true
	end
	if version < 0 then
		version = 0
	end
	local current: { [any]: any } = t
	while version < SaveSchema.VERSION do
		local step = SaveSchema.MIGRATIONS[version]
		if step then
			local ok, result = pcall(step, current)
			if ok and type(result) == "table" then
				current = result
			else
				warn(`[SaveSchema] migration from v{version} failed: {result}`)
			end
		end
		version += 1
	end
	return SaveSchema.sanitize(current), false
end

return SaveSchema
