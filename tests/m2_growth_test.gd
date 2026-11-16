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
# ⑤ 落点：守势每房 +8 护盾；精打细算 +1 免费刷新
# ⑥ next_symbol：取当前位置的下一格，带子空时为 null
# ⑦ 流程：房间胜利且有待选 → 弹出三选一，选完才进入房间间歇
# ⑧ 新一局：reset_run 清零经验 / 等级 / 技艺
# ⑨ 回春房胜利回血（BOSS 房更多、不超上限）；积蓄房胜利给金
# ⑩ 2026-11-17 命中确定性三技艺：落点吸附（每回合 2 次）、宽判窗口（容差 ±2）、
#    废铁豁免（每回合 1 次）；旧的稳定节奏 / 洞察 / 稳手已移除。
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
	_check(not ids.has("frugal"), "精打细算不再进入随机技艺池")
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
	# 命中确定性三技艺的落点查询接口（未选中时均回落默认值）
	_check(g.snap_per_turn() == 0, "未选落点吸附：每回合次数 0")
	_check(g.mercy_per_turn() == 0, "未选废铁豁免：每回合次数 0")
	_check(g.wide_range() == 1, "未选宽判窗口：容差回落 ±1")
	_check(g.snap_range() == 1, "落点吸附容差常量 ±1")
	g.perk_ids.append("snap")
	g.perk_ids.append("mercy")
	g.perk_ids.append("wide")
	_check(g.snap_per_turn() == 2, "落点吸附：每回合 2 次")
	_check(g.mercy_per_turn() == 1, "废铁豁免：每回合 1 次")
	_check(g.wide_range() == 2, "宽判窗口：容差 ±2")
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

	# 2026-11-17 命中确定性三技艺的落点（替换原「稳手」缓冲测试）
	var rs = duel.reel_system
	var rd = duel.readability
	var trash = duel.TRASH_SYMBOL
	var gold = duel.GOLD_SYMBOL
	var gold_path: String = gold.resource_path
	var backup_strips = rs.reel_strips.duplicate(true)
	var backup_cursor = rs.reel_cursor.duplicate()
	var backup_stopped = rs.reel_stopped.duplicate()
	var backup_target: String = rd.target_symbol_path

	# —— 落点吸附：目标符号在视觉中心 ±1 内，吸附到最近目标格，每回合 2 次 ——
	g.perk_ids.append("snap")
	rd.buffer_enabled = false
	rd.visual_stop = false
	rd.begin_spin()
	rd.target_symbol_path = gold_path
	var strip_ag: Array = [[gold, "none"], [trash, "none"], [trash, "none"]]
	_check(rd.snap_ready(), "落点吸附：本回合次数未用完")
	_check(rd.snap_target_index(1, strip_ag) == 0, "落点吸附：视觉中心 1 时目标 gold 在相邻索引 0")
	var strip_far: Array = [[gold, "none"], [trash, "none"], [trash, "none"], [trash, "none"]]
	_check(rd.snap_target_index(2, strip_far) == -1, "落点吸附：目标距视觉中心超过 ±1 时不吸附")
	rd.consume_snap()
	rd.consume_snap()
	_check(not rd.snap_ready(), "落点吸附：每回合 2 次用尽")
	rd.begin_spin()
	_check(rd.snap_ready(), "落点吸附：下一回合次数重置")

	# —— 废铁豁免：落点是废铁时改判相邻非废铁格，每回合 1 次 ——
	# 先移除落点吸附，避免它把目标 gold 提前吸附走、干扰废铁判定。
	g.perk_ids.erase("snap")
	g.perk_ids.append("mercy")
	rd.begin_spin()
	rd.target_symbol_path = ""   # 豁免不依赖目标符号
	_check(rd.mercy_ready(), "废铁豁免：本回合可用")
	var strip_tr: Array = [[trash, "none"], [gold, "none"]]
	rs.reel_strips = [strip_tr]
	rs.reel_cursor.clear()
	rs.reel_cursor.append(0)
	rs.reel_stopped.clear()
	rs.reel_stopped.append(false)
	rs._pending_stops.clear()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	# 视觉中心置 0（非旋转态默认 = cursor），落点为废铁 → 豁免改判到 gold(1)
	rs.lock_reel(0)
	_check(rd.mercy_used == 1, "废铁豁免：废铁落点触发改判并用掉 1 次")
	_check(not rd.mercy_ready(), "废铁豁免：每回合 1 次用尽")
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[0], "废铁豁免：吸附完成后落子")

	rd.begin_spin()
	_check(rd.mercy_ready(), "废铁豁免：下一回合次数重置")
	rd.target_symbol_path = backup_target
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
	_check(rs.next_symbol(0) == b, "next_symbol：下一格为带子位置 +1 的符号")
	rs.reel_cursor[0] = 1
	_check(rs.next_symbol(0) == a, "next_symbol：末格后循环回到首格")
	rs.reel_strips = [[]]
	_check(rs.next_symbol(0) == null, "next_symbol：空带子返回 null")
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
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后结算")
	_check(duel.room_flow.post_battle_phase() == "loot", "战后先展示同层战利品三选一")
	_check(screen.visible and screen.title_label.text.find("成长") >= 0, "成长三选一界面标题正确")
	_check(screen.reward_grid.get_child_count() == 3, "战利品固定三张同层卡")
	_check(not duel.in_interroom, "战利品结算前不进入房间间歇")
	_check(duel.room_flow.post_battle_has_growth(), "有待处理成长时成长队列非空")
	var cand: Dictionary = duel.room_flow.post_battle_growth_candidate()
	_check(String(cand.get("kind", "")) == "perk", "成长位为技艺（历练先触发）")
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
