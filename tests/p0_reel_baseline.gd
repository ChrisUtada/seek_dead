extends Node

# ============================================================================
# P0 · 转轮目押基线探针（docs/转轮目押_成长与减带优化_执行方案.md §10 P0）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p0_reel_baseline.tscn
#
# 目的：固定当前速度/预览/输入/建带规则作为对照组，输出代表性配装的
#   实际带长、未平铺带长、目标格数、目标占比、理论循环时间与目标反应窗口。
#
# 不修改任何生产状态：只读 ReelSystem / ReelPreview / WeaponMastery，测试结束退出。
# 输出行前缀 P0REEL|，可直接对照后续 P1/P2 改动。
# ============================================================================

const OUT := "P0REEL"
const STRIP_MIN := 30          # ReelSystem._STRIP_MIN_CELLS 的只读快照
const BASE_WAIT := 0.15        # ReelSystem._SPIN_BASE_WAIT
const MIN_WAIT := 0.06         # ReelSystem._SPIN_MIN_WAIT
const ACCEL := 0.0010          # ReelSystem.on_spin_tick 每跳减速
const STEADY_WAIT := 0.17      # GrowthSystem.STEADY_WAIT（稳定节奏前 2 回合）
const VISIBLE_AHEAD := 2       # ReelSpinView SLOTS=5、当前格居中 → 前向可见 2 槽
const TARGET_SYMBOL := "res://resources/symbols/fire_slash.tres"   # 主武器最高权重攻击符号

const WP := "res://resources/weapon_templates/"
const SK := "res://resources/skills/"

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	_duel = await _boot()
	var rows: Array = []
	for sc in _scenarios():
		rows.append(_measure(sc))
	_cross_checks(rows)
	_print_table(rows)
	print("---")
	print("%s|RESULT %s (checks=%d fails=%d)" % [OUT, "PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _scenarios() -> Array:
	return [
		{"id": "A_starter", "weapons": ["dagger", "fire_sword"], "skills": [], "forge": 0, "tune": false},
		{"id": "B_diff", "weapons": ["fire_sword", "ice_staff"], "skills": [], "forge": 0, "tune": false},
		{"id": "C_same", "weapons": ["fire_sword", "flame_staff"], "skills": [], "forge": 0, "tune": false},
		{"id": "D_buff3", "weapons": ["fire_sword", "ice_staff"], "skills": ["haste", "rage", "calm"], "forge": 0, "tune": false},
		{"id": "E_forge", "weapons": ["fire_sword", "ice_staff"], "skills": [], "forge": 2, "tune": false},
		{"id": "F_tune", "weapons": ["fire_sword", "ice_staff"], "skills": [], "forge": 0, "tune": true},
		{"id": "G_weapon_mix", "weapons": ["fire_sword", "ice_staff"], "skills": [], "forge": 2, "tune": true},
		{"id": "H_full_mix", "weapons": ["fire_sword", "ice_staff"], "skills": ["haste", "rage", "calm"], "forge": 2, "tune": true},
	]


func _measure(sc: Dictionary) -> Dictionary:
	# —— 固定本场景状态 ——
	var weapons: Array[String] = []
	for w in sc["weapons"]:
		weapons.append(WP + String(w) + ".tres")
	var skills: Array[String] = []
	for s in sc["skills"]:
		skills.append(SK + String(s) + ".tres")
	_duel.selected_loadout.assign(weapons)
	_duel.selected_skills.assign(skills)
	_duel.selected_charms.clear()
	_duel.mastery.reset_run()
	_duel.deprived_level = 0
	_duel.room_element_mult.clear()
	_duel.pending_chaos = false
	_duel.boss_trash = 0

	# 调律：逐武器按 engine 的合法目标（只有真实改变格数才允许），最多 2 次/把。
	if bool(sc["tune"]):
		for wp in weapons:
			for _i in 2:
				var tgt: Dictionary = _duel.mastery.tune_target(wp)
				if tgt.is_empty():
					break
				var row: Dictionary = _duel.mastery.imprints.get(wp, {"forge": 0, "tune": {}}).duplicate(true)
				row["tune"][tgt["sym"]] = int(row["tune"].get(tgt["sym"], 0)) + 1
				_duel.mastery.imprints[wp] = row

	# 锋铸：每把最多 2 次（不改变带子，只改基础攻击）。
	if int(sc["forge"]) > 0:
		for wp in weapons:
			var row: Dictionary = _duel.mastery.imprints.get(wp, {"forge": 0, "tune": {}}).duplicate(true)
			row["forge"] = int(sc["forge"])
			_duel.mastery.imprints[wp] = row

	# —— 建池 + 建带（固定种子；连续两次验证组成确定性）——
	_duel.reel_system.build_pool(_duel.selected_loadout)
	seed(1000)
	_duel.reel_system.build_strips()
	var strip: Array = _duel.reel_system.reel_strips[0]
	var counts: Dictionary = _counts(strip)
	seed(1000)
	_duel.reel_system.build_strips()
	var strip2: Array = _duel.reel_system.reel_strips[0]
	var counts2: Dictionary = _counts(strip2)

	# —— 三列一致 + 确定性 ——
	_check(_duel.reel_system.reel_strips.size() == 3, "%s：三列转轮" % sc["id"])
	var lens: Array[int] = []
	for r in 3:
		lens.append(_duel.reel_system.reel_strips[r].size())
	_check(lens[0] == lens[1] and lens[1] == lens[2], "%s：三列等长（%s）" % [sc["id"], str(lens)])
	_check(counts == counts2, "%s：同种子带子组成可复现" % sc["id"])

	# —— 与 ReelPreview 同口径比对 ——
	var comp: Dictionary = ReelPreview.compose(_duel.selected_loadout, _duel.selected_skills,
		_duel.selected_charms, _duel.room_element_mult, _duel._reward_system.run_symbol_bonus,
		_duel.deprived_level, _duel.pending_chaos, _duel.boss_trash, _duel.mastery.tune_map())
	var unit: int = int(comp["total_cells"])
	var copies: int = 1
	while unit * copies < STRIP_MIN:
		copies += 1
	_check(strip.size() == unit * copies, "%s：实际带长 = 未平铺 %d × %d" % [sc["id"], unit, copies])
	_check(strip.size() >= STRIP_MIN, "%s：实际带长 ≥ %d" % [sc["id"], STRIP_MIN])

	var target_cells := 0
	var target_row := {}
	for row in comp["rows"]:
		if String(row["path"]) == TARGET_SYMBOL:
			target_row = row
			target_cells = int(row["cells"])
			break
	_check(target_cells > 0, "%s：目标符号在带内（%d 格/单位）" % [sc["id"], target_cells])
	_check(int(counts.get(TARGET_SYMBOL, 0)) == target_cells * copies,
		"%s：目标实际格数 = %d×%d" % [sc["id"], target_cells, copies])

	# —— 指标 ——
	var total: int = strip.size()
	var target_actual: int = int(counts.get(TARGET_SYMBOL, 0))
	var ratio: float = float(target_actual) / float(total)
	var gap_cells: float = float(total) / maxf(1.0, float(target_actual))
	var cycle: float = _cycle_seconds(total, BASE_WAIT)
	var cycle_steady: float = _cycle_seconds(total, STEADY_WAIT)
	var power_parts: Array[String] = []
	for wp in weapons:
		var wd: WeaponData = load(wp)
		power_parts.append("%s:%d" % [String(wd.weapon_name), int(wd.base_power) + _duel.mastery.forge_bonus(wp)])
	return {
		"id": String(sc["id"]),
		"total": total,
		"unit": unit,
		"copies": copies,
		"symbol_cells": int(comp["symbol_cells"]),
		"miss_cells": int(comp["miss_cells"]),
		"gold_cells": int(comp["gold_cells"]),
		"trash_cells": int(comp.get("trash_cells", 0)),
		"target_cells_unit": target_cells,
		"target_cells": target_actual,
		"ratio": ratio,
		"gap_cells": gap_cells,
		"cycle": cycle,
		"cycle_steady": cycle_steady,
		"reaction_fastest": VISIBLE_AHEAD * MIN_WAIT,
		"reaction_now": VISIBLE_AHEAD * (BASE_WAIT - 0.001 * float(maxi(0, total - 1))),
		"power": " / ".join(power_parts),
		"top": _top_rows(comp["rows"], 3),
		"tune": _tune_summary(),
	}


func _cross_checks(rows: Array) -> void:
	var by := {}
	for r in rows:
		by[r["id"]] = r
	# 锋铸：带子组成不变、基础攻击提高
	_check(by["E_forge"]["total"] == by["B_diff"]["total"], "锋铸不改变实际带长（%d → %d）" % [by["B_diff"]["total"], by["E_forge"]["total"]])
	_check(by["E_forge"]["symbol_cells"] == by["B_diff"]["symbol_cells"], "锋铸不改变符号格数")
	_check(by["E_forge"]["power"] != by["B_diff"]["power"], "锋铸提高基础攻击（%s → %s）" % [by["B_diff"]["power"], by["E_forge"]["power"]])
	# 调律：单位内目标格数增加
	_check(by["F_tune"]["target_cells_unit"] > by["B_diff"]["target_cells_unit"],
		"调律增加目标格数（%d → %d/单位）" % [by["B_diff"]["target_cells_unit"], by["F_tune"]["target_cells_unit"]])
	_check(by["F_tune"]["ratio"] > by["B_diff"]["ratio"], "调律提高目标占比（%.1f%% → %.1f%%）" % [by["B_diff"]["ratio"] * 100.0, by["F_tune"]["ratio"] * 100.0])
	# Buff 技能：单位符号格数增加，目标占比被稀释
	_check(by["D_buff3"]["symbol_cells"] > by["B_diff"]["symbol_cells"],
		"3 技能增加符号格数（%d → %d/单位）" % [by["B_diff"]["symbol_cells"], by["D_buff3"]["symbol_cells"]])
	_check(by["D_buff3"]["ratio"] < by["B_diff"]["ratio"], "3 技能稀释目标占比（%.1f%% → %.1f%%）" % [by["B_diff"]["ratio"] * 100.0, by["D_buff3"]["ratio"] * 100.0])
	# 同元素与异元素：当前同元素配装因共鸣权重，目标占比更高但带长不同
	_check(by["C_same"]["ratio"] > by["B_diff"]["ratio"], "同元素配装目标占比高于异元素（%.1f%% vs %.1f%%）" % [by["C_same"]["ratio"] * 100.0, by["B_diff"]["ratio"] * 100.0])


func _counts(strip: Array) -> Dictionary:
	var d := {}
	for e in strip:
		var sym: SymbolData = e[0]
		var p: String = sym.resource_path
		d[p] = int(d.get(p, 0)) + 1
	return d


func _top_rows(rows: Array, n: int) -> String:
	var parts: Array[String] = []
	for i in mini(n, rows.size()):
		var r: Dictionary = rows[i]
		parts.append("%s×%d" % [String(r["name"]), int(r["cells"])])
	return " ".join(parts)


func _tune_summary() -> String:
	var parts: Array[String] = []
	for wp in _duel.mastery.imprints:
		var row: Dictionary = _duel.mastery.imprints[wp]
		for sym in row["tune"]:
			parts.append("%s+%d" % [String(sym).get_file().get_basename(), int(row["tune"][sym])])
	return "、".join(parts) if not parts.is_empty() else "-"


# 当前加速曲线的理论循环时长：从 base_wait 起每跳 -0.001，封底 min_wait。
func _cycle_seconds(cells: int, base_wait: float) -> float:
	var t := 0.0
	var w := base_wait
	for _i in cells:
		t += w
		w = maxf(MIN_WAIT, w - ACCEL)
	return t


func _print_table(rows: Array) -> void:
	print("%s|RULES base_wait=%.2f min_wait=%.2f accel=%.4f strip_min=%d visible_ahead=%d insight_next=1 input_buffer=0" % [
		OUT, BASE_WAIT, MIN_WAIT, ACCEL, STRIP_MIN, VISIBLE_AHEAD])
	for r in rows:
		print("%s|%s len=%d unit=%d copies=%d symbols=%d miss=%d gold=%d trash=%d target=%d(unit %d) ratio=%.1f%% gap=%.2fcells cycle=%.2fs steady=%.2fs reaction_now=%.2fs reaction_fast=%.2fs power=[%s] top=[%s] tune=[%s]" % [
			OUT, r["id"], int(r["total"]), int(r["unit"]), int(r["copies"]), int(r["symbol_cells"]),
			int(r["miss_cells"]), int(r["gold_cells"]), int(r["trash_cells"]), int(r["target_cells"]),
			int(r["target_cells_unit"]), float(r["ratio"]) * 100.0, float(r["gap_cells"]),
			float(r["cycle"]), float(r["cycle_steady"]), float(r["reaction_now"]),
			float(r["reaction_fastest"]), String(r["power"]), String(r["top"]), String(r["tune"])])


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + label)
	else:
		_fails += 1
		print("FAIL  " + label)
