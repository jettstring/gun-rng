local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local Gigantix = require(ReplicatedStorage.Packages.Gigantix)
local Spr = require(ReplicatedStorage.Packages.Spr)
local ZoneDefinitions = require(ReplicatedStorage.GameAssets.ZoneAssets.ZoneDefinitions)

local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local zoneRemotes = remotesFolder:WaitForChild("Zones")
local unlockZoneRemote = zoneRemotes:WaitForChild("UnlockZone") :: RemoteFunction

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type ZoneDefinition = ZoneDefinitions.ZoneDefinition
type WallBinding = {
	zoneOrder: number,
	unlockWall: Model?,
	doorLeft: Model?,
	doorRight: Model?,
	doorsOpened: boolean,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local ZoneController = {}

local wallBindings = {} :: { [Instance]: WallBinding }
local zoneConnections = {} :: { [Instance]: { RBXScriptConnection } }
local watchedLogicParts = {} :: { [Folder]: Instance }
local logicPartsConnections = {} :: { [Folder]: { RBXScriptConnection } }
local watchedWallFolders = {} :: { [Folder]: Instance }
local wallFolderConnections = {} :: { [Folder]: RBXScriptConnection }
local boundUnlockWalls = setmetatable({}, { __mode = "k" }) :: { [Model]: boolean }
local pendingButtons = setmetatable({}, { __mode = "k" }) :: { [GuiButton]: boolean }
local originalWallParts = setmetatable({}, { __mode = "k" }) :: { [BasePart]: { transparency: number, canCollide: boolean } }

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local HOVER_SCALE = 1.1
local BUTTON_DAMPING_RATIO = 0.75
local BUTTON_FREQUENCY = 6
local ZONES_WAIT_TIMEOUT = 10
local DOOR_OPEN_DISTANCE = 50
local UNLOCK_SOUND_ID = "rbxassetid://92913943199420"
local UNLOCK_SOUND_NAME = "ZoneUnlockSound"
local UNLOCK_SOUND_VOLUME = 0.7

local unlockSound: Sound?

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function scaleSize(size: UDim2, scale: number): UDim2
	return UDim2.new(
		size.X.Scale * scale,
		size.X.Offset * scale,
		size.Y.Scale * scale,
		size.Y.Offset * scale
	)
end

local function formatPrice(price: number): string
	local roundedPrice = math.max(0, math.floor(price + 0.5))
	return Gigantix.getShort(Gigantix.stringToNumber(tostring(roundedPrice)))
end

local function findChildFolder(parent: Instance, childName: string): Folder?
	local child = parent:FindFirstChild(childName)
	if child and child:IsA("Folder") then
		return child
	end

	return nil
end

local function findChildModel(parent: Instance, childName: string): Model?
	local child = parent:FindFirstChild(childName)
	if child and child:IsA("Model") then
		return child
	end

	return nil
end

local function isZoneContainer(instance: Instance): boolean
	return instance:IsA("Folder") or instance:IsA("Model")
end

local function getUnlockSound(): Sound
	if unlockSound then
		return unlockSound
	end

	local existingSound = SoundService:FindFirstChild(UNLOCK_SOUND_NAME)
	if existingSound and existingSound:IsA("Sound") then
		unlockSound = existingSound
		return existingSound
	end

	local sound = Instance.new("Sound")
	sound.Name = UNLOCK_SOUND_NAME
	sound.SoundId = UNLOCK_SOUND_ID
	sound.Volume = UNLOCK_SOUND_VOLUME
	sound.Parent = SoundService

	unlockSound = sound
	return sound
end

local function playUnlockSound()
	local sound = getUnlockSound()
	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local function getCurrentZone(currentZoneOverride: number?): number
	if typeof(currentZoneOverride) == "number" then
		return currentZoneOverride
	end

	local currentZone = player:GetAttribute("CurrentZone")
	if typeof(currentZone) ~= "number" then
		return 1
	end

	return currentZone
end

local function disconnectWallFolder(wallFolder: Folder)
	local connection = wallFolderConnections[wallFolder]
	if connection then
		connection:Disconnect()
		wallFolderConnections[wallFolder] = nil
	end

	watchedWallFolders[wallFolder] = nil
end

local function disconnectLogicParts(logicParts: Folder)
	local owner = watchedLogicParts[logicParts]
	local connections = logicPartsConnections[logicParts]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	logicPartsConnections[logicParts] = nil
	watchedLogicParts[logicParts] = nil

	if not owner then
		return
	end

	local wallFoldersToDisconnect = {} :: { Folder }
	for wallFolder, wallOwner in watchedWallFolders do
		if wallOwner == owner and wallFolder.Parent == logicParts then
			table.insert(wallFoldersToDisconnect, wallFolder)
		end
	end

	for _, wallFolder in wallFoldersToDisconnect do
		disconnectWallFolder(wallFolder)
	end
end

local function disconnectZoneModel(zoneModel: Instance)
	local connections = zoneConnections[zoneModel]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	local logicPartsToDisconnect = {} :: { Folder }
	for logicParts, owner in watchedLogicParts do
		if owner == zoneModel then
			table.insert(logicPartsToDisconnect, logicParts)
		end
	end

	for _, logicParts in logicPartsToDisconnect do
		disconnectLogicParts(logicParts)
	end

	local wallFoldersToDisconnect = {} :: { Folder }
	for wallFolder, owner in watchedWallFolders do
		if owner == zoneModel then
			table.insert(wallFoldersToDisconnect, wallFolder)
		end
	end

	for _, wallFolder in wallFoldersToDisconnect do
		disconnectWallFolder(wallFolder)
	end

	zoneConnections[zoneModel] = nil
	wallBindings[zoneModel] = nil
end

local function trackZoneConnection(zoneModel: Instance, connection: RBXScriptConnection)
	local connections = zoneConnections[zoneModel]
	if not connections then
		connection:Disconnect()
		return
	end

	table.insert(connections, connection)
end

-- hide/show the unlock wall instead of destroying it so we can restore on rebirth
local function setUnlockWallHidden(unlockWall: Model?, hidden: boolean)
	if not unlockWall then
		return
	end
	
	for _, descendant in unlockWall:GetDescendants() do
		if descendant:IsA("BasePart") then
			if hidden then
				-- store original properties so they can be restored later
				if not originalWallParts[descendant] then
					originalWallParts[descendant] = {
						transparency = descendant.Transparency,
						canCollide = descendant.CanCollide,
					}
				end

				descendant.Transparency = 1
				descendant.CanCollide = false
			else
				local original = originalWallParts[descendant]
				if original then
					descendant.Transparency = original.transparency
					descendant.CanCollide = original.canCollide
				end
			end
		elseif descendant:IsA("SurfaceGui") then
			descendant.Enabled = not hidden
		end
	end
end

local function openWall(binding: WallBinding)
	setUnlockWallHidden(binding.unlockWall, true)

	local doorLeft = binding.doorLeft
	local doorRight = binding.doorRight
	if binding.doorsOpened or not doorLeft or not doorRight then
		return
	end

	doorLeft:PivotTo(doorLeft:GetPivot() + Vector3.new(-DOOR_OPEN_DISTANCE, 0, 0))
	doorRight:PivotTo(doorRight:GetPivot() + Vector3.new(DOOR_OPEN_DISTANCE, 0, 0))

	binding.doorsOpened = true
end

local function closeWall(binding: WallBinding)
	setUnlockWallHidden(binding.unlockWall, false)

	local doorLeft = binding.doorLeft
	local doorRight = binding.doorRight
	if not binding.doorsOpened or not doorLeft or not doorRight then
		return
	end

	doorLeft:PivotTo(doorLeft:GetPivot() + Vector3.new(DOOR_OPEN_DISTANCE, 0, 0))
	doorRight:PivotTo(doorRight:GetPivot() + Vector3.new(-DOOR_OPEN_DISTANCE, 0, 0))

	binding.doorsOpened = false
end

local function refreshWalls(currentZoneOverride: number?)
	local currentZone = getCurrentZone(currentZoneOverride)

	for zoneModel, binding in wallBindings do
		if zoneModel.Parent then
			if binding.zoneOrder <= currentZone then
				openWall(binding)
			else
				closeWall(binding)
			end
		else
			wallBindings[zoneModel] = nil
		end
	end
end

local function bindUnlockWall(unlockWall: Model, zoneDefinition: ZoneDefinition, zoneOrder: number): boolean
	local screen = unlockWall:FindFirstChild("Screen")
	local surfaceGui: SurfaceGui? = nil
	if screen then
		local candidate = screen:FindFirstChildWhichIsA("SurfaceGui")
		if candidate and candidate:IsA("SurfaceGui") then
			surfaceGui = candidate
		end
	end

	if not surfaceGui then
		warn(`[ZoneController] {unlockWall:GetFullName()} is missing Screen.SurfaceGui`)
		return false
	end

	local zoneNameLabel = surfaceGui:FindFirstChild("ZoneName", true)
	if zoneNameLabel and zoneNameLabel:IsA("TextLabel") then
		zoneNameLabel.Text = zoneDefinition.label
	end

	local priceText = surfaceGui:FindFirstChild("PriceText", true)
	if priceText and priceText:IsA("TextLabel") then
		priceText.Text = formatPrice(zoneDefinition.price)
	end

	local button = surfaceGui:FindFirstChild("BuyButton", true)
	if not button or not button:IsA("GuiButton") then
		warn(`[ZoneController] {surfaceGui:GetFullName()} is missing BuyButton`)
		return false
	end

	button.Active = true
	button.AutoButtonColor = true
	button.Selectable = true
	surfaceGui.Enabled = true

	local defaultSize = button.Size
	local hoverSize = scaleSize(defaultSize, HOVER_SCALE)

	button.MouseEnter:Connect(function()
		Spr.target(button, BUTTON_DAMPING_RATIO, BUTTON_FREQUENCY, {
			Size = hoverSize,
		})
	end)

	button.MouseLeave:Connect(function()
		Spr.target(button, BUTTON_DAMPING_RATIO, BUTTON_FREQUENCY, {
			Size = defaultSize,
		})
	end)

	button.Activated:Connect(function()
		if pendingButtons[button] then
			return
		end

		pendingButtons[button] = true
		local ok, response = pcall(function()
			return unlockZoneRemote:InvokeServer(zoneOrder)
		end)
		pendingButtons[button] = nil

		if not ok then
			warn(`[ZoneController] UnlockZone invoke failed: {response}`)
			return
		end

		if typeof(response) ~= "table" then
			warn("[ZoneController] UnlockZone returned an invalid response")
			return
		end

		local responseTable = response :: { [string]: any }
		if responseTable.success == true then
			local currentZone = responseTable.currentZone
			refreshWalls(if typeof(currentZone) == "number" then currentZone else nil)

			if responseTable.unlocked == true then
				playUnlockSound()
			end
			return
		end

		local message = responseTable.message
		local displayMessage = if typeof(message) == "string" then message else "Unlock failed"
		
		warn(`[ZoneController] {displayMessage}`)
	end)

	return true
end

local function configureWall(zoneModel: Instance, wallFolder: Folder)
	local zoneDefinition = ZoneDefinitions[zoneModel.Name]
	if not zoneDefinition then
		warn(`[ZoneController] Missing ZoneDefinitions entry for Workspace.Zones.{zoneModel.Name}`)
		return
	end

	local zoneOrder = zoneDefinition.order
	if typeof(zoneOrder) ~= "number" then
		warn(`[ZoneController] Workspace.Zones.{zoneModel.Name} has an invalid zone order`)
		return
	end

	local unlockWall = findChildModel(wallFolder, "UnlockWall")
	local gate = findChildModel(wallFolder, "Gate")
	local doorLeft = if gate then findChildModel(gate, "DoorLeft") else nil
	local doorRight = if gate then findChildModel(gate, "DoorRight") else nil

	local binding = wallBindings[zoneModel]
	if binding then
		local doorsChanged = binding.doorLeft ~= doorLeft or binding.doorRight ~= doorRight
		binding.zoneOrder = zoneOrder
		binding.unlockWall = unlockWall
		binding.doorLeft = doorLeft
		binding.doorRight = doorRight

		if doorsChanged then
			binding.doorsOpened = false
		end
	else
		binding = {
			zoneOrder = zoneOrder,
			unlockWall = unlockWall,
			doorLeft = doorLeft,
			doorRight = doorRight,
			doorsOpened = false,
		}
		wallBindings[zoneModel] = binding
	end

	if unlockWall and not boundUnlockWalls[unlockWall] then
		if bindUnlockWall(unlockWall, zoneDefinition, zoneOrder) then
			boundUnlockWalls[unlockWall] = true
		end
	end

	if zoneOrder <= getCurrentZone(nil) then
		openWall(binding)
	end
end

local function bindWallFolder(zoneModel: Instance, wallFolder: Folder)
	configureWall(zoneModel, wallFolder)

	if watchedWallFolders[wallFolder] then
		return
	end

	watchedWallFolders[wallFolder] = zoneModel

	local connection = wallFolder.DescendantAdded:Connect(function()
		configureWall(zoneModel, wallFolder)
	end)

	wallFolderConnections[wallFolder] = connection
end

local function bindZoneModel(zoneModel: Instance)
	if zoneConnections[zoneModel] then
		return
	end

	zoneConnections[zoneModel] = {}

	local function bindLogicParts(logicParts: Folder)
		if watchedLogicParts[logicParts] then
			return
		end

		watchedLogicParts[logicParts] = zoneModel

		local wallFolder = findChildFolder(logicParts, "Wall")
		if wallFolder then
			bindWallFolder(zoneModel, wallFolder)
		end

		local childAddedConnection = logicParts.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Wall" and child:IsA("Folder") then
				bindWallFolder(zoneModel, child)
			end
		end)

		local childRemovedConnection = logicParts.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Folder") and watchedWallFolders[child] == zoneModel then
				disconnectWallFolder(child)
			end
		end)

		logicPartsConnections[logicParts] = {
			childAddedConnection,
			childRemovedConnection,
		}
	end

	local logicParts = findChildFolder(zoneModel, "LogicParts")
	if logicParts then
		bindLogicParts(logicParts)
	end

	trackZoneConnection(zoneModel, zoneModel.ChildAdded:Connect(function(child: Instance)
		if child.Name == "LogicParts" and child:IsA("Folder") then
			bindLogicParts(child)
		end
	end))

	trackZoneConnection(zoneModel, zoneModel.ChildRemoved:Connect(function(child: Instance)
		if child.Name == "LogicParts" and child:IsA("Folder") and watchedLogicParts[child] == zoneModel then
			disconnectLogicParts(child)
		end
	end))
end

local function bindZonesFolder()
	local zonesFolder = Workspace:WaitForChild("Zones", ZONES_WAIT_TIMEOUT)
	if not zonesFolder then
		warn(`[ZoneController] Workspace.Zones was not found within {ZONES_WAIT_TIMEOUT} seconds`)
		return
	end

	for _, zoneModel in zonesFolder:GetChildren() do
		if isZoneContainer(zoneModel) then
			bindZoneModel(zoneModel)

			local logicParts = findChildFolder(zoneModel, "LogicParts")
			local wallFolder = if logicParts then findChildFolder(logicParts, "Wall") else nil
			if wallFolder then
				configureWall(zoneModel, wallFolder)
			end
		end
	end

	zonesFolder.ChildAdded:Connect(function(child: Instance)
		if isZoneContainer(child) then
			bindZoneModel(child)
		end
	end)

	zonesFolder.ChildRemoved:Connect(function(child: Instance)
		if isZoneContainer(child) then
			disconnectZoneModel(child)
		end
	end)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ZoneController:RefreshUnlocks()
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return
	end

	for _, zoneModel in zonesFolder:GetChildren() do
		if isZoneContainer(zoneModel) then
			bindZoneModel(zoneModel)
		end
	end

	refreshWalls(nil)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ZoneController:Init()
end

function ZoneController:Start()
	player:GetAttributeChangedSignal("CurrentZone"):Connect(function()
		refreshWalls(nil)
	end)

	bindZonesFolder()
	refreshWalls(nil)
end

return ZoneController
