local ReplicatedStorage = game:GetService("ReplicatedStorage")
 
local ItemAssets = ReplicatedStorage.GameAssets:WaitForChild("ItemAssets")
local ItemModels = ItemAssets:WaitForChild("ItemModels")

local MutationDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.MutationDefinitions)

type WeaponMutation = MutationDefinitions.WeaponMutation
type MutationRollChances = MutationDefinitions.MutationRollChances

export type ItemDefinition = {
	itemType: "Dice" | "Boost" | "Component" | "Ammo",
	itemDescription: string,
	displayImage : string,
	dropChance: number,
	dropWeight: number?, -- magnet pickup weight; higher values collect more slowly
	dropStack: { min: number, max: number }?,
	model: Model?,
}

export type Boost = {
	boostType: "Luck" | "RollSpeed" | "MoneyMulti",
	multiplier: number,
	duration: number,
}

export type Dice = {
	mutationRollChances: MutationRollChances,
}

export type Component = {
	addedXP: number,
}
export type ComponentDefinition = ItemDefinition & Component
export type BoostDefinition = ItemDefinition & Boost
export type DiceDefinition = ItemDefinition & Dice

local module: {[string]: ItemDefinition} = {
	-- Boosts -- 
	["Luck Potion"] = {
		itemType = "Boost",
		itemDescription = "Doubles your luck for %d minutes.",
		displayImage = "125133291656822",
		dropChance = 0.5, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		boostType = "Luck",
		multiplier = 5,
		duration = 60 * 1,
	} :: BoostDefinition,
	
	["Super Luck Potion"] = {
		itemType = "Boost",
		itemDescription = "Triples your luck for %d minutes.",
		displayImage = "77382703127232",
		dropChance = 0.05, 
		dropWeight = 3,
		model = ItemModels["SuperLuckBoost"],
		--..
		boostType = "Luck",
		multiplier = 15,
		duration = 60 * 1,
	} :: BoostDefinition,
	
	["Roll Speed Potion"] = {
		itemType = "Boost",
		itemDescription = "Doubles Roll Speed for %d minutes.",
		displayImage = "140553247200454",
		dropChance = 0.01, 
		dropWeight = 3,
		model = ItemModels["RollSpeedBoost"],
		--..
		boostType = "RollSpeed",
		multiplier = 2,
		duration = 60 * 1,
	} :: BoostDefinition,
	
	["Money Potion"] = {
		itemType = "Boost",
		itemDescription = "Doubles money earnings for %d minutes.",
		displayImage = "82071024165695",
		dropChance = 0.01, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		boostType = "MoneyMulti",
		multiplier = 2,
		duration = 60 * 1,
	} :: BoostDefinition,
	
	-- Components -- 
	["Scrap Metal"] = {
		itemType = "Component",
		itemDescription = "Adds %d XP to a weapon.",
		displayImage = "133397058036491",
		dropChance = 0.5, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		addedXP = 15
	} :: ComponentDefinition,
	
	
	
	-- Dice -- 
	["Jackpot Dice"] = {
		itemType = "Dice",
		itemDescription = "Guaranteed 3 Spin slots on your next roll.",
		displayImage = "72225316112069",
		dropChance = nil, 
		dropWeight = nil,
		model = ItemModels["LuckBoost"],
		--..
		mutationRollChances = {}
	} :: DiceDefinition,
	
	["BIG Dice"] = {
		itemType = "Dice",
		itemDescription = "Guaranteed BIG on your next roll.",
		displayImage = "72225316112069",
		dropChance = 0.5, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		mutationRollChances = { 
			["BIG"] = 1
		}
	} :: DiceDefinition,

	["Shiny Dice"] = {
		itemType = "Dice",
		itemDescription = "Guaranteed Shiny on your next roll.",
		displayImage = "72225316112069",
		dropChance = 0.1, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		mutationRollChances = { 
			["Shiny"] = 1
		}
	} :: DiceDefinition,
	
	["Inverted Dice"] = {
		itemType = "Dice",
		itemDescription = "Guaranteed Inverted on your next roll.",
		displayImage = "72225316112069",
		dropChance = 0.1, 
		dropWeight = 3,
		model = ItemModels["LuckBoost"],
		--..
		mutationRollChances = { 
			["Inverted"] = 1
		}
	} :: DiceDefinition,
	
	
	-- Ammo --
	["Smart"] = {
		itemType = "Ammo",
		itemDescription = "Homing rounds that curve toward the nearest enemy.",
		displayImage = "0",
		dropChance = 0.03,
		dropWeight = 3,
		dropStack = { min = 15, max = 20 },
		model = ItemModels:FindFirstChild("SmartAmmo"),
	},

	["Incendiary"] = {
		itemType = "Ammo",
		itemDescription = "Ignites enemies, dealing burn damage over time.",
		displayImage = "0",
		dropChance = 0.01,
		dropWeight = 3,
		dropStack = { min = 10, max = 15 },
		model = ItemModels:FindFirstChild("IncendiaryAmmo"),
	},

	["Explosive"] = {
		itemType = "Ammo",
		itemDescription = "Detonates on impact, damaging nearby enemies.",
		displayImage = "0",
		dropChance = 0.005,
		dropWeight = 3,
		dropStack = { min = 5, max = 10 },
		model = ItemModels:FindFirstChild("ExplosiveAmmo"),
	},
}


return module
