extends Node

# ============================================================================
# T3-1 burn 批次 1：W01 / SIG_W01_EMBER 改写 + ember_sword 迁移验收（2026-11-26）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t31_burn_batch1_test.tscn
#
# 覆盖 7 条：
#   1. ember_sword 池过滤：burn 离池、火斩在池
#   2. W01 条件不含任何状态符号引用
#   3. W01 1C 语义：flame damage + flame status + 任意武器牌（三张不同牌）
#   4. SIG_W01_EMBER 同上（签名条件同步改写）
#   5. 反向守护：fire_sword 未迁移，burn 仍在池
#   6. 每 SPIN 至多一次：三列火斩 chance=1.0 → +1；再次调用仍 +1；chance=0.0 → 0
#   7. 不外溢：ember_sword + fire_sword 同装，fire_sword 的 burn 仍在池
# 注：1A = 第二格允许 status/special；1B = 第二格要求 kind=status；
#     1C = 1B + 第三条件「任意武器牌」（最终采用，见文档 §11）。
# ============================================================================

const EMBER_SWORD := "res://resources/weapon_templates/ember_sword.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const BURN := "res://resources/symbols/burn.tres"
const FLAME_SPECIAL := "res://resources/symbols/flame_special.tres"
const AEGIS_SYM := "res://resources/symbols/aegis.tres"
const W01 := "res://resources/patterns/w01_flame_resonance.tres"
const SIG_EMBER := "res://resources/patterns/sig_ember_sword.tres"
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
	_test_w01_new_semantics()
	_test_sig_new_semantics()
	_test_fire_sword_untouched()
	_test_once_per_spin()
	_test_no_overflow()

	print("T31BURN|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
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


func _card(sym_path: String, src: String, src_elem: String = "fire", kind: String = "weapon") -> Dictionary:
	var s = load(sym_path)
	return {"sym": s, "element": String(s.element), "source": src,
		"source_kind": kind, "source_element": src_elem, "valid": true}


# 1：ember_sword 迁移后，burn 不再入池，火斩仍在池。
func _test_pool_filter() -> void:
	_equip([EMBER_SWORD])
	var has_burn := _pool_has(BURN)
	var has_slash := _pool_has(FIRE_SLASH)
	_check(not has_burn and has_slash,
		"1 池过滤：burn 离池=%s，fire_slash 在池=%s" % [str(not has_burn), str(has_slash)])


# 2：W01 的 match_rule 不再包含任何 {"sym": ...} 条件。
func _test_rule_has_no_status_sym() -> void:
	var rule: Dictionary = (load(W01) as PatternData).match_rule
	var has_sym := false
	for c in rule.get("all", []):
		if (c as Dictionary).has("sym"):
			has_sym = true
	_check(not has_sym and not JSON.stringify(rule).contains("burn.tres"),
		"2 W01 条件无状态符号引用：has_sym=%s，含 burn=%s" % [
			str(has_sym), str(JSON.stringify(rule).contains("burn.tres"))])


# 3：W01 1C 语义——三张不同牌：flame damage + flame status + 任意武器牌。
#    正例：火斩 + burn + 炎爆（第三张任意武器牌）；火斩 + burn + 火斩。
#    反例：火斩 + burn + 技能（第三张非武器）、双火伤无 status、单火伤、双非伤害。
func _test_w01_new_semantics() -> void:
	var rule: Dictionary = (load(W01) as PatternData).match_rule
	var c1 := _card(FIRE_SLASH, "ember_sword")
	var c2 := _card(FIRE_SLASH, "fire_sword")
	var c_burn := _card(BURN, "fire_sword")
	var c_special := _card(FLAME_SPECIAL, "flame_staff")
	var c_skill := _card(AEGIS_SYM, "aegis", "none", "skill")
	var pos_special: bool = MATCHER.solve_rule([c1, c_burn, c_special], rule)
	var pos_second_slash: bool = MATCHER.solve_rule([c1, c_burn, c2], rule)
	var neg_skill: bool = MATCHER.solve_rule([c1, c_burn, c_skill], rule)
	var neg_dd: bool = MATCHER.solve_rule([c1, c2, c_special], rule)
	var neg_two_non: bool = MATCHER.solve_rule([c_burn, c_special, c_burn], rule)
	var neg_single: bool = MATCHER.solve_rule([c1], rule)
	_check(pos_special and pos_second_slash and not neg_skill and not neg_dd and not neg_two_non and not neg_single,
		"3 W01 1C 语义：火伤+burn+任意武器=%s/%s，+技能=%s，双火伤=%s，双非伤害=%s，单火伤=%s" % [
			str(pos_special), str(pos_second_slash), str(neg_skill), str(neg_dd),
			str(neg_two_non), str(neg_single)])


# 4：SIG_W01_EMBER 与 W01 同条件（1C）。
func _test_sig_new_semantics() -> void:
	var rule: Dictionary = (load(SIG_EMBER) as PatternData).match_rule
	var c1 := _card(FIRE_SLASH, "ember_sword")
	var c2 := _card(FIRE_SLASH, "fire_sword")
	var c_burn := _card(BURN, "fire_sword")
	var c_special := _card(FLAME_SPECIAL, "flame_staff")
	var c_skill := _card(AEGIS_SYM, "aegis", "none", "skill")
	var pos_special: bool = MATCHER.solve_rule([c1, c_burn, c_special], rule)
	var pos_second_slash: bool = MATCHER.solve_rule([c1, c_burn, c2], rule)
	var neg_skill: bool = MATCHER.solve_rule([c1, c_burn, c_skill], rule)
	var neg_dd: bool = MATCHER.solve_rule([c1, c2, c_special], rule)
	var neg_two_non: bool = MATCHER.solve_rule([c_burn, c_special, c_burn], rule)
	var no_status_ref := not JSON.stringify(rule).contains("burn.tres")
	_check(pos_special and pos_second_slash and not neg_skill and not neg_dd and not neg_two_non and no_status_ref,
		"4 SIG_W01_EMBER 1C 语义：火伤+burn+任意武器=%s/%s，+技能=%s，双火伤=%s，双非伤害=%s，含 burn=%s" % [
			str(pos_special), str(pos_second_slash), str(neg_skill), str(neg_dd),
			str(neg_two_non), str(not no_status_ref)])


# 5：fire_sword 本批不迁移，burn 仍在池（反向守护，防顺手全量迁移）。
func _test_fire_sword_untouched() -> void:
	var wd: WeaponData = load(FIRE_SWORD)
	_equip([FIRE_SWORD])
	var migrated := bool(wd.status_migrated)
	var has_burn := _pool_has(BURN)
	_check(not migrated and has_burn,
		"5 fire_sword 未迁移：status_migrated=%s，burn 在池=%s" % [str(migrated), str(has_burn)])


# 6：每 SPIN 至多一次 + 概率门控。
func _test_once_per_spin() -> void:
	var wd: WeaponData = load(EMBER_SWORD)
	wd.status_chance = 1.0
	_equip([EMBER_SWORD])
	_duel.enemy_status.clear()
	var acc := _settle_three_slash()
	_duel.combat._phase_migrated_status(acc)
	var after_first := int(_duel.enemy_status.get("burn", 0))
	_duel.combat._phase_migrated_status(acc)
	var after_second := int(_duel.enemy_status.get("burn", 0))
	_check(after_first == 1 and after_second == 1,
		"6a 每 SPIN 至多一次：三列火斩→%d 层，再判→%d 层（期望 1/1）" % [after_first, after_second])
	wd.status_chance = 0.0
	_duel.enemy_status.clear()
	var acc0 := _settle_three_slash()
	_duel.combat._phase_migrated_status(acc0)
	var got0 := int(_duel.enemy_status.get("burn", 0))
	_check(got0 == 0, "6b chance=0.0：燃烧 %d 层（期望 0）" % got0)
	wd.status_chance = 0.35


# 7：同装另一把未迁移火武器的 burn 仍在池。
func _test_no_overflow() -> void:
	_equip([EMBER_SWORD, FIRE_SWORD])
	var has_slash := _pool_has(FIRE_SLASH)
	var has_burn := _pool_has(BURN)
	_check(has_slash and has_burn,
		"7 不外溢：fire_slash 在池=%s，fire_sword 的 burn 在池=%s" % [str(has_slash), str(has_burn)])


func _settle_three_slash() -> Dictionary:
	for r in 3:
		_duel.grid[r][0] = load(FIRE_SLASH)
		_duel.grid_elem[r][0] = "fire"
		_duel.reel_system._set_grid_src(r, 0, "ember_sword")
	_duel.enemy_element = "none"
	_duel.enemy_armor = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	_duel.combat._phase_symbols(acc)
	return acc
