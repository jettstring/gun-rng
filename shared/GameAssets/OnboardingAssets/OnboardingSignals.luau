local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)
local OnboardingSteps = require(ReplicatedStorage.Modules.Onboarding.OnboardingSteps)


local OnboardingSignals = {
	StepAdvanced = Signal.new(),          
	OnboardingComplete = Signal.new(),   

	-- read in signals  ...
}

for _, step in OnboardingSteps.Steps do
	local signalName = step.eventSignal
	
	if signalName and not OnboardingSignals[signalName] then
		OnboardingSignals[signalName] = Signal.new()
	end
end

for name, signal in OnboardingSignals do
	print("TutorialSignal created:", name)
end

return OnboardingSignals
