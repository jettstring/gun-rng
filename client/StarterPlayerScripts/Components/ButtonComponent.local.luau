
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

-- Wait for Spr module
local Spr = require(ReplicatedStorage.Packages.Spr)

local DownTag = "ButtonDown"
local UpTag = "ButtonUp"

-- Track button instances and their connections
local buttonInstances = {}
local connectionsByButton = {}

-- Button effect configuration
local HOVER_SCALE_DOWN = 0.92
local CLICK_SCALE_DOWN = 0.85
local ANIMATION_DURATION = 0.6
local ANIMATION_EASING = 4

-- Button effect configuration
local HOVER_SCALE_UP = 1.1
local CLICK_SCALE_UP =1.13

-- Sound configuration
local UISounds = SoundService.SFX:WaitForChild("UI")
local SOUND_CONFIG = {
	Hover = UISounds.UIHover,
	Down = UISounds.UIDown, 
	Up = UISounds.UIUp
}

-- Helper function to get or create UIScale
local function getOrCreateUIScale(instance: GuiObject): UIScale
	local uiScale = instance:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = instance
	end
	return uiScale
end

-- Cleanup function for a button
local function cleanupButton(button: GuiObject)
	if connectionsByButton[button] then
		for _, connection in pairs(connectionsByButton[button]) do
			pcall(function()
				connection:Disconnect()
			end)
		end
		connectionsByButton[button] = nil
	end

	buttonInstances[button] = nil
end

-- Setup button effects for a single button instance
local function setupButton(button: GuiObject)
	if buttonInstances[button] then
		return -- Already set up
	end
	
	local HOVER_SCALE
	local CLICK_SCALE 
	
	if button:HasTag(DownTag) then
		HOVER_SCALE = HOVER_SCALE_DOWN
		CLICK_SCALE = CLICK_SCALE_DOWN
	elseif button:HasTag(UpTag) then
		HOVER_SCALE = HOVER_SCALE_UP
		CLICK_SCALE = CLICK_SCALE_UP
	end
	
	-- Validate that this is a proper GUI object
	if not button:IsA("GuiButton") and not button:IsA("TextButton") and not button:IsA("ImageButton") then
		warn("Button tag applied to non-button GUI object:", button.Name)
		return
	end
	
	buttonInstances[button] = true
	connectionsByButton[button] = {}
	
	local uiScale = getOrCreateUIScale(button)
	local hovering = false
	
	-- Mouse enter effect
	local mouseEnterConnection = button.MouseEnter:Connect(function()
		hovering = true
		
		Spr.target(uiScale, ANIMATION_DURATION, ANIMATION_EASING, {
			Scale = HOVER_SCALE
		})
		
		SOUND_CONFIG["Hover"]:Play()
	end)
	
	-- Mouse leave effect
	local mouseLeaveConnection = button.MouseLeave:Connect(function()
		hovering = false
		
		Spr.target(uiScale, ANIMATION_DURATION, ANIMATION_EASING, {
			Scale = 1
		})
		SOUND_CONFIG["Hover"]:Play()
	end)
	
	-- Click effect
	local activatedConnection = button.Activated:Connect(function()
		-- Immediate click down effect
		Spr.target(uiScale, ANIMATION_DURATION, ANIMATION_EASING, {
			Scale = CLICK_SCALE
		})
		
		SOUND_CONFIG["Down"]:Play()
		
		-- Wait briefly then return to hover state
		task.wait(0.1)
		
		SOUND_CONFIG["Up"]:Play()
		
		Spr.target(uiScale, ANIMATION_DURATION, ANIMATION_EASING, {
			Scale = hovering and HOVER_SCALE or 1
		})
	end)
	
	-- Store connections for cleanup
	table.insert(connectionsByButton[button], mouseEnterConnection)
	table.insert(connectionsByButton[button], mouseLeaveConnection)
	table.insert(connectionsByButton[button], activatedConnection)
	
	-- Cleanup when button is removed
	local ancestryConnection = button.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupButton(button)
		end
	end)
	table.insert(connectionsByButton[button], ancestryConnection)
end



-- Initialize existing tagged buttons
for _, button in ipairs(CollectionService:GetTagged(DownTag)) do
	if button:IsA("GuiObject") then
		setupButton(button)
	end
end
for _, button in ipairs(CollectionService:GetTagged(UpTag)) do
	if button:IsA("GuiObject") then
		setupButton(button)
	end
end

-- Handle new buttons being tagged
CollectionService:GetInstanceAddedSignal(DownTag):Connect(function(button)
	if button:IsA("GuiObject") then
		setupButton(button)
	end
end)
-- Handle buttons being untagged
CollectionService:GetInstanceRemovedSignal(DownTag):Connect(function(button)
	cleanupButton(button)
end)


-- Handle new buttons being tagged
CollectionService:GetInstanceAddedSignal(UpTag):Connect(function(button)
	if button:IsA("GuiObject") then
		setupButton(button)
	end
end)
-- Handle buttons being untagged
CollectionService:GetInstanceRemovedSignal(UpTag):Connect(function(button)
	cleanupButton(button)
end)

