local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local FlyingItem = require(ReplicatedStorage.Packages.FlyingItem)
local DroppedCurrencyItem = require(ReplicatedStorage.Packages.DroppedCurrencyItem)
local SoundPool = require(ReplicatedStorage.Packages.SoundPool)
local Abbreviate = require(ReplicatedStorage.Packages.Abbreviate)

local CurrencyAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("CurrencyAssets")
local currencyRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Currency")
local clientMoneyEffectsRemote = currencyRemotes:WaitForChild("ClientMoneyEffects") :: RemoteEvent
local spawnCurrencyDropsRemote = currencyRemotes:WaitForChild("SpawnCurrencyDrops") :: RemoteEvent
local collectCurrencyDropRemote = currencyRemotes:WaitForChild("CollectCurrencyDrop") :: RemoteEvent
local soundParent = workspace.CurrentCamera or workspace

local LocalPlayer: Player = Players.LocalPlayer
local MAGNET_RANGE_ATTRIBUTE = "magnetRange"
local character: Model = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local PrimaryPart = character.PrimaryPart or character:WaitForChild("HumanoidRootPart", 5)
local connections: { RBXScriptConnection } = {}

local moneyCollectSoundPool = SoundPool.new(CurrencyAssets:WaitForChild("MoneyCollectSound") :: Sound, soundParent, 4, 2)
local greencoinPool = SoundPool.new(CurrencyAssets:WaitForChild("greencoin") :: Sound, soundParent, 12, 4)
local bluecoinPool = SoundPool.new(CurrencyAssets:WaitForChild("bluecoin") :: Sound, soundParent, 10, 3)
local purplecoinPool = SoundPool.new(CurrencyAssets:WaitForChild("purplecoin") :: Sound, soundParent, 8, 2)
local dogtagitemPool = SoundPool.new(CurrencyAssets:WaitForChild("dogtagitem") :: Sound, soundParent, 8, 2)
local soundPools = {
	moneyCollectSoundPool,
	greencoinPool,
	bluecoinPool,
	purplecoinPool,
	dogtagitemPool,
}

local function getCurrentPrimaryPart(): BasePart?
	if PrimaryPart and PrimaryPart.Parent and PrimaryPart:IsA("BasePart") then
		return PrimaryPart
	end

	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		PrimaryPart = rootPart
		return rootPart
	end

	return nil
end

local flyingItems: {FlyingItem.FlyingItem} = {}
local function addFlyingMoney(
	itemName: string,
	groupId: string,
	count: number,
	amount: number,
	color: Color3?,
	baseDelay: number,
	totalLifetimeIncrement: number,
	isAutoSell: boolean?
)
	local targetPart = getCurrentPrimaryPart()
	if not targetPart or count <= 0 then
		return
	end

	local perpVec: { Vector3 } = {}
	local angleStep = (2 * math.pi) / count
	for i = 0, count - 1 do
		local angle = i * angleStep
		perpVec[i + 1] = Vector3.zAxis * math.cos(angle) - Vector3.yAxis * math.sin(angle)
	end

	for i = 1, count do
		local directionMultVertical = math.random(-10, 10)
		if directionMultVertical < 0 then
			directionMultVertical = -5
		else
			directionMultVertical = 5
		end

		local spawnDelay = baseDelay + (0.1 * (i - 1))
		local totalLifetime = 0.75 + totalLifetimeIncrement  + (0.1 * (i - 1))
		if isAutoSell ~= nil and isAutoSell == true then
			spawnDelay = 0
			--totalLifetime = 0.01
		end
		local flyingItem = FlyingItem.new(
			itemName,
			amount,
			groupId,
			color or Color3.fromRGB(7, 255, 9),
			workspace.CurrentCamera.CFrame.Position + workspace.CurrentCamera.CFrame.UpVector * directionMultVertical + workspace.CurrentCamera.CFrame.RightVector * directionMultVertical + workspace.CurrentCamera.CFrame.LookVector * 2,
			targetPart,
			perpVec[i],
			spawnDelay,
			totalLifetime
		)
		table.insert(flyingItems, flyingItem)
	end
end

--------------------------------------------------
-- CURRENCY ADDED POPUP --
-- Accumulating "+amount" readout (StarterGui.Popups.CurrencyAdded) that pops in
-- when a currency burst starts, counts up to the authoritative total, then fades
-- after a short idle gap. Money is credited from the authoritative server
-- `increment` (and dropped-Money amount); dogtags from dropped-Dogtag amount.
-- Per-coin `amount` is a sound-tier hint, not a real value, so it is never summed.
--------------------------------------------------
local HOLD_DURATION = 1.25 -- seconds without new currency before the popup fades out
local FADE_DURATION = 0.3
local COUNT_UP_SPEED = 6 -- higher = the displayed number catches up to the total faster
local POP_SCALE = 1.18
local POP_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)

type CurrencyRow = {
	frame: GuiObject,
	label: TextLabel,
	scale: UIScale,
	stroke: UIStroke?,
	strokeTransparency: number,
	icon: ImageLabel?,
	prefix: string,
	target: number,
	shown: number,
}

local function buildRow(frame: Instance?, prefix: string): CurrencyRow?
	if not frame or not frame:IsA("GuiObject") then
		return nil
	end

	local label = frame:FindFirstChild("Amount")
	if not label or not label:IsA("TextLabel") then
		return nil
	end

	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end

	local stroke = label:FindFirstChildOfClass("UIStroke")
	local icon = frame:FindFirstChild("Icon")

	return {
		frame = frame,
		label = label,
		scale = scale,
		stroke = stroke,
		strokeTransparency = if stroke then stroke.Transparency else 0,
		icon = if icon and icon:IsA("ImageLabel") then icon else nil,
		prefix = prefix,
		target = 0,
		shown = 0,
	}
end

local popupFrame: GuiObject? = nil
local moneyRow: CurrencyRow? = nil
local dogtagRow: CurrencyRow? = nil
local popupState = "hidden" -- "hidden" | "active" | "fading"
local lastActivityClock = 0
local fadeAlpha = 0

do
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local popups = playerGui:WaitForChild("Currency", 5)
	local currencyAdded = if popups then popups:WaitForChild("CurrencyAdded", 5) else nil
	if currencyAdded and currencyAdded:IsA("GuiObject") then
		popupFrame = currencyAdded
		moneyRow = buildRow(currencyAdded:FindFirstChild("MoneyDisplay"), "+$")
		dogtagRow = buildRow(currencyAdded:FindFirstChild("DogtagDisplay"), "+")
		-- Money sits above dogtags; both rows start hidden (the GUI persists across respawns).
		if moneyRow then
			moneyRow.frame.LayoutOrder = 1
			moneyRow.frame.Visible = false
		end
		if dogtagRow then
			dogtagRow.frame.LayoutOrder = 2
			dogtagRow.frame.Visible = false
		end
		-- The frame tracks the character on screen (see updatePopupPosition), so it
		-- anchors at its own centre rather than the static bottom-left design anchor.
		currencyAdded.AnchorPoint = Vector2.new(0, 0)
		currencyAdded.Visible = false
	else
		warn("[ClientMoneyEffects] CurrencyAdded popup not found; the +currency counter is disabled.")
	end
end

-- Projects the character's HumanoidRootPart (the point money flies to) into screen
-- space and parks the popup there. Popups (the ScreenGui) keeps the topbar inset, so
-- the viewport point is shifted down by GetGuiInset() to land in that GUI's space.
local function updatePopupPosition(targetPart: BasePart?)
	if not popupFrame or not targetPart then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewportPoint = camera:WorldToViewportPoint(targetPart.Position)
	if viewportPoint.Z <= 0 then
		return -- behind the camera; keep the last on-screen position
	end

	local inset = GuiService:GetGuiInset()
	popupFrame.Position = UDim2.fromOffset(viewportPoint.X - inset.X, viewportPoint.Y - inset.Y)
end

local function restoreRowVisual(row: CurrencyRow)
	row.label.TextTransparency = 0
	if row.stroke then
		row.stroke.Transparency = row.strokeTransparency
	end
	if row.icon then
		row.icon.ImageTransparency = 0
	end
end

local function updateRowText(row: CurrencyRow)
	row.label.Text = row.prefix .. Abbreviate.AbbreviateNumber(math.floor(row.shown), 2)
end

local function popRow(row: CurrencyRow)
	row.scale.Scale = 1
	TweenService:Create(row.scale, POP_TWEEN_INFO, { Scale = POP_SCALE }):Play()
end

local function creditCurrency(row: CurrencyRow?, amount: number)
	if not row or not popupFrame or amount <= 0 then
		return
	end

	-- A credit during the fade-out cancels it and keeps accumulating.
	if popupState == "fading" then
		if moneyRow then
			restoreRowVisual(moneyRow)
		end
		if dogtagRow then
			restoreRowVisual(dogtagRow)
		end
	end

	popupState = "active"
	lastActivityClock = os.clock()
	popupFrame.Visible = true
	updatePopupPosition(getCurrentPrimaryPart()) -- place it correctly on the first visible frame

	if not row.frame.Visible then
		row.frame.Visible = true
		row.shown = 0
		restoreRowVisual(row)
		updateRowText(row)
	end

	row.target += amount
	popRow(row)
end

local function creditMoney(amount: number)
	creditCurrency(moneyRow, amount)
end

local function creditDogtags(amount: number)
	creditCurrency(dogtagRow, amount)
end

local function tickRow(row: CurrencyRow, dt: number)
	if not row.frame.Visible or row.shown == row.target then
		return
	end

	local diff = row.target - row.shown
	if math.abs(diff) < 1 then
		row.shown = row.target
	else
		row.shown += diff * math.clamp(dt * COUNT_UP_SPEED, 0, 1)
	end
	updateRowText(row)
end

local function fadeRow(row: CurrencyRow, alpha: number)
	if not row.frame.Visible then
		return
	end
	row.label.TextTransparency = alpha
	if row.stroke then
		row.stroke.Transparency = row.strokeTransparency + (1 - row.strokeTransparency) * alpha
	end
	if row.icon then
		row.icon.ImageTransparency = alpha
	end
end

local function resetRow(row: CurrencyRow)
	row.frame.Visible = false
	row.target = 0
	row.shown = 0
	restoreRowVisual(row)
end

local function resetPopup()
	if popupFrame then
		popupFrame.Visible = false
	end
	if moneyRow then
		resetRow(moneyRow)
	end
	if dogtagRow then
		resetRow(dogtagRow)
	end
	popupState = "hidden"
end

local function updateCurrencyPopup(dt: number, targetPart: BasePart?)
	if popupState == "hidden" then
		return
	end

	updatePopupPosition(targetPart)

	if popupState == "active" then
		if moneyRow then
			tickRow(moneyRow, dt)
		end
		if dogtagRow then
			tickRow(dogtagRow, dt)
		end
		if os.clock() - lastActivityClock > HOLD_DURATION then
			popupState = "fading"
			fadeAlpha = 0
		end
	elseif popupState == "fading" then
		fadeAlpha = math.min(1, fadeAlpha + dt / FADE_DURATION)
		if moneyRow then
			fadeRow(moneyRow, fadeAlpha)
		end
		if dogtagRow then
			fadeRow(dogtagRow, fadeAlpha)
		end
		if fadeAlpha >= 1 then
			resetPopup()
		end
	end
end

table.insert(connections, clientMoneyEffectsRemote.OnClientEvent:Connect(function(_amount: number, increment: number?, sku: string?)
	if sku == "auto-sell-star-individual" then
		if increment == nil then
			return
		end

		addFlyingMoney("AutoSellMoney", sku, 1, increment, Color3.fromRGB(255, 240, 0), 0, 0, true)
		creditMoney(increment)
		return
	end

	if increment ~= nil and increment ~= 0 then
		moneyCollectSoundPool:Play()

		if increment > 0 then
			creditMoney(increment)

			local purples: number = increment // 100
			purples = math.min(10, purples)
			local valuePerPurple = 0
			if purples > 0 then
				valuePerPurple = ((increment // 100) * 100) / purples
			end

			local blues: number = (increment % 100) // 10
			local valuePerBlue = 0
			if blues > 0 then
				valuePerBlue = blues * 100
			end

			local greens: number = (increment % 10) // 1
			local valuePerGreen = 0
			if greens > 0 then
				valuePerGreen = (increment % 10) / greens
			end
			local baseDelay: number = 0
			local groupId = sku or ""
			addFlyingMoney("Money", groupId, greens, valuePerGreen, Color3.fromRGB(7, 255, 9), baseDelay, 0)
			baseDelay += greens * 0.12
			addFlyingMoney("Money", groupId, blues, 100, Color3.new(0, 0.502296, 0.977737), baseDelay, 0.1)
			baseDelay += blues * 0.12
			addFlyingMoney("Money", groupId, math.min(15, purples), valuePerPurple, Color3.new(0.792996, 0.00207523, 1), baseDelay, 0.25)
		end
	end
end))

local droppedCurrencyItems: {DroppedCurrencyItem.DroppedCurrencyItem} = {}
local currentMagnetRange = 0

local magnetRange = LocalPlayer:GetAttribute(MAGNET_RANGE_ATTRIBUTE)
if typeof(magnetRange) == "number" then
	currentMagnetRange = math.max(0, magnetRange)
end

table.insert(connections, LocalPlayer:GetAttributeChangedSignal(MAGNET_RANGE_ATTRIBUTE):Connect(function()
	local nextMagnetRange = LocalPlayer:GetAttribute(MAGNET_RANGE_ATTRIBUTE)
	currentMagnetRange = if typeof(nextMagnetRange) == "number" then math.max(0, nextMagnetRange) else 0
end))

local function playMoneyPickupSound(amount: number)
	if amount <= 10 then
		greencoinPool:Play()
	elseif amount <= 100 then
		bluecoinPool:Play()
	else
		purplecoinPool:Play()
	end
end

table.insert(connections, spawnCurrencyDropsRemote.OnClientEvent:Connect(function(dropPayloads: {DroppedCurrencyItem.DropData})

	if typeof(dropPayloads) ~= "table" then
		return
	end

	for _, dropData in dropPayloads do
		local droppedItem = DroppedCurrencyItem.new(dropData)
		if droppedItem then
			table.insert(droppedCurrencyItems, droppedItem)
		end
	end
end))
table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime: number)
	for i = #flyingItems, 1, -1 do
		local item = flyingItems[i]
		local didFinish = item.canDelete
		if item.canDelete or not item.part.Parent then
			if didFinish and (item.itemName == "Money" or item.itemName == "AutoSellMoney") then
				playMoneyPickupSound(item.amount)
				--ReplicatedStorage.Events.Local.MoneyAddedSpark:Fire()
			end
			item:Destroy() -- Call cleanup method if one exists
			table.remove(flyingItems, i)
		else
			item:Update(deltaTime)
		end
	end

	local currentPrimaryPart = getCurrentPrimaryPart()
	for i = #droppedCurrencyItems, 1, -1 do
		local item = droppedCurrencyItems[i]
		if item.canDelete or not item.visual.Parent then
			if item.didCollect then
				if item.dropName == "Money" then
					playMoneyPickupSound(item.amount)
					creditMoney(item.amount)
				elseif item.dropName == "Dogtags" then
					dogtagitemPool:Play()
					creditDogtags(item.amount)
				end

				if item.requiresServerCollect then
					collectCurrencyDropRemote:FireServer(item.id)
				end
			end

			item:Destroy()
			table.remove(droppedCurrencyItems, i)
		else
			item:Update(deltaTime, currentPrimaryPart, currentMagnetRange)
		end
	end

	updateCurrencyPopup(deltaTime, currentPrimaryPart)
end))

script.Destroying:Connect(function()
	if popupFrame then
		popupFrame.Visible = false
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	for _, item in flyingItems do
		item:Destroy()
	end
	table.clear(flyingItems)

	for _, item in droppedCurrencyItems do
		item:Destroy()
	end
	table.clear(droppedCurrencyItems)

	for _, soundPool in soundPools do
		soundPool:Destroy()
	end
	table.clear(soundPools)
end)
