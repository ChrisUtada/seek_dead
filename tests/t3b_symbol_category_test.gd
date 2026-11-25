extends Node

# ============================================================================
# T3-3 B 轮 Step 1 · symbol_category 字段与匹配条件验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3b_symbol_category_test.tscn
#
# 口径（docs/T3-3_统一组合_StepA_只读盘点_2026-11-24.md §D Q4）：
# ① 试点 11 个符号的 symbol_category 取值正确，其余符号默认 none；
# ② match_rule {"symbol_category":"flame"} 对 burn 命中、对 guard 不命中；
# ③ 未知/空值不命中任何类别（不回退成「任意」）；
# ④ 旧条件 sym/element/source_kind 行为不变（各挑一条正反例）；
# ⑤ 兼容性：21 个 PatternData 零改动，全部 match_rule 仍可 solve；
#    老 .tres 无 symbol_category 字段也能加载（缺省 none）。
# 本套件不实现任何组合、不改牌谱、不碰 RNG；只读资源与纯函数判定。
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行。
# ============================================================================

const MATCHER = preload("res://scripts/battle/pattern_matcher.gd")

const PILOT_EXPECT := {
	"burn": "flame",
	"fire_slash": "flame",
	"flame_special": "flame",
	"frost": "frost",
	"ice_crystal": "frost",
	"guard": "guard",
	"aegis": "guard",
	"iron_wall": "guard",
	"pistol_shot": "projectile",
	"bolt_shot": "projectile",
	"arrow_shot": "projectile",
}

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	_test_pilot_categories()
	_test_match_condition()
	_test_unknown_no_fallback()
	_test_legacy_conditions()
	_test_pattern_compat()
	print("T3B|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _sym(name: String) -> SymbolData:
	return load("res://resources/symbols/%s.tres" % name) as SymbolData


# 构造一张合法判定牌；element/source_kind 可覆盖，用于旧条件正反例。
func _card(sym_name: String, element: String = "none", source_kind: String = "weapon") -> Dictionary:
	return {
		"sym": _sym(sym_name),
		"element": element,
		"source": "res://resources/weapon_templates/iron_sword.tres",
		"source_kind": source_kind,
		"source_element": "none",
		"skill_role": "",
		"valid": true,
	}


func _solve(cards: Array, cond: Dictionary) -> bool:
	return MATCHER.solve_rule(cards, {"all": [cond]})


func _test_pilot_categories() -> void:
	for name in PILOT_EXPECT:
		var s := _sym(name)
		_check(s != null and String(s.symbol_category) == String(PILOT_EXPECT[name]),
			"试点符号 %s.symbol_category == %s" % [name, PILOT_EXPECT[name]])
	# 未打标符号：老 .tres 没有该字段，加载后必须保持默认 none
	for name in ["iron_slash", "miss", "trash", "heal"]:
		var s := _sym(name)
		_check(s != null and String(s.symbol_category) == "none",
			"未打标符号 %s 缺省 none" % name)


func _test_match_condition() -> void:
	var cond := {"symbol_category": "flame"}
	_check(_solve([_card("burn")], cond), "symbol_category=flame 命中 burn")
	_check(not _solve([_card("guard")], cond), "symbol_category=flame 不命中 guard")
	_check(_solve([_card("fire_slash")], cond), "symbol_category=flame 命中 fire_slash")
	_check(_solve([_card("flame_special")], cond), "symbol_category=flame 命中 flame_special")
	var frost_cond := {"symbol_category": "frost"}
	_check(_solve([_card("frost")], frost_cond), "symbol_category=frost 命中 frost")
	_check(_solve([_card("ice_crystal")], frost_cond), "symbol_category=frost 命中 ice_crystal")
	var guard_cond := {"symbol_category": "guard"}
	_check(_solve([_card("aegis")], guard_cond) and _solve([_card("iron_wall")], guard_cond),
		"symbol_category=guard 命中 aegis / iron_wall")
	var proj_cond := {"symbol_category": "projectile"}
	_check(_solve([_card("pistol_shot")], proj_cond) and _solve([_card("bolt_shot")], proj_cond) \
			and _solve([_card("arrow_shot")], proj_cond),
		"symbol_category=projectile 命中 pistol_shot / bolt_shot / arrow_shot")


func _test_unknown_no_fallback() -> void:
	# 类别写错、空字符串、缺省 none，均不得命中任何类别条件（不回退成「任意」）。
	var s := _sym("burn")
	s.symbol_category = ""
	_check(not _solve([_card("burn")], {"symbol_category": "flame"}), "空类别不命中 flame")
	_check(not _solve([_card("burn")], {"symbol_category": "guard"}), "空类别不命中 guard")
	s.symbol_category = "unknown_cat"
	_check(not _solve([_card("burn")], {"symbol_category": "flame"}), "未知类别不命中 flame")
	s.symbol_category = "none"
	_check(not _solve([_card("burn")], {"symbol_category": "flame"}), "none 不命中 flame")
	_check(not _solve([_card("iron_slash")], {"symbol_category": "blade"}), "未打标符号不命中 blade")
	# 符号为 null 时同样不命中（不能当作任意牌）
	_check(not _solve([{"sym": null, "valid": true}], {"symbol_category": "flame"}), "null 符号不命中任何类别")
	s.symbol_category = "flame"   # 还原内存态，避免影响后续用例


func _test_legacy_conditions() -> void:
	var burn_path := "res://resources/symbols/burn.tres"
	_check(_solve([_card("burn")], {"sym": burn_path}), "旧条件 sym 正例：burn.tres 命中")
	_check(not _solve([_card("guard")], {"sym": burn_path}), "旧条件 sym 反例：guard.tres 不命中 burn.tres")
	_check(_solve([_card("burn", "fire")], {"element": "fire"}), "旧条件 element 正例：有效元素 fire 命中")
	_check(not _solve([_card("burn", "none")], {"element": "fire"}), "旧条件 element 反例：none 不命中 fire")
	_check(_solve([_card("burn", "none", "weapon")], {"source_kind": "weapon"}), "旧条件 source_kind 正例：weapon 命中")
	_check(not _solve([_card("burn", "none", "skill")], {"source_kind": "weapon"}), "旧条件 source_kind 反例：skill 不命中 weapon")
	# 多条件组合语义不变（同一张牌承担两个条件）
	_check(MATCHER.solve_rule([_card("burn", "fire"), _card("fire_slash", "fire")],
		{"all": [{"sym": burn_path}, {"element": "fire"}]}), "旧条件 sym+element 组合仍成立")


# 21 个 PatternData 资源零改动：全部 match_rule 仍可 solve。
# 做法：逐条条件按其键合成一张卡（同键多条件各占一张牌），再交给 solve_rule；
# 只使用既有条件类型，验证求解器语义未被 symbol_category 条件影响。
func _test_pattern_compat() -> void:
	var dir := DirAccess.open("res://resources/patterns")
	_check(dir != null, "资源目录 res://resources/patterns 可读")
	if dir == null:
		return
	var files: Array[String] = []
	for f in dir.get_files():
		if String(f).ends_with(".tres"):
			files.append(String(f))
	_check(files.size() == 21, "PatternData 资源数 == 21（实测 %d）" % files.size())
	var solved := 0
	for f in files:
		var p := load("res://resources/patterns/%s" % f) as PatternData
		if p == null:
			continue
		var conds: Array = p.match_rule.get("all", [])
		if conds.is_empty():
			continue
		var cards: Array = []
		for cond in conds:
			cards.append(_card_from_cond(cond))
		if MATCHER.solve_rule(cards, p.match_rule):
			solved += 1
		else:
			print("  UNSOLVED  %s  rule=%s" % [f, str(p.match_rule)])
	_check(solved == files.size(), "全部 pattern 的 match_rule 仍能 solve（%d/%d）" % [solved, files.size()])


# 为一条既有条件合成一张能满足它的卡（只用于验证求解器语义未变）。
# 优先用 sym 指定资源；否则按 kind + source_element 从候选表里挑一张。
const KIND_SAMPLES := {
	"damage": "iron_slash",
	"status": "burn",
	"shield": "guard",
	"heal": "heal",
	"special": "flame_special",
	"buff": "buff_rage",
}

func _card_from_cond(cond: Dictionary) -> Dictionary:
	var sym_name := "iron_slash"
	if cond.has("sym"):
		var path := String(cond["sym"])
		var res := load(path) as SymbolData
		if res != null:
			sym_name = String(path).get_file().trim_suffix(".tres")
	elif cond.has("kind"):
		sym_name = String(KIND_SAMPLES.get(String(cond["kind"]), "iron_slash"))
	var element := "none"
	if cond.has("element"):
		element = String(cond["element"])
	var source_kind := "weapon"
	if cond.has("source_kind"):
		source_kind = String(cond["source_kind"])
	var c := _card(sym_name, element, source_kind)
	c["source_element"] = String(cond.get("source_element", "none"))
	c["skill_role"] = String(cond.get("skill_role", ""))
	c["source"] = String(cond.get("source", "res://resources/weapon_templates/iron_sword.tres"))
	return c
