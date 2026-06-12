local ReplicatedStorage = game:GetService("ReplicatedStorage")

local utils = ReplicatedStorage.Util
local ServerLuckUtil = require(utils.ServerLuckUtil)


export type MonetizedProduct = {
	id: number,
	giftId: number?, -- optional gift id
	isPass: boolean,
	oneTimePurchase: boolean?, -- one time purchase dev product
	isPaidRandomItem: boolean?, -- random paid item
}

export type PayerInfo = {
	paidRandomItemsRestricted: boolean,
	segmentsFetched: boolean,
	activePayerStatus: Enum.ActivePayerStatus,
	whenUserFirstPlayed: Enum.WhenUserFirstPlayed,
	platformSpenderStatus: Enum.PlayerPlatformSpenderStatus,
}

local Products = {
	-- GAMEPASSES --
	
	-- PRODUCTS -- 
	
	
	-- JACKPOT PACKS
	["JackpotPack1"] = {
		id = 3604203539,
		giftId = nil,
		isPass = false,
		oneTimePurchase = false,
		isPaidRandomItem = true,
	} :: MonetizedProduct,
		
	["JackpotPack2"] = {
		id = 3604203629,
		giftId = nil,
		isPass = false,
		oneTimePurchase = false,
		isPaidRandomItem = true,
	} :: MonetizedProduct,
		
	["JackpotPack3"] = {
		id = 3604203687,
		giftId = nil,
		isPass = false,
		oneTimePurchase = false,
		isPaidRandomItem = true,
	} :: MonetizedProduct,
	
}

-- add server luck products

local SERVER_LUCK_IDS = {
	[2] = 3604204270,
	[4] = 3604204306,
	[8] = 3604204336,
}
for _, multiplier in ServerLuckUtil.getPurchasableMultipliers() do
	Products[string.format("%dXServerLuck", multiplier)] = {
		id = SERVER_LUCK_IDS[multiplier],
	}
end

return Products
