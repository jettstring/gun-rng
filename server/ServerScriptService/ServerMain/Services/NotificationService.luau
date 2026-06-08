local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	Notify = remotesFolder.Notification:WaitForChild("Notify"),
	CreateBanner = remotesFolder.Notification:WaitForChild("CreateBanner"),
}

--------------------------------------------------
-- STATE --
--------------------------------------------------
local NotificationService = {}
NotificationService.Services = {}
NotificationService.Signals = {}

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function NotificationService:Notify(player, text, color: Color3, sound: Sound?, icon: string?)
	remotes.Notify:FireClient(player, text, color, sound, icon)
end

function NotificationService:Error(player, text, sound: Sound?, icon: string?)
	remotes.Notify:FireClient(player, text, Color3.fromRGB(255, 41, 45), sound, icon)
end

function NotificationService:NotifyPlayers(players: {Player}, text, color: Color3, sound: Sound?, icon: string?)
	for _, player in players do
		if player then
			NotificationService:Notify(player, text, color, sound, icon)
		end
	end
end

function NotificationService:NotifyAll(text, color: Color3, sound: Sound?, icon: string?)
	for _, player in Players:GetPlayers() do
		if player then
			NotificationService:Notify(player, text, color, sound, icon)
		end
	end
end


function NotificationService:CreateBanner(player, show: boolean, ID: string, text, color: Color3, sound: Sound)
	remotes.CreateBanner:FireClient(player, show, ID, text, color, sound)
end


--------------------------------------------------
-- MAIN --
--------------------------------------------------

function NotificationService:Init(services)
	self.Services = services
end

function NotificationService:Start()
end


return NotificationService