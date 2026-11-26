extends Node

# ============================================================================
# T3-1 frost 批次 1：W02 / SIG_W02_GLACIER 条件改写 + glacier 迁移验收（2026-11-26）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t31_frost_batch1_test.tscn
#
# 覆盖 8 条：
#   1. glacier 池过滤：frost 离池、冰刃在池
#   2. W02 条件不含任何状态符号引用
#   3. W02 新语义正例：冰伤 + frost + 任意武器牌（source_element=ice）
#   4. 反例：+技能 / 双冰伤无 status / 单冰伤 / 双非伤害
#   5. 反向守护：ice_gun 未迁移，frost 仍在池
#   6. 每 SPIN 至多一次：三冰刃 chance=1.0 → +1；chance=0.0 → 0
#   7. 不外溢：glacier + ice_gun 同装，ice_gun 的 frost 仍在池
#   8. W03 不受影响：三张毒伤仍满足
# ============================================================================

const GLACIER := "res://resources/weapon_templates/glacier_greatsword.tres"
const ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const FROST_SLASH := "res://resources/symbols/frost_slash.tres"
const ICE_CRYSTAL := "res://resources/symbols/ice_crystal.tres"
const ICE_SHOT := "res://resources/symbols/ice_shot.tres"
const FROST := "res://resources/symbols/frost.tres"
const AEGIS_SYM := "res://resources/symbols/aegis.tres"
const VENOM_BITE := "res://resources/symbols/venom_bite.tres"
const W02 := "res://resources/patterns/w02_frost_seal.tres"
const W03 := "res://resources/patterns/w03_venom_burst.tres"
const MATCHER = preload("res://scripts/battle/pattern_matcher.gd")

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	_duel.reel_system._timer.stop()

	_test_pool_filter()
	_test_rule_has_no_status_sym()
	_test_w02_new_semantics()
	_test_w02_negatives()
	_test_ice_gun_untouched()
	_test_once_per_spin()
	_test_no_overflow()
	_test_w03_untouched()

	print("T31FROST|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _equip(paths: Array) -> void:
	_duel.selected_loadout.clear()
	for p in paths:
		_duel.selected_loadout.append(String(p))
	_duel.selected_skills.clear()
	_duel._build_pool(_duel.selected_loadout)


func _pool_has(sym_path: String) -> bool:
	for it in _duel.pool:
		if String((it[0] as SymbolData).resource_path).ends_with(sym_path.get_file()):
			return true
	return false


func _card(sym_path: String, src: String, src_elem: String = "ice", kind: String = "weapon") -> Dictionary:
	var s = load(sym_path)
	return {"sym": s, "element": String(s.element), "source": src,
		"source_kind": kind, "source_element": src_elem, "valid": true}


# 1：glacier 迁移后，frost 不再入池，冰刃仍在池。
func _test_pool_filter() -> void:
	_equip([GLACIER])
	var has_frost := _pool_has(FROST)
	var has_slash := _pool_has(FROST_SLASH)
	_check(not has_frost and has_slash,
		"1 池过滤：frost 离池=%s，冰刃在池=%s" % [str(not has_frost), str(has_slash)])


# 2：W02 的 match_rule 不再包含 {"sym": ...} 条件。
func _test_rule_has_no_status_sym() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var has_sym := false
	for c in rule.get("all", []):
		if (c as Dictionary).has("sym"):
			has_sym = true
	_check(not has_sym and not JSON.stringify(rule).contains("frost.tres"),
		"2 W02 条件无状态符号引用：has_sym=%s，含 frost=%s" % [
			str(has_sym), str(JSON.stringify(rule).contains("frost.tres"))])


# 3：W02 正例——冰伤 + frost + 任意武器牌（三张不同牌，source_element=ice）。
#    冰弹符号 element=none 但来源武器是 ice，因此 source_element=ice 也应认。
func _test_w02_new_semantics() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var c_dmg := _card(FROST_SLASH, "glacier_greatsword")
	var c_status := _card(FROST, "ice_gun")
	var c_any := _card(ICE_CRYSTAL, "ice_staff")
	var c_shot := _card(ICE_SHOT, "ice_gun")
	var c_dmg2 := _card(ICE_CRYSTAL, "ice_staff")
	var pos_basic: bool = MATCHER.solve_rule([c_dmg, c_status, c_any], rule)
	var pos_ice_shot: bool = MATCHER.solve_rule([c_shot, c_status, c_dmg2], rule)
	_check(pos_basic and pos_ice_shot,
		"3 W02 正例：冰刃+frost+武器=%s，冰弹+frost+武器=%s" % [
			str(pos_basic), str(pos_ice_shot)])


# 4：W02 反例——第三张非武器 / 双冰伤无 status / 双非伤害 / 单冰伤。
func _test_w02_negatives() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var c_dmg := _card(FROST_SLASH, "glacier_greatsword")
	var c_status := _card(FROST, "ice_gun")
	var c_shot := _card(ICE_SHOT, "ice_gun")
	var c_dmg2 := _card(ICE_CRYSTAL, "ice_staff")
	var c_skill := _card(AEGIS_SYM, "aegis", "none", "skill")
	var neg_skill: bool = MATCHER.solve_rule([c_dmg, c_status, c_skill], rule)
	var neg_dd: bool = MATCHER.solve_rule([c_dmg, c_shot, c_dmg2], rule)
	var neg_two_non: bool = MATCHER.solve_rule([c_status, c_status, c_skill], rule)
	var neg_single: bool = MATCHER.solve_rule([c_dmg], rule)
	_check(not neg_skill and not neg_dd and not neg_two_non and not neg_single,
		"4 W02 反例：+技能=%s，双冰伤=%s，双非伤害=%s，单冰伤=%s" % [
			str(neg_skill), str(neg_dd), str(neg_two_non), str(neg_single)])


# 5：ice_gun 本批不迁移，frost 仍在池（反向守护）。
func _test_ice_gun_untouched() -> void:
	var wd: WeaponData = load(ICE_GUN)
	_equip([ICE_GUN])
	var migrated := bool(wd.status_migrated)
	var has_frost := _pool_has(FROST)
	_check(not migrated and has_frost,
		"5 ice_gun 未迁移：status_migrated=%s，frost 在池=%s" % [str(migrated), str(has_frost)])


# 6：每 SPIN 至多一次 + 概率门控。
func _test_once_per_spin() -> void:
	var wd: WeaponData = load(GLACIER)
	wd.status_chance = 1.0
	_equip([GLACIER])
	_duel.enemy_status.clear()
	var acc := _settle_three_slash()
	_duel.combat._phase_migrated_status(acc)
	var after_first := int(_duel.enemy_status.get("frost", 0))
	_duel.combat._phase_migrated_status(acc)
	var after_second := int(_duel.enemy_status.get("frost", 0))
	_check(after_first == 1 and after_second == 1,
		"6a 每 SPIN 至多一次：三列冰刃→%d 层，再判→%d 层（期望 1/1）" % [after_first, after_second])
	wd.status_chance = 0.0
	_duel.enemy_status.clear()
	var acc0 := _settle_three_slash()
	_duel.combat._phase_migrated_status(acc0)
	var got0 := int(_duel.enemy_status.get("frost", 0))
	_check(got0 == 0, "6b chance=0.0：霜冻 %d 层（期望 0）" % got0)
	wd.status_chance = 0.35


# 7：同装 ice_gun 的 frost 仍在池。
func _test_no_overflow() -> void:
	_equip([GLACIER, ICE_GUN])
	var has_slash := _pool_has(FROST_SLASH)
	var has_frost := _pool_has(FROST)
	_check(has_slash and has_frost,
		"7 不外溢：冰刃在池=%s，ice_gun 的 frost 在池=%s" % [str(has_slash), str(has_frost)])


# 8：W03 毒伤三条件不受本批影响。
func _test_w03_untouched() -> void:
	var rule: Dictionary = (load(W03) as PatternData).match_rule
	var cards := [
		_card(VENOM_BITE, "poison_dagger", "poison"),
		_card(VENOM_BITE, "poison_dagger", "poison"),
		_card(VENOM_BITE, "poison_dagger", "poison"),
	]
	_check(MATCHER.solve_rule(cards, rule), "8 W03 不受影响：三张毒伤仍成立")


func _settle_three_slash() -> Dictionary:
	for r in 3:
		_duel.grid[r][0] = load(FROST_SLASH)
		_duel.grid_elem[r][0] = "ice"
		_duel.reel_system._set_grid_src(r, 0, "glacier_greatsword")
	_duel.enemy_element = "none"
	_duel.enemy_armor = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	_duel.combat._phase_symbols(acc)
	return acc
