-- doggiowars/hud.lua
-- HUD systém: letové údaje, statbary, trick flash, race widgety.
-- Generické API (add/set/remove_key) používá i race.lua.

doggiowars.hud = {}
local hud = doggiowars.hud

-- [player_name] = {ids = {key = hud_id}, flash_token = n}
local state = {}

local function S(player)
    local name = player:get_player_name()
    local st = state[name]
    if not st then
        st = {ids = {}, flash_token = 0}
        state[name] = st
    end
    return st
end

function hud.add(player, key, def)
    local st = S(player)
    if st.ids[key] then
        player:hud_remove(st.ids[key])
    end
    st.ids[key] = player:hud_add(def)
    return st.ids[key]
end

function hud.set(player, key, props)
    local st = S(player)
    local id = st.ids[key]
    if not id then return end
    for k, v in pairs(props) do
        player:hud_change(id, k, v)
    end
end

function hud.remove_key(player, key)
    local st = S(player)
    if st.ids[key] then
        player:hud_remove(st.ids[key])
        st.ids[key] = nil
    end
end

-- Velký centrovaný text ("BARREL ROLL! ×3", "CHECKPOINT 3/9", ...),
-- zmizí po 1.2 s; novější flash přepíše starší
function hud.flash(player, text, color)
    local st = S(player)
    st.flash_token = st.flash_token + 1
    local token = st.flash_token
    if st.ids.flash then
        hud.set(player, "flash", {text = text, number = color or 0xFFD75E})
    else
        hud.add(player, "flash", {
            type      = "text",
            position  = {x = 0.5, y = 0.35},
            alignment = {x = 0, y = 0},
            text      = text,
            number    = color or 0xFFD75E,
            size      = {x = 3},
            z_index   = 100,
        })
    end
    local name = player:get_player_name()
    minetest.after(1.2, function()
        local p = minetest.get_player_by_name(name)
        local st2 = state[name]
        if p and st2 and st2.flash_token == token and st2.ids.flash then
            hud.set(p, "flash", {text = ""})
        end
    end)
end

---------------------------------------------------------------------------
-- Kompasová páska — sever = +Z, klouzavé okno ±60° kolem kurzu
---------------------------------------------------------------------------

local CARDINALS = {
    [0] = "S", [45] = "SV", [90] = "V", [135] = "JV",
    [180] = "J", [225] = "JZ", [270] = "Z", [315] = "SZ",
}

local function compass_tape(heading)
    local base = math.floor(heading / 15 + 0.5) * 15
    local parts = {}
    for off = -60, 60, 15 do
        local a = (base + off) % 360
        local label = CARDINALS[a] or "·"
        if #label == 1 then label = label .. " " end
        if off == 0 then
            label = "[" .. label .. "]"
        else
            label = " " .. label .. " "
        end
        table.insert(parts, label)
    end
    return table.concat(parts)
end

---------------------------------------------------------------------------
-- Umělý horizont
--
-- Luanti neumí HUD prvek otočit, takže nakloněnou čáru skládáme z několika
-- dílků rozmístěných po přímce. Poloha se počítá přes cos/sin, ne přes
-- tangens — ten u svislého náklonu (a ten tu jde, roll sahá přes 90°)
-- utíká do nekonečna.
--
-- Čára se naklání OPAČNĚ než letadlo: svět zůstává vodorovný, naklání se
-- stroj. Náklon doleva (roll < 0) tedy zvedne levý konec čáry.
---------------------------------------------------------------------------

-- Sudý počet dílků = uprostřed mezera, ve které sedí značka letadla.
-- Kdyby tam dílky byly, kreslily by se přes ni (značka je 31 px široká).
local HORIZON_PIPS    = 8      -- 4 vlevo, 4 vpravo, žádný ve středu
local HORIZON_SPACING = 16     -- px mezi dílky
local HORIZON_Y       = 0.80   -- pod křížem, nad údajem BANK

local PIP_TEX = "doggiowars_hud_pip.png^[colorize:#8FE3A0:255"
local REF_TEX = "doggiowars_hud_ref.png^[colorize:#FFFFFF:255"

local function horizon_key(i)
    return "horizon" .. i
end

-- i = 1..8  ->  vzdálenost od středu -64,-48,-32,-16, +16,+32,+48,+64
local function horizon_dist(i)
    local half = HORIZON_PIPS / 2
    local k = (i <= half) and (i - half - 1) or (i - half)
    return k * HORIZON_SPACING
end

local function horizon_add(player)
    for i = 1, HORIZON_PIPS do
        hud.add(player, horizon_key(i), {
            type      = "image",
            position  = {x = 0.5, y = HORIZON_Y},
            offset    = {x = 0, y = 0},
            text      = PIP_TEX,
            scale     = {x = 2, y = 2},
            alignment = {x = 0, y = 0},
            z_index   = 45,
        })
    end
    hud.add(player, "horizon_ref", {
        type      = "image",
        position  = {x = 0.5, y = HORIZON_Y},
        offset    = {x = 0, y = 0},
        text      = REF_TEX,
        -- scale 1: značka je 31 px široká a vejde se do mezery ±16 px
        scale     = {x = 1, y = 1},
        alignment = {x = 0, y = 0},
        z_index   = 46,
    })
end

-- roll v radiánech; show = false schová horizont (ponorka se nenaklání).
-- Texturu přepisujeme jen při změně viditelnosti — každý hud_change je
-- paket klientovi a tohle běží 7× za sekundu.
local function horizon_update(player, roll, show)
    local st = S(player)
    if show ~= st.horizon_shown then
        st.horizon_shown = show
        for i = 1, HORIZON_PIPS do
            hud.set(player, horizon_key(i), {text = show and PIP_TEX or ""})
        end
        hud.set(player, "horizon_ref", {text = show and REF_TEX or ""})
    end
    if not show then return end

    local a = -(roll or 0)
    local ca, sa = math.cos(a), math.sin(a)
    for i = 1, HORIZON_PIPS do
        local d = horizon_dist(i)
        hud.set(player, horizon_key(i), {
            offset = {x = math.floor(d * ca + 0.5),
                      y = math.floor(d * sa + 0.5)},
        })
    end
end

---------------------------------------------------------------------------
-- Letový HUD
---------------------------------------------------------------------------

function hud.init(player)
    horizon_add(player)
    hud.add(player, "compass", {
        type      = "text",
        position  = {x = 0.5, y = 0.02},
        alignment = {x = 0, y = 1},
        text      = "",
        number    = 0xFFFFFF,
        size      = {x = 2},
        style     = 4,   -- mono, ať páska neposkakuje
        z_index   = 50,
    })
    hud.add(player, "heading", {
        type      = "text",
        position  = {x = 0.5, y = 0.055},
        alignment = {x = 0, y = 1},
        text      = "",
        number    = 0x9FD8FF,
        size      = {x = 1},
        style     = 4,
    })
    hud.add(player, "speed", {
        type      = "text",
        position  = {x = 0.02, y = 0.94},
        alignment = {x = 1, y = 0},
        text      = "SPD 0",
        number    = 0x9FD8FF,
        size      = {x = 2},
    })
    hud.add(player, "hull", {
        type      = "statbar",
        position  = {x = 0.02, y = 0.88},
        text      = "doggiowars_particle_engine.png^[colorize:#ff5040:200",
        number    = 20,
        size      = {x = 20, y = 20},
        direction = 0,
    })
    hud.add(player, "boost", {
        type      = "statbar",
        position  = {x = 0.02, y = 0.84},
        text      = "doggiowars_particle_engine.png^[colorize:#ffd75e:200",
        number    = 10,
        size      = {x = 20, y = 20},
        direction = 0,
    })
    -- vlevo nahoře — vpravo nahoře sedí minimapa (radar), překrývaly se
    hud.add(player, "score", {
        type      = "text",
        position  = {x = 0.02, y = 0.06},
        alignment = {x = 1, y = 0},
        text      = "SKÓRE 0",
        number    = 0xFFD75E,
        size      = {x = 2},
    })
    hud.add(player, "bank", {
        type      = "text",
        position  = {x = 0.5, y = 0.92},
        alignment = {x = 0, y = 0},
        text      = "",
        number    = 0xFFFFFF,
        size      = {x = 1},
    })
    -- Gamepad diagnostika (zap/vyp přes /gp) — jinak prázdné
    hud.add(player, "gpdebug", {
        type      = "text",
        position  = {x = 0.5, y = 0.5},
        alignment = {x = 0, y = 0},
        text      = "",
        number    = 0x66FF99,
        size      = {x = 1},
        style     = 4,
        z_index   = 60,
    })
end

-- Volá fighter on_step (throttle 0.15 s); f = luaentity stíhačky
function hud.update_flight(player, f)
    -- levý panel: rychlost · výška · variometr (stoupání/klesání m/s)
    local pos = f.object and f.object:get_pos()
    local vel = f.object and f.object:get_velocity() or {x = 0, y = 0, z = 0}
    local alt = pos and math.floor(pos.y) or 0
    local vy = vel.y or 0
    local vs = "VS  0"
    if vy > 1 or vy < -1 then
        vs = string.format("VS %+d", math.floor(vy + 0.5))
    end
    local mtag = doggiowars.get_mode
        and doggiowars.get_mode(player:get_player_name()) == "sub"
        and "SUB   " or ""
    hud.set(player, "speed", {text = string.format(
        "%sSPD %d   ALT %d   %s", mtag, f.speed or 0, alt, vs)})

    -- kompas: kurz z pohledu (0° = sever = +Z, po směru hodin)
    local heading = (360 - math.deg(player:get_look_horizontal() or 0)) % 360
    hud.set(player, "compass", {text = compass_tape(heading)})
    hud.set(player, "heading", {text = string.format("%03d°", heading)})

    hud.set(player, "hull", {number = math.max(0, math.ceil((f.hp or 100) / 5))})
    hud.set(player, "boost", {number = math.floor((f.boost_meter or 0) / 10 + 0.5)})

    local score_text = string.format("SKÓRE %d", f.score or 0)
    local now = minetest.get_us_time() / 1e6
    if (f.combo or 1) > 1 and now - (f.combo_last or -math.huge) < 4.0 then
        score_text = score_text .. string.format("  ×%d", f.combo)
    end
    hud.set(player, "score", {text = score_text})

    -- umělý horizont — jen ve stíhačce, ponorka se nenaklání
    horizon_update(player, f.roll or 0, mtag == "")

    -- podélný sklon (▲ stoupání / ▼ klesání) + náklon
    local pdeg = math.deg(f.pitch or 0)
    local bank = math.deg(f.roll or 0)
    local att = ""
    if pdeg > 3 then
        att = string.format("▲ %d°", pdeg)
    elseif pdeg < -3 then
        att = string.format("▼ %d°", -pdeg)
    end
    if math.abs(bank) > 5 then
        att = att .. (att ~= "" and "    " or "")
            .. string.format("BANK %+d°", bank)
    end
    hud.set(player, "bank", {text = att})
end

minetest.register_on_leaveplayer(function(player)
    state[player:get_player_name()] = nil
end)
