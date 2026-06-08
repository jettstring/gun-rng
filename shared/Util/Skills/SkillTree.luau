--!strict

local Skill = require(script.Parent.Skill)

local SkillTree = {}
local skillTree_mt = { __index = SkillTree }

export type Skill = Skill.Type
export type SkillStats = Skill.Stats
export type SkillDefinition = Skill.Definition
export type Direction = Skill.Direction

-- The preferred authored format is NestedSkillDefinitions: each skill id maps to
-- its skill data, with child nodes under an optional `unlocks` table. Labels
-- default to the skill id unless a definition explicitly overrides them.
export type NestedSkillDefinition = {
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
	stats: Skill.Stats?,
	unlocks: NestedSkillDefinitions?,
}
export type NestedSkillDefinitions = { [string]: NestedSkillDefinition }

export type Definition = {
	tree: NestedSkillDefinitions,
	maxChildNodes: number?,
}

type SkillDefinitions = { [string]: SkillDefinition }
type UnlockMap = { [string]: { string } }
type FlattenedDefinitions = {
	skills: SkillDefinitions,
	unlocks: UnlockMap,
	roots: { string },
}

export type ResolvedStats = { [string]: number }

export type Type = {
	skills: { [string]: Skill.Type },
	rootIds: { string },
	maxChildNodes: number,
	_parentIds: { [string]: { string } },

	AddSkill: (self: Type, id: string, definition: SkillDefinition) -> Skill.Type,
	AddUnlock: (self: Type, parentId: string, childId: string) -> (),
	RemoveUnlock: (self: Type, parentId: string, childId: string) -> boolean,
	GetSkill: (self: Type, id: string) -> Skill.Type?,
	RequireSkill: (self: Type, id: string) -> Skill.Type,
	GetRoots: (self: Type) -> { Skill.Type },
	GetChildren: (self: Type, id: string) -> { Skill.Type },
	GetParents: (self: Type, id: string) -> { Skill.Type },
	SetOwned: (self: Type, id: string, owned: boolean) -> (),
	CrawlStats: (self: Type, rootId: string?) -> ResolvedStats,
	GetOwnedStats: (self: Type, rootId: string?) -> ResolvedStats,
	ValidateAcyclic: (self: Type) -> boolean,
}

SkillTree.MAX_CHILD_NODES = Skill.MAX_UNLOCKS

local function newResolvedStats(): ResolvedStats
	return {}
end

local function addStats(total: ResolvedStats, stats: Skill.Stats): ()
	for statKey, statValue in stats do
		total[statKey] = (total[statKey] or 0) + statValue
	end
end

local function crawlStats(skill: Skill.Type, visited: { [string]: boolean }, total: ResolvedStats): ()
	if visited[skill.id] then
		return
	end
	visited[skill.id] = true

	if skill.owned then
		addStats(total, skill.stats)
	end

	for _, child in skill.unlocks do
		crawlStats(child, visited, total)
	end
end

local function arrayContains(values: { string }, value: string): boolean
	for _, current in values do
		if current == value then
			return true
		end
	end

	return false
end

local function cloneNestedSkillDefinition(definition: NestedSkillDefinition): SkillDefinition
	return {
		label = definition.label,
		direction = definition.direction,
		description = definition.description,
		price = definition.price,
		imageId = definition.imageId,
		owned = definition.owned,
		alwaysShow = definition.alwaysShow,
		subTreeEntrance = definition.subTreeEntrance,
		subTreeExit = definition.subTreeExit,
		hidden = definition.hidden,
		stats = definition.stats,
	}
end

local function getSortedSkillIds(skills: { [string]: Skill.Type }): { string }
	local ids = {}
	for id in skills do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function checkMaxChildNodes(maxChildNodes: number): ()
	assert(maxChildNodes >= 1, "SkillTree maxChildNodes must be at least 1")
	assert(
		maxChildNodes <= SkillTree.MAX_CHILD_NODES,
		`SkillTree maxChildNodes cannot be greater than {SkillTree.MAX_CHILD_NODES}`
	)
end

local function flattenNestedSkillDefinitions(
	nestedSkillDefinitions: NestedSkillDefinitions,
	skills: SkillDefinitions,
	unlocks: UnlockMap,
	roots: { string },
	parentId: string?
): ()
	for skillId, nestedSkillDefinition in nestedSkillDefinitions do
		local skillKey = tostring(skillId)

		if not skills[skillKey] then
			skills[skillKey] = cloneNestedSkillDefinition(nestedSkillDefinition)
		end

		if parentId then
			local childIds = unlocks[parentId]
			if not childIds then
				childIds = {}
				unlocks[parentId] = childIds
			end

			if not arrayContains(childIds, skillKey) then
				table.insert(childIds, skillKey)
			end
		elseif not arrayContains(roots, skillKey) then
			table.insert(roots, skillKey)
		end

		if nestedSkillDefinition.unlocks then
			flattenNestedSkillDefinitions(nestedSkillDefinition.unlocks, skills, unlocks, roots, skillKey)
		end
	end
end

local function flattenNestedDefinitions(nestedSkillDefinitions: NestedSkillDefinitions): FlattenedDefinitions
	local skills: SkillDefinitions = {}
	local unlocks: UnlockMap = {}
	local roots: { string } = {}

	flattenNestedSkillDefinitions(nestedSkillDefinitions, skills, unlocks, roots, nil)

	return {
		skills = skills,
		unlocks = unlocks,
		roots = roots,
	}
end

function SkillTree.new(definition: Definition): Type
	local maxChildNodes = SkillTree.MAX_CHILD_NODES
	if definition.maxChildNodes ~= nil then
		maxChildNodes = definition.maxChildNodes
		checkMaxChildNodes(maxChildNodes)
	end

	local self = setmetatable({
		skills = {},
		rootIds = {},
		maxChildNodes = maxChildNodes,
		_parentIds = {},
	}, skillTree_mt) :: any

	local flattenedDefinitions = flattenNestedDefinitions(definition.tree)
	for id, skillDefinition in flattenedDefinitions.skills do
		SkillTree.AddSkill(self, tostring(id), skillDefinition)
	end

	for parentId, childIds in flattenedDefinitions.unlocks do
		for _, childId in childIds do
			SkillTree.AddUnlock(self, parentId, childId)
		end
	end

	for _, rootId in flattenedDefinitions.roots do
		SkillTree.RequireSkill(self, rootId)
		table.insert(self.rootIds, rootId)
	end

	assert(SkillTree.ValidateAcyclic(self), "SkillTree contains a cycle")

	return self
end

function SkillTree.AddSkill(self: Type, id: string, definition: SkillDefinition): Skill.Type
	assert(id ~= "", "Skill id cannot be empty")
	assert(self.skills[id] == nil, `Skill "{id}" already exists in the tree`)

	local skill = Skill.new(id, definition)
	self.skills[id] = skill
	self._parentIds[id] = self._parentIds[id] or {}

	return skill
end

function SkillTree.AddUnlock(self: Type, parentId: string, childId: string): ()
	local parent = SkillTree.RequireSkill(self, parentId)
	local child = SkillTree.RequireSkill(self, childId)

	if Skill.HasUnlock(parent, child) then
		return
	end

	assert(#parent.unlocks < self.maxChildNodes, `Skill "{parentId}" cannot unlock more than {self.maxChildNodes} skills`)

	Skill.AddUnlock(parent, child)

	local parentIds = self._parentIds[childId]
	if not parentIds then
		parentIds = {}
		self._parentIds[childId] = parentIds
	end

	if not arrayContains(parentIds, parentId) then
		table.insert(parentIds, parentId)
	end
end

function SkillTree.RemoveUnlock(self: Type, parentId: string, childId: string): boolean
	local parent = SkillTree.RequireSkill(self, parentId)
	local child = SkillTree.RequireSkill(self, childId)

	local removed = Skill.RemoveUnlock(parent, child)
	if not removed then
		return false
	end

	local parentIds = self._parentIds[childId]
	if parentIds then
		for index, existingParentId in parentIds do
			if existingParentId == parentId then
				table.remove(parentIds, index)
				break
			end
		end
	end

	return true
end

function SkillTree.GetSkill(self: Type, id: string): Skill.Type?
	return self.skills[id]
end

function SkillTree.RequireSkill(self: Type, id: string): Skill.Type
	local skill = self.skills[id]
	assert(skill ~= nil, `Skill "{id}" does not exist in the tree`)
	return skill
end

function SkillTree.GetRoots(self: Type): { Skill.Type }
	local roots = {}

	if #self.rootIds > 0 then
		for _, rootId in self.rootIds do
			table.insert(roots, SkillTree.RequireSkill(self, rootId))
		end
		return roots
	end

	for _, id in getSortedSkillIds(self.skills) do
		local parentIds = self._parentIds[id]
		if not parentIds or #parentIds == 0 then
			table.insert(roots, SkillTree.RequireSkill(self, id))
		end
	end

	return roots
end

function SkillTree.GetChildren(self: Type, id: string): { Skill.Type }
	return SkillTree.RequireSkill(self, id).unlocks
end

function SkillTree.GetParents(self: Type, id: string): { Skill.Type }
	SkillTree.RequireSkill(self, id)

	local parents = {}
	local parentIds = self._parentIds[id]
	if not parentIds then
		return parents
	end

	for _, parentId in parentIds do
		table.insert(parents, SkillTree.RequireSkill(self, parentId))
	end

	return parents
end

function SkillTree.SetOwned(self: Type, id: string, owned: boolean): ()
	Skill.SetOwned(SkillTree.RequireSkill(self, id), owned)
end

function SkillTree.CrawlStats(self: Type, rootId: string?): ResolvedStats
	local total = newResolvedStats()
	local visited = {}

	if rootId then
		crawlStats(SkillTree.RequireSkill(self, rootId), visited, total)
		return total
	end

	local roots = SkillTree.GetRoots(self)
	if #roots == 0 then
		for _, id in getSortedSkillIds(self.skills) do
			crawlStats(SkillTree.RequireSkill(self, id), visited, total)
		end
		return total
	end

	for _, root in roots do
		crawlStats(root, visited, total)
	end

	return total
end

function SkillTree.GetOwnedStats(self: Type, rootId: string?): ResolvedStats
	return SkillTree.CrawlStats(self, rootId)
end

function SkillTree.ValidateAcyclic(self: Type): boolean
	local visiting = {}
	local visited = {}

	local function visit(skill: Skill.Type): boolean
		if visited[skill.id] then
			return true
		end
		if visiting[skill.id] then
			return false
		end

		visiting[skill.id] = true
		for _, child in skill.unlocks do
			if not visit(child) then
				return false
			end
		end
		visiting[skill.id] = nil
		visited[skill.id] = true

		return true
	end

	for _, id in getSortedSkillIds(self.skills) do
		if not visit(SkillTree.RequireSkill(self, id)) then
			return false
		end
	end

	return true
end

return SkillTree
