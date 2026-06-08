local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDefinitions = require(ReplicatedStorage.GameAssets.ItemAssets.ItemDefinitions)

function getAllNames(): {string}
	local items = {}
	for itemName, itemDef: ItemDefinitions.ItemDefinition in ItemDefinitions do
		table.insert(items, itemName)
	end
	return items
end

return {
	Name = "giveItem";
	Aliases = {};
	Description = "Give a item.";
	Group = "DefaultAdmin";
	Args = {
		{
			Type = "player",
			Name = "player",
			Description = "Player to give item to.",
		},
		function(context)
			return {
				Type = context.Cmdr.Util.MakeEnumType("Item", getAllNames()),
				Name = "Item";
				Description = "Item to give.";
				Optional = false;
			}
		end,
		function(context)
			return {
				Type = "number",
				Name = "quantity";
				Description = "Amount to give.";
				Optional = true;
			}
		end
	};
}
