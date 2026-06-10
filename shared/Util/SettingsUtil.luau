local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Settings Assets
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local SettingsAssets = GameAssets:WaitForChild("SettingsAssets")
local SettingsDefinitions = require(SettingsAssets.SettingsDefinitions)

type SettingOption = SettingsDefinitions.SettingOption
type SettingGroup = SettingsDefinitions.SettingGroup

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

local SettingsUtil = {}

function SettingsUtil.getFlatSettingsOptions(): {[string]: SettingOption}
	local settingsOptions = {}
	
	for groupName, group: SettingGroup in SettingsDefinitions do
		for optionName, option in group.settings do
			if settingsOptions[optionName] then
				warn("duplicate setting option name", optionName)
				continue
			else
				settingsOptions[optionName] = option
			end
		end
	end
	
	return settingsOptions
end

return SettingsUtil
