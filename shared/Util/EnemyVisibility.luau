-- Shared hide/reveal helper for per-player enemy visibility.
-- The server hides an enemy (born invisible to everyone) before parenting it
-- to Workspace; only the owning client reveals its own enemies. Originals are
-- stored in attributes so reveal reverses exactly what hide changed.

local TRANSPARENCY_ATTR = "EV_Transparency"
local ENABLED_ATTR = "EV_Enabled"

local EnemyVisibility = {}

local function hideInstance(inst: Instance)
	-- Decal covers Texture (Texture is a subclass of Decal).
	if inst:IsA("BasePart") or inst:IsA("Decal") then
		local part = inst :: any
		if part.Transparency ~= 1 then
			inst:SetAttribute(TRANSPARENCY_ATTR, part.Transparency)
			part.Transparency = 1
		end
	elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") or inst:IsA("Highlight")
		or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail")
		or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
		local emitter = inst :: any
		if emitter.Enabled then
			inst:SetAttribute(ENABLED_ATTR, true)
			emitter.Enabled = false
		end
	end
end

local function revealInstance(inst: Instance)
	local anyInst = inst :: any
	local transparency = inst:GetAttribute(TRANSPARENCY_ATTR)
	if transparency ~= nil then
		anyInst.Transparency = transparency
		inst:SetAttribute(TRANSPARENCY_ATTR, nil)
	end
	if inst:GetAttribute(ENABLED_ATTR) == true then
		anyInst.Enabled = true
		inst:SetAttribute(ENABLED_ATTR, nil)
	end
end

function EnemyVisibility.hide(model: Instance)
	hideInstance(model)
	for _, inst in model:GetDescendants() do
		hideInstance(inst)
	end
end

-- Accepts a whole model or a single descendant (e.g. from DescendantAdded).
function EnemyVisibility.reveal(instance: Instance)
	revealInstance(instance)
	for _, inst in instance:GetDescendants() do
		revealInstance(inst)
	end
end

return EnemyVisibility
