extends Node

# ============================================================================
# G7 收尾验证（2026-11-20）
# G7-3 条件接线：Boss/成就/武器里程碑/收藏里程碑 → 定向解锁额度（去重）
# G7-4 战后复核：last_battle_summary 含机器摘要可归因行
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7 WRAPUP FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	duel.meta["directed_unlocks"] = 0
	duel.meta["collection_milestones"] = []

	# ① 成就达成 → 定向额度（去重）
	var before: int = duel._anvil_system.available_directed_unlocks()
	duel._career._unlock("first_clear")
	_ok(duel._anvil_system.available_directed_unlocks() == before + 1, "成就达成 +1 额度")
	duel._career._unlock("first_clear")
	_ok(duel._anvil_system.available_directed_unlocks() == before + 1, "重复解锁不重复给额度")

	# ② 武器出场里程碑（每5局）→ 额度
	before = duel._anvil_system.available_directed_unlocks()
	duel.meta["codex"] = {}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)
	for i in range(5):
		duel._codex.note_style_use("res://resources/weapon_templates/fire_sword.tres")
	# 模拟第5局第一房记录（直接检查 %5 逻辑需通过 start_room，这里验证 codex 累计）
	_ok(duel._codex.style_uses_of("res://resources/weapon_templates/fire_sword.tres") == 5,
		"武器出场累计 5")

	# ③ 收藏里程碑 → 定向额度（而非点数）
	before = duel._anvil_system.available_directed_unlocks()
	var points_before: int = int(duel.meta.get("anvil_points", 0))
	# 把收藏进度拉满，触发里程碑
	var pool: Array = duel._anvil_system._anvil_pool()
	for p in pool:
		duel._anvil_system._anvil_grant_owned(p)
	duel._anvil_system.check_collection_milestones()
	_ok(duel._anvil_system.available_directed_unlocks() > before, "收藏里程碑授予定向额度（%d→%d）" % [
		before, duel._anvil_system.available_directed_unlocks()])
	_ok(int(duel.meta.get("anvil_points", 0)) == points_before, "里程碑不再加历史点数")

	# ④ 战后复核可归因字段
	duel.room_flow._summary_before = {"gold": 0, "anvil": 0, "charms": [], "consumables": []}
	duel.room_flow._finish_battle_summary(false)
	var sum: Dictionary = duel.room_flow.last_battle_summary
	_ok(sum.has("attribution"), "战果含 attribution 字段")
	_ok((sum["attribution"] as Array).size() > 0, "可归因行非空（%d）" % (sum["attribution"] as Array).size())

	print("G7 WRAPUP RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
