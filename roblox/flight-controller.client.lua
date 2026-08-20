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
local pos = SPAWN_POS
local proxTimer, lastProx = 0, -10
local shootCooldown, crashCooldown = 0, 0
local flashTime, msgTimeLeft = 0, 0
local firstPerson = false
local clock = 0

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

local speedLabel = newLabel(UDim2.fromOffset(220, 28),
	UDim2.new(0.5, -220, 0.92, 0), 20)
local boostBg = newFrame(UDim2.fromOffset(260, 12),
	UDim2.fromScale(0.5, 0.92), Color3.fromRGB(20, 25, 35), 0.35)
local boostFill = Instance.new("Frame")
boostFill.Size = UDim2.fromScale(0.5, 1)
boostFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
boostFill.BorderSizePixel = 0
boostFill.Parent = boostBg
local boostLabel = newLabel(UDim2.fromOffset(300, 18),
	UDim2.new(0.5, 0, 0.92, -18), 13)
boostLabel.Text = "BOOST"

local hint = newLabel(UDim2.fromScale(0.9, 0.03), UDim2.fromScale(0.5, 0.965), 14)
hint.TextTransparency = 0.25
hint.Text = "mys zamerovac | W/S plyn | A/D vyboceni | Space/Shift nos"
	.. " | S+A/D drift | LMB strelba | RMB boost | V kamera | R respawn"

local msgLabel = newLabel(UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.5, 0.3), 32)
msgLabel.Text = ""

-- stav mapgenu ze serveru (workspace atribut Mapgen) -- diagnostika
local mapgenLabel = newLabel(UDim2.fromScale(0.5, 0.03), UDim2.fromScale(0.27, 0.86), 14)
mapgenLabel.TextXAlignment = Enum.TextXAlignment.Left
mapgenLabel.TextTransparency = 0.3
mapgenLabel.Text = "mapgen: cekam na server..."

local flash = newFrame(UDim2.fromScale(1.2, 1.2), UDim2.fromScale(0.5, 0.5),
	Color3.fromRGB(255, 60, 40), 1)
flash.ZIndex = 5

local function showMsg(text)
	msgLabel.Text = text
	msgTimeLeft = 1.6
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
	end
end)

---------------------------------------------------------------------------
-- Hlavni smycka -- primy port on_step z vehicle.lua
---------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	clock = clock + dt
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
			if speed > 15 and crashCooldown <= 0 then
				crashCooldown = 0.5
				flashTime = 0.35
				speed = SPEED_MIN
				showMsg("CRASH!")
			end
			newPos = hit.Position + hit.Normal * 4
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
					lastProx = clock
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

	-- HUD
	speedLabel.Text = string.format("SPD %3d m/s", math.floor(speed + 0.5))
	boostFill.Size = UDim2.fromScale(boostMeter / 100, 1)
	if clock - lastProx < 0.5 then
		boostFill.BackgroundColor3 = Color3.fromRGB(120, 255, 160)
	elseif boostMeter >= 25 then
		boostFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
	else
		boostFill.BackgroundColor3 = Color3.fromRGB(140, 140, 160)
	end
	flashTime = math.max(0, flashTime - dt)
	flash.BackgroundTransparency = 1 - math.min(flashTime * 1.6, 0.55)
	msgTimeLeft = math.max(0, msgTimeLeft - dt)
	msgLabel.TextTransparency = msgTimeLeft > 0
		and math.max(0, 1 - msgTimeLeft * 3) or 1
	local mg = workspace:GetAttribute("Mapgen")
	mapgenLabel.Text = "mapgen: " .. (mg or "cekam na server...")
	if mg and string.sub(mg, 1, 5) == "CHYBA" then
		mapgenLabel.TextColor3 = Color3.fromRGB(255, 90, 70)
	end
end)
