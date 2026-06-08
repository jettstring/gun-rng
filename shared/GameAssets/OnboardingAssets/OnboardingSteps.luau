local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineDefinitions = require(ReplicatedStorage.GameAssets.BaseAssets.MachineDefinitions)


export type Step = {
	StepName: string,
	stepDescriptor: string,
	SavedStep: boolean
}

local OnboardingSteps = {
	
	Steps = {
		[1] = {
			StepName = "unlocked_first_dropper",
			stepDescriptor = [[Buy the <font color="rgb(0, 166, 255)"> Free Dropper!</font>]],
			SavedStep = true,
		},
		
		[2] = {
			StepName = "pressed_dropper_button",
			stepDescriptor = [[Tap the <font color="rgb(255, 37, 52)">button!</font>]],
		},
		
		[3] = {
			StepName = "reached_generating_xp_goal",
			stepDescriptor = [[Fill the explosive to <font color="rgb(0, 234, 255)">100 XP!</font>]],
		},
		
		[4] = {
			StepName = "collect_explosive",
			stepDescriptor = [[Collect your explosive!]],
		},
		
		[5] = {
			StepName = "added_explosive",
			stepDescriptor = [[Add the explosive to your nuke by tapping!]],
		},
		
		[6] = {
			StepName = "launched_nuke_1",
			stepDescriptor = [[Launch your Nuke!]],
		},
		
		[7] = {
			StepName = "wait_for_nuke",
			stepDescriptor = [[Press <font color="rgb(255, 170, 0)">Control button</font> to Aim the Nuke!]],
		},
		
		[8] = {
			StepName = "upgrade_dropper_level",
			stepDescriptor = [[<font color="rgb(255, 170, 0)">Level Up</font> your dropper!]],
		},
		
		[9] = {
			StepName = "reached_money_goal",
			stepDescriptor = string.format([[Launch Again to Get <font color="rgb(69, 255, 12)">$%d!</font>]], MachineDefinitions["Auto Dropper"].Price),
		},
		
		[10] = {
			StepName = "unlocked_second_dropper",
			stepDescriptor = [[Unlock the <font color="rgb(255, 170, 0)">Auto Dropper</font>]],
		},
	},
	
	EndMessage = [[Great Job! Try to Nuke the Entire City!]],
}


return OnboardingSteps
