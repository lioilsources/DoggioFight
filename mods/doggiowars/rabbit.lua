-- doggiowars/rabbit.lua
-- "Zajíc" — zlatá AI loď, která letí trať závodu před hráčem.
-- Sleduje Catmull-Rom splajnu (race.lua), rubber-banduje rychlost podle
-- vzdálenosti hráče a když se hráč moc vzdálí, krouží a čeká (tutoriál).

local WAIT_ENTER_DIST  = 130  -- vzdálenost, při které králík začne čekat
local WAIT_LEAVE_DIST  = 55   -- hráč se přiblížil → pokračuje
local WAIT_RADIUS      = 25
local WAIT_SPEED       = 12

local function wrap_angle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

local function trail(self, dtime)
    self.trail_timer = (self.trail_timer or 0) + dtime
    if self.trail_timer < 0.1 then return end
    self.trail_timer = 0
    local pos = self.object:get_pos()
    if not pos then return end
    minetest.add_particlespawner({
        amount     = 6,
        time       = 0.1,
        minpos     = {x = pos.x - 0.3, y = pos.y - 0.3, z = pos.z - 0.3},
        maxpos     = {x = pos.x + 0.3, y = pos.y + 0.3, z = pos.z + 0.3},
        minvel     = {x = 0, y = -0.5, z = 0},
        maxvel     = {x = 0, y =  0.5, z = 0},
        minexptime = 0.5,
        maxexptime = 1.2,
        minsize    = 1.0,
        maxsize    = 2.5,
        texture    = "doggiowars_particle_engine.png^[colorize:#ffd75e:180",
        glow       = 14,
    })
end

-- Rotace z vektoru rychlosti; bank z rychlosti zatáčení (vyhlazený),
-- forced_roll přepisuje bank (showcase barrel roll)
local function set_flight_rotation(self, vel, dtime, forced_roll)
    local hlen = math.sqrt(vel.x * vel.x + vel.z * vel.z)
    if hlen < 0.05 then return end
    -- mesh quirk: entita letí směrem yaw_to_dir(rot.y + pi)
    local yaw = minetest.dir_to_yaw({x = vel.x, y = 0, z = vel.z}) + math.pi
    local roll
    if forced_roll then
        roll = forced_roll
        self.roll_s = 0
    else
        local rate = wrap_angle(yaw - (self.last_yaw or yaw))
            / math.max(dtime, 0.01)
        local target = math.min(math.max(rate * 0.6, -1.2), 1.2)
        self.roll_s = (self.roll_s or 0)
            + (target - (self.roll_s or 0)) * math.min(dtime * 5, 1)
        roll = self.roll_s
    end
    self.last_yaw = yaw
    self.object:set_rotation({
        x = -math.atan2(vel.y, hlen),
        y = yaw,
        z = roll,
    })
end

local function fly_toward(self, target, speed, dtime)
    local pos = self.object:get_pos()
    if not pos then return end
    local to = vector.subtract(target, pos)
    local dist = vector.length(to)
    if dist < 0.05 then return end
    local vel = vector.multiply(to, speed / dist)
    self.object:set_velocity(vel)
    set_flight_rotation(self, vel, dtime)
end

minetest.register_entity("doggiowars:rabbit", {
    initial_properties = {
        visual            = "mesh",
        mesh              = "doggiowars_fighter_01.obj",
        textures          = {"doggiowars_fighter_01.png^[multiply:#ffd75e"},
        physical          = false,
        collide_with_objects = false,
        collisionbox      = {-1.5, -0.5, -1.5, 1.5, 0.5, 1.5},
        selectionbox      = {-1.5, -0.5, -1.5, 1.5, 0.5, 1.5},
        visual_size       = {x = 2, y = 2, z = 2},
        glow              = 12,
        static_save       = false,
        pointable         = false,
    },

    route       = nil,
    player_name = nil,
    seg         = 1,
    t           = 0,
    wait_mode   = false,
    celebrate   = false,

    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        self.object:set_acceleration({x = 0, y = 0, z = 0})
    end,

    on_step = function(self, dtime)
        local race = doggiowars.race

        -- oslavné loopingy v cíli (než ho race.finish odklidí)
        if self.celebrate then
            self.cel_trick = self.cel_trick
                or {name = "loop", t = 0, dur = 2.0, dir = 1}
            local rot, vel, done = doggiowars.tricks.step_trick(self.cel_trick,
                {yaw = self.cel_yaw or 0, pitch = 0, speed = 18}, dtime)
            if done then self.cel_trick.t = 0 end
            self.object:set_rotation(rot)
            self.object:set_velocity(vel)
            trail(self, dtime)
            return
        end

        if not self.route then return end

        -- bez hráče nebo bez běžícího závodu nemá zajíc smysl
        local player = self.player_name
            and minetest.get_player_by_name(self.player_name)
        if not player or not race.active[self.player_name] then
            self.object:remove()
            return
        end

        local pos = self.object:get_pos()
        if not pos then return end
        local pfighter = doggiowars.get_player_fighter(player)
        local ppos = pfighter and pfighter.object:get_pos() or player:get_pos()
        local d = vector.distance(pos, ppos)

        -- čekací mód: kroužení kolem bodu trati, dokud se hráč nepřiblíží
        if self.wait_mode then
            self.wait_angle = (self.wait_angle or 0)
                + dtime * (WAIT_SPEED / WAIT_RADIUS)
            local cen = self.wait_center
            fly_toward(self, {
                x = cen.x + math.cos(self.wait_angle) * WAIT_RADIUS,
                y = cen.y + math.sin(self.wait_angle * 2) * 5,
                z = cen.z + math.sin(self.wait_angle) * WAIT_RADIUS,
            }, WAIT_SPEED, dtime)
            trail(self, dtime)
            if d < WAIT_LEAVE_DIST then
                self.wait_mode = false
            end
            return
        end

        if d > WAIT_ENTER_DIST then
            self.wait_mode = true
            self.wait_center = race.eval(self.route, self.seg, self.t)
            self.wait_angle = 0
            race.notify(self.player_name, "ZAJÍC ČEKÁ — dohoň ho!", 0xFFD75E)
            return
        end

        -- rubber-band: rychlost bodu trati škálovaná vzdáleností hráče
        local m = self.route.meta[self.seg] or {}
        local point_speed = m.speed or 25
        local speed = point_speed
            * math.min(math.max(1 - (d - 60) / 200, 0.55), 1.15)
        if d < 20 then
            speed = speed * 1.2
        end

        -- posun po splajně
        local prev_seg = self.seg
        local finished
        self.seg, self.t, finished =
            race.advance(self.route, self.seg, self.t, speed * dtime)

        if finished then
            self.celebrate = true
            self.cel_yaw = self.object:get_rotation().y
            race.notify(self.player_name,
                "ZAJÍC V CÍLI — doleť k němu!", 0xFFD75E)
            return
        end

        if self.seg ~= prev_seg then
            race.on_rabbit_segment(self.player_name, self.seg)
        end

        -- korekce velké odchylky od splajny (lag, kolize s ničím)
        local cur = race.eval(self.route, self.seg, self.t)
        if vector.distance(pos, cur) > 10 then
            self.object:move_to(cur, true)
            pos = cur
        end

        -- leť k bodu ~0.15 s před sebou (hladká interpolace na klientu)
        local aseg, at = race.advance(self.route, self.seg, self.t,
            math.max(speed * 0.15, 3))
        local ahead = race.eval(self.route, aseg, at)
        local to = vector.subtract(ahead, pos)
        local dist = vector.length(to)
        local vel = dist > 0.05 and vector.multiply(to, speed / dist)
            or {x = 0, y = 0, z = 0}
        self.object:set_velocity(vel)

        -- showcase segment: barrel roll napříč segmentem
        local forced_roll
        if m.trick == "barrel_roll" then
            forced_roll = 2 * math.pi * self.t
        end
        set_flight_rotation(self, vel, dtime, forced_roll)

        trail(self, dtime)
    end,
})
