local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)
local DataService = require(ServerScriptService.ServerMain.Services.DataService)
local InventoryService = require(ServerScriptService.ServerMain.Services.InventoryService)

type IncrementTarget = string

local CURRENCY_INCREMENTERS = {
	Money = function(player: Player, amount: number): string
		return DataService:IncrementMoney(player, amount, "Admin")
	end,
	Rolls = function(player: Player, amount: number): string
		return DataService:IncrementRolls(player, amount, "Admin")
	end,
	Dogtags = function(player: Player, amount: number): string
		return DataService:IncrementDogtags(player, amount, "Admin")
	end,
}

return function(_context, targetPlayer: Player, specifiedTarget: IncrementTarget, amount: number)
	local profile = DataService.Profiles[targetPlayer]
	if not profile then
		return "Profile not found for " .. targetPlayer.Name
	end

	local incrementCurrency = CURRENCY_INCREMENTERS[specifiedTarget]
	if incrementCurrency then
		return incrementCurrency(targetPlayer, amount)
	end

	if AmmoTypes.isConsumable(specifiedTarget) then
		local total = math.floor(amount)
		if total < 1 then
			return "Amount must be at least 1 for ammo."
		end

		local remaining = total
		while remaining > 0 do
			local chunk = math.min(99, remaining)
			InventoryService:AddItem(targetPlayer, specifiedTarget, chunk)
			remaining -= chunk
		end

		local newAmount = profile.Data.Inventory.Items[specifiedTarget] or 0
		return `{targetPlayer.Name} now has {newAmount} {specifiedTarget} ammo.`
	end

	return "Increment target not found for " .. specifiedTarget
end
