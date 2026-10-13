--!strict
-- Combat: the server side of fighting. It decides every player hit (combo timing, auto-face,
-- range, arc, crits, shields, weapon powers), dodges (invulnerable frames), damage to players
-- (status, Hurt Fx, falls through the onDown handlers) and regen outside openings and rifts.
-- The client only sends intent (Attack, Dodge) and plays the swing from the character's
-- Swing / SwingStep / SwingType attributes. Pure combo and arc maths: Shared/CombatMath.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CombatMath = require(Shared.CombatMath)
local Config = require(Shared.Config)
local Logic = require(Shared.Logic)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Attacks = require(script.Parent.Parent.Lib.Attacks)
local Status = require(script.Parent.Parent.Lib.Status)
local Monsters = require(script.Parent.Monsters)
local Notify = require(script.Parent.Notify)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local RateLimit = require(script.Parent.RateLimit)

type Item = Types.Item
type ComboStep = Types.ComboStep
type HitBatch = Types.HitBatch
type Hit = Types.Hit

type Mon = Monsters.Mon
-- What hit the player (Attacks builds it; also burn ticks from Status via Monsters).
export type DamageSrc = Attacks.HurtSrc

type State = {
	swingCount: number,
	prevStep: number,
	prevStepTime: number,
	dodgeUntil: number, -- invulnerable because of a dodge (os.clock)
	dodgeToken: number,
	flaggedUntil: number, -- anti-teleport: attacks and loot credit ignored until then
	exemptUntil: number, -- server moved the character: skip the speed check until then
	lastPos: Vector3?,
	lastSample: number,
	slowApplied: boolean,
	baseSpeed: number,
	burnUntil: number,
	burnDps: number,
	nextBurn: number,
	down: boolean,
	conns: { RBXScriptConnection },
}

local Combat = {}

local C = Config.Combat
local TICK = 0.25 -- 4 Hz: regen, teleport samples, player burn, slow speed
local DODGE_GRACE = 0.1 -- extra invulnerable time after the roll
local MAX_SPEED = 160 -- studs/s between two samples before attacks are ignored
local FLAG_TIME = 3 -- seconds attacks and loot credit are ignored after a too-fast move
local MOVE_EXEMPT = 0.6 -- seconds after a server move with no speed check
local DOWN_GRACE = 2 -- invulnerable seconds after the map fall sends a player home
local FX_RADIUS = 90 -- studs: other players who see a monster get hit
local HURT_SHAKE = 0.45 -- camera trauma for heavy hits on the player
local BOSS_STAGGER = 0.5 -- bosses stagger for half as long
local DEFAULT_SWING = "Sword" -- fists use the Sword timings and swing

local rng = Random.new()
local states: { [Player]: State } = {}
local downHandlers: { (Player) -> boolean } = {}
local staggerImmune: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function stateOf(player: Player): State?
	local state = states[player]
	if not state and player.Parent == Players then
		state = {
			swingCount = 0,
			prevStep = 0,
			prevStepTime = 0,
			dodgeUntil = 0,
			dodgeToken = 0,
			flaggedUntil = 0,
			exemptUntil = 0,
			lastPos = nil,
			lastSample = 0,
			slowApplied = false,
			baseSpeed = 16,
			burnUntil = 0,
			burnDps = 0,
			nextBurn = 0,
			down = false,
			conns = {},
		}
		states[player] = state
	end
	return state
end

-- Character, humanoid and root when the character is alive.
local function liveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character or character.Parent == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function equippedWeapon(player: Player): Item?
	local session = PlayerData.get(player)
	local id = session and session.profile.equipped.Weapon
	if not id then
		return nil
	end
	local item = PlayerData.findItem(player, id)
	if item and Logic.itemSlot(item) == "Weapon" then
		return item
	end
	return nil
end

local function monAlive(mon: Mon): boolean
	return mon.alive == true and mon.root ~= nil and mon.root.Parent ~= nil
end

local function monRadius(mon: Mon): number
	return CombatMath.targetRadius(mon.root.Size)
end

---------------------------------------------------------------------------
-- player speed (slow)
---------------------------------------------------------------------------

-- Writes the humanoid's WalkSpeed only when the slow starts or ends (and while it changes).
local function updateSpeed(player: Player, state: State)
	local _, humanoid = liveCharacter(player)
	if not humanoid then
		return
	end
	local mult = Status.speedMult(player)
	if mult < 1 then
		if not state.slowApplied then
			state.baseSpeed = humanoid.WalkSpeed
			state.slowApplied = true
		end
		local speed = state.baseSpeed * mult
		if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
			humanoid.WalkSpeed = speed
		end
	elseif state.slowApplied then
		state.slowApplied = false
		humanoid.WalkSpeed = state.baseSpeed
	end
end

---------------------------------------------------------------------------
-- falls
---------------------------------------------------------------------------

local function runDown(player: Player)
	local state = states[player]
	if not state or state.down then
		return
	end
	state.down = true
	local handled = false
	for _, fn in downHandlers do
		local ok, took = pcall(fn, player)
		if not ok then
			warn(`[Combat] onDown handler error: {took}`)
		elseif took == true then
			handled = true
			break
		end
	end
	if not handled and player.Parent == Players then
		-- falling on the map costs nothing: home and full health
		state.exemptUntil = os.clock() + MOVE_EXEMPT
		state.lastPos = nil
		Plots.sendHome(player)
		PlayerData.fullHeal(player)
		local session = PlayerData.get(player)
		if session then
			session.invulnUntil = math.max(session.invulnUntil, os.clock() + DOWN_GRACE)
		end
	end
	state.burnUntil = 0
	state.burnDps = 0
	player:SetAttribute("Burn", nil)
	state.down = false
end

---------------------------------------------------------------------------
-- damage to players
---------------------------------------------------------------------------

function Combat.isInvuln(player: Player): boolean
	local session = PlayerData.get(player)
	return session ~= nil and session.invulnUntil > os.clock()
end

function Combat.speedMult(player: Player): number
	return Status.speedMult(player)
end

-- True for a few seconds after the character moved impossibly fast: no attacks, no credit.
function Combat.isFlagged(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.flaggedUntil > os.clock()
end

-- Other systems call this right before they move a character far (Rift, Openings).
function Combat.noteTeleport(player: Player)
	local state = states[player]
	if state then
		state.exemptUntil = os.clock() + MOVE_EXEMPT
		state.lastPos = nil
	end
end

local function applyPlayerStatus(player: Player, state: State, status: any)
	if type(status) ~= "table" or not finite(status.duration) or status.duration <= 0 then
		return
	end
	local duration = math.min(status.duration, 30)
	if status.kind == "slow" then
		local amount = if finite(status.amount) then math.clamp(status.amount, 0, 0.9) else 0.3
		Status.apply(player, "slow", { duration = duration, amount = amount })
		updateSpeed(player, state)
	elseif status.kind == "burn" and finite(status.dps) and status.dps > 0 then
		-- player burn is ticked here (Status burn ticks go to Monsters' handler)
		local now = os.clock()
		if state.burnUntil <= now then
			state.burnDps = status.dps
			state.nextBurn = now + TICK
		else
			state.burnDps = math.max(state.burnDps, status.dps)
		end
		if now + duration > state.burnUntil then
			state.burnUntil = now + duration
			player:SetAttribute("Burn", Workspace:GetServerTimeNow() + duration)
		end
	end
end

-- Takes the health, tells the player and starts the fall at 0.
local function hurt(
	player: Player,
	session: PlayerData.Session,
	root: BasePart,
	amount: number,
	kind: string?,
	heavy: boolean
)
	session.lastHurt = os.clock()
	PlayerData.setHp(player, session.hp - amount)
	Notify.fx(player, {
		k = "Hurt",
		amount = math.max(1, math.floor(amount + 0.5)),
		pos = root.Position,
		status = kind,
	})
	if heavy then
		Notify.fx(player, { k = "Shake", amount = HURT_SHAKE })
	end
	if session.hp <= 0 then
		task.spawn(runDown, player)
	end
end

-- Burn ticks on a player: they keep burning through a dodge roll.
local function burnTick(player: Player, state: State, amount: number)
	local session = PlayerData.get(player)
	if not session or session.hp <= 0 or state.down then
		return
	end
	local _, _, root = liveCharacter(player)
	if root then
		hurt(player, session, root, amount, "burn", false)
	end
end

-- amount: health to take; src: who/what hit (status, heavy). Ignored while invulnerable.
function Combat.damagePlayer(player: Player, amount: number, src: DamageSrc?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not finite(amount) or amount <= 0 then
		return
	end
	local session = PlayerData.get(player)
	local state = stateOf(player)
	if not session or not state or session.hp <= 0 or state.down then
		return
	end
	local _, _, root = liveCharacter(player)
	if not root then
		return
	end
	local now = os.clock()
	if session.invulnUntil > now then
		if state.dodgeUntil > now then
			Notify.fx(player, { k = "Dodged" })
		end
		return
	end
	local status = src and src.status
	if status then
		applyPlayerStatus(player, state, status)
	end
	hurt(player, session, root, amount, if status then status.kind else nil, src ~= nil and src.heavy == true)
end

-- fn(player) -> true when it owns this fall. Handlers run in registration order.
function Combat.onDown(fn: (Player) -> boolean)
	table.insert(downHandlers, fn)
end

---------------------------------------------------------------------------
-- attacks
---------------------------------------------------------------------------

type Swing = {
	player: Player,
	character: Model,
	step: number,
	def: ComboStep,
	base: number,
	power: { [string]: any }?,
}

local function staggerMon(mon: Mon, power: { [string]: any }): boolean
	local chance = if finite(power.chance) then power.chance else 0
	local duration = if finite(power.duration) then power.duration else 0
	if duration <= 0 or rng:NextNumber() >= chance then
		return false
	end
	local now = os.clock()
	if (staggerImmune[mon] or 0) > now then
		return false
	end
	if mon.boss then
		duration *= BOSS_STAGGER
	end
	staggerImmune[mon] = now + duration + C.staggerImmune
	Status.apply(mon, "stagger", { duration = duration })
	return true
end

-- The power's effect after a landed hit; returns the power name to show, or nil.
local function applyPower(mon: Mon, power: { [string]: any }?, amount: number, player: Player): string?
	if not power or not monAlive(mon) then
		return nil
	end
	local kind = power.kind
	if kind == "stagger" then
		return if staggerMon(mon, power) then "stagger" else nil
	elseif kind == "burn" and finite(power.dps) and finite(power.duration) then
		Status.apply(mon, "burn", { duration = power.duration, dps = power.dps * amount, source = player })
		return "burn"
	elseif kind == "slow" and finite(power.amount) and finite(power.duration) then
		Status.apply(mon, "slow", { duration = power.duration, amount = power.amount })
		return "slow"
	end
	return nil
end

-- One strike on one monster: crit roll, damage, power. Adds the result to hits.
local function strike(
	swing: Swing,
	mon: Mon,
	dir: Vector3,
	hits: { Hit },
	forcedPower: string?,
	amount: number?
): number
	local crit = if amount then false else rng:NextNumber() < C.critChance
	local dealt = amount or CombatMath.hitAmount(swing.base, swing.def.damage, crit, C.critMult)
	local pos = mon.root.Position
	local power = forcedPower
	if not power and swing.power and swing.power.kind ~= "double" then
		-- burn and slow always land; stagger rolls its chance (name only shown when it lands)
		local kind = swing.power.kind
		if kind == "burn" or kind == "slow" then
			power = kind
		end
	end
	local killed = Monsters.damage(mon, dealt, swing.player, dir, {
		heavy = swing.def.heavy == true or crit,
		knock = swing.def.knock,
		crit = crit,
		power = power,
	})
	if not killed and not forcedPower then
		local shown = applyPower(mon, swing.power, dealt, swing.player)
		if shown then
			power = shown
		end
	end
	table.insert(hits, { model = mon.model, amount = dealt, crit = crit, power = power, pos = pos, killed = killed })
	Notify.fxNear(pos, FX_RADIUS, {
		k = "MonsterHit",
		model = mon.model,
		amount = dealt,
		crit = crit,
		power = power,
		by = swing.player.UserId,
	})
	return dealt
end

-- Runs at the contact time (end of windup): finds the targets and lands the hits.
local function resolveSwing(swing: Swing)
	local player = swing.player
	if player.Parent ~= Players or Combat.isFlagged(player) then
		return
	end
	local session = PlayerData.get(player)
	local character, _, root = liveCharacter(player)
	if not session or session.hp <= 0 or not character or character ~= swing.character or not root then
		return
	end
	local origin = root.Position
	local all = Monsters.hittableBy(player)

	-- auto-face: toward the nearest hittable monster in range, else where the character looks
	local nearest: Mon? = nil
	local nearestDist = math.huge
	for _, mon in all do
		if monAlive(mon) then
			local p = mon.root.Position
			local dx, dz = p.X - origin.X, p.Z - origin.Z
			local d = math.sqrt(dx * dx + dz * dz) - monRadius(mon)
			if d <= C.autoFaceRange and d < nearestDist then
				nearest = mon
				nearestDist = d
			end
		end
	end
	local dir = CombatMath.faceDirection(origin, root.CFrame.LookVector, if nearest then nearest.root.Position else nil)

	-- targets in range and arc (finishers: all around within radius), nearest first
	local def = swing.def
	local targets: { Mon } = {}
	local dists: { [Mon]: number } = {}
	for _, mon in all do
		if monAlive(mon) then
			local p = mon.root.Position
			local size = mon.root.Size
			if CombatMath.inSwing(origin, dir, p, monRadius(mon), def.range, def.arc, def.radius, size.Y) then
				table.insert(targets, mon)
				dists[mon] = (p - origin).Magnitude
			end
		end
	end
	if #targets == 0 then
		return
	end
	table.sort(targets, function(a, b)
		return dists[a] < dists[b]
	end)

	local hits: { Hit } = {}
	local strikes = if def.double then 2 else 1
	for i = 1, math.min(#targets, C.maxHitsPerSwing) do
		local mon = targets[i]
		local toMon = CombatMath.faceDirection(origin, dir, mon.root.Position)
		if Monsters.blocks(mon, origin) then
			table.insert(hits, {
				model = mon.model,
				amount = 0,
				crit = false,
				pos = mon.root.Position,
				killed = false,
				blocked = true,
			})
			Notify.fxNear(mon.root.Position, FX_RADIUS, {
				k = "MonsterHit",
				model = mon.model,
				amount = 0,
				crit = false,
				blocked = true,
				by = player.UserId,
			})
			continue
		end
		local lastDealt = 0
		for _ = 1, strikes do
			if not monAlive(mon) then
				break
			end
			lastDealt = strike(swing, mon, toMon, hits, nil, nil)
		end
		-- Void power: a chance of a second hit of the same damage
		local power = swing.power
		if power and power.kind == "double" and monAlive(mon) and lastDealt > 0 then
			local chance = if finite(power.chance) then power.chance else 0
			if rng:NextNumber() < chance then
				strike(swing, mon, toMon, hits, "double", lastDealt)
			end
		end
	end

	local hitsRemote = Net.find("Hits")
	if hitsRemote then
		local batch: HitBatch = { step = swing.step, heavy = def.heavy == true, hits = hits }
		hitsRemote:FireClient(player, batch)
	end
end

function Combat.onAttack(player: Player)
	local limit = Net.Limits.Attack
	if not RateLimit.allow(player, "Attack", limit.rate, limit.burst) then
		return
	end
	local session = PlayerData.get(player)
	local state = stateOf(player)
	if not session or not state or session.hp <= 0 or state.down then
		return
	end
	local character, _, root = liveCharacter(player)
	if not character or not root then
		return
	end
	local now = os.clock()
	if state.flaggedUntil > now or character:GetAttribute("Dodging") == true then
		return
	end

	local weapon = equippedWeapon(player)
	local gearType = if weapon then Config.GearTypes[weapon.type] else nil
	if not gearType or not gearType.combo then
		gearType = Config.GearTypes[DEFAULT_SWING]
	end
	local combo = gearType.combo :: { ComboStep }
	local reset = gearType.comboReset or 1

	local step =
		CombatMath.nextStep(state.prevStep, state.prevStepTime, now - session.lastAttack, #combo, reset, C.comboGrace)
	if not step then
		return -- too early: ignored, never queued
	end
	local def = combo[step]
	state.prevStep = step
	state.prevStepTime = CombatMath.stepTime(def)
	session.comboStep = step
	session.lastAttack = now

	-- every client plays this swing for this character
	state.swingCount += 1
	character:SetAttribute("SwingType", gearType.id)
	character:SetAttribute("SwingStep", step)
	character:SetAttribute("Swing", state.swingCount)

	local swing: Swing = {
		player = player,
		character = character,
		step = step,
		def = def,
		base = Logic.weaponDamage(weapon),
		power = if weapon then Logic.power(weapon) else nil,
	}
	task.delay(def.windup, function()
		local ok, err = pcall(resolveSwing, swing)
		if not ok then
			warn(`[Combat] swing error: {err}`)
		end
	end)
end

function Combat.onDodge(player: Player)
	local limit = Net.Limits.Dodge
	if not RateLimit.allow(player, "Dodge", limit.rate, limit.burst) then
		return
	end
	local session = PlayerData.get(player)
	local state = stateOf(player)
	if not session or not state or session.hp <= 0 or state.down then
		return
	end
	local character = liveCharacter(player)
	if not character then
		return
	end
	local now = os.clock()
	if now < session.dodgeReadyAt then
		return
	end
	local dodge = C.dodge
	session.dodgeReadyAt = now + dodge.cooldown
	state.dodgeUntil = now + dodge.duration + DODGE_GRACE
	session.invulnUntil = math.max(session.invulnUntil, state.dodgeUntil)
	state.dodgeToken += 1
	local token = state.dodgeToken
	character:SetAttribute("Dodging", true)
	task.delay(dodge.duration, function()
		if state.dodgeToken == token and character.Parent ~= nil then
			character:SetAttribute("Dodging", nil)
		end
	end)
end

---------------------------------------------------------------------------
-- 4 Hz loop: teleport samples, regen, player burn, slow speed
---------------------------------------------------------------------------

-- A big jump that lands on the player's own plot or a spawn is a server move, not a cheat.
local function sanctionedSpot(player: Player, pos: Vector3): boolean
	local plot = Plots.plotOf(player)
	if plot and Plots.isInside(plot, pos, -6) then
		return true
	end
	local spawnPart = Workspace:FindFirstChildOfClass("SpawnLocation")
	return spawnPart ~= nil and (spawnPart.Position - pos).Magnitude < 16
end

local function sample(player: Player, state: State, root: BasePart, now: number)
	local pos = root.Position
	local last = state.lastPos
	local dt = now - state.lastSample
	state.lastPos = pos
	state.lastSample = now
	if not last or now < state.exemptUntil or dt <= 0 then
		return
	end
	if not CombatMath.speedOk(last, pos, dt, MAX_SPEED) and not sanctionedSpot(player, pos) then
		state.flaggedUntil = now + FLAG_TIME
	end
end

local function tickPlayer(player: Player, state: State, now: number, dt: number)
	local session = PlayerData.get(player)
	local _, _, root = liveCharacter(player)
	if root then
		sample(player, state, root, now)
	else
		state.lastPos = nil
	end
	if not session then
		return
	end
	-- burn on the player
	if state.burnUntil > 0 then
		local ticks = 0
		while state.nextBurn <= now and state.nextBurn <= state.burnUntil + 1e-3 and ticks < 8 do
			ticks += 1
			state.nextBurn += TICK
		end
		local damage = state.burnDps * TICK * ticks
		if state.burnUntil <= now then
			state.burnUntil = 0
			state.burnDps = 0
			player:SetAttribute("Burn", nil)
		end
		if damage > 0 then
			burnTick(player, state, damage)
		end
	end
	updateSpeed(player, state)
	-- regen outside openings and rifts
	if session.hp > 0 and session.hp < session.maxHp and not state.down then
		if player:GetAttribute("InOpening") ~= true and player:GetAttribute("InRift") ~= true then
			if now - session.lastHurt >= C.regenDelay then
				PlayerData.heal(player, C.regenPerSecond * dt)
			end
		end
	end
end

local function cleanup(player: Player)
	local state = states[player]
	states[player] = nil
	if state then
		for _, conn in state.conns do
			conn:Disconnect()
		end
		table.clear(state.conns)
	end
	Status.clear(player)
end

local function onPlayerAdded(player: Player)
	local state = stateOf(player)
	if not state then
		return
	end
	table.insert(
		state.conns,
		player.CharacterAdded:Connect(function(character)
			state.lastPos = nil
			state.exemptUntil = os.clock() + MOVE_EXEMPT
			state.prevStep = 0
			state.slowApplied = false
			state.burnUntil = 0
			state.burnDps = 0
			state.dodgeUntil = 0
			player:SetAttribute("Burn", nil)
			Status.clear(player)
			character:SetAttribute("Dodging", nil)
		end)
	)
end

function Combat.init()
	Monsters.setPlayerDamage(Combat.damagePlayer)
	Net.get("Attack").OnServerEvent:Connect(function(player: Player)
		Combat.onAttack(player)
	end)
	Net.get("Dodge").OnServerEvent:Connect(function(player: Player)
		Combat.onDodge(player)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(cleanup)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function Combat.start()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = math.min(now - last, 1)
		last = now
		for player, state in states do
			if player.Parent ~= Players then
				cleanup(player)
				continue
			end
			local ok, err = pcall(tickPlayer, player, state, now, dt)
			if not ok then
				warn(`[Combat] tick error: {err}`)
			end
		end
	end
end

-- Pure helpers for specs.
Combat._test = { math = CombatMath }

return Combat
