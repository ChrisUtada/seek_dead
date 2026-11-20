extends Node

# ============================================================================
# G4-2 回路核心测试（2026-11-20）：回路状态 / 2槽替换 / 触发限制 / 来源日志
# 权威方案 §5.3 + G4-2。覆盖：
# ① 仓库 acquire / 2槽 equip / 槽满替换 / 防伪造
# ② 触发：白名单事件、上限（SPIN/回合/房间）、递归防护
# ③ 来源日志 + "为什么未触发"调试信息
# ④ 生命周期 reset
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G4-2 CIRCUIT FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var c = duel.circuit_system

	# ① 仓库/槽
	_ok(c.inventory.is_empty() and c.equipped.is_empty(), "初始仓库与槽为空")
	_ok(not c.acquire("nonexistent"), "未定义回路不能 acquire")
	_ok(c.acquire("circuit_triple_echo"), "acquire 回响")
	_ok(c.acquire("circuit_status_react"), "acquire 状态反应")
	_ok(c.acquire("circuit_armor_break"), "acquire 破甲余波")
	_ok(not c.acquire("circuit_triple_echo"), "重复 acquire 拒绝")
	_ok(not c.equip("nonexistent").ok, "未拥有回路不能装备")

	_ok(c.equip("circuit_triple_echo").ok, "装槽1")
	_ok(c.equip("circuit_status_react").ok, "装槽2")
	_ok(c.equipped.size() == 2, "槽满=2")
	var need: Dictionary = c.equip("circuit_armor_break")
	_ok(not need.ok and String(need["reason"]) == "need_replace", "槽满须指定替换")
	var rep: Dictionary = c.equip("circuit_armor_break", "circuit_triple_echo")
	_ok(rep.ok and not c.equipped.has("circuit_triple_echo") and c.equipped.has("circuit_armor_break"),
		"替换生效：换下回响装上破甲")

	# ② 触发：事件白名单 + 上限
	c.equipped.clear()
	c.equip("circuit_triple_echo")
	_ok(c.try_trigger("status_applied").is_empty(), "事件不匹配不触发")
	var fire1: Array = c.try_trigger("triple")
	_ok(fire1.size() == 1 and String(fire1[0]) == "circuit_triple_echo", "triple 事件触发")
	# 回响 spin 上限=1：同一 SPIN 再触发应被拒
	_ok(c.try_trigger("triple").is_empty(), "SPIN 上限拒绝第2次")
	c.reset_spin()
	_ok(c.try_trigger("triple").size() == 1, "reset_spin 后恢复")

	# ③ 递归防护
	c.begin_resolve()
	_ok(c.try_trigger("triple").is_empty(), "递归防护：结算追加结果不触发")
	c.end_resolve()
	c.reset_turn()   # turn 上限=2，已触发2次，须先重置回合计数
	_ok(c.try_trigger("triple").size() == 1, "end_resolve 后恢复")

	# ④ 来源日志 + 调试信息
	_ok(c.log.size() >= 2, "来源日志记录每次成功触发（%d）" % c.log.size())
	_ok(String(c.log[0]["event"]) == "triple" and not String(c.log[0]["id"]).is_empty(),
		"日志含 id/event/spin/turn/room")
	var why: String = c.why_not_triggered("circuit_triple_echo")
	_ok(why.begins_with("spin_limit") or why.begins_with("turn_limit") or why.begins_with("waiting"),
		"调试信息：上限后显示上限原因或等待事件（%s）" % why)
	_ok(String(c.why_not_triggered("circuit_status_react")) == "not_equipped", "未装备回路显示 not_equipped")

	# ⑤ 生命周期
	c.reset_turn()
	_ok(c.try_trigger("triple").size() == 1, "reset_turn 后回合上限恢复")
	c.reset_run()
	_ok(c.inventory.is_empty() and c.equipped.is_empty() and c.log.is_empty(), "reset_run 全清")

	print("G4-2 CIRCUIT RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
