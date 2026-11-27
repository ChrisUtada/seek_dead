extends Node

# ============================================================================
# T3-1 frost 批次 1：glacier 迁移验收 + 冰系牌谱去状态（2026-11-26 初版，2026-11-27 更新）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t31_frost_batch1_test.tscn
#
# 覆盖 8 条：
#   1. glacier 池过滤：frost 离池、冰刃在池
#   2. W02 条件不含状态符号/状态 kind，且保留一个特定符号约束（ice_crystal）
#   3. W02 正例：两张冰伤武器牌 + 其中一张冰霜晶弹（source_element=ice）
#   4. 反例：缺武器位 / 无冰霜晶弹 / 双非伤害 / 单冰伤
#   5. ice_gun 迁移后 frost 离池，glacier_spear 在池
#   6. 每 SPIN 至多一次：三冰刃 chance=1.0 → +1；chance=0.0 → 0
#   7. 不外溢：glacier + ice_gun 同装，双方 frost 都不在池
#   8. W03 不受影响：三张毒伤仍满足
# ============================================================================

const GLACIER := "res://resources/weapon_templates/glacier_greatsword.tres"
const ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const FROST_SLASH := "res://resources/symbols/frost_slash.tres"
const ICE_CRYSTAL := "res://resources/symbols/ice_crystal.tres"
const ICE_SHOT := "res://resources/symbols/ice_shot.tres"
const GLACIER_SPEAR := "res://resources/symbols/glacier_spear.tres"
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
	_test_ice_gun_migrated()
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


# 2：W02 不含状态符号/状态 kind；状态符号离开后必须保留一个特定符号约束。
func _test_rule_has_no_status_sym() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var has_status_sym := false
	var has_status_kind := false
	var has_crystal_sym := false
	for c in rule.get("all", []):
		var cond := c as Dictionary
		if String(cond.get("sym", "")).ends_with("frost.tres"):
			has_status_sym = true
		if String(cond.get("kind", "")) == "status":
			has_status_kind = true
		if String(cond.get("sym", "")).ends_with("ice_crystal.tres"):
			has_crystal_sym = true
	_check(not has_status_sym and not has_status_kind and has_crystal_sym,
		"2 W02 无状态条件=%s，保留冰霜晶弹特定符号=%s" % [
			str(not has_status_sym and not has_status_kind), str(has_crystal_sym)])


# 3：W02 正例——两张冰伤武器牌，其中一张是冰霜晶弹。
#    冰弹 element=none 但来源武器是 ice，因此 source_element=ice 也应认。
func _test_w02_new_semantics() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var c_slash := _card(FROST_SLASH, "glacier_greatsword")
	var c_crystal := _card(ICE_CRYSTAL, "ice_staff")
	var c_shot := _card(ICE_SHOT, "ice_gun")
	var pos_basic: bool = MATCHER.solve_rule([c_slash, c_crystal, c_shot], rule)
	var pos_crystal_second: bool = MATCHER.solve_rule([c_shot, c_crystal, c_slash], rule)
	_check(pos_basic and pos_crystal_second,
		"3 W02 正例：冰刃+晶弹+冰弹=%s，冰弹+晶弹+冰刃=%s" % [
			str(pos_basic), str(pos_crystal_second)])


# 4：W02 反例——缺武器位 / 无冰霜晶弹 / 双非伤害 / 单冰伤。
func _test_w02_negatives() -> void:
	var rule: Dictionary = (load(W02) as PatternData).match_rule
	var c_slash := _card(FROST_SLASH, "glacier_greatsword")
	var c_crystal := _card(ICE_CRYSTAL, "ice_staff")
	var c_shot := _card(ICE_SHOT, "ice_gun")
	var c_status := _card(FROST, "ice_gun")
	var c_skill := _card(AEGIS_SYM, "aegis", "none", "skill")
	var neg_skill: bool = MATCHER.solve_rule([c_slash, c_crystal, c_skill], rule)
	var neg_no_crystal: bool = MATCHER.solve_rule([c_slash, c_shot, c_shot], rule)
	var neg_two_non: bool = MATCHER.solve_rule([c_status, c_status, c_skill], rule)
	var neg_single: bool = MATCHER.solve_rule([c_slash], rule)
	_check(not neg_skill and not neg_no_crystal and not neg_two_non and not neg_single,
		"4 W02 反例：+技能=%s，无晶弹=%s，双非伤害=%s，单冰伤=%s" % [
			str(neg_skill), str(neg_no_crystal), str(neg_two_non), str(neg_single)])


# 5：ice_gun 已迁移，frost 离池，霜棘（glacier_spear）在池。
func _test_ice_gun_migrated() -> void:
	var wd: WeaponData = load(ICE_GUN)
	_equip([ICE_GUN])
	var migrated := bool(wd.status_migrated)
	var has_frost := _pool_has(FROST)
	var has_spear := _pool_has(GLACIER_SPEAR)
	_check(migrated and not has_frost and has_spear,
		"5 ice_gun 迁移：status_migrated=%s，frost 离池=%s，霜棘在池=%s" % [
			str(migrated), str(not has_frost), str(has_spear)])


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


# 7：同装 glacier + ice_gun，双方 frost 都不在池，冰伤符号都在池。
func _test_no_overflow() -> void:
	_equip([GLACIER, ICE_GUN])
	var has_slash := _pool_has(FROST_SLASH)
	var has_spear := _pool_has(GLACIER_SPEAR)
	var has_frost := _pool_has(FROST)
	_check(has_slash and has_spear and not has_frost,
		"7 不外溢：冰刃在池=%s，霜棘在池=%s，frost 离池=%s" % [
			str(has_slash), str(has_spear), str(not has_frost)])


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
