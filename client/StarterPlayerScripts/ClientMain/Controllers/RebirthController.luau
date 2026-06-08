local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local Displays = playerGui:WaitForChild("Displays")
local rebirthFrame = Displays:WaitForChild("Rebirth")
local displayFrame = rebirthFrame:WaitForChild("Display")
local rebirthButton = displayFrame:WaitForChild("RebirthButton")

local GameAssets = ReplicatedStorage.GameAssets
local RebirthAssets = GameAssets.RebirthAssets
local RebirthRewards = require(RebirthAssets.RebirthRewards)

local utils = ReplicatedStorage:WaitForChild("Util")
local RebirthUtil = require(utils.RebirthUtil)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	AttemptRebirth = remotesFolder.Rebirth:WaitForChild("AttemptRebirth"),
	RebirthsUpdated = remotesFolder.Rebirth:WaitForChild("RebirthsUpdated"),
	
	-- RFs
	GetRebirthData = remotesFolder.Rebirth:WaitForChild("GetRebirthData"),
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type RebirthReward = RebirthRewards.RebirthReward

--------------------------------------------------
-- STATE --
--------------------------------------------------
local RebirthController = {}
RebirthController.Controllers = {}
RebirthController.Signals = {}

local attributeConnections = {} :: {RBXScriptConnection}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function updateRebirthDisplay(rebirthLevel: number)
	if not rebirthLevel then warn("[updateRebirthDisplay] No rebirthLevel") return end
	
	for _, connection in attributeConnections do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
	
	-- get next rebirth level data
	local nextRebirthLevel = rebirthLevel + 1
	local requiredDogtags = RebirthUtil.GetRequiredDogtags(nextRebirthLevel)
	
	local currentRebirthLabel = displayFrame:WaitForChild("CurrentRebirthLabel")
	local requirementsDisplay = displayFrame:WaitForChild("RequirementsDisplay")
	
	currentRebirthLabel.Text = string.format("You have %s rebirths", rebirthLevel)
	
	-- progress bar
	local progressBar = requirementsDisplay:WaitForChild("ProgressBar")
	local amountLabel = progressBar:WaitForChild("AmountLabel")
	local fillGradient = progressBar.Fill:WaitForChild("FillGradient")
	
	local function updateProgressBar()
		local currentDogtags = player:GetAttribute("Dogtags") or 0
		local progress = math.clamp(currentDogtags / requiredDogtags, 0, 1)
		amountLabel.Text = string.format("%s / %s", Abbreviate.AbbreviateNumber(currentDogtags, 2), Abbreviate.AbbreviateNumber(requiredDogtags, 2))
		fillGradient.Offset = Vector2.new(math.map(progress, 0, 1, -0.5, 0.5), 0)
	end
	table.insert(attributeConnections, player:GetAttributeChangedSignal("Dogtags"):Connect(updateProgressBar))
	updateProgressBar()
	
	
	
	-- Display Values
	local rebirthRewardsDisplay = displayFrame:WaitForChild("RebirthRewardsDisplay")
	local valuesDisplay = rebirthRewardsDisplay:WaitForChild("ValuesDisplay")
	local luckDisplay = valuesDisplay:WaitForChild("LuckDisplay")
	local moneyDisplay = valuesDisplay:WaitForChild("MoneyDisplay")
	local zoneDisplay = valuesDisplay:WaitForChild("ZoneDisplay")
	
	local function updateValuesDisplay()
		local currentMoney = player:GetAttribute("Money") or 0
		local currentZone = player:GetAttribute("CurrentZone") or 1
		
		-- luck
		luckDisplay.CurrentDisplay.ValueLabel.Text = "x" .. Abbreviate.AbbreviateNumber(RebirthUtil.GetRebirthLuck(rebirthLevel), 1)
		luckDisplay.NextDisplay.ValueLabel.Text = "x" .. Abbreviate.AbbreviateNumber(RebirthUtil.GetRebirthLuck(nextRebirthLevel), 1)
		
		-- money
		moneyDisplay.CurrentDisplay.ValueLabel.Text = Abbreviate.AbbreviateNumber(currentMoney, 2)
		
		-- zone
		zoneDisplay.CurrentDisplay.ValueLabel.Text = currentZone
	end
	table.insert(attributeConnections, player:GetAttributeChangedSignal("Money"):Connect(updateValuesDisplay))
	table.insert(attributeConnections, player:GetAttributeChangedSignal("CurrentZone"):Connect(updateValuesDisplay))
	updateValuesDisplay()
	
	
	-- Display rewards
	local rewardsDisplay = rebirthRewardsDisplay:WaitForChild("RewardsDisplay")
	
	for _, rewardFrame in rewardsDisplay:GetChildren() do
		if not rewardFrame:IsA("Frame") then continue end
		rewardFrame:Destroy()
	end
	
	local levelRewards = RebirthUtil.GetRebirthRewards(nextRebirthLevel)
	if not levelRewards or not next(levelRewards) then
		rewardsDisplay.Visible = false
		moneyDisplay.Visible = true
		zoneDisplay.Visible = true
	else
		for rewardName, rewardData: RebirthReward in levelRewards do
			local rewardFrame = rewardsDisplay.UIListLayout:WaitForChild("RewardTemplate"):Clone()
			rewardFrame.Name = rewardName
			rewardFrame.Visible = true
			rewardFrame.Parent = rewardsDisplay
			rewardFrame.NameLabel.Text = rewardName
			rewardFrame.IconLabel.Image = "rbxassetid://" .. (rewardData.displayIcon or "")
		end
		
		rewardsDisplay.Visible = true
		moneyDisplay.Visible = false
		zoneDisplay.Visible = false
	end
	
end

local function _setupDisplay()
	rebirthButton.Activated:Connect(function()
		remotes.AttemptRebirth:FireServer()
	end)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function RebirthController:GetRebirthData()
	local success, rebirthLevel = pcall(function()
		return remotes.GetRebirthData:InvokeServer()
	end)
	
	if not success or not rebirthLevel then
		warn("[RebirthController:GetRebirthData] Failed to get rebirth data:", rebirthLevel)
		return
	end
	
	updateRebirthDisplay(rebirthLevel)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function RebirthController:Init(controllers)
	self.Controllers = controllers

end

function RebirthController:Start()
	_setupDisplay()
	
	-- Get inital rebirth data snapshot
	player:GetAttributeChangedSignal("Loaded"):Once(function()
		self:GetRebirthData()
	end)
	if player:GetAttribute("Loaded") then self:GetRebirthData() end
	
	
	remotes.RebirthsUpdated.OnClientEvent:Connect(updateRebirthDisplay)
	
end


return RebirthController