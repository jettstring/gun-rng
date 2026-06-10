export type RebirthReward = {
	displayIcon: string,
	description: string,
}

local RebirthRewards: {[number]: {[string]: RebirthReward}} = {
	
	[1] = {
		["Teleporter"] = {
			displayIcon = "99619551950595",
			description = "Allows you to teleport between zones.",
		},
	},
	
	[2] = {
		["Hoverboard"] = {
			displayIcon = "118774482065384",
			description = "swag board",
		},
	},
	--[7] = {
	--	["Teleporter"] = {
	--		displayIcon = "99619551950595",
	--		description = "Allows you to teleport between zones.",
	--	},
		
	--	["Hoverboard"] = {
	--		displayIcon = "118774482065384",
	--		description = "swag board",
	--	},
	--},
}

return RebirthRewards
