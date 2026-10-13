--!strict
-- Config: odds tables, lookups and the rarity statMult rule.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

return function(t)
	local function sum(odds: { { any } }): number
		local total = 0
		for _, row in odds do
			total += row[2] :: number
		end
		return total
	end

	t.test("every gear odds table sums to 100", function()
		for name, odds in Config.GearOdds do
			t.near(sum(odds), 100, 1e-9, name)
		end
	end)

	t.test("every map key odds table sums to 100, incl. Luckier Keys", function()
		for name, odds in Config.MapKeyOdds do
			t.near(sum(odds), 100, 1e-9, name)
		end
		t.ok(Config.MapKeyOdds.MapInnerLucky and Config.MapKeyOdds.MapOuterLucky, "lucky tables exist")
		t.eq(Config.MapKeyOdds.MapInner[3][2], 1, "inner Legendary 1%")
		t.eq(Config.MapKeyOdds.MapOuterLucky[3][2], 5, "outer lucky Legendary 5%")
	end)

	t.test("rarity statMult: next rarity at level 1 ~= previous at half its max level", function()
		t.eq(Config.Rarities[1].statMult, 1)
		for i = 2, #Config.Rarities do
			local prev, cur = Config.Rarities[i - 1], Config.Rarities[i]
			local prevAtHalf = prev.statMult * Config.LevelGrowth ^ (math.floor(prev.maxLevel / 2) - 1)
			t.near(cur.statMult, prevAtHalf, 1e-9, cur.id)
			t.ok(cur.statMult > prev.statMult, `{cur.id} stronger than {prev.id}`)
		end
	end)

	t.test("16 monsters, one boss per kind, sorted ids", function()
		t.eq(#Config.MonsterIds, 16)
		for i = 2, #Config.MonsterIds do
			t.ok(Config.MonsterIds[i - 1] < Config.MonsterIds[i], "sorted")
		end
		for _, kindId in Config.KindOrder do
			local boss = Config.Monsters[Config.BossByKind[kindId]]
			t.ok(boss and boss.boss, `{kindId} boss`)
		end
	end)

	t.test("warned attacks wind up for at least 0.4 s", function()
		for id, a in Config.Attacks do
			t.ok(a.windup >= 0.4, id)
			t.eq(a.id, id)
		end
	end)

	t.test("areas: 4 rings inside the world, outside the plots, gates on all but the first", function()
		t.eq(#Config.Areas, 4)
		local M = Config.Map
		local last = M.plotRadius + M.plotSize.Y / 2
		for i, area in Config.Areas do
			t.ok(area.inner.radius[1] > last, `{area.id} starts after the previous ring`)
			t.eq(area.inner.radius[2], area.outer.radius[1], `{area.id} bands touch`)
			t.ok(area.outer.radius[2] <= M.worldRadius, `{area.id} inside the world`)
			last = area.outer.radius[2]
			t.eq(area.inner.keyChance, 0.08)
			t.eq(area.outer.keyChance, 0.12)
			t.eq(area.gate == nil, i == 1, `{area.id} gate`)
			local count = 0
			for _, n in area.inner.monsters do
				count += n
			end
			for _, n in area.outer.monsters do
				count += n
			end
			t.ok(count >= 16 and count <= 20, `{area.id} has {count} map monsters`)
		end
	end)

	t.test("key shop prices x6 per area, Legendary never sold", function()
		t.eq(Config.KeyKinds.Ash.shop.Common, 150)
		t.eq(Config.KeyKinds.Ash.shop.Rare, 1500)
		t.eq(Config.KeyKinds.Ember.shop.Common, 900)
		t.eq(Config.KeyKinds.Void.shop.Rare, 1500 * 216)
		t.eq(Config.KeyKinds.Ash.shop.Legendary, nil)
	end)

	t.test("weapons have 3-step combos with roughly equal DPS", function()
		local dps = {}
		for _, id in { "Sword", "Axe", "TwinBlades" } do
			local gt = Config.GearTypes[id]
			local combo = gt.combo :: { any }
			t.eq(#combo, 3, id)
			local time, dmg = 0, 0
			for _, step in combo do
				time += step.windup + step.contact + step.recover
				dmg += step.damage * (if step.double then 2 else 1)
			end
			dps[id] = dmg / time
		end
		t.ok(math.abs(dps.Axe - dps.Sword) / dps.Sword < 0.1, "Axe ~ Sword")
		t.ok(math.abs(dps.TwinBlades - dps.Sword) / dps.Sword < 0.1, "Twin ~ Sword")
		local axe, sword = Config.GearTypes.Axe.combo :: any, Config.GearTypes.Sword.combo :: any
		t.ok(axe[3].damage > sword[3].damage, "Axe burst")
	end)
end
