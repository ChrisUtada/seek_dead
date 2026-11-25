extends Node

# ============================================================================
# T3-3B A7：symbol_category 字段与 match_rule 条件验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3b_symbol_category_test.tscn
# 四类取值 + 条件正反例 + 旧条件行为不变；不启动完整战斗。
# ============================================================================

const DIR := "res://resources/symbols/"
const TRIM := "res://resources/consumables/trim_scissors.tres"
const PatternMatcher = preload("res://scripts/battle/pattern_matcher.gd")

var _fails := 0
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("T3BCAT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _sym(path: String):
	return load(DIR + path + ".tres")


# 构造 card：solver 需要 sym/resource_path 与若干上下文字段
func _card(sym_path: String) -> Dictionary:
	var sym = load(DIR + sym_path + ".tres")
	return {
		"sym": sym,
		"element": String(sym.element),
		"kind": String(sym.kind),
		"source_kind": "weapon",
		"source_element": "fire" if sym_path == "fire_slash" else "none",
		"skill_role": "",
	}


func _run() -> void:
	# ① 四类取值（含 guard 三个、projectile 三个）
	var expect := {
		"iron_slash": "blade",
		"burn": "flame", "fire_slash": "flame", "flame_special": "flame",
		"frost": "frost", "ice_crystal": "frost",
		"guard": "guard", "aegis": "guard", "iron_wall": "guard",
		"pistol_shot": "projectile", "bolt_shot": "projectile", "arrow_shot": "projectile",
	}
	for k in expect:
		var sym = _sym(k)
		_check(sym != null and String(sym.symbol_category) == String(expect[k]),
			"类别 %s = %s（实测 %s）" % [k, expect[k], String(sym.symbol_category) if sym != null else "?"])
	# 未打标的符号保持 none
	var unmarked := ["heal", "mend", "gold", "miss", "trash"]
	for k in unmarked:
		var sym = _sym(k)
		_check(sym != null and String(sym.symbol_category) == "none", "未打标 %s = none" % k)

	# ② symbol_category 条件正反例（用 solve_rule 单牌 + 单条件）
	var rule_flame: Dictionary = {"all": [{"symbol_category": "flame"}]}
	var rule_guard: Dictionary = {"all": [{"symbol_category": "guard"}]}
	_check(PatternMatcher.solve_rule([_card("burn")], rule_flame), "category=flame 命中 burn")
	_check(PatternMatcher.solve_rule([_card("guard")], rule_flame) == false, "category=flame 不命中 guard")
	_check(PatternMatcher.solve_rule([_card("guard")], rule_guard), "category=guard 命中 guard")

	# ③ 未知值/空值不命中任何牌（不回退成任意）
	for bad in ["unknown", ""]:
		var bad_rule: Dictionary = {"all": [{"symbol_category": bad}]}
		var any_hit := false
		for k in expect:
			if PatternMatcher.solve_rule([_card(k)], bad_rule):
				any_hit = true
				break
		_check(not any_hit, "未知/空类别 %s 不命中任何牌" % ("(空)" if bad == "" else bad))

	# A6 零行为验证：W01 的 burn 条件加 symbol_category=flame（保留精确 sym）前后结果一致
	var old_w01: Dictionary = {"all": [{"sym": DIR + "burn.tres"}, {"kind": "damage", "source_element": "fire"}, {"source_kind": "weapon"}]}
	var new_w01: Dictionary = {"all": [{"sym": DIR + "burn.tres", "symbol_category": "flame"}, {"kind": "damage", "source_element": "fire"}, {"source_kind": "weapon"}]}
	var cards3: Array = [_card("burn"), _card("fire_slash"), _card("fire_slash")]
	_check(PatternMatcher.solve_rule(cards3, old_w01) == PatternMatcher.solve_rule(cards3, new_w01),
		"A6 W01 加 symbol_category 前后判定一致（恒真）")
	_check(PatternMatcher.solve_rule(cards3, new_w01), "A6 改后 W01 仍命中")

	# ④ 旧条件正反例：sym / element / source_kind / source_element / kind / skill_role
	_check(PatternMatcher.solve_rule([_card("burn")], {"all": [{"sym": DIR + "burn.tres"}]}), "旧 sym 正例命中 burn")
	_check(not PatternMatcher.solve_rule([_card("guard")], {"all": [{"sym": DIR + "burn.tres"}]}), "旧 sym 反例不命中 guard")
	_check(PatternMatcher.solve_rule([_card("burn")], {"all": [{"element": "fire"}]}), "旧 element 正例命中 burn")
	_check(not PatternMatcher.solve_rule([_card("guard")], {"all": [{"element": "fire"}]}), "旧 element 反例不命中 guard")
	_check(PatternMatcher.solve_rule([_card("burn")], {"all": [{"source_kind": "weapon"}]}), "旧 source_kind 正例")
	_check(not PatternMatcher.solve_rule([_card("burn")], {"all": [{"source_kind": "skill"}]}), "旧 source_kind 反例")
	_check(PatternMatcher.solve_rule([_card("fire_slash")], {"all": [{"source_element": "fire"}]}), "旧 source_element 正例")
	_check(not PatternMatcher.solve_rule([_card("burn")], {"all": [{"source_element": "fire"}]}), "旧 source_element 反例")
	_check(PatternMatcher.solve_rule([_card("burn")], {"all": [{"kind": "status"}]}), "旧 kind 正例")
	_check(not PatternMatcher.solve_rule([_card("burn")], {"all": [{"kind": "shield"}]}), "旧 kind 反例")
	# skill_role：构造 skill 来源 card
	var skill_card: Dictionary = _card("guard")
	skill_card["source_kind"] = "skill"
	skill_card["skill_role"] = "shield"
	_check(PatternMatcher.solve_rule([skill_card], {"all": [{"source_kind": "skill", "skill_role": "shield"}]}), "旧 skill_role 正例")
	_check(not PatternMatcher.solve_rule([_card("guard")], {"all": [{"source_kind": "skill", "skill_role": "shield"}]}), "旧 skill_role 反例")
