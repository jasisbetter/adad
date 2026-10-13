--!strict
-- Assets: finds a hand-made model by name and returns a clone, or nil (callers then use
-- Templates). Looks in ReplicatedStorage.Assets, and ServerStorage.Assets on the server.
-- Never yields and never errors when the folders are missing. Contract in ASSETS.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Assets = {}

local IS_SERVER = RunService:IsServer()
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn(`[Assets] {text}`)
	end
end

local function lookIn(container: Instance, category: string, name: string, sub: string?): Instance?
	local rootFolder = container:FindFirstChild("Assets")
	local folder = rootFolder and rootFolder:FindFirstChild(category)
	local found = folder and folder:FindFirstChild(name)
	if found and sub then
		found = found:FindFirstChild(sub)
	end
	return found
end

-- The original (not a clone), or nil.
function Assets.findSource(category: string, name: string, sub: string?): Instance?
	local ok, found = pcall(lookIn, ReplicatedStorage, category, name, sub)
	if ok and found then
		return found
	end
	if IS_SERVER then
		local ok2, found2 = pcall(lookIn, ServerStorage, category, name, sub)
		if ok2 and found2 then
			return found2
		end
	end
	return nil
end

-- A clone of Assets/<category>/<name>[/<sub>], or nil.
function Assets.find(category: string, name: string, sub: string?): Instance?
	local source = Assets.findSource(category, name, sub)
	if not source then
		return nil
	end
	local ok, copy = pcall(source.Clone, source)
	if not ok or copy == nil then
		warnOnce(source:GetFullName(), `{source:GetFullName()} could not be cloned (Archivable off?)`)
		return nil
	end
	return copy
end

local function asModel(inst: Instance?, label: string): Model?
	if inst == nil then
		return nil
	end
	if inst:IsA("Model") then
		return inst
	end
	warnOnce(label, `{label} is a {inst.ClassName}, expected a Model; using the grey template`)
	inst:Destroy()
	return nil
end

-- ServerStorage.Assets.Monsters.<id>: must have PrimaryPart "Root" and an Animator.
function Assets.monster(id: string): Model?
	local model = asModel(Assets.find("Monsters", id), `Monsters.{id}`)
	if not model then
		return nil
	end
	local root = model.PrimaryPart
	local host = model:FindFirstChildOfClass("AnimationController") or model:FindFirstChildOfClass("Humanoid")
	local animator = host and host:FindFirstChildOfClass("Animator")
	if not root or root.Name ~= "Root" or not animator then
		warnOnce(`Monsters.{id}`, `Monsters.{id} needs PrimaryPart "Root" and an Animator; using the grey template`)
		model:Destroy()
		return nil
	end
	return model
end

-- ReplicatedStorage.Assets.Gear.<kind>.<gearType>, or "<gearType>_<rarity>" first when a rarity is given.
function Assets.gear(kind: string, gearType: string, rarity: string?): Model?
	if rarity then
		local variant = asModel(Assets.find("Gear", kind, `{gearType}_{rarity}`), `Gear.{kind}.{gearType}_{rarity}`)
		if variant then
			return variant
		end
	end
	return asModel(Assets.find("Gear", kind, gearType), `Gear.{kind}.{gearType}`)
end

-- ReplicatedStorage.Assets.Portal.Tier<n>: must contain a part named "Surface".
function Assets.portalTier(n: number): Model?
	local label = `Portal.Tier{n}`
	local model = asModel(Assets.find("Portal", `Tier{n}`), label)
	if model and not model:FindFirstChild("Surface", true) then
		warnOnce(label, `{label} has no part named "Surface"; using the grey template`)
		model:Destroy()
		return nil
	end
	return model
end

local CHEST_NAMES: { [string]: string } = { normal = "Normal", big = "Big", boss = "Boss" }

-- ReplicatedStorage.Assets.Chests.<Normal|Big|Boss>; accepts "normal" or "Normal".
function Assets.chest(chestKind: string): Model?
	local name = CHEST_NAMES[chestKind] or chestKind
	return asModel(Assets.find("Chests", name), `Chests.{name}`)
end

-- ReplicatedStorage.Assets.Keys.<kind>
function Assets.key(kind: string): Model?
	return asModel(Assets.find("Keys", kind), `Keys.{kind}`)
end

return Assets
