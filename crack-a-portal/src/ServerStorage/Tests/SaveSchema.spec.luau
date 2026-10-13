--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local SaveSchema = require(ServerScriptService.Server.Lib.SaveSchema)

return function(t)
	t.test("defaults are fresh copies with the starter kit", function()
		local a, b = SaveSchema.default(), SaveSchema.default()
		t.ok(a ~= b and a.items ~= b.items and a.settings ~= b.settings, "no shared tables")
		a.items[1].level = 9
		t.eq(b.items[1].level, 1)
		t.eq(a.version, SaveSchema.VERSION)
		t.eq(b.items[1].id, "i1")
		t.eq(b.items[1].type, "Sword")
		t.eq(b.items[1].rarity, "Common")
		t.eq(b.equipped.Weapon, "i1")
		t.eq(b.keys["Ash|Common"], 1)
		t.eq(b.settings.music, 0.6)
		t.eq(b.settings.sfx, 0.8)
		t.eq(b.settings.shake, true)
		t.eq(b.settings.reducedMotion, false)
		t.eq(b.nextId, 2)
	end)

	t.test("garbage becomes the default", function()
		local fromNil, nilFuture = SaveSchema.migrate(nil)
		t.ok(not nilFuture)
		t.eq(fromNil.items[1].id, "i1")
		for _, junk in { 5, "text", true } :: { any } do
			local p, future = SaveSchema.migrate(junk)
			t.ok(not future)
			t.eq(p.version, SaveSchema.VERSION)
			t.eq(p.items[1].id, "i1")
		end
		local p = SaveSchema.migrate({ foo = 1 })
		t.eq(p.coins, 0)
		t.eq(p.equipped.Weapon, "i1")
		t.eq(p.tutorialDone, false)
	end)

	t.test("missing fields are filled from the default", function()
		local p = SaveSchema.migrate({ version = 1, coins = 50 })
		t.eq(p.coins, 50)
		t.eq(p.portalLevel, 1)
		t.ok(p.index.monsters ~= nil and p.index.gear ~= nil and p.index.claimed ~= nil)
		t.eq(p.stats.highestWave, 0)
		t.eq(p.settings.music, 0.6)
		t.eq(p.boardsSent.Pot, 0)
		t.ok(p.receipts ~= nil)
		local partial = SaveSchema.migrate({ version = 1, settings = { music = 0.2 } })
		t.eq(partial.settings.music, 0.2)
		t.eq(partial.settings.sfx, 0.8)
	end)

	t.test("numbers are clamped and made whole", function()
		local nan = 0 / 0
		t.eq(SaveSchema.migrate({ version = 1, coins = nan }).coins, 0)
		t.eq(SaveSchema.migrate({ version = 1, coins = -40 }).coins, 0)
		t.eq(SaveSchema.migrate({ version = 1, coins = math.huge }).coins, 0)
		t.eq(SaveSchema.migrate({ version = 1, coins = 12.7 }).coins, 12)
		t.eq(SaveSchema.migrate({ version = 1, portalLevel = 0 }).portalLevel, 1)
		local p = SaveSchema.migrate({ version = 1, settings = { music = 4, sfx = -1, shake = "yes" } })
		t.eq(p.settings.music, 1)
		t.eq(p.settings.sfx, 0)
		t.eq(p.settings.shake, true)
		local k = SaveSchema.migrate({ version = 1, keys = { ["Ash|Rare"] = 2.9, ["Ember|Common"] = -3, bad = 4 } })
		t.eq(k.keys["Ash|Rare"], 2)
		t.eq(k.keys["Ember|Common"], nil)
		t.eq(k.keys.bad, nil)
	end)

	t.test("malformed items are dropped and equips checked", function()
		local p = SaveSchema.migrate({
			version = 1,
			items = {
				{ id = "i4", kind = "Ash", type = "Axe", rarity = "Rare", level = 3 },
				{ id = "i5", kind = "Ash" },
				"junk",
				{ id = "i4", kind = "Ash", type = "Sword", rarity = "Common", level = 1 },
			},
			equipped = { Weapon = "i9", Armor = "i4" },
			nextId = 2,
		})
		t.eq(#p.items, 1)
		t.eq(p.equipped.Weapon, nil)
		t.eq(p.equipped.Armor, "i4")
		t.eq(p.nextId, 5, "nextId moves past existing ids")
	end)

	t.test("items are capped at 150", function()
		local items = {}
		for i = 1, 170 do
			table.insert(items, { id = `i{i}`, kind = "Ash", type = "Sword", rarity = "Common", level = 1 })
		end
		local p = SaveSchema.migrate({ version = 1, items = items })
		t.eq(#p.items, 150)
		t.eq(p.items[150].id, "i150")
	end)

	t.test("receipts keep the newest 100", function()
		local receipts = {}
		for i = 1, 120 do
			receipts[`r{i}`] = i
		end
		local p = SaveSchema.migrate({ version = 1, receipts = receipts })
		local count = 0
		for _ in p.receipts do
			count += 1
		end
		t.eq(count, 100)
		t.eq(p.receipts.r120, 120)
		t.eq(p.receipts.r1, nil)
	end)

	t.test("a grey-test table migrates from v0", function()
		local p = SaveSchema.migrate({
			coins = 320,
			keys = { ["Ash|Common"] = 3 },
			items = {
				{ id = "i1", kind = "Ash", type = "Sword", rarity = "Common", level = 1 },
				{ id = "i2", kind = "Ash", type = "Armor", rarity = "Rare", level = 2 },
			},
			equipped = { Weapon = "i1", Armor = "i2" },
			nextId = 3,
			hp = 80,
		})
		t.eq(p.version, 1)
		t.eq(p.coins, 320)
		t.eq(p.keys["Ash|Common"], 3)
		t.eq(#p.items, 2)
		t.eq(p.equipped.Armor, "i2")
		t.eq(p.nextId, 3)
		t.eq((p :: any).hp, nil, "session-only fields are not kept")
		t.eq(p.tutorialDone, true)
	end)

	t.test("a future version is kept and flagged, never downgraded", function()
		local data = { version = SaveSchema.VERSION + 1, coins = 999, newThing = true }
		local p, future = SaveSchema.migrate(data)
		t.ok(future, "flagged")
		t.eq((p :: any).newThing, true)
		t.eq(p.version, SaveSchema.VERSION + 1)
	end)

	t.test("sanitize keeps a pending loss only when well formed", function()
		local good = SaveSchema.migrate({
			version = 1,
			pendingLoss = { coins = 100, items = {}, tier = "small", kind = "Ash", at = 10 },
		})
		t.ok(good.pendingLoss ~= nil)
		local bad = SaveSchema.migrate({ version = 1, pendingLoss = { coins = 100 } })
		t.eq(bad.pendingLoss, nil)
	end)
end
