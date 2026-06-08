local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.WeaponDefinitions)

function getAllNames(): {string}
	local results: {{name: string, order: number}} = {}

	for name: string, data in pairs(WeaponDefinitions) do
		table.insert(results, {name = name, order = data.odds or 0})
	end

	table.sort(results, function(a, b)
		if a.order == b.order then
			return a.name > b.name
		end

		return a.order > b.order
	end)

	local sortedNames: {string} = {}
	for _, entry in ipairs(results) do
		table.insert(sortedNames, entry.name)
	end

	return sortedNames
end
return {
	Name = "givegun";
	Aliases = {};
	Description = "Give a gun.";
	Group = "DefaultAdmin";
	Args = {
		function(context)
			return {
				Type = context.Cmdr.Util.MakeEnumType("Gun", getAllNames()),
				Name = "Gun";
				Description = "Gun to give.";
			}
		end,
		function(context)
			return {
				Type = "player",
				Name = "player";
				Description = "The player to reset the data of.";
				Default = context.Executor
			}
		end
	};
}
