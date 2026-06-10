export type WeaponMutation = "BIG" | "Shiny" | "Inverted"

export type MutationRollChances = {[WeaponMutation]: number}

local MutationDefinitions = {}

MutationDefinitions.RollChances = {
	BIG = 0.35,
	Shiny = 0.15,
	Inverted = 0.05,
} :: MutationRollChances

MutationDefinitions.DamageMultipliers = {
	BIG = 1.5,
	Shiny = 2.5,
	Inverted = 4,
}

return MutationDefinitions