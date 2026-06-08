-- A "linger" effect is a damage-over-time applied on hit (e.g. incendiary burn,
-- and later poison). The server ticks the damage; the client clones a matching
-- "Linger" part from the ammo type's projectile asset folder. Adding a new
-- lingering ammo is just a definition with a `linger` block + the Studio asset.
export type LingerConfig = {
	tickPercentOfHit: number, -- each tick deals this fraction of the bullet's hit damage
	tickInterval: number, -- seconds between ticks
	duration: number, -- total seconds the effect lasts (refreshed on re-hit)
}

export type AmmoDefinition = {
	name: string,
	order: number,
	autoEquippedByDefault: boolean?,
	consumable: boolean?,
	linger: LingerConfig?,
}

export type AmmoProfileData = {[string]: any}

local DEFINITIONS: {AmmoDefinition} = {
	{ name = "Normal", order = 1, autoEquippedByDefault = true },
	{ name = "Smart", order = 2, autoEquippedByDefault = true, consumable = true },
	{ name = "Incendiary", order = 3, consumable = true, linger = { tickPercentOfHit = 5, tickInterval = 0.5, duration = 3 } },
	{ name = "Explosive", order = 4, consumable = true },
}

local AmmoTypes = {}

AmmoTypes.Definitions = DEFINITIONS
AmmoTypes.Default = DEFINITIONS[1].name

AmmoTypes.All = {}
AmmoTypes.Consumable = {}
AmmoTypes.AllSet = {}
AmmoTypes.ConsumableSet = {}
AmmoTypes.LingerByType = {}
AmmoTypes.ByName = {} :: { [string]: AmmoDefinition }
AmmoTypes.OrderByName = {} :: { [string]: number }
AmmoTypes.AutoEquipDefaultByName = {} :: { [string]: boolean }

for _, definition in DEFINITIONS do
	AmmoTypes.ByName[definition.name] = definition
	AmmoTypes.OrderByName[definition.name] = definition.order
	AmmoTypes.AutoEquipDefaultByName[definition.name] = definition.autoEquippedByDefault == true
	table.insert(AmmoTypes.All, definition.name)
	AmmoTypes.AllSet[definition.name] = true

	if definition.consumable == true then
		table.insert(AmmoTypes.Consumable, definition.name)
		AmmoTypes.ConsumableSet[definition.name] = true
	end

	if definition.linger then
		AmmoTypes.LingerByType[definition.name] = definition.linger
	end
end

function AmmoTypes.isKnown(ammoType: any): boolean
	return typeof(ammoType) == "string" and AmmoTypes.AllSet[ammoType] == true
end

function AmmoTypes.getLinger(ammoType: any): LingerConfig?
	if typeof(ammoType) ~= "string" then
		return nil
	end

	return AmmoTypes.LingerByType[ammoType]
end

function AmmoTypes.isConsumable(ammoType: any): boolean
	return typeof(ammoType) == "string" and AmmoTypes.ConsumableSet[ammoType] == true
end

function AmmoTypes.getOrder(ammoType: any): number
	if typeof(ammoType) == "string" and AmmoTypes.OrderByName[ammoType] ~= nil then
		return AmmoTypes.OrderByName[ammoType]
	end

	return 0
end

function AmmoTypes.isAutoEquippedByDefault(ammoType: any): boolean
	return typeof(ammoType) == "string" and AmmoTypes.AutoEquipDefaultByName[ammoType] == true
end

function AmmoTypes.createAutoEquipMap(): {[string]: boolean}
	local autoEquip = {}

	for _, definition in DEFINITIONS do
		autoEquip[definition.name] = definition.autoEquippedByDefault == true
	end

	return autoEquip
end

function AmmoTypes.createAmountMap(defaultAmount: number?): {[string]: number}
	local amount = if typeof(defaultAmount) == "number" then math.max(0, math.floor(defaultAmount)) else 0
	local amounts = {}

	for _, ammoType in AmmoTypes.Consumable do
		amounts[ammoType] = amount
	end

	return amounts
end

function AmmoTypes.createProfileData(): AmmoProfileData
	return {
		SelectedType = AmmoTypes.Default,
		AutoEquip = AmmoTypes.createAutoEquipMap(),
	}
end

return AmmoTypes
