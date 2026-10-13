--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Geometry = require(ReplicatedStorage.Shared.Geometry)

return function(t)
	local O = Vector3.new(0, 0, 0)

	t.test("flat drops the height", function()
		local v = Geometry.flat(Vector3.new(3, 9, -4))
		t.eq(v.Y, 0)
		t.eq(v.X, 3)
		t.eq(v.Z, -4)
	end)

	t.test("circle ignores height and includes the edge", function()
		t.ok(Geometry.inCircle(O, 5, Vector3.new(3, 50, 4)), "edge point is inside")
		t.ok(not Geometry.inCircle(O, 5, Vector3.new(3.1, 0, 4)), "just outside")
	end)

	t.test("line covers length and width only ahead of the origin", function()
		local dir = Vector3.new(0, 5, -1) -- height is flattened away
		t.ok(Geometry.inLine(O, dir, 10, 4, Vector3.new(1.9, 0, -9)), "inside")
		t.ok(not Geometry.inLine(O, dir, 10, 4, Vector3.new(2.1, 0, -5)), "too wide")
		t.ok(not Geometry.inLine(O, dir, 10, 4, Vector3.new(0, 0, 1)), "behind")
		t.ok(not Geometry.inLine(O, dir, 10, 4, Vector3.new(0, 0, -10.5)), "too far")
		t.ok(not Geometry.inLine(O, Vector3.new(0, 1, 0), 10, 4, Vector3.new(0, 0, -1)), "no flat direction")
	end)

	t.test("cone uses the full opening angle", function()
		local dir = Vector3.new(0, 0, -1)
		t.ok(Geometry.inCone(O, dir, 10, 90, Vector3.new(4, 0, -5)), "within 45 degrees")
		t.ok(not Geometry.inCone(O, dir, 10, 90, Vector3.new(6, 0, -5)), "outside 45 degrees")
		t.ok(not Geometry.inCone(O, dir, 10, 90, Vector3.new(0, 0, -11)), "out of range")
		t.ok(Geometry.inCone(O, dir, 10, 360, Vector3.new(0, 0, 5)), "360 hits behind")
		t.ok(Geometry.inCone(O, dir, 10, 30, O), "standing on the origin")
	end)

	t.test("arena hits outside the safe spots only", function()
		local safe = { Vector3.new(10, 0, 0) }
		t.ok(Geometry.inArena(O, 30, Vector3.new(0, 0, 0), safe, 5), "open ground is hit")
		t.ok(not Geometry.inArena(O, 30, Vector3.new(12, 0, 0), safe, 5), "safe spot is safe")
		t.ok(not Geometry.inArena(O, 30, Vector3.new(40, 0, 0), safe, 5), "outside the arena")
	end)

	t.test("segment helpers clamp to the ends", function()
		local a, b = Vector3.new(0, 0, 0), Vector3.new(10, 0, 0)
		t.near(Geometry.distanceToSegment(a, b, Vector3.new(5, 0, 3)), 3, 1e-9)
		t.near(Geometry.distanceToSegment(a, b, Vector3.new(13, 0, 4)), 5, 1e-9)
		t.eq(Geometry.pointOnSegment(a, b, Vector3.new(-5, 0, 2)).X, 0)
		t.eq(Geometry.segmentT(a, a, Vector3.new(1, 0, 1)), 0)
	end)

	t.test("safe spots stay inside the arena and apart", function()
		local center = Vector3.new(100, 2, -50)
		for seed = 1, 20 do
			local spots = Geometry.safeSpots(center, 34, 3, 7, Random.new(seed))
			t.eq(#spots, 3)
			for i, s in spots do
				t.eq(s.Y, center.Y, "spot keeps the arena height")
				t.ok(Geometry.flatDistance(s, center) + 7 <= 34 + 1e-6, "safe circle inside the arena")
				for j = i + 1, #spots do
					t.ok(Geometry.flatDistance(s, spots[j]) > 14, "safe circles do not overlap")
				end
			end
		end
		t.eq(#Geometry.safeSpots(center, 34, 0, 7, Random.new(1)), 0)
	end)

	t.test("ring points are evenly spaced on the radius", function()
		local pts = Geometry.ringPoints(O, 10, 4)
		t.eq(#pts, 4)
		for _, p in pts do
			t.near(Geometry.flatDistance(p, O), 10, 1e-9)
		end
		t.near(Geometry.flatDistance(pts[1], pts[2]), math.sqrt(200), 1e-9)
	end)

	t.test("random points stay in the circle", function()
		local rng = Random.new(7)
		for _ = 1, 200 do
			t.ok(Geometry.inCircle(O, 6, Geometry.randomInCircle(O, 6, rng)))
		end
	end)
end
