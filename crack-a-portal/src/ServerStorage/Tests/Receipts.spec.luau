--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Receipts = require(ServerScriptService.Server.Lib.Receipts)

return function(t)
	t.test("same receipt twice grants once", function()
		local profile = { receipts = {} }
		local grants = 0
		local function grant(): boolean
			grants += 1
			return true
		end
		t.eq(Receipts.apply(profile, "r1", 100, grant), "granted")
		t.eq(Receipts.apply(profile, "r1", 101, grant), "already")
		t.eq(grants, 1)
		t.ok(Receipts.has(profile, "r1"))
	end)

	t.test("a failed grant is not recorded", function()
		local profile = { receipts = {} }
		t.eq(Receipts.apply(profile, "r2", 100, function()
			return false
		end), "failed")
		t.ok(not Receipts.has(profile, "r2"))
		t.eq(Receipts.apply(profile, "r3", 100, function(): boolean
			error("boom")
		end), "failed")
		t.ok(not Receipts.has(profile, "r3"))
		-- the retry succeeds later
		t.eq(Receipts.apply(profile, "r2", 105, function()
			return true
		end), "granted")
	end)

	t.test("keeps the newest 100", function()
		local profile = { receipts = {} }
		for i = 1, 130 do
			Receipts.record(profile, `id{i}`, i)
		end
		local count = 0
		for _ in profile.receipts do
			count += 1
		end
		t.eq(count, 100)
		t.ok(not Receipts.has(profile, "id30"), "oldest dropped")
		t.ok(Receipts.has(profile, "id31"), "newest kept")
		t.ok(Receipts.has(profile, "id130"))
	end)
end
