local module = {}
local module_mt = { __index = module }

local EnemyTargeting = require(script.Parent:WaitForChild("EnemyTargeting"))

type TargetResult = EnemyTargeting.TargetResult

local CROSSHAIR_SCREEN_GUI_NAME = "Crosshair"
local EXPLICIT_CROSSHAIR_NAME = "ExplicitCrosshair"
local TARGET_HORIZONTAL_CENTER_BIAS_STUDS = 35

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

local function getViewportPointIfVisible(camera: Camera, worldPoint: Vector3): Vector3?
	local viewportPoint = camera:WorldToViewportPoint(worldPoint)
	if viewportPoint.Z <= 0 then
		return nil
	end

	local viewportSize = camera.ViewportSize
	if viewportPoint.X < 0 or viewportPoint.X > viewportSize.X then
		return nil
	end
	if viewportPoint.Y < 0 or viewportPoint.Y > viewportSize.Y then
		return nil
	end

	return viewportPoint
end

local function getHorizontalCenterBiasScore(camera: Camera, worldPoint: Vector3): number
	local viewportPoint = getViewportPointIfVisible(camera, worldPoint)
	if not viewportPoint then
		-- Off-screen targets are still selectable; give them the maximum bias so
		-- on-screen targets are preferred but they remain rankable by distance.
		return TARGET_HORIZONTAL_CENTER_BIAS_STUDS
	end

	local viewportSize = camera.ViewportSize
	local halfWidth = math.max(viewportSize.X * 0.5, 1)
	local horizontalOffset = math.abs(viewportPoint.X - halfWidth) / halfWidth
	return math.clamp(horizontalOffset, 0, 1) * TARGET_HORIZONTAL_CENTER_BIAS_STUDS
end

function module.new(player: Player, character: Model)
	local playerGui = player:WaitForChild("PlayerGui")
	local crosshair = playerGui:WaitForChild(CROSSHAIR_SCREEN_GUI_NAME):WaitForChild(EXPLICIT_CROSSHAIR_NAME) :: ImageLabel
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Visible = false

	local ownerTag = EnemyTargeting.getOwnerTag(player)
	local self = {
		player = player,
		character = character,
		ownerTag = ownerTag,
		cache = EnemyTargeting.acquireCache(ownerTag),
		enabled = false,
		crosshair = crosshair,
		currentTarget = nil :: Model?,
		currentAimPoint = nil :: Vector3?,
		visibleAimPoint = nil :: Vector3?,
	}

	return setmetatable(self, module_mt)
end

function module:hide()
	self.visibleAimPoint = nil
	self.crosshair.Visible = false
end

function module:setEnabled(enabled: boolean)
	self.enabled = enabled == true
	if not self.enabled then
		self.currentTarget = nil
		self.currentAimPoint = nil
		self:hide()
	end
end

function module:getOriginPosition(): Vector3?
	local rootPart = getRootPart(self.character)
	if rootPart then
		return rootPart.Position
	end

	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end

	return nil
end

function module:update(_step: number)
	self.visibleAimPoint = nil

	local crosshair = self.crosshair
	if not self.enabled then
		crosshair.Visible = false
		return
	end

	local originPosition = self:getOriginPosition()
	local camera = workspace.CurrentCamera
	if not originPosition or not camera then
		crosshair.Visible = false
		return
	end

	local result = EnemyTargeting.selectTarget(self.cache, {
		ownerTag = self.ownerTag,
		originPosition = originPosition,
		currentTarget = nil,
		getAimPart = function(enemyModel: Model): (BasePart?, boolean)
			local aimPart = EnemyTargeting.getPrimaryPartFirstAimPart(enemyModel)
			if not aimPart then
				return nil, false
			end

			return aimPart, false
		end,
		getTargetScore = function(targetResult: TargetResult): number
			local characterDistance = math.sqrt(targetResult.distanceSquared)
			return characterDistance + getHorizontalCenterBiasScore(camera, targetResult.aimPoint)
		end,
	})

	self.currentTarget = if result then result.enemy else nil
	self.currentAimPoint = if result then result.aimPoint else nil

	if not result then
		crosshair.Visible = false
		return
	end

	-- The selected target is shootable even when it is off-screen; only the
	-- crosshair visual is hidden when there is no on-screen point to draw it at.
	self.visibleAimPoint = result.aimPoint

	local viewportPoint = getViewportPointIfVisible(camera, result.aimPoint)
	if not viewportPoint then
		crosshair.Visible = false
		return
	end

	crosshair.Position = UDim2.fromOffset(viewportPoint.X, viewportPoint.Y)
	crosshair.Visible = true
end

-- Pins the reticle to a fixed screen position. Manual aim is "aim where the
-- screen points", so the reticle belongs at a fixed point (viewport center on
-- mobile, the cursor on PC) rather than reprojected from a world hit, which
-- swims by a frame whenever the camera moves.
function module:showAtViewportPoint(viewportPoint: Vector2)
	self.visibleAimPoint = nil
	local crosshair = self.crosshair
	crosshair.Position = UDim2.fromOffset(viewportPoint.X, viewportPoint.Y)
	crosshair.Visible = true
end

function module:hasTarget(): boolean
	return self.enabled and self.visibleAimPoint ~= nil
end

function module:getAimPoint(): Vector3?
	if not self:hasTarget() then
		return nil
	end

	return self.visibleAimPoint
end

function module:Destroy()
	self:setEnabled(false)
	EnemyTargeting.releaseCache(self.cache)
	self.cache = nil
	self.crosshair = nil
end

return module
