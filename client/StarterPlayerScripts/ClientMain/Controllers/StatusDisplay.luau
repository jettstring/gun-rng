local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui


-- UI
local ScreenElements = playerGui:WaitForChild("ScreenElements")
local activeStatusDisplay = ScreenElements:WaitForChild("ActiveStatusDisplay")
local luckIcon = activeStatusDisplay:WaitForChild("LuckIcon")
local rollTimeIcon = activeStatusDisplay:WaitForChild("RollTimeIcon")

local utils = ReplicatedStorage.Util
local RollUtil = require(utils.RollUtil)

local LuckInfoPopup = require(ReplicatedStorage.Modules.LuckInfoPopup)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets.ItemDefinitions)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	BoostsUpdated = remotesFolder.Boosts:WaitForChild("BoostsUpdated"),
	LuckDataUpdated = remotesFolder.Roll:WaitForChild("LuckDataUpdated"),
	RollTimeUpdated = remotesFolder.Roll:WaitForChild("RollTimeUpdated"),
	RemoveQueuedDice = remotesFolder.Roll:WaitForChild("RemoveQueuedDice"),
	RollingDataUpdated = remotesFolder.Roll:WaitForChild("RollingDataUpdated"),
	
	-- RFs
	GetLuckData = remotesFolder.Roll:WaitForChild("GetLuckData"),
	GetRollTime = remotesFolder.Roll:WaitForChild("GetRollTime"),
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type LuckTable = RollUtil.LuckTable
type LuckInfoFrameObject = LuckInfoPopup.LuckInfoFrameObject

type ItemDefinition = ItemDefinitions.ItemDefinition
type BoostDefinition = ItemDefinitions.BoostDefinition
type DiceDefinition = ItemDefinitions.DiceDefinition

--------------------------------------------------
-- STATE --
--------------------------------------------------
local StatusDisplay = {}
StatusDisplay.Controllers = {}
StatusDisplay.Signals = {}


StatusDisplay.LuckData = {
	TotalLuck = 0,
	LuckTable = {} :: LuckTable
}

local currentLuckInfoFrame = nil

local BoostIcons = {}
local UpgradeIcons = {}
local QueuedDiceIcons = {}

local boostsTimerThreads = {} -- {[itemName]: thread}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function updateLuck()
	local totalLuck = StatusDisplay.LuckData.TotalLuck or 1
	local luckTable = StatusDisplay.LuckData.LuckTable or {}
	
	local multiLabel = luckIcon:WaitForChild("MultiLabel")
	multiLabel.Text = "x" .. Abbreviate.AbbreviateNumber(totalLuck, 1)
	
	-- update luck info frame
	if currentLuckInfoFrame and luckTable and next(luckTable) then
		currentLuckInfoFrame:Update(luckTable)
	end
end

local function updateBoosts(activeBoostsData: {})
	if not activeBoostsData then return end
	
	local function removeBoostIcon(boostName)
		if BoostIcons[boostName] then
			BoostIcons[boostName]:Destroy()
			BoostIcons[boostName] = nil
		end
		if boostsTimerThreads[boostName] then
			task.cancel(boostsTimerThreads[boostName])
			boostsTimerThreads[boostName] = nil
		end
	end
	for boostType, typeBoosts in activeBoostsData do
		for boostName, boostData in typeBoosts do
			local boostDef: BoostDefinition = ItemDefinitions[boostName]
			if not boostDef then warn("Invalid boost name:", boostName) continue end

			local existingIcon = BoostIcons[boostName]
			if not existingIcon then
				existingIcon = activeStatusDisplay.UIListLayout:WaitForChild("BoostTemplate"):Clone()
				existingIcon.Name = boostName
				existingIcon.Parent = activeStatusDisplay
				BoostIcons[boostName] = existingIcon
			end

			local iconLabel = existingIcon:WaitForChild("IconLabel")
			local timerLabel = existingIcon:WaitForChild("TimerLabel")
			
			iconLabel.Image = "rbxassetid://" .. (boostDef.displayImage or "")

			local endTimestamp = boostData.endTime or 0
			if boostsTimerThreads[boostName] then task.cancel(boostsTimerThreads[boostName]) end
			boostsTimerThreads[boostName] = task.spawn(function()
				local function formatTime(totalSeconds)
					local hours = math.floor(totalSeconds / 3600)
					local minutes = math.floor((totalSeconds % 3600) / 60)
					local seconds = math.floor(totalSeconds % 60)

					if hours > 0 then
						return string.format("%02d:%02d", hours, minutes % 60)
					else
						return string.format("%02d:%02d", minutes, seconds)
					end
				end

				while endTimestamp > os.time() do
					timerLabel.Text = formatTime(boostData.endTime - os.time())
					task.wait(1)
				end

				-- Remove icon after timer ends
				if BoostIcons[boostName] then
					BoostIcons[boostName]:Destroy()
					BoostIcons[boostName] = nil
					boostsTimerThreads[boostName] = nil 
				end
			end)

		end
	end
	
	-- Clean old
	for boostName, _ in BoostIcons do
		local boostDef = ItemDefinitions[boostName]
		local boostType = boostDef and boostDef.boostType
		
		local boostData = activeBoostsData[boostType] and activeBoostsData[boostType][boostName]
		local expired = not boostData or not boostData.endTime or boostData.endTime <= os.time()
		if not boostData or expired then
			removeBoostIcon(boostName)
		end
	end
end

local function updateQueuedDice(payload: {SpecialRollData: {NextSpecialRoll: string, SpecialRolls: {}}, DiceQueue: {}})
	local queuedDiceData = payload.DiceQueue
	if not queuedDiceData then return end

	local function removeIcon(diceName)
		if QueuedDiceIcons[diceName] then
			QueuedDiceIcons[diceName]:Destroy()
			QueuedDiceIcons[diceName] = nil
		end
	end
	
	local validQueuedDice = {}
	for _, diceEntry in queuedDiceData do
		local diceName = diceEntry.diceName
		local amount = diceEntry.amount
		
		print("Updating queued dice:", diceName, "Amount:", amount)
		
		local diceDefinition: DiceDefinition = ItemDefinitions[diceName]
		if not diceDefinition then warn("Invalid dice name:", diceName) continue end
		
		validQueuedDice[diceName] = diceEntry
		
		local existingIcon = QueuedDiceIcons[diceName]
		if not existingIcon then
			existingIcon = activeStatusDisplay.UIListLayout:WaitForChild("DiceTemplate"):Clone()
			existingIcon.Name = diceName
			existingIcon.Parent = activeStatusDisplay
			QueuedDiceIcons[diceName] = existingIcon
			
			existingIcon.Activated:Connect(function()
				remotes.RemoveQueuedDice:FireServer(diceName)
			end)
			
			local xIcon = existingIcon:WaitForChild("CancelIcon")
			existingIcon.MouseEnter:Connect(function() xIcon.Visible = true end)
			existingIcon.MouseLeave:Connect(function() xIcon.Visible = false end)
			existingIcon.SelectionGained:Connect(function() xIcon.Visible = true end)
			existingIcon.SelectionLost:Connect(function()xIcon.Visible = false end)
		end
		
		local iconLabel = existingIcon:WaitForChild("IconLabel")
		local amountLabel = existingIcon:WaitForChild("AmountLabel")
		iconLabel.Image = "rbxassetid://" .. (diceDefinition.displayImage or "")
		amountLabel.Text = string.format("x%d", amount)
		
		existingIcon.Visible = true
	end

	-- Clean old
	for diceName, _ in QueuedDiceIcons do
		local validEntry = validQueuedDice[diceName]
		if not validEntry or validEntry.amount <= 0 then
			removeIcon(diceName)
		end
	end
end

local function updateRollTime(rollTime: number)
	if not rollTime then return end

	local timeLabel = rollTimeIcon:WaitForChild("TimeLabel")
	
	local function formatTime(n)
		local s = string.format("%.2f", n)
		s = s:gsub("0+$", ""):gsub("%.$", "")
		if not s:find("%.") then s = s .. ".0" end
		return s
	end
	
	timeLabel.Text = formatTime(rollTime)
	
	-- dont show if roll time is default time
	if rollTime == RollUtil.CONFIGS.DEFAULT_ROLL_TIME then
		rollTimeIcon.Visible = true
	else
		rollTimeIcon.Visible = true
	end
end

local function updateServerLuck(serverLuckData: {})
	
end

local function _setupLuckIcon()
	-- get inital data
	local success, luckData = pcall(function()
		return remotes.GetLuckData:InvokeServer()
	end)
	if not success or not luckData then
		warn("Failed to get initial luck data:", luckData)
	else
		StatusDisplay.LuckData = luckData
		updateLuck()
	end
	
	
	local luckInfoFrame: LuckInfoFrameObject = LuckInfoPopup.new(luckIcon, StatusDisplay.LuckData.LuckTable)
	if luckInfoFrame then
		currentLuckInfoFrame = luckInfoFrame
		print("Showing luck info frame")
	end
end

local function _setupRollTimeIcon()
	-- get inital data
	local success, rollTime = pcall(function()
		return remotes.GetRollTime:InvokeServer()
	end)
	if not success or not rollTime then
		warn("Failed to get initial roll speed data:", rollTime)
	else
		updateRollTime(rollTime)
	end

	-- Setup hover info
	
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function StatusDisplay:Init(controllers)
	self.Controllers = controllers

end

function StatusDisplay:Start()	
	_setupLuckIcon()
	_setupRollTimeIcon()
	
	remotes.LuckDataUpdated.OnClientEvent:Connect(function(totalLuck: number, updatedLuckTable: LuckTable)
		StatusDisplay.LuckData = {
			TotalLuck = totalLuck,
			LuckTable = updatedLuckTable
		}
		updateLuck()
	end)
	
	remotes.BoostsUpdated.OnClientEvent:Connect(updateBoosts)
	remotes.RollTimeUpdated.OnClientEvent:Connect(updateRollTime)
	remotes.RollingDataUpdated.OnClientEvent:Connect(updateQueuedDice)
end


return StatusDisplay