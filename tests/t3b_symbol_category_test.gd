extends Node

# ============================================================================
# T3-3B A7：symbol_category 字段与 match_rule 条件验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3b_symbol_category_test.tscn
# 四类取值 + 条件正反例 + 旧条件行为不变；不启动完整战斗。
# 附加守护：空/未知类别不回退成「任意」、null 符号不命中、全部 PatternData 仍可 solve。
# 本套件不实现任何组合、不改牌谱、不碰 RNG；只读资源与纯函数判定。
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行。
# ============================================================================

const DIR := "res://resources/symbols/"
const TRIM := "res://resources/consumables/trim_scissors.tres"
const PatternMatcher = preload("res://scripts/battle/pattern_matcher.gd")

# 旧条件合成样本：按 kind 取一张能满足该条件的牌
const KIND_SAMPLES := {
	"damage": "iron_slash",
	"status": "burn",
	"shield": "guard",
	"heal": "heal",
	"special": "flame_special",
	"buff": "buff_rage",
}
# 类别合成样本：同类别多条件时按序轮换取牌，避免复用同一张卡
const CATEGORY_SAMPLES := {
	"blade": ["iron_slash"],
	"flame": ["burn", "fire_slash", "flame_special"],
	"frost": ["frost", "ice_crystal"],
	"guard": ["guard", "aegis", "iron_wall"],
	"projectile": ["pistol_shot", "bolt_shot", "arrow_shot"],
	"none": ["miss", "trash", "heal"],
}

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
	# null 符号不得当作任意牌命中
	_check(PatternMatcher.solve_rule([{"sym": null, "valid": true}], rule_flame) == false,
		"null 符号不命中任何类别")

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
	# 多条件组合语义不变（同一张牌承担两个条件）
	_check(PatternMatcher.solve_rule([_card("burn"), _card("fire_slash")],
		{"all": [{"sym": DIR + "burn.tres"}, {"element": "fire"}]}), "旧条件 sym+element 组合仍成立")

	# ⑤ 全部 PatternData 的 match_rule 仍能 solve（W07 加入后共 22 条）
	_test_pattern_compat()


# 逐条条件按既有键合成一张能满足它的卡，再交给 solve_rule；
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
	_check(files.size() >= 21, "PatternData 资源数 >= 21（实测 %d）" % files.size())
	var solved := 0
	for f in files:
		var p := load("res://resources/patterns/%s" % f) as PatternData
		if p == null:
			continue
		var conds: Array = p.match_rule.get("all", [])
		if conds.is_empty():
			continue
		var cards: Array = []
		var rotations: Dictionary = {}
		for cond in conds:
			cards.append(_card_from_cond(cond, rotations))
		if PatternMatcher.solve_rule(cards, p.match_rule):
			solved += 1
		else:
			print("  UNSOLVED  %s  rule=%s" % [f, str(p.match_rule)])
	_check(solved == files.size(), "全部 pattern 的 match_rule 仍能 solve（%d/%d）" % [solved, files.size()])


# 为一条既有条件合成一张能满足它的卡（只用于验证求解器语义未变）。
func _card_from_cond(cond: Dictionary, rotations: Dictionary) -> Dictionary:
	var sym_name := "iron_slash"
	if cond.has("sym"):
		var path := String(cond["sym"])
		var res := load(path) as SymbolData
		if res != null:
			sym_name = String(path).get_file().trim_suffix(".tres")
	elif cond.has("symbol_category"):
		var cat := String(cond["symbol_category"])
		var pool: Array = CATEGORY_SAMPLES.get(cat, ["iron_slash"])
		var idx := int(rotations.get(cat, 0))
		sym_name = String(pool[idx % pool.size()])
		rotations[cat] = idx + 1
	elif cond.has("kind"):
		sym_name = String(KIND_SAMPLES.get(String(cond["kind"]), "iron_slash"))
	var c := _card(sym_name)
	if cond.has("element"):
		c["element"] = String(cond["element"])
	if cond.has("source_kind"):
		c["source_kind"] = String(cond["source_kind"])
	if cond.has("source_element"):
		c["source_element"] = String(cond["source_element"])
	if cond.has("skill_role"):
		c["skill_role"] = String(cond["skill_role"])
	if cond.has("source"):
		c["source"] = String(cond["source"])
	return c
