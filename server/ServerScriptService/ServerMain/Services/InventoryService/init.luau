local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES --  
--------------------------------------------------
 
local utils = ReplicatedStorage.Util
local InventoryUtil = require(utils.InventoryUtil)
local RollUtil = require(utils.RollUtil)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ItemAssets = GameAssets:WaitForChild("ItemAssets")
local ItemDefinitions = require(ItemAssets.ItemDefinitions)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	UseItem = remotesFolder.Inventory.UseItem,
	EquipGun = remotesFolder.Inventory.EquipGun,
	UnequipGun = remotesFolder.Inventory.UnequipGun,
	EquipBestWeapons = remotesFolder.Inventory.EquipBestWeapons,
	InventoryUpdated = remotesFolder.Inventory.InventoryUpdated,
	BoostsUpdated = remotesFolder.Boosts.BoostsUpdated,
	ItemAdded = remotesFolder.Inventory.ItemAdded,
	NewWeaponDiscovered = remotesFolder.Index.NewWeaponDiscovered,
	AddComponentToWeapon = remotesFolder.Inventory.AddComponentToWeapon,
	
	-- RFs
	GetInventory = remotesFolder.Inventory.GetInventory
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponData = InventoryUtil.WeaponData
type RollResult = RollUtil.RollResult

type ItemDefinition = ItemDefinitions.ItemDefinition
type ComponentDefinition = ItemDefinitions.ComponentDefinition
type BoostDefinition = ItemDefinitions.BoostDefinition
type DiceDefinition = ItemDefinitions.DiceDefinition

--------------------------------------------------
-- STATE --
--------------------------------------------------
local InventoryService = {}
InventoryService.Services = {}
InventoryService.Signals = {}

InventoryService.ActiveBoosts = {} -- [player] = {[boostType] = {boostName = { endTime = os.time() }} }

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function InventoryService:AddItem(player: Players, itemName: string, quantity: number)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[AddItem] No profile for player", player) return nil end
	
	local itemDef: ItemDefinition = ItemDefinitions[itemName]
	if not itemDef then warn("[AddItem] Invalid item name:", itemName) return nil end
	
	quantity = math.clamp(quantity or 1, 1, 99)
	
	profile.Inventory.Items[itemName] = (profile.Inventory.Items[itemName] or 0) + quantity
	
	-- Update client
	remotes.InventoryUpdated:FireClient(player, "Items", profile.Inventory.Items)
	remotes.ItemAdded:FireClient(player, itemName, quantity)

	if itemDef.itemType == "Ammo" then
		self.Services.GunService:OnAmmoItemAdded(player, itemName)
	end

	return true
end

function InventoryService:RemoveItem(player: Players, itemName: string, quantity: number)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[RemoveItem] No profile for player", player) return nil end

	local itemDef: ItemDefinition = ItemDefinitions[itemName]
	if not itemDef then warn("[RemoveItem] Invalid item name:", itemName) return nil end
	
	quantity = math.max(quantity or 1, 1)
	
	-- remove from inventory
	profile.Inventory.Items[itemName] = math.max(profile.Inventory.Items[itemName] - quantity, 0)
	if profile.Inventory.Items[itemName] <= 0 then
		profile.Inventory.Items[itemName] = nil
	end

	-- Update client
	remotes.InventoryUpdated:FireClient(player, "Items", profile.Inventory.Items)
end

function InventoryService:UseItem(player: Players, itemName: string)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[UseItem] No profile for player", player) return nil end

	local itemDef: ItemDefinition = ItemDefinitions[itemName]
	if not itemDef then warn("[UseItem] Invalid item name:", itemName) return nil end

	if not profile.Inventory.Items[itemName] or profile.Inventory.Items[itemName] <= 0 then
		self.Services.NotificationService:Error(player, "You do not have this item!")
		local itemEntry = profile.Inventory.Items[itemName]
		if not itemEntry or itemEntry <= 0 then
			profile.Inventory.Items[itemName] = nil
		end
		return
	end

	local success, result = pcall(function()
		local handlerModule = require(script.ItemHandlers:FindFirstChild(itemDef.itemType))
		return handlerModule.Use(player, self.Services, itemName)
	end)

	if not success then
		warn("[UseItem] Handler errored:", result)
		self.Services.NotificationService:Error(player, "Failed to use item!")
		return
	end
	if not result then
		-- Handler rejected
		return
	end

	-- remove from inventory
	self:RemoveItem(player, itemName, 1)

	return true
end

function InventoryService:AddWeapon(player: Player, weaponData: WeaponData | RollResult): string?
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[AddWeapon] No profile for player", player) return nil end
	
	local owned = profile.Inventory.Weapons.Owned
	local equipped = profile.Inventory.Weapons.Equipped
	local key = InventoryUtil.generateWeaponKey(weaponData)
	local maxSlots = self.Services.UpgradeService:GetGunSlots(player)
	
	if weaponData.level then
		-- Unique entry
		owned[key] = {
			weaponName = weaponData.weaponName,
			mutations = weaponData.mutations or {},
			level = weaponData.level,
			xp = weaponData.xp
		}
	else
		-- stacked entry
		owned[key] = (owned[key] or 0) + 1
	end
	
	-- New Discovery check
	local indexData = self.Services.IndexService:GetPlayerIndexData(player)
	if indexData and indexData.Discovered and indexData.Discovered.Weapons then
		local weaponIndexEntry = indexData.Discovered.Weapons[weaponData.weaponName]
		local isNewWeapon = weaponIndexEntry == nil
		if isNewWeapon then
			weaponIndexEntry = {}
			indexData.Discovered.Weapons[weaponData.weaponName] = weaponIndexEntry
		end

		local newMutations = {}
		local mutations = weaponData.mutations or {}

		if next(mutations) == nil then
			-- no mutations only Base
			if not weaponIndexEntry.Base then
				weaponIndexEntry.Base = true
				table.insert(newMutations, "Base")
			end
		else
			for mutationName in pairs(mutations) do
				if not weaponIndexEntry[mutationName] then
					weaponIndexEntry[mutationName] = true
					table.insert(newMutations, mutationName)
				end
			end
		end

		if isNewWeapon or #newMutations > 0 then
			self.Services.IndexService:SendIndexData(player)
			remotes.NewWeaponDiscovered:FireClient(player, weaponData.weaponName, newMutations)
			print("Discovered:", weaponData.weaponName, "new mutations:", newMutations)
		end
	end
	
	-- equip if not fully hitting max slots equipped
	local equippedCount = 0
	for key, value in equipped do
		if InventoryUtil.isStack(key) then
			equippedCount += value
		else
			equippedCount += 1
		end
	end
	if equippedCount < maxSlots then
		self:EquipWeapon(player, key)
	end
	
	-- Update client
	remotes.InventoryUpdated:FireClient(player, "Weapons", profile.Inventory.Weapons, maxSlots)
	return key
end

function InventoryService:EquipWeapon(player: Player, weaponKey: string): boolean
	if type(weaponKey) ~= "string" or weaponKey == "" then
		return false
	end
	
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[EquipWeapon] No profile for player", player) return false end
	
	local owned = profile.Inventory.Weapons.Owned
	local equipped = profile.Inventory.Weapons.Equipped
	local maxSlots = self.Services.UpgradeService:GetGunSlots(player)

	if owned[weaponKey] == nil then
		warn("[EquipWeapon] Player does not own weapon", player, weaponKey)
		return false
	end


	local equippedCount = 0
	for key, value in equipped do
		if InventoryUtil.isStack(key) then
			equippedCount += value
		else
			equippedCount += 1
		end
	end

	if equippedCount >= maxSlots then
		local equippedDataList = {}
		local dataToKey = {}
		for key, value in equipped do
			local data = InventoryUtil.getWeaponData(key, value)
			table.insert(equippedDataList, data)
			dataToKey[data] = key
		end

		local sorted = InventoryUtil.getSortedWeapons(equippedDataList)
		local worstKey = dataToKey[sorted[1]]
		if worstKey then
			local worstValue = equipped[worstKey]
			if InventoryUtil.isStack(worstKey) then
				equipped[worstKey] -= 1
				if equipped[worstKey] <= 0 then
					equipped[worstKey] = nil
				end
				owned[worstKey] = (owned[worstKey] or 0) + 1
			else
				equipped[worstKey] = nil
				owned[worstKey] = worstValue
			end
		end
	end
	
	-- Update slots
	local weaponValue = owned[weaponKey]
	if InventoryUtil.isStack(weaponKey) then
		owned[weaponKey] = weaponValue - 1
		if owned[weaponKey] <= 0 then
			owned[weaponKey] = nil
		end

		equipped[weaponKey] = (equipped[weaponKey] or 0) + 1
	else
		owned[weaponKey] = nil
		equipped[weaponKey] = weaponValue
	end
	
	-- Update client
	remotes.InventoryUpdated:FireClient(player, "Weapons", profile.Inventory.Weapons, maxSlots)
	self.Services.GunService:SyncEquippedWeapons(player)
	
	print("[EquipWeapon] player", player, "weaponKey", weaponKey)
	return true
end

function InventoryService:EquipBestWeapons(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[EquipBestWeapons] No profile for player", player) return end

	local weapons = profile.Inventory.Weapons
	local equipped = weapons.Equipped
	local owned = weapons.Owned
	local maxSlots = self.Services.UpgradeService:GetGunSlots(player)

	-- Explode owned + equipped into individual units, tracking the key each came from
	local dataList = {}
	local dataToKey = {}

	local function collect(container)
		for key, value in container do
			if InventoryUtil.isStack(key) then
				for _ = 1, value do
					local data = InventoryUtil.getWeaponData(key, value) -- fresh table per unit
					table.insert(dataList, data)
					dataToKey[data] = key
				end
			else
				table.insert(dataList, value)
				dataToKey[value] = key
			end
		end
	end

	collect(owned)
	collect(equipped)

	-- getSortedWeapons returns worst -> best, so the best maxSlots live at the tail
	local sorted = InventoryUtil.getSortedWeapons(dataList)

	table.clear(equipped)
	table.clear(owned)

	local equipFrom = math.max(#sorted - maxSlots, 0)
	for i, data in ipairs(sorted) do
		local target = (i > equipFrom) and equipped or owned
		local key = dataToKey[data]
		if InventoryUtil.isStack(key) then
			target[key] = (target[key] or 0) + 1
		else
			target[key] = data
		end
	end

	remotes.InventoryUpdated:FireClient(player, "Weapons", profile.Inventory.Weapons, maxSlots)
	self.Services.GunService:SyncEquippedWeapons(player)
end

function InventoryService:UnequipWeapon(player: Player, weaponKey: string): boolean
	if type(weaponKey) ~= "string" or weaponKey == "" then
		return false
	end

	print("[UnequipWeapon] player", player, "weaponKey", weaponKey)

	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[UnequipWeapon] No profile for player", player) return false end

	local owned = profile.Inventory.Weapons.Owned
	local equipped = profile.Inventory.Weapons.Equipped
	local maxSlots = self.Services.UpgradeService:GetGunSlots(player)

	local weaponValue = equipped[weaponKey]
	if weaponValue == nil then
		return false
	end

	if InventoryUtil.isStack(weaponKey) then
		equipped[weaponKey] -= 1
		if equipped[weaponKey] <= 0 then
			equipped[weaponKey] = nil
		end
		owned[weaponKey] = (owned[weaponKey] or 0) + 1
	else
		equipped[weaponKey] = nil
		owned[weaponKey] = weaponValue
	end

	remotes.InventoryUpdated:FireClient(player, "Weapons", profile.Inventory.Weapons, maxSlots)
	self.Services.GunService:SyncEquippedWeapons(player)

	return true
end


function InventoryService:AddComponentToWeapon(player: Players, weaponKey: string, componentKey: string, quantity: number)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[AddComponent] No profile for player", player) return nil end

	local componentDef: ComponentDefinition = ItemDefinitions[componentKey]
	if not componentDef then warn("[AddComponent] Invalid item name:", componentKey) return nil end
	

	-- add to weapon
	local weaponEntry = profile.Inventory.Weapons.Owned[weaponKey]
	if not weaponEntry then
		self.Services.NotificationService:Error(player, "You do not have this weapon!")
		return
	end
	
	local itemEntry = profile.Inventory.Items[componentKey]
	if not itemEntry or itemEntry <= 0 then
		self.Services.NotificationService:Error(player, "You do not have this item!")
		profile.Inventory.Items[componentKey] = nil
		return
	end
	
	quantity = math.clamp(quantity, 1, itemEntry)
	local addedXP = quantity * componentDef.addedXP
	
	-- add xp to weapon
	self.Services.GunService:IncrementGunXP(player, weaponKey, addedXP)

	-- remove component from inventory
	self:RemoveItem(player, componentKey, quantity)
	
	print(string.format("Added %dx %s to %s", quantity, componentKey, weaponKey))

	return true
end

function InventoryService:GetPlayerActiveBoostType(player: Player, boostType: string)
	local total = 0
	local activeBoosts = self.ActiveBoosts[player]
	if not activeBoosts then return total end

	local activeTypeData = activeBoosts[boostType]
	if not activeTypeData then return total end

	local now = os.time()
	for boostName, boostData in activeTypeData do
		if boostData.endTime and boostData.endTime <= now then continue end
		local boostDef: BoostDefinition = ItemDefinitions[boostName]
		if not boostDef then continue end
		
		total += boostDef.multiplier
	end

	return total
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function InventoryService:Init(services)
	self.Services = services

end

function InventoryService:Start()
	
	Players.PlayerRemoving:Connect(function(player)
		self.ActiveBoosts[player] = nil
	end)
	
	remotes.EquipGun.OnServerEvent:Connect(function(player, weaponKey: string)
		self:EquipWeapon(player, weaponKey)
	end)
	
	remotes.UnequipGun.OnServerEvent:Connect(function(player, weaponKey: string)
		self:UnequipWeapon(player, weaponKey)
	end)
	
	remotes.EquipBestWeapons.OnServerEvent:Connect(function(player)
		self:EquipBestWeapons(player)
	end)
	
	remotes.UseItem.OnServerEvent:Connect(function(player, itemKey: string)
		self:UseItem(player, itemKey)
	end)
	
	
	remotes.GetInventory.OnServerInvoke = function(player)
		local profile = self.Services.DataService:GetProfile(player)
		if not profile then return end
		
		local maxSlots = self.Services.UpgradeService:GetGunSlots(player)

		return profile.Inventory, maxSlots, self.Services.GunService:GetAmmoView(player)
	end
	
	remotes.AddComponentToWeapon.OnServerEvent:Connect(function(player, weaponKey: string, componentKey: string, quantity: number)
		self:AddComponentToWeapon(player, weaponKey, componentKey, quantity)
	end)
	
	-- Periodic boosts check
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, activeBoosts in self.ActiveBoosts do
				local expired = false
				
				for _, boostTypeData in activeBoosts do
					for boostName, boostData in boostTypeData do
						local endTime = boostData.endTime
						if endTime and endTime <= now then
							boostTypeData[boostName] = nil
							expired = true
						end
					end
				end
				
				if expired then
					remotes.BoostsUpdated:FireClient(player, self.ActiveBoosts[player])
				end
			end
		end
	end)
end


return InventoryService
