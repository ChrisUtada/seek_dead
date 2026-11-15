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

const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")
const PATTERN_SYSTEM := preload("res://scripts/battle/pattern_system.gd")
const PATTERN_DATA := preload("res://scripts/battle/pattern_data.gd")

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

	print("=== D Matcher 与现有结算一致 ===")
	_test_matcher_matches_settle()

	print("=== E Matcher 边界 ===")
	_test_matcher_edges()

	print("=== F 牌谱优先级 ===")
	_test_pattern_priority()

	print("=== G S01–S06 资源与解锁条件 ===")
	_test_equipment_patterns()

	print("=== H 牌谱效果真实生效 ===")
	_test_pattern_effects()
	_test_s04_venom()

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


# 三格分别指定符号/元素/来源（同族、清一色、牌谱判定都要用）。
func _settle_cards(syms: Array, elems: Array, sources: Array) -> Dictionary:
	for r in 3:
		_duel.grid[r][0] = load(String(syms[r]))
		_duel.grid_elem[r][0] = String(elems[r])
		_duel.reel_system._set_grid_src(r, 0, String(sources[r]))
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
	# Step 2：旧共鸣的数值效果已移除，权重提升与伤害加成都改由牌谱 S01 接管。
	_check(is_equal_approx(w_fire, 0.0) and is_equal_approx(w_burn, 0.0),
		"烈焰共鸣不再加符号权重（%.1f / %.1f）——已由 S01 接管" % [w_fire, w_burn])
	var on: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	var backup: Array = _duel._synergy_system._active.duplicate()
	_duel._synergy_system._active.clear()   # 只关共鸣、其它条件不变
	var off: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	_duel._synergy_system._active.clear()
	_duel._synergy_system._active.append_array(backup)
	_check(is_equal_approx(on, off),
		"烈焰共鸣不再直接改伤害（%.1f / %.1f）——由 S01 牌谱生效" % [on, off])


# B2：冰火二重（冰火各一）→ crit_bonus +0.5，同源三连倍率 2.0 → 2.5。
func _test_frostfire() -> void:
	_equip([FIRE_SWORD, ICE_STAFF])    # element:fire + element:ice → 激活
	var on: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	var backup2: Array = _duel._synergy_system._active.duplicate()
	_duel._synergy_system._active.clear()
	var off: float = _dmg(_settle(SYM_FIRE_SLASH, "fire", ["fire_sword"]))
	_duel._synergy_system._active.clear()
	_duel._synergy_system._active.append_array(backup2)
	# Step 2：crit_bonus 已清空，旧 ×1.25 不再出现；改由 S02 牌谱（穿透转换）接管。
	_check(is_equal_approx(on, off),
		"冰火二重不再改暴击倍率（%.1f / %.1f）——由 S02 接管" % [on, off])


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
	# Step 2：element_boost 已清空，旧 ×1.2 不再出现；改由 S03 牌谱（追加齐射）接管。
	_check(is_equal_approx(on, off),
		"黎明圣辉不再改光伤害（%.1f / %.1f）——由 S03 接管" % [on, off])


# C：守护——停列后直接结算，不允许任何「事后换牌」状态。
# Step 1–6 期间新增字段也要在这里显式登记，避免悄悄引入换牌窗口。
func _test_no_extra_swap_state() -> void:
	var forbidden := ["pending_swap", "awaiting_swap", "swap_tokens", "free_swap_left", "pending_redraw"]
	for name in forbidden:
		_check(_duel.get(name) == null, "不存在事后换牌状态字段 %s" % name)
	# 结算入口存在且是唯一入口：combat.evaluate 会置 turn_resolved
	_check(_duel.combat.has_method("evaluate"), "结算入口是 CombatSystem.evaluate")


# 当前实际条数。新增断言时同步上调：
# 运行时错误会中断函数、静默少检查，只有条数守卫能发现（见 Step 0 记录的假绿问题）。
const EXPECTED_CHECKS := 75


func _ids(patterns: Array) -> Array:
	var out: Array = []
	for p in patterns:
		out.append(String(p.get("id", "")))
	return out


# D：同一手牌，Matcher 的分类必须与现有结算一致（Step 1 的核心验收）。
func _test_matcher_matches_settle() -> void:
	# ① 同源三连
	_equip([FIRE_SWORD])
	var acc: Dictionary = _settle(SYM_FIRE_SLASH, "fire", ["fire_sword"])
	var m: Dictionary = MATCHER.match(MATCHER.cards_from_grid(_duel))
	_check(String(m["triple_kind"]) == "source",
		"同源三连：Matcher 判 source（实际 %s）" % String(m["triple_kind"]))
	_check(_ids(m["patterns"]).has("G01") and _ids(m["patterns"]).has("G02"),
		"同源同时命中 G01（同源刻）与 G02（同族刻）")
	_check(bool(acc["triple"]) == (String(m["triple_kind"]) != ""), "triple 标记与 Matcher 一致")

	# ② 同族三连（三来源各一格）
	_equip([FIRE_SWORD, EMBER_SWORD])
	var acc2: Dictionary = _settle(SYM_FIRE_SLASH, "fire", ["fire_sword", "ember_sword", "flame_staff"])
	var m2: Dictionary = MATCHER.match(MATCHER.cards_from_grid(_duel))
	_check(String(m2["triple_kind"]) == "family",
		"同族三连：Matcher 判 family（实际 %s，有效 %d，牌型 %s）" % [
			String(m2["triple_kind"]), int(m2["valid_count"]), str(_ids(m2["patterns"]))])
	_check(not _ids(m2["patterns"]).has("G01"), "多来源不命中 G01")
	_check(bool(acc2["triple"]), "现有结算也把同族算作 triple")

	# ③ 清一色（三个不同符号同元素）
	_equip([FIRE_SWORD])
	var syms := [SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH]
	for r in 3:
		_duel.grid[r][0] = load(String(syms[r]))
		_duel.grid_elem[r][0] = "fire"
		_duel.reel_system._set_grid_src(r, 0, "fire_sword" if r != 1 else "")
	_duel.enemy_element = "none"
	_duel.charge_points = 0
	var acc3: Dictionary = _duel.combat._new_acc()
	_duel.combat._reset_turn_state()
	acc3["counts"] = _duel.combat._phase_symbols(acc3)
	var m3: Dictionary = MATCHER.match(MATCHER.cards_from_grid(_duel))
	_check(_ids(m3["patterns"]).has("G03") == bool(acc3["element_resonance"]),
		"G03（清一色）与现有 element_resonance 一致")
	_check(String(m3["triple_kind"]) == "", "不同符号不构成三连（实际 %s）" % String(m3["triple_kind"]))


# E：无序 / 重复牌 / 冻结列 / MISS / 无元素 / 来源去重
func _test_matcher_edges() -> void:
	var sym_fire = load(SYM_FIRE_SLASH)
	var sym_burn = load(SYM_BURN)
	var trash = DuelController.TRASH_SYMBOL

	# 无序：三种排列结果一致
	var base := [
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
	]
	var p1: Dictionary = MATCHER.match(base)
	var p2: Dictionary = MATCHER.match([base[2], base[0], base[1]])
	var p3: Dictionary = MATCHER.match([base[1], base[2], base[0]])
	_check(p1["triple_kind"] == p2["triple_kind"] and p1["triple_kind"] == p3["triple_kind"],
		"无序：三种排列判定一致")
	_check(_ids(p1["patterns"]).size() == _ids(p2["patterns"]).size(),
		"无序：命中牌型数量一致")

	# 重复牌（只有 2 张同族）：不算三连，但两张仍然有效
	var dup := [
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_burn, "element": "fire", "source": "w", "valid": true},
	]
	var d: Dictionary = MATCHER.match(dup)
	_check(d["triple_kind"] == "", "两张同族不算三连")
	_check(d["valid_count"] == 3, "三张都算有效牌（%d）" % int(d["valid_count"]))
	_check(_ids(d["patterns"]).has("G03"), "同元素仍命中清一色")

	# 冻结列：那一格不参与，三格变两格 → 没有三连
	var frozen := [
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": false},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
	]
	var f: Dictionary = MATCHER.match(frozen)
	_check(f["valid_count"] == 2, "冻结列算无效牌（有效 %d）" % int(f["valid_count"]))
	_check(f["triple_kind"] == "", "冻结列后不构成三连")
	_check(String(f["reason"]) == "not_enough_valid", "冻结后给出 not_enough_valid")

	# MISS / 废铁：trash 不算有效牌
	var miss := [
		{"sym": trash, "element": "none", "source": "", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "w", "valid": true},
	]
	var mi: Dictionary = MATCHER.match(miss)
	_check(mi["valid_count"] == 2, "MISS/废铁不算有效牌（%d）" % int(mi["valid_count"]))
	_check(mi["triple_kind"] == "", "含废铁不构成三连")

	# 无元素：三格同符号 none → 三连成立，但不命中清一色
	var none_cards := [
		{"sym": sym_fire, "element": "none", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "none", "source": "w", "valid": true},
		{"sym": sym_fire, "element": "none", "source": "w", "valid": true},
	]
	var nc: Dictionary = MATCHER.match(none_cards)
	_check(nc["triple_kind"] == "source", "无元素仍可构成三连")
	_check(not _ids(nc["patterns"]).has("G03"), "none 不构成清一色")

	# 来源去重：同符号同来源 = 同源；同符号多来源 = 同族
	var one_src: Dictionary = MATCHER.match(base)
	_check(one_src["triple_kind"] == "source", "单一来源 = 同源刻")
	var multi_src := [
		{"sym": sym_fire, "element": "fire", "source": "a", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "b", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "c", "valid": true},
	]
	var ms: Dictionary = MATCHER.match(multi_src)
	_check(ms["triple_kind"] == "family", "三个不同来源 = 同族刻（实际 %s）" % String(ms["triple_kind"]))
	# 空来源（技能符号）不能算同源刻
	var no_src := [
		{"sym": sym_fire, "element": "fire", "source": "", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "", "valid": true},
		{"sym": sym_fire, "element": "fire", "source": "", "valid": true},
	]
	_check(String(MATCHER.match(no_src)["triple_kind"]) == "family", "空来源只算同族，不算同源")


# F：装备牌谱每回合至多一条；priority 降序、同优先级 id 升序；连携优先
func _test_pattern_priority() -> void:
	var sys = PATTERN_SYSTEM.new()
	var p_low = PATTERN_DATA.new()
	p_low.id = "S_LOW"; p_low.priority = 1; p_low.kind = "equipment"; p_low.assist_allowed = true
	var p_hi_a = PATTERN_DATA.new()
	p_hi_a.id = "S_HI_A"; p_hi_a.priority = 9; p_hi_a.kind = "equipment"; p_hi_a.assist_allowed = true
	var p_hi_b = PATTERN_DATA.new()
	p_hi_b.id = "S_HI_B"; p_hi_b.priority = 9; p_hi_b.kind = "equipment"; p_hi_b.assist_allowed = true
	var p_g = PATTERN_DATA.new()
	p_g.id = "G01"; p_g.priority = 100; p_g.kind = "universal"
	for p in [p_low, p_hi_a, p_hi_b, p_g]:
		sys.register(p)
	_check(sys.all_patterns().size() == 4, "注册 4 条牌谱")

	var matched := ["S_LOW", "S_HI_A", "S_HI_B", "G01"]
	var unlocked: Array = sys.all_patterns()
	var pick = sys.resolve_equipment(matched, unlocked)
	_check(pick != null and String(pick.id) == "S_HI_A",
		"同优先级按 id 升序取第一条（%s）" % ("null" if pick == null else String(pick.id)))
	# 通用牌型即使 priority 更高，也不参与「装备一条」的竞争
	_check(pick != null and not bool(pick.is_universal()), "通用牌型不进装备选择")
	var uni: Array = sys.resolve_universal(matched, unlocked)
	_check(uni.size() == 1 and String(uni[0].id) == "G01", "通用牌型独立返回")
	# 连携指定的牌谱优先
	var assisted = sys.resolve_equipment(matched, unlocked, "S_LOW")
	_check(assisted != null and String(assisted.id) == "S_LOW", "连携已确定的牌谱优先")
	# 没有命中时不挑任何装备牌谱
	_check(sys.resolve_equipment([], unlocked) == null, "无命中时返回 null（不硬塞）")
	# 补牌候选：排除已命中的
	var cands: Array = sys.assist_candidates(unlocked, ["S_HI_A"])
	var cand_ids: Array = []
	for c in cands:
		cand_ids.append(String(c.id))
	_check(not cand_ids.has("S_HI_A") and cand_ids.has("S_LOW"), "补牌候选排除已命中的牌谱")


# G：Step 1 第 5 点——S01–S03 的资源就位、解锁条件正确。
# 效果实装在 Step 2（本轮故意不动旧共鸣的结算），所以这里只验数据与解锁。
func _test_equipment_patterns() -> void:
	var sys = PATTERN_SYSTEM.new()
	for f in ["s01_flame_resonance", "s02_frostfire_dual", "s03_holy_volley"]:
		var pd = load("res://resources/patterns/%s.tres" % f)
		_check(pd != null, "牌谱资源可加载 %s" % f)
		if pd != null:
			sys.register(pd)
	_check(sys.all_patterns().size() == 3, "注册 S01–S03 三条（%d）" % sys.all_patterns().size())

	var tag_of := func(path: String) -> Array:
		var wd = load(path)
		if wd == null:
			return []
		var out: Array = []
		for t in (wd.family_tags as Array):
			out.append(String(t))
		var e := String(wd.element)
		if e != "" and e != "none":
			out.append("element:" + e)
		return out

	# S01 需要两件火装备
	_check(not bool(sys.get_pattern("S01").unlocked([FIRE_SWORD], tag_of)),
		"单件火装备不解锁 S01")
	_check(bool(sys.get_pattern("S01").unlocked([FIRE_SWORD, FLAME_STAFF], tag_of)),
		"两件火装备解锁 S01")
	# S02 需要冰、火各一
	_check(bool(sys.get_pattern("S02").unlocked([FIRE_SWORD, ICE_STAFF], tag_of)),
		"冰+火各一件解锁 S02")
	_check(not bool(sys.get_pattern("S02").unlocked([FIRE_SWORD, FLAME_STAFF], tag_of)),
		"两件火不解锁 S02")
	# S03 按精确路径
	_check(bool(sys.get_pattern("S03").unlocked([HOLY_SWORD, DAWN_BOW], tag_of)),
		"圣辉长剑+破晓之弓解锁 S03")
	_check(not bool(sys.get_pattern("S03").unlocked([HOLY_SWORD, FIRE_SWORD], tag_of)),
		"只有圣辉长剑不解锁 S03")
	# 解锁集只返回满足条件的
	var unlocked: Array = sys.unlocked_patterns([FIRE_SWORD, ICE_STAFF], tag_of)
	var ids: Array = []
	for p in unlocked:
		ids.append(String(p.id))
	# 火+冰各一件：S02（各一件）满足；S01 需要两件火，不满足；S03 需要两把指定武器，不满足
	_check(ids.has("S02") and not ids.has("S01") and not ids.has("S03"),
		"火+冰各一件只解锁 S02（%s）" % str(ids))


# H：S01 / S05 的效果必须真的写进累计器（Step 2 的核心）。
func _test_pattern_effects() -> void:
	# —— S01 烈焰共鸣：火斩 + 燃烧 + 任意火，本轮火系伤害 +25% ——
	_equip([FIRE_SWORD, FLAME_STAFF])
	var acc: Dictionary = _settle_cards(
		[SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH],
		["fire", "fire", "fire"],
		["fire_sword", "fire_sword", "flame_staff"])
	var fire_before: float = float((acc["dmg_by_elem"] as Dictionary).get("fire", 0.0))
	var dmg_before: float = float(acc["dmg"]) + float(acc["special"])
	_duel.combat._apply_patterns(acc)
	var dmg_after: float = float(acc["dmg"]) + float(acc["special"])
	_check(String(acc.get("pattern_equipment", "")) == "S01",
		"S01 被判定为生效牌谱（%s）" % String(acc.get("pattern_equipment", "")))
	_check(dmg_after > dmg_before, "S01 提高本轮伤害（%.1f → %.1f）" % [dmg_before, dmg_after])
	_check(absf((dmg_after - dmg_before) - fire_before * 0.25) < 1.0,
		"S01 加成 = 火系伤害 ×25%%（+%.1f，期望 %.1f）" % [dmg_after - dmg_before, fire_before * 0.25])
	# 牌谱新增的状态写在 pattern_status（status_stacks 在 _phase_defense 已落地过）
	_check(int((acc.get("pattern_status", {}) as Dictionary).get("burn", 0)) > 0,
		"S01 给燃烧加层（%d）" % int((acc.get("pattern_status", {}) as Dictionary).get("burn", 0)))

	# —— 装备不足时不触发 ——
	_equip([FIRE_SWORD])
	var acc2: Dictionary = _settle_cards(
		[SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH],
		["fire", "fire", "fire"],
		["fire_sword", "fire_sword", "fire_sword"])
	_duel.combat._apply_patterns(acc2)
	_check(String(acc2.get("pattern_equipment", "")) == "",
		"单件火装备不触发 S01（%s）" % String(acc2.get("pattern_equipment", "")))

	# —— S05 盾击连携：护盾 ×2 + 任意，+8 护盾并转 50% 伤害 ——
	var guard_path := "res://resources/symbols/guard.tres"
	var block_path := "res://resources/symbols/block.tres"
	# 需要两件 shield 家族装备才能解锁，这里直接手注册一条临时牌谱验证效果层
	var pd = PATTERN_DATA.new()
	pd.id = "T_S05"; pd.kind = "equipment"; pd.priority = 1
	pd.match_rule = {"all": [{"kind": "shield"}, {"kind": "shield"}, {}]}
	pd.effect_id = "shield_bash"; pd.effect_params = {"shield_flat": 8, "damage_ratio": 0.5}
	var sys = PATTERN_SYSTEM.new()
	sys.register(pd)
	_equip([DAGGER])
	var acc3: Dictionary = _settle_cards([guard_path, block_path, SYM_FIRE_SLASH],
		["none", "none", "none"], ["dagger", "dagger", "dagger"])
	var shield_before: int = int(acc3["shield"])
	var dmg3_before: float = float(acc3["dmg"])
	var cards: Array = MATCHER.cards_from_grid(_duel)
	_check(MATCHER.solve_rule(cards, pd.match_rule), "两张盾牌满足 S05 的 match_rule")
	var unlocked3: Array = sys.unlocked_patterns([DAGGER], func(_p): return [])
	var pick = sys.resolve_equipment(MATCHER.match_rules(cards, unlocked3), unlocked3)
	_check(pick != null and String(pick.id) == "T_S05", "S05 牌谱可被解析选中")
	if pick != null:
		var effects = preload("res://scripts/battle/pattern_effects.gd")
		effects.apply(acc3, pick, {"ctrl": _duel})
		_check(int(acc3["shield"]) == shield_before + 8,
			"S05 额外 +8 护盾（%d → %d）" % [shield_before, int(acc3["shield"])])
		_check(float(acc3["dmg"]) > dmg3_before, "S05 把护盾转成伤害（%.1f → %.1f）" % [dmg3_before, float(acc3["dmg"])])


# H2：S04 毒爆连携——按 StatusSystem 真实口径算「毒 tick 的 50%」，且不消耗毒层。
func _test_s04_venom() -> void:
	var poison_weapon := "res://resources/weapon_templates/blight_spear.tres"
	var poison_weapon2 := "res://resources/weapon_templates/corrosive_bow.tres"
	var sym_venom := "res://resources/symbols/venom_bite.tres"
	var sym_poison := "res://resources/symbols/poison.tres"
	_equip([poison_weapon, poison_weapon2])
	_duel.enemy_status.clear()
	_duel.enemy_status["poison"] = 4          # 先有 4 层
	var acc: Dictionary = _settle_cards([sym_venom, sym_poison, sym_venom],
		["poison", "poison", "poison"], ["blight_spear", "blight_spear", "blight_spear"])
	_duel.combat._apply_patterns(acc)
	_check(String(acc.get("pattern_equipment", "")) == "S04",
		"S04 被判定为生效牌谱（%s）" % String(acc.get("pattern_equipment", "")))
	# 层数：+2
	var ps: Dictionary = acc.get("pattern_status", {})
	_check(int(ps.get("poison", 0)) == 2, "S04 中毒 +2 层（%d）" % int(ps.get("poison", 0)))
	# 即时伤害 = (现有4 + 新增2) × base × 元素倍率 × 护符 × 50%
	var base := float(_duel.status_system.status_base("poison"))
	var mult: float = ElementCounter.multiplier("poison", String(_duel.enemy_element))
	var expect := 6.0 * base * mult * 0.5
	_check(float(acc["pierce"]) >= expect - 0.5,
		"S04 立即结算毒 tick 的 50%%（穿透 %.1f，期望 ≥%.1f）" % [float(acc["pierce"]), expect])
	# 不消耗毒层：+2 落地后是 6，即时结算没有再扣层（若是「消耗型」会小于 6）
	_check(int(_duel.enemy_status.get("poison", 0)) == 6,
		"S04 中毒 +2 落地且即时结算不消耗层数（4 → %d，期望 6）" % int(_duel.enemy_status.get("poison", 0)))


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
