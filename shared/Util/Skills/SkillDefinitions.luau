--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillTree = require(script.Parent.SkillTree)
local SpecialRollDefinitions = require(ReplicatedStorage.GameAssets.RollAssets.SpecialRollDefinitions)
local ItemDefinitions = require(ReplicatedStorage.GameAssets.ItemAssets.ItemDefinitions)
local LuckRolls = require(ReplicatedStorage.GameAssets.RollAssets.LuckRolls)

local tree: SkillTree.NestedSkillDefinitions = {
	["Player Defaults"] = {
		direction = "Top",
		description = "Base player stats used before any upgrades are owned", price = 0,
		owned = true, hidden = true,
		stats = {
			backpackUnlocked = 0,
			magnetRange = 100, 
			walkSpeed = 16,
			gunSlots = 3, 
			enemyCap = 3,
			tagsMultiplier = 0,
			moneyMultiplier = 1,
			offlineMoneyMultiplier = 1,

			-- Rolling related
			luck = 1,
			rollSpeed = 1,
			bonusChance = 0.1,

		},
		unlocks = {
			["Auto Roll"] = {
				direction = "Top",
				description = "Automatically Rolls", price = 1, alwaysShow = true,
				stats = { autoRollUnlocked = 1 },
				unlocks = {
					["Backpack"] = {
						direction = "Bottom",
						description = "Unlock the Backpack so you can manage and equip guns", price = 5,
						imageId = "rbxassetid://133918184513849",
						stats = { backpackUnlocked = 1 },
						unlocks = {
							["Player"] = {
								direction = "Bottom",
								description = "Player Skills", price = 0, subTreeEntrance = true,
								imageId = "rbxassetid://84459837347641",
								stats = {},
								unlocks = {
									["Luck I"] = {
										direction = "BottomLeft",
										subTreeExit = true,
										description = "20% extra luck", price = 500,
										stats = { luck = 0.2 },
										unlocks = {
											["Luck II"] = {
												direction = "TopLeft",
												description = "50% extra luck", price = 1500,
												stats = { luck = 0.3 },
												unlocks = {
													["Luck III"] = {
														direction = "TopLeft",
														description = "100% extra luck", price = 4000,
														stats = { luck = 0.5 },
														unlocks = {
															["Super Luck I"] = {
																direction = "TopLeft",
																description = "200% extra luck", price = 12000,
																stats = { luck = 1 },
																unlocks = {
																	["Super Luck II"] = {
																		direction = "BottomLeft",
																		description = "350% extra luck", price = 35000,
																		stats = { luck = 1.5 },
																		unlocks = {
																			["Super Luck III"] = {
																				direction = "BottomLeft",
																				description = "550% extra luck", price = 100000,
																				stats = { luck = 2 },
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
											["Golden Rolls"] = {
												direction = "Bottom",
												description = "4x Luck on every 10th Roll", price = 25000,
												imageId = "rbxassetid://" .. SpecialRollDefinitions.Gold.displayIcon,
												stats = { 
													goldenRollsNeeded = SpecialRollDefinitions.Gold.rollsNeeded, 
													goldenRollLuckMultiplier = SpecialRollDefinitions.Gold.rollLuckMultiplier 
												},
												unlocks = {
													["Extra Golden Rolls"] = {
														direction = "BottomLeft",
														description = "Golden Rolls on every 9th roll", price = 80000,
														imageId = "rbxassetid://" .. SpecialRollDefinitions.Gold.displayIcon,
														stats = { goldenRollsNeeded = -1 },
														unlocks = {
															["Mega Golden Rolls"] = {
																direction = "Bottom",
																description = "Golden Rolls on every 8th roll", price = 250000,
																imageId = "rbxassetid://" .. SpecialRollDefinitions.Gold.displayIcon,
																stats = { goldenRollsNeeded = -1 },
																unlocks = {
																	["Lucky Golden Rolls"] = {
																		direction = "Bottom",
																		description = "5x Luck on Golden Rolls", price = 800000,
																		imageId = "rbxassetid://" .. SpecialRollDefinitions.Gold.displayIcon,
																		stats = { goldenRollLuckMultiplier = 1 },
																	},
																},
															},
															["Diamond Rolls"] = {
																direction = "TopLeft",
																description = "25x Luck on every 100th roll", price = 1500000,
																imageId = "rbxassetid://" .. SpecialRollDefinitions.Diamond.displayIcon,
																stats = {
																	diamondRollsNeeded = SpecialRollDefinitions.Diamond.rollsNeeded,
																	diamondRollLuckMultiplier = SpecialRollDefinitions.Diamond.rollLuckMultiplier
																},
																unlocks = {
																	["Extra Diamond Rolls"] = {
																		direction = "BottomLeft",
																		description = "Diamond Rolls on every 90th roll", price = 3500000,
																		imageId = "rbxassetid://" .. SpecialRollDefinitions.Diamond.displayIcon,
																		stats = { diamondRollsNeeded = -10 },
																		unlocks = {
																			["Mega Diamond Rolls"] = {
																				direction = "Bottom",
																				description = "Diamond Rolls on every 75th roll", price = 7000000,
																				imageId = "rbxassetid://" .. SpecialRollDefinitions.Diamond.displayIcon,
																				stats = { diamondRollsNeeded = -15 },
																				unlocks = {
																					["Lucky Diamond Rolls"] = {
																						direction = "Bottom",
																						description = "50x Luck on Diamond Rolls", price = 13000000,
																						imageId = "rbxassetid://" .. SpecialRollDefinitions.Diamond.displayIcon,
																						stats = { diamondRollLuckMultiplier = 50 },
																					},
																				},
																			},
																			["Rainbow Rolls"] = {
																				direction = "TopLeft",
																				description = "250x Luck on every 1000th roll", price = 18000000,
																				imageId = "rbxassetid://" .. SpecialRollDefinitions.Rainbow.displayIcon,
																				stats = {
																					rainbowRollsNeeded = SpecialRollDefinitions.Rainbow.rollsNeeded,
																					rainbowRollLuckMultiplier = SpecialRollDefinitions.Rainbow.rollLuckMultiplier
																				},
																				unlocks = {
																					["Extra Rainbow Rolls"] = {
																						direction = "BottomLeft",
																						description = "Rainbow Rolls on every 950th roll", price = 24000000,
																						imageId = "rbxassetid://" .. SpecialRollDefinitions.Rainbow.displayIcon,
																						stats = { rainbowRollsNeeded = -50 },
																						unlocks = {
																							["Mega Rainbow Rolls"] = {
																								direction = "Bottom",
																								description = "Rainbow Rolls on every 900th roll", price = 28000000,
																								imageId = "rbxassetid://" .. SpecialRollDefinitions.Rainbow.displayIcon,
																								stats = { rainbowRollsNeeded = -50 },
																								unlocks = {
																									["Lucky Rainbow Rolls"] = {
																										direction = "Bottom",
																										description = "350x Luck on Rainbow Rolls", price = 32000000,
																										imageId = "rbxassetid://" .. SpecialRollDefinitions.Rainbow.displayIcon,
																										stats = { rainbowRollLuckMultiplier = 100 },
																									},
																								},
																							},
																						},
																					},
																				},
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
										},
									},
									["Roll Speed"] = {
										direction = "BottomRight",
										subTreeExit = true,
										description = "10% faster rolls", price = 2000,
										stats = { rollSpeed = 0.1 },
										unlocks = {
											["Faster Rolls"] = {
												direction = "BottomRight",
												description = "20% faster rolls", price = 8000,
												stats = { rollSpeed = 0.1 },
												unlocks = {
													["Faster Rolls II"] = {
														direction = "BottomRight",
														label = "Faster Rolls", description = "30% faster rolls", price = 32000,
														stats = { rollSpeed = 0.1 },
														unlocks = {
															["Faster Rolls III"] = {
																direction = "Bottom",
																label = "Faster Rolls", description = "40% faster rolls", price = 120000,
																stats = { rollSpeed = 0.1 },
																unlocks = {
																	["Faster Rolls IV"] = {
																		direction = "Bottom",
																		label = "Faster Rolls", description = "50% faster rolls", price = 500000,
																		stats = { rollSpeed = 0.1 },
																		unlocks = {
																			["Faster Rolls V"] = {
																				direction = "Bottom",
																				label = "Faster Rolls", description = "60% faster rolls", price = 2000000,
																				stats = { rollSpeed = 0.1 },
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},

											["Bonus Chance"] = {
												direction = "Bottom",
												description = "Bonus rolls happen 5% more often!", price = 7000,
												imageId = "rbxassetid://95785874481208",
												stats = { bonusChance = 0.05 },
												unlocks = {
													["Bonus Chains"] = {
														direction = "Bottom",
														description = "Bonus rolls happen 10% more often!", price = 70000,
														imageId = "rbxassetid://95785874481208",
														stats = { bonusChance = 0.05 },
														unlocks = {
															["Bonus Frenzy"] = {
																direction = "BottomLeft",
																description = "Bonus rolls happen 15% more often!", price = 700000,
																imageId = "rbxassetid://95785874481208",
																stats = { bonusChance = 0.05 },
															},
														},
													},
												},
											},

											["More Clovers I"] = {
												direction = "TopRight",
												description = "Clover Rolls happen 10% more often!", price = 30000,
												imageId = "rbxassetid://"..LuckRolls[1].displayIcon,
												stats = { cloverChance = 0.1 },
												unlocks = {
													["More Clovers II"] = {
														direction = "TopRight",
														description = "Clover Rolls happen 20% more often!", price = 150000,
														imageId = "rbxassetid://"..LuckRolls[2].displayIcon,
														stats = { cloverChance = 0.1 },
														unlocks = {
															["More Clovers III"] = {
																direction = "BottomRight",
																description = "Clover Rolls happen 30% more often!", price = 700000,
																imageId = "rbxassetid://"..LuckRolls[3].displayIcon,
																stats = { cloverChance = 0.1 },
																unlocks = {
																	["More Clovers IV"] = {
																		direction = "BottomRight",
																		description = "Clover Rolls happen 40% more often!", price = 3000000,
																		imageId = "rbxassetid://"..LuckRolls[4].displayIcon,
																		stats = { cloverChance = 0.1 },
																		unlocks = {
																			["More Clovers V"] = {
																				direction = "Bottom",
																				description = "Clover Rolls happen 50% more often!", price = 12000000,
																				imageId = "rbxassetid://"..LuckRolls[5].displayIcon,
																				stats = { cloverChance = 0.1 },
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
										},
									},
									["Walk Speed 1"] = {
										direction = "TopLeft",
										imageId = "rbxassetid://135735528184524",
										description = "Faster walking!", price = 400,
										stats = { walkSpeed = 5 },
										unlocks = {
											["Walk Speed 2"] = {
												direction = "TopLeft",
												description = "Even faster walking!", price = 1200,
												imageId = "rbxassetid://97466130162979",
												stats = { walkSpeed = 5 },
												unlocks = {
													["Walk Speed 3"] = {
														direction = "TopLeft",
														description = "Much faster walking!", price = 4000,
														imageId = "rbxassetid://98563300023721",
														stats = { walkSpeed = 5 },
														unlocks = {
															["Walk Speed 4"] = {
																direction = "TopLeft",
																description = "Super fast walking!", price = 12000,
																imageId = "rbxassetid://108070761117416",
																stats = { walkSpeed = 5 },
															},
														}
													},
												},
											},
										},
									},
									["Magnet 1"] = {
										direction = "BottomLeft",
										description = "100 range for coin magnet", price = 800,
										imageId = "rbxassetid://76224127454082",
										stats = { magnetRange = 10 },
										unlocks = {
											["Magnet 2"] = {
												direction = "BottomLeft",
												description = "150 range for coin magnet", price = 3000,
												imageId = "rbxassetid://76224127454082",
												stats = { magnetRange = 10 },
												unlocks = {
													["Magnet 3"] = {
														direction = "BottomLeft",
														description = "200 range for coin magnet", price = 12000,
														imageId = "rbxassetid://76224127454082",
														stats = { magnetRange = 10 },
														unlocks = {
															["Magnet 4"] = {
																direction = "BottomLeft",
																description = "250 range for coin magnet", price = 48000,
																imageId = "rbxassetid://76224127454082",
																stats = { magnetRange = 10 },
															},
														},
													},
												},
											},
										},
									},
								}
							}
						},
					},
					["Loot"] = {
						direction = "Top",
						description = "Placeholder description", price = 0, subTreeEntrance = true,
						stats = {},
						unlocks = {
							["Cash Boost 1"] = {
								direction = "Top",
								description = "25% more money!", price = 2000,
								imageId = "rbxassetid://88625177615779",
								stats = { moneyMultiplier = 0.25 },
								unlocks = {
										["Offline Boost 1"] = {
											direction = "TopLeft",
											description = "25% more offline money!", price = 50000,
											imageId = "rbxassetid://88625177615779",
											stats = { offlineMoneyMultiplier = 0.25 },
											unlocks = {
												["Offline Boost 2"] = {
													direction = "TopLeft",
													description = "50% more offline money!", price = 150000,
													imageId = "rbxassetid://88625177615779",
													stats = { offlineMoneyMultiplier = 0.25 },
													unlocks = {
														["Offline Boost 3"] = {
															direction = "TopLeft",
															description = "100% more offline money!", price = 400000,
															imageId = "rbxassetid://88625177615779",
															stats = { offlineMoneyMultiplier = 0.5 },
															unlocks = {
																["Offline Boost 4"] = {
																	direction = "TopLeft",
																	description = "150% more offline money!", price = 1000000,
																	imageId = "rbxassetid://88625177615779",
																	stats = { offlineMoneyMultiplier = 0.5 },
																	unlocks = {
																		["Offline Boost 5"] = {
																			direction = "TopLeft",
																			description = "200% more offline money!", price = 3000000,
																			imageId = "rbxassetid://88625177615779",
																			stats = { offlineMoneyMultiplier = 0.5 },
																	},
																},
															},
														},
													},
												},
											},
										},
									},
									["Cash Boost 2"] = {
										direction = "Top",
										description = "50% more money!", price = 4000,
										imageId = "rbxassetid://88625177615779",
										stats = { moneyMultiplier = 0.25 },
										unlocks = {
											["Cash Boost 3"] = {
												direction = "Top",
												description = "100% more money!", price = 8000,
												imageId = "rbxassetid://88625177615779",
												stats = { moneyMultiplier = 0.5 },
												unlocks = {
													["Cash Boost 4"] = {
														direction = "Top",
														description = "150% more money!", price = 16000,
														imageId = "rbxassetid://88625177615779",
														stats = { moneyMultiplier = 0.5 },
														unlocks = {
															["Cash Boost 5"] = {
																direction = "Top",
																description = "200% more money!", price = 32000,
																imageId = "rbxassetid://88625177615779",
																stats = { moneyMultiplier = 0.5 },
																unlocks = {
																	["Cash Boost 6"] = {
																		direction = "Top",
																		description = "250% more money!", price = 64000,
																		imageId = "rbxassetid://88625177615779",
																		stats = { moneyMultiplier = 0.5 },
																		unlocks = {
																			["Cash Boost 7"] = {
																				direction = "Top",
																				description = "300% more money!", price = 128000,
																				imageId = "rbxassetid://88625177615779",
																				stats = { moneyMultiplier = 0.5 },
																				unlocks = {
																					["Cash Boost 8"] = {
																						direction = "Top",
																						description = "350% more money!", price = 256000,
																						imageId = "rbxassetid://88625177615779",
																						stats = { moneyMultiplier = 0.5 },
																						unlocks = {
																							["Cash Boost 9"] = {
																								direction = "Top",
																								description = "400% more money!", price = 512000,
																								imageId = "rbxassetid://88625177615779",
																								stats = { moneyMultiplier = 0.5 },
																								unlocks = {
																									["Cash Boost 10"] = {
																										direction = "Top",
																										description = "450% more money!", price = 1000000,
																										imageId = "rbxassetid://88625177615779",
																										stats = { moneyMultiplier = 0.5 },
																										unlocks = {
																											["Cash Boost 11"] = {
																												direction = "Top",
																												description = "500% more money!", price = 2000000,
																												imageId = "rbxassetid://88625177615779",
																												stats = { moneyMultiplier = 0.5 },
																												unlocks = {
																													["Cash Boost 12"] = {
																														direction = "Top",
																														description = "550% more money!", price = 4000000,
																														imageId = "rbxassetid://88625177615779",
																														stats = { moneyMultiplier = 0.5 },
																														unlocks = {
																															["Cash Boost 13"] = {
																																direction = "Top",
																																description = "600% more money!", price = 8000000,
																																imageId = "rbxassetid://88625177615779",
																																stats = { moneyMultiplier = 0.5 },
																																unlocks = {
																																	["Cash Boost 14"] = {
																																		direction = "Top",
																																		description = "650% more money!", price = 16000000,
																																		imageId = "rbxassetid://88625177615779",
																																		stats = { moneyMultiplier = 0.5 },
																																		unlocks = {
																																			["Cash Boost 15"] = {
																																				direction = "Top",
																																				description = "700% more money!", price = 32000000,
																																				imageId = "rbxassetid://88625177615779",
																																				stats = { moneyMultiplier = 0.5 },
																																			},
																																		},
																																	},
																																},
																															},
																														},
																													},
																												},
																											},
																										},
																									},
																								},
																							},
																						},
																					},
																				},
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
										},
										},
									},
								},
							["Scraps"] = {
								direction = "BottomLeft",
								description = "Enemies can drop scraps", price = 5000,
								stats = { Scraps = 0.05},
								unlocks = {
									["Parts"] = {
										direction = "BottomLeft",
										description = "Enemies can drop parts", price = 50000,
										stats = { Parts = 0.05 },
										unlocks = {
											["Tech"] = {
												direction = "BottomLeft",
												description = "Enemies can drop tech", price = 500000,
												stats = { Tech = 0.05},
											},
										},
									},
								},
							},
							["Smart Bullets"] = {
								direction = "TopRight",
								description = "Enemies can drop Smart Bullets", price = 5000,
								stats = { Smart = ItemDefinitions["Smart"].dropChance },
								unlocks = {
									["Incendiary Bullets"] = {
										direction = "TopRight",
										description = "Enemies can drop Incendiary Bullets", price = 50000,
										stats = { Incendiary = ItemDefinitions["Incendiary"].dropChance },
										unlocks = {
											["Explosive Bullets"] = {
												direction = "TopRight",
												description = "Enemies can drop Explosive Bullets", price = 500000,
												stats = { Explosive = ItemDefinitions["Explosive"].dropChance },
											},
										},
									},
								},
							},
							["Luck Potions"] = {
								direction = "BottomRight",
								description = "Enemies can drop Luck Potions", price = 5000,
								imageId = "rbxassetid://"..ItemDefinitions["Luck Potion"].displayImage,
								stats = { ["Luck Potion"] = ItemDefinitions["Luck Potion"].dropChance },
								unlocks = {
									["Roll Speed Potion"] = {
										direction = "BottomRight",
										description = "Enemies can drop Roll Speed Potions", price = 80000,
										imageId = "rbxassetid://"..ItemDefinitions["Roll Speed Potion"].displayImage,
										stats = { ["Roll Speed Potion"] = ItemDefinitions["Roll Speed Potion"].dropChance },
										unlocks = {
											["Super Luck Potion"] = {
												direction = "BottomRight",
												description = "Enemies can drop Super Luck Potions", price = 500000,
												imageId = "rbxassetid://"..ItemDefinitions["Super Luck Potion"].displayImage,
												stats = { ["Super Luck Potion"] = ItemDefinitions["Super Luck Potion"].dropChance },
											},
										},
									},
									["Money Potion"] = {
										direction = "Bottom",
										description = "Enemies can drop Money Potions", price = 30000,
										imageId = "rbxassetid://"..ItemDefinitions["Money Potion"].displayImage,
										stats = { ["Money Potion"] = ItemDefinitions["Money Potion"].dropChance },
									},
								},
							},
							["2 Enemies"] = {
								direction = "TopRight",
								subTreeExit = true,
								label = "+1 Enemies",
								description = "1 more enemy", price = 9000,
								imageId = "rbxassetid://108440332916446",
								stats = { enemyCap = 1 },
								unlocks = {
									["Big Enemies"] = {
										direction = "BottomRight",
										description = "10% Chance of spawning big enemies", price = 30000,
										stats = { bigEnemyChance = 0.01 },
										unlocks = {
											["Shiny Enemies"] = {
												direction = "BottomRight",
												description = "10% Chance of spawning shiny enemies", price = 400000,
												stats = { shinyEnemyChance = 0.01 },
												unlocks = {
													["Inverted Enemies"] = {
														direction = "TopRight",
														description = "10% Chance of spawning inverted enemies", price = 10000000,
														stats = { invertedEnemyChance = 0.01 },
													},

													["More Big Enemies"] = {
														direction = "BottomRight",
														description = "20% Chance of spawning big enemies", price = 3000000,
														stats = { bigEnemyChance = 0.05 },
														unlocks = {
															["More Shiny Enemies"] = {
																direction = "BottomRight",
																description = "20% Chance of spawning Shiny enemies", price = 12000000,
																stats = { shinyEnemyChance = 0.02 },
																unlocks = {
																	["More Inverted Enemies"] = {
																		direction = "Top",
																		description = "20% Chance of spawning Inverted enemies", price = 70000000,
																		stats = { invertedEnemyChance = 0.01 },
																	},
																},
															},
														},
													},
												},
											},
										},
									},
									["3 Enemies"] = {
										direction = "TopRight",
										label = "+2 Enemies",
										description = "2 more enemies", price = 40000,
										imageId = "rbxassetid://137879301891582",
										stats = { enemyCap = 1 },
										unlocks = {
											["Tags I"] = {
												direction = "Top",
												description = "Unlock Tag drops (used to rebirth)", price = 50000,
												stats = { tagsMultiplier = 1 },
												unlocks = {
													["Tags II"] = {
														direction = "Top",
														description = "+20% tags", price = 150000,
														stats = { tagsMultiplier = 0.2 },
														unlocks = {
															["Tags III"] = {
																direction = "Top",
																description = "+40% tags", price = 500000,
																stats = { tagsMultiplier = 0.2 },
																unlocks = {
																	["Tags IV"] = {
																		direction = "TopLeft",
																		description = "+60% tags", price = 1500000,
																		stats = { tagsMultiplier = 0.2 },
																		unlocks = {
																			["Tags V"] = {
																				direction = "Top",
																				description = "+80% tags", price = 5000000,
																				stats = { tagsMultiplier = 0.2 },
																				unlocks = {
																					["Tags VI"] = {
																						direction = "Top",
																						description = "+100% tags", price = 15000000,
																						stats = { tagsMultiplier = 0.2 },
																					},
																				},
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
											["4 Enemies"] = {
												direction = "TopRight",
												label = "+3 Enemies",
												description = "3 more enemies", price = 180000,
												imageId = "rbxassetid://137879301891582",
												stats = { enemyCap = 1 },
												unlocks = {
													["5 Enemies"] = {
														direction = "TopRight",
														label = "+4 Enemies",
														description = "4 more enemies", price = 750000,
														imageId = "rbxassetid://137879301891582",
														stats = { enemyCap = 1 },
														unlocks = {
															["6 Enemies"] = {
																direction = "TopRight",
																label = "+5 Enemies",
																description = "5 more enemies", price = 3000000,
																imageId = "rbxassetid://137879301891582",
																stats = { enemyCap = 1 },
																unlocks = {
																	["7 Enemies"] = {
																		direction = "TopRight",
																		label = "+6 Enemies",
																		description = "6 more enemies", price = 12000000,
																		imageId = "rbxassetid://137879301891582",
																		stats = { enemyCap = 1 },
																		unlocks = {
																			["8 Enemies"] = {
																				direction = "TopRight",
																				label = "+7 Enemies",
																				description = "7 more enemies", price = 50000000,
																				imageId = "rbxassetid://137879301891582",
																				stats = { enemyCap = 1 },
																			},
																		},
																	},
																},
															},

															["Enemy Rush I"] = {
																direction = "Top",
																description = "20% faster enemy spawns", price = 1500000,
																stats = { enemySpawnSpeed = 0.04 },
																unlocks = {
																	["Enemy Rush II"] = {
																		direction = "Top",
																		description = "40% faster enemy spawns", price = 7000000,
																		stats = { enemySpawnSpeed = 0.04 },
																		unlocks = {
																			["Enemy Rush III"] = {
																				direction = "Top",
																				description = "65% faster enemy spawns", price = 30000000,
																				stats = { enemySpawnSpeed = 0.05 },
																			},
																		},
																	},
																},
															},
														},
													},
												},
											},
										},
									},
								},
							},
						},
					},
					["2 Gun Slots"] = {
						direction = "TopLeft",
						description = "Increase equipped gun slots to 2", price = 6000,
						stats = { gunSlots = 1 },
						unlocks = {
							["3 Gun Slots"] = {
								direction = "BottomLeft",
								description = "Increase equipped gun slots to 3", price = 25000,
								stats = { gunSlots = 1 },
								unlocks = {
									["Big Guns"] = {
										direction = "TopLeft",
										description = "Chance to roll Big Guns", price = 80000,
										stats = { Big = 1 },
										unlocks = {
											["Shiny Guns"] = {
												direction = "Top",
												description = "Chance to roll Shiny Guns", price = 400000,
												stats = { Shiny = 1 },
												unlocks = {
													["Inverted Guns"] = {
														direction = "Top",
														description = "Chance to roll Inverted Guns", price = 2000000,
														stats = { Inverted = 1 },
													},
												},
											},
											["4 Gun Slots"] = {
												direction = "TopLeft",
												description = "Increase equipped gun slots to 4", price = 120000,
												stats = { gunSlots = 1 },
												unlocks = {
													["5 Gun Slots"] = {
														direction = "BottomLeft",
														description = "Increase equipped gun slots to 5", price = 600000,
														stats = { gunSlots = 1 },
														unlocks = {
															["6 Gun Slots"] = {
																direction = "BottomLeft",
																description = "Increase equipped gun slots to 6", price = 3000000,
																stats = { gunSlots = 1 },
															},
														},
													},
												},
											},
										},
									},

								},
							},
						},
					},
				},
			},
		},
	},
}

local SkillDefinitions = {
	tree = tree,
}

return SkillDefinitions
