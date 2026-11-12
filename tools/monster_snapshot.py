#!/usr/bin/env python3
"""Step 0 baseline: dump every resources/rooms/*.tres -> CSV + JSON snapshot.

Read-only against the project. Used by docs/全怪物个性机制设计与制作计划 Step 0
(冻结基线：怪物清单 + 现有机制快照). Re-run after any room/gimmick change.
"""
from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOMS_DIR = ROOT / "resources" / "rooms"
ARCH_DIR = ROOT / "resources" / "archetypes"
BALANCE = ROOT / "resources" / "config" / "balance_config.tres"
OUT_DIR = ROOT / "docs" / "baseline" / "2026-11-12_step0_matrix"

EXT_RE = re.compile(r'\[ext_resource type="([^"]+)" (?:path|uid)="[^"]*"(?: path="([^"]+)")? id="([^"]+)"\]')
EXT_RE2 = re.compile(r'\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\]')
KV_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$')
STR_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"$')


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_tres(path: Path) -> dict:
    text = read_text(path)
    ext: dict[str, dict] = {}
    for m in EXT_RE.finditer(text):
        typ, p, i = m.group(1), m.group(2), m.group(3)
        if p:
            ext[i] = {"type": typ, "path": p}
    for m in EXT_RE2.finditer(text):
        typ, p, i = m.group(1), m.group(2), m.group(3)
        ext[i] = {"type": typ, "path": p}

    fields: dict[str, str] = {}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("[") or s.startswith(";"):
            continue
        m = KV_RE.match(s)
        if m:
            fields[m.group(1)] = m.group(2).strip()

    def resolve(key: str) -> str:
        raw = fields.get(key, "")
        m = re.match(r'ExtResource\("([^"]+)"\)', raw)
        if m and m.group(1) in ext:
            return ext[m.group(1)]["path"]
        return ""

    def string(key: str) -> str:
        raw = fields.get(key, "")
        m = STR_RE.match(raw)
        if not m:
            return ""
        return m.group(1).replace("\\n", "\n").replace('\\"', '"').replace("\\t", "\t")

    def number(key: str) -> str:
        return fields.get(key, "").strip()

    def boolean(key: str) -> bool:
        return fields.get(key, "").strip() == "true"

    return {
        "file": path.name,
        "name": string("name"),
        "hp": number("hp"),
        "atk": number("atk"),
        "armor": number("armor"),
        "element": string("element"),
        "kind": string("kind"),
        "act": number("act"),
        "archetype_path": resolve("archetype"),
        "gimmick_script": resolve("gimmick_script"),
        "gimmick_params": fields.get("gimmick_params", ""),
        "mechanic_summary": string("mechanic_summary"),
        "boss_role": string("boss_role"),
        "final_boss": boolean("final_boss"),
        "intents_raw": fields.get("intents", ""),
        "sha1": hashlib.sha1(read_text(path).encode("utf-8")).hexdigest(),
    }


def parse_archetype(path_str: str) -> dict:
    if not path_str:
        return {}
    path = ROOT / path_str.replace("res://", "")
    if not path.exists():
        return {"missing": path_str}
    text = read_text(path)
    fields: dict[str, str] = {}
    for line in text.splitlines():
        s = line.strip()
        m = KV_RE.match(s)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    return {
        "id": fields.get("id", "").strip('"'),
        "display_name": fields.get("display_name", "").strip('"'),
        "intent_weights": fields.get("intent_weights", ""),
        "hp_base": fields.get("hp_base", ""),
        "atk_base": fields.get("atk_base", ""),
        "armor_base": fields.get("armor_base", ""),
        "sha1": hashlib.sha1(text.encode("utf-8")).hexdigest(),
    }


def eff(value: str, fallback: str) -> str:
    # RoomData 的 0 = 回落行为族基准；行为族也为空（无 archetype）时保持 0。
    if value not in ("", "0"):
        return value
    return fallback if fallback not in ("",) else (value or "0")


def parse_balance() -> dict:
    if not BALANCE.exists():
        return {}
    fields: dict[str, str] = {}
    for line in read_text(BALANCE).splitlines():
        m = KV_RE.match(line.strip())
        if m:
            fields[m.group(1)] = m.group(2).strip()
    keep = [
        "counter_burst_pct",
        "heal_line_mults",
        "charge_burst_pct",
        "player_dmg_mult",
        "crit_chance",
        "ante_act_step_hp",
        "ante_act_step_atk",
        "ante_room_step_hp",
        "ante_room_step_atk",
        "run_act_layout",
    ]
    return {k: fields.get(k, "") for k in keep}


def main() -> int:
    rooms = [parse_tres(p) for p in sorted(ROOMS_DIR.glob("*.tres"))]
    arche = {p.stem: parse_archetype("res://resources/archetypes/%s.tres" % p.stem) for p in sorted(ARCH_DIR.glob("*.tres"))}
    for room in rooms:
        arch = arche.get(Path(room["archetype_path"]).stem, {}) if room["archetype_path"] else {}
        room["archetype"] = arch
        room["eff_hp"] = eff(room["hp"], arch.get("hp_base", ""))
        room["eff_atk"] = eff(room["atk"], arch.get("atk_base", ""))
        room["eff_armor"] = eff(room["armor"], arch.get("armor_base", ""))
        room["gimmick_sha1"] = ""
        if room["gimmick_script"]:
            gp = ROOT / room["gimmick_script"].replace("res://", "")
            if gp.exists():
                room["gimmick_sha1"] = hashlib.sha1(read_text(gp).encode("utf-8")).hexdigest()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    csv_path = OUT_DIR / "monsters_snapshot.csv"
    cols = [
        "id", "name", "kind", "act", "element", "hp", "atk", "armor",
        "eff_hp", "eff_atk", "eff_armor", "archetype_id", "archetype_weights",
        "gimmick_script", "gimmick_params", "mechanic_summary", "boss_role", "final_boss",
    ]
    with csv_path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rooms:
            w.writerow({
                "id": Path(r["file"]).stem,
                "name": r["name"],
                "kind": r["kind"],
                "act": r["act"],
                "element": r["element"],
                "hp": r["hp"],
                "atk": r["atk"],
                "armor": r["armor"],
                "eff_hp": r["eff_hp"],
                "eff_atk": r["eff_atk"],
                "eff_armor": r["eff_armor"],
                "archetype_id": r["archetype"].get("id", ""),
                "archetype_weights": r["archetype"].get("intent_weights", ""),
                "gimmick_script": r["gimmick_script"].replace("res://", ""),
                "gimmick_params": r["gimmick_params"],
                "mechanic_summary": r["mechanic_summary"],
                "boss_role": r["boss_role"],
                "final_boss": r["final_boss"],
            })

    snapshot = {
        "generated_from": "tools/monster_snapshot.py",
        "room_count": len(rooms),
        "counts": {
            kind: sum(1 for r in rooms if r["kind"] == kind)
            for kind in ("normal", "elite", "boss")
        },
        "balance": parse_balance(),
        "archetypes": arche,
        "rooms": rooms,
    }
    (OUT_DIR / "monsters_snapshot.json").write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    # Markdown quick table (one row per room, grouped by kind / act)
    lines = [
        "# 怪物清单与机制快照（2026-11-12 · Step 0 冻结）",
        "",
        "> 由 `tools/monster_snapshot.py` 从 `resources/rooms/*.tres` 与 `resources/archetypes/*.tres` 生成，勿手改。",
        "> 快照口径：0 值回落行为族基准；未乘 ante 缩放。完整字段见同目录 `monsters_snapshot.csv` / `.json`。",
        "",
        "| # | 怪物 | ID | 类型 | 幕 | 元素 | 有效 HP | 有效 ATK | 有效甲 | 行为族/意图 | 现有机制脚本 | 机制摘要 |",
        "|---:|---|---|---|---:|---|---:|---:|---:|---|---|---|",
    ]
    order = {"normal": 0, "elite": 1, "boss": 2}
    for i, r in enumerate(sorted(rooms, key=lambda x: (order.get(x["kind"], 9), x["act"], x["name"])), 1):
        summary = r["mechanic_summary"].replace("\n", " / ").replace("|", "\\|")
        arch = r["archetype"]
        arch_cell = "%s（%s）" % (arch.get("display_name", "—"), arch.get("intent_weights", "—")) if arch else "—"
        script = r["gimmick_script"].split("/")[-1].replace(".gd", "") if r["gimmick_script"] else "—"
        lines.append(
            "| %d | %s | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |"
            % (
                i, r["name"], Path(r["file"]).stem, r["kind"], r["act"], r["element"],
                r["eff_hp"], r["eff_atk"], r["eff_armor"], arch_cell, script, summary or "—",
            )
        )
    lines += [
        "",
        "## 计数",
        "",
        "| 类型 | 数量 |",
        "|---|---:|",
        "| 普通 | %d |" % snapshot["counts"]["normal"],
        "| 精英 | %d |" % snapshot["counts"]["elite"],
        "| BOSS | %d |" % snapshot["counts"]["boss"],
        "| **合计** | **%d** |" % len(rooms),
        "",
        "## 关键平衡冻结值",
        "",
        "| 键 | 值 |",
        "|---|---|",
    ]
    for k, v in snapshot["balance"].items():
        lines.append("| `%s` | `%s` |" % (k, v))
    (OUT_DIR / "monsters_snapshot.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("rooms=%d normal=%d elite=%d boss=%d" % (
        len(rooms), snapshot["counts"]["normal"], snapshot["counts"]["elite"], snapshot["counts"]["boss"]))
    print("wrote", csv_path.relative_to(ROOT))
    print("wrote", (OUT_DIR / "monsters_snapshot.json").relative_to(ROOT))
    print("wrote", (OUT_DIR / "monsters_snapshot.md").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
