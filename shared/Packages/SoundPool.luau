export type SoundPoolEntry = {
	host: BasePart,
	sound: Sound,
}

export type SoundPool = {
	entries: { SoundPoolEntry },
	sounds: { Sound },
	template: Sound?,
	parent: Instance?,
	-- Optional SoundGroup applied to every pooled voice. Routing only — the voice stays parented to
	-- its host part, so spatial/directional audio is unaffected. nil leaves voices ungrouped.
	soundGroup: SoundGroup?,
	maxSize: number,
	destroyed: boolean,
	Play: (self: SoundPool, location: Vector3?, volumeScale: number?) -> Sound?,
	Destroy: (self: SoundPool) -> (),
}

local SoundPool = {}
SoundPool.__index = SoundPool

local SOUND_HOST_SIZE = Vector3.new(0.1, 0.1, 0.1)

local function getCameraPosition(): Vector3?
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function createEntry(soundPool: SoundPool, location: Vector3?): SoundPoolEntry
	local template = soundPool.template :: Sound
	local host = Instance.new("Part")
	host.Name = `{template.Name}SoundHost`
	host.Size = SOUND_HOST_SIZE
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.CFrame = CFrame.new(location or getCameraPosition() or Vector3.zero)
	host.Parent = soundPool.parent :: Instance

	local sound = template:Clone()
	sound.Parent = host
	if soundPool.soundGroup then
		sound.SoundGroup = soundPool.soundGroup
	end

	local entry = {
		host = host,
		sound = sound,
	}
	table.insert(soundPool.entries, entry)
	table.insert(soundPool.sounds, sound)

	return entry
end

function SoundPool.new(
	template: Sound,
	parent: Instance,
	maxSize: number,
	initialSize: number?,
	soundGroup: SoundGroup?
): SoundPool
	local self: SoundPool = {
		entries = {},
		sounds = {},
		template = template,
		parent = parent,
		soundGroup = soundGroup,
		--maxSize = 200,

		maxSize = math.max(1, maxSize),
		destroyed = false,
	}

	setmetatable(self :: any, SoundPool)

	for _ = 1, math.min(initialSize or 0, self.maxSize) do
		createEntry(self, nil)
	end

	return self
end

function SoundPool:Play(location: Vector3?, volumeScale: number?): Sound?
	local self = self :: SoundPool
	if self.destroyed then
		return nil
	end

	local template = self.template :: Sound
	local playLocation = location or getCameraPosition() or Vector3.zero
	local volume = template.Volume * (volumeScale or 1)

	for _, entry in self.entries do
		local sound = entry.sound
		if not sound.IsPlaying then
			entry.host.CFrame = CFrame.new(playLocation)
			sound.Volume = volume
			sound.TimePosition = 0
			sound:Play()
			return sound
		end
	end

	if #self.entries < self.maxSize then
		local entry = createEntry(self, playLocation)
		entry.sound.Volume = volume
		entry.sound:Play()
		return entry.sound
	end

	return nil
end

function SoundPool:Destroy()
	local self = self :: SoundPool
	if self.destroyed then
		return
	end

	for _, entry in self.entries do
		entry.host:Destroy()
	end

	table.clear(self.entries)
	table.clear(self.sounds)
	self.destroyed = true
	self.template = nil
	self.parent = nil
	self.soundGroup = nil
end

return SoundPool
