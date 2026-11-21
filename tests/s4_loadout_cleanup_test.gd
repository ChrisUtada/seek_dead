extends Node

# S4-2/3 回整备字段级清理测试（2026-11-21）
# 验证：回整备清整备页可见残留（扩槽/预览/临时字段）、局外收藏不变、
# 再配装不产生双重发奖或双重日志、新局状态合规。

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S4 CLEANUP FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	# 局外收藏基线（测试前记录）
	var owned_before: Array = (duel.meta.get("owned_weapons", []) as Array).duplicate()
	var forge_before: Variant = duel.meta.get("forge_styles", null)

	# 注入上局残留状态（模拟打完一局后回整备）
	duel.loadout_max = 99
	duel.skill_max = 99
	duel.charm_max = 99
	duel._reward_system.run_symbol_bonus["res://resources/symbols/frost.tres"] = 6
	duel.deprived_level = 2
	duel.room_element_mult["fire"] = 2.0
	duel.pending_chaos = true
	duel.pending_armor_break = true
	duel.boss_trash = 3
	duel.mastery.mastery["res://resources/weapon_templates/dagger.tres"] = 50

	# 记录 act_boon / journal 基线
	var boons_before: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons_before = (duel._journal._data["act_boons"] as Array).size()

	# 回整备（房间未激活时 _active 可能为 false，return_to_loadout 仍需清字段）
	duel.room_flow.return_to_loadout()
	await get_tree().process_frame

	# ① 整备页可见残留已清
	_ok(duel.loadout_max == int(duel.SLOT_INIT["weapon"]), "loadout_max back to baseline")
	_ok(duel.skill_max == int(duel.SLOT_INIT["skill"]), "skill_max back to baseline")
	_ok(duel.charm_max == int(duel.SLOT_INIT["passive"]), "charm_max back to baseline")
	_ok(duel._reward_system.run_symbol_bonus.is_empty(), "run_symbol_bonus cleared")
	_ok(duel.deprived_level == 0, "deprived_level cleared")
	_ok(duel.room_element_mult.is_empty(), "room_element_mult cleared")
	_ok(not duel.pending_chaos, "pending_chaos cleared")
	_ok(not duel.pending_armor_break, "pending_armor_break cleared")
	_ok(duel.boss_trash == 0, "boss_trash cleared")
	_ok(duel.mastery.mastery.is_empty(), "mastery cleared on return")

	# ② 局外收藏不变
	var owned_after: Array = (duel.meta.get("owned_weapons", []) as Array)
	_ok(_same_arr(owned_before, owned_after), "meta owned_weapons unchanged")
	_ok(str(duel.meta.get("forge_styles", null)) == str(forge_before), "meta forge_styles unchanged")

	# ③ 再配装不产生双重发奖/双重日志
	var boons_after_return: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons_after_return = (duel._journal._data["act_boons"] as Array).size()
	_ok(boons_after_return == boons_before, "return_to_loadout: no duplicate act_boon log")
	duel._confirm_loadout()
	await get_tree().process_frame
	var boons_after_refit: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons_after_refit = (duel._journal._data["act_boons"] as Array).size()
	_ok(boons_after_refit == boons_before, "refit/full_reset: no duplicate act_boon log")
	_ok(int(duel._reward_system.run_power_bonus) == 0, "refit: run_power_bonus reset (no double grant)")
	_ok(duel.player_hp_max == int(duel.BALANCE.player_hp_base), "refit: hp_max back to base")
	_ok(duel._reward_system.run_symbol_bonus.is_empty(), "refit: run_symbol_bonus empty")
	_ok(duel.circuit_system.inventory.is_empty(), "refit: circuit inventory empty")
	_ok(duel.run_weapon_inventory.size() > 0, "refit: starter weapon in run inventory")

	print("S4 CLEANUP RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _same_arr(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if str(a[i]) != str(b[i]): return false
	return true
