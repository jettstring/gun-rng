local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("WeaponAssets")

local RANGE_INDICATOR_TEMPLATE_NAME = "RangeIndicator"
local BASE_Y_POSITION = 0.1
local Y_POSITION_STEP = 0.01

type Connection = RBXScriptConnection

type IndicatorRecord = {
	range: number,
	yPosition: number,
	instance: BasePart,
}

local module = {}
local module_mt = {__index = module}

local function getRootPart(character: Model): BasePart?
	local primaryPart = character.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return nil
end

local function resizeIndicator(indicator: BasePart, range: number)
	local diameter = range * 2
	indicator.Size = Vector3.new(diameter, indicator.Size.Y, diameter)
end

local function normalizeRanges(ranges: {number}): {number}
	local rangeSet: {[number]: boolean} = {}
	local normalizedRanges = {}

	for _, range in ranges do
		if typeof(range) == "number" and range > 0 and not rangeSet[range] then
			rangeSet[range] = true
			table.insert(normalizedRanges, range)
		end
	end

	table.sort(normalizedRanges, function(left, right)
		return left > right
	end)

	return normalizedRanges
end

function module.new(character: Model)
	local self = setmetatable({}, module_mt)
	self.character = character
	self.template = WeaponAssets:WaitForChild(RANGE_INDICATOR_TEMPLATE_NAME) :: BasePart
	self.indicators = {} :: {IndicatorRecord}
	self.heartbeatConnection = nil :: Connection?

	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:update()
	end)

	return self
end

function module:clear()
	for _, indicator in self.indicators do
		indicator.instance:Destroy()
	end

	self.indicators = {}
end

function module:setRanges(ranges: {number})
	self:clear()

	for index, range in normalizeRanges(ranges) do
		local indicator = self.template:Clone() :: BasePart
		indicator.Name = `RangeIndicator_{range}`
		resizeIndicator(indicator, range)
		indicator.Parent = self.character

		table.insert(self.indicators, {
			range = range,
			yPosition = BASE_Y_POSITION + (index - 1) * Y_POSITION_STEP,
			instance = indicator,
		})
	end

	self:update()
end

function module:update()
	local rootPart = getRootPart(self.character)
	if not rootPart then
		return
	end

	local rootPosition = rootPart.Position
	for _, indicator in self.indicators do
		indicator.instance.CFrame = CFrame.new(rootPosition.X, indicator.yPosition, rootPosition.Z)
	end
end

function module:Destroy()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		self.heartbeatConnection = nil
	end

	self:clear()
end

return module
