extends Node

# ============================================================================
# T3 阶段 2 · 牌谱去状态依赖契约（2026-11-27）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3_no_status_pattern_contract_test.tscn
#
# 阶段 2 裁决：状态符号（燃烧/霜冻/中毒/圣灼/暗蚀）不再由技能与武器进入轮池，
# 牌谱条件不得再依赖状态符号或状态牌。本批先处理火系三条（W01 / 火焰剑签名 / 火焰法杖签名）。
#
# 判定「依赖状态」：match_rule 序列化后出现
#   - "kind":"status"（状态牌条件）
#   - symbols/(burn|frost|poison|holy_burn|shadow_blight).tres（状态符号条件）
#
# 白名单是硬编码的人工期望，不得用实际结果反推：每批迁移完成后必须显式删除对应 id，
# 否则测试保持红。多一条、少一条都算不符。
# ============================================================================

const PATTERN_DIR := "res://resources/patterns"

# 当前仍依赖状态的牌谱 id（阶段 2 待清零）。清零 = 阶段 2「牌谱去状态」完成。
# 第 1 批（火系三条）已迁出：W01 / SIG_W01_FIRESWORD / SIG_W01_FLAMESTAFF。
const PENDING_STATUS_PATTERNS := [
	"W02",
	"SIG_W02_GLACIER",
	"SIG_W02_ZERO",
	"SIG_W02_ICEGUN",
]
# 已归档牌谱：老档继承装备时仍可触发，不设清零目标（保留其状态条件）。
const LEGACY_STATUS_PATTERNS := [
	"SIG_W01_EMBER",
]

const STATUS_SYMBOLS := ["burn", "frost", "poison", "holy_burn", "shadow_blight"]

var _checks := 0
var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	_run()
	print("T3NOSTATUS|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var patterns := _load_patterns()
	_check(patterns.size() > 0, "扫描到牌谱资源（%d）" % patterns.size())

	var actual: Array[String] = []
	for p in patterns:
		if _depends_on_status(p):
			actual.append(String(p.id))
	actual.sort()

	var want: Array[String] = []
	for id in PENDING_STATUS_PATTERNS:
		want.append(String(id))
	for id in LEGACY_STATUS_PATTERNS:
		want.append(String(id))
	want.sort()

	var missing: Array[String] = []
	for id in actual:
		if not want.has(id):
			missing.append(id)
	var stale: Array[String] = []
	for id in want:
		if not actual.has(id):
			stale.append(id)
	_check(actual == want,
		"依赖状态的牌谱集合 == 白名单（多出 %s / 缺 %s / 实测 %s）" % [
			str(missing), str(stale), str(actual)])


func _load_patterns() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PATTERN_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var p = load(PATTERN_DIR + "/" + f)
		if p != null:
			out.append(p)
	return out


func _depends_on_status(p) -> bool:
	var s := JSON.stringify(p.match_rule)
	if s.contains('"kind":"status"'):
		return true
	for name in STATUS_SYMBOLS:
		if s.contains("symbols/%s.tres" % name):
			return true
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)
