extends Node

# 充能门控微探针：直接驱动 CombatSystem.contribute 验证 A+B 调参规则
# ① 单格擦边克制(raw=1)：不充能、不计核爆标记
# ② 同符号双连(raw=2)+克制：充能+1 且计核爆标记
# ③ 元素三连(_elem_triple)+单格克制：充能+1
# ④ 非克制：一律不充能
# ⑤ 阈值：charge_max=6

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres", "res://resources/weapon_templates/holy_sword.tres"])
	duel._confirm_loadout()
	duel.enemy_element = "ice"   # 火克冰：火系符号必克制
	var fire_sym: SymbolData = null
	for p in duel.pool:
		if p[0].kind == "damage" and p[2] == "fire":
			fire_sym = p[0]
			break
	_check(fire_sym != null, "找到火系伤害符号")
	duel.deprived_level = 0
	duel.charm_element_boost = 0.0

	duel.charge_points = 0
	var acc := {"dmg": 0, "special": 0, "pierce": 0.0, "shield": 0, "heal": 0, "status_stacks": {}, "lines": [], "counter_triple": false, "triple": false, "heal_triple": false}
	duel.combat.contribute(fire_sym, 1, acc, "fire")
	_check(duel.charge_points == 0, "① 单格擦边克制不充能（实测 +%d）" % duel.charge_points)
	_check(acc["counter_triple"] == false, "① 不计核爆标记")

	duel.charge_points = 0
	acc = {"dmg": 0, "special": 0, "pierce": 0.0, "shield": 0, "heal": 0, "status_stacks": {}, "lines": [], "counter_triple": false, "triple": false, "heal_triple": false}
	duel.combat.contribute(fire_sym, 2, acc, "fire")
	_check(duel.charge_points == 1, "② 双连克制充能 +1")
	_check(acc["counter_triple"] == true, "② 计核爆标记")

	duel.charge_points = 0
	duel._elem_triple = true
	acc = {"dmg": 0, "special": 0, "pierce": 0.0, "shield": 0, "heal": 0, "status_stacks": {}, "lines": [], "counter_triple": false, "triple": false, "heal_triple": false}
	duel.combat.contribute(fire_sym, 1, acc, "fire")
	_check(duel.charge_points == 1, "③ 元素三连下单格克制也充能 +1")
	duel._elem_triple = false

	duel.enemy_element = "fire"
	duel.charge_points = 0
	acc = {"dmg": 0, "special": 0, "pierce": 0.0, "shield": 0, "heal": 0, "status_stacks": {}, "lines": [], "counter_triple": false, "triple": false, "heal_triple": false}
	duel.combat.contribute(fire_sym, 2, acc, "fire")
	_check(duel.charge_points == 0, "④ 抵抗对不充能")

	_check(DuelController.BALANCE.charge_max == 6, "⑤ charge_max=6（A+B 拍板）")

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)