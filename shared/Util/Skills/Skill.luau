--!strict

local Skill = {}
local skill_mt = { __index = Skill }

export type Stats = { [string]: number }
export type Direction = "Top" | "TopLeft" | "TopRight" | "Bottom" | "BottomLeft" | "BottomRight"

export type Definition = {
	label: string?,
	direction: Direction,
	description: string,
	price: number,
	imageId: string?,
	owned: boolean?,
	alwaysShow: boolean?,
	subTreeEntrance: boolean?,
	subTreeExit: boolean?,
	hidden: boolean?,
	stats: Stats?,
}

export type Type = {
	id: string,
	label: string,
	direction: Direction,
	description: string,
	price: number,
	imageId: string?,
	owned: boolean,
	alwaysShow: boolean,
	subTreeEntrance: boolean,
	subTreeExit: boolean,
	hidden: boolean,
	stats: Stats,
	unlocks: { Type },

	AddUnlock: (self: Type, child: Type) -> (),
	RemoveUnlock: (self: Type, child: Type) -> boolean,
	HasUnlock: (self: Type, child: Type) -> boolean,
	CanReach: (self: Type, target: Type) -> boolean,
	SetOwned: (self: Type, owned: boolean) -> (),
	IsOwned: (self: Type) -> boolean,
	CloneStats: (self: Type) -> Stats,
}

Skill.MAX_UNLOCKS = 6
local VALID_DIRECTIONS: { [string]: boolean } = {
	Top = true,
	TopLeft = true,
	TopRight = true,
	Bottom = true,
	BottomLeft = true,
	BottomRight = true,
}

local function cloneStats(stats: Stats?): Stats
	if not stats then
		return {}
	end

	local clonedStats: Stats = {}

	for statKey, statValue in stats do
		clonedStats[statKey] = statValue
	end

	return clonedStats
end

local function canReach(current: Type, target: Type, visited: { [string]: boolean }): boolean
	if current == target or current.id == target.id then
		return true
	end

	if visited[current.id] then
		return false
	end
	visited[current.id] = true

	for _, child in current.unlocks do
		if canReach(child, target, visited) then
			return true
		end
	end

	return false
end

function Skill.new(id: string, definition: Definition): Type
	assert(id ~= "", "Skill id cannot be empty")
	local label = definition.label or id
	assert(label ~= "", `Skill "{id}" label cannot be empty`)
	assert(VALID_DIRECTIONS[definition.direction] == true, `Skill "{id}" requires a valid direction`)
	assert(definition.description ~= "", `Skill "{id}" requires a description`)
	assert(definition.price >= 0, `Skill "{id}" price cannot be negative`)

	local self = {
		id = id,
		label = label,
		direction = definition.direction,
		description = definition.description,
		price = definition.price,
		imageId = definition.imageId,
		owned = definition.owned == true,
		alwaysShow = definition.alwaysShow == true,
		subTreeEntrance = definition.subTreeEntrance == true,
		subTreeExit = definition.subTreeExit == true,
		hidden = definition.hidden == true,
		stats = cloneStats(definition.stats),
		unlocks = {},
	}

	return setmetatable(self, skill_mt) :: any
end

function Skill.AddUnlock(self: Type, child: Type): ()
	assert(self ~= child and self.id ~= child.id, `Skill "{self.id}" cannot unlock itself`)

	if Skill.HasUnlock(self, child) then
		return
	end

	assert(#self.unlocks < Skill.MAX_UNLOCKS, `Skill "{self.id}" cannot unlock more than {Skill.MAX_UNLOCKS} skills`)
	assert(not Skill.CanReach(child, self), `Adding "{self.id}" -> "{child.id}" would create a cycle`)

	table.insert(self.unlocks, child)
end

function Skill.RemoveUnlock(self: Type, child: Type): boolean
	for index, unlockedSkill in self.unlocks do
		if unlockedSkill == child or unlockedSkill.id == child.id then
			table.remove(self.unlocks, index)
			return true
		end
	end

	return false
end

function Skill.HasUnlock(self: Type, child: Type): boolean
	for _, unlockedSkill in self.unlocks do
		if unlockedSkill == child or unlockedSkill.id == child.id then
			return true
		end
	end

	return false
end

function Skill.CanReach(self: Type, target: Type): boolean
	return canReach(self, target, {})
end

function Skill.SetOwned(self: Type, owned: boolean): ()
	self.owned = owned
end

function Skill.IsOwned(self: Type): boolean
	return self.owned
end

function Skill.CloneStats(self: Type): Stats
	return cloneStats(self.stats)
end

return Skill
