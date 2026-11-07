extends Node

# ============================================================================
# G6-01 生涯成就 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m4_career_test.tscn
#
# 覆盖：
# ① 新档/老档缺 career 键：默认空、不崩溃、下一目标可读；
# ② 首次 BOSS 通关解锁「初次深入」；同 BOSS 不重复解锁；
# ③ 四席猎手按不同 BOSS 数累计；同 ID 不重复计数；
# ④ 同素/异素配装判定；破甲、状态伤害、格挡、精英路线、棋盘武器格、和解；
# ⑤ 解锁跨局落盘（新 CareerSystem 从同一 meta 载入）；新解锁队列只取一次；
# ⑥ 整备页生涯面板可构建并列出全部条目。
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_defaults(duel)
	_test_first_and_duplicate(duel)
	_test_four_hunters(duel)
	_test_elements(duel)
	_test_combat_marks(duel)
	_test_board_marks(duel)
	_test_peaceful(duel)
	_test_persistence(duel)
	_test_panel(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _reset_career(duel: DuelController) -> void:
	duel.meta["career"] = {"unlocked": [], "bosses": []}
	duel._career = preload("res://scripts/systems/career_system.gd").new(duel)
	duel._telemetry.reset()
	duel.peaceful_win = false


func _boss_index(duel: DuelController) -> int:
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "boss":
			return i
	return -1


func _enter_boss(duel: DuelController) -> void:
	var idx := _boss_index(duel)
	duel.room_index = idx
	duel.current_room = duel.ROOMS[idx] if idx >= 0 else null


func _weapon(duel: DuelController, element: String, skip: Array = []) -> String:
	for p in duel.WEAPON_POOL:
		var w = load(p)
		if w is WeaponData and String(w.element) == element and not skip.has(p):
			return String(p)
	return ""


func _equip(duel: DuelController, elements: Array) -> void:
	duel.selected_loadout.clear()
	for e in elements:
		var p := _weapon(duel, String(e), duel.selected_loadout)
		if p != "":
			duel.selected_loadout.append(p)


func _test_defaults(duel: DuelController) -> void:
	# 老档：meta 里没有 career 键，构造不应崩溃，且可以正常查询/给出目标。
	duel.meta.erase("career")
	var c = preload("res://scripts/systems/career_system.gd").new(duel)
	_check(duel.meta.has("career"), "老档缺 career 键时载入自动补默认")
	_check(c.unlocked_count() == 0, "老档默认解锁数为 0")
	_check(c.total_count() == 10, "首批成就共 10 个")
	_check(c.next_goal_hint() != "", "老档也有下一目标")
	_check(c.take_new_unlocks().is_empty(), "初始新解锁队列为空")

	# 未知 ID / 空 BOSS ID 应被过滤，合法 ID 保留。
	duel.meta["career"] = {"unlocked": ["bogus", "first_clear"], "bosses": ["", "res://test/x.tres", "res://test/x.tres"]}
	var c2 = preload("res://scripts/systems/career_system.gd").new(duel)
	_check(c2.unlocked_count() == 1 and c2.has("first_clear"), "未知成就 ID 被过滤，合法 ID 保留")
	_check(c2.boss_count() == 1, "空/重复 BOSS ID 被过滤")


func _test_first_and_duplicate(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	_equip(duel, ["fire", "fire"])
	duel._career.on_boss_cleared()
	_check(duel._career.has("first_clear"), "首次 BOSS 通关解锁初次深入")
	_check(duel._career.has("same_element"), "两把同元素武器解锁同系共振")
	_check(not duel._career.has("off_element"), "同元素不误解锁异系调度")
	_check(duel._career.boss_count() == 1, "BOSS 计数为 1")
	_check(duel._career.take_new_unlocks().size() == 2, "新解锁队列含 2 项且取走后清空")
	_check(duel._career.take_new_unlocks().is_empty(), "新解锁队列只取一次")

	var before: int = duel._career.unlocked_count()
	duel._career.on_boss_cleared()
	_check(duel._career.unlocked_count() == before, "同一 BOSS 重复通关不再解锁")
	_check(duel._career.boss_count() == 1, "同一 BOSS 不重复计数")


func _test_four_hunters(duel: DuelController) -> void:
	_reset_career(duel)
	duel._career.record_boss("res://test/boss_a.tres")
	duel._career.record_boss("res://test/boss_a.tres")
	duel._career.record_boss("res://test/boss_b.tres")
	duel._career.record_boss("res://test/boss_c.tres")
	_check(not duel._career.has("four_hunters"), "3 个不同 BOSS 时未解锁四席猎手")
	duel._career.record_boss("res://test/boss_d.tres")
	_check(duel._career.has("four_hunters"), "4 个不同 BOSS 解锁四席猎手")
	_check(duel._career.boss_count() == 4, "重复 BOSS 不虚增计数")


func _test_elements(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	_equip(duel, ["fire", "ice"])
	duel._career.on_boss_cleared()
	_check(duel._career.has("off_element"), "两把异元素武器解锁异系调度")
	_check(not duel._career.has("same_element"), "异元素不误解锁同系共振")


func _test_combat_marks(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	duel._career.note_armor_break()
	duel._career.note_status_damage(30)
	duel._telemetry.damage_blocked = 40
	duel._career.on_boss_cleared()
	_check(duel._career.has("armor_break"), "BOSS 战破甲并获胜解锁破甲专家")
	_check(duel._career.has("status_apostle"), "BOSS 战状态伤害达标解锁状态使徒")
	_check(duel._career.has("guardian"), "本局格挡达标解锁坚守")

	# 非 BOSS 房不累计破甲/状态；BOSS 通关时不应误判。
	_reset_career(duel)
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "normal":
			duel.room_index = i
			break
	duel._career.note_armor_break()
	duel._career.note_status_damage(30)
	_enter_boss(duel)
	duel._career.on_boss_cleared()
	_check(not duel._career.has("armor_break"), "普通房破甲不误判为 BOSS 破甲")
	_check(not duel._career.has("status_apostle"), "普通房状态伤害不误判")

	# 门槛以下不解锁。
	_reset_career(duel)
	_enter_boss(duel)
	duel._career.note_status_damage(24)
	duel._telemetry.damage_blocked = 39
	duel._career.on_boss_cleared()
	_check(not duel._career.has("status_apostle"), "状态伤害低于门槛不解锁")
	_check(not duel._career.has("guardian"), "格挡低于门槛不解锁")


func _test_board_marks(duel: DuelController) -> void:
	_reset_career(duel)
	duel._career.note_board_weapon()
	_check(duel._career.has("board_treasure"), "棋盘武器格解锁棋盘寻宝")
	var before: int = duel._career.unlocked_count()
	duel._career.note_board_weapon()
	_check(duel._career.unlocked_count() == before, "棋盘寻宝不重复解锁")

	_reset_career(duel)
	var old_mode: bool = duel.node_mode
	duel.node_mode = true
	duel._career.note_elite_route()
	duel._career.on_boss_cleared()
	_check(duel._career.has("elite_route"), "经过精英分支并击败 BOSS 解锁高危路线")
	duel.node_mode = old_mode


func _test_peaceful(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	duel.peaceful_win = true
	duel._career.on_boss_cleared()
	_check(duel._career.has("peaceful"), "和解通关解锁特殊结局")
	duel.peaceful_win = false


func _test_persistence(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	duel._career.on_boss_cleared()
	var n: int = duel._career.unlocked_count()
	var b: int = duel._career.boss_count()
	duel._meta_store.save_meta()
	var again = preload("res://scripts/systems/career_system.gd").new(duel)
	_check(again.unlocked_count() == n, "成就解锁跨 CareerSystem 实例保留（%d）" % n)
	_check(again.boss_count() == b, "BOSS 记录跨实例保留（%d）" % b)
	_check(duel.meta["career"] is Dictionary, "career 以字典写入 meta")
	_check(duel.meta["career"].get("unlocked", []) is Array, "career.unlocked 为数组")


func _test_panel(duel: DuelController) -> void:
	var ls = duel.hud.loadout_screen
	_check(ls != null, "整备屏存在")
	if ls == null:
		return
	_check(ls._career_panel != null, "整备屏构建生涯面板")
	_check(ls._career_btn != null, "整备屏构建生涯按钮")
	ls._refresh_career()
	# 1 行标题 + 10 个成就 + 1 行下一目标
	_check(ls._career_box.get_child_count() == 12, "生涯面板列出 10 条成就与目标行")
