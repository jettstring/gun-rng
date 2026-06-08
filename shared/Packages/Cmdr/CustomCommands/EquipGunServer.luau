local ServerScriptService = game:GetService("ServerScriptService")
local InventoryService = require(ServerScriptService.ServerMain.Services.InventoryService)

return function (context, gun: string, player: Player)
	local weaponKey = InventoryService:AddWeapon(player, {
		weaponName = gun,
		mutation = nil, -- TODO: refactor to read mutation table
	})
	if not weaponKey then
		return `Failed to give {gun} to {player.Name}.`
	end

	if not InventoryService:EquipWeapon(player, weaponKey) then
		return `Added {gun} to {player.Name}, but failed to equip it.`
	end

	return `Gave and equipped {gun} for {player.Name}.`
end
