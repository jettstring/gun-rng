local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyAssets = ReplicatedStorage.GameAssets:WaitForChild("EnemyAssets")
local EnemyModels = EnemyAssets:WaitForChild("EnemyModels")
local ServerAgents = EnemyAssets:WaitForChild("ServerAgent")



export type EnemyVariant = "Normal" | "Big" | "Shiny" | "Inverted"

export type EnemyDefinition = {
	id: EnemyVariant,
	label: string,
	description: string,
	model: Model,
	agentModel: Model,
	deathAudioId: string,
	health: number,
	walkSpeed: number,
	cashReward: number,
	tagReward: number,
	baseSpawnChance: number?,
	itemDropNames: { string },
}

local NormalModel = EnemyModels:WaitForChild("Enemy") :: Model
local BigModel = EnemyModels:WaitForChild("Big Enemy") :: Model
local ShinyModel = EnemyModels:WaitForChild("Shiny Enemy") :: Model
local InvertedModel = EnemyModels:WaitForChild("Inverted Enemy") :: Model

local NormalAgent = ServerAgents:WaitForChild("Enemy") :: Model
local BigAgent = ServerAgents:WaitForChild("Big Enemy") :: Model
local ShinyAgent = ServerAgents:WaitForChild("Shiny Enemy") :: Model
local InvertedAgent = ServerAgents:WaitForChild("Inverted Enemy") :: Model

local module: { [EnemyVariant]: EnemyDefinition } = {
	Normal = {
		id = "Normal",
		label = "Enemy",
		description = "Baseline enemy.",
		model = NormalModel,
		agentModel = NormalAgent,
		deathAudioId = "rbxassetid://127812892911570",
		health = 100,
		walkSpeed = 4,
		cashReward = 10,
		tagReward = 0,
		baseSpawnChance = 1,
		itemDropNames = {
			"Smart",
			"Incendiary",
			"Explosive",
			"Scrap",
		},
	},

	Big = {
		id = "Big",
		label = "Big Enemy",
		description = "High-health enemy with a larger reward.",
		model = BigModel,
		agentModel = BigAgent,
		deathAudioId = "rbxassetid://127812892911570",
		health = 1000,
		walkSpeed = 3,
		cashReward = 50,
		tagReward = 1,
		baseSpawnChance = 0,
		itemDropNames = {
			"Luck Potion",
			"Money Potion",
			"Smart",
			"Scrap",
			"Tech",
		},
	},

	Shiny = {
		id = "Shiny",
		label = "Shiny Enemy",
		description = "Rare enemy with improved rewards.",
		model = ShinyModel,
		agentModel = ShinyAgent,
		deathAudioId = "rbxassetid://83888055007568",

		--deathAudioId = "rbxassetid://127812892911570",
		health = 2000,
		walkSpeed = 4,
		cashReward = 250,
		tagReward = 2,
		baseSpawnChance = 0,
		itemDropNames = {
			"Luck Potion",
			"Money Potion",
			"Roll Speed Potion",
			"Smart",
			"Incendiary",
			"Scrap",
			"Tech",
		},
	},

	Inverted = {
		id = "Inverted",
		label = "Inverted Enemy",
		description = "Very rare enemy with the best rewards.",
		model = InvertedModel,
		agentModel = InvertedAgent,
		deathAudioId = "rbxassetid://88066567098633",
		health = 5000,
		walkSpeed = 7,
		cashReward = 1250,
		tagReward = 4,
		baseSpawnChance = 0,
		itemDropNames = {
			"Luck Potion",
			"Super Luck Potion",
			"Roll Speed Potion",
			"Money Potion",
			"Smart",
			"Incendiary",
			"Explosive",
			"Scrap",
			"Tech",
			"Crystal"
		},
	},
}

return module
