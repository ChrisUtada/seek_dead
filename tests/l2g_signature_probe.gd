extends Node

# L2-G 签名接入定向探针（2026-11-18）
# 验证：① 未携带关键武器、未习得 → 签名不生效
#       ② 三选一习得卡写入 learned_signatures
#       ③ 习得后（即使没关键武器）签名生效
#       ④ 每局 learned_signatures 清零
# 运行：Godot --headless --path . res://tests/l2g_signature_probe.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SIG_CARD := "res://resources/rewards/defs/seed_sig_fire_sword.tres"
const SIG_ID := "SIG_W01_FIRESWORD"
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

	# ① 无 key 无习得 → 签名不生效
	_duel.learned_signatures.clear()
	var sig0 = ps.find_signature("W01", [], cards, _duel.learned_signatures)
	_check(sig0 == null, "未携带关键武器且未习得时签名不生效")

	# 校验 cards 本身能满足 match_rule（排除探针构造问题导致的假阴性）
	var sigdef = ps.get_pattern(SIG_ID)
	_check(sigdef != null, "签名资源可加载（%s）" % SIG_ID)
	if sigdef != null:
		var pm = load("res://scripts/battle/pattern_matcher.gd")
		_check(pm.solve_rule(cards, sigdef.match_rule), "探针 cards 满足签名 match_rule")

	# ② 走三选一习得卡
	var resolver = load("res://scripts/reward/reward_resolver.gd").new(_duel)
	var card: Resource = load(SIG_CARD)
	_check(card != null, "签名解锁卡可加载")
	if card != null:
		var result = resolver.resolve(card)
		_check(bool(result.ok), "三选一习得卡结算成功（%s）" % str(result.reason))
		_check(_duel.learned_signatures.has(SIG_ID), "习得后写入 learned_signatures")

	# ③ 习得后（仍无关键武器）签名生效
	var sig1 = ps.find_signature("W01", [], cards, _duel.learned_signatures)
	_check(sig1 != null and String(sig1.id) == SIG_ID, "习得后无需关键武器签名即生效")

	# ③b 扩卡：多张不同元素签名可同时习得（冰 SIG_W02_ZERO）
	var ice_card: Resource = load("res://resources/rewards/defs/seed_sig_absolute_zero.tres")
	_check(ice_card != null, "冰签名解锁卡可加载")
	if ice_card != null:
		var r2 = resolver.resolve(ice_card)
		_check(bool(r2.ok), "冰签名卡结算成功")
		_check(_duel.learned_signatures.has(SIG_ID) and _duel.learned_signatures.has("SIG_W02_ZERO"),
			"两张不同元素签名可同时习得（%d）" % _duel.learned_signatures.size())

	# ④ 每局清零后失效
	_duel._reset_run_state()
	_check(_duel.learned_signatures.is_empty(), "新局 learned_signatures 清零")
	var sig2 = ps.find_signature("W01", [], cards, _duel.learned_signatures)
	_check(sig2 == null, "清零后签名重新失效")

	_finish()


func _finish() -> void:
	print("L2GSIG|RESULT %s (pass=%d fail=%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 2)
