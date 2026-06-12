local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local AnalyticsService = game:GetService("AnalyticsService")
local PolicyService = game:GetService("PolicyService")

local Signal = require(ReplicatedStorage.Packages.Signal)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

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

type MonetizedProduct = Products.MonetizedProduct
type PayerInfo = Products.PayerInfo

type PurchaseProfile = PurchaseProfileTemplate.PurchaseProfile

--------------------------------------------------
-- STATE --
--------------------------------------------------
local MonetizationService = {}
MonetizationService.Services = {}
MonetizationService.Signals = {
	ProductPurchased = Signal.new(),
}

MonetizationService.StoredPurchases = {}
MonetizationService.PendingGiftRecipient = {} :: {[Player]: Player}
MonetizationService.StoredPayerInfo = {} :: {[Player]: PayerInfo}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function refreshAttributes()

end

local function _registerHandlers()
	
end


--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function MonetizationService:ProcessReceipt(receiptInfo)
	print("RECEIPT DETAILS:", receiptInfo)

	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	local player = Players:GetPlayerByUserId(userId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end


	local handler = MonetizationService.ProductFunctions[productId]
	if not handler then
		warn("No handler for productId: ", productId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local success, result = pcall(handler, receiptInfo, player)
	if not success then
		warn(string.format("Failed to process receipt %s: %s", productId, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Handler returned false means it intentionally failed (e.g., no pending request)
	if result == false then
		warn(string.format("Handler rejected receipt %s", productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end


	self:SendPurchaseProfile(player)
	self.Signals.ProductPurchased:Fire(player, productId, receiptInfo)

	-- Increment RobuxSpent in purchase profile
	local purchaseProfile = self.Services.DataService:GetPurchaseProfile(player)
	if purchaseProfile then
		purchaseProfile.robuxSpent += receiptInfo.CurrencySpent or 0
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:ProcessGamepass(player: Player, gamepassId, wasPurchased)
	if wasPurchased then
		self.Services.NotificationService:Notify(player, "😄 Thank you for your support! ", Color3.new(1,0.5,1), SoundService.UI.Success)

		self.StoredPurchases[player] = self.StoredPurchases[player] or {}
		table.insert(self.StoredPurchases[player], gamepassId)
		print("Stored Gamepass Purchase of player ", player.Name, "Stored Server Purchases: ", self.StoredPurchases[player])
		
		refreshAttributes(player)
		remotes.PurchaseProfileUpdated:FireClient(player)

		if self.GamepassFunctions[gamepassId] then
			self.GamepassFunctions[gamepassId](player)
		end

		-- Increment RobuxSpent in purchase profile
		local purchaseProfile = self.Services.DataService:GetPurchaseProfile(player)
		if purchaseProfile then
			local success, productInfo = pcall(function()
				return MarketplaceService:GetProductInfo(gamepassId, Enum.InfoType.GamePass)
			end)
			if success and productInfo then
				if productInfo.PriceInRobux then
					purchaseProfile.robuxSpent += productInfo.PriceInRobux or 0
				end
			end
		end

		MonetizationService.Signals.GamepassPurchased:Fire(player, gamepassId)
	end
end

function MonetizationService:OwnsPseudoGamepass(player: Player, productId: number)

	-- check for stored profile purchases
	local purchaseProfile: PurchaseProfileTemplate = self.Services.DataService:GetPurchaseProfile(player) 
	if purchaseProfile then
		if table.find(purchaseProfile.storedPurchases, productId) then return true end
	else
		warn("[OwnsPseudoGamepass] No playerPurchaseData for player: ", player) 
	end

	-- check for cached in-session purchases
	if self.storedPurchases[player] and table.find(self.storedPurchases[player], productId) then
		return true
	end

	return false
end

function MonetizationService:OwnsGamepass(player: Player, gamepassId: number)
	-- Resolve gamepass definition from gamepassId
	local name = nil
	for productName, productData: MonetizedProduct in pairs(Products) do
		if productData.isPass and productData.id == gamepassId then
			name = productName

			-- check for ownership of giftId of gamepass
			if productData.giftId and MonetizationService:OwnsPseudoGamepass(player, productData.giftId) then
				return true
			end
			
			break
		end
	end

	-- 1) check for attribute 
	if name and player:GetAttribute(name) == true then
		return true
	end

	-- 2 ) check cached in-session gamepass purchases
	if self.StoredPurchases[player] and table.find(self.StoredPurchases[player], gamepassId) then
		return true
	end

	-- 3) Direct check for MPS ownership
	local success, ownsGamepass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	if not success then 
		warn(string.format("[OwnsGamepass] MPS FAILURE: Player: %s, Result: %s", player.Name, ownsGamepass))
		return false
	end

	return ownsGamepass
end

function MonetizationService:CanUseRandomPaidItems(player: Player): boolean
	local success, result = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	if not success then
		warn("[PaidRandomItemsRestricted] Failed to get policy info for player:", player)
		return false
	end

	if result.ArePaidRandomItemsRestricted then
		return true
	end

	return false
end

function MonetizationService:PromptPurchase(player: Player, productName: string)
	if not player then warn("No player") return end

	local productDef: MonetizedProduct = Products[productName]
	if not productDef then warn("No product definition for: ", productName) return end
	
	local productType = productDef.isPass and Enum.InfoType.GamePass or Enum.InfoType.Product

	if productType == Enum.InfoType.GamePass then
		MarketplaceService:PromptGamePassPurchase(player, productDef.id)
		remotes.PurchasePrompted:FireClient(player, productName)
		
	elseif productType == Enum.InfoType.Product then
		-- check if player owns (psuedo-gamepasses)
		if productDef.oneTimePurchase then
			if MonetizationService:OwnsPseudoGamepass(player, productDef.id) then
				warn("Player already owns psuedo-gamepasses: ", player.Name, productName)
				return
			end
		end
		
		MarketplaceService:PromptProductPurchase(player, productDef.id)
		remotes.PurchasePrompted:FireClient(player, productName)
		
	else
		warn("Invalid product type: ", productType)
		return
	end
end

function MonetizationService:SendPurchaseProfile(player: Player)
	local purchaseProfileData: PurchaseProfile = self.Services.DataService:GetPurchaseProfile(player)
	if not purchaseProfileData then warn("No player purchaseProfileData") return end
	
	print("Sending Purchase profile to player ", player.Name, purchaseProfileData)
	remotes.PurchaseProfileUpdated:FireClient(player, purchaseProfileData)
end

function MonetizationService:GetPayerInfo(player: Player): PayerInfo
	local payerInfo: PayerInfo = self.StoredPayerInfo[player]
	if not payerInfo then
		self.StoredPayerInfo[player] = {
			paidRandomItemsRestricted = nil, 
			activePayerStatus = nil, 
			whenUserFirstPlayed = nil, 
			platformSpenderStatus = nil,
		}
		payerInfo = self.StoredPayerInfo[player]
	end
	
	-- get player policy info
	if payerInfo.paidRandomItemsRestricted == nil then
		payerInfo.paidRandomItemsRestricted = self:ArePaidRandomItemsRestricted(player)
	end
	
	
	-- get segment info
	if not payerInfo.segmentsFetched then
		payerInfo.segmentsFetched = true   -- mark attempted, even when segments fail
		
		local success, segments = pcall(function()
			return AnalyticsService:GetPlayerSegmentsAsync(player)
		end)
		if not success then
			warn("[GetPlayerPayerInfo] Error getting player segments for player", player.Name, ":", segments)
			return nil
		end

		print("[GetPlayerPayerInfo] segments result:", segments, "HasData:", segments.HasData)

		if not segments.HasData then 
			print("[GetPlayerPayerInfo] No segment data available for", player.Name)
		else
			if segments.ActivePayerStatus then
				payerInfo.activePayerStatus = segments.ActivePayerStatus
			end
			if segments.WhenUserFirstPlayed then
				payerInfo.whenUserFirstPlayed = segments.WhenUserFirstPlayed
			end
			if segments.PlatformSpenderStatus then
				payerInfo.platformSpenderStatus = segments.PlatformSpenderStatus
			end
		end
	end
	
	self.StoredPayerInfo[player] = payerInfo
	
	return payerInfo
end

function MonetizationService:ArePaidRandomItemsRestricted(player: Player): boolean
	local success, result = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	if not success then
		warn("[PaidRandomItemsRestricted] Failed to get policy info for player:", player)
		return false
	end

	if result.ArePaidRandomItemsRestricted then
		return true
	end

	return false
end


--------------------------------------------------
-- MAIN --
--------------------------------------------------

function MonetizationService:Init(services)
	self.Services = services

end

function MonetizationService:Start()
	
	
	remotes.AttemptPurchase.OnServerEvent:Connect(function(player, productName)
		self:PromptPurchase(player, productName)
	end)
	
	remotes.GetPurchaseProfile.OnServerInvoke = function(player)
		return self.Services.DataService:GetPurchaseProfile(player)
	end
	
	remotes.GetPayerInfo.OnServerInvoke = function(player)
		return self:GetPayerInfo(player)
	end

	
end


return MonetizationService