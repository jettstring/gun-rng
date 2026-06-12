local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local Displays = playerGui:WaitForChild("Displays")
local RobuxShop = Displays:WaitForChild("RobuxShop")
local groupList = RobuxShop.Display:WaitForChild("GroupsList")
local serverLuckDisplay = groupList:WaitForChild("ServerLuck")
local gamepassesDisplay = groupList:WaitForChild("Gamepasses")
local jackpotRollsDisplay = groupList:WaitForChild("JackpotRolls")


-- Modules
local MonetizationAssets = ReplicatedStorage.GameAssets.MonetizationAssets
local Products = require(MonetizationAssets.Products)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {}


--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type PurchaseProfile = PurchaseProfileTemplate.PurchaseProfile

type MonetizedProduct = Products.MonetizedProduct
type PayerInfo = Products.PayerInfo

--------------------------------------------------
-- STATE --
--------------------------------------------------
local RobuxShopController = {}
RobuxShopController.Controllers = {}
RobuxShopController.Signals = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function _setup()
	local purchaseProfile = RobuxShopController.Controllers.MonetizationController:GetPurchaseProfile()
	local payerInfo = RobuxShopController.Controllers.MonetizationController.PayerInfo
end


--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function RobuxShopController:Refresh()

end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function RobuxShopController:Init(controllers)
	self.Controllers = controllers

end

function RobuxShopController:Start()
	player:GetAttributeChangedSignal("Loaded"):Once(_setup)
	if player:GetAttribute("Loaded") then _setup() end
	
	-- listen for purchase profile updates
	self.Controllers.MonetizationController.Signals.PurchaseProfileUpdated:Connect(function(purchaseProfile: PurchaseProfile)
		self:Refresh()
	end)
	
end


return RobuxShopController