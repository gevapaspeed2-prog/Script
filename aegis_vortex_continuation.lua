--[[ ============================================================
	ПРОДОЛЖЕНИЕ A.E.G.I.S.-Vortex
	Вставьте всё ниже В КОНЕЦ вашего скрипта — сразу после строки:
		accel = g * (1 - CONFIG.GlideGravity)
============================================================ ]]
	end
	d.force.Force = Vector3.new(0, mass * accel, 0)

	-- горизонталь: плавное скольжение за стиком/наклоном (после рывка не мешаем)
	if os.clock() > (d.boostUntil or 0) then
		local v = hrp.AssemblyLinearVelocity
		local target = humanoid.MoveDirection * d.baseSpeed * CONFIG.GlideSpeedMult
		local h = Vector3.new(v.X, 0, v.Z):Lerp(target, 0.07)
		hrp.AssemblyLinearVelocity = Vector3.new(h.X, v.Y, h.Z)
	end
end

Modes.Glide = {
	enter = function(d)
		local R = 2.2
		d.baseSpeed = math.max(humanoid.WalkSpeed, 16)
		d.tilt = CFrame.identity
		d.boostUntil = 0
		d.att = d.maid:give(new("Attachment", {}, hrp))
		d.force = d.maid:give(new("VectorForce", {
			Attachment0 = d.att, RelativeTo = Enum.ActuatorRelativeTo.World,
			ApplyAtCenterOfMass = true, Force = Vector3.zero,
		}, hrp))

		d.holder = d.maid:give(fxPart({ Size = Vector3.one * 0.1, Transparency = 1, CFrame = hrp.CFrame }))
		d.disc = d.maid:give(fxPart({
			Shape = Enum.PartType.Cylinder, Material = Enum.Material.ForceField,
			Color = color(), Transparency = 0.35, Size = Vector3.new(0.1, 0.2, 0.2),
		}))
		tween(d.disc, 0.35, { Size = Vector3.new(0.1, R * 2, R * 2) }, Enum.EasingStyle.Back)

		-- переплетённые нити: звёздчатые многоугольники по ободу диска
		local N, rim = 24, {}
		for k = 1, N do
			local a = k / N * math.pi * 2
			rim[k] = new("Attachment", { Position = Vector3.new(math.cos(a) * R, 0, math.sin(a) * R) }, d.holder)
		end
		for k = 1, N do
			beam(rim[k], rim[(k + 4) % N + 1], 0.07, 0.15, d.holder)
			beam(rim[k], rim[(k + 8) % N + 1], 0.05, 0.4, d.holder)
		end

		new("PointLight", { Color = color(), Brightness = 1.5, Range = 10 }, d.holder)
		new("ParticleEmitter", {
			Color = ColorSequence.new(color()), LightEmission = 1, LightInfluence = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 0.9), Rate = 25, Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, -8, 0), SpreadAngle = Vector2.new(180, 180),
		}, d.holder)
		kick(0.3)
	end,

	update = function(d, t, dt)
		glidePhysics(d)
		local feet = hrp.Position - Vector3.new(0, rootToFeet() - 0.25, 0)
		local v = hrp.AssemblyLinearVelocity
		local lv = hrp.CFrame:VectorToObjectSpace(Vector3.new(v.X, 0, v.Z))
		local want = CFrame.Angles(math.clamp(lv.Z * 0.012, -0.4, 0.4), 0, math.clamp(-lv.X * 0.012, -0.4, 0.4))
		d.tilt = d.tilt:Lerp(want, 1 - math.exp(-8 * dt))
		local cf = CFrame.new(feet) * d.tilt
		d.holder.CFrame = cf * CFrame.Angles(0, t * 3, 0)
		d.disc.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	end,

	ribbon = function(_, i, n, t)
		local phase = i / n * math.pi * 2
		local a = t * 4.5 * ((i % 2 == 0) and 1 or -1) + phase
		local u = math.sin(t * 1.2 + phase * 2) * 0.5 + 0.5
		local feet = hrp.Position - Vector3.new(0, rootToFeet() - 0.2, 0)
		local r = 1.9 - 1.0 * u
		return feet + Vector3.new(math.cos(a) * r, u * 1.6, math.sin(a) * r), Vector3.new(0, 0.15, 0)
	end,

	-- тап = энергетический рывок
	action = function(d)
		local mv = humanoid.MoveDirection
		local dir = mv.Magnitude > 0.1 and mv.Unit or hrp.CFrame.LookVector
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 0.01 then return end
		dir = dir.Unit
		hrp.AssemblyLinearVelocity = Vector3.new(dir.X * 70, hrp.AssemblyLinearVelocity.Y, dir.Z * 70)
		d.boostUntil = os.clock() + 0.35
		ringWave(function() return CFrame.lookAt(hrp.Position - dir * 1.5, hrp.Position + dir) end, 3.5, 0.4, color())
		kick(0.35)
	end,
}

---------------------------------------------------------------- клинки
local function limbOf(side)
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local name = (side == "L" and "Left" or "Right") .. (r15 and "LowerArm" or " Arm")
	return char:FindFirstChild(name)
end

-- направление клинка: вперёд по взгляду + продолжение предплечья
local function handDir(side)
	local dir = hrp.CFrame.LookVector * 1.4
	local limb = limbOf(side)
	if limb then
		local v = grip(side) - limb.Position
		if v.Magnitude > 0.01 then dir += v.Unit end
	end
	return dir.Unit
end

Modes.Blades = {
	enter = function(d)
		d.ext, d.flare, d.nextScan = 0, 0, 0
		d.cool = setmetatable({}, { __mode = "k" })
		d.blades = {}
		for _, side in ipairs({ "L", "R" }) do
			local b = { teeth = {} }
			b.core = d.maid:give(fxPart({ Size = Vector3.new(0.12, 0.45, 1), Color = Color3.new(1, 1, 1) }))
			b.glow = d.maid:give(fxPart({ Size = Vector3.new(0.35, 0.9, 1), Color = color(), Transparency = 0.55 }))
			for k = 1, 4 do
				b.teeth[k] = d.maid:give(fxPart({ Size = Vector3.new(0.1, 0.3, 0.3), Color = color() }))
			end
			d.blades[side] = b
		end
		kick(0.3)
	end,

	update = function(d, t, dt)
		d.ext += (1 - d.ext) * math.min(1, dt * 12) -- «выстреливают» из запястий
		d.flare = math.max(0, d.flare - dt * 4)
		local scan = t >= d.nextScan
		if scan then d.nextScan = t + 0.05 end
		for side, b in pairs(d.blades) do
			local base = grip(side)
			local dir = handDir(side)
			local len = math.max(CONFIG.BladeLength * lengthMult() * d.ext, 0.1)
			local mid = base + dir * (len / 2)
			local cf = CFrame.lookAt(mid, mid + dir)
			local w = 1 + d.flare * 1.5
			b.core.Size = Vector3.new(0.12, 0.45, len)
			b.core.CFrame = cf
			b.glow.Size = Vector3.new(0.35 * w, 0.9 * w, len + 0.3)
			b.glow.CFrame = cf
			for k, tooth in ipairs(b.teeth) do -- зазубрины
				local sgn = (k % 2 == 0) and 1 or -1
				tooth.CFrame = cf * CFrame.new(0, sgn * 0.3, len / 2 - len * k / 5) * CFrame.Angles(math.pi / 4, 0, 0)
			end
			if scan and d.ext > 0.6 then
				for _, p in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(0.9, 0.9, len), overlapParams)) do
					local model = getHumanoidModel(p)
					if model then
						if (d.cool[model] or 0) < t - 0.5 then
							d.cool[model] = t
							reportHit(model, "Blade")
							kick(0.3)
						end
					elseif not p.Anchored and p.AssemblyMass < 200 and (d.cool[p] or 0) < t - 0.5 then
						d.cool[p] = t
						p:ApplyImpulse(dir * p.AssemblyMass * 25)
					end
				end
			end
		end
	end,

	ribbon = function(d, i, n, t)
		local side = sideOf(i)
		local base = grip(side)
		local dir = handDir(side)
		local len = CONFIG.BladeLength * lengthMult() * (d.ext or 0)
		local u = (i / n + t * 0.8) % 1
		local a = t * 12 + i * 2
		return base + dir * (len * u) + Vector3.new(math.cos(a), 0, math.sin(a)) * 0.15 * (1 - u),
			Vector3.new(0, 0.15, 0)
	end,

	action = function(d)
		d.flare = 1
		kick(0.35)
		ringWave(function()
			local p = hrp.Position + hrp.CFrame.LookVector * 3
			return CFrame.lookAt(p, p + hrp.CFrame.LookVector)
		end, 3, 0.3, color())
	end,
}

---------------------------------------------------------------- хлысты
Modes.Whips = {
	enter = function(d)
		local N = CONFIG.WhipSegments
		d.N = N
		d.whips = {}
		d.cool = setmetatable({}, { __mode = "k" })
		d.hook = nil
		for _, side in ipairs({ "L", "R" }) do
			local pts, atts = {}, {}
			local p0, fwd = grip(side), hrp.CFrame.LookVector
			for k = 1, N + 1 do
				pts[k] = p0 + fwd * (k - 1) * 0.3
				atts[k] = d.maid:give(new("Attachment", { Position = pts[k] }, terrain))
			end
			for k = 1, N do
				local b = beam(atts[k], atts[k + 1], 0.22 * (1 - (k - 1) / N) + 0.03, 0.05, fxFolder)
				b.Width1 = 0.22 * (1 - k / N) + 0.03
				b.Color = ColorSequence.new(k > N - 3 and Color3.new(1, 1, 1) or color())
				d.maid:give(b)
			end
			d.whips[side] = { pts = pts, atts = atts, crack = 0, aimDir = nil }
		end
		kick(0.3)
	end,

	update = function(d, t, dt)
		local N = d.N
		local segLen = CONFIG.WhipLength * lengthMult() / N
		local fwd = hrp.CFrame.LookVector
		local right = hrp.CFrame.RightVector

		-- рывок к зацепу
		local hook = d.hook
		if hook then
			local to = hook.pos - hrp.Position
			if t > hook.expire or to.Magnitude < 5 then
				d.hook, hook = nil, nil
			else
				hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity:Lerp(to.Unit * 75, 1 - math.exp(-8 * dt))
			end
		end

		for side, w in pairs(d.whips) do
			w.crack = math.max(0, w.crack - dt * 3)
			local pts = w.pts
			pts[1] = grip(side)
			local aimDir = w.aimDir or fwd
			for k = 2, N + 1 do
				local prev = pts[k - 1]
				local dir = pts[k] - prev
				dir = dir.Magnitude > 1e-3 and dir.Unit or fwd
				-- змеиная волна + провис; при щелчке хлыст выпрямляется к цели
				local wave = right * math.sin(t * 7 - k * 0.7 + (side == "L" and 0 or 2)) * 0.22 * (1 - w.crack)
				local sag = Vector3.new(0, -0.12, 0)
				local straight = aimDir * (0.25 + w.crack * 2.5)
				pts[k] = prev + (dir + wave + sag + straight).Unit * segLen
			end
			-- натянутый трос к зацепу
			if hook and side == "R" then
				for k = 1, N + 1 do pts[k] = pts[1]:Lerp(hook.pos, (k - 1) / N) end
			end
			for k = 1, N + 1 do w.atts[k].Position = pts[k] end

			-- удар кончиком во время щелчка
			if w.crack > 0.3 then
				local tip = pts[N + 1]
				for _, p in ipairs(workspace:GetPartBoundsInRadius(tip, 2.5, overlapParams)) do
					local model = getHumanoidModel(p)
					if model and (d.cool[model] or 0) < t - 0.5 then
						d.cool[model] = t
						reportHit(model, "Whip")
						kick(0.3)
					end
				end
			end
		end
	end,

	-- энергия «течёт» по хлыстам
	ribbon = function(d, i, n, t)
		local w = d.whips[sideOf(i)]
		local u = ((t * 0.9 + i / n) % 1) * d.N + 1
		local k0 = math.clamp(math.floor(u), 1, d.N)
		local p = w.pts[k0]:Lerp(w.pts[k0 + 1], u - k0)
		return p, Vector3.new(0, 0.15, 0)
	end,

	-- тап: щелчок хлыстом в точку касания (цепляется за архитектуру, хватает детали)
	action = function(d, pos)
		local res, ray = aim(pos)
		local target = res and res.Position or (ray.Origin + ray.Direction * CONFIG.AimRange)
		local reach = CONFIG.WhipLength * lengthMult()
		for side, w in pairs(d.whips) do
			local dir = target - grip(side)
			w.aimDir = dir.Magnitude > 0.1 and dir.Unit or hrp.CFrame.LookVector
			w.crack = 1
		end
		kick(0.3)
		local tw = d.whips.R
		ringWave(function()
			local p = tw.pts[#tw.pts]
			return CFrame.lookAt(p, p + tw.aimDir)
		end, 1.6, 0.35, Color3.new(1, 1, 1))

		if res and (res.Position - hrp.Position).Magnitude <= reach + 4 then
			local inst = res.Instance
			local model = getHumanoidModel(inst)
			if model then
				reportHit(model, "Whip")
			elseif not inst.Anchored then
				-- «раскручивание»: подтягиваем и закручиваем свободную деталь
				inst:ApplyImpulse((hrp.Position + Vector3.new(0, 2, 0) - res.Position).Unit * inst.AssemblyMass * 60)
				inst.AssemblyAngularVelocity = Vector3.new(0, 25, 0)
			else
				d.hook = { pos = res.Position, expire = os.clock() + 0.7 }
			end
		end
	end,
}

---------------------------------------------------------------- Quantum Binder
local function fadeBeams(beams, duration, done)
	animate(duration, function(a)
		local tr = NumberSequence.new(0.1 + 0.9 * a)
		for _, b in ipairs(beams) do b.Transparency = tr end
	end, done)
end

-- паутина: 8 спиц + 3 кольца в плоскости XY заданного CFrame
local function makeNet(cf, radius, life)
	local holder = fxPart({ Size = Vector3.one * 0.1, Transparency = 1, CFrame = cf })
	local S, R = 8, 3
	local center = new("Attachment", {}, holder)
	local atts, beams, ring = { center }, {}, {}
	for r = 1, R do
		ring[r] = {}
		for s = 1, S do
			local ang = s / S * math.pi * 2
			local a = new("Attachment", {
				Position = Vector3.new(math.cos(ang), math.sin(ang), 0) * radius * r / R,
			}, holder)
			ring[r][s] = a
			atts[#atts + 1] = a
		end
	end
	for s = 1, S do
		beams[#beams + 1] = beam(center, ring[1][s], 0.06, 0.1, holder)
		for r = 1, R do
			if r < R then beams[#beams + 1] = beam(ring[r][s], ring[r + 1][s], 0.06, 0.1, holder) end
			beams[#beams + 1] = beam(ring[r][s], ring[r][s % S + 1], 0.05, 0.15, holder)
		end
	end
	popIn(atts, 0.15, 0.3)
	task.delay(life, function() fadeBeams(beams, 0.5, function() holder:Destroy() end) end)
	return holder
end

-- веер нитей, вылетающих из рук к цели
local function fanStrands(target, flight)
	local beams, atts, runs = {}, {}, {}
	for _, side in ipairs({ "L", "R" }) do
		local from = grip(side)
		local axis = target - from
		if axis.Magnitude > 0.1 then
			axis = axis.Unit
			local right = axis:Cross(Vector3.yAxis)
			right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
			local up = right:Cross(axis)
			for k = 1, 3 do
				local a0 = new("Attachment", { Position = from }, terrain)
				local a1 = new("Attachment", { Position = from }, terrain)
				atts[#atts + 1], atts[#atts + 2] = a0, a1
				beams[#beams + 1] = beam(a0, a1, 0.1, 0.1, fxFolder)
				runs[#runs + 1] = { a1 = a1, from = from, to = target + right * (k - 2) * 1.6 + up * ((k == 2) and 0 or 0.4), bow = up }
			end
		end
	end
	animate(flight, function(a)
		for _, r in ipairs(runs) do
			r.a1.Position = r.from:Lerp(r.to, a) + r.bow * math.sin(a * math.pi) * 0.5
		end
	end, function()
		fadeBeams(beams, 0.3, function()
			for _, a in ipairs(atts) do a:Destroy() end
			for _, b in ipairs(beams) do b:Destroy() end
		end)
	end)
end

-- кокон из трёх перпендикулярных сетей вокруг цели
local function wrapTarget(model)
	local cf, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z) * 0.65
	local life = CONFIG.WebLife
	makeNet(cf, r, life)
	makeNet(cf * CFrame.Angles(0, math.pi / 2, 0), r, life)
	makeNet(cf * CFrame.Angles(math.pi / 2, 0, 0), r, life)
	reportHit(model, "Web")
	-- локальное обездвиживание сработает только если клиент владеет сетью цели;
	-- настоящую фиксацию делайте на сервере в обработчике AegisHit
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and not hum:GetAttribute("AegisWebbed") then
		hum:SetAttribute("AegisWebbed", true)
		local ws = hum.WalkSpeed
		hum.WalkSpeed = 0
		task.delay(life, function()
			if hum.Parent then
				hum.WalkSpeed = ws
				hum:SetAttribute("AegisWebbed", nil)
			end
		end)
	end
	kick(0.35)
end

local function releaseTether(d)
	local th = d.tether
	if not th then return end
	d.tether = nil
	th.rope:Destroy(); th.hrpAtt:Destroy(); th.anchorAtt:Destroy()
	for _, s in ipairs(th.strands) do s.b:Destroy(); s.a0:Destroy(); s.a1:Destroy() end
end

-- страховочный канат: RopeConstraint + три светящиеся нити
local function makeTether(d, res)
	local hrpAtt = new("Attachment", {}, hrp)
	local anchorAtt = new("Attachment", {}, res.Instance)
	anchorAtt.WorldPosition = res.Position
	local len = (res.Position - hrp.Position).Magnitude
	local rope = new("RopeConstraint", { Attachment0 = hrpAtt, Attachment1 = anchorAtt, Length = len, Visible = false }, hrp)
	local strands = {}
	for s = 1, 3 do
		local a0 = new("Attachment", {}, terrain)
		local a1 = new("Attachment", { Position = res.Position }, terrain)
		strands[s] = { a0 = a0, a1 = a1, b = beam(a0, a1, 0.1, 0.1, fxFolder) }
	end
	d.tether = {
		rope = rope, hrpAtt = hrpAtt, anchorAtt = anchorAtt, strands = strands,
		anchor = res.Position, expire = os.clock() + CONFIG.TetherTime,
	}
end

Modes.Web = {
	enter = function(d)
		d.tether = nil
		d.maid:give(function() releaseTether(d) end)
		kick(0.25)
	end,

	update = function(d, t, dt)
		local th = d.tether
		if not th then return end
		if t > th.expire or not th.anchorAtt.Parent then
			releaseTether(d)
			return
		end
		th.rope.Length = math.max(4, th.rope.Length - 5 * dt) -- канат слегка подтягивает
		local src = { grip("L"), grip("R"), hrp.Position }
		for s, st in ipairs(th.strands) do
			st.a0.Position = src[s]
			st.a1.Position = th.anchor
		end
	end,

	ribbon = function(d, i, n, t)
		local from = grip(sideOf(i))
		local th = d.tether
		if th then
			return from:Lerp(th.anchor, (t * 0.9 + i / n) % 1), Vector3.new(0, 0.15, 0)
		end
		local fan = ((i - 1) / math.max(n - 1, 1) - 0.5) * 1.8
		local fwd = (hrp.CFrame * CFrame.Angles(0, fan, 0)).LookVector
		return from + fwd * (1.3 + 0.4 * math.sin(t * 3 + i)) + Vector3.new(0, 0.4 * math.sin(t * 2 + i * 1.3), 0),
			Vector3.new(0, 0.15, 0)
	end,

	-- тап: выстрел сетью в точку касания
	action = function(d, pos)
		releaseTether(d)
		local res, ray = aim(pos)
		local origin = (grip("L") + grip("R")) / 2
		local target = res and res.Position or (ray.Origin + ray.Direction * CONFIG.AimRange * 0.6)
		local flight = math.clamp((target - origin).Magnitude / 200, 0.1, 0.4)
		fanStrands(target, flight)
		kick(0.2)
		if not res then return end
		task.delay(flight, function()
			if modeData ~= d then return end
			local inst = res.Instance
			local model = getHumanoidModel(inst)
			if model then
				wrapTarget(model)
				return
			end
			makeNet(CFrame.lookAt(res.Position + res.Normal * 0.12, res.Position + res.Normal * 2), 4, CONFIG.WebLife)
			if inst.Anchored or inst.AssemblyMass > hrp.AssemblyMass * 2 then
				makeTether(d, res)
			else
				-- лёгкий предмет: «чувствуем вес», подтягиваем к себе
				inst:ApplyImpulse((hrp.Position - res.Position).Unit * inst.AssemblyMass * 60)
			end
			kick(0.3)
		end)
	end,
}

---------------------------------------------------------------- ядро: режимы, высвобождение
local setMode, release, retract

local function applyRibbonLook()
	local c = color()
	for _, r in ipairs(ribbons) do
		r.trail.Color = ColorSequence.new(Color3.new(1, 1, 1), c)
		r.trail.Lifetime = 0.4 * lengthMult()
	end
	if glowLight then glowLight.Color = c end
end

function setMode(name)
	if modeData then modeData.maid:clean() end
	modeData = nil
	state.mode = name
	if not state.released then return end
	local d = { name = name, maid = newMaid() }
	modeData = d
	Modes[name].enter(d)
	-- кольцо-«перестройка» вокруг тела
	ringWave(function() return CFrame.new(hrp.Position) * CFrame.Angles(math.pi / 2, 0, 0) end, 5, 0.5, color())
	kick(0.2)
end

function release()
	if state.released then return end
	state.released = true
	for i, r in ipairs(ribbons) do resetRibbon(r, i, true) end
	applyRibbonLook()
	if glowLight then tween(glowLight, 0.4, { Brightness = 1.4 }) end
	for _, side in ipairs({ "L", "R" }) do
		ringWave(function()
			local p = grip(side)
			return CFrame.lookAt(p, p + hrp.CFrame.LookVector)
		end, 2.2, 0.5, color())
	end
	setMode(state.mode)
	kick(0.3)
end

function retract()
	if not state.released then return end
	state.released = false
	if modeData then modeData.maid:clean(); modeData = nil end
	if glowLight then tween(glowLight, 0.4, { Brightness = 0 }) end
	local starts = {}
	for i, r in ipairs(ribbons) do starts[i] = r.pos end
	animate(0.4, function(a)
		if state.released then return end
		for i, r in ipairs(ribbons) do
			if starts[i] then
				local p = starts[i]:Lerp(grip(sideOf(i)), a)
				r.pos = p
				r.a0.Position, r.a1.Position = p, p + Vector3.new(0, 0.15, 0)
			end
		end
	end, function()
		if state.released then return end
		for _, r in ipairs(ribbons) do r.trail.Enabled = false; r.trail:Clear() end
	end)
end

---------------------------------------------------------------- меню и жесты
local CAS = game:GetService("ContextActionService")
local playerGui = player:WaitForChild("PlayerGui")
local gui = new("ScreenGui", {
	Name = "AegisUI", ResetOnSpawn = false, DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local MENU = {
	{ id = "Shield", label = "Щит", title = "Aegis Wall", kind = "mode" },
	{ id = "Glide", label = "Левит.", title = "Vortex Glide", kind = "mode" },
	{ id = "Blades", label = "Клинки", title = "Kine-Blades", kind = "mode" },
	{ id = "Whips", label = "Хлысты", title = "Kine-Whips", kind = "mode" },
	{ id = "Web", label = "Сеть", title = "Quantum Binder", kind = "mode" },
	{ id = "Aura", label = "Аура", title = "Базовая аура", kind = "mode" },
	{ id = "Color", label = "Цвет", kind = "setting" },
	{ id = "Density", label = "Плотн.", kind = "setting" },
	{ id = "Length", label = "Длина", kind = "setting" },
	{ id = "Recall", label = "Свернуть", title = "Погасить энергию", kind = "system" },
}

local menu = nil
local toastLabel = nil

local function toast(text)
	if toastLabel then toastLabel:Destroy() end
	local l = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(240, 30),
		BackgroundColor3 = Color3.fromRGB(10, 14, 24), BackgroundTransparency = 0.35,
		Text = text, TextColor3 = color(), Font = Enum.Font.SourceSansBold, TextSize = 18,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, l)
	toastLabel = l
	task.delay(1.4, function()
		if toastLabel == l then
			toastLabel = nil
			tween(l, 0.4, { BackgroundTransparency = 1, TextTransparency = 1 })
			task.delay(0.4, function() l:Destroy() end)
		end
	end)
end

local function cycle(i, list) return i % #list + 1 end

local function describe(def)
	if def.kind ~= "setting" then return def.title end
	if def.id == "Color" then
		return "Цвет\n" .. CONFIG.Colors[state.colorIndex][1] .. " → " .. CONFIG.Colors[cycle(state.colorIndex, CONFIG.Colors)][1]
	elseif def.id == "Density" then
		return "Плотность\n" .. CONFIG.Densities[state.densityIndex] .. " → " .. CONFIG.Densities[cycle(state.densityIndex, CONFIG.Densities)]
	end
	return "Длина\n×" .. lengthMult() .. " → ×" .. CONFIG.Lengths[cycle(state.lengthIndex, CONFIG.Lengths)]
end

-- применение выбранного пункта (после «залипания»)
local function applyChoice(def)
	if def.kind == "mode" then
		if state.released then setMode(def.id) else state.mode = def.id; release() end
		toast(def.title)
	elseif def.id == "Color" then
		state.colorIndex = cycle(state.colorIndex, CONFIG.Colors)
		applyRibbonLook()
		if state.released then setMode(state.mode) end
		toast("Цвет: " .. CONFIG.Colors[state.colorIndex][1])
	elseif def.id == "Density" then
		state.densityIndex = cycle(state.densityIndex, CONFIG.Densities)
		buildRibbons()
		applyRibbonLook()
		toast("Плотность: " .. CONFIG.Densities[state.densityIndex])
	elseif def.id == "Length" then
		state.lengthIndex = cycle(state.lengthIndex, CONFIG.Lengths)
		applyRibbonLook()
		if state.released then setMode(state.mode) end
		toast("Длина: ×" .. lengthMult())
	elseif def.id == "Recall" then
		retract()
		toast("Энергия свёрнута")
	end
end

local function baseStroke(e)
	local active = e.def.kind == "mode" and state.released and e.def.id == state.mode
	return active and 0.1 or 0.55, active and 2.2 or 1.2
end

local function setHover(e, on)
	local S = CONFIG.ItemSize
	local sz = on and S * 1.18 or S
	tween(e.frame, 0.12, { Size = UDim2.fromOffset(sz, sz) })
	local tr, th = baseStroke(e)
	tween(e.stroke, 0.12, { Transparency = on and 0 or tr, Thickness = on and 2.5 or th })
	if not on then e.fill.Size = UDim2.fromOffset(0, 0) end
end

local function closeMenu(sel, fingerPos)
	local m = menu
	if not m then return end
	menu = nil
	CAS:UnbindAction("AegisMenuSink")
	local rel = fingerPos and (fingerPos - m.center) or Vector2.zero
	for _, e in ipairs(m.items) do
		if e == sel then
			-- выбранный пункт «прилипает» к пальцу, затем схлопывается
			tween(e.frame, 0.18, { Position = UDim2.fromOffset(rel.X, rel.Y) })
			task.delay(0.18, function()
				tween(e.frame, 0.15, { Size = UDim2.fromOffset(0, 0) })
				tween(e.stroke, 0.15, { Transparency = 1 })
			end)
		else
			tween(e.frame, 0.2, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 })
			tween(e.stroke, 0.2, { Transparency = 1 })
		end
	end
	tween(m.back, 0.25, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	m.label.Text = ""
	task.delay(0.45, function() m.root:Destroy() end)
end

local function commitMenu(e, fingerPos)
	closeMenu(e, fingerPos)
	if gesture then gesture.phase = "done" end
	applyChoice(e.def)
end

local function openMenu(pos)
	local n, S = #MENU, CONFIG.ItemSize
	local R = math.max(CONFIG.MenuRadius, n * (S + 4) / (2 * math.pi))
	local abs = gui.AbsoluteSize
	local margin = R + S / 2 + 6
	local c = Vector2.new(
		math.clamp(pos.X, margin, math.max(margin, abs.X - margin)),
		math.clamp(pos.Y, margin, math.max(margin, abs.Y - margin)))

	local root = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(c.X, c.Y),
		Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1,
	}, gui)
	local back = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(10, 14, 24), BackgroundTransparency = 0.45,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
	new("UIStroke", { Color = color(), Thickness = 1.5, Transparency = 0.4 }, back)
	tween(back, 0.2, { Size = UDim2.fromOffset(2 * R + S + 10, 2 * R + S + 10) }, Enum.EasingStyle.Back)

	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2 * R - S - 16, 56),
		BackgroundTransparency = 1, Text = "A.E.G.I.S.", TextColor3 = Color3.fromRGB(190, 210, 230),
		Font = Enum.Font.SourceSansBold, TextScaled = true, ZIndex = 5,
	}, root)
	new("UITextSizeConstraint", { MaxTextSize = 18 }, label)

	local m = { root = root, back = back, label = label, items = {}, center = c, startPos = pos, armed = false, hover = nil, hoverT = 0 }
	for idx, def in ipairs(MENU) do
		local ang = -math.pi / 2 + (idx - 1) / n * math.pi * 2
		local off = Vector2.new(math.cos(ang), math.sin(ang)) * R
		local frame = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Color3.fromRGB(22, 30, 48), BackgroundTransparency = 0.15,
		}, root)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
		local stroke = new("UIStroke", { Color = color(), Thickness = 1.2, Transparency = 0.55 }, frame)
		local fill = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0), BackgroundColor3 = color(), BackgroundTransparency = 0.45,
		}, frame)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		new("TextLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromScale(0.07, 0.25), Size = UDim2.fromScale(0.86, 0.5),
			Text = def.label, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.SourceSansBold,
			TextScaled = true, ZIndex = 3,
		}, frame)
		local e = { def = def, frame = frame, fill = fill, stroke = stroke, off = off }
		m.items[idx] = e
		local tr, th = baseStroke(e)
		stroke.Transparency, stroke.Thickness = tr, th
		task.delay((idx - 1) * 0.02, function()
			tween(frame, 0.22, { Position = UDim2.fromOffset(off.X, off.Y), Size = UDim2.fromOffset(S, S) }, Enum.EasingStyle.Back)
		end)
	end
	menu = m

	-- пока открыто меню, касание не должно крутить камеру
	CAS:BindActionAtPriority("AegisMenuSink", function() return Enum.ContextActionResult.Sink end,
		false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.Touch)
	kick(0.1)
end

local function updateMenu(dt, pos)
	local m = menu
	if not m then return end
	if not m.armed and (pos - m.startPos).Magnitude > CONFIG.MoveTolerance then m.armed = true end
	local hov = nil
	if m.armed and (pos - m.center).Magnitude >= CONFIG.CenterDeadZone then
		local best = CONFIG.ItemSize * 0.8
		for _, e in ipairs(m.items) do
			local dist = (pos - (m.center + e.off)).Magnitude
			if dist < best then best, hov = dist, e end
		end
	end
	if hov ~= m.hover then
		if m.hover then setHover(m.hover, false) end
		m.hover, m.hoverT = hov, 0
		if hov then
			setHover(hov, true)
			m.label.Text = describe(hov.def)
		else
			m.label.Text = "A.E.G.I.S."
		end
	end
	if hov then
		-- «длинное зажатие»: заполняющееся кольцо → фиксация
		m.hoverT += dt
		local p = math.clamp(m.hoverT / CONFIG.LockTime, 0, 1)
		hov.fill.Size = UDim2.fromOffset(CONFIG.ItemSize * p, CONFIG.ItemSize * p)
		if p >= 1 then commitMenu(hov, pos) end
	end
end

---------------------------------------------------------------- жесты
local function curPos(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

-- левый нижний угол занят виртуальным стиком — туда жесты не принимаем
local function inMoveZone(input, pos)
	if input.UserInputType ~= Enum.UserInputType.Touch or not UserInputService.TouchEnabled then return false end
	local abs = gui.AbsoluteSize
	return pos.X < abs.X * 0.35 and pos.Y > abs.Y * 0.45
end

local function onTap(pos)
	if not state.released then
		release()
		return
	end
	local m = modeData and Modes[modeData.name]
	if m and m.action then m.action(modeData, pos) end
end

local function sameInput(input)
	if not gesture then return false end
	if input == gesture.input then return true end
	return gesture.input.UserInputType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseButton1
end

local function stepGesture(dt)
	local g = gesture
	if not g then return end
	local pos = curPos(g.input)
	g.pos = pos
	if g.phase == "down" then
		if (pos - g.start).Magnitude > CONFIG.MoveTolerance then
			g.phase = "drag" -- обычное движение пальца (камера и т.п.)
		elseif os.clock() - g.t0 >= CONFIG.MenuOpenTime then
			g.phase = "menu"
			openMenu(pos)
		end
	elseif g.phase == "menu" then
		updateMenu(dt, pos)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or gesture or not (hrp and hrp.Parent) then return end
	local ty = input.UserInputType
	if ty ~= Enum.UserInputType.Touch and ty ~= Enum.UserInputType.MouseButton1 then return end
	local pos = curPos(input)
	if inMoveZone(input, pos) then return end
	gesture = { input = input, t0 = os.clock(), start = pos, pos = pos, phase = "down" }
end)

UserInputService.InputEnded:Connect(function(input)
	if not sameInput(input) then return end
	local g = gesture
	gesture = nil
	if g.phase == "down" then
		if os.clock() - g.t0 <= CONFIG.TapMaxTime then onTap(g.pos) end
	elseif g.phase == "menu" then
		if menu and menu.hover then commitMenu(menu.hover, g.pos) else closeMenu(nil, nil) end
	end
end)

---------------------------------------------------------------- персонаж и главный цикл
local function shutdown()
	state.released = false
	if modeData then modeData.maid:clean(); modeData = nil end
	clearRibbons()
	closeMenu(nil, nil)
	gesture = nil
end

local function onCharacter(c)
	if fxFolder then fxFolder:Destroy() end
	shutdown()
	char = c
	humanoid = c:WaitForChild("Humanoid")
	hrp = c:WaitForChild("HumanoidRootPart")
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	leftHand = c:WaitForChild(r15 and "LeftHand" or "Left Arm")
	rightHand = c:WaitForChild(r15 and "RightHand" or "Right Arm")
	leftHand:WaitForChild("LeftGripAttachment", 5)
	rightHand:WaitForChild("RightGripAttachment", 5)

	fxFolder = new("Folder", { Name = "AegisFX" }, workspace)
	rayParams.FilterDescendantsInstances = { c, fxFolder }
	overlapParams.FilterDescendantsInstances = { c, fxFolder }
	glowLight = new("PointLight", { Brightness = 0, Range = 14, Color = color(), Shadows = false }, hrp)

	buildRibbons()
	applyRibbonLook()
	humanoid.Died:Connect(shutdown)
end

RunService.Heartbeat:Connect(function(dt)
	stepGesture(dt)
	if not (char and hrp and hrp.Parent and humanoid) then return end
	local t = os.clock()
	auraPulse *= math.exp(-3 * dt)

	if state.released and modeData then
		local m = Modes[modeData.name]
		if m.update then m.update(modeData, t, dt) end
		local n = #ribbons
		local alpha = 1 - math.exp(-CONFIG.RibbonFollow * dt)
		for i, r in ipairs(ribbons) do
			local target, off = m.ribbon(modeData, i, n, t)
			r.pos = r.pos:Lerp(target, alpha)
			r.a0.Position = r.pos
			r.a1.Position = r.pos + off * lengthMult()
		end
	end

	-- тряска камеры («упругая вибрация»)
	if shake > 0.01 then
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake * 1.2
		shake *= math.exp(-9 * dt)
		shakeActive = true
	elseif shakeActive then
		humanoid.CameraOffset = Vector3.zero
		shake, shakeActive = 0, false
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end
