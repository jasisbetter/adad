--!strict
return function(t)
	t.test("random is deterministic with a seed", function()
		local a, b = Random.new(42), Random.new(42)
		for _ = 1, 20 do
			t.eq(a:NextInteger(1, 100), b:NextInteger(1, 100))
		end
	end)
end
