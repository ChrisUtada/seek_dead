from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
WEAPON_DIR = ROOT / "resources" / "weapon_templates"
POWER_SCALE = {0: 0.85, 2: 1.15, 3: 0.95}
HIT_DELTA = {0: 0.04, 2: -0.03}
TRIPLE_TEXT = {
    0: "同源三连追加50%伤害",
    2: "三连清空护甲",
    3: "同源三连充能+1、状态+1",
}


def field(text, name, default):
    match = re.search(rf"^{name}\s*=\s*(\S+)", text, re.M)
    return int(match.group(1)) if match else default


def replace_field(text, name, value):
    return re.sub(rf"^{name}\s*=\s*\S+", f"{name} = {value}", text, count=1, flags=re.M)


def update_summary(text, archetype, weapon_type, power, hit):
    text = re.sub(r"命中率\d+%", f"命中率{round(hit * 100)}%", text)
    text = re.sub(r"基础伤害\d+", f"基础伤害{power}", text)
    text = re.sub(r"基础攻击\d+", f"基础攻击{power}", text)
    descriptions = []
    if archetype in TRIPLE_TEXT:
        descriptions.append(TRIPLE_TEXT[archetype])
    if weapon_type == 1:
        descriptions.append("同源三连35%穿透")
    for description in descriptions:
        if description in text:
            continue
        if "无额外机制，靠基础伤害与三连线；" in text:
            text = text.replace("无额外机制，靠基础伤害与三连线；", description + "；", 1)
        else:
            text = text.replace("；命中率", "；" + description + "；命中率", 1)
    return text


def main():
    apply = "--apply" in sys.argv
    changes = []
    for path in sorted(WEAPON_DIR.glob("*.tres")):
        with path.open("r", encoding="utf-8", newline="") as handle:
            text = handle.read()
        archetype = field(text, "archetype", 1)
        weapon_type = field(text, "weapon_type", 0)
        old_power = field(text, "base_power", 0)
        old_hit_match = re.search(r"^hit_rate\s*=\s*(\S+)", text, re.M)
        if not old_hit_match or old_power <= 0:
            continue
        old_hit = float(old_hit_match.group(1))
        new_power = max(1, round(old_power * POWER_SCALE.get(archetype, 1.0)))
        new_hit = old_hit + HIT_DELTA.get(archetype, 0.0)
        if weapon_type == 1:
            new_hit += 0.03
        new_hit = round(min(0.96, max(0.50, new_hit)), 3)
        if archetype == 2:
            new_hit = max(0.72, new_hit)
        updated = replace_field(text, "base_power", new_power)
        updated = replace_field(updated, "hit_rate", new_hit)
        updated = update_summary(updated, archetype, weapon_type, new_power, new_hit)
        if updated == text:
            continue
        changes.append((path.name, old_power, new_power, old_hit, new_hit))
        if apply:
            with path.open("w", encoding="utf-8", newline="") as handle:
                handle.write(updated)
    print(f"{'APPLY' if apply else 'DRY-RUN'}: {len(changes)} weapons")
    for name, old_power, new_power, old_hit, new_hit in changes:
        print(f"{name}: power {old_power}->{new_power}; hit {old_hit:.3f}->{new_hit:.3f}")


if __name__ == "__main__":
    main()
