extends Node

# ============================================================================
# G4-3 回路赔付落地测试（2026-11-20）：回路真正改变结算结果
# 覆盖：三连回响→dmg / 状态反应→status_stacks / 破甲余波→pierce
# 递归防护（回路追加结果不二次触发）
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G4-3 PAYOUT FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var c = duel.circuit_system
	var combat = duel.combat

	# ① 三连回响：triple 事件 → acc.dmg 增加
	c.reset_run()
	c.acquire("circuit_triple_echo")
	c.equip("circuit_triple_echo")
	var acc1 := combat._new_acc()
	acc1["triple"] = true
	acc1["dmg"] = 10.0
	combat._apply_circuits(acc1)
	_ok(float(acc1["dmg"]) > 10.0, "三连回响提升 dmg（10 → %.1f）" % float(acc1["dmg"]))
	_ok(c.log.size() == 1 and String(c.log[0]["event"]) == "triple", "三连回响写入来源日志")

	# ② 状态反应：status_applied 事件 → status_stacks 增加
	c.reset_run()
	c.acquire("circuit_status_react")
	c.equip("circuit_status_react")
	var acc2 := combat._new_acc()
	acc2["status_stacks"] = {"burn": 2}
	combat._apply_circuits(acc2)
	_ok(int(acc2["status_stacks"]["burn"]) > 2, "状态反应提升层数（2 → %d）" % int(acc2["status_stacks"]["burn"]))

	# ③ 破甲余波：armor_broken 事件 → acc.pierce 增加
	c.reset_run()
	c.acquire("circuit_armor_break")
	c.equip("circuit_armor_break")
	var acc3 := combat._new_acc()
	acc3["armor_broken"] = true
	combat._apply_circuits(acc3)
	_ok(float(acc3["pierce"]) > 0.0, "破甲余波提升穿透（%.1f）" % float(acc3["pierce"]))

	# ④ 三个回路同时装备，一次回合各事件独立触发
	c.reset_run()
	for id in ["circuit_triple_echo", "circuit_status_react"]:
		c.acquire(id)
		c.equip(id)
	var acc4 := combat._new_acc()
	acc4["triple"] = true
	acc4["status_stacks"] = {"burn": 1}
	combat._apply_circuits(acc4)
	_ok(float(acc4["dmg"]) > 0.0 and int(acc4["status_stacks"]["burn"]) > 1,
		"多回路同时触发：dmg 与状态各自提升")
	_ok(c.log.size() == 2, "多回路各写一条来源日志（%d）" % c.log.size())

	# ⑤ 递归防护：赔付应用期间不二次触发（log 不膨胀）
	var log_before: int = c.log.size()
	c.begin_resolve()
	c.try_trigger("triple")
	c.end_resolve()
	_ok(c.log.size() == log_before, "begin_resolve 期间 try_trigger 不记日志（防递归）")

	# ⑥ 无事件不触发
	c.reset_run()
	c.acquire("circuit_triple_echo")
	c.equip("circuit_triple_echo")
	var acc6 := combat._new_acc()
	combat._apply_circuits(acc6)
	_ok(is_zero_approx(float(acc6["dmg"])) and c.log.is_empty(), "无原始事件时不触发回路")

	print("G4-3 PAYOUT RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
