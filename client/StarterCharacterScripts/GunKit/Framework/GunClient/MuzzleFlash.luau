local module = {}
local module_mt = {__index = module}

type EmitterRecord = {
	emitter: ParticleEmitter,
	rate: number,
}

function module.new(gunModel: Model)
	local self = {}

	self.gunModel = gunModel

	local muzzleFlashNode = gunModel.Nodes.MuzzleFlash
	self.muzzleFlashNode = muzzleFlashNode
	muzzleFlashNode.Transparency = 1

	-- Emitters are driven here on :play(). Sounds are catalogued but NOT played here — they are
	-- the designer-authored shot-sound templates, played (pooled/positional) through ProjectileAudio.
	self.Emitters = {} :: {EmitterRecord}
	self.Sounds = {} :: {Sound}
	for _, descendant in muzzleFlashNode:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			table.insert(self.Emitters, {
				emitter = descendant,
				rate = descendant.Rate,
			})
			descendant.Rate = 0
		elseif descendant:IsA("Sound") then
			table.insert(self.Sounds, descendant)
		end
	end

	self.light = muzzleFlashNode:FindFirstChildWhichIsA("PointLight")

	return setmetatable(self, module_mt)
end

function module:play(_amount: number?)
	for _, emitterRecord in self.Emitters do
		emitterRecord.emitter:Emit(emitterRecord.rate)
	end
end

function module:enable()
	if self.light then
		self.light.Enabled = true
	end
end

function module:disable()
	if self.light then
		self.light.Enabled = false
	end
end

return module
