-- Kinematic enemy steering: seek + separation + player-as-repulsor, with a
-- uniform spatial hash so neighbour lookups stay ~O(N) instead of O(N^2).
--
-- This module is pure math + a grid. It never touches Instances, Humanoids, or
-- game state, so it is cheap to unit-test and reuse. The caller (EnemyService)
-- owns the agents: each tick it builds one hash PER OWNER GROUP (a player only
-- ever sees their own enemies, so cross-owner overlap is invisible and we skip
-- it), then asks for each agent's desired velocity and integrates it.
--
-- All vectors are flattened to the X/Z plane; the caller pins Y to the floor.

local EnemySteering = {}

export type Config = {
	-- Blend strengths (dimensionless). Each behaviour produces a velocity in
	-- [0, maxSpeed]; these scale how much each contributes before the final cap.
	seekWeight: number,
	separationWeight: number,
	playerRepulseWeight: number,
	-- Radii in studs.
	separationRadius: number,
	playerRepulseRadius: number, -- attack standoff: where seek and repulse balance
	-- Small per-agent noise that breaks symmetric deadlocks (e.g. two enemies
	-- dead-opposite a target). Fraction of maxSpeed.
	jitter: number,
}

-- Defaults assume ~5-6 stud enemy spacing and a ~5 stud attack standoff (the old
-- ENEMY_CHASE_STOP_RADIUS). Equilibrium standoff ≈ playerRepulseRadius * (1 -
-- seekWeight / playerRepulseWeight) = 8 * (1 - 1/2.7) ≈ 5. Tune to taste.
EnemySteering.DefaultConfig = {
	seekWeight = 1,
	separationWeight = 3.6,
	playerRepulseWeight = 6.7,
	separationRadius = 6,
	playerRepulseRadius = 15,
	jitter = 0.05,
} :: Config

local EPS = 1e-4

local function flatXZ(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function randomUnitXZ(rng: Random): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

--------------------------------------------------
-- SPATIAL HASH --
--------------------------------------------------
-- Nested table buckets[cx][cz] -> { {item, position}, ... } to avoid string-key
-- allocation in the hot path. cellSize should be >= the largest query radius so
-- a 3x3 neighbourhood fully covers it.

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type SpatialHash = typeof(setmetatable(
	{} :: { cellSize: number, columns: { [number]: { [number]: { { any } } } } },
	SpatialHash
))

function EnemySteering.newSpatialHash(cellSize: number): SpatialHash
	return setmetatable({
		cellSize = math.max(EPS, cellSize),
		columns = {},
	}, SpatialHash)
end

function SpatialHash.clear(self: SpatialHash)
	table.clear(self.columns)
end

function SpatialHash.insert(self: SpatialHash, item: any, position: Vector3)
	local cx = math.floor(position.X / self.cellSize)
	local cz = math.floor(position.Z / self.cellSize)
	local column = self.columns[cx]
	if not column then
		column = {}
		self.columns[cx] = column
	end
	local cell = column[cz]
	if not cell then
		cell = {}
		column[cz] = cell
	end
	table.insert(cell, { item, position })
end

-- Calls fn(item, position) for every entry in the 3x3 cell neighbourhood around
-- `position` (including the agent itself; the caller skips self by identity).
function SpatialHash.forEachNeighbor(self: SpatialHash, position: Vector3, fn: (any, Vector3) -> ())
	local cx = math.floor(position.X / self.cellSize)
	local cz = math.floor(position.Z / self.cellSize)
	for dx = -1, 1 do
		local column = self.columns[cx + dx]
		if not column then
			continue
		end
		for dz = -1, 1 do
			local cell = column[cz + dz]
			if not cell then
				continue
			end
			for _, entry in cell do
				fn(entry[1], entry[2])
			end
		end
	end
end

--------------------------------------------------
-- STEERING --
--------------------------------------------------

-- Returns the desired velocity (X/Z, magnitude <= maxSpeed) for one agent.
-- `targetPos` is the owning player's position, or nil if it has no live target
-- (the agent then only separates from neighbours).
function EnemySteering.computeDesiredVelocity(
	agentItem: any,
	agentPos: Vector3,
	targetPos: Vector3?,
	maxSpeed: number,
	hash: SpatialHash,
	config: Config,
	rng: Random
): Vector3
	local desired = Vector3.zero

	-- Seek toward the player, with the player acting as a soft repulsor inside
	-- the standoff radius so the agent eases to a stop (and rings up) instead of
	-- piling onto the target.
	if targetPos then
		local toTarget = flatXZ(targetPos - agentPos)
		local distance = toTarget.Magnitude
		if distance > EPS then
			local dir = toTarget / distance
			desired += dir * (config.seekWeight * maxSpeed)
			if distance < config.playerRepulseRadius then
				local falloff = 1 - distance / config.playerRepulseRadius
				desired -= dir * (config.playerRepulseWeight * maxSpeed * falloff)
			end
		end
	end

	-- Separation from same-group neighbours. Costs nothing when spread out (no
	-- neighbours in the 3x3 cells); ramps up as they pack together.
	hash:forEachNeighbor(agentPos, function(item: any, neighborPos: Vector3)
		if item == agentItem then
			return
		end
		local offset = flatXZ(agentPos - neighborPos)
		local distance = offset.Magnitude
		if distance >= config.separationRadius then
			return
		end
		local dir, falloff
		if distance > EPS then
			dir = offset / distance
			falloff = 1 - distance / config.separationRadius
		else
			-- Exactly overlapping: shove apart in a random direction.
			dir = randomUnitXZ(rng)
			falloff = 1
		end
		desired += dir * (config.separationWeight * maxSpeed * falloff)
	end)

	if config.jitter > 0 then
		desired += randomUnitXZ(rng) * (config.jitter * maxSpeed)
	end

	local magnitude = desired.Magnitude
	if magnitude > maxSpeed then
		desired = (desired / magnitude) * maxSpeed
	end

	return desired
end

return EnemySteering
