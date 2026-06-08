local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local ControllerName = {}
ControllerName.Controllers = {}
ControllerName.Signals = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function PrivateFoo()
	
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function ControllerName:PublicFoo()

end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ControllerName:Init(controllers)
	self.Controllers = controllers

end

function ControllerName:Start()

end


return ControllerName