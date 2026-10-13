--!strict
-- Attacks: the pure helpers used by the monster AI and the attack shapes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(t)
	local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
	local Attacks =
		require(ServerScriptService:WaitForChild("Server"):WaitForChild("Lib"):WaitForChild("Attacks")) :: any

	t.test("warned attacks wind up for at least 0.4 s", function()
		for id, a in Config.Attacks do
			local w = Attacks.windupFor(a)
			t.ok(w > 0, `{id} has a wind-up`)
			if a.warn then
				t.ok(w >= 0.4, `{id} warned wind-up >= 0.4`)
			end
		end
		t.eq(Attacks.windupFor({ warn = true, windup = 0.1 } :: any), 0.4, "short warned wind-up raised")
	end)

	t.test("slams land on the monster when reach is close to the radius", function()
		t.ok(Attacks.slamAtSelf(Config.Attacks.StoneBruteSlam), "brute slams around itself")
		t.ok(Attacks.slamAtSelf(Config.Attacks.GlacierStomp), "troll stomps around itself")
		t.ok(not Attacks.slamAtSelf({ range = 30, radius = 6 } :: any), "long reach lands on the target")
	end)

	t.test("spreadDirs fans shots evenly around the aim", function()
		local dirs = Attacks.spreadDirs(Vector3.new(0, 0, -10), 3, 15)
		t.eq(#dirs, 3)
		t.near(dirs[2].X, 0, 1e-6, "middle shot straight")
		t.near(dirs[2].Z, -1, 1e-6, "middle shot straight")
		local angle = math.deg(math.acos(dirs[1]:Dot(dirs[2])))
		t.near(angle, 15, 1e-4, "15 degrees apart")
		t.near(dirs[1].X, -dirs[3].X, 1e-6, "symmetric")
		local one = Attacks.spreadDirs(Vector3.new(5, 3, 0), 1, 40)
		t.near(one[1].X, 1, 1e-6, "single shot follows the flat aim")
		t.eq(one[1].Y, 0, "flat")
	end)

	t.test("rain starts on the target and stays inside the spread", function()
		local center = Vector3.new(10, 2, -4)
		local points = Attacks.rainPoints(center, 12, 20, Random.new(5))
		t.eq(#points, 12)
		t.eq(points[1], center, "first circle on the target")
		for _, p in points do
			local d = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude
			t.ok(d <= 20 + 1e-6, "inside spread")
		end
	end)

	t.test("behindPoint is behind the facing direction", function()
		local p = Attacks.behindPoint(Vector3.new(0, 0, 0), Vector3.new(0, 0, -1), 3.5)
		t.near(p.Z, 3.5, 1e-6, "behind = opposite the look")
		t.near(p.X, 0, 1e-6)
	end)

	t.test("shield blocks only from the front arc", function()
		local origin = Vector3.new(0, 0, 0)
		local look = Vector3.new(0, 0, -1)
		t.ok(Attacks.blocks(origin, look, 120, Vector3.new(0, 0, -5)), "front blocked")
		t.ok(Attacks.blocks(origin, look, 120, Vector3.new(2, 0, -5)), "slightly off-centre blocked")
		t.ok(not Attacks.blocks(origin, look, 120, Vector3.new(5, 0, 0)), "side hits")
		t.ok(not Attacks.blocks(origin, look, 120, Vector3.new(0, 0, 5)), "back hits")
		t.ok(not Attacks.blocks(origin, look, 0, Vector3.new(0, 0, -5)), "no shield")
	end)

	t.test("summon room respects the cap", function()
		t.eq(Attacks.summonRoom(10, 19, 3), 3)
		t.eq(Attacks.summonRoom(17, 19, 3), 2)
		t.eq(Attacks.summonRoom(19, 19, 3), 0)
		t.eq(Attacks.summonRoom(25, 19, 3), 0, "never negative")
	end)

	t.test("normal monsters pick the shortest reach that fits", function()
		local ids = Config.Monsters.CinderHound.attacks
		local ready = {}
		t.eq((Attacks.chooseAttack(ids, ready, 0, 3, 1, false)), "CinderHoundBite", "close: bite")
		t.eq((Attacks.chooseAttack(ids, ready, 0, 15, 1, false)), "CinderHoundCharge", "far: charge")
		t.eq((Attacks.chooseAttack(ids, ready, 0, 40, 1, false)), nil, "too far: nothing")
		ready.CinderHoundBite = 5
		t.eq((Attacks.chooseAttack(ids, ready, 0, 3, 1, false)), "CinderHoundCharge", "bite cooling: charge")
	end)

	t.test("bosses rotate through their attacks", function()
		local ids = Config.Monsters.AshenGolem.attacks
		local ready = {}
		local first, nextIndex = Attacks.chooseAttack(ids, ready, 0, 5, 1, true)
		t.eq(first, ids[1])
		t.eq(nextIndex, 2)
		local second, after = Attacks.chooseAttack(ids, ready, 0, 5, nextIndex, true)
		t.eq(second, ids[2])
		t.eq(after, 3)
		-- out of slam reach: the rotation skips to an attack that reaches
		local far = Attacks.chooseAttack(ids, ready, 0, 40, 1, true)
		t.ok(far ~= nil and Config.Attacks[far].range >= 40, "a ranged attack")
	end)

	t.test("approach, circle and strafe points", function()
		local me = Vector3.new(0, 0, 0)
		local target = Vector3.new(0, 0, -20)
		local stop = Attacks.approachPoint(me, target, 4)
		t.near(stop.Z, -16, 1e-6, "stops 4 short")
		t.eq(Attacks.approachPoint(Vector3.new(0, 0, -17), target, 4), Vector3.new(0, 0, -17), "close: stays")
		local c = Attacks.circlePoint(target, 0, 9)
		t.near((c - target).Magnitude, 9, 1e-6, "on the circle")
		local s = Attacks.strafePoint(me, target, 12, 1, 4)
		local d = Vector3.new(s.X - target.X, 0, s.Z - target.Z).Magnitude
		t.near(d, math.sqrt(12 * 12 + 4 * 4), 1e-6, "keeps distance plus drift")
	end)
end
