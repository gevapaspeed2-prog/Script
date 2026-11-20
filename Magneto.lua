--==============================================================
-- LIVE HAND v3.8.1 | MAGNETO EDITION
-- FIXED BUILD
-- FIST GRAB + THROW + MAGNETIC PULSE
-- TWO HANDS + TELEPORT + GUI
--==============================================================

local HOST = "live-hand.onrender.com"
local WS_URL = "wss://" .. HOST .. "/ws?role=viewer"
local HTTP_URL = "https://" .. HOST .. "/pose"

pcall(function()
    local g = getgenv()
    if g.LIVE_HAND_CLEANUP then
        g.LIVE_HAND_CLEANUP()
    end
end)

local S = {
    forward = 1.30,
    size = 1.00,
    reach = 0.5,
    height = 0.82,

    collideFingers = true,
    collidePalm = false,

    grab = true,
    grabRange = 90,
    throwForce = 4.0,
    teleport = true,
    grabNPC = true,

    magneticRadius = 35,
    magneticPower = 250,
}

local SMOOTH_K = 45
local WIDTH_SCALE = 3.0
local HEIGHT_SCALE = 3.0
local DEPTH_SCALE = 4.2
local PALM_REF = 0.11
local DEPTH_SIGN = 1
local LOST_AFTER = 0.35
local HTTP_POLL = 0.06
local FADE_SPEED = 7
local FINGER_HIT = 0.22

local FIST_CLOSE = 0.95
local FIST_OPEN = 1.20

local TIP_JOINTS = {5, 9, 13, 17, 21}
local TIP_JOINT = {
    [5] = true,
    [9] = true,
    [13] = true,
    [17] = true,
    [21] = true
}

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local httpRequest = request or http_request or (syn and syn.request)

local alive = true
local connections = {}
local currentSock
local cleanup
local releaseGraph

local function tw(obj, t, props, style, dir)
    pcall(function()
        TweenService:Create(
            obj,
            TweenInfo.new(
                t,
                style or Enum.EasingStyle.Quad,
                dir or Enum.EasingDirection.Out
            ),
            props
        ):Play()
    end)
end

pcall(function()
    sethiddenproperty(player, "SimulationRadius", math.huge)
end)

pcall(function()
    sethiddenproperty(player, "MaximumSimulationRadius", math.huge)
end)

pcall(function()
    if setsimulationradius then
        setsimulationradius(math.huge, math.huge)
    end
end)

--==============================================================
-- FOLDER
--==============================================================

local folder = Instance.new("Folder")
folder.Name = "LIVE_HAND_V381_LOCAL"
folder.Parent = workspace

local function makePart(parent, name, size, color, shape)
    local p = Instance.new("Part")

    p.Name = name
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.SmoothPlastic

    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false

    p.CastShadow = false
    p.Shape = shape or Enum.PartType.Block
    p.Transparency = 1

    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth

    p.Parent = parent

    return p
end

--==============================================================
-- HAND STRUCTURE
--==============================================================

local links = {
    {1,2},{2,3},{3,4},{4,5},
    {1,6},{6,7},{7,8},{8,9},
    {6,10},{10,11},{11,12},{12,13},
    {10,14},{14,15},{15,16},{16,17},
    {14,18},{18,19},{19,20},{20,21},
    {1,18}
}

-- Only the actual palm bridge is excluded.
local PALM_LINK = {
    [21] = true
}

local DEFAULT_SKIN = Color3.fromRGB(226,176,142)

local LINK_FRAC = {
    0.26,0.22,0.19,0.165,0.22,
    0.175,0.155,0.14,0.20,
    0.18,0.16,0.145,0.20,
    0.17,0.15,0.135,0.19,
    0.145,0.13,0.115,0.22
}

local JOINT_FRAC = {}

for i, link in ipairs(links) do
    for _, j in ipairs(link) do
        JOINT_FRAC[j] = math.max(
            JOINT_FRAC[j] or 0,
            LINK_FRAC[i]
        )
    end
end

local function getSkin()
    local char = player.Character

    if char then
        for _, name in ipairs({"RightHand","Right Arm","Head"}) do
            local p = char:FindFirstChild(name)

            if p and p:IsA("BasePart") then
                return p.Color
            end
        end
    end

    return DEFAULT_SKIN
end

local function applySkin(rig)
    local skin = getSkin()
    local tip = skin:Lerp(Color3.fromRGB(240,150,140),0.22)

    for _, p in ipairs(rig.all) do
        p.Color = skin
    end

    for j in pairs(TIP_JOINT) do
        rig.joints[j].Color = tip
    end
end

local function createRig(label)
    local f = Instance.new("Folder")
    f.Name = label .. "_HAND"
    f.Parent = folder

    local rig = {
        joints = {},
        bones = {},
        hitboxes = {},
        all = {},

        target = nil,
        current = {},
        lastSeen = 0,

        visible = false,
        dirty = false,
        fade = 0,

        cf = false,
        cp = false,

        held = nil,
        fist = false,

        closedFor = 0,
        openFor = 0,

        vel = Vector3.zero,
        prevPos = nil,

        scanT = 0,
        palmCF = nil,

        armed = false,
        pointT = nil,

        tpCool = 0,
        noGrabUntil = 0,
        flashUntil = 0,

        gestureT = nil,
        prevRatio = nil,
        peakOpen = 0
    }

    local hl = Instance.new("Highlight")
    hl.Name = "GrabHighlight"
    hl.FillTransparency = 0.75
    hl.OutlineTransparency = 0.1
    hl.FillColor = Color3.fromRGB(150,50,255)
    hl.OutlineColor = Color3.new(1,1,1)
    hl.Enabled = false
    hl.Parent = f

    rig.hl = hl

    local ap = makePart(
        f,
        "AimAnchor",
        Vector3.new(0.2,0.2,0.2),
        Color3.new(1,1,1),
        Enum.PartType.Ball
    )

    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.fromOffset(46,46)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.Enabled = false
    gui.Adornee = ap
    gui.Parent = ap

    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5,0.5)
    ring.Position = UDim2.fromScale(0.5,0.5)
    ring.Size = UDim2.fromScale(1,1)
    ring.BackgroundTransparency = 1
    ring.Parent = gui

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(1,0)
    rc.Parent = ring

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    stroke.Color = Color3.fromRGB(150,50,255)
    stroke.Parent = ring

    local dotf = Instance.new("Frame")
    dotf.AnchorPoint = Vector2.new(0.5,0.5)
    dotf.Position = UDim2.fromScale(0.5,0.5)
    dotf.Size = UDim2.fromOffset(7,7)
    dotf.BackgroundColor3 = Color3.fromRGB(150,50,255)
    dotf.Parent = gui

    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(1,0)
    dc.Parent = dotf

    rig.aimPart = ap
    rig.aimGui = gui
    rig.aimStroke = stroke

    for i = 1,21 do
        rig.joints[i] = makePart(
            f,
            "Joint"..i,
            Vector3.new(0.16,0.16,0.16),
            DEFAULT_SKIN,
            Enum.PartType.Ball
        )

        table.insert(rig.all,rig.joints[i])
    end

    for i = 1,#links do
        rig.bones[i] = makePart(
            f,
            "Bone"..i,
            Vector3.new(0.105,0.2,0.105),
            DEFAULT_SKIN,
            Enum.PartType.Cylinder
        )

        table.insert(rig.all,rig.bones[i])

        if not PALM_LINK[i] then
            rig.hitboxes[i] = makePart(
                f,
                "FingerHit"..i,
                Vector3.new(0.2,0.2,0.2),
                DEFAULT_SKIN,
                Enum.PartType.Block
            )
        end
    end

    rig.palm = makePart(
        f,
        "Palm",
        Vector3.new(0.8,0.95,0.18),
        DEFAULT_SKIN
    )

    table.insert(rig.all,rig.palm)

    rig.wrist = makePart(
        f,
        "Wrist",
        Vector3.new(0.4,0.2,0.2),
        DEFAULT_SKIN,
        Enum.PartType.Cylinder
    )

    table.insert(rig.all,rig.wrist)

    return rig
end

local rigs = {
    Right = createRig("Right"),
    Left = createRig("Left")
}

for _, rig in pairs(rigs) do
    applySkin(rig)
end

--==============================================================
-- COLLISIONS
--==============================================================

local function setRigCollide(rig, fingersOn, palmOn)
    if rig.cf ~= fingersOn then
        rig.cf = fingersOn

        for _, j in ipairs(rig.joints) do
            j.CanCollide = fingersOn
        end

        for _, h in pairs(rig.hitboxes) do
            h.CanCollide = fingersOn
        end
    end

    if rig.cp ~= palmOn then
        rig.cp = palmOn
        rig.palm.CanCollide = palmOn
    end
end

local function fadeTransparency(f)
    return 1 - f * f * (3 - 2 * f)
end

local function hideRig(rig)
    if not rig.visible then return end

    releaseGraph(rig,false)

    rig.fist = false
    rig.closedFor = 0
    rig.openFor = 0

    rig.armed = false
    rig.pointT = nil

    rig.aimGui.Enabled = false
    rig.hl.Adornee = nil
    rig.hl.Enabled = false

    for _, p in ipairs(rig.all) do
        p.Transparency = 1
    end

    setRigCollide(rig,false,false)

    rig.visible = false
    rig.fade = 0
    rig.current = {}
    rig.palmLenS = nil
end

local function applyFade(rig)
    local tr = fadeTransparency(rig.fade)

    for _, p in ipairs(rig.all) do
        p.Transparency = tr
    end
end

local function setBone(part,a,b,width,tr)
    local len = (b-a).Magnitude

    if len < 0.004 then
        part.Transparency = 1
        return
    end

    local look = CFrame.lookAt(a,b)

    part.Size = Vector3.new(len,width,width)

    part.CFrame = CFrame.fromMatrix(
        (a+b)/2,
        look.LookVector,
        look.UpVector
    )

    part.Transparency = tr
end

--==============================================================
-- DATA RECEIVER
--==============================================================

local lastSeq = 0

local function onData(data)
    if type(data) ~= "table" then return end
    if type(data.hands) ~= "table" then return end

    local seq = tonumber(data.sequence)

    if seq then
        if seq <= lastSeq then return end
        lastSeq = seq
    end

    local now = os.clock()

    for _, hand in ipairs(data.hands) do
        if type(hand.points) == "table" and #hand.points == 21 then
            local name =
                hand.handedness == "Left" and "Left" or "Right"

            local rig = rigs[name]

            rig.target = hand.points
            rig.lastSeen = now
            rig.dirty = true
        end
    end
end

--==============================================================
-- WEBSOCKET
--==============================================================

local wsConnected = false

if WebSocket and WebSocket.connect then
    task.spawn(function()
        while alive do
            local ok,sock = pcall(
                WebSocket.connect,
                WS_URL
            )

            if ok and sock then
                currentSock = sock
                wsConnected = true
                lastSeq = 0

                local closed = false

                sock.OnMessage:Connect(function(msg)
                    local okd,data = pcall(
                        HttpService.JSONDecode,
                        HttpService,
                        msg
                    )

                    if okd then
                        onData(data)
                    end
                end)

                sock.OnClose:Connect(function()
                    closed = true
                end)

                while alive and not closed do
                    task.wait(0.5)
                end

                wsConnected = false
                currentSock = nil
            end

            if alive then
                task.wait(1.5)
            end
        end
    end)
end

--==============================================================
-- HTTP FALLBACK
--==============================================================

local busy = false
local lastPoll = 0

local function poll()
    if busy or not httpRequest then return end

    busy = true

    task.spawn(function()
        local ok,resp = pcall(
            httpRequest,
            {
                Url = HTTP_URL,
                Method = "GET",
                Headers = {
                    ["Cache-Control"] = "no-cache"
                }
            }
        )

        if ok and resp then
            local body = resp.Body or resp.body

            if body then
                local okd,data = pcall(
                    HttpService.JSONDecode,
                    HttpService,
                    body
                )

                if okd and type(data) == "table" then
                    onData(data)
                end
            end
        end

        busy = false
    end)
end

--==============================================================
-- MAGNETIC PULSE
--==============================================================

local function triggerMagneticPulse()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not root then return end

    local center = root.Position

    local ok,parts = pcall(function()
        return workspace:GetPartBoundsInRadius(
            center,
            S.magneticRadius
        )
    end)

    if not ok or not parts then return end

    local processed = {}

    for _,part in ipairs(parts) do
        if part:IsA("BasePart") and not part.Anchored then
            local pRoot = part.AssemblyRootPart or part

            if not processed[pRoot] then
                processed[pRoot] = true

                local model = pRoot:FindFirstAncestorOfClass("Model")

                if not (model and model == char) then
                    local dir = pRoot.Position-center

                    if dir.Magnitude < 1 then
                        dir = Vector3.new(0,1,0)
                    end

                    pRoot.AssemblyLinearVelocity =
                        dir.Unit*S.magneticPower
                        + Vector3.new(0,50,0)

                    pRoot.AssemblyAngularVelocity = Vector3.new(
                        math.random(-20,20),
                        math.random(-20,20),
                        math.random(-20,20)
                    )
                end
            end
        end
    end
end

--==============================================================
-- GRAB SYSTEM
--==============================================================

local function isMyCharacter(part)
    local char = player.Character

    return char and part:IsDescendantOf(char)
end

local function grabbableOK(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if isMyCharacter(part) then return false end

    local model = part:FindFirstAncestorOfClass("Model")

    if model then
        local humanoid = model:FindFirstChildOfClass("Humanoid")

        if humanoid then
            if not S.grabNPC then return false end

            local root =
                model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChild("Torso")
                or model:FindFirstChild("UpperTorso")

            if root and part ~= root then
                return false
            end
        end
    end

    local root = part.AssemblyRootPart

    return root ~= nil
        and not root.Anchored
        and part.AssemblyMass <= 3000
end

local function filterParams(isOverlap)
    local params

    if isOverlap then
        params = OverlapParams.new()
    else
        params = RaycastParams.new()
    end

    params.FilterType = Enum.RaycastFilterType.Exclude

    local ex = {folder}

    if player.Character then
        table.insert(ex,player.Character)
    end

    params.FilterDescendantsInstances = ex

    return params
end

local function findGrabbable(center,radius)
    local ok,best = pcall(function()
        local found
        local bestD = math.huge

        for _,part in ipairs(
            workspace:GetPartBoundsInRadius(
                center,
                radius,
                filterParams(true)
            )
        ) do
            if grabbableOK(part) then
                local d = (part.Position-center).Magnitude

                if d < bestD then
                    found = part
                    bestD = d
                end
            end
        end

        return found
    end)

    return ok and best or nil
end

local function findFarGrabbable(origin,dir,range)
    local ok,res = pcall(function()
        local hit = workspace:Raycast(
            origin,
            dir*range,
            filterParams(false)
        )

        if hit and hit.Instance and grabbableOK(hit.Instance) then
            return hit.Instance
        end

        return nil
    end)

    return ok and res or nil
end

local function findGrabTarget(pinchPos)
    local near = findGrabbable(pinchPos,2.8)

    if near then
        return near,"near"
    end

    if S.grabRange > 2.8 then
        local cam = workspace.CurrentCamera

        if cam then
            local origin = cam.CFrame.Position
            local dir = pinchPos-origin

            if dir.Magnitude > 0.01 then
                local far = findFarGrabbable(
                    origin,
                    dir.Unit,
                    S.grabRange
                )

                if far then
                    return far,"far"
                end
            end
        end
    end

    return nil
end

local function tryGrab(rig)
    if rig.held or not rig.palmCF then return end

    local grabCenter = rig.pinchPos or rig.palmCF.Position

    local part,mode = findGrabTarget(grabCenter)

    if not part then return end

    for _,other in pairs(rigs) do
        if other ~= rig and other.held
            and other.held.part == part then
            return
        end
    end

    local cam = workspace.CurrentCamera
    local targetPart = part

    local model = part:FindFirstAncestorOfClass("Model")

    if model then
        local hum = model:FindFirstChildOfClass("Humanoid")

        if hum then
            local rp =
                model:FindFirstChild("HumanoidRootPart")
                or model:FindFirstChild("Torso")

            if rp then
                targetPart = rp
            end
        end
    end

    rig.held = {
        part = targetPart,
        mode = mode,

        canCollide = targetPart.CanCollide,

        offset = rig.palmCF:ToObjectSpace(
            targetPart.CFrame
        ),

        dist = cam and (
            targetPart.Position-cam.CFrame.Position
        ).Magnitude or 10,

        rot = targetPart.CFrame.Rotation,
        reach0 = rig.reachRaw or 0
    }

    targetPart.CanCollide = false

    rig.prevPos = targetPart.Position
    rig.vel = Vector3.zero
    rig.peakOpen = 0

    rig.hl.FillColor = Color3.fromRGB(200,80,255)
    rig.hl.Adornee = targetPart
    rig.hl.Enabled = true
end

releaseGraph = function(rig,throwKind)
    local g = rig.held

    if not g then return end

    rig.held = nil
    rig.hl.Adornee = nil
    rig.hl.Enabled = false

    local part = g.part

    if part and part.Parent then
        part.CanCollide = g.canCollide

        local v = Vector3.zero

        if throwKind == "throw" then
            local cam = workspace.CurrentCamera

            local look = cam and cam.CFrame.LookVector
                or Vector3.new(0,0,-1)

            v = (rig.vel+look*80)*S.throwForce

            if v.Magnitude > 600 then
                v = v.Unit*600
            end

        elseif throwKind == "drop" then
            v = rig.vel*0.3

            if v.Magnitude > 25 then
                v = v.Unit*25
            end
        end

        part.AssemblyLinearVelocity = v

        part.AssemblyAngularVelocity = Vector3.new(
            math.random(-10,10),
            math.random(-10,10),
            math.random(-10,10)
        )
    end
end

local function holdUpdate(rig,dt)
    local g = rig.held

    if not g then return end

    local part = g.part

    if not part or not part.Parent then
        releaseGraph(rig,false)
        return
    end

    if g.mode == "far" then
        local cam = workspace.CurrentCamera

        if not cam or not rig.pinchPos then
            releaseGraph(rig,false)
            return
        end

        local origin = cam.CFrame.Position
        local dir = rig.pinchPos-origin

        if dir.Magnitude > 0.01 then
            local maxD = math.max(S.grabRange*1.5,10)

            local dist = math.clamp(
                g.dist+((rig.reachRaw or 0)-g.reach0)*25,
                3,
                maxD
            )

            local target = CFrame.new(
                origin+dir.Unit*dist
            )*g.rot

            part.CFrame = part.CFrame:Lerp(target,0.4)
        end

    else
        if not rig.palmCF then
            releaseGraph(rig,false)
            return
        end

        part.CFrame = rig.palmCF*g.offset
    end

    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero

    local pos = part.Position

    if rig.prevPos then
        local v = (pos-rig.prevPos)/math.max(dt,1e-3)
        rig.vel = rig.vel:Lerp(v,0.35)
    end

    rig.prevPos = pos
end

--==============================================================
-- TELEPORT
--==============================================================

local function aimTarget(positions)
    local cam = workspace.CurrentCamera

    if not cam then return nil end

    local origin = cam.CFrame.Position
    local dir = positions[9]-origin

    if dir.Magnitude < 0.01 then return nil end

    local ok,res = pcall(function()
        local params = RaycastParams.new()

        params.FilterType = Enum.RaycastFilterType.Exclude

        local ex = {folder}

        if player.Character then
            table.insert(ex,player.Character)
        end

        params.FilterDescendantsInstances = ex

        return workspace:Raycast(
            origin,
            dir.Unit*250,
            params
        )
    end)

    if ok and res then
        return res.Position,res.Normal
    end

    return nil
end

local function doTeleport(pos,normal)
    local char = player.Character

    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not root then return end

    local hum = char:FindFirstChildOfClass("Humanoid")

    local hip = (hum and hum.HipHeight or 0)+root.Size.Y/2

    local newPos =
        pos
        + Vector3.new(0,hip+0.3,0)
        + Vector3.new(normal.X,0,normal.Z)*1.2

    root.CFrame = CFrame.new(newPos)*(root.CFrame-root.CFrame.Position)
    root.AssemblyLinearVelocity = Vector3.zero
end

local function showAim(rig,pos,normal,now)
    rig.aimPart.Position = pos+normal*0.05

    local sz = 46+5*math.sin(now*9)

    rig.aimGui.Size = UDim2.fromOffset(sz,sz)
    rig.aimGui.Enabled = true
end

local function flashAim(rig,now)
    local gui = rig.aimGui
    local stroke = rig.aimStroke

    rig.flashUntil = now+0.4

    gui.Enabled = true
    gui.Size = UDim2.fromOffset(46,46)

    stroke.Transparency = 0

    tw(gui,0.35,{
        Size = UDim2.fromOffset(120,120)
    })

    tw(stroke,0.35,{
        Transparency = 1
    })

    task.delay(0.4,function()
        if not alive then return end
        gui.Enabled = false
        stroke.Transparency = 0
    end)
end

--==============================================================
-- BASE TRANSFORM
--==============================================================

local function getBase(root)
    local cam = workspace.CurrentCamera

    local look = cam and cam.CFrame.LookVector
        or root.CFrame.LookVector

    local flat = Vector3.new(look.X,0,look.Z)

    if flat.Magnitude < 0.01 then
        flat = root.CFrame.LookVector
    end

    return CFrame.lookAt(
        root.Position,
        root.Position+flat.Unit
    )
end

--==============================================================
-- UPDATE HAND
--==============================================================

local function updateRig(rig,dt,base,baseMoved)
    local present =
        rig.target
        and os.clock()-rig.lastSeen <= LOST_AFTER

    if not present then
        if rig.visible then
            rig.fade = rig.fade-dt*FADE_SPEED

            if rig.fade <= 0 then
                hideRig(rig)
            else
                applyFade(rig)
                setRigCollide(rig,false,false)
            end
        end

        return
    end

    local fading = rig.fade < 1

    if fading then
        rig.fade = math.min(1,rig.fade+dt*FADE_SPEED)
    end

    if not (
        rig.dirty
        or baseMoved
        or rig.moving
        or fading
    ) then
        return
    end

    rig.dirty = false

    local pts = rig.target

    local w,m = pts[1],pts[10]

    local palmSize = math.sqrt(
        ((w.x-m.x)*1.33)^2
        +(w.y-m.y)^2
    )

    local rawReach = math.clamp(
        (palmSize-PALM_REF)/PALM_REF,
        -1,
        1.5
    )

    rig.reachRaw = rig.reachRaw
        and (
            rig.reachRaw
            +(rawReach-rig.reachRaw)*math.min(1,dt*20)
        )
        or rawReach

    local reach = rawReach*S.reach

    rig.reach = rig.reach
        and (
            rig.reach
            +(reach-rig.reach)*math.min(1,dt*20)
        )
        or reach

    local raw = {}

    for i = 1,21 do
        local p = pts[i]

        local x = (0.5-(tonumber(p.x) or 0.5))*WIDTH_SCALE
        local y = (0.55-(tonumber(p.y) or 0.5))*HEIGHT_SCALE

        local depth =
            -(tonumber(p.z) or 0)*DEPTH_SCALE*DEPTH_SIGN

        raw[i] = Vector3.new(
            x,
            S.height+y,
            -(S.forward+rig.reach+depth)
        )
    end

    local wristRaw = raw[1]
    local alpha = 1-math.exp(-dt*SMOOTH_K)

    local moving = false
    local positions = {}

    local tr = fadeTransparency(rig.fade)

    for i = 1,21 do
        local target =
            wristRaw+(raw[i]-wristRaw)*S.size

        local cur = rig.current[i]

        if cur then
            cur = cur:Lerp(target,alpha)

            if (cur-target).Magnitude > 0.004 then
                moving = true
            end
        else
            cur = target
            moving = true
        end

        rig.current[i] = cur

        positions[i] = base:PointToWorldSpace(cur)

        local j = rig.joints[i]

        j.Position = positions[i]
        j.Transparency = tr
    end

    rig.moving = moving

    local pl = (positions[10]-positions[1]).Magnitude

    rig.palmLenS = rig.palmLenS
        and (
            rig.palmLenS
            +(pl-rig.palmLenS)*math.min(1,dt*12)
        )
        or pl

    local PL = math.max(rig.palmLenS,0.08)

    for i = 1,21 do
        local d = JOINT_FRAC[i]*PL
            *(TIP_JOINT[i] and 1 or 1.06)

        rig.joints[i].Size = Vector3.new(d,d,d)
    end

    -- FINGER BONES

    for i,link in ipairs(links) do
        setBone(
            rig.bones[i],
            positions[link[1]],
            positions[link[2]],
            LINK_FRAC[i]*PL,
            tr
        )
    end

    -- FINGER COLLIDERS

    if S.collideFingers then
        local hw = math.max(FINGER_HIT*S.size,0.12)

        for i,hb in pairs(rig.hitboxes) do
            local a = positions[links[i][1]]
            local b = positions[links[i][2]]

            local len = (b-a).Magnitude

            if len > 0.005 then
                hb.Size = Vector3.new(
                    hw,
                    hw,
                    len+hw*0.6
                )

                hb.CFrame = CFrame.lookAt(
                    (a+b)/2,
                    b
                )
            end
        end
    end

    -- PALM

    local wrist = positions[1]
    local indexB = positions[6]
    local pinkyB = positions[18]
    local middleB = positions[10]

    local up = middleB-wrist
    local right = indexB-pinkyB

    if up.Magnitude > 0.02 and right.Magnitude > 0.02 then
        up = up.Unit

        right = right-up*right:Dot(up)

        if right.Magnitude > 0.001 then
            right = right.Unit

            local back = right:Cross(up).Unit

            rig.palm.Size = Vector3.new(
                (indexB-pinkyB).Magnitude+PL*0.18,
                (middleB-wrist).Magnitude*1.02,
                PL*0.30
            )

            setBone(
                rig.wrist,
                wrist-up*(PL*0.55),
                wrist,
                PL*0.30,
                tr
            )

            local pcf = CFrame.fromMatrix(
                (wrist+middleB)/2,
                right,
                up,
                back
            )

            rig.palm.CFrame = pcf
            rig.palmCF = pcf
            rig.palm.Transparency = tr
        end
    end

    local nowT = os.clock()

    -- TELEPORT GESTURE

    local plen = (positions[10]-positions[1]).Magnitude

    if S.teleport and plen > 0.05 then
        local idx =
            (positions[9]-positions[1]).Magnitude/plen

        local oth = (
            (positions[13]-positions[1]).Magnitude
            +(positions[17]-positions[1]).Magnitude
            +(positions[21]-positions[1]).Magnitude
        )/3/plen

        local pointing = idx >= 1.60 and oth <= 1.45

        if pointing then
            rig.pointT = rig.pointT or nowT

            if not rig.armed
                and nowT-rig.pointT >= 0.12
                and nowT >= rig.tpCool then

                rig.armed = true
            end

        elseif not (rig.armed and oth <= 1.65) then
            rig.pointT = nil
            rig.armed = false
        end

        if rig.armed then
            rig.noGrabUntil = nowT+0.6

            if idx >= 1.50 then
                local pos,normal = aimTarget(positions)

                rig.tpTarget = pos
                rig.tpNormal = normal
            end

            if rig.tpTarget then
                showAim(
                    rig,
                    rig.tpTarget,
                    rig.tpNormal,
                    nowT
                )
            else
                rig.aimGui.Enabled = false
            end

            if idx <= 1.28 then
                if rig.tpTarget then
                    doTeleport(
                        rig.tpTarget,
                        rig.tpNormal
                    )

                    flashAim(rig,nowT)
                end

                rig.armed = false
                rig.pointT = nil
                rig.tpTarget = nil

                rig.tpCool = nowT+1
                rig.noGrabUntil = nowT+0.5
            end

        elseif nowT > rig.flashUntil then
            rig.aimGui.Enabled = false
        end

    else
        rig.armed = false
        rig.pointT = nil

        if nowT > rig.flashUntil then
            rig.aimGui.Enabled = false
        end
    end

    --==========================================================
    -- FIST GRAB
    --==========================================================

    if S.grab then
        local palmLen =
            (positions[10]-positions[1]).Magnitude

        rig.pinchPos = positions[10]

        if palmLen > 0.05 then
            local totalDist = 0

            for _,idx in ipairs(TIP_JOINTS) do
                totalDist = totalDist
                    +(positions[idx]-positions[10]).Magnitude
            end

            local avgDist =
                (totalDist/#TIP_JOINTS)/palmLen

            local dtg = math.max(
                nowT-(rig.gestureT or nowT),
                1e-3
            )

            local openRate =
                (avgDist-(rig.prevRatio or avgDist))/dtg

            rig.gestureT = nowT
            rig.prevRatio = avgDist

            rig.peakOpen = math.max(
                openRate,
                (rig.peakOpen or 0)*math.exp(-dtg*5)
            )

            if avgDist < FIST_CLOSE then
                rig.closedFor = rig.closedFor+dt
                rig.openFor = 0

            elseif avgDist > FIST_OPEN then
                rig.openFor = rig.openFor+dt
                rig.closedFor = 0
            end

            if not rig.fist and rig.closedFor >= 0.04 then
                rig.fist = true

                if nowT >= rig.noGrabUntil then
                    tryGrab(rig)
                end

            elseif rig.fist and rig.openFor >= 0.06 then
                rig.fist = false

                releaseGraph(
                    rig,
                    (rig.peakOpen or 0) >= 3
                        and "throw"
                        or "drop"
                )
            end
        end

        if not rig.fist and not rig.held then
            rig.scanT = rig.scanT+dt

            if rig.scanT >= 0.1 then
                rig.scanT = 0

                local near = findGrabTarget(
                    rig.pinchPos or positions[1]
                )

                if near then
                    rig.hl.FillColor =
                        Color3.fromRGB(180,80,255)

                    rig.hl.Adornee = near
                    rig.hl.Enabled = true
                else
                    rig.hl.Adornee = nil
                    rig.hl.Enabled = false
                end
            end
        end

    else
        if rig.held then
            releaseGraph(rig,false)
        end

        rig.fist = false
        rig.closedFor = 0
        rig.openFor = 0

        rig.hl.Adornee = nil
        rig.hl.Enabled = false
    end

    rig.visible = true

    local solid = rig.fade > 0.6

    setRigCollide(
        rig,
        S.collideFingers and solid,
        S.collidePalm and solid
    )
end

--==============================================================
-- MAIN LOOP
--==============================================================

local lastBasePos
local lastBaseLook

table.insert(
    connections,
    RunService.RenderStepped:Connect(function(dt)
        local now = os.clock()

        if not wsConnected and now-lastPoll >= HTTP_POLL then
            lastPoll = now
            poll()
        end

        local char = player.Character

        local root =
            char and char:FindFirstChild("HumanoidRootPart")

        if not root then
            hideRig(rigs.Right)
            hideRig(rigs.Left)
            return
        end

        local base = getBase(root)

        local moved =
            not lastBasePos
            or (base.Position-lastBasePos).Magnitude > 0.001
            or (base.LookVector-lastBaseLook).Magnitude > 0.0005

        lastBasePos = base.Position
        lastBaseLook = base.LookVector

        updateRig(rigs.Right,dt,base,moved)
        updateRig(rigs.Left,dt,base,moved)

        holdUpdate(rigs.Right,dt)
        holdUpdate(rigs.Left,dt)
    end)
)

table.insert(
    connections,
    player.CharacterAdded:Connect(function()
        task.wait(1)

        for _,rig in pairs(rigs) do
            rig.current = {}
            applySkin(rig)
        end
    end)
)

local function markDirty()
    rigs.Right.dirty = true
    rigs.Left.dirty = true
end

--==============================================================
-- GUI
--==============================================================

local WIN_W = 240
local FULL_H = 390
local TITLE_H = 28

local ACCENT = Color3.fromRGB(150,60,255)

local gui = Instance.new("ScreenGui")

gui.Name = "LiveHandUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then
        gui.Parent = gethui()
    end
end)

if not gui.Parent then
    pcall(function()
        gui.Parent = game:GetService("CoreGui")
    end)
end

if not gui.Parent then
    gui.Parent = player:WaitForChild("PlayerGui")
end

local function corner(obj,r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,r)
    c.Parent = obj
end

local function newLabel(parent,text,size,color,align)
    local l = Instance.new("TextLabel")

    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.GothamMedium
    l.TextSize = size
    l.TextColor3 = color or Color3.fromRGB(230,238,255)
    l.TextXAlignment = align or Enum.TextXAlignment.Left

    l.Parent = parent

    return l
end

local win = Instance.new("Frame")

win.Name = "Window"
win.Size = UDim2.fromOffset(WIN_W,FULL_H)
win.BackgroundColor3 = Color3.fromRGB(20,15,32)
win.BackgroundTransparency = 1
win.ClipsDescendants = true
win.Active = true
win.Parent = gui

corner(win,12)

local stroke = Instance.new("UIStroke")
stroke.Color = ACCENT
stroke.Thickness = 1.5
stroke.Transparency = 1
stroke.Parent = win

local vp = workspace.CurrentCamera
    and workspace.CurrentCamera.ViewportSize
    or Vector2.new(800,400)

local finalPos = UDim2.fromOffset(
    vp.X-WIN_W-10,
    10
)

win.Position = UDim2.fromOffset(vp.X+20,10)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1,0,0,TITLE_H)
titleBar.BackgroundTransparency = 1
titleBar.Active = true
titleBar.Parent = win

local title = newLabel(
    titleBar,
    "🧲 FIST & MAGNETIC PULSE",
    13,
    Color3.new(1,1,1)
)

title.Font = Enum.Font.GothamBold
title.Position = UDim2.fromOffset(10,0)
title.Size = UDim2.new(1,-104,1,0)

local function iconBtn(text,fromRight)
    local b = Instance.new("TextButton")

    b.Size = UDim2.fromOffset(26,22)
    b.Position = UDim2.new(1,-fromRight,0.5,-11)

    b.BackgroundColor3 = Color3.fromRGB(45,30,72)
    b.AutoButtonColor = false

    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.new(1,1,1)

    b.Parent = titleBar

    corner(b,6)

    b.MouseButton1Down:Connect(function()
        tw(b,0.08,{
            BackgroundColor3 = ACCENT
        })
    end)

    b.MouseButton1Up:Connect(function()
        tw(b,0.2,{
            BackgroundColor3 =
                b:GetAttribute("base")
                or Color3.fromRGB(45,30,72)
        })
    end)

    return b
end

local lockBtn = iconBtn("🔓",92)
local minBtn = iconBtn("–",62)
local closeBtn = iconBtn("✕",32)

local activeDrag

local function isStart(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch
end

table.insert(
    connections,
    UserInputService.InputChanged:Connect(function(input)
        if not activeDrag then return end

        local t = input.UserInputType

        if t == Enum.UserInputType.MouseMovement
            or (
                t == Enum.UserInputType.Touch
                and input == activeDrag.input
            ) then

            activeDrag.move(
                Vector2.new(
                    input.Position.X,
                    input.Position.Y
                )
            )
        end
    end)
)

table.insert(
    connections,
    UserInputService.InputEnded:Connect(function(input)
        if not activeDrag then return end

        if input == activeDrag.input
            or (
                input.UserInputType == Enum.UserInputType.MouseButton1
                and activeDrag.input.UserInputType
                    == Enum.UserInputType.MouseButton1
            ) then

            local d = activeDrag
            activeDrag = nil

            if d.finish then
                d.finish()
            end
        end
    end)
)

local locked = false
local minimized = false

titleBar.InputBegan:Connect(function(input)
    if locked or not isStart(input) then return end

    local startPointer = Vector2.new(
        input.Position.X,
        input.Position.Y
    )

    local startWin = win.AbsolutePosition

    activeDrag = {
        input = input,

        move = function(pos)
            local v = workspace.CurrentCamera
                and workspace.CurrentCamera.ViewportSize
                or Vector2.new(800,400)

            local nx = math.clamp(
                startWin.X+(pos.X-startPointer.X),
                0,
                v.X-win.AbsoluteSize.X
            )

            local ny = math.clamp(
                startWin.Y+(pos.Y-startPointer.Y),
                0,
                v.Y-TITLE_H
            )

            win.Position = UDim2.fromOffset(nx,ny)
        end
    }
end)

local content = Instance.new("Frame")
content.Position = UDim2.fromOffset(0,TITLE_H)
content.Size = UDim2.new(1,0,1,-TITLE_H)
content.BackgroundTransparency = 1
content.Parent = win

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0,12)
pad.PaddingRight = UDim.new(0,12)
pad.PaddingTop = UDim.new(0,6)
pad.Parent = content

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0,4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = content

--==============================================================
-- SLIDERS
--==============================================================

local sliders = {}

local function makeSlider(
    order,
    text,
    minV,
    maxV,
    default,
    decimals,
    onChange
)
    local row = Instance.new("Frame")

    row.LayoutOrder = order
    row.Size = UDim2.new(1,0,0,30)
    row.BackgroundTransparency = 1
    row.Parent = content

    local lbl = newLabel(row,text,13)
    lbl.Size = UDim2.new(0.7,0,0,16)

    local val = newLabel(
        row,
        "",
        13,
        ACCENT,
        Enum.TextXAlignment.Right
    )

    val.Font = Enum.Font.GothamBold
    val.Position = UDim2.fromScale(0.5,0)
    val.Size = UDim2.new(0.5,0,0,16)

    local track = Instance.new("Frame")

    track.Position = UDim2.fromOffset(0,19)
    track.Size = UDim2.new(1,0,0,6)
    track.BackgroundColor3 = Color3.fromRGB(45,35,66)
    track.Parent = row

    corner(track,3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0,1)
    fill.BackgroundColor3 = ACCENT
    fill.Parent = track

    corner(fill,3)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Size = UDim2.fromOffset(14,14)
    knob.Position = UDim2.fromScale(0,0.5)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.ZIndex = 2
    knob.Parent = track

    corner(knob,7)

    local hit = Instance.new("TextButton")
    hit.Position = UDim2.fromOffset(0,11)
    hit.Size = UDim2.new(1,0,0,19)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.ZIndex = 3
    hit.Parent = row

    local slider = {}

    function slider.set(v,instant)
        local k = 10^decimals

        v = math.floor(
            math.clamp(v,minV,maxV)*k+0.5
        )/k

        local ratio = (v-minV)/(maxV-minV)

        if instant then
            fill.Size = UDim2.fromScale(ratio,1)
            knob.Position = UDim2.fromScale(ratio,0.5)
        else
            tw(fill,0.18,{
                Size = UDim2.fromScale(ratio,1)
            })

            tw(knob,0.18,{
                Position = UDim2.fromScale(ratio,0.5)
            })
        end

        val.Text = string.format(
            "%."..decimals.."f",
            v
        )

        onChange(v)
    end

    function slider.reset()
        slider.set(default,false)
    end

    hit.InputBegan:Connect(function(input)
        if not isStart(input) then return end

        local function fromX(x)
            slider.set(
                minV+math.clamp(
                    (x-hit.AbsolutePosition.X)
                    /hit.AbsoluteSize.X,
                    0,
                    1
                )*(maxV-minV),
                true
            )
        end

        fromX(input.Position.X)

        activeDrag = {
            input = input,

            move = function(pos)
                fromX(pos.X)
            end,

            finish = function()
                tw(knob,0.15,{
                    Size = UDim2.fromOffset(14,14)
                })
            end
        }
    end)

    slider.set(default,true)

    table.insert(sliders,slider)

    return slider
end

makeSlider(
    1,
    "Дальность рук",
    0.5,
    8,
    S.forward,
    2,
    function(v)
        S.forward = v
        markDirty()
    end
)

makeSlider(
    2,
    "Радиус поля",
    10,
    100,
    S.magneticRadius,
    0,
    function(v)
        S.magneticRadius = v
    end
)

makeSlider(
    3,
    "Сила импульса",
    50,
    600,
    S.magneticPower,
    0,
    function(v)
        S.magneticPower = v
    end
)

--==============================================================
-- MAGNET BUTTON
--==============================================================

local pulseBtn = Instance.new("TextButton")

pulseBtn.LayoutOrder = 4
pulseBtn.Size = UDim2.new(1,0,0,34)

pulseBtn.BackgroundColor3 = Color3.fromRGB(120,46,160)
pulseBtn.AutoButtonColor = false

pulseBtn.Text = "⚡ АКТИВИРОВАТЬ МАГНИТНОЕ ПОЛЕ"
pulseBtn.Font = Enum.Font.GothamBold
pulseBtn.TextSize = 11
pulseBtn.TextColor3 = Color3.new(1,1,1)

pulseBtn.Parent = content

corner(pulseBtn,8)

pulseBtn.MouseButton1Click:Connect(function()
    tw(pulseBtn,0.1,{
        BackgroundColor3 = Color3.fromRGB(200,100,255)
    })

    task.delay(0.15,function()
        if alive then
            tw(pulseBtn,0.2,{
                BackgroundColor3 = Color3.fromRGB(120,46,160)
            })
        end
    end)

    triggerMagneticPulse()
end)

--==============================================================
-- TOGGLE BUTTONS
--==============================================================

local OFF_C = Color3.fromRGB(45,30,72)
local ON_C = Color3.fromRGB(120,46,160)

local function chipRow(order)
    local r = Instance.new("Frame")

    r.LayoutOrder = order
    r.Size = UDim2.new(1,0,0,32)
    r.BackgroundTransparency = 1
    r.Parent = content

    local l = Instance.new("UIListLayout")

    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0,6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = r

    return r
end

local function makeChip(
    row,
    count,
    order,
    caption,
    name,
    key,
    onClick
)
    local b = Instance.new("TextButton")

    b.LayoutOrder = order

    b.Size = UDim2.new(
        1/count,
        -(6*(count-1))/count,
        1,
        0
    )

    b.BackgroundColor3 =
        (key and S[key]) and ON_C or OFF_C

    b.AutoButtonColor = false
    b.RichText = true

    b.Text =
        '<font size="9" color="#d1afef">'
        ..caption
        ..'</font>\n'
        ..name

    b.Font = Enum.Font.GothamMedium
    b.TextSize = 12
    b.TextColor3 = Color3.new(1,1,1)

    b.Parent = row

    corner(b,8)

    b.MouseButton1Click:Connect(function()
        if key then
            S[key] = not S[key]

            tw(b,0.2,{
                BackgroundColor3 = S[key] and ON_C or OFF_C
            })

            markDirty()
        else
            tw(b,0.08,{
                BackgroundColor3 = ACCENT
            })

            task.delay(0.12,function()
                if alive then
                    tw(b,0.25,{
                        BackgroundColor3 = OFF_C
                    })
                end
            end)

            if onClick then
                onClick()
            end
        end
    end)
end

local row1 = chipRow(5)

makeChip(
    row1,2,1,
    "телекинез",
    "Захват NPC",
    "grabNPC"
)

makeChip(
    row1,2,2,
    "кулак",
    "Захват",
    "grab"
)

local row2 = chipRow(6)

makeChip(
    row2,2,1,
    "указательный",
    "Телепорт",
    "teleport"
)

makeChip(
    row2,2,2,
    "настройки",
    "Сброс",
    nil,
    function()
        for _,sl in ipairs(sliders) do
            sl.reset()
        end
    end
)

--==============================================================
-- STATUS
--==============================================================

local statusRow = Instance.new("Frame")

statusRow.LayoutOrder = 7
statusRow.Size = UDim2.new(1,0,0,18)
statusRow.BackgroundTransparency = 1
statusRow.Parent = content

local dot = Instance.new("Frame")

dot.AnchorPoint = Vector2.new(0,0.5)
dot.Position = UDim2.new(0,0,0.5,0)
dot.Size = UDim2.fromOffset(8,8)
dot.BackgroundColor3 = Color3.fromRGB(255,198,109)
dot.Parent = statusRow

corner(dot,4)

TweenService:Create(
    dot,
    TweenInfo.new(
        0.9,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1,
        true
    ),
    {
        BackgroundTransparency = 0.7
    }
):Play()

local statusLbl = newLabel(
    statusRow,
    "Подключение…",
    12,
    Color3.fromRGB(200,175,230)
)

statusLbl.Position = UDim2.fromOffset(14,0)
statusLbl.Size = UDim2.new(1,-14,1,0)

--==============================================================
-- WINDOW CONTROLS
--==============================================================

lockBtn.MouseButton1Click:Connect(function()
    locked = not locked

    lockBtn.Text = locked and "🔒" or "🔓"

    local c = locked and ON_C or OFF_C

    lockBtn:SetAttribute("base",c)

    tw(lockBtn,0.2,{
        BackgroundColor3 = c
    })
end)

minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized

    minBtn.Text = minimized and "+" or "–"

    tw(win,0.28,{
        Size = UDim2.fromOffset(
            WIN_W,
            minimized and TITLE_H or FULL_H
        )
    },Enum.EasingStyle.Quint)
end)

--==============================================================
-- CLEANUP
--==============================================================

cleanup = function()
    if not alive then return end

    alive = false

    for _,c in ipairs(connections) do
        pcall(function()
            c:Disconnect()
        end)
    end

    for _,rig in pairs(rigs) do
        pcall(releaseGraph,rig,false)
    end

    if currentSock then
        pcall(function()
            currentSock:Close()
        end)
    end

    pcall(function()
        folder:Destroy()
    end)

    pcall(function()
        gui:Destroy()
    end)
end

closeBtn.MouseButton1Click:Connect(cleanup)

pcall(function()
    getgenv().LIVE_HAND_CLEANUP = cleanup
end)

--==============================================================
-- STATUS LOOP
--==============================================================

task.spawn(function()
    while alive do
        local n =
            (rigs.Right.visible and 1 or 0)
            +(rigs.Left.visible and 1 or 0)

        local mode = wsConnected and "WS" or "HTTP"

        local held =
            (rigs.Right.held and 1 or 0)
            +(rigs.Left.held and 1 or 0)

        statusLbl.Text =
            mode
            .." · "
            ..n
            .."/2"
            ..(held > 0 and (" · Держит "..held) or "")

        tw(dot,0.3,{
            BackgroundColor3 =
                wsConnected
                and Color3.fromRGB(150,60,255)
                or Color3.fromRGB(255,198,109)
        })

        task.wait(0.5)
    end
end)

print("[LIVE HAND v3.8.1 MAGNETO] запущен.")