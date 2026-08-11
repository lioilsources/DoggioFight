-- doggiowars/weapons.lua
-- Projectiles, voxel explosions, and damage system

doggiowars = doggiowars or {}

local BULLET_SPEED        = 120   -- m/s (3× max plane speed)
local BULLET_TTL          = 2.5   -- seconds until auto-remove
local BULLET_DAMAGE       = 25    -- damage per hit (4 shots to kill)
local EXPLODE_RADIUS      = 3     -- blocks destroyed on node hit
local EXPLODE_RADIUS_HIT  = 1     -- blocks destroyed on entity hit
local ENTITY_HIT_RADIUS   = 1.5   -- proximity check radius for entity hits
local DEBRIS_MAX_ACTIVE   = 140   -- perf guard: cap of live debris chunks

---------------------------------------------------------------------------
-- Falling debris — odlomený kus ostrova s gravitací
---------------------------------------------------------------------------

local debris_active = 0

-- Textura první strany nodu (aby sutina vypadala jako zasažený materiál)
local function node_tile(name)
    local def = minetest.registered_nodes[name]
    local t = def and def.tiles and def.tiles[1]
    if type(t) == "table" then t = t.name end
    if type(t) ~= "string" then return "default_stone.png" end
    return t
end

minetest.register_entity("doggiowars:debris", {
    initial_properties = {
        visual            = "cube",
        visual_size       = {x = 0.8, y = 0.8, z = 0.8},
        textures          = {"default_stone.png", "default_stone.png",
                             "default_stone.png", "default_stone.png",
                             "default_stone.png", "default_stone.png"},
        physical          = true,
        collide_with_objects = false,
        collisionbox      = {-0.35, -0.35, -0.35, 0.35, 0.35, 0.35},
        static_save       = false,
        pointable         = false,
    },

    _ttl  = 0,
    _spin = nil,

    on_activate = function(self, staticdata)
        debris_active = debris_active + 1
        self._ttl = 2.5 + math.random() * 1.5
        self.object:set_acceleration({x = 0, y = -10, z = 0})
        self._spin = {
            x = (math.random() - 0.5) * 9,
            y = (math.random() - 0.5) * 9,
            z = (math.random() - 0.5) * 9,
        }
        if staticdata and staticdata ~= "" then
            self.object:set_properties({
                textures = {staticdata, staticdata, staticdata,
                            staticdata, staticdata, staticdata},
            })
        end
    end,

    on_step = function(self, dtime, moveresult)
        self._ttl = self._ttl - dtime
        local landed = moveresult and moveresult.collides
        if self._ttl <= 0 or landed then
            local pos = self.object:get_pos()
            if pos then
                minetest.add_particle({
                    pos            = pos,
                    velocity       = {x = 0, y = 0, z = 0},
                    acceleration   = {x = 0, y = -6, z = 0},
                    expirationtime = 0.4,
                    size           = 2.5,
                    texture        = "doggiowars_particle_engine.png",
                    glow           = 3,
                })
            end
            debris_active = math.max(0, debris_active - 1)
            self.object:remove()
            return
        end
        local rot = self.object:get_rotation()
        self.object:set_rotation({
            x = rot.x + self._spin.x * dtime,
            y = rot.y + self._spin.y * dtime,
            z = rot.z + self._spin.z * dtime,
        })
    end,
})

---------------------------------------------------------------------------
-- Voxel explosion — vyhloubí kráter, odlomí sutinu, částice ohně
---------------------------------------------------------------------------

function doggiowars.explode_voxels(pos, radius)
    local ir = math.ceil(radius)
    local r2 = radius * radius
    local removed = {}

    for dx = -ir, ir do
        for dy = -ir, ir do
            for dz = -ir, ir do
                if dx*dx + dy*dy + dz*dz <= r2 then
                    local npos = {x = pos.x + dx, y = pos.y + dy, z = pos.z + dz}
                    local node = minetest.get_node(npos)
                    if node.name ~= "air" and node.name ~= "ignore" then
                        minetest.remove_node(npos)
                        removed[#removed + 1] = {p = npos, n = node.name}
                    end
                end
            end
        end
    end

    -- Odlomit část zasažených bloků jako padající sutinu (kus odpadne)
    if #removed > 0 and debris_active < DEBRIS_MAX_ACTIVE then
        local want = math.min(#removed, 3 + math.floor(radius * 2))
        for _ = 1, want do
            if debris_active >= DEBRIS_MAX_ACTIVE then break end
            local pick = removed[math.random(1, #removed)]
            local dx = pick.p.x - pos.x
            local dy = pick.p.y - pos.y
            local dz = pick.p.z - pos.z
            local len = math.sqrt(dx*dx + dy*dy + dz*dz)
            if len < 0.1 then dx, dy, dz, len = 0, 1, 0, 1 end
            local sp = 3 + math.random() * 5
            local obj = minetest.add_entity(pick.p, "doggiowars:debris", node_tile(pick.n))
            if obj then
                obj:set_velocity({
                    x = dx / len * sp + (math.random() - 0.5) * 3,
                    y = math.abs(dy / len) * sp * 0.5 + 2 + math.random() * 3,
                    z = dz / len * sp + (math.random() - 0.5) * 3,
                })
            end
        end
    end

    -- Nechat sesypat sypké okraje kráteru (písek/sníh/popel)
    minetest.check_for_falling({x = pos.x, y = pos.y + ir + 1, z = pos.z})

    -- Oheň + sutinové částice
    minetest.add_particlespawner({
        amount     = 60,
        time       = 0.5,
        minpos     = {x = pos.x - 0.5, y = pos.y - 0.5, z = pos.z - 0.5},
        maxpos     = {x = pos.x + 0.5, y = pos.y + 0.5, z = pos.z + 0.5},
        minvel     = {x = -15, y = -10, z = -15},
        maxvel     = {x =  15, y =  22, z =  15},
        minacc     = {x = 0,  y = -8,  z = 0},
        maxacc     = {x = 0,  y = -14, z = 0},
        minexptime = 0.3,
        maxexptime = 1.5,
        minsize    = 1.5,
        maxsize    = 5.0,
        texture    = "doggiowars_particle_engine.png",
        glow       = 14,
    })
end

---------------------------------------------------------------------------
-- Bullet entity
---------------------------------------------------------------------------

minetest.register_entity("doggiowars:bullet", {
    initial_properties = {
        visual            = "sprite",
        textures          = {"doggiowars_particle_engine.png"},
        visual_size       = {x = 0.3, y = 0.3},
        physical          = true,
        collide_with_objects = false,
        collisionbox      = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
        glow              = 14,
        static_save       = false,
        pointable         = false,
    },

    _ttl          = BULLET_TTL,
    _shooter_name = nil,   -- pilot's player name (string, avoids stale refs)

    on_activate = function(self, staticdata)
        self.object:set_armor_groups({immortal = 1})
    end,

    on_step = function(self, dtime, moveresult)
        self._ttl = (self._ttl or BULLET_TTL) - dtime
        if self._ttl <= 0 then
            self.object:remove()
            return
        end

        local pos = self.object:get_pos()
        if not pos then return end

        -- Node collision via moveresult (physical = true gives this for free)
        if moveresult and moveresult.collides then
            for _, col in ipairs(moveresult.collisions or {}) do
                if col.type == "node" then
                    doggiowars.explode_voxels(pos, EXPLODE_RADIUS)
                    self.object:remove()
                    return
                end
            end
        end

        -- Entity collision via proximity (fighter has collide_with_objects=false)
        local objects = minetest.get_objects_inside_radius(pos, ENTITY_HIT_RADIUS)
        for _, obj in ipairs(objects) do
            if obj ~= self.object then
                local ent = obj:get_luaentity()
                if ent and ent.name == "doggiowars:fighter"
                        and ent.hp and ent.hp > 0 and not ent.is_dead then
                    -- Don't hit the shooter's own plane
                    local is_own = self._shooter_name ~= nil
                        and ent.pilot_name == self._shooter_name
                    if not is_own then
                        ent:damage_fighter(BULLET_DAMAGE)
                        doggiowars.explode_voxels(pos, EXPLODE_RADIUS_HIT)
                        self.object:remove()
                        return
                    end
                end
            end
        end

        -- Tracer trail
        minetest.add_particle({
            pos            = pos,
            velocity       = {x = 0, y = 0, z = 0},
            acceleration   = {x = 0, y = 0, z = 0},
            expirationtime = 0.1,
            size           = 0.8,
            texture        = "doggiowars_particle_engine.png",
            glow           = 12,
        })
    end,
})

---------------------------------------------------------------------------
-- Shoot function — called from vehicle.lua on_step
---------------------------------------------------------------------------

function doggiowars.shoot_bullet(fighter_self)
    local pos = fighter_self.object:get_pos()
    if not pos then return end

    local rot = fighter_self.object:get_rotation()
    local dir = minetest.yaw_to_dir(rot.y + math.pi)
    local pitch_angle = -(rot.x or 0)   -- rot.x is -pitch
    dir.y = math.sin(pitch_angle)
    -- Re-normalize horizontal component
    local hlen = math.sqrt(dir.x * dir.x + dir.z * dir.z)
    local cos_p = math.cos(pitch_angle)
    if hlen > 0 then
        dir.x = dir.x / hlen * cos_p
        dir.z = dir.z / hlen * cos_p
    end

    -- Muzzle: 6 blocks in front of center — first-person kamera pilota sedí
    -- ~4 jednotky před středem, muzzle musí být až před ní
    local muzzle = {
        x = pos.x + dir.x * 6,
        y = pos.y + dir.y * 6,
        z = pos.z + dir.z * 6,
    }

    local bullet = minetest.add_entity(muzzle, "doggiowars:bullet")
    if not bullet then return end

    -- Add plane velocity so bullet doesn't arc backward when diving
    local plane_vel = fighter_self.object:get_velocity() or {x = 0, y = 0, z = 0}
    bullet:set_velocity({
        x = dir.x * BULLET_SPEED + plane_vel.x,
        y = dir.y * BULLET_SPEED + plane_vel.y,
        z = dir.z * BULLET_SPEED + plane_vel.z,
    })

    local ent = bullet:get_luaentity()
    if ent then
        ent._shooter_name = fighter_self.pilot_name
    end

    -- Muzzle flash (malý — je přímo před first-person kamerou)
    minetest.add_particle({
        pos            = muzzle,
        velocity       = {x = 0, y = 0, z = 0},
        acceleration   = {x = 0, y = 0, z = 0},
        expirationtime = 0.08,
        size           = 2.0,
        texture        = "doggiowars_particle_engine.png",
        glow           = 15,
    })
end
