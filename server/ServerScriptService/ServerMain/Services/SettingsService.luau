local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

-- Settings Assets
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local SettingsAssets = GameAssets:WaitForChild("SettingsAssets")
local SettingsDefinitions = require(SettingsAssets.SettingsDefinitions)
local ServerSettingHandlers = require(SettingsAssets.ServerSettingHandlers)

local SettingsUtil = require(ReplicatedStorage.Util.SettingsUtil)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	SettingsUpdated = remotesFolder.Settings.SettingsUpdated,
	ChangeSettingValue = remotesFolder.Settings.ChangeSettingValue,	

	-- RFs
	GetSettingsData = remotesFolder.Settings.GetSettingsData
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type SettingOption = SettingsDefinitions.SettingOption
type SettingGroup = SettingsDefinitions.SettingGroup

type SettingHandler = ServerSettingHandlers.SettingHandler

--------------------------------------------------
-- STATE --
--------------------------------------------------
local SettingsService = {}
SettingsService.Services = {}
SettingsService.Signals = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local flatSettingsOptions = SettingsUtil.getFlatSettingsOptions()

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function PrivateFoo()

end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function SettingsService:ChangePlayerSettingOption(player: Player, optionName: string, newValue: any)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[SettingsService] no profile for", player); return end
	
	local optionDef: SettingOption = flatSettingsOptions[optionName]
	if not optionDef then warn("[SettingsService] invalid optionName", optionName) return end
	
	
	
	local settingsData = profile.Settings
	local current = settingsData[optionName]
	-- resolve and validate the value to store
	local valueToStore
	if optionDef.optionType == "toggle" then
		-- flips current (or default)
		local effective = if current ~= nil then current else optionDef.defaultValue
		valueToStore = not effective

	elseif optionDef.optionType == "slider" then
		-- validate index to value
		if typeof(newValue) ~= "number" then return end
		local index = math.floor(newValue)
		if index < 1 or index > #optionDef.options then return end -- out of bounds
		valueToStore = index

	elseif optionName == "customLuck" then
		-- TODO		

	else
		warn("[SettingsService] unhandled optionType", optionDef.optionType)
		return
	end
	
	
	-- call handler (if any)
	local handler: SettingHandler? = ServerSettingHandlers[optionName]
	if handler then
		local ok, result = pcall(handler, player, valueToStore)
		if not ok then warn("[SettingsService] handler failed", optionName, result); return end
	end
	
	-- store
	settingsData[optionName] = valueToStore
	
	-- update client with delta
	remotes.SettingsUpdated:FireClient(player, {[optionName] = profile.Settings[optionName]})
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function SettingsService:Init(services)
	self.Services = services
end

function SettingsService:Start()
	remotes.ChangeSettingValue.OnServerEvent:Connect(function(player, optionName: string, newValue: any)
		self:ChangePlayerSettingOption(player, optionName, newValue)
	end)
	
	
	remotes.GetSettingsData.OnServerInvoke = function(player)
		local profile = self.Services.DataService:GetProfile(player)
		if not profile then warn("[SettingsService] no profile for", player) return end
		return profile.Settings
	end
end


return SettingsService