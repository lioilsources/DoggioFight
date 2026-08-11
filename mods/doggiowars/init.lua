-- doggiowars/init.lua
-- DoggioWars — Voxel dogfight on aerial islands
-- Luanti mod entry point

doggiowars = {}

-- Sdílené letové konstanty (čtou je vehicle.lua, tricks.lua, rabbit.lua, race.lua)
doggiowars.const = {
    SPEED_MAX    = 40,      -- m/s
    SPEED_MIN    = 5,       -- stall speed
    TURN_SPEED   = 1.5,     -- rad/s (ponorka: dotáčení za zaměřovačem)

    -- Stíhačka zatáčí NÁKLONEM (bank-to-turn), ne mířením: levá páčka zadá
    -- úhel náklonu a zatáčka z něj teprve vznikne. Pravá páčka do letu
    -- nezasahuje vůbec — jen míří.
    BANK_ROLL     = 1.05,   -- rad (~60°) při plné výchylce páčky
    BANK_ROLL_MAX = 1.40,   -- rad (~80°) v airbrake driftu
    TURN_RATE     = 1.30,   -- rad/s při svislém náklonu; škáluje sin(roll)

    -- Zaměřovač NEMÁ tvrdou mez. Kužel, do kterého se pohled vracel, se
    -- pral s páčkou drženou na doraz: server vrátí na hranu, klient zase
    -- přetlačí ven, a v krajní poloze to začne kmitat. Místo meze se
    -- zaměřovač sám vrací na nos — ale jen když hráč nemíří, takže není
    -- do čeho zasahovat.
    AIM_RETURN    = 1.20,   -- rad/s návrat zaměřovače na nos při puštěné páčce

    PITCH_RATE   = 1.2,     -- rad/s
    PITCH_MAX    = 0.6,     -- max pitch angle
    PITCH_DECAY  = 0.8,     -- pitch return-to-center rate
    ROLL_SPEED   = 1.8,     -- rad/s
    ROLL_MAX     = math.pi,
    ROLL_DECAY   = 1.5,     -- roll auto-level rate
    SPAWN_HEIGHT = 300,     -- výška spawnu / respawnu

    -- Režim ponorky (/mode) — 5DoF hover
    SUB_SPEED      = 20,    -- m/s max tah dopředu/dozadu
    SUB_STRAFE     = 14,    -- m/s max úkrok do stran
    SUB_VERT_SPEED = 12,    -- m/s max stoupání/klesání
    SUB_ACCEL      = 25,    -- m/s^2 dojezd k cílové rychlosti (i brzda)
    SUB_PITCH_MAX  = 0.9,   -- rad clamp sklonu trupu (strmější než PITCH_MAX)
}

local MP = minetest.get_modpath("doggiowars")

-- Load modules in dependency order
dofile(MP .. "/nodes.lua")      -- Custom blocks (must be first for content IDs)
dofile(MP .. "/biomes.lua")     -- Biome definitions
dofile(MP .. "/mapgen.lua")     -- Island generator
dofile(MP .. "/decorate.lua")   -- Post-gen decoration (trees, mushrooms, etc.)
dofile(MP .. "/hud.lua")        -- HUD (statbary, flash, race widgety)
dofile(MP .. "/tricks.lua")     -- Vstupní komba a skriptované triky
dofile(MP .. "/vehicle.lua")    -- Fighter plane entity
dofile(MP .. "/weapons.lua")    -- Projectiles, explosions, damage
dofile(MP .. "/rabbit.lua")     -- Zajíc — AI loď pro chrtí závod
dofile(MP .. "/race.lua")       -- Chrtí závod: trať, tunely, checkpointy
dofile(MP .. "/sky.lua")        -- Sky, clouds, fog

-- Gamepad se zapíná deklarativně přes minetest.conf HRY (enable_joysticks,
-- joystick_deadzone) — hra smí posouvat výchozí hodnoty nastavení, takže
-- tady už nemusí být žádný zápis do hráčova configu. Zbývá jen připomenout
-- DualShock, protože joystick_type je vlastnost hardwaru a uhodnout ho
-- nejde (viz GAMEPAD.md).
minetest.register_on_joinplayer(function(player)
    -- has(), ne get() — get() vrací i enginový default ("auto"), takže by
    -- podmínka platila vždycky a hláška by nevyskočila nikdy
    local s = minetest.settings
    if s.has and s:has("joystick_type") then return end
    minetest.chat_send_player(player:get_player_name(),
        "Gamepad: PS4/PS5 DualShock needs Settings -> Controls -> Gamepads "
        .. "-> Joystick type = ps5. Xbox works on 'auto'. See GAMEPAD.md.")
end)

minetest.log("action", "[doggiowars] Mod loaded successfully")
