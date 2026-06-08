local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local utils = ReplicatedStorage.Util
local InventoryUtil = require(utils.InventoryUtil)
local RollUtil = require(utils.RollUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local WeaponDefinitions = require(GameAssets.WeaponAssets.WeaponDefinitions)

local WeaponInfoPopup = require(ReplicatedStorage.Modules.WeaponInfoPopup)
local weaponFrameTemplate = script:WaitForChild("WeaponFrame")
local weaponFrameRarityGradients = script:WaitForChild("WeaponFrameRarityGradients")
--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponData = InventoryUtil.WeaponData
type WeaponDefinition = WeaponDefinitions.WeaponDefinition
type WeaponInfoPopupObject = WeaponInfoPopup.WeaponInfoPopupObject

local WeaponFrame = {}
WeaponFrame.__index = WeaponFrame

function WeaponFrame.new(key: string, value: WeaponData | number, showAsStack: boolean?)
	local self = setmetatable({}, WeaponFrame)

	self._key = key
	self._rawValue = value
	self._weaponData = InventoryUtil.getWeaponData(key, value)
	self._showAsStack = showAsStack == true
	self._weaponInfoPopup = nil
	self.connections = {}

	local weaponDef = WeaponDefinitions[self._weaponData.weaponName]
	if not weaponDef then 
		warn("WeaponFrame.new - No weapon definition for", self._weaponData.weaponName)
		return nil
	end
	self.weaponDef = weaponDef

	local frame = self:CreateFrame()
	if not frame then return end
	self.frame = frame

	self:UpdateFrame()

	return self
end

function WeaponFrame:CreateFrame()
	local frame = weaponFrameTemplate
	if not frame then 
		warn("WeaponFrame:CreateFrame() - No frame for rarity")
		return nil
	end
	frame = frame:Clone()
	
	local frameButton: ImageButton = frame:WaitForChild("FrameButton")
	self.frameButton = frameButton
	
	local rarity = WeaponUtil.deriveRarity(self._weaponData.weaponName, self._weaponData.mutations)
	
	local rarityGradient = weaponFrameRarityGradients:WaitForChild(rarity)
	if rarityGradient then
		rarityGradient = rarityGradient:Clone()
		rarityGradient.Parent = frameButton
	end
	
	local iconContainer = frameButton:WaitForChild("WeaponIconContainer")
	local oddsLabel  = frameButton:WaitForChild("OddsLabel")
	
	oddsLabel.Text = "1 /" .. math.round(1 / self.weaponDef.odds)
	
	WeaponUtil.applyRarityTextEffects(oddsLabel, rarity)

	local weaponImageLabel = WeaponUtil.getDisplayImageLabel(self._weaponData.weaponName, self._weaponData.mutations)
	if weaponImageLabel then
		weaponImageLabel.Parent = iconContainer
	end
	
	self:BindPreview()
	frameButton:AddTag("ButtonUp")
	
	return frame
end

function WeaponFrame:UpdateFrame()
	local frame = self.frame
	if not frame then return end
	
	local frameButton = frame:WaitForChild("FrameButton")
	local quantityLabel = frameButton:WaitForChild("QuantityLabel")
	local levelLabel = frameButton:WaitForChild("LevelLabel")
	
	if self._showAsStack then
		quantityLabel.Text = "x" .. self._rawValue
		quantityLabel.Visible = true
		levelLabel.Visible = false
	else
		quantityLabel.Visible = false
		local deriveWeaponStats = WeaponUtil.deriveWeaponStats(self._weaponData)
		local currentLevel = deriveWeaponStats.level
		if currentLevel > 1 then
			levelLabel.Visible = true
			levelLabel.Text = "Lvl " .. currentLevel
		else
			levelLabel.Visible = false
		end
	end
	
end

function WeaponFrame:BindPreview()
	local frameButton: ImageButton = self.frameButton
	local iconLabel: ImageLabel = frameButton:WaitForChild("WeaponIconContainer")
	local oddsLabel  = frameButton:WaitForChild("OddsLabel")
	
	local originalSize = iconLabel.Size
	
	local function preview(state: boolean)
		if state then
			
			local infoPopup: WeaponInfoPopupObject = WeaponInfoPopup.new(frameButton, self._weaponData)
			if infoPopup then
				self._weaponInfoPopup = infoPopup
				print("Showing info popup")
			end
				
			TweenService:Create(iconLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(originalSize.X.Scale*1.25, originalSize.Y.Scale*1.25)}):Play()
		else
			if self._weaponInfoPopup then
				self._weaponInfoPopup:Destroy()
				self._weaponInfoPopup = nil
				print("Deleting info popup")	
			end
			
			TweenService:Create(iconLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {Size = UDim2.fromScale(originalSize.X.Scale, originalSize.Y.Scale)}):Play()
		end
	end

	-- Hover connections
	
	-- Mouse / PC
	table.insert(self.connections, frameButton.MouseEnter:Connect(function()
		preview(true)
	end))
	table.insert(self.connections, frameButton.MouseLeave:Connect(function()
		preview(false)
	end))
end

function WeaponFrame:Update(key: string, value: WeaponData | number, showAsStack: boolean?)
	self._key = key
	self._rawValue = value
	self._showAsStack = showAsStack == true
	self._weaponData = InventoryUtil.getWeaponData(key, value)
	self:UpdateFrame()
end

function WeaponFrame:Destroy()
	self.frame:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	
	if self._weaponInfoPopup then
		self._weaponInfoPopup:Destroy()
		self._weaponInfoPopup = nil
	end
end

export type WeaponFrameObject = typeof(setmetatable({} :: {
	frame: Frame,
	frameButton: ImageButton,
	connections: {RBXScriptConnection},
	isEquipped: boolean?,
	_showAsStack: boolean,
}, WeaponFrame))

return WeaponFrame
