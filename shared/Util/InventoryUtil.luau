local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local WeaponDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.WeaponDefinitions)
local MutationDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.MutationDefinitions)

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type RollResult = RollUtil.RollResult

export type Mutations = {[MutationDefinitions.WeaponMutation]: boolean}

export type WeaponData = {
	weaponName: string,
	mutations: Mutations,
	level: number,
	xp: number
}

export type InventoryProfileData = { 
	Guns: {},
	Items: {},
}



local InventoryUtil = {}

function InventoryUtil.isStack(key: string): boolean
	return string.sub(key, 1, 1) ~= "."
end

function InventoryUtil.generateWeaponKey(weaponData: WeaponData | RollResult): string
	if weaponData.level then
		return "." .. HttpService:GenerateGUID(false)
	end

	local mutationKey = InventoryUtil.getMutationKey(weaponData.mutations or {})
	return mutationKey .. "-" .. weaponData.weaponName
end

function InventoryUtil.getWeaponData(key: string, value: WeaponData | number): WeaponData
	if not InventoryUtil.isStack(key) then
		return value :: WeaponData
	end

	local split = string.split(key, "-")
	assert(#split == 2, `malformed inventory key: "{key}"`)

	return {
		weaponName = split[2],
		mutations = InventoryUtil.getMutationsFromKey(split[1]),
		level = 1,
		xp = 0,
	}
end

function InventoryUtil.getMutationKey(mutations: Mutations): string
	local names = {}
	for name in pairs(mutations) do
		table.insert(names, name)
	end
	table.sort(names) -- stable order, or stacks fragment
	return table.concat(names, "_")
end

function InventoryUtil.getMutationsFromKey(mutationKey: string): Mutations
	local mutations: Mutations = {}
	if mutationKey == "" then return mutations end
	for _, mutation in string.split(mutationKey, "_") do
		if mutation ~= "" then
			mutations[mutation] = true
		end
	end
	return mutations
end

function InventoryUtil.getSortedWeapons(weaponDataList: {WeaponData}): {WeaponData}
	local sorted = table.clone(weaponDataList)

	table.sort(sorted, function(a, b)
		local oddsA = WeaponDefinitions[a.weaponName] and WeaponDefinitions[a.weaponName].odds or 0
		local oddsB = WeaponDefinitions[b.weaponName] and WeaponDefinitions[b.weaponName].odds or 0
		return oddsA > oddsB 
	end)

	return sorted
end


local function xpRequiredForLevel(level: number): number
	local XP_LEVEL_CURVE_BASE = 10
	return (level - 1) ^ 3 * XP_LEVEL_CURVE_BASE
end

function InventoryUtil.getLevelFromXP(xp: number): number
	local level = 1
	while xp >= xpRequiredForLevel(level + 1) do
		level += 1
	end

	return level
end

function InventoryUtil.getNextLevelXPRequirement(weaponData: WeaponData): number
	return xpRequiredForLevel(InventoryUtil.getLevelFromXP(weaponData.xp) + 1)
end


return InventoryUtil

