-- dw_core/map.lua
-- Celoobrazovková kruhová mapa světa — přepíná klávesa Z (zoom bit;
-- na gamepadu tlačítko minimapy/zoomu) nebo příkaz /map.
--
-- Nativní minimapa entity neumí, je fixně malá a dosáhne max 512 m.
-- Tahle mapa je poskládaná z HUD prvků: ostrovy se počítají
-- deterministicky z doggiowars.island_for_cell (stejný trik jako radar
-- v roblox/ portu — žádné čtení mapy), monstra a velryby čte živě ze
-- spawner registrů (doggiowars.monster_groups/_whales) a hráč je
-- uprostřed s tečkou směru pohledu. Sever = +Z = nahoře.
--
-- Prvky se vytvoří jednou při otevření (pool) a pak se jen posouvají
-- přes hud_change; ostrovy se přepočítávají až při posunu o RECENTER.

local hud = doggiowars.hud

local RANGE    = 1400            -- m od hráče k okraji mapy
local HALF_PX  = 350             -- px od středu k okraji (drží se v 1080p)
local PXM      = HALF_PX / RANGE -- px na metr
local CELLS    = 4               -- okolí buněk (4×340 ≈ RANGE)
local RECENTER = 150             -- m posunu hráče → přepočet ostrovů
local UPDATE   = 0.2             -- s mezi překreslením živých teček
local MAX_ISL  = 90
local MAX_MON  = 24
local OFFSCREEN = {x = 0, y = 99999}

local DOT = "doggiowars_map_dot.png"

-- stejná paleta jako radar v roblox portu
local BIOME_COLOR = {
    verdant = "#4caf50", glacial = "#e8f4ff", volcanic = "#b24632",
    atoll   = "#e8d8a0", mycelial = "#9c6bb5", barren = "#8a8a8a",
    jungle  = "#2e7d32", desert = "#d9c07a", crystal = "#9fe8ff",
    ashen   = "#5c5c5c", savanna = "#a8a055", swamp = "#6b7a4f",
}

local state = {}   -- name -> {open, zoom_was, last_toggle, cx, cz}

local world_seed
local function seed()
    world_seed = world_seed or doggiowars.get_world_seed()
    return world_seed
end

local function S(player)
    local name = player:get_player_name()
    local st = state[name]
    if not st then
        st = {last_toggle = -1e9}
        state[name] = st
    end
    return st
end

local function dot_def(z_index, tex)
    return {
        type      = "image",
        position  = {x = 0.5, y = 0.5},
        offset    = OFFSCREEN,
        text      = tex or DOT,
        scale     = {x = 0.5, y = 0.5},
        alignment = {x = 0, y = 0},
        z_index   = z_index,
    }
end

local function open_map(player, st)
    -- kruhové pozadí = tečka zvětšená přes celou obrazovku
    hud.add(player, "map_bg", {
        type      = "image",
        position  = {x = 0.5, y = 0.5},
        offset    = {x = 0, y = 0},
        text      = DOT .. "^[colorize:#0a1016:255^[opacity:210",
        scale     = {x = (HALF_PX * 2 + 24) / 16, y = (HALF_PX * 2 + 24) / 16},
        alignment = {x = 0, y = 0},
        z_index   = 80,
    })
    for i = 1, MAX_ISL do
        hud.add(player, "map_i" .. i, dot_def(81))
    end
    for i = 1, MAX_MON do
        hud.add(player, "map_m" .. i, dot_def(82))
    end
    hud.add(player, "map_player", dot_def(85))
    hud.set(player, "map_player", {offset = {x = 0, y = 0}, scale = {x = 0.6, y = 0.6}})
    hud.add(player, "map_heading", dot_def(85))
    st.open = true
    st.cx = nil   -- vynutí první rebuild ostrovů
end

local function close_map(player, st)
    hud.remove_key(player, "map_bg")
    hud.remove_key(player, "map_player")
    hud.remove_key(player, "map_heading")
    for i = 1, MAX_ISL do hud.remove_key(player, "map_i" .. i) end
    for i = 1, MAX_MON do hud.remove_key(player, "map_m" .. i) end
    st.open = false
end

-- ostrovy: jen při posunu (jsou statické; šetří hud_change pakety)
local function update_islands(player, st, px, pz)
    st.cx, st.cz = px, pz
    local grid = doggiowars.ISLAND_GRID
    local pcx = math.floor(px / grid)
    local pcz = math.floor(pz / grid)
    local n = 0
    local lim2 = (HALF_PX - 8) ^ 2
    for dcx = -CELLS, CELLS do
        for dcz = -CELLS, CELLS do
            local isl = doggiowars.island_for_cell(pcx + dcx, pcz + dcz, seed())
            if isl and n < MAX_ISL then
                local ox = (isl.x - px) * PXM
                local oy = -(isl.z - pz) * PXM
                if ox * ox + oy * oy < lim2 then
                    n = n + 1
                    local d = math.max(6, isl.radius * 2 * PXM)
                    hud.set(player, "map_i" .. n, {
                        offset = {x = ox, y = oy},
                        scale = {x = d / 16, y = d / 16},
                        text = DOT .. "^[colorize:"
                            .. (BIOME_COLOR[isl.biome.name] or "#ffffff")
                            .. ":255^[opacity:205",
                    })
                end
            end
        end
    end
    for i = n + 1, MAX_ISL do
        hud.set(player, "map_i" .. i, {offset = OFFSCREEN})
    end
end

local function update_live(player, st, px, pz, ppos)
    local n = 0
    local lim2 = (HALF_PX - 6) ^ 2
    local function dot(pos, color, size)
        if n >= MAX_MON then return end
        local ox = (pos.x - px) * PXM
        local oy = -(pos.z - pz) * PXM
        if ox * ox + oy * oy >= lim2 then return end
        n = n + 1
        hud.set(player, "map_m" .. n, {
            offset = {x = ox, y = oy},
            scale = {x = size / 16, y = size / 16},
            text = DOT .. "^[colorize:" .. color .. ":255",
        })
    end
    for _, grp in pairs(doggiowars.monster_groups or {}) do
        for _, o in ipairs(grp.objs) do
            if o:get_luaentity() then
                local pos = o:get_pos()
                if pos then
                    dot(pos, "#ff6a50", 7)
                end
            end
        end
    end
    for _, o in pairs(doggiowars.monster_whales or {}) do
        if o:get_luaentity() then
            local pos = o:get_pos()
            if pos then
                dot(pos, "#cfe8f8", 10)
            end
        end
    end
    for i = n + 1, MAX_MON do
        hud.set(player, "map_m" .. i, {offset = OFFSCREEN})
    end

    -- hráč: mezi recentry mapa stojí, takže jeho značka po ní pluje;
    -- tečka směru pohledu 14 px před ní (kurz jako kompas v hud.lua)
    local pxo = (ppos.x - px) * PXM
    local pyo = -(ppos.z - pz) * PXM
    hud.set(player, "map_player", {offset = {x = pxo, y = pyo}})
    local heading = math.rad(
        (360 - math.deg(player:get_look_horizontal() or 0)) % 360)
    hud.set(player, "map_heading", {
        offset = {x = pxo + math.sin(heading) * 14,
                  y = pyo - math.cos(heading) * 14},
        scale = {x = 0.35, y = 0.35},
    })
end

local function toggle_map(player)
    local st = S(player)
    if st.open then
        close_map(player, st)
    else
        open_map(player, st)
    end
end

-- Z (zoom bit) s hranovou detekcí; 0.4 s zámek kvůli auto-repeatu
-- joystickových tlačítek (repeat_joystick_button_time 0.17 s, viz sky.lua)
local acc = 0
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local st = S(player)
        local zoom = player:get_player_control().zoom
        local now = minetest.get_us_time() / 1e6
        if zoom and not st.zoom_was and now - st.last_toggle > 0.4 then
            st.last_toggle = now
            toggle_map(player)
        end
        st.zoom_was = zoom
    end

    acc = acc + dtime
    if acc < UPDATE then return end
    acc = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local st = state[player:get_player_name()]
        if st and st.open then
            local f = doggiowars.get_player_fighter(player)
            local pos = f and f.object:get_pos() or player:get_pos()
            if pos then
                if not st.cx
                        or math.abs(pos.x - st.cx) > RECENTER
                        or math.abs(pos.z - st.cz) > RECENTER then
                    update_islands(player, st, pos.x, pos.z)
                end
                update_live(player, st, st.cx, st.cz, pos)
            end
        end
    end
end)

minetest.register_chatcommand("map", {
    description = "Toggle the fullscreen world map",
    privs = {interact = true},
    func = function(name)
        local p = minetest.get_player_by_name(name)
        if not p then return false, "Player not found" end
        toggle_map(p)
        return true
    end,
})

minetest.register_on_leaveplayer(function(player)
    state[player:get_player_name()] = nil
end)
