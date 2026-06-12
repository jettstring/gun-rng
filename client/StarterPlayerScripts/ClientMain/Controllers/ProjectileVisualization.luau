local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local gunKitRemotes = remotesFolder:WaitForChild("GunKit")
local remotes = {
	ProjectileVisuals = gunKitRemotes:WaitForChild("ProjectileVisuals"),
}

local ProjectileAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("ProjectileAssets"):WaitForChild("Bullets")
local ProjectileAudio = require(ReplicatedStorage.Packages.ProjectileAudio)
local LocalPlayer = Players.LocalPlayer

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type ProjectilePathEvent = {
	sequence: number,
	serverTime: number,
	position: Vector3,
	lookDirection: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	reason: string,
	normal: Vector3?,
	impactPosition: Vector3?,
	effectType: string?,
	soundType: string?,
	cosmeticArcTargetPosition: Vector3?,
	cosmeticArcSideSign: number?,
}

type ProjectileEndEvent = {
	sequence: number,
	serverEndTime: number,
	endPosition: Vector3,
	lookDirection: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	reason: string,
	normal: Vector3?,
	impactPosition: Vector3?,
	effectType: string?,
	soundType: string?,
}

type ProjectileTrail = {
	trail: Trail,
	maxLength: number?,
	originalEnabled: boolean,
	attachment0: Attachment?,
	attachment1: Attachment?,
	attachment0OriginalPosition: Vector3?,
	attachment1OriginalPosition: Vector3?,
	attachment0CollapsedPosition: Vector3?,
	attachment1CollapsedPosition: Vector3?,
}

type ProjectilePart = {
	part: BasePart,
	originalLocalTransparencyModifier: number,
}

type PendingProjectileEvent = {
	eventType: "Segment" | "End",
	payload: {[string]: any},
}

type IgnoredProjectile = {
	ignoredUntil: number,
	playTerminalSound: boolean,
	clearOnEnd: boolean,
}

type ActiveProjectile = {
	visual: Instance,
	visualRotationOffset: CFrame,
	impactTemplate: BasePart?,
	trails: {ProjectileTrail},
	parts: {ProjectilePart},
	bulletVisible: boolean,
	trailsFullyExpanded: boolean,
	showDelayDistanceTraveled: number,
	lastShowDelayDistancePosition: Vector3?,
	maxDistance: number?,
	distanceTraveled: number,
	lastDistancePosition: Vector3,
	maxLifetime: number,
	createdServerTime: number,
	currentSegment: ProjectilePathEvent,
	lastSequence: number,
	lastRenderPosition: Vector3?,
	endEvent: ProjectileEndEvent?,
	destroyAfterServerTime: number?,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local ProjectileVisualization = {}
ProjectileVisualization.Controllers = {}
ProjectileVisualization.Signals = {}
ProjectileVisualization.Projectiles = {} :: {[string]: ActiveProjectile}
ProjectileVisualization.PendingEvents = {} :: {[string]: {PendingProjectileEvent}}
ProjectileVisualization.IgnoredProjectiles = {} :: {[string]: IgnoredProjectile}
ProjectileVisualization.ShowOtherPlayerProjectiles = true
ProjectileVisualization.updateConnection = nil :: RBXScriptConnection?
ProjectileVisualization.visualsConnection = nil :: RBXScriptConnection?

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local DEFAULT_PROJECTILE_TYPE = "Normal"
local BULLET_CHILD_NAME = "Bullet"
local IMPACT_CHILD_NAME = "Impact"
local INTERPOLATION_DELAY = 0.075
local MAX_BUFFERED_EVENTS = 16
local PENDING_EVENT_TIMEOUT = 1
local BULLET_SHOW_DELAY_DISTANCE = 2
local TRAIL_SHOW_DELAY_DISTANCE = 5
local HIT_EFFECT_LIFETIME = 1
local HIT_EFFECT_POOL_MAX_PER_NODE = 32
local VECTOR_EPSILON = 1e-6
local PROJECTILE_PARENT = Workspace:WaitForChild("RAY_IGNORE")
local PROJECTILE_VISUAL_PREFIX = "ProjectileVisual_"
local FALLBACK_LOOK_DIRECTION = Vector3.new(0, 0, -1)
local SMART_COSMETIC_ARC_DISTANCE_FRACTION = 0.16
local SMART_COSMETIC_ARC_MAX_OFFSET = 10
local DEBUG_PROJECTILE_VISUALS = false
local DEBUG_ID_LIMIT = 12
local DEBUG_BATCH_INTERVAL = 30
local nextClientDebugSequence = 0
local hitEffectPools = {} :: {[Instance]: {Instance}}
local activeHitEffects = {} :: {[Instance]: boolean}
local hitEffectPoolGeneration = 0

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function debugProjectileVisuals(...: any)
	if DEBUG_PROJECTILE_VISUALS then
		print("[ProjectileVisualization]", ...)
	end
end

local function getDebugPayloadId(payload: any): string
	return tostring(payload.id or payload)
end

local function getDebugPayloadIds(payloads: {any}): string
	if #payloads == 0 then
		return "-"
	end

	local ids = {}
	for index, payload in ipairs(payloads) do
		if index > DEBUG_ID_LIMIT then
			table.insert(ids, `+{#payloads - DEBUG_ID_LIMIT}`)
			break
		end

		table.insert(ids, getDebugPayloadId(payload))
	end

	return table.concat(ids, ",")
end

local function getDebugPayloadReasonIds(payloads: {any}): string
	if #payloads == 0 then
		return "-"
	end

	local ids = {}
	for _, payload in ipairs(payloads) do
		local reason = payload.reason
		if reason and reason ~= "" then
			table.insert(ids, `{getDebugPayloadId(payload)}:{reason}`)
		else
			table.insert(ids, getDebugPayloadId(payload))
		end
		if #ids >= DEBUG_ID_LIMIT then
			break
		end
	end

	if #ids == 0 then
		return "-"
	end

	return table.concat(ids, ",")
end

local function getProjectileId(payload: any): string?
	local projectileId = payload.id
	if projectileId then
		return tostring(projectileId)
	end

	return nil
end

local function getCollapsedAttachmentPosition(attachment: Attachment, worldCenter: Vector3): Vector3
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame:PointToObjectSpace(worldCenter)
	end

	return attachment.Position
end

local function getProjectileTrails(visual: Instance): {ProjectileTrail}
	local trails = {} :: {ProjectileTrail}
	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("Trail") then
			local attachment0 = descendant.Attachment0
			local attachment1 = descendant.Attachment1
			local attachment0CollapsedPosition = nil
			local attachment1CollapsedPosition = nil
			if attachment0 and attachment1 then
				local worldCenter = (attachment0.WorldPosition + attachment1.WorldPosition) * 0.5
				attachment0CollapsedPosition = getCollapsedAttachmentPosition(attachment0, worldCenter)
				attachment1CollapsedPosition = getCollapsedAttachmentPosition(attachment1, worldCenter)
			end

			local maxLength = if descendant.MaxLength > 0 then descendant.MaxLength else nil
			table.insert(trails, {
				trail = descendant,
				maxLength = maxLength,
				originalEnabled = descendant.Enabled,
				attachment0 = attachment0,
				attachment1 = attachment1,
				attachment0OriginalPosition = if attachment0 then attachment0.Position else nil,
				attachment1OriginalPosition = if attachment1 then attachment1.Position else nil,
				attachment0CollapsedPosition = attachment0CollapsedPosition,
				attachment1CollapsedPosition = attachment1CollapsedPosition,
			})
		end
	end

	return trails
end

local function getProjectileParts(visual: Instance): {ProjectilePart}
	local parts = {} :: {ProjectilePart}
	if visual:IsA("BasePart") then
		table.insert(parts, {
			part = visual,
			originalLocalTransparencyModifier = visual.LocalTransparencyModifier,
		})
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, {
				part = descendant,
				originalLocalTransparencyModifier = descendant.LocalTransparencyModifier,
			})
		end
	end

	return parts
end

local function setProjectilePartsVisible(parts: {ProjectilePart}, visible: boolean)
	for _, projectilePart in ipairs(parts) do
		projectilePart.part.LocalTransparencyModifier = if visible then projectilePart.originalLocalTransparencyModifier else 1
	end
end

local function setTrailAttachmentRamp(trails: {ProjectileTrail}, alpha: number)
	alpha = math.clamp(alpha, 0, 1)
	for _, projectileTrail in ipairs(trails) do
		local attachment0 = projectileTrail.attachment0
		local attachment1 = projectileTrail.attachment1
		local attachment0OriginalPosition = projectileTrail.attachment0OriginalPosition
		local attachment1OriginalPosition = projectileTrail.attachment1OriginalPosition
		local attachment0CollapsedPosition = projectileTrail.attachment0CollapsedPosition
		local attachment1CollapsedPosition = projectileTrail.attachment1CollapsedPosition
		if
			attachment0
			and attachment1
			and attachment0OriginalPosition
			and attachment1OriginalPosition
			and attachment0CollapsedPosition
			and attachment1CollapsedPosition
		then
			attachment0.Position = attachment0CollapsedPosition:Lerp(attachment0OriginalPosition, alpha)
			attachment1.Position = attachment1CollapsedPosition:Lerp(attachment1OriginalPosition, alpha)
		end
	end
end

local function normalizeTrailLifetimes(trails: {ProjectileTrail}, velocity: Vector3)
	local speed = velocity.Magnitude
	if speed <= VECTOR_EPSILON then
		return
	end

	for _, projectileTrail in ipairs(trails) do
		if projectileTrail.trail:HasTag("UnlimitedTrail") then
			continue
		end
		local maxLength = projectileTrail.maxLength
		if not maxLength then
			continue
		end
		projectileTrail.trail.Lifetime = maxLength / speed
	end
end

local function updateProjectileVisibility(projectile: ActiveProjectile, position: Vector3)
	if projectile.bulletVisible and projectile.trailsFullyExpanded then
		return
	end

	local lastShowDelayDistancePosition = projectile.lastShowDelayDistancePosition
	if lastShowDelayDistancePosition then
		projectile.showDelayDistanceTraveled += (position - lastShowDelayDistancePosition).Magnitude
	end
	projectile.lastShowDelayDistancePosition = position

	if not projectile.bulletVisible and projectile.showDelayDistanceTraveled >= BULLET_SHOW_DELAY_DISTANCE then
		projectile.bulletVisible = true
		setProjectilePartsVisible(projectile.parts, true)
	end

	if not projectile.trailsFullyExpanded then
		local trailRampAlpha = if TRAIL_SHOW_DELAY_DISTANCE <= 0
			then 1
			else projectile.showDelayDistanceTraveled / TRAIL_SHOW_DELAY_DISTANCE
		setTrailAttachmentRamp(projectile.trails, trailRampAlpha)
		if trailRampAlpha >= 1 then
			projectile.trailsFullyExpanded = true
		end
	end
end

local function getVector(payload: {[string]: any}, key: string, fallback: Vector3): Vector3
	return payload[key] or fallback
end

local function getPayloadPosition(payload: {[string]: any}, fallback: Vector3?): Vector3?
	return payload.position or payload.origin or fallback
end

local function getLookDirection(direction: Vector3): Vector3
	if direction.Magnitude > VECTOR_EPSILON then
		return direction.Unit
	end

	return FALLBACK_LOOK_DIRECTION
end

local function getVisualCFrame(position: Vector3, lookDirection: Vector3, visualRotationOffset: CFrame?): CFrame
	local direction = getLookDirection(lookDirection)
	return CFrame.new(position, position + direction) * (visualRotationOffset or CFrame.new())
end

local function pivotVisual(visual: Instance, cframe: CFrame)
	if visual:IsA("Model") then
		visual:PivotTo(cframe)
	elseif visual:IsA("BasePart") then
		visual.CFrame = cframe
	end
end

local function resetEffectNode(effect: Instance)
	if effect:IsA("ParticleEmitter") then
		effect:Clear()
	elseif effect:IsA("Sound") then
		effect:Stop()
		effect.TimePosition = 0
	end

	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Clear()
		elseif descendant:IsA("Sound") then
			descendant:Stop()
			descendant.TimePosition = 0
		end
	end
end

-- Plays a projectile's "Impact" part: positions a (pooled) clone at the hit
-- point, plays every Sound descendant, and emits every ParticleEmitter
-- descendant with a burst count equal to that emitter's own Rate.
local function playImpactEffect(impactTemplate: BasePart, position: Vector3, lookDirection: Vector3)
	local effect: BasePart
	local pool = hitEffectPools[impactTemplate]
	if pool and #pool > 0 then
		effect = pool[#pool] :: BasePart
		pool[#pool] = nil
	else
		effect = impactTemplate:Clone() :: BasePart
	end

	resetEffectNode(effect)
	effect.CFrame = getVisualCFrame(position, lookDirection, nil)
	effect.Parent = PROJECTILE_PARENT

	for _, descendant in ipairs(effect:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(descendant.Rate)
		elseif descendant:IsA("Sound") then
			descendant:Play()
		end
	end

	activeHitEffects[effect] = true
	local effectGeneration = hitEffectPoolGeneration
	task.delay(HIT_EFFECT_LIFETIME, function()
		if effectGeneration ~= hitEffectPoolGeneration or not activeHitEffects[effect] then
			activeHitEffects[effect] = nil
			effect:Destroy()
			return
		end

		activeHitEffects[effect] = nil
		resetEffectNode(effect)
		effect.Parent = nil

		local returnPool = hitEffectPools[impactTemplate]
		if not returnPool then
			returnPool = {}
			hitEffectPools[impactTemplate] = returnPool
		end

		if #returnPool >= HIT_EFFECT_POOL_MAX_PER_NODE then
			effect:Destroy()
			return
		end

		table.insert(returnPool, effect)
	end)
end

local function playProjectileEffect(impactTemplate: BasePart?, event: {[string]: any})
	local effectType = event.effectType
	if event.reason == "range" or effectType == "range" then
		return
	end

	local soundType = event.soundType
	if (not effectType or effectType == "") and (not soundType or soundType == "") then
		return
	end

	local effectPosition = event.impactPosition or event.endPosition or event.position
	if not effectPosition then
		return
	end

	-- Special-case audio cues are routed through the dedicated audio package.
	if effectType == "forcefield" then
		ProjectileAudio.playForceFieldHit(effectPosition)
	end

	if impactTemplate then
		local lookDirection = getVector(event, "lookDirection", FALLBACK_LOOK_DIRECTION)
		playImpactEffect(impactTemplate, effectPosition, lookDirection)
	end
end

local function createPathEvent(payload: {[string]: any}, defaultReason: string): ProjectilePathEvent?
	local serverTime = payload.serverTime or payload.serverStartTime
	local position = getPayloadPosition(payload, nil)
	if not serverTime or not position then
		return nil
	end

	local lookDirection = getLookDirection(getVector(payload, "lookDirection", getVector(payload, "direction", FALLBACK_LOOK_DIRECTION)))
	return {
		sequence = payload.sequence or 0,
		serverTime = serverTime,
		position = position,
		lookDirection = lookDirection,
		velocity = getVector(payload, "velocity", Vector3.new()),
		acceleration = getVector(payload, "acceleration", Vector3.new()),
		reason = payload.reason or defaultReason,
		normal = payload.normal,
		impactPosition = payload.impactPosition,
		effectType = payload.effectType,
		soundType = payload.soundType,
		cosmeticArcTargetPosition = payload.cosmeticArcTargetPosition,
		cosmeticArcSideSign = payload.cosmeticArcSideSign or 1,
	}
end

local function createEndEvent(payload: {[string]: any}): ProjectileEndEvent?
	local serverEndTime = payload.serverEndTime or payload.serverTime
	local endPosition = payload.endPosition or getPayloadPosition(payload, nil)
	if not serverEndTime or not endPosition then
		return nil
	end

	local lookDirection = getLookDirection(getVector(payload, "lookDirection", getVector(payload, "direction", FALLBACK_LOOK_DIRECTION)))
	return {
		sequence = payload.sequence or 0,
		serverEndTime = serverEndTime,
		endPosition = endPosition,
		lookDirection = lookDirection,
		velocity = getVector(payload, "velocity", Vector3.new()),
		acceleration = getVector(payload, "acceleration", Vector3.new()),
		reason = payload.reason or "end",
		normal = payload.normal,
		impactPosition = payload.impactPosition,
		effectType = payload.effectType,
		soundType = payload.soundType,
	}
end

local function getPendingEventTime(event: PendingProjectileEvent): number
	local payload = event.payload
	return payload.serverEndTime or payload.serverTime or payload.serverStartTime or 0
end

local function evaluateSegment(segment: ProjectilePathEvent, renderTime: number): (Vector3, Vector3)
	local elapsedTime = math.max(renderTime - segment.serverTime, 0)
	local basePosition = segment.position
		+ segment.velocity * elapsedTime
		+ 0.5 * segment.acceleration * elapsedTime * elapsedTime
	local position = basePosition
	local cosmeticArcTargetPosition = segment.cosmeticArcTargetPosition
	if cosmeticArcTargetPosition then
		local targetOffset = cosmeticArcTargetPosition - segment.position
		local flatTargetOffset = Vector3.new(targetOffset.X, 0, targetOffset.Z)
		local flatDistanceSquared = flatTargetOffset:Dot(flatTargetOffset)
		if flatDistanceSquared > VECTOR_EPSILON then
			local flatDistance = math.sqrt(flatDistanceSquared)
			local flatTravelOffset = Vector3.new(
				basePosition.X - segment.position.X,
				0,
				basePosition.Z - segment.position.Z
			)
			local progress = math.clamp(flatTravelOffset:Dot(flatTargetOffset) / flatDistanceSquared, 0, 1)
			local arcAlpha = math.sin(progress * math.pi)
			if arcAlpha > 0 then
				local flatDirection = flatTargetOffset / flatDistance
				local sideDirection = Vector3.new(-flatDirection.Z, 0, flatDirection.X) * (segment.cosmeticArcSideSign or 1)
				local arcOffset = math.min(
					flatDistance * SMART_COSMETIC_ARC_DISTANCE_FRACTION,
					SMART_COSMETIC_ARC_MAX_OFFSET
				)
				position = basePosition + (sideDirection * arcOffset * arcAlpha)
			end
		end
	end
	local direction = position - segment.position
	if direction.Magnitude <= VECTOR_EPSILON then
		direction = segment.lookDirection
	end

	return position, direction
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ProjectileVisualization:DestroyProjectile(projectileId: string)
	local projectile = self.Projectiles[projectileId]
	local hadTrackedProjectile = projectile ~= nil
	if projectile then
		projectile.visual:Destroy()
		self.Projectiles[projectileId] = nil
	end

	local visualName = `{PROJECTILE_VISUAL_PREFIX}{projectileId}`
	local destroyedExactVisuals = 0
	local visual = PROJECTILE_PARENT:FindFirstChild(visualName)
	while visual do
		visual:Destroy()
		destroyedExactVisuals += 1
		visual = PROJECTILE_PARENT:FindFirstChild(visualName)
	end

	if DEBUG_PROJECTILE_VISUALS then
		debugProjectileVisuals(
			"destroy visual",
			projectileId,
			"tracked",
			hadTrackedProjectile,
			"exactChildren",
			destroyedExactVisuals
		)
	end
end

function ProjectileVisualization:IgnoreProjectile(
	projectileId: string,
	ignoredUntil: number,
	playTerminalSound: boolean,
	clearOnEnd: boolean
)
	self.IgnoredProjectiles[projectileId] = {
		ignoredUntil = ignoredUntil,
		playTerminalSound = playTerminalSound,
		clearOnEnd = clearOnEnd,
	}
	self.PendingEvents[projectileId] = nil
end

function ProjectileVisualization:BufferPendingEvent(
	projectileId: string,
	eventType: "Segment" | "End",
	payload: {[string]: any}
)
	local pendingEvents = self.PendingEvents[projectileId]
	if not pendingEvents then
		pendingEvents = {}
		self.PendingEvents[projectileId] = pendingEvents
	end

	table.insert(pendingEvents, {
		eventType = eventType,
		payload = payload,
	})
	table.sort(pendingEvents, function(left, right)
		local leftSequence = left.payload.sequence or 0
		local rightSequence = right.payload.sequence or 0
		if leftSequence == rightSequence then
			return getPendingEventTime(left) < getPendingEventTime(right)
		end

		return leftSequence < rightSequence
	end)

	while #pendingEvents > MAX_BUFFERED_EVENTS do
		table.remove(pendingEvents, 1)
	end
end

function ProjectileVisualization:ApplySegment(projectile: ActiveProjectile, segment: ProjectilePathEvent)
	if segment.sequence <= projectile.lastSequence then
		return
	end

	projectile.currentSegment = segment
	projectile.lastSequence = segment.sequence
	normalizeTrailLifetimes(projectile.trails, segment.velocity)
	playProjectileEffect(projectile.impactTemplate, segment)
end

function ProjectileVisualization:ApplyEnd(projectile: ActiveProjectile, projectileId: string, endEvent: ProjectileEndEvent)
	if endEvent.sequence <= projectile.lastSequence then
		return
	end

	projectile.lastSequence = endEvent.sequence
	projectile.endEvent = endEvent
	normalizeTrailLifetimes(projectile.trails, endEvent.velocity)
	projectile.destroyAfterServerTime = endEvent.serverEndTime + INTERPOLATION_DELAY
	playProjectileEffect(projectile.impactTemplate, endEvent)

	if DEBUG_PROJECTILE_VISUALS then
		debugProjectileVisuals("end event", projectileId, endEvent.sequence, endEvent.reason, endEvent.serverEndTime)
	end
end

function ProjectileVisualization:HandleProjectileBatch(payload: {[string]: any})
	local spawns = payload.spawns or {}
	local segments = payload.segments or {}
	local ends = payload.ends or {}
	if DEBUG_PROJECTILE_VISUALS then
		nextClientDebugSequence += 1
		local serverDebugSequence = payload.debugSequence or 0
		local spawnCount = #spawns
		local segmentCount = #segments
		local endCount = #ends
		local shouldDebugBatch = spawnCount > 0
			or segmentCount > 0
			or endCount > 0
			or serverDebugSequence % DEBUG_BATCH_INTERVAL == 0
		if shouldDebugBatch then
			debugProjectileVisuals(
				"recv batch",
				nextClientDebugSequence,
				"server",
				serverDebugSequence,
				"spawns",
				spawnCount,
				getDebugPayloadIds(spawns),
				"segments",
				segmentCount,
				getDebugPayloadReasonIds(segments),
				"ends",
				endCount,
				getDebugPayloadReasonIds(ends)
			)
		end
	end

	for _, spawnPayload in ipairs(spawns) do
		self:SpawnProjectile(spawnPayload)
	end

	for _, segmentPayload in ipairs(segments) do
		self:HandleProjectileSegment(segmentPayload)
	end

	for _, endPayload in ipairs(ends) do
		self:HandleProjectileEnd(endPayload)
	end
end

function ProjectileVisualization:HandleProjectileSegment(payload: {[string]: any})
	local projectileId = getProjectileId(payload)
	local segment = createPathEvent(payload, "segment")
	if not projectileId or not segment then
		return
	end

	local ignoredProjectile = self.IgnoredProjectiles[projectileId]
	if ignoredProjectile then
		return
	end

	local projectile = self.Projectiles[projectileId]
	if not projectile then
		self:BufferPendingEvent(projectileId, "Segment", payload)
		return
	end

	self:ApplySegment(projectile, segment)
end

function ProjectileVisualization:HandleProjectileEnd(payload: {[string]: any})
	local projectileId = getProjectileId(payload)
	local endEvent = createEndEvent(payload)
	if not projectileId or not endEvent then
		return
	end

	local ignoredProjectile = self.IgnoredProjectiles[projectileId]
	if ignoredProjectile then
		if ignoredProjectile.clearOnEnd then
			self.IgnoredProjectiles[projectileId] = nil
		end
		self.PendingEvents[projectileId] = nil
		return
	end

	local projectile = self.Projectiles[projectileId]
	if not projectile then
		self:BufferPendingEvent(projectileId, "End", payload)
		return
	end

	self:ApplyEnd(projectile, projectileId, endEvent)
end

function ProjectileVisualization:update(_step: number)
	local now = Workspace:GetServerTimeNow()
	local renderTime = now - INTERPOLATION_DELAY

	for projectileId, pendingEvents in pairs(self.PendingEvents) do
		local latestEvent = pendingEvents[#pendingEvents]
		if latestEvent and now - getPendingEventTime(latestEvent) > PENDING_EVENT_TIMEOUT then
			self.PendingEvents[projectileId] = nil
		end
	end

	for projectileId, ignoredProjectile in pairs(self.IgnoredProjectiles) do
		if now >= ignoredProjectile.ignoredUntil then
			self.IgnoredProjectiles[projectileId] = nil
		end
	end

	for projectileId, projectile in pairs(self.Projectiles) do
		if now - projectile.createdServerTime > projectile.maxLifetime + 1 then
			self:DestroyProjectile(projectileId)
			continue
		end

		local endEvent = projectile.endEvent
		local position
		local direction
		if endEvent and renderTime >= endEvent.serverEndTime then
			position = endEvent.endPosition
			direction = endEvent.lookDirection
		else
			position, direction = evaluateSegment(projectile.currentSegment, renderTime)
			local lastRenderPosition = projectile.lastRenderPosition
			if lastRenderPosition then
				local renderedDirection = position - lastRenderPosition
				if renderedDirection.Magnitude > VECTOR_EPSILON then
					direction = renderedDirection
				end
			end
		end

		local maxDistance = projectile.maxDistance
		if maxDistance then
			local completedPosition = position
			local reachedMaxDistance = projectile.distanceTraveled >= maxDistance
			if not reachedMaxDistance then
				local travelDelta = position - projectile.lastDistancePosition
				local travelDistance = travelDelta.Magnitude
				local nextDistanceTraveled = projectile.distanceTraveled + travelDistance
				if nextDistanceTraveled >= maxDistance then
					local remainingDistance = math.max(maxDistance - projectile.distanceTraveled, 0)
					completedPosition = if travelDistance > VECTOR_EPSILON
						then projectile.lastDistancePosition + (travelDelta.Unit * math.min(remainingDistance, travelDistance))
						else position
					projectile.distanceTraveled = maxDistance
					projectile.lastDistancePosition = completedPosition
					reachedMaxDistance = true
				else
					projectile.distanceTraveled = nextDistanceTraveled
					projectile.lastDistancePosition = position
				end
			end

			if reachedMaxDistance then
				local ignoredUntil = math.max(now + PENDING_EVENT_TIMEOUT, projectile.createdServerTime + projectile.maxLifetime + 1)

				self:DestroyProjectile(projectileId)
				self:IgnoreProjectile(projectileId, ignoredUntil, false, false)

				if DEBUG_PROJECTILE_VISUALS then
					debugProjectileVisuals("local complete", projectileId, "range", ignoredUntil)
				end

				continue
			end
		end

		updateProjectileVisibility(projectile, position)
		pivotVisual(projectile.visual, getVisualCFrame(position, direction, projectile.visualRotationOffset))
		projectile.lastRenderPosition = position

		if projectile.destroyAfterServerTime and now >= projectile.destroyAfterServerTime then
			if DEBUG_PROJECTILE_VISUALS then
				debugProjectileVisuals("scheduled end destroy", projectileId, projectile.destroyAfterServerTime, now)
			end
			self:DestroyProjectile(projectileId)
		end
	end
end

function ProjectileVisualization:Stop()
	if self.visualsConnection then
		self.visualsConnection:Disconnect()
		self.visualsConnection = nil
	end

	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	local projectileIds = {}
	for projectileId in pairs(self.Projectiles) do
		table.insert(projectileIds, projectileId)
	end
	for _, projectileId in projectileIds do
		self:DestroyProjectile(projectileId)
	end

	table.clear(self.Projectiles)
	table.clear(self.PendingEvents)
	table.clear(self.IgnoredProjectiles)

	hitEffectPoolGeneration += 1
	for effect in activeHitEffects do
		effect:Destroy()
	end
	table.clear(activeHitEffects)

	for _, pool in hitEffectPools do
		for _, effect in ipairs(pool) do
			effect:Destroy()
		end
		table.clear(pool)
	end
	table.clear(hitEffectPools)
end

function ProjectileVisualization:SpawnProjectile(payload: {[string]: any})
	local projectileId = getProjectileId(payload)
	if not projectileId then
		return
	end

	if self.IgnoredProjectiles[projectileId] then
		return
	end

	local ownerId = payload.ownerId or 0
	local isOwnedByOtherPlayer = ownerId ~= 0 and ownerId ~= LocalPlayer.UserId
	if isOwnedByOtherPlayer and not self.ShowOtherPlayerProjectiles then
		if DEBUG_PROJECTILE_VISUALS then
			debugProjectileVisuals("spawn ignored", projectileId, "otherPlayer", ownerId)
		end
		self:IgnoreProjectile(
			projectileId,
			Workspace:GetServerTimeNow() + (payload.maxLifetime or 10) + 1,
			false,
			true
		)
		return
	end

	local pendingEvents = self.PendingEvents[projectileId]
	local maxDistance = payload.maxDistance or payload.maxRange
	local projectileType = payload.projectileType or DEFAULT_PROJECTILE_TYPE
	local typeFolder = ProjectileAssets:FindFirstChild(projectileType)
	if not typeFolder then
		typeFolder = ProjectileAssets:FindFirstChild(DEFAULT_PROJECTILE_TYPE)
		if typeFolder then
			warn(`[ProjectileVisualization] Missing projectile folder "{projectileType}". Using "{DEFAULT_PROJECTILE_TYPE}" instead.`)
		end
	end
	if not typeFolder then
		warn(`[ProjectileVisualization] Missing projectile folder "{projectileType}" and fallback "{DEFAULT_PROJECTILE_TYPE}".`)
		return
	end

	local template = typeFolder:FindFirstChild(BULLET_CHILD_NAME)
	if not template then
		warn(`[ProjectileVisualization] Projectile folder "{typeFolder.Name}" is missing a "{BULLET_CHILD_NAME}" child.`)
		return
	end

	local impactTemplate = typeFolder:FindFirstChild(IMPACT_CHILD_NAME) :: BasePart?

	local firstSegment = createPathEvent({
		sequence = 0,
		serverTime = payload.serverStartTime or payload.serverTime or Workspace:GetServerTimeNow(),
		position = getPayloadPosition(payload, Vector3.new()),
		lookDirection = getVector(payload, "lookDirection", FALLBACK_LOOK_DIRECTION),
		velocity = getVector(payload, "velocity", Vector3.new()),
		acceleration = getVector(payload, "acceleration", Vector3.new()),
		reason = "spawn",
	}, "spawn")
	if not firstSegment then
		if DEBUG_PROJECTILE_VISUALS then
			debugProjectileVisuals("spawn failed; invalid payload", projectileId)
		end
		return
	end

	if DEBUG_PROJECTILE_VISUALS then
		debugProjectileVisuals(
			"spawn",
			projectileId,
			projectileType,
			"owner",
			ownerId,
			"pending",
			if pendingEvents then #pendingEvents else 0,
			"existing",
			self.Projectiles[projectileId] ~= nil
		)
	end
	self:DestroyProjectile(projectileId)
	self.IgnoredProjectiles[projectileId] = nil

	local visual = template:Clone()
	visual.Name = `ProjectileVisual_{projectileId}`
	local pivot = if visual:IsA("Model")
		then visual:GetPivot()
		elseif visual:IsA("BasePart") then visual.CFrame
		else CFrame.new()
	local visualRotationOffset = pivot - pivot.Position
	local trails = getProjectileTrails(visual)
	local parts = getProjectileParts(visual)
	local bulletVisible = BULLET_SHOW_DELAY_DISTANCE <= 0
	local trailsFullyExpanded = TRAIL_SHOW_DELAY_DISTANCE <= 0
	setProjectilePartsVisible(parts, bulletVisible)
	for _, projectileTrail in ipairs(trails) do
		projectileTrail.trail:Clear()
		projectileTrail.trail.Enabled = projectileTrail.originalEnabled
	end
	setTrailAttachmentRamp(trails, if trailsFullyExpanded then 1 else 0)
	normalizeTrailLifetimes(trails, firstSegment.velocity)
	visual.Parent = PROJECTILE_PARENT

	local renderTime = Workspace:GetServerTimeNow() - INTERPOLATION_DELAY
	local initialPosition, initialDirection = evaluateSegment(firstSegment, renderTime)
	pivotVisual(visual, getVisualCFrame(initialPosition, initialDirection, visualRotationOffset))

	local initialDistanceTraveled = if maxDistance then (initialPosition - firstSegment.position).Magnitude else 0
	local projectile = {
		visual = visual,
		visualRotationOffset = visualRotationOffset,
		impactTemplate = impactTemplate,
		trails = trails,
		parts = parts,
		bulletVisible = bulletVisible,
		trailsFullyExpanded = trailsFullyExpanded,
		showDelayDistanceTraveled = 0,
		lastShowDelayDistancePosition = initialPosition,
		maxDistance = maxDistance,
		distanceTraveled = initialDistanceTraveled,
		lastDistancePosition = initialPosition,
		maxLifetime = payload.maxLifetime or 10,
		createdServerTime = firstSegment.serverTime,
		currentSegment = firstSegment,
		lastSequence = firstSegment.sequence,
		lastRenderPosition = initialPosition,
		endEvent = nil,
		destroyAfterServerTime = nil,
	} :: ActiveProjectile

	self.Projectiles[projectileId] = projectile

	if pendingEvents then
		for _, pendingEvent in ipairs(pendingEvents) do
			if pendingEvent.eventType == "End" then
				local endEvent = createEndEvent(pendingEvent.payload)
				if endEvent then
					self:ApplyEnd(projectile, projectileId, endEvent)
				end
			else
				local segment = createPathEvent(pendingEvent.payload, "segment")
				if segment then
					self:ApplySegment(projectile, segment)
				end
			end
		end
		self.PendingEvents[projectileId] = nil
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ProjectileVisualization:Init(controllers)
	self.Controllers = controllers
end

function ProjectileVisualization:Start()
	self:Stop()

	if DEBUG_PROJECTILE_VISUALS then
		debugProjectileVisuals("controller start", script:GetFullName())
	end

	self.visualsConnection = remotes.ProjectileVisuals.OnClientEvent:Connect(function(action: string, payload)
		if action == "Batch" then
			self:HandleProjectileBatch(payload)
		end
	end)

	self.updateConnection = RunService.RenderStepped:Connect(function(step)
		self:update(step)
	end)
end

function ProjectileVisualization:Destroy()
	self:Stop()
	ProjectileAudio.destroy()
end

return ProjectileVisualization
