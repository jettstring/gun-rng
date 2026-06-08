local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type SpecialRoll = {
	rollsNeeded: number, -- base rolls needed to get this special roll
	rollLuckMultiplier: number, -- base multiplier for luck rolls
	displayIcon: string, 
}

local SpecialRolls = {
	["Gold"] = {
		rollsNeeded = 8,
		rollLuckMultiplier = 4,
		displayIcon = "81923133871653"
	},
	["Diamond"] = {
		rollsNeeded = 30,
		rollLuckMultiplier = 25,
		displayIcon = "103140141644613"
	},
	["Rainbow"] = {
		rollsNeeded = 70,
		rollLuckMultiplier = 250,
		displayIcon = "131037807946749"
	},
}


return SpecialRolls
