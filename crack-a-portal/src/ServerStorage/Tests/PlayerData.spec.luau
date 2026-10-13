--!strict
-- PlayerData.cleanProfile: the Config-aware clean-up after loading.
local ServerScriptService = game:GetService("ServerScriptService")

return function(t)
	local Systems = ServerScriptService:WaitForChild("Server"):WaitForChild("Systems")
	local PlayerData = require(Systems:WaitForChild("PlayerData")) :: any
	local SaveSchema =
		require(ServerScriptService:WaitForChild("Server"):WaitForChild("Lib"):WaitForChild("SaveSchema"))

	t.test("cleanProfile drops unknown items and clamps levels", function()
		local p = SaveSchema.default()
		p.items = {
			{ id = "i1", kind = "Ash", type = "Sword", rarity = "Common", level = 50 },
			{ id = "i2", kind = "Lava", type = "Sword", rarity = "Common", level = 1 },
			{ id = "i3", kind = "Ash", type = "Spear", rarity = "Common", level = 1 },
			{ id = "i4", kind = "Ash", type = "Armor", rarity = "Shiny", level = 1 },
			{ id = "i5", kind = "Void", type = "Armor", rarity = "Mythic", level = 0 },
		}
		p.equipped = { Weapon = "i1", Armor = "i4" }
		PlayerData.cleanProfile(p)
		t.eq(#p.items, 2, "kept items")
		t.eq(p.items[1].level, 10, "Common max level")
		t.eq(p.items[2].level, 1, "level at least 1")
		t.eq(p.equipped.Weapon, "i1")
		t.eq(p.equipped.Armor, nil, "dropped item unequipped")
	end)

	t.test("cleanProfile fixes slots, keys, portal level and coins", function()
		local p = SaveSchema.default()
		p.items = {
			{ id = "i1", kind = "Ash", type = "Sword", rarity = "Common", level = 1 },
			{ id = "i2", kind = "Ash", type = "Armor", rarity = "Common", level = 1 },
		}
		p.equipped = { Weapon = "i2", Armor = "i1" }
		p.keys = { ["Ash|Common"] = 3, ["Lava|Common"] = 2, ["Ash|Mythic"] = 1 }
		p.portalLevel = 400
		p.coins = 1e20
		PlayerData.cleanProfile(p)
		t.eq(p.equipped.Weapon, nil, "armour in the weapon slot")
		t.eq(p.equipped.Armor, nil, "weapon in the armour slot")
		t.eq(p.keys["Ash|Common"], 3)
		t.eq(p.keys["Lava|Common"], nil)
		t.eq(p.keys["Ash|Mythic"], nil)
		t.eq(p.portalLevel, 20)
		t.eq(p.coins, 1e15)
	end)
end
