local module = {}
local module_mt = {__index = module}
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Node = require(script.Parent.Node)
local Heap = require(script.Parent.Heap)

local function newHeap()
	local ok, heap = pcall(function()
		return Heap.new()
	end)

	if not ok or typeof(heap) ~= "table" or typeof(heap.Add) ~= "function" or typeof(heap.Pop) ~= "function" then
		error("GraphMaker: script.Parent.Heap is not the binary heap module. Make sure the Heap ModuleScript contains Heap.luau.", 2)
	end

	return heap
end
export type Type = {
	id: string,
	container: Folder,
	nodes: {Node.Type},
	seed: number,
	nodeCount: number,
	edgeCount: number
}

export type LoadOptions = {
	render: boolean?,
}

export type Path = { 
	waypoints: {Node.Type},
	startNode: Node.Type,
	endNode: Node.Type,
	cost: number,
	angleSum: number
}

function module.new(
	container: Folder?
)
	local self = {}

	if container then
		-- Load the graph
		if not container:HasTag("Graph") then
			warn("GraphMaker: Unable to load Graph. The selected Folder does not have a Graph tag.")
			return
		end

		self.id = container:GetAttribute("id")
		self.container = container
		self.nodes = {}
		self.seed = 0
		self.nodeCount = 0
		self.edgeCount = 0
		print("GraphMaker: Folder exists. Please run module:load() to load the existing graph.")
	else
		-- Make a new graph
		print("GraphMaker: Making new Graph.")
		self.container = Instance.new("Folder")
		self.container.Parent = workspace
		self.container:AddTag("Graph")
		self.container.Name = "Graph"

		self.id = HttpService:GenerateGUID(false)		
		self.container:SetAttribute("id", self.id)

		self.nodes = {}

		self.seed = 0
		self.container:SetAttribute("seed", self.seed)

		self.nodeCount = 0
		self.container:SetAttribute("nodeCount", self.nodeCount)

		self.edgeCount = 0
		self.container:SetAttribute("edgeCount", self.edgeCount)
	end

	return setmetatable(self, module_mt);
end

function module:load(folder: Folder, options: LoadOptions?)
	if not folder:HasTag("Graph") then
		warn("GraphMaker: Unable to load Graph. The selected Folder does not have a Graph tag.")
		return
	end
	local shouldRender = true
	if options and options.render == false then
		shouldRender = false
	end

	self.nodes = {} -- reset the graph
	local edgeTable = {} -- Structure [nodeID: string] = {otherNodeID_A: string, ..., otherNodeID_Z: string}
	local edgeCount = 0
	local nodeCount = 0

	self.id = folder:GetAttribute("id")
	self.seed = folder:GetAttribute("seed")

	self.container = folder

	-- Get all the nodes. Add to the Data Structure. Record all edges.
	local nodeParts = folder:GetChildren()
	for i, np in nodeParts do
		if np:HasTag("Node") and np:IsA("Part") then
			nodeCount += 1
			local id = np:GetAttribute("id")
			local node = Node.new(np.Position, np.Color, np.Size, self.container, id) 
			local role = np:GetAttribute("role")
			if typeof(role) == "string" then
				node.role = role
			end
			local flowDistance = np:GetAttribute("flowDistance")
			if typeof(flowDistance) == "number" then
				node.flowDistance = flowDistance
			end
			local flowReachable = np:GetAttribute("flowReachable")
			if typeof(flowReachable) == "boolean" then
				node.flowReachable = flowReachable
			end
			if not shouldRender then
				node.part = np
			end
			table.insert(self.nodes, node)
			if edgeTable[id] == nil then
				edgeTable[id] = {}
			end

			-- Add the edges of this node to the edge table
			for _, edgePart in np:GetChildren() do
				if edgePart:HasTag("Edge") and (edgePart:IsA("Beam") or edgePart:IsA("BasePart")) then
					local aID = edgePart:GetAttribute("a")
					local bID = edgePart:GetAttribute("b")

					if aID == id and typeof(bID) == "string" then
						edgeCount += 1
						table.insert(edgeTable[id], bID)
					end
				end
			end
		end
	end

	-- After adding nodes to DS and recording all edges, add edges to DS.
	for k, otherNodeIDs in edgeTable do
		-- Find node in table
		local originNode = nil
		for _, n in self.nodes do
			if n.id == k then
				originNode = n
			end
		end
		-- Add all corresponding edges
		for _, id in otherNodeIDs do
			for _, n in self.nodes do
				if n.id == id then
					originNode:addConnection(n)
				end
			end
		end
	end


	self.nodeCount = nodeCount
	self.edgeCount = edgeCount
	self:updateAttributes()

	if shouldRender then
		self:render()
	end

	return self.id
end

function module:updateAttributes()
	self.container:SetAttribute("seed", self.seed)
	self.container:SetAttribute("nodeCount", self.nodeCount)
	self.container:SetAttribute("edgeCount", self.edgeCount)
end
function module:updateSeed()
	self.seed += 1
	self.container:SetAttribute("seed", self.seed)
end

function module:updateNodePositions()
	for i, n in self.nodes do
		n:update()
	end
end

function module:render()
	self:updateNodePositions()
	for i, part in self.container:GetChildren() do
		part:Destroy()
	end
	for i, n in self.nodes do
		n.part = nil
		n.lines = {}
	end
	self:renderNodes()
	self:renderLines()
end

function module:renderLines()
	for i, n in self.nodes do
		n:renderLines()
	end
end

function module:hideLines()
	for i, n in self.nodes do
		n:hideLines()
	end
end

function module:renderNodes()
	for i, n in self.nodes do
		n:render()
	end
end

function module:findNodeWithRole(role: string)
	for _, node in self.nodes do
		if node.role == role then
			return node
		end
	end

	return nil
end

function module:calculateFlowDistancesToTarget()
	local targetNode = self:findNodeWithRole("Target")
	if not targetNode then
		return nil
	end

	local reverseConnections = {}
	self:updateNodePositions()
	for _, node in self.nodes do
		reverseConnections[node] = {}
	end

	for _, originNode in self.nodes do
		for _, target in originNode.connections do
			if reverseConnections[target] then
				table.insert(reverseConnections[target], originNode)
			end
		end
	end

	local distances = {}
	local open = newHeap()
	distances[targetNode] = 0
	open:Add(targetNode, 0)

	while open.Size > 0 do
		local currentNode, currentDistance = open:Pop()
		if not currentNode then
			break
		end

		for _, predecessor in reverseConnections[currentNode] do
			local edgeDistance = (predecessor.Position - currentNode.Position).Magnitude
			local nextDistance = currentDistance + edgeDistance
			local previousDistance = distances[predecessor]

			if previousDistance == nil or nextDistance < previousDistance then
				distances[predecessor] = nextDistance
				open:Add(predecessor, nextDistance)
			end
		end
	end

	local maxDistance = 0
	local reachableCount = 0
	local unreachableCount = 0
	for _, node in self.nodes do
		local flowDistance = distances[node]
		if flowDistance ~= nil then
			node.flowDistance = flowDistance
			node.flowReachable = true
			reachableCount += 1
			if flowDistance > maxDistance then
				maxDistance = flowDistance
			end
		else
			node.flowDistance = nil
			node.flowReachable = false
			unreachableCount += 1
		end
	end

	return {
		targetNode = targetNode,
		maxDistance = maxDistance,
		reachableCount = reachableCount,
		unreachableCount = unreachableCount,
	}
end



function module:addNode(node: Node.Type)
	for i, n in self.nodes do
		if n.id == node.id then
			warn("Node cannot be added to graph ", self.id, " because it already exists.")
			return n
		end
	end
	table.insert(self.nodes, node)
end

function module:findNode(id: string)
	for i, n in self.nodes do
		if n.id == id then
			return n
		end
	end
	return nil
end

function module:findClosestNode(position: Vector3)

	self:updateNodePositions()
	local closestNode = nil
	local closestMagnitude = 10000000
	for i, n in self.nodes do
		local currentMagnitude = (n.Position - position).Magnitude
		if currentMagnitude <= closestMagnitude  then
			closestNode = n
			closestMagnitude = currentMagnitude
		end
	end
	return closestNode
end

function module:removeNodesFromSelection(selectedObjects: {Instance})
	local nodeIdsToRemove = {}
	if #selectedObjects > 0 then
		for i, nodePart in selectedObjects do
			if nodePart:HasTag("Node") then
				local id: string = nodePart:GetAttribute("id")
				local originalNode = self:findNode(id)
				if originalNode then
					originalNode:remove()
					table.insert(nodeIdsToRemove, originalNode.id)
				else
					warn("GraphMaker: The original node cannot be found. Removing part.")
					Debris:AddItem(nodePart, 0)
				end
			end
		end
	end
	for _, id in nodeIdsToRemove do
		for i, node in self.nodes do
			if node.id == id then
				table.remove(self.nodes, i)
			end
		end
	end
	self:render()
end

function module:newRowFromSelection(selectedObjects: {Instance})
	self:updateNodePositions()
	local selectedNodes = {}
	if #selectedObjects > 0 then
		for i, nodePart in selectedObjects do
			if nodePart:HasTag("Node") then
				local originalNode = self:findNode(nodePart:GetAttribute("id"))
				if originalNode then
					table.insert(selectedNodes, originalNode)
				else
					warn("GraphMaker: The original node cannot be found.")
				end
			end
		end
	end
	local newSelections = {}
	local newNodes = {}

	local prevNewNode = nil
	for i, n in selectedNodes do
		-- Make a corresponding node
		local clone = Node.new(n.Position, n.Color, n.Size, self.container)
		table.insert(newNodes, clone)
		--clone:addConnection(n)
		--n:addConnection(clone)

		-- Previous new node			
		if prevNewNode then
			prevNewNode:addConnection(clone)
			clone:addConnection(prevNewNode)
			self.edgeCount += 2
		end
		prevNewNode = clone


		-- Original Node
		if selectedNodes[i] then
			selectedNodes[i]:addConnection(clone)
			clone:addConnection(selectedNodes[i])
			self.edgeCount += 2
		end
		-- Original Node Left
		if i - 1 >= 1 then
			print("Index exists i - 1")
			if selectedNodes[i - 1] then
				selectedNodes[i - 1]:addConnection(clone)
				clone:addConnection(selectedNodes[i - 1])
				self.edgeCount += 2
			end
		end

		-- Original Node Right
		if i + 1 <= #selectedNodes then
			print("Index exists i + 1")

			if selectedNodes[i + 1] then
				selectedNodes[i + 1]:addConnection(clone)
				clone:addConnection(selectedNodes[i + 1])
				self.edgeCount += 2
			end
		end
		clone:render()
		table.insert(newSelections, clone.part)
		self.nodeCount += 1
		table.insert(self.nodes, clone)
	end
	self:updateAttributes()
	return newSelections
end




function module:equals(node: Type)
	return self.id == node.id
end

function module:remove(id: string)
	for i, node in self.nodes do
		if node.id == id then
			table.remove(self.nodes, i)
		end
	end
end



function module:path(a: string, b: string): Path?

	self:updateNodePositions()
	local fromNode: Node.Type = self:findNode(a)
	local toNode: Node.Type = self:findNode(b)

	if not fromNode or not toNode then
		warn("GraphMaker: Cannot find nodes ", fromNode, " or ", toNode)
		return nil
	end
	local gCosts: {[Node.Type]: number} = {}
	local hCosts: {[Node.Type]: number} = {}
	local parents = {}

	gCosts[fromNode] = 0
	hCosts[fromNode] = (toNode.Position - fromNode.Position).Magnitude

	local function retracePath(): Path
		local path = {}

		local target: Node.Type = toNode
		local angleSum = 0

		while target ~= fromNode do
			path[#path + 1] = target

			local parent = parents[target]
			local grandParent = parent and parents[parent]

			if parent and grandParent then
				local dir0 = (parent.Position - grandParent.Position).Unit
				local dir1 = (target.Position - parent.Position).Unit
				angleSum += math.acos(dir0:Dot(dir1))
			end

			target = parent
		end

		path[#path + 1] = fromNode

		local result: Path = {
			waypoints = path,
			startNode = fromNode,
			endNode = toNode,
			cost = gCosts[toNode],
			angleSum = angleSum
		}
		return result

	end

	local function getFCost(node: Node.Type): number
		local gCostInfluence = 1
		return (gCosts[node] * gCostInfluence) + hCosts[node] 
	end

	if fromNode == toNode then
		return retracePath()
	end

	local Open = newHeap()
	local Closed = {}

	Open:Add(fromNode, getFCost(fromNode))

	while Open.Size > 0 do
		local currentNode = Open:Pop()

		if currentNode == toNode then
			return retracePath()
		end

		Closed[currentNode] = true
		local currentCost = gCosts[currentNode]

		for _,adjacentNode in currentNode.connections do			
			if Closed[adjacentNode]then
				continue
			end

			local costToNeighbor = currentCost + (adjacentNode.Position - currentNode.Position).Magnitude 
			local previousCost = gCosts[adjacentNode]

			if not previousCost or costToNeighbor < previousCost then
				gCosts[adjacentNode] = costToNeighbor
				parents[adjacentNode] = currentNode

				if not previousCost then
					hCosts[adjacentNode] = (toNode.Position - adjacentNode.Position).Magnitude 
				end 

				Open:Add(adjacentNode, getFCost(adjacentNode))
			end
		end
	end
	return nil 
end




return module
