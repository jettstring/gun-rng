local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Signal = require(ReplicatedStorage.Packages.Signal)


--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- Modules
local PurchaseProfileTemplate = require(ReplicatedStorage.Modules.PurchaseProfileTemplate)
local MonetizationAssets = ReplicatedStorage.GameAssets.MonetizationAssets
local Products = require(MonetizationAssets.Products)

-- Utils
local utils = ReplicatedStorage.Util
local MonetizationUtil = require(utils.MonetizationUtil)
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	AttemptPurchase = remotesFolder.Monetization:WaitForChild("AttemptPurchase"),
	PurchasePrompted = remotesFolder.Monetization:WaitForChild("PurchasePrompted"),
	PurchaseProfileUpdated = remotesFolder.Monetization:WaitForChild("PurchaseProfileUpdated"),

	-- RFs
	GetPurchaseProfile = remotesFolder.Monetization:WaitForChild("GetPurchaseProfile"),
	GetPayerInfo = remotesFolder.Monetization:WaitForChild("GetPayerInfo"),
}


--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type PurchaseProfile = PurchaseProfileTemplate.PurchaseProfile

type MonetizedProduct = Products.MonetizedProduct
type PayerInfo = Products.PayerInfo

--------------------------------------------------
-- STATE --
--------------------------------------------------
local MonetizationController = {}
MonetizationController.Controllers = {}
MonetizationController.Signals = {
	PurchaseProfileUpdated = Signal.new(),
}

MonetizationController.PurchaseProfile = nil
MonetizationController.PayerInfo = nil

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function _onPurchaseProfileUpdated(purchaseProfile: PurchaseProfile)
	if not purchaseProfile or next(purchaseProfile) == nil then
		warn("[_onPurchaseProfileUpdated] Purchase profile is nil")
	end
	
	MonetizationController.PurchaseProfile = purchaseProfile
	
	-- Fire signal
	MonetizationController.Signals.PurchaseProfileUpdated:Fire(purchaseProfile)
end


local function _setup()
	MonetizationController:GetPurchaseProfile()
	MonetizationController:GetPayerInfo()
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function MonetizationController:AttemptPurchase(productName: string)
	local productDef: MonetizedProduct = Products[productName]
	if not productDef then warn("No product definition for: ", productName) return end
	remotes.AttemptPurchase:FireServer(productName)
end

function MonetizationController:GetPurchaseProfile(): PurchaseProfile
	if self.PurchaseProfile and next(self.PurchaseProfile) ~= nil then
		return self.PurchaseProfile
	end
	
	local success, result = pcall(function()
		return remotes.GetPurchaseProfile:InvokeServer()
	end)
	
	if not success then
		warn("[GetPurchaseProfile] Error getting purchase profile: ", result)
		return nil
	end
	
	if not result or next(result) == nil then
		warn("[GetPurchaseProfile] Purchase profile is nil")
		return nil
	end
	
	self.PurchaseProfile = result
	
	return self.PurchaseProfile
end

function MonetizationController:GetPayerInfo(): PayerInfo
	if self.PayerInfo and next(self.PayerInfo) ~= nil then
		return self.PurchaseProfile
	end

	local success, result = pcall(function()
		return remotes.GetPayerInfo:InvokeServer()
	end)

	if not success then
		warn("[GetPurchaseProfile] Error getting purchase profile: ", result)
		return nil
	end

	if not result or next(result) == nil then
		warn("[GetPurchaseProfile] Purchase profile is nil")
		return nil
	end

	self.PayerInfo = result

	return self.PayerInfo
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function MonetizationController:Init(controllers)
	self.Controllers = controllers

end

function MonetizationController:Start()
	player:GetAttributeChangedSignal("Loaded"):Once(_setup)
	if player:GetAttribute("Loaded") then _setup() end
	
	remotes.PurchaseProfileUpdated.OnClientEvent:Connect(_onPurchaseProfileUpdated)
	
	remotes.PurchasePrompted.OnClientEvent:Connect(function(productName: string)
		local productDef: MonetizedProduct = Products[productName]
		if not productDef then warn("No product definition for: ", productName) return end
		
		self.Controllers.ScreenPromptController:CreatePromptEffect("Product")
	end)
	
end


return MonetizationController