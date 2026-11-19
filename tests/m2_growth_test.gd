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

	_test_perk_offer(duel)
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


# 2026-11-19 P0.3：等级/经验已移除，技艺保底归 RewardSystem（一次性前3房）
func _test_perk_offer(duel: DuelController) -> void:
	_fresh(duel)
	var rs = duel._reward_system
	_check(rs.skill_pity_rooms == 0 and not rs.skill_offer_guarantee_satisfied, "新局保底状态清零")
	# 前 3 房保底：逐房计数，达到门槛时 should_force_skill 为真
	var forced := false
	for i in range(rs.SKILL_PITY_ROOMS):
		rs.note_skill_pity_room(true)
		if rs.should_force_skill():
			forced = true
			break
	_check(forced, "前 %d 房保底触发强制技艺" % rs.SKILL_PITY_ROOMS)
	# 展示后一次性完成，之后不再强制
	rs.mark_skill_offer_satisfied()
	_check(not rs.should_force_skill(), "保底完成后不再强制")
	rs.note_skill_pity_room(true)
	_check(not rs.should_force_skill(), "保底完成后计数不再触发")


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
	_check(fams.size() == 2, "三选一候选覆盖 2 个家族（生存/运筹，目押已迁出）")
	for c in choices:
		_check(not g.has_perk(c["id"]), "候选 %s 未拥有" % c["name"])
		_check(String(c.get("hint", "")) != "", "候选 %s 带方向提示（%s）" % [c["name"], String(c.get("hint", ""))])
		var d: String = String(c["desc"])
		_check(d.find("→") >= 0 or d.find("提前") >= 0 or d.find("+") >= 0,
			"候选 %s 给出可量化效果" % c["name"])


func _test_pick_rules(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	duel.player_hp = 50
	_check(g.pick("tough"), "坚韧可选")
	_check(duel.player_hp_max == 110, "坚韧：最大 HP +10")
	_check(duel.player_hp == 60, "坚韧：立即恢复 10 HP")
	_check(g.summary_line().find("生存×1") >= 0, "成长摘要按家族聚合（生存×1）")
	_check(g.detail_text().find("坚韧") >= 0, "成长明细包含已选技艺名")
	_check(not g.pick("tough"), "同一技艺不可重复")
	_check(not g.pick("no_such_perk"), "未知技艺拒绝")
	duel.consumable_slots.clear()
	duel.consumable_slots.append({"path": "", "item_id": "a", "charges": 1, "uid": 1})
	duel.consumable_slots.append({"path": "", "item_id": "b", "charges": 2, "uid": 2})
	_check(g.pick("reserve"), "备用药剂可选")
	_check(duel.consumable_slots[0]["charges"] == 2 and duel.consumable_slots[1]["charges"] == 3, "备用药剂：腰带各消耗品 +1 次")
	duel.consumable_slots.clear()


func _test_hooks(duel: DuelController) -> void:
	_fresh(duel)
	var g = duel.growth
	_check(g.room_shield() == 0, "未选守势：无开局护盾")
	g.perk_ids.append("guard")
	_check(g.room_shield() == 8, "守势：每房开局护盾 8")
	# 免费刷新现在只来自信物「迷宫回声」，技艺「精打细算」已移除
	duel.charm_free_reroll = 0
	_check(duel._shop_system.free_reroll_count() == 0, "无信物时商店无免费刷新")
	duel.charm_free_reroll = 2
	_check(duel._shop_system.free_reroll_count() == 2, "商店免费刷新来自信物迷宫回声（+2）")
	# P1.1③：操控能力唯一由 reel_controls 授予，技艺不再授予（旧 aim 三技艺已迁出）
	_check(g.snap_per_turn() == 0, "无操控授予：吸附次数 0")
	_check(g.mercy_per_turn() == 0, "无操控授予：废铁转化次数 0")
	_check(g.snap_range() == 2, "落点吸附容差常量 ±2（B方案放宽）")
	var accel_before: float = duel.reel_system._accel()
	duel.reel_controls["snap"] = true
	duel.reel_controls["mercy"] = true
	duel.reel_controls["slow_ramp"] = true
	_check(g.snap_per_turn() == 2, "reel_controls 授予吸附：每回合 2 次")
	_check(g.mercy_per_turn() == 1, "reel_controls 授予废铁转化：每回合 1 次")
	_check(duel.reel_system._accel() < accel_before, "slow_ramp 授予后每拍加速度变小（加速变慢）")
	duel.reel_controls.clear()
	duel.charm_free_reroll = 0   # 还原，避免污染后续测试
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
	# P1.1③：操控唯一由 reel_controls 授予（旧 aim 技艺已迁出）
	duel.reel_controls["snap"] = true
	rd.buffer_enabled = false
	rd.visual_stop = false
	rd.begin_spin()
	rd.target_symbol_path = gold_path
	var strip_ag: Array = [[gold, "none"], [trash, "none"], [trash, "none"]]
	_check(rd.snap_ready(), "落点吸附：本回合次数未用完")
	_check(rd.snap_target_index(1, strip_ag) == 0, "落点吸附：视觉中心 1 时目标 gold 在相邻索引 0")
	var strip_far: Array = [[gold, "none"], [trash, "none"], [trash, "none"], [trash, "none"], [trash, "none"], [trash, "none"], [trash, "none"]]
	_check(rd.snap_target_index(3, strip_far) == -1, "落点吸附：目标距视觉中心超过 ±2 时不吸附")
	rd.consume_snap()
	rd.consume_snap()
	_check(not rd.snap_ready(), "落点吸附：每回合 2 次用尽")
	rd.begin_spin()
	_check(rd.snap_ready(), "落点吸附：下一回合次数重置")

	# —— B方案废铁转化：落点是废铁时 +2 金（不改判、不抵消空转），每回合 1 次 ——
	# 先移除落点吸附，避免它把目标 gold 提前吸附走、干扰废铁判定。
	duel.reel_controls.erase("snap")
	duel.reel_controls["mercy"] = true
	rd.begin_spin()
	rd.target_symbol_path = ""   # 废铁转化不依赖目标符号
	_check(rd.mercy_ready(), "废铁转化：本回合可用")
	var strip_tr: Array = [[trash, "none"], [gold, "none"]]
	rs.reel_strips = [strip_tr]
	rs.reel_cursor.clear()
	rs.reel_cursor.append(0)
	rs.reel_stopped.clear()
	rs.reel_stopped.append(false)
	rs._pending_stops.clear()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	var gold_before_trash: int = duel.gold
	# 视觉中心置 0（非旋转态默认 = cursor），落点为废铁 → 转化 +2 金，落点不变
	rs.lock_reel(0)
	_check(duel.gold == gold_before_trash + rs.TRASH_TO_GOLD, "废铁转化：+2 金")
	_check(rd.mercy_used == 1, "废铁转化：触发并用掉 1 次")
	_check(not rd.mercy_ready(), "废铁转化：每回合 1 次用尽")
	await get_tree().create_timer(0.45).timeout
	_check(rs.reel_stopped[0], "废铁转化：落子完成")

	rd.begin_spin()
	_check(rd.mercy_ready(), "废铁豁免：下一回合次数重置")
	rd.target_symbol_path = backup_target
	rs.reel_strips = backup_strips
	rs.reel_cursor = backup_cursor
	rs.reel_stopped = backup_stopped
	rs._pending_stops.clear()
	g.perk_ids.clear()
	duel.reel_controls.clear()


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


# 2026-11-19：技艺改由 Draft 引擎概率注入三选一，不再有独立"成长位/待选"流程。
# 本测试只验证战后流程能正常进入与结算。
func _test_room_flow_offers_pick(duel: DuelController) -> void:
	_fresh(duel)
	duel.room_index = 0
	duel.in_interroom = false
	var screen = duel.hud.reward_screen
	duel.room_flow.begin_post_battle()
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后结算")
	_check(duel.room_flow.post_battle_phase() == "loot", "战后先展示同层战利品三选一")
	_check(screen.visible, "战利品三选一界面可见")
	_check(screen.reward_grid.get_child_count() == 3, "战利品固定三张同层卡")
	_check(not duel.in_interroom, "战利品结算前不进入房间间歇")
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_reset(duel: DuelController) -> void:
	duel.growth.perk_ids.append("tough")
	duel._reward_system.skill_pity_rooms = 9
	duel._reward_system.skill_offer_guarantee_satisfied = true
	duel.growth.reset_run()
	duel._reward_system.reset_run()
	_check(duel.growth.perk_ids.is_empty(), "新一局：技艺清零")
	_check(duel._reward_system.skill_pity_rooms == 0 and not duel._reward_system.skill_offer_guarantee_satisfied,
		"新一局：保底状态清零")
