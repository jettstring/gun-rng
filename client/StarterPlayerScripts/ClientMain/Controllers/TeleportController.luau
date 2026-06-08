local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--------------------------------------------------
-- DEPENDENCIES --
--------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player.PlayerGui

-- UI
local Displays = playerGui:WaitForChild("Displays")
local teleportFrame = Displays:WaitForChild("Teleport") :: Frame
local zoneScrollingFrame = teleportFrame:WaitForChild("ZoneScrollingFrame") :: ScrollingFrame
local zoneListLayout = zoneScrollingFrame:WaitForChild("UIListLayout")
local zoneTemplate = zoneScrollingFrame:WaitForChild("ZoneTemplate") :: ImageLabel

local ScreenElements = playerGui:WaitForChild("ScreenElements")
local leftOptions = ScreenElements:WaitForChild("LeftOptions")
local teleportButton = leftOptions:WaitForChild("TeleportButton") :: ImageButton

local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ZoneDefinitions = require(GameAssets.ZoneAssets.ZoneDefinitions)

local utils = ReplicatedStorage:WaitForChild("Util")
local RebirthUtil = require(utils.RebirthUtil)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	MovePlayerToZone = remotesFolder.Zones:WaitForChild("MovePlayerToZone"),

	RebirthsUpdated = remotesFolder.Rebirth:WaitForChild("RebirthsUpdated"),
	GetRebirthData = remotesFolder.Rebirth:WaitForChild("GetRebirthData"),
}

--------------------------------------------------
-- TYPES --
--------------------------------------------------

type ZoneDefinition = ZoneDefinitions.ZoneDefinition
type ZoneEntry = { name: string, order: number, definition: ZoneDefinition }

--------------------------------------------------
-- STATE --
--------------------------------------------------
local TeleportController = {}
TeleportController.Controllers = {}
TeleportController.Signals = {}

local zoneFrames = {} :: { any }

--------------------------------------------------
-- VARIABLES --
--------------------------------------------------

-- Constants
local TELEPORTER_REWARD = "Teleporter"

-- Zones sorted by unlock order, built once from the static definitions.
local sortedZones = {} :: { ZoneEntry }
for zoneName, definition in ZoneDefinitions do
	table.insert(sortedZones, { name = zoneName, order = definition.order, definition = definition })
end
table.sort(sortedZones, function(a, b)
	return a.order < b.order
end)

--------------------------------------------------
-- PRIVATE FUNCTIONS --
--------------------------------------------------

local function updateButtonVisibility(rebirthLevel: number)
	teleportButton.Visible = RebirthUtil.OwnsRebirthReward(rebirthLevel, TELEPORTER_REWARD)
end

local function refreshUnlockFromServer()
	local ok, rebirthLevel = pcall(function()
		return remotes.GetRebirthData:InvokeServer()
	end)

	if not ok or not rebirthLevel then
		warn("[TeleportController] Failed to get rebirth data:", rebirthLevel)
		return
	end

	updateButtonVisibility(rebirthLevel)
end

--------------------------------------------------
-- PUBLIC FUNCTIONS --
--------------------------------------------------

function TeleportController:TeleportToZone(zoneOrder: number)
	local ok, success = pcall(function()
		return remotes.MovePlayerToZone:InvokeServer(zoneOrder)
	end)

	if not ok then
		warn("[TeleportController] MovePlayerToZone failed:", success)
		return
	end

	if success then
		self.Controllers.UIController:CloseFrames()
	end
end

-- Rebuild the zone list (unlocked zones only) and open the menu.
function TeleportController:Open()
	for _, frame in zoneFrames do
		frame:Destroy()
	end
	table.clear(zoneFrames)

	local currentZone = player:GetAttribute("CurrentZone") or 1
	for _, zoneEntry in sortedZones do
		if zoneEntry.order > currentZone then
			continue
		end

		local frame: any = zoneTemplate:Clone()
		frame.Name = zoneEntry.name
		frame.LayoutOrder = zoneEntry.order
		frame.ZoneNumberLabel.Text = zoneEntry.order
		frame.ZoneNameLabel.Text = zoneEntry.definition.label

		-- The player is already standing in their current zone, so that row is shown disabled.
		local isCurrent = zoneEntry.order == currentZone
		local button = frame.TeleportButton
		button.GreenGradient.Enabled = not isCurrent
		button.GreyGradient.Enabled = isCurrent
		button.TextLabel.Text = if isCurrent then "Current" else "Teleport"

		if not isCurrent then
			button.Activated:Connect(function()
				self:TeleportToZone(zoneEntry.order)
			end)
		end

		local playersDisplay = frame.PlayersDisplay
		local avatarTemplate = playersDisplay.AvatarDisplay
		avatarTemplate.Parent = playersDisplay.UIGridLayout

		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer == player or otherPlayer:GetAttribute("CurrentZone") ~= zoneEntry.order then
				continue
			end

			local avatar = avatarTemplate:Clone()
			avatar.Image = ""
			avatar.Parent = playersDisplay

			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(otherPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end)
				if ok then
					avatar.Image = content
				end
			end)
		end

		frame.Parent = zoneScrollingFrame
		table.insert(zoneFrames, frame)
	end

	self.Controllers.UIController:OpenFrame(teleportFrame)
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function TeleportController:Init(controllers)
	self.Controllers = controllers

	-- Tuck the master template under the layout so it is not rendered or counted in the
	-- list flow; clones are parented to the scrolling frame instead (mirrors Index/Rebirth).
	zoneTemplate.Parent = zoneListLayout

	-- Hidden until we confirm the player has unlocked the teleporter reward.
	teleportFrame.Visible = false
	teleportButton.Visible = false
end

function TeleportController:Start()
	player:GetAttributeChangedSignal("Loaded"):Once(refreshUnlockFromServer)
	if player:GetAttribute("Loaded") then
		refreshUnlockFromServer()
	end

	remotes.RebirthsUpdated.OnClientEvent:Connect(updateButtonVisibility)
end


return TeleportController
