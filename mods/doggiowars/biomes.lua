-- doggiowars/biomes.lua
-- Definice biomů a jejich materiálů (12 typů)

doggiowars = doggiowars or {}
doggiowars.biome_ids = {}  -- content ID cache

local c = doggiowars.biome_ids

-- Bezpečné načtení content ID: když node neexistuje, spadne na fallback
local function id(name, fallback)
    if minetest.registered_nodes[name] then
        local cid = minetest.get_content_id(name)
        if cid and cid ~= minetest.CONTENT_IGNORE then
            return cid
        end
    end
    return fallback
end

local function init_content_ids()
    c.air        = minetest.get_content_id("air")
    c.stone      = minetest.get_content_id("default:stone")
    c.dirt       = id("default:dirt",                 c.stone)
    c.grass      = id("default:dirt_with_grass",       c.dirt)
    c.ice        = id("default:ice",                   c.stone)
    c.cave_ice   = id("default:cave_ice",              c.ice)
    c.snow       = id("default:snowblock",             c.ice)
    c.permafrost = id("default:permafrost",            c.stone)
    c.obsidian   = id("default:obsidian",              c.stone)
    c.lava       = id("default:lava_source",           c.stone)
    c.sand       = id("default:sand",                  c.dirt)
    c.desert_sand   = id("default:desert_sand",        c.sand)
    c.desert_stone  = id("default:desert_stone",       c.stone)
    c.desert_ss     = id("default:desert_sandstone",   c.desert_stone)
    c.silver_sand   = id("default:silver_sand",        c.sand)
    c.sandstone  = id("default:sandstone",             c.stone)
    c.water      = id("default:water_source",          c.air)
    c.coral      = id("default:coral_skeleton",        c.stone)
    c.clay       = id("default:clay",                  c.dirt)
    c.gravel     = id("default:gravel",                c.stone)
    c.rainforest = id("default:dirt_with_rainforest_litter", c.grass)
    c.dry_grass  = id("default:dirt_with_dry_grass",   c.grass)
    c.dry_dirt   = id("default:dry_dirt",              c.dirt)

    -- Vlastní bloky (nodes.lua)
    c.mycelium   = id("doggiowars:spore_block",  c.dirt)
    c.magma      = id("doggiowars:magma_block",  c.obsidian)
    c.dead_stone = id("doggiowars:dead_stone",   c.stone)
    c.embers     = id("doggiowars:embers",       c.magma)
    c.ash        = id("doggiowars:ash",          c.gravel)
    c.mud        = id("doggiowars:mud",          c.dirt)
    c.crystal    = id("doggiowars:crystal",      c.ice)
    c.basalt     = id("doggiowars:basalt",       c.obsidian)
    c.mossy      = id("doggiowars:mossy_stone",  c.stone)
end

minetest.after(0, init_content_ids)

-- Definice biomů.
-- shape: tvar pro island_profile (avatar/disc/cone/mesa/spire)
-- surface(depth): materiál podle hloubky pod povrchem (0 = povrch)
-- decor: klíč pro decorate.lua
doggiowars.biomes = {
    [0] = { -- VERDANT — mírný les, řeky
        name = "verdant", shape = "avatar", decor = "verdant",
        surface = function(d)
            if d == 0 then return c.grass end
            if d <= 3 then return c.dirt end
            return c.stone
        end,
    },
    [1] = { -- GLACIAL — zamrzlá plošina, led
        name = "glacial", shape = "mesa", decor = "glacial",
        surface = function(d)
            if d == 0 then return c.snow end
            if d <= 2 then return c.ice end
            if d <= 5 then return c.permafrost end
            return c.stone
        end,
    },
    [2] = { -- VOLCANIC — ostrov s čedičovou sopkou (hora + kráter + láva)
        name = "volcanic", shape = "avatar", decor = "volcanic",
        surface = function(d)
            if d == 0 then return c.basalt end
            if d <= 3 then return c.obsidian end
            return c.stone
        end,
    },
    [3] = { -- ATOLL — písečný prstenec s lagunou
        name = "atoll", shape = "disc", decor = "atoll",
        surface = function(d)
            if d == 0 then return c.sand end
            if d <= 2 then return c.clay end
            return c.stone
        end,
    },
    [4] = { -- MYCELIAL — houbový svět
        name = "mycelial", shape = "avatar", decor = "mycelial",
        surface = function(d)
            if d == 0 then return c.mycelium end
            if d <= 3 then return c.dirt end
            return c.stone
        end,
    },
    [5] = { -- BARREN — mrtvá skála
        name = "barren", shape = "cone", decor = "barren",
        surface = function(d)
            if d == 0 then return c.dead_stone end
            return c.stone
        end,
    },
    [6] = { -- JUNGLE — deštný prales, bujná vegetace, řeky
        name = "jungle", shape = "avatar", decor = "jungle",
        surface = function(d)
            if d == 0 then return c.rainforest end
            if d <= 4 then return c.dirt end
            if d <= 7 then return c.mossy end
            return c.stone
        end,
    },
    [7] = { -- DESERT — mesa / kaňony, písek a pískovec
        name = "desert", shape = "mesa", decor = "desert",
        surface = function(d)
            if d == 0 then return c.desert_sand end
            if d <= 4 then return c.desert_ss end
            return c.desert_stone
        end,
    },
    [8] = { -- CRYSTAL — třpytivé věže, svítící krystaly
        name = "crystal", shape = "spire", decor = "crystal",
        surface = function(d)
            if d == 0 then return c.silver_sand end
            if d <= 2 then return c.gravel end
            if d % 5 == 0 then return c.crystal end
            return c.stone
        end,
    },
    [9] = { -- ASHEN — spálená země, žhavé uhlíky, oheň
        name = "ashen", shape = "cone", decor = "ashen",
        surface = function(d)
            if d == 0 then return c.ash end
            if d <= 2 then return c.embers end
            if d <= 5 then return c.basalt end
            return c.stone
        end,
    },
    [10] = { -- SAVANNA — nízká suchá plošina, akácie
        name = "savanna", shape = "mesa", decor = "savanna",
        surface = function(d)
            if d == 0 then return c.dry_grass end
            if d <= 3 then return c.dry_dirt end
            return c.stone
        end,
    },
    [11] = { -- SWAMP — bažina, bahno, voda, mech
        name = "swamp", shape = "disc", decor = "swamp",
        surface = function(d)
            if d == 0 then return c.mud end
            if d <= 3 then return c.dirt end
            if d <= 6 then return c.mossy end
            return c.stone
        end,
    },
}

-- Počet biomů (mapgen bere modulo přes tuto hodnotu)
doggiowars.biome_count = 12
