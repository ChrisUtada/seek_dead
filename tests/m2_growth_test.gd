extends Node

# ============================================================================
# M2-01 角色历练与技艺 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_growth_test.tscn
#
# 覆盖（docs/统一落地执行计划.md M2-01 / docs/M0-02_样板范围.md §1）：
# ① 历练经验：普通 1 / 精英 2 / BOSS 3；Lv.2 @3、Lv.3 @7、Lv.4 @12；每级最大 HP +5 并恢复
# ② 技艺次数：仅 Lv.2 / Lv.4 各给 1 次待选；Lv.4 封顶，之后经验照常累计但不再升级
# ③ 三选一候选：3 个、互不相同、均未拥有、覆盖不同家族
# ④ 选定：非法选择拒绝；同一技艺不可重复；坚韧 +10 HP 并恢复；备用药剂 腰带各 +1
# ⑤ 落点：守势每房 +8 护盾；精打细算 +1 免费刷新；稳定节奏 前 2 回合间隔 0.17s
# ⑥ 洞察：转轮 next_symbol 取当前位置的下一格，带子空时为 null
# ⑦ 流程：房间胜利且有待选 → 弹出三选一，选完才进入房间间歇
# ⑧ 新一局：reset_run 清零经验 / 等级 / 技艺
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
	var meta_backup: Dictionary = duel.meta.duplicate(true)   # 流程测试会结算铁砧/金币：结束还原

	_test_xp_and_levels(duel)
	_test_perk_choices(duel)
	_test_pick_rules(duel)
	_test_hooks(duel)
	_test_next_symbol(duel)
	_test_room_flow_offers_pick(duel)
	_test_reset(duel)

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


func _fresh(duel: DuelController) -> void:
	duel.growth.reset_run()
	duel.player_hp_max = 100
	duel.player_hp = 100
	duel.turn_count = 1


func _test_xp_and_levels(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	g.grant_room_xp("normal")
	_check(g.xp == 1 and g.level == 1, "普通房 +1 历练经验，仍为 Lv.1")
	g.grant_room_xp("elite")
	_check(g.xp == 3 and g.level == 2, "累计 3 经验升 Lv.2")
	_check(duel.player_hp_max == 105, "Lv.2 最大 HP +5")
	_check(g.pending_picks == 1, "Lv.2 给 1 次技艺选择")
	g.grant_room_xp("normal")
	g.grant_room_xp("elite")
	_check(g.xp == 6 and g.level == 2, "累计 6 经验仍为 Lv.2")
	g.grant_room_xp("normal")
	_check(g.level == 3 and duel.player_hp_max == 110, "累计 7 升 Lv.3，最大 HP 再 +5")
	_check(g.pending_picks == 1, "Lv.3 不额外给技艺")
	g.grant_room_xp("boss")
	_check(g.xp == 10 and g.level == 3, "BOSS 房 +3，累计 10 仍为 Lv.3")
	g.grant_room_xp("boss")
	_check(g.level == 4 and duel.player_hp_max == 115, "累计 12 升 Lv.4，最大 HP 再 +5")
	_check(g.pending_picks == 2, "Lv.4 累计 2 次技艺选择")
	g.grant_room_xp("boss")
	_check(g.level == 4 and g.pending_picks == 2 and duel.player_hp_max == 115, "Lv.4 封顶：经验累计但不再升级")
	_check(g.xp == 16, "封顶后经验照常累计（16）")


func _test_perk_choices(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	var choices: Array = g.roll_choices()
	_check(choices.size() == 3, "三选一候选为 3 个")
	var ids := {}
	for c in choices:
		ids[c["id"]] = true
	_check(ids.size() == 3, "三选一候选互不相同")
	var fams := {}
	for c in choices:
		fams[c["family"]] = true
	_check(fams.size() == 3, "三选一候选覆盖 3 个不同家族（生存/运筹/目押）")
	for c in choices:
		_check(not g.has_perk(c["id"]), "候选 %s 未拥有" % c["name"])


func _test_pick_rules(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	_check(not g.pick("tough"), "无待选次数时拒绝选择")
	g.pending_picks = 2
	duel.player_hp = 50
	_check(g.pick("tough"), "坚韧可选")
	_check(duel.player_hp_max == 110, "坚韧：最大 HP +10")
	_check(duel.player_hp == 60, "坚韧：立即恢复 10 HP")
	_check(g.pending_picks == 1, "选定后待选次数 -1")
	_check(not g.pick("tough"), "同一技艺不可重复")
	_check(not g.pick("no_such_perk"), "未知技艺拒绝")
	duel.consumable_slots.clear()
	duel.consumable_slots.append({"path": "", "item_id": "a", "charges": 1, "uid": 1})
	duel.consumable_slots.append({"path": "", "item_id": "b", "charges": 2, "uid": 2})
	_check(g.pick("reserve"), "备用药剂可选")
	_check(duel.consumable_slots[0]["charges"] == 2 and duel.consumable_slots[1]["charges"] == 3, "备用药剂：腰带各消耗品 +1 次")
	_check(g.pending_picks == 0, "两次选择后待选次数清零")
	duel.consumable_slots.clear()


func _test_hooks(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	_check(g.room_shield() == 0, "未选守势：无开局护盾")
	g.perk_ids.append("guard")
	_check(g.room_shield() == 8, "守势：每房开局护盾 8")
	_check(g.free_reroll_bonus() == 0, "未选精打细算：无额外免费刷新")
	g.perk_ids.append("frugal")
	_check(g.free_reroll_bonus() == 1, "精打细算：+1 免费刷新")
	duel.charm_free_reroll = 0
	_check(duel._shop_system.free_reroll_count() == 1, "商店免费刷新计数叠加精打细算（+1）")
	_check(is_equal_approx(g.spin_wait_base(0.15), 0.15), "未选稳定节奏：间隔保持 0.15")
	g.perk_ids.append("steady")
	duel.turn_count = 1
	_check(is_equal_approx(g.spin_wait_base(0.15), 0.17), "稳定节奏：第 1 回合间隔 0.17")
	duel.turn_count = 2
	_check(is_equal_approx(g.spin_wait_base(0.15), 0.17), "稳定节奏：第 2 回合间隔 0.17")
	duel.turn_count = 3
	_check(is_equal_approx(g.spin_wait_base(0.15), 0.15), "稳定节奏：第 3 回合起回落 0.15")
	g.perk_ids.clear()


func _test_next_symbol(duel: DuelController) -> void:
	var rs = duel.reel_system
	var a = duel.TRASH_SYMBOL
	var b = duel.GOLD_SYMBOL
	var backup_strips = rs.reel_strips.duplicate(true)
	var backup_cursor = rs.reel_cursor.duplicate()
	rs.reel_strips = [[[a, "none"], [b, "none"]]]
	rs.reel_cursor.clear()
	rs.reel_cursor.append(0)
	_check(rs.next_symbol(0) == b, "洞察：下一格为带子位置 +1 的符号")
	rs.reel_cursor[0] = 1
	_check(rs.next_symbol(0) == a, "洞察：末格后循环回到首格")
	rs.reel_strips = [[]]
	_check(rs.next_symbol(0) == null, "洞察：空带子返回 null")
	rs.reel_strips = backup_strips
	rs.reel_cursor = backup_cursor


func _test_room_flow_offers_pick(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	g.xp = 2   # 任意房型胜利（至少 +1）即升 Lv.2
	duel.room_index = 0
	duel.in_interroom = false
	duel.room_flow.finish_room(Callable(), false)
	_check(g.level == 2 and g.pending_picks == 1, "房间胜利升 Lv.2 后待选 1 次")
	_check(duel.hud._growth_picker != null and duel.hud._growth_picker.visible, "待选时弹出成长结算")
	_check(not duel.in_interroom, "成长结算确认前不进入房间间歇")
	_check(duel.hud._growth_picker._confirm_btn.disabled, "未选定技艺前确认按钮禁用")
	var has_btn := false
	for c in duel.hud._growth_picker._vbox.get_children():
		if c is Button and c.text.begins_with("["):
			has_btn = true
	_check(has_btn, "技艺候选按钮已渲染（含家族标签）")
	_check(duel.room_flow.growth_pick_pending(), "成长结算待确认")
	duel.room_flow.auto_pick_growth()
	_check(g.pending_picks == 0 and g.perk_ids.size() == 1, "确认后待选清零、技艺入列")
	_check(duel.in_interroom, "确认成长后进入房间间歇")
	_check(not duel.room_flow.growth_pick_pending(), "确认后无待确认项")
	duel.hud._growth_picker.visible = false
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_reset(duel: DuelController) -> void:
	duel.growth.xp = 9
	duel.growth.level = 3
	duel.growth.perk_ids.append("tough")
	duel.growth.pending_picks = 1
	duel.growth.reset_run()
	_check(duel.growth.xp == 0 and duel.growth.level == 1, "新一局：经验与等级清零")
	_check(duel.growth.perk_ids.is_empty() and duel.growth.pending_picks == 0, "新一局：技艺清零")
