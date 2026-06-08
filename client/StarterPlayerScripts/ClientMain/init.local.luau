local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Controllers = script:WaitForChild("Controllers")

local loadOrder = {
	{"RollController", require(Controllers.RollController) },
	{"SkillTreeController", require(Controllers.SkillTreeController) },
	{"UIController", require(Controllers.UIController) },
	{"TeleportController", require(Controllers.TeleportController) },
	{"ZoneController", require(Controllers.ZoneController) },
	{"MagnetRadiusVisualizer", require(Controllers.MagnetRadiusVisualizer) },
	{"ProjectileVisualization", require(Controllers.ProjectileVisualization), },
	{"EnemyEffects", require(Controllers.EnemyEffects) },
	{"EnemyRenderController", require(Controllers.EnemyRenderController) },
	{"LingerEffectsController", require(Controllers.LingerEffectsController) },
	{"InventoryController", require(Controllers.InventoryController) },
	{"NotificationController", require(Controllers.NotificationController) },
	{"StatusDisplay", require(Controllers.StatusDisplay) },
	{"RebirthController", require(Controllers.RebirthController) },
	{"IndexController", require(Controllers.IndexController) },
}

-- Build named lookup
local controllers = {}
for _, entry in ipairs(loadOrder) do
	controllers[entry[1]] = entry[2]
end

-- Init all
for _, entry in ipairs(loadOrder) do
	local ok, err = pcall(function()
		entry[2]:Init(controllers)
	end)
	if not ok then
		warn(string.format("[ClientMain] %s:Init failed: %s", entry[1], tostring(err)))
	end
end

-- Start all
for _, entry in ipairs(loadOrder) do
	local ok, err = pcall(function()
		entry[2]:Start()
	end)
	if not ok then
		warn(string.format("[ClientMain] %s:Start failed: %s", entry[1], tostring(err)))
	end
end


local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))
CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 , Enum.KeyCode.Semicolon})
