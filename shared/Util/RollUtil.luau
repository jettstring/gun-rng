local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local RollAssets = ReplicatedStorage.GameAssets.RollAssets
local LuckRolls = require(RollAssets.LuckRolls)

local WeaponDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.WeaponDefinitions)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)

local MutationDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.MutationDefinitions)

local ItemDefinitions = require(ReplicatedStorage.GameAssets.ItemAssets.ItemDefinitions)
local InventoryUtil = require(ReplicatedStorage.Util.InventoryUtil)

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type DiceDefinition = ItemDefinitions.DiceDefinition

type Mutations = InventoryUtil.Mutations

type WeaponMutation = MutationDefinitions.WeaponMutation
type MutationRollChances = MutationDefinitions.MutationRollChances

type LuckRoll = LuckRolls.LuckRoll


export type RollData = {
	columns : number,
	rollTime: number,
	playerLuck: number,
	mutationRollLuck: {[WeaponMutation]: number},
	specialRoll: string?,
	specialDice : string?,
	guaranteedJackpot: boolean?,
}

export type RollResult = {
	type: string,
	rollLuckMultiplier: number?,
	weaponName: string?,
	mutations: {},
}

export type JackpotResult = {
	weaponName: string,
	mutations: string?,
}

export type ColumnResults = {[number]: RollResult}

export type BonusChainType = "Spin" | "RollLuck"

export type LuckTable = {
	Multiplied: {
		["Server Luck"]: number,
		["Index"]: number,
		["Rebirths"]: number,
	},
	Added: {
		["Zone Luck"]: number,
		["Upgrades"]: number,
		["Friends"]: number,
		["Like/Group"]: number,
		["Boosts"]: number,
	}
}


local RollUtil = {}
RollUtil.SortedWeapons = WeaponUtil.getSortedWeapons()

local CONFIGS = {
	MAX_COLUMNS = #LuckRolls,
	LUCK_ROLL_CHANCE = 0.40,
	DEFAULT_ROLL_TIME = 3,
	CONSECUTIVE_ROLL_TIME_FRACTION  = 1/2,
	JACKPOT_ROLL_TIME = 9,
}
RollUtil.CONFIGS = CONFIGS

local MUTATION_ROLL_CHANCES = MutationDefinitions.RollChances


function RollUtil.randomRoll(chance: number, n: number): boolean
	return math.random() < 1 - (1 - chance) ^ n
end

function RollUtil.rolledJackpot(columnResults: ColumnResults): boolean
	for _, rollResult: RollResult in columnResults do
		if rollResult.type ~= "Spin" then return false end
	end
	return true
end

function RollUtil.getLuckRollTier(multiplier: number): number
	return math.round(math.log(multiplier, 2))
end

function RollUtil.getLuckRollDef(multiplier: number): LuckRoll?
	local tier = RollUtil.getLuckRollTier(multiplier)
	return LuckRolls[tier]
end

function RollUtil.isWeaponRoll(rollResult: RollResult): boolean
	return rollResult.type == "Weapon"
end

function RollUtil.getRollLuckMultiplier(rollResult: RollResult): number?
	if rollResult.type ~= "RollLuck" then return nil end
	return rollResult.rollLuckMultiplier or 1
end

function RollUtil.getEffectiveRollData(rollData: RollData, rollLuckMultiplier: number?): RollData
	local effectiveRollData = table.clone(rollData)
	effectiveRollData.playerLuck = rollData.playerLuck * (rollLuckMultiplier or 1)
	
	-- resolve mutation luck table
	
	return effectiveRollData
end

function RollUtil.rollWeaponResult(effectiveRollData: RollData): RollResult
	return {
		type = "Weapon",
		weaponName = RollUtil.rollWeapon(effectiveRollData),
		mutations = RollUtil.rollMutations(effectiveRollData.mutationRollLuck, effectiveRollData.specialDice),
	}
end

function RollUtil.rollBonusType(rollData: RollData, bonusChainType: BonusChainType): string
	-- Roll for a continuous bonus chain
	if bonusChainType then
		if bonusChainType == "RollLuck" then
			return if RollUtil.randomRoll(CONFIGS.LUCK_ROLL_CHANCE, 1) then "RollLuck" else nil
		elseif bonusChainType == "Spin" then
			local spinContinueChance = 0.25 -- TODO: read from rollData.playerLuck
			return if RollUtil.randomRoll(spinContinueChance, 1) then "Spin" else nil
		end
	end
	
	-- Roll for a starting bonus type
	local spinStartChance = 0.2 -- TODO: read from rollData.playerLuck
	if RollUtil.randomRoll(spinStartChance, 1) then
		return "Spin"
	end
	
	if RollUtil.randomRoll(CONFIGS.LUCK_ROLL_CHANCE, 1) then
		return "RollLuck"
	end
	
	-- no bonus
	return nil
end

function RollUtil.rollMutations(mutationRollLuck: {[WeaponMutation]: number}, specialDiceName: string): Mutations
	local rolled = {}
	
	for mutationName, rollOdds in MUTATION_ROLL_CHANCES do
		local mutationLuckMulti = mutationRollLuck[mutationName] or 1
		
		-- resolve modified dice mutation chances
		if specialDiceName then
			local diceDef: DiceDefinition? = ItemDefinitions[specialDiceName]
			if diceDef and diceDef.mutationRollChances then
				local diceMutationOdds = diceDef.mutationRollChances[mutationName]
				if diceMutationOdds then
					rollOdds = diceMutationOdds
				end
			end
		end
		
		if RollUtil.randomRoll(rollOdds, mutationLuckMulti) then
			rolled[mutationName] = true
		end
	end

	return rolled
end

function RollUtil.rollWeapon(effectiveRollData: RollData): string
	for i = #RollUtil.SortedWeapons, 1, -1 do
		local weaponName = RollUtil.SortedWeapons[i]
		local weaponDefinition: WeaponDefinition = WeaponDefinitions[weaponName]
		local odds = weaponDefinition.odds or 0
		
		if RollUtil.randomRoll(odds, effectiveRollData.playerLuck) then
			return weaponName
		end
	end
	
	-- Fallback to first weapon
	return RollUtil.SortedWeapons[1]
end

function RollUtil.rollJackpotWeapon(rollData: RollData): JackpotResult
	local effectiveRollData = RollUtil.getEffectiveRollData(rollData, 1000)
	return { weaponName = RollUtil.rollWeapon(effectiveRollData) }
end


function RollUtil.getRollResult(rollData: RollData, columnIndex: number, rollLuckMultiplier: number, bonusChainType: BonusChainType): RollResult
	local currentRollLuckMulti = rollLuckMultiplier or 1
	
	-- apply roll luck to existing luckData 
	local effectiveRollData = RollUtil.getEffectiveRollData(rollData, currentRollLuckMulti)
	
	-- return weapon if columnIndex exceeds max columns
	if columnIndex > CONFIGS.MAX_COLUMNS then
		return RollUtil.rollWeaponResult(effectiveRollData)
	end
	
	-- return spin if jackpot
	if rollData.guaranteedJackpot then
		return { type = "Spin" }
	end
	
	local bonusType = RollUtil.rollBonusType(rollData, bonusChainType)
	if bonusType then
		if bonusType == "RollLuck" then
			return { type = "RollLuck", rollLuckMultiplier = (currentRollLuckMulti * 2) }
		elseif bonusType == "Spin" then
			return { type = "Spin" }
		end
	end
	
	-- Roll for weapon
	return RollUtil.rollWeaponResult(effectiveRollData)
end
	
-- Builds a roll column roll result
function RollUtil.rollColumn(rollData: RollData): ColumnResults
	local columnResults: ColumnResults = {}
	local rollLuck = 1
	local bonusChainType: BonusChainType = nil
	local spinChainCount = 0
	
	-- Roll until we have a result
	while true do
		local columnIndex = #columnResults + 1
		
		local rollResult: RollResult = RollUtil.getRollResult(rollData, columnIndex, rollLuck, bonusChainType)
		if not rollResult then warn("[rollColumn] No rollResult") break end
		
		-- Classify bonus chain if rollResult is a bonus type
		if rollResult.type == "Spin" then
			bonusChainType = "Spin"
			spinChainCount += 1
		elseif rollResult.type == "RollLuck" then
			bonusChainType = "RollLuck"
			rollLuck =  RollUtil.getRollLuckMultiplier(rollResult) or rollLuck
		end
		
		-- Add to column results
		columnResults[columnIndex] = rollResult
		
		-- Break if we have a bonus chain and it's complete (3 in a row)
		if spinChainCount and spinChainCount >= 3 then
			break
		end
		
		-- Break if we have a weapon result
		if RollUtil.isWeaponRoll(rollResult) then
			break
		end
	end
	
	
	return columnResults
end

-- Simulates a roll with n columns
function RollUtil.roll(rollData: RollData): {ColumnResults}
	local results = {}
	for i = 1, rollData.columns  do
		local columnResult = RollUtil.rollColumn(rollData)
		if not columnResult then warn("[Roll] No columnResult result") continue end
		results[i] = columnResult
	end
	
	return results
end






return RollUtil
