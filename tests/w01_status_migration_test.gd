extends Node

# ============================================================================
# W-01B：poison_dagger 试点迁移验收（2026-11-26）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/w01_status_migration_test.tscn
#
# 覆盖 7 条：
#   3.1 池过滤：poison 离池、venom_bite 在池        （迁移生效的直接证据）
#   3.2 概率触发：chance=1.0 + 落线毒牙 → 中毒 +1    （管道接通）
#   3.3 每 SPIN 至多一次：三列毒牙 → +1；再次调用仍 +1（去重集合生效）
#   3.4 chance=0.0 → 不触发                         （概率门控有效）
#   3.5 不外溢：fire_sword 的 burn 仍在池            （未迁移武器零影响）
#   3.6 W03 可达：两条毒伤条件 + 武器条件           （牌谱条件改写后仍可达且不给状态符号）
#   3.7 P3 和解：三列毒牙 → on_turn_resolved 和解    （死锁解除的端到端证据）
# ============================================================================

const POISON_DAGGER := "res://resources/weapon_templates/poison_dagger.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const BLIGHT_SPEAR := "res://resources/weapon_templates/blight_spear.tres"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const VENOM_BITE := "res://resources/symbols/venom_bite.tres"
const POISON := "res://resources/symbols/poison.tres"
const IRON_SLASH := "res://resources/symbols/iron_slash.tres"
const W03 := "res://resources/patterns/w03_venom_burst.tres"
const SHADOW_BOSS := "勇者的阴影"
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

	_equip([POISON_DAGGER])
	_test_pool_filter()
	_test_chance_one()
	_test_once_per_spin()
	_test_chance_zero()
	_test_other_weapon_unaffected()
	_test_w03_rule()
	_test_p3_reconcile()

	print("W01MIG|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
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


# 驱动结算前半段：铺三格 → 清回合状态 → 符号计数（填 acc.source_dmg）。
func _settle(syms: Array, elems: Array, srcs: Array) -> Dictionary:
	for r in 3:
		_duel.grid[r][0] = load(String(syms[r]))
		_duel.grid_elem[r][0] = String(elems[r])
		_duel.reel_system._set_grid_src(r, 0, String(srcs[r]))
	_duel.enemy_element = "none"
	_duel.enemy_armor = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	_duel.combat._phase_symbols(acc)
	return acc


func _dagger() -> WeaponData:
	return load(POISON_DAGGER)


# 3.1：状态符号离池，毒牙在池。
func _test_pool_filter() -> void:
	var has_poison := false
	var has_venom := false
	for it in _duel.pool:
		var p := String((it[0] as SymbolData).resource_path)
		if p.ends_with("poison.tres"):
			has_poison = true
		if p.ends_with("venom_bite.tres"):
			has_venom = true
	_check(not has_poison and has_venom,
		"3.1 池过滤：poison 离池=%s，venom_bite 在池=%s" % [str(not has_poison), str(has_venom)])


# 3.2：chance=1.0 时一次落线必触发 1 层。
func _test_chance_one() -> void:
	_dagger().status_chance = 1.0
	_duel.enemy_status.clear()
	var acc := _settle([VENOM_BITE, _duel.TRASH_SYMBOL.resource_path, _duel.TRASH_SYMBOL.resource_path],
		["poison", "none", "none"], ["poison_dagger", "", ""])
	_duel.combat._phase_migrated_status(acc)
	var got := int(_duel.enemy_status.get("poison", 0))
	_check(got == 1, "3.2 概率触发（chance=1.0）：中毒 %d 层（期望 1）" % got)


# 3.3：三列毒牙（同一把武器）→ 只 +1；同 SPIN 再调一次仍 +1（去重集合）。
func _test_once_per_spin() -> void:
	_dagger().status_chance = 1.0
	_duel.enemy_status.clear()
	var acc := _settle([VENOM_BITE, VENOM_BITE, VENOM_BITE],
		["poison", "poison", "poison"], ["poison_dagger", "poison_dagger", "poison_dagger"])
	_duel.combat._phase_migrated_status(acc)
	var after_first := int(_duel.enemy_status.get("poison", 0))
	_duel.combat._phase_migrated_status(acc)   # 同一 SPIN 的第二次结算入口：应被去重集合拦住
	var after_second := int(_duel.enemy_status.get("poison", 0))
	_check(after_first == 1 and after_second == 1,
		"3.3 每 SPIN 至多一次：三列→%d 层，再判→%d 层（期望 1/1；逐格结算=3，去掉集合第二次会再 +1）" % [after_first, after_second])


# 3.4：chance=0.0 完全不触发。
func _test_chance_zero() -> void:
	_dagger().status_chance = 0.0
	_duel.enemy_status.clear()
	var acc := _settle([VENOM_BITE, VENOM_BITE, VENOM_BITE],
		["poison", "poison", "poison"], ["poison_dagger", "poison_dagger", "poison_dagger"])
	_duel.combat._phase_migrated_status(acc)
	var got := int(_duel.enemy_status.get("poison", 0))
	_check(got == 0, "3.4 chance=0.0：中毒 %d 层（期望 0）" % got)
	_dagger().status_chance = 0.35


# 3.5：未迁移武器不受门控影响。
func _test_other_weapon_unaffected() -> void:
	_equip([FIRE_SWORD])
	var has_burn := false
	for it in _duel.pool:
		if String((it[0] as SymbolData).resource_path).ends_with("burn.tres"):
			has_burn = true
	_check(has_burn, "3.5 不外溢：fire_sword 的 burn 仍在池=%s" % str(has_burn))


# 3.6：W03 新条件可达，且不再引用状态符号。
func _test_w03_rule() -> void:
	var rule: Dictionary = (load(W03) as PatternData).match_rule
	var c1 := _card(VENOM_BITE, "poison_dagger")
	var c2 := _card(VENOM_BITE, "blight_spear")
	var c3 := _card(VENOM_BITE, "blight_spear")
	var two_venom := [c1, c2]
	var three := [c1, c2, c3]
	# 负例：两张毒伤牌满足不了三条条件（每条条件必须由不同卡满足）
	var neg_ok: bool = MATCHER.solve_rule(two_venom, rule)
	var neg_non_poison: bool = MATCHER.solve_rule([c1, c2, _card(IRON_SLASH, "iron_sword", "none")], rule)
	var pos_ok: bool = MATCHER.solve_rule(three, rule)
	var no_status_ref := not JSON.stringify(rule).contains("poison.tres")
	_check(pos_ok and not neg_ok and not neg_non_poison and no_status_ref,
		"3.6 W03 可达：三张毒伤=%s，两张=%s，含非毒武器=%s，条件不含状态符号=%s" % [
			str(pos_ok), str(neg_ok), str(neg_non_poison), str(no_status_ref)])


func _card(sym_path: String, src: String, src_elem: String = "poison") -> Dictionary:
	var s = load(sym_path)
	return {"sym": s, "element": String(s.element), "source": src,
		"source_kind": "weapon", "source_element": src_elem, "valid": true}


# 3.7：P3 下三列毒牙 → on_turn_resolved 达成和解（真的走 gimmick 判定）。
func _test_p3_reconcile() -> void:
	var room: RoomData = null
	for r in _duel.ALL_ROOMS:
		if String(r.name) == SHADOW_BOSS:
			room = r
			break
	if room == null:
		_check(false, "3.7 找不到勇者的阴影房间")
		return
	_duel.ROOMS.clear()
	_duel.ROOMS.append(room)
	_duel.start_room_data(room, 0, 0, false)
	var g = _duel.current_gimmick
	# 推到 P3：66% → P2，20% → P3
	_duel.enemy_hp_max = 100
	_duel.enemy_hp = 66
	g.on_damaged(_duel, 0)
	_duel.enemy_hp = 19
	g.on_damaged(_duel, 0)
	_duel.enemy_hp = 1
	for r in _duel.REELS:
		_duel.grid[r][0] = load(VENOM_BITE)
		_duel.grid_elem[r][0] = "poison"
		_duel.reel_system._set_grid_src(r, 0, "poison_dagger")
	g.on_turn_resolved(_duel)
	_check(bool(_duel.peaceful_win), "3.7 P3 和解：三列毒牙触发 peaceful_win=%s" % str(_duel.peaceful_win))
