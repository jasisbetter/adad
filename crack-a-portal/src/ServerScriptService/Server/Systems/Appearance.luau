--!strict
-- Appearance: the equipped weapon and armour shown on the character (everyone sees them),
-- the swing trail, the character attributes SwingType / WeaponKind / WeaponRarity, and the
-- title over the head. Models come from Assets (hand-made) or Templates (grey fallback).
-- Refreshes on CharacterAdded, CharacterAppearanceLoaded and PlayerData.equipChanged.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Logic = require(Shared.Logic)
local Templates = require(Shared.Templates)
local Types = require(Shared.Types)

local PlayerData = require(script.Parent.PlayerData)

type Item = Types.Item

local Appearance = {}

local WEAPON_MODEL = "GearWeapon"
local ARMOR_MODEL = "GearArmor"
local TRAIL_NAME = "SwingTrail"
local TITLE_GUI = "TitleTag"
local TITLE_MAX_LENGTH = 64

-- Hand parts: R15 first, then R6 (R6 arms carry the same grip attachment names).
local HAND_PARTS = {
	Right = { "RightHand", "Right Arm" },
	Left = { "LeftHand", "Left Arm" },
}

type PlayerState = {
	conns: { RBXScriptConnection },
	weaponSig: string?,
	armorSig: string?,
	character: Model?,
}

local states: { [Player]: PlayerState } = {}

---------------------------------------------------------------------------
-- model helpers
---------------------------------------------------------------------------

local function findAttachment(root: Instance, name: string): Attachment?
	for _, d in root:GetDescendants() do
		if d:IsA("Attachment") and d.Name == name then
			return d
		end
	end
	return nil
end

-- Makes every part cosmetic: unanchored, massless, no collisions, queries or touches.
-- Scripts inside hand-made assets are removed.
local function dress(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
end

-- Welds every part of `root` that is not already joined (through welds inside `root`) to
-- one of `anchors`, keeping its current offset. Must run before the model is moved.
local function weldLoose(root: Instance, anchors: { BasePart })
	if #anchors == 0 then
		return
	end
	local links: { [BasePart]: { BasePart } } = {}
	local function link(a: BasePart?, b: BasePart?)
		if a and b and a:IsDescendantOf(root) and b:IsDescendantOf(root) then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") then
			local joint = d :: any
			link(joint.Part0, joint.Part1)
		end
	end
	local reached: { [BasePart]: boolean } = {}
	local queue: { BasePart } = table.clone(anchors)
	for _, a in anchors do
		reached[a] = true
	end
	local head = 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		for _, other in links[part] or {} do
			if not reached[other] then
				reached[other] = true
				table.insert(queue, other)
			end
		end
	end
	local base = anchors[1]
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not reached[d] then
			local w = Instance.new("WeldConstraint")
			w.Part0 = base
			w.Part1 = d
			w.Parent = base
			reached[d] = true
		end
	end
end

-- First body part of the character from a list of names (R15 first, then R6).
local function bodyPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- A body attachment (direct child of a body part, never one inside an accessory).
local function bodyAttachment(character: Model, name: string): Attachment?
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			local a = child:FindFirstChild(name)
			if a and a:IsA("Attachment") then
				return a
			end
		end
	end
	return nil
end

-- Rigid weld so that `attachment` (on a gear part) sits exactly on `target` (on a body part).
local function weldTo(target: Attachment, attachment: Attachment)
	local part0 = target.Parent
	local part1 = attachment.Parent
	if not part0 or not part0:IsA("BasePart") or not part1 or not part1:IsA("BasePart") then
		return
	end
	local w = Instance.new("Weld")
	w.Name = "GearWeld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = target.CFrame
	w.C1 = attachment.CFrame
	w.Parent = part1
end

local function gearModel(item: Item): Model
	return Assets.gear(item.kind, item.type, item.rarity) or Templates.gear(item.kind, item.type, item.rarity)
end

---------------------------------------------------------------------------
-- trail
---------------------------------------------------------------------------

local function addTrail(blade: Instance, item: Item)
	local top = findAttachment(blade, "TrailTop")
	local bottom = findAttachment(blade, "TrailBottom")
	local host = top and top.Parent
	if not top or not bottom or not host then
		return
	end
	local kind = Config.KeyKinds[item.kind]
	local order = Logic.rarityOrder(item.rarity)
	local glow = if kind then kind.glow else Config.Colors.White
	-- brighter by rarity: towards white, more light emission, more opaque at the head
	local bright = glow:Lerp(Config.Colors.White, math.clamp((order - 1) * 0.08, 0, 0.35))
	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(bright, glow)
	trail.LightEmission = math.clamp(0.25 + order * 0.15, 0, 1)
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(math.clamp(0.6 - order * 0.08, 0.1, 0.9), 1)
	trail.Lifetime = 0.16 + order * 0.02
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.Enabled = false -- clients switch it on during swings
	trail.Parent = host
end

---------------------------------------------------------------------------
-- weapon and armour
---------------------------------------------------------------------------

local function clearModel(character: Model, name: string)
	local old = character:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

-- Welds one blade (or the whole weapon) by its "Grip" to a hand's grip attachment.
local function mountBlade(character: Model, blade: Instance, side: "Right" | "Left", item: Item): boolean
	local grip = findAttachment(blade, "Grip")
	local gripPart = grip and grip.Parent
	if not grip or not gripPart or not gripPart:IsA("BasePart") then
		return false
	end
	local hand = bodyPart(character, HAND_PARTS[side])
	if not hand then
		return false
	end
	local target = hand:FindFirstChild(`{side}GripAttachment`)
	if not target or not target:IsA("Attachment") then
		-- no grip attachment (custom rig): make one at the bottom of the hand
		local a = Instance.new("Attachment")
		a.Name = `{side}GripAttachment`
		a.CFrame = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		a.Parent = hand
		target = a
	end
	weldLoose(blade, { gripPart })
	addTrail(blade, item)
	weldTo(target :: Attachment, grip)
	return true
end

local function mountWeapon(character: Model, item: Item)
	local model = gearModel(item)
	model.Name = WEAPON_MODEL
	dress(model)
	local right = model:FindFirstChild("Right")
	local left = model:FindFirstChild("Left")
	local mounted = false
	if item.type == "TwinBlades" and right and left then
		mounted = mountBlade(character, right, "Right", item)
		mountBlade(character, left, "Left", item)
	else
		mounted = mountBlade(character, model, "Right", item)
	end
	if not mounted then
		model:Destroy()
		return
	end
	model:SetAttribute("ItemKey", Logic.itemKey(item))
	model.Parent = character
end

local function mountArmor(character: Model, item: Item)
	local model = gearModel(item)
	model.Name = ARMOR_MODEL
	dress(model)
	-- every piece that carries a body attachment name is welded on its own
	local pieces: { { part: BasePart, attachment: Attachment, target: Attachment } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") then
			local part = d.Parent
			local target = bodyAttachment(character, d.Name)
			if target and part and part:IsA("BasePart") then
				table.insert(pieces, { part = part, attachment = d, target = target })
			end
		end
	end
	if #pieces == 0 then
		model:Destroy()
		return
	end
	local anchors: { BasePart } = {}
	local used: { [BasePart]: boolean } = {}
	for _, piece in pieces do
		if not used[piece.part] then
			used[piece.part] = true
			table.insert(anchors, piece.part)
		end
	end
	weldLoose(model, anchors)
	local welded: { [BasePart]: boolean } = {}
	for _, piece in pieces do
		if not welded[piece.part] then
			welded[piece.part] = true
			weldTo(piece.target, piece.attachment)
		end
	end
	model:SetAttribute("ItemKey", Logic.itemKey(item))
	model.Parent = character
end

local function sig(item: Item?): string?
	return if item then Logic.itemKey(item) else nil
end

local function stateOf(player: Player): PlayerState
	local state = states[player]
	if not state then
		state = { conns = {}, weaponSig = nil, armorSig = nil, character = nil }
		states[player] = state
	end
	return state
end

local function doRefresh(player: Player, force: boolean)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local state = stateOf(player)
	if state.character ~= character then
		state.character = character
		force = true
	end
	local session = PlayerData.get(player)
	local weapon: Item? = nil
	local armor: Item? = nil
	if session then
		local eq = session.profile.equipped
		weapon = if eq.Weapon then PlayerData.findItem(player, eq.Weapon) else nil
		armor = if eq.Armor then PlayerData.findItem(player, eq.Armor) else nil
	end

	local weaponSig = sig(weapon)
	if force or weaponSig ~= state.weaponSig or (character:FindFirstChild(WEAPON_MODEL) ~= nil) ~= (weapon ~= nil) then
		clearModel(character, WEAPON_MODEL)
		if weapon then
			local ok, err = pcall(mountWeapon, character, weapon)
			if not ok then
				warn(`[Appearance] weapon for {player.Name}: {err}`)
			end
		end
		state.weaponSig = weaponSig
	end
	local armorSig = sig(armor)
	if force or armorSig ~= state.armorSig or (character:FindFirstChild(ARMOR_MODEL) ~= nil) ~= (armor ~= nil) then
		clearModel(character, ARMOR_MODEL)
		if armor then
			local ok, err = pcall(mountArmor, character, armor)
			if not ok then
				warn(`[Appearance] armour for {player.Name}: {err}`)
			end
		end
		state.armorSig = armorSig
	end

	local swingType = if weapon then weapon.type else "Fists"
	if character:GetAttribute("SwingType") ~= swingType then
		character:SetAttribute("SwingType", swingType)
	end
	local kind = if weapon then weapon.kind else nil
	if character:GetAttribute("WeaponKind") ~= kind then
		character:SetAttribute("WeaponKind", kind)
	end
	local rarity = if weapon then weapon.rarity else nil
	if character:GetAttribute("WeaponRarity") ~= rarity then
		character:SetAttribute("WeaponRarity", rarity)
	end
end

-- Welds the equipped weapon and armour on the character (no-op when nothing changed).
function Appearance.refresh(player: Player)
	doRefresh(player, false)
end

---------------------------------------------------------------------------
-- title
---------------------------------------------------------------------------

local function titleGui(character: Model, title: string?)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild(TITLE_GUI)
	if not title then
		if old then
			old:Destroy()
		end
		return
	end
	local gui: BillboardGui
	if old and old:IsA("BillboardGui") then
		gui = old
	else
		if old then
			old:Destroy()
		end
		gui = Instance.new("BillboardGui")
		gui.Name = TITLE_GUI
		gui.Size = UDim2.fromScale(6, 0.7) -- studs, so it shrinks with distance like the world
		gui.StudsOffset = Vector3.new(0, 2.4, 0)
		gui.MaxDistance = 60
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Adornee = head
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
		label.TextScaled = true
		label.TextColor3 = Config.Colors.GoldBright
		label.TextStrokeColor3 = Config.Colors.Ink
		label.TextStrokeTransparency = 0.35
		label.Parent = gui
		gui.Parent = head
	end
	local label = gui:FindFirstChild("Title")
	if label and label:IsA("TextLabel") and label.Text ~= title then
		label.Text = title
	end
end

-- Sets (or clears) the title: player attribute Title, the profile, and the tag over the head.
function Appearance.setTitle(player: Player, title: string?)
	local clean: string? = nil
	if type(title) == "string" and #title > 0 then
		clean = string.sub(title, 1, TITLE_MAX_LENGTH)
	end
	if player:GetAttribute("Title") ~= clean then
		player:SetAttribute("Title", clean)
	end
	local session = PlayerData.get(player)
	if session and session.profile.title ~= clean then
		session.profile.title = clean
		PlayerData.markDirty(player)
	end
	local character = player.Character
	if character then
		titleGui(character, clean)
	end
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	task.spawn(function()
		-- wait for the hands (and the head for the title)
		character:WaitForChild("Head", 10)
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if not hand then
			character:WaitForChild("RightHand", 5)
		end
		if player.Character ~= character then
			return
		end
		doRefresh(player, true)
		local title = player:GetAttribute("Title")
		titleGui(character, if type(title) == "string" then title else nil)
	end)
end

local function onPlayer(player: Player)
	local state = stateOf(player)
	table.insert(
		state.conns,
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	)
	-- the avatar's body parts can be replaced when its appearance loads: rebuild then
	table.insert(
		state.conns,
		player.CharacterAppearanceLoaded:Connect(function(character)
			if player.Character == character then
				doRefresh(player, true)
				local title = player:GetAttribute("Title")
				titleGui(character, if type(title) == "string" then title else nil)
			end
		end)
	)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

function Appearance.init()
	PlayerData.equipChanged:Connect(function(player: Player)
		if player.Parent == Players then
			Appearance.refresh(player)
		end
	end)
	PlayerData.onLoaded(function(player: Player)
		local session = PlayerData.get(player)
		Appearance.setTitle(player, session and session.profile.title)
		Appearance.refresh(player)
	end)
end

function Appearance.start()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		if state then
			for _, c in state.conns do
				c:Disconnect()
			end
			states[player] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

return Appearance
