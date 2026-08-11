-- dw_nodes — náhrada nodů z minetest_game
--
-- DoggioWars staví terén z nodů pojmenovaných default:*, flowers:* a
-- fire:basic_flame. Aby hra nemusela balit minetest_game (LGPL 2.1 kód +
-- CC BY-SA 3.0 média), registrujeme si těch ~70 nodů sami, pod stejnými
-- jmény — volající kód v biomes.lua a decorate.lua se tak nemění ani na
-- jednom ze 123 míst.
--
-- Jména v cizím jmenném prostoru se zapisují s ÚVODNÍ DVOJTEČKOU;
-- bez ní by je Luanti odmítl ("modname: prefix required").
--
-- Textury generuje tools/gen_textures.py — proceduálně, ze standardní
-- knihovny, deterministicky. Přegenerování: python3 tools/gen_textures.py

local S = function(t) return t end     -- místo pro budoucí překlady

local function reg(name, def)
    minetest.register_node(":" .. name, def)
end

---------------------------------------------------------------------------
-- Lua API `default`
--
-- nodes.lua volá default.node_sound_*_defaults() — to není jméno nodu, ale
-- globální tabulka z minetest_game, takže ji grep po "default:" nenašel a
-- hra na ní bez shimu spadne. DoggioWars nebalí žádné zvuky, takže funkce
-- vracejí prázdný popis a nody prostě mlčí.
---------------------------------------------------------------------------

default = default or {}

local function silent(tbl)
    return tbl or {}
end

for _, kind in ipairs({"stone", "dirt", "sand", "glass", "wood",
                       "leaves", "gravel", "snow", "water", "metal"}) do
    default["node_sound_" .. kind .. "_defaults"] = silent
end
default.node_sound_defaults = silent

---------------------------------------------------------------------------
-- Pevné nody
---------------------------------------------------------------------------

-- {jméno, textura, popis, tvrdost}
local SOLIDS = {
    {"default:stone",            "stone",            "Stone",            3},
    {"default:desert_stone",     "desert_stone",     "Desert Stone",     3},
    {"default:sandstone",        "sandstone",        "Sandstone",        2},
    {"default:desert_sandstone", "desert_sandstone", "Desert Sandstone", 2},
    {"default:silver_sandstone", "silver_sandstone", "Silver Sandstone", 2},
    {"default:obsidian",         "obsidian",         "Obsidian",         3},
    {"default:clay",             "clay",             "Clay",             3},
    {"default:permafrost",       "permafrost",       "Permafrost",       3},
    {"default:coral_skeleton",   "coral_skeleton",   "Coral Skeleton",   3},
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
    {"default:sand",        "sand",        "Sand",         2},
    {"default:desert_sand", "desert_sand", "Desert Sand",  2},
    {"default:silver_sand", "silver_sand", "Silver Sand",  2},
    {"default:dirt",        "dirt",        "Dirt",         3},
    {"default:dry_dirt",    "dry_dirt",    "Dry Dirt",     3},
    {"default:gravel",      "gravel",      "Gravel",       2},
    {"default:snowblock",   "snowblock",   "Snow Block",   3},
    {"default:snow",        "snow",        "Snow",         3},
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
    {"default:dirt_with_grass",             "grass_top",
     "grass_side",     "Dirt with Grass"},
    {"default:dirt_with_dry_grass",         "dry_grass_top",
     "dry_grass_side", "Dirt with Dry Grass"},
    {"default:dirt_with_rainforest_litter", "rainforest_litter_top",
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
for _, s in ipairs({{"default:ice", "ice", "Ice"},
                    {"default:cave_ice", "cave_ice", "Cave Ice"}}) do
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
    {"default:tree",        "tree",        "Tree"},
    {"default:jungletree",  "jungletree",  "Jungle Tree"},
    {"default:pine_tree",   "pine_tree",   "Pine Tree"},
    {"default:aspen_tree",  "aspen_tree",  "Aspen Tree"},
    {"default:acacia_tree", "acacia_tree", "Acacia Tree"},
    {"default:bush_stem",   "bush_stem",   "Bush Stem"},
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
    {"default:leaves",            "leaves",            "Leaves"},
    {"default:jungleleaves",      "jungleleaves",      "Jungle Leaves"},
    {"default:pine_needles",      "pine_needles",      "Pine Needles"},
    {"default:aspen_leaves",      "aspen_leaves",      "Aspen Leaves"},
    {"default:acacia_leaves",     "acacia_leaves",     "Acacia Leaves"},
    {"default:bush_leaves",       "bush_leaves",       "Bush Leaves"},
    {"default:acacia_bush_leaves","acacia_bush_leaves","Acacia Bush Leaves"},
    {"default:blueberry_bush_leaves_with_berries", "blueberry_leaves",
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
reg("default:cactus", {
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

local function plant(name, tex, desc, extra)
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
    reg(name, def)
end

for _, p in ipairs(PLANTS) do
    local label = p:gsub("_", " "):gsub("^%l", string.upper)
    plant("default:" .. p, p, label)
end

-- Papyrus roste do sloupků, takže musí mít vlastní výšku výběru
plant("default:papyrus", "papyrus", "Papyrus", {
    selection_box = {type = "fixed", fixed = {-0.3, -0.5, -0.3, 0.3, 0.5, 0.3}},
    groups = {snappy = 3, flammable = 2},
})

---------------------------------------------------------------------------
-- Květiny a houby
---------------------------------------------------------------------------

local FLOWERS = {
    {"flowers:rose",             "rose",             "Red Rose"},
    {"flowers:tulip",            "tulip",            "Orange Tulip"},
    {"flowers:viola",            "viola",            "Viola"},
    {"flowers:geranium",         "geranium",         "Blue Geranium"},
    {"flowers:dandelion_yellow", "dandelion_yellow", "Yellow Dandelion"},
    {"flowers:dandelion_white",  "dandelion_white",  "White Dandelion"},
    {"flowers:mushroom_red",     "mushroom_red",     "Red Mushroom"},
    {"flowers:mushroom_brown",   "mushroom_brown",   "Brown Mushroom"},
}

for _, f in ipairs(FLOWERS) do
    plant(f[1], f[2], f[3])
end

-- Leknín leží na hladině — plochý nodebox, ne stéblo
reg("flowers:waterlily", {
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
})

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
        liquid_alternative_flowing = base .. "_flowing",
        liquid_alternative_source = base .. "_source",
        liquid_renewable = opts.renewable ~= false,
        use_texture_alpha = "blend",
        groups = opts.groups or {},
    }

    local src = {drawtype = "liquidsource", liquidtype = "source",
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

liquid_pair("default:water", "water", {
    desc = "Water", drowning = 1, viscosity = 1,
    post = {a = 103, r = 30, g = 60, b = 90},
    groups = {water = 3, liquid = 3, cools_lava = 1},
})

liquid_pair("default:river_water", "river_water", {
    desc = "River Water", drowning = 1, viscosity = 1, renewable = false,
    post = {a = 103, r = 30, g = 76, b = 90},
    groups = {water = 3, liquid = 3, cools_lava = 1},
})

liquid_pair("default:lava", "lava", {
    desc = "Lava", dps = 4, light = 13, viscosity = 7, renewable = false,
    post = {a = 191, r = 255, g = 64, b = 0},
    groups = {lava = 3, liquid = 2, igniter = 1},
})

---------------------------------------------------------------------------
-- Oheň — jen dekorace nad sopkami, nešíří se
---------------------------------------------------------------------------

reg("fire:basic_flame", {
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
})

minetest.log("action", "[dw_nodes] minetest_game node stand-ins registered")
