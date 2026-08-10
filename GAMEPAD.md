# Gamepad (Xbox 360 / PS4 DualShock) — nativní joystick

DoggioWars používá **nativní podporu joysticku v Luanti** (přes SDL2) — žádný
externí mapovač není potřeba. Funguje s Xbox 360 (drát) i PS4 DualShock
(Bluetooth) na macOS.

## Zapnutí

**V singleplayeru to mod zapne sám** při prvním spuštění (`enable_joysticks`
je klientské nastavení, na všech platformách vypnuté z výroby) — pak stačí
**jednou restartovat Luanti**. Ve hře se objeví hláška, že se to stalo.

Ruční nastavení (jiné počítače, servery) — do `minetest.conf` přidej:

```
enable_joysticks = true
joystick_type = auto      # auto-detekce; DualShock (PS4/PS5) chce "ps5"
joystick_deadzone = 4000
joystick_frustum_sensitivity = 150.0   # rychlost otáčení pravou páčkou
```

Kde `minetest.conf` bydlí:

- macOS: `~/Library/Application Support/minetest/minetest.conf`
- Windows: `%APPDATA%\Minetest\minetest.conf`
- Linux: `~/.minetest/minetest.conf`

⚠️ Config uprav, **když Luanti neběží** (při ukončení si ho přepisuje),
a projeví se **až po restartu**. Ovladač připoj **před** spuštěním
(Xbox drátem funguje s `auto`; DualShock spáruj přes Bluetooth a nastav
`joystick_type = ps5` — auto ho nepozná a osy se pomíchají).

## Ovládání (ověřeno na PS4 DualShock, `joystick_type = ps5`)

| Vstup | Akce |
|---|---|
| **Pravá páčka** | míření / let (letadlo se dotáčí za zaměřovačem) |
| **Levá páčka nahoru/dolů** | plyn / brzda (analogově dle výchylky) |
| **Levá páčka doleva/doprava** | zatáčení (yaw) |
| **R2** (`dig`) | **STŘELBA** (držet = dávka ~6/s) |
| **L2** (`place`) | **BOOST** (stojí 25 z metru) |
| **X** (`jump`) | nos nahoru; podržet ≥0,8 s = **Looping** |
| **kolečko** (`sneak`) | nos dolů |
| dvojšvih páčky **doleva/doprava** | **Barrel roll** (krátká nesmrtelnost) |
| dvojité „dozadu" (`down`) | **Immelmann** (otočka 180°) |

Náklon (bank) je **automatický** — letadlo se naklání samo podle ostrosti
zatáčky. Na klávesnici střílí **levé myšítko** (nebo `E`), boost je **pravé
myšítko** nebo dvojité W.

## Režim ponorky — `/mode sub`

Druhé schéma řízení téhož stroje: **6DoF**. Proti letadlu, které pořád někam
letí, ponorka po puštění páček **stojí na místě** — dá se u ostrova viset
a manévrovat z místa všemi směry.

| Vstup | Akce |
|---|---|
| **Levá páčka nahoru/dolů** | posun vpřed / vzad |
| **Levá páčka doleva/doprava** | **boční posun (strafe)** — nezatáčí! |
| **Pravá páčka** | pitch + yaw (trup se dotáčí za pohledem) |
| **X** (`jump`) / **kolečko** (`sneak`) | **nahoru / dolů** |
| **R2** (`dig`) | střelba — míří do zaměřovače, ne po trupu |
| **L2** (`place`) | boost |

Rychlosti: 18 m/s vpřed i vzad, 12 do strany, 10 svisle; rozjezd i úplné
zastavení trvá zhruba 0,7 s. Triky jsou v tomhle režimu **vypnuté** —
dvojšvih páčkou do strany by jinak spouštěl barrel roll při každém úkroku.
Bez parametru `/mode` jen přepíná, zpátky do letadla `/mode plane`.

⚠️ **Proč vertikál není na D-padu:** D-pad se z modu přečíst nedá vůbec.
`get_player_control()` ho nevrací, Luanti si ho drží na klientské zkratky
(viz seznam níž) — a D-pad dolů dokonce přepíná autoforward, který by rozbil
plyn. Proto jsou stoupání a klesání na X a kolečku, tedy na tlačítkách,
která ve stíhačce dávají nos nahoru/dolů.

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

Užitečné chatové příkazy: `/mode` (přepnutí stíhačka ↔ ponorka), `/island`
(nejbližší ostrov), `/island ice` (nejbližší daného biomu — ice, volcano,
desert, jungle, crystal, …), `/home` (domovský ostrov), `/gp` (diagnostika
gamepadu).

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
