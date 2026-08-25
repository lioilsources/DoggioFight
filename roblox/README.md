# DoggioWars — Roblox prototyp letového modelu

Port jádra letového modelu z `../mods/dw_core/vehicle.lua` (Luanti) do Roblox Luau.
Cíl: ověřit, jestli "feel" DoggioWars (mouse-flight, perzistentní plyn,
dive/climb fyzika, boost, skimming) funguje na robloxím enginu.

## Spuštění

1. Nainstaluj **Roblox Studio** — <https://create.roblox.com/> (zdarma,
   macOS i Windows; vyžaduje Roblox účet).
2. Otevři `DoggioWarsPrototype.rbxlx` (File → Open from File, nebo
   dvojklik).
3. Stiskni **Play** (F5). Server vygeneruje ostrovy, klient tě posadí
   do stíhačky nad domovským ostrovem.

## Ovládání

| Vstup | Akce |
|---|---|
| myš | zaměřovač — letadlo se za ním dotáčí |
| W / S | plyn / brzda (rychlost drží) |
| A / D | vybočení (hýbe zaměřovačem) |
| Space / LeftShift | nos nahoru / dolů |
| S + A/D | airbrake drift |
| LMB | střelba — **ničí terén** (`FillBall` vzduchem) |
| RMB | boost (stojí 25 z metru) |
| V | přepnutí kamery (chase / first-person "na nose") |
| M | radar zap/vyp (v Luanti `/radar`) |
| R | respawn |

## Co je portováno 1:1 z mapgen.lua / biomes.lua

- **nekonečné nebe**: deterministická mřížka 340 m (1020 studů), hustota 82 %,
  ostrovy se generují průběžně kolem hráče za letu (5×5 buněk) a daleko za ním
  se uvolňují — při návratu se ze seedu vygenerují stejně
- LCG hash rozmístění doslovně (double přesnost sedí s LuaJIT); poloměry
  72–165 m s bias `u^1.2`, výškové pásmo 140–760 m
- **5 tvarových profilů** podle biomu: avatar (parabolická kupole +
  exponenciální kořen), disc (čočka), cone, mesa (kolmé stěny), spire (jehla)
- value-noise deformace: kopce na povrchu (`np_hills`), zubaté pobřeží
  (`np_edge`), včetně obou bug-fixů originálu (guard + fade)
- **tunely** ze dvou 3D šumů (`a²+b² < 0.055`) u 55 % ostrovů — proletitelné
  trubky ~9–18 studů v poloměru
- domovský ostrov: buňka (0,0) vždy avatar R=190 m na y=320 m, biom ze seedu
- 12 biomů s vrstvami materiálů (surface/filler/deep) dle hloubky, strop 6 m

## Co je portováno z hud.lua

- **kompasová páska** (klouzavé okno ±60°, `[S ]` aktuální kurz) + kurz
  ve stupních; sever = +Z jako v Luanti
- řádek **SPD / ALT / VS** (rychlost, výška, variometr — vše v metrech)
- **hull** (červený) a **boost** (zlatý) bar vlevo, **SCORE** vlevo nahoře
  (drift +50/s, proximity +2/s — přežívá respawn)
- **vodováha**: čára se klopí s náklonem a stoupání ji zvedá nad pevný
  kruh (Roblox `Rotation` místo skládání z dílků)
- text sklonu/náklonu `▲ 12° BANK +45°` dole uprostřed
- **radar** vpravo nahoře (přepíná **M** místo `/radar`): ostrovy si klient
  počítá ze stejného deterministického LCG jako server — tečky barvené
  podle biomu, velikost dle poloměru, dosah 512 m, sever nahoře
- flash hlášky (zlaté, 1.2 s) na pozici Luanti `hud.flash`
- kolizní poškození `(speed−10)×2.5` a zničení stíhačky s respawnem

## Co je portováno 1:1 z vehicle.lua / tricks.lua (mods/dw_core/)

- konstanty `doggiowars.const` (SPEED_MAX 40, TURN_SPEED 1.5, PITCH_MAX
  0.6, …) — rychlosti v m/s, `SCALE = 3` studu na metr
- mouse-chase řízení: yaw dotáčení nejkratší cestou, pitch clamp,
  automatický náklon do zatáčky (`ROLL_MAX * 0.7`)
- perzistentní plyn (+8/s W, −10/s S), airbrake drift (×2.2 zatáčka,
  −12/s rychlost)
- dive zrychluje od 26° dolů (až 1.5× SPEED_MAX), stoupání krvácí
  rychlost, plný plyn vykryje 70 % ztráty, overspeed decay 12/s
- boost: 2 s při 60 m/s, meter 0–100, start 50, aktivace za 25
- proximity charge: terén do 6 m při >30 m/s nabíjí +1.6/0.2 s
- crash nad 15 m/s = rychlost na minimum (pomalé škrtnutí zdarma)
- eye-lean kamery do zatáčky podle náklonu

## Co je náhrada / zjednodušení

- **Ostrovy**: Roblox smooth Terrain (voxel 4 study ≈ 1,33 m, `WriteVoxels`),
  ne blokový vzhled — 12 biomů mapováno na Terrain materiály (seed 7);
  dekorace biomů (vulkány, houby, vodopády…) zatím chybí
- při odletu a návratu se ztrácí hráčova destrukce terénu (unload + regenerace)
- **Letadlo**: složené z Partů místo `doggiowars_fighter_01.obj`
  (mesh by vyžadoval upload na Roblox CDN)
- **Kinematický let na klientu** (CFrame, raycast kolize) — bez triků,
  HP, závodu a multiplayerové validace
- postava hráče je neviditelná a ukotvená k letadlu

## Soubory

- `DoggioWarsPrototype.rbxlx` — hotový place, otevři ve Studiu
- `island-generator.server.lua` — zdroják server skriptu (generátor ostrovů)
- `flight-controller.client.lua` — zdroják klientského letového modelu
- `build.sh` — po úpravě `.lua` zdrojáků znovu sestaví `.rbxlx`

- `test_mapgen.lua` — headless test mapgenu (`luajit test_mapgen.lua`):
  stub Roblox API, kontrola hustoty/tvarů/tunelů bez Studia

Zdrojem pravdy jsou `.lua` soubory; `.rbxlx` je generovaný artefakt.
Alternativně jde zdrojáky synchronizovat do Studia přes
[Rojo](https://rojo.space/) — pro prototyp zatím netřeba.

## Další kroky (mimo prototyp)

- triky (barrel roll, looping, Immelmann) — port stavového automatu
  `tricks.lua`
- gamepad (Roblox `UserInputService` GamepadThumbstick2 → zaměřovač)
- multiplayer: server-autoritativní pozice + RemoteEvents pro střelbu
- vlastní mesh letadla (upload `.obj` přes Asset Manager)
- blokový vzhled ostrovů: vlastní voxel systém z Partů (greedy meshing)
