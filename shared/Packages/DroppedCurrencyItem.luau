local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Spring = require(ReplicatedStorage.Packages.Spring)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local CurrencyAssets = GameAssets:WaitForChild("CurrencyAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets:WaitForChild("ItemDefinitions") :: ModuleScript)

local ARC_HEIGHT = 7
local COLLECT_DISTANCE = 2.5
local MAGNET_LIFETIME_SECONDS = 0.85
local MAGNET_BEZIER_DURATION = 0.4
local MIN_MAGNET_ANGULAR_FREQUENCY = 10
local MAX_MAGNET_ANGULAR_FREQUENCY = 34
local MAGNET_DAMPING_RATIO = 0.9
local FORCED_MAGNET_ANGULAR_FREQUENCY = 46
local FORCED_MAGNET_DAMPING_RATIO = 1.35
local MAGNET_MIN_LIFT = 2
local MAGNET_MAX_LIFT = 4.25
local MAGNET_MIN_OUTWARD_DISTANCE = 3
local MAGNET_MAX_OUTWARD_DISTANCE = 10
local MAGNET_SIDE_OFFSET_RADIUS = 5
local ARC_MIN_OUTWARD_DISTANCE = 1.5
local ARC_MAX_OUTWARD_DISTANCE = 3.5
local ARC_SIDE_NOISE_RADIUS = 2.25
local ARC_MIN_NOISE_AMPLITUDE = 0.35
local ARC_MAX_NOISE_AMPLITUDE = 1.2
local ARC_MIN_NOISE_FREQUENCY = 1.15
local ARC_MAX_NOISE_FREQUENCY = 1.8
local SPIN_RATE = 9
local DEFAULT_PICKUP_WEIGHT = 1
local DEFAULT_REQUIRES_MAGNET_RANGE = true
local DROP_SETTINGS = {
	Money = {
		pickupWeight = 1,
		requiresMagnetRange = false,
	},
	Dogtags = {
		pickupWeight = 2,
		requiresMagnetRange = false,
	},
}

export type DropData = {
	id: string,
	groupId: string,
	dropName: string,
	amount: number,
	pickupWeight: number?,
	requiresMagnetRange: boolean?,
	requiresServerCollect: boolean?,
	sourcePosition: Vector3,
	restPosition: Vector3,
	createdAt: number,
	landAt: number,
	expiresAt: number,
	color: Color3?,
}

export type DroppedCurrencyItem = {
	id: string,
	groupId: string,
	dropName: string,
	amount: number,
	pickupWeight: number,
	requiresMagnetRange: boolean,
	requiresServerCollect: boolean,
	visual: Instance,
	sourcePosition: Vector3,
	restPosition: Vector3,
	arcControlPointA: Vector3,
	arcControlPointB: Vector3,
	arcNoiseDirection: Vector3,
	arcNoiseAmplitude: number,
	arcNoiseFrequency: number,
	arcNoisePhase: number,
	magnetStartPosition: Vector3?,
	magnetControlPointA: Vector3?,
	magnetControlPointBOffset: Vector3,
	magnetSideDirection: Vector3,
	magnetLift: number,
	magnetOutwardDistance: number,
	magnetSideOffset: number,
	position: Vector3,
	magnetSpring: any?,
	magnetStartedAt: number?,
	createdAt: number,
	landAt: number,
	expiresAt: number,
	isMagnetized: boolean,
	canDelete: boolean,
	didCollect: boolean,
	Update: (self: DroppedCurrencyItem, deltaTime: number, target: BasePart?, magnetRange: number) -> (),
	Destroy: (self: DroppedCurrencyItem) -> (),
}

local DroppedCurrencyItem = {}
DroppedCurrencyItem.__index = DroppedCurrencyItem

local function setVisualCFrame(visual: Instance, cframe: CFrame)
	if visual:IsA("BasePart") then
		visual.CFrame = cframe
	elseif visual:IsA("Model") then
		visual:PivotTo(cframe)
	end
end

local function getRandomHorizontalUnitVector(random: Random): Vector3
	local angle = random:NextNumber(0, math.pi * 2)

	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function cubicBezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, alpha: number): Vector3
	local a = p0:Lerp(p1, alpha)
	local b = p1:Lerp(p2, alpha)
	local c = p2:Lerp(p3, alpha)
	local d = a:Lerp(b, alpha)
	local e = b:Lerp(c, alpha)

	return d:Lerp(e, alpha)
end

local function getDropSettings(dropName: string): (number, boolean)
	local settings = DROP_SETTINGS[dropName]
	if not settings then
		return DEFAULT_PICKUP_WEIGHT, DEFAULT_REQUIRES_MAGNET_RANGE
	end

	return math.max(0.01, settings.pickupWeight), settings.requiresMagnetRange
end

local function getDropTemplate(dropName: string): Instance?
	if dropName == "Dogtags" then
		return CurrencyAssets:WaitForChild("DogtagPickup")
	elseif dropName == "Money" then
		return CurrencyAssets:WaitForChild("MoneyPickup")
	end

	local itemDef = ItemDefinitions[dropName]
	if itemDef and itemDef.model then
		return itemDef.model
	end

	warn(`[DroppedCurrencyItem] No visual model found for drop "{dropName}".`)
	return nil
end

local function getArcData(sourcePosition: Vector3, restPosition: Vector3, random: Random)
	local horizontalDelta = Vector3.new(restPosition.X - sourcePosition.X, 0, restPosition.Z - sourcePosition.Z)
	local outwardDirection = if horizontalDelta.Magnitude > 0.001 then horizontalDelta.Unit else getRandomHorizontalUnitVector(random)
	local sideDirection = Vector3.yAxis:Cross(outwardDirection)
	if sideDirection.Magnitude <= 0.001 then
		sideDirection = getRandomHorizontalUnitVector(random)
	else
		sideDirection = sideDirection.Unit
	end

	local maxY = math.max(sourcePosition.Y, restPosition.Y)
	local sideA = sideDirection * random:NextNumber(-ARC_SIDE_NOISE_RADIUS, ARC_SIDE_NOISE_RADIUS)
	local sideB = sideDirection * random:NextNumber(-ARC_SIDE_NOISE_RADIUS, ARC_SIDE_NOISE_RADIUS)
	local controlPointA = Vector3.new(sourcePosition.X, maxY + ARC_HEIGHT * random:NextNumber(0.75, 1.15), sourcePosition.Z)
		+ outwardDirection * random:NextNumber(ARC_MIN_OUTWARD_DISTANCE, ARC_MAX_OUTWARD_DISTANCE)
		+ sideA
	local controlPointB = Vector3.new(restPosition.X, maxY + ARC_HEIGHT * random:NextNumber(0.35, 0.7), restPosition.Z)
		- outwardDirection * random:NextNumber(0.5, 2)
		+ sideB

	return controlPointA,
		controlPointB,
		sideDirection,
		random:NextNumber(ARC_MIN_NOISE_AMPLITUDE, ARC_MAX_NOISE_AMPLITUDE),
		random:NextNumber(ARC_MIN_NOISE_FREQUENCY, ARC_MAX_NOISE_FREQUENCY),
		random:NextNumber(0, math.pi * 2)
end

function DroppedCurrencyItem.new(dropData: DropData): DroppedCurrencyItem?
	if typeof(dropData.dropName) ~= "string" then
		warn("[DroppedCurrencyItem] Drop payload is missing dropName.")
		return nil
	end

	local dropName = dropData.dropName
	local template = getDropTemplate(dropName)
	if not template then
		return nil
	end

	local visual = template:Clone()
	local hash = 0
	for index = 1, #dropData.id do
		hash = (hash * 31 + string.byte(dropData.id, index)) % 2147483647
	end
	local random = Random.new(hash)
	local arcControlPointA, arcControlPointB, arcNoiseDirection, arcNoiseAmplitude, arcNoiseFrequency, arcNoisePhase =
		getArcData(dropData.sourcePosition, dropData.restPosition, random)
	local defaultPickupWeight, defaultRequiresMagnetRange = getDropSettings(dropName)
	local pickupWeight = if typeof(dropData.pickupWeight) == "number"
		then math.max(0.01, dropData.pickupWeight)
		else defaultPickupWeight
	local requiresMagnetRange = if typeof(dropData.requiresMagnetRange) == "boolean"
		then dropData.requiresMagnetRange
		else defaultRequiresMagnetRange
	local requiresServerCollect = if typeof(dropData.requiresServerCollect) == "boolean"
		then dropData.requiresServerCollect
		else dropName ~= "Money" and dropName ~= "Dogtags"

	if visual:IsA("BasePart") then
		visual.Anchored = true
		visual.CanCollide = false
		visual.CanTouch = false
		visual.CanQuery = false
	end

	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	if dropData.color then
		local beam = visual:FindFirstChild("Beam", true)
		if beam and beam:IsA("Beam") then
			beam.Color = ColorSequence.new(dropData.color)
		end

		local textLabel = visual:FindFirstChild("TextLabel", true)
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.TextColor3 = dropData.color
		end

		local backgroundGlow = visual:FindFirstChild("BackgroundGlow", true)
		if backgroundGlow and backgroundGlow:IsA("ImageLabel") then
			backgroundGlow.ImageColor3 = dropData.color
		end
	end

	setVisualCFrame(visual, CFrame.new(dropData.sourcePosition))
	visual.Parent = Workspace.CurrentCamera or Workspace

	Debris:AddItem(visual, math.max(1, dropData.expiresAt - Workspace:GetServerTimeNow() + 5))

	local self: DroppedCurrencyItem = {
		id = dropData.id,
		groupId = dropData.groupId,
		dropName = dropName,
		amount = dropData.amount,
		pickupWeight = pickupWeight,
		requiresMagnetRange = requiresMagnetRange,
		requiresServerCollect = requiresServerCollect,
		visual = visual,
		sourcePosition = dropData.sourcePosition,
		restPosition = dropData.restPosition,
		arcControlPointA = arcControlPointA,
		arcControlPointB = arcControlPointB,
		arcNoiseDirection = arcNoiseDirection,
		arcNoiseAmplitude = arcNoiseAmplitude,
		arcNoiseFrequency = arcNoiseFrequency,
		arcNoisePhase = arcNoisePhase,
		magnetStartPosition = nil,
		magnetControlPointA = nil,
		magnetControlPointBOffset = Vector3.zero,
		magnetSideDirection = getRandomHorizontalUnitVector(random),
		magnetLift = random:NextNumber(MAGNET_MIN_LIFT, MAGNET_MAX_LIFT),
		magnetOutwardDistance = random:NextNumber(MAGNET_MIN_OUTWARD_DISTANCE, MAGNET_MAX_OUTWARD_DISTANCE),
		magnetSideOffset = random:NextNumber(-MAGNET_SIDE_OFFSET_RADIUS, MAGNET_SIDE_OFFSET_RADIUS),
		position = dropData.sourcePosition,
		magnetSpring = nil,
		magnetStartedAt = nil,
		createdAt = dropData.createdAt,
		landAt = dropData.landAt,
		expiresAt = dropData.expiresAt,
		isMagnetized = false,
		canDelete = false,
		didCollect = false,
	}

	setmetatable(self :: any, DroppedCurrencyItem)
	return self
end

function DroppedCurrencyItem:Update(deltaTime: number, target: BasePart?, magnetRange: number)
	local self = self :: DroppedCurrencyItem
	local now = Workspace:GetServerTimeNow()
	magnetRange = math.max(0, magnetRange)

	if now >= self.expiresAt then
		self.canDelete = true
		return
	end

	if now < self.landAt then
		local duration = math.max(0.05, self.landAt - self.createdAt)
		local alpha = math.clamp((now - self.createdAt) / duration, 0, 1)
		local easedAlpha = 1 - (1 - alpha) * (1 - alpha)
		local noiseScale = math.sin(math.pi * easedAlpha)
		local noiseOffset = self.arcNoiseDirection
			* math.sin((easedAlpha * self.arcNoiseFrequency * math.pi * 2) + self.arcNoisePhase)
			* self.arcNoiseAmplitude
			* noiseScale

		self.position = cubicBezier(
			self.sourcePosition,
			self.arcControlPointA,
			self.arcControlPointB,
			self.restPosition,
			easedAlpha
		) + noiseOffset
	else
		if not self.isMagnetized then
			self.position = self.restPosition
		end

		if target then
			local targetPosition = target.Position
			local isInMagnetRange = (targetPosition - self.restPosition).Magnitude <= magnetRange
			if self.isMagnetized or not self.requiresMagnetRange or isInMagnetRange then
				if not self.isMagnetized then
					self.isMagnetized = true
					self.magnetStartedAt = now
					self.magnetStartPosition = self.position
					local horizontalDelta = Vector3.new(self.position.X - targetPosition.X, 0, self.position.Z - targetPosition.Z)
					local awayDirection = if horizontalDelta.Magnitude > 0.001 then horizontalDelta.Unit else self.magnetSideDirection
					self.magnetControlPointA = self.position
						+ awayDirection * self.magnetOutwardDistance
						+ self.magnetSideDirection * self.magnetSideOffset
						+ Vector3.yAxis * self.magnetLift
					self.magnetControlPointBOffset = self.magnetSideDirection * (self.magnetSideOffset * 0.35)
						+ Vector3.yAxis * (self.magnetLift * 0.25)
					self.magnetSpring = Spring.new(
						self.position,
						Vector3.zero,
						self.position,
						MIN_MAGNET_ANGULAR_FREQUENCY,
						MAGNET_DAMPING_RATIO
					)
				end

				local magnetSpring = self.magnetSpring
				if magnetSpring then
					local distanceToTarget = (targetPosition - self.position).Magnitude
					local range = math.max(1, magnetRange)
					local closeness = 1 - math.clamp(distanceToTarget / range, 0, 1)
					local strength = closeness * closeness
					local pickupWeight = math.max(0.01, self.pickupWeight)
					local magnetAge = if self.magnetStartedAt then (now - self.magnetStartedAt) / pickupWeight else 0
					local shouldForceToTarget = magnetAge >= MAGNET_LIFETIME_SECONDS
					local springTarget = targetPosition
					if not shouldForceToTarget then
						local bezierAlpha = math.clamp(magnetAge / MAGNET_BEZIER_DURATION, 0, 1)
						if bezierAlpha < 1 then
							local startPosition = self.magnetStartPosition or self.position
							local controlPointA = self.magnetControlPointA or startPosition
							local controlPointB = targetPosition + self.magnetControlPointBOffset
							local easedBezierAlpha = bezierAlpha * bezierAlpha
							springTarget = cubicBezier(startPosition, controlPointA, controlPointB, targetPosition, easedBezierAlpha)
						end
					end

					magnetSpring.target = springTarget
					if shouldForceToTarget then
						magnetSpring.angularFrequency = FORCED_MAGNET_ANGULAR_FREQUENCY
						magnetSpring.dampingRatio = FORCED_MAGNET_DAMPING_RATIO
					else
						local ageBoost = math.clamp(magnetAge / MAGNET_LIFETIME_SECONDS, 0, 1)
						local frequencyAlpha = math.max(strength, ageBoost * 0.65)
						magnetSpring.angularFrequency = MIN_MAGNET_ANGULAR_FREQUENCY
							+ (MAX_MAGNET_ANGULAR_FREQUENCY - MIN_MAGNET_ANGULAR_FREQUENCY) * frequencyAlpha
						magnetSpring.dampingRatio = MAGNET_DAMPING_RATIO
					end

					magnetSpring:update(deltaTime / pickupWeight)
					self.position = magnetSpring.p
				end

				if (targetPosition - self.position).Magnitude <= COLLECT_DISTANCE then
					self.didCollect = true
					self.canDelete = true
				end
			end
		end
	end

	local camera = Workspace.CurrentCamera
	local lookAtPosition = if camera then camera.CFrame.Position else self.position + Vector3.zAxis
	local spin = CFrame.Angles(0, now * SPIN_RATE, 0)
	setVisualCFrame(self.visual, CFrame.new(self.position, lookAtPosition) * spin)
end

function DroppedCurrencyItem:Destroy()
	local self = self :: DroppedCurrencyItem
	self.visual:Destroy()
	self.magnetSpring = nil
end

return DroppedCurrencyItem
