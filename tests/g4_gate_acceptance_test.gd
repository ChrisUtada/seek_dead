extends Node

# ============================================================================
# G4-6 rule_mod 启用门槛验收（2026-11-20）
# 方案 §5.3 五条门槛：
#  ① ≥6 机制不同回路、≥4 类组合条件
#  ② 每回路有可达性过滤/真实结算/独立反馈/递归测试
#  ③ 构筑摘要能查看/比较/替换回路
#  ④ 固定种子证明无"合法展示但整局无法触发"
#  ⑤ 2 槽替换流程 + 输出曲线通过验收
# 🔴 本测试只验技术可验项；④⑤需 rule_mod 恢复后的真实游玩数据，当前回路未进卡池故标记待验证。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G4-6 GATE FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var c = duel.circuit_system

	# 门槛①：≥6 回路、≥4 类组合条件
	var defs: Dictionary = CircuitSystem.DEFINITIONS
	_ok(defs.size() >= 6, "门槛①：定义 6 个回路（%d）" % defs.size())
	var classes := {}
	var seen_event := {}
	var seen_payout := {}
	for id in defs:
		var d: Dictionary = defs[id]
		classes[String(d.get("combo_class", ""))] = true
		var ev: String = String(d.get("event", ""))
		_ok(not seen_event.has(ev), "门槛①：事件机制不同（%s）" % ev)
		seen_event[ev] = true
		seen_payout[String(d.get("payout", ""))] = true
		_ok(bool(d.get("chain")) == false, "门槛②：回路 chain=false（%s）" % String(id))
	_ok(classes.size() >= 4, "门槛①：≥4 类组合条件（%d 类：%s）" % [classes.size(), str(classes.keys())])
	_ok(seen_payout.size() >= 6, "门槛①：赔付方式差异（%d 种）" % seen_payout.size())

	# 门槛②：可达性过滤（每回路都能判定）+ 递归防护字段
	for id in defs:
		var r: Dictionary = c.is_reachable(String(id))
		_ok(r.has("ok") and r.has("reason"), "门槛②：可达性判定可用（%s）" % String(id))
	_ok(not c._resolving, "门槛②：初始非递归态")

	# 门槛③：2 槽替换流程（查看/比较/替换）
	c.reset_run()
	for id in defs:
		c.acquire(String(id))
	_ok(c.equip("circuit_triple_echo").ok, "门槛③：装备回路1")
	_ok(c.equip("circuit_status_react").ok, "门槛③：装备回路2")
	_ok(c.equipped.size() == 2, "门槛③：槽上限 2")
	var rep: Dictionary = c.equip("circuit_pair", "circuit_triple_echo")
	_ok(rep.ok and c.equipped.has("circuit_pair") and not c.equipped.has("circuit_triple_echo"),
		"门槛③：槽满可替换并给出结果")
	var report: Dictionary = c.reachability_report()["circuits"]
	for id in report:
		var d: Dictionary = report[id]
		_ok(d.has("combo_class"), "门槛③：构筑摘要含组合类（%s）" % String(id))

	# 门槛④⑤：固定种子无死回路 + 输出曲线 —— 当前回路未进卡池，标记为"技术就绪/待真实游玩验证"
	# 这里验证的是"可达性报告能识别死回路"这一能力本身（固定构筑下不可达的回路被标记）
	duel._build_pool(duel.selected_loadout)
	var rr: Dictionary = c.reachability_report()
	_ok(rr.has("reachable_count") and rr.has("total"), "门槛④：可达性汇总含计数")
	_ok(int(rr["total"]) == 6, "门槛④：汇总覆盖 6 回路")
	# 默认构筑下破甲回路不可达 → 证明"死回路可被识别"（不是静默展示）
	var armor: Dictionary = rr["circuits"]["circuit_armor_break"]
	_ok(not bool(armor["reachable"]) and String(armor["reason"]).begins_with("event_unreachable"),
		"门槛④：不可达回路被明确标记（非静默展示）")

	print("G4-6 GATE RESULT: %d checks, %d fails" % [_checks, _fails])
	print("G4-6 GATE NOTE: 门槛④⑤的输出曲线验收需 rule_mod 恢复后真实游玩验证；当前 rule_mod 保持禁用")
	get_tree().quit(1 if _fails > 0 else 0)
