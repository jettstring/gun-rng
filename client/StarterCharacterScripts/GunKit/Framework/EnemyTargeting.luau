local CollectionService = game:GetService("CollectionService")

local module = {}

local ENEMY_OWNER_TAG_PREFIX = "Enemy-"
local AUTO_AIM_DISTANCE_TIE_EPSILON = 1e-3

type Connection = RBXScriptConnection

export type EnemyTagCache = {
	tag: string,
	refCount: number,
	enemyModels: { Model },
	enemyModelIndices: { [Model]: number },
	connections: { Connection },
}

export type TargetResult = {
	aimPoint: Vector3,
	enemy: Model,
	humanoid: Humanoid,
	aimPart: BasePart,
	isHeadshot: boolean,
	distanceSquared: number,
}

export type TargetOptions = {
	ownerTag: string,
	originPosition: Vector3,
	maxDistanceSquared: number?,
	currentTarget: Model?,
	getAimPart: (Model) -> (BasePart?, boolean),
	getTargetScore: ((TargetResult) -> number)?,
}

local enemyTagCaches: { [string]: EnemyTagCache } = {}

local function addEnemyToCache(cache: EnemyTagCache, instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	if cache.enemyModelIndices[instance] then
		return
	end

	table.insert(cache.enemyModels, instance)
	cache.enemyModelIndices[instance] = #cache.enemyModels
end

function module.removeFromCache(cache: EnemyTagCache, instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local index = cache.enemyModelIndices[instance]
	if not index then
		return
	end

	local lastEnemy = cache.enemyModels[#cache.enemyModels]
	cache.enemyModels[index] = lastEnemy
	cache.enemyModels[#cache.enemyModels] = nil
	cache.enemyModelIndices[instance] = nil
	if lastEnemy and lastEnemy ~= instance then
		cache.enemyModelIndices[lastEnemy] = index
	end
end

function module.getOwnerTag(player: Player): string
	return `{ENEMY_OWNER_TAG_PREFIX}{player.Name}`
end

function module.acquireCache(tag: string): EnemyTagCache
	local cache = enemyTagCaches[tag]
	if cache then
		cache.refCount += 1
		return cache
	end

	cache = {
		tag = tag,
		refCount = 1,
		enemyModels = {},
		enemyModelIndices = {},
		connections = {},
	}
	enemyTagCaches[tag] = cache

	for _, instance in CollectionService:GetTagged(tag) do
		addEnemyToCache(cache, instance)
	end

	table.insert(cache.connections, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		addEnemyToCache(cache, instance)
	end))
	table.insert(cache.connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		module.removeFromCache(cache, instance)
	end))

	return cache
end

function module.releaseCache(cache: EnemyTagCache?)
	if not cache then
		return
	end

	cache.refCount -= 1
	if cache.refCount > 0 then
		return
	end

	for _, connection in cache.connections do
		connection:Disconnect()
	end

	enemyTagCaches[cache.tag] = nil
end

function module.isOwnedEnemy(enemyModel: Model, ownerTag: string): boolean
	if not CollectionService:HasTag(enemyModel, ownerTag) then
		return false
	end

	for _, tag in CollectionService:GetTags(enemyModel) do
		if string.sub(tag, 1, #ENEMY_OWNER_TAG_PREFIX) == ENEMY_OWNER_TAG_PREFIX and tag ~= ownerTag then
			return false
		end
	end

	return true
end

function module.getAliveHumanoid(enemyModel: Model): Humanoid?
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
		return nil
	end

	return humanoid
end

function module.findFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function module.getHumanoidRootPart(enemyModel: Model): BasePart?
	local humanoidRootPart = enemyModel:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return nil
end

function module.getHeadPart(enemyModel: Model): BasePart?
	local head = enemyModel:FindFirstChild("Head")
	if head and head.Parent == enemyModel and head:IsA("BasePart") then
		return head
	end

	return nil
end

function module.getGunAimPart(enemyModel: Model): BasePart?
	return module.getHumanoidRootPart(enemyModel)
		or enemyModel.PrimaryPart
		or module.getHeadPart(enemyModel)
		or module.findFirstBasePart(enemyModel)
end

function module.getPrimaryPartFirstAimPart(enemyModel: Model): BasePart?
	return enemyModel.PrimaryPart
		or module.getHumanoidRootPart(enemyModel)
		or module.getHeadPart(enemyModel)
		or module.findFirstBasePart(enemyModel)
end

function module.getValidTarget(enemy: Model?, options: TargetOptions): TargetResult?
	if not enemy or not enemy.Parent then
		return nil
	end

	if not module.isOwnedEnemy(enemy, options.ownerTag) then
		return nil
	end

	local humanoid = module.getAliveHumanoid(enemy)
	if not humanoid then
		return nil
	end

	local aimPart, isHeadshot = options.getAimPart(enemy)
	if not aimPart then
		return nil
	end

	local aimPoint = aimPart.Position
	local offset = aimPoint - options.originPosition
	local distanceSquared = offset:Dot(offset)
	if options.maxDistanceSquared and distanceSquared > options.maxDistanceSquared then
		return nil
	end

	return {
		aimPoint = aimPoint,
		enemy = enemy,
		humanoid = humanoid,
		aimPart = aimPart,
		isHeadshot = isHeadshot == true,
		distanceSquared = distanceSquared,
	}
end

function module.selectTarget(cache: EnemyTagCache?, options: TargetOptions): TargetResult?
	if not cache then
		return nil
	end

	local currentResult = module.getValidTarget(options.currentTarget, options)
	if currentResult then
		return currentResult
	end

	local bestResult: TargetResult? = nil
	local bestDistanceSquared = math.huge
	local bestScore = math.huge
	local bestHealth = math.huge
	local index = 1

	while index <= #cache.enemyModels do
		local enemy = cache.enemyModels[index]
		if not enemy.Parent or not CollectionService:HasTag(enemy, cache.tag) then
			module.removeFromCache(cache, enemy)
			continue
		end

		local result = module.getValidTarget(enemy, options)
		if result then
			local health = result.humanoid.Health
			local targetScore = if options.getTargetScore then options.getTargetScore(result) else nil
			if targetScore then
				local isBetterScore = targetScore < bestScore - AUTO_AIM_DISTANCE_TIE_EPSILON
				local scoreDelta = math.abs(targetScore - bestScore)
				local isSameScoreLowerHealth = scoreDelta <= AUTO_AIM_DISTANCE_TIE_EPSILON and health < bestHealth
				if isBetterScore or isSameScoreLowerHealth then
					bestResult = result
					bestScore = targetScore
					bestDistanceSquared = result.distanceSquared
					bestHealth = health
				end
			else
				local isCloser = result.distanceSquared < bestDistanceSquared - AUTO_AIM_DISTANCE_TIE_EPSILON
				local distanceDelta = math.abs(result.distanceSquared - bestDistanceSquared)
				local isSameDistanceLowerHealth = distanceDelta <= AUTO_AIM_DISTANCE_TIE_EPSILON and health < bestHealth
				if isCloser or isSameDistanceLowerHealth then
					bestResult = result
					bestDistanceSquared = result.distanceSquared
					bestHealth = health
				end
			end
		end

		index += 1
	end

	return bestResult
end

return module
