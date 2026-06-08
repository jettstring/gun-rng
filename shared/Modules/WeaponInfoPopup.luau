local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local utils = ReplicatedStorage.Util
local InventoryUtil = require(utils.InventoryUtil)
local RollUtil = require(utils.RollUtil)
local WeaponUtil = require(ReplicatedStorage.Util.WeaponUtil)

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local WeaponDefinitions = require(GameAssets.WeaponAssets.WeaponDefinitions)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local PopupsGui = playerGui:WaitForChild("Popups")

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type WeaponData = InventoryUtil.WeaponData
type WeaponDefinition = WeaponDefinitions.WeaponDefinition

local current = nil

local WeaponInfoPopup = {}
WeaponInfoPopup.__index = WeaponInfoPopup

function WeaponInfoPopup.new(imageButton: ImageButton, weaponData: WeaponData)
	if current then current:Destroy() end
	local self = setmetatable({}, WeaponInfoPopup)
	
	self._imageButton = imageButton
	self._weaponData = weaponData
	self.connections = {}
	
	local weaponDef = WeaponDefinitions[weaponData.weaponName]
	if not weaponDef then 
		warn("WeaponInfoPopup.new - No weapon definition for", weaponData.weaponName)
		return nil
	end
	self.weaponDef = weaponDef

	local frame = self:CreateFrame()
	if not frame then
		warn("WeaponInfoPopup.new - No frame")
		return
	end
	self.frame = frame
	
	self:BindConnections()
	
	current = self
	return self
end

function WeaponInfoPopup:CreateFrame()
	local frame = PopupsGui:WaitForChild("WeaponInfoFrame")
	if not frame then 
		warn("WeaponInfoPopup:CreateFrame() - No frame")
		return nil
	end
	frame = frame:Clone()
	frame.Parent = PopupsGui

	WeaponUtil.displayWeaponInfo(frame, self._weaponData)
	
	return frame
end

function WeaponInfoPopup:BindConnections()
	local frame: ImageLabel = self.frame
	if not frame then return end
	
	local button  = self._imageButton
	if not button then return end
	
	-- PC
	table.insert(self.connections, button.MouseMoved:Connect(function(x, y)
		self:PositionAt(Vector2.new(x, y))
	end))
	
	-- Console
	table.insert(self.connections, button.SelectionGained:Connect(function()
		local pos = button.AbsolutePosition
		local size = button.AbsoluteSize
		self:PositionAt(Vector2.new(pos.X + size.X / 2, pos.Y))
	end))
end

function WeaponInfoPopup:PositionAt(pos: Vector2)
	local frame = self.frame
	if not frame then return end
	frame.Position = UDim2.fromOffset(pos.X, pos.Y)
	frame.Visible = true
end


function WeaponInfoPopup:Destroy()
	if current == self then current = nil end
	self.frame:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

export type WeaponInfoPopupObject = typeof(setmetatable({} :: {
	frame: Frame,
	connections: {RBXScriptConnection},
}, WeaponInfoPopup))

return WeaponInfoPopup
