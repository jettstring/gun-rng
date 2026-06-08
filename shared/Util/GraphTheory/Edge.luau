local module = {}
local module_mt = {__index = module}
local Debris = game:GetService("Debris")
local Node = require(script.Parent.Node)


export type Type = {
	a: Node.Type,
	b: Node.Type,
	part: Beam?
}

local IN_ATTACHMENT_NAME = "InAttachment"
local OUT_ATTACHMENT_NAME = "OutAttachment"
local UNREACHABLE_EDGE_COLOR = Color3.fromRGB(255, 140, 0)

local function getOrCreateAttachment(parent: BasePart, name: string): Attachment
	local existingAttachment = parent:FindFirstChild(name)
	if existingAttachment and existingAttachment:IsA("Attachment") then
		return existingAttachment
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = parent
	return attachment
end

function module.new(
	a: Node.Type,
	b: Node.Type,
	_parent: Instance,
	color: Color3?
)
	local self = {
		a = a,
		b = b,
	}

	if not a.part or not b.part then
		warn("GraphMaker: Edge cannot render because a node part is missing.")
		return setmetatable(self, module_mt);
	end

	local beam = Instance.new("Beam")
	beam.Name = "Edge"
	beam.Parent = a.part
	beam.Attachment0 = getOrCreateAttachment(a.part, OUT_ATTACHMENT_NAME)
	beam.Attachment1 = getOrCreateAttachment(b.part, IN_ATTACHMENT_NAME)
	beam.Width0 = 1
	beam.Width1 = 0.2
	beam.FaceCamera = true
	if a.flowReachable == false or b.flowReachable == false then
		beam.Color = ColorSequence.new(UNREACHABLE_EDGE_COLOR)
	elseif color then
		beam.Color = ColorSequence.new(color)
	else
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, a.color or Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, b.color or Color3.new(1, 1, 1)),
		})
	end
	beam:AddTag("Edge")
	beam:SetAttribute("a", a.id)
	beam:SetAttribute("b", b.id)

	self.part = beam
	return setmetatable(self, module_mt);
end

function module:cleanup()
	-- Add all parts, scripts, etc of this to Debris service. 
	-- Delete everything
	if self.part then
		Debris:AddItem(self.part, 0)
	end
end




return module
