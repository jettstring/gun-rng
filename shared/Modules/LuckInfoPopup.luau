local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)


local utils = ReplicatedStorage.Util
local RollUtil = require(utils.RollUtil)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local PopupsGui = playerGui:WaitForChild("Popups")

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type LuckTable = RollUtil.LuckTable

local LuckInfoFrame = {}
LuckInfoFrame.__index = LuckInfoFrame

function LuckInfoFrame.new(imageButton: ImageButton, luckTable: LuckTable)
	local self = setmetatable({}, LuckInfoFrame)
	
	self._imageButton = imageButton
	self._luckTable = luckTable
	self.connections = {}   


	local frame = self:CreateFrame()
	if not frame then
		warn("LuckInfoFrame.new - No frame")
		return
	end
	self.frame = frame
	
	self:Update(luckTable)
	
	return self
end

function LuckInfoFrame:CreateFrame()
	local frame = PopupsGui:WaitForChild("LuckInfoFrame")
	if not frame then 
		warn("LuckInfoFrame:CreateFrame() - No frame")
		return nil
	end
	frame = frame:Clone()
	frame.Parent = PopupsGui
	
	local button  = self._imageButton
	if not button then return end

	-- PC
	table.insert(self.connections, button.MouseEnter:Connect(function()
		self:Show()
	end))
	table.insert(self.connections, button.MouseLeave:Connect(function()
		self:Hide()
	end))

	-- Console
	table.insert(self.connections, button.SelectionGained:Connect(function()
		self:Show()
	end))
	table.insert(self.connections, button.SelectionLost:Connect(function()
		self:Hide()
	end))
	
	-- TODO: Mobile 
	
	
	return frame
end


function LuckInfoFrame:Update(luckTable: LuckTable)
	local frame = self.frame
	if not frame then return end
	
	local luckTable = luckTable or self._luckTable
	if not luckTable then return end
	
	local addedValuesDisplay = frame:WaitForChild("AddedValuesDisplay")
	local multipliedValuesDisplay = frame:WaitForChild("MultipliedValuesDisplay")
	local valueTemplate = frame.UIListLayout:WaitForChild("ValueTemplate")
	
	local addedValues = luckTable.Added
	local multipliedValues = luckTable.Multiplied
	
	-- display added values
	if addedValues and next(addedValues) then
		for valueName, value in addedValues do
			local existingFrame = addedValuesDisplay:FindFirstChild(valueName)
			if not existingFrame then
				existingFrame = valueTemplate:Clone()
				existingFrame.Parent = addedValuesDisplay
				existingFrame.Name = valueName
				existingFrame.Visible = true
			end
			
			local nameLabel = existingFrame:WaitForChild("NameLabel")
			local valueLabel = existingFrame:WaitForChild("ValueLabel")
			
			nameLabel.Text = valueName
			valueLabel.Text = "+" .. Abbreviate.AbbreviateNumber(value, 1)
		end
	end
	
	-- display multiplied values
	if multipliedValues and next(multipliedValues) then
		for valueName, value in multipliedValues do
			local existingFrame = multipliedValuesDisplay:FindFirstChild(valueName)
			if not existingFrame then
				existingFrame = valueTemplate:Clone()
				existingFrame.Parent = multipliedValuesDisplay
				existingFrame.Name = valueName
				existingFrame.Visible = true
			end
			
			local nameLabel = existingFrame:WaitForChild("NameLabel")
			local valueLabel = existingFrame:WaitForChild("ValueLabel")
			
			nameLabel.Text = valueName
			valueLabel.Text = "+" .. Abbreviate.AbbreviateNumber(value, 1)
		end
	end
	
	-- Cleanup old value frames
	for _, child in addedValuesDisplay:GetChildren() do
		if child:IsA("Frame") then
			if not addedValues[child.Name] then
				child:Destroy()
			end
		end
	end
	
	for _, child in multipliedValuesDisplay:GetChildren() do
		if child:IsA("Frame") then
			if not multipliedValues[child.Name] then
				child:Destroy()
			end
		end
	end
	
end

function LuckInfoFrame:Show()
	local frame = self.frame
	if not frame then return end
	frame.Visible = true
	
	local button = self._imageButton
	if not button then return end
	frame.Position = UDim2.fromOffset(button.AbsolutePosition.X + button.AbsoluteSize.X, button.AbsolutePosition.Y)
end

function LuckInfoFrame:Hide()
	local frame = self.frame
	if not frame then return end
	frame.Visible = false
end

function LuckInfoFrame:Destroy()
	self.frame:Destroy()
	for _, connection in self.connections do
		connection:Disconnect()
	end
end

export type LuckInfoFrameObject = typeof(setmetatable({} :: {
	frame: Frame,
	connections: {RBXScriptConnection},
}, LuckInfoFrame))

return LuckInfoFrame
