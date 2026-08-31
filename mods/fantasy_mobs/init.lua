-- fantasy_mobs — postavičky z UGC továrny (UGCFactory, doména `characters`).
--
-- Pipeline na NASu vyrobí z obrázku rigovaný model a `fc_luanti_pack.py` z něj
-- udělá GLB + PNG + tabulku frame rozsahů. Tenhle mod ty hotové kusy jen
-- registruje jako entity a rozsazuje po ostrovech.
--
-- Klipy se v Luanti přepínají číslem snímku, ne jménem: `set_animation` bere
-- {x = od, y = do}. Proto pipeline skládá všechny klipy na jednu timeline a
-- posílá s modelem jejich rozsahy — jméno klipu žije jen v glTF, kde ho vidí
-- prohlížeč v appce.

local S = core.get_translator and core.get_translator("fantasy_mobs") or function(s) return s end
local modpath = core.get_modpath("fantasy_mobs")

local mod = {}

-- Kolik mobů smí být naráz živých. Bez stropu ABM zaplaví ostrovy: každý
-- mob je mesh se skeletální animací, což je řádově dražší než node.
local MAX_ALIVE = tonumber(core.settings:get("fantasy_mobs_max")) or 40
local SPAWN_CHANCE = tonumber(core.settings:get("fantasy_mobs_spawn_chance")) or 800
local SPAWN_INTERVAL = tonumber(core.settings:get("fantasy_mobs_spawn_interval")) or 30

-- Vzdálenost, na kterou mob zpozoruje hráče, a na kterou se despawnuje.
local NOTICE_RANGE = 12
local DESPAWN_RANGE = 96

local alive = 0

---------------------------------------------------------------------------
-- načtení vygenerovaných postav

-- Každý soubor v characters/ vrací tabulku:
--   { slug, mesh, texture, ranges = { idle_01 = {x=1,y=60}, ... },
--     scale, hp, speed }
-- Soubory generuje export `char.export.luanti`; ručně se needitují.
local function load_characters()
	local out = {}
	local dir = modpath .. "/characters"
	for _, file in ipairs(core.get_dir_list(dir, false) or {}) do
		if file:match("%.lua$") then
			local chunk, err = loadfile(dir .. "/" .. file)
			if not chunk then
				core.log("error", "[fantasy_mobs] " .. file .. ": " .. tostring(err))
			else
				local ok, def = pcall(chunk)
				if ok and type(def) == "table" and def.slug then
					out[#out + 1] = def
				else
					core.log("error", "[fantasy_mobs] " .. file .. " nevrátil definici postavy")
				end
			end
		end
	end
	return out
end

-- Klip, který v modelu není, by entitu zasekl na jednom snímku. Radši
-- vrátíme nil a chování si pomůže tím, co má.
local function clip(def, name)
	local r = def.ranges and def.ranges[name]
	if type(r) ~= "table" or not r.x or not r.y or r.y <= r.x then return nil end
	return r
end

-- Klipy se jmenují podle knihovny animací, ne podle role ve hře. Mob potřebuje
-- "stůj" a "běž", tak se hledá první klip, který sedí; když žádný, vezme se
-- cokoliv, ať se aspoň hýbe.
local function pick(def, names)
	for _, n in ipairs(names) do
		local r = clip(def, n)
		if r then return r, n end
	end
	if def.ranges then
		for n, _ in pairs(def.ranges) do
			local r = clip(def, n)
			if r then return r, n end
		end
	end
	return nil, nil
end

mod.pick = pick
mod.clip = clip

---------------------------------------------------------------------------
-- entita

local function register(def)
	local idle = pick(def, { "idle_01", "idle", "standing_idle_01", "breathing_idle" })
	local walk = pick(def, { "walk_forward", "walking", "walk", "run", "running" })
	local scale = def.scale or 1

	core.register_entity(":fantasy_mobs:" .. def.slug, {
		initial_properties = {
			visual = "mesh",
			mesh = def.mesh,
			textures = { def.texture },
			visual_size = { x = scale, y = scale, z = scale },
			-- 1.8 m vysoká postava (fc_cleanup.py ji na tu výšku škáluje)
			collisionbox = { -0.35, 0, -0.35, 0.35, 1.8 * scale, 0.35 },
			physical = true,
			collide_with_objects = false,
			stepheight = 1.1,
			static_save = false,
		},

		hp_max = def.hp or 10,

		-- Stav patří na entitu, ne do definice: ta je sdílená všemi kusy
		-- téhle postavy, takže zapsat do ní `state` znamená, že si první
		-- mob přepíše chování všem ostatním. dw_core to dělá stejně.
		on_activate = function(self)
			alive = alive + 1
			self.speed = def.speed or 1.6
			self.state = "idle"
			self.object:set_acceleration({ x = 0, y = -9.81, z = 0 })
			if idle then self.object:set_animation(idle, 24, 0, true) end
			self.timer = math.random() * 3
		end,

		on_deactivate = function(self)
			alive = math.max(0, alive - 1)
		end,

		-- Přepnutí klipu je jediná věc, kterou stav dělá navíc; bez téhle
		-- stráže by se set_animation volal každý krok a animace by se
		-- restartovala do prvního snímku.
		set_state = function(self, state)
			if self.state == state then return end
			self.state = state
			local r = (state == "idle") and idle or walk
			if r then self.object:set_animation(r, 24, 0, true) end
		end,

		on_step = function(self, dtime)
			local pos = self.object:get_pos()
			if not pos then return end

			self.timer = (self.timer or 0) - dtime
			local player, dist = mod.nearest_player(pos)

			if player and dist and dist > DESPAWN_RANGE then
				self.object:remove()
				return
			end
			if not player then
				-- nikdo v dosahu: nechat běžet idle, ale nesnažit se chodit
				self:set_state("idle")
				self.object:set_velocity({ x = 0, y = self.object:get_velocity().y, z = 0 })
				return
			end

			if dist and dist < NOTICE_RANGE then
				-- utíkat od hráče; letadlo nad hlavou není kamarád
				local away = vector.direction(player:get_pos(), pos)
				away.y = 0
				self:set_state("walk")
				self.object:set_velocity({
					x = away.x * self.speed,
					y = self.object:get_velocity().y,
					z = away.z * self.speed,
				})
				self.object:set_yaw(math.atan2(away.x, away.z))
				return
			end

			if self.timer <= 0 then
				self.timer = 2 + math.random() * 4
				if math.random() < 0.5 then
					self:set_state("idle")
					self.object:set_velocity({ x = 0, y = self.object:get_velocity().y, z = 0 })
				else
					local yaw = math.random() * 2 * math.pi
					self:set_state("walk")
					self.object:set_yaw(yaw)
					self.object:set_velocity({
						x = math.sin(yaw) * self.speed,
						y = self.object:get_velocity().y,
						z = math.cos(yaw) * self.speed,
					})
				end
			end
		end,
	})
end

function mod.nearest_player(pos)
	local best, bestd
	for _, p in ipairs(core.get_connected_players() or {}) do
		local pp = p:get_pos()
		if pp then
			local d = vector.distance(pos, pp)
			if not bestd or d < bestd then best, bestd = p, d end
		end
	end
	return best, bestd
end

---------------------------------------------------------------------------
-- spawn

local characters = load_characters()
for _, def in ipairs(characters) do
	register(def)
end
mod.characters = characters

if #characters == 0 then
	core.log("action", "[fantasy_mobs] žádné postavy v characters/ — mod je nečinný")
else
	core.log("action", string.format("[fantasy_mobs] %d postav, strop %d živých",
		#characters, MAX_ALIVE))

	core.register_abm({
		label = "fantasy_mobs spawn",
		nodenames = { "group:soil", "group:grass", "default:dirt_with_grass" },
		neighbors = { "air" },
		interval = SPAWN_INTERVAL,
		chance = SPAWN_CHANCE,
		action = function(pos)
			if alive >= MAX_ALIVE then return end
			-- jen tam, kde je nad zemí místo; jinak se mob narodí v kameni
			if core.get_node({ x = pos.x, y = pos.y + 1, z = pos.z }).name ~= "air" then
				return
			end
			-- daleko od hráčů nemá smysl utrácet entity
			local _, dist = mod.nearest_player(pos)
			if not dist or dist > DESPAWN_RANGE then return end
			local def = characters[math.random(#characters)]
			core.add_entity({ x = pos.x, y = pos.y + 1, z = pos.z },
				"fantasy_mobs:" .. def.slug)
		end,
	})
end

-- pro testovací harness
mod.count_alive = function() return alive end
mod.reset_alive = function() alive = 0 end
mod.S = S
fantasy_mobs = mod
