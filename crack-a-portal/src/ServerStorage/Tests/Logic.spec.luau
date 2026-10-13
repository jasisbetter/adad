--!strict
-- Logic: the pure rules (falls, merges, costs, portal, waves, bosses, chests, keys, quests).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Logic = require(ReplicatedStorage.Shared.Logic)

type Item = Logic.Item

local function item(id: string, kind: string, typeId: string, rarity: string, level: number): Item
	return { id = id, kind = kind, type = typeId, rarity = rarity, level = level }
end

return function(t)
	t.test("oddsPercent sums to exactly 100 for every odds table", function()
		local tables = {}
		for _, odds in Config.GearOdds do
			table.insert(tables, odds)
		end
		for _, odds in Config.MapKeyOdds do
			table.insert(tables, odds)
		end
		table.insert(tables, { { "a", 1 }, { "b", 1 }, { "c", 1 } })
		table.insert(tables, { { "a", 2 }, { "b", 7 }, { "c", 11 }, { "d", 13 } })
		table.insert(tables, Logic.boostedOdds(Config.GearOdds.RareKey, 3, Config.Gear.chestOddsStep))
		for _, odds in tables do
			local hundredths = 0
			for _, row in Logic.oddsPercent(odds) do
				local h = row.percent * 100
				t.near(h, math.floor(h + 0.5), 1e-6, "2 decimals at most")
				hundredths += math.floor(h + 0.5)
			end
			t.eq(hundredths, 10000, "sums to exactly 100")
		end
		local thirds = Logic.oddsPercent({ { "a", 1 }, { "b", 1 }, { "c", 1 } })
		t.near(thirds[1].percent + thirds[2].percent + thirds[3].percent, 100, 1e-9)
		local exact = Logic.oddsPercent(Config.MapKeyOdds.MapInner)
		t.eq(exact[1].id, "Common")
		t.near(exact[1].percent, 85, 1e-9)
		t.near(exact[3].percent, 1, 1e-9)
	end)

	t.test("keptCoins keeps exactly half, rounded up", function()
		t.eq(Logic.keptCoins(0), 0)
		t.eq(Logic.keptCoins(10), 5)
		t.eq(Logic.keptCoins(11), 6)
		t.eq(Logic.keptCoins(1), 1)
	end)

	t.test("randomHalf keeps exactly ceil(n/2) distinct indexes over many seeds", function()
		for seed = 1, 200 do
			local rng = Random.new(seed)
			local n = seed % 13
			local kept = Logic.randomHalf(n, rng)
			local count = 0
			for index in kept do
				t.ok(index >= 1 and index <= n, "index in range")
				count += 1
			end
			t.eq(count, math.ceil(n / 2), `n = {n}`)
		end
	end)

	t.test("merge needs 3 identical, never Mythic, picks lowest levels, keeps the pick", function()
		local pick = item("i9", "Ash", "Sword", "Rare", 7)
		local items = {
			pick,
			item("i2", "Ash", "Sword", "Rare", 5),
			item("i3", "Ash", "Sword", "Rare", 1),
			item("i4", "Ash", "Sword", "Rare", 3),
			item("i5", "Ash", "Axe", "Rare", 1), -- other type
			item("i6", "Ember", "Sword", "Rare", 1), -- other kind
			item("i7", "Ash", "Sword", "Epic", 1), -- other rarity
		}
		local group = Logic.mergeGroup(items, pick, {})
		t.ok(group, "a group")
		local g = group :: { string }
		t.eq(#g, 3)
		t.eq(g[1], "i9", "the pick is kept")
		t.eq(g[2], "i3", "lowest level first")
		t.eq(g[3], "i4")
		-- an equipped item is never used as fodder
		local g2 = Logic.mergeGroup(items, pick, { Weapon = "i3" }) :: { string }
		t.eq(g2[2], "i4")
		t.eq(g2[3], "i2")
		-- not enough
		t.eq(Logic.mergeGroup({ pick, items[2] }, pick, {}), nil)
		-- Mythic never merges
		local m = item("m1", "Ash", "Sword", "Mythic", 1)
		local mythics = { m, item("m2", "Ash", "Sword", "Mythic", 1), item("m3", "Ash", "Sword", "Mythic", 1) }
		t.eq(Logic.mergeGroup(mythics, m, {}), nil)
		t.eq(Logic.nextRarity("Mythic"), nil)
		t.eq(Logic.nextRarity("Common"), "Rare")
		t.eq(Logic.itemKey(pick), "Ash|Sword|Rare")
	end)

	t.test("sell values for each rarity and kind", function()
		local sells = { Common = 10, Rare = 50, Epic = 250, Legendary = 1250, Mythic = 6250 }
		for _, kindId in Config.KindOrder do
			local mult = Config.KeyKinds[kindId].coinMult
			for rarity, value in sells do
				t.eq(Logic.sellValue(item("x", kindId, "Sword", rarity, 1)), value * mult, `{kindId} {rarity}`)
			end
		end
	end)

	t.test("upgrade costs for each rarity and kind, nil at max level", function()
		local bases = { Common = 20, Rare = 60, Epic = 200, Legendary = 700, Mythic = 2500 }
		for _, kindId in Config.KindOrder do
			local mult = Config.KeyKinds[kindId].coinMult
			for rarity, base in bases do
				for _, level in { 1, 2, 5 } do
					local cost = Logic.upgradeCost(item("x", kindId, "Axe", rarity, level))
					t.eq(cost, math.floor(base * 1.2 ^ level * mult + 0.5), `{kindId} {rarity} L{level}`)
				end
				local max = Logic.maxLevel(rarity)
				t.eq(Logic.upgradeCost(item("x", kindId, "Axe", rarity, max)), nil, `{rarity} max`)
			end
		end
		t.eq(Logic.upgradeCost(item("x", "Ash", "Sword", "Common", 1)), 24)
		t.eq(Logic.maxLevel("Common"), 10)
		t.eq(Logic.maxLevel("Mythic"), 50)
	end)

	t.test("item stats: rarity rule and +6% per level", function()
		local common = item("a", "Ash", "Sword", "Common", 5)
		local rare = item("b", "Ash", "Sword", "Rare", 1)
		t.near(Logic.itemStat(rare), Logic.itemStat(common), 1e-6, "Rare L1 = Common L5")
		t.near(Logic.statAt(common, 6) / Logic.statAt(common, 5), 1.06, 1e-9)
		local ember, ash = item("c", "Ember", "Sword", "Common", 1), item("d", "Ash", "Sword", "Common", 1)
		t.near(Logic.itemStat(ember), 3 * Logic.itemStat(ash), 1e-9)
		t.eq(Logic.weaponDamage(nil), Config.Combat.fistDamage)
		t.eq(Logic.maxHp(nil), Config.Combat.playerBaseHp)
		t.near(Logic.maxHp(item("e", "Ash", "Armor", "Common", 1)), 140, 1e-9)
	end)

	t.test("weapon powers: Rare and up, stronger by rarity, none for armor", function()
		t.eq(Logic.power(item("a", "Ember", "Sword", "Common", 1)), nil)
		t.eq(Logic.power(item("a", "Ember", "Armor", "Mythic", 1)), nil)
		local rare = Logic.power(item("a", "Ember", "Sword", "Rare", 1)) :: { [string]: any }
		local mythic = Logic.power(item("a", "Ember", "Sword", "Mythic", 1)) :: { [string]: any }
		t.eq(rare.kind, "burn")
		t.ok(mythic.dps > rare.dps, "Mythic burns harder")
		t.eq((Logic.power(item("a", "Void", "TwinBlades", "Epic", 1)) :: any).kind, "double")
	end)

	t.test("portalCost 300 then x1.6, nil at max", function()
		t.eq(Logic.portalCost(1), 300)
		t.eq(Logic.portalCost(2), 480)
		t.eq(Logic.portalCost(3), 768)
		t.eq(Logic.portalCost(4), 1229)
		t.ok(Logic.portalCost(19) ~= nil, "19 -> 20")
		t.eq(Logic.portalCost(20), nil)
	end)

	t.test("portalBonus +5% per level, tiers at 1/5/10/15/20", function()
		t.near(Logic.portalBonus(1), 1, 1e-9)
		t.near(Logic.portalBonus(11), 1.5, 1e-9)
		t.near(Logic.portalBonus(20), 1.95, 1e-9)
		t.eq(Logic.portalTier(1), 1)
		t.eq(Logic.portalTier(4), 1)
		t.eq(Logic.portalTier(5), 2)
		t.eq(Logic.portalTier(14), 3)
		t.eq(Logic.portalTier(15), 4)
		t.eq(Logic.portalTier(20), 5)
	end)

	t.test("unlocked kinds at 1/5/10/15", function()
		t.eq(#Logic.unlockedKinds(1), 1)
		t.eq(#Logic.unlockedKinds(4), 1)
		t.eq(#Logic.unlockedKinds(5), 2)
		t.eq(#Logic.unlockedKinds(10), 3)
		t.eq(#Logic.unlockedKinds(15), 4)
		t.eq(Logic.bestKind(1), "Ash")
		t.eq(Logic.bestKind(12), "Frost")
		t.eq(Logic.bestKind(20), "Void")
		t.eq(Logic.keyPrice("Ember", "Rare"), 9000)
		t.eq(Logic.keyPrice("Ash", "Legendary"), nil)
	end)

	t.test("waveSpec grows x1.15 hp, x1.10 damage, caps at 15 alive", function()
		local a = Logic.waveSpec(1, "Common", "Ash")
		local b = Logic.waveSpec(2, "Common", "Ash")
		t.eq(a.count, 5)
		t.eq(b.count, 6)
		t.near(b.hpMult / a.hpMult, 1.15, 1e-9)
		t.near(b.dmgMult / a.dmgMult, 1.10, 1e-9)
		local w11 = Logic.waveSpec(11, "Common", "Ash")
		local w12 = Logic.waveSpec(12, "Common", "Ash")
		t.eq(w11.count, 15)
		t.eq(w12.count, 15)
		t.near(w12.hpMult / w11.hpMult, 1.15 * 16 / 15, 1e-9, "extra monsters turn into strength")
		local rare = Logic.waveSpec(1, "Rare", "Ash")
		local leg = Logic.waveSpec(1, "Legendary", "Ember")
		t.near(rare.hpMult, 2, 1e-9)
		t.near(rare.coinMult, 2, 1e-9)
		t.near(leg.hpMult, 4 * 3, 1e-9)
		t.near(leg.coinMult, 5 * 6, 1e-9)
	end)

	t.test("boss waves: never on Common, ~30% every 5th on Rare, always every 5th on Legendary", function()
		local rng = Random.new(7)
		local rareBoss = 0
		for i = 1, 2000 do
			t.eq(Logic.isBossWave(5 * (i % 4 + 1), "Common", rng), false)
			t.eq(Logic.isBossWave(4, "Rare", rng), false)
			t.eq(Logic.isBossWave(7, "Legendary", rng), false)
			t.eq(Logic.isBossWave(10, "Legendary", rng), true)
			if Logic.isBossWave(5, "Rare", rng) then
				rareBoss += 1
			end
		end
		t.near(rareBoss / 2000, 0.3, 0.05, "Rare boss chance")
	end)

	t.test("chest kinds and minimum rarities", function()
		t.eq(Logic.chestKind(3, false), "normal")
		t.eq(Logic.chestKind(5, false), "big")
		t.eq(Logic.chestKind(10, true), "boss")
		local first = Logic.rollChest(1, "Common", "Ash", Random.new(1), { first = true })
		t.eq(#first, 1)
		t.eq(first[1].type, Config.Gear.firstChest.type)
		t.eq(first[1].rarity, Config.Gear.firstChest.rarity)
		local mythic = 0
		for seed = 1, 400 do
			local rng = Random.new(seed)
			local normal = Logic.rollChest(3, "Common", "Ash", rng)
			t.eq(#normal, 1)
			local big = Logic.rollChest(5, "Common", "Ash", rng)
			t.eq(#big, 3)
			t.ok(Logic.rarityOrder(big[1].rarity) >= Logic.rarityOrder("Epic"), "big chest best >= Epic")
			local boss = Logic.rollChest(5, "Rare", "Frost", rng, { boss = true })
			t.eq(#boss, 3)
			t.ok(Logic.rarityOrder(boss[1].rarity) >= Logic.rarityOrder("Legendary"), "boss chest best >= Legendary")
			t.eq(boss[1].kind, "Frost")
			local legBoss = Logic.rollChest(5, "Legendary", "Void", rng, { boss = true })
			if legBoss[1].rarity == "Mythic" then
				mythic += 1
			end
		end
		t.ok(mythic / 400 >= 0.12, `Legendary boss chests give Mythic often enough ({mythic}/400)`)
	end)

	t.test("chest odds get better every 5 waves", function()
		local early = Logic.boostedOdds(Config.GearOdds.RareKey, 0, Config.Gear.chestOddsStep)
		local late = Logic.boostedOdds(Config.GearOdds.RareKey, 3, Config.Gear.chestOddsStep)
		local e, l = Logic.oddsPercent(early), Logic.oddsPercent(late)
		t.ok(l[#l].percent > e[#e].percent, "rarest more likely later")
		t.ok(l[1].percent < e[1].percent, "commonest less likely later")
	end)

	t.test("map key odds incl. Luckier Keys tables", function()
		local ash = Config.AreaById.Ash
		t.eq(Logic.mapKeyOdds("inner", ash, false), Config.MapKeyOdds.MapInner)
		t.eq(Logic.mapKeyOdds("outer", ash, false), Config.MapKeyOdds.MapOuter)
		t.eq(Logic.mapKeyOdds("inner", ash, true), Config.MapKeyOdds.MapInnerLucky)
		t.eq(Logic.mapKeyOdds("outer", ash, true), Config.MapKeyOdds.MapOuterLucky)
		local rngA, rngB = Random.new(3), Random.new(11)
		local inner, outer = 0, 0
		local n = 20000
		for _ = 1, n do
			if Logic.rollMapKey("inner", ash, false, rngA) then
				inner += 1
			end
			local r = Logic.rollMapKey("outer", ash, true, rngB)
			if r then
				outer += 1
				t.ok(Config.KeyRarities[r], "a key rarity")
			end
		end
		t.near(inner / n, 0.08, 0.01, "inner 8%")
		t.near(outer / n, 0.12, 0.01, "outer 12%")
	end)

	t.test("killCoins, loss value and recover tiers", function()
		local spec = Logic.waveSpec(1, "Common", "Ash")
		t.eq(Logic.killCoins(Config.Monsters.AshImp, spec, 1, 1), Config.Monsters.AshImp.coins)
		t.eq(Logic.killCoins(Config.Monsters.AshImp, spec, 1, 2), Config.Monsters.AshImp.coins * 2)
		local zero = { count = 1, hpMult = 1, dmgMult = 1, coinMult = 0 }
		t.ok(Logic.killCoins(Config.Monsters.AshImp, zero, 1, 1) >= 1, ">= 1")
		local lost = { item("a", "Ember", "Sword", "Rare", 3) }
		t.near(Logic.lossValue(600, lost, "Ember"), (600 + 50 * 6) / 6, 1e-9)
		t.eq(Logic.recoverTier(999), "small")
		t.eq(Logic.recoverTier(1000), "medium")
		t.eq(Logic.recoverTier(10000), "big")
		t.near(Logic.riftHpMult(1), 1, 1e-9)
		t.near(Logic.riftHpMult(3), 2.2, 1e-9)
	end)

	t.test("questsForDay: 3 distinct quests, deterministic, varies by day", function()
		local differs = false
		local first = Logic.questsForDay(20000, 123456)
		for day = 20000, 20060 do
			for _, userId in { 1, 123456, 9876543210 } do
				local a = Logic.questsForDay(day, userId)
				local b = Logic.questsForDay(day, userId)
				t.eq(#a, 3)
				local seen = {}
				for i, id in a do
					t.eq(id, b[i], "deterministic")
					t.ok(not seen[id], "distinct")
					seen[id] = true
				end
				if userId == 123456 and table.concat(a, ",") ~= table.concat(first, ",") then
					differs = true
				end
			end
		end
		t.ok(differs, "quests change between days")
		local reward = Logic.questReward(1, "Ember")
		t.eq(reward.coins, 300 * 6)
		t.eq(reward.key, "Common")
		t.eq(Logic.questReward(3, "Ash").key, "Rare")
		t.eq(Logic.dayNumber(86400 * 3 + 5), 3)
	end)

	t.test("index rewards: area, row and all", function()
		local index = { monsters = {}, gear = {}, claimed = {} }
		t.eq(#Logic.indexRewards(index), 0)
		for _, id in Config.KeyKinds.Ash.monsters do
			index.monsters[id] = true
		end
		t.eq(#Logic.indexRewards(index), 0, "boss still missing")
		index.monsters.AshenGolem = true
		local r = Logic.indexRewards(index)
		t.eq(#r, 1)
		t.eq(r[1].id, "Area:Ash")
		index.claimed["Area:Ash"] = true
		t.eq(#Logic.indexRewards(index), 0, "claimed")
		for _, kindId in Config.KindOrder do
			for _, typeId in Config.KindGear[kindId] do
				index.gear[`{kindId}|{typeId}|Common`] = true
			end
		end
		local rows = Logic.indexRewards(index)
		t.eq(#rows, 1)
		t.eq(rows[1].coins, Config.Index.rowCoins.Common)
	end)

	t.test("areaAt finds rings and bands", function()
		local a, band = Logic.areaAtRadius(200)
		t.eq(a and a.id, "Ash")
		t.eq(band, "inner")
		local b, band2 = Logic.areaAt(Vector3.new(0, 5, 800))
		t.eq(b and b.id, "Void")
		t.eq(band2, "outer")
		t.eq(Logic.areaAtRadius(50), nil, "courtyard")
		t.eq(Logic.musicTier(1), 1)
		t.eq(Logic.musicTier(5), 2)
		t.eq(Logic.musicTier(99), #Config.Music.Combat)
	end)
end
