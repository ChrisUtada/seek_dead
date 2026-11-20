class_name SymbolEditRules
extends RefCounted

# ============================================================================
# 符号带编辑合法性规则（G3-3，2026-11-20）
#
# 权威方案 §5.2「六类基础操作」+「合法性规则」：
#   集中 / 转化 / 精简 / 添入 / 刻印 / 校准
#   所有卡按「目标、预算、实际变化」过滤，不静默缩卡，不制造死带。
#   集中与转化必须区分：集中扩张循环（总带长变），转化保持循环（总带长不变）。
#
# 🔴 纯规则层：只做只读判定，不写任何状态、不依赖 controller。
# 具体 effect（灌注/精简/刻印/校准/精华添入）共用本框架，保证口径一致。
#
# ctx 约定（全部只读、由调用方传入当前真实状态）：
#   target: String          目标符号 key（路径|元素）
#   cells_before: Dictionary  操作前各 key → 格数
#   cells_after: Dictionary   操作后各 key → 格数
#   damage_after: int         操作后 damage 类符号总格数（>0 才有输出）
#   budget_used: int / budget_max: int   本符号已用预算 / 上限（可选，缺省不检查）
#   total_before / total_after: int      操作前后总带长（集中/转化判定用）
# ============================================================================

const OP_FOCUS := "focus"        # 集中：目标 +N 格，总带长相应变化
const OP_CONVERT := "convert"    # 转化：来源 -N / 目标 +N，总带长不变
const OP_TRIM := "trim"          # 精简：非核心 -N 或移除
const OP_ADD := "add"            # 添入：添加具体新符号（有稀释代价）
const OP_IMPRINT := "imprint"    # 刻印：改目标参数（格数不变）
const OP_CALIBRATE := "calibrate" # 校准：改 MISS/命中（废铁格变化）

const ALL_OPS := [OP_FOCUS, OP_CONVERT, OP_TRIM, OP_ADD, OP_IMPRINT, OP_CALIBRATE]


# 统一入口：返回 {ok: bool, reason: String}。
static func validate(op: String, ctx: Dictionary) -> Dictionary:
	if not ALL_OPS.has(op):
		return _fail("unknown_op:" + op)
	var target: String = String(ctx.get("target", ""))
	if target.is_empty():
		return _fail("missing_target")
	var before: Dictionary = ctx.get("cells_before", {})
	var after: Dictionary = ctx.get("cells_after", {})
	if before.is_empty() and after.is_empty():
		return _fail("no_cells")

	# ① 预算（目标符号已用次数 ≥ 上限 → 拒绝）
	if ctx.has("budget_max") and int(ctx.get("budget_used", 0)) >= int(ctx["budget_max"]):
		return _fail("budget_exhausted")

	# ② 目标必须真实存在（添入除外：添入的目标原本不在带中）
	var b: int = int(before.get(target, 0))
	var a: int = int(after.get(target, 0))
	if op != OP_ADD and b <= 0:
		return _fail("target_not_in_band")

	# ③ 实际变化：按操作类型要求不同的变化方向
	match op:
		OP_FOCUS:
			if a <= b:
				return _fail("no_cell_change")
		OP_CONVERT:
			if a <= b:
				return _fail("no_cell_change")
		OP_TRIM, OP_ADD:
			if a == b and _same_cells(before, after):
				return _fail("no_cell_change")
		OP_IMPRINT, OP_CALIBRATE:
			# 刻印/校准改参数或废铁格，格数可不变；由调用方在 ctx 传 changed 标志
			if ctx.has("param_changed") and not bool(ctx["param_changed"]):
				return _fail("no_param_change")
		_:
			return _fail("unknown_op:" + op)

	# ④ 集中 vs 转化：循环变化语义必须不同（方案硬要求）
	if op == OP_FOCUS and ctx.has("total_before") and ctx.has("total_after"):
		if int(ctx["total_after"]) == int(ctx["total_before"]):
			return _fail("focus_must_expand_band")
	if op == OP_CONVERT and ctx.has("total_before") and ctx.has("total_after"):
		if int(ctx["total_after"]) != int(ctx["total_before"]):
			return _fail("convert_must_keep_band_length")

	# ⑤ 不制造死带：操作后仍有有效输出符号
	if ctx.has("damage_after") and int(ctx["damage_after"]) <= 0:
		return _fail("no_damage_left")

	return {"ok": true, "reason": ""}


static func _same_cells(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if int(a[k]) != int(b.get(k, 0)):
			return false
	return true


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
