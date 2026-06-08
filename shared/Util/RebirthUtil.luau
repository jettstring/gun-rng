local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local RebirthAssets = GameAssets:WaitForChild("RebirthAssets")
local RebirthRewards = require(RebirthAssets:WaitForChild("RebirthRewards"))

--------------------------------------------------
-- TYPES -- 
-----------------------------		---------------------


type RebirthReward = RebirthRewards.RebirthReward

local RebirthUtil = {}

function RebirthUtil.GetRequiredDogtags(rebirths: number): number
	return math.round(100 * 2 ^ (rebirths - 1))
end

function RebirthUtil.GetRebirthLuck(rebirths: number): number
	local amount  = 1 * 2 ^ ((rebirths) * 1.45)
	return  math.round(1 * 2 ^ (rebirths * 1.45) * 100) / 100 -- rounded 2 decimals
end

function RebirthUtil.GetRebirthRewards(rebirths: number): {RebirthReward}?
	return RebirthRewards[rebirths]
end

function RebirthUtil.OwnsRebirthReward(rebirths: number, rewardName: string): boolean
	for rebirthLevel, rewardsData in RebirthRewards do
		if rebirths >= rebirthLevel and rewardsData[rewardName] then
			return true
		end
	end

	return false
end

return RebirthUtil
