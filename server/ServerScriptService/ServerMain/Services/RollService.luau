local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local GameAssets = ReplicatedStorage.GameAssets
local WeaponAssets = GameAssets.WeaponAssets
local WeaponDefinitions = require(WeaponAssets.WeaponDefinitions)
local MutationDefinitions = require(WeaponAssets.MutationDefinitions)

local RollAssets = GameAssets.RollAssets
local SpecialRollDefinitions = require(RollAssets.SpecialRollDefinitions)

local ItemDefinitions = require(ReplicatedStorage.GameAssets.ItemAssets.ItemDefinitions)

local utils = ReplicatedStorage:WaitForChild("Util")
local RollUtil = require(utils.RollUtil)
local WeaponUtil = require(utils.WeaponUtil)
local RebirthUtil = require(utils.RebirthUtil)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	AttemptRoll = remotesFolder.Roll:WaitForChild("AttemptRoll"),
	RollResult = remotesFolder.Roll:WaitForChild("RollResult"),
	ToggleAutoRoll = remotesFolder.Roll:WaitForChild("ToggleAutoRoll"),
	LuckDataUpdated = remotesFolder.Roll:WaitForChild("LuckDataUpdated"),
	RollTimeUpdated = remotesFolder.Roll:WaitForChild("RollTimeUpdated"),
	PauseSpecialRoll = remotesFolder.Roll:WaitForChild("PauseSpecialRoll"),
	RollingDataUpdated = remotesFolder.Roll:WaitForChild("RollingDataUpdated"),
	RemoveQueuedDice = remotesFolder.Roll:WaitForChild("RemoveQueuedDice"),
	
	-- RFs
	GetAutoRollState = remotesFolder.Roll:WaitForChild("GetAutoRollState"),
	GetLuckData = remotesFolder.Roll:WaitForChild("GetLuckData"),
	GetRollTime = remotesFolder.Roll:WaitForChild("GetRollTime"),
	GetRollingData = remotesFolder.Roll:WaitForChild("GetRollingData")
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type ItemDefinition = ItemDefinitions.ItemDefinition
type DiceDefinition = ItemDefinitions.DiceDefinition

type ColumnResults = RollUtil.ColumnResults
type RollResult = RollUtil.RollResult
type RollData = RollUtil.RollData
type JackpotResult = RollUtil.JackpotResult

type LuckTable = RollUtil.LuckTable

type SpecialRoll = SpecialRollDefinitions.SpecialRoll

--------------------------------------------------
-- STATE --
--------------------------------------------------
local RollService = {}
RollService.Services = {}
RollService.Signals = {}

RollService.ActiveRollingPlayers = {} :: {[Player]: boolean}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function _playerRemoved(player: Player)
	if RollService.ActiveRollingPlayers[player] then
		RollService.ActiveRollingPlayers[player] = nil
	end
end



--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function RollService:Roll(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[Roll] No profile for player", player) return end
	
	local rollTime = self:GetPlayerRollTime(player)
	
	-- Roll time guard
	if self.ActiveRollingPlayers[player] then
		return
	else
		self.ActiveRollingPlayers[player] = true
	end
	
	-- player luck
	local playerLuck: number, luckTable: LuckTable = self:GetPlayerLuck(player)
	print("Total Luck", playerLuck, "luckTable", luckTable)
	
	-- get luck override
	if profile.Settings["CustomLuck"] and profile.Settings["CustomLuck"].enabled and profile.Settings["CustomLuck"].luck > 1 then
		playerLuck = math.max(profile.Settings["CustomLuck"].luck, 1)
	end
	
	-- mutations luck table
	local mutationRollLuck: {[WeaponMutation]: number} = self:GetPlayerMutationLuckTable(player)
	print("Mutations Luck table: ", mutationRollLuck)
	
	-- get special roll
	local nextSpecialRollName, specialRolls = self:GetPlayerSpecialRolls(player)
	local nextSpecialRoll = nextSpecialRollName and specialRolls[nextSpecialRollName]
	local specialRollLuckMulti = math.max(nextSpecialRoll and nextSpecialRoll.rollLuckMultiplier or 1, 1)
	
	-- get special dice
	local diceQueue = self:GetPlayerQueuedDice(player)
	local nextDice = diceQueue[1] 
	
	-- Get roll data
	local rollData: RollData = {
		columns = 2, -- TODO: read extra columns from server
		playerLuck = playerLuck * specialRollLuckMulti,
		mutationRollLuck = mutationRollLuck,
		rollTime = rollTime,
		specialRoll = nextSpecialRollName,
		specialDice = nextDice and nextDice.diceName,
		guaranteedJackpot = nextDice and nextDice.diceName == "Jackpot Dice",
	} 
	
	-- Generate Roll Results
	local roll: {ColumnResults} = RollUtil.roll(rollData)
	if not roll or not next(roll) then warn("[Roll] No roll reward") return end
	
	-- Add roll time based on roll results
	local highestRollResults = 1
	for columnIndex, columnResults: ColumnResults in roll do
		for resultIndex, result: RollResult in columnResults do
			if resultIndex > highestRollResults then
				highestRollResults = resultIndex
			end
		end
	end
	
	-- Compute jackpot per column
	local jackpotResults: {[nunber]: {JackpotResults}} = {}
	for columnIndex, columnResults: ColumnResults in roll do
		if RollUtil.rolledJackpot(columnResults) then
			jackpotResults[columnIndex] = RollUtil.rollJackpotWeapon(rollData)
		end
	end
	
	local totalRollTime = rollTime + (highestRollResults - 1) * (rollTime * RollUtil.CONFIGS.CONSECUTIVE_ROLL_TIME_FRACTION)
	if next(jackpotResults) then totalRollTime += RollUtil.CONFIGS.JACKPOT_ROLL_TIME end  -- Add jackpot time
	totalRollTime += 0.1 -- extra buffer
	
	-- Parse rewards
	for columnIndex, columnResults: ColumnResults in roll do
		if jackpotResults[columnIndex] then
			local jackpotResult: JackpotResult = jackpotResults[columnIndex]
			self.Services.InventoryService:AddWeapon(player, {
				weaponName = jackpotResult.weaponName,
				mutations = jackpotResults.mutations
			})
		else
			local result = columnResults[#columnResults]
			if result and result.type == "Weapon" and result.weaponName then
				self.Services.InventoryService:AddWeapon(player, {
					weaponName = result.weaponName,
					mutations = result.mutations
				})
			end
		end
	end
	
	-- Send result to client
	remotes.RollResult:FireClient(player, rollData, roll, jackpotResults)
	
	-- Progress player special rolls
	self:IncrementSpecialRollProgress(player)
	
	-- Remove special roll
	if nextSpecialRoll then
		profile.Rolling.SpecialRolls[nextSpecialRollName] = nil
		profile.Rolling.NextSpecialRoll = nil
	end
	
	-- remove one amount of queued dice
	if nextDice then
		nextDice.amount -= 1
		if nextDice.amount <= 0 then
			table.remove(diceQueue, 1)
		end
	end
		
	-- Update client
	self:SendUpdatedRollingData(player)
		
	-- AutoRoll fall through
	task.delay(totalRollTime, function()
		self.ActiveRollingPlayers[player] = nil
		
		if player.Parent and profile then 
			if profile.Rolling.AutoRoll then
				RollService:Roll(player)
			end
		end
	end)
end

function RollService:GetPlayerQueuedDice(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GetPlayerDiceQueue] No profile for player", player) return end

	local queuedDice = profile.Rolling.QueuedDice or {}
	profile.Rolling.QueuedDice = queuedDice
	
	-- Santize queue
	for i, diceEntry in queuedDice do
		local diceName = diceEntry.diceName
		local amount = diceEntry.amount or 0
		local diceDef: DiceDefinition? = ItemDefinitions[diceName]
		if not diceEntry.diceName or diceEntry.amount <= 0 or not diceDef then
			table.remove(queuedDice, i)
		end
		
		if not diceDef then warn("[GetPlayerDiceQueue] No dice def for", diceName) end
	end
	
	return queuedDice
end

function RollService:RemovePlayerQueuedDice(player: Player, diceNameToRemove: string)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[RemovePlayerQueuedDice] No profile for player", player) return end

	local queuedDice = profile.Rolling.QueuedDice or {}
	profile.Rolling.QueuedDice = queuedDice

	for i, diceEntry in queuedDice do
		if diceEntry.diceName == diceNameToRemove then
			diceEntry.amount = (diceEntry.amount or 0) - 1
			if diceEntry.amount <= 0 then
				table.remove(queuedDice, i)
			end
			
			-- give dice back to inventory
			self.Services.InventoryService:AddItem(player, diceNameToRemove, 1)
			
			self:SendUpdatedRollingData(player)
			return
		end
	end
end

function RollService:GetPlayerSpecialRolls(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GetPlayerSpecialRolls] No profile for player", player) return end
	
	local NextSpecialRoll = profile.Rolling.NextSpecialRoll
	local SpecialRolls = {}
	
	local specialRollsData = profile.Rolling.SpecialRolls or {}
	profile.Rolling.SpecialRolls = specialRollsData 
	
	local derivedNext = nil
	
	for specialRollName in SpecialRollDefinitions do
		local derivedSpecialRoll: SpecialRoll = self.Services.UpgradeService:GetSpecialRoll(player, specialRollName)
		if not derivedSpecialRoll then continue end
		
		local profileEntry = specialRollsData[specialRollName]
		if not profileEntry then
			profileEntry = {
				rollProgress = 0,
				paused = false,
			}
			specialRollsData[specialRollName] = profileEntry
		end
		
		
		-- Add to table
		SpecialRolls[specialRollName] = {
			rollsNeeded =  derivedSpecialRoll.rollsNeeded,
			rollLuckMultiplier = derivedSpecialRoll.rollLuckMultiplier,
			rollProgress = profileEntry.rollProgress,
			paused = profileEntry.paused,
		}
		
		-- derive next 
		if not NextSpecialRoll and not derivedNext
			and not profileEntry.paused
			and profileEntry.rollProgress >= derivedSpecialRoll.rollsNeeded then
			derivedNext = specialRollName
		end
	end
	
	NextSpecialRoll = NextSpecialRoll or derivedNext
	
	return NextSpecialRoll, SpecialRolls
end

function RollService:IncrementSpecialRollProgress(player: Player, amount: number?)
	amount = amount or 1
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then return end

	local specialRollsData = profile.Rolling.SpecialRolls or {}
	if not specialRollsData then return end

	for specialRollName, entry in specialRollsData do
		if entry.paused then continue end

		local derived = self.Services.UpgradeService:GetSpecialRoll(player, specialRollName)
		if not derived then continue end

		entry.rollProgress = math.clamp(entry.rollProgress + amount, 0, derived.rollsNeeded)
	end
end

function RollService:PauseSpecialRoll(player: Player, specialRollName: string)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[PauseSpecialRoll] No profile for player", player) return end

	local specialRollsData = profile.Rolling.SpecialRolls
	if specialRollsData and specialRollsData[specialRollName] then
		specialRollsData[specialRollName].paused = not specialRollsData[specialRollName].paused
	end

	-- Update client
	self:SendUpdatedRollingData(player)
end

function RollService:GetPlayerLuck(player: Player): (number, LuckTable)
	local total = 1

	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GetLuck] No profile for player", player) return total end
	
	local luckTable: LuckTable = {
		Added = {},
		Multiplied = {},
	}
	
	-- Added -- 
	-- Item luck boosts
	luckTable.Added["Boosts"] = self.Services.InventoryService:GetPlayerActiveBoostType(player, "Luck") or 0
	
	-- TODO: friends bonus
	
	-- TODO: like/group bonus	
	
	-- TODO: luck upgrades total
	
	
	-- Multiplied -- 
	-- Index Luck
	local indexLuck = 1 -- TODO
	luckTable.Multiplied["Index"] = indexLuck
	
	-- Rebirth Luck
	luckTable.Multiplied["Rebirths"] = RebirthUtil.GetRebirthLuck(profile.Rebirths or 0)
	
	-- Server luck (active luck products, admin luck, etc)
	luckTable.Multiplied["Server Luck"] = 1 -- TODO
	
	-- Total
	for _, value in luckTable.Added do
		value = math.max(0, value)
		total += value
	end
	for _, value in luckTable.Multiplied do
		value = math.max(1, value)
		total *= value
	end
	
	return total, luckTable
end

function RollService:GetPlayerMutationLuckTable(player: Player)
	-- server wide luck multi
	local serverLuckMulti = math.max(1, 1) -- TODO
	
	-- build table of mutations
	local mutationMultis = {}
	for mutation in MutationDefinitions.RollChances do 
		mutationMultis[mutation] = 1 * serverLuckMulti
	end
	
	
	return mutationMultis
end

function RollService:GetPlayerRollTime(player: Player): number
	local totalSpeedMulti = 1

	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GetLuck] No profile for player", player) return totalSpeedMulti end
	
	-- Read Upgrade Multi
	local upgradeMulti = self.Services.UpgradeService:GetRollSpeed(player)
	totalSpeedMulti *= upgradeMulti
	
	-- TODO: read active server speed boosts, etc
	
	return RollUtil.CONFIGS.DEFAULT_ROLL_TIME / totalSpeedMulti
end


function RollService:SendUpdatedLuck(player: Player)
	local totalLuck, luckTable = self:GetPlayerLuck(player)
	remotes.LuckDataUpdated:FireClient(player, totalLuck, luckTable)
end

function RollService:SendUpdatedRollTime(player: Player)
	remotes.RollTimeUpdated:FireClient(player, self:GetPlayerRollTime(player))
end

function RollService:SendUpdatedRollingData(player)
	local nextSpecialRoll, specialRolls = self:GetPlayerSpecialRolls(player)
	local diceQueue = self:GetPlayerQueuedDice(player)
	
	remotes.RollingDataUpdated:FireClient(player, {
		SpecialRollData = { NextSpecialRoll = nextSpecialRoll, SpecialRolls = specialRolls },
		DiceQueue = diceQueue
	})
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function RollService:Init(services)
	self.Services = services
	
end

function RollService:Start()
	self.Services.DataService.Signals.DataLoaded:Connect(function(player: Player)
		local profile = RollService.Services.DataService:GetProfile(player)
		if not profile then warn("[_playerAdded] No profile for player", player) return end
		
		self:SendUpdatedRollingData(player)
		
		-- Get auto roll state
		if profile.Rolling.AutoRoll then
			remotes.ToggleAutoRoll:FireClient(player, true)
			RollService:Roll(player)
		end

	end)
	
	Players.PlayerRemoving:Connect(_playerRemoved)
	
	
	remotes.AttemptRoll.OnServerEvent:Connect(function(player)
		self:Roll(player)
	end)
	
	remotes.ToggleAutoRoll.OnServerEvent:Connect(function(player)
		local profile = self.Services.DataService:GetProfile(player)
		if not profile then warn("[ToggleAutoRoll] No profile for player", player) return end
		
		profile.Rolling.AutoRoll = not profile.Rolling.AutoRoll
		
		if profile.Rolling.AutoRoll then
			self:Roll(player)
		end
		remotes.ToggleAutoRoll:FireClient(player, profile.Rolling.AutoRoll)
	end)
	
	remotes.PauseSpecialRoll.OnServerEvent:Connect(function(player, specialRollName)
		self:PauseSpecialRoll(player, specialRollName)
	end)
	
	remotes.GetLuckData.OnServerInvoke = function(player)
		local totalLuck, luckTable = self:GetPlayerLuck(player)
		return {
			TotalLuck = totalLuck,
			LuckTable = luckTable
		}
	end
	
	remotes.GetRollTime.OnServerInvoke = function(player)
		return self:GetPlayerRollTime(player)
	end
	
	remotes.GetRollingData.OnServerInvoke = function(player)
		local nextSpecialRoll, specialRolls = self:GetPlayerSpecialRolls(player)
		return {
			NextSpecialRoll = nextSpecialRoll,
			SpecialRolls = specialRolls,
		}
	end
	
	remotes.RemoveQueuedDice.OnServerEvent:Connect(function(player, diceName)
		self:RemovePlayerQueuedDice(player, diceName)
	end)
	
end


return RollService