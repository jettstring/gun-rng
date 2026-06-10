local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local SkillTree = require(ReplicatedStorage.Util.Skills.SkillTree)
local SkillDefinitions = require(ReplicatedStorage.Util.Skills.SkillDefinitions)
local SpecialRollDefinitions = require(ReplicatedStorage.GameAssets.RollAssets.SpecialRollDefinitions)
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local upgradeRemotes = remotesFolder:WaitForChild("Upgrades")
local remotes = {
	GetOwnedSkills = upgradeRemotes:WaitForChild("GetOwnedSkills") :: RemoteFunction,
	UnlockSkill = upgradeRemotes:WaitForChild("UnlockSkill") :: RemoteFunction,
	OwnedSkillsChanged = upgradeRemotes:WaitForChild("OwnedSkillsChanged") :: RemoteEvent,
}

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type SkillIdMap = { [string]: boolean }
type UnlockSkillResult = {
	success: boolean,
	message: string?,
	ownedSkills: SkillIdMap?,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local UpgradeService = {}
UpgradeService.Services = {}
UpgradeService.Signals = {}

local knownSkillIds: SkillIdMap = {}
local knownSkillTree = SkillTree.new({
	tree = SkillDefinitions.tree,
})
local defaultStats = knownSkillTree:GetOwnedStats()

for skillId, skill in knownSkillTree.skills do
	if not skill.hidden and not skill.subTreeEntrance then
		knownSkillIds[skillId] = true
	end
end

local MAGNET_RANGE_ATTRIBUTE = "magnetRange"
local AUTO_AIM_HEADSHOT_CHANCE_ATTRIBUTE = "autoAimHeadshotChance"

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function getResolvedStat(stats: SkillTree.ResolvedStats?, statName: string): number?
	if not stats then
		return nil
	end

	local statValue = stats[statName]
	if typeof(statValue) ~= "number" then
		return nil
	end

	return statValue
end

local function copySkillIdMap(skillIds: SkillIdMap): SkillIdMap
	local copy: SkillIdMap = {}

	for skillId in skillIds do
		copy[skillId] = true
	end

	return copy
end

local function sanitizeOwnedSkills(ownedSkills: any): SkillIdMap
	local sanitized: SkillIdMap = {}

	if typeof(ownedSkills) ~= "table" then
		return sanitized
	end

	for key, value in ownedSkills do
		local skillId: string? = nil

		if typeof(key) == "string" and value == true then
			skillId = key
		elseif typeof(value) == "string" then
			skillId = value
		end

		if skillId and knownSkillIds[skillId] == true then
			sanitized[skillId] = true
		end
	end

	return sanitized
end

local function getProfileUpgradeData(profile: any): any
	if typeof(profile.Upgrades) ~= "table" then
		profile.Upgrades = {}
	end

	return profile.Upgrades
end

local function syncProfileOwnedSkills(profile: any): SkillIdMap
	local upgrades = getProfileUpgradeData(profile)
	local ownedSkills = sanitizeOwnedSkills(upgrades.UnlockedNodes)

	upgrades.UnlockedNodes = ownedSkills

	return ownedSkills
end

local function createSkillTree(ownedSkills: SkillIdMap): SkillTree.Type
	local tree = SkillTree.new({
		tree = SkillDefinitions.tree,
	})

	for skillId, owned in ownedSkills do
		if owned and tree:GetSkill(skillId) then
			tree:SetOwned(skillId, true)
		end
	end

	return tree
end

local function isSkillAvailable(tree: SkillTree.Type, skillId: string): boolean
	local skill = tree:GetSkill(skillId)
	if not skill then
		return false
	end

	if skill.owned then
		return true
	end

	local parents = tree:GetParents(skillId)
	if #parents == 0 then
		return true
	end

	for _, parent in parents do
		if parent.owned or (parent.subTreeEntrance and isSkillAvailable(tree, parent.id)) then
			return true
		end
	end

	return false
end

local function setPlayerMagnetRangeAttribute(player: Player, magnetRange: number)
	player:SetAttribute(MAGNET_RANGE_ATTRIBUTE, math.max(0, magnetRange))
end

local function getProfileMoney(profile: any): number
	local money = profile.Money
	if typeof(money) ~= "number" then
		return 0
	end

	return money
end

local function getPlayerUpgradeStat(service: any, player: Player, statName: string): number?
	local dataService = service.Services.DataService
	if not dataService or not dataService.Profiles[player] then
		return getResolvedStat(defaultStats, statName)
	end

	local upgradeStats = service:GetPlayerSkillStats(player)
	return getResolvedStat(upgradeStats, statName)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function UpgradeService:GetProfile(player: Player): any?
	local dataService = self.Services.DataService
	if not dataService then
		warn("[UpgradeService] DataService is not available")
		return nil
	end

	return dataService:GetProfile(player)
end

function UpgradeService:GetOwnedSkills(player: Player): SkillIdMap
	local profile = self:GetProfile(player)
	if not profile then
		return {}
	end

	local ownedSkills = syncProfileOwnedSkills(profile)
	return copySkillIdMap(ownedSkills)
end

function UpgradeService:GetPlayerSkillTree(player: Player): SkillTree.Type?
	local profile = self:GetProfile(player)
	if not profile then
		return nil
	end

	return createSkillTree(syncProfileOwnedSkills(profile))
end

function UpgradeService:GetPlayerSkillStats(player: Player): SkillTree.ResolvedStats?
	local tree = self:GetPlayerSkillTree(player)
	if not tree then
		return nil
	end

	return tree:GetOwnedStats()
end

function UpgradeService:GetMagnetRange(player: Player): number
	-- TODO: Factor in gamepasses and developer products once they are added.
	return getPlayerUpgradeStat(self, player, "magnetRange") :: number
end

function UpgradeService:GetWalkSpeed(player: Player): number
	return getPlayerUpgradeStat(self, player, "walkSpeed") :: number
end

function UpgradeService:GetGunSlots(player: Player): number
	return getPlayerUpgradeStat(self, player, "gunSlots") :: number
end

function UpgradeService:GetBackpackUnlocked(player: Player): boolean
	return (getPlayerUpgradeStat(self, player, "backpackUnlocked") :: number) >= 1
end

function UpgradeService:GetLuck(player: Player): number
	return getPlayerUpgradeStat(self, player, "luck") :: number
end

function UpgradeService:GetRollSpeed(player: Player): number
	return getPlayerUpgradeStat(self, player, "rollSpeed") :: number
end

function UpgradeService:GetBonusChance(player: Player): number
	return getPlayerUpgradeStat(self, player, "bonusChance") :: number
end

function UpgradeService:GetMoneyMultiplier(player: Player): number
	return getPlayerUpgradeStat(self, player, "moneyMultiplier") :: number
end

function UpgradeService:GetDogtagsMultiplier(player: Player): number
	return getPlayerUpgradeStat(self, player, "tagsMultiplier") :: number
end

function UpgradeService:GetOfflineMoneyMultiplier(player: Player): number
	return getPlayerUpgradeStat(self, player, "offlineMoneyMultiplier") :: number
end

function UpgradeService:GetEnemyCap(player: Player): number
	return getPlayerUpgradeStat(self, player, "enemyCap") :: number
end

function UpgradeService:GetEnemySpawnSpeed(player: Player): number
	return getPlayerUpgradeStat(self, player, "enemySpawnSpeed") or 0
end

function UpgradeService:GetSpecialEnemyChance(player: Player, chanceStat: string): number
	return getPlayerUpgradeStat(self, player, chanceStat) or 0
end

function UpgradeService:CanRollMutation(player: Player, mutationName: string?): boolean
	local mutationValue = getPlayerUpgradeStat(self, player, mutationName)
	return mutationValue ~= nil and mutationValue >= 1
end

function UpgradeService:SyncPlayerMagnetRange(player: Player)
	setPlayerMagnetRangeAttribute(player, self:GetMagnetRange(player))
end

function UpgradeService:SyncPlayerAutoAimHeadshotChance(player: Player)
	local chance = self:GetAutoAimHeadshotChance(player)
	if typeof(chance) == "number" and chance > 0 then
		player:SetAttribute(AUTO_AIM_HEADSHOT_CHANCE_ATTRIBUTE, math.clamp(chance, 0, 1))
	else
		player:SetAttribute(AUTO_AIM_HEADSHOT_CHANCE_ATTRIBUTE, nil)
	end
end

function UpgradeService:GetSpecialRoll(player, specialRollName: string): SpecialRollDefinitions.SpecialRoll?
	if not SpecialRollDefinitions[specialRollName] then warn("Warning: Invalid special roll name: " .. specialRollName) return nil end
	if specialRollName == "Gold" then
		local rollsNeeded = getPlayerUpgradeStat(self, player, "goldenRollsNeeded")
		if rollsNeeded then
			return {
				rollsNeeded = rollsNeeded,
				rollLuckMultiplier = getPlayerUpgradeStat(self, player, "goldenRollLuckMultiplier"),
				displayIcon = SpecialRollDefinitions.Gold.displayIcon
			}
		end
	elseif specialRollName == "Diamond" then
		local rollsNeeded = getPlayerUpgradeStat(self, player, "diamondRollsNeeded")
		if rollsNeeded then
			return {
				rollsNeeded = rollsNeeded,
				rollLuckMultiplier = getPlayerUpgradeStat(self, player, "diamondRollLuckMultiplier"),
				displayIcon = SpecialRollDefinitions.Diamond.displayIcon
			}
		end
	elseif specialRollName == "Rainbow" then
		local rollsNeeded = getPlayerUpgradeStat(self, player, "rainbowRollsNeeded")
		if rollsNeeded then
			return {
				rollsNeeded = rollsNeeded,
				rollLuckMultiplier = getPlayerUpgradeStat(self, player, "rainbowRollLuckMultiplier"),
				displayIcon = SpecialRollDefinitions.Diamond.displayIcon
			}
		end
	else
		return nil
	end
end

function UpgradeService:GetItemDropChance(player, itemName: string): number?
	return getPlayerUpgradeStat(self, player, itemName)
end
function UpgradeService:GetComponentDropChance(player: Player, component: string): number?
	return getPlayerUpgradeStat(self, player, component)
end
function UpgradeService:GetAutoAimHeadshotChance(player): number?
	return getPlayerUpgradeStat(self, player, "AutoAimHeadshot")
end
function UpgradeService:ResetPlayerUpgrades(player: Player): (boolean, string)
	local profile = self:GetProfile(player)
	if not profile then
		return false, `Profile is not loaded for {player.Name}`
	end

	local upgrades = getProfileUpgradeData(profile)
	upgrades.UnlockedNodes = {}

	remotes.OwnedSkillsChanged:FireClient(player, {})
	self:SyncPlayerMagnetRange(player)
	self:SyncPlayerAutoAimHeadshotChance(player)
	if self.Services.CharacterService then
		self.Services.CharacterService:SyncPlayerWalkSpeed(player)
	end

	return true, `Upgrade tree reset for {player.Name}`
end

function UpgradeService:UnlockSkill(player: Player, skillId: any): UnlockSkillResult
	if typeof(skillId) ~= "string" or skillId == "" then
		return {
			success = false,
			message = "Invalid skill id",
		}
	end

	if knownSkillIds[skillId] ~= true then
		return {
			success = false,
			message = "Unknown skill id",
		}
	end

	local profile = self:GetProfile(player)
	if not profile then
		return {
			success = false,
			message = "Profile is not loaded",
		}
	end

	local ownedSkills = syncProfileOwnedSkills(profile)
	local tree = createSkillTree(ownedSkills)
	local skill = tree:RequireSkill(skillId)

	if skill.owned then
		return {
			success = true,
			message = "Skill is already unlocked",
			ownedSkills = copySkillIdMap(ownedSkills),
		}
	end

	if not isSkillAvailable(tree, skillId) then
		return {
			success = false,
			message = "Skill is not available",
			ownedSkills = copySkillIdMap(ownedSkills),
		}
	end

	local price = math.max(0, skill.price)
	if getProfileMoney(profile) < price then
		return {
			success = false,
			message = "Not enough Money",
			ownedSkills = copySkillIdMap(ownedSkills),
		}
	end

	if price > 0 then
		self.Services.DataService:IncrementMoney(player, -price, "upgrade")
	end

	ownedSkills[skillId] = true
	tree:SetOwned(skillId, true)

	local stats = tree:GetOwnedStats()
	setPlayerMagnetRangeAttribute(player, getResolvedStat(stats, "magnetRange") :: number)

	if skill.stats.AutoAimHeadshot ~= nil then
		self:SyncPlayerAutoAimHeadshotChance(player)
	end

	if skill.stats.walkSpeed ~= nil and self.Services.CharacterService then
		self.Services.CharacterService:SyncPlayerWalkSpeed(player)
	end
		
	if skill.stats.luck ~= nil then
		self.Services.RollService:SendUpdatedLuck(player)
	end
	
	if skill.stats.rollSpeed ~= nil then
		self.Services.RollService:SendUpdatedRollTime(player)
	end
	
	if skill.stats.goldenRollsNeeded ~= nil or 
		skill.stats.goldenRollLuckMultiplier ~= nil or 
		skill.stats.diamondRollsNeeded ~= nil or 
		skill.stats.diamondRollLuckMultiplier ~= nil or 
		skill.stats.rainbowRollsNeeded ~= nil or 
		skill.stats.rainbowRollLuckMultiplier ~= nil
	then
		self.Services.RollService:SendUpdatedRollingData(player)
	end

	local customAnalytics = self.Services.CustomAnalyticsService
	if customAnalytics then
		customAnalytics:SkillUnlock(player, {
			skillId = skillId,
			price = price,
		})
	end

	return {
		success = true,
		ownedSkills = copySkillIdMap(ownedSkills),
	}
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function UpgradeService:Init(services)
	self.Services = services
end

function UpgradeService:Start()
	remotes.GetOwnedSkills.OnServerInvoke = function(player: Player)
		return self:GetOwnedSkills(player)
	end

	remotes.UnlockSkill.OnServerInvoke = function(player: Player, skillId: any)
		local unlockResult: UnlockSkillResult = self:UnlockSkill(player, skillId)
		if not unlockResult.success then
			self.Services.NotificationService:Error(player, unlockResult.message, nil, nil)
		end
		return unlockResult
	end

	self.Services.DataService.Signals.DataLoaded:Connect(function(player: Player)
		self:SyncPlayerMagnetRange(player)
		self:SyncPlayerAutoAimHeadshotChance(player)
	end)

	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Loaded") == true then
			self:SyncPlayerMagnetRange(player)
			self:SyncPlayerAutoAimHeadshotChance(player)
		end
	end
end

return UpgradeService
