local Settings = {
    Enabled = true,
    Delay = 15, -- 3-20 detik menunggu di atas telur target
    Speed = 60, -- 20-100, untuk reposition/recovery dan perangkat FPS rendah
    Names = {},
    Rarities = {},
    Areas = {},
    Mutations = {},
    MinValue = 0,
    MinWeight = 0,
}

if not game:IsLoaded() then game.Loaded:Wait() end
local env = getgenv and getgenv() or _G
if type(env.LogicTP) == "table" and type(env.LogicTP.Destroy) == "function" then
    env.LogicTP.Destroy()
end
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "[LogicTP] Jalankan dari client")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local runtimeEnv = {}
local Config = { StealHoldSeconds = Settings.Delay }
local alive = true
local function sessionAlive() return alive end
local function resolveObjectsRoot()
    return Workspace:FindFirstChild("World") or Workspace:FindFirstChild("__OBJECTS")
end
local fps = 60
local fpsConnection = RunService.Heartbeat:Connect(function(dt)
    if dt > 0 then fps = fps * 0.9 + (1 / dt) * 0.1 end
end)
local function currentFps() return fps end

local catalog = (function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Assets = require(ReplicatedStorage.Data.Assets)
	local Mutations = require(ReplicatedStorage.Shared.Modules.Mutations)
	local Catalog = {}
	local RARITY_ORDER = {
		Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
		Mythic = 6, Cosmic = 7, Secret = 8, Eternal = 9, Divine = 10,
	}
	function Catalog.resolveMutationId(value)
		if type(value) ~= "string" then return nil end
		if Mutations.IdSet[value] then return value end
		for id in pairs(Mutations.Ids()) do
			if id ~= Mutations.NO_MUTATION and Mutations.LabelOf(id) == value then
				return id
			end
		end
		return nil
	end
	function Catalog.resolve(record)
		local config = record and Assets.Directory[record.AssetCategory]
		local rarity = config and config.Rarity
		local rarityName = rarity and (rarity.DisplayName or rarity._id) or "Unknown"
		return {
			name = config and (config.DisplayName or config._id) or (record and record.AssetCategory) or "Unknown",
			category = record and record.AssetCategory or "Unknown",
			rarity = rarityName,
			rarityRank = RARITY_ORDER[rarityName] or 0,
			rarityColor = rarity and rarity.Color or nil,
		}
	end
	return Catalog
	end)()
local EggRuntime = (function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local EggCmds = require(ReplicatedStorage.Client.EggState)
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	local EggWorld = Remotes.EggWorld
	local AreaEggs = require(ReplicatedStorage.Shared.Types.AreaEggs)
	local AreaEggSlotIdentity = require(ReplicatedStorage.Shared.Util.AreaEggSlotIdentity)
	local AreaEggResetWall = require(ReplicatedStorage.Client.AreaEggResetWall)
	local AssetEarnings = require(ReplicatedStorage.Shared.Util.AssetEarnings)
	local PlotState = require(ReplicatedStorage.Client.PlotState)
	local MOVEMENT_SPEED_MULTIPLIER = 10
	local MIN_MOVEMENT_SPEED_INPUT = 20
	local MAX_MOVEMENT_SPEED_INPUT = 100
	local DEFAULT_MOVEMENT_SPEED_INPUT = 60
	local NEXT_TARGET_HANDOFF_SECONDS = 0.1
	local MIN_MOVEMENT_SPEED = MIN_MOVEMENT_SPEED_INPUT * MOVEMENT_SPEED_MULTIPLIER
	local MAX_MOVEMENT_SPEED = MAX_MOVEMENT_SPEED_INPUT * MOVEMENT_SPEED_MULTIPLIER
	local DEFAULT_MOVEMENT_SPEED = DEFAULT_MOVEMENT_SPEED_INPUT * MOVEMENT_SPEED_MULTIPLIER

	local function maxMoveSpeed()
		return MAX_MOVEMENT_SPEED
	end
	local MOVEMENT_SPOOF_KEY = "__LimboStealAnEggMovementSpoof"
	local MOVEMENT_SPOOF_VERSION = 436
	local INTEGRITY_SPOOF_KEY = "__LimboStealAnEggIntegritySpoof"
	local INTEGRITY_SIGNAL_NAME = "ClientCharacter: GetDebugSnapshot"
	local INTEGRITY_SAMPLE_FIELDS = {
		"LastObservedSample",
		"LastSample",
		"LastGoodSample",
		"LastGameplayTrustedSample",
		"LastValidatedSample",
		"LastValidatedGroundedSample",
		"LastConfirmedGroundSample",
		"CandidateGroundedSample",
	}
	local EGG_ARRIVAL_CLEARANCE = 0.15
	local HOVER_PAD_SIZE_XZ = 8
	local HOVER_PAD_THICKNESS = 1
	local HOVER_PAD_NAME = "__LogicTPHoverPad"
	local HOVER_PAD_OWNER_ATTRIBUTE = "LimboRuntimeOwner"
	local SAFE_ZONE_CFRAME = CFrame.new(
		544.40094, 70.5743103, -364.193054,
		0.0320008546, -1.19248071e-07, -0.999487817,
		-1.76635826e-08, 1, -1.19874713e-07,
		0.999487817, 2.14906297e-08, 0.0320008546
	)
	local SAFE_ZONE_POSITION = SAFE_ZONE_CFRAME.Position

	local FOREST_TRANSFER_ATTEMPTS = 3
	local FOREST_DROP_SETTLE = 0.85  -- wait after a drop request for the server to release

	local SETTLE_CAP_DEFAULT = 13   -- unknown area -> safest (schedule max)
	local SETTLE_BY_AREA = {
		["Forest"] = 1.0,   ["Lake"] = 2.5,          ["Desert"] = 3.0,        ["Jungle"] = 4.5,
		["Snow"] = 5.5,     ["Volcano"] = 6.5,        ["Abyss Ocean"] = 7.5,   ["Prehistoric"] = 8.5,
		["Cosmic"] = 10.0,  ["Cherry Blossom"] = 11.5, ["Titan Temple"] = 12.5, ["Light Dark"] = 13.0,
	}

	local GLIDE_SPEED = 5000
	local FOREST_DROP_RELAY = CFrame.new(
	793.59216308594, 70.574203491211, -298.70162963867,
	0.35004562139511, 7.3665610500484e-08, 0.93673264980316,
	-8.2453034622176e-08, 1, -4.7829320948267e-08,
	-0.93673264980316, -6.0494002696032e-08, 0.35004562139511
)

	local HOVER_DESYNC_HEIGHT = 14

	local SAFE_ZONE_HORIZONTAL_RADIUS = 30
	local SAFE_ZONE_VERTICAL_TOLERANCE = 18
	local SAFE_TELEPORT_STABLE_SECONDS = 0.35
	local SAFE_TELEPORT_TIMEOUT_SECONDS = 2
	local SAFE_TELEPORT_RETRY_SECONDS = 0.1
	local TREADMILL_DECOY_NAME = "__LogicTPDecoy"
	local TREADMILL_DECOY_REMOVE_CLASSES = {
		Script = true,
		LocalScript = true,
		BillboardGui = true,
		Sound = true,
	}
	local CARRY_RETRY_INTERVAL = 0.25
	local CARRY_CONFIRM_TIMEOUT_SECONDS = 5
	local CARRY_REAPPROACH_DISTANCE = 10
	local CARRY_STATE_GRACE = 0.03
	local TARGET_GONE_HANDOFF_GRACE = 0.65
	local INTEGRITY_SPEED_HEADROOM = 1.35
	local LONG_FRAME_CLAMP = 0.15
	local MOVEMENT_BASELINE_PADDING = 24
	local CORRECTION_DISTANCE_EPSILON = 2
	local CORRECTION_SLOWDOWN_SECONDS = 0.5
	local CORRECTION_SPEED_FACTOR = 0.45
	local MOVEMENT_ARRIVAL_HOLD = 0.4
	local PLAYER_TRAP_NAME = "PlayerTrap"
	local LEGACY_TRAP_MODEL_NAME = "Trap"
	local EggRuntime = {}
	EggRuntime.__index = EggRuntime
	local _Stats = game:GetService("Stats")
	local function requestFieldEggCarry(uid, slotKey)
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				end)
		end
		local ping = 0
		pcall(function() ping = _Stats.Network.ServerStats.Ping:GetValue() end)
		task.wait(math.max(0.3, ping * 2.5 / 1000))
		local payload = { Uid = uid }
		if slotKey ~= nil then
			payload.FirstAreaSlotKey = slotKey
		end
		local result, reason = EggWorld.AskFieldEggCarry:InvokeServer(payload)
		return result == true, typeof(reason) == "string" and reason or nil
	end
	local function connect(signal, callback, connections)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
		return connection
	end
	local function disconnectAll(connections)
		for _, connection in ipairs(connections) do
			pcall(connection.Disconnect, connection)
		end
		table.clear(connections)
	end
	local function listContains(list, value)
		for _, candidate in ipairs(list or {}) do
			if candidate == value then
				return true
			end
		end
		return false
	end
	local resolveEggRate
	local function applyKillPartIgnore(character)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			root:SetAttribute("KillPartIgnore", true)
		end
	end
	local function stopHealthPinner(self)
		if self._healthPinner then
			pcall(self._healthPinner.Disconnect, self._healthPinner)
			self._healthPinner = nil
		end
		if self._healthChangedConnection then
			pcall(self._healthChangedConnection.Disconnect, self._healthChangedConnection)
			self._healthChangedConnection = nil
		end
	end
	local function startHealthPinner(self, char)
		stopHealthPinner(self)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not hum then return false end
		local maxHp = math.max(hum.MaxHealth, 100)
		local repairing = false
		local lastRepairAt = 0
		local function repair()
			if repairing or self.destroyed or LocalPlayer.Character ~= char or not hum.Parent then return end
			local now = os.clock()
			if now - lastRepairAt < 0.1 and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
				return
			end
			lastRepairAt = now
			repairing = true
			pcall(function()
				hum.BreakJointsOnDeath = false
				hum.RequiresNeck = false
				hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
				hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
				hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
				if hum.Health <= 0 then hum.Health = maxHp end
				if hum:GetState() == Enum.HumanoidStateType.Dead then
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end
				if root and root.Parent == char and root.Anchored then
					root.Anchored = false
				end
				end)
			repairing = false
		end
		repair()
		self._healthChangedConnection = hum.HealthChanged:Connect(function(health)
			if health <= 0 or health < maxHp then repair() end
			end)
		self._healthPinner = RunService.Heartbeat:Connect(repair)
		return true
	end
	local function restoreHumanoid(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		pcall(function()
			if humanoid.Health <= 0 then
				humanoid.Health = math.max(humanoid.MaxHealth, 1)
			end
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
			humanoid.BreakJointsOnDeath = true
			humanoid.RequiresNeck = true
			end)
	end
	local function environment()
		return runtimeEnv
	end
	local function getMovementSpoof()
		local env = environment()
		local existing = env[MOVEMENT_SPOOF_KEY]
		if type(existing) ~= "table" or existing.Version ~= MOVEMENT_SPOOF_VERSION then
			if type(existing) == "table" then existing.Enabled = false end
			existing = {
				Version = MOVEMENT_SPOOF_VERSION,
				Installed = false,
				Enabled = false,
				Mode = "StateBaseline",
				Humanoid = nil,
				RootPart = nil,
				WalkSpeed = DEFAULT_MOVEMENT_SPEED,
			}
			env[MOVEMENT_SPOOF_KEY] = existing
		end
		return existing
	end
	local function setMovementSpoof(character, speed)
		local holder = getMovementSpoof()
		if not holder then
			return false
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		holder.Humanoid = humanoid
		holder.RootPart = root
		holder.WalkSpeed = math.clamp(
			tonumber(speed) or DEFAULT_MOVEMENT_SPEED,
			MIN_MOVEMENT_SPEED,
			MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM
		)
		holder.Enabled = false
		return humanoid ~= nil and root ~= nil
	end
	local function clearMovementSpoof()
		local holder = environment()[MOVEMENT_SPOOF_KEY]
		if type(holder) == "table" then
			holder.Enabled = false
			holder.Humanoid = nil
			holder.RootPart = nil
		end
	end
	local function findIntegrityStateNow(player, humanoid, root)
		local found
		if type(getcallbackvalue) == "function" and type(debug) == "table" and type(debug.getupvalue) == "function" then
			local signalModule = ReplicatedStorage:FindFirstChild("Packages")
			and ReplicatedStorage.Packages:FindFirstChild("Signal")
			if signalModule then
				local okSig, Signal = pcall(require, signalModule)
				if okSig and type(Signal) == "table" and type(Signal.Invoked) == "function" then
					local okBind, bindable = pcall(Signal.Invoked, INTEGRITY_SIGNAL_NAME)
					if okBind and bindable then
						local okCb, callback = pcall(getcallbackvalue, bindable, "OnInvoke")
						if okCb and type(callback) == "function" then
							local okInfo, info = pcall(debug.getinfo, callback)
							if okInfo then
								local function scan(value, depth, seen)
									if found or type(value) ~= "table" or depth > 3 or seen[value] then return end
									seen[value] = true
									if rawget(value, "Player") == player
									and rawget(value, "Character") == player.Character
									and rawget(value, "Humanoid") == humanoid
									and rawget(value, "RootPart") == root
									and type(rawget(value, "SampleHistory")) == "table"
									and type(rawget(value, "Evidence")) == "table"
									then
										found = value
										return
									end
									local scanned = 0
									for _, child in pairs(value) do
										scanned = scanned + 1
										if scanned > 128 then break end
										if type(child) == "table" then scan(child, depth + 1, seen) end
									end
								end
								for idx = 1, info.nups or 0 do
									local okUp, upvalue = pcall(debug.getupvalue, callback, idx)
									if okUp and type(upvalue) == "table" then
										scan(upvalue, 0, {})
										if found then break end
									end
								end
							end
						end
					end
				end
			end
		end
		if not found and type(getgc) == "function" then
			local okGc, objects = pcall(getgc, true)
			if okGc and type(objects) == "table" then
				for _, obj in ipairs(objects) do
					if type(obj) == "table"
					and rawget(obj, "Player") == player
					and rawget(obj, "Character") == player.Character
					and rawget(obj, "Humanoid") == humanoid
					and rawget(obj, "RootPart") == root
					and type(rawget(obj, "SampleHistory")) == "table"
					and type(rawget(obj, "Evidence")) == "table"
					then
						found = obj
						break
					end
				end
			end
		end
		return found
	end
	local integrityScanRuntime = { busy = false, nextAt = 0, misses = 0, found = nil }
	local function findIntegrityState(player, humanoid, root)
		local cached = integrityScanRuntime.found
		if type(cached) == "table"
		and rawget(cached, "Player") == player
		and rawget(cached, "Character") == player.Character
		and rawget(cached, "Humanoid") == humanoid
		and rawget(cached, "RootPart") == root
		then
			return cached
		end
		if integrityScanRuntime.busy or os.clock() < integrityScanRuntime.nextAt then
			return nil
		end
		integrityScanRuntime.busy = true
		task.spawn(function()
			task.wait()
			local ok, found = pcall(findIntegrityStateNow, player, humanoid, root)
			found = ok and found or nil
			integrityScanRuntime.found = found
			integrityScanRuntime.misses = found and 0 or integrityScanRuntime.misses + 1
			integrityScanRuntime.nextAt = os.clock() + (found and 0.2 or (integrityScanRuntime.misses >= 5 and 10 or 1))
			integrityScanRuntime.busy = false
			end)
		return nil
	end
	local function patchIntegrityState(state, speed, travelVelocity)
		if type(state) ~= "table" then
			return false
		end
		local root = rawget(state, "RootPart")
		local rootCFrame = root and root.Parent and root.CFrame or nil
		local rootPosition = rootCFrame and rootCFrame.Position or nil
		local coherentVelocity = typeof(travelVelocity) == "Vector3" and travelVelocity or Vector3.zero
		local function patchSample(sample)
			if type(sample) == "table" then
				rawset(sample, "WalkSpeed", speed)
				if rootCFrame then
					rawset(sample, "CFrame", rootCFrame)
					rawset(sample, "Position", rootPosition)
					rawset(sample, "LinearVelocity", coherentVelocity)
					rawset(sample, "AngularVelocity", Vector3.zero)
				end
			end
		end
		for _, field in ipairs(INTEGRITY_SAMPLE_FIELDS) do
			patchSample(rawget(state, field))
		end
		for _, sample in pairs(rawget(state, "SampleHistory") or {}) do
			patchSample(sample)
		end
		for _, sample in pairs(rawget(state, "SafeGroundCheckpoints") or {}) do
			patchSample(sample)
		end
		local evidence = rawget(state, "Evidence")
		if type(evidence) == "table" then
			evidence.Speed = 0
			evidence.Teleport = 0
			evidence.Flight = 0
		end
		local impulse = rawget(state, "ImpulseContext")
		if type(impulse) == "table" then
			local horizontalSpeed = math.max(tonumber(impulse.MaxHorizontalSpeed) or 0, speed)
			local duration = math.max(
				(tonumber(impulse.ExpiresAt) or 0) - (tonumber(impulse.StartedAt) or 0),
				LONG_FRAME_CLAMP
			)
			impulse.MaxHorizontalSpeed = horizontalSpeed
			if rootPosition then impulse.OriginPosition = rootPosition end
			impulse.MaxHorizontalDistance = math.max(
				tonumber(impulse.MaxHorizontalDistance) or 0,
				horizontalSpeed * duration + MOVEMENT_BASELINE_PADDING * 2
			)
			patchSample(impulse.PreMovementSafeSample)
		end
		if rawget(state, "CorrectionContext") == nil then
			rawset(state, "FirstSuspiciousAt", nil)
			if rawget(state, "ThreatLevel") == "Observing" then
				rawset(state, "ThreatLevel", "Trusted")
			end
		end
		return true
	end
	local function getIntegritySpoof()
		local env = environment()
		local holder = env[INTEGRITY_SPOOF_KEY]
		if type(holder) ~= "table" then
			holder = {}
			env[INTEGRITY_SPOOF_KEY] = holder
		end
		return holder
	end
	local function integrityStateMatches(state, humanoid, root)
		return type(state) == "table"
		and rawget(state, "Player") == LocalPlayer
		and rawget(state, "Character") == LocalPlayer.Character
		and rawget(state, "Humanoid") == humanoid
		and rawget(state, "RootPart") == root
	end
	local function integrityStateCanTravel(state, humanoid, root)
		return integrityStateMatches(state, humanoid, root)
	end
	local function setIntegritySpoof(humanoid, root, speed)
		local holder = getIntegritySpoof()
		local state = holder.State
		if not integrityStateMatches(state, humanoid, root) then
			local now = os.clock()
			if now < (holder.NextSearchAt or 0) then return false end
			holder.NextSearchAt = now + 0.2
			state = findIntegrityState(LocalPlayer, humanoid, root)
		end
		if not state then
			return false
		end
		if not integrityStateCanTravel(state, humanoid, root) then
			holder.Enabled = false
			holder.Humanoid = humanoid
			holder.RootPart = root
			holder.State = state
			return false
		end
		holder.NextSearchAt = 0
		holder.Enabled = true
		holder.Humanoid = humanoid
		holder.RootPart = root
		holder.State = state
		holder.WalkSpeed = math.clamp(speed * INTEGRITY_SPEED_HEADROOM, MIN_MOVEMENT_SPEED, MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM)
		holder.TravelVelocity = Vector3.zero
		patchIntegrityState(state, holder.WalkSpeed, holder.TravelVelocity)
		return true
	end
	local function refreshIntegritySpoof(humanoid, root, speed, travelVelocity)
		local holder = environment()[INTEGRITY_SPOOF_KEY]
		if type(holder) ~= "table"
		or not holder.Enabled
		or holder.Humanoid ~= humanoid
		or holder.RootPart ~= root
		or not integrityStateCanTravel(holder.State, humanoid, root)
		then
			return false
		end
		holder.WalkSpeed = math.clamp(speed * INTEGRITY_SPEED_HEADROOM, MIN_MOVEMENT_SPEED, MAX_MOVEMENT_SPEED * INTEGRITY_SPEED_HEADROOM)
		if typeof(travelVelocity) == "Vector3" then
			holder.TravelVelocity = travelVelocity
		elseif typeof(holder.TravelVelocity) ~= "Vector3" then
			holder.TravelVelocity = Vector3.zero
		end
		return patchIntegrityState(holder.State, holder.WalkSpeed, holder.TravelVelocity)
	end
	local function clearIntegritySpoof(humanoid)
		local holder = environment()[INTEGRITY_SPOOF_KEY]
		if type(holder) ~= "table" then
			return
		end
		if humanoid == nil or holder.Humanoid == humanoid then
			holder.Enabled = false
			holder.Humanoid = nil
			holder.RootPart = nil
			holder.State = nil
			holder.TravelVelocity = nil
			holder.NextSearchAt = 0
		end
	end
	local function hasSelectedMutation(record, selected)
		if #selected == 0 then
			return true
		end
		for _, mutation in ipairs(record.Mutations or {}) do
			if listContains(selected, mutation) then
				return true
			end
		end
		return record.BaseMutation ~= nil and listContains(selected, record.BaseMutation)
	end
	function EggRuntime.new(catalog)
		local self = setmetatable({}, EggRuntime)
		self.catalog = catalog
		self.connections = {}
		self.listeners = {}
		self.records = {}
		self.enabled = false
		self.userStealEnabled = false

		self.skippedEggs = {}

		self.running = false
		self.safeStarting = false
		self.movementRetryPending = false
		self.destroyed = false
		self.resetBlocked = AreaEggResetWall.IsSealed()
		self.gateOpenAt = self.resetBlocked and math.huge or os.clock()
		self.activeTween = nil
		self.activeTarget = nil

		self.carry = { active = false, uid = nil, generation = 0 }
		self.carryWorker = nil
		self.tweenRecoveryUid = nil
		self.planGeneration = 0
		self.treadmillDecoy = nil
		self.treadmillDecoyCamera = nil
		self.treadmillDecoyCameraConnection = nil
		self.treadmillDecoyCharacterConnection = nil
		self.treadmillPopupConnection = nil
		self.treadmillDecoyRealTransparency = nil
		self.hoverPadOwnerId = string.format("%s:%0.6f", tostring(self), os.clock())
		self.instantPhase = nil
		self.primerUid = nil
		self.targetUid = nil
		self.hitTimer = nil
		self.guardHitBoostInstalled = false
		self.stats = {
			status = self.resetBlocked and "Reset wall closed" or "Ready",
			available = 0,
			matching = 0,
			lastTarget = "None",
			lastResult = "Idle",
		}
		self.config = {
			speed = DEFAULT_MOVEMENT_SPEED,
			antiTrap = true,
			minWeightKg = 0,

			minValuePerSec = 0,
			rarityEnabled = false,
			rarities = {},
			nameEnabled = false,
			names = {},
			areaEnabled = false,
			areas = {},
			mutationEnabled = false,
			mutations = {},
		}

		if LocalPlayer.Character then
			applyKillPartIgnore(LocalPlayer.Character)
			local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function()
					hum.BreakJointsOnDeath = false
					hum.RequiresNeck = false
					hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
					hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
					hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
					end)
			end
			startHealthPinner(self, LocalPlayer.Character)
		end
		local okWeight, weightUtil = pcall(function()
			return require(ReplicatedStorage.Shared.Util.EggRecords)
			end)
		self.weightUtil = okWeight and type(weightUtil.WeightKgForScale) == "function" and weightUtil or nil
		local function watchTrapContainer(container)
			if not container then
				return
			end
			connect(container.DescendantAdded, function(instance)
				if self.config.antiTrap then
					self:_purgeTrap(instance)
				end
				end, self.connections)
		end
		watchTrapContainer(workspace:FindFirstChild("Transient"))
		watchTrapContainer(workspace:FindFirstChild("__DEBRIS"))
		if self.config.antiTrap then self:_purgeTraps() end
		connect(workspace.ChildAdded, function(child)
			if child.Name == "Transient" or child.Name == "__DEBRIS" then
				watchTrapContainer(child)
				if self.config.antiTrap then
					self:_purgeTraps()
				end
			end
			end, self.connections)
		self:_replaceSnapshot(EggCmds.ReadFieldEggs())
		connect(EggCmds.FieldRefreshed, function(snapshot)
			self:_replaceSnapshot(snapshot)
			end, self.connections)
		connect(EggCmds.FieldShifted, function(record)
			self.records[record.Uid] = record
			self:_refreshCounts()
			end, self.connections)
		connect(EggCmds.FieldGone, function(uid)
			self.records[uid] = nil
			if self.activeTarget and self.activeTarget.Uid == uid then
				if self.carry.active and self.carry.uid == uid then
					self:_refreshCounts()
					return
				end
				self.carryAttemptToken = nil
				self:_clearArrivalHold(uid)
				if self.activeTween and self.activeTween.Cancel then
					pcall(self.activeTween.Cancel, self.activeTween)
				end
				local target = self.activeTarget
				task.delay(TARGET_GONE_HANDOFF_GRACE, function()
					if self.destroyed or not self.enabled then return end
					if self.carry.active and self.carry.uid == uid then return end
					if self.activeTarget == target and target.Uid == uid then
						self:_finish("Target removed — continuing")
					end
					end)
			end
			self:_refreshCounts()
			end, self.connections)
		connect(EggCmds.ResetCountdown, function()
			self:_closeGate("Egg reset countdown")
			end, self.connections)
		connect(EggCmds.ResetFade, function()
			self:_closeGate("Egg reset teleport")
			end, self.connections)
		connect(AreaEggResetWall.Changed, function(closed)
			if closed then
				self:_closeGate("Reset wall closed")
			else
				self.resetBlocked = false
				self.gateOpenAt = os.clock()
				self.safeStarting = false
				self.running = false
				self:_setStatus(self.enabled and "Searching" or "Ready")
				self:_schedule()
			end
			end, self.connections)
		connect(LocalPlayer.CharacterRemoving, function()
			self:_cleanupInstantSteal()
			self:_hideTreadmillDecoy()
			self._forestDropInProgress = nil
			self._instantReturnToken = nil
			self.carry.generation += 1
			self:_invalidateCarryWorker()
			self.carry.active = false
			self.carry.uid = nil
			self.safeStarting = false
			self.planGeneration += 1
			self:_cancelTween("Character resetting")
			self:_stopMovementProtection()
			end, self.connections)
		connect(RunService.Heartbeat, function()
			if self.destroyed then return end
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local velocity = root.AssemblyLinearVelocity
			if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 400
			or math.abs(velocity.Y) > 400
			then
				root.AssemblyLinearVelocity = Vector3.new(
					math.clamp(velocity.X, -100, 100),
					math.clamp(velocity.Y, -100, 100),
					math.clamp(velocity.Z, -100, 100)
				)
			end
			end, self.connections)
		connect(LocalPlayer.CharacterAdded, function(character)
			self:_hideTreadmillDecoy()
			applyKillPartIgnore(character)
			local freshHum = character:FindFirstChildOfClass("Humanoid")
			if freshHum then
				pcall(function()
					freshHum.BreakJointsOnDeath = false
					freshHum.RequiresNeck = false
					freshHum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
					freshHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
					freshHum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
					end)
			end
			startHealthPinner(self, character)
			task.delay(0.25, function()
				if not self.destroyed and self.enabled then
					self:_startMovementProtection()
				end
				end)
			task.delay(1, function()
				if not self.destroyed and self.enabled and self:_wallOpen() then
					self:_schedule()
				end
				end)
			end, self.connections)
		connect(EggCmds.CarryChanged, function(state)
			if state.IsCarrying then
				if self.running and self.activeTarget and state.Uid == self.activeTarget.Uid then
					if self.carry.active and self.carry.uid == state.Uid then return end
					if self.instantPhase == "priming" and state.Uid == self.primerUid then
						self.carry.active = true
						self.carry.uid = state.Uid
						self:_clearArrivalHold(state.Uid)
						self:_enterBaitWait()
						return
					end
					self.carry.generation += 1
					self:_invalidateCarryWorker()
					self:_clearArrivalHold(state.Uid)

					self.carry.active = true
					self.carry.uid = state.Uid
					self.carryStartTime = os.clock()
					self.carryStartPos = (self.activeTarget and self.activeTarget.BottomCFrame and self.activeTarget.BottomCFrame.Position)
					or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position)
					if self.tweenRecoveryUid == state.Uid then
						self.tweenRecoveryUid = nil
					end
					self.stats.lastResult = "Carry confirmed"
					self:_notify()
					self.carryAttemptToken = nil
					if self.activeTween and self.activeTween.Cancel then
						pcall(self.activeTween.Cancel, self.activeTween)
					end
					task.defer(function()
						if not self.destroyed and self.enabled
						and self.carry.uid == state.Uid
						and self:_hasConfirmedCarry(state.Uid)
						then
							self:_returnToSafe()
						end
						end)
				end
				return
			end
			if self.carry.uid ~= nil and state.Uid ~= nil and state.Uid ~= self.carry.uid then
				return
			end
			local droppedUid = state.Uid
			or self.carry.uid
			or (self.activeTarget and self.activeTarget.Uid)
			local wasTracked = self.carry.active
			self.carry.generation += 1
			local releaseGeneration = self.carry.generation
			self:_invalidateCarryWorker()
			if self.activeTween and self.activeTween.Cancel then
				pcall(self.activeTween.Cancel, self.activeTween)
			end
			self.carry.active = false
			self.carry.uid = nil
			if self.instantPhase == "priming" and (state.Uid == self.primerUid or droppedUid == self.primerUid) then
				self:_startPrimerTargetHunt()
				return
			end

			if self._forestDropInProgress ~= nil and droppedUid == self._forestDropInProgress then
				return
			end

			if not wasTracked then
				return
			end
			if not self.running or not self.activeTarget then
				return
			end
			local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root and self:_isInSafeArea(root) then
				self:_reportStolen()
				self:_finish("Safe return complete")
				return
			end
			task.delay(CARRY_STATE_GRACE, function()
				if self.destroyed or not self.enabled or self.carry.active
				or self.carry.generation ~= releaseGeneration
				then
					return
				end
				local latestRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if latestRoot and self:_isInSafeArea(latestRoot) then
					self:_reportStolen()
					self:_finish("Safe return complete")
					return
				end
				self:_reStealDroppedEgg(droppedUid)
				end)
			end, self.connections)
		connect(LocalPlayer:GetAttributeChangedSignal("RagdollEndTime"), function()
			local tEnd = LocalPlayer:GetAttribute("RagdollEndTime") or 0
			if self.instantPhase == "priming" and tEnd > workspace:GetServerTimeNow() then
				self:_startPrimerTargetHunt()
			end
			end, self.connections)
		local startupStatus = self.stats.status
		self.stats.status = startupStatus
		return self
	end
	function EggRuntime:_setStatus(status)
		if self.stats.status == status then
			return
		end
		self.stats.status = status
		self:_notify()
	end
	function EggRuntime:_notify()
		local snapshot = self:getSnapshot()
		for listener in pairs(self.listeners) do
			local ok, err = pcall(listener, snapshot)
			if not ok then
				warn("[StealAnEgg] Status listener failed:", err)
			end
		end
	end
	function EggRuntime:getSnapshot()
		return {
			status = self.stats.status,
			available = self.stats.available,
			matching = self.stats.matching,
			lastTarget = self.stats.lastTarget,
			lastResult = self.stats.lastResult,
			wallClosed = self.resetBlocked or AreaEggResetWall.IsSealed() or os.clock() < self.gateOpenAt,
			enabled = self.enabled,
			running = self.running,
		}
	end
	function EggRuntime:_replaceSnapshot(snapshot)
		table.clear(self.records)
		local records = snapshot and (snapshot.Records or snapshot) or {}
		for key, record in pairs(records) do
			if type(record) == "table" and type(record.Uid) == "string" then
				self.records[record.Uid] = record
			elseif type(key) == "string" and type(record) == "table" then
				self.records[key] = record
			end
		end
		self:_refreshCounts()
		self:_schedule()
	end
	function EggRuntime:_matchesNormalFilter(record)
		local info = self.catalog.resolve(record)
		local config = self.config
		if config.rarityEnabled and (#config.rarities == 0 or not listContains(config.rarities, info.rarity)) then
			return false
		end
		if config.nameEnabled and (#config.names == 0 or (not listContains(config.names, info.name) and not listContains(config.names, info.category))) then
			return false
		end
		if config.areaEnabled and (#config.areas == 0 or not listContains(config.areas, record.AreaId)) then
			return false
		end
		if config.mutationEnabled and not hasSelectedMutation(record, config.mutations) then
			return false
		end
		if (config.minWeightKg or 0) > 0 then
			local kg = self:_resolveWeightKg(record)
			if not kg or kg < config.minWeightKg then
				return false
			end
		end
		if (config.minValuePerSec or 0) > 0 then
			local rate = resolveEggRate(record)
			if not rate or rate < config.minValuePerSec then
				return false
			end
		end
		return true
	end
	function EggRuntime:_matches(record)
		return (record.State == AreaEggs.States.Slot or record.State == AreaEggs.States.Dropped)
			and self.userStealEnabled and self:_matchesNormalFilter(record)
	end
	function EggRuntime:_refreshCounts()
		local available = 0
		local matching = 0
		for _, record in pairs(self.records) do
			if record.State == AreaEggs.States.Slot then
				available += 1
				if self:_matches(record) then
					matching += 1
				end
			end
		end
		self.stats.available = available
		self.stats.matching = matching
		self:_notify()
	end
	function EggRuntime:isSkippedEgg(uid)

		if uid ~= nil and uid == workspace:GetAttribute("Event_CaptureTheEggUid") then return true end
		local untilAt = uid and self.skippedEggs[uid]
		if not untilAt then return false end
		if os.clock() < untilAt then return true end
		self.skippedEggs[uid] = nil
		return false
	end
	function EggRuntime:_chooseTarget()
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local best, bestRank, bestDistance
		for _, record in pairs(self.records) do
			if record.BottomCFrame and not self:isSkippedEgg(record.Uid) and self:_matches(record) then
				local rank = self.catalog.resolve(record).rarityRank or 0
				local distance = (record.BottomCFrame.Position - root.Position).Magnitude
				if not best or rank > bestRank or (rank == bestRank and distance < bestDistance) then
					best, bestRank, bestDistance = record, rank, distance
				end
			end
		end
		return best
	end
	local _originalResolveHitDistance = nil
	local GUARD_HIT_DISTANCE_BOOST = 25
	function EggRuntime:_installGuardHitDistanceBoost()
		if self.guardHitBoostInstalled then return end
		pcall(function()
			local GuardChasePolicy = require(ReplicatedStorage.Shared.Modules.GuardAreas.GuardChasePolicy)
			if GuardChasePolicy and type(GuardChasePolicy.ResolveHitDistance) == "function" then
				_originalResolveHitDistance = _originalResolveHitDistance or GuardChasePolicy.ResolveHitDistance
				local runtime = self
				GuardChasePolicy.ResolveHitDistance = function(hitDist)
					if runtime.enabled and runtime.instantPhase == "priming" then
						return GUARD_HIT_DISTANCE_BOOST
					end
					if runtime.enabled then
						return -math.huge
					end
					local base = _originalResolveHitDistance and _originalResolveHitDistance(hitDist) or (hitDist or 10)
					return base
				end
				self.guardHitBoostInstalled = true
			end
			end)
	end
	function EggRuntime:_removeGuardHitDistanceBoost()
		if not self.guardHitBoostInstalled then return end
		pcall(function()
			local GuardChasePolicy = require(ReplicatedStorage.Shared.Modules.GuardAreas.GuardChasePolicy)
			if GuardChasePolicy and _originalResolveHitDistance then
				GuardChasePolicy.ResolveHitDistance = _originalResolveHitDistance
				self.guardHitBoostInstalled = false
			end
			end)
	end
	function EggRuntime:_setInstantAnchored(anchored)
		pcall(function()
			local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root and root.Anchored ~= anchored then root.Anchored = anchored end
			end)
	end
	function EggRuntime:_kbCancelTimer()
		if self.hitTimer then
			pcall(task.cancel, self.hitTimer)
			self.hitTimer = nil
		end
	end
	function EggRuntime:_cleanupInstantSteal()
		self.instantPhase = nil
		self.primerUid = nil
		self.targetUid = nil
		self:_stopGuardStick()
		self:_stopGuardStrike()
		self:_kbCancelTimer()
		self:_setInstantAnchored(false)
		self:_hideTreadmillDecoy()
	end
	function EggRuntime:_choosePrimerEgg(excludeUid)
		local objects = resolveObjectsRoot()
		local areas = objects and objects:FindFirstChild("Areas")
		local guardAreas = areas and areas:FindFirstChild("GuardAreas")
		local forestArea = guardAreas and guardAreas:FindFirstChild("Forest")
		local forestGuard = forestArea and forestArea:FindFirstChild("Guard")
		local guardRoot = forestGuard and forestGuard:FindFirstChild("HumanoidRootPart")
		local guardPosition = guardRoot and guardRoot.Position
		local best, bestScore
		for _, rec in pairs(self.records) do
			if rec.State == AreaEggs.States.Slot and rec.AreaId == "Forest" and rec.Uid ~= excludeUid then
				local dist = guardPosition and (rec.BottomCFrame.Position - guardPosition).Magnitude
				or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
					and (rec.BottomCFrame.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
				or math.huge)
				local rarityRank = self.catalog.resolve(rec).rarityRank or 0
				local score = -dist - (rarityRank * 100)
				if not best or score > bestScore then
					best = rec
					bestScore = score
				end
			end
		end
		return best
	end
	local GUARD_STAND_OFFSET = 2.5
	local GUARD_STRIKE_INTERVAL = 0.05
	local GUARD_STRIKE_TIMEOUT = 1.5
	local GUARD_KNOCKBACK_VELOCITY = 18
	local GUARD_SETTLE_SECONDS = 0.35
	function EggRuntime:_stopGuardStick()
		if self.guardStickConnection then
			pcall(self.guardStickConnection.Disconnect, self.guardStickConnection)
			self.guardStickConnection = nil
		end
	end
	function EggRuntime:_startGuardStick()
		self:_stopGuardStick()
		local function forestGuardRoot()
			local objects = resolveObjectsRoot()
			local areas = objects and objects:FindFirstChild("Areas")
			local guardAreas = areas and areas:FindFirstChild("GuardAreas")
			local forest = guardAreas and guardAreas:FindFirstChild("Forest")
			local guard = forest and forest:FindFirstChild("Guard")
			return guard and guard:FindFirstChild("HumanoidRootPart")
		end
		self.guardStickConnection = RunService.PreSimulation:Connect(function()
			if self.destroyed or not self.enabled or self.instantPhase ~= "priming" then
				self:_stopGuardStick()
				return
			end
			local guardRoot = forestGuardRoot()
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not guardRoot or not root then
				return
			end
			local guardPosition = guardRoot.Position
			local front = guardRoot.CFrame.LookVector * GUARD_STAND_OFFSET
			local standAt = Vector3.new(guardPosition.X + front.X, root.Position.Y, guardPosition.Z + front.Z)
			local delta = standAt - root.Position
			if delta.Magnitude > 40 then
				delta = delta.Unit * 40
			end
			local nextPosition = root.Position + delta
			root.CFrame = CFrame.lookAt(nextPosition, Vector3.new(guardPosition.X, nextPosition.Y, guardPosition.Z))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			self:_syncHoverPad(nextPosition)
			end)
	end
	function EggRuntime:_forestGuardModel()
		local objects = resolveObjectsRoot()
		local areas = objects and objects:FindFirstChild("Areas")
		local guardAreas = areas and areas:FindFirstChild("GuardAreas")
		local forest = guardAreas and guardAreas:FindFirstChild("Forest")
		return forest and forest:FindFirstChild("Guard")
	end
	function EggRuntime:_triggerGuardHit()
		local guard = self:_forestGuardModel()
		local guardRoot = guard and guard:FindFirstChild("HumanoidRootPart")
		if not guardRoot then return end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local guardPosition = guardRoot.Position
		local front = guardRoot.CFrame.LookVector * GUARD_STAND_OFFSET
		local standAt = Vector3.new(guardPosition.X + front.X, root.Position.Y, guardPosition.Z + front.Z)
		self.guardStrikeAnchor = standAt
		root.CFrame = CFrame.lookAt(standAt, Vector3.new(guardPosition.X, standAt.Y, guardPosition.Z))
		root.AssemblyLinearVelocity = Vector3.zero
		local collider = guard:FindFirstChild("Collider") or guardRoot
		if collider and firetouchinterest then
			pcall(function()
				firetouchinterest(root, collider, 0)
				firetouchinterest(root, collider, 1)
				end)
		end
		pcall(function()
			local strike = Remotes.GuardPatrol and Remotes.GuardPatrol.ForestStrike
			if strike then
				strike:FireServer({
					EggUid = self.primerUid,
					GuardCFrame = guardRoot.CFrame,
					})
			end
			end)
	end
	function EggRuntime:_stopGuardStrike()
		self.guardStrikeGeneration = (self.guardStrikeGeneration or 0) + 1
	end
	function EggRuntime:_knockbackLanded()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then return false end
		if humanoid.PlatformStand or humanoid.Sit then return true end
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.PlatformStanding
		then
			return true
		end
		return root.AssemblyLinearVelocity.Magnitude > GUARD_KNOCKBACK_VELOCITY
	end
	function EggRuntime:_settleAfterKnockback()
		local anchor = self.guardStrikeAnchor
		local deadline = os.clock() + GUARD_SETTLE_SECONDS
		while os.clock() < deadline and not self.destroyed do
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				pcall(function()
					humanoid.PlatformStand = false
					humanoid.Sit = false
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
					end)
			end
			if anchor then root.CFrame = CFrame.new(anchor) end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			self:_syncHoverPad(anchor or root.Position)
			RunService.Heartbeat:Wait()
		end
	end
	function EggRuntime:_startGuardStrike()
		self:_stopGuardStrike()
		local generation = self.guardStrikeGeneration
		task.spawn(function()
			local deadline = os.clock() + GUARD_STRIKE_TIMEOUT
			while not self.destroyed
			and self.enabled
			and self.instantPhase == "priming"
			and self.guardStrikeGeneration == generation
			and os.clock() < deadline
			do
				self:_triggerGuardHit()
				local waitUntil = os.clock() + GUARD_STRIKE_INTERVAL
				local landed = false
				while os.clock() < waitUntil do
					if self:_knockbackLanded() then landed = true break end
					RunService.Heartbeat:Wait()
				end
				if landed then break end
			end
			if self.guardStrikeGeneration == generation then
				self:_stopGuardStick()
				self:_settleAfterKnockback()
			end
			end)
	end
	function EggRuntime:_enterBaitWait()
		self:_setInstantAnchored(false)
		self:_setStatus("Provoking Forest guard")
		self:_startGuardStick()
		self:_startGuardStrike()
		if self.hitTimer then return end
		self.hitTimer = task.delay(GUARD_STRIKE_TIMEOUT + 0.3, function()
			self.hitTimer = nil
			if self.destroyed or not self.enabled then return end
			if self.instantPhase ~= "priming" then return end
			self:_stopGuardStick()
			self:_stopGuardStrike()
			self:_finish("Guard bait timeout")
			end)
	end

	function EggRuntime:_resolveSettleSeconds(record)

		local areaId = type(record) == "table" and record.AreaId or nil
		local secs = areaId and SETTLE_BY_AREA[tostring(areaId)] or nil
		if type(secs) ~= "number" then secs = SETTLE_CAP_DEFAULT end
		return secs
	end
	function EggRuntime:_startPrimerTargetHunt()
		if self.instantPhase ~= "priming" then return end
		self:_stopGuardStick()
		self:_stopGuardStrike()
		pcall(function()
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
				humanoid.Sit = false
			end
			if root then
				if self.guardStrikeAnchor then root.CFrame = CFrame.new(self.guardStrikeAnchor) end
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			end)
		self:_kbCancelTimer()
		self:_setInstantAnchored(false)
		self.instantPhase = "hunting"
		self:_clearArrivalHold()
		self.carry.generation += 1
		self:_invalidateCarryWorker()
		self.carry.active = false
		self.carry.uid = nil
		local targetUid = self.targetUid
		self.targetUid = nil
		if not targetUid then
			self:_finish("No target egg")
			return
		end
		local current = EggCmds.ReadFieldEgg(targetUid) or self.records[targetUid]
		if not current or (current.State ~= AreaEggs.States.Slot and current.State ~= AreaEggs.States.Dropped) then
			self:_finish("Target egg no longer available")
			return
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			self:_finish("Character unavailable")
			return
		end
		self.activeTarget = current
		local destination = self:_resolveEggDestination(current, root, humanoid)
		if not destination then
			self:_finish("Target destination unavailable")
			return
		end
		if not self.lowFpsPrime then

			local holdUid = current.Uid
			local function stale()
				return self.destroyed or not self.enabled
					or self.instantPhase ~= "hunting"
					or not self.activeTarget or self.activeTarget.Uid ~= holdUid
			end
			local hoverCF = destination + Vector3.new(0, HOVER_DESYNC_HEIGHT, 0)
			self:_setStatus("Gliding to target")
			if not self:_glideRoot(hoverCF, stale) then
				if not stale() then self:_finish("Glide to target failed") end
				return
			end
			task.spawn(function()

				local hold = math.clamp(tonumber(Config.StealHoldSeconds) or 15, 3, 20)
				local deadline = os.clock() + hold
				while os.clock() < deadline do
					if stale() then return end
					self:_setStatus(string.format("Holding on egg (%.1fs)", math.max(0, deadline - os.clock())))
					local ch = LocalPlayer.Character
					local r = ch and ch:FindFirstChild("HumanoidRootPart")
					local h = ch and ch:FindFirstChildOfClass("Humanoid")
					if r and h then
						pcall(function()
							r.CFrame = hoverCF
							r.AssemblyLinearVelocity = Vector3.zero
							r.AssemblyAngularVelocity = Vector3.zero
							end)
						self:_syncHoverPad(hoverCF.Position)
						local ls = math.clamp(self.config.speed or DEFAULT_MOVEMENT_SPEED, MIN_MOVEMENT_SPEED, maxMoveSpeed())
						pcall(function()
							setMovementSpoof(ch, ls * INTEGRITY_SPEED_HEADROOM)
							refreshIntegritySpoof(h, r, ls, Vector3.zero)
							end)
					end
					task.wait(0.1)
				end
				if stale() then return end

				self:_glideRoot(destination, stale)
				if stale() then return end
				self:_setArrivalHold(destination, holdUid)
				self:_setStatus("Securing target egg")
				self:_requestCarry(current, true)
				end)
			return
		end

		self:_setStatus("Traveling to target")
		self:_tweenRoot(destination, function()
			if self.instantPhase == "hunting"
			and self.activeTarget
			and self.activeTarget.Uid == current.Uid
			then
				self:_requestCarry(current, false)
			end
			end, nil, {
				holdAfterArrival = true,
				holdUid = current.Uid,
				flightProfile = true,
				carryTarget = current,
			})
	end
	function EggRuntime:_wallOpen()
		if self.resetBlocked or AreaEggResetWall.IsSealed() or os.clock() < self.gateOpenAt then
			return false
		end
		local __root = resolveObjectsRoot()
		local areas = __root and __root:FindFirstChild("Areas")
		local collision = areas and areas:FindFirstChild("WallStartCollision")
		if collision and collision:IsA("BasePart") and collision.CanCollide then
			return false
		end
		return true
	end
	function EggRuntime:_closeGate(reason)
		self.resetBlocked = true
		self.gateOpenAt = math.huge
		self.safeStarting = false
		if not (self.activeTween and self.activeTween.sharedTravel) then
			self:_cancelTween(reason)
		end
		self:_setStatus(reason)
	end
	function EggRuntime:_cancelTween(reason, keepOperation)
		self:_cleanupInstantSteal()
		self.carryAttemptToken = nil
		self:_clearArrivalHold()
		self.safeStarting = false
		if self.activeTween then
			pcall(self.activeTween.Cancel, self.activeTween)
			self.activeTween = nil
		end
		if not self.activeTween and not self.arrivalHold then self:_stopHoverPad() end
		if self.running then
			self.running = false
			self.activeTarget = nil
			self.stats.lastResult = reason
			self:_notify()
		end
		if not keepOperation then

		end
	end

	function EggRuntime:_groundYAt(x, z, character)
		character = character or (LocalPlayer.Character)
		local origin = Vector3.new(x, (character and character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.Position.Y or SAFE_ZONE_POSITION.Y) + 60, z)
		local exclude = {}
		if character then table.insert(exclude, character) end
		if self.hoverPad then table.insert(exclude, self.hoverPad) end
		if self.treadmillDecoy then table.insert(exclude, self.treadmillDecoy) end
		for _, c in ipairs(workspace:GetChildren()) do
			if c.Name == HOVER_PAD_NAME or c.Name == TREADMILL_DECOY_NAME then
				table.insert(exclude, c)
			end
		end
		for _ = 1, 10 do
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = exclude
			params.IgnoreWater = true
			local hit = workspace:Raycast(origin, Vector3.new(0, -300, 0), params)
			if not hit then return nil end
			if hit.Instance.CanCollide then return hit.Position.Y end
			table.insert(exclude, hit.Instance)
		end
		return nil
	end
	function EggRuntime:_resolveSafeCFrame(root)
		if not root then return nil end
		return SAFE_ZONE_CFRAME
	end

	function EggRuntime:_groundSnap()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then return false end
		local pos = root.Position
		local groundY = self:_groundYAt(pos.X, pos.Z, character)
		if not groundY then return false end
		local restY = groundY + self:_feetOffset(root, humanoid)
		if pos.Y < restY - 0.25 or pos.Y > restY + 8 then
			pcall(function()
				self:_syncHoverPad(Vector3.new(pos.X, restY, pos.Z))
				root.CFrame = CFrame.new(pos.X, restY, pos.Z) * root.CFrame.Rotation
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
			return true
		end
		return false
	end
	local function destroyTreadmillDecoyTrail(instance)
		if typeof(instance) == "Instance" and instance:IsA("Trail") then
			pcall(instance.Destroy, instance)
		end
	end
	local function destroyTreadmillStealPopup(instance)
		if typeof(instance) == "Instance"
		and (instance.Name == "SpeedGainPopup" or instance.Name == "PlusOne")
		then
			pcall(instance.Destroy, instance)
		end
	end
	function EggRuntime:_showTreadmillDecoy()
		if self.treadmillDecoy and self.treadmillDecoy.Parent then
			return true
		end
		self:_hideTreadmillDecoy()
		local character = LocalPlayer.Character
		if not character then return false end
		local oldArchivable = character.Archivable
		character.Archivable = true
		local cloned, clone = pcall(character.Clone, character)
		character.Archivable = oldArchivable
		if not cloned or not clone or typeof(clone) ~= "Instance" then return false end
		clone.Name = TREADMILL_DECOY_NAME
		for _, descendant in ipairs(clone:GetDescendants()) do
			if TREADMILL_DECOY_REMOVE_CLASSES[descendant.ClassName] or descendant:IsA("Trail") then
				pcall(descendant.Destroy, descendant)
			elseif descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		local root = clone:FindFirstChild("HumanoidRootPart")
		local humanoid = clone:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			clone:Destroy()
			return false
		end
		pcall(function()
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end)
		clone.Parent = workspace
		clone:PivotTo(SAFE_ZONE_CFRAME)
		self.treadmillDecoy = clone
		local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, instance in ipairs(playerGui:GetDescendants()) do
				if instance.Name == "SpeedGainPopup" or instance.Name == "PlusOne" then
					destroyTreadmillStealPopup(instance)
				end
			end
			self.treadmillPopupConnection = playerGui.DescendantAdded:Connect(function(instance)
				if self.treadmillDecoy == clone then
					destroyTreadmillStealPopup(instance)
				end
				end)
		end
		local originals = setmetatable({}, { __mode = "k" })
		local function hideLivePart(part)
			if not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) then return end
			if originals[part] == nil then originals[part] = part.LocalTransparencyModifier end
			part.LocalTransparencyModifier = 1
		end
		for _, descendant in ipairs(character:GetDescendants()) do
			hideLivePart(descendant)
			destroyTreadmillDecoyTrail(descendant)
		end
		self.treadmillDecoyRealTransparency = originals
		self.treadmillDecoyCharacterConnection = character.DescendantAdded:Connect(function(descendant)
			if self.treadmillDecoy == clone then
				pcall(hideLivePart, descendant)
				destroyTreadmillDecoyTrail(descendant)
			end
			end)
		local camera = workspace.CurrentCamera
		if camera then
			self.treadmillDecoyCamera = camera.CameraSubject
			camera.CameraSubject = humanoid
		end
		self.treadmillDecoyCameraConnection = RunService.RenderStepped:Connect(function()
			if self.treadmillDecoy ~= clone or not clone.Parent or not humanoid.Parent then return end
			for part in pairs(originals) do
				if part.Parent and part.LocalTransparencyModifier ~= 1 then
					part.LocalTransparencyModifier = 1
				end
			end
			local liveCamera = workspace.CurrentCamera
			if liveCamera and liveCamera.CameraSubject ~= humanoid then
				liveCamera.CameraSubject = humanoid
			end
			end)
		return true
	end
	function EggRuntime:_hideTreadmillDecoy()
		if self.treadmillDecoyCameraConnection then
			pcall(self.treadmillDecoyCameraConnection.Disconnect, self.treadmillDecoyCameraConnection)
			self.treadmillDecoyCameraConnection = nil
		end
		if self.treadmillDecoyCharacterConnection then
			pcall(self.treadmillDecoyCharacterConnection.Disconnect, self.treadmillDecoyCharacterConnection)
			self.treadmillDecoyCharacterConnection = nil
		end
		if self.treadmillPopupConnection then
			pcall(self.treadmillPopupConnection.Disconnect, self.treadmillPopupConnection)
			self.treadmillPopupConnection = nil
		end
		for part, transparency in pairs(self.treadmillDecoyRealTransparency or {}) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function() part.LocalTransparencyModifier = transparency end)
			end
		end
		self.treadmillDecoyRealTransparency = nil
		local character = LocalPlayer.Character
		local liveHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		if camera then
			pcall(function()
				camera.CameraSubject = liveHumanoid or self.treadmillDecoyCamera
				end)
		end
		self.treadmillDecoyCamera = nil
		if self.treadmillDecoy then pcall(self.treadmillDecoy.Destroy, self.treadmillDecoy) end
		self.treadmillDecoy = nil
	end
	function EggRuntime:_restoreTreadmillVisualAtSafe()
		if not self.treadmillDecoy then
			self:_hideTreadmillDecoy()
			return true
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local safeDestination = self:_resolveSafeCFrame(root)
		if not root or not humanoid or not safeDestination then
			self:_hideTreadmillDecoy()
			return false
		end
		local deadline = os.clock() + SAFE_TELEPORT_TIMEOUT_SECONDS
		local stableSince = nil
		local nextTeleportAt = 0
		while not self.destroyed and os.clock() < deadline do
			local now = os.clock()
			if not self:_isInSafeArea(root) then
				stableSince = nil
				if now >= nextTeleportAt then
					nextTeleportAt = now + SAFE_TELEPORT_RETRY_SECONDS
					self:_teleportRoot(root, humanoid, safeDestination)
				end
			else
				stableSince = stableSince or now
				if now - stableSince >= SAFE_TELEPORT_STABLE_SECONDS then
					self:_hideTreadmillDecoy()
					return true
				end
			end
			task.wait(0.03)
		end
		self:_hideTreadmillDecoy()
		return false
	end
	function EggRuntime:_resolveEggDestination(record, root, humanoid)
		if type(record) ~= "table" or typeof(record.BottomCFrame) ~= "CFrame" then
			return nil
		end
		local character = LocalPlayer.Character
		root = root or (character and character:FindFirstChild("HumanoidRootPart"))
		humanoid = humanoid or (character and character:FindFirstChildOfClass("Humanoid"))
		if not root or not humanoid then
			return nil
		end
		local standingHeight = self:_feetOffset(root, humanoid) + EGG_ARRIVAL_CLEARANCE
		return CFrame.new(record.BottomCFrame.Position + Vector3.new(0, standingHeight, 0))
	end
	function EggRuntime:_resolveRouteCruiseY()
		return nil
	end
	function EggRuntime:_resolveElevatedDestination(root, destination)
		if not root or typeof(destination) ~= "CFrame" then return nil end
		return destination
	end
	function EggRuntime:_teleportRoot(root, humanoid, destination)
		if not root or not humanoid or typeof(destination) ~= "CFrame" then return false end
		local ok = pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = destination
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			end)
		if not ok then return false end
		local liveSpeed = math.clamp(self.config.speed or DEFAULT_MOVEMENT_SPEED, MIN_MOVEMENT_SPEED, maxMoveSpeed())
		setMovementSpoof(LocalPlayer.Character, liveSpeed * INTEGRITY_SPEED_HEADROOM)
		if not refreshIntegritySpoof(humanoid, root, liveSpeed, Vector3.zero) then
			setIntegritySpoof(humanoid, root, liveSpeed)
			refreshIntegritySpoof(humanoid, root, liveSpeed, Vector3.zero)
		end
		return true
	end

	function EggRuntime:_glideRoot(destCF, abortFn, speed)
		if typeof(destCF) ~= "CFrame" then return false end
		speed = speed or GLIDE_SPEED
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not humanoid then return false end
		pcall(applyKillPartIgnore, character)
		local glideGeneration = self.planGeneration
		local originalAutoRotate = humanoid.AutoRotate
		local function finishGlide(result)
			if humanoid and humanoid.Parent then
				pcall(function() humanoid.AutoRotate = originalAutoRotate end)
			end
			return result
		end
		pcall(function() humanoid.AutoRotate = false end)
		self:_startHoverPad()
		local target = destCF.Position
		local function warmSpoof(ch, h, r)
			local ls = math.clamp(self.config.speed or DEFAULT_MOVEMENT_SPEED, MIN_MOVEMENT_SPEED, maxMoveSpeed())
			pcall(function()
				setMovementSpoof(ch, ls * INTEGRITY_SPEED_HEADROOM)
				refreshIntegritySpoof(h, r, ls, Vector3.zero)
				end)
		end

		local deadline = os.clock() + math.clamp((target - root.Position).Magnitude / math.max(speed, 1) * 1.6 + 6, 15, 120)
		while os.clock() < deadline do
			if self.destroyed or not self.enabled or self.planGeneration ~= glideGeneration then
				return finishGlide(false)
			end
			if abortFn and abortFn() then return finishGlide(false) end
			if self.destroyed or not self.enabled then return finishGlide(false) end
			character = LocalPlayer.Character
			root = character and character:FindFirstChild("HumanoidRootPart")
			humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then return finishGlide(false) end
			local pos = root.Position
			local remaining = target - pos
			local dist = remaining.Magnitude
			if dist <= 1.0 then
				pcall(function()
					root.CFrame = destCF
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					end)
				self:_syncHoverPad(target)
				warmSpoof(character, humanoid, root)
				return finishGlide(true)
			end
			local dt = RunService.Heartbeat:Wait()
			dt = math.max(math.min(dt, LONG_FRAME_CLAMP), 1 / 240)
			local step = math.min(speed * dt, dist)
			local nextPos = pos + remaining.Unit * step
			if dt >= (1 / 30) then
				local groundY = self:_groundYAt(nextPos.X, nextPos.Z, character)
				if groundY then
					local minY = groundY + self:_feetOffset(root, humanoid)
					if nextPos.Y < minY then nextPos = Vector3.new(nextPos.X, minY, nextPos.Z) end
				end
			end
			pcall(function()
				root.CFrame = CFrame.new(nextPos, nextPos + remaining.Unit)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				end)
			self:_syncHoverPad(nextPos)
			warmSpoof(character, humanoid, root)
		end
		return finishGlide(false)
	end

	function EggRuntime:_isInSafeArea(root)
		if not root then return false end
		local delta = root.Position - SAFE_ZONE_POSITION
		return Vector2.new(delta.X, delta.Z).Magnitude <= SAFE_ZONE_HORIZONTAL_RADIUS
		and math.abs(delta.Y) <= SAFE_ZONE_VERTICAL_TOLERANCE
	end
	function EggRuntime:_isInField(root)
		local objects = resolveObjectsRoot()
		local areas = objects and objects:FindFirstChild("Areas")
		local wall = areas and areas:FindFirstChild("WallStartCollision")
		if not wall or not wall:IsA("BasePart") then
			return true
		end
		return root.Position.X >= wall.Position.X + 3
	end
	function EggRuntime:_invalidateCarryWorker()
		self.carryWorker = nil
	end
	function EggRuntime:_claimCarryWorker(kind, uid)
		local generation = self.carry.generation
		local current = self.carryWorker
		if current and current.generation == generation then return nil end
		local worker = {
			kind = kind,
			uid = uid,
			generation = generation,
			token = {},
		}
		self.carryWorker = worker
		return worker
	end
	function EggRuntime:_isCarryWorkerCurrent(worker)
		return type(worker) == "table"
		and self.carryWorker == worker
		and self.carry.generation == worker.generation
		and not self.destroyed
		and self.enabled
	end
	function EggRuntime:_releaseCarryWorker(worker)
		if self.carryWorker == worker then self.carryWorker = nil end
	end
	function EggRuntime:_hasConfirmedCarry(uid)
		if not self.carry.active then
			return false
		end
		if uid == nil or self.carry.uid == nil then
			return true
		end
		return self.carry.uid == uid
	end
	function EggRuntime:_recordShowsCarried(uid)
		if type(uid) ~= "string" or uid == "" then
			return false
		end
		local record = EggCmds.ReadFieldEgg(uid) or self.records[uid]
		return type(record) == "table"
		and record.State == AreaEggs.States.Carried
		and record.CarrierUserId == LocalPlayer.UserId
	end
	function EggRuntime:_resolveMovementSpeed(humanoid)
		if not humanoid.Parent or humanoid.Health <= 0 then
			return nil
		end
		return math.clamp(self.config.speed, MIN_MOVEMENT_SPEED, maxMoveSpeed())
	end
	function EggRuntime:_feetOffset(root, humanoid)
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			return root.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0.5)
		end
		return root.Size.Y * 0.5 + 2
	end
	function EggRuntime:_isForeignTrap(instance)
		if instance.Name == PLAYER_TRAP_NAME and instance:IsA("BasePart") then
			local owner = instance:GetAttribute("Owner")
			return type(owner) ~= "string" or owner ~= LocalPlayer.Name
		end
		return instance:IsA("Model")
		and instance.Name == LEGACY_TRAP_MODEL_NAME
		and instance:FindFirstChild("Hitbox") ~= nil
	end
	function EggRuntime:_purgeTrap(instance)
		if not self.config.antiTrap or not instance or not instance.Parent then
			return
		end
		if self:_isForeignTrap(instance) then
			pcall(instance.Destroy, instance)
		end
	end
	function EggRuntime:_purgeTraps()
		for _, fName in ipairs({ "Transient", "__DEBRIS" }) do
			local folder = workspace:FindFirstChild(fName)
			if folder then
				for _, instance in ipairs(folder:GetDescendants()) do
					self:_purgeTrap(instance)
				end
			end
		end
	end
	function EggRuntime:_syncHoverPad(position)
		local part = self.hoverPad
		if not part or not part.Parent
		or part:GetAttribute(HOVER_PAD_OWNER_ATTRIBUTE) ~= self.hoverPadOwnerId
		then
			return false
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then return false end
		local rootPosition = typeof(position) == "Vector3" and position or root.Position
		part.CFrame = CFrame.new(
			rootPosition.X,
			rootPosition.Y - self:_feetOffset(root, humanoid) - HOVER_PAD_THICKNESS * 0.5 - 0.05,
			rootPosition.Z
		)
		return true
	end
	function EggRuntime:_setArrivalHold(destination, uid)
		if typeof(destination) ~= "CFrame" then
			return
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			return
		end
		self.arrivalHold = {
			Character = character,
			RootPart = root,
			CFrame = destination,
			Uid = uid,
		}
	end
	function EggRuntime:_clearArrivalHold(uid)
		local hold = self.arrivalHold
		if not hold or uid == nil or hold.Uid == nil or hold.Uid == uid then
			self.arrivalHold = nil
		end
	end
	function EggRuntime:_enforceArrivalHold()
		local hold = self.arrivalHold
		if type(hold) ~= "table" or typeof(hold.CFrame) ~= "CFrame" then
			return false
		end
		if LocalPlayer.Character ~= hold.Character
		or not hold.RootPart
		or not hold.RootPart.Parent
		then
			self.arrivalHold = nil
			return false
		end
		self:_startHoverPad()
		pcall(function()
			hold.RootPart.AssemblyLinearVelocity = Vector3.zero
			hold.RootPart.AssemblyAngularVelocity = Vector3.zero
			self:_syncHoverPad(hold.CFrame.Position)
			hold.RootPart.CFrame = hold.CFrame
			end)
		self:_syncHoverPad(hold.CFrame.Position)
		return true
	end
	function EggRuntime:_purgeOrphanHoverPads()
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == HOVER_PAD_NAME
			and child ~= self.hoverPad
			then
				pcall(child.Destroy, child)
			end
		end
	end
	function EggRuntime:_startHoverPad()
		local part = self.hoverPad
		if not part or not part.Parent
		or part:GetAttribute(HOVER_PAD_OWNER_ATTRIBUTE) ~= self.hoverPadOwnerId
		then
			self:_purgeOrphanHoverPads()
			if part and part.Parent then pcall(part.Destroy, part) end
			part = Instance.new("Part")
			part.Name = HOVER_PAD_NAME
			part:SetAttribute(HOVER_PAD_OWNER_ATTRIBUTE, self.hoverPadOwnerId)
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency = 1
			part.Material = Enum.Material.SmoothPlastic
			part.Size = Vector3.new(HOVER_PAD_SIZE_XZ, HOVER_PAD_THICKNESS, HOVER_PAD_SIZE_XZ)
			self.hoverPad = part
			part.Parent = workspace
		end
		self:_syncHoverPad()
		if not self.hoverPadConnection then
			self.hoverPadConnection = RunService.PreSimulation:Connect(function()
				if not self:_syncHoverPad() then self:_startHoverPad() end
				end)
		end
		if not self.hoverPadPostConnection then
			self.hoverPadPostConnection = RunService.PostSimulation:Connect(function()
				if self.activeTween or self.arrivalHold then self:_syncHoverPad() end
				end)
		end
	end
	function EggRuntime:_stopHoverPad()
		if self.hoverPadConnection then
			pcall(self.hoverPadConnection.Disconnect, self.hoverPadConnection)
			self.hoverPadConnection = nil
		end
		if self.hoverPadPostConnection then
			pcall(self.hoverPadPostConnection.Disconnect, self.hoverPadPostConnection)
			self.hoverPadPostConnection = nil
		end
		if self.hoverPad then
			pcall(self.hoverPad.Destroy, self.hoverPad)
			self.hoverPad = nil
		end
		self:_purgeOrphanHoverPads()
	end
	function EggRuntime:_startMovementProtection()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid then
			return false
		end
		local speed = math.clamp(self.config.speed or DEFAULT_MOVEMENT_SPEED, MIN_MOVEMENT_SPEED, maxMoveSpeed())
		self.protectionCharacter = character
		self.protectionHumanoid = humanoid
		self.protectionRoot = root
		setMovementSpoof(character, speed * INTEGRITY_SPEED_HEADROOM)
		setIntegritySpoof(humanoid, root, speed)
		if not self.integritySpoofConnection then
			self.integritySpoofConnection = RunService.PreSimulation:Connect(function()
				local currentCharacter = LocalPlayer.Character
				local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
				local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
				if not currentCharacter or not currentRoot or not currentHumanoid then
					return
				end
				local liveSpeed = math.clamp(
					self.config.speed or DEFAULT_MOVEMENT_SPEED,
					MIN_MOVEMENT_SPEED,
					maxMoveSpeed()
				)
				self.protectionCharacter = currentCharacter
				self.protectionHumanoid = currentHumanoid
				self.protectionRoot = currentRoot
				setMovementSpoof(currentCharacter, liveSpeed * INTEGRITY_SPEED_HEADROOM)
				if not refreshIntegritySpoof(currentHumanoid, currentRoot, liveSpeed) then
					setIntegritySpoof(currentHumanoid, currentRoot, liveSpeed)
				end
				self:_enforceArrivalHold()
				end)
		end
		if not self.arrivalHoldConnection then
			self.arrivalHoldConnection = RunService.Heartbeat:Connect(function()
				self:_enforceArrivalHold()
				end)
		end
		return true
	end
	function EggRuntime:_stopMovementProtection()
		if self.integritySpoofConnection then
			pcall(self.integritySpoofConnection.Disconnect, self.integritySpoofConnection)
			self.integritySpoofConnection = nil
		end
		if self.arrivalHoldConnection then
			pcall(self.arrivalHoldConnection.Disconnect, self.arrivalHoldConnection)
			self.arrivalHoldConnection = nil
		end
		self:_clearArrivalHold()
		self:_stopHoverPad()
		clearMovementSpoof()
		clearIntegritySpoof(self.protectionHumanoid)
		self.protectionCharacter = nil
		self.protectionHumanoid = nil
		self.protectionRoot = nil
	end
	function EggRuntime:_tweenRoot(destination, callback, speedOverride, handlers)
		self:_clearArrivalHold()
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		handlers = handlers or {}
		if not root or not humanoid then
			self.safeStarting = false
			if handlers.silent then
				if handlers.onDone then pcall(handlers.onDone, false) end
				return
			end
			self:_finish("Character unavailable")
			return
		end
		local movementSpeed = speedOverride or self:_resolveMovementSpeed(humanoid)
		if not movementSpeed then
			self.safeStarting = false
			if handlers.silent then
				if handlers.onDone then pcall(handlers.onDone, false) end
				return
			end
			self:_finish("Movement unavailable")
			return
		end
		movementSpeed = math.clamp(movementSpeed, MIN_MOVEMENT_SPEED, maxMoveSpeed())
		self:_startMovementProtection()
		pcall(applyKillPartIgnore, character)
		local camera = workspace.CurrentCamera
		if camera and camera.CameraSubject ~= humanoid then
			pcall(function()
				camera.CameraSubject = humanoid
				end)
		end
		local originalAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
		local routeCruiseY = handlers.flightProfile == true
		and self:_resolveRouteCruiseY(root, destination)
		or nil
		local token = {
			sharedTravel = handlers.sharedTravel == true,
			routeCruiseY = routeCruiseY,
			travelPhase = routeCruiseY and "takeoff" or nil,

		}
		self.activeTween = token
		self:_startHoverPad()
		local released = false
		local connection
		local arrivalStableSince = nil
		local previousRemainingDistance = nil
		local correctionSlowUntil = 0
		local function release(completed)
			if released then
				return
			end
			released = true
			arrivalStableSince = nil
			if humanoid.Parent ~= nil then
				humanoid.AutoRotate = originalAutoRotate
			end
			if completed and handlers.holdAfterArrival then
				self:_setArrivalHold(destination, handlers.holdUid)
			end
			if handlers.onDone then
				pcall(handlers.onDone, completed == true)
			end
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if self.activeTween == token then
				self.activeTween = nil
			end
			if not self.arrivalHold then self:_stopHoverPad() end
			if not self.enabled then
				self:_stopMovementProtection()
			end
			pcall(function()
				if LocalPlayer.Character == character and root.Parent then
					root.AssemblyLinearVelocity = Vector3.zero
				end
				end)
			if completed
			and LocalPlayer.Character == character
			and humanoid.Parent ~= nil
			then
				if callback then
					callback()
				end
			end
		end
		token.Cancel = function()
			release(false)
		end
		connection = RunService.Heartbeat:Connect(function(deltaTime)
			if handlers.abort and handlers.abort() then
				release(false)
				return
			end
			if self.destroyed or self.activeTween ~= token then
				release(false)
				return
			end
			if handlers.carryTarget and os.clock() >= (token.nextTargetCheck or 0) then
				token.nextTargetCheck = os.clock() + 0.1
				local targetUid = handlers.carryTarget.Uid
				local live = EggCmds.ReadFieldEgg(targetUid)
				local state = live and live.State
				if state ~= AreaEggs.States.Slot and state ~= AreaEggs.States.Dropped and state ~= "GuardCarried"
				and not (live and live.CarrierUserId == LocalPlayer.UserId)
				and not self:_hasConfirmedCarry(targetUid)
				then
					release(false)
					self:_finish("Target taken by someone else")
					return
				end
			end
			pcall(function()
				local liveSpeed = math.clamp(
					speedOverride or self.config.speed or movementSpeed,
					MIN_MOVEMENT_SPEED,
					maxMoveSpeed()
				)
				setMovementSpoof(character, liveSpeed * INTEGRITY_SPEED_HEADROOM)
				local holder = environment()[INTEGRITY_SPOOF_KEY]
				local integrityState = type(holder) == "table" and holder.State or nil
				if not integrityStateCanTravel(integrityState, humanoid, root) then
					previousRemainingDistance = nil
					arrivalStableSince = nil
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					self:_syncHoverPad(root.Position)
					if integrityStateMatches(integrityState, humanoid, root) then
						patchIntegrityState(integrityState, liveSpeed * INTEGRITY_SPEED_HEADROOM, Vector3.zero)
					else
						setIntegritySpoof(humanoid, root, liveSpeed)
					end
					return
				end
				local position = root.Position
				local remaining = destination.Position - position
				local remainingDistance = remaining.Magnitude
				local horizontalRemaining = Vector3.new(remaining.X, 0, remaining.Z)
				local horizontalDistance = horizontalRemaining.Magnitude
				local movementTarget = destination.Position
				if token.routeCruiseY then
					if token.travelPhase == "takeoff" then
						if position.Y >= token.routeCruiseY - 0.5 then
							token.travelPhase = "cruise"
						else
							movementTarget = Vector3.new(position.X, token.routeCruiseY, position.Z)
						end
					end
					if token.travelPhase == "cruise" then
						if horizontalDistance <= 4 then
							token.travelPhase = "descend"
						else
							movementTarget = Vector3.new(destination.Position.X, token.routeCruiseY, destination.Position.Z)
						end
					end
					if token.travelPhase == "descend" then
						movementTarget = destination.Position
					end
				end
				local movementRemaining = movementTarget - position
				local movementDistance = movementRemaining.Magnitude
				local progressDistance = token.routeCruiseY and horizontalDistance or remainingDistance
				if previousRemainingDistance
				and progressDistance > previousRemainingDistance + CORRECTION_DISTANCE_EPSILON
				then
					correctionSlowUntil = os.clock() + CORRECTION_SLOWDOWN_SECONDS
				end
				previousRemainingDistance = progressDistance
				local effectiveSpeed = os.clock() < correctionSlowUntil
				and math.max(MIN_MOVEMENT_SPEED, liveSpeed * CORRECTION_SPEED_FACTOR)
				or liveSpeed
				if handlers.carryTarget and not token.__earlyCarrySpam and remainingDistance <= 30 then
					token.__earlyCarrySpam = true
					local targetRec = handlers.carryTarget
					local targetUid = targetRec.Uid
					local slotKey = AreaEggSlotIdentity.LooksLikeFirstAreaUid(targetUid)
					and AreaEggSlotIdentity.SlotKey(targetRec.AreaId, targetRec.NestId)
					or nil
					task.spawn(function()
						while not self.destroyed
						and self.enabled
						and self.activeTween == token
						and not self:_hasConfirmedCarry(targetUid)
						do
							pcall(requestFieldEggCarry, targetUid, slotKey)
							task.wait(0.08)
						end
						end)
				end
				local safeDeltaTime = math.max(math.min(deltaTime, LONG_FRAME_CLAMP), 1 / 240)
				local stepDistance = effectiveSpeed * safeDeltaTime
				local flatDirection = horizontalRemaining
				local currentLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local facingDirection = flatDirection.Magnitude > 0.001 and flatDirection.Unit
				or (currentLook.Magnitude > 0.001 and currentLook.Unit or Vector3.new(0, 0, -1))
				local canArrive = not token.routeCruiseY or token.travelPhase == "descend"
				if canArrive and remainingDistance <= math.max(stepDistance, 0.05) then
					if remainingDistance > 0.5 then
						arrivalStableSince = nil
					end
					self:_syncHoverPad(destination.Position)
					root.CFrame = CFrame.lookAt(destination.Position, destination.Position + facingDirection)
					root.AssemblyLinearVelocity = Vector3.zero
					self:_syncHoverPad(destination.Position)
					refreshIntegritySpoof(humanoid, root, liveSpeed, Vector3.zero)
					arrivalStableSince = arrivalStableSince or os.clock()
					if os.clock() - arrivalStableSince >= MOVEMENT_ARRIVAL_HOLD then
						release(true)
					end
					return
				end
				arrivalStableSince = nil
				if movementDistance <= 0.001 then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					self:_syncHoverPad(position)
					return
				end
				if not self.hoverPad or not self.hoverPad.Parent then self:_startHoverPad() end
				local actualStepDistance = math.min(stepDistance, movementDistance)
				local nextPosition = position + movementRemaining.Unit * actualStepDistance

				if safeDeltaTime >= (1 / 30) and (not token.routeCruiseY or token.travelPhase ~= "cruise") then
					local groundY = self:_groundYAt(nextPosition.X, nextPosition.Z, character)
					if groundY then
						local minY = groundY + self:_feetOffset(root, humanoid)
						if nextPosition.Y < minY then
							nextPosition = Vector3.new(nextPosition.X, minY, nextPosition.Z)
						end
					end
				end
				local travelVelocity = (nextPosition - position) / safeDeltaTime
				self:_syncHoverPad(nextPosition)
				root.CFrame = CFrame.lookAt(nextPosition, nextPosition + facingDirection)
				root.AssemblyLinearVelocity = Vector3.zero
				self:_syncHoverPad(nextPosition)
				if not refreshIntegritySpoof(humanoid, root, liveSpeed, travelVelocity) then
					setIntegritySpoof(humanoid, root, liveSpeed)
					refreshIntegritySpoof(humanoid, root, liveSpeed, travelVelocity)
				end
				end)
			end)
	end
	function EggRuntime:_reStealDroppedEgg(uid)
		if type(uid) ~= "string" or uid == "" then
			self:_finish("Egg lost — retrying")
			return
		end
		if self:isSkippedEgg(uid) then return end
		if self.tweenRecoveryUid == uid then
			self.running = false
			self.activeTarget = nil

			self:_scheduleMovementRetry()
			return
		end
		local worker = self:_claimCarryWorker("re-steal", uid)
		if not worker then return end
		local record = nil
		local deadline = os.clock() + 5
		self:_setStatus("Re-stealing dropped egg")
		while self:_isCarryWorkerCurrent(worker) and os.clock() < deadline do
			local candidate = EggCmds.ReadFieldEgg(uid) or self.records[uid]
			if candidate
			and (candidate.State == AreaEggs.States.Dropped or candidate.State == AreaEggs.States.Slot)
			then
				record = candidate
				break
			end
			task.wait(0.03)
		end
		if not self:_isCarryWorkerCurrent(worker) then return end
		if not record or not self:_wallOpen() then
			self:_releaseCarryWorker(worker)
			self:_finish("Egg lost — retrying")
			return
		end
		self:_cancelTween("Re-stealing dropped egg", true)
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local destination = self:_resolveEggDestination(record, root, humanoid)
		destination = destination and self:_resolveElevatedDestination(root, destination) or nil
		if not destination then
			self:_releaseCarryWorker(worker)
			self:_finish("Character unavailable")
			return
		end
		self.running = true
		self.activeTarget = record
		self:_setStatus("Re-grabbing dropped egg")
		if self:_regrabBurst(worker, record.Uid, 3.5) or not self:_isCarryWorkerCurrent(worker) then return end
		self:_setStatus("Teleporting to dropped egg")
		if not self:_teleportRoot(root, humanoid, destination) then
			self:_releaseCarryWorker(worker)
			self:_finish("Dropped egg teleport failed")
			return
		end
		self:_setArrivalHold(destination, record.Uid)
		self:_setStatus("Re-stealing egg")
		if self:_isCarryWorkerCurrent(worker) then self:_requestCarry(record, true) end
	end
	function EggRuntime:_regrabBurst(worker, uid, seconds)
		local function heldByMe()
			local current = EggCmds.ReadFieldEgg(uid)
			return current ~= nil and current.State == AreaEggs.States.Carried and current.CarrierUserId == LocalPlayer.UserId
		end
		local ragdoll = nil
		pcall(function() ragdoll = require(ReplicatedStorage.Shared.Modules.RagdollJoints) end)
		local askBusy, carryBusy = false, false
		local deadline = os.clock() + seconds
		while os.clock() < deadline and not self.destroyed and self.enabled do
			if heldByMe() then return true end
			if not self:_isCarryWorkerCurrent(worker) then return heldByMe() end
			local current = EggCmds.ReadFieldEgg(uid)
			if not current or (current.State ~= AreaEggs.States.Dropped and current.State ~= AreaEggs.States.Slot) then
				return false
			end
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid then return false end
			pcall(function()
				if ragdoll and ragdoll.Release then ragdoll.Release(character) end
				humanoid.PlatformStand = false
				humanoid.Sit = false
				if humanoid:GetState() ~= Enum.HumanoidStateType.Running then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
				end)
			local destination = self:_resolveEggDestination(current, root, humanoid)
			if destination then
				root.CFrame = destination
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				self:_syncHoverPad(destination.Position)
			end
			if not askBusy then
				askBusy = true
				task.spawn(function()
					pcall(function() EggWorld.AskFieldEggCarry:InvokeServer({ Uid = uid }) end)
					askBusy = false
					end)
			end
			if not carryBusy then
				carryBusy = true
				task.spawn(function()
					pcall(EggCmds.CarryFieldEgg, uid)
					carryBusy = false
					end)
			end
			pcall(function()
				local slots = workspace:FindFirstChild("AreaEggSlotsClient")
				local model = slots and slots:FindFirstChild(tostring(uid))
				local prompt = model and (model:FindFirstChild("CarryAreaEgg", true) or model:FindFirstChildWhichIsA("ProximityPrompt", true))
				if prompt and prompt.Enabled and type(fireproximityprompt) == "function" then
					prompt.HoldDuration = 0
					prompt.RequiresLineOfSight = false
					fireproximityprompt(prompt, 0)
				end
				end)
			task.wait(0.06)
		end
		return heldByMe()
	end
	function EggRuntime:_recoverCarryConfirmationTimeout(attemptToken, targetUid)
		if self.destroyed
		or not self.enabled
		or self.carryAttemptToken ~= attemptToken
		or self:_hasConfirmedCarry(targetUid)
		then
			return false
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local safeCFrame = root and self:_resolveSafeCFrame(root)
		safeCFrame = safeCFrame and self:_resolveElevatedDestination(root, safeCFrame) or nil
		self.tweenRecoveryUid = targetUid
		self.carry.generation += 1
		self:_invalidateCarryWorker()
		self.carryAttemptToken = nil
		self:_clearArrivalHold(targetUid)
		if self.activeTween and self.activeTween.Cancel then
			pcall(self.activeTween.Cancel, self.activeTween)
		end
		self.activeTween = nil
		self:_stopMovementProtection()
		self.running = false
		self.activeTarget = nil
		self.stats.lastResult = "Carry confirmation timeout"
		if root and safeCFrame then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.CFrame = safeCFrame
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				end)
			self:_setStatus("Carry timeout — teleported safe")
		else
			self:_setStatus("Carry timeout — safe area unavailable")
		end
		if self.enabled then
			self:_startMovementProtection()
		end

		task.delay(0.35, function()
			if not self.destroyed and self.enabled and self.carryAttemptToken == nil then
				self:_schedule()
			end
			end)
		return true
	end
	function EggRuntime:_requestCarry(record, teleportReapproach)
		if not self:_wallOpen() then
			self:_finish("Wall closed before carry")
			return
		end
		local targetUid = record.Uid
		local attemptToken = {}
		local confirmationDeadline = nil

		local isPrimerCarry = self.instantPhase == "priming" and targetUid == self.primerUid
		local confirmWindow = isPrimerCarry and CARRY_CONFIRM_TIMEOUT_SECONDS
			or math.max(CARRY_CONFIRM_TIMEOUT_SECONDS, self:_resolveSettleSeconds(record) + 3)
		self.carryAttemptToken = attemptToken
		self.stats.lastResult = "Carry requested"
		self:_setStatus("Securing egg")
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			pcall(humanoid.UnequipTools, humanoid)
		end
		task.spawn(function()
			while not self.destroyed
			and self.enabled
			and self.running
			and self.carryAttemptToken == attemptToken
			and self.activeTarget
			and self.activeTarget.Uid == targetUid
			do
				if self:_hasConfirmedCarry(targetUid) then
					if self:_recordShowsCarried(targetUid) then
						self:_clearArrivalHold(targetUid)
						self.carryAttemptToken = nil
						if self.activeTween then
							pcall(self.activeTween.Cancel, self.activeTween)
							self.activeTween = nil
						end
						if self.instantPhase == "priming" and targetUid == self.primerUid then
							self.carry.active = true
							self.carry.uid = targetUid
							self.stats.lastResult = "Primer secured"
							self:_enterBaitWait()
							return
						end

						self.carry.active = true
						self.carry.uid = targetUid
						self.stats.lastResult = "Carry confirmed"
						self:_setStatus("Carry confirmed")
						task.defer(function()
							if not self.destroyed and self.enabled and self:_hasConfirmedCarry(targetUid) then
								self:_returnToSafe()
							end
							end)
						return
					end
					self:_setStatus("Confirming carry record")
					task.wait(CARRY_RETRY_INTERVAL)
					continue
				end
				if confirmationDeadline and os.clock() >= confirmationDeadline then
					self:_recoverCarryConfirmationTimeout(attemptToken, targetUid)
					return
				end
				if not self:_wallOpen() then
					self:_finish("Wall closed before carry")
					return
				end
				local current = EggCmds.ReadFieldEgg(targetUid) or self.records[targetUid]
				if not current then
					self:_finish("Target unavailable")
					return
				end
				if current.State == AreaEggs.States.Carried then
					if current.CarrierUserId == LocalPlayer.UserId then
						self:_setStatus("Confirming carry state")
						task.wait(CARRY_RETRY_INTERVAL)
						continue
					end
					self:_finish("Egg carried by another player")
					return
				end
				if current.State ~= AreaEggs.States.Slot and current.State ~= AreaEggs.States.Dropped then
					self:_finish("Target changed")
					return
				end
				local character = LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root then
					self:_finish("Character unavailable")
					return
				end
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not humanoid then
					self:_finish("Character unavailable")
					return
				end
				local groundedEggDestination = self:_resolveEggDestination(current, root, humanoid)
				local reapproachDestination = groundedEggDestination
				and self:_resolveElevatedDestination(root, groundedEggDestination)
				or nil
				if not reapproachDestination then
					self:_finish("Character unavailable")
					return
				end
				local eggPosition = reapproachDestination.Position
				if (root.Position - eggPosition).Magnitude > CARRY_REAPPROACH_DISTANCE then
					if teleportReapproach then
						self:_setStatus("Teleporting back to dropped egg")
						if not self:_teleportRoot(root, humanoid, reapproachDestination) then
							self:_finish("Dropped egg teleport failed")
							return
						end
						self:_setArrivalHold(reapproachDestination, targetUid)
						self:_setStatus("Re-stealing egg")
					else
						self:_setStatus("Re-approaching egg")
						local reapproachDone = false
						self:_tweenRoot(groundedEggDestination, function()
							reapproachDone = true
							if self.carryAttemptToken == attemptToken and not self:_hasConfirmedCarry(targetUid) then
								self:_setStatus("Securing egg")
							end
							end, nil, {
								holdAfterArrival = true,
								holdUid = targetUid,
								flightProfile = true,
							})
						while not self.destroyed
						and self.enabled
						and self.carryAttemptToken == attemptToken
						and not self:_hasConfirmedCarry(targetUid)
						and not reapproachDone
						do
							task.wait(CARRY_RETRY_INTERVAL)
						end
						continue
					end
				end
				local slotKey = AreaEggSlotIdentity.LooksLikeFirstAreaUid(current.Uid)
				and AreaEggSlotIdentity.SlotKey(current.AreaId, current.NestId)
				or nil
				pcall(requestFieldEggCarry, current.Uid, slotKey)
				confirmationDeadline = confirmationDeadline or (os.clock() + confirmWindow)
				self.stats.lastResult = "Carry requested"
				self:_setStatus("Waiting for carry confirmation")
				task.wait(CARRY_RETRY_INTERVAL)
			end
			end)
	end

	function EggRuntime:_treadmillReset(abortFn)
		local function aborted() return abortFn ~= nil and abortFn() end
		local Treadmill = Remotes and Remotes.Treadmill
		if not Treadmill or aborted() then return false end
		local function serverMounted()
			local ok, ids = pcall(function() return Treadmill.AskRenderSnapshot:InvokeServer() end)
			if not ok or type(ids) ~= "table" then return nil end
			return table.find(ids, LocalPlayer.UserId) ~= nil
		end
		local function standCFrame()
			local ok, cf = pcall(function()
				local slot = type(PlotState.ResolveLocalSlot) == "function"
					and PlotState.ResolveLocalSlot() or PlotState.GetMySlot()
				local plotsFolder = type(PlotState.ResolveFolder) == "function"
					and PlotState.ResolveFolder() or PlotState.GetPlotsFolder()
				local plotFolder = plotsFolder and slot and plotsFolder:FindFirstChild(tostring(slot))
				local bottom = plotFolder and plotFolder:FindFirstChild("TreadmillBottom")
				if not (bottom and bottom:IsA("BasePart")) then return nil end
				local character = LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not root or not humanoid then return nil end
				local feetOffset = humanoid.RigType == Enum.HumanoidRigType.R15
					and (root.Size.Y * 0.5 + math.max(humanoid.HipHeight, 0.5))
					or (root.Size.Y * 0.5 + 2)
				return bottom.CFrame * CFrame.new(0, bottom.Size.Y * 0.5 + feetOffset + 0.05, 0)
			end)
			return ok and cf or nil
		end
		local stand = standCFrame()
		if not stand or aborted() then return false end

		self:_glideRoot(stand, function() return aborted() end)
		if aborted() then return false end
		local mountedOk = false
		local mountDeadline = os.clock() + 0.7
		while not aborted() and os.clock() < mountDeadline do
			pcall(function() Treadmill.AskWearStill:InvokeServer() end)
			task.wait(0.08)
			if serverMounted() == true then mountedOk = true break end
		end
		if mountedOk then
			local holdUntil = os.clock() + 0.25
			while not aborted() and os.clock() < holdUntil do
				task.wait(0.05)
			end
		end
		local released = false
		local releaseDeadline = os.clock() + 0.7
		while not aborted() and os.clock() < releaseDeadline do
			pcall(function() Treadmill.AskDoff:InvokeServer() end)
			task.wait(0.08)
			if serverMounted() == false then released = true break end
		end
		return mountedOk and released
	end
	function EggRuntime:_instantReturn(uid)
		if self._instantReturnToken ~= nil then return end
		local token = {}
		self._instantReturnToken = token

		task.spawn(function()
			local function alive()
				return not self.destroyed and self.enabled and self._instantReturnToken == token
			end
			local function parts()
				local character = LocalPlayer.Character
				return character and character:FindFirstChild("HumanoidRootPart"),
					character and character:FindFirstChildOfClass("Humanoid")
			end
			local function record()
				return EggCmds.ReadFieldEgg(uid)
			end
			local function heldByMe()
				local r = record()
				return r ~= nil and r.State == AreaEggs.States.Carried and r.CarrierUserId == LocalPlayer.UserId
			end
			local function banked()
				local r = record()
				if not r then return true end
				return r.State == AreaEggs.States.Claimed
			end
			local function safeCFrame()
				local root = (parts())
				return root and self:_resolveSafeCFrame(root) or nil
			end
			local function finish(reason, reportStolen)
				if self._instantReturnToken ~= token then return end
				self._instantReturnToken = nil
				self._forestDropInProgress = nil
				if not self.destroyed and self.enabled then
					if reportStolen ~= false then self:_reportStolen() end
					self:_finish(reason or "Safe return complete")
				end
			end

			self:_clearArrivalHold(uid)

			local dropRelay = FOREST_DROP_RELAY
			local needsTransfer = heldByMe()

			if needsTransfer then
				self._forestDropInProgress = uid

				self:_setStatus("Gliding egg to relay")
				if not self:_glideRoot(dropRelay, function()
					return not alive() or not heldByMe()
				end) then
					finish("Relay travel failed — retrying")
					return
				end
				if not alive() then return end

				local released = false
				for attempt = 1, FOREST_TRANSFER_ATTEMPTS do
					if not alive() or not heldByMe() then break end
					self:_setStatus(string.format("Dropping egg (%d/%d)", attempt, FOREST_TRANSFER_ATTEMPTS))
					self:_glideRoot(dropRelay, function() return not alive() or not heldByMe() end)
					if not alive() then return end
					if heldByMe() then

						task.wait(0.4)
						if not alive() then return end
						if heldByMe() then
							pcall(EggCmds.DropFieldEgg, "PlayerRequest")
						end
						local dropUntil = os.clock() + FOREST_DROP_SETTLE
						while alive() and heldByMe() and os.clock() < dropUntil do
							RunService.Heartbeat:Wait()
						end
					end
					local rec2 = record()
					if rec2 and rec2.State == AreaEggs.States.Dropped then released = true break end
					if not heldByMe() then break end
				end
				if not alive() then return end
				if not released then
					if self._instantReturnToken == token then self._instantReturnToken = nil end
					self._forestDropInProgress = nil
					self:_finish("Drop failed — retrying")
					return
				end

				local dropPos
				local syncUntil = os.clock() + 3
				while alive() and os.clock() < syncUntil do
					local r = record()
					if r and r.State == AreaEggs.States.Dropped then
						local b = r.BottomCFrame or r.BoundsCFrame
						dropPos = b and b.Position
						if dropPos then break end
					elseif r and r.State ~= AreaEggs.States.Carried then
						break
					end
					task.wait(0.1)
				end
				if not alive() then return end
				self._forestDropInProgress = nil

				self:_setStatus("Reset at safe zone")
				local safeCF = safeCFrame()
				if safeCF then self:_glideRoot(safeCF, function() return not alive() end) end
				if not alive() then return end

				local rgWorker = self:_claimCarryWorker("instant-regrab", uid)
				local regrabCF = dropPos and CFrame.new(dropPos + Vector3.new(0, 3.2, 0)) or dropRelay
				local function gotoEgg()
					self:_glideRoot(regrabCF, function() return not alive() or heldByMe() end)
				end
				local got = false
				if rgWorker then

					self:_setStatus("Re-grabbing dropped egg")
					gotoEgg()
					if not alive() then return end
					got = self:_regrabBurst(rgWorker, uid, 0.5)
					if not alive() then return end
					if heldByMe() then got = true end
					if not got and not heldByMe() and self:_isCarryWorkerCurrent(rgWorker) then

						self:_setStatus("Reset at safe zone")
						local resetSafeCF = safeCFrame()
						if resetSafeCF then self:_glideRoot(resetSafeCF, function() return not alive() end) end
						if not alive() then return end
						self:_setStatus("Resetting on treadmill")
						self:_treadmillReset(function() return not alive() end)
						if not alive() then return end

						self:_setStatus("Back to safe zone")
						local resetSafeCF2 = safeCFrame()
						if resetSafeCF2 then self:_glideRoot(resetSafeCF2, function() return not alive() end) end
						if not alive() then return end
						if self:_isCarryWorkerCurrent(rgWorker) then
							self:_setStatus("Re-grabbing dropped egg")
							gotoEgg()
							if not alive() then return end
							got = self:_regrabBurst(rgWorker, uid, 0.6)
							if not alive() then return end
						end
					end
				end
				if not got and not heldByMe() then
					finish(banked() and "Safe return complete" or "Re-grab failed — retrying")
					return
				end
			end

			if heldByMe() then
				self:_setStatus("Gliding egg home")
				local safeCF = safeCFrame()
				if safeCF then
					self:_glideRoot(safeCF, function() return not alive() or not heldByMe() end)
				end
			end

			self:_setStatus("Waiting for deposit")
			local depositDeadline = os.clock() + 8
			while alive() and not banked() and os.clock() < depositDeadline do
				local r, h = parts()
				if r and h and not self:_isInSafeArea(r) then
					local cf = self:_resolveSafeCFrame(r)
					if cf then self:_glideRoot(cf, function() return not alive() or banked() end) end
				end
				task.wait(0.2)
			end
			finish(banked() and "Safe return complete" or "Bank not confirmed — retrying")
			end)
	end
	function EggRuntime:_returnToSafe()

		if self.primerUid ~= nil and self.carry.uid == self.primerUid then
			local primerUid = self.carry.uid
			self.stats.lastResult = "Primer not banked"
			self.carry.active = false
			self.carry.uid = nil
			self.carry.generation += 1
			self:_invalidateCarryWorker()
			self.skippedEggs[primerUid] = os.clock() + 30
			pcall(EggCmds.DropFieldEgg, "PlayerRequest")
			if self.instantPhase == "priming" then self:_startPrimerTargetHunt() end
			self:_notify()
			return
		end

		local heldUid = self.carry.uid or (self.activeTarget and self.activeTarget.Uid)
		if heldUid then
			self:_instantReturn(heldUid)
		else
			self:_finish("Carry lost — retrying")
		end
	end
	function EggRuntime:_reportStolen()
		local record = self.activeTarget
		if type(record) ~= "table" or not record.Uid then return end
		if self.reportedUid == record.Uid then return end
		self.reportedUid = record.Uid
		task.delay(1.5, function()
			if self.destroyed then return end
			local field = nil
			pcall(function() field = EggCmds.ReadFieldEgg(record.Uid) end)
			local stillThere = type(field) == "table" and (field.State == AreaEggs.States.Slot
				or field.State == AreaEggs.States.Dropped
				or (field.State == AreaEggs.States.Carried and field.CarrierUserId ~= LocalPlayer.UserId))
			if stillThere then
				self.reportedUid = nil
				self.stats.deliveryFailed = (self.stats.deliveryFailed or 0) + 1
				self.stats.lastResult = "Delivery failed — retrying"
				self:_notify()
				if self.enabled and not self.running then self:_schedule() end
				return
			end
			self.stats.delivered = (self.stats.delivered or 0) + 1
			end)
	end
	function EggRuntime:_startWatchdog()
		if self.watchdogRunning then return end
		self.watchdogRunning = true
		task.spawn(function()
			local lastKey, keySince, idleSince = nil, os.clock(), nil
			while sessionAlive() and not self.destroyed and self.userStealEnabled do
				task.wait(2)
				if not self.enabled then
					lastKey, idleSince = nil, nil
				elseif self.running then
					idleSince = nil
					local key = tostring(self.activeTarget and self.activeTarget.Uid) .. "|" .. tostring(self.carry.active)
					if key ~= lastKey then
						lastKey, keySince = key, os.clock()
					elseif os.clock() - keySince > 60 then
						lastKey = nil
						self.stats.watchdogResets = (self.stats.watchdogResets or 0) + 1
						pcall(function() self:_invalidateCarryWorker() end)
						self:_finish("Stuck — retrying")
					end
				else
					lastKey = nil
					local okTarget, target = pcall(self._chooseTarget, self)
					if self:_wallOpen() and okTarget and target ~= nil then
						idleSince = idleSince or os.clock()
						if os.clock() - idleSince > 6 then
							idleSince = nil
							self.stats.watchdogResets = (self.stats.watchdogResets or 0) + 1

							self:_schedule()
						end
					else
						idleSince = nil
					end
				end
			end
			self.watchdogRunning = false
			end)
	end
	function EggRuntime:_finish(result)

		self:_hideTreadmillDecoy()
		self._forestDropInProgress = nil
		self._instantReturnToken = nil
		self:_invalidateCarryWorker()
		self.planGeneration += 1
		self:_cancelTween(result, self.enabled)
		self:_setStatus(self.enabled and "Searching" or "Idle")
		if self.enabled then
			task.delay(NEXT_TARGET_HANDOFF_SECONDS, function()
				if self.destroyed or not self.enabled then

					return
				end
				self:_reconcileRunningState()
				end)
		end
	end
	function EggRuntime:_scheduleMovementRetry()
		if self.movementRetryPending or self.destroyed or not self.enabled then
			return
		end
		self.movementRetryPending = true
		task.delay(0.2, function()
			self.movementRetryPending = false
			if not self.destroyed and self.enabled then
				self:_schedule()
			end
			end)
	end
	function EggRuntime:_schedule()
		if not self.running then
			self.safeStarting = false
		end
		if self.destroyed or not self.enabled or self.running then
			return
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then

			self:_setStatus("Character unavailable")
			return
		end
		self:_startMovementProtection()
		if self.carry.active and self.carry.uid ~= nil then
			if self.instantPhase == "priming" and self.carry.uid == self.primerUid then
				return
			end
			local carried = self.records[self.carry.uid] or EggCmds.ReadFieldEgg(self.carry.uid)
			local wanted = type(carried) == "table" and self:_matchesNormalFilter(carried)
			if type(carried) == "table" and not wanted then
				self:_setStatus("Dropping unwanted egg")
				self.skippedEggs[self.carry.uid] = os.clock() + 30
				pcall(EggCmds.DropFieldEgg, "PlayerRequest")
				task.delay(0.5, function()
					if not self.destroyed and self.enabled then self:_schedule() end
					end)
				return
			end
			self:_returnToSafe()
			return
		end
		if not self:_wallOpen() then

			self:_setStatus("Waiting for reset wall")
			return
		end
		local recoveryUid = self.tweenRecoveryUid
		local record = recoveryUid and (EggCmds.ReadFieldEgg(recoveryUid) or self.records[recoveryUid]) or nil
		if recoveryUid and (type(record) ~= "table"
			or (record.State ~= AreaEggs.States.Slot and record.State ~= AreaEggs.States.Dropped))
		then
			self.tweenRecoveryUid = nil
			recoveryUid = nil
			record = nil
		end
		if not record then record = self:_chooseTarget() end
		if not record then
			if self.stats.matching == 0 and self.stats.available > 0 and (self.config.minWeightKg or 0) > 0 then
				self:_setStatus(string.format("No eggs ≥ %dKg", self.config.minWeightKg))
			else
				self:_setStatus("No matching eggs")
			end

			if not self.activeTween and self:_isInField(root) and not self:_isInSafeArea(root) then
				local safeDestination = self:_resolveSafeCFrame(root)
				if safeDestination then
					self:_tweenRoot(safeDestination, nil, nil, {
						silent = true,
						flightProfile = true,
						abort = function() return not self.enabled or self.running end,
						})
				end
			end
			return
		end
		local planGeneration = self.planGeneration

		self.safeStarting = true
		self.running = true
		self.activeTarget = record
		local info = self.catalog.resolve(record)
		self.stats.lastTarget = string.format("%s · %s · %s", info.rarity, info.name, record.AreaId)
		if recoveryUid then
			self.safeStarting = false
			self.stats.lastResult = "Recovering with tween"
			local destination = self:_resolveEggDestination(record, root, humanoid)
			if not destination then
				self.tweenRecoveryUid = nil
				self:_finish("Recovery destination unavailable")
				return
			end
			self:_setStatus("Returning to egg")
			self:_tweenRoot(destination, function()
				if self.tweenRecoveryUid == record.Uid then
					self:_requestCarry(record, false)
				end
				end, nil, {
					holdAfterArrival = true,
					holdUid = record.Uid,
					flightProfile = true,
					carryTarget = record,
				})
			return
		end

		if not self:_leftTreadmill(root) then
			self.running = false
			self.safeStarting = false
			self.activeTarget = nil

			self:_setStatus("Leaving treadmill")
			task.delay(0.3, function()
				if not self.destroyed and self.enabled and self.planGeneration == planGeneration then
					self:_schedule()
				end
				end)
			return
		end

		local _safeDelta = root.Position - SAFE_ZONE_POSITION
		local _safeDistXZ = Vector2.new(_safeDelta.X, _safeDelta.Z).Magnitude

		if _safeDistXZ > 3 and os.clock() - (self.lastSafeRepositionAt or 0) > 5 then
			local safeDestination = self:_resolveSafeCFrame(root)
			if safeDestination then
				self.safeStarting = true
				self.running = true
				self.lastSafeRepositionAt = os.clock()
				self:_setStatus("Repositioning to safe area")
				self:_tweenRoot(safeDestination, function()
					self:_groundSnap()
					self.safeStarting = false
					self.running = false
					task.delay(0.15, function()
						if not self.destroyed and self.enabled and self.planGeneration == planGeneration then
							self:_schedule()
						end
						end)
					end, nil, {
						flightProfile = true,
					})
				return
			end
		end
		self.safeStarting = false
		local primer = self:_choosePrimerEgg(record.Uid)
		if not primer then
			self.running = false
			self.activeTarget = nil

			self:_setStatus("Waiting for Forest primer")
			task.delay(0.25, function()
				if not self.destroyed and self.enabled and self.planGeneration == planGeneration then
					self:_schedule()
				end
				end)
			return
		end
		self.instantPhase = "priming"
		self.primerUid = primer.Uid
		self.skippedEggs[primer.Uid] = os.clock() + 30
		self.targetUid = record.Uid
		self.activeTarget = primer

		self:_showTreadmillDecoy()
		self:_installGuardHitDistanceBoost()
		self.stats.lastResult = "Instant priming"

		self.lowFpsPrime = currentFps() < 30
		local primerDest = self:_resolveEggDestination(primer, root, humanoid)
		if not primerDest then
			self:_finish("Primer destination unavailable")
			return
		end
		if self.lowFpsPrime then
			self:_setStatus("Gliding to Forest primer (low FPS)")
			self:_tweenRoot(primerDest, function()
				if self.instantPhase == "priming" and self.primerUid == primer.Uid then
					self:_requestCarry(primer, false)
				end
				end, nil, {
					holdAfterArrival = true,
					holdUid = primer.Uid,
					flightProfile = true,
					carryTarget = primer,
				})
			return
		end
		self:_setStatus("Teleporting to Forest primer")
		if not self:_teleportRoot(root, humanoid, primerDest) then
			self:_finish("Teleport primer failed")
			return
		end
		self:_setArrivalHold(primerDest, primer.Uid)
		self:_requestCarry(primer, true)
	end

	function EggRuntime:_leftTreadmill(root)
		local treadmill = Remotes.Treadmill
		if not treadmill then return true end
		local ok, ids = pcall(function() return treadmill.AskRenderSnapshot:InvokeServer() end)
		if ok and type(ids) == "table" and not table.find(ids, LocalPlayer.UserId) then
			return true
		end
		pcall(function() treadmill.AskDoff:InvokeServer() end)
		if root and root.Anchored then root.Anchored = false end
		return false
	end
	function EggRuntime:_reconcileRunningState()
		local shouldRun = self.userStealEnabled == true
		if self.enabled == shouldRun then
			if self.enabled then
				self:_refreshCounts()
				self:_schedule()
			end
			return
		end
		self.enabled = shouldRun
		if self.enabled then
			if LocalPlayer.Character then
				applyKillPartIgnore(LocalPlayer.Character)
				startHealthPinner(self, LocalPlayer.Character)
			end
			self:_installGuardHitDistanceBoost()
			self:_startMovementProtection()
			self:_setStatus("Searching")
			self:_schedule()
		else
			self.planGeneration += 1
			self.carry.generation += 1
			self:_cleanupInstantSteal()
			self:_removeGuardHitDistanceBoost()
			self:_invalidateCarryWorker()
			self._forestDropInProgress = nil
			self._instantReturnToken = nil
			self.carry.active = false
			self.carry.uid = nil
			self.tweenRecoveryUid = nil

			self.safeStarting = false
			self.movementRetryPending = false
			self:_cancelTween("Disabled")
			self:_restoreTreadmillVisualAtSafe()

			self:_stopMovementProtection()
			stopHealthPinner(self)
			self.activeTarget = nil
			self.running = false
			self:_setStatus("Idle")
		end
		self:_refreshCounts()
	end
	function EggRuntime:setEnabled(value)
		self.userStealEnabled = value == true
		self:_reconcileRunningState()
		if self.userStealEnabled then self:_startWatchdog() end
	end
	function EggRuntime:_resolveWeightKg(record)
		local util = self.weightUtil
		if not util or not record or not record.AssetScale or not record.AssetCategory then
			return nil
		end
		local ok, kg = pcall(util.WeightKgForScale, record.AssetCategory, record.AssetScale)
		if ok and type(kg) == "number" then
			return kg
		end
		return nil
	end
	resolveEggRate = function(record)
		if type(record) ~= "table" then return nil end
		local category = record.Category or record.AssetCategory
		local scale = tonumber(record.Scale or record.AssetScale)
		if type(category) ~= "string" or not scale or scale <= 0 then return nil end
		local mutations = type(record.Mutations) == "table" and table.clone(record.Mutations) or {}
		local item = {
			Category = category,
			Scale = scale,
			Mutations = mutations,
			BaseMutation = type(record.BaseMutation) == "string" and record.BaseMutation or nil,
		}
		local ok, rate = pcall(AssetEarnings.MutationOnlyRatePerSecond, item)
		return ok and type(rate) == "number" and rate or nil
	end
	function EggRuntime:setMinWeightKg(value)
		local num = tonumber(value) or 0
		self.config.minWeightKg = math.max(num, 0)
	end
	function EggRuntime:setMinValuePerSec(value)
		local num = tonumber(value) or 0
		self.config.minValuePerSec = math.max(num, 0)
		self:_refreshCounts()
		self:_schedule()
	end
	function EggRuntime:setSpeed(value)
		local inputSpeed = math.clamp(
			math.floor((tonumber(value) or DEFAULT_MOVEMENT_SPEED_INPUT) + 0.5),
			MIN_MOVEMENT_SPEED_INPUT,
			MAX_MOVEMENT_SPEED_INPUT
		)
		self.config.speed = inputSpeed * MOVEMENT_SPEED_MULTIPLIER
		if self.enabled or self.activeTween then
			self:_startMovementProtection()
		end
		return inputSpeed
	end
	function EggRuntime:setFilterEnabled(filter, value)
		self.config[filter .. "Enabled"] = value == true
		self:_refreshCounts()
		self:_schedule()
	end
	function EggRuntime:setFilter(filter, values)
		local normalized = type(values) == "table" and table.clone(values) or {}
		if filter == "mutations" and type(self.catalog.resolveMutationId) == "function" then
			local ids = {}
			for _, value in ipairs(normalized) do
				local id = self.catalog.resolveMutationId(value)
				if id then table.insert(ids, id) end
			end
			normalized = ids
		end
		self.config[filter] = normalized
		self:_refreshCounts()
		self:_schedule()
	end
	function EggRuntime:destroy()
		if self.destroyed then
			return
		end
		self.destroyed = true
		self.enabled = false
		self:_hideTreadmillDecoy()
		self.planGeneration += 1
		self.carry.generation += 1
		self:_invalidateCarryWorker()
		self.carry.active = false
		self.carry.uid = nil
		self.tweenRecoveryUid = nil
		self.safeStarting = false
		self:_cancelTween("Destroyed")
		self:_cleanupInstantSteal()
		self:_removeGuardHitDistanceBoost()

		self:_stopMovementProtection()
		if self._healthPinner then
			pcall(self._healthPinner.Disconnect, self._healthPinner)
			self._healthPinner = nil
		end
		if self._healthChangedConnection then
			pcall(self._healthChangedConnection.Disconnect, self._healthChangedConnection)
			self._healthChangedConnection = nil
		end
		restoreHumanoid(LocalPlayer.Character)
		disconnectAll(self.connections)
		table.clear(self.listeners)
		table.clear(self.records)

	end
	return EggRuntime
	end)()

local runtime = EggRuntime.new(catalog)
local controller = { Settings = Settings }
function controller.Start()
    assert(alive, "[LogicTP] Sudah Destroy; jalankan ulang file")
    runtime:setEnabled(false)
    Config.StealHoldSeconds = math.clamp(tonumber(Settings.Delay) or 15, 3, 20)
    runtime:setSpeed(Settings.Speed)
    runtime:setMinWeightKg(Settings.MinWeight)
    runtime:setMinValuePerSec(Settings.MinValue)
    for _, filter in ipairs({
        { "names", "name", Settings.Names },
        { "rarities", "rarity", Settings.Rarities },
        { "areas", "area", Settings.Areas },
        { "mutations", "mutation", Settings.Mutations },
    }) do
        local values = type(filter[3]) == "table" and filter[3] or {}
        runtime:setFilter(filter[1], values)
        runtime:setFilterEnabled(filter[2], #values > 0)
    end
    Settings.Enabled = true
    runtime:setEnabled(true)
end
function controller.Stop()
    if not alive then return end
    Settings.Enabled = false
    runtime:setEnabled(false)
end
function controller.Status()
    return runtime:getSnapshot()
end
function controller.Destroy()
    if not alive then return end
    alive = false
    Settings.Enabled = false
    runtime:destroy()
    fpsConnection:Disconnect()
    if env.LogicTP == controller then env.LogicTP = nil end
end
env.LogicTP = controller
if Settings.Enabled then controller.Start() end
return controller
