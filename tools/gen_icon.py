#!/usr/bin/env python3
"""Generátor ikony hry pro menu/icon.png.

Ikona se kreslí, nevyřezává ze screenshotu: v 96x96 je z výřezu herního
záběru nečitelná změť a hráč ji v přepínači her nepozná. Tohle drží tři
velké čitelné tvary — obloha, dva létající ostrovy, silueta stroje.

Použití:  python3 tools/gen_icon.py menu/icon.png
"""
import sys
import zlib
import struct
import math
N = 96

def px_blank(c): return [[c for _ in range(N)] for _ in range(N)]

sky_top, sky_bot = (86, 152, 214), (150, 198, 236)
img = px_blank((0,0,0,255))
for y in range(N):
    t = y / (N - 1)
    img[y] = [(int(sky_top[0]+(sky_bot[0]-sky_top[0])*t),
               int(sky_top[1]+(sky_bot[1]-sky_top[1])*t),
               int(sky_top[2]+(sky_bot[2]-sky_top[2])*t), 255)] * N

def blob(cx, cy, rx, ry_up, ry_dn, top, side):
    for y in range(N):
        for x in range(N):
            dx = (x - cx) / rx
            if abs(dx) > 1: continue
            w = math.sqrt(max(0.0, 1 - dx*dx))
            ytop = cy - ry_up * w
            ybot = cy + ry_dn * (w ** 0.55)
            if ytop <= y <= ybot:
                img[y][x] = top if y < ytop + 4 else side

# dva ostrovy: maly vzadu, velky vpredu (hloubka)
blob(70, 40, 16, 4, 12, (96,150,74,255), (120,92,62,255))
blob(38, 62, 27, 6, 22, (108,168,80,255), (134,102,68,255))

# stihacka silueta - sipka smerem doprava nahoru
plane = [
    "............XX..........",
    "..........XXXX..........",
    ".........XXXXXX.........",
    "........XXXXXXXX........",
    "XXXXXXXXXXXXXXXXXXXXXXXX",
    "XXXXXXXXXXXXXXXXXXXXXXXX",
    "........XXXXXXXX........",
    "..........XXXX..........",
    "........XX....XX........",
    ".......XX......XX.......",
]
PW, PH, SC = len(plane[0]), len(plane), 2
ox, oy = 26, 14
dark, hi = (28, 34, 46, 255), (238, 242, 250, 255)
for j, row in enumerate(plane):
    for i, ch in enumerate(row):
        if ch != "X": continue
        for sy in range(SC):
            for sx in range(SC):
                x, y = ox + i*SC + sx, oy + j*SC + sy
                if 0 <= x < N and 0 <= y < N:
                    img[y][x] = hi if j < 2 or (j == 4 and i > PW-6) else dark

raw = b"".join(b"\x00"+bytes(v for p in row for v in p) for row in img)
def ch(t,d): return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
open(sys.argv[1],"wb").write(b"\x89PNG\r\n\x1a\n"
    + ch(b"IHDR", struct.pack(">IIBBBBB",N,N,8,6,0,0,0))
    + ch(b"IDAT", zlib.compress(raw,9)) + ch(b"IEND", b""))
print("ok")
