-- doggiowars/race.lua
-- Chrtí závod: generátor trati z deterministických ostrovů, Catmull-Rom
-- splajna, kutání tunelů, checkpointy, HUD a lifecycle. Králíka (AI loď,
-- která trať letí) definuje rabbit.lua.

doggiowars.race = {}
local race = doggiowars.race
local hud = doggiowars.hud

race.active = {}  -- [player_name] = race state

local CHECKPOINT_RADIUS = 15
local FINISH_RADIUS     = 20

---------------------------------------------------------------------------
-- Catmull-Rom splajna nad route.points
-- Segment `seg` vede z points[seg] do points[seg+1], t v [0,1]
---------------------------------------------------------------------------

local function catmull(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    local function comp(a, b, c, d)
        return 0.5 * (2 * b + (c - a) * t
            + (2 * a - 5 * b + 4 * c - d) * t2
            + (3 * b - a - 3 * c + d) * t3)
    end
    return {
        x = comp(p0.x, p1.x, p2.x, p3.x),
        y = comp(p0.y, p1.y, p2.y, p3.y),
        z = comp(p0.z, p1.z, p2.z, p3.z),
    }
end

local function clampi(i, n)
    return math.max(1, math.min(i, n))
end

function race.eval(route, seg, t)
    local pts = route.points
    local n = #pts
    seg = clampi(seg, n - 1)
    return catmull(
        pts[clampi(seg - 1, n)],
        pts[seg],
        pts[clampi(seg + 1, n)],
        pts[clampi(seg + 2, n)],
        t)
end

function race.tangent(route, seg, t)
    local e = 0.001
    local a = race.eval(route, seg, t)
    local b = race.eval(route, seg, t + e)
    return vector.multiply(vector.subtract(b, a), 1 / e)
end

-- Posun po splajně o ds metrů; vrací seg, t, finished
function race.advance(route, seg, t, ds)
    local n = #route.points
    local guard = 0
    while ds > 0 and guard < 32 do
        guard = guard + 1
        local tl = math.max(vector.length(race.tangent(route, seg, t)), 0.05)
        local remain = (1 - t) * tl
        if ds < remain then
            t = t + ds / tl
            ds = 0
        else
            ds = ds - remain
            seg = seg + 1
            t = 0
            if seg > n - 1 then
                return n - 1, 1, true
            end
        end
    end
    return seg, t, false
end

---------------------------------------------------------------------------
-- Generátor trati — řetěz ostrovů ve směru letu, střídání typů segmentů
---------------------------------------------------------------------------

local SEG_TYPES = {"slalom", "showcase", "orbit", "slalom", "tunnel", "climb_dive"}

local HINTS = {
    slalom     = "SLALOM! Drž se zajíce",
    showcase   = "ZAJÍC: BARREL ROLL! (double-tap LMB/RMB)",
    orbit      = "OSTRÁ ZATÁČKA! S+A/D = airbrake drift",
    tunnel     = "TUNEL! Zpomal (S) a leť přesně",
    climb_dive = "STOUPÁNÍ + STŘEMHLAV! Shift dolů = rychlost navíc",
}

function race.build_route(start_pos, heading, seed)
    local points = {}
    local meta   = {}
    local carves = {}

    local function add_point(pos, m)
        table.insert(points, {
            x = pos.x,
            y = math.min(math.max(pos.y, 30), 700),
            z = pos.z,
        })
        meta[#points] = m or {}
        return #points
    end

    -- směr letu v rovině XZ
    local ux, uz = heading.x, heading.z
    local ulen = math.sqrt(ux * ux + uz * uz)
    if ulen < 0.1 then ux, uz = 1, 0 else ux, uz = ux / ulen, uz / ulen end

    add_point(start_pos)
    add_point({
        x = start_pos.x + ux * 80,
        y = start_pos.y,
        z = start_pos.z + uz * 80,
    })

    local G = doggiowars.ISLAND_GRID
    local fx = start_pos.x / G
    local fz = start_pos.z / G
    local cur_alt = start_pos.y
    local side = 1
    local visited = {}
    local n_islands = 10 + math.random(0, 4)

    for k = 1, n_islands do
        fx = fx + ux * 1.2
        fz = fz + uz * 1.2

        -- z okolních buněk vyber ostrov s nejmenším výškovým skokem
        local base_cx = math.floor(fx + 0.5)
        local base_cz = math.floor(fz + 0.5)
        local best, best_score, best_key
        for dx = -1, 1 do
            for dz = -1, 1 do
                local cx, cz = base_cx + dx, base_cz + dz
                local key = cx .. ":" .. cz
                if not visited[key] then
                    local isl = doggiowars.island_for_cell(cx, cz, seed)
                    if isl then
                        local score = math.abs(isl.y - cur_alt)
                            + math.random() * 30
                        if not best or score < best_score then
                            best, best_score, best_key = isl, score, key
                        end
                    end
                end
            end
        end

        if best then
            visited[best_key] = true
            local isl = best
            local prev = points[#points]

            -- směr příletu k ostrovu
            local dvx, dvz = isl.x - prev.x, isl.z - prev.z
            local dlen = math.max(math.sqrt(dvx * dvx + dvz * dvz), 0.1)
            dvx, dvz = dvx / dlen, dvz / dlen
            local px, pz = -dvz, dvx  -- kolmice

            local seg_type = SEG_TYPES[(k - 1) % #SEG_TYPES + 1]

            -- tunel jen skrz dost velké plné ostrovy (disc je moc placatý)
            if seg_type == "tunnel"
                    and (isl.radius < 45 or isl.biome.shape == "disc") then
                seg_type = "slalom"
            end

            local hint = HINTS[seg_type]

            if seg_type == "slalom" then
                side = -side
                local off = isl.radius + 15
                add_point({
                    x = isl.x + px * off * side,
                    y = isl.y + 12,
                    z = isl.z + pz * off * side,
                }, {checkpoint = true, speed = 28, hint = hint})

            elseif seg_type == "showcase" then
                side = -side
                local off = isl.radius + 25
                add_point({
                    x = isl.x + px * off * side,
                    y = isl.y + 15,
                    z = isl.z + pz * off * side,
                }, {checkpoint = true, speed = 26,
                    trick = "barrel_roll", hint = hint})

            elseif seg_type == "orbit" then
                local a0 = math.atan2(prev.z - isl.z, prev.x - isl.x)
                local rr = isl.radius + 20
                local odir = side
                side = -side
                for i = 1, 4 do
                    local a = a0 + odir * i * (1.5 * math.pi / 4)
                    add_point({
                        x = isl.x + math.cos(a) * rr,
                        y = isl.y + 15,
                        z = isl.z + math.sin(a) * rr,
                    }, i == 1 and {checkpoint = true, speed = 24, hint = hint}
                       or {speed = 24})
                end

            elseif seg_type == "tunnel" then
                local off = isl.radius + 10
                local i0 = add_point({
                    x = isl.x - dvx * off,
                    y = isl.y + 4,
                    z = isl.z - dvz * off,
                }, {checkpoint = true, speed = 18, hint = hint})
                add_point({x = isl.x, y = isl.y + 4, z = isl.z}, {speed = 18})
                local i1 = add_point({
                    x = isl.x + dvx * off,
                    y = isl.y + 4,
                    z = isl.z + dvz * off,
                }, {speed = 22})
                table.insert(carves, {i0 = i0, i1 = i1, done = false})

            elseif seg_type == "climb_dive" then
                add_point({
                    x = isl.x,
                    y = isl.y + isl.radius * 0.6 + 50,
                    z = isl.z,
                }, {checkpoint = true, speed = 24, hint = hint})
                add_point({
                    x = isl.x + dvx * (isl.radius + 60),
                    y = math.max(isl.y - 60, 40),
                    z = isl.z + dvz * (isl.radius + 60),
                }, {speed = 35})
            end

            cur_alt = points[#points].y
        end
    end

    -- cílový bod kus za posledním ostrovem
    local lastp = points[#points]
    add_point({
        x = lastp.x + ux * 120,
        y = lastp.y,
        z = lastp.z + uz * 120,
    }, {finish = true})

    return {points = points, meta = meta, carves = carves}
end

---------------------------------------------------------------------------
-- Kutání tunelu podél splajny (VoxelManip po dávkách vzorků)
---------------------------------------------------------------------------

local CARVE_R = 4

local function carve_batch(samples)
    if #samples == 0 then return end
    local minp = {x = math.huge, y = math.huge, z = math.huge}
    local maxp = {x = -math.huge, y = -math.huge, z = -math.huge}
    for _, s in ipairs(samples) do
        minp.x = math.min(minp.x, s.x - CARVE_R - 1)
        minp.y = math.min(minp.y, s.y - CARVE_R - 1)
        minp.z = math.min(minp.z, s.z - CARVE_R - 1)
        maxp.x = math.max(maxp.x, s.x + CARVE_R + 1)
        maxp.y = math.max(maxp.y, s.y + CARVE_R + 1)
        maxp.z = math.max(maxp.z, s.z + CARVE_R + 1)
    end
    minp = vector.round(minp)
    maxp = vector.round(maxp)

    local vm = minetest.get_voxel_manip(minp, maxp)
    local emin, emax = vm:read_from_map(minp, maxp)
    local data = vm:get_data()
    local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
    local c_air = minetest.CONTENT_AIR
    local r2 = CARVE_R * CARVE_R

    for _, s in ipairs(samples) do
        local sx = math.floor(s.x + 0.5)
        local sy = math.floor(s.y + 0.5)
        local sz = math.floor(s.z + 0.5)
        for dz = -CARVE_R, CARVE_R do
            for dy = -CARVE_R, CARVE_R do
                for dx = -CARVE_R, CARVE_R do
                    if dx * dx + dy * dy + dz * dz <= r2 then
                        data[area:index(sx + dx, sy + dy, sz + dz)] = c_air
                    end
                end
            end
        end
    end

    vm:set_data(data)
    vm:write_to_map(true)
end

function race.carve_tunnel(route, carve)
    if carve.done then return end
    carve.done = true

    -- navzorkuj splajnu à 1.5 m mezi body i0..i1
    local samples = {}
    local seg, t = carve.i0, 0
    local guard = 0
    while seg < carve.i1 and guard < 600 do
        guard = guard + 1
        table.insert(samples, race.eval(route, seg, t))
        local fin
        seg, t, fin = race.advance(route, seg, t, 1.5)
        if fin then break end
    end
    table.insert(samples, route.points[carve.i1])

    -- bbox celého tunelu pro emerge
    local minp = {x = math.huge, y = math.huge, z = math.huge}
    local maxp = {x = -math.huge, y = -math.huge, z = -math.huge}
    for _, s in ipairs(samples) do
        minp.x = math.min(minp.x, s.x - CARVE_R - 2)
        minp.y = math.min(minp.y, s.y - CARVE_R - 2)
        minp.z = math.min(minp.z, s.z - CARVE_R - 2)
        maxp.x = math.max(maxp.x, s.x + CARVE_R + 2)
        maxp.y = math.max(maxp.y, s.y + CARVE_R + 2)
        maxp.z = math.max(maxp.z, s.z + CARVE_R + 2)
    end

    minetest.emerge_area(vector.round(minp), vector.round(maxp),
        function(blockpos, action, calls_remaining)
            if calls_remaining > 0 then return end
            -- kutej po dávkách ~60 m, ať VoxelManip nebobtná
            local batch = {}
            for _, s in ipairs(samples) do
                table.insert(batch, s)
                if #batch >= 40 then
                    carve_batch(batch)
                    batch = {}
                end
            end
            carve_batch(batch)
        end)
end

---------------------------------------------------------------------------
-- HUD pomůcky
---------------------------------------------------------------------------

function race.format_time(s)
    local m = math.floor(s / 60)
    return string.format("%d:%04.1f", m, s - m * 60)
end

function race.notify(name, text, color)
    local player = minetest.get_player_by_name(name)
    if player then
        hud.flash(player, text, color)
    end
end

-- Světelný prstenec z partiklů kolem checkpointu (kolmý na trať)
local function spawn_ring(route, idx)
    local pos = route.points[idx]
    local seg = math.min(idx, #route.points - 1)
    local T = race.tangent(route, seg, idx <= seg and 0 or 1)
    if vector.length(T) < 0.05 then T = {x = 1, y = 0, z = 0} end
    local u = vector.cross(T, {x = 0, y = 1, z = 0})
    if vector.length(u) < 0.1 then u = {x = 1, y = 0, z = 0} end
    u = vector.normalize(u)
    local v = vector.normalize(vector.cross(T, u))
    for i = 0, 13 do
        local a = i / 14 * 2 * math.pi
        local p = vector.add(pos, vector.add(
            vector.multiply(u, math.cos(a) * 7),
            vector.multiply(v, math.sin(a) * 7)))
        minetest.add_particle({
            pos            = p,
            velocity       = {x = 0, y = 0, z = 0},
            acceleration   = {x = 0, y = 0, z = 0},
            expirationtime = 2.0,
            size           = 2.5,
            texture        = "doggiowars_particle_engine.png^[colorize:#66ff88:180",
            glow           = 14,
        })
    end
end

---------------------------------------------------------------------------
-- Callback od králíka: vstup do nového segmentu → hinty, tunely, emerge
---------------------------------------------------------------------------

function race.on_rabbit_segment(name, seg)
    local st = race.active[name]
    if not st then return end

    local m = st.route.meta[seg]
    if m and m.hint and not m.hint_shown then
        m.hint_shown = true
        race.notify(name, m.hint, 0x9FD8FF)
    end

    -- vykutej tunely v horizontu ~6 bodů před králíkem
    for _, carve in ipairs(st.route.carves) do
        if not carve.done and seg >= carve.i0 - 6 then
            race.carve_tunnel(st.route, carve)
        end
    end

    -- emerge terénu před králíkem
    local idx = math.min(seg + 6, #st.route.points)
    if idx > (st.emerged_upto or 0) then
        st.emerged_upto = idx
        local p = st.route.points[idx]
        minetest.emerge_area(
            {x = p.x - 60, y = p.y - 60, z = p.z - 60},
            {x = p.x + 60, y = p.y + 60, z = p.z + 60})
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function remove_race_hud(player)
    hud.remove_key(player, "race_wp")
    hud.remove_key(player, "race_timer")
    hud.remove_key(player, "race_info")
end

function race.cleanup(name)
    local st = race.active[name]
    if not st then return end
    race.active[name] = nil
    if st.rabbit and st.rabbit:get_luaentity() then
        st.rabbit:remove()
    end
    local player = minetest.get_player_by_name(name)
    if player then
        remove_race_hud(player)
    end
end

function race.finish(name, st, player)
    if st.finished then return end
    st.finished = true
    race.active[name] = nil

    local elapsed = (minetest.get_us_time() - st.t0) / 1e6
    local fighter = doggiowars.get_player_fighter(player)
    if fighter then
        doggiowars.tricks.add_raw_score(fighter, 500)
    end
    local score = fighter and math.floor(fighter.score or 0) or 0

    hud.flash(player, string.format("FINISH — %s  |  SKÓRE %d",
        race.format_time(elapsed), score), 0x66FF88)
    minetest.chat_send_player(name, string.format(
        "Závod dokončen za %s! Checkpointy %d/%d, skóre %d.",
        race.format_time(elapsed), st.cp_hit, #st.cp_indices, score))
    remove_race_hud(player)

    -- králík slaví loopingy v cíli a po 8 s zmizí
    local rabbit = st.rabbit
    local rent = rabbit and rabbit:get_luaentity()
    if rent then
        rent.celebrate = true
        rent.cel_yaw = (rabbit:get_rotation() or {y = 0}).y
    end
    minetest.after(8, function()
        if rabbit and rabbit:get_luaentity() then
            rabbit:remove()
        end
    end)
end

-- Hook z vehicle.lua — smrt během závodu (zbraně/kolize aktivní) = FAIL
function doggiowars.race_on_pilot_died(name)
    local st = race.active[name]
    if not st then return end
    race.notify(name, "RACE FAILED", 0xFF5040)
    minetest.chat_send_player(name, "Závod nedokončen — stíhačka zničena.")
    race.cleanup(name)
end

function doggiowars.race_on_player_left(name)
    race.cleanup(name)
end

---------------------------------------------------------------------------
-- /race příkaz
---------------------------------------------------------------------------

minetest.register_chatcommand("race", {
    params = "[stop]",
    description = "Chrtí závod — leť za zlatým zajícem! /race stop = zrušit",
    privs = {interact = true},
    func = function(name, param)
        if param == "stop" then
            if race.active[name] then
                race.cleanup(name)
                return true, "Závod zrušen."
            end
            return false, "Žádný závod neběží."
        end

        if race.active[name] then
            return false, "Závod už běží — ukonči ho přes /race stop."
        end

        local player = minetest.get_player_by_name(name)
        local fighter = player and doggiowars.get_player_fighter(player)
        if not fighter then
            return false, "Nejsi ve stíhačce."
        end

        local pos = fighter.object:get_pos()
        local yaw = fighter.object:get_rotation().y
        local heading = minetest.yaw_to_dir(yaw + math.pi)
        local route = race.build_route(pos, heading, doggiowars.get_world_seed())

        -- spawn králíka 40 m před hráčem na trati
        local rseg, rt = race.advance(route, 1, 0, 40)
        local obj = minetest.add_entity(race.eval(route, rseg, rt),
            "doggiowars:rabbit")
        if not obj then
            return false, "Nepodařilo se spawnout zajíce."
        end
        local rent = obj:get_luaentity()
        rent.route = route
        rent.player_name = name
        rent.seg, rent.t = rseg, rt

        local cp_indices = {}
        for i in pairs(route.meta) do
            if route.meta[i].checkpoint then
                table.insert(cp_indices, i)
            end
        end
        table.sort(cp_indices)

        race.active[name] = {
            route      = route,
            rabbit     = obj,
            t0         = minetest.get_us_time(),
            cp_hit     = 0,
            cp_indices = cp_indices,
            finished   = false,
        }

        hud.add(player, "race_timer", {
            type = "text", position = {x = 0.5, y = 0.09},
            alignment = {x = 0, y = 0}, text = "0:00.0",
            number = 0xFFFFFF, size = {x = 2},
        })
        hud.add(player, "race_info", {
            type = "text", position = {x = 0.5, y = 0.125},
            alignment = {x = 0, y = 0}, text = "",
            number = 0xFFD75E, size = {x = 1},
        })
        if cp_indices[1] then
            hud.add(player, "race_wp", {
                type = "waypoint", name = "CP", text = "m",
                number = 0x66FF88, precision = 0,
                world_pos = route.points[cp_indices[1]],
            })
        end

        -- tunely na začátku trati vykutej hned
        for _, carve in ipairs(route.carves) do
            if carve.i0 <= 10 then
                race.carve_tunnel(route, carve)
            end
        end

        hud.flash(player, "ZÁVOD! Následuj zlatého zajíce!", 0xFFD75E)
        return true, "Závod začal — následuj zajíce!"
    end,
})

---------------------------------------------------------------------------
-- Globalstep: checkpointy, cíl, HUD (0.2 s)
---------------------------------------------------------------------------

local step_acc = 0
minetest.register_globalstep(function(dtime)
    step_acc = step_acc + dtime
    if step_acc < 0.2 then return end
    step_acc = 0

    for name, st in pairs(race.active) do
        local player = minetest.get_player_by_name(name)
        if not player then
            race.cleanup(name)
        else
            local fighter = doggiowars.get_player_fighter(player)
            if fighter then
                local fpos = fighter.object:get_pos()

                -- checkpoint
                local cp_idx = st.cp_indices[st.cp_hit + 1]
                if cp_idx and fpos then
                    if vector.distance(fpos, st.route.points[cp_idx])
                            < CHECKPOINT_RADIUS then
                        st.cp_hit = st.cp_hit + 1
                        doggiowars.tricks.add_raw_score(fighter, 50)
                        hud.flash(player, string.format("CHECKPOINT %d/%d",
                            st.cp_hit, #st.cp_indices), 0x66FF88)
                        local nxt = st.cp_indices[st.cp_hit + 1]
                        hud.set(player, "race_wp", {
                            world_pos = st.route.points[nxt or #st.route.points],
                        })
                    else
                        -- prstenec u dalšího checkpointu každé ~2 s
                        st.ring_timer = (st.ring_timer or 0) + 0.2
                        if st.ring_timer >= 2 then
                            st.ring_timer = 0
                            spawn_ring(st.route, cp_idx)
                        end
                    end
                end

                -- cíl
                local last = st.route.points[#st.route.points]
                if fpos and vector.distance(fpos, last) < FINISH_RADIUS then
                    race.finish(name, st, player)
                else
                    -- HUD: čas + vzdálenost od králíka
                    local elapsed = (minetest.get_us_time() - st.t0) / 1e6
                    hud.set(player, "race_timer",
                        {text = race.format_time(elapsed)})
                    local rpos = st.rabbit and st.rabbit:get_pos()
                    if rpos and fpos then
                        hud.set(player, "race_info", {
                            text = string.format("ZAJÍC %d m  ·  CP %d/%d",
                                math.floor(vector.distance(fpos, rpos)),
                                st.cp_hit, #st.cp_indices),
                        })
                    end
                end
            end
        end
    end
end)
