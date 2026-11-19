extends RefCounted

# ============================================================================
# BoardSystem — 分岔路线图（DAG）运行状态（单一路径）
# 2026-11-19：14×9 开放网格已彻底删除，分岔图是唯一地图模式。
#   generate()  → MapBoardBuilder.build_branch() 生成 DAG，BranchRuntime 持有状态
#   legal_targets() / advance_to() → 沿连线选下一层节点（不可回头）
#
# 边界：
# - 只决定「接下来进入哪个 RoomData / 节点」，不写战斗伤害与奖励数值；
# - 掷骰 / 行动点 / 扫雷数字 / 四邻移动概念已删除，移动=沿连线选下一层；
# - 节点进入即消耗，不可回头（由 BranchRuntime 保证）。
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")
const MAP_BUILDER = preload("res://scripts/board/map_board_builder.gd")
const BRANCH_RUNTIME = preload("res://scripts/board/branch_runtime.gd")

var _ctrl
var runtime = null                  # BranchRuntime：分岔路线图唯一运行时（2026-11-19 网格已删）

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
	# 分岔路线图是唯一地图模式（2026-11-19 网格已删）
	var builder = MAP_BUILDER.new(_ctrl)
	var data: Dictionary = builder.build_branch(act, seed_value, total_acts)
	runtime = BRANCH_RUNTIME.new()
	runtime.setup(data)

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
		"cols": int(data.get("cols", 3)), "rows": int(data.get("rows", 15)),
		"branch": true,
	}
	generated = true
	return _validate(data)


func _validate(_data: Dictionary) -> bool:
	# 分岔图结构校验（DAG：BOSS 唯一、战斗节点有房间、层间连通由 generator 保证）
	if boss_ids.size() != 1 or nodes.is_empty():
		return false
	for n in nodes:
		if String(n["type"]) in ["battle", "elite", "boss"] and n.get("room") == null:
			return false
	return true


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func node_count() -> int:
	return nodes.size()


func visited_count() -> int:
	return 0 if runtime == null else int(runtime.consumed.size())


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
	return int(layout.get("rows", 15))   # 路径长度 = 层数


func progress_text() -> String:
	return "本幕进度：%d / %d 层" % [visited_count(), route_length()]


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
	return -1   # 分岔图无数字坐标（节点用 id 定位）


# 相邻可进入格。巡逻占格不可进入；已消耗格可回访（只移动、不结算）。
func legal_targets() -> Array:
	var out: Array = []
	if runtime == null:
		return out
	return runtime.legal_targets()


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
	var res: Dictionary = runtime.advance_to(id)
	if not bool(res.get("ok", false)):
		return {}
	current_id = id
	last_move_revisit = false
	var node: Dictionary = res.get("node", {})
	var t: String = String(node.get("type", ""))
	if t in ["chest", "armory", "shop", "rest", "event"]:
		feedback = "进入%s" % String(node.get("title", t))
	return node


# 原地等待一个地图回合：怪物按预告行动一次。
func wait_here() -> Dictionary:
	return {}   # 分岔图无「原地等待」概念


func set_feedback(text: String) -> void:
	feedback = text


# 从战斗回到地图：走到这里说明当前战斗节点已胜利（战败走局末，不经过这里）。
# 幂等：重复调用只是再展示一次棋盘。收敛时这里被写成空实现，
# 导致所有「战斗结束回地图」的调用都打在空函数上，玩家停在结算界面出不来。
func return_to_board() -> void:
	note_battle_won()
	_ctrl.game_state = _ctrl.FlowState.PLAYING
	_ctrl.in_interroom = false
	_ctrl.hud.set_interroom_enabled(false)
	_ctrl.hud.show_board_screen(self)
