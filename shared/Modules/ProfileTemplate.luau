local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)
local InventoryUtil = require(ReplicatedStorage.Util.InventoryUtil)

return {
	Money = 10,
	Dogtags = 0,
	Rolls = 0,
	Rebirths = 0,
	CurrentZone = 1,
	
	Rolling = {
		AutoRoll = false,
		Fullscreen = false,
		
		NextSpecialRoll = nil,
		SpecialRolls = {},
		QueuedDice = {} :: {{ diceName: string, amount: number }} 
	},
	
	Inventory = {
		Weapons = {
			Owned = {},
			Equipped = {},
		},
		Items = {},
	},
	
	Index = {
		Discovered = {
			Weapons = {},
		},
		ClaimedMilestones = {} :: {[string]: {number: boolean}}
	},
	
	Ammo = AmmoTypes.createProfileData(),
	
	Upgrades = {
		UnlockedNodes = {},
	},
	
	Settings = {},

	-- Persisted data -- 
	LastSessionTimestamp = nil,
	Stats = {
		Playtime = 0,
	},

	-- Rewards 
	RedeemedCodes = {},
	ClaimedGroupReward = false,
} 
