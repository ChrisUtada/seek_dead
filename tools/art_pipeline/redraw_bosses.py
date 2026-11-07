#!/usr/bin/env python3
"""Draw the ten remaining bosses at native 48x48, without procedural noise."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "characters"
SHEET = ROOT / "docs" / "baseline" / "2026-11-05_boss_redraw"
SHEET.mkdir(parents=True, exist_ok=True)
CLEAR = (0, 0, 0, 0)
INK = (35, 20, 30, 255)
DEEP = (66, 31, 43, 255)
SHADE = (108, 44, 54, 255)
RED = (174, 65, 69, 255)
LIGHT = (224, 94, 82, 255)
PALE = (255, 145, 113, 255)
IVORY = (226, 215, 189, 255)
MUTED = (156, 145, 137, 255)
GOLD = (215, 166, 66, 255)
GOLD_DARK = (126, 86, 43, 255)
ICE = (102, 172, 196, 255)
ICE_DARK = (52, 91, 121, 255)
POISON = (166, 190, 76, 255)
POISON_DARK = (85, 112, 48, 255)
VIOLET = (154, 112, 174, 255)
VIOLET_DARK = (83, 56, 103, 255)


def poly(d, pts, color):
    d.polygon(pts, fill=color)


def box(d, coords, color):
    d.rectangle(coords, fill=color)


def line(d, pts, color, width=1):
    d.line(pts, fill=color, width=width)


def acid_ghoul(im):
    d = ImageDraw.Draw(im)
    # Back, hunched neck and asymmetric arms.
    poly(d, [(13,13),(19,7),(28,8),(33,15),(31,22),(36,25),(39,36),(35,42),(29,43),(14,42),(9,36),(11,25),(8,19)], INK)
    poly(d, [(15,14),(20,10),(27,11),(30,16),(28,23),(34,27),(36,35),(32,39),(15,39),(12,34),(14,25),(11,19)], RED)
    poly(d, [(12,23),(7,21),(4,25),(4,35),(7,42),(12,42),(15,35),(15,27)], INK)
    poly(d, [(10,24),(7,24),(6,27),(7,34),(9,38),(11,36),(12,29)], SHADE)
    poly(d, [(6,39),(5,45),(8,43),(10,46),(12,40)], INK)
    poly(d, [(32,23),(38,22),(43,27),(42,35),(38,39),(34,36),(37,31),(34,29)], INK)
    poly(d, [(35,25),(39,25),(40,29),(39,33),(37,34),(38,29),(34,28)], LIGHT)
    # Face: brow, cheeks, nose and a separate jaw keep the expression readable.
    poly(d, [(15,9),(19,4),(27,5),(32,10),(30,19),(26,23),(17,21),(12,16)], INK)
    poly(d, [(17,10),(21,7),(26,8),(29,11),(27,17),(24,20),(17,18),(15,15)], LIGHT)
    poly(d, [(16,10),(22,7),(28,10),(27,13),(20,12),(17,15),(14,14)], SHADE)
    box(d, (17,12,20,14), IVORY); box(d, (25,12,27,14), IVORY)
    box(d, (18,13,19,14), INK); box(d, (25,13,26,14), INK)
    poly(d, [(21,14),(24,14),(25,17),(20,17)], SHADE)
    box(d, (18,18,26,20), INK)
    for x in (19,22,25): box(d, (x,18,x,19), IVORY)
    # Acid reservoir: a designed, continuous shape rather than pixel speckle.
    poly(d, [(18,24),(25,22),(31,25),(33,32),(29,39),(20,40),(15,34),(15,28)], INK)
    poly(d, [(19,26),(25,25),(29,27),(30,32),(27,36),(21,37),(18,33),(18,28)], POISON_DARK)
    poly(d, [(20,27),(25,26),(28,28),(28,31),(23,30),(20,33),(19,30)], POISON)
    box(d, (21,27,25,28), IVORY)
    poly(d, [(23,36),(28,35),(28,42),(25,44),(23,41)], POISON)
    poly(d, [(16,37),(21,39),(20,45),(13,45),(12,42)], INK)
    poly(d, [(29,39),(34,38),(36,44),(29,45),(27,42)], INK)
    box(d, (15,42,19,43), SHADE); box(d, (30,41,33,42), SHADE)


def brittle_gargoyle(im):
    d = ImageDraw.Draw(im)
    # Broad stone wings, with three large membrane panels on each side.
    poly(d, [(20,16),(14,9),(5,5),(7,13),(2,18),(7,26),(4,33),(15,29),(21,35)], INK)
    poly(d, [(28,16),(34,9),(43,5),(41,13),(46,18),(41,26),(44,33),(33,29),(27,35)], INK)
    poly(d, [(18,18),(13,12),(8,9),(10,15),(6,19),(10,23),(8,28),(16,25),(20,30)], SHADE)
    poly(d, [(30,18),(35,12),(40,9),(38,15),(42,19),(38,23),(40,28),(32,25),(28,30)], SHADE)
    poly(d, [(16,16),(10,12),(12,19),(8,21),(16,22)], RED)
    poly(d, [(32,16),(38,12),(36,19),(40,21),(32,22)], RED)
    line(d, [(15,14),(17,25),(10,27)], LIGHT, 2)
    line(d, [(33,14),(31,25),(38,27)], LIGHT, 2)
    # Crouching stone torso and haunches.
    poly(d, [(17,18),(21,14),(28,15),(32,21),(31,29),(36,34),(34,43),(27,45),(22,42),(17,45),(11,41),(12,33),(16,28)], INK)
    poly(d, [(19,20),(22,17),(27,18),(29,22),(28,30),(32,34),(31,39),(26,41),(22,38),(17,41),(14,38),(15,33),(19,29)], RED)
    poly(d, [(15,31),(21,31),(21,38),(17,42),(12,40)], SHADE)
    poly(d, [(28,30),(34,33),(35,39),(31,42),(26,40)], SHADE)
    box(d, (13,40,20,43), INK); box(d, (28,40,36,43), INK)
    # Horned gargoyle face, muzzle and brow.
    poly(d, [(16,13),(14,5),(19,9),(22,4),(26,8),(32,5),(30,14),(32,18),(27,24),(19,23),(14,18)], INK)
    poly(d, [(18,13),(17,9),(21,11),(23,7),(25,11),(29,9),(28,14),(29,17),(26,21),(19,20),(17,17)], LIGHT)
    poly(d, [(17,13),(22,11),(28,13),(27,16),(23,15),(18,17)], SHADE)
    box(d, (18,14,21,16), ICE); box(d, (25,14,28,16), ICE)
    box(d, (20,15,21,16), INK); box(d, (25,15,26,16), INK)
    poly(d, [(20,18),(26,18),(27,20),(24,22),(20,21)], SHADE)
    box(d, (21,19,25,19), INK)
    # Two deliberate fracture paths and one exposed ice-blue core.
    poly(d, [(23,23),(26,24),(24,28),(27,31),(24,35),(25,39),(21,36),(22,32),(20,29)], INK)
    poly(d, [(23,25),(24,26),(22,29),(25,31),(23,33),(23,36),(22,34),(23,31),(21,29)], ICE)
    line(d, [(18,24),(20,27),(17,30)], DEEP, 2)
    line(d, [(29,23),(27,26),(30,28)], DEEP, 2)
    poly(d, [(18,34),(22,36),(20,40),(16,39)], LIGHT)


def abyss_watcher(im):
    d = ImageDraw.Draw(im)
    # Six rooted tentacles establish the abyssal silhouette.
    for pts in [
        [(16,30),(12,34),(8,36),(6,44),(11,46),(14,40),(20,37)],
        [(20,33),(17,39),(18,47),(23,46),(22,41),(26,35)],
        [(29,33),(28,40),(32,47),(37,45),(33,40),(34,34)],
        [(34,29),(38,33),(42,35),(45,42),(40,45),(37,39),(31,36)],
        [(13,23),(8,25),(3,31),(5,36),(9,31),(16,30)],
        [(36,22),(42,24),(46,31),(43,36),(40,30),(33,29)],
    ]:
        poly(d, pts, INK)
    poly(d, [(14,32),(10,37),(9,42),(11,43),(14,37),(18,35)], VIOLET_DARK)
    poly(d, [(21,36),(20,42),(21,44),(22,40),(25,35)], SHADE)
    poly(d, [(32,36),(31,41),(34,44),(32,39),(33,35)], VIOLET_DARK)
    poly(d, [(37,33),(41,37),(42,41),(40,41),(38,37),(34,35)], SHADE)
    # Cranial mantle and thick eyelids surround a single unmistakable eye.
    poly(d, [(14,10),(21,4),(31,5),(38,12),(41,22),(36,32),(27,37),(16,33),(8,25),(8,17)], INK)
    poly(d, [(16,11),(22,7),(30,8),(35,13),(38,22),(33,29),(26,33),(17,30),(11,24),(11,17)], RED)
    poly(d, [(16,10),(22,6),(29,7),(33,11),(29,12),(21,11),(15,15),(11,18),(12,13)], LIGHT)
    poly(d, [(11,19),(17,14),(27,13),(36,18),(37,24),(30,30),(19,29),(11,24)], DEEP)
    poly(d, [(13,20),(20,16),(28,16),(35,20),(31,26),(21,27),(15,24)], IVORY)
    poly(d, [(20,16),(28,16),(31,20),(29,25),(23,27),(19,23)], VIOLET)
    box(d, (22,18,27,24), INK); box(d, (23,18,25,21), PALE)
    poly(d, [(12,18),(19,13),(29,13),(36,18),(32,17),(25,16),(18,18)], SHADE)
    poly(d, [(14,26),(21,29),(29,28),(34,24),(30,30),(22,33),(16,30)], SHADE)
    # A connected crown of abyssal spines, not floating particles.
    poly(d, [(13,12),(10,5),(17,9),(18,2),(23,7),(29,1),(31,8),(38,5),(35,13),(29,9),(21,9)], INK)
    poly(d, [(17,9),(18,5),(21,9),(28,4),(29,9)], VIOLET_DARK)


def hero_shadow(im):
    d = ImageDraw.Draw(im)
    # A bowed knight with a torn cape and an empty off-hand; no crown or shield.
    poly(d, [(15,16),(11,20),(10,29),(7,36),(5,44),(11,42),(13,47),(18,43),(22,46),(25,38),(25,20)], INK)
    poly(d, [(15,20),(13,29),(10,36),(8,41),(12,39),(14,43),(17,39),(20,42),(22,36),(22,21)], VIOLET_DARK)
    poly(d, [(14,24),(13,33),(11,37),(14,35),(16,39),(18,35),(19,23)], DEEP)
    line(d, [(12,28),(16,31),(13,36)], SHADE, 2)
    # Slumped gorget and full breastplate, broad at the shoulders and narrow at the waist.
    poly(d, [(17,15),(23,13),(30,17),(32,25),(28,33),(19,33),(14,27),(14,20)], INK)
    poly(d, [(18,18),(23,16),(28,19),(29,25),(26,30),(20,30),(17,26),(16,21)], MUTED)
    poly(d, [(19,18),(23,17),(27,19),(25,22),(20,22),(17,20)], IVORY)
    poly(d, [(18,23),(23,22),(28,23),(26,28),(22,30),(19,27)], (115,112,119,255))
    poly(d, [(22,22),(25,23),(23,26),(25,28),(22,30),(21,27),(22,25),(20,24)], VIOLET_DARK)
    box(d, (19,30,27,32), INK)
    box(d, (20,30,26,30), GOLD_DARK)
    # Closed, slightly bowed helm with one narrow visor, not a face with round eyes.
    poly(d, [(17,5),(22,2),(28,4),(32,9),(30,17),(26,20),(19,18),(15,13),(15,8)], INK)
    poly(d, [(19,6),(23,4),(27,6),(29,9),(28,14),(25,17),(19,15),(17,12),(17,8)], MUTED)
    poly(d, [(20,6),(24,5),(28,8),(27,10),(20,9),(17,11),(17,8)], IVORY)
    poly(d, [(17,11),(22,10),(29,11),(28,14),(23,13),(18,15)], INK)
    box(d, (20,11,27,11), VIOLET)
    poly(d, [(22,14),(27,14),(25,17),(21,16)], (115,112,119,255))
    box(d, (23,7,24,10), MUTED)
    # Heavy pauldrons hang lower on the left, reinforcing the weary posture.
    poly(d, [(13,16),(17,14),(20,18),(18,23),(12,24),(9,21)], INK)
    poly(d, [(13,18),(17,16),(18,19),(16,21),(11,22),(11,20)], MUTED)
    poly(d, [(28,16),(33,18),(35,22),(31,25),(27,22)], INK)
    poly(d, [(30,18),(32,19),(33,21),(31,22),(29,20)], MUTED)
    # Left arm hangs open and empty.
    poly(d, [(12,22),(17,23),(17,30),(14,36),(10,35),(9,31)], INK)
    poly(d, [(13,24),(15,25),(14,30),(12,33),(11,31)], (115,112,119,255))
    poly(d, [(10,33),(14,33),(14,38),(11,40),(8,37)], INK)
    box(d, (10,35,12,37), MUTED)
    # Right gauntlet supports a longsword held point-down beside the body.
    poly(d, [(29,23),(34,24),(35,30),(32,34),(28,31)], INK)
    poly(d, [(31,25),(33,26),(33,29),(31,31),(30,29)], MUTED)
    poly(d, [(29,30),(34,30),(35,34),(31,36),(28,33)], INK)
    box(d, (30,31,33,33), MUTED)
    poly(d, [(32,32),(35,31),(45,44),(46,47),(42,45),(33,36)], INK)
    poly(d, [(34,33),(35,33),(44,44),(43,44),(35,36)], IVORY)
    poly(d, [(35,36),(42,44),(40,42),(34,35)], MUTED)
    poly(d, [(29,32),(36,29),(38,31),(31,35)], INK)
    poly(d, [(30,32),(36,30),(36,31),(31,34)], GOLD_DARK)
    box(d, (30,34,33,38), INK)
    # Full greaves and sabatons, slightly uneven rather than a heroic wide stance.
    poly(d, [(18,32),(23,32),(23,40),(21,46),(15,46),(15,42),(17,38)], INK)
    poly(d, [(24,32),(28,31),(30,39),(31,45),(26,47),(23,44),(25,39)], INK)
    poly(d, [(19,34),(21,34),(21,40),(19,43),(17,43),(18,38)], MUTED)
    poly(d, [(25,34),(27,34),(28,40),(28,43),(26,44),(25,40)], (115,112,119,255))
    box(d, (17,37,22,39), INK); box(d, (24,37,29,39), INK)
    poly(d, [(15,43),(21,43),(22,46),(14,47),(12,45)], INK)
    poly(d, [(26,43),(31,43),(33,46),(28,47),(24,45)], INK)
    box(d, (16,43,20,44), MUTED); box(d, (27,43,30,44), MUTED)


def manic_elementalist(im):
    d = ImageDraw.Draw(im)
    # Split mantle and robe: warm flame on the left, hard ice on the right.
    poly(d, [(16,13),(20,8),(29,8),(34,15),(33,23),(39,31),(37,44),(27,46),(23,42),(18,46),(9,43),(11,30),(15,23)], INK)
    poly(d, [(17,16),(22,12),(23,40),(18,42),(12,40),(14,30),(18,23)], RED)
    poly(d, [(25,12),(31,16),(30,23),(35,31),(34,41),(27,43),(24,39),(25,25)], ICE_DARK)
    poly(d, [(14,28),(21,24),(22,31),(18,35),(20,39),(14,38)], SHADE)
    poly(d, [(26,25),(31,28),(34,37),(29,35),(27,40),(25,34)], ICE)
    poly(d, [(19,8),(22,3),(28,4),(33,10),(31,20),(26,24),(18,20),(15,14)], INK)
    poly(d, [(20,10),(23,7),(27,7),(30,11),(28,18),(25,20),(19,17),(18,14)], SHADE)
    poly(d, [(20,11),(23,9),(27,10),(28,14),(25,17),(20,16)], DEEP)
    box(d, (20,12,22,14), GOLD); box(d, (25,12,27,14), ICE)
    box(d, (23,16,26,17), PALE)
    # Raised hands physically connect to two large elemental manifestations.
    poly(d, [(15,21),(10,20),(7,15),(4,17),(6,25),(13,29),(18,27)], INK)
    poly(d, [(32,21),(37,18),(40,13),(43,15),(41,24),(34,29),(30,27)], INK)
    box(d, (5,16,9,20), LIGHT); box(d, (38,14,42,18), ICE)
    poly(d, [(7,16),(2,12),(4,8),(3,3),(8,7),(10,2),(12,8),(16,6),(14,13),(10,17)], INK)
    poly(d, [(7,13),(5,11),(6,7),(9,10),(10,6),(12,11),(10,14)], GOLD)
    poly(d, [(8,12),(8,9),(11,11),(10,14)], IVORY)
    poly(d, [(39,15),(35,11),(37,5),(41,7),(43,1),(46,8),(44,14),(42,17)], INK)
    poly(d, [(40,12),(38,10),(39,7),(41,10),(43,5),(43,11)], ICE)
    poly(d, [(41,9),(43,6),(43,10)], IVORY)
    # Central unstable seam and broad belt.
    poly(d, [(23,22),(26,23),(24,28),(27,32),(24,38),(22,34),(24,30),(21,27)], INK)
    box(d, (16,28,31,30), GOLD_DARK)
    box(d, (22,28,25,30), GOLD)


def maze_whisperer(im):
    d = ImageDraw.Draw(im)
    # A towering, root-like silhouette: no human hands, boots or round hood.
    poly(d, [(14,16),(9,17),(5,23),(5,31),(1,38),(4,43),(9,37),(11,29),(17,25)], INK)
    poly(d, [(33,15),(39,17),(42,24),(41,31),(47,37),(44,44),(38,38),(37,30),(30,25)], INK)
    poly(d, [(15,21),(11,26),(10,35),(5,40),(7,33),(7,26),(11,21)], SHADE)
    poly(d, [(32,20),(37,23),(39,31),(43,37),(44,40),(40,37),(36,34),(35,26)], VIOLET_DARK)
    # Branching fingers read as claws and maze roots rather than mitten hands.
    poly(d, [(5,29),(1,27),(2,34),(0,36),(3,37),(6,33)], INK)
    poly(d, [(41,28),(46,25),(45,32),(48,34),(45,37),(41,34)], INK)
    # Narrow trunk splits into uneven hanging tendrils.
    poly(d, [(16,17),(21,14),(29,16),(34,23),(31,31),(33,39),(30,47),(25,42),(22,47),(18,43),(13,46),(14,37),(11,42),(10,34),(14,27)], INK)
    poly(d, [(18,20),(23,17),(28,19),(31,24),(28,31),(30,38),(28,42),(25,37),(22,43),(20,37),(16,41),(17,33),(13,37),(14,31),(17,26)], VIOLET_DARK)
    poly(d, [(18,23),(22,20),(22,35),(19,39),(18,33),(15,35),(16,28)], SHADE)
    poly(d, [(27,21),(30,25),(27,31),(29,36),(26,34),(24,39),(24,29)], DEEP)
    # Hollow rib cage and a crooked central seam give the body a hostile structure.
    poly(d, [(18,22),(23,19),(29,22),(28,30),(24,34),(18,30),(15,26)], INK)
    line(d, [(18,23),(22,25),(22,29),(19,30)], RED, 2)
    line(d, [(28,23),(25,25),(25,30),(28,31)], SHADE, 2)
    poly(d, [(23,20),(26,22),(24,26),(26,29),(23,33),(22,29),(23,26),(21,23)], VIOLET)
    # Tall flared head frame, closer to a parasite crown than a humanoid hood.
    poly(d, [(14,5),(19,1),(23,4),(28,0),(33,5),(36,14),(33,24),(28,27),(19,25),(12,20),(10,12)], INK)
    poly(d, [(16,7),(20,4),(23,7),(28,3),(31,7),(33,14),(30,22),(26,24),(18,21),(14,17),(13,11)], SHADE)
    poly(d, [(14,8),(10,4),(11,13),(8,17),(13,18),(17,12)], INK)
    poly(d, [(32,8),(37,3),(36,12),(40,16),(34,19),(30,13)], INK)
    # The mask is long, cracked and asymmetrical; the maze itself is the only face.
    poly(d, [(18,4),(23,6),(28,3),(31,8),(30,18),(26,23),(20,21),(16,16),(16,8)], INK)
    poly(d, [(19,6),(23,8),(27,5),(29,9),(28,16),(25,20),(20,18),(18,14),(18,9)], MUTED)
    poly(d, [(20,7),(23,9),(27,7),(27,13),(25,17),(21,16),(19,13),(19,9)], IVORY)
    line(d, [(20,9),(26,9),(26,15),(21,15),(21,11),(25,11),(25,13),(23,13)], INK, 1)
    poly(d, [(27,6),(29,9),(27,12),(29,16),(26,20),(25,17),(27,14),(25,11)], VIOLET_DARK)
    box(d, (22,17,25,19), INK)
    box(d, (23,17,24,18), RED)


def nameless_void(im):
    d = ImageDraw.Draw(im)
    # Floating robe with a hollow head and an absent torso, no facial features.
    poly(d, [(16,9),(21,3),(29,4),(35,11),(34,23),(40,31),(44,40),(36,43),(30,39),(25,47),(19,41),(12,45),(6,40),(10,29),(14,22),(12,15)], INK)
    poly(d, [(18,11),(22,7),(28,7),(32,12),(31,23),(36,31),(40,38),(35,40),(30,36),(25,42),(20,37),(14,41),(10,38),(13,29),(17,22),(15,15)], VIOLET_DARK)
    poly(d, [(17,13),(21,8),(28,8),(32,13),(29,22),(24,25),(18,21),(15,17)], SHADE)
    poly(d, [(19,12),(23,9),(28,11),(29,16),(26,21),(21,20),(18,17)], INK)
    poly(d, [(21,13),(26,12),(27,16),(24,19),(20,17)], DEEP)
    # Empty center: one coherent negative-space chamber with a broken rim.
    poly(d, [(18,24),(24,21),(31,25),(32,32),(27,38),(20,36),(15,31)], INK)
    poly(d, [(20,25),(25,24),(29,27),(29,32),(25,35),(20,33),(18,29)], (24,15,27,255))
    poly(d, [(17,24),(21,22),(23,24),(19,28),(17,32),(14,29)], RED)
    poly(d, [(29,23),(32,26),(34,32),(31,35),(30,30),(27,27)], SHADE)
    # Hanging sleeves terminate in large, intentional torn shapes.
    poly(d, [(14,23),(8,23),(4,31),(2,37),(8,39),(13,33),(17,28)], INK)
    poly(d, [(34,23),(40,24),(44,31),(46,36),(41,39),(36,33),(31,28)], INK)
    poly(d, [(11,26),(7,31),(6,35),(10,33),(14,27)], SHADE)
    poly(d, [(37,27),(41,31),(42,35),(38,33),(34,27)], SHADE)
    line(d, [(20,39),(23,42),(25,39)], VIOLET, 2)


def scale_inquisitor(im):
    d = ImageDraw.Draw(im)
    # Judge's robe and shoulder mantle.
    poly(d, [(16,17),(21,13),(29,14),(34,20),(33,28),(38,39),(34,46),(26,44),(22,47),(16,44),(10,46),(9,38),(14,28)], INK)
    poly(d, [(18,20),(23,17),(28,18),(31,22),(30,30),(34,39),(31,42),(25,40),(22,44),(18,40),(13,42),(12,38),(16,29)], SHADE)
    poly(d, [(17,25),(23,22),(23,40),(18,38),(14,40),(15,32)], RED)
    poly(d, [(25,22),(30,25),(30,32),(33,39),(27,38),(25,32)], DEEP)
    # Helmet and face are visible below the scales, not hidden by the beam.
    poly(d, [(17,13),(20,8),(28,8),(32,13),(31,22),(27,26),(20,24),(16,20)], INK)
    poly(d, [(19,14),(22,11),(27,11),(29,14),(28,20),(25,23),(20,21),(18,18)], MUTED)
    box(d, (18,15,29,17), DEEP)
    box(d, (20,15,22,16), GOLD); box(d, (26,15,28,16), GOLD)
    box(d, (23,14,24,21), INK)
    # Large ceremonial balance. Thick chains and solid pans survive 2x display.
    box(d, (23,2,25,13), INK); box(d, (24,3,24,11), GOLD)
    poly(d, [(21,3),(24,0),(27,3),(25,5),(22,5)], GOLD)
    poly(d, [(3,9),(20,7),(24,9),(28,7),(45,9),(45,12),(28,11),(24,13),(20,11),(3,12)], INK)
    poly(d, [(5,9),(20,8),(23,10),(20,10),(5,11)], GOLD)
    poly(d, [(25,10),(28,8),(43,9),(43,11),(28,10)], GOLD)
    for x in (7,14,34,41): box(d, (x,11,x+1,22), GOLD_DARK)
    poly(d, [(3,22),(19,22),(17,28),(7,30),(3,26)], INK)
    poly(d, [(29,22),(45,22),(45,26),(40,30),(31,28)], INK)
    poly(d, [(6,23),(16,23),(14,26),(8,27)], GOLD)
    poly(d, [(32,23),(42,23),(40,27),(34,26)], GOLD)
    # Hands clasped beneath the instrument and a central law seal.
    poly(d, [(15,27),(21,29),(24,34),(20,36),(14,32)], INK)
    poly(d, [(32,27),(27,29),(24,34),(28,36),(34,32)], INK)
    box(d, (21,30,27,33), IVORY)
    poly(d, [(22,35),(26,35),(28,39),(24,42),(20,39)], GOLD_DARK)
    box(d, (23,36,25,39), GOLD)


def shattered_king(im):
    d = ImageDraw.Draw(im)
    # Royal cape, broad broken armor and separated armored boots.
    poly(d, [(12,17),(19,13),(30,14),(38,20),(41,34),(37,44),(30,43),(25,47),(20,43),(11,45),(7,38),(9,26)], INK)
    poly(d, [(13,22),(18,18),(22,22),(20,39),(14,41),(10,37)], RED)
    poly(d, [(28,18),(35,22),(38,34),(35,40),(29,39),(26,25)], VIOLET_DARK)
    poly(d, [(13,19),(20,16),(29,17),(36,21),(33,31),(28,35),(19,34),(12,29)], INK)
    poly(d, [(15,21),(21,19),(23,23),(21,31),(17,31),(14,27)], LIGHT)
    poly(d, [(27,20),(33,22),(34,27),(29,31),(26,28)], SHADE)
    poly(d, [(14,21),(20,19),(19,23),(15,26)], GOLD_DARK)
    poly(d, [(29,20),(34,23),(32,26),(28,23)], ICE_DARK)
    # Fractured helmet with two still-readable eye slits.
    poly(d, [(16,9),(21,5),(29,6),(34,11),(32,20),(27,24),(19,22),(14,17)], INK)
    poly(d, [(18,11),(22,8),(28,9),(31,12),(29,18),(26,21),(19,19),(17,16)], RED)
    poly(d, [(18,12),(23,10),(29,12),(29,15),(24,14),(18,16)], DEEP)
    box(d, (19,12,22,13), GOLD); box(d, (26,12,29,13), ICE)
    poly(d, [(23,8),(26,9),(24,14),(27,17),(24,22),(22,18),(23,15),(21,12)], INK)
    # Broken crown: three large prongs, not disconnected debris.
    poly(d, [(15,10),(13,3),(19,6),(20,0),(24,5),(29,1),(30,7),(35,4),(33,12),(27,9),(21,9)], INK)
    poly(d, [(17,8),(16,6),(20,8),(21,4),(24,8),(28,4),(28,8),(31,7),(30,9),(24,7)], GOLD)
    # A three-element wound runs through crown, torso and skirt.
    poly(d, [(23,20),(26,22),(24,26),(28,30),(25,34),(27,39),(23,43),(21,38),(23,34),(20,30),(22,26),(20,23)], INK)
    poly(d, [(23,22),(24,23),(22,27),(25,30),(23,32),(21,29)], GOLD)
    poly(d, [(24,32),(25,34),(24,38),(23,40),(22,37)], ICE)
    poly(d, [(25,28),(27,30),(25,32),(24,30)], POISON)
    # Clawed gauntlets complete the silhouette.
    poly(d, [(11,24),(5,25),(3,33),(7,39),(13,35),(15,28)], INK)
    poly(d, [(36,24),(42,25),(45,32),(41,39),(35,35),(33,28)], INK)
    poly(d, [(8,27),(6,32),(8,35),(11,32),(12,27)], SHADE)
    poly(d, [(38,27),(42,31),(40,35),(37,32)], ICE_DARK)


def whispering_cultist(im):
    d = ImageDraw.Draw(im)
    # Robed preacher with a wide, readable hood and raised open hands.
    poly(d, [(16,12),(21,6),(29,7),(34,13),(33,24),(38,34),(36,44),(28,46),(24,42),(18,46),(10,43),(11,32),(15,24),(13,17)], INK)
    poly(d, [(18,15),(22,11),(28,11),(31,15),(30,24),(34,34),(33,41),(28,42),(24,38),(19,42),(14,40),(14,33),(18,24)], SHADE)
    poly(d, [(17,25),(22,27),(21,39),(16,40),(14,35)], RED)
    poly(d, [(27,25),(31,29),(33,38),(28,39),(25,34)], DEEP)
    poly(d, [(16,9),(21,3),(29,4),(35,10),(34,19),(29,25),(20,24),(14,19),(12,13)], INK)
    poly(d, [(18,11),(22,7),(28,8),(32,12),(31,18),(27,22),(20,20),(16,17),(15,13)], RED)
    poly(d, [(19,12),(23,9),(28,11),(30,15),(27,20),(21,18),(18,16)], DEEP)
    # Eyes and mouth remain visible within the hood.
    box(d, (20,13,22,14), IVORY); box(d, (26,13,28,14), IVORY)
    poly(d, [(22,16),(27,16),(26,19),(23,19)], INK)
    box(d, (23,16,26,16), PALE)
    # Arms rise in a preaching gesture; palms are intentionally large shapes.
    poly(d, [(15,23),(10,23),(7,18),(5,11),(2,9),(1,15),(4,24),(11,31),(17,29)], INK)
    poly(d, [(33,23),(38,21),(40,15),(40,9),(44,7),(46,13),(44,23),(37,30),(31,29)], INK)
    poly(d, [(12,25),(8,23),(5,17),(6,15),(9,20),(14,25)], LIGHT)
    poly(d, [(35,25),(40,21),(42,15),(43,13),(43,20),(38,26)], LIGHT)
    poly(d, [(3,12),(1,7),(4,8),(4,3),(7,7),(9,5),(9,12),(6,16)], LIGHT)
    poly(d, [(40,11),(39,5),(42,7),(44,2),(45,7),(47,5),(46,12),(43,15)], LIGHT)
    # A hanging scripture panel; the raised hands carry the preaching gesture.
    poly(d, [(18,27),(24,25),(30,27),(29,35),(24,38),(18,34)], INK)
    poly(d, [(20,28),(24,27),(28,29),(27,32),(24,34),(20,32)], IVORY)
    line(d, [(21,29),(26,30)], VIOLET_DARK, 1)


DRAWERS = {
    "acid_ghoul": acid_ghoul,
    "brittle_gargoyle": brittle_gargoyle,
    "abyss_watcher": abyss_watcher,
    "hero_shadow": hero_shadow,
    "manic_elementalist": manic_elementalist,
    "maze_whisperer": maze_whisperer,
    "nameless_void": nameless_void,
    "scale_inquisitor": scale_inquisitor,
    "shattered_king": shattered_king,
    "whispering_cultist": whispering_cultist,
}
NAMES = {
    "acid_ghoul": "酸蚀恶鬼", "brittle_gargoyle": "碎裂石像鬼",
    "abyss_watcher": "深渊监视者", "hero_shadow": "勇者的阴影",
    "manic_elementalist": "躁怒元素使", "maze_whisperer": "迷宫低语者",
    "nameless_void": "无名虚空", "scale_inquisitor": "天平审判官",
    "shattered_king": "碎裂魔王", "whispering_cultist": "呓语教徒",
}


def isolated_pixels(im):
    pix = im.load()
    seen = set()
    singles = []
    for y in range(im.height):
        for x in range(im.width):
            if (x,y) in seen or pix[x,y][3] == 0:
                continue
            stack, component = [(x,y)], []
            seen.add((x,y))
            while stack:
                cx,cy = stack.pop()
                component.append((cx,cy))
                for nx,ny in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                    if 0 <= nx < im.width and 0 <= ny < im.height and (nx,ny) not in seen and pix[nx,ny][3] > 0:
                        seen.add((nx,ny)); stack.append((nx,ny))
            if len(component) == 1:
                singles.append(component[0])
    return singles


def main():
    images = {}
    for boss_id, draw in DRAWERS.items():
        im = Image.new("RGBA", (48,48), CLEAR)
        draw(im)
        singles = isolated_pixels(im)
        if singles:
            raise RuntimeError(f"{boss_id}: isolated pixels at {singles}")
        target = OUT / boss_id / "idle_01.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        im.save(target)
        images[boss_id] = im
        print(f"{boss_id}: 48x48 RGBA, no isolated pixels")

    font = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 15)
    small = ImageFont.truetype("C:/Windows/Fonts/simhei.ttf", 11)
    cw,ch,cols = 250,220,5
    sheet = Image.new("RGBA", (cw*cols, ch*2+44), (22,13,19,255))
    d = ImageDraw.Draw(sheet)
    d.text((14,10), "SEEK DEAD / BOSS REDRAW · 原生48×48 / 预览4×", fill=IVORY, font=font)
    for i,(boss_id,im) in enumerate(images.items()):
        x,y = (i%cols)*cw, 44+(i//cols)*ch
        d.rectangle((x+6,y+6,x+cw-7,y+ch-7), outline=(100,77,72,255), width=1)
        sheet.alpha_composite(im.resize((192,192), Image.Resampling.NEAREST), (x+10,y+10))
        d.text((x+12,y+184), NAMES[boss_id], fill=IVORY, font=font)
        d.text((x+12,y+202), boss_id, fill=MUTED, font=small)
    sheet.save(SHEET / "boss_contact_sheet.png")
    print("sheet:", SHEET / "boss_contact_sheet.png")

    preserved = {
        "frozen_urn": "冰封铁瓮", "cocoon_sentinel": "茧居石雕",
        "grand_inquisitor": "耻辱审判官",
    }
    all_ids = ["frozen_urn", "cocoon_sentinel", "grand_inquisitor"] + list(DRAWERS)
    all_sheet = Image.new("RGBA", (cw*cols, ch*3+44), (22,13,19,255))
    ad = ImageDraw.Draw(all_sheet)
    ad.text((14,10), "SEEK DEAD / ALL 13 BOSSES · 原生48×48 / 预览4×", fill=IVORY, font=font)
    for i,boss_id in enumerate(all_ids):
        im = images.get(boss_id)
        if im is None:
            filename = "closed.png" if boss_id == "cocoon_sentinel" else "idle_01.png"
            im = Image.open(OUT / boss_id / filename).convert("RGBA")
        x,y = (i%cols)*cw, 44+(i//cols)*ch
        ad.rectangle((x+6,y+6,x+cw-7,y+ch-7), outline=(100,77,72,255), width=1)
        all_sheet.alpha_composite(im.resize((192,192), Image.Resampling.NEAREST), (x+10,y+10))
        ad.text((x+12,y+184), NAMES.get(boss_id, preserved.get(boss_id, boss_id)), fill=IVORY, font=font)
        ad.text((x+12,y+202), boss_id, fill=MUTED, font=small)
    all_sheet.save(SHEET / "all_bosses_contact_sheet.png")
    print("all bosses:", SHEET / "all_bosses_contact_sheet.png")


if __name__ == "__main__":
    main()
