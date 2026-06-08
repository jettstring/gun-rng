local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local EnemySteering = require(ReplicatedStorage.Util.EnemySteering)
local EnemyAssets = ReplicatedStorage.GameAssets:WaitForChild("EnemyAssets")

local EnemyDefinitions = require(EnemyAssets:WaitForChild("EnemyDefinitions") :: ModuleScript)
local ZoneDefinitions = require(ReplicatedStorage.GameAssets.ZoneAssets.ZoneDefinitions)
local ItemAssets = ReplicatedStorage.GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets:WaitForChild("ItemDefinitions") :: ModuleScript)

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type EnemyDefinition = EnemyDefinitions.EnemyDefinition
type ZoneDefinition = ZoneDefinitions.ZoneDefinition
type ItemDefinition = ItemDefinitions.ItemDefinition

type ZoneContext = {
	id: string,
	model: Instance,
	logicParts: Folder,
	definition: ZoneDefinition,
	detector: BasePart,
	spawnZones: { BasePart },
	floorParts: { BasePart },
	boundsParts: { BasePart },
}

type EnemyRecord = {
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	owner: Player,
	zoneContext: ZoneContext,
	definition: EnemyDefinition,
	cashReward: number,
	tagReward: number,
	removed: boolean,
	rewarded: boolean,
}

type DropKind = "Currency" | "Item"

type DropSpec = {
	dropName: string,
	amount: number,
	color: Color3?,
	pickupWeight: number?,
	requiresMagnetRange: boolean?,
}

type DropRecord = {
	id: string,
	owner: Player,
	dropName: string,
	amount: number,
	pickupWeight: number,
	requiresMagnetRange: boolean,
	sourcePosition: Vector3,
	restPosition: Vector3,
	createdAt: number,
	landAt: number,
	expiresAt: number,
	claimed: boolean,
}

type DropPayload = {
	id: string,
	groupId: string,
	dropName: string,
	amount: number,
	pickupWeight: number,
	requiresMagnetRange: boolean,
	requiresServerCollect: boolean,
	sourcePosition: Vector3,
	restPosition: Vector3,
	createdAt: number,
	landAt: number,
	expiresAt: number,
	color: Color3?,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------
local EnemyService = {}
EnemyService.Services = {}
EnemyService.Signals = {}
EnemyService.ActiveZoneByPlayer = {} :: { [Player]: ZoneContext }
EnemyService.ActiveEnemiesByPlayer = {} :: { [Player]: { EnemyRecord } }
EnemyService.LastSpawnAtByPlayer = {} :: { [Player]: number }
EnemyService.PlayerConnections = {} :: { [Player]: RBXScriptConnection }
EnemyService.ZoneContexts = {} :: { [string]: ZoneContext }
EnemyService.PendingDrops = {} :: { [string]: DropRecord }
EnemyService.CollectAttemptsByPlayer = {} :: { [Player]: { windowStartedAt: number, count: number } }
EnemyService.EnemyCollisionGroupNames = {} :: { string }
EnemyService.EnemyCollisionGroupByPlayer = {} :: { [Player]: string }
EnemyService.EnemyCollisionGroupOwnerByName = {} :: { [string]: Player }

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local ENEMY_TAG_PREFIX = "Enemy-"
local ENEMIES_FOLDER_NAME = "Enemies"
local ENEMY_DEFAULT_COLLISION_GROUP = "Enemy"
local ENEMY_OWNER_COLLISION_GROUP_PREFIX = "EnemyOwner"
local PLAYER_COLLISION_GROUP = "Player"
local PROPS_COLLISION_GROUP = "Props"
local ZONES_WAIT_TIMEOUT = 10
local ZONE_DETECTION_INTERVAL = 0.1
local LOGIC_PARTS_FOLDER_NAME = "LogicParts"

local SPAWN_ATTEMPT_INTERVAL = 0.2
local DEFAULT_SPAWN_INTERVAL = 0.2
local MIN_SPAWN_INTERVAL = 0.05
local MAX_SPAWNS_PER_TICK = 4
local STEER_INTERVAL = 1 / 30
local MAX_STEER_DT = 0.1
local ENEMY_DESPAWN_DISTANCE =500
local SPAWN_GROUND_CLEARANCE = 0
local SPAWN_ROOT_HEIGHT_FALLBACK = 4
local DEAD_ENEMY_CLEANUP_DELAY = 2
local XZ_BOUNDS_EPSILON = 0.25
local FLOOR_Y = 0.5
local FLOOR_TAG = "Floor"
local FLOOR_RAY_ORIGIN_HEIGHT = 50
local FLOOR_RAY_DISTANCE = 250
local FLOOR_RAY_DIRECTION = Vector3.new(0, -FLOOR_RAY_DISTANCE, 0)
local SERVER_PICKUP_GRACE_DISTANCE = 10
local DROP_RADIUS = 20
local MIN_ARC_DURATION = 0.45
local MAX_ARC_DURATION = 0.75
local DROP_STAGGER_SECONDS = 0.03
local DROP_EXPIRY_SECONDS = 30
local DOGTAG_MAX_DROPS = 1
local MAX_COLLECT_ATTEMPTS_PER_SECOND = 80

local MONEY_GREEN_COLOR = Color3.fromRGB(7, 255, 9)
local MONEY_BLUE_COLOR = Color3.new(0, 0.502296, 0.977737)
local MONEY_PURPLE_COLOR = Color3.new(0.792996, 0.00207523, 1)
local DEFAULT_DROP_PICKUP_WEIGHT = 1
local DEFAULT_ITEM_DROP_WEIGHT = 3
local DEFAULT_REQUIRES_MAGNET_RANGE = true
local CURRENCY_DROP_NAMES = {
	Money = true,
	Dogtags = true,
}
local DROP_SETTINGS = {
	Money = {
		pickupWeight = 1,
		requiresMagnetRange = false,
	},
	Dogtags = {
		pickupWeight = 2.5,
		requiresMagnetRange = false,
	},
}

local random = Random.new()
local steeringConfig = EnemySteering.DefaultConfig
local steeringHash = EnemySteering.newSpatialHash(steeringConfig.separationRadius)
local floorRaycastParams = RaycastParams.new()
local detectorOverlapParams = OverlapParams.new()
detectorOverlapParams.FilterType = Enum.RaycastFilterType.Include
detectorOverlapParams.MaxParts = 1
local enemiesFolder: Folder
local spawnCurrencyDropsRemote: RemoteEvent
local collectCurrencyDropRemote: RemoteEvent

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local child = parent:FindFirstChild(name)
	if child then
		assert(child:IsA("Folder"), `{parent:GetFullName()}.{name} must be a Folder`)
		return child
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	return folder
end

local function getRemoteEvent(parent: Instance, name: string): RemoteEvent
	local child = parent:FindFirstChild(name)
	assert(child and child:IsA("RemoteEvent"), `{parent:GetFullName()}.{name} must be a RemoteEvent`)

	return child
end

local function ensureCollisionGroup(name: string): boolean
	local success, result = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(name)
	end)

	if success and result then
		return true
	end

	success, result = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)

	if not success then
		warn(`[EnemyService] Failed to register collision group "{name}": {result}`)
		return false
	end

	return true
end

local function configureEnemyCollisionGroups()
	if not ensureCollisionGroup(ENEMY_DEFAULT_COLLISION_GROUP)
		or not ensureCollisionGroup(PLAYER_COLLISION_GROUP)
		or not ensureCollisionGroup(PROPS_COLLISION_GROUP)
	then
		return
	end

	PhysicsService:CollisionGroupSetCollidable(ENEMY_DEFAULT_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(ENEMY_DEFAULT_COLLISION_GROUP, PROPS_COLLISION_GROUP, false)

	table.clear(EnemyService.EnemyCollisionGroupNames)
	table.clear(EnemyService.EnemyCollisionGroupByPlayer)
	table.clear(EnemyService.EnemyCollisionGroupOwnerByName)

	local desiredOwnerGroupCount = 10
	for index = 1, desiredOwnerGroupCount do
		local groupName = `{ENEMY_OWNER_COLLISION_GROUP_PREFIX}{index}`
		if not ensureCollisionGroup(groupName) then
			break
		end

		PhysicsService:CollisionGroupSetCollidable(groupName, ENEMY_DEFAULT_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(groupName, PLAYER_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(groupName, PROPS_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(groupName, groupName, true)

		for _, otherGroupName in EnemyService.EnemyCollisionGroupNames do
			PhysicsService:CollisionGroupSetCollidable(groupName, otherGroupName, false)
		end

		table.insert(EnemyService.EnemyCollisionGroupNames, groupName)
	end

	if #EnemyService.EnemyCollisionGroupNames < desiredOwnerGroupCount then
		local registeredCollisionGroups = #PhysicsService:GetRegisteredCollisionGroups()
		local maxCollisionGroups = PhysicsService:GetMaxCollisionGroups()
		warn(
			`[EnemyService] Registered {#EnemyService.EnemyCollisionGroupNames}/{desiredOwnerGroupCount} enemy owner collision groups. `
				.. `Collision groups in use: {registeredCollisionGroups}/{maxCollisionGroups}. `
				.. "Extra players will not spawn enemies until a group is available."
		)
	end
end

local function roundNonNegative(value: number): number
	return math.max(0, math.floor(value + 0.5))
end

local function getDropKind(dropName: string): DropKind?
	if CURRENCY_DROP_NAMES[dropName] == true then
		return "Currency"
	end

	if ItemDefinitions[dropName] ~= nil then
		return "Item"
	end

	return nil
end

local function warnItemCurrencyNameCollisions()
	for itemName in ItemDefinitions do
		if CURRENCY_DROP_NAMES[itemName] == true then
			warn(`[EnemyService] Item name "{itemName}" collides with a currency drop name. It will resolve as currency.`)
		end
	end
end

local function getCharacterRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getPlayerRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return getCharacterRootPart(character)
end

local function getModelHumanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function findFirstBasePart(model: Model): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getModelRootPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		model.PrimaryPart = rootPart
		return rootPart
	end

	local firstBasePart = findFirstBasePart(model)
	if firstBasePart then
		model.PrimaryPart = firstBasePart
	end

	return firstBasePart
end

local function getBasePartsNamed(root: Instance, name: string): { BasePart }
	local parts = {}

	for _, descendant in root:GetDescendants() do
		if descendant.Name == name and descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getLogicParts(zoneModel: Instance): Folder?
	local logicParts = zoneModel:FindFirstChild(LOGIC_PARTS_FOLDER_NAME)
	if logicParts and logicParts:IsA("Folder") then
		return logicParts
	end

	warn(`[EnemyService] Workspace.Zones.{zoneModel.Name} needs a Folder named {LOGIC_PARTS_FOLDER_NAME}`)
	return nil
end

local function addEnemyTags(model: Model, owner: Player?, collisionGroupName: string, manageNetworkOwnership: boolean)
	CollectionService:AddTag(model, "Enemy")

	if owner then
		CollectionService:AddTag(model, `{ENEMY_TAG_PREFIX}{owner.Name}`)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, "Penetrate")
			descendant.CollisionGroup = collisionGroupName
			-- Anchored (kinematic) enemies are server-authoritative by virtue of
			-- being anchored, so setting network ownership is pointless work (and
			-- errors on anchored / welded-to-anchored parts). Only pre-placed,
			-- physics-driven enemies need it.
			if manageNetworkOwnership then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end
	end
end

local function configureExistingEnemy(model: Model)
	if model:GetAttribute("id") == nil then
		model:SetAttribute("id", HttpService:GenerateGUID(false))
	end

	addEnemyTags(model, nil, ENEMY_DEFAULT_COLLISION_GROUP, true)
end

local function isPointWithinPartXZ(part: BasePart, position: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5

	return math.abs(localPosition.X) <= halfSize.X + XZ_BOUNDS_EPSILON
		and math.abs(localPosition.Z) <= halfSize.Z + XZ_BOUNDS_EPSILON
end

local function isPointInZoneBounds(zoneContext: ZoneContext, position: Vector3): boolean
	for _, boundsPart in zoneContext.boundsParts do
		if isPointWithinPartXZ(boundsPart, position) then
			return true
		end
	end

	return false
end

local function getFloorYAtPosition(zoneContext: ZoneContext, position: Vector3): number?
	for _, floorPart in zoneContext.floorParts do
		if isPointWithinPartXZ(floorPart, position) then
			local localPosition = floorPart.CFrame:PointToObjectSpace(position)
			local worldTop = floorPart.CFrame:PointToWorldSpace(Vector3.new(
				localPosition.X,
				floorPart.Size.Y * 0.5,
				localPosition.Z
			))

			return worldTop.Y
		end
	end

	return nil
end

local function clampToFloorBounds(zoneContext: ZoneContext, position: Vector3): Vector3
	local bestPosition = position
	local bestDistanceSq = math.huge

	for _, floorPart in zoneContext.floorParts do
		local localPosition = floorPart.CFrame:PointToObjectSpace(position)
		local halfSize = floorPart.Size * 0.5
		local clamped = floorPart.CFrame:PointToWorldSpace(Vector3.new(
			math.clamp(localPosition.X, -halfSize.X, halfSize.X),
			localPosition.Y,
			math.clamp(localPosition.Z, -halfSize.Z, halfSize.Z)
		))

		local dx = clamped.X - position.X
		local dz = clamped.Z - position.Z
		local distanceSq = dx * dx + dz * dz
		if distanceSq < bestDistanceSq then
			bestDistanceSq = distanceSq
			bestPosition = clamped
		end
	end

	return bestPosition
end

local function getFlatLookAtCFrame(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude <= 0.001 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, flatTarget)
end

-- Vertical distance from a rig's root down to the lowest point of its geometry --
-- i.e. how high the root must sit for the feet to touch the floor -- plus the
-- ground clearance. Measured from the *visual* model (the client rig follows the
-- agent root 1:1, so the visible geometry is what would clip into the ground) and
-- cached per variant, since the source models don't change at runtime.
local spawnRootHeightCache: { [string]: number } = {}

local function getSpawnRootHeight(definition: EnemyDefinition): number
	local cached = spawnRootHeightCache[definition.id]
	if cached then
		return cached
	end

	local model = definition.model
	local rootPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local rootHeight = SPAWN_ROOT_HEIGHT_FALLBACK

	if rootPart and rootPart:IsA("BasePart") then
		local lowestY = math.huge
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local cframe = part.CFrame
				local half = part.Size * 0.5
				-- world-Y half-extent of this (possibly rotated) part's box
				local yExtent = math.abs(cframe.RightVector.Y) * half.X
					+ math.abs(cframe.UpVector.Y) * half.Y
					+ math.abs(cframe.LookVector.Y) * half.Z
				lowestY = math.min(lowestY, part.Position.Y - yExtent)
			end
		end

		if lowestY ~= math.huge then
			rootHeight = (rootPart.Position.Y - lowestY) + SPAWN_GROUND_CLEARANCE
		end
	end

	spawnRootHeightCache[definition.id] = rootHeight
	return rootHeight
end

-- Syncs the raycast filter to everything tagged FLOOR_TAG. Assigning IncludeInstances
-- flips FilterType to Include itself -- don't set FilterType too, it clears the list.
local function refreshFloorRaycastParams()
	floorRaycastParams.IncludeInstances = CollectionService:GetTagged(FLOOR_TAG)
end

local function configureFloorRaycast()
	refreshFloorRaycastParams()
	CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(refreshFloorRaycastParams)
	CollectionService:GetInstanceRemovedSignal(FLOOR_TAG):Connect(refreshFloorRaycastParams)
end

-- Casts down to find the floor and returns the root Y that rests this enemy's feet
-- on it. Falls back to fallbackY when no tagged floor is beneath the agent.
local function resolveFloorRootY(definition: EnemyDefinition, x: number, z: number, fallbackY: number): number
	local origin = Vector3.new(x, fallbackY + FLOOR_RAY_ORIGIN_HEIGHT, z)
	local result = Workspace:Raycast(origin, FLOOR_RAY_DIRECTION, floorRaycastParams)
	if result then
		return result.Position.Y + getSpawnRootHeight(definition)
	end

	return fallbackY
end

local function sampleSpawnGroundPosition(zoneContext: ZoneContext): Vector3?
	if #zoneContext.spawnZones == 0 then
		return nil
	end

	for _ = 1, 12 do
		local spawnZone = zoneContext.spawnZones[random:NextInteger(1, #zoneContext.spawnZones)]
		local localX = random:NextNumber(-spawnZone.Size.X * 0.5, spawnZone.Size.X * 0.5)
		local localZ = random:NextNumber(-spawnZone.Size.Z * 0.5, spawnZone.Size.Z * 0.5)
		local sampledXZ = spawnZone.CFrame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		local floorY = getFloorYAtPosition(zoneContext, sampledXZ) or sampledXZ.Y
		local groundPosition = Vector3.new(sampledXZ.X, floorY, sampledXZ.Z)

		-- Bounds are an XZ-only test, so we validate the floor-level point; the
		-- per-model root height is added by the caller once the variant is known.
		if isPointInZoneBounds(zoneContext, groundPosition) then
			return groundPosition
		end
	end

	return nil
end

-- Native zone-membership test: query the detector's volume with OverlapParams,
-- filtered to just this player's root part. GetPartsInPart respects the detector's
-- actual shape, so this returns true iff the root overlaps the zone. Replaces the
-- ZonePlus detectorZone:findPlayer call.
local function isPlayerInZone(zoneContext: ZoneContext, player: Player): boolean
	local rootPart = getCharacterRootPart(player.Character)
	if not rootPart then
		return false
	end

	detectorOverlapParams.FilterDescendantsInstances = { rootPart }
	return #Workspace:GetPartsInPart(zoneContext.detector, detectorOverlapParams) > 0
end

local function canPlayerAccessZone(player: Player, zoneContext: ZoneContext): boolean
	if player:GetAttribute("Loaded") ~= true then
		return false
	end

	local zoneService = EnemyService.Services.ZoneService
	if not zoneService then
		return false
	end

	return zoneService:CanPlayerAccessZone(player, zoneContext.definition.order)
end

local function setPlayerZone(player: Player, zoneContext: ZoneContext?)
	if zoneContext and not canPlayerAccessZone(player, zoneContext) then
		zoneContext = nil
	end

	if EnemyService.ActiveZoneByPlayer[player] == zoneContext then
		return
	end

	EnemyService.ActiveZoneByPlayer[player] = zoneContext
	EnemyService.LastSpawnAtByPlayer[player] = nil
end

local function refreshPlayerZone(player: Player)
	for _, zoneContext in EnemyService.ZoneContexts do
		if isPlayerInZone(zoneContext, player) and canPlayerAccessZone(player, zoneContext) then
			setPlayerZone(player, zoneContext)
			return
		end
	end

	setPlayerZone(player, nil)
end

local function removeEnemyRecord(record: EnemyRecord)
	if record.removed then
		return
	end

	record.removed = true

	local activeEnemies = EnemyService.ActiveEnemiesByPlayer[record.owner]
	if not activeEnemies then
		return
	end

	for index = #activeEnemies, 1, -1 do
		if activeEnemies[index] == record then
			table.remove(activeEnemies, index)
			break
		end
	end
end

local function destroyEnemyRecord(record: EnemyRecord)
	removeEnemyRecord(record)

	if record.model.Parent then
		record.model:Destroy()
	end
end

local function getEnemySourcePosition(record: EnemyRecord): Vector3
	local sourcePosition = record.model:GetPivot().Position
	local rootPart = getModelRootPart(record.model)
	if rootPart then
		sourcePosition = rootPart.Position
	end

	return sourcePosition
end

local function clearPlayerEnemies(player: Player)
	local activeEnemies = EnemyService.ActiveEnemiesByPlayer[player]
	if not activeEnemies then
		return
	end

	for index = #activeEnemies, 1, -1 do
		destroyEnemyRecord(activeEnemies[index])
	end

	EnemyService.ActiveEnemiesByPlayer[player] = nil
end

local function countActiveEnemies(player: Player): number
	local activeEnemies = EnemyService.ActiveEnemiesByPlayer[player]
	if not activeEnemies then
		return 0
	end

	for index = #activeEnemies, 1, -1 do
		local record = activeEnemies[index]
		if record.removed or not record.model.Parent or record.humanoid.Health <= 0 then
			table.remove(activeEnemies, index)
		end
	end

	return #activeEnemies
end

local function appendDistributedDropSpecs(
	specs: { DropSpec },
	dropName: string,
	totalAmount: number,
	count: number,
	color: Color3?
)
	if totalAmount <= 0 or count <= 0 then
		return
	end

	local baseAmount = totalAmount // count
	local remainder = totalAmount % count

	for index = 1, count do
		local amount = baseAmount
		if index <= remainder then
			amount += 1
		end

		table.insert(specs, {
			dropName = dropName,
			amount = amount,
			color = color,
		})
	end
end

local function getMoneyDropSpecs(amount: number): { DropSpec }
	amount = roundNonNegative(amount)

	local specs = {}
	if amount <= 0 then
		return specs
	end

	local thousandsAmount = (amount // 1000) * 1000
	local purples = math.min(10, amount // 1000)
	appendDistributedDropSpecs(specs, "Money", thousandsAmount, purples, MONEY_PURPLE_COLOR)

	local blues = (amount % 1000) // 100
	appendDistributedDropSpecs(specs, "Money", blues * 100, blues, MONEY_BLUE_COLOR)

	local greenAmount = amount % 100
	local greens = greenAmount // 10
	if greens > 0 then
		appendDistributedDropSpecs(specs, "Money", greenAmount, greens, MONEY_GREEN_COLOR)
	elseif greenAmount > 0 then
		table.insert(specs, {
			dropName = "Money",
			amount = greenAmount,
			color = MONEY_GREEN_COLOR,
		})
	end

	return specs
end

local function getDogtagDropSpecs(amount: number): { DropSpec }
	amount = roundNonNegative(amount)

	local specs = {}
	if amount <= 0 then
		return specs
	end

	appendDistributedDropSpecs(specs, "Dogtags", amount, math.min(DOGTAG_MAX_DROPS, amount), nil)

	return specs
end

local function getItemDropSpecs(player: Player, enemyDefinition: EnemyDefinition): { DropSpec }
	local specs = {}
	local upgradeService = EnemyService.Services.UpgradeService

	for _, itemName in enemyDefinition.itemDropNames do
		local itemDef: ItemDefinition = ItemDefinitions[itemName]

		local dropChance = upgradeService:GetItemDropChance(player, itemName)
		if not dropChance or dropChance <= 0 then
			continue
		end

		if random:NextNumber() >= dropChance then
			continue
		end

		local dropStack = itemDef.dropStack
		local amount = if dropStack then random:NextInteger(dropStack.min, dropStack.max) else 1

		table.insert(specs, {
			dropName = itemName,
			amount = amount,
			pickupWeight = if typeof(itemDef.dropWeight) == "number"
				then math.max(0.01, itemDef.dropWeight)
				else DEFAULT_ITEM_DROP_WEIGHT,
			requiresMagnetRange = true,
		})
	end

	return specs
end

local function sampleDropRestPosition(sourcePosition: Vector3): Vector3
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = DROP_RADIUS * math.sqrt(random:NextNumber())
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

	return Vector3.new(sourcePosition.X + offset.X, FLOOR_Y, sourcePosition.Z + offset.Z)
end

local function removeExpiredDrop(dropId: string, expiresAt: number)
	task.delay(math.max(0, expiresAt - Workspace:GetServerTimeNow()) + 1, function()
		local dropRecord = EnemyService.PendingDrops[dropId]
		if dropRecord and not dropRecord.claimed and dropRecord.expiresAt <= Workspace:GetServerTimeNow() then
			EnemyService.PendingDrops[dropId] = nil
		end
	end)
end

local function clearPlayerDrops(player: Player)
	for dropId, dropRecord in EnemyService.PendingDrops do
		if dropRecord.owner == player then
			EnemyService.PendingDrops[dropId] = nil
		end
	end

	EnemyService.CollectAttemptsByPlayer[player] = nil
end

local function getPlayerMagnetRange(player: Player): number
	local upgradeService = EnemyService.Services.UpgradeService
	if not upgradeService then
		return 0
	end

	return math.max(0, upgradeService:GetMagnetRange(player))
end

local function getDropSettings(dropName: string): (number, boolean)
	local settings = DROP_SETTINGS[dropName]
	if not settings then
		return DEFAULT_DROP_PICKUP_WEIGHT, DEFAULT_REQUIRES_MAGNET_RANGE
	end

	return math.max(0.01, settings.pickupWeight), settings.requiresMagnetRange
end

local function addProfileItem(player: Player, itemName: string, quantity: number)
	quantity = roundNonNegative(quantity)
	if quantity <= 0 or player.Parent ~= Players then
		return
	end

	local inventoryService = EnemyService.Services.InventoryService
	if not inventoryService then
		return
	end

	inventoryService:AddItem(player, itemName, quantity)
end

local function createDrops(player: Player, sourcePosition: Vector3, specs: { DropSpec })
	if #specs == 0 or player.Parent ~= Players then
		return
	end

	local now = Workspace:GetServerTimeNow()
	local expiresAt = now + DROP_EXPIRY_SECONDS
	local groupId = HttpService:GenerateGUID(false)
	local payloads = {} :: { DropPayload }

	for index, spec in specs do
		local dropKind = getDropKind(spec.dropName)
		if not dropKind then
			warn(`[EnemyService] Unknown drop name "{spec.dropName}" will not be created.`)
			continue
		end

		local createdAt = now + (index - 1) * DROP_STAGGER_SECONDS
		local arcDuration = random:NextNumber(MIN_ARC_DURATION, MAX_ARC_DURATION)
		local landAt = createdAt + arcDuration
		local dropId = HttpService:GenerateGUID(false)
		local restPosition = sampleDropRestPosition(sourcePosition)
		local defaultPickupWeight, defaultRequiresMagnetRange = getDropSettings(spec.dropName)
		local pickupWeight = math.max(0.01, spec.pickupWeight or defaultPickupWeight)
		local requiresMagnetRange = if spec.requiresMagnetRange ~= nil
			then spec.requiresMagnetRange
			else defaultRequiresMagnetRange
		local requiresServerCollect = dropKind ~= "Currency"

		if requiresServerCollect then
			local dropRecord: DropRecord = {
				id = dropId,
				owner = player,
				dropName = spec.dropName,
				amount = spec.amount,
				pickupWeight = pickupWeight,
				requiresMagnetRange = requiresMagnetRange,
				sourcePosition = sourcePosition,
				restPosition = restPosition,
				createdAt = createdAt,
				landAt = landAt,
				expiresAt = expiresAt,
				claimed = false,
			}

			EnemyService.PendingDrops[dropId] = dropRecord
			removeExpiredDrop(dropId, expiresAt)
		end

		table.insert(payloads, {
			id = dropId,
			groupId = groupId,
			dropName = spec.dropName,
			amount = spec.amount,
			pickupWeight = pickupWeight,
			requiresMagnetRange = requiresMagnetRange,
			requiresServerCollect = requiresServerCollect,
			sourcePosition = sourcePosition,
			restPosition = restPosition,
			createdAt = createdAt,
			landAt = landAt,
			expiresAt = expiresAt,
			color = spec.color,
		})
	end

	if #payloads > 0 then
		spawnCurrencyDropsRemote:FireClient(player, payloads)
	end
end

local function canProcessCollectAttempt(player: Player, now: number): boolean
	local attemptState = EnemyService.CollectAttemptsByPlayer[player]
	if not attemptState or now - attemptState.windowStartedAt >= 1 then
		EnemyService.CollectAttemptsByPlayer[player] = {
			windowStartedAt = now,
			count = 1,
		}
		return true
	end

	attemptState.count += 1

	return attemptState.count <= MAX_COLLECT_ATTEMPTS_PER_SECOND
end

local function onCollectCurrencyDrop(player: Player, dropId: any)
	local now = Workspace:GetServerTimeNow()
	if not canProcessCollectAttempt(player, now) or typeof(dropId) ~= "string" then
		return
	end

	local dropRecord = EnemyService.PendingDrops[dropId]
	if not dropRecord or dropRecord.claimed or dropRecord.owner ~= player or player.Parent ~= Players then
		return
	end

	if now > dropRecord.expiresAt then
		EnemyService.PendingDrops[dropId] = nil
		return
	end

	if now < dropRecord.landAt then
		return
	end

	local playerRootPart = getPlayerRootPart(player)
	if not playerRootPart then
		return
	end

	if dropRecord.requiresMagnetRange then
		local maxPickupDistance = getPlayerMagnetRange(player) + SERVER_PICKUP_GRACE_DISTANCE
		if (playerRootPart.Position - dropRecord.restPosition).Magnitude > maxPickupDistance then
			return
		end
	end

	local dropKind = getDropKind(dropRecord.dropName)
	if not dropKind then
		warn(`[EnemyService] Unknown collected drop name "{dropRecord.dropName}" will not be granted.`)
		EnemyService.PendingDrops[dropId] = nil
		return
	end

	dropRecord.claimed = true
	EnemyService.PendingDrops[dropId] = nil
	if dropKind == "Item" then
		addProfileItem(player, dropRecord.dropName, dropRecord.amount)
	end
end

local function configureCurrencyDropRemotes()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local currencyRemotesFolder = remotesFolder:WaitForChild("Currency")
	assert(currencyRemotesFolder:IsA("Folder"), "ReplicatedStorage.Remotes.Currency must be a Folder")

	spawnCurrencyDropsRemote = getRemoteEvent(currencyRemotesFolder, "SpawnCurrencyDrops")
	collectCurrencyDropRemote = getRemoteEvent(currencyRemotesFolder, "CollectCurrencyDrop")
	collectCurrencyDropRemote.OnServerEvent:Connect(onCollectCurrencyDrop)
end

local function awardEnemy(record: EnemyRecord)
	if record.rewarded then
		return
	end

	record.rewarded = true

	local sourcePosition = getEnemySourcePosition(record)
	local upgradeService = EnemyService.Services.UpgradeService
	local cashReward = roundNonNegative(record.cashReward * upgradeService:GetMoneyMultiplier(record.owner))
	local tagReward = roundNonNegative(record.tagReward * upgradeService:GetDogtagsMultiplier(record.owner))
	local dataService = EnemyService.Services.DataService

	if dataService then
		if cashReward > 0 then
			dataService:IncrementCurrency(record.owner, "Money", cashReward, "enemy", true, true)
		end
		if tagReward > 0 then
			dataService:IncrementCurrency(record.owner, "Dogtags", tagReward, "enemy", true, true)
		end
	end

	-- Per-kill telemetry is suppressed above; feed the aggregator instead.
	-- Zone is captured here, at kill time, so income is attributed to where it was earned.
	local customAnalytics = EnemyService.Services.CustomAnalyticsService
	if customAnalytics then
		customAnalytics:RecordEnemyKill(
			record.owner,
			record.zoneContext.definition.order,
			record.definition.id,
			cashReward,
			tagReward
		)
	end

	local specs = getMoneyDropSpecs(cashReward)
	for _, dogtagSpec in getDogtagDropSpecs(tagReward) do
		table.insert(specs, dogtagSpec)
	end
	for _, itemSpec in getItemDropSpecs(record.owner, record.definition) do
		table.insert(specs, itemSpec)
	end

	createDrops(record.owner, sourcePosition, specs)
end

local function getPlayerEnemyCap(player: Player): number
	local upgradeService = EnemyService.Services.UpgradeService
	return math.max(0, math.floor(upgradeService:GetEnemyCap(player)))
end

local function getPlayerSpawnInterval(player: Player): number
	local upgradeService = EnemyService.Services.UpgradeService
	local spawnSpeed = math.max(0, upgradeService:GetEnemySpawnSpeed(player))
	return math.max(MIN_SPAWN_INTERVAL, DEFAULT_SPAWN_INTERVAL - spawnSpeed)
end

local function getVariantChance(variantName: string, upgradeChance: number): number
	local definition = EnemyDefinitions[variantName]
	local baseChance = if definition then definition.baseSpawnChance or 0 else 0
	return math.clamp(baseChance + upgradeChance, 0, 1)
end

local function rollEnemyDefinition(player: Player): EnemyDefinition
	local upgradeService = EnemyService.Services.UpgradeService

	if random:NextNumber() < getVariantChance("Inverted", upgradeService:GetSpecialEnemyChance(player, "invertedEnemyChance")) then
		return EnemyDefinitions.Inverted
	end

	if random:NextNumber() < getVariantChance("Shiny", upgradeService:GetSpecialEnemyChance(player, "shinyEnemyChance")) then
		return EnemyDefinitions.Shiny
	end

	if random:NextNumber() < getVariantChance("Big", upgradeService:GetSpecialEnemyChance(player, "bigEnemyChance")) then
		return EnemyDefinitions.Big
	end

	return EnemyDefinitions.Normal
end

local function getRewardAttributes(definition: EnemyDefinition, zoneDefinition: ZoneDefinition): (number, number, number)
	local health = math.max(1, roundNonNegative(definition.health * zoneDefinition.enemyHealthMultiplier))
	local cashReward = roundNonNegative(definition.cashReward * zoneDefinition.enemyCashRewardMultiplier)
	local tagReward = roundNonNegative(definition.tagReward * zoneDefinition.enemyTagRewardMultiplier)

	return health, cashReward, tagReward
end

local function steerAllEnemies(dt: number)
	for owner, records in EnemyService.ActiveEnemiesByPlayer do
		if #records == 0 then
			continue
		end

		local targetRootPart = getPlayerRootPart(owner)
		local targetPosition = if targetRootPart then targetRootPart.Position else nil
		-- Pass 1: cull strays and build this owner's separation hash. player only sees their own enemies. 
		-- separation is scoped per owner. effective neighbour count is the player's enemy cap. 
		steeringHash:clear()
		local liveRecords: { EnemyRecord } = {}
		local livePositions: { Vector3 } = {}
		-- iterate a copy because destroyEnemyRecord mutates `records` mid-loop.
		for _, record in table.clone(records) do
			if record.removed or not record.model.Parent or record.humanoid.Health <= 0 then
				continue
			end

			local position = record.rootPart.Position
			if not isPointInZoneBounds(record.zoneContext, position) then
				destroyEnemyRecord(record)
				continue
			end

			if targetPosition then
				if not isPointInZoneBounds(record.zoneContext, targetPosition) then
					destroyEnemyRecord(record)
					continue
				end
				if (targetPosition - position).Magnitude > ENEMY_DESPAWN_DISTANCE then
					destroyEnemyRecord(record)
					continue
				end
			end

			table.insert(liveRecords, record)
			table.insert(livePositions, position)
			steeringHash:insert(record, position)
		end

		-- Pass 2: steer survivors and move them kinematically. Steering is XZ-only; a
		-- downward raycast re-pins Y to the floor beneath each agent's next step.
		for index, record in liveRecords do
			local position = livePositions[index]
			local desiredVelocity = EnemySteering.computeDesiredVelocity(
				record,
				position,
				targetPosition,
				record.definition.walkSpeed,
				steeringHash,
				steeringConfig,
				random
			)

			local steppedPosition = clampToFloorBounds(
				record.zoneContext,
				Vector3.new(position.X + desiredVelocity.X * dt, position.Y, position.Z + desiredVelocity.Z * dt)
			)
			local nextX = steppedPosition.X
			local nextZ = steppedPosition.Z
			local nextPosition = Vector3.new(
				nextX,
				resolveFloorRootY(record.definition, nextX, nextZ, position.Y),
				nextZ
			)

			local nextCFrame = if targetPosition
				then getFlatLookAtCFrame(nextPosition, targetPosition)
				else record.rootPart.CFrame.Rotation + nextPosition

			record.model:PivotTo(nextCFrame)
		end
	end
end

local function spawnEnemy(player: Player, zoneContext: ZoneContext): EnemyRecord?
	local playerRootPart = getPlayerRootPart(player)
	if not playerRootPart then
		return nil
	end

	local collisionGroupName = EnemyService.EnemyCollisionGroupByPlayer[player]
	if not collisionGroupName then
		for _, groupName in EnemyService.EnemyCollisionGroupNames do
			if EnemyService.EnemyCollisionGroupOwnerByName[groupName] == nil then
				EnemyService.EnemyCollisionGroupOwnerByName[groupName] = player
				EnemyService.EnemyCollisionGroupByPlayer[player] = groupName
				collisionGroupName = groupName
				break
			end
		end
	end

	if not collisionGroupName then
		warn(`[EnemyService] No enemy collision group is available for {player.Name}`)
		return nil
	end

	local groundPosition = sampleSpawnGroundPosition(zoneContext)
	if not groundPosition then
		warn(`[EnemyService] Zone "{zoneContext.id}" has no valid SpawnZone position`)
		return nil
	end

	local definition = rollEnemyDefinition(player)
	local enemyModel = definition.agentModel:Clone()
	local humanoid = getModelHumanoid(enemyModel)
	local rootPart = getModelRootPart(enemyModel)

	if not humanoid or not rootPart then
		warn(`[EnemyService] Enemy model "{definition.label}" must have a Humanoid and root BasePart`)
		enemyModel:Destroy()
		return nil
	end

	local health, cashReward, tagReward = getRewardAttributes(definition, zoneContext.definition)

	enemyModel.Name = definition.label
	enemyModel:SetAttribute("id", HttpService:GenerateGUID(false))
	enemyModel:SetAttribute("enemyType", definition.id)
	enemyModel:SetAttribute("ownerUserId", player.UserId)
	enemyModel:SetAttribute("ownerName", player.Name)
	enemyModel:SetAttribute("zoneId", zoneContext.id)
	enemyModel:SetAttribute("cashReward", cashReward)
	enemyModel:SetAttribute("tagReward", tagReward)
	enemyModel:SetAttribute("deathAudioId", definition.deathAudioId)

	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = definition.walkSpeed

	addEnemyTags(enemyModel, player, collisionGroupName, false)

	-- The agent rig is authored fully anchored, so the physics solver never
	-- simulates it; the steering tick moves it via PivotTo. BreakJointsOnDeath is
	-- belt-and-suspenders (anchored parts can't ragdoll anyway). The Highlight and
	-- HealthBillboardGui now live on the owner's client-side visual rig, not here.
	rootPart.Anchored = true
	humanoid.BreakJointsOnDeath = false

	-- Lift the root so the model's feet rest on the floor; taller models need a
	-- larger lift. The steering tick then preserves this Y for the enemy's life.
	local spawnPosition = groundPosition + Vector3.new(0, getSpawnRootHeight(definition), 0)
	enemyModel:PivotTo(getFlatLookAtCFrame(spawnPosition, playerRootPart.Position))
	enemyModel.Parent = enemiesFolder

	local record: EnemyRecord = {
		model = enemyModel,
		humanoid = humanoid,
		rootPart = rootPart,
		owner = player,
		zoneContext = zoneContext,
		definition = definition,
		cashReward = cashReward,
		tagReward = tagReward,
		removed = false,
		rewarded = false,
	}

	EnemyService.ActiveEnemiesByPlayer[player] = EnemyService.ActiveEnemiesByPlayer[player] or {}
	table.insert(EnemyService.ActiveEnemiesByPlayer[player], record)

	humanoid.Died:Connect(function()
		awardEnemy(record)
		removeEnemyRecord(record)

		-- prevent bullets from getting blocked by a dead server agent
		for _, descendant in enemyModel:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = false
			end
		end

		task.delay(DEAD_ENEMY_CLEANUP_DELAY, function()
			if enemyModel.Parent then
				enemyModel:Destroy()
			end
		end)
	end)

	enemyModel.Destroying:Connect(function()
		removeEnemyRecord(record)
	end)

	return record
end

local function trySpawnForPlayer(player: Player)
	if player:GetAttribute("Loaded") ~= true then
		return
	end

	local zoneContext = EnemyService.ActiveZoneByPlayer[player]
	if not zoneContext then
		return
	end

	if not canPlayerAccessZone(player, zoneContext) then
		setPlayerZone(player, nil)
		return
	end

	local enemyCap = getPlayerEnemyCap(player)
	if countActiveEnemies(player) >= enemyCap then
		return
	end

	local spawnInterval = getPlayerSpawnInterval(player)
	local now = os.clock()
	local lastSpawnAt = EnemyService.LastSpawnAtByPlayer[player]
	local spawnBudget = 1

	if lastSpawnAt then
		spawnBudget = math.floor((now - lastSpawnAt) / spawnInterval)
	else
		lastSpawnAt = now - spawnInterval
	end

	if spawnBudget <= 0 then
		return
	end

	local spawned = 0
	spawnBudget = math.min(spawnBudget, MAX_SPAWNS_PER_TICK)

	for _ = 1, spawnBudget do
		if countActiveEnemies(player) >= enemyCap then
			break
		end

		local record = spawnEnemy(player, zoneContext)
		if not record then
			break
		end

		spawned += 1
		lastSpawnAt += spawnInterval
	end

	EnemyService.LastSpawnAtByPlayer[player] = if spawned > 0 then lastSpawnAt else now
end

local function buildZoneBoundsParts(detector: BasePart, spawnZones: { BasePart }): { BasePart }
	local boundsParts = { detector }
	for _, spawnZone in spawnZones do
		table.insert(boundsParts, spawnZone)
	end

	return boundsParts
end

local function registerZoneModel(zoneModel: Instance)
	-- Zones are authored as Folders (a few legacy ones may be Models); both are just
	-- named containers for LogicParts, so accept either and skip any stray instances.
	if not zoneModel:IsA("Model") and not zoneModel:IsA("Folder") then
		return
	end

	if EnemyService.ZoneContexts[zoneModel.Name] then
		return
	end

	local zoneDefinition = ZoneDefinitions[zoneModel.Name]
	if not zoneDefinition then
		warn(`[EnemyService] Missing ZoneDefinitions entry for Workspace.Zones.{zoneModel.Name}`)
		return
	end

	local logicParts = getLogicParts(zoneModel)
	if not logicParts then
		return
	end

	local detector = logicParts:FindFirstChild("Detector")
	if not detector or not detector:IsA("BasePart") then
		warn(`[EnemyService] Workspace.Zones.{zoneModel.Name}.{LOGIC_PARTS_FOLDER_NAME} needs a BasePart named Detector`)
		return
	end

	local spawnZones = getBasePartsNamed(logicParts, "SpawnZone")
	if #spawnZones == 0 then
		warn(`[EnemyService] Workspace.Zones.{zoneModel.Name}.{LOGIC_PARTS_FOLDER_NAME} has no BasePart named SpawnZone`)
	end

	local floorParts = getBasePartsNamed(logicParts, "Floor")
	local zoneContext: ZoneContext = {
		id = zoneModel.Name,
		model = zoneModel,
		logicParts = logicParts,
		definition = zoneDefinition,
		detector = detector,
		spawnZones = spawnZones,
		floorParts = floorParts,
		boundsParts = buildZoneBoundsParts(detector, spawnZones),
	}

	EnemyService.ZoneContexts[zoneContext.id] = zoneContext

	-- Enter/exit is driven by zoneDetectionLoop polling isPlayerInZone; refresh now
	-- so a freshly registered zone claims any players already standing in it.
	for _, player in Players:GetPlayers() do
		refreshPlayerZone(player)
	end
end

local function unregisterZoneModel(zoneModel: Instance)
	local zoneContext = EnemyService.ZoneContexts[zoneModel.Name]
	if not zoneContext then
		return
	end

	EnemyService.ZoneContexts[zoneModel.Name] = nil

	for player, activeZoneContext in EnemyService.ActiveZoneByPlayer do
		if activeZoneContext == zoneContext then
			setPlayerZone(player, nil)
		end
	end
end

local function registerZones()
	local zonesFolder = Workspace:WaitForChild("Zones", ZONES_WAIT_TIMEOUT)
	if not zonesFolder then
		warn(`[EnemyService] Workspace.Zones was not found within {ZONES_WAIT_TIMEOUT} seconds`)
		return
	end

	for _, zoneModel in zonesFolder:GetChildren() do
		registerZoneModel(zoneModel)
	end

	zonesFolder.ChildAdded:Connect(registerZoneModel)
	zonesFolder.ChildRemoved:Connect(unregisterZoneModel)
end

local function trackPlayer(player: Player)
	if EnemyService.PlayerConnections[player] then
		return
	end

	EnemyService.PlayerConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		task.defer(function()
			character:WaitForChild("HumanoidRootPart", 5)
			refreshPlayerZone(player)
		end)
	end)

	task.defer(function()
		refreshPlayerZone(player)
	end)
end

local function untrackPlayer(player: Player)
	local connection = EnemyService.PlayerConnections[player]
	if connection then
		connection:Disconnect()
		EnemyService.PlayerConnections[player] = nil
	end

	setPlayerZone(player, nil)
	EnemyService.LastSpawnAtByPlayer[player] = nil
	clearPlayerEnemies(player)
	local collisionGroupName = EnemyService.EnemyCollisionGroupByPlayer[player]
	if collisionGroupName then
		EnemyService.EnemyCollisionGroupByPlayer[player] = nil
		EnemyService.EnemyCollisionGroupOwnerByName[collisionGroupName] = nil
	end
	clearPlayerDrops(player)
end

local function spawnLoop()
	while true do
		task.wait(SPAWN_ATTEMPT_INTERVAL)

		for _, player in Players:GetPlayers() do
			trySpawnForPlayer(player)
		end
	end
end

local function zoneDetectionLoop()
	while true do
		task.wait(ZONE_DETECTION_INTERVAL)

		for _, player in Players:GetPlayers() do
			refreshPlayerZone(player)
		end
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function EnemyService:RefreshPlayerZone(player: Player)
	refreshPlayerZone(player)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function EnemyService:Init(services)
	self.Services = services
	enemiesFolder = getOrCreateFolder(Workspace, ENEMIES_FOLDER_NAME)
	configureEnemyCollisionGroups()
	warnItemCurrencyNameCollisions()
	configureCurrencyDropRemotes()
	configureFloorRaycast()

	local enemies = CollectionService:GetTagged("Enemy") :: {Model}
	for _, enemyModel in pairs(enemies) do
		if enemyModel:IsA("Model") then
			configureExistingEnemy(enemyModel)
		end
	end

	print("[EnemyService] initiated")
end

function EnemyService:Start()
	registerZones()

	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)

	-- A player standing in a zone before they finish loading is rejected by
	-- canPlayerAccessZone (the Loaded check), so re-run detection once data lands.
	self.Services.DataService.Signals.DataLoaded:Connect(function(player: Player)
		task.defer(refreshPlayerZone, player)
	end)

	task.spawn(spawnLoop)
	task.spawn(zoneDetectionLoop)

	task.spawn(function()
		while true do
			local dt = task.wait(STEER_INTERVAL)
			steerAllEnemies(math.min(dt, MAX_STEER_DT))
		end
	end)
end


return EnemyService
