#!/usr/bin/env python3
"""Redraw the brittle gargoyle with a readable stone face, preserving the 96px binding."""
from pathlib import Path
from shutil import copyfile
from PIL import Image, ImageDraw, ImageFont
from redraw_bosses import CLEAR, INK, IVORY, isolated_pixels

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "assets" / "characters" / "brittle_gargoyle" / "idle_01.png"
OUT = ROOT / "docs" / "baseline" / "2026-11-09_gargoyle_face"
OUT.mkdir(parents=True, exist_ok=True)

OUTLINE = (20, 20, 27, 255)
WING = (38, 39, 50, 255)
WING_LIGHT = (57, 59, 71, 255)
STONE_DARK = (57, 62, 67, 255)
STONE = (113, 122, 124, 255)
STONE_LIGHT = (177, 187, 181, 255)
STONE_PALE = (211, 216, 200, 255)
ICE_DARK = (36, 87, 94, 255)
ICE = (72, 177, 181, 255)
ICE_LIGHT = (157, 229, 217, 255)


def poly(d, pts, color):
    d.polygon(pts, fill=color)


def box(d, coords, color):
    d.rectangle(coords, fill=color)


def line(d, pts, color, width=1):
    d.line(pts, fill=color, width=width)


def draw():
    im = Image.new("RGBA", (48, 48), CLEAR)
    d = ImageDraw.Draw(im)
    # Large bat wings: continuous frame and broad membrane panels.
    poly(d, [(20,17),(15,10),(8,3),(3,2),(5,10),(1,16),(5,22),(2,30),(10,28),(15,35),(22,29)], OUTLINE)
    poly(d, [(28,17),(33,10),(40,3),(45,2),(43,10),(47,16),(43,22),(46,30),(38,28),(33,35),(26,29)], OUTLINE)
    poly(d, [(19,18),(14,12),(7,6),(8,12),(4,16),(8,20),(6,26),(12,24),(17,30),(21,26)], WING)
    poly(d, [(29,18),(34,12),(41,6),(40,12),(44,16),(40,20),(42,26),(36,24),(31,30),(27,26)], WING)
    poly(d, [(16,14),(9,7),(11,15),(7,17),(14,20),(19,24)], WING_LIGHT)
    poly(d, [(32,14),(39,7),(37,15),(41,17),(34,20),(29,24)], WING_LIGHT)
    # Wing fingers and stone chips are deliberate large lines, not noise.
    line(d, [(8,5),(12,16),(18,26)], OUTLINE, 2)
    line(d, [(40,5),(36,16),(30,26)], OUTLINE, 2)
    line(d, [(3,17),(11,21),(17,28)], STONE_DARK, 2)
    line(d, [(45,17),(37,21),(31,28)], STONE_DARK, 2)
    poly(d, [(12,21),(16,22),(17,25),(13,25)], ICE_DARK)
    poly(d, [(36,21),(32,22),(31,25),(35,25)], ICE_DARK)
    # Haunches, torso and clawed limbs.
    poly(d, [(17,19),(22,16),(28,18),(33,24),(32,33),(37,38),(35,45),(28,46),(24,41),(20,46),(12,45),(11,38),(16,32),(14,25)], OUTLINE)
    poly(d, [(19,21),(23,18),(27,20),(30,25),(29,33),(33,38),(31,42),(27,42),(24,37),(20,42),(15,41),(14,37),(18,31),(17,25)], STONE_DARK)
    poly(d, [(20,20),(25,19),(29,23),(28,30),(24,35),(19,31),(18,25)], STONE)
    poly(d, [(20,21),(24,20),(25,26),(21,29),(19,26)], STONE_LIGHT)
    poly(d, [(16,24),(12,23),(8,27),(7,35),(3,38),(4,42),(10,40),(12,34),(17,30)], OUTLINE)
    poly(d, [(32,24),(36,23),(40,27),(41,35),(45,38),(44,42),(38,40),(36,34),(31,30)], OUTLINE)
    poly(d, [(13,26),(11,28),(10,34),(7,37),(10,37),(13,31),(16,28)], STONE)
    poly(d, [(35,26),(37,28),(38,34),(41,37),(38,37),(35,31),(32,28)], STONE)
    poly(d, [(14,35),(21,35),(22,41),(19,45),(11,45),(10,42)], OUTLINE)
    poly(d, [(27,35),(33,35),(38,42),(35,45),(28,45),(25,41)], OUTLINE)
    poly(d, [(16,37),(20,37),(19,41),(15,42),(13,41)], STONE)
    poly(d, [(28,37),(31,37),(34,41),(32,42),(28,42)], STONE)
    line(d, [(11,44),(17,44)], STONE_LIGHT, 1)
    line(d, [(31,44),(36,44)], STONE_LIGHT, 1)
    # Core cracks stay on the torso, leaving the face clean.
    poly(d, [(23,22),(26,24),(24,27),(27,30),(24,34),(21,31),(22,27),(20,25)], OUTLINE)
    poly(d, [(23,24),(25,25),(23,28),(25,30),(23,32),(22,30),(23,28),(21,26)], ICE)
    box(d, (23,26,24,28), ICE_LIGHT)
    line(d, [(27,22),(29,25),(28,28)], ICE_DARK, 1)
    line(d, [(20,30),(17,32),(18,35)], ICE_DARK, 1)
    # Horned head with a separate brow, eyes, nose, cheeks and jaw.
    poly(d, [(16,8),(14,2),(19,5),(22,2),(25,4),(31,2),(32,9),(35,14),(31,22),(26,25),(19,23),(14,18),(13,12)], OUTLINE)
    poly(d, [(18,9),(16,5),(20,8),(22,5),(25,7),(29,5),(29,10),(32,14),(29,20),(25,22),(19,20),(16,17),(15,12)], STONE)
    # Broad pale face planes give the features a stable silhouette at 2x.
    poly(d, [(18,10),(22,7),(27,8),(30,11),(29,17),(26,21),(20,20),(17,16)], STONE_LIGHT)
    poly(d, [(19,10),(22,8),(26,9),(28,11),(24,11),(20,12)], STONE_PALE)
    poly(d, [(17,12),(21,11),(23,13),(21,15),(17,15)], STONE_DARK)
    poly(d, [(25,12),(29,11),(31,13),(30,15),(26,15)], STONE_DARK)
    # Eyes are isolated from cracks and large enough to survive in-game scaling.
    box(d, (19,12,21,14), ICE_LIGHT)
    box(d, (27,12,29,14), ICE_LIGHT)
    box(d, (20,13,21,14), OUTLINE)
    box(d, (27,13,28,14), OUTLINE)
    # Nose bridge and angular cheekbones.
    poly(d, [(23,12),(25,12),(26,16),(24,18),(22,16)], STONE_PALE)
    poly(d, [(18,15),(21,16),(22,18),(19,18),(17,16)], STONE)
    poly(d, [(27,15),(30,15),(30,17),(27,19),(25,18)], STONE)
    # Mouth, stone lip and two large fangs read as a gargoyle rather than a blank mask.
    poly(d, [(19,18),(23,17),(28,18),(29,20),(25,22),(20,21)], OUTLINE)
    box(d, (21,18,26,18), STONE_DARK)
    poly(d, [(20,18),(22,18),(22,21),(20,20)], IVORY)
    poly(d, [(26,18),(28,18),(27,21),(26,20)], IVORY)
    box(d, (23,20,25,21), STONE_LIGHT)
    # Brow cracks stop at the forehead and never cross the eyes.
    line(d, [(22,7),(23,9),(22,10)], STONE_DARK, 1)
    line(d, [(29,7),(28,9)], STONE_DARK, 1)
    singles = isolated_pixels(im)
    if singles:
        raise RuntimeError(f"isolated pixels: {singles}")
    return im.resize((96,96), Image.Resampling.NEAREST)


def main():
    before = OUT / "before.png"
    if TARGET.exists() and not before.exists():
        copyfile(TARGET, before)
    after = draw()
    after.save(TARGET)
    preview = Image.new("RGBA", (600,340), (22,13,19,255))
    d = ImageDraw.Draw(preview)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    d.text((16,10), "BRITTLE GARGOYLE / FACE REDRAW", fill=IVORY, font=font)
    if before.exists():
        old = Image.open(before).convert("RGBA").resize((288,288), Image.Resampling.NEAREST)
        preview.alpha_composite(old, (8,42))
    preview.alpha_composite(after.resize((288,288), Image.Resampling.NEAREST), (304,42))
    d.text((108,316), "BEFORE", fill=IVORY, font=font)
    d.text((426,316), "AFTER", fill=IVORY, font=font)
    preview.save(OUT / "gargoyle_face_comparison.png")
    print("saved:", TARGET, after.size, after.mode)
    print("preview:", OUT / "gargoyle_face_comparison.png")


if __name__ == "__main__":
    main()
