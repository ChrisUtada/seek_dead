extends Node

# ============================================================================
# G5-3 回路上线三选一池测试（2026-11-20）
# 覆盖：6 回路卡进池 / circuit_acquire 结算进仓库 / 重复拒绝 /
# 已拥有过滤 / 2 槽装备 / 构筑摘要可达性
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G5-3 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var rs = duel._reward_system
	var c = duel.circuit_system

	# ① 6 张回路卡都被注册表加载且合法
	var defs: Array = RewardRegistry.load_valid()
	var circuit_defs := {}
	for d in defs:
		if String(d.category) == "rule_mod":
			circuit_defs[String(d.id)] = d
	_ok(circuit_defs.size() == 6, "6 张 rule_mod 回路卡合法（%d）" % circuit_defs.size())
	for cid in CircuitSystem.DEFINITIONS:
		_ok(circuit_defs.has(String(cid)), "回路卡存在：%s" % String(cid))

	# ② 回路卡进池：composer 多次抽取应能产出 rule_mod 卡
	duel._build_pool(duel.selected_loadout)
	var circuit_seen := 0
	for i in range(20):
		var draft: DraftResult = rs._draft_composer.compose(RunStateAnalyzer.capture(duel), 3, false)
		for d in draft.rewards:
			var ddef: RewardDefinition = d
			if ddef != null and String(ddef.category) == "rule_mod":
				circuit_seen += 1
	_ok(circuit_seen > 0, "回路卡可进池（20 次抽取中出现 %d 次）" % circuit_seen)

	# ③ circuit_acquire 结算：写入仓库，不自动装备
	var def_triple: RewardDefinition = circuit_defs["circuit_triple_echo"]
	var res = rs._draft_resolver.resolve(def_triple)
	_ok(bool(res.ok), "回路卡 resolve 成功（%s）" % String(res.reason))
	_ok(c.inventory.has("circuit_triple_echo"), "结算后回路进仓库")
	_ok(not c.equipped.has("circuit_triple_echo"), "结算后不自动装备（玩家自选 2 槽）")

	# ④ 重复获得被拒
	var dup = rs._draft_resolver.resolve(def_triple)
	_ok(not bool(dup.ok), "重复获得回路被拒（%s）" % String(dup.reason))

	# ⑤ 另一张回路可继续获得 + 2 槽装备
	var def_pair: RewardDefinition = circuit_defs["circuit_pair"]
	var res2 = rs._draft_resolver.resolve(def_pair)
	_ok(bool(res2.ok), "第二张回路可获得")
	_ok(c.inventory.size() == 2, "仓库有 2 张回路")
	_ok(c.equip("circuit_triple_echo").ok, "装备回路1")
	_ok(c.equip("circuit_pair").ok, "装备回路2")
	_ok(c.equipped.size() == 2, "2 槽满")

	# ⑥ 构筑摘要可达性（rechability_report）
	duel._build_pool(duel.selected_loadout)
	var report: Dictionary = c.reachability_report()
	_ok(int(report["total"]) == 6, "构筑摘要覆盖 6 回路")
	_ok(report["circuits"].has("circuit_triple_echo"), "摘要含已装备回路")

	# ⑦ 新局清零
	duel._reset_run_state()
	_ok(c.inventory.is_empty() and c.equipped.is_empty(), "新局回路仓库/槽清零")

	print("G5-3 CIRCUIT REWARD RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
