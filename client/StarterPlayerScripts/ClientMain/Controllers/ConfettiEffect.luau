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
-- CONSTANTS --
--------------------------------------------------
local TERMINAL_FALL = 0.15  -- feather drift speed (scale units / second)
local FALL_DAMP = 2.0       -- how fast velocity eases to terminal (higher = snappier)
local SWAY_AMP = 0.04   -- max horizontal drift, scale units
local SWAY_FREQ = 1.5   -- base flutter speed
local rng = Random.new()

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
	
	return confettiFrame
end

local function render(length: number)
	activeConfettiTrove:Clean()
	
	local confettiGui = Instance.new("ScreenGui")
	confettiGui.Name = "ConfettiEffectGui"
	confettiGui.Parent = playerGui
	confettiGui.IgnoreGuiInset = true
	confettiGui.ResetOnSpawn = false
	confettiGui.DisplayOrder = 2
	
	
	local emitCount = math.random(100, 120)
	local riseTime = Random.new():NextNumber(0.2, 0.3)
	local riseSpeed = 1 / riseTime
	
	-- create confetti frames
	local confettiData = {}
	for i = 1, emitCount do
		local confettiFrame = createConfettiFrame()
		confettiFrame.Size = UDim2.fromScale(rng:NextNumber(0.005, 0.011), rng:NextNumber(0.05, 0.08))
		confettiFrame.Parent = confettiGui
		activeConfettiTrove:Add(confettiFrame)

		local startY = 1.05                              -- just below the bottom edge
		local peakY = rng:NextNumber(0.45, 0.7)          -- target apex
		local tRise = length * rng:NextNumber(0.1, 0.35)  -- time to reach the apex
		local rise = startY - peakY                      -- distance to climb

		-- decelerate from v0 to exactly 0 at the apex, arriving at tRise
		local v0 = 2 * rise / tRise
		local gravity = v0 / tRise

		local data = {
			frame = confettiFrame,
			baseX = rng:NextNumber(0.05, 0.95),  -- the column it rises in
			y = startY,
			velY = -v0,
			gravity = gravity,
			terminalFall = TERMINAL_FALL * rng:NextNumber(0.7, 1),  -- rolled once, per confetti

			-- flutter: per-frame variation so they don't sway in lockstep
			swayAmp = SWAY_AMP * rng:NextNumber(0.6, 1.4),
			swayFreq = SWAY_FREQ * rng:NextNumber(0.7, 1.3),
			swayPhase = rng:NextNumber(0, math.pi * 2),

			-- tumble
			rot = rng:NextNumber(0, 360),
			rotSpeed = rng:NextNumber(-180, 180),  -- degrees/sec, signed = both directions
		}
		confettiFrame.Position = UDim2.new(data.baseX, 0, data.y, 0)
		confettiData[i] = data
	end
	
	local elapsed = 0
	activeConfettiTrove:Connect(RunService.RenderStepped, function(deltaTime)
		elapsed += deltaTime
		for _, c in confettiData do
			if c.velY < 0 then
				c.velY += c.gravity * deltaTime          -- rise: decelerate
			else
				c.velY = c.terminalFall + (c.velY - c.terminalFall) * math.exp(-FALL_DAMP * deltaTime)
			end
			c.y += c.velY * deltaTime

			local swayX = math.sin(elapsed * c.swayFreq + c.swayPhase) * c.swayAmp
			c.rot += c.rotSpeed * deltaTime

			c.frame.Position = UDim2.new(c.baseX + swayX, 0, c.y, 0)
			c.frame.Rotation = c.rot
		end
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