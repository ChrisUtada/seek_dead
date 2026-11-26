extends Node

# ============================================================================
# T3 Step 0 契约测试（2026-11-26）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3_step0_contract_test.tscn
# 覆盖（T3-0A Q1 / Q5）：
#   0A-1 铁誓共享符号：mace 产出的铁誓牌判 weapon；技能位铁誓牌判 skill
#   0A-2 T04：仅 mace 的铁誓牌不能充当技能牌；技能铁誓 + 两把武器成立
#   0A-3 W09：mace + 铁剑下「任意武器牌」条件成立
#   0A-4 圣裁共享符号：武器牌与技能牌不可互相顶替
#   0A-5 普通非共享符号判定不变
#   0B 牌卡来源路径（T3-0A Q1）：武器牌 source_path = WeaponData.resource_path，
#       技能 / 金币 / MISS / 废铁 / 精华一律空串；实盘与预览同源；同武器两格同路径。
#   0C 基础攻击契约（T3-0A Q2）：熟练不入 weapon_power；槽位锻造 / 铸式按公式进入；
#       不读取遗留字段 WeaponData.damage。
# ============================================================================

const MACE := "res://resources/weapon_templates/mace.tres"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
const IRON_WALL_SKILL := "res://resources/skills/iron_wall.tres"
const HOLY_VERDICT_SKILL := "res://resources/skills/holy_verdict.tres"
const GUARD_SKILL := "res://resources/skills/guard.tres"
const SY_IRON_WALL := "res://resources/symbols/iron_wall.tres"
const SY_IRON_SLASH := "res://resources/symbols/iron_slash.tres"
const SY_HOLY_VERDICT := "res://resources/symbols/holy_verdict.tres"
const SY_GUARD := "res://resources/symbols/guard.tres"
const SY_GOLD := "res://resources/symbols/gold.tres"
const SY_MISS := "res://resources/symbols/miss.tres"
const SY_TRASH := "res://resources/symbols/trash.tres"
const SY_ESSENCE_FIRE := "res://resources/symbols/essence_fire.tres"

const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")

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

	_test_0a_iron_wall()
	_test_0a_t04()
	_test_0a_w09()
	_test_0a_holy_verdict()
	_test_0a_normal()
	_test_0b_source_path()
	_test_0c_weapon_power()

	print("T3STEP0|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 只重建来源元数据（card_meta 的唯一输入），不建池、不起转。
func _setup(weapons: Array, skills: Array) -> void:
	_duel.selected_loadout.clear()
	for w in weapons:
		_duel.selected_loadout.append(String(w))
	_duel.selected_skills.clear()
	for s in skills:
		_duel.selected_skills.append(String(s))
	_duel._sync_pattern_source_meta()


# 建池（预览候选需要 pool_items）+ 来源元数据。
func _setup_pool(weapons: Array, skills: Array) -> void:
	_setup(weapons, skills)
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()


func _meta(sym_path: String, elem: String, src: String) -> Dictionary:
	return MATCHER.card_meta(_duel, load(sym_path), elem, src)


func _desc(card: Dictionary) -> String:
	return "source=%s kind=%s elem=%s role=%s" % [
		String(card.get("source", "")), String(card.get("source_kind", "")),
		String(card.get("source_element", "")), String(card.get("skill_role", ""))]


# 0A-1：铁誓同符号来自 mace（武器）与技能位（技能），来源判定必须分开。
func _test_0a_iron_wall() -> void:
	_setup([MACE], [IRON_WALL_SKILL])
	var w := _meta(SY_IRON_WALL, "none", "mace")
	_check(String(w.get("source", "")) == "mace" and String(w.get("source_kind", "")) == "weapon",
		"0A-1 铁誓：mace 产出的牌判 weapon（%s）" % _desc(w))
	var s := _meta(SY_IRON_WALL, "none", "")
	_check(String(s.get("source", "")) == "" and String(s.get("source_kind", "")) == "skill" \
			and String(s.get("skill_role", "")) == "shield",
		"0A-1 铁誓：技能位牌判 skill/shield（%s）" % _desc(s))


# 0A-2：T04 = 铁誓技能牌 + 任意武器攻击牌 + 任意武器牌（此处按设计行本地构造规则）。
func _test_0a_t04() -> void:
	_setup([MACE], [IRON_WALL_SKILL])
	var rule := {"all": [
		{"sym": SY_IRON_WALL, "source_kind": "skill"},
		{"kind": "damage", "source_kind": "weapon"},
		{"source_kind": "weapon"},
	]}
	var mace_cards := [
		_meta(SY_IRON_WALL, "none", "mace"),
		_meta(SY_IRON_SLASH, "none", "mace"),
		_meta(SY_IRON_SLASH, "none", "mace"),
	]
	_check(not MATCHER.solve_rule(mace_cards, rule),
		"0A-2 T04：仅 mace 的铁誓牌不充当技能牌（不得命中）")

	_setup([MACE, IRON_SWORD], [IRON_WALL_SKILL])
	var cards := [
		_meta(SY_IRON_WALL, "none", ""),
		_meta(SY_IRON_SLASH, "none", "mace"),
		_meta(SY_IRON_SLASH, "none", "iron_sword"),
	]
	_check(MATCHER.solve_rule(cards, rule),
		"0A-2 T04：技能铁誓 + 两把武器的攻击牌成立")


# 0A-3：W09 = mace 的铁斩 + 铁誓 + 任意武器牌。
func _test_0a_w09() -> void:
	_setup([MACE, IRON_SWORD], [])
	var rule := {"all": [
		{"sym": SY_IRON_SLASH},
		{"sym": SY_IRON_WALL},
		{"source_kind": "weapon"},
	]}
	var cards := [
		_meta(SY_IRON_SLASH, "none", "mace"),
		_meta(SY_IRON_WALL, "none", "mace"),
		_meta(SY_IRON_SLASH, "none", "iron_sword"),
	]
	_check(MATCHER.solve_rule(cards, rule),
		"0A-3 W09：mace+铁剑下「任意武器牌」条件成立")
	var w := _meta(SY_IRON_WALL, "none", "mace")
	_check(String(w.get("source_kind", "")) == "weapon",
		"0A-3 W09：mace 的铁誓牌计入武器牌（%s）" % _desc(w))


# 0A-4：圣裁同符号来自 holy_sword（武器）与技能位（技能），不可互相顶替。
func _test_0a_holy_verdict() -> void:
	_setup([HOLY_SWORD], [HOLY_VERDICT_SKILL])
	var hw := _meta(SY_HOLY_VERDICT, "light", "holy_sword")
	var hs := _meta(SY_HOLY_VERDICT, "light", "")
	_check(String(hw.get("source_kind", "")) == "weapon" \
			and String(hw.get("source_element", "")) == "light",
		"0A-4 圣裁：holy_sword 产出的牌判 weapon/light（%s）" % _desc(hw))
	_check(String(hs.get("source_kind", "")) == "skill" \
			and String(hs.get("source_element", "")) == "light",
		"0A-4 圣裁：技能位牌判 skill/light（%s）" % _desc(hs))
	var only_weapon := {"all": [{"sym": SY_HOLY_VERDICT, "source_kind": "weapon"}]}
	_check(MATCHER.solve_rule([hw], only_weapon), "0A-4 武器版圣裁满足武器条件")
	_check(not MATCHER.solve_rule([hs], only_weapon), "0A-4 技能版圣裁不能顶替武器条件")
	var only_skill := {"all": [{"sym": SY_HOLY_VERDICT, "source_kind": "skill"}]}
	_check(MATCHER.solve_rule([hs], only_skill), "0A-4 技能版圣裁满足技能条件")
	_check(not MATCHER.solve_rule([hw], only_skill), "0A-4 武器版圣裁不能顶替技能条件")


# 0A-5：普通非共享符号（铁斩 / 守备）判定不变。
func _test_0a_normal() -> void:
	_setup([IRON_SWORD], [GUARD_SKILL])
	var nw := _meta(SY_IRON_SLASH, "none", "iron_sword")
	var ns := _meta(SY_GUARD, "none", "")
	_check(String(nw.get("source_kind", "")) == "weapon" \
			and String(nw.get("source_element", "")) == "none",
		"0A-5 铁斩：武器牌判定不变（%s）" % _desc(nw))
	_check(String(ns.get("source_kind", "")) == "skill" \
			and String(ns.get("skill_role", "")) == "shield",
		"0A-5 守备：技能牌判定不变（%s）" % _desc(ns))


# 0B：牌卡来源路径（T3-0A Q1）。
func _test_0b_source_path() -> void:
	_setup_pool([IRON_SWORD], [GUARD_SKILL])
	_duel.frozen_cols.clear()
	# 三格：铁斩（铁剑）/ 守备（技能位）/ 铁斩（铁剑第二格）
	var syms := [SY_IRON_SLASH, SY_GUARD, SY_IRON_SLASH]
	var srcs := ["iron_sword", "", "iron_sword"]
	for c in 3:
		_duel.grid[c][0] = load(String(syms[c]))
		_duel.grid_elem[c][0] = "none"
		_duel.reel_system._set_grid_src(c, 0, String(srcs[c]))
	var cards: Array = MATCHER.cards_from_grid(_duel)
	_check(cards.size() == 3, "0B 实盘取 3 张牌（实测 %d）" % cards.size())
	if cards.size() != 3:
		return
	var c0: Dictionary = cards[0]
	var c1: Dictionary = cards[1]
	var c2: Dictionary = cards[2]
	_check(String(c0.get("source_path", "")) == IRON_SWORD \
			and load(String(c0.get("source_path", ""))) is WeaponData,
		"0B 武器牌 source_path = WeaponData.resource_path（%s）" % String(c0.get("source_path", "")))
	_check(String(c0.get("source_path", "")) == String(c2.get("source_path", "")),
		"0B 同一武器两格 → 同一 source_path（%s / %s）" % [
			String(c0.get("source_path", "")), String(c2.get("source_path", ""))])
	_check(String(c1.get("source_kind", "")) == "skill" \
			and String(c1.get("source_path", "")) == "",
		"0B 技能牌 source_path 为空串（%s）" % _spath(c1))

	var all_weapon_ok := true
	var all_skill_ok := true
	for card in cards:
		var d: Dictionary = card
		if String(d.get("source_kind", "")) == "weapon":
			var sp := String(d.get("source_path", ""))
			if sp == "" or not (load(sp) is WeaponData):
				all_weapon_ok = false
		elif String(d.get("source_kind", "")) == "skill":
			if String(d.get("source_path", "")) != "":
				all_skill_ok = false
	_check(all_weapon_ok, "0B 所有武器牌 source_path 非空且可载入 WeaponData")
	_check(all_skill_ok, "0B 所有技能牌 source_path 为空串")

	# 预览候选与实盘同源：同一符号的 source_kind / source_path 必须一致。
	var cands: Array[Dictionary] = _duel._preview_candidate_cards()
	var wcand := _find_cand(cands, SY_IRON_SLASH)
	var scand := _find_cand(cands, SY_GUARD)
	_check(not wcand.is_empty(), "0B 预览候选含铁斩")
	_check(not scand.is_empty(), "0B 预览候选含守备")
	if not wcand.is_empty():
		_check(String(wcand.get("source_kind", "")) == String(c0.get("source_kind", "")) \
				and String(wcand.get("source_path", "")) == String(c0.get("source_path", "")),
			"0B 实盘与预览武器牌一致（实盘 %s / 预览 %s）" % [
				_spath(c0), _spath(wcand)])
	if not scand.is_empty():
		_check(String(scand.get("source_kind", "")) == String(c1.get("source_kind", "")) \
				and String(scand.get("source_path", "")) == String(c1.get("source_path", "")),
			"0B 实盘与预览技能牌一致（实盘 %s / 预览 %s）" % [
				_spath(c1), _spath(scand)])

	# 非武器来源：金币 / MISS / 废铁 / 精华一律空串。
	for p in [SY_GOLD, SY_MISS, SY_TRASH, SY_ESSENCE_FIRE]:
		var m := _meta(String(p), "none", "")
		_check(String(m.get("source_path", "")) == "",
			"0B 非武器牌 source_path 为空串（%s → %s）" % [String(p).get_file(), _spath(m)])


func _find_cand(cands: Array[Dictionary], path: String) -> Dictionary:
	for c in cands:
		if String(c.get("path", "")) == path:
			return c
	return {}


func _spath(card: Dictionary) -> String:
	return "kind=%s path=%s" % [
		String(card.get("source_kind", "")), String(card.get("source_path", ""))]


# 0C：基础攻击契约（T3-0A Q2）。
# weapon_power = WeaponData.base_power + 槽位锻造 + 铸式攻击；不含熟练，不读 damage。
func _test_0c_weapon_power() -> void:
	_setup([IRON_SWORD], [])
	_duel.weapon_slots.reset_run()
	var slot := int(_duel.slot_of(IRON_SWORD))
	var p0: int = _duel.weapon_power(IRON_SWORD)
	_duel.mastery.mastery[IRON_SWORD] = 100
	var p1: int = _duel.weapon_power(IRON_SWORD)
	_check(p1 == p0, "0C-1 熟练 0→100 不改变 weapon_power（%d / %d）" % [p0, p1])
	_duel.mastery.mastery.erase(IRON_SWORD)

	_check(bool(_duel.weapon_slots.choose(slot, "forge")), "0C-2 槽位锻造第 1 次可选")
	var p2: int = _duel.weapon_power(IRON_SWORD)
	_check(p2 == p0 + 2, "0C-2 槽位锻造 +1 次 → 基础攻击 +2（%d → %d）" % [p0, p2])
	_check(bool(_duel.weapon_slots.choose(slot, "forge")), "0C-2 槽位锻造第 2 次可选")
	var p3: int = _duel.weapon_power(IRON_SWORD)
	_check(p3 == p0 + 4, "0C-2 槽位锻造 +2 次 → 基础攻击 +4（%d → %d）" % [p0, p3])
	_check(p3 == _formula(IRON_SWORD),
		"0C-2 weapon_power == base_power + 槽位锻造 + 铸式（实测 %d / 公式 %d）" % [
			p3, _formula(IRON_SWORD)])

	_duel.weapon_slots.reset_run()
	_setup([FIRE_SWORD], [])
	var base: int = int((load(FIRE_SWORD) as WeaponData).base_power)
	var before: int = _duel.weapon_power(FIRE_SWORD)
	_check(before == base, "0C-3 铸式前 weapon_power == base_power（%d / %d）" % [before, base])
	_unlock_codex(FIRE_SWORD)
	_check(bool(_duel._forge_styles.set_style(FIRE_SWORD, "lie_ren")), "0C-3 铸式「烈刃」可选")
	var style_power: int = int(_duel._forge_styles.style_def(FIRE_SWORD).get("power", 0))
	var after: int = _duel.weapon_power(FIRE_SWORD)
	_check(style_power == 2 and after == before + style_power,
		"0C-3 铸式攻击加成进入 weapon_power（%d → %d，铸式 +%d）" % [before, after, style_power])
	_check(after == _formula(FIRE_SWORD),
		"0C-3 weapon_power == base_power + 槽位锻造 + 铸式（实测 %d / 公式 %d）" % [
			after, _formula(FIRE_SWORD)])
	_duel._forge_styles.set_style(FIRE_SWORD, "")

	_duel.weapon_slots.reset_run()
	_setup([HOLY_SWORD], [])
	var wd: WeaponData = load(HOLY_SWORD)
	_check(int(wd.base_power) == 18 and is_equal_approx(float(wd.damage), 45.0),
		"0C-4 前提：圣辉长剑 base_power=%d / damage=%s" % [int(wd.base_power), str(wd.damage)])
	var p4: int = _duel.weapon_power(HOLY_SWORD)
	_check(p4 == 18, "0C-4 weapon_power 不读 WeaponData.damage（实测 %d，damage=45）" % p4)
	_check(p4 == _formula(HOLY_SWORD),
		"0C-4 weapon_power == base_power + 槽位锻造 + 铸式（实测 %d / 公式 %d）" % [
			p4, _formula(HOLY_SWORD)])
	_restore_meta()


func _formula(path: String) -> int:
	var wd: WeaponData = load(path)
	if wd == null:
		return 0
	var slot := int(_duel.slot_of(path))
	var forge: int = _duel.weapon_slots.forge_bonus(slot) if slot >= 0 else 0
	var style: int = _duel._forge_styles.power_bonus(path)
	return int(wd.base_power) + forge + style


# 铸式解锁按图鉴历史：只在本测试内存里注入 R2 记录，结束后整体还原 meta。
var _meta_backup: Dictionary = {}


func _unlock_codex(path: String) -> void:
	if _meta_backup.is_empty():
		_meta_backup = _duel.meta.duplicate(true)
	if not (_duel.meta.get("codex") is Dictionary):
		_duel.meta["codex"] = {}
	_duel.meta["codex"][path] = {"uses": 1, "best_rank": 2, "best_mastery": 3, "forge": 0, "tune": {}}
	_duel._codex = preload("res://scripts/systems/codex_system.gd").new(_duel)


func _restore_meta() -> void:
	if _meta_backup.is_empty():
		return
	_duel.meta.clear()
	for k in _meta_backup:
		_duel.meta[k] = _meta_backup[k]
	_duel._codex = preload("res://scripts/systems/codex_system.gd").new(_duel)
	_duel._meta_store.save_meta()
