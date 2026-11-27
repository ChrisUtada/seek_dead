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

	# ① 默认配装（2026-11-27 starter：fire_sword + battle_axe；燃=status w5 / 火斩=damage w3 /
	#    斧斩=damage w5(element none) / 回复=light w1）。铁剑不在默认配装内，但战斧是重武器，
	#    斧斩 5 格 ≥3 满足破甲兜底，故破甲回路在默认配装下**可达**；异色协奏仍不可达（非 none 元素只有 fire/light 两种）。
	duel._build_pool(duel.selected_loadout)
	var r_triple: Dictionary = c.is_reachable("circuit_triple_echo")
	var r_status: Dictionary = c.is_reachable("circuit_status_react")
	var r_pierce: Dictionary = c.is_reachable("circuit_armor_break")
	var r_color: Dictionary = c.is_reachable("circuit_tri_color")
	_ok(bool(r_triple["ok"]), "默认配装三连可达（w5 符号）")
	_ok(bool(r_status["ok"]), "默认配装状态可达（燃=status）")
	_ok(bool(r_pierce["ok"]), "默认配装破甲可达（战斧重武器三连兜底，reason=%s）" % String(r_pierce["reason"]))
	_ok(not bool(r_color["ok"]) and String(r_color["reason"]) == "event_unreachable:no_tri_color_source",
		"默认配装异色协奏不可达（非 none 元素不足 3 种，reason=%s）" % String(r_color["reason"]))

	# ② 空池：全部不可达
	duel.pool_items.clear()
	var r_empty: Dictionary = c.is_reachable("circuit_triple_echo")
	_ok(not bool(r_empty["ok"]) and String(r_empty["reason"]) == "event_unreachable:empty_pool",
		"空池时回路不可达")

	# ③ 为什么未触发：可达性优先于等待事件（用仍不可达的异色协奏做样本）
	duel._build_pool(duel.selected_loadout)
	c.reset_run()
	c.acquire("circuit_tri_color")
	c.equip("circuit_tri_color")
	var why: String = c.why_not_triggered("circuit_tri_color")
	_ok(why.begins_with("event_unreachable:"),
		"异色协奏装备后 why_not_triggered 优先报事件源不可达（%s）" % why)
	_ok(c.why_not_triggered("circuit_triple_echo") == "not_equipped", "未装备回路报 not_equipped")

	# ④ 注入第三种元素后，异色协奏变可达
	var ice_sym: SymbolData = load("res://resources/symbols/ice_crystal.tres")
	duel.pool_items.append({"syms": [[ice_sym, 3.0, "ice", ""]]})
	var r_color2: Dictionary = c.is_reachable("circuit_tri_color")
	_ok(bool(r_color2["ok"]), "注入第三种元素后异色协奏可达（reason=%s）" % String(r_color2["reason"]))
	_ok(c.why_not_triggered("circuit_tri_color").begins_with("waiting_for_event"),
		"可达后 why_not_triggered 报等待事件")

	# ⑤ reachability_report 结构（G4-6 升级：顶层 total/combo_classes + circuits 子字典）
	# 报告需反映装备/拥有：补装备破甲回路（2 槽：异色协奏 + 破甲余波）。
	c.acquire("circuit_armor_break")
	c.equip("circuit_armor_break")
	var report: Dictionary = c.reachability_report()
	var circuits: Dictionary = report["circuits"]
	_ok(int(report["total"]) == 6, "报告覆盖全部 6 个回路")
	_ok(circuits.size() == 6, "circuits 子字典含 6 项")
	for id in circuits:
		var d: Dictionary = circuits[id]
		_ok(d.has("reachable") and d.has("reason") and d.has("owned") and d.has("equipped") and d.has("combo_class"),
			"报告字段完整：%s" % String(id))
	_ok(bool(circuits["circuit_armor_break"]["equipped"]), "报告反映装备状态")
	_ok(bool(circuits["circuit_armor_break"]["owned"]), "报告反映拥有状态")
	# G4-6 门槛①：≥6 回路、≥4 类组合条件
	_ok(int(report["total"]) >= 6, "门槛①：回路数 ≥6（%d）" % int(report["total"]))
	_ok(int(report["combo_class_count"]) >= 4, "门槛①：组合条件类数 ≥4（%d）" % int(report["combo_class_count"]))

	# ⑥ 上限用尽仍报上限（可达性 OK 时）
	c.reset_run()
	c.acquire("circuit_triple_echo")
	c.equip("circuit_triple_echo")
	for i in range(2):
		c.try_trigger("triple")   # turn 上限=2；spin 上限=1 故每次触发后重置 spin
		c.reset_spin()
	_ok(c.why_not_triggered("circuit_triple_echo") == "turn_limit",
		"可达且上限用尽时报 turn_limit（%s）" % c.why_not_triggered("circuit_triple_echo"))

	# ⑦ 2026-11-21 对子可达性 false negative 修复专项（评审裁定保持真实结算语义）：
	#    真实 _has_pair_damage = 「某 damage 族恰 2 格 + 另一个不同的有效符号族 ≥1 格（任意 kind）」。
	#    可达性报告须与真实语义对齐：damage 族 + 任意不同第三族即视为可达。
	var pair_cases := [
		{"name": "伤害对子+状态(暴雪法杖)", "weapon": "res://resources/weapon_templates/blizzard_staff.tres",
		 "dmg": "res://resources/symbols/ice_crystal.tres", "third": "res://resources/symbols/frost.tres", "third_kind": "status"},
		{"name": "伤害对子+护盾(坚壁钉锤)", "weapon": "res://resources/weapon_templates/mace.tres",
		 "dmg": "res://resources/symbols/iron_slash.tres", "third": "res://resources/symbols/iron_wall.tres", "third_kind": "shield"},
		{"name": "两个伤害族(双式军刀)", "weapon": "res://resources/weapon_templates/dueling_saber.tres",
		 "dmg": "res://resources/symbols/iron_slash.tres", "third": "res://resources/symbols/dagger_slash.tres", "third_kind": "damage"},
	]
	for pc in pair_cases:
		duel.selected_loadout.clear()
		duel.selected_loadout.append(String(pc["weapon"]))
		duel._confirm_loadout()
		duel._build_pool(duel.selected_loadout)
		var pr: Dictionary = c.is_reachable("circuit_pair")
		_ok(bool(pr["ok"]), "对子可达性 %s：报告可达（reason=%s）" % [
			String(pc["name"]), String(pr.get("reason", ""))])
		# 真实结算判定：构造 counts（某 damage 族恰 2 格 + 第三符号 1 格）
		var dsym: Resource = load(String(pc["dmg"]))
		var tsym: Resource = load(String(pc["third"]))
		var dkey: String = String(dsym.resource_path) + "|" + String(dsym.element)
		var tkey: String = String(tsym.resource_path) + "|" + String(tsym.element)
		var counts := {}
		counts[dkey] = [dsym, String(dsym.element), 2, {"src": 2}]
		counts[tkey] = [tsym, String(tsym.element), 1, {"src": 1}]
		_ok(duel.combat._has_pair_damage(counts),
			"对子真实判定 %s：damage 对子 + %s 触发" % [String(pc["name"]), String(pc["third_kind"])])

	print("G4-4 REACH RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
