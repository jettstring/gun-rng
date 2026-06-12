local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local ServiceName = {}
ServiceName.Services = {}
ServiceName.Signals = {}

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

function ServiceName:PublicFoo()

end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function ServiceName:Init(services)
	self.Services = services

end

function ServiceName:Start()

end


return ServiceName