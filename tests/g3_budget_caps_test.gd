extends Node

# ============================================================================
# G3-5 参数契约测试（2026-11-20）：最小带长 / 预算 / 每符号上限 / 无隐藏补偿
# 权威方案 G3-5 + §5.2「如果整数化导致波动，用 36 格对照；不得两套口径并存」
#
# 覆盖：
# ① 每符号格数上限 MAX_SYMBOL_CELLS=8（G3-1 原型依据）
# ② 最小带长 30，整份平铺不改占比
# ③ 灌注预算（增量上限 6 / 单次 +3 / 最多 2 次）
# ④ 无隐藏补偿：预览总格数 == 实际建带长度（同一口径，无暗中平衡系数）
# ⑤ 连续改造仍有真实变化（G3 出口判据）
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G3-5 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame

	# ① 每符号上限 8：w=5 灌 +6 → w=11 → clamp 到 8
	_ok(ReelSystem.MAX_SYMBOL_CELLS == 8, "MAX_SYMBOL_CELLS=8（G3-1 原型值正式化）")
	_ok(ReelSystem.cells_for(11.0) == 8, "w=11 封顶 8 格")
	_ok(ReelSystem.cells_for(8.0) == 8, "w=8 = 8 格")
	_ok(ReelSystem.cells_for(5.0) == 5, "w=5 = 5 格（未封顶）")

	# ② 最小带长 30 + 整份平铺不改占比
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres"])
	duel._build_pool(duel.selected_loadout)
	duel.reel_system.build_strips()
	var strip: Array = duel.reel_system.reel_strips[0]
	_ok(strip.size() >= 30, "带长 ≥ 最小带长 30（实际 %d）" % strip.size())
	# 占比不变：用 unit 格数按 30 平铺公式算，与实际一致
	var comp: Dictionary = ReelPreview.compose(duel.selected_loadout, duel.selected_skills, duel.selected_charms,
		[], duel._reward_system.run_symbol_bonus, duel.deprived_level, false, 0,
		duel.mastery.tune_map(), duel._forge_styles.preview_map() if duel._forge_styles != null else {}, {})
	var unit: int = int(comp["symbol_cells"]) + int(comp["miss_cells"]) + int(comp["gold_cells"]) + int(comp["trash_cells"])
	_ok(strip.size() == StripTrimSystem.actual_len(unit),
		"实际带长 == 整份平铺公式（%d vs %d，占比不变）" % [strip.size(), StripTrimSystem.actual_len(unit)])

	# ③ 灌注预算：增量 6 / 单次 3 / 最多 2 次
	_ok(duel._reward_system.SYMBOL_WEIGHT_STEP == 3, "单次灌注增量 3")
	_ok(duel._reward_system.SYMBOL_WEIGHT_MAX == 6, "灌注增量上限 6（2 次×3）")
	var sym_defs: Array = duel._reward_system._make_symbol_weight_defs()
	_ok(not sym_defs.is_empty(), "有符号灌注候选")

	# ④ 无隐藏补偿：预览 symbol_cells == 建带符号格数（同一 cells_for 口径）
	var sym_cells_in_strip := 0
	for entry in strip:
		var e = entry[0] if entry is Array else entry
		if e == null:
			continue
		var ep: String = String(e.resource_path) if e is Resource else ""
		if String(e.kind) != "trash" and ep != String(DuelController.GOLD_SYMBOL.resource_path):
			sym_cells_in_strip += 1
	# 建带含 miss/gold/trash，symbol_cells 仅符号格；用占比一致性间接验证无暗中补偿
	var ratio_preview: float = float(comp["symbol_cells"]) / float(unit)
	var ratio_actual: float = float(sym_cells_in_strip) / float(strip.size())
	_ok(absf(ratio_preview - ratio_actual) < 0.001,
		"符号占比预览=实际（%.3f vs %.3f，无隐藏补偿）" % [ratio_preview, ratio_actual])

	# ⑤ 连续改造有真实变化：灌 2 次，每次格数都增加
	var spath: String = String(sym_defs[0].effects[0].get("params", {}).get("path", ""))
	var sym: SymbolData = load(spath)
	if sym != null:
		var c0: int = duel._reward_system._symbol_cells(sym, 0.0)
		var c1: int = duel._reward_system._symbol_cells(sym, 3.0)
		var c2: int = duel._reward_system._symbol_cells(sym, 6.0)
		_ok(c1 > c0 or c1 == ReelSystem.MAX_SYMBOL_CELLS, "第 1 次灌注有变化或已封顶（%d→%d）" % [c0, c1])
		_ok(c2 > c1 or c2 == ReelSystem.MAX_SYMBOL_CELLS, "第 2 次灌注有变化或已封顶（%d→%d）" % [c1, c2])

	print("G3-5 PARAMS RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
