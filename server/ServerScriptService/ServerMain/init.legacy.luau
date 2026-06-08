local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = script:WaitForChild("Services")

local loadOrder = {
	{"DataService", require(Services.DataService) },
	{"ZoneService", require(Services.ZoneService) },
	{"UpgradeService", require(Services.UpgradeService) },
	{"CharacterService", require(Services.CharacterService) },
	{"RollService", require(Services.RollService) },
	{"GunService", require(Services.GunService) },
	{"EnemyService", require(Services.EnemyService) },
	{"InventoryService", require(Services.InventoryService) },
	{"NotificationService", require(Services.NotificationService) },
	{"CustomAnalyticsService", require(Services.CustomAnalyticsService) },
	{"RebirthService", require(Services.RebirthService) },
	{"IndexService", require(Services.IndexService) },
}

-- Build named lookup
local services = {}
for _, entry in ipairs(loadOrder) do
	services[entry[1]] = entry[2]
end

-- Init all (ordered)
for _, entry in ipairs(loadOrder) do
	local ok, err = pcall(function()
		entry[2]:Init(services)
	end)
	if not ok then
		warn(string.format("[ServerMain] %s:Init failed: %s", entry[1], tostring(err)))
	end
end

-- Start all (ordered)
for _, entry in ipairs(loadOrder) do
	local ok, err = pcall(function()
		entry[2]:Start()
	end)
	if not ok then
		warn(string.format("[ServerMain] %s:Start failed: %s", entry[1], tostring(err)))
	end
end


local Cmdr = require(ReplicatedStorage.Packages.Cmdr)
Cmdr:RegisterDefaultCommands()
Cmdr:RegisterCommandsIn(ReplicatedStorage.Packages.Cmdr.CustomCommands)
Cmdr:RegisterHooksIn(ReplicatedStorage.Packages.Cmdr.Hooks)
