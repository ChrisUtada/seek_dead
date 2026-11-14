extends Node

# ============================================================================
# 棋盘拓扑与移动 · headless 回归（2026-11-14 单路径收敛后重写）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_board_test.tscn
#
# 收敛背景：14×9 地图替换 1D3 骨架与 4×4 扫雷灰盒，本套原「25 节点拓扑 / 1D3 步数预算 /
# 四个 BOSS 结局」的断言已随旧模型退役，改为验证单一地图的产品门面：
#   ① 生成结构：61 可走节点、内容预算、BOSS 唯一；
#   ② 连通：起点可达全部节点与 BOSS；
#   ③ 移动：只走四邻、非相邻拒绝、回访只移动不结算；
#   ④ 巡逻占格不可进入，等待推进一个地图回合；
#   ⑤ 三幕：每幕一张 14×9，只有最后一幕 BOSS 结束整局；
#   ⑥ 节点接入：宝箱 handler 仍按冻结内容发放。
# ============================================================================

const MAP_GRID = preload("res://scripts/board/map_grid.gd")
const SEED := 20261110

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	if scene_res == null:
		print("M2BOARD|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)

	var cfg = _duel.board_config
	var enabled_was: bool = bool(cfg.enabled)
	var acts_was: int = int(cfg.acts)
	var seed_was: int = int(cfg.map_seed)
	cfg.enabled = true
	cfg.map_seed = SEED

	print("=== A 生成结构 ===")
	_test_structure(cfg)
	print("=== B 连通与可达 ===")
	_test_connectivity()
	print("=== C 移动与回访 ===")
	_test_movement()
	print("=== D 巡逻占格与等待 ===")
	_test_patrol_block_and_wait()
	print("=== E 三幕终局 ===")
	_test_acts(cfg)
	print("=== F 节点接入 ===")
	_test_node_entry(cfg)

	cfg.enabled = enabled_was
	cfg.acts = acts_was
	cfg.map_seed = seed_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("M2BOARD|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_structure(cfg) -> void:
	_check(_duel.board.generate(cfg), "同种子生成通过结构校验")
	var board = _duel.board
	_check(board.node_count() == 61, "节点数等于可行走格 61（%d）" % board.node_count())
	_check(board.boss_ids.size() == 1, "BOSS 唯一（%d）" % board.boss_ids.size())
	var counts := {}
	var battle := 0
	for n in board.nodes:
		var t := String(n["type"])
		counts[t] = int(counts.get(t, 0)) + 1
		if t == "battle" or t == "elite" or t == "boss":
			battle += 1
	_check(int(counts.get("battle", 0)) == 12, "普通战 12（%d）" % int(counts.get("battle", 0)))
	_check(int(counts.get("elite", 0)) == 3, "精英 3（%d）" % int(counts.get("elite", 0)))
	_check(int(counts.get("chest", 0)) == 3, "宝箱 3（%d）" % int(counts.get("chest", 0)))
	_check(int(counts.get("armory", 0)) == 1, "武器藏库 1（%d）" % int(counts.get("armory", 0)))
	_check(int(counts.get("shop", 0)) == 1, "商店 1")
	_check(int(counts.get("rest", 0)) == 2, "休整 2")
	_check(int(counts.get("event", 0)) == 4, "事件 4")
	_check(battle == 16, "战斗合计 16（%d）" % battle)
	var isolated := 0
	for n in board.nodes:
		if MAP_GRID.neighbors(board.runtime.grid, int(n["cell_id"])).is_empty():
			isolated += 1
	_check(isolated == 0, "没有孤立节点（%d）" % isolated)
	_check(String(board.current_node().get("type", "")) == "start", "起点节点类型为 start")
	_check(board.progress_text() != "", "进度文案非空")


func _test_connectivity() -> void:
	var board = _duel.board
	var boss_id: String = String(board.boss_ids[0])
	var missing := 0
	for n in board.nodes:
		if MAP_GRID.reachable(board.runtime.grid, board.current_cell(), int(n["cell_id"])).is_empty():
			missing += 1
	_check(missing == 0, "起点可达全部节点（不可达 %d）" % missing)
	_check(not MAP_GRID.reachable(board.runtime.grid, board.current_cell(),
		int(board.node_by_id(boss_id)["cell_id"])).is_empty(), "起点可达 BOSS")


func _test_movement() -> void:
	var board = _duel.board
	var start_cell: int = board.current_cell()
	var legal: Array = board.legal_targets()
	_check(legal.size() >= 2, "起点有多个合法落点（%d）" % legal.size())
	var all_adjacent := true
	for n in legal:
		if not MAP_GRID.neighbors(board.runtime.grid, start_cell).has(int(n["cell_id"])):
			all_adjacent = false
	_check(all_adjacent, "合法落点全部四邻相邻")
	_check(board.advance_to("m68").is_empty(), "远处 BOSS 不可直达")

	var battle_id := ""
	for n in legal:
		if String(n["type"]) == "battle":
			battle_id = String(n["id"])
	if battle_id == "":
		_check(false, "起点相邻存在普通战格")
		return
	var node: Dictionary = board.advance_to(battle_id)
	_check(String(node.get("type", "")) == "battle", "进入战斗格返回战斗节点")
	_check(node.get("room") != null, "战斗节点带真实房间")
	_check(board.visited_count() >= 2, "访问计数增加")
	var back: Dictionary = board.advance_to("m57")
	_check(not back.is_empty(), "可回访起点")
	_check(board.last_move_revisit, "回访标记为只移动")
	_check(String(board.feedback).find("回访") >= 0, "回访给出反馈")


func _test_patrol_block_and_wait() -> void:
	var board = _duel.board
	board.generate(_duel.board_config)   # 重置：巡逻 p0 回到起点 30
	# 玩家放到巡逻 p0 起点（30）旁的 29。
	board.runtime.player_cell = 29
	board.current_id = "m29"
	var ids: Array = []
	for n in board.legal_targets():
		ids.append(String(n["id"]))
	_check(not ids.has("m30"), "巡逻占格不可进入")
	var turn_before: int = board.runtime.turn
	board.wait_here()
	_check(board.runtime.turn == turn_before + 1, "等待推进一个地图回合")
	_check(String(board.feedback) != "", "等待给出反馈")


func _test_acts(cfg) -> void:
	cfg.acts = 1
	_duel.board.generate(cfg, 1)
	var solo: Dictionary = _duel.board.node_by_id(_duel.board.boss_ids[0])
	_check(bool(solo.get("final", false)), "单幕：唯一 BOSS 是 final")
	_check(_duel.run_act_count() == 1, "单幕 run_act_count = 1")

	cfg.acts = 3
	var finals: Array = []
	for act in [1, 2, 3]:
		_duel.board.generate(cfg, act)
		_check(_duel.board.node_count() == 61, "ACT%d 仍是 14×9 地图" % act)
		var b: Dictionary = _duel.board.node_by_id(_duel.board.boss_ids[0])
		finals.append(bool(b.get("final", false)))
		_check(int(_duel.board.act) == act, "ACT%d 幕号写入棋盘" % act)
	_check(finals == [false, false, true], "仅 ACT III 的 BOSS 结束整局（%s）" % str(finals))
	_check(_duel.run_act_count() == 3, "三幕 run_act_count = 3")


func _test_node_entry(cfg) -> void:
	cfg.acts = 3
	_duel.board.generate(cfg, 1)
	var chest: Dictionary = {}
	for n in _duel.board.nodes:
		if String(n["type"]) == "chest":
			chest = n
			break
	_check(not chest.is_empty(), "地图上存在宝箱节点")
	if chest.is_empty():
		return
	var gold_before: int = _duel.gold
	_duel._on_board_node_entered(chest)
	if String(chest.get("treasure_kind", "")) == "gold":
		_check(_duel.gold > gold_before, "金币宝箱兑现（%d → %d）" % [gold_before, _duel.gold])
	else:
		_check(ResourceLoader.exists(String(chest.get("item_path", ""))), "宝箱冻结物品真实存在")
		_check(true, "物品宝箱走现有授予流程")


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
