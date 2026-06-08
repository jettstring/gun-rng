local ReplicatedStorage = game:GetService("ReplicatedStorage") 

local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)

local WeaponAssets = ReplicatedStorage.GameAssets.WeaponAssets
local WeaponDefinitions = require(WeaponAssets.WeaponDefinitions)
local RarityGradients = WeaponAssets.RarityGradients
local MutationDefinitions = require(ReplicatedStorage.GameAssets.WeaponAssets.MutationDefinitions)

local utils = ReplicatedStorage.Util
local InventoryUtil = require(utils.InventoryUtil)

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type Rarity = WeaponDefinitions.Rarity

type WeaponData = InventoryUtil.WeaponData
type Mutations = InventoryUtil.Mutations

export type DerivedWeaponStats = {
	damage: number,
	level: number,
}

local WeaponsUtil = {}

local RARITY_THRESHOLDS: { { rarity: Rarity, roof: number } } = {
	{ rarity = "Uncommon",  roof = 1/5 },
	{ rarity = "Rare",      roof = 1/50 },
	{ rarity = "Legendary", roof = 1/100 },
	{ rarity = "Mythic",    roof = 1/1_000 },
	{ rarity = "Secret",    roof = 1/10_000 },
	{ rarity = "Godly",     roof = 1/100_000 },
}

local function getMutationDamageMultiplier(mutations: Mutations): number
	local multiplier = 1
	for mutation in mutations do
		multiplier *= MutationDefinitions.DamageMultipliers[mutation] or 1
	end

	return multiplier
end

function WeaponsUtil.getWeaponDefinition(weaponName: string): WeaponDefinition
	return WeaponDefinitions[weaponName]
end

function WeaponsUtil.deriveWeaponStats(weaponData: WeaponData): DerivedWeaponStats
	local weaponDef = WeaponsUtil.getWeaponDefinition(weaponData.weaponName)
	local DAMAGE_GROWTH_PER_LEVEL = 0.1
	local level = InventoryUtil.getLevelFromXP(weaponData.xp)
	local damagePerLevel = math.ceil(weaponDef.damage * DAMAGE_GROWTH_PER_LEVEL)
	local leveledDamage = weaponDef.damage + (level - 1) * damagePerLevel
	local damage = leveledDamage * getMutationDamageMultiplier(weaponData.mutations)
	return {
		damage = damage,
		level = level,
	}
end 


function WeaponsUtil.getWeaponName(weaponName: string, mutations: Mutations): string
	local weaponDef = WeaponsUtil.getWeaponDefinition(weaponName)
	local MUTATION_LABEL_ORDER = { "Inverted", "Shiny", "BIG" }
	
	local parts = {}
	if mutations then
		for _, mutationName in MUTATION_LABEL_ORDER do
			if mutations[mutationName] then
				table.insert(parts, mutationName)
			end
		end
	end

	table.insert(parts, weaponName)
	return table.concat(parts, " ")
end

function WeaponsUtil.deriveRarity(weaponName, mutations: Mutations): Rarity
	mutations = mutations or {}
	local weaponDef = WeaponsUtil.getWeaponDefinition(weaponName)
	if not weaponDef then
		warn("WeaponUtil.deriveRarity: No weapon definition for", weaponName)
		return nil
	end

	local mutationMulti = 1
	for mutationName in mutations do
		mutationMulti *= MutationDefinitions.RollChances[mutationName] or 1
	end

	local odds = weaponDef.odds * mutationMulti

	-- Default to the rarest tier so anything rarer than the smallest roof clamps to Godly.
	local result: Rarity = "Godly"
	for _, tier in RARITY_THRESHOLDS do
		if tier.roof <= odds then
			result = tier.rarity
			break
		end
	end

	return result
end

function WeaponsUtil.getDisplayImageLabel(weaponName: string, mutations: Mutations): ImageLabel
	local weaponDef = WeaponsUtil.getWeaponDefinition(weaponName) 
	if not weaponDef then return nil end
	
	-- create 
	local containerFrame = Instance.new("Frame")
	containerFrame.Name = "WeaponIconFrame"
	containerFrame.Size = UDim2.fromScale(1, 1)
	containerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	containerFrame.Position = UDim2.fromScale(0.5, 0.5)
	containerFrame.BackgroundColor3 = Color3.fromRGB(21, 23, 48)
	containerFrame.BackgroundTransparency = 1
	containerFrame.ClipsDescendants = true
	
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Parent = containerFrame
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	imageLabel.Position = UDim2.fromScale(0.5, 0.5)
	imageLabel.BackgroundTransparency = 1
	imageLabel.Image = "rbxassetid://" .. weaponDef.displayImages["Base"] 
	imageLabel.ZIndex = 2
	
	if mutations and mutations.Inverted then
		imageLabel.ImageColor3 = Color3.new(0, 0.898039, 1)
		imageLabel.Image = "rbxassetid://" .. weaponDef.displayImages["Base"] -- TODO: read inverted
	else
		imageLabel.ImageColor3 = Color3.new(1, 1, 1)
		imageLabel.Image = "rbxassetid://" .. weaponDef.displayImages["Base"]
	end
	
	if mutations and mutations.Shiny then
		local shinyOverlay = script:WaitForChild("ShinyOverlay"):Clone()
		shinyOverlay.Parent = containerFrame
		
		local shinyShadow = script:WaitForChild("ShinyShadow"):Clone()
		shinyShadow.Parent = containerFrame
	end
	
	if mutations and mutations.BIG then
		containerFrame.Transparency = 0
		containerFrame.Size = UDim2.fromScale(0.85, 0.85)
		imageLabel.Size = UDim2.fromScale(2, 2)
		
		-- add stroke
		local stroke = Instance.new("UIStroke")
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
		stroke.LineJoinMode = Enum.LineJoinMode.Miter
		stroke.Thickness = 0.07
		stroke.Parent = containerFrame
	end
	
	
	return containerFrame
end

function WeaponsUtil.applyRarityTextEffects(textLabel: TextLabel, rarity): ()
	if not textLabel or not rarity then return end
	
	local rarityEffects = RarityGradients:FindFirstChild(rarity)
	if not rarityEffects then return end
	
	local UIGradient = rarityEffects:FindFirstChildWhichIsA("UIGradient")
	if not UIGradient then return end
	
	if textLabel:FindFirstChildWhichIsA("UIGradient") then
		textLabel:FindFirstChildWhichIsA("UIGradient"):Destroy()
	end
	UIGradient:Clone().Parent = textLabel
	
	local UIStroke = textLabel:FindFirstChildWhichIsA("UIStroke")
	if UIStroke then
		local rarityStroke = rarityEffects:FindFirstChildWhichIsA("UIStroke")
		if rarityStroke then
			UIStroke.Color = rarityStroke.Color
		end
	end
end

function WeaponsUtil.displayWeaponInfo(weaponInfoDisplay: Frame, weaponData: WeaponData)
	if not weaponInfoDisplay or not weaponData then return end
	
	local weaponName = weaponData.weaponName
	local weaponDef = WeaponsUtil.getWeaponDefinition(weaponName)
	if not weaponDef then return end
	
	local nameLabel = weaponInfoDisplay:FindFirstChild("NameLabel")
	local rarityLabel = weaponInfoDisplay:FindFirstChild("RarityLabel")
	local statsDisplay = weaponInfoDisplay:FindFirstChild("StatsDisplay")
	local levelDisplay = weaponInfoDisplay:FindFirstChild("LevelDisplay")
	local xpMeter = levelDisplay:FindFirstChild("XPMeter")
	
	local derivedWeaponStats: DerivedWeaponStats = WeaponsUtil.deriveWeaponStats(weaponData)
	local currentLevel = derivedWeaponStats.level

	-- name
	if nameLabel then nameLabel.Text = WeaponsUtil.getWeaponName(weaponData.weaponName, weaponData.mutations) end
	
	-- rarity
	if rarityLabel then
		rarityLabel.Text = WeaponsUtil.deriveRarity(weaponData.weaponName, weaponData.mutations)
		WeaponsUtil.applyRarityTextEffects(rarityLabel, WeaponsUtil.deriveRarity(weaponData.weaponName, weaponData.mutations))
	end
	
	-- level
	if levelDisplay then
		local requiredXP = InventoryUtil.getNextLevelXPRequirement(weaponData)
		local currentXP = weaponData.xp
		local progress = math.clamp(currentXP / requiredXP, 0, 1)
		levelDisplay.LevelLabel.Text = string.format("Level %s", currentLevel)
		xpMeter.Fill.FillGradient.Offset = Vector2.new(math.map(progress, 0, 1, -0.5, 0.5), 0)
		xpMeter.AmountLabel.Text = string.format([[%s <font color="rgb(0, 153, 255)" weight="900">xp</font> / %s <font color="rgb(0, 153, 255)" weight="900">xp</font>]],
			Abbreviate.AbbreviateNumber(currentXP), Abbreviate.AbbreviateNumber(requiredXP)
		)
		xpMeter.Visible = currentLevel ~= 1
	end	
	
	-- stats
	if statsDisplay then
		for _, statFrame in statsDisplay:GetChildren() do
			if statFrame:IsA("Frame") then
				if statFrame.Name == "Damage" then
					statFrame.AmountLabel.Text = Abbreviate.AbbreviateNumber(derivedWeaponStats.damage, 1)
				elseif statFrame.Name == "FireRate" then
					statFrame.AmountLabel.Text = string.format("%ss", weaponDef.tbs)
				end
			end
		end
	end
end


function WeaponsUtil.getSortedWeapons(): {string}
	local sorted = {}
	for weaponName in WeaponDefinitions do
		table.insert(sorted, weaponName)
	end
	table.sort(sorted, function(a, b)
		return WeaponDefinitions[a].odds > WeaponDefinitions[b].odds
	end)

	return sorted
end


return WeaponsUtil
