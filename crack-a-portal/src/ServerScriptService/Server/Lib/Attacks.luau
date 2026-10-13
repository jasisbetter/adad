--!strict
-- Attacks: runs one monster attack from start to finish (PLAN.md section 7):
-- red warning zone (Warn remote) -> wind-up (>= 0.4 s when warned) -> strike -> resolution with
-- Geometry, status effects, hazards, summons. One shape function per Config.Attacks `shape`.
-- Monsters binds a context (Attacks.bind) so this module never requires Monsters or Combat.
-- A staggered or killed monster cancels its attack: every wait re-checks mon.seq and mon.alive.
-- Also holds the pure helpers the monster AI uses (attack choice, shield arc, pack and strafe
-- points), so they can be tested offline.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Geometry = require(Shared.Geometry)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Notify = require(script.Parent.Parent:WaitForChild("Systems"):WaitForChild("Notify"))

type AttackDef = Types.AttackDef
type MonsterDef = Types.MonsterDef
type StatusDef = Types.StatusDef
type WarnShape = Types.WarnShape

-- PLAN.md section 7 SpawnOpts.
export type SpawnOpts = {
	mode: string, -- "opening" | "map" | "rift"
	owner: Player?,
	plot: Model?,
	hpMult: number,
	dmgMult: number,
	coinMult: number?,
	home: CFrame?,
	emerge: boolean?,
	scale: number?,
	glow: boolean?,
	boss: boolean?,
	band: string?,
	area: string?,
}

-- PLAN.md section 7 Mon, plus: opts (the SpawnOpts it was made with), boss, lastBy (last
-- player who damaged it) and seq (attack sequence; an interrupt bumps it).
export type Mon = {
	id: number,
	def: MonsterDef,
	model: Model,
	root: BasePart,
	hp: number,
	maxHp: number,
	dmg: number,
	mode: string,
	owner: Player?,
	plot: Model?,
	alive: boolean,
	state: string,
	target: Player?,
	home: CFrame?,
	nextAttack: number,
	attackIndex: number,
	busyUntil: number,
	data: { [string]: any },
	opts: SpawnOpts,
	boss: boolean,
	lastBy: Player?,
	seq: number,
}

-- What the injected player-damage function receives (Combat.damagePlayer's src).
export type HurtSrc = {
	mon: Mon?,
	status: StatusDef?,
	heavy: boolean?,
	attack: string?,
}

-- Bound by Monsters in its init.
export type Ctx = {
	send: (mon: Mon) -> { Player }, -- who sees warnings and can be hit
	hurt: (player: Player, amount: number, src: HurtSrc) -> (),
	spawn: (defId: string, cf: CFrame, opts: SpawnOpts) -> Mon?,
	room: (mon: Mon, wanted: number) -> number, -- how many summons fit under the caps
	active: (mon: Mon) -> boolean, -- false once a hazard's fight is over (opening cleared)
	setState: (mon: Mon, state: string, attackId: string?, windup: number?) -> (),
	playAttack: (mon: Mon, attackId: string) -> (),
	face: (mon: Mon, pos: Vector3) -> (),
	dash: (mon: Mon, groundPos: Vector3, speed: number, lift: number) -> (),
	endDash: (mon: Mon) -> (),
	teleport: (mon: Mon, groundPos: Vector3, facePos: Vector3) -> (),
	ground: (pos: Vector3) -> Vector3,
	arena: (mon: Mon, radius: number, near: Vector3) -> (Vector3, number),
	clamp: (mon: Mon, pos: Vector3) -> Vector3,
}

local Attacks = {}

local MIN_WARN_WINDUP = 0.4
local PLAYER_RADIUS = 1.5 -- added to reach checks (player's body)
local HEIGHT_TOLERANCE = 9 -- studs above/below a ground shape that still get hit
local STEP = 0.05 -- simulation step for dashes and projectiles
local RAIN_GROUP = 3 -- circles per staggered group
local RAIN_GAP = 0.15 -- seconds between rain groups
local TELEPORT_STRIKE = 0.35 -- seconds between appearing and striking
local TELEPORT_BEHIND = 3.5
local HAZARD_TICK = 0.5
local MAX_HAZARDS = 48
local MAX_HAZARDS_PER_ATTACK = 4
local SHAKE_HIT = 0.6
local SHAKE_NEAR = 0.3

local ctx: Ctx? = nil
local rng = Random.new()
local warnId = 0
local warnRemote: RemoteEvent? = nil

type Hazard = {
	pos: Vector3,
	radius: number,
	dps: number, -- absolute damage per second
	untilT: number,
	nextT: number,
	who: { Player },
	mon: Mon,
	attack: string,
}
local hazards: { Hazard } = {}

---------------------------------------------------------------------------
-- Pure helpers (specs in ServerStorage/Tests/Attacks.spec.luau)
---------------------------------------------------------------------------

-- Wind-up time: at least 0.4 s for anything with a red warning.
function Attacks.windupFor(a: AttackDef): number
	if a.warn then
		return math.max(a.windup, MIN_WARN_WINDUP)
	end
	return math.max(a.windup, 0.05)
end

-- Slams with a reach close to their radius land on the monster; longer ones on the target.
function Attacks.slamAtSelf(a: AttackDef): boolean
	local radius = a.radius or 6
	return a.range <= radius * 1.5
end

-- `count` flat directions fanned around `dir`, `spreadDeg` degrees apart (centred).
function Attacks.spreadDirs(dir: Vector3, count: number, spreadDeg: number): { Vector3 }
	local base = Geometry.flatUnit(dir) or Vector3.new(0, 0, -1)
	local out: { Vector3 } = {}
	local n = math.max(1, math.floor(count))
	local yaw = math.atan2(base.X, base.Z)
	for i = 1, n do
		local offset = math.rad((i - (n + 1) / 2) * spreadDeg)
		local a = yaw + offset
		table.insert(out, Vector3.new(math.sin(a), 0, math.cos(a)))
	end
	return out
end

-- Rain circle centres: the first exactly on the target, the rest random inside `spread`.
function Attacks.rainPoints(center: Vector3, count: number, spread: number, r: Random): { Vector3 }
	local out: { Vector3 } = { center }
	for _ = 2, math.max(1, math.floor(count)) do
		table.insert(out, Geometry.randomInCircle(center, spread, r))
	end
	return out
end

-- A spot `dist` studs behind someone facing `look` (Void Shade teleport).
function Attacks.behindPoint(targetPos: Vector3, look: Vector3, dist: number): Vector3
	local d = Geometry.flatUnit(look) or Vector3.new(0, 0, -1)
	return targetPos - d * dist
end

-- True when a hit coming from `fromPos` lands inside the shield arc in front of origin/look.
function Attacks.blocks(origin: Vector3, look: Vector3, arcDeg: number, fromPos: Vector3): boolean
	if arcDeg <= 0 then
		return false
	end
	if Geometry.flatDistance(origin, fromPos) < 0.05 then
		return false
	end
	return Geometry.inCone(origin, look, math.huge, arcDeg, fromPos)
end

-- How many summons fit: never more than wanted, never past the cap.
function Attacks.summonRoom(current: number, cap: number, wanted: number): number
	return math.max(0, math.min(wanted, cap - current))
end

-- Picks the next attack. ready[id] = time it is off cooldown. Normal monsters take the ready
-- attack with the smallest range that still reaches `dist`; bosses (rotate = true) walk their
-- list from startIndex and take the first ready one in reach. Returns (id?, index of the next start).
function Attacks.chooseAttack(
	ids: { string },
	ready: { [string]: number },
	now: number,
	dist: number,
	startIndex: number,
	rotate: boolean
): (string?, number)
	local n = #ids
	if n == 0 then
		return nil, startIndex
	end
	if rotate then
		for step = 0, n - 1 do
			local i = (startIndex - 1 + step) % n + 1
			local id = ids[i]
			local a = Config.Attacks[id]
			if a and now >= (ready[id] or 0) and dist <= a.range then
				return id, i % n + 1
			end
		end
		return nil, startIndex
	end
	local best: string? = nil
	local bestRange = math.huge
	for _, id in ids do
		local a = Config.Attacks[id]
		if a and now >= (ready[id] or 0) and dist <= a.range and a.range < bestRange then
			best = id
			bestRange = a.range
		end
	end
	return best, startIndex
end

-- Where a monster walks to: `stopAt` studs short of the target (or stays if already that close).
function Attacks.approachPoint(myPos: Vector3, targetPos: Vector3, stopAt: number): Vector3
	local d = Geometry.flatDistance(myPos, targetPos)
	if d <= stopAt then
		return myPos
	end
	local dir = Geometry.flatUnit(targetPos - myPos) or Vector3.new(0, 0, -1)
	return targetPos - dir * stopAt
end

-- A point on a circle around the target (pack circling).
function Attacks.circlePoint(targetPos: Vector3, angle: number, radius: number): Vector3
	return Vector3.new(targetPos.X + math.sin(angle) * radius, targetPos.Y, targetPos.Z + math.cos(angle) * radius)
end

-- Floaters keep `pref` studs away and drift sideways (`side` = -1 or 1).
function Attacks.strafePoint(myPos: Vector3, targetPos: Vector3, pref: number, side: number, drift: number): Vector3
	local away = Geometry.flatUnit(myPos - targetPos) or Vector3.new(0, 0, 1)
	local perp = Vector3.new(-away.Z, 0, away.X)
	return targetPos + away * pref + perp * (side * drift)
end

---------------------------------------------------------------------------
-- Runtime helpers
---------------------------------------------------------------------------

function Attacks.bind(context: Ctx)
	ctx = context
end

local function getWarnRemote(): RemoteEvent?
	if not warnRemote then
		warnRemote = Net.find("Warn")
	end
	return warnRemote
end

local function posOf(player: Player): Vector3?
	if player.Parent == nil then
		return nil
	end
	local hp = player:GetAttribute("HP")
	if type(hp) == "number" and hp <= 0 then
		return nil
	end
	local character = player.Character
	local root = character and character.PrimaryPart
	return if root then root.Position else nil
end

local function lookOf(player: Player): Vector3
	local character = player.Character
	local root = character and character.PrimaryPart
	return if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
end

local function live(mon: Mon, seq: number): boolean
	return mon.alive and mon.seq == seq
end

-- task.wait, then whether the attack is still going.
local function waitLive(mon: Mon, seq: number, t: number): boolean
	if t > 0 then
		task.wait(t)
	end
	return live(mon, seq)
end

local function sendWarn(who: { Player }, shape: WarnShape)
	local remote = getWarnRemote()
	if not remote then
		return
	end
	for _, player in who do
		if player.Parent ~= nil then
			remote:FireClient(player, shape)
		end
	end
end

local function nextWarnId(): number
	warnId += 1
	return warnId
end

local function fxAll(who: { Player }, ev: Types.FxEvent)
	for _, player in who do
		Notify.fx(player, ev)
	end
end

local function groundCf(origin: Vector3, dir: Vector3): CFrame
	local d = Geometry.flatUnit(dir) or Vector3.new(0, 0, -1)
	return CFrame.lookAt(origin, origin + d)
end

local function heightOk(p: Vector3, groundY: number): boolean
	return p.Y >= groundY - HEIGHT_TOLERANCE * 0.5 and p.Y <= groundY + HEIGHT_TOLERANCE
end

local function damageOf(mon: Mon, a: AttackDef): number
	return mon.dmg * a.damage
end

local function hurt(c: Ctx, mon: Mon, a: AttackDef, player: Player, amount: number)
	if amount <= 0 then
		return
	end
	c.hurt(player, amount, { mon = mon, status = a.status, heavy = a.heavy, attack = a.id })
end

-- Camera shake for heavy attacks: harder for players who were hit, softer for those nearby.
local function shake(who: { Player }, center: Vector3, radius: number, hit: { [Player]: boolean })
	for _, player in who do
		if hit[player] then
			Notify.fx(player, { k = "Shake", amount = SHAKE_HIT })
		else
			local p = posOf(player)
			if p and Geometry.flatDistance(p, center) <= radius + 15 then
				Notify.fx(player, { k = "Shake", amount = SHAKE_NEAR })
			end
		end
	end
end

local function addHazard(mon: Mon, a: AttackDef, center: Vector3, who: { Player })
	local h = a.hazard
	if not h then
		return
	end
	if #hazards >= MAX_HAZARDS then
		table.remove(hazards, 1)
	end
	local now = os.clock()
	table.insert(hazards, {
		pos = center,
		radius = h.radius,
		dps = h.dps * mon.dmg,
		untilT = now + h.duration,
		nextT = now + HAZARD_TICK,
		who = who,
		mon = mon,
		attack = a.id,
	})
	fxAll(who, {
		k = "Hazard",
		pos = center,
		radius = h.radius,
		duration = h.duration,
		style = h.style,
		kind = mon.def.kind,
	})
end

-- Ground point in front of / under / at the target, with a sane fallback when the target is gone.
local function targetGround(c: Ctx, mon: Mon, target: Player?, fallbackDist: number): Vector3
	local p = target and posOf(target)
	if p then
		return c.ground(p)
	end
	local root = mon.root
	return c.ground(root.Position + root.CFrame.LookVector * fallbackDist)
end

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------

type ShapeFn = (c: Ctx, mon: Mon, a: AttackDef, target: Player?, seq: number, windup: number, who: { Player }) -> ()

local Shapes: { [string]: ShapeFn } = {}

-- Small attacks: short wind-up, no warning (unless the row says warn), hit in range and arc.
Shapes.melee = function(c, mon, a, target, seq, windup, who)
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	local arc = a.angle or 100
	local reach = a.range + PLAYER_RADIUS
	if a.warn then
		local origin = c.ground(mon.root.Position)
		sendWarn(who, {
			id = nextWarnId(),
			shape = "cone",
			cf = groundCf(origin, mon.root.CFrame.LookVector),
			duration = windup,
			length = reach,
			radius = reach,
			angle = arc,
			style = a.id,
		})
	end
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	-- keep tracking the target for the first half of the wind-up, then commit
	if not waitLive(mon, seq, windup * 0.5) then
		return
	end
	tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	if not waitLive(mon, seq, windup * 0.5) then
		return
	end
	c.setState(mon, "attack", a.id)
	local origin = mon.root.Position
	local look = mon.root.CFrame.LookVector
	local groundY = c.ground(origin).Y
	local amount = damageOf(mon, a)
	for _, player in who do
		local p = posOf(player)
		if p and heightOk(p, groundY) and Geometry.inCone(origin, look, reach, arc, p) then
			hurt(c, mon, a, player, amount)
		end
	end
	if a.hazard then
		local flatLook = Geometry.flatUnit(look) or Vector3.new(0, 0, -1)
		addHazard(mon, a, c.ground(origin + flatLook * a.range * 0.6), who)
	end
end

-- Red line that fills over the wind-up, then a dash along it; anyone in the path is hit once.
local function dashAttack(
	c: Ctx,
	mon: Mon,
	a: AttackDef,
	target: Player?,
	seq: number,
	windup: number,
	who: { Player },
	lift: number
)
	local origin = c.ground(mon.root.Position)
	local aim = targetGround(c, mon, target, a.length or 20)
	local dir = Geometry.flatUnit(aim - origin)
		or Geometry.flatUnit(mon.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local length = a.length or 20
	local width = a.width or 4
	local finish = c.clamp(mon, origin + dir * length)
	length = Geometry.flatDistance(origin, finish)
	c.face(mon, origin + dir * 10)
	sendWarn(who, {
		id = nextWarnId(),
		shape = "line",
		cf = groundCf(origin, dir),
		duration = windup,
		length = length,
		width = width,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local speed = a.speed or 50
	c.dash(mon, finish, speed, lift)
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	local prev = mon.root.Position
	local maxTime = length / speed + 0.4
	local t = 0
	while t < maxTime do
		task.wait(STEP)
		t += STEP
		if not live(mon, seq) then
			break
		end
		local cur = mon.root.Position
		for _, player in who do
			if not hit[player] then
				local p = posOf(player)
				if
					p
					and heightOk(p, origin.Y)
					and Geometry.distanceToSegment(prev, cur, p) <= width / 2 + PLAYER_RADIUS * 0.5
				then
					hit[player] = true
					hurt(c, mon, a, player, amount)
				end
			end
		end
		prev = cur
		if Geometry.flatDistance(cur, finish) < 1.5 then
			break
		end
	end
	c.endDash(mon)
	if a.heavy then
		shake(who, mon.root.Position, width, hit)
	end
end

Shapes.charge = function(c, mon, a, target, seq, windup, who)
	dashAttack(c, mon, a, target, seq, windup, who, 0)
end

-- Flyers: line warning, then a dive along it close to the ground; the AI lifts it back up after.
Shapes.swoop = function(c, mon, a, target, seq, windup, who)
	dashAttack(c, mon, a, target, seq, windup, who, 0.5)
end

-- Circle on the monster (short reach) or on the target (long reach).
Shapes.slam = function(c, mon, a, target, seq, windup, who)
	local radius = a.radius or 8
	local center = if Attacks.slamAtSelf(a)
		then c.ground(mon.root.Position)
		else c.clamp(mon, targetGround(c, mon, target, 6))
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	sendWarn(who, {
		id = nextWarnId(),
		shape = "circle",
		cf = CFrame.new(center),
		duration = windup,
		radius = radius,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	for _, player in who do
		local p = posOf(player)
		if p and heightOk(p, center.Y) and Geometry.inCircle(center, radius + PLAYER_RADIUS * 0.5, p) then
			hit[player] = true
			hurt(c, mon, a, player, amount)
		end
	end
	if a.hazard then
		addHazard(mon, a, center, who)
	end
	if a.heavy then
		shake(who, center, radius, hit)
	end
end

-- Cone in front (sweeps, breath, tail). With `duration` it keeps hurting while it lasts (once each).
Shapes.cone = function(c, mon, a, target, seq, windup, who)
	local origin = c.ground(mon.root.Position)
	local aim = targetGround(c, mon, target, 6)
	local dir = Geometry.flatUnit(aim - origin)
		or Geometry.flatUnit(mon.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local length = a.length or a.range
	local angle = a.angle or 90
	c.face(mon, origin + dir * 10)
	sendWarn(who, {
		id = nextWarnId(),
		shape = "cone",
		cf = groundCf(origin, dir),
		duration = windup,
		length = length,
		radius = length,
		angle = angle,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	local reach = length + PLAYER_RADIUS * 0.5
	local duration = a.duration or 0
	local t = 0
	repeat
		for _, player in who do
			if not hit[player] then
				local p = posOf(player)
				if p and heightOk(p, origin.Y) and Geometry.inCone(origin, dir, reach, angle, p) then
					hit[player] = true
					hurt(c, mon, a, player, amount)
				end
			end
		end
		if t >= duration then
			break
		end
		task.wait(0.1)
		t += 0.1
	until not live(mon, seq)
	if a.heavy then
		shake(who, origin, length, hit)
	end
end

-- Many small circles around the target, landing in staggered groups.
Shapes.rain = function(c, mon, a, target, seq, windup, who)
	local radius = a.radius or 4
	local center = c.clamp(mon, targetGround(c, mon, target, 8))
	local points = Attacks.rainPoints(center, a.count or 6, a.spread or 16, rng)
	for i, p in points do
		points[i] = c.ground(c.clamp(mon, p))
	end
	local groups = math.ceil(#points / RAIN_GROUP)
	for g = 1, groups do
		local circles: { Vector3 } = {}
		for i = (g - 1) * RAIN_GROUP + 1, math.min(#points, g * RAIN_GROUP) do
			table.insert(circles, points[i])
		end
		sendWarn(who, {
			id = nextWarnId(),
			shape = "rain",
			cf = CFrame.new(center),
			duration = windup + (g - 1) * RAIN_GAP,
			radius = radius,
			circles = circles,
			style = a.id,
		})
	end
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	local hazardsLeft = MAX_HAZARDS_PER_ATTACK
	for g = 1, groups do
		if g > 1 and not waitLive(mon, seq, RAIN_GAP) then
			break
		end
		for i = (g - 1) * RAIN_GROUP + 1, math.min(#points, g * RAIN_GROUP) do
			local spot = points[i]
			for _, player in who do
				if not hit[player] then
					local p = posOf(player)
					if p and heightOk(p, spot.Y) and Geometry.inCircle(spot, radius + PLAYER_RADIUS * 0.5, p) then
						hit[player] = true
						hurt(c, mon, a, player, amount)
					end
				end
			end
			if a.hazard and hazardsLeft > 0 then
				hazardsLeft -= 1
				addHazard(mon, a, spot, who)
			end
		end
	end
	if a.heavy then
		shake(who, center, (a.spread or 16), hit)
	end
end

-- Boulders / ice shards / void orbs. With `length`: shots fly along fanned lines (line warnings);
-- without: they land in circles at the target (landing-circle warnings). Flight is simulated here
-- and clients draw it from the Projectile Fx.
Shapes.projectile = function(c, mon, a, target, seq, windup, who)
	local origin = mon.root.Position
	local originGround = c.ground(origin)
	local speed = a.speed or 40
	local count = a.count or 1
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	local amount = damageOf(mon, a)
	local hit: { [Player]: boolean } = {}
	if a.length then
		local length = a.length
		local width = a.width or (a.radius or 1.5) * 2
		local aim = targetGround(c, mon, target, length)
		local dirs = Attacks.spreadDirs(aim - originGround, count, a.spread or 12)
		for _, dir in dirs do
			sendWarn(who, {
				id = nextWarnId(),
				shape = "line",
				cf = groundCf(originGround, dir),
				duration = windup,
				length = length,
				width = width,
				style = a.id,
			})
		end
		c.setState(mon, "windup", a.id, windup)
		c.playAttack(mon, a.id)
		if not waitLive(mon, seq, windup) then
			return
		end
		c.setState(mon, "attack", a.id)
		origin = mon.root.Position
		for _, dir in dirs do
			fxAll(who, {
				k = "Projectile",
				from = origin,
				to = origin + dir * length,
				speed = speed,
				style = a.id,
				radius = width / 2,
				kind = mon.def.kind,
			})
		end
		local flight = length / speed
		local t = 0
		while t < flight and mon.alive do
			task.wait(STEP)
			t += STEP
			local travelled = math.min(length, t * speed)
			for _, dir in dirs do
				local shot = origin + dir * travelled
				for _, player in who do
					if not hit[player] then
						local p = posOf(player)
						if p and Geometry.flatDistance(shot, p) <= width / 2 + PLAYER_RADIUS * 0.5 then
							hit[player] = true
							hurt(c, mon, a, player, amount)
						end
					end
				end
			end
		end
	else
		local radius = a.radius or 6
		local center = c.clamp(mon, targetGround(c, mon, target, 12))
		local spots = Attacks.rainPoints(center, count, a.spread or 8, rng)
		local flights: { number } = {}
		for i, spot in spots do
			spots[i] = c.ground(c.clamp(mon, spot))
			local flight = Geometry.flatDistance(origin, spots[i]) / speed
			flights[i] = flight
			sendWarn(who, {
				id = nextWarnId(),
				shape = "circle",
				cf = CFrame.new(spots[i]),
				duration = windup + flight,
				radius = radius,
				style = a.id,
			})
		end
		c.setState(mon, "windup", a.id, windup)
		c.playAttack(mon, a.id)
		if not waitLive(mon, seq, windup) then
			return
		end
		c.setState(mon, "attack", a.id)
		local from = mon.root.Position + Vector3.new(0, mon.root.Size.Y * 0.4, 0)
		for _, spot in spots do
			fxAll(who, {
				k = "Projectile",
				from = from,
				to = spot,
				speed = speed,
				style = a.id,
				radius = radius,
				kind = mon.def.kind,
			})
		end
		-- resolve each landing at its own impact time
		local order: { number } = {}
		for i = 1, #spots do
			order[i] = i
		end
		table.sort(order, function(x, y)
			return flights[x] < flights[y]
		end)
		local elapsed = 0
		for _, i in order do
			local waitFor = flights[i] - elapsed
			if waitFor > 0 then
				task.wait(waitFor)
				elapsed = flights[i]
			end
			if not mon.alive then
				return
			end
			local spot = spots[i]
			for _, player in who do
				if not hit[player] then
					local p = posOf(player)
					if p and heightOk(p, spot.Y) and Geometry.inCircle(spot, radius + PLAYER_RADIUS * 0.5, p) then
						hit[player] = true
						hurt(c, mon, a, player, amount)
					end
				end
			end
			if a.hazard then
				addHazard(mon, a, spot, who)
			end
		end
		if a.heavy then
			shake(who, center, radius + (a.spread or 0), hit)
		end
	end
end

-- Thin red line first, then the beam; damage along the line while it lasts (once each).
Shapes.beam = function(c, mon, a, target, seq, windup, who)
	local origin = mon.root.Position
	local originGround = c.ground(origin)
	local aim = targetGround(c, mon, target, a.length or 30)
	local dir = Geometry.flatUnit(aim - originGround)
		or Geometry.flatUnit(mon.root.CFrame.LookVector)
		or Vector3.new(0, 0, -1)
	local length = a.length or a.range
	local width = a.width or 3
	c.face(mon, originGround + dir * 10)
	sendWarn(who, {
		id = nextWarnId(),
		shape = "line",
		cf = groundCf(originGround, dir),
		duration = windup,
		length = length,
		width = width,
		style = "thin",
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local duration = a.duration or 0.5
	origin = mon.root.Position
	local to = Vector3.new(originGround.X, origin.Y, originGround.Z) + dir * length
	fxAll(who, {
		k = "Beam",
		from = origin,
		to = c.ground(to) + Vector3.new(0, 1, 0),
		width = width,
		duration = duration,
		style = a.id,
		kind = mon.def.kind,
	})
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	local t = 0
	repeat
		for _, player in who do
			if not hit[player] then
				local p = posOf(player)
				if p and Geometry.inLine(originGround, dir, length, width + PLAYER_RADIUS, p) then
					hit[player] = true
					hurt(c, mon, a, player, amount)
				end
			end
		end
		task.wait(0.1)
		t += 0.1
	until t >= duration or not live(mon, seq)
	if a.heavy then
		shake(who, originGround + dir * (length / 2), length / 2, hit)
	end
end

-- Spit a pool on the ground (Fx Hazard); it burns anyone standing in it.
Shapes.pool = function(c, mon, a, target, seq, windup, who)
	local h = a.hazard
	local radius = if h then h.radius else (a.radius or 5)
	local center = c.clamp(mon, targetGround(c, mon, target, 8))
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	sendWarn(who, {
		id = nextWarnId(),
		shape = "circle",
		cf = CFrame.new(center),
		duration = windup,
		radius = radius,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local amount = damageOf(mon, a)
	if amount > 0 then
		for _, player in who do
			local p = posOf(player)
			if p and heightOk(p, center.Y) and Geometry.inCircle(center, radius, p) then
				hurt(c, mon, a, player, amount)
			end
		end
	end
	addHazard(mon, a, center, who)
end

-- Purple flash where it will appear (behind the target) first, then appear and strike.
Shapes.teleport = function(c, mon, a, target, seq, windup, who)
	local tp = target and posOf(target)
	if not target or not tp then
		return
	end
	local dest = c.ground(c.clamp(mon, Attacks.behindPoint(tp, lookOf(target), TELEPORT_BEHIND)))
	local radius = a.radius or 5
	fxAll(who, { k = "Teleport", from = mon.root.Position, to = dest, model = mon.model })
	sendWarn(who, {
		id = nextWarnId(),
		shape = "circle",
		cf = CFrame.new(dest),
		duration = windup + TELEPORT_STRIKE,
		radius = radius,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup + TELEPORT_STRIKE)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	local facePos = posOf(target) or tp
	c.teleport(mon, dest, facePos)
	if not waitLive(mon, seq, TELEPORT_STRIKE) then
		return
	end
	c.setState(mon, "attack", a.id)
	local amount = damageOf(mon, a)
	for _, player in who do
		local p = posOf(player)
		if p and heightOk(p, dest.Y) and Geometry.inCircle(dest, radius + PLAYER_RADIUS * 0.5, p) then
			hurt(c, mon, a, player, amount)
		end
	end
end

-- Calls more monsters around the caster (same owner, mode, plot and wave multipliers), capped.
Shapes.summon = function(c, mon, a, target, seq, windup, who)
	local s = a.summon
	if not s then
		return
	end
	local tp = target and posOf(target)
	if tp then
		c.face(mon, tp)
	end
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local n = c.room(mon, s.count)
	if n <= 0 then
		return
	end
	local opts = mon.opts
	local hpMult = opts.hpMult
	if mon.mode == "rift" and mon.boss then
		hpMult /= math.max(1, Config.Rift.bossHp) -- the boss's extra Rift health is not passed on
	end
	local center = mon.root.Position
	local ring = Geometry.ringPoints(center, math.max(5, mon.root.Size.X), n, rng:NextNumber() * math.pi * 2)
	for _, p in ring do
		local spot = c.ground(c.clamp(mon, p))
		local out = Geometry.flatUnit(spot - center) or Vector3.new(0, 0, -1)
		local child = c.spawn(s.monster, CFrame.lookAt(spot, spot + out), {
			mode = mon.mode,
			owner = mon.owner,
			plot = mon.plot,
			hpMult = hpMult,
			dmgMult = opts.dmgMult,
			coinMult = opts.coinMult,
			home = mon.home,
			emerge = true,
			band = opts.band,
			area = opts.area,
		})
		if child then
			child.data.summoned = true
			child.data.summoner = mon
			child.target = mon.target
		end
	end
	for _, player in who do
		Notify.fx(player, { k = "Shake", amount = SHAKE_NEAR })
	end
end

-- Full-arena slam: everything is red except a few safe circles, then everyone outside them is hit.
Shapes.arena = function(c, mon, a, target, seq, windup, who)
	local near = (target and posOf(target)) or mon.root.Position
	local center, radius = c.arena(mon, a.radius or 30, near)
	center = c.ground(center)
	local safeRadius = a.safeRadius or 7
	local safe = Geometry.safeSpots(center, radius, a.safeSpots or 3, safeRadius, rng)
	for i, spot in safe do
		safe[i] = Vector3.new(spot.X, center.Y, spot.Z)
	end
	sendWarn(who, {
		id = nextWarnId(),
		shape = "arena",
		cf = CFrame.new(center),
		duration = windup,
		radius = radius,
		safe = safe,
		safeRadius = safeRadius,
		style = a.id,
	})
	c.setState(mon, "windup", a.id, windup)
	c.playAttack(mon, a.id)
	if not waitLive(mon, seq, windup) then
		return
	end
	c.setState(mon, "attack", a.id)
	local hit: { [Player]: boolean } = {}
	local amount = damageOf(mon, a)
	for _, player in who do
		local p = posOf(player)
		-- the safe circles are a little generous (half a body) so a player on the edge is safe
		if
			p
			and heightOk(p, center.Y)
			and Geometry.inArena(center, radius, p, safe, safeRadius + PLAYER_RADIUS * 0.5)
		then
			hit[player] = true
			hurt(c, mon, a, player, amount)
		end
	end
	for _, player in who do
		Notify.fx(player, { k = "Shake", amount = if hit[player] then SHAKE_HIT else SHAKE_NEAR })
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Runs one attack to the end (yields). Monsters bumps mon.seq before calling; an interrupt or
-- death bumps it again and the attack stops at its next check without dealing damage.
function Attacks.run(mon: Mon, attackId: string, target: Player?)
	local c = ctx
	local a = Config.Attacks[attackId]
	if not c or not a or not mon.alive then
		return
	end
	local fn = Shapes[a.shape]
	if not fn then
		warn(`[Attacks] unknown shape {a.shape} for {attackId}`)
		return
	end
	local seq = mon.seq
	local who = c.send(mon)
	fn(c, mon, a, target, seq, Attacks.windupFor(a), who)
end

-- Hazard damage (fire pools, embers): direct ticks every 0.5 s. Called by the Monsters loop.
function Attacks.tick(now: number)
	local c = ctx
	if not c then
		return
	end
	for i = #hazards, 1, -1 do
		local h = hazards[i]
		if now >= h.untilT or not c.active(h.mon) then
			hazards[i] = hazards[#hazards]
			hazards[#hazards] = nil
			continue
		end
		if now >= h.nextT then
			h.nextT += HAZARD_TICK
			local amount = h.dps * HAZARD_TICK
			for _, player in h.who do
				local p = posOf(player)
				if p and heightOk(p, h.pos.Y) and Geometry.inCircle(h.pos, h.radius, p) then
					c.hurt(player, amount, { mon = h.mon, heavy = false, attack = h.attack })
				end
			end
		end
	end
end

-- Drops hazards made by this monster (owner left or the fight was torn down).
function Attacks.clear(mon: Mon)
	for i = #hazards, 1, -1 do
		if hazards[i].mon == mon then
			hazards[i] = hazards[#hazards]
			hazards[#hazards] = nil
		end
	end
end

-- Hazards still burning (debug / tests).
function Attacks.hazardCount(): number
	return #hazards
end

return Attacks
