-- Owner-only visual rigs for the local player's enemies.
--
-- The server spawns a lightweight, invisible "agent" (Humanoid + a hitbox + head,
-- fully anchored) and moves it. Only the owning client renders it: we clone the
-- full visual rig from ReplicatedStorage, follow the agent's root each frame, and
-- attach the Highlight + health bar locally. Non-owners do nothing (their
-- owner-tag listener never fires), so each client only ever builds its own ~enemyCap
-- rigs instead of receiving everyone's.
--
-- Death/damage are driven off the agent Humanoid's *Health* (replicated), NOT
-- Humanoid.Died: the agent is fully anchored, so on the client its state machine
-- never steps and Died never fires. Health <= 0 means dead -> sound + ragdoll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local EnemyDefinitions = require(ReplicatedStorage.GameAssets.EnemyAssets.EnemyDefinitions)
local Gigantix = require(ReplicatedStorage.Packages.Gigantix)

local player = Players.LocalPlayer

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local EnemyAssets = GameAssets:WaitForChild("EnemyAssets")
local EnemySounds = EnemyAssets:WaitForChild("EnemySounds")
local DeathSoundTemplate = EnemySounds:WaitForChild("Death") :: Sound
local HealthBillboardGuiTemplate = EnemyAssets:WaitForChild("HealthBillboardGui")

--------------------------------------------------
-- STATE --
--------------------------------------------------
local EnemyRenderController = {}
EnemyRenderController.Controllers = {}
EnemyRenderController.Signals = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

local OWNER_TAG_PREFIX = "Enemy-"
local DEATH_SOUND_CLEANUP_PADDING = 2
local DEATH_SOUND_FALLBACK_LIFETIME = 10
local AGENT_ROOT_WAIT_TIMEOUT = 5
-- Higher = the visual rig snaps to the agent faster. The agent moves at the
-- server tick rate; lerping toward its (replicated) root smooths that to 60fps.
local FOLLOW_SMOOTHING = 18

-- On death the rig is detached and ragdolled (every joint dropped). It collides as
-- an Enemy so the corpse rests on the floor without shoving the player, then Debris
-- removes it after this many seconds.
local RAGDOLL_LIFETIME = 3
local RAGDOLL_COLLISION_GROUP = "Enemy"

local HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 255, 255)
local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

type TrackedAgent = {
	rig: Model,
	rigRoot: BasePart,
	agentRoot: BasePart,
	connections: { RBXScriptConnection },
}

local tracked: { [Instance]: TrackedAgent } = {}
local pendingFollowers: { [Instance]: {Instance} } = {}
local rigsFolder: Folder

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function roundNonNegative(value: number): number
	return math.max(0, math.floor(value + 0.5))
end

-- Static full-state setup for a freshly cloned bar. Ongoing updates are handled by
-- EnemyEffects:DamageEffects off the agent's Health changes.
local function initHealthBar(gui: BillboardGui, health: number, maxHealth: number)
	local safeHealth = math.max(0, health)
	local safeMaxHealth = math.max(1, maxHealth)
	local healthRatio = math.clamp(safeHealth / safeMaxHealth, 0, 1)
	gui:SetAttribute("MaxHealth", safeMaxHealth)
	gui:SetAttribute("Health", safeHealth)

	local healthMeter = gui:FindFirstChild("HealthMeter")
	if not healthMeter then
		return
	end

	local fill = healthMeter:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(1, 1)

		local fillGradient = fill:FindFirstChild("FillGradient")
		if fillGradient and fillGradient:IsA("UIGradient") then
			if healthRatio <= 0 then
				fillGradient.Transparency = NumberSequence.new(1)
			elseif healthRatio >= 1 then
				fillGradient.Transparency = NumberSequence.new(0)
			else
				local edgeEnd = math.min(healthRatio + 0.001, 1)
				fillGradient.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(healthRatio, 0),
					NumberSequenceKeypoint.new(edgeEnd, 1),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		else
			fill.Size = UDim2.fromScale(healthRatio, 1)
		end
	end

	local amountLabel = healthMeter:FindFirstChild("AmountLabel")
	if amountLabel and amountLabel:IsA("TextLabel") then
		local healthText = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundNonNegative(safeHealth))))
		local maxHealthText = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundNonNegative(safeMaxHealth))))
		amountLabel.Text = `{healthText}/{maxHealthText}`
	end
end

local function playLocalDeathSound(agent: Model)
	local soundEmitter = Instance.new("Part")
	soundEmitter.Name = "EnemyDeathSound"
	soundEmitter.Anchored = true
	soundEmitter.CanCollide = false
	soundEmitter.CanTouch = false
	soundEmitter.CanQuery = false
	soundEmitter.Transparency = 1
	soundEmitter.Size = Vector3.new(0.1, 0.1, 0.1)
	soundEmitter.CFrame = agent:GetPivot()
	soundEmitter.Parent = Workspace

	local deathSound = DeathSoundTemplate:Clone()
	local deathAudioId = agent:GetAttribute("deathAudioId")
	if typeof(deathAudioId) == "string" and deathAudioId ~= "" then
		deathSound.SoundId = deathAudioId
	end
	deathSound.Parent = soundEmitter
	deathSound:Play()

	local cleanupLifetime = math.max(DEATH_SOUND_FALLBACK_LIFETIME, deathSound.TimeLength + DEATH_SOUND_CLEANUP_PADDING)
	Debris:AddItem(soundEmitter, cleanupLifetime)
end

-- Restore the old BreakJointsOnDeath look: drop every joint so the rig collapses,
-- unanchor so it falls, recollide as an Enemy so the corpse rests on the floor
-- without shoving the player, and strip the target highlight + health bar.
local function ragdollRig(rig: Model)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = true
			pcall(function()
				descendant.CollisionGroup = RAGDOLL_COLLISION_GROUP
			end)
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		elseif descendant:IsA("Highlight") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

-- Pin a follower instance (e.g. a linger/fire effect) to the rig root so it rides
-- along, and parent it under the rig so the rig's own teardown disposes of it.
local function attachFollowerToRig(entry: TrackedAgent, instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = false
		instance.CFrame = entry.rigRoot.CFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = entry.rigRoot
		weld.Part1 = instance
		weld.Parent = instance
	end

	instance.Parent = entry.rig
end

-- Plain teardown (despawn, owner-tag removal, or a corpse that never died): drop
-- the rig immediately, no ragdoll.
local function cleanupAgent(agent: Instance)
	pendingFollowers[agent] = nil

	local entry = tracked[agent]
	if not entry then
		return
	end

	tracked[agent] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.rig.Parent then
		entry.rig:Destroy()
	end
end

-- Death: stop tracking the agent, detach the rig, collapse it into a ragdoll, and
-- let Debris clean it up.
local function killAgent(agent: Instance)
	local entry = tracked[agent]
	if not entry then
		return
	end

	pendingFollowers[agent] = nil
	tracked[agent] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end

	ragdollRig(entry.rig)
	Debris:AddItem(entry.rig, RAGDOLL_LIFETIME)
end

-- Clone + prepare the owner-only visual rig for one agent.
local function watchAgent(agent: Instance)
	if not agent:IsA("Model") or tracked[agent] then
		return
	end

	-- The agent is a tiny model that replicates atomically; still, guard against a
	-- slow root so we don't fail-dark on a single enemy.
	local agentRoot = agent:WaitForChild("HumanoidRootPart", AGENT_ROOT_WAIT_TIMEOUT)
	if not agentRoot or not agentRoot:IsA("BasePart") or not agent.Parent then
		return
	end
	local agentHumanoid = agent:FindFirstChildOfClass("Humanoid")
	if not agentHumanoid then
		return
	end

	local enemyType = agent:GetAttribute("enemyType")
	local definition = if typeof(enemyType) == "string" then EnemyDefinitions[enemyType] else nil
	if not definition or not definition.model then
		return
	end

	local rig = definition.model:Clone()
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end

	local rigRoot = rig.PrimaryPart or rig:FindFirstChild("HumanoidRootPart")
	if not rigRoot or not rigRoot:IsA("BasePart") then
		rig:Destroy()
		return
	end
	-- Anchor only the rig root; the body follows via its joints when we move the
	-- root each frame (cheap, single CFrame write per rig). Mirrors the server.
	rigRoot.Anchored = true

	local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		rigHumanoid.EvaluateStateMachine = false
		rigHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = HIGHLIGHT_FILL_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = true
	highlight.Parent = rig

	local healthBar: BillboardGui? = nil
	local rigHead = rig:FindFirstChild("Head")
	if rigHead then
		local clonedBar = HealthBillboardGuiTemplate:Clone()
		if clonedBar:IsA("BillboardGui") then
			initHealthBar(clonedBar, agentHumanoid.Health, agentHumanoid.MaxHealth)
			clonedBar.Parent = rigHead
			healthBar = clonedBar
		else
			clonedBar:Destroy()
		end
	end

	rig:PivotTo(agentRoot.CFrame)
	rig.Parent = rigsFolder

	local connections: { RBXScriptConnection } = {}
	local entry: TrackedAgent = {
		rig = rig,
		rigRoot = rigRoot,
		agentRoot = agentRoot,
		connections = connections,
	}
	tracked[agent] = entry

	-- Attach any linger/fire effects that arrived before this rig existed.
	local queuedFollowers = pendingFollowers[agent]
	if queuedFollowers then
		pendingFollowers[agent] = nil
		for _, follower in queuedFollowers do
			pcall(attachFollowerToRig, entry, follower)
		end
	end

	-- The agent Humanoid is fully anchored, so on the client it never steps its
	-- state machine and Humanoid.Died never fires. Drive both the hit feedback and
	-- death off the replicated Health value, which always updates.
	local function onAgentHealthChanged()
		local currentHealth = agentHumanoid.Health
		if currentHealth <= 0 then
			playLocalDeathSound(agent :: Model)
			killAgent(agent)
			return
		end

		local enemyEffects = EnemyRenderController.Controllers.EnemyEffects
		if enemyEffects then
			enemyEffects:DamageEffects(highlight, healthBar, currentHealth)
		end
	end

	table.insert(connections, agentHumanoid:GetPropertyChangedSignal("Health"):Connect(onAgentHealthChanged))

	-- Handle the rare case where the agent already replicated at <= 0 health.
	if agentHumanoid.Health <= 0 then
		onAgentHealthChanged()
	end

	table.insert(connections, agent.Destroying:Connect(function()
		cleanupAgent(agent)
	end))
end

-- Smoothly follow each agent's (replicated, interpolated) root every frame.
local function updateFollow(deltaTime: number)
	local alpha = math.min(1, deltaTime * FOLLOW_SMOOTHING)
	for _, entry in tracked do
		if entry.agentRoot.Parent then
			entry.rigRoot.CFrame = entry.rigRoot.CFrame:Lerp(entry.agentRoot.CFrame, alpha)
		end
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

-- Attach a follower instance to an agent's visual rig. If the rig isn't built yet
-- (the agent just appeared), queue it; watchAgent drains the queue on build.
function EnemyRenderController:AttachFollower(agent: Instance, instance: Instance)
	local entry = tracked[agent]
	if entry then
		attachFollowerToRig(entry, instance)
		return
	end

	local queued = pendingFollowers[agent]
	if not queued then
		queued = {}
		pendingFollowers[agent] = queued
	end
	table.insert(queued, instance)
end

function EnemyRenderController:Init(controllers)
	self.Controllers = controllers
end

function EnemyRenderController:Start()
	rigsFolder = Instance.new("Folder")
	rigsFolder.Name = "ClientEnemyRigs"
	rigsFolder.Parent = Workspace

	local ownerTag = OWNER_TAG_PREFIX .. player.Name

	for _, agent in CollectionService:GetTagged(ownerTag) do
		task.spawn(watchAgent, agent)
	end

	CollectionService:GetInstanceAddedSignal(ownerTag):Connect(function(agent)
		task.spawn(watchAgent, agent)
	end)
	CollectionService:GetInstanceRemovedSignal(ownerTag):Connect(cleanupAgent)

	RunService.RenderStepped:Connect(updateFollow)
end

return EnemyRenderController
