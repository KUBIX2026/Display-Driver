#!/usr/bin/env python3
"""Modelo de referencia (independiente del RTL) del compositor, según la
especificación (03 - Especificación, sec. 7): fondo -> texto -> sprites del
slot 15 al 0, recorte, transparencia 0x0843, coordenadas con signo de 8 bits.
Imprime el cuadro como W/Y/. igual que sim/tb_spec_rules.v (pwm_level=1)."""
import sys
TRANSPARENT = 0x0843

def hexw(path, bits=16):
    return [int(l, 16) for l in open(path).read().split()]

sprites = hexw("assets/sprites.hex")
meta    = hexw("assets/sprite_meta.hex")
font    = hexw("assets/font8x8.hex")
bg      = hexw("assets/backgrounds.hex")

def s8(v): return v - 256 if v >= 128 else v

# escena (misma que tb_spec_rules.v) -----------------------------------------
bg_id = 0
text  = {0: (0x50, 0xFFFF)}                       # celda -> (char, color)
slots = {1:(1,4,24), 0:(2,4,24), 2:(1,-2,10), 3:(2,20,-2), 4:(2,62,62),
         5:(2,70,10), 7:(1,30,38), 6:(3,30,40), 9:(2,2,2)}   # el 8 se ocultó

fb = [bg[bg_id*4096 + i] for i in range(4096)]
for cell,(ch,col) in text.items():
    cx, cy = (cell & 7)*8, (cell >> 3)*8
    for r in range(8):
        row = font[ch*8 + r]
        for c in range(8):
            if row & (0x80 >> c):
                fb[(cy+r)*64 + cx+c] = col
for slot in range(15, -1, -1):
    if slot not in slots: continue
    sid, x, y = slots[slot]
    m = meta[sid]; h, w, base = (m >> 24) & 0xFF, (m >> 16) & 0xFF, m & 0x1FFF
    for j in range(h):
        for i in range(w):
            p = sprites[base + j*w + i]
            if p == TRANSPARENT: continue
            sx, sy = x+i, y+j
            if 0 <= sx < 64 and 0 <= sy < 64:
                fb[sy*64+sx] = p

def lit(p, level=1):             # panel_pwm: canal encendido si valor5 > nivel
    r, g, b = (p >> 11) & 31, (p >> 6) & 31, p & 31
    return r > level, g > level, b > level
out = []
for y in range(64):
    s = ""
    for x in range(64):
        r, g, b = lit(fb[y*64+x])
        s += "W" if (r and g and b) else "Y" if (r and g) else "?" if (r or g or b) else "."
    out.append(s)
print("\n".join(out))
