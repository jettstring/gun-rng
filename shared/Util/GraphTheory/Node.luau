local module = {}
local module_mt = {__index = module}
local HttpService = game:GetService("HttpService")
export type Type = {
	id: string,
	Position: Vector3,
	connections: {Type},
	parent: Instance,
	color: Color3,
	size: any?,
	role: string?,
	flowDistance: number?,
	flowReachable: boolean?,
	lines: {Instance},
	part: Part?,
}

local DEFAULT_NODE_SIZE = Vector3.new(1.5, 1.5, 1.5)
local IN_ATTACHMENT_NAME = "InAttachment"
local OUT_ATTACHMENT_NAME = "OutAttachment"
local UNREACHABLE_EDGE_COLOR = Color3.fromRGB(255, 140, 0)

local function getRenderedSize(size: any?): Vector3
	if typeof(size) == "Vector3" then
		return size
	end

	if typeof(size) == "number" then
		return Vector3.new(size, size, size)
	end

	return DEFAULT_NODE_SIZE
end

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

local function createEdgeBeam(originNode, targetNode): Beam?
	if not originNode.part or not targetNode.part then
		return nil
	end

	local beam = Instance.new("Beam")
	beam.Name = "Edge"
	beam.Parent = originNode.part
	beam.Attachment0 = getOrCreateAttachment(originNode.part, OUT_ATTACHMENT_NAME)
	beam.Attachment1 = getOrCreateAttachment(targetNode.part, IN_ATTACHMENT_NAME)
	beam.Width0 = 2
	beam.Width1 = 0.5
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0)
	beam.FaceCamera = true
	if originNode.flowReachable == false or targetNode.flowReachable == false then
		beam.Color = ColorSequence.new(UNREACHABLE_EDGE_COLOR)
	else
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, originNode.color or Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, targetNode.color or Color3.new(1, 1, 1)),
		})
	end
	beam:AddTag("Edge")
	beam:SetAttribute("a", originNode.id)
	beam:SetAttribute("b", targetNode.id)
	return beam
end

function module.new(
	Position: Vector3,
	color: Color3?,
	size: any?,
	parent: Folder,
	id: string?
)
	local self = {}
	if id then
		self.id = id
	else
		self.id = HttpService:GenerateGUID(false)
	end
	self.Position = Position
	self.connections = {}
	self.isSurface = false
	self.parent = parent
	self.color = color
	self.size = size
	self.lines = {}
	return setmetatable(self, module_mt);
end


function module:update()
	if self.part then
		self.Position = self.part.Position
	end
end


function module:render()
	if self.part then
		self.part:Destroy()
	end
	self.lines = {}

	local node = Instance.new("Part")
	node.Name = "Node"
	node.Parent = self.parent
	node.CFrame = CFrame.new(self.Position)
	node.CanCollide = false
	node.Anchored = true
	node.CastShadow = false
	node.Material = Enum.Material.Neon
	node.Transparency = 0.3
	node.Size = getRenderedSize(self.size)
	node.Shape = Enum.PartType.Ball
	node:AddTag("Node")
	getOrCreateAttachment(node, OUT_ATTACHMENT_NAME)
	getOrCreateAttachment(node, IN_ATTACHMENT_NAME)
	node:SetAttribute("id", self.id)
	node:SetAttribute("role", self.role)
	node:SetAttribute("flowDistance", self.flowDistance)
	node:SetAttribute("flowReachable", self.flowReachable)

	if self.color then
		node.Color = self.color
	else
		node.Color = Color3.new(1, 0.0449073, 0)
	end


	self.part = node
end

function module:renderLines()
	if self.lines then
		for i, l in self.lines do
			l:Destroy()
		end
	end
	self.lines = {}

	--Draw Connections
	for i, n in self.connections do
		n:update()
		if self.part and n.part then
			local beam = createEdgeBeam(self, n)
			if beam then
				table.insert(self.lines, beam)
			end
		else
			warn("GraphMaker: Node Part is missing. Please reload the Graph.")
		end
	end
end

function module:hideLines()
	if self.lines then
		for i, l in self.lines do
			l:Destroy()
		end
	end
	self.lines = {}
end

function module:equals(node: Type)
	return self.id == node.id
end

function module:removeConnectionTo(id: string)
	for i, n in self.connections do
		if n.id == id then
			table.remove(self.connections, i)
			n:renderLines()
		end
	end
end
function module:remove()
	for i, n in self.connections do
		n:removeConnectionTo(self.id)
	end
	self:hideLines()
	if self.part then
		self.part:Destroy()
		self.part = nil
	end
end
function module:addConnection(node: Type)
	for i, n in self.connections do
		if n:equals(node) then
			return true
		end
	end
	table.insert(self.connections, node)
	return false
end

function module:cleanup()
	if self.part then
		self.part:Destroy()
		self.part = nil
	end
end




return module
