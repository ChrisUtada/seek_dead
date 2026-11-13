extends Node

# 武器原型与三连分类：同源专精、同族标准收益、同元素共鸣、轻/重/远程/法术差异。
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const BOW := "res://resources/weapon_templates/hunting_bow.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const FORGE := "res://resources/weapon_templates/forge_greatsword.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"

var _checks := 0
var _fails := 0
var _save_backup := {}


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	await _run()
	if _checks == 0:
		_fails += 1
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()
	print("---")
	print("WEAPONARCH|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("WEAPONARCH|FAIL|" + msg)


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel.growth.perk_ids.clear()
	duel._reward_system.run_power_bonus = 0
	duel._confirm_loadout()
	duel.reel_system._timer.stop()
	return duel


func _equip(duel: DuelController, path: String) -> void:
	duel.selected_loadout.assign([path])
	duel._build_pool(duel.selected_loadout)
	duel.frozen_cols.clear()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false


func _evaluate(duel: DuelController, symbol_path: String, source_id: String, element: String = "none") -> Dictionary:
	var sym: SymbolData = load(symbol_path)
	for r in 3:
		duel.grid[r][0] = sym
		duel.grid_elem[r][0] = element
		duel.reel_system._set_grid_src(r, 0, source_id)
	duel.enemy_element = "none"
	var acc: Dictionary = duel.combat._new_acc()
	duel.combat._reset_turn_state()
	duel.charge_points = 0
	acc["counts"] = duel.combat._phase_symbols(acc)
	return acc


func _run() -> void:
	var duel: DuelController = await _boot()

	# 轻型：8攻×3格×同源暴击2×连击1.5 = 72。
	_equip(duel, DAGGER)
	var light: Dictionary = _evaluate(duel, "res://resources/symbols/dagger_slash.tres", "dagger")
	_check(is_equal_approx(float(light["dmg"]), 72.0), "轻型同源三连触发50%追加连击")
	_check(is_equal_approx(float(light["pierce"]), 0.0), "轻型近战不获得远程穿透")

	# 远程：10攻×3格×同源暴击2 = 60，35%穿透 / 65%普通。
	_equip(duel, BOW)
	var ranged: Dictionary = _evaluate(duel, "res://resources/symbols/arrow_shot.tres", "hunting_bow")
	_check(is_equal_approx(float(ranged["dmg"]), 39.0), "远程同源三连65%进入普通伤害")
	_check(is_equal_approx(float(ranged["pierce"]), 21.0), "远程同源三连35%进入穿透伤害")

	# 法术远程：14攻×3×2 = 84；法术充能1 + 同元素共鸣1。
	_equip(duel, ICE_STAFF)
	var magic: Dictionary = _evaluate(duel, "res://resources/symbols/ice_crystal.tres", "ice_staff", "ice")
	_check(is_equal_approx(float(magic["dmg"] + magic["special"]), 54.6), "法术远程保留65%普通伤害")
	_check(is_equal_approx(float(magic["pierce"]), 29.4), "法术远程同时具有35%穿透")
	_check(duel.charge_points == 2, "法术同源三连与同元素共鸣各充能1点")
	_check(bool(magic["element_resonance"]), "同元素3格标记元素共鸣而非自动必暴")

	# 法术状态：3格×暴击2 = 6，法术+1，元素共鸣+1，最终8层。
	duel.enemy_status.clear()
	var frost: Dictionary = _evaluate(duel, "res://resources/symbols/frost.tres", "ice_staff", "ice")
	_check(is_equal_approx(float(frost["status_stacks"].get("frost", 0)), 7.0), "法术同源状态在共鸣前为7层")
	await duel.combat._phase_defense(frost)
	_check(int(duel.enemy_status.get("frost", 0)) == 8, "元素共鸣使本回合状态再增加1层")

	# 重型：同源三连触发原型破甲，不依赖其它武器传递。
	_equip(duel, FORGE)
	duel.enemy_armor = 25
	var heavy: Dictionary = _evaluate(duel, "res://resources/symbols/fire_slash.tres", "forge_greatsword", "fire")
	duel.combat._phase_counter(heavy["counts"], heavy)
	_check(duel.enemy_armor == 0, "重型同源三连清空护甲")
	_check(is_equal_approx(float(heavy["dmg"]), 138.0), "重型同源三连按23攻×3×2结算")

	# 同元素不同符号：不自动暴击、不核爆，只有充能和状态共鸣。
	_equip(duel, FIRE_SWORD)
	var paths := ["res://resources/symbols/fire_slash.tres", "res://resources/symbols/burn.tres", "res://resources/symbols/flame_special.tres"]
	for p in paths:
		duel._item_crit_chance_map[p] = -1.0
		duel._item_crit_chance_map[ReelSystem.source_key(p, "fire_sword")] = -1.0
	for r in 3:
		duel.grid[r][0] = load(paths[r])
		duel.grid_elem[r][0] = "fire"
		duel.reel_system._set_grid_src(r, 0, "")
	duel.enemy_element = "none"
	duel.enemy_armor = 30
	duel.charge_points = 0
	var mixed: Dictionary = duel.combat._new_acc()
	duel.combat._reset_turn_state()
	mixed["counts"] = duel.combat._phase_symbols(mixed)
	_check(is_equal_approx(float(mixed["dmg"] + mixed["special"]), 43.0), "同元素不同符号不自动获得三连暴击")
	_check(not bool(mixed["counter_triple"]), "同元素混合不再自动触发核爆标记")
	_check(bool(mixed["element_resonance"]), "同元素混合仍触发元素共鸣")
	duel.combat._phase_counter(mixed["counts"], mixed)
	_check(duel.enemy_armor == 30, "同元素混合不再自动清甲")
	_check(duel.charge_points == 1, "同元素混合提供一次共鸣充能")
	await duel.combat._phase_defense(mixed)
	_check(int(mixed["status_stacks"].get("burn", 0)) == 2, "无状态武器专精时元素共鸣只增加1层状态")
