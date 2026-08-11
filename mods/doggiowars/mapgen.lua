-- doggiowars/mapgen.lua
-- Generátor vzdušných ostrovů: tvary, biomy, kopce/údolí (šum),
-- nepravidelné pobřeží a přírodní tunely provrtané skrz masiv.

doggiowars = doggiowars or {}

-- Parametry světa
local ISLAND_LAYER_MIN = 140
local ISLAND_LAYER_MAX = 760
local CLOUD_FLOOR      = -500
local CLOUD_CEIL       = 1500
-- Pozor: aby se sousední ostrovy NEPŘEKRÝVALY a nepohlcovaly se navzájem,
-- musí platit 2*RADIUS_MAX <= ISLAND_GRID (max ostrovy se pak nanejvýš dotknou).
local ISLAND_GRID      = 340   -- velikost buňky mřížky (větší rozestup = bez slévání)
local RADIUS_MIN       = 72    -- i nejmenší ostrov je pořádný
local RADIUS_MAX       = 165   -- velké ostrovy, ale ne tak, aby prorůstaly sousedy
local ISLAND_DENSITY   = 82    -- % buněk, které nesou ostrov (zbytek = volné nebe)

-- Tunely
local TUNNEL_MIN_R     = 36    -- menší ostrovy tunely nemají
local TUNNEL_CHANCE    = 55    -- % velkých ostrovů má tunely
local TUNNEL_R2        = 0.055 -- poloměr trubice (a^2 + b^2 < R2)

-- Kopce / rezerva výšky nad profilem
local HILL_AMP_MAX     = 42

-- Domovský ostrov u počátku — je tu VŽDY (nezávisle na seedu), aby hráč
-- spawnoval přímo nad terénem a hned viděl ostrovy. Biom je náhodný podle
-- seedu (viz island_for_cell); tvar drží "avatar" kvůli spawnu.
local HOME = {
    x = 0, y = 320, z = 0, radius = 190,
    height_scale = 1.0, cap_frac = 0.6, tail_frac = 0.6,
}

-- Content ID cache
local c_air
local c_stone

local function init_mapgen_ids()
    c_air   = minetest.get_content_id("air")
    c_stone = minetest.get_content_id("default:stone")
end

minetest.after(0, init_mapgen_ids)

---------------------------------------------------------------------------
-- Šumová pole (kopce, pobřeží, tunely). Vytvoří se líně, až je znám seed.
---------------------------------------------------------------------------

local np_edge, np_hills, np_t1, np_t2

local function init_noise()
    if np_edge then return end
    local get = minetest.get_value_noise or minetest.get_perlin
    np_hills = get({offset = 0, scale = 1, spread = {x = 56, y = 56, z = 56},
                    seed = 4771, octaves = 3, persistence = 0.5, lacunarity = 2.0})
    np_edge  = get({offset = 0, scale = 1, spread = {x = 34, y = 34, z = 34},
                    seed = 9123, octaves = 2, persistence = 0.5, lacunarity = 2.0})
    np_t1    = get({offset = 0, scale = 1, spread = {x = 30, y = 26, z = 30},
                    seed = 2207, octaves = 2, persistence = 0.5, lacunarity = 2.0})
    np_t2    = get({offset = 0, scale = 1, spread = {x = 30, y = 26, z = 30},
                    seed = 8842, octaves = 2, persistence = 0.5, lacunarity = 2.0})
end

---------------------------------------------------------------------------
-- Tvary ostrovů — vrací horizontální poloměr masivu ve výšce y_rel
---------------------------------------------------------------------------

local function island_profile(isl, y_rel)
    local base_r = isl.radius
    local hs   = isl.height_scale or 1.0
    local style = isl.shape

    if style == "avatar" then
        -- Kupole nahoře, exponenciální ocas dolů
        if y_rel >= 0 then
            local cap_h = base_r * (isl.cap_frac or 0.6) * hs
            if cap_h <= 0 then return 0 end
            return base_r * math.max(0, 1 - (y_rel / cap_h) ^ 2)
        else
            local tail_len = base_r * (isl.tail_frac or 0.6)
            if tail_len <= 0 then return 0 end
            return base_r * math.exp(y_rel / tail_len)
        end

    elseif style == "disc" then
        -- Placatý disk / atol
        local half_h = math.max(base_r * 0.12 * hs, 3)
        return base_r * math.max(0, 1 - math.abs(y_rel) / half_h)

    elseif style == "cone" then
        -- Hora: kužel vzhůru (široká základna → špička), krátký ocas dolů
        if y_rel >= 0 then
            local h_up = math.max(base_r * 1.0 * hs, 1)
            return base_r * math.max(0, 1 - y_rel / h_up)
        else
            local h_dn = math.max(base_r * 0.6 * hs, 1)
            return base_r * math.max(0, 1 - math.abs(y_rel) / h_dn)
        end

    elseif style == "mesa" then
        -- Plošina s plochým vrškem a strmými stěnami; mírně se zužující základna
        local top_h = base_r * 0.30 * hs
        if y_rel >= 0 then
            if y_rel <= top_h then return base_r end
            local over = y_rel - top_h
            return base_r * math.max(0, 1 - over / math.max(base_r * 0.25, 1))
        else
            return base_r * math.max(0.15, 1 - math.abs(y_rel) / math.max(base_r * 1.1, 1))
        end

    elseif style == "spire" then
        -- Vysoká věž / horský štít
        local peak_h = math.max(base_r * 1.15 * hs, 1)
        if y_rel >= 0 then
            return base_r * math.max(0, 1 - y_rel / peak_h)
        else
            return base_r * math.max(0.1, 1 - math.abs(y_rel) / math.max(base_r * 0.8, 1))
        end
    end
    return 0
end

-- Vertikální rozsah masivu (nahoru/dolů od středu) — pro ohraničení chunku
local function y_extents(isl)
    local r = isl.radius
    local up, down
    local shape = isl.shape
    if shape == "spire" then
        up, down = r * 1.6 * (isl.height_scale or 1), r * 0.9
    elseif shape == "cone" then
        up, down = r * 1.1 * (isl.height_scale or 1), r * 0.7 * (isl.height_scale or 1)
    elseif shape == "mesa" then
        up, down = r * 0.5, r * 1.2
    elseif shape == "disc" then
        up, down = r * 0.4, r * 0.4
    else -- avatar
        up   = r * (isl.cap_frac or 0.6) * (isl.height_scale or 1) + 8
        down = r * (isl.tail_frac or 0.6) + 4
    end
    return up + HILL_AMP_MAX, down
end

---------------------------------------------------------------------------
-- Deterministický hash pro rozmístění ostrovů
---------------------------------------------------------------------------

local function hash_2d(cx, cz, seed)
    local h = cx * 73856093 + cz * 19349663 + seed
    h = math.abs(h)
    h = (h * 1103515245 + 12345) % 2147483648
    return h
end

local function nexth(h)
    return (h * 1103515245 + 12345) % 2147483648
end

-- Rovnoměrné [0,1) z horních bitů hashe (nízké bity LCG jsou málo náhodné)
local function unit(h)
    return math.floor(h / 32768) / 65536
end

---------------------------------------------------------------------------
-- Deterministický ostrov pro jednu buňku mřížky
---------------------------------------------------------------------------

local function island_for_cell(cx, cz, seed)
    -- Domovská buňka — pevný ostrov u počátku. Biom je NÁHODNÝ podle seedu
    -- světa (různý svět = jiný biom domova), ale tvar držíme "avatar" (rovná
    -- kupole), ať spawn sedí u jakéhokoli biomu.
    if cx == 0 and cz == 0 then
        local hidx = math.floor(unit(nexth(hash_2d(777, 333, seed)))
            * (doggiowars.biome_count or 6))
        local b = doggiowars.biomes[hidx] or doggiowars.biomes[0]
        if not b then return nil end
        return {
            x = HOME.x, y = HOME.y, z = HOME.z, radius = HOME.radius,
            biome_idx = hidx, biome = b, shape = "avatar",
            height_scale = HOME.height_scale, cap_frac = HOME.cap_frac,
            tail_frac = HOME.tail_frac, tunnels = false,
        }
    end

    local h = hash_2d(cx, cz, seed)

    -- Hustota — část buněk zůstane prázdná (volné nebe)
    if unit(h) * 100 >= ISLAND_DENSITY then return nil end
    h = nexth(h)

    -- Poloměr (nelineární — mírná převaha středních, ale i pořádní obři)
    local frac = unit(h)
    local radius = math.floor(RADIUS_MIN + (frac ^ 1.2) * (RADIUS_MAX - RADIUS_MIN))
    h = nexth(h)

    -- Biom
    local biome_idx = math.floor(unit(h) * (doggiowars.biome_count or 6))
    h = nexth(h)
    local biome = doggiowars.biomes[biome_idx]
    if not biome then return nil end

    -- Střed v rámci buňky (necháme okraj = radius, ať se ostrovy moc nepřekrývají)
    local pad = math.min(radius, math.floor(ISLAND_GRID / 2) - 4)
    local span = math.max(1, ISLAND_GRID - 2 * pad)
    local ox = cx * ISLAND_GRID + pad + math.floor(unit(h) * span); h = nexth(h)
    local oz = cz * ISLAND_GRID + pad + math.floor(unit(h) * span); h = nexth(h)

    -- Výška vrstvy
    local oy = ISLAND_LAYER_MIN + math.floor(unit(h) * (ISLAND_LAYER_MAX - ISLAND_LAYER_MIN))
    h = nexth(h)

    -- Per-ostrov parametry tvaru
    local height_scale = 0.7 + unit(h) * 0.7     -- 0.70 .. 1.40
    h = nexth(h)
    local cap_frac = 0.45 + unit(h) * 0.5        -- 0.45 .. 0.95
    h = nexth(h)
    local tail_frac = 0.40 + unit(h) * 0.6       -- 0.40 .. 1.00
    h = nexth(h)
    local tunnels = radius >= TUNNEL_MIN_R and (unit(h) * 100 < TUNNEL_CHANCE)

    return {
        x = ox, y = oy, z = oz,
        radius = radius,
        biome_idx = biome_idx,
        biome = biome,
        shape = biome.shape,
        height_scale = height_scale,
        cap_frac = cap_frac,
        tail_frac = tail_frac,
        tunnels = tunnels,
    }
end

---------------------------------------------------------------------------
-- Ostrovy, jejichž bounding box zasahuje do chunku
---------------------------------------------------------------------------

local function get_islands_for_chunk(minp, maxp, seed)
    local islands = {}
    local margin = RADIUS_MAX * 1.4
    local cx0 = math.floor((minp.x - margin) / ISLAND_GRID)
    local cx1 = math.floor((maxp.x + margin) / ISLAND_GRID)
    local cz0 = math.floor((minp.z - margin) / ISLAND_GRID)
    local cz1 = math.floor((maxp.z + margin) / ISLAND_GRID)

    for cx = cx0, cx1 do
        for cz = cz0, cz1 do
            local isl = island_for_cell(cx, cz, seed)
            if isl then
                local r_ext = isl.radius * 1.2   -- rezerva na pobřežní šum
                local up, down = y_extents(isl)
                if isl.x + r_ext >= minp.x
                   and isl.x - r_ext <= maxp.x
                   and isl.z + r_ext >= minp.z
                   and isl.z - r_ext <= maxp.z
                   and isl.y + up >= minp.y
                   and isl.y - down <= maxp.y then
                    table.insert(islands, isl)
                end
            end
        end
    end
    return islands
end

---------------------------------------------------------------------------
-- Efektivní poloměr masivu ve výšce y (s posunem kopců)
---------------------------------------------------------------------------

local function surf_limit(isl, y_rel, hill_shift, edge_boost)
    local prof_y = y_rel
    if y_rel >= 0 then prof_y = y_rel - hill_shift end
    local prof = island_profile(isl, prof_y)
    -- Pobřežní šum smí jen zvlnit existující masiv. Bez tohohle se nad
    -- vrcholem (profil = 0) přičetl kladný edge_boost a sloupce u středu
    -- se plnily až po strop pásma — jehla z kamene trčící do nebe.
    if prof <= 0 then return 0 end
    local fade = math.min(1, prof / (isl.radius * 0.3))
    return prof + edge_boost * fade
end

-- Hloubka pod povrchem (0 = povrch) — konzistentní s výplní sloupce
local function calc_depth(x, y, z, isl, dist_xz, hill_shift, edge_boost)
    local depth = 0
    for check_y = y + 1, y + 6 do
        local yr = check_y - isl.y
        if dist_xz <= surf_limit(isl, yr, hill_shift, edge_boost) then
            depth = depth + 1
        else
            break
        end
    end
    return depth
end

---------------------------------------------------------------------------
-- Hlavní mapgen callback
---------------------------------------------------------------------------

local mapgen_seed = nil

function doggiowars.get_world_seed()
    if not mapgen_seed then
        -- Seed světa je u64 (až 20 cifer) — přes tonumber() by ztratil
        -- přesnost a hash_2d by s hodnotou >= 2^53 degeneroval na konstantu
        -- (h*LCG zaokrouhlené na násobky 2^38 dává % 2^31 == 0 vždy!).
        -- Proto ho složíme z číslic modulárně do bezpečného rozsahu < 2^31.
        local s = tostring(minetest.get_mapgen_setting("seed") or "42")
        local n = 0
        for d in s:gmatch("%d") do
            n = (n * 10 + tonumber(d)) % 2147483648
        end
        if n == 0 then n = 42 end
        mapgen_seed = n
    end
    return mapgen_seed
end

minetest.register_on_generated(function(minp, maxp, blockseed)
    if maxp.y < CLOUD_FLOOR or minp.y > CLOUD_CEIL then return end

    doggiowars.get_world_seed()
    init_noise()

    local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local data = vm:get_data()
    local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})

    local islands = get_islands_for_chunk(minp, maxp, mapgen_seed)
    if #islands == 0 then return end

    local modified = false

    for _, island in ipairs(islands) do
        local biome = island.biome
        local up, down = y_extents(island)

        local y_min = math.max(minp.y, math.floor(island.y - down))
        local y_max = math.min(maxp.y, math.ceil(island.y + up))

        local r_ext = island.radius * 1.2
        local x_min = math.max(minp.x, math.floor(island.x - r_ext))
        local x_max = math.min(maxp.x, math.ceil(island.x + r_ext))
        local z_min = math.max(minp.z, math.floor(island.z - r_ext))
        local z_max = math.min(maxp.z, math.ceil(island.z + r_ext))

        local edge_amp = island.radius * 0.14
        local hill_amp = math.max(4, island.radius * 0.16)
        local mid_band = island.radius * 0.5
        -- Nejzazší horizontální dosah masivu (poloměr + max. pobřežní šum).
        -- Sloupce za ním nemůžou být nikdy plné → přeskočíme (kruh ve čtverci).
        local max_reach = island.radius + edge_amp + 1

        for z = z_min, z_max do
            local dz = z - island.z
            for x = x_min, x_max do
                local dx = x - island.x
                local dist_xz = math.sqrt(dx * dx + dz * dz)

                if dist_xz <= max_reach then
                    local edge_boost = np_edge:get_2d({x = x, y = z}) * edge_amp
                    local hill_shift = np_hills:get_2d({x = x, y = z}) * hill_amp

                    for y = y_max, y_min, -1 do
                        local y_rel = y - island.y
                        local limit = surf_limit(island, y_rel, hill_shift, edge_boost)

                        if limit > 0 and dist_xz <= limit then
                            local vi = area:index(x, y, z)
                            if data[vi] == c_air then
                                -- Přírodní tunel (trubice ze dvou šumů)
                                local carve = false
                                if island.tunnels and math.abs(y_rel) < mid_band then
                                    local a = np_t1:get_3d({x = x, y = y, z = z})
                                    local b = np_t2:get_3d({x = x, y = y, z = z})
                                    if a * a + b * b < TUNNEL_R2 then
                                        carve = true
                                    end
                                end
                                if not carve then
                                    local depth = calc_depth(x, y, z, island,
                                        dist_xz, hill_shift, edge_boost)
                                    data[vi] = biome.surface(depth)
                                    modified = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if modified then
        vm:set_data(data)
        -- Plné denní světlo na ostrovy ze všech stran (svět je zamčený na
        -- poledne). Bez tohohle mají spodky a stinné strany světlo 0 =
        -- vypadají úplně černé.
        vm:set_lighting({day = 15, night = 15})
        vm:write_to_map()
        vm:update_liquids()
    end
end)

---------------------------------------------------------------------------
-- Vypnout defaultní mapgen (singlenode) — jen naše ostrovy
---------------------------------------------------------------------------

-- set_mapgen_params je deprecated (hlásilo to při každém startu);
-- set_mapgen_setting s override_meta=true je jeho náhrada a přebije
-- i map_meta.txt světů založených dřív. Hra navíc v game.conf povoluje
-- jen singlenode, takže nový svět jinak než takhle ani nevznikne.
minetest.register_on_mapgen_init(function()
    minetest.set_mapgen_setting("mg_name", "singlenode", true)
    minetest.set_mapgen_setting("mg_flags", "nolight", true)
end)

---------------------------------------------------------------------------
-- Spawn nad ostrovem — aby hráč vždy startoval u terénu
---------------------------------------------------------------------------

local function island_top(isl)
    local up = y_extents(isl)          -- horní rozsah (vč. rezervy na kopce)
    return isl.y + up
end

-- Spawn/přílet tak, aby ostrov byl PŘED hráčem, ne pod ním.
-- Hráče postavíme kus vedle ostrova na TU stranu, ze které přilétá (from_x,
-- from_z) — letí pak nejkratší cestou a ostrov má v zorném poli. Bez zadání
-- směru bereme +Z, což sedí čerstvě nasazené stíhačce (yaw 0 = letí na -Z).
-- Druhá návratová hodnota je yaw pohledu namířený na střed ostrova.
local APPROACH_MARGIN = 90     -- odstup od okraje ostrova (bloky)

local function frame_spawn(isl, from_x, from_z)
    local dx = (from_x or isl.x) - isl.x
    local dz = (from_z or (isl.z + 1)) - isl.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d < 1 then                                 -- přímo nad středem → +Z
        dx, dz, d = 0, 1, 1
    end
    dx, dz = dx / d, dz / d

    local dist = isl.radius + APPROACH_MARGIN
    local surf = isl.y + isl.radius * 0.55        -- ~ výška povrchu kupole
    local pos = {
        x = math.floor(isl.x + dx * dist),
        y = math.floor(surf + 18),
        z = math.floor(isl.z + dz * dist),
    }
    -- pohled zpátky na ostrov (opačný směr, než kterým jsme se odsadili)
    return pos, minetest.dir_to_yaw({x = -dx, y = 0, z = -dz})
end

-- Pozice u nejbližšího ostrova k (x,z); fallback = domovský ostrov
function doggiowars.spawn_pos_near(x, z, seed)
    seed = seed or doggiowars.get_world_seed()
    local ccx = math.floor(x / ISLAND_GRID)
    local ccz = math.floor(z / ISLAND_GRID)
    local best, bestd
    for dcx = -2, 2 do
        for dcz = -2, 2 do
            local isl = island_for_cell(ccx + dcx, ccz + dcz, seed)
            if isl then
                local ddx, ddz = isl.x - x, isl.z - z
                local d = ddx * ddx + ddz * ddz
                if not bestd or d < bestd then bestd, best = d, isl end
            end
        end
    end
    if not best then best = island_for_cell(0, 0, seed) end
    if not best then return {x = 0, y = ISLAND_LAYER_MIN + 60, z = 0} end
    return frame_spawn(best, x, z)
end

-- Domovský spawn (počátek světa)
function doggiowars.spawn_pos()
    local home = island_for_cell(0, 0, doggiowars.get_world_seed())
    if not home then return {x = 0, y = 260, z = 0} end
    return frame_spawn(home)
end

-- Nejbližší ostrov k bodu (pro info / navigaci): vrací isl, vzdálenost
function doggiowars.nearest_island(x, z, seed)
    seed = seed or doggiowars.get_world_seed()
    local ccx = math.floor(x / ISLAND_GRID)
    local ccz = math.floor(z / ISLAND_GRID)
    local best, bestd
    for dcx = -3, 3 do
        for dcz = -3, 3 do
            local isl = island_for_cell(ccx + dcx, ccz + dcz, seed)
            if isl then
                local ddx, ddz = isl.x - x, isl.z - z
                local d = math.sqrt(ddx * ddx + ddz * ddz)
                if not bestd or d < bestd then bestd, best = d, isl end
            end
        end
    end
    return best, bestd
end

-- Nejbližší ostrov daného biomu (pro /island <biom>). Prohledá box cca
-- max_cells buněk kolem hráče a vrátí nejbližší shodu + vzdálenost.
function doggiowars.nearest_island_of_biome(x, z, biome_name, seed, max_cells)
    seed = seed or doggiowars.get_world_seed()
    max_cells = max_cells or 12
    local ccx = math.floor(x / ISLAND_GRID)
    local ccz = math.floor(z / ISLAND_GRID)
    local best, bestd
    for dcx = -max_cells, max_cells do
        for dcz = -max_cells, max_cells do
            local isl = island_for_cell(ccx + dcx, ccz + dcz, seed)
            if isl and isl.biome and isl.biome.name == biome_name then
                local ddx, ddz = isl.x - x, isl.z - z
                local d = math.sqrt(ddx * ddx + ddz * ddz)
                if not bestd or d < bestd then bestd, best = d, isl end
            end
        end
    end
    return best, bestd
end

-- Spawn rámec (pozice nad okrajem ostrova) pro konkrétní ostrov
function doggiowars.island_spawn(isl)
    return frame_spawn(isl)
end

-- Přílet k ostrovu ze strany hráče: ostrov skončí PŘED ním, ne pod ním.
-- Vrací pozici + yaw pohledu na střed (viz frame_spawn).
function doggiowars.island_approach(isl, from_x, from_z)
    return frame_spawn(isl, from_x, from_z)
end

-- Vyhlídka NAD středem ostrova (prohlídka shora). Výška podle tvaru:
-- spire (krystalová věž) je nejvyšší, cone strmý, ostatní ploché;
-- rezerva pokryje i sopečnou homoli (~17 bloků) na sopečném ostrově.
-- Používá už jen /goto bez zadané výšky — příkazy k ostrovům létají
-- přes island_approach, aby hráč ostrov viděl před sebou.
function doggiowars.island_vantage(isl)
    local fac = 0.75
    if isl.shape == "spire" then fac = 2.6
    elseif isl.shape == "cone" then fac = 1.7 end
    return {x = isl.x, y = math.floor(isl.y + isl.radius * fac + 25), z = isl.z}
end

---------------------------------------------------------------------------
-- Export pro dekorace / závod
---------------------------------------------------------------------------

doggiowars.get_islands_for_chunk = get_islands_for_chunk
doggiowars.island_for_cell = island_for_cell
doggiowars.island_profile = island_profile
doggiowars.ISLAND_GRID = ISLAND_GRID
doggiowars.CLOUD_FLOOR = CLOUD_FLOOR
doggiowars.CLOUD_CEIL = CLOUD_CEIL
