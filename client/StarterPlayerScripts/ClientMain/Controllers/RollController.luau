local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Spr = require(ReplicatedStorage.Packages.Spr)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local RollingGui = playerGui:WaitForChild("RollingGui")
local fullRollDisplay = RollingGui:WaitForChild("FullRollDisplay")
local rollOptions = fullRollDisplay:WaitForChild("RollOptions")
local autoButton = rollOptions:WaitForChild("AutoButton")
local hideButton = rollOptions:WaitForChild("HideButton")
local rollColumnsContainer = fullRollDisplay.Container:WaitForChild("RollColumnsContainer")
local miniRollDisplay = RollingGui:WaitForChild("MiniRollDisplay")
local rewardFrameTemplates = rollColumnsContainer.UIListLayout.RewardFrames
--..
local jackpotDisplay = RollingGui:WaitForChild("JackpotDisplay")
--..
local ScreenElements = playerGui:WaitForChild("ScreenElements")
local hotbarFrame = ScreenElements:WaitForChild("Hotbar")
local rollButton = hotbarFrame:WaitForChild("RollButton")
local specialRollsFrame = rollButton:WaitForChild("SpecialRollsFrame")


local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local WeaponAssets = GameAssets.WeaponAssets
local WeaponDefinitions = require(WeaponAssets.WeaponDefinitions)

local RollAssets = GameAssets.RollAssets
local LuckRolls = require(RollAssets.LuckRolls)
local SpecialRollDefinitions = require(RollAssets.SpecialRollDefinitions)

local ItemDefinitions = require(GameAssets.ItemAssets.ItemDefinitions)

local RollUtil = require(ReplicatedStorage.Util.RollUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)

local SFX = SoundService:WaitForChild("SFX")
local RollSFX = SFX:WaitForChild("Rolling")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	AttemptRoll = remotesFolder.Roll:WaitForChild("AttemptRoll"),
	RollResult = remotesFolder.Roll:WaitForChild("RollResult"),
	ToggleAutoRoll = remotesFolder.Roll:WaitForChild("ToggleAutoRoll"),
	PauseSpecialRoll = remotesFolder.Roll:WaitForChild("PauseSpecialRoll"),
	RollingDataUpdated = remotesFolder.Roll:WaitForChild("RollingDataUpdated"),
	
	-- RFs
	GetAutoRollState = remotesFolder.Roll:WaitForChild("GetAutoRollState"),
	GetRollingData = remotesFolder.Roll:WaitForChild("GetRollingData")
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type ItemDefinition = ItemDefinitions.ItemDefinition
type DiceDefinition = ItemDefinitions.DiceDefinition

type ColumnResults = RollUtil.ColumnResults
type RollResult = RollUtil.RollResult
type RollData = RollUtil.RollData
type LuckRoll = LuckRolls.LuckRoll
type JackpotResult = RollUtil.JackpotResult

type SpecialRoll = SpecialRollDefinitions.SpecialRoll

--------------------------------------------------
-- STATE --
--------------------------------------------------
local RollController = {}
RollController.Controllers = {}
RollController.Signals = {}

RollController.RollDisplayView = "Mini"
RollController.Rolling = false
RollController.AutoRolling = false

local ActiveRollTrove = Trove.new()

local RotateConnection: RBXScriptConnection? = nil
local skipButtonConnection: RBXScriptConnection? = nil

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function generateFillerRewards(rollData: RollData, rollResult: RollResult): {RollResult}
	local rollLuck = rollData.playerLuck or 1
	local rollResultType = rollResult.type
	local effectiveRollData = RollUtil.getEffectiveRollData(rollData, rollLuck)
	
	local fillerRewards = {}
	for i = 1, 9 do
		fillerRewards[i] = RollUtil.rollWeaponResult(effectiveRollData)
	end
	
	return fillerRewards
end

local function createRewardFrame(rewardData: RollResult): Frame
	if rewardData.type == "Weapon" then
		local rewardFrame = rewardFrameTemplates.Weapon:Clone()
		
		local nameLabel = rewardFrame:FindFirstChild("NameLabel")
		local oddsLabel = rewardFrame:FindFirstChild("OddsLabel")
		local iconLabel = rewardFrame:FindFirstChild("WeaponIconContainer")
		
		local weaponName = rewardData.weaponName
		local weaponDef = WeaponUtil.getWeaponDefinition(rewardData.weaponName)
		if not weaponDef then warn("No weapon definition for", rewardData.weaponName) return end
		
		local rarity = WeaponUtil.deriveRarity(rewardData.weaponName, rewardData.mutations)

		nameLabel.Text = WeaponUtil.getWeaponName(rewardData.weaponName, rewardData.mutations)
		oddsLabel.Text = "1 /" .. math.round(1 / weaponDef.odds)
		iconLabel.Image =  ""
		
		local weaponImageLabel = WeaponUtil.getDisplayImageLabel(rewardData.weaponName, rewardData.mutations)
		if weaponImageLabel then
			weaponImageLabel.Parent = iconLabel
		end
		
		WeaponUtil.applyRarityTextEffects(oddsLabel, rarity)
		
		return rewardFrame
	elseif rewardData.type == "Spin" then
		local rewardFrame = rewardFrameTemplates.Spin:Clone()
		
		return rewardFrame
	elseif rewardData.type == "RollLuck" then
		local rewardFrame = rewardFrameTemplates.RollLuck:Clone()
		local multiplierLabel = rewardFrame:FindFirstChild("MultiplierLabel")
		
		local multiplier = rewardData.rollLuckMultiplier or 1
		local luckRollDef: LuckRoll = RollUtil.getLuckRollDef(multiplier)
		if not luckRollDef then
			warn("[createRewardFrame] No LuckRoll def for multiplier", multiplier)
			return
		end
		
		multiplierLabel.Text = "x" .. multiplier
		
		local displayIcon = luckRollDef.displayIcon
		if displayIcon then
			rewardFrame.Icon.Image = "rbxassetid://" .. displayIcon
		end

		local gradient = luckRollDef.displayGradient:Clone()
		if gradient then
			if multiplierLabel:FindFirstChildWhichIsA("UIGradient") then
				multiplierLabel:FindFirstChildWhichIsA("UIGradient"):Destroy()
			end
			
			gradient.Parent = multiplierLabel
		end
		
		return rewardFrame
	end
end

local function displayJackpotSpin(rollData: RollData, jackpotResults: {[number]: JackpotResult})
	if not rollData or not jackpotResults or not next(jackpotResults) then return end
	
	RollController.Controllers.UIController:SetOverlayOpenSource("JackpotDisplay", true)
	RollController.Controllers.UIController:CloseFrames()
	RollController.Controllers.UIController:ShowScreenElements(false)
	
	local wheelContainer = jackpotDisplay:WaitForChild("Container")
	local skipDisplay = jackpotDisplay:WaitForChild("SkipDisplay")
	local skipButton = skipDisplay:WaitForChild("SkipButton")
	local keyHint = skipButton:WaitForChild("KeyHint")
	local timerLabel = skipButton:WaitForChild("TimerLabel")
	local jackpotWheelTemplate = wheelContainer:WaitForChild("JackpotWheel")
	jackpotWheelTemplate.Visible = false
	jackpotDisplay.Visible = true
	skipDisplay.Visible = true

	Spr.target(skipDisplay, 0.7, 4, {
		Position = UDim2.new(0.5, 0, 1, 0),
	})
	
	for _, inputLabel in keyHint:GetChildren() do
		if not inputLabel:IsA("ImageLabel") then continue end
		if inputLabel.Name ~= UserInputService.PreferredInput.Name then
			inputLabel.Visible = false
		else
			inputLabel.Visible = true
		end
	end

	-- Time budget
	local jackpotTime          = RollUtil.CONFIGS.JACKPOT_ROLL_TIME
	local REWARD_DISPLAY_TIME  = jackpotTime * 0.2
	local FULL_SPIN_MAX_TIME   = jackpotTime * 0.4
	local SPIN_WINDOW          = jackpotTime - REWARD_DISPLAY_TIME  -- full + reveal combined

	local FULL_SPIN_RPS            = 3   -- revolutions/sec during full-speed phase
	local MIN_REVEAL_REVOLUTIONS   = 2   -- extra full rotations baked into the reveal slowdown
	local MIN_REVEAL_DURATION      = 0.4 -- safety floor if skipped extremely late

	local wheelSlices = 6
	local sliceAngle  = 360 / wheelSlices

	-- Shared phase state across all wheels (they all spin together, skip affects them all)
	local skipSignaled    = false
	local phaseStartClock = os.clock()

	local function elapsedFullSpin(): number
		return os.clock() - phaseStartClock
	end

	local function shouldStartReveal(): boolean
		return skipSignaled or elapsedFullSpin() >= FULL_SPIN_MAX_TIME
	end

	-- Countdown label + auto-hide skip UI once reveal starts
	ActiveRollTrove:Add(RunService.RenderStepped:Connect(function()
		if shouldStartReveal() then
			Spr.target(skipDisplay, 0.7, 4, {
				Position = UDim2.new(0.5, 0, 1.5, 0),
			})
			timerLabel.Text = ""
		else
			local remaining = math.max(0, FULL_SPIN_MAX_TIME - elapsedFullSpin())
			timerLabel.Text = string.format("%.1f", remaining)
		end
	end))

	for _, jackpotResult: JackpotResult in jackpotResults do
		local wheel = jackpotWheelTemplate:Clone()
		ActiveRollTrove:Add(wheel)
		wheel.Visible = true
		wheel.Parent = wheelContainer
		
		local beamsLabel = wheel:WaitForChild("Beams")
		local selectorArrow = wheel:WaitForChild("SelectorArrow")
		selectorArrow.Rotation = 0
		
		-- Track previous rotation to detect slice crossings
		local lastRotation = 0
		local lastSliceIndex = 0

		local rewardsContainer = wheel:WaitForChild("RewardsContainer")
		for _, slot in rewardsContainer:GetChildren() do
			if slot:IsA("Frame") and slot:FindFirstChildOfClass("Frame") then
				slot:FindFirstChildOfClass("Frame"):Destroy()
			end
		end

		-- Build rewards (filler + landing)
		local rewards = {}
		local landingIndex = math.random(1, wheelSlices)
		for _ = 1, (wheelSlices - 1) do
			table.insert(rewards, RollUtil.rollJackpotWeapon(rollData))
		end
		table.insert(rewards, landingIndex, jackpotResult)

		-- Clone reward frames
		local rewardFrames = {}
		for i, rewardData: JackpotResult in rewards do
			local template = jackpotDisplay.Container.UIListLayout.RewardFrames:FindFirstChild("Weapon")
			if not template then warn("[displayJackpotSpin] No reward frame") continue end

			local frame = template:Clone()
			frame.Visible = true
			frame.Parent = rewardsContainer:FindFirstChild(tostring(i))
			table.insert(rewardFrames, frame)

			local nameLabel = frame:FindFirstChild("NameLabel")
			local oddsLabel = frame:FindFirstChild("OddsLabel")
			local iconLabel = frame:FindFirstChild("Icon")

			local weaponDef = WeaponUtil.getWeaponDefinition(rewardData.weaponName)
			if not weaponDef then warn("No weapon definition for", rewardData.weaponName) continue end

			nameLabel.Text = rewardData.weaponName
			oddsLabel.Text = "1 /" .. math.round(1 / weaponDef.odds)
			
			local weaponImageLabel = WeaponUtil.getDisplayImageLabel(rewardData.weaponName, rewardData.mutations)
			if weaponImageLabel then
				weaponImageLabel.Parent = iconLabel
			end
			
			
			WeaponUtil.applyRarityTextEffects(oddsLabel, WeaponUtil.deriveRarity(rewardData.weaponName, rewardData.mutations))

			if i == landingIndex then
				iconLabel.ImageColor3 = Color3.fromRGB(247, 0, 255)
			end
		end

		local prizeFrame   = rewardFrames[landingIndex]
		local landingAngle = (360 - (landingIndex - 1) * sliceAngle) % 360
		rewardsContainer.Rotation = 0

		-- Per-wheel phase state
		local phase: "Full" | "Reveal" | "Done" = "Full"
		local revealStartClock: number?    = nil
		local revealStartRotation: number? = nil
		local revealTargetRotation: number? = nil
		local revealDuration: number?      = nil
		
		local TICK_FLICK_ANGLE    = -20   -- degrees the arrow deflects on impact
		local TICK_FLICK_DURATION = 0.05  -- snappy out
		local TICK_RETURN_DURATION = 0.18 -- slower spring-back
		local activeFlickTween: Tween? = nil
		local activeReturnTween: Tween? = nil
		
		local function onSliceCross(currentRotationPerSec: number)
			-- Cancel any in-progress flick or return
			if activeFlickTween then activeFlickTween:Cancel() end
			if activeReturnTween then activeReturnTween:Cancel() end

			-- Snap-flick out
			activeFlickTween = TweenService:Create(
				selectorArrow,
				TweenInfo.new(TICK_FLICK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Rotation = TICK_FLICK_ANGLE}
			)
			activeFlickTween:Play()

			-- Schedule the return after the flick completes
			activeFlickTween.Completed:Once(function(state)
				if state ~= Enum.PlaybackState.Completed then return end -- cancelled mid-flick
				activeReturnTween = TweenService:Create(
					selectorArrow,
					TweenInfo.new(TICK_RETURN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{Rotation = 0}
				)
				activeReturnTween:Play()
			end)

			-- Sound (use pre-hoisted template)
			local tick = RollSFX:WaitForChild("Tick"):Clone()
			local speedNormalized = math.clamp(currentRotationPerSec / (360 * FULL_SPIN_RPS), 0, 1)
			tick.PlaybackSpeed = math.map(speedNormalized, 0, 1, 0.6, 1.1)
			tick.Volume = math.map(speedNormalized, 0, 1, 0.4, 1.0)
			SoundService:PlayLocalSound(tick)
			Debris:AddItem(tick, 1)
		end

		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			local previousRotation = rewardsContainer.Rotation
			
			if phase == "Full" then
				-- Constant full-speed rotation
				rewardsContainer.Rotation = (rewardsContainer.Rotation + 360 * FULL_SPIN_RPS * dt) % 3600

				if shouldStartReveal() then
					phase = "Reveal"
					revealStartClock    = os.clock()
					revealStartRotation = rewardsContainer.Rotation

					local remaining = SPIN_WINDOW - elapsedFullSpin()
					revealDuration  = math.max(MIN_REVEAL_DURATION, remaining)

					-- ending exactly on landingAngle
					local currentMod    = revealStartRotation % 360
					local angleToLand   = (landingAngle - currentMod) % 360
					revealTargetRotation = revealStartRotation
						+ (MIN_REVEAL_REVOLUTIONS * 360)
						+ angleToLand
				end

			elseif phase == "Reveal" then
				local a = math.clamp((os.clock() - revealStartClock) / revealDuration, 0, 1)
				local eased = easeOutCubic(a)
				rewardsContainer.Rotation = revealStartRotation
					+ eased * (revealTargetRotation - revealStartRotation)
				
				
				-- Beams effect
				beamsLabel:FindFirstChild("UIScale").Scale = 1 + (0.3 * eased*0.5)
				beamsLabel.ImageTransparency = 0.75 - (0.25 * eased)
				
				if a >= 1 then
					phase = "Done"
					rewardsContainer.Rotation = revealTargetRotation -- exact snap
					connection:Disconnect()

					local UIScale = prizeFrame:FindFirstChild("UIScale")
					if not UIScale then
						UIScale = Instance.new("UIScale")
						UIScale.Parent = prizeFrame
					end
					local scaleTween = TweenService:Create(
						UIScale,
						TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.InOut),
						{Scale = 1.25}
					)
					scaleTween:Play()
					
					RollController.Controllers.ConfettiEffect:Emit(3)
				end
			end
			
			-- Slice crossing detection (works for both phases, including final landing)
			local currentRotation = rewardsContainer.Rotation
			local rotationDelta   = currentRotation - previousRotation
			-- Handle modulo wrap during Full phase
			if rotationDelta < -180 then rotationDelta += 3600 end

			local rotationPerSec = rotationDelta / dt
			local currentSliceIndex = math.floor(currentRotation / sliceAngle)

			if currentSliceIndex ~= lastSliceIndex and phase ~= "Done" then
				onSliceCross(math.abs(rotationPerSec))
				lastSliceIndex = currentSliceIndex
			end
			lastRotation = currentRotation
		end)
		ActiveRollTrove:Add(connection)
	end
	
	-- Bind Skip
	ActiveRollTrove:Add(skipButton.Activated:Connect(function()
		skipSignaled = true
	end))

	ContextActionService:BindAction(
		"SKIP_SPIN",
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				skipSignaled = true
			end
			return Enum.ContextActionResult.Pass -- don't sink the input
		end,
		false,
		Enum.KeyCode.ButtonY
	)
	ActiveRollTrove:Add(function() ContextActionService:UnbindAction("SKIP_SPIN") end)
		

	ActiveRollTrove:Add(task.delay(jackpotTime, function()
		jackpotDisplay.Visible = false
		RollController.Controllers.UIController:SetOverlayOpenSource("JackpotDisplay", false)
		RollController.Controllers.UIController:ShowScreenElements(true)
	end))
end

local function displayRollSpin(rollData: RollData, rollResults: {ColumnResults}, jackpotResults: {[nunber]: {JackpotResults}?})
	if not rollData or not rollResults then return end
	
	print("Roll Started", rollData)
	RollController.Rolling = true
	
	local rollTime = rollData.rollTime or 1
	
	-- Cleanup active roll playing
	ActiveRollTrove:Clean()
	RollController.Controllers.UIController:SetOverlayOpenSource("JackpotDisplay", false)
	
	if RollController.RollDisplayView == "Full" or (not RollController.AutoRolling and RollController.RollDisplayView == "Mini") then
		RollController:ShowRollDisplay()
	elseif RollController.RollDisplayView == "Mini" then
		rollColumnsContainer.Parent = miniRollDisplay
		miniRollDisplay.Visible = true
		fullRollDisplay.Visible = false
	end
	
	local rollColumnTemplate = rollColumnsContainer:WaitForChild("RollColumnTemplate")
	rollColumnTemplate.Visible = false
	
	
	for columnIndex, columnResult: ColumnResults in rollResults do
			local rollColumn = rollColumnTemplate:Clone()
			ActiveRollTrove:Add(rollColumn)
			rollColumn.Parent = rollColumnsContainer
			rollColumn.Visible = true
			rollColumn.LayoutOrder = columnIndex
			rollColumn.Name = "RollColumn_" .. columnIndex
			rollColumn.BackgroundColor3 = Color3.new(math.random(), math.random(), math.random())

			if rollColumn:FindFirstChild("ResultColumn") then
				rollColumn:FindFirstChild("ResultColumn"):Destroy()
			end

			-- Create result columns
		local resultColumnTemplate  = rollColumnTemplate:WaitForChild("ResultColumn")
		ActiveRollTrove:Add(task.spawn(function()
			for resultIndex, result: RollResult in columnResult do
				local resultColumn = resultColumnTemplate:Clone()
				resultColumn.Parent = rollColumn
				resultColumn.Visible = true
				resultColumn.LayoutOrder = resultIndex
				resultColumn.Name = "ResultColumn_" .. resultIndex
				
				local UIAspectRatioConstraint = resultColumn:WaitForChild("UIAspectRatioConstraint")
				UIAspectRatioConstraint.AspectRatio = RollController.RollDisplayView == "Full" and 0.3 or 0.3
				
				local thisRollTime = if resultIndex == 1
					then rollTime
					else rollTime * RollUtil.CONFIGS.CONSECUTIVE_ROLL_TIME_FRACTION

				-- build strip
				local rewards = {}
				local landingIndex = 3
				for _, fillerReward in generateFillerRewards(rollData, result) do
					table.insert(rewards, fillerReward)
				end
				table.insert(rewards, landingIndex, result) -- Landing reward

				local rewardsContainer = resultColumn:WaitForChild("RewardsContainer")
				for _, rewardFrame in rewardsContainer:GetChildren() do
					if rewardFrame:IsA("Frame") then rewardFrame:Destroy() end
				end

				-- Clone a frame per reward
				local rewardFrames = {}
				for i, rewardData: RollResult in rewards do
					local template = rewardFrameTemplates:FindFirstChild(rewardData.type)
					if not template then warn("[displayRollSpin] No reward frame for type: " .. rewardData.type) continue end

					local frame = createRewardFrame(rewardData)
					frame.Visible = true
					frame.Parent = rewardsContainer
					table.insert(rewardFrames, frame)
					frame.LayoutOrder = i

					local UIScale = frame:FindFirstChildWhichIsA("UIScale")
					if not UIScale then 
						UIScale = Instance.new("UIScale")
						UIScale.Parent = frame
					end
				end
				
				-- Scroll the strip into resting position
				local prizeFrame = rewardFrames[landingIndex]
				local frameCount = #rewardFrames
				
				local elapsed = 0
				local lastScroll = nil
				local connection
				connection = RunService.RenderStepped:Connect(function(deltaTime)
					elapsed += deltaTime
					local a = math.clamp(elapsed / thisRollTime, 0, 1)
					local scroll = (1 - easeOutCubic(a)) * (frameCount - 1)
					
					if lastScroll ~= nil and math.floor(lastScroll) ~= math.floor(scroll) then
						local popSound = RollSFX.Pop:Clone()
						popSound.PlaybackSpeed = math.map(a, 0, 1, 0.5, 1)
						SoundService:PlayLocalSound(popSound)
						Debris:AddItem(popSound, 3)
					end
					lastScroll = scroll

					for i, rewardFrame in rewardFrames do
						local h = rewardFrame.Size.Y.Scale
						local d = (i - landingIndex - scroll) 
						rewardFrame.Position = UDim2.fromScale(0.5, 0.5 + (i - landingIndex - scroll) * h)
						
						-- Falloff from center effect
						local FALLOFF = 0.5

						local UIScale = rewardFrame:FindFirstChildWhichIsA("UIScale")
						if UIScale then
							local MIN_SCALE = 0.5
							local s = 1 - math.abs(d) * FALLOFF      -- linear shrink with distance
							UIScale.Scale = math.max(s, MIN_SCALE)
						end

						local fade = math.clamp(math.abs(d) * FALLOFF, 0, 1)
						for _, textLabel: TextLabel in rewardFrame:QueryDescendants("TextLabel") do
							textLabel.TextTransparency = fade
						end
						for _, uiStroke: UIStroke in rewardFrame:QueryDescendants("UIStroke") do
							uiStroke.Transparency = fade
						end
						for _, imageLabel: ImageLabel in rewardFrame:QueryDescendants("ImageLabel") do
							local defaultTransparency = imageLabel:GetAttribute("DefaultTransparency") or imageLabel.ImageTransparency
							if not imageLabel:GetAttribute("DefaultTransparency") then
								imageLabel:SetAttribute("DefaultTransparency", defaultTransparency)
							end
							imageLabel.ImageTransparency = defaultTransparency + (1 - defaultTransparency) * fade
						end
						
						for _, frame: Frame in rewardFrame:QueryDescendants("Frame") do
							local defaultTransparency = frame:GetAttribute("DefaultTransparency") or frame.BackgroundTransparency
							if not frame:GetAttribute("DefaultTransparency") then
								frame:SetAttribute("DefaultTransparency", defaultTransparency)
							end
							frame.BackgroundTransparency = defaultTransparency + (1 - defaultTransparency) * fade
						end

					end

					if a >= 1 then
						connection:Disconnect()
						
						-- hide other reward frames
						for _, rewardFrame in rewardFrames do
							if rewardFrame ~= prizeFrame then
								local UIScale = rewardFrame:FindFirstChildWhichIsA("UIScale")
								if UIScale then
									local scaleTween = TweenService:Create(UIScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 0})
									scaleTween:Play()
									ActiveRollTrove:Add(task.delay(0.25, function()
										if rewardFrame then rewardFrame:Destroy() end
									end))
								end
							end
						end
						
						-- Play landing effects
						local revealBeam = rollColumnsContainer.UIListLayout:WaitForChild("RevealBeam"):Clone()
						revealBeam.Parent = prizeFrame
						
						local UIScale = revealBeam:FindFirstChild("UIScale")
						local sizeTween = TweenService:Create(UIScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true), {Scale = 2})
						sizeTween:Play()
						
						local transparencyTween = TweenService:Create(revealBeam, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true), {ImageTransparency = 0.6})
						transparencyTween:Play()
						
						ActiveRollTrove:Add(RunService.RenderStepped:Connect(function(deltaTime)
							revealBeam.Rotation += 100 * deltaTime
						end))
						
						-- create screen clover effect
						if result.type == "RollLuck" then
							local multiplier = result.rollLuckMultiplier or 1
							RollController.Controllers.CloverEffect:Emit(multiplier)
						end
					end
				end)
				ActiveRollTrove:Add(connection)

				-- Wait for the roll to finish
				task.wait(thisRollTime)
				
				
				-- Play landing effects
				local matchSound = RollSFX.MatchSounds:FindFirstChild(result.type)
				if matchSound then
					matchSound = matchSound:Clone()
					SoundService:PlayLocalSound(matchSound)
					Debris:AddItem(matchSound, 3)
				end
				
			end
		end))
			
	end
	
	
	local longestResultColumns = 0
	for _, columnResult in rollResults do
		local n = #columnResult
		if n > longestResultColumns then
			longestResultColumns = n
		end
	end
	
	local totalRollTime = rollTime + (longestResultColumns - 1) * (rollTime * RollUtil.CONFIGS.CONSECUTIVE_ROLL_TIME_FRACTION)
	if jackpotResults and next(jackpotResults) then
		local jackpotRevealTime = rollTime + 2 * (rollTime * RollUtil.CONFIGS.CONSECUTIVE_ROLL_TIME_FRACTION)
		totalRollTime += RollUtil.CONFIGS.JACKPOT_ROLL_TIME 
		
		ActiveRollTrove:Add(task.delay(jackpotRevealTime, function()
			displayJackpotSpin(rollData, jackpotResults)
		end))
	end 
	
	ActiveRollTrove:Add(task.delay(totalRollTime, function()
		print("Roll finished")
		RollController.Rolling = false
	end))
	
	
	-- Fire Onboarding Step
	if RollController.Controllers.OnboardingController.OnboardingComplete == false then
		RollController.Controllers.OnboardingController:OnGameEvent("first_roll")
	end
end

local function updateAutoRollState(isAutoRolling: boolean)
	RollController.AutoRolling = isAutoRolling

	local statusIndicator = autoButton:FindFirstChild("StatusIndicator")
	local colorFrame = statusIndicator:FindFirstChild("ColorFrame")
	local displayIcon = autoButton:FindFirstChild("Icon")

	if RotateConnection then RotateConnection:Disconnect() end

	if isAutoRolling then
		RotateConnection = RunService.RenderStepped:Connect(function(deltaTime)
			displayIcon.Rotation = (displayIcon.Rotation + 100 * deltaTime) % 360
		end)
	else
		displayIcon.Rotation = 0
	end

	colorFrame.BackgroundColor3 = isAutoRolling and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
	statusIndicator.ImageColor3 = isAutoRolling and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
end

local function rollDataUpdated(payload: {SpecialRollData: {NextSpecialRoll: string, SpecialRolls: {}}, DiceQueue: {}})
	local rollButtonContainer = specialRollsFrame:WaitForChild("RollButtonContainer")
	local rollButtonTemplate = rollButtonContainer.UIListLayout:WaitForChild("SpecialRollIcon")
	local rollButtonDiceLabel = rollButton:WaitForChild("DiceIcon")
	
	local SpecialRollData = payload.SpecialRollData
	local diceQueue = payload.DiceQueue
	local nextDice = diceQueue[1]

	-- update the special rolls display
	for specialRollName, specialRollEntry in SpecialRollData.SpecialRolls do
		local specialRollDef: SpecialRoll = SpecialRollDefinitions[specialRollName]
		if not specialRollDef then warn("[updateSpecialRolls] missing special roll def for ", specialRollName) continue end
		
		local specialRollButton: ImageButton = rollButtonContainer:FindFirstChild(specialRollName)
		if not specialRollButton then
			specialRollButton = rollButtonTemplate:Clone()
			specialRollButton.Name = specialRollName
			specialRollButton.Parent = rollButtonContainer
			specialRollButton.Image = "rbxassetid://" .. (specialRollDef.displayIcon or "133397058036491")
			
			specialRollButton.Activated:Connect(function()
				remotes.PauseSpecialRoll:FireServer(specialRollName)
			end)
		end
		
		local rollsRequired = specialRollEntry.rollsNeeded
		local rolls = specialRollEntry.rollProgress or 0
		local isPaused = specialRollEntry.paused or false
		
		local rollsLeft = math.max(0, rollsRequired - rolls)
		local progress = math.clamp(rolls / rollsRequired, 0, 1)
		
		local rollsLabel = specialRollButton:WaitForChild("RollsLabel")
		local pauseIcon = specialRollButton:WaitForChild("PauseIcon")
		
		rollsLabel.Text = rollsLeft

		local fillGradient: UIGradient = specialRollButton:WaitForChild("FillGradient")
		fillGradient.Offset = Vector2.new(0, math.map(progress, 0, 1, 0.5, -0.5))
		
		pauseIcon.Visible = isPaused
		rollsLabel.TextColor3 = isPaused and Color3.fromRGB(255, 115, 0) or Color3.fromRGB(255, 255, 255)
		
		specialRollButton.Visible = SpecialRollData.NextSpecialRoll ~= specialRollName
	end
	
	if nextDice then
		local diceName = nextDice.diceName
		local diceDefinition: DiceDefinition = ItemDefinitions[diceName]
		if not diceDefinition then warn("[rollDataUpdated] missing dice def for ", diceName) return end
		rollButtonDiceLabel.Image = "rbxassetid://" .. (diceDefinition.displayImage or "133397058036491")

	elseif SpecialRollData.NextSpecialRoll then
		local nextSpecialRollDef: SpecialRoll = SpecialRollDefinitions[SpecialRollData.NextSpecialRoll]
		if not nextSpecialRollDef then warn("[updateSpecialRolls] missing special roll def for ", SpecialRollData.NextSpecialRoll) return end
		rollButtonDiceLabel.Image = "rbxassetid://" .. (nextSpecialRollDef.displayIcon or "133397058036491")

	else
		rollButtonDiceLabel.Image = "rbxassetid://133397058036491"
	end
end

local function _bindOnboardingSteps()
	local onboardingController = RollController.Controllers.OnboardingController
	
	local rollSteps = { "first_roll", "second_roll", "third_roll" }
	for _, stepName in rollSteps do
		onboardingController.StepEventFunctions[stepName] = function()
			-- TODO: create a pointing icon to the roll button
			print("PRESS THE ROLL BUTTTON!")
		end
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function RollController:HideRollDisplay()
	RollController.RollDisplayView = "Mini"
	fullRollDisplay.Visible = false
	miniRollDisplay.Visible = true
	rollColumnsContainer.Parent = miniRollDisplay 
	
	self.Controllers.UIController:SetOverlayOpenSource("FullRollDisplay", false)
	self.Controllers.UIController:ShowScreenElements(true)
end

function RollController:ShowRollDisplay()
	RollController.RollDisplayView = "Full"
	fullRollDisplay.Visible = true
	miniRollDisplay.Visible = false
	rollColumnsContainer.Parent = fullRollDisplay.Container
	self.Controllers.UIController:SetOverlayOpenSource("FullRollDisplay", true)
	self.Controllers.UIController:CloseFrames()
	self.Controllers.UIController:ShowScreenElements(false)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function RollController:Init(controllers)
	self.Controllers = controllers
	
	_bindOnboardingSteps()
	
	hideButton.Activated:Connect(function()
		self:HideRollDisplay()
	end)
	
	autoButton.Activated:Connect(function()
		remotes.ToggleAutoRoll:FireServer()
	end)

	rollButton.Activated:Connect(function()
		if self.Rolling then
			self:ShowRollDisplay()
		else
			remotes.AttemptRoll:FireServer()
		end
	end)

end

function RollController:Start()
	remotes.RollResult.OnClientEvent:Connect(function(rollData: {}, rollResults: {ColumnResults}, jackpotResults: {[nunber]: {JackpotResults}?})
		displayRollSpin(rollData, rollResults, jackpotResults)
	end)
	
	remotes.ToggleAutoRoll.OnClientEvent:Connect(function(isAutoRolling)
		updateAutoRollState(isAutoRolling)
	end)
	
	-- TODO
	remotes.RollingDataUpdated.OnClientEvent:Connect(rollDataUpdated)
end


return RollController
