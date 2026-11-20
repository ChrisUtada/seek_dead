extends Node

# ============================================================================
# G3-3 符号带编辑合法性规则测试（2026-11-20）
# 覆盖权威方案 §5.2 六类操作的共同规则：目标/预算/实际变化/不制造死带/集中≠转化
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G3-3 RULES FAIL: " + label)


func _ready() -> void:
	var before := {"fire|fire": 5, "burn|fire": 3, "heal|none": 1}

	# ① 集中：目标格数增加 + 总带长变化 → 合法
	var focus_ctx := {
		"target": "fire|fire", "cells_before": before,
		"cells_after": {"fire|fire": 7, "burn|fire": 3, "heal|none": 1},
		"total_before": 9, "total_after": 11, "damage_after": 10,
	}
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_FOCUS, focus_ctx).ok, "focus 扩张循环合法")

	# ② 集中总长不变 → 拒绝（集中≠转化）
	var focus_same := focus_ctx.duplicate()
	focus_same["total_after"] = 9
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_FOCUS, focus_same)["reason"]) == "focus_must_expand_band",
		"focus 不改总长被拒")

	# ③ 转化：总长不变、目标增加 → 合法
	var convert_ctx := {
		"target": "fire|fire", "cells_before": before,
		"cells_after": {"fire|fire": 7, "burn|fire": 1, "heal|none": 1},
		"total_before": 9, "total_after": 9, "damage_after": 8,
	}
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_CONVERT, convert_ctx).ok, "convert 保持循环合法")

	# ④ 转化改了总长 → 拒绝
	var conv_expand := convert_ctx.duplicate()
	conv_expand["total_after"] = 11
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_CONVERT, conv_expand)["reason"]) == "convert_must_keep_band_length",
		"convert 改总长被拒")

	# ⑤ 实际变化：目标格数没变 → 拒绝
	var no_change := convert_ctx.duplicate()
	no_change["cells_after"] = before.duplicate()
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_CONVERT, no_change)["reason"]) == "no_cell_change",
		"目标格数不变被拒（no_cell_change）")

	# ⑥ 预算耗尽 → 拒绝
	var budget_ctx := convert_ctx.duplicate()
	budget_ctx["budget_used"] = 2
	budget_ctx["budget_max"] = 2
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_CONVERT, budget_ctx)["reason"]) == "budget_exhausted",
		"预算耗尽被拒")

	# ⑦ 不制造死带：操作后无 damage → 拒绝
	var dead_band := convert_ctx.duplicate()
	dead_band["damage_after"] = 0
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_CONVERT, dead_band)["reason"]) == "no_damage_left",
		"制造死带被拒")

	# ⑧ 精简：目标格数减少 → 合法
	var trim_ctx := {
		"target": "fire|fire", "cells_before": before,
		"cells_after": {"fire|fire": 4, "burn|fire": 3, "heal|none": 1},
		"damage_after": 7,
	}
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_TRIM, trim_ctx).ok, "trim 合法")

	# ⑨ 添入：目标原本不在带中 → 合法（不检查 target_not_in_band）
	var add_ctx := {
		"target": "new|fire", "cells_before": before,
		"cells_after": {"fire|fire": 5, "burn|fire": 3, "heal|none": 1, "new|fire": 2},
		"damage_after": 10,
	}
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_ADD, add_ctx).ok, "add 添入新符号合法")

	# ⑩ 刻印/校准：格数不变但参数变化 → 合法
	var param_ctx := {
		"target": "fire|fire", "cells_before": before, "cells_after": before.duplicate(),
		"param_changed": true, "damage_after": 9,
	}
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_IMPRINT, param_ctx).ok, "imprint 参数变化合法")
	_ok(SymbolEditRules.validate(SymbolEditRules.OP_CALIBRATE, param_ctx).ok, "calibrate 参数变化合法")

	# ⑪ 刻印参数未变 → 拒绝
	var param_same := param_ctx.duplicate()
	param_same["param_changed"] = false
	_ok(String(SymbolEditRules.validate(SymbolEditRules.OP_IMPRINT, param_same)["reason"]) == "no_param_change",
		"刻印参数无变化被拒")

	# ⑫ 未知操作 → 拒绝
	_ok(not SymbolEditRules.validate("unknown_op", focus_ctx).ok, "未知操作被拒")

	print("G3-3 RULES RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
