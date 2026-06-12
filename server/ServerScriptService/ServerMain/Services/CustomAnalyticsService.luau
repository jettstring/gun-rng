local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ENABLED = true
local CLOUD_RUN_URL = "https://gunrng-analytics-ingestion-1058252910405.us-central1.run.app/ingest"
local INGEST_SECRET_NAME = "ingest"
local FLUSH_INTERVAL = 30
local MAX_BATCH_BYTES = 900_000
local MAX_EVENTS_PER_PLAYER = 500
local MAX_PENDING_BATCHES = 50
local MAX_RETRY_ATTEMPTS = 8
local RETRY_BACKOFF_BASE_SECONDS = 2
local RETRY_BACKOFF_MAX_SECONDS = 120
local SEND_POLL_INTERVAL = 4
local MIN_SEND_INTERVAL_SECONDS = 4
local CLOSE_DRAIN_SECONDS = 8
local CLOSE_DRAIN_INTERVAL = 2
-- Enemy income is aggregated; flush the running summary at this kill count.
local ENEMY_INCOME_FLUSH_KILLS = 250
local DEBUG_BATCH_EVENT_TYPE = "debug-batch-overflow"
local DEBUG_BATCH_EVENT_COUNT = 1200
local DEBUG_BATCH_PADDING_BYTES = 1000

local CustomAnalytics = {}
CustomAnalytics.__index = CustomAnalytics

local RESERVED_EVENT_KEYS = {
	eventId = true,
	eventType = true,
	eventVersion = true,
	playerId = true,
	timestamp = true,
	sessionId = true,
	experimentId = true,
}

export type Event = {
	eventId: string,
	eventType: string,
	eventVersion: number,
	playerId: number,
	timestamp: number,
	sessionId: string,
	experimentId: string?,
	[string]: any,
}

export type Batch = {
	placeId: number,
	placeVersion: number,
	serverJobId: string,
	serverStartTime: number,
	batchTime: number,
	events: { Event },
}

type PendingBatch = {
	payload: Batch,
	attemptCount: number,
	nextAttemptAt: number,
}

-- Cloud Run

local analyticsEnabled = ENABLED
local apiKey
if ENABLED then
	local success, result = pcall(function()
		return HttpService:GetSecret(INGEST_SECRET_NAME)
	end)
	if success then
		apiKey = result
	else
		analyticsEnabled = false
		warn("[CustomAnalytics] Secrets unavailable — analytics writes disabled for this session.")
	end
end

local function isAnalyticsEnabled(): boolean
	return ENABLED and analyticsEnabled and apiKey ~= nil
end

local function getRetryDelaySeconds(attemptCount: number): number
	local exponent = math.max(0, attemptCount - 1)
	local delay = RETRY_BACKOFF_BASE_SECONDS * (2 ^ exponent)
	return math.min(delay, RETRY_BACKOFF_MAX_SECONDS)
end

local function shallowCopyTable(source: { [string]: any }): { [string]: any }
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function sendBatch(data: { [string]: any }): (boolean, boolean, string?)
	if not isAnalyticsEnabled() then
		return false, false, "disabled"
	end

	local ok, result = pcall(function()
		local body = HttpService:JSONEncode(data)

		return HttpService:RequestAsync({
			Url = CLOUD_RUN_URL,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["X-Ingest-Key"] = apiKey,
			},
			Body = body,
		})
	end)

	if not ok then
		return false, true, "request failed: " .. tostring(result)
	end

	local response = result
	if response.StatusCode >= 200 and response.StatusCode < 300 then
		return true, false, nil
	end

	local msg = string.format("status %d: %s", response.StatusCode, response.Body)
	local retryable = response.StatusCode == 408
		or response.StatusCode == 429
		or response.StatusCode >= 500
	return false, retryable, msg
end

-- Service

function CustomAnalytics.new()
	local self = setmetatable({}, CustomAnalytics)
	self.placeVersion = game.PlaceVersion

	self.placeId = game.PlaceId
	self.serverJobId = game.JobId
	self.startTime = os.time()
	self.events = {} :: { Event }
	self.playerEventCounts = {} :: { [number]: number }
	self.playerLimitWarned = {} :: { [number]: boolean }
	self.playerSessionIds = {} :: { [number]: string }
	self.pendingBatches = {} :: { PendingBatch }
	self.lastSendAttemptTime = 0
	self.isSendInFlight = false
	self.totalBatches = 0
	self.started = false

	-- Per-player enemy income waiting for the next summary event.
	self.enemyIncome = {} :: { [number]: any }

	return self
end

function CustomAnalytics:Init(services)
	self.Services = services
end

function CustomAnalytics:Start()
	if self.started then
		return
	end
	self.started = true

	if not ENABLED then
		return
	end

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			self:flush()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SEND_POLL_INTERVAL)
			self:drainPendingBatches(false)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:FlushEnemyIncome(player.UserId, "exit")
		self:PlayerExit(player)
	end)

	game:BindToClose(function()
		self:flushAllEnemyIncome("shutdown")
		self:flush()
		local closeDeadline = os.clock() + CLOSE_DRAIN_SECONDS
		while #self.pendingBatches > 0 and os.clock() < closeDeadline do
			self:drainPendingBatches(true)
			task.wait(CLOSE_DRAIN_INTERVAL)
		end
		if #self.pendingBatches > 0 then
			warn(string.format("[CustomAnalytics] Shutdown ended with %d unsent analytics batches.", #self.pendingBatches))
		end
	end)
end


function CustomAnalytics:getSessionId(playerId: number): string
	local existingSessionId = self.playerSessionIds[playerId]
	if existingSessionId then
		return existingSessionId
	end

	local sessionId = HttpService:GenerateGUID(false)
	self.playerSessionIds[playerId] = sessionId
	return sessionId
end


export type CurrencyChangedEvent = {
	currency: string,
	amount: number,
	balance: number,
	source: string?,
	playTime: number,
}

function CustomAnalytics:AddCurrency(player: Player, event: CurrencyChangedEvent)
	self:addEvent("currency-changed", player.UserId, event)
end

export type PlayerEnterExit = {
	playTime: number,
}

function CustomAnalytics:PlayerEnter(playerId: number, event: PlayerEnterExit)
	self:addEvent("enter", playerId, event)
end
-- Fired on PlayerRemoving. Captures the player's final state, plus OPTIONAL payer
-- segment info from MonetizationService (every field optional — absent if the
-- service isn't registered yet, or has no segment data). Enum segments are stored
-- by name so they serialize to JSON.
function CustomAnalytics:PlayerExit(player: Player)
	if not isAnalyticsEnabled() then
		return
	end

	local userId = player.UserId

	local ok, err = pcall(function()
		local data: { [string]: any } = {
			playerState = self:buildPlayerState(player, true),
		}

		local monetizationService = self.Services and self.Services.MonetizationService
		if monetizationService then
			local gotInfo, info = pcall(function()
				return monetizationService:GetPayerInfo(player)
			end)
			if gotInfo and typeof(info) == "table" then
				local function enumName(value: any): any
					return if typeof(value) == "EnumItem" then value.Name else value
				end
				data.payerRestricted = info.paidRandomItemsRestricted
				data.activePayerStatus = enumName(info.activePayerStatus)
				data.whenUserFirstPlayed = enumName(info.whenUserFirstPlayed)
				data.platformSpenderStatus = enumName(info.platformSpenderStatus)
			end
		end

		self:addEvent("exit", userId, data)
	end)

	if not ok then
		warn("[CustomAnalytics] PlayerExit failed:", err)
	end

	self.playerSessionIds[userId] = nil
end

export type BuyGamepassEvent = {
	passName: string?,
	passId: number,
	playTime: number,
	money: number,
	gems: number,
}

function CustomAnalytics:BuyGamepass(
	playerId: number,
	event: BuyGamepassEvent
)
	self:addEvent("buy-gamepass", playerId, event)
end

export type RobuxEvent = {
	playTime: number,
	money: number,
	gems: number,
	PurchaseId: string,
	ProductId: number,
	ProductPurchaseChannel: number,
	CurrencySpent: number
}

function CustomAnalytics:Robux(
	playerId: number,
	event: RobuxEvent
)
	self:addEvent("robux", playerId, event)
end

-- Player snapshots and gameplay events

-- Best-effort analytics snapshot. Include skills only for rare key events.
function CustomAnalytics:buildPlayerState(player: Player, includeSkills: boolean?): { [string]: any }?
	local snapshot
	local ok, err = pcall(function()
		local services = self.Services
		local dataService = services and services.DataService
		local upgradeService = services and services.UpgradeService

		local profile = dataService and dataService:GetProfile(player)
		if not profile then
			return
		end

		local stats = profile.Stats
		snapshot = {
			rebirths = profile.Rebirths,
			currentZone = profile.CurrentZone,
			moneyBalance = profile.Money,
			dogtagsBalance = profile.Dogtags,
			playtimeTotal = if typeof(stats) == "table" then stats.Playtime else nil,
		}

		if upgradeService then
			-- Store resolved luck because formulas can change between patches.
			snapshot.luck = upgradeService:GetLuck(player)

			if includeSkills then
				local skillList = {}
				for skillId in pairs(upgradeService:GetOwnedSkills(player)) do
					table.insert(skillList, skillId)
				end
				table.sort(skillList)
				snapshot.unlockedSkills = skillList
			end
		end
	end)

	if not ok then
		warn("[CustomAnalytics] buildPlayerState failed:", err)
	end

	return snapshot
end

-- Rare events get the full snapshot, including unlocked skills.
function CustomAnalytics:emitKeyEvent(eventType: string, player: Player, info: { [string]: any }?)
	if not isAnalyticsEnabled() then
		return
	end
	local data = if typeof(info) == "table" then table.clone(info) else {}
	data.playerState = self:buildPlayerState(player, true)
	self:addEvent(eventType, player.UserId, data)
end

export type RebirthEvent = {
	fromRebirth: number,
	toRebirth: number,
	dogtagsSpent: number,
	moneyForfeited: number,
	zoneReached: number,
}
function CustomAnalytics:Rebirth(player: Player, event: RebirthEvent)
	self:emitKeyEvent("rebirth", player, event)
end

export type ZoneUnlockEvent = {
	zoneOrder: number,
	zoneName: string?,
	price: number,
}
function CustomAnalytics:ZoneUnlock(player: Player, event: ZoneUnlockEvent)
	self:emitKeyEvent("zone-unlock", player, event)
end

export type SkillUnlockEvent = {
	skillId: string,
	price: number,
}
function CustomAnalytics:SkillUnlock(player: Player, event: SkillUnlockEvent)
	self:emitKeyEvent("skill-unlock", player, event)
end

-- Enemy income
-- Kills are too frequent to log directly, so rewards are bucketed by zone and enemy type.

function CustomAnalytics:RecordEnemyKill(player: Player, zone: number, enemyType: string, money: number, dogtags: number)
	if not isAnalyticsEnabled() then
		return
	end

	local ok, err = pcall(function()
		zone = zone or 0
		enemyType = enemyType or "unknown"

		local userId = player.UserId
		local entry = self.enemyIncome[userId]
		if not entry then
			entry = { player = player, kills = 0, buckets = {} }
			self.enemyIncome[userId] = entry
		end
		entry.player = player

		local byZone = entry.buckets[zone]
		if not byZone then
			byZone = {}
			entry.buckets[zone] = byZone
		end

		local tally = byZone[enemyType]
		if not tally then
			tally = { kills = 0, money = 0, dogtags = 0 }
			byZone[enemyType] = tally
		end

		tally.kills += 1
		tally.money += money or 0
		tally.dogtags += dogtags or 0
		entry.kills += 1

		if entry.kills >= ENEMY_INCOME_FLUSH_KILLS then
			self:FlushEnemyIncome(userId, "kill-threshold")
		end
	end)

	if not ok then
		warn("[CustomAnalytics] RecordEnemyKill failed:", err)
	end
end

-- Emits and clears one player's enemy-income summary.
function CustomAnalytics:FlushEnemyIncome(userId: number, reason: string)
	if not isAnalyticsEnabled() then
		return
	end

	local entry = self.enemyIncome[userId]
	if not entry or entry.kills <= 0 then
		self.enemyIncome[userId] = nil
		return
	end
	self.enemyIncome[userId] = nil

	local ok, err = pcall(function()
		-- Array shape keeps BigQuery UNNEST simple.
		local breakdown = {}
		local totalKills, totalMoney, totalDogtags = 0, 0, 0

		for zone, byType in pairs(entry.buckets) do
			for enemyType, tally in pairs(byType) do
				table.insert(breakdown, {
					zone = zone,
					enemyType = enemyType,
					kills = tally.kills,
					money = tally.money,
					dogtags = tally.dogtags,
				})
				totalKills += tally.kills
				totalMoney += tally.money
				totalDogtags += tally.dogtags
			end
		end

		local data: { [string]: any } = {
			flushReason = reason,
			totalKills = totalKills,
			totalMoney = totalMoney,
			totalDogtags = totalDogtags,
			breakdown = breakdown,
		}

		-- Skip the skill list to keep this high-frequency payload smaller.
		if entry.player then
			data.playerState = self:buildPlayerState(entry.player, false)
		end

		self:addEvent("enemy-income", userId, data)
	end)

	if not ok then
		warn("[CustomAnalytics] FlushEnemyIncome failed:", err)
	end
end

function CustomAnalytics:flushAllEnemyIncome(reason: string)
	local userIds = {}
	for userId in pairs(self.enemyIncome) do
		table.insert(userIds, userId)
	end
	for _, userId in ipairs(userIds) do
		self:FlushEnemyIncome(userId, reason)
	end
end

function CustomAnalytics:ToggleEnable(enabled: boolean)
	if not ENABLED then
		return
	end

	print("Toggling A: ", enabled)
	analyticsEnabled = enabled
end

-- Debug: queue enough synthetic payload to exceed MAX_BATCH_BYTES.
function CustomAnalytics:DebugTriggerBatchOverflow(
	playerId: number?,
	eventCount: number?,
	payloadTemplate: { [string]: any }?
)
	if not isAnalyticsEnabled() then
		return
	end

	local targetPlayerId = playerId or 1
	local totalEvents = eventCount or DEBUG_BATCH_EVENT_COUNT
	local template = payloadTemplate or {
		starName = "x-ray binary star",
		rodName = "Starter Rod",
		bobberName = "Starter Bobber",
	}
	local eventType = template.eventType or DEBUG_BATCH_EVENT_TYPE
	local padding = template.debugPadding or string.rep("x", DEBUG_BATCH_PADDING_BYTES)

	warn(string.format(
		"[CustomAnalytics] Debug overflow start: playerId=%d events=%d eventType=%s",
		targetPlayerId,
		totalEvents,
		tostring(eventType)
	))

	for i = 1, totalEvents do
		-- Synthetic IDs avoid the per-player cap during overflow tests.
		local syntheticPlayerId = targetPlayerId + math.floor((i - 1) / MAX_EVENTS_PER_PLAYER)
		local payload = shallowCopyTable(template)
		payload.sequence = i
		payload.starName = payload.starName or "x-ray binary star"
		payload.starUuid = HttpService:GenerateGUID(false)
		payload.rodName = payload.rodName or "Starter Rod"
		payload.bobberName = payload.bobberName or "Starter Bobber"
		payload.clientTimestamp = payload.clientTimestamp or os.time()
		payload.debugPadding = payload.debugPadding or padding
		payload.eventType = nil

		self:addEvent(eventType, syntheticPlayerId, payload)
	end

	warn(string.format(
		"[CustomAnalytics] Debug overflow complete: queuedEvents=%d pendingBatches=%d uniqueSyntheticPlayers=%d",
		#self.events,
		#self.pendingBatches,
		math.floor((math.max(totalEvents, 1) - 1) / MAX_EVENTS_PER_PLAYER) + 1
	))
end

-- Debug: print and return outbox health.
function CustomAnalytics:DebugQueueHealth()
	local now = os.time()
	local pendingBatchCount = #self.pendingBatches
	local pendingEventCount = 0
	local maxAttemptCount = 0
	local nextRetryInSeconds = 0
	local oldestBatchAgeSeconds = 0

	for _, pending in ipairs(self.pendingBatches) do
		pendingEventCount += #pending.payload.events
		if pending.attemptCount > maxAttemptCount then
			maxAttemptCount = pending.attemptCount
		end
	end

	if pendingBatchCount > 0 then
		local oldestPending = self.pendingBatches[1]
		nextRetryInSeconds = math.max(0, oldestPending.nextAttemptAt - now)
		oldestBatchAgeSeconds = math.max(0, now - oldestPending.payload.batchTime)
	end

	local snapshot = {
		analyticsEnabled = isAnalyticsEnabled(),
		sendInFlight = self.isSendInFlight,
		pendingBatchCount = pendingBatchCount,
		pendingEventCount = pendingEventCount,
		activeQueueCapacity = MAX_PENDING_BATCHES,
		maxAttemptCount = maxAttemptCount,
		nextRetryInSeconds = nextRetryInSeconds,
		oldestBatchAgeSeconds = oldestBatchAgeSeconds,
		bufferedEventCount = #self.events,
		totalBatchesFlushed = self.totalBatches,
		lastSendAttemptEpoch = self.lastSendAttemptTime,
	}

	warn(string.format(
		"[CustomAnalytics] Queue health: enabled=%s inFlight=%s pendingBatches=%d pendingEvents=%d bufferedEvents=%d maxAttempt=%d nextRetryIn=%ds oldestBatchAge=%ds",
		tostring(snapshot.analyticsEnabled),
		tostring(snapshot.sendInFlight),
		snapshot.pendingBatchCount,
		snapshot.pendingEventCount,
		snapshot.bufferedEventCount,
		snapshot.maxAttemptCount,
		snapshot.nextRetryInSeconds,
		snapshot.oldestBatchAgeSeconds
	))

	return snapshot
end

function CustomAnalytics:enqueueBatch(batch: Batch)
	if not isAnalyticsEnabled() then
		return
	end

	if #self.pendingBatches >= MAX_PENDING_BATCHES then
		table.remove(self.pendingBatches, 1)
		warn(string.format(
			"[CustomAnalytics] Pending queue hit limit (%d). Dropping oldest batch to protect memory/request budget.",
			MAX_PENDING_BATCHES
		))
	end

	table.insert(self.pendingBatches, {
		payload = batch,
		attemptCount = 0,
		nextAttemptAt = os.time(),
	})
end

function CustomAnalytics:drainPendingBatches(force: boolean)
	if not isAnalyticsEnabled() then
		return
	end

	if self.isSendInFlight then
		return
	end

	local pending = self.pendingBatches[1]
	if pending == nil then
		return
	end

	local now = os.time()
	if not force and now - self.lastSendAttemptTime < MIN_SEND_INTERVAL_SECONDS then
		return
	end

	if not force and now < pending.nextAttemptAt then
		return
	end

	self.lastSendAttemptTime = now
	self.isSendInFlight = true
	local success, retryable, reason = sendBatch(pending.payload)
	self.isSendInFlight = false

	if success then
		table.remove(self.pendingBatches, 1)
		return
	end

	pending.attemptCount += 1
	if not retryable then
		warn("[CustomAnalytics] Dropping non-retryable ingestion failure:", reason or "unknown error")
		table.remove(self.pendingBatches, 1)
		return
	end

	if pending.attemptCount >= MAX_RETRY_ATTEMPTS then
		warn(string.format(
			"[CustomAnalytics] Dropping batch after %d retry attempts. Last error: %s",
			pending.attemptCount,
			reason or "unknown error"
		))
		table.remove(self.pendingBatches, 1)
		return
	end

	local delaySeconds = getRetryDelaySeconds(pending.attemptCount)
	pending.nextAttemptAt = now + delaySeconds
	warn(string.format(
		"[CustomAnalytics] send failed (attempt %d/%d). Retrying in %ds. Error: %s",
		pending.attemptCount,
		MAX_RETRY_ATTEMPTS,
		delaySeconds,
		reason or "unknown error"
	))
end

function CustomAnalytics:addEvent(eventType: string, playerId: number, data: { [string]: any }?)
	if not isAnalyticsEnabled() then
		return
	end

	local success, err = pcall(function()
		-- Per-player rate limit
		local count = self.playerEventCounts[playerId] or 0
		if count >= MAX_EVENTS_PER_PLAYER then
			if not self.playerLimitWarned[playerId] then
				self.playerLimitWarned[playerId] = true
				warn(string.format("[CustomAnalytics] Player %d hit %d event limit for this batch — dropping excess events.", playerId, MAX_EVENTS_PER_PLAYER))
			end
			return
		end
		self.playerEventCounts[playerId] = count + 1

		local event: Event = {
			eventId = HttpService:GenerateGUID(false),
			eventType = eventType,
			eventVersion = if data and data.eventVersion ~= nil then data.eventVersion else 1,
			playerId = playerId,
			timestamp = os.time(),
			sessionId = self:getSessionId(playerId),
		}

		if data and data.experimentId ~= nil then
			event.experimentId = data.experimentId
		end

		if data then
			for key, value in pairs(data) do
				if not RESERVED_EVENT_KEYS[key] then
					event[key] = value
				end
			end
		end

		table.insert(self.events, event)

		-- Avoid encoding on every event; check once the batch is plausibly large.
		if #self.events > 500 then
			local batchBytes = #HttpService:JSONEncode(self.events)
			if batchBytes > MAX_BATCH_BYTES then
				self:flush()
			end
		end
	end)

	if not success then
		warn("[CustomAnalytics] addEvent failed:", err)
	end
end

function CustomAnalytics:flush()
	if not isAnalyticsEnabled() then
		return
	end

	if #self.events == 0 then
		return
	end

	local events = self.events
	self.events = {}
	self.playerEventCounts = {}
	self.playerLimitWarned = {}
	self.totalBatches += 1

	local batch: Batch = {
		placeId = self.placeId,
		placeVersion = self.placeVersion,
		serverJobId = self.serverJobId,
		serverStartTime = self.startTime,
		batchTime = os.time(),
		events = events,
	}
	self:enqueueBatch(batch)
	self:drainPendingBatches(false)
end

return CustomAnalytics.new()
