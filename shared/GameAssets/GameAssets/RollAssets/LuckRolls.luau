local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RollAssets = ReplicatedStorage.GameAssets:WaitForChild("RollAssets")
local Gradients = RollAssets.LuckRollGradients

export type LuckRoll = {
	multiplier: number,
	displayIcon: string,
	displayGradient: UIGradient,
}

local LuckRolls = {
	[1] = {
		displayIcon = "98748609480531",
		displayGradient = Gradients["Green"],
	},
	[2] = {
		displayIcon = "129636449710983",
		displayGradient = Gradients["Yellow"],
	},
	[3] = {
		displayIcon = "129636449710983",
		displayGradient = Gradients["Orange"],
	},
	[4] = {
		displayIcon = "99240949141990",
		displayGradient = Gradients["Red"],
	},
	[5] = {
		displayIcon = "127564032589875",
		displayGradient = Gradients["Purple"],
	},
	[6] = {
		displayIcon = "105467631096914",
		displayGradient = Gradients["Blue"],
	},
	[7] = {
		displayIcon = "119504908133367",
		displayGradient = Gradients["Rainbow"],
	},
}



return LuckRolls
