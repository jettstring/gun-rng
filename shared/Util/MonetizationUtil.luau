local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local PurchaseProfileTemplate = require(ReplicatedStorage.Modules.PurchaseProfileTemplate)
local MonetizationAssets = ReplicatedStorage.GameAssets.MonetizationAssets
local Products = require(MonetizationAssets.Products)


--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type MonetizedProduct = Products.MonetizedProduct
type PayerInfo = Products.PayerInfo

type PurchaseProfile = PurchaseProfileTemplate.PurchaseProfile


local MonetizationUtil = {}


function MonetizationUtil.getProductDefFromId(id: number): MonetizedProduct?
	for productName, productDef: MonetizedProduct in Products do
		if productDef.id == id or productDef.giftId == id then
			return productDef
		end
	end	

	warn("No product found with id: " .. id)
	return nil
end


return MonetizationUtil
