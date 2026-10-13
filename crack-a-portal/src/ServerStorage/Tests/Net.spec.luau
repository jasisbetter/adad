--!strict
-- Net: every client -> server remote has a rate limit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

return function(t)
	t.test("every ToServer remote has a Limits row", function()
		for _, name in Net.ToServer do
			local row = Net.Limits[name]
			t.ok(row, `{name} has a limit`)
			t.ok(row.rate > 0 and row.burst >= 1, `{name} limit is positive`)
			t.eq(row[1], row.rate, `{name} [1]`)
			t.eq(row[2], row.burst, `{name} [2]`)
		end
		t.ok(Net.Limits.Debug, "Debug has a limit")
	end)

	t.test("remote names are unique and FxU is unreliable only", function()
		local seen = {}
		for _, list in { Net.ToServer, Net.ToClient, Net.Unreliable } do
			for _, name in list do
				t.ok(not seen[name], `{name} listed once`)
				seen[name] = true
			end
		end
		t.eq(Net.Unreliable[1], "FxU")
	end)
end
