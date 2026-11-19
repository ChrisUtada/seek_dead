extends Node

# ============================================================================
# P1.1② 符号效果强化测试（headless，2026-11-19）
# 覆盖：
# ① Resolver 写入 symbol_effect_overrides
# ② build_pool 重建后覆盖重新应用到聚合 map（status/crit/power）
# ③ 非法参数/无效符号路径拒绝
# ④ 新局清零
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("P1.1② FAIL: " + label)


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
	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	var rs = duel._reward_system
	var path: String = duel.GOLD_SYMBOL.resource_path

	# ① Resolver 写入覆盖
	var def := RewardDefinition.new()
	def.id = "test_sym_effect"
	def.name = "测试符号强化"
	def.rarity = "common"
	def.effects = [{"effect_id": "symbol_effect_bonus", "params": {
		"symbol_path": path, "effect": "power", "delta": 3.0}}]
	var res = rs._draft_resolver.resolve(def)
	_ok(res.ok, "symbol_effect_bonus resolve ok: %s" % res.reason)
	_ok(duel.symbol_effect_overrides.has(path), "override written")
	_ok(float(duel.symbol_effect_overrides[path].get("power", 0.0)) == 3.0, "power delta=3")

	# ② build_pool 重建后覆盖重新应用
	var before: float = float(duel._weapon_power_map.get(path, 0.0))
	duel.reel_system.build_pool(duel.selected_loadout)
	var after: float = float(duel._weapon_power_map.get(path, 0.0))
	_ok(after >= before + 3.0, "build_pool reapplied power delta (%.1f -> %.1f)" % [before, after])

	# ③ 非法参数/无效路径拒绝
	var bad := RewardDefinition.new()
	bad.id = "test_bad"
	bad.name = "测试非法"
	bad.rarity = "common"
	bad.effects = [{"effect_id": "symbol_effect_bonus", "params": {
		"symbol_path": path, "effect": "unknown_effect", "delta": 1.0}}]
	_ok(not rs._draft_resolver.resolve(bad).ok, "unknown effect rejected")
	var bad2 := RewardDefinition.new()
	bad2.id = "test_bad2"
	bad2.name = "测试无效路径"
	bad2.rarity = "common"
	bad2.effects = [{"effect_id": "symbol_effect_bonus", "params": {
		"symbol_path": "res://nonexistent.tres", "effect": "power", "delta": 1.0}}]
	_ok(not rs._draft_resolver.resolve(bad2).ok, "unknown symbol path rejected")

	# ④ 新局清零
	duel._reset_run_state()
	_ok(duel.symbol_effect_overrides.is_empty(), "overrides cleared on new run")

	print("P11SYMEFF RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
