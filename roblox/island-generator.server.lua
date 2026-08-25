--!native
--!optimize 2
-- DoggioWars Roblox prototyp -- nekonecne nebe (server)
-- Verny port Luanti mapgenu (mapgen.lua + biomes.lua): deterministicka
-- mrizka 340 m, 5 tvarovych profilu podle biomu, value-noise deformace,
-- tunely ze dvou 3D sumu. Ostrovy se generuji prubezne kolem hrace za letu
-- a daleko za nim se uvolnuji (deterministicka regenerace pri navratu).
-- Jednotky: vypocty v metrech (Luanti prostor), do studu prevadi SCALE.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Terrain = workspace.Terrain

---------------------------------------------------------------------------
-- Konstanty (1:1 z mapgen.lua, metry)
---------------------------------------------------------------------------

local SEED = 7
local SCALE = 3                  -- studu na metr (stejne jako letovy model)
local VOX = 4                    -- study na terrain voxel
local VOX_M = VOX / SCALE        -- ~1.33 m na voxel

local ISLAND_GRID = 340          -- mrizka bunek
local ISLAND_DENSITY = 82        -- % bunek s ostrovem
local RADIUS_MIN = 72
local RADIUS_MAX = 165
local LAYER_MIN = 140            -- vyskove pasmo stredu ostrovu
local LAYER_MAX = 760
local HILL_AMP_MAX = 42          -- rezerva k hornimu extentu
local TUNNEL_MIN_R = 36
local TUNNEL_CHANCE = 55         -- % ostrovu s tunely
local TUNNEL_R2 = 0.055          -- prah trubky: a^2 + b^2 < prah

local CELL_STUDS = ISLAND_GRID * SCALE
local GEN_DIST = 2               -- Cebysev: generovat 5x5 bunek kolem hrace
local UNLOAD_DIST = 4            -- uvolnit bunky dal nez tohle
local MAX_CELL = 28              -- limit Terrain boundu (~32k studu)

Lighting.ClockTime = 12.5
Lighting.Brightness = 2.5
Lighting.ExposureCompensation = 0.1
Lighting.Ambient = Color3.fromRGB(80, 85, 95)
Lighting.OutdoorAmbient = Color3.fromRGB(160, 170, 185)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.4
Lighting.FogColor = Color3.fromRGB(190, 215, 235)
Lighting.FogEnd = 5500
local atm = Instance.new("Atmosphere")
atm.Density = 0.15
atm.Parent = Lighting

---------------------------------------------------------------------------
-- Hash / PRNG -- doslovny port z mapgen.lua (LCG v double presnosti)
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- Value noise (nahrada minetest.get_value_noise): mrizkovy hash -> [-1,1],
-- smoothstep interpolace, oktavy persistence 0.5 / lacunarity 2.
-- Pevne seedy poli (4771/9123/2207/8842) -- mezi svety se meni jen
-- rozmisteni ostrovu, textura kopcu/pobrezi/tunelu je stejna jako v Luanti.
---------------------------------------------------------------------------

local function latt2(ix, iz, seed)
	local h = (ix * 73856093 + iz * 19349663 + seed * 83492791) % 2147483648
	h = (h * 1103515245 + 12345) % 2147483648
	h = (h * 1103515245 + 12345) % 2147483648
	return math.floor(h / 32768) / 32768 - 1
end

local function latt3(ix, iy, iz, seed)
	local h = (ix * 73856093 + iy * 39916801 + iz * 19349663
		+ seed * 83492791) % 2147483648
	h = (h * 1103515245 + 12345) % 2147483648
	h = (h * 1103515245 + 12345) % 2147483648
	return math.floor(h / 32768) / 32768 - 1
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

-- np = {sx, sy, sz, seed, oct}
local function noise2(x, z, np)
	local sum, amp, freq = 0, 1, 1
	for o = 1, np.oct do
		local s = np.seed + o * 919
		local xx = x / np.sx * freq
		local zz = z / np.sz * freq
		local ix, iz = math.floor(xx), math.floor(zz)
		local fx, fz = smooth(xx - ix), smooth(zz - iz)
		local v00 = latt2(ix, iz, s)
		local v10 = latt2(ix + 1, iz, s)
		local v01 = latt2(ix, iz + 1, s)
		local v11 = latt2(ix + 1, iz + 1, s)
		local a = v00 + (v10 - v00) * fx
		local b = v01 + (v11 - v01) * fx
		sum = sum + amp * (a + (b - a) * fz)
		amp = amp * 0.5
		freq = freq * 2
	end
	return sum
end

local function noise3(x, y, z, np)
	local sum, amp, freq = 0, 1, 1
	for o = 1, np.oct do
		local s = np.seed + o * 919
		local xx = x / np.sx * freq
		local yy = y / np.sy * freq
		local zz = z / np.sz * freq
		local ix, iy, iz = math.floor(xx), math.floor(yy), math.floor(zz)
		local fx = smooth(xx - ix)
		local fy = smooth(yy - iy)
		local fz = smooth(zz - iz)
		local v000 = latt3(ix, iy, iz, s)
		local v100 = latt3(ix + 1, iy, iz, s)
		local v010 = latt3(ix, iy + 1, iz, s)
		local v110 = latt3(ix + 1, iy + 1, iz, s)
		local v001 = latt3(ix, iy, iz + 1, s)
		local v101 = latt3(ix + 1, iy, iz + 1, s)
		local v011 = latt3(ix, iy + 1, iz + 1, s)
		local v111 = latt3(ix + 1, iy + 1, iz + 1, s)
		local a = v000 + (v100 - v000) * fx
		local b = v010 + (v110 - v010) * fx
		local c = v001 + (v101 - v001) * fx
		local d = v011 + (v111 - v011) * fx
		local e = a + (b - a) * fy
		local f = c + (d - c) * fy
		sum = sum + amp * (e + (f - e) * fz)
		amp = amp * 0.5
		freq = freq * 2
	end
	return sum
end

local np_hills = {sx = 56, sy = 56, sz = 56, seed = 4771, oct = 3}
local np_edge  = {sx = 34, sy = 34, sz = 34, seed = 9123, oct = 2}
local np_t1    = {sx = 30, sy = 26, sz = 30, seed = 2207, oct = 2}
local np_t2    = {sx = 30, sy = 26, sz = 30, seed = 8842, oct = 2}

---------------------------------------------------------------------------
-- Biomy (biomes.lua) -- materialy jako (surface / filler pasma / deep),
-- hloubka = souvisle plne voxely nad aktualnim, strop 6 m jako v Luanti
---------------------------------------------------------------------------

local M = Enum.Material
local BIOMES = {
	[0]  = {name = "verdant",  shape = "avatar", surface = M.Grass,
	        fill = {{M.Ground, 3}}, deep = M.Rock},
	[1]  = {name = "glacial",  shape = "mesa",   surface = M.Snow,
	        fill = {{M.Ice, 2}, {M.Ground, 5}}, deep = M.Rock},
	[2]  = {name = "volcanic", shape = "avatar", surface = M.Basalt,
	        fill = {{M.Slate, 3}}, deep = M.Rock},
	[3]  = {name = "atoll",    shape = "disc",   surface = M.Sand,
	        fill = {{M.Limestone, 2}}, deep = M.Rock},
	[4]  = {name = "mycelial", shape = "avatar", surface = M.Mud,
	        fill = {{M.Ground, 3}}, deep = M.Rock},
	[5]  = {name = "barren",   shape = "cone",   surface = M.Rock,
	        fill = {}, deep = M.Rock},
	[6]  = {name = "jungle",   shape = "avatar", surface = M.LeafyGrass,
	        fill = {{M.Ground, 4}, {M.Slate, 7}}, deep = M.Rock},
	[7]  = {name = "desert",   shape = "mesa",   surface = M.Sand,
	        fill = {{M.Sandstone, 4}}, deep = M.Sandstone},
	[8]  = {name = "crystal",  shape = "spire",  surface = M.Salt,
	        fill = {{M.Glacier, 2}}, deep = M.Slate},
	[9]  = {name = "ashen",    shape = "cone",   surface = M.Ground,
	        fill = {{M.CrackedLava, 2}, {M.Basalt, 5}}, deep = M.Rock},
	[10] = {name = "savanna",  shape = "mesa",   surface = M.Ground,
	        fill = {{M.Ground, 3}}, deep = M.Rock},
	[11] = {name = "swamp",    shape = "disc",   surface = M.Mud,
	        fill = {{M.Ground, 3}, {M.Slate, 6}}, deep = M.Rock},
}

---------------------------------------------------------------------------
-- Ostrov pro bunku -- presne poradi tahu z mapgen.lua (kazdy nexth se
-- pocita). Bunka (0,0) je vzdy domovsky ostrov, jen biom je ze seedu.
---------------------------------------------------------------------------

local function island_for_cell(cx, cz)
	if cx == 0 and cz == 0 then
		local hb = nexth(hash_2d(777, 333, SEED))
		return {
			x = 0, y = 320, z = 0, radius = 190,
			biome = BIOMES[math.floor(unit(hb) * 12)],
			shape = "avatar", hs = 1.0, cap_frac = 0.6, tail_frac = 0.6,
			tunnels = false,
		}
	end
	local h = hash_2d(cx, cz, SEED)
	if unit(h) * 100 >= ISLAND_DENSITY then
		return nil
	end
	h = nexth(h)
	local radius = math.floor(
		RADIUS_MIN + unit(h) ^ 1.2 * (RADIUS_MAX - RADIUS_MIN))
	h = nexth(h)
	local biome = BIOMES[math.floor(unit(h) * 12)]
	h = nexth(h)
	local pad = math.min(radius, 166)
	local span = math.max(1, ISLAND_GRID - 2 * radius)
	local ox = cx * ISLAND_GRID + pad + math.floor(unit(h) * span)
	h = nexth(h)
	local oz = cz * ISLAND_GRID + pad + math.floor(unit(h) * span)
	h = nexth(h)
	local oy = LAYER_MIN + math.floor(unit(h) * (LAYER_MAX - LAYER_MIN))
	h = nexth(h)
	local hs = 0.7 + unit(h) * 0.7
	h = nexth(h)
	local cap_frac = 0.45 + unit(h) * 0.5
	h = nexth(h)
	local tail_frac = 0.4 + unit(h) * 0.6
	h = nexth(h)
	local tunnels = radius >= TUNNEL_MIN_R and unit(h) * 100 < TUNNEL_CHANCE
	return {
		x = ox, y = oy, z = oz, radius = radius, biome = biome,
		shape = biome.shape, hs = hs, cap_frac = cap_frac,
		tail_frac = tail_frac, tunnels = tunnels,
	}
end

---------------------------------------------------------------------------
-- Tvarove profily (island_profile) -- polomer plne hmoty ve vysce y_rel
---------------------------------------------------------------------------

local function island_profile(isl, y_rel)
	local R, hs = isl.radius, isl.hs
	local shape = isl.shape
	if shape == "avatar" then
		if y_rel >= 0 then
			local t = y_rel / (R * isl.cap_frac * hs)
			return R * math.max(0, 1 - t * t)
		end
		return R * math.exp(y_rel / (R * isl.tail_frac))
	elseif shape == "disc" then
		local half_h = math.max(R * 0.12 * hs, 3)
		return R * math.max(0, 1 - math.abs(y_rel) / half_h)
	elseif shape == "cone" then
		if y_rel >= 0 then
			return R * math.max(0, 1 - y_rel / math.max(R * hs, 1))
		end
		return R * math.max(0, 1 + y_rel / math.max(R * 0.6 * hs, 1))
	elseif shape == "mesa" then
		if y_rel < 0 then
			return R * math.max(0.15, 1 + y_rel / (R * 1.1))
		end
		local top_h = R * 0.30 * hs
		if y_rel <= top_h then
			return R
		end
		return R * math.max(0, 1 - (y_rel - top_h) / (R * 0.25))
	else -- spire
		if y_rel >= 0 then
			return R * math.max(0, 1 - y_rel / math.max(R * 1.15 * hs, 1))
		end
		return R * math.max(0.10, 1 + y_rel / (R * 0.8))
	end
end

-- Vertikalni extents (pro AABB a orez y-pasma)
local function y_extents(isl)
	local R, hs = isl.radius, isl.hs
	local up, down
	if isl.shape == "spire" then
		up, down = 1.6 * R * hs, 0.9 * R
	elseif isl.shape == "cone" then
		up, down = 1.1 * R * hs, 0.7 * R * hs
	elseif isl.shape == "mesa" then
		up, down = 0.5 * R, 1.2 * R
	elseif isl.shape == "disc" then
		up, down = 0.4 * R, 0.4 * R
	else
		up = R * isl.cap_frac * hs + 8
		down = R * isl.tail_frac + 4
	end
	return up + HILL_AMP_MAX, down
end

-- Efektivni polomer sloupce ve vysce y_rel: hill_shift posouva profil jen
-- nad stredem (kopce na povrchu, hladke dno). Guard prof<=0 a fade jsou
-- bug-fixy originalu -- bez nich vznikaji kamenne jehly a boule na spicce.
local function surf_limit(isl, y_rel, hill_shift, edge_boost)
	local prof_y = y_rel
	if y_rel >= 0 then
		prof_y = y_rel - hill_shift
	end
	local prof = island_profile(isl, prof_y)
	if prof <= 0 then
		return 0
	end
	local fade = math.min(1, prof / (isl.radius * 0.3))
	return prof + edge_boost * fade
end

---------------------------------------------------------------------------
-- Generovani ostrova: po dlazdicich 32x32 sloupcu, ReadVoxels -> uprava
-- jen plnych voxelu -> WriteVoxels (merge chrani prekryvy AABB sousedu).
-- Frame-budget drzi server plynuly; pri plne fronte se zvysi.
---------------------------------------------------------------------------

local function setStatus(msg)
	workspace:SetAttribute("Mapgen", msg)
end

local TILE = 32 * VOX            -- 128 studu
local budget_limit = 0.006       -- s CPU na frame; adaptivne az 0.015

local function generateIsland(isl)
	local R = isl.radius
	local up, down = y_extents(isl)
	local reach = R + R * 0.14 + 1          -- max_reach originalu (m)
	local edge_amp = R * 0.14
	local hill_amp = math.max(4, R * 0.16)
	local half_band = R * 0.5               -- tunelove pasmo

	local cxs, cys, czs = isl.x * SCALE, isl.y * SCALE, isl.z * SCALE
	local reach_s = reach * SCALE
	local minX = math.floor((cxs - reach_s) / VOX) * VOX
	local maxX = math.ceil((cxs + reach_s) / VOX) * VOX
	local minZ = math.floor((czs - reach_s) / VOX) * VOX
	local maxZ = math.ceil((czs + reach_s) / VOX) * VOX
	local minY = math.floor((cys - down * SCALE) / VOX) * VOX
	local maxY = math.ceil((cys + up * SCALE) / VOX) * VOX

	-- AABB sousednich ostrovu: jen dlazdice, kde hrozi prekryv, potrebuji
	-- drahy ReadVoxels merge; vsude jinde staci cerstva pole (table.create)
	local overlaps = {}
	local ccx = math.floor(isl.x / ISLAND_GRID)
	local ccz = math.floor(isl.z / ISLAND_GRID)
	for dcx = -1, 1 do
		for dcz = -1, 1 do
			if not (dcx == 0 and dcz == 0) then
				local nb = island_for_cell(ccx + dcx, ccz + dcz)
				if nb then
					local nreach = (nb.radius * 1.14 + 1) * SCALE
					local o = {
						nb.x * SCALE - nreach, nb.x * SCALE + nreach,
						nb.z * SCALE - nreach, nb.z * SCALE + nreach,
					}
					if o[1] < maxX and o[2] > minX
							and o[3] < maxZ and o[4] > minZ then
						overlaps[#overlaps + 1] = o
					end
				end
			end
		end
	end

	local AIR = Enum.Material.Air
	local ny = (maxY - minY) / VOX
	local clockStart = os.clock()
	for tx = minX, maxX - 1, TILE do
		for tz = minZ, maxZ - 1, TILE do
			local x2 = math.min(tx + TILE, maxX)
			local z2 = math.min(tz + TILE, maxZ)
			-- dlazdice cele mimo disk ostrova preskocit
			local ddx = math.max(tx - cxs, cxs - x2, 0)
			local ddz = math.max(tz - czs, czs - z2, 0)
			if ddx * ddx + ddz * ddz <= reach_s * reach_s then
				local region = Region3.new(
					Vector3.new(tx, minY, tz), Vector3.new(x2, maxY, z2))
				local nx = (x2 - tx) / VOX
				local nz = (z2 - tz) / VOX
				local needMerge = false
				for _, o in ipairs(overlaps) do
					if o[1] < x2 and o[2] > tx
							and o[3] < z2 and o[4] > tz then
						needMerge = true
						break
					end
				end
				local mats, occ
				if needMerge then
					mats, occ = Terrain:ReadVoxels(region, VOX)
				else
					mats, occ = {}, {}
					for i = 1, nx do
						local mi, oi = {}, {}
						mats[i], occ[i] = mi, oi
						for j = 1, ny do
							mi[j] = table.create(nz, AIR)
							oi[j] = table.create(nz, 0)
						end
					end
				end
				for i = 1, nx do
					local xm = (tx + (i - 0.5) * VOX) / SCALE
					local mcol, ocol = mats[i], occ[i]
					for k = 1, nz do
						local zm = (tz + (k - 0.5) * VOX) / SCALE
						local dx, dz = xm - isl.x, zm - isl.z
						local dist = math.sqrt(dx * dx + dz * dz)
						if dist <= reach then
							local eb = noise2(xm, zm, np_edge) * edge_amp
							local hsft = noise2(xm, zm, np_hills) * hill_amp
							local depth = 0
							for j = ny, 1, -1 do
								local ym = (minY + (j - 0.5) * VOX) / SCALE
								local y_rel = ym - isl.y
								local solid =
									dist <= surf_limit(isl, y_rel, hsft, eb)
								if solid and isl.tunnels
										and math.abs(y_rel) < half_band then
									local a = noise3(xm, ym, zm, np_t1)
									local b = noise3(xm, ym, zm, np_t2)
									if a * a + b * b < TUNNEL_R2 then
										solid = false
									end
								end
								if solid then
									local mat
									if depth == 0 then
										mat = isl.biome.surface
									else
										local dm = math.min(depth * VOX_M, 6)
										mat = isl.biome.deep
										for _, band in ipairs(isl.biome.fill) do
											if dm <= band[2] then
												mat = band[1]
												break
											end
										end
									end
									mcol[j][k] = mat
									ocol[j][k] = 1
									depth = depth + 1
								else
									depth = 0
								end
							end
						end
					end
					if os.clock() - clockStart > budget_limit then
						task.wait()
						clockStart = os.clock()
					end
				end
				Terrain:WriteVoxels(region, VOX, mats, occ)
			end
		end
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

---------------------------------------------------------------------------
-- Dekorace biomu -- zjednoduseny port decorate.lua: vulkan s lavou,
-- laguna, rampouchy, obri houby, krystaly, stromy, balvany.
-- Deterministicke z bunkoveho LCG (stejny ostrov = stejna dekorace).
-- Party jdou do slozky per ostrov (unload ji znici), teren primo do mapy.
---------------------------------------------------------------------------

local decorRoot = Instance.new("Folder")
decorRoot.Name = "DoggioDecor"
decorRoot.Parent = workspace

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = {Terrain}

local function make_rng(cx, cz)
	local h = hash_2d(cx * 3 + 11, cz * 7 + 5, SEED + 999)
	return function()
		h = nexth(h)
		return unit(h)
	end
end

local function surfaceAt(isl, xs, zs)
	local up, down = y_extents(isl)
	local top = (isl.y + up + 8) * SCALE
	local len = (up + down + 16) * SCALE
	return workspace:Raycast(
		Vector3.new(xs, top, zs), Vector3.new(0, -len, 0), terrainOnly)
end

local function undersideAt(isl, xs, zs)
	local up, down = y_extents(isl)
	local bottom = (isl.y - down - 8) * SCALE
	local len = (up + down + 16) * SCALE
	return workspace:Raycast(
		Vector3.new(xs, bottom, zs), Vector3.new(0, len, 0), terrainOnly)
end

local function decorPart(folder, shape, size, cf, color, material)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CastShadow = false
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = folder
	return p
end

local UP_CYL = CFrame.Angles(0, 0, math.pi / 2)  -- valec osou svisle

local function tree(folder, pos, rng, trunkH, leafC)
	local h = trunkH * SCALE
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(h, 0.9 * SCALE, 0.9 * SCALE),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * UP_CYL,
		Color3.fromRGB(104, 76, 50), Enum.Material.Wood)
	local n = 1 + math.floor(rng() * 2 + 0.5)
	for _ = 1, n do
		local d = (2.6 + rng() * 2.2) * SCALE
		local off = Vector3.new(
			(rng() - 0.5) * 2, (rng() - 0.5) * 0.8, (rng() - 0.5) * 2) * SCALE
		decorPart(folder, Enum.PartType.Ball, Vector3.new(d, d, d),
			CFrame.new(pos + Vector3.new(0, h, 0) + off),
			leafC, Enum.Material.Grass)
	end
end

local function acacia(folder, pos, rng)
	local h = (4 + rng() * 2) * SCALE
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(h, 0.8 * SCALE, 0.8 * SCALE),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * UP_CYL,
		Color3.fromRGB(104, 76, 50), Enum.Material.Wood)
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(0.8 * SCALE, 7 * SCALE, 7 * SCALE),
		CFrame.new(pos + Vector3.new(0, h + 0.4 * SCALE, 0)) * UP_CYL,
		Color3.fromRGB(120, 150, 60), Enum.Material.Grass)
end

local function cactus(folder, pos, rng)
	local green = Color3.fromRGB(70, 130, 60)
	local h = (2 + rng() * 2) * SCALE
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(h, 1.1 * SCALE, 1.1 * SCALE),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * UP_CYL,
		green, Enum.Material.Grass)
	if rng() < 0.7 then
		local ah = 1.4 * SCALE
		decorPart(folder, Enum.PartType.Cylinder,
			Vector3.new(ah, 0.8 * SCALE, 0.8 * SCALE),
			CFrame.new(pos + Vector3.new(1.1 * SCALE, h * 0.6, 0)) * UP_CYL,
			green, Enum.Material.Grass)
	end
end

local function deadTree(folder, pos, rng)
	local h = (3 + rng() * 3) * SCALE
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(h, 0.6 * SCALE, 0.6 * SCALE),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * UP_CYL,
		Color3.fromRGB(92, 82, 72), Enum.Material.Wood)
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(2 * SCALE, 0.4 * SCALE, 0.4 * SCALE),
		CFrame.new(pos + Vector3.new(0.9 * SCALE, h * 0.7, 0)),
		Color3.fromRGB(92, 82, 72), Enum.Material.Wood)
end

local function mushroom(folder, pos, rng, giant)
	local h = (giant and 4 + rng() * 5 or 1 + rng()) * SCALE
	local stemD = (giant and 1.6 or 0.7) * SCALE
	decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new(h, stemD, stemD),
		CFrame.new(pos + Vector3.new(0, h / 2, 0)) * UP_CYL,
		Color3.fromRGB(225, 215, 190), Enum.Material.SmoothPlastic)
	local capD = (giant and (4 + rng() * 4) or 1.4) * SCALE
	local cap = decorPart(folder, Enum.PartType.Cylinder,
		Vector3.new((giant and 1.4 or 0.5) * SCALE, capD, capD),
		CFrame.new(pos + Vector3.new(0, h + 0.5 * SCALE, 0)) * UP_CYL,
		Color3.fromRGB(150, 95, 185), Enum.Material.Neon)
	if giant then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(190, 130, 230)
		l.Range = 10 * SCALE
		l.Brightness = 0.8
		l.Parent = cap
	end
end

local function crystalCluster(folder, pos, rng)
	local n = 2 + math.floor(rng() * 3)
	local main
	for _ = 1, n do
		local h = (1.5 + rng() * 3.5) * SCALE
		local off = Vector3.new((rng() - 0.5) * 3, 0, (rng() - 0.5) * 3) * SCALE
		local p = decorPart(folder, Enum.PartType.Cylinder,
			Vector3.new(h, (0.7 + rng() * 0.6) * SCALE,
				(0.7 + rng() * 0.6) * SCALE),
			CFrame.new(pos + off + Vector3.new(0, h / 2 - 0.3 * SCALE, 0))
				* UP_CYL * CFrame.Angles(rng() * 0.5, rng() * math.pi, 0),
			Color3.fromRGB(150, 225, 255), Enum.Material.Neon)
		main = main or p
	end
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(150, 225, 255)
	l.Range = 12 * SCALE
	l.Brightness = 1
	l.Parent = main
end

local function terrainBall(pos, r_m, mat)
	Terrain:FillBall(
		pos - Vector3.new(0, r_m * 0.4 * SCALE, 0), r_m * SCALE, mat)
end

-- Vulkan (port build_volcano): basaltovy kuzel, krater s lavou,
-- lavovy jazyk po svahu nahodnym smerem
local function volcano(isl, rng)
	local R = isl.radius
	local mr = math.clamp(math.floor(R * 0.42), 18, 34)
	local crater = math.max(4, math.floor(mr * 0.22))
	local mh = math.max(11, math.floor(mr * 0.5))
	local cxs, czs = isl.x * SCALE, isl.z * SCALE
	local hit = surfaceAt(isl, cxs, czs)
	if not hit then return end
	local base = hit.Position.Y
	local steps = 7
	for i = 0, steps do
		local f = i / steps
		local rr = (crater + (mr - crater) * (1 - f) ^ 1.5 + 1) * SCALE
		Terrain:FillCylinder(
			CFrame.new(cxs, base + f * mh * SCALE, czs),
			(mh / steps + 1) * SCALE, rr, Enum.Material.Basalt)
	end
	local topY = base + mh * SCALE
	Terrain:FillCylinder(CFrame.new(cxs, topY + 2.5 * SCALE, czs),
		6 * SCALE, crater * SCALE, Enum.Material.Air)
	Terrain:FillCylinder(CFrame.new(cxs, topY - 0.8 * SCALE, czs),
		2 * SCALE, (crater - 0.5) * SCALE, Enum.Material.CrackedLava)
	local ang = rng() * 2 * math.pi
	local dxu, dzu = math.cos(ang), math.sin(ang)
	local d = crater
	while d <= mr + 6 do
		local px = cxs + dxu * d * SCALE
		local pz = czs + dzu * d * SCALE
		local sHit = workspace:Raycast(
			Vector3.new(px, topY + 6 * SCALE, pz),
			Vector3.new(0, -(mh + 30) * SCALE, 0), terrainOnly)
		if sHit then
			Terrain:FillBall(sHit.Position, 1.6 * SCALE,
				Enum.Material.CrackedLava)
		end
		d = d + 1.6
	end
end

-- Laguna atolu (port fill_atoll_center)
local function lagoon(isl)
	local hole = math.max(3, math.floor(isl.radius * 0.3))
	local cxs, czs = isl.x * SCALE, isl.z * SCALE
	local hit = surfaceAt(isl, cxs, czs)
	if not hit then return end
	local y = hit.Position.Y
	Terrain:FillCylinder(CFrame.new(cxs, y + 1.5 * SCALE, czs),
		5 * SCALE, hole * SCALE, Enum.Material.Air)
	Terrain:FillCylinder(CFrame.new(cxs, y - 1.2 * SCALE, czs),
		2.4 * SCALE, hole * SCALE, Enum.Material.Water)
end

-- Rampouchy pod okrajem ledovcove mesy (port place_icicles)
local function icicles(isl, rng)
	local n = 6 + math.floor(rng() * 7)
	for _ = 1, n do
		local ang = rng() * 2 * math.pi
		local rad = isl.radius * (0.55 + rng() * 0.4) * SCALE
		local xs = isl.x * SCALE + math.cos(ang) * rad
		local zs = isl.z * SCALE + math.sin(ang) * rad
		local hit = undersideAt(isl, xs, zs)
		if hit then
			for k = 0, 2 do
				Terrain:FillBall(
					hit.Position - Vector3.new(0, k * 1.6 * SCALE, 0),
					math.max(0.6, 1.6 - k * 0.45) * SCALE,
					Enum.Material.Glacier)
			end
		end
	end
end

local TREE_GREEN = Color3.fromRGB(70, 140, 60)
local JUNGLE_GREEN = Color3.fromRGB(45, 110, 45)

local function decorateIsland(isl, key, cx, cz)
	local folder = Instance.new("Folder")
	folder.Name = key
	folder.Parent = decorRoot
	local rng = make_rng(cx, cz)
	local function scatter(n, fn)
		for _ = 1, n do
			local ang = rng() * 2 * math.pi
			local rad = isl.radius * (0.12 + 0.78 * math.sqrt(rng())) * SCALE
			local xs = isl.x * SCALE + math.cos(ang) * rad
			local zs = isl.z * SCALE + math.sin(ang) * rad
			local hit = surfaceAt(isl, xs, zs)
			if hit and hit.Material ~= Enum.Material.Water then
				fn(hit.Position)
			end
		end
	end
	local b = isl.biome.name
	if b == "verdant" then
		scatter(8 + math.floor(rng() * 8), function(p)
			tree(folder, p, rng, 4 + rng() * 3, TREE_GREEN)
		end)
		scatter(2, function(p)
			terrainBall(p, 1.5 + rng(), Enum.Material.Rock)
		end)
	elseif b == "jungle" then
		scatter(12 + math.floor(rng() * 8), function(p)
			tree(folder, p, rng, 6 + rng() * 4, JUNGLE_GREEN)
		end)
	elseif b == "savanna" then
		scatter(3 + math.floor(rng() * 3), function(p)
			acacia(folder, p, rng)
		end)
	elseif b == "desert" then
		scatter(4 + math.floor(rng() * 4), function(p)
			cactus(folder, p, rng)
		end)
		scatter(2, function(p)
			terrainBall(p, 1 + rng(), Enum.Material.Sandstone)
		end)
	elseif b == "volcanic" then
		volcano(isl, rng)
	elseif b == "ashen" then
		scatter(2 + math.floor(rng() * 3), function(p)
			deadTree(folder, p, rng)
		end)
		scatter(4 + math.floor(rng() * 3), function(p)
			Terrain:FillBall(p, (1.5 + rng()) * SCALE,
				Enum.Material.CrackedLava)
		end)
	elseif b == "mycelial" then
		scatter(3 + math.floor(rng() * 6), function(p)
			mushroom(folder, p, rng, true)
		end)
	elseif b == "swamp" then
		scatter(4 + math.floor(rng() * 5), function(p)
			mushroom(folder, p, rng, false)
		end)
	elseif b == "crystal" then
		scatter(5 + math.floor(rng() * 5), function(p)
			crystalCluster(folder, p, rng)
		end)
	elseif b == "barren" then
		scatter(2 + math.floor(rng() * 4), function(p)
			terrainBall(p, 1.5 + rng() * 1.5, Enum.Material.Rock)
		end)
	elseif b == "glacial" then
		icicles(isl, rng)
		scatter(3, function(p)
			terrainBall(p, 1 + rng(), Enum.Material.Glacier)
		end)
	elseif b == "atoll" then
		lagoon(isl)
		scatter(3, function(p)
			tree(folder, p, rng, 5 + rng() * 2, Color3.fromRGB(90, 160, 70))
		end)
	end
end

---------------------------------------------------------------------------
-- Chunk manager: bunky kolem hracu do fronty (nejblizsi prvni),
-- vzdalene vygenerovane bunky uvolnit (FillRegion Air + zapomenout)
---------------------------------------------------------------------------

local done_count = 0
local generated = {}   -- key -> true (prazdna bunka) | {min, max} (region)
local pending = {}     -- key -> true (ve fronte / prave se generuje)
local queue = {}

local function cellKey(cx, cz)
	return cx .. ":" .. cz
end

local function playerCells()
	local cells = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			local p = root.Position
			cells[#cells + 1] = {
				math.floor(p.X / CELL_STUDS),
				math.floor(p.Z / CELL_STUDS),
			}
		end
	end
	return cells
end

-- Zasobovaci + unload smycka
task.spawn(function()
	while true do
		local cells = playerCells()
		for _, c in ipairs(cells) do
			for dcx = -GEN_DIST, GEN_DIST do
				for dcz = -GEN_DIST, GEN_DIST do
					local cx, cz = c[1] + dcx, c[2] + dcz
					if math.abs(cx) <= MAX_CELL
							and math.abs(cz) <= MAX_CELL then
						local key = cellKey(cx, cz)
						if not generated[key] and not pending[key] then
							pending[key] = true
							queue[#queue + 1] = {cx, cz, key}
						end
					end
				end
			end
		end
		if #queue > 1 and #cells > 0 then
			local pc = cells[1]
			table.sort(queue, function(a, b)
				local da = math.max(
					math.abs(a[1] - pc[1]), math.abs(a[2] - pc[2]))
				local db = math.max(
					math.abs(b[1] - pc[1]), math.abs(b[2] - pc[2]))
				return da < db
			end)
		end
		budget_limit = #queue > 6 and 0.015 or 0.006
		if #cells > 0 then
			for key, info in pairs(generated) do
				local scx, scz = string.match(key, "^(-?%d+):(-?%d+)$")
				local cx, cz = tonumber(scx), tonumber(scz)
				local near = false
				for _, c in ipairs(cells) do
					if math.max(math.abs(cx - c[1]), math.abs(cz - c[2]))
							< UNLOAD_DIST then
						near = true
						break
					end
				end
				if not near then
					if typeof(info) == "table" then
						Terrain:FillRegion(
							Region3.new(info.min, info.max),
							VOX, Enum.Material.Air)
					end
					local df = decorRoot:FindFirstChild(key)
					if df then
						df:Destroy()
					end
					generated[key] = nil
				end
			end
		end
		task.wait(0.5)
	end
end)

-- Generacni worker: jeden ostrov po druhem
task.spawn(function()
	while true do
		local item = table.remove(queue, 1)
		if item then
			local key = item[3]
			if not generated[key] then
				local isl = island_for_cell(item[1], item[2])
				if isl then
					setStatus(string.format("generuji (%d,%d) %s R=%dm, fronta %d",
						item[1], item[2], isl.biome.name, isl.radius, #queue))
					local ok, rmin, rmax = pcall(generateIsland, isl)
					if ok then
						-- +88 studu rezerva nad AABB: vulkan/stromy at
						-- nezustanou viset po unloadu
						generated[key] = {min = rmin,
							max = rmax + Vector3.new(0, 88, 0)}
						done_count = done_count + 1
						local dok, derr = pcall(decorateIsland, isl, key,
							item[1], item[2])
						if not dok then
							warn("[DoggioWars] decor error: "
								.. tostring(derr))
						end
						if key == "0:0" then
							workspace:SetAttribute("MapgenHome", true)
						end
						print(string.format(
							"[DoggioWars] island (%d,%d) %s %s R=%dm y=%dm%s",
							item[1], item[2], isl.biome.name, isl.shape,
							isl.radius, isl.y,
							isl.tunnels and " +tunnels" or ""))
						setStatus(string.format("ostrovu: %d, fronta %d",
							done_count, #queue))
					else
						warn("[DoggioWars] mapgen error: " .. tostring(rmin))
						setStatus("CHYBA: " .. tostring(rmin))
						generated[key] = true
					end
				else
					generated[key] = true
				end
			end
			pending[key] = nil
		else
			task.wait(0.25)
		end
	end
end)

setStatus("startuji, seed " .. SEED)
print("[DoggioWars] Infinite mapgen ready, seed " .. SEED)
