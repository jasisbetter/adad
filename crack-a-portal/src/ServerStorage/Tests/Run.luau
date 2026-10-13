--!strict
-- Tiny test runner. In Studio (Edit or Play), from the command bar:
--   require(game.ServerStorage.Tests.Run)()            -- every spec
--   require(game.ServerStorage.Tests.Run)("Logic")     -- specs whose name contains "Logic"
-- Offline: `lune run tools/test.luau` runs the same specs (pure modules only).
-- A spec is a ModuleScript named "<Name>.spec" that returns function(t: T).

export type T = {
	test: (name: string, fn: () -> ()) -> (),
	ok: (condition: any, message: string?) -> (),
	eq: (actual: any, expected: any, message: string?) -> (),
	near: (actual: number, expected: number, tolerance: number, message: string?) -> (),
}

local function describe(value: any): string
	if typeof(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

return function(filter: string?): (number, number)
	local passed, failed = 0, 0
	local specs: { ModuleScript } = {}
	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
			if not filter or string.find(child.Name, filter, 1, true) then
				table.insert(specs, child)
			end
		end
	end
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)
	for _, spec in specs do
		local current = ""
		local t: T = {
			test = function() end,
			ok = function() end,
			eq = function() end,
			near = function() end,
		}
		local function fail(message: string)
			error({ testFailure = `{current}: {message}` }, 0)
		end
		t.ok = function(condition: any, message: string?)
			if not condition then
				fail(message or "expected a true value")
			end
		end
		t.eq = function(actual: any, expected: any, message: string?)
			if actual ~= expected then
				fail(`{message or "values differ"} (got {describe(actual)}, expected {describe(expected)})`)
			end
		end
		t.near = function(actual: number, expected: number, tolerance: number, message: string?)
			if math.abs(actual - expected) > tolerance then
				fail(`{message or "not close enough"} (got {actual}, expected {expected} ± {tolerance})`)
			end
		end
		t.test = function(name: string, fn: () -> ())
			current = `{spec.Name} > {name}`
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				local text = if typeof(err) == "table" and (err :: any).testFailure
					then (err :: any).testFailure
					else `{current}: {tostring(err)}`
				print("FAIL " .. text)
			end
		end
		local ok, body = pcall(require, spec)
		if not ok then
			failed += 1
			print(`FAIL {spec.Name} did not load: {body}`)
		elseif typeof(body) ~= "function" then
			failed += 1
			print(`FAIL {spec.Name} must return a function`)
		else
			local ran, err = pcall(body, t)
			if not ran then
				failed += 1
				print(`FAIL {spec.Name} stopped: {err}`)
			end
		end
	end
	print(`[Tests] {passed} passed, {failed} failed ({#specs} specs)`)
	return passed, failed
end
