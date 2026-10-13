--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Config = require(ReplicatedStorage.Shared.Config)

return function(t)
	local O = Vector3.new(0, 0, 0)
	local FWD = Vector3.new(0, 0, -1)
	local sword = Config.GearTypes.Sword
	local combo = sword.combo :: { any }
	local reset = sword.comboReset :: number
	local grace = Config.Combat.comboGrace

	t.test("step time is windup + contact + recover", function()
		t.near(CombatMath.stepTime(combo[1]), 0.45, 1e-9)
	end)

	t.test("first swing is step 1", function()
		t.eq(CombatMath.nextStep(0, 0, 999, 3, reset, grace), 1)
	end)

	t.test("too early is ignored (no queueing)", function()
		local st = CombatMath.stepTime(combo[1])
		t.eq(CombatMath.nextStep(1, st, 0.2, 3, reset, grace), nil)
		t.eq(CombatMath.nextStep(1, st, st - CombatMath.LATENCY - 0.01, 3, reset, grace), nil)
	end)

	t.test("in the window the combo advances, with a small latency allowance", function()
		local st = CombatMath.stepTime(combo[1])
		t.eq(CombatMath.nextStep(1, st, st - CombatMath.LATENCY + 0.01, 3, reset, grace), 2)
		t.eq(CombatMath.nextStep(2, st, reset + grace - 0.01, 3, reset, grace), 3)
	end)

	t.test("after the reset time or the finisher the combo restarts", function()
		local st = CombatMath.stepTime(combo[1])
		t.eq(CombatMath.nextStep(2, st, reset + grace + 0.01, 3, reset, grace), 1)
		t.eq(CombatMath.nextStep(3, CombatMath.stepTime(combo[3]), 0.7, 3, reset, grace), 1)
	end)

	t.test("every weapon can chain its whole combo", function()
		for id, gear in Config.GearTypes do
			if gear.combo then
				local steps = gear.combo :: { any }
				for i = 1, #steps - 1 do
					local st = CombatMath.stepTime(steps[i])
					local r = gear.comboReset :: number
					t.ok(st - CombatMath.LATENCY < r + grace, `{id} step {i} window is open`)
					t.eq(CombatMath.nextStep(i, st, st, #steps, r, grace), i + 1, `{id} step {i}`)
				end
			end
		end
	end)

	t.test("swing arc and range count the target's body", function()
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(0, 0, -8), 0, 8, 110), "edge of range")
		t.ok(not CombatMath.inSwing(O, FWD, Vector3.new(0, 0, -8.5), 0, 8, 110), "past range")
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(0, 0, -9.5), 2, 8, 110), "big body reaches")
		t.ok(not CombatMath.inSwing(O, FWD, Vector3.new(0, 0, 5), 0.5, 8, 110), "behind")
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(4, 0, -4), 0, 8, 110), "45 degrees inside a 110 arc")
		t.ok(not CombatMath.inSwing(O, FWD, Vector3.new(6, 0, -2), 0, 8, 110), "70 degrees outside a 110 arc")
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(0.3, 0, 0.3), 1, 8, 110), "standing inside the target")
	end)

	t.test("finisher radius hits all around", function()
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(0, 0, 8), 0, 8.5, 140, 9), "behind within radius")
		t.ok(not CombatMath.inSwing(O, FWD, Vector3.new(0, 0, 10), 0, 8.5, 140, 9), "behind past radius")
	end)

	t.test("swing ignores far heights, allows hovering flyers", function()
		t.ok(CombatMath.inSwing(O, FWD, Vector3.new(0, 6, -4), 1, 8, 110, nil, 2), "low flyer")
		t.ok(not CombatMath.inSwing(O, FWD, Vector3.new(0, 40, -4), 1, 8, 110, nil, 2), "island above")
	end)

	t.test("face direction and nearest", function()
		local d = CombatMath.faceDirection(O, FWD, Vector3.new(5, 3, 0))
		t.near(d.X, 1, 1e-6)
		t.near(d.Y, 0, 1e-6)
		local f = CombatMath.faceDirection(O, Vector3.new(0, 1, 0), nil)
		t.near(f.Z, -1, 1e-6, "no flat look falls back to -Z")
		local pts = { Vector3.new(0, 0, -10), Vector3.new(3, 0, 0), Vector3.new(30, 0, 0) }
		t.eq(CombatMath.nearest(O, pts, { 0, 0, 0 }, 14), 2)
		t.eq(CombatMath.nearest(O, pts, { 8, 0, 0 }, 14), 1, "body radius counts")
		t.eq(CombatMath.nearest(O, { Vector3.new(30, 0, 0) }, { 0 }, 14), nil)
	end)

	t.test("speed check and hit amounts", function()
		t.ok(CombatMath.speedOk(O, Vector3.new(0, 0, 30), 0.25, 160), "120 studs/s ok")
		t.ok(not CombatMath.speedOk(O, Vector3.new(0, 0, 50), 0.25, 160), "200 studs/s flagged")
		t.eq(CombatMath.hitAmount(10, 1.6, false, 2), 16)
		t.eq(CombatMath.hitAmount(10, 1.6, true, 2), 32)
		t.eq(CombatMath.hitAmount(0.1, 1, false, 2), 1, "at least 1")
	end)
end
