local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local spring = require(ReplicatedStorage.Packages.Spring)
local spr = require(ReplicatedStorage.Packages.Spr)
local Gigantix = require(ReplicatedStorage.Packages.Gigantix)
local PlayerGUI = LocalPlayer:WaitForChild("PlayerGui")

local hitmarkerContainer = PlayerGUI:WaitForChild("HitmarkerContainer")
local hitmarkerGui: ImageLabel = hitmarkerContainer:WaitForChild("Hitmarker")
local damageNumberTemplate: TextLabel = hitmarkerContainer:WaitForChild("DamageNumber") :: TextLabel

for _, child in hitmarkerContainer:GetChildren() do
	if child.Name:match("^DamageNumber_%d+$") or child.Name:match("^DamageCounter_%d+$") then
		child:Destroy()
	end
end

local hitmarkerTimer = -1

local HITMARKER_VISIBLE_DURATION = 0.3
local HITMARKER_SHRINK_SIZE_MULT = 0.5
local HITMARKER_SOUND_ID = "rbxassetid://137166459647708"
local HEADSHOT_HITMARKER_SOUND_ID = "rbxassetid://108290646184559"
local HITMARKER_AUDIO_EMITTER_NAME = "HitmarkerAudioEmitter"
local HITMARKER_AUDIO_VOICE_COUNT = 8
local HITMARKER_AUDIO_MIN_INTERVAL = 0.025
local HITMARKER_AUDIO_BASE_VOLUME = 0.42
local HITMARKER_AUDIO_HEADSHOT_VOLUME_BONUS = 0.08
local HITMARKER_AUDIO_BATCH_VOLUME_STEP = 0.04
local HITMARKER_AUDIO_MAX_VOLUME = 100
local HITMARKER_AUDIO_MAX_BATCH_VOLUME_STEPS = 5
local HITMARKER_AUDIO_PITCH_VARIANCE = 0.035
local USE_HIT_POSITION_HITMARKER = true
local USE_COUNTER_HITMARKER = true
local COUNTER_HITMARKER_POOL_SIZE = 20
local COUNTER_HITMARKER_MAX_SIZE_MULT = 1.18
local COUNTER_HITMARKER_REST_SIZE_MULT = 1
local COUNTER_HITMARKER_POP_DURATION = 0.08
local COUNTER_HITMARKER_LINGER_DURATION = 0.45
local COUNTER_HITMARKER_FALL_DURATION = 0.2
local COUNTER_HEADSHOT_COLOR = Color3.new(1, 0, 0)
local COUNTER_COLOR_SPRING_DAMPING_RATIO = 0.75
local COUNTER_COLOR_SPRING_FREQUENCY = 18
local DAMAGE_NUMBER_POOL_SIZE = 20
local DAMAGE_NUMBER_POP_DURATION = 0.1
local DAMAGE_NUMBER_FALL_DURATION = 0.2
local DAMAGE_NUMBER_HEADSHOT_COLOR = Color3.new(1, 1, 1)
local HEAD_DAMAGE_GAP_PIXELS = 4
local HEAD_DAMAGE_JITTER_PIXELS = 4
local COUNTER_HEAD_DAMAGE_GAP_PIXELS = 0
local COUNTER_HEAD_DAMAGE_JITTER_PIXELS = 0
local sizeMultSpring = spring.new(HITMARKER_SHRINK_SIZE_MULT, 0, HITMARKER_SHRINK_SIZE_MULT, 45, 1)
local originalSize: UDim2 = hitmarkerGui.Size
local hitmarkerPosition: UDim2 = hitmarkerGui.Position
local hitmarkerWorldPosition: Vector3? = nil
local hitmarkerRenderStepName = "hitmarkerRender_" .. HttpService:GenerateGUID(false)
local isCleaningUp = false
local connections = {}
local delayedThreads = {}

RunService:UnbindFromRenderStep("hitmarkerRender")

local function trackConnection(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(connections, connection)
	return connection
end

local function scheduleDelay(duration: number, callback: () -> ())
	local delayedThread
	delayedThread = task.delay(duration, function()
		delayedThreads[delayedThread] = nil
		if isCleaningUp then
			return
		end

		callback()
	end)
	delayedThreads[delayedThread] = true
end

local currentCamera = workspace.CurrentCamera
if currentCamera then
	for _, child in currentCamera:GetChildren() do
		if child.Name == HITMARKER_AUDIO_EMITTER_NAME then
			child:Destroy()
		end
	end
end

local hitmarkerAudioEmitter = Instance.new("AudioEmitter")
hitmarkerAudioEmitter.Name = HITMARKER_AUDIO_EMITTER_NAME
hitmarkerAudioEmitter.Parent = currentCamera

local hitmarkerAudioLimiter = Instance.new("AudioLimiter")
hitmarkerAudioLimiter.Name = "HitmarkerAudioLimiter"
hitmarkerAudioLimiter.Parent = hitmarkerAudioEmitter

local hitmarkerAudioLimiterWire = Instance.new("Wire")
hitmarkerAudioLimiterWire.Name = "HitmarkerAudioLimiterWire"
hitmarkerAudioLimiterWire.SourceInstance = hitmarkerAudioLimiter
hitmarkerAudioLimiterWire.TargetInstance = hitmarkerAudioEmitter
hitmarkerAudioLimiterWire.Parent = hitmarkerAudioLimiter

trackConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local camera = workspace.CurrentCamera
	if camera then
		for _, child in camera:GetChildren() do
			if child.Name == HITMARKER_AUDIO_EMITTER_NAME and child ~= hitmarkerAudioEmitter then
				child:Destroy()
			end
		end
		hitmarkerAudioEmitter.Parent = camera
	end
end))

local hitmarkerAudioVoices = table.create(HITMARKER_AUDIO_VOICE_COUNT)
local nextHitmarkerAudioVoiceIndex = 1
local lastHitmarkerAudioAt = -math.huge
local pendingHitmarkerAudioCount = 0
local pendingHitmarkerAudioHeadshot = false
local hitmarkerAudioFlushScheduled = false

for index = 1, HITMARKER_AUDIO_VOICE_COUNT do
	local audioPlayer = Instance.new("AudioPlayer")
	audioPlayer.Name = `HitmarkerAudioPlayer_{index}`
	audioPlayer.Parent = hitmarkerAudioEmitter
	audioPlayer.AutoLoad = true

	local wire = Instance.new("Wire")
	wire.Name = `HitmarkerAudioWire_{index}`
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = hitmarkerAudioLimiter
	wire.Parent = audioPlayer

	hitmarkerAudioVoices[index] = audioPlayer
end

local function playHitmarkerAudioBatch(headshot: boolean, hitCount: number)
	local audioPlayer: AudioPlayer = hitmarkerAudioVoices[nextHitmarkerAudioVoiceIndex]
	nextHitmarkerAudioVoiceIndex = (nextHitmarkerAudioVoiceIndex % HITMARKER_AUDIO_VOICE_COUNT) + 1

	local batchSteps = math.min(math.max(hitCount - 1, 0), HITMARKER_AUDIO_MAX_BATCH_VOLUME_STEPS)
	audioPlayer:Stop()
	audioPlayer.AssetId = if headshot then HEADSHOT_HITMARKER_SOUND_ID else HITMARKER_SOUND_ID
	audioPlayer.Volume = math.min(
		HITMARKER_AUDIO_MAX_VOLUME,
		HITMARKER_AUDIO_BASE_VOLUME
			+ (if headshot then HITMARKER_AUDIO_HEADSHOT_VOLUME_BONUS else 0)
			+ (batchSteps * HITMARKER_AUDIO_BATCH_VOLUME_STEP)
	)
	audioPlayer.PlaybackSpeed = (if headshot then 1.03 else 1)
		+ ((math.random() * 2 - 1) * HITMARKER_AUDIO_PITCH_VARIANCE)
	audioPlayer.TimePosition = 0
	audioPlayer:Play()
	lastHitmarkerAudioAt = os.clock()
end

local function scaleSize(size: UDim2, scale: number): UDim2
	return UDim2.new(
		size.X.Scale * scale,
		size.X.Offset * scale,
		size.Y.Scale * scale,
		size.Y.Offset * scale
	)
end

local enemyModelCacheById = setmetatable({}, { __mode = "v" })

local function getContainerAbsolutePosition(): Vector2
	if hitmarkerContainer:IsA("GuiObject") then
		return hitmarkerContainer.AbsolutePosition
	end
	return Vector2.new()
end

local function getSizePixels(size: UDim2): Vector2
	local containerSize: Vector2
	if hitmarkerContainer:IsA("GuiObject") then
		containerSize = hitmarkerContainer.AbsoluteSize
	else
		local camera = workspace.CurrentCamera
		containerSize = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	end

	return Vector2.new(
		(size.X.Scale * containerSize.X) + size.X.Offset,
		(size.Y.Scale * containerSize.Y) + size.Y.Offset
	)
end

local function isValidHeadPart(headPart: BasePart?): boolean
	return typeof(headPart) == "Instance" and headPart:IsA("BasePart") and headPart.Parent ~= nil
end

local function getDamageAnchorPart(enemyId: any): BasePart?
	if enemyId == nil then
		return nil
	end

	local enemyModel: Model? = enemyModelCacheById[enemyId]
	if not (enemyModel and enemyModel.Parent and enemyModel:GetAttribute("id") == enemyId) then
		enemyModelCacheById[enemyId] = nil

		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("Model") and descendant:GetAttribute("id") == enemyId then
				enemyModel = descendant
				enemyModelCacheById[enemyId] = descendant
				break
			end
		end
	end

	if not enemyModel then
		return nil
	end

	local head = enemyModel:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return enemyModel.PrimaryPart
end

local function createHeadPlacement(gapPixels: number?, jitterPixels: number?)
	local gapBase = gapPixels or HEAD_DAMAGE_GAP_PIXELS
	local jitter = jitterPixels or HEAD_DAMAGE_JITTER_PIXELS

	return {
		placement = math.random(1, 2),
		gap = gapBase + math.random(0, jitter),
		jitterX = math.random(-jitter, jitter),
		jitterY = math.random(-jitter, jitter),
		yAlpha = math.random(),
	}
end

local function getGuiPositionAroundHead(headPart: BasePart?, guiSize: Vector2, placementData): Vector2?
	if not isValidHeadPart(headPart) then
		return nil
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local halfSize = headPart.Size * 0.5
	local minX = math.huge
	local maxX = -math.huge
	local minY = math.huge
	local maxY = -math.huge
	local hasProjectedPoint = false

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local corner = headPart.CFrame:PointToWorldSpace(Vector3.new(halfSize.X * xSign, halfSize.Y * ySign, halfSize.Z * zSign))
				local viewportPoint = camera:WorldToViewportPoint(corner)
				if viewportPoint.Z > 0 then
					hasProjectedPoint = true
					minX = math.min(minX, viewportPoint.X)
					maxX = math.max(maxX, viewportPoint.X)
					minY = math.min(minY, viewportPoint.Y)
					maxY = math.max(maxY, viewportPoint.Y)
				end
			end
		end
	end

	if not hasProjectedPoint then
		return nil
	end

	local placement = placementData or createHeadPlacement()
	local yPosition = minY + ((maxY - minY) * placement.yAlpha) + placement.jitterY

	if placement.placement == 1 then
		return Vector2.new(
			minX - (guiSize.X * 0.5) - placement.gap + placement.jitterX,
			yPosition
		) - getContainerAbsolutePosition()
	end

	return Vector2.new(
		maxX + (guiSize.X * 0.5) + placement.gap + placement.jitterX,
		yPosition
	) - getContainerAbsolutePosition()
end

local function formatDamage(damage: number): string
	local rounded = math.floor(damage + 0.5)
	if math.abs(damage) >= 1000 then
		local sign = if damage < 0 then "-" else ""
		local absoluteRounded = math.max(math.floor(math.abs(damage) + 0.5), 0)
		return sign .. Gigantix.getShort(Gigantix.stringToNumber(string.format("%.0f", absoluteRounded)))
	end

	if math.abs(damage - rounded) < 0.05 then
		return tostring(rounded)
	end
	return string.format("%.1f", damage)
end

local damageNumberPool = table.create(DAMAGE_NUMBER_POOL_SIZE)
local nextDamageNumberIndex = 1

damageNumberTemplate.Visible = false

for index = 1, DAMAGE_NUMBER_POOL_SIZE do
	local damageNumber = damageNumberTemplate:Clone()
	damageNumber.Name = `DamageNumber_{index}`
	damageNumber.AnchorPoint = Vector2.new(0.5, 0.5)
	damageNumber.Visible = false
	damageNumber.Parent = hitmarkerContainer

	local uiStroke = damageNumber:FindFirstChildWhichIsA("UIStroke", true)

	damageNumberPool[index] = {
		gui = damageNumber,
		busy = false,
		token = 0,
		tween = nil,
		tweenCompletedConnection = nil,
		strokeTween = nil,
		uiStroke = uiStroke,
		originalSize = damageNumberTemplate.Size,
		originalRotation = damageNumberTemplate.Rotation,
		originalBackgroundTransparency = damageNumberTemplate.BackgroundTransparency,
		originalTextColor = damageNumber.TextColor3,
		originalTextTransparency = damageNumber.TextTransparency,
		originalTextStrokeTransparency = damageNumber.TextStrokeTransparency,
		originalUIStrokeTransparency = if uiStroke then uiStroke.Transparency else nil,
	}
end

local function resetDamageNumber(record)
	if record.tweenCompletedConnection then
		record.tweenCompletedConnection:Disconnect()
		record.tweenCompletedConnection = nil
	end
	if record.tween then
		record.tween:Cancel()
		record.tween = nil
	end
	if record.strokeTween then
		record.strokeTween:Cancel()
		record.strokeTween = nil
	end

	local gui: TextLabel = record.gui
	local uiStroke: UIStroke? = record.uiStroke

	spr.stop(gui)
	gui.Visible = false
	gui.Size = record.originalSize
	gui.Rotation = record.originalRotation
	gui.BackgroundTransparency = record.originalBackgroundTransparency
	gui.TextTransparency = record.originalTextTransparency
	gui.TextStrokeTransparency = record.originalTextStrokeTransparency
	gui.TextColor3 = record.originalTextColor

	if uiStroke then
		uiStroke.Transparency = record.originalUIStrokeTransparency
	end
end

local function playDamageNumber(damage: number, headshot: boolean, headPart: BasePart?)
	if damage <= 0 then
		return
	end

	local record
	for offset = 0, DAMAGE_NUMBER_POOL_SIZE - 1 do
		local index = ((nextDamageNumberIndex + offset - 1) % DAMAGE_NUMBER_POOL_SIZE) + 1
		local candidate = damageNumberPool[index]
		if not candidate.busy then
			record = candidate
			nextDamageNumberIndex = (index % DAMAGE_NUMBER_POOL_SIZE) + 1
			break
		end
	end

	if not record then
		record = damageNumberPool[nextDamageNumberIndex]
		nextDamageNumberIndex = (nextDamageNumberIndex % DAMAGE_NUMBER_POOL_SIZE) + 1
	end

	record.busy = true
	record.token += 1
	local token = record.token

	resetDamageNumber(record)
	record.busy = true

	local gui: TextLabel = record.gui
	local hitmarkerCenter = hitmarkerGui.AbsolutePosition + (hitmarkerGui.AbsoluteSize * 0.5)
	local localCenter = hitmarkerCenter - getContainerAbsolutePosition()
	local damageNumberSize = getSizePixels(record.originalSize)
	local side = if math.random(1, 2) == 1 then -1 else 1
	local gap = math.random(8, 18)
	local xOffset = side * ((hitmarkerGui.AbsoluteSize.X + damageNumberSize.X) * 0.5 + gap)
	local yVariance = math.max(6, math.floor(hitmarkerGui.AbsoluteSize.Y * 0.25))
	local startPosition = getGuiPositionAroundHead(headPart, damageNumberSize, createHeadPlacement())
		or localCenter + Vector2.new(xOffset, math.random(-yVariance, yVariance))
	local endPosition = startPosition + Vector2.new(side * math.random(8, 28), math.random(42, 72))

	gui.Size = UDim2.fromScale(0, 0)
	gui.Position = UDim2.fromOffset(startPosition.X, startPosition.Y)
	gui.Rotation = record.originalRotation + math.random(-8, 8)
	gui.Visible = true
	gui.Text = formatDamage(damage)
	gui.TextColor3 = if headshot then DAMAGE_NUMBER_HEADSHOT_COLOR else record.originalTextColor

	spr.target(gui, 0.85, 22, {
		Size = record.originalSize,
	})

	scheduleDelay(DAMAGE_NUMBER_POP_DURATION, function()
		if record.token ~= token then
			return
		end
		spr.stop(gui, "Size")
		gui.Size = record.originalSize

		local tweenProperties: {[string]: any} = {
			Position = UDim2.fromOffset(endPosition.X, endPosition.Y),
			Rotation = record.originalRotation + math.random(-45, 45),
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}

		local tween = TweenService:Create(
			gui,
			TweenInfo.new(DAMAGE_NUMBER_FALL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			tweenProperties
		)
		record.tween = tween

		local completedConnection: RBXScriptConnection?
		completedConnection = tween.Completed:Connect(function()
			if completedConnection then
				completedConnection:Disconnect()
			end
			if record.tweenCompletedConnection == completedConnection then
				record.tweenCompletedConnection = nil
			end
			if isCleaningUp or record.token ~= token or record.tween ~= tween then
				return
			end
			record.tween = nil
			resetDamageNumber(record)
			record.busy = false
		end)
		record.tweenCompletedConnection = completedConnection
		tween:Play()

		local uiStroke: UIStroke? = record.uiStroke
		if uiStroke then
			record.strokeTween = TweenService:Create(
				uiStroke,
				TweenInfo.new(DAMAGE_NUMBER_FALL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			)
			record.strokeTween:Play()
		end
	end)
end

local counterHitmarkerPool = table.create(COUNTER_HITMARKER_POOL_SIZE)
local activeCounterHitmarkersByEnemyId = {}
local nextCounterHitmarkerIndex = 1

for index = 1, COUNTER_HITMARKER_POOL_SIZE do
	local counter = damageNumberTemplate:Clone()
	counter.Name = `DamageCounter_{index}`
	counter.AnchorPoint = Vector2.new(0.5, 0.5)
	counter.Visible = false
	counter.Parent = hitmarkerContainer

	local counterStroke = counter:FindFirstChildWhichIsA("UIStroke", true)
	local counterAspectRatioConstraint = counter:FindFirstChildWhichIsA("UIAspectRatioConstraint", true)

	counterHitmarkerPool[index] = {
		gui = counter,
		counterStroke = counterStroke,
		aspectRatioConstraint = counterAspectRatioConstraint,
		enemyId = nil,
		anchorPart = nil,
		headPlacement = nil,
		position = nil,
		totalDamage = 0,
		busy = false,
		token = 0,
		lingerUntil = 0,
		sizeSpring = spring.new(COUNTER_HITMARKER_REST_SIZE_MULT, 0, COUNTER_HITMARKER_REST_SIZE_MULT, 60, 0.85),
		rotationSpring = spring.new(0, 0, 0, 42, 0.75),
		fallTween = nil,
		fallTweenCompletedConnection = nil,
		strokeTween = nil,
		originalSize = damageNumberTemplate.Size,
		originalRotation = damageNumberTemplate.Rotation,
		originalBackgroundTransparency = damageNumberTemplate.BackgroundTransparency,
		originalTextTransparency = counter.TextTransparency,
		originalTextStrokeTransparency = counter.TextStrokeTransparency,
		originalTextColor = counter.TextColor3,
		originalStrokeTransparency = if counterStroke then counterStroke.Transparency else nil,
	}
end

local function getCounterSizePixels(record, scale: number): Vector2
	local sizePixels = getSizePixels(scaleSize(record.originalSize, scale))
	local aspectRatioConstraint: UIAspectRatioConstraint? = record.aspectRatioConstraint
	if not aspectRatioConstraint or aspectRatioConstraint.AspectRatio <= 0 then
		return sizePixels
	end

	if aspectRatioConstraint.DominantAxis.Name == "Height" then
		return Vector2.new(sizePixels.Y * aspectRatioConstraint.AspectRatio, sizePixels.Y)
	end

	return Vector2.new(sizePixels.X, sizePixels.X / aspectRatioConstraint.AspectRatio)
end

local function cancelCounterHitmarkerTweens(record)
	if record.fallTweenCompletedConnection then
		record.fallTweenCompletedConnection:Disconnect()
		record.fallTweenCompletedConnection = nil
	end
	if record.fallTween then
		record.fallTween:Cancel()
		record.fallTween = nil
	end
	if record.strokeTween then
		record.strokeTween:Cancel()
		record.strokeTween = nil
	end
end

local function restoreCounterHitmarkerVisuals(record, preserveTextColor: boolean?)
	local gui: TextLabel = record.gui
	local counterStroke: UIStroke? = record.counterStroke

	gui.BackgroundTransparency = record.originalBackgroundTransparency
	gui.TextTransparency = record.originalTextTransparency
	gui.TextStrokeTransparency = record.originalTextStrokeTransparency
	if not preserveTextColor then
		spr.stop(gui, "TextColor3")
		gui.TextColor3 = record.originalTextColor
	end

	if counterStroke then
		counterStroke.Transparency = record.originalStrokeTransparency
	end
end

local function resetCounterHitmarker(record)
	cancelCounterHitmarkerTweens(record)

	if record.enemyId ~= nil and activeCounterHitmarkersByEnemyId[record.enemyId] == record then
		activeCounterHitmarkersByEnemyId[record.enemyId] = nil
	end

	local gui: TextLabel = record.gui
	gui.Visible = false
	gui.Rotation = record.originalRotation
	gui.Size = record.originalSize

	restoreCounterHitmarkerVisuals(record)
	gui.Text = "0"
	record.enemyId = nil
	record.anchorPart = nil
	record.headPlacement = nil
	record.position = nil
	record.totalDamage = 0
	record.busy = false
	record.lingerUntil = 0
	record.sizeSpring.p = COUNTER_HITMARKER_REST_SIZE_MULT
	record.sizeSpring.v = 0
	record.sizeSpring.target = COUNTER_HITMARKER_REST_SIZE_MULT
	record.rotationSpring.p = record.originalRotation
	record.rotationSpring.v = 0
	record.rotationSpring.target = record.originalRotation
end

local function getCounterPosition(record, headPart: BasePart?, headPlacement, allowFallback: boolean?): Vector2?
	local hitmarkerCenter = hitmarkerGui.AbsolutePosition + (hitmarkerGui.AbsoluteSize * 0.5)
	local localCenter = hitmarkerCenter - getContainerAbsolutePosition()
	local counterSize = getCounterSizePixels(record, COUNTER_HITMARKER_MAX_SIZE_MULT)
	local headPosition = getGuiPositionAroundHead(headPart, counterSize, headPlacement)
	if headPosition then
		return headPosition
	end

	if allowFallback == false then
		return nil
	end

	local side = if math.random(1, 2) == 1 then -1 else 1
	local gap = math.random(10, 22)
	local xOffset = side * ((hitmarkerGui.AbsoluteSize.X + counterSize.X) * 0.5 + gap)
	local yVariance = math.max(6, math.floor(hitmarkerGui.AbsoluteSize.Y * 0.35))

	return localCenter + Vector2.new(xOffset + math.random(-8, 8), math.random(-yVariance, yVariance))
end

local function playCounterHitmarker(enemyId: any, damage: number, headshot: boolean): boolean
	if enemyId == nil or damage <= 0 then
		return false
	end

	local record = activeCounterHitmarkersByEnemyId[enemyId]
	if not record then
		for offset = 0, COUNTER_HITMARKER_POOL_SIZE - 1 do
			local index = ((nextCounterHitmarkerIndex + offset - 1) % COUNTER_HITMARKER_POOL_SIZE) + 1
			local candidate = counterHitmarkerPool[index]
			if not candidate.busy then
				record = candidate
				nextCounterHitmarkerIndex = (index % COUNTER_HITMARKER_POOL_SIZE) + 1
				break
			end
		end

		if not record then
			record = counterHitmarkerPool[nextCounterHitmarkerIndex]
			nextCounterHitmarkerIndex = (nextCounterHitmarkerIndex % COUNTER_HITMARKER_POOL_SIZE) + 1
			resetCounterHitmarker(record)
		end

		record.enemyId = enemyId
		local anchorPart = getDamageAnchorPart(enemyId)
		if isValidHeadPart(anchorPart) then
			record.anchorPart = anchorPart
			record.headPlacement = createHeadPlacement(COUNTER_HEAD_DAMAGE_GAP_PIXELS, COUNTER_HEAD_DAMAGE_JITTER_PIXELS)
		end
		record.position = nil
		record.totalDamage = 0
		record.busy = true
		activeCounterHitmarkersByEnemyId[enemyId] = record
	elseif not isValidHeadPart(record.anchorPart) then
		local anchorPart = getDamageAnchorPart(enemyId)
		if isValidHeadPart(anchorPart) then
			record.anchorPart = anchorPart
			record.headPlacement = record.headPlacement or createHeadPlacement(COUNTER_HEAD_DAMAGE_GAP_PIXELS, COUNTER_HEAD_DAMAGE_JITTER_PIXELS)
			record.position = nil
		end
	end

	record.token += 1
	local token = record.token
	cancelCounterHitmarkerTweens(record)
	restoreCounterHitmarkerVisuals(record, true)

	local gui: TextLabel = record.gui
	record.totalDamage += damage
	local damageText = formatDamage(record.totalDamage)

	local counterPosition: Vector2? = nil
	if record.headPlacement ~= nil then
		counterPosition = getCounterPosition(record, record.anchorPart, record.headPlacement, false)
	end
	counterPosition = counterPosition or record.position or getCounterPosition(record, record.anchorPart, record.headPlacement, true)
	if not counterPosition then
		return false
	end
	record.position = counterPosition

	gui.Text = damageText
	spr.target(gui, COUNTER_COLOR_SPRING_DAMPING_RATIO, COUNTER_COLOR_SPRING_FREQUENCY, {
		TextColor3 = if headshot then COUNTER_HEADSHOT_COLOR else record.originalTextColor,
	})
	record.lingerUntil = os.clock() + COUNTER_HITMARKER_LINGER_DURATION
	record.sizeSpring.p = math.min(record.sizeSpring.p, COUNTER_HITMARKER_REST_SIZE_MULT)
	record.sizeSpring.v = 0
	record.sizeSpring.target = COUNTER_HITMARKER_MAX_SIZE_MULT
	record.rotationSpring.v = math.random(-120, 120)
	record.rotationSpring.target = record.originalRotation + math.random(-12, 12)
	gui.Size = scaleSize(record.originalSize, record.sizeSpring.p)
	gui.Position = UDim2.fromOffset(counterPosition.X, counterPosition.Y)
	gui.Visible = true

	scheduleDelay(COUNTER_HITMARKER_POP_DURATION, function()
		if record.token ~= token then
			return
		end
		record.sizeSpring.target = COUNTER_HITMARKER_REST_SIZE_MULT
		record.rotationSpring.target = record.originalRotation
	end)

	return true
end

local function updateCounterHitmarkers(step: number)
	local now = os.clock()
	for _, record in counterHitmarkerPool do
		if record.busy then
			record.sizeSpring:update(step)
			record.rotationSpring:update(step)
			if record.fallTween == nil and record.headPlacement ~= nil then
				if not isValidHeadPart(record.anchorPart) then
					record.anchorPart = getDamageAnchorPart(record.enemyId)
				end

				local trackedPosition = getCounterPosition(record, record.anchorPart, record.headPlacement, false)
				if trackedPosition then
					record.position = trackedPosition
					record.gui.Position = UDim2.fromOffset(trackedPosition.X, trackedPosition.Y)
				end
			end
			record.gui.Size = scaleSize(record.originalSize, record.sizeSpring.p)
			record.gui.Rotation = record.rotationSpring.p

			if record.fallTween == nil and now >= record.lingerUntil then
				local token = record.token
				local gui: TextLabel = record.gui
				local currentPosition = gui.Position
				local endPosition = UDim2.new(
					currentPosition.X.Scale,
					currentPosition.X.Offset + math.random(-18, 18),
					currentPosition.Y.Scale,
					currentPosition.Y.Offset + math.random(52, 82)
				)

				local fallTween = TweenService:Create(
					gui,
					TweenInfo.new(COUNTER_HITMARKER_FALL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{
						Position = endPosition,
						BackgroundTransparency = 1,
						TextTransparency = 1,
						TextStrokeTransparency = 1,
					}
				)
				record.fallTween = fallTween

				local completedConnection: RBXScriptConnection?
				completedConnection = fallTween.Completed:Connect(function()
					if completedConnection then
						completedConnection:Disconnect()
					end
					if record.fallTweenCompletedConnection == completedConnection then
						record.fallTweenCompletedConnection = nil
					end
					if isCleaningUp or record.token ~= token or record.fallTween ~= fallTween then
						return
					end
					record.fallTween = nil
					resetCounterHitmarker(record)
				end)
				record.fallTweenCompletedConnection = completedConnection
				fallTween:Play()

				local counterStroke: UIStroke? = record.counterStroke
				if counterStroke then
					record.strokeTween = TweenService:Create(
						counterStroke,
						TweenInfo.new(COUNTER_HITMARKER_FALL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Transparency = 1 }
					)
					record.strokeTween:Play()
				end
			end
		end
	end
end

trackConnection(ReplicatedStorage.Remotes.GunKit.HitLog.OnClientEvent:Connect(function(
	hitPartOrHeadshot: any,
	_shootFrom: Vector3?,
	hitPosition: Vector3?,
	damage: number?,
	_totalHits: number?,
	isHeadshot: boolean?,
	didDamage: boolean?,
	enemyId: any
)
	local headshot = false
	local damageAmount = damage
	local shouldShowDamage = didDamage == true
	local hitEnemyId = enemyId

	if typeof(hitPartOrHeadshot) == "boolean" then
		headshot = hitPartOrHeadshot
	elseif typeof(hitPartOrHeadshot) == "table" then
		local payload = hitPartOrHeadshot
		headshot = payload.headshot == true
		damageAmount = payload.damage
		shouldShowDamage = payload.didDamage == true
		hitEnemyId = payload.enemyId or payload.id
		hitPosition = payload.hitPosition or payload.position or hitPosition
	else
		headshot = isHeadshot == true
	end

	if hitmarkerContainer:IsA("LayerCollector") then
		hitmarkerContainer.Enabled = true
	elseif hitmarkerContainer:IsA("GuiObject") then
		hitmarkerContainer.Visible = true
	end

	hitmarkerTimer = HITMARKER_VISIBLE_DURATION
	hitmarkerGui.Visible = true
	hitmarkerGui.Size = originalSize
	if USE_HIT_POSITION_HITMARKER then
		hitmarkerPosition = hitmarkerGui.Position
		hitmarkerWorldPosition = hitPosition
	end
	if USE_HIT_POSITION_HITMARKER and hitPosition then
		local camera = workspace.CurrentCamera
		if camera then
			local viewportPoint = camera:WorldToViewportPoint(hitPosition)
			if viewportPoint.Z > 0 then
				local localPosition = Vector2.new(viewportPoint.X, viewportPoint.Y) - getContainerAbsolutePosition()
				hitmarkerPosition = UDim2.fromOffset(localPosition.X, localPosition.Y)
			end
		end
	end
	if USE_HIT_POSITION_HITMARKER then
		hitmarkerGui.Position = hitmarkerPosition
	end
	hitmarkerGui.ImageColor3 = if headshot then Color3.new(1, 0, 0) else Color3.new(1, 1, 1)
	sizeMultSpring.p = 1
	sizeMultSpring.v = 0
	sizeMultSpring.target = HITMARKER_SHRINK_SIZE_MULT

	if USE_COUNTER_HITMARKER then
		if shouldShowDamage and typeof(damageAmount) == "number" then
			playCounterHitmarker(hitEnemyId, damageAmount, headshot)
		end
	end

	pendingHitmarkerAudioCount += 1
	pendingHitmarkerAudioHeadshot = pendingHitmarkerAudioHeadshot or headshot

	local now = os.clock()
	if now - lastHitmarkerAudioAt >= HITMARKER_AUDIO_MIN_INTERVAL then
		local hitCount = pendingHitmarkerAudioCount
		local shouldPlayHeadshot = pendingHitmarkerAudioHeadshot
		pendingHitmarkerAudioCount = 0
		pendingHitmarkerAudioHeadshot = false
		playHitmarkerAudioBatch(shouldPlayHeadshot, hitCount)
	elseif not hitmarkerAudioFlushScheduled then
		hitmarkerAudioFlushScheduled = true
		scheduleDelay(HITMARKER_AUDIO_MIN_INTERVAL - (now - lastHitmarkerAudioAt), function()
			hitmarkerAudioFlushScheduled = false
			if pendingHitmarkerAudioCount <= 0 then
				return
			end

			local hitCount = pendingHitmarkerAudioCount
			local shouldPlayHeadshot = pendingHitmarkerAudioHeadshot
			pendingHitmarkerAudioCount = 0
			pendingHitmarkerAudioHeadshot = false
			playHitmarkerAudioBatch(shouldPlayHeadshot, hitCount)
		end)
	end

	if not USE_COUNTER_HITMARKER and shouldShowDamage and typeof(damageAmount) == "number" then
		playDamageNumber(damageAmount, headshot, getDamageAnchorPart(hitEnemyId))
	end
end))

RunService:BindToRenderStep(hitmarkerRenderStepName, Enum.RenderPriority.Last.Value, function(step)
	updateCounterHitmarkers(step)

	hitmarkerTimer = hitmarkerTimer - step
	if hitmarkerTimer <= 0 then
		hitmarkerGui.Visible = false
		hitmarkerWorldPosition = nil
		return
	end

	sizeMultSpring:update(step)

	local mult = sizeMultSpring.p
	if USE_HIT_POSITION_HITMARKER then
		local worldPosition = hitmarkerWorldPosition
		local camera = workspace.CurrentCamera
		if worldPosition and camera then
			local viewportPoint = camera:WorldToViewportPoint(worldPosition)
			if viewportPoint.Z > 0 then
				local localPosition = Vector2.new(viewportPoint.X, viewportPoint.Y) - getContainerAbsolutePosition()
				hitmarkerPosition = UDim2.fromOffset(localPosition.X, localPosition.Y)
				hitmarkerGui.Visible = true
			else
				hitmarkerGui.Visible = false
			end
		end

		hitmarkerGui.Position = hitmarkerPosition
	end
	hitmarkerGui.Size = scaleSize(originalSize, mult)
end)

trackConnection(script.Destroying:Connect(function()
	if isCleaningUp then
		return
	end

	isCleaningUp = true
	RunService:UnbindFromRenderStep(hitmarkerRenderStepName)

	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	for delayedThread in delayedThreads do
		task.cancel(delayedThread)
	end
	table.clear(delayedThreads)

	for _, record in damageNumberPool do
		record.token += 1
		resetDamageNumber(record)
		record.busy = false
		record.gui:Destroy()
	end
	table.clear(damageNumberPool)

	for _, record in counterHitmarkerPool do
		record.token += 1
		resetCounterHitmarker(record)
		record.gui:Destroy()
	end
	table.clear(counterHitmarkerPool)
	table.clear(activeCounterHitmarkersByEnemyId)
	table.clear(enemyModelCacheById)
	table.clear(hitmarkerAudioVoices)

	hitmarkerAudioEmitter:Destroy()
end))
