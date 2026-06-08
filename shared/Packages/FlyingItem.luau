--!strict
-- FlyingItem.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Bezier = require(ReplicatedStorage.Packages.Bezier)
local Spring = require(ReplicatedStorage.Packages.Spring)

local CurrencyAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("CurrencyAssets")

-- Type definitions
export type FlyingItem = {
	part: BasePart,
	itemName: string,
	amount: number,
	groupId: string,
	origin: Vector3,
	target: BasePart,
	perpVector: Vector3,
	bezierCurve: Bezier.Bezier,
	spawnDelay: number,
	totalLifetime: number,
	lifetimeRemaining: number,
	spring: any,
	canDelete: boolean
}

-- Class definition
local FlyingItem = {}
FlyingItem.__index = FlyingItem

function FlyingItem.new(
	itemName: string,
	amount: number,
	groupId: string,
	color: Color3?,
	origin: Vector3,
	target: BasePart,
	perpVector: Vector3?,
	spawnDelay: number,
	totalLifetime: number
): FlyingItem
	local template = CurrencyAssets:WaitForChild("MoneyPickup") :: BasePart
	local templateClone: BasePart = template:Clone()
	
	templateClone.CFrame = CFrame.new(origin)
	templateClone.Parent = workspace.CurrentCamera
	
	Debris:AddItem(templateClone, 2* (spawnDelay + totalLifetime)) -- mergency in case the actual delete method shits the bed.
	local self: FlyingItem = {
		part = templateClone,
		itemName = itemName,
		amount = amount,
		groupId = groupId,
		origin = origin,
		target = target,
		perpVector = perpVector or Vector3.zero,
		bezierCurve = Bezier.new(
			{origin, target.CFrame.Position - origin + Vector3.new(0, 10, 0), target.CFrame.Position},
			workspace.CurrentCamera,
			10
		),	
		spawnDelay = spawnDelay,
		totalLifetime = totalLifetime,
		lifetimeRemaining = totalLifetime,
		spring = Spring.new(origin, Vector3.zero, origin, 15, 0.8),
		canDelete = false
	}
	

	setmetatable(self :: any, FlyingItem)
	return self
end
local function easeOutIn(t: number): number
	if t < 0.5 then
		-- Ease out: fast, then slowing
		local x = 1 - 2 * t
		return 0.5 * (1 - x * x)
	else
		-- Ease in: slow, then speeding up
		local x = 2 * t - 1
		return 0.5 + 0.5 * x * x
	end
end

function FlyingItem:Update(deltaTime: number)
	local self = self :: FlyingItem
	self.spawnDelay = self.spawnDelay - deltaTime
	if self.spawnDelay <= 0 then
		self.lifetimeRemaining = math.max(0, self.lifetimeRemaining - deltaTime)
		local bezierPosition = 1 - (self.lifetimeRemaining / self.totalLifetime)
		local midPoint = (self.target.CFrame.Position + self.origin) * 0.5 

		self.bezierCurve:updateControlPoints(
			self.origin, 
			midPoint + self.perpVector * 15 ,
			self.target.CFrame.Position
		)
		--self.bezierCurve:toggleVisualization(true)
		self.spring.target = self.bezierCurve:positionAt(easeOutIn(bezierPosition))
		self.spring:update(deltaTime)
		self.part.CFrame = CFrame.new(self.spring.p, self.target.CFrame.Position)
		local distanceToTarget = (self.target.CFrame.Position - self.part.CFrame.Position).Magnitude
		
		if self.lifetimeRemaining <= 0 then
			self.spring.angularFrequency = 30
			self.spring.dampingRatio = 0.95
		end
		if (self.lifetimeRemaining <= 0 and distanceToTarget <= 1.0) or distanceToTarget == math.huge then
			self.canDelete = true
		end
	end
end
function FlyingItem:Destroy()
	local self = self :: FlyingItem
	Debris:AddItem(self.part, 0)
	self.bezierCurve:Destroy()
end

return FlyingItem
