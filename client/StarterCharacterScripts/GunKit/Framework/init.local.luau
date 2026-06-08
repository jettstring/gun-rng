local GunClient = require(script:WaitForChild("GunClient"))
local GuiChanger = require(script:WaitForChild("GunClient"):WaitForChild("GuiChanger"))
local ExplicitCrosshair = require(script:WaitForChild("ExplicitCrosshair"))
local RangeIndicatorManager = require(script:WaitForChild("RangeIndicatorManager"))
local RemoteGunVisualizer = require(script:WaitForChild("RemoteGunVisualizer"))
local Spring = require(script:WaitForChild("GunClient"):WaitForChild("Spring"))

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local WeaponDefinitions = require(
	ReplicatedStorage:WaitForChild("GameAssets")
		:WaitForChild("WeaponAssets")
		:WaitForChild("WeaponDefinitions")
)
local AmmoTypes = require(ReplicatedStorage.Util.AmmoTypes)
local ProjectileAudio = require(ReplicatedStorage.Packages.ProjectileAudio)

local LocalPlayer = Players.LocalPlayer
local Character = script:FindFirstAncestorOfClass("Model") or LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid: Humanoid = Character:WaitForChild("Humanoid")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local AIM_DISTANCE = 1000
local MANUAL_TO_AUTOMATIC_SHOOTING_DELAY = 2
local CAMERA_FOV_RECOIL_MAX = 4
local CAMERA_FOV_RECOIL_VELOCITY_MULTIPLIER = 18
local CAMERA_ROLL_RECOIL_MAX = math.rad(4)
local CAMERA_ROLL_RECOIL_VELOCITY_MULTIPLIER = 3
local REPLICATED_GUN_FOLDER_NAME = "PsychicGuns"
local CLIENT_GUN_FOLDER_NAME = `{LocalPlayer.Name}_PsychicGuns`
local IGNORE_TAG_NAME = "Ignore"
local PLAYER_IGNORE_TAG_NAME = `{IGNORE_TAG_NAME}-{LocalPlayer.Name}`
local IGNORE_TAG_NAMES = {IGNORE_TAG_NAME, PLAYER_IGNORE_TAG_NAME}
local AMMO_COUNTER_EMPTY_COLOR = Color3.fromRGB(255, 0, 0)
local AMMO_COUNTER_FULL_COLOR = Color3.fromRGB(255, 255, 255)
local AMMO_COUNTER_FULL_AMOUNT = 100
local GUN_VISUAL_STATE_SEND_INTERVAL = 1 / 12

type Connection = RBXScriptConnection
type WeaponDefinition = WeaponDefinitions.WeaponDefinition

type GunRecord = {
	id: string,
	gunName: string,
	gunClient: any,
	source: Instance?,
}

local gunRecordsById: {[string]: GunRecord} = {}
local gunOrder: {GunRecord} = {}
local sourceRecordIds: {[Instance]: string} = {}
local sourceConnections: {[Instance]: {Connection}} = {}
local connections: {Connection} = {}
local remoteFunctions: {[string]: RemoteFunction} = {}
local ignoreTaggedInstances: {Instance} = {}
local ignoreTaggedInstanceIndices: {[Instance]: number} = {}
local inputBound = false
local renderBound = false
local isShuttingDown = false
local uiWindowOpen = false
local nextGeneratedGunId = 0
local fireCadenceClock = 0
local fireCadenceStartsByType: {[string]: number} = {}
local projectileRaysEnabled = false
local debugVisible = false
local manualAimOverrideHeld = false
local automaticModeResumeAt = 0
local nextGunVisualStateSendTime = 0
local selectedAmmoType = AmmoTypes.Default
local ammoAmounts = AmmoTypes.createAmountMap()
local fovCamera: Camera? = nil
local normalCameraFov = 70
local cameraFovRecoilSpring = Spring.new(0, 0, 0, 30, 0.85)
local cameraRollRecoilSpring = Spring.new(0, 0, 0, 15, 0.78)
local explicitManualCameraOffsetSpring = Spring.new(
	Humanoid.CameraOffset,
	Vector3.new(),
	Humanoid.CameraOffset,
	12,
	1
)

local gunEventFolder = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("GunKit")
local GunEvent = if gunEventFolder then gunEventFolder:FindFirstChild("GunEvent") else nil
if GunEvent and not GunEvent:IsA("RemoteEvent") then
	GunEvent = nil
end

local rayIgnoreFolder = workspace:WaitForChild("RAY_IGNORE")
local existingClientGunFolder = rayIgnoreFolder:FindFirstChild(CLIENT_GUN_FOLDER_NAME)
if existingClientGunFolder then
	existingClientGunFolder:Destroy()
end

local clientGunFolder = Instance.new("Folder")
clientGunFolder.Name = CLIENT_GUN_FOLDER_NAME
clientGunFolder.Parent = rayIgnoreFolder

local remoteGunVisualizer = RemoteGunVisualizer.new(LocalPlayer, GunEvent, rayIgnoreFolder)

local gui = GuiChanger.new(PlayerGui)
local explicitCrosshair = ExplicitCrosshair.new(LocalPlayer, Character)
local rangeIndicatorManager = RangeIndicatorManager.new(Character)
local warnedUnsupportedGuns: {[string]: boolean} = {}
local mobileAimAssistEnabled = true
local mobileAimAssistButton: GuiButton? = nil
local mobileShootButton: GuiButton? = nil
local mobileShootButtonBound = false
local mobileShootButtonPressed = false
local bindToggleAimAssistButton: (() -> ())? = nil
local bindMobileShootButton: (() -> ())? = nil
local mobileShootButtonVisual: any = nil
local mobileAimAssistButtonConnections: {Connection} = {}
local mobileShootButtonConnections: {Connection} = {}
local isAutomaticGunModeEnabled = function(): boolean
	return false
end
local explicitCrosshairMouseIconWasEnabled: boolean? = nil
local explicitManualShiftLockActive = false
local explicitManualShiftLockPreviousRotationType: Enum.RotationType? = nil
local explicitManualPreviousCameraOffset: Vector3? = nil

local function disconnectConnectionList(connectionList: {Connection})
	for _, connection in connectionList do
		connection:Disconnect()
	end

	table.clear(connectionList)
end

local function isTouchShootSupported(): boolean
	return UserInputService.TouchEnabled or UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

local function isMobileAimAssistSupported(): boolean
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.TouchEnabled
		or UserInputService.GamepadEnabled
		or lastInputType == Enum.UserInputType.Touch
		or string.sub(lastInputType.Name, 1, 7) == "Gamepad"
end

local function isMobileAimAssistActive(): boolean
	return isMobileAimAssistSupported() and mobileAimAssistEnabled and #gunOrder > 0
end

local function isExplicitManualAimModeActive(): boolean
	return isMobileAimAssistSupported() and not mobileAimAssistEnabled and #gunOrder > 0
end

local function setExplicitCrosshairMouseHidden(hidden: boolean)
	if hidden then
		if explicitCrosshairMouseIconWasEnabled == nil then
			explicitCrosshairMouseIconWasEnabled = UserInputService.MouseIconEnabled
		end
		UserInputService.MouseIconEnabled = false
		return
	end

	if explicitCrosshairMouseIconWasEnabled ~= nil then
		UserInputService.MouseIconEnabled = explicitCrosshairMouseIconWasEnabled
		explicitCrosshairMouseIconWasEnabled = nil
	end
end

local function setExplicitManualShiftLockEnabled(enabled: boolean)
	if enabled then
		if not explicitManualShiftLockActive then
			local returningCameraOffset = explicitManualPreviousCameraOffset
			explicitManualShiftLockActive = true
			explicitManualShiftLockPreviousRotationType = UserGameSettings.RotationType
			explicitManualPreviousCameraOffset = returningCameraOffset or Humanoid.CameraOffset
			explicitManualCameraOffsetSpring.p = Humanoid.CameraOffset
			if not returningCameraOffset then
				explicitManualCameraOffsetSpring.v = Vector3.new()
			end
		end

		UserGameSettings.RotationType = Enum.RotationType.CameraRelative
		explicitManualCameraOffsetSpring.target = (explicitManualPreviousCameraOffset or Vector3.new())
			+ Vector3.new(3.5, 3.75, 0)
		return
	end

	if explicitManualShiftLockActive then
		if explicitManualShiftLockPreviousRotationType then
			UserGameSettings.RotationType = explicitManualShiftLockPreviousRotationType
		end
		explicitManualCameraOffsetSpring.target = explicitManualPreviousCameraOffset or Vector3.new()

		explicitManualShiftLockPreviousRotationType = nil
		explicitManualShiftLockActive = false
	end
end

local function updateExplicitManualCameraOffset(step: number)
	if not explicitManualShiftLockActive and not explicitManualPreviousCameraOffset then
		return
	end

	explicitManualCameraOffsetSpring:update(step)
	Humanoid.CameraOffset = explicitManualCameraOffsetSpring.p

	if
		not explicitManualShiftLockActive
		and explicitManualPreviousCameraOffset
		and (explicitManualCameraOffsetSpring.p - explicitManualCameraOffsetSpring.target).Magnitude <= 0.01
		and explicitManualCameraOffsetSpring.v.Magnitude <= 0.01
	then
		Humanoid.CameraOffset = explicitManualPreviousCameraOffset
		explicitManualCameraOffsetSpring.p = explicitManualPreviousCameraOffset
		explicitManualCameraOffsetSpring.v = Vector3.new()
		explicitManualPreviousCameraOffset = nil
	end
end

local function resetExplicitManualCameraOffset()
	if explicitManualPreviousCameraOffset then
		Humanoid.CameraOffset = explicitManualPreviousCameraOffset
	else
		Humanoid.CameraOffset = explicitManualCameraOffsetSpring.target
	end

	explicitManualCameraOffsetSpring.p = Humanoid.CameraOffset
	explicitManualCameraOffsetSpring.v = Vector3.new()
	explicitManualCameraOffsetSpring.target = Humanoid.CameraOffset
	explicitManualPreviousCameraOffset = nil
end

local function getToggleAimAssistButton(): GuiButton?
	local gunGui = PlayerGui:FindFirstChild("GunGui")
	local button = gunGui and gunGui:FindFirstChild("ToggleAimAssist")
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function getMobileShootButton(): GuiButton?
	local gunGui = PlayerGui:FindFirstChild("GunGui")
	local button = gunGui and gunGui:FindFirstChild("ShootButton")
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function resetMobileShootButtonVisual()
	local visual = mobileShootButtonVisual
	if not visual then
		return
	end

	visual.button.Active = visual.baseActive
	if visual.gradient then
		visual.gradient.Color = visual.baseGradientColor
	elseif visual.button:IsA("ImageButton") then
		visual.button.ImageColor3 = visual.baseImageColor3
	else
		visual.button.BackgroundColor3 = visual.baseBackgroundColor3
	end

	mobileShootButtonVisual = nil
end

local SHOOT_BUTTON_AUTO_COLOR = Color3.fromRGB(0, 0, 0)
local SHOOT_BUTTON_MANUAL_COLOR = Color3.fromRGB(253, 255, 255)

local function applyMobileShootButtonColor()
	local visual = mobileShootButtonVisual
	if not visual or visual.button ~= mobileShootButton then
		return
	end

	local color = if mobileShootButtonPressed then SHOOT_BUTTON_MANUAL_COLOR else SHOOT_BUTTON_AUTO_COLOR
	if visual.gradient then
		visual.gradient.Color = ColorSequence.new(color)
	elseif visual.button:IsA("ImageButton") then
		visual.button.ImageColor3 = color
	else
		visual.button.BackgroundColor3 = color
	end
end

local function updateMobileAimAssistState()
	local supported = isMobileAimAssistSupported()
	local currentButton = getToggleAimAssistButton()
	if currentButton ~= mobileAimAssistButton and bindToggleAimAssistButton then
		bindToggleAimAssistButton()
	end

	local button = mobileAimAssistButton
	if button then
		mobileAimAssistButton = button
		button.Visible = supported
		button.Active = supported
		button.Selectable = supported
		local onText = button:FindFirstChild("OnText")
		if onText and onText:IsA("GuiObject") then
			onText.Visible = mobileAimAssistEnabled
		end

		local offText = button:FindFirstChild("OffText")
		if offText and offText:IsA("GuiObject") then
			offText.Visible = not mobileAimAssistEnabled
		end
	end

	explicitCrosshair:setEnabled(isMobileAimAssistActive())
end

local function updateMobileShootButtonState()
	local supported = isTouchShootSupported()
	local currentButton = getMobileShootButton()
	if currentButton ~= mobileShootButton and bindMobileShootButton then
		bindMobileShootButton()
	end

	local button = mobileShootButton or currentButton
	if not button then
		return
	end

	mobileShootButton = button
	if not mobileShootButtonVisual or mobileShootButtonVisual.button ~= button then
		resetMobileShootButtonVisual()

		local gradient = button:FindFirstChildOfClass("UIGradient")
		local baseButtonColor = if button:IsA("ImageButton") then button.ImageColor3 else button.BackgroundColor3
		mobileShootButtonVisual = {
			button = button,
			gradient = gradient,
			baseActive = button.Active,
			baseImageColor3 = baseButtonColor,
			baseBackgroundColor3 = button.BackgroundColor3,
			baseGradientColor = if gradient then gradient.Color else ColorSequence.new(baseButtonColor),
		}
		applyMobileShootButtonColor()
	end
	local visible = supported and #gunOrder > 0
	button.Visible = visible
	-- Non-sinking, so the firing touch still reaches the camera.
	button.Active = false
	button.Selectable = false
	if not visible then
		resetMobileShootButtonVisual()
	end
end

local function updateInputModeUiState()
	updateMobileAimAssistState()
	updateMobileShootButtonState()
	setExplicitManualShiftLockEnabled(isExplicitManualAimModeActive())
end

local function clearMobileAimAssistButtonBinding()
	disconnectConnectionList(mobileAimAssistButtonConnections)
	mobileAimAssistButton = nil
end

bindToggleAimAssistButton = function()
	if isShuttingDown then
		return
	end

	local button = getToggleAimAssistButton()
	if not button then
		clearMobileAimAssistButtonBinding()
		updateMobileAimAssistState()
		return
	end
	if mobileAimAssistButton == button then
		updateMobileAimAssistState()
		return
	end

	clearMobileAimAssistButtonBinding()
	mobileAimAssistButton = button
	table.insert(mobileAimAssistButtonConnections, button.Activated:Connect(function()
		if not isMobileAimAssistSupported() then
			return
		end

		mobileAimAssistEnabled = not mobileAimAssistEnabled
		updateInputModeUiState()
	end))
	table.insert(mobileAimAssistButtonConnections, button.Destroying:Connect(function()
		if mobileAimAssistButton == button then
			clearMobileAimAssistButtonBinding()
			updateMobileAimAssistState()
		end
	end))
	updateInputModeUiState()
end

local function getAmmoUi()
	local gunGui = PlayerGui:FindFirstChild("GunGui")
	local gunInfoDisplay = gunGui and gunGui:FindFirstChild("GunInfoDisplay")
	local ammoButton = gunInfoDisplay and gunInfoDisplay:FindFirstChild("NextButton")
	local ammoDisplay = gunInfoDisplay and gunInfoDisplay:FindFirstChild("AmmoDisplay")

	return {
		ammoButton = ammoButton,
		ammoName = ammoButton and ammoButton:FindFirstChild("AmmoName"),
		remainingAmount = ammoDisplay and ammoDisplay:FindFirstChild("RemainingAmountCount"),
	}
end

local function updateAmmoUi()
	local ammoUi = getAmmoUi()
	local ammoName = ammoUi.ammoName
	if ammoName and ammoName:IsA("TextLabel") then
		ammoName.Text = selectedAmmoType
	end

	local remainingAmount = ammoUi.remainingAmount
	if remainingAmount and remainingAmount:IsA("TextLabel") then
		if selectedAmmoType == AmmoTypes.Default then
			remainingAmount.Text = "∞"
			remainingAmount.TextColor3 = AMMO_COUNTER_FULL_COLOR
		else
			local ammoAmount = ammoAmounts[selectedAmmoType] or 0
			remainingAmount.Text = tostring(ammoAmount)
			remainingAmount.TextColor3 = AMMO_COUNTER_EMPTY_COLOR:Lerp(
				AMMO_COUNTER_FULL_COLOR,
				math.clamp(ammoAmount / AMMO_COUNTER_FULL_AMOUNT, 0, 1)
			)
		end
	end
end

local function syncAmmoAmountsFromCharacterAttributes()
	for _, ammoTypeName in AmmoTypes.Consumable do
		ammoAmounts[ammoTypeName] = Character:GetAttribute(ammoTypeName) or 0
	end

	updateAmmoUi()
end

local function cycleAmmoSelection()
	local currentIndex = 1
	for index, validAmmoType in AmmoTypes.All do
		if validAmmoType == selectedAmmoType then
			currentIndex = index
			break
		end
	end

	local nextIndex = (currentIndex % #AmmoTypes.All) + 1
	selectedAmmoType = AmmoTypes.All[nextIndex]

	updateAmmoUi()

	if GunEvent then
		GunEvent:FireServer("SetAmmoType", selectedAmmoType)
	end
end

for _, ammoTypeName in AmmoTypes.Consumable do
	table.insert(connections, Character:GetAttributeChangedSignal(ammoTypeName):Connect(syncAmmoAmountsFromCharacterAttributes))
end
syncAmmoAmountsFromCharacterAttributes()

table.insert(connections, UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(updateInputModeUiState))
table.insert(connections, UserInputService:GetPropertyChangedSignal("GamepadEnabled"):Connect(updateInputModeUiState))
table.insert(connections, UserInputService.GamepadConnected:Connect(function()
	updateInputModeUiState()
end))
table.insert(connections, UserInputService.GamepadDisconnected:Connect(function()
	updateInputModeUiState()
end))
table.insert(connections, UserInputService.LastInputTypeChanged:Connect(function()
	updateInputModeUiState()
end))
uiWindowOpen = LocalPlayer:GetAttribute("UIWindowOpen") == true
table.insert(connections, LocalPlayer:GetAttributeChangedSignal("UIWindowOpen"):Connect(function()
	uiWindowOpen = LocalPlayer:GetAttribute("UIWindowOpen") == true
end))
table.insert(connections, PlayerGui.DescendantAdded:Connect(function(descendant)
	if
		descendant.Name ~= "GunGui"
		and descendant.Name ~= "ToggleAimAssist"
		and descendant.Name ~= "ShootButton"
	then
		return
	end

	task.defer(function()
		if isShuttingDown then
			return
		end
		if bindToggleAimAssistButton then
			bindToggleAimAssistButton()
		end
		if isShuttingDown then
			return
		end
		if bindMobileShootButton then
			bindMobileShootButton()
		end
	end)
end))

task.defer(function()
	PlayerGui:WaitForChild("GunGui", 10)
	if isShuttingDown then
		return
	end
	if bindToggleAimAssistButton then
		bindToggleAimAssistButton()
	end
	if isShuttingDown then
		return
	end
	if bindMobileShootButton then
		bindMobileShootButton()
	end
end)

local function addIgnoredInstance(instance: Instance)
	if ignoreTaggedInstanceIndices[instance] then
		return
	end

	table.insert(ignoreTaggedInstances, instance)
	ignoreTaggedInstanceIndices[instance] = #ignoreTaggedInstances
end

local function hasIgnoredInstanceTag(instance: Instance): boolean
	for _, tagName in IGNORE_TAG_NAMES do
		if CollectionService:HasTag(instance, tagName) then
			return true
		end
	end

	return false
end

local function removeIgnoredInstance(instance: Instance)
	if hasIgnoredInstanceTag(instance) then
		return
	end

	local index = ignoreTaggedInstanceIndices[instance]
	if not index then
		return
	end

	local lastInstance = ignoreTaggedInstances[#ignoreTaggedInstances]
	ignoreTaggedInstances[index] = lastInstance
	ignoreTaggedInstances[#ignoreTaggedInstances] = nil
	ignoreTaggedInstanceIndices[instance] = nil
	if lastInstance and lastInstance ~= instance then
		ignoreTaggedInstanceIndices[lastInstance] = index
	end
end

for _, tagName in IGNORE_TAG_NAMES do
	for _, instance in CollectionService:GetTagged(tagName) do
		addIgnoredInstance(instance)
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tagName):Connect(addIgnoredInstance))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tagName):Connect(removeIgnoredInstance))
end

local function getPositiveSetting(value: number?, defaultValue: number): number
	if typeof(value) == "number" and value > 0 then
		return value
	end

	return defaultValue
end

local function resetCameraFovSpring(camera: Camera?)
	fovCamera = camera
	if camera then
		normalCameraFov = camera.FieldOfView
	end

	cameraFovRecoilSpring.p = 0
	cameraFovRecoilSpring.v = 0
	cameraFovRecoilSpring.target = 0
	cameraRollRecoilSpring.p = 0
	cameraRollRecoilSpring.v = 0
	cameraRollRecoilSpring.target = 0
end

local function getCameraRecoilTypeKey(gunData: WeaponDefinition, gunName: string): string
	if typeof(gunData.label) == "string" and gunData.label ~= "" then
		return string.lower(gunData.label)
	end

	return string.lower(gunName)
end

local function applyCameraShotRecoil(gunData: WeaponDefinition, gunName: string, recoilMultiplier: number?, gunId: string)
	local recoilTypeKey = getCameraRecoilTypeKey(gunData, gunName)
	for _, record in gunOrder do
		local recordGunData = record.gunClient and record.gunClient.gunData
		local recordTypeKey = if typeof(recordGunData) == "table"
			then getCameraRecoilTypeKey(recordGunData, record.gunName)
			else string.lower(record.gunName)

		if recordTypeKey == recoilTypeKey and record.id ~= gunId then
			return
		elseif recordTypeKey == recoilTypeKey then
			break
		end
	end

	local multiplier = if typeof(recoilMultiplier) == "number" then math.max(recoilMultiplier, 0) else 1
	local rollRecoil = getPositiveSetting(gunData.cameraRollRecoilStrength, 0) * multiplier
	if rollRecoil > 0 then
		local rollDirection = if math.random(0, 1) == 0 then -1 else 1
		local rollImpulse = math.rad(rollRecoil) * rollDirection
		cameraRollRecoilSpring.p = math.clamp(
			cameraRollRecoilSpring.p + rollImpulse,
			-CAMERA_ROLL_RECOIL_MAX,
			CAMERA_ROLL_RECOIL_MAX
		)
		cameraRollRecoilSpring.v = math.clamp(
			cameraRollRecoilSpring.v + rollImpulse * CAMERA_ROLL_RECOIL_VELOCITY_MULTIPLIER,
			-CAMERA_ROLL_RECOIL_MAX * CAMERA_ROLL_RECOIL_VELOCITY_MULTIPLIER,
			CAMERA_ROLL_RECOIL_MAX * CAMERA_ROLL_RECOIL_VELOCITY_MULTIPLIER
		)
	end

	local fovRecoil = getPositiveSetting(gunData.cameraFovRecoilStrength, 0) * multiplier
	if fovRecoil > 0 then
		cameraFovRecoilSpring.p = math.clamp(cameraFovRecoilSpring.p + fovRecoil, 0, CAMERA_FOV_RECOIL_MAX)
		cameraFovRecoilSpring.v = math.clamp(
			cameraFovRecoilSpring.v + fovRecoil * CAMERA_FOV_RECOIL_VELOCITY_MULTIPLIER,
			0,
			CAMERA_FOV_RECOIL_MAX * CAMERA_FOV_RECOIL_VELOCITY_MULTIPLIER
		)
	end
end

local function updateCameraEffects(step: number)
	local camera = workspace.CurrentCamera
	if not camera then
		resetCameraFovSpring(nil)
		return
	end

	if camera ~= fovCamera then
		resetCameraFovSpring(camera)
	end

	cameraFovRecoilSpring.target = 0
	cameraFovRecoilSpring:update(step)
	cameraFovRecoilSpring.p = math.clamp(cameraFovRecoilSpring.p, 0, CAMERA_FOV_RECOIL_MAX)

	cameraRollRecoilSpring.target = 0
	cameraRollRecoilSpring:update(step)
	cameraRollRecoilSpring.p = math.clamp(cameraRollRecoilSpring.p, -CAMERA_ROLL_RECOIL_MAX, CAMERA_ROLL_RECOIL_MAX)

	camera.FieldOfView = math.clamp(normalCameraFov + cameraFovRecoilSpring.p, 1, 120)
	if math.abs(cameraRollRecoilSpring.p) > 1e-4 then
		camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, cameraRollRecoilSpring.p)
	end
end

local function getWeaponDefinition(gunName: string): WeaponDefinition?
	local directDefinition = WeaponDefinitions[gunName]
	if directDefinition then
		return directDefinition
	end

	local loweredGunName = string.lower(gunName)
	for definitionName, definition in WeaponDefinitions do
		if typeof(definitionName) == "string" and string.lower(definitionName) == loweredGunName then
			return definition
		end

		if typeof(definition) == "table" and typeof(definition.label) == "string" then
			if string.lower(definition.label) == loweredGunName then
				return definition
			end
		end
	end

	if not warnedUnsupportedGuns[gunName] then
		warn(`GunKit has no weapon definition for "{gunName}".`)
		warnedUnsupportedGuns[gunName] = true
	end

	return nil
end

local function getCharacterForwardAimPoint(): Vector3
	local rootPart = Character.PrimaryPart
	if not rootPart then
		local humanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			rootPart = humanoidRootPart
		end
	end

	if rootPart then
		return rootPart.Position + rootPart.CFrame.LookVector * AIM_DISTANCE
	end

	return Vector3.new(0, 0, -AIM_DISTANCE)
end

local function getRaycastAimPoint(aimRay: Ray): Vector3
	local raycastParams = RaycastParams.new()
	local filterInstances = {Character, rayIgnoreFolder}
	local vecViz = workspace:FindFirstChild("VecViz")
	if vecViz then
		table.insert(filterInstances, vecViz)
	end

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterInstances
	raycastParams:AddToFilter(ignoreTaggedInstances)

	local raycastResult = workspace:Raycast(aimRay.Origin, aimRay.Direction * AIM_DISTANCE, raycastParams)
	if raycastResult then
		return raycastResult.Position
	end

	return aimRay.Origin + aimRay.Direction * AIM_DISTANCE
end

local function getAimPoint(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return getCharacterForwardAimPoint()
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	if mouseLocation.X <= 0 and mouseLocation.Y <= 0 then
		mouseLocation = camera.ViewportSize / 2
	end

	local aimRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	return getRaycastAimPoint(aimRay)
end

local function isMouseOverInteractableGui(): boolean
	local mouseLocation = UserInputService:GetMouseLocation()
	for _, guiObject in PlayerGui:GetGuiObjectsAtPosition(mouseLocation.X, mouseLocation.Y) do
		if guiObject.Active and (guiObject:IsA("GuiButton") or guiObject:IsA("TextBox")) then
			return true
		end
	end

	return false
end

local function refreshGunSlots()
	local totalGuns = #gunOrder
	local recordsByType: {[string]: {GunRecord}} = {}
	local autoAimRanges = {}
	local autoAimRangeSet: {[number]: boolean} = {}

	for index, record in gunOrder do
		record.gunClient:setSlot(index, totalGuns)
		record.gunClient:setProjectileRays(projectileRaysEnabled)

		local recordGunData = record.gunClient and record.gunClient.gunData
		local gunTypeKey = if typeof(recordGunData) == "table"
			then getCameraRecoilTypeKey(recordGunData, record.gunName)
			else string.lower(record.gunName)
		local recordsForType = recordsByType[gunTypeKey]
		if not recordsForType then
			recordsForType = {}
			recordsByType[gunTypeKey] = recordsForType
		end
		table.insert(recordsForType, record)

		local autoAimRange = if typeof(record.gunClient.gunData.autoAimRange) == "number"
				and record.gunClient.gunData.autoAimRange > 0
			then record.gunClient.gunData.autoAimRange
			else 0
		if autoAimRange > 0 and not autoAimRangeSet[autoAimRange] then
			autoAimRangeSet[autoAimRange] = true
			table.insert(autoAimRanges, autoAimRange)
		end
	end

	local staleGunTypeKeys = {}
	for gunTypeKey in fireCadenceStartsByType do
		if not recordsByType[gunTypeKey] then
			table.insert(staleGunTypeKeys, gunTypeKey)
		end
	end
	for _, gunTypeKey in staleGunTypeKeys do
		fireCadenceStartsByType[gunTypeKey] = nil
	end

	for gunTypeKey, recordsForType in recordsByType do
		local cadenceStartTime = fireCadenceStartsByType[gunTypeKey]
		if not cadenceStartTime then
			cadenceStartTime = fireCadenceClock
			fireCadenceStartsByType[gunTypeKey] = cadenceStartTime
		end

		local totalOfType = #recordsForType
		for typeIndex, record in recordsForType do
			record.gunClient:setFireCadence(typeIndex, totalOfType, cadenceStartTime, fireCadenceClock)
		end
	end

	rangeIndicatorManager:setRanges(autoAimRanges)
	gui:setEnabled(#gunOrder > 0)
end

local function removeRecordFromOrder(record: GunRecord)
	for index, orderedRecord in gunOrder do
		if orderedRecord == record then
			table.remove(gunOrder, index)
			return
		end
	end
end

function isAutomaticGunModeEnabled(): boolean
	return not isExplicitManualAimModeActive() and not manualAimOverrideHeld and fireCadenceClock >= automaticModeResumeAt
end

local function updateGunShootingMode()
	local automaticGunModeEnabled = isAutomaticGunModeEnabled()
	local shouldShoot = manualAimOverrideHeld or automaticGunModeEnabled
	for _, record in gunOrder do
		record.gunClient:setAutoAimEnabled(automaticGunModeEnabled)
		record.gunClient:setShoot(shouldShoot)
	end
end

local function sendGunVisualState()
	if not GunEvent or #gunOrder <= 0 then
		return
	end

	local visualStates = {}
	for _, record in gunOrder do
		local visualState = record.gunClient:getVisualReplicationState()
		if visualState then
			table.insert(visualStates, visualState)
		end
	end

	if #visualStates > 0 then
		GunEvent:FireServer("GunVisualState", visualStates)
	end
end

local function updateAllGuns(step: number)
	fireCadenceClock += step
	updateGunShootingMode()
	local explicitTargetingActive = isMobileAimAssistActive()
	local explicitManualAimModeActive = isExplicitManualAimModeActive()
	setExplicitManualShiftLockEnabled(explicitManualAimModeActive)
	updateExplicitManualCameraOffset(step)

	local manualAimModeActive = explicitManualAimModeActive or manualAimOverrideHeld or not isAutomaticGunModeEnabled()
	local centeredExplicitAimPoint = nil
	if explicitManualAimModeActive then
		local camera = workspace.CurrentCamera
		if camera then
			local viewportCenter = camera.ViewportSize / 2
			local aimRay = camera:ViewportPointToRay(viewportCenter.X, viewportCenter.Y)
			centeredExplicitAimPoint = getRaycastAimPoint(aimRay)
		else
			centeredExplicitAimPoint = getCharacterForwardAimPoint()
		end
	end
	local fallbackAimPoint = if explicitTargetingActive or explicitManualAimModeActive then nil else getAimPoint()
	explicitCrosshair:update(step)

	local explicitTargetAimPoint = if explicitTargetingActive and manualAimModeActive then explicitCrosshair:getAimPoint() else nil
	local aimPoint = centeredExplicitAimPoint or explicitTargetAimPoint or fallbackAimPoint
	local mouseExplicitCrosshairActive = manualAimModeActive
		and not explicitTargetingActive
		and not explicitManualAimModeActive
		and aimPoint ~= nil
		and UserInputService.MouseEnabled
		and not isMouseOverInteractableGui()
		and not uiWindowOpen
	if explicitManualAimModeActive and aimPoint then
		-- Pin the reticle to screen center; the gun still aims at the raycast world
		-- point (aimPoint), only the display stops reprojecting (no swim on pan).
		setExplicitCrosshairMouseHidden(false)
		local camera = workspace.CurrentCamera
		if camera then
			explicitCrosshair:showAtViewportPoint(camera.ViewportSize / 2)
		else
			explicitCrosshair:hide()
		end
	elseif mouseExplicitCrosshairActive and aimPoint then
		-- Pin the reticle to the cursor directly rather than reprojecting the hit.
		setExplicitCrosshairMouseHidden(true)
		explicitCrosshair:showAtViewportPoint(UserInputService:GetMouseLocation())
	else
		setExplicitCrosshairMouseHidden(false)
		if not explicitTargetingActive then
			explicitCrosshair:hide()
		end
	end

	for _, record in gunOrder do
		record.gunClient:update(step, aimPoint, manualAimModeActive, fireCadenceClock)
	end

	if fireCadenceClock >= nextGunVisualStateSendTime then
		nextGunVisualStateSendTime = fireCadenceClock + GUN_VISUAL_STATE_SEND_INTERVAL
		sendGunVisualState()
	end

	updateCameraEffects(step)
	if aimPoint then
		gui:positionCrosshair(aimPoint)
	end
	gui:update(step)
end

local function setManualAimOverride(enabled: boolean)
	local shouldEnable = enabled == true
	if manualAimOverrideHeld == shouldEnable then
		return
	end

	local wasManualAimOverrideHeld = manualAimOverrideHeld
	manualAimOverrideHeld = shouldEnable
	if shouldEnable then
		automaticModeResumeAt = 0
		for gunTypeKey in fireCadenceStartsByType do
			fireCadenceStartsByType[gunTypeKey] = fireCadenceClock
		end
		refreshGunSlots()
		-- On the press, ask every gun to fire now if it has cooled down, so a click fires all ready
		-- guns at once instead of only the gun whose staggered cadence slot is currently live.
		for _, record in gunOrder do
			record.gunClient:requestManualFire()
		end
	elseif wasManualAimOverrideHeld then
		automaticModeResumeAt = fireCadenceClock + MANUAL_TO_AUTOMATIC_SHOOTING_DELAY
	end

	updateGunShootingMode()
end

local SHOOT_TAP_MOVE_TOLERANCE = 20 -- px a free-space touch may drift and still count as a tap
local SHOOT_TAP_MAX_DURATION = 0.1 -- seconds; a clean tap must release within this
local SHOOT_TAP_HOLD_WINDOW = 0.3 -- seconds; re-press window after a clean tap
local SHOOT_PAN_HOLD_WINDOW = 0.2 -- seconds; tighter re-press window after a pan
local SHOOT_PAN_HOLD_GRACE = 0.05 -- seconds a pan re-press must stay still before it fires
local SHOOT_TAP_HOLD_MAX_DISTANCE_FRACTION = 0.3 -- of the larger viewport axis

local SHOOT_TOUCH_SHOOT = "shoot"
local SHOOT_TOUCH_PENDING = "pending"
local SHOOT_TOUCH_PAN_PENDING = "panPending"
local SHOOT_TOUCH_IGNORED = "ignored"
type ShootTouchState = {role: string, startPosition: Vector2, startTime: number}
local shootTouchStates: {[InputObject]: ShootTouchState} = {}
local shootHoldArmExpiresAt: number? = nil
local shootHoldArmPosition: Vector2? = nil
local shootHoldArmFromPan = false

local function refreshMobileShootingState()
	local shooting = false
	for _, state in shootTouchStates do
		if state.role == SHOOT_TOUCH_SHOOT then
			shooting = true
			break
		end
	end

	mobileShootButtonPressed = shooting
	applyMobileShootButtonColor()
	setManualAimOverride(shooting)
end

local function clearAllShootTouches()
	if next(shootTouchStates) ~= nil then
		table.clear(shootTouchStates)
	end
	shootHoldArmExpiresAt = nil
	shootHoldArmPosition = nil
	shootHoldArmFromPan = false
	refreshMobileShootingState()
end

local function onShootTouchBegan(input: InputObject, gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if not isTouchShootSupported() or #gunOrder <= 0 then
		return
	end
	if shootTouchStates[input] then
		return
	end

	local onShootButton = false
	local onOtherGui = false
	for _, guiObject in PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y) do
		if mobileShootButton and guiObject == mobileShootButton then
			onShootButton = true
		elseif guiObject.Active and (guiObject:IsA("GuiButton") or guiObject:IsA("TextBox")) then
			onOtherGui = true
		end
	end

	local role
	if onShootButton then
		role = SHOOT_TOUCH_SHOOT
	elseif onOtherGui or gameProcessed then
		role = SHOOT_TOUCH_IGNORED
	else
		role = SHOOT_TOUCH_PAN_PENDING
	end

	-- A free-space re-press fires only if a recent touch armed it (near the same
	-- spot, within the window): tap-armed fires now; pan-armed waits out the grace
	-- timer to see whether the finger holds still or keeps panning.
	if role == SHOOT_TOUCH_PAN_PENDING and shootHoldArmExpiresAt and os.clock() <= shootHoldArmExpiresAt then
		local armed = true
		if shootHoldArmPosition then
			local camera = workspace.CurrentCamera
			local viewportSize = if camera then camera.ViewportSize else Vector2.new(1, 1)
			local maxDistance = math.max(viewportSize.X, viewportSize.Y) * SHOOT_TAP_HOLD_MAX_DISTANCE_FRACTION
			armed = (Vector2.new(input.Position.X, input.Position.Y) - shootHoldArmPosition).Magnitude <= maxDistance
		end
		if armed then
			role = if shootHoldArmFromPan then SHOOT_TOUCH_PENDING else SHOOT_TOUCH_SHOOT
		end
	end

	if role == SHOOT_TOUCH_SHOOT or role == SHOOT_TOUCH_PENDING then
		shootHoldArmExpiresAt = nil
		shootHoldArmPosition = nil
		shootHoldArmFromPan = false
	end

	shootTouchStates[input] = {
		role = role,
		startPosition = Vector2.new(input.Position.X, input.Position.Y),
		startTime = os.clock(),
	}

	if role == SHOOT_TOUCH_SHOOT then
		refreshMobileShootingState()
	elseif role == SHOOT_TOUCH_PENDING then
		task.delay(SHOOT_PAN_HOLD_GRACE, function()
			local pending = shootTouchStates[input]
			if not pending or pending.role ~= SHOOT_TOUCH_PENDING then
				return
			end

			local moved = (Vector2.new(input.Position.X, input.Position.Y) - pending.startPosition).Magnitude
			if moved > SHOOT_TAP_MOVE_TOLERANCE then
				pending.role = SHOOT_TOUCH_PAN_PENDING
			else
				pending.role = SHOOT_TOUCH_SHOOT
				refreshMobileShootingState()
			end
		end)
	end
end

local function onShootTouchEnded(input: InputObject)
	local state = shootTouchStates[input]
	if not state then
		return
	end
	shootTouchStates[input] = nil

	if state.role == SHOOT_TOUCH_SHOOT then
		refreshMobileShootingState()
		return
	end

	if state.role == SHOOT_TOUCH_PAN_PENDING or state.role == SHOOT_TOUCH_PENDING then
		local now = os.clock()
		local endPosition = Vector2.new(input.Position.X, input.Position.Y)
		local moved = (endPosition - state.startPosition).Magnitude
		if moved <= SHOOT_TAP_MOVE_TOLERANCE then
			-- Stayed still: only a quick tap arms; a long rest arms nothing.
			if (now - state.startTime) <= SHOOT_TAP_MAX_DURATION then
				shootHoldArmExpiresAt = now + SHOOT_TAP_HOLD_WINDOW
				shootHoldArmPosition = endPosition
				shootHoldArmFromPan = false
			end
		else
			-- A pan arms only a very brief follow-up, so just a fast re-press fires.
			shootHoldArmExpiresAt = now + SHOOT_PAN_HOLD_WINDOW
			shootHoldArmPosition = endPosition
			shootHoldArmFromPan = true
		end
	end
end

local function clearMobileShootButtonBinding()
	disconnectConnectionList(mobileShootButtonConnections)
	clearAllShootTouches()
	resetMobileShootButtonVisual()
	mobileShootButton = nil
	mobileShootButtonBound = false
	mobileShootButtonPressed = false
end

bindMobileShootButton = function()
	if isShuttingDown then
		return
	end

	local button = getMobileShootButton()
	if not button then
		clearMobileShootButtonBinding()
		updateMobileShootButtonState()
		return
	end
	if mobileShootButton == button and mobileShootButtonBound then
		updateMobileShootButtonState()
		return
	end

	clearMobileShootButtonBinding()
	mobileShootButton = button
	mobileShootButtonBound = true
	table.insert(mobileShootButtonConnections, UserInputService.InputBegan:Connect(onShootTouchBegan))
	table.insert(mobileShootButtonConnections, UserInputService.InputEnded:Connect(onShootTouchEnded))
	table.insert(mobileShootButtonConnections, button.Destroying:Connect(function()
		if mobileShootButton == button then
			clearMobileShootButtonBinding()
			updateMobileShootButtonState()
		end
	end))
	updateMobileShootButtonState()
end

local function setGunsAutoFireEnabled(enabled: boolean)
	if enabled == true then
		updateGunShootingMode()
		return
	end

	for _, record in gunOrder do
		record.gunClient:setAutoAimEnabled(false)
		record.gunClient:setShoot(false)
	end
end

table.insert(connections, GuiService.MenuOpened:Connect(function()
	clearAllShootTouches()
	setManualAimOverride(false)
end))

local function setProjectileRaysEnabled(enabled: boolean): boolean
	projectileRaysEnabled = enabled == true
	for _, record in gunOrder do
		record.gunClient:setProjectileRays(projectileRaysEnabled)
	end

	return projectileRaysEnabled
end

local function setDebugVisible(enabled: boolean)
	debugVisible = enabled
	for _, record in gunOrder do
		record.gunClient:setDebugVisible(debugVisible)
	end
end

local function bindGunControls()
	if inputBound then
		return
	end

	inputBound = true

	ContextActionService:BindAction("gunKitShoot", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setManualAimOverride(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			setManualAimOverride(false)
		end

		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("gunKitSway", function(_, inputState, inputObject)
		if not inputObject then
			return Enum.ContextActionResult.Pass
		end

		for _, record in gunOrder do
			record.gunClient:updateSway(inputState, inputObject)
		end

		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseMovement, Enum.KeyCode.Thumbstick2)

	ContextActionService:BindAction("gunKitProjectileRays", function(_, inputState)
		if inputState == Enum.UserInputState.End then
			setProjectileRaysEnabled(not projectileRaysEnabled)
		end

		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.P)

	ContextActionService:BindAction("gunKitDebug", function(_, inputState)
		if inputState == Enum.UserInputState.End then
			local enabled = not debugVisible
			setDebugVisible(enabled)
			setProjectileRaysEnabled(enabled)
		end

		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K)
end

local function unbindGunControls()
	if not inputBound then
		return
	end

	inputBound = false
	setManualAimOverride(false)
	setGunsAutoFireEnabled(false)
	ContextActionService:UnbindAction("gunKitShoot")
	ContextActionService:UnbindAction("gunKitSway")
	ContextActionService:UnbindAction("gunKitProjectileRays")
	ContextActionService:UnbindAction("gunKitDebug")
end

local function unbindGunRender()
	if not renderBound then
		return
	end

	renderBound = false
	RunService:UnbindFromRenderStep("gunKitPsychicGuns")

	local camera = fovCamera
	if camera then
		camera.FieldOfView = normalCameraFov
	end

	resetCameraFovSpring(nil)
end

local function updateGunBindings()
	if #gunOrder > 0 then
		bindGunControls()
		if not renderBound then
			renderBound = true
			RunService:BindToRenderStep("gunKitPsychicGuns", Enum.RenderPriority.Camera.Value + 1, updateAllGuns)
		end
		setGunsAutoFireEnabled(true)
	else
		setGunsAutoFireEnabled(false)
		unbindGunControls()
		unbindGunRender()
		setExplicitManualShiftLockEnabled(false)
		resetExplicitManualCameraOffset()
		resetMobileShootButtonVisual()
		setExplicitCrosshairMouseHidden(false)
		explicitCrosshair:hide()
		gui:setEnabled(false)
	end

	updateInputModeUiState()
end

local function clearDescriptorBookkeeping(descriptor: Instance)
	sourceRecordIds[descriptor] = nil

	local descriptorConnections = sourceConnections[descriptor]
	if descriptorConnections then
		disconnectConnectionList(descriptorConnections)
		sourceConnections[descriptor] = nil
	end
end

local function addGun(gunName: string, requestedGunId: string?, source: Instance?): string?
	if isShuttingDown then
		return nil
	end

	if typeof(gunName) ~= "string" or gunName == "" then
		warn("GunKit addGun expected a non-empty gun name.")
		return nil
	end

	local weaponDefinition = getWeaponDefinition(gunName)
	if not weaponDefinition then
		return nil
	end

	local gunId = if typeof(requestedGunId) == "string" and requestedGunId ~= "" then requestedGunId else nil
	if not gunId then
		nextGeneratedGunId += 1
		gunId = `{gunName}:{nextGeneratedGunId}`
	end

	local existingRecord = gunRecordsById[gunId]
	if existingRecord then
		local descriptors = {}
		if existingRecord.source then
			table.insert(descriptors, existingRecord.source)
		end

		for descriptor, recordId in sourceRecordIds do
			if recordId == existingRecord.id then
				table.insert(descriptors, descriptor)
			end
		end

		for _, descriptor in descriptors do
			clearDescriptorBookkeeping(descriptor)
		end

		existingRecord.gunClient:DestroyModels()
		removeRecordFromOrder(existingRecord)
		gunRecordsById[gunId] = nil
	end

	local gunClient = GunClient.new(LocalPlayer, Character, weaponDefinition, {
		gunId = gunId,
		gunName = gunName,
		gunEvent = GunEvent,
		modelParent = clientGunFolder,
		anchorParent = clientGunFolder,
		onClientShot = function(shotGunData: WeaponDefinition, shotGunName: string, recoilMultiplier: number)
			applyCameraShotRecoil(shotGunData, shotGunName, recoilMultiplier, gunId)
		end,
		canClientShoot = function()
			if selectedAmmoType == AmmoTypes.Default then
				return true
			end

			local amount = ammoAmounts[selectedAmmoType] or 0
			if amount <= 0 then
				return false
			end

			ammoAmounts[selectedAmmoType] = amount - 1
			updateAmmoUi()

			return true
		end,
		requiresOnTarget = function()
			-- Special/consumable don't shoot target until a target is acquired
			return AmmoTypes.isConsumable(selectedAmmoType)
		end,
	})

	if not gunClient then
		warn(`Unable to initialize psychic gun "{gunName}".`)
		return nil
	end

	gunClient:equip()
	gunClient:setProjectileRays(projectileRaysEnabled)
	gunClient:setAutoAimEnabled(true)
	gunClient:setDebugVisible(debugVisible)

	local record: GunRecord = {
		id = gunId,
		gunName = gunName,
		gunClient = gunClient,
		source = source,
	}

	gunRecordsById[gunId] = record
	table.insert(gunOrder, record)
	refreshGunSlots()
	updateGunBindings()

	return gunId
end

local function removeGun(gunId: string): boolean
	local record = gunRecordsById[gunId]
	if not record then
		return false
	end

	record.gunClient:DestroyModels()
	removeRecordFromOrder(record)
	gunRecordsById[gunId] = nil
	refreshGunSlots()
	updateGunBindings()

	return true
end

local function clearAllGuns()
	local records = table.clone(gunOrder)
	for _, record in records do
		removeGun(record.id)
	end
end

local function unregisterGunDescriptor(descriptor: Instance)
	local recordId = sourceRecordIds[descriptor]
	if recordId then
		removeGun(recordId)
	end

	clearDescriptorBookkeeping(descriptor)
end

local function registerGunDescriptor(descriptor: Instance)
	if isShuttingDown then
		return
	end

	unregisterGunDescriptor(descriptor)

	local gunNameAttribute = descriptor:GetAttribute("GunName")
	local weaponNameAttribute = descriptor:GetAttribute("WeaponName")
	local gunIdAttribute = descriptor:GetAttribute("GunId")
	local gunName = if typeof(gunNameAttribute) == "string" and gunNameAttribute ~= ""
		then gunNameAttribute
		elseif typeof(weaponNameAttribute) == "string" and weaponNameAttribute ~= "" then weaponNameAttribute
		elseif descriptor:IsA("StringValue") and descriptor.Value ~= "" then descriptor.Value
		else descriptor.Name
	local gunId = if typeof(gunIdAttribute) == "string" and gunIdAttribute ~= "" then gunIdAttribute else nil
	local recordId = addGun(gunName, gunId, descriptor)
	if not recordId then
		return
	end

	sourceRecordIds[descriptor] = recordId
	sourceConnections[descriptor] = {
		descriptor:GetAttributeChangedSignal("GunName"):Connect(function()
			registerGunDescriptor(descriptor)
		end),
		descriptor:GetAttributeChangedSignal("WeaponName"):Connect(function()
			registerGunDescriptor(descriptor)
		end),
		descriptor:GetAttributeChangedSignal("GunId"):Connect(function()
			registerGunDescriptor(descriptor)
		end),
	}

	if descriptor:IsA("StringValue") then
		table.insert(sourceConnections[descriptor], descriptor:GetPropertyChangedSignal("Value"):Connect(function()
			registerGunDescriptor(descriptor)
		end))
	end
end

local function observeReplicatedGunFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		registerGunDescriptor(child)
	end

	table.insert(connections, folder.ChildAdded:Connect(registerGunDescriptor))
	table.insert(connections, folder.ChildRemoved:Connect(unregisterGunDescriptor))
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local gunKitRemotesFolder: Instance? = nil
if remotesFolder then
	gunKitRemotesFolder = remotesFolder:WaitForChild("GunKit", 10)
end

if not remotesFolder then
	warn("ReplicatedStorage.Remotes was not found; GunKit server calls are disabled.")
elseif not gunKitRemotesFolder then
	warn("ReplicatedStorage.Remotes.GunKit was not found; GunKit server calls are disabled.")
else
	for _, remoteFunctionName in {"AddGun", "RemoveGun", "ClearGuns", "SetProjectileRays"} do
		local remoteFunction = gunKitRemotesFolder:WaitForChild(remoteFunctionName, 10)
		if not remoteFunction then
			warn(`GunKit remote function ReplicatedStorage.Remotes.GunKit.{remoteFunctionName} was not found.`)
		elseif not remoteFunction:IsA("RemoteFunction") then
			warn(`ReplicatedStorage.Remotes.GunKit.{remoteFunctionName} must be a RemoteFunction.`)
		else
			remoteFunctions[remoteFunctionName] = remoteFunction
		end
	end

	local addGunRemote = remoteFunctions.AddGun
	if addGunRemote then
		addGunRemote.OnClientInvoke = function(gunName: string, gunId: string?)
			return addGun(gunName, gunId)
		end
	end

	local removeGunRemote = remoteFunctions.RemoveGun
	if removeGunRemote then
		removeGunRemote.OnClientInvoke = function(gunId: string)
			return removeGun(gunId)
		end
	end

	local clearGunsRemote = remoteFunctions.ClearGuns
	if clearGunsRemote then
		clearGunsRemote.OnClientInvoke = function()
			clearAllGuns()
			return true
		end
	end

	local setProjectileRaysRemote = remoteFunctions.SetProjectileRays
	if setProjectileRaysRemote then
		setProjectileRaysRemote.OnClientInvoke = setProjectileRaysEnabled
	end
end

local existingReplicatedGunFolder = Character:FindFirstChild(REPLICATED_GUN_FOLDER_NAME)
if existingReplicatedGunFolder then
	observeReplicatedGunFolder(existingReplicatedGunFolder)
end

table.insert(connections, Character.ChildAdded:Connect(function(child)
	if child.Name == REPLICATED_GUN_FOLDER_NAME then
		observeReplicatedGunFolder(child)
	end
end))

if GunEvent then
	table.insert(connections, GunEvent.OnClientEvent:Connect(function(action: string, ...)
		if action == "AddGun" then
			local gunName, gunId = ...
			addGun(gunName, gunId)
		elseif action == "RemoveGun" then
			local gunId = ...
			if typeof(gunId) == "string" then
				removeGun(gunId)
			end
		elseif action == "ClearGuns" then
			clearAllGuns()
		elseif action == "SetProjectileRays" then
			local enabled = ...
			setProjectileRaysEnabled(enabled)
		elseif action == "AmmoState" then
			local ammoType = ...
			if typeof(ammoType) == "string" and AmmoTypes.isKnown(ammoType) then
				selectedAmmoType = ammoType
			else
				selectedAmmoType = AmmoTypes.Default
			end

			updateAmmoUi()
		elseif action == "GunVisualState" then
			local ownerUserId, visualStates = ...
			remoteGunVisualizer:applyState(ownerUserId, visualStates)
		elseif action == "GunVisualShot" then
			local ownerUserId, gunId, shootCFrame, shootDirection = ...
			remoteGunVisualizer:applyShot(ownerUserId, gunId, shootCFrame, shootDirection)
		end
	end))

	task.defer(function()
		PlayerGui:WaitForChild("GunGui", 10)
		if isShuttingDown then
			return
		end

		local ammoUi = getAmmoUi()
		local ammoButton = ammoUi.ammoButton
		if ammoButton and ammoButton:IsA("GuiButton") then
			if isShuttingDown then
				return
			end

			table.insert(connections, ammoButton.Activated:Connect(function()
				cycleAmmoSelection()
			end))

			updateAmmoUi()
		end
	end)
end

local function shutdown()
	if isShuttingDown then
		return
	end

	isShuttingDown = true

	local descriptors = {}
	for descriptor in sourceRecordIds do
		table.insert(descriptors, descriptor)
	end

	for _, descriptor in descriptors do
		unregisterGunDescriptor(descriptor)
	end

	clearMobileAimAssistButtonBinding()
	clearMobileShootButtonBinding()

	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}

	clearAllGuns()
	ProjectileAudio.destroy()
	setExplicitManualShiftLockEnabled(false)
	resetExplicitManualCameraOffset()
	resetMobileShootButtonVisual()
	setExplicitCrosshairMouseHidden(false)
	remoteGunVisualizer:Destroy()
	explicitCrosshair:Destroy()
	rangeIndicatorManager:Destroy()
	unbindGunControls()
	unbindGunRender()
	gui:setEnabled(false)

	for _, remoteFunction in remoteFunctions do
		remoteFunction.OnClientInvoke = nil
	end
	remoteFunctions = {}

	if clientGunFolder.Parent then
		clientGunFolder:Destroy()
	end
end

table.insert(connections, Humanoid.Died:Connect(shutdown))
table.insert(connections, Character.Destroying:Connect(shutdown))
