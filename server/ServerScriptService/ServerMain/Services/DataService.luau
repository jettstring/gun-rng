local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AnalyticsService = game:GetService("AnalyticsService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local ProfileStore = require(ReplicatedStorage.Packages.ProfileStore)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	GetProfile = remotesFolder.Data.GetProfile,
	GetPurchaseProfile = remotesFolder.Data.GetPurchaseProfile,
}

local INCREMENTABLE_VALUES = {
	["Money"] = true,
	["Dogtags"] = true,
}

local PROFILE_TEMPLATE = require(ReplicatedStorage.Modules:WaitForChild("ProfileTemplate"))
local PURCHASE_PROFILE_TEMPLATE = require(ReplicatedStorage.Modules:WaitForChild("PurchaseProfileTemplate"))


--------------------------------------------------
-- STATE --
--------------------------------------------------
local DataService = {}
DataService.Services = {}
DataService.Signals = {
	DataLoaded = Signal.new(),
}

DataService.MainKey = "DEV-15"
DataService.PurchaseKey = "DEV-PURCHASES-01"

DataService.DATA_CONFIG = {
	Mock = false, 
}

DataService.PlayerStore = ProfileStore.New(DataService.MainKey, PROFILE_TEMPLATE)
DataService.PurchaseStore = ProfileStore.New(DataService.PurchaseKey, PURCHASE_PROFILE_TEMPLATE)

if RunService:IsStudio() and DataService.DATA_CONFIG.Mock == true then
	DataService.PlayerStore = DataService.PlayerStore.Mock
	DataService.PurchaseStore = DataService.PurchaseStore.Mock
	warn("[WARNING] MOCK PROFILE ACTIVE")
end

DataService.Profiles = {}
DataService.PurchaseProfiles = {}

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function _NormalizeUnlockedNodes(profileData)
	local normalized = {}

	local upgrades = profileData.Upgrades
	if typeof(upgrades) ~= "table" then
		upgrades = {}
		profileData.Upgrades = upgrades
	end

	local unlockedNodes = upgrades.UnlockedNodes
	if typeof(unlockedNodes) == "table" then
		for key, value in unlockedNodes do
			if typeof(key) == "string" and value == true then
				normalized[key] = true
			elseif typeof(value) == "string" then
				normalized[value] = true
			end
		end
	end

	upgrades.UnlockedNodes = normalized
end

local function _PlayerAdded(player: Player)
	local profile = DataService.PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	local purchaseProfile = DataService.PurchaseStore:StartSessionAsync(`{player.UserId}_purchases`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})


	if profile ~= nil and purchaseProfile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		_NormalizeUnlockedNodes(profile.Data)

		purchaseProfile:AddUserId(player.UserId)
		purchaseProfile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			if DataService.Profiles[player] then
				DataService.Profiles[player].Data.LastSessionTimestamp =  workspace:GetServerTimeNow()
			end
			DataService.Profiles[player] = nil
			player:SetAttribute("Loaded", false)
			player:Kick(`Profile session end - Please rejoin`)
		end)

		purchaseProfile.OnSessionEnd:Connect(function()
			DataService.PurchaseProfiles[player] = nil
		end)


		if player.Parent == Players then
			DataService.Profiles[player] = profile
			DataService.PurchaseProfiles[player] = purchaseProfile

			if RunService:IsStudio() then
				print("PROFILE: ", profile.Data)
				print("PURCHASE PROFILE: ", purchaseProfile.Data)
			end
			

			-- Set Shared Attributes
			DataService:UpdateAttributes(player)
			
			player:SetAttribute("Loaded", true)
			DataService.Signals.DataLoaded:Fire(player)
		else
			profile:EndSession()
			purchaseProfile:EndSession()
		end
	else
		player:Kick(`Profile load fail - Please rejoin`)
	end
end

local function _PlayerRemoved(player: Player)
	local profile = DataService.Profiles[player]
	local purchaseProfile = DataService.PurchaseProfiles[player]

	if profile then
		profile.Data.LastSessionTimestamp = os.time()
		profile:EndSession()
	end

	if purchaseProfile then
		purchaseProfile:EndSession()
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function DataService:GetProfile(player: Player)
	local profile = self.Profiles[player]

	if not profile then
		warn("[GetProfile] No profile found for player:", player.Name)
		warn(debug.traceback())
		return nil
	end

	return profile.Data
end

function DataService:GetPurchaseProfile(player: Player)
	local purchaseProfile = self.PurchaseProfiles[player]

	if not purchaseProfile then
		warn("[GetPurchaseProfile] No purchaseProfile found for player:", player.Name)
		return nil
	end

	return purchaseProfile.Data
end

function DataService:IncrementCurrency(
	player: Player,
	valueName: string,
	amount: number,
	source: string?,
	suppressClientEffects: boolean?,
	suppressAnalytics: boolean?
): string
	if INCREMENTABLE_VALUES[valueName] ~= true then
		return `Value not found for {valueName}`
	end

	local profile = self.Profiles[player]
	if not profile then
		return `Profile not found for {player.Name}`
	end

	if typeof(amount) ~= "number" then
		return "Amount must be a number."
	end

	local currentValue = profile.Data[valueName]
	if typeof(currentValue) ~= "number" then
		currentValue = 0
	end

	local newValue = currentValue + amount
	profile.Data[valueName] = newValue
	
	-- Update attributes
	self:UpdateAttributes(player)

	local transactionAmount = math.abs(amount)
	if not suppressAnalytics then
		if amount > 0 then
			AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, valueName,
				transactionAmount,
				newValue,
				Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
				nil,
				{
					[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = source,
				} 
			)
		elseif amount < 0 then
			AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, valueName,
				transactionAmount,
				newValue,
				Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
				nil,
				{
					[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = source,
				} 
			)
		end
	end

	local customAnalyticsService = self.Services.CustomAnalyticsService
	if customAnalyticsService and amount ~= 0 and not suppressAnalytics then
		local stats = profile.Data.Stats
		local playTime = if typeof(stats) == "table" and typeof(stats.Playtime) == "number" then stats.Playtime else 0

		customAnalyticsService:AddCurrency(
			player,
			{
				currency = valueName,
				amount = amount,
				balance = newValue,
				source = source,
				playTime = playTime,
			}
		)
	end

	-- Client Effects
	if valueName == "Money" and amount > 0 and not suppressClientEffects then
		ReplicatedStorage.Remotes.Currency.ClientMoneyEffects:FireClient(player, newValue, amount, source)
	end

	return `{player.Name} now has {newValue} {valueName}.`
end

function DataService:IncrementMoney(player: Player, amount: number, source: string?, suppressClientEffects: boolean?): string
	return self:IncrementCurrency(player, "Money", amount, source, suppressClientEffects)
end

function DataService:IncrementDogtags(player: Player, amount: number, source: string?, suppressClientEffects: boolean?): string
	return self:IncrementCurrency(player, "Dogtags", amount, source, suppressClientEffects)
end

function DataService:IncrementRolls(player: Player, amount: number, source: string?, suppressClientEffects: boolean?): string
	return self:IncrementCurrency(player, "Rolls", amount, source, suppressClientEffects)
end

function DataService:IncrementPlaytimePoints(player: Player, amount: number, source: string?, suppressClientEffects: boolean?): string
	return self:IncrementCurrency(player, "PlaytimePoints", amount, source, suppressClientEffects)
end

function DataService:EnemyKilled(player: Player, enemyType: string)
	local profile = self.Profiles[player]
	if not profile then
		warn("[EnemyKilled] No profile found for player:", player.Name)
		return
	end

	local stats = profile.Data.Stats
	stats.EnemiesKilled += 1

	local perTypeKey = `{enemyType}EnemiesKilled`
	if typeof(stats[perTypeKey]) == "number" then
		stats[perTypeKey] += 1
	else
		warn(`[EnemyKilled] Unknown enemy type "{enemyType}" for {player.Name}`)
	end
end


function DataService:UpdateAttributes(player: Player)
	local profile = self:GetProfile(player)
	if not profile then warn("[UpdateAttributes] No profile found for player:", player.Name) return end
	
	for valueName in INCREMENTABLE_VALUES do
		player:SetAttribute(valueName, profile[valueName])
	end
end
--------------------------------------------------
-- MAIN --
--------------------------------------------------

function DataService:Init(services)
	self.Services = services
	
	print("✅ DataService initiated")
end

function DataService:Start()
	
	for _, player in Players:GetPlayers() do
		_PlayerAdded(player)
	end
Players.PlayerAdded:Connect(_PlayerAdded)
	Players.PlayerRemoving:Connect(_PlayerRemoved)
	
	-- Increment playtime
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				if self.Profiles[player] then
					self.Profiles[player].Data.Stats.Playtime += 10
				end
			end
		end
	end)
	
	
	remotes.GetProfile.OnServerInvoke = function(player)
		return self:GetProfile(player)
	end
	
	remotes.GetPurchaseProfile.OnServerInvoke = function(player)
		return self:GetPurchaseProfile(player)
	end
	
	print("✅ DataService started")
end


return DataService
