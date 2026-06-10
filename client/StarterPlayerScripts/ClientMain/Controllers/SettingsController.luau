local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer 
local playerGui = player.PlayerGui

-- UI
local displays = playerGui:WaitForChild("Displays")
local SettingsFrame = displays:WaitForChild("Settings")
local optionsList = SettingsFrame:WaitForChild("Options")
local displayFrame = SettingsFrame:WaitForChild("Display")
local settingsList = displayFrame:WaitForChild("SettingsList")


-- Settings Assets
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local SettingsAssets = GameAssets:WaitForChild("SettingsAssets")
local SettingsDefinitions = require(SettingsAssets.SettingsDefinitions)
local ClientSettingHandlers = require(SettingsAssets.ClientSettingHandlers)

local SettingsUtil = require(ReplicatedStorage.Util.SettingsUtil)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SliderBar = require(Modules.SliderBar)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	SettingsUpdated = remotesFolder.Settings.SettingsUpdated,
	ChangeSettingValue = remotesFolder.Settings.ChangeSettingValue,	
	LuckDataUpdated = remotesFolder.Roll.LuckDataUpdated,
	
	-- RFs
	GetSettingsData = remotesFolder.Settings.GetSettingsData,
	GetLuckData = remotesFolder.Roll.GetLuckData,
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type SettingOption = SettingsDefinitions.SettingOption
type SettingGroup = SettingsDefinitions.SettingGroup

type SettingHandler = ClientSettingHandlers.SettingHandler

type SliderBarObject = SliderBar.SlideBarObject


--------------------------------------------------
-- STATE --
--------------------------------------------------
local SettingsController = {}
SettingsController.Controllers = {}
SettingsController.Signals = {}

SettingsController.SettingsData = {} 

local SettingsOptionFrames = {} :: {[string]: Frame}
local OptionSliderBars = {} :: {[string]: SliderBarObject}

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function getCustomLuckValues(): (boolean, number)
	local luckOptionData = SettingsController.SettingsData["CustomLuck"]
	local enabledValue = if luckOptionData and luckOptionData.enabled then luckOptionData.enabled else false
	local luckValue = if luckOptionData and luckOptionData.luck then luckOptionData.luck else 1

	return enabledValue, luckValue
end

local function updateOptionFrame(optionName: string, optionDef: SettingOption, value: any)
	local optionFrame = SettingsOptionFrames[optionName]
	if not optionFrame then return end
	
	local display = optionFrame.Display

	if optionDef.optionType == "toggle" then
		local titleLabel = display.TitleLabel
		local toggleButton = display.ToggleButton

		toggleButton.GreenGradient.Enabled = value
		toggleButton.RedGradient.Enabled = not value
		
		toggleButton.ValueLabel.Text = value and "On" or "Off"
		
	elseif optionDef.optionType == "slider" then
		local titleLabel = display.TitleLabel
		local sliderFrame = display.SliderFrame
		local valueDisplay = display.ValueDisplay

		local slider = OptionSliderBars[optionName]
		if slider then
			slider:SetValue(value, true)
			valueDisplay.ValueLabel.Text = tostring(optionDef.options[value])
		end
		
	elseif optionName == "CustomLuck" then
		local titleLabel = display.TitleLabel
		local toggleButton = display.ToggleButton
		local luckTextBox = display.CustomLuckDisplay.TextBox
		
		local enabled, luck = getCustomLuckValues()
		
		toggleButton.GreenGradient.Enabled = enabled
		toggleButton.RedGradient.Enabled = not enabled
		
		luckTextBox.Text = tostring(luck)
		luckTextBox.TextColor3 = if enabled then Color3.new(1, 1, 1) else Color3.new(0.5, 0.5, 0.5)
		luckTextBox.TextEditable = enabled
		
	end
	
	
	local handler = ClientSettingHandlers[optionName]
	if not handler then return end -- setting has no client effect (e.g. server-only)
	local ok, err = pcall(handler, value)
	if not ok then warn("[SettingsController] client handler failed", optionName, err) end
end

local function refreshSettings()
	local settingsData = SettingsController.SettingsData
	if not settingsData or not next(settingsData) then return end
	
	-- setup setting groups
	for _, groupData: SettingGroup in SettingsDefinitions do
		for optionName, optionDef: SettingOption in groupData.settings do
			local optionData = settingsData[optionName]
			local value = if optionData ~= nil then optionData else optionDef.defaultValue
			updateOptionFrame(optionName, optionDef, value)
		end
	end
end

local function getSettingsData()
	local success, result = pcall(function()
		return remotes.GetSettingsData:InvokeServer()
	end)
	if not success then warn("[GetSettingsData] Failed:", result); return end
	if result == nil then warn("[GetSettingsData] nil result"); return end
	
	SettingsController.SettingsData = result 
	refreshSettings()
end


local function setupOptionFrame(optionName: string, optionDef: SettingOption): Frame
	local optionTemplates = settingsList.UIListLayout.OptionTemplates
	
	-- resolve frame template
	if optionDef.optionType == "toggle" then
		local optionFrame = optionTemplates.ToggleSettingTemplate:Clone()
		local display = optionFrame.Display
		local titleLabel = display.TitleLabel
		local toggleButton = display.ToggleButton
		
		titleLabel.Text = optionDef.displayTitle
		optionFrame.LayoutOrder = optionDef.layoutOrder
		
		toggleButton.Activated:Connect(function()
			remotes.ChangeSettingValue:FireServer(optionName)
		end)
		
		return optionFrame
		
	elseif optionDef.optionType == "slider" then
		local optionFrame = optionTemplates.SliderSettingTemplate:Clone()
		local display = optionFrame.Display
		local titleLabel = display.TitleLabel
		local sliderFrame = display.SliderFrame
		local valueDisplay = display.ValueDisplay
		
		titleLabel.Text = optionDef.displayTitle
		optionFrame.LayoutOrder = optionDef.layoutOrder
		
		local config = {
			values = optionDef.options,
		}
		local sliderBar: SliderBarObject = SliderBar.new(sliderFrame, config)
		OptionSliderBars[optionName] = sliderBar
		sliderBar.changedSignal:Connect(function(newValue)
			remotes.ChangeSettingValue:FireServer(optionName, newValue)
			valueDisplay.ValueLabel.Text = tostring(newValue)
		end)
		
		return optionFrame
		
	elseif optionName == "CustomLuck" then
		local optionFrame = optionTemplates.LuckSetting:Clone()
		local display = optionFrame.Display
		local titleLabel = display.TitleLabel
		local toggleButton = display.ToggleButton
		local luckTextBox = display.CustomLuckDisplay.TextBox
		local maxLuckLabel = display.MaxLuckLabel

		titleLabel.Text = optionDef.displayTitle
		optionFrame.LayoutOrder = optionDef.layoutOrder
		
		local enabled, luck = getCustomLuckValues()
		
		toggleButton.Activated:Connect(function()
			local enabled, luck = getCustomLuckValues()
			remotes.ChangeSettingValue:FireServer(optionName, {
				enabled = not enabled,
				luck = luck,
			})
		end)	
		
		luckTextBox.FocusLost:Connect(function()
			local enabled, _ = getCustomLuckValues()
			local luck = tonumber(luckTextBox.Text) or 1
			remotes.ChangeSettingValue:FireServer(optionName, {
				enabled = enabled,
				luck = luck,
			})
		end)
		
		luckTextBox.ReturnPressedFromOnScreenKeyboard:Connect(function()
			local enabled, _ = getCustomLuckValues()
			local luck = tonumber(luckTextBox.Text) or 1
			remotes.ChangeSettingValue:FireServer(optionName, {
				enabled = enabled,
				luck = luck,
			})
			
			luckTextBox:ReleaseFocus()
		end)
		
		
		-- get inital luck data
		local success, luckData = pcall(function()
			return remotes.GetLuckData:InvokeServer()
		end)
		if not success or not luckData then
			warn("[setupOptionFrame] Failed to get initial luck data:", luckData)
		else
			if luckData.TotalLuck then
				maxLuckLabel.Text = string.format("Max: x%s", luckData.TotalLuck)
			end
		end
		
		-- listen for total luck updates
		remotes.LuckDataUpdated.OnClientEvent:Connect(function(totalLuck: number, updatedLuckTable: LuckTable)
			if totalLuck then
				maxLuckLabel.Text = string.format("Max: x%s", totalLuck)
			end
		end)
		
		return optionFrame
		
	end
	
	return nil
end

local function _setupSettings()
	-- clear frames
	for _, child in settingsList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	
	-- setup setting groups
	for settingGroup, groupData: SettingGroup in SettingsDefinitions do
		if not groupData.settings or groupData.settings and next(groupData.settings) == nil then continue end
		
		local groupTemplate = settingsList.UIListLayout.GroupTemplate:Clone()
		groupTemplate.Name = settingGroup
		groupTemplate.GroupNameLabel.Text = settingGroup
		groupTemplate.LayoutOrder = groupData.layoutOrder
		
		-- setup group options
		for optionName, optionDef: SettingOption in groupData.settings do
			local optionFrame = setupOptionFrame(optionName, optionDef)
			if not optionFrame then
				warn("[SettingsController] No option frame for", optionName)
				continue
			else
				SettingsOptionFrames[optionName] = optionFrame
				optionFrame.Parent = groupTemplate
				updateOptionFrame(optionName, optionDef, optionDef.defaultValue)
			end
		end
		
		groupTemplate.Parent = settingsList
	end
	
end

local function refreshStats() end

local function _setupStats() end
	

local function _setup()
	_setupSettings()
	_setupStats()
	
	getSettingsData()
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function SettingsController:PublicFoo()

end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function SettingsController:Init(controllers)
	self.Controllers = controllers
end

function SettingsController:Start()
	-- Get inital weapons data snapshot
	player:GetAttributeChangedSignal("Loaded"):Once(function()
		_setup()
	end)
	if player:GetAttribute("Loaded") then
		_setup()
	end

	remotes.SettingsUpdated.OnClientEvent:Connect(function(delta)
		if not delta then return end
		for key, value in delta do
			self.SettingsData[key] = value
		end
		refreshSettings()
	end)
end


return SettingsController