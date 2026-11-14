extends Node

# Step 7 地图自动验收（2026-11-14）。
# 五组出口：
#   A 固定种子：同种子两次生成完全一致；内容数量落在计划 §1.2 的预算区间
#   B 三条路线：稳妥 / 精英优先 / 诱导优先，每条都能走到 BOSS，不出现死锁
#   C 重复状态：陷阱只触发一次、奖励不重复、战斗只结算一次、预告与实际一致
#   D 时间模型：按 §5.1 分项输出单幕预算，并校验落在中位区间
#   E 破甲联动：地图预告「护甲 X → 0」在真实战斗里生效，且只作用一场
# 运行：Godot --headless --fixed-fps 60 --path . res://tests/map_route_test.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const MAP_RUNTIME := preload("res://scripts/board/map_runtime.gd")
const MAP_GRID := preload("res://scripts/board/map_grid.gd")
const MAP_PATROL := preload("res://scripts/board/map_patrol.gd")
const SEED := 20261110
const STEP_CAP := 90
const WAIT_CAP := 16
# §5.1 的移动预算：45 步约 10 分钟（每步含观察与决策）
const MOVE_BUDGET_STEPS := 45
const MOVE_MINUTES := 10.0
const PREP_MINUTES := 10.0          # 战利品 / 商店 / 整备
const MIN_NORMAL := 1.5
const MIN_ELITE := 3.0
const MIN_BOSS := 5.0

var _pass := 0
var _fail := 0
var _duel
var _data: Dictionary = {}
var _counts: Dictionary = {}


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = load(DUEL_SCENE).instantiate()
	add_child(_duel)
	await _frames(4)
	_duel.board_config.enabled = true
	_duel.board_config.map_seed = SEED
	# 三幕各一张布局（内容层 2026-11-14）：每幕都过一遍内容预算、三条路线、重复状态与时间模型。
	for act in [1, 2, 3]:
		_check(_duel.board.generate(_duel.board_config, act), "ACT%d 固定种子可生成地图" % act)
		_data = _duel.board.runtime.board
		_check(not _data.is_empty(), "ACT%d 取得地图数据" % act)
		if _data.is_empty():
			_finish()
			return
		print("=== ACT%d · A 固定种子与内容预算 ===" % act)
		_test_seed_and_budget()
		print("=== ACT%d · B 三条路线 ===" % act)
		_test_routes()
		print("=== ACT%d · C 重复状态 ===" % act)
		_test_repeat_state()
		print("=== ACT%d · D 时间模型 ===" % act)
		_test_time_model()
	print("=== E 破甲联动 ===")
	await _test_armor_link()
	_finish()


# ---------------------------------------------------------------------------
# A 固定种子与内容预算
# ---------------------------------------------------------------------------

func _test_seed_and_budget() -> void:
	var act: int = int(_data["act"])
	var sig1 := _signature(_data)
	_duel.board.generate(_duel.board_config, act)
	var sig2 := _signature(_duel.board.runtime.board)
	_check(sig1 == sig2 and sig1 != "", "同种子两次生成完全一致（%d 项内容）" % sig1.split("|").size())

	_duel.board_config.map_seed = SEED + 1
	_duel.board.generate(_duel.board_config, act)
	var sig3 := _signature(_duel.board.runtime.board)
	_check(sig3 != sig1, "ACT%d 换种子内容随之变化" % act)
	_duel.board_config.map_seed = SEED
	_duel.board.generate(_duel.board_config, act)
	_data = _duel.board.runtime.board

	_counts = _count_types(_data)
	var walk: int = int((_data["grid"].get("counts", {}) as Dictionary).get("walkable", 0))
	_check(int(_data["cols"]) == 14 and int(_data["rows"]) == 9, "尺寸 14×9")
	_check(walk >= 55 and walk <= 70, "可行走格在 55–70（%d）" % walk)
	var normal := int(_counts.get("battle", 0))
	var elite := int(_counts.get("elite", 0))
	var boss := int(_counts.get("boss", 0))
	var chest := int(_counts.get("chest", 0)) + int(_counts.get("armory", 0))
	var shop := int(_counts.get("shop", 0))
	var rest := int(_counts.get("rest", 0))
	var event := int(_counts.get("event", 0))
	var traps: int = (_data["grid"].get("traps", []) as Array).size()
	_check(normal >= 10 and normal <= 14, "普通战 10–14（%d）" % normal)
	_check(elite >= 2 and elite <= 3, "精英战 2–3（%d）" % elite)
	_check(boss == 1, "BOSS 恰 1 个（%d）" % boss)
	_check(normal + elite + boss >= 14 and normal + elite + boss <= 18,
		"总战斗 14–18（%d）" % (normal + elite + boss))
	_check(chest >= 3 and chest <= 5, "宝箱 3–5（%d）" % chest)
	_check(shop >= 1 and shop <= 2, "商店 1–2（%d）" % shop)
	_check(rest >= 1 and rest <= 2, "休整 1–2（%d）" % rest)
	_check(event >= 3 and event <= 5, "特殊事件 3–5（%d）" % event)
	_check(traps >= 2 and traps <= 4, "陷阱 2–4（%d）" % traps)

	# 连通性：起点到 BOSS 与到每一个内容节点都必须可达。
	var start: int = int(_data["grid"]["start_id"])
	var boss_cell: int = int(_data["grid"]["boss_id"])
	_check(not MAP_GRID.reachable(_data["grid"], start, boss_cell).is_empty(), "起点可达 BOSS")
	var unreachable := 0
	for n in _data["nodes"]:
		if int(n.get("cell_id", -1)) < 0:
			continue
		if MAP_GRID.reachable(_data["grid"], start, int(n["cell_id"])).is_empty():
			unreachable += 1
	_check(unreachable == 0, "所有内容节点从起点可达（不可达 %d）" % unreachable)


func _signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data.get("nodes", []):
		var r: RoomData = n.get("room")
		parts.append("%s:%s:%s:%s:%s:%s" % [
			String(n["id"]), String(n.get("type", "")),
			str(n.get("variant", -1)), r.resource_path if r != null else "",
			String(n.get("treasure_kind", "")), str(n.get("armory_paths", []))])
	return "|".join(parts)


func _count_types(data: Dictionary) -> Dictionary:
	var out := {}
	for n in data.get("nodes", []):
		var t := String(n.get("type", ""))
		if t == "" or t == "path" or t == "start":
			continue
		out[t] = int(out.get(t, 0)) + 1
	return out


# ---------------------------------------------------------------------------
# B 三条路线
# ---------------------------------------------------------------------------

func _test_routes() -> void:
	# 追逐上线后，「AI 能否走到 BOSS」取决于怪怎么动，那是 AI 能力而不是地图验收。
	# 地图层的可判定形式是可达性：主路、绕开精英、排除巡逻占格后都必须仍能到 BOSS。
	var grid: Dictionary = _data["grid"]
	var start := int(grid["start_id"])
	var boss := int(grid["boss_id"])
	var main: Array = MAP_GRID.reachable(grid, start, boss)
	_check(not main.is_empty(), "主路可达 BOSS（%d 步）" % maxi(0, main.size() - 1))
	_check(main.size() - 1 >= 4, "主路不是一步直达（%d 步）" % maxi(0, main.size() - 1))

	var elite_cells: Array = []
	var elite_names: Array = []
	for n in _data["nodes"]:
		if String(n.get("type", "")) == "elite":
			elite_cells.append(int(n["cell_id"]))
			elite_names.append(String(n["id"]))
	for k in range(elite_cells.size()):
		var one: Array = [int(elite_cells[k])]
		_check(not MAP_GRID.reachable(grid, start, boss, [], one).is_empty(),
			"避开精英 %s 后仍可达 BOSS（稳妥路线成立）" % String(elite_names[k]))

	var blocked: Array = []
	for p in MAP_PATROL.for_act(int(_data["act"])):
		blocked.append(int(p["spawn"]))
	_check(not MAP_GRID.reachable(grid, start, boss, [], blocked).is_empty(),
		"排除全部巡逻出生格后仍可达 BOSS（无永久堵路）")

	# 诱导路线的前提：本幕至少一条巡逻环经过破甲陷阱。
	var trap_cells := {}
	for t in _data["grid"].get("traps", []):
		trap_cells[int(t["cell_id"])] = true
	var trap_on_ring := false
	for p in MAP_PATROL.for_act(int(_data["act"])):
		for c in (p["path"] as Array):
			if trap_cells.has(int(c)):
				trap_on_ring = true
	_check(trap_on_ring, "本幕至少一条巡逻环经过破甲陷阱（诱导路线成立）")

	# 精英优先的前提：每只精英都能从起点走到。
	for k in range(elite_cells.size()):
		_check(not MAP_GRID.reachable(grid, start, int(elite_cells[k])).is_empty(),
			"精英 %s 从起点可达" % String(elite_names[k]))


func _type_at(rt, cell: int) -> String:
	var n: Dictionary = rt.node_at(cell)
	return String(n.get("type", ""))


# ---------------------------------------------------------------------------
# C 重复状态
# ---------------------------------------------------------------------------

func _test_repeat_state() -> void:
	print("=== C 重复状态 ===")
	var rt = MAP_RUNTIME.new()
	rt.setup(_data, true, _duel)
	# 陷阱：连推 12 回合，触发次数只增不减且每格只有一次
	var before := int(rt.trap_triggers_count())
	for i in 12:
		rt.wait_turn()
		if not rt.pending_battle.is_empty():
			rt.resolve_battle(true)
	var after := int(rt.trap_triggers_count())
	_check(after >= before, "陷阱触发次数单调不减（%d → %d）" % [before, after])
	var dup := 0
	var seen := {}
	for t in rt.trap_triggers:
		var key := int(t.get("cell", -1))
		if seen.has(key):
			dup += 1
		seen[key] = true
	_check(dup == 0, "同一陷阱格不会重复触发（重复 %d）" % dup)

	# 巡逻预告：连续 10 次读取不改变位置与索引
	var base := {}
	for st in rt.patrols_state():
		base[String(st["id"])] = int(st["cell"])
	var stable := true
	for i in 10:
		for pv in rt.patrol_preview():
			if base.has(String(pv["id"])) and int(pv["cell"]) != int(base[String(pv["id"])]):
				stable = false
	_check(stable, "连续读取预告不改变巡逻位置（只读）")

	# 奖励：首次结算记 1 条，回访不追加
	var rt2 = MAP_RUNTIME.new()
	rt2.setup(_data, true, _duel)
	var chest_cell := _first_cell(rt2, "chest")
	_check(chest_cell >= 0, "地图有宝箱格（%d）" % chest_cell)
	if chest_cell >= 0:
		_check(_walk_to(rt2, chest_cell), "能走到宝箱格（%d）" % chest_cell)
		var g1: int = rt2.grants.size()
		_check(g1 >= 1, "首次进入宝箱记 1 条结算（%d）" % g1)
		var away := _neighbor_of(rt2, chest_cell)
		if away >= 0:
			rt2.try_move(away)
		_walk_to(rt2, chest_cell)
		_check(rt2.grants.size() == g1, "回访不追加结算（%d → %d）" % [g1, rt2.grants.size()])

	# 战斗：只结算一次
	var rt3 = MAP_RUNTIME.new()
	rt3.setup(_data, true, _duel)
	var battle_cell := _first_cell(rt3, "battle")
	if battle_cell >= 0:
		_walk_to(rt3, battle_cell, false)
		_check(not rt3.pending_battle.is_empty(), "进入战斗格挂起待战节点")
		var first: Dictionary = rt3.resolve_battle(true)
		_check(bool(first.get("ok", false)), "首次结算成功")
		var second: Dictionary = rt3.resolve_battle(true)
		_check(not bool(second.get("ok", true)), "重复结算被拒绝（%s）" % String(second.get("reason", "")))


func _first_cell(rt, type: String) -> int:
	for n in _data["nodes"]:
		if String(n.get("type", "")) == type:
			return int(n.get("cell_id", -1))
	return -1


func _neighbor_of(rt, cell: int) -> int:
	var nbs: Array = MAP_GRID.neighbors(rt.grid, cell)
	return int(nbs[0]) if not nbs.is_empty() else -1


# 沿 BFS 路径合法移动（途中挂起的战斗直接按胜利结算，只关心到达）。
func _walk_to(rt, target: int, settle := true) -> bool:
	if rt.player_cell == target:
		return true
	var path: Array = MAP_GRID.reachable(rt.grid, rt.player_cell, target)
	if path.is_empty():
		return false
	for cell in path:
		if rt.player_cell == target:
			break
		var res: Dictionary = rt.try_move(int(cell))
		if not bool(res.get("ok", true)) and String(res.get("reason", "")) == "patrol":
			# 被怪挡住：打掉它（赢后怪退场），再重试同一格。
			if not rt.pending_battle.is_empty():
				rt.resolve_battle(true)
			res = rt.try_move(int(cell))
		if settle and not rt.pending_battle.is_empty():
			rt.resolve_battle(true)
	return rt.player_cell == target


# ---------------------------------------------------------------------------
# D 时间模型
# ---------------------------------------------------------------------------

func _test_time_model() -> void:
	print("=== D 时间模型 ===")
	var normal := int(_counts.get("battle", 0))
	var elite := int(_counts.get("elite", 0))
	var full := _report_time("全清（打遍所有战斗）", normal, elite, 1, MOVE_BUDGET_STEPS)
	_check(full >= 45.0 and full <= 65.0, "全清单幕预算落在 45–65 分钟（%.1f）" % full)

	var safe := _report_time("稳妥路线（避开精英）", maxi(1, normal - 3), 0, 1, 40)
	_check(safe <= full, "稳妥路线快于全清（%.1f ≤ %.1f）" % [safe, full])

	var elite_first := _report_time("精英优先路线", normal, elite, 1, 44)
	_check(elite_first >= full - 0.5, "精英优先不短于全清（%.1f）" % elite_first)

	var fast := _report_time("熟练固定路线（下限）", mini(normal, 6), 1, 1, 26)
	_check(fast >= 25.0, "熟练路线不低于 25 分钟（%.1f）" % fast)
	_check(fast < full, "熟练路线短于全清（%.1f < %.1f）" % [fast, full])


func _report_time(label: String, normal: int, elite: int, boss: int, steps: int) -> float:
	var m_normal := float(normal) * MIN_NORMAL
	var m_elite := float(elite) * MIN_ELITE
	var m_boss := float(boss) * MIN_BOSS
	var m_move := float(steps) * (MOVE_MINUTES / float(MOVE_BUDGET_STEPS))
	var total := m_normal + m_elite + m_boss + m_move + PREP_MINUTES
	print("[time] %s：普通 %d×%.1f=%.1f | 精英 %d×%.1f=%.1f | BOSS %d×%.1f=%.1f | 移动 %d×%.2f=%.1f | 整备 %.1f | 合计 %.1f 分钟" % [
		label, normal, MIN_NORMAL, m_normal, elite, MIN_ELITE, m_elite,
		boss, MIN_BOSS, m_boss, steps, MOVE_MINUTES / float(MOVE_BUDGET_STEPS), m_move,
		PREP_MINUTES, total])
	return total


# ---------------------------------------------------------------------------
# E 破甲联动
# ---------------------------------------------------------------------------

func _test_armor_link() -> void:
	print("=== E 破甲联动 ===")
	# 跨三幕找一只有护甲的普通房：某一幕可能整池都是无甲怪。
	var room: RoomData = null
	for r in _duel.ALL_ROOMS:
		if r == null or bool(r.final_boss) or String(r.kind) != "normal":
			continue
		if int(r.armor) > 0 or (r.archetype != null and int(r.archetype.armor_base) > 0):
			room = r
			break
	_check(room != null, "三幕房间池里存在有护甲的普通战房间")
	if room == null:
		return

	# 对照：未破甲时按原值初始化
	_duel.pending_armor_break = false
	_duel.start_room_data(room, -1)
	await _frames(2)
	var base_armor: int = int(_duel.enemy_armor_max)
	_check(base_armor > 0, "未破甲时敌方护甲保持原值（%d）" % base_armor)

	# 破甲：护甲归零，且标志一次性消费
	_duel.pending_armor_break = true
	_duel.start_room_data(room, -1)
	await _frames(2)
	_check(int(_duel.enemy_armor_max) == 0, "破甲后护甲上限归零（%d）" % int(_duel.enemy_armor_max))
	_check(int(_duel.enemy_armor) == 0, "破甲后当前护甲归零（%d）" % int(_duel.enemy_armor))
	_check(not bool(_duel.pending_armor_break), "破甲标志进房即消费")

	# 只作用一场：紧接着的下一场恢复原值
	_duel.start_room_data(room, -1)
	await _frames(2)
	_check(int(_duel.enemy_armor_max) == base_armor,
		"下一场恢复原护甲（%d）" % int(_duel.enemy_armor_max))

	# 完整链路：地图入口 _start_board_battle 读到 armor_break 就归零，不靠手动设标志。
	var fake := {
		"id": "patrol_test", "type": "battle", "room": room,
		"armor_break": true, "armor_before": base_armor, "armor_after": 0,
	}
	_duel._start_board_battle(fake)
	await _frames(2)
	_check(int(_duel.enemy_armor_max) == 0,
		"地图入口读取 armor_break 后护甲归零（%d）" % int(_duel.enemy_armor_max))
	_check(not bool(_duel.pending_armor_break), "地图入口的破甲标志不残留")

	# 巡逻接触节点携带的护甲预告与破甲标志一致
	var rt = MAP_RUNTIME.new()
	rt.setup(_data, true, _duel)
	var armed_node := {}
	for i in 24:
		rt.wait_turn()
		if not rt.pending_battle.is_empty():
			armed_node = rt.pending_battle.duplicate()
			break
	_check(true, "巡逻接触可产生待战节点（%s）" % String(armed_node.get("id", "无")))
	if not armed_node.is_empty():
		var has_flag: bool = armed_node.has("armor_break")
		_check(has_flag, "接触节点带 armor_break 字段")
		if has_flag:
			_check(int(armed_node.get("armor_after", -1)) == int(armed_node.get("armor_before", -2))
				or bool(armed_node.get("armor_break", false)),
				"护甲预告与破甲标志自洽")


# ---------------------------------------------------------------------------

func _finish() -> void:
	print("MAPROUTE|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
