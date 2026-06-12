
local PurchaseProfileTemplate = {
	storedPurchases = {},
	giftedPurchases = {},	
	totalGifted = 0,
	giftPopup = {},
	robuxSpent = 0,
}

export type PurchaseProfile = typeof(PurchaseProfileTemplate)

return PurchaseProfileTemplate
