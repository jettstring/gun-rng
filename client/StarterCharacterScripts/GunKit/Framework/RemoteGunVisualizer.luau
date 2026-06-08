local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GunClient = require(script.Parent:WaitForChild("GunClient"))
local WeaponDefinitions = require(
	ReplicatedStorage:WaitForChild("GameAssets")
		:WaitForChild("WeaponAssets")
		:WaitForChild("WeaponDefinitions")
)

local module = {}
local module_mt = {__index = module}

local REPLICATED_GUN_FOLDER_NAME = "PsychicGuns"
local REMOTE_GUN_ROOT_FOLDER_NAME = "RemotePsychicGuns"
local PENDING_SHOT_TTL = 1
local MAX_PENDING_SHOTS_PER_GUN = 8
local FALLBACK_AIM_DISTANCE = 1000

type Connection = RBXScriptConnection
type WeaponDefinition = WeaponDefinitions.WeaponDefinition

local function disconnectConnections(connections: {Connection})
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function getWeaponDefinition(gunName: string): WeaponDefinition?
	local directDefinition = WeaponDefinitions[gunName]
	if directDefinition then
		return directDefinition
	end

	local loweredGunName = string.lower(gunName)
	for definitionName, definition in WeaponDefinitions do
		if typeof(definitionName) == "string" and string.lower(definitionName) == loweredGunName then
			return definition
		end

		if typeof(definition) == "table" and typeof(definition.label) == "string" then
			if string.lower(definition.label) == loweredGunName then
				return definition
			end
		end
	end

	return nil
end

local function getGunTypeKey(gunData: WeaponDefinition, gunName: string): string
	if typeof(gunData.label) == "string" and gunData.label ~= "" then
		return string.lower(gunData.label)
	end

	return string.lower(gunName)
end

local function getRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

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

local function getFallbackAimPoint(character: Model?): Vector3?
	local rootPart = getRootPart(character)
	if not rootPart then
		return nil
	end

	return rootPart.Position + rootPart.CFrame.LookVector * FALLBACK_AIM_DISTANCE
end

local function readGunDescriptor(descriptor: Instance): (string?, string?)
	local gunNameAttribute = descriptor:GetAttribute("GunName")
	local weaponNameAttribute = descriptor:GetAttribute("WeaponName")
	local gunIdAttribute = descriptor:GetAttribute("GunId")
	local gunName = if typeof(gunNameAttribute) == "string" and gunNameAttribute ~= ""
		then gunNameAttribute
		elseif typeof(weaponNameAttribute) == "string" and weaponNameAttribute ~= "" then weaponNameAttribute
		elseif descriptor:IsA("StringValue") and descriptor.Value ~= "" then descriptor.Value
		else descriptor.Name
	local gunId = if typeof(gunIdAttribute) == "string" and gunIdAttribute ~= "" then gunIdAttribute else descriptor.Name

	if gunName == "" or gunId == "" then
		return nil, nil
	end

	return gunName, gunId
end

function module:getRecordKey(ownerUserId: number, gunId: string): string
	return `{ownerUserId}:{gunId}`
end

function module.new(localPlayer: Player?, gunEvent: RemoteEvent?, modelParent: Instance?)
	local self = setmetatable({}, module_mt)
	self.localPlayer = localPlayer or Players.LocalPlayer
	self.gunEvent = gunEvent
	self.connections = {}
	self.playerConnections = {}
	self.playerStates = {}
	self.recordsByKey = {}
	self.stateByKey = {}
	self.pendingShotsByKey = {}
	self.clock = 0
	self.destroyed = false

	local rootParent = modelParent or workspace:FindFirstChild("RAY_IGNORE") or workspace
	local rootFolderName = `{self.localPlayer.Name}_{REMOTE_GUN_ROOT_FOLDER_NAME}`
	local existingRootFolder = rootParent:FindFirstChild(rootFolderName)
	if existingRootFolder then
		existingRootFolder:Destroy()
	end

	local rootFolder = Instance.new("Folder")
	rootFolder.Name = rootFolderName
	rootFolder.Parent = rootParent
	self.rootFolder = rootFolder

	for _, player in Players:GetPlayers() do
		self:observePlayer(player)
	end

	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		self:observePlayer(player)
	end))
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self:removePlayer(player)
	end))
	table.insert(self.connections, RunService.RenderStepped:Connect(function(step)
		self:update(step)
	end))

	return self
end

function module:createPlayerFolder(player: Player): Folder
	local folder = Instance.new("Folder")
	folder.Name = `{player.Name}_{player.UserId}_PsychicGuns`
	folder.Parent = self.rootFolder
	return folder
end

function module:observePlayer(player: Player)
	if self.destroyed or player == self.localPlayer or self.playerConnections[player] then
		return
	end

	self.playerConnections[player] = {
		player.CharacterAdded:Connect(function(character)
			self:observeCharacter(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			self:clearCharacter(player)
		end),
	}

	if player.Character then
		self:observeCharacter(player, player.Character)
	end
end

function module:removePlayer(player: Player)
	self:clearCharacter(player)
	self:clearOwnerTransientState(player.UserId)

	local connections = self.playerConnections[player]
	if connections then
		disconnectConnections(connections)
		self.playerConnections[player] = nil
	end
end

function module:clearOwnerTransientState(ownerUserId: number)
	local keyPrefix = `{ownerUserId}:`
	for key in self.stateByKey do
		if string.sub(key, 1, #keyPrefix) == keyPrefix then
			self.stateByKey[key] = nil
		end
	end
	for key in self.pendingShotsByKey do
		if string.sub(key, 1, #keyPrefix) == keyPrefix then
			self.pendingShotsByKey[key] = nil
		end
	end
end

function module:clearCharacter(player: Player)
	local state = self.playerStates[player]
	if not state then
		return
	end
	self.playerStates[player] = nil

	disconnectConnections(state.connections)
	disconnectConnections(state.folderConnections)
	for _, descriptorConnections in state.descriptorConnections do
		disconnectConnections(descriptorConnections)
	end

	for _, record in state.order do
		self.recordsByKey[record.key] = nil
		self.stateByKey[record.key] = nil
		record.gunClient:DestroyModels()
	end

	if state.modelFolder and state.modelFolder.Parent then
		state.modelFolder:Destroy()
	end

end

function module:observeCharacter(player: Player, character: Model)
	if self.destroyed or player == self.localPlayer then
		return
	end

	self:clearCharacter(player)

	local state = {
		player = player,
		character = character,
		gunFolder = nil,
		modelFolder = self:createPlayerFolder(player),
		connections = {},
		folderConnections = {},
		descriptorConnections = {},
		descriptorKeys = {},
		recordsById = {},
		order = {},
	}
	self.playerStates[player] = state

	local function retryDescriptors()
		if self.playerStates[player] ~= state then
			return
		end

		if state.gunFolder then
			for _, descriptor in state.gunFolder:GetChildren() do
				self:registerDescriptor(state, descriptor)
			end
		end
	end

	local existingGunFolder = character:FindFirstChild(REPLICATED_GUN_FOLDER_NAME)
	if existingGunFolder then
		self:observeGunFolder(state, existingGunFolder)
	end

	table.insert(state.connections, character.ChildAdded:Connect(function(child)
		if child.Name == REPLICATED_GUN_FOLDER_NAME then
			self:observeGunFolder(state, child)
		elseif child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then
			retryDescriptors()
		end
	end))
	table.insert(state.connections, character.ChildRemoved:Connect(function(child)
		if self.playerStates[player] ~= state then
			return
		end

		if child ~= state.gunFolder then
			return
		end

		disconnectConnections(state.folderConnections)
		local descriptors = {}
		for descriptor in state.descriptorKeys do
			table.insert(descriptors, descriptor)
		end
		for _, descriptor in descriptors do
			self:unregisterDescriptor(state, descriptor)
		end
		state.gunFolder = nil
	end))
	table.insert(state.connections, character.Destroying:Connect(function()
		self:clearCharacter(player)
	end))
end

function module:observeGunFolder(state, folder: Instance)
	if self.destroyed or self.playerStates[state.player] ~= state then
		return
	end

	disconnectConnections(state.folderConnections)
	local descriptors = {}
	for descriptor in state.descriptorKeys do
		table.insert(descriptors, descriptor)
	end
	for _, descriptor in descriptors do
		self:unregisterDescriptor(state, descriptor)
	end

	state.gunFolder = folder
	for _, child in folder:GetChildren() do
		self:registerDescriptor(state, child)
	end

	table.insert(state.folderConnections, folder.ChildAdded:Connect(function(child)
		self:registerDescriptor(state, child)
	end))
	table.insert(state.folderConnections, folder.ChildRemoved:Connect(function(child)
		self:unregisterDescriptor(state, child)
	end))
end

function module:removeRecord(state, record)
	record.gunClient:DestroyModels()
	self.recordsByKey[record.key] = nil
	self.stateByKey[record.key] = nil
	state.recordsById[record.id] = nil

	for index, orderedRecord in state.order do
		if orderedRecord == record then
			table.remove(state.order, index)
			break
		end
	end
end

function module:registerDescriptor(state, descriptor: Instance)
	if self.destroyed or self.playerStates[state.player] ~= state or not descriptor.Parent then
		return
	end

	self:unregisterDescriptor(state, descriptor)

	local character = state.character
	if not character or not character.Parent then
		return
	end

	local gunName, gunId = readGunDescriptor(descriptor)
	if not gunName or not gunId then
		return
	end

	local weaponDefinition = getWeaponDefinition(gunName)
	if not weaponDefinition then
		return
	end

	local existingRecord = state.recordsById[gunId]
	if existingRecord then
		self:removeRecord(state, existingRecord)
	end

	local gunClient = GunClient.new(state.player, character, weaponDefinition, {
		gunId = gunId,
		gunName = gunName,
		modelParent = state.modelFolder,
		anchorParent = state.modelFolder,
		assistVisualsEnabled = false,
		autoAimEnabled = false,
		sendShootEvents = false,
	})
	if not gunClient then
		return
	end

	gunClient:equip()
	gunClient:setAutoAimEnabled(false)
	gunClient:setProjectileRays(false)

	local key = self:getRecordKey(state.player.UserId, gunId)
	local record = {
		id = gunId,
		key = key,
		gunName = gunName,
		gunClient = gunClient,
		source = descriptor,
	}
	state.recordsById[gunId] = record
	table.insert(state.order, record)
	self.recordsByKey[key] = record
	state.descriptorKeys[descriptor] = key
	state.descriptorConnections[descriptor] = {
		descriptor:GetAttributeChangedSignal("GunName"):Connect(function()
			self:registerDescriptor(state, descriptor)
		end),
		descriptor:GetAttributeChangedSignal("WeaponName"):Connect(function()
			self:registerDescriptor(state, descriptor)
		end),
		descriptor:GetAttributeChangedSignal("GunId"):Connect(function()
			self:registerDescriptor(state, descriptor)
		end),
	}
	if descriptor:IsA("StringValue") then
		table.insert(state.descriptorConnections[descriptor], descriptor:GetPropertyChangedSignal("Value"):Connect(function()
			self:registerDescriptor(state, descriptor)
		end))
	end

	self:refreshSlots(state)
	self:flushPendingShots(key)
end

function module:unregisterDescriptor(state, descriptor: Instance)
	if self.playerStates[state.player] ~= state then
		return
	end

	local key = state.descriptorKeys[descriptor]
	if key then
		local record = self.recordsByKey[key]
		if record and state.recordsById[record.id] == record then
			self:removeRecord(state, record)
		end
	end

	local descriptorConnections = state.descriptorConnections[descriptor]
	if descriptorConnections then
		disconnectConnections(descriptorConnections)
		state.descriptorConnections[descriptor] = nil
	end
	state.descriptorKeys[descriptor] = nil

	self:refreshSlots(state)
end

function module:refreshSlots(state)
	local totalGuns = #state.order
	local recordsByType = {}

	for index, record in state.order do
		record.gunClient:setSlot(index, totalGuns)

		local gunTypeKey = getGunTypeKey(record.gunClient.gunData, record.gunName)
		local recordsForType = recordsByType[gunTypeKey]
		if not recordsForType then
			recordsForType = {}
			recordsByType[gunTypeKey] = recordsForType
		end
		table.insert(recordsForType, record)
	end

	for _, recordsForType in recordsByType do
		local totalOfType = #recordsForType
		for typeIndex, record in recordsForType do
			record.gunClient:setFireCadence(typeIndex, totalOfType, self.clock, self.clock)
		end
	end
end

function module:applyState(ownerUserId: number, visualStates: {any})
	if self.destroyed or type(ownerUserId) ~= "number" or ownerUserId == self.localPlayer.UserId then
		return
	end
	if type(visualStates) ~= "table" then
		return
	end

	for _, visualState in ipairs(visualStates) do
		if type(visualState) ~= "table" then
			continue
		end

		local gunId = visualState.gunId
		local aimPoint = visualState.aimPoint
		if type(gunId) ~= "string" or gunId == "" or typeof(aimPoint) ~= "Vector3" then
			continue
		end

		self.stateByKey[self:getRecordKey(ownerUserId, gunId)] = {
			aimPoint = aimPoint,
			hasShootTarget = visualState.hasShootTarget == true,
			shooting = visualState.shooting == true,
			updatedAt = self.clock,
		}
	end
end

function module:applyShot(ownerUserId: number, gunId: string, shootCFrame: CFrame, shootDirection: Vector3)
	if
		self.destroyed
		or type(ownerUserId) ~= "number"
		or ownerUserId == self.localPlayer.UserId
		or type(gunId) ~= "string"
		or gunId == ""
		or typeof(shootCFrame) ~= "CFrame"
		or typeof(shootDirection) ~= "Vector3"
	then
		return
	end

	local key = self:getRecordKey(ownerUserId, gunId)
	local record = self.recordsByKey[key]
	if record then
		record.gunClient:playShotVisual(nil, shootCFrame, shootDirection)
		return
	end

	local pendingShots = self.pendingShotsByKey[key]
	if not pendingShots then
		pendingShots = {}
		self.pendingShotsByKey[key] = pendingShots
	end

	table.insert(pendingShots, {
		expiresAt = self.clock + PENDING_SHOT_TTL,
		shootCFrame = shootCFrame,
		shootDirection = shootDirection,
	})

	while #pendingShots > MAX_PENDING_SHOTS_PER_GUN do
		table.remove(pendingShots, 1)
	end
end

function module:flushPendingShots(key: string)
	local record = self.recordsByKey[key]
	local pendingShots = self.pendingShotsByKey[key]
	if not record or not pendingShots then
		return
	end

	for _, shot in pendingShots do
		if shot.expiresAt >= self.clock then
			record.gunClient:playShotVisual(nil, shot.shootCFrame, shot.shootDirection)
		end
	end

	self.pendingShotsByKey[key] = nil
end

function module:prunePendingShots()
	for key, pendingShots in self.pendingShotsByKey do
		for index = #pendingShots, 1, -1 do
			if pendingShots[index].expiresAt < self.clock then
				table.remove(pendingShots, index)
			end
		end

		if #pendingShots == 0 then
			self.pendingShotsByKey[key] = nil
		end
	end
end

function module:update(step: number)
	if self.destroyed then
		return
	end

	self.clock += step
	for _, state in self.playerStates do
		for _, record in state.order do
			local visualState = self.stateByKey[record.key]
			local aimPoint = if visualState then visualState.aimPoint else getFallbackAimPoint(state.character)
			record.gunClient:updateExternal(
				step,
				aimPoint,
				if visualState then visualState.hasShootTarget else false,
				if visualState then visualState.shooting else false,
				self.clock
			)
		end
	end

	self:prunePendingShots()
end

function module:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	disconnectConnections(self.connections)

	local players = {}
	for player in self.playerConnections do
		table.insert(players, player)
	end
	for _, player in players do
		self:removePlayer(player)
	end

	if self.rootFolder and self.rootFolder.Parent then
		self.rootFolder:Destroy()
	end
end

return module
