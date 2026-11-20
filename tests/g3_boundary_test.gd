extends Node

# ============================================================================
# G3-4 边界处理测试（2026-11-20）：共享符号 / 多来源 / 换装休眠 / 核心保护 / 敌人注废
# 权威方案 §5.2「合法性规则」+ G3-4 任务
# 运行：Godot --headless --fixed-fps 60 --path . res://tests/g3_boundary_test.tscn
# ============================================================================

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FROST_BLADE := "res://resources/weapon_templates/frost_blade.tres"
const FORGE_GREATSWORD := "res://resources/weapon_templates/forge_greatsword.tres"

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G3-4 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	_test_shared_scope(duel)
	_test_trim_core_protection(duel)
	_test_trim_dormancy_on_swap(duel)
	_test_enemy_trash_not_trimmable(duel)

	print("G3-4 BOUNDARY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ① 共享符号作用范围：单武器 single，双武器共享 multi
func _test_shared_scope(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	var comp1: Dictionary = ReelPreview.compose(duel.selected_loadout, [], [], {}, {}, 0, false, 0, {}, {}, {})
	var rows1: Array = comp1["rows"]
	var multi1 := 0
	for r in rows1:
		if String((r as Dictionary)["source_scope"]) == "multi":
			multi1 += 1
	_ok(multi1 == 0, "单武器：无 multi 来源符号")

	duel.selected_loadout.assign([FIRE_SWORD, FORGE_GREATSWORD])
	duel._build_pool(duel.selected_loadout)
	var comp2: Dictionary = ReelPreview.compose(duel.selected_loadout, [], [], {}, {}, 0, false, 0, {}, {}, {})
	var rows2: Array = comp2["rows"]
	var has_multi := false
	for r in rows2:
		var d: Dictionary = r
		if String(d["source_scope"]) == "multi":
			has_multi = true
			_ok(d["items"].size() >= 2, "multi 符号 items 含多来源: %s" % str(d["items"]))
			break
	_ok(has_multi, "双武器共享符号：存在 multi 来源标记")


# ② 核心保护：精简不会删到无 damage 输出 / 每武器无格
func _test_trim_core_protection(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD, FROST_BLADE])
	duel._build_pool(duel.selected_loadout)
	duel._trim.reset_run()
	duel._trim.grant(8)  # 充足次数，反复精简直到无法再减
	var rounds := 0
	while rounds < 12:
		var cands: Array = duel._trim.candidates()
		if cands.is_empty():
			break
		duel._trim.apply(cands[0])
		duel._build_pool(duel.selected_loadout)
		rounds += 1
	var comp: Dictionary = ReelPreview.compose(duel.selected_loadout, [], [], {}, {}, 0, false, 0, {}, {}, duel._trim.trimmed)
	var damage_cells := 0
	for r in comp["rows"]:
		if String((r as Dictionary)["kind"]) == "damage":
			damage_cells += int((r as Dictionary)["cells"])
	_ok(damage_cells > 0, "反复精简后仍有 damage 格（核心保护，%d）" % damage_cells)
	_ok(not duel._trim.candidates().is_empty() or damage_cells > 0, "精简到极限时合法候选耗尽而非制造死带")


# ③ 换装休眠：trim 记录按 key 保留，换武器不退款
func _test_trim_dormancy_on_swap(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	duel._trim.reset_run()
	duel._trim.grant(1)
	var cands: Array = duel._trim.candidates()
	if cands.is_empty():
		_ok(false, "换装休眠前置：有精简候选")
		return
	var key: String = String(cands[0]["key"])
	duel._trim.apply(cands[0])
	_ok(int(duel._trim.trimmed.get(key, 0)) > 0, "换装休眠前置：trim 记录已写入")

	# 换到不含该符号的武器（霜晶法杖），记录应保留（休眠）
	duel.selected_loadout.assign(["res://resources/weapon_templates/ice_staff.tres"])
	duel._build_pool(duel.selected_loadout)
	_ok(int(duel._trim.trimmed.get(key, 0)) > 0, "换装后：trim 记录保留（休眠，不暗中退款）")

	# 换回原武器，记录仍生效
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	_ok(int(duel._trim.trimmed.get(key, 0)) > 0, "换回后：trim 记录恢复生效")


# ④ 敌人注废不被精简：boss_trash 独立于 trim
func _test_enemy_trash_not_trimmable(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD])
	duel.boss_trash = 3
	duel._build_pool(duel.selected_loadout)
	duel.reel_system.build_strips()
	var trash_before := 0
	for entry in duel.reel_system.reel_strips[0]:
		var sym = entry[0] if entry is Array else entry
		if sym != null and String(sym.kind) == "trash":
			trash_before += 1
	_ok(trash_before >= 3, "敌人注废进入带子（%d 格）" % trash_before)

	# 精简一个符号后，注废格数不应减少（注废不在 agg，不受 trim 影响）
	duel._trim.reset_run()
	duel._trim.grant(1)
	var cands: Array = duel._trim.candidates()
	if not cands.is_empty():
		duel._trim.apply(cands[0])
		duel.reel_system.build_strips()
	var trash_after := 0
	for entry in duel.reel_system.reel_strips[0]:
		var sym = entry[0] if entry is Array else entry
		if sym != null and String(sym.kind) == "trash":
			trash_after += 1
	_ok(trash_after >= 3, "精简后敌人注废仍保留（不被精简，%d 格）" % trash_after)
	duel.boss_trash = 0
