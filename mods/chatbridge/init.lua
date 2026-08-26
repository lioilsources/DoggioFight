-- chatbridge — Luanti side.
--
-- VENDOROVANÁ KOPIE. Zdroj pravdy je repo chatbridge (mod/chatbridge); sem
-- se kopíruje přes jeho tools/sync-to-doggiowars.sh, aby hra dorazila
-- streamerovi i s integrací a on neinstaloval žádný mod. Needituj tady.
--
-- Luanti Lua is sandboxed: no sockets, HTTP only, and only when the mod is
-- whitelisted in secure.http_mods. So the mod POLLS the bridge's GET /events;
-- the bridge never calls us.

---------------------------------------------------------------------------
-- Public API for the host game. Declared before the HTTP check so a game can
-- always register, even when the bridge is unreachable.
--
-- register_on_spawn(fn(obj, ev)) lets the game finish an entity the bridge
-- knows nothing about — DoggioWars uses it to bind monsters to an island,
-- without either side depending on the other.
---------------------------------------------------------------------------

chatbridge = {}

local spawn_hooks = {}

function chatbridge.register_on_spawn(fn)
	if type(fn) == "function" then
		spawn_hooks[#spawn_hooks + 1] = fn
	end
end

-- The mod ships inside the game, so most players never use it. Staying quiet
-- until someone points it at a bridge keeps their log clean.
local CONFIGURED_URL = core.settings:get("chatbridge_url")
if not CONFIGURED_URL then
	core.log("action", "[chatbridge] inactive (set chatbridge_url to enable)")
	return
end

-- request_http_api() MUST be called here, at load time, on the top level.
-- Called later it returns nil and there is no second chance.
--
-- The whitelist cannot come from the game's minetest.conf — Luanti refuses
-- secure.* from a game ("Secure setting ... isn't allowed") so a game cannot
-- grant itself network access. It has to be in the player's or server's own
-- minetest.conf.
local http = core.request_http_api()
if not http then
	core.log("warning", "[chatbridge] chatbridge_url is set but HTTP is not "
		.. "allowed — add 'secure.http_mods = chatbridge' to YOUR minetest.conf "
		.. "(the game's own config cannot grant this)")
	return
end

local BRIDGE_URL = CONFIGURED_URL
BRIDGE_URL = (BRIDGE_URL:gsub("/+$", "")) -- trim trailing slash

local POLL_INTERVAL = 1.0 -- seconds between polls
local CHECK_INTERVAL = 0.2 -- how often to check an in-flight fetch
local FETCH_TIMEOUT = 5
local MAX_EVENTS = 50
local SPAWN_R_MIN, SPAWN_R_MAX = 5, 15 -- spawn ring around the player
local SPAWN_COUNT_CAP = 10 -- hard cap regardless of params.count
local SWEEP_INTERVAL = 1.0 -- seconds between TTL sweeps

-- Protected zone: chat may not drop anything within this radius of the spawn
-- point, so nobody can swarm a player the moment they land there.
--
-- The centre comes from chatbridge_protect_center, falling back to the game's
-- static_spawnpoint. With neither set there is no meaningful place to protect
-- and the zone stays off — guessing (0,0,0) would carve a hole out of a world
-- like DoggioWars, whose home island sits above the origin.
local PROTECT_R = tonumber(core.settings:get("chatbridge_protect_radius")) or 40
local PROTECT_CENTER
do
	local raw = core.settings:get("chatbridge_protect_center")
		or core.settings:get("static_spawnpoint")
	local x, y, z = tostring(raw or ""):match(
		"^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*$")
	if x then
		PROTECT_CENTER = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	else
		PROTECT_R = 0
	end
end

-- Optional fixed spawn point used ONLY when no players are online (showcase /
-- testing). Empty = skip spawns when the world is empty. Format "x,y,z".
local SPAWN_FALLBACK
do
	local raw = core.settings:get("chatbridge_spawn_fallback")
	if raw then
		local x, y, z = raw:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
		if x then
			SPAWN_FALLBACK = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
		end
	end
end

local last_seq = 0 -- highest event seq we have applied
local enabled = true -- flipped in-game by /chatoff and /chaton
local tracked = {} -- { {obj = ObjectRef, expires = seconds}, ... }

---------------------------------------------------------------------------
-- Event handlers (phase 4: spawn only; weather/effect come later)
---------------------------------------------------------------------------

local function now()
	return core.get_us_time() / 1e6
end

-- Full 3D distance on purpose: a horizontal test would protect an infinite
-- column, and in a sky game that is the whole airspace over the spawn.
local function in_protected(pos)
	if PROTECT_R <= 0 then
		return false
	end
	local dx = pos.x - PROTECT_CENTER.x
	local dy = pos.y - PROTECT_CENTER.y
	local dz = pos.z - PROTECT_CENTER.z
	return dx * dx + dy * dy + dz * dz < PROTECT_R * PROTECT_R
end

-- Everything chat spawns is remembered so it can be reclaimed. ttl = 0 means
-- "the entity manages its own lifetime" (DoggioWars debris does), so it is
-- spawned but never tracked.
local function track(obj, ttl)
	if ttl and ttl > 0 then
		tracked[#tracked + 1] = { obj = obj, expires = now() + ttl }
	end
end

local function sweep()
	local t = now()
	local kept = {}
	for _, rec in ipairs(tracked) do
		local obj = rec.obj
		if not obj:get_luaentity() then
			-- already gone (engine unloaded it, or it removed itself)
		elseif t >= rec.expires then
			obj:remove()
		else
			kept[#kept + 1] = rec
		end
	end
	tracked = kept
	core.after(SWEEP_INTERVAL, sweep)
end
core.after(SWEEP_INTERVAL, sweep)

local function handle_spawn(ev)
	local params = ev.params or {}
	local entity = params.entity
	if type(entity) ~= "string" then
		core.log("warning", "[chatbridge] spawn '" .. tostring(ev.action)
			.. "' has no params.entity")
		return
	end
	local players = core.get_connected_players()
	if #players == 0 and not SPAWN_FALLBACK then
		return -- nobody online and no fallback point
	end
	local count = math.max(1, math.min(tonumber(params.count) or 1, SPAWN_COUNT_CAP))
	local ttl = tonumber(ev.ttl) or 0
	for _ = 1, count do
		local base
		if #players > 0 then
			base = players[math.random(#players)]:get_pos()
		else
			base = SPAWN_FALLBACK
		end
		local ang = math.random() * math.pi * 2
		local r = SPAWN_R_MIN + math.random() * (SPAWN_R_MAX - SPAWN_R_MIN)
		local pos = {
			x = base.x + math.cos(ang) * r,
			y = base.y + 1,
			z = base.z + math.sin(ang) * r,
		}
		if in_protected(pos) then
			-- Skip rather than relocate: nudging it outward would just drop
			-- the thing at the zone border, which is the same nuisance.
			core.log("info", "[chatbridge] spawn skipped inside protected zone")
		else
			local obj = core.add_entity(pos, entity)
			if obj then
				track(obj, ttl)
				for _, fn in ipairs(spawn_hooks) do
					-- one bad hook must not stop the others
					local ok, err = pcall(fn, obj, ev)
					if not ok then
						core.log("error", "[chatbridge] spawn hook failed: "
							.. tostring(err))
					end
				end
			else
				core.log("warning", "[chatbridge] add_entity failed for " .. entity)
			end
		end
	end
end

-- The bridge tells us when it stopped issuing spawns; surface it rather than
-- leaving the streamer wondering why the chat went quiet.
local function handle_system(ev)
	if ev.action == "throttled" then
		core.chat_send_all("[chatbridge] world is full, spawns paused")
	end
end

local handlers = {
	spawn = handle_spawn,
	system = handle_system,
}

local function apply_event(ev)
	if type(ev) ~= "table" or type(ev.type) ~= "string" then
		return
	end
	if not enabled and ev.type ~= "system" then
		return -- muted in-game by /chatoff
	end
	local h = handlers[ev.type]
	if h then
		h(ev)
	end
	-- unknown types are ignored on purpose (forward-compatible)
end

---------------------------------------------------------------------------
-- Poll loop: one in-flight fetch at a time, checked on later ticks so the
-- server thread never blocks on the network.
---------------------------------------------------------------------------

local pending -- in-flight fetch handle, or nil

local function process(res)
	if not res.succeeded or res.code ~= 200 then
		core.log("warning", "[chatbridge] poll failed code=" .. tostring(res.code))
		return
	end
	local data = core.parse_json(res.data or "")
	if type(data) ~= "table" then
		core.log("warning", "[chatbridge] bad JSON from bridge")
		return
	end
	if data.reset then
		-- We fell outside the retained window: resync to latest, don't replay.
		last_seq = tonumber(data.latest) or last_seq
		core.log("action", "[chatbridge] resynced to seq " .. last_seq)
		return
	end
	for _, ev in ipairs(data.events or {}) do
		apply_event(ev)
		local s = tonumber(ev.seq)
		if s and s > last_seq then
			last_seq = s
		end
	end
end

local poll -- forward declaration

local function check_pending()
	local res = http.fetch_async_get(pending)
	if not res.completed then
		core.after(CHECK_INTERVAL, check_pending) -- still in flight
		return
	end
	pending = nil
	process(res)
	core.after(POLL_INTERVAL, poll) -- next cycle
end

poll = function()
	local url = BRIDGE_URL .. "/events?since=" .. last_seq .. "&max=" .. MAX_EVENTS
	pending = http.fetch_async({ url = url, timeout = FETCH_TIMEOUT, method = "GET" })
	core.after(CHECK_INTERVAL, check_pending)
end

core.after(POLL_INTERVAL, poll)
core.log("action", "[chatbridge] polling " .. BRIDGE_URL .. " every " .. POLL_INTERVAL .. "s")

---------------------------------------------------------------------------
-- In-game kill switch. Faster than reaching for the admin endpoint when
-- something is going wrong on stream; POST /admin/off remains the remote one.
---------------------------------------------------------------------------

local function set_enabled(on)
	enabled = on
	if not on then
		for _, rec in ipairs(tracked) do
			if rec.obj:get_luaentity() then
				rec.obj:remove()
			end
		end
		tracked = {}
	end
	return true, on and "Chat actions ON." or "Chat actions OFF, world cleared."
end

core.register_chatcommand("chatoff", {
	description = "Stop applying Twitch chat actions and clear what chat spawned",
	privs = { server = true },
	func = function()
		return set_enabled(false)
	end,
})

core.register_chatcommand("chaton", {
	description = "Resume applying Twitch chat actions",
	privs = { server = true },
	func = function()
		return set_enabled(true)
	end,
})
