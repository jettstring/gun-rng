local module = {}
local module_mt = {__index = module}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local hitLogEvent = ReplicatedStorage.Remotes.GunKit.HitLog
local serverHitLogEvent = ReplicatedStorage.Remotes.GunKit.ServerHitLog
local damageEffectsEvent = ReplicatedStorage.Remotes.Enemy.DamageEffects

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local CastVisuals = require(ReplicatedStorage.Packages.CastVisuals)
local ProjectileRaycastParams = require(ReplicatedStorage.Packages.ProjectileRaycastParams)
local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)
local LingerEffect = require(ReplicatedStorage.Packages.LingerEffect)

local VIZ = true
local VIZ_THICKNESS = 1
local VIZ_DURATION = 1
local DEBUG = false
local SHOOT_IGNORE = workspace:WaitForChild("RAY_IGNORE")

local ProjectileAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("ProjectileAssets")

type ProjectileOptions = {
	showRays: boolean?,
	shootFromVisual: Vector3?,
	shootFrom: CFrame?,
	shootTowards: Vector3?,
	forwardVelocity: number?,
	acceleration: Vector3?,
	maxBulletDistance: number?,
	damage: number?,
	headshotMult: number?,
	player: Player?,
	ignoreCharacter: Model?,
	ammoType: string?,
	isExplosive: boolean?,
	ricochet: number?,
	penetrations: number?,
	visualId: string?,
	serverVisuals: boolean?,
}

local DEFAULT_VISIBLE_BULLET_NAME = "Bullet"
local DEFAULT_FORWARD_VELOCITY = 1000
local DEFAULT_DAMAGE = 0
local DEFAULT_HEADSHOT_MULT = 1
local ENEMY_TAG_PREFIX = "Enemy-"
local SURFACE_RAYCAST_OFFSET = 0.25
local EXPLOSION_LIFETIME = 1
local PHYSICS_TARGET_BULLET_MASS = 0.01
local PHYSICS_TARGET_BULLET_VELOCITY = 1200
local PHYSICS_TARGET_TRANSFER_EFFICIENCY = 0.7
local PHYSICS_TARGET_MAX_VELOCITY = 200
local PHYSICS_TARGET_IMPULSE_SCALE = 20

local METERS_PER_STUD = 0.28
local STUDS_PER_METER = 1 / METERS_PER_STUD
local AIR_DENSITY_KG_PER_M3 = 1.225
local BULLET_DRAG_COEFFICIENT = 0.295
local BULLET_DIAMETER_METERS = 0.00762
local BULLET_MASS_KG = 0.01
local BULLET_CROSS_SECTION_AREA_METERS = math.pi * (BULLET_DIAMETER_METERS * 0.5) ^ 2
local MIN_RICOCHET_SPEED = 25

local DEFAULT_RICOCHET_RESTITUTION = 0.35
local DEFAULT_RICOCHET_FRICTION = 0.18
local FALLBACK_LOOK_DIRECTION = Vector3.new(0, 0, -1)
local FORCEFIELD_VISUAL_TRANSPARENCY_LIMIT = 1
local VECTOR_EPSILON = 1e-6
local SMART_MAX_ENEMY_HITS = 3
local SMART_TARGET_SCORE_EPSILON = 1e-3

local MAX_LIFESPAN = 10 -- Seconds

local function getSurfaceResponse(hitInstance: Instance): (number, number)
	if not hitInstance:IsA("BasePart") then
		return DEFAULT_RICOCHET_RESTITUTION, DEFAULT_RICOCHET_FRICTION
	end

	local material = hitInstance.Material
	if material == Enum.Material.Metal
		or material == Enum.Material.DiamondPlate
		or material == Enum.Material.CorrodedMetal
	then
		return 0.55, 0.1
	elseif material == Enum.Material.Concrete
		or material == Enum.Material.Brick
		or material == Enum.Material.Rock
		or material == Enum.Material.Cobblestone
		or material == Enum.Material.Asphalt
	then
		return 0.36, 0.22
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		return 0.22, 0.32
	end

	return DEFAULT_RICOCHET_RESTITUTION, DEFAULT_RICOCHET_FRICTION
end

local function getDragAcceleration(velocity: Vector3): Vector3
	local speedStudsPerSecond = velocity.Magnitude
	if speedStudsPerSecond <= 0 then
		return Vector3.new()
	end

	local speedMetersPerSecond = speedStudsPerSecond * METERS_PER_STUD
	-- Fd = 0.5 * rho * Cd * A * v^2, then a = Fd / m.
	local dragAccelerationMetersPerSecondSquared = (
		0.5
		* AIR_DENSITY_KG_PER_M3
		* BULLET_DRAG_COEFFICIENT
		* BULLET_CROSS_SECTION_AREA_METERS
		* speedMetersPerSecond
		* speedMetersPerSecond
	) / BULLET_MASS_KG

	return velocity.Unit * (-dragAccelerationMetersPerSecondSquared * STUDS_PER_METER)
end

local function getRicochetVelocity(incidentVelocity: Vector3, surfaceNormal: Vector3, hitInstance: Instance): Vector3?
	if incidentVelocity.Magnitude < MIN_RICOCHET_SPEED or surfaceNormal.Magnitude <= 0 then
		return nil
	end

	local normal = surfaceNormal.Unit
	if incidentVelocity:Dot(normal) > 0 then
		normal = normal * -1
	end

	local normalVelocity = normal * incidentVelocity:Dot(normal)
	local tangentialVelocity = incidentVelocity - normalVelocity
	local restitution, friction = getSurfaceResponse(hitInstance)

	-- v' = vt * (1 - friction) - e * vn, where e is the coefficient of restitution.
	local ricochetVelocity = (tangentialVelocity * math.max(0, 1 - friction)) - (normalVelocity * restitution)
	if ricochetVelocity.Magnitude < MIN_RICOCHET_SPEED then
		return nil
	end

	return ricochetVelocity
end

local function canDamageTaggedEnemy(player: Player?, characterModel: Model): boolean
	local hasEnemyOwnerTag = false
	local expectedEnemyTag = if player then `{ENEMY_TAG_PREFIX}{player.Name}` else nil

	for _, tag in CollectionService:GetTags(characterModel) do
		if string.sub(tag, 1, #ENEMY_TAG_PREFIX) ~= ENEMY_TAG_PREFIX then
			continue
		end

		hasEnemyOwnerTag = true
		if tag == expectedEnemyTag then
			return true
		end
	end

	return not hasEnemyOwnerTag
end

local function fireEnemyDamageEffects(player: Player?, characterModel: Model, newHealth: number)
	if not player then
		return
	end

	local highlight = characterModel:FindFirstChildWhichIsA("Highlight")
	if not highlight then
		return
	end

	local healthBillboardGui = characterModel:FindFirstChild("HealthBillboardGui", true)
	if healthBillboardGui and not healthBillboardGui:IsA("BillboardGui") then
		healthBillboardGui = nil
	end

	damageEffectsEvent:FireClient(player, highlight, healthBillboardGui, newHealth)
end

function module.new(shootPart: BasePart, options: ProjectileOptions, bulletName: string?)
	local projectileOptions = options
	local shootFrom = projectileOptions.shootFrom or shootPart.CFrame
	local shootTowards = projectileOptions.shootTowards or shootFrom.LookVector
	local shootFromVisual = projectileOptions.shootFromVisual or shootPart.Position
	local visibleBulletName = bulletName or DEFAULT_VISIBLE_BULLET_NAME

	local maxBulletDistanceOption = projectileOptions.maxBulletDistance
	local maxBulletDistance = if maxBulletDistanceOption and maxBulletDistanceOption > 0 then maxBulletDistanceOption else nil
	local ricochetCount = math.max(0, math.floor(projectileOptions.ricochet or 0))
	local penetrationCount = math.max(0, math.floor(projectileOptions.penetrations or 0))

	local self = {}
	VIZ = projectileOptions.showRays == true
	self.shootPart = shootPart
	self.shootPartCf = shootFrom
	self.shootFromVisual = shootFromVisual
	self.shootFrom = shootFrom.Position
	self.shootTowards = shootTowards
	self.player = projectileOptions.player
	self.ignoreCharacter = projectileOptions.ignoreCharacter
	

	
	self.visibleBulletName = visibleBulletName
	self.visualId = projectileOptions.visualId
	self.visualSequence = 0
	self.createdServerTime = Workspace:GetServerTimeNow()
	self.pendingVisualSegments = {}
	self.pendingVisualEnd = nil
	self.hasRecordedVisualEnd = false

	self.forwardVelocity = projectileOptions.forwardVelocity or DEFAULT_FORWARD_VELOCITY
	self.baseAcceleration = projectileOptions.acceleration or Vector3.new()
	self.initialAcceleration = self.baseAcceleration
	self.maxBulletDistance = maxBulletDistance
	self.totalDistanceTraveled = 0
	self.damage = projectileOptions.damage or DEFAULT_DAMAGE
	self.headshotMult = projectileOptions.headshotMult or DEFAULT_HEADSHOT_MULT
	self.ricochetsRemaining = ricochetCount
	self.penetrationsRemaining = penetrationCount
	self.maxHits = math.max(10, self.ricochetsRemaining + self.penetrationsRemaining + 1)
	self.rayOrigin = self.shootPart.Position
	self.smartEnemyHits = 0
	self.smartLockedTarget = nil
	self.ammoType = projectileOptions.ammoType
	self.isExplosive = projectileOptions.isExplosive == true
	if self.ammoType == "Explosive" then
		self.isExplosive = true
		self.ricochetsRemaining = 0
		self.penetrationsRemaining = 0
		self.damage *= 1.5
	end

	self.rayOutsideParams = ProjectileRaycastParams.newOutsideParams(shootPart, self.ignoreCharacter, self.player)

	self.accelerationAdjustment = Vector3.new()
	self.totalRaySegments = 0
	self.totalHits = 0
	self.t = 0
	self.totalElapsedTime = 0

	self.currentBullet = nil
	if projectileOptions.serverVisuals == true then
		local bulletTemplate = ProjectileAssets:FindFirstChild(visibleBulletName)
		if not bulletTemplate then
			warn(`Projectile visual "{visibleBulletName}" was not found. Using "{DEFAULT_VISIBLE_BULLET_NAME}" instead.`)
			bulletTemplate = ProjectileAssets:WaitForChild(DEFAULT_VISIBLE_BULLET_NAME)
		end

		local bulletModel = bulletTemplate:Clone()
		bulletModel.Parent = SHOOT_IGNORE
		self.currentBullet = bulletModel
	end

	self.characterModelsHit = {}

	self.isValid = true
	self.hasHit = false
	self.hasHeadshot = false
	self.lastHitPosition = Vector3.new()
	self.lastHitEffect = nil
	self.lastHitSound = nil
	self.lastHitCharacterModel = nil
	self.lastDamageDone = nil
	self.smartVisualArcTargetPosition = nil
	self.smartVisualArcSideSign = nil
	return setmetatable(self, module_mt)
end

function module:getVisualSpawnPayload(): {[string]: any}?
	if not self.visualId then
		return nil
	end

	local lookDirection = self.shootTowards
	if lookDirection.Magnitude <= 0 then
		lookDirection = self.shootPartCf.LookVector
	end
	if lookDirection.Magnitude <= 0 then
		lookDirection = FALLBACK_LOOK_DIRECTION
	end

	local ownerId = if self.player then self.player.UserId else 0
	local velocity = lookDirection.Unit * self.forwardVelocity
	return {
		id = self.visualId,
		ownerId = ownerId,
		projectileType = self.visibleBulletName,
		maxLifetime = MAX_LIFESPAN,
		maxDistance = self.maxBulletDistance,
		maxRange = self.maxBulletDistance,
		serverStartTime = self.createdServerTime,
		serverTime = self.createdServerTime,
		origin = self.shootFromVisual,
		position = self.shootFromVisual,
		lookDirection = lookDirection.Unit,
		velocity = velocity,
		acceleration = self.initialAcceleration + self.accelerationAdjustment,
	}
end

function module:recordVisualSegment(
	position: Vector3,
	lookDirection: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	reason: string,
	normal: Vector3?,
	impactPosition: Vector3?,
	effectType: string?,
	soundType: string?
)
	if not self.visualId then
		return
	end

	if lookDirection.Magnitude <= 0 then
		if velocity.Magnitude > 0 then
			lookDirection = velocity.Unit
		else
			lookDirection = self.shootTowards
		end
	end
	if lookDirection.Magnitude <= 0 then
		lookDirection = self.shootPartCf.LookVector
	end
	if lookDirection.Magnitude <= 0 then
		lookDirection = FALLBACK_LOOK_DIRECTION
	end

	self.visualSequence += 1
	local visualSegment = {
		id = self.visualId,
		sequence = self.visualSequence,
		serverTime = Workspace:GetServerTimeNow(),
		position = position,
		lookDirection = lookDirection.Unit,
		velocity = velocity,
		acceleration = acceleration,
		reason = reason,
		normal = normal,
		impactPosition = impactPosition,
		effectType = effectType,
		soundType = soundType,
	}

	if reason == "smart" and self.smartVisualArcTargetPosition then
		visualSegment.cosmeticArcTargetPosition = self.smartVisualArcTargetPosition
		visualSegment.cosmeticArcSideSign = self.smartVisualArcSideSign
		self.smartVisualArcTargetPosition = nil
		self.smartVisualArcSideSign = nil
	end

	table.insert(self.pendingVisualSegments, visualSegment)
end

function module:recordVisualEnd(
	endPosition: Vector3,
	lookDirection: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	reason: string,
	normal: Vector3?,
	impactPosition: Vector3?,
	effectType: string?,
	soundType: string?
)
	if not self.visualId or self.hasRecordedVisualEnd then
		return
	end

	if lookDirection.Magnitude <= 0 then
		if velocity.Magnitude > 0 then
			lookDirection = velocity.Unit
		else
			lookDirection = self.shootTowards
		end
	end
	if lookDirection.Magnitude <= 0 then
		lookDirection = self.shootPartCf.LookVector
	end
	if lookDirection.Magnitude <= 0 then
		lookDirection = FALLBACK_LOOK_DIRECTION
	end

	self.visualSequence += 1
	local serverEndTime = Workspace:GetServerTimeNow()
	self.pendingVisualEnd = {
		id = self.visualId,
		sequence = self.visualSequence,
		serverEndTime = serverEndTime,
		serverTime = serverEndTime,
		endPosition = endPosition,
		position = endPosition,
		lookDirection = lookDirection.Unit,
		velocity = velocity,
		acceleration = acceleration,
		reason = reason,
		normal = normal,
		impactPosition = impactPosition,
		effectType = effectType,
		soundType = soundType,
	}
	self.hasRecordedVisualEnd = true
end

function module:consumeVisualSegments(): {{[string]: any}}
	local visualSegments = self.pendingVisualSegments
	self.pendingVisualSegments = {}
	return visualSegments
end

function module:consumeVisualEnd(): {[string]: any}?
	local visualEnd = self.pendingVisualEnd
	self.pendingVisualEnd = nil
	return visualEnd
end

function module:getSmartLockedTargetRaycastParams(): RaycastParams?
	local target = self.smartLockedTarget
	if not self.player or not target or not target.Parent then
		self.smartLockedTarget = nil
		return nil
	end

	local humanoid = target:FindFirstChildWhichIsA("Humanoid")
	if not CollectionService:HasTag(target, `{ENEMY_TAG_PREFIX}{self.player.Name}`)
		or not humanoid
		or humanoid.Health <= 0
	then
		self.smartLockedTarget = nil
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.IncludeInstances = { target }

	return raycastParams
end

function module:findSmartTarget(originPosition: Vector3, forwardDirection: Vector3): (Model?, BasePart?)
	if not self.player then
		return nil, nil
	end

	local ownerTag = `{ENEMY_TAG_PREFIX}{self.player.Name}`
	if forwardDirection.Magnitude > VECTOR_EPSILON then
		forwardDirection = forwardDirection.Unit
	elseif self.shootTowards.Magnitude > VECTOR_EPSILON then
		forwardDirection = self.shootTowards.Unit
	else
		forwardDirection = FALLBACK_LOOK_DIRECTION
	end

	local bestEnemy: Model? = nil
	local bestAimPart: BasePart? = nil
	local bestAlignment = -math.huge
	local bestDistanceSquared = math.huge
	local bestHealth = math.huge

	for _, instance in CollectionService:GetTagged(ownerTag) do
		local enemyModel = instance :: Model
		if self.characterModelsHit[enemyModel] then
			continue
		end

		if not enemyModel.Parent or enemyModel:HasTag("Invulnerable") then
			continue
		end

		local humanoid = enemyModel:FindFirstChildWhichIsA("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local aimPart = (enemyModel.PrimaryPart or enemyModel:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if not aimPart then
			continue
		end

		local targetOffset = aimPart.Position - originPosition
		local distanceSquared = targetOffset:Dot(targetOffset)
		local alignment = if distanceSquared > VECTOR_EPSILON
			then forwardDirection:Dot(targetOffset.Unit)
			else 1
		local alignmentDelta = alignment - bestAlignment
		local distanceDelta = math.abs(distanceSquared - bestDistanceSquared)
		local isBetterAlignment = alignmentDelta > SMART_TARGET_SCORE_EPSILON
		local isSameAlignmentCloser = math.abs(alignmentDelta) <= SMART_TARGET_SCORE_EPSILON
			and distanceSquared < bestDistanceSquared - SMART_TARGET_SCORE_EPSILON
		local isSameAlignmentDistanceLowerHealth = math.abs(alignmentDelta) <= SMART_TARGET_SCORE_EPSILON
			and distanceDelta <= SMART_TARGET_SCORE_EPSILON
			and humanoid.Health < bestHealth

		if isBetterAlignment or isSameAlignmentCloser or isSameAlignmentDistanceLowerHealth then
			bestEnemy = enemyModel
			bestAimPart = aimPart
			bestAlignment = alignment
			bestDistanceSquared = distanceSquared
			bestHealth = humanoid.Health
		end
	end

	return bestEnemy, bestAimPart
end

function module:redirectSmartProjectile(target: Model, aimPart: BasePart, originPosition: Vector3, incidentVelocity: Vector3): boolean
	local targetOffset = aimPart.Position - originPosition
	if targetOffset.Magnitude <= VECTOR_EPSILON then
		return false
	end

	local speed = incidentVelocity.Magnitude
	if speed <= VECTOR_EPSILON then
		speed = self.forwardVelocity
	end
	if speed <= VECTOR_EPSILON then
		speed = DEFAULT_FORWARD_VELOCITY
	end

	self.smartLockedTarget = target
	self.smartVisualArcTargetPosition = aimPart.Position
	self.smartVisualArcSideSign = if self.smartEnemyHits % 2 == 0 then -1 else 1
	self.shootTowards = targetOffset.Unit
	self.forwardVelocity = speed
	self.initialAcceleration = self.baseAcceleration + getDragAcceleration(self.shootTowards * self.forwardVelocity)
	self.accelerationAdjustment = Vector3.new()
	self.shootFrom = originPosition + (self.shootTowards * SURFACE_RAYCAST_OFFSET)
	self.rayOrigin = self.shootFrom
	self.t = 0

	return true
end

function module:getSmartHitResponse(raycastResult: RaycastResult, impactVelocity: Vector3): string?
	if self.ammoType ~= "Smart" then
		return nil
	end

	local hitCharacterModel = self.lastHitCharacterModel
	if not self.player
		or not hitCharacterModel
		or not self.lastDamageDone
		or self.lastDamageDone <= 0
		or not CollectionService:HasTag(hitCharacterModel, `{ENEMY_TAG_PREFIX}{self.player.Name}`)
	then
		return nil
	end

	self.smartLockedTarget = nil
	self.rayOutsideParams:AddToFilter(hitCharacterModel)
	self.smartEnemyHits += 1

	if self.smartEnemyHits >= SMART_MAX_ENEMY_HITS then
		return "limit"
	end

	local nextTarget, nextAimPart = self:findSmartTarget(raycastResult.Position, impactVelocity)
	if nextTarget and nextAimPart and self:redirectSmartProjectile(nextTarget, nextAimPart, raycastResult.Position, impactVelocity) then
		return "redirect"
	end

	return "continue"
end

function module:ricochet(raycastResult: RaycastResult, incidentVelocity: Vector3): boolean
	if self.ricochetsRemaining <= 0 then
		return false
	end

	local ricochetVelocity = getRicochetVelocity(incidentVelocity, raycastResult.Normal, raycastResult.Instance)
	if not ricochetVelocity then
		return false
	end

	self.ricochetsRemaining -= 1
	self.shootTowards = ricochetVelocity.Unit
	self.forwardVelocity = ricochetVelocity.Magnitude
	self.initialAcceleration = self.baseAcceleration + getDragAcceleration(ricochetVelocity)
	self.accelerationAdjustment = Vector3.new()
	self.shootFrom = raycastResult.Position + (self.shootTowards * SURFACE_RAYCAST_OFFSET)
	self.rayOrigin = self.shootFrom
	self.t = 0

	return true
end

function module:update(deltaTimeRender)
	if not self.isValid then
		return
	end
	self.hasHit = false
	self.hasHeadshot = false
	self.lastHitPosition = Vector3.new()
	self.lastHitEffect = nil
	self.lastHitSound = nil
	self.lastHitCharacterModel = nil
	self.lastDamageDone = nil

	self.t += deltaTimeRender
	self.totalElapsedTime += deltaTimeRender
	local t = self.t
	local raycastParams: RaycastParams = self.rayOutsideParams
	local smartLockedTargetRaycastParams = if self.ammoType == "Smart" then self:getSmartLockedTargetRaycastParams() else nil
	if smartLockedTargetRaycastParams then
		raycastParams = smartLockedTargetRaycastParams
	end

	local velocity: Vector3 = self.shootTowards * self.forwardVelocity
	local acceleration: Vector3 = self.initialAcceleration + self.accelerationAdjustment

	local distance: Vector3 = (velocity * t) + (0.5 * acceleration * t * t) + self.shootFrom
	local rawRayDirection: Vector3 = distance - self.rayOrigin
	local rayDirection: Vector3 = rawRayDirection
	local rayEndAlpha = 1
	if self.maxBulletDistance then
		local remainingDistance = self.maxBulletDistance - self.totalDistanceTraveled
		local rayMagnitude = rayDirection.Magnitude
		if remainingDistance <= 0 and rayMagnitude > 0 then
			rayDirection = rayDirection.Unit * 0
			rayEndAlpha = 0
		elseif rayMagnitude > remainingDistance then
			rayDirection = rayDirection.Unit * math.max(remainingDistance, 0)
			rayEndAlpha = if rawRayDirection.Magnitude > 0
				then math.clamp(rayDirection.Magnitude / rawRayDirection.Magnitude, 0, 1)
				else 1
		end
	end

	local segmentStartTime = math.max(0, t - deltaTimeRender)
	local segmentEndTime = segmentStartTime + ((t - segmentStartTime) * rayEndAlpha)
	local raycastResult: RaycastResult? = nil
	if rayDirection.Magnitude > 0 then
		raycastResult = Workspace:Raycast(self.rayOrigin, rayDirection, raycastParams)
		-- Enemies owned by other players are invisible to and undamageable by
		-- this shooter; pass the ray through them instead of letting their
		-- bodies block the shot. Guarded to the outside Exclude params: a
		-- smart-locked Include ray can only hit its own (damageable) target.
		if raycastParams == self.rayOutsideParams then
			while raycastResult do
				local hitModel = raycastResult.Instance:FindFirstAncestorOfClass("Model")
				if hitModel and not canDamageTaggedEnemy(self.player, hitModel) then
					self.rayOutsideParams:AddToFilter(hitModel)
					raycastResult = Workspace:Raycast(self.rayOrigin, rayDirection, raycastParams)
				else
					break
				end
			end
		end
	end

	local visColor: Color3
	local rayEndPosition: Vector3
	local didRicochet = false
	local didSmartRedirect = false
	local impactVelocity = velocity + (acceleration * segmentEndTime)
	local rayStartPosition = self.rayOrigin
	local visualEventReason = nil
	local visualEventEffectType = nil
	local visualEventSoundType = nil
	local visualEventNormal = nil
	local visualEventImpactPosition = nil
	local terminalReason = nil
	local terminalEffectType = nil
	local terminalSoundType = nil
	local terminalNormal = nil
	local terminalImpactPosition = nil
	if raycastResult then
		if DEBUG then
			print("From ", self.rayOrigin, " towards ", rayDirection, " hit =", raycastResult.Instance.Name)
			for _, instanceToIgnore in self.rayOutsideParams.ExcludeInstances do
				print("    Name: ", instanceToIgnore.Name)
			end
		end

		self.rayOutsideParams:AddToFilter(raycastResult.Instance)

		self.totalHits += 1
		visColor = Color3.new(1, 0, 0)
		rayEndPosition = raycastResult.Position
	else
		if DEBUG then
			print("From ", self.rayOrigin, " towards ", rayDirection, " hit = none")
		end
		visColor = Color3.new(0, 0, 1)

		rayEndPosition = self.rayOrigin + rayDirection
	end

	if VIZ and rayDirection.Magnitude > 0 then
		local castVisual = CastVisuals.new(visColor, VIZ_THICKNESS, nil, nil, VIZ_DURATION)
		castVisual:Raycast(self.rayOrigin, rayDirection, raycastParams)
	end

	if raycastResult then
		if rayDirection.Magnitude > 0 then
			local impactAlpha = math.clamp(
				(raycastResult.Position - rayStartPosition).Magnitude / rayDirection.Magnitude,
				0,
				1
			)
			local impactTime = segmentStartTime + ((segmentEndTime - segmentStartTime) * impactAlpha)
			impactVelocity = velocity + (acceleration * impactTime)
		end

		self.totalDistanceTraveled += (rayEndPosition - rayStartPosition).Magnitude
		local hasReachedMaxBulletDistance = self.maxBulletDistance ~= nil
			and self.totalDistanceTraveled >= self.maxBulletDistance
		local canPenetrate: boolean = raycastResult.Instance:HasTag("Penetrate") and self.penetrationsRemaining > 0
		self:hit(rayStartPosition, raycastResult)
		local hitEffectType = self.lastHitEffect
		local hitSoundType = self.lastHitSound
		local smartHitResponse = if not hasReachedMaxBulletDistance
			then self:getSmartHitResponse(raycastResult, impactVelocity)
			else nil

		if smartHitResponse == "redirect" then
			didSmartRedirect = true
			visualEventReason = "smart"
			visualEventEffectType = hitEffectType
			visualEventSoundType = hitSoundType
			visualEventNormal = raycastResult.Normal
			visualEventImpactPosition = raycastResult.Position
		elseif smartHitResponse == "continue" then
			visualEventReason = "penetrate"
			visualEventEffectType = hitEffectType
			visualEventSoundType = hitSoundType
			visualEventNormal = raycastResult.Normal
			visualEventImpactPosition = raycastResult.Position
		elseif smartHitResponse == "limit" then
			terminalReason = "smart-hit-limit"
			terminalEffectType = hitEffectType or "impact"
			terminalSoundType = hitSoundType
			terminalNormal = raycastResult.Normal
			terminalImpactPosition = raycastResult.Position
			self:cleanup()
		elseif not canPenetrate then
			if not hasReachedMaxBulletDistance then
				didRicochet = self:ricochet(raycastResult, impactVelocity)
			end
			if not didRicochet then
				terminalReason = if hasReachedMaxBulletDistance then "range" else "impact"
				terminalEffectType = hitEffectType or terminalReason
				terminalSoundType = hitSoundType
				terminalNormal = raycastResult.Normal
				terminalImpactPosition = raycastResult.Position
				self:cleanup()
			else
				visualEventReason = "ricochet"
				visualEventEffectType = hitEffectType or "ricochet"
				visualEventSoundType = hitSoundType
				visualEventNormal = raycastResult.Normal
				visualEventImpactPosition = raycastResult.Position
			end
		elseif hasReachedMaxBulletDistance then
			terminalReason = "range"
			terminalEffectType = hitEffectType or "range"
			terminalSoundType = hitSoundType
			terminalNormal = raycastResult.Normal
			terminalImpactPosition = raycastResult.Position
			self:cleanup()
		else
			self.penetrationsRemaining -= 1
			visualEventReason = "penetrate"
			visualEventEffectType = hitEffectType
			visualEventSoundType = hitSoundType
			visualEventNormal = raycastResult.Normal
			visualEventImpactPosition = raycastResult.Position
		end
	else
		self.totalDistanceTraveled += (rayEndPosition - rayStartPosition).Magnitude
	end

	if raycastResult then
		-- Move the next ray a small amount so it does not hit the same surface again.
		if didRicochet or didSmartRedirect then
			self.rayOrigin = self.shootFrom
		else
			local offset = Vector3.new()
			if rayDirection.Magnitude > 0 then
				offset = rayDirection.Unit * SURFACE_RAYCAST_OFFSET
			end
			self.rayOrigin = raycastResult.Position + offset
		end
	else
		self.rayOrigin = rayEndPosition
	end

	local shouldCleanupForDistance = self.maxBulletDistance ~= nil
		and self.totalDistanceTraveled >= self.maxBulletDistance
	local shouldCleanupForLimit = self.totalElapsedTime >= MAX_LIFESPAN or self.totalHits >= self.maxHits
	local visualVelocity = if didRicochet or didSmartRedirect then self.shootTowards * self.forwardVelocity else impactVelocity
	local visualAcceleration = self.initialAcceleration + self.accelerationAdjustment
	local cosmeticRayDirection = if didRicochet or didSmartRedirect then self.shootTowards else rayDirection

	if visualEventReason and self.isValid and not shouldCleanupForDistance and not shouldCleanupForLimit then
		self:recordVisualSegment(
			self.rayOrigin,
			cosmeticRayDirection,
			visualVelocity,
			visualAcceleration,
			visualEventReason,
			visualEventNormal,
			visualEventImpactPosition,
			visualEventEffectType,
			visualEventSoundType
		)
	end

	if self.currentBullet then
		local lookDirection = cosmeticRayDirection
		if lookDirection.Magnitude <= 0 then
			lookDirection = self.currentBullet.CFrame.LookVector
		end

		local cosmeticBulletCFrame = CFrame.new(self.rayOrigin, self.rayOrigin + lookDirection)
		if self.totalRaySegments <= 1 then
			cosmeticBulletCFrame = CFrame.new(self.shootFromVisual, self.shootFromVisual + lookDirection)

			local cf = CFrame.new(self.shootFromVisual, self.rayOrigin)
			local visualBulletFront = cf.LookVector * (self.rayOrigin - self.shootFromVisual).Magnitude
			if VIZ then
				local muzzleVisual = CastVisuals.new(
					Color3.new(0.990753, 0, 0.797726),
					VIZ_THICKNESS,
					false,
					false,
					VIZ_DURATION,
					false,
					workspace
				)
				muzzleVisual:Raycast(cf.Position, visualBulletFront, self.rayOutsideParams, VIZ_DURATION)
			end
		end

		self.currentBullet.CFrame = cosmeticBulletCFrame
	end

	self.totalRaySegments += 1

	if shouldCleanupForDistance then
		if self.isValid then
			self.lastHitEffect = "range"
			terminalReason = terminalReason or "range"
			terminalEffectType = terminalEffectType or self.lastHitEffect or "range"
			self:cleanup()
		end
		self:recordVisualEnd(
			rayEndPosition,
			cosmeticRayDirection,
			visualVelocity,
			visualAcceleration,
			terminalReason or "range",
			terminalNormal,
			terminalImpactPosition or rayEndPosition,
			terminalEffectType or "range",
			terminalSoundType
		)
		return
	end

	if shouldCleanupForLimit then
		terminalReason = if self.totalHits >= self.maxHits then "hit-limit" else "lifetime"
		self:cleanup()
		self:recordVisualEnd(
			self.rayOrigin,
			cosmeticRayDirection,
			visualVelocity,
			visualAcceleration,
			terminalReason,
			terminalNormal,
			terminalImpactPosition,
			terminalEffectType,
			terminalSoundType
		)
		return
	end

	if not self.isValid then
		self:recordVisualEnd(
			rayEndPosition,
			cosmeticRayDirection,
			visualVelocity,
			visualAcceleration,
			terminalReason or "impact",
			terminalNormal,
			terminalImpactPosition or rayEndPosition,
			terminalEffectType,
			terminalSoundType
		)
	end
end

function module:hit(rayOrigin: Vector3, raycastResult: RaycastResult)
	local instance: Instance = raycastResult.Instance
	local characterModel = instance:FindFirstAncestorOfClass("Model")

	local targetsHit = false
	local damageDone: number? = nil
	local wasHeadshot = false
	

	if self.isExplosive then
		local explosion = Instance.new("Explosion")
		explosion.Position = raycastResult.Position
		explosion.DestroyJointRadiusPercent = 0
		explosion.BlastRadius = 12
		explosion.BlastPressure = 0
		explosion.Visible = false
		self.lastHitSound = "explosion"

		local modelsHit = {}
		explosion.Hit:Connect(function(part, distance)
			local parentModel = part:FindFirstAncestorOfClass("Model")
			if parentModel and parentModel:HasTag("Enemy") then
				if modelsHit[parentModel] then
					return
				end

				modelsHit[parentModel] = true
				local humanoid = parentModel:FindFirstChildWhichIsA("Humanoid")
				if humanoid and canDamageTaggedEnemy(self.player, parentModel) then
					local distanceFactor = distance / explosion.BlastRadius 
					distanceFactor = 1 - distanceFactor 
					local damage = self.damage * distanceFactor
					local healthBefore = humanoid.Health
					humanoid:TakeDamage(damage) 
					if humanoid.Health < healthBefore then
						fireEnemyDamageEffects(self.player, parentModel, humanoid.Health)
						local enemyId: string? = parentModel:GetAttribute("id")
						if enemyId then
							hitLogEvent:FireClient(self.player, raycastResult.Instance.Name, self.shootFrom, raycastResult.Position, damage, self.totalHits, false, true, enemyId)
							serverHitLogEvent:Fire(self.player, raycastResult.Instance.Name, self.shootFrom, raycastResult.Position, damage, self.totalHits, false, true, enemyId)

						end
					end
					targetsHit = true
				end
			end
		end)

		explosion.Parent = workspace
		Debris:AddItem(explosion, EXPLOSION_LIFETIME)
	end

	if characterModel then
		local humanoid: Humanoid? = characterModel:FindFirstChildWhichIsA("Humanoid")

		if self.characterModelsHit[characterModel] then
			return
		end

		if humanoid then
			if characterModel:HasTag("Invulnerable") then return end
			if not canDamageTaggedEnemy(self.player, characterModel) then return end
			wasHeadshot = instance:IsA("BasePart") and (instance:HasTag("head") or instance.Name == "Head")
			damageDone = self:hitHumanoid(humanoid, rayOrigin, raycastResult.Position, wasHeadshot)
			if damageDone > 0 then
				self.lastHitCharacterModel = characterModel
				self.lastDamageDone = damageDone
				fireEnemyDamageEffects(self.player, characterModel, humanoid.Health)

				if RunService:IsServer() then
					local lingerConfig = AmmoTypes.getLinger(self.ammoType)
					if lingerConfig then
						LingerEffect.apply(self.player, characterModel, humanoid, self.ammoType, lingerConfig, damageDone)
					end
				end
			end

			targetsHit = true
		end
		self.characterModelsHit[characterModel] = true
	end

	-- hit sound

	if instance:IsA("BasePart") then
		if instance.Material == Enum.Material.ForceField and instance.Transparency < FORCEFIELD_VISUAL_TRANSPARENCY_LIMIT then
			self.lastHitEffect = "forcefield"
		end

		if instance.Name == "PhysicsTarget" then
			instance:SetAttribute("isHit", true)

			local impactOffset = raycastResult.Position - rayOrigin
			if not instance.Anchored and impactOffset.Magnitude > 0 then
				local bulletMomentum = impactOffset.Unit * PHYSICS_TARGET_BULLET_MASS * PHYSICS_TARGET_BULLET_VELOCITY
				local finalVelocity = (bulletMomentum / instance.Mass) * PHYSICS_TARGET_TRANSFER_EFFICIENCY
				if finalVelocity.Magnitude > PHYSICS_TARGET_MAX_VELOCITY then
					finalVelocity = finalVelocity.Unit * PHYSICS_TARGET_MAX_VELOCITY
				end

				instance:ApplyImpulseAtPosition(finalVelocity * PHYSICS_TARGET_IMPULSE_SCALE, raycastResult.Position)
			end
		end

		if instance.Name == "TargetPlate" or instance.Name == "PhysicsTarget" then
			targetsHit = true
		end
		if instance.Name == "TargetPlate" then
			instance.Hit:Fire(self.player)
		end
	end

	-- Send hit log message to client
	if targetsHit then
		local displayDamage = damageDone or self.damage
		local didDamage = damageDone ~= nil and damageDone > 0
		local enemyId = nil
		if didDamage then
			if characterModel then
				enemyId = characterModel:GetAttribute("id")
			end

			if enemyId == nil then
				local modelName = if characterModel then characterModel.Name else "unknown"
				warn(`Hit enemy model "{modelName}" is missing an id attribute.`)
			end
		end

		hitLogEvent:FireClient(self.player, raycastResult.Instance.Name, self.shootFrom, raycastResult.Position, displayDamage, self.totalHits, wasHeadshot, didDamage, enemyId)
		serverHitLogEvent:Fire(self.player, raycastResult.Instance.Name, self.shootFrom, raycastResult.Position, displayDamage, self.totalHits, wasHeadshot, didDamage, enemyId)
	end
end

function module:hitHumanoid(humanoid: Humanoid, _rayOrigin: Vector3, rayHit: Vector3, isHeadshot: boolean): number
	local damage = self.damage
	local healthBefore = humanoid.Health
	if isHeadshot then
		humanoid.Health -= damage * self.headshotMult
	end
	humanoid.Health -= damage
	self.hasHit = true
	self.hasHeadshot = isHeadshot
	self.lastHitPosition = rayHit

	if humanoid.Name ~= "Inanimate" then
		self.lastHitEffect = "blood"
	end

	return math.max(0, healthBefore - humanoid.Health)
end

function module:cleanup()
	if self.currentBullet then
		if self.currentBullet.Parent then
			Debris:AddItem(self.currentBullet, 0)
		end
		self.currentBullet = nil
	end
	self.isValid = false
end

return module
