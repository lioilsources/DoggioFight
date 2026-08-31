# Vygenerované postavy

Sem padají soubory z exportu `char.export.luanti` v UGCFactory. Ručně se
needitují — příští export je přepíše.

Každý `<slug>.lua` vrací definici:

```lua
return {
	slug    = "knight",           -- shodný s názvem souboru
	mesh    = "fc_knight.glb",    -- patří do ../models/
	texture = "fc_knight.png",    -- patří do ../textures/
	scale   = 1,                  -- model už je 1.8 m vysoký
	hp      = 10,
	speed   = 1.6,
	ranges  = {                   -- z anim_ranges.lua, frame rozsahy
		idle_01      = { x = 1,  y = 60 },
		walk_forward = { x = 65, y = 125 },
	},
}
```

Mod si z `ranges` vybere klip pro stání a pro chůzi podle jména; když
nesedí ani jeden ze známých názvů, vezme první, který v modelu existuje.
Klip s prázdným rozsahem (`y <= x`) se ignoruje — v modelu není a entita by
na něm zamrzla na jednom snímku.
