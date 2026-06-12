local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

local ServerLuckUtil = {}

local PURCHASABLE_MULTIPLIERS = { 2, 4, 8 }

function ServerLuckUtil.getPurchasableMultipliers(): { number }
	return PURCHASABLE_MULTIPLIERS
end

function ServerLuckUtil.getLuckProductKey(luckMultiplier: number): string
	return string.format("%dX_SERVER_LUCK", luckMultiplier)
end


return ServerLuckUtil
