-- Stub harness for the chatbridge Luanti mod. Mocks the `core` API, loads
-- init.lua, and drives the core.after queue to exercise the poll state machine
-- without a running server. Run: luajit mod/chatbridge/tests/harness.lua
--
-- unpack shim (LuaJIT is 5.1: global unpack; newer Lua: table.unpack)
local unpack = unpack or table.unpack

local INIT = (arg and arg[0] or ""):gsub("tests/harness%.lua$", "init.lua")
if INIT == "" or INIT == (arg and arg[0]) then INIT = "../init.lua" end

local scheduled, added, fetches, fake_result, canned
local passed, failed = 0, 0

local function check(cond, msg)
	if cond then passed = passed + 1 else
		failed = failed + 1
		print("  FAIL: " .. msg)
	end
end

-- Build a fresh mocked `core` and (re)load the mod. opts.settings is a table
-- of setting values; opts.players overrides the connected-players list.
local settings_values, players, fake_time, chatcmds, chat_lines, removed, hooked
local sweep_job
local function load_mod(opts)
	opts = opts or {}
	settings_values = opts.settings or {}
	-- The mod stays dormant without a bridge URL, so every scenario that is
	-- not explicitly about that gets one.
	if settings_values.chatbridge_url == nil and not opts.unconfigured then
		settings_values.chatbridge_url = "http://127.0.0.1:8093"
	end
	players = opts.players
	fake_time, chatcmds, chat_lines, removed, hooked = 0, {}, {}, {}, {}
	if players == nil then
		players = { { get_pos = function() return { x = 0, y = 10, z = 0 } end } }
	end
	scheduled, added, fetches, fake_result, canned = {}, {}, {}, nil, nil
	math.randomseed(1)
	_G.core = {
		request_http_api = function()
			return {
				fetch_async = function(req)
					fetches[#fetches + 1] = req
					return { id = #fetches }
				end,
				fetch_async_get = function() return fake_result end,
			}
		end,
		after = function(d, fn, ...)
			scheduled[#scheduled + 1] = { fn = fn, args = { ... } }
		end,
		log = function() end,
		get_us_time = function() return fake_time * 1e6 end,
		register_chatcommand = function(name, def) chatcmds[name] = def end,
		chat_send_all = function(msg) chat_lines[#chat_lines + 1] = msg end,
		settings = { get = function(_, k) return settings_values[k] end },
		get_connected_players = function() return players end,
		add_entity = function(pos, name)
			local rec = { pos = pos, name = name, alive = true }
			local obj
			obj = {
				get_luaentity = function() return rec.alive and rec or nil end,
				remove = function()
					rec.alive = false
					removed[#removed + 1] = rec
				end,
			}
			rec.obj = obj
			added[#added + 1] = rec
			return obj
		end,
		parse_json = function() return canned end,
	}
	dofile(INIT)
	-- The TTL sweep schedules itself at load; keep it out of the poll FIFO so
	-- step() stays "advance the poll state machine" and time is explicit.
	sweep_job = table.remove(scheduled, 1)
end

-- Run the next scheduled callback (FIFO).
local function step()
	local job = table.remove(scheduled, 1)
	if not job then return false end
	job.fn(unpack(job.args))
	return true
end

-- Run the pending TTL sweep at the current fake_time; it reschedules itself.
local function run_sweep()
	if not sweep_job then return false end
	local job = sweep_job
	sweep_job = nil
	job.fn()
	sweep_job = table.remove(scheduled) -- the freshly rescheduled sweep
	return true
end

local function complete_ok()
	fake_result = { completed = true, succeeded = true, code = 200, data = "{}" }
end

---------------------------------------------------------------------------
print("scenario: spawn event applied, last_seq advances")
load_mod()
check(#fetches == 0 and #scheduled == 1, "load schedules exactly one poll")
step() -- poll(): starts fetch #1 with since=0, schedules check_pending
check(#fetches == 1, "poll starts one fetch")
check(fetches[1].url:find("since=0"), "first fetch uses since=0")
canned = {
	events = {
		{ seq = 1, type = "spawn", action = "chicken",
			params = { entity = "test:chicken", count = 2 }, ttl = 60 },
	},
	latest = 1,
}
complete_ok()
step() -- check_pending(): completed → process → spawn ×2 → schedule poll
check(#added == 2, "count=2 spawned two entities (got " .. #added .. ")")
check(added[1].name == "test:chicken", "spawned the requested entity")
do
	local dx, dz = added[1].pos.x, added[1].pos.z
	local d = math.sqrt(dx * dx + dz * dz)
	check(d >= 5 and d <= 15, "spawn distance within [5,15] (got " .. string.format("%.1f", d) .. ")")
	check(added[1].pos.y == 11, "spawn y = player.y + 1")
end
step() -- next poll(): should use since=1 now
check(fetches[2] and fetches[2].url:find("since=1"), "second fetch uses since=1 (last_seq advanced)")

---------------------------------------------------------------------------
print("scenario: reset jumps to latest, no spawns")
load_mod()
step() -- poll #1 (since=0)
canned = { reset = true, latest = 42 }
complete_ok()
step() -- check_pending → process → reset
check(#added == 0, "reset applies no events")
step() -- next poll
check(fetches[2] and fetches[2].url:find("since=42"), "after reset, fetch uses since=latest (42)")

---------------------------------------------------------------------------
print("scenario: fallback spawn point used when no players online")
load_mod({ settings = { chatbridge_spawn_fallback = "0,8,0" }, players = {} })
step() -- poll
canned = {
	events = {
		{ seq = 1, type = "spawn", action = "rocks",
			params = { entity = "test:rock", count = 2 }, ttl = 10 },
	},
	latest = 1,
}
complete_ok()
step() -- process → spawn at fallback
check(#added == 2, "empty world + fallback spawns 2 (got " .. #added .. ")")
do
	local d = math.sqrt(added[1].pos.x ^ 2 + added[1].pos.z ^ 2)
	check(d >= 5 and d <= 15, "fallback spawn distance within [5,15]")
	check(added[1].pos.y == 9, "fallback spawn y = 8 + 1")
end

---------------------------------------------------------------------------
print("scenario: no players and no fallback → nothing spawns")
load_mod({ players = {} })
step()
canned = {
	events = {
		{ seq = 1, type = "spawn", action = "rocks",
			params = { entity = "test:rock", count = 2 }, ttl = 10 },
	},
	latest = 1,
}
complete_ok()
step()
check(#added == 0, "empty world without a fallback spawns nothing")

---------------------------------------------------------------------------
print("scenario: HTTP error is logged, not applied")
load_mod()
step()
fake_result = { completed = true, succeeded = false, code = 502, data = "" }
canned = nil
step() -- process: non-200 → no spawn, no crash
check(#added == 0, "failed poll spawns nothing")
step()
check(fetches[2] ~= nil, "poll loop continues after a failed fetch")

---------------------------------------------------------------------------
-- Phase 5: safety layer
---------------------------------------------------------------------------

-- Drive one spawn event through a freshly loaded mod and return its records.
local function spawn_once(opts, ev)
	load_mod(opts)
	step() -- poll
	canned = { events = { ev }, latest = ev.seq or 1 }
	complete_ok()
	step() -- process
end

print("scenario: TTL cleanup reclaims what chat spawned")
load_mod()
check(#scheduled == 1 and sweep_job, "load schedules a poll plus the TTL sweep")
step() -- poll
canned = {
	events = { { seq = 1, type = "spawn", action = "rocks",
		params = { entity = "test:rock", count = 1 }, ttl = 30 } },
	latest = 1,
}
complete_ok()
step() -- process → spawn
check(#added == 1 and added[1].alive, "entity spawned and alive")
fake_time = 10
run_sweep()
check(added[1].alive, "still alive before TTL expires")
fake_time = 31
run_sweep()
check(not added[1].alive, "removed once TTL expired")

print("scenario: ttl = 0 means the entity owns its lifetime")
spawn_once(nil, { seq = 1, type = "spawn", action = "debris",
	params = { entity = "test:debris", count = 1 }, ttl = 0 })
check(#added == 1, "ttl=0 entity spawned")
fake_time = 9999
run_sweep()
check(added[1].alive, "ttl=0 entity is never reclaimed by the sweep")

print("scenario: protected zone rejects spawns near the world spawn")
-- player sits at (0,10,0) and the zone covers the whole spawn ring
spawn_once({ settings = { chatbridge_protect_center = "0,10,0",
	chatbridge_protect_radius = "100" } },
	{ seq = 1, type = "spawn", action = "rocks",
		params = { entity = "test:rock", count = 3 }, ttl = 10 })
check(#added == 0, "nothing spawns inside the protected zone (got " .. #added .. ")")

print("scenario: unconfigured centre leaves the zone off")
spawn_once(nil,
	{ seq = 1, type = "spawn", action = "rocks",
		params = { entity = "test:rock", count = 2 }, ttl = 10 })
check(#added == 2, "no centre configured = no zone (got " .. #added .. ")")

print("scenario: /chatoff mutes and clears, /chaton resumes")
spawn_once(nil,
	{ seq = 1, type = "spawn", action = "rocks",
		params = { entity = "test:rock", count = 2 }, ttl = 60 })
check(#added == 2, "two entities live before the kill switch")
check(chatcmds.chatoff and chatcmds.chaton, "both chat commands registered")
check(chatcmds.chatoff.privs.server, "/chatoff needs the server priv")
chatcmds.chatoff.func("admin")
check(not added[1].alive and not added[2].alive, "/chatoff cleared chat spawns")
-- further events are ignored while muted
canned = { events = { { seq = 2, type = "spawn", action = "rocks",
	params = { entity = "test:rock", count = 2 }, ttl = 60 } }, latest = 2 }
complete_ok()
step() -- next poll
step() -- process while muted
check(#added == 2, "muted: no new spawns (got " .. #added .. ")")
chatcmds.chaton.func("admin")
canned = { events = { { seq = 3, type = "spawn", action = "rocks",
	params = { entity = "test:rock", count = 1 }, ttl = 60 } }, latest = 3 }
complete_ok()
step()
step()
check(#added == 3, "resumed: spawns apply again (got " .. #added .. ")")

print("scenario: system/throttled reaches the streamer even while muted")
spawn_once(nil,
	{ seq = 1, type = "system", action = "throttled", params = { live = 40 } })
check(#chat_lines == 1 and chat_lines[1]:find("full"), "throttled announced in chat")
chatcmds.chatoff.func("admin")
canned = { events = { { seq = 2, type = "system", action = "throttled",
	params = { live = 40 } } }, latest = 2 }
complete_ok()
step()
step()
check(#chat_lines == 2, "system events bypass the mute (got " .. #chat_lines .. ")")

print("scenario: game spawn hook runs and survives a bad hook")
load_mod()
chatbridge.register_on_spawn(function() error("boom") end)
chatbridge.register_on_spawn(function(obj, ev)
	hooked[#hooked + 1] = { obj = obj, action = ev.action }
end)
step()
canned = { events = { { seq = 1, type = "spawn", action = "dragon",
	params = { entity = "doggiowars:dragon_fire", count = 1 }, ttl = 45 } },
	latest = 1 }
complete_ok()
step()
check(#hooked == 1, "later hook still ran after an erroring one")
check(hooked[1].action == "dragon", "hook receives the event")
check(hooked[1].obj == added[1].obj, "hook receives the spawned object")

print("scenario: unconfigured mod stays dormant")
load_mod({ unconfigured = true })
check(#scheduled == 0 and not sweep_job, "no URL = no poll loop, no sweep")
check(#fetches == 0, "no URL = no HTTP traffic")

---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
