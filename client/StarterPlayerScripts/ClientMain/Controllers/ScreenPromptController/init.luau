local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local TopbarPlus = require(ReplicatedStorage.Packages.Icon)
local Spr = require(ReplicatedStorage.Packages.Spr)
local Signal = require(ReplicatedStorage.Packages.Signal)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local PlayerGui = player.PlayerGui


local PromptEffects = script:WaitForChild("PromptEffects")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local ScreenPromptController = {}
ScreenPromptController.Controllers = {}
ScreenPromptController.Signals = {}

local CurrentPromptEffect = nil

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------


--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ScreenPromptController:CreatePromptEffect(effectType: ("Product" | "Moderate"))
	self:Cleanup()
	local effectModule = require(PromptEffects:FindFirstChild(effectType))
	if effectModule then
		local effect = effectModule.new()
		if effect then
			CurrentPromptEffect = effect
			effect:Start()
		end
	end
end


function ScreenPromptController:Cleanup()
	if CurrentPromptEffect then
		CurrentPromptEffect:Destroy()
		CurrentPromptEffect = nil
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ScreenPromptController:Init(controllers)
	self.Controllers = controllers

end

function ScreenPromptController:Start()
	MarketplaceService.PromptProductPurchaseFinished:Connect(function()
		self:Cleanup()
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
		self:Cleanup()
	end)
end


return ScreenPromptController