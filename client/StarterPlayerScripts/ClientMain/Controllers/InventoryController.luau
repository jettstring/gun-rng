local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local Displays = playerGui:WaitForChild("Displays")
local inventoryFrame = Displays:WaitForChild("Inventory")
local banner = inventoryFrame:WaitForChild("Banner")
local headerText = banner.Top:WaitForChild("HeaderText")
local equipBestButton = banner:WaitForChild("EquipBest")
local optionsList = inventoryFrame:WaitForChild("Options")
local display = inventoryFrame:WaitForChild("Display")
local gunsDisplay = display:WaitForChild("Guns")
local itemsDisplay = display:WaitForChild("Items")
local previewDisplay = itemsDisplay:WaitForChild("PreviewDisplay")
local itemsList =  itemsDisplay:WaitForChild("ItemList")
local selectGunList = itemsDisplay:WaitForChild("SelectGunList")
local addComponentDisplay = itemsDisplay:WaitForChild("AddComponent")
local quantitySlideBar = addComponentDisplay:WaitForChild("QuantitySlideBar")
local addAllFrame = addComponentDisplay:WaitForChild("AddAllFrame")
-- 
local Popups = playerGui:WaitForChild("Popups")
local addedItemDisplay = Popups:WaitForChild("AddedItemDisplay")


local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponFrame = require(Modules.WeaponFrame)
local SliderBar = require(Modules.SliderBar)

local utils = ReplicatedStorage.Util
local InventoryUtil = require(utils.InventoryUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)
local AmmoTypes = require(utils.AmmoTypes)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets.ItemDefinitions)
local WeaponDefinitions = require(GameAssets.WeaponAssets.WeaponDefinitions)

local itemSFX = SoundService.SFX.Items

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	UseItem = remotesFolder.Inventory.UseItem,
	EquipGun = remotesFolder.Inventory.EquipGun,
	UnequipGun = remotesFolder.Inventory.UnequipGun,
	EquipBestWeapons = remotesFolder.Inventory.EquipBestWeapons,
	InventoryUpdated = remotesFolder.Inventory.InventoryUpdated,
	ItemAdded = remotesFolder.Inventory.ItemAdded,
	AddComponentToWeapon = remotesFolder.Inventory.AddComponentToWeapon,

	-- RFs
	GetInventory = remotesFolder.Inventory.GetInventory,
	ToggleAutoEquipForAmmo = remotesFolder.GunKit.ToggleAutoEquipForAmmo,
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponFrameObject = WeaponFrame.WeaponFrameObject
type SliderBarObject = SliderBar.SlideBarObject

type ItemDefinition = ItemDefinitions.ItemDefinition
type ComponentDefinition = ItemDefinitions.ComponentDefinition
type BoostDefinition = ItemDefinitions.BoostDefinition
type DiceDefinition = ItemDefinitions.DiceDefinition

type WeaponData = InventoryUtil.WeaponData

type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type ComponentSession = {
	componentKey: string,
	weaponKey: string,
	amount: number,
	addAll: boolean,
}

--------------------------------------------------
-- STATE --
--------------------------------------------------
local InventoryController = {}
InventoryController.Controllers = {}
InventoryController.Signals = {}

InventoryController.InventoryData = {}
InventoryController.AmmoData = { SelectedType = AmmoTypes.Default, AutoEquip = {} }
InventoryController.MaxSlots = 0
InventoryController.CurrentDisplay = "Guns"
InventoryController.PreviewingItem = nil

InventoryController.ComponentSession = nil :: ComponentSession?


local WeaponFrames = {}
local EmptyFrames = {}
local ItemFrames = {}

local ComponentWeaponFrames = {}
local slideBar: SliderBarObject = nil

local previewButtonConnection: RBXScriptConnection = nil
local previewAmmoConnection: RBXScriptConnection = nil
local itemFrameConnections: {[string]: RBXScriptConnection} = {}
local ammoAttributeConnections: {[string]: RBXScriptConnection} = {}



--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------


local function onItemAdded(itemName: string, quantity: number)
	local itemDef = ItemDefinitions[itemName]
	if not itemDef then warn("No item definition for", itemName) return end
	
	local itemFrame = addedItemDisplay.UIListLayout:WaitForChild("ItemPopupTemplate"):Clone()
	local iconLabel = itemFrame:WaitForChild("IconLabel")
	local quantityLabel = itemFrame.QuantityDisplay:WaitForChild("TextLabel")

	iconLabel.Image = "rbxassetid://" .. (itemDef.displayImage or "")
	quantityLabel.Text = "x" .. quantity or 1
	
	
	SoundService:PlayLocalSound(itemSFX:FindFirstChild("ItemAdded"))
	itemFrame.Visible = true
	itemFrame.Parent = addedItemDisplay
	
	TweenService:Create(itemFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false), {
		Size = UDim2.new(1, 0, 0.3, 0)
	}):Play()
	
	task.delay(2, function()
		TweenService:Create(itemFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false), {
			Size = UDim2.new(0, 0, 0, 0)
		}):Play()
		task.wait(0.5)
		itemFrame:Destroy()
	end)
end

local function getInventoryData()
	local inventoryData, maxSlots, ammoData = remotes.GetInventory:InvokeServer()
	if not inventoryData or (inventoryData and next(inventoryData) == nil) then
		warn("[GetInventoryData] Failed to get inventory data")
		return
	end

	InventoryController.InventoryData = inventoryData
	InventoryController.MaxSlots = maxSlots or 0
	if ammoData then
		InventoryController.AmmoData = ammoData
	end
end

local function _setupUI()
	InventoryController:OpenDisplay(InventoryController.CurrentDisplay)
	InventoryController:PreviewItem(nil)
	
	-- EquipBestButton
	equipBestButton.Activated:Connect(function()
		remotes.EquipBestWeapons:FireServer()
	end)
	
	-- Options buttons
	for _, button in optionsList:GetChildren() do
		if not button:IsA("ImageButton") then continue end
		button.Activated:Connect(function()
			InventoryController:OpenDisplay(button.Name)
		end)
	end
	
	inventoryFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if inventoryFrame.Visible then
			InventoryController:OpenDisplay("Guns")
		end
	end)
	
	
	-- component display
	slideBar = SliderBar.new(quantitySlideBar, {min = 1, max = 5})
	
	slideBar.changedSignal:Connect(function(newValue)
		local s = InventoryController.ComponentSession
		if not s then return end
		s.amount = newValue
		InventoryController:RefreshAddComponentDisplay()
	end)
	
	addComponentDisplay.AddButton.Activated:Connect(function()
		local r = InventoryController:ResolveComponentSession()
		if not r then return end
		local componentSession: ComponentSession = r.session
		local amount = componentSession.addAll and componentSession.quantity or componentSession.amount
		remotes.AddComponentToWeapon:FireServer(r.session.weaponKey, componentSession.componentKey, amount)
	end)
	
	addAllFrame.Button.Activated:Connect(function()
		local s = InventoryController.ComponentSession
		if not s then return end
		s.addAll = not s.addAll
		slideBar:SetEnabled(not s.addAll)
		InventoryController:RefreshAddComponentDisplay()
	end)
	
	addComponentDisplay.BackButton.Activated:Connect(function()
		InventoryController:OpenDisplay("SelectGunList")
	end)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function InventoryController:OpenDisplay(newDisplay: ("Guns" | "Items" | "SelectGunList" | "AddComponent"))
	if newDisplay ~= "Guns" and newDisplay ~= "Items" and newDisplay ~= "SelectGunList" and newDisplay ~= "AddComponent" then return end
	InventoryController.CurrentDisplay = newDisplay
	
	itemsDisplay.Visible = (newDisplay == "Items" or newDisplay == "SelectGunList" or newDisplay == "AddComponent")
	itemsList.Visible = (newDisplay == "Items")
	previewDisplay.Visible = (newDisplay == "Items" or newDisplay == "SelectGunList")
	selectGunList.Visible = (newDisplay == "SelectGunList")
	addComponentDisplay.Visible = (newDisplay == "AddComponent")

	gunsDisplay.Visible = (newDisplay == "Guns")
	equipBestButton.Visible = (newDisplay == "Guns")
	
	
	if newDisplay == "Guns" then
		headerText.Text = "Guns"
	elseif newDisplay == "Items" then
		headerText.Text = "Items"
		if InventoryController.PreviewingItem then
			self:PreviewItem(InventoryController.PreviewingItem)
		end
	end
end

function InventoryController:UpdateGuns()
	local activeFrameIds = {}
	local owned = InventoryController.InventoryData.Weapons.Owned
	local equipped = InventoryController.InventoryData.Weapons.Equipped
	local maxSlots = InventoryController.MaxSlots

	--------------------------------------------------
	-- UNEQUIPPED: sort by rarity, then create/update frames
	--------------------------------------------------
	local unequippedDataList = {}
	local dataToUnequipped = {} -- WeaponData -> {key, value}

	for weaponKey, weaponValue in owned do
		local data = InventoryUtil.getWeaponData(weaponKey, weaponValue)
		table.insert(unequippedDataList, data)
		dataToUnequipped[data] = { key = weaponKey, value = weaponValue }
	end

	local sortedUnequipped = InventoryUtil.getSortedWeapons(unequippedDataList)

	for layoutOrder, data in sortedUnequipped do
		local entry = dataToUnequipped[data]
		local weaponKey, weaponValue = entry.key, entry.value
		local frameId = "Owned:" .. weaponKey
		activeFrameIds[frameId] = true

		local existingFrame: WeaponFrameObject = WeaponFrames[frameId]
		if existingFrame and existingFrame.isEquipped then
			existingFrame:Destroy()
			WeaponFrames[frameId] = nil
			existingFrame = nil
		end

		if not existingFrame then
			local weaponFrame: WeaponFrameObject = WeaponFrame.new(weaponKey, weaponValue, InventoryUtil.isStack(weaponKey))
			if weaponFrame then
				weaponFrame.isEquipped = false
				weaponFrame.frame.Parent = gunsDisplay.Unequipped.ScrollingFrame
				table.insert(weaponFrame.connections, weaponFrame.frameButton.Activated:Connect(function()
					remotes.EquipGun:FireServer(weaponKey)
				end))
				WeaponFrames[frameId] = weaponFrame
			end
		else
			existingFrame:Update(weaponKey, weaponValue, InventoryUtil.isStack(weaponKey))
			existingFrame.isEquipped = false
		end

		if WeaponFrames[frameId] then
			WeaponFrames[frameId].frame.LayoutOrder = layoutOrder
		end
	end

	--------------------------------------------------
	-- EQUIPPED: expand stacks, sort by rarity, create/update frames
	--------------------------------------------------
	local equippedDataList = {}
	local dataToEquipped = {} -- WeaponData -> {key, value, index}

	for weaponKey, weaponValue in equipped do
		if InventoryUtil.isStack(weaponKey) then
			local stackData = InventoryUtil.getWeaponData(weaponKey, weaponValue)
			for index = 1, weaponValue do
				-- clone per entry so each has unique table identity for dataToEquipped mapping
				local dataCopy = {
					weaponName = stackData.weaponName,
					mutations = stackData.mutations,
					level = stackData.level,
					xp = stackData.xp,
				}
				table.insert(equippedDataList, dataCopy)
				dataToEquipped[dataCopy] = { key = weaponKey, value = stackData, index = index }
			end
		else
			local data = weaponValue :: WeaponData
			table.insert(equippedDataList, data)
			dataToEquipped[data] = { key = weaponKey, value = data, index = 1 }
		end
	end

	local sortedEquipped = InventoryUtil.getSortedWeapons(equippedDataList)
	local equippedCount = #sortedEquipped
	
	gunsDisplay.Equipped.EquippedStatus.TextLabel.Text = equippedCount .. "/" .. maxSlots .. " Equipped"

	for layoutOrder, data in sortedEquipped do
		local entry = dataToEquipped[data]
		local weaponKey, weaponFrameValue, index = entry.key, entry.value, entry.index
		local frameId = "Equipped:" .. weaponKey .. ":" .. index
		activeFrameIds[frameId] = true

		local existingFrame: WeaponFrameObject = WeaponFrames[frameId]
		if existingFrame and not existingFrame.isEquipped then
			existingFrame:Destroy()
			WeaponFrames[frameId] = nil
			existingFrame = nil
		end

		if not existingFrame then
			local weaponFrame: WeaponFrameObject = WeaponFrame.new(weaponKey, weaponFrameValue, false)
			if weaponFrame then
				weaponFrame.isEquipped = true
				weaponFrame.frame.Parent = gunsDisplay.Equipped.Slots
				table.insert(weaponFrame.connections, weaponFrame.frameButton.Activated:Connect(function()
					remotes.UnequipGun:FireServer(weaponKey)
				end))
				WeaponFrames[frameId] = weaponFrame
			end
		else
			existingFrame:Update(weaponKey, weaponFrameValue, false)
			existingFrame.isEquipped = true
		end

		if WeaponFrames[frameId] then
			WeaponFrames[frameId].frame.LayoutOrder = layoutOrder
		end
	end

	--------------------------------------------------
	-- EMPTY SLOTS: fill from equippedCount+1 to MaxSlots
	--------------------------------------------------
	local emptyFrameTemplate = gunsDisplay.Equipped.Slots.UIListLayout.EmptyFrame
	local emptySlotCount = math.max(0, maxSlots - equippedCount)

	for i = 1, emptySlotCount do
		local frameId = "Empty:" .. i
		activeFrameIds[frameId] = true
		local existing = EmptyFrames[frameId]

		if not existing then
			local emptyFrame = emptyFrameTemplate:Clone()
			emptyFrame.Parent = gunsDisplay.Equipped.Slots
			emptyFrame.LayoutOrder = equippedCount + i
			EmptyFrames[frameId] = emptyFrame
		else
			existing.LayoutOrder = equippedCount + i
		end
	end

	--------------------------------------------------
	-- CLEANUP
	--------------------------------------------------
	for frameId, frame in WeaponFrames do
		if not activeFrameIds[frameId] then
			frame:Destroy()
			WeaponFrames[frameId] = nil
		end
	end

	for frameId, frame in EmptyFrames do
		if not activeFrameIds[frameId] then
			frame:Destroy()
			EmptyFrames[frameId] = nil
		end
	end
	
	self:UpdateSelectGunList()
end

function InventoryController:UpdateSelectGunList()
	local activeFrameIds = {}
	local owned = InventoryController.InventoryData.Weapons.Owned

	--------------------------------------------------
	-- UNEQUIPPED: sort by rarity, then create/update frames
	--------------------------------------------------
	local unequippedDataList = {}
	local dataToUnequipped = {} -- WeaponData -> {key, value}

	for weaponKey, weaponValue in owned do
		local data = InventoryUtil.getWeaponData(weaponKey, weaponValue)
		table.insert(unequippedDataList, data)
		dataToUnequipped[data] = { key = weaponKey, value = weaponValue }
	end

	local sortedUnequipped = InventoryUtil.getSortedWeapons(unequippedDataList)

	for layoutOrder, data in sortedUnequipped do
		local entry = dataToUnequipped[data]
		local weaponKey, weaponValue = entry.key, entry.value
		local frameId = "Owned:" .. weaponKey
		activeFrameIds[frameId] = true

		local existingFrame: WeaponFrameObject = ComponentWeaponFrames[frameId]
		if existingFrame and existingFrame.isEquipped then
			existingFrame:Destroy()
			ComponentWeaponFrames[frameId] = nil
			existingFrame = nil
		end

		if not existingFrame then
			local weaponFrame: WeaponFrameObject = WeaponFrame.new(weaponKey, weaponValue, InventoryUtil.isStack(weaponKey))
			if weaponFrame then
				weaponFrame.frame.Parent = selectGunList.WeaponList
				table.insert(weaponFrame.connections, weaponFrame.frameButton.Activated:Connect(function()
					self:OpenAddComponentMenu(weaponKey)
				end))
				ComponentWeaponFrames[frameId] = weaponFrame
			end
		else
			existingFrame:Update(weaponKey, weaponValue, InventoryUtil.isStack(weaponKey))
		end

		if ComponentWeaponFrames[frameId] then
			ComponentWeaponFrames[frameId].frame.LayoutOrder = layoutOrder
		end
	end
end

function InventoryController:UpdateItems()
	local owned = InventoryController.InventoryData.Items
	
	local itemFrameTemplate = itemsDisplay.ItemList.UIGridLayout:WaitForChild("ItemFrame")
	
	for itemKey, quantity in owned do
		local itemDef: ItemDefinition = ItemDefinitions[itemKey]
		if not itemDef then warn("[UpdateItems] No item definition for", itemKey) continue end
		
		if quantity <= 0 then
			if ItemFrames[itemKey] then
				ItemFrames[itemKey]:Destroy()
				ItemFrames[itemKey] = nil
			end
			if itemFrameConnections[itemKey] then
				itemFrameConnections[itemKey]:Disconnect()
				itemFrameConnections[itemKey] = nil
			end
			if ammoAttributeConnections[itemKey] then
				ammoAttributeConnections[itemKey]:Disconnect()
				ammoAttributeConnections[itemKey] = nil
			end
			continue
		end
		
		-- Create new item frame
		local existingFrame = ItemFrames[itemKey]
		if not existingFrame then
			existingFrame = itemFrameTemplate:Clone()
			existingFrame.Parent = itemsList
			ItemFrames[itemKey] = existingFrame
			
			local frameButton = existingFrame:WaitForChild("FrameButton")
			itemFrameConnections[itemKey] = frameButton.Activated:Connect(function()
				self:PreviewItem(itemKey)
			end)
		end
		
		-- Update item frame
		local frameButton = existingFrame:WaitForChild("FrameButton")
		local iconLabel = frameButton:WaitForChild("IconLabel")
		local nameLabel = frameButton:WaitForChild("NameLabel")
		local quantityLabel = frameButton.QuantityDisplay:WaitForChild("TextLabel")
		
		iconLabel.Image = "rbxassetid://" .. itemDef.displayImage or ""
		nameLabel.Text = itemKey
		quantityLabel.Text = "x" .. quantity

		if itemDef.itemType == "Ammo" then
			if ammoAttributeConnections[itemKey] then
				ammoAttributeConnections[itemKey]:Disconnect()
				ammoAttributeConnections[itemKey] = nil
			end

			local function refreshAmmoCount()
				local character = player.Character
				quantityLabel.Text = "x" .. tostring((character and character:GetAttribute(itemKey)) or quantity)
			end

			local character = player.Character
			if character then
				ammoAttributeConnections[itemKey] =
					character:GetAttributeChangedSignal(itemKey):Connect(refreshAmmoCount)
			end
			refreshAmmoCount()
		end
	end

	-- Cleanup old item frames
	for itemKey, frame in ItemFrames do
		if not owned[itemKey] then
			frame:Destroy()
			ItemFrames[itemKey] = nil
			if itemFrameConnections[itemKey] then
				itemFrameConnections[itemKey]:Disconnect()
				itemFrameConnections[itemKey] = nil
			end
			if ammoAttributeConnections[itemKey] then
				ammoAttributeConnections[itemKey]:Disconnect()
				ammoAttributeConnections[itemKey] = nil
			end
		end
	end
	
	
	-- Update preview display
	if InventoryController.PreviewingItem then
		self:PreviewItem(InventoryController.PreviewingItem)
	end
end

function InventoryController:PreviewItem(itemKey: string)
	local nameLabel = previewDisplay:WaitForChild("NameLabel")
	local descriptionLabel = previewDisplay:WaitForChild("DescriptionLabel")
	local actionButton  = previewDisplay:WaitForChild("ActionButton")
	local iconLabel = previewDisplay.IconDisplay:WaitForChild("IconLabel")
	local quantityLabel = previewDisplay.IconDisplay.QuantityDisplay:WaitForChild("TextLabel")
	
	local itemDef: ItemDefinition = ItemDefinitions[itemKey]
	if not itemDef then warn("[PreviewItem] No item definition for", itemKey) return end
	
	local itemQuantity = InventoryController.InventoryData.Items[itemKey]
	
	if previewButtonConnection then previewButtonConnection:Disconnect() end
	if previewAmmoConnection then previewAmmoConnection:Disconnect() previewAmmoConnection = nil end
	InventoryController.PreviewingItem = itemKey
	
	-- TODO: hide if no itemQuantity found
	if itemQuantity then
		nameLabel.Text = itemKey
		iconLabel.Image = "rbxassetid://" .. itemDef.displayImage or ""
		quantityLabel.Text = "x" .. itemQuantity
		actionButton.Visible = true
	else
		nameLabel.Text = ""
		iconLabel.Image = ""
		quantityLabel.Text = ""
		descriptionLabel.Text = ""
		actionButton.Visible = false
		return 
	end
	
	
	if itemDef.itemType == "Boost" then
		local duration = itemDef.duration or 0
		local minutes = math.floor(duration / 60)
		descriptionLabel.Text = string.format(itemDef.itemDescription, (minutes > 0 and minutes) or duration)
		
		actionButton.TextLabel.Text = "Use"
		for _, uiGradient in previewDisplay:QueryDescendants("UIGradient") do
			uiGradient.Enabled = false
			if uiGradient == actionButton.GreenGradient then 
				uiGradient.Enabled = true
			end
		end
		
		previewButtonConnection = actionButton.Activated:Connect(function()
			remotes.UseItem:FireServer(itemKey)
		end)
	elseif itemDef.itemType == "Dice" then
		descriptionLabel.Text = itemDef.itemDescription
		actionButton.TextLabel.Text = "Roll"
		for _, uiGradient in previewDisplay:QueryDescendants("UIGradient") do
			uiGradient.Enabled = false
			if uiGradient == actionButton.BlueGradient then 
				uiGradient.Enabled = true
			end
		end
		
		previewButtonConnection = actionButton.Activated:Connect(function()
			remotes.UseItem:FireServer(itemKey)
		end)
	elseif itemDef.itemType == "Component" then
		actionButton.TextLabel.Text = "Add"
		for _, uiGradient in previewDisplay:QueryDescendants("UIGradient") do
			uiGradient.Enabled = false
			if uiGradient == actionButton.PurpleGradient then 
				uiGradient.Enabled = true
			end
		end
		
		previewButtonConnection = actionButton.Activated:Connect(function()
			self:OpenComponentGunSelection(itemKey)
		end)
	elseif itemDef.itemType == "Ammo" then
		descriptionLabel.Text = itemDef.itemDescription

		local function refreshPreviewQuantity()
			local character = player.Character
			quantityLabel.Text = "x" .. tostring((character and character:GetAttribute(itemKey)) or itemQuantity)
		end

		local character = player.Character
		if character then
			previewAmmoConnection = character:GetAttributeChangedSignal(itemKey):Connect(refreshPreviewQuantity)
		end
		refreshPreviewQuantity()

		local function renderAutoEquipState()
			local on = InventoryController.AmmoData.AutoEquip[itemKey] == true
			actionButton.TextLabel.Text = if on then "Auto-Equip: ON" else "Auto-Equip: OFF"
			for _, uiGradient in previewDisplay:QueryDescendants("UIGradient") do
				uiGradient.Enabled = (uiGradient == actionButton.GreenGradient and on)
			end
			local checkmark = actionButton:FindFirstChild("CheckmarkLabel")
			if checkmark then
				checkmark.Visible = on
			end
		end

		renderAutoEquipState()

		previewButtonConnection = actionButton.Activated:Connect(function()
			local newState = remotes.ToggleAutoEquipForAmmo:InvokeServer(itemKey)
			if typeof(newState) == "boolean" then
				InventoryController.AmmoData.AutoEquip[itemKey] = newState
				renderAutoEquipState()
			end
		end)
	end
	
end

function InventoryController:OpenComponentGunSelection(componentItemKey: string)
	local descriptionLabel = previewDisplay:WaitForChild("DescriptionLabel")
	local actionButton  = previewDisplay:WaitForChild("ActionButton")
	
	local componentDef: ComponentDefinition = ItemDefinitions[componentItemKey]
	if not componentDef then warn("[OpenComponentGunSelection] No component definition for", componentItemKey) return end

	local itemQuantity = InventoryController.InventoryData.Items[componentItemKey]
	if not itemQuantity or itemQuantity <= 0 then warn("[OpenComponentGunSelection] No component item quantity for", componentItemKey) return end

	if previewButtonConnection then previewButtonConnection:Disconnect() end
	actionButton.TextLabel.Text = "Cancel"
	for _, uiGradient in previewDisplay:QueryDescendants("UIGradient") do
		uiGradient.Enabled = false
		if uiGradient == actionButton.RedGradient then 
			uiGradient.Enabled = true
		end
	end
	previewButtonConnection = actionButton.Activated:Connect(function()
		self:OpenDisplay("Items")
	end)
	
	self:UpdateSelectGunList()
	self:OpenDisplay("SelectGunList")
end

function InventoryController:OpenAddComponentMenu(weaponKey: string)
	if not weaponKey then warn("[OpenAddComponentMenu] No weaponKey") return end

	local componentKey = InventoryController.PreviewingItem
	local componentDef: ComponentDefinition = componentKey and ItemDefinitions[componentKey]
	local componentQuantity = componentKey and InventoryController.InventoryData.Items[componentKey]

	if not componentKey
		or not componentDef or componentDef.itemType ~= "Component"
		or not componentQuantity or componentQuantity <= 0 then
		warn("[OpenAddComponentMenu] Invalid component:", componentKey)
		return
	end

	local weaponValue = InventoryController.InventoryData.Weapons.Owned[weaponKey]
	if not weaponValue then warn("[OpenAddComponentMenu] No weapon value for", weaponKey) return end

	local weaponData = InventoryUtil.getWeaponData(weaponKey, weaponValue)
	if not weaponData then warn("[OpenAddComponentMenu] No weaponData for", weaponKey) return end

	self.ComponentSession = {
		componentKey = componentKey,
		weaponKey = weaponKey,
		amount = 1,
		addAll = false,
	}

	self:OpenDisplay("AddComponent")

	headerText.Text = string.format("Add %s", componentKey)

	local weaponIconContainer = addComponentDisplay.WeaponInfoDisplay:WaitForChild("WeaponIconContainer")
	local existingIcon = weaponIconContainer:FindFirstChild("WeaponIconFrame")
	if existingIcon then existingIcon:Destroy() end
	local weaponImageLabel = WeaponUtil.getDisplayImageLabel(weaponData.weaponName, weaponData.mutations)
	if weaponImageLabel then weaponImageLabel.Parent = weaponIconContainer end

	-- sync slider to this session
	slideBar:SetEnabled(true) 
	slideBar:UpdateConfig({ min = 1, max = componentQuantity })
	slideBar:SetValue(1)

	self:RefreshAddComponentDisplay()
end

function InventoryController:RefreshAddComponentDisplay()
	local addButton = addComponentDisplay:WaitForChild("AddButton")
	local addAllButton = addAllFrame:WaitForChild("Button")
	local weaponInfoDisplay = addComponentDisplay:WaitForChild("WeaponInfoDisplay")
	local currentWeaponInfoDisplay = weaponInfoDisplay:WaitForChild("CurrentWeaponInfo")
	local resultingInfoDisplay = weaponInfoDisplay:WaitForChild("ResultWeaponInfo")
	local addedXPlabel = weaponInfoDisplay:WaitForChild("AddedXPLabel")
	
	local r = self:ResolveComponentSession()
	if not r then warn("[RefreshAddComponentDisplay] No component session") return end
	
	local componentSession: ComponentSession = r.session
	local componentKey = componentSession.componentKey
	local weaponKey = componentSession.weaponKey
	local amount = componentSession.addAll and r.quantity or componentSession.amount
	local weaponData: WeaponData = r.weaponData
	
	local weaponDef: WeaponDefinition = WeaponDefinitions[weaponData.weaponName]
	local componentDef: ComponentDefinition = ItemDefinitions[componentKey]

	local xpAdded = amount * componentDef.addedXP
	addedXPlabel.Text = string.format("+%d xp", xpAdded)
	
	-- display current weapon info
	WeaponUtil.displayWeaponInfo(currentWeaponInfoDisplay, weaponData)
	
	-- display resulting weapon info
	local resultingWeaponData = table.clone(weaponData)
	resultingWeaponData.xp = weaponData.xp + xpAdded
	WeaponUtil.displayWeaponInfo(resultingInfoDisplay, resultingWeaponData)
	
	addButton.TextLabel.Text = string.format("Add (%d)", amount)
	
	addAllButton.CheckmarkLabel.Visible = componentSession.addAll
	if componentSession.addAll then
		slideBar:SetValue(r.quantity)
		slideBar:SetEnabled(false)
	else
		slideBar:SetEnabled(true)
	end
end

function InventoryController:ResolveComponentSession()
	local s: ComponentSession = self.ComponentSession
	if not s then return nil end

	local quantity = self.InventoryData.Items[s.componentKey] or 0
	local weaponValue = self.InventoryData.Weapons.Owned[s.weaponKey]
	if quantity <= 0 or not weaponValue then return nil end

	return {
		session = s,
		weaponData = InventoryUtil.getWeaponData(s.weaponKey, weaponValue),
		quantity = quantity,
	}
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function InventoryController:Init(controllers)
	self.Controllers = controllers
	
	equipBestButton.Activated:Connect(function()
		remotes.EquipBestWeapons:FireServer()
	end)
end

function InventoryController:Start()
	-- Get inital inventory data snapshot
	player:GetAttributeChangedSignal("Loaded"):Once(function()
		getInventoryData()
	end)
	if player:GetAttribute("Loaded") then getInventoryData() end
	
	self:UpdateGuns()
	self:UpdateItems()
	_setupUI()

	player.CharacterAdded:Connect(function()
		self:UpdateItems()
	end)

	-- inventory data delta  
	remotes.InventoryUpdated.OnClientEvent:Connect(function(category, updatedData: {}, maxSlots: number?)
		if not InventoryController.InventoryData[category] then
			InventoryController.InventoryData[category] = {}
		end
		InventoryController.InventoryData[category] = updatedData
		
		if category == "Weapons" then
			if maxSlots ~= nil then
				InventoryController.MaxSlots = maxSlots
			end
			self:UpdateGuns()
		elseif category == "Items" then
			self:UpdateItems()
			
			local resolvedSession = self:ResolveComponentSession()
			if resolvedSession and self.CurrentDisplay == "AddComponent" then
				slideBar:UpdateConfig({ min = 1, max = resolvedSession.quantity })
				if resolvedSession.session.addAll then
					slideBar:SetValue(resolvedSession.quantity)   -- keep pinned to new top
				else
					resolvedSession.session.amount = math.clamp(resolvedSession.session.amount, 1, resolvedSession.quantity)
				end
				self:RefreshAddComponentDisplay()
			elseif not resolvedSession and self.CurrentDisplay == "AddComponent" then
				self:OpenDisplay("Items")
				self.ComponentSession = nil
			end
		end
	end)
	
	-- Added item frame popup
	remotes.ItemAdded.OnClientEvent:Connect(onItemAdded)
end


return InventoryController
