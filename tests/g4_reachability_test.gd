extends Node

# ============================================================================
# G4-4 可达性过滤与未触发调试测试（2026-11-20）
# 覆盖：可达性判定（事件源是否存在）/ why_not_triggered 优先级 / reachability_report
# 方案 §5.3「固定种子证明不存在'合法展示但整局无法触发'」
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G4-4 REACH FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var c = duel.circuit_system

	# ① 默认配装（fire_sword + dagger，燃=status w5 / 火斩=damage w3 / 匕斩=damage w5）
	duel._build_pool(duel.selected_loadout)
	var r_triple: Dictionary = c.is_reachable("circuit_triple_echo")
	var r_status: Dictionary = c.is_reachable("circuit_status_react")
	var r_pierce: Dictionary = c.is_reachable("circuit_armor_break")
	_ok(bool(r_triple["ok"]), "默认配装三连可达（w5 符号）")
	_ok(bool(r_status["ok"]), "默认配装状态可达（燃=status）")
	_ok(not bool(r_pierce["ok"]) and String(r_pierce["reason"]) == "event_unreachable:no_pierce_source",
		"默认配装破甲不可达（无破甲机制，reason=%s）" % String(r_pierce["reason"]))

	# ② 空池：全部不可达
	duel.pool_items.clear()
	var r_empty: Dictionary = c.is_reachable("circuit_triple_echo")
	_ok(not bool(r_empty["ok"]) and String(r_empty["reason"]) == "event_unreachable:empty_pool",
		"空池时回路不可达")

	# ③ 为什么未触发：可达性优先于等待事件
	duel._build_pool(duel.selected_loadout)
	c.reset_run()
	c.acquire("circuit_armor_break")
	c.equip("circuit_armor_break")
	var why: String = c.why_not_triggered("circuit_armor_break")
	_ok(why.begins_with("event_unreachable:"),
		"破甲回路装备后 why_not_triggered 优先报事件源不可达（%s）" % why)
	_ok(c.why_not_triggered("circuit_triple_echo") == "not_equipped", "未装备回路报 not_equipped")

	# ④ 注入破甲机制后，破甲回路变可达
	duel._item_pierce_map["fire_sword"] = true
	var r_pierce2: Dictionary = c.is_reachable("circuit_armor_break")
	_ok(bool(r_pierce2["ok"]), "有破甲机制武器后破甲回路可达")
	_ok(c.why_not_triggered("circuit_armor_break").begins_with("waiting_for_event"),
		"可达后 why_not_triggered 报等待事件")

	# ⑤ reachability_report 结构（每个回路含 reachable/reason/owned/equipped）
	var report: Dictionary = c.reachability_report()
	_ok(report.size() == 3, "报告覆盖全部 3 个回路")
	for id in report:
		var d: Dictionary = report[id]
		_ok(d.has("reachable") and d.has("reason") and d.has("owned") and d.has("equipped"),
			"报告字段完整：%s" % String(id))
	_ok(bool(report["circuit_armor_break"]["equipped"]), "报告反映装备状态")
	_ok(bool(report["circuit_armor_break"]["owned"]), "报告反映拥有状态")

	# ⑥ 上限用尽仍报上限（可达性 OK 时）
	c.reset_run()
	c.acquire("circuit_triple_echo")
	c.equip("circuit_triple_echo")
	for i in range(2):
		c.try_trigger("triple")   # turn 上限=2；spin 上限=1 故每次触发后重置 spin
		c.reset_spin()
	_ok(c.why_not_triggered("circuit_triple_echo") == "turn_limit",
		"可达且上限用尽时报 turn_limit（%s）" % c.why_not_triggered("circuit_triple_echo"))

	print("G4-4 REACH RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
