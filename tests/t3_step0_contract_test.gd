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
# ============================================================================

const MACE := "res://resources/weapon_templates/mace.tres"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
const IRON_WALL_SKILL := "res://resources/skills/iron_wall.tres"
const HOLY_VERDICT_SKILL := "res://resources/skills/holy_verdict.tres"
const GUARD_SKILL := "res://resources/skills/guard.tres"
const SY_IRON_WALL := "res://resources/symbols/iron_wall.tres"
const SY_IRON_SLASH := "res://resources/symbols/iron_slash.tres"
const SY_HOLY_VERDICT := "res://resources/symbols/holy_verdict.tres"
const SY_GUARD := "res://resources/symbols/guard.tres"

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
