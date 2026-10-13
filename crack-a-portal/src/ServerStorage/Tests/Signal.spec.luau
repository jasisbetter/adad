--!strict
-- Signal runs handlers with task.spawn; offline runs use Lune's task library.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Signal)

return function(t)
	local hasTask = typeof(task) == "table" and typeof(task.spawn) == "function"
	if not hasTask then
		t.test("task library missing: Signal specs skipped", function() end)
		return
	end

	t.test("handlers run in connect order with the arguments", function()
		local sig = Signal.new()
		local seen = {}
		sig:Connect(function(a, b)
			table.insert(seen, `1:{a}{b}`)
		end)
		sig:Connect(function(a, b)
			table.insert(seen, `2:{a}{b}`)
		end)
		sig:Fire("x", 7)
		t.eq(table.concat(seen, ","), "1:x7,2:x7")
	end)

	t.test("disconnect and once", function()
		local sig = Signal.new()
		local a, b = 0, 0
		local conn = sig:Connect(function()
			a += 1
		end)
		sig:Once(function()
			b += 1
		end)
		sig:Fire()
		conn:Disconnect()
		t.ok(not conn.Connected)
		sig:Fire()
		t.eq(a, 1)
		t.eq(b, 1)
	end)

	t.test("an erroring handler does not stop the others", function()
		local sig = Signal.new()
		local ran = false
		sig:Connect(function()
			error("expected test error")
		end)
		sig:Connect(function()
			ran = true
		end)
		sig:Fire()
		t.ok(ran)
	end)

	t.test("disconnecting during a fire is safe", function()
		local sig = Signal.new()
		local count = 0
		local second
		sig:Connect(function()
			count += 1
			second:Disconnect()
		end)
		second = sig:Connect(function()
			count += 10
		end)
		sig:Connect(function()
			count += 100
		end)
		sig:Fire()
		t.eq(count, 101)
	end)

	t.test("disconnect all", function()
		local sig = Signal.new()
		local n = 0
		local c1 = sig:Connect(function()
			n += 1
		end)
		sig:Connect(function()
			n += 1
		end)
		sig:DisconnectAll()
		sig:Fire()
		t.eq(n, 0)
		t.ok(not c1.Connected)
		c1:Disconnect() -- harmless
	end)

	t.test("wait resumes with the fired values", function()
		local sig = Signal.new()
		local got: number? = nil
		task.spawn(function()
			got = sig:Wait()
		end)
		sig:Fire(5)
		t.eq(got, 5)
	end)
end
