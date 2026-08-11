-- doggiowars/decorate.lua
-- Post-mapgen dekorace: lesy, houby, kaktusy, krystaly, řeky, oheň...

doggiowars = doggiowars or {}

---------------------------------------------------------------------------
-- Pomocníci
---------------------------------------------------------------------------

local function has(name)
    return minetest.registered_nodes[name] ~= nil
end

-- Postav node, jen když cíl je vzduch a node existuje
local function set_if_air(pos, name)
    if not has(name) then return false end
    if minetest.get_node(pos).name == "air" then
        minetest.set_node(pos, {name = name})
        return true
    end
    return false
end

-- První pevný povrch ve sloupci (shora dolů). Vrací y, jméno nodu.
local function surface_y(x, z, island)
    local topfac = 1.2
    if island.shape == "spire" then topfac = 2.5
    elseif island.shape == "cone" then topfac = 1.6 end
    local top = math.floor(island.y + island.radius * topfac + 30)
    local bot = math.floor(island.y - island.radius * 1.6 - 5)
    for y = top, bot, -1 do
        local n = minetest.get_node({x = x, y = y, z = z}).name
        if n ~= "air" and n ~= "ignore" then
            return y, n
        end
    end
    return nil
end

-- Rozptyl count bodů do disku o poloměru radius*rfrac; fn(x, surf_y, z, name)
local function scatter(island, count, rfrac, fn)
    for _ = 1, count do
        local a = math.random() * math.pi * 2
        local r = island.radius * rfrac * math.sqrt(math.random())
        local x = math.floor(island.x + math.cos(a) * r)
        local z = math.floor(island.z + math.sin(a) * r)
        local y, name = surface_y(x, z, island)
        if y then fn(x, y, z, name) end
    end
end

-- Malý balvan (koule z jednoho materiálu) na povrchu
local function place_boulder(x, y, z, name, rad)
    if not has(name) then return end
    for dx = -rad, rad do
        for dy = 0, rad do
            for dz = -rad, rad do
                if dx * dx + dy * dy + dz * dz <= rad * rad + 1 then
                    set_if_air({x = x + dx, y = y + dy, z = z + dz}, name)
                end
            end
        end
    end
end

-- Svislý sloupek (kaktus, papyrus, uschlý kmen)
local function place_column(x, y, z, name, height)
    if not has(name) then return end
    for dy = 1, height do
        if not set_if_air({x = x, y = y + dy, z = z}, name) then break end
    end
end

---------------------------------------------------------------------------
-- Strom (obecný — kmen + koule listí)
---------------------------------------------------------------------------

function doggiowars.place_tree(x, surface_yv, z, trunk, leaf)
    trunk = has(trunk) and trunk or "default:tree"
    leaf  = has(leaf) and leaf or "default:leaves"
    local trunk_h = math.random(4, 7)
    for dy = 1, trunk_h do
        set_if_air({x = x, y = surface_yv + dy, z = z}, trunk)
    end
    local top = surface_yv + trunk_h
    for dx = -2, 2 do
        for dy = -1, 2 do
            for dz = -2, 2 do
                if dx * dx + dy * dy + dz * dz <= 6 then
                    set_if_air({x = x + dx, y = top + dy, z = z + dz}, leaf)
                end
            end
        end
    end
end

-- Akácie — široká plochá koruna (savana)
local function place_acacia(x, y, z)
    local trunk = has("default:acacia_tree") and "default:acacia_tree" or "default:tree"
    local leaf  = has("default:acacia_leaves") and "default:acacia_leaves" or "default:leaves"
    local h = math.random(4, 6)
    for dy = 1, h do
        set_if_air({x = x, y = y + dy, z = z}, trunk)
    end
    local top = y + h
    for dx = -3, 3 do
        for dz = -3, 3 do
            if dx * dx + dz * dz <= 10 then
                set_if_air({x = x + dx, y = top, z = z + dz}, leaf)
                set_if_air({x = x + dx, y = top + 1, z = z + dz}, leaf)
            end
        end
    end
end

-- Uschlý strom — holý kmen s pár pahýly větví
local function place_dead_tree(x, y, z)
    local trunk = has("default:acacia_tree") and "default:acacia_tree" or "default:tree"
    local h = math.random(3, 6)
    for dy = 1, h do
        set_if_air({x = x, y = y + dy, z = z}, trunk)
    end
    local top = y + h
    for _ = 1, math.random(1, 3) do
        local bx = (math.random(0, 1) == 0) and 1 or -1
        set_if_air({x = x + bx, y = top - math.random(0, 1), z = z}, trunk)
    end
end

-- Krystalový trs — svislé svítící krystaly
local function place_crystal_cluster(x, y, z)
    local name = has("doggiowars:crystal") and "doggiowars:crystal" or "default:ice"
    place_column(x, y, z, name, math.random(2, 5))
    for _ = 1, math.random(1, 3) do
        local ox, oz = math.random(-1, 1), math.random(-1, 1)
        place_column(x + ox, y, z + oz, name, math.random(1, 3))
    end
end

---------------------------------------------------------------------------
-- Obří houba (mycelium)
---------------------------------------------------------------------------

function doggiowars.place_giant_mushroom(island)
    local angle = math.random() * math.pi * 2
    local r = math.random(0, math.floor(island.radius * 0.6))
    local mx = math.floor(island.x + math.cos(angle) * r)
    local mz = math.floor(island.z + math.sin(angle) * r)

    local sy = surface_y(mx, mz, island)
    if not sy then return end

    local stem_h = math.random(4, 9)
    for dy = 1, stem_h do
        set_if_air({x = mx, y = sy + dy, z = mz}, "default:tree")
    end

    local cap_r = math.random(2, 4)
    local top = sy + stem_h + 1
    for dx = -cap_r, cap_r do
        for dz = -cap_r, cap_r do
            if dx * dx + dz * dz <= cap_r * cap_r then
                set_if_air({x = mx + dx, y = top, z = mz + dz}, "doggiowars:spore_block")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Rampouchy (ledový biom) — visí z okrajů spodku ostrova
---------------------------------------------------------------------------

function doggiowars.place_icicles(island)
    local count = math.random(6, 16)
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local r = island.radius * (0.7 + math.random() * 0.3)
        local ix = math.floor(island.x + math.cos(angle) * r)
        local iz = math.floor(island.z + math.sin(angle) * r)

        local bottom_y = nil
        for y = island.y, island.y - math.floor(island.radius * 1.5), -1 do
            local node = minetest.get_node({x = ix, y = y, z = iz})
            if node.name ~= "air" and node.name ~= "ignore" then
                bottom_y = y
            elseif bottom_y then
                break
            end
        end
        if not bottom_y then bottom_y = island.y end

        local icicle_len = math.random(3, 8)
        for dy = 1, icicle_len do
            set_if_air({x = ix, y = bottom_y - dy, z = iz}, "doggiowars:ice_crystal")
        end
    end
end

---------------------------------------------------------------------------
-- Zadržená tůň / jezero
---------------------------------------------------------------------------

-- Mělká ZADRŽENÁ tůň: kapalina zarovnaná s povrchem, s těsnícím dnem (y-1)
-- a obvodovým valem, aby na kopcovitém terénu NEPŘETEKLA. mat = dno/val.
local function carve_pond(cx, y, cz, rad, liquid, mat)
    mat = mat or "default:dirt"
    -- vnitřek: voda + pevné dno
    for dx = -rad, rad do
        for dz = -rad, rad do
            if dx * dx + dz * dz <= rad * rad then
                local fb = {x = cx + dx, y = y - 1, z = cz + dz}
                local fn = minetest.get_node(fb).name
                if fn == "air" or fn == "ignore" then
                    minetest.set_node(fb, {name = mat})
                end
                minetest.set_node({x = cx + dx, y = y, z = cz + dz}, {name = liquid})
            end
        end
    end
    -- val: obvodový prstenec — kde je ve výšce vody nebo pod ní díra, zazdít
    for dx = -rad - 1, rad + 1 do
        for dz = -rad - 1, rad + 1 do
            local d2 = dx * dx + dz * dz
            if d2 > rad * rad and d2 <= (rad + 1) * (rad + 1) + 1 then
                for ddy = 0, -1, -1 do
                    local p = {x = cx + dx, y = y + ddy, z = cz + dz}
                    local nn = minetest.get_node(p).name
                    if nn == "air" or nn == "ignore" then
                        minetest.set_node(p, {name = mat})
                    end
                end
            end
        end
    end
end

local function lava_mat()
    return has("doggiowars:basalt") and "doggiowars:basalt" or "default:stone"
end

-- Lávové jezírko (kráter na vrcholu sopky)
function doggiowars.place_lava_pool(island)
    local pool_r = math.random(2, math.max(3, math.floor(island.radius * 0.12)))
    local sy = surface_y(island.x, island.z, island)
    if not sy then return end
    carve_pond(island.x, sy, island.z, pool_r, "default:lava_source", lava_mat())
end

---------------------------------------------------------------------------
-- Sopka: čedičová hora na ostrově s kráterem a lávovým přepadem do údolí.
-- Staví se po vrstvách (minetest.after), ať to necuká.
---------------------------------------------------------------------------

-- Topmost pevný blok v okně kolem očekávané výšky (pro přisednutí k terénu)
local function top_solid(x, z, y_hi, y_lo)
    for y = y_hi, y_lo, -1 do
        local n = minetest.get_node({x = x, y = y, z = z}).name
        if n ~= "air" and n ~= "ignore" then return y end
    end
end

local function finish_volcano(cx, cz, top_y, mr, crater_r, basalt)
    local lava  = "default:lava_source"
    local magma = has("doggiowars:magma_block") and "doggiowars:magma_block" or basalt

    -- Kráter na vrcholu: mísa (hladina lávy na top_y-1, dno top_y-3)
    for dx = -crater_r, crater_r do
        for dz = -crater_r, crater_r do
            if dx * dx + dz * dz <= crater_r * crater_r then
                minetest.set_node({x = cx + dx, y = top_y,     z = cz + dz}, {name = "air"})
                minetest.set_node({x = cx + dx, y = top_y - 1, z = cz + dz}, {name = lava})
                minetest.set_node({x = cx + dx, y = top_y - 2, z = cz + dz}, {name = lava})
                minetest.set_node({x = cx + dx, y = top_y - 3, z = cz + dz}, {name = basalt})
            end
        end
    end

    -- Zvýšený žhavý okraj kráteru (val z magmy) o 1 nad vršek — kromě notche na +X
    for dx = -crater_r - 1, crater_r + 1 do
        for dz = -crater_r - 1, crater_r + 1 do
            local d2 = dx * dx + dz * dz
            if d2 > crater_r * crater_r and d2 <= (crater_r + 1) * (crater_r + 1) + 1 then
                local notch = (dx >= crater_r - 1) and (math.abs(dz) <= 1)
                if not notch then
                    minetest.set_node({x = cx + dx, y = top_y,     z = cz + dz}, {name = magma})
                    minetest.set_node({x = cx + dx, y = top_y + 1, z = cz + dz}, {name = magma})
                end
            end
        end
    end

    -- Přepad (notch) na +X: prořízneme okraj kráteru, ať láva vytéká ven
    for dx = crater_r - 1, crater_r + 3 do
        for dz = -1, 1 do
            minetest.set_node({x = cx + dx, y = top_y,     z = cz + dz}, {name = "air"})
            minetest.set_node({x = cx + dx, y = top_y - 1, z = cz + dz}, {name = lava})
        end
    end

    -- Lávový proud dolů po +X svahu homole (po jejím povrchu) až k úpatí
    for x = cx + crater_r + 1, cx + mr + 2 do
        local sy = top_solid(x, cz, top_y, top_y - mr - 8)
        if not sy then break end
        for dz = -1, 1 do
            minetest.set_node({x = x, y = sy, z = cz + dz}, {name = lava})
        end
        minetest.set_node({x = x, y = sy + 1, z = cz + 2}, {name = basalt})
        minetest.set_node({x = x, y = sy + 1, z = cz - 2}, {name = basalt})
    end

    -- Údolí na úpatí: zadržená lávová tůň
    local vx = cx + mr + 3
    local vy = top_solid(vx, cz, top_y, top_y - mr - 40)
    if vy then
        carve_pond(vx, vy, cz, math.random(3, 5), lava, basalt)
    end
end

function doggiowars.build_volcano(island)
    local cx, cz = island.x, island.z
    local R = island.radius
    local mr = math.max(18, math.min(math.floor(R * 0.42), 34))  -- ŠIROKÁ základna
    local crater_r = math.max(4, math.floor(mr * 0.22))
    local mh = math.max(11, math.floor(mr * 0.5))               -- výška (skutečná homole)
    local basalt = has("doggiowars:basalt") and "doggiowars:basalt" or "default:obsidian"

    -- Robustní základní výška: medián povrchu na prstenci — ignoruje
    -- případnou úzkou šumovou špičku přesně ve středu ostrova.
    local samples = {}
    for a = 0, 7 do
        local ang = a * math.pi / 4
        local sx = cx + math.floor(math.cos(ang) * mr * 0.65)
        local sz = cz + math.floor(math.sin(ang) * mr * 0.65)
        local s = surface_y(sx, sz, island)
        if s then samples[#samples + 1] = s end
    end
    if #samples == 0 then return end
    table.sort(samples)
    local base_y = samples[math.ceil(#samples / 2)]

    -- Kulatá homole (parabolický profil), zarovnaná: každý sloupec vyplníme
    -- od base_y-6 po vrchol kužele a odstraníme terén/špičky nad ním.
    local dx = -mr
    local function row()
        if dx > mr then
            finish_volcano(cx, cz, base_y + mh, mr, crater_r, basalt)
            return
        end
        for dz = -mr, mr do
            local d = math.sqrt(dx * dx + dz * dz)
            if d <= mr then
                local x, z = cx + dx, cz + dz
                -- konkávní profil sopky: malý vršek (kráter) + rozšířená základna
                local h
                if d <= crater_r then
                    h = mh
                else
                    h = math.floor(mh * (1 - (d - crater_r) / (mr - crater_r)) ^ 1.5 + 0.5)
                end
                if h < 0 then h = 0 end
                local coney = base_y + h
                for yy = base_y - 6, coney do
                    minetest.set_node({x = x, y = yy, z = z}, {name = basalt})
                end
                for yy = coney + 1, base_y + mh + mr + 8 do
                    local n = minetest.get_node({x = x, y = yy, z = z}).name
                    if n == "air" then break end
                    if n ~= "ignore" then
                        minetest.set_node({x = x, y = yy, z = z}, {name = "air"})
                    end
                end
            end
        end
        dx = dx + 1
        minetest.after(0, row)
    end
    row()
end

---------------------------------------------------------------------------
-- Zaplavení středu atolu vodou
---------------------------------------------------------------------------

function doggiowars.fill_atoll_center(island)
    local hole_r = math.max(3, math.floor(island.radius * 0.3))
    local sy = surface_y(island.x, island.z, island)
    if not sy then return end
    carve_pond(island.x, sy, island.z, hole_r, "default:water_source", "default:sand")
end

---------------------------------------------------------------------------
-- Vodopád z okraje (sloupec padající vody dolů)
---------------------------------------------------------------------------

local function waterfall_at(ix, iz, island, water)
    water = has(water) and water or "default:water_flowing"
    local top_y = surface_y(ix, iz, island)
    if not top_y then return end
    for y = top_y + 1, top_y - 34, -1 do
        local pos = {x = ix, y = y, z = iz}
        local node = minetest.get_node(pos)
        if node.name == "air" then
            minetest.set_node(pos, {name = water})
        elseif y < top_y then
            break
        end
    end
end

function doggiowars.place_waterfall(island)
    local angle = math.random() * math.pi * 2
    local ex = math.floor(island.x + math.cos(angle) * (island.radius - 2))
    local ez = math.floor(island.z + math.sin(angle) * (island.radius - 2))
    waterfall_at(ex, ez, island, "default:water_flowing")
end

---------------------------------------------------------------------------
-- Řeka — meandrující kanál od středu k okraji, zakončený vodopádem
---------------------------------------------------------------------------

function doggiowars.place_river(island)
    local water = has("default:river_water_source")
        and "default:river_water_source" or "default:water_source"
    local flow = has("default:river_water_flowing")
        and "default:river_water_flowing" or "default:water_flowing"

    local ang = math.random() * math.pi * 2
    local x, z = island.x + 0.0, island.z + 0.0
    local steps = math.floor(island.radius * 1.4)

    for _ = 1, steps do
        ang = ang + (math.random() - 0.5) * 0.6
        local dirx, dirz = math.cos(ang), math.sin(ang)
        x = x + dirx
        z = z + dirz
        local ix, iz = math.floor(x), math.floor(z)

        local sy = surface_y(ix, iz, island)
        if not sy then break end

        -- vyhloubit koryto (šířka 3) a naplnit vodou
        for w = -1, 1 do
            local px = ix + math.floor(-dirz * w + 0.5)
            local pz = iz + math.floor(dirx * w + 0.5)
            local syw = surface_y(px, pz, island) or sy
            minetest.set_node({x = px, y = syw, z = pz}, {name = water})
        end

        local dcx, dcz = ix - island.x, iz - island.z
        if math.sqrt(dcx * dcx + dcz * dcz) > island.radius * 0.85 then
            waterfall_at(ix, iz, island, flow)
            break
        end
    end
end

---------------------------------------------------------------------------
-- Rozptýlené rostliny / drobnosti (guardované, ať nespadnou na chybějícím modu)
---------------------------------------------------------------------------

local FLOWERS = {
    "flowers:rose", "flowers:tulip", "flowers:dandelion_yellow",
    "flowers:dandelion_white", "flowers:geranium", "flowers:viola",
}

local function plant_one(x, y, z, names)
    local name = names[math.random(1, #names)]
    set_if_air({x = x, y = y + 1, z = z}, name)
end

---------------------------------------------------------------------------
-- Hlavní dispatch dekorace
---------------------------------------------------------------------------

local VERDANT_TREES = {
    {"default:tree", "default:leaves"},
    {"default:aspen_tree", "default:aspen_leaves"},
    {"default:pine_tree", "default:pine_needles"},
}

-- Travní podrost, kapradí, suché traviny (více variant = živější povrch)
local GRASS     = {"default:grass_1", "default:grass_2", "default:grass_3",
                   "default:grass_4", "default:grass_5"}
local DRY_GRASS = {"default:dry_grass_1", "default:dry_grass_2", "default:dry_grass_3",
                   "default:dry_grass_4", "default:dry_grass_5"}
local FERNS     = {"default:fern_1", "default:fern_2", "default:fern_3"}
local MARRAM    = {"default:marram_grass_1", "default:marram_grass_2", "default:marram_grass_3"}

-- Malý keř: nízký kmínek + koule listí (i bobulový)
local function place_bush(x, y, z, leaf)
    if not has(leaf) then return end
    local stem = has("default:bush_stem") and "default:bush_stem" or nil
    if stem then set_if_air({x = x, y = y + 1, z = z}, stem) end
    local base = stem and (y + 2) or (y + 1)
    for dx = -1, 1 do
        for dz = -1, 1 do
            set_if_air({x = x + dx, y = base, z = z + dz}, leaf)
        end
    end
    set_if_air({x = x, y = base + 1, z = z}, leaf)
end


-- Povrch VE SVISLÉM ROZSAHU tohoto chunku (rychlé — jen [y_bot..y_top]).
-- Vrací y, jméno; nil když povrch není v tomto chunku (řeší sousední chunk).
local function surface_col(x, z, y_top, y_bot)
    local above = minetest.get_node({x = x, y = y_top + 1, z = z}).name
    for y = y_top, y_bot, -1 do
        local n = minetest.get_node({x = x, y = y, z = z}).name
        if n ~= "air" and n ~= "ignore" then
            if above == "air" then return y, n end
            return nil
        end
        above = n
    end
    return nil
end

local JUNGLE_GROUND = {"default:junglegrass", "default:fern_1", "default:fern_2", "default:fern_3"}
local SWAMP_MUSH    = {"flowers:mushroom_red", "flowers:mushroom_brown"}

-- Umísti JEDEN prvek na povrch (x,y,z) podle biomu. Biomy jsou bujné —
-- podrost (tráva/kapradí) je hustý, květin je hodně. "name" = povrch pod ním.
local function place_feature(kind, x, y, z, name, island)
    local r = math.random(100)

    if kind == "verdant" then
        if r <= 42 then plant_one(x, y, z, GRASS)
        elseif r <= 68 then plant_one(x, y, z, FLOWERS)
        elseif r <= 77 then
            local t = VERDANT_TREES[math.random(#VERDANT_TREES)]
            doggiowars.place_tree(x, y, z, t[1], t[2])
        elseif r <= 83 then place_bush(x, y, z, "default:bush_leaves")
        elseif r <= 87 then place_bush(x, y, z, "default:blueberry_bush_leaves_with_berries")
        elseif r <= 90 then plant_one(x, y, z, SWAMP_MUSH)
        end

    elseif kind == "jungle" then
        if r <= 38 then plant_one(x, y, z, JUNGLE_GROUND)
        elseif r <= 56 then
            doggiowars.place_tree(x, y, z, "default:jungletree", "default:jungleleaves")
        elseif r <= 68 then
            if name ~= "default:water_source" then
                place_column(x, y, z, "default:papyrus", math.random(2, 4))
            end
        elseif r <= 77 then place_bush(x, y, z, "default:jungleleaves")
        elseif r <= 86 then plant_one(x, y, z, FLOWERS)
        end

    elseif kind == "glacial" then
        if r <= 30 then place_column(x, y, z, "doggiowars:ice_crystal", math.random(1, 3))
        elseif r <= 46 then set_if_air({x = x, y = y + 1, z = z}, "default:snow")
        elseif r <= 58 then place_boulder(x, y, z, "default:ice", math.random(1, 2))
        elseif r <= 64 then place_boulder(x, y, z, "default:cave_ice", 1)
        end

    elseif kind == "crystal" then
        if r <= 34 then place_crystal_cluster(x, y, z)
        elseif r <= 46 then
            set_if_air({x = x, y = y + 1, z = z},
                has("doggiowars:crystal") and "doggiowars:crystal" or "default:ice")
        elseif r <= 56 then place_boulder(x, y, z, "default:silver_sandstone", math.random(1, 2))
        end

    elseif kind == "volcanic" then
        if r <= 22 then set_if_air({x = x, y = y + 1, z = z}, "doggiowars:embers")
        elseif r <= 34 then place_boulder(x, y, z, "doggiowars:basalt", math.random(1, 2))
        elseif r <= 42 then set_if_air({x = x, y = y + 1, z = z}, "fire:basic_flame")
        elseif r <= 48 then carve_pond(x, y, z, math.random(1, 2), "default:lava_source", lava_mat())
        end

    elseif kind == "ashen" then
        if r <= 14 then place_dead_tree(x, y, z)
        elseif r <= 40 then set_if_air({x = x, y = y + 1, z = z}, "doggiowars:embers")
        elseif r <= 52 then set_if_air({x = x, y = y + 1, z = z}, "fire:basic_flame")
        elseif r <= 58 then carve_pond(x, y, z, 1, "default:lava_source", lava_mat())
        elseif r <= 66 then set_if_air({x = x, y = y + 1, z = z}, "default:dry_shrub")
        end

    elseif kind == "atoll" then
        if name == "default:water_source" then
            if r <= 55 then set_if_air({x = x, y = y + 1, z = z}, "flowers:waterlily") end
        elseif r <= 30 then plant_one(x, y, z, MARRAM)
        elseif r <= 40 then place_column(x, y, z, "default:papyrus", math.random(2, 3))
        elseif r <= 48 then place_boulder(x, y, z, "default:coral_skeleton", 1)
        elseif r <= 58 then carve_pond(x, y, z, math.random(1, 2), "default:water_source", "default:sand")
        end

    elseif kind == "swamp" then
        if name == "default:water_source" then
            if r <= 55 then set_if_air({x = x, y = y + 1, z = z}, "flowers:waterlily") end
        elseif r <= 22 then
            carve_pond(x, y, z, math.random(1, 2), "default:water_source",
                has("doggiowars:mud") and "doggiowars:mud" or "default:dirt")
        elseif r <= 42 then place_column(x, y, z, "default:papyrus", math.random(2, 4))
        elseif r <= 56 then plant_one(x, y, z, SWAMP_MUSH)
        elseif r <= 66 then plant_one(x, y, z, FERNS)
        elseif r <= 72 then place_boulder(x, y, z, "doggiowars:mossy_stone", math.random(1, 2))
        end

    elseif kind == "desert" then
        if r <= 14 then place_column(x, y, z, "default:cactus", math.random(2, 4))
        elseif r <= 40 then set_if_air({x = x, y = y + 1, z = z}, "default:dry_shrub")
        elseif r <= 55 then plant_one(x, y, z, DRY_GRASS)
        elseif r <= 62 then place_boulder(x, y, z, "default:desert_sandstone", math.random(1, 2))
        end

    elseif kind == "savanna" then
        if r <= 8 then place_acacia(x, y, z)
        elseif r <= 55 then plant_one(x, y, z, DRY_GRASS)
        elseif r <= 68 then set_if_air({x = x, y = y + 1, z = z}, "default:dry_shrub")
        elseif r <= 73 then place_bush(x, y, z, "default:acacia_bush_leaves")
        end

    elseif kind == "mycelial" then
        if r <= 40 then plant_one(x, y, z, SWAMP_MUSH)
        elseif r <= 55 then plant_one(x, y, z, FERNS)
        end

    elseif kind == "barren" then
        if r <= 12 then place_boulder(x, y, z, "default:stone", math.random(1, 2))
        elseif r <= 20 then place_boulder(x, y, z, "default:gravel", 1)
        elseif r <= 32 then set_if_air({x = x, y = y + 1, z = z}, "default:dry_shrub")
        end
    end
end

---------------------------------------------------------------------------
-- Dekorace ČÁSTI ostrova v tomto chunku (jen na už načtený terén)
---------------------------------------------------------------------------

-- Ostrovy, které už dostaly globální prvky (řeka, laguna, sopka...)
local global_done = {}

function doggiowars.decorate_chunk(island, minp, maxp)
    local biome = island.biome
    if not biome then return end
    local kind = biome.decor or biome.name
    local R = island.radius

    local x0 = math.max(minp.x, math.floor(island.x - R))
    local x1 = math.min(maxp.x, math.ceil(island.x + R))
    local z0 = math.max(minp.z, math.floor(island.z - R))
    local z1 = math.min(maxp.z, math.ceil(island.z + R))
    if x1 < x0 or z1 < z0 then return end

    local area = (x1 - x0 + 1) * (z1 - z0 + 1)
    local n = math.max(6, math.min(300, math.floor(area / 22)))  -- hustý podrost
    local R2 = R * R
    local ytop, ybot = maxp.y, minp.y

    -- Globální prvky: spustí se přesně v chunku, kde je NAČTENÝ povrch nad
    -- středem ostrova (řeka/laguna/sopka/houby/rampouchy potřebují střed).
    local function try_global()
        if island.x >= minp.x and island.x <= maxp.x
                and island.z >= minp.z and island.z <= maxp.z then
            local key = math.floor(island.x / doggiowars.ISLAND_GRID) .. ":"
                     .. math.floor(island.z / doggiowars.ISLAND_GRID)
            if not global_done[key] and surface_col(island.x, island.z, ytop, ybot) then
                global_done[key] = true
                doggiowars.decorate_global(island)
            end
        end
    end

    -- Dávkově (max ~60 vzorků na snímek), ať rychlý let necuká
    local done = 0
    local function step()
        local budget = 0
        while done < n and budget < 60 do
            done = done + 1
            budget = budget + 1
            local x = math.random(x0, x1)
            local z = math.random(z0, z1)
            local dx, dz = x - island.x, z - island.z
            if dx * dx + dz * dz <= R2 then
                local y, name = surface_col(x, z, ytop, ybot)
                if y then
                    place_feature(kind, x, y, z, name, island)
                end
            end
        end
        if done < n then
            minetest.after(0, step)
        else
            try_global()
        end
    end
    step()
end

---------------------------------------------------------------------------
-- Globální prvky ukotvené ke středu ostrova (jednou za ostrov)
---------------------------------------------------------------------------

function doggiowars.decorate_global(island)
    local biome = island.biome
    if not biome then return end
    local kind = biome.decor or biome.name
    local R = island.radius

    if kind == "verdant" then
        if R > 90 and math.random() < 0.5 then doggiowars.place_river(island) end
        if math.random() < 0.3 then doggiowars.place_waterfall(island) end
    elseif kind == "jungle" then
        if R > 90 and math.random() < 0.5 then doggiowars.place_river(island) end
        if math.random() < 0.25 then doggiowars.place_waterfall(island) end
    elseif kind == "volcanic" then
        doggiowars.build_volcano(island)
    elseif kind == "atoll" then
        doggiowars.fill_atoll_center(island)
    elseif kind == "glacial" then
        doggiowars.place_icicles(island)
    elseif kind == "mycelial" then
        for _ = 1, math.random(3, 8) do
            doggiowars.place_giant_mushroom(island)
        end
    end
end

-- Kompletní dekorace celého ostrova naráz (pro testy / ruční použití)
function doggiowars.decorate_island(island)
    local biome = island.biome
    if not biome then return end
    local kind = biome.decor or biome.name
    doggiowars.decorate_global(island)
    local n = math.max(20, math.floor(island.radius * island.radius * 0.02))
    for _ = 1, n do
        local a = math.random() * math.pi * 2
        local r = island.radius * math.sqrt(math.random())
        local x = math.floor(island.x + math.cos(a) * r)
        local z = math.floor(island.z + math.sin(a) * r)
        local y, name = surface_y(x, z, island)
        if y then
            place_feature(kind, x, y, z, name, island)
        end
    end
end

---------------------------------------------------------------------------
-- Hook do mapgenu — dekorace až po zapsání terénu
---------------------------------------------------------------------------

minetest.register_on_generated(function(minp, maxp, blockseed)
    local lo = doggiowars.CLOUD_FLOOR or -500
    local hi = doggiowars.CLOUD_CEIL or 1500
    if maxp.y < lo or minp.y > hi then return end

    -- POZOR: seed vždy přes get_world_seed() — skládá u64 seed bez ztráty
    -- přesnosti. Lokální tonumber() by u velkých seedů našel JINÉ (fantomové)
    -- ostrovy než mapgen a dekorace by minuly skutečný terén.
    local seed = doggiowars.get_world_seed()
    local islands = doggiowars.get_islands_for_chunk(minp, maxp, seed)
    if #islands == 0 then return end

    -- Chvilka po zapsání terénu, ať get_node vidí bloky tohoto chunku
    minetest.after(0.4, function()
        for _, island in ipairs(islands) do
            doggiowars.decorate_chunk(island, minp, maxp)
        end
    end)
end)
