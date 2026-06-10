export type SettingOption = {
	optionType: "toggle" | "slider",
	defaultValue: boolean | number,
	options: {any}?,
	displayTitle: string,
	layoutOrder: number?,
}

export type SettingGroup = { 
	layoutOrder: number,
	settings: { [string]: SettingOption },
}

local SettingsDefinitions: {[string]: SettingGroup} = {
	
	["Sound"] = {
		layoutOrder = 1,
		settings = {
			["BackgroundMusic"] = { optionType = "toggle", defaultValue = true, displayTitle = "Background Music", layoutOrder = 1 },
			["UISounds"] = { optionType = "toggle", defaultValue = true, displayTitle = "UI Sounds", layoutOrder = 2 },
		}
	},
	
	["Gameplay"] = {
		layoutOrder = 2,
		settings = {
			["CustomLuck"] = { defaultValue = false, options = {16, 17, 18}, displayTitle = "Custom Roll Luck", layoutOrder = 1 },
			["WalkSpeed"] = { optionType = "slider", defaultValue = 1, options = {16, 17, 18}, displayTitle = "Walk Speed", layoutOrder = 2 },
		}
	},
	
} 

return SettingsDefinitions
