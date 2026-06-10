local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService") 
local StarterPlayer = game:GetService("StarterPlayer")
local CollectionService = game:GetService("CollectionService") 
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local AvatarEditorService = game:GetService("AvatarEditorService")

local TopbarPlus = require(ReplicatedStorage.Packages.Icon)
local Spr = require(ReplicatedStorage.Packages.Spr)
local Signal = require(ReplicatedStorage.Packages.Signal)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local camera = workspace.CurrentCamera

local UIsfx = SoundService:WaitForChild("UI")

-- GUIs 
local Displays = playerGui:WaitForChild("Displays")
local ScreenElements = playerGui:WaitForChild("ScreenElements")


-- UI MAPS
local displayFrames = {
	Inventory = Displays:WaitForChild("Inventory"),
	Rebirth = Displays:WaitForChild("Rebirth"),
	Settings = Displays:WaitForChild("Settings"),
}

local screenElements = {
	ActiveStatusDisplay = ScreenElements:WaitForChild("ActiveStatusDisplay"),
	BottomLeft = ScreenElements:WaitForChild("BottomLeft"),
	Hotbar = ScreenElements:WaitForChild("Hotbar"),
	LeftOptions = ScreenElements:WaitForChild("LeftOptions"),
}


local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local UIController = {}
UIController.Controllers = {}
UIController.Signals = {
	DisplayChanged = Signal.new()
}

UIController.CurrentDisplay = nil

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants
local overlayOpenSources: {[string]: boolean} = {}

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function applyOverlayOpenState()
	local overlayOpen = UIController.CurrentDisplay ~= nil or next(overlayOpenSources) ~= nil

	-- Disable the whole Crosshair ScreenGui (its .Enabled overrides descendant .Visible,
	-- which the gun framework re-drives every render frame).
	local crosshairGui = playerGui:FindFirstChild("Crosshair")
	if crosshairGui then
		crosshairGui.Enabled = not overlayOpen
	end

	-- The gun framework hides the mouse cursor each frame while aiming; this lets it
	-- restore the cursor while a window is open.
	player:SetAttribute("UIWindowOpen", overlayOpen)
end

local function setFov(fov: number)
	local camera = workspace.CurrentCamera
	if camera then
		Spr.target(camera, 0.8, 4, { FieldOfView = fov })
	end
end

local function _setupTopbar()
	local settingsButton = TopbarPlus.new()
		:setEnabled(true)
		:setName("Settings")
		:setImage(100207744901330)
		:setImageScale(0.95)
		:setCaption("View Settings")
		:setOrder(1)
		:align("Left")
		:oneClick(true)

	settingsButton.selected:Connect(function()
		UIController:OpenFrame(displayFrames.Settings)
	end)

	local favoriteIcon = TopbarPlus.new()
		:setEnabled(true)
		:setName("Referall Rewards")
		:setImage(114414259063828)
		:setImageScale(0.65)
		:setCaption("Favorite Game!")
		:setOrder(2)
		:align("Right")
		:oneClick(true)

	favoriteIcon.selected:Connect(function()
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	
	
	local codesIcon = TopbarPlus.new()
		:setEnabled(true)
		:setName("Codes")
		:setImage(77541547944273)
		:setImageScale(0.8)
		:setCaption("Code Rewards!")
		:setOrder(1)
		:align("Right")
		:oneClick(true)

	codesIcon.selected:Connect(function()
		if UIController.CurrentDisplay ~= displayFrames.RobuxShop then
			UIController:OpenFrame(displayFrames.RobuxShop)
		end
		UIController.Controllers.RobuxShopController:ScrollTo(Displays.RobuxShop.Display.ItemsList.CodesFrame)
	end)
end

local function _setupButtons()
	screenElements.Hotbar.InventoryButton.Activated:Connect(function()
		UIController:OpenFrame(displayFrames.Inventory)
	end)
	
	screenElements.LeftOptions.RebirthButton.Activated:Connect(function()
		UIController:OpenFrame(displayFrames.Rebirth)
	end)
	
	screenElements.LeftOptions.IndexButton.Activated:Connect(function()
		UIController.Controllers.IndexController:Open()
	end)

	screenElements.LeftOptions.TeleportButton.Activated:Connect(function()
		UIController.Controllers.TeleportController:Open()
	end)
end

local function _setupCollectionTags()
	for _, button in CollectionService:GetTagged("DisplayClose") do
		(button :: GuiButton).Activated:Connect(function()
			UIController:CloseFrames()
		end)
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function UIController:OpenFrame(frameOrName: Frame | string, animateFrame: boolean?)
	local frame: Frame
	if typeof(frameOrName) == "string" then
		frame = displayFrames[frameOrName]
		if not frame then
			warn("UIController: unknown frame name: " .. frameOrName)
			return
		end
	else
		frame = frameOrName
	end
	

	
	-- Toggle closed if already open
	if self.CurrentDisplay == frame then
		self:CloseFrames()
		return
	end

	if self.CurrentDisplay then
		self.CurrentDisplay.Visible = false
	end

	if animateFrame ~= false then
		local uiScale = frame:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Parent = frame
		end
		uiScale.Scale = 0.5
		Spr.target(uiScale, 0.7, 4, { Scale = 1 })
	end

	frame.Visible = true
	self.CurrentDisplay = frame
	UIsfx.UIOpen:Play()
	
	self:ShowScreenElements(false)
	setFov(90)
	Spr.target(Lighting.Blur, 0.7, 4, { Size = 15 })

	self.Signals.DisplayChanged:Fire(frame)
end

function UIController:CloseFrames()
	if not self.CurrentDisplay then return end

	self.CurrentDisplay.Visible = false
	self.CurrentDisplay = nil
	UIsfx.UIClose:Play()
	
	self:ShowScreenElements(true)
	setFov(70)
	Spr.target(Lighting.Blur, 0.7, 4, { Size = 1 })

	self.Signals.DisplayChanged:Fire(nil)
end


function UIController:SetOverlayOpenSource(sourceName: string, isOpen: boolean)
	if isOpen then
		overlayOpenSources[sourceName] = true
	else
		overlayOpenSources[sourceName] = nil
	end

	applyOverlayOpenState()
end


function UIController:ShowScreenElements(show: boolean)
	local hotbar = screenElements.Hotbar
	local bottomLeft = screenElements.BottomLeft
	local leftOptions = screenElements.LeftOptions
	local statusDisplay = screenElements.ActiveStatusDisplay
	
	if show then
		Spr.target(hotbar, 0.85, 4, { Position = hotbar:GetAttribute("DefaultPosition") })
		Spr.target(bottomLeft, 0.85, 4, { Position = bottomLeft:GetAttribute("DefaultPosition") })
		Spr.target(leftOptions, 0.85, 4, { Position = leftOptions:GetAttribute("DefaultPosition") })
		Spr.target(statusDisplay, 0.85, 4, { Position = statusDisplay:GetAttribute("DefaultPosition") })
	else
		local hotbarPos = hotbar:GetAttribute("DefaultPosition") :: UDim2
		local bottomLeftPos = bottomLeft:GetAttribute("DefaultPosition") :: UDim2
		local leftOptionsPos = leftOptions:GetAttribute("DefaultPosition") :: UDim2
		local statusDisplayPos = statusDisplay:GetAttribute("DefaultPosition") :: UDim2

		Spr.target(hotbar, 0.85, 4, { Position = UDim2.fromScale(hotbarPos.X.Scale, hotbarPos.Y.Scale + 1) })
		Spr.target(bottomLeft, 0.85, 4, { Position = UDim2.fromScale(bottomLeftPos.X.Scale - 1, bottomLeftPos.Y.Scale) })
		Spr.target(leftOptions, 0.85, 4, { Position = UDim2.fromScale(leftOptionsPos.X.Scale - 1, leftOptionsPos.Y.Scale) })
		Spr.target(statusDisplay, 0.85, 4, { Position = UDim2.fromScale(statusDisplayPos.X.Scale + 1, statusDisplayPos.Y.Scale) })
	end
end


--------------------------------------------------
-- MAIN --
--------------------------------------------------

function UIController:Init(controllers)
	self.Controllers = controllers

	_setupTopbar()
	_setupButtons()
	_setupCollectionTags()

	for _, screenElement in screenElements do
		screenElement:SetAttribute("DefaultPosition", screenElement.Position)
	end
	
	if not Lighting:FindFirstChild("Blur") then
		local blur = Instance.new("BlurEffect")
		blur.Size = 0
		blur.Parent = Lighting
	end
	
end

function UIController:Start()
	self.Signals.DisplayChanged:Connect(applyOverlayOpenState)

	player.CharacterRemoving:Connect(function()
		self:CloseFrames()
		self.Controllers.IndexController:Close()
		self:SetOverlayOpenSource("FullRollDisplay", false)
		self:SetOverlayOpenSource("JackpotDisplay", false)
	end)

end


return UIController
