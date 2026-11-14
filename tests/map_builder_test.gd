extends Node

# ============================================================================
# 地图巡逻诱导 · Step 2 阶段 1 · MapBoardBuilder 适配层定向回归（2026-11-14）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/map_builder_test.tscn
#
# 目的：证明 14×9 MapGrid 能转成 BoardSystem 可消费的节点图（61 可走格、
# 四方向邻接、16 个战斗节点全部绑定现有 RoomData），且不改动现有运行入口。
#
# 本套只调用 MapBoardBuilder.build()，不调用 BoardSystem.generate()，
# 不加载 board_screen，不写存档，不产生第二套地图模型。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BUILDER := "res://scripts/board/map_board_builder.gd"
const MAP_GRID := "res://scripts/board/map_grid.gd"
const SEED := 20261110

const EXPECTED_WALKABLE := 61
const EXPECTED_CONTENT := 28
const EXPECTED_BATTLE := 16

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPBUILD|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel.board_config.enabled = false

	var builder = load(BUILDER).new(_duel)
	var map = load(MAP_GRID)
	var data: Dictionary = builder.build(1, SEED)

	print("=== A 结构 ===")
	_test_structure(data, map)
	print("=== B 邻接与可达 ===")
	_test_graph(data)
	print("=== C 房间绑定 ===")
	_test_rooms(data)
	print("=== D 固定种子与三幕 ===")
	_test_determinism(builder)
	print("=== E 无旧模型残留 ===")
	_test_no_legacy(data, map)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPBUILD|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_structure(data: Dictionary, map) -> void:
	var nodes: Array = data["nodes"]
	var by_id: Dictionary = data["by_id"]
	var content := 0
	var battle := 0
	var types: Dictionary = {}
	for n in nodes:
		var t := String(n["type"])
		types[t] = int(types.get(t, 0)) + 1
		if t != "path":
			content += 1
		if t in ["battle", "elite", "boss"]:
			battle += 1
	_check(nodes.size() == EXPECTED_WALKABLE, "可走格全部成节点（%d）" % nodes.size())
	_check(by_id.size() == nodes.size(), "by_id 与 nodes 一一对应（%d）" % by_id.size())
	_check(content == EXPECTED_CONTENT, "内容节点 28 个（实际 %d）" % content)
	_check(battle == EXPECTED_BATTLE, "战斗节点 16 个（实际 %d）" % battle)
	_check(int(types.get("battle", 0)) == 12, "battle 12（%d）" % int(types.get("battle", 0)))
	_check(int(types.get("elite", 0)) == 3, "elite 3（%d）" % int(types.get("elite", 0)))
	_check(int(types.get("boss", 0)) == 1, "boss 唯一（%d）" % int(types.get("boss", 0)))
	_check(int(types.get("chest", 0)) + int(types.get("armory", 0)) == 4,
		"宝箱 3 + 藏库 1 = 4（%d）" % (int(types.get("chest", 0)) + int(types.get("armory", 0))))
	_check(int(types.get("shop", 0)) == 1, "shop 1（%d）" % int(types.get("shop", 0)))
	_check(int(types.get("rest", 0)) == 2, "rest 2（%d）" % int(types.get("rest", 0)))
	_check(int(types.get("event", 0)) == 4, "event 4（%d）" % int(types.get("event", 0)))
	_check(int(types.get("start", 0)) == 1, "起点唯一（%d）" % int(types.get("start", 0)))
	_check(int(types.get("path", 0)) == EXPECTED_WALKABLE - EXPECTED_CONTENT,
		"通路格 = 61 - 28 = 33（%d）" % int(types.get("path", 0)))
	_check(by_id.has(data["start_id"]), "start_id 指向真实节点")
	_check(by_id.has(data["boss_id"]), "boss_id 指向真实节点")
	_check(String(by_id[data["boss_id"]]["type"]) == "boss", "boss_id 节点类型为 boss")
	_check(data["battle_rooms"].size() == EXPECTED_BATTLE,
		"battle_rooms 16 个（%d）" % data["battle_rooms"].size())
	_check(data["cols"] == 14 and data["rows"] == 9, "尺寸冻结 14×9")
	_check(map.validate(data["grid"]).is_empty(), "原始 MapGrid 数据通过 validate()")


func _test_graph(data: Dictionary) -> void:
	var nodes: Array = data["nodes"]
	var by_id: Dictionary = data["by_id"]
	var bad_ref := 0
	var bad_sym := 0
	var min_degree := 99
	var max_degree := 0
	for n in nodes:
		var id := String(n["id"])
		var ns: Array = n["next"]
		min_degree = mini(min_degree, ns.size())
		max_degree = maxi(max_degree, ns.size())
		for nx in ns:
			var t: Dictionary = by_id.get(String(nx), {})
			if t.is_empty():
				bad_ref += 1
			elif not (id in (t.get("next", []) as Array)):
				bad_sym += 1
	_check(bad_ref == 0, "所有邻接都指向真实可走格（异常 %d）" % bad_ref)
	_check(bad_sym == 0, "邻接双向对称（异常 %d）" % bad_sym)
	_check(min_degree >= 1, "无孤立格（最小度 %d）" % min_degree)
	_check(max_degree <= 4, "四方向邻接不越界（最大度 %d）" % max_degree)

	# BFS：61 个节点全部从起点可达，BOSS 也在其中。
	var seen: Dictionary = {}
	var stack: Array = [data["start_id"]]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nx in by_id[id]["next"]:
			stack.append(String(nx))
	_check(seen.size() == EXPECTED_WALKABLE, "全图连通（%d / %d）" % [seen.size(), EXPECTED_WALKABLE])
	_check(seen.has(data["boss_id"]), "起点到 BOSS 可达")


func _test_rooms(data: Dictionary) -> void:
	var nodes: Array = data["nodes"]
	var missing := 0
	var mismatch := 0
	var bad_index := 0
	var final_boss_leak := 0
	var idx := 0
	for n in nodes:
		var t := String(n["type"])
		if not (t in ["battle", "elite", "boss"]):
			continue
		var r: RoomData = n.get("room")
		if r == null:
			missing += 1
			continue
		if String(r.kind) != String(n.get("legacy_type", "")):
			mismatch += 1
		if int(n.get("battle_index", -1)) != idx:
			bad_index += 1
		if bool(r.final_boss):
			final_boss_leak += 1
		idx += 1
	_check(missing == 0, "16 个战斗节点全部绑定 RoomData（缺 %d）" % missing)
	_check(mismatch == 0, "房间 kind 与节点 type 一致（异常 %d）" % mismatch)
	_check(bad_index == 0, "battle_index 与 battle_rooms 顺序一致（异常 %d）" % bad_index)
	_check(final_boss_leak == 0, "节奏样板不误用最终 BOSS 房（泄漏 %d）" % final_boss_leak)

	# ACT1 精英 / BOSS 沿用冻结的节奏样板。
	var elite_name := ""
	var boss_name := ""
	for n in nodes:
		if String(n["type"]) == "elite":
			elite_name = String(n["room"].name)
		elif String(n["type"]) == "boss":
			boss_name = String(n["room"].name)
	_check(elite_name == "寒铁精英", "ACT1 精英样板 = 寒铁精英（%s）" % elite_name)
	_check(boss_name == "冰封铁瓮", "ACT1 BOSS 样板 = 冰封铁瓮（%s）" % boss_name)


func _test_determinism(builder) -> void:
	var a: Dictionary = builder.build(1, SEED)
	var b: Dictionary = builder.build(1, SEED)
	_check(_signature(a) == _signature(b), "同 (seed, act) 两次生成完全一致")
	var c: Dictionary = builder.build(1, 20261111)
	_check(_signature(a) != _signature(c), "不同 seed 可区分（房间 / 变体）")
	# 布局、内容、陷阱、巡逻起点不随 seed 变。
	_check(_layout_signature(a) == _layout_signature(c), "地形与内容布局不随 seed 变")
	_check(str(a["grid"]["traps"]) == str(c["grid"]["traps"]), "陷阱位置不随 seed 变")
	_check(str(a["grid"]["patrol_spawns"]) == str(c["grid"]["patrol_spawns"]),
		"巡逻起点不随 seed 变")
	for act in [1, 2, 3]:
		var d: Dictionary = builder.build(act, SEED)
		var missing := 0
		for n in d["nodes"]:
			if String(n["type"]) in ["battle", "elite", "boss"] and n.get("room") == null:
				missing += 1
		_check(missing == 0, "ACT%d 的 16 个战斗节点都有房间（缺 %d）" % [act, missing])
		_check(int(d["act"]) == act, "ACT%d 写进节点" % act)


func _test_no_legacy(data: Dictionary, map) -> void:
	var nodes: Array = data["nodes"]
	var with_number := 0
	var with_dice := 0
	for n in nodes:
		if n.has("number") and int(n["number"]) >= 0:
			with_number += 1
		if n.has("dice"):
			with_dice += 1
	_check(with_number == 0, "节点不含扫雷数字（残留 %d）" % with_number)
	_check(with_dice == 0, "节点不含骰子 / 行动点字段（残留 %d）" % with_dice)
	_check(data["grid"]["cells"].size() == 126, "保留 126 格原始数据供 Step 3/4 读取")
	_check(data["grid"]["traps"].size() == 3, "保留 3 个破甲陷阱位")
	_check(data["grid"]["patrol_spawns"].size() == 3, "保留 3 个巡逻起点")
	_check(map.validate(data["grid"]).is_empty(), "适配不破坏 Step 1 冻结校验")


func _signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data["nodes"]:
		var r: RoomData = n.get("room")
		parts.append("%s:%s:%s:%s" % [String(n["id"]), String(n["type"]),
			str(n.get("variant", -1)), r.resource_path if r != null else ""])
	return "|".join(parts)


func _layout_signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for c in data["grid"]["cells"]:
		parts.append("%s%s" % [String(c["terrain"]), String(c["content"])])
	return "|".join(parts)


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
