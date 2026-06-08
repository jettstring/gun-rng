return {
	Name = "datareset";
	Aliases = {};
	Description = "WARNING: Resets profile data for a player.";
	Group = "Admin";
	Args = {
		function(context)
			return {
				Type = context.Cmdr.Util.MakeEnumType("Data Category", {"dev", "all", "upgrades", "zone", "ammo"}),
				Name = "category";
				Description = "The category of data to reset.";
				Default = "dev";
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
