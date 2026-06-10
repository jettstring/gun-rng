local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

export type SettingHandler = (value: any) -> boolean

local ClientSettingHandlers = {
	-- Sounds
	["BackgroundMusic"] = function(enabled: boolean)
		SoundService.BackgroundMusic.Volume = enabled and 0.5 or 0
	end,
	
	["UISounds"] = function(enabled: boolean)
		SoundService.SFX.Volume = enabled and 0.5 or 0
	end,
	
}

return ClientSettingHandlers
