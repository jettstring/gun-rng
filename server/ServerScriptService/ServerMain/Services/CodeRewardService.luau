local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ConfigService = game:GetService("ConfigService")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	RedeemCode = remotesFolder.CodeRewards:WaitForChild("RedeemCode"),
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------

type RewardType = "Money" | "Dogtags" | "Crate"
type Reward = {rewardType: RewardType, rewardData: {any}}


--------------------------------------------------
-- STATE --
--------------------------------------------------
local CodeRewardService = {}
CodeRewardService.Services = {}
CodeRewardService.Signals = {}

CodeRewardService.CodesData = {} :: {[string]: Reward}

local debounces = {}

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------



local function _StartConfig()
	local success, config = pcall(function()
		return ConfigService:GetConfigAsync()
	end)

	if not success then
		warn("[CodeRewardService] Failed to get codes config: ", config)
	else
		CodeRewardService.CodesData = config:GetValue("CODE_REWARDS") or {}
		
		-- Listen for config updates
		config.UpdateAvailable:Connect(function()
			config:Refresh()
			CodeRewardService.CodesData = config:GetValue("CODE_REWARDS") or {}
		end)
	end 
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function CodeRewardService:ClaimCode(player: Player, code: string)
	if debounces[player] and debounces[player] > os.time() - 10 then return end
	debounces[player] = os.time()

	-- Valid Code Check
	local codeData = CodeRewardService.CodesData[code]
	if not codeData then
		self.Services.NotificationService:Error(player, string.format("\"%s\" is Invalid!", code))
		return
	end
	
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then warn("[ClaimCode] No profile found for player:", player.Name) return end
	
	-- Already Redeemed Check
	if profile.RedeemedCodes[code] then
		self.Services.NotificationService:Error(player, string.format("\"%s\" already redeemed!", code))
		return
	end
	
	
	-- Reward Player
	profile.RedeemedCodes[code] = true
	self:GiveRewards(player, codeData)
	self.Services.NotificationService:Notify(player, "Code redeemed!", Color3.fromRGB(26, 255, 0), game.SoundService.UI.Success)
end

function CodeRewardService:GiveRewards(player: Player, codeData: {Reward})
	for _, reward in codeData do
		if reward.rewardType == "Money" then
			local amount = reward.rewardData.amount or 0
			self.Services.DataService:IncrementMoney(player, amount)
			self.Services.NotificationService:Notify(player, "Money added!")
		elseif reward.rewardType == "Crate" then
			self.Services.CrateService:OpenCrate(player, reward.rewardData.name, 1)
			self.Services.NotificationService:Notify(player, "Crate opened!")
		elseif reward.rewardType == "Dogtags" then
			
		end
	end
end


function CodeRewardService:ValidCode(code: string): boolean
	return CodeRewardService.CodesData[code] ~= nil
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function CodeRewardService:Init(services)
	self.Services = services
	
end

function CodeRewardService:Start()
	_StartConfig()
	
	remotes.RedeemCode.OnServerEvent:Connect(function(player, code)
		CodeRewardService:ClaimCode(player, code)
	end)
end


return CodeRewardService