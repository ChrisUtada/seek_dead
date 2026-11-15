extends Node

# ============================================================================
# 牌型匹配器 · Step 0 现状对照（2026-11-15）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §10 Step 0
#
# 本套现在只做一件事：把「当前结算的实际数值」钉成断言。
#
# 为什么要钉数值而不是钉「共鸣被激活了」：
# Step 1 会用 PatternMatcher 复算 G01–G03，Step 2 会用 S01–S06 替换掉现有三条永久装备共鸣。
# 替换期间新旧两套会短暂共存，如果对照只断言「触发了」，那么同一次攻击吃掉两份加成
# 也照样能通过。只有断言最终伤害数值，才能证明删旧效果时没有双份。
#
# 现有覆盖情况：weapon_archetype_test 已经钉了同源三连（72 / 39+21 / 54.6+29.4 / 138）
# 与元素共鸣（charge+1、状态再+1）。本套补的是它没覆盖的两块：
#   A 同族三连（同符号、多来源 → 固定 ×1.5，不使用武器专精倍率）
#   B 三条装备共鸣的真实数值（烈焰 / 冰火二重 / 黎明圣辉）
# ============================================================================

const DAGGER := "res://resources/weapon_templates/dagger.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const EMBER_SWORD := "res://resources/weapon_templates/ember_sword.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
const DAWN_BOW := "res://resources/weapon_templates/dawn_bow.tres"

const SYM_FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const SYM_BURN := "res://resources/symbols/burn.tres"
const SYM_HOLY_SLASH := "res://resources/symbols/holy_slash.tres"
const SYM_ICE_CRYSTAL := "res://resources/symbols/ice_crystal.tres"

var _checks := 0
var _fails := 0
var _duel


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = await _boot()
	if _duel == null:
		_check(false, "战斗场景可实例化")
		_finish()
		return

	print("=== A 现状对照：三连与元素共鸣 ===")
	_test_source_triple()
	_test_family_triple()
	_test_element_resonance()
	_test_single_card()

	print("=== B 现状对照：三条装备共鸣 ===")
	_test_flame_resonance()
	_test_frostfire()
	_test_holy_pair()

	print("=== C 守护：结算入口的既有语义 ===")
	_test_no_extra_swap_state()

	_finish()


func _boot():
	var duel = load("res://scenes/duel/duel.tscn").instantiate()
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


func _equip(paths: Array) -> void:
	_duel.selected_loadout.clear()
	for p in paths:
		_duel.selected_loadout.append(String(p))
	_duel._build_pool(_duel.selected_loadout)
	_duel.frozen_cols.clear()
	_duel.pending_jam_reel = -1
	_duel.pending_lock_reel = -1
	_duel.pending_chaos = false
	if _duel._synergy_system != null:
		_duel._synergy_system.refresh()


# 铺三格并跑阶段 1（符号计数与贡献）。sources 为空时三个格都用第一个来源。
func _settle(sym_path: String, element: String, sources: Array) -> Dictionary:
	var sym = load(sym_path)
	for r in 3:
		_duel.grid[r][0] = sym
		_duel.grid_elem[r][0] = element
		var src := ""
		if not sources.is_empty():
			src = String(sources[mini(r, sources.size() - 1)])
		_duel.reel_system._set_grid_src(r, 0, src)
	_duel.enemy_element = "none"
	_duel.enemy_armor = 0
	_duel.charge_points = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	acc["counts"] = _duel.combat._phase_symbols(acc)
	return acc


func _dmg(acc: Dictionary) -> float:
	return float(acc["dmg"]) + float(acc["special"])


# A1：同源三连——三个同族符号来自同一来源，用武器自己的专精倍率。
func _test_source_triple() -> void:
	_equip([FIRE_SWORD])
	var acc: Dictionary = _settle(SYM_FIRE_SLASH, "fire", ["fire_sword"])
	_check(bool(acc["triple"]), "同源三连标记 triple")
	var key := ReelSystem.source_key(SYM_FIRE_SLASH, "fire_sword")
	var crit: float = float(_duel._item_crit_map.get(key, 1.0))
	var flat: float = float(_duel._weapon_power_map.get(key, 0.0))
	_check(flat > 0.0, "武器攻击映射已建立（%.1f）" % flat)
	var expect: float = flat * 3.0 * crit
	_check(is_equal_approx(_dmg(acc), expect),
		"同源三连伤害 = 攻击×3×专精倍率（%.1f，期望 %.1f）" % [_dmg(acc), expect])


# A2：同族三连——同符号、三个不同来源，固定 ×1.5，不吃武器专精倍率。
func _test_family_triple() -> void:
	_equip([FIRE_SWORD, EMBER_SWORD])
	var acc: Dictionary = _settle(SYM_FIRE_SLASH, "fire", ["fire_sword", "ember_sword", "flame_staff"])
	_check(bool(acc["triple"]), "同族三连标记 triple")
	# 同族三连的倍率固定 1.5，而同源用武器专精倍率（本例 2.0），所以两者之比应为 0.75。
	# 不自己推绝对期望值：三个来源的攻击力可能不同，绝对值不该由测试假装知道。
	var single: Dictionary = _settle(SYM_FIRE_SLASH, "fire", ["fire_sword"])
	var src_triple: float = _dmg(single)
	_check(absf(_dmg(acc) / maxf(1.0, src_triple) - 0.75) < 0.02,
		"同族三连 = 同源三连的 0.75 倍（%.1f vs %.1f）" % [_dmg(acc), src_triple])


# A3：元素共鸣——三个不同符号同元素，充能 +1（不替代三连）。
func _test_element_resonance() -> void:
	_equip([FIRE_SWORD])
	var syms := [SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH]
	for r in 3:
		_duel.grid[r][0] = load(String(syms[r]))
		_duel.grid_elem[r][0] = "fire"
		_duel.reel_system._set_grid_src(r, 0, "fire_sword" if r != 1 else "")
	_duel.enemy_element = "none"
	_duel.charge_points = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	acc["counts"] = _duel.combat._phase_symbols(acc)
	_check(bool(acc["element_resonance"]), "同元素 3 格标记元素共鸣")
	_check(_duel.charge_points >= 1, "元素共鸣提供充能（%d）" % _duel.charge_points)


# A4：单牌永远有效——1 格也要正常造成伤害，不能要求凑牌型。
func _test_single_card() -> void:
	_equip([FIRE_SWORD])
	for r in 3:
		_duel.grid[r][0] = load(SYM_FIRE_SLASH) if r == 0 else null
		_duel.grid_elem[r][0] = "fire" if r == 0 else "none"
		_duel.reel_system._set_grid_src(r, 0, "fire_sword" if r == 0 else "")
	# 单牌场景：grid 只放一格，另外两格用 trash（不产生伤害）
	var trash = DuelController.TRASH_SYMBOL
	for r in [1, 2]:
		_duel.grid[r][0] = trash
		_duel.grid_elem[r][0] = "none"
		_duel.reel_system._set_grid_src(r, 0, "")
	_duel.enemy_element = "none"
	_duel.charge_points = 0
	var acc: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	acc["counts"] = _duel.combat._phase_symbols(acc)
	_check(_dmg(acc) > 0.0, "单牌也造成伤害（%.1f）" % _dmg(acc))
	_check(not bool(acc["triple"]), "单牌不算三连")


# B1：烈焰共鸣（2 件火装备）——现状是「只加符号权重，不改伤害」。
# flame_resonance.tres 的 element_boost 为空串，只有 weight_bonus（burn/fire_slash +2.0）；
# element_boost_mult = 1.2 因为绑定的 element_boost 为空而不会被 element_boost() 取用。
# 这条对照很关键：Step 2 要用 S01（烈焰共鸣牌谱）替换它，语义从「更容易摸到」变成「火伤 +25% + 燃烧 +1」，
# 属于真实的机制变化，必须留档。
func _test_flame_resonance() -> void:
	_equip([FIRE_SWORD, FLAME_STAFF])   # 两件 element:fire → 激活
	_check(_duel._synergy_system.active_synergies().size() >= 1, "两件火装备激活烈焰共鸣")
	var sym_fire = load(SYM_FIRE_SLASH)
	var sym_burn = load(SYM_BURN)
	var w_fire: float = _duel._synergy_system.weight_mod(sym_fire)
	var w_burn: float = _duel._synergy_system.weight_mod(sym_burn)
	_check(is_equal_approx(w_fire, 2.0) and is_equal_approx(w_burn, 2.0),
		"烈焰共鸣给火斩/燃烧各 +2 权重（%.1f / %.1f）" % [w_fire, w_burn])
	var on: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	var backup: Array = _duel._synergy_system._active.duplicate()
	_duel._synergy_system._active.clear()   # 只关共鸣、其它条件不变
	var off: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	_duel._synergy_system._active.clear()
	_duel._synergy_system._active.append_array(backup)
	_check(is_equal_approx(on, off),
		"烈焰共鸣当前不影响伤害（%.1f / %.1f）——Step 2 会把它换成伤害型牌谱" % [on, off])


# B2：冰火二重（冰火各一）→ crit_bonus +0.5，同源三连倍率 2.0 → 2.5。
func _test_frostfire() -> void:
	_equip([FIRE_SWORD, ICE_STAFF])    # element:fire + element:ice → 激活
	var on: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	var backup2: Array = _duel._synergy_system._active.duplicate()
	_duel._synergy_system._active.clear()
	var off: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	_duel._synergy_system._active.clear()
	_duel._synergy_system._active.append_array(backup2)
	_check(on > off, "冰火二重提高暴击倍率（%.1f → %.1f）" % [off, on])
	_check(absf(on / maxf(1.0, off) - 1.25) < 0.02,
		"冰火二重 = crit +0.5（倍率比 %.1f×1.25）" % [off])


# B3：黎明圣辉（圣辉长剑 + 破晓之弓）→ light 元素倍率 ×1.2。
func _test_holy_pair() -> void:
	_equip([HOLY_SWORD, DAWN_BOW])
	_check(_duel._synergy_system.active_synergies().size() >= 1, "圣辉长剑+破晓之弓激活黎明圣辉")
	var on: float = _dmg(_settle(SYM_HOLY_SLASH, "light", ["holy_sword"]))
	var backup3: Array = _duel._synergy_system._active.duplicate()
	_duel._synergy_system._active.clear()
	var off: float = _dmg(_settle(SYM_HOLY_SLASH, "light", ["holy_sword"]))
	_duel._synergy_system._active.clear()
	_duel._synergy_system._active.append_array(backup3)
	_check(absf(on / maxf(1.0, off) - 1.2) < 0.02,
		"黎明圣辉使光伤害 ×1.2（%.1f → %.1f）" % [off, on])


# C：守护——停列后直接结算，不允许任何「事后换牌」状态。
# Step 1–6 期间新增字段也要在这里显式登记，避免悄悄引入换牌窗口。
func _test_no_extra_swap_state() -> void:
	var forbidden := ["pending_swap", "awaiting_swap", "swap_tokens", "free_swap_left", "pending_redraw"]
	for name in forbidden:
		_check(_duel.get(name) == null, "不存在事后换牌状态字段 %s" % name)
	# 结算入口存在且是唯一入口：combat.evaluate 会置 turn_resolved
	_check(_duel.combat.has_method("evaluate"), "结算入口是 CombatSystem.evaluate")


const EXPECTED_CHECKS := 22


func _finish() -> void:
	# 防假绿：运行时错误会中断函数、静默少检查，只看 fails 会误判通过。
	if _checks < EXPECTED_CHECKS:
		_fails += 1
		print("PATTERNMATCH|FAIL|检查数不足：%d < %d（疑似运行时错误中断）" % [_checks, EXPECTED_CHECKS])
	print("---")
	print("PATTERNMATCH|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("PATTERNMATCH|FAIL|" + what)
