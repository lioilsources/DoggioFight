--!native
--!optimize 2
-- DoggioWars Roblox prototyp -- letovy model (klient)
-- Port jadra z vehicle.lua (Luanti): mouse-flight, zamerovac vede a letadlo
-- se za nim dotaci. Kinematicky let pres CFrame, zadna fyzika enginu --
-- stejny pristup jako serverova entita v Luanti (set_velocity kazdy step).
--
-- Ovladani: mys = zamerovac | W/S plyn | A/D vyboceni | Space/Shift nos
-- S+A/D drift | LMB strelba (nici teren) | RMB boost | V kamera | R respawn

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local Terrain = workspace.Terrain

-- Konstanty 1:1 z doggiowars.const (m/s, rad/s); SCALE prevadi metry na study
local SCALE      = 3
local SPEED_MAX  = 40
local SPEED_MIN  = 5
local TURN_SPEED = 1.5
local PITCH_RATE = 1.2
local PITCH_MAX  = 0.6
local ROLL_SPEED = 1.8
local BANK_MAX   = math.pi * 0.7    -- ROLL_MAX * 0.7, auto-naklon v zatacce
local LOOK_CLAMP = 1.25
local MOUSE_SENS = 0.0022
local SPAWN_POS  = Vector3.new(0, 1400, -150)

-- Stav letu (nazvy dle vehicle.lua)
local aimYaw, aimPitch = 0, -0.15  -- look_h/look_v: kam miri zamerovac
                                   -- (start mirne dolu, at je videt ostrov)
local yaw, pitch, roll = 0, 0, 0   -- skutecna orientace letadla
local speed = 15                   -- m/s; DRZI tam, kam ji hrac nastavi
local boostMeter, boostTime = 50, 0
local score, hp = 0, 100          -- SCORE prezije respawn (jako Luanti)
local hudTimer, radarTimer = 0, 0
local radarOn = true
local pos = SPAWN_POS
local proxTimer = 0
local shootCooldown, crashCooldown = 0, 0
local flashTime, msgTimeLeft = 0, 0
local firstPerson = false

local function wrapAngle(a)
	while a > math.pi do a = a - 2 * math.pi end
	while a < -math.pi do a = a + 2 * math.pi end
	return a
end

local function resetFlight()
	pos = SPAWN_POS
	aimYaw, aimPitch = 0, -0.15
	yaw, pitch, roll = 0, 0, 0
	speed = 15
	boostMeter, boostTime = 50, 0
	hp = 100
end

---------------------------------------------------------------------------
-- Model letadla z Partu (nahrada za doggiowars_fighter_01.obj; dopredu = -Z)
---------------------------------------------------------------------------

local RED   = Color3.fromRGB(200, 60, 50)
local WHITE = Color3.fromRGB(235, 230, 220)
local DARK  = Color3.fromRGB(45, 45, 58)

local plane = Instance.new("Model")
plane.Name = "DoggioFighter"

local function makePart(size, cf, color, material)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = plane
	return part
end

local hull = makePart(Vector3.new(3, 2.4, 12), CFrame.new(0, 0, 0), RED)
makePart(Vector3.new(1.6, 1.2, 3.4), CFrame.new(0, 1.6, 0.6), DARK, Enum.Material.Glass)
makePart(Vector3.new(16, 0.5, 4), CFrame.new(0, 0.4, -0.5), WHITE)
makePart(Vector3.new(6, 0.4, 2.2), CFrame.new(0, 0.6, 5.2), WHITE)
makePart(Vector3.new(0.4, 2.6, 2.4), CFrame.new(0, 1.6, 5.4), RED)
makePart(Vector3.new(1.4, 1.4, 1.2), CFrame.new(0, 0, -6.4), DARK)
plane.PrimaryPart = hull
plane.Parent = workspace

local exhaustAtt = Instance.new("Attachment")
exhaustAtt.Position = Vector3.new(0, 0, 6.2)
exhaustAtt.Parent = hull
local exhaust = Instance.new("ParticleEmitter")
exhaust.Texture = "rbxasset://textures/particles/smoke_main.dds"
exhaust.Lifetime = NumberRange.new(0.3, 0.7)
exhaust.Speed = NumberRange.new(8, 16)
exhaust.Size = NumberSequence.new(1.2, 2.6)
exhaust.Transparency = NumberSequence.new(0.4, 1)
exhaust.Acceleration = Vector3.new(0, -2, 0)
exhaust.Color = ColorSequence.new(
	Color3.fromRGB(255, 190, 120), Color3.fromRGB(120, 120, 130))
exhaust.Parent = exhaustAtt

---------------------------------------------------------------------------
-- Postava: neviditelna, ukotvena, leti s letadlem (drzi streaming/replikaci)
---------------------------------------------------------------------------

local charRoot = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRayFilter()
	local list = {plane}
	if player.Character then
		table.insert(list, player.Character)
	end
	rayParams.FilterDescendantsInstances = list
end

local function hidePart(d)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = 1
		d.CanCollide = false
	end
end

local function adoptCharacter(char)
	local root = char:WaitForChild("HumanoidRootPart")
	local humanoid = char:WaitForChild("Humanoid")
	root.Anchored = true
	humanoid.PlatformStand = true
	for _, d in ipairs(char:GetDescendants()) do
		hidePart(d)
	end
	char.DescendantAdded:Connect(hidePart)
	charRoot = root
	refreshRayFilter()
end

player.CharacterAdded:Connect(adoptCharacter)
if player.Character then
	adoptCharacter(player.Character)
end
refreshRayFilter()

---------------------------------------------------------------------------
-- HUD (nahrada hud.lua): zamerovac, rychlost, boost bar, hlasky
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DoggioHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function newFrame(size, position, color, transparency)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = gui
	return f
end

local function newLabel(size, position, textSize)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Code
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	l.Parent = gui
	return l
end

local dot = newFrame(UDim2.fromOffset(5, 5), UDim2.fromScale(0.5, 0.5),
	Color3.new(1, 1, 1))
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot

local ring = newFrame(UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5),
	Color3.new(1, 1, 1), 1)
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.new(1, 1, 1)
ringStroke.Thickness = 1.5
ringStroke.Transparency = 0.35
ringStroke.Parent = ring

-- Levy sloupec dle hud.lua: SPD/ALT/VS (0.94), hull (0.88), boost (0.84)
local speedLabel = newLabel(UDim2.fromOffset(380, 24), UDim2.fromScale(0.02, 0.94), 20)
speedLabel.AnchorPoint = Vector2.new(0, 0.5)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.TextColor3 = Color3.fromRGB(159, 216, 255)

local function newBar(yScale, color)
	local bg = newFrame(UDim2.fromOffset(200, 10), UDim2.fromScale(0.02, yScale),
		Color3.fromRGB(20, 25, 35), 0.35)
	bg.AnchorPoint = Vector2.new(0, 0.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bg
	return fill
end
local hullFill = newBar(0.88, Color3.fromRGB(255, 80, 64))
local boostFill = newBar(0.84, Color3.fromRGB(255, 215, 94))

-- SCORE vlevo nahore (0.02/0.06), zlata
-- Luanti ma 0.02/0.06; tady niz -- horni roh zabira nevypnutelny topbar
local scoreLabel = newLabel(UDim2.fromOffset(300, 24), UDim2.fromScale(0.02, 0.105), 20)
scoreLabel.AnchorPoint = Vector2.new(0, 0.5)
scoreLabel.TextXAlignment = Enum.TextXAlignment.Left
scoreLabel.TextColor3 = Color3.fromRGB(255, 215, 94)
scoreLabel.Text = "SCORE 0"

-- Kompasova paska (0.5/0.02, mono) + kurz ve stupnich pod ni
local compassLabel = newLabel(UDim2.fromOffset(720, 22), UDim2.fromScale(0.5, 0.03), 18)
local headingLabel = newLabel(UDim2.fromOffset(120, 18), UDim2.fromScale(0.5, 0.065), 15)
headingLabel.TextColor3 = Color3.fromRGB(159, 216, 255)

-- Podelny sklon + naklon textem (0.5/0.92)
local bankLabel = newLabel(UDim2.fromOffset(420, 18), UDim2.fromScale(0.5, 0.92), 14)

-- Vodovaha (att_* z hud.lua): cara se klopi SPOLU se strojem, stoupani
-- ji zveda nad pevny kruh. Roblox ma Rotation, netreba skladat z dilku --
-- dva zelene segmenty s mezerou v rotujicim ramu + pevna reference.
local attBox = newFrame(UDim2.fromOffset(188, 76), UDim2.new(1, -110, 0.38, 0),
	Color3.new(0, 0, 0), 1)
local attLine = Instance.new("Frame")
attLine.AnchorPoint = Vector2.new(0.5, 0.5)
attLine.Size = UDim2.fromOffset(176, 12)
attLine.Position = UDim2.fromScale(0.5, 0.5)
attLine.BackgroundTransparency = 1
attLine.Parent = attBox
for _, x0 in ipairs({0, 110}) do
	local seg = Instance.new("Frame")
	seg.Size = UDim2.fromOffset(66, 4)
	seg.Position = UDim2.new(0, x0, 0.5, -2)
	seg.BackgroundColor3 = Color3.fromRGB(143, 227, 160)
	seg.BorderSizePixel = 0
	seg.Parent = attLine
end
local attRef = Instance.new("Frame")
attRef.AnchorPoint = Vector2.new(0.5, 0.5)
attRef.Size = UDim2.fromOffset(18, 18)
attRef.Position = UDim2.fromScale(0.5, 0.5)
attRef.BackgroundTransparency = 1
attRef.Parent = attBox
local attRefStroke = Instance.new("UIStroke")
attRefStroke.Color = Color3.new(1, 1, 1)
attRefStroke.Thickness = 2
attRefStroke.Parent = attRef
local attRefCorner = Instance.new("UICorner")
attRefCorner.CornerRadius = UDim.new(1, 0)
attRefCorner.Parent = attRef

-- Radar (Luanti minimapa vpravo nahore, prepina M misto /radar)
local RADAR_PX = 220
local RADAR_RANGE = 512   -- m, jako minimap size 512
local radarBox = newFrame(UDim2.fromOffset(RADAR_PX, RADAR_PX),
	UDim2.new(1, -(RADAR_PX / 2 + 10), 0, RADAR_PX / 2 + 10),
	Color3.fromRGB(10, 16, 26), 0.4)
local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(1, 0)
radarCorner.Parent = radarBox
local radarStroke = Instance.new("UIStroke")
radarStroke.Color = Color3.new(1, 1, 1)
radarStroke.Transparency = 0.5
radarStroke.Parent = radarBox
local radarDots = {}
for i = 1, 30 do
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.BackgroundColor3 = Color3.new(1, 1, 1)
	d.BorderSizePixel = 0
	d.Visible = false
	d.Parent = radarBox
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = d
	radarDots[i] = d
end
local radarArrow = Instance.new("TextLabel")
radarArrow.AnchorPoint = Vector2.new(0.5, 0.5)
radarArrow.Position = UDim2.fromScale(0.5, 0.5)
radarArrow.Size = UDim2.fromOffset(20, 20)
radarArrow.BackgroundTransparency = 1
radarArrow.Font = Enum.Font.Code
radarArrow.TextSize = 16
radarArrow.TextColor3 = Color3.new(1, 1, 1)
radarArrow.Text = "▲"
radarArrow.ZIndex = 3
radarArrow.Parent = radarBox
local northLabel = Instance.new("TextLabel")
northLabel.AnchorPoint = Vector2.new(0.5, 0)
northLabel.Position = UDim2.new(0.5, 0, 0, 4)
northLabel.Size = UDim2.fromOffset(16, 14)
northLabel.BackgroundTransparency = 1
northLabel.Font = Enum.Font.Code
northLabel.TextSize = 13
northLabel.TextColor3 = Color3.new(1, 1, 1)
northLabel.TextTransparency = 0.3
northLabel.Text = "N"
northLabel.Parent = radarBox

local hint = newLabel(UDim2.fromScale(0.9, 0.03), UDim2.fromScale(0.5, 0.965), 14)
hint.TextTransparency = 0.25
hint.Text = "mys zamerovac | W/S plyn | A/D vyboceni | Space/Shift nos"
	.. " | S+A/D drift | LMB strelba | RMB boost | V kamera | M radar | R respawn"

-- flash (Luanti hud.flash): velky zlaty text na 0.5/0.35, mizi po 1.2 s
local msgLabel = newLabel(UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.5, 0.35), 32)
msgLabel.TextColor3 = Color3.fromRGB(255, 215, 94)
msgLabel.Text = ""

-- stav mapgenu ze serveru (workspace atribut Mapgen) -- diagnostika
local mapgenLabel = newLabel(UDim2.fromScale(0.45, 0.025), UDim2.fromScale(0.02, 0.99), 12)
mapgenLabel.AnchorPoint = Vector2.new(0, 0.5)
mapgenLabel.TextXAlignment = Enum.TextXAlignment.Left
mapgenLabel.TextTransparency = 0.3
mapgenLabel.Text = "mapgen: cekam na server..."

local flash = newFrame(UDim2.fromScale(1.2, 1.2), UDim2.fromScale(0.5, 0.5),
	Color3.fromRGB(255, 60, 40), 1)
flash.ZIndex = 5

local function showMsg(text)
	msgLabel.Text = text
	msgTimeLeft = 1.2
end

-- Nativni Roblox UI pryc (chat, playerlist...) -- HUD je cely vlastni
task.spawn(function()
	local sg = game:GetService("StarterGui")
	for _ = 1, 10 do
		if pcall(function()
			sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end) then
			break
		end
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------------
-- Kompasova paska (port compass_tape) + radar: ostrovy si klient spocita
-- ze stejneho deterministickeho LCG jako server (SEED musi sedet!)
---------------------------------------------------------------------------

local CARDINALS = {
	[0] = "N", [45] = "NE", [90] = "E", [135] = "SE",
	[180] = "S", [225] = "SW", [270] = "W", [315] = "NW",
}

local function compassTape(heading)
	local base = math.floor(heading / 15 + 0.5) * 15
	local parts = {}
	for off = -60, 60, 15 do
		local a = (base + off) % 360
		local label = CARDINALS[a] or "·"
		if #label == 1 then
			label = label .. " "
		end
		if off == 0 then
			label = "[" .. label .. "]"
		else
			label = " " .. label .. " "
		end
		parts[#parts + 1] = label
	end
	return table.concat(parts)
end

local MAPGEN_SEED = 7
local ISLAND_GRID = 340

local function hash_2d(cx, cz, seed)
	local h = cx * 73856093 + cz * 19349663 + seed
	h = math.abs(h)
	return (h * 1103515245 + 12345) % 2147483648
end

local function nexth(h)
	return (h * 1103515245 + 12345) % 2147483648
end

local function unit(h)
	return math.floor(h / 32768) / 65536
end

local BIOME_DOTS = {
	[0] = Color3.fromRGB(76, 175, 80),    -- verdant
	[1] = Color3.fromRGB(232, 244, 255),  -- glacial
	[2] = Color3.fromRGB(178, 70, 50),    -- volcanic
	[3] = Color3.fromRGB(232, 216, 160),  -- atoll
	[4] = Color3.fromRGB(156, 107, 181),  -- mycelial
	[5] = Color3.fromRGB(138, 138, 138),  -- barren
	[6] = Color3.fromRGB(46, 125, 50),    -- jungle
	[7] = Color3.fromRGB(217, 192, 122),  -- desert
	[8] = Color3.fromRGB(159, 232, 255),  -- crystal
	[9] = Color3.fromRGB(92, 92, 92),     -- ashen
	[10] = Color3.fromRGB(168, 160, 85),  -- savanna
	[11] = Color3.fromRGB(107, 122, 79),  -- swamp
}

-- zkracene island_for_cell: jen pozice/polomer/biom (stejne poradi tahu!)
local function islandForCell(cx, cz)
	if cx == 0 and cz == 0 then
		local hb = nexth(hash_2d(777, 333, MAPGEN_SEED))
		return 0, 0, 190, math.floor(unit(hb) * 12)
	end
	local h = hash_2d(cx, cz, MAPGEN_SEED)
	if unit(h) * 100 >= 82 then
		return nil
	end
	h = nexth(h)
	local radius = math.floor(72 + unit(h) ^ 1.2 * 93)
	h = nexth(h)
	local biome = math.floor(unit(h) * 12)
	h = nexth(h)
	local pad = math.min(radius, 166)
	local span = math.max(1, ISLAND_GRID - 2 * radius)
	local ox = cx * ISLAND_GRID + pad + math.floor(unit(h) * span)
	h = nexth(h)
	local oz = cz * ISLAND_GRID + pad + math.floor(unit(h) * span)
	return ox, oz, radius, biome
end

---------------------------------------------------------------------------
-- Strelba: paprsek podle zamerovace, zasah nici teren (FillBall vzduchem)
---------------------------------------------------------------------------

local function boomAt(p)
	local fx = Instance.new("Part")
	fx.Anchored = true
	fx.CanCollide = false
	fx.Transparency = 1
	fx.Size = Vector3.new(1, 1, 1)
	fx.CFrame = CFrame.new(p)
	fx.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = fx
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/fire_main.dds"
	pe.Speed = NumberRange.new(20, 45)
	pe.Lifetime = NumberRange.new(0.2, 0.6)
	pe.Size = NumberSequence.new(4, 8)
	pe.Color = ColorSequence.new(
		Color3.fromRGB(255, 170, 60), Color3.fromRGB(90, 80, 70))
	pe.Enabled = false
	pe.Parent = att
	pe:Emit(24)
	task.delay(1.2, function()
		fx:Destroy()
	end)
end

local function shoot()
	local aimDir = CFrame.fromEulerAnglesYXZ(aimPitch, aimYaw, 0).LookVector
	local origin = pos + aimDir * 8
	local hit = workspace:Raycast(origin, aimDir * 1200, rayParams)
	local target = hit and hit.Position or origin + aimDir * 1200
	local dist = (target - origin).Magnitude

	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.Size = Vector3.new(0.4, 0.4, math.max(dist, 1))
	tracer.CFrame = CFrame.lookAt(origin + (target - origin) * 0.5, target)
	tracer.Color = Color3.fromRGB(255, 220, 80)
	tracer.Material = Enum.Material.Neon
	tracer.Transparency = 0.2
	tracer.Parent = workspace
	task.delay(0.06, function()
		tracer:Destroy()
	end)

	if hit and hit.Instance == Terrain then
		Terrain:FillBall(hit.Position, 6, Enum.Material.Air)
		boomAt(hit.Position)
	end
end

---------------------------------------------------------------------------
-- Vstup: mys hybe zamerovacem (LockCenter jako first-person v Luanti)
---------------------------------------------------------------------------

UserInputService.InputChanged:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		aimYaw = aimYaw - input.Delta.X * MOUSE_SENS
		aimPitch = math.clamp(
			aimPitch - input.Delta.Y * MOUSE_SENS, -LOOK_CLAMP, LOOK_CLAMP)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.V then
		firstPerson = not firstPerson
	elseif input.KeyCode == Enum.KeyCode.R then
		resetFlight()
		showMsg("RESPAWN")
	elseif input.KeyCode == Enum.KeyCode.M then
		radarOn = not radarOn
		radarBox.Visible = radarOn
	end
end)

---------------------------------------------------------------------------
-- Hlavni smycka -- primy port on_step z vehicle.lua
---------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	camera.CameraType = Enum.CameraType.Scriptable

	local function down(k)
		return UserInputService:IsKeyDown(k)
	end

	-- Plyn (W/S): rychlost DRZI, zadne samovolne vraceni
	local thr = (down(Enum.KeyCode.W) and 1 or 0)
		- (down(Enum.KeyCode.S) and 1 or 0)
	if thr > 0 and speed < SPEED_MAX then
		speed = math.min(speed + 8 * dt * thr, SPEED_MAX)
	elseif thr < 0 then
		speed = math.max(speed + 10 * dt * thr, SPEED_MIN)
	end

	-- Airbrake drift: S + A/D = ostra zatacka za cenu rychlosti
	local turn = TURN_SPEED
	local drifting = down(Enum.KeyCode.S)
		and (down(Enum.KeyCode.A) or down(Enum.KeyCode.D))
	if drifting then
		turn = TURN_SPEED * 2.2
		speed = math.max(speed - 12 * dt, SPEED_MIN)
		score = score + 50 * dt
	end

	-- Klavesy hybou zamerovacem stejne jako mys (A/D yaw, Space/Shift pitch)
	if down(Enum.KeyCode.A) then
		aimYaw = aimYaw + turn * dt
	end
	if down(Enum.KeyCode.D) then
		aimYaw = aimYaw - turn * dt
	end
	if down(Enum.KeyCode.Space) then
		aimPitch = math.min(aimPitch + PITCH_RATE * dt, LOOK_CLAMP)
	elseif down(Enum.KeyCode.LeftShift) then
		aimPitch = math.max(aimPitch - PITCH_RATE * dt, -LOOK_CLAMP)
	end

	-- Yaw: dotaceni za zamerovacem nejkratsi cestou
	local chase = math.max(turn * 1.3, 2.0) * dt
	local dy = wrapAngle(aimYaw - yaw)
	yaw = yaw + math.clamp(dy, -chase, chase)

	-- Pitch: cil ze svisleho pohledu, clamp PITCH_MAX
	local targetPitch = math.clamp(aimPitch, -PITCH_MAX, PITCH_MAX)
	local pstep = PITCH_RATE * 1.5 * dt
	pitch = pitch + math.clamp(targetPitch - pitch, -pstep, pstep)

	-- Naklon: automaticky do zatacky, po srovnani kurzu se vyrovna
	local targetRoll = math.clamp(dy * 2.0, -1, 1) * BANK_MAX
	local rstep = ROLL_SPEED * dt
	roll = roll + math.clamp(targetRoll - roll, -rstep, rstep)

	-- Boost + gravitacni fyzika: strmy dive zrychluje, stoupani krvaci
	-- rychlost (plny plyn vykryje 70 % ztraty), overspeed se vycerpa
	if boostTime > 0 then
		boostTime = boostTime - dt
		speed = 60
	elseif pitch < -0.45 then
		speed = math.min(speed + 80 * dt * (-pitch - 0.45), SPEED_MAX * 1.5)
	else
		if pitch > 0.3 then
			local bleed = 40 * (pitch - 0.3) * (1 - 0.7 * math.max(thr, 0))
			speed = math.max(speed - bleed * dt, SPEED_MIN)
		end
		if speed > SPEED_MAX then
			speed = math.max(SPEED_MAX, speed - 12 * dt)
		end
	end

	-- Boost: RMB, stoji 25 z metru (plneho boostu si vsimne az po vyprseni)
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			and boostMeter >= 25 and boostTime <= 0 then
		boostMeter = boostMeter - 25
		boostTime = 2.0
		showMsg("BOOST!")
	end

	-- Pohyb presne jako Luanti: horizontalni smer z yaw * speed,
	-- svisla slozka sin(pitch) * speed
	local hdir = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local vel = (hdir * speed
		+ Vector3.new(0, math.sin(pitch) * speed, 0)) * SCALE
	-- Nez server dogeneruje domovsky ostrov, letadlo visi na miste
	if not workspace:GetAttribute("MapgenHome") then
		vel = Vector3.zero
		msgLabel.Text = "GENERUJI SVET..."
		msgTimeLeft = 0.5
	end
	local newPos = pos + vel * dt

	-- Kolize s terenem: naraz nad 15 m/s = crash (rychlost na minimum),
	-- pomale skrtnuti je zdarma -- uci opatrne letani
	crashCooldown = math.max(0, crashCooldown - dt)
	local step = newPos - pos
	if step.Magnitude > 0.001 then
		local hit = workspace:Raycast(pos, step + step.Unit * 4, rayParams)
		if hit then
			local destroyed = false
			if speed > 15 and crashCooldown <= 0 then
				crashCooldown = 0.5
				flashTime = 0.35
				-- kolizni poskozeni jako vehicle.lua: (speed - 10) * 2.5
				hp = hp - math.floor((speed - 10) * 2.5)
				speed = SPEED_MIN
				if hp <= 0 then
					destroyed = true
					resetFlight()
					showMsg("FIGHTER DESTROYED!")
				else
					showMsg("CRASH!")
				end
			end
			if destroyed then
				newPos = pos
			else
				newPos = hit.Position + hit.Normal * 4
			end
		end
	end
	pos = newPos

	-- Pad do prazdna -> respawn (dno ostrovu muze sahat k ~ -180 studum)
	if pos.Y < -700 then
		resetFlight()
		showMsg("VOID -- RESPAWN")
	end

	-- Proximity charge: let tesne kolem terenu (do 6 m) pri rychlosti
	-- nad 30 m/s nabiji boost -- port tricks.update_passive
	proxTimer = proxTimer + dt
	if proxTimer >= 0.2 then
		proxTimer = 0
		if speed > 30 then
			local reach = 6 * SCALE
			local dirs = {
				Vector3.new(0, -1, 0),
				Vector3.new(0, 1, 0),
				hdir,
				Vector3.new(-hdir.Z, 0, hdir.X),
				Vector3.new(hdir.Z, 0, -hdir.X),
			}
			for _, d in ipairs(dirs) do
				if workspace:Raycast(pos, d * reach, rayParams) then
					boostMeter = math.min(boostMeter + 8 * 0.2, 100)
					score = score + 10 * 0.2
					break
				end
			end
		end
	end

	-- Strelba: LMB, cooldown 0.15 s jako weapons.lua
	shootCooldown = math.max(0, shootCooldown - dt)
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			and shootCooldown <= 0 then
		shootCooldown = 0.15
		shoot()
	end

	-- Vykresleni letadla + postava leti s nim
	local planeCF = CFrame.new(pos)
		* CFrame.fromEulerAnglesYXZ(pitch, yaw, roll)
	plane:PivotTo(planeCF)
	if charRoot then
		charRoot.CFrame = planeCF
	end
	exhaust.Rate = 8 + speed * 1.5

	-- Kamera: zamerovac vzdy uprostred, letadlo se pod nim dotaci.
	-- Eye-lean z vehicle.lua: kamera sklouzne do zatacky podle naklonu
	local aimCF = CFrame.fromEulerAnglesYXZ(aimPitch, aimYaw, 0)
	local aimDir = aimCF.LookVector
	local lean = math.clamp(roll / 1.2, -1, 1)
	local camPos
	if firstPerson then
		local noRoll = CFrame.new(pos)
			* CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		camPos = noRoll:PointToWorldSpace(Vector3.new(
			lean * 1.6 * SCALE,
			(0.5 - math.abs(lean) * 0.4) * SCALE,
			-4 * SCALE))
	else
		camPos = pos - aimDir * 34 + Vector3.new(0, 9, 0)
			+ aimCF.RightVector * lean * 5
		local camHit = workspace:Raycast(pos, camPos - pos, rayParams)
		if camHit then
			camPos = camHit.Position + camHit.Normal * 2
		end
	end
	camera.CFrame = CFrame.lookAt(camPos, pos + aimDir * 300)
	camera.FieldOfView = 70
		+ 20 * math.clamp((speed - SPEED_MAX) / 20, 0, 1)
		+ 5 * math.clamp(speed / SPEED_MAX, 0, 1)

	-- HUD: texty 0.15 s throttle (jako hud.update_flight), bary, vodovaha
	-- a radar kazdy frame / 0.25 s
	local heading = math.deg(
		math.atan2(-math.sin(aimYaw), -math.cos(aimYaw))) % 360
	hudTimer = hudTimer + dt
	if hudTimer >= 0.15 then
		hudTimer = 0
		local alt = math.floor(pos.Y / SCALE + 0.5)
		local vy = math.sin(pitch) * speed
		local vs = "VS  0"
		if vy > 1 or vy < -1 then
			vs = string.format("VS %+d", math.floor(vy + 0.5))
		end
		speedLabel.Text = string.format("SPD %d   ALT %d   %s",
			math.floor(speed + 0.5), alt, vs)
		compassLabel.Text = compassTape(heading)
		headingLabel.Text = string.format("%03d\u{00B0}",
			math.floor(heading + 0.5) % 360)
		scoreLabel.Text = string.format("SCORE %d", math.floor(score))
		local pdeg = math.deg(pitch)
		local bank = math.deg(roll)
		local att = ""
		if pdeg > 3 then
			att = string.format("\u{25B2} %d\u{00B0}", math.floor(pdeg + 0.5))
		elseif pdeg < -3 then
			att = string.format("\u{25BC} %d\u{00B0}", math.floor(-pdeg + 0.5))
		end
		if math.abs(bank) > 5 then
			att = att .. (att ~= "" and "    " or "")
				.. string.format("BANK %+d\u{00B0}", math.floor(bank + 0.5))
		end
		bankLabel.Text = att
		local mg = workspace:GetAttribute("Mapgen")
		mapgenLabel.Text = "mapgen: " .. (mg or "cekam na server...")
		if mg and string.sub(mg, 1, 5) == "CHYBA" then
			mapgenLabel.TextColor3 = Color3.fromRGB(255, 90, 70)
		end
	end
	hullFill.Size = UDim2.fromScale(math.max(0, hp) / 100, 1)
	boostFill.Size = UDim2.fromScale(boostMeter / 100, 1)
	attLine.Rotation = math.deg(roll)
	attLine.Position = UDim2.new(0.5, 0, 0.5,
		-math.clamp(pitch / PITCH_MAX, -1, 1) * 30)
	radarArrow.Rotation = heading
	radarTimer = radarTimer + dt
	if radarOn and radarTimer >= 0.25 then
		radarTimer = 0
		local pxm = pos.X / SCALE
		local pzm = pos.Z / SCALE
		local pcx = math.floor(pxm / ISLAND_GRID)
		local pcz = math.floor(pzm / ISLAND_GRID)
		local sc = (RADAR_PX / 2) / RADAR_RANGE
		local di = 0
		for dcx = -2, 2 do
			for dcz = -2, 2 do
				local ox, oz, r, biome = islandForCell(pcx + dcx, pcz + dcz)
				if ox then
					local rx = (ox - pxm) * sc
					local rz = (oz - pzm) * sc
					if rx * rx + rz * rz < (RADAR_PX / 2 - 6) ^ 2
							and di < #radarDots then
						di = di + 1
						local d2 = radarDots[di]
						d2.Visible = true
						d2.Position = UDim2.new(0.5, rx, 0.5, -rz)
						local ds = math.max(5, r * 2 * sc)
						d2.Size = UDim2.fromOffset(ds, ds)
						d2.BackgroundColor3 = BIOME_DOTS[biome]
						d2.BackgroundTransparency = 0.25
					end
				end
			end
		end
		for i = di + 1, #radarDots do
			radarDots[i].Visible = false
		end
	end
	flashTime = math.max(0, flashTime - dt)
	flash.BackgroundTransparency = 1 - math.min(flashTime * 1.6, 0.55)
	msgTimeLeft = math.max(0, msgTimeLeft - dt)
	msgLabel.TextTransparency = msgTimeLeft > 0
		and math.max(0, 1 - msgTimeLeft * 3) or 1
end)
