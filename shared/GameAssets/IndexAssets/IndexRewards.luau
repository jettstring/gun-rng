local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.WeaponDefinitions)

export type RewardType = "Dice" | "Boost" | "Component" | "LuckMultiplier"
| "MoneyMultiplier" | "Currency"| "BaseLuck"


export type DiceReward = {
	type: "Dice",
	diceName: string,
	quantity: number,
}

export type BoostReward = {
	type: "Boost",
	boostName: string, 
	quantity: number,
}

export type ComponentReward = {
	type: "Component",
	componentName: string,
	quantity: number,
}

export type LuckMultiplierReward = {
	type: "LuckMultiplier",
	multiplier: number,
}

export type MoneyMultiplierReward = {
	type: "MoneyMultiplier",
	multiplier: number,
}

export type CurrencyReward = {
	type: "Currency",
	currency: "Money" | "Dogtags",
	amount: number,
}

export type BaseLuck = {
	type: "BaseLuck",
	amount: number,
}

export type Reward = DiceReward | BoostReward | ComponentReward 
| LuckMultiplierReward | MoneyMultiplierReward | CurrencyReward
| BaseLuck

export type Milestone = {
	discoveriesRequired: number,
	rewards: {Reward},
}

type WeaponMutation = WeaponDefinitions.WeaponMutation


---------------------------------------------

local IndexRewards: {[WeaponMutation | "Base"]: {Milestone}} = {
	["Base"] = {
		{ discoveriesRequired = 5,  rewards = {
			{type = "Dice", diceName = "BIG Dice", quantity = 1},
			{type = "LuckMultiplier", multiplier = 0.05},
		}},
		{ discoveriesRequired = 10, rewards = {
			{type = "Boost", boostName = "Roll Speed Potion", quantity = 2},
			{type = "LuckMultiplier", multiplier = 0.05},
			{type = "MoneyMultiplier", multiplier = 0.05},
		}},
	},

	["BIG"] = {
		{ discoveriesRequired = 5,  rewards = {
			{type = "Dice", diceName = "BIG Dice", quantity = 1},
			{type = "LuckMultiplier", multiplier = 0.05},
		}},
		
		{ discoveriesRequired = 10,  rewards = {
			{type = "Dice", diceName = "BIG Dice", quantity = 1},
			{type = "LuckMultiplier", multiplier = 0.05},
		}},
	},
}




return IndexRewards