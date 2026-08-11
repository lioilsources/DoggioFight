-- doggiowars/sky.lua
-- Sky, clouds, and fog setup for the aerial world

local SKY_COLOR     = "#2e3155"
-- Mraky jen jako řídká, vysoká clona NAD hracím pásmem (ostrovy jsou
-- ve výšce ~ -400..1400). Hustá deka uprostřed vypadala jako hladina moře.
local CLOUD_HEIGHT  = 1500
local CLOUD_DENSITY = 0.2
local CLOUD_SPEED   = {x = 2, z = 0}

-- Spawn point in the sky
local SPAWN_HEIGHT  = doggiowars.const.SPAWN_HEIGHT

-- Check if set_fog is available (Luanti 5.16+)
local has_set_fog = minetest.features and minetest.features.object_step_has_moveresult ~= nil

---------------------------------------------------------------------------
-- Zafixované poledne — ostrovy jsou vždy plně nasvícené, hvězdy nad nimi
-- (neměníme time_speed v globálním configu, jen periodicky vracíme čas)
---------------------------------------------------------------------------

minetest.after(0, function()
    minetest.set_timeofday(0.5)
end)

local noon_timer = 0
minetest.register_globalstep(function(dtime)
    noon_timer = noon_timer + dtime
    if noon_timer < 5 then return end
    noon_timer = 0
    minetest.set_timeofday(0.5)
end)

minetest.register_on_joinplayer(function(player)
    -- Dark blue skybox
    player:set_sky({
        type       = "plain",
        base_color = SKY_COLOR,
        clouds     = true,
    })

    -- Upper cloud layer
    player:set_clouds({
        density   = CLOUD_DENSITY,
        height    = CLOUD_HEIGHT,
        thickness = 12,
        speed     = CLOUD_SPEED,
        color     = "#e8e8f0a0",
    })

    -- Set sun/moon for atmosphere
    player:set_sun({
        visible = true,
        scale   = 1.5,
    })
    player:set_moon({
        visible = true,
        scale   = 1.2,
    })
    player:set_stars({
        visible    = true,
        count      = 2000,
        star_color = "#ffffffa0",
    })

    -- Teleport to sky spawn on first join
    local name = player:get_player_name()

    -- Minimapa = radar na ostrovy, trvale zapnutá s JEDINÝM režimem.
    -- Klient opakuje držené joystick tlačítko po 0.17 s
    -- (repeat_joystick_button_time), takže tlačítko minimapy na D-padu
    -- přepínalo/blikalo — s jediným režimem a prázdným popiskem nemá co
    -- cyklit ani zobrazit. Vypnutí radaru: příkaz /radar.
    -- Dalekohled (zoom_fov) vypnout: D-pad vlevo ho tiskl spolu s minimapou.
    player:hud_set_flags({minimap = true, minimap_radar = false})
    player:set_minimap_modes({
        {type = "surface", label = "", size = 256},
    }, 0)
    minetest.after(0.5, function()
        local p = minetest.get_player_by_name(name)
        -- až PO minetest_game (binoculars mod si zoom_fov nastavuje na joinu)
        if p then p:set_properties({zoom_fov = 0}) end
    end)
    local meta = player:get_meta()
    if meta:get_int("doggiowars_spawned") == 0 then
        meta:set_int("doggiowars_spawned", 1)
        local sp = doggiowars.spawn_pos and doggiowars.spawn_pos()
            or {x = 0, y = SPAWN_HEIGHT, z = 0}
        player:set_pos(sp)
        minetest.chat_send_player(name,
            "Welcome to DoggioWars! You ARE the fighter — fly!")
    end

    -- Každý join: hráč rovnou letí (malé zpoždění, ať klient doinicializuje;
    -- selhání pokryje watchdog ve vehicle.lua)
    minetest.after(0.2, function()
        local p = minetest.get_player_by_name(name)
        if not p or doggiowars.get_player_fighter(p) then return end
        local pos = p:get_pos()
        doggiowars.mount_player(p, {
            x = pos.x,
            y = math.max(pos.y + 2, 100),
            z = pos.z,
        })
    end)
end)

-- Radar (minimapu) zapíná/vypíná příkaz — tlačítko minimapy na gamepadu
-- kvůli auto-repeatu klienta blikalo, tak je záměrně bez funkce
minetest.register_chatcommand("radar", {
    description = "Toggle the island radar (minimap)",
    privs = {interact = true},
    func = function(name)
        local p = minetest.get_player_by_name(name)
        if not p then return false, "Player not found" end
        local on = p:hud_get_flags().minimap
        p:hud_set_flags({minimap = not on})
        return true, on and "Radar OFF." or "Radar ON."
    end,
})
