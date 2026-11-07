#!/usr/bin/env python3
"""Generate one 48x48 enemy sprite for every RoomData and bind it.

Deterministic, project-owned pixel art. Silhouette family comes from the room
archetype/name; element controls the secondary accent. Bosses get dedicated
silhouettes. Existing hand-made art is never overwritten.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import re

ROOT = Path(__file__).resolve().parents[2]
ROOM_DIR = ROOT / "resources" / "rooms"
OUT_DIR = ROOT / "assets" / "characters"
SHEET_DIR = ROOT / "docs" / "baseline" / "2026-11-05_all_monsters"
SHEET_DIR.mkdir(parents=True, exist_ok=True)

DEEP = (0x3A, 0x22, 0x2B, 255)
DARK = (0x8C, 0x34, 0x38, 255)
RED = (0xE3, 0x5B, 0x50, 255)
LIGHT = (0xFF, 0x80, 0x70, 255)
IVORY = (0xE2, 0xD7, 0xBD, 255)
MUTED = (0xA9, 0x9D, 0x89, 255)
CLEAR = (0, 0, 0, 0)
ACCENTS = {
    "none": (MUTED[0], MUTED[1], MUTED[2], 255),
    "fire": (0xD5, 0xA3, 0x3D, 255),
    "ice": (0x62, 0xA1, 0xC2, 255),
    "poison": (0xA4, 0xBC, 0x4D, 255),
    "light": IVORY,
    "dark": (0x9A, 0x76, 0xB8, 255),
}
ACCENT_DARK = {
    "none": (0x6E, 0x5F, 0x57, 255),
    "fire": (0x8C, 0x6A, 0x24, 255),
    "ice": (0x37, 0x61, 0x7A, 255),
    "poison": (0x6E, 0x82, 0x30, 255),
    "light": MUTED,
    "dark": (0x5C, 0x42, 0x70, 255),
}

EXPLICIT_FAMILY = {
    "abyssal_cantor": "cantor", "annihilation_apostle": "caster",
    "annihilation_lord": "brute", "beguiling_lantern": "lantern",
    "blasphemy_priest": "caster", "collapsing_core": "core",
    "corrupted_slime": "slime", "cracked_statue": "statue",
    "defiled_scribe": "scribe", "ember_golem": "golem",
    "final_watcher": "watcher", "frost_bat": "swarm",
    "riftsoul_wanderer": "wraith", "rust_blind_bat": "swarm",
    "shadow_acolyte": "cultist", "toxin_spore": "spore",
    "void_echo": "orb", "void_whisperer": "cultist",
}
ARCH_FAMILY = {
    "heavy_brawler": "brute", "elite_brute": "brute",
    "bulwark": "bulwark", "elite_warden": "bulwark", "sentinel": "bulwark",
    "striker": "striker", "trickster": "trickster",
    "elite_trickster": "trickster", "jammer": "hexer",
    "elite_hexer": "hexer", "status_sower": "caster",
    "elite_caster": "caster", "swarmer": "swarm",
    "elite_swarmking": "swarm", "poison_biter": "worm",
}
BOSSES = {
    "acid_ghoul", "brittle_gargoyle", "abyss_watcher", "hero_shadow",
    "manic_elementalist", "maze_whisperer", "nameless_void",
    "scale_inquisitor", "shattered_king", "whispering_cultist",
}
PRESERVE = {"frozen_urn", "cocoon_sentinel", "acid_golem", "grand_inquisitor", "a1_brute_none", "rust_blind_bat"} | BOSSES


def read_fields(path: Path):
    s = path.read_text(encoding="utf-8")
    def field(key, default=""):
        m = re.search(r"^" + re.escape(key) + r'\s*=\s*"?([^"\n]+)"?', s, re.M)
        return m.group(1).strip() if m else default
    arch = ""
    m = re.search(r'archetype\s*=\s*ExtResource\("([^"]+)"\)', s)
    if m:
        aid = m.group(1)
        em = re.search(r'\[ext_resource[^\]]*id="' + re.escape(aid) + r'"[^\]]*path="([^"]+)"', s)
        if not em:
            em = re.search(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="' + re.escape(aid) + r'"', s)
        if em:
            arch = Path(em.group(1)).stem
    return {
        "stem": path.stem,
        "name": field("name", path.stem),
        "kind": field("kind", "normal").strip('"'),
        "act": field("act", "1"),
        "element": field("element", "none").strip('"'),
        "arch": arch,
        "art": field("art"),
        "text": s,
    }


def family(room):
    stem = room["stem"]
    if stem in EXPLICIT_FAMILY:
        return EXPLICIT_FAMILY[stem]
    return ARCH_FAMILY.get(room["arch"], "brute")


def clean_isolated_pixels(img):
    """Remove disconnected single pixels; larger semantic components are preserved."""
    pix = img.load()
    w, h = img.size
    seen = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or pix[x, y][3] == 0:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            component = []
            while stack:
                cx, cy = stack.pop()
                component.append((cx, cy))
                for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and pix[nx, ny][3] > 0:
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if len(component) == 1:
                pix[component[0]] = CLEAR
    return img


def poly(d, pts, color):
    d.polygon(pts, fill=color)


def box(d, bb, color):
    d.rectangle(bb, fill=color)


def eyes(d, x, y, accent, count=2, gap=4):
    for i in range(count):
        xx = x + i * gap
        box(d, (xx, y, xx + 1, y + 1), accent)
        box(d, (xx + 1, y + 1, xx + 1, y + 1), DEEP)


def accent_gem(d, x, y, accent, style):
    if style == "fire":
        poly(d, [(x + 3, y), (x + 5, y + 4), (x + 5, y + 7), (x + 2, y + 9), (x, y + 6), (x + 1, y + 3)], accent)
        box(d, (x + 2, y + 5, x + 3, y + 7), IVORY)
    elif style == "ice":
        poly(d, [(x + 3, y), (x + 6, y + 3), (x + 5, y + 8), (x + 2, y + 9), (x, y + 4)], accent)
        box(d, (x + 2, y + 3, x + 3, y + 6), IVORY)
    elif style == "poison":
        box(d, (x + 1, y + 2, x + 6, y + 6), accent)
        box(d, (x + 2, y + 7, x + 5, y + 8), accent)
        box(d, (x + 2, y + 3, x + 3, y + 4), IVORY)
    elif style == "light":
        poly(d, [(x + 3, y), (x + 5, y + 3), (x + 8, y + 4), (x + 5, y + 6), (x + 3, y + 9), (x + 1, y + 6), (x - 2, y + 4), (x + 1, y + 3)], accent)
    elif style == "dark":
        box(d, (x, y + 1, x + 7, y + 7), DEEP)
        box(d, (x + 2, y + 3, x + 5, y + 5), accent)
        box(d, (x + 3, y + 4, x + 4, y + 4), IVORY)
    else:
        box(d, (x + 1, y + 1, x + 6, y + 7), accent)
        box(d, (x + 2, y + 2, x + 5, y + 6), ACCENT_DARK["none"])


def humanoid_base(d, accent, elite, variant, wide=False):
    shoulder = 3 if wide else 1
    poly(d, [(16 - shoulder, 17), (13, 11), (19, 5), (28, 5), (34, 11), (32 - shoulder, 18),
             (36, 24), (34, 38), (37, 44), (30, 47), (17, 47), (10, 44), (13, 38), (10, 24)], DEEP)
    poly(d, [(17 - shoulder, 18), (14, 12), (20, 7), (27, 7), (33, 12), (31 - shoulder, 19),
             (34, 25), (32, 37), (34, 42), (29, 45), (18, 45), (12, 42), (15, 37), (12, 25)], RED)
    poly(d, [(17, 14), (23, 10), (27, 14), (26, 23), (32, 32), (30, 43), (22, 44), (20, 33), (15, 25)], DARK)
    poly(d, [(16, 8), (20, 4), (27, 4), (31, 9), (29, 16), (26, 19), (18, 18), (14, 14)], LIGHT)
    poly(d, [(17, 9), (21, 6), (26, 6), (29, 10), (27, 15), (18, 15), (15, 13)], DARK)
    if elite:
        # Crown of thorns: an elite silhouette change, not only a recolor.
        poly(d, [(15, 8), (13, 2), (18, 5), (21, 0), (24, 5), (29, 2), (30, 9)], DEEP)
        poly(d, [(17, 7), (16, 4), (19, 6), (21, 3), (23, 6), (27, 4), (27, 8)], accent)
    else:
        box(d, (17 + variant, 7, 20 + variant, 9), accent)
    eyes(d, 19, 10, accent, 2, 5)
    # Shoulder ridges and arm asymmetry.
    poly(d, [(10, 20), (15, 16), (20, 19), (18, 24), (12, 25)], DEEP)
    poly(d, [(31, 18), (36, 19), (37, 24), (33, 27), (29, 23)], DEEP)
    poly(d, [(12, 21), (15, 19), (18, 21), (16, 23)], DARK)
    poly(d, [(33, 20), (36, 22), (34, 25), (31, 23)], DARK)
    # Legs.
    box(d, (17, 43, 22, 47), DEEP)
    box(d, (26, 43, 31, 47), DEEP)
    box(d, (18, 44, 21, 46), DARK)
    box(d, (27, 44, 30, 46), DARK)
    accent_gem(d, 21, 25, accent, "none")


def draw_brute(d, accent, elite, v):
    humanoid_base(d, accent, elite, v, wide=True)
    poly(d, [(7, 30), (3, 34), (5, 44), (11, 45), (14, 39), (13, 31)], DEEP)
    box(d, (7, 34, 12, 42), DARK)
    poly(d, [(38, 29), (44, 32), (43, 42), (37, 44), (34, 38)], DEEP)
    box(d, (37, 33, 42, 41), DARK)
    accent_gem(d, 10, 34, accent, "none")


def draw_bulwark(d, accent, elite, v):
    humanoid_base(d, accent, elite, v, wide=True)
    # Large frontal shield dominates the silhouette.
    poly(d, [(4, 19), (14, 17), (19, 22), (18, 35), (11, 43), (3, 35), (1, 23)], DEEP)
    poly(d, [(5, 21), (13, 20), (16, 24), (15, 33), (10, 39), (5, 33), (3, 24)], RED)
    poly(d, [(7, 24), (12, 23), (14, 26), (12, 31), (9, 34), (7, 30)], DARK)
    accent_gem(d, 7, 25, accent, "dark")
    box(d, (33, 23, 42, 25), DEEP)
    box(d, (35, 22, 44, 24), LIGHT)


def draw_striker(d, accent, elite, v):
    humanoid_base(d, accent, elite, v)
    # Lean body overlay and forward blade.
    poly(d, [(28, 24), (34, 18), (40, 15), (44, 9), (43, 17), (36, 28), (33, 34)], DEEP)
    poly(d, [(30, 24), (35, 19), (41, 15), (41, 18), (35, 25), (32, 31)], LIGHT)
    box(d, (30, 26, 33, 28), accent)
    poly(d, [(7, 27), (12, 23), (16, 26), (14, 31), (9, 31)], DEEP)


def draw_trickster(d, accent, elite, v):
    humanoid_base(d, accent, elite, v)
    # Tall split mask and narrow cape.
    poly(d, [(14, 18), (18, 14), (30, 14), (34, 18), (32, 29), (28, 35), (20, 35), (16, 28)], DEEP)
    poly(d, [(17, 18), (21, 16), (28, 16), (31, 19), (29, 27), (25, 31), (20, 30), (18, 26)], DARK)
    box(d, (21, 20, 23, 22), accent)
    box(d, (26, 20, 28, 22), accent)
    poly(d, [(9, 23), (5, 27), (7, 36), (12, 38), (14, 31)], DEEP)
    poly(d, [(34, 25), (39, 22), (43, 27), (40, 31), (35, 31)], DEEP)
    box(d, (37, 24, 42, 26), accent)


def draw_hexer(d, accent, elite, v):
    # Robed caster shape, no feet.
    poly(d, [(16, 9), (20, 4), (28, 4), (33, 10), (35, 20), (39, 38), (34, 46), (12, 46), (7, 38), (11, 20)], DEEP)
    poly(d, [(17, 11), (21, 7), (27, 7), (31, 11), (33, 20), (36, 36), (32, 43), (14, 43), (10, 36), (13, 20)], RED)
    poly(d, [(18, 12), (22, 9), (26, 9), (30, 12), (29, 21), (25, 25), (19, 22), (16, 17)], DARK)
    eyes(d, 20, 14, accent, 2, 4)
    poly(d, [(23, 14), (25, 14), (24, 20), (21, 23), (19, 20)], accent)
    # Staff with an accent orb.
    box(d, (37, 15, 39, 42), DEEP)
    poly(d, [(34, 11), (38, 7), (43, 11), (41, 17), (36, 18)], DEEP)
    box(d, (36, 10, 40, 14), accent)
    accent_gem(d, 20, 27, accent, d.elem if hasattr(d, "elem") else "none")


def draw_caster(d, accent, elite, v):
    draw_hexer(d, accent, elite, v)
    # Floating focus at the right hand.
    poly(d, [(34, 29), (39, 26), (43, 30), (42, 36), (37, 38), (33, 34)], DEEP)
    box(d, (35, 29, 40, 35), accent)
    box(d, (37, 30, 39, 32), IVORY)


def draw_cantor(d, accent, elite, v):
    # Floating lower robe with halo.
    poly(d, [(15, 12), (20, 6), (28, 6), (33, 12), (32, 23), (37, 39), (31, 43), (17, 43), (10, 38), (14, 24)], DEEP)
    poly(d, [(16, 13), (21, 8), (27, 8), (31, 13), (30, 23), (34, 37), (30, 40), (18, 40), (13, 37), (16, 24)], RED)
    poly(d, [(18, 14), (22, 10), (27, 10), (30, 14), (27, 20), (18, 20), (16, 17)], DARK)
    eyes(d, 20, 14, accent, 2, 4)
    box(d, (17, 23, 30, 24), IVORY)
    box(d, (20, 26, 27, 27), accent)
    # Halo.
    box(d, (17, 3, 31, 4), accent)
    box(d, (19, 2, 29, 2), ACCENT_DARK["dark"])
    # No feet; dangling ribbon.
    poly(d, [(21, 39), (24, 43), (22, 47), (19, 43)], DEEP)


def draw_worm(d, accent, elite, v):
    poly(d, [(9, 15), (17, 11), (27, 12), (35, 18), (39, 27), (35, 36), (40, 40), (36, 45), (24, 44), (17, 39), (10, 39), (3, 34), (6, 25)], DEEP)
    poly(d, [(11, 17), (18, 13), (26, 14), (33, 19), (36, 26), (32, 33), (36, 37), (31, 41), (24, 41), (18, 36), (11, 36), (6, 32), (8, 26)], RED)
    poly(d, [(12, 18), (19, 15), (23, 18), (19, 28), (14, 31), (9, 27)], DARK)
    # Segmented body rings.
    for x, y in [(24, 18), (27, 22), (29, 27), (27, 32), (23, 37), (17, 39)]:
        box(d, (x, y, x + 3, y + 2), LIGHT)
    eyes(d, 13, 19, accent, 2, 4)
    poly(d, [(10, 13), (8, 7), (12, 9), (14, 5), (16, 11)], DEEP)
    accent_gem(d, 13, 26, accent, "poison")


def draw_swarm(d, accent, elite, v):
    # Bat/imp with wide wings.
    poly(d, [(23, 17), (18, 11), (10, 6), (3, 10), (8, 17), (4, 24), (13, 23), (19, 29), (23, 26)], DEEP)
    poly(d, [(25, 17), (30, 11), (38, 6), (45, 10), (40, 17), (44, 24), (35, 23), (29, 29), (25, 26)], DEEP)
    poly(d, [(22, 18), (18, 13), (12, 9), (7, 12), (11, 17), (8, 21), (15, 20), (20, 26)], DARK)
    poly(d, [(26, 18), (30, 13), (36, 9), (41, 12), (37, 17), (40, 21), (33, 20), (28, 26)], DARK)
    poly(d, [(18, 22), (23, 16), (30, 16), (34, 22), (31, 33), (27, 38), (21, 36), (16, 29)], RED)
    poly(d, [(19, 19), (22, 14), (26, 14), (24, 20), (21, 23)], LIGHT)
    eyes(d, 23, 20, accent, 2, 4)
    poly(d, [(18, 13), (17, 8), (21, 11), (23, 6), (25, 11), (29, 8), (28, 14)], DEEP)
    accent_gem(d, 23, 28, accent, "dark")


def draw_slime(d, accent, elite, v):
    poly(d, [(12, 18), (18, 10), (27, 8), (35, 14), (41, 25), (40, 39), (36, 44), (10, 44), (5, 37), (7, 26)], DEEP)
    poly(d, [(13, 19), (19, 12), (26, 10), (33, 15), (38, 25), (37, 38), (33, 41), (12, 41), (8, 35), (9, 26)], RED)
    poly(d, [(16, 18), (22, 14), (30, 17), (32, 25), (27, 28), (19, 26)], DARK)
    eyes(d, 18, 20, accent, 2, 5)
    # Acid bubbles and drips.
    accent_gem(d, 23, 28, accent, "poison")
    for x, y in [(11, 32), (32, 29), (35, 35)]:
        box(d, (x, y, x + 3, y + 3), accent)
        box(d, (x + 1, y - 2, x + 2, y), accent)
    box(d, (19, 40, 22, 46), accent)
    box(d, (28, 39, 31, 44), accent)


def draw_statue(d, accent, elite, v):
    poly(d, [(15, 8), (21, 3), (29, 4), (34, 9), (35, 19), (39, 23), (37, 35), (40, 42), (34, 47), (13, 47), (8, 42), (10, 34), (7, 22), (13, 18)], DEEP)
    poly(d, [(16, 10), (22, 6), (28, 7), (32, 11), (33, 19), (36, 23), (34, 34), (37, 40), (32, 44), (15, 44), (11, 40), (13, 34), (10, 23), (14, 19)], RED)
    poly(d, [(18, 11), (22, 8), (28, 9), (31, 12), (29, 18), (20, 18), (16, 15)], DARK)
    eyes(d, 20, 12, accent, 2, 4)
    # Cracks and broken stone facets.
    poly(d, [(27, 7), (29, 16), (26, 20), (30, 25), (27, 34)], accent)
    poly(d, [(13, 24), (17, 23), (16, 31), (12, 35), (10, 29)], LIGHT)
    box(d, (9, 37, 17, 42), DARK)
    box(d, (31, 35, 38, 42), DARK)
    accent_gem(d, 21, 26, accent, "none")


def draw_golem(d, accent, elite, v):
    poly(d, [(10, 15), (17, 10), (31, 11), (39, 17), (43, 28), (38, 42), (29, 46), (17, 44), (8, 38), (4, 25)], DEEP)
    poly(d, [(12, 17), (18, 12), (30, 13), (37, 18), (40, 27), (35, 39), (29, 43), (18, 41), (11, 36), (7, 25)], RED)
    poly(d, [(15, 16), (22, 13), (23, 30), (18, 37), (11, 31), (9, 23)], DARK)
    poly(d, [(5, 25), (10, 22), (14, 27), (13, 40), (7, 44), (3, 37)], DEEP)
    poly(d, [(36, 23), (42, 26), (43, 38), (38, 43), (34, 36)], DEEP)
    eyes(d, 17, 18, accent, 2, 4)
    # Core and cracks.
    poly(d, [(20, 22), (30, 23), (33, 30), (28, 38), (19, 35), (16, 28)], DEEP)
    box(d, (20, 25, 29, 32), accent)
    poly(d, [(27, 8), (30, 2), (32, 9), (36, 4), (37, 13)], DEEP)
    accent_gem(d, 22, 26, accent, "fire")


def draw_core(d, accent, elite, v):
    # Floating shattered core with orbital shards.
    poly(d, [(14, 10), (22, 5), (31, 9), (37, 18), (35, 29), (29, 37), (20, 39), (11, 32), (8, 22)], DEEP)
    poly(d, [(16, 12), (23, 8), (29, 11), (34, 18), (32, 28), (27, 34), (20, 35), (13, 30), (10, 22)], RED)
    poly(d, [(19, 14), (27, 13), (31, 19), (29, 28), (23, 32), (16, 26), (15, 19)], DARK)
    box(d, (21, 18, 28, 25), accent)
    box(d, (23, 20, 26, 23), IVORY)
    for coords in [[(3, 18), (10, 15), (12, 20)], [(37, 11), (44, 14), (40, 20)], [(34, 33), (42, 35), (38, 41)]]:
        poly(d, coords, DEEP)


def draw_lantern(d, accent, elite, v):
    # Suspended cage with a bright flame core.
    box(d, (22, 1, 24, 7), DEEP)
    poly(d, [(15, 8), (20, 5), (29, 5), (34, 9), (32, 14), (18, 14)], DEEP)
    poly(d, [(14, 13), (34, 13), (38, 21), (37, 38), (31, 45), (18, 45), (11, 38), (10, 22)], DEEP)
    poly(d, [(16, 15), (31, 15), (34, 21), (33, 36), (28, 41), (19, 41), (14, 36), (13, 22)], DARK)
    box(d, (18, 18, 29, 36), RED)
    accent_gem(d, 20, 20, accent, "fire")
    for x in (17, 22, 27, 32):
        box(d, (x, 16, x, 39), DEEP)
    box(d, (15, 38, 32, 41), DEEP)
    box(d, (20, 42, 26, 45), DEEP)


def draw_spore(d, accent, elite, v):
    # Mushroom-like spore with a heavy cap.
    poly(d, [(9, 19), (13, 9), (22, 4), (32, 8), (39, 18), (36, 24), (13, 24)], DEEP)
    poly(d, [(11, 19), (15, 11), (22, 7), (30, 10), (36, 18), (33, 21), (14, 21)], RED)
    for x, y in [(14, 12), (20, 9), (29, 11), (25, 17), (31, 15)]:
        box(d, (x, y, x + 3, y + 2), accent)
    poly(d, [(18, 21), (27, 21), (30, 32), (28, 42), (22, 46), (16, 41), (16, 31)], DEEP)
    poly(d, [(19, 23), (26, 23), (28, 32), (25, 40), (20, 37), (18, 30)], DARK)
    eyes(d, 20, 26, accent, 2, 4)
    for x, y in [(11, 31), (33, 27), (31, 38)]:
        box(d, (x, y, x + 2, y + 3), accent)


def draw_watcher(d, accent, elite, v):
    # Giant eye with root/tentacle lower body.
    poly(d, [(20, 4), (35, 10), (41, 23), (37, 35), (27, 40), (17, 36), (10, 29), (9, 16)], DEEP)
    poly(d, [(21, 7), (33, 12), (38, 23), (34, 32), (26, 36), (18, 33), (13, 27), (13, 17)], RED)
    poly(d, [(20, 11), (32, 14), (35, 23), (31, 29), (23, 27), (16, 22)], DARK)
    poly(d, [(21, 16), (28, 16), (31, 20), (27, 24), (21, 23), (18, 20)], accent)
    box(d, (23, 18, 26, 21), IVORY)
    box(d, (24, 19, 25, 20), DEEP)
    for x1, x2 in [(14, 7), (20, 12), (42, 44), (31, 39)]:
        poly(d, [(x1, 33), (x2, 47), (x1 + 4, 45), (x1 + 5, 36)], DEEP)
    accent_gem(d, 35, 28, accent, "dark")


def draw_wraith(d, accent, elite, v):
    poly(d, [(17, 12), (22, 5), (29, 5), (34, 12), (35, 25), (40, 36), (34, 44), (28, 47), (22, 43), (15, 47), (9, 39), (13, 25)], DEEP)
    poly(d, [(18, 13), (23, 8), (28, 8), (32, 13), (32, 25), (36, 35), (31, 40), (25, 42), (20, 39), (13, 42), (11, 36), (16, 25)], RED)
    poly(d, [(19, 12), (24, 9), (28, 10), (30, 15), (27, 22), (19, 21), (16, 17)], DARK)
    eyes(d, 21, 14, accent, 2, 4)
    poly(d, [(11, 23), (7, 28), (9, 36), (14, 34), (16, 27)], DEEP)
    poly(d, [(35, 26), (41, 24), (43, 31), (38, 35)], DEEP)
    accent_gem(d, 21, 27, accent, "ice")


def draw_orb(d, accent, elite, v):
    poly(d, [(14, 10), (22, 5), (31, 9), (38, 18), (36, 31), (29, 39), (19, 39), (11, 31), (8, 20)], DEEP)
    poly(d, [(16, 12), (22, 8), (29, 11), (34, 18), (32, 29), (27, 35), (20, 35), (14, 29), (11, 21)], RED)
    poly(d, [(20, 14), (26, 13), (30, 18), (29, 27), (24, 32), (18, 27), (17, 20)], DARK)
    box(d, (21, 20, 27, 25), accent)
    box(d, (23, 21, 25, 23), IVORY)
    # Orbital ring.
    for x in range(8, 40, 4):
        if x < 20 or x > 28:
            box(d, (x, 18 if x % 8 else 20, x + 2, 20 if x % 8 else 22), ACCENT_DARK["dark"])


def draw_scribe(d, accent, elite, v):
    draw_hexer(d, accent, elite, v)
    poly(d, [(9, 30), (23, 28), (26, 35), (12, 38)], DEEP)
    box(d, (11, 30, 24, 35), IVORY)
    box(d, (13, 32, 21, 33), DEEP)


def draw_cultist(d, accent, elite, v):
    draw_hexer(d, accent, elite, v)
    # Sound/whisper rings from the right side.
    for r, y in [(3, 22), (6, 25)]:
        box(d, (39 + r, y, 40 + r, y + 1), accent)


def draw_acid_ghoul(d, accent, elite):
    # Hunched ghoul with one oversized arm and exposed acid belly.
    poly(d, [(13, 10), (19, 5), (28, 7), (33, 13), (31, 21), (37, 26), (38, 39), (31, 45), (14, 44), (8, 37), (10, 26), (7, 18)], DEEP)
    poly(d, [(14, 12), (20, 8), (27, 10), (30, 14), (28, 21), (34, 27), (34, 37), (29, 42), (16, 41), (11, 35), (13, 26), (10, 19)], RED)
    poly(d, [(17, 12), (22, 9), (26, 11), (25, 18), (18, 20), (13, 16)], DARK)
    eyes(d, 18, 13, accent, 2, 4)
    poly(d, [(5, 22), (9, 18), (14, 22), (13, 33), (8, 43), (3, 39), (2, 29)], DEEP)
    poly(d, [(7, 24), (10, 21), (12, 25), (10, 36), (7, 39), (5, 31)], DARK)
    poly(d, [(19, 23), (29, 22), (33, 28), (31, 37), (25, 41), (17, 36), (15, 29)], DEEP)
    box(d, (20, 25, 29, 34), accent)
    box(d, (22, 26, 27, 28), IVORY)
    box(d, (25, 34, 28, 42), accent)
    box(d, (18, 37, 21, 43), accent)


def draw_gargoyle(d, accent, elite):
    # Spread wings and cracked stone body.
    poly(d, [(22, 16), (13, 10), (3, 11), (7, 18), (2, 25), (12, 24), (18, 32), (23, 28)], DEEP)
    poly(d, [(26, 16), (35, 10), (45, 11), (41, 18), (46, 25), (36, 24), (30, 32), (25, 28)], DEEP)
    poly(d, [(21, 18), (13, 13), (7, 14), (10, 19), (7, 23), (15, 21), (21, 27)], DARK)
    poly(d, [(27, 18), (35, 13), (41, 14), (38, 19), (41, 23), (33, 21), (27, 27)], DARK)
    poly(d, [(17, 14), (21, 8), (27, 8), (32, 14), (33, 25), (37, 33), (35, 42), (29, 46), (18, 45), (12, 38), (13, 27)], DEEP)
    poly(d, [(19, 15), (22, 10), (27, 11), (30, 16), (30, 26), (34, 33), (31, 39), (27, 42), (19, 41), (15, 35), (16, 27)], RED)
    poly(d, [(20, 15), (23, 12), (27, 13), (28, 18), (25, 22), (19, 21), (17, 18)], DARK)
    eyes(d, 21, 16, accent, 2, 4)
    poly(d, [(18, 9), (15, 3), (21, 6), (24, 2), (27, 7), (31, 4), (30, 11)], DEEP)
    box(d, (21, 28, 27, 30), accent)
    poly(d, [(26, 31), (29, 37), (26, 42), (24, 37)], accent)


def draw_abyss_watcher(d, accent):
    draw_watcher(d, accent, True, 0)
    # Multiple concentric eyes and heavier tentacles.
    box(d, (17, 9, 36, 10), ACCENT_DARK["dark"])
    box(d, (11, 27, 15, 39), accent)
    box(d, (32, 29, 36, 40), accent)
    box(d, (17, 41, 21, 47), DEEP)
    box(d, (26, 41, 30, 47), DEEP)


def draw_hero_shadow(d, accent):
    # Mirror knight: clean vertical silhouette, empty helm, long blade.
    poly(d, [(17, 8), (21, 4), (29, 4), (34, 9), (33, 19), (31, 25), (36, 34), (34, 45), (28, 47), (17, 47), (11, 43), (13, 31), (11, 20)], DEEP)
    poly(d, [(18, 10), (22, 6), (28, 6), (31, 10), (31, 18), (28, 24), (33, 33), (31, 43), (27, 44), (18, 44), (14, 41), (16, 31), (13, 20)], RED)
    poly(d, [(19, 10), (22, 8), (27, 8), (30, 11), (28, 17), (20, 17), (16, 13)], DARK)
    box(d, (20, 12, 22, 14), IVORY)
    box(d, (26, 12, 28, 14), IVORY)
    # Great blade held forward.
    poly(d, [(32, 26), (41, 11), (46, 5), (44, 16), (37, 31)], DEEP)
    poly(d, [(34, 26), (42, 12), (44, 8), (42, 18), (36, 29)], IVORY)
    box(d, (32, 27, 38, 29), accent)
    # Crown shard.
    poly(d, [(18, 8), (17, 3), (21, 5), (23, 1), (25, 5), (29, 3), (29, 9)], DEEP)


def draw_manic_elementalist(d, accent):
    draw_hexer(d, accent, True, 1)
    # Three floating unstable orbs.
    for cx, cy, col in [(6, 12, ACCENTS["fire"]), (40, 8, IVORY), (41, 37, ACCENTS["dark"])]:
        box(d, (cx, cy, cx + 5, cy + 5), DEEP)
        box(d, (cx + 1, cy + 1, cx + 4, cy + 4), col)


def draw_maze_whisperer(d, accent):
    # Tall oval mask with maze orbit and hanging tendrils.
    poly(d, [(15, 9), (20, 3), (31, 5), (37, 13), (36, 29), (39, 36), (31, 41), (13, 40), (7, 33), (10, 23), (8, 16)], DEEP)
    poly(d, [(16, 11), (21, 6), (29, 8), (34, 14), (33, 28), (35, 34), (29, 38), (15, 37), (10, 32), (13, 23), (11, 16)], RED)
    poly(d, [(17, 11), (23, 8), (30, 11), (31, 23), (28, 30), (20, 29), (14, 23), (14, 16)], DARK)
    # Spiral eye/mask motif.
    box(d, (18, 15, 29, 16), accent)
    box(d, (19, 20, 28, 21), accent)
    box(d, (24, 16, 25, 20), accent)
    box(d, (21, 18, 23, 19), IVORY)
    for x in (14, 20, 29, 35):
        box(d, (x, 38, x + 3, 46), DEEP)


def draw_nameless_void(d, accent):
    # Floating hollow robe, central absence.
    poly(d, [(15, 8), (20, 3), (29, 5), (36, 12), (38, 29), (45, 40), (34, 44), (27, 40), (20, 47), (10, 42), (8, 30), (12, 17)], DEEP)
    poly(d, [(17, 10), (22, 6), (28, 8), (33, 14), (34, 28), (39, 37), (30, 40), (24, 36), (17, 42), (12, 38), (11, 29), (14, 17)], RED)
    poly(d, [(18, 10), (23, 7), (28, 10), (29, 20), (25, 28), (18, 24), (14, 17)], DARK)
    # Empty inner void.
    poly(d, [(20, 20), (27, 19), (31, 26), (27, 34), (20, 32), (17, 26)], DEEP)
    box(d, (21, 23, 27, 28), accent)
    box(d, (23, 24, 25, 26), IVORY)
    for x in (12, 34):
        box(d, (x, 33, x + 3, 45), DEEP)


def draw_scale_inquisitor(d, accent):
    # Tall judge with a balance beam.
    draw_hexer(d, accent, True, 2)
    box(d, (4, 15, 43, 16), IVORY)
    box(d, (8, 16, 9, 23), IVORY)
    box(d, (38, 16, 39, 23), IVORY)
    poly(d, [(4, 24), (14, 24), (12, 30), (6, 30)], DEEP)
    poly(d, [(34, 24), (44, 24), (42, 30), (36, 30)], DEEP)
    box(d, (7, 25, 12, 28), accent)
    box(d, (35, 25, 41, 28), accent)
    box(d, (22, 5, 26, 14), DEEP)
    box(d, (23, 6, 25, 12), accent)


def draw_shattered_king(d, accent):
    # Broad king split by a bright central fracture.
    humanoid_base(d, accent, True, 0, wide=True)
    poly(d, [(8, 19), (14, 15), (20, 20), (18, 31), (12, 34), (6, 28)], DEEP)
    poly(d, [(40, 18), (34, 15), (29, 21), (31, 32), (38, 34), (44, 28)], DEEP)
    box(d, (9, 20, 16, 27), DARK)
    box(d, (33, 20, 40, 27), DARK)
    # Crown and split.
    poly(d, [(16, 7), (15, 1), (19, 4), (22, 0), (25, 4), (30, 1), (30, 9)], DEEP)
    box(d, (19, 3, 27, 6), accent)
    poly(d, [(23, 15), (25, 15), (24, 23), (27, 28), (24, 36), (22, 30), (20, 23)], IVORY)
    box(d, (34, 30, 44, 32), accent)


def draw_whispering_cultist(d, accent):
    # Preaching silhouette: hood, raised arms, sound arcs.
    draw_hexer(d, accent, False, 3)
    poly(d, [(8, 25), (3, 18), (1, 10), (5, 15), (9, 21)], DEEP)
    poly(d, [(34, 26), (41, 20), (45, 13), (43, 23), (38, 31)], DEEP)
    for x, y in [(40, 8), (43, 11), (46, 14)]:
        box(d, (x, y, x + 1, y + 4), accent)
    box(d, (17, 28, 28, 29), IVORY)
    box(d, (20, 31, 25, 32), ACCENT_DARK["dark"])


def draw_room(room):
    stem, fam = room["stem"], family(room)
    element = room["element"]
    accent = ACCENTS.get(element, MUTED)
    elite = room["kind"] == "elite"
    v = sum(ord(c) for c in stem) % 4
    im = Image.new("RGBA", (48, 48), CLEAR)
    d = ImageDraw.Draw(im)
    if stem == "acid_ghoul":
        draw_acid_ghoul(d, accent, elite)
    elif stem == "brittle_gargoyle":
        draw_gargoyle(d, accent, elite)
    elif stem == "abyss_watcher":
        draw_abyss_watcher(d, accent)
    elif stem == "hero_shadow":
        draw_hero_shadow(d, accent)
    elif stem == "manic_elementalist":
        draw_manic_elementalist(d, accent)
    elif stem == "maze_whisperer":
        draw_maze_whisperer(d, accent)
    elif stem == "nameless_void":
        draw_nameless_void(d, accent)
    elif stem == "scale_inquisitor":
        draw_scale_inquisitor(d, accent)
    elif stem == "shattered_king":
        draw_shattered_king(d, accent)
    elif stem == "whispering_cultist":
        draw_whispering_cultist(d, accent)
    elif fam == "brute": draw_brute(d, accent, elite or room["kind"] == "boss", v)
    elif fam == "bulwark": draw_bulwark(d, accent, elite or room["kind"] == "boss", v)
    elif fam == "striker": draw_striker(d, accent, elite, v)
    elif fam == "trickster": draw_trickster(d, accent, elite, v)
    elif fam == "hexer": draw_hexer(d, accent, elite, v)
    elif fam == "caster": draw_caster(d, accent, elite, v)
    elif fam == "cantor": draw_cantor(d, accent, elite, v)
    elif fam == "worm": draw_worm(d, accent, elite, v)
    elif fam == "swarm": draw_swarm(d, accent, elite, v)
    elif fam == "slime": draw_slime(d, accent, elite, v)
    elif fam == "statue": draw_statue(d, accent, elite, v)
    elif fam == "golem": draw_golem(d, accent, elite, v)
    elif fam == "core": draw_core(d, accent, elite, v)
    elif fam == "lantern": draw_lantern(d, accent, elite, v)
    elif fam == "spore": draw_spore(d, accent, elite, v)
    elif fam == "watcher": draw_watcher(d, accent, elite, v)
    elif fam == "wraith": draw_wraith(d, accent, elite, v)
    elif fam == "orb": draw_orb(d, accent, elite, v)
    elif fam == "scribe": draw_scribe(d, accent, elite, v)
    elif fam == "cultist": draw_cultist(d, accent, elite, v)
    else: draw_brute(d, accent, elite, v)
    return clean_isolated_pixels(im)


def integrate_room(path: Path, room, asset_rel: str):
    raw = path.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    changes = []
    if not room["art"]:
        ext = f'[ext_resource type="Texture2D" path="res://{asset_rel}" id="art_room"]'
        lines = raw.splitlines(keepends=True)
        insert_at = max(i for i, line in enumerate(lines) if line.startswith("[ext_resource")) + 1
        lines.insert(insert_at, ext + nl)
        raw = "".join(lines)
        raw = re.sub(r"load_steps=(\d+)", lambda m: f"load_steps={int(m.group(1)) + 1}", raw, count=1)
        scale = "2.0" if room["kind"] == "boss" else "1.0"
        body = f'art = ExtResource("art_room"){nl}art_scale = {scale}{nl}'
        if not raw.endswith(("\n", "\r")):
            raw += nl
        raw += body
        changes.append("art")
    path.write_bytes(raw.encode("utf-8"))


def make_sheet(items, title):
    font_path = "C:/Windows/Fonts/simhei.ttf"
    font = ImageFont.truetype(font_path, 12)
    small = ImageFont.truetype(font_path, 9)
    cols = 8
    cw, ch = 140, 108
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * ch + 36), (0x16, 0x0D, 0x13, 255))
    d = ImageDraw.Draw(sheet)
    d.text((12, 10), title, fill=IVORY, font=font)
    for i, (stem, name, kind, img) in enumerate(items):
        x, y = (i % cols) * cw, 36 + (i // cols) * ch
        box = (x + 6, y + 6, x + cw - 6, y + ch - 6)
        d.rectangle(box, outline=(0x6E, 0x5F, 0x57, 255), width=1)
        sheet.alpha_composite(img.resize((72, 72), Image.Resampling.NEAREST), (x + 10, y + 9))
        d.text((x + 86, y + 12), kind[:5], fill=ACCENTS["ice"], font=small)
        label = name if len(name) <= 8 else name[:8] + "…"
        d.text((x + 86, y + 29), label, fill=IVORY, font=small)
        d.text((x + 86, y + 44), stem[:15], fill=MUTED, font=small)
    return sheet


def main():
    rooms = [read_fields(p) for p in sorted(ROOM_DIR.glob("*.tres"))]
    generated = []
    for room in rooms:
        path = ROOM_DIR / f"{room['stem']}.tres"
        asset_dir = OUT_DIR / room["stem"]
        target = asset_dir / "idle_01.png"
        asset_rel = target.relative_to(ROOT).as_posix()
        if room["stem"] in PRESERVE:
            if target.exists():
                integrate_room(path, room, asset_rel)
            else:
                print("preserved art missing, skipped binding:", room["stem"])
        else:
            asset_dir.mkdir(parents=True, exist_ok=True)
            img = draw_room(room)
            img.save(target)
            integrate_room(path, room, asset_rel)
            print("generated:", room["stem"])
        preview = target
        if room["stem"] == "cocoon_sentinel":
            preview = asset_dir / "closed.png"
        if preview.exists():
            generated.append((room["stem"], room["name"], room["kind"], Image.open(preview).convert("RGBA")))
    make_sheet(generated, "SEEK DEAD - ALL %d ROOMS / 48x48" % len(generated)).save(SHEET_DIR / "all_rooms_contact_sheet.png")
    boss_items = [x for x in generated if x[2] == "boss"]
    make_sheet(boss_items, "SEEK DEAD - ALL %d BOSSES / 48x48" % len(boss_items)).save(SHEET_DIR / "boss_contact_sheet.png")
    print("rooms:", len(generated), "bosses:", len(boss_items))
    print("sheet:", SHEET_DIR / "all_rooms_contact_sheet.png")


if __name__ == "__main__":
    main()
