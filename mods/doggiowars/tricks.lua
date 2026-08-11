-- doggiowars/tricks.lua
-- Detekce vstupních komb (double-tap/hold) a skriptované triky.
-- Step funkce operují nad "airframe" tabulkou {yaw, pitch, speed} —
-- stejnou matematiku používá hráčova stíhačka i závodní králík (race).

doggiowars.tricks = {}
local tricks = doggiowars.tricks
local C = doggiowars.const

local DOUBLE_TAP   = 0.35  -- max rozestup double-tapu (s)
local COMBO_WINDOW = 4.0   -- okno pro řetězení triků (s)
local COMBO_MAX    = 5

-- Session skóre per hráč — přežívá zničení stíhačky
tricks.scores = {}

local WATCHED_KEYS = {"up", "down", "left", "right", "jump", "sneak",
    "dig", "place", "zoom"}

local function now_s()
    return minetest.get_us_time() / 1e6
end

function tricks.init(self)
    self.input       = {prev = {}, last_tap = {}, held_since = {}}
    self.trick       = nil
    self.boost_meter = 50
    self.boost_time  = 0
    self.iframes     = 0
    self.combo       = 1
    self.combo_last  = -math.huge
    self.prox_timer  = 0
    self.score       = self.score or 0
end

---------------------------------------------------------------------------
-- Detektor hran vstupu: double-tapy a holdy existujících kláves
---------------------------------------------------------------------------

function tricks.update_input(self, ctrl)
    if not self.input then tricks.init(self) end
    local inp = self.input
    local now = now_s()
    local events = {}
    for _, k in ipairs(WATCHED_KEYS) do
        local pressed = ctrl[k] and true or false
        if pressed and not inp.prev[k] then
            -- rising edge
            events["tap_" .. k] = true
            if inp.last_tap[k] and now - inp.last_tap[k] < DOUBLE_TAP then
                events["double_" .. k] = true
                inp.last_tap[k] = nil
            else
                inp.last_tap[k] = now
            end
            inp.held_since[k] = now
        elseif not pressed then
            inp.held_since[k] = nil
        end
        if pressed and inp.held_since[k] then
            events["hold_" .. k] = now - inp.held_since[k]
        end
        inp.prev[k] = pressed
    end
    return events
end

---------------------------------------------------------------------------
-- Skóre a combo
---------------------------------------------------------------------------

function tricks.add_raw_score(self, points)
    self.score = (self.score or 0) + points
end

function tricks.award(self, label, points, boost_add)
    local now = now_s()
    if now - (self.combo_last or -math.huge) < COMBO_WINDOW then
        self.combo = math.min((self.combo or 1) + 1, COMBO_MAX)
    else
        self.combo = 1
    end
    self.combo_last = now
    self.score = (self.score or 0) + points * self.combo
    self.boost_meter = math.min((self.boost_meter or 0) + (boost_add or 0), 100)
    local player = self.pilot_name and minetest.get_player_by_name(self.pilot_name)
    if player then
        local text = label
        if self.combo > 1 then
            text = text .. "  ×" .. self.combo
        end
        doggiowars.hud.flash(player, text, 0xFFD75E)
    end
end

---------------------------------------------------------------------------
-- Skriptované manévry — sdílené s králíkem
-- trick = {name, t (0..1), dur (s), dir (±1)}, af = {yaw, pitch, speed}
-- Vrací: rot (euler), vel (vektor), done (bool)
---------------------------------------------------------------------------

function tricks.step_trick(trick, af, dtime)
    trick.t = trick.t + dtime / trick.dur
    local t = math.min(trick.t, 1)
    local s = af.speed
    local rot = {x = 0, y = af.yaw, z = 0}
    local vel

    if trick.name == "barrel_roll" then
        -- 360° kolem podélné osy + boční úhybný impulz
        rot.x = -af.pitch
        rot.z = trick.dir * 2 * math.pi * t
        local dir = minetest.yaw_to_dir(af.yaw + math.pi)
        local cp = math.cos(af.pitch)
        vel = {
            x = dir.x * cp * s - dir.z * trick.dir * 8,
            y = math.sin(af.pitch) * s,
            z = dir.z * cp * s + dir.x * trick.dir * 8,
        }

    elseif trick.name == "loop" then
        -- plný vertikální kruh; za 90° cos(a) obrací horizontální směr
        local a = 2 * math.pi * t
        rot.x = -a
        local dir = minetest.yaw_to_dir(af.yaw + math.pi)
        vel = {
            x = dir.x * math.cos(a) * s,
            y = math.sin(a) * s,
            z = dir.z * math.cos(a) * s,
        }

    elseif trick.name == "immelmann" then
        -- půl-loop nahoru, pak srovnávací půl-roll — výstup otočený o 180°
        local dir = minetest.yaw_to_dir(af.yaw + math.pi)
        if t < 0.65 then
            local a = math.pi * (t / 0.65)
            rot.x = -a
            vel = {
                x = dir.x * math.cos(a) * s,
                y = math.sin(a) * s,
                z = dir.z * math.cos(a) * s,
            }
        else
            local k = (t - 0.65) / 0.35
            rot.y = af.yaw + math.pi
            rot.z = math.pi * (1 - k)
            vel = {x = -dir.x * s, y = 0, z = -dir.z * s}
        end
    end

    return rot, vel, trick.t >= 1
end

---------------------------------------------------------------------------
-- Trik hráčovy stíhačky (stav uložený na entitě)
---------------------------------------------------------------------------

function tricks.start(self, name, dur, dir)
    local rot = self.object:get_rotation()
    self.trick = {
        name  = name,
        t     = 0,
        dur   = dur,
        dir   = dir or 1,
        yaw   = rot.y,
        pitch = self.pitch or 0,
        speed = math.max(self.speed or C.SPEED_MIN, C.SPEED_MIN),
    }
end

-- Vrací rot + vel; při dokončení aplikuje výstupní stav a odměnu
function tricks.step_active(self, dtime)
    local trick = self.trick
    local rot, vel, done = tricks.step_trick(trick,
        {yaw = trick.yaw, pitch = trick.pitch, speed = trick.speed}, dtime)
    if done then
        self.trick = nil
        if trick.name == "barrel_roll" then
            self.roll = 0
            tricks.award(self, "BARREL ROLL!", 100, 15)
        elseif trick.name == "loop" then
            self.pitch = 0
            tricks.award(self, "LOOPING!", 200, 20)
        elseif trick.name == "immelmann" then
            self.pitch = 0
            self.roll = 0
            self.speed = math.max(C.SPEED_MIN + 5, trick.speed * 0.6)
            tricks.award(self, "IMMELMANN!", 150, 10)
        end
    end
    return rot, vel
end

function tricks.check_triggers(self, events, pilot)
    if self.trick then return end

    -- Barrel roll: dvojšvih doleva/doprava (A/D nebo levá páčka)
    -- + krátká nesmrtelnost
    if events.double_left or events.double_right then
        tricks.start(self, "barrel_roll", 0.6, events.double_left and -1 or 1)
        self.iframes = 1.0
        return
    end

    -- Looping: podržet Space >= 0.8 s při dostatečné rychlosti
    if (events.hold_jump or 0) >= 0.8 and (self.speed or 0) > 25 then
        self.input.held_since.jump = nil  -- consume — ať se nespouští opakovaně
        tricks.start(self, "loop", 1.6)
        return
    end

    -- Immelmann: double-tap S — nejrychlejší otočka o 180°
    if events.double_down and (self.speed or 0) > 20 then
        tricks.start(self, "immelmann", 1.2)
        return
    end

    -- Boost: L2/RMB (place) nebo double-tap W — stojí 25 z metru.
    -- (zoom NE — na gamepadu sdílí tlačítko s minimapou, žral boost omylem)
    if (events.tap_place or events.double_up)
            and (self.boost_meter or 0) >= 25
            and (self.boost_time or 0) <= 0 then
        self.boost_meter = self.boost_meter - 25
        self.boost_time = 2.0
        if pilot then
            pilot:set_fov(1.25, true, 0.15)
            doggiowars.hud.flash(pilot, "BOOST!", 0x66CCFF)
        end
        return
    end
end

---------------------------------------------------------------------------
-- Pasivní systém: létání těsně kolem terénu nabíjí boost (proximity charge)
---------------------------------------------------------------------------

local PROX_OFFSETS = {
    {x = 0, y = -6, z = 0},
    {x = 6, y = 0, z = 0},
    {x = -6, y = 0, z = 0},
    {x = 0, y = 0, z = 6},
    {x = 0, y = 0, z = -6},
}

function tricks.update_passive(self, dtime)
    self.prox_timer = (self.prox_timer or 0) + dtime
    if self.prox_timer < 0.2 then return end
    self.prox_timer = 0
    if (self.speed or 0) <= 30 then return end
    local pos = self.object:get_pos()
    if not pos then return end
    for _, off in ipairs(PROX_OFFSETS) do
        local node = minetest.get_node({
            x = pos.x + off.x, y = pos.y + off.y, z = pos.z + off.z,
        })
        if node.name ~= "air" and node.name ~= "ignore" then
            self.boost_meter = math.min((self.boost_meter or 0) + 8 * 0.2, 100)
            tricks.add_raw_score(self, 10 * 0.2)
            return
        end
    end
end
