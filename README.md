# DoggioWars ✈️

**You ARE the fighter plane.** An aerial dogfight arena set among floating
voxel islands — fly, shoot, pull aerobatic tricks and race a golden rabbit
through carved tunnels.

![screenshot](screenshot.png)

## The world

An endless sky filled with floating islands in **12 biomes**, generated
deterministically from the world seed:

verdant · jungle · savanna · glacial · desert · atoll · crystal ·
volcanic · ashen · barren · mycelial · swamp

Expect volcanoes with lava overflowing from the crater, waterfalls and
rivers on large green islands, lagoon atolls, giant mushrooms, glowing
crystal spires and icicled glacier mesas. Islands are **destructible** —
your shots knock pieces off, and the debris tumbles into the void.

You spawn on a home island (random biome per world) and take off
immediately — there is no walking in DoggioWars.

## Controls

Mouse-flight: the plane chases your crosshair. Steer by looking.

| Input | Action |
|---|---|
| Mouse / right stick | aim — the plane follows the crosshair |
| W / S (left stick ↑↓) | throttle / brake (speed is persistent) |
| A / D (left stick ←→) | yaw assist |
| Left mouse button, E (R2) | **shoot** |
| Right mouse button (L2) | **boost** |
| Space / Shift (X / ○) | nose up / down |
| double-tap A or D | **Barrel roll** (brief invulnerability) |
| hold Space ≥ 0.8 s | **Looping** |
| double-tap S | **Immelmann** turn |
| S + A/D | airbrake drift turn |

Steep dives build overspeed, climbing bleeds it off. Skimming close to
terrain charges your boost meter, and tricks score points.

### Submarine mode — `/mode sub`

A second control scheme for the same craft: **6DoF**, and unlike the plane it
**stands still** when you let go. Nothing carries you forward, so you can hover
next to an island and manoeuvre out of a standstill in any direction.

| Input | Action |
|---|---|
| W / S (left stick ↑↓) | move forward / backward |
| A / D (left stick ←→) | **strafe** left / right |
| Mouse / right stick | pitch + yaw (the hull swings around to follow) |
| Space / Shift (X / ○) | move **up** / **down** |
| Left mouse button, E (R2) | shoot — aimed at the crosshair, not the hull |
| Right mouse button (L2) | boost |

Top speed is 18 m/s forward, 12 sideways, 10 vertically, and it takes about
0.7 s to reach either full speed or a full stop. Tricks are off in this mode —
a double flick of the strafe stick would otherwise fire a barrel roll on every
sidestep. `/mode` with no argument toggles, `/mode plane` goes back.

The vertical is on X / ○ rather than the D-pad because the D-pad cannot be read
by a mod at all — Luanti keeps it for client shortcuts. See
[GAMEPAD.md](GAMEPAD.md).

**Gamepad**: native Luanti joystick support (Xbox 360, PS4 DualShock) —
see [GAMEPAD.md](GAMEPAD.md) for setup, the button map and
troubleshooting (in Czech).

## Chat commands

| Command | Effect |
|---|---|
| `/mode` | switch controls: `/mode sub` = submarine (6DoF), `/mode plane` = fighter |
| `/island` | fly to the nearest island |
| `/island <biome>` | fly above the nearest island of a biome (`ice`, `volcano`, `sand`, `green`, … or full names) |
| `/goto <x> <z>` or `/goto <x> <y> <z>` | fly to coordinates |
| `/home` | return to the home island at the origin |
| `/race` | greyhound race — chase the golden rabbit (`/race stop` to cancel) |
| `/radar` | toggle the island radar (minimap) |
| `/gp` | live gamepad diagnostics overlay |
| `/respawn_fighter` | respawn your plane |

## Installation

Install from ContentDB (Luanti main menu → Content), or clone into your
mods folder:

```
git clone https://github.com/lioilsources/DoggioWars.git doggiowars
```

Requires **Luanti 5.12+** and **Minetest Game**. Enable the mod for your
world; a singlenode-style sky world is created automatically.

## License

- Code: **MIT**
- Media (textures): **CC BY-SA 4.0**

See [LICENSE](LICENSE) for details.
