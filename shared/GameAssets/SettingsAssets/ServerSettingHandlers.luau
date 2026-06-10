local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

export type SettingHandler = (player: Player, value: any) -> boolean

local ServerSettingHandlers: {[string]: SettingHandler} = {

} 

return ServerSettingHandlers
