local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local GameAssets = ReplicatedStorage.GameAssets
local IndexAssets = GameAssets.IndexAssets
local IndexRewards = require(IndexAssets.IndexRewards)

local utils = ReplicatedStorage:WaitForChild("Util")
local IndexUtil = require(utils.IndexUtil)


local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	ClaimIndexMilestone = remotesFolder.Index.ClaimIndexMilestone,
	IndexDataUpdated = remotesFolder.Index.IndexDataUpdated,
	NewWeaponDiscovered = remotesFolder.Index.NewWeaponDiscovered,
	
	-- RFs
	GetIndexData = remotesFolder.Index.GetIndexData,
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type Milestone = IndexRewards.Milestone
type RewardType = IndexRewards.RewardType
type Reward = IndexRewards.Reward

--------------------------------------------------
-- STATE --
--------------------------------------------------
local IndexService = {}
IndexService.Services = {}
IndexService.Signals = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------



function IndexService:ClaimMilestone(player: Player, mutation: string)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[ClaimMilestone] No profile found for player: " .. player.Name) return end
	
	local indexData = profile.Index
	if not indexData then warn("[ClaimMilestone] No index data found for player: " .. player.Name) return end
	
	local rewardTable = IndexRewards[mutation]
	if not rewardTable then warn("[ClaimMilestone] Invalid mutation: " .. mutation) return end
	
	local discovered = indexData.Discovered and indexData.Discovered.Weapons
	if not discovered then 
		self.Services.NotificationService:Error(player, "Not enough discoveries!")
		return
	end
	
	-- count discovered weapons for this mutation
	local count = 0
	for _, weaponMutations in discovered do
		if weaponMutations[mutation] then
			count += 1
		end
	end
	
	indexData.ClaimedMilestones = indexData.ClaimedMilestones or {}
	indexData.ClaimedMilestones[mutation] = indexData.ClaimedMilestones[mutation] or {}
	local claimedMilestones = indexData.ClaimedMilestones[mutation]
	
	-- find current milestone
	for i, milestone: Milestone in rewardTable do
		if not claimedMilestones[i] and count >= milestone.discoveriesRequired then
			claimedMilestones[i] = true
			self:ClaimIndexRewards(player, milestone.rewards)
			
			self.Services.NotificationService:Notify(player, "Claimed!", Color3.fromRGB(212, 0, 255))
			self:SendIndexData(player)
			return
		end
	end
	
	self.Services.NotificationService:Error(player, "Not enough discoveries!")
end

function IndexService:ClaimIndexRewards(player: Player, rewards: {Reward})
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[ClaimIndexReward] No profile found for player: " .. player.Name) return end

	for _, reward in rewards do
		if reward.type == "Dice" then
			self.Services.InventoryService:AddItem(player, reward.diceName, reward.quantity)

		elseif reward.type == "Boost" then
			self.Services.InventoryService:AddItem(player, reward.boostName, reward.quantity)

		elseif reward.type == "Component" then
			self.Services.InventoryService:AddItem(player, reward.componentName, reward.quantity)

		elseif reward.type == "LuckMultiplier" then
			

		elseif reward.type == "MoneyMultiplier" then
			
			
		elseif reward.type == "Currency" then
			if reward.currency == "Money" then
				self.Services.DataService:IncrmentMoney(player, "Money", reward.amount, "Index Reward", false)
			elseif reward.currency == "Dogtags" then
				self.Services.DataService:IncrementDogtags(player, reward.amount, "Index Reward", false)
			else
				warn("[ClaimIndexReward] Unknown currency type:", reward.currency)
			end
			
		elseif reward.type == "BaseLuck" then
			
			
		else
			warn("[ClaimIndexReward] Unhandled reward type:", reward.type)
		end
	end
end
function IndexService:GetPlayerIndexData(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GetPlayerIndexProgress] No profile found for player: " .. player.Name) return end
	return profile.Index or {}
end

function IndexService:SendIndexData(player: Player)
	remotes.IndexDataUpdated:FireClient(player, self:GetPlayerIndexData(player))
end


--------------------------------------------------
-- MAIN --
--------------------------------------------------

function IndexService:Init(services)
	self.Services = services

end

function IndexService:Start()
	
	remotes.GetIndexData.OnServerInvoke = function(player)
		return self:GetPlayerIndexData(player)
	end
	
	remotes.ClaimIndexMilestone.OnServerEvent:Connect(function(player, mutation: string)
		self:ClaimMilestone(player, mutation)
	end)
end


return IndexService