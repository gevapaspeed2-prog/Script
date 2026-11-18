--==========================================================================
--  QUICKSILVER v7
--  Flash (разгон, следы, afterimage, пыль) + Time Stop / Slow-mo
--  + Invis + Aim Lock + ULTRA DODGE (blink-уворот) + выбор цели
--  + фоновая музыка + меню по зажатию
--  R6 + R15 | Mobile / Arceus X friendly
--==========================================================================

local env = (type(getgenv) == "function" and getgenv()) or _G
if env.__QS_UNLOAD then pcall(env.__QS_UNLOAD) end

pcall(function()
	local o = game:GetService("CoreGui"):FindFirstChild("FlashGUI")
	if o then o:Destroy() end
end)
pcall(function()
	local o = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("FlashGUI")
	if o then o:Destroy() end
end)
pcall(function()
	if type(gethui) == "function" then
		local o = gethui():FindFirstChild("FlashGUI")
		if o then o:Destroy() end
	end
end)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

--==========================================================================
-- UTILS
--==========================================================================
local alive = true
local conns = {}
local function track(c) conns[#conns + 1] = c return c end
local function rand(a, b) return a + math.random() * (b - a) end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(obj, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, obj)
end

--==========================================================================
-- SETTINGS
--==========================================================================
local K = {}
K.FOLDER = "Quicksilver"
K.MUSIC_FOLDER = K.FOLDER .. "/music"
K.CACHE_FOLDER = K.FOLDER .. "/cache"
K.SETTINGS_FILE = K.FOLDER .. "/settings.json"

local function fsWorks()
	if not (type(isfile) == "function" and type(writefile) == "function" and type(readfile) == "function") then
		return false
	end
	local ok = pcall(function()
		writefile("qs_test.txt", "1")
		assert(readfile("qs_test.txt") == "1")
		if type(delfile) == "function" then delfile("qs_test.txt") end
	end)
	return ok
end

local hasFS = fsWorks()
local hasGCA = type(getcustomasset) == "function" or type(getsynasset) == "function"

local DEFAULTS = {
	track = "Sweet Dreams",
	musicOn = true,
	volume = 4.5,
	stopDuration = 0,
	invisOnStop = true,
	freezeReplication = true,
	shake = true,
	maxSpeed = 300,
	instantSpeed = false,
	trails = true,
	afterimages = true,
	arcs = true,
	dust = true,
	dynamicFov = true,
	autoDodge = true,
	dodgeRadius = 12,
	dodgeDist = 6,
	dodgePlayers = true,
	dodgeProj = true,
	dodgeRadar = false,
	aimLock = false,
	capeMode = "gradient",
	capeTop = "E6EBF5",
	capeBottom = "3A4252",
	capeImage = "",
	capePreset = 1,
	capeParts = 4,
	timeMode = "stop",
	slowFactor = 0.2,
	musicLoop = true,
	boom = true,
	boomSound = true,
	theme = "Silver",
	menuLayout = "Classic",
	capeAnim = "Cascade",
	language = "English",
	profileSlot = 1,
	profiles = {},
	customTracks = {},
}

local Settings = {}
for k, v in pairs(DEFAULTS) do Settings[k] = (type(v) == "table") and {} or v end

if hasFS then
	pcall(function()
		if type(makefolder) == "function" and type(isfolder) == "function" then
			for _, f in ipairs({ K.FOLDER, K.MUSIC_FOLDER, K.CACHE_FOLDER }) do
				if not isfolder(f) then makefolder(f) end
			end
		end
	end)

	pcall(function()
		if isfile(K.SETTINGS_FILE) then
			local data = HttpService:JSONDecode(readfile(K.SETTINGS_FILE))
			for k, def in pairs(DEFAULTS) do
				if type(data[k]) == type(def) then Settings[k] = data[k] end
			end
			if type(data.pos) == "table" and type(data.pos.x) == "number" and type(data.pos.y) == "number" then
				Settings.pos = { x = data.pos.x, y = data.pos.y }
			end
		end
	end)
end

local saveQueued = false
local function saveSettings()
	if not hasFS or saveQueued then return end
	saveQueued = true
	task.delay(0.6, function()
		saveQueued = false
		pcall(function()
			writefile(K.SETTINGS_FILE, HttpService:JSONEncode(Settings))
		end)
	end)
end

--==========================================================================
-- CONSTANTS / COLORS
--==========================================================================
K.START_SPEED, K.ACCEL = 100, 18
K.TIMESTOP_SPEED = 48
K.DODGE_CD = 0.25
K.LOCK_HOLD, K.MENU_HOLD, K.DRAG_THRESHOLD = 0.65, 0.5, 8
local W, H = 184, 54
K.MENU_H = 184
K.DW = 224

-- общее состояние/функции (в таблице, чтобы не упираться в лимит локальных)
K.slow, K.movers = false, {}
K.boomArmed, K.lastBoom = true, 0
K.trailUntil = 0
K.fx = Color3.fromRGB(245, 247, 250)
K.ringP, K.ringA, K.musicLeft = 0, 0, nil
K.Theme, K.Menu = {}, {}

K.hash = function(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

K.fmtTime = function(t)
	t = math.max(0, math.floor(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end
K.VISIBLE_MIN = 24
K.FALLBACK_ID = "rbxassetid://91311956696414"

local C = {
	bg = Color3.fromRGB(13, 15, 19),
	row = Color3.fromRGB(30, 34, 41),
	rowHi = Color3.fromRGB(52, 58, 69),
	btn = Color3.fromRGB(48, 54, 64),
	off = Color3.fromRGB(70, 76, 88),
	on = Color3.fromRGB(190, 225, 255),
	accent = Color3.fromRGB(190, 225, 255),
	silver = Color3.fromRGB(210, 216, 224),
	light = Color3.fromRGB(245, 247, 250),
	dim = Color3.fromRGB(135, 145, 160),
	white = Color3.fromRGB(255, 255, 255),
	danger = Color3.fromRGB(255, 150, 150),
	capTop = Color3.fromRGB(30, 34, 42),
	capBot = Color3.fromRGB(10, 12, 16),
	bar = Color3.fromRGB(55, 61, 72),
}

local trailColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, C.white),
	ColorSequenceKeypoint.new(1, C.silver),
})

--==========================================================================
-- STATE
--==========================================================================
local char, humanoid, hrp
local normalSpeed, currentSpeed = 16, 16

local isFlash, isLocked, isDodging, isSelectingTarget = false, false, false, false
local stoppedtime, isInvisible = false, false
local stopToken, stopEndsAt = 0, nil
local bgMusic = false -- музыка включена вручную (играет независимо от Time Stop)

local targetPlayer, targetHighlight, targetConn
local aimHL
local lastDodge, dodgeArmed = 0, true

local bodyFX, trailObjs, trailsOn, dustEmitter = {}, {}, false, nil
local rotOverride = false
local fovLock, shakeAmt = false, 0
local baseFOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70

local timestop, timeresume, refreshLabels, showToast, toggleMenu, closeMenu
local applyLockVisual, setTarget, clearTarget, reloadMusic, unload
local menuOpen = false
local refreshers = {}
local function refreshAll()
	for _, f in ipairs(refreshers) do f() end
	if K.Language and K.Language.apply then K.Language.apply() end
end

local fxFolder = new("Folder", { Name = "QS_FX" }, Workspace)
local cc = new("ColorCorrectionEffect", { Name = "QS_CC", Enabled = false }, Lighting)
local blur = new("BlurEffect", { Name = "QS_Blur", Size = 0, Enabled = false }, Lighting)

--==========================================================================
-- MUSIC
--==========================================================================
local TRACKS = {
	{
		name = "Time in a Bottle",
		file = "TimeInABottle_TS.mp3",
		url = "https://cdn.discordapp.com/attachments/1571663353967935639/1571663457743282226/Time_in_a_Bottle.mp3?ex=6afb8d28&is=6afa3ba8&hm=144ef2e93b9fa272c7b999f505eee7b946d1603ebb35c4ec0077d46b6ea5836f&",
	},
	{
		name = "Sweet Dreams",
		file = "SweetDreams_TS.mp3",
		url = "https://cdn.discordapp.com/attachments/1571663353967935639/1571983605176082462/Eurythmics_-_Sweat_dreams.mp3?ex=6afcb751&is=6afb65d1&hm=68995f98b0c2b4b3d4b8f5e3e5f0e4d8f7d0e4e9a8b7c6d5e4f3a2b1c0d9e8f7&",
	},
}

local trackList = {}

local function buildTrackList()
	trackList = {}
	for _, t in ipairs(TRACKS) do trackList[#trackList + 1] = t end
	for _, ct in ipairs(Settings.customTracks or {}) do
		if type(ct) == "table" and ct.name and (ct.id or ct.url) then
			trackList[#trackList + 1] = ct
		end
	end
	pcall(function()
		if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(K.MUSIC_FOLDER) then
			for _, path in ipairs(listfiles(K.MUSIC_FOLDER)) do
				local lower = path:lower()
				if lower:match("%.mp3$") or lower:match("%.ogg$") then
					local base = path:match("([^/\\]+)$") or path
					local nm = base:gsub("%.%w+$", "")
					trackList[#trackList + 1] = { name = nm, localfile = path }
				end
			end
		end
	end)
	trackList[#trackList + 1] = { name = "Default", id = K.FALLBACK_ID }
end

buildTrackList()

K.addTrack = function(raw)
	local v = tostring(raw or ""):gsub("%s", "")
	if v == "" then return false, "empty" end

	local entry
	local id = v:match("^rbxassetid://(%d+)$") or (v:match("^%d+$") and v)

	if id then
		entry = { name = "ID " .. id, id = "rbxassetid://" .. id }
	elseif v:match("^https?://") then
		local clean = v:match("^[^?#]+") or v
		local base = clean:match("([^/]+)$") or "Custom"
		base = base:gsub("%.%w+$", ""):gsub("%%20", " "):gsub("[_%-]+", " ")
		if base == "" then base = "Custom" end
		local ext = (clean:match("%.(%w+)$") or "mp3"):lower()
		if ext ~= "mp3" and ext ~= "ogg" then ext = "mp3" end
		entry = { name = base:sub(1, 22), url = v, file = "custom_" .. K.hash(v) .. "." .. ext }
	else
		return false, "use a link or sound ID"
	end

	if #Settings.customTracks >= 20 then return false, "limit: 20 tracks" end

	local nm, n = entry.name, 1
	local function taken(x)
		for _, t in ipairs(trackList) do
			if t.name == x then return true end
		end
		return false
	end
	while taken(entry.name) do
		n = n + 1
		entry.name = nm .. " " .. n
	end

	table.insert(Settings.customTracks, entry)
	saveSettings()
	buildTrackList()
	Settings.track = entry.name
	reloadMusic()
	return true, entry.name
end

K.removeTrack = function()
	for i, t in ipairs(Settings.customTracks) do
		if t.name == Settings.track then
			table.remove(Settings.customTracks, i)
			if t.file and type(delfile) == "function" then
				pcall(delfile, K.CACHE_FOLDER .. "/" .. t.file)
			end
			buildTrackList()
			Settings.track = "Sweet Dreams"
			saveSettings()
			reloadMusic()
			return true
		end
	end
	return false
end

local function trackNames()
	local n = { "Random" }
	for _, t in ipairs(trackList) do n[#n + 1] = t.name end
	return n
end

local function httpGet(url)
	local fn = request or http_request or (syn and syn.request) or (http and http.request)
	if fn then
		local ok, res = pcall(fn, { Url = url, Method = "GET" })
		if ok and res and (res.StatusCode == nil or res.StatusCode == 200) and res.Body and #res.Body > 2000 then
			return res.Body
		end
		return nil
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and body and #body > 2000 then return body end
	return nil
end

local assetCache = {}

local function resolveTrack(tr)
	if tr.id then return tr.id end
	if assetCache[tr] then return assetCache[tr] end
	if not hasGCA or not hasFS then return nil end
	local gca = getcustomasset or getsynasset

	local ok, asset = pcall(function()
		if tr.localfile then return gca(tr.localfile) end
		local cached = K.CACHE_FOLDER .. "/" .. tr.file
		for _, p in ipairs({ cached, tr.file }) do
			if isfile(p) then
				if #readfile(p) > 2000 then return gca(p) end
				pcall(delfile, p)
			end
		end
		local body = httpGet(tr.url)
		if not body then return nil end
		writefile(cached, body)
		return gca(cached)
	end)

	if ok and asset then
		assetCache[tr] = asset
		return asset
	end
	return nil
end

local music = new("Sound", { Name = "QS_TimeStopMusic", Volume = 0, Looped = Settings.musicLoop }, SoundService)
local musicTween
local loadToken = 0

local function pickTrack()
	if Settings.track ~= "Random" then
		for _, t in ipairs(trackList) do
			if t.name == Settings.track then return t end
		end
	end
	return trackList[math.random(1, #trackList)]
end

local function prepareMusic(tr, autoplay)
	loadToken = loadToken + 1
	local my = loadToken
	task.spawn(function()
		local id = resolveTrack(tr)
		if my ~= loadToken or not alive then return end
		music.SoundId = id or K.FALLBACK_ID
		local t0 = os.clock()
		while alive and my == loadToken and not music.IsLoaded and os.clock() - t0 < 5 do
			task.wait(0.1)
		end
		if my ~= loadToken or not alive then return end
		if not music.IsLoaded and music.SoundId ~= K.FALLBACK_ID then
			music.SoundId = K.FALLBACK_ID
		end

		-- смена трека «на лету», пока музыка включена вручную
		if autoplay and bgMusic then
			if musicTween then musicTween:Cancel() end
			music.TimePosition = 0
			music.Volume = 0
			music:Play()
			musicTween = tween(music, 0.6, { Volume = Settings.volume })
		end
	end)
end

local pendingReload = false

reloadMusic = function()
	if bgMusic then
		pendingReload = false
		prepareMusic(pickTrack(), true)
		return
	end
	if music.IsPlaying then
		pendingReload = true
		return
	end
	pendingReload = false
	prepareMusic(pickTrack())
end

local function musicStart()
	if not Settings.musicOn then return end
	if musicTween then musicTween:Cancel() end
	music.TimePosition = 0
	music.Volume = 0
	music:Play()
	musicTween = tween(music, 1.4, { Volume = Settings.volume })
end

local function musicStop()
	if musicTween then musicTween:Cancel() end
	local tw = tween(music, 0.18, { Volume = 0 })
	musicTween = tw
	tw.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not stoppedtime and not bgMusic then
			music:Stop()
			if pendingReload or Settings.track == "Random" then reloadMusic() end
		end
	end)
end

-- ручное включение: играет в фоне, меню можно закрыть, Time Stop не прерывает
local function setBgMusic(on)
	bgMusic = on
	if on then
		if musicTween then musicTween:Cancel() end
		music.TimePosition = 0
		music.Volume = 0
		music:Play()
		musicTween = tween(music, 0.8, { Volume = Settings.volume })
		if showToast then showToast("MUSIC ON", 1.2) end
	else
		musicStop()
		if showToast then showToast("MUSIC OFF", 1) end
	end
end

K.toggleMusic = function()
	local audible = music.IsPlaying and music.Volume > 0.02
	setBgMusic(not audible)
end

-- трек доиграл (без Loop) -> выключаем флаг
music.Ended:Connect(function()
	if bgMusic then
		bgMusic = false
		if Settings.track == "Random" then reloadMusic() end
		if refreshLabels then refreshLabels() end
	end
end)

--==========================================================================
-- FX HELPERS
--==========================================================================
local function destroyBodyFX()
	for _, o in ipairs(bodyFX) do
		if o and o.Parent then o:Destroy() end
	end
	bodyFX, trailObjs, trailsOn = {}, {}, false
	if dustEmitter and dustEmitter.Parent then dustEmitter.Parent:Destroy() end
	dustEmitter = nil
end

local function buildBodyFX()
	destroyBodyFX()
	if not char or not hrp then return end

	local names = {
		"Head", "Left Arm", "LeftUpperArm", "Right Arm", "RightUpperArm",
		"Left Leg", "LeftUpperLeg", "Right Leg", "RightUpperLeg",
	}

	local parts = {}
	for _, n in ipairs(names) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then parts[#parts + 1] = p end
	end
	parts[#parts + 1] = hrp

	for _, part in ipairs(parts) do
		local a0 = new("Attachment", { Position = Vector3.new(0, 0.4, 0) }, part)
		local a1 = new("Attachment", { Position = Vector3.new(0, -0.4, 0) }, part)
		local tr = new("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = trailColor,
			Lifetime = 0.2,
			WidthScale = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			LightEmission = 0.5,
			FaceCamera = true,
			Enabled = false,
		}, part)

		bodyFX[#bodyFX + 1] = a0
		bodyFX[#bodyFX + 1] = a1
		bodyFX[#bodyFX + 1] = tr
		trailObjs[#trailObjs + 1] = tr
	end

	local att = new("Attachment", { Name = "QS_DustAtt", Position = Vector3.new(0, -2.8, 0) }, hrp)

	dustEmitter = new("ParticleEmitter", {
		Name = "QS_Dust",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = trailColor,
		LightEmission = 0.7,
		Rate = 28,
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Enabled = false,
	}, att)

	bodyFX[#bodyFX + 1] = att
end

local function setTrailsActive(on)
	if on == trailsOn then return end
	trailsOn = on
	for _, t in ipairs(trailObjs) do t.Enabled = on end
end

local function spawnArc()
	if not hrp then return end

	local origin = hrp.Position + Vector3.new(rand(-1.5, 1.5), rand(-2.5, 2.5), rand(-1.5, 1.5))
	local dir = Vector3.new(rand(-1, 1), rand(-0.5, 1), rand(-1, 1))
	if dir.Magnitude < 0.1 then dir = Vector3.new(0, 1, 0) end
	local finish = origin + dir.Unit * rand(3, 6)

	local function anchor(pos)
		return new("Part", {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Position = pos,
			Parent = fxFolder,
		})
	end

	local p0, p1 = anchor(origin), anchor(finish)
	local a0, a1 = new("Attachment", {}, p0), new("Attachment", {}, p1)
	local beam = new("Beam", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = trailColor,
		LightEmission = 1,
		LightInfluence = 0,
		Width0 = 0.2,
		Width1 = 0.05,
		Segments = 8,
		CurveSize0 = rand(-1.5, 1.5),
		CurveSize1 = rand(-1.5, 1.5),
		FaceCamera = true,
		Transparency = NumberSequence.new(0.1),
	}, p0)

	tween(beam, 0.2, { Width0 = 0, Width1 = 0 })
	Debris:AddItem(p0, 0.3)
	Debris:AddItem(p1, 0.3)
end

local function createAfterimage()
	if not char then return end
	for _, original in ipairs(char:GetChildren()) do
		if original:IsA("BasePart") and original.Name ~= "HumanoidRootPart" and original.Transparency < 1 then
			local ok, ghost = pcall(function() return original:Clone() end)
			if ok and ghost then
				for _, child in ipairs(ghost:GetChildren()) do
					if not child:IsA("DataModelMesh") then child:Destroy() end
				end
				if ghost:IsA("MeshPart") then ghost.TextureID = "" end
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanTouch = false
				ghost.CanQuery = false
				ghost.Material = Enum.Material.Neon
				ghost.Color = K.fx
				ghost.Transparency = 0.7
				ghost.CFrame = original.CFrame
				ghost.Parent = fxFolder
				tween(ghost, 0.32, { Transparency = 1 }, Enum.EasingStyle.Sine)
				Debris:AddItem(ghost, 0.4)
			end
		end
	end
end

do
	local bcc = new("ColorCorrectionEffect", { Name = "QS_BoomCC", Enabled = false }, Lighting)
	local bblur = new("BlurEffect", { Name = "QS_BoomBlur", Size = 0, Enabled = false }, Lighting)
	K.bcc, K.bblur = bcc, bblur
	local boomToken = 0

	local function ring(cf, d0, d1, t, col, thick, trans0)
		local p = new("Part", {
			Shape = Enum.PartType.Cylinder,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = col,
			Transparency = trans0 or 0.2,
			Size = Vector3.new(thick, d0, d0),
			CFrame = cf,
			Parent = fxFolder,
		})
		tween(p, t, { Size = Vector3.new(thick, d1, d1), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(p, t + 0.1)
	end

	local function sparks(pos, count, speedMin, speedMax)
		local a = new("Part", {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Position = pos,
			Parent = fxFolder,
		})
		local att = new("Attachment", {}, a)
		local em = new("ParticleEmitter", {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(C.white, C.accent),
			LightEmission = 1,
			Lifetime = NumberRange.new(0.35, 0.8),
			Speed = NumberRange.new(speedMin, speedMax),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 0,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, att)
		em:Emit(count)
		Debris:AddItem(a, 1.2)
	end

	-- переиспользуем в Ultra Dodge
	K.ring, K.sparks = ring, sparks

	K.boom = function()
		if not hrp or not humanoid then return end

		local pos = hrp.Position
		local dir = humanoid.MoveDirection
		if dir.Magnitude < 0.1 then dir = hrp.CFrame.LookVector end
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, -1) end
		dir = dir.Unit

		local col, accent = K.fx, C.accent

		-- 1) три кольца давления позади бегуна
		for i = 1, 3 do
			task.delay((i - 1) * 0.07, function()
				if not alive then return end
				local back = pos - dir * (1.2 + i * 1.6)
				local cf = CFrame.lookAt(back, back + dir) * CFrame.Angles(0, math.rad(90), 0)
				ring(cf, 4, 34 + i * 12, 0.7 + i * 0.12, (i == 2) and accent or col, 0.35, 0.15)
			end)
		end

		-- 2) диск ударной волны
		local disc = new("Part", {
			Size = Vector3.new(1, 1, 1),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = col,
			Transparency = 0.35,
			CFrame = CFrame.lookAt(pos - dir * 0.5, pos + dir),
			Parent = fxFolder,
		})
		local mesh = new("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(3, 3, 1) }, disc)
		tween(mesh, 0.5, { Scale = Vector3.new(38, 38, 7) }, Enum.EasingStyle.Quart)
		tween(disc, 0.55, { Transparency = 1 })
		Debris:AddItem(disc, 0.7)

		-- 3) кольца на земле + пыль
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char, fxFolder }
		local hit = Workspace:Raycast(pos, Vector3.new(0, -8, 0), rp)
		if hit then
			local gcf = CFrame.new(hit.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring(gcf, 3, 64, 0.85, col, 0.25, 0.25)
			ring(gcf, 2, 40, 0.55, accent, 0.2, 0.35)
			sparks(hit.Position + Vector3.new(0, 0.5, 0), 22, 14, 30)
		end

		-- 4) искры вокруг + остаточные образы
		sparks(pos, 46, 30, 70)
		createAfterimage()

		-- 5) камера: рывок FOV, тряска, вспышка и размытие
		local cam = Workspace.CurrentCamera
		if cam and not fovLock then
			fovLock = true
			tween(cam, 0.1, { FieldOfView = baseFOV + 38 })
			task.delay(0.1, function()
				local c = Workspace.CurrentCamera
				if c and alive then tween(c, 0.8, { FieldOfView = baseFOV + 28 }, Enum.EasingStyle.Quart) end
			end)
			task.delay(0.95, function() fovLock = false end)
		end

		if Settings.shake then shakeAmt = math.max(shakeAmt, 1.3) end

		boomToken = boomToken + 1
		local my = boomToken
		bcc.Enabled, bblur.Enabled = true, true
		bcc.Brightness, bcc.Contrast, bcc.TintColor = 0.32, 0.35, C.white:Lerp(accent, 0.2)
		bblur.Size = 16
		tween(bcc, 0.55, { Brightness = 0, Contrast = 0, TintColor = C.white }, Enum.EasingStyle.Quart)
		tween(bblur, 0.45, { Size = 0 })
		task.delay(0.7, function()
			if my == boomToken then
				bcc.Enabled, bblur.Enabled = false, false
			end
		end)

		-- 6) звук: два слоя (удар + низкий гул)
		if Settings.boomSound then
			for _, cfg in ipairs({ { 1.6, 0.9 }, { 1.0, 0.5 } }) do
				local snd = new("Sound", {
					SoundId = "rbxasset://sounds/impact_explosion_03.mp3",
					Volume = cfg[1],
					PlaybackSpeed = cfg[2],
				}, SoundService)
				snd:Play()
				Debris:AddItem(snd, 4)
			end
		end
	end
end

--==========================================================================
-- TIME STOP
--==========================================================================
local frozenParts, frozenEmitters, frozenSounds, frozenTracks, animConns = {}, {}, {}, {}, {}
local smokeAnchor

local function isOurs(inst)
	return (char and inst:IsDescendantOf(char)) or inst:IsDescendantOf(fxFolder)
end

local function freezeAnimator(an)
	local f = K.slow and Settings.slowFactor or 0

	local function freezeTrack(tr)
		if frozenTracks[tr] == nil then
			frozenTracks[tr] = tr.Speed
			pcall(function() tr:AdjustSpeed(tr.Speed * f) end)
		end
	end

	for _, tr in ipairs(an:GetPlayingAnimationTracks()) do freezeTrack(tr) end

	animConns[#animConns + 1] = an.AnimationPlayed:Connect(function(tr)
		if stoppedtime then freezeTrack(tr) end
	end)
end

local function freezeWorld(token)
	local n = 0
	local slow = K.slow
	local f = slow and Settings.slowFactor or 0

	K.movers = {}
	local movers = K.movers

	for _, v in ipairs(Workspace:GetDescendants()) do
		if token ~= stopToken or not stoppedtime then return end

		if v:IsA("BasePart") then
			if not v.Anchored and not isOurs(v) then
				local mdl = slow and v:FindFirstAncestorOfClass("Model") or nil
				local hum = mdl and mdl:FindFirstChildOfClass("Humanoid") or nil

				if hum then
					-- в слоу-мо персонажей не якорим: двигаем корень вручную
					if v.Name == "HumanoidRootPart" and #movers < 120 then
						local rp = RaycastParams.new()
						rp.FilterType = Enum.RaycastFilterType.Exclude
						rp.FilterDescendantsInstances = { char, fxFolder, mdl }
						movers[#movers + 1] = {
							part = v,
							vel = v.AssemblyLinearVelocity,
							hum = hum,
							char = true,
							rp = rp,
						}
					end
				else
					local vel = v.AssemblyLinearVelocity
					frozenParts[#frozenParts + 1] = { v, vel, v.AssemblyAngularVelocity }
					v.Anchored = true

					if slow and vel.Magnitude > 6 and #movers < 120 then
						local list = { char, fxFolder, v }
						local ok, conn = pcall(function() return v:GetConnectedParts(true) end)
						if ok and #conn <= 80 then
							for _, cp in ipairs(conn) do list[#list + 1] = cp end
						end
						local rp = RaycastParams.new()
						rp.FilterType = Enum.RaycastFilterType.Exclude
						rp.FilterDescendantsInstances = list
						movers[#movers + 1] = { part = v, vel = vel, rp = rp }
					end
				end
			end
		elseif v:IsA("ParticleEmitter") then
			if not isOurs(v) then
				frozenEmitters[v] = v.TimeScale
				tween(v, 2.5, { TimeScale = v.TimeScale * f })
			end
		elseif v:IsA("Sound") then
			if not isOurs(v) then
				frozenSounds[v] = v.PlaybackSpeed
				tween(v, 2.5, { PlaybackSpeed = v.PlaybackSpeed * f })
			end
		elseif v:IsA("Animator") then
			if not isOurs(v) then freezeAnimator(v) end
		end

		n = n + 1
		if n % 1500 == 0 then task.wait() end
	end
end

local function unfreezeWorld()
	for _, e in ipairs(frozenParts) do
		local p = e[1]
		if p and p.Parent then
			p.Anchored = false
			pcall(function()
				p.AssemblyLinearVelocity = e[2]
				p.AssemblyAngularVelocity = e[3]
			end)
		end
	end
	frozenParts = {}

	for em, ts in pairs(frozenEmitters) do
		if em.Parent then tween(em, 1, { TimeScale = ts }) end
	end
	frozenEmitters = {}

	for s, sp in pairs(frozenSounds) do
		if s.Parent then tween(s, 1, { PlaybackSpeed = sp }) end
	end
	frozenSounds = {}

	for tr, sp in pairs(frozenTracks) do
		pcall(function() tr:AdjustSpeed(sp) end)
	end
	frozenTracks = {}

	for _, c in ipairs(animConns) do c:Disconnect() end
	animConns = {}
	K.movers = {}
end

local function setReplicationLag(on)
	pcall(function()
		settings().Network.IncomingReplicationLag = on and 1000 or 0
	end)
end

local function createSmoke()
	if not hrp then return end
	if smokeAnchor and smokeAnchor.Parent then smokeAnchor:Destroy() end

	local anchor = new("Part", {
		Name = "QS_Smoke",
		Size = Vector3.new(0.1, 0.1, 0.1),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Position = hrp.Position,
		Parent = fxFolder,
	})

	local att = new("Attachment", {}, anchor)

	local smoke = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 245, 250)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 210, 220)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 170, 185)),
		}),
		LightEmission = 0.3,
		LightInfluence = 0.25,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.35, 3.2),
			NumberSequenceKeypoint.new(1, 6.5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.4, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(4, 5.5),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Rate = 110,
		Enabled = true,
	}, att)

	local smoke2 = smoke:Clone()
	smoke2.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.4, 1.8),
		NumberSequenceKeypoint.new(1, 3.8),
	})
	smoke2.Speed = NumberRange.new(9, 17)
	smoke2.Rate = 70
	smoke2.Parent = att

	smokeAnchor = anchor

	task.delay(0.2, function()
		smoke.Enabled = false
		smoke2.Enabled = false
	end)

	task.delay(0.7, function()
		if stoppedtime and smoke.Parent then
			smoke.TimeScale = 0
			smoke2.TimeScale = 0
		end
	end)
end

local function shockwave()
	if not hrp then return end
	local pos = hrp.Position

	local ring = new("Part", {
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = C.light,
		Transparency = 0.3,
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(pos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = fxFolder,
	})

	tween(ring, 1.3, { Size = Vector3.new(0.4, 150, 150), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(ring, 1.5)

	for _, d in ipairs({ { 64, 1.1 }, { 48, 1.5 } }) do
		local s = new("Part", {
			Shape = Enum.PartType.Ball,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.ForceField,
			Color = C.white,
			Size = Vector3.new(1, 1, 1),
			Position = pos,
			Parent = fxFolder,
		})

		tween(s, d[2], { Size = Vector3.new(d[1], d[1], d[1]) }, Enum.EasingStyle.Quart)

		task.delay(d[2], function()
			if s.Parent then tween(s, 0.9, { Transparency = 1 }) end
		end)

		Debris:AddItem(s, d[2] + 1.1)
	end
end

local function stopIntro()
	local cam = Workspace.CurrentCamera
	fovLock = true

	if cam then
		tween(cam, 0.22, { FieldOfView = 112 })
		task.delay(0.22, function()
			local c = Workspace.CurrentCamera
			if c and alive then
				tween(c, 1.1, { FieldOfView = baseFOV }, Enum.EasingStyle.Quart)
			end
		end)
	end

	task.delay(1.5, function() fovLock = false end)

	if Settings.shake then shakeAmt = 0.9 end

	cc.Enabled, blur.Enabled = true, true
	cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = 0.25, 0.6, 0, C.white
	blur.Size = 28

	tween(cc, 0.9, {
		Brightness = 0,
		Contrast = 0.12,
		Saturation = -0.85,
		TintColor = Color3.fromRGB(215, 225, 240),
	})
	tween(blur, 0.8, { Size = 0 })
end

do
	K.slowIntro = function()
		local cam = Workspace.CurrentCamera
		fovLock = true

		if cam then
			tween(cam, 0.3, { FieldOfView = baseFOV + 22 })
			task.delay(0.3, function()
				local c = Workspace.CurrentCamera
				if c and alive then tween(c, 1.4, { FieldOfView = baseFOV }, Enum.EasingStyle.Quart) end
			end)
		end

		task.delay(1.8, function() fovLock = false end)

		if Settings.shake then shakeAmt = 0.4 end

		cc.Enabled, blur.Enabled = true, true
		cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = 0.14, 0.3, 0, C.white
		blur.Size = 14

		tween(cc, 1.1, {
			Brightness = 0,
			Contrast = 0.1,
			Saturation = -0.4,
			TintColor = C.white:Lerp(C.accent, 0.28),
		})
		tween(blur, 0.9, { Size = 0 })

		if not hrp then return end
		local pos = hrp.Position

		for i = 1, 3 do
			task.delay((i - 1) * 0.2, function()
				if not alive then return end
				local ring = new("Part", {
					Shape = Enum.PartType.Cylinder,
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Material = Enum.Material.Neon,
					Color = (i == 2) and C.accent or K.fx,
					Transparency = 0.3,
					Size = Vector3.new(0.25, 2, 2),
					CFrame = CFrame.new(pos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Parent = fxFolder,
				})
				tween(ring, 1.5, {
					Size = Vector3.new(0.25, 70 + i * 20, 70 + i * 20),
					Transparency = 1,
				}, Enum.EasingStyle.Quart)
				Debris:AddItem(ring, 1.6)
			end)
		end

		local sphere = new("Part", {
			Shape = Enum.PartType.Ball,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.ForceField,
			Color = C.accent,
			Size = Vector3.new(1, 1, 1),
			Position = pos,
			Transparency = 0.5,
			Parent = fxFolder,
		})
		tween(sphere, 1.6, { Size = Vector3.new(46, 46, 46), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(sphere, 1.7)
	end

	-- покадровое «замедленное» движение объектов и персонажей
	K.stepSlow = function(dt)
		local f = Settings.slowFactor
		local g = Workspace.Gravity
		local list = K.movers

		for i = #list, 1, -1 do
			local e = list[i]
			local p = e.part

			if not p.Parent then
				table.remove(list, i)
			else
				local v = e.vel

				if e.char then
					local hum = e.hum
					local air = hum and hum.Parent and hum.FloorMaterial == Enum.Material.Air

					if air then
						v = v + Vector3.new(0, -g * dt * f, 0)
					else
						v = Vector3.new(v.X, 0, v.Z)
					end

					local h = Vector3.new(v.X, 0, v.Z) * dt * f
					if h.Magnitude > 1e-4 then
						local r = Workspace:Raycast(p.Position, h + h.Unit * 1.4, e.rp)
						if r then
							v = Vector3.new(0, v.Y, 0)
							h = Vector3.zero
						end
					end

					local y = v.Y * dt * f
					if y < 0 then
						local r = Workspace:Raycast(p.Position, Vector3.new(0, y - 3.1, 0), e.rp)
						if r then
							v = Vector3.new(v.X, 0, v.Z)
							y = 0
						end
					end

					e.vel = v
					p.CFrame = p.CFrame + h + Vector3.new(0, y, 0)
				else
					local step = v * dt * f
					if step.Magnitude > 1e-4 then
						local r = Workspace:Raycast(p.Position, step + step.Unit * 0.5, e.rp)
						if r then
							v = v - r.Normal * v:Dot(r.Normal)
							e.vel = v
							step = v * dt * f
						end
						p.CFrame = p.CFrame + step
					end
				end
			end
		end
	end
end

timestop = function()
	if stoppedtime or not char or not humanoid or not hrp then return end

	stoppedtime = true
	stopToken = stopToken + 1
	local token = stopToken

	humanoid.WalkSpeed = isFlash and currentSpeed or K.TIMESTOP_SPEED
	K.slow = (Settings.timeMode == "slow")
	isInvisible = Settings.invisOnStop and not K.slow

	if Settings.freezeReplication or K.slow then setReplicationLag(true) end

	if K.slow then
		K.slowIntro()
	else
		createSmoke()
		shockwave()
		stopIntro()
	end

	-- если музыка уже включена вручную — она просто продолжает играть
	if not bgMusic then musicStart() end

	task.spawn(freezeWorld, token)

	stopEndsAt = (Settings.stopDuration > 0) and (os.clock() + Settings.stopDuration) or nil
	if refreshLabels then refreshLabels() end
end

timeresume = function()
	if not stoppedtime then return end

	stoppedtime = false
	stopToken = stopToken + 1
	stopEndsAt = nil
	isInvisible = false

	if humanoid then
		humanoid.WalkSpeed = isFlash and currentSpeed or normalSpeed
	end

	setReplicationLag(false)
	if not bgMusic then musicStop() end
	unfreezeWorld()

	if smokeAnchor and smokeAnchor.Parent then
		for _, d in ipairs(smokeAnchor:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
				tween(d, 0.3, { TimeScale = 4 })
			end
		end
		Debris:AddItem(smokeAnchor, 2)
	end
	smokeAnchor = nil

	tween(cc, 1.3, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = C.white })

	task.delay(1.4, function()
		if not stoppedtime then
			cc.Enabled = false
			blur.Enabled = false
		end
	end)

	if refreshLabels then refreshLabels() end
end

--==========================================================================
-- CAPE (визуальный, только для тебя; от 3 до 8 сегментов на пружинах)
--==========================================================================
local Cape = {}

do
local CAPE_PRESETS = {
	{ "Silver", "E6EBF5", "3A4252" },
	{ "Crimson", "FF5A5A", "4A0A12" },
	{ "Void", "8A5BFF", "0A0614" },
	{ "Gold", "FFE27A", "7A4A06" },
	{ "Ice", "BEE1FF", "1B3A66" },
	{ "Emerald", "7CFFB2", "06382A" },
}

local CAPE_TOTAL = 3.9

local cape, capeWanted, capeTween, lastTorsoPos = nil, false, nil, nil
local capeReveal = new("NumberValue", { Name = "QS_CapeReveal", Value = 0 }, fxFolder)
local capeImage, capeImageSrc, capeStatus = nil, nil, ""
local imageToken = 0

local function partsCount()
	return math.clamp(math.floor(tonumber(Settings.capeParts) or 4), 3, 8)
end

local function hexToColor(str)
	local h = tostring(str or ""):gsub("[#%s]", "")
	if #h == 6 and h:match("^%x+$") then
		return Color3.fromRGB(
			tonumber(h:sub(1, 2), 16),
			tonumber(h:sub(3, 4), 16),
			tonumber(h:sub(5, 6), 16)
		)
	end
	return nil
end

-- ---------- загрузка картинок (ID или ссылка Discord CDN) ----------
local function hashStr(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

local function fetchBytes(url)
	local fn = request or http_request or (syn and syn.request) or (http and http.request)
	if fn then
		local ok, res = pcall(fn, { Url = url, Method = "GET" })
		if ok and res and (res.StatusCode == nil or res.StatusCode == 200) and res.Body and #res.Body > 100 then
			return res.Body
		end
		return nil
	end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok and body and #body > 100 then return body end
	return nil
end

-- done(content, err); content подходит для ImageLabel.Image
local function resolveImage(raw, done)
	if raw == "" then done(nil) return end

	if raw:match("^%d+$") then
		done("rbxassetid://" .. raw)
		return
	end

	if raw:match("^https?://") and not raw:find("roblox.com/asset", 1, true) then
		if not (hasFS and hasGCA) then
			done(nil, "executor has no file/asset support")
			return
		end

		local gca = getcustomasset or getsynasset
		local clean = raw:match("^[^?#]+") or raw
		local ext = (clean:match("%.(%w+)$") or "png"):lower()
		if #ext > 4 then ext = "png" end

		imageToken = imageToken + 1
		local my = imageToken

		task.spawn(function()
			local path = K.CACHE_FOLDER .. "/cape_" .. hashStr(raw) .. "." .. ext

			local ok, asset = pcall(function()
				if isfile(path) and #readfile(path) > 100 then
					return gca(path)
				end
				local body = fetchBytes(raw)
				if not body then return nil end
				writefile(path, body)
				return gca(path)
			end)

			if my ~= imageToken or not alive then return end

			if ok and asset then
				done(asset)
			else
				done(nil, "download failed (link expired?)")
			end
		end)
		return
	end

	done(raw)
end

-- ---------- рисование сегментов ----------
local function paintSegment(seg, i, n)
	local a = hexToColor(Settings.capeTop) or C.silver
	local b = hexToColor(Settings.capeBottom) or C.dim
	local url = (Settings.capeMode == "image") and capeImage or nil

	for _, cg in ipairs(seg.groups) do
		cg:ClearAllChildren()

		local bg = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.white,
			BorderSizePixel = 0,
			Visible = (url == nil),
		}, cg)

		new("UIGradient", {
			Color = ColorSequence.new(a:Lerp(b, (i - 1) / n), a:Lerp(b, i / n)),
			Rotation = 90,
		}, bg)

		if url then
			local clip = new("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			}, cg)

			new("ImageLabel", {
				Size = UDim2.new(1, 0, n, 0),
				Position = UDim2.new(0, 0, -(i - 1), 0),
				BackgroundTransparency = 1,
				Image = url,
				ScaleType = Enum.ScaleType.Stretch,
			}, clip)
		end
	end
end

local repaintCape

repaintCape = function()
	if not cape then return end
	for i, seg in ipairs(cape.segs) do paintSegment(seg, i, cape.n) end
end

local function applyImage()
	local raw = tostring(Settings.capeImage or ""):gsub("%s", "")

	if Settings.capeMode ~= "image" or raw == "" then
		capeImage, capeImageSrc, capeStatus = nil, nil, ""
		repaintCape()
		return
	end

	if capeImageSrc == raw and capeImage then
		repaintCape()
		return
	end

	capeImage, capeImageSrc, capeStatus = nil, raw, "loading image..."
	repaintCape()

	resolveImage(raw, function(content, err)
		if capeImageSrc ~= raw then return end
		capeImage = content
		if content then
			capeStatus = "image loaded"
		else
			capeStatus = "image failed: " .. tostring(err or "unknown")
			showToast("Image failed: " .. tostring(err or "unknown"), 2.5)
		end
		repaintCape()
		refreshAll()
	end)
end

local function destroyCape()
	if cape then
		for _, sg in ipairs(cape.segs) do
			if sg.part then sg.part:Destroy() end
		end
	end
	cape, lastTorsoPos = nil, nil
end

local function buildCape()
	destroyCape()
	if not char then return false end

	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	if not torso then return false end

	local n = partsCount()

	cape = {
		torso = torso,
		n = n,
		L = CAPE_TOTAL / n,
		segs = {},
		ang = {}, vel = {}, roll = {}, rvel = {}, lastPe = {},
		k = {}, d = {},
	}

	local wTop, wBot = torso.Size.X + 0.1, torso.Size.X + 0.9

	for i = 1, n do
		cape.ang[i], cape.vel[i], cape.roll[i], cape.rvel[i], cape.lastPe[i] = -0.04, 0, 0, 0, -1
		cape.k[i] = 70 - 32 * (i - 1) / (n - 1)
		cape.d[i] = 9 - 2.8 * (i - 1) / (n - 1)

		local w = wTop + (wBot - wTop) * (i - 0.5) / n

		local part = new("Part", {
			Name = "QS_Cape" .. i,
			Size = Vector3.new(w, cape.L + 0.08, 0.06),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Massless = true,
			Parent = fxFolder,
		})

		local seg = { part = part, groups = {}, w = w }

		for _, face in ipairs({ Enum.NormalId.Back, Enum.NormalId.Front }) do
			local sg = new("SurfaceGui", {
				Face = face,
				LightInfluence = 0.35,
				ResetOnSpawn = false,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, part)
			sg.Adornee = part

			seg.groups[#seg.groups + 1] = new("CanvasGroup", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				GroupTransparency = 1,
			}, sg)
		end

		cape.segs[i] = seg
		paintSegment(seg, i, n)
	end

	if Settings.capeMode == "image" then
		local raw = tostring(Settings.capeImage or ""):gsub("%s", "")
		if raw ~= "" and capeImageSrc ~= raw then applyImage() end
	end

	return true
end

local function rebuildCape()
	if cape then
		if not buildCape() then capeWanted = false end
	end
end

local function capeBurst()
	if not cape then return end

	local pos = cape.torso.Position
	local col = hexToColor(Settings.capeTop) or C.silver

	local a = new("Part", {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Position = pos,
		Parent = fxFolder,
	})

	local att = new("Attachment", {}, a)

	local em = new("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(col, C.white),
		LightEmission = 0.8,
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, att)

	em:Emit(26)
	Debris:AddItem(a, 1.5)

	local ring = new("Part", {
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = col,
		Transparency = 0.35,
		Size = Vector3.new(0.2, 1, 1),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = fxFolder,
	})

	tween(ring, 0.7, { Size = Vector3.new(0.2, 11, 11), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(ring, 0.8)
end

local function setCape(on)
	if on and not isLocked then
		showToast("ARM FIRST: HOLD ⚡", 1.6)
		return
	end

	capeWanted = on
	if capeTween then capeTween:Cancel() end

	if on then
		if not cape or not cape.torso.Parent then
			if not buildCape() then
				capeWanted = false
				showToast("Cape: no torso found")
				return
			end
			capeReveal.Value = 0
		end

		capeBurst()
		local anim = Settings.capeAnim or "Cascade"
		local duration = (anim == "Materialize") and 1.15 or ((anim == "Sweep") and 1.35 or 1.7)
		local style = (anim == "Materialize") and Enum.EasingStyle.Back or ((anim == "Sweep") and Enum.EasingStyle.Quint or Enum.EasingStyle.Sine)
		capeTween = tween(capeReveal, duration, { Value = 1 }, style, Enum.EasingDirection.Out)
		showToast("CAPE ON · " .. anim, 1.2)
	else
		local tw = tween(capeReveal, 0.8, { Value = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		capeTween = tw
		tw.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not capeWanted then
				destroyCape()
			end
		end)
		showToast("CAPE OFF", 1)
	end
end

local function updateCape(dt)
	if not cape or not hrp then return end

	local torso = cape.torso
	if not torso.Parent then return end

	local tcf = torso.CFrame

	-- защита от трюка невидимости (hrp на мгновение улетает вниз)
	if lastTorsoPos and (tcf.Position - lastTorsoPos).Magnitude > 500 then return end
	lastTorsoPos = tcf.Position

	dt = math.min(dt, 1 / 30)

	local n = cape.n
	local vel = hrp.AssemblyLinearVelocity
	local hcf = hrp.CFrame
	local fN = math.clamp(vel:Dot(hcf.LookVector) / 55, -1, 1.4)
	local lN = math.clamp(vel:Dot(hcf.RightVector) / 45, -1, 1)
	local fall = math.clamp(-vel.Y / 70, 0, 1)
	local rise = math.clamp(vel.Y / 60, 0, 1)
	local speedF = math.clamp(vel.Magnitude / 60, 0, 1)
	local fw, bw = math.max(fN, 0), math.max(-fN, 0)
	local t = os.clock()
	local rv = capeReveal.Value
	local share = 1 / (n - 1)

	local prev = tcf * CFrame.new(0, torso.Size.Y / 2 - 0.12, torso.Size.Z / 2 + 0.04)

	for i = 1, n do
		local seg = cape.segs[i]

		-- каскадное раскрытие: сегменты разворачиваются по очереди
		local anim = Settings.capeAnim or "Cascade"
		local p
		if anim == "Sweep" then
			p = math.clamp(rv * 1.45 - (i - 1) * 0.42 * share, 0, 1)
		elseif anim == "Materialize" then
			p = math.clamp((rv - (i - 1) * 0.10 * share) * 1.9, 0, 1)
		else
			p = math.clamp(rv * 1.7 - (i - 1) * 0.7 * share, 0, 1)
		end
		local pe = p * p * (3 - 2 * p)

		local flutter = math.sin(t * (1.6 + i * 0.5)) * 0.03
			+ math.sin(t * 22 + i * 1.9) * 0.05 * speedF

		local target
		if i == 1 then
			target = -0.06 - 0.95 * fw + 0.3 * bw - 0.5 * fall + 0.1 * rise + flutter
			target = target - (1 - pe) * 1.3
		else
			target = -0.03 - 0.6 * share * fw + 0.4 * share * bw - 0.5 * share * fall + flutter
			target = target - (1 - pe) * 1.6 * share
		end

		local k, d = cape.k[i], cape.d[i]
		local a, v = cape.ang[i], cape.vel[i]
		v = v + (k * (target - a) - d * v) * dt
		a = a + v * dt
		if i == 1 then
			a = math.clamp(a, -1.7, -0.02)
		else
			a = math.clamp(a, -1.2, 0.45)
		end
		cape.ang[i], cape.vel[i] = a, v

		local rT = -lN * 0.4 * (0.6 + 0.6 * i / n) + math.sin(t * 1.3 + i) * 0.02
		local r, rvl = cape.roll[i], cape.rvel[i]
		rvl = rvl + (k * 0.7 * (rT - r) - d * rvl) * dt
		r = math.clamp(r + rvl * dt, -0.8, 0.8)
		cape.roll[i], cape.rvel[i] = r, rvl

		local Ls = cape.L * (0.2 + 0.8 * pe)
		local pivot = prev * CFrame.Angles(a, 0, r)

		seg.part.Size = Vector3.new(seg.w * (0.3 + 0.7 * pe), Ls + 0.08, 0.06)
		seg.part.CFrame = pivot * CFrame.new(0, -Ls / 2, 0)
		prev = pivot * CFrame.new(0, -Ls, 0)

		if cape.lastPe[i] ~= pe then
			cape.lastPe[i] = pe
			for _, cg in ipairs(seg.groups) do
				cg.GroupTransparency = 1 - pe
			end
		end
	end
end

Cape.set = setCape
Cape.update = updateCape
Cape.destroy = destroyCape
Cape.build = buildCape
Cape.rebuild = rebuildCape
Cape.repaint = repaintCape
Cape.applyImage = applyImage
Cape.hex = hexToColor
Cape.presets = CAPE_PRESETS
Cape.reveal = capeReveal
Cape.isOn = function() return capeWanted end
Cape.status = function() return capeStatus end

end

--==========================================================================
-- TARGET / AIM LOCK
--==========================================================================
local function nearestOther(maxDist)
	if not hrp then return nil end

	local bestHRP, bestChar, bestD = nil, nil, maxDist

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and plr.Character then
			local t = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")

			if t and hum and hum.Health > 0 then
				local d = (hrp.Position - t.Position).Magnitude
				if d < bestD then
					bestHRP, bestChar, bestD = t, plr.Character, d
				end
			end
		end
	end

	return bestHRP, bestChar, bestD
end

local function attachHighlight()
	if targetHighlight then
		targetHighlight:Destroy()
		targetHighlight = nil
	end

	if targetPlayer and targetPlayer.Character then
		targetHighlight = new("Highlight", {
			FillColor = C.light,
			FillTransparency = 0.94,
			OutlineColor = C.white,
			OutlineTransparency = 0.3,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}, targetPlayer.Character)
	end
end

clearTarget = function()
	if targetHighlight then
		targetHighlight:Destroy()
		targetHighlight = nil
	end
	if targetConn then
		targetConn:Disconnect()
		targetConn = nil
	end

	targetPlayer = nil
	isSelectingTarget = false
	dodgeArmed = true
end

setTarget = function(plr)
	if not plr or plr == player then return end

	clearTarget()
	targetPlayer = plr
	attachHighlight()

	targetConn = plr.CharacterAdded:Connect(function()
		task.wait(0.5)
		attachHighlight()
	end)

	if showToast then showToast("TARGET: " .. plr.DisplayName) end
	refreshAll()
end

local function clearAimHL()
	if aimHL then
		aimHL:Destroy()
		aimHL = nil
	end
end

local function updateAim()
	local want = Settings.aimLock and isLocked and not stoppedtime and not isDodging

	if want and hrp and humanoid then
		local t, tc
		if targetPlayer and targetPlayer.Character then
			tc = targetPlayer.Character
			t = tc:FindFirstChild("HumanoidRootPart")
		end
		if not t then t, tc = nearestOther(150) end

		if t then
			if not rotOverride then
				rotOverride = true
				humanoid.AutoRotate = false
			end

			local lookAt = Vector3.new(t.Position.X, hrp.Position.Y, t.Position.Z)
			if (lookAt - hrp.Position).Magnitude > 0.5 then
				hrp.CFrame = CFrame.new(hrp.Position, lookAt)
			end

			if not aimHL or aimHL.Parent ~= tc then
				clearAimHL()
				aimHL = new("Highlight", {
					FillColor = C.white,
					FillTransparency = 0.85,
					OutlineColor = C.white,
					OutlineTransparency = 0.1,
					DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				}, tc)
			end
			return
		end
	end

	clearAimHL()
	if rotOverride and not isDodging then
		rotOverride = false
		if humanoid then humanoid.AutoRotate = true end
	end
end

--==========================================================================
-- ULTRA DODGE  (гибрид: мгновенный blink-уворот от приближающихся
--               игроков и снарядов + красивые эффекты и радар)
--==========================================================================
do
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude

	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.MaxParts = 80

	local lastSeen = setmetatable({}, { __mode = "k" })
	local armedAt = setmetatable({}, { __mode = "k" })
	local filterChar

	local PROJ = { "hitbox", "bullet", "projectile", "missile", "fireball" }
	local ANGLES = { 80, -80, 50, -50, 115, -115, 0, 170 }

	local function setFilters()
		if filterChar ~= char then
			filterChar = char
			local list = { fxFolder }
			if char then list[2] = char end
			rp.FilterDescendantsInstances = list
			op.FilterDescendantsInstances = list
		end
	end

	local function isProjectile(part)
		if part:GetAttribute("IsProjectile") == true then return true end
		local n = part.Name:lower()
		for _, key in ipairs(PROJ) do
			if n:find(key, 1, true) then return true end
		end
		return false
	end

	local function feetPos(pos)
		local g = Workspace:Raycast(pos, Vector3.new(0, -8, 0), rp)
		return (g and g.Position or (pos - Vector3.new(0, 2.8, 0))) + Vector3.new(0, 0.12, 0)
	end

	-- ищем безопасную точку: чистый путь, под ногами земля, не обрыв
	local function findSpot(from, threatPos)
		local away = Vector3.new(from.X - threatPos.X, 0, from.Z - threatPos.Z)
		if away.Magnitude < 0.1 then away = Vector3.new(rand(-1, 1), 0, rand(-1, 1)) end
		if away.Magnitude < 0.05 then away = Vector3.new(1, 0, 0) end
		away = away.Unit

		local dist = Settings.dodgeDist
		local flip = math.random(1, 2) == 1 and 1 or -1
		local g0 = Workspace:Raycast(from, Vector3.new(0, -10, 0), rp)

		for _, deg in ipairs(ANGLES) do
			local a = math.rad(deg * flip)
			local c, s = math.cos(a), math.sin(a)
			local dir = Vector3.new(away.X * c - away.Z * s, 0, away.X * s + away.Z * c)
			local target = from + dir * dist

			if not Workspace:Raycast(from, dir * (dist + 1.5), rp) then
				local g = Workspace:Raycast(target + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), rp)
				if g then
					local dy = g0 and (g.Position.Y - g0.Position.Y) or 0
					if math.abs(dy) <= 4.5 then
						return Vector3.new(target.X, from.Y + dy, target.Z)
					end
				end
			end
		end

		return nil
	end

	local function anchorAt(pos)
		return new("Part", {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Position = pos,
			Parent = fxFolder,
		})
	end

	K.dodgeFX = function(from, to, threat)
		K.trailUntil = os.clock() + 0.5

		-- световой росчерк между точками
		local p0 = anchorAt(from + Vector3.new(0, 0.4, 0))
		local p1 = anchorAt(to + Vector3.new(0, 0.4, 0))
		local a0, a1 = new("Attachment", {}, p0), new("Attachment", {}, p1)
		local beam = new("Beam", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = trailColor,
			LightEmission = 1,
			LightInfluence = 0,
			Width0 = 0.9,
			Width1 = 0.9,
			Segments = 1,
			FaceCamera = true,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 0.5),
			}),
		}, p0)
		tween(beam, 0.32, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quart)
		Debris:AddItem(p0, 0.4)
		Debris:AddItem(p1, 0.4)

		-- кольца и искры в обеих точках
		if K.ring then
			K.ring(CFrame.new(feetPos(to)) * CFrame.Angles(0, 0, math.rad(90)), 2, 20, 0.55, K.fx, 0.2, 0.25)
			K.ring(CFrame.new(feetPos(from)) * CFrame.Angles(0, 0, math.rad(90)), 2, 14, 0.45, C.accent, 0.15, 0.4)
		end
		if K.sparks then
			K.sparks(to + Vector3.new(0, 0.5, 0), 20, 10, 26)
			K.sparks(from + Vector3.new(0, 0.5, 0), 16, 8, 22)
		end

		spawnArc()
		spawnArc()

		-- камера: короткий рывок FOV + лёгкая тряска
		local cam = Workspace.CurrentCamera
		if cam and not fovLock then
			fovLock = true
			tween(cam, 0.07, { FieldOfView = cam.FieldOfView + 9 })
			task.delay(0.14, function() fovLock = false end)
		end
		if Settings.shake then shakeAmt = math.max(shakeAmt, 0.4) end

		-- подсветка источника угрозы
		if threat and threat.Parent then
			local hl = new("Highlight", {
				Name = "QS_DodgeHL",
				Adornee = threat,
				FillColor = C.accent,
				FillTransparency = 0.45,
				OutlineColor = C.white,
				OutlineTransparency = 0,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			}, fxFolder)
			tween(hl, 0.4, { FillTransparency = 1, OutlineTransparency = 1 })
			Debris:AddItem(hl, 0.5)
		end

		if K.dodgePulse then K.dodgePulse() end
		if K.radarPulse then K.radarPulse() end
	end

	local function doDodge(threatPos, threatObj)
		if not hrp or not humanoid or humanoid.Health <= 0 then return false end

		local from = hrp.Position
		local spot = findSpot(from, threatPos)
		if not spot then return false end

		pcall(createAfterimage) -- оставляем «призрак» в точке, откуда ушли

		local rot = hrp.CFrame - hrp.CFrame.Position
		hrp.CFrame = CFrame.new(spot) * rot

		if not isFlash then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end

		lastDodge = os.clock()
		K.dodgeFX(from, spot, threatObj)
		return true
	end

	K.dodgeScan = function(now)
		if not hrp or not humanoid or humanoid.Health <= 0 then return end
		if stoppedtime and not K.slow then return end
		if now - lastDodge < K.DODGE_CD then return end

		setFilters()

		local R = Settings.dodgeRadius
		local pos = hrp.Position
		local bestD, bestKey, bestPos, bestObj = math.huge, nil, nil, nil

		-- игроки: реагируем на тех, кто быстро приближается или вплотную
		if Settings.dodgePlayers then
			for _, plr in ipairs(Players:GetPlayers()) do
				local c = plr.Character
				if plr ~= player and c and (not targetPlayer or plr == targetPlayer) then
					local t = c:FindFirstChild("HumanoidRootPart")
					local hum = c:FindFirstChildOfClass("Humanoid")

					if t and hum and hum.Health > 0 then
						local d = (pos - t.Position).Magnitude
						local e = lastSeen[plr]
						local closing = 0
						if e and now - e[2] < 0.4 then
							closing = (e[1] - d) / math.max(now - e[2], 0.016)
						end
						lastSeen[plr] = { d, now }

						local armed = (not armedAt[plr]) or d > R * 1.05 or now - armedAt[plr] > 0.8
						if armed and d <= R and d < bestD and (closing >= 9 or d <= R * 0.4) then
							bestD, bestKey, bestPos, bestObj = d, plr, t.Position, c
						end
					end
				end
			end
		end

		-- снаряды / хитбоксы
		if Settings.dodgeProj then
			for _, part in ipairs(Workspace:GetPartBoundsInRadius(pos, R, op)) do
				if part ~= Workspace.Terrain and isProjectile(part) then
					local d = (part.Position - pos).Magnitude
					local e = lastSeen[part]
					local closing = 0
					if e and now - e[2] < 0.4 then
						closing = (e[1] - d) / math.max(now - e[2], 0.016)
					end
					lastSeen[part] = { d, now }

					local moving = part.AssemblyLinearVelocity.Magnitude > 5 or math.abs(closing) > 6
					local flagged = part:GetAttribute("IsProjectile") == true
					local armed = (not armedAt[part]) or now - armedAt[part] > 1

					if armed and d < bestD
						and ((moving and (closing > 4 or d <= R * 0.5)) or (flagged and d <= R * 0.6)) then
						bestD, bestKey, bestPos, bestObj = d, part, part.Position, part
					end
				end
			end
		end

		if bestKey then
			armedAt[bestKey] = now
			doDodge(bestPos, bestObj)
		end
	end

	-- ---------- радар на земле ----------
	local radarPart = new("Part", {
		Name = "QS_Radar",
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Size = Vector3.new(24, 0.02, 24),
	})
	K.radarPart = radarPart

	local sg = new("SurfaceGui", {
		Face = Enum.NormalId.Top,
		CanvasSize = Vector2.new(1000, 1000),
		LightInfluence = 0,
		ResetOnSpawn = false,
	}, radarPart)
	sg.Adornee = radarPart

	local spin = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
	}, sg)

	local ringF = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
	}, spin)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ringF)

	local ringStroke = new("UIStroke", { Thickness = 10, Color = C.accent, Transparency = 0.55 }, ringF)

	-- внутренняя зона «в упор» (0.4 радиуса)
	local innerF = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundTransparency = 1,
	}, spin)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, innerF)
	local innerStroke = new("UIStroke", { Thickness = 4, Color = C.accent, Transparency = 0.75 }, innerF)

	local sweep = new("Frame", {
		Size = UDim2.new(0.5, 0, 0, 14),
		Position = UDim2.new(0.5, 0, 0.5, -7),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
	}, spin)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sweep)

	local rcol

	K.radarStep = function(dt)
		local want = Settings.dodgeRadar and Settings.autoDodge and isLocked and hrp and humanoid
			and humanoid.Health > 0 and not (stoppedtime and not K.slow)

		if not want then
			if radarPart.Parent then radarPart.Parent = nil end
			return
		end

		if radarPart.Parent ~= fxFolder then radarPart.Parent = fxFolder end

		setFilters()

		local R = Settings.dodgeRadius
		if radarPart.Size.X ~= R * 2 then radarPart.Size = Vector3.new(R * 2, 0.02, R * 2) end

		spin.Rotation = (spin.Rotation + 140 * dt) % 360

		local g = Workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rp)
		local y = g and (g.Position.Y + 0.06) or (hrp.Position.Y - 2.9)
		radarPart.CFrame = CFrame.new(hrp.Position.X, y, hrp.Position.Z)

		-- цвета следуют за темой
		if rcol ~= C.accent then
			rcol = C.accent
			ringF.BackgroundColor3 = rcol
			ringStroke.Color = rcol
			innerStroke.Color = rcol
			sweep.BackgroundColor3 = rcol
		end
	end

	K.radarPulse = function()
		ringStroke.Transparency = 0.05
		ringF.BackgroundTransparency = 0.65
		tween(ringStroke, 0.55, { Transparency = 0.55 })
		tween(ringF, 0.55, { BackgroundTransparency = 0.9 })
	end
end

--==========================================================================
-- GUI  (капсула: две «орбы» + спидометр по центру)
--==========================================================================
local gui = new("ScreenGui", {
	Name = "FlashGUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(gui) end
end)

pcall(function()
	gui.Parent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end)

if not gui.Parent then
	gui.Parent = player:WaitForChild("PlayerGui")
end

local holder = new("Frame", {
	Name = "Holder",
	Size = UDim2.fromOffset(W, H),
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 120),
}, gui)

local holderScale = new("UIScale", { Scale = 0.6 }, holder)

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 1,
	ClipsDescendants = true,
}, holder)

corner(main, H / 2)

new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(30, 34, 42), Color3.fromRGB(10, 12, 16)),
	Rotation = 90,
}, main)

local stroke = new("UIStroke", {
	Color = C.silver,
	Thickness = 1.5,
	Transparency = 0.5,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, main)

-- блик сверху
local gloss = new("Frame", {
	Size = UDim2.new(1, -28, 0, 14),
	Position = UDim2.new(0, 14, 0, 3),
	BackgroundColor3 = C.white,
	BorderSizePixel = 0,
	ZIndex = 2,
}, main)
corner(gloss, 7)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Rotation = 90,
}, gloss)

local function makeOrb(xPos, icon)
	local orb = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = xPos,
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C.off,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, main)

	corner(orb, 20)

	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 156, 168)),
		Rotation = 90,
	}, orb)

	local st = new("UIStroke", {
		Color = C.white,
		Thickness = 1.2,
		Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, orb)

	local sc = new("UIScale", { Scale = 1 }, orb)

	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = icon,
		TextColor3 = Color3.fromRGB(20, 24, 30),
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		ZIndex = 4,
	}, orb)

	return orb, st, sc
end

local leftOrb, leftOrbStroke, leftOrbScale = makeOrb(UDim2.new(0, 27, 0.5, 0), "⚡")
local rightOrb, rightOrbStroke, rightOrbScale = makeOrb(UDim2.new(1, -27, 0.5, 0), "◉")

do
	local R, T = 52, 3
	local S = R - 2 * T - 2

	local root = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -27, 0.5, 0),
		Size = UDim2.fromOffset(R, R),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Visible = false,
	}, main)

	local trackRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S, S),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, root)
	corner(trackRing, R)

	local trackStroke = new("UIStroke", {
		Color = C.silver,
		Thickness = T,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, trackRing)

	local function half(side)
		local clip = new("Frame", {
			Position = UDim2.fromScale(side == "right" and 0.5 or 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 4,
		}, root)

		local ringF = new("Frame", {
			Position = UDim2.fromOffset(side == "right" and (-S / 2) or (R / 2 - S / 2), (R - S) / 2),
			Size = UDim2.fromOffset(S, S),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, clip)
		corner(ringF, R)

		local st = new("UIStroke", {
			Color = C.accent,
			Thickness = T,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ringF)

		local g = new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.499, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, st)

		return st, g
	end

	local stR, gR = half("right")
	local stL, gL = half("left")

	-- шкала остатка музыки: плавно появляется, убывает по часовой, плавно уходит
	K.ringStep = function(dt)
		local want = (stoppedtime or bgMusic) and music.IsPlaying
			and music.TimeLength > 0.5 and music.Volume > 0.02

		local tp = 0
		if want then
			tp = 1 - math.clamp(music.TimePosition / music.TimeLength, 0, 1)
			K.musicLeft = music.TimeLength - music.TimePosition
		else
			K.musicLeft = nil
		end

		K.ringP = K.ringP + (tp - K.ringP) * (1 - math.exp(-dt * (want and 5 or 4)))
		K.ringA = K.ringA + ((want and 1 or 0) - K.ringA) * (1 - math.exp(-dt * (want and 9 or 3.2)))

		if K.ringA < 0.01 and not want then
			if root.Visible then root.Visible = false end
			K.ringP = 0
			return
		end

		root.Visible = true

		local r = K.ringP * 360
		gR.Rotation = math.min(r, 180)
		gL.Rotation = math.max(r, 180)

		local tr = 1 - K.ringA
		stR.Transparency = tr
		stL.Transparency = tr
		trackStroke.Transparency = 1 - 0.14 * K.ringA
	end
end

local STROKE_FONT = Color3.fromRGB(10, 12, 16)

local speedText = new("TextLabel", {
	Size = UDim2.new(1, -100, 0, 22),
	Position = UDim2.new(0, 50, 0, 6),
	BackgroundTransparency = 1,
	Text = "016",
	TextColor3 = C.light,
	TextSize = 19,
	Font = Enum.Font.GothamBold,
	TextStrokeColor3 = STROKE_FONT,
	TextStrokeTransparency = 0.6,
	ZIndex = 4,
}, main)

local subText = new("TextLabel", {
	Size = UDim2.new(1, -100, 0, 12),
	Position = UDim2.new(0, 50, 0, 27),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = C.dim,
	TextSize = 8,
	Font = Enum.Font.GothamBold,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 4,
}, main)

local barBG = new("Frame", {
	Size = UDim2.new(1, -112, 0, 3),
	Position = UDim2.new(0, 56, 1, -10),
	BackgroundColor3 = Color3.fromRGB(55, 61, 72),
	BorderSizePixel = 0,
	ZIndex = 4,
}, main)
corner(barBG, 2)

local barFill = new("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = C.silver,
	BorderSizePixel = 0,
	ZIndex = 5,
}, barBG)
corner(barFill, 2)

-- большие хитбоксы на каждую половину
local leftBtn = new("TextButton", {
	Name = "LeftHitbox",
	Size = UDim2.new(0.3, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	Selectable = false,
	ZIndex = 20,
}, main)

local rightBtn = new("TextButton", {
	Name = "RightHitbox",
	Size = UDim2.new(0.3, 0, 1, 0),
	Position = UDim2.new(0.7, 0, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	Selectable = false,
	ZIndex = 20,
}, main)

new("TextButton", {
	Name = "CenterHitbox",
	Size = UDim2.new(0.4, 0, 1, 0),
	Position = UDim2.new(0.3, 0, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	Selectable = false,
	ZIndex = 20,
}, main)

-- шторка меню
local drawer = new("CanvasGroup", {
	Name = "Drawer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, H + 4),
	Size = UDim2.fromOffset(6, 0),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	ZIndex = 3,
	Visible = false,
	Active = true,
	GroupTransparency = 1,
}, holder)

corner(drawer, 16)

-- Живой мягкий фон меню: медленно движущийся градиент под элементами интерфейса.
local menuAura = new("Frame", {
	Name = "MenuAura",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.18,
	BorderSizePixel = 0,
	ZIndex = 1,
}, drawer)
corner(menuAura, 16)
local auraGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 35, 49)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 22, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 25, 48)),
	}),
	Rotation = 25,
}, menuAura)
task.spawn(function()
	while alive and auraGradient.Parent do
		local tw = tween(auraGradient, 8, { Rotation = auraGradient.Rotation + 110 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		tw.Completed:Wait()
	end
end)

new("UIStroke", {
	Color = C.silver,
	Thickness = 1,
	Transparency = 0.55,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, drawer)

do
	-- мягкий блик сверху шторки
	local sheen = new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = C.white,
		BorderSizePixel = 0,
	}, drawer)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.93),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, sheen)
end

-- тосты (над капсулой)
local toast = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, -6),
	Size = UDim2.fromOffset(W, 18),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = C.light,
	TextTransparency = 1,
	TextSize = 9,
	Font = Enum.Font.GothamBold,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 30,
}, holder)
corner(toast, 9)

local toastToken = 0
showToast = function(text, dur)
	toastToken = toastToken + 1
	local my = toastToken
	toast.Text = text
	toast.BackgroundTransparency = 0.15
	toast.TextTransparency = 0
	task.delay(dur or 1.6, function()
		if alive and my == toastToken then
			tween(toast, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
		end
	end)
end

--==========================================================================
-- LABELS / VISUAL STATE
--==========================================================================
local function orbColors()
	local l, r = C.off, C.off
	if isLocked then
		l = isFlash and C.white or C.silver
		r = stoppedtime and C.accent or C.silver
	end
	return l, r
end

refreshLabels = function()
	local mus = (K.musicLeft and (bgMusic or stoppedtime)) and ("  " .. K.fmtTime(K.musicLeft)) or ""

	if not isLocked then
		if bgMusic and K.musicLeft then
			subText.Text = "MUSIC" .. mus
		else
			subText.Text = "HOLD ⚡ TO ARM"
		end
	elseif stoppedtime then
		if stopEndsAt then
			subText.Text = "STOP " .. math.max(0, math.ceil(stopEndsAt - os.clock())) .. "S"
		else
			subText.Text = (K.slow and "SLOW-MO" or "STOPPED") .. mus
		end
	elseif isFlash then
		if bgMusic and mus ~= "" then
			subText.Text = "FLASH" .. mus
		else
			subText.Text = Settings.aimLock and "FLASH + AIM" or "FLASH"
		end
	else
		if bgMusic and mus ~= "" then
			subText.Text = "READY" .. mus
		else
			subText.Text = Settings.aimLock and "READY + AIM" or "READY"
		end
	end

	subText.TextColor3 = (isLocked and (isFlash or stoppedtime)) and C.accent or C.dim
	speedText.TextColor3 = stoppedtime and C.accent or C.light
end

local function strokeState()
	local col = C.silver
	if isLocked then
		if stoppedtime then col = C.accent
		elseif isFlash then col = C.accent:Lerp(C.white, 0.45)
		else col = C.white end
	end
	tween(stroke, 0.25, { Color = col })
end

local function paintOrbs()
	local l, r = orbColors()
	tween(leftOrb, 0.25, { BackgroundColor3 = l })
	tween(rightOrb, 0.25, { BackgroundColor3 = r })
	for _, s in ipairs({ leftOrbStroke, rightOrbStroke }) do
		tween(s, 0.2, { Thickness = 1.2, Transparency = 0.6 })
	end
end

applyLockVisual = function()
	paintOrbs()
	strokeState()
	refreshLabels()
end

local function ripple(pos)
	local w = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = C.white,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, main)

	corner(w, 100)
	tween(w, 0.55, { Size = UDim2.fromOffset(120, 120), BackgroundTransparency = 1 })
	Debris:AddItem(w, 0.6)
end

local function pressFeedback(half)
	if half == "center" then
		ripple(UDim2.fromScale(0.5, 0.5))
		return
	end
	local sc = half == "left" and leftOrbScale or rightOrbScale
	local pos = half == "left" and UDim2.new(0, 27, 0.5, 0) or UDim2.new(1, -27, 0.5, 0)

	tween(sc, 0.07, { Scale = 0.86 })
	ripple(pos)

	task.delay(0.1, function()
		if alive then tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back) end
	end)
end

local function lockAnimation()
	ripple(UDim2.fromScale(0.5, 0.5))
	tween(stroke, 0.15, { Transparency = 0.05, Thickness = 2.6 })
	task.delay(0.2, function()
		tween(stroke, 0.4, { Transparency = 0.5, Thickness = 1.5 })
	end)
end

-- короткая вспышка капсулы при успешном увороте
K.dodgePulse = function()
	tween(stroke, 0.08, { Transparency = 0, Thickness = 3 })
	task.delay(0.1, function()
		if alive then tween(stroke, 0.35, { Transparency = 0.5, Thickness = 1.5 }) end
	end)
end

--==========================================================================
-- MENU ROWS
--==========================================================================
do
	local PAGE_W = K.DW - 12
	local DARK = Color3.fromRGB(18, 22, 28)
	local rowOrder = 0
	local pages, tabBtns = {}, {}
	local scroll
	local grids = {}
	local hasReq = (request or http_request or (syn and syn.request) or (http and http.request)) ~= nil

	local tabBar = new("Frame", {
		Position = UDim2.fromOffset(6, 7),
		Size = UDim2.fromOffset(PAGE_W, 22),
		BackgroundTransparency = 1,
	}, drawer)

	local divider = new("Frame", {
		Position = UDim2.fromOffset(10, 33),
		Size = UDim2.fromOffset(K.DW - 20, 1),
		BackgroundColor3 = C.silver,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
	}, drawer)

	local pageHolder = new("Frame", {
		Position = UDim2.fromOffset(6, 38),
		Size = UDim2.fromOffset(PAGE_W, K.MENU_H - 44),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, drawer)

	local TAB_DEFS = {
		{ "music", "MUSIC" }, { "time", "TIME" }, { "flash", "FLASH" },
		{ "fight", "FIGHT" }, { "cape", "CAPE" }, { "more", "MORE" },
	}

	local function selectTab(key)
		for k, p in pairs(pages) do p.Visible = (k == key) end
		for k, b in pairs(tabBtns) do
			local on = (k == key)
			tween(b, 0.18, {
				BackgroundColor3 = on and C.on or C.row,
				TextColor3 = on and DARK or C.dim,
			})
		end
		pages[key].CanvasPosition = Vector2.new(0, 0)
	end

	for i, d in ipairs(TAB_DEFS) do
		local page = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = C.silver,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, pageHolder)

		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		new("UIPadding", { PaddingBottom = UDim.new(0, 4) }, page)
		pages[d[1]] = page

		local b = new("TextButton", {
			Position = UDim2.new((i - 1) / 6, 0, 0, 0),
			Size = UDim2.new(1 / 6, -3, 1, 0),
			BackgroundColor3 = C.row,
			Text = d[2],
			TextColor3 = C.dim,
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			AutoButtonColor = false,
			Active = true,
		}, tabBar)
		corner(b, 7)
		tabBtns[d[1]] = b
		b.Activated:Connect(function() selectTab(d[1]) end)
	end

	-- ---------- строительные блоки ----------
	local function newRow(h)
		rowOrder = rowOrder + 1
		local r = new("Frame", {
			Size = UDim2.new(1, -5, 0, h or 24),
			BackgroundColor3 = C.row,
			BorderSizePixel = 0,
			LayoutOrder = rowOrder,
		}, scroll)
		corner(r, 8)
		return r
	end

	local function rowLabel(r, text, w)
		return new("TextLabel", {
			Size = UDim2.new(1, -(w or 80), 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = C.silver,
			TextSize = 9,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, r)
	end

	local function addInfo(getText)
		local r = newRow(18)
		r.BackgroundTransparency = 1
		local l = new("TextLabel", {
			Size = UDim2.new(1, -8, 1, 0),
			Position = UDim2.new(0, 4, 0, 0),
			BackgroundTransparency = 1,
			Text = getText(),
			TextColor3 = C.dim,
			TextSize = 8,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, r)
		refreshers[#refreshers + 1] = function() l.Text = getText() end
	end

	-- сетка кнопок: toggle (key) или обычная кнопка (cb)
	local function addGrid(cols, items, dense)
		rowOrder = rowOrder + 1
		local g = new("Frame", {
			Size = UDim2.new(1, -5, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = rowOrder,
		}, scroll)

		local gl = new("UIGridLayout", {
			CellSize = UDim2.new(1 / cols, -(4 * (cols - 1)) / cols, 0, 24),
			CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
		}, g)
		grids[#grids + 1] = { layout = gl, cols = cols, dense = dense }

		local btns = {}

		for idx, it in ipairs(items) do
			local b = new("TextButton", {
				LayoutOrder = idx,
				BackgroundColor3 = C.row,
				Text = it.text,
				TextColor3 = it.color or C.silver,
				TextSize = 9,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = false,
				Active = true,
			}, g)
			corner(b, 8)

			local function paint(instant)
				if not it.key then return end
				local on = Settings[it.key]
				local props = {
					BackgroundColor3 = on and C.on or C.row,
					TextColor3 = on and DARK or C.dim,
				}
				if instant then
					for k, v in pairs(props) do b[k] = v end
				else
					tween(b, 0.15, props)
				end
			end

			paint(true)
			if it.key then
				refreshers[#refreshers + 1] = function() paint(true) end
			end

			b.Activated:Connect(function()
				if it.key then
					Settings[it.key] = not Settings[it.key]
					paint(false)
					saveSettings()
					if it.onChange then it.onChange(Settings[it.key]) end
					refreshLabels()
				else
					tween(b, 0.08, { BackgroundColor3 = C.rowHi })
					task.delay(0.1, function()
						if b.Parent then tween(b, 0.2, { BackgroundColor3 = C.row }) end
					end)
					it.cb(b)
				end
			end)

			btns[idx] = b
		end

		return btns
	end

	local function addStepper(text, getText, step)
		local r = newRow(24)
		rowLabel(r, text, 92)

		local function small(txt, x)
			local b = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, x, 0.5, 0),
				Size = UDim2.fromOffset(20, 17),
				BackgroundColor3 = C.btn,
				Text = txt,
				TextColor3 = C.light,
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = false,
				Active = true,
			}, r)
			corner(b, 5)
			return b
		end

		local minus, plus = small("-", -64), small("+", -5)

		local val = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -26, 0.5, 0),
			Size = UDim2.fromOffset(36, 17),
			BackgroundTransparency = 1,
			Text = getText(),
			TextColor3 = C.accent,
			TextSize = 9,
			Font = Enum.Font.GothamBold,
		}, r)

		local function paint() val.Text = getText() end
		refreshers[#refreshers + 1] = paint

		minus.Activated:Connect(function() step(-1) paint() saveSettings() end)
		plus.Activated:Connect(function() step(1) paint() saveSettings() end)
	end

	local function addTextBox(text, get, set, placeholder)
		local r = newRow(24)
		rowLabel(r, text, 128)

		local box = new("TextBox", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(118, 17),
			BackgroundColor3 = C.btn,
			Text = get(),
			PlaceholderText = placeholder or "",
			PlaceholderColor3 = C.dim,
			TextColor3 = C.accent,
			TextSize = 9,
			Font = Enum.Font.GothamBold,
			ClearTextOnFocus = false,
		}, r)
		corner(box, 5)

		refreshers[#refreshers + 1] = function() box.Text = get() end

		box.FocusLost:Connect(function()
			set(box.Text)
			box.Text = get()
			saveSettings()
		end)
	end

	local function addTrackSelector()
		local r = newRow(26)

		local function arrow(txt, pos)
			local b = new("TextButton", {
				Position = pos,
				Size = UDim2.fromOffset(26, 20),
				BackgroundColor3 = C.btn,
				Text = txt,
				TextColor3 = C.light,
				TextSize = 12,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = false,
				Active = true,
			}, r)
			corner(b, 6)
			return b
		end

		local prev = arrow("<", UDim2.new(0, 4, 0.5, -10))
		local nxt = arrow(">", UDim2.new(1, -30, 0.5, -10))

		local name = new("TextLabel", {
			Size = UDim2.new(1, -68, 1, 0),
			Position = UDim2.new(0, 34, 0, 0),
			BackgroundTransparency = 1,
			Text = Settings.track,
			TextColor3 = C.light,
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, r)

		refreshers[#refreshers + 1] = function() name.Text = Settings.track end

		local function step(d)
			local names = trackNames()
			local idx = 1
			for i, n in ipairs(names) do
				if n == Settings.track then idx = i end
			end
			idx = ((idx - 1 + d) % #names) + 1
			Settings.track = names[idx]
			name.Text = Settings.track
			saveSettings()
			reloadMusic()
		end

		prev.Activated:Connect(function() step(-1) end)
		nxt.Activated:Connect(function() step(1) end)
	end

	local DURATIONS = { 0, 5, 10, 15, 30, 60 }

	local function durationText()
		return Settings.stopDuration > 0 and (Settings.stopDuration .. "s") or "OFF"
	end

	local function targetText()
		return targetPlayer and ("Target: " .. targetPlayer.DisplayName) or "No target selected"
	end

	-- ================= MUSIC =================
	scroll = pages.music
	addTrackSelector()

	local musicBtns = addGrid(2, {
		{ text = "Play on stop", key = "musicOn" },
		{ text = "Play music", cb = function()
			K.toggleMusic()
			refreshAll()
		end },
		{ text = "Loop", key = "musicLoop", onChange = function(on) music.Looped = on end },
		{ text = "Remove track", color = C.danger, cb = function()
			if K.removeTrack() then
				showToast("Track removed")
			else
				showToast("Only your own tracks can be removed", 2)
			end
			refreshAll()
		end },
	})
	refreshers[#refreshers + 1] = function()
		local audible = music.IsPlaying and music.Volume > 0.02
		musicBtns[2].Text = audible and "Stop music" or "Play music"
		musicBtns[2].BackgroundColor3 = audible and C.on or C.row
		musicBtns[2].TextColor3 = audible and DARK or C.silver
	end
	refreshers[#refreshers]()

	addTextBox("Add track", function() return "" end, function(txt)
		local clean = tostring(txt):gsub("%s", "")
		if clean == "" then return end
		local ok, msg = K.addTrack(txt)
		showToast(ok and ("Added: " .. tostring(msg)) or ("Failed: " .. tostring(msg or "?")), 2.2)
		refreshAll()
	end, "link / sound ID")

	addStepper("Volume", function()
		return string.format("%.1f", Settings.volume)
	end, function(d)
		Settings.volume = math.clamp(Settings.volume + d * 0.5, 0, 10)
		if music.IsPlaying and (stoppedtime or bgMusic) then
			music.Volume = Settings.volume
		end
	end)

	addInfo(function()
		if music.IsPlaying and music.Volume > 0.02 then
			return "Now playing: " .. tostring(Settings.track)
		end
		return "Music is off"
	end)

	addInfo(function() return "Own files: workspace/Quicksilver/music" end)

	-- ================= TIME =================
	scroll = pages.time

	local modeBtn = addGrid(1, {
		{ text = "Mode", cb = function()
			Settings.timeMode = (Settings.timeMode == "slow") and "stop" or "slow"
			saveSettings()
			refreshAll()
		end },
	})[1]
	refreshers[#refreshers + 1] = function()
		modeBtn.Text = "Mode: " .. ((Settings.timeMode == "slow") and "Slow-mo" or "Time stop") .. "   >"
	end
	refreshers[#refreshers]()

	local SLOW_STEPS = { 0.2, 0.25, 1/3, 0.5, 1.0, 2.0 }
	addStepper("Slow speed", function()
		local v = Settings.slowFactor or 0.2
		local labels = { "5", "4", "3", "2", "1", "0.5" }
		local best, dist = "5x", math.huge
		for i, x in ipairs(SLOW_STEPS) do
			local d = math.abs(v-x)
			if d < dist then dist, best = d, labels[i] .. "x" end
		end
		return best
	end, function(d)
		local idx = 1
		for i, x in ipairs(SLOW_STEPS) do if math.abs((Settings.slowFactor or 0.2)-x) < 0.015 then idx=i end end
		idx = math.clamp(idx + d, 1, #SLOW_STEPS)
		Settings.slowFactor = SLOW_STEPS[idx]
	end)

	addStepper("Auto resume", durationText, function(d)
		local idx = 1
		for i, v in ipairs(DURATIONS) do
			if v == Settings.stopDuration then idx = i end
		end
		idx = math.clamp(idx + d, 1, #DURATIONS)
		Settings.stopDuration = DURATIONS[idx]
	end)

	addGrid(3, {
		{ text = "Invisible", key = "invisOnStop", onChange = function(on)
			if stoppedtime then isInvisible = on and not K.slow end
		end },
		{ text = "Freeze net", key = "freezeReplication", onChange = function(on)
			if stoppedtime then setReplicationLag(on or K.slow) end
		end },
		{ text = "Shake", key = "shake" },
	})

	-- ================= FLASH =================
	scroll = pages.flash

	addStepper("Max speed", function()
		return tostring(Settings.maxSpeed)
	end, function(d)
		Settings.maxSpeed = math.clamp(Settings.maxSpeed + d * 50, 100, 600)
	end)

	addGrid(2, {
		{ text = "Sonic boom", key = "boom" },
		{ text = "Boom sound", key = "boomSound" },
		{ text = "Instant speed", key = "instantSpeed" },
		{ text = "Dynamic FOV", key = "dynamicFov" },
		{ text = "Body trails", key = "trails", onChange = function(on)
			if not on then setTrailsActive(false) end
		end },
		{ text = "Afterimages", key = "afterimages" },
		{ text = "Lightning", key = "arcs" },
		{ text = "Foot dust", key = "dust" },
	}, 3)

	-- ================= FIGHT =================
	scroll = pages.fight

	addInfo(targetText)

	addGrid(2, {
		{ text = "Aim lock", key = "aimLock", onChange = function(on)
			if not on then clearAimHL() end
		end },
		{ text = "Ultra dodge", key = "autoDodge" },
	})

	addGrid(3, {
		{ text = "Players", key = "dodgePlayers" },
		{ text = "Projectiles", key = "dodgeProj" },
		{ text = "Radar", key = "dodgeRadar" },
	})

	addStepper("Dodge radius", function()
		return tostring(Settings.dodgeRadius)
	end, function(d)
		Settings.dodgeRadius = math.clamp(Settings.dodgeRadius + d * 2, 4, 40)
	end)

	addStepper("Blink distance", function()
		return tostring(Settings.dodgeDist)
	end, function(d)
		Settings.dodgeDist = math.clamp(Settings.dodgeDist + d, 2, 12)
	end)

	addGrid(3, {
		{ text = "Pick", cb = function()
			isSelectingTarget = true
			closeMenu()
			showToast("TAP A PLAYER TO TARGET", 4)
			task.delay(8, function() isSelectingTarget = false end)
		end },
		{ text = "Nearest", cb = function()
			local _, c = nearestOther(150)
			local plr = c and Players:GetPlayerFromCharacter(c)
			if plr then setTarget(plr) else showToast("No players nearby") end
			refreshAll()
		end },
		{ text = "Clear", cb = function()
			clearTarget()
			showToast("Target cleared")
			refreshAll()
		end },
	})

	-- ================= CAPE =================
	scroll = pages.cape

	local capeBtns = addGrid(2, {
		{ text = "Show cape", cb = function()
			Cape.set(not Cape.isOn())
			refreshAll()
		end },
		{ text = "Mode", cb = function()
			Settings.capeMode = (Settings.capeMode == "image") and "gradient" or "image"
			saveSettings()
			Cape.applyImage()
			refreshAll()
		end },
	})

	local capeAnimBtn = addGrid(1, {
		{ text = "Animation", cb = function()
			local choices = { "Cascade", "Sweep", "Materialize" }
			local at = 1
			for i, v in ipairs(choices) do if v == Settings.capeAnim then at = i end end
			Settings.capeAnim = choices[at % #choices + 1]
			saveSettings()
			refreshAll()
		end },
	})[1]
	refreshers[#refreshers + 1] = function()
		capeAnimBtn.Text = "Animation: " .. tostring(Settings.capeAnim or "Cascade") .. "  >"
	end

	addStepper("Parts (3-8)", function()
		return tostring(Settings.capeParts)
	end, function(d)
		Settings.capeParts = math.clamp(Settings.capeParts + d, 3, 8)
		Cape.rebuild()
	end)

	local presetBtn = addGrid(1, {
		{ text = "Preset", cb = function()
			local idx = (Settings.capePreset % #Cape.presets) + 1
			Settings.capePreset = idx
			Settings.capeTop, Settings.capeBottom = Cape.presets[idx][2], Cape.presets[idx][3]
			Settings.capeMode = "gradient"
			saveSettings()
			Cape.applyImage()
			refreshAll()
		end },
	})[1]

	refreshers[#refreshers + 1] = function()
		capeBtns[1].Text = Cape.isOn() and "Hide cape" or "Show cape"
		capeBtns[2].Text = "Mode: " .. ((Settings.capeMode == "image") and "Image" or "Gradient")
		local pr = Cape.presets[Settings.capePreset]
		presetBtn.Text = "Preset: " .. (pr and pr[1] or "Custom") .. "   >"
	end
	refreshers[#refreshers]()

	addTextBox("Top color", function() return Settings.capeTop end, function(txt)
		local h = tostring(txt):gsub("[#%s]", "")
		if Cape.hex(h) then
			Settings.capeTop = h:upper()
			Settings.capePreset = 0
			Cape.repaint()
		else
			showToast("Bad hex, e.g. BEE1FF", 2)
		end
	end, "BEE1FF")

	addTextBox("Bottom color", function() return Settings.capeBottom end, function(txt)
		local h = tostring(txt):gsub("[#%s]", "")
		if Cape.hex(h) then
			Settings.capeBottom = h:upper()
			Settings.capePreset = 0
			Cape.repaint()
		else
			showToast("Bad hex, e.g. 1B3A66", 2)
		end
	end, "1B3A66")

	addTextBox("Image / link", function() return Settings.capeImage end, function(txt)
		local v = tostring(txt):gsub("%s", "")
		Settings.capeImage = v
		Settings.capeMode = (v ~= "") and "image" or "gradient"
		Cape.applyImage()
		refreshAll()
	end, "ID or Discord CDN")

	addInfo(function()
		if not isLocked then return "Arm first (hold ⚡) to use the cape" end
		local st = Cape.status()
		return st ~= "" and st or "Tap the center of the bar to toggle"
	end)

	-- ================= MORE =================
	scroll = pages.more

	local themeBtn = addGrid(1, {
		{ text = "Theme", cb = function()
			K.Theme.next()
			refreshAll()
		end },
	})[1]
	refreshers[#refreshers + 1] = function()
		themeBtn.Text = "Theme: " .. tostring(Settings.theme) .. "   >"
	end
	refreshers[#refreshers]()

	addInfo(function()
		return K.Theme.info and K.Theme.info() or ""
	end)

	local layoutNames = { "Classic", "Battle", "Mystic", "Royal", "Frost", "Matrix" }
	local layoutBtn = addGrid(1, {
		{ text = "Button layout", cb = function()
			local idx = 1
			for i, v in ipairs(layoutNames) do if v == (Settings.menuLayout or "Classic") then idx = i end end
			Settings.menuLayout = layoutNames[idx % #layoutNames + 1]
			if K.Menu.applyLayout then K.Menu.applyLayout(Settings.menuLayout) end
			saveSettings(); refreshAll()
		end },
	})[1]
	refreshers[#refreshers + 1] = function() layoutBtn.Text = "Button layout: " .. (Settings.menuLayout or "Classic") .. "  >" end

	local langBtn = addGrid(1, {
		{ text = "Language", cb = function()
			Settings.language = (Settings.language == "Русский") and "English" or "Русский"
			saveSettings(); refreshAll()
			if K.Language and K.Language.apply then K.Language.apply() end
		end },
	})[1]
	refreshers[#refreshers + 1] = function() langBtn.Text = "Language: " .. (Settings.language or "English") .. "  >" end

	local profileSaveBtn, profileLoadBtn = addGrid(2, {
		{ text = "Save profile", cb = function()
			Settings.profiles = Settings.profiles or {}
			local snap = {}
			for key in pairs(DEFAULTS) do
				if key ~= "profiles" and key ~= "customTracks" then
					local value = Settings[key]
					if type(value) ~= "table" then snap[key] = value end
				end
			end
			Settings.profiles[Settings.profileSlot or 1] = snap
			saveSettings(); showToast("Profile " .. tostring(Settings.profileSlot or 1) .. " saved")
		end },
		{ text = "Load profile", cb = function()
			local snap = Settings.profiles and Settings.profiles[Settings.profileSlot or 1]
			if type(snap) ~= "table" then showToast("Profile is empty"); return end
			for key, value in pairs(snap) do if DEFAULTS[key] ~= nil and key ~= "profiles" and key ~= "customTracks" then Settings[key] = value end end
			saveSettings()
			if K.Theme.apply then K.Theme.apply(Settings.theme, true) end
			if K.Menu.applyLayout then K.Menu.applyLayout(Settings.menuLayout or "Classic") end
			Cape.rebuild(); Cape.applyImage(); refreshAll(); refreshLabels()
			showToast("Profile " .. tostring(Settings.profileSlot or 1) .. " loaded")
		end },
	})
	local profileSlotBtn = addGrid(1, {
		{ text = "Profile slot", cb = function()
			Settings.profileSlot = (Settings.profileSlot or 1) % 3 + 1
			saveSettings(); refreshAll()
		end },
	})[1]
	refreshers[#refreshers + 1] = function() profileSlotBtn.Text = "Profile slot: " .. tostring(Settings.profileSlot or 1) .. "  >" end

	addGrid(2, {
		{ text = "Reset settings", cb = function()
			for k, v in pairs(DEFAULTS) do
				if k ~= "customTracks" then Settings[k] = v end
			end
			saveSettings()
			clearAimHL()
			music.Looped = Settings.musicLoop
			reloadMusic()
			Cape.rebuild()
			Cape.applyImage()
			if K.Theme.apply then K.Theme.apply(Settings.theme, true) end
			if K.Menu.applyLayout then K.Menu.applyLayout(Settings.menuLayout or "Classic") end
			refreshAll()
			refreshLabels()
			showToast("Settings reset")
		end },
		{ text = "Unload", color = C.danger, cb = function() unload() end },
	})

	addGrid(1, {
		{ text = "Close menu", cb = function() closeMenu() end },
	})

	local function yn(v) return v and "ok" or "no" end
	addInfo(function()
		return string.format("Files %s | Assets %s | HTTP %s", yn(hasFS), yn(hasGCA), yn(hasReq))
	end)


	K.Menu.select = selectTab

	K.Language = {}
	local EN_RU = {
		["MUSIC"]="МУЗЫКА", ["TIME"]="ВРЕМЯ", ["FLASH"]="ФЛЭШ", ["FIGHT"]="БОЙ", ["CAPE"]="ПЛАЩ", ["MORE"]="ЕЩЁ",
		["Theme"]="Тема", ["Button layout"]="Расположение кнопок", ["Language"]="Язык",
		["Save profile"]="Сохранить профиль", ["Load profile"]="Загрузить профиль", ["Profile slot"]="Слот профиля",
		["Reset settings"]="Сбросить настройки", ["Unload"]="Выгрузить", ["Close menu"]="Закрыть меню",
		["Show cape"]="Показать плащ", ["Hide cape"]="Скрыть плащ", ["Mode"]="Режим",
		["Parts (3-8)"]="Сегменты (3–8)", ["Preset"]="Пресет", ["Top color"]="Верхний цвет",
		["Bottom color"]="Нижний цвет", ["Image / link"]="Изображение / ссылка",
		["Animation"]="Анимация", ["Slow speed"]="Скорость времени", ["Auto resume"]="Автовозврат",
		["Invisible"]="Невидимость", ["Freeze net"]="Заморозка сети", ["Shake"]="Тряска",
		["Max speed"]="Макс. скорость", ["Sonic boom"]="Звуковой удар", ["Boom sound"]="Звук удара",
		["Instant speed"]="Мгновенная скорость", ["Dynamic FOV"]="Динамический FOV",
		["Body trails"]="Следы тела", ["Afterimages"]="Послесвечения", ["Lightning"]="Молнии",
		["Foot dust"]="Пыль из-под ног", ["Aim lock"]="Захват цели", ["Ultra dodge"]="Ультра-уклонение",
		["Players"]="Игроки", ["Projectiles"]="Снаряды", ["Radar"]="Радар",
		["Dodge radius"]="Радиус уклонения", ["Blink distance"]="Дистанция скачка",
		["Pick"]="Выбрать", ["Nearest"]="Ближайший", ["Clear"]="Очистить",
		["Play on stop"]="Музыка при стопе", ["Play music"]="Играть музыку", ["Stop music"]="Остановить музыку",
		["Loop"]="Повтор", ["Remove track"]="Удалить трек", ["Volume"]="Громкость",
		["Add track"]="Добавить трек", ["Time stop"]="Остановка времени", ["Slow-mo"]="Замедление",
		["Track"]="Трек", ["No target selected"]="Цель не выбрана", ["Music is off"]="Музыка выключена",
		["Classic"]="Классика", ["Battle"]="Битва", ["Mystic"]="Мистика", ["Royal"]="Королевский",
		["Frost"]="Мороз", ["Matrix"]="Матрица", ["Cascade"]="Каскад", ["Sweep"]="Волна", ["Materialize"]="Материализация",
	}
	local function replaceWords(value, dict)
		local keys = {}
		for k in pairs(dict) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return #a > #b end)
		for _, k in ipairs(keys) do
			local escaped = k:gsub("([^%w])", "%%%1")
			value = value:gsub(escaped, dict[k])
		end
		return value
	end
	EN_RU["Theme"] = "Тема"
	EN_RU["Button layout"] = "Расположение кнопок"
	EN_RU["Language"] = "Язык"
	EN_RU["Animation"] = "Анимация"
	EN_RU["Profile slot"] = "Слот профиля"
	EN_RU["Layout"] = "Раскладка"
	EN_RU["Color theme only · button layout is separate"] = "Тема меняет только цвет · раскладка отдельно"
	EN_RU["tabs"] = "вкладки"
	EN_RU["top"] = "сверху"
	EN_RU["bottom"] = "снизу"
	EN_RU["Gradient"] = "Градиент"
	EN_RU["Image"] = "Изображение"
	local RU_EN = {}
	for en, ru in pairs(EN_RU) do RU_EN[ru] = en end
	K.Language.apply = function()
		local ru = Settings.language == "Русский"
		for _, obj in ipairs(gui:GetDescendants()) do
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				local value = obj.Text
				obj.Text = replaceWords(value, ru and EN_RU or RU_EN)
			end
		end
	end

	K.Menu.layout = function(th)
		local bottom = (th.tabsAt == "bottom")

		for idx, key in ipairs(th.order) do
			tween(tabBtns[key], 0.28, { Position = UDim2.new((idx - 1) / 6, 0, 0, 0) }, Enum.EasingStyle.Quint)
		end

		local tbPos = bottom and UDim2.fromOffset(6, K.MENU_H - 29) or UDim2.fromOffset(6, 7)
		local dvPos = bottom and UDim2.fromOffset(10, K.MENU_H - 34) or UDim2.fromOffset(10, 33)
		local phPos = bottom and UDim2.fromOffset(6, 6) or UDim2.fromOffset(6, 38)

		tween(tabBar, 0.28, { Position = tbPos }, Enum.EasingStyle.Quint)
		tween(divider, 0.28, { Position = dvPos }, Enum.EasingStyle.Quint)
		tween(pageHolder, 0.28, { Position = phPos }, Enum.EasingStyle.Quint)

		for _, g in ipairs(grids) do
			local c = (th.dense and g.dense) or g.cols
			g.layout.CellSize = UDim2.new(1 / c, -(4 * (c - 1)) / c, 0, 24)
		end
	end

	local LAYOUTS = {
		Classic = { tabsAt="top", dense=false, order={"music","time","flash","fight","cape","more"} },
		Battle = { tabsAt="bottom", dense=false, order={"fight","flash","time","cape","music","more"} },
		Mystic = { tabsAt="top", dense=true, order={"cape","time","flash","fight","music","more"} },
		Royal = { tabsAt="bottom", dense=true, order={"music","time","flash","fight","cape","more"} },
		Frost = { tabsAt="top", dense=false, order={"time","flash","music","fight","cape","more"} },
		Matrix = { tabsAt="bottom", dense=true, order={"flash","time","fight","cape","music","more"} },
	}
	K.Menu.applyLayout = function(name) K.Menu.layout(LAYOUTS[name] or LAYOUTS.Classic) end

	selectTab("music")
	if Settings.language == "Русский" and K.Language.apply then K.Language.apply() end
end

-- ================= ТЕМЫ (цвета GUI + раскладка меню) =================
do
	local rgb = Color3.fromRGB
	local ROLES = { "bg", "row", "rowHi", "btn", "off", "accent", "silver", "dim", "capTop", "capBot", "bar" }

	local THEMES = {
		{
			name = "Silver", layoutName = "Classic", tabsAt = "top", dense = false, start = "music",
			order = { "music", "time", "flash", "fight", "cape", "more" },
			fx = rgb(245, 247, 250), trail = rgb(210, 216, 224),
			pal = {
				bg = rgb(13, 15, 19), row = rgb(30, 34, 41), rowHi = rgb(52, 58, 69), btn = rgb(48, 54, 64),
				off = rgb(70, 76, 88), accent = rgb(190, 225, 255), silver = rgb(210, 216, 224),
				dim = rgb(135, 145, 160), capTop = rgb(30, 34, 42), capBot = rgb(10, 12, 16), bar = rgb(55, 61, 72),
			},
		},
		{
			name = "Crimson", layoutName = "Battle", tabsAt = "bottom", dense = false, start = "fight",
			order = { "fight", "flash", "time", "cape", "music", "more" },
			fx = rgb(255, 210, 214), trail = rgb(255, 112, 120),
			pal = {
				bg = rgb(20, 11, 13), row = rgb(42, 23, 27), rowHi = rgb(70, 38, 45), btn = rgb(64, 34, 41),
				off = rgb(92, 62, 68), accent = rgb(255, 112, 120), silver = rgb(236, 196, 200),
				dim = rgb(176, 128, 134), capTop = rgb(46, 22, 27), capBot = rgb(16, 7, 9), bar = rgb(72, 40, 46),
			},
		},
		{
			name = "Void", layoutName = "Mystic", tabsAt = "top", dense = true, start = "cape",
			order = { "cape", "time", "flash", "fight", "music", "more" },
			fx = rgb(222, 205, 255), trail = rgb(178, 140, 255),
			pal = {
				bg = rgb(14, 11, 24), row = rgb(30, 24, 52), rowHi = rgb(50, 40, 84), btn = rgb(46, 38, 78),
				off = rgb(74, 66, 108), accent = rgb(178, 140, 255), silver = rgb(214, 204, 240),
				dim = rgb(140, 128, 178), capTop = rgb(30, 22, 56), capBot = rgb(9, 6, 18), bar = rgb(52, 44, 86),
			},
		},
		{
			name = "Gold", layoutName = "Royal", tabsAt = "bottom", dense = true, start = "flash",
			order = { "music", "time", "flash", "fight", "cape", "more" },
			fx = rgb(255, 238, 190), trail = rgb(255, 208, 100),
			pal = {
				bg = rgb(20, 16, 9), row = rgb(42, 35, 20), rowHi = rgb(68, 57, 32), btn = rgb(62, 52, 30),
				off = rgb(96, 84, 56), accent = rgb(255, 208, 100), silver = rgb(240, 224, 184),
				dim = rgb(176, 160, 112), capTop = rgb(44, 36, 18), capBot = rgb(14, 11, 5), bar = rgb(74, 62, 34),
			},
		},
		{
			name = "Ice", layoutName = "Frost", tabsAt = "top", dense = false, start = "time",
			order = { "time", "flash", "music", "fight", "cape", "more" },
			fx = rgb(214, 244, 255), trail = rgb(136, 222, 255),
			pal = {
				bg = rgb(10, 16, 22), row = rgb(22, 36, 48), rowHi = rgb(38, 60, 80), btn = rgb(34, 54, 72),
				off = rgb(62, 86, 106), accent = rgb(136, 222, 255), silver = rgb(204, 228, 244),
				dim = rgb(116, 150, 176), capTop = rgb(20, 36, 50), capBot = rgb(7, 12, 17), bar = rgb(40, 62, 82),
			},
		},
		{
			name = "Emerald", layoutName = "Matrix", tabsAt = "bottom", dense = true, start = "flash",
			order = { "flash", "time", "fight", "cape", "music", "more" },
			fx = rgb(205, 255, 230), trail = rgb(110, 255, 180),
			pal = {
				bg = rgb(9, 19, 15), row = rgb(20, 42, 34), rowHi = rgb(34, 68, 55), btn = rgb(30, 62, 50),
				off = rgb(58, 98, 82), accent = rgb(110, 255, 180), silver = rgb(200, 240, 222),
				dim = rgb(110, 166, 140), capTop = rgb(18, 44, 36), capBot = rgb(6, 14, 11), bar = rgb(36, 72, 58),
			},
		},
	}

	local function ckey(c)
		return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
	end

	local function find(name)
		for i, t in ipairs(THEMES) do
			if t.name == name then return t, i end
		end
		return THEMES[1], 1
	end

	local function remap(d, map)
		if d:IsA("GuiObject") then
			local n = map[ckey(d.BackgroundColor3)]
			if n then d.BackgroundColor3 = n end

			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				n = map[ckey(d.TextColor3)]
				if n then d.TextColor3 = n end
				if d:IsA("TextBox") then
					n = map[ckey(d.PlaceholderColor3)]
					if n then d.PlaceholderColor3 = n end
				end
			end

			if d:IsA("ScrollingFrame") then
				n = map[ckey(d.ScrollBarImageColor3)]
				if n then d.ScrollBarImageColor3 = n end
			end
		elseif d:IsA("UIStroke") then
			local n = map[ckey(d.Color)]
			if n then d.Color = n end
		elseif d:IsA("UIGradient") then
			local out, changed = {}, false
			for _, kp in ipairs(d.Color.Keypoints) do
				local n = map[ckey(kp.Value)]
				if n then changed = true end
				out[#out + 1] = ColorSequenceKeypoint.new(kp.Time, n or kp.Value)
			end
			if changed then d.Color = ColorSequence.new(out) end
		end
	end

	K.Theme.apply = function(name, silent)
		local th = find(name)

		-- карта «старый цвет роли → новый цвет роли»
		local map = {}
		for _, r in ipairs(ROLES) do
			map[ckey(C[r])] = th.pal[r]
		end

		for _, r in ipairs(ROLES) do C[r] = th.pal[r] end
		C.on = C.accent

		for _, d in ipairs(gui:GetDescendants()) do
			pcall(remap, d, map)
		end

		-- эффекты
		K.fx = th.fx
		trailColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.white),
			ColorSequenceKeypoint.new(1, th.trail),
		})
		if char and hrp then buildBodyFX() end


		Settings.theme = th.name
		saveSettings()

		local function repaint()
			paintOrbs()
			strokeState()
			refreshLabels()
			refreshAll()
		end

		repaint()
		task.delay(0.3, function()
			if alive then repaint() end
		end)

		if not silent then
			showToast("THEME: " .. th.name, 1.8)
		end
	end

	K.Theme.next = function()
		local _, i = find(Settings.theme)
		K.Theme.apply(THEMES[i % #THEMES + 1].name)
	end

	K.Theme.info = function()
		return "Color theme only · button layout is separate"
	end
end

--==========================================================================
-- MENU OPEN / CLOSE
--==========================================================================
local preShiftPos
local menuToken = 0

local function openMenu()
	if menuOpen then return end

	menuOpen = true
	menuToken = menuToken + 1

	refreshAll()

	preShiftPos = holder.Position

	local vp = gui.AbsoluteSize
	local bottom = holder.AbsolutePosition.Y + (H + 4 + K.MENU_H + 10) * holderScale.Scale
	local onScreen = holder.AbsolutePosition.Y + holder.AbsoluteSize.Y < vp.Y

	if bottom > vp.Y and onScreen then
		local p = holder.Position
		tween(holder, 0.35, {
			Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset - (bottom - vp.Y)),
		}, Enum.EasingStyle.Quint)
	end

	drawer.Visible = true
	drawer.Size = UDim2.fromOffset(6, 0)
	drawer.GroupTransparency = 1

	tween(drawer, 0.5, { Size = UDim2.fromOffset(K.DW, K.MENU_H), GroupTransparency = 0 }, Enum.EasingStyle.Quint)
	tween(stroke, 0.2, { Transparency = 0.15 })
	task.delay(0.25, function() tween(stroke, 0.4, { Transparency = 0.5 }) end)
end

closeMenu = function()
	if not menuOpen then return end

	menuOpen = false
	menuToken = menuToken + 1
	local my = menuToken

	-- музыка, включённая вручную, продолжает играть после закрытия меню

	local tw = tween(drawer, 0.32, {
		Size = UDim2.fromOffset(6, 0),
		GroupTransparency = 1,
	}, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

	tw.Completed:Connect(function()
		if my == menuToken then drawer.Visible = false end
	end)

	if preShiftPos then
		tween(holder, 0.35, { Position = preShiftPos }, Enum.EasingStyle.Quint)
		preShiftPos = nil
	end
end

toggleMenu = function()
	if menuOpen then closeMenu() else openMenu() end
end

--==========================================================================
-- FLASH / LOCK LOGIC
--==========================================================================
local function stopFlashInternal()
	isFlash = false
	currentSpeed = normalSpeed

	if humanoid and not isDodging then
		humanoid.WalkSpeed = stoppedtime and K.TIMESTOP_SPEED or normalSpeed
	end

	setTrailsActive(false)
	if dustEmitter then dustEmitter.Enabled = false end
end

local function toggleFlash()
	if not isLocked or not humanoid then return end

	if isFlash then
		stopFlashInternal()
	else
		isFlash = true
		currentSpeed = K.START_SPEED
		humanoid.WalkSpeed = K.START_SPEED
	end

	paintOrbs()
	strokeState()
	refreshLabels()
end

local function setLocked(v)
	isLocked = v

	if not v then
		clearTarget()
		clearAimHL()
		if Cape.isOn() then Cape.set(false) end
		if isFlash then stopFlashInternal() end
		if humanoid then humanoid.AutoRotate = true end
		rotOverride = false
	end

	applyLockVisual()
	lockAnimation()
	showToast(v and "ARMED" or "DISARMED", 1.2)
	refreshAll()
end

local function toggleTimeStop()
	if not isLocked then return end
	if not stoppedtime and menuOpen then return end

	if stoppedtime then timeresume() else timestop() end

	paintOrbs()
	strokeState()
end

--==========================================================================
-- INPUT (HOLD / TAP / DRAG)
--==========================================================================
local currentHalf, pressInput, pressStart = nil, nil, 0
local dragging, wasDragged = false, false
local dragGrabOffset, dragStartPointer

local function clampPos(x, y)
	local vp = gui.AbsoluteSize
	local size = holder.AbsoluteSize
	return math.clamp(x, K.VISIBLE_MIN - size.X, vp.X - K.VISIBLE_MIN),
		math.clamp(y, K.VISIBLE_MIN - size.Y, vp.Y - K.VISIBLE_MIN)
end

local function beginPress(half, input)
	if currentHalf then return end

	currentHalf = half
	pressInput = input
	pressStart = os.clock()
	wasDragged = false

	if not isLocked and not menuOpen then
		dragging = true
		dragStartPointer = Vector2.new(input.Position.X, input.Position.Y)
		dragGrabOffset = holder.AbsolutePosition
	else
		dragging = false
		dragStartPointer, dragGrabOffset = nil, nil
	end

	pressFeedback(half)
end

local function updateDrag(input)
	if not dragging or not input or not dragGrabOffset then return end

	local pointer = Vector2.new(input.Position.X, input.Position.Y)

	-- Захват фиксируется в момент нажатия: первое движение не теряется,
	-- а исходная позиция GUI не пересчитывается из системных координат экрана.
	local delta = pointer - dragStartPointer

	if not wasDragged and delta.Magnitude >= K.DRAG_THRESHOLD then
		wasDragged = true
	end

	if wasDragged then
		local desired = dragGrabOffset + delta
		local x, y = clampPos(desired.X, desired.Y)
		holder.Position = UDim2.fromOffset(x, y)
	end
end

local function finishPress()
	if not currentHalf then return end

	local half = currentHalf
	local held = os.clock() - pressStart
	local dragged = wasDragged

	currentHalf, pressInput = nil, nil
	dragging = false
	dragGrabOffset, dragStartPointer = nil, nil

	paintOrbs()

	if dragged then
		local vp = gui.AbsoluteSize
		local p = holder.AbsolutePosition
		Settings.pos = { x = p.X / vp.X, y = p.Y / vp.Y }
		saveSettings()
		return
	end

	if half == "left" then
		if held >= K.LOCK_HOLD then
			setLocked(not isLocked)
		elseif isLocked then
			toggleFlash()
		else
			showToast("HOLD ⚡ TO ARM", 1.4)
		end
	elseif half == "center" then
		Cape.set(not Cape.isOn())
	else
		if held >= K.MENU_HOLD then
			toggleMenu()
		elseif isLocked then
			if menuOpen then
				-- сначала закрываем меню, и только потом останавливаем время
				closeMenu()
				task.delay(0.4, function()
					if alive and isLocked and not menuOpen then toggleTimeStop() end
				end)
			else
				toggleTimeStop()
			end
		else
			showToast("HOLD ⚡ TO ARM", 1.4)
		end
	end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

track(leftBtn.InputBegan:Connect(function(i)
	if isPress(i) then beginPress("left", i) end
end))

track(rightBtn.InputBegan:Connect(function(i)
	if isPress(i) then beginPress("right", i) end
end))

track(main.CenterHitbox.InputBegan:Connect(function(i)
	if isPress(i) then beginPress("center", i) end
end))

track(UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		updateDrag(input)
	elseif input.UserInputType == Enum.UserInputType.Touch and input == pressInput then
		updateDrag(input)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if not currentHalf then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or (input.UserInputType == Enum.UserInputType.Touch and input == pressInput) then
		finishPress()
	end
end))

-- выбор цели тапом по игроку
local function selectTargetFromScreen(x, y)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- ScreenPointToRay сам учитывает инсет, поэтому тап попадает точно
	local ray = camera:ScreenPointToRay(x, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, fxFolder }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not result then return end

	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if not model then return end

	local plr = Players:GetPlayerFromCharacter(model)
	if plr and plr ~= player then
		setTarget(plr)
		isSelectingTarget = false
	end
end

track(UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not isSelectingTarget then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		selectTargetFromScreen(input.Position.X, input.Position.Y)
	end
end))

track(Players.PlayerRemoving:Connect(function(plr)
	if plr == targetPlayer then
		clearTarget()
		refreshAll()
	end
end))

--==========================================================================
-- MAIN LOOPS
--==========================================================================
local lastArc, lastGhost, lastDodgeCheck, lastUI, lastTick = 0, 0, 0, 0, 0

track(RunService.Heartbeat:Connect(function(dt)
	if not alive or not humanoid or not hrp or not hrp.Parent then return end

	local now = os.clock()
	local moving = humanoid.MoveDirection.Magnitude > 0.1

	-- разгон Flash
	if isFlash and not isDodging and now - lastTick >= 0.08 then
		lastTick = now

		if moving then
			if Settings.instantSpeed then
				currentSpeed = Settings.maxSpeed
			else
				currentSpeed = math.min(math.max(currentSpeed, K.START_SPEED) + K.ACCEL, Settings.maxSpeed)
			end
		else
			currentSpeed = normalSpeed
		end

		humanoid.WalkSpeed = currentSpeed
	end

	local active = (isFlash or stoppedtime) and moving

	setTrailsActive(((active) or now < K.trailUntil) and Settings.trails)

	if dustEmitter then
		dustEmitter.Enabled = (isFlash and moving and Settings.dust) or false
	end

	if active then
		if Settings.arcs and now - lastArc > 0.11 then
			lastArc = now
			spawnArc()
		end

		if isFlash and not stoppedtime and Settings.afterimages and now - lastGhost > 0.13 then
			lastGhost = now
			createAfterimage()
		end
	end

	-- слоу-мо: покадровое движение «замороженных» объектов
	if K.slow and stoppedtime and K.stepSlow then
		pcall(K.stepSlow, dt)
	end

	-- звуковой удар при выходе на максимум скорости
	if isFlash and Settings.boom then
		local frac = currentSpeed / math.max(Settings.maxSpeed, 1)
		if moving and frac >= 0.98 and K.boomArmed and now - K.lastBoom > 2 then
			K.boomArmed = false
			K.lastBoom = now
			pcall(K.boom)
		elseif (not moving) or frac < 0.6 then
			K.boomArmed = true
		end
	else
		K.boomArmed = true
	end

	updateAim()

	-- Ultra Dodge работает всегда, пока включён ARM (Flash не обязателен)
	if isLocked and Settings.autoDodge and now - lastDodgeCheck > 0.05 then
		lastDodgeCheck = now
		pcall(K.dodgeScan, now)
	end

	if stoppedtime and stopEndsAt and now >= stopEndsAt then
		timeresume()
		paintOrbs()
		strokeState()
	end
end))

-- невидимость во время Time Stop
track(RunService.Heartbeat:Connect(function()
	if alive and isInvisible and hrp and humanoid and hrp.Parent then
		local cf = hrp.CFrame
		local off = humanoid.CameraOffset
		local down = cf * CFrame.new(0, -200000, 0)

		hrp.CFrame = down
		humanoid.CameraOffset = down:ToObjectSpace(CFrame.new(cf.Position)).Position

		RunService.RenderStepped:Wait()

		if hrp and hrp.Parent then hrp.CFrame = cf end
		if humanoid and humanoid.Parent then humanoid.CameraOffset = off end
	end
end))

track(RunService.RenderStepped:Connect(function(dt)
	if not alive then return end

	local now = os.clock()
	local cam = Workspace.CurrentCamera

	pcall(Cape.update, dt)
	pcall(K.ringStep, dt)
	pcall(K.radarStep, dt)

	if cam and not fovLock then
		local target = baseFOV

		if isFlash and Settings.dynamicFov and not stoppedtime then
			local a = math.clamp((currentSpeed - normalSpeed) / math.max(Settings.maxSpeed - normalSpeed, 1), 0, 1)
			target = baseFOV + 28 * a
		end

		cam.FieldOfView = cam.FieldOfView + (target - cam.FieldOfView) * (1 - math.exp(-dt * 7))
	end

	-- прогресс удержания: обводка орба растёт
	if currentHalf and currentHalf ~= "center" and not wasDragged then
		local th = currentHalf == "left" and K.LOCK_HOLD or K.MENU_HOLD
		local p = math.clamp((now - pressStart) / th, 0, 1)
		local st = currentHalf == "left" and leftOrbStroke or rightOrbStroke
		st.Thickness = 1.2 + 2.8 * p
		st.Transparency = 0.6 - 0.6 * p
	end

	if now - lastUI > 0.05 then
		lastUI = now

		if humanoid then
			local spd = math.floor(humanoid.WalkSpeed + 0.5)
			speedText.Text = string.format("%03d", spd)
			barFill.Size = UDim2.new(math.clamp(spd / math.max(Settings.maxSpeed, 1), 0, 1), 0, 1, 0)
			barFill.BackgroundColor3 = (spd >= Settings.maxSpeed) and C.white or C.silver
		end

		if (stoppedtime and (stopEndsAt or K.musicLeft)) or bgMusic then refreshLabels() end
	end
end))

RunService:BindToRenderStep("QS_Shake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeAmt > 0.001 then
		local c = Workspace.CurrentCamera

		if c then
			c.CFrame = c.CFrame
				* CFrame.new((math.random() - 0.5) * shakeAmt, (math.random() - 0.5) * shakeAmt, 0)
				* CFrame.Angles(0, 0, (math.random() - 0.5) * shakeAmt * 0.02)
		end

		shakeAmt = shakeAmt * math.exp(-dt * 3.2)
	end
end)

--==========================================================================
-- CHARACTER / UNLOAD / INIT
--==========================================================================
local function setupCharacter(newChar)
	char = newChar
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")

	normalSpeed = humanoid.WalkSpeed
	currentSpeed = normalSpeed

	isDodging, dodgeArmed, isInvisible, rotOverride = false, true, false, false

	if stoppedtime then timeresume() end

	Cape.destroy()
	buildBodyFX()
	if Cape.isOn() and Cape.build() then Cape.reveal.Value = 1 end

	if isFlash then
		currentSpeed = K.START_SPEED
		humanoid.WalkSpeed = K.START_SPEED
	end
end

unload = function()
	if not alive then return end

	if stoppedtime then pcall(timeresume) end

	alive = false
	pcall(setReplicationLag, false)

	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end

	pcall(function() RunService:UnbindFromRenderStep("QS_Shake") end)

	pcall(clearTarget)
	pcall(clearAimHL)
	pcall(Cape.destroy)
	pcall(destroyBodyFX)

	if humanoid then
		pcall(function()
			humanoid.WalkSpeed = normalSpeed
			humanoid.AutoRotate = true
		end)
	end

	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = baseFOV end

	for _, o in ipairs({ gui, fxFolder, cc, blur, music, K.bcc, K.bblur, K.radarPart }) do
		pcall(function() o:Destroy() end)
	end

	env.__QS_UNLOAD = nil
end

env.__QS_UNLOAD = unload

if player.Character then
	task.spawn(setupCharacter, player.Character)
end

track(player.CharacterAdded:Connect(function(c)
	task.spawn(setupCharacter, c)
end))

task.defer(function()
	RunService.Heartbeat:Wait()
	if not alive then return end

	local vp = gui.AbsoluteSize
	local x, y

	if Settings.pos then
		x, y = Settings.pos.x * vp.X, Settings.pos.y * vp.Y
	else
		x, y = 24, vp.Y * 0.42
	end

	x, y = clampPos(x, y)
	holder.Position = UDim2.fromOffset(x, y)

	tween(holderScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)

	applyLockVisual()

	if Settings.theme ~= "Silver" then K.Theme.apply(Settings.theme, true) end
	if K.Menu.applyLayout then K.Menu.applyLayout(Settings.menuLayout or "Classic") end
	if K.Language and K.Language.apply then K.Language.apply() end
end)

reloadMusic()

print(string.format("[Quicksilver v7] loaded | FS=%s customasset=%s gethui=%s",
	tostring(hasFS), tostring(hasGCA), tostring(type(gethui) == "function")))