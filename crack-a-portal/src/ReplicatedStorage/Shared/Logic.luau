--!strict
-- Logic: pure game maths (no services, no instances). Both sides can require it; the
-- server's answer is the real one. Randomness is passed in as `rng` so tests can seed it.

local Config = require(script.Parent.Config)

local Logic = {}

export type Item = {
	id: string,
	kind: string,
	type: string,
	rarity: string,
	level: number,
}

export type WaveSpec = {
	count: number, -- monsters in the wave
	hpMult: number,
	dmgMult: number,
	coinMult: number,
}

type Rng = Random

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

-- Rolls the gear for a chest after `wave`. Normal chest: 1 item with the next key rarity's odds.
-- Every 5th wave: a big chest with 3 items, the best at least Epic.
function Logic.rollChest(wave: number, keyRarity: string, kindId: string, rng: Rng): { Item }
	local G = Config.Gear
	local kr = Config.KeyRarities[keyRarity] or Config.KeyRarities.Common
	local steps = math.floor((wave - 1) / G.chestOddsStepEvery)
	local odds = Logic.boostedOdds(Config.GearOdds[kr.chestOdds], steps, G.chestOddsStep)
	local big = wave % G.bigChestEvery == 0
	local count = if big then G.bigChestCount else 1
	local items = {}
	for i = 1, count do
		local minRarity = if big and i == 1 then G.bigChestMin else nil
		table.insert(items, Logic.newItem(kindId, Logic.rollGearType(kindId, rng), Logic.rollRarity(odds, rng, minRarity)))
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

return Logic
