local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local IndexAssets = GameAssets:WaitForChild("IndexAssets")
local IndexRewards = require(IndexAssets.IndexRewards)
local RewardTypeMetadata = require(IndexAssets.RewardTypeMetadata)
local ItemDefinitions = require(GameAssets.ItemAssets.ItemDefinitions)

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type Milestone = IndexRewards.Milestone
type Reward = IndexRewards.Reward

local IndexUtil = {}


function IndexUtil.getRewardDisplay(reward: Reward): {rewardIcon: string, amountLabel: string, description: string}
	if reward.type == "LuckMultiplier" then
		local data = RewardTypeMetadata.LuckMultiplier
		local percent = math.round(reward.multiplier * 100)
		
		return {
			rewardIcon = data.icon,
			amountLabel = string.format(data.labelFormat, percent),
			description = string.format(data.descriptionFormat, percent),
		}
	elseif reward.type == "MoneyMultiplier" then
		local data = RewardTypeMetadata.LuckMultiplier
		local percent = math.round(reward.multiplier * 100)

		return {
			rewardIcon = data.icon,
			amountLabel = string.format(data.labelFormat, percent),
			description = string.format(data.descriptionFormat, percent),
		}
	elseif reward.type == "BaseLuck" then
		local data = RewardTypeMetadata.LuckMultiplier
		
		return {
			rewardIcon = data.icon,
			amountLabel = string.format(data.labelFormat, reward.amount),
			description = string.format(data.descriptionFormat, reward.amount),
		}
	elseif reward.type == "Dice" then
		local def: ItemDefinitions.DiceDefinition = ItemDefinitions[reward.diceName]
		
		return {
			rewardIcon = def.displayImage,
			amountLabel = string.format("x%d", reward.quantity),
			description = def.itemDescription,
		}
	elseif reward.type == "Boost" then
		local def: ItemDefinitions.BoostDefinition = ItemDefinitions[reward.boostName]
		local duration = def.duration or 0
		local minutes = math.floor(duration / 60)
		
		return {
			rewardIcon = def.displayImage,
			amountLabel = string.format("x%d", reward.quantity),
			description = string.format(def.itemDescription, (minutes > 0 and minutes) or duration),
		}
	end
end

return IndexUtil
