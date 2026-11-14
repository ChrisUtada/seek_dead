extends Node

# ============================================================================
# 地图巡逻诱导 · Step 3 · 巡逻与下一步预告定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §3.3 巡逻规则、§6 Step 3 任务 1–5 与出口
#
# 覆盖四条出口：
#   1) 预告位置与实际行动位置 100% 一致；
#   2) 多只怪物行动顺序固定；
#   3) 巡逻不穿墙、不越界、不永久堵死 BOSS；
#   4) 同一地图种子和输入序列得到完全一致结果。
# 以及 §3.3 的占格 / 接触 / 不扣血 / 查看不影响巡逻。
#
# 只使用开发／AI 测试入口（MapRuntime with_patrols），不接产品默认入口，
# 不改 board_system / board_screen / board_config，不退役任何旧测试。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const MAP_GRID := preload("res://scripts/board/map_grid.gd")
const MAP_PATROL := preload("res://scripts/board/map_patrol.gd")
const RUNTIME := preload("res://scripts/board/map_runtime.gd")

const SEED := 20261110

# LAYOUT 固定坐标。
const START := 57
const PATH_DOWN := 71
const EVENT_A := 43
const BOSS := 68
const WALL := 56

# 巡逻冻结坐标。
const P0_SPAWN := 30
const P0_NEIGHBOR := 29    # 与 P0 起点相邻的空地
const P0_NEXT := 31        # P0 第一回合的下一格

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPPATROL|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)

	var cfg = _duel.board_config
	var dev_was: bool = bool(cfg.map_dev_override)
	cfg.map_dev_override = true

	print("=== A 巡逻结构与冻结路径 ===")
	_test_structure()
	print("=== B 预告与实际行动一致 ===")
	_test_preview_consistency()
	print("=== C 占格阻挡与撞击接触 ===")
	_test_block_and_bump()
	print("=== D 怪物追上玩家 ===")
	_test_chase_contact()
	print("=== E 多只行动顺序固定 ===")
	_test_action_order()
	print("=== F 同种子同输入完全一致 ===")
	_test_determinism()
	print("=== G 不穿墙、不越界、不永久堵死 BOSS ===")
	_test_no_block_boss()
	print("=== H 查看与取消不影响巡逻 ===")
	_test_read_only()
	print("=== I 存档恢复含巡逻 ===")
	_test_save_restore()

	cfg.map_dev_override = dev_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPPATROL|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _rt(seed_value: int = SEED):
	return RUNTIME.create(_duel, 1, seed_value, 1, true)


# ---------------------------------------------------------------------------
# A 结构与冻结路径
# ---------------------------------------------------------------------------

func _test_structure() -> void:
	var rt = _rt()
	_check(rt.patrol_enabled, "巡逻在开发入口下启用")
	_check(rt.patrols.size() == 3, "巡逻共 3 只（%d）" % rt.patrols.size())

	var grid: Dictionary = rt.grid
	var errs: Array = MAP_PATROL.validate(grid)
	_check(errs.is_empty(), "路径校验无错误（%s）" % str(errs.slice(0, 3)))

	var state: Array = rt.patrols_state()
	_check(int(state[0]["order"]) == 0 and int(state[1]["order"]) == 1 and int(state[2]["order"]) == 2,
		"巡逻 order 依次为 0/1/2")
	var spawns: Array = grid["patrol_spawns"]
	for i in range(3):
		_check(int(state[i]["cell"]) == int(spawns[i]),
			"%s 初始位置等于冻结起点 %d" % [String(state[i]["id"]), int(spawns[i])])
		_check(String(state[i]["region"]) == ("A" if i == 0 else "C"),
			"%s 落在区域 %s" % [String(state[i]["id"]), String(state[i]["region"])])

	var region_a := 0
	var region_c := 0
	for p in state:
		if String(p["region"]) == "A":
			region_a += 1
		elif String(p["region"]) == "C":
			region_c += 1
	_check(region_a == 1, "入口区 A 恰好 1 只（%d）" % region_a)
	_check(region_c == 2, "深层区 C 恰好 2 只（%d）" % region_c)

	var cells: Array = grid["cells"]
	var doors: Array = grid["doors"]
	for cfg in MAP_PATROL.PATROLS:
		var path: Array = cfg["path"]
		var pid := String(cfg["id"])
		_check(path.size() >= 3, "%s 路径至少 3 格（%d）" % [pid, path.size()])
		_check(int(path[0]) == int(cfg["spawn"]), "%s 路径首格是起点" % pid)
		var uniq: Dictionary = {}
		var all_walk := true
		var touches_boss := false
		var touches_start := false
		var touches_door := false
		for raw in path:
			var cid: int = int(raw)
			uniq[cid] = true
			if not bool(cells[cid]["walkable"]):
				all_walk = false
			if cid == BOSS:
				touches_boss = true
			if cid == START:
				touches_start = true
			if doors.has(cid):
				touches_door = true
		_check(all_walk, "%s 路径全部可行走（不穿墙）" % pid)
		_check(uniq.size() == path.size(), "%s 路径无重复格（简单环）" % pid)
		_check(not touches_boss, "%s 路径不经过 BOSS 格" % pid)
		_check(not touches_start, "%s 路径不经过起点格" % pid)
		_check(not touches_door, "%s 路径不经过区域门" % pid)
		var closed := true
		for j in range(path.size()):
			var a: int = int(path[j])
			var b: int = int(path[(j + 1) % path.size()])
			if not MAP_GRID.neighbors(grid, a).has(b):
				closed = false
		_check(closed, "%s 路径可闭合循环" % pid)
		var region_ok := true
		for raw in path:
			if String(cells[int(raw)]["region"]) != String(cfg["region"]):
				region_ok = false
		_check(region_ok, "%s 路径不跨区域" % pid)

	# 房间绑定来自现有池且确定性。
	var rooms: Array = []
	for p in rt.patrols:
		rooms.append(String(p.get("room_path", "")))
	_check(rooms[0] != "" and rooms[1] != "" and rooms[2] != "",
		"三只巡逻都绑定现有房间（%s）" % str(rooms))
	var again = _rt()
	var rooms2: Array = []
	for p in again.patrols:
		rooms2.append(String(p.get("room_path", "")))
	_check(rooms == rooms2, "同幕两次构建绑定同一批房间（确定性）")
	var unique_rooms: Dictionary = {}
	for r in rooms:
		unique_rooms[r] = true
	_check(unique_rooms.size() == 3, "三只巡逻绑定不同房间（%d）" % unique_rooms.size())


# ---------------------------------------------------------------------------
# B 预告与实际行动一致
# ---------------------------------------------------------------------------

func _test_preview_consistency() -> void:
	var rt = _rt()
	var mismatch := 0
	var checked := 0
	var preview: Array = rt.patrol_preview()
	_check(preview.size() == 3, "预告覆盖 3 只（%d）" % preview.size())
	for i in range(12):
		preview = rt.patrol_preview()
		var before: Array = rt.patrols_state()
		if i % 2 == 0:
			rt.wait_turn()
		else:
			var target: int = PATH_DOWN if rt.player_cell == START else START
			rt.try_move(target)
		var after: Array = rt.patrols_state()
		for k in range(preview.size()):
			var pid := String(preview[k]["id"])
			var expect := int(preview[k]["next"])
			var actual := -1
			for st in after:
				if String(st["id"]) == pid:
					actual = int(st["cell"])
			checked += 1
			if actual != expect:
				mismatch += 1
				print("  预告不符：%s 预期 %d 实际 %d（第 %d 回合）" % [pid, expect, actual, i])
	_check(mismatch == 0, "12 回合 %d 次预告全部与实际一致" % checked)

	# 预告是纯只读：连续调用不改变任何状态。
	var rt2 = _rt()
	var sig: String = rt2.signature()
	for i in range(10):
		rt2.patrol_preview()
	_check(rt2.signature() == sig, "连续 10 次预告不改变状态")
	var idx_before: int = int(rt2.patrols_state()[0]["path_index"])
	rt2.patrol_preview()
	_check(int(rt2.patrols_state()[0]["path_index"]) == idx_before, "预告不推进路径索引")


# ---------------------------------------------------------------------------
# C 占格阻挡与撞击接触
# ---------------------------------------------------------------------------

func _test_block_and_bump() -> void:
	var rt = _rt()
	rt.player_cell = P0_NEIGHBOR
	var blocked: Dictionary = rt.can_move(P0_SPAWN)
	_check(not bool(blocked["ok"]), "被巡逻占据的格不可进入")
	_check(String(blocked["reason"]) == "patrol", "阻挡原因是 patrol（%s）" % String(blocked["reason"]))

	var sig: String = rt.signature()
	var bump: Dictionary = rt.try_move(P0_SPAWN)
	_check(not bool(bump["ok"]), "撞击被判定为未移动")
	_check(String(bump["reason"]) == "patrol", "撞击返回 patrol 原因")
	_check(rt.player_cell == P0_NEIGHBOR, "撞击后玩家仍在原格")
	_check(rt.turn == 0, "撞击不推进地图回合")
	_check(rt.visits.get(P0_SPAWN, 0) == 0, "撞击不计入目标格访问")
	var contact: Dictionary = bump["contact"]
	_check(String(contact.get("patrol", "")) == "p0", "撞击对象是 p0")
	_check(not rt.pending_battle.is_empty(), "撞击后挂起待战节点")
	_check(String(rt.pending_battle.get("kind", "")) == "patrol", "待战节点类型为 patrol")
	_check(String(rt.pending_battle.get("source", "")) == "patrol", "待战节点来源为 patrol")
	_check(rt.pending_battle.get("room") != null, "待战节点带真实房间资源")
	_check(rt.pending_battle.get("room") == rt.patrols[0].get("room"), "待战房间就是该巡逻怪的房间")
	_check(rt.consumed.is_empty() and rt.settled_log.is_empty(), "接触不结算任何地图内容（不额外扣血/发奖）")
	_check(rt.signature() != sig, "接触记录已写入状态指纹")

	rt.resolve_contact(true)
	_check(rt.pending_battle.is_empty(), "战斗返回后待战节点清空")
	_check(not bool(rt.patrols[0]["active"]), "击败后该巡逻怪退场")
	var now_ok: Dictionary = rt.can_move(P0_SPAWN)
	_check(bool(now_ok["ok"]), "击败后该格可正常进入")
	_check(String(now_ok["reason"]) == "ok", "进入原巡逻格不再报 patrol")
	var move_in: Dictionary = rt.try_move(P0_SPAWN)
	_check(bool(move_in["ok"]) and rt.player_cell == P0_SPAWN, "击败后可以走进该格")


# ---------------------------------------------------------------------------
# D 怪物追上玩家
# ---------------------------------------------------------------------------

func _test_chase_contact() -> void:
	var rt = _rt()
	rt.player_cell = P0_NEXT
	var w: Dictionary = rt.wait_turn()
	var contact: Dictionary = w["contact"]
	_check(not contact.is_empty(), "等待后巡逻怪走到玩家格触发接触")
	_check(String(contact.get("patrol", "")) == "p0", "接触对象为 p0")
	_check(int(rt.patrols[0]["cell"]) == P0_NEXT, "p0 已移动到预告格 %d" % P0_NEXT)
	_check(rt.player_cell == P0_NEXT, "玩家位置不变（怪物撞上来）")
	_check(rt.turn == 1, "等待推进一个回合")
	_check(int(w["advanced"]) == 1, "接触回合只推进一次")
	_check(rt.contacts.size() == 1, "接触流水 1 条")
	_check(int(rt.contacts[0]["turn"]) == 1, "接触记录写在第 1 回合")
	_check(not rt.pending_battle.is_empty(), "追上后挂起待战节点")


# ---------------------------------------------------------------------------
# E 多只行动顺序固定
# ---------------------------------------------------------------------------

func _test_action_order() -> void:
	var rt = _rt()
	var before: Array = rt.patrols_state()
	rt.wait_turn()
	var after: Array = rt.patrols_state()
	_check(after.size() == 3, "行动后仍是 3 只")
	for i in range(3):
		_check(String(after[i]["id"]) == String(before[i]["id"]),
			"第 %d 位始终是 %s（顺序不随机）" % [i, String(after[i]["id"])])
		_check(int(after[i]["order"]) == i, "%s order 不变" % String(after[i]["id"]))
		var path: Array = rt.patrols[i]["path"]
		var expect: int = int(path[1 % path.size()])
		_check(int(after[i]["cell"]) == expect,
			"%s 第一回合前进到路径第 2 格（%d）" % [String(after[i]["id"]), expect])
	# 再推进一轮，路径索引 +1。
	rt.wait_turn()
	var thirds: Array = rt.patrols_state()
	for i in range(3):
		var path: Array = rt.patrols[i]["path"]
		_check(int(thirds[i]["path_index"]) == 2, "%s 索引到 2" % String(thirds[i]["id"]))
		_check(int(thirds[i]["cell"]) == int(path[2 % path.size()]), "%s 位于路径第 3 格" % String(thirds[i]["id"]))


# ---------------------------------------------------------------------------
# F 同种子同输入完全一致
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var a = _rt()
	var b = _rt()
	var seq := [START, PATH_DOWN, START, EVENT_A, START]
	for cell in seq:
		a.wait_turn()
		b.wait_turn()
		a.try_move(int(cell))
		b.try_move(int(cell))
	_check(a.signature() == b.signature(), "同种子同输入后状态指纹完全一致")
	var sa: Array = a.patrols_state()
	var sb: Array = b.patrols_state()
	var same := true
	for i in range(sa.size()):
		if int(sa[i]["cell"]) != int(sb[i]["cell"]) or int(sa[i]["path_index"]) != int(sb[i]["path_index"]):
			same = false
	_check(same, "三只巡逻位置与索引完全一致")
	var ra: Array = []
	var rb: Array = []
	for p in a.patrols:
		ra.append(String(p.get("room_path", "")))
	for p in b.patrols:
		rb.append(String(p.get("room_path", "")))
	_check(ra == rb, "同种子绑定同一批巡逻怪资源")

	# 换种子：巡逻路径与起始位置不变（冻结）。
	var a0 = _rt()
	var c = _rt(SEED + 1)
	var s0: Array = a0.patrols_state()
	var sc: Array = c.patrols_state()
	var path_same := true
	for i in range(sc.size()):
		if int(sc[i]["cell"]) != int(s0[i]["cell"]) or int(sc[i]["path_index"]) != int(s0[i]["path_index"]):
			path_same = false
		var pa: Array = a0.patrols[i]["path"]
		var pc: Array = c.patrols[i]["path"]
		if pa != pc:
			path_same = false
	_check(path_same, "换种子不改变巡逻路径与起始位置")
	var errs: Array = MAP_PATROL.validate(c.grid)
	_check(errs.is_empty(), "换种子后路径校验仍无错误")


# ---------------------------------------------------------------------------
# G 不穿墙、不越界、不永久堵死 BOSS
# ---------------------------------------------------------------------------

func _test_no_block_boss() -> void:
	var rt = _rt()
	var bad_wall := 0
	var out_of_range := 0
	var blocked_turns := 0
	for i in range(20):
		if i % 2 == 0:
			rt.wait_turn()
		else:
			rt.try_move(PATH_DOWN if rt.player_cell == START else START)
		for p in rt.patrols_state():
			var cid: int = int(p["cell"])
			if cid < 0 or cid >= rt.cols * rt.rows:
				out_of_range += 1
			elif not rt.is_walkable(cid):
				bad_wall += 1
		if rt.reachable_avoiding_patrols(BOSS).is_empty():
			blocked_turns += 1
	_check(bad_wall == 0, "20 回合内巡逻从不穿墙（%d）" % bad_wall)
	_check(out_of_range == 0, "20 回合内巡逻从不越界（%d）" % out_of_range)
	_check(blocked_turns == 0, "20 回合内 BOSS 始终可达（堵死回合 %d）" % blocked_turns)
	_check(not rt.reachable_avoiding_patrols(BOSS).is_empty(), "最终仍存在避开巡逻的 BOSS 路径")
	# 结构保证：BOSS 格与两道门都不在任何巡逻路径上。
	var structural := true
	for cfg in MAP_PATROL.PATROLS:
		if (cfg["path"] as Array).has(BOSS) or (cfg["path"] as Array).has(START):
			structural = false
	_check(structural, "结构上巡逻不占用起点 / BOSS 格")


# ---------------------------------------------------------------------------
# H 查看与取消不影响巡逻
# ---------------------------------------------------------------------------

func _test_read_only() -> void:
	var rt = _rt()
	var sig: String = rt.signature()
	var state_before: String = str(rt.patrols_state())
	rt.view(P0_SPAWN)
	rt.view(BOSS)
	rt.view_build()
	rt.cancel()
	rt.cancel()
	_check(rt.signature() == sig, "查看与取消不改变含巡逻的状态指纹")
	_check(str(rt.patrols_state()) == state_before, "查看与取消不改变巡逻位置")
	_check(rt.turn == 0, "查看与取消不推进回合")
	_check(rt.contacts.is_empty(), "查看与取消不产生接触")
	# 重开界面＝重建运行时：同种子得到同一批巡逻。
	var again = _rt()
	_check(str(again.patrols_state()) == state_before, "重开界面后巡逻回到同一起点与索引")


# ---------------------------------------------------------------------------
# I 存档恢复含巡逻
# ---------------------------------------------------------------------------

func _test_save_restore() -> void:
	var rt = _rt()
	rt.wait_turn()
	rt.try_move(PATH_DOWN)
	rt.wait_turn()
	var saved: Dictionary = rt.to_dict()
	_check(bool(saved.get("patrol_enabled", false)), "存档记录巡逻开关")
	_check((saved["patrols"] as Array).size() == 3, "存档记录 3 只巡逻")
	_check(int(saved["patrols"][0]["path_index"]) == int(rt.patrols[0]["path_index"]),
		"存档记录路径索引")

	var parsed = JSON.parse_string(JSON.stringify(saved))
	_check(parsed is Dictionary, "含巡逻的存档可 JSON 往返")
	var restored = _rt()
	_check(restored.from_dict(parsed), "含巡逻的存档可恢复")
	_check(restored.signature() == rt.signature(), "恢复后含巡逻的状态指纹一致")
	_check(int(restored.patrols[0]["cell"]) == int(rt.patrols[0]["cell"]), "恢复后巡逻位置一致")

	# 恢复后继续输入与未中断一致。
	for i in range(4):
		rt.wait_turn()
		restored.wait_turn()
	_check(restored.signature() == rt.signature(), "恢复后继续推进结果一致")

	# 巡逻开关不一致的存档被拒。
	var plain = RUNTIME.create(_duel, 1, SEED, 1, false)
	_check(not plain.from_dict(saved), "巡逻关闭的运行时拒绝含巡逻的存档")
	var plain_save: Dictionary = plain.to_dict()
	_check(not _rt().from_dict(plain_save), "巡逻开启的运行时拒绝不含巡逻的存档")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_fails += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
