local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local FlyingItem = require(ReplicatedStorage.Packages.FlyingItem)
local DroppedCurrencyItem = require(ReplicatedStorage.Packages.DroppedCurrencyItem)
local SoundPool = require(ReplicatedStorage.Packages.SoundPool)

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
table.insert(connections, clientMoneyEffectsRemote.OnClientEvent:Connect(function(_amount: number, increment: number?, sku: string?)
	if sku == "auto-sell-star-individual" then
		if increment == nil then
			return
		end

		addFlyingMoney("AutoSellMoney", sku, 1, increment, Color3.fromRGB(255, 240, 0), 0, 0, true)
		return
	end

	if increment ~= nil and increment ~= 0 then
		moneyCollectSoundPool:Play()

		if increment > 0 then
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
				elseif item.dropName == "Dogtags" then
					dogtagitemPool:Play()
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
end))

script.Destroying:Connect(function()
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
