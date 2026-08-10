-- doggiowars/submarine.lua
-- Režim ponorky: 6DoF řízení. Na rozdíl od stíhačky, která drží nastavenou
-- rychlost a pořád někam letí, ponorka v klidu STOJÍ — cílová rychlost je
-- nula, kdykoli se hráč nedotýká páček, a stroj k ní dojede a zůstane viset.
--
-- Levá páčka  = posun vpřed/vzad + boční posun (strafe)
-- Pravá páčka = pitch + yaw (pohled; trup se za ním dotáčí)
-- jump/sneak  = vertikální posun nahoru/dolů
--
-- Proč vertikál není na D-padu: get_player_control() D-pad nevrací, Luanti
-- si ho drží na klientské zkratky (minimapa, fast, fly, autoforward) — viz
-- GAMEPAD.md. jump/sneak jsou navíc tatáž tlačítka, co ve stíhačce dávají
-- nos nahoru/dolů, takže se to dobře pamatuje.

doggiowars.sub = {}
local sub = doggiowars.sub
local C = doggiowars.const

local SUB_BOOST_MUL = 2.2   -- násobek cílové rychlosti po dobu boostu

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function wrap_angle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- Analogová osa s digitálním fallbackem. Klient spíná bity up/down/left/right
-- až při velké výchylce páčky, proto se pod prahem 0.25 bere raději bit —
-- stejný idiom, jakým čte plyn stíhačka (vehicle.lua).
local function axis(analog, neg, pos)
    local a = clamp(analog or 0, -1, 1)
    if math.abs(a) < 0.25 then
        a = (pos and 1 or 0) - (neg and 1 or 0)
    end
    return a
end

-- Vrací rot (euler) a vel (vektor); rotaci i rychlost rovnou aplikuje,
-- stejně jako to dělá letový blok stíhačky.
function sub.step(self, dtime, ctrl, pilot)
    local rot = self.object:get_rotation()
    local look_h = pilot:get_look_horizontal()
    local look_v = pilot:get_look_vertical()   -- kladné = dolů

    -- Vstupy: surge (vpřed/vzad), sway (strafe), heave (nahoru/dolů).
    -- movement_x > 0 = doprava; kdyby byl strafe na nějakém ovladači obráceně,
    -- stačí otočit znaménko tady.
    local surge = axis(ctrl.movement_y, ctrl.down, ctrl.up)
    local sway  = axis(ctrl.movement_x, ctrl.left, ctrl.right)
    local heave = (ctrl.jump and 1 or 0) - (ctrl.sneak and 1 or 0)
    self.dbg_thr = surge

    -- Boost: zrychlí, ale nepřepisuje rychlost natvrdo jako u stíhačky —
    -- jen po dobu trvání zvedne cíl, ke kterému se ponorka rozjíždí.
    local mul = 1
    if (self.boost_time or 0) > 0 then
        self.boost_time = self.boost_time - dtime
        mul = SUB_BOOST_MUL
        if self.boost_time <= 0 then
            pilot:set_fov(0)
        end
    end

    -- Směr pohledu: vodorovná složka + sklon (look_v kladné = dolů)
    local fwd = minetest.yaw_to_dir(look_h)
    local cv, sv = math.cos(look_v), math.sin(look_v)
    local fx, fy, fz = fwd.x * cv, -sv, fwd.z * cv
    -- Doprava od směru pohledu (rotace o -90° kolem svislé osy)
    local rx, rz = fwd.z, -fwd.x

    local target = {
        x = (fx * surge * C.SUB_SPEED_MAX + rx * sway * C.SUB_STRAFE) * mul,
        y = (fy * surge * C.SUB_SPEED_MAX + heave * C.SUB_VERT) * mul,
        z = (fz * surge * C.SUB_SPEED_MAX + rz * sway * C.SUB_STRAFE) * mul,
    }

    -- Přiblížení k cíli omezeným krokem = setrvačnost i doplavání do klidu.
    -- Krok se omezuje na délku vektoru (ne po osách), aby diagonála
    -- nezrychlovala rychleji než přímý směr a aby se na nule opravdu stálo.
    local vel = self.object:get_velocity()
    local dx, dvy, dz = target.x - vel.x, target.y - vel.y, target.z - vel.z
    local dlen = math.sqrt(dx * dx + dvy * dvy + dz * dz)
    local step = C.SUB_ACCEL * dtime
    if dlen > step and dlen > 0 then
        local k = step / dlen
        vel = {x = vel.x + dx * k, y = vel.y + dvy * k, z = vel.z + dz * k}
    else
        vel = target
    end
    self.object:set_velocity(vel)

    -- HUD, kolizní poškození i výfuk čtou self.speed — držíme ho na skutečné
    -- velikosti rychlosti, ať fungují beze změny
    self.speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)

    -- Trup se dotáčí za pohledem (pohyb ale jde vždy podle pohledu, ne podle
    -- trupu — dotáčení je čistě vizuální, těžká ponorka smí zaostávat)
    local dyaw = wrap_angle(look_h + math.pi - rot.y)
    local chase = C.SUB_TURN * dtime
    rot.y = rot.y + clamp(dyaw, -chase, chase)

    -- Sklon: mnohem volnější než u letadla, ponorka smí zamířit skoro kolmo
    local target_pitch = clamp(-look_v, -C.SUB_PITCH_MAX, C.SUB_PITCH_MAX)
    local pstep = C.PITCH_RATE * 1.5 * dtime
    self.pitch = (self.pitch or 0)
        + clamp(target_pitch - (self.pitch or 0), -pstep, pstep)
    rot.x = -self.pitch

    -- Náklon je čistě kosmetický: lehce se položí do strafu a do zatáčky
    local target_roll = clamp(-sway * 0.6 - dyaw, -1, 1) * C.ROLL_MAX * 0.25
    local rstep = C.ROLL_SPEED * dtime
    self.roll = (self.roll or 0)
        + clamp(target_roll - (self.roll or 0), -rstep, rstep)
    rot.z = self.roll

    self.object:set_rotation(rot)
    return rot, vel
end
