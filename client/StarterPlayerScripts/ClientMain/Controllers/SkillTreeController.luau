--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SkillTree = require(ReplicatedStorage.Util.Skills.SkillTree)
local SkillDefinitions = require(ReplicatedStorage.Util.Skills.SkillDefinitions)
local Gigantix = require(ReplicatedStorage.Packages.Gigantix)
local Spr = require(ReplicatedStorage.Packages.Spr)
local SoundPool = require(ReplicatedStorage.Packages.SoundPool)
local UIsfx = SoundService.SFX:WaitForChild("UI")

type Skill = SkillTree.Skill

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local gameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local notificationAssets = gameAssets:WaitForChild("NotificationAssets")
local ScreenElements = playerGui:WaitForChild("ScreenElements")
local hotbarFrame = ScreenElements:WaitForChild("Hotbar")
local openUpgradesButton = hotbarFrame:WaitForChild("UpgradeButton") :: GuiButton
local counterBadgeTemplate = notificationAssets:WaitForChild("CounterBadge") :: ImageLabel

local upgradeGui = playerGui:WaitForChild("UpgradeGui") :: ScreenGui
local upgradeGuiHotbar = upgradeGui:WaitForChild("Hotbar")
local hideUpgradesButton = upgradeGuiHotbar:WaitForChild("HideButton") :: GuiButton
local skillTreeContainer = upgradeGui:WaitForChild("SkillTreeContainer") :: Frame
local skillButtonTemplate = skillTreeContainer:WaitForChild("SkillButton") :: ImageButton
local popupsGui = playerGui:WaitForChild("Popups") :: ScreenGui
local skillInfoFrame = popupsGui:WaitForChild("SkillInfoFrame") :: ImageLabel
local skillInfoName = skillInfoFrame.SkillName :: TextLabel
local skillInfoDescription = skillInfoFrame.Description :: TextLabel
local skillInfoMoneyLabel = skillInfoFrame.MoneyLabel :: Frame
local skillInfoMoneyIcon = skillInfoMoneyLabel.Icon :: ImageLabel
local skillInfoMoneyAmount = skillInfoMoneyLabel.Description :: TextLabel
local skillInfoMoneyAmountDefaultPosition = skillInfoMoneyAmount.Position
local skillInfoMoneyAmountDefaultAnchor = skillInfoMoneyAmount.AnchorPoint
local skillButtonTemplateMoneyDisplay = skillButtonTemplate.MoneyDisplay :: Frame
local skillButtonTemplatePrice = skillButtonTemplateMoneyDisplay.Amount :: TextLabel
local skillButtonPriceDefaultPosition = skillButtonTemplatePrice.Position
local skillButtonPriceDefaultAnchor = skillButtonTemplatePrice.AnchorPoint
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local upgradeRemotes = remotesFolder:WaitForChild("Upgrades")
local getOwnedSkillsRemote = upgradeRemotes:WaitForChild("GetOwnedSkills") :: RemoteFunction
local unlockSkillRemote = upgradeRemotes:WaitForChild("UnlockSkill") :: RemoteFunction
local ownedSkillsChangedRemote = upgradeRemotes:WaitForChild("OwnedSkillsChanged") :: RemoteEvent

type LayoutMap = { [string]: Vector2 }
type NumberMap = { [string]: number }
type SkillIdMap = { [string]: boolean }
type OptionalSkillIdMap = { [string]: boolean? }
type DirectionGridOffsetMap = { [string]: Vector2 }
type FrameSizeMap = { [string]: UDim2 }
type PixelBounds = {
	min: Vector2,
	max: Vector2,
}
type RevealInfo = {
	depth: number,
	order: number,
}
type RevealInfoMap = { [string]: RevealInfo }
type BadgeCandidate = {
	price: number,
}
type UnlockSkillResult = {
	success: boolean,
	message: string?,
	ownedSkills: SkillIdMap?,
}

local SQRT_3 = math.sqrt(3)
local MIN_ZOOM = 0.45
local MAX_ZOOM = 2.75
local SCROLL_ZOOM_STEP = 1.12
local DRAG_CLICK_SUPPRESSION_DISTANCE = 8
local DRAG_CLICK_SUPPRESSION_SECONDS = 0.15
local REVEAL_NODE_DELAY = 0.035
local REVEAL_LAYER_DELAY = 0.025
local REVEAL_DAMPING_RATIO = 0.56
local REVEAL_FREQUENCY = 12
local TREE_VIEW_HIDE_SECONDS = 0.14
local POSITION_DAMPING_RATIO = 0.78
local POSITION_FREQUENCY = 10
local NODE_PADDING_COUNT = 7
local NODE_HOVER_SCALE = 1.1
local NODE_CLICK_SCALE = 1
local NODE_SCALE_DAMPING_RATIO = 0.62
local NODE_SCALE_FREQUENCY = 8
local NODE_UNLOCK_PULSE_SCALE = 1.035
local NODE_UNLOCK_PULSE_SECONDS = 0.1
local NODE_UNLOCK_PULSE_LAYER_DELAY = 0.05
local NODE_UNLOCK_PULSE_DAMPING_RATIO = 0.88
local NODE_UNLOCK_PULSE_FREQUENCY = 7
local VIEWPORT_PAN_DAMPING_RATIO = 0.92
local VIEWPORT_PAN_FREQUENCY = 11
local ZINDEX_LAYER_STEP = 3
local POP_SOUND_POOL_SIZE = 15
local POP_SOUND_VOLUME_MULTIPLIER = 0.9
local SKILL_INFO_GAP_NODE_WIDTH_SCALE = -0.27
local CENTERED_MONEY_TEXT_POSITION = UDim2.fromScale(0.5, 0.5)
local CENTERED_MONEY_TEXT_ANCHOR = Vector2.new(0.5, 0.5)
local UPGRADE_CURRENCY_ATTRIBUTE = "Money"

local NODE_IMAGES = {
	UNOWNED = "rbxassetid://71861382935431",
	OWNED = "rbxassetid://116569397359748",
	SUBTREE = "rbxassetid://123682832796721",
	PREVIEW = "rbxassetid://77407754606015",
	BACK = "rbxassetid://71697073730409",
}

local DIRECTION_GRID_OFFSETS: DirectionGridOffsetMap = {
	Top = Vector2.new(0, -2),
	TopRight = Vector2.new(1, -1),
	BottomRight = Vector2.new(1, 1),
	Bottom = Vector2.new(0, 2),
	BottomLeft = Vector2.new(-1, 1),
	TopLeft = Vector2.new(-1, -1),
}

local SkillTreeController = {}
SkillTreeController.Controllers = {}
SkillTreeController.Signals = {}

local tree = SkillTree.new({
	tree = SkillDefinitions.tree,
})

local defaultOwnedSkillIds: SkillIdMap = {}
for skillId, skill in tree.skills do
	defaultOwnedSkillIds[skillId] = skill.owned
end

local existingTreeContent = skillTreeContainer:FindFirstChild("SkillTreeContent")
if existingTreeContent then
	existingTreeContent:Destroy()
end

local treeContentFrame = Instance.new("Frame")
treeContentFrame.Name = "SkillTreeContent"
treeContentFrame.BackgroundTransparency = 1
treeContentFrame.BorderSizePixel = 0
treeContentFrame.ClipsDescendants = false
treeContentFrame.Position = UDim2.fromOffset(0, 0)
treeContentFrame.Size = UDim2.fromOffset(0, 0)
treeContentFrame.ZIndex = skillButtonTemplate.ZIndex - 1
treeContentFrame.Parent = skillTreeContainer

local treeContentScale = Instance.new("UIScale")
treeContentScale.Scale = 1
treeContentScale.Parent = treeContentFrame

local popSoundPoolFolder = Instance.new("Folder")
popSoundPoolFolder.Name = "SkillTreePopSoundPool"
popSoundPoolFolder.Parent = Workspace

local popSoundPool = SoundPool.new(
	UIsfx:WaitForChild("PopSound") :: Sound,
	popSoundPoolFolder,
	POP_SOUND_POOL_SIZE,
	POP_SOUND_POOL_SIZE
)

local parentsBySkillId: { [string]: { string } } = {}
local renderedNodes: { ImageButton } = {}
local renderedNodesBySkillId: { [string]: ImageButton } = {}
local frameBaseSizesBySkillId: FrameSizeMap = {}
local subtreeCounterBadgesByEntranceId: { [string]: ImageLabel } = {}
local globalBadgeCandidates: { BadgeCandidate } = {}
local subtreeBadgeCandidatesByEntranceId: { [string]: { BadgeCandidate } } = {}
local refreshTree: (boolean?, SkillIdMap?) -> ()
local started = false
local revealGeneration = 0
local visibleSkillIds: SkillIdMap = {}
local pendingUnlockSkillIds: SkillIdMap = {}
local subTreeEntranceStack: { string } = {}
local hoveredSkillIds: OptionalSkillIdMap = {}
local hoveredTooltipSkillId: string? = nil
local pressedSkillIds: OptionalSkillIdMap = {}
local unlockPulseUntilBySkillId: { [string]: number? } = {}
local zoom = 1
local pan = Vector2.zero
local contentBounds: PixelBounds = {
	min = Vector2.zero,
	max = Vector2.zero,
}
local dragging = false
local pinching = false
local dragInput: InputObject? = nil
local dragStartScreenPoint = Vector2.zero
local dragStartPan = Vector2.zero
local dragMoved = false
local suppressClickUntil = 0
local pinchStartZoom = 1
local treeViewTransitionGeneration = 0
local treeViewTransitioning = false
local counterBadgeRefreshQueued = false

local function getSkillIds(): { string }
	local ids = {}
	for id, skill in tree.skills do
		if not skill.hidden then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function sanitizeOwnedSkills(ownedSkills: any): SkillIdMap
	local sanitized: SkillIdMap = {}

	if typeof(ownedSkills) ~= "table" then
		return sanitized
	end

	for skillId, owned in ownedSkills do
		local skill = if typeof(skillId) == "string" then tree:GetSkill(skillId) else nil
		if skill and owned == true and not skill.hidden and not skill.subTreeEntrance then
			sanitized[skillId] = true
		end
	end

	return sanitized
end

local function applyOwnedSkills(ownedSkills: any): ()
	for skillId in tree.skills do
		tree:SetOwned(skillId, defaultOwnedSkillIds[skillId] == true)
	end

	for skillId, owned in sanitizeOwnedSkills(ownedSkills) do
		if owned then
			tree:SetOwned(skillId, true)
		end
	end
end

local function requestOwnedSkills(): SkillIdMap
	local success, result = pcall(function()
		return getOwnedSkillsRemote:InvokeServer()
	end)

	if not success then
		warn("[SkillTreeController] Failed to load owned skills:", result)
		return {}
	end

	return sanitizeOwnedSkills(result)
end

local function requestUnlockSkill(skillId: string): UnlockSkillResult?
	local success, result = pcall(function()
		return unlockSkillRemote:InvokeServer(skillId)
	end)

	if not success then
		warn(`[SkillTreeController] Failed to unlock skill "{skillId}":`, result)
		return nil
	end

	if typeof(result) ~= "table" or typeof(result.success) ~= "boolean" then
		warn(`[SkillTreeController] Invalid unlock response for skill "{skillId}"`)
		return nil
	end

	if result.ownedSkills ~= nil then
		result.ownedSkills = sanitizeOwnedSkills(result.ownedSkills)
	end

	return result :: UnlockSkillResult
end

local hotbarCounterBadge = counterBadgeTemplate:Clone()
hotbarCounterBadge.Visible = false
hotbarCounterBadge.Parent = openUpgradesButton

local function clampPan(candidatePan: Vector2): Vector2
	local containerSize = skillTreeContainer.AbsoluteSize
	local minX = containerSize.X - contentBounds.max.X * zoom
	local maxX = -contentBounds.min.X * zoom
	local minY = containerSize.Y - contentBounds.max.Y * zoom
	local maxY = -contentBounds.min.Y * zoom

	if minX > maxX then
		local centeredPan = (minX + maxX) / 2
		minX = centeredPan
		maxX = centeredPan
	end

	if minY > maxY then
		local centeredPan = (minY + maxY) / 2
		minY = centeredPan
		maxY = centeredPan
	end

	return Vector2.new(
		math.clamp(candidatePan.X, minX, maxX),
		math.clamp(candidatePan.Y, minY, maxY)
	)
end

local function applyViewportTransform(animate: boolean?): ()
	pan = clampPan(pan)
	local targetPosition = UDim2.fromOffset(math.round(pan.X), math.round(pan.Y))

	Spr.stop(treeContentFrame, "Position")
	if animate == true then
		Spr.target(treeContentFrame, VIEWPORT_PAN_DAMPING_RATIO, VIEWPORT_PAN_FREQUENCY, {
			Position = targetPosition,
		})
	else
		treeContentFrame.Position = targetPosition
	end

	treeContentScale.Scale = zoom
end

local function setZoomAtScreenPoint(nextZoom: number, screenPoint: Vector2): ()
	Spr.stop(treeContentFrame, "Position")
	local position = treeContentFrame.Position
	pan = Vector2.new(position.X.Offset, position.Y.Offset)

	local clampedZoom = math.clamp(nextZoom, MIN_ZOOM, MAX_ZOOM)
	local focusPoint = screenPoint - skillTreeContainer.AbsolutePosition
	local worldPoint = (focusPoint - pan) / zoom

	zoom = clampedZoom
	pan = focusPoint - worldPoint * zoom
	applyViewportTransform()
end

local function buildParentLookup(): ()
	parentsBySkillId = {}

	for parentId, skill in tree.skills do
		parentsBySkillId[parentId] = parentsBySkillId[parentId] or {}

		for _, child in skill.unlocks do
			local parents = parentsBySkillId[child.id]
			if not parents then
				parents = {}
				parentsBySkillId[child.id] = parents
			end

			table.insert(parents, parentId)
		end
	end
end

local function getSortedChildren(skill: Skill): { Skill }
	local children = {}

	for _, child in skill.unlocks do
		if not child.hidden then
			table.insert(children, child)
		end
	end

	table.sort(children, function(left: Skill, right: Skill): boolean
		if left.label == right.label then
			return left.id < right.id
		end

		return left.label < right.label
	end)

	return children
end

-- The subtree entrance whose "room" a skill lives in, or nil for the top-level
-- tree. A `subTreeExit` child detaches from the entrance directly above it and
-- rejoins that entrance's own room (one level out), so it renders as a normal
-- node in the outer tree instead of being swept into the subtree.
local function getViewEntrance(skillId: string): string?
	local parentIds = parentsBySkillId[skillId]
	if not parentIds or #parentIds == 0 then
		return nil
	end

	local parentId = parentIds[1]
	local parent = tree:RequireSkill(parentId)
	if parent.subTreeEntrance then
		if tree:RequireSkill(skillId).subTreeExit then
			return getViewEntrance(parentId)
		end

		return parentId
	end

	return getViewEntrance(parentId)
end

-- True if diving into `entranceId` (or any subtree nested below it) leads to the
-- skill. Detached (`subTreeExit`) nodes report nil/an outer room, so they fall
-- out of their former entrance's bucket while still counting globally.
local function isInSubTreeOf(skillId: string, entranceId: string): boolean
	local entrance = getViewEntrance(skillId)
	while entrance do
		if entrance == entranceId then
			return true
		end

		entrance = getViewEntrance(entrance)
	end

	return false
end

local function isInCurrentTreeView(skillId: string): boolean
	local activeEntranceId = subTreeEntranceStack[#subTreeEntranceStack]
	return skillId == activeEntranceId or getViewEntrance(skillId) == activeEntranceId
end

local function getSortedVisibleRoots(visible: SkillIdMap): { Skill }
	local roots = {}

	for _, skillId in getSkillIds() do
		local skill = tree:RequireSkill(skillId)
		local hasVisibleParent = false
		local parentIds = parentsBySkillId[skill.id]
		if parentIds then
			for _, parentId in parentIds do
				if visible[parentId] then
					hasVisibleParent = true
					break
				end
			end
		end

		if visible[skill.id] and not hasVisibleParent then
			table.insert(roots, skill)
		end
	end

	table.sort(roots, function(left: Skill, right: Skill): boolean
		if left.label == right.label then
			return left.id < right.id
		end

		return left.label < right.label
	end)

	return roots
end

local function isAvailable(skill: Skill): boolean
	if skill.owned then
		return true
	end

	local parents = parentsBySkillId[skill.id]
	if not parents or #parents == 0 then
		return true
	end

	for _, parentId in parents do
		local parent = tree:RequireSkill(parentId)
		if parent.owned or (parent.subTreeEntrance and isAvailable(parent)) then
			return true
		end
	end

	return false
end

local function rebuildCounterBadgeCandidates(): ()
	globalBadgeCandidates = {}
	subtreeBadgeCandidatesByEntranceId = {}

	local subtreeEntranceIds: { string } = {}
	for _, skillId in getSkillIds() do
		local skill = tree:RequireSkill(skillId)
		if skill.subTreeEntrance then
			table.insert(subtreeEntranceIds, skillId)
			subtreeBadgeCandidatesByEntranceId[skillId] = {}
		end
	end

	for _, skillId in getSkillIds() do
		local skill = tree:RequireSkill(skillId)
		if not skill.owned and not skill.subTreeEntrance and isAvailable(skill) then
			local candidate = {
				price = math.max(0, math.floor(skill.price + 0.5)),
			}
			table.insert(globalBadgeCandidates, candidate)

			for _, entranceId in subtreeEntranceIds do
				if isInSubTreeOf(skill.id, entranceId) then
					table.insert(subtreeBadgeCandidatesByEntranceId[entranceId], candidate)
				end
			end
		end
	end
end

local function refreshCounterBadges(): ()
	local money = math.floor(player:GetAttribute(UPGRADE_CURRENCY_ATTRIBUTE) or 0)
	local globalCount = 0
	for _, candidate in globalBadgeCandidates do
		if candidate.price <= money then
			globalCount += 1
		end
	end
	hotbarCounterBadge.Visible = globalCount > 0
	hotbarCounterBadge.IndicatorIcon.Text.Text = tostring(globalCount)

	for entranceId, badge in subtreeCounterBadgesByEntranceId do
		local subtreeCount = 0
		for _, candidate in subtreeBadgeCandidatesByEntranceId[entranceId] do
			if candidate.price <= money then
				subtreeCount += 1
			end
		end
		badge.Visible = subtreeCount > 0
		badge.IndicatorIcon.Text.Text = tostring(subtreeCount)
	end
end

local function computeVisibleSkillIds(): (SkillIdMap, SkillIdMap)
	local visible: SkillIdMap = {}
	local preview: SkillIdMap = {}
	local activeEntranceId = subTreeEntranceStack[#subTreeEntranceStack]

	for _, skillId in getSkillIds() do
		local skill = tree:RequireSkill(skillId)
		if isInCurrentTreeView(skillId) and (skillId == activeEntranceId or skill.alwaysShow or skill.owned or isAvailable(skill)) then
			visible[skillId] = true
		end
	end

	for _, skillId in getSkillIds() do
		local skill = tree:RequireSkill(skillId)
		if visible[skillId] and not skill.owned and isAvailable(skill) then
			for _, child in getSortedChildren(skill) do
				if isInCurrentTreeView(child.id) and not child.owned and not isAvailable(child) then
					visible[child.id] = true
					preview[child.id] = true
				end
			end
		end
	end

	return visible, preview
end

local function getNewlyVisibleSkillIds(previousVisibleSkillIds: SkillIdMap, nextVisibleSkillIds: SkillIdMap): SkillIdMap
	local newlyVisible: SkillIdMap = {}

	for skillId in nextVisibleSkillIds do
		if not previousVisibleSkillIds[skillId] then
			newlyVisible[skillId] = true
		end
	end

	return newlyVisible
end

local function showSkillInfo(skill: Skill, nodeFrame: GuiObject): ()
	local roundedPrice = math.max(0, math.floor(skill.price + 0.5))
	local requiresMoney = not skill.owned and not skill.subTreeEntrance and roundedPrice > 0

	skillInfoName.Text = skill.label
	skillInfoDescription.Text = skill.description
	skillInfoMoneyLabel.Visible = not skill.subTreeEntrance
	skillInfoMoneyIcon.Visible = requiresMoney
	skillInfoMoneyAmount.AnchorPoint = if requiresMoney then skillInfoMoneyAmountDefaultAnchor else CENTERED_MONEY_TEXT_ANCHOR
	skillInfoMoneyAmount.Position = if requiresMoney then skillInfoMoneyAmountDefaultPosition else CENTERED_MONEY_TEXT_POSITION

	if roundedPrice == 0 then
		skillInfoMoneyAmount.Text = "FREE"
	else
		skillInfoMoneyAmount.Text = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundedPrice)))
	end
	
	if skill.owned then
		skillInfoMoneyAmount.Text = "OWNED"
	end

	local nodeRight = nodeFrame.AbsolutePosition.X + nodeFrame.AbsoluteSize.X
	local nodeCenterY = nodeFrame.AbsolutePosition.Y + nodeFrame.AbsoluteSize.Y / 2
	local gap = nodeFrame.AbsoluteSize.X * SKILL_INFO_GAP_NODE_WIDTH_SCALE
	skillInfoFrame.Position = UDim2.fromOffset(
		math.round(nodeRight + gap),
		math.round(nodeCenterY)
	)
	skillInfoFrame.Visible = true
	hoveredTooltipSkillId = skill.id
end

local function computeRevealInfo(visible: SkillIdMap, revealOnly: SkillIdMap?): RevealInfoMap
	local revealInfo: RevealInfoMap = {}
	local visited: { [string]: boolean } = {}
	local currentLayer = getSortedVisibleRoots(visible)
	local depth = 0
	local order = 0

	while #currentLayer > 0 do
		local nextLayer = {}
		local nextLayerSeen: { [string]: boolean } = {}

		for _, skill in currentLayer do
			if visible[skill.id] and not visited[skill.id] then
				visited[skill.id] = true
				if not revealOnly or revealOnly[skill.id] then
					revealInfo[skill.id] = {
						depth = depth,
						order = order,
					}
					order += 1
				end

				for _, child in getSortedChildren(skill) do
					if visible[child.id] and not visited[child.id] and not nextLayerSeen[child.id] then
						nextLayerSeen[child.id] = true
						table.insert(nextLayer, child)
					end
				end
			end
		end

		table.sort(nextLayer, function(left: Skill, right: Skill): boolean
			if left.label == right.label then
				return left.id < right.id
			end

			return left.label < right.label
		end)

		currentLayer = nextLayer
		depth += 1
	end

	for _, skillId in getSkillIds() do
		if visible[skillId] and not visited[skillId] and (not revealOnly or revealOnly[skillId]) then
			revealInfo[skillId] = {
				depth = depth,
				order = order,
			}
			order += 1
		end
	end

	return revealInfo
end

local function computeVisibleDepths(visible: SkillIdMap): (NumberMap, number)
	local depths: NumberMap = {}
	local currentLayer = getSortedVisibleRoots(visible)
	local depth = 0
	local maxDepth = 0

	while #currentLayer > 0 do
		local nextLayer = {}
		local nextLayerSeen: { [string]: boolean } = {}

		for _, skill in currentLayer do
			if visible[skill.id] and depths[skill.id] == nil then
				depths[skill.id] = depth
				maxDepth = math.max(maxDepth, depth)

				for _, child in getSortedChildren(skill) do
					if visible[child.id] and depths[child.id] == nil and not nextLayerSeen[child.id] then
						nextLayerSeen[child.id] = true
						table.insert(nextLayer, child)
					end
				end
			end
		end

		table.sort(nextLayer, function(left: Skill, right: Skill): boolean
			if left.label == right.label then
				return left.id < right.id
			end

			return left.label < right.label
		end)

		currentLayer = nextLayer
		depth += 1
	end

	local fallbackDepth = maxDepth + 1
	local usedFallbackDepth = false
	for _, skillId in getSkillIds() do
		if visible[skillId] and depths[skillId] == nil then
			depths[skillId] = fallbackDepth
			usedFallbackDepth = true
		end
	end

	if usedFallbackDepth then
		maxDepth = fallbackDepth
	end

	return depths, maxDepth
end

local function getTemplateAnchorScalePosition(): Vector2
	local containerSize = skillTreeContainer.AbsoluteSize
	if containerSize.X <= 0 or containerSize.Y <= 0 then
		local position = skillButtonTemplate.Position
		return Vector2.new(position.X.Scale, position.Y.Scale)
	end

	local localTopLeft = skillButtonTemplate.AbsolutePosition - skillTreeContainer.AbsolutePosition
	local anchorOffset = Vector2.new(
		skillButtonTemplate.AbsoluteSize.X * skillButtonTemplate.AnchorPoint.X,
		skillButtonTemplate.AbsoluteSize.Y * skillButtonTemplate.AnchorPoint.Y
	)
	local anchorPosition = localTopLeft + anchorOffset

	return Vector2.new(anchorPosition.X / containerSize.X, anchorPosition.Y / containerSize.Y)
end

local function placeSkillAtLogicalPosition(
	skill: Skill,
	position: Vector2,
	logicalLayout: LayoutMap,
	occupied: { [string]: string }
): ()
	local existingPosition = logicalLayout[skill.id]
	if existingPosition then
		if existingPosition ~= position then
			warn(
				`[SkillTreeController] Skill "{skill.id}" has multiple explicit positions; keeping {existingPosition.X},{existingPosition.Y} and ignoring {position.X},{position.Y}`
			)
		end
		return
	end

	logicalLayout[skill.id] = position

	local positionKey = `{position.X},{position.Y}`
	local occupiedBy = occupied[positionKey]
	if occupiedBy and occupiedBy ~= skill.id then
		warn(`[SkillTreeController] Skill "{skill.id}" overlaps "{occupiedBy}" at explicit direction position {positionKey}`)
	else
		occupied[positionKey] = skill.id
	end
end

local function placeVisibleChildren(skill: Skill, visible: SkillIdMap, logicalLayout: LayoutMap, occupied: { [string]: string }): ()
	local parentPosition = logicalLayout[skill.id]

	for _, child in getSortedChildren(skill) do
		if visible[child.id] then
			placeSkillAtLogicalPosition(child, parentPosition + DIRECTION_GRID_OFFSETS[child.direction], logicalLayout, occupied)
			placeVisibleChildren(child, visible, logicalLayout, occupied)
		end
	end
end

local function computeLayout(visible: SkillIdMap): LayoutMap
	local logicalLayout: LayoutMap = {}
	local occupied: { [string]: string } = {}

	for _, root in getSortedVisibleRoots(visible) do
		placeSkillAtLogicalPosition(root, Vector2.zero, logicalLayout, occupied)
		placeVisibleChildren(root, visible, logicalLayout, occupied)
	end

	for _, skillId in getSkillIds() do
		if visible[skillId] and not logicalLayout[skillId] then
			local skill = tree:RequireSkill(skillId)
			warn(`[SkillTreeController] Skill "{skillId}" has no visible root path; placing it at the center`)
			placeSkillAtLogicalPosition(skill, Vector2.zero, logicalLayout, occupied)
		end
	end

	local layout: LayoutMap = {}
	local rootScalePosition = getTemplateAnchorScalePosition()
	local containerSize = skillTreeContainer.AbsoluteSize
	local hexFrame = skillButtonTemplate.Frame :: ImageLabel
	local hexSize = hexFrame.AbsoluteSize
	if hexSize.X <= 0 or hexSize.Y <= 0 then
		hexSize = skillButtonTemplate.AbsoluteSize
	end

	local hexRadius = math.min(hexSize.X / 2, hexSize.Y / SQRT_3) * 1
	local scaleStep = if containerSize.X > 0 and containerSize.Y > 0 and hexRadius > 0
		then Vector2.new((1.5 * hexRadius) / containerSize.X, ((SQRT_3 / 2) * hexRadius) / containerSize.Y)
		else Vector2.zero

	for skillId, position in logicalLayout do
		layout[skillId] = rootScalePosition + Vector2.new(position.X * scaleStep.X, position.Y * scaleStep.Y)
	end

	return layout
end

local function computeContentBounds(layout: LayoutMap, visible: SkillIdMap): PixelBounds
	local containerSize = skillTreeContainer.AbsoluteSize
	local nodeSize = skillButtonTemplate.AbsoluteSize
	local anchorPoint = skillButtonTemplate.AnchorPoint
	local minX = math.huge
	local minY = math.huge
	local maxX = -math.huge
	local maxY = -math.huge

	for skillId, scalePosition in layout do
		if visible[skillId] then
			local anchorPosition = Vector2.new(scalePosition.X * containerSize.X, scalePosition.Y * containerSize.Y)
			local topLeft = anchorPosition - Vector2.new(nodeSize.X * anchorPoint.X, nodeSize.Y * anchorPoint.Y)
			local bottomRight = topLeft + nodeSize

			minX = math.min(minX, topLeft.X)
			minY = math.min(minY, topLeft.Y)
			maxX = math.max(maxX, bottomRight.X)
			maxY = math.max(maxY, bottomRight.Y)
		end
	end

	if minX == math.huge then
		return {
			min = Vector2.zero,
			max = containerSize,
		}
	end

	return {
		min = Vector2.new(minX - nodeSize.X * NODE_PADDING_COUNT, minY - nodeSize.Y * NODE_PADDING_COUNT),
		max = Vector2.new(maxX + nodeSize.X * NODE_PADDING_COUNT, maxY + nodeSize.Y * NODE_PADDING_COUNT),
	}
end

local function getRevealStartPosition(skillId: string, layout: LayoutMap, visible: SkillIdMap, depths: NumberMap): UDim2
	local parents = parentsBySkillId[skillId]
	if not parents or #parents == 0 then
		local rootPosition = getTemplateAnchorScalePosition()
		return UDim2.fromScale(rootPosition.X, rootPosition.Y)
	end

	local selectedParentId: string? = nil
	local selectedParentDepth = math.huge
	local selectedParentOwned = false

	for _, parentId in parents do
		if visible[parentId] then
			local parentOwned = tree:RequireSkill(parentId).owned
			local parentDepth = depths[parentId] or math.huge

			if selectedParentId == nil
				or (parentOwned and not selectedParentOwned)
				or (parentOwned == selectedParentOwned and parentDepth < selectedParentDepth)
			then
				selectedParentId = parentId
				selectedParentDepth = parentDepth
				selectedParentOwned = parentOwned
			end
		end
	end

	if selectedParentId then
		local selectedParentPosition = layout[selectedParentId]
		return UDim2.fromScale(selectedParentPosition.X, selectedParentPosition.Y)
	end

	local rootPosition = getTemplateAnchorScalePosition()
	return UDim2.fromScale(rootPosition.X, rootPosition.Y)
end

local function applyButtonZIndex(button: ImageButton, zIndex: number): ()
	local templateZIndex = skillButtonTemplate.ZIndex
	button.ZIndex = zIndex

	for _, descendant in button:GetDescendants() do
		if descendant:IsA("GuiObject") then
			local relativeZIndex = descendant.ZIndex - templateZIndex
			descendant.ZIndex = math.max(1, zIndex + relativeZIndex)
		end
	end
end

local function applyNodeState(button: ImageButton, skill: Skill, preview: boolean): ()
	local available = isAvailable(skill)
	local frame = button.Frame :: ImageLabel
	local moneyDisplay = button.MoneyDisplay :: Frame
	local price = moneyDisplay.Amount :: TextLabel
	local priceIcon = moneyDisplay.Icon :: ImageLabel
	local name = button.NameLabel :: TextLabel
	local icon = button.Icon :: ImageLabel
	button.AutoButtonColor = available
	button.Active = available

	frame.ImageColor3 = Color3.new(1, 1, 1)
	frame.ImageTransparency = 0
	name.Text = skill.label
	name.Visible = true
	moneyDisplay.Visible = true
	price.Visible = true

	if skill.subTreeEntrance and not preview then
		local isReturnNode = skill.id == subTreeEntranceStack[#subTreeEntranceStack]
		button.AutoButtonColor = available or isReturnNode
		button.Active = available or isReturnNode
		if isReturnNode then
			frame.Image = NODE_IMAGES.BACK
			icon.Image = "rbxassetid://116466780169833"
			name.Text = "Back"
		else
			frame.Image = NODE_IMAGES.SUBTREE
			name.Text = skill.label
		end
		moneyDisplay.Visible = false
		price.Visible = false
		priceIcon.Visible = false
		price.AnchorPoint = CENTERED_MONEY_TEXT_ANCHOR
		price.Position = CENTERED_MONEY_TEXT_POSITION
	elseif preview then
		button.AutoButtonColor = false
		button.Active = false
		frame.Image = NODE_IMAGES.PREVIEW
		name.Visible = false
		moneyDisplay.Visible = false
		icon.Image = "rbxassetid://72080843632905"
		priceIcon.Visible = false
		price.AnchorPoint = CENTERED_MONEY_TEXT_ANCHOR
		price.Position = CENTERED_MONEY_TEXT_POSITION
	elseif skill.owned then
		frame.Image = NODE_IMAGES.OWNED
		price.Visible = false
		price.TextColor3 = Color3.fromRGB(255, 255, 255)
		priceIcon.Visible = false
		icon.Image = skill.imageId or ""
		price.AnchorPoint = CENTERED_MONEY_TEXT_ANCHOR
		price.Position = CENTERED_MONEY_TEXT_POSITION
	elseif available then
		frame.Image = NODE_IMAGES.UNOWNED
		local roundedPrice = math.max(0, math.floor(skill.price + 0.5))
		local requiresMoney = roundedPrice > 0
		icon.Image = skill.imageId or ""
		if roundedPrice == 0 then
			price.Text = "FREE"
		else
			price.Text = Gigantix.getShort(Gigantix.stringToNumber(tostring(roundedPrice)))
		end
		price.TextColor3 = Color3.fromRGB(118, 255, 151)
		priceIcon.Visible = requiresMoney
		price.AnchorPoint = if requiresMoney then skillButtonPriceDefaultAnchor else CENTERED_MONEY_TEXT_ANCHOR
		price.Position = if requiresMoney then skillButtonPriceDefaultPosition else CENTERED_MONEY_TEXT_POSITION
	else
		frame.Image = NODE_IMAGES.UNOWNED
		frame.ImageColor3 = Color3.fromRGB(95, 102, 126)
		frame.ImageTransparency = 0.35
		icon.Image = skill.imageId or ""
		price.Text = "LOCKED"
		price.TextColor3 = Color3.fromRGB(255, 91, 91)
		priceIcon.Visible = false
		price.AnchorPoint = CENTERED_MONEY_TEXT_ANCHOR
		price.Position = CENTERED_MONEY_TEXT_POSITION
	end
end

local function animateNodeReveal(button: ImageButton, originalSize: UDim2, revealInfo: RevealInfo, generation: number): ()
	button.Size = UDim2.fromScale(0, 0)
	task.delay(revealInfo.depth * REVEAL_LAYER_DELAY + revealInfo.order * REVEAL_NODE_DELAY, function()
		if generation ~= revealGeneration or not button.Parent then
			return
		end

		Spr.stop(button, "Size")
		popSoundPool:Play(nil, POP_SOUND_VOLUME_MULTIPLIER ^ revealInfo.order)
		Spr.target(button, REVEAL_DAMPING_RATIO, REVEAL_FREQUENCY, {
			Size = originalSize,
		})
	end)
end

local function updateNodeScale(skillId: string, animateAsPulse: boolean?): ()
	local button = renderedNodesBySkillId[skillId]
	if not button then
		return
	end

	local scale = 1
	local dampingRatio = NODE_SCALE_DAMPING_RATIO
	local frequency = NODE_SCALE_FREQUENCY

	if pressedSkillIds[skillId] then
		scale = NODE_CLICK_SCALE
	elseif hoveredSkillIds[skillId] then
		scale = NODE_HOVER_SCALE
	elseif (unlockPulseUntilBySkillId[skillId] or 0) > os.clock() then
		scale = NODE_UNLOCK_PULSE_SCALE
		dampingRatio = NODE_UNLOCK_PULSE_DAMPING_RATIO
		frequency = NODE_UNLOCK_PULSE_FREQUENCY
	elseif animateAsPulse then
		dampingRatio = NODE_UNLOCK_PULSE_DAMPING_RATIO
		frequency = NODE_UNLOCK_PULSE_FREQUENCY
	end

	local frame = button.Frame :: ImageLabel
	local baseSize = frameBaseSizesBySkillId[skillId]
	Spr.target(frame, dampingRatio, frequency, {
		Size = UDim2.new(
			baseSize.X.Scale * scale,
			baseSize.X.Offset * scale,
			baseSize.Y.Scale * scale,
			baseSize.Y.Offset * scale
		),
	})
end

local function getUnlockPulseLayers(skillId: string): { { string } }
	local layers: { { string } } = {}
	local seenSkillIds: SkillIdMap = {}

	local function addSkillToLayer(layerIndex: number, pulseSkillId: string): ()
		if seenSkillIds[pulseSkillId] or not renderedNodesBySkillId[pulseSkillId] then
			return
		end

		seenSkillIds[pulseSkillId] = true
		layers[layerIndex] = layers[layerIndex] or {}
		table.insert(layers[layerIndex], pulseSkillId)
	end

	addSkillToLayer(1, skillId)

	local parentLayer: { string } = parentsBySkillId[skillId] or {}
	local childLayer: { Skill } = getSortedChildren(tree:RequireSkill(skillId))
	local layerIndex = 2

	while #parentLayer > 0 or #childLayer > 0 do
		local nextParentLayer: { string } = {}
		local nextChildLayer: { Skill } = {}

		for _, parentId in parentLayer do
			addSkillToLayer(layerIndex, parentId)

			local grandparentIds = parentsBySkillId[parentId]
			if grandparentIds then
				for _, grandparentId in grandparentIds do
					table.insert(nextParentLayer, grandparentId)
				end
			end
		end

		for _, child in childLayer do
			addSkillToLayer(layerIndex, child.id)

			if renderedNodesBySkillId[child.id] then
				for _, grandchild in getSortedChildren(child) do
					table.insert(nextChildLayer, grandchild)
				end
			end
		end

		parentLayer = nextParentLayer
		childLayer = nextChildLayer
		layerIndex += 1
	end

	return layers
end

local function pulseNode(skillId: string, volumeScale: number): ()
	local pulseEndsAt = os.clock() + NODE_UNLOCK_PULSE_SECONDS
	unlockPulseUntilBySkillId[skillId] = math.max(unlockPulseUntilBySkillId[skillId] or 0, pulseEndsAt)
	popSoundPool:Play(nil, volumeScale)
	updateNodeScale(skillId, true)

	task.delay(NODE_UNLOCK_PULSE_SECONDS, function()
		if (unlockPulseUntilBySkillId[skillId] or 0) > os.clock() then
			return
		end

		unlockPulseUntilBySkillId[skillId] = nil
		updateNodeScale(skillId, true)
	end)
end

local function pulseUnlock(skillId: string): ()
	local pulseIndex = 0

	for layerIndex, layer in getUnlockPulseLayers(skillId) do
		task.delay((layerIndex - 1) * NODE_UNLOCK_PULSE_LAYER_DELAY, function()
			for _, pulseSkillId in layer do
				pulseIndex += 1
				pulseNode(pulseSkillId, POP_SOUND_VOLUME_MULTIPLIER ^ (pulseIndex - 1))
			end
		end)
	end
end

local function transitionTreeView(nextSubTreeEntranceStack: { string }, anchorSkillId: string, anchorLocalPosition: Vector2): ()
	treeViewTransitionGeneration += 1
	revealGeneration += 1
	treeViewTransitioning = true
	local transitionGeneration = treeViewTransitionGeneration

	for _, button in renderedNodes do
		Spr.stop(button)
		Spr.target(button, REVEAL_DAMPING_RATIO, REVEAL_FREQUENCY, {
			Size = UDim2.fromScale(0, 0),
		})
	end

	task.delay(TREE_VIEW_HIDE_SECONDS, function()
		if transitionGeneration ~= treeViewTransitionGeneration then
			return
		end

		subTreeEntranceStack = nextSubTreeEntranceStack
		treeViewTransitioning = false
		rebuildCounterBadgeCandidates()

		local nextVisibleSkillIds = computeVisibleSkillIds()
		local nextLayout = computeLayout(nextVisibleSkillIds)
		local nextAnchorScalePosition = nextLayout[anchorSkillId]
		if nextAnchorScalePosition then
			local containerSize = skillTreeContainer.AbsoluteSize
			local nextAnchorPosition = Vector2.new(
				nextAnchorScalePosition.X * containerSize.X,
				nextAnchorScalePosition.Y * containerSize.Y
			)
			local templateFrame = skillButtonTemplate.Frame :: GuiObject
			local templateButtonSize = skillButtonTemplate.AbsoluteSize
			local templateButtonAnchor = skillButtonTemplate.AbsolutePosition
				+ Vector2.new(
					templateButtonSize.X * skillButtonTemplate.AnchorPoint.X,
					templateButtonSize.Y * skillButtonTemplate.AnchorPoint.Y
				)
			local templateFrameSize = templateFrame.AbsoluteSize
			local templateFrameCenter = templateFrame.AbsolutePosition
				+ Vector2.new(templateFrameSize.X / 2, templateFrameSize.Y / 2)
			local templateFrameCenterOffset = templateFrameCenter - templateButtonAnchor

			pan = anchorLocalPosition - (nextAnchorPosition + templateFrameCenterOffset) * zoom
			contentBounds = computeContentBounds(nextLayout, nextVisibleSkillIds)
			pan = clampPan(pan)
			treeContentFrame.Position = UDim2.fromOffset(math.round(pan.X), math.round(pan.Y))
		end

		refreshTree(true)
	end)
end

local function animateNodePosition(
	button: ImageButton,
	targetPosition: UDim2,
	startPosition: UDim2?,
	revealInfo: RevealInfo?,
	generation: number
): ()
	if not startPosition
		or (
			startPosition.X.Scale == targetPosition.X.Scale
			and startPosition.X.Offset == targetPosition.X.Offset
			and startPosition.Y.Scale == targetPosition.Y.Scale
			and startPosition.Y.Offset == targetPosition.Y.Offset
		)
	then
		button.Position = targetPosition
		return
	end

	button.Position = startPosition
	task.delay(if revealInfo then revealInfo.depth * REVEAL_LAYER_DELAY + revealInfo.order * REVEAL_NODE_DELAY else 0, function()
		if generation ~= revealGeneration or not button.Parent then
			return
		end

		Spr.stop(button, "Position")
		Spr.target(button, POSITION_DAMPING_RATIO, POSITION_FREQUENCY, {
			Position = targetPosition,
		})
	end)
end

local function createNode(
	skill: Skill,
	layout: LayoutMap,
	revealInfo: RevealInfo?,
	generation: number,
	previousPosition: UDim2?,
	visible: SkillIdMap,
	preview: boolean,
	depths: NumberMap,
	maxDepth: number
): ImageButton
	local button = skillButtonTemplate:Clone()
	local originalSize = button.Size
	local scalePosition = layout[skill.id]
	local targetPosition = UDim2.fromScale(scalePosition.X, scalePosition.Y)
	local startPosition = if revealInfo then getRevealStartPosition(skill.id, layout, visible, depths) else previousPosition
	local frame = button.Frame :: ImageLabel

	button.Name = skill.id
	button.Visible = true
	button.Position = targetPosition
	if skill.subTreeEntrance and not preview and skill.id ~= subTreeEntranceStack[#subTreeEntranceStack] then
		local badge = counterBadgeTemplate:Clone()
		local hexRadius = math.min(frame.Size.X.Scale / 2, frame.Size.Y.Scale / SQRT_3) * 0.85
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(
			frame.Position.X.Scale + 0.75 * hexRadius,
			frame.Position.Y.Scale - (SQRT_3 / 4) * hexRadius
		)
		badge.Visible = false
		badge.Parent = button
		for i, v in pairs(badge:GetDescendants()) do
			if v:IsA("GuiObject") then
				v.ZIndex = v.ZIndex + 50
			end
		end
		subtreeCounterBadgesByEntranceId[skill.id] = badge
	end
	applyButtonZIndex(
		button,
		skillButtonTemplate.ZIndex + (maxDepth - (depths[skill.id] or maxDepth) + 1) * ZINDEX_LAYER_STEP
	)
	button.Parent = treeContentFrame
	animateNodePosition(button, targetPosition, startPosition, revealInfo, generation)

	if skill.imageId then
		local icon = button.Icon :: ImageLabel
		icon.Image = skill.imageId
	end

	applyNodeState(button, skill, preview)

	if revealInfo then
		animateNodeReveal(button, originalSize, revealInfo, generation)
	end

	button.MouseEnter:Connect(function()
		hoveredSkillIds[skill.id] = true
		showSkillInfo(skill, frame)
		updateNodeScale(skill.id)
	end)

	button.MouseLeave:Connect(function()
		hoveredSkillIds[skill.id] = nil
		if hoveredTooltipSkillId == skill.id then
			hoveredTooltipSkillId = nil
			skillInfoFrame.Visible = false
		end
		updateNodeScale(skill.id)
	end)

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			UIsfx.UIDown:Play()
			pressedSkillIds[skill.id] = true
			updateNodeScale(skill.id)
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressedSkillIds[skill.id] = nil
			updateNodeScale(skill.id)
		end
	end)

	button.Activated:Connect(function()
		if treeViewTransitioning or os.clock() < suppressClickUntil then
			return
		end

		if skill.subTreeEntrance then
			local nextSubTreeEntranceStack: { string } = {}
			local activeEntranceId = subTreeEntranceStack[#subTreeEntranceStack]

			if skill.id == activeEntranceId then
				for index = 1, #subTreeEntranceStack - 1 do
					table.insert(nextSubTreeEntranceStack, subTreeEntranceStack[index])
				end
			else
				if not isAvailable(skill) then
					return
				end

				for _, entranceId in subTreeEntranceStack do
					table.insert(nextSubTreeEntranceStack, entranceId)
				end
				table.insert(nextSubTreeEntranceStack, skill.id)
			end

			local frameSize = frame.AbsoluteSize
			local frameCenter = frame.AbsolutePosition
				- skillTreeContainer.AbsolutePosition
				+ Vector2.new(frameSize.X / 2, frameSize.Y / 2)
			transitionTreeView(nextSubTreeEntranceStack, skill.id, frameCenter)
			return
		end

		if not isAvailable(skill) then
			return
		end

		pulseUnlock(skill.id)

		if not skill.owned then
			if pendingUnlockSkillIds[skill.id] then
				return
			end

			pendingUnlockSkillIds[skill.id] = true
			local previousVisibleSkillIds = visibleSkillIds
			local result = requestUnlockSkill(skill.id)
			pendingUnlockSkillIds[skill.id] = nil

			if not result then
				return
			end

			if result.ownedSkills then
				applyOwnedSkills(result.ownedSkills)
			end

			if not result.success then
				if result.message then
					warn(`[SkillTreeController] Could not unlock skill "{skill.id}": {result.message}`)
				end
				refreshTree(false)
				return
			end

			UIsfx.Success:Play()
			rebuildCounterBadgeCandidates()
			local nextVisibleSkillIds = (computeVisibleSkillIds())
			refreshTree(false, getNewlyVisibleSkillIds(previousVisibleSkillIds, nextVisibleSkillIds))
		end
	end)

	table.insert(renderedNodes, button)
	renderedNodesBySkillId[skill.id] = button
	frameBaseSizesBySkillId[skill.id] = frame.Size
	updateNodeScale(skill.id)
	return button
end

local function clearRenderedTree(): ()
	revealGeneration += 1
	hoveredSkillIds = {}
	pressedSkillIds = {}
	hoveredTooltipSkillId = nil
	skillInfoFrame.Visible = false

	for _, button in renderedNodes do
		local frame = button.Frame :: ImageLabel
		Spr.stop(button)
		Spr.stop(frame, "Size")
		button:Destroy()
	end
	renderedNodes = {}
	renderedNodesBySkillId = {}
	frameBaseSizesBySkillId = {}
	subtreeCounterBadgesByEntranceId = {}
end

refreshTree = function(animateReveal: boolean?, revealOnlySkillIds: SkillIdMap?): ()
	local previousNodePositions: { [string]: UDim2 } = {}
	for _, button in renderedNodes do
		previousNodePositions[button.Name] = button.Position
	end

	local shouldAnimateLayout = animateReveal == true or revealOnlySkillIds ~= nil

	clearRenderedTree()
	local containerSize = skillTreeContainer.AbsoluteSize
	treeContentFrame.Size = UDim2.fromOffset(containerSize.X, containerSize.Y)

	local nextVisibleSkillIds, nextPreviewSkillIds = computeVisibleSkillIds()
	local layout = computeLayout(nextVisibleSkillIds)
	visibleSkillIds = nextVisibleSkillIds
	local visibleDepths, maxVisibleDepth = computeVisibleDepths(nextVisibleSkillIds)
	local revealInfoBySkillId = if animateReveal == true or revealOnlySkillIds ~= nil
		then computeRevealInfo(nextVisibleSkillIds, revealOnlySkillIds)
		else nil
	local generation = revealGeneration
	contentBounds = computeContentBounds(layout, nextVisibleSkillIds)
	applyViewportTransform(shouldAnimateLayout)

	for _, skillId in getSkillIds() do
		if nextVisibleSkillIds[skillId] then
			local revealInfo = if revealInfoBySkillId then revealInfoBySkillId[skillId] else nil
			createNode(
				tree:RequireSkill(skillId),
				layout,
				revealInfo,
				generation,
				previousNodePositions[skillId],
				nextVisibleSkillIds,
				nextPreviewSkillIds[skillId] == true,
				visibleDepths,
				maxVisibleDepth
			)
		end
	end

	refreshCounterBadges()
end

local function connectViewportInput(): ()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if pinching then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local screenPoint = Vector2.new(input.Position.X, input.Position.Y)
		local point = screenPoint - skillTreeContainer.AbsolutePosition
		local containerSize = skillTreeContainer.AbsoluteSize
		if point.X < 0 or point.X > containerSize.X or point.Y < 0 or point.Y > containerSize.Y then
			return
		end

		Spr.stop(treeContentFrame, "Position")
		local position = treeContentFrame.Position
		pan = Vector2.new(position.X.Offset, position.Y.Offset)
		dragging = true
		dragInput = input
		dragStartScreenPoint = screenPoint
		dragStartPan = pan
		dragMoved = false
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local screenPoint = Vector2.new(input.Position.X, input.Position.Y)
			local point = screenPoint - skillTreeContainer.AbsolutePosition
			local containerSize = skillTreeContainer.AbsoluteSize
			if input.Position.Z ~= 0
				and point.X >= 0
				and point.X <= containerSize.X
				and point.Y >= 0
				and point.Y <= containerSize.Y
			then
				setZoomAtScreenPoint(zoom * (SCROLL_ZOOM_STEP ^ input.Position.Z), screenPoint)
			end

			return
		end

		if not dragging or pinching then
			return
		end

		if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch then
			if input ~= dragInput then
				return
			end

			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartScreenPoint
			if delta.Magnitude >= DRAG_CLICK_SUPPRESSION_DISTANCE then
				dragMoved = true
			end

			pan = dragStartPan + delta
			applyViewportTransform()
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartScreenPoint
			if delta.Magnitude >= DRAG_CLICK_SUPPRESSION_DISTANCE then
				dragMoved = true
			end

			pan = dragStartPan + delta
			applyViewportTransform()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if not dragging then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput then
			if dragMoved then
				suppressClickUntil = os.clock() + DRAG_CLICK_SUPPRESSION_SECONDS
			end

			dragging = false
			dragInput = nil
			dragMoved = false
		end
	end)

	UserInputService.TouchPinch:Connect(function(touchPositions, scale, _velocity, state)
		if #touchPositions == 0 then
			return
		end

		local screenPoint = Vector2.zero
		for _, touchPosition in touchPositions do
			screenPoint += touchPosition
		end
		screenPoint /= #touchPositions

		if state == Enum.UserInputState.Begin then
			local point = screenPoint - skillTreeContainer.AbsolutePosition
			local containerSize = skillTreeContainer.AbsoluteSize
			if point.X < 0 or point.X > containerSize.X or point.Y < 0 or point.Y > containerSize.Y then
				return
			end

			if dragging then
				if dragMoved then
					suppressClickUntil = os.clock() + DRAG_CLICK_SUPPRESSION_SECONDS
				end

				dragging = false
				dragInput = nil
				dragMoved = false
			end

			pinching = true
			pinchStartZoom = zoom
		elseif state == Enum.UserInputState.Change then
			if pinching then
				setZoomAtScreenPoint(pinchStartZoom * scale, screenPoint)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			pinching = false
		end
	end)
end

function SkillTreeController:ShowSkillTree(): ()
	local uiController = self.Controllers.UIController
	local shouldOpen = uiController.CurrentDisplay ~= skillTreeContainer

	upgradeGui.Enabled = true
	upgradeGuiHotbar.Visible = true
	uiController:OpenFrame(skillTreeContainer, false)

	if shouldOpen and uiController.CurrentDisplay == skillTreeContainer then
		subTreeEntranceStack = {}
		zoom = 1
		pan = Vector2.zero
		refreshTree(true)
	end
end

function SkillTreeController:HideSkillTree(): ()
	hoveredTooltipSkillId = nil
	skillInfoFrame.Visible = false
	self.Controllers.UIController:CloseFrames()
end

function SkillTreeController:Init(controllers)
	self.Controllers = controllers
	buildParentLookup()
	skillTreeContainer.Active = true
	skillTreeContainer.ClipsDescendants = true
	skillButtonTemplate.Visible = false

	upgradeGui.Enabled = false
	upgradeGuiHotbar.Visible = false
	skillTreeContainer.Visible = false
	skillInfoFrame.Visible = false

	openUpgradesButton.Activated:Connect(function()
		self:ShowSkillTree()
	end)

	hideUpgradesButton.Activated:Connect(function()
		self:HideSkillTree()
	end)

	self.Controllers.UIController.Signals.DisplayChanged:Connect(function(newFrame)
		local isOpen = newFrame == skillTreeContainer
		upgradeGui.Enabled = isOpen
		upgradeGuiHotbar.Visible = isOpen

		if not isOpen then
			hoveredTooltipSkillId = nil
			skillInfoFrame.Visible = false
			skillTreeContainer.Visible = false
		end
	end)

	ownedSkillsChangedRemote.OnClientEvent:Connect(function(ownedSkills)
		local previousVisibleSkillIds = visibleSkillIds
		applyOwnedSkills(ownedSkills)
		rebuildCounterBadgeCandidates()
		local nextVisibleSkillIds = (computeVisibleSkillIds())
		refreshTree(false, getNewlyVisibleSkillIds(previousVisibleSkillIds, nextVisibleSkillIds))
	end)
end

function SkillTreeController:Start()
	if started then
		return
	end

	started = true
	while skillTreeContainer.AbsoluteSize.X <= 0 or skillTreeContainer.AbsoluteSize.Y <= 0 do
		RunService.RenderStepped:Wait()
	end

	while player:GetAttribute("Loaded") ~= true do
		player:GetAttributeChangedSignal("Loaded"):Wait()
	end

	applyOwnedSkills(requestOwnedSkills())
	rebuildCounterBadgeCandidates()
	refreshTree()
	connectViewportInput()
	player:GetAttributeChangedSignal(UPGRADE_CURRENCY_ATTRIBUTE):Connect(function()
		if counterBadgeRefreshQueued then
			return
		end

		counterBadgeRefreshQueued = true
		RunService.RenderStepped:Once(function()
			counterBadgeRefreshQueued = false
			refreshCounterBadges()
		end)
	end)

	skillTreeContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		refreshTree()
	end)
end

return SkillTreeController
