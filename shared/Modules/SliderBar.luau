local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local SlideBar = {}
SlideBar.__index = SlideBar

type Config<T> = {
	values: {T}?,
	min: number?,
	max: number?,
	step: number?,
}

--------------------------------------------------
-- HELPERS --
--------------------------------------------------

local function resolveValues<T>(config: Config<T>): { any }
	if config.values then
		return config.values
	end
	local min = assert(config.min, "SlideBar: numeric config needs `min`")
	local max = assert(config.max, "SlideBar: numeric config needs `max`")
	local step = config.step or 1
	local values = {}
	for i = min, max, step do
		table.insert(values, i) 
	end
	return values
end

-- index (1..N) -> fraction along the track (0..1)
local function indexToFraction(self, index: number): number
	local n = #self.values
	if n <= 1 then
		return 0
	end
	return (index - 1) / (n - 1)
end

-- fraction (0..1) -> nearest valid index (1..N)
local function fractionToIndex(self, fraction: number): number
	local n = #self.values
	if n <= 1 then
		return 1
	end
	local raw = math.round(fraction * (n - 1)) + 1
	return math.clamp(raw, 1, n)
end

local function rebuildNotches(self)
	for _, notch in self.notches do
		notch:Destroy()
	end
	self.notches = {}

	local template = self.notchTemplate
	if not template then
		return
	end

	for i = 1, #self.values do
		local notch = template:Clone()
		notch.Position = UDim2.fromScale(indexToFraction(self, i), 0.5)
		notch.Visible = true
		notch.Parent = self.trackFrame
		table.insert(self.notches, notch)
	end
end

local function updateBoundLabels(self)
	if self.minLabel then
		self.minLabel.Text = tostring(self.values[1])
	end
	if self.maxLabel then
		self.maxLabel.Text = tostring(self.values[#self.values])
	end
end

local function render(self)
	local fraction = indexToFraction(self, self.index)
	self.handleButton.Position = UDim2.fromScale(fraction, self.handleButton.Position.Y.Scale)
	if self.valueLabel then
		self.valueLabel.Text = tostring(self.values[self.index])
	end
end

local function setIndex(self, index: number)
	local old = self.index
	self.index = index
	render(self)
	if old ~= index then
		self.changedSignal:Fire(self.values[index], self.values[old])
	end
end

local function snapToNearest(self)
	local trackX = self.trackFrame.AbsolutePosition.X
	local trackW = self.trackFrame.AbsoluteSize.X
	if trackW <= 0 then
		return
	end
	local handleCenter = self.handleButton.AbsolutePosition.X + self.handleButton.AbsoluteSize.X / 2
	local fraction = math.clamp((handleCenter - trackX) / trackW, 0, 1)
	setIndex(self, fractionToIndex(self, fraction))
end

--------------------------------------------------
-- MAIN --
--------------------------------------------------

function SlideBar.new<T>(containerFrame: Frame, config: Config<T>)
	local self = setmetatable({}, SlideBar)
	
	self._connections = {}
	self.changedSignal = Signal.new()
	self.notches = {}
	
	-- resolve starting values
	self.values = resolveValues(config)
	self.index = 1
	
	-- required UI components
	self.trackFrame = assert(containerFrame:WaitForChild("Track"), "No trackFrame")
	self.handleButton = assert(self.trackFrame:WaitForChild("Handle"), "No Handle button")
	self.uiDragDetector = assert(self.handleButton:WaitForChild("UIDragDetector"), "UIDragDetector not found")
	-- optional 
	self.minLabel = containerFrame:FindFirstChild("MinLabel")
	self.maxLabel = containerFrame:FindFirstChild("MaxLabel")
	self.valueLabel = containerFrame:FindFirstChild("ValueLabel")
	self.notchTemplate = self.trackFrame:FindFirstChild("NotchTemplate")
	
	-- drag connections
	table.insert(self._connections, self.uiDragDetector.DragContinue:Connect(function()
		snapToNearest(self)
	end))
	table.insert(self._connections, self.uiDragDetector.DragEnd:Connect(function()
		snapToNearest(self)
	end))

	rebuildNotches(self)
	updateBoundLabels(self)
	render(self)
	
	return self
end

function SlideBar:UpdateConfig<T>(config: Config<T>) 
	local oldValue = self.values[self.index]

	self.values = resolveValues(config)

	-- keep the same selected value if it still exists, else clamp the index
	local keep = table.find(self.values, oldValue)
	self.index = keep or math.clamp(self.index, 1, #self.values)

	rebuildNotches(self)
	updateBoundLabels(self)
	render(self)

	if self.values[self.index] ~= oldValue then
		self.changedSignal:Fire(self.values[self.index], oldValue)
	end
end

function SlideBar:GetValue<T>(): T
	return self.values[self.index]
end

function SlideBar:SetValue<T>(value: T)
	local index = table.find(self.values, value)
	if index then
		setIndex(self, index)
	end
end

function SlideBar:SetEnabled(enabled: boolean)
	self.uiDragDetector.Enabled = enabled
end

function SlideBar:Destroy()
	self.changedSignal:Destroy()
	
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections) 
end


export type SlideBarObject<T> = typeof(setmetatable({} :: {
	changedSignal: Signal,
	values: {T},
	trackFrame: Frame,
	handleButton: TextButton,
	minLabel: TextLabel?,
	maxLabel: TextLabel?,
	valueLabel: TextLabel?,
	notchTemplate: Frame?,
}, SlideBar))
	
return SlideBar
