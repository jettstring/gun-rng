local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local RollAssets = GameAssets.RollAssets
local LuckRolls = require(RollAssets.LuckRolls)

local RollUtil = require(ReplicatedStorage.Util.RollUtil)

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type LuckRoll = LuckRolls.LuckRoll

--------------------------------------------------
-- STATE --
--------------------------------------------------
local CloverEffect = {}
CloverEffect.Controllers = {}
CloverEffect.Signals = {}

--------------------------------------------------
-- CONSTANTS --
--------------------------------------------------

local FALL_TIME = 2      -- seconds, top to bottom
local rng = Random.new()

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function createClover(luckRollDef: LuckRoll): ImageLabel
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Size = UDim2.fromScale(0.1, 0.1)
	imageLabel.Position = UDim2.new(0, 0, 0, 0)
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	imageLabel.ZIndex = 1
	imageLabel.BackgroundTransparency = 1
	imageLabel.Parent = playerGui
	
	-- get clover image
	local cloverImage = luckRollDef.displayIcon
	if cloverImage then
		imageLabel.Image = "rbxassetid://" .. cloverImage
	end
	
	local uiAspectRatio = Instance.new("UIAspectRatioConstraint")
	uiAspectRatio.AspectRatio = 1
	uiAspectRatio.Parent = imageLabel

	
	return imageLabel
end

local function render(luckRollDef: LuckRoll)
	local cloverGui = playerGui:FindFirstChild("CloverEffectGui")
	if not cloverGui then
		cloverGui = Instance.new("ScreenGui")
		cloverGui.Name = "CloverEffectGui"
		cloverGui.Parent = playerGui
		cloverGui.IgnoreGuiInset = true
		cloverGui.ResetOnSpawn = false
		cloverGui.DisplayOrder = 2
	end
	
	local emitCount = math.random(20, 30)
	local cloverData = {}
	for i = 1, emitCount do
		local frame = createClover(luckRollDef)
		if frame then
			frame.Parent = cloverGui
			
			local tFall = FALL_TIME * rng:NextNumber(0.85, 1.15)
			
			local data = {
				frame = frame,
				x = rng:NextNumber(0, 1),            -- column
				y = rng:NextNumber(-0.1, 0),         -- staggered just above the top edge
				velY = 0,
				gravity = 2 * 0.75 / (tFall * tFall),
				rot = rng:NextNumber(0, 360),
				rotSpeed = rng:NextNumber(-45, 45),  -- slight spin, deg/s
			}
			frame.Position = UDim2.fromScale(data.x, data.y)
			frame.Rotation = data.rot
			cloverData[i] = data
		end
	end
	
	local conn
	conn = RunService.RenderStepped:Connect(function(deltaTime)
		for i = #cloverData, 1, -1 do
			local c = cloverData[i]
			c.velY += c.gravity * deltaTime
			c.y += c.velY * deltaTime
			c.rot += c.rotSpeed * deltaTime
			c.frame.Position = UDim2.fromScale(c.x, c.y)
			c.frame.Rotation = c.rot

			if c.y > 1.15 then                   -- cleared the bottom
				c.frame:Destroy()
				table.remove(cloverData, i)
			end
		end

		if #cloverData == 0 then
			conn:Disconnect()
		end
	end)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function CloverEffect:Emit(multiplier: number)
	local luckRollDef: LuckRoll = RollUtil.getLuckRollDef(multiplier)
	if not luckRollDef then
		warn("[CloverEffect] No LuckRoll def for multiplier", multiplier)
		return
	end
	render(luckRollDef)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function CloverEffect:Init(controllers)
	self.Controllers = controllers
end

function CloverEffect:Start()
end


return CloverEffect