local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

export type SettingHandler = (player: Player, services: any, data: any) -> boolean

local ServerSettingHandlers: {[string]: SettingHandler} = {
	["CustomLuck"] = function(player: Player, services, data: {enabled: boolean, luck: number})
		local profile = services.DataService:GetProfile(player)
		if not profile then warn("[ServerSettingHandlers] no profile for", player); return false end
		
		local settingsData = profile.Settings
		
		-- validate luck value
		if typeof(data.luck) ~= "number" then return false end
		if data.luck < 1 then return false end
		
		local maxPlayerLuck = services.RollService:GetPlayerLuck(player)
		if maxPlayerLuck and maxPlayerLuck < data.luck then
			return false
		end
		
		-- update setting
		settingsData["CustomLuck"] = {
			enabled = data.enabled,
			luck = data.luck
		}
		
		return true
	end,
} 

return ServerSettingHandlers
