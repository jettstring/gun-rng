local module = {}
local module_mt = {__index = module}

local spring = require(script.Parent:WaitForChild("Spring"))

local function setGuiEnabled(gui: Instance?, enabled: boolean)
	if not gui then
		return
	end

	if gui:IsA("LayerCollector") then
		gui.Enabled = enabled
	elseif gui:IsA("GuiObject") then
		gui.Visible = enabled
	end
end

function module.new(playerGui: PlayerGui)
	local self = {}
	self.crosshairGUI = playerGui:FindFirstChild("CrosshairGui")
	self.hitmarkerGUIContainer = playerGui:FindFirstChild("HitmarkerContainer")
	self.enabled = false
	self.positionSpring = spring.new(Vector2.new(), Vector2.new(), Vector2.new(), 1000, 15)

	setGuiEnabled(self.crosshairGUI, false)
	setGuiEnabled(self.hitmarkerGUIContainer, false)

	return setmetatable(self, module_mt)
end

function module:setEnabled(enabled: boolean)
	self.enabled = enabled
	setGuiEnabled(self.crosshairGUI, enabled)
	setGuiEnabled(self.hitmarkerGUIContainer, enabled)
end

function module:positionCrosshair(worldPoint: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local vector = camera:WorldToViewportPoint(worldPoint)
	self.positionSpring.target = Vector2.new(vector.X, vector.Y)
end

function module:update(step: number)
	if not self.enabled then
		return
	end

	self.positionSpring:update(step)

	if self.crosshairGUI then
		local actualCrosshair = self.crosshairGUI:FindFirstChild("ActualCrosshair")
		if actualCrosshair and actualCrosshair:IsA("GuiObject") then
			actualCrosshair.Visible = true
			actualCrosshair.Position = UDim2.fromOffset(self.positionSpring.p.X, self.positionSpring.p.Y)
		end

		local stableCrosshair = self.crosshairGUI:FindFirstChild("StableCrosshair")
		if stableCrosshair and stableCrosshair:IsA("GuiObject") then
			stableCrosshair.Visible = true
		end

		local meleeCrosshair = self.crosshairGUI:FindFirstChild("MeleeCrosshair")
		if meleeCrosshair and meleeCrosshair:IsA("GuiObject") then
			meleeCrosshair.Visible = false
		end
	end

	if self.hitmarkerGUIContainer then
		local hitmarker = self.hitmarkerGUIContainer:FindFirstChild("Hitmarker")
		if hitmarker and hitmarker:IsA("GuiObject") then
			hitmarker.Position = UDim2.fromOffset(self.positionSpring.p.X, self.positionSpring.p.Y)
		end
	end
end

return module
