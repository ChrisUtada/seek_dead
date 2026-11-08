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
# ⑥ 整备页生涯面板可构建并列出全部条目；
# ⑦ G6-03 局末路线总结：路线 / 成长 / 新收藏 / 下一局建议与元进度屏集成。
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
	_test_directed_unlock(duel)
	_test_run_summary(duel)
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
	_check(c.unlock_charges() == 0, "老档默认定向解锁机会为 0")

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


func _owned_has(duel: DuelController, path: String) -> bool:
	for key in ["owned_weapons", "owned_charms", "owned_consumables"]:
		var arr: Array = duel.meta.get(key, [])
		if arr.has(path):
			return true
	return false


func _test_directed_unlock(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	_equip(duel, ["fire", "ice"])
	duel._career.on_boss_cleared()
	_check(duel._career.unlock_charges() == 1, "首次通关获得 1 次定向解锁")

	var cands: Array = duel._career.roll_unlock_candidates(3)
	_check(cands.size() == 3, "定向解锁给出 3 个候选")
	var seen := {}
	for c in cands:
		var p := String(c.get("path", ""))
		_check(p != "" and not seen.has(p), "候选路径非空且不重复")
		seen[p] = true
		_check(not _owned_has(duel, p), "候选均为未拥有：%s" % p.get_file())
		var res = load(p)
		_check(not (res is ItemData and duel._meta_store._is_boss_relic(res, p)), "候选不含 BOSS 信物")
		_check(String(c.get("name", "")) != "" and String(c.get("desc", "")) != "", "候选带名称与类别说明")

	var pick := String(cands[0].get("path", ""))
	_check(duel._career.grant_unlock(pick), "选中后写入拥有池")
	_check(duel._career.unlock_charges() == 0, "解锁机会消耗一次")
	_check(_owned_has(duel, pick), "选中物品进入对应拥有池")
	_check(duel._career.roll_unlock_candidates(3).is_empty(), "无机会时不再给出候选")

	# 四席猎手里程碑同样给一次机会。
	_reset_career(duel)
	for i in range(4):
		duel._career.record_boss("res://test/boss_%d.tres" % i)
	_check(duel._career.has("four_hunters") and duel._career.unlock_charges() == 1, "四席猎手给 1 次定向解锁")

	# 局末界面先展示解锁三选一，选完回到铁砧点结算。
	_reset_career(duel)
	_enter_boss(duel)
	duel._career.on_boss_cleared()
	var ms = duel.hud.meta_screen
	ms.show_choice()
	_check(ms.visible, "局末解锁屏可见")
	_check(ms.title_label.text.contains("生涯解锁"), "局末先显示生涯解锁标题")
	_check(ms.meta_grid.get_child_count() == 3, "局末解锁屏显示 3 张卡")
	var ui_pick := String(duel._career.roll_unlock_candidates(3)[0].get("path", ""))
	duel._on_career_unlock_chosen(ui_pick)
	_check(duel._career.unlock_charges() == 0, "界面选择后机会清零")
	_check(_owned_has(duel, ui_pick), "界面选择写入拥有池")
	_check(not ms.title_label.text.contains("生涯解锁"), "解锁后回到原元进度结算")
	_check(ms.meta_grid.get_child_count() == 1, "原元进度仍显示铁砧点卡")


func _test_run_summary(duel: DuelController) -> void:
	_reset_career(duel)
	_enter_boss(duel)
	var rs = preload("res://scripts/systems/run_summary.gd").new(duel)

	# 收藏快照：基线只有匕首，本局新增火焰剑。
	duel.meta["owned_weapons"] = ["res://resources/weapon_templates/dagger.tres"]
	duel.meta["owned_charms"] = []
	duel.meta["owned_consumables"] = []
	rs.snapshot()
	duel.meta["owned_weapons"].append("res://resources/weapon_templates/fire_sword.tres")
	_check(rs.collection_line().contains("火焰剑"), "局末总结列出本局新增武器")
	_check(rs.collection_line().contains("新收藏："), "局末总结带新收藏前缀")

	# 成长：等级 + 熟练 + R 等级。
	duel.growth.level = 3
	duel.mastery.mastery.clear()
	duel.mastery.mastery["res://resources/weapon_templates/dagger.tres"] = 4
	var gl: String = rs.growth_line()
	_check(gl.contains("Lv.3"), "局末总结显示本局等级")
	_check(gl.contains("匕首") and gl.contains("R2"), "局末总结显示熟练与 R 等级")

	# 棋盘路线：骨架/模板 + 已走节点分类计数。
	var old_mode: bool = duel.node_mode
	var old_shape = duel.board_config.shape_id
	duel.node_mode = true
	duel.board_config.shape_id = "standard"
	_check(duel.board.generate(duel.board_config), "测试棋盘可生成")
	var marked := {"normal": false, "elite": false, "shop": false, "rest": false, "special": false}
	for n in duel.board.nodes:
		var t := String(n.get("type", ""))
		if marked.has(t) and not bool(marked[t]):
			duel.board.consumed[String(n["id"])] = true
			marked[t] = true
		elif t in ["weapon", "charm", "treasure", "shrine", "armory"] and not bool(marked["special"]):
			duel.board.consumed[String(n["id"])] = true
			marked["special"] = true
	var rl: String = rs.route_line()
	_check(rl.contains("棋盘") and rl.contains("标准"), "局末总结显示棋盘骨架")
	_check(rl.contains("战斗1") and rl.contains("精英1") and rl.contains("特殊1"), "局末总结按节点类型计数")
	duel.board.reset()
	duel.node_mode = old_mode
	duel.board_config.shape_id = old_shape

	# 线性路线：房型计数 + 终局 BOSS。
	var ll: String = rs.route_line()
	_check(ll.contains("线性") and ll.contains("BOSS"), "线性模式给房型计数")

	# 下一局建议：生涯目标 + 剩余解锁机会。
	duel._career._unlock_charges = 1
	_check(rs.next_line().contains("定向解锁"), "下一局建议提示剩余解锁机会")
	duel._career._unlock_charges = 0

	# 元进度屏集成：四行摘要都进入副标题。
	duel.hud.meta_screen.show_choice()
	var sub: String = duel.hud.meta_screen.sub_label.text
	_check(sub.contains("路线：") and sub.contains("成长："), "局末屏展示路线与成长")
	_check(sub.contains("新收藏：") and sub.contains("下一局建议："), "局末屏展示新收藏与建议")
	_check(rs.lines().size() == 4, "局末总结固定四行")
	duel.hud.meta_screen.hide_screen()


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
