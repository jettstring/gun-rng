--!strict

-- Lua Binary Min-Heap implementation

--[[

local heap = Heap.new()

heap:Add(object, value) -> void
heap:Remove(object) -> object, value
heap:Get(object: any) -> value

heap:Pop() -> object, value
heap:Peek() -> object, value

heap:PopUnder(maxValue) -> object, value
heap:PopAllUnder(maxValue) -> { object... }
heap:PeekUnder(maxValue) -> object, value

--]]

type HeapIndex = number
type HeapValue = number
type HeapObject = any

local Heap = {}
Heap.__index = Heap

function Heap.new()
	local self = {
		Size = 0,
		Array = {} :: { [HeapIndex]: HeapObject },
		IndexMap = {} :: { [HeapObject]: HeapIndex },
		ValueMap = {} :: { [HeapObject]: HeapValue }
	}

	setmetatable(self, Heap)
	return self
end

--

function SiftDown(heap: Heap, index: HeapIndex, obj: HeapObject, value: HeapValue)
	while index > 1 do
		local parIndex = (index - index % 2) / 2
		local parObj = heap.Array[parIndex]
		local parValue = heap.ValueMap[parObj]

		if parValue <= value then
			break
		end

		heap.Array[index] = parObj
		heap.IndexMap[parObj] = index

		index = parIndex
	end

	heap.Array[index] = obj
	heap.IndexMap[obj] = index
	heap.ValueMap[obj] = value
end

function SiftUp(heap: Heap, index: HeapIndex, obj: HeapObject, value: HeapValue)
	local leafIndex = index * 2

	while leafIndex < heap.Size do
		local leftObj = heap.Array[leafIndex]
		local rightObj = heap.Array[leafIndex + 1]

		local leftVal = heap.ValueMap[leftObj]
		local rightVal = heap.ValueMap[rightObj]

		if leftVal < rightVal then
			if value > leftVal then
				heap.Array[index] = leftObj
				heap.IndexMap[leftObj] = index

				index = leafIndex
			else
				break
			end
		else
			if value > rightVal then
				heap.Array[index] = rightObj
				heap.IndexMap[rightObj] = index

				index = leafIndex + 1
			else
				break
			end
		end

		leafIndex = index * 2
	end

	if leafIndex == heap.Size then -- only has a single child
		local leafObj = heap.Array[leafIndex]
		local leafVal = heap.ValueMap[leafObj]

		if leafVal < value then
			heap.Array[index] = leafObj
			heap.IndexMap[leafObj] = index

			index = leafIndex
		end
	end

	--

	heap.Array[index] = obj
	heap.IndexMap[obj] = index
	heap.ValueMap[obj] = value
end

function HeapPop(heap: Heap, index: HeapIndex): (HeapObject, HeapValue)
	local removedObj = heap.Array[index]
	local removedVal = heap.ValueMap[removedObj]

	heap.IndexMap[removedObj] = nil
	heap.ValueMap[removedObj] = nil

	--

	local leafIndex = index * 2

	while leafIndex <= heap.Size do
		local leftObj = heap.Array[leafIndex]
		local rightObj = heap.Array[leafIndex + 1]

		if not rightObj or heap.ValueMap[leftObj] < heap.ValueMap[rightObj] then
			heap.Array[index] = leftObj
			heap.IndexMap[leftObj] = index

			index = leafIndex
		else
			heap.Array[index] = rightObj
			heap.IndexMap[rightObj] = index

			index = leafIndex + 1
		end

		leafIndex = index * 2
	end

	--

	if index < heap.Size then
		local finalObj = heap.Array[heap.Size]
		local finalValue = heap.ValueMap[finalObj]

		heap.Array[heap.Size] = nil
		heap.Size -= 1

		SiftDown(heap, index, finalObj, finalValue)
	else
		heap.Array[heap.Size] = nil
		heap.Size -= 1
	end

	--

	return removedObj, removedVal
end

--

function Heap:Get(obj: HeapObject)
	return self.ValueMap[obj]
end

function Heap:Add(obj: HeapObject, value: HeapValue)
	assert(typeof(value) == "number")

	local index = self.IndexMap[obj]

	if index then
		-- Move instead of adding
		local oldValue = self.ValueMap[obj]

		if value < oldValue then
			SiftDown(self, index, obj, value)
		elseif value > oldValue then
			SiftUp(self, index, obj, value)
		end
	else
		self.Size += 1
		SiftDown(self, self.Size, obj, value)
	end
end

function Heap:Remove(obj: HeapObject): (HeapObject?, HeapValue?)
	local index = self.IndexMap[obj]

	if not index then
		return nil
	end

	return HeapPop(self, index)
end

function Heap:Pop(): (HeapObject?, HeapValue?)
	if self.Size == 0 then
		return nil
	end

	return HeapPop(self, 1)
end

function Heap:PopUnder(value: HeapValue): (HeapObject?, HeapValue?)
	if self.Size == 0 then
		return nil
	end

	local firstObj = self.Array[1]
	local firstVal = self.ValueMap[firstObj]

	if firstVal > value then
		return nil
	end

	return HeapPop(self, 1)
end

function Heap:Peek(): (HeapObject?, HeapValue?)
	if self.Size == 0 then
		return nil
	end

	local firstObj = self.Array[1]
	local firstVal = self.ValueMap[firstObj]

	return firstObj, firstVal
end

function Heap:PeekUnder(value: HeapValue):  (HeapObject?, HeapValue?)
	if self.Size == 0 then
		return nil
	end

	local firstObj = self.Array[1]
	local firstVal = self.ValueMap[firstObj]

	if firstVal > value then
		return nil
	end

	return firstObj, firstVal
end

--

function Heap:PopAllUnder(value: HeapValue): { HeapObject }
	local result = {}

	while true do
		local obj = self:PopUnder(value)

		if obj then
			result[#result + 1] = obj
		else
			break
		end
	end

	return result
end

--

type Heap = typeof(Heap.new())

--

return Heap