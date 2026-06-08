local ServerScriptService = game:GetService("ServerScriptService")
local InventoryService = require(ServerScriptService.ServerMain.Services.InventoryService)

return function (context, recipient: Player, itemName: string, quantity: number)
	if InventoryService:AddItem(recipient, itemName, quantity) then
		return `Gave {quantity} of {itemName} for {recipient.Name}.`
	end
	return `Failed to give {quantity} of {itemName} for {recipient.Name}.`
end
