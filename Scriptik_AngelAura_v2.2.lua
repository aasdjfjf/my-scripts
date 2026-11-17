-- SCRIPTIK | Angel Aura Visual + Wallhack + Aimbot  v2.2  (client-side Luau)
-- Telegram: @skriptik2026

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end
local camera = workspace.CurrentCamera or workspace:WaitForChild("Camera", 10)
local host = camera or workspace

-- ===== error guard: one broken module never kills the whole script =====
local errCount = 0
local function safe(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		errCount += 1
		if errCount <= 20 then warn("[Scriptik] " .. name .. ": " .. tostring(err)) end
	end
	return ok
end

if _G.ScriptikCleanup then pcall(_G.ScriptikCleanup) end
if _G.AeroVisualCleanup then pcall(_G.AeroVisualCleanup) end

local TG_HANDLE = "@skriptik2026"
local TG_LINK = "https://t.me/skriptik2026"
local TOUCH = UIS.TouchEnabled and not UIS.MouseEnabled

local MAIN   = Color3.fromRGB(170, 60, 255)
local ACCENT = Color3.fromRGB(255, 150, 255)
local DEEP   = Color3.fromRGB(70, 10, 140)
local WHITE  = Color3.new(1, 1, 1)

-- ===== settings (all changeable from the menu) =====
local CFG = {
	Visual = true, Lighting = true, Halo = true, Wings = true, Rings = true,
	Particles = true, Highlight = true, PointLight = true, Orbs = true,
	WingScale = 0.85, FlapSpeed = 2.0, FlapAmount = 7,
	WingDetail = TOUCH and 2 or 3, WingSparks = true,

	ESP = false, ESPNames = true, ESPHealth = true, ESPDistance = true,
	ESPTeamCheck = true, ESPMaxDist = 1500,

	Aim = false, AimMode = TOUCH and "Always" or "Hold RMB", AimPart = "Head",
	AimFOV = 150, AimSmooth = 0.25, AimWallCheck = true, AimTeamCheck = true, AimShowFOV = true,

	Crosshair = true, CrosshairRainbow = false, CrosshairSize = 1, CrosshairSpeed = 1,
	RainbowWeapon = true, RainbowSpeed = 1,
	HideFab = false,

	MenuKey = Enum.KeyCode.RightShift,
}

local DETAIL = {
	[1] = { mul = 0.55, split = false, tips = false },
	[2] = { mul = 0.80, split = true,  tips = false },
	[3] = { mul = 1.00, split = true,  tips = true  },
}
local DETAIL_NAMES = { "Low", "Medium", "High" }

local WING = {
	Shoulder = Vector3.new(0.42, 0.85, 0.55),
	BaseYaw = 32, BackTilt = 12,
	P1 = { 0.55, 1.9 },
	P2 = { 2.5, 2.7 },
	BoneSegments = 8,
	Layers = {
		{ count = 9,  lenMul = 1.00, width = 0.52, z = 0.00, transp = 0.22 },
		{ count = 10, lenMul = 0.80, width = 0.46, z = 0.06, transp = 0.18 },
		{ count = 11, lenMul = 0.60, width = 0.38, z = 0.12, transp = 0.14 },
		{ count = 12, lenMul = 0.42, width = 0.30, z = 0.18, transp = 0.10 },
		{ count = 14, lenMul = 0.26, width = 0.22, z = 0.24, transp = 0.05 },
	},
}

-- ===== state =====
local conns, saved, savedSkies, lightFx = {}, {}, {}, {}
local lightingActive = false
local S = { char = nil, root = nil, head = nil, groundY = 0 }
local rings, wings, disc = {}, {}, nil
local orbs, rbTools = {}, {}
local charObjs, wingParts, wingCFs = {}, {}, {}
local flapPhase = 0
local ui, win, fovCircle, cross = nil, nil, nil, nil

local folder = Instance.new("Folder")
folder.Name = "ScriptikVisual"
folder.Parent = host
local espFolder = Instance.new("Folder")
espFolder.Name = "ScriptikESP"
espFolder.Parent = host
local weaponFolder = Instance.new("Folder")
weaponFolder.Name = "ScriptikWeapon"
weaponFolder.Parent = host

-- ===== helpers =====
local function newPart(size, color, transp, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transp or 0
	p.Size = size
	if shape then p.Shape = shape end
	p.Parent = folder
	return p
end

local function makeRing(n, radius, thick, color, transp, speed, tiltX, tiltZ)
	local arc = (2 * math.pi * radius / n) * 1.08
	local parts = {}
	for i = 1, n do
		parts[i] = newPart(Vector3.new(arc, thick, thick), color, transp)
	end
	table.insert(rings, { parts = parts, n = n, radius = radius, speed = speed, tx = tiltX or 0, tz = tiltZ or 0 })
end

local function updateRing(r, pivot, t)
	local base = pivot * CFrame.Angles(r.tx, 0, r.tz) * CFrame.Angles(0, t * r.speed, 0)
	for i, p in ipairs(r.parts) do
		local a = (i / r.n) * math.pi * 2
		p.CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r.radius)
	end
end

local function rot(x, y, a)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

local function bez(k, cx, cy, p2x, p2y)
	local m = 1 - k
	return 2 * m * k * cx + k * k * p2x, 2 * m * k * cy + k * k * p2y
end

local function isTeammate(p)
	return p.Team ~= nil and player.Team ~= nil and p.Team == player.Team
end

-- ===== lighting =====
local function lightingOn()
	if lightingActive then return end
	lightingActive = true
	for _, k in ipairs({ "ClockTime", "Ambient", "OutdoorAmbient", "Brightness" }) do
		saved[k] = Lighting[k]
	end
	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("Sky") then
			table.insert(savedSkies, v)
			v.Parent = nil
		end
	end
	Lighting.ClockTime = 0
	Lighting.Ambient = Color3.fromRGB(90, 30, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 50, 170)
	Lighting.Brightness = 2

	local sky = Instance.new("Sky")
	sky.StarCount = 4000
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 14
	sky.Parent = Lighting
	table.insert(lightFx, sky)

	local atm = Instance.new("Atmosphere")
	atm.Color = Color3.fromRGB(150, 60, 230)
	atm.Decay = Color3.fromRGB(90, 20, 160)
	atm.Density = 0.32
	atm.Offset = 0.2
	atm.Glare = 0
	atm.Haze = 1.6
	atm.Parent = Lighting
	table.insert(lightFx, atm)

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 1.3
	bloom.Size = 28
	bloom.Threshold = 0.85
	bloom.Parent = Lighting
	table.insert(lightFx, bloom)

	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(235, 195, 255)
	cc.Saturation = 0.2
	cc.Contrast = 0.1
	cc.Parent = Lighting
	table.insert(lightFx, cc)
end

local function lightingOff()
	if not lightingActive then return end
	lightingActive = false
	for _, o in ipairs(lightFx) do pcall(function() o:Destroy() end) end
	lightFx = {}
	for k, v in pairs(saved) do pcall(function() Lighting[k] = v end) end
	for _, s in ipairs(savedSkies) do pcall(function() s.Parent = Lighting end) end
	savedSkies = {}
end

local function setLighting()
	if CFG.Visual and CFG.Lighting then lightingOn() else lightingOff() end
end

-- ===== wings: build =====
local function buildWing(side)
	local sc = CFG.WingScale
	local D = DETAIL[CFG.WingDetail] or DETAIL[2]
	local w = { side = side, feathers = {}, bones = {}, joints = {} }

	for li, L in ipairs(WING.Layers) do
		local count = math.max(4, math.floor(L.count * D.mul + 0.5))
		for i = 1, count do
			local k = (i - 0.5 + ((li % 2 == 0) and 0.5 or 0)) / count
			local len = (1.9 + 1.9 * k ^ 0.9) * L.lenMul * sc
			local width = L.width * sc
			local mix = math.clamp(k * 0.6 + (li - 1) * 0.12, 0, 1)
			local col = MAIN:Lerp(ACCENT, mix)
			local colOuter = col:Lerp(WHITE, 0.25)

			local ft = {
				k = k, layer = li, len = len, w = width,
				z = L.z + (i % 3) * 0.008,
				a0 = math.rad(-100 + 94 * k + li * 2),
				shaft = newPart(Vector3.new(0.05, len, 0.04), ACCENT, 0),
			}
			if D.split then
				ft.vA = newPart(Vector3.new(width * 0.5, len * 0.90, 0.02), col, L.transp)
				ft.vB = newPart(Vector3.new(width * 0.5, len * 0.86, 0.02), colOuter, math.min(L.transp + 0.05, 1))
			else
				ft.vA = newPart(Vector3.new(width, len * 0.90, 0.02), col, L.transp)
			end
			if D.tips then
				local d = width * 0.7071
				ft.tip = newPart(Vector3.new(d, d, 0.02), colOuter, L.transp)
			end
			table.insert(w.feathers, ft)
		end
	end

	for i = 1, WING.BoneSegments do
		w.bones[i] = newPart(Vector3.new(0.1, 0.1, 1), ACCENT, 0)
	end
	for i = 1, 3 do
		w.joints[i] = newPart(Vector3.new(0.3 * sc, 0.3 * sc, 0.3 * sc), ACCENT, 0, Enum.PartType.Ball)
	end

	if CFG.WingSparks then
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(ACCENT, MAIN)
		e.LightEmission = 1
		e.Rate = 14
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(0.3, 1.2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = w.joints[3]
	end
	return w
end

-- ===== wings: update =====
local function updateWings(root, dt, t)
	local sc = CFG.WingScale
	local fold = math.clamp(root.AssemblyLinearVelocity.Magnitude / 40, 0, 1)
	flapPhase += dt * (CFG.FlapSpeed + fold * 3)
	local f = math.sin(flapPhase)
	local n = 0
	local bob = math.sin(t * 2) * 0.06

	local p1x, p1y = rot(WING.P1[1], WING.P1[2], -f * 0.12)
	p1x, p1y = p1x * sc, p1y * sc
	local ex, ey = rot(WING.P2[1] - WING.P1[1], WING.P2[2] - WING.P1[2], -f * 0.28)
	local p2x, p2y = p1x + ex * sc, p1y + ey * sc
	local cx, cy = 2 * p1x - 0.5 * p2x, 2 * p1y - 0.5 * p2y

	for _, w in ipairs(wings) do
		local side = w.side
		local yaw = math.rad(WING.BaseYaw + f * CFG.FlapAmount + fold * 14)
		local W = root.CFrame
			* CFrame.new(WING.Shoulder.X * side, WING.Shoulder.Y + bob, WING.Shoulder.Z)
			* CFrame.Angles(0, -side * yaw, 0)
			* CFrame.Angles(math.rad(WING.BackTilt), 0, 0)

		for _, ft in ipairs(w.feathers) do
			local k = ft.k
			local ux, vy = bez(k, cx, cy, p2x, p2y)
			local ang = ft.a0 - f * 0.28 * k + math.sin(flapPhase - k * 1.5 - ft.layer * 0.25) * 0.07 * k
			if side == -1 then ang = math.pi - ang end
			local fb = W * CFrame.new(side * ux, vy, ft.z) * CFrame.Angles(0, 0, ang - math.pi / 2)
			local L = ft.len

			n += 1
			wingParts[n] = ft.shaft
			wingCFs[n] = fb * CFrame.new(0, L / 2, 0.02)
			if ft.vB then
				local q = ft.w * 0.25
				n += 1
				wingParts[n] = ft.vA
				wingCFs[n] = fb * CFrame.new(-q, L * 0.45, 0) * CFrame.Angles(0, 0, 0.08)
				n += 1
				wingParts[n] = ft.vB
				wingCFs[n] = fb * CFrame.new(q, L * 0.43, 0.012) * CFrame.Angles(0, 0, -0.08)
			else
				n += 1
				wingParts[n] = ft.vA
				wingCFs[n] = fb * CFrame.new(0, L * 0.45, 0)
			end
			if ft.tip then
				n += 1
				wingParts[n] = ft.tip
				wingCFs[n] = fb * CFrame.new(0, L * 0.9, 0) * CFrame.Angles(0, 0, math.rad(45))
			end
		end

		local zb = 0.2
		local wa = W:PointToWorldSpace(Vector3.new(0, 0, zb))
		for i = 1, #w.bones do
			local bx, by = bez(i / #w.bones, cx, cy, p2x, p2y)
			local wb = W:PointToWorldSpace(Vector3.new(side * bx, by, zb))
			local len = (wb - wa).Magnitude + 0.02
			local bone = w.bones[i]
			bone.Size = Vector3.new(0.1, 0.1, len)
			n += 1
			wingParts[n] = bone
			wingCFs[n] = CFrame.lookAt(wa, wb) * CFrame.new(0, 0, -len / 2)
			wa = wb
		end

		local jx, jy = bez(0.5, cx, cy, p2x, p2y)
		local jpos = {
			Vector3.new(0, 0, zb),
			Vector3.new(side * jx, jy, zb),
			Vector3.new(side * p2x, p2y, zb),
		}
		for i = 1, 3 do
			n += 1
			wingParts[n] = w.joints[i]
			wingCFs[n] = CFrame.new(W:PointToWorldSpace(jpos[i]))
		end
	end

	if n > 0 then
		workspace:BulkMoveTo(wingParts, wingCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ===== spirit orbs: glowing balls with light trails orbiting the character =====
local ORB_COUNT = 5

local function buildOrbs()
	for i = 1, ORB_COUNT do
		local col = Color3.fromHSV((0.72 + (i - 1) * 0.045) % 1, 0.65, 1)
		local p = newPart(Vector3.new(0.38, 0.38, 0.38), col, 0, Enum.PartType.Ball)

		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.17, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.17, 0)
		a1.Parent = p

		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.75
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.Color = ColorSequence.new(col, ACCENT)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		tr.Parent = p

		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 6
		l.Brightness = 1.2
		l.Parent = p

		orbs[i] = {
			part = p,
			phase = (i - 1) / ORB_COUNT * math.pi * 2,
			speed = 1.0 + i * 0.13,
			dir = (i % 2 == 0) and -1 or 1,
			radius = 2.3 + i * 0.22,
			height = -0.6 + i * 0.5,
		}
	end
end

local function updateOrbs(rp, t)
	for _, o in ipairs(orbs) do
		local a = o.phase + t * o.speed * o.dir
		local r = o.radius + math.sin(t * 1.3 + o.phase) * 0.2
		local y = o.height + math.sin(t * 1.7 + o.phase * 2) * 0.35
		o.part.CFrame = CFrame.new(rp + Vector3.new(math.cos(a) * r, y, math.sin(a) * r))
	end
end

-- ===== aura build / clear =====
local function clearChar()
	for _, o in ipairs(charObjs) do pcall(function() o:Destroy() end) end
	charObjs, rings, wings, disc, orbs = {}, {}, {}, nil, {}
	wingParts, wingCFs = {}, {}
	folder:ClearAllChildren()
end

local function build()
	clearChar()
	local char, root = S.char, S.root
	if not (char and root) then return end

	if CFG.Halo then
		makeRing(28, 1.5, 0.16, ACCENT, 0, 1.6, math.rad(10), 0)
		makeRing(28, 1.9, 0.07, MAIN, 0.35, -1.1, math.rad(-8), math.rad(6))
	end
	if CFG.Rings then
		makeRing(40, 3.2, 0.14, MAIN, 0.1, 1.4)
		makeRing(48, 4.4, 0.10, ACCENT, 0.25, -1.0)
		makeRing(56, 5.6, 0.06, DEEP, 0.4, 0.7)
		disc = newPart(Vector3.new(0.1, 7, 7), DEEP, 0.6, Enum.PartType.Cylinder)
	end
	if CFG.Wings then
		table.insert(wings, buildWing(-1))
		table.insert(wings, buildWing(1))
	end
	if CFG.Orbs then buildOrbs() end
	if CFG.Particles then
		local stars = Instance.new("ParticleEmitter")
		stars.Color = ColorSequence.new(ACCENT, MAIN)
		stars.LightEmission = 1
		stars.Rate = 30
		stars.Lifetime = NumberRange.new(2, 3.5)
		stars.Speed = NumberRange.new(1, 3)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.Acceleration = Vector3.new(0, 2, 0)
		stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		stars.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		stars.Parent = root
		table.insert(charObjs, stars)

		local glow = Instance.new("ParticleEmitter")
		glow.Color = ColorSequence.new(MAIN)
		glow.LightEmission = 1
		glow.Rate = 6
		glow.Lifetime = NumberRange.new(1.5, 2.5)
		glow.Speed = NumberRange.new(0.5, 1)
		glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
		glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		glow.Parent = root
		table.insert(charObjs, glow)
	end
	if CFG.Highlight then
		local h = Instance.new("Highlight")
		h.Adornee = char
		h.FillColor = MAIN
		h.OutlineColor = ACCENT
		h.FillTransparency = 0.75
		h.OutlineTransparency = 0.15
		h.Parent = folder
	end
	if CFG.PointLight then
		local l = Instance.new("PointLight")
		l.Color = MAIN
		l.Range = 16
		l.Brightness = 3
		l.Parent = root
		table.insert(charObjs, l)
	end
end

local function rebuild()
	if CFG.Visual and S.root and S.root.Parent then build() else clearChar() end
end

local function applyVisual()
	setLighting()
	rebuild()
end

local function setupChar(char)
	S.char = char
	S.root = char:WaitForChild("HumanoidRootPart", 10)
	S.head = char:FindFirstChild("Head")
	if not S.root then return end
	S.groundY = S.root.Position.Y - 3
	rebuild()
end

local function onRebuild() safe("rebuild", rebuild) end
local function onVisual() safe("visual", applyVisual) end
local function onLighting() safe("lighting", setLighting) end

-- ===== wallhack (ESP) =====
local espObjs = {}

local function espRemove(p)
	local o = espObjs[p]
	if not o then return end
	pcall(function() o.hl:Destroy() end)
	pcall(function() o.gui:Destroy() end)
	espObjs[p] = nil
end

local function espEnsure(p, char, head)
	local o = espObjs[p]
	if o and o.char == char and o.hl.Parent then return o end
	espRemove(p)

	local hl = Instance.new("Highlight")
	hl.Adornee = char
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillColor = MAIN
	hl.OutlineColor = ACCENT
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0
	hl.Parent = espFolder

	local gui = Instance.new("BillboardGui")
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(200, 34)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.Parent = espFolder

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextSize = 13
	lbl.TextColor3 = WHITE
	lbl.TextStrokeTransparency = 0.2
	lbl.TextStrokeColor3 = DEEP
	lbl.Text = ""
	lbl.Parent = gui

	o = { char = char, hl = hl, gui = gui, label = lbl }
	espObjs[p] = o
	return o
end

local function updateESP()
	if not CFG.ESP then
		for p in pairs(espObjs) do espRemove(p) end
		return
	end
	local myRoot = S.root
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local head = char and char:FindFirstChild("Head")
			local dist = (myRoot and root) and (root.Position - myRoot.Position).Magnitude or 0
			local show = hum and root and head and hum.Health > 0
				and dist <= CFG.ESPMaxDist
				and not (CFG.ESPTeamCheck and isTeammate(p))
			if show then
				local o = espEnsure(p, char, head)
				local parts = {}
				if CFG.ESPNames then parts[#parts + 1] = p.DisplayName end
				if CFG.ESPHealth then parts[#parts + 1] = ("HP %d"):format(math.floor(hum.Health + 0.5)) end
				if CFG.ESPDistance then parts[#parts + 1] = ("%d st"):format(math.floor(dist)) end
				o.label.Text = table.concat(parts, "  |  ")
				o.label.TextColor3 = Color3.fromHSV(0.33 * math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1), 0.6, 1)
				o.gui.Enabled = #parts > 0
			else
				espRemove(p)
			end
		end
	end
end

table.insert(conns, Players.PlayerRemoving:Connect(espRemove))

-- ===== aimbot =====
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.RespectCanCollide = true

local function refPoint()
	if TOUCH then
		local vs = camera.ViewportSize
		return Vector2.new(vs.X / 2, vs.Y / 2)
	end
	return UIS:GetMouseLocation()
end

local function isVisible(char, part)
	aimParams.FilterDescendantsInstances = { S.char or player.Character or folder, char, folder, espFolder }
	local origin = camera.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, aimParams) == nil
end

local function getTarget()
	local ref = refPoint()
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and not (CFG.AimTeamCheck and isTeammate(p)) then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local part = char and (char:FindFirstChild(CFG.AimPart) or char:FindFirstChild("HumanoidRootPart"))
			if hum and part and hum.Health > 0 then
				local sp, on = camera:WorldToViewportPoint(part.Position)
				if on then
					local d = (Vector2.new(sp.X, sp.Y) - ref).Magnitude
					if d <= CFG.AimFOV and (not bestD or d < bestD) then
						if not CFG.AimWallCheck or isVisible(char, part) then
							best, bestD = part, d
						end
					end
				end
			end
		end
	end
	return best
end

local function aimStep(dt)
	if not CFG.Aim then return end
	if UIS:GetFocusedTextBox() then return end
	if CFG.AimMode == "Hold RMB" and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
	local part = getTarget()
	if not part then return end
	local cam = workspace.CurrentCamera
	local pos = cam.CFrame.Position
	if (part.Position - pos).Magnitude < 0.5 then return end
	local desired = CFrame.lookAt(pos, part.Position)
	local alpha = 1 - (1 - CFG.AimSmooth) ^ (dt * 60)
	cam.CFrame = cam.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
end

pcall(function() RunService:UnbindFromRenderStep("ScriptikAim") end)
RunService:BindToRenderStep("ScriptikAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
	safe("aim", aimStep, dt)
end)

-- ===== UI helpers =====
local C = {
	bg = Color3.fromRGB(16, 8, 30), panel = Color3.fromRGB(32, 17, 58),
	off = Color3.fromRGB(70, 45, 105), text = Color3.fromRGB(242, 228, 255),
	dim = Color3.fromRGB(175, 145, 215),
}

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 8)
	c.Parent = o
end

local function stroke(o, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = th or 1
	s.Parent = o
	return s
end

local function mkLabel(parent, text, size, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamSemibold
	l.Text = text
	l.TextSize = size or 13
	l.TextColor3 = color or C.text
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- ===== crosshair: three counter-rotating layers + pulsing core =====
local function buildCrosshair(parent)
	local rootF = Instance.new("Frame")
	rootF.Name = "ScriptikCrosshair"
	rootF.AnchorPoint = Vector2.new(0.5, 0.5)
	rootF.Position = UDim2.fromScale(0.5, 0.5)
	rootF.Size = UDim2.fromOffset(160, 160)
	rootF.BackgroundTransparency = 1
	rootF.Parent = parent
	local sc = Instance.new("UIScale")
	sc.Parent = rootF

	local X = { root = rootF, scale = sc, fills = {}, strokes = {}, layers = {} }

	local function mkLayer(name, size)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(size, size)
		f.BackgroundTransparency = 1
		f.Parent = rootF
		X.layers[name] = f
		return f
	end

	local function polar(r, deg)
		local a = math.rad(deg)
		return r * math.sin(a), -r * math.cos(a)
	end

	local function bar(par, w, h, r, deg, off, transp)
		local x, y = polar(r, deg)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, x, 0.5, y)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = deg
		f.BorderSizePixel = 0
		f.BackgroundColor3 = MAIN
		f.BackgroundTransparency = transp or 0
		f.Parent = par
		table.insert(X.fills, { f = f, off = off })
		return f
	end

	local function ringFrame(par, scale, th, off, transp, rotation)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(scale, scale)
		f.BackgroundTransparency = 1
		f.Rotation = rotation or 0
		f.Parent = par
		local s = Instance.new("UIStroke")
		s.Thickness = th
		s.Transparency = transp or 0
		s.Color = MAIN
		s.Parent = f
		table.insert(X.strokes, { s = s, off = off })
		return f
	end

	-- outer layer: thin circle and 24 ticks, slow clockwise
	local outer = mkLayer("outer", 150)
	local circ = ringFrame(outer, 0.92, 1, 0, 0.35)
	corner(circ, UDim.new(1, 0))
	for i = 0, 23 do
		local long = (i % 6 == 0)
		bar(outer, long and 2 or 1, long and 11 or 5, 69, i * 15, i / 24, long and 0 or 0.3)
	end

	-- middle layer: four blades, counter-clockwise
	local blades = mkLayer("blades", 110)
	for i = 0, 3 do
		local d = i * 90 + 45
		bar(blades, 3, 16, 38, d, i / 4)
		bar(blades, 13, 2, 28, d, i / 4 + 0.1)
	end

	-- inner layer: diamond with four pips, fast clockwise
	local inner = mkLayer("inner", 44)
	ringFrame(inner, 0.62, 1.5, 0.5, 0, 45)
	for i = 0, 3 do
		bar(inner, 2, 7, 26, i * 90, i / 4 + 0.25)
	end

	-- core: pulsing halo and a dot
	local halo = mkLayer("halo", 14)
	local hc = ringFrame(halo, 1, 1, 0.8, 0.2)
	corner(hc, UDim.new(1, 0))
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = WHITE
	dot.Parent = rootF
	corner(dot, UDim.new(1, 0))
	table.insert(X.fills, { f = dot, off = 0.9 })

	return X
end

local function buildUI()
	ui = Instance.new("ScreenGui")
	ui.Name = "ScriptikUI"
	ui.ResetOnSpawn = false
	ui.IgnoreGuiInset = true
	ui.DisplayOrder = 999
	ui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- mount first, so the user sees something even if a later step fails
	local mounted = false
	local okH, h = pcall(function() return gethui() end)
	local targets = {}
	if okH and h then table.insert(targets, h) end
	table.insert(targets, game:GetService("CoreGui"))
	table.insert(targets, player:WaitForChild("PlayerGui"))
	for _, p in ipairs(targets) do
		local ok = pcall(function() ui.Parent = p end)
		if ok and ui.Parent == p then
			mounted = true
			break
		end
	end
	if not mounted then error("could not mount ScreenGui") end

	fovCircle = Instance.new("Frame")
	fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	fovCircle.BackgroundTransparency = 1
	fovCircle.Visible = false
	corner(fovCircle, UDim.new(1, 0))
	stroke(fovCircle, ACCENT, 1.5)
	fovCircle.Parent = ui
	safe("crosshair", function() cross = buildCrosshair(ui) end)

	local FULLH = 470
	win = Instance.new("Frame")
	win.Size = UDim2.fromOffset(310, FULLH)
	win.Position = UDim2.new(0, 64, 0.5, -235)
	win.ClipsDescendants = true
	win.BackgroundColor3 = C.bg
	win.Parent = ui
	corner(win, UDim.new(0, 12))
	stroke(win, MAIN, 1.5)

	local refreshFab = function() end -- assigned when the S button is built

	local title = Instance.new("Frame")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundColor3 = DEEP
	title.Parent = win
	corner(title, UDim.new(0, 12))
	local titleLbl = mkLabel(title, "SCRIPTIK  •  Angel Aura", 14, WHITE)
	titleLbl.Position = UDim2.fromOffset(12, 0)
	titleLbl.Size = UDim2.new(1, -90, 1, 0)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(28, 24)
	closeBtn.Position = UDim2.new(1, -34, 0.5, -12)
	closeBtn.BackgroundColor3 = C.panel
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 13
	closeBtn.TextColor3 = WHITE
	closeBtn.Parent = title
	corner(closeBtn, UDim.new(0, 6))
	closeBtn.MouseButton1Click:Connect(function()
		win.Visible = false
		refreshFab()
	end)

	-- minimize: collapse the window to just its title bar
	local minBtn = Instance.new("TextButton")
	minBtn.Size = UDim2.fromOffset(28, 24)
	minBtn.Position = UDim2.new(1, -66, 0.5, -12)
	minBtn.BackgroundColor3 = C.panel
	minBtn.Text = "-"
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 15
	minBtn.TextColor3 = WHITE
	minBtn.Parent = title
	corner(minBtn, UDim.new(0, 6))
	local collapsed = false
	minBtn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		win.Size = UDim2.fromOffset(310, collapsed and 36 or FULLH)
		minBtn.Text = collapsed and "+" or "-"
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(0, 40)
	scroll.Size = UDim2.new(1, 0, 1, -76)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = MAIN
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = win
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = scroll
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = scroll

	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local function header(text)
		local l = mkLabel(scroll, text, 12, C.dim)
		l.Size = UDim2.new(1, -20, 0, 20)
		l.LayoutOrder = nextOrder()
	end

	local function toggle(text, key, onChange)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -12, 0, 30)
		b.BackgroundColor3 = C.panel
		b.Text = ""
		b.AutoButtonColor = false
		b.LayoutOrder = nextOrder()
		b.Parent = scroll
		corner(b, UDim.new(0, 6))
		local l = mkLabel(b, text, 13, C.text)
		l.Position = UDim2.fromOffset(10, 0)
		l.Size = UDim2.new(1, -60, 1, 0)
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromOffset(34, 16)
		pill.Position = UDim2.new(1, -44, 0.5, -8)
		pill.Parent = b
		corner(pill, UDim.new(1, 0))
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BackgroundColor3 = WHITE
		dot.Parent = pill
		corner(dot, UDim.new(1, 0))
		local function refresh()
			pill.BackgroundColor3 = CFG[key] and MAIN or C.off
			dot.Position = CFG[key] and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
		end
		b.MouseButton1Click:Connect(function()
			CFG[key] = not CFG[key]
			refresh()
			if onChange then onChange() end
		end)
		refresh()
	end

	local function cycle(text, key, options, fmt, onChange)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -12, 0, 30)
		b.BackgroundColor3 = C.panel
		b.AutoButtonColor = true
		b.Font = Enum.Font.GothamSemibold
		b.TextSize = 13
		b.TextColor3 = C.text
		b.LayoutOrder = nextOrder()
		b.Parent = scroll
		corner(b, UDim.new(0, 6))
		local function refresh()
			b.Text = text .. ": " .. (fmt and fmt(CFG[key]) or tostring(CFG[key]))
		end
		b.MouseButton1Click:Connect(function()
			local idx = table.find(options, CFG[key]) or 0
			CFG[key] = options[idx % #options + 1]
			refresh()
			if onChange then onChange() end
		end)
		refresh()
	end

	local function slider(text, min, max, step, key, fmt)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -12, 0, 46)
		holder.BackgroundColor3 = C.panel
		holder.LayoutOrder = nextOrder()
		holder.Parent = scroll
		corner(holder, UDim.new(0, 6))
		local lbl = mkLabel(holder, "", 13, C.text)
		lbl.Position = UDim2.fromOffset(10, 4)
		lbl.Size = UDim2.new(1, -20, 0, 16)
		local track = Instance.new("Frame")
		track.Position = UDim2.new(0, 10, 0, 30)
		track.Size = UDim2.new(1, -20, 0, 8)
		track.BackgroundColor3 = C.off
		track.Parent = holder
		corner(track, UDim.new(1, 0))
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = MAIN
		fill.Parent = track
		corner(fill, UDim.new(1, 0))
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Position = UDim2.fromOffset(0, 16)
		hit.Size = UDim2.new(1, 0, 0, 30)
		hit.Parent = holder

		local function refresh()
			fill.Size = UDim2.fromScale(math.clamp((CFG[key] - min) / (max - min), 0, 1), 1)
			lbl.Text = text .. ": " .. (fmt and fmt(CFG[key]) or tostring(CFG[key]))
		end
		local dragging = false
		local function setFromX(x)
			local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			local v = math.floor((min + rel * (max - min)) / step + 0.5) * step
			CFG[key] = math.clamp(v, min, max)
			refresh()
		end
		hit.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				scroll.ScrollingEnabled = false
				setFromX(i.Position.X)
			end
		end)
		table.insert(conns, UIS.InputChanged:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
				setFromX(i.Position.X)
			end
		end))
		table.insert(conns, UIS.InputEnded:Connect(function(i)
			if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
				dragging = false
				scroll.ScrollingEnabled = true
			end
		end))
		refresh()
	end

	-- menu content
	header("VISUAL")
	toggle("Visual (master)", "Visual", onVisual)
	toggle("Purple sky & lighting", "Lighting", onLighting)
	toggle("Halo", "Halo", onRebuild)
	toggle("Wings", "Wings", onRebuild)
	toggle("Ground rings", "Rings", onRebuild)
	toggle("Particles", "Particles", onRebuild)
	toggle("Glow outline", "Highlight", onRebuild)
	toggle("Spirit orbs", "Orbs", onRebuild)
	cycle("Wing detail", "WingDetail", { 1, 2, 3 }, function(v) return DETAIL_NAMES[v] end, onRebuild)

	header("CROSSHAIR")
	toggle("Crosshair", "Crosshair")
	toggle("Rainbow crosshair", "CrosshairRainbow")
	slider("Crosshair size", 0.5, 2, 0.05, "CrosshairSize", function(v) return ("%.2fx"):format(v) end)
	slider("Spin speed", 0, 3, 0.1, "CrosshairSpeed", function(v) return ("%.1fx"):format(v) end)

	header("WEAPON")
	toggle("Rainbow weapon", "RainbowWeapon")
	slider("Rainbow speed", 0.2, 3, 0.1, "RainbowSpeed", function(v) return ("%.1fx"):format(v) end)

	header("WALLHACK (ESP)")
	toggle("Wallhack", "ESP")
	toggle("Names", "ESPNames")
	toggle("Health", "ESPHealth")
	toggle("Distance", "ESPDistance")
	toggle("Team check", "ESPTeamCheck")
	slider("Max distance", 100, 3000, 50, "ESPMaxDist", function(v) return v .. " st" end)

	header("AIMBOT")
	toggle("Aimbot", "Aim")
	cycle("Activation", "AimMode", { "Hold RMB", "Always" })
	cycle("Target", "AimPart", { "Head", "HumanoidRootPart" }, function(v) return v == "Head" and "Head" or "Body" end)
	slider("FOV radius", 30, 500, 5, "AimFOV", function(v) return v .. " px" end)
	slider("Smoothness", 0.05, 1, 0.05, "AimSmooth", function(v) return ("%.2f"):format(v) end)
	toggle("Wall check", "AimWallCheck")
	toggle("Team check", "AimTeamCheck")
	toggle("Show FOV circle", "AimShowFOV")

	if not TOUCH then
		header("INTERFACE")
		toggle("Hide S button (RShift = menu)", "HideFab", function() refreshFab() end)
	end

	-- footer
	local tgBtn = Instance.new("TextButton")
	tgBtn.Position = UDim2.new(0, 8, 1, -32)
	tgBtn.Size = UDim2.new(1, -16, 0, 26)
	tgBtn.BackgroundColor3 = DEEP
	tgBtn.Font = Enum.Font.GothamSemibold
	tgBtn.TextSize = 12
	tgBtn.TextColor3 = WHITE
	tgBtn.Text = "Telegram: " .. TG_HANDLE .. "  (tap to copy)"
	tgBtn.Parent = win
	corner(tgBtn, UDim.new(0, 6))
	tgBtn.MouseButton1Click:Connect(function()
		pcall(function() setclipboard(TG_LINK) end)
		tgBtn.Text = "Link copied!"
		task.delay(1.5, function()
			if tgBtn.Parent then tgBtn.Text = "Telegram: " .. TG_HANDLE .. "  (tap to copy)" end
		end)
	end)

	-- window drag
	local dragging, dragStart, startPos = false, nil, nil
	title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos = win.Position
		end
	end)
	table.insert(conns, UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(conns, UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- floating open button: small, faint while the menu is closed, draggable
	local fab = Instance.new("TextButton")
	fab.Size = UDim2.fromOffset(30, 30)
	fab.Position = UDim2.new(0, 8, 0.5, -15)
	fab.BackgroundColor3 = DEEP
	fab.Text = "S"
	fab.Font = Enum.Font.GothamBold
	fab.TextSize = 15
	fab.TextColor3 = ACCENT
	fab.AutoButtonColor = false
	fab.Parent = ui
	corner(fab, UDim.new(1, 0))
	local fabStroke = stroke(fab, MAIN, 1.2)

	local fabHover = false
	refreshFab = function()
		fab.Visible = not CFG.HideFab
		local faint = (not win.Visible) and not fabHover
		fab.BackgroundTransparency = faint and 0.7 or 0.1
		fab.TextTransparency = faint and 0.55 or 0
		fabStroke.Transparency = faint and 0.7 or 0
	end
	if not TOUCH then
		fab.MouseEnter:Connect(function() fabHover = true; refreshFab() end)
		fab.MouseLeave:Connect(function() fabHover = false; refreshFab() end)
	end

	local fDrag, fMoved, fStart, fPos = false, false, nil, nil
	fab.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			fDrag, fMoved, fStart, fPos = true, false, i.Position, fab.Position
		end
	end)
	table.insert(conns, UIS.InputChanged:Connect(function(i)
		if fDrag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - fStart
			if d.Magnitude > 6 then fMoved = true end
			if fMoved then
				fab.Position = UDim2.new(fPos.X.Scale, fPos.X.Offset + d.X, fPos.Y.Scale, fPos.Y.Offset + d.Y)
			end
		end
	end))
	table.insert(conns, UIS.InputEnded:Connect(function(i)
		if fDrag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			fDrag = false
			if not fMoved then
				win.Visible = not win.Visible
				refreshFab()
			end
		end
	end))
	table.insert(conns, UIS.InputBegan:Connect(function(i, gpe)
		if not gpe and i.KeyCode == CFG.MenuKey then
			win.Visible = not win.Visible
			refreshFab()
		end
	end))
	refreshFab()

	-- intro preview (English)
	local cg = Instance.new("CanvasGroup")
	cg.AnchorPoint = Vector2.new(0.5, 0.5)
	cg.Position = UDim2.fromScale(0.5, 0.3)
	cg.Size = UDim2.fromOffset(340, 170)
	cg.BackgroundColor3 = C.bg
	cg.ZIndex = 50
	cg.Parent = ui
	corner(cg, UDim.new(0, 14))
	stroke(cg, MAIN, 2)

	local t1 = mkLabel(cg, "SCRIPTIK", 36, ACCENT, Enum.TextXAlignment.Center)
	t1.Font = Enum.Font.GothamBlack
	t1.Position = UDim2.fromOffset(0, 14)
	t1.Size = UDim2.new(1, 0, 0, 44)
	local t2 = mkLabel(cg, "Angel Aura  •  Wallhack  •  Aimbot", 14, C.text, Enum.TextXAlignment.Center)
	t2.Position = UDim2.fromOffset(0, 62)
	t2.Size = UDim2.new(1, 0, 0, 20)
	local t3 = mkLabel(cg, "Telegram: " .. TG_HANDLE, 16, WHITE, Enum.TextXAlignment.Center)
	t3.Font = Enum.Font.GothamBold
	t3.Position = UDim2.fromOffset(0, 90)
	t3.Size = UDim2.new(1, 0, 0, 22)
	local t4 = mkLabel(cg, "Open the menu with the S button or RightShift", 11, C.dim, Enum.TextXAlignment.Center)
	t4.Position = UDim2.fromOffset(0, 114)
	t4.Size = UDim2.new(1, 0, 0, 16)

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 20, 1, -22)
	bar.Size = UDim2.new(1, -40, 0, 6)
	bar.BackgroundColor3 = C.off
	bar.Parent = cg
	corner(bar, UDim.new(1, 0))
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = MAIN
	barFill.Parent = bar
	corner(barFill, UDim.new(1, 0))

	task.spawn(function()
		pcall(function()
			TweenService:Create(barFill, TweenInfo.new(3.2, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
			task.wait(3.6)
			local tw = TweenService:Create(cg, TweenInfo.new(0.6), { GroupTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
		end)
		pcall(function() cg:Destroy() end)
	end)
end

-- ===== per-frame work =====
local t0 = os.clock()
local espAccum = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ===== crosshair animation =====
local function crossColor(t, off)
	if CFG.CrosshairRainbow then
		return Color3.fromHSV((t * 0.2 + off) % 1, 0.85, 1)
	end
	return MAIN:Lerp(ACCENT, 0.5 + 0.5 * math.sin(t * 2 + off * math.pi * 2))
end

local function updateCrosshair()
	if not cross then return end
	cross.root.Visible = CFG.Crosshair
	if not CFG.Crosshair then return end
	local t = os.clock() - t0
	local sp = CFG.CrosshairSpeed
	cross.scale.Scale = CFG.CrosshairSize
	cross.layers.outer.Rotation = (t * 20 * sp) % 360
	cross.layers.blades.Rotation = (-t * 60 * sp) % 360
	cross.layers.inner.Rotation = (t * 110 * sp) % 360
	local pulse = 1 + math.sin(t * 3) * 0.1
	cross.layers.halo.Size = UDim2.fromOffset(14 * pulse, 14 * pulse)
	for _, it in ipairs(cross.fills) do
		it.f.BackgroundColor3 = crossColor(t, it.off)
	end
	for _, it in ipairs(cross.strokes) do
		it.s.Color = crossColor(t, it.off)
	end
end

-- ===== rainbow weapon (local visual only, original colors are restored) =====
local function rbRelease(tool)
	local o = rbTools[tool]
	if not o then return end
	rbTools[tool] = nil
	for part, orig in pairs(o.parts) do
		pcall(function()
			part.Color = orig.c
			part.Material = orig.m
		end)
	end
	if o.hl then pcall(function() o.hl:Destroy() end) end
	if o.conn then pcall(function() o.conn:Disconnect() end) end
end

local function rbTrack(o, d)
	if d:IsA("BasePart") and not o.parts[d] then
		o.parts[d] = { c = d.Color, m = d.Material }
		o.n += 1
		o.off[d] = (o.n * 0.07) % 1
		d.Material = Enum.Material.Neon
	end
end

local function rbApply(tool)
	if rbTools[tool] then return end
	local o = { parts = {}, off = {}, n = 0 }
	rbTools[tool] = o
	for _, d in ipairs(tool:GetDescendants()) do rbTrack(o, d) end
	o.conn = tool.DescendantAdded:Connect(function(d) rbTrack(o, d) end)
	local hl = Instance.new("Highlight")
	hl.Adornee = tool
	hl.FillTransparency = 0.45
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = weaponFolder
	o.hl = hl
end

local function updateWeapon()
	if not CFG.RainbowWeapon then
		for tool in pairs(rbTools) do rbRelease(tool) end
		return
	end
	local char = S.char
	if char and char.Parent then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") then rbApply(c) end
		end
	end
	local t = (os.clock() - t0) * 0.3 * CFG.RainbowSpeed
	for tool, o in pairs(rbTools) do
		if tool.Parent ~= char then
			rbRelease(tool)
		else
			for part, off in pairs(o.off) do
				part.Color = Color3.fromHSV((t + off) % 1, 0.85, 1)
			end
			o.hl.FillColor = Color3.fromHSV(t % 1, 0.9, 1)
			o.hl.OutlineColor = Color3.fromHSV((t + 0.5) % 1, 0.9, 1)
		end
	end
end

local function updateHud()
	if not fovCircle then return end
	local show = CFG.Aim and CFG.AimShowFOV
	fovCircle.Visible = show
	if show then
		local ref = refPoint()
		fovCircle.Position = UDim2.fromOffset(ref.X, ref.Y)
		fovCircle.Size = UDim2.fromOffset(CFG.AimFOV * 2, CFG.AimFOV * 2)
	end
end

local function updateAura(dt)
	local root = S.root
	if not CFG.Visual or not root or not root.Parent then return end
	local t = os.clock() - t0
	local rp = root.Position

	rayParams.FilterDescendantsInstances = { S.char or folder, folder, espFolder }
	local hit = workspace:Raycast(rp, Vector3.new(0, -14, 0), rayParams)
	local targetY = hit and (hit.Position.Y + 0.05) or (rp.Y - 3)
	S.groundY = S.groundY + (targetY - S.groundY) * math.min(1, dt * 15)

	local headPos = (S.head and S.head.Position or rp + Vector3.new(0, 1.5, 0)) + Vector3.new(0, 1.4 + math.sin(t * 2) * 0.12, 0)
	local haloPivot = CFrame.new(headPos)
	local groundPivot = CFrame.new(rp.X, S.groundY, rp.Z)
	local idx = 0
	for _, r in ipairs(rings) do
		idx += 1
		if CFG.Halo and idx <= 2 then
			updateRing(r, haloPivot, t)
		else
			updateRing(r, groundPivot, t)
		end
	end

	if disc then
		local pulse = 7 + math.sin(t * 2.5) * 0.6
		disc.Size = Vector3.new(0.1, pulse, pulse)
		disc.Transparency = 0.6 + math.sin(t * 2.5) * 0.12
		disc.CFrame = CFrame.new(rp.X, S.groundY + 0.02, rp.Z) * CFrame.Angles(0, 0, math.rad(90))
	end

	if #orbs > 0 then updateOrbs(rp, t) end
	if #wings > 0 then updateWings(root, dt, t) end
end

table.insert(conns, RunService.RenderStepped:Connect(function(dt)
	camera = workspace.CurrentCamera or camera
	safe("hud", updateHud)
	safe("crosshair", updateCrosshair)
	safe("weapon", updateWeapon)
	espAccum += dt
	if espAccum >= 0.1 then
		espAccum = 0
		safe("esp", updateESP)
	end
	safe("aura", updateAura, dt)
end))

table.insert(conns, player.CharacterAdded:Connect(function(c)
	task.spawn(safe, "character", setupChar, c)
end))

-- ===== cleanup =====
_G.ScriptikCleanup = function()
	pcall(function() RunService:UnbindFromRenderStep("ScriptikAim") end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	for p in pairs(espObjs) do espRemove(p) end
	for tool in pairs(rbTools) do pcall(rbRelease, tool) end
	pcall(clearChar)
	pcall(function() folder:Destroy() end)
	pcall(function() espFolder:Destroy() end)
	pcall(function() weaponFolder:Destroy() end)
	if ui then pcall(function() ui:Destroy() end) end
	pcall(lightingOff)
	_G.ScriptikCleanup = nil
end

-- ===== start =====
safe("ui", buildUI)
safe("lighting", setLighting)
if player.Character then
	task.spawn(safe, "character", setupChar, player.Character)
end
safe("notify", function()
	StarterGui:SetCore("SendNotification", {
		Title = "SCRIPTIK",
		Text = "Loaded  |  Telegram: " .. TG_HANDLE,
		Duration = 6,
	})
end)
print("[Scriptik] v2.2 loaded | " .. TG_HANDLE)
