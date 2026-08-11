#!/usr/bin/env python3
"""Generátor textur pro mods/dw_nodes.

Kreslí všech ~50 dlaždic a spritů proceduálně, jen ze standardní knihovny
(zlib + struct, žádný Pillow). Deterministické — stejný název textury dá
vždycky stejné pixely, takže přegenerování nedělá šum v gitu.

Použití:  python3 tools/gen_textures.py
Výstup:   mods/dw_nodes/textures/dwn_*.png  (16x16 RGBA)
"""
import os
import struct
import zlib

SIZE = 16
OUT = os.path.join(os.path.dirname(__file__), "..", "mods", "dw_nodes", "textures")


# --------------------------------------------------------------------------
# PNG zápis a deterministický šum
# --------------------------------------------------------------------------

def write_png(path, pixels):
    """pixels = [[(r,g,b,a), ...16], ...16]"""
    raw = b"".join(
        b"\x00" + bytes(v for px in row for v in px) for row in pixels)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    hdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", hdr)
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


class Rnd:
    """LCG se seedem odvozeným z názvu — reprodukovatelné napříč běhy."""

    def __init__(self, name):
        h = 2166136261
        for ch in name:
            h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
        self.s = h or 1

    def next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s

    def rng(self, a, b):
        return a + self.next() % (b - a + 1)


def blank():
    return [[(0, 0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]


def clamp(v):
    return max(0, min(255, int(v)))


# --------------------------------------------------------------------------
# Kreslicí primitiva
# --------------------------------------------------------------------------

def noise_tile(name, base, spread=12, alpha=255, coarse=1):
    """Rovnoměrná dlaždice s jemným zrnem — kámen, písek, hlína."""
    r = Rnd(name)
    px = blank()
    for y in range(SIZE):
        for x in range(SIZE):
            if coarse > 1 and (x % coarse or y % coarse):
                px[y][x] = px[y][x - 1] if x else px[y - 1][x]
                continue
            d = r.rng(-spread, spread)
            px[y][x] = (clamp(base[0] + d), clamp(base[1] + d),
                        clamp(base[2] + d), alpha)
    return px


def speckle(px, name, color, count, size=1):
    """Rozsype po dlaždici skvrnky (oblázky ve štěrku, bobule v listí)."""
    r = Rnd(name + "speck")
    for _ in range(count):
        cx, cy = r.rng(0, SIZE - 1), r.rng(0, SIZE - 1)
        for dy in range(size):
            for dx in range(size):
                x, y = (cx + dx) % SIZE, (cy + dy) % SIZE
                if px[y][x][3]:
                    px[y][x] = color
    return px


def leaves_tile(name, base, berries=None):
    """Listí: zrno + průhledné díry po okrajích, ať prosvítá obloha."""
    px = noise_tile(name, base, spread=18)
    r = Rnd(name + "holes")
    for _ in range(26):
        x, y = r.rng(0, SIZE - 1), r.rng(0, SIZE - 1)
        px[y][x] = (0, 0, 0, 0)
    if berries:
        speckle(px, name, berries, 7)
    return px


def bark_tile(name, base):
    """Kůra: svislé pruhy."""
    r = Rnd(name)
    px = blank()
    cols = [r.rng(-16, 16) for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            d = cols[x] + r.rng(-4, 4)
            px[y][x] = (clamp(base[0] + d), clamp(base[1] + d),
                        clamp(base[2] + d), 255)
    return px


def tree_top_tile(name, base):
    """Řez kmenem: soustředné letokruhy."""
    r = Rnd(name)
    px = blank()
    c = (SIZE - 1) / 2
    for y in range(SIZE):
        for x in range(SIZE):
            dist = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            ring = -14 if int(dist) % 3 == 0 else 6
            d = ring + r.rng(-4, 4)
            px[y][x] = (clamp(base[0] + d), clamp(base[1] + d),
                        clamp(base[2] + d), 255)
    return px


def blades(name, color, height, count=5, width=1):
    """Sprite trávy/kapradí: stébla ode dna nahoru s mírným ohnutím."""
    r = Rnd(name)
    px = blank()
    dark = tuple(clamp(c * 0.72) for c in color) + (255,)
    light = color + (255,)
    for i in range(count):
        x = r.rng(1, SIZE - 2)
        h = r.rng(max(2, height - 3), height)
        lean = r.rng(-1, 1)
        for step in range(h):
            y = SIZE - 1 - step
            bx = x + (lean if step > h // 2 else 0)
            for w in range(width):
                if 0 <= bx + w < SIZE:
                    px[y][bx + w] = light if i % 2 else dark
    return px


def flower(name, stem, petal, cap_w=5):
    """Sprite květiny: stonek + barevná hlavička.

    Stonek MUSÍ růst pod hlavičkou (dřív se kreslil na náhodné x, zatímco
    hlavička seděla ve středu — hlava pak plavala vedle stonku).
    """
    r = Rnd(name)
    px = blank()
    cx = SIZE // 2 + r.rng(-1, 1)
    stem_h = 9
    light = stem + (255,)
    dark = tuple(clamp(c * 0.72) for c in stem) + (255,)

    for step in range(stem_h):
        px[SIZE - 1 - step][cx] = light if step % 2 else dark
    for dy, dx in ((2, -1), (5, 1)):          # dva lístky u země
        if 0 <= cx + dx < SIZE:
            px[SIZE - 1 - dy][cx + dx] = dark

    top = SIZE - stem_h                        # hlavička sedí na stonku
    for dy in range(3):
        w = cap_w - 2 * abs(dy - 1)            # kosočtverec: 1 / 5 / 1
        for dx in range(-(w // 2), w // 2 + 1):
            x, y = cx + dx, top - dy
            if 0 <= x < SIZE and 0 <= y < SIZE:
                px[y][x] = petal + (255,)
    return px


def mushroom(name, cap, dots=None):
    px = blank()
    stem = (222, 214, 196, 255)
    for y in range(SIZE - 6, SIZE - 1):
        for x in range(SIZE // 2 - 1, SIZE // 2 + 1):
            px[y][x] = stem
    for dy in range(4):
        w = 6 - dy
        for dx in range(-w, w + 1):
            x, y = SIZE // 2 + dx, SIZE - 7 - dy
            if 0 <= x < SIZE and 0 <= y < SIZE:
                px[y][x] = cap + (255,)
    if dots:
        speckle(px, name, dots + (255,), 5)
    return px


def flame(name):
    """Plamen: špičatý tvar, uvnitř světlejší."""
    r = Rnd(name)
    px = blank()
    for y in range(SIZE):
        h = SIZE - 1 - y
        w = max(0, int((SIZE - h) * 0.42) - 1)
        for dx in range(-w, w + 1):
            x = SIZE // 2 + dx
            if 0 <= x < SIZE:
                inner = abs(dx) < max(1, w - 1)
                base = (255, 226, 90) if inner else (232, 118, 26)
                d = r.rng(-12, 12)
                px[y][x] = (clamp(base[0] + d), clamp(base[1] + d),
                            clamp(base[2] + d), 255)
    return px


def lily_pad(name, color):
    """Leknín shora: kruh s výřezem."""
    r = Rnd(name)
    px = blank()
    c = (SIZE - 1) / 2
    for y in range(SIZE):
        for x in range(SIZE):
            dist = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if dist <= 7.2 and not (x > c and abs(y - c) < 1.5):
                d = r.rng(-14, 14)
                px[y][x] = (clamp(color[0] + d), clamp(color[1] + d),
                            clamp(color[2] + d), 255)
    return px


def cactus_side(name, base):
    px = noise_tile(name, base, spread=10)
    rib = tuple(clamp(c * 0.78) for c in base) + (255,)
    for y in range(SIZE):
        for x in (3, 11):
            px[y][x] = rib
    return px


# --------------------------------------------------------------------------
# Katalog
# --------------------------------------------------------------------------

SOLID = {
    "stone": ((108, 108, 108), 12),
    "desert_stone": ((167, 90, 60), 12),
    "sandstone": ((196, 180, 130), 10),
    "desert_sandstone": ((185, 120, 80), 10),
    "silver_sandstone": ((198, 198, 204), 10),
    "obsidian": ((26, 22, 32), 8),
    "gravel": ((130, 127, 124), 24),
    "clay": ((172, 174, 180), 8),
    "permafrost": ((86, 86, 96), 10),
    "coral_skeleton": ((222, 222, 214), 10),
    "snowblock": ((238, 243, 250), 6),
    "snow": ((245, 249, 255), 5),
    "sand": ((222, 205, 155), 9),
    "desert_sand": ((215, 175, 120), 9),
    "silver_sand": ((214, 214, 220), 8),
    "dirt": ((110, 80, 55), 12),
    "dry_dirt": ((140, 110, 75), 12),
    "grass_top": ((85, 140, 60), 14),
    "dry_grass_top": ((172, 150, 82), 14),
    "rainforest_litter_top": ((72, 106, 50), 14),
    "lava": ((226, 110, 26), 18),
}

TRANSLUCENT = {
    "ice": ((150, 200, 230), 8, 190),
    "cave_ice": ((170, 215, 235), 8, 190),
    "water": ((52, 108, 190), 10, 190),
    "water_flow": ((62, 118, 198), 14, 190),
    "river_water": ((70, 132, 192), 10, 190),
    "river_water_flow": ((80, 142, 200), 14, 190),
}

TREES = {
    "tree": ((100, 72, 45), (150, 110, 70)),
    "jungletree": ((86, 60, 40), (140, 100, 60)),
    "pine_tree": ((78, 58, 40), (160, 120, 75)),
    "aspen_tree": ((186, 181, 166), (202, 192, 172)),
    "acacia_tree": ((120, 70, 45), (170, 110, 70)),
    "bush_stem": ((95, 70, 45), (140, 105, 68)),
}

LEAVES = {
    "leaves": ((60, 120, 50), None),
    "jungleleaves": ((45, 105, 40), None),
    "pine_needles": ((35, 85, 55), None),
    "aspen_leaves": ((110, 160, 70), None),
    "acacia_leaves": ((95, 135, 55), None),
    "bush_leaves": ((70, 125, 55), None),
    "acacia_bush_leaves": ((100, 130, 60), None),
    "blueberry_leaves": ((70, 120, 55), (70, 90, 190, 255)),
}

PLANTS = {
    "grass_1": ((95, 150, 65), 4), "grass_2": ((95, 150, 65), 6),
    "grass_3": ((95, 150, 65), 8), "grass_4": ((95, 150, 65), 10),
    "grass_5": ((95, 150, 65), 12),
    "dry_grass_1": ((175, 155, 90), 4), "dry_grass_2": ((175, 155, 90), 6),
    "dry_grass_3": ((175, 155, 90), 8), "dry_grass_4": ((175, 155, 90), 10),
    "dry_grass_5": ((175, 155, 90), 12),
    "fern_1": ((70, 130, 60), 7), "fern_2": ((70, 130, 60), 10),
    "fern_3": ((70, 130, 60), 13),
    "marram_grass_1": ((150, 165, 105), 7),
    "marram_grass_2": ((150, 165, 105), 10),
    "marram_grass_3": ((150, 165, 105), 13),
    "junglegrass": ((60, 130, 55), 14),
    "dry_shrub": ((130, 100, 65), 9),
    "papyrus": ((90, 150, 80), 15),
}

FLOWERS = {
    "rose": ((70, 120, 55), (200, 40, 45)),
    "tulip": ((70, 120, 55), (235, 150, 40)),
    "viola": ((70, 120, 55), (130, 70, 190)),
    "geranium": ((70, 120, 55), (75, 90, 220)),
    "dandelion_yellow": ((70, 120, 55), (240, 220, 60)),
    "dandelion_white": ((70, 120, 55), (245, 245, 240)),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    made = 0

    def save(stem, px):
        nonlocal made
        write_png(os.path.join(OUT, "dwn_%s.png" % stem), px)
        made += 1

    for n, (base, spread) in SOLID.items():
        px = noise_tile(n, base, spread, coarse=2 if n == "gravel" else 1)
        if n == "gravel":
            speckle(px, n, (96, 94, 92, 255), 18, 2)
        save(n, px)

    for n, (base, spread, a) in TRANSLUCENT.items():
        save(n, noise_tile(n, base, spread, alpha=a))

    for n, (bark, top) in TREES.items():
        save(n, bark_tile(n, bark))
        save(n + "_top", tree_top_tile(n + "_top", top))

    for n, (base, berry) in LEAVES.items():
        save(n, leaves_tile(n, base, berry))

    for n, (color, h) in PLANTS.items():
        count = 3 if "shrub" in n else (2 if n == "papyrus" else 5)
        save(n, blades(n, color, h, count=count,
                       width=2 if n == "papyrus" else 1))

    for n, (stem, petal) in FLOWERS.items():
        save(n, flower(n, stem, petal))

    save("mushroom_red", mushroom("mushroom_red", (198, 48, 44), (240, 240, 235)))
    save("mushroom_brown", mushroom("mushroom_brown", (150, 110, 72)))
    save("waterlily", lily_pad("waterlily", (68, 128, 58)))
    save("cactus_side", cactus_side("cactus_side", (70, 120, 60)))
    save("cactus_top", noise_tile("cactus_top", (82, 132, 70), 10))
    save("basic_flame", flame("basic_flame"))

    # boční textura zeminy s travním pruhem nahoře se skládá až v Lua
    # přes ^ (overlay), aby se nemusela generovat pro každý typ trávy
    for n, top in (("grass_side", (85, 140, 60)),
                   ("dry_grass_side", (172, 150, 82)),
                   ("litter_side", (72, 106, 50))):
        px = noise_tile(n, (110, 80, 55), 12)
        r = Rnd(n + "edge")
        for x in range(SIZE):
            for y in range(r.rng(2, 4)):
                d = r.rng(-14, 14)
                px[y][x] = (clamp(top[0] + d), clamp(top[1] + d),
                            clamp(top[2] + d), 255)
        save(n, px)

    print("vygenerováno %d textur do %s" % (made, os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
