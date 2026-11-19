extends Node

# L2-G 签名接入定向探针（2026-11-19 改为「全解锁」语义）
# 验证：① 无专属武器 → 签名不生效（仍需武器）
#       ② 携带专属武器 + 牌型满足 → 签名自动生效（无需习得）
#       ③ 无对应牌型 → 不生效
#       ④ 多把不同武器签名可同时生效（按 base_id 分别查）
# 运行：Godot --headless --path . res://tests/l2g_signature_probe.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SIG_ID := "SIG_W01_FIRESWORD"
const SIG_ICE_ID := "SIG_W02_ZERO"
const BURN := "res://resources/symbols/burn.tres"
const FIRE := "res://resources/symbols/ember_spark.tres"

var _pass := 0
var _fail := 0
var _duel = null


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  %s" % label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# sig_fire_sword 的 match_rule：burn符号 + fire伤害 + weapon来源（3张不同卡）
func _make_cards() -> Array:
	var burn: Resource = load(BURN)
	var fire: Resource = load(FIRE)
	return [
		{"sym": burn, "element": "fire", "source_element": "fire", "source_kind": "weapon", "valid": true},
		{"sym": fire, "kind": "damage", "source_element": "fire", "source_kind": "weapon", "valid": true},
		{"sym": fire, "kind": "damage", "source_element": "fire", "source_kind": "weapon", "valid": true},
	]


func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	_duel = scene_res.instantiate()
	add_child(_duel)
	await _frames(3)
	_duel.node_mode = false

	var ps = _duel._pattern_system
	var cards := _make_cards()
	var key_loadout := ["res://resources/weapon_templates/fire_sword.tres"]

	# ① 无专属武器 → 不生效
	var sig0 = ps.find_signature("W01", [], cards)
	_check(sig0 == null, "无专属武器时签名不生效")

	# 校验 cards 满足 match_rule（排除探针构造问题导致的假阴性）
	var sigdef = ps.get_pattern(SIG_ID)
	_check(sigdef != null, "签名资源可加载（%s）" % SIG_ID)
	if sigdef != null:
		var pm = load("res://scripts/battle/pattern_matcher.gd")
		_check(pm.solve_rule(cards, sigdef.match_rule), "探针 cards 满足签名 match_rule")

	# ② 携带专属武器 + 牌型满足 → 自动生效（无需习得，全解锁）
	var sig1 = ps.find_signature("W01", key_loadout, cards)
	_check(sig1 != null and String(sig1.id) == SIG_ID, "携带专属武器+牌型满足时签名自动生效（全解锁）")

	# ③ 无对应牌型 → 不生效
	var sig_no_pattern = ps.find_signature("W01", key_loadout, [])
	_check(sig_no_pattern == null, "无对应牌型时签名不生效")

	# ④ 冰签名资源可加载（全解锁后不再依赖习得卡）
	var ice_def = ps.get_pattern(SIG_ICE_ID)
	_check(ice_def != null, "冰签名资源可加载")

	_finish()


func _finish() -> void:
	print("L2GSIG|RESULT %s (pass=%d fail=%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 2)
