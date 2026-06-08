local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local ZoneDefinitions = require(ReplicatedStorage.GameAssets.ZoneAssets.ZoneDefinitions)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type ZoneDefinition = ZoneDefinitions.ZoneDefinition

type ZoneContext = {
	logicParts: Folder,
	wallFolder: Folder?,
	definition: ZoneDefinition,
	order: number,
	unlockWall: Model?,
}

type UnlockZoneResult = {
	success: boolean,
	message: string?,
	currentZone: number?,
	money: number?,
	unlocked: boolean?,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local ZoneService = {}
ZoneService.Services = {}
ZoneService.Signals = {}
ZoneService.ZoneContexts = {} :: { [string]: ZoneContext }
ZoneService.ZoneContextsByOrder = {} :: { [number]: ZoneContext }
ZoneService.ZoneConnections = {} :: { [Instance]: { RBXScriptConnection } }

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local DEFAULT_ZONE_ORDER = 1
local LOGIC_PARTS_FOLDER_NAME = "LogicParts"
local WALL_FOLDER_NAME = "Wall"
local UNLOCK_WALL_MODEL_NAME = "UnlockWall"
local SCREEN_PART_NAME = "Screen"
local FLOOR_PART_NAME = "Floor"
local MAX_UNLOCK_DISTANCE_FROM_PART = 60
local PLAYER_IGNORE_TAG_PREFIX = "Ignore-"
local HIDDEN_ZONE_PART_NAMES = {
	Detector = true,
	SpawnZone = true,
}

local zoneRemotes = remotesFolder:WaitForChild("Zones")
local remotes = {
	UnlockZone = zoneRemotes:WaitForChild("UnlockZone") :: RemoteFunction,
}

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function normalizeZoneOrder(value: any): number?
	if typeof(value) ~= "number" then
		return nil
	end

	local zoneOrder = math.floor(value)
	if zoneOrder ~= value or zoneOrder < DEFAULT_ZONE_ORDER then
		return nil
	end

	return zoneOrder
end

local function syncPlayerAttributes(player: Player, profile: any)
	player:SetAttribute("CurrentZone", profile.CurrentZone)

	player:SetAttribute("Money", profile.Money)
end

local function getCharacterRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getZoneFloorSpawnCFrame(zoneContext: ZoneContext): CFrame?
	local floorPart = zoneContext.logicParts:FindFirstChild(FLOOR_PART_NAME)
	if not floorPart or not floorPart:IsA("BasePart") then
		return nil
	end

	local targetPosition = floorPart.CFrame:PointToWorldSpace(Vector3.new(0, floorPart.Size.Y / 2 + 5, 0))
	return CFrame.new(targetPosition)
end

local function tagUnlockedZoneScreens(player: Player, currentZone: number)
	local ignoreTag = `{PLAYER_IGNORE_TAG_PREFIX}{player.Name}`
	for zoneOrder = DEFAULT_ZONE_ORDER, currentZone do
		local zoneContext = ZoneService.ZoneContextsByOrder[zoneOrder]
		local unlockWall = if zoneContext then zoneContext.unlockWall else nil
		if unlockWall then
			CollectionService:AddTag(unlockWall:FindFirstChild(SCREEN_PART_NAME) :: BasePart, ignoreTag)
		end
	end
end

local function removePlayerIgnoreTags(player: Player)
	local ignoreTag = `{PLAYER_IGNORE_TAG_PREFIX}{player.Name}`
	for _, instance in CollectionService:GetTagged(ignoreTag) do
		CollectionService:RemoveTag(instance, ignoreTag)
	end
end

local function registerZoneModel(zoneModel: Instance)
	if ZoneService.ZoneContexts[zoneModel.Name] then
		return
	end

	local zoneDefinition = ZoneDefinitions[zoneModel.Name]
	if not zoneDefinition then
		warn(`[ZoneService] Missing ZoneDefinitions entry for Workspace.Zones.{zoneModel.Name}`)
		return
	end

	local zoneOrder = zoneDefinition.order :: number

	if ZoneService.ZoneContextsByOrder[zoneOrder] then
		warn(`[ZoneService] Duplicate zone order {zoneOrder} for Workspace.Zones.{zoneModel.Name}`)
		return
	end

	local logicParts = zoneModel:WaitForChild(LOGIC_PARTS_FOLDER_NAME) :: Folder

	for _, descendant in logicParts:GetDescendants() do
		if HIDDEN_ZONE_PART_NAMES[descendant.Name] then
			local part = descendant :: BasePart
			part.Transparency = 1
			part.CastShadow = false
			part.CanCollide = false
		end
	end

	local wallFolder = logicParts:FindFirstChild(WALL_FOLDER_NAME) :: Folder?
	local unlockWall = if wallFolder then wallFolder:FindFirstChild(UNLOCK_WALL_MODEL_NAME) :: Model? else nil
	local zoneContext: ZoneContext = {
		logicParts = logicParts,
		wallFolder = wallFolder,
		definition = zoneDefinition,
		order = zoneOrder,
		unlockWall = unlockWall,
	}

	ZoneService.ZoneContexts[zoneModel.Name] = zoneContext
	ZoneService.ZoneContextsByOrder[zoneOrder] = zoneContext

	ZoneService.ZoneConnections[zoneModel] = {
		logicParts.DescendantAdded:Connect(function(descendant: Instance)
			if HIDDEN_ZONE_PART_NAMES[descendant.Name] then
				local part = descendant :: BasePart
				part.Transparency = 1
				part.CastShadow = false
				part.CanCollide = false
			end
		end),

		logicParts.ChildAdded:Connect(function(child: Instance)
			if child.Name == WALL_FOLDER_NAME then
				local addedWallFolder = child :: Folder
				zoneContext.wallFolder = addedWallFolder
				zoneContext.unlockWall = addedWallFolder:FindFirstChild(UNLOCK_WALL_MODEL_NAME) :: Model?

				table.insert(ZoneService.ZoneConnections[zoneModel], addedWallFolder.ChildAdded:Connect(function(wallChild: Instance)
					if wallChild.Name == UNLOCK_WALL_MODEL_NAME then
						zoneContext.unlockWall = wallChild :: Model
					end
				end))

				table.insert(ZoneService.ZoneConnections[zoneModel], addedWallFolder.ChildRemoved:Connect(function(wallChild: Instance)
					if wallChild == zoneContext.unlockWall then
						zoneContext.unlockWall = nil
					end
				end))
			end
		end),

		logicParts.ChildRemoved:Connect(function(child: Instance)
			if child == zoneContext.wallFolder then
				zoneContext.wallFolder = nil
				zoneContext.unlockWall = nil
			end
		end),
	}

	if wallFolder then
		table.insert(ZoneService.ZoneConnections[zoneModel], wallFolder.ChildAdded:Connect(function(child: Instance)
			if child.Name == UNLOCK_WALL_MODEL_NAME then
				zoneContext.unlockWall = child :: Model
			end
		end))

		table.insert(ZoneService.ZoneConnections[zoneModel], wallFolder.ChildRemoved:Connect(function(child: Instance)
			if child == zoneContext.unlockWall then
				zoneContext.unlockWall = nil
			end
		end))
	end
end

local function unregisterZoneModel(zoneModel: Instance)
	local zoneContext = ZoneService.ZoneContexts[zoneModel.Name]
	if not zoneContext then
		return
	end

	local connections = ZoneService.ZoneConnections[zoneModel]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	ZoneService.ZoneConnections[zoneModel] = nil
	ZoneService.ZoneContexts[zoneModel.Name] = nil
	ZoneService.ZoneContextsByOrder[zoneContext.order] = nil
end

local function onPlayerDataLoaded(player: Player)
	local profile = ZoneService:GetProfile(player)
	if not profile then
		return
	end

	local currentZone = profile.CurrentZone
	syncPlayerAttributes(player, profile)
	tagUnlockedZoneScreens(player, currentZone)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ZoneService:GetProfile(player: Player): any?
	return self.Services.DataService:GetProfile(player)
end

function ZoneService:GetCurrentZone(player: Player): number?
	local profile = self:GetProfile(player)
	if not profile then
		return nil
	end

	return profile.CurrentZone
end

function ZoneService:GetZoneSpawnCFrame(zoneOrder: number): CFrame?
	local zoneContext = self.ZoneContextsByOrder[zoneOrder]
	if not zoneContext then
		return nil
	end

	return getZoneFloorSpawnCFrame(zoneContext)
end

function ZoneService:CanPlayerAccessZone(player: Player, zoneOrder: any): boolean
	local normalizedZoneOrder = normalizeZoneOrder(zoneOrder)
	if not normalizedZoneOrder then
		return false
	end

	local currentZone = self:GetCurrentZone(player)
	return currentZone ~= nil and normalizedZoneOrder <= currentZone
end

function ZoneService:UnlockZone(player: Player, zone: any): UnlockZoneResult
	local requestedZoneOrder = normalizeZoneOrder(zone)
	if not requestedZoneOrder then
		return {
			success = false,
			message = "Invalid zone",
		}
	end

	local zoneContext = self.ZoneContextsByOrder[requestedZoneOrder]
	if not zoneContext then
		return {
			success = false,
			message = "Unknown zone",
		}
	end

	local profile = self:GetProfile(player)
	if not profile then
		return {
			success = false,
			message = "Profile is not loaded",
		}
	end

	local currentZone = profile.CurrentZone
	if requestedZoneOrder <= currentZone then
		syncPlayerAttributes(player, profile)
		tagUnlockedZoneScreens(player, currentZone)
		return {
			success = true,
			message = "Zone already unlocked",
			currentZone = currentZone,
			money = profile.Money,
			unlocked = false,
		}
	end

	if requestedZoneOrder > currentZone + 1 then
		self.Services.NotificationService:Error(player, "Unlock the previous zone first", nil, nil)

		return {
			success = false,
			message = "Unlock the previous zone first",
			currentZone = currentZone,
			money = profile.Money,
		}
	end

	local unlockWall = zoneContext.unlockWall
	if not unlockWall or not unlockWall.Parent then
		return {
			success = false,
			message = "Unlock wall is unavailable",
			currentZone = currentZone,
			money = profile.Money,
		}
	end

	local rootPart = getCharacterRootPart(player)
	if not rootPart then
		return {
			success = false,
			message = "Character is not ready",
			currentZone = currentZone,
			money = profile.Money,
		}
	end


	local price = math.max(0, zoneContext.definition.price)
	local money = profile.Money
	if money < price then
		self.Services.NotificationService:Error(player, "Not enough Money", nil, nil)
		return {
			success = false,
			message = "Not enough Money",
			currentZone = currentZone,
			money = money,
		}
	end

	self.Services.DataService:IncrementMoney(player, -price, "zone")
	profile.CurrentZone = requestedZoneOrder

	syncPlayerAttributes(player, profile)
	tagUnlockedZoneScreens(player, requestedZoneOrder)
	self.Services.EnemyService:RefreshPlayerZone(player)

	-- Emit only on a real new unlock (this branch); the "already unlocked" path above does not.
	local customAnalytics = self.Services.CustomAnalyticsService
	if customAnalytics then
		customAnalytics:ZoneUnlock(player, {
			zoneOrder = requestedZoneOrder,
			zoneName = zoneContext.definition.label,
			price = price,
		})
	end

	return {
		success = true,
		currentZone = requestedZoneOrder,
		money = profile.Money,
		unlocked = true,
	}
end

function ZoneService:ResetPlayerZones(player: Player): (boolean, string)
	local profile = self:GetProfile(player)
	if not profile then
		return false, "Profile is not loaded"
	end

	profile.CurrentZone = DEFAULT_ZONE_ORDER
	syncPlayerAttributes(player, profile)
	removePlayerIgnoreTags(player)
	tagUnlockedZoneScreens(player, DEFAULT_ZONE_ORDER)
	self.Services.EnemyService:RefreshPlayerZone(player)

	local firstZoneContext = self.ZoneContextsByOrder[DEFAULT_ZONE_ORDER]
	local rootPart = getCharacterRootPart(player)
	if firstZoneContext and rootPart then
		local spawnCFrame = getZoneFloorSpawnCFrame(firstZoneContext)
		if spawnCFrame then
			rootPart.CFrame = spawnCFrame
		end
	end

	return true, `Zone reset for {player.Name}`
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ZoneService:Init(services)
	self.Services = services

	local zonesFolder = Workspace:WaitForChild("Zones")
	for _, zoneModel in zonesFolder:GetChildren() do
		registerZoneModel(zoneModel)
	end

	zonesFolder.ChildAdded:Connect(function(child: Instance)
		registerZoneModel(child)
	end)

	zonesFolder.ChildRemoved:Connect(function(child: Instance)
		unregisterZoneModel(child)
	end)
end

function ZoneService:Start()
	remotes.UnlockZone.OnServerInvoke = function(player: Player, zone: any)
		return self:UnlockZone(player, zone)
	end

	Players.PlayerRemoving:Connect(removePlayerIgnoreTags)

	self.Services.DataService.Signals.DataLoaded:Connect(onPlayerDataLoaded)

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Loaded") == true then
			onPlayerDataLoaded(player)
		end
	end
end

return ZoneService
