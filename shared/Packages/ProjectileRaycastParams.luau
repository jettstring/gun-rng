local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ProjectileRaycastParams = {}

local SHOOT_IGNORE = workspace:WaitForChild("RAY_IGNORE")
local IGNORE_TAG_NAME = "Ignore"
local PLAYER_IGNORE_TAG_PREFIX = "Ignore-"

local function appendIfPresent(instances: {Instance}, instance: Instance?)
	if instance then
		table.insert(instances, instance)
	end
end

function ProjectileRaycastParams.newOutsideParams(
	shootPart: Instance?,
	ignoreCharacter: Instance?,
	player: Player?
): RaycastParams
	local raycastParams = RaycastParams.new() :: RaycastParams
	local excludeInstances: {Instance} = {}

	appendIfPresent(excludeInstances, shootPart)
	appendIfPresent(excludeInstances, SHOOT_IGNORE)
	appendIfPresent(excludeInstances, Workspace:FindFirstChild("VecViz"))
	appendIfPresent(excludeInstances, ignoreCharacter)

	-- Assigning ExcludeInstances sets both the filter list and Exclude mode.
	raycastParams.ExcludeInstances = excludeInstances
	raycastParams:AddToFilter(CollectionService:GetTagged(IGNORE_TAG_NAME))
	if player then
		raycastParams:AddToFilter(CollectionService:GetTagged(`{PLAYER_IGNORE_TAG_PREFIX}{player.Name}`))
	end
	raycastParams:AddToFilter(CollectionService:GetTagged("Player"))

	return raycastParams
end

return ProjectileRaycastParams
