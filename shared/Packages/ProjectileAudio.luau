local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local SoundPool = require(ReplicatedStorage.Packages.SoundPool)

local ProjectileAudio = {}

ProjectileAudio.OtherPlayerGunAudioEnabled = true

local GUN_SOUND_GROUP_NAME = "GunSounds"
local gunSoundGroup: SoundGroup? = nil
local function getGunSoundGroup(): SoundGroup?
	if gunSoundGroup and gunSoundGroup.Parent then
		return gunSoundGroup
	end
	gunSoundGroup = SoundService:FindFirstChild(GUN_SOUND_GROUP_NAME) :: SoundGroup?
	return gunSoundGroup
end

local PROJECTILE_SOUND_POOL_FOLDER_NAME = "ProjectileSoundPools"
local SHOOT_SOUND_POOL_MIN_SIZE = 4
local SHOOT_SOUND_POOL_FALLBACK_SIZE = 50
local SHOOT_SOUND_POOL_MAX_SIZE_PER_SOURCE = 64
local SHOOT_SOUND_POOL_MAX_SOURCES = 8
local SHOOT_SOUND_POOL_HEADROOM = 2
local FORCEFIELD_HIT_SOUND_ID = "rbxassetid://81290777041327"
local FORCEFIELD_HIT_SOUND_POOL_SIZE = 10
local EXPLOSION_SOUND_ID = "rbxassetid://127623936928619"
local EXPLOSION_SOUND_POOL_SIZE = 8
local EXPLOSION_SOUND_POOL_INITIAL_SIZE = 2
local EXPLOSION_SOUND_ROLL_OFF_MAX_DISTANCE = 500

local projectileSoundPools = {} :: {[string]: any}

local function getNonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function getPositiveNumber(value: any): number?
	if typeof(value) == "number" and value > 0 then
		return value
	end

	return nil
end

local function createSoundTemplate(
	name: string,
	soundId: string,
	volume: number,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?
): Sound
	local template = Instance.new("Sound")
	template.Name = name
	template.SoundId = soundId
	template.Volume = volume
	if rollOffMinDistance then
		template.RollOffMinDistance = rollOffMinDistance
	end
	if rollOffMaxDistance then
		template.RollOffMaxDistance = rollOffMaxDistance
	end

	return template
end

local function getProjectileSoundPool(
	poolKey: string,
	template: Sound,
	maxSize: number,
	initialSize: number?,
	soundGroup: SoundGroup?
): any
	local soundPool = projectileSoundPools[poolKey]
	if not soundPool then
		local projectileParent = Workspace:WaitForChild("RAY_IGNORE")
		local soundFolder = projectileParent:FindFirstChild(PROJECTILE_SOUND_POOL_FOLDER_NAME)
		if not soundFolder then
			soundFolder = Instance.new("Folder")
			soundFolder.Name = PROJECTILE_SOUND_POOL_FOLDER_NAME
			soundFolder.Parent = projectileParent
		end

		soundPool = SoundPool.new(template, soundFolder, maxSize, initialSize, soundGroup)
		projectileSoundPools[poolKey] = soundPool
	elseif soundPool.maxSize < maxSize then
		soundPool.maxSize = maxSize
	end

	return soundPool
end

local function playPooledShot(sourceSound: Sound, position: Vector3?, shotInterval: number?, sourceCount: number)
	local soundId = getNonEmptyString(sourceSound.SoundId)
	if not soundId then
		return
	end

	-- Clone the designer-authored Sound as the pool template so its properties (RollOff, Volume,
	-- PlaybackSpeed, ...) carry into every pooled voice. The clone is owned by the pool, so the
	-- original instance in the gun model is never reparented, played, or destroyed.
	local poolKey = `ShootSound:{soundId}`
	local soundPool = projectileSoundPools[poolKey]
	local template = if soundPool then soundPool.template :: Sound else sourceSound:Clone()

	local maxPoolSize = SHOOT_SOUND_POOL_MAX_SIZE_PER_SOURCE * sourceCount
	local soundLength = getPositiveNumber(template.TimeLength)
	if not soundLength and soundPool then
		for _, sound in soundPool.sounds do
			soundLength = getPositiveNumber(sound.TimeLength)
			if soundLength then
				break
			end
		end
	end

	local poolSize = if soundLength and shotInterval and shotInterval > 0
		then math.clamp(
			(math.ceil(soundLength / shotInterval) + SHOOT_SOUND_POOL_HEADROOM) * sourceCount,
			SHOOT_SOUND_POOL_MIN_SIZE,
			maxPoolSize
		)
		else math.clamp(SHOOT_SOUND_POOL_FALLBACK_SIZE * sourceCount, SHOOT_SOUND_POOL_MIN_SIZE, maxPoolSize)
	soundPool =
		getProjectileSoundPool(poolKey, template, poolSize, math.min(SHOOT_SOUND_POOL_MIN_SIZE, poolSize), getGunSoundGroup())
	soundPool:Play(position)
end

-- Plays a gun's shot from the Sound instance(s) authored under its MuzzleFlash node. Each sound
-- is pooled (polyphony for rapid fire) and positional. Remote shots pass isLocalShooter = false
-- and are silenced when OtherPlayerGunAudioEnabled is off.
function ProjectileAudio.playGunShot(options: {[string]: any})
	if options.isLocalShooter == false and not ProjectileAudio.OtherPlayerGunAudioEnabled then
		return
	end

	local sounds = options.sounds
	if type(sounds) ~= "table" then
		return
	end

	local shotInterval = getPositiveNumber(options.shotInterval)
	local rawSourceCount = options.sourceCount
	local sourceCount = if typeof(rawSourceCount) == "number" and rawSourceCount > 0
		then math.clamp(math.floor(rawSourceCount), 1, SHOOT_SOUND_POOL_MAX_SOURCES)
		else 1

	for _, sound in sounds do
		if typeof(sound) == "Instance" and sound:IsA("Sound") then
			playPooledShot(sound, options.position, shotInterval, sourceCount)
		end
	end
end

function ProjectileAudio.playForceFieldHit(location: Vector3?)
	local poolKey = "ForceFieldHit"
	local soundPool = projectileSoundPools[poolKey]
	if not soundPool then
		local template = createSoundTemplate("ForceFieldHit", FORCEFIELD_HIT_SOUND_ID, 3, 70, nil)
		soundPool = getProjectileSoundPool(
			poolKey,
			template,
			FORCEFIELD_HIT_SOUND_POOL_SIZE,
			FORCEFIELD_HIT_SOUND_POOL_SIZE,
			getGunSoundGroup()
		)
	end

	soundPool:Play(location)
end

function ProjectileAudio.playExplosion(location: Vector3?)
	local poolKey = "Explosion"
	local soundPool = projectileSoundPools[poolKey]
	if not soundPool then
		local template = createSoundTemplate("Explode", EXPLOSION_SOUND_ID, 1, nil, EXPLOSION_SOUND_ROLL_OFF_MAX_DISTANCE)
		soundPool = getProjectileSoundPool(
			poolKey,
			template,
			EXPLOSION_SOUND_POOL_SIZE,
			EXPLOSION_SOUND_POOL_INITIAL_SIZE,
			getGunSoundGroup()
		)
	end

	soundPool:Play(location)
end

function ProjectileAudio.destroy()
	for _, soundPool in projectileSoundPools do
		local template = soundPool.template :: Sound
		soundPool:Destroy()
		template:Destroy()
	end

	table.clear(projectileSoundPools)

	local projectileParent = Workspace:FindFirstChild("RAY_IGNORE")
	local soundFolder = if projectileParent then projectileParent:FindFirstChild(PROJECTILE_SOUND_POOL_FOLDER_NAME) else nil
	if soundFolder and #soundFolder:GetChildren() == 0 then
		soundFolder:Destroy()
	end
end

return ProjectileAudio
