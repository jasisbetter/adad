--!nocheck
-- Offline harness: runs the game's pure modules under Lune (https://lune-org.github.io),
-- outside Roblox. It builds a fake instance tree from default.project.json so that
-- `script.Parent.Config`, `game:GetService("ReplicatedStorage").Shared.Logic` and
-- `require(...)` work exactly as they do in Studio, and adds the few Roblox globals
-- that pure modules use (Random, TweenInfo, Vector3, Color3, CFrame, Enum...).
-- Only pure modules can run here: anything that needs a real service errors loudly.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local taskLib = require("@lune/task")

local Harness = {}

local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
-- tools are run from the crack-a-portal folder
local PROJECT = serde.decode("json", fs.readFile(ROOT .. "default.project.json"))

---------------------------------------------------------------------------
-- Random shim (deterministic; same API as Roblox's Random)
---------------------------------------------------------------------------
local RandomShim = {}
RandomShim.__index = RandomShim
RandomShim.__type = "Random"

local seedCounter = 0
local function mix(seed: number): number
	-- 31-bit LCG state
	return (seed * 1103515245 + 12345) % 2147483648
end

function RandomShim.new(seed: number?)
	if seed == nil then
		seedCounter += 1
		seed = os.time() + seedCounter * 7919
	end
	local s = math.floor(math.abs(seed :: number)) % 2147483648
	local self = setmetatable({ state = mix(s + 1) }, RandomShim)
	return self
end

function RandomShim:_next(): number
	self.state = mix(self.state)
	-- second round to decorrelate low bits
	local a = self.state
	self.state = mix(self.state)
	return ((a * 65536) + self.state) % 2147483648 / 2147483648
end

function RandomShim:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min == nil then
		return r
	end
	return (min :: number) + r * ((max :: number) - (min :: number))
end

function RandomShim:NextInteger(min: number, max: number): number
	if max < min then
		error("NextInteger: max < min", 2)
	end
	return min + math.floor(self:_next() * (max - min + 1))
end

function RandomShim:Clone()
	return setmetatable({ state = self.state }, RandomShim)
end

local TweenInfoShim = {}
function TweenInfoShim.new(time, style, direction, repeatCount, reverses, delayTime)
	return {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

---------------------------------------------------------------------------
-- Fake instance tree
---------------------------------------------------------------------------
type Node = {
	Name: string,
	ClassName: string,
	Parent: any,
	_dir: string?, -- folder on disk (for folders and init modules)
	_file: string?, -- file on disk (for modules)
	_children: { [string]: any }?,
	_attrs: { [string]: any },
}

local NodeMeta = {}
local nodePath: { [any]: string } = {}

local function isDir(path: string): boolean
	return fs.isDir(path)
end

local function classForFile(name: string): string
	if string.match(name, "%.server%.luau$") then
		return "Script"
	elseif string.match(name, "%.client%.luau$") then
		return "LocalScript"
	end
	return "ModuleScript"
end

local function newNode(name: string, className: string, parent: any, dir: string?, file: string?)
	local node = setmetatable({
		Name = name,
		ClassName = className,
		Parent = parent,
		_dir = dir,
		_file = file,
		_children = nil,
		_attrs = {},
	}, NodeMeta)
	return node
end

local function loadChildren(node)
	local existing = rawget(node, "_children")
	if existing then
		return existing
	end
	local kids = {}
	rawset(node, "_children", kids)
	local dir = rawget(node, "_dir")
	if dir and isDir(dir) then
		for _, entry in fs.readDir(dir) do
			local full = dir .. "/" .. entry
			if isDir(full) then
				local initFile = nil
				for _, candidate in { "init.luau", "init.server.luau", "init.client.luau" } do
					if fs.isFile(full .. "/" .. candidate) then
						initFile = full .. "/" .. candidate
						break
					end
				end
				local cls = if initFile then classForFile(initFile) else "Folder"
				kids[entry] = newNode(entry, cls, node, full, initFile)
			elseif string.match(entry, "%.luau$") and not string.match(entry, "^init[%.%a]*%.luau$") then
				local name = string.gsub(entry, "%.server%.luau$", "")
				name = string.gsub(name, "%.client%.luau$", "")
				name = string.gsub(name, "%.luau$", "")
				kids[name] = newNode(name, classForFile(entry), node, nil, full)
			end
		end
	end
	return kids
end

local NodeMethods = {}

function NodeMethods.FindFirstChild(self, name: string)
	return loadChildren(self)[name]
end

function NodeMethods.WaitForChild(self, name: string)
	local child = loadChildren(self)[name]
	if not child then
		error(`[harness] {self:GetFullName()} has no child {name} (only real services exist in Studio)`, 2)
	end
	return child
end

function NodeMethods.GetChildren(self)
	local list = {}
	for _, child in loadChildren(self) do
		table.insert(list, child)
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

function NodeMethods.IsA(self, className: string): boolean
	if className == "Instance" then
		return true
	end
	if className == "LuaSourceContainer" then
		local c = rawget(self, "ClassName")
		return c == "ModuleScript" or c == "Script" or c == "LocalScript"
	end
	if className == "BaseScript" then
		local c = rawget(self, "ClassName")
		return c == "Script" or c == "LocalScript"
	end
	return rawget(self, "ClassName") == className
end

function NodeMethods.GetFullName(self): string
	local parts = {}
	local n = self
	while n and rawget(n, "Name") ~= "game" do
		table.insert(parts, 1, rawget(n, "Name"))
		n = rawget(n, "Parent")
	end
	return table.concat(parts, ".")
end

function NodeMethods.GetAttribute(self, name: string)
	return rawget(self, "_attrs")[name]
end

function NodeMethods.SetAttribute(self, name: string, value: any)
	rawget(self, "_attrs")[name] = value
end

function NodeMethods.Clone(self)
	return self
end

NodeMeta.__index = function(self, key)
	local method = NodeMethods[key]
	if method then
		return method
	end
	local child = loadChildren(self)[key]
	if child then
		return child
	end
	error(`[harness] {key} is not a valid member of {rawget(self, "Name")}`, 2)
end
NodeMeta.__tostring = function(self)
	return rawget(self, "Name")
end
NodeMeta.__type = "Instance"

-- Stub services: pure modules may ask about the run context but nothing else.
local function stubService(name: string)
	local stub = {
		Name = name,
		ClassName = name,
		IsStudio = function()
			return true
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsRunning = function()
			return false
		end,
	}
	return setmetatable(stub, {
		__index = function(_, key)
			error(`[harness] {name}.{key} is not available offline (pure modules only)`, 2)
		end,
	})
end

local game = newNode("game", "DataModel", nil, nil, nil)
local services: { [string]: any } = {}

local function mapTree(node, spec, diskBase: string)
	for key, value in spec do
		if string.sub(key, 1, 1) ~= "$" and typeof(value) == "table" then
			local child
			if value["$path"] then
				local path = ROOT .. value["$path"]
				local initFile = nil
				for _, candidate in { "init.luau", "init.server.luau", "init.client.luau" } do
					if fs.isFile(path .. "/" .. candidate) then
						initFile = path .. "/" .. candidate
						break
					end
				end
				local cls = if initFile then classForFile(initFile) else "Folder"
				child = newNode(key, cls, node, path, initFile)
			else
				child = newNode(key, value["$className"] or "Folder", node, nil, nil)
				rawset(child, "_children", {})
			end
			loadChildren(node)[key] = child
			mapTree(child, value, diskBase)
		end
	end
end

rawset(game, "_children", {})
mapTree(game, PROJECT.tree, ROOT)

-- Load the whole tree now: file calls can't run inside the __index metamethod.
local function preload(node)
	for _, child in loadChildren(node) do
		preload(child)
	end
end
preload(game)

local function getService(_, name: string)
	local mapped = rawget(game, "_children")[name]
	if mapped then
		return mapped
	end
	if not services[name] then
		services[name] = stubService(name)
	end
	return services[name]
end
rawset(game, "GetService", getService)

---------------------------------------------------------------------------
-- require
---------------------------------------------------------------------------
local cache: { [any]: any } = {}
local loading: { [any]: boolean } = {}
local requireModule

local function makeEnv(scriptNode)
	local env = {
		script = scriptNode,
		game = game,
		workspace = stubService("Workspace"),
		require = function(target)
			return requireModule(target)
		end,
		Random = RandomShim,
		TweenInfo = TweenInfoShim,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		Rect = roblox.Rect,
		Font = roblox.Font,
		task = taskLib,
		print = print,
		warn = function(...)
			stdio.ewrite("[warn] " .. table.concat(table.pack(...) :: any, " ") .. "\n")
		end,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		select = select,
		type = type,
		typeof = typeof,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		unpack = table.unpack,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		math = math,
		string = string,
		table = table,
		os = os,
		utf8 = utf8,
		bit32 = bit32,
		buffer = buffer,
		coroutine = coroutine,
		debug = debug,
		tick = os.clock,
		time = os.clock,
		_HARNESS = true,
	}
	return env
end

requireModule = function(target)
	if typeof(target) ~= "Instance" and getmetatable(target) ~= NodeMeta then
		error("[harness] require() expects a module instance", 2)
	end
	if cache[target] ~= nil then
		return cache[target]
	end
	local file = rawget(target, "_file")
	if not file then
		error(`[harness] {target:GetFullName()} is not a module`, 2)
	end
	if loading[target] then
		error(`[harness] cyclic require of {target:GetFullName()}`, 2)
	end
	loading[target] = true
	local source = fs.readFile(file)
	local chunk = luau.load(source, { debugName = target:GetFullName(), environment = makeEnv(target) })
	local result = chunk()
	loading[target] = nil
	cache[target] = result
	return result
end

Harness.game = game
Harness.require = requireModule
Harness.Random = RandomShim
Harness.ROOT = ROOT

-- Compiles every .luau file under src/ (syntax check, all contexts).
function Harness.compileAll(): (number, { string })
	local errors = {}
	local count = 0
	local function walk(dir: string)
		for _, entry in fs.readDir(dir) do
			local full = dir .. "/" .. entry
			if fs.isDir(full) then
				walk(full)
			elseif string.match(entry, "%.luau$") then
				count += 1
				local ok, err = pcall(luau.compile, fs.readFile(full))
				if not ok then
					table.insert(errors, `{string.sub(full, #ROOT + 1)}: {err}`)
				end
			end
		end
	end
	walk(ROOT .. "src")
	return count, errors
end

return Harness
