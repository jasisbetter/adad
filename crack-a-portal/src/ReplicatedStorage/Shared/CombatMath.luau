--!strict
-- CombatMath: pure combo and swing maths shared by the server (Combat decides hits) and the
-- client (Combat predicts the swing it plays). No instances, flat (Y ignored) unless noted.

local Shared = script.Parent
local Geometry = require(Shared.Geometry)
local Types = require(Shared.Types)

type ComboStep = Types.ComboStep

local CombatMath = {}

-- Seconds a combo step may arrive early (network jitter between two taps).
CombatMath.LATENCY = 0.08
-- Extra vertical reach on top of the swing range (flyers hover above the ground).
CombatMath.VERTICAL_SLACK = 6

-- Whole time of a step: the hit lands at the end of windup, then contact and recover.
function CombatMath.stepTime(step: ComboStep): number
	return step.windup + step.contact + step.recover
end

-- Which combo step a new swing is.
--   prevStep: the last swing's step (0 = none yet), prevStepTime: that step's stepTime,
--   elapsed: seconds since the last swing started, comboLen: steps in the combo,
--   reset: the weapon's comboReset, grace: Config.Combat.comboGrace.
-- Returns nil when the swing comes too early (ignored, no queueing), 1 when the combo
-- restarts (after the finisher or after reset + grace), else prevStep + 1.
function CombatMath.nextStep(
	prevStep: number,
	prevStepTime: number,
	elapsed: number,
	comboLen: number,
	reset: number,
	grace: number,
	latency: number?
): number?
	if prevStep <= 0 or comboLen <= 0 then
		return 1
	end
	if elapsed ~= elapsed or elapsed < prevStepTime - (latency or CombatMath.LATENCY) then
		return nil
	end
	if prevStep >= comboLen or elapsed > reset + grace then
		return 1
	end
	return prevStep + 1
end

-- Body radius on the ground for a monster of this size (half the mean of width and depth).
function CombatMath.targetRadius(size: Vector3): number
	return (size.X + size.Z) / 4
end

-- True when a target at `pos` with body radius `targetRadius` is hit by a swing from `origin`
-- facing `dir`: within range and the arc (full opening, degrees), or within `radius` all
-- around (finishers). The target's body counts, so big monsters are easier to reach.
function CombatMath.inSwing(
	origin: Vector3,
	dir: Vector3,
	pos: Vector3,
	targetRadius: number,
	range: number,
	arc: number,
	radius: number?,
	height: number?
): boolean
	local dy = math.abs(pos.Y - origin.Y)
	if dy > range + (height or 0) / 2 + CombatMath.VERTICAL_SLACK then
		return false
	end
	local dx, dz = pos.X - origin.X, pos.Z - origin.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if radius and dist <= radius + targetRadius then
		return true
	end
	if dist > range + targetRadius then
		return false
	end
	if dist <= targetRadius + 0.5 or arc >= 360 then
		return true -- standing in it
	end
	local facing = Geometry.flatUnit(dir)
	if not facing then
		return false
	end
	local half = math.rad(arc / 2) + math.asin(math.min(1, targetRadius / dist))
	if half >= math.pi then
		return true
	end
	local dot = (dx * facing.X + dz * facing.Z) / dist
	return dot >= math.cos(half)
end

-- Flat unit direction from origin toward target, or the flattened fallback (or -Z).
function CombatMath.faceDirection(origin: Vector3, fallback: Vector3, target: Vector3?): Vector3
	if target then
		local toward = Geometry.flatUnit(target - origin)
		if toward then
			return toward
		end
	end
	return Geometry.flatUnit(fallback) or Vector3.new(0, 0, -1)
end

-- Index of the nearest point within `range` (flat distance minus its body radius), or nil.
function CombatMath.nearest(origin: Vector3, points: { Vector3 }, radii: { number }, range: number): number?
	local best: number? = nil
	local bestDist = math.huge
	for i, p in points do
		local d = Geometry.flatDistance(origin, p) - (radii[i] or 0)
		if d <= range and d < bestDist then
			best = i
			bestDist = d
		end
	end
	return best
end

-- True when moving from a to b in dt seconds stays at or under maxSpeed (studs/s, 3D).
function CombatMath.speedOk(a: Vector3, b: Vector3, dt: number, maxSpeed: number): boolean
	if dt <= 0 then
		return true
	end
	return (b - a).Magnitude / dt <= maxSpeed
end

-- Rounded hit damage, at least 1.
function CombatMath.hitAmount(base: number, mult: number, crit: boolean, critMult: number): number
	local amount = base * mult * (if crit then critMult else 1)
	if amount ~= amount or amount == math.huge then
		return 1
	end
	return math.max(1, math.floor(amount + 0.5))
end

return CombatMath
