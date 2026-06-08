local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local zoneRemotes = remotesFolder:WaitForChild("Zones")
local remotes = {
	MovePlayerToZone = zoneRemotes:WaitForChild("MovePlayerToZone") :: RemoteFunction,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local CharacterService = {}
CharacterService.Services = {}
CharacterService.Signals = {}
CharacterService.PlayerConnections = {} :: { [Player]: RBXScriptConnection }

local PLAYER_COLLISION_GROUP = "Player"
local TELEPORTER_REWARD = "Teleporter"

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function CharacterService:SyncPlayerWalkSpeed(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end

	local walkSpeed = self.Services.UpgradeService:GetWalkSpeed(player)
	humanoid.WalkSpeed = math.max(0, walkSpeed)
end

function CharacterService:SetCharacterCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			print("SET COLLISION GROUP")
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
			descendant:AddTag("Player")
		end
	end
end

function CharacterService:MovePlayerToZone(player: Player, zoneOrder: number)
	local character = player.Character
	if not character then
		return
	end

	if not character:WaitForChild("HumanoidRootPart", 5) then
		return
	end

	local spawnCFrame = self.Services.ZoneService:GetZoneSpawnCFrame(zoneOrder)
	if not spawnCFrame then
		return
	end

	character:PivotTo(spawnCFrame)
end

function CharacterService:MovePlayerToCurrentZone(player: Player)
	-- Guard before reading the profile; the character can spawn before data loads.
	if player:GetAttribute("Loaded") ~= true then
		return
	end

	self:MovePlayerToZone(player, self.Services.ZoneService:GetCurrentZone(player))
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function CharacterService:Init(services)
	self.Services = services
end

function CharacterService:Start()
	local function bindPlayer(player: Player)
		local existingConnection = CharacterService.PlayerConnections[player]
		if existingConnection then
			existingConnection:Disconnect()
		end

		CharacterService.PlayerConnections[player] = player.CharacterAdded:Connect(function(character)
			self:SetCharacterCollisionGroup(character)
			self:SyncPlayerWalkSpeed(player)
			self:MovePlayerToCurrentZone(player)
		end)

		if player.Character then
			self:SetCharacterCollisionGroup(player.Character)
			self:SyncPlayerWalkSpeed(player)
			self:MovePlayerToCurrentZone(player)
		end
	end

	local function unbindPlayer(player: Player)
		local connection = CharacterService.PlayerConnections[player]
		if connection then
			connection:Disconnect()
			CharacterService.PlayerConnections[player] = nil
		end
	end

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(unbindPlayer)

	self.Services.DataService.Signals.DataLoaded:Connect(function(player: Player)
		self:SyncPlayerWalkSpeed(player)
		self:MovePlayerToCurrentZone(player)
	end)

	remotes.MovePlayerToZone.OnServerInvoke = function(player: Player, zoneOrder: any): boolean
		if player:GetAttribute("Loaded") ~= true then
			return false
		end

		-- Teleporting is a rebirth-gated feature, so verify the player actually owns it.
		if not self.Services.RebirthService:OwnsRebirthReward(player, TELEPORTER_REWARD) then
			return false
		end

		-- Never let a player teleport into a zone they have not unlocked.
		if not self.Services.ZoneService:CanPlayerAccessZone(player, zoneOrder) then
			return false
		end

		self:MovePlayerToZone(player, zoneOrder)
		return true
	end
end

return CharacterService
