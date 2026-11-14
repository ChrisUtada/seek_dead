extends RefCounted

# ============================================================================
# BoardSystem — 14×9 地图运行状态（单一路径）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §2.2 地图操作、§3.3 巡逻、§3.4 陷阱、§6 Step 2 任务 6（单路径收敛）
#
# 2026-11-14 收敛：本类不再生成 1D3 骨架（board_generator.gd）或 4×4 扫雷灰盒
# （board_grid.gd），只做 14×9 地图的**产品侧门面**，内部委托 MapRuntime：
#   generate()  → MapGrid + MapBoardBuilder 冻结内容，MapRuntime 持有运行时状态
#   legal_targets() / advance_to() → 四邻移动（不再是掷骰步数）
#   wait_here() → 原地等待一个地图回合（怪物按预告行动一次）
#
# 边界：
# - 只决定「接下来进入哪个 RoomData / 节点」，不写战斗伤害与奖励数值；
# - 掷骰 / 行动点 / 扫雷数字概念已删除，移动=点击相邻格；
# - 节点进入即消耗，回访只移动不重复结算（由 MapRuntime 保证）。
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")
const MAP_GRID = preload("res://scripts/board/map_grid.gd")
const MAP_BUILDER = preload("res://scripts/board/map_board_builder.gd")
const MAP_RUNTIME = preload("res://scripts/board/map_runtime.gd")

var _ctrl
var runtime = null                  # MapRuntime：14×9 唯一运行时状态源

var nodes: Array = []
var by_id: Dictionary = {}
var battle_rooms: Array[RoomData] = []
var current_id := ""
var consumed: Dictionary = {}
var dice := 0                       # 兼容字段：14×9 不再掷骰，恒为 0
var last_roll := 0
var feedback := ""                  # 非战斗节点结算反馈（棋盘信息栏展示）
var act := 1
var boss_ids: Array[String] = []
var boss_depth := 0
var generated := false
# 记录层兼容字段（run_journal / run_summary / loadout_system 仍读它们）：
# 收敛后不再代表「骨架模板」，只是这张地图的固定标识。
var shape_id := "map14x9"
var template_id := ""
var layout := {}
var revealed: Dictionary = {}
var defeated: Dictionary = {}
var last_move_revisit := false
var act_summaries: Array[Dictionary] = []


func _init(ctrl) -> void:
	_ctrl = ctrl


func reset() -> void:
	nodes.clear()
	by_id.clear()
	battle_rooms.clear()
	current_id = ""
	consumed.clear()
	dice = 0
	last_roll = 0
	feedback = ""
	act = 1
	boss_ids.clear()
	boss_depth = 0
	generated = false
	shape_id = "map14x9"
	template_id = ""
	layout = {}
	revealed.clear()
	defeated.clear()
	last_move_revisit = false
	runtime = null
	# act_summaries 属于「本局」而不是「本张地图」，换图不清；新局由 clear_summaries() 清空。


# 生成一局 14×9 地图。返回 false 表示结构校验不通过。
# act_override >= 0 时按该幕生成（三幕串联逐幕换图），不修改共享 BoardConfig。
func generate(cfg, act_override: int = -1) -> bool:
	reset()
	act = int(cfg.act) if act_override < 0 else int(act_override)
	var seed_value: int = int(cfg.map_seed) if cfg != null and "map_seed" in cfg else 20261110
	var total_acts: int = int(cfg.acts) if cfg != null else 1
	var builder = MAP_BUILDER.new(_ctrl)
	var data: Dictionary = builder.build(act, seed_value, total_acts)

	runtime = MAP_RUNTIME.new()
	runtime.setup(data, true, _ctrl)   # 产品地图默认启用巡逻与陷阱

	nodes = data["nodes"]
	by_id = data["by_id"]
	battle_rooms.assign(data["battle_rooms"])
	current_id = String(data["start_id"])
	boss_ids.clear()
	boss_ids.append(String(data["boss_id"]))
	boss_depth = 0
	defeated.clear()
	last_move_revisit = false
	# 位置与内容始终公开（§3.4），不存在「未揭示格」。
	revealed.clear()
	for n in nodes:
		revealed[String(n["id"])] = true
	consumed = runtime.consumed
	consumed[current_id] = true
	layout = {
		"cols": MAP_GRID.COLS, "rows": MAP_GRID.ROWS,
		"cam_cols": MAP_RUNTIME.VIEW_COLS, "cam_rows": MAP_RUNTIME.VIEW_ROWS,
		"cell": float(MAP_RUNTIME.TILE_SIZE),
	}
	generated = true
	return _validate(data)


func _validate(data: Dictionary) -> bool:
	var errs: Array = MAP_GRID.validate(data.get("grid", {}))
	for e in errs:
		push_error("MapGrid: %s" % e)
	if not errs.is_empty():
		return false
	if boss_ids.size() != 1 or nodes.is_empty():
		return false
	for n in nodes:
		if NODE.is_battle(String(n["type"])) and n.get("room") == null:
			return false
	return true


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func node_count() -> int:
	return nodes.size()


func visited_count() -> int:
	# 访问口径是「走过的格子数」，不是「结算过的内容数」：回访也计入历史访问。
	return 0 if runtime == null else runtime.visits.size()


func current_node() -> Dictionary:
	return node_by_id(current_id)


func current_depth() -> int:
	var n: Dictionary = current_node()
	return int(n.get("row", 0)) + int(n.get("col", 0))


func current_index() -> int:
	return 0


func node_by_id(id: String) -> Dictionary:
	return by_id.get(id, {})


func node_at_index(i: int) -> Dictionary:
	return nodes[i] if i >= 0 and i < nodes.size() else {}


func is_consumed(id: String) -> bool:
	return consumed.has(id)


func is_revealed(id: String) -> bool:
	return true


func is_defeated(id: String) -> bool:
	return defeated.has(id)


func number_of(_id: String) -> int:
	return 0


func numbers_snapshot() -> Dictionary:
	return {}


func note_battle_won() -> void:
	if current_id != "":
		defeated[current_id] = true


func is_boss_node(node: Dictionary) -> bool:
	return String(node.get("type", "")) == "boss"


func is_boss_id(id: String) -> bool:
	return boss_ids.has(id)


func current_is_boss() -> bool:
	return is_boss_id(current_id)


func is_final_node(node: Dictionary) -> bool:
	return bool(node.get("final", false))


func route_length() -> int:
	return MAP_GRID.CELL_COUNT


func progress_text() -> String:
	return "已探索 %d 格 · 第 %d 回合" % [visited_count(), 0 if runtime == null else runtime.turn]


func act_label() -> String:
	return "ACT %s" % ["I", "II", "III"][clampi(act - 1, 0, 2)]


func clear_summaries() -> void:
	act_summaries.clear()


func summary() -> Dictionary:
	return {
		"act": act,
		"visited": visited_count(),
		"battles": 0 if runtime == null else runtime.battles.size(),
	}


# ---------------------------------------------------------------------------
# 移动（§2.2：点击相邻可行走格 → 移动一格并推进一个地图回合）
# ---------------------------------------------------------------------------

func current_cell() -> int:
	return -1 if runtime == null else runtime.player_cell


# 相邻可进入格。巡逻占格不可进入；已消耗格可回访（只移动、不结算）。
func legal_targets() -> Array:
	var out: Array = []
	if runtime == null:
		return out
	for cid in MAP_GRID.neighbors(runtime.grid, runtime.player_cell):
		if not runtime.patrol_at(int(cid)).is_empty():
			continue
		out.append(node_by_id("m%d" % int(cid)))
	return out


func can_roll() -> bool:
	return false


func has_steps() -> bool:
	return false


func roll_dice() -> int:
	return 0


# 移动到指定相邻节点。返回该节点（含待进入战斗）；非法或战斗接触时返回解析结果。
func advance_to(id: String) -> Dictionary:
	if runtime == null or id == "":
		return {}
	var cell: int = int(String(id).trim_prefix("m"))
	var res: Dictionary = runtime.try_move(cell)
	if String(res.get("reason", "")) == "patrol":
		# 撞上巡逻怪：不移动但进入战斗。
		var contact: Dictionary = res.get("contact", {})
		if not contact.is_empty():
			feedback = "撞上巡逻怪"
			return contact.get("node", {})
		return {}
	if not bool(res.get("ok", false)):
		return {}
	# 门面同步当前位置：棋子、确认层判断、右侧「当前局面」都以 current_id 为准。
	# 漏掉这一步会让玩家移动后「当前位置」仍停在起点，确认层再点进入战斗时
	# 被当成二次移动到同一格（same_cell）直接拒绝。
	current_id = id
	# 回访判定看「该格此前是否已访问过」，覆盖通路 / 战斗格等所有类型。
	last_move_revisit = int(runtime.visits.get(cell, 0)) > 1
	var node: Dictionary = node_by_id(id)
	var settled: Dictionary = res.get("settled", {})
	if String(settled.get("kind", "")) == "battle":
		return settled.get("node", node)
	if String(settled.get("kind", "")) == "settle":
		feedback = String(settled.get("text", ""))
	elif last_move_revisit:
		feedback = "回访：只移动，不重复结算"
	# 巡逻接触优先于节点内容。
	var contact2: Dictionary = res.get("contact", {})
	if not contact2.is_empty():
		return contact2.get("node", node)
	return node


# 原地等待一个地图回合：怪物按预告行动一次。
func wait_here() -> Dictionary:
	if runtime == null:
		return {}
	var res: Dictionary = runtime.wait_turn()
	var contact: Dictionary = res.get("contact", {})
	if not contact.is_empty():
		feedback = "巡逻怪逼近"
		return contact.get("node", {})
	feedback = "等待一回合（第 %d 回合）" % int(res.get("turn", 0))
	return {}


func set_feedback(text: String) -> void:
	feedback = text


func return_to_board() -> void:
	pass
