-- doggiowars/vehicle.lua
-- Entita stíhačky. Hráč JE loď — mount při joinu, žádné nasedání/vysedání.

local C = doggiowars.const

-- Kamera "na nose": mesh (visual_size 2, collisionbox ±1.5) končí ~3 jednotky
-- od středu entity, offset 4 dopředu drží celý mesh za near plane kamery
local EYE_OFFSET = {x = 0, y = 0.5, z = 4}

-- Hráči čekající na naplánovaný respawn — watchdog je nesmí remountovat dřív
local respawn_pending = {}

-- Gamepad diagnostika (přepíná /gp): živě ukazuje páčky a stisknutá tlačítka,
-- aby šlo namapovat konkrétní ovladač (Xbox/PS4) na herní akce.
doggiowars.gp_debug = doggiowars.gp_debug or {}

-- Řídicí režim per hráč (/mode): "sub" = ponorka (VÝCHOZÍ), "fighter" =
-- letadlo. Přežívá respawn entity — klíčem je jméno hráče, ne entita.
doggiowars.mode = doggiowars.mode or {}

-- Jediné místo, kde se rozhoduje o výchozím režimu — nezapsaný hráč jede
-- ponorku
function doggiowars.get_mode(name)
    return doggiowars.mode[name or ""] or "sub"
end
local GP_KEYS = {"up", "down", "left", "right", "jump", "aux1",
                 "sneak", "dig", "place", "zoom"}
local function gp_debug_str(ctrl, look_v, f)
    local on = {}
    for _, k in ipairs(GP_KEYS) do
        if ctrl[k] then on[#on + 1] = k end
    end
    -- Klíč ke čtení: když SPD roste bez doteku páček — thr>0 = plyn (drift
    -- levé páčky / špatná osa movement_y), thr=0 = dive fyzika (let < -26°).
    -- pitch = kam koukáš (pravá páčka), let = skutečný sklon letadla.
    return string.format(
        "GAMEPAD  L(%+.2f,%+.2f)  thr=%+.2f  SPD=%.0f  pitch=%+.0f\194\176"
            .. "  let=%+.0f\194\176  [ %s ]",
        ctrl.movement_x or 0, ctrl.movement_y or 0,
        f and f.dbg_thr or 0, f and f.speed or 0, math.deg(look_v or 0),
        math.deg(f and f.pitch or 0),
        #on > 0 and table.concat(on, " ") or "—")
end

local function wrap_angle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

---------------------------------------------------------------------------
-- Exhaust particle spawner
---------------------------------------------------------------------------

local function spawn_exhaust(pos, dir, speed)
    local intensity = math.min(speed / C.SPEED_MAX, 1)
    minetest.add_particlespawner({
        amount   = math.floor(3 + 7 * intensity),
        time     = 0.1,
        minpos   = {x = pos.x - 0.1, y = pos.y - 0.3, z = pos.z - 0.1},
        maxpos   = {x = pos.x + 0.1, y = pos.y + 0.3, z = pos.z + 0.1},
        minvel   = {x = -dir.x * 5, y = -0.5, z = -dir.z * 5},
        maxvel   = {x = -dir.x * 8, y =  0.5, z = -dir.z * 8},
        minacc   = {x = 0, y = -1, z = 0},
        maxacc   = {x = 0, y = -2, z = 0},
        minexptime = 0.3,
        maxexptime = 0.8,
        minsize  = 0.5,
        maxsize  = 1.5,
        texture  = "doggiowars_particle_engine.png",
        glow     = math.floor(8 * intensity),
    })
end

---------------------------------------------------------------------------
-- Mount / dismount — hráč je vždy pilotem své stíhačky
---------------------------------------------------------------------------

function doggiowars.get_player_fighter(player)
    local parent = player and player:get_attach()
    local ent = parent and parent:get_luaentity()
    if ent and ent.name == "doggiowars:fighter" and not ent.is_dead then
        return ent
    end
    return nil
end

-- yaw (nepovinný) = kterým směrem má stíhačka po nasazení koukat; spawnovací
-- funkce ho vracejí tak, aby hráč měl ostrov před sebou
function doggiowars.mount_player(player, pos, yaw)
    if not player or not player:is_player() then return end
    local name = player:get_player_name()
    if not pos then
        local ppos = player:get_pos()
        pos = {x = ppos.x, y = ppos.y + 2, z = ppos.z}
    end
    local obj = minetest.add_entity(pos, "doggiowars:fighter")
    if not obj then return end
    local self = obj:get_luaentity()
    self.pilot = player
    self.pilot_name = name
    self.score = doggiowars.tricks.scores[name] or 0
    if yaw then
        obj:set_rotation({x = 0, y = yaw + math.pi, z = 0})
    end

    player:set_attach(obj, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    -- srovnat zaměřovač se směrem letu (letadlo se pak dotáčí za pohledem)
    local ryaw = (obj:get_rotation() or {y = 0}).y
    player:set_look_horizontal(ryaw + math.pi)
    player:set_look_vertical(0)
    player:set_eye_offset(EYE_OFFSET, EYE_OFFSET)
    -- zoom_fov = 72 ≈ normální FOV: klient pak spolehlivě posílá zoom bit
    -- (klávesa Z = boost) a vizuálně se nic nemění
    player:set_properties({visual_size = {x = 0, y = 0}, zoom_fov = 72})
    if player.set_camera then
        player:set_camera({mode = "first"})
    end
    player:set_physics_override({speed = 0, jump = 0, gravity = 0})
    player:set_fov(0)
    player:hud_set_flags({
        hotbar = false, wielditem = false, healthbar = false,
        breathbar = false, crosshair = true,
    })
    doggiowars.hud.init(player)
    respawn_pending[name] = nil
    return obj
end

-- Interní úklid (odchod ze hry) — není to herní akce, vysedání neexistuje
function doggiowars.dismount_player(player)
    if not player or not player:is_player() then return end
    player:set_detach()
    player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    player:set_properties({visual_size = {x = 1, y = 1}, zoom_fov = 0})
    if player.set_camera then
        player:set_camera({mode = "any"})
    end
    player:set_physics_override({speed = 1, jump = 1, gravity = 1})
    player:hud_set_flags({
        hotbar = true, wielditem = true, healthbar = true,
        breathbar = true, crosshair = true,
    })
end

---------------------------------------------------------------------------
-- Fighter entity definition
---------------------------------------------------------------------------

minetest.register_entity("doggiowars:fighter", {
    initial_properties = {
        visual            = "mesh",
        mesh              = "doggiowars_fighter_01.obj",
        textures          = {"doggiowars_fighter_01.png"},
        physical          = true,
        collide_with_objects = false,
        collisionbox      = {-1.5, -0.5, -1.5, 1.5, 0.5, 1.5},
        selectionbox      = {-1.5, -0.5, -1.5, 1.5, 0.5, 1.5},
        visual_size       = {x = 2, y = 2, z = 2},
        static_save       = false,
        stepheight        = 0,
    },

    pilot          = nil,
    pilot_name     = nil,
    speed          = 15,
    pitch          = 0,
    roll           = 0,
    exhaust_timer  = 0,
    hp             = 100,
    shoot_cooldown = 0,
    smoke_timer    = 0,
    is_dead        = false,

    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
        -- Disable gravity — plane handles its own physics
        self.object:set_acceleration({x = 0, y = 0, z = 0})
        self.hp = 100
        doggiowars.tricks.init(self)
    end,

    on_step = function(self, dtime, moveresult)
        if self.is_dead then return end

        -- Fighter existuje jen s živým pilotem na palubě
        local pilot = self.pilot
        if not pilot or not pilot:is_player()
                or pilot:get_attach() ~= self.object then
            self.object:remove()
            return
        end

        local ctrl = pilot:get_player_control()
        local events = doggiowars.tricks.update_input(self, ctrl)
        self.iframes = math.max(0, (self.iframes or 0) - dtime)

        if doggiowars.gp_debug[self.pilot_name or ""] then
            doggiowars.hud.set(pilot, "gpdebug",
                {text = gp_debug_str(ctrl, pilot:get_look_vertical(), self)})
        end

        -- Kolizní poškození: náraz do terénu v rychlosti bolí (pomalé
        -- škrtnutí pod ~15 m/s je zdarma — učí opatrné létání)
        self.crash_cooldown = math.max(0, (self.crash_cooldown or 0) - dtime)
        if moveresult and moveresult.collides and self.crash_cooldown <= 0
                and (self.speed or 0) > 15 then
            self.crash_cooldown = 0.5
            local dmg = math.floor((self.speed - 10) * 2.5)
            self.speed = C.SPEED_MIN
            self:damage_fighter(dmg, true)
            if self.is_dead then return end
        end

        local sub_mode = doggiowars.get_mode(self.pilot_name) == "sub"
        local rot, vel

        if self.trick then
            -- Skriptovaný trik přebírá řízení (looping potřebuje pitch
            -- za clampem ±PITCH_MAX)
            rot, vel = doggiowars.tricks.step_active(self, dtime)
            self.object:set_rotation(rot)
            self.object:set_velocity(vel)
            -- kamera sleduje trik (v apexu loopingu se překlopí přes yaw)
            local th = math.sqrt(vel.x * vel.x + vel.z * vel.z)
            if th > 0.05 then
                pilot:set_look_horizontal(
                    minetest.dir_to_yaw({x = vel.x, y = 0, z = vel.z}))
                pilot:set_look_vertical(-math.atan2(vel.y, th))
            end
        elseif sub_mode then
            -- PONORKA: 5DoF hover. Levá páčka = tah/úkrok, pohled (myš nebo
            -- pravá páčka) = kurz+sklon, jump/sneak = stoupání/klesání.
            -- Žádný roll, žádné triky (check_triggers se tu nevolá).
            rot = self.object:get_rotation()
            local look_h = pilot:get_look_horizontal()
            local look_v = pilot:get_look_vertical()

            -- yaw + pitch: trup se dotáčí za zaměřovačem; left/right/jump/
            -- sneak pohledem NEhýbou — v ponorce mají nový význam
            local chase = 2.0 * dtime
            local dy = wrap_angle(look_h + math.pi - rot.y)
            rot.y = rot.y + math.max(-chase, math.min(chase, dy))

            local target_pitch = math.max(-C.SUB_PITCH_MAX,
                math.min(C.SUB_PITCH_MAX, -look_v))
            local pstep = C.PITCH_RATE * 1.5 * dtime
            self.pitch = self.pitch + math.max(-pstep,
                math.min(pstep, target_pitch - self.pitch))

            -- roll: žádné bankování, plynule srovnat do nuly
            local rstep = C.ROLL_DECAY * dtime
            self.roll = (self.roll or 0)
                - math.max(-rstep, math.min(rstep, self.roll or 0))

            -- vstupy: levá páčka analogově, digitální klávesy jako záloha
            -- (stejný deadzone vzor jako plyn stíhačky)
            local thr = math.max(-1, math.min(1, ctrl.movement_y or 0))
            if math.abs(thr) < 0.25 then
                thr = (ctrl.up and 1 or 0) - (ctrl.down and 1 or 0)
            end
            self.dbg_thr = thr
            local sway = math.max(-1, math.min(1, ctrl.movement_x or 0))
            if math.abs(sway) < 0.25 then
                sway = (ctrl.right and 1 or 0) - (ctrl.left and 1 or 0)
            end
            -- Svislý pohyb: sneak nahoru, jump dolů. Vypadá to obráceně, ale
            -- sedí to na fyzická tlačítka DualShocku pod joystick_type=ps5,
            -- kde X posílá sneak a ○ jump (ověřeno /gp) — X tedy stoupá.
            local heave = (ctrl.sneak and 1 or 0) - (ctrl.jump and 1 or 0)

            -- cílová rychlost: dopředu po skloněné ose trupu, úkrok vodorovně
            -- kolmo na kurz (right = (f.z, -f.x)), heave svisle ve světových
            -- osách nezávisle na sklonu nosu
            local dir = minetest.yaw_to_dir(rot.y + math.pi)
            local cp, sp = math.cos(self.pitch), math.sin(self.pitch)
            local tvx = dir.x * cp * thr * C.SUB_SPEED
                + dir.z * sway * C.SUB_STRAFE
            local tvy = sp * thr * C.SUB_SPEED + heave * C.SUB_VERT_SPEED
            local tvz = dir.z * cp * thr * C.SUB_SPEED
                - dir.x * sway * C.SUB_STRAFE

            -- hover model: rychlost se dojíždí k cílové, puštěné ovládání
            -- znamená cíl (0,0,0) → ponorka plynule zastaví a visí
            local v = self.sub_vel or self.object:get_velocity()
                or {x = 0, y = 0, z = 0}
            local astep = C.SUB_ACCEL * dtime
            v.x = v.x + math.max(-astep, math.min(astep, tvx - v.x))
            v.y = v.y + math.max(-astep, math.min(astep, tvy - v.y))
            v.z = v.z + math.max(-astep, math.min(astep, tvz - v.z))
            self.sub_vel = v
            self.speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

            rot.x = -self.pitch
            rot.z = self.roll
            self.object:set_rotation(rot)
            vel = v
            self.object:set_velocity(vel)
        else
            rot = self.object:get_rotation()

            -- Plyn: čistě analogově z levé páčky (movement_y: +1 dopředu,
            -- -1 dozadu; klávesnice W/S dává plné ±1). Rychlost DRŽÍ tam,
            -- kam ji hráč nastaví — žádné samovolné vracení. Bity up/down
            -- jen jako záloha (klient je z páčky spíná až při velké výchylce,
            -- proto dřív jemný plyn "nereagoval").
            local thr = math.max(-1, math.min(1, ctrl.movement_y or 0))
            if math.abs(thr) < 0.25 then
                thr = (ctrl.up and 1 or 0) - (ctrl.down and 1 or 0)
            end
            self.dbg_thr = thr
            if thr > 0 and self.speed < C.SPEED_MAX then
                self.speed = math.min(self.speed + 8 * dtime * thr, C.SPEED_MAX)
            elseif thr < 0 then
                self.speed = math.max(self.speed + 10 * dtime * thr, C.SPEED_MIN)
            end

            -- Airbrake drift: S + A/D = ostrá zatáčka za cenu rychlosti
            local turn = C.TURN_SPEED
            local drifting = ctrl.down and (ctrl.left or ctrl.right)
            if drifting then
                turn = C.TURN_SPEED * 2.2
                self.speed = math.max(self.speed - 12 * dtime, C.SPEED_MIN)
                doggiowars.tricks.add_raw_score(self, 50 * dtime)
            end

            -- Mouse-flight: myš (nebo pravá páčka gamepadu) míří zaměřovačem,
            -- letadlo se za ním dotáčí. Levá páčka / A-D / Space-Shift natáčí
            -- pohledem stejně jako myš — nativní joystick tak funguje přímo.
            -- Zatáčení je proporcionální podle výchylky páčky (klávesnice = ±1).
            local xmag = math.abs(ctrl.movement_x or 1)
            if xmag < 0.001 then xmag = 1 end
            local look_h = pilot:get_look_horizontal()
            local look_v = pilot:get_look_vertical()
            local keys_steered = false
            if ctrl.left then
                look_h = look_h + turn * dtime * xmag
                keys_steered = true
            end
            if ctrl.right then
                look_h = look_h - turn * dtime * xmag
                keys_steered = true
            end
            if ctrl.jump then
                look_v = math.max(look_v - C.PITCH_RATE * dtime, -1.25)
                keys_steered = true
            elseif ctrl.sneak then
                look_v = math.min(look_v + C.PITCH_RATE * dtime, 1.25)
                keys_steered = true
            end
            if keys_steered then
                pilot:set_look_horizontal(look_h)
                pilot:set_look_vertical(look_v)
            end

            -- yaw: dotáčení za zaměřovačem nejkratší cestou
            local chase = math.max(turn * 1.3, 2.0) * dtime
            local dy = wrap_angle(look_h + math.pi - rot.y)
            rot.y = rot.y + math.max(-chase, math.min(chase, dy))

            -- pitch: cíl z vertikálního pohledu (look_v kladné = dolů)
            local target_pitch = math.max(-C.PITCH_MAX,
                math.min(C.PITCH_MAX, -look_v))
            local pstep = C.PITCH_RATE * 1.5 * dtime
            self.pitch = self.pitch + math.max(-pstep,
                math.min(pstep, target_pitch - self.pitch))

            -- Náklon: automaticky do zatáčky (podle toho, jak ostře se
            -- letadlo dotáčí za zaměřovačem); po srovnání kurzu se vyrovná
            local target_roll = math.max(-1, math.min(1, -dy * 2.0))
                * C.ROLL_MAX * 0.7
            local rstep = C.ROLL_SPEED * dtime
            self.roll = (self.roll or 0)
                + math.max(-rstep, math.min(rstep, target_roll - self.roll))

            -- Boost + gravitační fyzika: strmý střemhlavý let zrychluje
            -- (úměrně sklonu, až od ~26° dolů), stoupání rychlost ubírá.
            -- Mírný pohled dolů (prohlížení ostrova) už NEzrychluje.
            if (self.boost_time or 0) > 0 then
                self.boost_time = self.boost_time - dtime
                self.speed = 60
                if self.boost_time <= 0 then
                    pilot:set_fov(0)
                end
            elseif self.pitch < -0.45 then
                self.speed = math.min(
                    self.speed + 80 * dtime * (-self.pitch - 0.45),
                    C.SPEED_MAX * 1.5)
            else
                if self.pitch > 0.3 then
                    -- Stoupání ubírá rychlost, ale plyn proti tomu táhne:
                    -- plný plyn vykryje 70 % ztráty (motor vs. gravitace),
                    -- bez plynu se krvácí naplno. Páčka tak reaguje vždy.
                    local bleed = 40 * (self.pitch - 0.3)
                        * (1 - 0.7 * math.max(thr, 0))
                    self.speed = math.max(
                        self.speed - bleed * dtime, C.SPEED_MIN)
                end
                -- overspeed z dive/boostu se po srovnání rychle vyčerpá
                if self.speed > C.SPEED_MAX then
                    self.speed = math.max(C.SPEED_MAX, self.speed - 12 * dtime)
                end
            end

            rot.x = -self.pitch
            rot.z = self.roll
            self.object:set_rotation(rot)

            -- Velocity from direction + speed
            local dir = minetest.yaw_to_dir(rot.y + math.pi)
            vel = {
                x = dir.x * self.speed,
                y = math.sin(self.pitch) * self.speed,
                z = dir.z * self.speed,
            }
            self.object:set_velocity(vel)

            doggiowars.tricks.check_triggers(self, events, pilot)
        end

        -- Eye-lean: kamera "sklouzne" do zatáčky podle bankování — engine
        -- roll horizontu neumí (ověřeno v 5.15), tohle je pohybová náhrada.
        -- Ve triku (barrel roll = plná otočka) se vrací k nule, ať nekmitá.
        local lean = 0
        if not self.trick then
            lean = math.max(-1, math.min(1, (self.roll or 0) / 1.2))
        end
        local lx = lean * 1.6
        local ly = -math.abs(lean) * 0.4
        if math.abs(lx - (self.lean_x or 0)) > 0.03
                or math.abs(ly - (self.lean_y or 0)) > 0.03 then
            self.lean_x, self.lean_y = lx, ly
            pilot:set_eye_offset(
                {x = EYE_OFFSET.x + lx, y = EYE_OFFSET.y + ly, z = EYE_OFFSET.z},
                EYE_OFFSET)
        end

        local hlen = math.sqrt(vel.x * vel.x + vel.z * vel.z)

        -- Proximity charge: let těsně kolem terénu nabíjí boost
        doggiowars.tricks.update_passive(self, dtime)

        -- Střelba: dig (LMB / gamepad R2) nebo aux1 (E), cooldown 0.15 s
        self.shoot_cooldown = math.max(0, (self.shoot_cooldown or 0) - dtime)
        if (ctrl.dig or ctrl.aux1) and self.shoot_cooldown <= 0 then
            self.shoot_cooldown = 0.15
            doggiowars.shoot_bullet(self)
        end

        -- Damage smoke: light at HP < 70, heavy fire at HP < 30
        if (self.hp or 100) < 70 then
            self.smoke_timer = (self.smoke_timer or 0) + dtime
            local interval = (self.hp or 100) < 30 and 0.1 or 0.25
            if self.smoke_timer >= interval then
                self.smoke_timer = 0
                local spos = self.object:get_pos()
                minetest.add_particlespawner({
                    amount     = (self.hp or 100) < 30 and 8 or 3,
                    time       = interval,
                    minpos     = {x = spos.x - 0.3, y = spos.y - 0.2, z = spos.z - 0.3},
                    maxpos     = {x = spos.x + 0.3, y = spos.y + 0.5, z = spos.z + 0.3},
                    minvel     = {x = -1, y = 1, z = -1},
                    maxvel     = {x =  1, y = 4, z =  1},
                    minacc     = {x = 0,  y = 0.5, z = 0},
                    maxacc     = {x = 0,  y = 1,   z = 0},
                    minexptime = 0.5,
                    maxexptime = 2.0,
                    minsize    = 2,
                    maxsize    = 6,
                    texture    = "doggiowars_particle_engine.png",
                    glow       = (self.hp or 100) < 30 and 5 or 0,
                })
            end
        end

        -- Exhaust particles (throttled to every 0.1s)
        self.exhaust_timer = (self.exhaust_timer or 0) + dtime
        if self.exhaust_timer >= 0.1 and hlen > 0.05 then
            self.exhaust_timer = 0
            local pos = self.object:get_pos()
            spawn_exhaust(pos, {x = vel.x / hlen, z = vel.z / hlen}, self.speed)
        end

        -- HUD update (throttled to every 0.15s)
        self.hud_timer = (self.hud_timer or 0) + dtime
        if self.hud_timer >= 0.15 then
            self.hud_timer = 0
            doggiowars.hud.update_flight(pilot, self)
        end
    end,

    damage_fighter = function(self, amount, bypass_iframes)
        if self.is_dead then return end
        -- Barrel roll dává krátkou nesmrtelnost vůči střelám (náraz
        -- do terénu ale bolí vždy)
        if not bypass_iframes and (self.iframes or 0) > 0 then return end
        self.hp = math.max(0, (self.hp or 100) - amount)
        if self.hp <= 0 then
            self:die()
        end
    end,

    die = function(self)
        if self.is_dead then return end
        self.is_dead = true
        local pos = self.object:get_pos()
        local pilot_name = self.pilot_name
        local player = pilot_name and minetest.get_player_by_name(pilot_name)

        -- Session skóre přežívá zničení stíhačky
        if pilot_name then
            doggiowars.tricks.scores[pilot_name] = self.score or 0
        end

        -- Odpojit pilota — zůstává neviditelný na místě havárie (death cam),
        -- gravity 0 z physics_override ho drží na místě
        if player and player:get_attach() == self.object then
            player:set_detach()
        end

        -- Big explosion at crash site
        if pos then
            doggiowars.explode_voxels(pos, 5)
        end

        if pilot_name then
            -- Hook pro race.lua — smrt během závodu = RACE FAILED
            if doggiowars.race_on_pilot_died then
                doggiowars.race_on_pilot_died(pilot_name)
            end
            respawn_pending[pilot_name] = true
            minetest.chat_send_player(pilot_name,
                "Fighter destroyed! Respawning...")
            minetest.after(3, function()
                respawn_pending[pilot_name] = nil
                local p = minetest.get_player_by_name(pilot_name)
                if not p then return end
                local ppos = p:get_pos()
                local sp, yaw
                if doggiowars.spawn_pos_near then
                    sp, yaw = doggiowars.spawn_pos_near(ppos.x, ppos.z)
                else
                    sp = {x = ppos.x, y = C.SPAWN_HEIGHT, z = ppos.z}
                end
                doggiowars.mount_player(p, sp, yaw)
            end)
        end

        self.object:remove()
    end,

    on_deactivate = function(self)
        -- Unload entity → odpojit pilota, watchdog ho remountuje
        local player = self.pilot_name
            and minetest.get_player_by_name(self.pilot_name)
        if player and player:get_attach() == self.object then
            player:set_detach()
        end
    end,
})

---------------------------------------------------------------------------
-- Watchdog — každý připojený hráč musí sedět v živé stíhačce
---------------------------------------------------------------------------

local watchdog_timer = 0
minetest.register_globalstep(function(dtime)
    watchdog_timer = watchdog_timer + dtime
    if watchdog_timer < 2 then return end
    watchdog_timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        if not respawn_pending[name]
                and not doggiowars.get_player_fighter(player) then
            local pos = player:get_pos()
            doggiowars.mount_player(player, {
                x = pos.x,
                y = math.max(pos.y + 2, 100),
                z = pos.z,
            })
        end
    end
end)

minetest.register_on_respawnplayer(function(player)
    local name = player:get_player_name()
    respawn_pending[name] = nil
    minetest.after(0.1, function()
        local p = minetest.get_player_by_name(name)
        if p and not doggiowars.get_player_fighter(p) then
            local sp, yaw
            if doggiowars.spawn_pos then
                sp, yaw = doggiowars.spawn_pos()
            else
                sp = {x = 0, y = C.SPAWN_HEIGHT, z = 0}
            end
            doggiowars.mount_player(p, sp, yaw)
        end
    end)
    return true
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local fighter = doggiowars.get_player_fighter(player)
    doggiowars.dismount_player(player)
    if fighter then
        doggiowars.tricks.scores[name] = fighter.score or 0
        fighter.object:remove()
    end
    respawn_pending[name] = nil
    if doggiowars.race_on_player_left then
        doggiowars.race_on_player_left(name)
    end
end)

---------------------------------------------------------------------------
-- Debug: zahodit a znovu nasadit stíhačku
---------------------------------------------------------------------------

minetest.register_chatcommand("respawn_fighter", {
    description = "Debug: respawn your fighter at your position",
    privs = {interact = true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found"
        end
        local fighter = doggiowars.get_player_fighter(player)
        if fighter then
            player:set_detach()
            fighter.object:remove()
        end
        local pos = player:get_pos()
        doggiowars.mount_player(player, {x = pos.x, y = pos.y + 2, z = pos.z})
        return true, "Fighter respawned!"
    end,
})

-- Přesun k nejbližšímu ostrovu (funguje v jakémkoli světě — chunk se
-- v případě potřeby dogeneruje). Řeší "nevidím žádné ostrovy".
-- yaw (nepovinný) = kam se má hráč po přeletu dívat. Bez něj zůstane
-- pohled beze změny.
local function fly_player_to(player, sp, yaw)
    -- zajistit vygenerování cílové oblasti, ať tam ostrov opravdu je
    if minetest.emerge_area then
        minetest.emerge_area(
            {x = sp.x - 48, y = sp.y - 96, z = sp.z - 48},
            {x = sp.x + 48, y = sp.y + 48,  z = sp.z + 48})
    end
    local f = doggiowars.get_player_fighter(player)
    if f and f.object then
        f.object:set_pos(sp)
        f.speed = 12
        f.sub_vel = nil          -- ponorka: zahodit setrvačnost z minulého místa
        if yaw then
            -- trup i zaměřovač srovnat na ostrov (rot.y = look + PI, viz
            -- dotáčení v on_step) — jinak by se letadlo teprve otáčelo
            player:set_look_horizontal(yaw)
            player:set_look_vertical(0)
            f.pitch, f.roll = 0, 0
            f.object:set_rotation({x = 0, y = yaw + math.pi, z = 0})
        end
    else
        player:set_pos(sp)
        if yaw then
            player:set_look_horizontal(yaw)
            player:set_look_vertical(0)
        end
    end
end

-- Aliasy pro /island <biome> — plné názvy biomů (glacial, volcanic, desert,
-- jungle, savanna, swamp, crystal, verdant, atoll, barren, ashen, mycelial)
-- fungují přímo, tohle jsou intuitivní zkratky
local BIOME_ALIAS = {
    ice = "glacial", snow = "glacial",
    volcano = "volcanic", lava = "volcanic", fire = "volcanic",
    sand = "desert",
    green = "verdant", forest = "verdant",
    mushroom = "mycelial", shroom = "mycelial",
    ash = "ashen", burnt = "ashen",
    dead = "barren", rock = "barren",
}

minetest.register_chatcommand("island", {
    description = "Fly to the nearest island; /island <biome> = nearest of that biome",
    params = "[biome]",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local pos = player:get_pos()
        param = (param or ""):gsub("%s+", ""):lower()

        if param ~= "" then
            local target = BIOME_ALIAS[param] or param
            local isl, dist = doggiowars.nearest_island_of_biome(pos.x, pos.z, target)
            if not isl then
                local names = {}
                for i = 0, (doggiowars.biome_count or 1) - 1 do
                    names[#names + 1] = doggiowars.biomes[i].name
                end
                return false, "Unknown biome '" .. param .. "' (or none nearby). Biomes: "
                    .. table.concat(names, ", ")
            end
            fly_player_to(player,
                doggiowars.island_approach(isl, pos.x, pos.z))
            return true, string.format(
                "%s island at (%d, %d, %d), r=%d, %d blocks away - it is "
                    .. "right in front of you. Give it a moment to generate.",
                isl.biome.name, isl.x, isl.y, isl.z, isl.radius,
                math.floor(dist or 0))
        end

        local isl, dist = doggiowars.nearest_island(pos.x, pos.z)
        local sp, yaw = doggiowars.spawn_pos_near(pos.x, pos.z)
        fly_player_to(player, sp, yaw)
        if isl then
            return true, string.format(
                "%s island, r=%d, was %d blocks away - it is in front of you. Give it a moment to generate.",
                isl.biome and isl.biome.name or "?", isl.radius, math.floor(dist or 0))
        end
        return true, "Moving to island."
    end,
})

minetest.register_chatcommand("goto", {
    description = "Fly above coordinates: /goto <x> <z> or /goto <x> <y> <z>",
    params = "<x> [<y>] <z>",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local nums = {}
        for n in (param or ""):gmatch("%-?%d+%.?%d*") do
            nums[#nums + 1] = tonumber(n)
        end
        if #nums < 2 or #nums > 3 then
            return false, "Usage: /goto <x> <z> or /goto <x> <y> <z>"
        end
        local x, z = nums[1], nums[#nums]
        local y = (#nums == 3) and nums[2] or nil
        if not y then
            -- bez zadané výšky: vyhlídka nad nejbližším ostrovem u cíle
            local isl = doggiowars.nearest_island(x, z)
            y = isl and doggiowars.island_vantage(isl).y or 320
        end
        fly_player_to(player, {x = x, y = y, z = z})
        return true, string.format("Flying to (%d, %d, %d).", x, y, z)
    end,
})

-- Registrace až po načtení všech modů — minetest_game má vlastní /home
-- (sethome) a přepsal by nás, kdybychom se registrovali dřív než on
minetest.register_on_mods_loaded(function()
    minetest.register_chatcommand("home", {
        description = "Fly to the home island at the world origin",
        privs = {interact = true},
        func = function(name)
            local player = minetest.get_player_by_name(name)
            if not player then return false, "Player not found" end
            local sp, yaw = doggiowars.spawn_pos()
            fly_player_to(player, sp, yaw)
            return true, "Flying to the home island (0,0) - it will be "
                .. "in front of you."
        end,
    })
end)

minetest.register_chatcommand("gp", {
    description = "Gamepad diagnostika: ukáže živě páčky a stisknutá tlačítka",
    privs = {interact = true},
    func = function(name)
        doggiowars.gp_debug[name] = not doggiowars.gp_debug[name]
        local p = minetest.get_player_by_name(name)
        if p and not doggiowars.gp_debug[name] then
            doggiowars.hud.set(p, "gpdebug", {text = ""})
        end
        if doggiowars.gp_debug[name] then
            return true, "Gamepad diagnostika ZAP — mačkej tlačítka/páčky a "
                .. "sleduj, co se rozsvítí uprostřed obrazovky."
        end
        return true, "Gamepad diagnostika VYP."
    end,
})

minetest.register_chatcommand("mode", {
    description = "Přepnutí ovládání: stíhačka <-> ponorka",
    params = "[fighter|sub]",
    privs = {interact = true},
    func = function(name, param)
        param = (param or ""):gsub("%s+", ""):lower()
        local new
        if param == "sub" or param == "submarine" then
            new = "sub"
        elseif param == "fighter" or param == "plane" then
            new = "fighter"
        else
            new = doggiowars.get_mode(name) == "sub" and "fighter" or "sub"
        end
        doggiowars.mode[name] = new
        local p = minetest.get_player_by_name(name)
        local f = p and doggiowars.get_player_fighter(p)
        if f then
            -- Čistý přechod za letu: zrušit trik i boost a srovnat vstupní
            -- hrany, ať držené klávesy nespustí hold-trik ve druhém režimu.
            -- Záměrně NE tricks.init — ten by smazal boost_meter/combo/skóre.
            f.trick = nil
            f.boost_time = 0
            f.input = {prev = {}, last_tap = {}, held_since = {}}
            f.sub_vel = nil
            if new == "fighter" then f.speed = 15 end
            p:set_fov(0)
        end
        if new == "sub" then
            return true, "PONORKA: levá páčka = tah/úkrok, pohled = kurz, "
                .. "X = nahoru, ○ = dolů. Triky a boost vypnuty."
        end
        return true, "STÍHAČKA: klasické letecké ovládání."
    end,
})
