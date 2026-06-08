-- Owner-only "linger" effects (incendiary fire, future poison, ...).
--
-- The server fires Enemy.LingerEffect (on ignite AND refresh) with the agent
-- model, the ammo type, and the burn duration. We clone the matching "Linger"
-- part from that ammo type's projectile asset folder, hand it to
-- EnemyRenderController so it rides the visible enemy rig, and pulse its particle
-- emitters + sounds every tick. There is no Stop event: we self-terminate when
-- the duration elapses, the agent despawns, or the agent dies.
--
-- Effects are inherently private: the server only :FireClient's the bullet's
-- owner, and only that client renders the enemy rig the fire attaches to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local enemyRemotes = remotesFolder:WaitForChild("Enemy")
local remotes = {
	LingerEffect = enemyRemotes:WaitForChild("LingerEffect") :: RemoteEvent,
}

local ProjectileAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("ProjectileAssets"):WaitForChild("Bullets")

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type EmitterRecord = {
	emitter: ParticleEmitter,
	originalRate: number,
}

type LingerState = {
	part: Instance?,
	emitters: { EmitterRecord },
	sounds: { Sound },
	expireTime: number,
	thread: thread?,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------

local LingerEffectsController = {}
LingerEffectsController.Controllers = {}
LingerEffectsController.Signals = {}
LingerEffectsController.lingerConnection = nil :: RBXScriptConnection?
LingerEffectsController.destroyingConnection = nil :: RBXScriptConnection?

-- {[Model]: {[ammoType: string]: LingerState}} keyed by the agent model. Weak keys
-- so a despawned enemy can never pin this table even if a loop misses cleanup.
local active = setmetatable({}, { __mode = "k" }) :: any

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local LINGER_CHILD_NAME = "Linger"
local DEFAULT_TICK_INTERVAL = 0.5

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function getLingerTemplate(ammoType: string): Instance?
	local typeFolder = ProjectileAssets:FindFirstChild(ammoType)
	if not typeFolder then
		warn(`[LingerEffectsController] Missing projectile folder "{ammoType}".`)
		return nil
	end

	local lingerTemplate = typeFolder:FindFirstChild(LINGER_CHILD_NAME)
	if not lingerTemplate then
		warn(`[LingerEffectsController] Projectile folder "{ammoType}" is missing a "{LINGER_CHILD_NAME}" child.`)
		return nil
	end

	return lingerTemplate
end

-- Snapshot each emitter's Rate, then zero the live Rate so the effect is
-- burst-only: we :Emit(originalRate) per tick instead of streaming continuously.
-- Mirrors ProjectileVisualization's impact-effect convention.
local function collectEmittersAndSounds(part: Instance): ({ EmitterRecord }, { Sound })
	local emitters: { EmitterRecord } = {}
	local sounds: { Sound } = {}

	for _, descendant in part:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			table.insert(emitters, { emitter = descendant, originalRate = descendant.Rate })
			descendant.Rate = 0
		elseif descendant:IsA("Sound") then
			table.insert(sounds, descendant)
		end
	end

	return emitters, sounds
end

local function pulse(state: LingerState)
	for _, record in state.emitters do
		record.emitter:Emit(record.originalRate)
	end
	for _, sound in state.sounds do
		sound:Play()
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function LingerEffectsController:Clear(agentModel: Model, ammoType: string, state: LingerState)
	local lingers = active[agentModel]
	if lingers and lingers[ammoType] == state then
		lingers[ammoType] = nil
		if next(lingers) == nil then
			active[agentModel] = nil
		end
	end

	if state.part then
		state.part:Destroy()
		state.part = nil
	end
end

function LingerEffectsController:OnLingerEffect(agentModel: Model, ammoType: string, duration: number)
	if typeof(agentModel) ~= "Instance" or not agentModel:IsA("Model") then
		return
	end
	if typeof(ammoType) ~= "string" or typeof(duration) ~= "number" then
		return
	end

	-- Refresh an already-burning effect of the same type: just extend its life.
	local lingers = active[agentModel]
	if lingers and lingers[ammoType] then
		lingers[ammoType].expireTime = os.clock() + duration
		return
	end

	local lingerTemplate = getLingerTemplate(ammoType)
	if not lingerTemplate then
		return
	end

	local config = AmmoTypes.getLinger(ammoType)
	local tickInterval = if config then config.tickInterval else DEFAULT_TICK_INTERVAL

	local part = lingerTemplate:Clone()
	local emitters, sounds = collectEmittersAndSounds(part)
	local humanoid = agentModel:FindFirstChildOfClass("Humanoid")

	local state: LingerState = {
		part = part,
		emitters = emitters,
		sounds = sounds,
		expireTime = os.clock() + duration,
		thread = nil,
	}

	if not lingers then
		lingers = {}
		active[agentModel] = lingers
	end
	lingers[ammoType] = state

	-- Hand the part to the rig owner so it follows the visible enemy. If the rig
	-- isn't built yet, EnemyRenderController queues and attaches it on build.
	local enemyRender = self.Controllers.EnemyRenderController
	if enemyRender then
		enemyRender:AttachFollower(agentModel, part)
	end

	pulse(state) -- immediate ignition burst

	state.thread = task.spawn(function()
		while true do
			task.wait(tickInterval)

			if os.clock() >= state.expireTime
				or agentModel.Parent == nil
				or (humanoid ~= nil and humanoid.Health <= 0)
			then
				break
			end

			pulse(state)
		end

		self:Clear(agentModel, ammoType, state)
	end)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function LingerEffectsController:Init(controllers)
	self.Controllers = controllers
end

function LingerEffectsController:Start()
	if self.lingerConnection then
		self.lingerConnection:Disconnect()
		self.lingerConnection = nil
	end

	self.lingerConnection = remotes.LingerEffect.OnClientEvent:Connect(function(agentModel, ammoType, duration)
		self:OnLingerEffect(agentModel, ammoType, duration)
	end)

	if not self.destroyingConnection then
		self.destroyingConnection = script.Destroying:Connect(function()
			if self.lingerConnection then
				self.lingerConnection:Disconnect()
				self.lingerConnection = nil
			end

			for agentModel, lingers in active do
				for ammoType, state in lingers do
					if state.thread then
						task.cancel(state.thread)
					end
					if state.part then
						state.part:Destroy()
					end
					lingers[ammoType] = nil
				end
				active[agentModel] = nil
			end

			if self.destroyingConnection then
				self.destroyingConnection:Disconnect()
				self.destroyingConnection = nil
			end
		end)
	end
end

return LingerEffectsController
