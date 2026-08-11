#!/usr/bin/env python3
"""Generátor HUD textur pro umělý horizont.

Luanti neumí HUD prvek otočit, takže nakloněná čára se skládá z několika
malých dílků rozmístěných po přímce — proto je "pip" tak malý. Referenční
značka letadla je jeden pevný obrázek uprostřed.

Bílé se generuje schválně: barvu si HUD dobarví přes ^[colorize, takže
jedna textura obslouží víc barevných variant.

Použití:  python3 tools/gen_hud.py
Výstup:   mods/doggiowars/textures/doggiowars_hud_*.png
"""
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..",
                   "mods", "doggiowars", "textures")
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def write_png(path, px):
    h, w = len(px), len(px[0])
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in px)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


def rect(w, h, fill=WHITE):
    return [[fill for _ in range(w)] for _ in range(h)]


def main():
    os.makedirs(OUT, exist_ok=True)

    # dílek horizontu — plný obdélníček
    write_png(os.path.join(OUT, "doggiowars_hud_pip.png"), rect(6, 2))

    # referenční značka letadla: [——   ·   ——]
    # Uprostřed mezera, ať je vidět, kudy prochází čára horizontu.
    W, H = 31, 7
    px = rect(W, H, CLEAR)
    mid = H // 2
    for x in list(range(0, 11)) + list(range(20, W)):   # křídla
        px[mid][x] = WHITE
        px[mid + 1][x] = WHITE
    for x in (0, 1, W - 2, W - 1):                       # koncové patky dolů
        for y in range(mid, mid + 4):
            px[y][x] = WHITE
    for y in range(mid - 1, mid + 2):                    # střed
        for x in range(W // 2 - 1, W // 2 + 2):
            px[y][x] = WHITE
    write_png(os.path.join(OUT, "doggiowars_hud_ref.png"), px)

    print("vygenerovany doggiowars_hud_pip.png a doggiowars_hud_ref.png")


if __name__ == "__main__":
    main()
