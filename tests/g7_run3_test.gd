extends Node

# ============================================================================
# G7-A S4 · 三幕串联 headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g7_run3_test.tscn
#
# 覆盖：
# ① BoardConfig.acts 默认 3（2026-11-08 作者拍板三幕为默认）；单幕回退 = 改回 1，此时 BOSS 节点全部 final；
# ② 三幕：只有第三幕的 BOSS 节点 final，且第三幕四条尾路里恰好 1 个是最终 BOSS；
# ③ advance_act：只换棋盘与幕号——HP/上限/金币/装备/技能/护符/消耗品/成长/技艺/熟练/铭印逐项相等；
# ④ 三幕 bot：每幕 8 战（特殊格替换尾路首战时 7 战）跑通，无软锁、无空节点，
#    第三幕 BOSS 后进入元进度；
# ⑤ 局内记录：act=3、acts 三条、战斗数 = 24 − 特殊格、局末总结带三幕路线。
# 说明：bot 用临时放大的生命与武器强度（只改本局运行时数据，不改 .tres / BALANCE），
#       目的是让 24 场在可控时间内跑完；战斗平衡本身由 m2_board_test 与 S5 基线覆盖。
# 测试在隔离 APPDATA 下运行，不触碰真实存档。
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
	var cfg_was: bool = bool(duel.board_config.enabled)
	var act_was: int = int(duel.board_config.act)
	var acts_was: int = int(duel.board_config.acts)
	var shape_was := String(duel.board_config.shape_id)
	var special_was := String(duel.board_config.special_id)
	var template_was := String(duel.board_config.template_id)
	var dice_was: int = int(duel.board_config.dice_sides)
	var ria_was: int = int(duel.board_config.boss_ria)

	_test_defaults(duel)
	_test_final_flags(duel)
	_test_state_preserved(duel)
	await _test_three_act_run(duel)

	duel.board_config.enabled = cfg_was
	duel.board_config.act = act_was
	duel.board_config.acts = acts_was
	duel.board_config.shape_id = shape_was
	duel.board_config.special_id = special_was
	duel.board_config.template_id = template_was
	duel.board_config.dice_sides = dice_was
	duel.board_config.boss_ria = ria_was
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
	duel.board_config.enabled = false
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


# 固定参数的三幕棋盘局（骨架/特殊格固定，避免随机形状影响断言口径）。
func _build(duel: DuelController, acts: int) -> void:
	duel.board_config.enabled = true
	duel.board_config.act = 1
	duel.board_config.acts = acts
	duel.board_config.dice_sides = 3
	duel.board_config.boss_ria = 7
	duel.board_config.shape_id = "standard"
	duel.board_config.special_id = "treasure"
	duel.board_config.template_id = ""
	duel._loadout_system.full_reset()


func _final_boss_nodes(duel: DuelController) -> Array:
	var out: Array = []
	for id in duel.board.boss_ids:
		var n: Dictionary = duel.board.node_by_id(id)
		if bool(n.get("final", false)):
			out.append(String(id))
	return out


func _final_room_nodes(duel: DuelController) -> Array:
	var out: Array = []
	for id in duel.board.boss_ids:
		var n: Dictionary = duel.board.node_by_id(id)
		var r: RoomData = n.get("room")
		if r != null and r.final_boss:
			out.append(String(id))
	return out


# ---------------------------------------------------------------------------
# ① 默认值
# ---------------------------------------------------------------------------

func _test_defaults(duel: DuelController) -> void:
	_check(not duel.node_mode, "默认线性模式（棋盘开关关闭）")
	_check(int(duel.board_config.acts) == 3, "BoardConfig.acts 默认 3（三幕；单幕回退改回 1）")
	duel.board_config.acts = 1
	_check(duel.run_act_count() == 1, "单幕局 run_act_count = 1（%d）" % duel.run_act_count())


# ---------------------------------------------------------------------------
# ② 最终标记：只有最后一幕的 BOSS 结束整局
# ---------------------------------------------------------------------------

func _test_final_flags(duel: DuelController) -> void:
	seed(7411)
	_build(duel, 1)
	_check(duel.node_mode, "单幕：进入棋盘模式")
	_check(duel.board.act == 1, "单幕：棋盘在 ACT I")
	_check(_final_boss_nodes(duel).size() == 4, "单幕：4 个 BOSS 节点都标记 final（%d）" % _final_boss_nodes(duel).size())
	duel.board_config.act = 1
	duel._start_board_battle(duel.board.node_by_id(String(duel.board.boss_ids[0])))
	_check(duel.run_final, "单幕：进入任一 BOSS 节点即 run_final")
	duel.board.return_to_board()

	seed(7412)
	_build(duel, 3)
	_check(duel.run_act_count() == 3, "三幕：run_act_count = 3")
	_check(duel.board.act == 1, "三幕：首张棋盘在 ACT I")
	_check(_final_boss_nodes(duel).is_empty(), "ACT I 的 BOSS 节点不结束整局（%d）" % _final_boss_nodes(duel).size())
	_check(_final_room_nodes(duel).is_empty(), "ACT I 不含最终 BOSS 房")
	var sizes: Array[int] = [duel.ROOMS.size()]
	var acts_at: Array[int] = [duel.board.act]
	var finals_at: Array[int] = []
	var final_rooms_at: Array[int] = []
	var rooms_ok := true
	for i in range(2):
		var ok: bool = duel.advance_act()
		_check(ok, "advance_act 进入第 %d 幕" % (i + 2))
		if duel.ROOMS.size() != duel.board.battle_rooms.size() or duel.ROOMS.is_empty():
			rooms_ok = false
		sizes.append(duel.ROOMS.size())
		acts_at.append(duel.board.act)
		finals_at.append(_final_boss_nodes(duel).size())
		final_rooms_at.append(_final_room_nodes(duel).size())
	_check(acts_at == [1, 2, 3], "逐幕推进：棋盘幕号 %s" % str(acts_at))
	_check(finals_at == [0, 4], "ACT II 无 final、ACT III 4 个 final（%s）" % str(finals_at))
	_check(final_rooms_at == [0, 1], "只有 ACT III 含唯一最终 BOSS 房（%s）" % str(final_rooms_at))
	_check(duel.current_act == 3, "current_act 随幕推进到 3（%d）" % duel.current_act)
	_check(not duel.run_final, "幕间不残留 run_final")
	_check(duel.board.act_summaries.size() == 2, "已完成两幕的快照（%d）" % duel.board.act_summaries.size())
	_check(int(duel.board.act_summaries[0].get("act", 0)) == 1
		and int(duel.board.act_summaries[1].get("act", 0)) == 2, "快照按幕顺序记录 ACT I / ACT II")
	_check(rooms_ok, "每次换幕后 ROOMS 都按新棋盘重建且非空（%s）" % str(sizes))
	_check(not duel.advance_act(), "第三幕之后没有第四幕（advance_act = false）")
	duel.board.return_to_board()


# ---------------------------------------------------------------------------
# ③ 幕间不重置：状态逐项相等
# ---------------------------------------------------------------------------

func _state(duel: DuelController) -> Dictionary:
	return {
		"hp": duel.player_hp,
		"hp_max": duel.player_hp_max,
		"gold": duel.gold,
		"loadout": duel.selected_loadout.duplicate(),
		"skills": duel.selected_skills.duplicate(),
		"charms": duel.selected_charms.duplicate(),
		"consumables": duel.selected_consumables.duplicate(),
		"slots": duel.consumable_slots.duplicate(),
		"level": duel.growth.level,
		"xp": duel.growth.xp,
		"perks": duel.growth.perk_ids.duplicate(),
		"perk_picks": duel.growth.pending_picks,
		"mastery": duel.mastery.mastery.duplicate(true),
		"imprints": _loadout_imprints(duel),
		"shop_paid": duel._shop_system.paid_price.duplicate(true),
	}


# 只比对本局已装备武器的铭印：Mastery 的读取器会为「被读到的武器」建空条目，
# 那属于读副作用，不是幕间重置。
func _loadout_imprints(duel: DuelController) -> Dictionary:
	var out := {}
	for p in duel.selected_loadout:
		out[String(p)] = duel.mastery.imprints.get(String(p), {}).duplicate(true)
	return out


func _test_state_preserved(duel: DuelController) -> void:
	seed(7413)
	_build(duel, 3)
	# 造一组「不可能是开局默认值」的局内状态，便于逐项比对。
	duel.player_hp_max = 137
	duel.player_hp = 77
	duel.gold = 42
	duel.growth.xp = 11
	duel.growth.level = 3
	if not duel.growth.perk_ids.has("regen"):
		duel.growth.perk_ids.append("regen")
	duel.growth.pending_picks = 1
	var wp := String(duel.selected_loadout[0])
	duel.mastery.mastery[wp] = 5
	duel.mastery.imprints[wp] = {"forge": 1, "tune": {}, "calibrate": 0, "tyrant": 0}
	# consumable_slots 是 Array[Dictionary]：[{path, item_id, charges, uid}]（见 _board_treasure_active）。
	if duel.consumable_slots.is_empty():
		duel.consumable_slots.append({"path": "res://resources/consumables/heal_potion.tres",
			"item_id": "heal_potion", "charges": 1, "uid": "ctest"})

	var before: Dictionary = _state(duel)
	var rooms_before: int = duel.ROOMS.size()
	var ok: bool = duel.advance_act()
	var after: Dictionary = _state(duel)
	_check(ok, "幕间推进成功")
	_check(duel.board.act == 2, "推进后第二幕（act=%d）" % duel.board.act)
	_check(duel.board.act_label() == "ACT II", "幕名随幕切换（%s）" % duel.board.act_label())
	var diffs: Array[String] = []
	for k in before:
		if str(before[k]) != str(after[k]):
			diffs.append("%s %s→%s" % [k, str(before[k]), str(after[k])])
	_check(diffs.is_empty(), "幕间不重置：HP/金币/装备/成长/熟练/铭印逐项相等%s" % ("" if diffs.is_empty() else "：" + ", ".join(diffs)))
	_check(duel.player_hp == 77 and duel.player_hp_max == 137, "幕间 HP 保持 77/137（%d/%d）" % [duel.player_hp, duel.player_hp_max])
	_check(duel.gold == 42, "幕间金币保持 42（%d）" % duel.gold)
	_check(duel.ROOMS.size() == duel.board.battle_rooms.size(), "ROOMS 与第二幕棋盘战斗房同步（%d / %d）" % [duel.ROOMS.size(), duel.board.battle_rooms.size()])
	_check(duel.ROOMS.size() != rooms_before or rooms_before == duel.board.battle_rooms.size(), "ROOMS 已按新棋盘重建（%d → %d）" % [rooms_before, duel.ROOMS.size()])
	_check(duel.board.current_id == String(duel.board.current_node().get("id", "")) and not duel.board.consumed.is_empty(),
		"新棋盘从起点重新计数（当前 %s）" % duel.board.current_id)
	_check(duel.game_state == DuelController.FlowState.PLAYING, "幕间转场恢复 PLAYING（避免停在 WON）")
	_check(duel.hud.board_screen.visible, "幕间转场直接展示新棋盘")


# ---------------------------------------------------------------------------
# ④ 三幕 bot：3 幕 × 8 战
# ---------------------------------------------------------------------------

func _test_three_act_run(duel: DuelController) -> void:
	seed(20261108)
	_build(duel, 3)
	duel.player_hp_max = 1000000
	duel.player_hp = 1000000
	duel.game_state = DuelController.FlowState.PLAYING

	var terminal := ""
	var battles := 0
	var specials := 0
	var moves := 0
	var acts_seen := {}
	var guard := 0
	while guard < 4000:
		guard += 1
		acts_seen[int(duel.board.act) if duel.board != null else 1] = true
		if duel.game_state == DuelController.FlowState.LOST:
			terminal = "LOST"
			break
		if duel.game_state == DuelController.FlowState.WON:
			if duel.room_flow.post_battle_active and duel.room_flow.post_battle_has_growth():
				duel.room_flow.auto_pick_post_battle(["growth"])
			else:
				duel._on_reward_skip_pressed()
			await get_tree().process_frame
			if duel.hud.meta_screen.visible:
				terminal = "WON_GAME"
				break
			continue
		if duel.hud.board_screen.visible:
			var b = duel.board
			if b.dice == 0:
				b.roll_dice()
			var legal: Array = b.legal_targets()
			if legal.is_empty():
				_check(false, "三幕：棋盘待机时存在合法落点（ACT%d %s）" % [b.act, b.current_id])
				terminal = "NO_LEGAL"
				break
			var pick: Dictionary = legal[randi() % legal.size()]
			var node: Dictionary = b.advance_to(String(pick["id"]))
			if node.is_empty():
				_check(false, "三幕：合法落点 advance 成功")
				terminal = "ADVANCE_FAIL"
				break
			moves += 1
			var t := String(node.get("type", ""))
			duel._on_board_node_entered(node)
			if t in ["normal", "elite", "boss"] and not duel.hud.board_screen.visible:
				battles += 1
				_boost_weapons(duel)
			elif t in ["treasure", "shrine", "armory"]:
				specials += 1   # 特殊格替换一条尾路的首战 → 该幕 7 战而不是 8 战
			await get_tree().process_frame
			if duel.hud._camp_dialog != null and duel.hud._camp_dialog.visible:
				duel._camp_leave()
			if duel.hud.shop_screen_is_open():
				duel._on_shop_leave_pressed()
			if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
				duel.hud._on_replace_cancelled()
			continue
		if duel.game_state != DuelController.FlowState.PLAYING:
			continue
		var turn := await _play_one_turn(duel)
		if turn != "OK":
			terminal = turn
			break

	_check(terminal == "WON_GAME", "三幕跑通至元进度（terminal=%s，移动 %d 步，战斗 %d 场）" % [terminal, moves, battles])
	_check(acts_seen.size() == 3 and acts_seen.has(1) and acts_seen.has(2) and acts_seen.has(3),
		"真实经过 ACT I / II / III（%s）" % str(acts_seen.keys()))
	# 每幕 8 战；特殊格会替换掉一条尾路的首战，所以实际 = 24 − 走过的特殊格。
	_check(specials <= 3 and battles == 24 - specials,
		"三幕战斗 = 24 − 特殊格（%d 战 / %d 特殊格）" % [battles, specials])
	_check(duel.board.act_summaries.size() == 2, "幕间快照两条（%d）" % duel.board.act_summaries.size())
	_check(duel.board.current_is_boss(), "最终停在第三幕某个 BOSS 节点（%s）" % duel.board.current_id)
	_check(duel.board.visited_count() == duel.board.route_length(),
		"第三幕走满 %d 格（%d）" % [duel.board.route_length(), duel.board.visited_count()])
	_check(duel.growth.level == 6, "三幕跑完等级 = 6（%d，历练 %d）" % [duel.growth.level, duel.growth.xp])
	_check(duel.growth.perk_ids.size() == 3, "三幕跑完技艺 = 3（%d）" % duel.growth.perk_ids.size())

	var j = duel._journal
	if j != null:
		var d: Dictionary = j._data
		_check(int(d.get("act", 0)) == 3, "局内记录 act = 3（%d）" % int(d.get("act", 0)))
		_check((d.get("acts", []) as Array).size() == 3, "局内记录按幕 3 条（%d）" % (d.get("acts", []) as Array).size())
		_check((d.get("battles", []) as Array).size() == 24 - specials,
			"局内记录战斗 %d 场（%d）" % [24 - specials, (d.get("battles", []) as Array).size()])
		var act_ids: Array = []
		for a in d.get("acts", []):
			act_ids.append(int(a.get("act", 0)))
		_check(act_ids == [1, 2, 3], "记录幕号顺序 %s" % str(act_ids))
	else:
		_check(false, "局内记录已实例化")

	var line: String = duel._run_summary.route_line()
	_check(line.contains("ACT I") and line.contains("ACT II") and line.contains("ACT III"),
		"局末总结显示三幕路线（%s）" % line)

	duel.hud.hide_meta_screen()
	duel.game_state = DuelController.FlowState.PLAYING


# 本套只验证三幕串联与状态延续，不验证战斗长度：每场开打后把武器强度临时放大 40 倍，
# 让 24 场在可控回合内结束。只改本局运行时的 map（下一房重建池时自然还原），不动 .tres / BALANCE。
func _boost_weapons(duel: DuelController) -> void:
	for k in duel._weapon_power_map:
		duel._weapon_power_map[k] = float(duel._weapon_power_map[k]) * 40.0


func _play_one_turn(duel: DuelController) -> String:
	duel._on_spin_pressed()
	var waited := 0
	while waited < 900:
		if duel.reel_system.spinning:
			duel._on_spin_button_pressed()
		elif not duel._busy:
			return "OK"
		waited += 1
		await get_tree().process_frame
	return "TURN_TIMEOUT"
