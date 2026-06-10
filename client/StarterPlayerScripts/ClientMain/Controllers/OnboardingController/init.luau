local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local Signal = require(ReplicatedStorage.Packages.Signal)

--------------------------------------------------
-- DEPENDENCIES -- 
--------------------------------------------------
local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local OnboardingGui = playerGui:WaitForChild("OnboardingGui")
local bannerFrame = OnboardingGui:WaitForChild("BannerFrame")

-- Onboarding assets
local OnboardingAssets = ReplicatedStorage.GameAssets.OnboardingAssets
local OnboardingSteps = require(OnboardingAssets.OnboardingSteps)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	OnboardingComplete = remotesFolder.Onboarding:WaitForChild("OnboardingComplete"),
	StepAdvance = remotesFolder.Onboarding:WaitForChild("StepAdvance"),
	
	-- RFs
	GetOnboardingStatus = remotesFolder.Onboarding:WaitForChild("GetOnboardingStatus"),
}

--------------------------------------------------
-- TYPES -- 
--------------------------------------------------


--------------------------------------------------
-- STATE --
--------------------------------------------------
local OnboardingController = {}
OnboardingController.Controllers = {}
OnboardingController.Signals = {
	StepAdvanced = Signal.new(),          
	OnboardingComplete = Signal.new(),   
}

OnboardingController.StepEventFunctions = {}
OnboardingController.OnboardingComplete = false
OnboardingController.CurrentStep = 1

local BeamTrove = Trove.new()
local HighlightStrokeTrove = Trove.new()

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------


local function createHintBanner(textString: string)
	local textLabel = bannerFrame:WaitForChild("TextLabel")
	bannerFrame.Visible = textString
	textLabel.Text = textString
end

local function _setup()
	local success, completedOnboarding = pcall(function()
		return remotes.GetOnboardingStatus:InvokeServer()
	end)
	if not success then return end
	if completedOnboarding then
		OnboardingController.OnboardingComplete = true
		return
	end
	
	
	-- get first step
	local currentStepIndex = OnboardingController.CurrentStep
	local step: Step = OnboardingSteps.Steps[currentStepIndex]
	if step then
		if OnboardingController.StepEventFunctions[step.stepName] then
			OnboardingController.StepEventFunctions[step.stepName]()
		end

		-- If the synchronous signal chain already advanced past this step, bail
		if OnboardingController.CurrentStep ~= currentStepIndex or OnboardingController.OnboardingComplete then return end
		createHintBanner(step.stepDescriptor)
	end
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function OnboardingController:OnGameEvent(stepName: string)
	-- Read current step
	local currentStepIndex = OnboardingController.CurrentStep
	local currentStep = OnboardingSteps.Steps[currentStepIndex]
	if not currentStep then warn("No current step") return end 

	if currentStep.stepName == stepName then
		self:AdvanceStep(player)
	end
end

function OnboardingController:AdvanceStep(player: Player)
	local nextStepIndex = OnboardingController.CurrentStep + 1
	local nextStep: Step = OnboardingSteps.Steps[nextStepIndex]

	OnboardingController:ShowArrow(player, nil)

	if nextStep then
		self.CurrentStep = nextStepIndex
		if OnboardingController.StepEventFunctions[nextStep.stepName] then
			OnboardingController.StepEventFunctions[nextStep.stepName]()
		end
		
		-- If the synchronous signal chain already advanced past this step, bail
		if self.CurrentStep ~= nextStepIndex or OnboardingController.OnboardingComplete then return end
		createHintBanner(nextStep.stepDescriptor)
		remotes.StepAdvance:FireServer(nextStepIndex)
		
	else
		task.spawn(function()
			createHintBanner(OnboardingSteps.EndMessage)
			task.wait(2)
			createHintBanner(nil)
		end)
		remotes.OnboardingComplete:FireServer()
	
	end
end

function OnboardingController:ShowArrow(part: BasePart)
	print("[OnboardingController] Got beam for ", part)

	BeamTrove:Clean()
	if not part then return end


	local character = player.Character 
	if not character then return end
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	local beam = script:WaitForChild("ArrowBeam"):Clone()
	local light = script:WaitForChild("PointLight"):Clone()

	BeamTrove:Add(beam)
	BeamTrove:Add(light)

	local Attachment0 = Instance.new("Attachment")
	local Attachment1 = Instance.new("Attachment")
	BeamTrove:Add(Attachment1)
	BeamTrove:Add(Attachment0)

	Attachment0.Parent = humanoidRootPart
	Attachment1.Parent = part
	beam.Parent = humanoidRootPart
	beam.Attachment0 = Attachment0
	beam.Attachment1 = Attachment1
	beam.Enabled = true

	light.Parent = Attachment1
end

function OnboardingController:ShowHighlightStroke(guiObject: GuiObject, displayType: ("Flash" | "Solid"))
	print("[OnboardingController] Got GuiObject for ", guiObject)

	HighlightStrokeTrove:Clean()
	if not guiObject then return end

	local highlightStroke = script:WaitForChild("HighlightStroke"):Clone()
	highlightStroke.Parent = guiObject


	if displayType == "Flash" then
		local flashTween = TweenService:Create(highlightStroke, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true), {
			Transparency = 0.5
		})
		flashTween:Play()
		HighlightStrokeTrove:Add(function()
			highlightStroke:Destroy()
		end)
	elseif displayType == "Solid" then
		local fadeTween = TweenService:Create(highlightStroke, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false), {
			Transparency = 0.65
		})
		fadeTween:Play()

		HighlightStrokeTrove:Add(function()
			local fadeOutTween = TweenService:Create(highlightStroke, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false), {
				Transparency = 1
			})
			fadeOutTween:Play()
			task.wait(0.35)
			highlightStroke:Destroy()
		end)
	end

end


--------------------------------------------------
-- MAIN --
--------------------------------------------------

function OnboardingController:Init(controllers)
	self.Controllers = controllers

end 

function OnboardingController:Start()
	player:GetAttributeChangedSignal("Loaded"):Once(function()
		_setup()
	end)
	if player:GetAttribute("Loaded") then _setup() end
	
	remotes.OnboardingComplete.OnClientEvent:Connect(function()
		self:AdvanceStep(player)
	end)
	

end


return OnboardingController