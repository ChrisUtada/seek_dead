#!/usr/bin/env python3
"""Draw the sword-and-shield player's breathing frames at native 48x48."""
from pathlib import Path
from math import hypot
from PIL import Image, ImageDraw, ImageFont
from redraw_bosses import INK, DEEP, SHADE, MUTED, IVORY, GOLD, GOLD_DARK, ICE_DARK, VIOLET_DARK, CLEAR, isolated_pixels

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "characters" / "viking_ash"
SHEET = ROOT / "docs" / "baseline" / "2026-11-06_player_knight"
SHEET.mkdir(parents=True, exist_ok=True)
STEEL = (115, 122, 132, 255)
STEEL_LIGHT = (190, 194, 190, 255)
CLOTH = (54, 73, 94, 255)


def poly(d, pts, color):
    d.polygon(pts, fill=color)


def box(d, coords, color):
    d.rectangle(coords, fill=color)


def line(d, pts, color, width=1):
    d.line(pts, fill=color, width=width)


def sword(d, hilt, tip):
    hx,hy = hilt
    tx,ty = tip
    length = max(1.0, hypot(tx-hx,ty-hy))
    ux,uy = (tx-hx)/length,(ty-hy)/length
    px,py = -uy,ux
    # Blade, bright ridge and point remain pixel-native Bresenham shapes.
    line(d, [(hx,hy),(tx,ty)], INK, 5)
    line(d, [(hx,hy),(tx,ty)], IVORY, 3)
    line(d, [(hx+round(ux*3),hy+round(uy*3)),(tx,ty)], STEEL_LIGHT, 1)
    # Crossguard and a short two-handed grip.
    g1 = (round(hx-px*5),round(hy-py*5))
    g2 = (round(hx+px*5),round(hy+py*5))
    line(d, [g1,g2], INK, 3)
    line(d, [g1,g2], GOLD, 1)
    pommel = (round(hx-ux*6),round(hy-uy*6))
    line(d, [(hx,hy),pommel], INK, 3)
    line(d, [(hx,hy),pommel], GOLD_DARK, 1)
    box(d, (pommel[0]-1,pommel[1]-1,pommel[0]+1,pommel[1]+1), GOLD_DARK)


def body(d, dx=0, dy=0, stride=0, cape=0):
    def pts(values):
        return [(x+dx,y+dy) for x,y in values]
    # Blue travel cloak, behind the plate armor.
    poly(d, pts([(14,17),(10,21),(9,30),(6,39),(9,44+cape),(14,41),(17,45),(21,39),(22,20)]), INK)
    poly(d, pts([(14,20),(12,29),(9,38),(10,40+cape),(14,38),(17,41),(19,37),(19,21)]), CLOTH)
    poly(d, pts([(13,24),(13,31),(11,36),(14,34),(16,38),(17,24)]), ICE_DARK)
    # Planted greaves and steel sabatons.
    poly(d, pts([(17,31),(23,31),(23,39),(21,46),(14,46),(14,42),(16,37)]), INK)
    poly(d, pts([(24,31),(29,31+stride),(31,39),(33,45),(27,47),(23,44),(25,39)]), INK)
    poly(d, pts([(18,34),(21,34),(21,39),(19,43),(16,43),(17,38)]), STEEL)
    poly(d, pts([(26,34),(28,34+stride),(29,40),(29,43),(27,44),(26,40)]), STEEL)
    box(d, (16+dx,37+dy,22+dx,39+dy), INK)
    box(d, (25+dx,37+dy,30+dx,39+dy), INK)
    poly(d, pts([(14,43),(21,43),(22,46),(13,47),(11,45)]), INK)
    poly(d, pts([(27,43),(32,43),(35,46),(29,47),(24,45)]), INK)
    box(d, (15+dx,43+dy,20+dx,44+dy), STEEL_LIGHT)
    box(d, (28+dx,43+dy,31+dx,44+dy), STEEL_LIGHT)
    # Breastplate and articulated waist.
    poly(d, pts([(16,16),(22,14),(29,17),(32,24),(28,33),(18,33),(13,27),(13,20)]), INK)
    poly(d, pts([(18,18),(22,16),(27,18),(29,24),(26,30),(19,30),(16,26),(15,21)]), STEEL)
    poly(d, pts([(18,18),(23,16),(28,19),(26,22),(20,21),(16,20)]), STEEL_LIGHT)
    poly(d, pts([(18,23),(23,22),(28,23),(26,28),(22,30),(19,27)]), MUTED)
    poly(d, pts([(21,22),(24,22),(24,28),(21,28)]), IVORY)
    box(d, (22+dx,23+dy,23+dx,27+dy), GOLD_DARK)
    box(d, (21+dx,24+dy,24+dx,25+dy), GOLD_DARK)
    box(d, (18+dx,30+dy,28+dx,32+dy), INK)
    box(d, (20+dx,30+dy,26+dx,30+dy), GOLD_DARK)
    # Closed helmet, a narrow visor and a short blue crest.
    poly(d, pts([(16,6),(21,3),(28,4),(32,9),(31,16),(27,20),(19,18),(15,14),(14,9)]), INK)
    poly(d, pts([(18,7),(22,5),(27,6),(29,9),(28,14),(25,17),(19,15),(17,12),(16,9)]), STEEL)
    poly(d, pts([(19,7),(23,5),(28,8),(27,10),(20,9),(16,11),(16,9)]), STEEL_LIGHT)
    poly(d, pts([(16,11),(22,10),(29,11),(28,14),(23,13),(18,15)]), INK)
    box(d, (20+dx,11+dy,27+dx,11+dy), IVORY)
    box(d, (23+dx,7+dy,24+dx,10+dy), MUTED)
    poly(d, pts([(20,4),(21,0),(24,2),(27,1),(28,5),(23,5)]), INK)
    poly(d, pts([(22,4),(22,2),(24,4),(26,3),(26,5)]), CLOTH)
    # Shoulder plates are large continuous shapes, not scattered highlights.
    poly(d, pts([(13,16),(17,14),(20,18),(18,23),(12,24),(9,21)]), INK)
    poly(d, pts([(13,18),(17,16),(18,19),(16,21),(11,22),(11,20)]), STEEL_LIGHT)
    poly(d, pts([(28,16),(33,18),(35,22),(31,25),(27,22)]), INK)
    poly(d, pts([(30,18),(32,19),(33,21),(31,22),(29,20)]), STEEL_LIGHT)


def sword_arm(d, hilt, dx=0, dy=0):
    hx,hy = hilt
    line(d, [(32+dx,22+dy),(34+dx,26+dy),(hx,hy)], INK, 6)
    line(d, [(32+dx,22+dy),(34+dx,26+dy),(hx,hy)], STEEL, 3)
    box(d, (hx-2,hy-2,hx+2,hy+2), INK)
    box(d, (hx-1,hy-1,hx+1,hy+1), STEEL_LIGHT)


def shield(d, dx=0, dy=0):
    def pts(values):
        return [(x+dx,y+dy) for x,y in values]
    # The left forearm disappears behind a large, unmistakable heater shield.
    line(d, [(13+dx,22+dy),(12+dx,29+dy)], INK, 6)
    line(d, [(13+dx,22+dy),(12+dx,29+dy)], STEEL, 3)
    poly(d, pts([(5,21),(13,18),(20,21),(20,30),(15,37),(10,40),(5,35),(3,27)]), INK)
    poly(d, pts([(7,23),(13,21),(17,23),(17,29),(13,34),(10,37),(7,33),(6,27)]), STEEL_LIGHT)
    poly(d, pts([(9,24),(13,22),(16,24),(16,29),(12,34),(10,35),(9,32)]), ICE_DARK)
    line(d, pts([(13,23),(13,33)]), IVORY, 2)
    line(d, pts([(9,27),(16,27)]), IVORY, 2)


def knight(pose):
    im = Image.new("RGBA", (48,48), CLEAR)
    d = ImageDraw.Draw(im)
    # Every frame uses the same sword-and-shield pose; only breathing changes height.
    breath = int(pose[-1]) % 2
    body(d, 0, breath, 0, breath)
    hilt,tip = (28,23+breath),(42,3+breath)
    sword(d, hilt, tip)
    sword_arm(d, hilt, 0, breath)
    shield(d, 0, breath)
    singles = isolated_pixels(im)
    if singles:
        raise RuntimeError(f"{pose}: isolated pixels {singles}")
    return im


def main():
    names = [f"idle_0{i}" for i in range(1,5)] + [f"attack_0{i}" for i in range(1,6)]
    images = {}
    for name in names:
        im = knight(name)
        im.save(OUT / f"{name}.png")
        images[name] = im
        print(name, "48x48 RGBA, no isolated pixels")
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 12)
    sheet = Image.new("RGBA", (3*176,3*190+34), (22,13,19,255))
    d = ImageDraw.Draw(sheet)
    d.text((10,8), "PLAYER KNIGHT / 48x48 / PREVIEW 3x", fill=IVORY, font=font)
    for i,(name,im) in enumerate(images.items()):
        x,y = (i%3)*176,34+(i//3)*190
        d.rectangle((x+4,y+4,x+171,y+185), outline=(100,77,72,255))
        sheet.alpha_composite(im.resize((144,144), Image.Resampling.NEAREST), (x+16,y+8))
        d.text((x+50,y+158), name, fill=IVORY, font=font)
    sheet.save(SHEET / "player_contact_sheet.png")
    print("sheet:", SHEET / "player_contact_sheet.png")


if __name__ == "__main__":
    main()
