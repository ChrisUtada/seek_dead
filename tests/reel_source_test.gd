extends Node

# 双武器共享符号：同族总格数、分源图标、来源伤害、同族三连、来源破甲与充能去重。
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FORGE_SWORD := "res://resources/weapon_templates/forge_greatsword.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"

var _checks := 0
var _fails := 0
var _save_backup := {}


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	await _run()
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()
	print("---")
	print("REELSOURCE|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("REELSOURCE|FAIL|" + msg)


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_loadout.assign([FIRE_SWORD, FORGE_SWORD])
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	duel.growth.perk_ids.clear()
	duel._reward_system.run_power_bonus = 0
	duel.reel_system._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.frozen_cols.clear()
	return duel


func _set_grid(duel: DuelController, sources: Array) -> void:
	var sym: SymbolData = load(FIRE_SLASH)
	for r in 3:
		duel.grid[r][0] = sym
		duel.grid_elem[r][0] = "fire"
		duel.reel_system._set_grid_src(r, 0, String(sources[r]))


func _evaluate_grid(duel: DuelController, sources: Array, enemy_element: String = "light") -> Dictionary:
	_set_grid(duel, sources)
	duel.enemy_element = enemy_element
	var acc: Dictionary = duel.combat._new_acc()
	duel.combat._reset_turn_state()
	acc["counts"] = duel.combat._phase_symbols(acc)
	return acc


func _run() -> void:
	var duel: DuelController = await _boot()
	var rs = duel.reel_system

	# 火焰剑权重3、锻炉巨剑权重6：每个基础平铺单元同族4格，分源后各2格。
	rs.build_strips()
	var counts := {"fire_sword": 0, "forge_greatsword": 0, "other": 0}
	for entry in rs.reel_strips[0]:
		if entry[0].resource_path != FIRE_SLASH:
			continue
		var src := String(entry[2]) if entry.size() > 2 else ""
		if counts.has(src):
			counts[src] += 1
		else:
			counts["other"] += 1
	_check(counts["fire_sword"] > 0 and counts["fire_sword"] == counts["forge_greatsword"],
		"两把武器在平铺后的带子上仍各占相同数量的独立火斩格")
	_check(counts["other"] == 0, "共享火斩没有无来源或错误来源格")
	_check((counts["fire_sword"] + counts["forge_greatsword"]) % 4 == 0,
		"每个平铺单元的双武器火斩族总预算仍为4格")

	var alloc_a: Dictionary = ReelSystem.allocate_source_cells({"a": 2.0, "b": 2.0}, 4)
	var alloc_b: Dictionary = ReelSystem.allocate_source_cells({"a": 3.0, "b": 1.0}, 4)
	_check(alloc_a.get("a", 0) == 2 and alloc_a.get("b", 0) == 2, "同权重来源均分总格数")
	_check(alloc_b.get("a", 0) == 3 and alloc_b.get("b", 0) == 1, "不同权重按最大余数分配且每源至少1格")

	var fire_icon := WeaponIcons.cell_icon_for_id("fire_sword")
	var forge_icon := WeaponIcons.cell_icon_for_id("forge_greatsword")
	_check(fire_icon != null and forge_icon != null and fire_icon != forge_icon, "两把武器使用不同的完整32px图标")
	var view = duel.hud.cell_spin_views[0][0]
	_check(view._reel_icon(load(FIRE_SLASH).icon_tex, load(FIRE_SLASH), "fire", "fire_sword") == fire_icon,
		"滚动中的火焰剑格直接使用火焰剑图标")
	_check(view._reel_icon(load(FIRE_SLASH).icon_tex, load(FIRE_SLASH), "fire", "forge_greatsword") == forge_icon,
		"滚动中的锻炉巨剑格直接使用锻炉巨剑图标")

	# A+A+B：两个来源分别按18/23攻结算，同族混合三连统一为1.5倍。
	duel.mastery.reset_room()
	var mixed: Dictionary = _evaluate_grid(duel, ["fire_sword", "fire_sword", "forge_greatsword"])
	_check(is_equal_approx(float(mixed["dmg"]), 88.5), "混合三连按来源伤害18×2×1.5 + 23×1×1.5 = 88.5")
	_check(bool(mixed["triple"]), "不同武器图标仍可组成同族三连")
	_check(mixed["lines"].size() == 2, "伤害分解分别列出两个武器来源")
	_check(duel.mastery._settled.has("fire_sword|" + FIRE_SLASH)
		and duel.mastery._settled.has("forge_greatsword|" + FIRE_SLASH), "两个实际结算的来源都记录武器熟练")

	# 同族克制连线充能1点，同元素共鸣再提供1点，不因来源数重复增加。
	duel.charge_points = 0
	var charged: Dictionary = _evaluate_grid(duel, ["fire_sword", "fire_sword", "forge_greatsword"], "ice")
	_check(duel.charge_points == 2, "同族克制与同元素共鸣合计充能2点")
	_check(int(duel._charge_elem_counts.get("fire", 0)) == 1, "主导元素计数不随来源数翻倍")
	_check(bool(charged["counter_triple"]), "同族克制连线仍正常标记")

	# 混合格中锻炉巨剑只有1格，不能把它的破甲传给火焰剑，也不能自行凑满三连。
	duel.enemy_armor = 20
	var no_pierce: Dictionary = _evaluate_grid(duel, ["fire_sword", "fire_sword", "forge_greatsword"])
	duel.combat._phase_counter(no_pierce["counts"], no_pierce)
	_check(duel.enemy_armor == 20, "混合三连不继承另一把武器的破甲特性")

	# 三格全部来自锻炉巨剑时，才触发它自己的三连破甲。
	duel.enemy_armor = 20
	var pure_forge: Dictionary = _evaluate_grid(duel, ["forge_greatsword", "forge_greatsword", "forge_greatsword"])
	duel.combat._phase_counter(pure_forge["counts"], pure_forge)
	_check(duel.enemy_armor == 0, "锻炉巨剑同源三连触发自己的破甲")
