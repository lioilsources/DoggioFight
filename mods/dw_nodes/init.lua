-- dw_nodes — nody, ze kterých DoggioWars staví terén
--
-- Kdysi to byly nody z minetest_game (default:*, flowers:*, fire:*). Hra je
-- nebalí — kód by byl LGPL 2.1 a média CC BY-SA 3.0 — a od té doby si je
-- registruje sama. Všechno teď žije ve VLASTNÍM jmenném prostoru
-- `dw_nodes:`, protože zapisovat položky do cizího namespace je něco, na co
-- se recenzenti ContentDB ptají, a hra na to nemá žádný nárok.
--
-- Stará jména zůstávají jako aliasy (register_alias dole), takže světy
-- uložené dřív se načtou beze změny.
--
-- Textury generuje tools/gen_textures.py — proceduálně, ze standardní
-- knihovny, deterministicky. Přegenerování: python3 tools/gen_textures.py

-- čistě přiřazení: `dw_nodes or {}` by globál nejdřív ČETL a Luanti
-- to hlásí jako přístup k nedeklarované globální proměnné
dw_nodes = {}

local S = minetest.get_translator("dw_nodes")

-- Stará jména pro aliasy: krátké jméno -> jmenný prostor, ze kterého node
-- historicky pocházel
local LEGACY_NS = {}

local function reg(short, def, legacy_ns)
    minetest.register_node("dw_nodes:" .. short, def)
    LEGACY_NS[short] = legacy_ns or "default"
end

---------------------------------------------------------------------------
-- Zvukové helpery
--
-- nodes.lua je volal jako default.node_sound_*_defaults() — globální
-- tabulka minetest_game, kterou grep po "default:" nenašel a hra na ní
-- padala. Teď je to naše vlastní tabulka. Hra nebalí žádné zvuky, takže
-- vracejí prázdný popis a nody mlčí; až nějaké zvuky přibudou, mění se to
-- na jednom místě.
---------------------------------------------------------------------------

local function silent(tbl)
    return tbl or {}
end

for _, kind in ipairs({"stone", "dirt", "sand", "glass", "wood",
                       "leaves", "gravel", "snow", "water", "metal"}) do
    dw_nodes["node_sound_" .. kind .. "_defaults"] = silent
end
dw_nodes.node_sound_defaults = silent

---------------------------------------------------------------------------
-- Pevné nody
---------------------------------------------------------------------------

-- {jméno, textura, popis, tvrdost}
local SOLIDS = {
    {"stone",            "stone",            "Stone",            3},
    {"desert_stone",     "desert_stone",     "Desert Stone",     3},
    {"sandstone",        "sandstone",        "Sandstone",        2},
    {"desert_sandstone", "desert_sandstone", "Desert Sandstone", 2},
    {"silver_sandstone", "silver_sandstone", "Silver Sandstone", 2},
    {"obsidian",         "obsidian",         "Obsidian",         3},
    {"clay",             "clay",             "Clay",             3},
    {"permafrost",       "permafrost",       "Permafrost",       3},
    {"coral_skeleton",   "coral_skeleton",   "Coral Skeleton",   3},
}

for _, s in ipairs(SOLIDS) do
    reg(s[1], {
        description = S(s[3]),
        tiles = {"dwn_" .. s[2] .. ".png"},
        groups = {cracky = s[4], stone = 1},
        is_ground_content = true,
    })
end

-- Sypké: písky, zeminy, štěrk, sníh
local LOOSE = {
    {"sand",        "sand",        "Sand",         2},
    {"desert_sand", "desert_sand", "Desert Sand",  2},
    {"silver_sand", "silver_sand", "Silver Sand",  2},
    {"dirt",        "dirt",        "Dirt",         3},
    {"dry_dirt",    "dry_dirt",    "Dry Dirt",     3},
    {"gravel",      "gravel",      "Gravel",       2},
    {"snowblock",   "snowblock",   "Snow Block",   3},
    {"snow",        "snow",        "Snow",         3},
}

for _, s in ipairs(LOOSE) do
    reg(s[1], {
        description = S(s[3]),
        tiles = {"dwn_" .. s[2] .. ".png"},
        groups = {crumbly = s[4], falling_node = 1},
        is_ground_content = true,
    })
end

-- Zemina s porostem — boční textura má travní pruh nahoře
local COVERED = {
    {"dirt_with_grass",             "grass_top",
     "grass_side",     "Dirt with Grass"},
    {"dirt_with_dry_grass",         "dry_grass_top",
     "dry_grass_side", "Dirt with Dry Grass"},
    {"dirt_with_rainforest_litter", "rainforest_litter_top",
     "litter_side",    "Dirt with Rainforest Litter"},
}

for _, s in ipairs(COVERED) do
    reg(s[1], {
        description = S(s[4]),
        tiles = {
            "dwn_" .. s[2] .. ".png",
            "dwn_dirt.png",
            "dwn_" .. s[3] .. ".png",
        },
        groups = {crumbly = 3, soil = 1},
        is_ground_content = true,
    })
end

-- Led: průsvitný, ať je vidět dovnitř ledovcových ostrovů
for _, s in ipairs({{"ice", "ice", "Ice"},
                    {"cave_ice", "cave_ice", "Cave Ice"}}) do
    reg(s[1], {
        description = S(s[3]),
        tiles = {"dwn_" .. s[2] .. ".png"},
        use_texture_alpha = "blend",
        paramtype = "light",
        sunlight_propagates = true,
        groups = {cracky = 3, cools_lava = 1, slippery = 3},
        is_ground_content = true,
    })
end

---------------------------------------------------------------------------
-- Stromy a listí
---------------------------------------------------------------------------

local TREES = {
    {"tree",        "tree",        "Tree"},
    {"jungletree",  "jungletree",  "Jungle Tree"},
    {"pine_tree",   "pine_tree",   "Pine Tree"},
    {"aspen_tree",  "aspen_tree",  "Aspen Tree"},
    {"acacia_tree", "acacia_tree", "Acacia Tree"},
    {"bush_stem",   "bush_stem",   "Bush Stem"},
}

for _, s in ipairs(TREES) do
    reg(s[1], {
        description = S(s[3]),
        -- pořadí: nahoře, dole, boky → řez kmenem nahoře i dole
        tiles = {
            "dwn_" .. s[2] .. "_top.png",
            "dwn_" .. s[2] .. "_top.png",
            "dwn_" .. s[2] .. ".png",
        },
        paramtype2 = "facedir",
        on_place = minetest.rotate_node,
        groups = {choppy = 2, tree = 1, flammable = 2},
        is_ground_content = false,
    })
end

local LEAVES = {
    {"leaves",            "leaves",            "Leaves"},
    {"jungleleaves",      "jungleleaves",      "Jungle Leaves"},
    {"pine_needles",      "pine_needles",      "Pine Needles"},
    {"aspen_leaves",      "aspen_leaves",      "Aspen Leaves"},
    {"acacia_leaves",     "acacia_leaves",     "Acacia Leaves"},
    {"bush_leaves",       "bush_leaves",       "Bush Leaves"},
    {"acacia_bush_leaves","acacia_bush_leaves","Acacia Bush Leaves"},
    {"blueberry_bush_leaves_with_berries", "blueberry_leaves",
     "Blueberry Bush with Berries"},
}

for _, s in ipairs(LEAVES) do
    reg(s[1], {
        description = S(s[3]),
        drawtype = "allfaces_optional",
        tiles = {"dwn_" .. s[2] .. ".png"},
        use_texture_alpha = "clip",
        paramtype = "light",
        waving = 1,
        groups = {snappy = 3, leaves = 1, flammable = 2},
        is_ground_content = false,
    })
end

-- Kaktus je pevný, ale s vlastními boky
reg("cactus", {
    description = S("Cactus"),
    tiles = {"dwn_cactus_top.png", "dwn_cactus_top.png", "dwn_cactus_side.png"},
    paramtype2 = "facedir",
    groups = {choppy = 3},
    damage_per_second = 1,
    is_ground_content = false,
})

---------------------------------------------------------------------------
-- Rostliny (plantlike) — neprůchozí kolizi nemají, jsou to jen kulisy
---------------------------------------------------------------------------

local PLANTS = {
    "grass_1", "grass_2", "grass_3", "grass_4", "grass_5",
    "dry_grass_1", "dry_grass_2", "dry_grass_3", "dry_grass_4", "dry_grass_5",
    "fern_1", "fern_2", "fern_3",
    "marram_grass_1", "marram_grass_2", "marram_grass_3",
    "junglegrass", "dry_shrub",
}

local function plant(name, tex, desc, extra, legacy_ns)
    local def = {
        description = S(desc),
        drawtype = "plantlike",
        tiles = {"dwn_" .. tex .. ".png"},
        inventory_image = "dwn_" .. tex .. ".png",
        wield_image = "dwn_" .. tex .. ".png",
        paramtype = "light",
        sunlight_propagates = true,
        walkable = false,
        buildable_to = true,
        waving = 1,
        groups = {snappy = 3, flora = 1, attached_node = 1, flammable = 1},
        selection_box = {
            type = "fixed",
            fixed = {-0.35, -0.5, -0.35, 0.35, 0.1, 0.35},
        },
    }
    for k, v in pairs(extra or {}) do def[k] = v end
    reg(name, def, legacy_ns)
end

for _, p in ipairs(PLANTS) do
    local label = p:gsub("_", " "):gsub("^%l", string.upper)
    plant(p, p, label)
end

-- Papyrus roste do sloupků, takže musí mít vlastní výšku výběru
plant("papyrus", "papyrus", "Papyrus", {
    selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 0.5, 0.3}},
    groups = {snappy = 3, flammable = 2},
})

---------------------------------------------------------------------------
-- Květiny a houby
---------------------------------------------------------------------------

local FLOWERS = {
    {"rose",             "rose",             "Red Rose"},
    {"tulip",            "tulip",            "Orange Tulip"},
    {"viola",            "viola",            "Viola"},
    {"geranium",         "geranium",         "Blue Geranium"},
    {"dandelion_yellow", "dandelion_yellow", "Yellow Dandelion"},
    {"dandelion_white",  "dandelion_white",  "White Dandelion"},
    {"mushroom_red",     "mushroom_red",     "Red Mushroom"},
    {"mushroom_brown",   "mushroom_brown",   "Brown Mushroom"},
}

for _, f in ipairs(FLOWERS) do
    plant(f[1], f[2], f[3], nil, "flowers")
end

-- Leknín leží na hladině — plochý nodebox, ne stéblo
reg("waterlily", {
    description = S("Waterlily"),
    drawtype = "nodebox",
    tiles = {"dwn_waterlily.png"},
    inventory_image = "dwn_waterlily.png",
    use_texture_alpha = "clip",
    paramtype = "light",
    paramtype2 = "facedir",
    sunlight_propagates = true,
    walkable = false,
    buildable_to = true,
    groups = {snappy = 3, flower = 1},
    node_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}},
    selection_box = {type = "fixed", fixed = {-0.5, -0.5, -0.5, 0.5, -0.4375, 0.5}},
}, "flowers")

---------------------------------------------------------------------------
-- Kapaliny
---------------------------------------------------------------------------

-- Zdroj i tekoucí varianta se musí registrovat v páru, jinak
-- vm:update_liquids() v mapgenu nemá co roztéct.
local function liquid_pair(base, tex, opts)
    opts = opts or {}
    local common = {
        paramtype = "light",
        walkable = false,
        pointable = false,
        diggable = false,
        buildable_to = true,
        is_ground_content = false,
        drowning = opts.drowning,
        damage_per_second = opts.dps,
        light_source = opts.light,
        post_effect_color = opts.post,
        liquid_viscosity = opts.viscosity or 1,
        liquid_alternative_flowing = "dw_nodes:" .. base .. "_flowing",
        liquid_alternative_source = "dw_nodes:" .. base .. "_source",
        liquid_renewable = opts.renewable ~= false,
        use_texture_alpha = "blend",
        groups = opts.groups or {},
    }

    local src = {drawtype = "liquid", liquidtype = "source",
                 tiles = {"dwn_" .. tex .. ".png"},
                 description = S(opts.desc or "Liquid")}
    local flow = {drawtype = "flowingliquid", liquidtype = "flowing",
                  tiles = {"dwn_" .. tex .. ".png"},
                  special_tiles = {
                      {name = "dwn_" .. tex .. "_flow.png",
                       backface_culling = false},
                      {name = "dwn_" .. tex .. "_flow.png",
                       backface_culling = true},
                  },
                  paramtype2 = "flowingliquid",
                  description = S((opts.desc or "Liquid") .. " Flowing")}
    for k, v in pairs(common) do src[k] = v; flow[k] = v end
    flow.groups = {}
    for k, v in pairs(common.groups) do flow.groups[k] = v end
    flow.groups.not_in_creative_inventory = 1

    reg(base .. "_source", src)
    reg(base .. "_flowing", flow)
end

liquid_pair("water", "water", {
    desc = "Water", drowning = 1, viscosity = 1,
    post = {a = 103, r = 30, g = 60, b = 90},
    groups = {water = 3, liquid = 3, cools_lava = 1},
})

liquid_pair("river_water", "river_water", {
    desc = "River Water", drowning = 1, viscosity = 1, renewable = false,
    post = {a = 103, r = 30, g = 76, b = 90},
    groups = {water = 3, liquid = 3, cools_lava = 1},
})

liquid_pair("lava", "lava", {
    desc = "Lava", dps = 4, light = 13, viscosity = 7, renewable = false,
    post = {a = 191, r = 255, g = 64, b = 0},
    groups = {lava = 3, liquid = 2, igniter = 1},
})

---------------------------------------------------------------------------
-- Oheň — jen dekorace nad sopkami, nešíří se
---------------------------------------------------------------------------

reg("basic_flame", {
    description = S("Fire"),
    drawtype = "firelike",
    tiles = {"dwn_basic_flame.png"},
    inventory_image = "dwn_basic_flame.png",
    use_texture_alpha = "clip",
    paramtype = "light",
    light_source = 13,
    walkable = false,
    pointable = false,
    buildable_to = true,
    damage_per_second = 4,
    sunlight_propagates = true,
    floodable = true,
    groups = {igniter = 2, not_in_creative_inventory = 1},
    on_flood = function(pos)
        minetest.remove_node(pos)
        return false
    end,
}, "fire")

---------------------------------------------------------------------------
-- Aliasy na historická jména
--
-- Světy uložené verzí, která ještě stavěla z default:*/flowers:*/fire:*,
-- se díky tomu načtou beze změny — engine si alias přeloží při načtení
-- bloku. V registered_nodes se aliasy NEobjeví, takže nový kód je smí
-- používat jen přes dw_nodes:.
---------------------------------------------------------------------------

local aliased = 0
for short, ns in pairs(LEGACY_NS) do
    minetest.register_alias(ns .. ":" .. short, "dw_nodes:" .. short)
    aliased = aliased + 1
end

minetest.log("action", ("[dw_nodes] %d nodes registered, %d legacy aliases")
    :format(aliased, aliased))
