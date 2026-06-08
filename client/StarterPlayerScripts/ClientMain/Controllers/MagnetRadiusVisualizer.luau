local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local CurrencyAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("CurrencyAssets")
local visualizerTemplate = CurrencyAssets:WaitForChild("MagnetRadiusVisualizer") :: BasePart
local visualizerRotation = visualizerTemplate.CFrame.Rotation
local localPlayer = Players.LocalPlayer

--------------------------------------------------
-- STATE --
--------------------------------------------------

local MagnetRadiusVisualizer = {}
MagnetRadiusVisualizer.Controllers = {}
MagnetRadiusVisualizer.Signals = {}
MagnetRadiusVisualizer.Visualizer = nil :: BasePart?
MagnetRadiusVisualizer.UpdateConnection = nil :: RBXScriptConnection?
MagnetRadiusVisualizer.CharacterConnection = nil :: RBXScriptConnection?

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local MAGNET_RANGE_ATTRIBUTE = "magnetRange"
local VISUALIZER_NAME = "MagnetRadiusVisualizer"
local VISUALIZER_Y = 0
local MIN_VISUALIZER_DIAMETER = 0.05

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function bindCharacter(character: Model)
	if MagnetRadiusVisualizer.Visualizer then
		MagnetRadiusVisualizer.Visualizer:Destroy()
	end

	local oldVisualizer = character:FindFirstChild(VISUALIZER_NAME)
	if oldVisualizer then
		oldVisualizer:Destroy()
	end

	local visualizer = visualizerTemplate:Clone()
	visualizer.Name = VISUALIZER_NAME
	visualizer.Parent = character
	MagnetRadiusVisualizer.Visualizer = visualizer
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function MagnetRadiusVisualizer:Init(controllers)
	self.Controllers = controllers
end

function MagnetRadiusVisualizer:Start()
	self:Stop()

	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end

	self.CharacterConnection = localPlayer.CharacterAdded:Connect(bindCharacter)

	self.UpdateConnection = RunService.RenderStepped:Connect(function()
		local character = localPlayer.Character
		local visualizer = self.Visualizer
		if not character or not visualizer or not visualizer.Parent then
			return
		end

		local rootPart = character.PrimaryPart
		if not rootPart then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
				rootPart = humanoidRootPart
			end
		end

		if not rootPart then
			return
		end

		local magnetRange = localPlayer:GetAttribute(MAGNET_RANGE_ATTRIBUTE)
		if typeof(magnetRange) ~= "number" then
			magnetRange = 0
		end

		local diameter = math.max(MIN_VISUALIZER_DIAMETER, math.max(0, magnetRange) * 2)
		visualizer.Size = Vector3.new(diameter, visualizer.Size.Y, diameter)
		visualizer.CFrame = CFrame.new(rootPart.Position.X, VISUALIZER_Y, rootPart.Position.Z) * visualizerRotation
	end)
end

function MagnetRadiusVisualizer:Stop()
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
		self.CharacterConnection = nil
	end

	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	if self.Visualizer then
		self.Visualizer:Destroy()
		self.Visualizer = nil
	end
end

function MagnetRadiusVisualizer:Destroy()
	self:Stop()
end

return MagnetRadiusVisualizer
