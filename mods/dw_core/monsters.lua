-- dw_core/monsters.lua
-- Dekorativní monstra oživující ostrovy: hadí draci pěti živlů, písečný
-- červ, kamenný strážce, vznášivé medúzy a toulavá nebeská velryba.
--
-- Technika: „čínský drak" — hlava (cube s obličejovou texturou) + řetěz
-- zmenšujících se cube článků, které pružinově následují předchůdce.
-- Had se tím animuje zadarmo, bez koster (engine je pro .obj stejně neumí).
-- Živel nese particle efekt + glow, ne geometrie.
--
-- Vše je čistě dekorativní: pointable = false, žádný damage v obou směrech
-- (střely testují jméno fightera, viz weapons.lua). static_save = false —
-- lifecycle řeší engine (mimo aktivní bloky entita zmizí) + proximity
-- spawner dole, který osazenstvo při návratu hráče postaví znovu.

local SPAWN_DIST    = 200   -- 3D vzdálenost hráč–střed ostrova pro spawn
local CELL_SCAN     = 2     -- Čebyšev okolí buněk mřížky kolem hráče
local SCAN_INTERVAL = 3     -- s mezi průchody spawneru
local WHALE_CHANCE  = 40    -- 1/N šance na velrybu za tick spawneru
local SEG_PULL      = 6     -- pružina řetězu: rychlost ~ přetažení × k
local SEG_MAX_SPEED = 60

---------------------------------------------------------------------------
-- Letové primitivy — port z rabbit.lua BEZ mesh quirku (+pi): cube nemá
-- otočený model, obličej je na obou ±Z stěnách, takže yaw = dir_to_yaw.
---------------------------------------------------------------------------

local function wrap_angle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

-- Orientace z vektoru rychlosti; bank z rychlosti zatáčení (vyhlazený)
local function set_cube_rotation(self, vel, dtime, banking)
    local hlen = math.sqrt(vel.x * vel.x + vel.z * vel.z)
    if hlen < 0.05 then return end
    local yaw = minetest.dir_to_yaw({x = vel.x, y = 0, z = vel.z})
    local roll = 0
    if banking then
        local rate = wrap_angle(yaw - (self.last_yaw or yaw))
            / math.max(dtime, 0.01)
        local target = math.min(math.max(rate * 0.5, -1.0), 1.0)
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
    set_cube_rotation(self, vel, dtime, true)
end

---------------------------------------------------------------------------
-- Řetěz článků: každý článek drží rozestup za předchůdcem pružinovým
-- seekem. Medúzy mají svislý bias (chapadla visí dolů).
---------------------------------------------------------------------------

local function update_chain(self, def)
    local pred = self.object
    for i, o in ipairs(self.segs or {}) do
        local ent = o and o:get_luaentity()
        if ent then
            local ppos = pred:get_pos()
            local spos = o:get_pos()
            if ppos and spos then
                ent.orphan_t = 0
                local anchor = ppos
                if def.chain_hang then
                    anchor = vector.offset(ppos, 0, -def.spacing * 0.8, 0)
                end
                local to = vector.subtract(anchor, spos)
                local dist = vector.length(to)
                local vel
                if dist > def.spacing then
                    local k = math.min(
                        (dist - def.spacing) * SEG_PULL, SEG_MAX_SPEED)
                    vel = vector.multiply(to, k / dist)
                else
                    -- v klidu dojíždí — řetěz se přirozeně narovnává
                    vel = vector.multiply(o:get_velocity(), 0.5)
                end
                o:set_velocity(vel)
                local hlen = math.sqrt(vel.x * vel.x + vel.z * vel.z)
                if hlen > 0.5 then
                    o:set_rotation({
                        x = -math.atan2(vel.y, hlen),
                        y = minetest.dir_to_yaw({x = vel.x, y = 0, z = vel.z}),
                        z = 0,
                    })
                end
            end
            pred = o
        end
    end
end

---------------------------------------------------------------------------
-- Particle efekty živlů (throttlované z on_step hlavy)
---------------------------------------------------------------------------

local function fx(pos, opts)
    minetest.add_particlespawner({
        amount     = opts.amount or 4,
        time       = 0.2,
        minpos     = vector.offset(pos, -0.6, -0.4, -0.6),
        maxpos     = vector.offset(pos, 0.6, 0.6, 0.6),
        minvel     = opts.minvel or {x = -0.5, y = -0.5, z = -0.5},
        maxvel     = opts.maxvel or {x = 0.5, y = 0.5, z = 0.5},
        minexptime = 0.4,
        maxexptime = opts.maxexptime or 1.2,
        minsize    = opts.minsize or 1.0,
        maxsize    = opts.maxsize or 2.2,
        texture    = opts.texture,
        glow       = opts.glow or 0,
    })
end

local FX = {
    fire = function(pos) fx(pos, {
        texture = "doggiowars_particle_engine.png^[colorize:#ff6a28:200",
        minvel = {x = -0.4, y = 0.8, z = -0.4},
        maxvel = {x = 0.4, y = 2.2, z = 0.4},
        glow = 13, amount = 6,
    }) end,
    ice = function(pos) fx(pos, {
        texture = "doggiowars_particle_engine.png^[colorize:#dff4ff:220",
        minvel = {x = -0.6, y = -0.8, z = -0.6},
        maxvel = {x = 0.6, y = 0.2, z = 0.6},
        glow = 6, maxsize = 1.4,
    }) end,
    water = function(pos) fx(pos, {
        texture = "doggiowars_particle_drop.png^[colorize:#4fd8e8:160",
        minvel = {x = -0.3, y = -2.5, z = -0.3},
        maxvel = {x = 0.3, y = -0.8, z = 0.3},
        glow = 4,
    }) end,
    mud = function(pos) fx(pos, {
        texture = "doggiowars_particle_drop.png^[colorize:#7a5c30:220",
        minvel = {x = -0.2, y = -3, z = -0.2},
        maxvel = {x = 0.2, y = -1, z = 0.2},
        maxsize = 1.8,
    }) end,
    electric = function(pos) fx(pos, {
        texture = "doggiowars_particle_engine.png^[colorize:#ffe94a:255",
        minvel = {x = -3, y = -3, z = -3},
        maxvel = {x = 3, y = 3, z = 3},
        maxexptime = 0.3, minsize = 0.6, maxsize = 1.2,
        glow = 14, amount = 8,
    }) end,
    dust = function(pos) fx(pos, {
        texture = "doggiowars_particle_engine.png^[colorize:#d8c07a:180",
        minvel = {x = -1.5, y = 0.5, z = -1.5},
        maxvel = {x = 1.5, y = 2.5, z = 1.5},
        maxexptime = 0.8, amount = 10, maxsize = 2.8,
    }) end,
    spore = function(pos) fx(pos, {
        texture = "doggiowars_spore.png",
        minvel = {x = -0.3, y = -0.6, z = -0.3},
        maxvel = {x = 0.3, y = 0.1, z = 0.3},
        glow = 10, amount = 2, maxsize = 1.2,
    }) end,
    blow = function(pos) fx(vector.offset(pos, 0, 1.5, 0), {
        texture = "doggiowars_particle_engine.png^[colorize:#cfe8f8:200",
        minvel = {x = -0.5, y = 4, z = -0.5},
        maxvel = {x = 0.5, y = 8, z = 0.5},
        amount = 20, maxexptime = 1.0, maxsize = 2.5, glow = 4,
    }) end,
}

---------------------------------------------------------------------------
-- Chování hlav
---------------------------------------------------------------------------

-- Kroužení kolem ostrova (vzor: zaječí wait-kroužení) + bob; draci si
-- občas střihnou looping — svislý kruh po tečně dráhy.
local function orbit_island(self, def, dtime)
    local isl = self.island
    -- strop 110 m: spawn (200) + orbit (110) musí zůstat pod aktivním
    -- rozsahem bloků (320 m), jinak engine maže draky na odvrácené straně
    local orbit_r = math.min(math.max(isl.radius * 0.8, 30), 110)
    local alt = isl.y + isl.radius * (def.alt_frac or 0.35) + (def.alt or 10)

    if self.stunt then
        -- looping: rychlost rotuje ve svislé rovině dané tečnou
        self.stunt.a = self.stunt.a + dtime * (2 * math.pi / 2.6)
        local a = self.stunt.a
        local d = self.stunt.dir
        local vel = {
            x = d.x * math.cos(a) * def.speed,
            y = math.sin(a) * def.speed,
            z = d.z * math.cos(a) * def.speed,
        }
        self.object:set_velocity(vel)
        set_cube_rotation(self, vel, dtime, false)
        if a >= 2 * math.pi then
            self.stunt = nil
        end
        return
    end

    self.phase = (self.phase or 0) + dtime * def.speed / orbit_r
    local target = {
        x = isl.x + math.cos(self.phase) * orbit_r,
        y = alt + math.sin(self.phase * 2) * 6,
        z = isl.z + math.sin(self.phase) * orbit_r,
    }
    fly_toward(self, target, def.speed, dtime)

    if def.stunts then
        self.stunt_cd = (self.stunt_cd or math.random(8, 20)) - dtime
        if self.stunt_cd <= 0 then
            self.stunt_cd = math.random(12, 30)
            local vel = self.object:get_velocity()
            local hlen = math.sqrt(vel.x * vel.x + vel.z * vel.z)
            if hlen > 1 then
                self.stunt = {a = 0, dir = {x = vel.x / hlen, z = vel.z / hlen}}
            end
        end
    end
end

-- Písečný červ: krouží po povrchu ostrova a „delfíní" oblouky ho nořují
-- pod povrch a zpět. Povrch sonduje get_node sloupcem (throttle 1 s).
local function worm_arcs(self, def, dtime)
    local isl = self.island
    local orbit_r = math.max(isl.radius * 0.45, 18)
    self.phase = (self.phase or 0) + dtime * def.speed / orbit_r
    local tx = isl.x + math.cos(self.phase) * orbit_r
    local tz = isl.z + math.sin(self.phase) * orbit_r

    self.surf_t = (self.surf_t or 1)
    self.surf_t = self.surf_t + dtime
    if self.surf_t >= 1 then
        self.surf_t = 0
        local y = isl.y + math.floor(isl.radius * 0.6)
        local surf = nil
        for i = 0, 80 do
            local node = minetest.get_node({x = tx, y = y - i, z = tz})
            if node.name ~= "air" and node.name ~= "ignore" then
                surf = y - i + 1
                break
            end
        end
        self.surf_y = surf or self.surf_y or isl.y
    end

    local dive = math.sin(self.phase * 5) * 7
    local target = {x = tx, y = (self.surf_y or isl.y) + dive, z = tz}
    fly_toward(self, target, def.speed, dtime)

    -- prach při průchodu povrchem
    local above = dive > 0
    if self.was_above ~= nil and above ~= self.was_above then
        FX.dust({x = tx, y = self.surf_y or isl.y, z = tz})
    end
    self.was_above = above
end

-- Medúza: líné bloudění mezi náhodnými waypointy nad ostrovem
local function drift_swarm(self, def, dtime)
    local isl = self.island
    local pos = self.object:get_pos()
    if not self.wp or (pos and vector.distance(pos, self.wp) < 4)
            or (self.wp_t or 0) > 20 then
        local ang = math.random() * 2 * math.pi
        local r = math.random() * isl.radius * 0.6
        self.wp = {
            x = isl.x + math.cos(ang) * r,
            y = isl.y + isl.radius * (0.3 + math.random() * 0.35),
            z = isl.z + math.sin(ang) * r,
        }
        self.wp_t = 0
    end
    self.wp_t = (self.wp_t or 0) + dtime
    self.bob = (self.bob or 0) + dtime * 2
    local target = vector.offset(self.wp, 0, math.sin(self.bob) * 1.5, 0)
    fly_toward(self, target, def.speed, dtime)
end

-- Kamenný strážce: visí nad vrcholem, mikro-bob, pomalu se natáčí za
-- nejbližším hráčem do 100 m — jen sleduje, nic víc (zatím).
local function face_player_hover(self, def, dtime)
    local isl = self.island
    local anchor = {
        x = isl.x,
        y = isl.y + isl.radius * 0.55 + 8,
        z = isl.z,
    }
    local pos = self.object:get_pos()
    if not pos then return end
    self.bob = (self.bob or math.random() * 6) + dtime
    local target = vector.offset(anchor, 0, math.sin(self.bob * 0.8) * 1.2, 0)
    local vel = vector.multiply(vector.subtract(target, pos), 0.6)
    self.object:set_velocity(vel)

    -- otáčení: za hráčem, jinak líné bloumání
    local want = (self.idle_yaw or 0)
    local nearest, ndist = nil, 100
    for _, player in ipairs(minetest.get_connected_players()) do
        local f = doggiowars.get_player_fighter(player)
        local ppos = f and f.object:get_pos()
        if ppos then
            local d = vector.distance(pos, ppos)
            if d < ndist then
                nearest, ndist = ppos, d
            end
        end
    end
    if nearest then
        want = minetest.dir_to_yaw(vector.direction(pos, nearest))
    else
        self.idle_yaw = (self.idle_yaw or 0) + dtime * 0.15
        want = self.idle_yaw
    end
    local rot = self.object:get_rotation() or {x = 0, y = 0, z = 0}
    local step = 0.8 * dtime
    local dy = wrap_angle(want - rot.y)
    rot.y = rot.y + math.max(-step, math.min(step, dy))
    rot.x, rot.z = 0, 0
    self.object:set_rotation(rot)
end

-- Velryba: pluje přímo mezi vzdálenými waypointy, vznešený bob, občas
-- gejzír z dýchacího otvoru
local function roam(self, def, dtime)
    local pos = self.object:get_pos()
    if not pos then return end
    if not self.wp or vector.distance(pos, self.wp) < 25 then
        local ang = math.random() * 2 * math.pi
        local dist = 300 + math.random() * 300
        self.wp = {
            x = pos.x + math.cos(ang) * dist,
            y = math.max(150, math.min(600,
                pos.y + (math.random() - 0.5) * 120)),
            z = pos.z + math.sin(ang) * dist,
        }
    end
    self.bob = (self.bob or 0) + dtime * 0.5
    local target = vector.offset(self.wp, 0, math.sin(self.bob) * 4, 0)
    fly_toward(self, target, def.speed, dtime)

    self.blow_t = (self.blow_t or math.random(8, 20)) - dtime
    if self.blow_t <= 0 then
        self.blow_t = math.random(15, 25)
        FX.blow(pos)
    end
end

---------------------------------------------------------------------------
-- Továrna druhů: registruje hlavu + článek, řeší spawn/úklid řetězu
---------------------------------------------------------------------------

local function tinted(tex, tint)
    if not tint then return tex end
    return tex .. "^[multiply:" .. tint
end

local function register_species(name, def)
    local seg_name = "doggiowars:" .. name .. "_seg"
    local body = tinted(def.body_tex or "doggiowars_monster_body.png", def.tint)
    local face = tinted(def.face_tex or "doggiowars_monster_head.png", def.tint)

    if def.seg_count > 0 then
        minetest.register_entity(":" .. seg_name, {
            initial_properties = {
                visual            = "cube",
                textures          = {body, body, body, body, body, body},
                visual_size       = {x = 1, y = 1, z = 1},
                physical          = false,
                collide_with_objects = false,
                collisionbox      = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
                pointable         = false,
                static_save       = false,
                glow              = def.glow or 0,
            },
            on_activate = function(self)
                self.object:set_armor_groups({immortal = 1})
                self.object:set_acceleration(vector.zero())
            end,
            -- články řídí hlava; osiřelý článek (hlava zmizela dřív při
            -- unload) se po 2 s uklidí sám
            on_step = function(self, dtime)
                self.orphan_t = (self.orphan_t or 0) + dtime
                if self.orphan_t > 2 then
                    self.object:remove()
                end
            end,
        })
    end

    minetest.register_entity(":doggiowars:" .. name, {
        initial_properties = {
            visual            = "cube",
            -- obličej na obou ±Z stěnách — orientační konvence pak nehraje roli
            textures          = {body, body, body, body, face, face},
            visual_size       = {
                x = def.head_size or 1,
                y = def.head_size or 1,
                z = def.head_size or 1,
            },
            physical          = false,
            collide_with_objects = false,
            collisionbox      = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
            pointable         = false,
            static_save       = false,
            glow              = def.glow or 0,
        },

        island = nil,   -- injektuje spawner (jako race.lua injektuje route)

        on_activate = function(self)
            self.object:set_armor_groups({immortal = 1})
            self.object:set_acceleration(vector.zero())
            self.segs = {}
            self.phase = math.random() * 2 * math.pi
        end,

        on_deactivate = function(self)
            for _, o in ipairs(self.segs or {}) do
                if o and o:get_luaentity() then
                    o:remove()
                end
            end
        end,

        on_step = function(self, dtime)
            local pos = self.object:get_pos()
            if not pos then return end

            -- bez ostrova (a bez roam) nemá smysl existovat
            if not self.island and not def.roaming then
                self.lost_t = (self.lost_t or 0) + dtime
                if self.lost_t > 1 then
                    self.object:remove()
                end
                return
            end

            -- články až v prvním stepu — spawner injektuje island až po
            -- add_entity, on_activate běží dřív
            if not self.segs_spawned and def.seg_count > 0 then
                self.segs_spawned = true
                for i = 1, def.seg_count do
                    local o = minetest.add_entity(pos, seg_name)
                    if o then
                        local sc
                        if def.seg_sizes then
                            sc = def.seg_sizes[i] or def.seg_sizes[#def.seg_sizes]
                        else
                            sc = math.max(0.35,
                                (def.head_size or 1) * (0.85 - 0.07 * i))
                        end
                        o:set_properties({
                            visual_size = {x = sc, y = sc, z = sc},
                        })
                        self.segs[i] = o
                    end
                end
                -- velrybí ocasní ploutev: poslední článek zploštit a rozšířit
                if def.fluke and self.segs[def.seg_count] then
                    self.segs[def.seg_count]:set_properties({
                        visual_size = {x = 2.4, y = 0.5, z = 1.2},
                    })
                end
            end

            def.behavior(self, def, dtime)
            if def.seg_count > 0 then
                update_chain(self, def)
            end

            if def.fx then
                self.fx_t = (self.fx_t or 0) + dtime
                if self.fx_t >= (def.fx_interval or 0.25) then
                    self.fx_t = 0
                    FX[def.fx](self.object:get_pos() or pos)
                end
            end
        end,
    })
end

---------------------------------------------------------------------------
-- Druhy
---------------------------------------------------------------------------

local function dragon(tint, opts)
    return {
        tint = tint, glow = opts.glow or 6,
        seg_count = 7, spacing = 1.7, head_size = 1.5,
        speed = opts.speed or 12,
        alt = opts.alt, alt_frac = opts.alt_frac,
        behavior = orbit_island, stunts = true,
        fx = opts.fx, fx_interval = opts.fx_interval,
    }
end

local SPECIES = {
    dragon_fire     = dragon("#e0512e", {glow = 8, fx = "fire"}),
    dragon_ice      = dragon("#bfe6ff", {glow = 6, fx = "ice"}),
    dragon_water    = dragon("#35c8c0", {glow = 4, fx = "water",
                             alt_frac = 0.2, alt = 6}),
    dragon_mud      = dragon("#8a6a3a", {glow = 0, fx = "mud", speed = 9}),
    dragon_electric = dragon("#ffe94a", {glow = 11, fx = "electric",
                             speed = 16, fx_interval = 0.15}),

    worm = {
        tint = "#d8c07a", glow = 0,
        seg_count = 8, spacing = 1.3, head_size = 1.2,
        speed = 11,
        behavior = worm_arcs,
    },

    guardian = {
        body_tex = "doggiowars_basalt.png",
        face_tex = "doggiowars_guardian.png",
        glow = 7,
        seg_count = 0, head_size = 3.2,
        behavior = face_player_hover,
    },

    jelly = {
        body_tex = "doggiowars_jelly.png",
        face_tex = "doggiowars_jelly.png",
        glow = 4,
        seg_count = 4, spacing = 0.8, head_size = 1.2,
        seg_sizes = {0.4, 0.35, 0.3, 0.25},
        chain_hang = true,
        speed = 2.5,
        behavior = drift_swarm,
    },

    jelly_glow = {
        body_tex = "doggiowars_jelly.png",
        face_tex = "doggiowars_jelly.png",
        tint = "#d8a8ff", glow = 12,
        seg_count = 4, spacing = 0.8, head_size = 1.2,
        seg_sizes = {0.4, 0.35, 0.3, 0.25},
        chain_hang = true,
        speed = 2.2,
        behavior = drift_swarm,
        fx = "spore", fx_interval = 0.6,
    },

    whale = {
        tint = "#8fa6ba", glow = 0,
        seg_count = 4, spacing = 3.2, head_size = 3.0,
        seg_sizes = {2.6, 2.0, 1.4, 0.9},
        fluke = true,
        speed = 6,
        behavior = roam, roaming = true,
    },
}

for name, def in pairs(SPECIES) do
    register_species(name, def)
end

---------------------------------------------------------------------------
-- Spawner: osazenstvo biomu na ostrovech kolem hráčů + toulavé velryby
---------------------------------------------------------------------------

local BIOME_CREW = {
    volcanic = {"dragon_fire"},
    ashen    = {"dragon_fire"},
    glacial  = {"dragon_ice"},
    atoll    = {"dragon_water"},
    swamp    = {"dragon_mud"},
    crystal  = {"dragon_electric"},
    desert   = {"worm"},
    savanna  = {"worm"},
    barren   = {"guardian"},
    verdant  = {"jelly", "jelly", "jelly"},
    jungle   = {"jelly", "jelly"},
    mycelial = {"jelly_glow", "jelly_glow", "jelly_glow"},
}

local spawned = {}   -- cellkey -> {objs = {ObjectRef...}}
local whales = {}    -- player_name -> ObjectRef

-- mapa sveta (map.lua) z nich kresli zive tecky
doggiowars.monster_groups = spawned
doggiowars.monster_whales = whales

local function spawn_crew(isl, key)
    local crew = BIOME_CREW[isl.biome.name]
    if not crew then return end
    local objs = {}
    for i, sp in ipairs(crew) do
        local ang = math.random() * 2 * math.pi
        local pos = {
            x = isl.x + math.cos(ang) * isl.radius * 0.6,
            y = isl.y + isl.radius * 0.5 + i * 4,
            z = isl.z + math.sin(ang) * isl.radius * 0.6,
        }
        local obj = minetest.add_entity(pos, "doggiowars:" .. sp)
        if obj then
            local ent = obj:get_luaentity()
            ent.island = isl
            objs[#objs + 1] = obj
        end
    end
    spawned[key] = {objs = objs}
    minetest.log("action", string.format(
        "[doggiowars] monsters: %s x%d @ island %s (%s)",
        crew[1], #objs, key, isl.biome.name))
end

-- seed je per svět konstantní; get_world_seed() skládá u64 bez ztráty
-- (viz mapgen.lua) — stačí si ho líně zapamatovat
local world_seed
local function seed()
    world_seed = world_seed or doggiowars.get_world_seed()
    return world_seed
end

local scan_t = 0
minetest.register_globalstep(function(dtime)
    scan_t = scan_t + dtime
    if scan_t < SCAN_INTERVAL then return end
    scan_t = 0

    -- pročistit skupiny, jejichž entity engine odaktivoval (smazal)
    for key, grp in pairs(spawned) do
        local alive = false
        for _, o in ipairs(grp.objs) do
            if o:get_luaentity() then
                alive = true
                break
            end
        end
        if not alive then
            spawned[key] = nil
        end
    end

    local grid = doggiowars.ISLAND_GRID
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local f = doggiowars.get_player_fighter(player)
        local ppos = f and f.object:get_pos() or player:get_pos()
        if ppos then
            local pcx = math.floor(ppos.x / grid)
            local pcz = math.floor(ppos.z / grid)
            for dcx = -CELL_SCAN, CELL_SCAN do
                for dcz = -CELL_SCAN, CELL_SCAN do
                    local cx, cz = pcx + dcx, pcz + dcz
                    local key = cx .. ":" .. cz
                    if not spawned[key] then
                        local isl = doggiowars.island_for_cell(cx, cz, seed())
                        if isl and vector.distance(ppos, isl) < SPAWN_DIST then
                            spawn_crew(isl, key)
                        end
                    end
                end
            end

            -- toulavá velryba: max jedna na hráče, vzácně
            local w = whales[name]
            if w and not w:get_luaentity() then
                whales[name] = nil
                w = nil
            end
            if not w and math.random(WHALE_CHANCE) == 1 then
                local ang = math.random() * 2 * math.pi
                local pos = {
                    x = ppos.x + math.cos(ang) * 250,
                    y = math.max(150, math.min(600, ppos.y + 40)),
                    z = ppos.z + math.sin(ang) * 250,
                }
                local obj = minetest.add_entity(pos, "doggiowars:whale")
                if obj then
                    whales[name] = obj
                    minetest.log("action",
                        "[doggiowars] monsters: whale near " .. name)
                end
            end
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    whales[player:get_player_name()] = nil
end)

minetest.log("action", "[doggiowars] monsters loaded: "
    .. "5 dragons, worm, guardian, jelly, whale")
