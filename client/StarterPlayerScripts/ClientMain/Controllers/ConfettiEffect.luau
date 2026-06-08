local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

--------------------------------------------------
-- STATE --
--------------------------------------------------
local ConfettiEffect = {}
ConfettiEffect.Controllers = {}
ConfettiEffect.Signals = {}

local activeConfettiTrove = Trove.new()

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function createConfettiFrame(): Frame
	local confettiFrame = Instance.new("Frame")
	confettiFrame.Size = UDim2.new(0, 0, 0, 0)
	confettiFrame.Position = UDim2.new(0, 0, 0, 0)
	confettiFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	confettiFrame.BorderSizePixel = 0
	confettiFrame.ZIndex = 1
	confettiFrame.Parent = playerGui
	
	local colors = {
		Color3.fromRGB(255, 32, 62),
		Color3.fromRGB(255, 127, 0),
		Color3.fromRGB(255, 255, 0),
		Color3.fromRGB(0, 255, 0),
		Color3.fromRGB(64, 223, 255),
		Color3.fromRGB(232, 102, 255)
	}
	confettiFrame.BackgroundColor3 = colors[math.random(1, #colors)]
	
	local uiAspectRatio = Instance.new("UIAspectRatioConstraint")
	uiAspectRatio.Parent = confettiFrame
	uiAspectRatio.AspectRatio = Random.new():NextNumber(0.4, 0.6)
	
	
	return confettiFrame
end

local function render(length: number)
	activeConfettiTrove:Clean()
	
	local confettiGui = Instance.new("ScreenGui")
	confettiGui.Name = "ConfettiEffectGui"
	confettiGui.Parent = playerGui
	confettiGui.IgnoreGuiInset = true
	confettiGui.ResetOnSpawn = false
	
	
	local emitCount = math.random(100, 120)
	local riseTime = length * Random.new():NextNumber(0.2, 0.3)
	local riseSpeed = 1 / riseTime
	
	-- create confetti frames
	local confettiFrames = {}
	for i = 1, emitCount do
		local confettiFrame = createConfettiFrame()
		confettiFrames[i] = confettiFrame
		confettiFrame.Parent = confettiGui
		activeConfettiTrove:Add(confettiFrame)
	end
	
	activeConfettiTrove:Add(RunService.RenderStepped, function(deltaTime)
		
	end)
	
	
	
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ConfettiEffect:Emit(length: number)
	if not length then warn("ConfettiEffect:Emit() requires a length argument") return end
	render(length)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ConfettiEffect:Init(controllers)
	self.Controllers = controllers

end

function ConfettiEffect:Start()

end


return ConfettiEffect