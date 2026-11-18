extends Node

# 分岔路线图（DAG）数据层定向回归（2026-11-18，L2-A）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/branch_map_test.tscn
# 只测 MapBoardBuilder.build_branch()，不加载 board_screen / runtime，不写存档。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BUILDER := "res://scripts/board/map_board_builder.gd"
const SEED := 20261110

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL  %s" % label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("BRANCHMAP|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel.board_config.enabled = false

	var builder = load(BUILDER).new(_duel)
	var map: Dictionary = builder.build_branch(1, SEED, 1)
	var nodes: Array = map.get("nodes", [])
	var by_id: Dictionary = map.get("by_id", {})

	_check(nodes.size() >= 13 and nodes.size() <= 17, "node count in [13,17] (got %d)" % nodes.size())
	_check(map.get("branch") == true, "branch flag set")
	_check(String(map.get("start_id", "")).begins_with("b0_"), "start id")
	_check(String(map.get("boss_id", "")).begins_with("b6_"), "boss id")

	# 层间连通：每个节点的 next 只指向下一层
	var bad_edge := 0
	for n in nodes:
		var layer := int(String(n["id"]).substr(1, 1))
		for nid in n["next"]:
			var nlayer := int(String(nid).substr(1, 1))
			if nlayer != layer + 1:
				bad_edge += 1
	_check(bad_edge == 0, "all edges go layer→layer+1 (bad=%d)" % bad_edge)

	# 每个非 BOSS 节点都有出边；每个非起点节点都有入边（全连通）
	var no_out := 0
	var incoming: Dictionary = {}
	for n in nodes:
		if int(String(n["id"]).substr(1, 1)) < 6 and (n["next"] as Array).is_empty():
			no_out += 1
		for nid in n["next"]:
			incoming[nid] = true
	var no_in := 0
	for n in nodes:
		if n["id"] == map["start_id"]:
			continue
		if not incoming.has(n["id"]):
			no_in += 1
	_check(no_out == 0, "all non-boss nodes have out-edge (bad=%d)" % no_out)
	_check(no_in == 0, "all non-start nodes have in-edge (bad=%d)" % no_in)

	# BOSS 唯一且绑定 RoomData
	var boss_count := 0
	var boss_node: Dictionary = {}
	for n in nodes:
		if String(n["type"]) == "boss":
			boss_count += 1
			boss_node = n
	_check(boss_count == 1, "exactly one boss (got %d)" % boss_count)
	_check(boss_node.get("room") != null, "boss has RoomData")
	if boss_node.get("room") != null:
		_check(String(boss_node["room"].kind) == "boss", "boss room kind=boss")
		_check(not bool(boss_node["room"].final_boss), "act1 boss not final_boss")

	# 战斗节点全部绑定房间；内容节点有 source
	var battle_no_room := 0
	var content_no_source := 0
	for n in nodes:
		if String(n["type"]) in ["battle", "elite"] and n.get("room") == null:
			battle_no_room += 1
		if String(n["type"]) in ["chest", "armory", "shop", "rest", "event"] and String(n.get("source", "")).is_empty():
			content_no_source += 1
	_check(battle_no_room == 0, "all battle/elite nodes have room (bad=%d)" % battle_no_room)
	_check(content_no_source == 0, "all content nodes have source (bad=%d)" % content_no_source)

	# 战斗房列表与战斗节点数一致
	var battle_nodes := 0
	for n in nodes:
		if String(n["type"]) in ["battle", "elite", "boss"]:
			battle_nodes += 1
	_check((map.get("battle_rooms", []) as Array).size() == battle_nodes,
		"battle_rooms size matches (got %d vs %d)" % [(map.get("battle_rooms", []) as Array).size(), battle_nodes])

	# 确定性：同 seed 两次生成结构一致
	var map2: Dictionary = builder.build_branch(1, SEED, 1)
	var ids1: Array = []
	var ids2: Array = []
	for n in nodes:
		ids1.append("%s:%s" % [n["id"], n["type"]])
	for n in map2["nodes"]:
		ids2.append("%s:%s" % [n["id"], n["type"]])
	_check(ids1 == ids2, "same seed → same structure")

	# BoardSystem 门面：branch_mode=true 时应委托 BranchRuntime，可沿边走到 BOSS
	_duel.board_config.branch_mode = true
	var ok_gen: bool = _duel.board.generate(_duel.board_config)
	_check(ok_gen, "board.generate ok in branch mode")
	_check(_duel.board.branch_mode, "board.branch_mode set")
	_check(_duel.board.current_id == "b0_0", "starts at b0_0")
	# 逐层沿第一条合法边前进，直到 BOSS
	var steps := 0
	while steps < 10 and not _duel.board.current_is_boss():
		var targets: Array = _duel.board.legal_targets()
		if targets.is_empty():
			break
		var next_node: Dictionary = targets[0]
		var res: Dictionary = _duel.board.advance_to(String(next_node["id"]))
		_check(not res.is_empty() and String(res.get("id", "")) == String(next_node["id"]), "advance to %s ok" % next_node["id"])
		steps += 1
	_check(_duel.board.current_is_boss(), "reached BOSS in %d steps" % steps)
	_check(_duel.board.visited_count() == 7, "visited 7 nodes (got %d)" % _duel.board.visited_count())
	# 分岔图不能回访：起点不可再进
	var back: Dictionary = _duel.board.advance_to("b0_0")
	_check(back.is_empty(), "cannot go back to start")
	_duel.board_config.branch_mode = false

	_duel.free()
	print("BRANCHMAP|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 2)
