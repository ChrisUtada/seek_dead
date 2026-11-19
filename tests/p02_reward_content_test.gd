extends Node

# ============================================================================
# P0.2 最小奖励池内容测试（headless，2026-11-19）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/p02_reward_content_test.tscn
#
# 覆盖：
# ① 符号权重卡动态构造：目标 path 为真实 resource_path、category=symbol_mod
# ② Resolver 执行符号权重：run_symbol_bonus 增加、返回成功
# ③ 单符号灌注上限（SYMBOL_WEIGHT_MAX）
# ④ 金币卡执行：gold 增加
# ⑤ 新卡仍通过 Registry 校验（20 张）
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P0.2 FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _run() -> void:
	var problems := RewardRegistry.validate_all()
	_ok(problems.is_empty(), "all reward defs valid: %s" % str(problems))
	_ok(RewardRegistry.count() >= 12, "at least 12 seed defs (got %d)" % RewardRegistry.count())

	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return

	await _test_symbol_weight(duel)
	_test_gold(duel)

	print("P02CONTENT RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_symbol_weight(duel: DuelController) -> void:
	var defs: Array = duel._reward_system._make_symbol_weight_defs()
	_ok(not defs.is_empty(), "symbol weight defs generated from pool")
	if defs.is_empty():
		return
	var def: RewardDefinition = defs[0]
	_ok(def.category == "symbol_mod", "symbol def category=symbol_mod")
	_ok(def.effect_family == "symbol_weight", "symbol def effect_family=symbol_weight")
	var params: Dictionary = def.effects[0].get("params", {})
	var path := String(params.get("path", ""))
	_ok(path.begins_with("res://resources/symbols/") and path.ends_with(".tres"),
		"symbol path is real resource_path: %s" % path)
	_ok(int(params.get("weight", 0)) > 0, "symbol weight delta positive")

	var before := int(duel._reward_system.run_symbol_bonus.get(path, 0))
	var sym_dbg: SymbolData = load(path)
	var resolver: RewardResolver = duel._reward_system._draft_resolver
	var res = resolver.resolve(def)
	_ok(res.ok, "symbol weight resolve ok: %s" % res.reason)
	var after := int(duel._reward_system.run_symbol_bonus.get(path, 0))
	_ok(after > before, "run_symbol_bonus increased %d -> %d" % [before, after])

	# 灌注到上限后不再生成该符号的奖励
	for i in range(10):
		duel._reward_system.run_symbol_bonus[path] = duel._reward_system.SYMBOL_WEIGHT_MAX
	var defs2: Array = duel._reward_system._make_symbol_weight_defs()
	var has_path := false
	for d in defs2:
		if String(d.effects[0].get("params", {}).get("path", "")) == path:
			has_path = true
	_ok(not has_path, "symbol at max weight not offered again")


func _test_gold(duel: DuelController) -> void:
	var gold_before := int(duel.gold)
	var def := RewardDefinition.new()
	def.id = "test_gold"
	def.name = "测试金币"
	def.rarity = "common"
	def.effects = [{"effect_id": "gold_add", "params": {"amount": 7}}]
	var res = duel._reward_system._draft_resolver.resolve(def)
	_ok(res.ok, "gold_add resolve ok: %s" % res.reason)
	_ok(duel.gold == gold_before + 7, "gold increased %d -> %d" % [gold_before, duel.gold])
