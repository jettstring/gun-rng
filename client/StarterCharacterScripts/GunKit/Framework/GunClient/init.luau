local module = {}
local module_mt = {__index = module}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))
local spring = require(script:WaitForChild("Spring"))
local MuzzleFlash = require(script:WaitForChild("MuzzleFlash"))
local ProjectileAudio = require(ReplicatedStorage.Packages.ProjectileAudio)
local WeaponAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("WeaponAssets")
local WeaponDefinitions = require(
	WeaponAssets:WaitForChild("WeaponDefinitions")
)

local DEFAULT_TIME_BETWEEN_SHOTS = 1 / 4
-- Stagger same-type guns across one fire interval.
local ALTERNATING_SHOOTING_ENABLED = true
local DEFAULT_ANCHOR_CAMERA_MAX_YAW = math.rad(35)
local DEFAULT_ANCHOR_CAMERA_MAX_PITCH = math.rad(20)
local ANCHOR_CAMERA_BEHIND_DOT = 0
local DEFAULT_MAX_AIM_HORIZONTAL_ANGLE = math.rad(140)
local DEFAULT_ANCHOR_POSITION_SPRING_FREQUENCY = 100
local DEFAULT_ANCHOR_POSITION_SPRING_DAMPING = 0.9
local DEFAULT_AIM_TARGET_SPRING_FREQUENCY = 18
local DEFAULT_AIM_TARGET_SPRING_DAMPING = 0.95
local DEFAULT_ON_TARGET_ANGLE = math.rad(3)
local DEFAULT_SPREAD_RECOIL_SPRING_FREQUENCY = 18
local DEFAULT_SPREAD_RECOIL_SPRING_DAMPING = 0.95
local DEFAULT_RECOIL_DISTANCE = 0.35
local DEFAULT_RECOIL_RETURN_DELAY = 0.06
local DEFAULT_KICKBACK_ROTATION_RETURN_TBS_PERCENT = 0.65
local DEFAULT_KICKBACK_ROTATION_DAMPING = 1
local KICKBACK_ROTATION_SETTLE_MULTIPLIER = 7
local MIN_KICKBACK_ROTATION_RETURN_DURATION = 1 / 240
local DEFAULT_GUN_ROLL_RECOIL_SPRING_FREQUENCY = 32
local DEFAULT_GUN_ROLL_RECOIL_SPRING_DAMPING = 0.85
local DEFAULT_GUN_ROLL_RECOIL_GROWTH_DEGREES = 0.75
local DEFAULT_GUN_ROLL_RECOIL_NOISE_DEGREES = 0.5
local DEFAULT_SUSTAINED_RECOIL_FALLOFF_DURATION = 1.5
local DEFAULT_SUSTAINED_RECOIL_MIN_MULTIPLIER = 0.25
local DEBUG_MARKER_SIZE = 0.45
local DEBUG_LINE_THICKNESS = 0.08
local DEBUG_TARGET_ANCHOR_COLOR = Color3.fromRGB(255, 214, 10)
local DEBUG_SPRING_ANCHOR_COLOR = Color3.fromRGB(0, 221, 255)
local DEBUG_LINE_COLOR = Color3.fromRGB(255, 255, 255)
local AUTO_AIM_IDLE_DISTANCE = 1000
local SMART_CROSSHAIR_CONTAINER_NAME = "HitmarkerContainer"
local SMART_CROSSHAIR_TEMPLATE_NAME = "Crosshair"
local SMART_CROSSHAIR_VALID_TARGET_COLOR = Color3.fromRGB(255, 55, 55)
local SMART_CROSSHAIR_HEADSHOT_TARGET_COLOR = Color3.fromRGB(0, 0, 0)
local TARGET_HIGHLIGHT_TEMPLATE_NAME = "TargetHighlight"
local TARGET_HIGHLIGHT_FOOTPRINT_SCALE = 1.15
local POSITIONING_FOLDER_NAME = "GunPositioning"
local IDLE_POSITIONING_SET_NAME = "Idle"
local AIMING_POSITIONING_SET_NAME = "Aiming"
local POSITIONING_ROOT_PART_NAME = "RootPart"
local FALLBACK_BACK_ANCHOR_LOCAL_CFRAME = CFrame.new(0, 3, 6)
local FALLBACK_FRONT_ANCHOR_LOCAL_CFRAME = CFrame.new(0, 3, -6)
local VECTOR_EPSILON = 1e-5

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type PositioningNode = {
	instance: Instance,
	cframe: CFrame,
	order: number,
}

type PositioningSet = {
	rootCFrame: CFrame,
	nodes: {PositioningNode},
}

type AnchorPlacement = {
	origin: Vector3,
	right: Vector3,
	up: Vector3,
	normal: Vector3,
}

type GunClientOptions = {
	gunId: string,
	gunName: string,
	gunEvent: RemoteEvent?,
	modelParent: Instance?,
	anchorParent: Instance?,
	onClientShot: ((WeaponDefinition, string, number) -> ())?,
	canClientShoot: (() -> boolean)?,
	requiresOnTarget: (() -> boolean)?,
	assistVisualsEnabled: boolean?,
	autoAimEnabled: boolean?,
	sendShootEvents: boolean?,
	playShotAudio: boolean?,
}

type AutoAimResult = {
	aimPoint: Vector3,
	enemy: Model,
	isHeadshot: boolean,
}

local warnedMissingSmartCrosshair = false

local function getRootPart(character: Model): BasePart?
	local primaryPart = character.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return nil
end

local function getAutoAimPart(enemyModel: Model, gunData: WeaponDefinition): (BasePart?, boolean)
	if gunData.autoAimHeadshot == true then
		return EnemyTargeting.getHeadPart(enemyModel), true
	end

	return EnemyTargeting.getGunAimPart(enemyModel), false
end

local function findSmartCrosshairTemplate(player: Player): ImageLabel?
	local starterContainer = StarterGui:FindFirstChild(SMART_CROSSHAIR_CONTAINER_NAME)
	local starterTemplate = if starterContainer then starterContainer:FindFirstChild(SMART_CROSSHAIR_TEMPLATE_NAME) else nil
	if starterTemplate and starterTemplate:IsA("ImageLabel") then
		return starterTemplate
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local playerContainer = if playerGui then playerGui:FindFirstChild(SMART_CROSSHAIR_CONTAINER_NAME) else nil
	local playerTemplate = if playerContainer then playerContainer:FindFirstChild(SMART_CROSSHAIR_TEMPLATE_NAME) else nil
	if playerTemplate and playerTemplate:IsA("ImageLabel") then
		return playerTemplate
	end

	return nil
end

local function findSmartCrosshairParent(player: Player): Instance?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild(SMART_CROSSHAIR_CONTAINER_NAME)
end

local function getGuiPositionOffset(parent: Instance?): Vector2
	if parent and parent:IsA("GuiObject") then
		return parent.AbsolutePosition
	end

	return Vector2.new()
end

local function prepareGunModel(gunModel: Model)
	gunModel.PrimaryPart = gunModel.Nodes.main

	for _, descendant in gunModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function createAnchorPart(name: string, parent: Instance?): BasePart
	local anchorPart = Instance.new("Part")
	anchorPart.Name = `{name}Anchor`
	anchorPart.Size = Vector3.new(0.25, 0.25, 0.25)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.Parent = parent or workspace

	return anchorPart
end

local function createDebugPart(name: string, color: Color3, size: Vector3, parent: Instance?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 0.1
	part.Parent = parent or workspace

	return part
end

local function createDebugLine(name: string, color: Color3, parent: Instance?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(DEBUG_LINE_THICKNESS, DEBUG_LINE_THICKNESS, DEBUG_LINE_THICKNESS)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 0.35
	part.Parent = parent or workspace

	return part
end

local function getPivotOffset(gunModel: Model, part: BasePart): CFrame
	return gunModel:GetPivot():ToObjectSpace(part.CFrame)
end

local function getTimeBetweenShots(gunData: WeaponDefinition): number
	if gunData.tbs > 0 then
		return gunData.tbs
	end

	return DEFAULT_TIME_BETWEEN_SHOTS
end

local function getAutoAimRange(gunData: WeaponDefinition): number
	if gunData.autoAimRange > 0 then
		return gunData.autoAimRange
	end

	return 0
end

local function getOnTargetAngle(gunData: WeaponDefinition): number
	if gunData.onTargetAngleDegrees and gunData.onTargetAngleDegrees > 0 then
		return math.rad(gunData.onTargetAngleDegrees)
	end

	return DEFAULT_ON_TARGET_ANGLE
end

local function getPositiveSetting(value: number?, defaultValue: number): number
	if value and value > 0 then
		return value
	end

	return defaultValue
end

local function getClampedNumberSetting(value: number?, defaultValue: number, minValue: number, maxValue: number): number
	if value then
		return math.clamp(value, minValue, maxValue)
	end

	return defaultValue
end

local function getPercentSetting(value: number?, defaultValue: number, minValue: number, maxValue: number): number
	if not value then
		return defaultValue
	end

	local normalizedValue = if value > 1 then value / 100 else value
	return math.clamp(normalizedValue, minValue, maxValue)
end

local function getKickbackRotationTheta(gunData: WeaponDefinition): number
	if gunData.kickbackRotationThetaDegrees and gunData.kickbackRotationThetaDegrees > 0 then
		return math.rad(gunData.kickbackRotationThetaDegrees)
	end

	return 0
end

local function getKickbackRotationReturnDuration(gunData: WeaponDefinition): number
	local returnPercent = getPercentSetting(
		gunData.kickbackRotationReturnTbsPercent,
		DEFAULT_KICKBACK_ROTATION_RETURN_TBS_PERCENT,
		0,
		0.95
	)

	return math.max(getTimeBetweenShots(gunData) * returnPercent, MIN_KICKBACK_ROTATION_RETURN_DURATION)
end

local function getGunRollRecoilMax(gunData: WeaponDefinition): number
	if gunData.gunRollRecoilMaxDegrees and gunData.gunRollRecoilMaxDegrees > 0 then
		return math.rad(gunData.gunRollRecoilMaxDegrees)
	end

	return 0
end

local function getGunRollRecoilGrowth(gunData: WeaponDefinition): number
	if gunData.gunRollRecoilGrowthDegrees and gunData.gunRollRecoilGrowthDegrees > 0 then
		return math.rad(gunData.gunRollRecoilGrowthDegrees)
	end

	return math.rad(DEFAULT_GUN_ROLL_RECOIL_GROWTH_DEGREES)
end

local function getGunRollRecoilNoise(gunData: WeaponDefinition): number
	if gunData.gunRollRecoilNoiseDegrees and gunData.gunRollRecoilNoiseDegrees > 0 then
		return math.rad(gunData.gunRollRecoilNoiseDegrees)
	end

	return math.rad(DEFAULT_GUN_ROLL_RECOIL_NOISE_DEGREES)
end

local function isSustainedRecoilFalloffEnabled(gunData: WeaponDefinition): boolean
	return gunData.sustainedRecoilFalloffEnabled == true
end

local function isAimAngleLimitEnabled(gunData: WeaponDefinition): boolean
	return gunData.aimAngleLimitEnabled ~= false
end

local function sampleSpreadOffset(moa: number?): Vector2
	if not moa or moa <= 0 then
		return Vector2.new()
	end

	local spreadRadians = math.rad(moa / 60)
	if spreadRadians <= 0 then
		return Vector2.new()
	end

	local theta = math.random() * math.pi * 2
	local radius = math.sqrt(math.random()) * spreadRadians
	return Vector2.new(math.sin(theta) * radius, math.cos(theta) * radius)
end

local function applySpreadOffset(direction: Vector3, spreadOffset: Vector2): Vector3
	if direction.Magnitude <= VECTOR_EPSILON then
		return direction
	end

	local basis = CFrame.lookAt(Vector3.zero, direction)
	local spreadCFrame = basis * CFrame.Angles(spreadOffset.X, spreadOffset.Y, 0)

	return spreadCFrame.LookVector
end

local function projectOntoPlane(vector: Vector3, normal: Vector3): Vector3
	return vector - normal * vector:Dot(normal)
end

local function getDefaultAnchorNormal(rootPart: BasePart, useFrontPole: boolean?): Vector3
	local forward = rootPart.CFrame.LookVector
	if forward.Magnitude > VECTOR_EPSILON then
		return if useFrontPole then forward.Unit else -forward.Unit
	end

	return if useFrontPole then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)
end

local function getCameraInfluencedAnchorNormal(rootPart: BasePart, useFrontPole: boolean?): Vector3
	local defaultNormal = getDefaultAnchorNormal(rootPart, useFrontPole)
	local camera = workspace.CurrentCamera
	if not camera or camera.CFrame.LookVector.Magnitude <= VECTOR_EPSILON then
		return defaultNormal
	end

	local cameraLook = camera.CFrame.LookVector.Unit
	local poleFacingDirection = -defaultNormal
	if cameraLook:Dot(poleFacingDirection) < ANCHOR_CAMERA_BEHIND_DOT then
		return defaultNormal
	end

	local desiredNormal = -cameraLook
	local right = rootPart.CFrame.RightVector
	local up = rootPart.CFrame.UpVector
	local forwardDot = desiredNormal:Dot(defaultNormal)
	local rightDot = desiredNormal:Dot(right)
	local upDot = desiredNormal:Dot(up)
	local horizontalMagnitude = math.sqrt(forwardDot * forwardDot + rightDot * rightDot)
	local yaw = math.clamp(math.atan2(rightDot, forwardDot), -DEFAULT_ANCHOR_CAMERA_MAX_YAW, DEFAULT_ANCHOR_CAMERA_MAX_YAW)
	local pitch = math.clamp(
		math.atan2(upDot, horizontalMagnitude),
		-DEFAULT_ANCHOR_CAMERA_MAX_PITCH,
		DEFAULT_ANCHOR_CAMERA_MAX_PITCH
	)
	local horizontalDirection = defaultNormal * math.cos(yaw) + right * math.sin(yaw)
	if horizontalDirection.Magnitude <= VECTOR_EPSILON then
		return defaultNormal
	end

	local normal = horizontalDirection.Unit * math.cos(pitch) + up * math.sin(pitch)
	if normal.Magnitude <= VECTOR_EPSILON then
		return defaultNormal
	end

	return normal.Unit
end

local function getAnchorPlacement(rootPart: BasePart, useFrontPole: boolean?): AnchorPlacement
	local normal = getCameraInfluencedAnchorNormal(rootPart, useFrontPole)
	local rightVector = projectOntoPlane(rootPart.CFrame.RightVector, normal)
	if rightVector.Magnitude <= VECTOR_EPSILON then
		rightVector = projectOntoPlane(Vector3.new(1, 0, 0), normal)
	end
	if rightVector.Magnitude <= VECTOR_EPSILON then
		rightVector = projectOntoPlane(Vector3.new(0, 0, 1), normal)
	end

	local right = if rightVector.Magnitude > VECTOR_EPSILON then rightVector.Unit else rootPart.CFrame.RightVector
	local upVector = projectOntoPlane(rootPart.CFrame.UpVector, normal)
	upVector = projectOntoPlane(upVector, right)
	if upVector.Magnitude <= VECTOR_EPSILON then
		upVector = projectOntoPlane(Vector3.new(0, 1, 0), normal)
		upVector = projectOntoPlane(upVector, right)
	end
	if upVector.Magnitude <= VECTOR_EPSILON then
		upVector = projectOntoPlane(Vector3.new(0, 0, 1), normal)
		upVector = projectOntoPlane(upVector, right)
	end

	local up = if upVector.Magnitude > VECTOR_EPSILON then upVector.Unit else rootPart.CFrame.UpVector

	return {
		origin = rootPart.Position,
		right = right,
		up = up,
		normal = normal,
	}
end

local function transformAnchorLocalPosition(placement: AnchorPlacement, localPosition: Vector3): Vector3
	return placement.origin
		+ placement.right * localPosition.X
		+ placement.up * localPosition.Y
		+ placement.normal * localPosition.Z
end

local POSITIONING_REFERENCE_NAMES = {
	origin = true,
	root = true,
	rootpart = true,
	center = true,
	pivot = true,
	reference = true,
	character = true,
	humanoidrootpart = true,
}

local function getInstanceCFrame(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end

	return nil
end

local function findChildCaseInsensitive(parent: Instance, childName: string): Instance?
	local targetName = string.lower(childName)
	for _, child in parent:GetChildren() do
		if string.lower(child.Name) == targetName then
			return child
		end
	end

	return nil
end

local function findDescendantCaseInsensitive(parent: Instance, descendantName: string): Instance?
	local targetName = string.lower(descendantName)
	for _, descendant in parent:GetDescendants() do
		if string.lower(descendant.Name) == targetName then
			return descendant
		end
	end

	return nil
end

local function isPositioningReferenceNode(instance: Instance): boolean
	return POSITIONING_REFERENCE_NAMES[string.lower(instance.Name)] == true
end

local function hasPositioningReferenceAncestor(instance: Instance, container: Instance): boolean
	local current: Instance? = instance
	while current and current ~= container do
		if isPositioningReferenceNode(current) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function getNodeOrder(instance: Instance): number
	for _, attributeName in {"Index", "Slot", "Order"} do
		local value = instance:GetAttribute(attributeName)
		if typeof(value) == "number" then
			return value
		end

		if typeof(value) == "string" then
			local order = tonumber(value)
			if order then
				return order
			end
		end
	end

	return tonumber(instance.Name) or tonumber(string.match(instance.Name, "%d+")) or math.huge
end

local function collectPositioningNodes(container: Instance?): {PositioningNode}
	local nodes: {PositioningNode} = {}
	if not container then
		return nodes
	end

	for _, descendant in container:GetDescendants() do
		if hasPositioningReferenceAncestor(descendant, container) then
			continue
		end

		local cframe = getInstanceCFrame(descendant)
		if not cframe then
			continue
		end

		table.insert(nodes, {
			instance = descendant,
			cframe = cframe,
			order = getNodeOrder(descendant),
		})
	end

	table.sort(nodes, function(left: PositioningNode, right: PositioningNode): boolean
		if left.order ~= right.order then
			return left.order < right.order
		end

		return left.instance.Name < right.instance.Name
	end)

	return nodes
end

local function getPositioningRootCFrame(container: Instance?): CFrame
	if not container then
		return CFrame.new()
	end

	local rootPart = findChildCaseInsensitive(container, POSITIONING_ROOT_PART_NAME)
		or findDescendantCaseInsensitive(container, POSITIONING_ROOT_PART_NAME)
	if rootPart then
		local rootCFrame = getInstanceCFrame(rootPart)
		if rootCFrame then
			return rootCFrame
		end
	end

	for _, descendant in container:GetDescendants() do
		if isPositioningReferenceNode(descendant) then
			local cframe = getInstanceCFrame(descendant)
			if cframe then
				return cframe
			end
		end
	end

	return CFrame.new()
end

local function getPositioningSet(container: Instance?): PositioningSet
	return {
		rootCFrame = getPositioningRootCFrame(container),
		nodes = collectPositioningNodes(container),
	}
end

local function getGunPositioningData(): (PositioningSet?, PositioningSet?)
	local positioningFolder = ReplicatedStorage.GameAssets.WeaponAssets:FindFirstChild(POSITIONING_FOLDER_NAME)
	if not positioningFolder then
		return nil, nil
	end

	local idleSet = findChildCaseInsensitive(positioningFolder, IDLE_POSITIONING_SET_NAME)
	local aimingSet = findChildCaseInsensitive(positioningFolder, AIMING_POSITIONING_SET_NAME)

	return getPositioningSet(idleSet), getPositioningSet(aimingSet)
end

local function getSlotNodeCFrame(nodes: {PositioningNode}, slotIndex: number): CFrame?
	if #nodes <= 0 then
		return nil
	end

	local nodeIndex = math.clamp(math.floor(slotIndex), 1, #nodes)
	return nodes[nodeIndex].cframe
end

local function getSlotLocalCFrame(positioningSet: PositioningSet?, slotIndex: number): CFrame?
	if not positioningSet then
		return nil
	end

	local nodeCFrame = getSlotNodeCFrame(positioningSet.nodes, slotIndex)
	if not nodeCFrame then
		return nil
	end

	return positioningSet.rootCFrame:ToObjectSpace(nodeCFrame)
end

local function lookAtPoint(position: Vector3, lookTarget: Vector3, fallbackDirection: Vector3): CFrame
	if (lookTarget - position).Magnitude > VECTOR_EPSILON then
		return CFrame.new(position, lookTarget)
	end

	local direction = if fallbackDirection.Magnitude > VECTOR_EPSILON then fallbackDirection.Unit else Vector3.new(0, 0, -1)
	return CFrame.new(position, position + direction)
end

local function updateLinePart(linePart: BasePart, startPosition: Vector3, endPosition: Vector3)
	local delta = endPosition - startPosition
	local distance = delta.Magnitude

	if distance <= VECTOR_EPSILON then
		linePart.Transparency = 1
		return
	end

	linePart.Transparency = 0.35
	linePart.Size = Vector3.new(DEBUG_LINE_THICKNESS, DEBUG_LINE_THICKNESS, distance)
	linePart.CFrame = CFrame.new(startPosition, endPosition) * CFrame.new(0, 0, -distance / 2)
end

local function getAimLimitBasis(rootPart: BasePart, useFrontPole: boolean?): (Vector3?, Vector3?, Vector3?)
	local up = rootPart.CFrame.UpVector
	local facingDirection = if useFrontPole then -rootPart.CFrame.LookVector else rootPart.CFrame.LookVector
	local forward = projectOntoPlane(facingDirection, up)
	if forward.Magnitude <= VECTOR_EPSILON then
		return nil, nil, nil
	end

	local forwardUnit = forward.Unit
	local right = forwardUnit:Cross(up)
	if right.Magnitude <= VECTOR_EPSILON then
		right = projectOntoPlane(rootPart.CFrame.RightVector, up)
	end
	if right.Magnitude <= VECTOR_EPSILON then
		return nil, nil, nil
	end

	local rightUnit = right.Unit

	return forwardUnit, rightUnit, up
end

local function getAimPointHorizontalYaw(aimPoint: Vector3, rootPart: BasePart, useFrontPole: boolean?): number?
	local forwardUnit, rightUnit, up = getAimLimitBasis(rootPart, useFrontPole)
	if not forwardUnit or not rightUnit or not up then
		return nil
	end

	local aimOffset = aimPoint - rootPart.Position
	local horizontalOffset = projectOntoPlane(aimOffset, up)
	if horizontalOffset.Magnitude <= VECTOR_EPSILON then
		return nil
	end

	local horizontalDirection = horizontalOffset.Unit
	return math.atan2(horizontalDirection:Dot(rightUnit), horizontalDirection:Dot(forwardUnit))
end

local function isAimPointOutsideAngleLimit(aimPoint: Vector3, rootPart: BasePart): boolean
	local yaw = getAimPointHorizontalYaw(aimPoint, rootPart, false)
	return yaw ~= nil and math.abs(yaw) > DEFAULT_MAX_AIM_HORIZONTAL_ANGLE
end

local function clampAimPointToPoleFacing(aimPoint: Vector3, rootPart: BasePart, useFrontPole: boolean?): Vector3
	local forwardUnit, rightUnit, up = getAimLimitBasis(rootPart, useFrontPole)
	if not forwardUnit or not rightUnit or not up then
		return aimPoint
	end

	local aimOffset = aimPoint - rootPart.Position
	local horizontalOffset = projectOntoPlane(aimOffset, up)
	if horizontalOffset.Magnitude <= VECTOR_EPSILON then
		return aimPoint
	end

	local yaw = math.atan2(horizontalOffset.Unit:Dot(rightUnit), horizontalOffset.Unit:Dot(forwardUnit))
	local clampedYaw = math.clamp(yaw, -DEFAULT_MAX_AIM_HORIZONTAL_ANGLE, DEFAULT_MAX_AIM_HORIZONTAL_ANGLE)
	if yaw == clampedYaw then
		return aimPoint
	end

	local horizontalDistance = horizontalOffset.Magnitude
	local verticalOffset = up * aimOffset:Dot(up)
	local clampedHorizontalDirection = forwardUnit * math.cos(clampedYaw) + rightUnit * math.sin(clampedYaw)

	return rootPart.Position + clampedHorizontalDirection * horizontalDistance + verticalOffset
end

function module.new(
	player: Player,
	character: Model,
	gunData: WeaponDefinition,
	options: GunClientOptions
)
	assert(player and character and gunData and gunData.model, "GunClient.new requires a player, character, and weapon definition with a model.")
	assert(options and options.gunId and options.gunName, "GunClient.new requires gunId and gunName options.")

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = getRootPart(character)
	if not humanoid or not rootPart then
		return nil
	end

	local self = {}
	self.player = player
	self.isLocalShooter = player == Players.LocalPlayer
	self.character = character
	self.humanoid = humanoid
	self.rootPart = rootPart
	self.gunData = gunData
	self.gunId = options.gunId
	self.gunName = options.gunName
	self.gunEvent = options.gunEvent
	self.onClientShot = options.onClientShot
	self.canClientShoot = options.canClientShoot
	self.requiresOnTarget = options.requiresOnTarget
	self.assistVisualsEnabled = options.assistVisualsEnabled ~= false
	self.sendShootEvents = options.sendShootEvents ~= false
	self.playShotAudio = options.playShotAudio ~= false
	self.projectileRays = false
	self.autoAimEnabled = options.autoAimEnabled ~= false
	self.autoAimTag = EnemyTargeting.getOwnerTag(player)
	self.autoAimCache = if self.autoAimEnabled then EnemyTargeting.acquireCache(self.autoAimTag) else nil
	self.currentAutoAimTarget = nil
	self.currentAutoAimIsHeadshot = false
	self.debugVisible = false
	self.debugFolder = nil
	self.debugParts = nil
	self.smartCrosshair = nil
	self.smartCrosshairParent = if self.assistVisualsEnabled then findSmartCrosshairParent(player) else nil
	self.smartCrosshairTemplate = if self.assistVisualsEnabled then findSmartCrosshairTemplate(player) else nil
	self.smartCrosshairDefaultColor = Color3.new(1, 1, 1)
	self.targetHighlightTemplate = if self.assistVisualsEnabled then WeaponAssets:WaitForChild(TARGET_HIGHLIGHT_TEMPLATE_NAME) else nil
	self.targetHighlight = nil
	self.targetHighlightThickness = nil
	self.targetHighlightTarget = nil
	self.targetHighlightHeartbeatConnection = if self.assistVisualsEnabled
		then RunService.Heartbeat:Connect(function()
			self:updateTargetHighlight()
		end)
		else nil
	self.isEquipped = false
	self.state = {
		shooting = false,
		sustainedRecoilStartedAt = nil,
	}
	self.lastAimPoint = nil
	self.lastHasShootTarget = false

	self.gunModel = gunData.model:Clone()
	self.gunModel.Name = `{self.gunName}ClientModel`
	prepareGunModel(self.gunModel)
	self.gunModel.Parent = options.modelParent or workspace

	self.anchorPart = createAnchorPart(self.gunName, options.anchorParent)
	local primaryPart = self.gunModel.PrimaryPart
	self.primaryPartOffset = getPivotOffset(self.gunModel, primaryPart)
	self.modelAnchorOffset = self.primaryPartOffset
	self.muzzleNode = self.gunModel.Nodes.MuzzleFlash
	self.muzzleOffset = getPivotOffset(self.gunModel, self.muzzleNode)

	self.MuzzleFlash = MuzzleFlash.new(self.gunModel)

	self.slotIndex = 1
	self.slotTotal = 1
	self.anchorPositionInitialized = false
	self.aimTargetInitialized = false
	self.gameTime = 0
	self.nextAllowedShotTime = 0
	self.lastShotFireTime = -math.huge
	self.fireCadenceStartTime = 0
	self.fireCadencePhaseOffset = 0
	self.fireCadenceInterval = getTimeBetweenShots(gunData)
	self.fireCadenceGroupSize = 1
	self.manualFireRequested = false
	self.returnRecoilTime = 0
	self.kickbackRotationReturnTime = 0
	self.gunRollRecoilMagnitude = 0
	self.gunRollRecoilDirection = if math.random(0, 1) == 0 then -1 else 1

	self.springs = {
		anchorPosition = spring.new(
			Vector3.new(),
			Vector3.new(),
			Vector3.new(),
			getPositiveSetting(gunData.anchorPositionSpringFrequency, DEFAULT_ANCHOR_POSITION_SPRING_FREQUENCY),
			getPositiveSetting(gunData.anchorPositionSpringDamping, DEFAULT_ANCHOR_POSITION_SPRING_DAMPING)
		),
		aimTarget = spring.new(
			Vector3.new(),
			Vector3.new(),
			Vector3.new(),
			getPositiveSetting(gunData.aimTargetSpringFrequency, DEFAULT_AIM_TARGET_SPRING_FREQUENCY),
			getPositiveSetting(gunData.aimTargetSpringDamping, DEFAULT_AIM_TARGET_SPRING_DAMPING)
		),
		spreadRecoil = spring.new(
			Vector3.new(),
			Vector3.new(),
			Vector3.new(),
			getPositiveSetting(gunData.spreadRecoilSpringFrequency, DEFAULT_SPREAD_RECOIL_SPRING_FREQUENCY),
			getPositiveSetting(gunData.spreadRecoilSpringDamping, DEFAULT_SPREAD_RECOIL_SPRING_DAMPING)
		),
		sway = spring.new(Vector3.new(), Vector3.new(), Vector3.new(), 15, 1.25),
		bobbing = spring.new(Vector3.new(), Vector3.new(), Vector3.new(), 10, 1),
		kickback = spring.new(Vector3.new(), Vector3.new(), Vector3.new(), 28, 0.7),
		kickbackRotation = spring.new(0, 0, 0, 40, DEFAULT_KICKBACK_ROTATION_DAMPING),
		gunRollRecoil = spring.new(
			0,
			0,
			0,
			DEFAULT_GUN_ROLL_RECOIL_SPRING_FREQUENCY,
			DEFAULT_GUN_ROLL_RECOIL_SPRING_DAMPING
		),
	}

	return setmetatable(self, module_mt)
end

function module:equip()
	self.isEquipped = true
	if self.assistVisualsEnabled then
		self:createSmartCrosshair()
	end
end

function module:unequip()
	self.isEquipped = false
	self.state.shooting = false
	self.state.sustainedRecoilStartedAt = nil
	self.kickbackRotationReturnTime = 0
	self:resetGunRollRecoil(true)
	self:setSmartCrosshairVisible(false)
end

function module:setSlot(index: number, total: number)
	self.slotIndex = math.max(index, 1)
	self.slotTotal = math.max(total, 1)
end

function module:setProjectileRays(enabled: boolean)
	self.projectileRays = enabled == true
end

function module:setAutoAimEnabled(enabled: boolean)
	self.autoAimEnabled = enabled == true
	if self.autoAimEnabled and not self.autoAimCache then
		self.autoAimCache = EnemyTargeting.acquireCache(self.autoAimTag)
	elseif not self.autoAimEnabled then
		self:setCurrentAutoAimTarget(nil, false)
	end
end

function module:setCurrentAutoAimTarget(target: Model?, isHeadshot: boolean?)
	local headshotTarget = isHeadshot == true
	if self.currentAutoAimTarget == target and self.currentAutoAimIsHeadshot == headshotTarget then
		return
	end

	self.currentAutoAimTarget = target
	self.currentAutoAimIsHeadshot = headshotTarget
end

function module:createSmartCrosshair()
	if not self.assistVisualsEnabled then
		return
	end

	if self.smartCrosshair then
		return
	end

	local template = self.smartCrosshairTemplate or findSmartCrosshairTemplate(self.player)
	local parent = self.smartCrosshairParent or findSmartCrosshairParent(self.player)
	if not template or not parent then
		if not warnedMissingSmartCrosshair then
			warn("GunKit smart crosshair template StarterGui.HitmarkerContainer.Crosshair was not found.")
			warnedMissingSmartCrosshair = true
		end
		return
	end
	self.smartCrosshairTemplate = template
	self.smartCrosshairParent = parent

	if template.Parent == parent then
		template.Visible = false
	end

	local crosshair = template:Clone()
	crosshair.Name = `{self.gunName}_{self.gunId}_SmartCrosshair`
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Visible = false
	crosshair.Parent = parent

	self.smartCrosshair = crosshair
	self.smartCrosshairDefaultColor = crosshair.ImageColor3
end

function module:setSmartCrosshairVisible(visible: boolean)
	if not self.assistVisualsEnabled then
		return
	end

	if self.smartCrosshair then
		self.smartCrosshair.Visible = visible == true
	end

	if visible ~= true then
		self:setTargetHighlightTarget(nil)
	end
end

function module:destroySmartCrosshair()
	if self.smartCrosshair then
		self.smartCrosshair:Destroy()
	end

	self.smartCrosshair = nil
end

function module:createTargetHighlight()
	if not self.assistVisualsEnabled or not self.targetHighlightTemplate then
		return
	end

	if self.targetHighlight then
		return
	end

	local targetHighlight = self.targetHighlightTemplate:Clone() :: BasePart
	targetHighlight.Name = `{self.gunName}_{self.gunId}_TargetHighlight`
	targetHighlight.Parent = nil
	self.targetHighlight = targetHighlight
	self.targetHighlightThickness = targetHighlight.Size.Y
end

function module:setTargetHighlightTarget(target: Model?)
	if not self.assistVisualsEnabled then
		return
	end

	if self.targetHighlightTarget == target then
		return
	end

	self.targetHighlightTarget = target
	if not target then
		if self.targetHighlight then
			self.targetHighlight.Parent = nil
		end
		return
	end

	self:createTargetHighlight()
	if self.targetHighlight then
		self.targetHighlight.Parent = workspace
		self:updateTargetHighlight()
	end
end

function module:updateTargetHighlight()
	if not self.assistVisualsEnabled then
		return
	end

	local target = self.targetHighlightTarget
	local targetHighlight = self.targetHighlight
	if not target or not targetHighlight then
		return
	end

	if not target.Parent or not EnemyTargeting.isOwnedEnemy(target, self.autoAimTag) or not EnemyTargeting.getAliveHumanoid(target) then
		self:setTargetHighlightTarget(nil)
		return
	end

	if targetHighlight.Parent ~= workspace then
		targetHighlight.Parent = workspace
	end

	local boundingCFrame, boundingSize = target:GetBoundingBox()
	local center = boundingCFrame.Position
	local baseY = center.Y - boundingSize.Y * 0.5
	local footprint = math.max(boundingSize.X, boundingSize.Z) * TARGET_HIGHLIGHT_FOOTPRINT_SCALE
	local thickness = self.targetHighlightThickness or targetHighlight.Size.Y

	targetHighlight.Size = Vector3.new(footprint, thickness, footprint)
	targetHighlight.CFrame = CFrame.new(center.X, baseY, center.Z)
end

function module:destroyTargetHighlight()
	if self.targetHighlightHeartbeatConnection then
		self.targetHighlightHeartbeatConnection:Disconnect()
		self.targetHighlightHeartbeatConnection = nil
	end

	if self.targetHighlight then
		self.targetHighlight:Destroy()
		self.targetHighlight = nil
	end

	self.targetHighlightTarget = nil
end

function module:isSmartCrosshairOnCurrentTarget(screenPosition: Vector2): boolean
	if not self.assistVisualsEnabled then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local enemyModel = self.currentAutoAimTarget
	if not enemyModel then
		return false
	end

	if not EnemyTargeting.isOwnedEnemy(enemyModel, self.autoAimTag) or not EnemyTargeting.getAliveHumanoid(enemyModel) then
		return false
	end

	local aimPart = if self.currentAutoAimIsHeadshot then EnemyTargeting.getHeadPart(enemyModel) else EnemyTargeting.getGunAimPart(enemyModel)
	if not aimPart then
		return false
	end

	local viewportPoint = camera:WorldToViewportPoint(aimPart.Position)
	if viewportPoint.Z <= 0 then
		return false
	end

	local targetScreenPosition = Vector2.new(viewportPoint.X, viewportPoint.Y)
	local crosshair = self.smartCrosshair
	local crosshairRadius = if crosshair then math.max(crosshair.AbsoluteSize.X, crosshair.AbsoluteSize.Y) * 0.5 else 12
	return (targetScreenPosition - screenPosition).Magnitude <= math.max(crosshairRadius, 12)
end

function module:updateSmartCrosshair()
	if not self.assistVisualsEnabled then
		return
	end

	self:createSmartCrosshair()

	local crosshair = self.smartCrosshair
	if not crosshair then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera or not self.aimTargetInitialized then
		crosshair.Visible = false
		self:setTargetHighlightTarget(nil)
		return
	end

	local viewportPoint = camera:WorldToViewportPoint(self.springs.aimTarget.p)
	if viewportPoint.Z <= 0 then
		crosshair.Visible = false
		self:setTargetHighlightTarget(nil)
		return
	end

	local screenPosition = Vector2.new(viewportPoint.X, viewportPoint.Y)
	local parentOffset = getGuiPositionOffset(crosshair.Parent)
	crosshair.Position = UDim2.fromOffset(screenPosition.X - parentOffset.X, screenPosition.Y - parentOffset.Y)
	local isOnCurrentTarget = self:isSmartCrosshairOnCurrentTarget(screenPosition)
	if isOnCurrentTarget then
		crosshair.ImageColor3 = if self.currentAutoAimIsHeadshot
			then SMART_CROSSHAIR_HEADSHOT_TARGET_COLOR
			else SMART_CROSSHAIR_VALID_TARGET_COLOR
	else
		crosshair.ImageColor3 = self.smartCrosshairDefaultColor
	end
	crosshair.Visible = false

	self:setTargetHighlightTarget(if self.isEquipped and isOnCurrentTarget then self.currentAutoAimTarget else nil)
end

function module:createDebugParts()
	if self.debugFolder then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = `{self.gunName}Debug`
	folder.Parent = self.anchorPart and self.anchorPart.Parent or workspace

	self.debugFolder = folder
	self.debugParts = {
		targetAnchor = createDebugPart(
			"TargetAnchor",
			DEBUG_TARGET_ANCHOR_COLOR,
			Vector3.new(DEBUG_MARKER_SIZE, DEBUG_MARKER_SIZE, DEBUG_MARKER_SIZE),
			folder
		),
		springAnchor = createDebugPart(
			"SpringAnchor",
			DEBUG_SPRING_ANCHOR_COLOR,
			Vector3.new(DEBUG_MARKER_SIZE, DEBUG_MARKER_SIZE, DEBUG_MARKER_SIZE),
			folder
		),
		anchorSpringLine = createDebugLine("AnchorSpringLine", DEBUG_LINE_COLOR, folder),
	}
end

function module:destroyDebugParts()
	if self.debugFolder then
		self.debugFolder:Destroy()
	end

	self.debugFolder = nil
	self.debugParts = nil
end

function module:setDebugVisible(enabled: boolean)
	self.debugVisible = enabled == true

	if self.debugVisible then
		self:createDebugParts()
	else
		self:destroyDebugParts()
	end
end

function module:updateDebugParts(targetAnchorPosition: Vector3, springAnchorPosition: Vector3)
	if not self.debugVisible then
		return
	end

	self:createDebugParts()

	local debugParts = self.debugParts
	if not debugParts then
		return
	end

	debugParts.targetAnchor.CFrame = CFrame.new(targetAnchorPosition)
	debugParts.springAnchor.CFrame = CFrame.new(springAnchorPosition)
	updateLinePart(debugParts.anchorSpringLine, springAnchorPosition, targetAnchorPosition)
end

function module:DestroyModels()
	self:unequip()
	self:destroyDebugParts()
	self:destroySmartCrosshair()
	self:destroyTargetHighlight()
	if self.autoAimCache then
		EnemyTargeting.releaseCache(self.autoAimCache)
	end
	self.autoAimCache = nil
	self.currentAutoAimTarget = nil
	self.currentAutoAimIsHeadshot = false

	if self.gunModel then
		Debris:AddItem(self.gunModel, 0)
		self.gunModel = nil
	end

	if self.anchorPart then
		Debris:AddItem(self.anchorPart, 0)
		self.anchorPart = nil
	end
end

function module:shouldUseFrontAnchorPole(aimPoint: Vector3, rootPart: BasePart): boolean
	return isAimAngleLimitEnabled(self.gunData)
		and isAimPointOutsideAngleLimit(aimPoint, rootPart)
end

function module:getFallbackAnchorCFrame(rootPart: BasePart, useFrontPole: boolean?): CFrame
	local localCFrame = if useFrontPole then FALLBACK_FRONT_ANCHOR_LOCAL_CFRAME else FALLBACK_BACK_ANCHOR_LOCAL_CFRAME
	return rootPart.CFrame * localCFrame
end

function module:getAnchorPosition(rootPart: BasePart, useFrontPole: boolean?): Vector3
	local idleSet, aimingSet = getGunPositioningData()
	if not idleSet and not aimingSet then
		return self:getFallbackAnchorCFrame(rootPart, useFrontPole).Position
	end

	local idleLocalCFrame = getSlotLocalCFrame(idleSet, self.slotIndex)
	local aimingLocalCFrame = getSlotLocalCFrame(aimingSet, self.slotIndex)
	local placement = getAnchorPlacement(rootPart, useFrontPole)

	-- Prefer Aiming; fall back to Idle.
	local selectedLocalCFrame = aimingLocalCFrame or idleLocalCFrame
	if selectedLocalCFrame then
		return transformAnchorLocalPosition(placement, selectedLocalCFrame.Position)
	end

	return self:getFallbackAnchorCFrame(rootPart, useFrontPole).Position
end

function module:getAutoAimTarget(originPosition: Vector3): AutoAimResult?
	if not self.autoAimEnabled then
		return nil
	end

	local autoAimRange = getAutoAimRange(self.gunData)
	if autoAimRange <= 0 then
		return nil
	end

	local cache = self.autoAimCache
	if not cache then
		return nil
	end

	return EnemyTargeting.selectTarget(cache, {
		ownerTag = self.autoAimTag,
		originPosition = originPosition,
		maxDistanceSquared = autoAimRange * autoAimRange,
		currentTarget = self.currentAutoAimTarget,
		getAimPart = function(enemyModel: Model): (BasePart?, boolean)
			return getAutoAimPart(enemyModel, self.gunData)
		end,
	})
end

function module:updateAnchorFromAimPoint(aimPoint: Vector3?, hasShootTarget: boolean, rootPart: BasePart?): (CFrame?, boolean)
	rootPart = rootPart or getRootPart(self.character)
	if not rootPart then
		return nil, false
	end

	self.rootPart = rootPart
	local anchorPosition = self:getAnchorPosition(rootPart, false)

	if not aimPoint then
		aimPoint = anchorPosition + rootPart.CFrame.LookVector * AUTO_AIM_IDLE_DISTANCE
	end

	local useFrontPole = self:shouldUseFrontAnchorPole(aimPoint, rootPart)
	anchorPosition = self:getAnchorPosition(rootPart, useFrontPole)
	if isAimAngleLimitEnabled(self.gunData) then
		aimPoint = clampAimPointToPoleFacing(aimPoint, rootPart, useFrontPole)
	end

	self.lastAimPoint = aimPoint
	self.lastHasShootTarget = hasShootTarget == true

	local anchorPositionSpring = self.springs.anchorPosition
	local aimTargetSpring = self.springs.aimTarget

	if not self.anchorPositionInitialized then
		anchorPositionSpring.p = anchorPosition
		anchorPositionSpring.v = Vector3.new()
		anchorPositionSpring.target = anchorPosition
		self.anchorPositionInitialized = true
	else
		anchorPositionSpring.target = anchorPosition
	end

	if not self.aimTargetInitialized then
		aimTargetSpring.p = aimPoint
		aimTargetSpring.v = Vector3.new()
		aimTargetSpring.target = aimPoint
		self.aimTargetInitialized = true
	else
		aimTargetSpring.target = aimPoint
	end

	if self.anchorPart then
		self.anchorPart.CFrame = lookAtPoint(anchorPosition, aimPoint, rootPart.CFrame.LookVector)
	end
	self:updateDebugParts(anchorPosition, anchorPositionSpring.p)

	return lookAtPoint(anchorPositionSpring.p, aimTargetSpring.p, rootPart.CFrame.LookVector), self.lastHasShootTarget
end

function module:updateAnchor(manualAimPoint: Vector3?, manualAimOverride: boolean?): (CFrame?, boolean, boolean)
	local rootPart = getRootPart(self.character)
	if not rootPart then
		return nil, false, false
	end

	local autoAimOrigin = rootPart.Position
	local autoAimResult = self:getAutoAimTarget(autoAimOrigin)
	local autoAimPoint = if autoAimResult then autoAimResult.aimPoint else nil
	local autoAimTarget = if autoAimResult then autoAimResult.enemy else nil
	self:setCurrentAutoAimTarget(autoAimTarget, if autoAimResult then autoAimResult.isHeadshot else false)

	local hasManualAimOverride = manualAimOverride == true and manualAimPoint ~= nil
	local hasShootTarget = autoAimTarget ~= nil or hasManualAimOverride
	local aimPoint = if hasManualAimOverride then manualAimPoint else autoAimPoint
	if not aimPoint then
		aimPoint = manualAimPoint
	end

	local anchorCFrame, resolvedHasShootTarget = self:updateAnchorFromAimPoint(aimPoint, hasShootTarget, rootPart)
	return anchorCFrame, resolvedHasShootTarget, hasManualAimOverride
end

function module:getVisualReplicationState(): {[string]: any}?
	local aimPoint = self.lastAimPoint
	if not aimPoint and self.aimTargetInitialized then
		aimPoint = self.springs.aimTarget.target
	end
	if not aimPoint then
		return nil
	end

	return {
		gunId = self.gunId,
		aimPoint = aimPoint,
		hasShootTarget = self.lastHasShootTarget == true,
		shooting = self.state.shooting == true,
	}
end

function module:getMuzzleCFrame(modelPivotCFrame: CFrame?): CFrame
	if modelPivotCFrame then
		return modelPivotCFrame * self.muzzleOffset
	end

	return self.muzzleNode.CFrame
end

-- Checks the actual shot ray against the intended target from the muzzle.
function module:isMuzzleOnTarget(modelPivotCFrame: CFrame?): boolean
	if not self.aimTargetInitialized then
		return false
	end

	local muzzlePosition = self:getMuzzleCFrame(modelPivotCFrame).Position
	local shotDirection = self.springs.aimTarget.p - muzzlePosition
	local toTarget = self.springs.aimTarget.target - muzzlePosition
	if shotDirection.Magnitude <= VECTOR_EPSILON or toTarget.Magnitude <= VECTOR_EPSILON then
		return true
	end

	local alignment = shotDirection.Unit:Dot(toTarget.Unit)
	local theta = math.acos(math.clamp(alignment, -1, 1))

	return theta <= getOnTargetAngle(self.gunData)
end

function module:getSustainedRecoilMultiplier(): number
	if not isSustainedRecoilFalloffEnabled(self.gunData) then
		return 1
	end

	local startedAt = self.state.sustainedRecoilStartedAt
	if not startedAt then
		return 1
	end

	local falloffDuration = getPositiveSetting(
		self.gunData.sustainedRecoilFalloffDuration,
		DEFAULT_SUSTAINED_RECOIL_FALLOFF_DURATION
	)
	local minMultiplier = getClampedNumberSetting(
		self.gunData.sustainedRecoilMinMultiplier,
		DEFAULT_SUSTAINED_RECOIL_MIN_MULTIPLIER,
		0,
		1
	)
	local alpha = math.clamp((self.gameTime - startedAt) / falloffDuration, 0, 1)

	return 1 + (minMultiplier - 1) * alpha
end

function module:resetKickbackRotation()
	local kickbackRotationSpring = self.springs.kickbackRotation
	kickbackRotationSpring.p = 0
	kickbackRotationSpring.v = 0
	kickbackRotationSpring.target = 0
	self.kickbackRotationReturnTime = 0
end

function module:resetGunRollRecoil(hardReset: boolean?)
	self.gunRollRecoilMagnitude = 0
	self.gunRollRecoilDirection = if math.random(0, 1) == 0 then -1 else 1

	local gunRollRecoilSpring = self.springs.gunRollRecoil
	gunRollRecoilSpring.target = 0
	if hardReset then
		gunRollRecoilSpring.p = 0
		gunRollRecoilSpring.v = 0
	end
end

function module:updateKickbackRotationReturn()
	if self.kickbackRotationReturnTime <= 0 or self.gameTime < self.kickbackRotationReturnTime then
		return
	end

	self:resetKickbackRotation()
end

function module:applyKickbackRotation(modelPivotCFrame: CFrame): CFrame
	local kickbackRotation = self.springs.kickbackRotation.p
	if math.abs(kickbackRotation) <= VECTOR_EPSILON then
		return modelPivotCFrame
	end

	local primaryPartCFrame = modelPivotCFrame * self.primaryPartOffset
	local pitchAxis = primaryPartCFrame.RightVector
	if pitchAxis.Magnitude <= VECTOR_EPSILON then
		return modelPivotCFrame
	end

	local pivotPosition = primaryPartCFrame.Position
	local rotation = CFrame.fromAxisAngle(pitchAxis.Unit, kickbackRotation)
	return CFrame.new(pivotPosition) * rotation * CFrame.new(-pivotPosition) * modelPivotCFrame
end

function module:applyGunRollRecoil(modelPivotCFrame: CFrame): CFrame
	local rollRecoil = self.springs.gunRollRecoil.p
	if math.abs(rollRecoil) <= VECTOR_EPSILON then
		return modelPivotCFrame
	end

	local primaryPartCFrame = modelPivotCFrame * self.primaryPartOffset
	local rollAxis = primaryPartCFrame.LookVector
	if rollAxis.Magnitude <= VECTOR_EPSILON then
		return modelPivotCFrame
	end

	local pivotPosition = primaryPartCFrame.Position
	local rotation = CFrame.fromAxisAngle(rollAxis.Unit, rollRecoil)
	return CFrame.new(pivotPosition) * rotation * CFrame.new(-pivotPosition) * modelPivotCFrame
end

function module:applyGunRollRecoilShot()
	local maxRollRecoil = getGunRollRecoilMax(self.gunData)
	if maxRollRecoil <= 0 then
		return
	end

	self.gunRollRecoilDirection = -self.gunRollRecoilDirection
	self.gunRollRecoilMagnitude = math.min(
		self.gunRollRecoilMagnitude + getGunRollRecoilGrowth(self.gunData),
		maxRollRecoil
	)

	local noise = (math.random() * 2 - 1) * math.min(getGunRollRecoilNoise(self.gunData), maxRollRecoil)
	local targetMagnitude = math.clamp(
		self.gunRollRecoilMagnitude + noise,
		self.gunRollRecoilMagnitude * 0.5,
		maxRollRecoil
	)
	local gunRollRecoilSpring = self.springs.gunRollRecoil
	gunRollRecoilSpring.target = self.gunRollRecoilDirection * targetMagnitude
end

function module:applyShotRecoil(spreadOffset: Vector2, recoilMultiplier: number?)
	local multiplier = if recoilMultiplier then math.max(recoilMultiplier, 0) else 1
	self.springs.spreadRecoil.target = Vector3.new(
		spreadOffset.X * multiplier,
		spreadOffset.Y * multiplier,
		0
	)

	self.springs.kickback.angularFrequency = 70
	self.springs.kickback.dampingRatio = 0.85
	self.springs.kickback.target = Vector3.new(0, 0, DEFAULT_RECOIL_DISTANCE)
	self.returnRecoilTime = self.gameTime + getPositiveSetting(
		self.gunData.spreadRecoilReturnDelay,
		DEFAULT_RECOIL_RETURN_DELAY
	)

	local kickbackRotationTheta = getKickbackRotationTheta(self.gunData) * multiplier
	if kickbackRotationTheta > 0 then
		local returnDuration = getKickbackRotationReturnDuration(self.gunData)
		local kickbackRotationSpring = self.springs.kickbackRotation
		kickbackRotationSpring.angularFrequency = KICKBACK_ROTATION_SETTLE_MULTIPLIER / returnDuration
		kickbackRotationSpring.dampingRatio = DEFAULT_KICKBACK_ROTATION_DAMPING
		kickbackRotationSpring.p = math.clamp(kickbackRotationSpring.p + kickbackRotationTheta, 0, kickbackRotationTheta)
		kickbackRotationSpring.v = 0
		kickbackRotationSpring.target = 0
		self.kickbackRotationReturnTime = self.gameTime + returnDuration
	end

	self:applyGunRollRecoilShot()
end

function module:playShotEffects(
	aimPoint: Vector3?,
	modelPivotCFrame: CFrame?,
	replicatedShootCFrame: CFrame?,
	replicatedShootDirection: Vector3?,
	applyCameraRecoil: boolean?,
	applySpreadToDirection: boolean?
): (CFrame, Vector3)
	local muzzleCFrame = replicatedShootCFrame or self:getMuzzleCFrame(modelPivotCFrame)
	local direction = replicatedShootDirection
	if direction and direction.Magnitude > VECTOR_EPSILON then
		direction = direction.Unit
	elseif aimPoint and (aimPoint - muzzleCFrame.Position).Magnitude >= VECTOR_EPSILON then
		direction = (aimPoint - muzzleCFrame.Position).Unit
	else
		direction = muzzleCFrame.LookVector
	end

	if isSustainedRecoilFalloffEnabled(self.gunData) and not self.state.sustainedRecoilStartedAt then
		self.state.sustainedRecoilStartedAt = self.gameTime
	end

	local spreadOffset = sampleSpreadOffset(self.gunData.moa)
	local recoilMultiplier = self:getSustainedRecoilMultiplier()
	if applySpreadToDirection == true then
		direction = applySpreadOffset(direction, spreadOffset)
	end

	self.MuzzleFlash:play(20)
	self.MuzzleFlash:enable()
	task.delay(0.05, function()
		self.MuzzleFlash:disable()
	end)

	if self.playShotAudio then
		ProjectileAudio.playGunShot({
			sounds = self.MuzzleFlash.Sounds,
			position = muzzleCFrame.Position,
			shotInterval = getTimeBetweenShots(self.gunData),
			sourceCount = self.fireCadenceGroupSize,
			isLocalShooter = self.isLocalShooter,
		})
	end

	self:applyShotRecoil(spreadOffset, recoilMultiplier)
	if applyCameraRecoil == true and self.onClientShot then
		self.onClientShot(self.gunData, self.gunName, recoilMultiplier)
	end

	local shootCFrame = CFrame.new(muzzleCFrame.Position, muzzleCFrame.Position + direction)
	return shootCFrame, direction
end

function module:returnRecoil()
	self.springs.spreadRecoil.target = Vector3.new()
	self.springs.kickback.angularFrequency = 28
	self.springs.kickback.dampingRatio = 0.7
	self.springs.kickback.target = Vector3.new()
end

function module:getNextCadenceShotTimeAtOrAfter(scheduleTime: number): number
	local interval = self.fireCadenceInterval
	if typeof(interval) ~= "number" or interval <= 0 then
		return scheduleTime
	end

	local cadenceTime = self.fireCadenceStartTime + self.fireCadencePhaseOffset
	if scheduleTime <= cadenceTime then
		return cadenceTime
	end

	local elapsedIntervals = (scheduleTime - cadenceTime) / interval
	local cycles = math.max(0, math.ceil(elapsedIntervals))
	return cadenceTime + cycles * interval
end

function module:getNextCadenceShotTimeAfter(scheduleTime: number): number
	local interval = self.fireCadenceInterval
	if typeof(interval) ~= "number" or interval <= 0 then
		return scheduleTime
	end

	local cadenceTime = self.fireCadenceStartTime + self.fireCadencePhaseOffset
	if scheduleTime < cadenceTime then
		return cadenceTime
	end

	local elapsedIntervals = (scheduleTime - cadenceTime) / interval
	local cycles = math.max(0, math.floor(elapsedIntervals) + 1)
	return cadenceTime + cycles * interval
end

function module:setFireCadence(typeIndex: number, typeTotal: number, cadenceStartTime: number, scheduleTime: number?)
	local total = math.max(1, math.floor(typeTotal))
	local index = math.clamp(math.floor(typeIndex), 1, total)
	local interval = getTimeBetweenShots(self.gunData)
	local phaseOffset = if ALTERNATING_SHOOTING_ENABLED and total > 1 then ((index - 1) / total) * interval else 0
	local startTime = cadenceStartTime
	local currentScheduleTime = scheduleTime or self.gameTime

	-- Keep cadence stable during rapid taps.
	if currentScheduleTime - self.lastShotFireTime < interval then
		startTime = self.fireCadenceStartTime
	end

	local cadenceChanged = self.fireCadenceGroupSize ~= total
		or self.fireCadencePhaseOffset ~= phaseOffset
		or self.fireCadenceInterval ~= interval
		or self.fireCadenceStartTime ~= startTime

	self.fireCadenceGroupSize = total
	self.fireCadencePhaseOffset = phaseOffset
	self.fireCadenceInterval = interval
	self.fireCadenceStartTime = startTime

	if cadenceChanged then
		self.nextAllowedShotTime = self:getNextCadenceShotTimeAtOrAfter(currentScheduleTime)
	end
end

function module:fire(aimPoint: Vector3, modelPivotCFrame: CFrame?)
	if not self.isEquipped then
		return
	end

	local shootCFrame, direction = self:playShotEffects(aimPoint, modelPivotCFrame, nil, nil, true, true)

	if self.sendShootEvents and self.gunEvent then
		self.gunEvent:FireServer(
			"Shoot",
			self.gunId,
			shootCFrame,
			direction,
			self.projectileRays,
			self.gunName
		)
	elseif self.sendShootEvents then
		warn("Warning: Gun event cannot be founds")
	end
end

function module:playShotVisual(aimPoint: Vector3?, shootCFrame: CFrame?, shootDirection: Vector3?)
	if not self.isEquipped then
		return
	end

	self:playShotEffects(aimPoint, nil, shootCFrame, shootDirection, false, false)
end

function module:calculateBobbingTarget()
	local moveDirection = self.humanoid.MoveDirection
	local isMoving = moveDirection:Dot(moveDirection) > 0
	local moveSpeed = self.humanoid.WalkSpeed / 16
	local bobbingMultiplier = if isMoving then 0.05 else 0.005
	local gunMult = self.gunData.hipBobbingMult or 1

	self.springs.bobbing.target = Vector3.new(
		math.sin(os.clock() * 7 * moveSpeed) * bobbingMultiplier * gunMult,
		math.sin(os.clock() * 10 * moveSpeed) * bobbingMultiplier * gunMult,
		0
	)
end

function module:updateVisualSprings(step: number, shouldUpdateAssistVisuals: boolean?): CFrame?
	self:calculateBobbingTarget()

	for _, springObject in self.springs do
		springObject:update(step)
	end
	self:updateKickbackRotationReturn()
	if shouldUpdateAssistVisuals == true then
		self:updateSmartCrosshair()
	end

	local rootPart = self.rootPart
	if not rootPart then
		return nil
	end

	local anchorCFrame = lookAtPoint(self.springs.anchorPosition.p, self.springs.aimTarget.p, rootPart.CFrame.LookVector)
	self:updateDebugParts(self.springs.anchorPosition.target, self.springs.anchorPosition.p)
	local bobbingOffset = CFrame.new(self.springs.bobbing.p)
	local spreadRecoilAngle = CFrame.Angles(
		self.springs.spreadRecoil.p.X,
		self.springs.spreadRecoil.p.Y,
		self.springs.spreadRecoil.p.Z
	)
	local swayAngle = CFrame.Angles(self.springs.sway.p.X, self.springs.sway.p.Y, self.springs.sway.p.Z)
	local kickbackOffset = CFrame.new(self.springs.kickback.p)
	local gunModelCFrame = anchorCFrame * spreadRecoilAngle * bobbingOffset * swayAngle * kickbackOffset
	return gunModelCFrame * self.modelAnchorOffset:Inverse()
end

function module:pivotVisualModel(baseModelPivotCFrame: CFrame)
	local modelPivotCFrame = self:applyKickbackRotation(baseModelPivotCFrame)
	modelPivotCFrame = self:applyGunRollRecoil(modelPivotCFrame)

	self.gunModel:PivotTo(modelPivotCFrame)

	if self.returnRecoilTime > 0 and self.gameTime >= self.returnRecoilTime then
		self.returnRecoilTime = 0
		self:returnRecoil()
	end
end

function module:requestManualFire()
	self.manualFireRequested = true
end

function module:update(step: number, manualAimPoint: Vector3?, manualAimOverride: boolean?, scheduleTime: number?)
	if not self.isEquipped or not self.gunModel then
		return
	end

	self.gameTime += step
	local fireScheduleTime = scheduleTime or self.gameTime
	local anchorCFrame, hasShootTarget, usedManualAim = self:updateAnchor(manualAimPoint, manualAimOverride)
	if not anchorCFrame then
		return
	end

	local baseModelPivotCFrame = self:updateVisualSprings(step, true)
	if not baseModelPivotCFrame then
		return
	end

	-- Manual fire ignores staggered slots once each gun has cooled down.
	local manualFireReady = self.manualFireRequested
		and (fireScheduleTime - self.lastShotFireTime) >= self.fireCadenceInterval
	self.manualFireRequested = false

	if fireScheduleTime >= self.nextAllowedShotTime or manualFireReady then
		local shouldFire = hasShootTarget and (self.state.shooting or manualFireReady)

		-- Hold auto-aim shots until the muzzle is on target.
		local holdForOnTarget = shouldFire
			and not usedManualAim
			and self.requiresOnTarget ~= nil
			and self.requiresOnTarget()
			and not self:isMuzzleOnTarget(baseModelPivotCFrame)

		if not holdForOnTarget then
			if fireScheduleTime >= self.nextAllowedShotTime then
				self.nextAllowedShotTime = self:getNextCadenceShotTimeAfter(fireScheduleTime)
			end

			if shouldFire and (not self.canClientShoot or self.canClientShoot()) then
				self.lastShotFireTime = fireScheduleTime
				if manualFireReady then
					-- Re-anchor off-slot manual shots.
					self.nextAllowedShotTime = self:getNextCadenceShotTimeAtOrAfter(fireScheduleTime + self.fireCadenceInterval)
				end
				self:fire(self.springs.aimTarget.p, baseModelPivotCFrame)
			end
		end
	end

	self:pivotVisualModel(baseModelPivotCFrame)
end

function module:updateExternal(step: number, aimPoint: Vector3?, hasShootTarget: boolean?, shooting: boolean?, scheduleTime: number?)
	if not self.isEquipped or not self.gunModel then
		return
	end

	self.gameTime = scheduleTime or (self.gameTime + step)
	self:setShoot(shooting == true)
	local anchorCFrame = self:updateAnchorFromAimPoint(aimPoint, hasShootTarget == true)
	if not anchorCFrame then
		return
	end

	local baseModelPivotCFrame = self:updateVisualSprings(step, false)
	if baseModelPivotCFrame then
		self:pivotVisualModel(baseModelPivotCFrame)
	end
end

function module:setShoot(shooting: boolean)
	local shouldShoot = shooting == true
	if self.state.shooting == shouldShoot then
		return
	end

	self.state.shooting = shouldShoot
	self.state.sustainedRecoilStartedAt = nil
	self:resetGunRollRecoil(shouldShoot)
end

function module:updateSway(inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Change then
		return
	end

	local delta = inputObject.Delta
	if inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		local theta = math.atan2(inputObject.Position.Y, inputObject.Position.X)
		delta = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), theta) * Vector3.new(25 * inputObject.Position.Magnitude, 0, 0)
	end

	local verticalSway = math.rad(math.clamp(delta.Y * 0.15, -8, 8))
	local horizontalSway = math.rad(math.clamp(delta.X * 0.1, -8, 8))
	local forwardSway = math.rad(math.clamp(delta.X * 0.3, -5, 5))
	local gunMult = self.gunData.hipSwayMult or 1

	self.springs.sway.target = Vector3.new(verticalSway, horizontalSway, forwardSway) * gunMult
end

function module:toggleProjectileRays()
	self:setProjectileRays(not self.projectileRays)
end

return module
