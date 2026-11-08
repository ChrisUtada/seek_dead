extends Node

# ============================================================================
# G7-B B5 · P3 成长与 Buff 对照夹具（2026-11-09）
#
# 目的：给「成长轴 / Buff 轴」搭一个可复现的对照框架，**不产出平衡结论**。
#   8 组（`docs/转轮目押_成长与减带优化_执行方案.md` §10 P3）：
#     ① 无成长·无额外技能（基础）  ② 仅锋铸  ③ 仅调律  ④ 仅精简
#     ⑤ 仅增伤 Buff               ⑥ 仅防御/恢复 Buff  ⑦ 调律+精简  ⑧ 武器成长+Buff
#
# 与 G7-A 基线 bot 的关键差别：**按指定目标停轮**。
#   旧 bot「每列转起来就按停」= 随机落点，用它测调律/精简会把操作差异算进数值。
#   本夹具每拍读「逻辑游标此刻会落在哪一格」(`reel_strips[r][reel_cursor[r]]`)，
#   只在该格属于**同一个指定目标符号**时才按停；等待超过 MAX_WAIT 拍则强制停（记 forced）。
#   → 因此它是「理想化全信息 bot」：绝对伤害/等待拍数只代表本夹具，
#     组间差值才是「这条轴本身改变了什么」的量级参考。真人数据必须分开读。
#
# 协议：
#   - headless --fixed-fps 60；不改 BALANCE、不改任何 .tres；
#   - 同一个敌人（ACT1 固定精英房，无 gimmick）、同一玩家假人生命、同一回合数；
#   - 每组同种子列表、同目标符号（目标取主武器 R2 调律目标，取不到则取最大伤害符号）；
#   - 资源预算：②③ 各 2 次铭印；⑤⑥ 各 2 件同稀有度护符；④ 1 次精简（机制上限就是每幕 1）；
#     ⑦ 2 铭印 + 1 精简；⑧ 2 铭印 + 1 护符；
#   - 敌人 HP 抬到极大（不会被打死），每回合把敌人/玩家状态复位，只测「每回合产出与承伤」。
#
# 运行（必须隔离 APPDATA）：
#   set APPDATA=%TEMP%\seek_dead_probe_appdata
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/g7b_p3_compare.tscn
#   可选：-- --seeds=3 --turns=8 --seed=7301
# 产物：docs/baseline/2026-11-09_p3_compare/report.txt
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-09_p3_compare"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const DUMMY_HP := 99999
const BIG_HP := 999999
const BASE_SEED := 7301
const SEEDS := 3
const TURNS := 8
const MAX_WAIT := 16          # 等目标的上限（拍）；超过就强制停，记为 forced

const C_DMG_A := "res://resources/charms/blood_pact.tres"      # 血契：damage_bonus 6（common）
const C_DMG_B := "res://resources/charms/rust_relic.tres"      # 锈蚀核心：damage_bonus 4（common）
const C_DEF_A := "res://resources/charms/guard_charm.tres"     # 守备护符：shield 4（common）
const C_DEF_B := "res://resources/charms/regen_charm.tres"     # 回春护符：heal 6（common）

var _duel: DuelController
var _room: RoomData
var _weapon := ""
var _target_key := ""
var _target_name := ""
var _target_sym := ""
var _base_skills: Array[String] = []
var _seeds := SEEDS
var _turns := TURNS
var _seed0 := BASE_SEED
var _lines: Array[String] = []
var _rows: Array[Dictionary] = []
var _group_rows: Array[String] = []
var _selfcheck_fail := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--seeds="):
			_seeds = maxi(1, int(s.get_slice("=", 1)))
		elif s.begins_with("--turns="):
			_turns = maxi(1, int(s.get_slice("=", 1)))
		elif s.begins_with("--seed="):
			_seed0 = int(s.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_duel = load(DUEL_SCENE).instantiate() as DuelController
	add_child(_duel)
	await _frames(8)
	_duel.board_config.enabled = false
	_duel._confirm_loadout()
	await _frames(6)
	_base_skills = _duel.selected_skills.duplicate()
	_weapon = String(_duel.selected_loadout[0]) if not _duel.selected_loadout.is_empty() else ""
	_room = _pick_room()
	if _room == null or _weapon == "":
		print("G7B_P3|FAIL 夹具初始化失败（room=%s weapon=%s）" % [str(_room), _weapon])
		get_tree().quit(2)
		return

	# 目标符号：先清掉一切运行时成长，再读主武器的调律目标（与游戏内 R2 调律同一口径）。
	_duel._reset_run_state()
	_duel.selected_charms.clear()
	_duel._build_pool(_duel.selected_loadout)
	_resolve_target()

	for g in _groups():
		for i in range(_seeds):
			await _run_seed(g, _seed0 + i)
		_rows_append_group(g)

	_write_report()
	var fails := _selfcheck_fail
	print("G7B_P3|DONE groups=8 seeds=%d turns=%d selfcheck_fail=%d" % [_seeds, _turns, fails])
	get_tree().quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------------------
# 夹具定义
# ---------------------------------------------------------------------------

# ACT1 固定敌人：普通房、无机制（去掉 gimmick 噪声），取名字排序第一间，保证跨机器一致。
# 注：ACT1 的精英房全部挂了课程化 mini 机制（gimmick_script != null），故用普通房做同一敌人夹具；
# 敌人强度写进报告，读者可自行按比例外推。
func _pick_room() -> RoomData:
	var best: RoomData = null
	for r in _duel.ALL_ROOMS:
		if r == null or int(r.act) != 1 or String(r.kind) != "normal":
			continue
		if r.gimmick_script != null:
			continue
		if best == null or String(r.name) < String(best.name):
			best = r
	return best


func _resolve_target() -> void:
	var tgt: Dictionary = _duel.mastery.tune_target(_weapon)
	var sym_path := String(tgt.get("sym", ""))
	var comp: Dictionary = _duel._trim._compose({}, _duel.selected_skills)
	var best_cells := -1
	for r in comp["rows"]:
		if String(r["kind"]) != "damage":
			continue
		if sym_path != "" and String(r["path"]) != sym_path:
			continue
		if int(r["cells"]) > best_cells:
			best_cells = int(r["cells"])
			_target_key = String(r["key"])
			_target_sym = String(r["path"])
			_target_name = String(r["name"])
	if _target_key == "":
		# 调律目标取不到（或不在带里）：退化为带内格数最大的伤害符号
		for r in comp["rows"]:
			if String(r["kind"]) == "damage" and int(r["cells"]) > best_cells:
				best_cells = int(r["cells"])
				_target_key = String(r["key"])
				_target_sym = String(r["path"])
				_target_name = String(r["name"])


func _groups() -> Array:
	var t := _target_sym
	return [
		{"id": "base", "label": "① 无成长·无额外技能", "imprints": [], "charms": [], "trim": false},
		{"id": "forge", "label": "② 仅锋铸", "imprints": [["forge", ""], ["forge", ""]], "charms": [], "trim": false},
		{"id": "tune", "label": "③ 仅调律", "imprints": [["tune", t], ["tune", t]], "charms": [], "trim": false},
		{"id": "trim", "label": "④ 仅精简", "imprints": [], "charms": [], "trim": true},
		{"id": "dmg_buff", "label": "⑤ 仅增伤 Buff", "imprints": [], "charms": [C_DMG_A, C_DMG_B], "trim": false},
		{"id": "def_buff", "label": "⑥ 仅防御/恢复 Buff", "imprints": [], "charms": [C_DEF_A, C_DEF_B], "trim": false},
		{"id": "tune_trim", "label": "⑦ 调律+精简", "imprints": [["tune", t], ["tune", t]], "charms": [], "trim": true},
		{"id": "growth_buff", "label": "⑧ 武器成长+Buff", "imprints": [["forge", ""], ["tune", t]], "charms": [C_DMG_A], "trim": false},
	]


# ---------------------------------------------------------------------------
# 一组 · 一个种子
# ---------------------------------------------------------------------------

func _run_seed(g: Dictionary, s: int) -> void:
	seed(s)
	_duel._reset_run_state()
	_duel.selected_skills.assign(_base_skills.duplicate())
	_duel.selected_charms.assign((g["charms"] as Array).duplicate())
	for imp in g["imprints"]:
		var pair: Array = imp
		_duel.mastery.choose(_weapon, String(pair[0]), String(pair[1]))
	_duel._build_pool(_duel.selected_loadout)
	var trim_applied := false
	if bool(g["trim"]):
		trim_applied = _apply_target_trim()
	_duel.ROOMS = _room_list()
	_duel._start_room(0)
	_duel.player_hp_max = DUMMY_HP
	_duel.player_hp = DUMMY_HP
	var real_hp: int = int(_duel.enemy_hp_max)
	_duel.enemy_hp_max = BIG_HP
	_duel.enemy_hp = BIG_HP
	await _frames(2)

	var row := {
		"group": String(g["id"]), "label": String(g["label"]), "seed": s,
		"trim_applied": trim_applied, "real_enemy_hp": real_hp,
		"band": _band_stats(), "logical": _logical_stats(),
		"turns": 0, "dmg": 0, "taken": 0, "blocked": 0,
		"stops": 0, "hits": 0, "forced": 0, "mech_cols": 0, "wait_sum": 0,
	}
	for i in range(_turns):
		await _one_turn(row)
		_duel.enemy_hp = BIG_HP
		_duel.enemy_armor = _duel.enemy_armor_max   # 每回合视为同一只满甲敌人（护甲不被跨回合磨穿）
		_duel.player_hp = DUMMY_HP
	_rows.append(row)


func _room_list() -> Array[RoomData]:
	var arr: Array[RoomData] = [_room]
	return arr


# 精简：只精简「本次对照的目标符号」，应用后重建池（apply 内部已重建）。
func _apply_target_trim() -> bool:
	for c in _duel._trim.candidates():
		if String(c["kind"]) == "symbol" and String(c["key"]) == _target_key:
			return _duel._trim.apply(c) != ""
	return false


# 目标停轮：每拍看「此刻停会落在哪一格」，是目标就停；超时就强制停。
func _one_turn(row: Dictionary) -> void:
	var t0_taken: int = _duel._telemetry.damage_taken
	var t0_blocked: int = _duel._telemetry.damage_blocked
	var mech := {}
	for r in _duel.frozen_cols:
		mech[int(r)] = true
	if int(_duel.pending_jam_reel) >= 0:
		mech[int(_duel.pending_jam_reel)] = true
	if int(_duel.pending_lock_reel) >= 0:
		mech[int(_duel.pending_lock_reel)] = true

	_duel._on_spin_pressed()
	var seen := {}
	var waited := {0: 0, 1: 0, 2: 0}
	var ours := {}
	var guard := 0
	while guard < 4000:
		guard += 1
		if not _duel._busy:
			break
		if _duel.reel_system.spinning:
			for r in DuelController.REELS:
				if _duel.reel_system.reel_stopped[r] or ours.has(r):
					continue
				if mech.has(r):
					continue   # 机制列（冻结/注废/锁轮）：结果不由目押决定，不计入目标统计
				var strip: Array = _duel.reel_system.reel_strips[r]
				if strip.is_empty():
					continue
				var cur: int = int(_duel.reel_system.reel_cursor[r]) % strip.size()
				if int(seen.get(r, -1)) != cur:
					seen[r] = cur
					waited[r] = int(waited.get(r, 0)) + 1
				if _strip_key(strip[cur]) == _target_key:
					_duel.reel_system.lock_reel(r, false, "player")
					ours[r] = true
				elif int(waited[r]) >= MAX_WAIT:
					_duel.reel_system.lock_reel(r, false, "player")
					ours[r] = true
					row["forced"] = int(row["forced"]) + 1
		await get_tree().process_frame

	row["turns"] = int(row["turns"]) + 1
	row["dmg"] = int(row["dmg"]) + (BIG_HP - int(_duel.enemy_hp))
	row["taken"] = int(row["taken"]) + (_duel._telemetry.damage_taken - t0_taken)
	row["blocked"] = int(row["blocked"]) + (_duel._telemetry.damage_blocked - t0_blocked)
	for r in DuelController.REELS:
		if not ours.has(r):
			row["mech_cols"] = int(row["mech_cols"]) + 1   # 敌人夺轮 / 机制停：不算玩家停
			continue
		row["stops"] = int(row["stops"]) + 1
		row["wait_sum"] = int(row["wait_sum"]) + int(waited[r])
		if _grid_key(r) == _target_key:
			row["hits"] = int(row["hits"]) + 1


# ---------------------------------------------------------------------------
# 带子统计 / 键
# ---------------------------------------------------------------------------

func _band_stats() -> Dictionary:
	var strip: Array = _duel.reel_system.reel_strips[0] if _duel.reel_system.reel_strips.size() > 0 else []
	var out := {"len": strip.size(), "target": 0, "damage": 0, "miss": 0, "gold": 0}
	for c in strip:
		var sym: SymbolData = c[0]
		if sym == null:
			continue
		if _strip_key(c) == _target_key:
			out["target"] = int(out["target"]) + 1
		match String(sym.kind):
			"damage":
				out["damage"] = int(out["damage"]) + 1
			"gold":
				out["gold"] = int(out["gold"]) + 1
			"trash":
				out["miss"] = int(out["miss"]) + 1
	return out


func _strip_key(c: Array) -> String:
	return String(c[0].resource_path) + "|" + String(c[1])


# 「逻辑带」= build_strips 里平铺之前的口径（每符号按权重档位分格）。
# 与「实际带长」分开记：logical 与 trim/调律的真实口径一致，actual 才是玩家转的带子。
func _logical_stats() -> Dictionary:
	var comp: Dictionary = _duel._trim._compose(_duel._trim.trimmed, _duel.selected_skills)
	var out := {"cells": int(comp["total_cells"]), "target": 0, "damage": 0, "miss": int(comp["miss_cells"])}
	for r in comp["rows"]:
		if String(r["key"]) == _target_key:
			out["target"] = int(out["target"]) + int(r["cells"])
		if String(r["kind"]) == "damage":
			out["damage"] = int(out["damage"]) + int(r["cells"])
	return out


func _grid_key(r: int) -> String:
	var sym: SymbolData = _duel.grid[r][0]
	if sym == null:
		return ""
	return String(sym.resource_path) + "|" + String(_duel.grid_elem[r][0])


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------

func _rows_append_group(g: Dictionary) -> void:
	var grp: Array = []
	for r in _rows:
		if String(r["group"]) == String(g["id"]):
			grp.append(r)
	var n := grp.size()
	if n == 0:
		return
	var dmg := 0
	var taken := 0
	var blocked := 0
	var stops := 0
	var hits := 0
	var forced := 0
	var mech := 0
	var wait := 0
	var turns := 0
	for r in grp:
		dmg += int(r["dmg"])
		taken += int(r["taken"])
		blocked += int(r["blocked"])
		stops += int(r["stops"])
		hits += int(r["hits"])
		forced += int(r["forced"])
		mech += int(r["mech_cols"])
		wait += int(r["wait_sum"])
		turns += int(r["turns"])
	var band: Dictionary = grp[0]["band"]
	var lg: Dictionary = grp[0]["logical"]
	_group_rows.append("| %s | %d | %d/%d/%d | %d | %d（%.0f%%） | %.1f | %.2f | %d | %.1f | %.1f |" % [
		String(g["label"]), int(lg["cells"]), int(lg["target"]), int(lg["damage"]), int(lg["miss"]),
		int(band["len"]), int(band["target"]),
		(100.0 * float(band["target"]) / float(maxi(1, int(band["len"])))),
		float(dmg) / float(maxi(1, turns)),
		float(wait) / float(maxi(1, stops)),
		forced,
		float(taken) / float(maxi(1, turns)),
		float(blocked) / float(maxi(1, turns))])


func _write_report() -> void:
	_lines.clear()
	_lines.append("# G7-B B5 · P3 成长与 Buff 对照（夹具读数，不是平衡结论）%s" % Time.get_datetime_string_from_system())
	_lines.append("")
	_lines.append("> **本表只搭框架，不产出结论。** bot 是理想化全信息停轮（看得见逻辑游标、拍级反应），")
	_lines.append("> 绝对伤害/等待拍数不能当真人读数；组间差值只说明「这条轴本身改变了什么」的量级。")
	_lines.append("> 真人测试与 bot 测试必须分开解读（方案 §10 P3 要求）。")
	_lines.append("")
	_lines.append("协议：headless --fixed-fps 60 · 真实平衡（未改 BALANCE / 任何 .tres） · 同一敌人「%s」（%s · 无机制 · 底子 HP %d / 攻 %d） · "
		% [String(_room.name), String(_room.kind), int(_room.hp), int(_room.atk)])
	_lines.append("      玩家假人生命 %d（不测存活） · 敌人 HP 抬到 %d（不会被打死，每回合复位 HP/护甲） · 每组 %d 种子 × %d 回合 · 停轮上限 %d 拍"
		% [DUMMY_HP, BIG_HP, _seeds, _turns, MAX_WAIT])
	_lines.append("操作目标：**同一个指定符号「%s」**（主武器 R2 调律目标；取不到时退化为带内最大伤害符号）" % _target_name)
	_lines.append("主武器：`%s` · 目标键：`%s`" % [_weapon, _target_key])
	_lines.append("种子：%d..%d" % [_seed0, _seed0 + _seeds - 1])
	_lines.append("")
	_lines.append("## 1. 分组对照（%d 种子 × %d 回合合计）" % [_seeds, _turns])
	_lines.append("")
	_lines.append("| 组 | 逻辑带(格) | 逻辑 目标/伤害/MISS | 实际带长 | 实际目标格(占比) | 每回合伤害 | 等待(拍) | 强制停 | 承伤/回合 | 格挡/回合 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|")
	_lines.append_array(_group_rows)
	_lines.append("")
	_lines.append("注：**逻辑带** = `build_strips` 平铺前的口径（trim / 调律直接作用在这里）；**实际带长** = 平铺到 ≥30 格后玩家真正转的带子。")
	_lines.append("    两者必须一起读：减 1 个逻辑格可能让整份平铺多一份（例：15 格 → 13 格，平铺从 2 份变 3 份），")
	_lines.append("    于是「实际目标占比」可能反而下降——这是最小带长量化的真实后果，不是夹具噪声。")
	_lines.append("    等待拍数 = 从开始旋转到按下停止之间，游标经过的格数（越短说明目标越常见/越早出现）。")
	_lines.append("    停中率 = 玩家停轮落点命中目标的列数 ÷ 玩家停轮列数；机制列（冻结/注废/锁轮/敌人夺轮）不计入。")
	_lines.append("    强制停 = 等满 %d 拍仍未出现目标、被迫按停的列数。" % MAX_WAIT)
	_lines.append("    带子取该组第一个种子实测值（三列是同一多重集的洗牌副本，组内各种子格数相同）。")
	_lines.append("")
	_lines.append("## 2. 单种子明细")
	_lines.append("")
	_lines.append("| 组 | 种子 | 逻辑带 目标/总 | 实际带长(目标格) | 每回合伤害 | 等待(拍) | 强制停 | 机制列 | 精简生效 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|")
	for r in _rows:
		var lg: Dictionary = r["logical"]
		var band: Dictionary = r["band"]
		_lines.append("| %s | %d | %d/%d | %d(%d) | %.1f | %.2f | %d | %d | %s |" % [
			String(r["label"]), int(r["seed"]), int(lg["target"]), int(lg["cells"]),
			int(band["len"]), int(band["target"]),
			float(r["dmg"]) / float(maxi(1, int(r["turns"]))),
			float(r["wait_sum"]) / float(maxi(1, int(r["stops"]))),
			int(r["forced"]), int(r["mech_cols"]), "✓" if bool(r["trim_applied"]) else "-"])
	_lines.append("")
	_lines.append("## 3. 夹具自检")
	_lines.append("")
	_lines.append("| 检查 | 结果 |")
	_lines.append("|---|---|")
	var base_target := _logical_of("base", "target")
	var tune_target := _logical_of("tune", "target")
	var trim_target := _logical_of("trim", "target")
	var tt_target := _logical_of("tune_trim", "target")
	_add_check("基础组逻辑带 > 0", _logical_of("base", "cells") > 0)
	_add_check("调律组逻辑目标格 > 基础组（调律真的加格）", tune_target > base_target)
	_add_check_skip("精简组逻辑目标格 = 基础组 - 1（精简真的减 1 格）",
		_trim_any_applied(), trim_target == base_target - 1)
	_add_check_skip("调律+精简组逻辑目标格 = 调律组 - 1",
		_trim_any_applied(), tt_target == tune_target - 1)
	_lines.append("")
	_lines.append("自检口径：全部按**逻辑带**断言（trim/调律的作用点）。实际带长受「平铺到 ≥30 格」影响，")
	_lines.append("可能出现「逻辑目标 -1、实际目标格不变或占比下降」，这种量化后果在第 1 节单列，不当自检失败。")
	_lines.append("")
	_lines.append("## 4. 怎么读 / 不能怎么读")
	_lines.append("")
	_lines.append("- **能读**：同一敌人、同一目标、同一预算下，各轴让「每回合伤害 / 目标等待拍数 / 承伤」往哪边走、大致多少。")
	_lines.append("- **不能读**：绝对 TTK、胜负率、真人停中率。bot 看得见逻辑游标且零反应延迟，真人要看视觉中心+输入延迟。")
	_lines.append("  正因如此，bot 的停中率恒 ≈100%（只在目标出现时才停），该列不列表；真人的停中率才是方案 §11.1 的指标。")
	_lines.append("  同理，三列都停在同一个符号上 = 每回合都必成三连，**每回合伤害是本带构造下的上限口径**，不是操作水平。")
	_lines.append("- **不能读**：显著性。组间差值里有「同种子 RNG 流在第一次不同随机数后分叉」的噪声，种子数也只有 %d。" % _seeds)
	_lines.append("- **也不能读**：构筑结论。这里是「单轴 + 固定敌人 + 固定目标」，不是完整一局的构筑强度。")
	_lines.append("- 判定调律是否被操作/循环成本抵消、Buff 是否普遍最优、精简是否有强迫感 —— **都要真人对局**，本夹具只给方向。")
	_lines.append("")

	var f := FileAccess.open(OUT_DIR + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()


func _logical_of(group_id: String, key: String) -> int:
	for r in _rows:
		if String(r["group"]) == group_id:
			var lg: Dictionary = r["logical"]
			return int(lg.get(key, 0))
	return 0


func _trim_any_applied() -> bool:
	for r in _rows:
		if bool(r["trim_applied"]):
			return true
	return false


func _add_check(name: String, ok: bool) -> void:
	if not ok:
		_selfcheck_fail += 1
	_lines.append("| %s | %s |" % [name, "✓" if ok else "✗"])


func _add_check_skip(name: String, ran: bool, ok: bool) -> void:
	if not ran:
		_lines.append("| %s | 跳过（目标不可精简） |" % name)
		return
	_add_check(name, ok)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
