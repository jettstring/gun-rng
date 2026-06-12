local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Spr = require(ReplicatedStorage.Modules.Spr)
local Satchel = require(ReplicatedStorage.Modules.SatchelLoader.Satchel)


local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local camera = workspace.CurrentCamera

local PromptEffect = {}
PromptEffect.__index = PromptEffect

function PromptEffect.new()
	local self = setmetatable({}, PromptEffect)
	
	self.Trove = Trove.new()
	
	local effectGui = script:WaitForChild("EffectGui")
	if not effectGui then return nil end
	
	return self
end

function PromptEffect:Start()
	local effectGui = script:WaitForChild("EffectGui"):Clone()
	effectGui.Parent = playerGui 
	self.Trove:Add(effectGui)
	
	local backgroundTint = effectGui:WaitForChild("BackgroundTint")
	local spotlightCircle = effectGui:WaitForChild("SpotlightGlow")
	local promptGlow = effectGui:WaitForChild("PromptGlow")
	
	-- Animate background tint
	local gradient = backgroundTint:WaitForChild("UIGradient")
	self.Trove:Connect(RunService.RenderStepped, function(deltaTime: number)
		gradient.Rotation = (gradient.Rotation + 90 * deltaTime) % 360
	end)
	
	
	-- Animate Glow
	task.spawn(function()
		promptGlow.ImageTransparency = 1
		local promptFadeInTween = TweenService:Create(promptGlow, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false), {
			ImageTransparency = 0.05
		})
		promptFadeInTween:Play()
		promptFadeInTween.Completed:Wait()
		
		local promptGlowTween = TweenService:Create(promptGlow, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true), {
			ImageTransparency = 0.8
		})
		promptGlowTween:Play()
	end)
	
	-- Animate spotlight Circle
	local firstIteration = true
	self.Trove:Add(task.spawn(function()
		while true do
			-- Pick side + offset within that side
			local side = math.random(0, 1)
			local randomX = side * 0.7 + math.random() * 0.3

			-- Snap start state
			spotlightCircle.Position = UDim2.fromScale(randomX, 1.3)
			spotlightCircle.Size = UDim2.fromScale(0.3, 0.3)
			spotlightCircle.ImageTransparency = 0.85

			local duration = firstIteration and 4 or 1

			local spotlightTween = TweenService:Create(spotlightCircle, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Position = UDim2.fromScale(0.5, 0.5),
				Size  = UDim2.fromScale(0.1, 0.1)
			})
		
			local transparencyTween = TweenService:Create(spotlightCircle, TweenInfo.new(firstIteration and 5.5 or 1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = (firstIteration and 0.5 or 0.8),
			})

			spotlightTween:Play()
			transparencyTween:Play()
			spotlightTween.Completed:Wait()
			
			firstIteration = false
			task.wait(0.5) -- pause before next spotlight; tune or remove
		end
	end))
	
	-- Hide backpack
	local backpackEnabled = Satchel:GetBackpackEnabled()
	if backpackEnabled then
		Satchel:SetBackpackEnabled(false)
		self.Trove:Add(function()
			Satchel:SetBackpackEnabled(backpackEnabled)
		end)
	end
	
	-- Blur 
	local blur = Lighting:FindFirstChild("PromptBlur")
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "PromptBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	Spr.target(blur, 0.7, 4, { Size = 10 })
	self.Trove:Add(function()
		Spr.target(blur, 0.7, 4, { Size = 0 })
	end)

	-- Fov zoom in
	local previousFov = camera.FieldOfView
	local fovTween = TweenService:Create(camera, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = 55
	})
	fovTween:Play()
	self.Trove:Add(function()
		fovTween:Cancel()
		Spr.target(camera, 0.8, 4, { FieldOfView = previousFov })
	end)
	
	-- reduce background music
	local musicGroup = SoundService:FindFirstChild("BackgroundMusic")
	if musicGroup and musicGroup.Volume > 0 then
		local previousVolume = musicGroup.Volume
		local volumeTween = TweenService:Create(musicGroup, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = 0.05
		})
		volumeTween:Play()
		self.Trove:Add(function()
			volumeTween:Cancel()
			Spr.target(musicGroup, 0.7, 4, { Volume = previousVolume })
		end)
	end
	
end

function PromptEffect:Destroy()
	self.Trove:Destroy()
end

return PromptEffect
