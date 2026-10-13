--!strict
-- PlayerData: the in-memory session per player (PLAN.md section 7) and the only way other
-- systems change a profile. Loads through Save (kick on failure on a live server), keeps the
-- custom HP, sends the Profile snapshot (coalesced, at most ~5/s), autosaves every 60 s,
-- runs onLeaving hooks before the final save, and saves everyone on shutdown.
-- Equipment changes fire PlayerData.equipChanged (Appearance listens; PlayerData never
-- requires Appearance, so there is no cycle).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local Bus = require(Server.Lib.Bus)
local SaveSchema = require(Server.Lib.SaveSchema)
local RateLimit = require(script.Parent.RateLimit)
local Save = require(script.Parent.Save)
local Notify = require(script.Parent.Notify)

type Profile = SaveSchema.Profile
type Item = Types.Item
type PublicProfile = Types.PublicProfile

export type Session = {
	player: Player,
	profile: Profile,
	loaded: boolean,
	hp: number,
	maxHp: number,
	damage: number,
	invulnUntil: number,
	lastHurt: number,
	lastAttack: number,
	comboStep: number,
	dodgeReadyAt: number,
	passes: { DoubleCoins: boolean, LuckierKeys: boolean },
	noPaidRandom: boolean,
	tutorial: { step: number, coinsGiven: boolean },
}

-- Internal per-player state (never handed out).
type Inner = {
	nextSave: number,
	snapshotQueued: boolean,
	lastSnapshot: number,
	finalizing: boolean,
	finalized: boolean,
	left: boolean,
	pendingSettings: { [string]: any },
	settingsQueued: boolean,
	conns: { RBXScriptConnection },
	charConns: { RBXScriptConnection },
}

local PlayerData = {}

-- Fired with (player) whenever the equipped weapon or armour may have changed.
PlayerData.equipChanged = Signal.new() :: Signal.Signal<Player>

local AUTOSAVE = 60
local AUTOSAVE_STAGGER = 30 -- first autosave lands 60 + (UserId % 30) s after loading
local SNAPSHOT_GAP = 0.2 -- at most ~5 Profile snapshots per second
local CLOSE_WAIT = 25
local MAX_COINS = 1e15
local MAX_KEYS = 9999
local SETTING_RETRY = 0.5 -- a rate-limited setting is applied after this (newest value wins)

local KICK_FAILED = "Your progress couldn't load right now, so we stopped to keep it safe. Please rejoin in a moment."
local KICK_LOCKED = "Your progress is still saving on another server. Please rejoin in a moment."
local KICK_FUTURE = "Your progress was saved by a newer version of the game. Please rejoin to get the newest server."
local KICK_LOST = "Your progress was opened on another server, so this one stopped saving it. Please rejoin."

local IS_STUDIO = RunService:IsStudio()

local sessions: { [Player]: Session } = {}
local inner: { [Player]: Inner } = {}
local loadedHooks: { (Player) -> () } = {}
local leavingHooks: { (Player) -> () } = {}
local readyHooks: { (Player) -> () } = {}
local profileRemote: RemoteEvent? = nil

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function hook(list: { (Player) -> () }, fn: (Player) -> ())
	table.insert(list, fn)
end

local function runHooks(list: { (Player) -> () }, player: Player, label: string)
	for _, fn in list do
		local ok, err = pcall(fn, player)
		if not ok then
			warn(`[PlayerData] {label} hook error: {err}`)
		end
	end
end

local function keyId(kind: string, rarity: string): string
	return `{kind}|{rarity}`
end

local function itemIndex(profile: Profile, id: string): number?
	for i, item in profile.items do
		if item.id == id then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- profile clean-up after loading (Config-aware; SaveSchema only checks shapes)
---------------------------------------------------------------------------

-- Drops items whose kind, type or rarity is not in Config, clamps item levels to
-- Logic.maxLevel and portalLevel to Config.Portal.maxLevel, drops unknown keys and
-- equipped ids that are missing or in the wrong slot. Mutates and returns the profile.
function PlayerData.cleanProfile(profile: Profile): Profile
	local items: { Item } = {}
	for _, item in profile.items do
		if Config.KeyKinds[item.kind] and Config.GearTypes[item.type] and Config.RarityById[item.rarity] then
			item.level = math.clamp(math.floor(item.level), 1, Logic.maxLevel(item.rarity))
			table.insert(items, item)
		end
	end
	profile.items = items
	local byId: { [string]: Item } = {}
	for _, item in items do
		byId[item.id] = item
	end
	local equipped: { [string]: string } = profile.equipped :: any
	for _, slot in { "Weapon", "Armor" } do
		local id = equipped[slot]
		local item = id and byId[id]
		if id and (not item or Logic.itemSlot(item) ~= slot) then
			equipped[slot] = nil
		end
	end
	local keys: { [string]: number } = {}
	for key, count in profile.keys do
		local kind, rarity = string.match(key, "^(%w+)|(%w+)$")
		if kind and rarity and Config.KeyKinds[kind] and Config.KeyRarities[rarity] and count > 0 then
			keys[key] = math.clamp(math.floor(count), 0, MAX_KEYS)
		end
	end
	profile.keys = keys
	profile.portalLevel = math.clamp(math.floor(profile.portalLevel), 1, Config.Portal.maxLevel)
	profile.coins = math.clamp(math.floor(profile.coins), 0, MAX_COINS)
	return profile
end

---------------------------------------------------------------------------
-- session access
---------------------------------------------------------------------------

-- The loaded session, or nil (not loaded yet, failed, or gone).
function PlayerData.get(player: Player): Session?
	local session = sessions[player]
	if session and session.loaded then
		return session
	end
	return nil
end

function PlayerData.waitLoaded(player: Player, timeout: number?): Session?
	local limit = os.clock() + (timeout or 30)
	while os.clock() < limit do
		local session = sessions[player]
		if session and session.loaded then
			return session
		end
		if player.Parent ~= Players or (inner[player] and inner[player].left) then
			return nil
		end
		task.wait(0.1)
	end
	return PlayerData.get(player)
end

function PlayerData.onLoaded(fn: (Player) -> ())
	hook(loadedHooks, fn)
	-- players who loaded before the hook was added get it too
	for player, session in sessions do
		if session.loaded then
			task.spawn(function()
				local ok, err = pcall(fn, player)
				if not ok then
					warn(`[PlayerData] onLoaded hook error: {err}`)
				end
			end)
		end
	end
end

function PlayerData.onLeaving(fn: (Player) -> ())
	hook(leavingHooks, fn)
end

function PlayerData.onReady(fn: (Player) -> ())
	hook(readyHooks, fn)
end

---------------------------------------------------------------------------
-- snapshot
---------------------------------------------------------------------------

local function build(session: Session): PublicProfile
	local p = session.profile
	local now = os.time()
	local level = p.portalLevel
	local weapon = p.equipped.Weapon
	local armor = p.equipped.Armor
	return {
		coins = p.coins,
		portalLevel = level,
		keys = p.keys,
		items = p.items,
		equipped = { Weapon = weapon, Armor = armor },
		unlocked = Logic.unlockedKinds(level),
		bestKind = Logic.bestKind(level),
		stats = p.stats,
		settings = p.settings,
		quests = {
			day = p.quests.day,
			list = p.quests.list,
			resetAt = (Logic.dayNumber(now) + 1) * Config.Daily.keyEvery,
		},
		index = p.index,
		dailyReadyAt = p.dailyKeyAt + Config.Daily.keyEvery,
		tutorialDone = p.tutorialDone,
		tutorialStep = p.tutorialStep,
		passes = { DoubleCoins = session.passes.DoubleCoins, LuckierKeys = session.passes.LuckierKeys },
		noPaidRandom = session.noPaidRandom,
		title = p.title,
		invCap = Config.Inventory.cap,
		serverTime = workspace:GetServerTimeNow(),
		pendingLoss = p.pendingLoss,
		maxHp = session.maxHp,
		damage = session.damage,
	}
end

local function sendNow(player: Player)
	local session = PlayerData.get(player)
	local state = inner[player]
	if not session or not state or player.Parent ~= Players then
		return
	end
	state.snapshotQueued = false
	state.lastSnapshot = os.clock()
	local remote = profileRemote or Net.find("Profile")
	profileRemote = remote
	if remote then
		remote:FireClient(player, build(session))
	end
end

-- Schedules one Profile snapshot (coalesced with task.defer, at most ~5/s).
function PlayerData.snapshot(player: Player)
	local state = inner[player]
	if not state or state.snapshotQueued then
		return
	end
	state.snapshotQueued = true
	local wait = SNAPSHOT_GAP - (os.clock() - state.lastSnapshot)
	if wait > 0 then
		task.delay(wait, sendNow, player)
	else
		task.defer(sendNow, player)
	end
end

-- Call after changing session.profile directly (the API functions call it themselves).
function PlayerData.markDirty(player: Player)
	PlayerData.snapshot(player)
end

---------------------------------------------------------------------------
-- health and derived stats
---------------------------------------------------------------------------

local function writeHp(session: Session)
	setAttr(session.player, "HP", math.ceil(session.hp))
	setAttr(session.player, "MaxHP", math.ceil(session.maxHp))
end

-- Recomputes max health and damage from the equipped gear (and the PortalLevel attribute).
function PlayerData.recalc(player: Player)
	local session = PlayerData.get(player)
	if not session then
		return
	end
	local p = session.profile
	local weapon = p.equipped.Weapon and PlayerData.findItem(player, p.equipped.Weapon)
	local armor = p.equipped.Armor and PlayerData.findItem(player, p.equipped.Armor)
	local oldMax = session.maxHp
	local newMax = Logic.maxHp(armor or nil)
	session.damage = Logic.weaponDamage(weapon or nil)
	session.maxHp = newMax
	if newMax > oldMax and oldMax > 0 then
		session.hp += newMax - oldMax -- better armour: the extra health is there at once
	end
	session.hp = math.clamp(session.hp, 0, newMax)
	writeHp(session)
	setAttr(player, "PortalLevel", p.portalLevel)
	PlayerData.snapshot(player)
end

function PlayerData.setHp(player: Player, hp: number)
	local session = PlayerData.get(player)
	if not session or not isFinite(hp) then
		return
	end
	session.hp = math.clamp(hp, 0, session.maxHp)
	writeHp(session)
end

function PlayerData.heal(player: Player, n: number)
	local session = PlayerData.get(player)
	if not session or not isFinite(n) or n <= 0 then
		return
	end
	PlayerData.setHp(player, session.hp + n)
end

function PlayerData.fullHeal(player: Player)
	local session = PlayerData.get(player)
	if session then
		PlayerData.setHp(player, session.maxHp)
	end
end

---------------------------------------------------------------------------
-- coins and keys
---------------------------------------------------------------------------

function PlayerData.addCoins(player: Player, n: number, _source: string?)
	local session = PlayerData.get(player)
	if not session or not isFinite(n) or n <= 0 then
		return
	end
	local p = session.profile
	p.coins = math.clamp(math.floor(p.coins + n), 0, MAX_COINS)
	PlayerData.snapshot(player)
end

function PlayerData.spendCoins(player: Player, n: number): boolean
	local session = PlayerData.get(player)
	if not session or not isFinite(n) or n < 0 then
		return false
	end
	local cost = math.ceil(n)
	local p = session.profile
	if p.coins < cost then
		return false
	end
	p.coins -= cost
	PlayerData.snapshot(player)
	return true
end

-- 2 with the 2x Coins pass, else 1.
function PlayerData.coinMult(player: Player): number
	local session = PlayerData.get(player)
	return if session and session.passes.DoubleCoins then 2 else 1
end

function PlayerData.keyCount(player: Player, kind: string, rarity: string): number
	local session = PlayerData.get(player)
	if not session or type(kind) ~= "string" or type(rarity) ~= "string" then
		return 0
	end
	return session.profile.keys[keyId(kind, rarity)] or 0
end

-- Adds keys (fires Bus KeyGained). Effects and pop-ups are the caller's job.
function PlayerData.addKey(player: Player, kind: string, rarity: string, n: number?, source: string?)
	local session = PlayerData.get(player)
	local count = n or 1
	if not session or not Config.KeyKinds[kind] or not Config.KeyRarities[rarity] then
		return
	end
	if not isFinite(count) or count < 1 then
		return
	end
	count = math.floor(count)
	local id = keyId(kind, rarity)
	local keys = session.profile.keys
	keys[id] = math.min(MAX_KEYS, (keys[id] or 0) + count)
	PlayerData.snapshot(player)
	Bus.fire("KeyGained", player, kind, rarity, source or "unknown")
end

function PlayerData.takeKey(player: Player, kind: string, rarity: string): boolean
	local session = PlayerData.get(player)
	if not session or type(kind) ~= "string" or type(rarity) ~= "string" then
		return false
	end
	local id = keyId(kind, rarity)
	local keys = session.profile.keys
	local have = keys[id] or 0
	if have < 1 then
		return false
	end
	keys[id] = if have > 1 then have - 1 else nil
	PlayerData.snapshot(player)
	return true
end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------

function PlayerData.findItem(player: Player, id: string): Item?
	local session = PlayerData.get(player)
	if not session or type(id) ~= "string" then
		return nil
	end
	local i = itemIndex(session.profile, id)
	return if i then session.profile.items[i] else nil
end

-- Adds a copy of `item` with a new id "i<nextId>" and fires Bus ItemGained. Past the
-- inventory cap the item is sold at once for Logic.sellValue (toast) and nil is returned.
function PlayerData.addItem(player: Player, item: Item): Item?
	local session = PlayerData.get(player)
	if not session or type(item) ~= "table" then
		return nil
	end
	if not Config.KeyKinds[item.kind] or not Config.GearTypes[item.type] or not Config.RarityById[item.rarity] then
		return nil
	end
	local p = session.profile
	local level = if isFinite(item.level) then math.clamp(math.floor(item.level), 1, Logic.maxLevel(item.rarity)) else 1
	local copy: Item = { id = `i{p.nextId}`, kind = item.kind, type = item.type, rarity = item.rarity, level = level }
	p.nextId += 1
	if #p.items >= Config.Inventory.cap then
		local coins = Logic.sellValue(copy)
		PlayerData.addCoins(player, coins, "autoSell")
		Notify.toast(
			player,
			`Inventory full: sold {copy.rarity} {Logic.itemName(copy)} for {Logic.short(coins)} coins`,
			"warn"
		)
		Bus.fire("ItemGained", player, copy)
		return nil
	end
	table.insert(p.items, copy)
	PlayerData.snapshot(player)
	Bus.fire("ItemGained", player, copy)
	return copy
end

function PlayerData.removeItem(player: Player, id: string): Item?
	local session = PlayerData.get(player)
	if not session or type(id) ~= "string" then
		return nil
	end
	local p = session.profile
	local i = itemIndex(p, id)
	if not i then
		return nil
	end
	local item = table.remove(p.items, i) :: Item
	local unequipped = false
	if p.equipped.Weapon == id then
		p.equipped.Weapon = nil
		unequipped = true
	end
	if p.equipped.Armor == id then
		p.equipped.Armor = nil
		unequipped = true
	end
	if unequipped then
		PlayerData.recalc(player)
		PlayerData.equipChanged:Fire(player)
	end
	PlayerData.snapshot(player)
	return item
end

-- Equips an owned item in its slot (Economy checks state, e.g. not during an opening).
function PlayerData.equip(player: Player, id: string): boolean
	local item = PlayerData.findItem(player, id)
	local session = PlayerData.get(player)
	if not item or not session then
		return false
	end
	local slot = Logic.itemSlot(item)
	if slot ~= "Weapon" and slot ~= "Armor" then
		return false
	end
	local equipped: { [string]: string } = session.profile.equipped :: any
	if equipped[slot] ~= id then
		equipped[slot] = id
		PlayerData.recalc(player)
		PlayerData.equipChanged:Fire(player)
	end
	PlayerData.snapshot(player)
	return true
end

-- Fills each empty slot with the best item for it.
function PlayerData.equipIfEmpty(player: Player)
	local session = PlayerData.get(player)
	if not session then
		return
	end
	local p = session.profile
	local equipped: { [string]: string } = p.equipped :: any
	local changed = false
	for _, slot in { "Weapon", "Armor" } do
		if equipped[slot] == nil then
			local candidates: { Item } = {}
			for _, item in p.items do
				if Logic.itemSlot(item) == slot then
					table.insert(candidates, item)
				end
			end
			if #candidates > 0 then
				Logic.sortBest(candidates)
				equipped[slot] = candidates[1].id
				changed = true
			end
		end
	end
	if changed then
		PlayerData.recalc(player)
		PlayerData.equipChanged:Fire(player)
	end
end

function PlayerData.bestKind(player: Player): string
	local session = PlayerData.get(player)
	return Logic.bestKind(if session then session.profile.portalLevel else 1)
end

function PlayerData.unlocked(player: Player): { string }
	local session = PlayerData.get(player)
	return Logic.unlockedKinds(if session then session.profile.portalLevel else 1)
end

---------------------------------------------------------------------------
-- settings (remote "Setting")
---------------------------------------------------------------------------

local SETTING_ATTR: { [string]: string } = {
	music = "MusicVolume",
	sfx = "SfxVolume",
	shake = "CameraShake",
	reducedMotion = "ReducedMotion",
}

local function writeSettingAttrs(session: Session)
	local s = session.profile.settings
	setAttr(session.player, "MusicVolume", s.music)
	setAttr(session.player, "SfxVolume", s.sfx)
	setAttr(session.player, "CameraShake", s.shake)
	setAttr(session.player, "ReducedMotion", s.reducedMotion)
end

-- Validated value or nil.
local function checkSetting(name: any, value: any): any
	if type(name) ~= "string" or SETTING_ATTR[name] == nil then
		return nil
	end
	if name == "music" or name == "sfx" then
		if not isFinite(value) then
			return nil
		end
		return math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
	end
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

local function applySetting(session: Session, name: string, value: any)
	local settings: { [string]: any } = session.profile.settings :: any
	settings[name] = value
	setAttr(session.player, SETTING_ATTR[name], value)
end

local function flushSettings(player: Player)
	local state = inner[player]
	local session = PlayerData.get(player)
	if not state then
		return
	end
	state.settingsQueued = false
	if not session then
		return
	end
	for name, value in state.pendingSettings do
		applySetting(session, name, value)
	end
	table.clear(state.pendingSettings)
end

-- name: "music" | "sfx" (0..1) | "shake" | "reducedMotion" (boolean). Saved in the profile and
-- mirrored to the player attributes. Rate-limited requests are kept (newest wins) and applied shortly.
function PlayerData.setSetting(player: Player, name: any, value: any)
	local clean = checkSetting(name, value)
	local state = inner[player]
	if clean == nil or not state then
		return
	end
	local limit = Net.Limits.Setting
	if RateLimit.allow(player, "Setting", limit.rate, limit.burst) then
		local session = PlayerData.get(player)
		if session then
			state.pendingSettings[name] = nil
			applySetting(session, name, clean)
		end
		return
	end
	state.pendingSettings[name] = clean
	if not state.settingsQueued then
		state.settingsQueued = true
		task.delay(SETTING_RETRY, flushSettings, player)
	end
end

---------------------------------------------------------------------------
-- character: game HP is custom; the Humanoid never dies from game damage
---------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	local state = inner[player]
	if not state then
		return
	end
	for _, c in state.charConns do
		c:Disconnect()
	end
	table.clear(state.charConns)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Health = humanoid.MaxHealth
	table.insert(
		state.charConns,
		humanoid.HealthChanged:Connect(function(health: number)
			if health > 0 and health < humanoid.MaxHealth then
				humanoid.Health = humanoid.MaxHealth
			end
		end)
	)
	-- a fresh character on the map starts at full health (not mid-opening or in the Rift)
	if player:GetAttribute("InOpening") ~= true and player:GetAttribute("InRift") ~= true then
		PlayerData.fullHeal(player)
	end
	-- players and monsters never collide (groups registered by init.server)
	local function group(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	for _, d in character:GetDescendants() do
		group(d)
	end
	table.insert(state.charConns, character.DescendantAdded:Connect(group))
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------

local function newSession(player: Player, profile: Profile): Session
	return {
		player = player,
		profile = profile,
		loaded = false,
		hp = 0,
		maxHp = 0,
		damage = Config.Combat.fistDamage,
		invulnUntil = 0,
		lastHurt = 0,
		lastAttack = 0,
		comboStep = 0,
		dodgeReadyAt = 0,
		passes = { DoubleCoins = false, LuckierKeys = false },
		noPaidRandom = true, -- hidden until Purchases checks PolicyService
		tutorial = { step = profile.tutorialStep, coinsGiven = profile.tutorialCoins },
	}
end

local function kick(player: Player, message: string)
	if player.Parent == Players then
		player:Kick(message)
	end
end

local function onJoin(player: Player)
	if inner[player] then
		return
	end
	local state: Inner = {
		nextSave = math.huge,
		snapshotQueued = false,
		lastSnapshot = 0,
		finalizing = false,
		finalized = false,
		left = false,
		pendingSettings = {},
		settingsQueued = false,
		conns = {},
		charConns = {},
	}
	inner[player] = state

	local ok, profile, reason = Save.load(player)
	if state.left or player.Parent ~= Players then
		-- left while loading: Save already released (or never claimed) the lock
		if ok and profile then
			Save.save(player, profile, true)
		end
		Save.forget(player)
		inner[player] = nil
		return
	end
	if not ok or not profile then
		if IS_STUDIO then
			warn(`[PlayerData] load failed for {player.Name} ({reason}); Studio test continues on a temporary profile`)
			profile = SaveSchema.default()
			Save.markTemp(player, profile :: Profile)
		else
			warn(`[PlayerData] load failed for {player.UserId} ({reason}); kicking`)
			inner[player] = nil
			Save.forget(player)
			kick(
				player,
				if reason == "locked" then KICK_LOCKED elseif reason == "future" then KICK_FUTURE else KICK_FAILED
			)
			return
		end
	end
	local clean = PlayerData.cleanProfile(profile :: Profile)
	local session = newSession(player, clean)
	sessions[player] = session
	session.loaded = true
	Save.markLoaded(player)
	state.nextSave = os.clock() + AUTOSAVE + player.UserId % AUTOSAVE_STAGGER

	session.maxHp = Logic.maxHp(nil)
	session.hp = session.maxHp
	PlayerData.recalc(player)
	session.hp = session.maxHp
	writeHp(session)
	writeSettingAttrs(session)
	setAttr(player, "PortalLevel", clean.portalLevel)
	setAttr(player, "Title", clean.title)

	table.insert(
		state.conns,
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end

	runHooks(loadedHooks, player, "onLoaded")
	PlayerData.snapshot(player)
end

-- onLeaving hooks, final save with release, cleanup. Safe to call twice (PlayerRemoving + BindToClose).
local function finalize(player: Player)
	local state = inner[player]
	if not state then
		return
	end
	if state.finalizing then
		local started = os.clock()
		while not state.finalized and os.clock() - started < CLOSE_WAIT + 5 do
			task.wait(0.1)
		end
		return
	end
	state.finalizing = true
	state.left = true
	local session = sessions[player]
	if session and session.loaded then
		runHooks(leavingHooks, player, "onLeaving")
		if state.settingsQueued then
			flushSettings(player)
		end
		local ok = Save.save(player, session.profile, true)
		if not ok and not Save.isTemp(player) then
			warn(`[PlayerData] final save failed for {player.UserId}`)
		end
		session.loaded = false
	end
	for _, c in state.conns do
		c:Disconnect()
	end
	for _, c in state.charConns do
		c:Disconnect()
	end
	sessions[player] = nil
	state.finalized = true
	inner[player] = nil
end

local function onLeave(player: Player)
	local state = inner[player]
	if not state then
		return
	end
	if not sessions[player] then
		-- still loading: onJoin sees `left` and releases the lock itself
		state.left = true
		return
	end
	finalize(player)
end

local function autosaveLoop()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, session in sessions do
			local state = inner[player]
			if session.loaded and state and not state.finalizing and now >= state.nextSave then
				state.nextSave = now + AUTOSAVE
				task.spawn(function()
					local ok, reason = Save.save(player, session.profile, false)
					if not ok and reason == "lost" and not IS_STUDIO then
						-- another server owns this profile now: stop saving here
						session.loaded = false
						Save.forget(player)
						kick(player, KICK_LOST)
					end
				end)
			end
		end
	end
end

local function onClose()
	local mode = Save.mode()
	local pending = 0
	for _, player in Players:GetPlayers() do
		if inner[player] then
			pending += 1
			task.spawn(function()
				pcall(finalize, player)
				pending -= 1
			end)
		end
	end
	if IS_STUDIO and mode ~= "datastore" then
		return
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < CLOSE_WAIT do
		task.wait(0.1)
	end
end

local function onReadyRemote(player: Player)
	local limit = Net.Limits.Ready
	if not RateLimit.allow(player, "Ready", limit.rate, limit.burst) then
		return
	end
	local session = PlayerData.waitLoaded(player, 30)
	if not session then
		return
	end
	sendNow(player)
	runHooks(readyHooks, player, "onReady")
end

function PlayerData.init()
	profileRemote = Net.find("Profile")
	local ready = Net.find("Ready")
	if ready then
		ready.OnServerEvent:Connect(onReadyRemote)
	end
	local setting = Net.find("Setting")
	if setting then
		setting.OnServerEvent:Connect(function(player: Player, name: any, value: any)
			PlayerData.setSetting(player, name, value)
		end)
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosaveLoop)
end

return PlayerData
