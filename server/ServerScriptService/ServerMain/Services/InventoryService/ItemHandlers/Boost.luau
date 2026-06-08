local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	BoostsUpdated = remotesFolder.Boosts:WaitForChild("BoostsUpdated"),
}

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets.ItemDefinitions)

type BoostDefinition = ItemDefinitions.BoostDefinition

local Boost = {}

function Boost.Use(player, services, boostName)
	local boostDef: BoostDefinition = ItemDefinitions[boostName]
	if not boostDef then
		warn("Invalid boost name:", boostName)
		return false
	end
	
	local InventoryService = services.InventoryService
	InventoryService.ActiveBoosts[player] = InventoryService.ActiveBoosts[player] or {}
	local playerBoosts = InventoryService.ActiveBoosts[player]
	playerBoosts[boostDef.boostType] = playerBoosts[boostDef.boostType] or {}

	local existing = playerBoosts[boostDef.boostType][boostName]
	local now = os.time()

	if existing and existing.endTime > now then
		-- Stack: extend from current endTime
		existing.endTime += boostDef.duration
	else
		-- Fresh or expired: start from now
		playerBoosts[boostDef.boostType][boostName] = {
			endTime = now + boostDef.duration,
		}
	end
	
	-- Update player luck
	if boostDef.boostType == "Luck" then
		services.RollService:SendUpdatedLuck(player)
	end
	
	-- Fire to client
	remotes.BoostsUpdated:FireClient(player, playerBoosts)
	
	print("Boost used:", boostName, "Active Boosts:", playerBoosts)

	return true 
end

return Boost