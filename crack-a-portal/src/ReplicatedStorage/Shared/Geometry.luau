--!strict
-- Geometry: pure shape tests on the ground plane (Y is ignored). The server resolves attacks
-- with these and the client draws warning zones with the same numbers. No instances.

local Geometry = {}

local EPSILON = 1e-6

-- The vector with its height removed.
function Geometry.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Flat distance between two points.
function Geometry.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Flattened unit direction, or nil when it has no length on the ground.
function Geometry.flatUnit(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	local m = f.Magnitude
	if m < EPSILON or m ~= m then
		return nil
	end
	return f / m
end

function Geometry.inCircle(center: Vector3, radius: number, p: Vector3): boolean
	local dx, dz = p.X - center.X, p.Z - center.Z
	return dx * dx + dz * dz <= radius * radius
end

-- 0..1 position of p's projection along a -> b (flat), clamped.
function Geometry.segmentT(a: Vector3, b: Vector3, p: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	if len2 < EPSILON then
		return 0
	end
	local t = ((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2
	return math.clamp(t, 0, 1)
end

-- Closest point on the flat segment a -> b to p (Y taken from a).
function Geometry.pointOnSegment(a: Vector3, b: Vector3, p: Vector3): Vector3
	local t = Geometry.segmentT(a, b, p)
	return Vector3.new(a.X + (b.X - a.X) * t, a.Y, a.Z + (b.Z - a.Z) * t)
end

-- Flat distance from p to the segment a -> b.
function Geometry.distanceToSegment(a: Vector3, b: Vector3, p: Vector3): number
	return Geometry.flatDistance(Geometry.pointOnSegment(a, b, p), p)
end

-- A rectangle starting at origin, `length` long along dir (flattened) and `width` wide.
function Geometry.inLine(origin: Vector3, dir: Vector3, length: number, width: number, p: Vector3): boolean
	local d = Geometry.flatUnit(dir)
	if not d then
		return false
	end
	local rx, rz = p.X - origin.X, p.Z - origin.Z
	local along = rx * d.X + rz * d.Z
	if along < 0 or along > length then
		return false
	end
	local px, pz = rx - d.X * along, rz - d.Z * along
	local half = width / 2
	return px * px + pz * pz <= half * half
end

-- A cone of `range` studs; angleDegrees is the full opening (90 = 45 each side of dir).
function Geometry.inCone(origin: Vector3, dir: Vector3, range: number, angleDegrees: number, p: Vector3): boolean
	local d = Geometry.flatUnit(dir)
	if not d then
		return false
	end
	local rx, rz = p.X - origin.X, p.Z - origin.Z
	local dist2 = rx * rx + rz * rz
	if dist2 > range * range then
		return false
	end
	if dist2 < EPSILON then
		return true
	end
	if angleDegrees >= 360 then
		return true
	end
	local dist = math.sqrt(dist2)
	local cosAngle = (rx * d.X + rz * d.Z) / dist
	return cosAngle >= math.cos(math.rad(angleDegrees / 2))
end

-- Full-arena slam: true = gets hit (inside the arena and outside every safe spot).
function Geometry.inArena(
	center: Vector3,
	radius: number,
	p: Vector3,
	safeSpots: { Vector3 },
	safeRadius: number
): boolean
	if not Geometry.inCircle(center, radius, p) then
		return false
	end
	for _, spot in safeSpots do
		if Geometry.inCircle(spot, safeRadius, p) then
			return false
		end
	end
	return true
end

-- Spread-out safe circle centres inside the arena: even angles with a random turn,
-- each at a random distance that keeps the whole safe circle inside the arena.
function Geometry.safeSpots(
	center: Vector3,
	radius: number,
	count: number,
	safeRadius: number,
	rng: Random
): { Vector3 }
	local spots: { Vector3 } = {}
	local n = math.max(0, math.floor(count))
	if n == 0 then
		return spots
	end
	local maxDist = math.max(0, radius - safeRadius - 1)
	local minDist = math.min(maxDist, math.max(safeRadius * 1.2, radius * 0.35))
	local turn = rng:NextNumber() * math.pi * 2
	local step = math.pi * 2 / n
	local jitter = step * 0.25
	for i = 1, n do
		local angle = turn + (i - 1) * step + (rng:NextNumber() * 2 - 1) * jitter
		local dist = minDist + rng:NextNumber() * (maxDist - minDist)
		table.insert(spots, Vector3.new(center.X + math.sin(angle) * dist, center.Y, center.Z + math.cos(angle) * dist))
	end
	return spots
end

-- n points evenly spaced on a circle (first point at angle `offset` radians, towards +Z at 0).
function Geometry.ringPoints(center: Vector3, radius: number, n: number, offset: number?): { Vector3 }
	local points: { Vector3 } = {}
	local count = math.max(0, math.floor(n))
	local start = offset or 0
	for i = 1, count do
		local angle = start + (i - 1) / count * math.pi * 2
		local x, z = center.X + math.sin(angle) * radius, center.Z + math.cos(angle) * radius
		table.insert(points, Vector3.new(x, center.Y, z))
	end
	return points
end

-- A uniformly random point inside a circle (icicle rain, ember spots).
function Geometry.randomInCircle(center: Vector3, radius: number, rng: Random): Vector3
	local angle = rng:NextNumber() * math.pi * 2
	local dist = math.sqrt(rng:NextNumber()) * radius
	return Vector3.new(center.X + math.sin(angle) * dist, center.Y, center.Z + math.cos(angle) * dist)
end

return Geometry
