--!strict
-- Logic: pure game maths (no services, no instances). Both sides can require it; the
-- server's answer is the real one. Randomness is passed in as `rng` so tests can seed it.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Logic = {}

export type Item = Types.Item
export type WaveSpec = Types.WaveSpec

type Rng = Random
type Area = Types.Area
type MonsterDef = Types.MonsterDef

-- Picks one id from { { id, weight }, ... }.
function Logic.weightedPick(list: { { any } }, rng: Rng): string
	local total = 0
	for _, entry in list do
		total += entry[2] :: number
	end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= entry[2] :: number
		if roll < 0 then
			return entry[1] :: string
		end
	end
	return list[#list][1] :: string
end

-- Rarity odds with rarer results weighted up by `boostSteps` (chests get better every 5 waves).
function Logic.boostedOdds(base: { { any } }, boostSteps: number, stepSize: number): { { any } }
	local out = {}
	for i, entry in base do
		local factor = (1 + stepSize * boostSteps) ^ (i - 1)
		table.insert(out, { entry[1], (entry[2] :: number) * factor })
	end
	return out
end

function Logic.rarityOrder(id: string): number
	local r = Config.RarityById[id]
	return if r then r.order else 0
end

-- Rolls a gear rarity, at least `minRarity` when given.
function Logic.rollRarity(odds: { { any } }, rng: Rng, minRarity: string?): string
	local id = Logic.weightedPick(odds, rng)
	if minRarity and Logic.rarityOrder(id) < Logic.rarityOrder(minRarity) then
		id = minRarity
	end
	return id
end

-- The main stat of an item: damage for weapons, extra health for armor.
function Logic.itemStat(item: Item): number
	local gearType = Config.GearTypes[item.type]
	local rarity = Config.RarityById[item.rarity]
	local kind = Config.KeyKinds[item.kind]
	if not gearType or not rarity or not kind then
		return 0
	end
	return gearType.baseStat * rarity.statMult * kind.statMult * Config.LevelGrowth ^ (item.level - 1)
end

function Logic.itemName(item: Item): string
	local gearType = Config.GearTypes[item.type]
	local kind = Config.KeyKinds[item.kind]
	return (if kind then kind.name else item.kind) .. " " .. (if gearType then gearType.name else item.type)
end

function Logic.itemSlot(item: Item): string
	local gearType = Config.GearTypes[item.type]
	return if gearType then gearType.slot else "Weapon"
end

-- Rounded stat for the screen: "12" or "1.2K".
function Logic.formatStat(n: number): string
	if n < 100 then
		return string.format("%d", math.floor(n + 0.5))
	end
	return Logic.short(n)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
-- Short numbers: exact under 10,000, then 12.3K, 123K, 1.23M...
function Logic.short(n: number): string
	n = math.floor(n)
	if n < 10000 then
		local s = tostring(n)
		if n >= 1000 then
			s = string.sub(s, 1, #s - 3) .. "," .. string.sub(s, -3)
		end
		return s
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local digits = if v >= 100 then 0 elseif v >= 10 then 1 else 2
	local factor = 10 ^ digits
	v = math.floor(v * factor) / factor -- round down
	return string.format("%." .. digits .. "f", v) .. SUFFIXES[i]
end

-- How big and how strong a wave is. Past `maxAlive` monsters, extra ones turn into strength.
function Logic.waveSpec(wave: number, keyRarity: string, kindId: string): WaveSpec
	local W = Config.Waves
	local kr = Config.KeyRarities[keyRarity] or Config.KeyRarities.Common
	local kind = Config.KeyKinds[kindId] or Config.KeyKinds.Ash
	local wanted = W.baseCount + wave
	local count = math.min(wanted, W.maxAlive)
	local extra = wanted / count
	return {
		count = count,
		hpMult = W.hpGrowth ^ (wave - 1) * kr.hp * kind.statMult * extra,
		dmgMult = W.dmgGrowth ^ (wave - 1) * kr.dmg * kind.statMult,
		coinMult = W.coinGrowth ^ (wave - 1) * kr.coins * kind.coinMult * extra,
	}
end

-- Weighted mix of the kind's monsters for a wave: tougher types show up more as waves go on.
function Logic.monsterMix(wave: number, kindId: string): { { any } }
	local kind = Config.KeyKinds[kindId] or Config.KeyKinds.Ash
	local list = {}
	for _, id in kind.monsters do
		local def = Config.Monsters[id]
		if def and wave >= def.minWave then
			table.insert(list, { id, def.weight + def.weightGrowth * (wave - def.minWave) })
		end
	end
	return list
end

-- The fall rule for coins: keep exactly half, rounded up in the player's favour.
function Logic.keptCoins(coins: number): number
	return math.ceil(coins / 2)
end

-- The fall rule for gear: a random half is kept, rounded up. Returns a set of kept indexes.
function Logic.randomHalf(count: number, rng: Rng): { [number]: boolean }
	local order = table.create(count, 0)
	for i = 1, count do
		order[i] = i
	end
	for i = count, 2, -1 do -- Fisher-Yates shuffle
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local kept = {}
	for i = 1, math.ceil(count / 2) do
		kept[order[i]] = true
	end
	return kept
end

-- Which chest a cleared wave gives: a boss chest after a boss wave, a big chest every 5th wave.
function Logic.chestKind(wave: number, boss: boolean): "normal" | "big" | "boss"
	if boss then
		return "boss"
	elseif wave % Config.Gear.bigChestEvery == 0 then
		return "big"
	end
	return "normal"
end

-- Rolls the gear for a chest after `wave`. Normal chest: 1 item with the next key rarity's odds.
-- Big chest (every 5th wave): 3 items, the best at least Epic. Boss chest: 3 items, the best at
-- least Legendary, and a Legendary key's boss chest can make the best one Mythic.
-- opts.first: the tutorial's first chest (Config.Gear.firstChest). Odds improve every 5 waves.
function Logic.rollChest(
	wave: number,
	keyRarity: string,
	kindId: string,
	rng: Rng,
	opts: { boss: boolean?, first: boolean? }?
): { Item }
	local G = Config.Gear
	if opts and opts.first then
		return { Logic.newItem(kindId, G.firstChest.type, G.firstChest.rarity) }
	end
	local kr = Config.KeyRarities[keyRarity] or Config.KeyRarities.Common
	local steps = math.floor((wave - 1) / G.chestOddsStepEvery)
	local odds = Logic.boostedOdds(Config.GearOdds[kr.chestOdds], steps, G.chestOddsStep)
	local kind = Logic.chestKind(wave, opts ~= nil and opts.boss == true)
	local count, minBest = 1, nil
	if kind == "boss" then
		count, minBest = G.bossChestCount, G.bossChestMin
	elseif kind == "big" then
		count, minBest = G.bigChestCount, G.bigChestMin
	end
	local items = {}
	for i = 1, count do
		local minRarity = if i == 1 then minBest else nil
		local rarity = Logic.rollRarity(odds, rng, minRarity)
		if i == 1 and kind == "boss" and kr.mythicBossChest > 0 and rng:NextNumber() < kr.mythicBossChest then
			rarity = "Mythic"
		end
		table.insert(items, Logic.newItem(kindId, Logic.rollGearType(kindId, rng), rarity))
	end
	table.sort(items, function(a, b)
		return Logic.rarityOrder(a.rarity) > Logic.rarityOrder(b.rarity)
	end)
	return items
end

function Logic.rollGearType(kindId: string, rng: Rng): string
	local types = Config.KindGear[kindId] or { "Sword" }
	return types[rng:NextInteger(1, #types)]
end

-- A monster drop: 3% chance per wave monster, with the key rarity's odds.
function Logic.rollMonsterGear(keyRarity: string, kindId: string, rng: Rng, bonus: number?): Item?
	if rng:NextNumber() >= Config.Gear.monsterDropChance * (1 + (bonus or 0)) then
		return nil
	end
	local kr = Config.KeyRarities[keyRarity] or Config.KeyRarities.Common
	return Logic.newItem(kindId, Logic.rollGearType(kindId, rng), Logic.rollRarity(Config.GearOdds[kr.gearOdds], rng))
end

function Logic.newItem(kindId: string, typeId: string, rarity: string): Item
	return { id = "", kind = kindId, type = typeId, rarity = rarity, level = 1 }
end

-- Sorts items best first: rarity, then stat.
function Logic.sortBest(items: { Item })
	table.sort(items, function(a, b)
		local ra, rb = Logic.rarityOrder(a.rarity), Logic.rarityOrder(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return Logic.itemStat(a) > Logic.itemStat(b)
	end)
end

---------------------------------------------------------------------------
-- Gear: levels, costs, merge, sell, powers
---------------------------------------------------------------------------

-- The main stat an item would have at `level`.
function Logic.statAt(item: Item, level: number): number
	return Logic.itemStat({ id = item.id, kind = item.kind, type = item.type, rarity = item.rarity, level = level })
end

function Logic.maxLevel(rarity: string): number
	local r = Config.RarityById[rarity]
	return if r then r.maxLevel else 1
end

-- Coins to go from item.level to item.level + 1; nil at max level.
function Logic.upgradeCost(item: Item): number?
	local r = Config.RarityById[item.rarity]
	local kind = Config.KeyKinds[item.kind]
	if not r or not kind or item.level >= r.maxLevel then
		return nil
	end
	return math.floor(r.upgradeBase * Config.UpgradeGrowth ^ item.level * kind.coinMult + 0.5)
end

function Logic.sellValue(item: Item): number
	local r = Config.RarityById[item.rarity]
	local kind = Config.KeyKinds[item.kind]
	if not r or not kind then
		return 0
	end
	return r.sell * kind.coinMult
end

function Logic.nextRarity(rarity: string): string?
	local r = Config.RarityById[rarity]
	local nextRow = r and Config.Rarities[r.order + 1]
	return if nextRow then nextRow.id else nil
end

-- Merge identity and index key: "Ash|Sword|Rare".
function Logic.itemKey(item: Item): string
	return `{item.kind}|{item.type}|{item.rarity}`
end

-- The 3 items a merge uses: `pick` plus the 2 lowest-level identical items that are not equipped.
-- nil when there aren't 3, or the rarity can't merge (Mythic).
function Logic.mergeGroup(items: { Item }, pick: Item, equipped: { [string]: string }): { string }?
	if not Logic.nextRarity(pick.rarity) then
		return nil
	end
	local equippedIds = {}
	for _, id in equipped do
		equippedIds[id] = true
	end
	local key = Logic.itemKey(pick)
	local others = {}
	for _, item in items do
		if item.id ~= pick.id and not equippedIds[item.id] and Logic.itemKey(item) == key then
			table.insert(others, item)
		end
	end
	if #others < 2 then
		return nil
	end
	table.sort(others, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.id < b.id
	end)
	return { pick.id, others[1].id, others[2].id }
end

-- A weapon's power row with its kind, e.g. { kind = "burn", dps = 0.2, duration = 3 }.
-- nil for Common items and armor.
function Logic.power(item: Item): { [string]: any }?
	if Logic.itemSlot(item) ~= "Weapon" then
		return nil
	end
	local def = Config.Powers[item.kind]
	local row = def and def.byRarity[item.rarity]
	if not def or not row then
		return nil
	end
	local out: { [string]: any } = { kind = def.kind }
	for k, v in row do
		out[k] = v
	end
	return out
end

function Logic.maxHp(armor: Item?): number
	local extra = if armor and Logic.itemSlot(armor) == "Armor" then Logic.itemStat(armor) else 0
	return Config.Combat.playerBaseHp + extra
end

function Logic.weaponDamage(weapon: Item?): number
	if weapon and Logic.itemSlot(weapon) == "Weapon" then
		return Logic.itemStat(weapon)
	end
	return Config.Combat.fistDamage
end

---------------------------------------------------------------------------
-- Portal levels, kinds and keys
---------------------------------------------------------------------------

-- Coins to go from `level` to `level + 1`; nil at max.
function Logic.portalCost(level: number): number?
	local P = Config.Portal
	if level >= P.maxLevel or level < 1 then
		return nil
	end
	return math.floor(P.baseCost * P.costGrowth ^ (level - 1) + 0.5)
end

-- Coins and gear drop chance multiplier from openings.
function Logic.portalBonus(level: number): number
	return 1 + Config.Portal.bonusPerLevel * (math.max(level, 1) - 1)
end

function Logic.portalTier(level: number): number
	local tier = 1
	for i, startLevel in Config.Portal.tiers do
		if level >= startLevel then
			tier = i
		end
	end
	return tier
end

function Logic.unlockedKinds(level: number): { string }
	local list = {}
	for _, kindId in Config.KindOrder do
		if Config.KeyKinds[kindId].unlockLevel <= level then
			table.insert(list, kindId)
		end
	end
	return list
end

function Logic.bestKind(level: number): string
	local list = Logic.unlockedKinds(level)
	return list[#list] or Config.KindOrder[1]
end

-- Key shop price; nil for Legendary (never sold) or unknown ids.
function Logic.keyPrice(kind: string, rarity: string): number?
	local row = Config.KeyKinds[kind]
	return if row then row.shop[rarity] else nil
end

function Logic.mapKeyOdds(band: string, area: Area, lucky: boolean): { { any } }
	local b = if band == "outer" then area.outer else area.inner
	local name = if lucky then b.odds .. "Lucky" else b.odds
	return Config.MapKeyOdds[name] or Config.MapKeyOdds[b.odds]
end

-- A map monster's key drop: nil = no key, else the key rarity.
function Logic.rollMapKey(band: string, area: Area, lucky: boolean, rng: Rng): string?
	local b = if band == "outer" then area.outer else area.inner
	if rng:NextNumber() >= b.keyChance then
		return nil
	end
	if Config.GreyTest then
		return "Common"
	end
	return Logic.weightedPick(Logic.mapKeyOdds(band, area, lucky), rng)
end

-- Exact percentages for the screen (2 decimals at most) that always sum to exactly 100:
-- rounding error goes onto the largest entry. Work in hundredths so the sum is exact.
function Logic.oddsPercent(odds: { { any } }): { Types.OddsPercent }
	local total = 0
	for _, row in odds do
		total += row[2] :: number
	end
	local out = {}
	if total <= 0 then
		return out
	end
	local hundredths = {}
	local sum, largest = 0, 1
	for i, row in odds do
		local h = math.floor((row[2] :: number) / total * 10000 + 0.5)
		hundredths[i] = h
		sum += h
		if h > hundredths[largest] then
			largest = i
		end
	end
	hundredths[largest] += 10000 - sum
	for i, row in odds do
		table.insert(out, { id = row[1] :: string, percent = hundredths[i] / 100 })
	end
	return out
end

---------------------------------------------------------------------------
-- Openings: bosses, coins, falls
---------------------------------------------------------------------------

function Logic.isBossWave(wave: number, keyRarity: string, rng: Rng): boolean
	local kr = Config.KeyRarities[keyRarity]
	if not kr or kr.bossEvery <= 0 or wave % kr.bossEvery ~= 0 then
		return false
	end
	return rng:NextNumber() < kr.bossChance
end

-- Whole coins for one kill (>= 1). spec.coinMult already holds wave, key and kind; `coinMult` is the
-- player's own multiplier (2 with the 2x Coins pass).
function Logic.killCoins(def: MonsterDef, spec: WaveSpec, portalLevel: number, coinMult: number): number
	return math.max(1, math.floor(def.coins * spec.coinMult * Logic.portalBonus(portalLevel) * coinMult + 0.5))
end

-- What a fall lost, measured in Ash coins: (coins + sell values) / kind coinMult.
function Logic.lossValue(coins: number, items: { Item }, kindId: string): number
	local total = coins
	for _, item in items do
		total += Logic.sellValue(item)
	end
	local kind = Config.KeyKinds[kindId]
	return total / (if kind then kind.coinMult else 1)
end

function Logic.recoverTier(value: number): "small" | "medium" | "big"
	local T = Config.Recover.thresholds
	if value >= T.big then
		return "big"
	elseif value >= T.medium then
		return "medium"
	end
	return "small"
end

function Logic.riftHpMult(players: number): number
	return 1 + Config.Rift.hpPerExtra * (math.max(players, 1) - 1)
end

-- Combat music step: waves 1-4 -> 1, 5-9 -> 2, 10-14 -> 3, 15+ -> 4.
function Logic.musicTier(wave: number): number
	return math.clamp(math.floor(wave / Config.Music.tierEvery) + 1, 1, #Config.Music.Combat)
end

---------------------------------------------------------------------------
-- Areas by position (rings around the centre)
---------------------------------------------------------------------------

-- The area and band at a distance from the centre; nil in the plots/courtyard or between rings.
function Logic.areaAtRadius(r: number): (Area?, string?)
	for _, area in Config.Areas do
		if r >= area.inner.radius[1] and r < area.inner.radius[2] then
			return area, "inner"
		elseif r >= area.outer.radius[1] and r < area.outer.radius[2] then
			return area, "outer"
		end
	end
	return nil, nil
end

function Logic.areaAt(pos: Vector3): (Area?, string?)
	local c = Config.Map.riftCenter
	local dx, dz = pos.X - c.X, pos.Z - c.Z
	return Logic.areaAtRadius(math.sqrt(dx * dx + dz * dz))
end

---------------------------------------------------------------------------
-- Daily key, quests, index
---------------------------------------------------------------------------

function Logic.dayNumber(t: number): number
	return math.floor(t / Config.Daily.keyEvery)
end

-- 3 distinct quest ids for (day, userId). Deterministic on every machine: a small integer LCG
-- (MINSTD), not Random, so it never depends on the engine's generator.
function Logic.questsForDay(day: number, userId: number): { string }
	local list = Config.Quests.list
	local state = ((math.floor(day) % 100000) * 7919 + (math.floor(math.abs(userId)) % 1000003) * 104729) % 2147483647
	if state == 0 then
		state = 1
	end
	local function nextInt(n: number): number
		state = (state * 48271) % 2147483647
		return state % n + 1
	end
	local order = table.create(#list, 0)
	for i = 1, #list do
		order[i] = i
	end
	local picks = {}
	local count = math.min(Config.Quests.perDay, #list)
	for i = 1, count do -- partial Fisher-Yates
		local j = i + nextInt(#list - i + 1) - 1
		order[i], order[j] = order[j], order[i]
		table.insert(picks, list[order[i]].id)
	end
	return picks
end

function Logic.questReward(slot: number, bestKind: string): { coins: number, key: string? }
	local row = Config.Quests.rewards[slot]
	if not row then
		return { coins = 0 }
	end
	local kind = Config.KeyKinds[bestKind] or Config.KeyKinds.Ash
	return { coins = (row.coins or 0) * kind.coinMult, key = row.key }
end

-- Index rewards earned and not yet claimed: an area's monsters (3 + boss) -> a Rare key of that
-- kind; a rarity row (every kind's every gear type) -> coins; everything -> the title.
function Logic.indexRewards(index: Types.IndexData): { Types.IndexReward }
	local out = {}
	local all = true
	for _, area in Config.Areas do
		local kind = Config.KeyKinds[area.kind]
		local done = index.monsters[kind.boss] == true
		for _, id in kind.monsters do
			if not index.monsters[id] then
				done = false
			end
		end
		all = all and done
		local id = `Area:{area.id}`
		if done and not index.claimed[id] then
			local reward: Types.IndexReward = { id = id, kind = "area", area = area.id, key = Config.Index.areaKey }
			table.insert(out, reward)
		end
	end
	for _, rarity in Config.Rarities do
		local done = true
		for _, kindId in Config.KindOrder do
			for _, typeId in Config.KindGear[kindId] do
				if not index.gear[`{kindId}|{typeId}|{rarity.id}`] then
					done = false
				end
			end
		end
		all = all and done
		local id = `Row:{rarity.id}`
		if done and not index.claimed[id] then
			local coins = Config.Index.rowCoins[rarity.id] or 0
			local reward: Types.IndexReward = { id = id, kind = "row", rarity = rarity.id, coins = coins }
			table.insert(out, reward)
		end
	end
	if all and not index.claimed.All then
		local reward: Types.IndexReward = { id = "All", kind = "all", title = Config.Index.title }
		table.insert(out, reward)
	end
	return out
end
return Logic
