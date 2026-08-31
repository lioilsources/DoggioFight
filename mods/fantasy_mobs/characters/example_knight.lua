-- Příklad tvaru, který generuje export. Skutečné postavy sem přibydou
-- vedle; tenhle soubor slouží testům a jako vzor.
return {
	slug    = "example_knight",
	mesh    = "fc_example_knight.glb",
	texture = "fc_example_knight.png",
	scale   = 1,
	hp      = 10,
	speed   = 1.6,
	ranges  = {
		idle_01      = { x = 1,  y = 60 },
		walk_forward = { x = 65, y = 125 },
	},
}
