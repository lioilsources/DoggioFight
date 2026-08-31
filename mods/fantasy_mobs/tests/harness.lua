-- Stub harness pro fantasy_mobs. Mockuje `core` API, načte init.lua a
-- prožene entitu chováním bez běžícího serveru.
--   Spuštění: luajit mods/fantasy_mobs/tests/harness.lua
--
-- Stejný důvod jako u chatbridge: spawn a přepínání klipů se jinak ověřuje
-- jen tak, že se hra pustí a kouká se — což nezachytí regresi.

local INIT = (arg and arg[0] or ""):gsub("tests/harness%.lua$", "init.lua")
if INIT == "" or INIT == (arg and arg[0]) then INIT = "../init.lua" end
local MODPATH = INIT:gsub("/init%.lua$", "")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else
		failed = failed + 1
		print("  FAIL: " .. msg)
	end
end

local registered, entities, abms, players, nodes, logs

local function fake_object(pos)
	local o = {
		pos = pos, vel = { x = 0, y = 0, z = 0 }, yaw = 0,
		anim = nil, anim_calls = 0, removed = false,
	}
	o.get_pos = function() return o.pos end
	o.set_pos = function(_, p) o.pos = p end
	o.get_velocity = function() return o.vel end
	o.set_velocity = function(_, v) o.vel = v end
	o.set_acceleration = function() end
	o.set_yaw = function(_, y) o.yaw = y end
	o.set_animation = function(_, r) o.anim = r; o.anim_calls = o.anim_calls + 1 end
	o.remove = function() o.removed = true end
	o.set_properties = function() end
	return o
end

local function load_mod(opts)
	opts = opts or {}
	registered, entities, abms, logs = {}, {}, {}, {}
	players = opts.players or {}
	nodes = opts.nodes or {}
	math.randomseed(opts.seed or 1)

	_G.vector = {
		distance = function(a, b)
			local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
			return math.sqrt(dx * dx + dy * dy + dz * dz)
		end,
		direction = function(from, to)
			local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			if len == 0 then return { x = 0, y = 0, z = 0 } end
			return { x = dx / len, y = dy / len, z = dz / len }
		end,
	}
	_G.core = {
		get_modpath = function() return MODPATH end,
		get_dir_list = function(_, dirs)
			if dirs then return {} end
			return opts.files or { "example_knight.lua" }
		end,
		register_entity = function(name, def) registered[name] = def end,
		register_abm = function(def) abms[#abms + 1] = def end,
		add_entity = function(pos, name)
			local o = fake_object({ x = pos.x, y = pos.y, z = pos.z })
			local ent = setmetatable({ object = o, name = name }, {})
			-- Luanti dava entite celou definici jako prototyp, ne jen
			-- funkce; mock to musi delat taky, jinak by testy prehlizely
			-- pole, na ktera se kod spoleha.
			local proto = registered[":" .. name] or registered[name] or {}
			for k, v in pairs(proto) do
				if k ~= "initial_properties" then ent[k] = v end
			end
			entities[#entities + 1] = ent
			if ent.on_activate then ent:on_activate() end
			return o
		end,
		get_node = function(p) return { name = nodes[p.y] or "air" } end,
		get_connected_players = function() return players end,
		settings = { get = function(_, k) return opts.settings and opts.settings[k] end },
		log = function(_, msg) logs[#logs + 1] = msg end,
		get_translator = nil,
	}
	_G.minetest = _G.core
	dofile(INIT)
	return fantasy_mobs
end

local function fake_player(pos)
	return { get_pos = function() return pos end }
end

---------------------------------------------------------------------------
print("scenario: postavy se nactou a zaregistruji")
local m = load_mod()
check(#m.characters == 1, "nacetla se jedna postava")
check(m.characters[1].slug == "example_knight", "slug z vygenerovaneho souboru")
check(registered[":fantasy_mobs:example_knight"] ~= nil, "entita zaregistrovana")
check(#abms == 1, "spawn ABM zaregistrovano")

print("scenario: prazdna slozka nechá mod necinny")
local empty = load_mod({ files = {} })
check(#empty.characters == 0, "zadne postavy")
check(#abms == 0, "bez postav se ABM neregistruje")

print("scenario: vyber klipu podle jmena")
m = load_mod()
local def = m.characters[1]
local idle = m.pick(def, { "idle_01" })
local walk = m.pick(def, { "walk_forward" })
check(idle and idle.x == 1 and idle.y == 60, "idle rozsah")
check(walk and walk.x == 65 and walk.y == 125, "walk rozsah")
-- neznamy nazev spadne na cokoliv, co v modelu je
local fallback = m.pick(def, { "neexistuje" })
check(fallback ~= nil, "fallback na existujici klip")
-- degenerovany rozsah je jako by nebyl
check(m.clip({ ranges = { a = { x = 5, y = 5 } } }, "a") == nil, "prazdny rozsah se ignoruje")
check(m.clip({ ranges = { a = { x = 9, y = 2 } } }, "a") == nil, "obraceny rozsah se ignoruje")

print("scenario: mob utika od hrace a prepne klip")
m = load_mod({ players = { fake_player({ x = 0, y = 10, z = 0 }) } })
local obj = core.add_entity({ x = 3, y = 10, z = 0 }, "fantasy_mobs:example_knight")
local ent = entities[1]
check(obj.anim ~= nil, "on_activate nastavil idle")
local calls_before = obj.anim_calls
ent:on_step(0.1)
check(ent.state == "walk", "blizky hrac prepne do walk")
check(obj.anim.x == 65, "prehrava se walk klip")
check(obj.vel.x > 0, "utika smerem od hrace (+x)")
-- opakovany krok uz klip neprepina, jinak by se animace restartovala
local calls_after_switch = obj.anim_calls
ent:on_step(0.1)
check(obj.anim_calls == calls_after_switch, "stejny stav klip nepresouva")
check(calls_after_switch > calls_before, "prepnuti stavu klip presunulo")

print("scenario: bez hrace stoji")
m = load_mod({ players = {} })
core.add_entity({ x = 0, y = 10, z = 0 }, "fantasy_mobs:example_knight")
ent = entities[1]
ent:on_step(0.1)
check(ent.state == "idle", "bez hrace idle")
check(ent.object.vel.x == 0 and ent.object.vel.z == 0, "bez hrace se nehybe")

print("scenario: daleky hrac mob despawnuje")
m = load_mod({ players = { fake_player({ x = 500, y = 10, z = 0 }) } })
core.add_entity({ x = 0, y = 10, z = 0 }, "fantasy_mobs:example_knight")
ent = entities[1]
ent:on_step(0.1)
check(ent.object.removed, "mimo dosah se odstrani")

print("scenario: strop zivych entit")
m = load_mod({ players = { fake_player({ x = 0, y = 10, z = 0 }) },
	settings = { fantasy_mobs_max = 2 } })
local abm = abms[1]
for _ = 1, 10 do abm.action({ x = 0, y = 9, z = 0 }) end
check(m.count_alive() == 2, "ABM nepresahne strop (" .. m.count_alive() .. ")")

print("scenario: nespawnuje do kamene")
m = load_mod({ players = { fake_player({ x = 0, y = 10, z = 0 }) },
	nodes = { [10] = "default:stone" } })
abms[1].action({ x = 0, y = 9, z = 0 })
check(m.count_alive() == 0, "bez vzduchu nad zemi se nespawnuje")

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
