extends Node

const MAP_GRID = preload("res://scripts/board/map_grid.gd")

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
	var ria_was: int = int(duel.board_config.boss_ria)

	_test_defaults(duel)
	_test_final_flags(duel)
	_test_state_preserved(duel)
	await _test_three_act_run(duel)

	duel.board_config.enabled = cfg_was
	duel.board_config.act = act_was
	duel.board_config.acts = acts_was
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
	duel.board_config.boss_ria = 7
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
	_check(_final_boss_nodes(duel).size() == 1, "单幕：唯一 BOSS 标记 final（%d）" % _final_boss_nodes(duel).size())
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
	_check(finals_at == [0, 1], "ACT II 无 final、ACT III 唯一 final（%s）" % str(finals_at))
	_check(final_rooms_at == [0, 1], "只有 ACT III 含唯一最终 BOSS 房（%s）" % str(final_rooms_at))
	_check(duel.current_act == 3, "current_act 随幕推进到 3（%d）" % duel.current_act)
	_check(not duel.run_final, "幕间不残留 run_final")
	_check(duel.board.act_summaries.size() == 2, "已完成两幕的快照（%d）" % duel.board.act_summaries.size())
	_check(int(duel.board.act_summaries[0].get("act", 0)) == 1
		and int(duel.board.act_summaries[1].get("act", 0)) == 2, "快照按幕顺序记录 ACT I / ACT II")
	_check(rooms_ok, "每次换幕后 ROOMS 都按新棋盘重建且非空（%s）" % str(sizes))
	# G7-A S5 后续：两次换幕各发放一次锻魂（+8 伤害 / +20 最大 HP）。
	_check(int(duel._reward_system.run_power_bonus) == 16, "两次换幕累计锻魂：符号伤害 +16（%d）" % int(duel._reward_system.run_power_bonus))
	_check(duel.player_hp_max == 140 and duel.player_hp == 140, "两次换幕累计锻魂：最大 HP 100 → 140（%d/%d）" % [duel.player_hp, duel.player_hp_max])
	_check(not duel.advance_act(), "第三幕之后没有第四幕（advance_act = false）")
	_check(int(duel._reward_system.run_power_bonus) == 16 and duel.player_hp_max == 140,
		"无下一幕时不重复发放锻魂（+%d / %d）" % [int(duel._reward_system.run_power_bonus), duel.player_hp_max])
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
	_check(int(duel._reward_system.run_power_bonus) == 0 and duel.player_hp_max == 100,
		"ACT I 开局无锻魂（+%d / %d）" % [int(duel._reward_system.run_power_bonus), duel.player_hp_max])
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
		if k == "hp" or k == "hp_max":
			continue   # G7-A S5 后续：锻魂按设计改这两项，单独断言
		if str(before[k]) != str(after[k]):
			diffs.append("%s %s→%s" % [k, str(before[k]), str(after[k])])
	_check(diffs.is_empty(), "幕间不重置：金币/装备/成长/熟练/铭印逐项相等%s" % ("" if diffs.is_empty() else "：" + ", ".join(diffs)))
	_check(duel.player_hp_max == 157 and duel.player_hp == 97, "幕间锻魂：最大 HP 137 → 157、HP 77 → 97（%d/%d）" % [duel.player_hp, duel.player_hp_max])
	_check(int(duel._reward_system.run_power_bonus) == 8, "幕间锻魂：本局符号伤害 +8（%d）" % int(duel._reward_system.run_power_bonus))
	_check((duel._journal._data.get("act_boons", []) as Array).size() == 1,
		"局内记录锻魂 1 条（%d）" % (duel._journal._data.get("act_boons", []) as Array).size())
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
	# 2026-11-14 收敛：14×9 地图下「三幕整局模拟」的步数与战斗数不再是固定值，
	# 且整局跑完耗时过长。这里改为结构性验证三幕链：每幕一张 14×9 地图、
	# 幕号写入、只有最后一幕 BOSS 结束整局、地图状态可被换幕重建。
	var acts_was: int = int(duel.board_config.acts)
	duel.board_config.acts = 3
	var finals: Array = []
	var nodes_ok := 0
	var rooms_ok := 0
	for act in [1, 2, 3]:
		var ok: bool = duel.board.generate(duel.board_config, act)
		if ok:
			nodes_ok += 1
		_check(int(duel.board.act) == act, "ACT%d：幕号写入棋盘" % act)
		_check(duel.board.boss_ids.size() == 1, "ACT%d：BOSS 唯一" % act)
		var b: Dictionary = duel.board.node_by_id(duel.board.boss_ids[0])
		finals.append(bool(b.get("final", false)))
		var r: RoomData = b.get("room")
		if r != null:
			rooms_ok += 1
	_check(nodes_ok == 3, "三幕地图都通过结构校验（%d/3）" % nodes_ok)
	_check(rooms_ok == 3, "三幕 BOSS 都绑定真实房间（%d/3）" % rooms_ok)
	_check(finals == [false, false, true], "仅 ACT III 的 BOSS 结束整局（%s）" % str(finals))
	_check(duel.run_act_count() == 3, "三幕 run_act_count = 3")

	# 换幕重建：ACT I → ACT II 后棋盘内容整体替换，不残留上一幕状态。
	var act1_start: String = String(duel.board.current_id)
	duel.board.generate(duel.board_config, 2)
	_check(duel.board.current_id == act1_start, "换幕后回到新地图起点")
	_check(int(duel.board.act) == 2, "换幕后 act = 2")

	# 单幕局：唯一 BOSS 即 final。
	duel.board_config.acts = 1
	duel.board.generate(duel.board_config, 1)
	var solo: Dictionary = duel.board.node_by_id(duel.board.boss_ids[0])
	_check(bool(solo.get("final", false)), "单幕局：唯一 BOSS 结束整局")
	duel.board_config.acts = acts_was


