-- Server-authoritative damage-over-time ("linger") manager.
--
-- Applied from Projectile:hit() when the ammo type has a `linger` config
-- (AmmoTypes.getLinger). Each tick deals a fraction of the bullet's hit damage
-- to the agent Humanoid; the replicated Health change drives the owning client's
-- health bar/flash for free (see EnemyRenderController.onAgentHealthChanged).
--
-- Per tick we also fire the existing GunKit.HitLog to the owner so the burn
-- triggers the hitmarker GUI + sound + rising damage counter, exactly like a
-- normal shot. A single Enemy.LingerEffect remote (fired on ignite AND refresh,
-- carrying the duration) tells the client to attach/extend the fire visual; the
-- client self-terminates from that duration, so there is no Stop event.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local enemyRemotes = remotesFolder:WaitForChild("Enemy")
local gunKitRemotes = remotesFolder:WaitForChild("GunKit")
local lingerEffectEvent = enemyRemotes:WaitForChild("LingerEffect")
local hitLogEvent = gunKitRemotes:WaitForChild("HitLog")

local ENEMY_TAG_PREFIX = "Enemy-"

type LingerConfig = AmmoTypes.LingerConfig

type LingerEntry = {
	expireTime: number,
	hitDamage: number,
	thread: thread?,
}

local LingerEffect = {}

-- Keyed by Humanoid so re-hits refresh instead of stacking; nested by ammo type
-- so different lingering effects (fire, future poison) coexist. Weak keys are a
-- safety net in case an enemy vanishes without its loop cleaning up.
local activeLingers: {[Humanoid]: {[string]: LingerEntry}} = setmetatable({}, { __mode = "k" }) :: any

-- Mirrors Projectile.canDamageTaggedEnemy: damageable if owned by this player, or
-- if it carries no owner tag at all (neutral targets). Keeps the per-tick check
-- consistent with the hit that started the burn.
local function canDamage(player: Player, agentModel: Model): boolean
	local hasOwnerTag = false
	local expectedTag = `{ENEMY_TAG_PREFIX}{player.Name}`

	for _, tag in CollectionService:GetTags(agentModel) do
		if string.sub(tag, 1, #ENEMY_TAG_PREFIX) ~= ENEMY_TAG_PREFIX then
			continue
		end

		hasOwnerTag = true
		if tag == expectedTag then
			return true
		end
	end

	return not hasOwnerTag
end

local function getEnemyPosition(humanoid: Humanoid, agentModel: Model): Vector3
	local rootPart = humanoid.RootPart
	if rootPart then
		return rootPart.Position
	end

	return agentModel:GetPivot().Position
end

local function clearEntry(humanoid: Humanoid, ammoType: string, entry: LingerEntry)
	local lingers = activeLingers[humanoid]
	if lingers and lingers[ammoType] == entry then
		lingers[ammoType] = nil
		if next(lingers) == nil then
			activeLingers[humanoid] = nil
		end
	end
end

function LingerEffect.apply(
	player: Player?,
	agentModel: Model,
	humanoid: Humanoid,
	ammoType: string,
	config: LingerConfig,
	hitDamage: number
)
	if not RunService:IsServer() then
		return
	end
	if not player or not agentModel or not humanoid then
		return
	end
	if humanoid.Health <= 0 or hitDamage <= 0 then
		return
	end

	local lingersForHumanoid = activeLingers[humanoid]
	if not lingersForHumanoid then
		lingersForHumanoid = {}
		activeLingers[humanoid] = lingersForHumanoid
	end

	local now = os.clock()
	local existing = lingersForHumanoid[ammoType]
	if existing then
		-- Refresh: extend the burn and update the damage basis; the running loop
		-- reads these fields, so no new thread is spawned. Re-tell the client so
		-- it extends its (duration-bounded) visual too.
		existing.expireTime = now + config.duration
		existing.hitDamage = hitDamage
		if player.Parent then
			lingerEffectEvent:FireClient(player, agentModel, ammoType, config.duration)
		end
		return
	end

	local entry: LingerEntry = {
		expireTime = now + config.duration,
		hitDamage = hitDamage,
	}
	lingersForHumanoid[ammoType] = entry

	if player.Parent then
		lingerEffectEvent:FireClient(player, agentModel, ammoType, config.duration)
	end

	entry.thread = task.spawn(function()
		while true do
			task.wait(config.tickInterval)

			-- End the burn when its time is up, the enemy died/despawned, or it is
			-- no longer this player's enemy.
			if os.clock() >= entry.expireTime
				or humanoid.Health <= 0
				or not agentModel.Parent
				or not canDamage(player, agentModel)
			then
				break
			end

			-- Pause damage (but keep the timer running) while invulnerable.
			if not agentModel:HasTag("Invulnerable") then
				local tickDamage = entry.hitDamage * config.tickPercentOfHit
				if tickDamage > 0 then
					humanoid:TakeDamage(tickDamage)

					if player.Parent then
						local enemyPos = getEnemyPosition(humanoid, agentModel)
						hitLogEvent:FireClient(
							player,
							agentModel.Name,
							enemyPos,
							enemyPos,
							tickDamage,
							1,
							false,
							true,
							agentModel:GetAttribute("id")
						)
					end
				end
			end
		end

		clearEntry(humanoid, ammoType, entry)
	end)
end

return LingerEffect
