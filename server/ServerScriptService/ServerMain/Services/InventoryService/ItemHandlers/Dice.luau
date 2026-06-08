local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	BoostsUpdated = remotesFolder.Boosts:WaitForChild("BoostsUpdated"),
}

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets.ItemDefinitions)

type DiceDefinition = ItemDefinitions.DiceDefinition

local Dice = {}

function Dice.Use(player, services, diceName)
	local diceDef: DiceDefinition = ItemDefinitions[diceName]
	if not diceDef then
		warn("Invalid dice name:", diceName)
		return false
	end
	
	local profile = services.DataService:GetProfile(player)
	if not profile then  
		warn("No profile for player:", player)
		return false
	end
	
	local queuedDice = profile.Rolling.QueuedDice
	if not queuedDice then profile.Rolling.QueuedDice = {} end
	
	-- Add dice to queue
	local existingEntry = nil
	for _, diceEntry in queuedDice do
		if diceEntry.diceName == diceName then
			existingEntry = diceEntry
			break
		end
	end
	
	if existingEntry then
		existingEntry.amount += 1
	else
		table.insert(queuedDice, {
			diceName = diceName,
			amount = 1
		})
	end
	
	-- update clinet
	services.RollService:SendUpdatedRollingData(player)
	
	print("Dice used:", diceName)
	return true 
end

return Dice