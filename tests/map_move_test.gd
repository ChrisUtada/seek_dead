extends Node

# ============================================================================
# 地图巡逻诱导 · Step 2 · 移动／等待／回访／镜头定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §2.2 地图操作、§4.1 镜头、§4.3 操作栏、§6 Step 2 出口
#
# 覆盖六条出口：
#   1) 非相邻格不移动；        2) 等待只推进一次；
#   3) 回访不重复结算；        4) 查看与取消不改变 RNG / 内容；
#   5) 镜头和按钮在 480×270 下不越界；
#   6) 正式入口在 Step 5A 完成前保持关闭。
#
# 本套只使用开发／AI 测试入口（MapRuntime），不接产品默认入口，
# 不改 board_system / board_screen / board_config，不退役任何旧测试。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const MAP_GRID := preload("res://scripts/board/map_grid.gd")
const RUNTIME := preload("res://scripts/board/map_runtime.gd")

const SEED := 20261110
const VIEWPORT := Vector2i(480, 270)

# LAYOUT 固定坐标（cell_id = col + row*14）。
const START := 57        # row4 col1
const EVENT_A := 43      # row3 col1（V 事件，紧邻起点）
const PATH_UP := 71      # row5 col1（通路）
const BATTLE := 58       # row4 col2（普通战）
const WALL := 56         # row4 col0（墙）
const DIAGONAL := 44      # row3 col2（斜向，非四邻）
const BOSS := 68         # row4 col12
const TOP_LEFT := 15     # row1 col1
const BOTTOM_RIGHT := 110 # row7 col12
const CHEST := 20        # row1 col6（宝箱，非 armory）

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPMOVE|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)

	var cfg = _duel.board_config
	var dev_was: bool = bool(cfg.map_dev_override)
	cfg.map_dev_override = true

	print("=== A 相邻移动与非法输入 ===")
	_test_move_adjacency()
	print("=== B 等待 ===")
	_test_wait()
	print("=== C 回访不重复结算 ===")
	_test_revisit()
	print("=== D 查看与取消无副作用 ===")
	_test_read_only()
	print("=== E 镜头窗口与像素映射 ===")
	_test_camera()
	print("=== F 底部操作栏布局 ===")
	_test_action_bar()
	print("=== G 存档恢复 ===")
	_test_save_restore()
	print("=== H 正式入口关闭与旧开关 ===")
	_test_entry_gate(cfg)

	cfg.map_dev_override = dev_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPMOVE|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------------------
# A 相邻移动与非法输入
# ---------------------------------------------------------------------------

func _test_move_adjacency() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	_check(rt.player_cell == START, "初始位置在起点（%d）" % rt.player_cell)
	_check(rt.turn == 0, "初始回合为 0")
	_check(MAP_GRID.ascii_map(rt.grid).split("\n")[4].substr(1, 1) == "S",
		"网格 ASCII 起点与冻结布局一致")

	_check(bool(rt.can_move(EVENT_A)["ok"]), "北邻格可移动")
	_check(String(rt.can_move(DIAGONAL)["reason"]) == "not_adjacent", "斜向格判定为非相邻")
	_check(String(rt.can_move(BOSS)["reason"]) == "not_adjacent", "远处 BOSS 判定为非相邻")
	_check(String(rt.can_move(WALL)["reason"]) == "blocked", "墙格判定为不可进入")
	_check(String(rt.can_move(999)["reason"]) == "out_of_range", "越界格判定为超范围")
	_check(String(rt.can_move(START)["reason"]) == "same_cell", "原地判定为同格")

	# 非法移动不改状态。
	var sig_before: String = rt.signature()
	for bad in [DIAGONAL, BOSS, WALL, 999, -1, START]:
		var r: Dictionary = rt.try_move(int(bad))
		_check(not bool(r["ok"]), "非法目标 %d 被拒绝（%s）" % [int(bad), String(r["reason"])])
	_check(rt.signature() == sig_before, "六次非法移动后状态指纹完全不变")
	_check(rt.turn == 0, "非法移动不推进回合")
	_check(rt.consumed.is_empty(), "非法移动不结算任何内容")

	# 合法移动：一格一回合。
	var ok_move: Dictionary = rt.try_move(PATH_UP)
	_check(bool(ok_move["ok"]), "相邻通路格移动成功")
	_check(rt.player_cell == PATH_UP, "位置更新为目标格")
	_check(rt.turn == 1, "移动一格只推进一个回合（%d）" % rt.turn)
	_check(int(rt.visits.get(PATH_UP, 0)) == 1, "访问计数 +1")
	_check(rt.patrol_ticks == 1, "巡逻钩子与回合推进同步（%d）" % rt.patrol_ticks)


# ---------------------------------------------------------------------------
# B 等待
# ---------------------------------------------------------------------------

func _test_wait() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	var consumed_before: int = rt.consumed.size()
	var fp_before: String = rt.content_fingerprint()
	var w1: Dictionary = rt.wait_turn()
	_check(int(w1["advanced"]) == 1, "等待只推进一个回合（%d）" % int(w1["advanced"]))
	_check(rt.turn == 1, "等待后回合为 1")
	_check(rt.player_cell == START, "等待不改变坐标")
	_check(rt.consumed.size() == consumed_before, "等待不结算内容")
	_check(rt.content_fingerprint() == fp_before, "等待不重抽地图内容")
	var base: int = rt.turn
	for i in range(3):
		rt.wait_turn()
	_check(rt.turn == base + 3, "连续三次等待推进三回合（%d）" % (rt.turn - base))
	_check(rt.patrol_ticks == rt.turn, "巡逻钩子次数等于回合推进次数")
	_check(rt.player_cell == START, "连续等待仍在原地")


# ---------------------------------------------------------------------------
# C 回访不重复结算
# ---------------------------------------------------------------------------

func _test_revisit() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	var fp_before: String = rt.content_fingerprint()

	# 首次进入事件格 → 结算一次。
	var first: Dictionary = rt.try_move(EVENT_A)
	var settled: Dictionary = first["settled"]
	_check(String(settled.get("kind", "")) == "settle",
		"首次进入事件格触发结算（%s）" % String(settled.get("kind", "")))
	_check(String(settled.get("source", "")) == "event", "事件格来源为 event")
	_check(rt.is_consumed(EVENT_A), "事件格被标记为已消耗")
	_check(rt.settled_log.size() == 1, "结算流水只有 1 条")
	var shrine_kind := String(settled["node"].get("shrine_kind", ""))
	_check(shrine_kind != "", "事件格带独立配置（%s）" % shrine_kind)

	# 回起点再回访 → 只移动。
	rt.try_move(START)
	var back: Dictionary = rt.try_move(EVENT_A)
	_check(String(back["settled"].get("kind", "")) == "revisit", "回访判定为 revisit")
	_check(rt.settled_log.size() == 1, "回访不追加结算流水")
	_check(int(rt.visits.get(EVENT_A, 0)) == 2, "回访仍计入访问次数（%d）" % int(rt.visits.get(EVENT_A, 0)))
	_check(String(back["settled"]["node"].get("shrine_kind", "")) == shrine_kind,
		"回访看到的事件内容与首次一致")

	# 第三次回访仍不结算。
	rt.try_move(START)
	var third: Dictionary = rt.try_move(EVENT_A)
	_check(String(third["settled"].get("kind", "")) == "revisit", "第三次回访仍是 revisit")
	_check(rt.settled_log.size() == 1, "三次进入只结算一次")

	# 宝箱：真实来源、只发一次、回访不重发。
	var rt2 = RUNTIME.create(_duel, 1, SEED, 1)
	_check(_walk(rt2, CHEST), "可沿合法路径走到宝箱格（%d）" % CHEST)
	_check(rt2.is_consumed(CHEST), "宝箱格进入后被标记已消耗")
	var chest_logs: Array = []
	for entry in rt2.settled_log:
		if int(entry["cell"]) == CHEST:
			chest_logs.append(entry)
	_check(chest_logs.size() == 1, "宝箱结算流水 1 条（%d）" % chest_logs.size())
	var chest_node: Dictionary = rt2.node_at(CHEST)
	_check(String(chest_node.get("type", "")) == "chest", "宝箱节点类型为 chest")
	_check(String(chest_node.get("source", "")) == "chest", "宝箱来源为 chest")
	var chest_kind := String(chest_node.get("treasure_kind", ""))
	_check(chest_kind != "", "宝箱带 treasure_kind（%s）" % chest_kind)
	var chest_settles: int = _log_count(rt2, CHEST)
	_check(chest_settles == 1, "宝箱结算流水 1 条（%d）" % chest_settles)
	var away: Array = MAP_GRID.neighbors(rt2.grid, CHEST)
	if not away.is_empty():
		rt2.try_move(int(away[0]))
	_walk(rt2, CHEST)
	_check(_log_count(rt2, CHEST) == chest_settles, "宝箱回访不追加结算")
	_check(rt2.is_consumed(CHEST), "宝箱回访后仍是已消耗")

	# 战斗格：只记录遭遇，不发固定奖励。
	var rt3 = RUNTIME.create(_duel, 1, SEED, 1)
	var battle_move: Dictionary = rt3.try_move(BATTLE)
	_check(String(battle_move["settled"].get("kind", "")) == "battle", "普通战格判定为 battle")
	_check(not rt3.pending_battle.is_empty(), "战斗格挂起待进入战斗")
	var taken: Dictionary = rt3.take_pending_battle()
	_check(not taken.is_empty() and rt3.pending_battle.is_empty(), "待战节点可被取走且只取一次")
	_check(String(taken.get("type", "")) == "battle", "取走的节点类型为 battle")
	_check(int(rt3.encounters.get(BATTLE, 0)) == 1, "战斗遭遇计数为 1")
	_check(not rt3.is_consumed(BATTLE), "战斗格不写入探索消耗表")

	# 通路与起点不结算。
	var rt4 = RUNTIME.create(_duel, 1, SEED, 1)
	var path_move: Dictionary = rt4.try_move(PATH_UP)
	_check(path_move["settled"].is_empty(), "通路格不产生结算")
	var tab_back: Dictionary = rt4.try_move(START)
	_check(tab_back["settled"].is_empty(), "起点格不产生结算")
	_check(rt4.settled_log.is_empty(), "通路与起点不写结算流水")

	_check(rt.content_fingerprint() == fp_before, "整段回访后内容指纹不变")


# ---------------------------------------------------------------------------
# D 查看与取消无副作用
# ---------------------------------------------------------------------------

func _test_read_only() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	var rt_ref = RUNTIME.create(_duel, 1, SEED, 1)
	var ascii_before: String = MAP_GRID.ascii_map(rt.grid)
	var fp_before: String = rt.content_fingerprint()
	var sig_before: String = rt.signature()

	var info: Dictionary = rt.view(CHEST)
	_check(String(info.get("type", "")) == "chest", "查看返回目标真实类型")
	_check(String(info.get("source", "")) == "chest", "查看返回真实来源")
	_check(bool(info.get("walkable", false)), "查看返回可行走标记")
	_check(not bool(info.get("adjacent", true)), "远处目标标记为不可直达")

	var build: Dictionary = rt.view_build()
	_check(build.has("note"), "查看构筑返回只读快照")

	var c: Dictionary = rt.cancel()
	_check(bool(c["ok"]), "取消操作返回成功")
	rt.view(BOSS)
	rt.view(START)
	rt.cancel()

	_check(rt.signature() == sig_before, "查看与取消后状态指纹不变")
	_check(rt.content_fingerprint() == fp_before, "查看与取消后内容指纹不变（未重抽）")
	_check(MAP_GRID.ascii_map(rt.grid) == ascii_before, "查看与取消后布局 ASCII 不变")
	_check(rt.turn == 0, "查看与取消不推进回合")
	_check(rt.player_cell == START && rt_ref.player_cell == START, "查看与取消不改变坐标")

	# 对照：查看过的与没查看过的，后续同序列输入结果完全一致。
	# 序列均为四邻可达：起点→事件→起点→下通路→起点→普通战。
	var seq := [EVENT_A, START, PATH_UP, START, BATTLE]
	for cell in seq:
		_check(bool(rt.try_move(int(cell))["ok"]), "对照序列移动 %d 合法" % int(cell))
		rt.take_pending_battle()
		rt_ref.try_move(int(cell))
		rt_ref.take_pending_battle()
	_check(rt.signature() == rt_ref.signature(), "查看过的运行时与对照运行时状态一致")
	_check(rt.content_fingerprint() == rt_ref.content_fingerprint(), "两者内容指纹一致")
	_check(rt.turn == seq.size(), "五步移动推进五回合（%d）" % rt.turn)


# ---------------------------------------------------------------------------
# E 镜头窗口与像素映射
# ---------------------------------------------------------------------------

func _test_camera() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	_check(rt.VIEW_COLS == 9 and rt.VIEW_ROWS == 7, "视口窗口为 9×7")
	_check(rt.VIEW_COLS < rt.cols and rt.VIEW_ROWS < rt.rows,
		"窗口小于 14×9，不整图入屏（%d×%d）" % [rt.cols, rt.rows])

	var cases := [
		[START, "起点"],
		[BOSS, "BOSS"],
		[TOP_LEFT, "左上角"],
		[BOTTOM_RIGHT, "右下角"],
	]
	for item in cases:
		rt.player_cell = int(item[0])
		var rect: Rect2i = rt.camera_cells()
		var pc: int = rt.player_cell % rt.cols
		var pr: int = rt.player_cell / rt.cols
		_check(rect.has_point(Vector2i(pc, pr)),
			"%s格在镜头窗口内（%s）" % [String(item[1]), str(rect)])
		_check(rect.position.x >= 0 and rect.position.y >= 0, "%s窗口原点不为负" % String(item[1]))
		_check(rect.position.x + rect.size.x <= rt.cols, "%s窗口不越右边界" % String(item[1]))
		_check(rect.position.y + rect.size.y <= rt.rows, "%s窗口不越下边界" % String(item[1]))

	# 四角钳制。
	rt.player_cell = TOP_LEFT
	_check(rt.camera_origin() == Vector2i(0, 0), "左上角镜头钳制到 (0,0)")
	rt.player_cell = BOTTOM_RIGHT
	_check(rt.camera_origin() == Vector2i(rt.cols - rt.VIEW_COLS, rt.rows - rt.VIEW_ROWS),
		"右下角镜头钳制到最大原点")

	# 像素映射在 480×270 内。
	rt.player_cell = START
	var area: Rect2i = rt.map_area()
	var px: Rect2i = rt.camera_pixels()
	_check(area.encloses(px), "镜头像素矩形完全落在地图区内（%s ⊂ %s）" % [str(px), str(area)])
	_check(rt.TILE_SIZE >= 24, "格子像素 %d ≥ 24，能容纳图标与箭头" % rt.TILE_SIZE)
	_check(px.size.x == rt.VIEW_COLS * rt.TILE_SIZE and px.size.y == rt.VIEW_ROWS * rt.TILE_SIZE,
		"像素尺寸等于窗口格数 × 格子尺寸")
	var cell_px: Vector2i = rt.cell_pixels(START)
	_check(px.has_point(cell_px), "玩家所在格像素原点在镜头矩形内")
	var panel: Rect2i = rt.panel_rect()
	_check(not px.intersects(panel), "镜头矩形不与右侧信息栏重叠")
	_check(panel.position.x + panel.size.x == VIEWPORT.x, "信息栏贴齐右边界")
	_check(area.position.x + area.size.x <= panel.position.x, "地图区不进入信息栏")


# ---------------------------------------------------------------------------
# F 底部操作栏布局
# ---------------------------------------------------------------------------

func _test_action_bar() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	var rects: Array = rt.action_bar_rects()
	_check(rects.size() == 4, "操作栏 4 个按钮（%d）" % rects.size())
	_check(rt.ACTIONS == ["move", "wait", "build", "withdraw"], "操作顺序为 移动/等待/查看构筑/撤回整备")
	var screen := Rect2i(Vector2i.ZERO, VIEWPORT)
	var all_in := true
	for r in rects:
		if not screen.encloses(r):
			all_in = false
	_check(all_in, "四个按钮都在 480×270 视口内")
	var overlap := false
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2i).intersects(rects[j] as Rect2i):
				overlap = true
	_check(not overlap, "按钮彼此不重叠")
	var panel: Rect2i = rt.panel_rect()
	var hit_panel := false
	for r in rects:
		if (r as Rect2i).intersects(panel):
			hit_panel = true
	_check(not hit_panel, "按钮不与信息栏重叠")
	_check(rects[0].position.y + rects[0].size.y <= VIEWPORT.y, "按钮不越下边界")
	_check(String(rt.ACTION_LABELS["wait"]).find("回合") >= 0, "等待文案写明会推进回合")


# ---------------------------------------------------------------------------
# G 存档恢复
# ---------------------------------------------------------------------------

func _test_save_restore() -> void:
	var rt = RUNTIME.create(_duel, 1, SEED, 1)
	rt.try_move(EVENT_A)
	rt.try_move(START)
	rt.wait_turn()
	var saved: Dictionary = rt.to_dict()
	_check(int(saved["version"]) == 1, "存档带版本号")
	_check(int(saved["player_cell"]) == START, "存档记录坐标")
	_check(int(saved["turn"]) == rt.turn, "存档记录回合（%d）" % int(saved["turn"]))
	_check((saved["consumed"] as Array).size() == 1, "存档记录消耗状态")
	_check(int(saved["seed"]) == SEED, "存档记录种子")

	var json_text: String = JSON.stringify(saved)
	var parsed = JSON.parse_string(json_text)
	_check(parsed is Dictionary, "存档可 JSON 序列化并解析")
	var restored = RUNTIME.create(_duel, 1, SEED, 1)
	_check(restored.from_dict(parsed), "同种子同幕可恢复")
	_check(restored.signature() == rt.signature(), "恢复后状态指纹一致")
	_check(restored.is_consumed(EVENT_A), "恢复后事件格仍是已消耗")

	# 恢复后继续输入，与未中断路径一致（序列保持四邻可达）。
	for cell in [EVENT_A, START, PATH_UP, START]:
		_check(bool(rt.try_move(int(cell))["ok"]), "续跑移动 %d 合法" % int(cell))
		restored.try_move(int(cell))
	_check(restored.signature() == rt.signature(), "恢复后继续移动与未中断结果一致")
	var revisit: Dictionary = restored.try_move(EVENT_A)
	_check(String(revisit["settled"].get("kind", "")) == "revisit", "恢复后回访仍不结算")

	# 拒绝不匹配的存档。
	var other = RUNTIME.create(_duel, 1, SEED + 1, 1)
	_check(not other.from_dict(saved), "种子不匹配的存档被拒绝")
	var bad_version: Dictionary = saved.duplicate(true)
	bad_version["version"] = 99
	_check(not RUNTIME.create(_duel, 1, SEED, 1).from_dict(bad_version), "版本不符的存档被拒绝")
	var bad_cell: Dictionary = saved.duplicate(true)
	bad_cell["player_cell"] = WALL
	_check(not RUNTIME.create(_duel, 1, SEED, 1).from_dict(bad_cell), "落在墙上的坐标被拒绝")
	var bad_act: Dictionary = saved.duplicate(true)
	bad_act["act"] = 2
	_check(not RUNTIME.create(_duel, 1, SEED, 1).from_dict(bad_act), "幕号不匹配的存档被拒绝")


# ---------------------------------------------------------------------------
# H 正式入口关闭与旧开关
# ---------------------------------------------------------------------------

func _test_entry_gate(cfg) -> void:
	_check(not bool(cfg.map14x9_enabled), "正式入口 map14x9_enabled 默认关闭")
	cfg.map_dev_override = false
	_check(not cfg.map14x9_active(), "无开发标记时正式入口不激活")
	cfg.map_dev_override = true
	_check(cfg.map14x9_active(), "开发／AI 测试入口可提前激活")
	cfg.map_dev_override = false

	# Step 2 任务 6/7：本步不动旧双开关与旧模型入口。
	_check(cfg.has_method("use_grid"), "layout_mode / use_grid() 双开关保留")
	_check(String(cfg.layout_mode) == "legacy", "默认 layout_mode 仍是 legacy")
	_check(not cfg.use_grid(), "默认不走 4×4 扫雷路径")
	_check(cfg.has_method("is_active"), "board_config.is_active() 入口保留")
	_check(_duel.board != null and _duel.board.has_method("generate"),
		"旧 BoardSystem 入口仍可用（未收敛）")
	_check(not cfg.has_method("open_map14x9"), "产品侧没有开放正式入口的接口")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

# 结算流水按格统计，用于证明回访不追加结算。
func _log_count(rt, cell: int) -> int:
	var n := 0
	for entry in rt.settled_log:
		if int(entry["cell"]) == cell:
			n += 1
	return n


# 沿 BFS 最短路径合法移动；途经战斗格时取走挂起节点。
func _walk(rt, target: int) -> bool:
	var path: Array = MAP_GRID.reachable(rt.grid, rt.player_cell, target)
	if path.is_empty():
		return false
	for i in range(1, path.size()):
		var r: Dictionary = rt.try_move(int(path[i]))
		if not bool(r["ok"]):
			return false
		var settled: Dictionary = r["settled"]
		if String(settled.get("kind", "")) == "battle":
			rt.take_pending_battle()
	return rt.player_cell == target


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
