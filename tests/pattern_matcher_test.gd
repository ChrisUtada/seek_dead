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

	print("=== M 六条参数签名 ===")
	_test_param_signatures()

	print("=== L 签名样板 ===")
	_test_signatures()

	print("=== K T01/T03 术式 ===")
	_test_t01_t03()

	print("=== J W02/W05/W06 效果 ===")
	_test_w02_w05_w06()

	print("=== I 三轨隔离 ===")
	_test_tracks()

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


const SKILL_AEGIS := "res://resources/skills/aegis.tres"


func _equip(paths: Array, skills: Array = []) -> void:
	_duel.selected_skills.clear()
	for sk in skills:
		_duel.selected_skills.append(String(sk))
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
const EXPECTED_CHECKS := 101


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
	for f in ["w01_flame_resonance", "s02_frostfire_dual", "w04_holy_volley", "w03_venom_burst"]:
		var pd = load("res://resources/patterns/%s.tres" % f)
		_check(pd != null, "牌谱资源可加载 %s" % f)
		if pd != null:
			sys.register(pd)
	_check(sys.all_patterns().size() == 4, "注册 W01/W03/W04 与签名候选 SIG02（%d）" % sys.all_patterns().size())

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
	_check(not bool(sys.get_pattern("W01").unlocked([FIRE_SWORD], tag_of)),
		"单件火装备不解锁 S01")
	_check(bool(sys.get_pattern("W01").unlocked([FIRE_SWORD, FLAME_STAFF], tag_of)),
		"两件火装备解锁 S01")
	# S02 需要冰、火各一
	_check(bool(sys.get_pattern("SIG02").unlocked([FIRE_SWORD, ICE_STAFF], tag_of)),
		"冰+火各一件解锁 S02")
	_check(not bool(sys.get_pattern("SIG02").unlocked([FIRE_SWORD, FLAME_STAFF], tag_of)),
		"两件火不解锁 S02")
	# S03 按精确路径
	_check(bool(sys.get_pattern("W04").unlocked([HOLY_SWORD, DAWN_BOW], tag_of)),
		"圣辉长剑+破晓之弓解锁 S03")
	_check(not bool(sys.get_pattern("W04").unlocked([HOLY_SWORD, FIRE_SWORD], tag_of)),
		"只有圣辉长剑不解锁 S03")
	# 解锁集只返回满足条件的
	var unlocked: Array = sys.unlocked_patterns([FIRE_SWORD, ICE_STAFF], tag_of)
	var ids: Array = []
	for p in unlocked:
		ids.append(String(p.id))
	# 火+冰各一件：S02（各一件）满足；S01 需要两件火，不满足；S03 需要两把指定武器，不满足
	_check(ids.has("SIG02") and not ids.has("W01") and not ids.has("W04"),
		"火+冰各一件只解锁 SIG02（%s）" % str(ids))


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
	_check(String(acc.get("pattern_equipment", "")) == "W01",
		"S01 被判定为生效牌谱（%s）" % String(acc.get("pattern_equipment", "")))
	_check(dmg_after > dmg_before, "S01 提高本轮伤害（%.1f → %.1f）" % [dmg_before, dmg_after])
	# 火焰剑在场 → SIG_W01_FIRESWORD 生效，倍率从 1.25 提到 1.30
	_check(String(acc.get("pattern_signature", "")) == "SIG_W01_FIRESWORD",
		"火焰剑签名生效（%s）" % String(acc.get("pattern_signature", "")))
	_check(absf((dmg_after - dmg_before) - fire_before * 0.30) < 1.0,
		"W01 带签名时火系伤害 +30%%（+%.1f，期望 %.1f）" % [dmg_after - dmg_before, fire_before * 0.30])
	# 换一对无签名的火武器，验证基础 25%
	_equip(["res://resources/weapon_templates/cinder_cleaver.tres",
		"res://resources/weapon_templates/cinder_hatchet.tres"])
	var acc_b: Dictionary = _settle_cards(
		[SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH],
		["fire", "fire", "fire"],
		["cinder_cleaver", "cinder_cleaver", "cinder_hatchet"])
	var fire_b: float = float((acc_b["dmg_by_elem"] as Dictionary).get("fire", 0.0))
	var dmg_b: float = float(acc_b["dmg"]) + float(acc_b["special"])
	_duel.combat._apply_patterns(acc_b)
	_check(String(acc_b.get("pattern_signature", "")) == "", "无高阶火武器时不触发签名")
	_check(absf(((float(acc_b["dmg"]) + float(acc_b["special"])) - dmg_b) - fire_b * 0.25) < 1.0,
		"W01 无签名时火系伤害 +25%%（基础值）")
	# 牌谱新增的状态写在 pattern_status（status_stacks 在 _phase_defense 已落地过）
	_check(int((acc.get("pattern_status", {}) as Dictionary).get("burn", 0)) > 0,
		"S01 给燃烧加层（%d）" % int((acc.get("pattern_status", {}) as Dictionary).get("burn", 0)))
	# 演出：牌谱触发时应有横幅（中频高潮的「那一下」）
	var banner = _duel.hud.get("_pattern_banner")
	_check(banner != null and is_instance_valid(banner),
		"牌谱触发时有横幅演出")
	if banner != null and is_instance_valid(banner):
		var texts := ""
		for child in banner.get_children():
			if child is Label:
				texts = String((child as Label).text)
		_check(texts.find("W01") >= 0, "横幅文本含牌谱 id（%s）" % texts)
	# 常驻面板暂时关闭显示（实机上字号过大、遮挡左上 UI）。这里钉住「默认不显示」，
	# 防止以后不小心又打开却没调整表现。实现与数据层保留，开关见 battle_hud.PATTERN_TRAY_ENABLED。
	var tray = _duel.hud.get("_pattern_tray")
	_check(tray == null, "常驻面板默认不显示（实机遮挡问题待表现方案）")

	# —— 装备不足时不触发 ——
	_equip([FIRE_SWORD])
	var acc2: Dictionary = _settle_cards(
		[SYM_FIRE_SLASH, SYM_BURN, SYM_FIRE_SLASH],
		["fire", "fire", "fire"],
		["fire_sword", "fire_sword", "fire_sword"])
	_duel.combat._apply_patterns(acc2)
	_check(String(acc2.get("pattern_equipment", "")) == "",
		"单件火装备不触发 S01（%s）" % String(acc2.get("pattern_equipment", "")))

	# —— S05/S06 已退役：它们的 effect_id 不再被分发，牌谱也不在武器轨 ——
	var retired := 0
	for f in DirAccess.get_files_at("res://resources/patterns"):
		if f.ends_with(".tres"):
			var pd2 = load("res://resources/patterns/" + f)
			if pd2 != null and (String(pd2.id) == "S05" or String(pd2.id) == "S06"):
				retired += 1
	_check(retired == 0, "S05/S06 资源已删除（残留 %d）" % retired)


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
	_check(String(acc.get("pattern_equipment", "")) == "W03",
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


# M：六条纯参数签名——效果值必须真的被改写，且两把武器各带签名时有确定的裁决。
func _test_param_signatures() -> void:
	var W := "res://resources/weapon_templates/"
	var SYM_SHADOW := "res://resources/symbols/shadow_slash.tres"
	# 先确认这些签名真的被注册（tres 解析失败会静默跳过）
	var sig_ids: Array = []
	for pd in _duel._pattern_system.by_track("signature"):
		sig_ids.append(String(pd.id))
	_check(sig_ids.size() >= 11, "签名资源全部注册（%d 个：%s）" % [sig_ids.size(), str(sig_ids)])
	# —— 余烬长剑 × W01：火伤 25% → 35%，燃烧 +2 ——
	_equip([W+"ember_sword.tres", W+"fire_sword.tres"])
	var a: Dictionary = _settle_cards([SYM_BURN, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["fire", "none", "none"], ["ember_sword", "ember_sword", "fire_sword"])
	var fire_a: float = float((a["dmg_by_elem"] as Dictionary).get("fire", 0.0))
	var d_a: float = float(a["dmg"]) + float(a["special"])
	_duel.combat._apply_patterns(a)
	_check(String(a.get("pattern_signature", "")) == "SIG_W01_EMBER",
		"余烬长剑签名生效（%s）" % String(a.get("pattern_signature", "")))
	_check(absf(((float(a["dmg"]) + float(a["special"])) - d_a) - fire_a * 0.35) < 1.0,
		"余烬长剑把火伤加成提到 +35%%")
	_check(int((a.get("pattern_status", {}) as Dictionary).get("burn", 0)) == 2, "燃烧 +2")

	# —— 冰霜枪 × W02：霜冻 +3，阈值 3 ——
	_equip([W+"ice_gun.tres", W+"ice_staff.tres"])
	_duel.enemy_status.clear()
	_duel.enemy_status["frost"] = 0
	_duel._pattern_enemy_atk_mult = 1.0
	var b: Dictionary = _settle_cards(["res://resources/symbols/frost.tres", "res://resources/symbols/ice_crystal.tres", "res://resources/symbols/ice_crystal.tres"],
		["ice", "ice", "ice"], ["ice_gun", "ice_gun", "ice_staff"])
	_duel.combat._apply_patterns(b)
	_check(String(b.get("pattern_signature", "")) == "SIG_W02_ICEGUN",
		"冰霜枪签名生效（%s）" % String(b.get("pattern_signature", "")))
	_check(int((b.get("pattern_status", {}) as Dictionary).get("frost", 0)) == 3, "霜冻 +3")
	_check(is_equal_approx(float(_duel._pattern_enemy_atk_mult), 0.85), "冰霜枪阈值 3 层即削弱到 ×0.85")

	# —— 冰川巨剑 × W02：×0.6 ——
	_equip([W+"glacier_greatsword.tres", W+"ice_staff.tres"])
	_duel.enemy_status.clear()
	_duel.enemy_status["frost"] = 4
	_duel._pattern_enemy_atk_mult = 1.0
	var c: Dictionary = _settle_cards(["res://resources/symbols/frost.tres", "res://resources/symbols/ice_crystal.tres", "res://resources/symbols/ice_crystal.tres"],
		["ice", "ice", "ice"], ["glacier_greatsword", "glacier_greatsword", "ice_staff"])
	_duel.combat._apply_patterns(c)
	_check(String(c.get("pattern_signature", "")) == "SIG_W02_GLACIER",
		"冰川巨剑签名生效（%s）" % String(c.get("pattern_signature", "")))
	_check(is_equal_approx(float(_duel._pattern_enemy_atk_mult), 0.6), "冰川巨剑把敌方攻击压到 ×0.6")

	# —— 瘟疫收割者 × W03：中毒 +3、即时 60% ——
	_equip([W+"plague_reaper.tres", W+"corrosive_bow.tres"])
	_duel.enemy_status.clear()
	_duel.enemy_status["poison"] = 4
	var d: Dictionary = _settle_cards(["res://resources/symbols/venom_bite.tres", "res://resources/symbols/poison.tres", "res://resources/symbols/venom_bite.tres"],
		["poison", "poison", "poison"], ["plague_reaper", "plague_reaper", "corrosive_bow"])
	_duel.combat._apply_patterns(d)
	_check(String(d.get("pattern_signature", "")) == "SIG_W03_REAPER",
		"瘟疫收割者签名生效（%s）" % String(d.get("pattern_signature", "")))
	_check(int((d.get("pattern_status", {}) as Dictionary).get("poison", 0)) == 3, "中毒 +3")

	# —— 蚀日之刃 × W05：35% / 处决线 60% ——
	_equip([W+"eclipse_blade.tres", W+"night_scythe.tres"])
	_duel.enemy_hp = 800          # 80%：高于签名的处决线 60% → 走 pierce_ratio 0.35
	_duel.enemy_hp_max = 1000
	var e: Dictionary = _settle_cards(["res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres"],
		["dark", "dark", "dark"], ["eclipse_blade", "night_scythe", "eclipse_blade"])
	var bucket_e: float = float((e["dmg_bucket_by_elem"] as Dictionary).get("dark", 0.0))
	var dmg_e: float = float(e["dmg"])
	_duel.combat._apply_patterns(e)
	# 两把武器各带签名（蚀日之刃 epic / 夜幕镰刀 rare），同 prio 20 → 按 id 升序 ECLIPSE 胜，裁决必须确定
	_check(String(e.get("pattern_signature", "")) == "SIG_W05_ECLIPSE",
		"两把暗武器都有签名时裁决确定（%s）" % String(e.get("pattern_signature", "")))
	_check(absf((dmg_e - float(e["dmg"])) - bucket_e * 0.35) < 1.0,
		"蚀日之刃常态转移 35%" )
	# 处决线以下（签名把阈值提到 60%）→ 走 exec_ratio 0.6
	_duel.enemy_hp = 500
	var e2: Dictionary = _settle_cards([SYM_SHADOW, SYM_SHADOW, SYM_SHADOW],
		["dark", "dark", "dark"], ["eclipse_blade", "night_scythe", "eclipse_blade"])
	var bucket_e2: float = float((e2["dmg_bucket_by_elem"] as Dictionary).get("dark", 0.0))
	var dmg_e2: float = float(e2["dmg"])
	_duel.combat._apply_patterns(e2)
	_check(absf((dmg_e2 - float(e2["dmg"])) - bucket_e2 * 0.6) < 1.0,
		"蚀日之刃处决线（HP 50%% < 阈值 60%%）转移 60%%")

	# —— 处刑巨斧 × W06：+35% ——
	_equip([W+"executioner_axe.tres", W+"iron_sword.tres"])
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	var f: Dictionary = _settle_cards([SYM_FIRE_SLASH, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["executioner_axe", "iron_sword", "executioner_axe"])
	var none_f: float = float((f["dmg_by_elem"] as Dictionary).get("none", 0.0))
	var dmg_f: float = float(f["dmg"])
	_duel.combat._apply_patterns(f)
	_check(String(f.get("pattern_signature", "")) == "SIG_W06_EXECAXE",
		"处刑巨斧签名生效（%s）" % String(f.get("pattern_signature", "")))
	_check(absf((float(f["dmg"]) - dmg_f) - none_f * 0.35) < 1.0, "处刑巨斧无元素伤害 +35%")


# L：四条签名样板——绝对零度 × W02、火焰法杖 × W01、卸下即失效、不要求第三把武器。
func _test_signatures() -> void:
	var AZ := "res://resources/weapon_templates/absolute_zero.tres"
	var ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
	var FROST_BLADE := "res://resources/weapon_templates/frost_blade.tres"
	var ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
	var FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
	var SYM_FROST := "res://resources/symbols/frost.tres"
	var SYM_ICE := "res://resources/symbols/ice_crystal.tres"
	var SYM_FLAME_SPECIAL := "res://resources/symbols/flame_special.tres"

	# —— 绝对零度 × W02：霜冻 +3、敌方攻击 ×0.7 ——
	_equip([AZ, ICE_GUN])
	_duel.enemy_status.clear()
	_duel.enemy_status["frost"] = 2
	_duel._pattern_enemy_atk_mult = 1.0
	var az: Dictionary = _settle_cards([SYM_FROST, SYM_ICE, SYM_ICE],
		["ice", "ice", "ice"], ["absolute_zero", "absolute_zero", "ice_gun"])
	_duel.combat._apply_patterns(az)
	_check(String(az.get("pattern_signature", "")) == "SIG_W02_ZERO",
		"绝对零度签名生效（%s）" % String(az.get("pattern_signature", "")))
	_check(int((az.get("pattern_status", {}) as Dictionary).get("frost", 0)) == 3,
		"签名把霜冻提高到 +3（%d）" % int((az.get("pattern_status", {}) as Dictionary).get("frost", 0)))
	_check(is_equal_approx(float(_duel._pattern_enemy_atk_mult), 0.7),
		"签名把敌方攻击削弱提高到 ×0.7（%.2f）" % float(_duel._pattern_enemy_atk_mult))
	# 只带两把武器，不依赖第三个槽
	_check(_duel.selected_loadout.size() == 2, "签名只需两把武器（%d）" % _duel.selected_loadout.size())

	# —— 火焰法杖 × W01：需要炎爆出现；且比火焰剑签名优先 ——
	_equip([FLAME_STAFF, FIRE_SWORD])
	var fs: Dictionary = _settle_cards([SYM_BURN, SYM_FLAME_SPECIAL, SYM_FIRE_SLASH],
		["fire", "fire", "none"], ["flame_staff", "flame_staff", "fire_sword"])
	var fire_before: float = float((fs["dmg_by_elem"] as Dictionary).get("fire", 0.0))
	var dmg_before_fs: float = float(fs["dmg"]) + float(fs["special"])
	_duel.combat._apply_patterns(fs)
	_check(String(fs.get("pattern_signature", "")) == "SIG_W01_FLAMESTAFF",
		"火焰法杖签名优先于火焰剑签名（%s）" % String(fs.get("pattern_signature", "")))
	_check(absf(((float(fs["dmg"]) + float(fs["special"])) - dmg_before_fs) - fire_before * 0.40) < 1.5,
		"火焰法杖签名把火系加成提到 +40%")

	# —— 圣辉长剑 × W04：齐射 50% → 80%（光系补了 rare 后才有这条签名） ——
	var DAWN_BOW := "res://resources/weapon_templates/dawn_bow.tres"
	var HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
	var SYM_DAWN := "res://resources/symbols/dawn_bolt.tres"
	_equip([HOLY_SWORD, DAWN_BOW])
	var hv: Dictionary = _settle_cards([SYM_HOLY_SLASH, SYM_DAWN, SYM_HOLY_SLASH],
		["light", "light", "light"], ["holy_sword", "dawn_bow", "holy_sword"])
	_duel.combat._apply_patterns(hv)
	_check(String(hv.get("pattern_signature", "")) == "SIG_W04_HOLYSWORD",
		"圣辉长剑 × W04 签名生效（%s）" % String(hv.get("pattern_signature", "")))
	_check(float(hv["pierce"]) > 0.0, "W04 齐射进入穿透（%.0f）" % float(hv["pierce"]))

	# —— 卸下关键武器 → 签名立即失效 ——
	_equip([FIRE_SWORD, FLAME_STAFF])
	var with_key: Dictionary = _settle_cards([SYM_BURN, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["fire", "none", "none"], ["fire_sword", "fire_sword", "flame_staff"])
	_duel.combat._apply_patterns(with_key)
	_check(String(with_key.get("pattern_signature", "")) != "", "装备关键武器时签名生效")
	_equip(["res://resources/weapon_templates/cinder_cleaver.tres",
		"res://resources/weapon_templates/cinder_hatchet.tres"])
	var without_key: Dictionary = _settle_cards([SYM_BURN, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["fire", "none", "none"], ["cinder_cleaver", "cinder_cleaver", "cinder_hatchet"])
	_duel.combat._apply_patterns(without_key)
	_check(String(without_key.get("pattern_signature", "")) == "",
		"卸下关键武器后签名立即失效（%s）" % String(without_key.get("pattern_signature", "")))
	_check(String(without_key.get("pattern_equipment", "")) == "W01",
		"基础牌谱仍然生效（%s）" % String(without_key.get("pattern_equipment", "")))


# K：T01 增伤术式（只强化武器）与 T03 恢复术式（满血不激活）。
func _test_t01_t03() -> void:
	var SKILL_POWER := "res://resources/skills/focus.tres"       # 蓄势：buff_effect = power
	var SKILL_HEAL := "res://resources/skills/herbal_tonic.tres"  # 草药汤：kind = heal
	var power_sym := String((load(SKILL_POWER) as SkillData).symbol.resource_path)
	var heal_sym := String((load(SKILL_HEAL) as SkillData).symbol.resource_path)

	# —— T01：power 技能 + 武器伤害牌 + 武器牌 ——
	_equip([FIRE_SWORD, FLAME_STAFF], [SKILL_POWER])
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	var a1: Dictionary = _settle_cards([power_sym, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "fire_sword", "flame_staff"])
	var dmg_before1: float = float(a1["dmg"]) + float(a1["special"])
	var total1 := 0.0
	for e in (a1["dmg_by_elem"] as Dictionary):
		total1 += float(a1["dmg_by_elem"][e])
	_duel.combat._apply_patterns(a1)
	_check(String(a1.get("pattern_skill", "")) == "T01",
		"power 技能触发 T01（实际 %s）" % String(a1.get("pattern_skill", "")))
	var bonus1: float = (float(a1["dmg"]) + float(a1["special"])) - dmg_before1
	_check(absf(bonus1 - total1 * 0.15) < 1.0,
		"T01 武器伤害 +15%%（+%.1f，期望 %.1f）" % [bonus1, total1 * 0.15])

	# —— T03：未满血时激活，治疗 +25% ——
	_equip([DAGGER, FIRE_SWORD], [SKILL_HEAL])
	_duel.player_hp_max = 100
	_duel.player_hp = 50
	var a3: Dictionary = _settle_cards([heal_sym, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "dagger", "fire_sword"])
	var heal_before: float = float(a3["heal"])
	_duel.combat._apply_patterns(a3)
	_check(String(a3.get("pattern_skill", "")) == "T03",
		"未满血时 heal 技能触发 T03（实际 %s）" % String(a3.get("pattern_skill", "")))
	_check(heal_before > 0.0 and float(a3["heal"]) > heal_before,
		"T03 提升本轮治疗（%.1f → %.1f）" % [heal_before, float(a3["heal"])])
	_check(bool(a3.get("recovery_purify", false)) == bool(_duel.debuffs.active.size() > 0),
		"HP≤50% 时标记净化（当前有减益时才算成功）")

	# —— T03 低血线真的移除一个减益（purify_one） ——
	_duel.debuffs.reset()
	_duel.debuffs.apply(_duel, "blind", 2)          # 干扰类，优先被净化
	_duel.debuffs.apply(_duel, "weak", 2)           # 状态类，排在后面
	_check(_duel.debuffs.has("blind") and _duel.debuffs.has("weak"), "测试前两个减益都在")
	_duel.player_hp_max = 100
	_duel.player_hp = 40
	var a3p: Dictionary = _settle_cards([heal_sym, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "dagger", "fire_sword"])
	_duel.combat._apply_patterns(a3p)
	_check(String(a3p.get("pattern_skill", "")) == "T03", "低血线触发 T03")
	_check(not _duel.debuffs.has("blind"), "T03 净化掉干扰类减益（优先）")
	_check(_duel.debuffs.has("weak"), "状态类减益保留（每次只净化一个）")
	_check(bool(a3p.get("recovery_purify", false)), "T03 记录净化发生在本次结算")
	_duel.debuffs.reset()

	# —— T03 满血不激活 ——
	_duel.player_hp = 100
	var a3b: Dictionary = _settle_cards([heal_sym, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "dagger", "fire_sword"])
	_duel.combat._apply_patterns(a3b)
	_check(String(a3b.get("pattern_skill", "")) == "",
		"满血时 T03 不激活（实际 %s）" % String(a3b.get("pattern_skill", "")))


# J：W02 霜封 / W05 暗影处刑 / W06 无锋磨砺 的效果与结算口径。
func _test_w02_w05_w06() -> void:
	var ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
	var FROST_BLADE := "res://resources/weapon_templates/frost_blade.tres"
	var ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
	var SYM_FROST := "res://resources/symbols/frost.tres"
	var SYM_ICE := "res://resources/symbols/ice_crystal.tres"
	var NIGHT := "res://resources/weapon_templates/night_scythe.tres"
	var ABYSS := "res://resources/weapon_templates/abyss_scythe.tres"
	var SYM_SHADOW := "res://resources/symbols/shadow_slash.tres"
	var IRON := "res://resources/weapon_templates/iron_sword.tres"

	# —— W02 霜封：霜冻 +2；已有 ≥4 层时敌方攻击 ×0.8 ——
	# 用一对「没有签名」的冰武器，测 W02 的基础数值（ice_gun 已有签名，会盖掉基础值）
	_equip([ICE_STAFF, FROST_BLADE])
	_duel.enemy_status.clear()
	_duel.enemy_status["frost"] = 0
	var a2: Dictionary = _settle_cards([SYM_FROST, SYM_ICE, SYM_ICE],
		["ice", "ice", "ice"], ["ice_staff", "ice_staff", "frost_blade"])
	_duel.combat._apply_patterns(a2)
	_check(String(a2.get("pattern_equipment", "")) == "W02",
		"W02 被判定生效（%s）" % String(a2.get("pattern_equipment", "")))
	_check(int((a2.get("pattern_status", {}) as Dictionary).get("frost", 0)) == 2,
		"W02 霜冻 +2（%d）" % int((a2.get("pattern_status", {}) as Dictionary).get("frost", 0)))
	_check(is_equal_approx(float(_duel._pattern_enemy_atk_mult), 1.0),
		"W02 未达 4 层时不削弱敌方攻击")
	# 已有 2 层 + 本次 2 层 = 4 → 触发削弱
	_duel.enemy_status["frost"] = 2
	_duel._pattern_enemy_atk_mult = 1.0
	var a2b: Dictionary = _settle_cards([SYM_FROST, SYM_ICE, SYM_ICE],
		["ice", "ice", "ice"], ["ice_staff", "ice_staff", "frost_blade"])
	_duel.combat._apply_patterns(a2b)
	_check(is_equal_approx(float(_duel._pattern_enemy_atk_mult), 0.8),
		"W02 达到 4 层时敌方攻击 ×0.8（%.2f）" % float(_duel._pattern_enemy_atk_mult))

	# —— W05 暗影处刑：暗伤害按比例转穿透；HP 低于 35% 时比例提高 ——
	_equip([NIGHT, ABYSS])
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	var a5: Dictionary = _settle_cards(["res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres"],
		["dark", "dark", "dark"], ["night_scythe", "abyss_scythe", "night_scythe"])
	var dark_bucket: float = float((a5["dmg_bucket_by_elem"] as Dictionary).get("dark", 0.0))
	var dmg_before: float = float(a5["dmg"])
	_duel.combat._apply_patterns(a5)
	_check(String(a5.get("pattern_equipment", "")) == "W05",
		"W05 被判定生效（%s）" % String(a5.get("pattern_equipment", "")))
	_check(float(a5["pierce"]) > 0.0, "W05 把暗伤害转成穿透（%.1f）" % float(a5["pierce"]))
	# 夜幕镰刀在场 → SIG_W05_NIGHT：比例 30%
	_check(String(a5.get("pattern_signature", "")) == "SIG_W05_NIGHT",
		"夜幕镰刀签名生效（%s）" % String(a5.get("pattern_signature", "")))
	_check(absf((dmg_before - float(a5["dmg"])) - dark_bucket * 0.3) < 1.0,
		"W05 带签名常态转移 30%%（移出 %.1f，期望 %.1f）" % [dmg_before - float(a5["dmg"]), dark_bucket * 0.3])
	# HP 低于 35% → 35%
	_duel.enemy_hp = 100
	_duel.enemy_hp_max = 1000
	var a5b: Dictionary = _settle_cards(["res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres"],
		["dark", "dark", "dark"], ["night_scythe", "abyss_scythe", "night_scythe"])
	var bucket_b: float = float((a5b["dmg_bucket_by_elem"] as Dictionary).get("dark", 0.0))
	var dmg_b_before: float = float(a5b["dmg"])
	_duel.combat._apply_patterns(a5b)
	# 签名把处决线从 35% 提到 50%
	_check(absf((dmg_b_before - float(a5b["dmg"])) - bucket_b * 0.5) < 1.0,
		"W05 带签名处决线以下转移 50%%（移出 %.1f，期望 %.1f）" % [dmg_b_before - float(a5b["dmg"]), bucket_b * 0.5])
	# 换一对无签名的暗武器，验证基础 20% / 35%
	_equip(["res://resources/weapon_templates/abyss_scythe.tres",
		"res://resources/weapon_templates/gloom_saber.tres"])
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	var a5c: Dictionary = _settle_cards(["res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres", "res://resources/symbols/shadow_slash.tres"],
		["dark", "dark", "dark"], ["abyss_scythe", "gloom_saber", "abyss_scythe"])
	var bucket_c: float = float((a5c["dmg_bucket_by_elem"] as Dictionary).get("dark", 0.0))
	var dmg_c: float = float(a5c["dmg"])
	_duel.combat._apply_patterns(a5c)
	_check(String(a5c.get("pattern_signature", "")) == "", "无高阶暗武器时不触发签名")
	_check(absf((dmg_c - float(a5c["dmg"])) - bucket_c * 0.2) < 1.0, "W05 无签名时基础 20%")

	# —— W06 无锋磨砺：无元素伤害 +20% ——
	_equip([DAGGER, IRON])
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	var a6: Dictionary = _settle_cards([SYM_FIRE_SLASH, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["dagger", "iron_sword", "dagger"])
	var none_dmg: float = float((a6["dmg_by_elem"] as Dictionary).get("none", 0.0))
	var d6_before: float = float(a6["dmg"])
	_duel.combat._apply_patterns(a6)
	_check(String(a6.get("pattern_equipment", "")) == "W06",
		"W06 被判定生效（%s）" % String(a6.get("pattern_equipment", "")))
	_check(absf((float(a6["dmg"]) - d6_before) - none_dmg * 0.2) < 1.0,
		"W06 无元素伤害 +20%%（+%.1f，期望 %.1f）" % [float(a6["dmg"]) - d6_before, none_dmg * 0.2])
	_check(float(a6["dmg"]) > 0.0 and not (a6["status_stacks"] as Dictionary).has("gold"),
		"W06 不提供金币或其它资源")


# I：三轨隔离——技能牌不能填武器牌谱，T 恰好 1 技能 + 2 武器，每轨各最多一条。
func _test_tracks() -> void:
	var aegis = load(SKILL_AEGIS)
	var aegis_sym := String(aegis.symbol.resource_path)

	# ① 2 张武器牌 + 1 张技能牌 → W01 不能触发（「任意武器牌」不接受技能牌）
	_equip([FIRE_SWORD, FLAME_STAFF], [SKILL_AEGIS])
	var acc: Dictionary = _settle_cards([SYM_FIRE_SLASH, SYM_BURN, aegis_sym],
		["none", "fire", "none"], ["fire_sword", "fire_sword", ""])
	_duel.combat._apply_patterns(acc)
	_check(String(acc.get("pattern_equipment", "")) == "",
		"技能牌不能充当武器牌谱的组件（实际 %s）" % String(acc.get("pattern_equipment", "")))
	var kinds := []
	for c in MATCHER.cards_from_grid(_duel):
		kinds.append(String(c.get("source_kind", "")))
	_check(kinds.count("skill") == 1 and kinds.count("weapon") == 2,
		"来源类别判定正确（%s）" % str(kinds))

	# ② 1 技能 + 2 武器触发真实 T02（aegis 是 shield 技能）
	var acc2: Dictionary = _settle_cards([aegis_sym, SYM_FIRE_SLASH, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "fire_sword", "fire_sword"])
	var shield_before2: float = float(acc2["shield"])
	_duel.combat._apply_patterns(acc2)
	_check(String(acc2.get("pattern_skill", "")) == "T02",
		"1 技能 + 2 武器触发 T02（实际 %s）" % String(acc2.get("pattern_skill", "")))
	_check(float(acc2["shield"]) > shield_before2,
		"防御术式效果落地（护盾 %.0f → %.0f）" % [shield_before2, float(acc2["shield"])])

	# ③ 2 张技能牌不触发术式（基础设计只要求 1 个技能槽）
	var acc3: Dictionary = _settle_cards([aegis_sym, aegis_sym, SYM_FIRE_SLASH],
		["none", "none", "none"], ["", "", "fire_sword"])
	_duel.combat._apply_patterns(acc3)
	_check(String(acc3.get("pattern_skill", "")) == "",
		"两张技能牌不触发术式（实际 %s）" % String(acc3.get("pattern_skill", "")))

	# ④ 同一回合 W 与 T 可以各触发一条（不同轨互不挤占）
	var acc4: Dictionary = _settle_cards([SYM_FIRE_SLASH, SYM_BURN, aegis_sym],
		["none", "fire", "none"], ["fire_sword", "fire_sword", ""])
	_equip([FIRE_SWORD, FLAME_STAFF], [SKILL_AEGIS])
	_duel.combat._apply_patterns(acc4)
	# 这里只有 2 张武器牌，W01 不触发；但 T 需要 shield 技能，aegis 是 shield → 可触发
	_check(String(acc4.get("pattern_skill", "")) == "T02",
		"W 不成立时技能轨仍独立触发（实际 %s）" % String(acc4.get("pattern_skill", "")))


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
