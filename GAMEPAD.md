# Gamepad (Xbox 360 / PS4 DualShock) — nativní joystick

DoggioWars používá **nativní podporu joysticku v Luanti** (přes SDL2) — žádný
externí mapovač není potřeba. Funguje s Xbox 360 (drát) i PS4 DualShock
(Bluetooth) na macOS.

## Zapnutí

**Hra si joystick zapne sama.** `enable_joysticks` je klientské nastavení,
z výroby vypnuté na všech platformách; DoggioWars ho posílá jako svůj
výchozí stav v `minetest.conf` hry (spolu s `joystick_deadzone = 4000`).
Do tvého configu to nic nezapíše — jen se posune výchozí hodnota, dokud
hraješ tuhle hru.

Zbývá **jedna věc, kterou za tebe udělat nejde**: typ ovladače. Je to
vlastnost hardwaru, ne hry, a Luanti modu neprozradí, co je připojené.

**Nastavení → Ovládání → Gamepady → Joystick type**

- **Xbox 360 / Xbox One** → `auto` stačí, nic neměň.
- **PS4 / PS5 DualShock** → přepni na **`ps5`**. Na `auto` se osy pomíchají
  a ovládání působí „rozhozeně".

Ve stejné sekci je i `Joystick dead zone` (ujíždí-li kamera, zvyš) a
`Joystick frustum sensitivity` (rychlost otáčení pravou páčkou).

⚠️ Ovladač připoj **před** spuštěním hry.

Kdo si to raději píše ručně do `minetest.conf` (servery, dávkové nasazení),
najde ho tady — ale uprav ho, **když Luanti neběží**, protože při ukončení
si ho hra přepisuje:

- macOS: `~/Library/Application Support/minetest/minetest.conf`
- Windows: `%APPDATA%\Minetest\minetest.conf`
- Linux: `~/.minetest/minetest.conf`

## Ovládání (ověřeno na PS4 DualShock, `joystick_type = ps5`)

| Vstup | Akce |
|---|---|
| **Pravá páčka** | míření / let (letadlo se dotáčí za zaměřovačem) |
| **Levá páčka nahoru/dolů** | plyn / brzda (analogově dle výchylky) |
| **Levá páčka doleva/doprava** | **náklon** — položí letadlo na křídlo a stáčí ho ~3× pomaleji než pohled |
| **R2** (`dig`) | **STŘELBA** (držet = dávka ~6/s) |
| **L2** (`place`) | **BOOST** (stojí 25 z metru) |
| **X** (`jump`) | nos nahoru; podržet ≥0,8 s = **Looping** |
| **kolečko** (`sneak`) | nos dolů |
| dvojšvih páčky **doleva/doprava** | **Barrel roll** (krátká nesmrtelnost) |
| dvojité „dozadu" (`down`) | **Immelmann** (otočka 180°) |

Polohu stroje ukazuje **vodováha pod minimapou** — čára se naklání spolu s
letadlem a při stoupání se zvedne nad pevnou značku, při klesání pod ni.
Když na značce leží, letíš rovně.

Náklon máš **pod páčkou**: čím víc levou páčku vychýlíš do strany, tím víc
letadlo položí na křídlo (plná výchylka ≈ 60°) a tím ochotněji se stáčí —
ale pořád ~3× pomaleji, než když zamíříš pohledem. Něco navíc si letadlo
přidá samo podle toho, jak ostře se dotáčí za zaměřovačem. Na klávesnici střílí **levé myšítko** (nebo `E`), boost je **pravé
myšítko** nebo dvojité W.

## Režim ponorky — příkaz `/mode` (VÝCHOZÍ REŽIM)

Ponorka je **výchozí** ovládání. Příkaz **`/mode`** přepíná na stíhačku a
zpět (`/mode sub`, `/mode fighter` nastaví režim napřímo). Ponorka je
„hover": puštěné ovládání plynule zastaví a loď visí na místě. Režim
přežívá respawn.

| Vstup | Akce |
|---|---|
| **Levá páčka nahoru/dolů** (W/S) | tah dopředu/dozadu po ose trupu |
| **Levá páčka doleva/doprava** (A/D) | úkrok do stran (strafe, kurz se nemění) |
| **Pravá páčka** (myš) | kurz + sklon (trup se dotáčí za zaměřovačem) |
| **X** (`sneak`, Shift) | stoupání svisle nahoru |
| **○ kolečko** (`jump`, Space) | klesání svisle dolů |
| **R2** (`dig`) | střelba (funguje i v ponorce) |

Triky, boost a drift jsou v ponorce **vypnuté** (tlačítka mají nový
význam). Vertikální posun je na X/kolečku, protože D-pad Luanti modu
neposílá (viz níže).

⚠️ **Proč je stoupání na `sneak` a klesání na `jump`?** Vypadá to obráceně,
ale je to kvůli fyzickým tlačítkům: pod `joystick_type = ps5` posílá
DualShock **X jako `sneak`** a **○ jako `jump`** (ověřeno přes `/gp`).
Aby X stoupalo — jak to na ovladači sedí do ruky — musí být `sneak`
nahoru. **Daň za to platí klávesnice**: v ponorce je stoupání na
**Shiftu** a klesání na **Space**, tedy naopak než ve stíhačce. Kdyby ti
na jiném ovladači vyšlo mapování opačně, je to jeden řádek ve
`vehicle.lua` (proměnná `heave`).

Co ovladač NEUMÍ namapovat (klientské zkratky Luanti, mod je nezmění):

- **Trojúhelník / čtverec, R1 / L1** — nic (Luanti je nemapuje vůbec).
- **D-pad vlevo** (minimapa) — záměrně bez funkce. Klient opakuje držená
  joystick tlačítka po 0,17 s (`repeat_joystick_button_time`), takže
  tlačítko minimapy blikalo — radar je proto trvale zapnutý s jediným
  režimem a vypíná se příkazem **`/radar`** (dalekohled/zoom vypnut taky).
- **D-pad vpravo** — přepíná fast mode (pro hru neškodné, jen hláška).
- **D-pad nahoru** — přepíná fly mode (taky neškodné).
- ⚠️ **D-pad dolů** — přepíná **AUTOFORWARD** (automatická chůze vpřed)!
  Se zapnutým autoforwardem klient hlásí plný plyn napořád — letadlo
  věčně zrychluje a levá páčka „nereaguje". Poznáš to v `/gp`:
  `L(...,+1.00)` v klidu. Oprava: stisknout D-pad dolů znovu
  (hláška „Automatic forward disabled").

Užitečné chatové příkazy: `/island` (nejbližší ostrov), `/island ice`
(nejbližší daného biomu — ice, volcano, desert, jungle, crystal, …),
`/home` (domovský ostrov), `/gp` (diagnostika gamepadu).

## Které fyzické tlačítko dělá co? → příkaz `/gp`

Nativní mapování tlačítko→akce si Luanti drží interně a liší se podle
ovladače. Zjistíš ho takhle:

1. Ve hře napiš do chatu **`/gp`** (zapne diagnostiku).
2. Uprostřed obrazovky se ukáže živě: výchylka levé páčky `L(x,y)` a seznam
   právě „stisknutých" akcí (`jump aux1 dig …`).
3. Zmáčkni postupně každé tlačítko na ovladači a poznamenej si, která akce
   se rozsvítí. Tak zjistíš, které tlačítko je střelba (`aux1`), náklon
   (`dig`/`place`), plyn atd.
4. Znovu `/gp` = vypnout.

Když ti nějaká akce sedí na nepohodlném tlačítku, napiš mi mapování z `/gp`
a **přemapuju herní akce** na ergonomičtější tlačítka (mod si určuje, co která
akce dělá — takže to jde doladit bez externího nástroje).

## Řešení potíží

- **Ovladač nereaguje** → připoj ho *před* startem hry; zkus `joystick_type =
  xbox` (pro 360) nebo `ps5` (pro DualShock 4/5) místo `auto`.
- **Kamera ujíždí sama** → zvyš `joystick_deadzone` (např. 3500).
- **Otáčení moc rychlé/pomalé** → uprav `joystick_frustum_sensitivity`.
- Přepínání ovladačů: `joystick_id` (0 = první).
