extends Node

# ============================================================================
# G2-1 本局武器仓库测试（headless）
# 运行：Godot --headless --path <项目> res://tests/g2_weapon_inventory_test.tscn
#
# 覆盖（权威 §5.1 / G2-1）：
# ① 三态分离：run_weapon_inventory（本局）与 meta.owned_weapons（局外）独立
# ② 开局携带武器自动加入本局仓库（当前已装备 ⊆ 本局已拥有）
# ③ reset_run_state 清空仓库，不落盘
# ④ 换下武器仍保留在本局仓库（G2-5 前瞻，验证仓库模型基础）
# 不污染真实存档：结束还原 meta。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G2 FAIL: " + label)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _run() -> void:
	var duel := await _boot()
	if duel == null:
		push_error("G2 boot failed")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_inventory_separate(duel)
	await _test_start_loadout_in_inventory(duel)
	_test_reset_clears(duel)
	await _test_swap_keeps_in_inventory(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()
	print("G2INV RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_inventory_separate(duel: DuelController) -> void:
	_ok(duel.run_weapon_inventory is Array, "run_weapon_inventory field exists")
	_ok(duel.meta.has("owned_weapons"), "meta.owned_weapons (out-of-run) still exists")
	# 本局仓库不落盘：不是 meta 的键
	_ok(not duel.meta.has("run_weapon_inventory"), "run inventory is not persisted in meta")


func _test_start_loadout_in_inventory(duel: DuelController) -> void:
	# _boot 后尚未 confirm_loadout，走一次完整开局
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres"])
	duel._confirm_loadout()
	await get_tree().process_frame
	for wpath in duel.selected_loadout:
		_ok(duel.run_weapon_inventory.has(wpath), "start loadout weapon in run inventory: %s" % wpath)
	_ok(duel.run_weapon_inventory.size() >= 2, "run inventory has both starter weapons (size=%d)" % duel.run_weapon_inventory.size())


func _test_reset_clears(duel: DuelController) -> void:
	duel.run_weapon_inventory.append("res://resources/weapon_templates/battle_axe.tres")
	_ok(duel.run_weapon_inventory.size() > 0, "inventory non-empty before reset")
	duel._reset_run_state()
	_ok(duel.run_weapon_inventory.is_empty(), "reset_run_state clears run inventory")


func _test_swap_keeps_in_inventory(duel: DuelController) -> void:
	# 开局仓库应含当前装备；换下武器（从 selected_loadout 移除）不应从仓库消失
	duel.selected_loadout.assign(["res://resources/weapon_templates/fire_sword.tres",
		"res://resources/weapon_templates/dagger.tres"])
	duel._confirm_loadout()
	await get_tree().process_frame
	var old_path := String(duel.selected_loadout[0])
	_ok(duel.run_weapon_inventory.has(old_path), "equipped weapon in inventory before swap")
	# 模拟换下：从装备移除，仓库应仍保留（G2-5 目标；仓库模型已支持）
	duel.selected_loadout.erase(old_path)
	_ok(duel.run_weapon_inventory.has(old_path), "swapped-out weapon still in run inventory")
