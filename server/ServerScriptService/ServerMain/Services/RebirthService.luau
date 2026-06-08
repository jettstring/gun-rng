local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local GameAssets = ReplicatedStorage.GameAssets
local RebirthAssets = GameAssets.RebirthAssets
local RebirthRewards = require(RebirthAssets.RebirthRewards)

local utils = ReplicatedStorage:WaitForChild("Util")
local RebirthUtil = require(utils.RebirthUtil)


local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	AttemptRebirth = remotesFolder.Rebirth:WaitForChild("AttemptRebirth"),
	RebirthsUpdated = remotesFolder.Rebirth:WaitForChild("RebirthsUpdated"),

	-- RFs
	GetRebirthData = remotesFolder.Rebirth:WaitForChild("GetRebirthData"),
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type RebirthReward = RebirthRewards.RebirthReward

--------------------------------------------------
-- STATE --
--------------------------------------------------
local RebirthService = {}
RebirthService.Services = {}
RebirthService.Signals = {}

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

function RebirthService:Rebirth(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[Rebirth] No profile found for player: " .. player.Name) return end
	
	local current = profile.Rebirths
	local nextRebirth = current + 1
	
	local requiredDogtags = RebirthUtil.GetRequiredDogtags(nextRebirth)
	local currentDogtags = profile.Dogtags or 0
	
	if currentDogtags < requiredDogtags then
		self.Services.NotificationService:Error(player, "Not enough Dogtags to rebirth")
		return
	end
	
	-- Capture pre-rebirth facts the reset is about to destroy, and close out the
	-- enemy-income tally for the life being ended (so it keeps the old rebirth count).
	local moneyForfeited = profile.Money
	local zoneReached = profile.CurrentZone
	local customAnalytics = self.Services.CustomAnalyticsService
	if customAnalytics then
		customAnalytics:FlushEnemyIncome(player.UserId, "rebirth")
	end

	-- deduct values
	self.Services.DataService:IncrementDogtags(player, -requiredDogtags, "Rebirth")
	self.Services.DataService:IncrementMoney(player, -profile.Money, "Rebirth")
	self.Services.ZoneService:ResetPlayerZones(player)
	
	self:GiveRebirth(player, nextRebirth)

	if customAnalytics then
		customAnalytics:Rebirth(player, {
			fromRebirth = current,
			toRebirth = nextRebirth,
			dogtagsSpent = requiredDogtags,
			moneyForfeited = moneyForfeited,
			zoneReached = zoneReached,
		})
	end
end

function RebirthService:GiveRebirth(player: Player, rebirth: number)
	if not rebirth or typeof(rebirth) ~= "number" or rebirth < 0 then
		warn("[GiveRebirth] Invalid rebirth value: " .. tostring(rebirth))
		return
	end
	
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[GiveRebirth] No profile found for player: " .. player.Name) return end
	
	profile.Rebirths = rebirth
	
	-- update client
	self.Services.RollService:SendUpdatedLuck(player)
	self:SendRebirths(player)
end


function RebirthService:SendRebirths(player: Player)
	remotes.RebirthsUpdated:FireClient(player, self:GetPlayerRebirth(player))
end

function RebirthService:GetPlayerRebirth(player: Player): number
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[SendRebirthData] No profile found for player: " .. player.Name) return end
	return profile.Rebirths or 0
end

function RebirthService:OwnsRebirthReward(player: Player, rewardName: string): boolean
	return RebirthUtil.OwnsRebirthReward(self:GetPlayerRebirth(player), rewardName)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function RebirthService:Init(services)
	self.Services = services

end

function RebirthService:Start()
	
	remotes.AttemptRebirth.OnServerEvent:Connect(function(player)
		self:Rebirth(player)
	end)
	
	remotes.GetRebirthData.OnServerInvoke = function(player)
		return self:GetPlayerRebirth(player)
	end
end


return RebirthService