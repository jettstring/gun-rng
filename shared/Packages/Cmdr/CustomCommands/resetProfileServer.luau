local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService.ServerMain.Services.DataService)
local GunService = require(ServerScriptService.ServerMain.Services.GunService)
local UpgradeService = require(ServerScriptService.ServerMain.Services.UpgradeService)
local ZoneService = require(ServerScriptService.ServerMain.Services.ZoneService)
local ProfileTemplate = require(ReplicatedStorage.Modules:WaitForChild("ProfileTemplate"))
local PurchaseProfileTemplate = require(ReplicatedStorage.Modules:WaitForChild("PurchaseProfileTemplate"))

type ResetCategory = "dev" | "all" | "upgrades" | "zone" | "ammo"

local function DeepCopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end

	return copy
end

local function resetProfileData(targetPlayer: Player, includePurchaseProfile: boolean): string
	local profile = DataService.Profiles[targetPlayer]
	if not profile then
		return `Profile is not loaded for {targetPlayer.Name}`
	end

	local purchaseProfile = if includePurchaseProfile then DataService.PurchaseProfiles[targetPlayer] else nil
	if includePurchaseProfile and not purchaseProfile then
		return `Purchase profile is not loaded for {targetPlayer.Name}`
	end

	profile.Data = DeepCopyTable(ProfileTemplate)

	if purchaseProfile then
		purchaseProfile.Data = DeepCopyTable(PurchaseProfileTemplate)
	end

	print("PLAYER DATA RESET: ", profile.Data)
	if purchaseProfile then
		print("PLAYER PURCHASE DATA RESET: ", purchaseProfile.Data)
	end

	if targetPlayer.Parent then
		targetPlayer:Kick("Profile reset, please rejoin.")
	end

	return if includePurchaseProfile then `Profile and purchase profile reset for {targetPlayer.Name}` else `Profile reset for {targetPlayer.Name}`
end

return function(_context, category: ResetCategory, targetPlayer: Player?)
	targetPlayer = targetPlayer or _context.Executor
	if category == "upgrades" then
		local _success, message = UpgradeService:ResetPlayerUpgrades(targetPlayer)
		return message
	end

	if category == "zone" then
		local _success, message = ZoneService:ResetZone(targetPlayer)
		return message
	end

	if category == "ammo" then
		local _success, message = GunService:ResetAmmo(targetPlayer)
		return message
	end

	if category == "dev" then
		return resetProfileData(targetPlayer, false)
	end

	if category == "all" then
		return resetProfileData(targetPlayer, true)
	end

	return `Invalid reset category: {category}`
end
