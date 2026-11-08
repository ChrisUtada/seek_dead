# -*- coding: utf-8 -*-
"""Seek Dead · ACT1 局内自动记录汇总（G5 自动记录配套）

读取 run_journal 写出的 user://runs/run_*.json，合成一张总表：
胜率、各骨架/模板表现、战败分布、逐局明细。

用法（在项目根目录）：
  python tools\\run_summary_report.py
  python tools\\run_summary_report.py "<runs 目录>"
  python tools\\run_summary_report.py "<runs 目录>" --out 报告.md --csv 明细.csv

默认目录：%APPDATA%\\Godot\\app_userdata\\Seek Dead Prototype\\runs
只读 JSON、只写你要的报表文件；不碰存档（lobby_data.json），不改任何数值。
主观项（手感、选路理由）不在这里，也不该在这里——按项目约定由作者口头反馈。

样本很少时（单骨架 < 3 局）比例没有统计意义，报告里会标注。
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import statistics
import sys
from datetime import datetime
from pathlib import Path

SHAPE_LABEL = {"standard": "标准", "long_tail": "长尾", "long_share": "延展"}
TEMPLATE_LABEL = {
    "standard": "常规",
    "mirror": "镜像",
    "elite_first": "精英前置",
    "elite_upper": "上路精英前置",
    "elite_lower": "下路精英前置",
}
KIND_LABEL = {"normal": "普通", "elite": "精英", "boss": "BOSS"}
SMALL_SAMPLE = 3          # 低于这个局数就提示“样本太少”
MIN_VALID_DURATION = 30.0  # 秒；再短的局基本是秒退，仍计入但单独标注


def default_runs_dir() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "Godot" / "app_userdata" / "Seek Dead Prototype" / "runs"
    return Path.home() / "runs"


def load_runs(runs_dir: Path) -> tuple[list[dict], list[str]]:
    """读入所有 run_*.json。返回 (局列表, 警告)。"""
    runs: list[dict] = []
    warnings: list[str] = []
    if not runs_dir.is_dir():
        warnings.append(f"目录不存在：{runs_dir}")
        return runs, warnings
    for path in sorted(runs_dir.glob("run_*.json")):
        try:
            with path.open("r", encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            warnings.append(f"跳过无法解析的文件 {path.name}：{exc}")
            continue
        data["_file"] = path.name
        runs.append(data)
    return runs, warnings


def num(value, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def tele(run: dict, key: str) -> float:
    return num((run.get("telemetry") or {}).get(key), 0.0)


def shape_of(run: dict) -> str:
    board = run.get("board") or {}
    shape = str(board.get("shape", "") or "")
    return shape if shape else "linear"


def template_of(run: dict) -> str:
    return str((run.get("board") or {}).get("template", "") or "")


def fmt_pct(part: float, whole: float) -> str:
    return f"{part / whole * 100.0:.0f}%" if whole else "—"


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def is_finished(run: dict) -> bool:
    return str(run.get("result", "")) in ("clear", "defeat")


def battle_count(run: dict) -> int:
    return int(num(run.get("battles_count", len(run.get("battles") or [])), 0))


def summarize(runs: list[dict]) -> dict:
    finished = [r for r in runs if is_finished(r)]
    clears = [r for r in finished if r.get("result") == "clear"]
    first_picks = [num((r.get("first_pick") or {}).get("seconds"), -1) for r in runs]
    first_picks = [v for v in first_picks if v >= 0]
    return {
        "total": len(runs),
        "finished": len(finished),
        "clears": len(clears),
        "defeats": len(finished) - len(clears),
        "unfinished": len(runs) - len(finished),
        "minutes": [num(r.get("duration_sec")) / 60.0 for r in finished],
        "battles": [battle_count(r) for r in finished],
        "turns": [tele(r, "turns") for r in finished],
        "damage": [tele(r, "damage_taken") for r in finished],
        "triple_rate": [tele(r, "triple_rate") for r in finished],
        "target_rate": [tele(r, "target_hit_rate") for r in finished],
        "first_picks": first_picks,
    }


def section_overview(runs: list[dict]) -> list[str]:
    s = summarize(runs)
    lines = ["## 一、总览", ""]
    if not runs:
        lines.append("（没有找到记录文件）")
        lines.append("")
        return lines
    lines.append(f"- 记录局数：**{s['total']}**（已完成 {s['finished']} 局，其中中途退出/未收口 {s['unfinished']} 局）")
    if s["finished"]:
        lines.append(f"- 通关 {s['clears']} / 战败 {s['defeats']}，通关率 **{fmt_pct(s['clears'], s['finished'])}**")
        lines.append(
            f"- 单局时长：均 {mean(s['minutes']):.1f} 分钟（中位 {median(s['minutes']):.1f}，"
            f"范围 {min(s['minutes']):.1f}–{max(s['minutes']):.1f}）"
        )
        lines.append(f"- 战斗场次：均 {mean(s['battles']):.1f} 场")
        lines.append(f"- 总局合：均 {mean(s['turns']):.0f} 回（每场 {mean(s['turns']) / max(mean(s['battles']), 1):.1f} 回）")
        lines.append(f"- 承伤：均 {mean(s['damage']):.0f}")
        lines.append(f"- 三连率：均 {mean(s['triple_rate']) * 100:.0f}%")
        lines.append(f"- 目标停中率：均 {mean(s['target_rate']) * 100:.0f}%")
    if s["first_picks"]:
        lines.append(
            f"- 首次落点（10 秒找落点）：均 {mean(s['first_picks']):.1f} 秒"
            f"（中位 {median(s['first_picks']):.1f}，最慢 {max(s['first_picks']):.1f}）"
        )
    lines.append("")
    return lines


def section_by_key(runs: list[dict], title: str, key_fn, label_fn) -> list[str]:
    groups: dict[str, list[dict]] = {}
    for run in runs:
        if not is_finished(run):
            continue
        groups.setdefault(key_fn(run), []).append(run)
    lines = [f"## {title}", ""]
    if not groups:
        lines.append("（没有已完成的局）")
        lines.append("")
        return lines
    lines.append("| 分组 | 局数 | 通关 | 通关率 | 均时长 | 均场次 | 均回合 | 均承伤 | 目标停中 | 首落点 |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    for key in sorted(groups, key=lambda k: (-len(groups[k]), k)):
        grp = groups[key]
        s = summarize(grp)
        picks = s["first_picks"]
        pick_text = f"{mean(picks):.1f}s" if picks else "—"
        name = label_fn(key)
        if len(grp) < SMALL_SAMPLE:
            name += "（样本少）"
        lines.append(
            f"| {name} | {len(grp)} | {s['clears']} | {fmt_pct(s['clears'], len(grp))} | "
            f"{mean(s['minutes']):.1f}m | {mean(s['battles']):.1f} | {mean(s['turns']):.0f} | "
            f"{mean(s['damage']):.0f} | {mean(s['target_rate']) * 100:.0f}% | {pick_text} |"
        )
    lines.append("")
    return lines


def section_deaths(runs: list[dict]) -> list[str]:
    defeats = [r for r in runs if r.get("result") == "defeat"]
    lines = ["## 四、战败分布", ""]
    if not defeats:
        lines.append("（没有战败记录）")
        lines.append("")
        return lines
    by_index: dict[int, int] = {}
    by_room: dict[str, int] = {}
    for run in defeats:
        idx = battle_count(run)
        by_index[idx] = by_index.get(idx, 0) + 1
        death = run.get("death") or {}
        room = str(death.get("room", "") or "未知")
        kind = KIND_LABEL.get(str(death.get("kind", "")), str(death.get("kind", "")))
        label = f"{room}（{kind}）" if kind else room
        by_room[label] = by_room.get(label, 0) + 1
    lines.append("- 死在第几场：" + " / ".join(f"第{i}场×{by_index[i]}" for i in sorted(by_index)))
    lines.append("- 死亡房间：" + " / ".join(
        f"{k}×{v}" for k, v in sorted(by_room.items(), key=lambda kv: (-kv[1], kv[0]))
    ))
    lines.append("")
    return lines


def section_runs(runs: list[dict]) -> list[str]:
    lines = ["## 五、逐局明细", ""]
    if not runs:
        lines.append("（空）")
        lines.append("")
        return lines
    lines.append("| 开始时间 | 模式 | 骨架 | 模板 | 结果 | 时长 | 场次 | 回合 | 承伤 | 三连率 | 停中率 | 首落点 | 终点/死亡点 | 文件 |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for run in sorted(runs, key=lambda r: str(r.get("started_at", ""))):
        shape = shape_of(run)
        shape_text = SHAPE_LABEL.get(shape, shape)
        tpl = template_of(run)
        tpl_text = TEMPLATE_LABEL.get(tpl, tpl) if tpl else "—"
        result = str(run.get("result", ""))
        result_text = {"clear": "通关", "defeat": "战败"}.get(result, "未收口")
        # 未收口的局没有局末补全的时长/遥测；显示「—」而不是假的 0。
        done = is_finished(run)
        mins = f"{num(run.get('duration_sec')) / 60.0:.1f}m" if done else "—"
        turns = f"{tele(run, 'turns'):.0f}" if done else "—"
        taken = f"{tele(run, 'damage_taken'):.0f}" if done else "—"
        triple = f"{tele(run, 'triple_rate') * 100:.0f}%" if done else "—"
        hit = f"{tele(run, 'target_hit_rate') * 100:.0f}%" if done else "—"
        death = run.get("death") or {}
        end_text = "—"
        if death:
            end_text = str(death.get("room", "")) or "—"
            node = str(death.get("node", "") or "")
            if node:
                end_text += f" @{node}"
        elif result == "clear":
            end_text = str(run.get("final_boss", "")) or "通关"
        pick = num((run.get("first_pick") or {}).get("seconds"), -1)
        lines.append(
            f"| {run.get('started_at', '?')} | {'棋盘' if run.get('mode') == 'board' else '线性'} | "
            f"{shape_text} | {tpl_text} | {result_text} | "
            f"{mins} | {battle_count(run)} | "
            f"{turns} | {taken} | "
            f"{triple} | {hit} | "
            f"{'—' if pick < 0 else f'{pick:.1f}s'} | {end_text} | {run.get('_file', '')} |"
        )
    lines.append("")
    return lines


def section_deck(runs: list[dict]) -> list[str]:
    """换装 / 成长 / 特殊格：看路线决策的实际落点，不含主观理由。"""
    lines = ["## 六、换装与特殊格", ""]
    if not runs:
        lines.append("（空）")
        lines.append("")
        return lines
    swap_runs = [r for r in runs if r.get("weapon_changes")]
    lines.append(f"- 有换武器的局：{len(swap_runs)} / {len(runs)}")
    if swap_runs:
        per_run = [len(r["weapon_changes"]) for r in swap_runs]
        lines.append(f"- 每局换武器次数：均 {mean(per_run):.1f}，最多 {max(per_run)}")
    specials: dict[str, int] = {}
    for run in runs:
        for item in run.get("special") or []:
            label = {"treasure": "宝箱", "shrine": "神龛", "armory": "武器藏库"}.get(
                str(item.get("type", "")), str(item.get("type", ""))
            )
            specials[label] = specials.get(label, 0) + 1
    if specials:
        lines.append("- 特殊格进入次数：" + " / ".join(
            f"{k}×{v}" for k, v in sorted(specials.items(), key=lambda kv: (-kv[1], kv[0]))
        ))
    consumables = sum(len(r.get("consumables") or []) for r in runs)
    lines.append(f"- 消耗品使用总次数：{consumables}")
    lines.append("")
    return lines


def build_markdown(runs: list[dict], warnings: list[str], runs_dir: Path) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# Seek Dead · ACT1 自动记录汇总",
        "",
        f"生成时间：{now}　目录：`{runs_dir}`",
        "",
        "> 数据来自 run_journal 自动写入的 JSON（每局结束/战败时生成）。"
        "主观项（手感、选路理由、复玩意愿）不在记录范围内。",
        "",
    ]
    if warnings:
        lines.append("**读取提示**")
        lines.extend(f"- {w}" for w in warnings)
        lines.append("")
    lines.extend(section_overview(runs))
    lines.extend(section_by_key(runs, "二、按骨架", shape_of,
                                lambda k: SHAPE_LABEL.get(k, k) if k != "linear" else "线性模式"))
    lines.extend(section_by_key(runs, "三、按模板", template_of,
                                lambda k: TEMPLATE_LABEL.get(k, k) if k else "—"))
    lines.extend(section_deaths(runs))
    lines.extend(section_runs(runs))
    lines.extend(section_deck(runs))
    lines.append("---")
    lines.append(
        "比例在单组样本少于 "
        f"{SMALL_SAMPLE} 局时标注「样本少」，此时只看方向，不要当结论。"
    )
    lines.append("")
    return "\n".join(lines)


def write_csv(path: Path, runs: list[dict]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "开始时间", "模式", "骨架", "模板", "结果", "时长分钟", "战斗场次", "回合",
            "承伤", "格挡", "三连率", "目标停中率", "首次落点秒", "死亡房间", "死亡节点",
            "换武器次数", "成长次数", "文件",
        ])
        for run in sorted(runs, key=lambda r: str(r.get("started_at", ""))):
            shape = shape_of(run)
            death = run.get("death") or {}
            pick = num((run.get("first_pick") or {}).get("seconds"), -1)
            done = is_finished(run)
            writer.writerow([
                run.get("started_at", ""),
                "棋盘" if run.get("mode") == "board" else "线性",
                SHAPE_LABEL.get(shape, shape),
                TEMPLATE_LABEL.get(template_of(run), template_of(run)),
                {"clear": "通关", "defeat": "战败"}.get(str(run.get("result", "")), "未收口"),
                f"{num(run.get('duration_sec')) / 60.0:.1f}" if done else "",
                battle_count(run),
                f"{tele(run, 'turns'):.0f}" if done else "",
                f"{tele(run, 'damage_taken'):.0f}" if done else "",
                f"{tele(run, 'damage_blocked'):.0f}" if done else "",
                f"{tele(run, 'triple_rate') * 100:.0f}%" if done else "",
                f"{tele(run, 'target_hit_rate') * 100:.0f}%" if done else "",
                "" if pick < 0 else f"{pick:.1f}",
                death.get("room", ""),
                death.get("node", ""),
                len(run.get("weapon_changes") or []),
                len(run.get("growth") or []),
                run.get("_file", ""),
            ])


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="汇总 Seek Dead ACT1 自动记录")
    parser.add_argument("runs_dir", nargs="?", default=None, help="runs 目录（默认 user://runs）")
    parser.add_argument("--out", default=None, help="Markdown 输出路径（默认 runs/summary_<时间>.md）")
    parser.add_argument("--csv", default=None, help="额外导出 CSV 明细")
    args = parser.parse_args(argv)

    runs_dir = Path(args.runs_dir) if args.runs_dir else default_runs_dir()
    runs, warnings = load_runs(runs_dir)
    report = build_markdown(runs, warnings, runs_dir)

    out_path = Path(args.out) if args.out else (
        runs_dir / f"summary_{datetime.now().strftime('%Y-%m-%dT%H-%M-%S')}.md"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report, encoding="utf-8")
    try:
        print(report)
        print(f"[汇总] 报告已写入：{out_path}")
        if args.csv:
            csv_path = Path(args.csv)
            csv_path.parent.mkdir(parents=True, exist_ok=True)
            write_csv(csv_path, runs)
            print(f"[汇总] 明细已写入：{csv_path}")
    except BrokenPipeError:      # 管道被 head / Select-Object 提前关闭时不算失败
        return 0
    return 0


if __name__ == "__main__":
    code = main(sys.argv[1:])
    try:
        sys.stdout.flush()
    except BrokenPipeError:
        # 输出被 | head / Select-Object -First 提前关闭：把 stdout 丢给空设备，
        # 避免解释器退出时再抛一次 BrokenPipeError（会变成非零退出码）。
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    sys.exit(code)
