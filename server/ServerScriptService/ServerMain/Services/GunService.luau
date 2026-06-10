local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local Projectile = require(ReplicatedStorage.Packages.Projectile)
local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)
local InventoryUtil = require(ReplicatedStorage.Util.InventoryUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)
local WeaponDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.WeaponDefinitions)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local gunKitRemotes = remotesFolder:WaitForChild("GunKit")
local remotes = {
	SetProjectileRays = gunKitRemotes:WaitForChild("SetProjectileRays"),
	ProjectileVisuals = gunKitRemotes:WaitForChild("ProjectileVisuals"),
	ToggleAutoEquipForAmmo = gunKitRemotes:WaitForChild("ToggleAutoEquipForAmmo"),
	InventoryUpdated = remotesFolder.Inventory.InventoryUpdated,
}

local GunEvent = ReplicatedStorage:WaitForChild("Remotes").GunKit.GunEvent

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type ActiveProjectile = {
	projectile: any,
	shootOriginPart: BasePart,
	owner: Player?,
	spawnOrigin: Vector3,
	spawnPayload: {[string]: any}?, -- pending spawn event; nil once dispatched
	recipients: {Player}?, -- frozen at spawn; nil = not admitted, empty = seen by nobody
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local GunService = {}
GunService.Services = {}
GunService.Signals = {}

GunService.ActiveProjectiles = {} :: {ActiveProjectile}
GunService.LastFireTime = {} :: {[string]: number}
GunService.LastVisualStateTime = {} :: {[Player]: number}
GunService.ActiveGunsByPlayer = {} :: {[Player]: {[string]: string}}
-- Per-viewer budget for other players' projectile spawns (see admitNewProjectiles).
GunService.ViewerProjectileTokens = {} :: {[Player]: number}
GunService.PlayerCharacterConnections = {} :: {[Player]: RBXScriptConnection}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local MAX_SHOT_DISTANCE_FROM_CHARACTER = 35
local FIRE_RATE_TOLERANCE = 0.9
local DEFAULT_HEADSHOT_MULTIPLIER = 1
local DEFAULT_PELLETS = 1
local VECTOR_EPSILON = 1e-6
local REPLICATED_GUN_FOLDER_NAME = "PsychicGuns"
local SHOOT_IGNORE = Workspace:WaitForChild("RAY_IGNORE")
local MAX_GUN_VISUAL_STATES = 64
local GUN_VISUAL_STATE_MIN_INTERVAL = 1 / 20
local MAX_REPLICATED_AIM_COORDINATE = 1000000
local nextProjectileVisualId = 0

-- Interest + load cap for OTHER players' projectile visuals; own shots are never culled
-- or capped. Enforced server-side in admitNewProjectiles.
local OTHER_PROJECTILE_VIEW_RADIUS = 500
local OTHER_PROJECTILE_VIEW_RADIUS_SQ = OTHER_PROJECTILE_VIEW_RADIUS * OTHER_PROJECTILE_VIEW_RADIUS
-- Aggregate spawns/sec a viewer accepts; over budget, nearest win. ~rate * lifetime on screen.
local OTHER_PROJECTILE_ADMIT_RATE_PER_SECOND = 60
-- Tokens a viewer can bank while idle (burst ceiling).
local OTHER_PROJECTILE_ADMIT_BURST = 90

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function getWeaponDefinition(gunName: string): WeaponDefinitions.WeaponDefinition?
	local directDefinition = WeaponDefinitions[gunName]
	if directDefinition then
		return directDefinition
	end

	local loweredGunName = string.lower(gunName)
	for definitionName, definition in WeaponDefinitions do
		if string.lower(definitionName) == loweredGunName then
			return definition
		end

		if string.lower(definition.label) == loweredGunName then
			return definition
		end
	end

	return nil
end

local function getProfile(player: Player): {[string]: any}?
	local dataService = GunService.Services.DataService
	if not dataService then
		return nil
	end

	if dataService.Profiles[player] == nil then
		return nil
	end

	return dataService:GetProfile(player)
end

local function getWeaponData(profile: {[string]: any}, weaponKey: string): InventoryUtil.WeaponData?
	local weapons = profile.Inventory.Weapons
	local weaponValue = weapons.Equipped[weaponKey] or weapons.Owned[weaponKey]
	if weaponValue == nil then
		return nil
	end

	return InventoryUtil.getWeaponData(weaponKey, weaponValue)
end

local function getCharacterGunFolder(player: Player, shouldCreate: boolean): Folder?
	local character = player.Character
	if not character then
		return nil
	end

	local existingFolder = character:FindFirstChild(REPLICATED_GUN_FOLDER_NAME)
	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	if not shouldCreate then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = REPLICATED_GUN_FOLDER_NAME
	folder.Parent = character

	return folder
end

local function getDescriptorGunId(descriptor: Instance): string
	local gunId = descriptor:GetAttribute("GunId")
	if type(gunId) ~= "string" or gunId == "" then
		return descriptor.Name
	end

	return gunId
end

local function getAmmoCount(profile: {[string]: any}, ammoType: string): number
	return profile.Inventory.Items[ammoType] or 0
end

local function getAmmoData(profile: {[string]: any}): {[string]: any}
	if type(profile.Ammo) ~= "table" then
		profile.Ammo = AmmoTypes.createProfileData()
	end

	local ammoData = profile.Ammo
	if not AmmoTypes.isKnown(ammoData.SelectedType) then
		ammoData.SelectedType = AmmoTypes.Default
	end

	return ammoData
end

local function sendAmmoState(player: Player, profile: {[string]: any}?)
	profile = profile or getProfile(player)
	if not profile then
		return
	end

	local ammoData = getAmmoData(profile)
	local character = player.Character
	if character then
		for _, ammoType in AmmoTypes.Consumable do
			character:SetAttribute(ammoType, getAmmoCount(profile, ammoType))
		end
	end

	GunEvent:FireClient(player, "AmmoState", ammoData.SelectedType)
end

local function resolveAutoEquipFallback(profile: {[string]: any}, ammoData: {[string]: any}): string
	local fallback = AmmoTypes.Default
	local fallbackOrder = -math.huge

	for _, ammoType in AmmoTypes.Consumable do
		if ammoData.AutoEquip[ammoType] and getAmmoCount(profile, ammoType) > 0 then
			local order = AmmoTypes.getOrder(ammoType)
			if order > fallbackOrder then
				fallbackOrder = order
				fallback = ammoType
			end
		end
	end

	return fallback
end

local function consumeSelectedAmmo(player: Player): (boolean, string)
	local profile = getProfile(player)
	if not profile then
		return false, AmmoTypes.Default
	end

	local ammoData = getAmmoData(profile)
	local ammoType = ammoData.SelectedType
	if not AmmoTypes.isConsumable(ammoType) then
		return true, ammoType
	end

	local amount = getAmmoCount(profile, ammoType)
	if amount <= 0 then
		ammoData.SelectedType = resolveAutoEquipFallback(profile, ammoData)
		sendAmmoState(player, profile)
		return false, ammoType
	end

	local items = profile.Inventory.Items
	amount -= 1

	if amount <= 0 then
		items[ammoType] = nil
		ammoData.SelectedType = resolveAutoEquipFallback(profile, ammoData)
		sendAmmoState(player, profile)
		remotes.InventoryUpdated:FireClient(player, "Items", items)
	else
		items[ammoType] = amount
		local character = player.Character
		if character then
			character:SetAttribute(ammoType, amount)
		end
	end

	return true, ammoType
end

local function sampleSpreadOffset(moa: number?): Vector2
	if type(moa) ~= "number" or moa <= 0 then
		return Vector2.new()
	end

	local spreadRadians = math.rad(moa / 60)
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

local function getFireKey(player: Player, gunId: string): string
	return `{player.UserId}:{gunId}`
end

local function createShootOriginPart(shootCFrame: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = "GunShotOrigin"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = shootCFrame
	part.Parent = SHOOT_IGNORE

	return part
end

local function getNextProjectileVisualId(player: Player): string
	nextProjectileVisualId += 1
	return `{player.UserId}:{nextProjectileVisualId}`
end

local function collectPlayerPositions(): {[Player]: Vector3}
	local positions = {}
	for _, otherPlayer in Players:GetPlayers() do
		local character = otherPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			positions[otherPlayer] = rootPart.Position
		end
	end

	return positions
end

-- Freezes each new projectile's recipient set: the owner always, plus nearby players
-- admitted nearest-first against their per-viewer token budget. Never recomputed, so a
-- viewer that sees the spawn also gets its segments/end. Returns the spawns admitted now.
local function admitNewProjectiles(playerPositions: {[Player]: Vector3}, deltaTime: number): {ActiveProjectile}
	-- Refill buckets, clamped to the burst ceiling.
	for _, viewer in Players:GetPlayers() do
		local tokens = GunService.ViewerProjectileTokens[viewer] or OTHER_PROJECTILE_ADMIT_BURST
		GunService.ViewerProjectileTokens[viewer] = math.min(
			OTHER_PROJECTILE_ADMIT_BURST,
			tokens + OTHER_PROJECTILE_ADMIT_RATE_PER_SECOND * deltaTime
		)
	end

	local newlyAdmitted = {}
	local candidatesByViewer = {} :: {[Player]: {{ entry: ActiveProjectile, distanceSquared: number }}}
	for _, activeProjectile in ipairs(GunService.ActiveProjectiles) do
		-- Skip anything already admitted or with no spawn to send.
		if activeProjectile.recipients ~= nil or activeProjectile.spawnPayload == nil then
			continue
		end

		local recipients = {}
		activeProjectile.recipients = recipients
		table.insert(newlyAdmitted, activeProjectile)

		local owner = activeProjectile.owner
		if owner and owner.Parent then
			table.insert(recipients, owner) -- owner always, uncapped
		end

		local origin = activeProjectile.spawnOrigin
		for viewer, position in playerPositions do
			if viewer == owner then
				continue
			end

			local offset = position - origin
			local distanceSquared = offset:Dot(offset) -- squared, no sqrt
			if distanceSquared <= OTHER_PROJECTILE_VIEW_RADIUS_SQ then
				local viewerCandidates = candidatesByViewer[viewer]
				if not viewerCandidates then
					viewerCandidates = {}
					candidatesByViewer[viewer] = viewerCandidates
				end
				table.insert(viewerCandidates, { entry = activeProjectile, distanceSquared = distanceSquared })
			end
		end
	end

	-- Spend each viewer's budget nearest-first; the rest are dropped for them.
	for viewer, viewerCandidates in candidatesByViewer do
		table.sort(viewerCandidates, function(left, right)
			return left.distanceSquared < right.distanceSquared
		end)

		local tokens = GunService.ViewerProjectileTokens[viewer] or 0
		for _, candidate in ipairs(viewerCandidates) do
			if tokens < 1 then
				break
			end
			tokens -= 1
			table.insert(candidate.entry.recipients, viewer)
		end
		GunService.ViewerProjectileTokens[viewer] = tokens
	end

	return newlyAdmitted
end

-- Per tick: admit new projectiles, step every live one, and flush one batch per viewer
-- (each gets only the projectiles relevant to them, not a broadcast to everyone).
local function updateProjectiles(deltaTime: number)
	local playerPositions = collectPlayerPositions()
	local newlyAdmitted = admitNewProjectiles(playerPositions, deltaTime)

	-- Per-viewer batches. Payload tables are shared by reference (FireClient copies per send).
	local batchesByViewer = {} :: {[Player]: { spawns: {any}, segments: {any}, ends: {any} }}
	local function getViewerBatch(viewer: Player)
		local batch = batchesByViewer[viewer]
		if not batch then
			batch = { spawns = {}, segments = {}, ends = {} }
			batchesByViewer[viewer] = batch
		end
		return batch
	end

	-- Send spawns before this tick's segments/ends so the client has the projectile first.
	for _, activeProjectile in ipairs(newlyAdmitted) do
		local spawnPayload = activeProjectile.spawnPayload
		activeProjectile.spawnPayload = nil
		if spawnPayload then
			for _, viewer in ipairs(activeProjectile.recipients :: {Player}) do
				table.insert(getViewerBatch(viewer).spawns, spawnPayload)
			end
		end
	end

	for index = #GunService.ActiveProjectiles, 1, -1 do
		local activeProjectile = GunService.ActiveProjectiles[index]
		local projectile = activeProjectile.projectile

		-- Simulate regardless of audience; visual culling never affects gameplay.
		if projectile.isValid then
			projectile:update(deltaTime)
		end

		local recipients = activeProjectile.recipients
		local hasRecipients = recipients ~= nil and #recipients > 0

		-- Always drain the buffer (else it grows unwatched); route only if anyone sees it.
		local projectileVisualSegments = projectile:consumeVisualSegments()
		if hasRecipients then
			for _, payload in ipairs(projectileVisualSegments) do
				for _, viewer in ipairs(recipients :: {Player}) do
					table.insert(getViewerBatch(viewer).segments, payload)
				end
			end
		end

		if not projectile.isValid then
			local visualEnd = projectile:consumeVisualEnd()
			if visualEnd and hasRecipients then
				for _, viewer in ipairs(recipients :: {Player}) do
					table.insert(getViewerBatch(viewer).ends, visualEnd)
				end
			end

			local shootOriginPart = activeProjectile.shootOriginPart
			if shootOriginPart and shootOriginPart.Parent then
				shootOriginPart:Destroy()
			end
			table.remove(GunService.ActiveProjectiles, index)
		end
	end

	-- One remote per viewer with anything to send; skip players who left mid-tick.
	for viewer, batch in batchesByViewer do
		if viewer.Parent and (#batch.spawns > 0 or #batch.segments > 0 or #batch.ends > 0) then
			remotes.ProjectileVisuals:FireClient(viewer, "Batch", batch)
		end
	end
end

local function canFire(player: Player, gunId: string, weaponDefinition: WeaponDefinitions.WeaponDefinition): boolean
	local fireInterval = if weaponDefinition.tbs > 0 then weaponDefinition.tbs else 0

	if fireInterval <= 0 then
		return true
	end

	local fireKey = getFireKey(player, gunId)
	local now = os.clock()
	local lastFireTime = GunService.LastFireTime[fireKey] or 0
	if now - lastFireTime < fireInterval * FIRE_RATE_TOLERANCE then
		return false
	end

	return true
end

local function isFiniteReplicatedCoordinate(value: any): boolean
	return type(value) == "number"
		and value == value
		and value > -MAX_REPLICATED_AIM_COORDINATE
		and value < MAX_REPLICATED_AIM_COORDINATE
end

local function isValidReplicatedVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and isFiniteReplicatedCoordinate(value.X)
		and isFiniteReplicatedCoordinate(value.Y)
		and isFiniteReplicatedCoordinate(value.Z)
end

local function sanitizeGunVisualStates(player: Player, visualStates: any): {{[string]: any}}
	local sanitizedStates = {}
	if type(visualStates) ~= "table" then
		return sanitizedStates
	end

	local activeGuns = GunService.ActiveGunsByPlayer[player]
	if not activeGuns then
		return sanitizedStates
	end

	for _, visualState in ipairs(visualStates) do
		if type(visualState) ~= "table" then
			continue
		end

		local gunId = visualState.gunId
		local aimPoint = visualState.aimPoint
		if type(gunId) ~= "string" or gunId == "" then
			continue
		end

		if not activeGuns[gunId] or not isValidReplicatedVector3(aimPoint) then
			continue
		end

		table.insert(sanitizedStates, {
			gunId = gunId,
			aimPoint = aimPoint,
			hasShootTarget = visualState.hasShootTarget == true,
			shooting = visualState.shooting == true,
		})

		if #sanitizedStates >= MAX_GUN_VISUAL_STATES then
			break
		end
	end

	return sanitizedStates
end

local function fireOtherClients(player: Player, action: string, ...)
	for _, recipient in Players:GetPlayers() do
		if recipient ~= player then
			GunEvent:FireClient(recipient, action, ...)
		end
	end
end

local function handleGunVisualState(player: Player, visualStates: any)
	local now = os.clock()
	local lastVisualStateTime = GunService.LastVisualStateTime[player] or 0
	if now - lastVisualStateTime < GUN_VISUAL_STATE_MIN_INTERVAL then
		return
	end

	local sanitizedStates = sanitizeGunVisualStates(player, visualStates)
	if #sanitizedStates <= 0 then
		return
	end

	GunService.LastVisualStateTime[player] = now
	fireOtherClients(player, "GunVisualState", player.UserId, sanitizedStates)
end

local function handleShoot(
	player: Player,
	gunId: string,
	shootCFrame: CFrame,
	shootDirection: Vector3,
	showRays: boolean?,
	gunName: string?
)
	if type(gunId) ~= "string" or gunId == "" then
		return
	end
	if type(gunName) ~= "string" or gunName == "" then
		return
	end
	if typeof(shootCFrame) ~= "CFrame" or typeof(shootDirection) ~= "Vector3" then
		return
	end
	if shootDirection.Magnitude <= 0 then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local rootPart = humanoid.RootPart
	if not rootPart then
		return
	end
	if (shootCFrame.Position - rootPart.Position).Magnitude > MAX_SHOT_DISTANCE_FROM_CHARACTER then
		return
	end

	local profile = getProfile(player)
	if not profile then
		return
	end

	local weapons = profile.Inventory.Weapons
	local activeGuns = GunService.ActiveGunsByPlayer[player]
	if not activeGuns then
		return
	end

	local weaponKey = activeGuns[gunId]
	if not weaponKey or weapons.Equipped[weaponKey] == nil then
		return
	end

	local weaponData = getWeaponData(profile, weaponKey)
	if not weaponData or weaponData.weaponName ~= gunName then
		return
	end

	local weaponDefinition = getWeaponDefinition(weaponData.weaponName)
	if not weaponDefinition then
		return
	end

	if not canFire(player, gunId, weaponDefinition) then
		return
	end

	local consumedAmmo, ammoType = consumeSelectedAmmo(player)
	if not consumedAmmo then
		return
	end
	GunService.LastFireTime[getFireKey(player, gunId)] = os.clock()

	shootDirection = shootDirection.Unit
	local acceptedShootCFrame = CFrame.new(shootCFrame.Position, shootCFrame.Position + shootDirection)
	fireOtherClients(player, "GunVisualShot", player.UserId, gunId, acceptedShootCFrame, shootDirection)

	-- Energy weapons (and any future cosmetic variant) re-skin Normal bullets: the
	-- gameplay ammoType stays "Normal", only the visual/audio bullet folder changes.
	-- Consumable ammo (Smart/Incendiary/Explosive) keeps its own visual.
	local bulletVisualName = ammoType
	if ammoType == AmmoTypes.Default and type(weaponDefinition.normalBulletOverride) == "string" then
		bulletVisualName = weaponDefinition.normalBulletOverride
	end

	local pelletCount = DEFAULT_PELLETS
	if type(weaponDefinition.pellets) == "number" and weaponDefinition.pellets > 0 then
		pelletCount = math.max(1, math.floor(weaponDefinition.pellets))
	end

	local derivedStats = WeaponUtil.deriveWeaponStats(weaponData)

	for pelletIndex = 1, pelletCount do
		local pelletDirection = shootDirection
		if pelletCount > 1 then
			pelletDirection = applySpreadOffset(shootDirection, sampleSpreadOffset(weaponDefinition.moa))
		end

		local pelletShootCFrame = CFrame.new(shootCFrame.Position, shootCFrame.Position + pelletDirection)
		local shootOriginPart = createShootOriginPart(pelletShootCFrame)
		local projectileVisualId = getNextProjectileVisualId(player)
		local projectile = Projectile.new(shootOriginPart, {
			showRays = showRays == true,
			shootFrom = pelletShootCFrame,
			shootFromVisual = shootCFrame.Position,
			shootTowards = pelletDirection,
			forwardVelocity = weaponDefinition.bulletVelocity or weaponDefinition.forwardVelocity,
			acceleration = weaponDefinition.bulletAcceleration,
			maxBulletDistance = weaponDefinition.maxBulletDistance,
			damage = derivedStats.damage,
			headshotMult = weaponDefinition.headshotMultiplier or DEFAULT_HEADSHOT_MULTIPLIER,
			player = player,
			ignoreCharacter = character,
			ammoType = ammoType,
			isExplosive = weaponDefinition.isExplosive == true,
			blastRadius = weaponDefinition.blastRadius,
			ricochet = weaponDefinition.ricochet,
			penetrations = weaponDefinition.penetrations,
			visualId = projectileVisualId,
		}, bulletVisualName)

		local visualSpawnPayload = projectile:getVisualSpawnPayload()

		-- recipients left nil; admission runs next tick in admitNewProjectiles.
		table.insert(GunService.ActiveProjectiles, {
			projectile = projectile,
			shootOriginPart = shootOriginPart,
			owner = player,
			spawnOrigin = shootCFrame.Position,
			spawnPayload = visualSpawnPayload,
			recipients = nil,
		})
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function GunService:AddGun(player: Player, weaponKey: string, gunId: string?): string?
	if not player or type(weaponKey) ~= "string" or weaponKey == "" then
		return nil
	end
	local runtimeGunId = if type(gunId) == "string" and gunId ~= "" then gunId else weaponKey

	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local weaponData = getWeaponData(profile, weaponKey)
	if not weaponData then
		return nil
	end

	local gunName = weaponData.weaponName
	if not getWeaponDefinition(gunName) then
		return nil
	end

	local gunFolder = getCharacterGunFolder(player, true)
	if not gunFolder then
		return nil
	end

	local descriptor = gunFolder:FindFirstChild(runtimeGunId)
	if descriptor and not descriptor:IsA("StringValue") then
		descriptor:Destroy()
		descriptor = nil
	end

	if not descriptor then
		descriptor = Instance.new("StringValue")
		descriptor.Name = runtimeGunId
	end

	descriptor.Value = gunName
	descriptor:SetAttribute("GunId", runtimeGunId)
	descriptor:SetAttribute("WeaponKey", weaponKey)
	descriptor:SetAttribute("WeaponName", gunName)
	descriptor.Parent = gunFolder

	local activeGuns = self.ActiveGunsByPlayer[player]
	if not activeGuns then
		activeGuns = {}
		self.ActiveGunsByPlayer[player] = activeGuns
	end
	activeGuns[runtimeGunId] = weaponKey

	return runtimeGunId
end

function GunService:RemoveGun(player: Player, gunId: string): boolean
	if not player or type(gunId) ~= "string" or gunId == "" then
		return false
	end

	local removed = false
	local gunFolder = getCharacterGunFolder(player, false)
	if gunFolder then
		for _, descriptor in gunFolder:GetChildren() do
			if getDescriptorGunId(descriptor) == gunId then
				descriptor:Destroy()
				removed = true
			end
		end
	end

	local activeGuns = self.ActiveGunsByPlayer[player]
	if activeGuns then
		removed = removed or activeGuns[gunId] ~= nil
		activeGuns[gunId] = nil
	end
	self.LastFireTime[getFireKey(player, gunId)] = nil

	return removed
end

function GunService:ClearGuns(player: Player): boolean
	if not player then
		return false
	end

	local gunFolder = getCharacterGunFolder(player, false)
	if gunFolder then
		for _, descriptor in gunFolder:GetChildren() do
			self.LastFireTime[getFireKey(player, getDescriptorGunId(descriptor))] = nil
			descriptor:Destroy()
		end
	end

	local activeGuns = self.ActiveGunsByPlayer[player]
	if activeGuns then
		for gunId in activeGuns do
			self.LastFireTime[getFireKey(player, gunId)] = nil
		end
	end
	self.ActiveGunsByPlayer[player] = nil

	return true
end

function GunService:SyncEquippedWeapons(player: Player): boolean
	if not player then
		return false
	end

	local profile = getProfile(player)
	if not profile then
		return false
	end

	local weapons = profile.Inventory.Weapons

	local desiredGuns = {}
	for weaponKey, weaponValue in weapons.Equipped do
		local weaponData = InventoryUtil.getWeaponData(weaponKey, weaponValue)
		if getWeaponDefinition(weaponData.weaponName) then
			if InventoryUtil.isStack(weaponKey) then
				for index = 1, weaponValue do
					desiredGuns[`{weaponKey}:{index}`] = weaponKey
				end
			else
				desiredGuns[weaponKey] = weaponKey
			end
		end
	end

	local activeGuns = self.ActiveGunsByPlayer[player]
	if not activeGuns then
		activeGuns = {}
		self.ActiveGunsByPlayer[player] = activeGuns
	end

	local activeSnapshot = table.clone(activeGuns)
	for gunId in activeSnapshot do
		if desiredGuns[gunId] == nil then
			self:RemoveGun(player, gunId)
		end
	end

	local gunFolder = getCharacterGunFolder(player, false)
	if gunFolder then
		for _, descriptor in gunFolder:GetChildren() do
			local descriptorGunId = getDescriptorGunId(descriptor)
			if desiredGuns[descriptorGunId] == nil then
				self.LastFireTime[getFireKey(player, descriptorGunId)] = nil
				descriptor:Destroy()
			end
		end
	end

	for gunId, weaponKey in desiredGuns do
		self:AddGun(player, weaponKey, gunId)
	end

	return true
end

function GunService:SetProjectileRays(player: Player, enabled: boolean): boolean
	if not player then
		return false
	end

	return remotes.SetProjectileRays:InvokeClient(player, enabled == true) == true
end

function GunService:SetSelectedAmmoType(player: Player, ammoType: string): string?
	if not player then
		return nil
	end

	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local ammoData = getAmmoData(profile)
	if not AmmoTypes.isKnown(ammoType) then
		return nil
	end

	ammoData.SelectedType = ammoType
	sendAmmoState(player, profile)

	return ammoType
end

function GunService:ToggleAutoEquipForAmmo(player: Player, ammoType: string): boolean?
	if not AmmoTypes.isKnown(ammoType) then
		return nil
	end

	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local ammoData = getAmmoData(profile)
	local newState = not ammoData.AutoEquip[ammoType]
	ammoData.AutoEquip[ammoType] = newState

	return newState
end

function GunService:GetSelectedAmmoType(player: Player): string
	local profile = getProfile(player)
	if not profile then
		return AmmoTypes.Default
	end

	local ammoData = getAmmoData(profile)
	return ammoData.SelectedType
end

function GunService:GetAmmoView(player: Player): {[string]: any}?
	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local ammoData = getAmmoData(profile)
	return {
		SelectedType = ammoData.SelectedType,
		AutoEquip = table.clone(ammoData.AutoEquip),
	}
end

function GunService:GetAmmoAmount(player: Player, ammoType: string): number?
	if not AmmoTypes.isConsumable(ammoType) then
		return nil
	end

	local profile = getProfile(player)
	if not profile then
		return 0
	end

	return getAmmoCount(profile, ammoType)
end

function GunService:OnAmmoItemAdded(player: Player, ammoType: string)
	local profile = getProfile(player)
	if not profile then
		return
	end

	local ammoData = getAmmoData(profile)
	if ammoData.AutoEquip[ammoType] then
		ammoData.SelectedType = ammoType
	end

	sendAmmoState(player, profile)
end

function GunService:ResetAmmo(player: Player): (boolean, string)
	if not player then
		return false, "Player is required"
	end

	local profile = getProfile(player)
	if not profile then
		return false, `Profile is not loaded for {player.Name}`
	end

	profile.Ammo = AmmoTypes.createProfileData()

	local items = profile.Inventory.Items
	for _, ammoType in AmmoTypes.Consumable do
		items[ammoType] = nil
	end
	remotes.InventoryUpdated:FireClient(player, "Items", items)

	sendAmmoState(player, profile)

	return true, `Ammo reset for {player.Name}`
end

function GunService:SendAmmoState(player: Player)
	if not player then
		return
	end

	sendAmmoState(player)
end

function GunService:IncrementGunXP(player: Player, weaponKey: string, xpAmount: number)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[IncrementGunXP] No profile for player", player) return end
	
	local owned = profile.Inventory.Weapons.Owned
	
	local weaponEntry = owned[weaponKey]
	if not weaponEntry then warn("[IncrementGunXP] No weapon entry for", player, weaponKey) return end
	
	if InventoryUtil.isStack(weaponKey) then
		local weaponData = InventoryUtil.getWeaponData(weaponKey, weaponEntry)
		
		-- create new unique weapon entry
		local newKey = InventoryUtil.generateWeaponKey(weaponData)
		owned[newKey] = weaponData
		owned[newKey].xp += xpAmount
		
		-- subtract from stacked entry
		weaponEntry -= 1 
		
		-- remove if empty
		if weaponEntry <= 0 then
			owned[weaponKey] = nil
		end
	else
		weaponEntry.xp += xpAmount
	end
	
	-- Update client
	local maxSlots = self.Services.UpgradeService:GetGunSlots(player)
	remotes.InventoryUpdated:FireClient(player, "Weapons", profile.Inventory.Weapons, maxSlots)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function GunService:Init(services)
	self.Services = services
end

function GunService:Start()
	RunService.Heartbeat:Connect(updateProjectiles)

	GunEvent.OnServerEvent:Connect(function(player: Player, action: string, ...)
		if type(action) ~= "string" then
			return
		end

		if action == "Shoot" then
			handleShoot(player, ...)
		elseif action == "GunVisualState" then
			handleGunVisualState(player, ...)
		elseif action == "SetAmmoType" then
			local ammoType = ...
			GunService:SetSelectedAmmoType(player, ammoType)
		end
	end)

	remotes.ToggleAutoEquipForAmmo.OnServerInvoke = function(player: Player, ammoType: string)
		return GunService:ToggleAutoEquipForAmmo(player, ammoType)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		GunService.ActiveGunsByPlayer[player] = nil
		GunService.LastVisualStateTime[player] = nil
		GunService.ViewerProjectileTokens[player] = nil
		local characterConnection = GunService.PlayerCharacterConnections[player]
		if characterConnection then
			characterConnection:Disconnect()
			GunService.PlayerCharacterConnections[player] = nil
		end

		local fireKeyPrefix = `{player.UserId}:`
		for fireKey in GunService.LastFireTime do
			if string.sub(fireKey, 1, #fireKeyPrefix) == fireKeyPrefix then
				GunService.LastFireTime[fireKey] = nil
			end
		end
	end)

	local function bindPlayer(player: Player)
		GunService.PlayerCharacterConnections[player] = player.CharacterAdded:Connect(function()
			GunService.ActiveGunsByPlayer[player] = nil
			task.defer(function()
				self:SendAmmoState(player)
				self:SyncEquippedWeapons(player)
			end)
		end)

		if player.Character then
			task.defer(function()
				self:SendAmmoState(player)
				self:SyncEquippedWeapons(player)
			end)
		end
	end

	Players.PlayerAdded:Connect(bindPlayer)

	local dataService = self.Services.DataService
	if dataService and dataService.Signals and dataService.Signals.DataLoaded then
		dataService.Signals.DataLoaded:Connect(function(player: Player)
			self:SendAmmoState(player)
			self:SyncEquippedWeapons(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
		if player:GetAttribute("Loaded") == true then
			self:SendAmmoState(player)
			self:SyncEquippedWeapons(player)
		end
	end
end

return GunService
