local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local Gigantix = require(ReplicatedStorage.Packages.Gigantix)
local Spring = require(ReplicatedStorage.Packages.Spring)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local enemyRemotes = remotesFolder:WaitForChild("Enemy")
local remotes = {
	DamageEffects = enemyRemotes:WaitForChild("DamageEffects") :: RemoteEvent,
}

--------------------------------------------------
-- TYPES --
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local EnemyEffects = {}
EnemyEffects.Controllers = {}
EnemyEffects.Signals = {}
EnemyEffects.damageEffectsConnection = nil :: RBXScriptConnection?
EnemyEffects.destroyingConnection = nil :: RBXScriptConnection?

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local FLASH_VISIBLE_TRANSPARENCY = 0.5
local FLASH_RESTING_TRANSPARENCY = 1
local FLASH_PEAK_TIME = 0.1
local FLASH_TOTAL_TIME = 0.13
local FLASH_SPRING_FREQUENCY = 30
local FLASH_SPRING_DAMPING_RATIO = 0.9

local HEART_SHRINK_SCALE = 1.1
local HEART_SHRINK_TIME = 0.05
local HEART_BOUNCE_TIME = 0.16
local HEART_SPRING_FREQUENCY = 40
local HEART_SPRING_DAMPING_RATIO = 0.85

local HIT_STROKE_TARGET_BORDER_OFFSET = 0.7
local HIT_STROKE_VISIBLE_TRANSPARENCY = 0.1
local HIT_STROKE_HIDDEN_TRANSPARENCY = 1
local HIT_STROKE_START_COLOR = Color3.fromRGB(255, 101, 104)
local HIT_STROKE_END_COLOR = Color3.fromRGB(255, 255, 255)
local HIT_STROKE_WAVE_TIME = 0.4
local HIT_STROKE_SPRING_FREQUENCY = 12
local HIT_STROKE_SPRING_DAMPING_RATIO = 0.8

local activeHighlightConnections = setmetatable({}, {__mode = "k"}) :: {[Highlight]: RBXScriptConnection}
local activeHeartConnections = setmetatable({}, {__mode = "k"}) :: {[GuiObject]: RBXScriptConnection}
local activeHitStrokeConnections = setmetatable({}, {__mode = "k"}) :: {[UIStroke]: RBXScriptConnection}
local heartOriginalSizes = setmetatable({}, {__mode = "k"}) :: {[GuiObject]: UDim2}
local hitStrokeOriginalOffsets = setmetatable({}, {__mode = "k"}) :: {[UIStroke]: UDim}

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function EnemyEffects:DamageEffects(highlight: Instance?, healthBillboardGui: Instance?, newHealth: number?)
	if highlight and highlight:IsA("Highlight") and highlight.Parent then
		local typedHighlight = highlight :: Highlight
		local existingConnection = activeHighlightConnections[typedHighlight]
		if existingConnection then
			existingConnection:Disconnect()
			activeHighlightConnections[typedHighlight] = nil
		end

		local fillSpring = Spring.new(
			typedHighlight.FillTransparency,
			0,
			FLASH_VISIBLE_TRANSPARENCY,
			FLASH_SPRING_FREQUENCY,
			FLASH_SPRING_DAMPING_RATIO
		)
		local outlineSpring = Spring.new(
			typedHighlight.OutlineTransparency,
			0,
			FLASH_VISIBLE_TRANSPARENCY,
			FLASH_SPRING_FREQUENCY,
			FLASH_SPRING_DAMPING_RATIO
		)
		local elapsed = 0
		local isReturning = false

		activeHighlightConnections[typedHighlight] = RunService.Heartbeat:Connect(function(deltaTime: number)
			if not typedHighlight.Parent then
				local connection = activeHighlightConnections[typedHighlight]
				if connection then
					connection:Disconnect()
					activeHighlightConnections[typedHighlight] = nil
				end
				return
			end

			fillSpring:update(deltaTime)
			outlineSpring:update(deltaTime)
			typedHighlight.FillTransparency = math.clamp(fillSpring.p, 0, 1)
			typedHighlight.OutlineTransparency = math.clamp(outlineSpring.p, 0, 1)

			elapsed += deltaTime
			if not isReturning and elapsed >= FLASH_PEAK_TIME then
				isReturning = true
				fillSpring.target = FLASH_RESTING_TRANSPARENCY
				outlineSpring.target = FLASH_RESTING_TRANSPARENCY
			end

			if elapsed >= FLASH_TOTAL_TIME then
				typedHighlight.FillTransparency = FLASH_RESTING_TRANSPARENCY
				typedHighlight.OutlineTransparency = FLASH_RESTING_TRANSPARENCY

				local connection = activeHighlightConnections[typedHighlight]
				if connection then
					connection:Disconnect()
					activeHighlightConnections[typedHighlight] = nil
				end
			end
		end)
	end
	--if true then return end
	if not healthBillboardGui or not healthBillboardGui:IsA("BillboardGui") or not healthBillboardGui.Parent then
		return
	end

	local typedBillboardGui = healthBillboardGui :: BillboardGui
	local healthMeter = typedBillboardGui:FindFirstChild("HealthMeter", true)
	if not healthMeter then
		return
	end

	if typeof(newHealth) == "number" then
		local safeHealth = math.max(0, newHealth)
		local maxHealth = typedBillboardGui:GetAttribute("MaxHealth")
		if typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			local enemyModel = typedBillboardGui:FindFirstAncestorOfClass("Model")
			local humanoid = if enemyModel then enemyModel:FindFirstChildWhichIsA("Humanoid") else nil
			maxHealth = if humanoid then math.max(1, humanoid.MaxHealth) else math.max(1, safeHealth)
		end

		local healthRatio = math.clamp(safeHealth / maxHealth, 0, 1)
		typedBillboardGui:SetAttribute("Health", safeHealth)

		local fill = healthMeter:FindFirstChild("Fill")
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(1, 1)

			local fillGradient = fill:FindFirstChild("FillGradient")
			if fillGradient and fillGradient:IsA("UIGradient") then
				if healthRatio <= 0 then
					fillGradient.Transparency = NumberSequence.new(1)
				elseif healthRatio >= 1 then
					fillGradient.Transparency = NumberSequence.new(0)
				else
					local edgeEnd = math.min(healthRatio + 0.001, 1)
					fillGradient.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(healthRatio, 0),
						NumberSequenceKeypoint.new(edgeEnd, 1),
						NumberSequenceKeypoint.new(1, 1),
					})
				end
			else
				fill.Size = UDim2.fromScale(healthRatio, 1)
			end
		end

		local amountLabel = healthMeter:FindFirstChild("AmountLabel")
		if amountLabel and amountLabel:IsA("TextLabel") then
			local roundedHealth = math.max(0, math.floor(safeHealth + 0.5))
			local roundedMaxHealth = math.max(0, math.floor(maxHealth + 0.5))
			local healthText = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundedHealth)))
			local maxHealthText = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundedMaxHealth)))
			amountLabel.Text = `{healthText}/{maxHealthText}`
		end
	end

	--local heart = healthMeter:FindFirstChild("Heart")
	--if heart and heart:IsA("GuiObject") then
	--	local originalSize = heartOriginalSizes[heart] or heart.Size
	--	local existingConnection = activeHeartConnections[heart]
	--	if existingConnection then
	--		existingConnection:Disconnect()
	--		activeHeartConnections[heart] = nil
	--	end

	--	heartOriginalSizes[heart] = originalSize
	--	heart.Size = originalSize

	--	local scaleSpring = Spring.new(1, 0, HEART_SHRINK_SCALE, HEART_SPRING_FREQUENCY, HEART_SPRING_DAMPING_RATIO)
	--	local elapsed = 0
	--	local isReturning = false

	--	activeHeartConnections[heart] = RunService.Heartbeat:Connect(function(deltaTime: number)
	--		if not heart.Parent then
	--			local connection = activeHeartConnections[heart]
	--			if connection then
	--				connection:Disconnect()
	--				activeHeartConnections[heart] = nil
	--			end
	--			heartOriginalSizes[heart] = nil
	--			return
	--		end

	--		scaleSpring:update(deltaTime)
	--		heart.Size = UDim2.new(
	--			originalSize.X.Scale * scaleSpring.p,
	--			originalSize.X.Offset * scaleSpring.p,
	--			originalSize.Y.Scale * scaleSpring.p,
	--			originalSize.Y.Offset * scaleSpring.p
	--		)

	--		elapsed += deltaTime
	--		if not isReturning and elapsed >= HEART_SHRINK_TIME then
	--			isReturning = true
	--			scaleSpring.target = 1
	--		end

	--		if elapsed >= HEART_BOUNCE_TIME then
	--			heart.Size = originalSize

	--			local connection = activeHeartConnections[heart]
	--			if connection then
	--				connection:Disconnect()
	--				activeHeartConnections[heart] = nil
	--			end
	--			heartOriginalSizes[heart] = nil
	--		end
	--	end)
	--end

	local hitStroke = healthMeter:FindFirstChild("HitStroke")
	if hitStroke and hitStroke:IsA("UIStroke") then
		local originalBorderOffset = hitStrokeOriginalOffsets[hitStroke] or hitStroke.BorderOffset
		local existingConnection = activeHitStrokeConnections[hitStroke]
		if existingConnection then
			existingConnection:Disconnect()
			activeHitStrokeConnections[hitStroke] = nil
		end

		hitStrokeOriginalOffsets[hitStroke] = originalBorderOffset
		hitStroke.BorderOffset = originalBorderOffset
		hitStroke.Transparency = HIT_STROKE_VISIBLE_TRANSPARENCY
		hitStroke.Color = HIT_STROKE_START_COLOR

		local borderOffsetSpring = Spring.new(
			originalBorderOffset.Scale,
			0,
			HIT_STROKE_TARGET_BORDER_OFFSET,
			HIT_STROKE_SPRING_FREQUENCY,
			HIT_STROKE_SPRING_DAMPING_RATIO
		)
		local transparencySpring = Spring.new(
			HIT_STROKE_VISIBLE_TRANSPARENCY,
			0,
			HIT_STROKE_HIDDEN_TRANSPARENCY,
			HIT_STROKE_SPRING_FREQUENCY,
			HIT_STROKE_SPRING_DAMPING_RATIO
		)
		local colorSpring = Spring.new(
			0,
			0,
			1,
			HIT_STROKE_SPRING_FREQUENCY,
			HIT_STROKE_SPRING_DAMPING_RATIO
		)
		local elapsed = 0

		activeHitStrokeConnections[hitStroke] = RunService.Heartbeat:Connect(function(deltaTime: number)
			if not hitStroke.Parent then
				local connection = activeHitStrokeConnections[hitStroke]
				if connection then
					connection:Disconnect()
					activeHitStrokeConnections[hitStroke] = nil
				end
				hitStrokeOriginalOffsets[hitStroke] = nil
				return
			end

			borderOffsetSpring:update(deltaTime)
			transparencySpring:update(deltaTime)
			colorSpring:update(deltaTime)
			hitStroke.BorderOffset = UDim.new(borderOffsetSpring.p, originalBorderOffset.Offset)
			hitStroke.Transparency = math.clamp(transparencySpring.p, 0, 1)
			hitStroke.Color = HIT_STROKE_START_COLOR:Lerp(HIT_STROKE_END_COLOR, math.clamp(colorSpring.p, 0, 1))

			elapsed += deltaTime
			if elapsed >= HIT_STROKE_WAVE_TIME then
				hitStroke.BorderOffset = originalBorderOffset
				hitStroke.Transparency = HIT_STROKE_HIDDEN_TRANSPARENCY
				hitStroke.Color = HIT_STROKE_END_COLOR

				local connection = activeHitStrokeConnections[hitStroke]
				if connection then
					connection:Disconnect()
					activeHitStrokeConnections[hitStroke] = nil
				end
				hitStrokeOriginalOffsets[hitStroke] = nil
			end
		end)
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function EnemyEffects:Init(controllers)
	self.Controllers = controllers
end

function EnemyEffects:Start()
	if self.damageEffectsConnection then
		self.damageEffectsConnection:Disconnect()
		self.damageEffectsConnection = nil
	end

	self.damageEffectsConnection = remotes.DamageEffects.OnClientEvent:Connect(function(highlight: Instance?, healthBillboardGui: Instance?, newHealth: number?)
		self:DamageEffects(highlight, healthBillboardGui, newHealth)
	end)

	if not self.destroyingConnection then
		self.destroyingConnection = script.Destroying:Connect(function()
			if self.damageEffectsConnection then
				self.damageEffectsConnection:Disconnect()
				self.damageEffectsConnection = nil
			end

			for highlight, connection in activeHighlightConnections do
				connection:Disconnect()
				activeHighlightConnections[highlight] = nil
			end

			for heart, connection in activeHeartConnections do
				connection:Disconnect()
				activeHeartConnections[heart] = nil
				heartOriginalSizes[heart] = nil
			end

			for hitStroke, connection in activeHitStrokeConnections do
				connection:Disconnect()
				activeHitStrokeConnections[hitStroke] = nil
				hitStrokeOriginalOffsets[hitStroke] = nil
			end

			if self.destroyingConnection then
				self.destroyingConnection:Disconnect()
				self.destroyingConnection = nil
			end
		end)
	end
end

return EnemyEffects
