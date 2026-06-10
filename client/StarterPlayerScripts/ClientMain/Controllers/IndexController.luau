local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Spr = require(ReplicatedStorage.Packages.Spr)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local camera = workspace.CurrentCamera

-- UI
local IndexGui = playerGui:WaitForChild("IndexGui")
local hotbar = IndexGui:WaitForChild("Hotbar")
local selectedWeaponDisplay = IndexGui:WaitForChild("SelectedWeaponDisplay")
local displayFrame = IndexGui:WaitForChild("Display")
local mutationButtons = displayFrame:WaitForChild("MutationButtons")
local weaponDisplay = displayFrame:WaitForChild("WeaponDisplay")
local progressDisplay = displayFrame:WaitForChild("ProgressDisplay")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemDefinitions = require(GameAssets.ItemAssets.ItemDefinitions)
local WeaponDefinitions = require(GameAssets.WeaponAssets.WeaponDefinitions)


local IndexAssets = GameAssets:WaitForChild('IndexAssets')
local IndexRewards = require(IndexAssets.IndexRewards)
local IndexScene = IndexAssets:WaitForChild("IndexScene")



local utils = ReplicatedStorage:WaitForChild("Util")
local IndexUtil = require(utils.IndexUtil)
local InventoryUtil = require(utils.InventoryUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)


local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	ClaimIndexMilestone = remotesFolder.Index.ClaimIndexMilestone,
	IndexDataUpdated = remotesFolder.Index.IndexDataUpdated,
	NewWeaponDiscovered = remotesFolder.Index.NewWeaponDiscovered,

	-- RFs
	GetIndexData = remotesFolder.Index.GetIndexData,
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type Milestone = IndexRewards.Milestone
type Reward = IndexRewards.Reward

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

--------------------------------------------------
-- STATE --
--------------------------------------------------
local IndexController = {}
IndexController.Controllers = {}
IndexController.Signals = {}

IndexController.IndexData = {}
IndexController.IsOpen = false

local activeScene = nil
local selectedMutation = nil
local selectedWeaponName = nil

local selectedWeaponModel = nil :: Model
local selectedWeaponConnections = {} :: {RBXScriptConnection}

local weaponFrames = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function ownsWeapon(weaponName: string, mutation: string): boolean
	local indexData = IndexController.IndexData
	if not indexData or not indexData.Discovered or not indexData.Discovered.Weapons then
		return false
	end
	local weaponEntry = indexData.Discovered.Weapons[weaponName]
	if not weaponEntry then return false end
	return weaponEntry[mutation] == true
end

local function countDiscoveriesForMutation(mutation: string): number
	local discovered = IndexController.IndexData 
		and IndexController.IndexData.Discovered 
		and IndexController.IndexData.Discovered.Weapons
	if not discovered then return 0 end

	local count = 0
	for _, weaponMutations in discovered do
		if weaponMutations[mutation] then
			count += 1
		end
	end
	return count
end

local function getCurrentTrackMilestone(mutation: string): (number?, MilestoneReward?, boolean)
	local indexData = IndexController.IndexData
	if not indexData then return nil, nil, false end

	local rewardTable = IndexRewards[mutation]
	if not rewardTable then return nil, nil, false end

	local discoveredCount = countDiscoveriesForMutation(mutation)
	local claimedSet = (indexData.ClaimedMilestones and indexData.ClaimedMilestones[mutation]) or {}

	for i, milestone: Milestone in rewardTable do
		if not claimedSet[i] then
			local canClaim = discoveredCount >= milestone.discoveriesRequired
			return i, milestone, canClaim
		end
	end

	-- all milestones claimed
	return nil, nil, false
end

local function getIndexData()
	local indexData = remotes.GetIndexData:InvokeServer()
	if not indexData or (indexData and next(indexData) == nil) then
		warn("[GetindexProgress] Failed to get inventory data")
		return
	else
		IndexController.IndexData = indexData
		return indexData
	end
end

local function updateIndexDisplay()
	if not selectedMutation then  selectedMutation = "Base" end
		
	for _, mutationButton in mutationButtons:GetChildren() do
		if not mutationButton:IsA("ImageButton") then continue end
		if mutationButton.Name == selectedMutation then
			mutationButton.Image = "rbxassetid://83263420812010"
		else
			mutationButton.Image = "rbxassetid://102514017089696"
		end
	end
	
	-- display weapons
	local weaponListFrame = weaponDisplay:WaitForChild("WeaponsList")
	local discoveredData = IndexController.IndexData.Discovered
	local sortedWeapons = WeaponUtil.getSortedWeapons()
	
	for i, weaponName in sortedWeapons do
		local weaponDef: WeaponDefinition = WeaponUtil.getWeaponDefinition(weaponName)
		
		local weaponFrame = weaponFrames[weaponName]
		if not weaponFrame then
			weaponFrame = weaponListFrame.UIGridLayout:WaitForChild("WeaponFrame"):Clone()
			weaponFrame.Name = weaponName
			weaponFrame.Parent = weaponListFrame
			weaponFrames[weaponName] = weaponFrame
			weaponFrame.LayoutOrder = i
			
			weaponFrame:WaitForChild("FrameButton").Activated:Connect(function()
				IndexController:SelectWeapon(weaponName)
			end)
		end
		
		local frameButton = weaponFrame:WaitForChild("FrameButton")
		local nameLabel = frameButton:WaitForChild("NameLabel")
		local oddsLabel = frameButton:WaitForChild("OddsLabel")
		local iconContainer = frameButton:WaitForChild("WeaponIconContainer")

		nameLabel.Text = WeaponUtil.getWeaponName(weaponName, {[selectedMutation] = true})
		oddsLabel.Text = "1 /" .. math.round(1 / weaponDef.odds)
		WeaponUtil.applyRarityTextEffects(oddsLabel, weaponDef.rarity)	
		
		if iconContainer:FindFirstChild("WeaponIconFrame") then iconContainer:FindFirstChild("WeaponIconFrame"):Destroy() end
		local weaponImageLabel = WeaponUtil.getDisplayImageLabel(weaponName, {[selectedMutation] = true})
		if weaponImageLabel then
			weaponImageLabel.Parent = iconContainer
		end
	end
	
	
	-- display progress for mutation track
	local milestoneIndex, milestoneRewardData, canClaim = getCurrentTrackMilestone(selectedMutation)
	local discoveredCount = countDiscoveriesForMutation(selectedMutation)
	
	local claimButton = progressDisplay:WaitForChild("ClaimButton")
	local requirementsDisplay = progressDisplay:WaitForChild("RequirementsDisplay")
	local rewardsDisplay = progressDisplay:WaitForChild("RewardsDisplay")
	
	claimButton:FindFirstChild("GreyGradient").Enabled = not canClaim
	claimButton:FindFirstChild("PurpleGradient").Enabled = canClaim
	
	-- display progress
	local progressBar = requirementsDisplay:WaitForChild("ProgressBar")
	local amountLabel = progressBar:WaitForChild("AmountLabel")
	local fillGradient = progressBar.Fill:WaitForChild("FillGradient")
	
	local denominator = milestoneRewardData.discoveriesRequired or #WeaponUtil.getSortedWeapons()
	local a = math.clamp(discoveredCount / denominator, 0, 1)
	amountLabel.Text = string.format("%s / %s", discoveredCount, denominator)
	fillGradient.Offset = Vector2.new(math.map(a, 0, 1, -0.5, 0.5), 0)
	
	-- display rewards
	local rewardsListFrame = rewardsDisplay:WaitForChild("RewardsListFrame")
	for _, rewardFrame in rewardsListFrame:GetChildren() do
		if not rewardFrame:IsA("Frame") then continue end
		rewardFrame:Destroy()
	end
	
	for index, rewardData: Reward in  milestoneRewardData.rewards do
		local rewardFrame = rewardsListFrame.UIListLayout:WaitForChild("RewardTemplate"):Clone()
		local iconLabel = rewardFrame:WaitForChild("IconLabel")
		local amountLabel = rewardFrame:WaitForChild("AmountLabel")
		
		-- resolve reward display info
		local rewardDisplayData = IndexUtil.getRewardDisplay(rewardData)
		iconLabel.Image = "rbxassetid://" .. rewardDisplayData.rewardIcon or ""
		amountLabel.Text = rewardDisplayData.amountLabel or ""
		
		rewardFrame.Parent = rewardsListFrame
	end
end


local function _setupUI()
	-- exit button
	hotbar:FindFirstChild("ExitButton").Activated:Connect(function()
		IndexController:Close()
	end)
	
	-- mutation track reward button
	progressDisplay:WaitForChild("ClaimButton").Activated:Connect(function()
		remotes.ClaimIndexMilestone:FireServer(selectedMutation)
	end)
	
	-- mutation sort buttons
	for _, mutationButton in mutationButtons:GetChildren() do
		if not mutationButton:IsA("ImageButton") then continue end
		mutationButton.Activated:Connect(function()
			selectedMutation = mutationButton.Name
			updateIndexDisplay()
			if selectedWeaponName then
				IndexController:SelectWeapon(selectedWeaponName)
			end
		end)
	end
end


--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function IndexController:SelectWeapon(weaponName)
	local weaponDef: WeaponDefinition = WeaponUtil.getWeaponDefinition(weaponName)
	if not weaponDef then warn("[SelectWeapon] failed to get weaponDef for", weaponName) return end
	
	selectedWeaponName = weaponName
	
	-- highlight weapon frame
	for frameWeaponName, weaponFrame in weaponFrames do
		local frameButton = weaponFrame:WaitForChild("FrameButton")
		local outerStroke = frameButton:WaitForChild("Outer")
		if frameWeaponName == weaponName then
			outerStroke.Color = Color3.fromRGB(255, 255, 255)
		else
			outerStroke.Color = Color3.fromRGB(0, 0, 0)
		end
	end
	
	-- update selected display ui
	local nameLabel = selectedWeaponDisplay:WaitForChild("NameLabel")
	local rarityLabel = selectedWeaponDisplay:WaitForChild("RarityLabel")
	local statsDisplay = selectedWeaponDisplay:WaitForChild("StatsDisplay")
	
	-- setup new weapon model
	local components = activeScene:WaitForChild("Components")
	local camPart = components:WaitForChild("CameraPart")
	local weaponPart = components:WaitForChild("WeaponPart")

	local weaponModel = weaponDef.model:Clone()
	
	-- check ownership
	local owned = ownsWeapon(weaponName, selectedMutation)
	if not owned then
		local lockedHightlight = Instance.new("Highlight")
		lockedHightlight.FillTransparency = .05
		lockedHightlight.OutlineTransparency = 0
		lockedHightlight.FillColor = Color3.fromRGB(0, 0, 0)
		lockedHightlight.OutlineColor = Color3.fromRGB(0, 0, 0)
		lockedHightlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		lockedHightlight.Parent = weaponModel
	end
	
	nameLabel.Text = (owned and WeaponUtil.getWeaponName(weaponName, {[selectedMutation] = true})) or "???"
	
	local rarity = WeaponUtil.deriveRarity(weaponName, {[selectedMutation] = true})
	rarityLabel.Text = rarity
	WeaponUtil.applyRarityTextEffects(rarityLabel, rarity)	

	-- cleanup previous
	if selectedWeaponModel then selectedWeaponModel:Destroy() end
	for _, connection in selectedWeaponConnections do connection:Disconnect() end

	weaponModel.Parent = weaponPart
	selectedWeaponModel = weaponModel

	weaponModel:PivotTo(weaponPart.CFrame)
end

function IndexController:Open()
	local character = player.Character
	if not character then return end
	
	if IndexController.IsOpen then return end
	IndexController.IsOpen = true
	
	self.Controllers.UIController:SetOverlayOpenSource("Index", true)
	self.Controllers.UIController:ShowScreenElements(false)
	IndexGui.Enabled = true
	updateIndexDisplay()
	
	
	
	
	-- setup scene components
	if activeScene then activeScene:Destroy() end
	activeScene = IndexScene:Clone()
	
	local components = activeScene:WaitForChild("Components")
	local camPart = components:WaitForChild("CameraPart")
	local weaponPart = components:WaitForChild("WeaponPart")
	activeScene.Parent = workspace
	activeScene:PivotTo(character:GetPivot() * CFrame.new(0, 50, 0) * IndexScene:GetPivot().Rotation)
	
	local depthOfField = IndexAssets:WaitForChild("IndexDOF"):Clone()
	depthOfField.Parent = Lighting
	depthOfField.Enabled = true
	
	-- show weapon model
	if selectedWeaponName then
		IndexController:SelectWeapon(selectedWeaponName)
	else
		IndexController:SelectWeapon(WeaponUtil.getSortedWeapons()[1])
	end
	
	-- animate camera
	local CAMERA_FLY_TIME = 0.4
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = camPart

	local cameraTween = TweenService:Create(camera, TweenInfo.new(CAMERA_FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = camPart.CFrame
	}):Play()
	
	
	-- Show UI
	task.delay(CAMERA_FLY_TIME*0.9, function()
		Spr.target(displayFrame, 0.85, 4, {
			Position = UDim2.fromScale(1, 0.5)
		})
		Spr.target(selectedWeaponDisplay, 0.85, 4, {
			Position = UDim2.fromScale(0.4, 0.03)
		})
	end)
end

function IndexController:Close()
	if not IndexController.IsOpen then
		self.Controllers.UIController:SetOverlayOpenSource("Index", false)
		return
	end

	-- UI animation
	Spr.target(displayFrame, 0.85, 4, {
		Position = UDim2.fromScale(2, 0.5)
	})
	Spr.target(selectedWeaponDisplay, 0.85, 4, {
		Position = UDim2.fromScale(0.4, -1)
	})
	
	task.wait(0.2)
	
	-- cleanup
	if Lighting:FindFirstChild("IndexDOF") then
		Lighting:FindFirstChild("IndexDOF"):Destroy()
	end
	
	-- ui
	IndexController.IsOpen = false
	IndexGui.Enabled = false
	self.Controllers.UIController:SetOverlayOpenSource("Index", false)
	self.Controllers.UIController:ShowScreenElements(true)
	
	
	if activeScene then activeScene:Destroy() end
	camera.CameraType = Enum.CameraType.Custom
	if camera and player.Character then
		local humanoid = player.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function IndexController:Init(controllers)
	self.Controllers = controllers
	
	_setupUI()
end

function IndexController:Start()
	
	-- Get inital weapons data snapshot
	player:GetAttributeChangedSignal("Loaded"):Once(function()
		getIndexData()
	end)
	if player:GetAttribute("Loaded") then getIndexData() end
	
	remotes.IndexDataUpdated.OnClientEvent:Connect(function(updatedIndexData: {})
		if updatedIndexData and next(updatedIndexData) ~= nil then
			IndexController.IndexData = updatedIndexData
			updateIndexDisplay()
		else
			warn("[IndexController] Received nil index data from server")
		end
	end)
	
	
end


return IndexController
