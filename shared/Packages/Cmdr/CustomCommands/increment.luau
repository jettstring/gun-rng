local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)

local INCREMENT_TARGETS = {
	"Money",
	"Research",
	"Dogtags",
}

for _, ammoType in AmmoTypes.Consumable do
	table.insert(INCREMENT_TARGETS, ammoType)
end

return {
	Name = "increment";
	Aliases = {};
	Description = "Increments a currency or ammo value.";
	Group = "DefaultAdmin";
	Args = {
		{
			Type = "player";
			Name = "Target";
			Description = "The player to get data for.";
		},
		function(context)
			return {
				Type = context.Cmdr.Util.MakeEnumType("Increment Target", INCREMENT_TARGETS),
				Name = "target";
				Description = "Currency or ammo type to increment.";
				Optional = false;
			}
		end,
		{
			Type = "number";
			Name = "amount";
			Description = "Amount to add.";
			Optional = false;
		},
	};
}
