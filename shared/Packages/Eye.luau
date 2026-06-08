--!strict

local Players = game:GetService("Players")

local Spring = require(script.Parent.Spring)

----------------------------------------------
-- Types
----------------------------------------------

export type EyeStateName = "Normal" | "Surprised" | "Suspicious" | "Angry" | "Love" | "Dead"

export type TrackingStyle = {
	lookFrequency: number,
	lookDamping: number,
	saccadeInterval: { number }, -- {min, max}
	saccadeAmplitude: number,
}

export type EyeConfig = {
	trackingStyle: TrackingStyle?,
	baseSizeMult: number?,
}

export type DamageShockRequest = {
	damageRatio: number,
	dominantSide: "Left" | "Right",
}

type EyeStateValues = {
	whiteSize: Vector3,
	whiteColor: Color3,
	whiteTransparency: number,
	pupilSize: Vector3,
	pupilColor: Color3,
	pupilTransparency: number,
	heartSize: Vector3,
	heartTransparency: number,
	crossedSize: Vector3,
	crossedTransparency: number,
	eyebrowSize: Vector3,
	eyebrowOffset: Vector3,
	eyebrowRotZ: number,
	eyebrowTransparency: number,
	activePupil: "Pupil" | "HeartPupil" | "CrossedPupil",
}

type EyeStateData = {
	default: EyeStateValues,
	left: EyeStateValues?,
	right: EyeStateValues?,
}

----------------------------------------------
-- Constants
----------------------------------------------

local TRACKING_STYLES: { [string]: TrackingStyle } = {
	bird = { lookFrequency = 25, lookDamping = 1.2, saccadeInterval = { 0.3, 0.8 }, saccadeAmplitude = 0.02 },
	predator = { lookFrequency = 4, lookDamping = 0.9, saccadeInterval = { 1.5, 4.0 }, saccadeAmplitude = 0.005 },
	default = { lookFrequency = 10, lookDamping = 1.0, saccadeInterval = { 0.8, 2.0 }, saccadeAmplitude = 0.01 },
}

local ANIMAL_TO_EYE_STATE: { [string]: EyeStateName } = {
	Idle = "Normal",
	Patrol = "Normal",
	Startled = "Surprised",
	Escaping = "Surprised",
	Chase = "Angry",
	Attacking = "Angry",
	Carried = "Suspicious",
	Stored = "Normal",
	Dead = "Dead",
}

-- Breathing intensity targets per eye state
local BREATH_INTENSITY: { [EyeStateName]: number } = {
	Normal = 0.3,
	Surprised = 1.0,
	Suspicious = 0.5,
	Angry = 0.8,
	Love = 0.4,
	Dead = 0.0,
}

local BREATH_AMPLITUDE = 0.02
local BREATH_RATE_NORMAL = 2.0
local BREATH_RATE_ELEVATED = 4.0
local BREATH_INTENSITY_THRESHOLD = 0.6

local BLINK_INTERVAL_MIN = 2.0
local BLINK_INTERVAL_MAX = 6.0
local BLINK_CLOSE_DURATION = 0.06
local BLINK_HOLD_DURATION = 0.04
local BLINK_OPEN_DURATION = 0.08
local BLINK_TOTAL_DURATION = BLINK_CLOSE_DURATION + BLINK_HOLD_DURATION + BLINK_OPEN_DURATION
local BLINK_SQUASH_MIN = 0.15
local DOUBLE_BLINK_CHANCE = 0.15
local DOUBLE_BLINK_GAP = 0.12

local PLAYER_TRACK_RANGE = 30
local WANDER_CONE_ANGLE = math.rad(30)
local WANDER_INTERVAL_MIN = 2.0
local WANDER_INTERVAL_MAX = 4.0

local ANTICIPATION_DURATION = 0.06
local ANTICIPATION_SCALE = 0.85
local PUPIL_SWAP_DELAY = 0.08

local DOUBLE_TAKE_SNAP_TIME = 0.15
local DOUBLE_TAKE_BACK_TIME = 0.10
local DOUBLE_TAKE_RETURN_TIME = 0.25

local PUPIL_DISTANCE_RATIO = 0.286 -- pupil offset / white diameter (0.143 / 0.5)
local LOOK_MAX_ANGLE = math.rad(70) -- max angle from forward (-Z) that pupils can look
local rad = math.rad
local DAMAGE_SHOCK_TRIGGER_RATIO = 0.10
local DAMAGE_SHOCK_MAX_SCALE = 5.5
local DAMAGE_SHOCK_DOMINANT_SCALE = 5.15
local DAMAGE_SHOCK_SUBDUED_SCALE = 1.95

local WHITE_SHOCK_OFFSET_VELOCITY = Vector3.new(1.0, 2.35, -0.35) * 0.5
local PUPIL_SHOCK_OFFSET_VELOCITY = Vector3.new(0.6, 1.35, -0.12) * 0.5
local BROW_SHOCK_OFFSET_VELOCITY = Vector3.new(1.15, 2.8, -0.2) * 0.5

local WHITE_SHOCK_ROT_VELOCITY = Vector3.new(rad(6), 0, rad(45))
local PUPIL_SHOCK_ROT_VELOCITY = Vector3.new(rad(2), 0, rad(18))
local BROW_SHOCK_ROT_VELOCITY = Vector3.new(rad(8), 0, rad(58))

local WHITE_SHOCK_SIZE_VELOCITY = Vector3.new(0.12, 0.18, 0.08)
local PUPIL_SHOCK_SIZE_VELOCITY = Vector3.new(0.08, 0.11, 0.05)
local BROW_SHOCK_SIZE_VELOCITY = Vector3.new(0.14, 0.04, 0.03)

local WHITE_SHOCK_MAX_SPEED = 5.0 * 1
local PUPIL_SHOCK_MAX_SPEED = 3.5 * 1
local BROW_SHOCK_MAX_SPEED = 6.0 * 1
local WHITE_SHOCK_MAX_ROT_SPEED = rad(115) 
local PUPIL_SHOCK_MAX_ROT_SPEED = rad(50) 
local BROW_SHOCK_MAX_ROT_SPEED = rad(140) 
local WHITE_SHOCK_MAX_SIZE_SPEED = 1.5
local PUPIL_SHOCK_MAX_SIZE_SPEED = 1.0
local BROW_SHOCK_MAX_SIZE_SPEED = 1.1

----------------------------------------------
-- State Data (authored for Right eye)
----------------------------------------------

local DEFAULT_PUPIL_COLOR = Color3.fromRGB(27, 42, 53)
local DEFAULT_WHITE_COLOR = Color3.fromRGB(140, 140, 143)

local NORMAL_VALUES: EyeStateValues = {
	whiteSize = Vector3.new(0.5, 0.5, 0.5),
	whiteColor = DEFAULT_WHITE_COLOR,
	whiteTransparency = 0,
	pupilSize = Vector3.new(0.286, 0.286, 0.286),
	pupilColor = DEFAULT_PUPIL_COLOR,
	pupilTransparency = 0,
	heartSize = Vector3.new(0.236, 0.204, 0.135),
	heartTransparency = 1,
	crossedSize = Vector3.new(0.287, 0.072, 0.287),
	crossedTransparency = 1,
	eyebrowSize = Vector3.new(0.4, 0.1, 0.05),
	eyebrowOffset = Vector3.new(0.1, 0.3, 0),
	eyebrowRotZ = rad(-10),
	eyebrowTransparency = 0,
	activePupil = "Pupil",
}

local STATE_DATA: { [EyeStateName]: EyeStateData } = {
	Normal = { default = NORMAL_VALUES },

	Surprised = {
		default = {
			whiteSize = Vector3.new(0.7, 0.7, 0.7),
			whiteColor = DEFAULT_WHITE_COLOR,
			whiteTransparency = 0,
			pupilSize = Vector3.new(0.4, 0.4, 0.4),
			pupilColor = DEFAULT_PUPIL_COLOR,
			pupilTransparency = 0,
			heartSize = Vector3.new(0.236, 0.204, 0.135),
			heartTransparency = 1,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 1,
			eyebrowSize = Vector3.new(0.4, 0.1, 0.05),
			eyebrowOffset = Vector3.new(0.1, 0.5, -0.007),
			eyebrowRotZ = rad(-20),
			eyebrowTransparency = 0,
			activePupil = "Pupil",
		},
	},

	Suspicious = {
		default = { -- right eye: slightly raised brow, otherwise normal sizes
			whiteSize = Vector3.new(0.5, 0.5, 0.5),
			whiteColor = DEFAULT_WHITE_COLOR,
			whiteTransparency = 0,
			pupilSize = Vector3.new(0.286, 0.286, 0.286),
			pupilColor = DEFAULT_PUPIL_COLOR,
			pupilTransparency = 0,
			heartSize = Vector3.new(0.236, 0.204, 0.135),
			heartTransparency = 1,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 1,
			eyebrowSize = Vector3.new(0.4, 0.1, 0.05),
			eyebrowOffset = Vector3.new(0, 0.35, 0),
			eyebrowRotZ = rad(-20),
			eyebrowTransparency = 0,
			activePupil = "Pupil",
		},
		left = { -- squinting eye: enlarged, steeper brow
			whiteSize = Vector3.new(0.7, 0.7, 0.7),
			whiteColor = DEFAULT_WHITE_COLOR,
			whiteTransparency = 0,
			pupilSize = Vector3.new(0.4, 0.4, 0.4),
			pupilColor = DEFAULT_PUPIL_COLOR,
			pupilTransparency = 0,
			heartSize = Vector3.new(0.236, 0.204, 0.135),
			heartTransparency = 1,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 1,
			eyebrowSize = Vector3.new(0.5, 0.1, 0.05),
			eyebrowOffset = Vector3.new(-0.038, 0.5, -0.007),
			eyebrowRotZ = rad(30),
			eyebrowTransparency = 0,
			activePupil = "Pupil",
		},
	},

	Angry = {
		default = {
			whiteSize = Vector3.new(0.5, 0.5, 0.5),
			whiteColor = Color3.fromRGB(152, 137, 56),
			whiteTransparency = 0,
			pupilSize = Vector3.new(0.286, 0.286, 0.286),
			pupilColor = Color3.fromRGB(255, 0, 0),
			pupilTransparency = 0,
			heartSize = Vector3.new(0.236, 0.204, 0.135),
			heartTransparency = 1,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 1,
			eyebrowSize = Vector3.new(0.4, 0.1, 0.05),
			eyebrowOffset = Vector3.new(0, 0.3, 0),
			eyebrowRotZ = rad(30),
			eyebrowTransparency = 0,
			activePupil = "Pupil",
		},
	},

	Love = {
		default = {
			whiteSize = Vector3.new(0.5, 0.5, 0.5),
			whiteColor = DEFAULT_WHITE_COLOR,
			whiteTransparency = 0,
			pupilSize = Vector3.zero,
			pupilColor = DEFAULT_PUPIL_COLOR,
			pupilTransparency = 1,
			heartSize = Vector3.new(0.236, 0.204, 0.135),
			heartTransparency = 0,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 1,
			eyebrowSize = Vector3.new(0.4, 0.1, 0.05),
			eyebrowOffset = Vector3.new(0.1, 0.3, 0),
			eyebrowRotZ = rad(-20),
			eyebrowTransparency = 0,
			activePupil = "HeartPupil",
		},
	},

	Dead = {
		default = {
			whiteSize = Vector3.new(0.5, 0.5, 0.5),
			whiteColor = DEFAULT_WHITE_COLOR,
			whiteTransparency = 0,
			pupilSize = Vector3.zero,
			pupilColor = DEFAULT_PUPIL_COLOR,
			pupilTransparency = 1,
			heartSize = Vector3.zero,
			heartTransparency = 1,
			crossedSize = Vector3.new(0.287, 0.072, 0.287),
			crossedTransparency = 0,
			eyebrowSize = Vector3.new(0.001, 0.001, 0.001),
			eyebrowOffset = Vector3.new(0, 0, 0),
			eyebrowRotZ = 0,
			eyebrowTransparency = 0,
			activePupil = "CrossedPupil",
		},
	},
}

----------------------------------------------
-- Eye Class
----------------------------------------------

local Eye = {}
local Eye_mt = { __index = Eye }

export type Eye = typeof(setmetatable({} :: {
	eyeModel: Model?,
	side: "Left" | "Right",
	socketPart: BasePart,
	baseSizeMult: number,
	destroyed: boolean,

	-- Part references
	white: BasePart?,
	pupil: BasePart?,
	heartPupil: BasePart?,
	crossedPupil: Model?,
	crossedParts: { BasePart },
	eyebrow: BasePart?,

	-- Original sizes (from template)
	originalHeartSize: Vector3,
	originalCrossedSize: Vector3,

	-- Springs
	springs: {
		whiteSize: Spring.Spring<Vector3>,
		whiteColor: Spring.Spring<Vector3>,
		whiteTransparency: Spring.Spring<number>,
		whiteShockOffset: Spring.Spring<Vector3>,
		whiteShockRot: Spring.Spring<Vector3>,
		whiteShockSize: Spring.Spring<Vector3>,
		pupilSize: Spring.Spring<Vector3>,
		pupilTransparency: Spring.Spring<number>,
		pupilColor: Spring.Spring<Vector3>,
		pupilShockOffset: Spring.Spring<Vector3>,
		pupilShockRot: Spring.Spring<Vector3>,
		pupilShockSize: Spring.Spring<Vector3>,
		heartSize: Spring.Spring<Vector3>,
		heartTransparency: Spring.Spring<number>,
		crossedSize: Spring.Spring<Vector3>,
		crossedTransparency: Spring.Spring<number>,
		eyebrowSize: Spring.Spring<Vector3>,
		eyebrowOffset: Spring.Spring<Vector3>,
		eyebrowRotZ: Spring.Spring<number>,
		eyebrowTransparency: Spring.Spring<number>,
		browShockOffset: Spring.Spring<Vector3>,
		browShockRot: Spring.Spring<Vector3>,
		browShockSize: Spring.Spring<Vector3>,
		lookDirection: Spring.Spring<Vector3>,
		saccade: Spring.Spring<Vector3>,
	},

	-- State
	currentState: EyeStateName,
	previousState: EyeStateName,
	localOverride: EyeStateName?,
	serverState: EyeStateName,

	-- Transition timers
	anticipationTimer: number,
	pendingStateData: EyeStateValues?,
	pupilSwapTimer: number,
	pendingPupilData: EyeStateValues?,
	staggerDelay: number,
	staggerTimer: number,
	pendingStaggerState: EyeStateName?,

	-- Blink
	blinkCooldown: number,
	blinkTimer: number,
	isBlinking: boolean,
	doubleBlink: boolean,
	doubleBlinkPending: boolean,

	-- Saccade
	saccadeTimer: number,

	-- Breathing
	breathPhase: number,
	breathIntensity: number,
	breathIntensityTarget: number,

	-- Look-at
	trackingStyle: TrackingStyle,
	wanderTimer: number,
	wanderTarget: Vector3,
	wasPlayerInRange: boolean,
	doubleTakePhase: number,
	doubleTakeTimer: number,
	doubleTakePlayerPos: Vector3?,
	manualLookTarget: Vector3?,
	useCameraTracking: boolean,
}, Eye_mt))

----------------------------------------------
-- Helpers
----------------------------------------------

local function resolveStateForSide(stateData: EyeStateData, side: "Left" | "Right"): EyeStateValues
	-- Check for explicit side override
	local sideOverride = if side == "Left" then stateData.left else stateData.right
	if sideOverride then
		return sideOverride
	end

	-- Use default, mirroring for left eye
	local d = stateData.default
	if side == "Left" then
		return {
			whiteSize = d.whiteSize,
			whiteColor = d.whiteColor,
			whiteTransparency = d.whiteTransparency,
			pupilSize = d.pupilSize,
			pupilColor = d.pupilColor,
			pupilTransparency = d.pupilTransparency,
			heartSize = d.heartSize,
			heartTransparency = d.heartTransparency,
			crossedSize = d.crossedSize,
			crossedTransparency = d.crossedTransparency,
			eyebrowSize = d.eyebrowSize,
			eyebrowOffset = Vector3.new(-d.eyebrowOffset.X, d.eyebrowOffset.Y, d.eyebrowOffset.Z),
			eyebrowRotZ = -d.eyebrowRotZ,
			eyebrowTransparency = d.eyebrowTransparency,
			activePupil = d.activePupil,
		}
	end

	return d
end

local function randomInRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function lerpNum(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Color3 doesn't support arithmetic operators, so we use Vector3 as a proxy
local function colorToVec(c: Color3): Vector3
	return Vector3.new(c.R, c.G, c.B)
end

local function vecToColor(v: Vector3): Color3
	return Color3.new(math.clamp(v.X, 0, 1), math.clamp(v.Y, 0, 1), math.clamp(v.Z, 0, 1))
end

local function clampVectorMagnitude(vec: Vector3, maxMagnitude: number): Vector3
	local magnitude = vec.Magnitude
	if magnitude <= maxMagnitude or magnitude <= 0.0001 then
		return vec
	end

	return vec.Unit * maxMagnitude
end

local function addClampedImpulse(spring: Spring.Spring<Vector3>, impulse: Vector3, maxMagnitude: number)
	spring.v = clampVectorMagnitude(spring.v + impulse, maxMagnitude)
end

local function clampVectorComponentsMin(vec: Vector3, minValue: number): Vector3
	return Vector3.new(
		math.max(vec.X, minValue),
		math.max(vec.Y, minValue),
		math.max(vec.Z, minValue)
	)
end

local function shockTransform(offset: Vector3, rot: Vector3): CFrame
	return CFrame.new(offset) * CFrame.Angles(rot.X, rot.Y, rot.Z)
end

local function sanitizeBaseSizeMult(baseSizeMult: number?): number
	if baseSizeMult and baseSizeMult > 0 then
		return baseSizeMult
	end

	return 1
end

local function scaleStateValues(stateValues: EyeStateValues, baseSizeMult: number): EyeStateValues
	if baseSizeMult == 1 then
		return stateValues
	end

	return {
		whiteSize = stateValues.whiteSize * baseSizeMult,
		whiteColor = stateValues.whiteColor,
		whiteTransparency = stateValues.whiteTransparency,
		pupilSize = stateValues.pupilSize * baseSizeMult,
		pupilColor = stateValues.pupilColor,
		pupilTransparency = stateValues.pupilTransparency,
		heartSize = stateValues.heartSize * baseSizeMult,
		heartTransparency = stateValues.heartTransparency,
		crossedSize = stateValues.crossedSize * baseSizeMult,
		crossedTransparency = stateValues.crossedTransparency,
		eyebrowSize = stateValues.eyebrowSize * baseSizeMult,
		eyebrowOffset = stateValues.eyebrowOffset * baseSizeMult,
		eyebrowRotZ = stateValues.eyebrowRotZ,
		eyebrowTransparency = stateValues.eyebrowTransparency,
		activePupil = stateValues.activePupil,
	}
end

local function resolveScaledStateForSide(stateName: EyeStateName, side: "Left" | "Right", baseSizeMult: number): EyeStateValues
	return scaleStateValues(resolveStateForSide(STATE_DATA[stateName], side), baseSizeMult)
end

local function randomWanderDirection(): Vector3
	local angle = math.random() * math.pi * 2
	local elevation = (math.random() - 0.5) * 2 * WANDER_CONE_ANGLE
	local x = math.sin(angle) * math.sin(WANDER_CONE_ANGLE)
	local y = math.sin(elevation)
	local z = -math.cos(angle) * math.cos(WANDER_CONE_ANGLE)
	return Vector3.new(x, y, z).Unit
end

-- Clamp a local-space look direction to within LOOK_MAX_ANGLE of forward (-Z)
local FORWARD = Vector3.new(0, 0, -1)
local function clampLookDirection(dir: Vector3): Vector3
	local dotForward = dir:Dot(FORWARD)
	local cosMax = math.cos(LOOK_MAX_ANGLE)

	-- If already within the cone, return as-is
	if dotForward >= cosMax then
		return dir
	end

	-- Project dir onto the plane perpendicular to forward, then blend
	local lateral = dir - FORWARD * dotForward
	local lateralMag = lateral.Magnitude
	if lateralMag < 0.001 then
		-- Looking directly backward, snap to forward
		return FORWARD
	end

	-- Construct a direction at exactly the max angle
	local sinMax = math.sin(LOOK_MAX_ANGLE)
	local clampedDir = FORWARD * cosMax + (lateral / lateralMag) * sinMax
	return clampedDir.Unit
end

----------------------------------------------
-- Constructor
----------------------------------------------

function Eye.new(eyeModel: Model, side: "Left" | "Right", socketPart: BasePart, config: EyeConfig?): Eye
	local white = eyeModel:FindFirstChild("White") :: BasePart
	local pupil = eyeModel:FindFirstChild("Pupil") :: BasePart
	local heartPupil = eyeModel:FindFirstChild("HeartPupil") :: BasePart
	local crossedPupil = eyeModel:FindFirstChild("CrossedPupil") :: Model
	local eyebrow = eyeModel:FindFirstChild("Eyebrow") :: BasePart

	assert(white, "Eye model missing 'White' part")
	assert(pupil, "Eye model missing 'Pupil' part")
	assert(eyebrow, "Eye model missing 'Eyebrow' part")

	local baseSizeMult = sanitizeBaseSizeMult(if config then config.baseSizeMult else nil)

	-- Gather crossed pupil parts
	local crossedParts: { BasePart } = {}
	if crossedPupil then
		for _, child in crossedPupil:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(crossedParts, child)
			end
		end
	end

	-- Resolve initial state values
	local initValues = resolveScaledStateForSide("Normal", side, baseSizeMult)

	-- Resolve tracking style
	local trackingStyle = TRACKING_STYLES.default
	if config and config.trackingStyle then
		trackingStyle = config.trackingStyle
	end

	-- Store original sizes for pupil types that swap in/out
	local originalHeartSize = if heartPupil then heartPupil.Size else Vector3.new(0.236, 0.204, 0.135)
	local originalCrossedSize = if #crossedParts > 0 then crossedParts[1].Size else Vector3.new(0.287, 0.072, 0.287)

	local self = {
		eyeModel = eyeModel,
		side = side,
		socketPart = socketPart,
		baseSizeMult = baseSizeMult,
		destroyed = false,

		-- Part references
		white = white,
		pupil = pupil,
		heartPupil = heartPupil,
		crossedPupil = crossedPupil,
		crossedParts = crossedParts,
		eyebrow = eyebrow,

		originalHeartSize = originalHeartSize,
		originalCrossedSize = originalCrossedSize,

		-- Springs (created with initial Normal values)
		springs = {
			whiteSize = Spring.new(initValues.whiteSize, Vector3.zero, initValues.whiteSize, 12, 0.7),
			whiteColor = Spring.new(colorToVec(initValues.whiteColor), Vector3.zero, colorToVec(initValues.whiteColor), 8, 1.0),
			whiteTransparency = Spring.new(initValues.whiteTransparency, 0, initValues.whiteTransparency, 10, 1.2),
			whiteShockOffset = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 18, 0.28),
			whiteShockRot = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 18, 0.28),
			whiteShockSize = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 18, 0.28),
			pupilSize = Spring.new(initValues.pupilSize, Vector3.zero, initValues.pupilSize, 14, 0.7),
			pupilTransparency = Spring.new(initValues.pupilTransparency, 0, initValues.pupilTransparency, 12, 1.2),
			pupilColor = Spring.new(colorToVec(initValues.pupilColor), Vector3.zero, colorToVec(initValues.pupilColor), 8, 1.0),
			pupilShockOffset = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 14, 0.34),
			pupilShockRot = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 14, 0.34),
			pupilShockSize = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 14, 0.34),
			heartSize = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 10, 0.6),
			heartTransparency = Spring.new(1, 0, 1, 12, 1.2),
			crossedSize = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 12, 0.7),
			crossedTransparency = Spring.new(1, 0, 1, 12, 1.2),
			eyebrowSize = Spring.new(initValues.eyebrowSize, Vector3.zero, initValues.eyebrowSize, 10, 0.8),
			eyebrowOffset = Spring.new(initValues.eyebrowOffset, Vector3.zero, initValues.eyebrowOffset, 10, 0.8),
			eyebrowRotZ = Spring.new(initValues.eyebrowRotZ, 0, initValues.eyebrowRotZ, 10, 0.8),
			eyebrowTransparency = Spring.new(initValues.eyebrowTransparency, 0, initValues.eyebrowTransparency, 10, 1.2),
			browShockOffset = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 20, 0.24),
			browShockRot = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 20, 0.24),
			browShockSize = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 20, 0.24),
			lookDirection = Spring.new(Vector3.new(0, 0, -1), Vector3.zero, Vector3.new(0, 0, -1), trackingStyle.lookFrequency, trackingStyle.lookDamping),
			saccade = Spring.new(Vector3.zero, Vector3.zero, Vector3.zero, 20, 0.5),
		},

		-- State
		currentState = "Normal" :: EyeStateName,
		previousState = "Normal" :: EyeStateName,
		localOverride = nil :: EyeStateName?,
		serverState = "Normal" :: EyeStateName,

		-- Transition timers
		anticipationTimer = 0,
		pendingStateData = nil :: EyeStateValues?,
		pupilSwapTimer = 0,
		pendingPupilData = nil :: EyeStateValues?,
		staggerDelay = 0,
		staggerTimer = 0,
		pendingStaggerState = nil :: EyeStateName?,

		-- Blink
		blinkCooldown = randomInRange(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX),
		blinkTimer = 0,
		isBlinking = false,
		doubleBlink = false,
		doubleBlinkPending = false,

		-- Saccade
		saccadeTimer = randomInRange(trackingStyle.saccadeInterval[1], trackingStyle.saccadeInterval[2]),

		-- Breathing
		breathPhase = math.random() * math.pi * 2, -- random start phase
		breathIntensity = BREATH_INTENSITY.Normal,
		breathIntensityTarget = BREATH_INTENSITY.Normal,

		-- Look-at
		trackingStyle = trackingStyle,
		wanderTimer = randomInRange(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX),
		wanderTarget = Vector3.new(0, 0, -1),
		wasPlayerInRange = false,
		doubleTakePhase = 0, -- 0 = inactive
		doubleTakeTimer = 0,
		doubleTakePlayerPos = nil :: Vector3?,
		manualLookTarget = nil :: Vector3?,
		useCameraTracking = false,
	}

	return setmetatable(self, Eye_mt) :: any
end

----------------------------------------------
-- State Management
----------------------------------------------

function Eye.mapAnimalState(animalState: string): EyeStateName
	return ANIMAL_TO_EYE_STATE[animalState] or "Normal"
end

function Eye:setState(newState: EyeStateName)
	-- If we have a stagger delay, buffer the state change
	if self.staggerDelay > 0 then
		self.pendingStaggerState = newState
		self.staggerTimer = self.staggerDelay
		return
	end

	self:_applyState(newState)
end

function Eye:_applyState(newState: EyeStateName)
	if newState == self.currentState then return end

	self.previousState = self.currentState
	self.currentState = newState

	-- Update breathing intensity target
	self.breathIntensityTarget = BREATH_INTENSITY[newState] or 0.3

	local stateData = resolveScaledStateForSide(newState, self.side, self.baseSizeMult)
	local prevData = resolveScaledStateForSide(self.previousState, self.side, self.baseSizeMult)

	-- Anticipation: brief squeeze before Surprised burst
	if newState == "Surprised" and self.previousState ~= "Dead" then
		self.anticipationTimer = ANTICIPATION_DURATION
		self.pendingStateData = stateData
		self.springs.whiteSize.target = prevData.whiteSize * ANTICIPATION_SCALE
		self.springs.pupilSize.target = prevData.pupilSize * ANTICIPATION_SCALE
		return
	end

	self:_applyStateTargets(stateData, prevData)
end

function Eye:_applyStateTargets(stateData: EyeStateValues, prevData: EyeStateValues)
	local s = self.springs

	s.whiteSize.target = stateData.whiteSize
	s.whiteColor.target = colorToVec(stateData.whiteColor)
	s.whiteTransparency.target = stateData.whiteTransparency
	s.eyebrowSize.target = stateData.eyebrowSize
	s.eyebrowOffset.target = stateData.eyebrowOffset
	s.eyebrowRotZ.target = stateData.eyebrowRotZ
	s.eyebrowTransparency.target = stateData.eyebrowTransparency
	s.pupilColor.target = colorToVec(stateData.pupilColor)

	-- Pupil swap choreography
	if stateData.activePupil ~= prevData.activePupil then
		-- Fade out ALL pupil types immediately
		s.pupilTransparency.target = 1
		s.pupilSize.target = Vector3.zero
		s.heartTransparency.target = 1
		s.heartSize.target = Vector3.zero
		s.crossedTransparency.target = 1
		s.crossedSize.target = Vector3.zero

		-- Schedule fade-in of new pupil after delay
		self.pupilSwapTimer = PUPIL_SWAP_DELAY
		self.pendingPupilData = stateData
	else
		-- Same pupil type, update directly
		s.pupilSize.target = stateData.pupilSize
		s.pupilTransparency.target = stateData.pupilTransparency
		s.heartSize.target = stateData.heartSize
		s.heartTransparency.target = stateData.heartTransparency
		s.crossedSize.target = stateData.crossedSize
		s.crossedTransparency.target = stateData.crossedTransparency
	end
end

function Eye:_applyPendingPupil(stateData: EyeStateValues)
	local s = self.springs
	if stateData.activePupil == "Pupil" then
		s.pupilSize.target = stateData.pupilSize
		s.pupilTransparency.target = stateData.pupilTransparency
	elseif stateData.activePupil == "HeartPupil" then
		s.heartSize.target = stateData.heartSize
		s.heartTransparency.target = stateData.heartTransparency
	elseif stateData.activePupil == "CrossedPupil" then
		s.crossedSize.target = stateData.crossedSize
		s.crossedTransparency.target = stateData.crossedTransparency
	end
end

function Eye:setLocalOverride(stateName: EyeStateName?)
	self.localOverride = stateName
	local effectiveState = stateName or self.serverState
	self:setState(effectiveState)
end

function Eye:setServerState(animalState: string)
	local eyeState = Eye.mapAnimalState(animalState)
	self.serverState = eyeState
	if not self.localOverride then
		self:setState(eyeState)
	end
end

function Eye:setLookTarget(worldPos: Vector3?)
	self.manualLookTarget = worldPos
end

function Eye:triggerDamageShock(request: DamageShockRequest)
	local damageRatio = math.max(request.damageRatio, DAMAGE_SHOCK_TRIGGER_RATIO)
	local impulseScale = math.clamp(damageRatio / DAMAGE_SHOCK_TRIGGER_RATIO, 1, DAMAGE_SHOCK_MAX_SCALE)
	local dominanceScale = if request.dominantSide == self.side then DAMAGE_SHOCK_DOMINANT_SCALE else DAMAGE_SHOCK_SUBDUED_SCALE
	local sideSign = if self.side == "Right" then 1 else -1
	local spatialScale = self.baseSizeMult * impulseScale * dominanceScale
	local rotationalScale = impulseScale * dominanceScale
	local s = self.springs

	addClampedImpulse(
		s.whiteShockOffset,
		Vector3.new(sideSign * WHITE_SHOCK_OFFSET_VELOCITY.X, WHITE_SHOCK_OFFSET_VELOCITY.Y, WHITE_SHOCK_OFFSET_VELOCITY.Z) * spatialScale,
		WHITE_SHOCK_MAX_SPEED * self.baseSizeMult
	)
	addClampedImpulse(
		s.whiteShockRot,
		Vector3.new(WHITE_SHOCK_ROT_VELOCITY.X, WHITE_SHOCK_ROT_VELOCITY.Y, sideSign * WHITE_SHOCK_ROT_VELOCITY.Z) * rotationalScale,
		WHITE_SHOCK_MAX_ROT_SPEED
	)
	addClampedImpulse(
		s.whiteShockSize,
		WHITE_SHOCK_SIZE_VELOCITY * spatialScale,
		WHITE_SHOCK_MAX_SIZE_SPEED * self.baseSizeMult
	)
	addClampedImpulse(
		s.pupilShockOffset,
		Vector3.new(sideSign * PUPIL_SHOCK_OFFSET_VELOCITY.X, PUPIL_SHOCK_OFFSET_VELOCITY.Y, PUPIL_SHOCK_OFFSET_VELOCITY.Z) * spatialScale,
		PUPIL_SHOCK_MAX_SPEED * self.baseSizeMult
	)
	addClampedImpulse(
		s.pupilShockRot,
		Vector3.new(PUPIL_SHOCK_ROT_VELOCITY.X, PUPIL_SHOCK_ROT_VELOCITY.Y, sideSign * PUPIL_SHOCK_ROT_VELOCITY.Z) * rotationalScale,
		PUPIL_SHOCK_MAX_ROT_SPEED
	)
	addClampedImpulse(
		s.pupilShockSize,
		PUPIL_SHOCK_SIZE_VELOCITY * spatialScale,
		PUPIL_SHOCK_MAX_SIZE_SPEED * self.baseSizeMult
	)
	addClampedImpulse(
		s.browShockOffset,
		Vector3.new(sideSign * BROW_SHOCK_OFFSET_VELOCITY.X, BROW_SHOCK_OFFSET_VELOCITY.Y, BROW_SHOCK_OFFSET_VELOCITY.Z) * spatialScale,
		BROW_SHOCK_MAX_SPEED * self.baseSizeMult
	)
	addClampedImpulse(
		s.browShockRot,
		Vector3.new(BROW_SHOCK_ROT_VELOCITY.X, BROW_SHOCK_ROT_VELOCITY.Y, sideSign * BROW_SHOCK_ROT_VELOCITY.Z) * rotationalScale,
		BROW_SHOCK_MAX_ROT_SPEED
	)
	addClampedImpulse(
		s.browShockSize,
		BROW_SHOCK_SIZE_VELOCITY * spatialScale,
		BROW_SHOCK_MAX_SIZE_SPEED * self.baseSizeMult
	)
end

----------------------------------------------
-- Look-At Logic
----------------------------------------------

-- Check if a local-space direction is within the look cone
local function isWithinLookCone(localDir: Vector3): boolean
	return localDir:Dot(FORWARD) >= math.cos(LOOK_MAX_ANGLE)
end

function Eye:_getPlayerTrackingPositions(): (Vector3?, Vector3?)
	-- Returns (headPos, cameraPos) — either can be nil
	local player = Players.LocalPlayer
	if not player then return nil, nil end

	local cameraPos: Vector3? = nil
	local cam = workspace.CurrentCamera
	if cam then
		cameraPos = cam.CFrame.Position
	end

	if self.useCameraTracking then
		return cameraPos, nil -- camera-only mode, no fallback needed
	end

	local character = player.Character
	if not character then return nil, cameraPos end

	local head = character:FindFirstChild("Head") :: BasePart?
	local headPos = if head then head.Position else nil
	return headPos, cameraPos
end

function Eye:_updateLookAt(dt: number)
	local white = self.white
	if not white then return end

	-- Dead eyes don't track
	if self.currentState == "Dead" then
		self.springs.lookDirection.target = Vector3.new(0, 0, -1)
		self.wasPlayerInRange = false
		return
	end

	local whiteCFrame = white.CFrame
	local targetWorldPos: Vector3? = self.manualLookTarget

	-- Priority: manual > player head (with camera fallback) > wander
	if not targetWorldPos then
		local headPos, cameraPos = self:_getPlayerTrackingPositions()

		-- Find the best trackable position: prefer head, fall back to camera
		-- if head is outside the look cone
		local bestPos: Vector3? = nil
		if headPos then
			local dist = (headPos - whiteCFrame.Position).Magnitude
			if dist <= PLAYER_TRACK_RANGE then
				local localDir = whiteCFrame:VectorToObjectSpace((headPos - whiteCFrame.Position).Unit)
				if isWithinLookCone(localDir) then
					bestPos = headPos
				elseif cameraPos then
					-- Head is behind us, try camera instead
					local camDist = (cameraPos - whiteCFrame.Position).Magnitude
					if camDist <= PLAYER_TRACK_RANGE then
						local camLocalDir = whiteCFrame:VectorToObjectSpace((cameraPos - whiteCFrame.Position).Unit)
						if isWithinLookCone(camLocalDir) then
							bestPos = cameraPos
						else
							-- Neither in cone — still use head, clamp will handle it
							bestPos = headPos
						end
					else
						bestPos = headPos
					end
				else
					bestPos = headPos
				end
			end
		elseif cameraPos then
			-- No head available, try camera
			local camDist = (cameraPos - whiteCFrame.Position).Magnitude
			if camDist <= PLAYER_TRACK_RANGE then
				bestPos = cameraPos
			end
		end

		if bestPos then
			targetWorldPos = bestPos

			-- Double-take: player just entered range
			if not self.wasPlayerInRange then
				self.wasPlayerInRange = true
				self.doubleTakePhase = 1
				self.doubleTakeTimer = 0
				self.doubleTakePlayerPos = bestPos
			end
		else
			if self.wasPlayerInRange then
				self.wasPlayerInRange = false
				self.doubleTakePhase = 0
			end
		end
	end

	-- Double-take state machine
	if self.doubleTakePhase > 0 then
		self.doubleTakeTimer = self.doubleTakeTimer + dt
		local playerPos = self.doubleTakePlayerPos or whiteCFrame.Position + whiteCFrame.LookVector * -5

		if self.doubleTakePhase == 1 then
			-- Phase 1: snap to player
			local localDir = whiteCFrame:VectorToObjectSpace((playerPos - whiteCFrame.Position).Unit)
			self.springs.lookDirection.target = localDir
			if self.doubleTakeTimer >= DOUBLE_TAKE_SNAP_TIME then
				self.doubleTakePhase = 2
				self.doubleTakeTimer = 0
			end
		elseif self.doubleTakePhase == 2 then
			-- Phase 2: snap back to forward
			self.springs.lookDirection.target = Vector3.new(0, 0, -1)
			if self.doubleTakeTimer >= DOUBLE_TAKE_BACK_TIME then
				self.doubleTakePhase = 3
				self.doubleTakeTimer = 0
			end
		elseif self.doubleTakePhase == 3 then
			-- Phase 3: snap back to player and hold
			local localDir = whiteCFrame:VectorToObjectSpace((playerPos - whiteCFrame.Position).Unit)
			self.springs.lookDirection.target = localDir
			if self.doubleTakeTimer >= DOUBLE_TAKE_RETURN_TIME then
				self.doubleTakePhase = 0 -- done, normal tracking takes over
			end
		end
		return -- skip normal targeting during double-take
	end

	if targetWorldPos then
		-- Convert to White-local direction
		local localDir = whiteCFrame:VectorToObjectSpace((targetWorldPos - whiteCFrame.Position).Unit)
		self.springs.lookDirection.target = localDir
	else
		-- Random wander
		self.wanderTimer = self.wanderTimer - dt
		if self.wanderTimer <= 0 then
			self.wanderTarget = randomWanderDirection()
			self.wanderTimer = randomInRange(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)
		end
		self.springs.lookDirection.target = self.wanderTarget
	end
end

----------------------------------------------
-- Idle Behaviors
----------------------------------------------

function Eye:_updateBlink(dt: number): (number, number)
	-- Returns (blinkSquash: Y-scale multiplier, blinkPupilHide: transparency additive)
	if self.currentState == "Dead" then
		return 1, 0
	end

	if self.isBlinking then
		self.blinkTimer = self.blinkTimer + dt
		local t = self.blinkTimer

		local squash: number
		local pupilHide: number

		if t < BLINK_CLOSE_DURATION then
			-- Closing
			local alpha = t / BLINK_CLOSE_DURATION
			squash = lerpNum(1.0, BLINK_SQUASH_MIN, alpha)
			pupilHide = alpha
		elseif t < BLINK_CLOSE_DURATION + BLINK_HOLD_DURATION then
			-- Hold closed
			squash = BLINK_SQUASH_MIN
			pupilHide = 1
		elseif t < BLINK_TOTAL_DURATION then
			-- Opening
			local alpha = (t - BLINK_CLOSE_DURATION - BLINK_HOLD_DURATION) / BLINK_OPEN_DURATION
			squash = lerpNum(BLINK_SQUASH_MIN, 1.0, alpha)
			pupilHide = 1 - alpha
		else
			-- Blink complete
			self.isBlinking = false
			self.blinkTimer = 0

			if self.doubleBlinkPending then
				self.doubleBlinkPending = false
				self.blinkCooldown = DOUBLE_BLINK_GAP
			else
				self.blinkCooldown = randomInRange(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)
			end

			return 1, 0
		end

		return squash, pupilHide
	else
		-- Countdown to next blink
		self.blinkCooldown = self.blinkCooldown - dt
		if self.blinkCooldown <= 0 then
			self.isBlinking = true
			self.blinkTimer = 0

			-- Check for double blink
			if not self.doubleBlink and math.random() < DOUBLE_BLINK_CHANCE then
				self.doubleBlink = true
				self.doubleBlinkPending = true
			else
				self.doubleBlink = false
				self.doubleBlinkPending = false
			end
		end
		return 1, 0
	end
end

function Eye:_updateSaccade(dt: number)
	self.saccadeTimer = self.saccadeTimer - dt
	if self.saccadeTimer <= 0 then
		local style = self.trackingStyle
		local amp = style.saccadeAmplitude
		self.springs.saccade.target = Vector3.new(
			(math.random() - 0.5) * 2 * amp,
			(math.random() - 0.5) * 2 * amp,
			0
		)
		self.saccadeTimer = randomInRange(style.saccadeInterval[1], style.saccadeInterval[2])
	end
end

function Eye:_updateBreathing(dt: number): number
	-- Lerp intensity toward target
	local lerpRate = 2.0 * dt
	self.breathIntensity = lerpNum(self.breathIntensity, self.breathIntensityTarget, math.min(lerpRate, 1))

	-- Advance phase
	local rate = if self.breathIntensity > BREATH_INTENSITY_THRESHOLD then BREATH_RATE_ELEVATED else BREATH_RATE_NORMAL
	self.breathPhase = self.breathPhase + dt * rate

	-- Compute scale multiplier
	local breathScale = 1.0 + math.sin(self.breathPhase) * BREATH_AMPLITUDE * self.breathIntensity
	return breathScale
end

----------------------------------------------
-- Update
----------------------------------------------

function Eye:update(dt: number)
	if self.destroyed then return end
	if not self.white or not self.eyeModel then return end

	local socketCFrame = self.socketPart.CFrame

	-- 1. Timers
	-- Stagger timer
	if self.staggerTimer > 0 then
		self.staggerTimer = self.staggerTimer - dt
		if self.staggerTimer <= 0 and self.pendingStaggerState then
			self:_applyState(self.pendingStaggerState)
			self.pendingStaggerState = nil
		end
	end

	-- Anticipation timer
	if self.anticipationTimer > 0 then
		self.anticipationTimer = self.anticipationTimer - dt
		if self.anticipationTimer <= 0 and self.pendingStateData then
			local prevData = resolveScaledStateForSide(self.previousState, self.side, self.baseSizeMult)
			self:_applyStateTargets(self.pendingStateData, prevData)
			self.pendingStateData = nil
		end
	end

	-- Pupil swap timer
	if self.pupilSwapTimer > 0 then
		self.pupilSwapTimer = self.pupilSwapTimer - dt
		if self.pupilSwapTimer <= 0 and self.pendingPupilData then
			self:_applyPendingPupil(self.pendingPupilData)
			self.pendingPupilData = nil
		end
	end

	-- 2. Look-at
	self:_updateLookAt(dt)

	-- 3. Micro-saccade
	self:_updateSaccade(dt)

	-- 4. Blink
	local blinkSquash, blinkPupilHide = self:_updateBlink(dt)

	-- 5. Breathing
	local breathScale = self:_updateBreathing(dt)

	-- 6. Update all springs
	local s = self.springs
	s.whiteSize:update(dt)
	s.whiteColor:update(dt)
	s.whiteTransparency:update(dt)
	s.whiteShockOffset:update(dt)
	s.whiteShockRot:update(dt)
	s.whiteShockSize:update(dt)
	s.pupilSize:update(dt)
	s.pupilTransparency:update(dt)
	s.pupilColor:update(dt)
	s.pupilShockOffset:update(dt)
	s.pupilShockRot:update(dt)
	s.pupilShockSize:update(dt)
	s.heartSize:update(dt)
	s.heartTransparency:update(dt)
	s.crossedSize:update(dt)
	s.crossedTransparency:update(dt)
	s.eyebrowSize:update(dt)
	s.eyebrowOffset:update(dt)
	s.eyebrowRotZ:update(dt)
	s.eyebrowTransparency:update(dt)
	s.browShockOffset:update(dt)
	s.browShockRot:update(dt)
	s.browShockSize:update(dt)
	s.lookDirection:update(dt)
	s.saccade:update(dt)

	-- 7. Apply to parts

	-- 7a. White
	local white = self.white :: BasePart
	local whiteSize = clampVectorComponentsMin(s.whiteSize.p + s.whiteShockSize.p, 0.001) * breathScale
	whiteSize = Vector3.new(whiteSize.X, whiteSize.Y * blinkSquash, whiteSize.Z)
	white.Size = whiteSize
	white.Color = vecToColor(s.whiteColor.p)
	white.Transparency = s.whiteTransparency.p
	local whiteCFrame = socketCFrame * shockTransform(s.whiteShockOffset.p, s.whiteShockRot.p)
	white.CFrame = whiteCFrame

	-- Compute pupil positioning
	local lookDir = s.lookDirection.p + s.saccade.p
	local lookMag = lookDir.Magnitude
	if lookMag > 0.001 then
		lookDir = lookDir / lookMag
	else
		lookDir = Vector3.new(0, 0, -1)
	end
	-- Clamp so pupils can't rotate past the side of the head
	lookDir = clampLookDirection(lookDir)

	local pupilDistance = whiteSize.X * PUPIL_DISTANCE_RATIO
	local pupilLocalOffset = lookDir * pupilDistance + s.pupilShockOffset.p
	local pupilWorldPos = (whiteCFrame * CFrame.new(pupilLocalOffset)).Position

	-- Make pupil face outward along the look direction
	local pupilLookWorld = whiteCFrame:VectorToWorldSpace(lookDir)
	local pupilWorldCFrame = whiteCFrame * CFrame.new(pupilLocalOffset)
	if pupilLookWorld.Magnitude > 0.001 then
		pupilWorldCFrame = CFrame.lookAt(pupilWorldPos, pupilWorldPos + pupilLookWorld)
	end
	pupilWorldCFrame = pupilWorldCFrame * CFrame.Angles(s.pupilShockRot.p.X, s.pupilShockRot.p.Y, s.pupilShockRot.p.Z)

	-- 7b. Pupil
	local pupil = self.pupil :: BasePart
	pupil.Size = clampVectorComponentsMin(s.pupilSize.p + s.pupilShockSize.p, 0.001)
	pupil.Color = vecToColor(s.pupilColor.p)
	pupil.Transparency = math.clamp(s.pupilTransparency.p + blinkPupilHide, 0, 1)
	pupil.CFrame = pupilWorldCFrame

	-- 7c. HeartPupil
	if self.heartPupil then
		local heart = self.heartPupil :: BasePart
		heart.Size = clampVectorComponentsMin(s.heartSize.p + s.pupilShockSize.p, 0.001)
		heart.Transparency = math.clamp(s.heartTransparency.p + blinkPupilHide, 0, 1)
		-- HeartPupil needs to face the look direction but flipped (mesh faces -Z)
		local heartCFrame = pupilWorldCFrame * CFrame.Angles(0, math.pi, 0)
		heart.CFrame = heartCFrame
	end

	-- 7d. CrossedPupil (Model)
	if self.crossedPupil then
		self.crossedPupil:PivotTo(pupilWorldCFrame)
		local crossedScale = clampVectorComponentsMin(s.crossedSize.p + s.pupilShockSize.p, 0.001)
		local crossedTrans = math.clamp(s.crossedTransparency.p + blinkPupilHide, 0, 1)
		for _, part in self.crossedParts do
			part.Size = crossedScale
			part.Transparency = crossedTrans
		end
	end

	-- 7e. Eyebrow
	local eyebrow = self.eyebrow :: BasePart
	local browOffset = s.eyebrowOffset.p
	local browRotZ = s.eyebrowRotZ.p

	-- Slight look-direction influence on eyebrow
	local lookInfluence = s.lookDirection.p
	local browLookRotZ = lookInfluence.X * 0.1 -- subtle rotation based on horizontal gaze

	local browCFrame = socketCFrame
		* CFrame.new(browOffset)
		* CFrame.Angles(0, 0, browRotZ + browLookRotZ)
		* shockTransform(s.browShockOffset.p, s.browShockRot.p)
	eyebrow.CFrame = browCFrame
	eyebrow.Size = clampVectorComponentsMin(s.eyebrowSize.p + s.browShockSize.p, 0.001)
	eyebrow.Transparency = s.eyebrowTransparency.p
end

----------------------------------------------
-- Cleanup
----------------------------------------------

-- Stops updates but keeps the eye model alive in the instance tree.
-- Used when the socket leaves workspace (e.g. tool unequipped to backpack).
function Eye:deactivate()
	if self.destroyed then return end
	self.destroyed = true

	-- Nil out references so update() is a no-op, but do NOT Destroy the model
	self.eyeModel = nil
	self.white = nil
	self.pupil = nil
	self.heartPupil = nil
	self.crossedPupil = nil
	self.crossedParts = {}
	self.eyebrow = nil
end

-- Permanently removes the eye model from the game.
-- Used when the socket is truly gone (tag removed, animal destroyed).
function Eye:destroy()
	if self.destroyed then return end
	self.destroyed = true

	if self.eyeModel then
		self.eyeModel:Destroy()
		self.eyeModel = nil
	end

	self.white = nil
	self.pupil = nil
	self.heartPupil = nil
	self.crossedPupil = nil
	self.crossedParts = {}
	self.eyebrow = nil
end

----------------------------------------------
-- Module Exports
----------------------------------------------

Eye.TRACKING_STYLES = TRACKING_STYLES
Eye.STATE_DATA = STATE_DATA
Eye.DAMAGE_SHOCK_TRIGGER_RATIO = DAMAGE_SHOCK_TRIGGER_RATIO

return Eye
