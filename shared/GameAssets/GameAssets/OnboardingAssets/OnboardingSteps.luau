export type Step = {
	stepName: string,
	stepDescriptor: string,
}

local OnboardingSteps = {
	
	Steps = {
		[1] = {
			stepName = "first_roll",
			stepDescriptor = [[Roll your first Gun!]],
		},
		
		[2] = {
			stepName = "kill_first_enemy",
			stepDescriptor = [[Guns shoot automatically!]],
		},
		
		[3] = {
			stepName = "second_roll",
			stepDescriptor = [[Roll another gun!]],
		},
		
		[4] = {
			stepName = "third_roll",
			stepDescriptor = [[Roll one more time!]],
		},
		
		[5] = {
			stepName = "open_backpack",
			stepDescriptor = [[Open Backpack!]],
		},
		
		[6] = {
			stepName = "equip_gun",
			stepDescriptor = [[Equip the gun!]],
		},
		
		[7] = {
			stepName = "close_backpack",
			stepDescriptor = [[Close the Backpack!]],
		},
		
		[8] = {
			stepName = "open_upgrades",
			stepDescriptor = [[Open Upgrades!]],
		},
		
		[9] = {
			stepName = "unlock_auto_roll",
			stepDescriptor = [[Unlock Auto Roll]],
		},
		
		[10] = {
			stepName = "close_upgrades",
			stepDescriptor = [[Press close]],
		},
		
		[11] = {
			stepName = "unlock_zone_2",
			stepDescriptor = [[Unlock <font color="rgb(255, 170, 0)">Zone 2!</font>]],
		},
	},
	
	EndMessage = [[Great Job! You completed the tutorial!]],
}


return OnboardingSteps
