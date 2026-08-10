-- doggiowars/init.lua
-- DoggioWars — Voxel dogfight on aerial islands
-- Luanti mod entry point

doggiowars = {}

-- Sdílené letové konstanty (čtou je vehicle.lua, tricks.lua, rabbit.lua, race.lua)
doggiowars.const = {
    SPEED_MAX    = 40,      -- m/s
    SPEED_MIN    = 5,       -- stall speed
    TURN_SPEED   = 1.5,     -- rad/s
    PITCH_RATE   = 1.2,     -- rad/s
    PITCH_MAX    = 0.6,     -- max pitch angle
    PITCH_DECAY  = 0.8,     -- pitch return-to-center rate
    ROLL_SPEED   = 1.8,     -- rad/s
    ROLL_MAX     = math.pi,
    ROLL_DECAY   = 1.5,     -- roll auto-level rate
    SPAWN_HEIGHT = 300,     -- výška spawnu / respawnu

    -- Režim ponorky (/mode sub) — 6DoF. Klidová rychlost je 0: ponorka nikam
    -- sama nejede, po puštění páček dojede na nulu a zůstane viset.
    SUB_SPEED_MAX = 18,     -- m/s vpřed i vzad
    SUB_STRAFE    = 12,     -- m/s boční posun
    SUB_VERT      = 10,     -- m/s stoupání / klesání
    SUB_ACCEL     = 25,     -- m/s^2 — jak rychle se dojíždí k cílové rychlosti
    SUB_TURN      = 1.2,    -- rad/s dotáčení trupu za pohledem
    SUB_PITCH_MAX = 1.2,    -- rad (~69°), letadlo má 0.6
}

local MP = minetest.get_modpath("doggiowars")

-- Load modules in dependency order
dofile(MP .. "/nodes.lua")      -- Custom blocks (must be first for content IDs)
dofile(MP .. "/biomes.lua")     -- Biome definitions
dofile(MP .. "/mapgen.lua")     -- Island generator
dofile(MP .. "/decorate.lua")   -- Post-gen decoration (trees, mushrooms, etc.)
dofile(MP .. "/hud.lua")        -- HUD (statbary, flash, race widgety)
dofile(MP .. "/tricks.lua")     -- Vstupní komba a skriptované triky
dofile(MP .. "/submarine.lua")  -- Režim ponorky (6DoF řízení)
dofile(MP .. "/vehicle.lua")    -- Fighter plane entity
dofile(MP .. "/weapons.lua")    -- Projectiles, explosions, damage
dofile(MP .. "/rabbit.lua")     -- Zajíc — AI loď pro chrtí závod
dofile(MP .. "/race.lua")       -- Chrtí závod: trať, tunely, checkpointy
dofile(MP .. "/sky.lua")        -- Sky, clouds, fog

-- Automatické zapnutí gamepadu. enable_joysticks je klientské nastavení
-- s výchozí hodnotou false na VŠECH platformách — bez něj žádný ovladač
-- nefunguje. V singleplayeru běží mod ve stejném procesu jako klient,
-- takže ho smíme zapnout sami; projeví se po restartu Luanti. Marker
-- zaručí, že to uděláme jen jednou — když si hráč joystick později
-- vědomě vypne, nebudeme mu ho přepisovat.
if minetest.is_singleplayer() then
    local s = minetest.settings
    if not s:get_bool("doggiowars_gamepad_setup", false) then
        s:set_bool("doggiowars_gamepad_setup", true)
        if not s:get_bool("enable_joysticks", false) then
            s:set_bool("enable_joysticks", true)
            if not s:get("joystick_deadzone") then
                s:set("joystick_deadzone", "4000")
            end
            minetest.register_on_joinplayer(function(player)
                minetest.chat_send_player(player:get_player_name(),
                    "Gamepad support enabled - restart Luanti once to use it."
                    .. " DualShock (PS4/PS5): also set joystick_type = ps5"
                    .. " (see GAMEPAD.md).")
            end)
            minetest.log("action",
                "[doggiowars] enable_joysticks turned on (takes effect "
                .. "after restart)")
        end
    end
end

minetest.log("action", "[doggiowars] Mod loaded successfully")
