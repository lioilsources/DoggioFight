-- doggiowars/nodes.lua
-- Custom bloky pro biomy

minetest.register_node("doggiowars:spore_block", {
    description = "Spore Block",
    tiles = {"doggiowars_spore.png"},
    groups = {crumbly = 2, soil = 1},
    sounds = default.node_sound_dirt_defaults(),
})

minetest.register_node("doggiowars:magma_block", {
    description = "Magma Block",
    tiles = {"doggiowars_magma.png"},
    light_source = 8,
    damage_per_second = 2,
    groups = {cracky = 2},
    sounds = default.node_sound_stone_defaults(),
})

minetest.register_node("doggiowars:ice_crystal", {
    description = "Ice Crystal",
    tiles = {"doggiowars_ice_crystal.png"},
    use_texture_alpha = "blend",
    drawtype = "glasslike",
    paramtype = "light",
    sunlight_propagates = true,
    groups = {cracky = 3},
    sounds = default.node_sound_glass_defaults(),
})

minetest.register_node("doggiowars:dead_stone", {
    description = "Dead Stone",
    tiles = {"doggiowars_dead_stone.png"},
    groups = {cracky = 2},
    sounds = default.node_sound_stone_defaults(),
})

-- Žhavé uhlíky — svítí, lehce pálí (spálené / ohnivé ostrovy)
minetest.register_node("doggiowars:embers", {
    description = "Embers",
    tiles = {"doggiowars_embers.png"},
    light_source = 10,
    damage_per_second = 1,
    groups = {crumbly = 2, cracky = 3},
    sounds = default.node_sound_stone_defaults(),
})

-- Popel — sypká vrstva po požáru
minetest.register_node("doggiowars:ash", {
    description = "Ash",
    tiles = {"doggiowars_ash.png"},
    groups = {crumbly = 3, falling_node = 1},
    sounds = default.node_sound_sand_defaults(),
})

-- Bahno — bažinné ostrovy
minetest.register_node("doggiowars:mud", {
    description = "Mud",
    tiles = {"doggiowars_mud.png"},
    groups = {crumbly = 3, soil = 1},
    sounds = default.node_sound_dirt_defaults(),
})

-- Svítící krystal — krystalové ostrovy
minetest.register_node("doggiowars:crystal", {
    description = "Glowing Crystal",
    tiles = {"doggiowars_crystal.png"},
    light_source = 12,
    use_texture_alpha = "opaque",
    paramtype = "light",
    groups = {cracky = 2},
    sounds = default.node_sound_glass_defaults(),
})

-- Čedič — sopečné / spálené jádro
minetest.register_node("doggiowars:basalt", {
    description = "Basalt",
    tiles = {"doggiowars_basalt.png"},
    groups = {cracky = 2},
    sounds = default.node_sound_stone_defaults(),
})

-- Mechový kámen — bažiny, vlhké oblasti
minetest.register_node("doggiowars:mossy_stone", {
    description = "Mossy Stone",
    tiles = {"doggiowars_mossy_stone.png"},
    groups = {cracky = 2},
    sounds = default.node_sound_stone_defaults(),
})
