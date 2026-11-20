extends Node

# ============================================================================
# G7-5 新手引导与辅助选项测试（2026-11-20）
# 方案 §11.4 首局四件事（不弹窗，一次性）+ §11.3 辅助来源与奖励遥测分开记录。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7-5 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	var ob = duel.onboarding
	_ok(ob != null, "OnboardingAssist 已注入")
	# 清空引导进度，保证测试从干净状态开始
	duel.meta["onboarding"] = {"shown": {}}

	# ① 四件事提示一次性
	for id in ["stop", "weapon", "draft", "intent"]:
		_ok(not ob.is_shown(id), "%s 初始未提示" % id)
		_ok(ob.hint(id), "%s 首次提示成功" % id)
		_ok(ob.is_shown(id), "%s 标记已提示" % id)
		_ok(not ob.hint(id), "%s 不重复提示" % id)
	_ok(ob.all_done(), "四件事全提示完")

	# ② contextual 提示（遇到时才解释）
	duel.meta["onboarding"] = {"shown": {}}
	_ok(ob.hint("circuit"), "回路 contextual 提示")
	_ok(ob.hint("forge_style"), "铸式 contextual 提示")
	_ok(ob.hint("signature"), "签名 contextual 提示")
	_ok(not ob.all_done(), "contextual 不算入首局四件事")

	# ③ 辅助来源标注：默认
	duel.meta["onboarding"] = {"shown": {}}
	duel.reel_controls.clear()
	duel.readability.apply_preset("control")
	_ok(ob.assist_source() == "default", "默认来源 default（%s）" % ob.assist_source())

	# ④ 辅助来源：assist（readable 预设）
	duel.readability.apply_preset("readable")
	_ok(ob.assist_source() == "assist", "辅助预设来源 assist（%s）" % ob.assist_source())
	var snap: Dictionary = ob.assist_snapshot()
	_ok(snap.get("source") == "assist" and snap.has("preset"), "辅助快照结构正确")

	# ⑤ 辅助来源：reward（slow_ramp 奖励卡 + control 预设）
	duel.readability.apply_preset("control")
	duel.reel_controls["slow_ramp"] = true
	_ok(ob.assist_source() == "reward", "奖励卡来源 reward（%s）" % ob.assist_source())

	# ⑥ 遥测 assist 字段（与奖励数据分开）
	duel._telemetry.assist_snapshot = ob.assist_snapshot()
	var t2: Dictionary = duel._telemetry.summary()
	_ok((t2["assist"] as Dictionary).has("source"), "遥测 assist 含来源")

	print("G7-5 ONBOARDING RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
