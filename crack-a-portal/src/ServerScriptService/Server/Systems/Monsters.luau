--!strict
-- Monsters: every monster in the game (openings, map, Server Rift). Rebuilt from NOTES.md with
-- the same API, then extended (PLAN.md section 7).
-- Rigs are AnimationController models moved by the server (PLAN.md section 7 decision): an
-- invisible Root (server network owner) with AlignPosition + AlignOrientation on RootAttachment.
-- One 10 Hz loop runs every monster's AI: it picks a goal, raycasts the ground once when the goal
-- moves and sets the align targets; physics smooths in between and replication interpolates.
-- No per-monster connections, no table allocation per tick, properties written only on change.
-- Attacks live in Lib/Attacks (bound here, so it never requires this module).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimHooks = require(Shared.AnimHooks)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Net = require(Shared.Net)
local Templates = require(Shared.Templates)
local Types = require(Shared.Types)

local Lib = script.Parent.Parent:WaitForChild("Lib")
local Attacks = require(Lib:WaitForChild("Attacks"))
local Bus = require(Lib:WaitForChild("Bus"))
local Status = require(Lib:WaitForChild("Status"))

local Notify = require(script.Parent:WaitForChild("Notify"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Plots = require(script.Parent:WaitForChild("Plots"))

export type Mon = Attacks.Mon
export type SpawnOpts = Attacks.SpawnOpts
export type DamageOpts = { heavy: boolean?, knock: number?, crit: boolean?, power: string? }
type MonsterDef = Types.MonsterDef

local Monsters = {}

---------------------------------------------------------------------------
-- Tuning (small AI constants; game numbers live in Config)
---------------------------------------------------------------------------

local TICK = 1 / math.max(1, Config.MapMonsters.tickHz)
local WARN_RADIUS = 70 -- map monsters: who sees warnings / can be hit
local FX_RADIUS = 150 -- death bursts for players nearby
local ALIGN_FORCE = 1e7
local ALIGN_RESPONSIVENESS = 40
local TURN_RESPONSIVENESS = 30
local TURN_RATE = 12 -- rad/s
local TURN_RATE_BOSS = 4
local TURN_RATE_SHIELD = 1.6 -- Void Knight turns slowly so players can flank it
local RECOVER = 0.35 -- seconds after an attack before the AI moves again
local FIRST_ATTACK_DELAY = 0.8
local KNOCK_TIME = 0.25
local KNOCK_STUDS = 0.3 -- studs pushed per knock unit (Config knock is studs/s)
local DEFAULT_KNOCK = 6
local BOSS_KNOCK = 0.15
local BOSS_ROAR = 1.5 -- intro roar: invulnerable
local DEATH_DESPAWN = 0.9
local RETURN_SPEED = 1.4
local WANDER_SPEED = 0.45
local WANDER_RADIUS = 12
local HOME_REACHED = 3
local PACK_RADIUS = 9
local PACK_SPIN = 1.1 -- rad/s while circling
local PACK_DASH = 1.8 -- seconds of a dash-in before circling again
local PACK_DASH_SPEED = 1.35
local FLOAT_DRIFT = 4
local RIFT_RETARGET = 1
local RIFT_MARGIN = 8
local LEASH_SLACK = 6 -- studs past the leash a target may stand and still be chased
local MOVE_EPS = 0.1
local GROUND_EPS = 1.5
local YAW_EPS = 0.02
local BOSS_BAR_GAP = 0.2 -- at most 5 per second
local BOSS_BAR_REFRESH = 1
local SHAKE_ROAR = 0.5

local EMERGE: { [string]: { dist: number, time: number, arc: number, sink: number } } = {
	crawl = { dist = 5, time = 1.2, arc = 0, sink = 2 },
	leap = { dist = 9, time = 0.9, arc = 5, sink = 0 },
	burst = { dist = 6, time = 0.45, arc = 1.5, sink = 1 },
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

type Emerge = { style: string, from: Vector3, to: Vector3, t0: number, time: number, arc: number }

type Rig = {
	att: Attachment,
	align: AlignPosition,
	orient: AlignOrientation,
	animator: Animator?,
	tracks: { [string]: AnimationTrack }, -- idle, move, hit, death, emerge, roar, <attackId>
	playing: string?, -- current base track key ("idle" / "move")
	goal: Vector3, -- last AlignPosition target
	yaw: number,
	maxVel: number,
	groundAt: Vector3, -- where the last ground ray was cast
	groundY: number,
	attOffset: number, -- RootAttachment height above the model pivot
	hover: number,
	cd: { [string]: number }, -- attack id -> ready time
	engage: number, -- melee stop distance
	prefDist: number, -- floaters' keep-away distance
	strafe: number,
	strafeAt: number,
	packAngle: number,
	packDir: number,
	packUntil: number,
	packDash: number,
	wanderAt: number,
	retargetAt: number,
	asleep: boolean,
	dashing: boolean,
	knockUntil: number,
	invulnUntil: number,
	emerge: Emerge?,
	bar: { [Player]: boolean }?, -- boss bar recipients
	barSent: number,
	barHp: number,
}

local list: { Mon } = {}
local indexOf: { [Mon]: number } = {}
local rigs: { [Mon]: Rig } = {}
local byModel: { [Model]: Mon } = {}
local nextId = 0
local rng = Random.new()

local damageListeners: { (mon: Mon, amount: number, by: Player?) -> () } = {}
local deathListeners: { (mon: Mon, killer: Player?) -> () } = {}
local playerDamage: ((player: Player, amount: number, src: Attacks.HurtSrc) -> ())? = nil

local folder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
rayParams.IgnoreWater = true
local DOWN = Vector3.new(0, -140, 0)
local RAY_UP = Vector3.new(0, 30, 0)

local remotes = {
	boss = nil :: RemoteEvent?,
	fxU = nil :: UnreliableRemoteEvent?,
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function now(): number
	return os.clock()
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function isPlayer(v: any): boolean
	return typeof(v) == "Instance" and v:IsA("Player")
end

local function rootPosOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character.PrimaryPart
	return if root then root.Position else nil
end

-- Alive, loaded, has a character.
local function targetable(player: Player): boolean
	if player.Parent ~= Players then
		return false
	end
	local hp = player:GetAttribute("HP")
	if type(hp) ~= "number" or hp <= 0 then
		return false
	end
	local character = player.Character
	return character ~= nil and character.PrimaryPart ~= nil
end

local function inOpening(player: Player): boolean
	return player:GetAttribute("InOpening") == true
end

local function riftParticipant(player: Player): boolean
	if player:GetAttribute("InRift") == true then
		return true
	end
	if inOpening(player) then
		return false
	end
	local p = rootPosOf(player)
	local M = Config.Map
	return p ~= nil and Geometry.flatDistance(p, M.riftCenter) <= M.riftRadius + 12
end

local function rebuildFilter()
	local filter: { Instance } = {}
	if folder then
		table.insert(filter, folder)
	end
	local fx = Workspace:FindFirstChild("Fx")
	if fx then
		table.insert(filter, fx)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filter
end

-- Ground point under pos (pos itself when nothing is below).
local function groundAt(pos: Vector3): Vector3
	local result = Workspace:Raycast(pos + RAY_UP, DOWN, rayParams)
	if result then
		return result.Position
	end
	return pos
end

---------------------------------------------------------------------------
-- Recipients and the boss bar
---------------------------------------------------------------------------

-- Who sees this monster's warnings and can be hit by it: the owner (opening), players within
-- 70 studs (map), Rift participants (rift).
function Monsters.send(mon: Mon): { Player }
	local out: { Player } = {}
	if mon.mode == "opening" then
		local owner = mon.owner
		if owner and owner.Parent == Players then
			table.insert(out, owner)
		end
		return out
	end
	local pos = mon.root.Position
	for _, player in Players:GetPlayers() do
		if mon.mode == "rift" then
			if riftParticipant(player) then
				table.insert(out, player)
			end
		elseif not inOpening(player) then
			local p = rootPosOf(player)
			if p and (p - pos).Magnitude <= WARN_RADIUS then
				table.insert(out, player)
			end
		end
	end
	return out
end

local function bossPayload(mon: Mon): Types.BossBar
	return {
		name = mon.def.bossTitle or mon.def.name,
		hp = math.ceil(mon.hp),
		maxHp = math.ceil(mon.maxHp),
		kind = mon.def.kind,
		rift = mon.mode == "rift",
	}
end

local function bossBarOff(rig: Rig)
	local bar = rig.bar
	local remote = remotes.boss
	if not bar then
		return
	end
	rig.bar = nil
	if remote then
		for player in bar do
			if player.Parent == Players then
				remote:FireClient(player, false)
			end
		end
	end
end

local function bossBarUpdate(mon: Mon, rig: Rig, t: number)
	local bar = rig.bar
	local remote = remotes.boss
	if not bar or not remote or t - rig.barSent < BOSS_BAR_GAP then
		return
	end
	if mon.hp == rig.barHp and t - rig.barSent < BOSS_BAR_REFRESH then
		return
	end
	rig.barSent = t
	rig.barHp = mon.hp
	local payload = bossPayload(mon)
	local who = Monsters.send(mon)
	for player in bar do
		if not table.find(who, player) then
			bar[player] = nil
			if player.Parent == Players then
				remote:FireClient(player, false)
			end
		end
	end
	for _, player in who do
		bar[player] = true
		remote:FireClient(player, payload)
	end
end

local function sendBossBarsTo(player: Player)
	local remote = remotes.boss
	if not remote then
		return
	end
	for _, mon in list do
		local rig = rigs[mon]
		if mon.alive and rig and rig.bar and table.find(Monsters.send(mon), player) then
			rig.bar[player] = true
			remote:FireClient(player, bossPayload(mon))
		end
	end
end

-- Unreliable Fx to players near pos, except one (who gets the reliable copy).
local function fxNearExcept(pos: Vector3, ev: Types.FxEvent, except: Player?)
	local remote = remotes.fxU
	if not remote then
		return
	end
	for _, player in Players:GetPlayers() do
		if player ~= except then
			local p = rootPosOf(player)
			if p and (p - pos).Magnitude <= FX_RADIUS then
				remote:FireClient(player, ev)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------

-- Keeps goals legal: inside the plot (opening), inside the Rift circle (rift), within leash (map).
local function clampGoal(mon: Mon, pos: Vector3): Vector3
	if mon.mode == "opening" then
		local plot = mon.plot
		if plot then
			local ok, clamped = pcall(Plots.clampInside, plot, pos)
			if ok and typeof(clamped) == "Vector3" then
				return clamped
			end
		end
		return pos
	elseif mon.mode == "rift" then
		local M = Config.Map
		local center = M.riftCenter
		local limit = M.riftRadius + RIFT_MARGIN
		local offset = Geometry.flat(pos - center)
		if offset.Magnitude > limit then
			local p = center + offset.Unit * limit
			return Vector3.new(p.X, pos.Y, p.Z)
		end
		return pos
	end
	local home = mon.home
	if home then
		local leash = mon.def.leash
		local offset = Geometry.flat(pos - home.Position)
		if offset.Magnitude > leash then
			local p = home.Position + offset.Unit * leash
			return Vector3.new(p.X, pos.Y, p.Z)
		end
	end
	return pos
end

local function setMaxVel(rig: Rig, v: number)
	if math.abs(v - rig.maxVel) > 0.05 then
		rig.maxVel = v
		rig.align.MaxVelocity = v
	end
end

local function setGoalRaw(rig: Rig, target: Vector3)
	if (target - rig.goal).Magnitude > MOVE_EPS then
		rig.goal = target
		rig.align.Position = target
	end
end

-- Moves the align target to the ground under `goal` (+ hover for flyers).
local function moveTo(mon: Mon, rig: Rig, goal: Vector3, lift: number)
	local g = clampGoal(mon, goal)
	local dx, dz = g.X - rig.groundAt.X, g.Z - rig.groundAt.Z
	if dx * dx + dz * dz > GROUND_EPS * GROUND_EPS then
		rig.groundAt = g
		rig.groundY = groundAt(g).Y
	end
	setGoalRaw(rig, Vector3.new(g.X, rig.groundY + rig.attOffset + lift, g.Z))
end

local function hold(mon: Mon, rig: Rig)
	local p = mon.root.Position
	moveTo(mon, rig, p, rig.hover)
end

local function faceYaw(rig: Rig, yaw: number)
	local diff = math.abs((yaw - rig.yaw + math.pi) % (2 * math.pi) - math.pi)
	if diff > YAW_EPS then
		rig.yaw = yaw
		rig.orient.CFrame = CFrame.Angles(0, yaw, 0)
	end
end

local function faceTo(mon: Mon, rig: Rig, pos: Vector3)
	local from = mon.root.Position
	local dx, dz = pos.X - from.X, pos.Z - from.Z
	if dx * dx + dz * dz < 0.01 then
		return
	end
	faceYaw(rig, math.atan2(-dx, -dz))
end

---------------------------------------------------------------------------
-- Animation hooks (ids > 0 only; MonsterFx runs placeholder motion for grey rigs)
---------------------------------------------------------------------------

local function playTrack(rig: Rig, key: string, fade: number?)
	local track = rig.tracks[key]
	if track then
		AnimHooks.play(track, fade or 0.1)
	end
end

local function stopTrack(rig: Rig, key: string, fade: number?)
	local track = rig.tracks[key]
	if track and track.IsPlaying then
		track:Stop(fade or 0.1)
	end
end

local function setBase(rig: Rig, key: string)
	if rig.playing == key then
		return
	end
	local old = rig.playing
	rig.playing = key
	if old then
		stopTrack(rig, old, 0.15)
	end
	playTrack(rig, key, 0.15)
end

local function loadTracks(rig: Rig, def: MonsterDef)
	local animator = rig.animator
	if not animator then
		return
	end
	local A = def.anims
	local P = Enum.AnimationPriority
	local function add(key: string, id: number, priority: Enum.AnimationPriority, looped: boolean)
		if id > 0 then
			local track = AnimHooks.load(animator, id, { priority = priority, looped = looped })
			if track then
				rig.tracks[key] = track
			end
		end
	end
	add("idle", A.idle, P.Idle, true)
	add("move", A.move, P.Movement, true)
	add("hit", A.hit, P.Action2, false)
	add("death", A.death, P.Action4, false)
	add("emerge", A.emerge, P.Action3, false)
	add("roar", A.roar, P.Action3, false)
	for attackId, id in A.attacks do
		add(attackId, id, P.Action, false)
	end
end

---------------------------------------------------------------------------
-- State and attacks
---------------------------------------------------------------------------

local function setState(mon: Mon, state: string, attackId: string?, windup: number?)
	mon.state = state
	local model = mon.model
	setAttr(model, "State", state)
	if state == "windup" or state == "attack" then
		setAttr(model, "Attack", attackId)
	else
		setAttr(model, "Attack", nil)
	end
	if state == "windup" and windup then
		setAttr(model, "Windup", Workspace:GetServerTimeNow() + windup)
	elseif state ~= "attack" then
		setAttr(model, "Windup", nil)
	end
	if state == "windup" then
		local rig = rigs[mon]
		if rig then
			hold(mon, rig)
		end
	end
end

local function stopAttackTracks(mon: Mon, rig: Rig)
	for _, attackId in mon.def.attacks do
		stopTrack(rig, attackId, 0.1)
	end
end

-- Cancels a running attack (no damage) and puts the monster in `state` for a moment.
local function interrupt(mon: Mon, state: string)
	local rig = rigs[mon]
	mon.seq += 1
	if rig then
		rig.dashing = false
		stopAttackTracks(mon, rig)
	end
	mon.busyUntil = now() + RECOVER
	setState(mon, state)
end

local function runAttack(mon: Mon, attackId: string, target: Player?, seq: number)
	if not mon.alive or mon.seq ~= seq then
		return
	end
	local ok, err = pcall(Attacks.run, mon, attackId, target)
	if not ok then
		warn(`[Monsters] attack {attackId} failed: {err}`)
	end
	if mon.alive and mon.seq == seq then
		local rig = rigs[mon]
		if rig then
			rig.dashing = false
		end
		mon.busyUntil = now() + RECOVER
		setState(mon, "recover")
	end
end

local function startAttack(mon: Mon, rig: Rig, attackId: string, target: Player?, t: number)
	local a = Config.Attacks[attackId]
	if not a then
		return
	end
	mon.seq += 1
	rig.cd[attackId] = t + a.cooldown
	mon.nextAttack = t + Attacks.windupFor(a) + 0.5
	setState(mon, "windup", attackId, Attacks.windupFor(a))
	task.defer(runAttack, mon, attackId, target, mon.seq)
end

-- Boss intro roar: 1.5 s invulnerable, roar hook, camera shake for whoever fights it.
local function startRoar(mon: Mon, rig: Rig, t: number)
	rig.invulnUntil = t + BOSS_ROAR
	mon.busyUntil = t + BOSS_ROAR
	mon.nextAttack = t + BOSS_ROAR + 0.4
	setState(mon, "roar")
	playTrack(rig, "roar", 0.05)
	for _, player in Monsters.send(mon) do
		Notify.fx(player, { k = "Shake", amount = SHAKE_ROAR })
	end
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local existing = Workspace:FindFirstChild("Monsters")
	if existing and existing:IsA("Folder") then
		f = existing
	else
		local made = Instance.new("Folder")
		made.Name = "Monsters"
		made.Parent = Workspace
		f = made
	end
	folder = f
	rebuildFilter()
	return f :: Folder
end

local function prepareParts(model: Model, root: BasePart)
	local junk: { Instance } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CollisionGroup = "Monsters"
			if d ~= root then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Massless = true
			end
		elseif d:IsA("BaseScript") then
			table.insert(junk, d)
		end
	end
	for _, d in junk do
		d:Destroy()
	end
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false -- hit tests are by distance (Combat uses hittableBy + positions)
	root.Massless = false
end

local function addGlow(model: Model, root: BasePart, def: MonsterDef)
	local kind = Config.KeyKinds[def.kind]
	local color = if kind then kind.glow else def.deathColor
	local light = Instance.new("PointLight")
	light.Name = "BossGlow"
	light.Color = color
	light.Brightness = 3
	light.Range = math.clamp(root.Size.Magnitude * 1.5, 16, 50)
	light.Shadows = false
	light.Parent = root
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Color = color
		end
	end
end

local function engageOf(def: MonsterDef): number
	local best = math.huge
	for _, id in def.attacks do
		local a = Config.Attacks[id]
		if a and a.shape ~= "summon" then
			best = math.min(best, a.range)
		end
	end
	return if best == math.huge then 4 else best
end

local function prefDistOf(def: MonsterDef): number
	local longest = 0
	for _, id in def.attacks do
		local a = Config.Attacks[id]
		if a then
			longest = math.max(longest, a.range)
		end
	end
	return math.clamp(longest * 0.6, 8, 24)
end

-- Spawns a monster. cf = where it appears (the plot's MonsterSpawn for openings). opts.emerge makes
-- it crawl / leap / burst out instead of appearing: towards the plot's middle when opts.plot is set,
-- else along cf.LookVector.
function Monsters.spawn(defId: string, cf: CFrame, opts: SpawnOpts): Mon
	local def = Config.Monsters[defId]
	assert(def, `[Monsters] unknown monster {defId}`)
	local parent = ensureFolder()
	local model = Assets.monster(def.model) or Templates.monster(def)
	local root = model.PrimaryPart :: BasePart
	local scale = if opts.scale and opts.scale > 0 then opts.scale else 1
	if scale ~= 1 then
		local ok, err = pcall(model.ScaleTo, model, model:GetScale() * scale)
		if not ok then
			warn(`[Monsters] ScaleTo failed for {defId}: {err}`)
		end
	end
	prepareParts(model, root)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local boss = opts.boss == true or def.boss
	if opts.glow then
		addGlow(model, root, def)
	end

	local att = root:FindFirstChild("RootAttachment")
	if not att or not att:IsA("Attachment") then
		local made = Instance.new("Attachment")
		made.Name = "RootAttachment"
		made.Parent = root
		att = made
	end
	local attachment = att :: Attachment

	nextId += 1
	local opening = opts.mode == "opening"
	local hp = math.max(1, def.hp * (opts.hpMult or 1))
	local mon: Mon = {
		id = nextId,
		def = def,
		model = model,
		root = root,
		hp = hp,
		maxHp = hp,
		dmg = math.max(0, def.damage * (opts.dmgMult or 1)),
		mode = opts.mode,
		owner = opts.owner,
		plot = opts.plot,
		alive = true,
		state = "idle",
		target = if opening then opts.owner else nil,
		home = opts.home or cf,
		nextAttack = 0,
		attackIndex = 1,
		busyUntil = 0,
		data = {},
		opts = opts,
		boss = boss,
		lastBy = nil,
		seq = 0,
	}

	-- placement: the pivot (bottom centre) on the ground at cf, or at the emerge start
	local look = Geometry.flatUnit(cf.LookVector) or Vector3.new(0, 0, -1)
	local plot = opts.plot
	if plot and opts.emerge then
		-- come out of the portal towards the middle of the plot (the marker may face either way)
		local ok, box = pcall(plot.GetBoundingBox, plot)
		local toward = ok and Geometry.flatUnit(box.Position - cf.Position)
		if toward then
			look = toward
		end
	end
	local yaw = math.atan2(-look.X, -look.Z)
	local spawnGround = groundAt(cf.Position)
	local hover = if def.flying then def.hover * scale else 0
	local emerge: Emerge? = nil
	local startPos = spawnGround + Vector3.new(0, hover, 0)
	if opts.emerge then
		local style = EMERGE[def.emerge] and def.emerge or "burst"
		local e = EMERGE[style]
		local perp = Vector3.new(-look.Z, 0, look.X)
		local land = cf.Position + look * e.dist + perp * rng:NextNumber(-2.5, 2.5)
		land = groundAt(clampGoal(mon, land)) + Vector3.new(0, hover, 0)
		startPos = spawnGround - Vector3.new(0, e.sink * root.Size.Y * 0.5, 0)
		emerge = { style = style, from = startPos, to = land, t0 = now(), time = e.time, arc = e.arc }
	end
	model:PivotTo(CFrame.new(startPos) * CFrame.Angles(0, yaw, 0))
	local attOffset = attachment.WorldPosition.Y - startPos.Y

	local align = Instance.new("AlignPosition")
	align.Name = "Move"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = ALIGN_FORCE
	align.MaxVelocity = def.speed
	align.Responsiveness = ALIGN_RESPONSIVENESS
	align.ApplyAtCenterOfMass = true
	align.Position = attachment.WorldPosition
	align.Parent = root

	local orient = Instance.new("AlignOrientation")
	orient.Name = "Turn"
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.MaxTorque = ALIGN_FORCE
	orient.MaxAngularVelocity = if def.behaviour == "shield"
		then TURN_RATE_SHIELD
		elseif boss then TURN_RATE_BOSS
		else TURN_RATE
	orient.Responsiveness = TURN_RESPONSIVENESS
	orient.CFrame = CFrame.Angles(0, yaw, 0)
	orient.Parent = root

	local rig: Rig = {
		att = attachment,
		align = align,
		orient = orient,
		animator = AnimHooks.animatorOf(model),
		tracks = {},
		playing = nil,
		goal = attachment.WorldPosition,
		yaw = yaw,
		maxVel = def.speed,
		groundAt = cf.Position,
		groundY = spawnGround.Y,
		attOffset = attOffset,
		hover = hover,
		cd = {},
		engage = engageOf(def),
		prefDist = prefDistOf(def),
		strafe = if rng:NextNumber() < 0.5 then -1 else 1,
		strafeAt = 0,
		packAngle = (nextId * 2.39996) % (2 * math.pi), -- golden angle: wolves spread around
		packDir = if nextId % 2 == 0 then 1 else -1,
		packUntil = now() + rng:NextNumber(1.2, 2.4),
		packDash = 0,
		wanderAt = now() + rng:NextNumber(1, 4),
		retargetAt = 0,
		asleep = false,
		dashing = false,
		knockUntil = 0,
		invulnUntil = 0,
		emerge = emerge,
		bar = if boss then {} else nil,
		barSent = 0,
		barHp = -1,
	}
	for _, attackId in def.attacks do
		rig.cd[attackId] = 0
	end

	-- attributes (PLAN.md section 11)
	model:SetAttribute("MonsterId", mon.id)
	model:SetAttribute("Def", def.id)
	model:SetAttribute("HP", math.ceil(hp))
	model:SetAttribute("MaxHP", math.ceil(hp))
	model:SetAttribute("Owner", if opts.owner then opts.owner.UserId else 0)
	model:SetAttribute("Mode", opts.mode)
	model:SetAttribute("Boss", boss)
	model:SetAttribute("Kind", def.kind)
	model:SetAttribute("State", if emerge then "emerging" else "idle")
	if emerge then
		model:SetAttribute("Emerge", emerge.style)
	end
	model.Name = def.id
	CollectionService:AddTag(model, "Monster")

	model.Parent = parent
	pcall(root.SetNetworkOwner, root, nil)

	table.insert(list, mon)
	indexOf[mon] = #list
	rigs[mon] = rig
	byModel[model] = mon

	loadTracks(rig, def)
	if emerge then
		mon.state = "emerging"
		setMaxVel(rig, 80)
		playTrack(rig, "emerge", 0.05)
		local ev = { k = "Emerge", style = emerge.style, pos = emerge.to, kind = def.kind, model = model }
		if opts.owner then
			Notify.fx(opts.owner, ev)
		end
		fxNearExcept(emerge.to, ev, opts.owner)
	else
		setBase(rig, "idle")
		mon.nextAttack = now() + FIRST_ATTACK_DELAY
		if boss then
			startRoar(mon, rig, now())
		end
	end
	return mon
end

---------------------------------------------------------------------------
-- Damage, death, despawn
---------------------------------------------------------------------------

local function runDeathListener(fn: (mon: Mon, killer: Player?) -> (), mon: Mon, killer: Player?)
	local ok, err = pcall(fn, mon, killer)
	if not ok then
		warn(`[Monsters] onDeath listener error: {err}`)
	end
end

function Monsters.despawn(mon: Mon)
	local rig = rigs[mon]
	if not rig then
		return
	end
	rigs[mon] = nil
	if mon.alive then
		mon.alive = false
		mon.seq += 1
	end
	bossBarOff(rig)
	local i = indexOf[mon]
	if i then
		local last = list[#list]
		list[i] = last
		indexOf[last] = i
		list[#list] = nil
		indexOf[mon] = nil
	end
	byModel[mon.model] = nil
	Status.clear(mon)
	local animator = rig.animator
	if animator then
		AnimHooks.clear(animator)
	end
	mon.model:Destroy()
end

function Monsters.kill(mon: Mon, by: Player?)
	local rig = rigs[mon]
	if not mon.alive or not rig then
		return
	end
	mon.alive = false
	mon.hp = 0
	mon.seq += 1
	rig.dashing = false
	mon.state = "dead"
	local model = mon.model
	setAttr(model, "HP", 0)
	setAttr(model, "State", "dead")
	setAttr(model, "Attack", nil)
	setAttr(model, "Windup", nil)
	setAttr(model, "Emerge", nil)
	setAttr(model, "Dead", true)
	setGoalRaw(rig, mon.root.Position)
	setMaxVel(rig, 0)
	if rig.animator then
		AnimHooks.stopAll(rig.animator, 0.1)
	end
	playTrack(rig, "death", 0.05)
	bossBarOff(rig)

	local killer = if by and isPlayer(by) then by else mon.lastBy
	local pos = mon.root.Position
	local ev = { k = "Death", model = model, pos = pos, kind = mon.def.kind, monsterId = mon.def.id, boss = mon.boss }
	if mon.owner then
		Notify.fx(mon.owner, ev)
	end
	fxNearExcept(pos, ev, mon.owner)

	if killer and killer.Parent == Players then
		Bus.fire("MonsterBeaten", killer, mon.def.id, mon.mode)
		if mon.boss then
			Bus.fire("BossBeaten", killer, mon.def.id, mon.mode)
		end
	end
	for _, fn in deathListeners do
		task.spawn(runDeathListener, fn, mon, killer)
	end
	task.delay(DEATH_DESPAWN, Monsters.despawn, mon)
end

local function knockback(mon: Mon, rig: Rig, dir: Vector3?, by: Player?, knock: number)
	if rig.dashing or mon.state == "emerging" then
		return
	end
	local d = dir and Geometry.flatUnit(dir)
	if not d and by then
		local p = rootPosOf(by)
		d = p and Geometry.flatUnit(mon.root.Position - p)
	end
	if not d then
		return
	end
	local amount = knock * KNOCK_STUDS * (if mon.boss then BOSS_KNOCK else 1)
	if amount <= 0.05 then
		return
	end
	rig.knockUntil = now() + KNOCK_TIME
	setMaxVel(rig, math.max(mon.def.speed, amount / KNOCK_TIME * 1.5))
	moveTo(mon, rig, mon.root.Position + d * amount, rig.hover)
end

-- Deals damage. Returns true when this hit killed it. Heavy hits interrupt a wind-up (not on
-- bosses); knockback pushes the align target away (opts.knock, e.g. the Axe's bigger number).
function Monsters.damage(mon: Mon, amount: number, by: Player?, dir: Vector3?, opts: DamageOpts?): boolean
	local rig = rigs[mon]
	if not mon.alive or not rig or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	if amount == math.huge then
		amount = mon.hp
	end
	local t = now()
	if mon.state == "emerging" or t < rig.invulnUntil then
		return false
	end
	local player = if by and isPlayer(by) then by else nil
	if player then
		mon.lastBy = player
	end
	mon.hp = math.max(0, mon.hp - amount)
	local model = mon.model
	setAttr(model, "HP", math.ceil(mon.hp))
	model:SetAttribute("HitAt", Workspace:GetServerTimeNow())

	local power = opts and opts.power
	if power ~= "burn" then
		local heavy = opts ~= nil and opts.heavy == true
		if heavy and not mon.boss and mon.state == "windup" then
			interrupt(mon, "recover")
		end
		knockback(mon, rig, dir, player, (opts and opts.knock) or DEFAULT_KNOCK)
		if mon.hp > 0 then
			playTrack(rig, "hit", 0.05)
		end
	end
	for _, fn in damageListeners do
		local ok, err = pcall(fn, mon, amount, player)
		if not ok then
			warn(`[Monsters] onDamage listener error: {err}`)
		end
	end
	if mon.hp <= 0 and mon.alive then
		Monsters.kill(mon, player)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Queries and hooks
---------------------------------------------------------------------------

function Monsters.fromModel(model: Model): Mon?
	return byModel[model]
end

function Monsters.all(): { Mon }
	return table.clone(list)
end

-- Monsters this player may hit: their own opening monsters, or map / Rift monsters when they are
-- not inside an opening. Emerging monsters are not hittable yet.
function Monsters.hittableBy(player: Player): { Mon }
	local out: { Mon } = {}
	local busy = inOpening(player)
	for _, mon in list do
		if mon.alive and mon.state ~= "emerging" then
			if mon.mode == "opening" then
				if mon.owner == player then
					table.insert(out, mon)
				end
			elseif not busy then
				table.insert(out, mon)
			end
		end
	end
	return out
end

function Monsters.ownedBy(player: Player): { Mon }
	local out: { Mon } = {}
	for _, mon in list do
		if mon.owner == player then
			table.insert(out, mon)
		end
	end
	return out
end

-- Alive opening monsters owned by this player.
function Monsters.countOwned(player: Player): number
	local n = 0
	for _, mon in list do
		if mon.alive and mon.owner == player and mon.mode == "opening" then
			n += 1
		end
	end
	return n
end

function Monsters.setTarget(mon: Mon, player: Player?)
	mon.target = player
end

-- True when a shield monster (shieldArc > 0) blocks a hit coming from fromPos (its front).
function Monsters.blocks(mon: Mon, fromPos: Vector3): boolean
	local arc = mon.def.shieldArc
	if not mon.alive or arc <= 0 or mon.state == "stagger" or Status.isStaggered(mon) then
		return false
	end
	local root = mon.root
	return Attacks.blocks(root.Position, root.CFrame.LookVector, arc, fromPos)
end

function Monsters.setPlayerDamage(fn: (player: Player, amount: number, src: Attacks.HurtSrc) -> ())
	playerDamage = fn
end

function Monsters.onDamage(fn: (mon: Mon, amount: number, by: Player?) -> ())
	table.insert(damageListeners, fn)
end

function Monsters.onDeath(fn: (mon: Mon, killer: Player?) -> ())
	table.insert(deathListeners, fn)
end

-- Despawns every monster this player owns (owner left, opening torn down).
function Monsters.despawnOwned(player: Player)
	for i = #list, 1, -1 do
		local mon = list[i]
		if mon and mon.owner == player then
			Attacks.clear(mon)
			Monsters.despawn(mon)
		end
	end
end

-- Alive monsters (debug and MapMonsters.count style checks).
function Monsters.count(): number
	local n = 0
	for _, mon in list do
		if mon.alive then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- AI
---------------------------------------------------------------------------

local function countMode(mode: string): number
	local n = 0
	for _, mon in list do
		if mon.alive and mon.mode == mode then
			n += 1
		end
	end
	return n
end

local function countSummons(summoner: Mon): number
	local n = 0
	for _, mon in list do
		if mon.alive and mon.data.summoner == summoner then
			n += 1
		end
	end
	return n
end

local function nearest(pos: Vector3, maxDist: number, mode: string): (Player?, number)
	local best: Player? = nil
	local bestD = maxDist
	for _, player in Players:GetPlayers() do
		if targetable(player) then
			local ok = if mode == "rift" then riftParticipant(player) else not inOpening(player)
			if ok then
				local p = rootPosOf(player) :: Vector3
				local d = Geometry.flatDistance(p, pos)
				if d <= bestD then
					best = player
					bestD = d
				end
			end
		end
	end
	return best, bestD
end

-- Nearest player distance of any kind (map sleep check).
local function nearestAny(pos: Vector3): number
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local p = rootPosOf(player)
		if p then
			local d = (p - pos).Magnitude
			if d < best then
				best = d
			end
		end
	end
	return best
end

local function finishEmerge(mon: Mon, rig: Rig, t: number)
	rig.emerge = nil
	setAttr(mon.model, "Emerge", nil)
	stopTrack(rig, "emerge", 0.1)
	setBase(rig, "idle")
	setMaxVel(rig, mon.def.speed)
	mon.nextAttack = t + FIRST_ATTACK_DELAY
	if mon.boss then
		startRoar(mon, rig, t)
	else
		setState(mon, "chase")
	end
end

local function stepEmerge(mon: Mon, rig: Rig, e: Emerge, t: number)
	local u = math.clamp((t - e.t0) / e.time, 0, 1)
	local ease = 1 - (1 - u) * (1 - u)
	local p = e.from:Lerp(e.to, ease) + Vector3.new(0, e.arc * 4 * u * (1 - u), 0)
	setGoalRaw(rig, p + Vector3.new(0, rig.attOffset, 0))
	faceTo(mon, rig, e.to + (e.to - e.from))
	if u >= 1 then
		finishEmerge(mon, rig, t)
	end
end

-- Picks this tick's target. Returns the target and its flat distance.
local function pickTarget(mon: Mon, rig: Rig, pos: Vector3, t: number): (Player?, number)
	local def = mon.def
	if mon.mode == "opening" then
		local owner = mon.owner
		if owner and targetable(owner) then
			mon.target = owner
			return owner, Geometry.flatDistance(rootPosOf(owner) :: Vector3, pos)
		end
		mon.target = nil
		return nil, math.huge
	end
	local current = mon.target
	if mon.mode == "rift" then
		if current and targetable(current) and riftParticipant(current) and t < rig.retargetAt then
			return current, Geometry.flatDistance(rootPosOf(current) :: Vector3, pos)
		end
		rig.retargetAt = t + RIFT_RETARGET
		local best, d = nearest(pos, math.huge, "rift")
		mon.target = best
		return best, d
	end
	-- map: keep chasing until the player runs past giveUp or out of reach of the leash
	-- (goals are clamped to the leash, so the target's distance from home is what counts)
	if current and targetable(current) and not inOpening(current) then
		local tp = rootPosOf(current) :: Vector3
		local d = Geometry.flatDistance(tp, pos)
		local home = mon.home
		local targetFromHome = if home then Geometry.flatDistance(tp, home.Position) else 0
		if d <= def.giveUp and targetFromHome <= def.leash + rig.engage + LEASH_SLACK then
			return current, d
		end
		mon.target = nil
		setState(mon, "return")
		return nil, math.huge
	end
	mon.target = nil
	local best, d = nearest(pos, def.notice, "map")
	if best then
		mon.target = best
		if mon.state ~= "chase" then
			setState(mon, "chase")
		end
	end
	return best, d
end

local function stepReturn(mon: Mon, rig: Rig, pos: Vector3, speed: number)
	local home = mon.home
	if not home or Geometry.flatDistance(pos, home.Position) <= HOME_REACHED then
		-- home: heal fully
		mon.hp = mon.maxHp
		setAttr(mon.model, "HP", math.ceil(mon.hp))
		setState(mon, "idle")
		hold(mon, rig)
		return
	end
	setMaxVel(rig, speed * RETURN_SPEED)
	moveTo(mon, rig, home.Position, rig.hover)
	faceTo(mon, rig, home.Position)
end

local function stepIdle(mon: Mon, rig: Rig, pos: Vector3, speed: number, t: number)
	if mon.mode ~= "map" then
		hold(mon, rig)
		return
	end
	local home = mon.home
	if home and Geometry.flatDistance(pos, home.Position) > mon.def.leash * 0.6 then
		setState(mon, "return")
		return
	end
	if t >= rig.wanderAt and home then
		rig.wanderAt = t + rng:NextNumber(3, 7)
		local radius = math.min(WANDER_RADIUS, mon.def.leash * 0.3)
		local goal = Geometry.randomInCircle(home.Position, radius, rng)
		setMaxVel(rig, speed * WANDER_SPEED)
		moveTo(mon, rig, goal, rig.hover)
		faceTo(mon, rig, goal)
		setState(mon, "wander")
	elseif mon.state == "wander" and Geometry.flatDistance(pos, rig.goal) < 1.5 then
		setState(mon, "idle")
	end
end

-- Movement while chasing, by behaviour.
local function stepChase(mon: Mon, rig: Rig, pos: Vector3, tp: Vector3, speed: number, t: number)
	local behaviour = mon.def.behaviour
	local mult = 1
	local goal: Vector3
	if behaviour == "float" then
		if t >= rig.strafeAt then
			rig.strafeAt = t + rng:NextNumber(2.5, 4)
			rig.strafe = -rig.strafe
		end
		goal = Attacks.strafePoint(pos, tp, rig.prefDist, rig.strafe, FLOAT_DRIFT)
	elseif behaviour == "pack" then
		if t < rig.packDash then
			mult = PACK_DASH_SPEED
			goal = Attacks.approachPoint(pos, tp, rig.engage * 0.7)
		else
			local angle = rig.packAngle + t * PACK_SPIN * rig.packDir
			goal = Attacks.circlePoint(tp, angle, PACK_RADIUS)
			if t >= rig.packUntil then
				rig.packDash = t + PACK_DASH
				rig.packUntil = t + PACK_DASH + rng:NextNumber(1.5, 3)
			end
		end
	else
		goal = Attacks.approachPoint(pos, tp, rig.engage * 0.8)
	end
	setMaxVel(rig, speed * mult)
	moveTo(mon, rig, goal, rig.hover)
	faceTo(mon, rig, tp)
end

-- How many summons fit: openings and the Rift never pass Waves.maxAlive + 4; map casters keep
-- at most twice their summon count alive.
local function roomFor(mon: Mon, wanted: number): number
	if mon.mode == "opening" then
		local owner = mon.owner
		if not owner then
			return 0
		end
		return Attacks.summonRoom(Monsters.countOwned(owner), Config.Waves.maxAlive + 4, wanted)
	elseif mon.mode == "rift" then
		return Attacks.summonRoom(countMode("rift"), Config.Waves.maxAlive + 4, wanted)
	end
	return Attacks.summonRoom(countSummons(mon), wanted * 2, wanted)
end

local function tryAttack(mon: Mon, rig: Rig, target: Player, d: number, t: number)
	if t < mon.nextAttack then
		return
	end
	local behaviour = mon.def.behaviour
	-- pack wolves only bite during a dash-in
	if behaviour == "pack" and t >= rig.packDash then
		return
	end
	local rotate = behaviour == "boss"
	local id, nextIndex = Attacks.chooseAttack(mon.def.attacks, rig.cd, t, d, mon.attackIndex, rotate)
	if not id then
		return
	end
	local a = Config.Attacks[id]
	if a and a.shape == "summon" and a.summon and roomFor(mon, a.summon.count) <= 0 then
		rig.cd[id] = t + 2 -- nothing fits; try again a little later
		mon.attackIndex = nextIndex
		return
	end
	mon.attackIndex = nextIndex
	if behaviour == "pack" then
		rig.packDash = 0
		rig.packUntil = t + rng:NextNumber(1.5, 3)
	end
	startAttack(mon, rig, id, target, t)
end

local function stepMon(mon: Mon, t: number)
	local rig = rigs[mon]
	if not rig or not mon.alive then
		return
	end
	local root = mon.root
	if root.Parent == nil then
		Monsters.despawn(mon)
		return
	end
	local e = rig.emerge
	if e then
		stepEmerge(mon, rig, e, t)
		return
	end
	if mon.boss then
		bossBarUpdate(mon, rig, t)
	end
	local state = mon.state
	if state == "windup" or state == "attack" then
		return -- Attacks drives movement and facing
	end
	if t < rig.knockUntil then
		return
	end
	local pos = root.Position

	-- map monsters sleep when nobody is near (align target held)
	if mon.mode == "map" then
		local asleep = nearestAny(pos) > Config.MapMonsters.activeRadius
		if asleep then
			if not rig.asleep then
				rig.asleep = true
				mon.target = nil
				hold(mon, rig)
				setBase(rig, "idle")
				if state ~= "return" then
					setState(mon, "idle")
				end
			end
			return
		end
		rig.asleep = false
	end

	local speed = mon.def.speed * Status.speedMult(mon)
	if state == "stagger" then
		if Status.isStaggered(mon) or t < mon.busyUntil then
			setMaxVel(rig, 0)
			return
		end
		setState(mon, "chase")
	elseif state == "recover" or state == "roar" then
		if t < mon.busyUntil then
			hold(mon, rig)
			local target = mon.target
			local tp = target and rootPosOf(target)
			if tp then
				faceTo(mon, rig, tp)
			end
			return
		end
		setState(mon, "chase")
	end

	if mon.state == "return" then
		stepReturn(mon, rig, pos, speed)
	else
		local target, d = pickTarget(mon, rig, pos, t)
		if mon.state == "return" then
			stepReturn(mon, rig, pos, speed)
		elseif target then
			local tp = rootPosOf(target) :: Vector3
			if mon.state ~= "chase" then
				setState(mon, "chase")
			end
			stepChase(mon, rig, pos, tp, speed, t)
			tryAttack(mon, rig, target, d, t)
		else
			if mon.state == "chase" then
				setState(mon, "idle")
			end
			stepIdle(mon, rig, pos, speed, t)
		end
	end

	if mon.state ~= "windup" then
		local moving = rig.maxVel > 0.5 and Geometry.flatDistance(pos, rig.goal) > 1.2
		setBase(rig, if moving then "move" else "idle")
	end
end

local function tickAll()
	local t = now()
	Status.tick()
	Attacks.tick(t)
	-- walk backwards: a despawn swaps the last monster into the freed slot
	for i = #list, 1, -1 do
		local mon = list[i]
		if mon then
			local ok, err = pcall(stepMon, mon, t)
			if not ok then
				warn(`[Monsters] AI error ({mon.def.id}): {err}`)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Attacks context
---------------------------------------------------------------------------

local function ctxHurt(player: Player, amount: number, src: Attacks.HurtSrc)
	local fn = playerDamage
	if fn and player.Parent == Players then
		fn(player, amount, src)
	end
end

local function ctxActive(mon: Mon): boolean
	if mon.mode == "opening" then
		local owner = mon.owner
		return owner ~= nil and owner.Parent == Players and Monsters.countOwned(owner) > 0
	end
	return true
end

local function ctxPlayAttack(mon: Mon, attackId: string)
	local rig = rigs[mon]
	if rig then
		playTrack(rig, attackId, 0.05)
	end
end

local function ctxFace(mon: Mon, pos: Vector3)
	local rig = rigs[mon]
	if rig then
		faceTo(mon, rig, pos)
	end
end

local function ctxDash(mon: Mon, groundPos: Vector3, speed: number, lift: number)
	local rig = rigs[mon]
	if not rig then
		return
	end
	rig.dashing = true
	setMaxVel(rig, speed)
	faceTo(mon, rig, groundPos)
	rig.groundAt = groundPos
	rig.groundY = groundPos.Y
	setGoalRaw(rig, groundPos + Vector3.new(0, rig.attOffset + lift, 0))
	setBase(rig, "move")
end

local function ctxEndDash(mon: Mon)
	local rig = rigs[mon]
	if rig then
		rig.dashing = false
		setMaxVel(rig, mon.def.speed)
		hold(mon, rig)
	end
end

local function ctxTeleport(mon: Mon, groundPos: Vector3, facePos: Vector3)
	local rig = rigs[mon]
	if not rig then
		return
	end
	local dx, dz = facePos.X - groundPos.X, facePos.Z - groundPos.Z
	local yaw = if dx * dx + dz * dz > 0.01 then math.atan2(-dx, -dz) else rig.yaw
	local base = groundPos + Vector3.new(0, rig.hover, 0)
	mon.model:PivotTo(CFrame.new(base) * CFrame.Angles(0, yaw, 0))
	rig.groundAt = groundPos
	rig.groundY = groundPos.Y
	setGoalRaw(rig, base + Vector3.new(0, rig.attOffset, 0))
	faceYaw(rig, yaw)
end

local function ctxArena(mon: Mon, radius: number, _near: Vector3): (Vector3, number)
	if mon.mode == "rift" then
		return Config.Map.riftCenter, math.min(radius, Config.Map.riftRadius)
	end
	local plot = mon.plot
	if mon.mode == "opening" and plot then
		local ok, cf, size = pcall(plot.GetBoundingBox, plot)
		if ok then
			local half = math.min(size.X, size.Z) / 2 - 2
			return cf.Position, math.clamp(half, 10, radius)
		end
	end
	return mon.root.Position, radius
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	Monsters.despawnOwned(player)
	for _, mon in list do
		if mon.target == player then
			mon.target = nil
		end
		if mon.lastBy == player then
			mon.lastBy = nil
		end
		local rig = rigs[mon]
		if rig and rig.bar then
			rig.bar[player] = nil
		end
	end
	Status.clear(player)
	task.defer(rebuildFilter)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		task.defer(rebuildFilter)
	end)
	player.CharacterRemoving:Connect(function()
		task.defer(rebuildFilter)
	end)
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

function Monsters.init()
	pcall(function()
		for _, name in { "Players", "Monsters", "Fx" } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable("Players", "Monsters", false)
		for _, name in { "Players", "Monsters", "Fx", "Default" } do
			PhysicsService:CollisionGroupSetCollidable("Fx", name, false)
		end
	end)
	ensureFolder()
	remotes.boss = Net.find("Boss")
	local folderR = ReplicatedStorage:FindFirstChild("Remotes")
	local fxU = folderR and folderR:FindFirstChild("FxU")
	if fxU and fxU:IsA("UnreliableRemoteEvent") then
		remotes.fxU = fxU
	end

	Attacks.bind({
		send = Monsters.send,
		hurt = ctxHurt,
		spawn = function(defId: string, cf: CFrame, opts: SpawnOpts): Mon?
			local ok, mon = pcall(Monsters.spawn, defId, cf, opts)
			if ok then
				return (mon :: any) :: Mon
			end
			warn(`[Monsters] summon failed: {mon}`)
			return nil
		end,
		room = roomFor,
		active = ctxActive,
		setState = setState,
		playAttack = ctxPlayAttack,
		face = ctxFace,
		dash = ctxDash,
		endDash = ctxEndDash,
		teleport = ctxTeleport,
		ground = groundAt,
		arena = ctxArena,
		clamp = clampGoal,
	})

	-- burn ticks: monsters take damage here; players go to the injected damage function
	Status.setBurnHandler(function(target: any, amount: number, source: any?)
		if type(target) == "table" and target.model and target.alive ~= nil then
			local mon = target :: Mon
			if rigs[mon] then
				Monsters.damage(mon, amount, if isPlayer(source) then source else nil, nil, { power = "burn" })
			end
		elseif isPlayer(target) then
			ctxHurt(target :: Player, amount, { mon = nil, heavy = false, attack = "burn" })
		end
	end)
	-- stagger cancels a running attack (bosses shrug it off but still stop moving)
	Status.setStaggerHandler(function(target: any, _duration: number)
		if type(target) == "table" and rigs[target :: Mon] then
			local mon = target :: Mon
			if mon.alive and not mon.boss and mon.state ~= "emerging" then
				interrupt(mon, "stagger")
			end
		end
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	PlayerData.onReady(sendBossBarsTo)
end

function Monsters.start()
	while true do
		task.wait(TICK)
		local ok, err = pcall(tickAll)
		if not ok then
			warn(`[Monsters] tick error: {err}`)
		end
	end
end

return Monsters
