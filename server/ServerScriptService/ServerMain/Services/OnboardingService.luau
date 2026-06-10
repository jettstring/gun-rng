local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------

-- Onboarding assets
local OnboardingAssets = ReplicatedStorage.GameAssets.OnboardingAssets
local OnboardingSteps = require(OnboardingAssets.OnboardingSteps)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	StepAdvance = remotesFolder.Onboarding:WaitForChild("StepAdvance"),
	OnboardingComplete = remotesFolder.Onboarding:WaitForChild("OnboardingComplete"),
	
	-- RFs
	GetOnboardingStatus = remotesFolder.Onboarding:WaitForChild("GetOnboardingStatus"),
}

--------------------------------------------------
-- STATE --
--------------------------------------------------
local OnboardingService = {}
OnboardingService.Services = {}
OnboardingService.Signals = {}

OnboardingService.OnboardingPlayers = {} :: {[Player]: boolean}

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type Step = OnboardingSteps.Step

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function LogAnalyticStepEvent(player, step: number)
	if not player then return end
		
	local stepData: Step = OnboardingSteps.Steps[step]
	if not stepData then
		warn("No stepData for LogAnalyticStepEvent for step: ", step)
		return
	end

	AnalyticsService:LogOnboardingFunnelStepEvent(player,
		step + 1, -- first step is player join
		stepData.stepName
	)
end


local function onPlayerRemoved(player)
	if OnboardingService.OnboardingPlayers[player] then
		OnboardingService.OnboardingPlayers[player] = nil
	end
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function OnboardingService:Init(services)
	self.Services = services
	
	Players.PlayerRemoving:Connect(onPlayerRemoved)
end

function OnboardingService:Start()
	
	remotes.StepAdvance.OnServerEvent:Connect(function(player, stepIndex)
		LogAnalyticStepEvent(player, stepIndex)
	end)
	
	remotes.OnboardingComplete.OnServerEvent:Connect(function(player)
		if self.OnboardingPlayers[player] then
			self.OnboardingPlayers[player] = nil
		end
	end)

	remotes.GetOnboardingStatus.OnServerInvoke = function(player)
		local profile = self.Services.DataService:GetProfile(player)
		if not profile then
			warn("No profile for player")
			return nil
		end
		
		if profile.LastSessionTimestamp and profile.LastSessionTimestamp > 0 then
			return true -- Player has been in the game before
		else
			return false
		end
	end
end


return OnboardingService