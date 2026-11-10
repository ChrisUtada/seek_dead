extends Node

# ============================================================================
# M2-01 角色历练与技艺 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_growth_test.tscn
#
# 覆盖（docs/统一落地执行计划.md M2-01 / docs/M0-02_样板范围.md §1；
# G7-A S1 起成长扩至 Lv.6 / 3 技艺 / 池 9，见 docs/G7-A_切片拆分与验收清单_2026-11-08.md）：
# ① 历练经验：普通 1 / 精英 2 / BOSS 3；Lv.2 @3、Lv.3 @7、Lv.4 @12、Lv.5 @20、Lv.6 @30；每级最大 HP +5 并恢复
# ② 技艺次数：Lv.2 / Lv.4 / Lv.6 各给 1 次待选；Lv.6 封顶，之后经验照常累计但不再升级
# ③ 三选一候选：3 个、互不相同、均未拥有、覆盖不同家族
# ④ 选定：非法选择拒绝；同一技艺不可重复；坚韧 +10 HP 并恢复；备用药剂 腰带各 +1
# ⑤ 落点：守势每房 +8 护盾；精打细算 +1 免费刷新；稳定节奏 前 2 回合间隔 0.17s
# ⑥ 洞察：转轮 next_symbol 取当前位置的下一格，带子空时为 null
# ⑦ 流程：房间胜利且有待选 → 弹出三选一，选完才进入房间间歇
# ⑧ 新一局：reset_run 清零经验 / 等级 / 技艺
# ⑨ G7-A S1 新技艺：回春房胜利回血（BOSS 房更多、不超上限）；积蓄房胜利给金；稳手每回合一次缓冲
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
	_test_new_perks(duel)
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
	_check(g.xp == 13 and g.level == 4 and duel.player_hp_max == 115, "累计 13 升 Lv.4，最大 HP 再 +5")
	_check(g.pending_picks == 2, "Lv.4 累计 2 次技艺选择")
	g.grant_room_xp("boss")
	_check(g.xp == 16 and g.level == 4, "累计 16 仍为 Lv.4（G7-A：Lv.5 门槛 20）")
	g.grant_room_xp("elite")
	g.grant_room_xp("elite")
	_check(g.xp == 20 and g.level == 5 and duel.player_hp_max == 120, "累计 20 升 Lv.5，最大 HP +5")
	_check(g.pending_picks == 2, "Lv.5 不额外给技艺")
	g.grant_room_xp("boss")
	g.grant_room_xp("boss")
	g.grant_room_xp("boss")
	_check(g.xp == 29 and g.level == 5, "累计 29 仍为 Lv.5（Lv.6 门槛 30）")
	g.grant_room_xp("boss")
	_check(g.xp == 32 and g.level == 6 and duel.player_hp_max == 125, "累计 30 升 Lv.6，最大 HP 125")
	_check(g.pending_picks == 3, "Lv.6 累计 3 次技艺选择（上限）")
	g.grant_room_xp("boss")
	_check(g.level == 6 and g.pending_picks == 3 and duel.player_hp_max == 125, "Lv.6 封顶：经验累计但不再升级")
	_check(g.xp == 35, "封顶后经验照常累计（35）")


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
		_check(String(c.get("hint", "")) != "", "候选 %s 带方向提示（%s）" % [c["name"], String(c.get("hint", ""))])
		_check(String(c["desc"]).find("→") >= 0 or String(c["desc"]).find("提前") >= 0,
			"候选 %s 给出可量化前后效果" % c["name"])


func _test_pick_rules(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	_check(not g.pick("tough"), "无待选次数时拒绝选择")
	g.pending_picks = 2
	duel.player_hp = 50
	_check(g.pick("tough"), "坚韧可选")
	_check(duel.player_hp_max == 110, "坚韧：最大 HP +10")
	_check(duel.player_hp == 60, "坚韧：立即恢复 10 HP")
	_check(g.summary_line().find("生存×1") >= 0, "成长摘要按家族聚合（生存×1）")
	_check(g.detail_text().find("坚韧") >= 0, "成长明细包含已选技艺名")
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


func _test_new_perks(duel: DuelController) -> void:
	# 回春 / 积蓄：房胜利结算（普通房与 BOSS 房两档）
	_fresh(duel)
	var g = duel.growth
	g.perk_ids.append("regen")
	duel.player_hp_max = 125
	duel.player_hp = 100
	g.apply_victory_perks("normal")
	_check(duel.player_hp == 104, "回春：普通房胜利恢复 4 HP")
	duel.player_hp = 120
	g.apply_victory_perks("boss")
	_check(duel.player_hp == 125, "回春：BOSS 房回血不超上限（120 → 125）")
	duel.player_hp = 100
	g.apply_victory_perks("boss")
	_check(duel.player_hp == 108, "回春：BOSS 房胜利恢复 8 HP")

	g.perk_ids.clear()
	duel.gold = 0
	g.apply_victory_perks("normal")
	_check(duel.gold == 0, "未选积蓄：房胜利不给金")
	g.perk_ids.append("hoard")
	g.apply_victory_perks("normal")
	_check(duel.gold == 2, "积蓄：普通房胜利 +2 金")
	g.apply_victory_perks("boss")
	_check(duel.gold == 7, "积蓄：BOSS 房胜利 +5 金")
	g.enabled = false
	g.apply_victory_perks("boss")
	_check(duel.gold == 7, "探针关闭时不结算房胜利技艺")
	g.enabled = true
	g.perk_ids.clear()

	# 稳手：视觉中心在下一格时，每回合可用一次一拍缓冲；用掉后本回合不再缓冲
	var rs = duel.reel_system
	var rd = duel.readability
	var a = duel.TRASH_SYMBOL
	var b = duel.GOLD_SYMBOL
	var backup_strips = rs.reel_strips.duplicate(true)
	var backup_cursor = rs.reel_cursor.duplicate()
	var backup_stopped = rs.reel_stopped.duplicate()
	g.perk_ids.append("steady_hand")
	rd.buffer_enabled = false
	rd.visual_stop = false
	rd.begin_spin()
	_check(rd.steady_hand_ready(), "稳手：预设未开缓冲时仍可用（每回合一次）")
	rs.reel_strips = [[[a, "none"], [b, "none"]]]
	rs.reel_cursor.clear()
	for i in DuelController.REELS:
		rs.reel_cursor.append(0)
	rs.reel_stopped.clear()
	for i in DuelController.REELS:
		rs.reel_stopped.append(false)
	rs._pending_stops.clear()
	# 视觉中心由 ReelSpinView 计算：非旋转态直接等于 cursor，测不出「下一格」。
	# 这里把视图置为旋转态（_index=0、_frac=1.0、带子 2 格），视觉中心固定为索引 1，
	# 逻辑游标停在 0 → 正好是「视觉中心在下一格」。
	var view = duel.hud.cell_spin_views[0][0]
	var backup_active = view._active
	var backup_frac = view._frac
	var backup_index = view._index
	view._index = 0
	view._frac = 1.0
	view._active = true
	var vi: int = duel.hud.visual_center_index(0)
	_check(vi == 1, "稳手测试前提：视觉中心为索引 1（实测 %d）" % vi)
	rs.reel_cursor[0] = 0
	# Step 4：普通怪可能带「首轮注废」特性（窃语咒师），注废列会跳过视觉缓冲。
	# 本子测只验证稳手缓冲，先清掉本房干扰列，避免测试依赖随机抽到的房间。
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	rs.lock_reel(0)
	_check(rs.has_pending_stop(0) and not rs.reel_stopped[0], "稳手：进入一拍缓冲而不是立即落子")
	_check(not rd.steady_hand_ready(), "稳手：本回合的缓冲已用掉")
	rs._pending_stops.clear()
	rs.reel_stopped[0] = false
	rs.lock_reel(0)
	_check(rs.reel_stopped[0], "稳手：本回合第二次按停不再缓冲，直接落子")
	rd.begin_spin()
	_check(rd.steady_hand_ready(), "稳手：下一回合重新可用")
	view._active = backup_active
	view._frac = backup_frac
	view._index = backup_index
	rs.reel_strips = backup_strips
	rs.reel_cursor = backup_cursor
	rs.reel_stopped = backup_stopped
	rs._pending_stops.clear()
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
	var screen = duel.hud.reward_screen
	duel.room_flow.begin_post_battle()
	_check(g.level == 2 and g.pending_picks == 1, "房间胜利升 Lv.2 后待选 1 次")
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后成长三槽")
	_check(screen.visible and screen.title_label.text == "战后成长 · 选择一项", "战后成长界面标题正确")
	_check(screen.reward_grid.get_child_count() == 3, "战后成长固定三张槽位卡")
	_check(not duel.in_interroom, "战后成长确认前不进入房间间歇")
	_check(duel.room_flow.post_battle_has_growth(), "有待处理成长时成长位为真实成长")
	var cands: Array = duel.room_flow.post_offer()
	_check(String(cands[2].get("kind", "")) == "perk", "成长位为技艺（历练先触发）")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(g.pending_picks == 0 and g.perk_ids.size() == 1, "确认后待选清零、技艺入列")
	_check(duel.in_interroom, "确认成长后进入房间间歇")
	_check(not duel.room_flow.post_battle_active, "确认后无待确认项")
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
