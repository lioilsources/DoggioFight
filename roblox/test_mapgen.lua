-- Headless test portu mapgenu: stub Roblox API, nacte generator bez
-- chunk manageru a otestuje distribuci, tvary, tunely a vykon.

-- ── stuby ────────────────────────────────────────────────────────────
local write_stats = {solid = 0, mats = {}, calls = 0}

Enum = {Material = setmetatable({}, {__index = function(_, k) return k end})}
table.create = table.create or function(n, v)
    local t = {}
    for i = 1, n do t[i] = v end
    return t
end
Vector3 = {new = function(x, y, z) return {X = x, Y = y, Z = z} end}
Region3 = {new = function(mn, mx) return {min = mn, max = mx} end}
Color3 = {fromRGB = function() return {} end}
Instance = {new = function() return setmetatable({}, {__newindex = function() end, __index = function() return nil end}) end}
game = {GetService = function(_, n) return {GetPlayers = function() return {} end} end}
workspace = setmetatable({}, {__newindex = function() end, __index = function(_, k)
    if k == "SetAttribute" then return function() end end
    if k == "Terrain" then
        return {
            ReadVoxels = function(_, region, res)
                local nx = math.floor((region.max.X - region.min.X) / res)
                local ny = math.floor((region.max.Y - region.min.Y) / res)
                local nz = math.floor((region.max.Z - region.min.Z) / res)
                local mats, occ = {Size = {X = nx, Y = ny, Z = nz}}, {}
                for i = 1, nx do
                    mats[i], occ[i] = {}, {}
                    for j = 1, ny do
                        mats[i][j], occ[i][j] = {}, {}
                        for k = 1, nz do
                            mats[i][j][k] = "Air"
                            occ[i][j][k] = 0
                        end
                    end
                end
                return mats, occ
            end,
            WriteVoxels = function(_, region, res, mats, occ)
                write_stats.calls = write_stats.calls + 1
                local nx = math.floor((region.max.X - region.min.X) / res)
                local ny = math.floor((region.max.Y - region.min.Y) / res)
                local nz = math.floor((region.max.Z - region.min.Z) / res)
                assert(#mats == nx and #mats[1] == ny and #mats[1][1] == nz,
                    "array dims mismatch region")
                for i = 1, nx do
                    for j = 1, ny do
                        for k = 1, nz do
                            if occ[i][j][k] == 1 then
                                write_stats.solid = write_stats.solid + 1
                                local m = mats[i][j][k]
                                write_stats.mats[m] = (write_stats.mats[m] or 0) + 1
                            end
                        end
                    end
                end
            end,
            FillRegion = function() end,
        }
    end
end})
task = {spawn = function() end, wait = function() end}
typeof = type

-- ── nacist generator bez manageru ────────────────────────────────────
local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = io.open(dir .. "/island-generator.server.lua")
local src = f:read("*a")
f:close()
local cut = src:find("%-%- Chunk manager")
assert(cut, "chunk manager marker")
src = src:sub(1, cut - 1)
src = src .. "\nreturn {ifc = island_for_cell, prof = island_profile, ext = y_extents, gen = generateIsland}\n"
local chunk = assert(loadstring(src))
local G = chunk()

-- ── test 1: distribuce pres 61x61 bunek ──────────────────────────────
local n, occupied, radsum = 0, 0, 0
local rmin, rmax, ymin, ymax = 1e9, 0, 1e9, 0
local biomes, tunnels = {}, 0
for cx = -30, 30 do
    for cz = -30, 30 do
        if not (cx == 0 and cz == 0) then
            n = n + 1
            local isl = G.ifc(cx, cz)
            if isl then
                occupied = occupied + 1
                radsum = radsum + isl.radius
                rmin = math.min(rmin, isl.radius)
                rmax = math.max(rmax, isl.radius)
                ymin = math.min(ymin, isl.y)
                ymax = math.max(ymax, isl.y)
                biomes[isl.biome.name] = (biomes[isl.biome.name] or 0) + 1
                if isl.tunnels then tunnels = tunnels + 1 end
                assert(isl.radius >= 72 and isl.radius <= 165, "radius range")
                assert(isl.y >= 140 and isl.y < 760, "layer range")
                -- ostrov musi lezet ve sve bunce
                assert(isl.x >= cx * 340 and isl.x < (cx + 1) * 340, "x in cell")
                assert(isl.z >= cz * 340 and isl.z < (cz + 1) * 340, "z in cell")
            end
        end
    end
end
local bn = 0
for _ in pairs(biomes) do bn = bn + 1 end
print(string.format("cells=%d occupied=%.1f%% (cil 82) rad=%d..%d avg=%.0f y=%d..%d biomes=%d tunnels=%.1f%% (cil 55)",
    n, occupied / n * 100, rmin, rmax, radsum / occupied, ymin, ymax, bn,
    tunnels / occupied * 100))
assert(math.abs(occupied / n * 100 - 82) < 3, "density")
assert(bn == 12, "all 12 biomes")
assert(math.abs(tunnels / occupied * 100 - 55) < 5, "tunnel chance")

-- home
local home = G.ifc(0, 0)
assert(home.radius == 190 and home.y == 320 and home.shape == "avatar"
    and not home.tunnels, "home island")
print("home biome: " .. home.biome.name)

-- ── test 2: profil avatar ostrova (ASCII rez) ────────────────────────
local isl = home
local up, down = G.ext(isl)
print(string.format("home extents: up=%.0f down=%.0f (m)", up, down))
for y_rel = math.floor(up), -math.floor(down), -math.floor((up + down) / 12) do
    local r = G.prof(isl, y_rel)
    print(string.format("%+5d | %s", y_rel, string.rep("#", math.floor(r / 5))))
end

-- ── test 3: plne generovani mensiho ostrova, tunely ──────────────────
local cand
for cx = 1, 40 do
    local i2 = G.ifc(cx, 3)
    if i2 and i2.tunnels and i2.radius < 95 then cand = i2 break end
end
assert(cand, "tunnel candidate")
print(string.format("kandidat: %s %s R=%d y=%d", cand.biome.name, cand.shape, cand.radius, cand.y))

local t0 = os.clock()
cand.tunnels = false
write_stats = {solid = 0, mats = {}, calls = 0}
G.gen(cand)
local solid_no = write_stats.solid
cand.tunnels = true
write_stats = {solid = 0, mats = {}, calls = 0}
G.gen(cand)
local solid_yes = write_stats.solid
local dt = os.clock() - t0
print(string.format("solid bez tunelu=%d s tunely=%d vykopano=%d (%.1f%%) cas 2 gen=%.2fs",
    solid_no, solid_yes, solid_no - solid_yes,
    (solid_no - solid_yes) / solid_no * 100, dt))
assert(solid_yes < solid_no, "tunnels carve air")
assert(solid_no > 10000, "island has mass")
local surf = write_stats.mats[cand.biome.surface]
print("materialy:", (function() local s = "" for m, c in pairs(write_stats.mats) do s = s .. m .. "=" .. c .. " " end return s end)())
assert(surf and surf > 100, "surface material present")
print("ALL TESTS PASSED")
